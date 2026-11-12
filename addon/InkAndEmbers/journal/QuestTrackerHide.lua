-- Own quest tracker, lifecycle and hiding of the foreign trackers (WoW Forever only; option "questTracker", default off).
-- On: the mini note and the dock rest (TodoTracker.suppressed), Blizzard's ObjectiveTrackerFrame and Questie's
-- Questie_BaseFrame are kept hidden. Off: only the suppression we set ourselves is released, then the baseline holds again.
--
-- Hiding follows Questie 12.6.4 on Forever (Modules/QuestieCompat.lua, HideWatchFrame/ShowWatchFrame): once per frame
-- HookScript("OnShow"), inside it Hide() while our flag is set. A frame that is IsProtected() in combat waits for
-- PLAYER_REGEN_ENABLED. Releasing = flag off and one Show() outside combat (only if its owner wanted it shown).
-- Never: Update() (would run Blizzard's layout and taint it), SetParent, UnregisterAllEvents, hooksecurefunc on methods,
-- writing into Blizzard or Questie tables (no Questie.db, no ReloadUI). Foreign frames are only touched through
-- HookScript, Hide, Show and the reads IsProtected/IsShown. In Retail nothing is hooked and no option is shown.
--
-- Blizzard's yellow quest progress lines in the screen centre (UIErrorsFrame, UI_INFO_MESSAGE "Wolf slain: 3/10") are muted
-- while the tracker is on and panel.hideInfo is set (default on): only through Blizzard's own UIErrorsMixin:SetMessageTypeEnabled
-- for the quest progress types (the way EnhanceQoL's Submodules/UIErrors.lua filters), the previous state read with
-- ShouldDisplayMessageType. No SetScript("OnEvent") replacement and no UnregisterEvent on UIErrorsFrame (both would run every
-- message through our code). A type someone else already muted stays theirs; releasing re-enables only the types we muted.
-- (That Blizzard method sets the key in its own BLACK_LISTED_MESSAGE_TYPES; we never write that table ourselves.) It is plain
-- Lua state without protected calls, so it needs no combat wait; it follows the applied tracker state (st.active).
local _, ns = ...

local Journal = ns.Journal
if not Journal then return end

local QTH = {}
Journal.QuestTrackerHide = QTH

-- foreign frames we may hide (global names; looked up at runtime, never created or replaced)
QTH.TARGETS = {
  { id = "blizzard", name = "ObjectiveTrackerFrame" },
  { id = "questie", name = "Questie_BaseFrame", addon = "Questie" },
}
QTH.FIND_EVERY = 1   -- seconds between searches for a frame created late (Questie builds its tracker after login)
QTH.FIND_TRIES = 60  -- give up after this many searches (until the next switch-on or /reload)

QTH.TEXT = ns.Locale.ns("QuestTrackerHide", {
  on = "Quest-Tracker eingeschaltet: Questie- und Blizzard-Tracker sind ausgeblendet, Mini-Zettel und Andocken ruhen.",
  off = "Quest-Tracker ausgeschaltet: Questie- und Blizzard-Tracker sind wieder da.",
  combat = "Wird nach dem Kampf umgeschaltet.",
  retail = "Der Quest-Tracker gibt es nur in WoW Forever.",
  usage = "/chronik quests an|aus - eigenen Quest-Tracker ein-/ausschalten (blendet Questie- und Blizzard-Tracker aus)",
})
local T = QTH.TEXT

local st = { active = false, frames = {}, pending = false, finder = nil, finderTries = 0 }
QTH.state = st
QTH.listeners = {}

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function say(msg)
  if ns.Core and ns.Core.print then ns.Core.print(msg) end
end

local function safe(fn, ...)
  if ns.Core and ns.Core.safe then return ns.Core.safe(fn, ...) end
  return pcall(fn, ...)
end

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

-- only WoW Forever (the client switch of MapSpace; Retail never gets the option, the hooks or the frames)
function QTH.available()
  local ms = Journal.MapSpace
  if not (ms and type(ms.retailClient) == "function") then return false end
  local ok, retail = pcall(ms.retailClient)
  return ok and retail == false
end

-- Settings ---------------------------------------------------------------------------------------------------------------------
-- Account-wide EveNChronicleDB.questTracker.on (default false), kept by the settings layer of journal/model/QuestTrack.lua
-- (loaded before this file, see the .toc): QuestTrack.settings() reads, QuestTrack.set("on", ...) writes.
QTH.DEFAULTS = { on = false }

function QTH.storedOn()
  local QT = Journal.QuestTrack
  if not (QT and type(QT.settings) == "function") then return QTH.DEFAULTS.on end
  local ok, st = pcall(QT.settings)
  local v = ok and type(st) == "table" and rawget(st, "on")
  if type(v) ~= "boolean" then return QTH.DEFAULTS.on end
  return v
end

local function storeOn(on)
  local QT = Journal.QuestTrack
  if not (QT and type(QT.set) == "function") then return false end
  local ok, res = pcall(QT.set, "on", on and true or false)
  return ok and res == true
end

-- wanted state: switched on and in WoW Forever
function QTH.wanted()
  return QTH.available() and QTH.storedOn() == true
end

-- applied state: true while the foreign trackers are suppressed and the mini note rests (TodoTracker.suppressed)
function QTH.active()
  return st.active == true
end

-- Foreign frames -----------------------------------------------------------------------------------------------------------------

local function frameOf(e)
  local f = rawget(_G, e.name)
  if type(f) ~= "table" or isSecret(f) then return nil end
  return f
end

local function protected(f)
  if type(f.IsProtected) ~= "function" then return false end
  local ok, v = pcall(f.IsProtected, f)
  return ok and v == true
end

local function shown(f)
  if type(f.IsShown) ~= "function" then return false end
  local ok, v = pcall(f.IsShown, f)
  return ok and v == true
end

local events -- own event frame for the after-combat retry (created on first need, never in Retail)

local function waitForCombatEnd()
  if not events then
    if type(CreateFrame) ~= "function" then return end
    events = CreateFrame("Frame")
    events:SetScript("OnEvent", function()
      events:UnregisterEvent("PLAYER_REGEN_ENABLED")
      safe(QTH.apply)
    end)
  end
  pcall(events.RegisterEvent, events, "PLAYER_REGEN_ENABLED")
end
QTH.waitForCombatEnd = waitForCombatEnd

-- One frame towards the current state. Hiding: Hide() now, unless the frame is protected in combat (then after combat).
-- Releasing: only frames we hold, one Show() outside combat, and only if the owner wanted it shown meanwhile.
local function applyFrame(e)
  local rec = st.frames[e.id]
  local f = frameOf(e)
  if not (rec and f and rec.frame == f) then return end
  if st.active then
    if inCombat() and protected(f) then
      rec.deferred = true
      waitForCombatEnd()
      return
    end
    rec.deferred = false
    if not rec.held then
      rec.held = true
      rec.ownerShown = shown(f) -- the owner had it shown when we took over
    end
    if shown(f) then
      rec.ownerShown = true
      rec.hiding = true -- our own Hide: the OnHide hook must not take it for the owner's
      pcall(f.Hide, f)
      rec.hiding = false
    end
  elseif rec.held then
    if inCombat() then
      rec.deferred = true
      waitForCombatEnd()
      return
    end
    rec.held, rec.deferred = false, false
    local again = rec.ownerShown
    rec.ownerShown = nil
    if again then pcall(f.Show, f) end
  end
end

-- the OnShow hook: the owner just showed its frame; while we suppress, it goes again (or after combat, when protected)
local function onShow(e)
  if not st.active then return end
  local rec = st.frames[e.id]
  if rec then rec.ownerShown = true end
  applyFrame(e)
end

-- the OnHide hook: the owner hid its frame itself (e.g. Questie with no tracked quests), so releasing must not show it again.
-- Not our own Hide (rec.hiding) and not a hidden parent (IsShown still true then). An owner Hide on a frame we already hid
-- fires no OnHide; that case is invisible without hooking the method, which we never do.
local function onHide(e)
  local rec = st.frames[e.id]
  if not rec or rec.hiding then return end
  if not shown(rec.frame) then rec.ownerShown = false end
end

-- Sets the hooks once per frame object (for the session). Returns true if the frame exists and is hooked.
local function hookFrame(e)
  local f = frameOf(e)
  if not f then return false end
  local rec = st.frames[e.id]
  if rec and rec.frame == f then return true end
  if type(f.HookScript) ~= "function" then return false end
  local ok = pcall(f.HookScript, f, "OnShow", function() safe(onShow, e) end)
  if not ok then return false end
  st.frames[e.id] = { frame = f, held = false }
  pcall(f.HookScript, f, "OnHide", function() safe(onHide, e) end)
  return true
end

local function stopFinder()
  if st.finder then st.finder:Cancel() end
  st.finder, st.finderTries = nil, 0
end

-- Is the add-on behind a target loaded? Targets without add-on (Blizzard) count as loaded; without the API we keep searching.
local function addonLoaded(e)
  if not e.addon then return true end
  local api = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
  if type(api) ~= "function" then return true end
  local ok, loaded = pcall(api, e.addon)
  if not ok or isSecret(loaded) then return true end
  return loaded == true or loaded == 1
end
QTH.addonLoaded = addonLoaded

-- hooks every target that exists; returns true while one is still missing whose add-on is loaded (Questie not installed or
-- not loaded yet: no search; its ADDON_LOADED starts one)
local function hookAll()
  local missing = false
  for _, e in ipairs(QTH.TARGETS) do
    if not hookFrame(e) and addonLoaded(e) then missing = true end
  end
  return missing
end

-- frames created later (Questie's tracker after its init): search a bounded number of times while active
local function startFinder()
  if st.finder or not (C_Timer and C_Timer.NewTicker) then return end
  st.finderTries = 0
  st.finder = C_Timer.NewTicker(QTH.FIND_EVERY, function()
    st.finderTries = st.finderTries + 1
    if not st.active then stopFinder() return end
    local missing = hookAll()
    for _, e in ipairs(QTH.TARGETS) do applyFrame(e) end
    if not missing or st.finderTries >= QTH.FIND_TRIES then stopFinder() end
  end)
end

-- Blizzard quest progress messages -----------------------------------------------------------------------------------------------
-- The quest progress message types (names as GetGameMessageInfo returns them; Questie's _QuestProgressMessages on Forever,
-- Modules/EventHandler/EventHandler.lua). The id is the client global LE_GAME_<name>. Turn-in, accept and failure messages
-- (ERR_QUEST_COMPLETE_S, ERR_QUEST_ACCEPTED_S, ERR_QUEST_FAILED_S ...) are not progress and stay visible.
QTH.INFO_TYPES = {
  "ERR_QUEST_ADD_KILL_SII", "ERR_QUEST_ADD_ITEM_SII", "ERR_QUEST_ADD_FOUND_SII", "ERR_QUEST_ADD_PLAYER_KILL_SII",
  "ERR_QUEST_OBJECTIVE_COMPLETE_S", "ERR_QUEST_UNKNOWN_COMPLETE",
}
st.muted = {}       -- message type id -> true while we keep it disabled
st.mutedFrame = nil -- the UIErrorsFrame we muted on

local function infoSetting()
  local QT = Journal.QuestTrack
  if not (QT and type(QT.settings) == "function") then return QTH.INFO_DEFAULT end
  local ok, s = pcall(QT.settings)
  local v = ok and type(s) == "table" and type(s.panel) == "table" and s.panel.hideInfo
  if type(v) ~= "boolean" then return QTH.INFO_DEFAULT end
  return v
end
QTH.INFO_DEFAULT = true

-- Blizzard's message frame with the filter methods of UIErrorsMixin, or nil
local function errorsFrame()
  local f = rawget(_G, "UIErrorsFrame")
  if type(f) ~= "table" or isSecret(f) then return nil end
  if type(f.SetMessageTypeEnabled) ~= "function" or type(f.ShouldDisplayMessageType) ~= "function" then return nil end
  return f
end

local function infoTypeId(name)
  local id = rawget(_G, "LE_GAME_" .. name)
  if type(id) ~= "number" or isSecret(id) then return nil end
  return id
end

local function releaseInfo()
  local f = st.mutedFrame
  for id in pairs(st.muted) do
    if f then pcall(f.SetMessageTypeEnabled, f, id, true) end
    st.muted[id] = nil
  end
  st.mutedFrame = nil
end

-- true while at least one quest progress type is muted by us
function QTH.infoMuted()
  return next(st.muted) ~= nil
end

-- wanted: tracker applied (st.active, so only in WoW Forever) and the option on. Otherwise exactly our types are re-enabled.
function QTH.applyInfo()
  local f = errorsFrame()
  local want = st.active and QTH.available() and infoSetting() == true and f ~= nil
  if not want or (st.mutedFrame and st.mutedFrame ~= f) then releaseInfo() end
  if not want then return false end
  for _, name in ipairs(QTH.INFO_TYPES) do
    local id = infoTypeId(name)
    if id and not st.muted[id] then
      -- shown right now? (quest types are not throttled, so this only reads the blacklist; "" never matches a line on screen)
      local ok, display = pcall(f.ShouldDisplayMessageType, f, id, "")
      if ok and not isSecret(display) and display == true and pcall(f.SetMessageTypeEnabled, f, id, false) then
        st.muted[id] = true
        st.mutedFrame = f
      end
    end
  end
  return QTH.infoMuted()
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------------------

local function notify()
  local TT = Journal.TodoTracker
  if TT then
    safe(TT.refresh)
    if type(TT.syncSettings) == "function" then safe(TT.syncSettings) end
  end
  local O = Journal.Options
  if O and type(O.refresh) == "function" then safe(O.refresh) end
  for _, fn in ipairs(QTH.listeners) do safe(fn, st.active) end
end

-- listener for the own quest tracker (E4): fn(active) after every change of the applied state
function QTH.onChange(fn)
  if type(fn) == "function" then QTH.listeners[#QTH.listeners + 1] = fn end
end

-- Brings everything to the wanted state. In combat a change of the applied state waits for PLAYER_REGEN_ENABLED.
function QTH.apply()
  if not QTH.available() then return false end
  local want = QTH.wanted()
  if want ~= st.active then
    if inCombat() then
      st.pending = true
      waitForCombatEnd()
      return st.active
    end
    st.active = want
    st.pending = false
    if want then
      if hookAll() then startFinder() end
    else
      stopFinder()
    end
    for _, e in ipairs(QTH.TARGETS) do applyFrame(e) end
    safe(QTH.applyInfo)
    notify()
    return st.active
  end
  st.pending = false
  if st.active and hookAll() then startFinder() end
  for _, e in ipairs(QTH.TARGETS) do applyFrame(e) end
  safe(QTH.applyInfo)
  return st.active
end

-- switch (options, slash). The choice is saved at once; the applied state follows outside combat.
function QTH.setEnabled(on)
  if not QTH.available() then return false end
  storeOn(on and true or false)
  QTH.apply()
  return on and true or false
end

function QTH.slash(arg)
  if not QTH.available() then
    say(T.retail)
    return false
  end
  local on = ns.Core and ns.Core.onOff and ns.Core.onOff(arg)
  if on == nil then
    say(T.usage)
    return false
  end
  QTH.setEnabled(on)
  if QTH.active() ~= on then say(T.combat)
  elseif on then say(T.on)
  else say(T.off) end
  return on
end

-- the option follows at once (QuestTrack.set notifies "settings" with the key)
if Journal.QuestTrack and type(Journal.QuestTrack.onChange) == "function" then
  Journal.QuestTrack.onChange(function(reason, key)
    if reason == "settings" and key == "panel.hideInfo" and QTH.available() then safe(QTH.applyInfo) end
  end)
end

if ns.Core and ns.Core.on then
  ns.Core.on("PLAYER_ENTERING_WORLD", function()
    if QTH.available() then safe(QTH.apply) end
  end)
  ns.Core.on("ADDON_LOADED", function(_, name)
    if not (st.active and QTH.available()) then return end
    for _, e in ipairs(QTH.TARGETS) do
      if e.addon == name or name == "Blizzard_ObjectiveTracker" then
        safe(QTH.apply)
        return
      end
    end
  end)
end
