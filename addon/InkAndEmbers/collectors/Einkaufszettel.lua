-- Collector 'Einkaufszettel' (WoW Forever only; Retail has no recipe cache): the shopping list to-do. A recipe plus a count becomes a
-- free to-do "Einkaufszettel: 20× Kupferbarren" (stored in chars[guid].vorhaben like every to-do, additive field p.shop) with one
-- material line per reagent. The lines are counted live in the bags (C_Item.GetItemCount, bank only as a hint) and tick themselves;
-- when all are there the list is "ready" and the journal window (journal/Einkaufszettel.lua) offers "Jetzt herstellen".
-- Optionally an intermediate product (a material that is the output of a learned recipe in the cache) is resolved into its own
-- materials (state at the time the list is made or changed).
-- Data: the recipe cache of collectors/RecipeScan.lua (ns.RecipeCache, chars[guid].recipeCache[professionID] = { name, skill, max, at,
--   recipes = { [recipeID] = { n = name, l = learned, d = relativeDifficulty 0..3, u = skill ups, o = output itemID, q = output count,
--   r = { { itemID, qty }, ... } } } }); read only here, never written.
-- p.shop = { prof, recipe, count (crafts), qty (output per craft), out (itemID), name, resolve (bool), made (output items seen
--   arriving), last (bag count of the output at the last check), lines = { { id, need, n = name, sub = true | nil, craft = crafts,
--   recipe = recipeID of an intermediate } } }.
-- The list completes itself (Plans.finishPlan) once as many output items arrived as were planned; by hand it can always be ticked.
-- Counting is batched (BAG_UPDATE_DELAYED, Einkauf.CHANGE_DELAY); nothing is bought, clicked or crafted without a click of the player.
local _, ns = ...
local Core, Store = ns.Core, ns.Store

local floor, min, max, ceil = math.floor, math.min, math.max, math.ceil

local Einkauf = {}
ns.Einkauf = Einkauf

Einkauf.COUNT_MAX = 999     -- crafts per list
Einkauf.LINES_MAX = 24      -- material lines per list
Einkauf.RESOLVE_DEPTH = 3   -- levels of intermediate products
Einkauf.CHANGE_DELAY = 0.4  -- seconds: bag changes are counted in one batch

local T = ns.Locale.ns("col.Einkauf", {
  title = "Einkaufszettel: %s× %s",
  ready = "bereit",
  errOff = "Der Einkaufszettel gibt es nur in WoW Forever.",
  errCount = "Bitte eine Anzahl von 1 bis 999 wählen.",
  errRecipe = "Dieses Rezept ist nicht im Rezeptbuch gespeichert. Öffnet das Berufsfenster einmal.",
  errNotReady = "Es fehlen noch Materialien.",
  errNoApi = "Das Herstellen ist gerade nicht möglich.",
  errWindow = "Öffnet zuerst das Berufsfenster: %s.",
  errBlocked = "Das Spiel sperrt das Herstellen von hier. Stellt es im Berufsfenster her: %s.",
  errCombat = "Im Kampf geht das nicht.",
  errFull = "Die To-do-Liste ist voll.",
  moreLines = "… %s weitere",
  errNotReadyChar = "Der Charakter ist noch nicht bereit.",
})
Einkauf.TEXT = T

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

