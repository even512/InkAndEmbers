-- Lehrplan (class trainer plan, WoW Forever only): which class spells the trainer teaches at which level, what is learned,
-- what is learnable now and what it costs, what comes next, spells from class quests, free talent points and the nearest
-- known class trainer. Display-ready data for pages/QuestsLehrplan.lua and collectors/Trainer.lua (to-do, reminder).
-- Data: ns.TrainerSpells (data/TrainerSpells.lua, MIT, from "What's Training?"); learned spells from the client spellbook
-- (C_SpellBook / IsPlayerSpell); trainer visits and locations from collectors/Trainer.lua (snapshots.trainers,
-- snapshots.state.trainerVisit). On retail clients (class spells come automatically) everything stays off.
-- Learned check (like What's Training?): a rank counts as learned if the client knows it, if a higher rank of the same group
-- is known (ranks replace each other in the spellbook) or if a spell that requires it is known.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Lehrplan = {}
Journal.Lehrplan = Lehrplan

local floor, gmatch, match = math.floor, string.gmatch, string.match

Lehrplan.ALLOW_RETAIL = false   -- tests: switch the retail block off
Lehrplan.MAX_TRAINERS = 200     -- trainer locations read across all characters
Lehrplan.PET_CLASS = "HUNTER"   -- the only class with a pet trainer section
Lehrplan.NEXT_LEVELS = 4        -- "coming next" levels in the summary
-- race file -> race id (fallback if UnitRace has no third return)
Lehrplan.RACE_IDS = { Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Tauren = 6, Gnome = 7, Troll = 8 }

local T = ns.Locale.ns("m.Lehrplan", {
  spellFallback = "Zauber %s",
})
Lehrplan.TEXT = T

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function str(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

local function tbl(v)
  if type(v) == "table" and not isSecret(v) then return v end
  return nil
end

local function isTrue(v)
  return not isSecret(v) and v == true
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d
end

-- Retail client: the shared check Journal.MapSpace.retailClient (project id AND interface version, so Forever is never Retail).
function Lehrplan.active()
  local ms = Journal.MapSpace
  return Lehrplan.ALLOW_RETAIL or ns.devForceTrainer == true or not (ms ~= nil and ms.retailClient() == true)
end

-- player: { class = "PALADIN", faction = "A"|"H"|nil, race = id|nil, level = n|nil }
function Lehrplan.player()
  local _, cls = call(UnitClass, "player")
  local fac = str((call(UnitFactionGroup, "player")))
  local _, raceFile, raceID = call(UnitRace, "player")
  local level = num((call(UnitLevel, "player")))
  local race = num(raceID)
  if not race and str(raceFile) then race = Lehrplan.RACE_IDS[raceFile] end
  return {
    class = str(cls),
    faction = fac == "Alliance" and "A" or fac == "Horde" and "H" or nil,
    race = race and floor(race) or nil,
    level = level and floor(level) or nil,
  }
end

-- Data

local function idList(s)
  local out = {}
  for id in gmatch(s or "", "%d+") do
    out[#out + 1] = tonumber(id)
    if #out >= 32 then break end
  end
  return out
end

local cache = {}

-- parsed data of a class (cached): { list = { entry }, byId, groupOf = { [id] = { group, index } }, quests = { ... } }
function Lehrplan.parse(cls)
  if type(cls) ~= "string" then return nil end
  if cache[cls] then return cache[cls] end
  local D = ns.TrainerSpells
  local text = type(D) == "table" and type(D.spells) == "table" and D.spells[cls]
  if type(text) ~= "string" then return nil end
  local list, byId = {}, {}
  for line in gmatch(text, "[^\n]+") do
    local lv, id, cost, req, tal, fac, race = match(line, "^(%d+)\t(%d+)\t(%d*)\t([%d,]*)\t(%d*)\t([AH]?)\t(%d*)$")
    if lv then
      local e = { level = tonumber(lv), id = tonumber(id), cost = tonumber(cost) or 0, req = idList(req), talent = tonumber(tal),
        faction = fac ~= "" and fac or nil, race = tonumber(race), idx = #list + 1 }
      list[#list + 1] = e
      if not byId[e.id] then byId[e.id] = e end
    end
  end
  local groupOf = {}
  local g = type(D.groups) == "table" and D.groups[cls] or nil
  for part in gmatch(type(g) == "string" and g or "", "[^;]+") do
    local ids = idList(part)
    for i, id in ipairs(ids) do groupOf[id] = { ids, i } end
  end
  local quests = {}
  local q = type(D.quests) == "table" and D.quests[cls] or nil
  for line in gmatch(type(q) == "string" and q or "", "[^\n]+") do
    local id, lv, races, qs, areas = match(line, "^(%d+)\t(%d+)\t([%d,]*)\t([%d,]*)\t([%d,]*)$")
    if id then
      quests[#quests + 1] = { id = tonumber(id), level = tonumber(lv), races = idList(races), quests = idList(qs), areas = idList(areas) }
    end
  end
  local plan = { list = list, byId = byId, groupOf = groupOf, quests = quests }
  -- pet abilities (Beast Training): same line format, own list; only classes that have pets.<CLASS> data
  local pt = type(D.pets) == "table" and D.pets[cls] or nil
  if type(pt) == "string" then
    local plist, pById = {}, {}
    for line in gmatch(pt, "[^\n]+") do
      local lv, id, cost, req = match(line, "^(%d+)\t(%d+)\t(%d*)\t([%d,]*)\t(%d*)\t([AH]?)\t(%d*)$")
      if lv then
        local e = { level = tonumber(lv), id = tonumber(id), cost = tonumber(cost) or 0, req = idList(req), idx = #plist + 1 }
        plist[#plist + 1] = e
        if not pById[e.id] then pById[e.id] = e end
      end
    end
    if #plist > 0 then plan.pets = { list = plist, byId = pById } end
  end
  cache[cls] = plan
  return plan
end

function Lehrplan.resetCache()
  cache = {}
end

-- Hunter pet ability IDs (pets.<CLASS> in the data: Beast Training, taught by the pet trainer, not part of the class plan).
-- The Trainer collector uses them to tell a pet trainer window from a class trainer window; the rows themselves are plan.pets
-- (Lehrplan.parse) and are evaluated by Lehrplan.evaluatePets.
function Lehrplan.petIds(cls)
  local D = ns.TrainerSpells
  local text = type(cls) == "string" and type(D) == "table" and type(D.pets) == "table" and D.pets[cls] or nil
  local out = {}
  for line in gmatch(type(text) == "string" and text or "", "[^\n]+") do
    local id = match(line, "^%d+\t(%d+)\t")
    if id then out[#out + 1] = tonumber(id) end
  end
  return out
end

function Lehrplan.dataInfo()
  local D = ns.TrainerSpells
  if type(D) ~= "table" then return nil end
  return { source = D.source, commit = D.commit, date = D.date, license = D.license }
end

-- Known spells

local function bankPlayer()
  local E = rawget(_G, "Enum")
  local B = type(E) == "table" and not isSecret(E) and tbl(E.SpellBookSpellBank) or nil
  return B and B.Player or nil
end

-- one spell, client only (no rank rules)
function Lehrplan.clientKnows(id)
  id = num(id)
  if not id then return false end
  local SB = tbl(C_SpellBook)
  if SB then
    local bank = bankPlayer()
    if isTrue((call(SB.IsSpellKnown, id, bank))) then return true end
    if isTrue((call(SB.IsSpellInSpellBook, id, bank, false))) then return true end
  end
  if isTrue((call(rawget(_G, "IsPlayerSpell"), id))) then return true end
  if isTrue((call(rawget(_G, "IsSpellKnown"), id))) then return true end
  return false
end

-- learned set for a plan: client + higher rank of the same group + spell that requires it (repeated, chains)
function Lehrplan.knownSet(plan)
  local known, asked = {}, {}
  local function ask(id)
    if id and asked[id] == nil then
      asked[id] = Lehrplan.clientKnows(id)
      if asked[id] then known[id] = true end
    end
  end
  for _, e in ipairs(plan.list) do
    ask(e.id)
    for _, r in ipairs(e.req) do ask(r) end
    ask(e.talent)
  end
  for _, q in ipairs(plan.quests) do ask(q.id) end
  for id, g in pairs(plan.groupOf) do
    ask(id)
    if known[id] then
      for i = 1, g[2] - 1 do known[g[1][i]] = true end
    end
  end
  for _ = 1, 6 do
    local changed = false
    for _, e in ipairs(plan.list) do
      if known[e.id] then
        for _, r in ipairs(e.req) do
          if not known[r] then
            known[r] = true
            changed = true
          end
        end
      end
    end
    if not changed then break end
  end
  return known
end

-- Spell names (client, in its language); missing data is requested once and filled on the next draw

local infoCache = {}

function Lehrplan.spellInfo(id)
  id = num(id)
  if not id then return nil end
  local hit = infoCache[id]
  if hit then return hit end
  local CS = tbl(C_Spell)
  local name, rank, icon
  if CS then
    name = str((call(CS.GetSpellName, id)))
    rank = str((call(CS.GetSpellSubtext, id)))
    icon = (call(CS.GetSpellTexture, id))
  end
  if not name then
    local n, _, ic = call(rawget(_G, "GetSpellInfo"), id)
    name, icon = str(n), icon or ic
  end
  if isSecret(icon) or (type(icon) ~= "number" and type(icon) ~= "string") then icon = nil end
  if not name then
    if CS then call(CS.RequestLoadSpellData, id) end
    return { name = T("spellFallback", id), missing = true, icon = icon }
  end
  local info = { name = ns.Sanitize.field(name), rank = rank and ns.Sanitize.field(rank) or nil, icon = icon }
  infoCache[id] = info
  return info
end

function Lehrplan.resetNames()
  infoCache = {}
end

-- Visits (collectors/Trainer.lua): snapshots.state.trainerVisit = { level, at, names = { "spell name", ... } } = the services the
-- class trainer offered as "available" at the last visit. Used to spot entries the trainer did not offer (data differs from
-- Forever) so the to-do does not stay open forever.

local function charTable()
  local S = ns.Store
  local c = S and S.char and S.char()
  return type(c) == "table" and c or nil
end

function Lehrplan.lastVisit()
  local c = charTable()
  local st = c and type(c.snapshots) == "table" and type(c.snapshots.state) == "table" and c.snapshots.state.trainerVisit or nil
  if type(st) ~= "table" or type(st.level) ~= "number" then return nil end
  local names = {}
  if type(st.names) == "table" then
    for _, n in pairs(st.names) do
      if type(n) == "string" then names[n] = true end
    end
  end
  return { level = st.level, at = st.at, names = names }
end

local function fits(e, p)
  if e.faction and p.faction and e.faction ~= p.faction then return false end
  if e.race and e.race ~= p.race then return false end
  return true
end

local function questFits(q, p)
  if #q.races == 0 then return true end
  for _, r in ipairs(q.races) do
    if r == p.race then return true end
  end
  return false
end

-- Evaluation. opts: level (override, e.g. right after PLAYER_LEVEL_UP), money (copper), names (false = no name lookups)
-- -> { available, reason, class, level, rows = { { id, level, cost, state, name, rank, icon, req, talent, quests, offered } },
--      now = { n, cost }, missing = { n }, talent = { n }, learned = { n, cost }, next = { { level, n, cost } }, todo = { n, cost },
--      money, short }
-- state: "learned" | "now" (learnable now) | "missing" (level reached, previous rank missing) | "talent" (talent missing)
--        | "later" (level not reached) | "quest" (from a class quest, not from the trainer)
function Lehrplan.evaluate(opts)
  opts = type(opts) == "table" and opts or {}
  local out = { available = false, rows = {}, now = { n = 0, cost = 0 }, missing = { n = 0 }, talent = { n = 0 },
    learned = { n = 0, cost = 0 }, next = {}, todo = { n = 0, cost = 0 }, later = { n = 0 } }
  if not Lehrplan.active() then
    out.reason = "RETAIL"
    return out
  end
  local p = Lehrplan.player()
  out.class = p.class
  local plan = Lehrplan.parse(p.class)
  if not plan then
    out.reason = p.class and "NODATA" or "NOCLASS"
    return out
  end
  out.available = true
  local level = num(opts.level) or p.level or 1
  out.level = level
  local known = Lehrplan.knownSet(plan)
  local visit = Lehrplan.lastVisit()
  if visit and visit.level ~= level then visit = nil end
  local nextBy = {}
  local names = opts.names ~= false
  for _, e in ipairs(plan.list) do
    if fits(e, p) then
      local r = { id = e.id, level = e.level, cost = e.cost, req = e.req, talent = e.talent }
      if known[e.id] then
        r.state = "learned"
        out.learned.n = out.learned.n + 1
        out.learned.cost = out.learned.cost + e.cost
      elseif e.talent and not known[e.talent] then
        r.state = "talent"
        out.talent.n = out.talent.n + 1
      elseif e.level > level then
        r.state = "later"
        out.later.n = out.later.n + 1
        local nb = nextBy[e.level]
        if not nb then
          nb = { level = e.level, n = 0, cost = 0 }
          nextBy[e.level] = nb
        end
        nb.n = nb.n + 1
        nb.cost = nb.cost + e.cost
      else
        local ok = true
        for _, req in ipairs(e.req) do
          if not known[req] then ok = false end
        end
        r.state = ok and "now" or "missing"
        if ok then
          out.now.n = out.now.n + 1
          out.now.cost = out.now.cost + e.cost
        else
          out.missing.n = out.missing.n + 1
        end
      end
      if names then
        local info = Lehrplan.spellInfo(e.id)
        if info then r.name, r.rank, r.icon, r.missingName = info.name, info.rank, info.icon, info.missing end
      end
      if r.state == "now" then
        -- visit at this level: the trainer did not list this name as available -> not offered (data differs)
        r.offered = not (visit and r.name and not r.missingName and not visit.names[r.name])
        if r.offered then
          out.todo.n = out.todo.n + 1
          out.todo.cost = out.todo.cost + e.cost
        end
      end
      out.rows[#out.rows + 1] = r
    end
  end
  for _, q in ipairs(plan.quests) do
    if questFits(q, p) and not known[q.id] and not (plan.byId[q.id] and known[q.id]) then
      local r = { id = q.id, level = q.level, cost = 0, req = {}, state = "quest", quests = q.quests }
      if names then
        local info = Lehrplan.spellInfo(q.id)
        if info then r.name, r.rank, r.icon, r.missingName = info.name, info.rank, info.icon, info.missing end
      end
      out.rows[#out.rows + 1] = r
    end
  end
  -- hunter only: pet abilities (own list for the Pet Training tab; never part of the class counts above, so "Zum Lehrer" ignores them)
  if plan.pets and p.class == Lehrplan.PET_CLASS then
    out.pets = Lehrplan.evaluatePets(plan.pets, level, names)
  elseif ns.devForceHunter == true then
    -- development switch (journal/SimPanel.lua, not in the release package): preview of the hunter Pet Training tab for another class
    local hunter = Lehrplan.parse(Lehrplan.PET_CLASS)
    if hunter and hunter.pets then out.pets = Lehrplan.evaluatePets(hunter.pets, level, names, true) end
  end
  local levels = {}
  for lv in pairs(nextBy) do levels[#levels + 1] = lv end
  table.sort(levels)
  for i = 1, math.min(#levels, Lehrplan.NEXT_LEVELS) do out.next[i] = nextBy[levels[i]] end
  local money = num(opts.money)
  if money == nil then money = num((call(rawget(_G, "GetMoney")))) end
  out.money = money
  out.short = money and out.now.cost > money and (out.now.cost - money) or 0
  return out
end

-- Pet training (hunter, Beast Training). State of the last pet trainer visits: snapshots.state.petTraining =
-- { level, at, visited, learned = { [id] = true }, open = { [id] = true } } (collectors/Trainer.lua). "learned" is proof of learned
-- (row "used", learn message); "open" is proof of not learned (row "available"/"unavailable"). The trainer window hides learned
-- rows by default, so a missing row proves nothing: an id in neither set is "unknown".
function Lehrplan.petTraining()
  local c = charTable()
  local st = c and type(c.snapshots) == "table" and type(c.snapshots.state) == "table" and c.snapshots.state.petTraining or nil
  if type(st) ~= "table" then return nil end
  local function set(v)
    local out = {}
    if type(v) == "table" then
      for id, on in pairs(v) do
        if on == true and type(id) == "number" then out[id] = true end
      end
    end
    return out
  end
  return { level = num(st.level), at = num(st.at), visited = st.visited == true, learned = set(st.learned), open = set(st.open) }
end

-- Merge of a new reading into the stored state (never resets "learned"): ids in learnedIds become learned (lower ranks of the same
-- ability too), ids in openIds become open unless already learned. old = Lehrplan.petTraining() result or nil.
-- Returns { learned = set, open = set } restricted to known pet ids, or nil without pet data.
function Lehrplan.petMerge(old, learnedIds, openIds)
  local plan = Lehrplan.parse(Lehrplan.PET_CLASS)
  local pets = plan and plan.pets
  if not pets then return nil end
  local learned, open = {}, {}
  local function take(dst, src)
    if type(src) ~= "table" then return end
    for id, on in pairs(src) do
      if on == true and pets.byId[id] then dst[id] = true end
    end
  end
  take(learned, old and old.learned)
  take(open, old and old.open)
  take(learned, learnedIds)
  take(open, openIds)
  -- higher rank learned => every lower rank of the chain learned (repeated: chains)
  for _ = 1, 12 do
    local changed = false
    for id in pairs(learned) do
      for _, r in ipairs(pets.byId[id].req) do
        if not learned[r] and pets.byId[r] then
          learned[r] = true
          changed = true
        end
      end
    end
    if not changed then break end
  end
  for id in pairs(learned) do open[id] = nil end
  return { learned = learned, open = open }
end

-- rows of the pet list: { id, level, cost, req, pet = true, state, name, rank, icon }
-- state: "learned" | "now" (open at the visit, level reached, no open lower rank) | "missing" (a lower rank is known unlearned)
--        | "later" (level not reached) | "unknown" (level reached, never seen in the window and not known learned: no guessing)
-- -> { rows, seen (visited a pet trainer), at, learned = { n }, now = { n, cost }, missing = { n }, later = { n }, unknown = { n },
--      todo = { n, cost } } ("todo" = learnable now, as for the class spells)
-- Sample state of the development preview (memory only, never stored): first two ranks of Great Stamina and Natural Armor learned,
-- everything else seen at the trainer except two level-20 abilities (shown as unknown).
local SAMPLE_LEARNED = { 4187, 4188, 24545, 24549 }
local SAMPLE_UNSEEN = { [24493] = true, [23992] = true }

local function sampleTraining(pets)
  local pt = { visited = true, learned = {}, open = {} }
  for _, id in ipairs(SAMPLE_LEARNED) do pt.learned[id] = true end
  for _, e in ipairs(pets.list) do
    if not pt.learned[e.id] and not SAMPLE_UNSEEN[e.id] then pt.open[e.id] = true end
  end
  return pt
end

function Lehrplan.evaluatePets(pets, level, names, preview)
  local pt = preview and sampleTraining(pets) or Lehrplan.petTraining()
  local out = { preview = preview == true or nil, rows = {}, seen = pt ~= nil and pt.visited == true, at = pt and pt.at, learned = { n = 0 }, now = { n = 0, cost = 0 },
    missing = { n = 0 }, later = { n = 0 }, unknown = { n = 0 }, todo = { n = 0, cost = 0 }, next = {} }
  local nextBy = {}
  for _, e in ipairs(pets.list) do
    local r = { id = e.id, level = e.level, cost = e.cost, req = e.req, pet = true }
    if pt and pt.learned[e.id] then
      r.state = "learned"
      out.learned.n = out.learned.n + 1
    elseif e.level > level then
      r.state = "later"
      out.later.n = out.later.n + 1
      local nb = nextBy[e.level]
      if not nb then
        nb = { level = e.level, n = 0, cost = 0 }
        nextBy[e.level] = nb
      end
      nb.n = nb.n + 1
      nb.cost = nb.cost + e.cost
    elseif pt and pt.open[e.id] then
      local ok = true
      for _, req in ipairs(e.req) do
        if pt.open[req] then ok = false end
      end
      r.state = ok and "now" or "missing"
      if ok then
        out.now.n = out.now.n + 1
        out.now.cost = out.now.cost + e.cost
        out.todo.n = out.todo.n + 1
        out.todo.cost = out.todo.cost + e.cost
      else
        out.missing.n = out.missing.n + 1
      end
    else
      r.state = "unknown"
      out.unknown.n = out.unknown.n + 1
    end
    if names then
      local info = Lehrplan.spellInfo(e.id)
      if info then r.name, r.rank, r.icon, r.missingName = info.name, info.rank, info.icon, info.missing end
    end
    out.rows[#out.rows + 1] = r
  end
  local levels = {}
  for lv in pairs(nextBy) do levels[#levels + 1] = lv end
  table.sort(levels)
  for i = 1, math.min(#levels, Lehrplan.NEXT_LEVELS) do out.next[i] = nextBy[levels[i]] end
  return out
end

-- Is the sub-view "Tierausbildung" on offer? Only where the trainer plan is on (not Retail) and only for hunters (class of the logged-in
-- character) - or while the development preview /chronik sim jaeger is on (journal/SimPanel.lua, not in the release package).
function Lehrplan.petTabVisible()
  if not Lehrplan.active() then return false end
  if ns.devForceHunter == true then return true end
  local plan = Lehrplan.parse(Lehrplan.player().class)
  return plan ~= nil and plan.pets ~= nil and Lehrplan.player().class == Lehrplan.PET_CLASS
end

-- Rows of the pet view for a page filter (same filters as the class spells): "now" = learnable now + missing lower rank +
-- unknown (level reached), "next" = later, "learned", "all". Sorted by level, then id.
function Lehrplan.petRows(pv, filter)
  local out = {}
  if type(pv) ~= "table" or type(pv.rows) ~= "table" then return out end
  for _, r in ipairs(pv.rows) do
    local s = r.state
    local take
    if filter == "now" then
      take = s == "now" or s == "missing" or s == "unknown"
    elseif filter == "next" then
      take = s == "later"
    elseif filter == "learned" then
      take = s == "learned"
    else
      take = true
    end
    if take then out[#out + 1] = r end
  end
  table.sort(out, function(a, b)
    if a.level ~= b.level then
      if filter == "learned" then return a.level > b.level end
      return a.level < b.level
    end
    return a.id < b.id
  end)
  return out
end

-- Rows for the page: filter "now" (learnable now + missing rank + talent at reached level), "next" (later + quests),
-- "learned", "all". Sorted by level, then state, then data order.
local ORDER = { now = 1, missing = 2, talent = 3, quest = 4, later = 5, learned = 6 }
Lehrplan.FILTERS = { "now", "next", "learned", "all" }

function Lehrplan.rows(view, filter)
  local out = {}
  if type(view) ~= "table" or type(view.rows) ~= "table" then return out end
  local level = view.level or 1
  for _, r in ipairs(view.rows) do
    local s = r.state
    local take
    if filter == "now" then
      take = s == "now" or s == "missing" or (s == "talent" and r.level <= level) or (s == "quest" and r.level <= level)
    elseif filter == "next" then
      take = s == "later" or (s == "quest" and r.level > level)
    elseif filter == "learned" then
      take = s == "learned"
    else
      take = true
    end
    if take then out[#out + 1] = r end
  end
  table.sort(out, function(a, b)
    if a.level ~= b.level then
      if filter == "learned" then return a.level > b.level end
      return a.level < b.level
    end
    if ORDER[a.state] ~= ORDER[b.state] then return ORDER[a.state] < ORDER[b.state] end
    return a.id < b.id
  end)
  return out
end

-- Talent points: free points of the active C_Traits config (like collectors/Character.lua). nil = not readable.
function Lehrplan.unspentTalents()
  local CT, TR = tbl(C_ClassTalents), tbl(C_Traits)
  if not (CT and TR) then return nil end
  local configID = num((call(CT.GetActiveConfigID)))
  if not configID then return nil end
  local cfg = tbl((call(TR.GetConfigInfo, configID)))
  local trees = cfg and tbl(cfg.treeIDs)
  if not trees then return nil end
  for ti = 1, 4 do
    local treeID = num(trees[ti])
    if not treeID then break end
    local cur = tbl((call(TR.GetTreeCurrencyInfo, configID, treeID, false)))
    local c1 = cur and tbl(cur[1])
    local q = c1 and num(c1.quantity)
    if q then return math.max(0, floor(q)) end
  end
  return nil
end

-- Trainer locations (own visits, all characters of this class and faction): { { name, mapID, x, y, zone, dist } }

local function validMap(v)
  v = num(v)
  if not v or v <= 0 or v > 2147483647 or v ~= floor(v) then return nil end
  return v
end

-- Stored trainer places come from Zone.here() as tenths of a permille (integers 0..9999, collectors/Trainer.lua); Plans and
-- Plans.distance expect map fractions 0..1. Reads both: 0..1 is taken as is, 1 < v <= 10000 is divided by 10000, the scale of
-- Zone.coord (value 1 stays a fraction). Anything else (secret, negative, too large) is dropped.
local COORD_SCALE = 10000

local function coord(v)
  v = num(v)
  if not v or v < 0 or v > COORD_SCALE then return nil end
  if v <= 1 then return v end
  return v / COORD_SCALE
end

function Lehrplan.trainers(p)
  p = p or Lehrplan.player()
  local out = {}
  local S = ns.Store
  local db = S and S.db
  local chars = type(db) == "table" and type(db.chars) == "table" and db.chars or nil
  if not (chars and p.class) then return out end
  local seen = {}
  for _, c in pairs(chars) do
    local info = type(c) == "table" and type(c.info) == "table" and c.info or nil
    local snaps = type(c) == "table" and type(c.snapshots) == "table" and c.snapshots or nil
    local list = snaps and type(snaps.trainers) == "table" and snaps.trainers or nil
    local facOk = info and (p.faction == nil or (info.faction == "Alliance" and "A" or info.faction == "Horde" and "H" or nil) == p.faction)
    if list and info and info.classFile == p.class and facOk then
      for key, t in pairs(list) do
        if type(t) == "table" and #out < Lehrplan.MAX_TRAINERS then
          local mapID, x, y = validMap(t.mapID), coord(t.x), coord(t.y)
          local name = type(t.name) == "string" and t.name or nil
          local id = tostring(key)
          if mapID and x and y and name and not seen[id] and (t.class == nil or t.class == p.class) then
            seen[id] = true
            out[#out + 1] = { key = id, name = ns.Sanitize.field(name), mapID = mapID, x = x, y = y, at = num(t.at) }
          end
        end
      end
    end
  end
  return out
end

-- nearest known trainer: shortest distance (Plans.distance, same continent); without any distance the newest visit on the
-- player's continent is not knowable -> nil
function Lehrplan.nearestTrainer(p)
  local list = Lehrplan.trainers(p)
  if #list == 0 then return nil, 0 end
  local Plans = ns.Plans
  local best, bestD
  for _, t in ipairs(list) do
    local d = Plans and type(Plans.distance) == "function" and num((call(Plans.distance, { kind = "place", mapID = t.mapID, x = t.x, y = t.y }))) or nil
    if d and (not bestD or d < bestD) then best, bestD = t, d end
  end
  if best then
    best.dist = bestD
  else
    -- nothing on this continent: the most recently visited one, without a distance
    table.sort(list, function(a, b) return (a.at or 0) > (b.at or 0) end)
    best = list[1]
  end
  local info = ns.Zone and ns.Zone.info and ns.Zone.info(best.mapID)
  local zone = info and str(info.name)
  if not zone then
    -- map name remembered by the chronicle (snapshots.maps)
    local c = charTable()
    local maps = c and type(c.snapshots) == "table" and type(c.snapshots.maps) == "table" and c.snapshots.maps or nil
    local e = maps and maps[best.mapID]
    zone = type(e) == "table" and str(e.name) or nil
  end
  best.zone = zone and ns.Sanitize.field(zone) or nil
  return best, #list
end

-- training fees paid so far (collectors/Money.lua books money spent with an open trainer as money_out.training)
function Lehrplan.feesPaid()
  local c = charTable()
  local cnt = c and type(c.counters) == "table" and c.counters.money_out
  local v = type(cnt) == "table" and num(cnt.training) or nil
  return v and floor(v) or 0
end
