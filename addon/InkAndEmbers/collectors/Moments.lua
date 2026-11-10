-- Collector 'Moments': automatic milestones and auto screenshots.
-- Milestones come as internal signals from the other collectors (FC_KILL, FC_DEATH, ...) or straight from PLAYER_LEVEL_UP. Screenshots: never in combat, at most one per 10 s;
-- triggers in combat wait for PLAYER_REGEN_ENABLED (+0.5 s), further triggers merge into the next shot; on death after releasing the ghost (or resurrection). File name from local time at SCREENSHOT_SUCCEEDED (Store.putShot).
local _, ns = ...
local Core, Store = ns.Core, ns.Store

local floor, concat, match = math.floor, table.concat, string.match

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
  local ok, a, b = pcall(fn, ...)
  if not ok then return nil end
  return a, b
end

local SHOT_GAP = 10       -- seconds: at most one screenshot per SHOT_GAP
local SHOT_DELAY = 0.5    -- seconds after the trigger or after combat ends
local LEVEL_DELAY = 1.5   -- seconds after level-up (banner)
local EXPECT_TTL = 10     -- seconds: a SCREENSHOT_SUCCEEDED this soon belongs to our own trigger
local DEATH_WAIT = 120    -- seconds: without releasing the ghost, the death is photographed anyway after this
local HIGHLIGHT = { [10] = true, [20] = true, [30] = true, [40] = true, [50] = true, [60] = true }

local function playerLevel()
  return num(call(UnitLevel, "player"))
end

local Moments = {
  requires = { "UnitLevel" },
  events = {
    "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "PLAYER_ALIVE", "PLAYER_UNGHOST", "SCREENSHOT_SUCCEEDED",
    "SCREENSHOT_FAILED",
  },
  signals = {
    "FC_KILL", "FC_CLOSE_WIN", "FC_DEATH", "FC_ZONE_NEW", "FC_CONTINENT_NEW", "FC_INSTANCE", "FC_BOSS", "FC_MOMENT",
  },
}
local handlers = {}

function Moments:init()
  self.reasons, self.reasonSet = {}, {}
  self.levelShot = false
  self.timerOn, self.waitCombat = false, false
  self.lastShot, self.expect = nil, nil
  self.deathToken = 0
end

-- Milestones

local function moment(kind, value, detail)
  Store.append("MO", kind, value, detail, playerLevel(), (ns.Zone.here()), ns.Zone.sub())
end

-- first time per character (snapshots.moments[kind], survives reloads). true if it was the first time.
local function first(kind, value, detail)
  local v = num(value) or str(value)
  if Store.putSnapshot("moments", kind, { seen = true, value = v, detail = detail, level = playerLevel() }) then
    moment(kind, value, detail)
    return true
  end
  return false
end

-- Screenshots

local schedule -- forward declaration

local function fire(self)
  self.timerOn = false
  if #self.reasons == 0 then return end
  if InCombatLockdown() then
    self.waitCombat = true
    return
  end
  local reasons = concat(self.reasons, ",")
  self.reasons, self.reasonSet, self.levelShot = {}, {}, false
  self.lastShot = GetTime()
  self.expect = { reasons = reasons, at = GetTime() }
  if not pcall(Screenshot) then
    self.expect = nil
    Store.count("moments", "screenshot_failed")
  end
end

schedule = function(self)
  if self.timerOn or #self.reasons == 0 then return end
  if InCombatLockdown() then
    self.waitCombat = true
    return
  end
  local now = GetTime()
  local at = now + (self.levelShot and LEVEL_DELAY or SHOT_DELAY)
  if self.lastShot and self.lastShot + SHOT_GAP > at then at = self.lastShot + SHOT_GAP end
  self.timerOn = true
  if not Core.after(self, at - now, fire) then self.timerOn = false end
end

-- setting "Automatische Screenshots" (journal/Options.lua, Pages.setting("autoShots"), default on); without the journal: on
local function autoShotsOn()
  local P = ns.Journal and ns.Journal.Pages
  if not P or type(P.setting) ~= "function" then return true end
  return P.setting("autoShots") ~= false
