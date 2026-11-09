-- Collector 'Social': groups, guild, duels, PvP kills and deaths, trade, mail.
-- Groups: players (name, class, level) from the group units; shared kills, quests and instances are an approximation (everything while grouped). An open group survives reloads (snapshots.state.group).
-- Names of other players are foreign text (Store/Sanitize); secret values are never guessed. Trade: contents tracked until closing, written on 'Trade complete.' Mail: take via hooks, send after MAIL_SEND_SUCCESS.
local _, ns = ...
local Core, Store, Patterns = ns.Core, ns.Store, ns.Patterns

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

-- player name: UNKNOWNOBJECT (while the client does not know the unit yet) counts as nil, never as a name
local function nameOf(v)
  v = str(v)
  if v == nil then return nil end
  local unknown = UNKNOWNOBJECT
  if type(unknown) == "string" and not isSecret(unknown) and v == unknown then return nil end
  return v
end

local ROSTER_DELAY = 0.5   -- seconds: GROUP_ROSTER_UPDATE arrives in bursts
local READY_DELAY = 5      -- seconds after start: first state of group and guild
local EARLY = 60           -- seconds after start: guild data is still loading
local RESUME_MAX = 1800    -- seconds: a stored group counts as resumed this long after reload/login
local PCACHE_MAX = 60      -- players in the unit cache
local DUEL_WAIT = 1.5      -- seconds after DUEL_FINISHED until the message
local PK_DEDUPE = 5        -- seconds: the same player counts as a kill only once
local TRADE_WAIT = 1.0     -- seconds after TRADE_CLOSED until the decision (the message can come later)
local TRADE_SLOTS = 7
local INBOX_MAX = 50
local MAIL_ATTACH = 16
local SEND_ATTACH = 12
local PD_TRIES = { 1.0, 3.0 }
local GI_DELAY = 2.0       -- seconds after entering an instance: group units are only read by then
local GI_MEMBERS_MAX = 250 -- bytes in the members field of the GI line (Sanitize.FIELD_MAX)

local Social = {
  requires = { "UnitName" },
  events = {
    "GROUP_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "DUEL_REQUESTED", "DUEL_FINISHED", "CHAT_MSG_SYSTEM", "UI_INFO_MESSAGE",
    "PARTY_KILL", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "PLAYER_DEAD",
    "TRADE_SHOW", "TRADE_ACCEPT_UPDATE", "TRADE_MONEY_CHANGED", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED",
    "TRADE_CLOSED", "MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "QUEST_TURNED_IN", "PLAYER_LOGOUT",
  },
  signals = { "FC_KILL", "FC_INSTANCE" },
}
local handlers = {}

local function here()
  return ns.Zone.here()
end

local function savedState(key)
  local char = Store.char()
  local st = char and char.snapshots and char.snapshots.state
  local v = type(st) == "table" and st[key] or nil
  return type(v) == "table" and v or nil
end

function Social:init()
  self.born = GetTime()
  self.group, self.first = nil, true
  self.pcache, self.pcacheOrder, self.pkSeen = {}, {}, {}
  self.trade, self.inbox, self.pendingSend = nil, {}, nil
  self.guildSaved = savedState("guild")
  self.guildReady = false
  Core.after(self, READY_DELAY, function(s)
    s.guildReady = true
    s.refreshGroup(s)
    s.checkGuild(s)
  end)
  Core.hook(self, "StartDuel", function(s, name) s.duelOpp = str(name) or s.duelOpp end)
  Core.hook(self, "TakeInboxMoney", function(s, index) s.mailTake(s, index, "money") end)
  Core.hook(self, "TakeInboxItem", function(s, index, attach) s.mailTake(s, index, "item", attach) end)
  Core.hook(self, "AutoLootMailItem", function(s, index) s.mailTake(s, index, "all") end)
  Core.hook(self, "SendMail", function(s, recipient) s.mailSend(s, recipient) end)
end

-- Units

local function unitInfo(unit)
  local guid = str(call(UnitGUID, unit))
  local name = nameOf(call(UnitName, unit))
  local _, class = call(UnitClass, unit)
  local level = num(call(UnitLevel, unit))
  if level and level <= 0 then level = nil end
  return guid, name, str(class), level and floor(level) or nil
