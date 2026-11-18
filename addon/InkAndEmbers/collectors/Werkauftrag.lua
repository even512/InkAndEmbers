-- Collector 'Werkauftrag' (WoW Forever only; Retail has no recipe cache): the work order. A to-do in chars[guid].vorhaben with the
-- additive field p.werk describes what is to be made, in steps; the shopping list (Einkaufszettel) is what is still missing for
-- all open orders together. Like every collector it keeps running with the module Crafting switched off (counting, mail, migration),
-- only the bars and the entry points live in the module.
--   p.werk = { v = 1, prof, goal (target skill of a route order, nil for a single recipe), recipe (main recipe of a single order),
--     n (crafts of a single order), name, resolve (bool), made / last (output items of the main step, same meaning as p.shop),
--     created, cur (index of the current step), steps = { step, ... } }
--   craft step = { kind = "craft", recipe, n (planned crafts; an upper bound for a precursor), out (itemID | nil), q (output per
--     craft), prof (profession of the recipe, may differ: precursor in another profession), name, pre (precursor: true | nil),
--     from / to (skill range of a route stage), y / g (yellow and grey threshold, see Werk.band), r (reagent snapshot { {id, qty} }),
--     unknown (reagents not known yet: true | nil), made (output items, or casts without an output item), last (bag count of out),
--     done (time | nil) }
--   trainer step = { kind = "trainer", recipe, prof, name, cost (copper), at (skill to learn it), npc (npcID | nil), done }
-- Stations (derived, never stored): 1 plan (before the order exists, the bar), 2 buy (something is missing), 3 make (all there),
-- "done" (every step done: Plans.finishPlan, so plansDone counts). Steps are counted live:
--   * craft steps with an output item: growth of that item in the bags (like p.shop), shared out in step order; without one
--     (enchantments): UNIT_SPELLCAST_SUCCEEDED of the recipe spell;
--   * a route stage (to) is done once the profession skill reached `to`; the crafts still needed are re-estimated from the live skill
--     (Werk.expected); a precursor (pre) needs only what its consumers still lack (bags first) - nothing is double counted;
--   * a trainer step is done once the recipe is learned (recipe cache, spellbook).
-- Mail ("unterwegs per Post"): own purchases at the auction house (the dock announces them: Werk.expectPurchase, then
-- COMMODITY_PURCHASE_SUCCEEDED; COMMODITY_PURCHASE_FAILED counts nothing) are kept per character in chars[guid].werkMail =
-- { [itemID] = { n, at, bag } } until they arrive in the bags (bag growth) or the inbox shows fewer (read while the mailbox is open);
-- after Werk.MAIL_TTL (48 h) without arriving they are dropped. Money.lua and Social.lua keep their own hooks: this file only listens.
-- Migration: once per character (chars[guid].werkMigrated = 1) every open to-do with p.shop gets p.werk (one craft step plus its
-- precursors, same count / made / last); p.shop stays and is marked p.shop.migrated = true. Readers take p.werk, else p.shop.
-- Nothing is bought, clicked or crafted here; foreign text (item and recipe names) only through Sanitize.display.
local _, ns = ...
local Core, Store = ns.Core, ns.Store

local floor, min, max, ceil = math.floor, math.min, math.max, math.ceil

local Werk = {}
ns.Werk = Werk

Werk.STEPS_MAX = 60        -- steps per order
Werk.CRAFTS_MAX = 9999     -- crafts per order (all steps together)
Werk.LINES_MAX = 40        -- material lines per order and in the shopping list
Werk.RESOLVE_DEPTH = 3     -- levels of precursors
Werk.MAIL_TTL = 48 * 3600  -- seconds: a purchase that never arrived is dropped
Werk.MAIL_MAX = 80         -- items kept in werkMail
Werk.PURCHASE_WAIT = 60    -- seconds between Werk.expectPurchase and COMMODITY_PURCHASE_SUCCEEDED
Werk.CHANGE_DELAY = 0.4    -- seconds: bag changes are counted in one batch
Werk.INBOX_MAX = 50
Werk.MAIL_ATTACH = 16
Werk.DELIVERY_WAIT = 60    -- seconds: a purchase is only compared with the inbox once it had time to arrive there
Werk.STUCK_CHANCE = 0.02   -- below this skill-up chance a route stage counts as stuck (grey)

local T = ns.Locale.ns("col.Werkauftrag", {
  titleOne = "Werkauftrag: %s× %s",
  titleRoute = "Werkauftrag: %s bis %s",
  ready = "bereit",
  unknownMat = "Material zeigt das Spiel nach dem Lernen",
  errSteps = "Der Werkauftrag ist zu lang (höchstens 60 Schritte).",
  errEmpty = "Der Werkauftrag hat keinen Schritt.",
  errNoOrder = "Diesen Werkauftrag gibt es nicht mehr.",
})
Werk.TEXT = T

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

local function nonNeg(v)
  v = num(v)
  if not v or v < 0 then return nil end
  return floor(v)
end

