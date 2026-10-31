-- Data for "welcome back". Detects a real login (PLAYER_ENTERING_WORLD with isInitialLogin; not /reload or zone changes)
-- and runs the ns.onLoginWelcome hooks. Welcome.summary() -> { name, level, first, lastZone, lastMapID, lastSeenAgo,
-- openQuests, restedXP, restedPct, vorhabenNearby }.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Welcome = ns.Welcome or {}
ns.Welcome = Welcome

local floor, huge = math.floor, math.huge

Welcome.DELAY = 3         -- seconds after load until the card shows
Welcome.RETRY = 5         -- seconds between retries while in combat
Welcome.TRIES = 6
Welcome.NAMES_MAX = 5
Welcome.QUEST_SCAN = 400  -- max quest log entries to read

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == huge or v == -huge then return nil end
  return v
end

local function str(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if not ok then return nil end
  return a, b
end

local function flag(v)
  return not isSecret(v) and v == true
end

local hooks = {}
local state = { kind = nil, reloadGuess = false, fired = false, timerOn = false, first = true }

local schedule -- defined below

function ns.onLoginWelcome(fn)
  if type(fn) ~= "function" then return false end
  for _, f in ipairs(hooks) do
    if f == fn then return false end
  end
  hooks[#hooks + 1] = fn
  if state.kind == "login" then schedule() end -- hook registered late, card still pending
  return true
end

function Welcome.kind()
  return state.kind
end

-- previous session, captured at load (Store.login already sets info.lastSeen to now)

local function previousSession()
  local Store = ns.Store
  local db = Store and Store.db
  local meta = type(db) == "table" and db.meta
  local sessions = type(meta) == "table" and meta.sessions
  if type(sessions) ~= "table" or not Store.guid then return nil end
  local start = (tonumber(Store.session) or (#sessions + 1)) - 1
  for i = start, 1, -1 do
    local s = sessions[i]
    if type(s) == "table" and s.guid == Store.guid then return s end
  end
  return nil
end

local function sessionEnd(s)
  for _, k in ipairs({ "stop", "lastKnown", "lastSave", "start" }) do
    local v = tonumber(s[k])
    if v and v == v and v ~= huge and v ~= -huge then return v end
  end
  return nil
end

-- map at the end of the previous session: head of the last trail block (epoch, mapID)
local function lastMap()
  local Store = ns.Store
  local char = Store and Store.char()
  local trail = char and char.trail
  if type(trail) ~= "table" then return nil end
  for i = #trail, 1, -1 do
    local b = trail[i]
    if type(b) == "string" then
      local map = string.match(b, "^#~%-?%d+~(%d+)")
      map = map and tonumber(map)
      if map and map > 0 then return map end
    end
  end
  return nil
end

local function mapName(mapID)
  if not mapID then return nil end
  local Store = ns.Store
  local char = Store and Store.char()
  local snaps = char and char.snapshots
  local m = type(snaps) == "table" and type(snaps.maps) == "table" and snaps.maps[mapID]
  local name = type(m) == "table" and str(m.name) or nil
  if not name and ns.Zone then
    local info = ns.Zone.info(mapID)
    name = info and str(info.name) or nil
  end
  if not name then return nil end
  name = ns.Sanitize.field(name)
  return name ~= "" and name or nil
end

local function capture()
  local prev = previousSession()
  state.first = prev == nil
  state.prevEnd = prev and sessionEnd(prev) or nil
  state.capturedAt = time()
  state.lastMapID = prev and lastMap() or nil
end

-- accept time of a quest: chars[guid].quests[questID].firstAt (set by the collector); nil if unknown
local function acceptedAt(questID)
  questID = num(questID)
  local Store = ns.Store
  local char = questID and Store and Store.char and Store.char()
  local quests = type(char) == "table" and char.quests
  if type(quests) ~= "table" then return nil end
  local e = quests[floor(questID)]
  if e == nil then e = quests[tostring(floor(questID))] end
  return type(e) == "table" and num(e.firstAt) or nil
end

local function openQuests()
  local out = { count = 0, names = {} }
  local api = type(C_QuestLog) == "table" and C_QuestLog or nil
  if not api or type(api.GetInfo) ~= "function" then return out end
  local newest, newestAt -- most recently accepted open quest
  local n = num(call(api.GetNumQuestLogEntries))
  local last = n and math.min(floor(n), Welcome.QUEST_SCAN) or Welcome.QUEST_SCAN
  for i = 1, last do
    local info = call(api.GetInfo, i)
    if info == nil then
      if not n then break end
    elseif type(info) == "table" and not isSecret(info) then
      if not flag(info.isHeader) and not flag(info.isHidden) and not flag(info.isTask) then
        out.count = out.count + 1
        local title = str(info.title)
        if title then
          title = ns.Sanitize.field(title)
          if title == "" then title = nil end
        end
        if title and #out.names < Welcome.NAMES_MAX then out.names[#out.names + 1] = title end
        local at = title and acceptedAt(info.questID)
        if at and (not newestAt or at > newestAt) then newest, newestAt = title, at end
      end
    end
  end
  out.lastAccepted = newest
  return out
end

function Welcome.summary()
  local Live = Journal.Live
  local out = { first = state.first }
  out.name = str(call(UnitName, "player")) and ns.Sanitize.field(call(UnitName, "player")) or nil
  out.level = Live and Live.level() or nil
  local now = time()
  if state.prevEnd then
    out.lastSeenAgo = math.max(0, floor(now - state.prevEnd))
  end
  out.lastMapID = state.lastMapID
  out.lastZone = mapName(state.lastMapID)
  out.openQuests = openQuests()
  local rested = Live and Live.rested() or nil
  if rested and rested > 0 then
    out.restedXP = floor(rested)
    local _, max = Live.xp()
    if max and max > 0 then out.restedPct = floor(rested / max * 100 + 0.5) end
  end
  out.vorhabenNearby = {}
  if ns.Plans and ns.Plans.nearby then
    for i, p in ipairs(ns.Plans.nearby()) do out.vorhabenNearby[i] = { id = p.id, text = p.text, mapID = p.mapID } end
  end
  return out
end

local function inCombat()
  local v = call(InCombatLockdown)
  return flag(v)
end

function Welcome.trigger()
  local s = Welcome.summary()
  local n = 0
  for i = 1, #hooks do
    n = n + 1
    ns.Core.safe(hooks[i], s)
  end
  return n
end

local function attempt(tries)
  state.timerOn = false
  if state.fired then return end
  if inCombat() then
    if tries >= Welcome.TRIES then return end
    state.timerOn = true
    C_Timer.After(Welcome.RETRY, function() ns.Core.safe(attempt, tries + 1) end)
    return
  end
  state.fired = true
  Welcome.trigger()
end

-- timer only while a hook waits and nothing is scheduled or fired yet
schedule = function()
  if state.fired or state.timerOn or #hooks == 0 then return end
  state.timerOn = true
  C_Timer.After(Welcome.DELAY, function() ns.Core.safe(attempt, 1) end)
end

if ns.Core and ns.Core.on then
  -- PLAYER_LOGIN runs after Store.login and before the first PLAYER_ENTERING_WORLD: fallback for reload detection
  ns.Core.on("PLAYER_LOGIN", function()
    local Store = ns.Store
    local meta = Store and Store.db and Store.db.meta
    local at = type(meta) == "table" and tonumber(meta.reloadAt) or nil
    state.reloadGuess = at ~= nil and time() - at <= (Store.RELOAD_WINDOW or 600)
    state.kind, state.fired, state.timerOn = nil, false, false
  end)
  ns.Core.on("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
    if state.kind ~= nil then return end -- zone change: only the first PLAYER_ENTERING_WORLD counts
    local kind
    if isReloadingUi == true then
      kind = "reload"
    elseif isInitialLogin == true then
      kind = "login"
    elseif isInitialLogin == nil and isReloadingUi == nil then
      kind = state.reloadGuess and "reload" or "login" -- old client without args
    else
      kind = "other"
    end
    state.kind = kind
    capture()
    if kind == "login" then schedule() end
  end)
end
