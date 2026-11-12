-- Bridge to the third-party addon Spoken (Spoken_Quests): reads quest texts aloud with its voice recordings. The only
-- module that knows Spoken; the page just calls available() / has() / toggle() / isPlaying().
-- No official interface: it uses the global VoiceOver table of Spoken_Quests 3.6.0 (Player:PlayNow/Contains/Remove,
-- DataModules:PrepareSound/GetQuestLogQuestGiverTypeAndID/GetObjectName, Enums, Utils:MakeGUID). Every access is
-- pcall'd and type-checked; if anything is missing or throws, Spoken counts as unavailable.
-- event: 1 = accept/quest text, 2 = progress, 3 = complete
local _, ns = ...

local Journal = ns.Journal
if not Journal then return end

local Spoken = {}
Journal.Spoken = Spoken

Spoken.ACCEPT, Spoken.PROGRESS, Spoken.COMPLETE = 1, 2, 3
Spoken.TEX_PLAY = "Interface\\AddOns\\Spoken_Quests\\Textures\\QuestLogPlayButton"
Spoken.TEX_STOP = "Interface\\AddOns\\Spoken_Quests\\Textures\\QuestLogStopButton"
Spoken.ORIGIN = "InkAndEmbers"

local EVENT_NAME = { "QuestAccept", "QuestProgress", "QuestComplete" } -- Spoken's Enums.SoundEvent
local CACHE_MAX = 600
local TEXT_MAX = 160
local NEG_TTL = 20 -- seconds a "no recording" answer counts; a found recording stays until reset()

-- pos[key] = true (recording found, kept); neg[key] = GetTime() until which the "none" holds. A "none" is never kept for
-- good: Spoken loads its voice packs (LoadOnDemand, one per frame, from ~1 s after login), and a question asked before
-- that would otherwise stay "none" for the whole session.
local pos, neg, cacheN = {}, {}, 0
local playing = {}

local function global(name)
  if type(_G) ~= "table" then return nil end
  local ok, v = pcall(rawget, _G, name)
  if ok and type(v) == "table" then return v end
  return nil
end

local function field(t, name)
  if type(t) ~= "table" then return nil end
  local ok, v = pcall(function() return t[name] end)
  if ok then return v end
  return nil
end

local function method(t, name)
  local f = field(t, name)
  if type(f) == "function" then return f end
  return nil
end

local function isEvent(event)
  return type(event) == "number" and (event == 1 or event == 2 or event == 3)
end

local function isId(id)
  return type(id) == "number" and id == id and id > 0 and id < 2 ^ 31 and id == math.floor(id)
end

local function keyOf(questID, event) return questID * 4 + event end

local function now()
  if type(GetTime) ~= "function" then return nil end
  local ok, t = pcall(GetTime)
  if ok and type(t) == "number" then return t end
  return nil
end

local hooked = false
local ensureHooks -- defined below env()

local function env()
  local S, VO = global("Spoken"), global("VoiceOver")
  if not (S and VO) then return nil end
  if not hooked then ensureHooks(S) end
  local compat = method(S, "IsCompatible")
  if not compat then return nil end
  local ok, res = pcall(compat, S, 1)
  if not (ok and res) then return nil end
  local P, DM = field(VO, "Player"), field(VO, "DataModules")
  if type(P) ~= "table" or type(DM) ~= "table" then return nil end
  if not (method(P, "PlayNow") and method(P, "Contains") and method(P, "Remove") and method(DM, "PrepareSound")) then return nil end
  return { VO = VO, P = P, DM = DM }
end

-- Spoken's voice packs still loading? Spoken itself asks the same flag (Addon.dataModulesPending, VoiceOver.lua:627-661)
-- before it plays anything. Then every "none" is only provisional and is not cached at all.
local function packsPending(e)
  local addon = field(e.VO, "Addon")
  return type(addon) == "table" and field(addon, "dataModulesPending") and true or false
end

function Spoken.available() return env() ~= nil end

-- soundData as in Spoken's QuestOverlayUI:BindPlayButton; without a giver in the data pack still with questID.
-- Cut to TEXT_MAX bytes without splitting a UTF-8 character.
local function cut(s)
  if #s <= TEXT_MAX then return s end
  local n = TEXT_MAX
  while n > 0 do
    local b = string.byte(s, n + 1)
    if not b or b < 128 or b >= 192 then break end
    n = n - 1
  end
  return string.sub(s, 1, n)
end