end

local function queueShot(self, reason)
  if type(Screenshot) ~= "function" or not str(reason) then return end
  if not autoShotsOn() then return end
  if not self.reasonSet[reason] then
    self.reasonSet[reason] = true
    self.reasons[#self.reasons + 1] = reason
  end
  if reason == "levelup" then self.levelShot = true end
  schedule(self)
end

handlers.PLAYER_REGEN_ENABLED = function(self)
  if self.waitCombat then
    self.waitCombat = false
    schedule(self)
  end
end

handlers.SCREENSHOT_SUCCEEDED = function(self)
  local e = self.expect
  self.expect = nil
  local auto = e ~= nil and GetTime() - e.at <= EXPECT_TTL
  local reasons = auto and e.reasons or "manual"
  local level = playerLevel()
  local mapID, x, y = ns.Zone.here()
  local key = Store.putShot({ reasons = reasons, auto = auto, level = level, mapID = mapID })
  if key then Store.append("SH", key, reasons, auto and 1 or 0, level, mapID, x, y, ns.Zone.sub()) end
end

handlers.SCREENSHOT_FAILED = function(self)
  self.expect = nil
  Store.count("moments", "screenshot_failed")
end

-- Triggers

handlers.PLAYER_LEVEL_UP = function(self, level)
  level = num(level) or playerLevel()
  moment("level", level, (level and HIGHLIGHT[floor(level)]) and 1 or 0)
  queueShot(self, "levelup")
end

-- rare and boss as a moment and screenshot. Elite is routine (whole elite areas): no moment, no screenshot;
-- only the very first elite kill outside instances is noted as "first_elite" (no screenshot).
handlers.FC_KILL = function(self, npcID, level, cls)
  cls = str(cls)
  local tag = Core.specialTag(cls, level)
  if not tag then return end
  if tag == "elite" then
    if call(IsInInstance) ~= true then first("first_elite", npcID, cls or tag) end
    return
  end
  moment("kill", npcID, cls or tag)
  first("first_" .. tag, npcID, cls or tag)
  queueShot(self, "kill")
end

handlers.FC_CLOSE_WIN = function(self, pct)
  moment("close_win", pct, 1)
  queueShot(self, "close_win")
end

handlers.FC_DEATH = function(self)
  first("first_death")
  self.deathToken = self.deathToken + 1
  local token = self.deathToken
  self.deathPending = true
  Core.after(self, DEATH_WAIT, function(s)
    if s.deathPending and s.deathToken == token then
      s.deathPending = false
      queueShot(s, "death")
    end
  end)
end

local function afterDeath(self)
  if self.deathPending then
    self.deathPending = false
    queueShot(self, "death")
  end
end
handlers.PLAYER_ALIVE = afterDeath
handlers.PLAYER_UNGHOST = afterDeath

handlers.FC_ZONE_NEW = function(self)
  -- the starting zone of a character (very first login) gets no screenshot: the introduction is on screen then
  if Store.putSnapshot("moments", "start_zone", { seen = true, level = playerLevel() }) then return end
  queueShot(self, "zone")
end

handlers.FC_CONTINENT_NEW = function(self, mapID)
  moment("continent", mapID)
end

handlers.FC_INSTANCE = function(self, instanceID, kind)
  if kind == "party" then
    first("first_dungeon", instanceID)
  elseif kind == "raid" then
    first("first_raid", instanceID)
  end
end

handlers.FC_BOSS = function(self, encounterID)
  moment("boss", encounterID)
  queueShot(self, "boss")
end

-- for later collectors (first blue/purple, mount, reputation, profession): FC_MOMENT(kind, value, detail, shotReason, once)
handlers.FC_MOMENT = function(self, kind, value, detail, shotReason, once)
  kind = str(kind)
  if not kind or not match(kind, "^[%a_]+$") then return end
  if once then
    if not first(kind, value, detail) then return end
  else
    moment(kind, value, detail)
  end
  shotReason = str(shotReason)
  if shotReason and match(shotReason, "^[%a_]+$") then queueShot(self, shotReason) end
end

function Moments:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("Moments", Moments)
