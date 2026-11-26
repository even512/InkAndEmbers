-- Data for "welcome back". Detects a real login (PLAYER_ENTERING_WORLD with isInitialLogin; not /reload or zone changes)
-- and runs the ns.onLoginWelcome hooks. Welcome.summary() -> { name, level, first, lastZone, lastMapID, lastSeenAgo,
-- openQuests, restedXP, restedPct, vorhabenNearby, lastSessionStart, lastSessionEnd, prevEnd, gapSeconds }.
--
-- Change "Begruessung neu" (K1, K2, K4, K5): Welcome.plan(summary) decides WHAT the welcome says, without UI and without the
-- index (the index is ready ~20 s after login, the note comes after 3 s: the plan reads the log tail and the session list).
--   ns.Welcome.plan(summary) -> plan     (summary = Welcome.summary(); nil = it is read now)
--   plan = {
--     tier = "none" | "note" | "recap",  -- "recap" only with the setting welcomeRecap on AND pause >= 3 days (259200 s);
--                                        -- off or empty -> "note" / "none". "note" from 1 h (3600 s); below that "none".
--     gap  = { seconds = 90000, word = "nach zwei Tagen", kind = "after" | "since" },  -- pause of THIS character, in words (never a
--                                         -- clock time); the word is already part of the sentences; nil on the first session
--     note = nil | {
--       title = "Willkommen zurück, <Name>.",
--       sentences = { s1, s2 },        -- 1..2 finished sentences (sanitized, "Ihr" form), the first variant
--       variants  = { { s1, s2 }, { s1 } },  -- alternatives (B picks the one that fits 182 px best; variants[1] == sentences)
--       parts = { activity = { kind = "quest"|"dungeon"|"werk"|"craft"|"flight", zone = "...", quest = "..." } | nil,
--                 goal = { kind = "pin"|"level"|"trainer"|"todo"|"werk", text = "...", questID = nil } | nil,
--                 anniversary = "..." | nil },
--     },
--     lateNote = "Lange nicht gesehen ... Klick öffnet den Rückblick",  -- only when tier == "recap" (K5: card instead of auto-open)
--   }
--   No activity AND no goal -> tier "none" (an anniversary alone does not count as a statement; it is added only to a note).
--   Welcome.plan(summary, opts): opts.force = true is the preview (/chronik willkommen: ignores the setting welcome and the 1 h threshold; welcomeRecap is still
--   read, so tier may be "recap"; plan.note is always set: with nothing to say it holds only the pause sentence),
--   opts.rnd(n) picks the variant (tests), opts.now. Welcome.plan itself writes nothing; the one who SHOWS a note calls
--   Welcome.noteShown(plan) (counts it for the reminder rhythm: a reminder only after two notes without one). The recap calls
--   Journal.Recap.markShown(recap). Both keep their numbers in snapshots.state.recap (per character, not in ui).
--   Every name goes through Sanitize.field; the settings read are welcome and welcomeRecap (journal/Pages.lua).
-- The recap model (Journal.Recap.get/last/markShown/onReady) is documented in model/Recap.lua; example data for both:
-- tests/helpers/recap-fixture.mjs.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Welcome = ns.Welcome or {}
ns.Welcome = Welcome

local floor, huge = math.floor, math.huge

Welcome.DELAY = 3         -- seconds after load until the card shows
Welcome.RETRY = 5         -- seconds between retries while in combat
Welcome.TRIES = 6
Welcome.REGEN_DELAY = 1   -- s after the end of combat (a level-up note goes first)
Welcome.NAMES_MAX = 5
Welcome.QUEST_SCAN = 400  -- max quest log entries to read

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == huge or v == -huge then return nil end
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

local function flag(v)
  return not isSecret(v) and v == true
end

local hooks = {}
local state = { kind = nil, reloadGuess = false, fired = false, timerOn = false, first = true }

local schedule -- defined below

