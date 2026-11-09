-- Quest tally: counts a list of quest IDs for the player, shared by journal/model/DungeonQuests.lua ("Dungeon abgeschlossen")
-- and journal/model/ZoneProgress.lua ("Zone abgeschlossen"). Pure logic, no frames, no state of its own: the callers hand in
-- their record/state readers (OpenQuests.record / OpenQuests.statesOf, usually through their per-generation caches).
--
-- PUBLIC API:
--   QuestTally.count(ids, rec, st, load, opts) -> { all, total, done, log, open, locked, foreign, voided, complete, partial[, units] }
--     ids  = list of quest IDs (duplicates are counted once)
--     rec  = function(id) -> record { excl = { id, ... } } | nil   (OpenQuests.record shape)
--     st   = function(id) -> state { state = "done"|"log"|"open"|"locked"|"foreign", partial } | nil
--     load = function(list) | nil: loads the states of the IDs in list before st is asked (one reader call)
--     opts.units = true adds units = { { id, state }, ... }: one entry per counted unit (a quest, or a group of alternatives
--       that exclude each other) with the member that decided the state (best state; ties: the first in ids order); sorted by ID.
--   Rules: foreign quests are left out (counted in foreign); quests voided by a done/accepted alternative (own excl; the other
--   way round, i.e. listed as excl by another quest, only if that exclusion is mutual) are left out (voided); alternatives that
--   exclude each other (mutual) count once with their best state (done > log > open > locked).
--   all = known quests of ids (with record and state); total = counted units; complete = total > 0 and done == total;
--   partial = a state was preliminary (Chronik index not finished).
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local QuestTally = {}
Journal.QuestTally = QuestTally

local sort = table.sort

local EMPTY = {}
local PRIO = { done = 4, log = 3, open = 2, locked = 1 }
QuestTally.PRIO = PRIO

local function hasId(list, id)
  if list then
    for _, x in ipairs(list) do
      if x == id then return true end
    end
  end
  return false
end

function QuestTally.count(ids, rec, st, load, opts)
  local list, seen = {}, {}
  for _, id in ipairs(ids or EMPTY) do
    if not seen[id] then
      seen[id] = true
      list[#list + 1] = id
    end
  end
  local extra = {}
  for _, id in ipairs(list) do
    local r = rec(id)
    if r and r.excl then
      for _, x in ipairs(r.excl) do
        if not seen[x] then
          seen[x] = "peer"
          extra[#extra + 1] = x
        end
      end
    end
  end
  if load then
    load(list)
    load(extra)
  end
  local res = { all = 0, total = 0, done = 0, log = 0, open = 0, locked = 0, foreign = 0, voided = 0 }
  local cand, rev = {}, {}
  for _, id in ipairs(list) do
    local r, s = rec(id), st(id)
    if r and s then
      res.all = res.all + 1
      if s.partial then res.partial = true end
      if s.state == "foreign" then
        res.foreign = res.foreign + 1
      else
        cand[#cand + 1] = id
        for _, x in ipairs(r.excl or EMPTY) do
          local t = rev[x]
          if not t then
            t = {}
            rev[x] = t
          end
          t[#t + 1] = id
        end
      end
    end
  end
  local live, liveSet = {}, {}
  for _, id in ipairs(cand) do
    local s = st(id)
    local void = false
    if s.state ~= "done" and s.state ~= "log" then
      local r = rec(id)
      for _, x in ipairs(r.excl or EMPTY) do
        local sx = st(x)
        if sx and (sx.state == "done" or sx.state == "log") then void = true break end
      end
      if not void then
        -- reverse voiding only if the exclusion is mutual (both list each other): QuestieDB often has one-sided entries
        -- (e.g. 2923 excludes 2922 but not the other way round); the row of the other quest shows no reason then, so it must
        -- not be dropped from the counts either
        for _, x in ipairs(rev[id] or EMPTY) do
          local sx = st(x)
          if sx and (sx.state == "done" or sx.state == "log") and hasId(r.excl, x) then void = true break end
        end
      end
    end
    if void then
      res.voided = res.voided + 1
    else
      live[#live + 1] = id
      liveSet[id] = true
    end
  end
  -- mutual exclusion groups (union-find)
  local parent = {}
  local function root(x)
    while parent[x] and parent[x] ~= x do
      parent[x] = parent[parent[x]] or parent[x]
      x = parent[x]
    end
    return x
  end
  for _, id in ipairs(live) do parent[id] = id end
  for _, id in ipairs(live) do
    local r = rec(id)
    for _, x in ipairs(r.excl or EMPTY) do
      if liveSet[x] then
        local rx = rec(x)
        if rx and hasId(rx.excl, id) then
          local a, b = root(id), root(x)
          if a ~= b then parent[b] = a end
        end
      end
    end
  end
  local unit, unitId = {}, {}
  for _, id in ipairs(live) do
    local k = root(id)
    local s = st(id).state
    if not unit[k] or PRIO[s] > PRIO[unit[k]] then
      unit[k], unitId[k] = s, id
    end
  end
  for _, s in pairs(unit) do
    res.total = res.total + 1
    res[s] = res[s] + 1
  end
  res.complete = res.total > 0 and res.done == res.total
  if type(opts) == "table" and opts.units == true then
    local units = {}
    for k, s in pairs(unit) do units[#units + 1] = { id = unitId[k], state = s } end
    sort(units, function(a, b) return a.id < b.id end)
    res.units = units
  end
  return res
end
