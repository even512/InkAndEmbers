-- Vermächtnis (Legacy system of WoW Forever, Chronik sub-bookmark "Vermächtnis", pages/ChronikVermaechtnis.lua). Read only, account-wide.
-- There is no C_Legacy API: the system is built from existing parts (measured in Forever build 70938, journal/LegacyProbe.lua, specs
-- ...-recherche-legacy.md):
--   points       reward track (major faction 2802): renownLevel = earned Legacy points; maximum from
--                C_Traits.GetMaxAvailableTraitCurrency(4225, false) (65). Fallback when the track is unreadable: the tree currency
--                (quantity + spent of currency 4225, C_Traits.GetTreeCurrencyInfo).
--   challenges   achievement categories 15577-15585 (one per class, three achievements each: Novice / Experienced / Master), done /
--                done by this character / date from GetAchievementInfo, points per challenge from C_Traits.GetTraitCurrencyForAchievement
--   trees        C_Traits trees 1187 (Professions), 1188 (Adventure), 1189 (Progression): nodes with name (entry -> definition ->
--                override name or spell name), current / maximum rank
--   rewards      C_MajorFactions.GetRenownRewardsForLevel(2802, 15 / 25 / 40 / 55): item, name, isCollected
-- Every API access runs in pcall, every return value is checked with issecretvalue (secret values are never compared or stored), nothing
-- is read in combat (then only the cache is returned), nothing is written into the game (no reset / commit of a tree). Foreign text (item,
-- spell, achievement names) only through Sanitize.plain. The result is cached in the account SV (EveNChronicleDB.legacy) so combat,
-- a failed read and the next login show the last good state.
--   data = { at, points, pointsMax, level, levelMax, readable = bool,
--            classes = { { file, cat, name, tiers = { { id, name, done, mine, pts, d, m, y, cur, tot } } } },
--            groups = { { key, cat, name, items = { same as a tier } } },  -- further challenge groups: achievements with Legacy points outside the class categories, by top category
--            trees = { { key, id, readable, nodes = { { name | nil, spell | nil, entry | nil, rank, max } } } },
--            rewards = { { level, itemID | nil, name | nil, collected = true | false | nil } } }
--   data, status = Vermaechtnis.get(force)   status: "ok" | "stale" (cache, reason in 3rd value) | "unreadable" | "combat" | "off"
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local V = {}
Journal.Vermaechtnis = V

local floor, min = math.floor, math.min
local format = string.format

V.CURRENCY_ID = 4225
V.FACTION_ID = 2802
V.REWARD_LEVELS = { 15, 25, 40, 55 }
V.TREES = { { key = "professions", id = 1187 }, { key = "adventure", id = 1188 }, { key = "progression", id = 1189 } }
V.CLASSES = {
  { file = "DRUID", cat = 15577 }, { file = "HUNTER", cat = 15578 }, { file = "MAGE", cat = 15579 }, { file = "PALADIN", cat = 15580 },
  { file = "PRIEST", cat = 15581 }, { file = "ROGUE", cat = 15582 }, { file = "SHAMAN", cat = 15583 }, { file = "WARLOCK", cat = 15584 },
  { file = "WARRIOR", cat = 15585 },
}
V.TIERS = 3             -- Novice / Experienced / Master
V.GROUPS_MAX = 8        -- groups besides the classes
V.ITEMS_MAX = 40        -- achievements per group
V.CATS_SCAN_MAX = 600   -- categories looked at
V.CAT_ITEMS_MAX = 400   -- achievements read per category
V.FOUND_TTL = 86400     -- seconds the list of categories with Legacy challenges stays valid (found once, then only its categories are read)
V.SCAN_PER_TICK = 150   -- achievements looked at per timer tick of the discovery scan
V.SCAN_TICK = 0.05      -- seconds between two ticks
V.SCAN_MAX = 6000       -- achievements looked at in total
V.SCAN_RETRY = 300      -- seconds before a scan that found nothing readable is tried again
V.CRITERIA_MAX = 12     -- criteria counted for a progress
V.NODES_MAX = 12        -- nodes read per tree
V.NAME_MAX = 60         -- bytes of a foreign name
V.TTL = 30              -- seconds a read stays fresh (reopening the page does not read again)
V.POINTS_CAP = 1000     -- plausibility limit of every number
V.ALLOW_RETAIL = false  -- tests / diagnosis: read in the Retail client too

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return ok and not isSecret(v) and v == true
end

