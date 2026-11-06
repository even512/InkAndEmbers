-- Collector 'Quests': life story (accepted, turned in, abandoned) and full archive of the texts.
-- Log lines carry only IDs (questID, npcID, itemID). Titles and texts are stored once in chars[guid].quests[questID] (Store.putText, each field once,
-- timestamped), NPC names in npcs[npcID]. No item links.
local _, ns = ...
local Core, Store = ns.Core, ns.Store

local floor, abs = math.floor, math.abs
local match, gsub = string.match, string.gsub

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

-- value for a log line: numbers and secret values ('?') stay, everything else is dropped
local function keep(v)
  if isSecret(v) or type(v) == "number" then return v end
  return nil
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if not ok then return nil end
  return a, b
end

-- like call, but with all return values (GetQuestItemInfo returns six)
local function callAll(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  return unpack(r, 2, 7)
end

local REMOVE_WINDOW = 1.5   -- seconds: QUEST_REMOVED waits this long for a QUEST_TURNED_IN (order is not guaranteed)
local TURNED_TTL = 15       -- seconds: a removal this close to a turn-in is no abandon
local CHOICE_TTL = 60       -- seconds: the chosen item is valid only briefly for the next turn-in
local NPC_TTL = 900         -- seconds: quest giver from the dialog (QUEST_DETAIL/COMPLETE) stays valid this long
local MAX_CACHE = 60
local REWARD_MAX = 10       -- reward items per kind (choice/fixed) that go into the text archive
-- quest objective progress (QO)
local QO_DELAY = 0.5        -- seconds: quest log events are batched this long, then one comparison
local QO_QUIET = 5          -- seconds after start (login/reload): comparisons only fill the cache
local QO_GOAL_MAX = 100     -- at most this many QO lines per objective (besides the 'need' limit)
local QO_OBJ_MAX = 20       -- objectives read per quest
local QO_LOG_MAX = 200      -- quest log entries (incl. headers) one comparison walks through
local QO_PENDING_MAX = 40   -- pending questIDs (QUEST_WATCH_UPDATE) per comparison
local QO_TEXT_MAX = 80      -- bytes of the objective name
local QO_KIND_MAX = 20      -- bytes of the objective kind

local function playerLevel()
  return num(call(UnitLevel, "player"))
end

local function here()
  if ns.Zone then return ns.Zone.here() end
  return nil
end

local function charQuests()
  local char = Store.char()
  return char and char.quests or nil
end

-- itemID from an item link (only the ID, the link itself is never stored)
local function itemIdOf(link)
  if not str(link) then return nil end
  local id = match(link, "|Hitem:(%d+)")
  return id and tonumber(id) or nil
end

-- npcID from a creature/vehicle GUID; other GUIDs (object, item) have none
local function npcIdOf(guid)
  if not str(guid) then return nil end
  local kind, id = match(guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if (kind == "Creature" or kind == "Vehicle") and id then return tonumber(id) end
  return nil
end

-- conversation partner 'npc': npcID and name; the name goes into npcs[npcID].
local function readNpc()
  local id = npcIdOf(call(UnitGUID, "npc"))
  local name = str(call(UnitName, "npc"))
  if id and name then Store.putText("npcs", id, name) end
  return id, name
end

local function questIdFromFrame()
  local id = num(call(GetQuestID))
  if id and id > 0 then return floor(id) end
  return nil
end

local function questTitle(questID)
  return str(call(C_QuestLog and C_QuestLog.GetTitleForQuestID, questID))
end

-- quest level: stored value first (survives reloads), then the quest log by questID, then the difficulty level.
local function questLevel(questID)
  local quests = charQuests()
  local entry = quests and quests[questID]
  if type(entry) == "table" and num(entry.qlevel) then return entry.qlevel end
  local lvl
  if type(C_QuestLog) == "table" then
    local idx = num(call(C_QuestLog.GetLogIndexForQuestID, questID))
    if idx and idx > 0 then
      local info = call(C_QuestLog.GetInfo, idx)
      if type(info) == "table" and not isSecret(info) then lvl = num(info.level) end
    end
    lvl = lvl or num(call(C_QuestLog.GetQuestDifficultyLevel, questID))
  end
  if lvl and lvl > 0 then return floor(lvl) end
  return nil
end

-- quest chain: quest line (ID, name) and the quest's position in it, as far as C_QuestLine is readable. Once per quest
-- in quests[questID] (questLine, questLineName, questLinePos, questLineLen); anything missing stays empty.
local function questLineOf(questID, mapID)
  local QL = C_QuestLine
  if type(QL) ~= "table" or isSecret(QL) then return nil end
  local info = mapID and call(QL.GetQuestLineInfo, questID, mapID) or nil
  if type(info) ~= "table" or isSecret(info) then info = call(QL.GetQuestLineInfo, questID) end
  if type(info) ~= "table" or isSecret(info) then return nil end
  local id = num(info.questLineID)
  if not id or id <= 0 then return nil end
  id = floor(id)
  local out = { questLine = id, questLineName = str(info.questLineName) }
  local list = call(QL.GetQuestLineQuests, id)
  if type(list) == "table" and not isSecret(list) then
    local n = 0
    for i = 1, 200 do
      local q = list[i]
      if not isSecret(q) and q == nil then break end
      n = i
      if num(q) == questID then out.questLinePos = i end -- secret entries count but never match
    end
    if n > 0 then out.questLineLen = n end
  end
  return out
end

local function noteQuestLine(questID, mapID)
  local quests = charQuests()
  local entry = quests and quests[questID]
  if type(entry) == "table" and entry.questLine ~= nil then return end
  local ql = questLineOf(questID, mapID)
  if ql then Store.putText("quests", questID, ql) end
end

-- name only goes into the line if there is no npcID (object, item as quest giver)
local function nameIfNoId(id, name)
  if id then return nil end
  return name
end

-- bound the cache: the oldest entries (smallest .at) are dropped, not all.
local function trimCache(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  while n > MAX_CACHE do
    local oldestKey, oldestAt
    for k, v in pairs(t) do
      local at = type(v) == "table" and tonumber(v.at) or 0
      if oldestAt == nil or at < oldestAt then oldestKey, oldestAt = k, at end
    end
    if oldestKey == nil then break end
    t[oldestKey] = nil
    n = n - 1
  end
end


local Quests = {
  requires = { "UnitLevel" },
  events = {
    "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
    "PLAYER_LOGOUT", "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "QUEST_FINISHED",
  },
  unitEvents = { UNIT_QUEST_LOG_CHANGED = { "player" } },
  signals = { "FC_LOOT" },
}
local handlers = {}

-- abandon detection via button: SetAbandonQuest remembers the quest, AbandonQuest executes.
-- questID of the quest to abandon: GetAbandonQuest, else (older global path) via the quest log index.
local function abandonId()
  if type(C_QuestLog) == "table" then
    local id = num(call(C_QuestLog.GetAbandonQuest))
    if id and id > 0 then return floor(id) end
    local idx = num(call(GetQuestLogSelection))
    if idx and idx > 0 then
      id = num(call(C_QuestLog.GetQuestIDForLogIndex, floor(idx)))
      if id and id > 0 then return floor(id) end
    end
  end
  return nil
end

-- chosen item known: straight into a fresh turn-in without item (own QR line), else kept for the coming QUEST_TURNED_IN
local function assignChoice(self, questID, itemID)
  local rec = self.turned[questID]
  if rec and GetTime() - rec.at < TURNED_TTL then
    if rec.item ~= nil then return end -- already assigned (hook and loot message for the same turn-in)
    rec.item = itemID
    Store.append("QR", questID, itemID) -- QUEST_TURNED_IN was faster than the hook
    self.completing, self.choiceItems = nil, {}
    self.awaiting[questID] = nil
  else
    self.choice = { questID = questID, itemID = itemID, at = GetTime() }
  end
end

function Quests:init()
  self.givers = {}      -- questID -> { id, name, at } from QUEST_DETAIL
  self.turnNpc = {}     -- questID -> { id, name, at } from QUEST_PROGRESS/QUEST_COMPLETE
  self.choiceItems = {} -- index -> itemID of the choice items of the open turn-in window
  self.turned = {}
  self.removed = {}     -- questID -> time of QUEST_REMOVED while the decision is pending
  self.tasks = {}       -- questID -> { at }: task quests (world quests, bonus objectives) seen at QUEST_ACCEPTED
  self.awaiting = {}    -- questID -> { items = { [itemID] = true }, at, turnedAt, closedAt }: turn-ins with a choice, until the item is known
  self.completing = nil -- { questID, at } from QUEST_COMPLETE, kept until the choice item is assigned (or CHOICE_TTL)
  self.choice = nil
  self.abandonSel, self.abandonReq = nil, nil
  self.obj = {}         -- questID -> { at, have = { [idx] = number }, logged = { [idx] = lines } } (QO cache)
  self.objPending = {}  -- questIDs from QUEST_WATCH_UPDATE for the next comparison
  self.objTimer = false
  self.objQuietUntil = GetTime() + QO_QUIET

  local onSet = function(s) s.abandonSel = abandonId() end
  local onAbandon = function(s)
    local id = abandonId() or s.abandonSel
    s.abandonReq = { questID = id, at = GetTime() }
  end
  if type(C_QuestLog) == "table" then
    Core.hook(self, C_QuestLog, "SetAbandonQuest", onSet)
    Core.hook(self, C_QuestLog, "AbandonQuest", onAbandon)
  end
  Core.hook(self, "AbandonQuest", onAbandon) -- older global API, if present
  -- Only catches callers of the global: quest UI replacements (DialogueUI) keep their own local copy of GetQuestReward
  -- from before our hook, then the chosen item arrives via FC_LOOT (see there).
  Core.hook(self, "GetQuestReward", function(s, idx)
    idx = num(idx)
    if not idx or idx < 1 then return end -- no choice
    idx = floor(idx)
    local itemID = s.choiceItems[idx] or itemIdOf(call(GetQuestItemLink, "choice", idx))
    if not itemID then return end
    -- nothing is stored without a known questID (no guessing)
    local comp = s.completing
    local questID = comp and GetTime() - comp.at < CHOICE_TTL and comp.questID or questIdFromFrame()
    if not questID then return end
    assignChoice(s, questID, itemID)
  end)
end

-- rewards in full: all items of one kind ('choice' = pick, 'reward' = fixed) from the open turn-in window as
-- a list { { id = itemID, n = count|nil }, ... } (at most REWARD_MAX); name and quality go into snapshots.items.
-- Secret or missing values are dropped; no entry without a readable itemID (no guessing).
local function rewardList(kind, n)
  n = num(n)
  if not n or n < 1 then return nil end
  local out = {}
  for i = 1, math.min(floor(n), REWARD_MAX) do
    local name, _, count, quality, _, infoID = callAll(GetQuestItemInfo, kind, i)
    local id = itemIdOf(call(GetQuestItemLink, kind, i)) or num(infoID)
    if id and id > 0 and id == floor(id) then
      count = num(count)
      out[#out + 1] = { id = id, n = (count and count > 1) and floor(count) or nil }
      Store.noteItem(id, str(name), num(quality))
    end
  end
  return #out > 0 and out or nil
end

-- Dialog and text archive

handlers.QUEST_DETAIL = function(self)
  local questID = questIdFromFrame()
  if not questID then
    Store.count("quests", "ohne ID")
    return
  end
  local id, name = readNpc()
  self.givers[questID] = { id = id, name = name, at = GetTime() }
  trimCache(self.givers)
  local mapID = here()
  Store.putText("quests", questID, {
    title = str(call(GetTitleText)),
    detail = str(call(GetQuestText)),
    objectives = str(call(GetObjectiveText)),
    giver = name,
    giverNpc = id,
    mapID = mapID,
    qlevel = questLevel(questID),
  })
  noteQuestLine(questID, mapID)
end

handlers.QUEST_PROGRESS = function(self)
  local questID = questIdFromFrame()
  if not questID then
    Store.count("quests", "ohne ID")
    return
  end
  local id, name = readNpc()
  self.turnNpc[questID] = { id = id, name = name, at = GetTime() }
  trimCache(self.turnNpc)
  Store.putText("quests", questID, { title = str(call(GetTitleText)), progress = str(call(GetProgressText)) })
end

handlers.QUEST_COMPLETE = function(self)
  local questID = questIdFromFrame()
  if not questID then
    Store.count("quests", "ohne ID")
    return
  end
  local id, name = readNpc()
  self.turnNpc[questID] = { id = id, name = name, at = GetTime() }
  trimCache(self.turnNpc)
  self.completing = { questID = questID, at = GetTime() }
  -- remember choice items: the hook on GetQuestReward runs after the original, when the links may be gone
  self.choiceItems = {}
  local n = num(call(GetNumQuestChoices)) or 0
  local set, any = {}, false
  for i = 1, floor(n) do
    self.choiceItems[i] = itemIdOf(call(GetQuestItemLink, "choice", i))
    if self.choiceItems[i] then set[self.choiceItems[i]], any = true, true end
  end
  self.awaiting[questID] = any and { items = set, at = GetTime() } or nil
  trimCache(self.awaiting)
  Store.putText("quests", questID, {
    title = str(call(GetTitleText)),
    reward = str(call(GetRewardText)),
    rewardMoney = num(call(GetRewardMoney)),
    choices = floor(n),
    rewardChoices = rewardList("choice", n),
    rewardItems = rewardList("reward", call(GetNumQuestRewards)),
  })
end

-- Quest objective progress (QO) and quest log category

-- boolean only if readable (secret counts as unset)
local function flag(v)
  return not isSecret(v) and v == true
end

-- info table of a quest log entry (nil if unreadable or secret)
local function logInfo(i)
  local info = call(C_QuestLog and C_QuestLog.GetInfo, i)
  if type(info) ~= "table" or isSecret(info) then return nil end
  return info
end

-- header above the quest in the quest log: walk backwards from the quest's entry to the first header. nil if none.
local function questCategory(questID)
  if type(C_QuestLog) ~= "table" then return nil end
  local idx = num(call(C_QuestLog.GetLogIndexForQuestID, questID))
  if not idx or idx <= 1 then return nil end
  idx = floor(idx)
  for i = idx - 1, math.max(1, idx - QO_LOG_MAX), -1 do
    local info = logInfo(i)
    if info and flag(info.isHeader) then return str(info.title) end
  end
  return nil
end

-- objective name without counter ('Wolf Pelt: 3/10', '3/10 Wolf Pelt', 'Progress (45%)'), sanitized, at most QO_TEXT_MAX bytes.
local function goalText(v)
  local s = str(v)
  if not s then return nil end
  s = ns.Sanitize.field(s)
  s = gsub(s, "^%d+%s*/%s*%d+%s+", "")
  s = gsub(s, "%s*:%s*%d+%s*/%s*%d+$", "")
  s = gsub(s, "%s*%(%d+%s*/%s*%d+%)$", "")
  s = gsub(s, "%s*%(%d+%%%)$", "")
  s = gsub(ns.Sanitize.cut(s, QO_TEXT_MAX), " +$", "")
  if s == "" then return nil end
  return s
end

-- objective kind (monster, item, object, event, reputation, log, progressbar, ...): letters and '_' only
local function goalKind(v)
  local s = str(v)
  if not s or not match(s, "^[%a_]+$") then return nil end
  return string.sub(s, 1, QO_KIND_MAX)
end

-- have/need of an objective; progress bars as percent (need = 100). nil if unreadable or secret.
local function goalCounts(questID, o)
  local have, need
  if goalKind(o.type) == "progressbar" then
    have, need = num(call(GetQuestProgressBarPercent, questID)), 100
  else
    have, need = num(o.numFulfilled), num(o.numRequired)
  end
  if not have or have < 0 then return nil end
  have = floor(have)
  need = (need and need >= 0) and floor(need) or nil
  return have, need
end

-- cache per quest: have[idx] = state of the last line or start value (base), last[idx] = last read { have, need, kind, text },
-- logged[idx] = lines written, done[idx] = final state (have >= need) already written. Reading (readQuest) and writing (emitQuest)
-- are separate, so a read but unwritten step can still be written when the objective list is already empty at turn-in.

-- reads a quest's objectives into last. New quests/objectives and silent = true also set the base (remember only).
-- An objective the client has not loaded yet reads as 0 without count and text ('empty'). Such a read is never a real state:
-- as the base (c.pending) the first loaded state replaces it without a line; if a loaded state exists, the empty read is ignored.
-- returns true if an objective list was readable.
local function readQuest(self, questID, silent)
  local list = call(C_QuestLog and C_QuestLog.GetQuestObjectives, questID)
  if type(list) ~= "table" or isSecret(list) then return false end
  local c = self.obj[questID]
  local fresh = c == nil
  local now = GetTime()
  for i = 1, QO_OBJ_MAX do
    local o = list[i]
    if not isSecret(o) and o == nil then break end
    if type(o) == "table" and not isSecret(o) then
      local have, need = goalCounts(questID, o)
      if have then
        if c == nil then
          c = { have = {}, last = {}, logged = {}, done = {}, pending = {} }
          self.obj[questID] = c
        end
        c.at = now
        local kind, text = goalKind(o.type), goalText(o.text)
        local loaded = kind == "progressbar" or (need ~= nil and need > 0) or text ~= nil
        local prev = c.last[i]
        if loaded or not (prev and prev.loaded) then
          c.last[i] = { have = have, need = need, kind = kind, text = text, loaded = loaded }
          if fresh or silent or c.have[i] == nil or (loaded and c.pending[i]) then c.have[i] = have end
          c.pending[i] = (not loaded) or nil
        end
      end
    end
  end
  return true
end

-- writes a QO line per objective if the last read is above the base (real increase). At most need or QO_GOAL_MAX lines per objective;
-- the final state (have >= need) is always written once.
local function emitQuest(self, questID)
  local c = self.obj[questID]
  if not c then return end
  for i = 1, QO_OBJ_MAX do
    local l, base = c.last[i], c.have[i]
    if l and base ~= nil and l.have ~= base then
      if l.have > base then
        local n = c.logged[i] or 0
        local cap = math.min(math.max(l.need or 1, 1), QO_GOAL_MAX)
        local final = l.need ~= nil and l.need > 0 and l.have >= l.need
        if n < cap or (final and not c.done[i]) then
          c.logged[i] = n + 1
          if final then c.done[i] = true end
          local mapID, px, py = here()
          Store.append("QO", questID, i, l.have, l.need, l.kind, l.text, mapID, px, py)
        else
          Store.count("quests", "QO begrenzt")
        end
      end
      c.have[i] = l.have -- a decrease (item turned in/destroyed) also becomes the new base, without a line
    end
  end
end

local function scanQuest(self, questID, silent)
  readQuest(self, questID, silent)
  emitQuest(self, questID)
end

-- one comparison: all quests in the quest log (without headers and hidden), pending and already known questIDs.
-- Incidentally already archived quests without category get their quest log header (existing entries only).
local function scanAll(self)
  local silent = GetTime() < self.objQuietUntil
  local ids, seen = {}, {}
  local function add(id)
    id = num(id)
    if id and id > 0 then
      id = floor(id)
      if not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  if type(C_QuestLog) == "table" then
    local n = num(call(C_QuestLog.GetNumQuestLogEntries)) or 0
    local quests = charQuests()
    local header
    for i = 1, math.min(floor(n), QO_LOG_MAX) do
      local info = logInfo(i)
      if info then
        if flag(info.isHeader) then
          header = str(info.title)
        elseif not flag(info.isHidden) then
          local id = num(info.questID)
          if id and id > 0 then
            id = floor(id)
            add(id)
            local entry = quests and quests[id]
            if header and type(entry) == "table" and entry.category == nil then
              Store.putText("quests", id, { category = header })
            end
          end
        end
      end
    end
    -- watched quests directly by questID (also under collapsed headers the quest log does not list)
    local w = num(call(C_QuestLog.GetNumQuestWatches)) or 0
    for i = 1, math.min(floor(w), QO_PENDING_MAX) do
      add(call(C_QuestLog.GetQuestIDForQuestWatchIndex, i))
    end
  end
  for id in pairs(self.objPending) do add(id) end
  self.objPending = {}
  for id in pairs(self.obj) do add(id) end
  for _, id in ipairs(ids) do scanQuest(self, id, silent) end
  trimCache(self.obj)
end

-- batch events: one comparison QO_DELAY seconds after the first event.
local function requestScan(self, questID)
  questID = num(questID)
  if questID and questID > 0 then
    local n = 0
    for _ in pairs(self.objPending) do n = n + 1 end
    if n < QO_PENDING_MAX then self.objPending[floor(questID)] = true end
  end
  if self.objTimer then return end
  self.objTimer = true
  if not Core.after(self, QO_DELAY, function(s)
    s.objTimer = false
    scanAll(s)
  end) then
    self.objTimer = false
  end
end

handlers.QUEST_LOG_UPDATE = function(self) requestScan(self) end
-- QUEST_WATCH_UPDATE names the quest: read its state at once (one quest, cheap), written batched.
handlers.QUEST_WATCH_UPDATE = function(self, questID)
  local id = num(questID)
  if id and id > 0 then readQuest(self, floor(id), GetTime() < self.objQuietUntil) end
  requestScan(self, questID)
end
handlers.UNIT_QUEST_LOG_CHANGED = function(self) requestScan(self) end -- 'player' only (unitEvents)

-- turn-in/removal: write a pending increase (from a fresh objective list, else from the last read), then drop the quest from the cache.
-- Nothing is invented without a read.
local function closeObjectives(self, questID)
  if self.obj[questID] then
    readQuest(self, questID, GetTime() < self.objQuietUntil)
    emitQuest(self, questID)
  end
  self.obj[questID] = nil
  self.objPending[questID] = nil
end

-- B7: suggested group size, elite flag, tag name and frequency of a quest, stored once in quests[questID] (group, elite, tag, freq).
-- Forever: C_QuestLog.IsEliteQuest; Retail: C_QuestLog.GetQuestTagInfo (isElite, tagName). Every call under pcall, only readable values
-- of the right type are taken, anything else stays missing.
local TAG_MAX = 40

local function readableBool(v)
  if isSecret(v) or type(v) ~= "boolean" then return nil end
  return v
end

local function questExtras(questID)
  local out = {}
  local C = C_QuestLog
  if type(C) ~= "table" or isSecret(C) then return out end
  local idx = num(call(C.GetLogIndexForQuestID, questID))
  local info = (idx and idx > 0) and logInfo(floor(idx)) or nil
  local group = info and num(info.suggestedGroup) or nil
  if group == nil then group = num(call(C.GetSuggestedGroupSize, questID)) end
  if group ~= nil and group >= 0 then out.group = floor(group) end
  local freq = info and num(info.frequency) or nil
  if freq ~= nil and freq >= 0 then out.freq = floor(freq) end
  local elite = readableBool(call(C.IsEliteQuest, questID))
  local tagInfo = call(C.GetQuestTagInfo, questID)
  if type(tagInfo) == "table" and not isSecret(tagInfo) then
    if elite == nil then elite = readableBool(tagInfo.isElite) end
    local tag = str(tagInfo.tagName)
    if tag then
      tag = gsub(ns.Sanitize.cut(ns.Sanitize.field(tag), TAG_MAX), " +$", "")
      if tag ~= "" then out.tag = tag end
    end
  end
  if elite ~= nil then out.elite = elite end
  return out
end

-- Life story

-- Task quest (Retail: world quest, bonus objective): it leaves the log when the area is left or the timer ends, which is
-- no abandon. Only a readable true counts; missing API or secret = no task.
local function isTaskQuest(questID)
  local C = C_QuestLog
  if type(C) ~= "table" or isSecret(C) then return false end
  return readableBool(call(C.IsQuestTask, questID)) == true or readableBool(call(C.IsWorldQuest, questID)) == true
end

handlers.QUEST_ACCEPTED = function(self, a, b)
  local questID = num(b) or num(a) -- Retail: (questID); older clients: (index, questID)
  if not questID or questID <= 0 then return end
  questID = floor(questID)
  if isTaskQuest(questID) then
    self.tasks[questID] = { at = GetTime() }
    trimCache(self.tasks)
  end
  local gid, gname
  local g = self.givers[questID]
  if g and GetTime() - g.at < NPC_TTL then
    gid, gname = g.id, g.name
  else
    gid, gname = readNpc()
  end
  self.givers[questID] = nil
  local ql = questLevel(questID)
  local mapID, px, py = here()
  local fields = {
    title = questTitle(questID), qlevel = ql, mapID = mapID, giver = gname, giverNpc = gid, category = questCategory(questID),
  }
  for k, v in pairs(questExtras(questID)) do fields[k] = v end
  Store.putText("quests", questID, fields)
  -- fallback for the description text: GetQuestText is missing or was unreadable
  local quests = charQuests()
  local entry = quests and quests[questID]
  if not (type(entry) == "table" and entry.detail) then
    local desc = str(call(C_QuestLog and C_QuestLog.GetQuestDescription, questID))
    if desc then Store.putText("quests", questID, { detail = desc }) end
  end
  noteQuestLine(questID, mapID)
  Store.append("QA", questID, playerLevel(), ql, mapID, gid, nameIfNoId(gid, gname), px, py)
  requestScan(self, questID) -- remember the objectives' start value, even if the quest sits under a collapsed header
end

handlers.QUEST_TURNED_IN = function(self, questID, xp, money)
  questID = num(questID)
  if not questID or questID <= 0 then return end
  questID = floor(questID)
  local t = GetTime()
  local npcID, npcName
  local tn = self.turnNpc[questID]
  if tn and t - tn.at < NPC_TTL then
    npcID, npcName = tn.id, tn.name
  else
    npcID, npcName = readNpc()
  end
  self.turnNpc[questID] = nil
  local item
  local ch = self.choice
  if ch and t - ch.at >= CHOICE_TTL then
    self.choice, ch = nil, nil
  end
  if ch and ch.questID == questID then -- a turn-in for another quest leaves the choice standing
    item = ch.itemID
    self.choice = nil
  end
  if item then self.completing, self.choiceItems = nil, {} end -- assigned; otherwise it stays for a late hook
  local aw = self.awaiting[questID]
  if aw then
    if item then self.awaiting[questID] = nil else aw.turnedAt = t end -- else waits for the loot message
  end
  self.turned[questID] = { at = t, item = item }
  trimCache(self.turned)
  closeObjectives(self, questID)
  local mapID, px, py = here()
  noteQuestLine(questID, mapID)
  Store.append("QT", questID, playerLevel(), questLevel(questID), mapID, keep(xp), keep(money), item, npcID,
    nameIfNoId(npcID, npcName), px, py)
end

-- abandon = QUEST_REMOVED without a turn-in. Decided after REMOVE_WINDOW because the order of QUEST_REMOVED and QUEST_TURNED_IN is not guaranteed.
local function decideRemoval(self, questID)
  local removedAt = self.removed[questID]
  if removedAt == nil then return end
  self.removed[questID] = nil
  local rec = self.turned[questID]
  if rec and abs(rec.at - removedAt) <= TURNED_TTL then return end -- turn-in (or removal after it): no abandon
  local req = self.abandonReq
  local confirmed = 0
  -- confirmed only if the hooked questID matches this removal (unknown questID -> 0)
  if req and GetTime() - req.at < 30 and req.questID == questID then
    confirmed = 1
    self.abandonReq = nil
  end
  Store.append("QX", questID, playerLevel(), questLevel(questID), here(), confirmed)
end

handlers.QUEST_REMOVED = function(self, questID, wasReplay)
  questID = num(questID)
  if not questID or questID <= 0 then return end
  questID = floor(questID)
  closeObjectives(self, questID)
  if wasReplay == true then return end -- replay of a completed quest ends, no abandon
  if self.removed[questID] ~= nil then return end
  -- task quest: not an abandon, nothing is decided or written (the flag may be gone from the API once the quest is removed)
  local task = self.tasks[questID] ~= nil or isTaskQuest(questID)
  self.tasks[questID] = nil
  if task then return end
  self.removed[questID] = GetTime()
  Core.after(self, REMOVE_WINDOW, function(s) decideRemoval(s, questID) end)
end

-- dropped at logout: a still undecided removal is not necessarily an abandon
handlers.PLAYER_LOGOUT = function(self)
  self.removed = {}
end

-- the turn-in window closes: a turn-in that did not happen no longer waits for its choice
-- (short grace, the order of QUEST_FINISHED and QUEST_TURNED_IN is not guaranteed)
handlers.QUEST_FINISHED = function(self)
  local t = GetTime()
  local comp = self.completing
  if comp and not self.turned[comp.questID] then self.completing, self.choiceItems = nil, {} end
  for _, aw in pairs(self.awaiting) do
    if not aw.turnedAt and not aw.closedAt then aw.closedAt = t end
  end
end

-- received item (signal of the Loot collector): the chosen reward, if it is one of the choice items of a pending
-- turn-in. Independent of the quest UI (DialogueUI & co. bypass the GetQuestReward hook). Only items from the quest
-- context (or without a known source, when the message comes after the window closed) count.
-- Bound to the questID: turn-ins already done get their item first (oldest first, loot follows the turn-ins in order),
-- only then the window still open; a late item of quest A never lands on the next quest B.
local REWARD_SOURCE = { quest = true, other = true }
handlers.FC_LOOT = function(self, itemID, _, _, kind)
  itemID = num(itemID)
  if not itemID or not REWARD_SOURCE[kind] then return end
  local t = GetTime()
  local turned, open
  for questID, aw in pairs(self.awaiting) do
    if t - aw.at >= CHOICE_TTL or (aw.turnedAt and t - aw.turnedAt >= TURNED_TTL)
      or (aw.closedAt and not aw.turnedAt and t - aw.closedAt >= REMOVE_WINDOW) then
      self.awaiting[questID] = nil -- expired, or closed without a turn-in
    elseif aw.items[itemID] then
      if aw.turnedAt then
        if not turned or aw.turnedAt < self.awaiting[turned].turnedAt then turned = questID end
      elseif not open or aw.at > self.awaiting[open].at then
        open = questID
      end
    end
  end
  if turned then
    self.awaiting[turned] = nil
    local rec = self.turned[turned]
    if rec and rec.item == nil then
      rec.item = itemID
      Store.append("QR", turned, itemID)
      local comp = self.completing
      if comp and comp.questID == turned then self.completing, self.choiceItems = nil, {} end
    end
  elseif open then
    local ch = self.choice
    if ch and ch.questID == open and t - ch.at < CHOICE_TTL then return end -- the hook was first
    self.choice = { questID = open, itemID = itemID, at = t }
  end
end

function Quests:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("Quests", Quests)
