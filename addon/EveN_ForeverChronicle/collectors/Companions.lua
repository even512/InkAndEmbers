-- Collector 'Companions': group/raid members get a WB line on joining and a WV line on leaving (name-realm, class, race, level, map, position).
-- Read only out of combat, batched (GROUP_ROSTER_UPDATE fires in bursts). A member with a secret field is skipped, never guessed, and added once readable;
-- no leaves are written while one was unreadable. The roster survives a reload (snapshots.state.companions); logout closes everyone (WV why = logout).
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
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  return r[2], r[3], r[4]
end

local COMPANION_DELAY = 2.0 -- seconds: batches GROUP_ROSTER_UPDATE
local MAX_UNITS_RAID, MAX_UNITS_PARTY = 40, 4
local NAME_MAX = 64

local Companions = {
  requires = { "UnitName", "UnitClass", "UnitRace", "UnitLevel", "IsInGroup", "GetNumGroupMembers" },
  events = { "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT" },
}
local handlers = {}

-- own realm as name part: GetNormalizedRealmName (no spaces, as the client uses for name-realm), else GetRealmName
local function ownRealm()
  local r = str(call(GetNormalizedRealmName))
  if not r then
    r = str(call(GetRealmName))
    if r then r = string.gsub(r, "[%s%-]", "") end
  end
  return r
end

local function inCombat()
  local v = call(InCombatLockdown)
  return not isSecret(v) and v == true
end

local function savedState()
  local char = Store.char()
  local st = char and char.snapshots and char.snapshots.state
  local v = type(st) == "table" and st.companions or nil
  return type(v) == "table" and v or nil
end

-- reads a unit. Returns info table | nil, reason ('none' = no unit, 'secret' = restricted, 'unknown' = not loaded yet)
local function readUnit(unit)
  local exists = call(UnitExists, unit)
  if isSecret(exists) then return nil, "secret" end
  if exists ~= nil and exists ~= true then return nil, "none" end
  local name, realm
  if type(UnitFullName) == "function" then
    name, realm = call(UnitFullName, unit)
  else
    name, realm = call(UnitName, unit)
  end
  if isSecret(name) or isSecret(realm) then return nil, "secret" end
  if name == nil and exists ~= true then return nil, "none" end
  name = str(name)
  local unknown = _G.UNKNOWNOBJECT
  if not name or (type(unknown) == "string" and not isSecret(unknown) and name == unknown) then return nil, "unknown" end
  realm = str(realm) or ownRealm()
  local full = realm and (name .. "-" .. realm) or name
  full = ns.Sanitize.cut(ns.Sanitize.field(full), NAME_MAX)
  if full == "" then return nil, "unknown" end

  local _, class = call(UnitClass, unit)
  if isSecret(class) then return nil, "secret" end
  local _, race = call(UnitRace, unit)
  if isSecret(race) then return nil, "secret" end
  local level = call(UnitLevel, unit)
  if isSecret(level) then return nil, "secret" end
  level = num(level)
  if level and level <= 0 then level = nil end
  class = str(class) and ns.Sanitize.field(class) or nil
  race = str(race) and ns.Sanitize.field(race) or nil
  if class == "" then class = nil end
  if race == "" then race = nil end
  return { key = full, name = full, class = class, race = race, level = level and floor(level) or nil }
end

-- all readable members (not you). Returns list, complete (false if at least one unit was secret)
local function roster()
  local raid = call(IsInRaid)
  raid = not isSecret(raid) and raid == true
  local prefix, max = raid and "raid" or "party", raid and MAX_UNITS_RAID or MAX_UNITS_PARTY
  local list, complete = {}, true
  for i = 1, max do
    local info, why = readUnit(prefix .. i)
    if info then
      local isMe = call(UnitIsUnit, prefix .. i, "player")
      if not (not isSecret(isMe) and isMe == true) then list[#list + 1] = info end
    elseif why == "secret" or why == "unknown" then
      complete = false
    end
  end
  return list, complete
end

local function isGrouped()
  local g = call(IsInGroup)
  if isSecret(g) then return nil end
  if g == nil then
    local n = num(call(GetNumGroupMembers))
    return n ~= nil and n > 1
  end
  return g == true
end

function Companions:init()
  self.members = {}
  self.timer = false
  self.deferred = false
  self.first = true
end

local function persist(self)
  local list = {}
  for key in pairs(self.members) do list[#list + 1] = key end
  if #list == 0 and not self.persisted then return end
  self.persisted = #list > 0
  local t = {}
  for _, key in ipairs(list) do t[key] = 1 end
  Store.putSnapshot("state", "companions", { open = #list > 0, session = Store.session, members = t }, true)
end

local function lineFor(code, info, mapID, x, y, why)
  Store.append(code, info.name, info.class, info.race, info.level, mapID, x, y, why)
end

-- first pass after a reload: adopt members of the same session silently (no new join)
local function adoptSaved(self, list)
  local saved = self.first and savedState() or nil
  self.first = false
  if not saved or saved.open ~= true or saved.session ~= Store.session or type(saved.members) ~= "table" then return end
  for _, info in ipairs(list) do
    if saved.members[info.key] ~= nil then self.members[info.key] = info end
  end
end

function Companions.refresh(self)
  if not Store.ready() then return end
  if inCombat() then
    self.deferred = true
    return
  end
  self.deferred = false
  local grouped = isGrouped()
  if grouped == nil then return end -- group state secret: change nothing
  local mapID, x, y = ns.Zone.here()
  if not grouped then
    adoptSaved(self, {})
    for key, info in pairs(self.members) do
      lineFor("WV", info, mapID, x, y, "end")
      self.members[key] = nil
    end
    persist(self)
    return
  end
  local list, complete = roster()
  adoptSaved(self, list)
  local present = {}
  for _, info in ipairs(list) do
    present[info.key] = true
    local old = self.members[info.key]
    if not old then
      self.members[info.key] = info
      lineFor("WB", info, mapID, x, y)
    else
      old.level, old.class, old.race = info.level or old.level, old.class or info.class, old.race or info.race
    end
  end
  if complete then
    for key, info in pairs(self.members) do
      if not present[key] then
        lineFor("WV", info, mapID, x, y, "left")
        self.members[key] = nil
      end
    end
  end
  persist(self)
end

local function request(self)
  if self.timer then return end
  if inCombat() then
    self.deferred = true
    return
  end
  self.timer = true
  if not Core.after(self, COMPANION_DELAY, function(s)
    s.timer = false
    s.refresh(s)
  end) then
    self.timer = false
  end
end

handlers.GROUP_ROSTER_UPDATE = function(self)
  request(self)
end

handlers.PLAYER_REGEN_ENABLED = function(self)
  if self.deferred then request(self) end
end

-- logout (no reload): everyone still open is closed. On a reload the list stays (snapshots.state.companions).
handlers.PLAYER_LOGOUT = function(self)
  if Store.reloadPending() then return end
  local mapID, x, y = ns.Zone.here()
  local any = false
  for key, info in pairs(self.members) do
    lineFor("WV", info, mapID, x, y, "logout")
    self.members[key] = nil
    any = true
  end
  if any then persist(self) end
end

function Companions:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("Companions", Companions)
