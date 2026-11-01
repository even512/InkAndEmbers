-- Collector 'Progress': level-up, /played, XP by source, rested XP.
-- XP on two tracks: (a) chat messages via Patterns (GlobalStrings), (b) a check via the PLAYER_XP_UPDATE difference. Each gain is written exactly once:
-- message and difference are matched against each other; a difference without a message (after WINDOW seconds) is booked as 'other'. Nothing is counted at max level.
local _, ns = ...
local Core, Store, Patterns = ns.Core, ns.Store, ns.Patterns

local floor, min, max = math.floor, math.min, math.max
local match, gsub = string.match, string.gsub

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

-- only readable, finite numbers / non-empty strings; otherwise nil (secret values, missing APIs)
local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function str(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

-- calls the function only if it exists; error -> nil
local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c
end

local Zone = ns.Zone

-- Helpers

local WINDOW = 1.0     -- seconds: a message may wait this long for its difference (and vice versa)
local MSG_KEEP = 5.0   -- seconds: a message stays valid for matching
local HINT_TTL = 3.0   -- seconds: validity of quest hints (QUEST_TURNED_IN, 'Experience gained')
local DEDUPE = 2.0     -- seconds: duplicate discovery/quest messages (CHAT_MSG_SYSTEM and UI_INFO_MESSAGE)

local function playerLevel()
  return num(call(UnitLevel, "player"))
end

local function readXp()
  return num(call(UnitXP, "player")), num(call(UnitXPMax, "player")), playerLevel()
end

local function atMaxLevel()
  local r = call(IsPlayerAtEffectiveMaxLevel)
  if r == true then return true end
  if r == false then return false end
  local lvl = playerLevel()
  local top = num(call(GetMaxPlayerLevel)) or num(MAX_PLAYER_LEVEL)
  return lvl ~= nil and top ~= nil and lvl >= top
end

-- first number from a text like '+31' (thousands separators allowed)
local function firstInt(s)
  if not str(s) then return nil end
  local n = match(s, "%d[%d%.]*")
  if not n then return nil end
  return tonumber((gsub(n, "%.", "")))
end

-- XP message patterns. Argument numbers refer to the pattern from the GlobalString (positional arguments).
--   mob = argument with the enemy name, amt = amount, rest/rest2 = texts with the rested bonus, restSign = sign, grp = group/raid value, grpSign = sign.

local XP_DEFS = {}
local function def(name, o)
  o.name = name
  XP_DEFS[#XP_DEFS + 1] = o
end

-- order: variants with a group/raid value before the plain ones (more specific pattern first)
def("COMBATLOG_XPGAIN_FIRSTPERSON_GROUP", { src = "kill", mob = 1, amt = 2, grp = 3, grpSign = 1 })
def("COMBATLOG_XPGAIN_FIRSTPERSON_RAID", { src = "kill", mob = 1, amt = 2, grp = 3, grpSign = -1 })
def("COMBATLOG_XPGAIN_FIRSTPERSON", { src = "kill", mob = 1, amt = 2 })
for _, v in ipairs({ { "1", 1 }, { "2", 1 }, { "4", -1 }, { "5", -1 } }) do
  local n, sign = v[1], v[2]
  def("COMBATLOG_XPGAIN_EXHAUSTION" .. n .. "_GROUP", { src = "kill", mob = 1, amt = 2, rest = 3, rest2 = 4, restSign = sign, grp = 5, grpSign = 1 })
  def("COMBATLOG_XPGAIN_EXHAUSTION" .. n .. "_RAID", { src = "kill", mob = 1, amt = 2, rest = 3, rest2 = 4, restSign = sign, grp = 5, grpSign = -1 })
  def("COMBATLOG_XPGAIN_EXHAUSTION" .. n, { src = "kill", mob = 1, amt = 2, rest = 3, rest2 = 4, restSign = sign })
end
def("COMBATLOG_XPGAIN_QUEST", { src = "quest", amt = 1, rest = 2, rest2 = 3, restSign = 1 })
def("COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP", { src = "unnamed", amt = 1, grp = 2, grpSign = 1 })
def("COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_RAID", { src = "unnamed", amt = 1, grp = 2, grpSign = -1 })
def("COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED", { src = "unnamed", amt = 1 })

-- text -> { src, amt, rested, group, target, alts } or nil
local function parseXpMessage(text)
  if isSecret(text) or type(text) ~= "string" then return nil end
  for i = 1, #XP_DEFS do
    local d = XP_DEFS[i]
    local matcher = Patterns.compile(d.name)
    if matcher then
      local caps = { matcher(text) }
      local amt = num(caps[d.amt])
      if amt then
        local m = { src = d.src, amt = floor(amt), via = "msg" }
        if d.mob then m.target = str(caps[d.mob]) end
        if d.rest then
          local r = firstInt(caps[d.rest]) or firstInt(caps[d.rest2])
          if r and r > 0 then m.rested = r * d.restSign end
          -- All sources: unclear whether the amount already includes the rested bonus. So amt or amt + rested (amt - deduction for a penalty)
          -- counts as the difference when matching.
          if m.rested and m.amt + m.rested > 0 then m.alts = { m.amt + m.rested } end
        end
        if d.grp then
          local g = num(caps[d.grp])
          if g and g > 0 then m.group = floor(g) * d.grpSign end
        end
        return m
      end
    end
  end
  return nil
end

-- Collector

local Progress = {
  requires = { "UnitLevel" },
  events = {
    "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_SYSTEM",
    "UI_INFO_MESSAGE", "TIME_PLAYED_MSG", "QUEST_TURNED_IN", "PLAYER_LOGOUT",
  },
}
local handlers = {}

local settle

local function writeXp(self, m)
  local mapID = Zone.here()
  Store.append("XP", m.src, m.amt, m.rested, m.group, m.target, m.questID, playerLevel(), mapID, m.via)
  Core.emit("FC_XP", m.src, m.amt, m.target, m.via) -- Combat assigns kill XP to the kill
end

-- find and consume a quest hint (QUEST_TURNED_IN with XP or 'Experience gained: n') for an amount.
-- Assigned to the turn-in only if amt == xp or a stated rested bonus explains the difference (amt + rested == xp or xp <= amt <= xp + rested); otherwise 'other'.
local function takeQuestHint(self, amt, rested)
  local t, h = GetTime(), self.hints
  local turn, qmsg = h.turn, h.qmsg
  if turn and (turn.used or t - turn.at > HINT_TTL) then turn = nil end
  if qmsg and (qmsg.used or t - qmsg.at > HINT_TTL) then qmsg = nil end
  local fromTurn = turn and (amt == turn.xp
    or (rested and rested > 0 and (amt + rested == turn.xp or (amt >= turn.xp and amt <= turn.xp + rested))))
  local fromMsg = qmsg and qmsg.amt == amt
  if not fromTurn and not fromMsg then return false, nil end
  local questID = turn and turn.questID or nil
  if turn then turn.used = true end
  if qmsg then qmsg.used = true end
  return true, questID
end

-- amount without an unambiguous source (UNNAMED message or plain difference): quest hints, else 'other'.
local function writeAmbiguous(self, m)
  local found, questID = takeQuestHint(self, m.amt, m.rested)
  if found then
    m.src, m.questID = "quest", questID
  else
    m.src = "other"
  end
  writeXp(self, m)
end

local function pruneRecent(self, t)
  local r, keep = self.recent, {}
  for i = 1, #r do
    if t - r[i].at <= DEDUPE then keep[#keep + 1] = r[i] end
  end
  self.recent = keep
end

local function dropPending(self, amt)
  local p = self.pending
  for i = #p, 1, -1 do
    if p[i].amt == amt then
      local e = table.remove(p, i)
      for j = #self.msgs, 1, -1 do
        if self.msgs[j] == e then table.remove(self.msgs, j) end
      end
    end
  end
end

local function hasAlt(e, amt)
  if e.alts then
    for i = 1, #e.alts do
      if e.alts[i] == amt then return true end
    end
  end
  return false
end

-- match messages against differences: exact hits first, then in order (one XP_UPDATE can combine several gains).
local function pair(self)
  local msgs, diffs = self.msgs, self.diffs
  local i = 1
  while i <= #diffs do
    local d, hit = diffs[i], nil
    for j = 1, #msgs do
      if msgs[j].left == d.left or hasAlt(msgs[j], d.left) then
        hit = j
        break
      end
    end
    if hit then
      table.remove(msgs, hit)
      table.remove(diffs, i)
    else
      i = i + 1
    end
  end
  while msgs[1] and diffs[1] do
    local m, d = msgs[1], diffs[1]
    local c = min(m.left, d.left)
    m.left, d.left = m.left - c, d.left - c
    if m.left <= 0 then table.remove(msgs, 1) end
    if d.left <= 0 then table.remove(diffs, 1) end
  end
end

local function schedule(self)
  if self.timerOn then return end
  local first
  local p, d = self.pending[1], self.diffs[1]
  if p then first = p.at end
  if d and (not first or d.at < first) then first = d.at end
  if not first then return end
  self.timerOn = true
  local delay = max(0.05, first + WINDOW - GetTime() + 0.05)
  if not Core.after(self, delay, function(s)
    s.timerOn = false
    settle(s, false)
  end) then
    self.timerOn = false
  end
end

-- match and write due bookings. force = everything now (logout).
settle = function(self, force)
  pair(self)
  local t = GetTime()
  local p = self.pending
  local i = 1
  while i <= #p do
    local e = p[i]
    if force or t - e.at >= WINDOW then
      table.remove(p, i)
      writeAmbiguous(self, e.m)
    else
      i = i + 1
    end
  end
  local d = self.diffs
  while d[1] and (force or t - d[1].at >= WINDOW) do
    local x = table.remove(d, 1)
    writeAmbiguous(self, { amt = x.left, via = "diff" })
    self.booked[#self.booked + 1] = { amt = x.left, at = t } -- booked as difference only: a late message does not count again
  end
  local booked = self.booked
  for k = #booked, 1, -1 do
    if t - booked[k].at > MSG_KEEP then table.remove(booked, k) end
  end
  local msgs = self.msgs
  for k = #msgs, 1, -1 do
    if t - msgs[k].at > MSG_KEEP then table.remove(msgs, k) end
  end
  schedule(self)
end

local function addMessage(self, m)
  local t = GetTime()
  pruneRecent(self, t)
  -- message arrived after the window: the difference was already booked as other. Do not write again (nothing may count twice);
  -- the source stays 'other'.
  for k = #self.booked, 1, -1 do
    local b = self.booked[k]
    if t - b.at <= MSG_KEEP and (b.amt == m.amt or (m.alts and m.alts[1] == b.amt)) then
      table.remove(self.booked, k)
      return
    end
  end
  local src = m.src
  if src == "unnamed" then
    for _, r in ipairs(self.recent) do
      if r.amt == m.amt and (r.src == "explore" or r.src == "quest") then return end -- already recorded as discovery/quest
    end
  elseif src == "explore" then
    for _, r in ipairs(self.recent) do
      if r.src == "explore" and r.amt == m.amt and r.target == m.target then return end -- reported twice
    end
    dropPending(self, m.amt)
  elseif src == "quest" then
    dropPending(self, m.amt)
  end
  self.recent[#self.recent + 1] = { src = src, amt = m.amt, target = m.target, at = t }
  local e = { amt = m.amt, left = m.amt, alts = m.alts, at = t, m = m }
  self.msgs[#self.msgs + 1] = e
  if src == "unnamed" then
    self.pending[#self.pending + 1] = e
  else
    if src == "quest" then
      local _, questID = takeQuestHint(self, m.amt, m.rested)
      m.questID = questID
    end
    writeXp(self, m)
  end
  settle(self, false)
end

local function addDiff(self, amt)
  self.diffs[#self.diffs + 1] = { amt = amt, left = amt, at = GetTime() }
  settle(self, false)
end

-- /played

local function chatFrame()
  local cf = ChatFrame1
  if type(cf) == "table" and not isSecret(cf) and type(cf.IsEventRegistered) == "function"
    and type(cf.UnregisterEvent) == "function" and type(cf.RegisterEvent) == "function" then
    return cf
  end
  return nil
end

-- Deliberate deviation: /played is requested at login/reload and after level-up, but NOT at logout.
-- At logout the answer (TIME_PLAYED_MSG) no longer arrives, and ChatFrame1 would have to stay unregistered.
-- ChatFrame1 is re-registered only if we unregistered it ourselves.
local requestPlayed

local function restoreChat(self)
  self.playedWait = false
  if self.chatWasRegistered then
    self.chatWasRegistered = false
    local cf = chatFrame()
    if cf then pcall(cf.RegisterEvent, cf, "TIME_PLAYED_MSG") end
  end
  -- run a queued request (made during a running one) instead of dropping it
  local nextReason = table.remove(self.playedQueue, 1)
  if nextReason and not self.closing then
    Core.after(self, 0.5, function(s) requestPlayed(s, nextReason) end)
  end
end

requestPlayed = function(self, reason)
  if type(RequestTimePlayed) ~= "function" then return end
  if self.playedWait then
    for _, r in ipairs(self.playedQueue) do
      if r == reason then return end
    end
    self.playedQueue[#self.playedQueue + 1] = reason
    return
  end
  local cf = chatFrame()
  self.chatWasRegistered = false
  if cf then
    local ok, registered = pcall(cf.IsEventRegistered, cf, "TIME_PLAYED_MSG")
    if ok and registered == true and pcall(cf.UnregisterEvent, cf, "TIME_PLAYED_MSG") then
      self.chatWasRegistered = true
    end
  end
  self.playedReason = reason
  self.playedWait = true
  self.playedToken = (self.playedToken or 0) + 1
  local token = self.playedToken
  if not pcall(RequestTimePlayed) then
    restoreChat(self)
    return
  end
  Core.after(self, 10, function(s)
    if s.playedToken == token and s.playedWait then restoreChat(s) end
  end)
end

handlers.TIME_PLAYED_MSG = function(self, total, thisLevel)
  total, thisLevel = num(total), num(thisLevel)
  if total and total ~= self.lastPlayedTotal then
    self.lastPlayedTotal = total
    local reason = self.playedWait and self.playedReason or nil
    Store.append("PL", total, thisLevel, playerLevel(), reason)
  end
  if self.playedWait then
    self.playedReason = nil
    -- re-register only after the event, so the chat does not print the answer in the same pass
    Core.after(self, 0.2, restoreChat)
  end
end

-- Rested XP

-- At a real logout the APIs return 0 (xp = 0, xpMax = 0): the last known values apply (self.xp/xpMax/xpLevel);
-- rested bonus and rested state stay empty (the query is unreliable there).
local function logRested(self, reason)
  local xp, xpMax, level = readXp()
  local rested = num(call(GetXPExhaustion))
  local resting = call(IsResting)
  if reason == "logout" and not (xpMax and xpMax > 0) then
    xp, xpMax = self.xp, self.xpMax
    if not (level and level > 0) then level = self.xpLevel end
    rested, resting = nil, nil
  end
  local flag
  if resting == true then flag = 1 elseif resting == false then flag = 0 end
  Store.append("RS", reason, rested, flag, xp, xpMax, level)
end

-- Events

function Progress:init()
  self.msgs, self.diffs, self.pending, self.recent, self.hints, self.booked = {}, {}, {}, {}, {}, {}
  self.playedQueue = {}
  self.levelsPending = 0
  self.xp, self.xpMax, self.xpLevel = readXp()
end

handlers.PLAYER_ENTERING_WORLD = function(self, _, isReloadingUi)
  if self.entered then return end
  self.entered = true
  local reason = isReloadingUi == true and "reload" or "login"
  logRested(self, reason)
  requestPlayed(self, reason)
end

handlers.PLAYER_LEVEL_UP = function(self, level)
  level = num(level) or playerLevel()
  local mapID, x, y = Zone.here()
  Store.append("LV", level, mapID, x, y, Zone.sub())
  -- order relative to PLAYER_XP_UPDATE is not guaranteed: if the client already has the new maximum, XP_UPDATE is not processed yet
  -- (remember the level for jump detection); otherwise advance the base level.
  local curMax = num(call(UnitXPMax, "player"))
  if curMax and self.xpMax and curMax ~= self.xpMax then
    self.levelsPending = self.levelsPending + 1
  elseif level and self.xpLevel and level > self.xpLevel then
    self.xpLevel = level
  end
  Core.after(self, 2, function(s) requestPlayed(s, "levelup") end)
end

handlers.PLAYER_XP_UPDATE = function(self, unit)
  if type(unit) == "string" and unit ~= "player" then return end
  local xp, xpMax, level = readXp()
  if not xp or not xpMax then return end
  local oldXp, oldMax, oldLevel = self.xp, self.xpMax, self.xpLevel
  local pending = self.levelsPending
  self.levelsPending = 0
  self.xp, self.xpMax, self.xpLevel = xp, xpMax, level or oldLevel
  if xpMax <= 0 or atMaxLevel() then return end
  if not oldXp or not oldMax then return end
  local jump = pending
  if level and oldLevel and level - oldLevel > jump then jump = level - oldLevel end
  if jump >= 2 then
    -- multi-level jump: the intermediate levels are unknown. Do not book wrongly, only note it (amount empty).
    Store.append("XP", "other", nil, nil, nil, nil, nil, level, (Zone.here()), "unclear")
    return
  end
  local diff
  if xpMax ~= oldMax or jump >= 1 then
    diff = (oldMax - oldXp) + xp -- rest of the old level plus progress on the new one
  else
    diff = xp - oldXp
  end
  if diff > 0 then addDiff(self, floor(diff)) end
end

handlers.CHAT_MSG_COMBAT_XP_GAIN = function(self, text)
  if atMaxLevel() then return end
  local m = parseXpMessage(text)
  if m then addMessage(self, m) end
end

local function systemMessage(self, text)
  if isSecret(text) or type(text) ~= "string" then return end
  local zone, amt = Patterns.match("ERR_ZONE_EXPLORED_XP", text)
  amt = num(amt)
  if zone ~= nil and amt then
    if not atMaxLevel() then addMessage(self, { src = "explore", amt = floor(amt), target = str(zone), via = "msg" }) end
    return
  end
  local xp = num((Patterns.match("ERR_QUEST_REWARD_EXP_I", text)))
  if xp and not atMaxLevel() then self.hints.qmsg = { amt = floor(xp), at = GetTime() } end
end

handlers.CHAT_MSG_SYSTEM = function(self, text)
  systemMessage(self, text)
end

handlers.UI_INFO_MESSAGE = function(self, a, b)
  systemMessage(self, type(b) == "string" and b or a)
end

handlers.QUEST_TURNED_IN = function(self, questID, xp)
  xp = num(xp)
  if xp and xp > 0 then
    self.hints.turn = { questID = num(questID), xp = floor(xp), at = GetTime() }
  end
end

handlers.PLAYER_LOGOUT = function(self)
  self.closing = true
  settle(self, true)
  logRested(self, "logout")
  restoreChat(self)
end

function Progress:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("Progress", Progress)