local function str(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

local function clean(s, n)
  s = str(s)
  if not s then return nil end
  local S = ns.Sanitize
  s = S and S.display and S.display(s, n or 80) or s
  return str(s)
end

function Einkauf.active()
  local H = ns.Journal and ns.Journal.Handwerk
  if H and type(H.active) == "function" then return H.active() == true end
  return true
end

-- Recipe cache --------------------------------------------------------------------------------------------------------------------

-- The cache table of a character (default: the logged-in one): professionID -> { name, skill, max, at, recipes }; nil without one.
function Einkauf.cache(char)
  if char == nil then char = Store and Store.char and Store.char() or nil end
  local c = type(char) == "table" and char.recipeCache or nil
  if type(c) ~= "table" or isSecret(c) then return nil end
  return c
end

-- reagents of a cached recipe as { { id, qty }, ... } (invalid entries dropped)
function Einkauf.reagents(rec)
  local out = {}
  if type(rec) ~= "table" or type(rec.r) ~= "table" then return out end
  for _, e in ipairs(rec.r) do
    local id, qty
    if type(e) == "table" then id, qty = posInt(e[1] or e.id), posInt(e[2] or e.qty) end
    if id and qty then out[#out + 1] = { id = id, qty = qty } end
  end
  return out
end

-- cached recipe -> profID, rec (profID may be nil: then every profession is searched)
function Einkauf.recipe(profID, recipeID, char)
  local c = Einkauf.cache(char)
  recipeID = posInt(recipeID)
  if not (c and recipeID) then return nil end
  profID = posInt(profID)
  if profID then
    local p = c[profID]
    local rec = type(p) == "table" and type(p.recipes) == "table" and p.recipes[recipeID] or nil
    if type(rec) == "table" then return profID, rec end
    return nil
  end
  local keys = {}
  for k in pairs(c) do if type(k) == "number" then keys[#keys + 1] = k end end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local p = c[k]
    local rec = type(p) == "table" and type(p.recipes) == "table" and p.recipes[recipeID] or nil
    if type(rec) == "table" then return k, rec end
  end
  return nil
end

-- Learned recipe that makes itemID (intermediate product): smallest recipeID wins; recipes of the same profession first.
function Einkauf.producer(itemID, profID, char)
  local c = Einkauf.cache(char)
  itemID = posInt(itemID)
  if not (c and itemID) then return nil end
  local bestP, bestId, bestRec
  local function consider(pid, p)
    if type(p) ~= "table" or type(p.recipes) ~= "table" then return end
    for rid, rec in pairs(p.recipes) do
      if type(rid) == "number" and type(rec) == "table" and rec.l == true and posInt(rec.o) == itemID then
        local better = bestId == nil
        if not better then
          local sameNow, sameBest = pid == profID, bestP == profID
          better = (sameNow and not sameBest) or (sameNow == sameBest and (rid < bestId or (rid == bestId and pid < bestP)))
        end
        if better then bestP, bestId, bestRec = pid, rid, rec end
      end
    end
  end
  for pid, p in pairs(c) do
    if type(pid) == "number" then consider(pid, p) end
  end
  if not bestId then return nil end
  return bestP, bestId, bestRec
end

-- Counting ------------------------------------------------------------------------------------------------------------------------

local memo = {}
local memoAt = nil
Einkauf.gen = 0
Einkauf.MEMO_TTL = 1.0 -- seconds: counts are also re-read on their own, should a bag event ever be missed

function Einkauf.invalidate()
  memo = {}
  memoAt = nil
  Einkauf.gen = Einkauf.gen + 1
end

local function clock()
  if type(GetTime) == "function" then
    local ok, t = pcall(GetTime)
    if ok and num(t) then return t end
  end
  return nil
end

-- items in the bags (bank = false) or bags + bank (bank = true); nil if the client cannot say
function Einkauf.count(itemID, bank)
  itemID = posInt(itemID)
  if not itemID then return nil end
  local key = bank and (itemID .. "b") or itemID
  local now = clock()
  if now and (memoAt == nil or now - memoAt > Einkauf.MEMO_TTL or now < memoAt) then
    memo = {}
    memoAt = now
  end
  local v = memo[key]
  if v ~= nil then return v or nil end
  local fn = C_Item and C_Item.GetItemCount
  if type(fn) ~= "function" then return nil end
  local ok, n
  if bank then ok, n = pcall(fn, itemID, true) else ok, n = pcall(fn, itemID, false) end
  n = ok and num(n) or nil
  if n and n < 0 then n = 0 end
  memo[key] = n and floor(n) or false
  return n and floor(n) or nil
end

local function itemName(id, fallback)
  local fn = C_Item and C_Item.GetItemNameByID
  if type(fn) == "function" then
    local ok, n = pcall(fn, id)
    if ok then
      n = clean(n)
      if n then return n end
    end
  end
  return clean(fallback)
end
Einkauf.itemName = itemName

-- Build ---------------------------------------------------------------------------------------------------------------------------

-- Material lines for `count` crafts of a cached recipe. resolve: intermediate products with a learned producer recipe become their
-- own lines (what is already in the bags is not made again) and the producer's materials are added as sub lines.
local function expand(lines, reagents, crafts, depth, resolve, profID, stack, bagLeft)
  for _, rg in ipairs(reagents) do
    local total = rg.qty * crafts
    local done = false
    if resolve and depth < Einkauf.RESOLVE_DEPTH then
      local pid, rid, prec = Einkauf.producer(rg.id, profID)
      if rid and not stack[rid] then
        local inBags = bagLeft[rg.id]
        if inBags == nil then inBags = Einkauf.count(rg.id, false) or 0 end
        local missing = max(0, total - inBags)
        bagLeft[rg.id] = max(0, inBags - total)
        if missing > 0 then
          local per = posInt(prec.q) or 1
          local sub = ceil(missing / per)
          local li = lines.byKey[(depth > 0 and "s" or "t") .. rg.id]
          if li then
            li.need = li.need + total
            li.craft = (li.craft or 0) + sub
          else
            li = { id = rg.id, need = total, craft = sub, recipe = rid, sub = depth > 0 or nil }
            lines.byKey[(depth > 0 and "s" or "t") .. rg.id] = li
            lines[#lines + 1] = li
          end
          stack[rid] = true
          expand(lines, Einkauf.reagents(prec), sub, depth + 1, resolve, pid or profID, stack, bagLeft)
          stack[rid] = nil
          done = true
        end
      end
    end
    if not done then
      local key = (depth > 0 and "s" or "t") .. rg.id
      local li = lines.byKey[key]
      if li then
        li.need = li.need + total
      else
        li = { id = rg.id, need = total, sub = depth > 0 or nil }
        lines.byKey[key] = li
        lines[#lines + 1] = li
      end
    end
  end
end

-- shop data for `count` crafts of recipeID, or nil, reason ("aus" | "anzahl" | "rezept" | "leer")
function Einkauf.build(profID, recipeID, count, resolve)
  if not Einkauf.active() then return nil, "aus" end
  count = posInt(count)
  if not count or count > Einkauf.COUNT_MAX then return nil, "anzahl" end
  local pid, rec = Einkauf.recipe(profID, recipeID)
  if not pid then return nil, "rezept" end
  local reagents = Einkauf.reagents(rec)
  if #reagents == 0 then return nil, "leer" end
  local lines = { byKey = {} }
  expand(lines, reagents, count, 0, resolve == true, pid, { [posInt(recipeID)] = true }, {})
  lines.byKey = nil
  -- top-level lines first, then the sub lines of the intermediate products
  local top, sub = {}, {}
  for _, li in ipairs(lines) do
    if li.sub then sub[#sub + 1] = li else top[#top + 1] = li end
  end
  local out = {}
  for _, li in ipairs(top) do out[#out + 1] = li end
  for _, li in ipairs(sub) do out[#out + 1] = li end
  while #out > Einkauf.LINES_MAX do out[#out] = nil end
  for _, li in ipairs(out) do
    li.n = li.n or itemName(li.id)
  end
  local outId = posInt(rec.o)
  return {
    prof = pid, recipe = posInt(recipeID), count = count, qty = posInt(rec.q) or 1, out = outId,
    name = clean(rec.n, 60) or ("#" .. tostring(recipeID)), resolve = resolve == true and true or false,
    made = 0, last = outId and Einkauf.count(outId, false) or nil, lines = out,
  }
end

function Einkauf.titleText(shop)
  if type(shop) ~= "table" then return nil end
  return T("title", tostring(posInt(shop.count) or 1), clean(shop.name, 60) or "?")
end

-- an open list of this recipe -> plan id
function Einkauf.find(recipeID)
  local P = ns.Plans
  local list = P and P.rawList and P.rawList()
  recipeID = posInt(recipeID)
  if not (list and recipeID) then return nil end
  for _, p in ipairs(list) do
    if type(p) == "table" and not p.done and type(p.shop) == "table" and posInt(p.shop.recipe) == recipeID then return p.id end
  end
  return nil
end

-- Make (or update, when an open list of this recipe exists) a shopping list -> id, "new" | "update" | nil, reason
function Einkauf.add(profID, recipeID, count, resolve)
  local P = ns.Plans
  if not (P and Store and Store.ready and Store.ready()) then return nil, "nicht-bereit" end
  local shop, err = Einkauf.build(profID, recipeID, count, resolve)
  if not shop then return nil, err end
  local text = Einkauf.titleText(shop)
  local old = Einkauf.find(recipeID)
  if old then
    local p = P.raw(old)
    p.shop = shop
    local clean2 = P.cleanText(text)
    if clean2 then p.text = clean2 end
    P.changed()
    return old, "update"
  end
  local id, e = P.add({ kind = "free", text = text, shop = shop })
  if not id then return nil, e end
  return id, "new"
end

-- Change count / resolve of an existing list (lines are rebuilt from the cache; made/last stay) -> true | nil, reason
function Einkauf.rebuild(id, opts)
  local P = ns.Plans
  local p = P and P.raw and P.raw(id)
  if not (p and type(p.shop) == "table") then return nil, "kein-zettel" end
  opts = type(opts) == "table" and opts or {}
  local s = p.shop
  local resolve = opts.resolve
  if resolve == nil then resolve = s.resolve == true end
  local shop, err = Einkauf.build(s.prof, s.recipe, opts.count or s.count, resolve)
  if not shop then return nil, err end
  shop.made, shop.last = num(s.made) or 0, num(s.last) or shop.last
  p.shop = shop
  local text = P.cleanText(Einkauf.titleText(shop))
  if text then p.text = text end
  P.changed()
  return true
end

-- Status ----------------------------------------------------------------------------------------------------------------------------

-- Live status of a shop table: { lines = { { id, name, need, have, bank, done, sub, craft } }, doneN, total, ready, made, target }
-- ready = all top-level lines (not the sub lines of an intermediate that is already complete) are covered.
function Einkauf.status(shop)
  if type(shop) ~= "table" or type(shop.lines) ~= "table" then return nil end
  local lines, doneN, ready = {}, 0, true
  for _, li in ipairs(shop.lines) do
    if type(li) == "table" and posInt(li.id) and posInt(li.need) then
      local have = Einkauf.count(li.id, false)
      local withBank = Einkauf.count(li.id, true)
      local row = { id = li.id, name = itemName(li.id, li.n) or ("#" .. li.id), need = li.need, have = have or 0,
        bank = (have and withBank and withBank > have) and (withBank - have) or 0, sub = li.sub == true, craft = li.craft,
        recipe = li.recipe, known = have ~= nil }
      row.done = have ~= nil and have >= li.need
      if row.done then doneN = doneN + 1 end
      if not row.sub and not row.done then ready = false end
      lines[#lines + 1] = row
    end
  end
  local target = (posInt(shop.count) or 1) * (posInt(shop.qty) or 1)
  return { lines = lines, doneN = doneN, total = #lines, ready = ready and #lines > 0, made = floor(num(shop.made) or 0), target = target }
end

-- Plans.copy hook: own text in the current language, progress "3/5" or "bereit", flag c.shop
function Einkauf.decorate(p, c)
  local s = p.shop
  if type(s) ~= "table" then return end
  c.shop = true
  c.text = Einkauf.titleText(s) or c.text
  c.recipeID, c.profID = s.recipe, s.prof
  local st = Einkauf.status(s)
  if st then
    c.progress = st.ready and T.ready or string.format("%d/%d", st.doneN, st.total)
    c.ready = st.ready
  end
end

-- Tooltip lines of a list (display-ready): "Kupfererz 4/20" per material
function Einkauf.tipLines(id)
  local P = ns.Plans
  local p = P and P.raw and P.raw(id)
  if not (p and type(p.shop) == "table") then return {} end
  local st = Einkauf.status(p.shop)
  local out = {}
  if st then
    for _, r in ipairs(st.lines) do
      out[#out + 1] = { text = string.format("%s  %d/%d", r.name, min(r.have, 99999), r.need), done = r.done, sub = r.sub }
    end
  end
  return out
end

-- Material lines for the trackers (to-do note, dock, quest tracker, to-do page): like quest objectives, open lines first, then the done
-- ones; at most `max` shown. -> { lines = { { id, name, have, need, done, text = "Kupfererz 4/20" } }, more = number of hidden lines }
Einkauf.SUB_MAX = 5
function Einkauf.objectiveLines(id, max)
  local P = ns.Plans
  local p = P and P.raw and P.raw(id)
  if not (p and type(p.shop) == "table") then return { lines = {}, more = 0 } end
  local st = Einkauf.status(p.shop)
  if not st then return { lines = {}, more = 0 } end
  max = posInt(max) or Einkauf.SUB_MAX
  local open, done = {}, {}
  for _, r in ipairs(st.lines) do
    local shownHave = min(r.have, r.need)
    local row = { id = r.id, name = r.name, have = shownHave, need = r.need, done = r.done,
      text = string.format("%s %d/%d", r.name, shownHave, r.need) }
    if r.done then done[#done + 1] = row else open[#open + 1] = row end
  end
  local all = {}
  for _, r in ipairs(open) do all[#all + 1] = r end
  for _, r in ipairs(done) do all[#all + 1] = r end
  local out = {}
  for i = 1, min(max, #all) do out[i] = all[i] end
  return { lines = out, more = #all - #out }
end

-- Craft ("Jetzt herstellen"): only from a click, only when ready and the profession window is open -> true | nil, reason, extra
-- Fallback: if the game blocks CraftRecipe (the call fails, or ADDON_ACTION_BLOCKED/FORBIDDEN names InkAndEmbers while it runs, or
-- Core.actionLog already holds such an entry for CraftRecipe), Einkauf.craftBlocked is set for the session. From then on the button
-- crafts nothing: it only opens the profession window (C_TradeSkillUI.OpenTradeSkill, if the client has it) and says so -> nil, "gesperrt", name.
Einkauf.craftBlocked = false

local function actionTotal()
  local log = Core and Core.actionLog
  return log and num(log.total) or 0
end

local function loggedBlock()
  local log = Core and Core.actionLog
  if type(log) ~= "table" or type(log.entries) ~= "table" then return false end
  for _, en in ipairs(log.entries) do
    if type(en) == "table" and type(en.func) == "string" and string.find(en.func, "CraftRecipe", 1, true) then return true end
  end
  return false
end

local function profName(id)
  local pc = Einkauf.cache()
  return pc and pc[id] and clean(pc[id].name, 40) or tostring(id)
end

-- only the profession window opens (pcall: a missing or failing opener is no error) -> nil, "gesperrt", profession name
local function blockedFallback(api, prof)
  if type(api) == "table" and type(api.OpenTradeSkill) == "function" then pcall(api.OpenTradeSkill, prof) end
  return nil, "gesperrt", profName(prof)
end

function Einkauf.craft(id)
  local P = ns.Plans
  local p = P and P.raw and P.raw(id)
  if not (p and type(p.shop) == "table") then return nil, "kein-zettel" end
  local s = p.shop
  local st = Einkauf.status(s)
  if not (st and st.ready) then return nil, "nicht-komplett" end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return nil, "kampf" end
  local api = C_TradeSkillUI
  if type(api) ~= "table" or type(api.CraftRecipe) ~= "function" then return nil, "keine-api" end
  if Einkauf.craftBlocked or loggedBlock() then
    Einkauf.craftBlocked = true
    return blockedFallback(api, posInt(s.prof))
  end
  local okInfo, info = pcall(function() return type(api.GetBaseProfessionInfo) == "function" and api.GetBaseProfessionInfo() or nil end)
  local open = okInfo and type(info) == "table" and posInt(info.professionID) or nil
  if open ~= posInt(s.prof) then
    return nil, "fenster", profName(s.prof)
  end
  local before = actionTotal()
  local ok = pcall(api.CraftRecipe, posInt(s.recipe), posInt(s.count) or 1)
  if not ok or actionTotal() > before then
    Einkauf.craftBlocked = true
    return blockedFallback(api, posInt(s.prof))
  end
  return true
end

function Einkauf.reasonText(reason, extra)
  if reason == "aus" then return T.errOff end
  if reason == "anzahl" then return T.errCount end
  if reason == "rezept" or reason == "leer" then return T.errRecipe end
  if reason == "nicht-komplett" then return T.errNotReady end
  if reason == "keine-api" then return T.errNoApi end
  if reason == "fenster" then return T("errWindow", extra or "?") end
  if reason == "gesperrt" then return T("errBlocked", extra or "?") end
  if reason == "kampf" then return T.errCombat end
  if reason == "voll" then return T.errFull end
  if reason == "nicht-bereit" then return T.errNotReadyChar end
  return nil
end

-- Check (batched after bag changes): count arriving output items, complete finished lists, redraw -> number of open lists
function Einkauf.check()
  local P = ns.Plans
  local list = P and P.rawList and P.rawList()
  if not list then return 0 end
  local n, finished = 0, {}
  for _, p in ipairs(list) do
    if type(p) == "table" and not p.done and type(p.shop) == "table" then
      n = n + 1
      local s = p.shop
      local out = posInt(s.out)
      if out then
        local cur = Einkauf.count(out, false)
        if cur then
          local last = num(s.last)
          if last and cur > last then s.made = (num(s.made) or 0) + (cur - last) end
          s.last = cur
        end
        if (num(s.made) or 0) >= (posInt(s.count) or 1) * (posInt(s.qty) or 1) then finished[#finished + 1] = p.id end
      end
    end
  end
  for _, id in ipairs(finished) do P.finishPlan(id, "craft") end
  if n > 0 and P.changed then P.changed() end
  return n
end

local Collector = {
  -- no "requires": without C_Item.GetItemCount the counts are simply unknown (Einkauf.count -> nil), the collector stays on
  events = { "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" },
}
Einkauf.collector = Collector

function Collector:init()
  self.pending = false
end

function Collector:onEvent()
  Einkauf.invalidate()
  if self.pending then return end
  self.pending = true
  if not Core.after(self, Einkauf.CHANGE_DELAY, function(s)
    s.pending = false
    Einkauf.check()
  end) then
    self.pending = false
  end
end

-- Diagnostics (/chronik diag)
function Einkauf.diagLine()
  local c = Einkauf.cache()
  local n = 0
  for _, p in pairs(c or {}) do
    if type(p) == "table" and type(p.recipes) == "table" then for _ in pairs(p.recipes) do n = n + 1 end end
  end
  local open = 0
  local list = ns.Plans and ns.Plans.rawList and ns.Plans.rawList() or {}
  for _, p in ipairs(list) do
    if type(p) == "table" and not p.done and type(p.shop) == "table" then open = open + 1 end
  end
  return string.format("%s, cached recipes %d, open lists %d", Einkauf.active() and "on" or "off (Retail)", n, open)
end

ns.RegisterCollector("Einkaufszettel", Collector)