local function now()
  if type(time) ~= "function" then return 0 end
  local ok, t = pcall(time)
  if not ok or isSecret(t) or type(t) ~= "number" then return 0 end
  return t
end

-- Retail has no Legacy system: the bookmark stays out there
function V.active()
  if V.ALLOW_RETAIL then return true end
  local ms = Journal.MapSpace
  return not (ms ~= nil and type(ms.retailClient) == "function" and ms.retailClient() == true)
end

-- ---------- safe reading ----------

local function num(v, lo, hi)
  if isSecret(v) or type(v) ~= "number" or v ~= v then return nil end
  if v < (lo or 0) or v > (hi or V.POINTS_CAP) then return nil end
  return floor(v)
end

local function bool(v)
  if isSecret(v) or type(v) ~= "boolean" then return nil end
  return v
end

local function text(v, max)
  if isSecret(v) or type(v) ~= "string" then return nil end
  local S = ns.Sanitize
  if S and S.plain then return S.plain(v, max or V.NAME_MAX) end
  local s = string.gsub(string.gsub(v, "|", ""), "%c", " ")
  return s ~= "" and string.sub(s, 1, max or V.NAME_MAX) or nil
end

-- field of a table (guarded)
local function field(t, k)
  if isSecret(t) or type(t) ~= "table" then return nil end
  local ok, v = pcall(function() return t[k] end)
  if not ok or isSecret(v) then return nil end
  return v
end

local function api(owner, name)
  local t = owner == "" and _G or rawget(_G, owner)
  if type(t) ~= "table" or isSecret(t) then return nil end
  local ok, f = pcall(function() return t[name] end)
  if ok and type(f) == "function" then return f end
  return nil
end

-- guarded call: results table (r[1] first result) or nil when missing / failed
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local r = { pcall(f, ...) }
  if not r[1] then return nil end
  table.remove(r, 1)
  return r
end

