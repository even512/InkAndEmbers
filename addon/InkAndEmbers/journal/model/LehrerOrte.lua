-- LehrerOrte (Werkauftrag, WoW Forever): where the profession trainers stand. Two sources, own visits first:
--   1. own visits: chars[guid].werkTrainers[npcID] = { line, mapID, x, y (0..1), name, at } (collectors/LehrerBesuch.lua writes them
--      when a profession trainer window opens: the player stands next to the trainer);
--   2. QuestieDB: the data add-on InkAndEmbers_Data (LoadOnDemand, same load as the to-do lists through Journal.TodoData), file
--      ProfTrainers.lua, global EveNChronicleProfTrainerData (scripts/build-prof-trainers.mjs; format there), adopted once.
-- Choice (LehrerOrte.nearest): trainers of the skill line, of the own faction (or both), who teach up to the needed skill (cap 0 =
-- unknown counts as fitting), no specialist unless asked; the nearest one on the same continent (distance through
-- Plans.distance), else one of another continent (own visits first, then the lowest npc id). Loaded in every client mode (also in
-- tests without the module Crafting); names are foreign text: Sanitize.display.
--   LehrerOrte.list(line)                 -> { entry } (merged, sorted by npc id)
--   LehrerOrte.nearest(line, opts)        -> entry | nil, reason ("nodata" | "none")
--   LehrerOrte.pick(entries, ctx)         -> entry | nil (pure: ctx.dist(entry) -> meters | nil, ctx.continent(mapID), ctx.here)
--   entry = { npc, line, cap, faction, special, mapID, x, y (0..1), name, own (visited), dist (meters, nearest only) }
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local LehrerOrte = {}
Journal.LehrerOrte = LehrerOrte

local floor, tonumber, gmatch, match = math.floor, tonumber, string.gmatch, string.match

LehrerOrte.GLOBAL = "EveNChronicleProfTrainerData"
LehrerOrte.OWN_MAX = 60      -- own visits kept per character
LehrerOrte.NAME_MAX = 60

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function posInt(v)
  v = num(v)
  if not v or v < 1 or v > 2147483647 then return nil end
  return floor(v)
end

local function coord(v)
  v = num(v)
  if not v or v < 0 or v > 1 then return nil end
  return v
end

local function display(s)
  if isSecret(s) or type(s) ~= "string" or s == "" then return nil end
  local S = ns.Sanitize
  s = S and S.display and S.display(s, LehrerOrte.NAME_MAX) or s
  return s ~= "" and s or nil
end

-- Data (load on demand, adopt once) --------------------------------------------------------------------------------------------

local S = { data = nil, parsed = nil }
LehrerOrte._state = S

local function adopt()
  local g = rawget(_G, LehrerOrte.GLOBAL)
  if type(g) ~= "table" then return false end
  _G[LehrerOrte.GLOBAL] = nil
  if type(g.trainers) ~= "string" then return false end
  S.data = g
  S.parsed = nil
  return true
end

function LehrerOrte.load()
  if S.data then return true end
  if adopt() then return true end
  local TD = Journal.TodoData
  if TD and type(TD.available) == "function" then pcall(TD.available, "item") end
  return adopt()
end

local LINE = "^(%d+)\t(%d+)\t(%d+)\t([AH]?)\t(s?)\t([^\t]*)\t([^\t]*)\t([^\t]*)$"

local function english()
  local L = ns.Locale
  return type(L) == "table" and L.active ~= nil and L.active ~= "deDE"
end

