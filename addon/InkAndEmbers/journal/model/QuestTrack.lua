-- Quest tracker data model (change "quest-tracker", step E1; WoW Forever only). Pure logic: no window, no hooks on foreign frames,
-- no actions. The window (E4), the hiding of the foreign trackers (E2) and the actions (E3) build on this module.
--
-- What it does: reads the quest log (bundled, one read per frame after any of the events below), builds one record per quest,
-- finds a place for each quest (QuestieDB first, then the game's own quest map data), measures the distance, and arranges the
-- records into groups for the window (selection mode x order x "turn in" handling). Settings live account-wide in
-- EveNChronicleDB.questTracker, the per-character parts (hidden quests, folded zones) in char.questTrackerState.
--
-- PUBLIC API (all functions are safe to call at any time; none of them raises an error)
--   QuestTrack.available()          -> bool   Forever client (never in Retail: nothing is read, nothing is registered)
--   QuestTrack.enabled()            -> bool   available() and settings().on (the switch EveNChronicleDB.questTracker.on, default false)
--   QuestTrack.settings()           -> table  validated COPY: { on, mode, order, done, locked, look = { marker, doneObj, dist },
--                                             collapsed = { todo, quests, turnin }, pos = { point, x, y } | nil, size = { w, h } | nil }
--   QuestTrack.set(key, value)      -> bool   keys: on, mode, order, done, locked, pos, size, look.marker, look.doneObj, look.dist,
--                                             collapsed.todo / collapsed.quests / collapsed.turnin. false = invalid (nothing changed).
--                                             pos/size accept nil (back to default). "on" = true is refused in Retail.
--   QuestTrack.resetPlace()         -> nil    clears pos and size (E4: "reset position")
--   QuestTrack.toggleSection(name)  -> bool   flips collapsed.<name> ("todo" | "quests" | "turnin")
--   QuestTrack.build()              -> view   the arranged result (see below); cheap, call it on every onChange
--   QuestTrack.records()            -> list   the raw records of the last read, in quest log order
--   QuestTrack.request()            -> nil    bundled re-read (C_Timer.After(0)); ignored while not enabled()
--   QuestTrack.read()               -> list   immediate re-read (tests, first fill); works whenever available()
--   QuestTrack.tick()               -> bool   one distance update; true = something changed (the 1 s ticker calls this)
--   QuestTrack.setActive(bool)      -> nil    start/stop the 1 s distance ticker (E4: true while the window is visible)
--   QuestTrack.onChange(fn)         -> bool   fn(reason, detail) after a change; reason = "log" | "loc" | "dist" | "settings" | "state"
--   QuestTrack.hide(id) / unhide(id) / isHidden(id) / hiddenCount() / clearHidden()   own hide list (per character)
--   QuestTrack.toggleZone(key)      -> bool   folds/unfolds a zone group (state per character, key = group.key)
--   QuestTrack.status()             -> table  diagnostics: counts per location source, QuestieDB state, cache size
--   QuestTrack.difficulty(level, playerLevel) -> token ("red"|"orange"|"yellow"|"green"|"gray"), { r, g, b }
--   E4 (window after the design template, additive):
--   settings() also holds filter = { done, group }, focus = { show, dist, bar, giver, rewards }, panel = { hover, delay (ms 0-2000),
--     scale (0.8-1.4), notify, todo ("top"|"bottom"), itemBar, itemBarNear (quest items only near the objective), pinned }, look.objs / look.icons; set("group.key", v) for all of them.
--     Defaults after the template: done "inZone", look.doneObj "strike" (finished objectives stay, pale), look.dist false.
--   order "level" = one flat list by level (then distance). build() also returns readyCount, total, maxQuests, filtered (count
--     removed by filter.done/filter.group) and focus (the focus record while focus.show; it stays in the groups too, the row is marked).
--   QuestTrack.focus() / setFocus(id|nil) / toggleFocus(id)    focus quest (char.questTrackerState.focus)
--   QuestTrack.isFolded(id) / toggleQuest(id)                  quest rows folded in the window (char.questTrackerState.folded)
--   QuestTrack.kindOf(objectives) -> "kill"|"collect"|"explore"|"talk" (record.kind), record.group/groupSize (suggestedGroup >= 2,
--     tag "Group" or elite), record.starter (quest giver from QuestieDB startedBy | nil)
--   QuestTrack.rewards(id) -> { xp, money, item = { name, quality, count, texture, itemID }, choice } | nil (readable values only)
--   QuestTrack.facing() -> radians | nil, QuestTrack.bearing(rec) -> radians relative to the facing | nil, QuestTrack.mapName(id)
--
-- RECORD (one per quest): { questID, ord (position in this read), logIndex, title (display-safe), level, elite, diff (token),
--   color = { r, g, b }, header (quest log header text, display-safe | nil), zoneMapID (map of the quest's log zone | nil),
--   zone (map of the quest's PLACE, else of the log zone | nil), objectives = { { text, label, have, need, done, kind } },
--   complete (ready to turn in), watched, loc = { mapID, x, y, src } | nil, dist (meters | nil), item = { itemID, texture,
--   charges } | nil, finisher (turn-in NPC name from QuestieDB | nil), next (bool, set by build()) }
--   loc.src: "qdb" (QuestieDB) | "map" (GetQuestsOnMap of the current map) | "zone" (GetQuestsOnMap of the zone map that really contains the quest: continent point -> GetMapInfoAtPosition)
--            | "waypoint" (GetNextWaypoint). No loc = "place unknown" (never an error).
--   dist without loc is possible: sqrt(GetDistanceSqToQuest) as the last resort. Records without dist sort last.
--
-- VIEW (build()): { mode, order, done, ready (a read has happened), zoneMapID (current zone), zoneName, count (visible quests),
--   hiddenCount, next (the record marked as "next" | nil), groups = { group, ... } }
--   group: { id, kind = "turnin" | "zone" | "header" | "flat", key (state key for toggleZone; nil for turnin/flat),
--            mapID, name (display-safe | nil: the UI supplies "Ohne Zone"/"Abgeben"), current, collapsed, count, quests = { record, ... } }
--   Rules: order "zones" = current zone first (open), other zones folded unless the user unfolded them (remembered per zone),
--   inside a group by distance; order "distance" = one flat list; order "log" = groups = quest log headers in log order.
--   done "group" = ready quests in their own group "turnin" on top; done "inZone" = they stay in their zone group / list, at its END
--   (open quests keep their order).
--   next = the nearest OPEN (not ready) visible quest whose place lies in the current zone (a quest without place counts if its log
--   header is the current zone), exactly one, or nil.
--   Selection: "tracked" = Blizzard watch list, "log" = all quests of the log, "zone" = place in the current zone (a quest without a
--   place only if its log header is the current zone). Hidden quests are removed in every mode.
--
-- Security: every game value goes through num()/str() (secret values and nil are dropped, the record then has no place), all foreign
-- text through Sanitize.display, QuestieDB only through LibQuestieDB (OpenQuestsQDB), in a coroutine with a time budget and never in
-- combat. Nothing is written into foreign tables.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local QuestTrack = {}
Journal.QuestTrack = QuestTrack

local floor, min, max, sqrt, abs = math.floor, math.min, math.max, math.sqrt, math.abs
local sort = table.sort
local match, gsub, lower, sub, find = string.match, string.gsub, string.lower, string.sub, string.find

QuestTrack.MODES = { tracked = true, log = true, zone = true }
QuestTrack.ORDERS = { zones = true, distance = true, log = true, level = true }
QuestTrack.DONE = { group = true, inZone = true }
QuestTrack.MARKERS = { dot = true, level = true }
QuestTrack.DONE_OBJ = { hide = true, strike = true }
QuestTrack.SECTIONS = { todo = true, quests = true, turnin = true }
QuestTrack.TODO_AT = { top = true, bottom = true }
-- E4 (design template, round 3): done "inZone" is the default (D7), finished objectives stay visible, pale with a tick (D6:
-- doneObj "strike"), the row distance is off by default (D4 "Liste"). filter/focus/panel are the switches of D1/D4/D8-D10.
QuestTrack.DEFAULTS = {
  on = false, mode = "tracked", order = "zones", done = "inZone", locked = false,
  look = { marker = "dot", doneObj = "strike", dist = false, objs = true, icons = true },
  collapsed = { todo = false, quests = false, turnin = false },
  filter = { done = false, group = false, zoneOnly = false },
  focus = { show = true, dist = true, bar = true, giver = true, rewards = true },
  panel = { hover = true, delay = 600, scale = 1, gripScale = 1, gripAlpha = 0.4, notify = true, todo = "top", itemBar = true, itemBarNear = true, pinned = false, syncFocus = true,
    bgAlpha = 0.96, fadeWidth = 36, fadeTime = 0.3, fontScale = 1, fontHead = "", fontText = "", panMap = true, hideInfo = true },
}
QuestTrack.GROUP_TAG = 1 -- Enum.QuestTag.Group
QuestTrack.RANGES = { ["panel.delay"] = { 0, 2000 }, ["panel.scale"] = { 0.8, 1.4 }, ["panel.gripScale"] = { 0.7, 1.6 }, ["panel.gripAlpha"] = { 0.1, 1 }, ["panel.bgAlpha"] = { 0.5, 1 },
  ["panel.fadeWidth"] = { 0, 120 }, ["panel.fadeTime"] = { 0, 1 }, ["panel.fontScale"] = { 0.8, 1.5 } }
QuestTrack.POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true, BOTTOMLEFT = true,
  BOTTOM = true, BOTTOMRIGHT = true }
QuestTrack.SIZE = { minW = 160, maxW = 700, minH = 100, maxH = 1000 }
QuestTrack.EVENTS = { "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
  "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "SUPER_TRACKING_CHANGED" }

QuestTrack.LOG_MAX = 300 -- quest log entries read at most
QuestTrack.OBJ_MAX = 12 -- objectives per quest
QuestTrack.TITLE_BYTES = 80
QuestTrack.TEXT_BYTES = 100
QuestTrack.NAME_BYTES = 60
QuestTrack.KEY_BYTES = 64
QuestTrack.POINTS_MAX = 32 -- QuestieDB points kept per quest
QuestTrack.HIDDEN_MAX = 500
QuestTrack.ZONES_MAX = 200
QuestTrack.CACHE_MAX = 400 -- QuestieDB results (per quest)
QuestTrack.STOCK_MAX = 600 -- candidate quest IDs taken from the character's own quest stock per read
QuestTrack.TICK_SEC = 1
QuestTrack.QDB_BUDGET_MS = 4 -- QuestieDB work per frame (debugprofilestop)
QuestTrack.QDB_STEP_TICKS = 40 -- entity lookups per frame at most (the only limit without a clock)
QuestTrack.QDB_COMBAT_WAIT = 2 -- seconds between checks while in combat
QuestTrack.QDB_ENTITY_MAX = 40 -- NPC/object/item lookups per quest
QuestTrack.QDB_DROPPERS_MAX = 12 -- droppers per quest item
QuestTrack.QDB_ERRORS_MAX = 3 -- crashed jobs before QuestieDB is given up until the next loading screen
QuestTrack.NAME_INDEX_MAX = 400 -- zone names per continent

-- ---------------------------------------------------------------- helpers

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function whole(v)
  v = num(v)
  return v and floor(v + 0.5) or nil
end

local function str(v)
  if isSecret(v) or type(v) ~= "string" then return nil end
  return v
end

local function flag(v)
  return not isSecret(v) and v == true
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d
end

local function unit01(v)
  v = num(v)
  if not v or v < 0 or v > 1 then return nil end
  return v
end

local function display(s, max)
  local S_ = ns.Sanitize
  if not (S_ and S_.display) then return nil end
  s = str(s)
  if not s then return nil end
  return S_.display(s, max or QuestTrack.TEXT_BYTES)
end

local function inCombat()
  return type(InCombatLockdown) == "function" and flag(call(InCombatLockdown))
end

local function after(sec, fn)
  if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return false end
  return (pcall(C_Timer.After, sec, fn))
end

local function geo() return Journal.Geo end

local function validKey(k)
  k = str(k)
  if not k or k == "" or #k > QuestTrack.KEY_BYTES then return nil end
  if find(k, "[%c|]") then return nil end
  return k
end

local S = {
  records = {}, byID = {}, ready = false, here = nil, listeners = {}, readPending = false, ticker = nil, active = false,
  mem = {}, memChar = { hidden = {}, zones = {} }, names = {}, nameIndex = {}, trueMap = {}, lastView = nil, installed = false,
  foldedIDs = {}, notOn = {},
  qdb = { cache = {}, cacheN = 0, queue = {}, queued = {}, timer = false, co = nil, zones = nil, state = "idle", reason = nil,
    errors = 0, steps = 0, jobs = 0 },
}
QuestTrack._state = S

-- ---------------------------------------------------------------- Forever switch

-- Retail check directly over MapSpace.retailClient (not Lehrplan.active); without MapSpace the module stays off.
function QuestTrack.available()
  local ms = Journal.MapSpace
  if not (ms and type(ms.retailClient) == "function") then return false end
  return ms.retailClient() ~= true
end

-- ---------------------------------------------------------------- persistence

-- EveNChronicleDB.questTracker (pattern db.ui of Pages.lua); false/nil when the database is not there yet
local function account(create)
  local db = rawget(_G, "EveNChronicleDB")
  if type(db) ~= "table" or isSecret(db) then return nil end
  local t = db.questTracker
  if type(t) ~= "table" or isSecret(t) then
    if not create then return nil end
    t = {}
    db.questTracker = t
  end
  return t
end

-- the switch EveNChronicleDB.questTracker.on (default false); never true in Retail
function QuestTrack.enabled()
  if not QuestTrack.available() then return false end
  local t = account(false) or S.mem
  return type(t.on) == "boolean" and not isSecret(t.on) and t.on == true
end

local nestedValue -- defined with NESTED below

local function pick(v, set, default)
  if type(v) == "string" and not isSecret(v) and set[v] then return v end
  return default
end

local function boolOr(v, default)
  if type(v) == "boolean" and not isSecret(v) then return v end
  return default
end

local function sizeOf(raw)
  if type(raw) ~= "table" or isSecret(raw) then return nil end
  local w, h = num(raw.w), num(raw.h)
  local Z = QuestTrack.SIZE
  if not (w and h) then return nil end
  return min(Z.maxW, max(Z.minW, floor(w))), min(Z.maxH, max(Z.minH, floor(h)))
end

-- nested switches: group -> key -> kind (true = boolean, a set = one of its keys, "range" = number inside QuestTrack.RANGES)
local NESTED = {
  look = { marker = QuestTrack.MARKERS, doneObj = QuestTrack.DONE_OBJ, dist = true, objs = true, icons = true },
  filter = { done = true, group = true, zoneOnly = true },
  focus = { show = true, dist = true, bar = true, giver = true, rewards = true },
  panel = { hover = true, delay = "range", scale = "range", gripScale = "range", gripAlpha = "range", notify = true, todo = QuestTrack.TODO_AT, itemBar = true, itemBarNear = true, pinned = true,
    syncFocus = true, bgAlpha = "range", fadeWidth = "range", fadeTime = "range", fontScale = "range", fontHead = "font", fontText = "font", panMap = true, hideInfo = true },
}
QuestTrack.NESTED = NESTED

local function inRange(group, key, v)
  local r = QuestTrack.RANGES[group .. "." .. key]
  v = num(v)
  if not (r and v) or v < r[1] or v > r[2] then return nil end
  return v
end

-- a font choice: "" (the default) or the name of a font (built-in or registered at LibSharedMedia), at most 80 bytes, no control characters
function QuestTrack.fontName(v)
  if type(v) ~= "string" or isSecret(v) or #v > 80 or find(v, "[%c|]") then return nil end
  return v
end

nestedValue = function(group, key, kind, v)
  local d = QuestTrack.DEFAULTS[group][key]
  if kind == true then return boolOr(v, d) end
  if kind == "range" then return inRange(group, key, v) or d end
  if kind == "font" then return QuestTrack.fontName(v) or d end
  return pick(v, kind, d)
end

function QuestTrack.settings()
  local raw = account(false) or S.mem
  local d = QuestTrack.DEFAULTS
  local out = { collapsed = {} }
  out.on = boolOr(raw.on, d.on) and QuestTrack.available()
  out.mode = pick(raw.mode, QuestTrack.MODES, d.mode)
  out.order = pick(raw.order, QuestTrack.ORDERS, d.order)
  out.done = pick(raw.done, QuestTrack.DONE, d.done)
  out.locked = boolOr(raw.locked, d.locked)
  for group, spec in pairs(NESTED) do
    local src = type(raw[group]) == "table" and not isSecret(raw[group]) and raw[group] or {}
    local t = {}
    for k, kind in pairs(spec) do t[k] = nestedValue(group, k, kind, src[k]) end
    out[group] = t
  end
  local col = type(raw.collapsed) == "table" and not isSecret(raw.collapsed) and raw.collapsed or {}
  for name in pairs(QuestTrack.SECTIONS) do out.collapsed[name] = boolOr(col[name], d.collapsed[name]) end
  local p = raw.pos
  if type(p) == "table" and not isSecret(p) and type(p.point) == "string" and not isSecret(p.point) and QuestTrack.POINTS[p.point]
    and num(p.x) and num(p.y) and abs(p.x) <= 10000 and abs(p.y) <= 10000 then
    out.pos = { point = p.point, x = p.x, y = p.y }
  end
  local w, h = sizeOf(raw.size)
  if w then out.size = { w = w, h = h } end
  return out
end

local function notify(reason, detail)
  local list = S.listeners
  local core = ns.Core
  for i = 1, #list do
    if core and core.safe then core.safe(list[i], reason, detail) else pcall(list[i], reason, detail) end
  end
end

function QuestTrack.onChange(fn)
  if type(fn) ~= "function" then return false end
  for _, f in ipairs(S.listeners) do
    if f == fn then return false end
  end
  S.listeners[#S.listeners + 1] = fn
  return true
end

local function enumSetter(set) return function(v) return type(v) == "string" and not isSecret(v) and set[v] == true end end
local function boolSetter(v) return type(v) == "boolean" and not isSecret(v) end

local SETTERS = {
  on = boolSetter, locked = boolSetter,
  mode = enumSetter(QuestTrack.MODES), order = enumSetter(QuestTrack.ORDERS), done = enumSetter(QuestTrack.DONE),
}

function QuestTrack.set(key, value)
  key = str(key)
  if not key then return false end
  local group, sub1 = match(key, "^(%a+)%.(%a+)$")
  if group and NESTED[group] then
    local kind = NESTED[group][sub1]
    if kind == nil then return false end
    if kind == true then
      if not boolSetter(value) then return false end
    elseif kind == "range" then
      value = inRange(group, sub1, value)
      if value == nil then return false end
    elseif kind == "font" then
      value = QuestTrack.fontName(value)
      if value == nil then return false end
    elseif not enumSetter(kind)(value) then
      return false
    end
    local t = account(true) or S.mem
    if type(t[group]) ~= "table" or isSecret(t[group]) then t[group] = {} end
    t[group][sub1] = value
  elseif group == "collapsed" then
    if not (QuestTrack.SECTIONS[sub1] and boolSetter(value)) then return false end
    local t = account(true) or S.mem
    if type(t.collapsed) ~= "table" or isSecret(t.collapsed) then t.collapsed = {} end
    t.collapsed[sub1] = value
  elseif key == "pos" then
    local t = account(true) or S.mem
    if value == nil then
      t.pos = nil
    else
      if type(value) ~= "table" or isSecret(value) or type(value.point) ~= "string" or isSecret(value.point)
        or not QuestTrack.POINTS[value.point] or not num(value.x) or not num(value.y) or abs(value.x) > 10000 or abs(value.y) > 10000 then
        return false
      end
      t.pos = { point = value.point, x = value.x, y = value.y }
    end
  elseif key == "size" then
    local t = account(true) or S.mem
    if value == nil then
      t.size = nil
    else
      local w, h = sizeOf(value)
      if not w then return false end
      t.size = { w = w, h = h }
    end
  elseif SETTERS[key] then
    if not SETTERS[key](value) then return false end
    if key == "on" and value == true and not QuestTrack.available() then return false end
    local t = account(true) or S.mem
    t[key] = value
  else
    return false
  end
  notify("settings", key)
  if key == "on" and value == true then QuestTrack.request() end
  return true
end

function QuestTrack.resetPlace()
  QuestTrack.set("pos", nil)
  QuestTrack.set("size", nil)
end

function QuestTrack.toggleSection(name)
  if not QuestTrack.SECTIONS[name] then return false end
  return QuestTrack.set("collapsed." .. name, not QuestTrack.settings().collapsed[name])
end

-- char.questTrackerState = { hidden = { [questID] = true }, zones = { [key] = true (folded) | false (unfolded) } }
local function charState(create)
  local Store = ns.Store
  local char = Store and Store.char and Store.char() or nil
  if type(char) ~= "table" or isSecret(char) then return S.memChar end
  local t = char.questTrackerState
  if type(t) ~= "table" or isSecret(t) then
    if not create then return nil end
    t = {}
    char.questTrackerState = t
  end
  if type(t.hidden) ~= "table" or isSecret(t.hidden) then
    if not create then return t end
    t.hidden = {}
  end
  if type(t.zones) ~= "table" or isSecret(t.zones) then
    if not create then return t end
    t.zones = {}
  end
  return t
end

local function hiddenTable(create)
  local t = charState(create)
  if t and type(t.hidden) == "table" and not isSecret(t.hidden) then return t.hidden end
  return nil
end

local function zonesTable(create)
  local t = charState(create)
  if t and type(t.zones) == "table" and not isSecret(t.zones) then return t.zones end
  return nil
end

local function countKeys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function questKey(id)
  id = whole(id)
  if not id or id <= 0 or id > 10000000 then return nil end
  return id
end

function QuestTrack.hide(questID)
  local id = questKey(questID)
  if not id then return false end
  local h = hiddenTable(true)
  if not h then return false end
  if h[id] ~= true and countKeys(h) >= QuestTrack.HIDDEN_MAX then return false end
  h[id] = true
  notify("state", "hidden")
  return true
end

function QuestTrack.unhide(questID)
  local id = questKey(questID)
  local h = hiddenTable(false)
  if not (id and h) or h[id] == nil then return false end
  h[id] = nil
  notify("state", "hidden")
  return true
end

function QuestTrack.isHidden(questID)
  local id = questKey(questID)
  local h = hiddenTable(false)
  return id ~= nil and h ~= nil and h[id] == true
end

function QuestTrack.hiddenCount()
  local h = hiddenTable(false)
  return h and countKeys(h) or 0
end

function QuestTrack.clearHidden()
  local h = hiddenTable(false)
  if not h or next(h) == nil then return false end
  for k in pairs(h) do h[k] = nil end
  notify("state", "hidden")
  return true
end

-- ---------------------------------------------------------------- focus and folded quests (E4, per character)

-- char.questTrackerState.focus = questID (the focus card, D5), .folded = { [questID] = true } (quest rows folded, D6)
function QuestTrack.focus()
  local t = charState(false)
  local id = t and questKey(t.focus) or nil
  return id
end

local function applyFocus(questID)
  local t = charState(true)
  if not t then return false end
  if questID == nil then
    if t.focus == nil then return false end
    t.focus = nil
  else
    local id = questKey(questID)
    if not id then return false end
    t.focus = id
  end
  notify("state", "focus")
  return true
end

-- ---- sync with the game's active quest (super tracking): the focus quest follows C_SuperTrack and the other way round.
-- S.sync = { pending = questID | 0 (push deferred out of combat), own = last id pushed by us (its event is not an outside change),
--            pushes, errors, blocked } ; the result of every push is noted in diag.questTracker.superTrack (action-blocked counter).
S.sync = { pending = nil, own = nil, pushes = 0, errors = 0, blocked = 0, lastPush = nil, lastRead = nil }

local function syncOn()
  return QuestTrack.settings().panel.syncFocus == true
end

-- the active quest of the game: questID or nil (nothing, 0, a secret value or no API)
function QuestTrack.superTracked()
  local ST = rawget(_G, "C_SuperTrack")
  if type(ST) ~= "table" then return nil end
  local v = call(ST.GetSuperTrackedQuestID)
  if v == nil or isSecret(v) then return nil end
  return questKey(v)
end

local function onLog(id)
  local CQ = rawget(_G, "C_QuestLog")
  if type(CQ) ~= "table" then return S.byID[id] ~= nil end
  local idx = num(call(CQ.GetLogIndexForQuestID, id))
  if idx and idx > 0 then return true end
  return call(CQ.IsOnQuest, id) == true
end

local function diagTable()
  local db = ns.Store and ns.Store.db
  if type(db) ~= "table" or isSecret(db) then return nil end
  if type(db.diag) ~= "table" then db.diag = {} end
  if type(db.diag.questTracker) ~= "table" then db.diag.questTracker = {} end
  local d = db.diag.questTracker
  if type(d.superTrack) ~= "table" then d.superTrack = {} end
  return d.superTrack
end

local function blockedTotal()
  local C = ns.Core
  if not (C and type(C.actionSummary) == "function") then return nil end
  local ok, total = pcall(C.actionSummary)
  return ok and num(total) or nil
end

local function doPush(id)
  local ST = rawget(_G, "C_SuperTrack")
  if type(ST) ~= "table" or type(ST.SetSuperTrackedQuestID) ~= "function" then return false end
  if QuestTrack.superTracked() == (id ~= 0 and id or nil) then return true end -- the game already shows it
  local before = blockedTotal()
  S.sync.own = id
  local ok = pcall(ST.SetSuperTrackedQuestID, id)
  local afterN = blockedTotal()
  S.sync.pushes = S.sync.pushes + 1
  if not ok then S.sync.errors = S.sync.errors + 1 end
  local blocked = (before and afterN) and (afterN - before) or 0
  S.sync.blocked = S.sync.blocked + blocked
  S.sync.lastPush = id
  local d = diagTable()
  if d then
    d.pushes, d.errors, d.blocked, d.lastId, d.lastOk = S.sync.pushes, S.sync.errors, S.sync.blocked, id, ok
    d.actionBlockedTotal = afterN
  end
  return ok
end

-- our focus changed -> tell the game (out of combat; in combat the last value is kept and sent after combat)
local function pushFocus(id)
  if not syncOn() then S.sync.pending = nil return end
  id = id or 0
  if inCombat() then
    S.sync.pending = id
    return
  end
  S.sync.pending = nil
  doPush(id)
end

local function flushPush()
  local id = S.sync.pending
  if id == nil then return end
  S.sync.pending = nil
  if syncOn() then doPush(id) end
end

-- the game's active quest changed (event) or is read at login: it becomes the focus when it is in the quest log
local function readSuperTracked()
  if not syncOn() then return false end
  if S.sync.pending ~= nil then return false end -- our own change waits for the end of combat and wins
  local id = QuestTrack.superTracked()
  S.sync.lastRead = id
  if not id then return false end
  if S.sync.own == id then S.sync.own = nil end
  if QuestTrack.focus() == id then return false end
  if not onLog(id) then return false end
  return applyFocus(id)
end
QuestTrack.readSuperTracked = readSuperTracked

function QuestTrack.setFocus(questID)
  local changed = applyFocus(questID)
  if changed then pushFocus(questKey(questID)) end
  return changed
end

function QuestTrack.toggleFocus(questID)
  local id = questKey(questID)
  if not id then return false end
  if QuestTrack.focus() == id then return QuestTrack.setFocus(nil) end
  return QuestTrack.setFocus(id)
end

local function foldedTable(create)
  local t = charState(create)
  if not t then return nil end
  if type(t.folded) ~= "table" or isSecret(t.folded) then
    if not create then return nil end
    t.folded = {}
  end
  return t.folded
end

function QuestTrack.isFolded(questID)
  local id = questKey(questID)
  local f = foldedTable(false)
  return id ~= nil and f ~= nil and f[id] == true
end

function QuestTrack.toggleQuest(questID)
  local id = questKey(questID)
  if not id then return false end
  local f = foldedTable(true)
  if not f then return false end
  if f[id] then
    f[id] = nil
  else
    if countKeys(f) >= QuestTrack.HIDDEN_MAX then return false end
    f[id] = true
  end
  notify("state", "folded")
  return true
end

-- a quest left the log: its fold mark and the focus go with it
local function forgetQuest(questID)
  local id = questKey(questID)
  if not id then return end
  local f = foldedTable(false)
  if f then f[id] = nil end
  local t = charState(false)
  if t and t.focus == id then
    t.focus = nil
    notify("state", "focus")
  end
end

-- fold/unfold a zone group. The effective state is read from the last view (default: only the current zone is open).
function QuestTrack.toggleZone(key)
  key = validKey(key)
  if not key then return false end
  local z = zonesTable(true)
  if not z then return false end
  local effective
  local view = S.lastView
  for _, g in ipairs(view and view.groups or {}) do
    if g.key == key then effective = g.collapsed end
  end
  if effective == nil then effective = z[key] == true end
  if z[key] == nil and countKeys(z) >= QuestTrack.ZONES_MAX then return false end
  z[key] = not effective
  notify("state", "zones")
  return true
end

-- ---------------------------------------------------------------- difficulty color

local COLORS = {
  red = { 1, 0.1, 0.1 }, orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 }, green = { 0.25, 0.75, 0.25 }, gray = { 0.5, 0.5, 0.5 },
}

-- standard difficulty color of a quest level against the player level (fallback when the game gives no color)
function QuestTrack.difficulty(level, playerLevel)
  level, playerLevel = num(level), num(playerLevel)
  local token = "yellow"
  if level and playerLevel then
    local diff = level - playerLevel
    local greenRange = playerLevel <= 5 and 3 or playerLevel <= 39 and floor(playerLevel / 10) + 5 or floor(playerLevel / 5) + 1
    if diff >= 5 then token = "red"
    elseif diff >= 3 then token = "orange"
    elseif diff >= -2 then token = "yellow"
    elseif -diff <= greenRange then token = "green"
    else token = "gray" end
  end
  local c = COLORS[token]
  return token, { r = c[1], g = c[2], b = c[3] }
end

-- ---------------------------------------------------------------- maps and places

local function mapNameOf(mapID)
  mapID = whole(mapID)
  if not mapID then return nil end
  local n = S.names[mapID]
  if n then return n end
  local info = type(C_Map) == "table" and call(C_Map.GetMapInfo, mapID) or nil
  local name = type(info) == "table" and not isSecret(info) and display(info.name, QuestTrack.NAME_BYTES) or nil
  if name then S.names[mapID] = name end
  return name
end

-- display-safe map name (E4: zone of the focus card)
function QuestTrack.mapName(mapID) return mapNameOf(mapID) end

local function zoneOfMap(mapID)
  mapID = whole(mapID)
  if not mapID then return nil end
  local G = geo()
  local z = G and G.mainZoneOf and whole(call(G.mainZoneOf, mapID)) or nil
  return z or mapID
end

-- player position: { map, x, y, zone } (x/y nil when unreadable); nil without a map
local function readHere()
  local Z = ns.Zone
  if not (Z and Z.raw) then return nil end
  local m, x, y = call(Z.raw)
  m = whole(m)
  if not m or m <= 0 then return nil end
  return { map = m, x = unit01(x), y = unit01(y), zone = zoneOfMap(m) }
end

-- zone name -> map id, for log headers: the current zone chain first, then the zone maps of the current continent (kept per continent)
local function lookupZoneByName(R, name)
  local key = lower(name)
  local h = R.here
  if not h then return nil end
  local own = h.zone and mapNameOf(h.zone)
  if own and lower(own) == key then return h.zone end
  local cur = mapNameOf(h.map)
  if cur and lower(cur) == key then return zoneOfMap(h.map) end
  local G = geo()
  local cont = G and G.continentOf and whole(call(G.continentOf, h.map)) or nil
  if not (cont and type(C_Map) == "table") then return nil end
  local idx = S.nameIndex[cont]
  if not idx then
    if R.nameFail[cont] then return nil end
    local list = call(C_Map.GetMapChildrenInfo, cont, G.ZONE_TYPE or 3, true)
    if type(list) ~= "table" or isSecret(list) then
      R.nameFail[cont] = true
      return nil
    end
    idx = {}
    local n = 0
    for i = 1, #list do
      local e = list[i]
      if type(e) == "table" and not isSecret(e) then
        local id, nm = whole(e.mapID), display(e.name, QuestTrack.NAME_BYTES)
        if id and nm and n < QuestTrack.NAME_INDEX_MAX and idx[lower(nm)] == nil then
          idx[lower(nm)] = id
          n = n + 1
        end
      end
    end
    S.nameIndex[cont] = idx
  end
  return idx[key]
end

-- GetQuestsOnMap(mapID) -> { [questID] = { mapID, x, y } }, once per read and map
local function poiOf(R, mapID)
  local p = R.poi[mapID]
  if p then return p end
  p = {}
  R.poi[mapID] = p
  if R.poiCount >= 16 then return p end
  R.poiCount = R.poiCount + 1
  local list = type(C_QuestLog) == "table" and call(C_QuestLog.GetQuestsOnMap, mapID) or nil
  if type(list) ~= "table" or isSecret(list) then return p end
  for i = 1, min(#list, 300) do
    local e = list[i]
    if type(e) == "table" and not isSecret(e) then
      local id, x, y = questKey(e.questID), unit01(e.x), unit01(e.y)
      if id and x and y and p[id] == nil then p[id] = { mapID = mapID, x = x, y = y } end
    end
  end
  return p
end

-- ---------------------------------------------------------------- QuestieDB (Forever, optional)

local function qdbModule() return Journal.OpenQuestsQDB end

-- QDB.probe() under pcall (it touches foreign addon globals): ok, reason, lib
local function probe()
  local QDB = qdbModule()
  if not (QDB and type(QDB.probe) == "function") then return false, "NO_MODULE" end
  local okP, ok, reason, lib = pcall(QDB.probe)
  if not okP or ok ~= true then return false, okP and reason or "ERROR" end
  return true, reason, lib
end

local function clockFn()
  local f = rawget(_G, "debugprofilestop")
  if type(f) ~= "function" then return nil end
  return function()
    local ok, v = pcall(f)
    return (ok and num(v)) or 0
  end
end

local function dbGet(ent, id, key)
  if type(ent) ~= "table" or type(ent.Get) ~= "function" then return nil end
  local ok, v = pcall(ent.Get, id, key)
  if not ok or isSecret(v) then return nil end
  return v
end

-- list of entity ids in a QuestieDB entry list ({ id, ... } or { { id, name }, ... } or a single number), sorted, at most max
local function entryIds(v, max)
  local out = {}
  if type(v) == "number" then v = { v } end
  if type(v) ~= "table" or isSecret(v) then return out end
  local seen = {}
  for _, e in pairs(v) do
    local id = whole(type(e) == "table" and not isSecret(e) and e[1] or e)
    if id and id > 0 and id <= 10000000 and not seen[id] then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  sort(out)
  for i = #out, max + 1, -1 do out[i] = nil end
  return out
end

-- collector of spawn points: acc[mapID] = { { x*100, y*100 }, ... }; maps come from QDB.spawnMaps (0-1)
local function addMaps(acc, maps)
  for _, m in ipairs(maps or {}) do
    local list = acc[m.mapID]
    if not list then
      list = {}
      acc[m.mapID] = list
    end
    for _, p in ipairs(m.points) do list[#list + 1] = { p[1] * 100, p[2] * 100 } end
  end
end

-- thinned flat list { { mapID, x, y }, ... } (0-1), at most POINTS_MAX; false when empty
local function flatten(acc)
  local QDB = qdbModule()
  local ids = {}
  for mapID in pairs(acc) do ids[#ids + 1] = mapID end
  sort(ids)
  local out = {}
  for _, mapID in ipairs(ids) do
    for _, p in ipairs(QDB.thinPoints(acc[mapID])) do
      if #out < QuestTrack.POINTS_MAX then out[#out + 1] = { mapID = mapID, x = p[1] / 100, y = p[2] / 100 } end
    end
  end
  if #out == 0 then return false end
  return out
end

-- resolves one quest (kind "open" = objective places, "fin" = turn-in places) into S.qdb.cache[id]. Runs in the coroutine: yields
-- only through tick(), never inside a pcall; every QuestieDB access is one pcall (dbGet).
local function resolveQuest(lib, zones, id, kind, tick)
  local QDB = qdbModule()
  local Q = S.qdb
  local entry = Q.cache[id]
  if not entry then
    if Q.cacheN >= QuestTrack.CACHE_MAX then
      Q.cache, Q.cacheN = {}, 0
    end
    entry = {}
    Q.cache[id] = entry
    Q.cacheN = Q.cacheN + 1
  end
  local acc, used = {}, 0
  local function spawnsOf(ent, eid)
    if used >= QuestTrack.QDB_ENTITY_MAX then return end
    used = used + 1
    addMaps(acc, QDB.spawnMaps(dbGet(ent, eid, "spawns"), zones))
    tick()
  end
  local quest = lib.Quest
  if entry.zone == nil then
    local zs = whole(dbGet(quest, id, "zoneOrSort"))
    entry.zone = (zs and zs > 0 and zones.resolve(zs)) or false
    tick()
  end
  if entry.starter == nil then
    -- quest giver (focus card, D5): first NPC, else first object of startedBy
    local sb = dbGet(quest, id, "startedBy")
    local name
    if type(sb) == "table" and not isSecret(sb) then
      for _, nid in ipairs(entryIds(sb[1], 4)) do name = name or QDB.cleanName(dbGet(lib.Npc, nid, "name")) end
      if not name then
        for _, oid in ipairs(entryIds(sb[2], 4)) do name = name or QDB.cleanName(dbGet(lib.Object, oid, "name")) end
      end
    end
    entry.starter = name or false
    tick()
  end
  if kind == "fin" then
    local fb = dbGet(quest, id, "finishedBy")
    local npcs = type(fb) == "table" and entryIds(fb[1], 8) or {}
    local objs = type(fb) == "table" and entryIds(fb[2], 8) or {}
    local name
    for _, nid in ipairs(npcs) do
      name = name or QDB.cleanName(dbGet(lib.Npc, nid, "name"))
      spawnsOf(lib.Npc, nid)
    end
    for _, oid in ipairs(objs) do
      if not name then name = QDB.cleanName(dbGet(lib.Object, oid, "name")) end
      spawnsOf(lib.Object, oid)
    end
    entry.finisher = name or false
    entry.fin = flatten(acc)
  else
    local obj = dbGet(quest, id, "objectives")
    if type(obj) == "table" then
      for _, nid in ipairs(entryIds(obj[1], QuestTrack.QDB_ENTITY_MAX)) do spawnsOf(lib.Npc, nid) end
      for _, oid in ipairs(entryIds(obj[2], QuestTrack.QDB_ENTITY_MAX)) do spawnsOf(lib.Object, oid) end
      if type(lib.Item) == "table" then
        for _, iid in ipairs(entryIds(obj[3], 8)) do
          for _, nid in ipairs(entryIds(dbGet(lib.Item, iid, "npcDrops"), QuestTrack.QDB_DROPPERS_MAX)) do spawnsOf(lib.Npc, nid) end
          for _, oid in ipairs(entryIds(dbGet(lib.Item, iid, "objectDrops"), QuestTrack.QDB_DROPPERS_MAX)) do spawnsOf(lib.Object, oid) end
        end
      end
    end
    local te = dbGet(quest, id, "triggerEnd")
    if type(te) == "table" and not isSecret(te) then
      addMaps(acc, QDB.spawnMaps(te[2], zones))
      tick()
    end
    entry.open = flatten(acc)
  end
end

local function queueQdb(id, kind)
  local Q = S.qdb
  local key = id * 2 + (kind == "fin" and 1 or 0)
  if Q.queued[key] then return end
  Q.queued[key] = true
  Q.queue[#Q.queue + 1] = { id = id, kind = kind, key = key }
end

local stepQdb

-- schedule the next frame of QuestieDB work; force = also without queued quests (a paused job still has to finish)
local function kickQdb(delay, force)
  local Q = S.qdb
  if Q.timer or (#Q.queue == 0 and not force) then return end
  Q.timer = true
  if not after(delay or 0, function()
    Q.timer = false
    stepQdb()
  end) then
    Q.timer = false
  end
end

local relocateAll
local headerKeyOf -- defined with the arrangement below

-- The player entered a zone: its fold mark is cleared, so the current zone is always open on entering (folding it by hand afterwards
-- holds until the zone is left and entered again). Other zones keep their state. Keys: "z<map>" (order zones) and the log header keys
-- of the zone (order log: the zone's own name and the headers whose map lies in the zone). The first position read after a /reload
-- only sets the baseline (no entering, a folded zone stays folded).
local function openEnteredZone(zone)
  local z = zonesTable(false)
  if not (z and zone) then return end
  z["z" .. zone] = nil
  local name = mapNameOf(zone)
  if name then z[headerKeyOf(name)] = nil end
  for _, rec in ipairs(S.records) do
    if rec.header and rec.zoneMapID and zoneOfMap(rec.zoneMapID) == zone then z[headerKeyOf(rec.header)] = nil end
  end
end

-- the one place that stores the player position: detects the change of the zone (entering)
local function setHere(h)
  if not h then return end
  local old = S.here
  S.here = h
  if old and old.zone and h.zone and old.zone ~= h.zone then openEnteredZone(h.zone) end
end

-- one frame of QuestieDB work (never in combat, never when the feature is off or QuestieDB does not fit)
stepQdb = function()
  local Q = S.qdb
  local QDB = qdbModule()
  if not QDB or not QuestTrack.enabled() then
    Q.state, Q.queue, Q.queued, Q.co = "idle", {}, {}, nil
    return
  end
  if inCombat() then
    Q.state = "waiting"
    -- a paused job (empty queue) has to be resumed after the fight too
    kickQdb(QuestTrack.QDB_COMBAT_WAIT, Q.co ~= nil)
    return
  end
  local ok, reason, lib = probe()
  if not ok then
    Q.state, Q.reason, Q.queue, Q.queued, Q.co = "off", reason, {}, {}, nil
    return
  end
  if Q.errors >= QuestTrack.QDB_ERRORS_MAX then
    Q.state = "failed"
    return
  end
  Q.state, Q.reason = "building", nil
  local clock = clockFn()
  local t0 = clock and clock() or nil
  local ticks = 0
  local function tick()
    ticks = ticks + 1
    if ticks >= QuestTrack.QDB_STEP_TICKS or (t0 and clock() - t0 >= QuestTrack.QDB_BUDGET_MS) then coroutine.yield() end
  end
  if not Q.co or coroutine.status(Q.co) == "dead" then
    Q.jobs = Q.jobs + 1
    Q.co = coroutine.create(function()
      if not Q.zones then
        local zones, why = QDB.zones(lib, coroutine.yield)
        if not zones then
          Q.zoneFail = why
          return
        end
        Q.zones = zones
      end
      while #Q.queue > 0 do
        local item = table.remove(Q.queue, 1)
        Q.queued[item.key] = nil
        resolveQuest(lib, Q.zones, item.id, item.kind, function() Q.tick() end)
        Q.tick()
      end
    end)
  end
  Q.tick = tick
  Q.steps = Q.steps + 1
  local okR, err = coroutine.resume(Q.co)
  if not okR then
    Q.errors = Q.errors + 1
    Q.state, Q.co = "error", nil
    Q.err = type(err) == "string" and sub(gsub(err, "[%c|]", " "), 1, 200) or nil
    Q.queue, Q.queued = {}, {}
    return
  end
  if coroutine.status(Q.co) == "dead" then
    Q.co = nil
    if Q.zoneFail then
      Q.state, Q.reason = "failed", Q.zoneFail
      Q.zoneFail, Q.queue, Q.queued = nil, {}, {}
      Q.errors = QuestTrack.QDB_ERRORS_MAX
      return
    end
    Q.state = "idle"
    if #Q.queue > 0 then
      kickQdb(0)
    else
      relocateAll()
      notify("loc")
    end
  else
    kickQdb(0, true)
  end
end

-- ---------------------------------------------------------------- records

local function itemOf(logIndex, complete)
  if not logIndex or type(GetQuestLogSpecialItemInfo) ~= "function" then return nil end
  local link, texture, charges, showWhenComplete = call(GetQuestLogSpecialItemInfo, logIndex)
  link = str(link)
  if not link then return nil end
  if complete and not flag(showWhenComplete) then return nil end
  local itemID = whole(tonumber(match(link, "item:(%d+)")))
  if not itemID or itemID <= 0 then return nil end
  local tex = nil
  if num(texture) then tex = floor(texture) elseif str(texture) and #texture <= 200 and not find(texture, "[%c|]") then tex = texture end
  return { itemID = itemID, texture = tex, charges = whole(charges) }
end

-- objective line without the counter ("Wolf Pelt: 3/10", "3/10 Wolf Pelt", "Wolf Pelt (3/10)")
local function labelOf(text)
  if not text then return nil end
  local s = gsub(text, "^%d+%s*/%s*%d+%s+", "")
  s = gsub(s, "%s*:%s*%d+%s*/%s*%d+$", "")
  s = gsub(s, "%s*%(%d+%s*/%s*%d+%)$", "")
  s = gsub(s, "%s*%(%d+%%%)$", "")
  s = gsub(s, "%s+$", "")
  if s == "" then return nil end
  return s
end

local function objectivesOf(questID)
  local out = {}
  local list = type(C_QuestLog) == "table" and call(C_QuestLog.GetQuestObjectives, questID) or nil
  if type(list) ~= "table" or isSecret(list) then return out end
  for i = 1, QuestTrack.OBJ_MAX do
    local o = list[i]
    if not isSecret(o) and o == nil then break end
    if type(o) == "table" and not isSecret(o) then
      local text = display(o.text, QuestTrack.TEXT_BYTES)
      local have, need = whole(o.numFulfilled), whole(o.numRequired)
      if have and have < 0 then have = nil end
      if need and need <= 0 then need = nil end
      if text or have then
        local done = flag(o.finished) or (need ~= nil and have ~= nil and have >= need)
        local kind = str(o.type)
        if kind and not match(kind, "^[%a_]+$") then kind = nil end
        out[#out + 1] = { text = text, label = labelOf(text), have = have, need = need, done = done, kind = kind and sub(kind, 1, 20) or nil }
      end
    end
  end
  return out
end

local function colorOf(questID, level, playerLevel)
  local token, fallback = QuestTrack.difficulty(level, playerLevel)
  local pinfo = type(C_PlayerInfo) == "table" and C_PlayerInfo or nil
  if pinfo and type(GetDifficultyColor) == "function" then
    local d = call(pinfo.GetContentDifficultyQuestForPlayer, questID)
    if d ~= nil and not isSecret(d) then
      local c = call(GetDifficultyColor, d)
      if type(c) == "table" and not isSecret(c) and num(c.r) and num(c.g) and num(c.b) then
        return token, { r = c.r, g = c.g, b = c.b }
      end
    end
  end
  return token, fallback
end

-- watch list: set of questIDs; false when the API is missing
local function watchSet()
  local C = type(C_QuestLog) == "table" and C_QuestLog or nil
  if not (C and type(C.GetNumQuestWatches) == "function" and type(C.GetQuestIDForQuestWatchIndex) == "function") then return false end
  local n = whole(call(C.GetNumQuestWatches))
  if not n then return false end
  local set = {}
  for i = 1, min(n, 100) do
    local id = questKey(call(C.GetQuestIDForQuestWatchIndex, i))
    if id then set[id] = true end
  end
  return set
end

-- quest log entries: { questID, info, header, logIndex } in log order. Quests under a folded Blizzard header are only listed when
-- the watch list names them (the game does not list them); log.hidden counts the rest.
local function readLog()
  local list, seen = {}, {}
  local C = type(C_QuestLog) == "table" and C_QuestLog or nil
  if not C then return list, 0 end
  local shown, total = call(C.GetNumQuestLogEntries)
  shown, total = whole(shown) or 0, whole(total)
  local header
  local skipped = 0 -- hidden/task quests: counted by the game, not shown by us
  for i = 1, min(shown, QuestTrack.LOG_MAX) do
    local info = call(C.GetInfo, i)
    if type(info) == "table" and not isSecret(info) then
      if flag(info.isHeader) then
        header = display(info.title, QuestTrack.NAME_BYTES)
      elseif flag(info.isHidden) or flag(info.isTask) then
        skipped = skipped + 1
      else
        local id = questKey(info.questID)
        if id and not seen[id] then
          seen[id] = true
          list[#list + 1] = { questID = id, info = info, header = header, logIndex = i }
        end
      end
    end
  end
  return list, total and max(0, total - #list - skipped) or 0
end

local function readEntry(e, playerLevel, watch)
  local id, info = e.questID, e.info
  local level = whole(info.level)
  local complete = false
  local C = C_QuestLog
  if flag(call(C.IsComplete, id)) or flag(call(C.ReadyForTurnIn, id)) or flag(info.readyForTurnIn) then complete = true end
  local elite, group = false, false
  local tag = call(C.GetQuestTagInfo, id)
  if type(tag) == "table" and not isSecret(tag) then
    if flag(tag.isElite) then elite = true end
    if whole(tag.tagID) == QuestTrack.GROUP_TAG then group = true end
  end
  local size = whole(info.suggestedGroup)
  if size and size >= 2 then group = true else size = nil end
  local token, color = colorOf(id, level, playerLevel)
  local watched
  if watch then
    watched = watch[id] == true
  else
    local wt = call(C.GetQuestWatchType, id)
    watched = wt ~= nil and not isSecret(wt)
  end
  local objectives = objectivesOf(id)
  return {
    questID = id, logIndex = e.logIndex, title = display(info.title, QuestTrack.TITLE_BYTES) or ("#" .. id), level = level, elite = elite,
    group = group or elite, groupSize = size,
    diff = token, color = color, header = e.header, objectives = objectives, complete = complete, watched = watched,
    item = itemOf(e.logIndex, complete), next = false, kind = QuestTrack.kindOf(objectives),
  }
end

-- quest type for the row symbol (D6) from the objective types of the game: "kill" (monster/player), "collect" (item/object),
-- "explore" (event, area, progress bar, anything else with objectives), "talk" (no objectives at all: speak with, deliver)
local KIND_OF = { monster = "kill", player = "kill", item = "collect", object = "collect" }
function QuestTrack.kindOf(objectives)
  if type(objectives) ~= "table" or #objectives == 0 then return "talk" end
  local found = {}
  for _, o in ipairs(objectives) do
    local k = type(o) == "table" and KIND_OF[o.kind or ""] or nil
    if k then found[k] = true end
  end
  if found.kill then return "kill" end
  if found.collect then return "collect" end
  return "explore"
end

-- ---------------------------------------------------------------- places

-- nearest point of a QuestieDB point list to the player: returns point, distance (nil when no distance can be measured; then the
-- point on the player's map or the first one)
local function nearest(pts, here)
  local G = geo()
  local best, bestD
  if here and here.x and G and G.distance then
    for _, p in ipairs(pts) do
      local d = G.distance(here.map, here.x, here.y, p.mapID, p.x, p.y)
      if d and (not bestD or d < bestD) then best, bestD = p, d end
    end
  end
  if best then return best, bestD end
  if here then
    for _, p in ipairs(pts) do
      if p.mapID == here.map then return p, nil end
    end
  end
  return pts[1], nil
end

local function lastResortDist(rec)
  local sq, onContinent = call(type(C_QuestLog) == "table" and C_QuestLog.GetDistanceSqToQuest or nil, rec.questID)
  sq = num(sq)
  if not sq or sq < 0 or onContinent == false then return nil end
  local G = geo()
  return sqrt(sq) * (G and G.YARD_M or 0.9144)
end

-- distance (and, for QuestieDB points, the nearest point) of one record
local function updateDist(rec, here)
  local old = rec.dist
  local d
  local zoneChanged = false
  if rec.pts then
    local p, pd = nearest(rec.pts, here)
    if p then
      local loc = rec.loc
      if loc and loc.src == "qdb" then
        -- same table, no new allocation per tick; the zone follows when the nearest point lies in another zone
        if loc.mapID ~= p.mapID then
          loc.mapID = p.mapID
          local z = zoneOfMap(p.mapID)
          if z ~= rec.zone then
            rec.zone = z
            zoneChanged = true
          end
        end
        loc.x, loc.y = p.x, p.y
      else
        rec.loc = { mapID = p.mapID, x = p.x, y = p.y, src = "qdb" }
      end
      d = pd
    end
  elseif rec.loc and here and here.x then
    local G = geo()
    d = G and G.distance and G.distance(here.map, here.x, here.y, rec.loc.mapID, rec.loc.x, rec.loc.y) or nil
  end
  if d == nil and (not here or not here.x) and old ~= nil and (rec.loc or rec.pts) then return zoneChanged end -- position unreadable: keep
  if d == nil then d = lastResortDist(rec) end
  rec.dist = d
  if d == nil or old == nil then return zoneChanged or d ~= old end
  return zoneChanged or abs(d - old) >= 1
end

-- zone of a record: header map (log zone), place zone
local function resolveZone(rec, R)
  local zm
  if rec.header then zm = lookupZoneByName(R, rec.header) end
  local c = S.qdb.cache[rec.questID]
  if not zm and c and c.zone then zm = c.zone end
  rec.zoneMapID = zm
end

-- The real place of a quest. GetQuestsOnMap(zoneMap) also lists a quest on neighbouring zone maps with a substitute point at the
-- border; the continent map has the quest once, at its real place. So: continent point -> C_Map.GetMapInfoAtPosition -> the zone map
-- that contains it -> the point of that zone map (else the continent point itself, with the zone as hint). Cached per quest and
-- continent point until the next QUEST_LOG_UPDATE / loading screen. Returns true when rec.loc was set.
local function mapAt(cont, x, y)
  local f = type(C_Map) == "table" and C_Map.GetMapInfoAtPosition or nil
  if type(f) ~= "function" then return nil end
  local info = call(f, cont, x, y)
  if type(info) ~= "table" or isSecret(info) then return nil end
  local m = whole(info.mapID)
  return m and m > 0 and m or nil
end

local function trueLoc(rec, R)
  if type(C_QuestLog) ~= "table" then return false end
  local id = rec.questID
  local G = geo()
  if not (G and G.continentOf) then return false end
  local conts, seen = {}, {}
  for _, m in ipairs({ R.here and R.here.map or 0, rec.zoneMapID or 0 }) do
    local c = m > 0 and whole(call(G.continentOf, m)) or nil
    if c and not seen[c] then
      seen[c] = true
      conts[#conts + 1] = c
    end
  end
  for _, cont in ipairs(conts) do
    local cp = poiOf(R, cont)[id]
    if cp then
      local t = S.trueMap[id]
      local at
      if t and t.cont == cont and t.x == cp.x and t.y == cp.y then
        at = t.map
      else
        at = mapAt(cont, cp.x, cp.y) or false
        S.trueMap[id] = { cont = cont, x = cp.x, y = cp.y, map = at }
      end
      if at then
        local z = zoneOfMap(at)
        for _, m in ipairs({ at, z }) do
          local p = m ~= cont and poiOf(R, m)[id] or nil
          if p then
            local here = R.here
            rec.loc = { mapID = p.mapID, x = p.x, y = p.y, src = (here and m == here.map) and "map" or "zone" }
            return true
          end
        end
        rec.loc = { mapID = cp.mapID, x = cp.x, y = cp.y, src = "zone", zone = z }
        return true
      end
    end
  end
  return false
end

local function resolveLoc(rec, R)
  rec.loc, rec.pts, rec.finisher, rec.starter = nil, nil, nil, nil
  local id = rec.questID
  local Q = S.qdb
  if R.qdb then
    local c = Q.cache[id]
    local kind = rec.complete and "fin" or "open"
    if c and c[kind] == nil then
      queueQdb(id, kind)
    elseif c and c[kind] then
      rec.pts = c[kind]
    elseif not c then
      queueQdb(id, kind)
    end
    if c and rec.complete and c.finisher then rec.finisher = display(c.finisher, QuestTrack.NAME_BYTES) end
    if c and c.starter then rec.starter = display(c.starter, QuestTrack.NAME_BYTES) end
  end
  if rec.pts then
    local p = nearest(rec.pts, R.here)
    rec.loc = { mapID = p.mapID, x = p.x, y = p.y, src = "qdb" }
    return
  end
  if trueLoc(rec, R) then return end
  local here = R.here
  if here then
    local p = poiOf(R, here.map)[id]
    if p then
      rec.loc = { mapID = p.mapID, x = p.x, y = p.y, src = "map" }
      return
    end
    if rec.zoneMapID and rec.zoneMapID ~= here.map then
      p = poiOf(R, rec.zoneMapID)[id]
      if p then
        rec.loc = { mapID = p.mapID, x = p.x, y = p.y, src = "zone" }
        return
      end
    end
  end
  local C = C_QuestLog
  if type(C) == "table" and type(C.GetNextWaypoint) == "function" then
    local m, x, y = call(C.GetNextWaypoint, id)
    m, x, y = whole(m), unit01(x), unit01(y)
    if m and m > 0 and x and y then rec.loc = { mapID = m, x = x, y = y, src = "waypoint" } end
  end
end

local function placeZone(rec)
  if rec.loc and rec.loc.zone then return rec.loc.zone end
  if rec.loc then return zoneOfMap(rec.loc.mapID) end
  return rec.zoneMapID and zoneOfMap(rec.zoneMapID) or nil
end

local function newContext()
  return { here = readHere(), poi = {}, poiCount = 0, qdb = false, nameFail = {} }
end

-- places, zones and distances for all records of the last read (also after QuestieDB results came in)
relocateAll = function()
  local R = newContext()
  local QDB = qdbModule()
  R.qdb = QDB ~= nil and QuestTrack.available() and (probe()) == true
  for _, rec in ipairs(S.records) do
    resolveZone(rec, R)
    resolveLoc(rec, R)
    rec.zone = placeZone(rec)
    updateDist(rec, R.here)
  end
  setHere(R.here) -- after the records: the header maps are known for the fold marks of an entered zone
  if R.qdb then kickQdb(0) end
end

-- ---------------------------------------------------------------- reading

function QuestTrack.read()
  if not QuestTrack.available() or type(C_QuestLog) ~= "table" then return S.records end
  local list, missing = readLog()
  local watch = watchSet()
  -- Quests under a folded Blizzard header are not listed by the game. When the log says there are more quests than listed
  -- (second return of GetNumQuestLogEntries), look for them by ID: watch list, quests of the current map, earlier finds, the
  -- character's own quest stock. Every candidate must pass C_QuestLog.IsOnQuest. No ExpandQuestHeader (that would change the log).
  if missing > 0 then
    local have = {}
    for _, e in ipairs(list) do have[e.questID] = true end
    local C = C_QuestLog
    local function consider(id)
      id = questKey(id)
      if not id or have[id] or missing <= 0 then return end
      have[id] = true
      if S.notOn[id] then return end
      local on = call(C.IsOnQuest, id)
      if on ~= true or isSecret(on) then
        if on == false then
          S.notOn[id] = true -- stays so until the next QUEST_ACCEPTED / loading screen
          S.foldedIDs[id] = nil
        end
        return
      end
      local entry
      local idx = whole(call(C.GetLogIndexForQuestID, id))
      local info = idx and call(C.GetInfo, idx) or nil
      if type(info) == "table" and not isSecret(info) and not flag(info.isHeader) and questKey(info.questID) == id then
        if flag(info.isHidden) or flag(info.isTask) then return end
        entry = { questID = id, info = info, header = nil, logIndex = idx }
      else
        local title = call(C.GetTitleForQuestID, id)
        entry = { questID = id, header = nil, logIndex = nil, info = { title = title, level = call(C.GetQuestDifficultyLevel, id) } }
      end
      list[#list + 1] = entry
      S.foldedIDs[id] = true
      missing = missing - 1
    end
    for id in pairs(watch or {}) do consider(id) end
    for id in pairs(S.foldedIDs) do consider(id) end
    local here = readHere()
    if here and missing > 0 then
      local R0 = { poi = {}, poiCount = 0 }
      for id in pairs(poiOf(R0, here.map)) do consider(id) end
    end
    if missing > 0 then
      local char = ns.Store and ns.Store.char and ns.Store.char() or nil
      local stock = type(char) == "table" and not isSecret(char) and char.quests or nil
      if type(stock) == "table" and not isSecret(stock) then
        local n = 0
        for id in pairs(stock) do
          n = n + 1
          if n > QuestTrack.STOCK_MAX or missing <= 0 then break end
          consider(id)
        end
      end
    end
    missing = max(0, missing)
  end
  local folded = missing
  local playerLevel = whole(call(UnitLevel, "player"))
  local records, byID = {}, {}
  for _, e in ipairs(list) do
    local rec = readEntry(e, playerLevel, watch)
    rec.ord = #records + 1
    records[rec.ord] = rec
    byID[rec.questID] = rec
  end
  -- hidden quests that left the log are dropped (only after a read that found quests: an unloaded log must not wipe the list)
  -- (and only for quests the game says are certainly not in the log: IsOnQuest == false, never because the listed log lacks them)
  local hidden = hiddenTable(false)
  if hidden and #records > 0 then
    for id in pairs(hidden) do
      if not byID[id] then
        local on = call(C_QuestLog.IsOnQuest, id)
        if on == false then hidden[id] = nil end
      end
    end
  end
  S.records, S.byID, S.ready, S.foldedHidden = records, byID, true, folded
  S.rewards = {}
  relocateAll()
  return records
end

local function runRequest()
  S.readPending = false
  if not QuestTrack.enabled() then return end
  QuestTrack.read()
  notify("log")
end

-- bundled read: any number of events in one frame lead to one read
function QuestTrack.request()
  if not QuestTrack.enabled() or S.readPending then return end
  S.readPending = true
  if not after(0, runRequest) then runRequest() end
end

function QuestTrack.records() return S.records end

-- E4 getters for the window and the item bar (no access to QuestTrack._state from outside)
function QuestTrack.record(questID)
  local id = questKey(questID)
  return id and S.byID[id] or nil
end

-- zone of the player (the zone of the last build, else of the last position read) | nil
function QuestTrack.currentZone()
  local v = S.lastView
  if v and v.zoneMapID then return v.zoneMapID end
  return S.here and S.here.zone or nil
end

-- ---------------------------------------------------------------- distance ticker

function QuestTrack.tick()
  if not QuestTrack.enabled() or not S.ready then return false end
  local here = readHere()
  if here and S.here and here.zone ~= S.here.zone then
    setHere(here)
    QuestTrack.request()
    return false
  end
  if here then S.here = here end
  local changed = false
  for _, rec in ipairs(S.records) do
    if updateDist(rec, here) then changed = true end
  end
  if changed then notify("dist") end
  return changed
end

function QuestTrack.setActive(on)
  on = on == true
  S.active = on
  if on and not S.ticker and QuestTrack.available() and type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
    local ok, t = pcall(C_Timer.NewTicker, QuestTrack.TICK_SEC, function() QuestTrack.tick() end)
    if ok then S.ticker = t end
  elseif not on and S.ticker then
    pcall(function() S.ticker:Cancel() end)
    S.ticker = nil
  end
end

-- ---------------------------------------------------------------- rewards and direction (E4: focus card)

QuestTrack.REWARD_SCAN_MAX = 6

-- all returns of a legacy global under pcall (call() keeps only four)
local function passOk(ok, ...)
  if not ok then return nil end
  return ...
end

local function callAll(fn, ...)
  if type(fn) ~= "function" then return nil end
  return passOk(pcall(fn, ...))
end

local function rewardItem(name, texture, count, quality, itemID)
  name = display(name, QuestTrack.NAME_BYTES)
  if not name or name == "" then return nil end
  local q = whole(quality)
  if q and (q < 0 or q > 8) then q = nil end
  local tex
  if num(texture) then tex = floor(texture) elseif str(texture) and #texture <= 200 and not find(texture, "[%c|]") then tex = texture end
  local id = whole(itemID)
  return { name = name, quality = q, count = whole(count), texture = tex, itemID = id and id > 0 and id or nil }
end

-- Rewards of a quest (D5) from the quest log globals the game reads itself (GetQuestLogRewardXP/Money, GetNumQuestLogRewards,
-- GetQuestLogRewardInfo, GetNumQuestLogChoices, GetQuestLogChoiceInfo; all with the questID). Only readable, non-secret values;
-- nil when nothing is readable (the card then shows no reward line). Cached until the next read.
-- -> { xp = n | nil, money = copper | nil, item = { name, quality, count, texture, itemID } | nil, choice = bool }
function QuestTrack.rewards(questID)
  local id = questKey(questID)
  if not id or not QuestTrack.available() then return nil end
  S.rewards = S.rewards or {}
  local c = S.rewards[id]
  if c ~= nil then return c or nil end
  local out = {}
  local xp = whole(call(rawget(_G, "GetQuestLogRewardXP"), id))
  if xp and xp > 0 then out.xp = xp end
  local money = whole(call(rawget(_G, "GetQuestLogRewardMoney"), id))
  if money and money > 0 then out.money = money end
  local n = whole(call(rawget(_G, "GetNumQuestLogRewards"), id)) or 0
  for i = 1, min(n, QuestTrack.REWARD_SCAN_MAX) do
    if out.item then break end
    local name, texture, count, quality, _, itemID = callAll(rawget(_G, "GetQuestLogRewardInfo"), i, id)
    out.item = rewardItem(name, texture, count, quality, itemID)
  end
  if not out.item then
    local nc = whole(call(rawget(_G, "GetNumQuestLogChoices"), id, true)) or 0
    for i = 1, min(nc, QuestTrack.REWARD_SCAN_MAX) do
      if out.item then break end
      local name, texture, count, quality, _, itemID = callAll(rawget(_G, "GetQuestLogChoiceInfo"), i, id)
      out.item = rewardItem(name, texture, count, quality, itemID)
      if out.item then out.choice = nc > 1 end
    end
  end
  if not (out.xp or out.money or out.item) then out = false end
  S.rewards[id] = out
  return out or nil
end

-- the player's facing (radians, 0 = north, counter-clockwise), nil when the game gives none (instances) or a secret value
function QuestTrack.facing()
  local v = num(call(rawget(_G, "GetPlayerFacing")))
  if not v then return nil end
  return v
end

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

-- Direction to the quest's place relative to the player's facing (radians, counter-clockwise, 0 = straight ahead), for an arrow
-- that points up (Texture:SetRotation). nil without facing, position or place (the window then shows only the distance).
function QuestTrack.bearing(rec)
  if type(rec) ~= "table" or isSecret(rec) then return nil end
  local loc, h = rec.loc, S.here
  if type(loc) ~= "table" or not (h and h.x and h.y) then return nil end
  local face = QuestTrack.facing()
  local G = geo()
  if not (face and G and G.vector) then return nil end
  local dx, dy = G.vector(h.map, h.x, h.y, loc.mapID, loc.x, loc.y)
  if not (num(dx) and num(dy)) or (abs(dx) < 0.5 and abs(dy) < 0.5) then return nil end
  local b = atan2(-dx, -dy) -- bearing of the place: 0 = north, counter-clockwise (like GetPlayerFacing)
  return (b - face) % (2 * math.pi)
end

-- ---------------------------------------------------------------- arrangement

local function byDist(a, b)
  local da, db = a.dist, b.dist
  if da and db then
    if da ~= db then return da < db end
  elseif da then
    return true
  elseif db then
    return false
  end
  return a.ord < b.ord
end

local function byOrd(a, b) return a.ord < b.ord end

-- state key of a log header: the lower-cased text; text with escaped '|' or control characters gets '_' for them plus a hash suffix,
-- so different headers never collapse into one key
headerKeyOf = function(header)
  local s = lower(header)
  local k = validKey("h:" .. s)
  if k then return k end
  local h = 5381
  for i = 1, #s do h = (h * 33 + string.byte(s, i)) % 1000003 end
  local clean = gsub(s, "[%c|]", "_")
  local S_ = ns.Sanitize
  if S_ and S_.cut then clean = S_.cut(clean, 40) else clean = sub(clean, 1, 40) end
  return "h:" .. clean .. "#" .. h
end

local function zoneKey(rec)
  if rec.zone then return "z" .. rec.zone end
  if rec.header then return headerKeyOf(rec.header) end
  return "none"
end

local function headerKey(rec)
  if rec.header then return headerKeyOf(rec.header) end
  return "none"
end

-- is the quest's place in the current zone (rec.zone = zone of the place, for a quest without a place the zone of its log header)
local function inCurrentZone(rec, cur)
  return cur ~= nil and rec.zone == cur
end

-- ready-to-turn-in quests (done = "inZone": they stay in their list) go to the END of that list; the order of the open ones and
-- the order among the ready ones stay as they were (stable, in place)
local function readyLast(list)
  local open, ready = {}, {}
  for _, rec in ipairs(list) do
    if rec.complete then ready[#ready + 1] = rec else open[#open + 1] = rec end
  end
  if #ready == 0 or #open == 0 then return list end
  for i, rec in ipairs(open) do list[i] = rec end
  for i, rec in ipairs(ready) do list[#open + i] = rec end
  return list
end

function QuestTrack.build()
  local st = QuestTrack.settings()
  local cur = S.here and S.here.zone or nil
  local hidden = hiddenTable(false) or {}
  local zstate = zonesTable(false) or {}
  local view = {
    mode = st.mode, order = st.order, done = st.done, ready = S.ready, zoneMapID = cur, zoneName = cur and mapNameOf(cur) or nil,
    count = 0, hiddenCount = countKeys(hidden), groups = {}, readyCount = 0, total = #S.records, filtered = 0, zoneHidden = 0,
    zoneOnly = st.filter.zoneOnly,
    maxQuests = whole(call(type(C_QuestLog) == "table" and C_QuestLog.GetMaxNumQuestsCanAccept or nil)) or 25,
  }
  -- focus card (D5): the focused quest ALSO stays in its list place (the row is marked); hidden quests never
  local fid = QuestTrack.focus()
  local visible, turnin = {}, {}
  for _, rec in ipairs(S.records) do
    rec.next = false
    local show
    local isHidden = hidden[rec.questID] == true
    if not isHidden and rec.complete then view.readyCount = view.readyCount + 1 end
    if not isHidden and fid == rec.questID then view.focusRec = rec end
    if isHidden then show = false
    elseif st.mode == "tracked" then show = rec.watched == true
    elseif st.mode == "zone" then show = inCurrentZone(rec, cur)
    else show = true end
    if show and ((st.filter.done and rec.complete) or (st.filter.group and rec.group)) then
      show = false
      view.filtered = view.filtered + 1
    end
    -- "only current zone" (filter.zoneOnly) works on top of any selection mode; the focus card is exempt
    if show and st.filter.zoneOnly and not inCurrentZone(rec, cur) then
      show = false
      view.zoneHidden = view.zoneHidden + 1
    end
    if show then
      if rec.complete and st.done == "group" then turnin[#turnin + 1] = rec else visible[#visible + 1] = rec end
    end
  end
  view.count = #visible + #turnin
  if #turnin > 0 then
    sort(turnin, byDist)
    view.groups[1] = { id = "turnin", kind = "turnin", count = #turnin, quests = turnin, current = false,
      collapsed = st.collapsed.turnin }
  end
  if st.order == "distance" then
    if #visible > 0 then
      sort(visible, byDist)
      readyLast(visible)
      view.groups[#view.groups + 1] = { id = "all", kind = "flat", count = #visible, quests = visible, current = false, collapsed = false }
    end
  elseif st.order == "level" then
    if #visible > 0 then
      sort(visible, function(a, b)
        local la, lb = a.level or 0, b.level or 0
        if la ~= lb then return la < lb end
        return byDist(a, b)
      end)
      readyLast(visible)
      view.groups[#view.groups + 1] = { id = "level", kind = "flat", count = #visible, quests = visible, current = false, collapsed = false }
    end
  elseif st.order == "log" then
    local byKey, list = {}, {}
    sort(visible, byOrd)
    readyLast(visible)
    for _, rec in ipairs(visible) do
      local key = headerKey(rec)
      local g = byKey[key]
      if not g then
        g = { id = key, kind = "header", key = key, name = rec.header, mapID = rec.zoneMapID, quests = {}, count = 0 }
        g.current = cur ~= nil and g.mapID ~= nil and zoneOfMap(g.mapID) == cur
        g.collapsed = zstate[key] == true
        byKey[key] = g
        list[#list + 1] = g
      end
      g.quests[#g.quests + 1] = rec
      g.count = g.count + 1
    end
    for _, g in ipairs(list) do view.groups[#view.groups + 1] = g end
  else
    local byKey, list = {}, {}
    for _, rec in ipairs(visible) do
      local key = zoneKey(rec)
      local g = byKey[key]
      if not g then
        g = { id = key, kind = "zone", key = key, mapID = rec.zone, quests = {}, count = 0 }
        g.name = rec.zone and mapNameOf(rec.zone) or rec.header
        g.current = cur ~= nil and rec.zone == cur
        if zstate[key] ~= nil then g.collapsed = zstate[key] == true else g.collapsed = not g.current end
        byKey[key] = g
        list[#list + 1] = g
      end
      g.quests[#g.quests + 1] = rec
      g.count = g.count + 1
    end
    for _, g in ipairs(list) do
      sort(g.quests, byDist)
      g.first = g.quests[1] -- the group order still follows the nearest quest, ready or not
      readyLast(g.quests)
    end
    sort(list, function(a, b)
      if a.current ~= b.current then return a.current end
      return byDist(a.first, b.first)
    end)
    for _, g in ipairs(list) do
      g.first = nil
      view.groups[#view.groups + 1] = g
    end
  end
  -- next: the nearest open visible quest of the current zone
  local best
  for _, rec in ipairs(visible) do
    if not rec.complete and inCurrentZone(rec, cur) and (not best or byDist(rec, best)) then best = rec end
  end
  if best then
    best.next = true
    view.next = best
  end
  view.focus = st.focus.show and view.focusRec or nil
  S.lastView = view
  return view
end

-- ---------------------------------------------------------------- diagnostics

function QuestTrack.status()
  local Q = S.qdb
  local src = { qdb = 0, map = 0, zone = 0, waypoint = 0, none = 0 }
  for _, rec in ipairs(S.records) do
    local k = rec.loc and rec.loc.src or "none"
    src[k] = (src[k] or 0) + 1
  end
  return { available = QuestTrack.available(), enabled = QuestTrack.enabled(), installed = S.installed, ready = S.ready,
    records = #S.records, src = src, qdb = { state = Q.state, reason = Q.reason, cached = Q.cacheN, queued = #Q.queue, steps = Q.steps,
    jobs = Q.jobs, errors = Q.errors, err = Q.err }, foldedHidden = S.foldedHidden or 0, active = S.active, listeners = #S.listeners,
    superTrack = { pushes = S.sync.pushes, errors = S.sync.errors, blocked = S.sync.blocked, pending = S.sync.pending, last = S.sync.lastPush } }
end

-- ---------------------------------------------------------------- events

local function onEvent(event, a)
  if not QuestTrack.enabled() then return end
  if event == "PLAYER_REGEN_ENABLED" then
    flushPush()
    kickQdb(0, S.qdb.co ~= nil)
    return
  end
  if event == "SUPER_TRACKING_CHANGED" then
    readSuperTracked()
    return
  end
  if event == "PLAYER_ENTERING_WORLD" then
    -- a loading screen gives QuestieDB (and the map data) a new chance
    S.qdb.errors, S.qdb.state = 0, "idle"
    S.names, S.nameIndex, S.notOn, S.trueMap = {}, {}, {}, {}
    readSuperTracked()
  elseif event == "QUEST_LOG_UPDATE" then
    S.trueMap = {}
  elseif event == "QUEST_ACCEPTED" then
    S.notOn = {}
  elseif event == "QUEST_REMOVED" then
    QuestTrack.unhide(a)
    forgetQuest(a)
    S.foldedIDs[questKey(a) or 0] = nil
  end
  QuestTrack.request()
end

-- Forever only: in Retail nothing is registered (QuestTrack.status().installed == false)
function QuestTrack.install()
  if S.installed or not QuestTrack.available() then return S.installed end
  local core = ns.Core
  if not (core and core.on) then return false end
  S.installed = true
  for _, ev in ipairs(QuestTrack.EVENTS) do core.on(ev, onEvent) end
  return true
end

QuestTrack.install()
