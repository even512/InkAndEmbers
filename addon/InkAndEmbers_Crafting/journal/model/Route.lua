-- Route (Werkauftrag, station 1 "Planen"): the cheapest way from the current skill of a profession to a target skill, in stages.
-- Pure model: Route.compute(input) takes everything it needs as arguments (tests run it without a client); Route.plan(prof, goal,
-- opts) collects the live inputs and calls it. Nothing is drawn, stored or clicked here; ns.Werk.addRoute(route) makes the order.
-- Candidates per skill point: learned recipes of the recipe cache (collectors/RecipeScan.lua; live colour d, grey threshold t =
-- maxTrivialLevel) and recipes a trainer teaches that are not learned yet (What's Training data, journal/model/Rezepte.lua: learn
-- value L and price). Thresholds: ns.Werk.band (rule of thumb from L, corrected by the live values); chance per craft ns.Werk.chance
-- (orange 1, yellow/green (G - skill) / (G - Y), grey 0); expected crafts per point 1/p, shown with "ca.".
-- Cost per point = expected crafts x materials per craft, each material at its auction price when known (journal/model/Preise.lua,
-- prices of this session), else at the median of the known prices (no price at all: every material weighs 1, like Skillpunkt.lua);
-- what the bags hold counts Route.HAVE_WEIGHT (the Skillpunkt rule: use what you have). A recipe whose materials are unknown
-- (not in the cache yet: the game shows them after learning) costs the median of the known candidates x UNKNOWN_PENALTY; it is
-- marked unknown and its materials are never invented. The chosen recipe stays while it is at most KEEP (10 %) dearer than the
-- best (fewer stage changes). The learning cost of a trainer recipe is not part of the choice (one-off, small), it is added to the
-- total. Before the first stage of a recipe that is not learned yet a trainer step is inserted (nearest trainer:
-- Journal.LehrerOrte). Precursors ("Zwischenprodukte selbst herstellen", also of another profession): ns.Werk.addPrecursors.
-- Limits: ns.Werk.STEPS_MAX steps, ns.Werk.CRAFTS_MAX crafts (the route ends early: reason "limit").
--   input = { prof, skill, max, goal, recipes = { [id] = rec }, scanSkill, learnable = { { id, skill, cost } }, learnOf = { [id] = L },
--     knows(id), count(itemID), price(itemID) -> unit | nil, priceN(itemID, n) -> total, got | nil, resolve, nameOf(id),
--     trainerFor(prof, L) -> { npc, name, mapID, x, y } | nil }
--   route = { prof, goal, from, to (reached), resolve, steps = { step (ns.Werk format) + display fields color, chance, crafts (float),
--     learned, known }, materials = { { id, name, need, have, missing, self (made by a precursor), unit, total } },
--     cost = { ah (copper of what is missing, priced part), trainer, unknownPrices (lines without a price) },
--     unknown = { recipe names without known materials }, reason = nil | "nocache" | "gap" | "limit" | "done" | "nodata" }
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Route = {}
Journal.Route = Route

local floor, min, max, ceil = math.floor, math.min, math.max, math.ceil

Route.HAVE_WEIGHT = 0.25
Route.KEEP = 1.10
Route.UNKNOWN_PENALTY = 1.5
Route.MILESTONES = { 75, 150, 225, 300 }

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

local function display(s, n)
  if isSecret(s) or type(s) ~= "string" or s == "" then return nil end
  local S = ns.Sanitize
  s = S and S.display and S.display(s, n or 60) or s
  return s ~= "" and s or nil
end

local function W() return ns.Werk end