-- first point of the first map of "<map>:<x>,<y>;...|<map>:..." (x/y 0..100) -> mapID, x, y (0..1); all points as a list
local function points(loc)
  local list = {}
  for part in gmatch(loc, "[^|]+") do
    local m, rest = match(part, "^(%d+):(.+)$")
    m = tonumber(m)
    if m and rest then
      for x, y in gmatch(rest, "([%d%.]+),([%d%.]+)") do
        x, y = tonumber(x), tonumber(y)
        if x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100 then list[#list + 1] = { mapID = m, x = x / 100, y = y / 100 } end
      end
    end
  end
  return list
end

local function parsed()
  if S.parsed then return S.parsed end
  local out = {}
  local text = S.data and S.data.trainers
  if type(text) == "string" then
    local en = english()
    for row in gmatch(text, "[^\n]+") do
      local id, line, cap, fac, kind, loc, de, enName = match(row, LINE)
      if id then
        local pts = points(loc)
        if #pts > 0 then
          local e = { npc = tonumber(id), line = tonumber(line), cap = tonumber(cap) or 0, faction = fac ~= "" and fac or nil,
            special = kind == "s" or nil, points = pts, mapID = pts[1].mapID, x = pts[1].x, y = pts[1].y,
            name = display(en and enName ~= "" and enName or de) or display(de) }
          local l = out[e.line]
          if not l then l = {} out[e.line] = l end
          l[#l + 1] = e
        end
      end
    end
  end
  S.parsed = out
  return out
end

-- Own visits ---------------------------------------------------------------------------------------------------------------------

local function ownTable(create)
  local St = ns.Store
  local c = St and type(St.char) == "function" and St.char() or nil
  if type(c) ~= "table" then return nil end
  if type(c.werkTrainers) ~= "table" then
    if not create then return nil end
    c.werkTrainers = {}
  end
  return c.werkTrainers
end

-- remembers a profession trainer the player is standing at -> true | false
function LehrerOrte.remember(npc, line, mapID, x, y, name)
  npc, line, mapID, x, y = posInt(npc), posInt(line), posInt(mapID), coord(x), coord(y)
  if not (npc and line and mapID and x and y) then return false end
  local t = ownTable(true)
  if not t then return false end
  if t[npc] == nil then
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    if n >= LehrerOrte.OWN_MAX then
      -- the oldest visit makes room
      local oldK, oldAt
      for k, v in pairs(t) do
        local at = type(v) == "table" and num(v.at) or 0
        if not oldAt or at < oldAt then oldK, oldAt = k, at end
      end
      if oldK then t[oldK] = nil end
    end
  end
  local ok, now = pcall(time)
  t[npc] = { line = line, mapID = mapID, x = x, y = y, name = display(name), at = ok and floor(now) or 0 }
  return true
end

-- Lists --------------------------------------------------------------------------------------------------------------------------

-- data entry of an npc (any line) -> entry | nil
function LehrerOrte.dataOf(npc)
  npc = posInt(npc)
  if not npc then return nil end
  LehrerOrte.load()
  for _, l in pairs(parsed()) do
    for _, e in ipairs(l) do if e.npc == npc then return e end end
  end
  return nil
end

function LehrerOrte.list(line)
  line = posInt(line)
  local out, seen = {}, {}
  if not line then return out end
  local own = ownTable(false) or {}
  LehrerOrte.load()
  local data = parsed()[line] or {}
  local byNpc = {}
  for _, e in ipairs(data) do byNpc[e.npc] = e end
  for npc, v in pairs(own) do
    if type(npc) == "number" and type(v) == "table" and posInt(v.line) == line and posInt(v.mapID) and coord(v.x) and coord(v.y) then
      local d = byNpc[npc]
      out[#out + 1] = { npc = npc, line = line, cap = d and d.cap or 0, faction = d and d.faction or nil, special = d and d.special or nil,
        mapID = floor(v.mapID), x = v.x, y = v.y, name = display(v.name) or (d and d.name) or nil, own = true }
      seen[npc] = true
    end
  end
  for _, e in ipairs(data) do
    if not seen[e.npc] then
      out[#out + 1] = { npc = e.npc, line = e.line, cap = e.cap, faction = e.faction, special = e.special, mapID = e.mapID, x = e.x, y = e.y,
        name = e.name, points = e.points }
    end
  end
  table.sort(out, function(a, b) return a.npc < b.npc end)
  return out
end

-- pure choice. ctx = { faction ("A" | "H" | nil), skill (needed skill | nil), special (true = specialists allowed),
--   dist = function(entry) -> meters | nil, continent = function(mapID) -> id | nil, here = mapID | nil }
function LehrerOrte.pick(entries, ctx)
  ctx = type(ctx) == "table" and ctx or {}
  local best, bestD, other
  local hereC = ctx.here and ctx.continent and ctx.continent(ctx.here) or nil
  for _, e in ipairs(entries or {}) do
    local fits = (not e.faction or not ctx.faction or e.faction == ctx.faction)
      and (ctx.special or not e.special)
      and (not ctx.skill or (e.cap or 0) == 0 or e.cap >= ctx.skill)
    if fits then
      local d = ctx.dist and ctx.dist(e) or nil
      if d and (not bestD or d < bestD or (d == bestD and e.npc < best.npc)) then
        best, bestD = e, d
      elseif not d then
        local sameC = hereC ~= nil and ctx.continent and ctx.continent(e.mapID) == hereC
        local rank = (sameC and 0 or 2) + (e.own and 0 or 1)
        if not other or rank < other.rank or (rank == other.rank and e.npc < other.e.npc) then other = { e = e, rank = rank } end
      end
    end
  end
  if best then
    best.dist = bestD
    return best
  end
  return other and other.e or nil
end

local function playerFaction()
  local ok, f = pcall(UnitFactionGroup, "player")
  if not ok or isSecret(f) then return nil end
  return f == "Alliance" and "A" or f == "Horde" and "H" or nil
end

-- nearest fitting trainer. opts: skill (learn value of the recipe), special, faction (default: the player's)
function LehrerOrte.nearest(line, opts)
  opts = type(opts) == "table" and opts or {}
  local list = LehrerOrte.list(line)
  if #list == 0 then return nil, S.data and "none" or "nodata" end
  local Pl = ns.Plans
  local Geo = Journal.Geo
  local here
  if ns.Zone and type(ns.Zone.raw) == "function" then
    local ok, m = pcall(ns.Zone.raw)
    if ok then here = m end
  end
  local ctx = {
    faction = opts.faction or playerFaction(), skill = num(opts.skill), special = opts.special == true, here = posInt(here),
    dist = function(e)
      -- every point of the entry counts (QuestieDB knows several spawns); the nearest one is the trainer's place
      local bestD
      for _, pt in ipairs(e.points or { { mapID = e.mapID, x = e.x, y = e.y } }) do
        local d = Pl and type(Pl.distance) == "function" and Pl.distance({ kind = "place", mapID = pt.mapID, x = pt.x, y = pt.y }) or nil
        d = num(d)
        if d and (not bestD or d < bestD) then
          bestD = d
          e.mapID, e.x, e.y = pt.mapID, pt.x, pt.y
        end
      end
      return bestD
    end,
    continent = function(mapID)
      if not (Geo and type(Geo.continentOf) == "function") then return nil end
      local ok, c = pcall(Geo.continentOf, mapID)
      return ok and num(c) or nil
    end,
  }
  local e = LehrerOrte.pick(list, ctx)
  if not e then return nil, "none" end
  return e
end

-- tests: forget the adopted data
function LehrerOrte.reset()
  S.data, S.parsed = nil, nil
end