local function build(e, questID, event, title, giver)
  local VO, DM = e.VO, e.DM
  local enum = field(field(VO, "Enums"), "SoundEvent")
  local ev = field(enum, EVENT_NAME[event])
  if type(ev) ~= "number" then ev = event end
  local data = { event = ev, questID = questID, origin = Spoken.ORIGIN }
  if type(title) == "string" and title ~= "" then data.title = cut(title) end
  local gtype, gid
  local look = method(DM, "GetQuestLogQuestGiverTypeAndID")
  if look then
    local ok, t, i = pcall(look, DM, questID)
    if ok and type(t) == "number" and type(i) == "number" then gtype, gid = t, i end
  end
  local name
  if gid then
    local get = method(DM, "GetObjectName")
    if get then
      local ok, n = pcall(get, DM, gtype, gid)
      if ok and type(n) == "string" and n ~= "" then name = n end
    end
  end
  if not name and type(giver) == "string" and giver ~= "" then name = cut(giver) end
  data.name = name or "Unknown Name"
  if gid then
    local guid = field(VO, "Enums")
    guid = field(guid, "GUID")
    local can, isCreature = method(guid, "CanHaveID"), method(guid, "IsCreature")
    local utils = field(VO, "Utils")
    local make = method(utils, "MakeGUID")
    if can and make then
      local ok, can1 = pcall(can, guid, gtype)
      if ok and can1 then
        local ok2, g = pcall(make, utils, gtype, gid)
        if ok2 and type(g) == "string" then data.unitGUID = g end
      end
    end
    if isCreature then
      local ok, c = pcall(isCreature, guid, gtype)
      data.unitIsObjectOrItem = ok and not c or false
    else
      data.unitIsObjectOrItem = true
    end
  end
  return data
end

function Spoken.reset()
  pos, neg, cacheN = {}, {}, 0
end

-- Ask the tracker (if any) to redraw so that buttons grey-out from before the packs were loaded become active.
local function redrawTracker()
  local QT = Journal.QuestTracker
  local f = method(QT, "request")
  if f then pcall(f) end
end

local function onPacksChanged(redraw)
  Spoken.reset()
  if redraw then redrawTracker() end
end

ensureHooks = function(S)
  if hooked then return end
  local reg = method(S or global("Spoken"), "RegisterCallback")
  if not reg then return end
  hooked = true
  local target = S or global("Spoken")
  pcall(reg, target, "VOICE_PACKS_LOADED", function() onPacksChanged(true) end)
  pcall(reg, target, "PART_SWITCHED", function(part)
    if part == nil or part == "quests" then onPacksChanged(true) end
  end)
end

-- A Spoken data pack (addon folder "Spoken...") finished loading: earlier "none" answers may be stale now.
do
  if type(CreateFrame) == "function" then
    local ok, f = pcall(CreateFrame, "Frame")
    if ok and type(f) == "table" and type(f.RegisterEvent) == "function" and type(f.SetScript) == "function" then
      pcall(f.RegisterEvent, f, "ADDON_LOADED")
      pcall(f.RegisterEvent, f, "PLAYER_LOGIN")
      pcall(f.SetScript, f, "OnEvent", function(_, event, name)
        if event == "ADDON_LOADED" then
          if type(name) == "string" and string.sub(name, 1, 6) == "Spoken" then
            onPacksChanged(false)
            ensureHooks(nil)
          end
        else
          ensureHooks(nil)
        end
      end)
    end
  end
end

function Spoken.has(questID, event)
  if not (isId(questID) and isEvent(event)) then return false end
  local e = env()
  if not e then return false end
  local key = keyOf(questID, event)
  if pos[key] then return true end
  local t = now()
  local until_ = neg[key]
  if until_ and t and t < until_ then return false end
  -- Same minimal data as Spoken's own Play button and Questie's tracker (event + questID): PrepareSound writes into it
  local ok, res = pcall(function()
    local ev = field(field(e.VO, "Enums"), "SoundEvent")
    ev = field(ev, EVENT_NAME[event])
    if type(ev) ~= "number" then ev = event end
    return e.DM:PrepareSound({ event = ev, questID = questID })
  end)
  local found = ok and res and true or false
  if found then
    if cacheN >= CACHE_MAX then pos, neg, cacheN = {}, {}, 0 end
    pos[key] = true
    neg[key] = nil
    cacheN = cacheN + 1
  elseif t and not packsPending(e) then
    if cacheN >= CACHE_MAX then pos, neg, cacheN = {}, {}, 0 end
    neg[key] = t + NEG_TTL
    cacheN = cacheN + 1
  end
  return found
end

function Spoken.isPlaying(questID, event)
  if not (isId(questID) and isEvent(event)) then return false end
  local key = keyOf(questID, event)
  local data = playing[key]
  if not data then return false end
  local e = env()
  local ok, res = false, nil
  if e then ok, res = pcall(e.P.Contains, e.P, data) end
  if ok and res then return true end
  playing[key] = nil
  return false
end

local function notify(onState, state)
  if type(onState) == "function" then pcall(onState, state) end
end

function Spoken.toggle(questID, event, title, onState, giver)
  if not (isId(questID) and isEvent(event)) then return nil end
  local e = env()
  if not e then return nil end
  local key = keyOf(questID, event)
  local cur = playing[key]
  if cur and not Spoken.isPlaying(questID, event) then cur = nil end
  if cur then
    playing[key] = nil -- clear first: a callback from the old line then changes nothing
    pcall(e.P.Remove, e.P, cur)
    notify(onState, false)
    return "stop"
  end
  if not Spoken.has(questID, event) then return nil end
  local ok, data = pcall(build, e, questID, event, title, giver)
  if not (ok and type(data) == "table") then return nil end
  data.stopCallback = function()
    if playing[key] == data then
      playing[key] = nil
      notify(onState, false)
    end
  end
  playing[key] = data
  local ok2, queued = pcall(e.P.PlayNow, e.P, data)
  if not (ok2 and queued) then
    if playing[key] == data then playing[key] = nil end
    return nil
  end
  notify(onState, true)
  return "play"
end
