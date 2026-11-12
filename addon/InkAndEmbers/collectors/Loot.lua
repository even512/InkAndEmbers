-- Collector 'Loot': finds from green up individually, below only counters. Finds come from the chat message (patterns from GlobalStrings); LOOT_OPENED only gives source and quality.
-- A secret message is never guessed (counters.unreadable.loot_msg). Items are stored as item key (Patterns.itemLink); signal FC_LOOT(itemID, count, quality, source, srcID, name).
-- Loot rolls (B5): START_LOOT_ROLL remembers the item, the RollOnLoot hook writes RL (choice) and counts counters.rolls[need|greed|pass|de|tmog];
-- the system messages give RW (won, with our own roll number if it was seen) and counters.rolls.won.
-- Unreadable source (Retail 12.x): a fresh kill nearby (KILL_TTL_*) gives source 'mob', srcID only if unambiguous and newer than KILL_SRC_MAX s; an approximation (a chest after a kill can count as an enemy).
-- Finds of other group members (LG, 1.0.8): only inside an instance (visit open in the Instance collector) and only from green up, from the
-- other-player loot messages (LOOT_ITEM_MULTIPLE, LOOT_ITEM, LOOT_ITEM_PUSHED). Recipient name from the message, class only when the group units
-- give it readable; the roll type (need/greed/de/tmog) only when the matching "<player> won: <item> (<type> - n)" message (LOOT_ROLL_WON_NO_SPAM_*)
-- was seen for the same item and player shortly before, else empty. Own messages stay LT (never LG). A secret message only counts as unreadable.
local _, ns = ...
local Core, Store, Patterns, Context = ns.Core, ns.Store, ns.Patterns, ns.Context

local floor, min, match = math.floor, math.min, string.match

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

local GOOD = 2          -- quality green: individually from here
local SLOT_TTL = 20     -- seconds: loot window data stays valid for the message this long
local SLOT_MAX = 60     -- slots per loot window
local KILL_TTL_WINDOW = 20   -- seconds: a kill counts as source when a loot window accompanies the message
local KILL_SRC_MAX = 8        -- seconds: only a kill this fresh and unambiguous provides the npcID (else 'mob' without srcID)
local KILL_TTL_NOWINDOW = 15  -- seconds: same without a loot window (looting without a window, window unreadable)
local KILL_MAX = 8            -- remembered kills
local KILL_DEDUPE = 5         -- seconds: the same kill via FC_KILL_SEEN and FC_KILL
local KILL_PAIR = 2           -- seconds: an unreadable-ID kill (FC_KILL_SEEN) is paired with its FC_KILL this soon (Combat waits 1 s for the XP)

