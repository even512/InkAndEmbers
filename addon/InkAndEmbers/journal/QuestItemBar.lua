-- Quest item bar of the own quest tracker (change "quest-tracker", E4 after the design template, D10; WoW Forever only). A small, movable
-- bar (own edit-mode entry "questbar", place saved per layout) that shows the quest item buttons of the quests whose objective or
-- turn-in place lies in the current zone.
--
-- The buttons are the secure buttons of journal/QuestItemButtons.lua (QIB). They hang on QIB's own holder (a plain frame covering
-- UIParent) and are placed by measuring this bar (QIB.acquire(questID, bar, { scaled = true, dx, dy })): the bar itself is a plain
-- frame without secure children and without secure anchors, so moving or hiding it never blocks. Rebuilding the bar (new set of
-- quests, other size, other place) happens only OUTSIDE combat; in combat only counts/cooldowns/range change in place (QIB.update)
-- and the rebuild is noted for PLAYER_REGEN_ENABLED (QIB.onRelayout). The bar is never anchored to a font string.
--
-- PUBLIC API: QIBar.wanted() -> bool, QIBar.list() -> { record, ... } (the quests of the bar, at most QIBar.MAX), QIBar.refresh()
--   -> bool (false = noted for after combat), QIBar.place() (follow the edit-mode holder), QIBar.hide(), QIBar.status() -> table.
local _, ns = ...

local Journal = ns.Journal
if not Journal then return end
local Theme = Journal.Theme

local QIBar = {}
Journal.QuestItemBar = QIBar

QIBar.NAME = "EveNChronicleQuestItemBar"
QIBar.SIZE = 30
QIBar.GAP = 4
QIBar.PAD = 5
QIBar.MAX = 8
QIBar.EDIT_SLOTS = 4 -- empty slots shown in edit mode (the edit-mode holder has this size)
QIBar.DEFAULT_POS = { point = "BOTTOM", x = 0, y = 236 }
QIBar.COLORS = { bg = { 0.024, 0.031, 0.047, 0.72 }, edge = { 0.91, 0.78, 0.48, 0.42 }, slot = { 0, 0, 0, 0.45 } }

QIBar.TEXT = ns.Locale.ns("QuestItemBar", {
  title = "Quest-Gegenstände",
  editHint = "Quest-Gegenstände der aktuellen Zone",
})

local st = { frame = nil, bound = {}, pending = false, editing = false, slots = {}, sig = nil, installed = false, near = {} }
QIBar.state = st

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return ok and not isSecret(v) and v == true
end

local function QT() return Journal.QuestTrack end
local function QIB() return Journal.QuestItemButtons end
local function Tracker() return Journal.QuestTracker end

local function safe(fn, ...)
  if ns.Core and ns.Core.safe then return ns.Core.safe(fn, ...) end
  return pcall(fn, ...)
end

-- the bar exists while the own tracker is active (QuestTracker.active) and its switch panel.itemBar is on
function QIBar.wanted()
  local Tr, Q = Tracker(), QT()
  if not (Tr and type(Tr.active) == "function" and Tr.active()) then return false end
  local ok, s = pcall(Q.settings)
  return ok and type(s) == "table" and s.panel and s.panel.itemBar == true
end

-- Option panel.itemBarNear (default on): a quest item shows only while the player is "near" its quest place: within NEAR_YD yards of
-- the nearest objective point (turn-in place for a ready quest; QuestTrack keeps rec.dist = metres to that point, updated by its 1 s
-- ticker, which also asks for a redraw = QIBar.refresh). Hysteresis: it appears at <= NEAR_YD and goes only beyond NEAR_YD + HYST_YD,
-- so the border does not flicker. Without a distance (no data) the old rule holds: shown while the quest lies in the current zone
-- (better too often than never). A ready quest only has an item here if the game says it is needed for the turn-in (QuestTrack.itemOf).
-- In combat the last state is kept (and the bar is frozen anyway, see refresh).
QIBar.NEAR_YD, QIBar.HYST_YD = 140, 35

local function nearOn()
  local Q = QT()
  local ok, s = pcall(Q.settings)
  return not (ok and type(s) == "table" and s.panel and s.panel.itemBarNear == false)
