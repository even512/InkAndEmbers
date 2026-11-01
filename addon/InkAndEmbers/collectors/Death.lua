-- Collector 'Death': full deaths (place, level, death report, cause, way back, duration).
-- Death report from C_DeathRecap; without a readable report the cause is guessed: breath bar (MIRROR_TIMER BREATH) -> drowning, death without combat -> fall.
-- Guesses are flagged guess = 1.
local _, ns = ...
local Core, Store = ns.Core, ns.Store

local floor, match, lower = math.floor, string.match, string.lower

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
  local ok, a, b, c = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c
end

-- value for a log line: numbers and secret values ('?') stay, everything else is dropped
local function keep(v)
  if isSecret(v) or num(v) then return v end
  return nil
end

-- text for a log line: secret values stay ('?'), otherwise only readable strings
local function textOrSecret(v)
  if isSecret(v) then return v end
  return str(v)
end

local function flag(v)
  if isSecret(v) then return v end
  if v == true then return 1 end
  if v == false then return 0 end
  return nil
end

local RECAP_DELAY = 0.5  -- seconds after PLAYER_DEAD until the death report is first read
local RECAP_TRIES = 3    -- attempts (1 s apart) while the report is missing
local RECAP_MAX = 50
local TIMER_GRACE = 3    -- seconds: a breath bar stopped shortly before death still counts
local COMBAT_GRACE = 2   -- seconds: combat ending shortly before death counts as 'in combat'
local GOSSIP_TTL = 10    -- seconds: a ghost's gossip option counts as an offer only this long before coming alive
local HOOK_TTL = 120    -- seconds: spirit healer/corpse/resurrect via button is valid this long
local DUP_WINDOW = 5     -- seconds: a second PLAYER_DEAD this soon after the first is the same event
local CORPSE_NEAR = 0.05 -- map fraction: this close to the corpse counts as a corpse run (guessed)
local SICKNESS_IDS = { 15007 } -- aura 'Resurrection Sickness' (spirit healer)
local AURA_FRESH = 30        -- seconds: an aura running longer is not from this resurrection
local AURA_WAIT = 1.5        -- seconds: the aura may arrive shortly after PLAYER_UNGHOST; a guessed way stays open this long
local AURA_SCAN = 40

local XP_POPUPS = { "XP_LOSS", "XP_LOSS_NO_DURABILITY", "XP_LOSS_NO_SICKNESS" } -- spirit healer windows (Classic legacy)
local XP_POPUP_SET = {}
for _, which in ipairs(XP_POPUPS) do XP_POPUP_SET[which] = true end

local ENV = { falling = "fall", drowning = "drown", fatigue = "fatigue", lava = "lava", fire = "fire", slime = "slime" }

local function playerLevel()
  return num(call(UnitLevel, "player"))
end

