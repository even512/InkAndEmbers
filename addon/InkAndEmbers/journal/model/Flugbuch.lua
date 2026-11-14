-- Flight and hearthstone book (data package P3): what the log already holds about flights (TF take-off with from/to/cost, TL
-- landing with duration) and hearthstone trips (HS with the bind location), condensed for "Journey > Whole journey".
-- Pure read logic over the lists of the journey model (J.tf, J.tl, J.hs); no UI, no SavedVariables, no new log format.
--
-- PUBLIC API:
--   Flugbuch.build(tf, tl, hs) -> nil (nothing to show) or
--     { flights = n, cost = copper|nil (sum of the known fares), route = { from, to, fromFull, toFull, count }|nil (most flown,
--       at least Flugbuch.MIN_REPEAT times), longest = { sec, from, to, fromFull, toFull }|nil, hearths = n,
--       bind = { name, count }|nil (most used bind place, at least Flugbuch.MIN_REPEAT times) }
--   All names are display-ready (Sanitize.display); "from"/"to" without the zone suffix after the comma ("Orgrimmar, Durotar" ->
--   "Orgrimmar"), "fromFull"/"toFull" complete (tooltip). Equal counts: the earlier one wins.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Flugbuch = {}
Journal.Flugbuch = Flugbuch

local floor, sort = math.floor, table.sort
local type, ipairs = type, ipairs

Flugbuch.NAME_MAX = 60
Flugbuch.MIN_REPEAT = 2           -- "favourite" needs at least two times, otherwise it is no favourite
Flugbuch.SEC_MAX = 86400          -- longest plausible flight (s); the log can be edited from outside
Flugbuch.COST_MAX = 2000000000    -- copper per fare cap (200000 gold), the sum stays a finite number

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function plainName(s)
  local S = ns.Sanitize
  if type(s) ~= "string" or not (S and S.plain) then return nil end
  return S.plain(s, Flugbuch.NAME_MAX)
end

-- "Orgrimmar, Durotar" -> "Orgrimmar" (the node name carries the zone after the first comma)
local function shortName(p)
  local head = p:match("^%s*([^,]-)%s*,")
  if head and head ~= "" then return head end
  return p
end

local function display(p)
  local S = ns.Sanitize
  return (S and S.display) and S.display(p, Flugbuch.NAME_MAX) or nil
end

-- copy sorted by time (stable: equal times keep the log order)
local function byTime(list)
  local out = {}
  if type(list) ~= "table" then return out end
  for i, r in ipairs(list) do
    if type(r) == "table" and finite(r.t) then out[#out + 1] = { r = r, i = i } end
  end
  sort(out, function(a, b)
    if a.r.t ~= b.r.t then return a.r.t < b.r.t end
    return a.i < b.i
  end)
  for k, e in ipairs(out) do out[k] = e.r end
  return out
end

-- counts per key, the winner: highest count, ties by first occurrence; -> entry or nil
local function favourite(counts, order)
  local best
  for _, key in ipairs(order) do
    local e = counts[key]
    if not best or e.count > best.count then best = e end
  end
  return best
end

function Flugbuch.build(tf, tl, hs)
  local flights = byTime(tf)
  local landings = byTime(tl)
  local hearths = byTime(hs)
  if #flights == 0 and #hearths == 0 then return nil end

  local cost, costKnown = 0, false
  local routes, routeOrder = {}, {}
  for _, f in ipairs(flights) do
    local c = f.cost
    if finite(c) and c >= 0 then
      cost = cost + math.min(c, Flugbuch.COST_MAX)
      costKnown = true
    end
    local from, to = plainName(f.from), plainName(f.to)
    if from and to then
      local key = from .. "\n" .. to
      local e = routes[key]
      if not e then
        e = { from = from, to = to, count = 0 }
        routes[key] = e
        routeOrder[#routeOrder + 1] = key
      end
      e.count = e.count + 1
    end
  end

  -- duration: every landing belongs to the latest take-off before it (once; a landing after a reload has no duration of its own)
  local longest
  local used, fi = {}, 0
  for _, l in ipairs(landings) do
    while flights[fi + 1] and flights[fi + 1].t <= l.t do fi = fi + 1 end
    local f = flights[fi]
    local sec = l.sec
    if f and not used[fi] then
      used[fi] = true
      if finite(sec) and sec > 0 and sec <= Flugbuch.SEC_MAX and (not longest or sec > longest.sec) then
        longest = { sec = floor(sec + 0.5), from = plainName(f.from), to = plainName(f.to) }
      end
    end
  end

  local binds, bindOrder = {}, {}
  for _, h in ipairs(hearths) do
    local b = plainName(h.bind)
    if b then
      local e = binds[b]
      if not e then
        e = { name = b, count = 0 }
        binds[b] = e
        bindOrder[#bindOrder + 1] = b
      end
      e.count = e.count + 1
    end
  end

  local out = { flights = #flights, cost = costKnown and cost or nil, hearths = #hearths }
  local r = favourite(routes, routeOrder)
  if r and r.count >= Flugbuch.MIN_REPEAT then
    out.route = { from = display(shortName(r.from)), to = display(shortName(r.to)), fromFull = display(r.from),
      toFull = display(r.to), count = r.count }
    if not (out.route.from and out.route.to) then out.route = nil end
  end
  if longest then
    local o = { sec = longest.sec }
    if longest.from and longest.to then
      o.from, o.to = display(shortName(longest.from)), display(shortName(longest.to))
      o.fromFull, o.toFull = display(longest.from), display(longest.to)
    end
    out.longest = o
  end
  local b = favourite(binds, bindOrder)
  if b and b.count >= Flugbuch.MIN_REPEAT then
    local name = display(b.name)
    if name then out.bind = { name = name, count = b.count } end
  end
  return out
end