function ns.onLoginWelcome(fn)
  if type(fn) ~= "function" then return false end
  for _, f in ipairs(hooks) do
    if f == fn then return false end
  end
  hooks[#hooks + 1] = fn
  if state.kind == "login" then schedule() end -- hook registered late, card still pending
  return true
end

function Welcome.kind()
  return state.kind
end

-- previous session, captured at load (Store.login already sets info.lastSeen to now)

local function previousSession()
  local Store = ns.Store
  local db = Store and Store.db
  local meta = type(db) == "table" and db.meta
  local sessions = type(meta) == "table" and meta.sessions
  if type(sessions) ~= "table" or not Store.guid then return nil end
  local start = (tonumber(Store.session) or (#sessions + 1)) - 1
  for i = start, 1, -1 do
    local s = sessions[i]
    if type(s) == "table" and s.guid == Store.guid then return s, i end
  end
  return nil
end

local function sessionEnd(s)
  for _, k in ipairs({ "stop", "lastKnown", "lastSave", "start" }) do
    local v = tonumber(s[k])
    if v and v == v and v ~= huge and v ~= -huge then return v end
  end
  return nil
end

-- map at the end of the previous session: head of the last trail block (epoch, mapID)
local function lastMap()
  local Store = ns.Store
  local char = Store and Store.char()
  local trail = char and char.trail
  if type(trail) ~= "table" then return nil end
  for i = #trail, 1, -1 do
    local b = trail[i]
    if type(b) == "string" then
      local map = string.match(b, "^#~%-?%d+~(%d+)")
      map = map and tonumber(map)
      if map and map > 0 then return map end
    end
  end
  return nil
end

local function mapName(mapID)
  if not mapID then return nil end
  local Store = ns.Store
  local char = Store and Store.char()
  local snaps = char and char.snapshots
  local m = type(snaps) == "table" and type(snaps.maps) == "table" and snaps.maps[mapID]
  local name = type(m) == "table" and str(m.name) or nil
  if not name and ns.Zone then
    local info = ns.Zone.info(mapID)
    name = info and str(info.name) or nil
  end
  if not name then return nil end
  name = ns.Sanitize.field(name)
  return name ~= "" and name or nil
end

local function capture()
  local prev, idx = previousSession()
  state.first = prev == nil
  state.prevEnd = prev and sessionEnd(prev) or nil
  state.prevStart = prev and tonumber(prev.start) or nil
  state.prevIdx = idx
  state.scan = nil
  state.capturedAt = time()
  state.lastMapID = prev and lastMap() or nil
end

-- accept time of a quest: chars[guid].quests[questID].firstAt (set by the collector); nil if unknown
local function acceptedAt(questID)
  questID = num(questID)
  local Store = ns.Store
  local char = questID and Store and Store.char and Store.char()
  local quests = type(char) == "table" and char.quests
  if type(quests) ~= "table" then return nil end
  local e = quests[floor(questID)]
  if e == nil then e = quests[tostring(floor(questID))] end
  return type(e) == "table" and num(e.firstAt) or nil
end

local function openQuests()
  local out = { count = 0, names = {} }
  local api = type(C_QuestLog) == "table" and C_QuestLog or nil
  if not api or type(api.GetInfo) ~= "function" then return out end
  local newest, newestAt -- most recently accepted open quest
  local n = num(call(api.GetNumQuestLogEntries))
  local last = n and math.min(floor(n), Welcome.QUEST_SCAN) or Welcome.QUEST_SCAN
  for i = 1, last do
    local info = call(api.GetInfo, i)
    if info == nil then
      if not n then break end
    elseif type(info) == "table" and not isSecret(info) then
      if not flag(info.isHeader) and not flag(info.isHidden) and not flag(info.isTask) then
        out.count = out.count + 1
        local title = str(info.title)
        if title then
          title = ns.Sanitize.field(title)
          if title == "" then title = nil end
        end
        if title and #out.names < Welcome.NAMES_MAX then out.names[#out.names + 1] = title end
        local at = title and acceptedAt(info.questID)
        if at and (not newestAt or at > newestAt) then newest, newestAt = title, at end
      end
    end
  end
  out.lastAccepted = newest
  return out
end

function Welcome.summary()
  local Live = Journal.Live
  local out = { first = state.first }
  out.name = str(call(UnitName, "player")) and ns.Sanitize.field(call(UnitName, "player")) or nil
  out.level = Live and Live.level() or nil
  local now = time()
  if state.prevEnd then
    out.lastSeenAgo = math.max(0, floor(now - state.prevEnd))
  end
  out.lastMapID = state.lastMapID
  out.lastZone = mapName(state.lastMapID)
  -- previous session of THIS character (guid); the pause is measured per character (change "Begruessung neu")
  out.lastSessionStart, out.lastSessionEnd, out.prevEnd = state.prevStart, state.prevEnd, state.prevEnd
  out.gapSeconds = out.lastSeenAgo
  out.openQuests = openQuests()
  local rested = Live and Live.rested() or nil
  if rested and rested > 0 then
    out.restedXP = floor(rested)
    local _, max = Live.xp()
    if max and max > 0 then out.restedPct = floor(rested / max * 100 + 0.5) end
  end
  out.vorhabenNearby = {}
  if ns.Plans and ns.Plans.nearby then
    for i, p in ipairs(ns.Plans.nearby()) do out.vorhabenNearby[i] = { id = p.id, text = p.text, mapID = p.mapID } end
  end
  return out
end

-- Welcome.plan (change "Begruessung neu") ----------------------------------------------------------------------------------------
-- WHAT the welcome says, without UI and without the index: the log tail of the previous session (chars[guid].log, blocks
-- "#~<epoch>~<session>" with lines "<dt>~<CODE>~..."), the session list (meta.sessions, filtered by guid), the quest texts, the
-- to-do list and the modules. Every name goes through Sanitize.field; every foreign call is in pcall.

Welcome.TIER_NOTE = 3600        -- pause from which the note comes (1 h)
Welcome.TIER_RECAP = 259200     -- pause from which the book opens by itself (3 days)
Welcome.LOG_BLOCKS = 80         -- most log blocks read backwards for the previous session
Welcome.XP_BLOCKS = 40          -- most log blocks read backwards for the quest XP of the current level
Welcome.XP_SAMPLES = 10         -- quests of the current level the median is taken from
Welcome.XP_MIN_SAMPLES = 3      -- fewer: no number ("about N quests"), only words
Welcome.NEAR_QUESTS = 4         -- "about N quests" only up to this many
Welcome.ANNIV_EVERY = 2         -- notes in between: a reminder only after two notes without one (about every third)
Welcome.ANNIV_SEEN_MAX = 24
Welcome.QUEST_BONUS = 900       -- seconds: a quest in progress wins against a later flight or dungeon of the last quarter hour
Welcome.NAME_MAX = 60

local match, gmatch, find = string.match, string.gmatch, string.find

local function charTable()
  local Store = ns.Store
  local c = Store and Store.char and Store.char() or nil
  return type(c) == "table" and c or nil
end

local function snapGroup(c, name)
  local snaps = c and c.snapshots
  local g = type(snaps) == "table" and snaps[name]
  return type(g) == "table" and g or nil
end

-- a foreign name for display: sanitized, cut, nil when empty
local function clean(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  local s = ns.Sanitize.field(v)
  if s == "" then return nil end
  return ns.Sanitize.cut(s, Welcome.NAME_MAX)
end

local function questTitle(c, questID)
  questID = num(questID)
  local quests = c and c.quests
  if not questID then return nil end
  if type(quests) == "table" then
    local e = quests[floor(questID)]
    if e == nil then e = quests[tostring(floor(questID))] end
    local t = type(e) == "table" and clean(e.title) or nil
    if t then return t end
  end
  local api = type(C_QuestLog) == "table" and C_QuestLog or nil
  if api and type(api.GetTitleForQuestID) == "function" then return clean(call(api.GetTitleForQuestID, floor(questID))) end
  return nil
end

-- log blocks newest to oldest: fn(start, session, text) -> true stops
local function eachBlock(c, maxBlocks, fn)
  local log = c and c.log
  if type(log) ~= "table" then return end
  local n = 0
  for i = #log, 1, -1 do
    local b = log[i]
    if type(b) == "string" then
      local start, sess = match(b, "^#~(%-?%d+)~(%-?%d+)")
      if start then
        n = n + 1
        if n > maxBlocks then return end
        if fn(tonumber(start), tonumber(sess), b) then return end
      end
    end
  end
end

local function fieldsOf(rest)
  local t, n = {}, 0
  for v in gmatch(rest .. "~", "([^~]*)~") do
    n = n + 1
    t[n] = v
  end
  return t
end

-- reads the previous session of this character from the log tail: the quests still in progress, the last dungeon visit, flight
-- and craft. Cached per login. -> { quests = { [questID] = { t, mapID, text } }, inst, flight, craft, endT } | nil
local function scanSession()
  if state.scan ~= nil then return state.scan or nil end
  state.scan = false
  local c = charTable()
  local idx = state.prevIdx
  if not (c and idx) then return nil end
  local blocks = {}
  eachBlock(c, Welcome.LOG_BLOCKS, function(start, sess, text)
    if sess == idx then
      table.insert(blocks, 1, { start = start, text = text })
    elseif sess < idx then
      return true
    end
  end)
  if #blocks == 0 then return nil end
  local res = { quests = {}, endT = state.prevEnd }
  local seq = 0
  for _, b in ipairs(blocks) do
    for dt, code, rest in gmatch(b.text, "\n(%-?%d+)~(%u+)~?([^\n]*)") do
      local t = b.start + (tonumber(dt) or 0)
      if code == "QA" or code == "QO" then
        local f = fieldsOf(rest)
        local qid = num(tonumber(f[1]))
        if qid then
          local q = res.quests[qid]
          if not q then q = {} end
          seq = seq + 1
          q.t, q.seq = t, seq
          if code == "QA" then
            q.mapID = tonumber(f[4]) or q.mapID
          else
            q.text, q.kind, q.mapID = clean(f[6]), f[5], tonumber(f[7]) or q.mapID
          end
          res.quests[qid] = q
        end
      elseif code == "QT" or code == "QX" then
        local qid = num(tonumber(fieldsOf(rest)[1]))
        if qid then res.quests[qid] = false end
      elseif code == "IE" then
        local f = fieldsOf(rest)
        res.inst = { t = t, id = tonumber(f[1]), kind = f[2], open = true }
      elseif code == "IL" then
        if res.inst then res.inst.open, res.inst.left = false, t end
      elseif code == "TF" then
        local f = fieldsOf(rest)
        res.flight = { t = t, from = clean(f[1]), to = clean(f[2]), open = true }
      elseif code == "TL" then
        if res.flight then res.flight.open, res.flight.land = false, t end
      elseif code == "SK" then
        local f = fieldsOf(rest)
        res.craft = { t = t, name = clean(f[1]) }
      end
    end
  end
  state.scan = res
  return res
end

-- exported for the recap: quests the previous session touched (questID -> last touch time)
function Welcome.touchedQuests()
  local s = scanSession()
  local out = {}
  if s then
    for qid, q in pairs(s.quests) do
      if type(q) == "table" and q.t then out[qid] = q.t end
    end
  end
  return out
end

-- last activity of the previous session: the quest in progress (the latest one), else dungeon / craft / flight by the latest event
local function activityOf()
  local s = scanSession()
  if not s then return nil end
  local c = charTable()
  local endT = s.endT or 0
  -- the latest quest with progress or accept that is still open and has a readable title
  local bestQ, title
  for qid, q in pairs(s.quests) do
    if type(q) == "table" and q.t and (not bestQ or q.t > bestQ.t or (q.t == bestQ.t and q.seq > bestQ.seq)) then
      local t = questTitle(c, qid)
      if t then bestQ, title = { id = qid, t = q.t, seq = q.seq }, t end
    end
  end
  local cands = {}
  if title then cands[#cands + 1] = { score = bestQ.t + Welcome.QUEST_BONUS, kind = "quest", quest = title, questID = bestQ.id } end
  local inst = s.inst
  if inst and (inst.kind == "party" or inst.kind == "raid" or inst.kind == "scenario") then
    local g = snapGroup(c, "instances")
    local e = g and inst.id and g[inst.id]
    local name = type(e) == "table" and clean(e.name) or nil
    if name then cands[#cands + 1] = { score = inst.open and endT or inst.t, kind = "dungeon", dungeon = name } end
  end
  local f = s.flight
  if f and (f.open or (f.land and endT - f.land < 300)) then
    cands[#cands + 1] = { score = f.open and endT or f.land, kind = "flight", from = f.from, to = f.to }
  end
  if s.craft and s.craft.name then cands[#cands + 1] = { score = s.craft.t, kind = "craft", skill = s.craft.name } end
  table.sort(cands, function(a, b) return a.score > b.score end)
  local top = cands[1]
  if not top then return nil end
  local a = { kind = top.kind, quest = top.quest, questID = top.questID, dungeon = top.dungeon, skill = top.skill, from = top.from, to = top.to }
  if top.kind == "quest" then a.zone = mapName(state.lastMapID) end
  return a
end

-- XP of the quests turned in on the current level (log tail, newest first, at most XP_SAMPLES)
local function questXpSamples(c, level)
  local out = {}
  eachBlock(c, Welcome.XP_BLOCKS, function(_, _, text)
    local list = {}
    for rest in gmatch(text, "\n%-?%d+~QT~([^\n]*)") do
      local f = fieldsOf(rest)
      local xp = tonumber(f[5])
      if tonumber(f[2]) == level and xp and xp > 0 then list[#list + 1] = xp end
    end
    for i = #list, 1, -1 do
      out[#out + 1] = list[i]
      if #out >= Welcome.XP_SAMPLES then return true end
    end
  end)
  return out
end

local function median(list)
  local c = {}
  for i, v in ipairs(list) do c[i] = v end
  table.sort(c)
  local n = #c
  if n == 0 then return nil end
  if n % 2 == 1 then return c[(n + 1) / 2] end
  return (c[n / 2] + c[n / 2 + 1]) / 2
end

local function maxLevel()
  local C = Journal.Chronik
  local v = C and type(C.maxLevel) == "function" and call(C.maxLevel) or nil
  return num(v) or 60
end

-- level goal: "about N quests" only with at least XP_MIN_SAMPLES quests of this level (median of their XP, rested bonus not
-- counted), otherwise words from the share of the level already filled; nothing when the level is far from done
local function levelGoal(level)
  local Live = Journal.Live
  if not (Live and level) or level >= maxLevel() then return nil end
  local cur, need = Live.xp()
  if not (cur and need and need > 0) then return nil end
  local rest = math.max(0, need - cur)
  local samples = questXpSamples(charTable(), level)
  if #samples >= Welcome.XP_MIN_SAMPLES then
    local m = median(samples)
    if m and m > 0 then
      local n = math.ceil(rest / m)
      if n >= 1 and n <= Welcome.NEAR_QUESTS then return { kind = "level", level = level + 1, n = n } end
    end
  end
  local frac = cur / need
  if frac >= 0.9 then return { kind = "level", level = level + 1, words = "almost" } end
  if frac >= 0.75 then return { kind = "level", level = level + 1, words = "close" } end
  return nil
end

local function moduleOn(id)
  local API = ns.Core and ns.Core.API
  if not (API and type(API.moduleLoaded) == "function") then return false end
  local ok, v = pcall(API.moduleLoaded, id)
  return ok and v == true
end
Welcome.moduleOn = moduleOn

local function foreverOn()
  local f = ns.Core and ns.Core.foreverParts
  if type(f) ~= "function" then return true end
  local ok, v = pcall(f)
  return not ok or v ~= false
end

-- pinned quest (module Quest tracker only, through its API; never the saved state)
function Welcome.pinned()
  if not moduleOn("tracker") then return nil end
  local QP = Journal.QuestPin
  if not (QP and type(QP.current) == "function") then return nil end
  local ok, id = pcall(QP.current)
  id = ok and num(id) or nil
  if not id then return nil end
  local api = type(C_QuestLog) == "table" and C_QuestLog or nil
  if api and type(api.IsOnQuest) == "function" then
    local ok2, on = pcall(api.IsOnQuest, floor(id))
    if ok2 and not isSecret(on) and on == false then return nil end
  end
  local title = questTitle(charTable(), id)
  if not title then return nil end
  return { questID = floor(id), title = title }
end

-- open work order (module Crafting), text sanitized
function Welcome.werkOrder()
  local W = ns.Werk
  if not (W and moduleOn("crafting") and type(W.active) == "function" and type(W.orders) == "function" and type(W.titleText) == "function") then
    return nil
  end
  local ok, active = pcall(W.active)
  if not (ok and active == true) then return nil end
  local ok2, list = pcall(W.orders)
  if not (ok2 and type(list) == "table") then return nil end
  for _, o in ipairs(list) do
    local ok3, text = pcall(W.titleText, o.w)
    text = ok3 and clean(text) or nil
    if text then return text end
  end
  return nil
end

-- open to-dos (module Plans): free to-dos of the player, no automatic ones (teacher) and no work orders; the newest maxN
function Welcome.todos(maxN)
  local out = {}
  local P = ns.Plans
  if not (P and moduleOn("plans") and type(P.list) == "function") then return out end
  local ok, list = pcall(P.list, "open")
  if not (ok and type(list) == "table") then return out end
  for _, p in ipairs(list) do
    if type(p) == "table" and p.auto == nil and p.werk == nil and p.shop == nil then
      local label = type(P.label) == "function" and call(P.label, p) or nil
      local text = clean(label or p.text)
      if text then out[#out + 1] = text end
    end
  end
  maxN = maxN or #out
  while #out > maxN do table.remove(out, 1) end
  return out
end

function Welcome.trainerOpen()
  if not (moduleOn("plans") and foreverOn()) then return false end
  local T = ns.Trainer
  if not (T and type(T.lehrplanTodoOpen) == "function") then return false end
  local ok, v = pcall(T.lehrplanTodoOpen)
  return ok and v == true
end

-- next goal, one, by priority: pin -> level almost reached -> teacher due -> work order / to-do
local function goalOf(level)
  local pin = Welcome.pinned()
  if pin then return { kind = "pin", text = pin.title, questID = pin.questID } end
  local lg = levelGoal(level)
  if lg then return lg end
  if Welcome.trainerOpen() then
    local RT = Journal.RecapTexts
    return { kind = "trainer", text = RT and RT.trainerShort() or nil }
  end
  local werk = Welcome.werkOrder()
  if werk then return { kind = "werk", text = werk } end
  local todos = Welcome.todos(1)
  if todos[1] then return { kind = "todo", text = todos[1] } end
  return nil
end

-- persistent state per character: snapshots.state.recap = { at, from, to, n, anniv = { n, seen = { key, ... } } }
-- (Store.putSnapshot; "at" is the time the recap was last SHOWN, a note only touches anniv)
function Welcome.state()
  local c = charTable()
  local st = c and snapGroup(c, "state")
  local r = type(st) == "table" and st.recap
  return type(r) == "table" and r or {}
end

function Welcome.putState(patch)
  local Store = ns.Store
  if type(patch) ~= "table" or not (Store and Store.ready and Store.ready()) then return false end
  local cur = Welcome.state()
  local entry = {}
  for _, k in ipairs({ "at", "from", "to", "n" }) do entry[k] = cur[k] end
  if type(cur.anniv) == "table" then
    local seen = {}
    for i, v in ipairs(type(cur.anniv.seen) == "table" and cur.anniv.seen or {}) do seen[i] = v end
    entry.anniv = { n = tonumber(cur.anniv.n) or 0, seen = seen }
  end
  for k, v in pairs(patch) do entry[k] = v end
  local keepAt = entry.at
  if not Store.putSnapshot("state", "recap", entry, true) then return false end
  local g = snapGroup(charTable(), "state")
  if g and type(g.recap) == "table" then g.recap.at = keepAt end -- putSnapshot stamps "now"; "at" stays the time of the last recap
  return true
end

-- reminders ("Heute vor 14 Tagen ..."): level 10, 20, ... milestones, new continents, first dungeon / raid and medals whose
-- day lies exactly 7/14/30/60/90/180/365 days back. Log tail only (blocks older than a year stop the search).
local function dayNo(t, tz) return floor((t + tz) / 86400) end

local function anniversaryOf(seen, now)
  local RT = Journal.RecapTexts
  local c = charTable()
  if not (RT and c) then return nil end
  local Store = ns.Store
  local meta = Store and Store.db and Store.db.meta
  local tz = type(meta) == "table" and tonumber(meta.tzOffset) or 0
  local today = dayNo(now, tz)
  local want = {}
  for _, d in ipairs(RT.AGO_DAYS) do want[d] = true end
  local seenSet = {}
  for _, k in ipairs(seen or {}) do seenSet[k] = true end
  local best
  local function consider(t, key, a)
    if not t or seenSet[key] then return end
    local days = today - dayNo(t, tz)
    if want[days] and (not best or days < best.a.days) then
      a.days = days
      best = { key = key, a = a }
    end
  end
  local oldest = now - 370 * 86400
  eachBlock(c, 400, function(start, _, text)
    if start < oldest then return true end
    if find(text, "~LV~", 1, true) or find(text, "~MO~", 1, true) then
      for dt, code, rest in gmatch(text, "\n(%-?%d+)~(%u+)~?([^\n]*)") do
        if code == "LV" or code == "MO" then
          local t = start + (tonumber(dt) or 0)
          local f = fieldsOf(rest)
          if code == "LV" then
            local lv = tonumber(f[1])
            if lv and lv >= 10 and lv % 10 == 0 then consider(t, "lv" .. floor(lv), { kind = "level", level = floor(lv) }) end
          elseif f[1] == "continent" then
            local zone = mapName(tonumber(f[2]))
            if zone then consider(t, "cont" .. tostring(f[2]), { kind = "continent", zone = zone }) end
          elseif f[1] == "first_dungeon" or f[1] == "first_raid" then
            local g = snapGroup(c, "instances")
            local e = g and g[tonumber(f[2])]
            local name = type(e) == "table" and clean(e.name) or nil
            if name then consider(t, "inst" .. tostring(f[2]), { kind = f[1] == "first_raid" and "raid" or "dungeon", dungeon = name }) end
          end
        end
      end
    end
  end)
  local medals = snapGroup(c, "medals")
  local C = Journal.Chronik
  if medals and C and type(C.SEAL_BY_ID) == "table" then
    for key, m in pairs(medals) do
      local id = type(key) == "string" and match(key, "^([^:]+):")
      local seal = id and C.SEAL_BY_ID[id]
      local t = type(m) == "table" and tonumber(m.t) or nil
      local title = seal and clean(seal.title) or nil
      if t and title then consider(t, "medal" .. key, { kind = "medal", title = title }) end
    end
  end
  if not best then return nil end
  local text = RT.anniversary(best.a)
  if not text then return nil end
  return text, best.key
end

-- the recap's side note ("Am Rande", model/Recap.lua): the same reminder, read only (nothing is counted or remembered)
function Welcome.anniversary(seen, now)
  local text = anniversaryOf(seen, tonumber(now) or time())
  return text
end

-- rnd(n) -> 1..n; default math.random
local function defaultRnd(n) return math.random(n) end

-- Welcome.plan(summary, opts) -> plan (see the head of this file). opts = { force = true: preview (ignores the setting welcome and the
-- pause thresholds), rnd = function(n), now = epoch }
function Welcome.plan(summary, opts)
  opts = type(opts) == "table" and opts or {}
  local plan = { tier = "none" }
  local RT = Journal.RecapTexts
  if not RT then return plan end
  if type(summary) ~= "table" then
    local ok, s = pcall(Welcome.summary)
    summary = ok and s or nil
  end
  if type(summary) ~= "table" or summary.first or not num(summary.gapSeconds) then return plan end
  local now = num(opts.now) or time()
  local gapS = math.max(0, floor(summary.gapSeconds))
  local Store = ns.Store
  local meta = Store and Store.db and Store.db.meta
  local tz = type(meta) == "table" and tonumber(meta.tzOffset) or 0
  plan.gap = RT.gap(gapS, summary.lastSessionEnd, now, tz)
  local Pages = Journal.Pages
  local function setting(key)
    if not (Pages and type(Pages.setting) == "function") then return true end
    local ok, v = pcall(Pages.setting, key)
    return not ok or v ~= false
  end
  if not opts.force then
    if not setting("welcome") then return plan end
    if gapS < Welcome.TIER_NOTE then return plan end
  end
  local rnd = type(opts.rnd) == "function" and opts.rnd or defaultRnd
  local level = num(summary.level)
  local parts = {}
  local ok, a = pcall(activityOf)
  if ok then parts.activity = a end
  local ok2, g = pcall(goalOf, level)
  if ok2 then parts.goal = g end
  -- reminder: only when there is little to say (activity or goal, not both) and the counter allows it
  local anniv = Welcome.state().anniv
  local annivN = type(anniv) == "table" and tonumber(anniv.n) or 0
  if (parts.activity ~= nil) ~= (parts.goal ~= nil) and annivN >= Welcome.ANNIV_EVERY then
    local ok3, text, key = pcall(anniversaryOf, type(anniv) == "table" and anniv.seen or nil, now)
    if ok3 and text then parts.anniversary, parts.anniversaryKey = text, key end
  end
  local sentences, variants
  if opts.force and not parts.activity and not parts.goal then parts.backOnly = true end
  if parts.activity or parts.goal or parts.backOnly then
    local ok4, s, v = pcall(RT.note, parts, plan.gap, rnd)
    if ok4 then sentences, variants = s, v end
  end
  if sentences then
    plan.note = { title = RT.title(summary.name), sentences = sentences, variants = variants, parts = parts }
    -- the level goal carries its finished sentence as text (for the one who shows it)
    if parts.goal and parts.goal.kind == "level" and #sentences >= 2 then parts.goal.text = sentences[2] end
  end
  local wantRecap = gapS >= Welcome.TIER_RECAP and setting("welcomeRecap")
  if wantRecap then
    plan.tier = "recap"
    plan.lateNote = RT.lateNote(plan.gap, rnd)
  elseif plan.note then
    plan.tier = "note"
  end
  return plan
end

-- called by the one who SHOWED a note (B): counts it for the reminder rhythm and remembers a reminder that was said
function Welcome.noteShown(plan)
  local note = type(plan) == "table" and plan.note
  if type(note) ~= "table" then return false end
  local cur = Welcome.state().anniv
  local n = type(cur) == "table" and tonumber(cur.n) or 0
  local seen = {}
  for _, k in ipairs(type(cur) == "table" and type(cur.seen) == "table" and cur.seen or {}) do seen[#seen + 1] = k end
  local parts = type(note.parts) == "table" and note.parts or {}
  if parts.anniversary and parts.anniversaryKey then
    seen[#seen + 1] = parts.anniversaryKey
    while #seen > Welcome.ANNIV_SEEN_MAX do table.remove(seen, 1) end
    n = 0
  else
    n = n + 1
  end
  return Welcome.putState({ anniv = { n = n, seen = seen } })
end

Welcome.mapName = mapName
Welcome.sessionEnd = sessionEnd
function Welcome.lastMapID() return state.lastMapID end

local function inCombat()
  local v = call(InCombatLockdown)
  return flag(v)
end

function Welcome.trigger()
  local s = Welcome.summary()
  local n = 0
  for i = 1, #hooks do
    n = n + 1
    ns.Core.safe(hooks[i], s)
  end
  return n
end

local function attempt(tries)
  state.timerOn = false
  if state.fired then return end
  if inCombat() then
    if tries >= Welcome.TRIES then
      state.waitRegen = true -- no more timers: the note comes with PLAYER_REGEN_ENABLED (once)
      return
    end
    state.timerOn = true
    C_Timer.After(Welcome.RETRY, function() ns.Core.safe(attempt, tries + 1) end)
    return
  end
  state.fired = true
  Welcome.trigger()
end

-- timer only while a hook waits and nothing is scheduled or fired yet
schedule = function()
  if state.fired or state.timerOn or #hooks == 0 then return end
  state.timerOn = true
  C_Timer.After(Welcome.DELAY, function() ns.Core.safe(attempt, 1) end)
end

if ns.Core and ns.Core.on then
  -- PLAYER_LOGIN runs after Store.login and before the first PLAYER_ENTERING_WORLD: fallback for reload detection
  ns.Core.on("PLAYER_LOGIN", function()
    local Store = ns.Store
    local meta = Store and Store.db and Store.db.meta
    local at = type(meta) == "table" and tonumber(meta.reloadAt) or nil
    state.reloadGuess = at ~= nil and time() - at <= (Store.RELOAD_WINDOW or 600)
    state.kind, state.fired, state.timerOn, state.waitRegen = nil, false, false, false
  end)
  ns.Core.on("PLAYER_REGEN_ENABLED", function()
    if not state.waitRegen then return end
    state.waitRegen = false
    if state.kind == "login" and not state.fired and not state.timerOn then
      C_Timer.After(Welcome.REGEN_DELAY, function() ns.Core.safe(attempt, Welcome.TRIES) end)
    end
  end)
  ns.Core.on("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
    if state.kind ~= nil then return end -- zone change: only the first PLAYER_ENTERING_WORLD counts
    local kind
    if isReloadingUi == true then
      kind = "reload"
    elseif isInitialLogin == true then
      kind = "login"
    elseif isInitialLogin == nil and isReloadingUi == nil then
      kind = state.reloadGuess and "reload" or "login" -- old client without args
    else
      kind = "other"
    end
    state.kind = kind
    capture()
    if kind == "login" then schedule() end
  end)
end