local function npcIdOf(guid)
  if not str(guid) then return nil end
  local kind, id = match(guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if (kind == "Creature" or kind == "Vehicle") and id then return tonumber(id) end
  return nil
end

local Death = {
  requires = { "UnitLevel" },
  events = {
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "MIRROR_TIMER_START", "MIRROR_TIMER_STOP", "CONFIRM_XP_LOSS", "RESURRECT_REQUEST",
  },
}
local handlers = {}

function Death:init()
  self.inCombat = InCombatLockdown() == true
  self.timers = {}
  self.dead = nil
  if call(UnitIsDeadOrGhost, "player") == true then self.dead = { reloaded = true } end -- reload as ghost: start unknown
  -- hooks defensively: Core.hook only sets if the function exists in the client (else false, no error)
  local function spiritMark(s) s.spiritAt = GetTime() end
  local function offerMark(s) s.spiritOffer = GetTime() end
  local function resMark(s) s.resAt = GetTime() end
  Core.hook(self, "AcceptXPLoss", spiritMark)
  Core.hook(self, "RetrieveCorpse", function(s) s.corpseAt = GetTime() end)
  Core.hook(self, "AcceptResurrect", resMark)
  Core.hook(self, "UseSoulstone", resMark)
  -- Retail spirit healer: a ghost's gossip option (a ghost only talks to the spirit healer). Only an offer:
  -- choosing it proves no resurrection (the conversation can abort), see gossipOffered/classify.
  if type(C_GossipInfo) == "table" then
    Core.hook(self, C_GossipInfo, "SelectOption", function(s)
      local d = s.dead
      if d and d.ghost then s.gossipAt = GetTime() end
    end)
  end
  -- spirit healer via the XP-loss popup (window or function depending on the client)
  if type(StaticPopupDialogs) == "table" then
    for _, which in ipairs(XP_POPUPS) do
      local dlg = StaticPopupDialogs[which]
      if type(dlg) == "table" then
        Core.hook(self, dlg, "OnAccept", spiritMark)
        Core.hook(self, dlg, "OnShow", offerMark)
      end
    end
  end
  Core.hook(self, "StaticPopup_Show", function(s, which)
    if XP_POPUP_SET[str(which) or ""] then s.spiritOffer = GetTime() end
  end)
  Core.hook(self, "StaticPopup_OnClick", function(s, dialog, index)
    local which = type(dialog) == "table" and not isSecret(dialog) and str(dialog.which) or nil
    if which and XP_POPUP_SET[which] and index == 1 then s.spiritAt = GetTime() end
  end)
end

local function recent(t)
  return t ~= nil and GetTime() - t <= HOOK_TTL
end

-- ghost gossip option shortly before now (spirit healer offer, no proof)
local function gossipOffered(self)
  return self.gossipAt ~= nil and GetTime() - self.gossipAt <= GOSSIP_TTL
end

local function timerActive(self, name)
  local t = self.timers[name]
  if not t then return false end
  return t.on or (t.offAt ~= nil and GetTime() - t.offAt <= TIMER_GRACE)
end

handlers.MIRROR_TIMER_START = function(self, name)
  name = str(name)
  if name then self.timers[name] = { on = true } end
end

handlers.MIRROR_TIMER_STOP = function(self, name)
  name = str(name)
  if name and self.timers[name] then self.timers[name] = { on = false, offAt = GetTime() } end
end

handlers.PLAYER_REGEN_DISABLED = function(self)
  self.inCombat = true
end

handlers.PLAYER_REGEN_ENABLED = function(self)
  self.inCombat = false
  self.combatEndAt = GetTime()
end

handlers.CONFIRM_XP_LOSS = function(self)
  self.spiritOffer = GetTime() -- spirit healer offers resurrection (accepted via AcceptXPLoss)
end

handlers.RESURRECT_REQUEST = function(self)
  self.resOffer = GetTime()
end

-- Death and death report

local function cause(d, killer)
  if killer then
    local env = str(killer.environmentalType)
    if env then return ENV[lower(env)] or "environment", 0 end
    if str(killer.event) == "ENVIRONMENTAL_DAMAGE" then return "environment", 0 end
    if killer.npcID or killer.source then return "enemy", 0 end
  end
  if d.breath then return "drown", 1 end
  if d.fatigue then return "fatigue", 1 end
  if not d.combat and not killer then return "fall", 1 end
  return nil, nil
end

local function writeRecap(self, d, events)
  local DR = C_DeathRecap
  local count, killer, maxHP
  if isSecret(events) then
    count = events
  elseif type(events) == "table" then
    local list = {}
    for i = 1, RECAP_MAX do
      local e = events[i]
      if not isSecret(e) and e == nil then break end
      list[#list + 1] = e
    end
    count = #list
    local last -- time of the last hit (= killing blow)
    for _, e in ipairs(list) do
      if type(e) == "table" and not isSecret(e) then
        local ts = num(e.timestamp)
        if ts and (last == nil or ts > last) then last = ts end
      end
    end
    for i, e in ipairs(list) do
      if type(e) == "table" and not isSecret(e) then
        local npcID = npcIdOf(e.sourceGUID)
        local source = str(e.sourceName)
        if npcID and source then Store.putText("npcs", npcID, source) end
        local ts = num(e.timestamp)
        local ago = (ts and last) and floor((last - ts) * 10 + 0.5) or nil
        local spellID = keep(e.spellId) or keep(e.spellID)
        Store.append("DR", ago, textOrSecret(e.event), npcID, (npcID == nil) and source or nil, spellID, keep(e.amount),
          keep(e.overkill), keep(e.school), flag(e.critical), keep(e.currentHP), textOrSecret(e.environmentalType))
        -- killing blow: the entry with the latest time, without times the first
        if not killer and ((ago == 0) or (last == nil and i == 1)) then
          killer = { npcID = npcID, source = (npcID == nil) and source or nil, spellID = spellID,
                     environmentalType = e.environmentalType, event = e.event }
        end
      else
        Store.append("DR", nil, e) -- secret entry: '?'
      end
    end
    if type(DR) == "table" then maxHP = keep(call(DR.GetRecapMaxHealth)) end
  end
  local c, guess = cause(d, killer)
  Store.append("DC", killer and killer.npcID, killer and killer.source, killer and killer.spellID, c, guess, count, maxHP)
end

local function readRecap(self, d)
  if self.dead ~= d or d.recapDone then return end
  local DR = C_DeathRecap
  local events = type(DR) == "table" and not isSecret(DR) and call(DR.GetRecapEvents) or nil
  if events == nil and d.tries < RECAP_TRIES and type(DR) == "table" then
    d.tries = d.tries + 1
    Core.after(self, 1, function(s) readRecap(s, d) end)
    return
  end
  d.recapDone = true
  writeRecap(self, d, events)
end

local revived -- forward declaration (way back, below)

handlers.PLAYER_DEAD = function(self)
  local old = self.dead
  -- a duplicate event is detected by time only; an older open death (resurrection never reported) is closed
  if old and old.at and GetTime() - old.at < DUP_WINDOW then return end
  if old then revived(self, "unknown", 1) end
  local mapID, px, py = ns.Zone.raw()
  local x, y
  if px then x, y = ns.Zone.coord(px), ns.Zone.coord(py) end
  local combat = self.inCombat or InCombatLockdown() == true
    or (self.combatEndAt ~= nil and GetTime() - self.combatEndAt <= COMBAT_GRACE)
  local d = {
    at = GetTime(), mapID = mapID, combat = combat, tries = 0, death = px and { x = px, y = py } or nil,
    breath = timerActive(self, "BREATH"), fatigue = timerActive(self, "EXHAUSTION"),
  }
  self.dead = d
  self.spiritAt, self.corpseAt, self.resAt, self.spiritOffer, self.resOffer = nil, nil, nil, nil, nil
  self.gossipAt = nil
  Store.append("DE", playerLevel(), mapID, x, y, call(IsInInstance) == true and 1 or 0, combat and 1 or 0, ns.Zone.sub())
  Core.emit("FC_DEATH")
  Core.after(self, RECAP_DELAY, function(s) readRecap(s, d) end)
end

-- Way back

-- corpse position (map fractions) on the death map; nil if unreadable
local function corpsePos(mapID)
  if not mapID or type(C_DeathInfo) ~= "table" then return nil end
  local pos = call(C_DeathInfo.GetCorpseMapPosition, mapID)
  if type(pos) ~= "table" or isSecret(pos) then return nil end
  local x, y = call(pos.GetXY, pos)
  x, y = num(x), num(y)
  if x and y then return { x = x, y = y } end
  return nil
end

-- 'Resurrection Sickness' aura fresh? true = yes, false = old, nil = unreadable (secret values).
local function freshAura(aura)
  if type(aura) ~= "table" or isSecret(aura) then return nil end
  local duration, expires = num(aura.duration), num(aura.expirationTime)
  if duration and expires and duration > 0 then
    return (duration - (expires - GetTime())) <= AURA_FRESH
  end
  return true
end

-- Resurrection Sickness (secret-safe): true = present and fresh, false = absent, nil = unreadable.
local function sicknessState()
  local A = C_UnitAuras
  if type(A) ~= "table" or isSecret(A) then return nil end
  if type(A.GetPlayerAuraBySpellID) == "function" then
    local readable = false
    for _, id in ipairs(SICKNESS_IDS) do
      local ok, aura = pcall(A.GetPlayerAuraBySpellID, id)
      if ok and not isSecret(aura) then
        readable = true
        if aura ~= nil and freshAura(aura) ~= false then return freshAura(aura) end
      end
    end
    if readable then return false end
  end
  if type(A.GetAuraDataByIndex) == "function" then -- fallback: scan debuffs in order
    local sawSecret = false
    for i = 1, AURA_SCAN do
      local ok, aura = pcall(A.GetAuraDataByIndex, "player", i, "HARMFUL")
      if not ok then return nil end
      if aura == nil then break end
      if isSecret(aura) or type(aura) ~= "table" then
        sawSecret = true
      else
        local sid = num(aura.spellId)
        if sid == nil then
          sawSecret = true
        else
          for _, id in ipairs(SICKNESS_IDS) do
            if sid == id and freshAura(aura) ~= false then return freshAura(aura) end
          end
        end
      end
    end
    if sawSecret then return nil end
    return false
  end
  return nil
end

local function snapshot(d)
  local mapID, x, y = ns.Zone.here()
  return { mapID = mapID, x = x, y = y, seconds = d.at and floor(GetTime() - d.at) or nil }
end

local function writeBack(how, guess, snap)
  Store.append("DB", how, guess, snap.seconds, snap.mapID, snap.x, snap.y)
end

revived = function(self, how, guess)
  local d = self.dead
  self.dead = nil
  writeBack(how, guess, snapshot(d))
end

handlers.PLAYER_ALIVE = function(self)
  local d = self.dead
  if not d then return end
  if call(UnitIsGhost, "player") == true then
    d.ghost = true -- ghost released; remember the corpse to tell resurrection kinds apart
    d.corpse = corpsePos(d.mapID)
    if not d.corpse then -- the corpse position may not exist right after release: ask once more later
      Core.after(self, 1, function()
        if d.corpse == nil then d.corpse = corpsePos(d.mapID) end
      end)
    end
    return
  end
  revived(self, "res", 0) -- resurrected without releasing the ghost
end

-- way back on coming alive as a ghost: how, guess, final (false = the aura may still arrive).
-- Order: safe hooks, then the aura (spirit healer), then distance to the corpse (or death place).
local function classify(self, d)
  if recent(self.spiritAt) then return "spirit", 0, true end
  if recent(self.corpseAt) then return "corpse", 0, true end
  if sicknessState() == true then return "spirit", 0, true end
  if recent(self.resAt) then return "res", 0, true end
  local mapID, px, py = ns.Zone.raw()
  local ref = d.corpse or d.death -- corpse per client, else the death place
  if ref and px and mapID == d.mapID then
    local dx, dy = px - ref.x, py - ref.y
    if dx * dx + dy * dy <= CORPSE_NEAR * CORPSE_NEAR then return "corpse", 1, true end
    if recent(self.resOffer) and not recent(self.spiritOffer) and not gossipOffered(self) then return "res", 1, false end
    return "spirit", 1, false
  end
  if recent(self.spiritOffer) or gossipOffered(self) then return "spirit", 1, false end
  return "unknown", 1, false
end

handlers.PLAYER_UNGHOST = function(self)
  local d = self.dead
  if not d then return end
  local how, guess, final = classify(self, d)
  if final then return revived(self, how, guess) end
  -- guessed way: record place and duration now, wait briefly for the aura (spirit healer)
  local snap = snapshot(d)
  self.dead = nil
  local function write()
    if sicknessState() == true then how, guess = "spirit", 0 end
    writeBack(how, guess, snap)
  end
  if not Core.after(self, AURA_WAIT, write) then write() end
end

function Death:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("Death", Death)
