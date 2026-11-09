-- Zone progress ("Zone abgeschlossen", change "zone-abgeschlossen", Forever only): how many of the countable quests of a zone the
-- player has done, for the chapter card (journal/Frame.lua) and the medal "Zonenkenner" (journal/model/Chronik.lua, live counter
-- counters.zonedone). Pure logic over the readers of journal/model/OpenQuests.lua (zoneIndex, record, statesOf, generation, listen)
-- and the shared counting of journal/model/QuestTally.lua; nothing of it goes into the cached journey model.
--
-- Countable quests of a zone: every quest with a fitting giver (faction) on the zone map (OpenQuests.zoneIndex, a quest with
-- givers in two zones counts in both), without group/dungeon/raid/PvP/event (g), repeatable (r), profession/reputation/spell/max
-- level (s, not checkable) and category quests without a class (k; class quests count when the class fits). Other faction, race
-- or class: out (foreign). Quests voided by a done/accepted alternative: out; alternatives that exclude each other count once.
-- Level too low and locked quests count (the share grows with the journey). Quests with unsure beta data count (marked in the
-- tooltip). Zones with fewer than ZoneProgress.MIN_QUESTS countable quests show no share and give no medal (small).
--
-- PUBLIC API (all results read-only, shared per state; nothing loads or computes before the first call):
--   ZoneProgress.available()      -> true | false, reason   data of OpenQuests loaded (never loads), not retail
--   ZoneProgress.of(zoneID)       -> result | nil, reason   { mapID, total, done, log, open, locked, foreign, voided, pct
--        (floor(done * 100 / total), 100 only when complete, nil without quests), complete, small (total < MIN_QUESTS), unsure
--        (counted quests with unsure beta data), partial (Chronik index not finished: preliminary) }. In combat only a cached
--        result (else nil, "COMBAT"). reasons: NO_ZONE (world/continent/invalid), RETAIL, COMBAT, OpenQuests' load reasons.
--   ZoneProgress.openList(zoneID, max) -> rows, n   the not completed quests (open, accepted, locked) sorted by level and name:
--        at most max rows { id, name (display), level, state, unsure }, n = all of them
--   ZoneProgress.tooltip(zoneID)  -> lines, colors | nil   display-ready tooltip of the chapter card row
--   ZoneProgress.summary()        -> { zones, complete, partial } | nil   result of the last sweep (zones with a share)
--   ZoneProgress.sweep()          -> true | false, reason   computes every zone (time budget per frame, never in combat) and
--        records zones that became complete in counters.zonedone (once, never removed). The first sweep of a character writes
--        the zones already complete silently (snapshots.state.zoneBaseline, then Toast.rebase: no toast storm for veterans).
--        Nothing is written in the test mode of OpenQuests or while the Chronik index is not finished.
--   ZoneProgress.onChange(fn)     -> true   fn() after the quest state changed (OpenQuests.listen) or a sweep finished
--   ZoneProgress.diagLine()       -> "Zonen: 24 berechnet, 3 abgeschlossen" | nil (retail)
-- Automatic part (only on a real Forever client, MapSpace.client() == "data", or ZoneProgress.AUTO = true): LOGIN_DELAY s after
-- login (not in combat) the quest data is loaded (decision F6) and swept; every change notice of OpenQuests sweeps again after
-- SWEEP_DELAY s.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local ZP = {}
Journal.ZoneProgress = ZP

local floor, min, sort, concat, tostring = math.floor, math.min, table.sort, table.concat, tostring

ZP.MIN_QUESTS = 10      -- countable quests a zone needs for a share and the medal (decision F5)
ZP.TIP_MAX = 8          -- open quests named in the tooltip
ZP.BUDGET_MS = 4        -- sweep work per frame (debugprofilestop)
ZP.LOGIN_DELAY = 30     -- seconds after login until the data is loaded and swept (decision F6)
ZP.COMBAT_WAIT = 2      -- seconds between checks while in combat
ZP.SWEEP_DELAY = 2      -- seconds after a change notice until the sweep
ZP.GROUP = "zonedone"   -- counter group of the medal (Store.COUNTER_LIMITS)
ZP.BASELINE = "zoneBaseline" -- snapshots.state key: the first sweep of this character is done
ZP.AUTO = nil           -- true = automatic part also outside a Forever client (tests)
ZP.TIP_COLOR = { label = { 0.62, 0.58, 0.50 }, done = { 0.55, 0.85, 0.50 }, open = { 1.00, 0.82, 0.30 } }