local function str(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

local function clean(s, n)
  s = str(s)
  if not s then return nil end
  local S = ns.Sanitize
  s = S and S.display and S.display(s, n or 60) or s
  return str(s)
end

local function now()
  local ok, t = pcall(time)
  return (ok and num(t)) and floor(t) or 0
end

local function E() return ns.Einkauf end

-- Same switch as the shopping list: the module Crafting is loaded (Journal.Handwerk active) - entry points and new orders only then
function Werk.active()
  local Ek = E()
  return Ek ~= nil and type(Ek.active) == "function" and Ek.active() == true
end

-- Skill thresholds ---------------------------------------------------------------------------------------------------------------

-- Band of a recipe: { l = learn value, y = yellow from, gs = green from, g = grey from }. Rule of thumb (classic) from the learn value L:
-- orange [L, L+25), yellow [L+25, L+50), green [L+50, L+75), grey >= L+75. Live values win: rec.t (maxTrivialLevel, recipe cache)
-- is the grey threshold; rec.d (relativeDifficulty at the skill the window was read with, `at`) moves yellow/green so that the
-- colour at that skill is the one the game showed. nil when nothing is known.
function Werk.band(L, rec, at)
  L = nonNeg(L)
  local y, g
  if L then y, g = L + 25, L + 75 end
  local t = type(rec) == "table" and posInt(rec.t) or nil
  if t then
    g = t
    if not y or y >= g then y = g - 50 end
  end
  local d = type(rec) == "table" and nonNeg(rec.d) or nil
  at = nonNeg(at)
  if not g and d and at then
    -- only the colour is known: assume the middle of that colour's band at the scanned skill
    if d == 0 then y, g = at + 13, at + 63
    elseif d == 1 then y, g = at - 12, at + 38
    elseif d == 2 then y, g = at - 37, at + 13
    else y, g = at - 63, at end
  end
  if not (y and g) then return nil end
  if d and at then
    if d == 0 and y <= at then y = at + 1 end
    if d == 1 and y > at then y = at end
    if d >= 1 and g <= at and d < 3 then g = at + 1 end
    -- yellow at `at`: green must start above it (gs = middle of yellow and grey)
    if d == 1 and floor((y + g) / 2) <= at then g = 2 * (at + 1) - y end
    if d == 2 then
      local gs = floor((y + g) / 2)
      if gs > at then y = 2 * at - g end
    end
    if d == 3 and g > at then g = at end
  end
  if g <= y then g = y + 1 end
  local gs = floor((y + g) / 2)
  return { l = L, y = y, gs = gs, g = g }
end

-- colour at a skill: "orange" | "yellow" | "green" | "grey"
function Werk.color(band, skill)
  if type(band) ~= "table" or not num(skill) then return nil end
  if skill < band.y then return "orange" end
  if skill < (band.gs or floor((band.y + band.g) / 2)) then return "yellow" end
  if skill < band.g then return "green" end
  return "grey"
end

-- skill-up chance of one craft at a skill: orange 1; yellow and green (G - skill) / (G - Y), limited to [0, 1]; grey 0
function Werk.chance(band, skill)
  if type(band) ~= "table" or not num(skill) then return nil end
  local y, g = num(band.y), num(band.g)
  if not (y and g) then return nil end
  if skill < y then return 1 end
  if skill >= g then return 0 end
  local p = (g - skill) / (g - y)
  if p > 1 then p = 1 elseif p < 0 then p = 0 end
  return p
end

-- expected crafts from skill `from` to skill `to` (sum of 1/p per point); nil when a point is grey on the way (cannot be reached)
function Werk.expected(band, from, to)
  from, to = num(from), num(to)
  if not (from and to) then return nil end
  local sum = 0
  for s = floor(from), floor(to) - 1 do
    local p = Werk.chance(band, s)
    if not p or p < Werk.STUCK_CHANCE then return nil end
    sum = sum + 1 / p
  end
  return sum
end

-- Reading the character --------------------------------------------------------------------------------------------------------

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a = pcall(fn, ...)
  if not ok or isSecret(a) then return nil end
  return a
end

local function callAll(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  table.remove(r, 1)
  return r
end

-- current skill of a profession (skill line id = profession id of the recipe cache): GetProfessions, else the skill of the last scan
function Werk.skill(prof)
  prof = posInt(prof)
  if not prof then return nil end
  local idx = callAll(rawget(_G, "GetProfessions"))
  if idx then
    for i = 1, 6 do
      local v = num(idx[i])
      if v then
        local info = callAll(rawget(_G, "GetProfessionInfo"), v)
        if info and num(info[7]) == prof and num(info[3]) then return floor(info[3]), num(info[4]) and floor(info[4]) or nil end
      end
    end
  end
  local Ek = E()
  local c = Ek and Ek.cache and Ek.cache()
  local p = c and c[prof]
  if type(p) == "table" and num(p.skill) then return floor(p.skill), num(p.max) and floor(p.max) or nil end
  return nil
end

-- a recipe of the cache (profession nil = any) -> rec | nil
function Werk.cached(prof, recipe)
  local Ek = E()
  if not (Ek and Ek.recipe) then return nil end
  local _, rec = Ek.recipe(prof, recipe)
  return type(rec) == "table" and rec or nil
end

-- recipe learned: recipe cache (any profession), client spellbook, spells the collectors saw being learned
function Werk.knows(recipe)
  recipe = posInt(recipe)
  if not recipe then return false end
  local rec = Werk.cached(nil, recipe)
  if type(rec) == "table" and rec.l == true then return true end
  local SB = ns.Journal and ns.Journal.SpellBook
  if SB and type(SB.clientKnows) == "function" then
    local ok, k = pcall(SB.clientKnows, recipe)
    if ok and k == true then return true end
  end
  local c = Store and Store.char and Store.char()
  local sp = type(c) == "table" and type(c.snapshots) == "table" and c.snapshots.spells or nil
  return type(sp) == "table" and sp[recipe] ~= nil
end

-- reagents of a craft step: the recipe cache (live, so an order "re-calculates" after learning) else the snapshot -> list, known
function Werk.reagents(step)
  local Ek = E()
  local rec = Werk.cached(step.prof, step.recipe) or Werk.cached(nil, step.recipe)
  local list = rec and Ek.reagents(rec) or nil
  if list and #list > 0 then return list, true end
  list = {}
  if type(step.r) == "table" then
    for _, e in ipairs(step.r) do
      local id = type(e) == "table" and posInt(e[1] or e.id) or nil
      local qty = type(e) == "table" and posInt(e[2] or e.qty) or nil
      if id and qty then list[#list + 1] = { id = id, qty = qty } end
    end
  end
  return list, #list > 0
end

-- Building orders ---------------------------------------------------------------------------------------------------------------

local function recipeName(prof, recipe, fallback)
  local rec = Werk.cached(prof, recipe)
  return clean(rec and rec.n, 60) or clean(fallback, 60) or ("#" .. tostring(recipe))
end

local function snapshot(list)
  local out = {}
  for _, r in ipairs(list or {}) do out[#out + 1] = { r.id, r.qty } end
  return out
end

-- One validated step (input from the route model or a migration) -> step | nil
local function cleanStep(s)
  if type(s) ~= "table" or isSecret(s) then return nil end
  local recipe = posInt(s.recipe)
  if not recipe then return nil end
  if s.kind == "trainer" then
    return { kind = "trainer", recipe = recipe, prof = posInt(s.prof), name = clean(s.name, 60) or recipeName(s.prof, recipe),
      cost = nonNeg(s.cost) or 0, at = nonNeg(s.at), npc = posInt(s.npc), done = posInt(s.done) }
  end
  if s.kind ~= "craft" then return nil end
  local n = posInt(s.n)
  if not n then return nil end
  local st = { kind = "craft", recipe = recipe, n = min(n, Werk.CRAFTS_MAX), out = posInt(s.out), q = posInt(s.q) or 1,
    prof = posInt(s.prof), name = clean(s.name, 60) or recipeName(s.prof, recipe), pre = s.pre == true or nil,
    from = nonNeg(s.from), to = posInt(s.to), y = num(s.y), g = num(s.g), made = nonNeg(s.made) or 0, last = nonNeg(s.last),
    done = posInt(s.done), unknown = s.unknown == true or nil }
  if type(s.r) == "table" and not isSecret(s.r) then
    local r = {}
    for _, e in ipairs(s.r) do
      local id = type(e) == "table" and posInt(e[1] or e.id) or nil
      local qty = type(e) == "table" and posInt(e[2] or e.qty) or nil
      if id and qty and #r < 16 then r[#r + 1] = { id, qty } end
    end
    if #r > 0 then st.r = r end
  end
  return st
end

-- Precursors: before the first consumer of a material that a LEARNED recipe in the cache makes (also in another profession, e.g.
-- copper bars = mining), a step "pre" is inserted (depth RESOLVE_DEPTH, no cycles). Its n is the upper bound (all of it); what the
-- bags hold is taken into account live (Werk.compute). steps: list of craft/trainer steps -> new list
function Werk.addPrecursors(steps, resolve)
  if not resolve then return steps end
  local Ek = E()
  if not (Ek and Ek.producer) then return steps end
  local out, preOf = {}, {}
  -- post-order: the precursors of a precursor come before it
  local function need(step, crafts, depth, stack, before)
    for _, rg in ipairs((Werk.reagents(step))) do
      local pid, rid, prec = Ek.producer(rg.id, step.prof)
      if rid and depth < Werk.RESOLVE_DEPTH and not stack[rid] and rid ~= step.recipe then
        local per = posInt(prec.q) or 1
        local crafts2 = ceil(rg.qty * crafts / per)
        local pre = preOf[rid]
        local fresh = pre == nil
        if fresh then
          pre = { kind = "craft", recipe = rid, n = 0, out = rg.id, q = per, prof = pid, pre = true,
            name = clean(prec.n, 60) or ("#" .. rid), made = 0, r = snapshot(Ek.reagents(prec)) }
          preOf[rid] = pre
        end
        pre.n = min(Werk.CRAFTS_MAX, pre.n + crafts2)
        stack[rid] = true
        need(pre, crafts2, depth + 1, stack, before)
        stack[rid] = nil
        if fresh then before[#before + 1] = pre end
      end
    end
  end
  for _, s in ipairs(steps) do
    if s.kind == "craft" and not s.pre then
      local before = {}
      need(s, s.n, 0, {}, before)
      for _, b in ipairs(before) do out[#out + 1] = b end
    end
    out[#out + 1] = s
  end
  return out
end

-- Order of one recipe: count crafts, precursors (resolve) -> werk | nil, reason ("anzahl" | "rezept" | "leer")
function Werk.planRecipe(prof, recipe, count, resolve)
  local Ek = E()
  count = posInt(count)
  local maxCount = Ek and Ek.COUNT_MAX or 999
  if not count or count > maxCount then return nil, "anzahl" end
  local pid, rec
  if Ek and Ek.recipe then pid, rec = Ek.recipe(prof, recipe) end
  if not pid then return nil, "rezept" end
  local reagents = Ek.reagents(rec)
  if #reagents == 0 then return nil, "leer" end
  recipe = posInt(recipe)
  local out = posInt(rec.o)
  local main = { kind = "craft", recipe = recipe, n = count, out = out, q = posInt(rec.q) or 1, prof = pid,
    name = clean(rec.n, 60) or ("#" .. recipe), made = 0, last = out and Ek.count(out, false) or nil, r = snapshot(reagents) }
  local steps = Werk.addPrecursors({ main }, resolve == true)
  return { v = 1, prof = pid, recipe = recipe, n = count, name = main.name, resolve = resolve == true, made = 0, last = main.last,
    created = now(), cur = 1, steps = steps }
end

-- Validated order from a route plan (journal/model/Route.lua) or any other spec -> werk | nil, reason
function Werk.normalize(spec)
  if type(spec) ~= "table" or isSecret(spec) or type(spec.steps) ~= "table" then return nil, "leer" end
  local steps, crafts = {}, 0
  for _, s in ipairs(spec.steps) do
    local c = cleanStep(s)
    if c then
      if #steps >= Werk.STEPS_MAX then return nil, "schritte" end
      if c.kind == "craft" then
        crafts = crafts + c.n
        if crafts > Werk.CRAFTS_MAX then return nil, "anzahl" end
      end
      steps[#steps + 1] = c
    end
  end
  if #steps == 0 then return nil, "leer" end
  local w = { v = 1, prof = posInt(spec.prof), goal = posInt(spec.goal), recipe = posInt(spec.recipe), n = posInt(spec.n),
    name = clean(spec.name, 60), resolve = spec.resolve == true, made = nonNeg(spec.made) or 0, last = nonNeg(spec.last),
    created = posInt(spec.created) or now(), cur = 1, steps = steps }
  if not w.prof then return nil, "rezept" end
  return w
end

-- p.shop (old shopping list) -> p.werk: the intermediate lines become precursor steps (deepest first), then the recipe itself
function Werk.fromShop(shop)
  if type(shop) ~= "table" or isSecret(shop) then return nil end
  local recipe, count = posInt(shop.recipe), posInt(shop.count)
  if not (recipe and count) then return nil end
  local Ek = E()
  local steps = {}
  local lines = type(shop.lines) == "table" and shop.lines or {}
  local function addPre(li)
    local rid, crafts = posInt(li.recipe), posInt(li.craft)
    if not (rid and crafts) then return end
    local pid, prec
    if Ek and Ek.recipe then pid, prec = Ek.recipe(nil, rid) end
    steps[#steps + 1] = { kind = "craft", recipe = rid, n = crafts, out = posInt(li.id), q = prec and posInt(prec.q) or 1, prof = pid,
      pre = true, name = clean(prec and prec.n, 60) or clean(li.n, 60), r = prec and snapshot(Ek.reagents(prec)) or nil }
  end
  for _, li in ipairs(lines) do if type(li) == "table" and li.sub then addPre(li) end end
  for _, li in ipairs(lines) do if type(li) == "table" and not li.sub then addPre(li) end end
  local main = { kind = "craft", recipe = recipe, n = count, out = posInt(shop.out), q = posInt(shop.qty) or 1, prof = posInt(shop.prof),
    name = clean(shop.name, 60), made = nonNeg(shop.made) or 0, last = nonNeg(shop.last) }
  local r = {}
  for _, li in ipairs(lines) do
    if type(li) == "table" and not li.sub and posInt(li.id) and posInt(li.need) then r[#r + 1] = { li.id, max(1, floor(li.need / count)) } end
  end
  if #r > 0 then main.r = r end
  steps[#steps + 1] = main
  return Werk.normalize({ prof = shop.prof, recipe = recipe, n = count, name = shop.name, resolve = shop.resolve == true,
    made = shop.made, last = shop.last, steps = steps, created = nil })
end

-- Access ------------------------------------------------------------------------------------------------------------------------

local function P() return ns.Plans end

-- the order of a to-do: p.werk, else an old p.shop read as an order (not stored) -> werk, migrated? | nil
function Werk.of(p)
  if type(p) ~= "table" then return nil end
  if type(p.werk) == "table" and type(p.werk.steps) == "table" then return p.werk end
  if type(p.shop) == "table" then
    return Werk.fromShop(p.shop), true
  end
  return nil
end

-- open orders (creation order) -> { { id, p, w } }; prof filters
function Werk.orders(prof)
  local Pl = P()
  local list = Pl and Pl.rawList and Pl.rawList()
  local out = {}
  if not list then return out end
  prof = posInt(prof)
  for _, p in ipairs(list) do
    if type(p) == "table" and not p.done and type(p.id) == "number" and (type(p.werk) == "table" or type(p.shop) == "table") then
      local w = Werk.of(p)
      if w and (not prof or w.prof == prof) then out[#out + 1] = { id = p.id, p = p, w = w } end
    end
  end
  table.sort(out, function(a, b)
    local ca, cb = num(a.p.created) or 0, num(b.p.created) or 0
    if ca ~= cb then return ca < cb end
    return a.id < b.id
  end)
  return out
end

function Werk.get(id)
  local Pl = P()
  local p = Pl and Pl.raw and Pl.raw(id)
  if not p or p.done then return nil end
  return Werk.of(p), p
end

-- open route order of a profession -> id | nil
function Werk.findRoute(prof)
  for _, o in ipairs(Werk.orders(prof)) do
    if o.w.goal then return o.id end
  end
  return nil
end

-- open single order of a recipe -> id | nil
function Werk.find(recipe)
  recipe = posInt(recipe)
  if not recipe then return nil end
  for _, o in ipairs(Werk.orders()) do
    if not o.w.goal and o.w.recipe == recipe then return o.id end
  end
  return nil
end

function Werk.titleText(w)
  if type(w) ~= "table" then return nil end
  if w.goal then
    local Ek = E()
    local c = Ek and Ek.cache and Ek.cache()
    local pn = c and c[w.prof] and clean(c[w.prof].name, 40) or tostring(w.prof)
    return T("titleRoute", pn, tostring(w.goal))
  end
  return T("titleOne", tostring(posInt(w.n) or 1), clean(w.name, 60) or "?")
end

local function store(p, w, text)
  Werk.gen = (Werk.gen or 0) + 1
  local Pl = P()
  p.werk = w
  local t = Pl.cleanText(text)
  if t then p.text = t end
  Pl.changed()
end

-- New order (or update of the open one: same recipe for a single order, same profession for a route order)
-- -> id, "new" | "update" | nil, reason
local function put(w)
  local Pl = P()
  if not (Pl and Store and Store.ready and Store.ready()) then return nil, "nicht-bereit" end
  local old = w.goal and Werk.findRoute(w.prof) or (not w.goal and Werk.find(w.recipe)) or nil
  local text = Werk.titleText(w)
  if old then
    local p = Pl.raw(old)
    if type(p.werk) ~= "table" and type(p.shop) == "table" then p.shop.migrated = true end
    w.created = num(p.created) or w.created
    store(p, w, text)
    return old, "update"
  end
  Werk.gen = (Werk.gen or 0) + 1
  local id, e = Pl.add({ kind = "free", text = text, werk = w })
  if not id then return nil, e end
  return id, "new"
end

function Werk.addRecipe(prof, recipe, count, resolve)
  if not Werk.active() then return nil, "aus" end
  local w, err = Werk.planRecipe(prof, recipe, count, resolve)
  if not w then return nil, err end
  return put(w)
end

-- route = output of Journal.Route.plan (or any spec with prof, goal, steps, resolve)
function Werk.addRoute(route)
  if not Werk.active() then return nil, "aus" end
  if type(route) ~= "table" or not posInt(route.goal) then return nil, "leer" end
  local w, err = Werk.normalize({ prof = route.prof, goal = route.goal, name = route.name, resolve = route.resolve, steps = route.steps })
  if not w then return nil, err end
  return put(w)
end

function Werk.reasonText(reason, extra)
  if reason == "schritte" then return T.errSteps end
  if reason == "kein-auftrag" then return T.errNoOrder end
  if reason == "leer" and extra == "route" then return T.errEmpty end
  local Ek = E()
  return Ek and Ek.reasonText and Ek.reasonText(reason, extra) or nil
end

-- Mail ("unterwegs per Post") --------------------------------------------------------------------------------------------------

local function mailTable(create)
  local c = Store and Store.char and Store.char()
  if type(c) ~= "table" then return nil end
  if type(c.werkMail) ~= "table" then
    if not create then return nil end
    c.werkMail = {}
  end
  return c.werkMail
end

local function bags(id)
  local Ek = E()
  return Ek and Ek.count and Ek.count(id, false) or nil
end

-- drops purchases older than MAIL_TTL and empty entries
function Werk.pruneMail(at)
  local m = mailTable(false)
  if not m then return 0 end
  at = num(at) or now()
  local dropped = 0
  for id, e in pairs(m) do
    if type(e) ~= "table" or not posInt(e.n) or (num(e.at) or 0) + Werk.MAIL_TTL < at then
      m[id] = nil
      dropped = dropped + 1
    end
  end
  return dropped
end

-- items of this id still on the way by mail (0 when none)
function Werk.inMail(itemID)
  local m = mailTable(false)
  local e = m and m[posInt(itemID) or 0]
  if type(e) ~= "table" then return 0 end
  if (num(e.at) or 0) + Werk.MAIL_TTL < now() then return 0 end
  return posInt(e.n) or 0
end

-- all of it -> { { id, n, at } } sorted by id
function Werk.mailList()
  local out = {}
  local m = mailTable(false)
  if not m then return out end
  local t = now()
  for id, e in pairs(m) do
    if type(id) == "number" and type(e) == "table" and posInt(e.n) and (num(e.at) or 0) + Werk.MAIL_TTL >= t then
      out[#out + 1] = { id = id, n = posInt(e.n), at = num(e.at) }
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- a purchase arrived as mail: n items of itemID (also used by tests and the dock's own success path)
function Werk.markBought(itemID, n)
  itemID, n = posInt(itemID), posInt(n)
  if not (itemID and n) then return false end
  local m = mailTable(true)
  if not m then return false end
  local e = m[itemID]
  if type(e) ~= "table" then
    local count = 0
    for _ in pairs(m) do count = count + 1 end
    if count >= Werk.MAIL_MAX then return false end
    e = { n = 0 }
    m[itemID] = e
  end
  e.n = min(2147483647, (posInt(e.n) or 0) + n)
  e.at = now()
  e.bag = bags(itemID) or nonNeg(e.bag) or 0
  Werk.session[itemID] = (Werk.session[itemID] or 0) + n
  Werk.gen = (Werk.gen or 0) + 1
  if P() and P().changed then P().changed() end
  return true
end

-- what the dock bought in this session ("gekauft"): itemID -> n
Werk.session = {}

-- The dock announces the purchase it is about to confirm (Klick 2); COMMODITY_PURCHASE_SUCCEEDED books it, _FAILED forgets it
local pending = nil
function Werk.expectPurchase(itemID, n)
  itemID, n = posInt(itemID), posInt(n)
  if not (itemID and n) then
    pending = nil
    return false
  end
  local t = type(GetTime) == "function" and num(call(GetTime)) or 0
  pending = { id = itemID, n = n, at = t }
  return true
end

function Werk.cancelPurchase() pending = nil end
function Werk.pendingPurchase() return pending end

local function purchaseDone(ok)
  local pd = pending
  pending = nil
  if not ok or not pd then return false end
  local t = type(GetTime) == "function" and num(call(GetTime)) or 0
  if t - (pd.at or 0) > Werk.PURCHASE_WAIT then return false end
  return Werk.markBought(pd.id, pd.n)
end
Werk._purchaseDone = purchaseDone

-- bag growth of a mailed item = it arrived (taken from the mailbox)
local function mailArrivals()
  local m = mailTable(false)
  if not m then return end
  Werk.gen = (Werk.gen or 0) + 1
  for id, e in pairs(m) do
    if type(e) == "table" then
      local cur = bags(id)
      local before = nonNeg(e.bag)
      if cur then
        if before and cur > before then e.n = max(0, (posInt(e.n) or 0) - (cur - before)) end
        e.bag = cur
      end
      if not posInt(e.n) then m[id] = nil end
    end
  end
end

-- inbox read while the mailbox is open: never more on the way than the inbox holds (only when the whole inbox was readable, and only
-- for purchases older than DELIVERY_WAIT: a mail that is not delivered yet does not count as taken)
function Werk.readInbox()
  local m = mailTable(false)
  if not m or next(m) == nil then return false end
  local shown = callAll(rawget(_G, "GetInboxNumItems"))
  local n, total = shown and num(shown[1]), shown and num(shown[2])
  if not n or n > Werk.INBOX_MAX or (total and total > n) then return false end
  local have = {}
  for i = 1, floor(n) do
    local h = callAll(rawget(_G, "GetInboxHeaderInfo"), i)
    local want = h and (num(h[8]) or (h[8] == true and Werk.MAIL_ATTACH) or 0) or 0
    if want > 0 then
      for j = 1, Werk.MAIL_ATTACH do
        local info = callAll(rawget(_G, "GetInboxItem"), i, j)
        local id, c = info and posInt(info[2]), info and posInt(info[4])
        if id then have[id] = (have[id] or 0) + (c or 1) end
      end
    end
  end
  local t = now()
  Werk.gen = (Werk.gen or 0) + 1
  for id, e in pairs(m) do
    if type(e) == "table" and t - (num(e.at) or 0) >= Werk.DELIVERY_WAIT then
      local inBox = have[id] or 0
      if (posInt(e.n) or 0) > inBox then e.n = inBox end
      if not posInt(e.n) then m[id] = nil end
    end
  end
  return true
end

-- Live state of an order -------------------------------------------------------------------------------------------------------

local function craftsDone(step)
  local made = nonNeg(step.made) or 0
  if step.out then return floor(made / (posInt(step.q) or 1)) end
  return made
end

-- crafts still to do for one craft step (without the precursor rule) -> left, stuck
local function leftOf(step, skillOf)
  if step.done then return 0 end
  local planned = max(0, (posInt(step.n) or 1) - craftsDone(step))
  if step.to then
    local sk = skillOf(step.prof)
    if sk then
      if sk >= step.to then return 0 end
      local band = { y = num(step.y), g = num(step.g) }
      if band.y and band.g then
        local e = Werk.expected(band, max(sk, step.from or sk), step.to)
        if e then return max(1, ceil(e)) end
        return max(1, planned), true
      end
    end
  end
  return planned
end

-- Werk.compute(w, ctx): per step { state = "done" | "open", left (crafts), stuck }, the external demand { [itemID] = n } (what this
-- order still needs from outside: precursor products are made, not bought), selfMade { [itemID] = n }, unknown = { step names }.
-- ctx = { skill = function(prof), count = function(itemID) } (defaults: live).
function Werk.compute(w, ctx)
  ctx = type(ctx) == "table" and ctx or {}
  local skillOf = ctx.skill or function(prof) return (Werk.skill(prof)) end
  local count = ctx.count or bags
  local knows = ctx.knows or Werk.knows
  local steps = type(w) == "table" and type(w.steps) == "table" and w.steps or {}
  local rows, need, selfMade, unknown = {}, {}, {}, {}
  for k = #steps, 1, -1 do
    local s = steps[k]
    local row = { step = s, index = k }
    if s.kind == "trainer" then
      row.done = s.done ~= nil or knows(s.recipe)
      row.left = row.done and 0 or 1
    else
      local left, stuck = leftOf(s, skillOf)
      local reagents, known = Werk.reagents(s)
      if s.pre and s.out and not s.done then
        -- the precursor makes what the bags do not cover, at most its planned crafts; the bag part and a rest beyond the plan stay
        -- as demand of the order (shared bags, the shopping list buys the rest)
        local q = posInt(s.q) or 1
        local want = max(0, (need[s.out] or 0) - (count(s.out) or 0))
        left = min(left, ceil(want / q))
        local made = min(left * q, want)
        selfMade[s.out] = (selfMade[s.out] or 0) + made
        local restNeed = (need[s.out] or 0) - made
        need[s.out] = restNeed > 0 and restNeed or nil
      end
      row.left, row.stuck, row.known = left, stuck, known
      row.done = left <= 0
      if left > 0 then
        if known then
          for _, rg in ipairs(reagents) do need[rg.id] = (need[rg.id] or 0) + rg.qty * left end
        else
          unknown[#unknown + 1] = s.name or ("#" .. tostring(s.recipe))
        end
      end
    end
    rows[k] = row
  end
  local cur
  for k = 1, #steps do
    if not rows[k].done then cur = k break end
  end
  return { rows = rows, need = need, selfMade = selfMade, unknown = unknown, cur = cur, done = cur == nil and #steps > 0 }
end

-- itemID name for display (client, then the order's stored names)
local function itemName(id)
  local Ek = E()
  return Ek and Ek.itemName and Ek.itemName(id) or nil
end

-- Status of one order with the bags shared among the orders (avail: itemID -> what is left for this order; changed here).
-- -> { id, station = 2 | 3 | "done", cur, next, lines = { { id, name, need, have, mail, missing } }, missing, unknown, steps = rows }
local function orderStatus(o, avail, ctx)
  local c = Werk.compute(o.w, ctx)
  local lines, missingN, mailN = {}, 0, 0
  local ids = {}
  for id in pairs(c.need) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local n = c.need[id]
    if n > 0 then
      local a = avail[id]
      if a == nil then a = { bag = (ctx and ctx.count or bags)(id) or 0, mail = Werk.inMail(id) } avail[id] = a end
      local fromBag = min(a.bag, n)
      a.bag = a.bag - fromBag
      local fromMail = min(a.mail, n - fromBag)
      a.mail = a.mail - fromMail
      local missing = n - fromBag - fromMail
      if missing > 0 then missingN = missingN + 1 end
      if fromMail > 0 then mailN = mailN + 1 end
      if #lines < Werk.LINES_MAX then
        lines[#lines + 1] = { id = id, name = itemName(id) or ("#" .. id), need = n, have = fromBag, mail = fromMail, missing = missing }
      end
    end
  end
  local st = { id = o.id, w = o.w, cur = c.cur, steps = c.rows, lines = lines, missing = missingN, mail = mailN, unknown = c.unknown,
    selfMade = c.selfMade }
  if c.done then
    st.station = "done"
    st.next = { kind = "done" }
  elseif missingN > 0 then
    st.station = 2
    local first
    for _, li in ipairs(lines) do if li.missing > 0 then first = li break end end
    st.next = { kind = "buy", item = first and first.id, n = first and first.missing, name = first and first.name }
  elseif mailN > 0 then
    st.station = 2
    st.next = { kind = "mail" }
  else
    st.station = 3
    local row = c.rows[c.cur]
    local s = row and row.step
    if s and s.kind == "trainer" then
      st.next = { kind = "trainer", step = s, recipe = s.recipe, npc = s.npc, name = s.name, cost = s.cost }
    elseif s then
      st.next = { kind = "craft", step = s, recipe = s.recipe, prof = s.prof, n = row.left, name = s.name, stuck = row.stuck }
    end
  end
  return st
end

-- Plans.list decorates every to-do in one go: the statuses of all orders are computed once per pass (same GetTime, same count
-- generation of the bags, no change of the orders in between: Werk.gen) instead of once per to-do
Werk.gen = Werk.gen or 0
local memo = { key = nil, byId = {} }
function Werk.cachedStatus(id)
  local Ek = E()
  local key = tostring(type(GetTime) == "function" and call(GetTime) or 0) .. "|" .. tostring(Ek and Ek.gen) .. "|" .. Werk.gen
  if memo.key ~= key then
    memo.key, memo.byId = key, {}
    for _, st in ipairs(Werk.statusAll()) do memo.byId[st.id] = st end
  end
  return memo.byId[id]
end

-- one order (bags shared with the orders created before it) -> status | nil
function Werk.status(id, ctx)
  local avail = {}
  for _, o in ipairs(Werk.orders()) do
    local st = orderStatus(o, avail, ctx)
    if o.id == id then return st end
  end
  return nil
end

-- all open orders -> { status, ... } (creation order)
function Werk.statusAll(prof, ctx)
  local avail, out = {}, {}
  prof = posInt(prof)
  for _, o in ipairs(Werk.orders()) do
    local st = orderStatus(o, avail, ctx)
    if not prof or o.w.prof == prof then out[#out + 1] = st end
  end
  return out
end

-- The shopping list over all open orders: what is missing (demand - bags - on the way by mail; bank only as a hint).
-- -> { orders = n, lines = { { id, name, need, have, mail, bank, missing, bought (this session), orders = { id, ... } } },
--      missing = lines with something missing, mail = items on the way, unknown = { names } }
function Werk.shoppingList(ctx)
  local need, forOrders, unknown = {}, {}, {}
  local orders = Werk.orders()
  for _, o in ipairs(orders) do
    local c = Werk.compute(o.w, ctx)
    for id, n in pairs(c.need) do
      if n > 0 then
        need[id] = (need[id] or 0) + n
        forOrders[id] = forOrders[id] or {}
        local f = forOrders[id]
        f[#f + 1] = o.id
      end
    end
    for _, u in ipairs(c.unknown) do unknown[#unknown + 1] = u end
  end
  local ids = {}
  for id in pairs(need) do ids[#ids + 1] = id end
  table.sort(ids)
  local lines, missingN, mailN = {}, 0, 0
  local count = ctx and ctx.count or bags
  local Ek = E()
  for _, id in ipairs(ids) do
    local have = count(id) or 0
    local withBank = Ek and Ek.count and Ek.count(id, true) or nil
    local mail = Werk.inMail(id)
    local missing = max(0, need[id] - have - mail)
    if missing > 0 then missingN = missingN + 1 end
    mailN = mailN + min(mail, max(0, need[id] - have))
    if #lines < Werk.LINES_MAX then
      lines[#lines + 1] = { id = id, name = itemName(id) or ("#" .. id), need = need[id], have = have, mail = mail, missing = missing,
        bank = (withBank and withBank > have) and (withBank - have) or 0, bought = Werk.session[id] or 0, orders = forOrders[id] }
    end
  end
  -- missing lines first (the dock buys top down), then the ones only on the way, then the covered ones
  table.sort(lines, function(a, b)
    local ka = a.missing > 0 and 0 or (a.mail > 0 and 1 or 2)
    local kb = b.missing > 0 and 0 or (b.mail > 0 and 1 or 2)
    if ka ~= kb then return ka < kb end
    return a.id < b.id
  end)
  return { orders = #orders, lines = lines, missing = missingN, mail = mailN, unknown = unknown }
end

-- recipes of open trainer steps (CraftTodo leaves them out of "Zum Berufslehrer": no duplicate for the same recipe)
function Werk.trainerRecipes()
  local out = {}
  for _, o in ipairs(Werk.orders()) do
    for _, s in ipairs(o.w.steps) do
      if s.kind == "trainer" and not s.done then out[s.recipe] = true end
    end
  end
  return out
end

-- Trackers -------------------------------------------------------------------------------------------------------------------------

-- Plans.copy hook: own text in the current language, flags c.shop (old readers keep working) and c.werk, station and next step
function Werk.decorate(p, c)
  local w = type(p.werk) == "table" and p.werk or nil
  if not w then return end
  c.shop, c.werk = true, true
  c.text = Werk.titleText(w) or c.text
  c.recipeID, c.profID, c.goal = w.recipe, w.prof, w.goal
  if p.done then return end
  local st = Werk.cachedStatus(p.id)
  if st then
    c.station, c.next = st.station, st.next
    local doneN, total = 0, #st.lines
    for _, li in ipairs(st.lines) do if li.missing <= 0 and li.mail <= 0 then doneN = doneN + 1 end end
    c.ready = st.station == 3
    c.progress = c.ready and T.ready or string.format("%d/%d", doneN, total)
  end
end

-- material lines like Einkauf.objectiveLines (open first, at most `max`) -> { lines = { { id, name, have, need, done, text } }, more }
function Werk.objectiveLines(id, maxN)
  local st = Werk.status(id)
  if not st then return { lines = {}, more = 0 } end
  maxN = posInt(maxN) or 5
  local open, done = {}, {}
  for _, li in ipairs(st.lines) do
    local have = li.need - li.missing
    local row = { id = li.id, name = li.name, have = have, need = li.need, done = li.missing <= 0, mail = li.mail,
      text = string.format("%s %d/%d", li.name, have, li.need) }
    if row.done then done[#done + 1] = row else open[#open + 1] = row end
  end
  local all = {}
  for _, r in ipairs(open) do all[#all + 1] = r end
  for _, r in ipairs(done) do all[#all + 1] = r end
  local out = {}
  for i = 1, min(maxN, #all) do out[i] = all[i] end
  return { lines = out, more = #all - #out }
end

function Werk.tipLines(id)
  local st = Werk.status(id)
  local out = {}
  for _, li in ipairs(st and st.lines or {}) do
    out[#out + 1] = { text = string.format("%s  %d/%d", li.name, min(li.need - li.missing, 99999), li.need), done = li.missing <= 0 }
  end
  return out
end

-- Counting progress ----------------------------------------------------------------------------------------------------------------

-- bag growth of output items -> made of the open craft steps (step order, orders by creation); a step takes at most its target
local function countOutputs(orders)
  local byItem = {}
  for _, o in ipairs(orders) do
    if type(o.p.werk) == "table" then
      for _, s in ipairs(o.w.steps) do
        if s.kind == "craft" and s.out and not s.done then
          local l = byItem[s.out]
          if not l then l = {} byItem[s.out] = l end
          l[#l + 1] = { s = s, w = o.w }
        end
      end
    end
  end
  for id, list in pairs(byItem) do
    local cur = bags(id)
    if cur then
      local base
      for _, e in ipairs(list) do
        local l = nonNeg(e.s.last)
        if l and (not base or l > base) then base = l end
      end
      local delta = base and max(0, cur - base) or 0
      for i, e in ipairs(list) do
        if delta <= 0 then break end
        local s = e.s
        local target = (posInt(s.n) or 1) * (posInt(s.q) or 1)
        local room = max(0, target - (nonNeg(s.made) or 0))
        local take = (i == #list or s.to) and delta or min(delta, room)
        s.made = (nonNeg(s.made) or 0) + take
        delta = delta - take
        -- the main step of a single order keeps w.made like p.shop did
        if e.w.recipe == s.recipe and not s.pre then e.w.made = s.made end
      end
      for _, e in ipairs(list) do e.s.last = cur end
    end
  end
end

-- a successful cast of a recipe spell without an output item (enchantment) -> one craft of the first open such step
function Werk.onCast(spellID)
  spellID = posInt(spellID)
  if not spellID then return false end
  for _, o in ipairs(Werk.orders()) do
    if type(o.p.werk) == "table" then
      for _, s in ipairs(o.w.steps) do
        if s.kind == "craft" and not s.out and not s.done and s.recipe == spellID then
          s.made = (nonNeg(s.made) or 0) + 1
          Werk.gen = (Werk.gen or 0) + 1
          return true
        end
      end
    end
  end
  return false
end

-- Check (batched after bag changes): count, mark steps done, move cur, complete finished orders -> open orders
function Werk.check()
  local Pl = P()
  if not (Pl and Pl.rawList and Store and Store.ready and Store.ready()) then return 0 end
  mailArrivals()
  local orders = Werk.orders()
  countOutputs(orders)
  Werk.gen = (Werk.gen or 0) + 1
  local finished, n = {}, 0
  for _, o in ipairs(orders) do
    if type(o.p.werk) == "table" then
      n = n + 1
      local c = Werk.compute(o.w)
      local t = now()
      for k, row in ipairs(c.rows) do
        local s = row.step
        -- persistent marks: learned recipes, reached stages, all crafts of a step (precursors stay live: what is still needed)
        if row.done and not s.done and (s.kind == "trainer" or not s.pre) then s.done = t end
        if s.pre and not s.done and craftsDone(s) >= (posInt(s.n) or 1) then s.done = t end
        c.rows[k] = row
      end
      o.w.cur = c.cur or #o.w.steps
      if c.done then finished[#finished + 1] = o.id end
    end
  end
  for _, id in ipairs(finished) do Pl.finishPlan(id, "craft") end
  if n > 0 and Pl.changed then Pl.changed() end
  return n
end

-- Migration ------------------------------------------------------------------------------------------------------------------------

-- once per character: open p.shop to-dos get p.werk; p.shop stays (marked migrated) -> number migrated, or nil when already done
function Werk.migrate()
  local c = Store and Store.char and Store.char()
  if type(c) ~= "table" then return nil end
  if c.werkMigrated == 1 then return nil end
  local list = type(c.vorhaben) == "table" and c.vorhaben or {}
  local n = 0
  for _, p in ipairs(list) do
    if type(p) == "table" and not p.done and type(p.shop) == "table" and type(p.werk) ~= "table" then
      local w = Werk.fromShop(p.shop)
      if w then
        w.created = num(p.created) or w.created
        p.werk = w
        p.shop.migrated = true
        n = n + 1
      end
    end
  end
  c.werkMigrated = 1
  Werk.gen = (Werk.gen or 0) + 1
  return n
end

-- the old window changed p.shop of an order (count, resolve): the order follows. The progress comes from the previous p.werk
-- (p.shop of a migrated or pure work order is frozen or freshly built with made = 0): per recipe made / last / done of each step,
-- made / last of the order.
function Werk.syncFromShop(p)
  if type(p) ~= "table" or type(p.shop) ~= "table" or type(p.werk) ~= "table" then return false end
  local w = Werk.fromShop(p.shop)
  if not w then return false end
  local old = p.werk
  local byRecipe = {}
  for _, s in ipairs(type(old.steps) == "table" and old.steps or {}) do
    if type(s) == "table" and s.kind == "craft" and posInt(s.recipe) and not byRecipe[s.recipe] then byRecipe[s.recipe] = s end
  end
  for _, s in ipairs(w.steps) do
    local o = s.kind == "craft" and byRecipe[s.recipe] or nil
    if o then
      s.made, s.last = nonNeg(o.made) or 0, nonNeg(o.last) or s.last
      if posInt(o.done) and craftsDone(s) >= (posInt(s.n) or 1) then s.done = o.done end
    end
  end
  w.made, w.last = nonNeg(old.made) or w.made, nonNeg(old.last) or w.last
  w.created = old.created or w.created
  Werk.gen = Werk.gen + 1
  p.werk = w
  p.shop.migrated = true
  return true
end

-- Collector ------------------------------------------------------------------------------------------------------------------------

local Collector = {
  -- no "requires": without counts or mail functions the numbers are just unknown, the collector stays on
  events = { "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED",
    "MAIL_INBOX_UPDATE", "MAIL_CLOSED", "AUCTION_HOUSE_CLOSED", "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE" },
  unitEvents = { UNIT_SPELLCAST_SUCCEEDED = { "player" } },
}
Werk.collector = Collector

function Collector:init()
  self.pending = false
  if Store and Store.ready and Store.ready() then
    Werk.migrate()
    Werk.pruneMail()
  end
end

local function schedule(self)
  local Ek = E()
  if Ek and Ek.invalidate then Ek.invalidate() end
  if self.pending then return end
  self.pending = true
  if not Core.after(self, Werk.CHANGE_DELAY, function(s)
    s.pending = false
    Werk.check()
  end) then
    self.pending = false
  end
end

local handlers = {}
handlers.PLAYER_ENTERING_WORLD = function(self)
  Werk.migrate()
  Werk.pruneMail()
  schedule(self)
end
handlers.BAG_UPDATE_DELAYED = schedule
handlers.SKILL_LINES_CHANGED = schedule
handlers.LEARNED_SPELL_IN_SKILL_LINE = schedule
handlers.COMMODITY_PURCHASE_SUCCEEDED = function(self)
  if purchaseDone(true) then schedule(self) end
end
handlers.COMMODITY_PURCHASE_FAILED = function() purchaseDone(false) end
handlers.AUCTION_HOUSE_CLOSED = function() end -- a pending purchase still settles with its result event (PURCHASE_WAIT)
handlers.MAIL_INBOX_UPDATE = function(self)
  if Werk.readInbox() then schedule(self) end
end
handlers.MAIL_CLOSED = schedule
handlers.UNIT_SPELLCAST_SUCCEEDED = function(self, _, _, spellID)
  if Werk.onCast(spellID) then schedule(self) end
end

function Collector:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

-- Diagnostics (/chronik diag)
function Werk.diagLine()
  local n, route = 0, 0
  for _, o in ipairs(Werk.orders()) do
    n = n + 1
    if o.w.goal then route = route + 1 end
  end
  return string.format("orders %d (routes %d), on the way by mail %d", n, route, #Werk.mailList())
end

ns.RegisterCollector("Werkauftrag", Collector)