end

-- true = in the area | false = outside | nil = no distance known
local function inArea(rec)
  local d = rec.dist
  if type(d) ~= "number" or d ~= d or isSecret(d) then return nil end
  local G = Journal.Geo
  local yd = d / ((G and G.YARD_M) or 0.9144)
  local id = rec.questID
  local was = st.near[id]
  if inCombat() and was ~= nil then return was end
  local now
  if yd <= QIBar.NEAR_YD then now = true
  elseif yd > QIBar.NEAR_YD + QIBar.HYST_YD then now = false
  else now = was == true end
  if not inCombat() then st.near[id] = now end
  return now
end

-- quests with a special item whose place (objective, turn-in for ready quests) lies in the current zone, or - option "near" - within
-- reach of the objective point (see above); the focus quest first, then by distance. Hidden quests are left out.
function QIBar.list()
  local Q = QT()
  if not (Q and type(Q.records) == "function") then return {} end
  local cur = type(Q.currentZone) == "function" and Q.currentZone() or nil
  local focus = type(Q.focus) == "function" and Q.focus() or nil
  local near = nearOn()
  local out, seen = {}, {}
  for _, rec in ipairs(Q.records() or {}) do
    if type(rec) == "table" and rec.item and not Q.isHidden(rec.questID) then
      seen[rec.questID] = true
      local show
      local a -- (not "near and inArea() or nil": a false would turn into nil)
      if near then a = inArea(rec) end
      if a ~= nil then show = a else show = cur ~= nil and rec.zone == cur end
      if show then out[#out + 1] = rec end
    end
  end
  if not inCombat() then
    for id in pairs(st.near) do
      if not seen[id] then st.near[id] = nil end
    end
  end
  table.sort(out, function(a, b)
    if (a.questID == focus) ~= (b.questID == focus) then return a.questID == focus end
    local da, db = a.dist, b.dist
    if da and db and da ~= db then return da < db end
    if (da ~= nil) ~= (db ~= nil) then return da ~= nil end
    return (a.ord or 0) < (b.ord or 0)
  end)
  for i = #out, QIBar.MAX + 1, -1 do out[i] = nil end
  return out
end

local function colorTex(t, c)
  t:SetColorTexture(c[1], c[2], c[3], c[4])
end

local function build()
  if st.frame then return st.frame end
  local f = CreateFrame("Frame", QIBar.NAME, UIParent)
  f:SetSize(QIBar.PAD * 2 + QIBar.SIZE, QIBar.PAD * 2 + QIBar.SIZE)
  f:SetFrameStrata("MEDIUM")
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  if f.SetDontSavePosition then f:SetDontSavePosition(true) end
  f:EnableMouse(false)
  -- rounded dark plate with a thin gold edge (white helper textures of the journal, tinted)
  if Theme and Theme.roundRect then
    f.edge = Theme.roundRect(f, { 1, 1, 1 }, 1, 6, "BACKGROUND", Theme.TEX and Theme.TEX.ring)
    f.edge.color(QIBar.COLORS.edge, QIBar.COLORS.edge[4])
    f.plate = Theme.roundRect(f, { 1, 1, 1 }, 1, 6, "BACKGROUND")
    f.plate.color(QIBar.COLORS.bg, QIBar.COLORS.bg[4])
  else
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    colorTex(bg, QIBar.COLORS.bg)
  end
  f:Hide()
  st.frame = f
  return f
end

-- slot backgrounds (visual only, children of the bar)
local function slot(i)
  local s = st.slots[i]
  if s then return s end
  local f = st.frame
  s = f:CreateTexture(nil, "BORDER")
  s:SetSize(QIBar.SIZE, QIBar.SIZE)
  colorTex(s, QIBar.COLORS.slot)
  st.slots[i] = s
  return s
end

local function sizeFor(n)
  n = math.max(1, n)
  return QIBar.PAD * 2 + n * QIBar.SIZE + (n - 1) * QIBar.GAP, QIBar.PAD * 2 + QIBar.SIZE
end

-- follow the edit-mode holder (or the default place); the buttons follow at the next layout outside combat
function QIBar.place()
  local f = st.frame
  if not f then return false end
  local hud = QIBar.hud
  local placed = false
  if hud and type(hud.place) == "function" then
    local ok, r = pcall(hud.place, f)
    placed = ok and r == true
  end
  if not placed then
    local p = QIBar.DEFAULT_POS
    if f:GetParent() ~= UIParent and f.SetParent then f:SetParent(UIParent) end
    f:ClearAllPoints()
    f:SetPoint(p.point, UIParent, p.point, p.x, p.y)
  end
  local B = QIB()
  if B and not inCombat() then B.layout() end
  return true
end

local function releaseAll()
  local B = QIB()
  for id in pairs(st.bound) do
    if B then B.release(id) end
  end
  st.bound = {}
end

-- hide the bar and give its buttons back (outside combat; in combat noted)
function QIBar.hide()
  local B = QIB()
  if inCombat() then
    -- gone from sight at once (holder alpha 0, allowed in combat); the buttons stay bound, their attributes are cleared after
    -- combat (pending -> refresh -> release)
    st.pending = true
    if B and next(st.bound) ~= nil then B.setAlpha(0) end
    if st.frame then st.frame:SetAlpha(0) end
    return false
  end
  releaseAll()
  if B then B.setAlpha(1) end
  if st.frame then
    st.frame:Hide()
    st.frame:SetAlpha(1)
  end
  st.sig = nil
  return true
end

function QIBar.refresh()
  local B = QIB()
  if not B then return false end
  if inCombat() then
    -- frozen: no new buttons, no other size or place; counts and cooldowns change in place. Switched off: only out of sight.
    st.pending = true
    if not QIBar.wanted() then
      QIBar.hide()
    else
      B.update()
    end
    return false
  end
  st.pending = false
  if not QIBar.wanted() then
    QIBar.hide()
    return true
  end
  local f = build()
  local list = QIBar.list()
  local editing = st.editing
  local n = #list
  local slots = math.max(n, editing and QIBar.EDIT_SLOTS or 0)
  if slots == 0 then
    QIBar.hide()
    return true
  end
  local w, h = sizeFor(slots)
  f:SetSize(w, h)
  for i = 1, math.max(slots, #st.slots) do
    local s = (i <= slots) and slot(i) or st.slots[i]
    if s then
      s:ClearAllPoints()
      s:SetPoint("TOPLEFT", f, "TOPLEFT", QIBar.PAD + (i - 1) * (QIBar.SIZE + QIBar.GAP), -QIBar.PAD)
      s:SetShown(i <= slots)
    end
  end
  f:SetAlpha(1)
  f:Show()
  B.setAlpha(1)
  QIBar.place()
  local keep = {}
  for i, rec in ipairs(list) do
    local dx = QIBar.PAD + i * QIBar.SIZE + (i - 1) * QIBar.GAP
    local b = B.acquire(rec.questID, f, { size = QIBar.SIZE, dx = dx, dy = -QIBar.PAD, scaled = true })
    if b then keep[rec.questID] = true end
  end
  for id in pairs(st.bound) do
    if not keep[id] then B.release(id) end
  end
  st.bound = keep
  return true
end

function QIBar.setEditing(on)
  st.editing = on == true
  safe(QIBar.refresh)
end

function QIBar.status()
  local n = 0
  for _ in pairs(st.bound) do n = n + 1 end
  return { shown = st.frame ~= nil and st.frame:IsShown() == true, bound = n, pending = st.pending, editing = st.editing }
end

-- Forever only (QuestTrack.available): after combat the noted rebuild runs; QIB tells when its own noted work is done
function QIBar.install()
  if st.installed then return true end
  local Q, B = QT(), QIB()
  if not (Q and Q.available and Q.available() and B) then return false end
  st.installed = true
  B.onRelayout(function()
    if st.pending or QIBar.wanted() then safe(QIBar.refresh) end
  end)
  if ns.Core and ns.Core.on then
    ns.Core.on("PLAYER_REGEN_ENABLED", function()
      if st.pending then safe(QIBar.refresh) end
    end)
  end
  return true
end

QIBar.install()
