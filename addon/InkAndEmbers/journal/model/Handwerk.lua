-- Handwerk evaluator (tab "Handwerk"): reads the profession lines SK (skill rises with time) and SP kind recipe (learned recipes) from
-- the log on first call (not in the index: Index.H.SK keeps only the maximum per profession; closed blocks once, the open block fresh)
-- and the craft finds (index list LT, source "craft", only from quality green) plus the counters gather/fishing/crafted of the character.
-- Kept at runtime only (weak key on the index), nothing in the SV. Works for the logged-in character and for a guest book alike: it
-- reads nothing live, only the log and the SV of index.char.
--   res = { professions = { p }, recipes = { r }, unassigned = n, balance = { mined, picked, skinned, fished, crafted },
--           firstCraft = { t, level, name } | nil, playTotal = seconds, truncated }
--   p = { key, line, name, kind = "primary" | "secondary", rank, max, rankName, first = point, last = point, points = { point },
--         milestones = { { step, t, level, rank, x } or { step } (not reached) }, recipes = { r }, firstCraft = { t, level, name } | nil }
--   point = { t, x = active play seconds since the start of the journey, rank, level }
--   r = { label, t, level, key = profession key | nil }   (label = Sanitize.display, never raw)
-- Recipe -> profession: SP lines carry no skill line (and in practice no spellID), so the recipe is attributed only when the answer is
-- clear: exactly one recipe-capable profession was known at that time; otherwise first by name (the recipe lists of the data add-on,
-- Journal.Rezepte, spell ids per profession, names read with C_Spell.GetSpellName in pcall; a spellID in the SP line counts too): a
-- recipe found in exactly one candidate profession belongs to it; only then the time estimate: one profession has skill rises close
-- in time and the next one is clearly further away. Everything else stays unassigned and is counted in res.unassigned (the tab lists
-- all recipes anyway). The recipe data is loaded only when a recipe is ambiguous.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Handwerk = {}
Journal.Handwerk = Handwerk

local floor, huge, min, max = math.floor, math.huge, math.min, math.max

Handwerk.STEPS = { 75, 150, 225, 300 }   -- rank steps of the profession skill (Classic curve: Lehrling .. Meister)
Handwerk.SECONDARY = { [185] = true, [129] = true, [356] = true, [794] = true } -- cooking, first aid, fishing, archaeology
Handwerk.NO_RECIPES = { [182] = true, [393] = true, [356] = true, [794] = true } -- herbalism, skinning, fishing, archaeology: no recipes
Handwerk.MAX_EVENTS = 8000       -- SK/SP lines read (the rest sets res.truncated)
Handwerk.MAX_PROFESSIONS = 16
Handwerk.MAX_POINTS = 1500       -- skill rises kept per profession
Handwerk.RECIPE_MAX = 600
Handwerk.ASSIGN_GAP = 900        -- s: a recipe is attributed by time only if the nearest skill rise is this close
Handwerk.CRAFT_GAP = 6           -- s: a craft find belongs to the profession whose skill rise came with it
Handwerk.COUNT_SCAN = 8000       -- counter keys read per group
Handwerk.ALLOW_RETAIL = false    -- tests / diagnosis: show the tab in the Retail client too

local T = ns.Locale.ns("m.Handwerk", {
  rank_75 = "Lehrling",
  rank_150 = "Geselle",
  rank_225 = "Experte",
  rank_300 = "Meister",
})
Handwerk.TEXT = T

local cache = setmetatable({}, { __mode = "k" })

local function finite(v)
  return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

-- Retail professions are per expansion (other skill lines, other maxima): the Classic curve 75/150/225/300 would be wrong there.
-- The tab therefore exists only in WoW Forever (Journal.MapSpace.retailClient: project id AND interface version).
function Handwerk.active()
  if Handwerk.ALLOW_RETAIL then return true end
  local ms = Journal.MapSpace
  return not (ms ~= nil and type(ms.retailClient) == "function" and ms.retailClient() == true)
end

-- title of the rank for a skill maximum (75 -> Lehrling .. 300 -> Meister); nil below the first step
function Handwerk.rankName(cap)
  cap = tonumber(cap)
  if not finite(cap) then return nil end
  local best
  for _, s in ipairs(Handwerk.STEPS) do
    if cap >= s then best = s end
  end
  return best and T["rank_" .. best] or nil
end

-- ---------------------------------------------------------------- log reading

local scan = nil -- { char, nBlocks, firstRef, lastRef, ev }