-- texts (German here, English in locales/enUS_model.lua, scope "m.ZoneProgress")
local T = ns.Locale.ns("m.ZoneProgress", {
  tipHead = "In dieser Zone habt Ihr %s von %s Quests erledigt.",
  tipComplete = "Alle zählbaren Quests dieser Zone sind erledigt.",
  tipOpen = "Noch offen:",
  tipLine = "%s (Stufe %s)",
  tipLineLog = "%s (Stufe %s, angenommen)",
  tipLineLocked = "%s (Stufe %s, gesperrt)",
  tipMore = "… und %s weitere",
  tipUnsure_one = "%s Quest mit unsicheren Beta-Daten",
  tipUnsure_other = "%s Quests mit unsicheren Beta-Daten",
  tipRule = "Quests ohne Kartenpunkt, Gruppen-, wiederholbare und Berufsquests zählen nicht.",
  tipPartial = "Das Tagebuch wird noch gelesen: vorläufiger Stand.",
  diag = "Zonen: %s berechnet, %s abgeschlossen",
  diagNone = "Zonen: noch nicht berechnet (%s)",
  notSwept = "Daten noch nicht geladen",
})
ZP.TEXT = T

local EMPTY = {}

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return ok and not isSecret(v) and v == true
end

local function clock()
  local f = rawget(_G, "debugprofilestop")
  if type(f) ~= "function" then return 0 end
  local ok, v = pcall(f)
  return (ok and num(v)) or 0
end

local function after(sec, fn)
  if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return false end
  return pcall(C_Timer.After, sec, fn) == true
end