-- messages (GlobalStrings) in order: variants with a quantity first. Columns: name, kind, has quantity.
local MESSAGES = {
  { "LOOT_ITEM_SELF_MULTIPLE", "loot" }, { "LOOT_ITEM_SELF", "loot" },
  { "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "pushed" }, { "LOOT_ITEM_PUSHED_SELF", "pushed" },
  { "LOOT_ITEM_CREATED_SELF_MULTIPLE", "craft" }, { "LOOT_ITEM_CREATED_SELF", "craft" },
  { "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", "bonus" }, { "LOOT_ITEM_BONUS_ROLL_SELF", "bonus" },
}

-- messages about other players' finds: GlobalString, has quantity (arguments: player, item[, quantity]); missing strings are skipped silently
local OTHERS = {
  { "LOOT_ITEM_MULTIPLE", true }, { "LOOT_ITEM", false },
  { "LOOT_ITEM_PUSHED_MULTIPLE", true }, { "LOOT_ITEM_PUSHED", false },
}
-- win messages of other players with the roll type. Client format: "%1$s won: %3$s |cff818181(Need - %2$d)|r"; Patterns.compile returns the
-- captures by argument position: (player, roll number, item)
local WON = {
  { "LOOT_ROLL_WON_NO_SPAM_NEED", "need" }, { "LOOT_ROLL_WON_NO_SPAM_GREED", "greed" },
  { "LOOT_ROLL_WON_NO_SPAM_DE", "de" }, { "LOOT_ROLL_WON_NO_SPAM_TRANSMOG", "tmog" },
}
local WIN_TTL = 120          -- seconds: a win message stays valid for the loot message of the same item and player
local GROUP_MAX_PARTY, GROUP_MAX_RAID = 4, 40
local WHO_MAX = 64

-- counter group per source
local GROUP = { vendor = "bought", craft = "crafted", mail = "received", trade = "received", ah = "received", quest = "quest_items" }

local Loot = {
  requires = { "UnitGUID" },
  events = { "LOOT_OPENED", "CHAT_MSG_LOOT", "START_LOOT_ROLL" },
  signals = { "FC_KILL", "FC_KILL_SEEN" },
}
local handlers = {}

-- RollOnLoot(rollID, rollType): 0 pass, 1 need, 2 greed, 3 disenchant, 4 transmog (Retail)
local ROLL_CHOICE = { [0] = "pass", [1] = "need", [2] = "greed", [3] = "de", [4] = "tmog" }
local ROLLED = { "LOOT_ROLL_ROLLED_NEED", "LOOT_ROLL_ROLLED_GREED", "LOOT_ROLL_ROLLED_DE" } -- (roll, item, player)
local ROLL_MAX = 20 -- remembered rolls (open rolls and our roll numbers) before the memory starts over

-- { key, id } of the item of a roll; nil if the API is missing or the link unreadable
local function rollItem(rollID)
  if type(GetLootRollItemLink) ~= "function" then return nil end
  local id, bonus, quality, name = Patterns.itemLink(call(GetLootRollItemLink, rollID))
  if not id then return nil end
  Store.noteItem(id, name, quality)
  return { key = Patterns.itemKey(id, bonus), id = id }
end

local function remember(t, k, v)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  if n >= ROLL_MAX then
    for key in pairs(t) do t[key] = nil end
  end
  t[k] = v
end

handlers.START_LOOT_ROLL = function(self, rollID)
  rollID = num(rollID)
  if not rollID then return end
  rollID = floor(rollID)
  local item = rollItem(rollID)
  if item then remember(self.rolls, rollID, item) end
end

-- hook on RollOnLoot (runs after the original call)
local function onRoll(self, rollID, rollType)
  rollID, rollType = num(rollID), num(rollType)
  if not rollID then return end
  rollID = floor(rollID)
  local choice = rollType and ROLL_CHOICE[floor(rollType)] or "other"
  local item = self.rolls[rollID] or rollItem(rollID)
  self.rolls[rollID] = nil
  Store.append("RL", item and item.key, choice, rollID)
  Store.count("rolls", choice)
end

-- own name in "by <player>" (plain, with realm, or "Vorname Nachname"/"Vorname-Nachname" on Forever, Names.isMe); never a name
-- that only contains ours
local function isMe(who)
  if ns.Names then return ns.Names.isMe(who) end
  local me = str(call(UnitName, "player"))
  who = str(who)
  if not me or not who then return false end
  return who == me or string.sub(who, 1, #me + 1) == me .. "-"
end

-- name without realm part ("Name-Realm" -> "Name")
local function baseName(who)
  return match(who, "^([^%-]+)") or who
end

-- roll messages of CHAT_MSG_LOOT: our own roll number (ROLLED) and the win (LOOT_ROLL_YOU_WON). true if the text was one of them.
local function rollMessage(self, text)
  local link = Patterns.match("LOOT_ROLL_YOU_WON", text)
  if link then
    local id, bonus = Patterns.itemLink(link)
    if id then
      Store.append("RW", Patterns.itemKey(id, bonus), self.myRolls[id])
      Store.count("rolls", "won")
      self.myRolls[id] = nil
    end
    return true
  end
  for i = 1, #ROLLED do
    local roll, itemLink, who = Patterns.match(ROLLED[i], text)
    if roll ~= nil then
      local id = Patterns.itemLink(itemLink)
      if id and num(roll) and isMe(who) then remember(self.myRolls, id, floor(roll)) end
      return true
    end
  end
  -- win of another player with the roll type: remembered for the loot message that follows
  for i = 1, #WON do
    if type(_G[WON[i][1]]) == "string" then
      local who, _, itemLink = Patterns.match(WON[i][1], text)
      if itemLink ~= nil then
        local id = Patterns.itemLink(itemLink)
        who = str(who)
        if id and who and not isMe(who) then remember(self.wins, id .. ":" .. baseName(who), { who = baseName(who), kind = WON[i][2], at = GetTime() }) end
        return true
      end
    end
  end
  return false
end

function Loot:init()
  self.wins = {} -- itemID:player -> { who, kind, at }: win messages of other players with the roll type
  self.rolls, self.myRolls = {}, {} -- rollID -> { key, id } (open rolls); itemID -> our roll number
  if type(GetLootRollItemLink) == "function" then Core.hook(self, "RollOnLoot", onRoll) end
  self.slots = {} -- itemID -> { kind, srcID, quality, at }
  self.kills = {} -- fresh kills: { id = npcID or nil (unreadable), at }
  self.window = nil -- last opened loot window: { at, fishing }
end

-- kill from Combat (FC_KILL): the npcID can be secret ('?'), then id stays empty.
local function recentKills(self, ttl)
  local t, out = GetTime(), {}
  for _, k in ipairs(self.kills) do
    if t - k.at <= ttl then out[#out + 1] = k end
  end
  return out
end

local function fallbackMob(self, ttl)
  local list = recentKills(self, ttl)
  if #list == 0 then return nil end
  local id, newest = list[1].id, list[1].at
  for i = 2, #list do
    if list[i].id ~= id then id = nil end
    if list[i].at > newest then newest = list[i].at end
  end
  if GetTime() - newest > KILL_SRC_MAX then id = nil end -- too old for a safe match: only the kind, no ID
  return "mob", id
end

-- source from the loot GUID: mob (npcID), object (object ID), container (opened bag)
local function sourceOf(guid)
  guid = str(guid)
  if not guid then return nil end
  local kind, id = match(guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if kind == "Creature" or kind == "Vehicle" then return "mob", tonumber(id) end
  if kind == "GameObject" then return "object", tonumber(id) end
  if match(guid, "^Item%-") then return "container", nil end
  return nil
end

-- FC_KILL_SEEN fires right at the kill (Combat then waits briefly for XP before FC_KILL); auto-loot can arrive before FC_KILL.
-- The same kill via both signals is remembered once (same npcID within KILL_DEDUPE s).
-- Kills without a readable npcID (secret) have nothing to compare: they are never merged by "same ID". Such a kill from FC_KILL only
-- joins the kill that FC_KILL_SEEN noted a moment ago (within KILL_PAIR s, once each); every other unreadable kill stays its own entry.
local function noteKill(self, npcID, signal)
  local id, t, k = num(npcID), GetTime(), self.kills
  for i = #k, 1, -1 do
    local e = k[i]
    if id ~= nil then
      if e.id == id and t - e.at <= KILL_DEDUPE then
        -- duplicate (second signal or second kill of the same npcID): do not create anew, but move the timestamp to the newer kill,
        -- else the younger kill is judged 'too old' for srcID (KILL_SRC_MAX) too early.
        e.at = t
        return
      end
    elseif signal == "kill" and e.id == nil and e.unpaired and t - e.at <= KILL_PAIR then
      e.unpaired = nil -- the same kill, now confirmed by FC_KILL
      return
    end
  end
  k[#k + 1] = { id = id, at = t, unpaired = (id == nil and signal ~= "kill") or nil }
  while #k > KILL_MAX do table.remove(k, 1) end
end

handlers.FC_KILL = function(self, npcID) return noteKill(self, npcID, "kill") end
handlers.FC_KILL_SEEN = function(self, npcID) return noteKill(self, npcID, "seen") end

handlers.LOOT_OPENED = function(self)
  local t = GetTime()
  for id, s in pairs(self.slots) do
    if t - s.at > SLOT_TTL then self.slots[id] = nil end
  end
  self.window = { at = t, fishing = isTrue(call(IsFishingLoot)) } -- also when the slots are unreadable
  local n = num(call(GetNumLootItems))
  if not n then return end
  local fishing = self.window.fishing
  for slot = 1, min(floor(n), SLOT_MAX) do
    local id = Patterns.itemLink(call(GetLootSlotLink, slot))
    if id then
      local kind, srcID
      if fishing then
        kind = "fishing"
      else
        local src = callAll(GetLootSourceInfo, slot)
        kind, srcID = sourceOf(src and src[1])
      end
      local info = callAll(GetLootSlotInfo, slot)
      self.slots[id] = { kind = kind, srcID = srcID, quality = info and num(info[5]) or nil, at = t }
    end
  end
end

-- source for items without a loot window, from context
local function contextSource(how)
  if how == "craft" then return "craft" end
  if how == "bonus" then return "bonus" end
  if Context then
    local w = Context.first("merchant", "quest", "mail", "trade", "ah")
    if w == "merchant" then return "vendor" end
    if w then return w end
  end
  return "other"
end

local function gotItem(self, link, count, how)
  local id, bonus, quality, name = Patterns.itemLink(link)
  if not id then return end
  count = (num(count) and count >= 1) and floor(count) or 1
  local slot = self.slots[id]
  if slot and GetTime() - slot.at > SLOT_TTL then slot = nil end
  if quality == nil and slot then quality = slot.quality end
  if quality == nil then quality = num(call(C_Item and C_Item.GetItemQualityByID, id)) end
  local kind, srcID
  if slot and how == "loot" and slot.kind then
    kind, srcID = slot.kind, slot.srcID
  elseif how == "loot" then
    -- source unreadable or no window seen: loot window or fresh kill instead of 'other'
    local w = self.window
    local windowFresh = w ~= nil and GetTime() - w.at <= SLOT_TTL
    if windowFresh and w.fishing then
      kind = "fishing"
    elseif windowFresh then
      kind, srcID = fallbackMob(self, KILL_TTL_WINDOW)
    else
      kind, srcID = fallbackMob(self, KILL_TTL_NOWINDOW)
    end
    if not kind then kind, srcID = contextSource(how), nil end
  else
    kind = contextSource(how)
  end
  Store.noteItem(id, name, quality)
  if quality ~= nil then Store.count("loot_quality", quality) end
  if quality ~= nil and quality < GOOD then
    Store.count(GROUP[kind] or "loot", id, count)
  else
    local mapID, x, y = ns.Zone.here()
    Store.append("LT", Patterns.itemKey(id, bonus), count, quality, kind, srcID, playerLevel(), mapID, x, y)
  end
  Core.emit("FC_LOOT", id, count, quality, kind, srcID, name) -- name last (to-do counters match by name)
  if quality == 3 then
    Core.emit("FC_MOMENT", "first_blue", id, 3, "item", true)
  elseif quality ~= nil and quality >= 4 then
    Core.emit("FC_MOMENT", "first_epic", id, quality, "item", true)
  end
end

-- a visit in an instance is open (the Instance collector keeps it)
local function inInstance()
  local e = Core.collector and Core.collector("Instance")
  local d = e and e.active and e.def
  return d ~= nil and d.cur ~= nil
end

-- class file name of a group member by name; nil when the unit is not found or the values are not readable
local function groupClass(who)
  local want = baseName(who)
  local raid = call(IsInRaid)
  raid = not isSecret(raid) and raid == true
  local prefix, max = raid and "raid" or "party", raid and GROUP_MAX_RAID or GROUP_MAX_PARTY
  for i = 1, max do
    local unit = prefix .. i
    local name = str(call(UnitName, unit))
    if name and baseName(name) == want then
      local _, class = call(UnitClass, unit)
      class = str(class)
      if not class then return nil end
      class = ns.Sanitize.field(class)
      return class ~= "" and class or nil
    end
  end
  return nil
end

-- find of another player (inside an instance, green and better): LG line. true if the text was such a message (written or not).
local function otherLoot(self, text)
  for i = 1, #OTHERS do
    local name = OTHERS[i][1]
    if type(_G[name]) == "string" then
      local who, link, qty = Patterns.match(name, text)
      if who ~= nil and link ~= nil then
        who = str(who)
        if not who or isMe(who) then return true end
        if not inInstance() then return true end
        local id, bonus, quality, itemName = Patterns.itemLink(link)
        if not id then return true end
        if quality == nil then quality = num(call(C_Item and C_Item.GetItemQualityByID, id)) end
        if quality == nil or quality < GOOD then return true end
        local count = (num(qty) and qty >= 1) and floor(qty) or 1
        Store.noteItem(id, itemName, quality)
        local roll
        local winKey = id .. ":" .. baseName(who)
        local win = self.wins[winKey]
        if win then
          self.wins[winKey] = nil
          if GetTime() - win.at <= WIN_TTL then roll = win.kind end
        end
        Store.append("LG", Patterns.itemKey(id, bonus), count, quality, ns.Sanitize.cut(ns.Sanitize.field(who), WHO_MAX), groupClass(who), roll)
        return true
      end
    end
  end
  return false
end

handlers.CHAT_MSG_LOOT = function(self, text)
  if isSecret(text) then
    Store.count("unreadable", "loot_msg")
    return
  end
  if type(text) ~= "string" then return end
  for i = 1, #MESSAGES do
    local m = MESSAGES[i]
    local matcher = Patterns.compile(m[1])
    if matcher then
      local link, qty = matcher(text)
      if link then
        gotItem(self, link, qty, m[2])
        return
      end
    end
  end
  if otherLoot(self, text) then return end
  rollMessage(self, text)
end

function Loot:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("Loot", Loot)
