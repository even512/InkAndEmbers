-- Collector 'Pet': the companion creature of the player (hunter pet, warlock demon, death knight ghoul ...). One PE line when the creature
-- (GUID) changes: summon, dismiss, change, new (first time seen, remembered in snapshots.pets[npcID]) or tame (right after the taming spell).
-- Forever adds loyalty and happiness (C_PetInfo) and the stable slots; every API runs under pcall, anything unreadable stays empty
-- (secret values become '?' in the line). UNIT_PET is debounced, so a burst of events costs one read.
local _, ns = ...
local Core, Store = ns.Core, ns.Store

local floor = math.floor
local match = string.match

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
  local ok, a = pcall(fn, ...)
  if not ok then return nil end
  return a
end

-- value for a log line: readable numbers, texts and booleans stay, secret values stay ('?' in the line), everything else is dropped
local function raw(v)
  if isSecret(v) then return v end
  if num(v) or str(v) or type(v) == "boolean" then return v end
  return nil
end

local SETTLE = 0.5        -- seconds: UNIT_PET events are batched this long, then one read
local READY_DELAY = 3     -- seconds after start: the pet at login is only remembered (no summon line); first sight still writes 'new'
local TAME_SPELL = 1515   -- Tame Beast
local PETS_MAX = 500      -- snapshots.pets entries; beyond it nothing new is remembered (diag.limits.snapshots.pets)
local TAME_TTL = 30       -- seconds: a new pet this soon after the taming spell counts as tamed

local Pet = {
  requires = { "UnitGUID" }, -- UnitExists is read under pcall: without it there is simply no pet
  unitEvents = { UNIT_PET = { "player" }, UNIT_SPELLCAST_SUCCEEDED = { "player" } },
}
local handlers = {}

-- npcID of a creature or pet GUID (hunter and warlock pets: Pet-0-<server>-<instance>-<zoneUID>-<npcID>-<spawnUID>); nil for anything else
local function npcIdOf(guid)
  local kind, id = match(guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if (kind == "Creature" or kind == "Vehicle" or kind == "Pet") and id then return tonumber(id) end
  return nil
end

-- the current pet: false = none, nil = not readable (no change), else { key, npcID, name, family, level, loyalty, happiness }
local function readPet()
  local exists = call(UnitExists, "pet")
  if isSecret(exists) then return nil end
  if exists ~= true then return false end
  local guid = call(UnitGUID, "pet")
  local p = {}
  if isSecret(guid) then
    p.key, p.npcID = "?", guid
  elseif str(guid) then
    p.key, p.npcID = guid, npcIdOf(guid)
  else
    return nil
  end
  p.name = raw(call(UnitName, "pet"))
  p.family = raw(call(UnitCreatureFamily, "pet"))
  p.level = raw(call(UnitLevel, "pet"))
  local PI = C_PetInfo
  if type(PI) == "table" and not isSecret(PI) then
    p.loyalty = raw(call(PI.GetPetLoyalty))
    p.happiness = raw(call(PI.GetPetHappiness))
  end
  return p
end

local function write(how, p)
  Store.append("PE", how, p.npcID, p.name, p.family, p.level, p.loyalty, p.happiness)
end

-- remembers a creature the first time it is seen (snapshots.pets[npcID], written once); true = new
local function notePet(p)
  local id, name = num(p.npcID), str(p.name)
  if not id or not name then return false end
  local snaps = Store.char() and Store.char().snapshots
  local group = type(snaps) == "table" and snaps.pets or nil
  if type(group) == "table" and group[floor(id)] == nil then
    local n = 0
    for _ in pairs(group) do n = n + 1 end
    if n >= PETS_MAX then
      Store.noteLimit("snapshots.pets")
      return false
    end
  end
  return Store.putSnapshot("pets", floor(id), { name = name, family = str(p.family) })
end

local function check(self)
  self.timer = false
  local p = readPet()
  if p == nil then return end
  local cur = self.cur
  if p == false then
    if cur and self.ready then write("dismiss", cur) end
    self.cur = nil
    return
  end
  if cur and cur.key == p.key then
    self.cur = p -- same creature: only refresh the values for a later dismiss
    return
  end
  self.cur = p
  local isNew = notePet(p)
  local tamed = self.tameAt ~= nil and GetTime() - self.tameAt <= TAME_TTL
  local how
  if self.ready and tamed then
    how = "tame"
  elseif isNew then
    how = "new"
  elseif not self.ready then
    how = nil
  elseif cur then
    how = "change"
  else
    how = "summon"
  end
  if tamed and self.ready then self.tameAt = nil end
  if how then write(how, p) end
end

function Pet:init()
  self.cur, self.ready, self.timer, self.tameAt = nil, false, false, nil
  Core.after(self, READY_DELAY, function(s)
    check(s) -- baseline: the pet at login is only remembered (a first sight still writes 'new')
    s.ready = true
    -- stable slots (Forever): written once per start, replaces the earlier value
    local SI = C_StableInfo
    local slots = type(SI) == "table" and not isSecret(SI) and num(call(SI.GetNumStableSlots)) or nil
    if slots then Store.putSnapshot("state", "stable", { slots = floor(slots) }, true) end
  end)
end

handlers.UNIT_PET = function(self, unit)
  if unit ~= "player" or self.timer then return end
  self.timer = true
  if not Core.after(self, SETTLE, check) then self.timer = false end
end

handlers.UNIT_SPELLCAST_SUCCEEDED = function(self, unit, _, spellID)
  if unit == "player" and num(spellID) == TAME_SPELL then self.tameAt = GetTime() end
end

function Pet:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("Pet", Pet)
