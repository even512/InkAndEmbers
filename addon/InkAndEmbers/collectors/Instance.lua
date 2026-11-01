-- Collector 'Instance': enter and leave, duration, group, bosses, deaths, kills.
-- The running visit is in snapshots.state.instance and survives reloads (IE with resumed = 1). Secret values are noted, not guessed:
-- IE.pos = 0 (position unreadable), mapLock/chatLock from C_RestrictedActions. Bosses only if the client fires ENCOUNTER_START/END; loot from FC_LOOT (green+).
local _, ns = ...
local Core, Store = ns.Core, ns.Store

local floor = math.floor

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
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

-- all return values as a list (GetInstanceInfo returns the instanceID in 8th place); nil on error
local function pack(ok, ...)
  if not ok then return nil end
  return { ... } -- gaps (nil) are allowed, read by index only
end

local function callAll(fn, ...)
  if type(fn) ~= "function" then return nil end
  return pack(pcall(fn, ...))
end

local function keep(v)
  if isSecret(v) or num(v) then return v end
  return nil
end

local CHECK_DELAY = 0.2     -- seconds after PLAYER_ENTERING_WORLD/ZONE_CHANGED_NEW_AREA
local RESUME_MAX = 4 * 3600 -- seconds: a stored visit counts as resumed this long after reload/login
local MAP_LOCK, CHAT_LOCK = 4, 5 -- C_RestrictedActions: map lock, chat lock

local function playerLevel()
  return num(call(UnitLevel, "player"))
end

local Instance = {
  requires = { "IsInInstance" },
  events = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_DEAD" },
  signals = { "FC_KILL", "FC_LOOT" },
}
local handlers = {}

local function saved()
  local char = Store.char()
  local s = char and char.snapshots and char.snapshots.state
  local v = type(s) == "table" and s.instance or nil
  return type(v) == "table" and v or nil
end

local function persist(self)
  local c = self.cur
  if c then
    Store.putSnapshot("state", "instance",
      { open = true, id = c.id, start = c.start, kills = c.kills, deaths = c.deaths, bosses = c.bosses, loot = c.loot }, true)
  else
    Store.putSnapshot("state", "instance", { open = false }, true)
  end
end

local function restriction(kind)
  local RA = C_RestrictedActions
  if type(RA) ~= "table" or isSecret(RA) then return nil end
  return keep(call(RA.GetAddOnRestrictionState, kind))
end

local function readInstance()
  local r = callAll(GetInstanceInfo)
  if not r then return nil end
  local id = num(r[8])
  return id and floor(id) or nil, str(r[2]), num(r[3]), str(r[1])
end

local function enter(self, id, kind, difficulty, name)
  local s = saved()
  local resumed = s ~= nil and s.open == true and s.id == id and num(s.start) ~= nil and time() - s.start <= RESUME_MAX
  if resumed then
    self.cur = { id = id, start = s.start, kills = num(s.kills) or 0, deaths = num(s.deaths) or 0, bosses = num(s.bosses) or 0, loot = num(s.loot) or 0 }
  else
    self.cur = { id = id, start = time(), kills = 0, deaths = 0, bosses = 0, loot = 0 }
  end
  if id and name then Store.putSnapshot("instances", id, { name = name, type = kind }) end
  persist(self)
  local _, px = ns.Zone.raw()
  Store.append("IE", id, kind, difficulty, num(call(GetNumGroupMembers)), playerLevel(), px ~= nil and 1 or 0,
    restriction(MAP_LOCK), restriction(CHAT_LOCK), resumed and 1 or 0)
  if not resumed then Core.emit("FC_INSTANCE", id, kind) end
end

local function leave(self)
  local c = self.cur
  self.cur = nil
  Store.append("IL", c.id, time() - c.start, c.kills, c.deaths, c.bosses, c.loot)
  persist(self)
end

local function check(self)
  local inside = call(IsInInstance) == true
  local id, kind, difficulty, name
  if inside then id, kind, difficulty, name = readInstance() end
  if self.first then
    self.first = false
    local s = saved()
    -- logged in outside, but a visit was still open (logout inside, crash): close without duration
    -- (also the same visit if older than RESUME_MAX: enter() then starts a new one)
    if s and s.open == true then
      local stale = num(s.start) == nil or time() - s.start > RESUME_MAX
      if not (inside and s.id == id) or stale then
        Store.append("IL", num(s.id), nil, num(s.kills), num(s.deaths), num(s.bosses), num(s.loot))
        Store.putSnapshot("state", "instance", { open = false }, true)
      end
    end
  end
  local c = self.cur
  if c and (not inside or (id and c.id ~= id)) then leave(self) end
  if inside and not self.cur then enter(self, id, kind or "none", difficulty, name) end
end

local function scheduleCheck(self)
  if self.checkOn then return end
  self.checkOn = true
  if not Core.after(self, CHECK_DELAY, function(s)
    s.checkOn = false
    check(s)
  end) then
    self.checkOn = false
  end
end

function Instance:init()
  self.cur, self.first, self.encounters = nil, true, {}
end

handlers.PLAYER_ENTERING_WORLD = scheduleCheck
handlers.ZONE_CHANGED_NEW_AREA = scheduleCheck

handlers.FC_KILL = function(self)
  local c = self.cur
  if not c then return end
  c.kills = c.kills + 1
  persist(self)
end

-- green and better (quality 2); unknown quality counts
handlers.FC_LOOT = function(self, _, count, quality)
  local c = self.cur
  if not c then return end
  if quality ~= nil and (num(quality) or 0) < 2 then return end
  c.loot = c.loot + (num(count) or 1)
  persist(self)
end

handlers.PLAYER_DEAD = function(self)
  local c = self.cur
  if not c then return end
  c.deaths = c.deaths + 1
  persist(self)
end

handlers.ENCOUNTER_START = function(self, encounterID, name)
  local id = num(encounterID)
  if not id then return end
  id = floor(id)
  self.encounters[id] = GetTime()
  name = str(name)
  if name then Store.putSnapshot("encounters", id, { name = name }) end
end

handlers.ENCOUNTER_END = function(self, encounterID, name, difficultyID, groupSize, success)
  local id = num(encounterID)
  local started = id and self.encounters[floor(id)]
  if id then
    id = floor(id)
    self.encounters[id] = nil
    name = str(name)
    if name then Store.putSnapshot("encounters", id, { name = name }) end
  end
  local ok
  if isSecret(success) then
    ok = success
  elseif success == 1 or success == true then
    ok = 1
  elseif success == 0 or success == false then
    ok = 0
  end
  local c = self.cur
  Store.append("IB", id or keep(encounterID), ok, started and floor(GetTime() - started) or nil, keep(groupSize),
    keep(difficultyID), c and c.id)
  if ok == 1 then
    if c then
      c.bosses = c.bosses + 1
      persist(self)
    end
    Core.emit("FC_BOSS", id)
  end
end

function Instance:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("Instance", Instance)
