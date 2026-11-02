-- Collector 'Afk' (away time for the Chronik). A phase starts when UnitIsAFK("player") turns true (PLAYER_FLAGS_CHANGED, plus a
-- check every HEARTBEAT s as a safety net) and ends when it turns false. At the end one AF line is written and the character's totals grow:
-- counters.afk = { seconds, phases }, snapshots.state.afk.longest. Time basis is the wall clock (time()), like all other times of the
-- addon; AFK time is part of the /played time because the character stays logged in.
-- The open phase is persisted in snapshots.state.afk = { since, seen, longest } (seen = last heartbeat), so that
--   reload  -> the phase continues if the flag is still set (a short gap is bridged), otherwise it ends at 'seen',
--   logout  -> the phase ends right away (why = logout),
--   crash   -> the phase ends at the next start at 'seen' (why = gap).
-- No double counting: a phase is closed exactly once (the state is cleared before anything is written). Secret values count as 'unknown'.
local _, ns = ...
local Core, Store = ns.Core, ns.Store

local floor = math.floor

local Afk = ns.Afk or {}
ns.Afk = Afk

Afk.MIN_PHASE = 10         -- seconds: shorter phases are ignored (flag flicker)
Afk.MAX_PHASE = 86400      -- seconds: upper bound of one phase (clock jump, damaged data)
Afk.HEARTBEAT = 60         -- seconds: poll and 'seen' mark while the phase is open
Afk.CONTINUE_GAP = 120     -- seconds: a persisted phase continues after a reload if its 'seen' is at most this old

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a = pcall(fn, ...)
  if not ok then return nil end
  return a
end

-- is the player marked away? -> true | false | nil (unknown: secret or unusable value). Older clients return 1 / nil.
local function readAfk()
  local v = call(UnitIsAFK, "player")
  if isSecret(v) then return nil end
  if v == true or v == 1 then return true end
  if v == false or v == nil or v == 0 then return false end
  return nil
end

-- persisted state (snapshots.state.afk), numbers only
function Afk.state()
  local char = Store.char()
  local st = char and char.snapshots and char.snapshots.state
  local a = type(st) == "table" and st.afk or nil
  if type(a) ~= "table" or isSecret(a) then return {} end
  return { since = num(a.since), seen = num(a.seen), longest = num(a.longest) }
end

local function saveState(since, seen, longest)
  local t = {}
  if since then t.since = floor(since) end
  if seen then t.seen = floor(seen) end
  if longest and longest > 0 then t.longest = floor(longest) end
  if next(t) == nil then return Store.dropSnapshot("state", "afk") end
  return Store.putSnapshot("state", "afk", t, true)
end

-- ends the open phase at endT: clears the state first (never written twice), then counts and logs
local function closePhase(self, endT, why, here)
  local since = self.since
  self.since = nil
  local st = Afk.state()
  local longest = st.longest
  saveState(nil, nil, longest)
  if not since or not Store.ready() then return false end
  endT = num(endT)
  if not endT or endT <= since then return false end
  local secs = floor(endT - since)
  if secs > Afk.MAX_PHASE then secs = Afk.MAX_PHASE end
  if secs < Afk.MIN_PHASE then return false end
  Store.count("afk", "seconds", secs)
  Store.count("afk", "phases", 1)
  if not longest or secs > longest then saveState(nil, nil, secs) end
  local mapID
  if here then mapID = ns.Zone.here() end
  local level = num(call(UnitLevel, "player"))
  Store.append("AF", secs, level and floor(level) or nil, mapID, why)
  return true
end

local function openPhase(self, now)
  self.since = now
  saveState(now, now, Afk.state().longest)
end

-- compares the flag with the open phase and starts or ends it
local function check(self)
  if not Store.ready() then return end
  local v = readAfk()
  if v == nil then return end
  if v and not self.since then
    openPhase(self, time())
  elseif not v and self.since then
    closePhase(self, time(), "end", true)
  end
end

local function beat(self)
  check(self)
  if self.since and Store.ready() then saveState(self.since, time(), Afk.state().longest) end
end

local Collector = {
  requires = { "UnitIsAFK" },
  events = { "PLAYER_LOGOUT" },
  unitEvents = { PLAYER_FLAGS_CHANGED = { "player" } },
}
local handlers = {}

handlers.PLAYER_FLAGS_CHANGED = check

-- reload (flag from Store.reloadPending): the phase stays open, 'seen' marks the last moment; real logout: the phase ends
handlers.PLAYER_LOGOUT = function(self)
  if not self.since then return end
  local now = time()
  if Store.reloadPending() then
    saveState(self.since, now, Afk.state().longest)
  else
    closePhase(self, now, "logout", true)
  end
end

function Collector:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

-- start after login or reload: resume a persisted phase or close it at its last known moment
function Collector:init()
  self.since = nil
  if Store.ready() then
    local st = Afk.state()
    local now = time()
    local v = readAfk()
    if st.since then
      local seen = st.seen or st.since
      if v ~= false and now >= seen and now - seen <= Afk.CONTINUE_GAP then
        self.since = st.since -- reload in the middle of the phase (or flag unreadable): it goes on
      else
        self.since = st.since
        closePhase(self, seen, "gap", false)
      end
    end
    if v == true and not self.since then openPhase(self, now) end
  end
  Core.ticker(self, Afk.HEARTBEAT, beat)
end

ns.RegisterCollector("Afk", Collector)
