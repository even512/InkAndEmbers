-- Collector 'Trail': position trail by movement.
-- Core.ticker every 3 s, no OnUpdate. A point after 22 yd of movement (UnitPosition, world yards); fallback without world position: map distance > 0.3 % (C_Map.GetPlayerMapPosition).
-- Mandatory marked points on zone change (z), death (d), takeoff (f) and landing (l). Paused in flight, continues in combat; without a readable position one TP line per pause.
local _, ns = ...
local Core, Store = ns.Core, ns.Store

local sqrt = math.sqrt

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d
end

local TICK = 3          -- seconds per tick (worst case in the size model)
local MIN_YARDS = 22    -- minimum distance in world yards (~20 m)
local MIN_MAP = 0.003   -- minimum distance as map fraction (0.3 %) when UnitPosition is missing or secret
local ZONE_DELAY = 0.5  -- seconds after ZONE_CHANGED_NEW_AREA (the map is current by then)

local Trail = {
  requires = { "C_Timer.NewTicker" },
  events = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_DEAD" },
}
local handlers = {}

-- world position in yards (x, y, instanceID); nil if secret or missing
local function worldPos()
  local y, x, _, inst = call(UnitPosition, "player")
  x, y = num(x), num(y)
  if not (x and y) then return nil end
  return x, y, num(inst)
end

local function pause(self, reason, mapID)
  if self.paused == reason then return end
  self.paused = reason
  Store.append("TP", reason, mapID)
end

-- writes a point (mapID/fx/fy optional, already read). Returns true if written.
local function record(self, mark, mapID, fx, fy)
  if not mapID then mapID, fx, fy = ns.Zone.raw() end
  if not mapID or not fx then return false end
  if not Store.trailPoint(mapID, fx, fy, mark) then return false end
  local wx, wy, wi = worldPos()
  self.last = { mapID = mapID, fx = fx, fy = fy, wx = wx, wy = wy, wi = wi }
  self.paused = nil
  return true
end

local function moved(last, mapID, fx, fy)
  if not last or last.mapID ~= mapID then return true end
  local wx, wy, wi = worldPos()
  if wx and last.wx and wi == last.wi then
    local dx, dy = wx - last.wx, wy - last.wy
    return dx * dx + dy * dy >= MIN_YARDS * MIN_YARDS
  end
  local dx, dy = fx - last.fx, fy - last.fy
  return sqrt(dx * dx + dy * dy) > MIN_MAP
end

local function tick(self)
  if call(UnitOnTaxi, "player") == true then
    if not self.flying then
      self.flying = true
      record(self, "f")
    end
    pause(self, "taxi", self.last and self.last.mapID)
    return
  end
  if self.flying then
    self.flying = false
    if record(self, "l") then return end
  end
  local mapID, fx, fy = ns.Zone.raw()
  if not mapID or not fx then
    pause(self, call(IsInInstance) == true and "instance" or "unreadable", mapID)
    return
  end
  if moved(self.last, mapID, fx, fy) then record(self, nil, mapID, fx, fy) end
end

function Trail:init()
  self.last, self.paused, self.flying = nil, nil, false
  self.handle = Core.ticker(self, TICK, tick)
end

handlers.PLAYER_ENTERING_WORLD = function(self)
  if call(UnitOnTaxi, "player") == true then return end
  local mapID, fx, fy = ns.Zone.raw()
  if mapID and fx then
    if moved(self.last, mapID, fx, fy) then record(self, nil, mapID, fx, fy) end
  else
    pause(self, call(IsInInstance) == true and "instance" or "unreadable", mapID)
  end
end

handlers.ZONE_CHANGED_NEW_AREA = function(self)
  Core.after(self, ZONE_DELAY, function(s)
    if call(UnitOnTaxi, "player") ~= true then record(s, "z") end
  end)
end

handlers.PLAYER_DEAD = function(self)
  record(self, "d")
end

function Trail:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("Trail", Trail)
