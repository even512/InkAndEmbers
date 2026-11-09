-- Reunion model ("reunion in the tooltip"): a lookup table built once from the companions (WB/WV), the dungeon groups and the
-- campfire rounds (LF), so that the tooltip of a player you travelled with can show up to two memory lines. Pure read logic,
-- nothing is written to the saved variables; the table lives in memory only.
-- Person key: name-realm exactly as collectors/Companions.lua writes it (the first key); the player GUID is a second key and only
-- exists for campfire guests (the LF line carries it). Dungeon groups and companions have name-realm only.
-- Building: Reunion.start(index) works in time slices (a few dungeon runs per C_Timer.After(0), not in combat), so that
-- Dungeons.group over many runs causes no stutter; until it is finished the lookup uses the partial state. The lookup itself
-- (Reunion.lookup) is two table accesses plus formatting: no log scan, no aggregate, no build.
-- Display texts are made display-ready while building (Sanitize.display); dates are stored as day/month numbers only.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Reunion = {}
Journal.ReunionModel = Reunion

local format, floor, huge = string.format, math.floor, math.huge

Reunion.PEOPLE_MAX = 500      -- people in the table (like FireMates.PEOPLE_MAX)
Reunion.RUNS_MAX = 150        -- dungeon runs read (the newest)
Reunion.RUNS_PER_SLICE = 8    -- runs per time slice
Reunion.COMBAT_RETRY = 2      -- seconds to wait while a slice is held up by combat
Reunion.NAME_MAX = 48

local state = { gen = 0, tbl = nil, building = false, done = false, runsDone = 0, runsTotal = 0, builds = 0, errors = 0,
  lastError = nil, people = 0 }
Reunion.state = state
local seen = setmetatable({}, { __mode = "k" }) -- indexes already started (weak: holds no index alive)

local function finite(v)
  return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return ok and not isSecret(v) and v == true
end

local function after(sec, fn)
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(sec, fn)
    return true
  end
  return false
end

-- texts (display-ready); locale scope "m.Reunion" (English in locales/enUS_model.lua). Always the "Ihr" form: the tooltip is read
-- by the player, the du/Ihr setting of the campfire talk only applies to sent chat lines.

local TX = ns.Locale.ns("m.Reunion", {
  dateShort = "{d}.{m}.",
  dungeonDone = "{dungeon} zusammen geschafft, {date}",
  dungeonDoneAny = "Einen Dungeon zusammen geschafft, {date}",
  dungeonFought = "Mit Euch in {dungeon} gekämpft, {date}",
  dungeonFoughtAny = "Mit Euch in einem Dungeon gekämpft, {date}",
  fire = "Saß mit Euch am Feuer in {zone}, {date}",
  fireAny = "Saß mit Euch am Feuer, {date}",
  together = "Mit Euch unterwegs, zuletzt {date}",
  togetherZone = "Mit Euch unterwegs, zuletzt {date} in {zone}",
  times = " ({n}×)",
})
Reunion.TEXT = TX

local function shown(v, n)
  if type(v) ~= "string" or isSecret(v) then return nil end
  local S = ns.Sanitize
  return S and S.display(v, n or Reunion.NAME_MAX) or nil
end

local function dayOf(index, t)
  local Idx = Journal.Index
  if not (Idx and type(Idx.dateOf) == "function") or not finite(t) then return nil, nil end
  local d, m = Idx.dateOf(index, t)
  if not finite(d) or not finite(m) then return nil, nil end
  return floor(d), floor(m)
end

local function dateText(d, m)
  return TX("dateShort", { d = format("%02d", d), m = format("%02d", m) })
end

-- table ------------------------------------------------------------------------------------------------------------------

local function newTable()
  return { byName = {}, byGuid = {}, n = 0 }
end

