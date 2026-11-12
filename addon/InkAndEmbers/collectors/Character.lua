-- Collector 'Character': learned spells/ranks, talent points, professions/skills, reputation, stats per level.
-- Spells: LEARNED_SPELL_IN_SKILL_LINE gives the spellID, the system message the kind; merged. SP only for new spells; at login the client re-fires the event for known ones (snapshot only).
-- Talents: C_Traits (nil-safe), a TA line per node and change. Professions: GetProfessions + skill-up message. Reputation: messages (RP), C_Reputation tier changes (RT). Stats: snapshots.stats[level].
local _, ns = ...
local Core, Store, Patterns = ns.Core, ns.Store, ns.Patterns

local floor, min = math.floor, math.min

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

-- true only for a readable true (comparing secret values would throw)
local function isTrue(v)
  return not isSecret(v) and v == true
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

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c
end

local function callAll(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  table.remove(r, 1)
  return r
end

local function playerLevel()
  return num(call(UnitLevel, "player"))
end

local LEARN_WAIT = 0.6      -- seconds: event and message of a learned spell arrive together
local READY_DELAY = 3       -- seconds after start: baseline of talents, professions and reputation
local DEBOUNCE = 0.5        -- seconds: batched queries after events
local TALENT_DEBOUNCE = 1.0
local STATS_DELAY = 1.5     -- seconds after level-up
local MOUNT_DEDUPE = 5      -- seconds: message and event of the same mount
local WORLD_SETTLE = 5      -- seconds after login/loading screen: learn events without a message are noise (snapshot only)
local MAX_NODES = 400       -- talent nodes per tree
local MAX_FACTIONS = 200
local MAX_TA_LINES = 40     -- lines per talent query
local PROF_STEP = 75        -- profession levels in a moment: multiples of 75

-- learning messages: GlobalString -> kind
local LEARN = {
  { "ERR_LEARN_SPELL_S", "spell" }, { "ERR_LEARN_ABILITY_S", "ability" }, { "ERR_LEARN_PASSIVE_S", "passive" },
  { "ERR_LEARN_RECIPE_S", "recipe" }, { "ERR_LEARN_MOUNT_S", "mount" }, { "ERR_LEARN_COMPANION_S", "companion" },
}
-- reputation messages (faction, change); order does not matter, the patterns are unambiguous
local REP = {
  { "FACTION_STANDING_INCREASED", 1 }, { "FACTION_STANDING_DECREASED", -1 },
  { "FACTION_STANDING_INCREASED_BONUS", 1 }, { "FACTION_STANDING_INCREASED_ACH_BONUS", 1 },
  { "FACTION_STANDING_INCREASED_GENERIC", 1, true }, { "FACTION_STANDING_DECREASED_GENERIC", -1, true },
}

local Character = {
  requires = { "UnitLevel" },
  events = {
    "LEARNED_SPELL_IN_SKILL_LINE", "NEW_MOUNT_ADDED", "CHAT_MSG_SYSTEM", "CHAT_MSG_SKILL", "SKILL_LINES_CHANGED",
    "CHAT_MSG_COMBAT_FACTION_CHANGE", "UPDATE_FACTION", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE",
    "CHARACTER_POINTS_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD",
  },
  signals = { "FC_LOOT" },
}
local handlers = {}

function Character:init()
  self.ready = false
  self.learnEvents, self.learnMsgs, self.learnTimer, self.eventSeen = {}, {}, false, false
  self.mountIDs = {}
  self.spellSeen = {} -- spellID -> true: seen this session (in case the snapshot is full)
  self.worldAt = GetTime()
  self.skills, self.otherSkills = {}, {}
  self.standing, self.repQueue = {}, {}
  self.talentBase, self.nodeKnown = nil, {}
  self.statsLevel = nil
  local st = Store.char() and Store.char().snapshots and Store.char().snapshots.state
  local t = type(st) == "table" and st.talents or nil
  if type(t) == "table" then
    self.talentBase = {}
    for k, v in pairs(t) do
      if type(k) == "number" and type(v) == "number" then self.talentBase[k] = v end
    end
  end
  Core.after(self, READY_DELAY, function(s)
    s.ready = true
    s.skills = s.scanProfessions() or {}
    s.scanReputation(s, true)
    s.readTalents(s)
    s.statsSnapshot(s, nil) -- first start: stats of the current level (later calls do not write again)
  end)
end

local function debounce(self, key, sec, fn)
  if self[key] then return end
  self[key] = true
  if not Core.after(self, sec, function(s)
    s[key] = false
    fn(s)
  end) then
    self[key] = false
  end
end

-- Spells and ranks

local function spellName(spellID)
  local C = C_Spell
  if type(C) == "table" and not isSecret(C) then return str(call(C.GetSpellName, spellID)) end
  return str(call(GetSpellInfo, spellID))
end

local function spellRank(spellID)
  local C = C_Spell
  if type(C) == "table" and not isSecret(C) then return str(call(C.GetSpellSubtext, spellID)) end
  return nil
end

local function mountMoment(self, id, name)
  if self.mountAt and GetTime() - self.mountAt <= MOUNT_DEDUPE then return end
  self.mountAt = GetTime()
  Core.emit("FC_MOMENT", "mount", id or name, name, "item", false)
end

-- spell already known? snapshots.spells (earlier sessions) or this session.
local function spellKnown(self, spellID)
  if self.spellSeen[spellID] then return true end
  local char = Store.char()
  local snaps = char and char.snapshots
  local group = type(snaps) == "table" and snaps.spells or nil
  return type(group) == "table" and group[spellID] ~= nil
end

local function learnFlush(self)
  self.learnTimer = false
  local events, msgs = self.learnEvents, self.learnMsgs
  self.learnEvents, self.learnMsgs = {}, {}
  local used = {}
  local mapID = ns.Zone.here()
  for _, ev in ipairs(events) do
    local name = spellName(ev.spellID)
    local kind
    for i, m in ipairs(msgs) do
      if not used[i] and name and m.name == name then
        used[i], kind = true, m.kind
        break
      end
    end
    if not kind and not name then -- name unreadable: assign messages in order
      for i, m in ipairs(msgs) do
        if not used[i] then
          used[i], kind = true, m.kind
          break
        end
      end
    end
    if not spellKnown(self, ev.spellID) then
      local noise = kind == nil and ev.at - (self.worldAt or 0) <= WORLD_SETTLE -- login/loading screen without a message
      if not noise then Store.append("SP", ev.spellID, kind, playerLevel(), mapID) end
      Store.putSnapshot("spells", ev.spellID, { name = name, rank = spellRank(ev.spellID) })
      self.spellSeen[ev.spellID] = true
      local mountID = call(C_MountJournal and C_MountJournal.GetMountFromSpell, ev.spellID)
      if not noise and (kind == "mount" or num(mountID)) then mountMoment(self, num(mountID) or ev.spellID, name) end
    end
  end
  for i, m in ipairs(msgs) do
    if not used[i] then
      if not self.eventSeen then Store.append("SP", nil, m.kind, playerLevel(), mapID, m.name) end
      if m.kind == "mount" then mountMoment(self, nil, m.name) end
    end
  end
  local mounts = self.mountIDs
  self.mountIDs = {}
  for _, id in ipairs(mounts) do mountMoment(self, id, nil) end -- mount without spell event and without message
end

local function queueLearn(self)
  debounce(self, "learnTimer", LEARN_WAIT, learnFlush)
end

handlers.LEARNED_SPELL_IN_SKILL_LINE = function(self, spellID)
  spellID = num(spellID)
  if not spellID then return end
  self.eventSeen = true
  self.learnEvents[#self.learnEvents + 1] = { spellID = floor(spellID), at = GetTime() }
  queueLearn(self)
end

handlers.PLAYER_ENTERING_WORLD = function(self)
  self.worldAt = GetTime()
end

handlers.NEW_MOUNT_ADDED = function(self, mountID)
  mountID = num(mountID)
  if not mountID then return end
  self.mountIDs[#self.mountIDs + 1] = floor(mountID)
  queueLearn(self) -- waits briefly for spell event and message so the name is included
end

-- Professions and skills

function Character.scanProfessions()
  if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return nil end
  local idx = callAll(GetProfessions)
  if not idx then return nil end
  local out = {}
  for i = 1, 6 do
    local v = num(idx[i])
    if v then
      local info = callAll(GetProfessionInfo, v)
      local name = info and str(info[1])
      if name then out[name] = { rank = num(info[3]), max = num(info[4]), line = num(info[7]) } end
    end
  end
  return out
end

local function professionMoment(name, rank, prev)
  if not rank then return end
  if prev == nil or floor(rank / PROF_STEP) > floor((prev or 0) / PROF_STEP) then
    Core.emit("FC_MOMENT", "profession", name, floor(rank), nil, false)
  end
end

local function skillDiff(self)
  local now = Character.scanProfessions()
  if not now then return end
  for name, info in pairs(now) do
    local old = self.skills[name]
    local rank = info.rank
    if rank and (old == nil or (old.rank or 0) < rank) then
      Store.append("SK", name, floor(rank), info.max and floor(info.max) or nil, info.line and floor(info.line) or nil,
        playerLevel(), old == nil and "new" or "up")
      if info.line then Store.putSnapshot("skills", floor(info.line), { name = name }) end
      professionMoment(name, rank, old and old.rank or nil)
    end
    self.skills[name] = info
  end
  for name in pairs(self.skills) do
    if now[name] == nil then self.skills[name] = nil end -- profession unlearned
  end
end

handlers.SKILL_LINES_CHANGED = function(self)
  if not self.ready then return end
  debounce(self, "skillTimer", DEBOUNCE, skillDiff)
end

local function onSkillMessage(self, text)
  local name, rank = Patterns.match("ERR_SKILL_UP_SI", text)
  if not name then name, rank = Patterns.match("SKILL_RANK_UP", text) end
  if name and num(rank) then
    if self.skills[name] then
      handlers.SKILL_LINES_CHANGED(self) -- profession: the value comes from GetProfessions
      return true
    end
    local known = self.otherSkills[name]
    if known == nil or rank > known then
      Store.append("SK", name, floor(rank), nil, nil, playerLevel(), "up")
      self.otherSkills[name] = floor(rank)
    end
    return true
  end
  local gained = Patterns.match("ERR_SKILL_GAINED_S", text)
  if gained then
    if type(GetProfessions) == "function" then
      handlers.SKILL_LINES_CHANGED(self) -- professions come from GetProfessions, else the entry would be doubled
    else
      Store.append("SK", gained, nil, nil, nil, playerLevel(), "new")
    end
    return true
  end
  return false
end

-- Reputation

-- factions from C_Reputation: id -> { name, reaction }, nil if the API is missing
local function readFactions()
  local R = C_Reputation
  if type(R) ~= "table" or isSecret(R) then return nil end
  local n = num(call(R.GetNumFactions))
  if not n then return nil end
  local out = {}
  for i = 1, min(floor(n), MAX_FACTIONS) do
    local d = tbl(call(R.GetFactionDataByIndex, i))
    local id = d and num(d.factionID)
    local name = d and str(d.name)
    if id and id > 0 and name then
      out[floor(id)] = { name = name, reaction = num(d.reaction) and floor(d.reaction) or nil }
    end
  end
  return out
end

local function idByName(factions, name)
  for id, f in pairs(factions) do
    if f.name == name then return id, f end
  end
  return nil
end

function Character.scanReputation(self, silent)
  local now = readFactions()
  if not now then
    self.repOk = false
    return nil
  end
  self.repOk = true
  local mapID = ns.Zone.here()
  local level = playerLevel()
  local queue = self.repQueue
  self.repQueue = {}
  local wroteRT = {}
  if not silent then
    -- Tier change
    for id, f in pairs(now) do
      local old = self.standing[id]
      if old and f.reaction and f.reaction ~= old then
        local standingName
        for _, q in ipairs(queue) do
          if q.kind == "standing" and q.faction == f.name then standingName = q.text end
        end
        Store.append("RT", f.name, id, f.reaction, old, standingName, level)
        wroteRT[f.name] = true
        if f.reaction > old then Core.emit("FC_MOMENT", "reputation", id, f.reaction, nil, false) end
      end
    end
  end
  for id, f in pairs(now) do
    if f.reaction then self.standing[id] = f.reaction end
    Store.putSnapshot("factions", id, { name = f.name })
  end
  if not silent then
    for _, q in ipairs(queue) do
      if q.kind == "delta" then
        local id, f = idByName(now, q.faction)
        Store.append("RP", q.faction, id, q.delta, f and f.reaction, level, mapID)
      elseif q.kind == "standing" and not wroteRT[q.faction] then
        local id = idByName(now, q.faction)
        Store.append("RT", q.faction, id, nil, nil, q.text, level)
      end
    end
  end
  return now
end

local function repMessage(self, text)
  if isSecret(text) or type(text) ~= "string" then return false end
  for i = 1, #REP do
    local def = REP[i]
    local matcher = Patterns.compile(def[1])
    if matcher then
      local faction, delta = matcher(text)
      if str(faction) then
        local d = num(delta)
        self.repQueue[#self.repQueue + 1] = { kind = "delta", faction = faction, delta = (not def[3] and d) and floor(d) * def[2] or nil }
        return true
      end
    end
  end
  local standingText, faction = Patterns.match("FACTION_STANDING_CHANGED", text)
  if str(faction) then
    self.repQueue[#self.repQueue + 1] = { kind = "standing", faction = faction, text = standingText }
    return true
  end
  return false
end

local function repFlush(self)
  if not self.ready then return end
  if Character.scanReputation(self, false) == nil then
    -- C_Reputation missing: write the messages alone
    local queue = self.repQueue
    self.repQueue = {}
    local mapID = ns.Zone.here()
    for _, q in ipairs(queue) do
      if q.kind == "delta" then
        Store.append("RP", q.faction, nil, q.delta, nil, playerLevel(), mapID)
      else
        Store.append("RT", q.faction, nil, nil, nil, q.text, playerLevel())
      end
    end
  end
end

handlers.CHAT_MSG_COMBAT_FACTION_CHANGE = function(self, text)
  if repMessage(self, text) then debounce(self, "repTimer", DEBOUNCE, repFlush) end
end

handlers.UPDATE_FACTION = function(self)
  if self.ready and #self.repQueue > 0 then debounce(self, "repTimer", DEBOUNCE, repFlush) end
end

-- Messages (system, skills)

local function onSystemMessage(self, text)
  if isSecret(text) or type(text) ~= "string" then return end
  if onSkillMessage(self, text) then return end
  if repMessage(self, text) then
    debounce(self, "repTimer", DEBOUNCE, repFlush)
    return
  end
  for i = 1, #LEARN do
    local name = Patterns.match(LEARN[i][1], text)
    if str(name) then
      -- hunter pet ability taught by the pet trainer: the spell link names it (Trainer.noteLearned ignores every other id)
      local linkID = tonumber(string.match(name, "|Hspell:(%d+)"))
      if linkID and ns.Trainer and type(ns.Trainer.noteLearned) == "function" then pcall(ns.Trainer.noteLearned, linkID) end
      self.learnMsgs[#self.learnMsgs + 1] = { name = name, kind = LEARN[i][2] }
      queueLearn(self)
      return
    end
  end
end
handlers.CHAT_MSG_SYSTEM = onSystemMessage
handlers.CHAT_MSG_SKILL = onSystemMessage

-- Talents

local function nodeMeta(configID, nodeID, info, treeKnown)
  local entry = tbl(info.entryIDs) and num(info.entryIDs[1]) or nil
  local spellID
  if entry then
    local ei = tbl(call(C_Traits.GetEntryInfo, configID, entry))
    local defID = ei and num(ei.definitionID)
    local di = defID and tbl(call(C_Traits.GetDefinitionInfo, defID))
    spellID = di and num(di.spellID) or nil
  end
  return { x = num(info.posX), y = num(info.posY), spellID = spellID, maxRanks = num(info.maxRanks) }
end

-- current talents: ranks[nodeID] = rank (only > 0), spent, unspent. nil if unreadable.
local function talentApiPresent()
  local CT, T = C_ClassTalents, C_Traits
  return type(CT) == "table" and not isSecret(CT) and type(CT.GetActiveConfigID) == "function"
    and type(T) == "table" and not isSecret(T) and type(T.GetConfigInfo) == "function"
end

local function talentState(self)
  local CT, T = C_ClassTalents, C_Traits
  if type(CT) ~= "table" or isSecret(CT) or type(T) ~= "table" or isSecret(T) then return nil end
  local configID = num(call(CT.GetActiveConfigID))
  if not configID then return nil end
  local cfg = tbl(call(T.GetConfigInfo, configID))
  local trees = cfg and tbl(cfg.treeIDs)
  if not trees then return nil end
  local ranks, spent, unspent, seen = {}, 0, nil, 0
  for ti = 1, 4 do
    local treeID = num(trees[ti])
    if not treeID then break end
    local nodes = tbl(call(T.GetTreeNodes, treeID))
    if nodes then
      for ni = 1, MAX_NODES do
        local nodeID = num(nodes[ni])
        if not nodeID then break end
        local info = tbl(call(T.GetNodeInfo, configID, nodeID))
        if info then
          seen = seen + 1
          local r = num(info.ranksPurchased) or num(info.currentRank) or 0
          if r > 0 then
            nodeID = floor(nodeID)
            ranks[nodeID] = floor(r)
            spent = spent + floor(r)
            if not self.nodeKnown[nodeID] then
              self.nodeKnown[nodeID] = true
              Store.putSnapshot("talentNodes", nodeID, nodeMeta(configID, nodeID, info))
            end
          end
        end
      end
    end
    local cur = tbl(call(T.GetTreeCurrencyInfo, configID, treeID, false))
    local c1 = cur and tbl(cur[1])
    if c1 and num(c1.quantity) and unspent == nil then unspent = floor(c1.quantity) end
  end
  if seen == 0 then return nil end
  return ranks, spent, unspent
end

function Character.readTalents(self)
  local ranks, spent, unspent = talentState(self)
  if not ranks then
    -- API present but (still) without config or nodes, e.g. level 1 without a talent tree: the baseline is 'nothing learned', so the first
    -- talent points later get a TA line instead of being swallowed as baseline.
    if self.talentBase == nil and talentApiPresent() then
      self.talentBase = {}
      Store.putSnapshot("state", "talents", Character.talentSnapshot({}), true)
    end
    return
  end
  local base = self.talentBase
  if base == nil then
    self.talentBase = ranks -- first start (or first readable query): only remember the state
    Store.putSnapshot("state", "talents", Character.talentSnapshot(ranks), true)
    return
  end
  local changed = {}
  for id, r in pairs(ranks) do
    if (base[id] or 0) ~= r then changed[#changed + 1] = id end
  end
  for id, r in pairs(base) do
    if ranks[id] == nil and r ~= 0 then changed[#changed + 1] = id end
  end
  table.sort(changed)
  local level = playerLevel()
  for i = 1, min(#changed, MAX_TA_LINES) do
    local id = changed[i]
    Store.append("TA", id, ranks[id] or 0, spent, unspent, level)
  end
  if #changed > 0 and spent > 0 then Store.putSnapshot("talents", spent, ranks, true) end
  self.talentBase = ranks
  Store.putSnapshot("state", "talents", Character.talentSnapshot(ranks), true)
end

function Character.talentSnapshot(ranks)
  local out = { ok = 1 }
  for id, r in pairs(ranks) do out[id] = r end
  return out
end

local function talentEvent(self)
  if not self.ready then return end
  debounce(self, "talentTimer", TALENT_DEBOUNCE, function(s) Character.readTalents(s) end)
end
handlers.TRAIT_CONFIG_UPDATED = talentEvent
handlers.PLAYER_TALENT_UPDATE = talentEvent
handlers.CHARACTER_POINTS_CHANGED = talentEvent

-- Stats per level

local function second(fn, ...)
  local r = callAll(fn, ...)
  return r and num(r[2]) or nil
end

local function first(fn, ...)
  local r = callAll(fn, ...)
  return r and num(r[1]) or nil
end

-- B9: free slots in the bags (backpack and bags 1-4); nil if the API is missing or nothing was readable
local BAG_LAST = 4
local function freeBagSlots()
  local C = C_Container
  if type(C) ~= "table" or isSecret(C) then return nil end
  local sum, read = 0, false
  for bag = 0, BAG_LAST do
    local n = num(call(C.GetContainerNumFreeSlots, bag))
    if n and n >= 0 then
      sum = sum + floor(n)
      read = true
    end
  end
  return read and sum or nil
end

-- B9: ammunition in the ammo slot (inventory slot 0); only for classes that use ammo (UnitUsesAmmo exists on Forever only)
local function ammoCount()
  if not isTrue(call(UnitUsesAmmo, "player")) then return nil end
  return num(call(GetInventoryItemCount, "player", 0))
end

function Character.statsSnapshot(self, level)
  level = num(level) or playerLevel()
  if not level then return end
  level = floor(level)
  if isTrue(call(InCombatLockdown)) then
    self.statsLevel = level
    return
  end
  self.statsLevel = nil
  local v = {}
  v.str, v.agi, v.sta = second(UnitStat, "player", 1), second(UnitStat, "player", 2), second(UnitStat, "player", 3)
  v.int, v.spi = second(UnitStat, "player", 4), second(UnitStat, "player", 5)
  v.armor = second(UnitArmor, "player")
  v.health, v.power = first(UnitHealthMax, "player"), first(UnitPowerMax, "player")
  v.crit, v.spellCrit = first(GetCritChance), first(GetSpellCritChance, 2)
  v.dodge, v.parry, v.block = first(GetDodgeChance), first(GetParryChance), first(GetBlockChance)
  local ap = callAll(UnitAttackPower, "player")
  if ap then
    local a, b, c = num(ap[1]), num(ap[2]), num(ap[3])
    if a then v.attackPower = a + (b or 0) + (c or 0) end
  end
  v.spellPower, v.healing = first(GetSpellBonusDamage, 2), first(GetSpellBonusHealing)
  v.bagFree, v.ammo = freeBagSlots(), ammoCount()
  v.defense = first(UnitDefenseSkill, "player") -- B10 (Forever only)
  if next(v) then Store.putSnapshot("stats", level, v) end
end

handlers.PLAYER_LEVEL_UP = function(self, level)
  Core.after(self, STATS_DELAY, function(s) Character.statsSnapshot(s, level) end)
end

handlers.PLAYER_REGEN_ENABLED = function(self)
  if self.statsLevel then Character.statsSnapshot(self, self.statsLevel) end
end

-- gather counters from finds: ore and herbs from objects, leather from enemies (approximation: item class trade goods)

local TRADE_GOODS, SUB_LEATHER, SUB_ORE, SUB_HERB = 7, 6, 7, 9

handlers.FC_LOOT = function(self, itemID, count, quality, source)
  if source ~= "object" and source ~= "mob" then return end
  local r = callAll(C_Item and C_Item.GetItemInfoInstant, itemID)
  if not r or num(r[6]) ~= TRADE_GOODS then return end
  local sub = num(r[7])
  local kind
  if source == "object" and sub == SUB_ORE then
    kind = "ore"
  elseif source == "object" and sub == SUB_HERB then
    kind = "herb"
  elseif source == "mob" and sub == SUB_LEATHER then
    kind = "leather"
  end
  if kind then Store.count("gather", kind, num(count) or 1) end
end

handlers.PLAYER_LOGOUT = function(self)
  if self.ready and self.talentBase then
    Store.putSnapshot("state", "talents", Character.talentSnapshot(self.talentBase), true)
  end
end

function Character:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("Character", Character)
