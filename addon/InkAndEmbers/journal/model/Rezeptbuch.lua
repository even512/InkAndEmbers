-- Rezeptbuch (change "runde3", package R; WoW Forever only): display-ready data for the sub-bookmark "Rezeptbuch" of the tab Handwerk
-- (journal/pages/HandwerkRezeptbuch.lua). Per profession of the logged-in character all recipes, learned and not yet learned:
--   * with a recipe cache (ns.RecipeCache, written by collectors/RecipeScan.lua when the profession window was open): every recipe
--     with difficulty, output item and reagents; minimum skill and source of the not yet learned ones from the recipe data when it knows
--     the recipe (journal/model/Rezepte.lua, data add-on InkAndEmbers_Data/Recipes.lua);
--   * without a cache: the recipes of the recipe data (minimum skill, source), learned or not as Rezepte.knows says; no reagents.
-- Public hook for the shopping list (package E): Journal.Rezeptbuch.rowExtra = { build = fn(row, extra), fill = fn(row, extra, rec),
-- clear = fn(row, extra) } (all optional, read late, each call in pcall). "row" is the list row (Button), "extra" an empty frame of
-- 104 x 13 px at the lower right of the row (parent it, anchor to it); rec is the entry of Rezeptbuch.recipes (see there).
-- Rezeptbuch.redraw() redraws the open recipe book (after the list of to-dos changed).
-- Retail clients: off (the cache and the data are Forever's). Nothing here writes into the saved variables.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Rezeptbuch = {}
Journal.Rezeptbuch = Rezeptbuch

local lower, sort = string.lower, table.sort

Rezeptbuch.FILTERS = { "all", "learned", "open" }
-- colour keys of relativeDifficulty 0..3 (optimal, medium, easy, trivial)
Rezeptbuch.DIFF = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "grey" }
Rezeptbuch.MAX_ROWS = 800

local T = ns.Locale.ns("m.Rezeptbuch", {
  profFallback = "Beruf %s",
  recipeFallback = "Rezept %s",
  diff_orange = "optimal", diff_yellow = "mittel", diff_green = "leicht", diff_grey = "ohne Gewinn",
})
Rezeptbuch.TEXT = T

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function disp(s, max)
  if isSecret(s) or type(s) ~= "string" or s == "" then return nil end
  local S = ns.Sanitize
  local out = S and S.display(s, max or 80) or s
  if type(out) ~= "string" or out == "" then return nil end
  return out
end

local function rezepte() return Journal.Rezepte end

function Rezeptbuch.active()
  local R = rezepte()
  return R ~= nil and type(R.active) == "function" and R.active() == true
end

function Rezeptbuch.redraw()
  local V = Journal.RezeptbuchView
  if V and type(V.redraw) == "function" then pcall(V.redraw) end
end

-- the professions of the book: { { key, line, cacheId, name, rank, max, at, count, learned, cached } } in the order of the character;
-- a profession with recipes only (no gathering) or with a cache. Not readable (client): the cached ones only.
function Rezeptbuch.professions()
  local R, RC = rezepte(), ns.RecipeCache
  local cached = RC and type(RC.professions) == "function" and RC.professions() or {}
  local byId, byName = {}, {}
  for _, c in ipairs(cached) do
    byId[c.id] = c
    if c.name then byName[lower(c.name)] = c end
  end
  local cur = R and type(R.professions) == "function" and R.professions() or nil
  local out = {}
  local function add(p, c)
    local line = p and p.line or (c and c.id)
    out[#out + 1] = { key = "p" .. tostring(c and c.id or line), line = line, cacheId = c and c.id or nil,
      name = (p and p.name) or (c and c.name) or T("profFallback", tostring(line)),
      rank = p and p.rank or (c and c.skill), max = p and p.max or (c and c.max), at = c and c.at, count = c and c.count or 0,
      learned = c and c.learned or 0, cached = c ~= nil }
  end
  if cur then
    for _, p in ipairs(cur) do
      local c = byId[p.line] or (p.name and byName[lower(p.name)]) or nil
      if c or not (R.NO_RECIPE_LINES and R.NO_RECIPE_LINES[p.line]) then add(p, c) end
    end
  else
    for _, c in ipairs(cached) do add(nil, c) end
  end
  return out
end