local function safe(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and ns.Core and ns.Core.coreError then ns.Core.coreError(err) end
  return ok
end

local OQ = Journal.OpenQuests
local QT = Journal.QuestTally

-- module state: per-state cache (records, states, results), the running sweep, the last summary, listeners
local M = { c = nil, job = nil, last = nil, listeners = {}, planned = false, loginPlanned = false }
ZP._state = M

-- Retail client: nothing (the test mode and OpenQuests.ALLOW_RETAIL keep the data, like DungeonQuests)
local function retail()
  return OQ == nil or (OQ.retailClient() and not (OQ.test() ~= nil or OQ.ALLOW_RETAIL))
end

-- automatic loading and sweeping: only on a real Forever client (or when switched on for tests)
local function auto()
  if ZP.AUTO == true then return true end
  local ms = Journal.MapSpace
  return ms ~= nil and type(ms.client) == "function" and ms.client() == "data"
end

function ZP.available()
  if retail() then return false, OQ and "RETAIL" or "NO_DATA" end
  local st = OQ.status()
  if not (st and st.loaded) then return false, (st and st.reason) or "NOT_LOADED" end
  return true
end

-- zone key: a whole map ID > 0 that is a zone (not the world or a continent)
local function zoneKey(v)
  v = num(v)
  if not v or v <= 0 or v ~= floor(v) or v > 2147483647 then return nil end
  if OQ and OQ.NO_ZONE and OQ.NO_ZONE[v] then return nil end
  return v
end
ZP.zoneKey = zoneKey

-- cache of one state: OpenQuests generation (events, names), profile and zone index (identity changes with the data)
local function profileKey()
  local p = OQ.profileInfo()
  return concat({ tostring(p.race), tostring(p.class), tostring(p.level), tostring(p.faction), p.test and "T" or "-" }, "|")
end

local function cache()
  local g, n = OQ.generation()
  local key = profileKey()
  local zi = OQ.zoneIndex()
  local c = M.c
  if not c or c.g ~= g or c.n ~= n or c.key ~= key or c.zi ~= zi then
    c = { g = g, n = n, key = key, zi = zi, rec = {}, st = {}, res = {} }
    M.c = c
  end
  return c
end

local function rec(c, id)
  local r = c.rec[id]
  if r == nil then
    r = OQ.record(id, true) or false
    c.rec[id] = r
  end
  return r or nil
end

local function loadStates(c, ids)
  local need
  for _, id in ipairs(ids) do
    if c.st[id] == nil then
      need = need or {}
      need[#need + 1] = id
    end
  end
  if need then
    local got = OQ.statesOf(need)
    for _, id in ipairs(need) do c.st[id] = got[id] or false end
  end
end

-- countable kind: no group/repeatable/special requirement, no category quest without a class
local function countable(r)
  local f = r.flags or EMPTY
  if f.g or f.r or f.s then return false end
  if f.k and (r.classes or 0) == 0 then return false end
  return true
end

local function compute(c, id)
  local list = {}
  for _, qid in ipairs((c.zi and c.zi[id]) or EMPTY) do
    local r = rec(c, qid)
    if r and countable(r) then list[#list + 1] = qid end
  end
  local n = QT.count(list, function(x) return rec(c, x) end, function(x) return c.st[x] or nil end,
    function(l) loadStates(c, l) end, { units = true })
  local res = { mapID = id, total = n.total, done = n.done, log = n.log, open = n.open, locked = n.locked, foreign = n.foreign,
    voided = n.voided, complete = n.complete, partial = n.partial == true, small = n.total < ZP.MIN_QUESTS, unsure = 0,
    units = n.units }
  if n.total > 0 then res.pct = n.complete and 100 or min(99, floor(n.done * 100 / n.total)) end
  for _, u in ipairs(n.units or EMPTY) do
    local r = rec(c, u.id)
    if r and r.unsure then res.unsure = res.unsure + 1 end
  end
  return res
end

-- change notices of OpenQuests: registered on first use (a listener makes OpenQuests bundle every event in a timer; an
-- add-on state without a zone share needs none)
local ensureListen

function ZP.of(zoneID)
  local id = zoneKey(zoneID)
  if not id then return nil, "NO_ZONE" end
  local ok, why = ZP.available()
  if not ok then return nil, why end
  ensureListen()
  local combat = inCombat()
  local c = combat and M.c or cache()
  local r = c and c.res[id]
  if r then return r end
  if combat then return nil, "COMBAT" end
  r = compute(c, id)
  c.res[id] = r
  return r
end

local STATE_RANK = { log = 1, open = 2, locked = 3 }

function ZP.openList(zoneID, maxRows)
  local res = ZP.of(zoneID)
  if not res then return {}, 0 end
  local c = M.c
  local rows = {}
  for _, u in ipairs(res.units or EMPTY) do
    if u.state ~= "done" then
      local r = c and rec(c, u.id)
      rows[#rows + 1] = { id = u.id, level = r and (r.level or r.minLevel) or nil, state = u.state, unsure = r and r.unsure or false }
    end
  end
  sort(rows, function(a, b)
    local la, lb = a.level or 999, b.level or 999
    if la ~= lb then return la < lb end
    if STATE_RANK[a.state] ~= STATE_RANK[b.state] then return (STATE_RANK[a.state] or 9) < (STATE_RANK[b.state] or 9) end
    return a.id < b.id
  end)
  local n = #rows
  maxRows = num(maxRows) and floor(maxRows) or n
  local out = {}
  for i = 1, min(n, maxRows) do
    local row = rows[i]
    local full = OQ.record(row.id) -- named (display-ready, already sanitized by OpenQuests)
    row.name = (full and full.name) or OQ.TEXT("questFallback", row.id)
    out[i] = row
  end
  return out, n
end

function ZP.tooltip(zoneID)
  local res = ZP.of(zoneID)
  if not res or res.small then return nil end
  local C = ZP.TIP_COLOR
  local lines, colors = {}, {}
  local function add(text, color)
    lines[#lines + 1] = text
    colors[#lines] = color
  end
  add(OQ.mapName(res.mapID) or "")
  add(T("tipHead", res.done, res.total), res.complete and C.done or nil)
  if res.complete then
    add(T.tipComplete, C.done)
  else
    local rows, n = ZP.openList(res.mapID, ZP.TIP_MAX)
    add(T.tipOpen, C.label)
    for _, row in ipairs(rows) do
      local key = row.state == "log" and "tipLineLog" or row.state == "locked" and "tipLineLocked" or "tipLine"
      add(T(key, row.name, row.level or "?"), row.state == "open" and C.open or nil)
    end
    if n > #rows then add(T("tipMore", n - #rows), C.label) end
  end
  if res.unsure > 0 then
    local L = ns.Locale
    local key = (L and L.plural) and L.plural(res.unsure, "tipUnsure_one", "tipUnsure_other") or "tipUnsure_other"
    add(T(key, res.unsure), C.label)
  end
  if res.partial then add(T.tipPartial, C.label) end
  add(T.tipRule, C.label)
  add(OQ.footer(), C.label)
  return lines, colors
end

function ZP.summary()
  return M.last
end

function ZP.onChange(fn)
  if type(fn) ~= "function" then return false end
  M.listeners[#M.listeners + 1] = fn
  return true
end

local function notify()
  for _, fn in ipairs(M.listeners) do pcall(fn) end
end

-- ---------------------------------------------------------------- sweep and medal counter

local function baselineDone(char)
  local st = type(char.snapshots) == "table" and char.snapshots.state or nil
  return type(st) == "table" and st[ZP.BASELINE] ~= nil
end

-- records the complete zones in counters.zonedone (only new keys, value 1). First sweep of the character: silently (baseline
-- mark, Toast.rebase), later: Toast.poke for the medal toast. -> added, baseline
local function commit(list)
  local Store = ns.Store
  local char = Store and Store.current
  if type(char) ~= "table" or type(Store.count) ~= "function" then return 0, false end
  if OQ.test() ~= nil then return 0, false end -- test profile: never into the character's counters
  local baseline = not baselineDone(char)
  local added = 0
  for _, id in ipairs(list) do
    local group = type(char.counters) == "table" and char.counters[ZP.GROUP] or nil
    if not (type(group) == "table" and group[id] ~= nil) and Store.count(ZP.GROUP, id, 1) then added = added + 1 end
  end
  local Toast = Journal.Toast
  if baseline then
    if type(Store.putSnapshot) == "function" then Store.putSnapshot("state", ZP.BASELINE, { v = 1 }, true) end
    if added > 0 and Toast and Toast.rebase then
      Toast.rebase()
      if Toast.poke then Toast.poke() end
    end
  elseif added > 0 and Toast and Toast.poke then
    Toast.poke()
  end
  return added, baseline
end
ZP._commit = commit

local function newJob(c)
  local zones = {}
  for id in pairs(c.zi or EMPTY) do
    if zoneKey(id) then zones[#zones + 1] = id end
  end
  sort(zones)
  return { c = c, zones = zones, i = 1, counted = 0, complete = {}, partial = false }
end

local function finish(job)
  M.job = nil
  M.last = { zones = job.counted, complete = #job.complete, partial = job.partial }
  if not job.partial then
    local ok, added, baseline = pcall(commit, job.complete)
    if ok then M.last.added, M.last.baseline = added, baseline end
  end
  notify()
end

local function step()
  local job = M.job
  if not job then return end
  if inCombat() then
    if not after(ZP.COMBAT_WAIT, function() safe(step) end) then M.job = nil end
    return
  end
  if not ZP.available() then
    M.job = nil
    return
  end
  local c = cache()
  if c ~= job.c then -- the state changed meanwhile: start over with the new one
    job = newJob(c)
    M.job = job
  end
  local t0 = clock()
  while job.i <= #job.zones do
    local r = ZP.of(job.zones[job.i])
    job.i = job.i + 1
    if r then
      if r.partial then job.partial = true end
      if not r.small then
        job.counted = job.counted + 1
        if r.complete then job.complete[#job.complete + 1] = r.mapID end
      end
    end
    if job.i <= #job.zones and clock() - t0 >= ZP.BUDGET_MS then
      if after(0, function() safe(step) end) then return end
    end
  end
  finish(job)
end

function ZP.sweep()
  local ok, why = ZP.available()
  if not ok then return false, why end
  ensureListen()
  if M.job then return true end -- running (it restarts by itself when the state changed)
  if inCombat() then
    M.job = { c = false, zones = {}, i = 1, counted = 0, complete = {}, partial = false }
    if not after(ZP.COMBAT_WAIT, function() safe(step) end) then M.job = nil end
    return false, "COMBAT"
  end
  M.job = newJob(cache())
  step()
  return true
end

function ZP.diagLine()
  if retail() then return nil end
  local s = M.last
  if not s then
    local ok, why = ZP.available()
    return T("diagNone", ok and T.notSwept or (OQ.reasonText and OQ.reasonText(why)) or tostring(why))
  end
  return T("diag", s.zones, s.complete)
end

-- ---------------------------------------------------------------- automatic part (Forever client)

local function planSweep(delay)
  if M.planned then return end
  M.planned = true
  if not after(delay, function()
    M.planned = false
    safe(ZP.sweep)
  end) then
    M.planned = false
    safe(ZP.sweep)
  end
end

local function loginLoad()
  M.loginPlanned = false
  if not auto() or retail() then return end
  if inCombat() then
    M.loginPlanned = after(ZP.COMBAT_WAIT, function() safe(loginLoad) end)
    return
  end
  if OQ.available() then planSweep(0) end -- loads the data addon once (OpenQuests: never in combat, retry after a failure)
end

function ZP.onLogin()
  if M.loginPlanned or not auto() or retail() then return end
  ensureListen()
  M.loginPlanned = after(ZP.LOGIN_DELAY, function() safe(loginLoad) end)
end

ensureListen = function()
  if M.listening or not (OQ and type(OQ.listen) == "function") then return end
  M.listening = true
  OQ.listen(function()
    notify()
    if auto() and ZP.available() then planSweep(ZP.SWEEP_DELAY) end
  end)
end
if ns.Core and ns.Core.on then
  ns.Core.on("PLAYER_LOGIN", function() ZP.onLogin() end)
end
