-- Recipe cache (change "runde3", package R; WoW Forever only): what the profession window showed, kept in the character's saved variables
-- (chars[guid].recipeCache) so the recipe book and the shopping list can work without an open window.
--   recipeCache[professionID] = { name, skill, max, at, recipes = { [recipeID] = { n, l, d, u, o, q, r = { { itemID, qty }, ... } } } }
--     name   profession name (sanitized)            skill / max   skill level and cap when the window was read       at   epoch seconds
--     n      recipe name (sanitized)                l   learned (true/false)
--     d      relativeDifficulty 0 optimal (orange), 1 medium (yellow), 2 easy (green), 3 trivial (grey); nil = unknown
--     u      numSkillUps (nil = unknown)            o   outputItemID (nil = no item, e.g. enchantments)   q   quantityMin of the output
--     i      icon file id of the recipe (GetRecipeInfo.icon; nil = unknown, the book asks the client for the item/spell icon)
--     r      reagents in the order of the recipe: { itemID, quantity } (the first reagent of every basic slot)
-- Written by collectors/RecipeScan.lua (RecipeCache.put), read by journal/model/Rezeptbuch.lua and the shopping list (file in journal/model/:
-- loaded in every client mode, also in tests without collectors).
-- Read API (nothing here writes or throws; the returned tables are the saved data: do not change them):
--   RecipeCache.get(profID)                -> entry | nil
--   RecipeCache.recipe(profID, recipeID)   -> recipe | nil
--   RecipeCache.professions()              -> { { id, name, skill, max, at, count, learned } } sorted by id (empty list without cache)
--   RecipeCache.byOutput(itemID)           -> profID, recipeID, recipe | nil   (a LEARNED recipe first, else the lowest recipe id)
-- Sizes are bounded (MAX_*); foreign text only as Sanitize.field; no events, no timers.
local _, ns = ...

local RecipeCache = {}
ns.RecipeCache = RecipeCache

local floor = math.floor

RecipeCache.MAX_PROFESSIONS = 12
RecipeCache.MAX_RECIPES = 1000    -- per profession (same limit as RecipeScan.MAX_IDS)
RecipeCache.MAX_REAGENTS = 8      -- per recipe
RecipeCache.MAX_ID = 2147483647
RecipeCache.NAME_MAX = 80

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function whole(v, min, max)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  v = floor(v)
  if v < (min or 0) or v > (max or RecipeCache.MAX_ID) then return nil end
  return v
end