end

-- player by GUID: name, class (English), also without a unit
local function playerByGuid(guid)
  local r = callAll(GetPlayerInfoByGUID, guid)
  if not r then return nil, nil end
  return nameOf(r[6]), str(r[2])
end

-- group size: GetNumGroupMembers (counts you), fallback: read members + 1. Never smaller than the read list.
local function groupSize(list)
  local n = num(call(GetNumGroupMembers))
  local own = #list + 1
  if n and n >= own then return floor(n) end
  return own
end

local function remember(self, unit)
  if not isTrue(call(UnitIsPlayer, unit)) then return end
  local guid, name, class, level = unitInfo(unit)
  if not guid or not string.find(guid, "^Player%-") then return end
  local e = self.pcache[guid]
  if not e then
    e = {}
    self.pcache[guid] = e
    local order = self.pcacheOrder
    order[#order + 1] = guid
    if #order > PCACHE_MAX then self.pcache[table.remove(order, 1)] = nil end
  end
  e.name, e.class, e.level = name or e.name, class or e.class, level or e.level
end

handlers.PLAYER_TARGET_CHANGED = function(self) remember(self, "target") end
handlers.UPDATE_MOUSEOVER_UNIT = function(self) remember(self, "mouseover") end
handlers.NAME_PLATE_UNIT_ADDED = function(self, unit)
  if str(unit) then remember(self, unit) end
end

-- Group

local function roster()
  local raid = isTrue(call(IsInRaid))
  local prefix, max = raid and "raid" or "party", raid and 40 or 4
  local me = str(call(UnitGUID, "player"))
  local list = {}
  for i = 1, max do
    local guid, name, class, level = unitInfo(prefix .. i)
    if (guid or name) and guid ~= me then
      list[#list + 1] = { key = guid or name, name = name, class = class, level = level }
    end
  end
  return list, raid and "raid" or "party"
end

local function isGrouped()
  local g = call(IsInGroup)
  if isSecret(g) then return false end
  if g == nil then return (num(call(GetNumGroupMembers)) or 0) > 1 end
  return g == true
end

local function persistGroup(self)
  local g = self.group
  if g then
    Store.putSnapshot("state", "group",
      { open = true, start = g.start, kills = g.kills, quests = g.quests, instances = g.instances, maxSize = g.maxSize, at = time() }, true)
  else
    Store.putSnapshot("state", "group", { open = false }, true)
  end
end

local function endGroup(self, g, seconds)
  local mapID = here()
  Store.append("GE", seconds, g.maxSize, g.kills, g.quests, g.instances, playerLevel(), mapID)
  self.group = nil
  persistGroup(self)
end

function Social.refreshGroup(self)
  local grouped = isGrouped()
  local g = self.group
  local first = self.first
  self.first = false
  local saved = first and savedState("group") or nil
  if grouped then
    local list, kind = roster()
    local size = groupSize(list)
    local mapID = here()
    if not g then
      if saved and saved.open == true and num(saved.start) and num(saved.at) and time() - saved.at <= RESUME_MAX then
        g = { start = saved.start, kills = num(saved.kills) or 0, quests = num(saved.quests) or 0,
              instances = num(saved.instances) or 0, maxSize = num(saved.maxSize) or size, members = {} }
        for _, m in ipairs(list) do g.members[m.key] = { name = m.name, class = m.class, level = m.level, at = time() } end
        self.group = g
        return
      end
      if saved and saved.open == true then -- old group: close without duration
        Store.append("GE", nil, num(saved.maxSize), num(saved.kills), num(saved.quests), num(saved.instances), playerLevel(), mapID)
      end
      g = { start = time(), kills = 0, quests = 0, instances = 0, maxSize = size, members = {} }
      self.group = g
      Store.append("GS", size, kind, isTrue(call(UnitIsGroupLeader, "player")) and 1 or 0, playerLevel(), mapID)
      for _, m in ipairs(list) do
        g.members[m.key] = { name = m.name, class = m.class, level = m.level, at = time() }
        Store.append("GM", m.name, m.class, m.level, size)
        if m.name then Store.count("mates", m.name) end
      end
      persistGroup(self)
      return
    end
    local present = {}
    for _, m in ipairs(list) do
      present[m.key] = true
      local old = g.members[m.key]
      if not old then
        g.members[m.key] = { name = m.name, class = m.class, level = m.level, at = time() }
        Store.append("GM", m.name, m.class, m.level, size)
        if m.name then Store.count("mates", m.name) end
      else
        old.level, old.name, old.class = old.level or m.level, old.name or m.name, old.class or m.class
      end
    end
    for key, old in pairs(g.members) do
      if not present[key] then
        g.members[key] = nil
        Store.append("GL", old.name, old.class, old.level, time() - old.at)
      end
    end
    if size > g.maxSize then g.maxSize = size end
  else
    if g then
      endGroup(self, g, time() - g.start)
    elseif saved and saved.open == true then
      Store.append("GE", nil, num(saved.maxSize), num(saved.kills), num(saved.quests), num(saved.instances), playerLevel(), (here()))
      persistGroup(self)
    end
  end
end

handlers.GROUP_ROSTER_UPDATE = function(self)
  if self.first and GetTime() - self.born < READY_DELAY then return end -- the first state comes after start
  if self.rosterTimer then return end
  self.rosterTimer = true
  if not Core.after(self, ROSTER_DELAY, function(s)
    s.rosterTimer = false
    s.refreshGroup(s)
  end) then
    self.rosterTimer = false
  end
end

handlers.FC_KILL = function(self)
  local g = self.group
  if g then g.kills = g.kills + 1 end
end

handlers.QUEST_TURNED_IN = function(self)
  local g = self.group
  if g then g.quests = g.quests + 1 end
end

-- members field of the GI line: per entry name:class:level, separated by ','. Each part sanitized, ':' and ',' replaced in it;
-- only complete entries go in (at most GI_MEMBERS_MAX bytes in total).
local function memberPart(v)
  return (string.gsub(ns.Sanitize.field(v or ""), "[:,]", "_"))
end

local function membersText(list)
  local out, used = {}, 0
  for _, m in ipairs(list) do
    local entry = memberPart(m.name or "?") .. ":" .. memberPart(m.class) .. ":" .. (m.level and string.format("%d", m.level) or "")
    local add = #entry + (#out > 0 and 1 or 0)
    if used + add > GI_MEMBERS_MAX then break end
    out[#out + 1] = entry
    used = used + add
  end
  return table.concat(out, ",")
end

-- group on entering an instance (extends IE from the Instance collector). The group units are often not read right after entering:
-- GI is written GI_DELAY seconds later (the instance counts at once).
handlers.FC_INSTANCE = function(self, instanceID)
  local g = self.group
  if g then g.instances = g.instances + 1 end
  Core.after(self, GI_DELAY, function(s)
    local list = roster()
    if #list == 0 then return end
    Store.append("GI", instanceID, groupSize(list), membersText(list))
  end)
end

-- Guild

local function readGuild()
  local r = callAll(GetGuildInfo, "player")
  if not r then return nil end
  return { name = str(r[1]), rank = str(r[2]), rankIndex = num(r[3]) and floor(r[3]) or nil }
end

local function guildSave(self, g)
  local v = { inGuild = g.name ~= nil }
  if g.name then
    v.name, v.rank, v.rankIndex = g.name, g.rank, g.rankIndex
  end
  self.guildSaved = v
  Store.putSnapshot("state", "guild", v, true)
end

function Social.checkGuild(self)
  if not self.guildReady then return end
  local g = readGuild()
  if g == nil then return end
  local st = self.guildSaved
  local early = GetTime() - self.born < EARLY
  local level = playerLevel()
  if st == nil then
    if g.name then Store.append("GU", "seen", g.name, g.rank, g.rankIndex, level) end
    guildSave(self, g)
  elseif st.inGuild == true and not g.name then
    if early then -- guild data still loading: PLAYER_GUILD_UPDATE calls again
      Core.after(self, EARLY, function(s) s.checkGuild(s) end)
      return
    end
    Store.append("GU", "leave", str(st.name), nil, nil, level)
    guildSave(self, g)
  elseif st.inGuild ~= true and g.name then
    Store.append("GU", early and "seen" or "join", g.name, g.rank, g.rankIndex, level)
    guildSave(self, g)
  elseif st.inGuild == true and g.name and st.name ~= g.name then
    Store.append("GU", "change", g.name, g.rank, g.rankIndex, level)
    guildSave(self, g)
  elseif st.inGuild == true and g.name and (num(st.rankIndex) ~= g.rankIndex) then
    Store.append("GU", "rank", g.name, g.rank, g.rankIndex, level)
    guildSave(self, g)
  end
end

handlers.PLAYER_GUILD_UPDATE = function(self, unit)
  if unit ~= nil and unit ~= "player" then return end
  if self.guildTimer then return end
  self.guildTimer = true
  if not Core.after(self, 1.0, function(s)
    s.guildTimer = false
    s.checkGuild(s)
  end) then
    self.guildTimer = false
  end
end

-- Duels

-- own name in a duel message: plain or "Vorname Nachname"/"Vorname-Nachname" on Forever (Names.isMe)
local function itsMe(name, me)
  if ns.Names then return ns.Names.isMe(name) end
  return name == me
end

local function duelMessage(self, text)
  local me = str(call(UnitName, "player"))
  if not me then return false end
  local winner, loser = Patterns.match("DUEL_WINNER_KNOCKOUT", text)
  local result, opponent
  if str(winner) and str(loser) then
    if itsMe(winner, me) then
      result, opponent = "win", loser
    elseif itsMe(loser, me) then
      result, opponent = "loss", winner
    end
  else
    winner, loser = Patterns.match("DUEL_WINNER_RETREAT", text)
    if str(winner) and str(loser) then
      if itsMe(loser, me) then
        result, opponent = "fled", winner
      elseif itsMe(winner, me) then
        result, opponent = "opp_fled", loser
      end
    end
  end
  if not result then return false end
  if self.duelLast == text and self.duelDoneAt and GetTime() - self.duelDoneAt < 2 then return true end -- the same message via two events
  self.duelLast = text
  Store.append("DU", opponent, result, playerLevel(), (here()))
  Store.count("duels", result)
  self.duelDoneAt, self.duelOpp = GetTime(), nil
  return true
end

handlers.DUEL_REQUESTED = function(self, challenger)
  self.duelOpp = str(challenger) or self.duelOpp
end

handlers.DUEL_FINISHED = function(self)
  local opp = self.duelOpp
  Core.after(self, DUEL_WAIT, function(s)
    if s.duelDoneAt and GetTime() - s.duelDoneAt <= DUEL_WAIT + 3 then return end
    if opp or s.duelOpp then
      Store.append("DU", opp or s.duelOpp, "unknown", playerLevel(), (here()))
      Store.count("duels", "unknown")
    end
    s.duelOpp = nil
  end)
end

-- PvP

local function attackerKind(attacker)
  if isSecret(attacker) then return attacker end
  if not str(attacker) then return nil end
  if attacker == str(call(UnitGUID, "player")) then return "self" end
  local pet = str(call(UnitGUID, "pet"))
  if pet and attacker == pet then return "pet" end
  return "group"
end

handlers.PARTY_KILL = function(self, attacker, target)
  local guid = str(target)
  if not guid or not string.find(guid, "^Player%-") then return end
  local t = GetTime()
  if self.pkSeen[guid] and t - self.pkSeen[guid] < PK_DEDUPE then return end
  for other, at in pairs(self.pkSeen) do
    if t - at >= PK_DEDUPE then self.pkSeen[other] = nil end -- expired entries: the table does not grow
  end
  self.pkSeen[guid] = t
  local e = self.pcache[guid] or {}
  local name, class, level = e.name, e.class, e.level
  if not name or not class then
    local n, c = playerByGuid(guid)
    name, class = name or n, class or c
  end
  if not level then
    local unit = str(call(UnitTokenFromGUID, guid))
    if unit then level = num(call(UnitLevel, unit)) end
    if level and level <= 0 then level = nil end
  end
  local mapID, x, y = here()
  Store.append("PK", name or "?", class, level, attackerKind(attacker), playerLevel(), mapID, x, y)
  Store.count("pvp", "kills")
end

local function pvpDeath(self, token, attempt)
  if self.deathToken ~= token then return end
  local DR = C_DeathRecap
  local events = type(DR) == "table" and not isSecret(DR) and tbl(call(DR.GetRecapEvents)) or nil
  if events then
    local first = events[1]
    if not isSecret(first) and first == nil then events = nil end -- empty table (not loaded yet) like nil: second attempt
  end
  if events then
    local last, lastTs
    for i = 1, 60 do
      local e = events[i]
      if not isSecret(e) and e == nil then break end
      if tbl(e) then
        local ts = num(e.timestamp) or 0
        if last == nil or ts >= lastTs then last, lastTs = e, ts end
      end
    end
    local guid = last and str(last.sourceGUID)
    if guid and string.find(guid, "^Player%-") then
      local n, c = playerByGuid(guid)
      local mapID, x, y = here()
      Store.append("PD", str(last.sourceName) or n, c, playerLevel(), mapID, x, y)
      Store.count("pvp", "deaths")
    end
    return
  end
  if attempt < #PD_TRIES then
    Core.after(self, PD_TRIES[attempt + 1] - PD_TRIES[attempt], function(s) pvpDeath(s, token, attempt + 1) end)
  end
end

handlers.PLAYER_DEAD = function(self)
  if self.deadAt and GetTime() - self.deadAt < 5 then return end -- duplicate event
  self.deadAt = GetTime()
  self.deathToken = (self.deathToken or 0) + 1
  local token = self.deathToken
  Core.after(self, PD_TRIES[1], function(s) pvpDeath(s, token, 1) end)
end

-- Trade

local function itemText(list)
  local parts = {}
  for _, it in ipairs(list) do
    parts[#parts + 1] = (it.count and it.count > 1) and (it.key .. "*" .. string.format("%d", it.count)) or it.key
  end
  return #parts > 0 and table.concat(parts, ",") or nil
end

local function tradeSide(linkFn, infoFn)
  local out = {}
  for i = 1, TRADE_SLOTS do
    local id, bonus = Patterns.itemLink(call(linkFn, i))
    if id then
      local info = callAll(infoFn, i)
      local n = info and num(info[3])
      out[#out + 1] = { key = Patterns.itemKey(id, bonus), count = n and floor(n) or 1 }
    end
  end
  return out
end

local function tradeUpdate(self)
  local t = self.trade
  if not t then return end
  t.partner = str(call(UnitName, "NPC")) or t.partner
  t.giveGold = num(call(GetPlayerTradeMoney)) or t.giveGold
  t.getGold = num(call(GetTargetTradeMoney)) or t.getGold
  t.give = tradeSide(GetTradePlayerItemLink, GetTradePlayerItemInfo)
  t.get = tradeSide(GetTradeTargetItemLink, GetTradeTargetItemInfo)
end

handlers.TRADE_SHOW = function(self)
  self.trade = { give = {}, get = {} }
  tradeUpdate(self)
end

local function tradeEvent(self)
  if not self.trade then self.trade = { give = {}, get = {} } end
  tradeUpdate(self)
end
handlers.TRADE_ACCEPT_UPDATE = tradeEvent
handlers.TRADE_MONEY_CHANGED = tradeEvent
handlers.TRADE_PLAYER_ITEM_CHANGED = tradeEvent
handlers.TRADE_TARGET_ITEM_CHANGED = tradeEvent

handlers.TRADE_CLOSED = function(self)
  local t = self.trade
  if not t then return end
  Core.after(self, TRADE_WAIT, function(s)
    if s.trade ~= t then return end
    s.trade = nil
    if t.complete then
      local mapID = here()
      Store.append("TH", t.partner, t.giveGold, t.getGold, itemText(t.give or {}), itemText(t.get or {}), playerLevel(), mapID)
      Store.count("trade", "completed")
    else
      Store.count("trade", "cancelled")
    end
  end)
end

local function systemMessage(self, text)
  if isSecret(text) or type(text) ~= "string" then return end
  local done = _G.ERR_TRADE_COMPLETE
  if type(done) == "string" and not isSecret(done) then
    if text == done and self.trade then self.trade.complete = true end
  else
    Patterns.compile("ERR_TRADE_COMPLETE") -- notes the missing GlobalString in diag.patterns
  end
  duelMessage(self, text)
end

handlers.CHAT_MSG_SYSTEM = function(self, text)
  systemMessage(self, text)
end

handlers.UI_INFO_MESSAGE = function(self, a, b)
  systemMessage(self, type(b) == "string" and b or a)
end

-- Mail

local function mailSnapshot(self)
  local count = num(call(GetInboxNumItems))
  if not count then return end
  local inbox = {}
  for i = 1, min(floor(count), INBOX_MAX) do
    local h = callAll(GetInboxHeaderInfo, i)
    if h then
      local m = { sender = str(h[3]), money = num(h[5]) or 0, cod = num(h[6]) or 0, items = {} }
      -- h[8] (hasItem): number of attachments or true; true/unreadable -> query all slots. Attachments can have gaps (a taken slot stays empty),
      -- so the slots are walked and stopped once the count is reached.
      local want = num(h[8]) and floor(h[8]) or (isTrue(h[8]) and MAIL_ATTACH or 0)
      if want > MAIL_ATTACH then want = MAIL_ATTACH end
      local found = 0
      for j = 1, want > 0 and MAIL_ATTACH or 0 do
        if found >= want then break end
        local id, bonus = Patterns.itemLink(call(GetInboxItemLink, i, j))
        if id then
          found = found + 1
          local info = callAll(GetInboxItem, i, j)
          local c = info and num(info[4])
          m.items[j] = { key = Patterns.itemKey(id, bonus), count = c and floor(c) or 1 }
        end
      end
      local inv = callAll(GetInboxInvoiceInfo, i)
      m.ah = inv ~= nil and str(inv[1]) ~= nil
      inbox[i] = m
    end
  end
  self.inbox = inbox
end

handlers.MAIL_INBOX_UPDATE = mailSnapshot

local function writeMail(self, m, money, items, cod)
  if (money or 0) <= 0 and #items == 0 then return end
  Store.append("PM", m.sender, (money or 0) > 0 and money or nil, itemText(items), (cod or 0) > 0 and cod or nil, m.ah and 1 or 0,
    playerLevel())
  Store.count("mail", "received")
end

-- after the original call (hook): the data comes from the last read mailbox
function Social.mailTake(self, index, what, attach)
  index = num(index)
  local m = index and self.inbox[floor(index)]
  if not m then return end
  if what == "money" then
    local money = m.money
    m.money = 0
    writeMail(self, m, money, {}, nil)
  elseif what == "item" then
    local a = num(attach) and floor(attach) or 1
    local it = m.items[a]
    if not it then return end
    m.items[a] = nil
    writeMail(self, m, 0, { it }, m.cod)
  else
    local money, items = m.money, {}
    for j = 1, MAIL_ATTACH do
      if m.items[j] then items[#items + 1] = m.items[j] end
    end
    m.money, m.items = 0, {}
    writeMail(self, m, money, items, #items > 0 and m.cod or nil)
  end
end

local function sendSnapshot(recipient)
  local items = {}
  for i = 1, SEND_ATTACH do
    local info = callAll(GetSendMailItem, i)
    local id = info and num(info[2])
    if id and id > 0 then
      local c = num(info[4])
      items[#items + 1] = { key = Patterns.itemKey(floor(id), nil), count = c and floor(c) or 1 }
    end
  end
  return { recipient = str(recipient), money = num(call(GetSendMailMoney)) or 0, cod = num(call(GetSendMailCOD)) or 0, items = items,
           at = GetTime() }
end

local function writeSend(self, s)
  Store.append("PS", s.recipient, s.money > 0 and s.money or nil, itemText(s.items), s.cod > 0 and s.cod or nil, playerLevel())
  Store.count("mail", "sent")
end

function Social.mailSend(self, recipient)
  local snap = sendSnapshot(recipient)
  local e = Core.collector("Social")
  if e and e.unknown and string.find(e.unknown, "MAIL_SEND_SUCCESS", 1, true) then
    writeSend(self, snap) -- confirmation event unknown: write on send
  else
    self.pendingSend = snap
  end
end

handlers.MAIL_SEND_SUCCESS = function(self)
  local s = self.pendingSend
  self.pendingSend = nil
  if s and GetTime() - s.at <= 30 then writeSend(self, s) end
end

handlers.MAIL_FAILED = function(self)
  self.pendingSend = nil
end


handlers.PLAYER_LOGOUT = function(self)
  if not self.first then persistGroup(self) end
end

function Social:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("Social", Social)