local function readBlockEvents(ev, block)
  if type(block) ~= "string" then return end
  local h = tonumber(string.match(block, "^#~(%-?%d+)~"))
  if not finite(h) then return end
  for dt, code, rest in string.gmatch(block, "\n(%-?%d+)~(S[KP])~([^\n]*)") do
    local t = h + tonumber(dt)
    if finite(t) and #ev < Handwerk.MAX_EVENTS then ev[#ev + 1] = { t = t, code = code, rest = rest } end
  end
end

local function logEvents(char)
  local log = type(char) == "table" and type(char.log) == "table" and char.log or {}
  if not scan or scan.char ~= char or #log < scan.nBlocks or (scan.nBlocks > 0 and (log[1] ~= scan.firstRef or log[scan.nBlocks] ~= scan.lastRef)) then
    scan = { char = char, nBlocks = 0, ev = {} }
  end
  for i = scan.nBlocks + 1, #log do readBlockEvents(scan.ev, log[i]) end
  scan.nBlocks = #log
  scan.firstRef, scan.lastRef = log[1], log[#log]
  local out = {}
  for i = 1, #scan.ev do out[i] = scan.ev[i] end
  local Store = ns.Store
  local ob = Store and Store.current == char and Store.block
  if type(ob) == "table" and finite(tonumber(ob.start)) and type(ob.lines) == "table" then
    local start = tonumber(ob.start)
    for _, l in ipairs(ob.lines) do
      local dt, code, rest = string.match(l, "^(%-?%d+)~(S[KP])~(.*)$")
      if dt and #out < Handwerk.MAX_EVENTS and finite(start + tonumber(dt)) then
        out[#out + 1] = { t = start + tonumber(dt), code = code, rest = rest }
      end
    end
  end
  return out, #out >= Handwerk.MAX_EVENTS
end

-- "a~b~~d" -> { "a", "b", "", "d" } (n fields; missing ones are "")
local function split(rest, n)
  local f, pos = {}, 1
  for i = 1, n do
    local e = string.find(rest, "~", pos, true)
    if e and i < n then
      f[i] = string.sub(rest, pos, e - 1)
      pos = e + 1
    else
      f[i] = string.sub(rest, pos)
      pos = #rest + 2
    end
  end
  return f
end

local function text(v)
  if v == nil or v == "" or v == "?" then return nil end
  return v
end

local function number(v)
  local n = tonumber(text(v))
  if n and finite(n) then return n end
  return nil
end

local function display(s, n)
  local S = ns.Sanitize
  if type(s) ~= "string" or isSecret(s) or not S then return nil end
  return S.display(s, n or 48)
end

local function level(v)
  local n = number(v)
  if n and n >= 1 and n <= 200 then return floor(n) end
  return nil
end

-- ---------------------------------------------------------------- helpers

-- table from the SV: snapshots.<group>[id] (keys may be numbers or strings)
local function snap(char, group, id)
  local s = type(char) == "table" and type(char.snapshots) == "table" and char.snapshots[group]
  if type(s) ~= "table" or isSecret(s) or id == nil then return nil end
  local v = s[id]
  if v == nil then v = s[tostring(id)] end
  if v == nil and type(id) == "string" then v = s[tonumber(id)] end
  return type(v) == "table" and not isSecret(v) and v or nil
end

local function counterSum(char, group)
  local c = type(char) == "table" and type(char.counters) == "table" and char.counters[group]
  if type(c) ~= "table" or isSecret(c) then return 0 end
  local sum, scanned = 0, 0
  for _, v in pairs(c) do
    scanned = scanned + 1
    if scanned > Handwerk.COUNT_SCAN then break end
    if not isSecret(v) and finite(v) and v > 0 then sum = sum + min(v, 2 ^ 31) end
  end
  return floor(min(sum, 2 ^ 40))
end

local function counterValue(char, group, key)
  local c = type(char) == "table" and type(char.counters) == "table" and char.counters[group]
  local v = type(c) == "table" and not isSecret(c) and c[key] or nil
  if isSecret(v) or not finite(v) or v < 0 then return 0 end
  return floor(min(v, 2 ^ 40))
end

-- index of the last point with t <= x (0 if none)
local function lastAtOrBefore(points, x)
  local lo, hi, found = 1, #points, 0
  while lo <= hi do
    local mid = floor((lo + hi) / 2)
    if points[mid].t <= x then found, lo = mid, mid + 1 else hi = mid - 1 end
  end
  return found
end

local function nearest(points, t)
  local i = lastAtOrBefore(points, t)
  local best = huge
  if i >= 1 then best = t - points[i].t end
  if i < #points then best = min(best, points[i + 1].t - t) end
  return best
end

local function playSeconds(index, base, t)
  local I = Journal.Index
  if not (I and I.activeSeconds) or not finite(t) or t <= base then return 0 end
  local s = I.activeSeconds(index, base, t)
  return finite(s) and s > 0 and s or 0
end

local function itemName(char, itemID)
  local s = snap(char, "items", itemID)
  return s and display(s.name, 48) or nil
end

-- ---------------------------------------------------------------- recipe names

-- name of a spell in the client language, as display text (nil = not readable)
local function spellLabel(id)
  local name
  local CS = rawget(_G, "C_Spell")
  if type(CS) == "table" and type(CS.GetSpellName) == "function" then
    local ok, v = pcall(CS.GetSpellName, id)
    if ok then name = v end
  end
  if name == nil and type(rawget(_G, "GetSpellInfo")) == "function" then
    local ok, v = pcall(GetSpellInfo, id)
    if ok and type(v) == "string" then name = v end
  end
  return display(name, 48)
end

-- candidates (entries { p, d }) whose profession knows the recipe by spell id or by name; nil = no recipe data (not loaded / Retail).
-- cache: per skill line { ids, names }, built once per aggregation
local function matchByName(r, cands, cache)
  local Rz = Journal.Rezepte
  if not (Rz and type(Rz.active) == "function" and Rz.active() and type(Rz.load) == "function" and type(Rz.parse) == "function") then return nil end
  local okLoad, loaded = pcall(Rz.load)
  if not (okLoad and loaded) then return nil end
  local out = {}
  for _, c in ipairs(cands) do
    local line = c.p.line
    if line and not Handwerk.NO_RECIPES[line] then
      local set = cache[line]
      if set == nil then
        set = { ids = {}, names = {} }
        local okParse, list = pcall(Rz.parse, line)
        for _, e in ipairs(okParse and type(list) == "table" and list or {}) do
          set.ids[e.id] = true
          local nm = spellLabel(e.id)
          if nm then set.names[nm] = true end
        end
        cache[line] = set
      end
      if (r.id and set.ids[r.id]) or set.names[r.label] then out[#out + 1] = c end
    end
  end
  return out
end

-- ---------------------------------------------------------------- aggregation

local function compute(index)
  local char = index.char
  local I = Journal.Index
  local events, truncated = logEvents(char)
  local base = finite(index.startT) and index.startT or (finite(index.firstT) and index.firstT or 0)

  local byLine, byName, order = {}, {}, {}
  local recipes, seenRecipe = {}, {}

  for _, e in ipairs(events) do
    if e.code == "SK" then
      local f = split(e.rest, 6)
      local name, rank, cap, line = text(f[1]), number(f[2]), number(f[3]), number(f[4])
      -- only professions have a maximum; weapon skills (no maximum, no skill line) are not part of this tab
      if name and rank and cap and cap > 0 and rank >= 0 then
        local p = (line and byLine[line]) or byName[name]
        if not p and #order < Handwerk.MAX_PROFESSIONS then
          p = { rank = -1, max = 0, points = {}, rawName = name }
          order[#order + 1] = p
        end
        if p then
          if line then p.line, byLine[line] = line, p end
          byName[name] = p
          p.rawName = name
          if rank < p.rank then p.points = {} end -- learned again after giving it up: the curve starts anew
          p.max = cap
          if rank > p.rank or #p.points == 0 then
            p.rank = rank
            if #p.points < Handwerk.MAX_POINTS then
              p.points[#p.points + 1] = { t = e.t, rank = rank, level = level(f[5]) }
            end
          end
        end
      end
    elseif e.code == "SP" then
      local f = split(e.rest, 5)
      if text(f[2]) == "recipe" and #recipes < Handwerk.RECIPE_MAX then
        local name = text(f[5])
        if not name then
          local id = number(f[1])
          local s = id and snap(char, "spells", floor(id))
          name = s and text(s.name) or nil
        end
        local label = display(name, 48)
        if label and not seenRecipe[label] then
          seenRecipe[label] = true
          local rid = number(f[1])
          recipes[#recipes + 1] = { label = label, t = e.t, level = level(f[3]), id = rid and floor(rid) or nil }
        end
      end
    end
  end

  -- professions: points with their play time, milestones, rank title
  local list = {}
  for _, p in ipairs(order) do
    if #p.points > 0 then
      for _, pt in ipairs(p.points) do pt.x = playSeconds(index, base, pt.t) end
      p.name = display(p.rawName, 40) or "?"
      p.key = p.line and ("l" .. floor(p.line)) or ("n" .. p.rawName)
      p.kind = (p.line and Handwerk.SECONDARY[p.line]) and "secondary" or "primary"
      p.first, p.last = p.points[1], p.points[#p.points]
      p.rankName = Handwerk.rankName(p.max)
      p.milestones = {}
      for _, step in ipairs(Handwerk.STEPS) do
        local m = { step = step }
        for _, pt in ipairs(p.points) do
          if pt.rank >= step then
            m.t, m.level, m.rank, m.x = pt.t, pt.level, pt.rank, pt.x
            break
          end
        end
        p.milestones[#p.milestones + 1] = m
      end
      p.recipes = {}
      list[#list + 1] = p
    end
  end
  table.sort(list, function(a, b)
    if a.kind ~= b.kind then return a.kind == "primary" end
    if a.first.t ~= b.first.t then return a.first.t < b.first.t end
    return a.name < b.name
  end)

  -- recipes -> profession (only when clear)
  local unassigned = 0
  local nameCache = {}
  for _, r in ipairs(recipes) do
    local cands = {}
    for _, p in ipairs(list) do
      if not (p.line and Handwerk.NO_RECIPES[p.line]) and p.first.t <= r.t + 30 then
        cands[#cands + 1] = { p = p, d = nearest(p.points, r.t) }
      end
    end
    local pick
    if #cands > 1 then
      local hit = matchByName(r, cands, nameCache)
      if hit and #hit == 1 then pick = hit[1].p
      elseif hit and #hit > 1 then cands = hit end
    end
    if pick then
      -- attributed by name
    elseif #cands == 1 then
      pick = cands[1].p
    elseif #cands > 1 then
      table.sort(cands, function(a, b) return a.d < b.d end)
      if cands[1].d <= Handwerk.ASSIGN_GAP and cands[2].d > cands[1].d * 2 then pick = cands[1].p end
    end
    if pick then
      r.key = pick.key
      pick.recipes[#pick.recipes + 1] = r
    else
      unassigned = unassigned + 1
    end
  end

  -- craft finds (from quality green): the first one overall and, where a skill rise came with it, the first one per profession
  local firstCraft, craftedGreen = nil, 0
  local crafting = {}
  for _, p in ipairs(list) do
    if not (p.line and Handwerk.NO_RECIPES[p.line]) then crafting[#crafting + 1] = p end
  end
  local seen = 0
  for _, rec in ipairs(I and I.list(index, "LT") or {}) do
    if I.str(rec, "LT", "source") == "craft" then
      local key = I.str(rec, "LT", "item")
      local itemID = key and tonumber(string.match(key, "^(%d+)"))
      local cnt = I.num(rec, "LT", "count")
      craftedGreen = craftedGreen + ((cnt and cnt >= 1 and cnt < 100000) and floor(cnt) or 1)
      seen = seen + 1
      if finite(rec.t) and seen <= 400 then
        local found = {
          t = rec.t, level = level(I.str(rec, "LT", "level")),
          name = itemID and itemName(char, itemID) or nil,
        }
        if not firstCraft then firstCraft = found end
        local near, n = nil, 0
        for _, p in ipairs(crafting) do
          if nearest(p.points, rec.t) <= Handwerk.CRAFT_GAP then near, n = p, n + 1 end
        end
        if n == 1 and not near.firstCraft then near.firstCraft = found end
      end
    end
  end

  local balance = {
    mined = counterValue(char, "gather", "ore"),
    picked = counterValue(char, "gather", "herb"),
    skinned = counterValue(char, "gather", "leather"),
    fished = counterSum(char, "fishing"),
    crafted = counterSum(char, "crafted") + craftedGreen,
  }
  local lastT = finite(index.lastT) and index.lastT or base
  for _, p in ipairs(list) do lastT = max(lastT, p.last.t) end
  return {
    professions = list, recipes = recipes, unassigned = unassigned, balance = balance, firstCraft = firstCraft,
    playTotal = playSeconds(index, base, lastT), truncated = truncated,
  }
end

-- Handwerk.aggregate(index) -> res (nil for an invalid index); empty lists and zero counters when nothing was ever recorded
function Handwerk.aggregate(index)
  if type(index) ~= "table" or type(index.char) ~= "table" then return nil end
  local c = cache[index]
  if c then return c end
  local ok, res = pcall(compute, index)
  if not ok then
    res = { professions = {}, recipes = {}, unassigned = 0, balance = { mined = 0, picked = 0, skinned = 0, fished = 0, crafted = 0 },
      playTotal = 0, truncated = false, error = tostring(res) }
  end
  cache[index] = res
  return res
end

-- true if there is anything to show (a profession, a recipe or one of the counters)
function Handwerk.hasData(res)
  if type(res) ~= "table" then return false end
  if #res.professions > 0 or #res.recipes > 0 then return true end
  local b = res.balance or {}
  return (b.mined or 0) + (b.picked or 0) + (b.skinned or 0) + (b.fished or 0) + (b.crafted or 0) > 0
end

function Handwerk.clear()
  scan = nil
  cache = setmetatable({}, { __mode = "k" })
end