local function name(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  local S = ns.Sanitize
  local out = S and S.field(v) or v
  if type(out) ~= "string" or out == "" then return nil end
  return S and S.cut and S.cut(out, RecipeCache.NAME_MAX) or out
end

local function charTable()
  local S = ns.Store
  local c = S and type(S.char) == "function" and S.char() or nil
  return type(c) == "table" and c or nil
end

-- the table of the cache; create = true makes it
local function cache(create)
  local c = charTable()
  if not c then return nil end
  local t = c.recipeCache
  if type(t) ~= "table" then
    if not create then return nil end
    t = {}
    c.recipeCache = t
  end
  return t
end

local byOut, byOutChar = nil, nil -- itemID -> { prof, id } (built on demand, dropped on every write and for another character table)

function RecipeCache.get(profID)
  profID = whole(profID, 1)
  local t = profID and cache(false)
  local e = t and t[profID]
  if type(e) == "table" and type(e.recipes) == "table" then return e end
  return nil
end

function RecipeCache.recipe(profID, recipeID)
  local e = RecipeCache.get(profID)
  recipeID = whole(recipeID, 1)
  local r = e and recipeID and e.recipes[recipeID]
  if type(r) == "table" then return r end
  return nil
end

function RecipeCache.professions()
  local out = {}
  local t = cache(false)
  if not t then return out end
  for id, e in pairs(t) do
    if type(id) == "number" and type(e) == "table" and type(e.recipes) == "table" then
      local count, learned = 0, 0
      for _, r in pairs(e.recipes) do
        if type(r) == "table" then
          count = count + 1
          if r.l == true then learned = learned + 1 end
        end
      end
      out[#out + 1] = { id = id, name = type(e.name) == "string" and e.name or nil, skill = tonumber(e.skill), max = tonumber(e.max),
        at = tonumber(e.at), count = count, learned = learned }
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

function RecipeCache.byOutput(itemID)
  itemID = whole(itemID, 1)
  if not itemID then return nil end
  if not byOut or byOutChar ~= charTable() then
    byOut, byOutChar = {}, charTable()
    local t = cache(false)
    if t then
      local profs = {}
      for id, e in pairs(t) do
        if type(id) == "number" and type(e) == "table" and type(e.recipes) == "table" then profs[#profs + 1] = id end
      end
      table.sort(profs)
      for _, pid in ipairs(profs) do
        local ids = {}
        for rid, r in pairs(t[pid].recipes) do
          if type(rid) == "number" and type(r) == "table" and type(r.o) == "number" then ids[#ids + 1] = rid end
        end
        table.sort(ids)
        for _, rid in ipairs(ids) do
          local r = t[pid].recipes[rid]
          local cur = byOut[r.o]
          -- a learned recipe beats an unlearned one; otherwise the first (lowest profession and recipe id) stays
          if not cur or (r.l == true and cur.learned ~= true) then byOut[r.o] = { prof = pid, id = rid, learned = r.l == true } end
        end
      end
    end
  end
  local hit = byOut[itemID]
  if not hit then return nil end
  local r = RecipeCache.recipe(hit.prof, hit.id)
  if not r then return nil end
  return hit.prof, hit.id, r
end

-- Writes (replaces) the entry of one profession. info = { name, skill, max }, recipes = { [recipeID] = { n, l, d, u, o, q, r = { {itemID, qty} } } }.
-- Everything is checked and cleaned here; returns true when the entry was stored (false: no character, bad profession id, or no valid recipe).
function RecipeCache.put(profID, info, recipes)
  profID = whole(profID, 1)
  if not profID or type(info) ~= "table" or type(recipes) ~= "table" then return false end
  local t = cache(true)
  if not t then return false end
  if t[profID] == nil then
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    if n >= RecipeCache.MAX_PROFESSIONS then return false end
  end
  -- when there are more recipes than the limit, the cut is deterministic (learned first, then by recipe id), never pairs() order
  local order = {}
  for rid, r in pairs(recipes) do
    local id = whole(rid, 1)
    if id and type(r) == "table" then order[#order + 1] = { id = id, key = rid, learned = r.l == true } end
  end
  table.sort(order, function(a, b)
    if a.learned ~= b.learned then return a.learned end
    return a.id < b.id
  end)
  local clean, count = {}, 0
  for _, o in ipairs(order) do
    local rid, r = o.id, recipes[o.key]
    if count < RecipeCache.MAX_RECIPES then
      local out = { n = name(r.n), l = r.l == true }
      out.d = whole(r.d, 0, 3)
      out.u = whole(r.u, 0, 1000)
      out.o = whole(r.o, 1)
      out.q = out.o and whole(r.q, 1, 1000) or nil
      out.i = whole(r.i, 1)
      local reagents = {}
      if type(r.r) == "table" and not isSecret(r.r) then
        for _, rg in ipairs(r.r) do
          if #reagents >= RecipeCache.MAX_REAGENTS then break end
          local id = type(rg) == "table" and whole(rg[1], 1)
          local qty = type(rg) == "table" and whole(rg[2], 1, 10000)
          if id and qty then reagents[#reagents + 1] = { id, qty } end
        end
      end
      out.r = reagents
      if out.n then
        clean[rid] = out
        count = count + 1
      end
    end
  end
  if count == 0 then return false end
  t[profID] = { name = name(info.name), skill = whole(info.skill, 0, 100000), max = whole(info.max, 0, 100000),
    at = floor(type(time) == "function" and time() or 0), recipes = clean }
  byOut = nil
  return true
end

-- drops the lookup index (tests that change the saved data directly)
function RecipeCache.reset()
  byOut = nil
end
