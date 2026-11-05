-- Collector 'Gear': equipment changes per slot, snapshot per level-up, first-bag milestone.
-- Changes: PLAYER_EQUIPMENT_CHANGED + GetInventoryItemLink (item key instead of link); during the first SETTLE seconds after start only the state is remembered; then the worn items are compared with the last noted state (snapshots.state.gear) and differences are noted afterwards (no moments).
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

-- slot -> { key, quality, name, id, link }; nil = slot is empty.
-- Second result true = not readable (API error, secret value, link text that cannot be read): the slot counts as unchanged, never as empty.
local function readSlot(slot)
  local ok, link = pcall(GetInventoryItemLink, "player", slot)
  if not ok or isSecret(link) then return nil, true end
  if link == nil or link == "" then return nil end
  if type(link) ~= "string" then return nil, true end
  local id, bonus, quality, name = Patterns.itemLink(link)
  if not id then return nil, true end
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

-- remembers what is worn (self.worn); a slot that cannot be read keeps its previous value and is listed in self.unreadable
local function scan(self)
  local before = self.worn or {}
  self.worn, self.unreadable = {}, {}
  local function take(slot)
    local s, bad = readSlot(slot)
    if bad then
      self.unreadable[slot] = true
      self.worn[slot] = before[slot]
    elseif s then
      self.worn[slot] = s.key
    end
  end
  for slot = 1, MAX_SLOT do take(slot) end
  for _, slot in ipairs(bagSlots()) do
    if slot > MAX_SLOT and slot > 0 then take(slot) end
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

local function isBag(itemID)
  local r = callAll(C_Item and C_Item.GetItemInfoInstant, itemID)
  local class = r and num(r[6])
  return class == CLASS_CONTAINER or class == CLASS_QUIVER
end

-- Noted state (self.noted: slot -> item key, what the last GW line says per slot). Persisted in snapshots.state.gear
-- = { set = 1, slots = { [slot] = key } } after every GW line, so that the login check (reconcile) can compare against it.
local function persistNoted(self)
  if type(self.noted) ~= "table" then return end
  Store.putSnapshot("state", "gear", { set = 1, slots = self.noted }, true)
end

local function loadNoted()
  local char = Store.char()
  local st = char and type(char.snapshots) == "table" and char.snapshots.state
  local g = type(st) == "table" and st.gear
  if type(g) ~= "table" or g.set ~= 1 then return nil end
  local out = {}
  if type(g.slots) == "table" then
    for k, v in pairs(g.slots) do
      if type(k) == "number" and k >= 1 and k <= MAX_SLOT and type(v) == "string" and v ~= "" then out[k] = v end
    end
  end
  return out
end

-- one-time rebuild when no stored state exists yet (first start after the update): the latest GW line per slot from the
-- own block log, for slots without a line the newest gear snapshot (slots 1-19 it lists), remaining slots count as unchanged.
-- nil = no history at all (new character).
local function rebuildNoted(worn)
  local char = Store.char()
  if not char then return nil end
  local noted, seen, found = {}, {}, false
  local log = char.log
  if type(log) == "table" then
    for i = #log, 1, -1 do
      local entry = log[i]
      if type(entry) == "string" and string.find(entry, "~GW~", 1, true) then
        local lines = {}
        for line in string.gmatch(entry, "[^\n]+") do lines[#lines + 1] = line end
        for j = #lines, 1, -1 do
          local slot, item = string.match(lines[j], "^%-?%d+~GW~(%d+)~?([^~]*)")
          slot = tonumber(slot)
          if slot and slot >= 1 and slot <= MAX_SLOT and not seen[slot] then
            seen[slot], found = true, true
            if item ~= "" then noted[slot] = item end
          end
        end
      end
    end
  end
  local gear = type(char.snapshots) == "table" and char.snapshots.gear
  if type(gear) == "table" then
    local best, bestLevel
    for level, v in pairs(gear) do
      if type(level) == "number" and type(v) == "table" and (not bestLevel or level > bestLevel) then best, bestLevel = v, level end
    end
    if best then
      for slot = 1, GEAR_SLOTS do
        local v = best[slot]
        if not seen[slot] and type(v) == "string" and v ~= "" then
          seen[slot], found = true, true
          noted[slot] = v
        end
      end
    end
  end
  if not found then return nil end
  for slot = 1, MAX_SLOT do
    if not seen[slot] then noted[slot] = worn[slot] end
  end
  return noted
end

-- GW line for a slot; updates the noted state. moments = false for the login check (no first-blue/epic/bag again).
local function recordSlot(self, slot, s, old, moments)
  local newKey = s and s.key or nil
  if s then Store.noteItem(s.id, s.name, s.quality) end
  local mapID = ns.Zone.here()
  Store.append("GW", slot, newKey, s and ilvlOf(s.link) or nil, old, playerLevel(), mapID)
  if type(self.noted) ~= "table" then self.noted = {} end
  self.noted[slot] = newKey
  persistNoted(self)
  if s and moments then
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

-- after SETTLE: compare what is worn with the noted state; a difference (e.g. a crafted item whose link was not readable
-- before) is noted afterwards (time = now, prev = noted state). No history: only remember. Unreadable slots stay untouched.
local function reconcile(self)
  local noted = loadNoted() or rebuildNoted(self.worn)
  if not noted then
    self.noted = {}
    for slot, key in pairs(self.worn) do
      if not self.unreadable[slot] then self.noted[slot] = key end
    end
    persistNoted(self)
    return
  end
  self.noted = noted
  for slot = 1, MAX_SLOT do
    if not self.unreadable[slot] then
      local new, old = self.worn[slot], noted[slot]
      if new ~= old then
        local s, bad = readSlot(slot)
        if not bad and (s and s.key or nil) == new then recordSlot(self, slot, s, old, false) end
      end
    end
  end
  persistNoted(self)
end

function Gear:init()
  self.born, self.settled = GetTime(), false
  scan(self)
  Core.after(self, SETTLE, function(s)
    scan(s)
    s.settled = true
    local ok = pcall(reconcile, s)
    if not ok then Store.noteLimit("gear_reconcile") end
    snapshot(s) -- first start: gear of the current level (later calls do not write again)
  end)
end

-- shared comparison of a slot with self.worn (several events must not double-report)
local function applySlot(self, slot)
  local s, bad = readSlot(slot)
  if bad then return end -- unreadable: slot stays as it was, no phantom removal
  local newKey = s and s.key or nil
  local old = self.worn[slot]
  if newKey == old then return end
  self.worn[slot] = newKey
  if not self.settled then return end
  recordSlot(self, slot, s, old, true)
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