-- the entry of a person: guid first, then name-realm; created if absent (up to PEOPLE_MAX). Both keys point to the same entry.
local function entryFor(t, full, guid)
  if type(full) ~= "string" or full == "" or isSecret(full) then full = nil end
  if type(guid) ~= "string" or guid == "" or isSecret(guid) then guid = nil end
  if not full and not guid then return nil end
  local e = (guid and t.byGuid[guid]) or (full and t.byName[full]) or nil
  if not e then
    if t.n >= Reunion.PEOPLE_MAX then return nil end
    e = {}
    t.n = t.n + 1
  end
  if guid and not t.byGuid[guid] then t.byGuid[guid] = e end
  if full and not t.byName[full] then t.byName[full] = e end
  return e
end

-- phase 1: campfire guests (real rounds only; the trial rounds of the retail simulation carry sim)
local function stepFire(job)
  local FM = Journal.FireMates
  if not (FM and type(FM.aggregate) == "function") then return end
  local res = FM.aggregate(job.index)
  for _, p in ipairs(type(res) == "table" and res.list or {}) do
    if type(p) == "table" and (p.full or p.guid) then
      local n, last = 0, nil
      for _, v in ipairs(type(p.visits) == "table" and p.visits or {}) do
        if type(v) == "table" and not v.sim and finite(v.t) then
          n = n + 1
          if not last or v.t >= last.t then last = v end
        end
      end
      if n > 0 then
        local d, m = dayOf(job.index, last.t)
        if d then
          local e = entryFor(job.t, p.full, p.guid)
          if e then e.fire = { d = d, m = m, zone = shown(last.zone, 40), n = n } end
        end
      end
    end
  end
end

-- phase 2: companions (fallback line): last time travelled together
local function stepTogether(job)
  local C = Journal.Companions
  if not (C and type(C.aggregate) == "function") then return end
  local res = C.aggregate(job.index)
  local count = 0
  for _, p in ipairs(type(res) == "table" and res.list or {}) do
    if count >= Reunion.PEOPLE_MAX then break end
    count = count + 1
    if type(p) == "table" and type(p.name) == "string" then
      local d, m = dayOf(job.index, p.lastT)
      if d then
        local e = entryFor(job.t, p.name, nil)
        if e then e.together = { d = d, m = m, zone = shown(p.lastZone, 40) } end
      end
    end
  end
end

