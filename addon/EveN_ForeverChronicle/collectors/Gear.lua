-- Collector 'Gear': equipment changes per slot, snapshot per level-up, first-bag milestone.
-- Changes: PLAYER_EQUIPMENT_CHANGED + GetInventoryItemLink (item key instead of link); during the first SETTLE seconds after start only the state is remembered.
-- Snapshot: snapshots.gear[level] = { [slot] = item key, ilvl = average }, 1.5 s after level-up and once at first start. Equipping blue/purple items counts as 'first blue/purple' (FC_MOMENT).
local _, ns = ...
local Core, Store, Patterns = ns.Core, ns.Store, ns.Patterns

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
  local ok, a, b, c = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c
end

local function callAll(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  table.remove(r, 1)
  return r
end

local function playerLevel()
  return num(call(UnitLevel, "player"))
end

local SETTLE = 5          -- seconds after start: gear is still loading, only remember the state
local SNAPSHOT_DELAY = 1.5 -- seconds after level-up
local GEAR_SLOTS = 19     -- INVSLOT 1-19: equipment
local MAX_SLOT = 40       -- highest slot considered (bag slots are above)
local CLASS_CONTAINER, CLASS_QUIVER = 1, 11

local Gear = {
  requires = { "GetInventoryItemLink" },
  events = { "PLAYER_EQUIPMENT_CHANGED", "BAG_CONTAINER_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP" },
}
local handlers = {}

-- slot -> item key, quality, name, itemID, link
local function readSlot(slot)
  local link = call(GetInventoryItemLink, "player", slot)
  if not str(link) then return nil end
  local id, bonus, quality, name = Patterns.itemLink(link)
  if not id then return nil end
  if quality == nil then quality = num(call(GetInventoryItemQuality, "player", slot)) end
  return { key = Patterns.itemKey(id, bonus), id = id, quality = quality, name = name, link = link }
end

local function ilvlOf(link)
  local r = callAll(C_Item and C_Item.GetDetailedItemLevelInfo, link)
  local v = r and num(r[1])
  return v and floor(v) or nil
end

-- inventory slots of the bags (Retail: ContainerIDToInventoryID(1..5) = 31..35; old clients: fixed slots 20-23)
local FALLBACK_BAG_SLOTS = { 20, 21, 22, 23 }
local function bagSlots()
  local out = {}
  local fn = C_Container and C_Container.ContainerIDToInventoryID
  if type(fn) == "function" then
    for id = 1, 5 do
      local slot = num(call(fn, id))
      if slot then out[#out + 1] = floor(slot) end
    end
  end
  if #out == 0 then return FALLBACK_BAG_SLOTS end
  return out
end

local function scan(self)
  self.worn = {}
  for slot = 1, MAX_SLOT do
    local s = readSlot(slot)
    if s then self.worn[slot] = s.key end
  end
  for _, slot in ipairs(bagSlots()) do
    if slot > MAX_SLOT and slot > 0 then
      local s = readSlot(slot)
      if s then self.worn[slot] = s.key end
    end
  end
end

local function snapshot(self, level)
  level = num(level) or playerLevel()
  if not level then return end
  local values = {}
  for slot = 1, GEAR_SLOTS do
    local s = readSlot(slot)
    if s then
      values[slot] = s.key
      Store.noteItem(s.id, s.name, s.quality)
    end
  end
  local avg = callAll(GetAverageItemLevel)
  if avg then
    local equipped = num(avg[2]) or num(avg[1])
    if equipped then values.ilvl = floor(equipped) end
  end
  if next(values) then Store.putSnapshot("gear", floor(level), values) end
end

function Gear:init()
  self.born, self.settled = GetTime(), false
  scan(self)
  Core.after(self, SETTLE, function(s)
    scan(s)
    s.settled = true
    snapshot(s) -- first start: gear of the current level (later calls do not write again)
  end)
end

local function isBag(itemID)
  local r = callAll(C_Item and C_Item.GetItemInfoInstant, itemID)
  local class = r and num(r[6])
  return class == CLASS_CONTAINER or class == CLASS_QUIVER
end

-- shared comparison of a slot with self.worn (several events must not double-report)
local function applySlot(self, slot)
  local s = readSlot(slot)
  local newKey = s and s.key or nil
  local old = self.worn[slot]
  if newKey == old then return end
  self.worn[slot] = newKey
  if not self.settled then return end
  if s then Store.noteItem(s.id, s.name, s.quality) end
  local mapID = ns.Zone.here()
  Store.append("GW", slot, newKey, s and ilvlOf(s.link) or nil, old, playerLevel(), mapID)
  if s then
    if s.quality == 3 then
      Core.emit("FC_MOMENT", "first_blue", s.id, 3, "item", true)
    elseif s.quality ~= nil and s.quality >= 4 then
      Core.emit("FC_MOMENT", "first_epic", s.id, s.quality, "item", true)
    end
    if slot > GEAR_SLOTS and isBag(s.id) then
      Core.emit("FC_MOMENT", "first_bag", s.id, nil, nil, true)
    end
  end
end

handlers.PLAYER_EQUIPMENT_CHANGED = function(self, slot)
  slot = num(slot)
  if not slot then return end
  slot = floor(slot)
  if slot < 1 or slot > MAX_SLOT then return end
  applySlot(self, slot)
end

-- bag change: since Dragonflight BAG_CONTAINER_UPDATE / BAG_UPDATE_DELAYED fire instead of (or besides)
-- PLAYER_EQUIPMENT_CHANGED; the bag slots are read directly here.
local function checkBags(self)
  if not self.worn then return end
  for _, slot in ipairs(bagSlots()) do
    -- secret link: leave the slot unchanged instead of writing a phantom removal
    if slot > 0 and not isSecret(call(GetInventoryItemLink, "player", slot)) then applySlot(self, slot) end
  end
end
handlers.BAG_CONTAINER_UPDATE = checkBags
handlers.BAG_UPDATE_DELAYED = checkBags

handlers.PLAYER_LEVEL_UP = function(self, level)
  Core.after(self, SNAPSHOT_DELAY, function(s) snapshot(s, level) end)
end

function Gear:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("Gear", Gear)
