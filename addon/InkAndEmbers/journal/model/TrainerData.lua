-- Class trainer data and recognition (1.1.0, core): the data/recognition half of the Lehrplan. The Trainer collector records
-- trainer visits (class and pet trainer) with it, also without the module Plans; the Lehrplan (journal/model/Lehrplan.lua,
-- module Plans) builds its view and to-dos on top of it.
-- Data: ns.TrainerSpells (data/TrainerSpells.lua, MIT, from "What's Training?"). Pet training state: snapshots.state.petTraining
-- (written by collectors/Trainer.lua). WoW Forever only: on retail clients (class spells come automatically) it stays off.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local TrainerData = {}
Journal.TrainerData = TrainerData

local floor, gmatch, match = math.floor, string.gmatch, string.match

TrainerData.ALLOW_RETAIL = false   -- tests: switch the retail block off
TrainerData.PET_CLASS = "HUNTER"   -- the only class with a pet trainer section
-- race file -> race id (fallback if UnitRace has no third return)
TrainerData.RACE_IDS = { Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Tauren = 6, Gnome = 7, Troll = 8 }

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

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d
end

-- Retail client: the shared check Journal.MapSpace.retailClient (project id AND interface version, so Forever is never Retail).
-- The developer switches ns.devForceTrainer and the Lehrplan's own ALLOW_RETAIL (tests, module Plans) count as well.
function TrainerData.active()
  if TrainerData.ALLOW_RETAIL or ns.devForceTrainer == true then return true end
  local LP = Journal.Lehrplan
  if type(LP) == "table" and LP.ALLOW_RETAIL == true then return true end
  local ms = Journal.MapSpace
  return not (ms ~= nil and ms.retailClient() == true)
end

-- player: { class = "PALADIN", faction = "A"|"H"|nil, race = id|nil, level = n|nil }
function TrainerData.player()
  local _, cls = call(UnitClass, "player")
  local fac = str((call(UnitFactionGroup, "player")))
  local _, raceFile, raceID = call(UnitRace, "player")
  local level = num((call(UnitLevel, "player")))
  local race = num(raceID)
  if not race and str(raceFile) then race = TrainerData.RACE_IDS[raceFile] end
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
function TrainerData.parse(cls)
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

function TrainerData.resetCache()
  cache = {}
end

-- Hunter pet ability IDs (pets.<CLASS> in the data: Beast Training, taught by the pet trainer, not part of the class plan).
-- The Trainer collector uses them to tell a pet trainer window from a class trainer window.
function TrainerData.petIds(cls)
  local D = ns.TrainerSpells
  local text = type(cls) == "string" and type(D) == "table" and type(D.pets) == "table" and D.pets[cls] or nil
  local out = {}
  for line in gmatch(type(text) == "string" and text or "", "[^\n]+") do
    local id = match(line, "^%d+\t(%d+)\t")
    if id then out[#out + 1] = tonumber(id) end
  end
  return out
end

function TrainerData.dataInfo()
  local D = ns.TrainerSpells
  if type(D) ~= "table" then return nil end
  return { source = D.source, commit = D.commit, date = D.date, license = D.license }
end

-- Spell names (client, in its language): journal/model/SpellBook.lua (cache and fallback name live there)
function TrainerData.spellInfo(id)
  local SB = Journal.SpellBook
  return SB and SB.spellInfo(id) or nil
end

local function charTable()
  local S = ns.Store
  local c = S and S.char and S.char()
  return type(c) == "table" and c or nil
end

-- Pet training (hunter, Beast Training). State of the last pet trainer visits: snapshots.state.petTraining =
-- { level, at, visited, learned = { [id] = true }, open = { [id] = true } } (collectors/Trainer.lua). "learned" is proof of learned
-- (row "used", learn message); "open" is proof of not learned (row "available"/"unavailable"). The trainer window hides learned
-- rows by default, so a missing row proves nothing: an id in neither set is "unknown".
function TrainerData.petTraining()
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
-- ability too), ids in openIds become open unless already learned. old = TrainerData.petTraining() result or nil.
-- Returns { learned = set, open = set } restricted to known pet ids, or nil without pet data.
function TrainerData.petMerge(old, learnedIds, openIds)
  local plan = TrainerData.parse(TrainerData.PET_CLASS)
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