local function listOf(v, max)
  if isSecret(v) or type(v) ~= "table" then return {} end
  local out = {}
  local ok = pcall(function()
    for i = 1, max do
      local x = v[i]
      if x == nil then break end
      out[#out + 1] = x
    end
  end)
  return ok and out or {}
end

-- ---------- reading the parts ----------

local function readRenown()
  local r = call(api("C_MajorFactions", "GetMajorFactionData"), V.FACTION_ID)
  local d = r and r[1]
  local level, max = num(field(d, "renownLevel")), num(field(d, "maxLevel"))
  if not level then
    local c = call(api("C_MajorFactions", "GetCurrentRenownLevel"), V.FACTION_ID)
    level = c and num(c[1]) or nil
  end
  return level, max
end

local function readPointsMax()
  local r = call(api("C_Traits", "GetMaxAvailableTraitCurrency"), V.CURRENCY_ID, false)
  return r and num(r[1]) or nil
end

-- -> name | nil, spellID | nil, entryID | nil (the spell id feeds the original game tooltip in the view)
local function nodeName(configID, node)
  local entryID
  local active = field(node, "activeEntry")
  if type(active) == "table" then entryID = field(active, "entryID") end
  if entryID == nil then entryID = listOf(field(node, "entryIDs"), 1)[1] end
  if entryID == nil or isSecret(entryID) then return nil end
  entryID = num(entryID, 1, 2 ^ 31)
  local e = call(api("C_Traits", "GetEntryInfo"), configID, entryID)
  local defID = e and field(e[1], "definitionID")
  if defID == nil then return nil, nil, entryID end
  local d = call(api("C_Traits", "GetDefinitionInfo"), defID)
  local def = d and d[1]
  local spellID = num(field(def, "spellID"), 1, 2 ^ 31)
  local override = text(field(def, "overrideName"))
  if override then return override, spellID, entryID end
  if spellID ~= nil then
    local s = call(api("C_Spell", "GetSpellName"), spellID)
    return s and text(s[1]) or nil, spellID, entryID
  end
  return nil, nil, entryID
end

-- one tree -> { key, id, readable, nodes }, and the currency of the points (quantity once, spent summed up by the caller)
local function readTree(def)
  local out = { key = def.key, id = def.id, readable = false, nodes = {} }
  local c = call(api("C_Traits", "GetConfigIDByTreeID"), def.id)
  local configID = c and num(c[1], 1, 2 ^ 31)
  if not configID then return out end
  local currency
  local cr = call(api("C_Traits", "GetTreeCurrencyInfo"), configID, def.id, false)
  for _, info in ipairs(listOf(cr and cr[1], 8)) do
    if field(info, "traitCurrencyID") == V.CURRENCY_ID then currency = { quantity = num(field(info, "quantity")), spent = num(field(info, "spent")) } end
  end
  local nl = call(api("C_Traits", "GetTreeNodes"), def.id)
  local ids = listOf(nl and nl[1], V.NODES_MAX)
  for _, nodeID in ipairs(ids) do
    if not isSecret(nodeID) then
      local r = call(api("C_Traits", "GetNodeInfo"), configID, nodeID)
      local node = r and r[1]
      if type(node) == "table" and not isSecret(node) then
        local rank, max = num(field(node, "currentRank")), num(field(node, "maxRanks"))
        local visible = field(node, "isVisible")
        if rank and max and max > 0 and visible ~= false then
          local name, spell, entry = nodeName(configID, node)
          out.nodes[#out.nodes + 1] = { name = name, spell = spell, entry = entry, rank = rank, max = max }
        end
      end
    end
  end
  out.readable = #ids > 0
  return out, currency
end

local function classTitle(def)
  local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
  local n = type(names) == "table" and not isSecret(names) and text(field(names, def.file)) or nil
  if n then return n end
  local r = call(api("", "GetCategoryInfo"), def.cat)
  return r and text(r[1]) or nil
end

-- progress of a challenge: one criterion with a quantity (level 12 of 25) or the number of finished criteria (3 of 5); nil when not readable
local function readProgress(id)
  local n = call(api("", "GetAchievementNumCriteria"), id)
  n = n and num(n[1], 0, 500)
  local f = api("", "GetAchievementCriteriaInfo")
  if not n or n < 1 or not f then return nil end
  if n == 1 then
    local r = call(f, id, 1)
    local cur, tot = r and num(r[4], 0, 2 ^ 31), r and num(r[5], 0, 2 ^ 31)
    if cur and tot and tot > 1 then return min(cur, tot), tot end
    return nil
  end
  if n > V.CRITERIA_MAX then return nil end
  local done = 0
  for i = 1, n do
    local r = call(f, id, i)
    if not r then return nil end
    if bool(r[3]) == true then done = done + 1 end
  end
  return done, n
end

-- one achievement of a category -> { id, name, done, mine, pts, m, d, y, cur, tot } | nil
local function readAch(cat, index, info, pts)
  local r = call(info, cat, index)
  local id = r and num(r[1], 1, 2 ^ 31)
  if not id then return nil end
  local done = bool(r[4]) == true
  local t = { id = id, name = text(r[2]), done = done, mine = done and bool(r[13]) == true or false }
  local p = call(pts, V.CURRENCY_ID, id)
  t.pts = p and num(p[1]) or nil
  if done then
    local m, d, y = num(r[5], 1, 12), num(r[6], 1, 31), num(r[7], 0, 9999)
    if m and d and y then
      if y < 100 then y = y + 2000 end -- the client reports two digit years
      t.m, t.d, t.y = m, d, y
    end
  elseif t.pts == nil or t.pts > 0 then
    t.cur, t.tot = readProgress(id) -- only challenges (an achievement without Legacy points is not looked at further)
  end
  return t
end

local function readClass(def)
  local out = { file = def.file, cat = def.cat, name = classTitle(def), tiers = {} }
  local n = call(api("", "GetCategoryNumAchievements"), def.cat, true)
  local total = n and num(n[1]) or 0
  local info, pts = api("", "GetAchievementInfo"), api("C_Traits", "GetTraitCurrencyForAchievement")
  for i = 1, min(total, V.TIERS) do
    local t = readAch(def.cat, i, info, pts)
    if t then out.tiers[#out.tiers + 1] = t end
  end
  return out
end

-- ---------- the other challenge groups (professions, PvP, ...) ----------
-- The class categories are the only ones below one parent; the other Legacy challenges are ordinary achievements elsewhere (measured: 27 of
-- the 65 points lie in the class categories). They are FOUND by their points: one scan over all achievement categories looks at every
-- achievement and keeps those with C_Traits.GetTraitCurrencyForAchievement(4225, id) > 0 outside the class categories. The scan runs outside
-- combat in small steps (timer ticks) and stores only WHICH categories hold such achievements (EveNChronicleDB.legacy.found); every normal read
-- then reads just those categories. A group is the top category of the achievement (its real name: Professions, PvP, ...).

local CLASS_CAT = {}
for _, c in ipairs(V.CLASSES) do CLASS_CAT[c.cat] = true end

-- all categories: { ids, parent, names } | nil when the list is not readable
local function readCategories()
  local lr = call(api("", "GetCategoryList"))
  local ids = listOf(lr and lr[1], V.CATS_SCAN_MAX)
  local infoFn = api("", "GetCategoryInfo")
  if #ids == 0 or not infoFn then return nil end
  local c = { ids = {}, parent = {}, names = {} }
  for _, id in ipairs(ids) do
    local cid = num(id, 1, 2 ^ 31)
    if cid then
      local r = call(infoFn, cid)
      c.ids[#c.ids + 1] = cid
      c.parent[cid] = r and num(r[2], 1, 2 ^ 31) or nil
      c.names[cid] = r and text(r[1]) or nil
    end
  end
  return #c.ids > 0 and c or nil
end

-- top category of a category (follows the parents; guarded against loops)
local function topOf(cid, parent)
  local cur = cid
  for _ = 1, 8 do
    local p = parent[cur]
    if not p or p == cur then break end
    cur = p
  end
  return cur
end

local function foundCache()
  local db = ns.Store and ns.Store.db
  local f = type(db) == "table" and type(db.legacy) == "table" and db.legacy.found
  if type(f) ~= "table" or type(f.cats) ~= "table" then return nil end
  local at = num(f.at, 0, 2 ^ 40)
  if not at then return nil end
  local cats, n = {}, 0
  for cid, top in pairs(f.cats) do
    cid, top = num(cid, 1, 2 ^ 31), num(top, 1, 2 ^ 31)
    if cid and top and not CLASS_CAT[cid] and n < V.CATS_SCAN_MAX then cats[cid], n = top, n + 1 end
  end
  return { at = at, cats = cats }
end

local function saveFound(f)
  local db = ns.Store and ns.Store.db
  if type(db) ~= "table" then return end
  if type(db.legacy) ~= "table" then db.legacy = { v = 1 } end
  db.legacy.found = f
end

-- the groups from the found categories -> { { cat, name, items } }
local function readGroups(found)
  local out = {}
  if not found then return out end
  local c = readCategories()
  if not c then return out end
  local numFn = api("", "GetCategoryNumAchievements")
  local info, pts = api("", "GetAchievementInfo"), api("C_Traits", "GetTraitCurrencyForAchievement")
  local cids = {}
  for cid in pairs(found.cats) do
    if c.parent[cid] ~= nil or c.names[cid] ~= nil then cids[#cids + 1] = cid end
  end
  table.sort(cids)
  local byTop, tops = {}, {}
  for _, cid in ipairs(cids) do
    local top = topOf(cid, c.parent)
    local g = byTop[top]
    if not g then
      g = { cat = top, name = c.names[top], items = {} }
      byTop[top] = g
      tops[#tops + 1] = top
    end
    local n = call(numFn, cid)
    for i = 1, min(n and num(n[1], 0, 5000) or 0, V.CAT_ITEMS_MAX) do
      if #g.items >= V.ITEMS_MAX then break end
      local t = readAch(cid, i, info, pts)
      if t and t.pts and t.pts > 0 then g.items[#g.items + 1] = t end
    end
  end
  table.sort(tops)
  for _, top in ipairs(tops) do
    local g = byTop[top]
    if #out < V.GROUPS_MAX and g.name and #g.items > 0 then out[#out + 1] = g end
  end
  return out
end

-- discovery scan (timer ticks, not in combat)
local scan, scanFailAt
local doneFns = {}

function V.onScanDone(fn)
  if type(fn) == "function" then doneFns[#doneFns + 1] = fn end
end

function V.scanning() return scan ~= nil end

local function schedule(sec, fn)
  local T = rawget(_G, "C_Timer")
  if type(T) ~= "table" or type(T.After) ~= "function" then return false end
  return pcall(T.After, sec, fn)
end

local function finishScan()
  local st = scan
  scan = nil
  if not st then return end
  if st.total == 0 then
    scanFailAt = now() -- nothing readable: no cache, a later read tries again
    return
  end
  saveFound({ at = now(), cats = st.found })
  for _, fn in ipairs(doneFns) do pcall(fn) end
end

local function scanStep()
  local st = scan
  if not st then return end
  if inCombat() then
    if not schedule(2, scanStep) then scan = nil end
    return
  end
  local budget = V.SCAN_PER_TICK
  while budget > 0 do
    local cid = st.cats[st.ci]
    if not cid or st.total >= V.SCAN_MAX then return finishScan() end
    if not st.n then
      local n = call(st.numFn, cid)
      st.n, st.ai = n and num(n[1], 0, 5000) or 0, 1
    end
    if st.ai > st.n then
      st.ci, st.n = st.ci + 1, nil
    else
      local r = call(st.info, cid, st.ai)
      local id = r and num(r[1], 1, 2 ^ 31)
      if id then
        local p = call(st.pts, V.CURRENCY_ID, id)
        local v = p and num(p[1])
        if v and v > 0 then st.found[cid] = topOf(cid, st.parent) end
      end
      st.ai, st.total, budget = st.ai + 1, st.total + 1, budget - 1
    end
  end
  if not schedule(V.SCAN_TICK, scanStep) then scan = nil end
end

-- starts the scan (false: already running, nothing to scan, no timer)
function V.startScan()
  if scan or not V.active() or inCombat() then return false end
  local c = readCategories()
  local numFn, info, pts = api("", "GetCategoryNumAchievements"), api("", "GetAchievementInfo"), api("C_Traits", "GetTraitCurrencyForAchievement")
  if not (c and numFn and info and pts) then return false end
  local cats = {}
  for _, cid in ipairs(c.ids) do
    if not CLASS_CAT[cid] then cats[#cats + 1] = cid end
  end
  scan = { cats = cats, ci = 1, total = 0, found = {}, parent = c.parent, numFn = numFn, info = info, pts = pts }
  if not schedule(V.SCAN_TICK, scanStep) then
    scan = nil
    return false
  end
  return true
end

-- a scan is due when the list of found categories is missing or old (and the last failed one is not too recent)
local function scanDue(force)
  if scan then return false end
  if scanFailAt and now() - scanFailAt < V.SCAN_RETRY and now() >= scanFailAt then return false end
  local f = foundCache()
  return f == nil or now() - f.at >= V.FOUND_TTL or now() < f.at or (force == true and now() - f.at >= V.FOUND_TTL / 24)
end

local function itemName(itemID)
  local f = api("C_Item", "GetItemNameByID")
  local r = f and call(f, itemID)
  return r and text(r[1]) or nil
end

local function readReward(level)
  local r = call(api("C_MajorFactions", "GetRenownRewardsForLevel"), V.FACTION_ID, level)
  local pick
  for _, reward in ipairs(listOf(r and r[1], 6)) do
    if type(reward) == "table" and not isSecret(reward) then
      if not pick or (num(field(reward, "itemID"), 1, 2 ^ 31) and not num(field(pick, "itemID"), 1, 2 ^ 31)) then pick = reward end
    end
  end
  local out = { level = level }
  if pick then
    out.itemID = num(field(pick, "itemID"), 1, 2 ^ 31)
    out.name = text(field(pick, "name")) or (out.itemID and itemName(out.itemID)) or nil
    out.collected = bool(field(pick, "isCollected"))
  end
  return out
end

-- ---------- normalizing (every read and every cache load goes through here) ----------

local CLASS_BY_FILE, TREE_BY_KEY = {}, {}
for _, c in ipairs(V.CLASSES) do CLASS_BY_FILE[c.file] = c end
for _, t in ipairs(V.TREES) do TREE_BY_KEY[t.key] = t end
local REWARD_LEVEL = {}
for _, l in ipairs(V.REWARD_LEVELS) do REWARD_LEVEL[l] = true end

local function cleanTier(t)
  if type(t) ~= "table" then return nil end
  local out = { id = num(t.id, 1, 2 ^ 31), name = text(t.name), done = t.done == true, pts = num(t.pts) }
  out.mine = out.done and t.mine == true or false
  if not out.done then
    out.cur, out.tot = num(t.cur, 0, 2 ^ 31), num(t.tot, 1, 2 ^ 31)
    if not (out.cur and out.tot and out.cur <= out.tot) then out.cur, out.tot = nil, nil end
  end
  if out.done then
    out.m, out.d, out.y = num(t.m, 1, 12), num(t.d, 1, 31), num(t.y, 1, 9999)
    if not (out.m and out.d and out.y) then out.m, out.d, out.y = nil, nil, nil end
  end
  return out
end

function V.normalize(raw)
  if type(raw) ~= "table" or isSecret(raw) then return nil end
  local d = { groups = {}, at = num(raw.at, 0, 2 ^ 40) or 0, points = num(raw.points), pointsMax = num(raw.pointsMax), level = num(raw.level),
    levelMax = num(raw.levelMax), classes = {}, trees = {}, rewards = {} }
  for _, c in ipairs(type(raw.classes) == "table" and raw.classes or {}) do
    local def = type(c) == "table" and CLASS_BY_FILE[c.file]
    if def and #d.classes < #V.CLASSES then
      local tiers = {}
      for _, t in ipairs(type(c.tiers) == "table" and c.tiers or {}) do
        local ct = cleanTier(t)
        if ct and ct.id and #tiers < V.TIERS then tiers[#tiers + 1] = ct end
      end
      d.classes[#d.classes + 1] = { file = def.file, cat = def.cat, name = text(c.name), tiers = tiers }
    end
  end
  for _, g in ipairs(type(raw.groups) == "table" and raw.groups or {}) do
    local name = type(g) == "table" and text(g.name, 60) or nil
    local cat = type(g) == "table" and num(g.cat, 1, 2 ^ 31) or nil
    if name and cat and #d.groups < V.GROUPS_MAX then
      local items = {}
      for _, t in ipairs(type(g.items) == "table" and g.items or {}) do
        local ct = cleanTier(t)
        if ct and ct.id and #items < V.ITEMS_MAX then items[#items + 1] = ct end
      end
      if #items > 0 then d.groups[#d.groups + 1] = { key = "g" .. format("%.0f", cat), cat = cat, name = name, items = items } end
    end
  end
  for _, t in ipairs(type(raw.trees) == "table" and raw.trees or {}) do
    local def = type(t) == "table" and TREE_BY_KEY[t.key]
    if def and #d.trees < #V.TREES then
      local nodes = {}
      for _, n in ipairs(type(t.nodes) == "table" and t.nodes or {}) do
        local rank, max = type(n) == "table" and num(n.rank) or nil, type(n) == "table" and num(n.max) or nil
        if rank and max and max > 0 and #nodes < V.NODES_MAX then nodes[#nodes + 1] = { name = text(n.name), spell = num(n.spell, 1, 2 ^ 31), entry = num(n.entry, 1, 2 ^ 31), rank = rank, max = max } end
      end
      d.trees[#d.trees + 1] = { key = def.key, id = def.id, readable = t.readable == true, nodes = nodes }
    end
  end
  for _, r in ipairs(type(raw.rewards) == "table" and raw.rewards or {}) do
    local level = type(r) == "table" and num(r.level)
    if level and REWARD_LEVEL[level] and #d.rewards < #V.REWARD_LEVELS then
      local rw = { level = level, itemID = num(r.itemID, 1, 2 ^ 31), name = text(r.name) }
      if type(r.collected) == "boolean" then rw.collected = r.collected end -- nil = not readable (never "x and false or nil")
      d.rewards[#d.rewards + 1] = rw
    end
  end
  local any = d.points ~= nil or d.level ~= nil
  for _, c in ipairs(d.classes) do if #c.tiers > 0 then any = true end end
  for _, t in ipairs(d.trees) do if #t.nodes > 0 then any = true end end
  if #d.groups > 0 then any = true end
  for _, r in ipairs(d.rewards) do if r.itemID or r.name then any = true end end
  d.readable = any
  return d
end

-- ---------- cache (account SV) ----------

local function loadCache()
  local db = ns.Store and ns.Store.db
  local c = type(db) == "table" and db.legacy
  if type(c) ~= "table" then return nil end
  local d = V.normalize(c.data)
  if d and d.readable then return d end
  return nil
end

local function saveCache(d)
  local db = ns.Store and ns.Store.db
  if type(db) ~= "table" then return end
  local keep = type(db.legacy) == "table" and db.legacy.found or nil
  db.legacy = { v = 1, data = d, found = keep }
end

function V.clearCache()
  local db = ns.Store and ns.Store.db
  if type(db) == "table" then db.legacy = nil end
  scan, scanFailAt = nil, nil
end

-- ---------- public ----------

-- reads everything now (not in combat: the caller checks); -> normalized data (data.readable tells whether anything was readable)
function V.read()
  local raw = { at = now(), classes = {}, trees = {}, rewards = {} }
  raw.level, raw.levelMax = readRenown()
  raw.pointsMax = readPointsMax()
  local quantity, spent, anySpent = nil, 0, false
  for _, def in ipairs(V.TREES) do
    local tree, currency = readTree(def)
    raw.trees[#raw.trees + 1] = tree
    if currency then
      quantity = quantity or currency.quantity
      if currency.spent then spent, anySpent = spent + currency.spent, true end
    end
  end
  raw.points = raw.level
  if raw.points == nil and quantity then raw.points = quantity + (anySpent and spent or 0) end
  for _, def in ipairs(V.CLASSES) do raw.classes[#raw.classes + 1] = readClass(def) end
  raw.groups = readGroups(foundCache())
  for _, level in ipairs(V.REWARD_LEVELS) do raw.rewards[#raw.rewards + 1] = readReward(level) end
  return V.normalize(raw)
end

-- data, status, reason. force = read again even if the last read is fresh
function V.get(force)
  if not V.active() then return nil, "off" end
  local cached = loadCache()
  if inCombat() then
    if cached then return cached, "stale", "combat" end
    return nil, "combat"
  end
  if scanDue(force) then V.startScan() end
  if not force and cached and cached.at > 0 and now() - cached.at >= 0 and now() - cached.at < V.TTL then return cached, "ok" end
  local d = V.read()
  if d and d.readable then
    saveCache(d)
    return d, "ok"
  end
  if cached then return cached, "stale", "unreadable" end
  return nil, "unreadable"
end
