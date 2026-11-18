-- Waypoint (Werkauftrag "Zum Lehrer · Wegpunkt setzen", usable anywhere): sets the game's own map pin and the arrow on it.
--   Waypoint.set(mapID, x, y)  -> true | nil, reason   (x, y 0..1; ONLY from a click of the player, never from a timer or event)
--   Waypoint.clear()           -> true | false
--   Waypoint.canSet(mapID)     -> bool
-- API: C_Map.CanSetUserWaypointOnMap, C_Map.SetUserWaypoint(UiMapPoint), C_SuperTrack.SetSuperTrackedUserWaypoint(true); the point
-- table is built by hand ({ uiMapID, position = CreateVector2D(x, y) | { x, y }, z = 0 }), UiMapPoint.CreateFromCoordinates is used
-- when the client has it. Every call in pcall; nothing in combat. Reasons: "kampf" | "keine-api" | "karte" | "ort" | "fehler".
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Waypoint = {}
Journal.Waypoint = Waypoint

local floor = math.floor

local T = ns.Locale.ns("Waypoint", {
  set = "Wegpunkt gesetzt: %s",
  errCombat = "Im Kampf geht das nicht.",
  errApi = "Wegpunkte gibt es in diesem Spiel nicht.",
  errMap = "Auf dieser Karte lässt sich kein Wegpunkt setzen.",
  errPlace = "Der Ort ist unbekannt.",
  errFail = "Der Wegpunkt ließ sich nicht setzen.",
})
Waypoint.TEXT = T

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function api()
  local m = rawget(_G, "C_Map")
  if type(m) ~= "table" or isSecret(m) or type(m.SetUserWaypoint) ~= "function" then return nil end
  return m
end

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, r = pcall(InCombatLockdown)
  return not ok or r == true
end

local function point(mapID, x, y)
  local U = rawget(_G, "UiMapPoint")
  if type(U) == "table" and type(U.CreateFromCoordinates) == "function" then
    local ok, p = pcall(U.CreateFromCoordinates, mapID, x, y)
    if ok and type(p) == "table" then return p end
  end
  local pos
  local cv = rawget(_G, "CreateVector2D")
  if type(cv) == "function" then
    local ok, v = pcall(cv, x, y)
    if ok then pos = v end
  end
  return { uiMapID = mapID, position = pos or { x = x, y = y }, z = 0 }
end

function Waypoint.canSet(mapID)
  local m = api()
  mapID = num(mapID)
  if not (m and mapID) then return false end
  if type(m.CanSetUserWaypointOnMap) ~= "function" then return true end
  local ok, r = pcall(m.CanSetUserWaypointOnMap, floor(mapID))
  return ok and r == true
end

function Waypoint.set(mapID, x, y)
  if inCombat() then return nil, "kampf" end
  local m = api()
  if not m then return nil, "keine-api" end
  mapID, x, y = num(mapID), num(x), num(y)
  if not (mapID and mapID >= 1 and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1) then return nil, "ort" end
  mapID = floor(mapID)
  if not Waypoint.canSet(mapID) then return nil, "karte" end
  local ok, r = pcall(m.SetUserWaypoint, point(mapID, x, y))
  if not ok or r == false then return nil, "fehler" end
  local st = rawget(_G, "C_SuperTrack")
  if type(st) == "table" and type(st.SetSuperTrackedUserWaypoint) == "function" then pcall(st.SetSuperTrackedUserWaypoint, true) end
  return true
end

function Waypoint.clear()
  local m = rawget(_G, "C_Map")
  if type(m) ~= "table" or type(m.ClearUserWaypoint) ~= "function" then return false end
  return (pcall(m.ClearUserWaypoint))
end

function Waypoint.reasonText(reason)
  if reason == "kampf" then return T.errCombat end
  if reason == "keine-api" then return T.errApi end
  if reason == "karte" then return T.errMap end
  if reason == "ort" then return T.errPlace end
  return T.errFail
end