-- goal choices of the bar: next point, next milestone, the cap -> { { key, goal } } (no duplicates, each above the skill)
function Route.goals(skill, cap)
  skill, cap = num(skill), num(cap)
  local out = {}
  if not skill then return out end
  local top = cap or 300
  local seen = {}
  local function add(key, g)
    g = floor(g)
    if g > skill and g <= top and not seen[g] then
      seen[g] = true
      out[#out + 1] = { key = key, goal = g }
    end
  end
  add("next", skill + 1)
  for _, m in ipairs(Route.MILESTONES) do
    if m > skill + 1 then add("milestone", m) break end
  end
  add("max", top)
  return out
end

local function reagentsOf(rec)
  local list = {}
  if type(rec) ~= "table" or type(rec.r) ~= "table" then return list end
  for _, e in ipairs(rec.r) do
    local id = type(e) == "table" and posInt(e[1] or e.id) or nil
    local qty = type(e) == "table" and posInt(e[2] or e.qty) or nil
    if id and qty then list[#list + 1] = { id = id, qty = qty } end
  end
  return list
end

local function median(list)
  if #list == 0 then return nil end
  table.sort(list)
  local m = floor((#list + 1) / 2)
  if #list % 2 == 0 then return (list[m] + list[m + 1]) / 2 end
  return list[m]
end

-- candidates: learned cache recipes + trainer recipes not learned (cache entry if the window showed it, else none)
local function candidates(input)
  local Wk = W()
  local out, byId = {}, {}
  local learnable = {}
  for _, row in ipairs(input.learnable or {}) do
    local id = posInt(row.id)
    if id then learnable[id] = row end
  end
  local function add(id, rec, row)
    if byId[id] then return end
    local learned = (type(rec) == "table" and rec.l == true) or (input.knows and input.knows(id)) or false
    if not learned and not row then return end
    local L = num((input.learnOf or {})[id]) or (row and num(row.skill)) or nil
    local band = Wk.band(L, rec, input.scanSkill)
    if not band then return end
    local reagents = reagentsOf(rec)
    local c = { id = id, rec = rec, learned = learned, L = L, band = band, reagents = reagents, known = #reagents > 0,
      cost = row and num(row.cost) or 0, name = display(rec and rec.n) or (input.nameOf and display(input.nameOf(id))) or ("#" .. id),
      out = rec and posInt(rec.o) or nil, q = rec and posInt(rec.q) or 1 }
    byId[id] = c
    out[#out + 1] = c
  end
  for id, rec in pairs(input.recipes or {}) do
    if type(id) == "number" and type(rec) == "table" then add(id, rec, learnable[id]) end
  end
  for id, row in pairs(learnable) do add(id, nil, row) end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

function Route.compute(input)
  local Wk = W()
  input = type(input) == "table" and input or {}
  local prof, skill, goal = posInt(input.prof), num(input.skill), posInt(input.goal)
  local route = { prof = prof, goal = goal, from = skill, to = skill, resolve = input.resolve == true, steps = {}, materials = {},
    cost = { ah = 0, trainer = 0, unknownPrices = 0 }, unknown = {} }
  if not (Wk and prof and skill and goal) then
    route.reason = "nodata"
    return route
  end
  skill = floor(skill)
  local cap = num(input.max)
  if cap and goal > cap then goal = floor(cap) route.goal = goal end
  if goal <= skill then
    route.reason = "done"
    return route
  end
  local cands = candidates(input)
  local count = input.count or function() return nil end
  local price = input.price or function() return nil end
  -- unit value of a material: its price, else the median of the known prices, else 1
  local known = {}
  for _, c in ipairs(cands) do
    for _, r in ipairs(c.reagents) do
      local p = num(price(r.id))
      if p and p > 0 then known[#known + 1] = p end
    end
  end
  local fallback = median(known) or 1
  local unitOf = {}
  local function unit(id)
    local u = unitOf[id]
    if u == nil then
      u = num(price(id))
      if not u or u <= 0 then u = fallback end
      unitOf[id] = u
    end
    return u
  end
  local bagLeft = {}
  local function bag(id)
    local b = bagLeft[id]
    if b == nil then
      b = num(count(id)) or 0
      bagLeft[id] = b
    end
    return b
  end
  local function costOf(c, crafts)
    local sum = 0
    for _, r in ipairs(c.reagents) do
      local need = r.qty * crafts
      local covered = min(bag(r.id), need)
      sum = sum + ((need - covered) + covered * Route.HAVE_WEIGHT) * unit(r.id)
    end
    return sum
  end
  local segs, prev = {}, nil
  local s = skill
  while s < goal do
    local opts, knownCosts = {}, {}
    for _, c in ipairs(cands) do
      if c.learned or (c.L and c.L <= s) then
        local p = Wk.chance(c.band, s)
        if p and p >= Wk.STUCK_CHANCE then
          local e = 1 / p
          local o = { c = c, p = p, e = e }
          if c.known then
            o.cost = costOf(c, e)
            knownCosts[#knownCosts + 1] = o.cost
          end
          opts[#opts + 1] = o
        end
      end
    end
    if #opts == 0 then
      route.reason = "gap"
      break
    end
    local unknownCost = (median(knownCosts) or fallback * 3) * Route.UNKNOWN_PENALTY
    local best, prevOpt
    for _, o in ipairs(opts) do
      o.score = o.cost or unknownCost
      if prev and o.c == prev then prevOpt = o end
      if not best or o.score < best.score or (o.score == best.score and (o.p > best.p or (o.p == best.p and o.c.id < best.c.id))) then
        best = o
      end
    end
    if prevOpt and prevOpt.score <= best.score * Route.KEEP then best = prevOpt end
    local c = best.c
    for _, r in ipairs(c.reagents) do bagLeft[r.id] = max(0, bag(r.id) - r.qty * best.e) end
    local seg = segs[#segs]
    if seg and seg.c == c then
      seg.to = s + 1
      seg.crafts = seg.crafts + best.e
    else
      segs[#segs + 1] = { c = c, from = s, to = s + 1, crafts = best.e, p = best.p }
    end
    prev = c
    s = s + 1
  end
  -- stages -> steps (a trainer step before the first stage of a recipe that is not learned yet)
  local steps, trained, crafts = {}, {}, 0
  for _, seg in ipairs(segs) do
    local c = seg.c
    local need = (not c.learned and not trained[c.id]) and 2 or 1
    local n = ceil(seg.crafts - 1e-9)
    if #steps + need > Wk.STEPS_MAX or crafts + n > Wk.CRAFTS_MAX then
      route.reason = "limit"
      break
    end
    if not c.learned and not trained[c.id] then
      trained[c.id] = true
      local npc = input.trainerFor and input.trainerFor(prof, c.L) or nil
      steps[#steps + 1] = { kind = "trainer", recipe = c.id, prof = prof, name = c.name, cost = c.cost, at = max(c.L or seg.from, seg.from),
        npc = type(npc) == "table" and posInt(npc.npc) or nil, trainer = type(npc) == "table" and npc or nil }
      route.cost.trainer = route.cost.trainer + (c.cost or 0)
    end
    local r = {}
    for _, rg in ipairs(c.reagents) do r[#r + 1] = { rg.id, rg.qty } end
    steps[#steps + 1] = { kind = "craft", recipe = c.id, prof = prof, name = c.name, n = max(1, n), from = seg.from, to = seg.to,
      out = c.out, q = c.q, y = c.band.y, g = c.band.g, r = #r > 0 and r or nil, unknown = not c.known or nil,
      color = Wk.color(c.band, seg.from), chance = seg.p, crafts = seg.crafts, learned = c.learned, known = c.known }
    crafts = crafts + n
    route.to = seg.to
    if not c.known then route.unknown[#route.unknown + 1] = c.name end
  end
  local all = Wk.addPrecursors(steps, input.resolve == true)
  if #all > Wk.STEPS_MAX then
    -- precursors pushed the order over the limit: plan without them
    route.reason = "limit"
    all = steps
  end
  route.steps = all
  -- materials of the whole route (precursor products are made, their materials bought)
  local demand = Wk.compute({ steps = all }, { skill = function() return skill end, count = count, knows = function() return false end })
  local ids = {}
  for id in pairs(demand.need) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local n = demand.need[id]
    if n > 0 then
      local have = num(count(id)) or 0
      local missing = max(0, n - have)
      local u = num(price(id))
      local total
      if missing > 0 and input.priceN then total = num((input.priceN(id, missing))) end
      if missing > 0 and not total and u then total = u * missing end
      if missing > 0 then
        if total then route.cost.ah = route.cost.ah + total else route.cost.unknownPrices = route.cost.unknownPrices + 1 end
      end
      if #route.materials < Wk.LINES_MAX then
        route.materials[#route.materials + 1] = { id = id, name = input.itemName and display(input.itemName(id)) or ("#" .. id), need = n,
          have = min(have, n), missing = missing, unit = u, total = total }
      end
    end
  end
  for id, n in pairs(demand.selfMade) do
    if n > 0 and #route.materials < Wk.LINES_MAX then
      route.materials[#route.materials + 1] = { id = id, name = input.itemName and display(input.itemName(id)) or ("#" .. id), need = n,
        have = 0, missing = 0, self = n }
    end
  end
  -- without a recipe cache the bar says "open the profession window once"; that hint beats the gap it causes
  if input.noCache and (route.reason == nil or route.reason == "gap") then route.reason = "nocache" end
  return route
end

-- live plan of the logged-in character -> route (reason "nocache" when the profession window was never read: only trainer
-- recipes then, without materials)
function Route.plan(prof, goal, opts)
  opts = type(opts) == "table" and opts or {}
  local Wk, E = W(), ns.Einkauf
  prof = posInt(prof)
  local cache = E and E.cache and E.cache() or nil
  local entry = cache and prof and cache[prof] or nil
  local noCache = type(entry) ~= "table" or type(entry.recipes) ~= "table"
  local skill, cap
  if Wk then skill, cap = Wk.skill(prof) end
  if not skill and not noCache then skill, cap = num(entry.skill), num(entry.max) end
  local Rz = Journal.Rezepte
  local learnable, learnOf = {}, {}
  if Rz and type(Rz.load) == "function" and Rz.active() and Rz.load() then
    local fac = Rz.player().faction
    for _, row in ipairs(Rz.parse(prof) or {}) do
      if not row.rank and not (row.faction and fac and row.faction ~= fac) then
        learnOf[row.id] = row.skill
        if Rz.hasSource(row, "T") and not Wk.knows(row.id) then learnable[#learnable + 1] = { id = row.id, skill = row.skill, cost = row.cost } end
      end
    end
  end
  local Pr = Journal.Preise
  local LO = Journal.LehrerOrte
  return Route.compute({
    prof = prof, skill = skill, max = cap, goal = goal, recipes = not noCache and entry.recipes or {}, scanSkill = not noCache and entry.skill or nil,
    learnable = learnable, learnOf = learnOf, knows = Wk and Wk.knows, resolve = opts.resolve == true, noCache = noCache,
    count = function(id) return E and E.count and E.count(id, false) or nil end,
    price = function(id) return Pr and Pr.unit(id) or nil end,
    priceN = function(id, n) if Pr then return Pr.priceFor(id, n) end return nil end,
    itemName = function(id) return E and E.itemName and E.itemName(id) or nil end,
    nameOf = function(id)
      local info = Rz and Rz.spellInfo and Rz.spellInfo(id)
      return info and not info.missing and info.name or nil
    end,
    trainerFor = function(line, L) return LO and LO.nearest(line, { skill = L }) or nil end,
  })
end
