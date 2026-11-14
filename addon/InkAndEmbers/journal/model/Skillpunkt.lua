-- Skillpunkt (tab "Handwerk", block "Für den nächsten Skillpunkt"): which learned recipes of a profession are best for the next skill
-- point. Source: the recipe cache of the character (collectors/RecipeScan.lua, read through ns.Einkauf.cache; one profession =
-- chars[guid].recipeCache[professionID].recipes = { [recipeID] = { n, l, d, u, o, q, r = { { itemID, qty }, ... } } }).
-- Order: colour first (d = 0 orange, then 1 yellow; green d = 2 only when nothing orange/yellow exists; grey d = 3 never), then the
-- cost per expected skill point = materials per craft x expected crafts per point (EXPECT: orange 1, yellow 2, green 4); materials
-- the bags already hold count only HAVE_WEIGHT (a quarter), missing ones fully; ties: more crafts the bags cover, then the name.
-- "Enough for N" = how many crafts the bags cover (reagents only from the bags, no bank); nil without counts (another character's
-- book) or for a recipe without reagents. "Missing" = what is still lacking for the expected crafts of ONE point (own book only).
--   res = { rows = { row }, best = row | nil, learned = n, total = n, tier = "orange" | "yellow" | "green" | nil,
--           reason = nil | "nocache" | "nolearned" | "nonext", noSure = true when no orange/yellow recipe is learned (not for "nocache") }
--   row = { id, name, d, u, mats, kinds, out, n = enough for N | nil, color = "orange" | "yellow" | "green", crafts = expected crafts per
--           point, cost, missing = { { id, qty } } | nil (nil = unknown) }
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Skillpunkt = {}
Journal.Skillpunkt = Skillpunkt

local floor, min = math.floor, math.min

Skillpunkt.ROWS = 4          -- recommendation + alternatives (the Handwerk page shows all, the profession bar fewer)
Skillpunkt.COLOR = { [0] = "orange", [1] = "yellow", [2] = "green" }
Skillpunkt.EXPECT = { [0] = 1, [1] = 2, [2] = 4 }  -- expected crafts for the next skill point (orange sure, yellow likely, green rare)
Skillpunkt.HAVE_WEIGHT = 0.25                      -- a material already in the bags costs this much of a missing one

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function int(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return floor(v)
end

local function name(rec, id)
  local n = type(rec.n) == "string" and not isSecret(rec.n) and rec.n ~= "" and rec.n or nil
  local S = ns.Sanitize
  if n and S and S.display then n = S.display(n, 60) end
  if type(n) ~= "string" or n == "" then return "#" .. tostring(id) end
  return n
end

-- opts: char (table; default the logged-in character), count (function(itemID) -> number | nil; nil = no counts), limit
function Skillpunkt.rank(profID, opts)
  opts = type(opts) == "table" and opts or {}
  local E = ns.Einkauf
  local res = { rows = {}, learned = 0 }
  local cache = E and E.cache and E.cache(opts.char) or nil
  profID = int(profID)
  local p = cache and profID and cache[profID] or nil
  if type(p) ~= "table" or type(p.recipes) ~= "table" then
    res.reason = "nocache"
    return res
  end
  local count = opts.count
  local cand = { [0] = {}, [1] = {}, [2] = {} }
  local have = 0
  for id, rec in pairs(p.recipes) do
    if type(id) == "number" and type(rec) == "table" and rec.l == true then
      have = have + 1
      local d = int(rec.d)
      if d and cand[d] then
        local reagents = E.reagents(rec)
        local crafts = Skillpunkt.EXPECT[d]
        local mats, enough, unknown, cost, missing = 0, nil, type(count) ~= "function", 0, {}
        for _, r in ipairs(reagents) do
          mats = mats + r.qty
          local c = (not unknown) and int(count(r.id)) or nil
          if c then
            local k = floor(c / r.qty)
            enough = enough and min(enough, k) or k
          else
            unknown = true
          end
          local need = r.qty * crafts
          local covered = c and min(c, need) or 0
          cost = cost + (need - covered) + covered * Skillpunkt.HAVE_WEIGHT
          if need - covered > 0 then missing[#missing + 1] = { id = r.id, qty = need - covered } end
        end
        if unknown or #reagents == 0 then enough = nil end
        local row = { id = id, name = name(rec, id), d = d, u = int(rec.u) or 1, mats = mats, kinds = #reagents, out = int(rec.o),
          n = enough, color = Skillpunkt.COLOR[d], profID = profID, crafts = crafts, cost = cost, missing = (not unknown) and missing or nil }
        local list = cand[d]
        list[#list + 1] = row
      end
    end
  end
  res.learned = have
  if have == 0 then
    res.reason = "nolearned"
    res.noSure = true
    return res
  end
  local tier
  if #cand[0] > 0 then tier = 0 elseif #cand[1] > 0 then tier = 1 elseif #cand[2] > 0 then tier = 2 end
  if not tier then
    res.reason = "nonext"
    res.noSure = true
    return res
  end
  -- orange and yellow are both listed (orange first), green only on its own
  local rows = {}
  if tier <= 1 then
    for _, d in ipairs({ 0, 1 }) do
      for _, r in ipairs(cand[d]) do rows[#rows + 1] = r end
    end
  else
    rows = cand[2]
  end
  table.sort(rows, function(a, b)
    if a.d ~= b.d then return a.d < b.d end
    if a.cost ~= b.cost then return a.cost < b.cost end
    local an, bn = a.n or -1, b.n or -1
    if an ~= bn then return an > bn end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
  end)
  local limit = int(opts.limit) or Skillpunkt.ROWS
  for i = 1, min(limit, #rows) do res.rows[i] = rows[i] end
  res.total = #rows
  res.tier = Skillpunkt.COLOR[tier]
  res.best = res.rows[1]
  res.noSure = tier == 2
  return res
end

-- live bag count for the own character's book
function Skillpunkt.bagCount(id)
  local E = ns.Einkauf
  return E and E.count and E.count(id, false) or nil
end