-- phase 3: the runs to read (newest first, at most RUNS_MAX)
local function prepareRuns(job)
  local D = Journal.Dungeons
  local list = {}
  if D and type(D.build) == "function" then
    local res = D.build(job.index)
    for _, run in ipairs(type(res) == "table" and res.runs or {}) do
      if type(run) == "table" and finite(run.t1) then list[#list + 1] = run end
    end
  end
  table.sort(list, function(a, b) return a.t1 > b.t1 end)
  for i = #list, Reunion.RUNS_MAX + 1, -1 do list[i] = nil end
  job.runs, job.pos = list, 1
  state.runsTotal, state.runsDone = #list, 0
end

local function takeRun(job, run)
  local D = Journal.Dungeons
  local group = D.group(job.index, run)
  if type(group) ~= "table" or #group == 0 then return end
  local done = nil
  for _, member in ipairs(group) do
    local e = type(member) == "table" and entryFor(job.t, member.name, nil) or nil
    if e then
      local cur = e.dungeon
      if not cur then
        local d, m = dayOf(job.index, run.t1)
        if d then
          if done == nil then
            local ok, c = pcall(D.completion, run)
            done = ok and type(c) == "table" and c.complete == true or false
          end
          e.dungeon = { d = d, m = m, name = shown(run.name, 48), done = done, n = 1, inst = run.instanceID }
        end
      elseif cur.inst == run.instanceID then
        cur.n = cur.n + 1 -- older run of the same dungeon: only the count grows, the newest one stays
      end
    end
  end
end

-- phase 4: a few runs per slice; true when all are read
local function stepRuns(job)
  local D = Journal.Dungeons
  local list = job.runs or {}
  if not (D and type(D.group) == "function") then return true end
  local last = math.min(#list, job.pos + Reunion.RUNS_PER_SLICE - 1)
  for i = job.pos, last do
    local ok, err = pcall(takeRun, job, list[i])
    if not ok then
      state.errors, state.lastError = state.errors + 1, tostring(err)
    end
  end
  job.pos = last + 1
  state.runsDone = last
  return job.pos > #list
end

local PHASES = { stepFire, stepTogether, prepareRuns }

-- one slice; true when the build is finished
local function runStep(job)
  if job.phase <= #PHASES then
    local fn = PHASES[job.phase]
    job.phase = job.phase + 1
    local ok, err = pcall(fn, job)
    if not ok then
      state.errors, state.lastError = state.errors + 1, tostring(err)
      if job.phase > #PHASES and not job.runs then return true end -- no run list: nothing more to read
    end
    return false
  end
  local ok, done = pcall(stepRuns, job)
  if not ok then
    state.errors, state.lastError = state.errors + 1, tostring(done)
    return true
  end
  return done
end

local function finish(job)
  if job.gen ~= state.gen then return end
  state.tbl, state.building, state.done = job.t, false, true
  state.people = job.t.n
  state.builds = state.builds + 1
end

local function pump(job)
  if job.gen ~= state.gen then return end -- a newer build replaced this one
  if inCombat() then
    if not after(Reunion.COMBAT_RETRY, function() pump(job) end) then finish(job) end
    return
  end
  if runStep(job) then
    finish(job)
  elseif not after(0, function() pump(job) end) then
    while not runStep(job) do end -- no timers: finish at once
    finish(job)
  end
end

-- Starts a build for the index (once per index object, opts.force overrides). Returns true if a build was started.
-- opts.sync builds at once, without time slices (tests).
function Reunion.start(index, opts)
  opts = opts or {}
  if type(index) ~= "table" or isSecret(index) then return false end
  if seen[index] and not opts.force then return false end
  seen[index] = true
  state.gen = state.gen + 1
  local job = { gen = state.gen, index = index, t = newTable(), phase = 1 }
  state.building, state.done = true, false
  state.runsDone, state.runsTotal = 0, 0
  if not state.tbl then state.tbl = job.t end -- first build: the partial state is visible
  if opts.sync then
    while not runStep(job) do end
    finish(job)
  elseif not after(0, function() pump(job) end) then
    while not runStep(job) do end
    finish(job)
  end
  return true
end

function Reunion.ready() return state.tbl ~= nil end
function Reunion.building() return state.building end
function Reunion.count() return state.tbl and state.tbl.n or 0 end

-- forgets the table and everything started (tests, character switch)
function Reunion.clear()
  state.gen = state.gen + 1
  state.tbl, state.building, state.done = nil, false, false
  state.runsDone, state.runsTotal, state.people = 0, 0, 0
  state.builds, state.errors, state.lastError = 0, 0, nil
  seen = setmetatable({}, { __mode = "k" })
end

-- lookup -----------------------------------------------------------------------------------------------------------------

local function withTimes(text, n)
  if finite(n) and n > 1 then return text .. TX("times", { n = format("%d", n) }) end
  return text
end

local function linesOf(e)
  local out = {}
  local d = e.dungeon
  if d then
    local date = dateText(d.d, d.m)
    local key = (d.done and "dungeonDone" or "dungeonFought") .. (d.name and "" or "Any")
    out[#out + 1] = withTimes(TX(key, { dungeon = d.name, date = date }), d.n)
  end
  local f = e.fire
  if f then
    local date = dateText(f.d, f.m)
    out[#out + 1] = withTimes(TX(f.zone and "fire" or "fireAny", { zone = f.zone, date = date }), f.n)
  end
  if #out == 0 and e.together then
    local g = e.together
    out[1] = TX(g.zone and "togetherZone" or "together", { zone = g.zone, date = dateText(g.d, g.m) })
  end
  return out
end

-- lines (at most two, most important first: dungeon, campfire; only without both the fallback "travelled together") for a
-- person: guid (if readable and known) first, otherwise name-realm. nil if the person is unknown. Never uses a secret value
-- as a table key.
function Reunion.lookup(full, guid)
  local t = state.tbl
  if not t then return nil end
  local e
  if type(guid) == "string" and not isSecret(guid) then e = t.byGuid[guid] end
  if not e and type(full) == "string" and not isSecret(full) then e = t.byName[full] end
  if not e then return nil end
  local lines = linesOf(e)
  if #lines == 0 then return nil end
  return lines
end