-- recipe-data rows of one skill line: id -> row of Rezepte.evaluate (state, skill, src) plus the list in data order
local function dataRows(line)
  local R = rezepte()
  local byId, list = {}, {}
  if not (R and line and type(R.evaluate) == "function") then return byId, list end
  local ok, view = pcall(R.evaluate, { names = false })
  if not ok or type(view) ~= "table" or type(view.rows) ~= "table" then return byId, list end
  for _, r in ipairs(view.rows) do
    if r.line == line and not r.rank then -- rank steps (Geselle/Experte/Meister) are no recipes
      byId[r.id] = r
      list[#list + 1] = r
    end
  end
  return byId, list
end

local function sourceOf(row)
  local R = rezepte()
  if not (row and R and type(R.sourceText) == "function") then return nil end
  local s = R.sourceText(row)
  return s ~= "" and s or nil
end

local function spellName(id)
  local R = rezepte()
  local info = R and type(R.spellInfo) == "function" and R.spellInfo(id) or nil
  if info and not info.missing and info.name then return disp(info.name) end
  return nil
end

-- sort: learned first (by difficulty, orange first), then the not yet learned by minimum skill; name last
local function less(a, b)
  if a.learned ~= b.learned then return a.learned end
  if a.learned then
    local da, db = a.diff or 4, b.diff or 4
    if da ~= db then return da < db end
    if (a.skill or 0) ~= (b.skill or 0) then return (a.skill or 0) < (b.skill or 0) end
  else
    local sa, sb = a.skill or 99999, b.skill or 99999
    if sa ~= sb then return sa < sb end
  end
  if a.name ~= b.name then return a.name < b.name end
  return a.id < b.id
end

-- Rows of one profession entry (from Rezeptbuch.professions), filter all | learned | open.
-- rec = { id (recipeID), icon (file id from the cache | nil), prof (profession id of the cache or the skill line), name, learned, diff (0..3 | nil), ups, out (itemID | nil),
--         qty, reagents = { { id, qty } }, skill (minimum skill | nil), cost (copper | nil), src (source text | nil), details (true = from the cache) }
-- -> rows, counts = { all, learned, open }
function Rezeptbuch.recipes(entry, filter)
  local rows, counts = {}, { all = 0, learned = 0, open = 0 }
  if type(entry) ~= "table" then return rows, counts end
  local R, RC = rezepte(), ns.RecipeCache
  local byId, list = {}, {}
  if R and entry.line then
    -- the data add-on is only loaded when the profession has recipes there (login stays light)
    if R.NO_RECIPE_LINES and R.NO_RECIPE_LINES[entry.line] then
      byId, list = {}, {}
    elseif type(R.load) == "function" and R.load() then
      byId, list = dataRows(entry.line)
    end
  end
  local all = {}
  local cache = entry.cacheId and RC and type(RC.get) == "function" and RC.get(entry.cacheId) or nil
  if cache then
    for rid, r in pairs(cache.recipes) do
      if type(rid) == "number" and type(r) == "table" and #all < Rezeptbuch.MAX_ROWS then
        local d = byId[rid]
        local reagents = {}
        if type(r.r) == "table" then
          for _, rg in ipairs(r.r) do
            if type(rg) == "table" and num(rg[1]) and num(rg[2]) then reagents[#reagents + 1] = { id = rg[1], qty = rg[2] } end
          end
        end
        all[#all + 1] = { id = rid, prof = entry.cacheId, name = disp(r.n) or T("recipeFallback", rid), learned = r.l == true,
          diff = num(r.d), ups = num(r.u), icon = num(r.i), out = num(r.o), qty = num(r.q), reagents = reagents, skill = d and d.skill or nil, cost = d and d.cost or nil,
          src = sourceOf(d), details = true }
      end
    end
  else
    for _, d in ipairs(list) do
      if #all < Rezeptbuch.MAX_ROWS then
        all[#all + 1] = { id = d.id, prof = entry.line, name = spellName(d.id) or T("recipeFallback", d.id), learned = d.state == "learned",
          reagents = {}, skill = d.skill, cost = d.cost, src = sourceOf(d), details = false }
      end
    end
  end
  sort(all, less)
  for _, r in ipairs(all) do
    counts.all = counts.all + 1
    if r.learned then counts.learned = counts.learned + 1 else counts.open = counts.open + 1 end
    local take = true
    if filter == "learned" then take = r.learned elseif filter == "open" then take = not r.learned end
    if take then rows[#rows + 1] = r end
  end
  return rows, counts
end

-- name of a difficulty colour for a tooltip line ("optimal" ...); nil when unknown
function Rezeptbuch.diffText(d)
  local key = Rezeptbuch.DIFF[d]
  return key and T["diff_" .. key] or nil
end
