-- "Zuvor auf Eurer Reise": the recap model (change "Begruessung neu", K3). Built from the index (needs Journal.Index ready; same
-- "baut"-retry as Rest.summary), shown by journal/pages/ChronikRueckblick.lua. Texts come from model/RecapTexts.lua.
--
--   Journal.Recap.get(opts) -> recap | nil, reason
--     opts.preview = true: nothing is written, the window ignores what was shown before (the last <= 5 sessions)
--     opts.from / opts.to: an explicit window (Recap.last); reason: "baut" (the index is still building: retry through
--     Recap.onReady), "keine-daten" (no index / no finished session), "leer" (nothing to tell in the window), "kein-charakter"
--   Journal.Recap.onReady(fn)         fn() once, as soon as the index is ready (at once when it already is), then Recap.get works
--   Journal.Recap.last() -> recap | nil, reason   the recap shown last, rebuilt from its window (snapshots.state.recap.from/to)
--   Journal.Recap.markShown(recap)    snapshots.state.recap = { at, from, to, n, anniv = { ... } } (Store.putSnapshot, per character);
--                                     refuses a preview (recap.preview == true)
--
--   recap = {
--     from, to, sessions, days, gapSeconds,            -- window (epoch), sessions in it (<= 5), play days (<= 7), pause before
--     story = { "paragraph 1", "paragraph 2" },        -- finished text (sanitized), 1..2 short paragraphs
--     facts = { zones = { ... } (main zones only, never a continent/world), newZones = { ... } (first arrival), levelFrom, levelTo,
--               levelUps, deaths, kills, quests, dungeons, firsts = { { kind = "mount"|"close_win"|"fish"|"elite", name } },
--               highlights = { { kind = "medal"|"best"|"dungeon"|"rare", text, name } } },    -- name = the raw name (sanitized)
--               (best also: itemID, quality, link = "item:..." for the coloured link with the game tooltip)
--     stand = { level, xpPct|nil, nextLevel, zone|nil, restedPct|nil (>= 25 only), gold|nil (copper),
--               lines = { "finished line", ... } },
--     open  = { pin = { questID, title }|nil, progress = { { questID, title, have, need } } (<= 5), todos = { "..." },
--               werk = "..."|nil, trainer = "..."|nil,
--               list = { { kind = "pin"|"progress"|"open", questID, title, goal|nil } } (<= 5: pin, progress, the rest of the log,
--               accepted last first; goal = the goal line "Kobold getötet: 4/8" / "Bereit zur Abgabe") },
--     done  = { { questID, title, text|nil (2..3 whole sentences), full|nil (the whole quest text), t } } (<= 3, newest first),
--     aside = { "side note", ... } (<= 2: a reminder, the longest session so far, the way on foot; never a repeat of the story),
--     picture = nil | { kind = "route", mapID (the MAIN ZONE), zoneName, t0, t1,
--                       points = { { x, y }, { brk = true }, ... } (<= 150 points plus the brk entries; x, y = 0..1 of the zone map,
--                       sub maps projected; brk = jump/flight/death/continent),
--                       startPt = { x, y }, endPt = { x, y }, marks = { { x, y, questID, title } } (turn-ins, <= 12) },
--     preview = true | nil,
--   }
-- A decides WHAT is said (finished, sanitized text), B decides HOW it looks. Example data: tests/helpers/recap-fixture.mjs.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Recap = {}
Journal.Recap = Recap

local floor, huge, max, min = math.floor, math.huge, math.max, math.min
local match, gmatch = string.match, string.gmatch

Recap.MAX_SESSIONS = 5     -- sessions in one recap
Recap.MAX_DAYS = 7         -- play days in one recap
Recap.POINTS_MAX = 150     -- trail points in the picture
Recap.POINTS_MIN = 8       -- fewer: no picture
Recap.SPAN_MIN = 0.01      -- the route must span at least 1 % of the map in one direction: otherwise no picture
Recap.BREAK_GAP = 120      -- seconds without a trail point ... (as Rest.BREAK_GAP)
Recap.BREAK_DIST = 0.02    -- ... and more than 2 % of the map apart: the line breaks
Recap.RESTED_MIN = 25      -- rested bonus is named from this percentage
Recap.PROGRESS_MAX = 5
Recap.TODOS_MAX = 3
Recap.HIGHLIGHTS_MAX = 4
Recap.ZONES_MAX = 4
Recap.QUEST_SCAN = 400

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function finite(v)
  return type(v) == "number" and v == v and v ~= huge and v ~= -huge and not isSecret(v)
end

local function clean(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  local s = ns.Sanitize.field(v)
  if s == "" then return nil end
  return ns.Sanitize.cut(s, 60)
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if not ok or isSecret(a) then return nil end
  return a, b
end

local function Idx() return Journal.Index end
local function Wel() return ns.Welcome end
local function RT() return Journal.RecapTexts end

-- sessions -------------------------------------------------------------------------------------------------------------------

local function dayNo(t, tz) return floor((t + tz) / 86400) end

-- finished sessions of this character (guid), oldest first: { idx, start, stop }; the running session never counts
local function sessionList()
  local Store, W = ns.Store, Wel()
  local meta = Store and Store.db and Store.db.meta
  local sessions = type(meta) == "table" and meta.sessions
  if type(sessions) ~= "table" or not Store.guid then return nil end
  local current = tonumber(Store.session) or (#sessions + 1)
  local out = {}
  for i = 1, #sessions do
    local s = sessions[i]
    if type(s) == "table" and s.guid == Store.guid and i < current then
      local start = tonumber(s.start)
      local stop = W and W.sessionEnd and W.sessionEnd(s) or nil
      if finite(start) and finite(stop) then
        if stop < start then stop = start end
        out[#out + 1] = { idx = i, start = start, stop = stop }
      end
    end
  end
  return out, tonumber(meta.tzOffset) or 0
end

-- the sessions of the window: since `after` (the last recap shown), at most MAX_SESSIONS and MAX_DAYS play days, newest kept
local function windowSessions(opts, st)
  local list, tz = sessionList()
  if not list then return nil end
  local sel = {}
  if finite(opts.from) and finite(opts.to) then
    for _, s in ipairs(list) do
      if s.stop > opts.from and s.start < opts.to then sel[#sel + 1] = s end
    end
  else
    local after = (not opts.preview) and finite(st.at) and st.at or nil
    local days = {}
    local ndays = 0
    for i = #list, 1, -1 do
      local s = list[i]
      if after and s.stop <= after then break end
      if #sel >= Recap.MAX_SESSIONS then break end
      local d = dayNo(s.stop, tz)
      if not days[d] then
        if ndays >= Recap.MAX_DAYS then break end
        days[d], ndays = true, ndays + 1
      end
      table.insert(sel, 1, s)
    end
  end
  if #sel == 0 then return nil end
  local from, to = sel[1].start, sel[#sel].stop
  if not (finite(opts.from) and finite(opts.to)) then
    local after = (not opts.preview) and finite(st.at) and st.at or nil
    if after and after > from then from = min(after, to) end
  else
    from, to = max(from, opts.from), min(to, opts.to)
  end
  local days = {}
  local nd = 0
  for _, s in ipairs(sel) do
    for d = dayNo(s.start, tz), dayNo(s.stop, tz) do
      if not days[d] then days[d], nd = true, nd + 1 end
    end
  end
  return { sessions = sel, from = from, to = to, days = nd, last = sel[#sel] }
end

-- facts from the index ---------------------------------------------------------------------------------------------------------

local function inWin(list, t0, t1, fn)
  for i = 1, #list do
    local r = list[i]
    if r.t >= t0 and r.t < t1 then fn(r) end
  end
end

local function levelAt(index, t)
  local I = Idx()
  local lv = I.list(index, "LV")
  local best
  for i = 1, #lv do
    if lv[i].t <= t then best = I.num(lv[i], "LV", "level") else break end
  end
  if best then return floor(best) end
  local first = lv[1] and I.num(lv[1], "LV", "level")
  if first and first >= 2 then return floor(first) - 1 end
  return nil
end

-- map type (Enum.UIMapType: 0 cosmos, 1 world, 2 continent, 3 zone, 4 dungeon, 5 micro, 6 orphan): the live client, else the type
-- the ZN line wrote at the first arrival; nil when unknown
local function mapTypeOf(index, mapID)
  if not finite(mapID) then return nil end
  local Z = ns.Zone
  local info = Z and type(Z.info) == "function" and call(Z.info, mapID) or nil
  if type(info) == "table" and finite(info.mapType) then return floor(info.mapType) end
  local types = index.recapMapTypes
  if not types then
    types = {}
    local I = Idx()
    for _, r in ipairs(I.list(index, "ZN")) do
      local m, t = I.num(r, "ZN", "mapID"), I.num(r, "ZN", "mapType")
      if m and t and types[m] == nil then types[m] = floor(t) end
    end
    index.recapMapTypes = types
  end
  return types[mapID]
end
Recap.mapTypeOf = mapTypeOf

-- main zone of a map (a city, cave or sub map counts with its zone); nil for a continent, the world or the cosmos: they are no
-- place one was in ("Östliche Königreiche" never stands as a region in the recap)
local function mainZone(index, mapID)
  if not finite(mapID) then return nil end
  local t = mapTypeOf(index, mapID)
  if t and t < 3 then return nil end
  local Geo = Journal.Geo
  local z = Geo and type(Geo.mainZoneOf) == "function" and call(Geo.mainZoneOf, mapID) or nil
  if finite(z) and z ~= mapID then
    local tz = mapTypeOf(index, z)
    if tz and tz < 3 then z = nil end
  end
  return finite(z) and floor(z) or floor(mapID)
end
Recap.mainZone = mainZone

-- raw name of the main zone of a map (sanitized), nil for a continent / the world
local function zoneName(index, mapID)
  local M = Journal.Meilensteine
  local z = mainZone(index, mapID)
  if not z then return nil end
  local name = M and M.mapNameOf(index, z) or nil
  if not name and z ~= mapID then name = M and M.mapNameOf(index, mapID) or nil end
  return clean(name)
end

-- trail blocks of the window, oldest first: { start, map, text }
local function trailBlocks(index, t0, t1)
  local char = index.char
  local trail = type(char) == "table" and char.trail
  local out = {}
  if type(trail) ~= "table" then return out end
  for i = 1, #trail do
    local b = trail[i]
    if type(b) == "string" then
      local start, map = match(b, "^#~(%-?%d+)~(%-?%d+)")
      start, map = tonumber(start), tonumber(map)
      if start and map and map > 0 and start >= t0 and start <= t1 then out[#out + 1] = { start = start, map = map, text = b } end
    end
  end
  return out
end

-- zones of the window: the busiest ones (by trail lines), in the order of first arrival
local function zonesOf(index, blocks)
  local counts, first, order = {}, {}, {}
  for _, b in ipairs(blocks) do
    local name = zoneName(index, b.map)
    if name then
      local _, n = string.gsub(b.text, "\n", "")
      counts[name] = (counts[name] or 0) + n
      if not first[name] then
        order[#order + 1] = name
        first[name] = #order
      end
    end
  end
  local names = {}
  for _, n in ipairs(order) do names[#names + 1] = n end
  table.sort(names, function(a, b)
    if counts[a] ~= counts[b] then return counts[a] > counts[b] end
    return first[a] < first[b]
  end)
  while #names > Recap.ZONES_MAX do table.remove(names) end
  table.sort(names, function(a, b) return first[a] < first[b] end)
  return names
end

local function npcName(index, npcID)
  local char = index.char
  local npcs = type(char) == "table" and char.npcs
  local e = type(npcs) == "table" and npcID and (npcs[npcID] or npcs[tostring(npcID)])
  if type(e) == "table" then e = e.name end
  return clean(e)
end

-- highlights: medal, rare, dungeon, best find (each at most once, newest in the window)
local function highlightsOf(index, from, to, sec)
  local I, T = Idx(), RT()
  local out = {}
  local C = Journal.Chronik
  if C and type(C.sealsOf) == "function" then
    local seals = call(C.sealsOf, index)
    local newest, title
    for _, e in ipairs(type(seals) == "table" and type(seals.list) == "table" and seals.list or {}) do
      for _, s in pairs(type(e.steps) == "table" and e.steps or {}) do
        if type(s) == "table" and finite(s.at) and s.at >= from and s.at < to and (not newest or s.at > newest) then
          newest, title = s.at, clean(e.title)
        end
      end
    end
    if title then out[#out + 1] = { kind = "medal", text = T.medalText(title), name = title } end
  end
  local rare
  inWin(I.list(index, "MO"), from, to, function(r)
    local kind = I.str(r, "MO", "kind")
    local detail = I.str(r, "MO", "detail")
    if kind == "first_rare" or (kind == "kill" and detail and match(detail, "^rare")) then
      local name = npcName(index, I.num(r, "MO", "value"))
      if name then rare = name end
    end
  end)
  if rare then out[#out + 1] = { kind = "rare", text = rare, name = rare } end
  local dungeon
  for _, run in ipairs(sec.runs or {}) do
    if finite(run.t0) and run.t0 >= from and run.t0 < to and clean(run.name) then
      if not dungeon or run.t0 > dungeon.t0 then dungeon = { t0 = run.t0, name = clean(run.name) } end
    end
  end
  if dungeon then out[#out + 1] = { kind = "dungeon", text = dungeon.name, name = dungeon.name } end
  local best = sec.best and clean(sec.best.name) or nil
  if best then
    local b = sec.best
    local Tx = Journal.Texts
    local link = (Tx and type(Tx.itemString) == "function" and b.key and call(Tx.itemString, b.key)) or b.link
    if type(link) ~= "string" or not match(link, "^item:%d+[%d:%-]*$") then link = nil end
    out[#out + 1] = { kind = "best", text = best, name = best, itemID = finite(b.itemID) and floor(b.itemID) or nil,
      quality = finite(b.quality) and floor(b.quality) or nil, link = link }
  end
  while #out > Recap.HIGHLIGHTS_MAX do table.remove(out) end
  return out
end

-- first times of the window (MO lines): mount, close win, first catch, first elite; each kind once, oldest first, at most 2
Recap.FIRSTS_MAX = 2
local FIRST_KINDS = { mount = "mount", close_win = "close_win", first_fish = "fish", first_elite = "elite" }

local function firstsOf(index, from, to)
  local I = Idx()
  local out, seen = {}, {}
  inWin(I.list(index, "MO"), from, to, function(r)
    local kind = FIRST_KINDS[I.str(r, "MO", "kind") or ""]
    if kind and not seen[kind] and #out < Recap.FIRSTS_MAX then
      seen[kind] = true
      local e = { kind = kind }
      if kind == "mount" then e.name = clean(I.str(r, "MO", "detail")) end
      out[#out + 1] = e
    end
  end)
  return out
end

-- stand -----------------------------------------------------------------------------------------------------------------------

local function standOf(index)
  local Live, W, T = Journal.Live, Wel(), RT()
  local st = {}
  local level = Live and Live.level() or nil
  st.level = level
  if not level then return st end
  local C = Journal.Chronik
  local top = C and type(C.maxLevel) == "function" and call(C.maxLevel) or 60
  if level < top then
    st.nextLevel = level + 1
    local cur, need = Live.xp()
    if cur and need and need > 0 then st.xpPct = max(0, min(99, floor(cur / need * 100))) end
  end
  local mapID = ns.Zone and type(ns.Zone.here) == "function" and call(ns.Zone.here) or nil
  if not finite(mapID) then mapID = W and W.lastMapID and W.lastMapID() or nil end
  if finite(mapID) then st.zone = zoneName(index, mapID) end
  local rested = Live.rested()
  if rested and rested > 0 then
    local _, need = Live.xp()
    if need and need > 0 then
      local pct = floor(rested / need * 100 + 0.5)
      if pct >= Recap.RESTED_MIN then st.restedPct = pct end
    end
  end
  local gold = Live.money()
  if gold and gold > 0 then st.gold = floor(gold) end
  st.lines = T.standLines(st)
  return st
end

-- open ------------------------------------------------------------------------------------------------------------------------

Recap.OPEN_MAX = 6        -- quests in "Was offen ist" (pin, here in the area, elsewhere)
Recap.DONE_MAX = 3        -- quests in "Zuletzt erledigt"
Recap.GOAL_MAX = 110      -- bytes of a goal line
Recap.ASIDE_MAX = 2       -- side notes ("Am Rande")
Recap.MARKS_MAX = 12      -- turn-in marks on the picture

local function questsTable(index)
  local char = type(index) == "table" and index.char
  return type(char) == "table" and type(char.quests) == "table" and char.quests or {}
end

local function questEntry(index, qid)
  local q = questsTable(index)
  local e = q[qid]
  if e == nil then e = q[tostring(qid)] end
  return type(e) == "table" and e or nil
end

local function questTitleOf(index, qid)
  local e = questEntry(index, qid)
  local t = e and clean(e.title) or nil
  if t then return t end
  local api = type(C_QuestLog) == "table" and C_QuestLog or nil
  if api and type(api.GetTitleForQuestID) == "function" then return clean(call(api.GetTitleForQuestID, qid)) end
  return nil
end

-- a foreign line for display: sanitized, cut between words
local function line(v, maxB)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  local s = ns.Sanitize.field(v)
  if s == "" then return nil end
  local T = RT()
  return T and T.cutWords(s, maxB or Recap.GOAL_MAX) or ns.Sanitize.cut(s, maxB or Recap.GOAL_MAX)
end

-- the quest log: { questID, title, pos } without headers, hidden and task quests
local function logQuests()
  local api = type(C_QuestLog) == "table" and C_QuestLog or nil
  local out = {}
  if not (api and type(api.GetInfo) == "function") then return out end
  local n = call(api.GetNumQuestLogEntries)
  n = finite(n) and floor(n) or Recap.QUEST_SCAN
  local header -- Classic log: the header above a quest is its zone (Retail: mostly a zone too, else a category)
  for i = 1, min(n, Recap.QUEST_SCAN) do
    local info = call(api.GetInfo, i)
    if type(info) == "table" and not isSecret(info) and info.isHeader == true then
      header = clean(info.title)
    elseif type(info) == "table" and not isSecret(info) and info.isHidden ~= true and info.isTask ~= true then
      local qid = finite(info.questID) and floor(info.questID) or nil
      local title = clean(info.title)
      if qid and title then out[#out + 1] = { questID = qid, title = title, pos = i, header = header } end
    end
  end
  return out
end

-- goal line of an open quest: ready to turn in, else the first open objective (live log, else the index), else the first sentence
-- of the written-down objectives
local function goalOf(index, qid)
  local T = RT()
  local api = type(C_QuestLog) == "table" and C_QuestLog or nil
  if api and type(api.IsComplete) == "function" and call(api.IsComplete, qid) == true then return T.openReady() end
  if api and type(api.GetQuestObjectives) == "function" then
    local list = call(api.GetQuestObjectives, qid)
    if type(list) == "table" and not isSecret(list) then
      for _, o in ipairs(list) do
        if type(o) == "table" and not isSecret(o) and o.finished ~= true then
          local text = line(o.text)
          if text then return text end
        end
      end
    end
  end
  for _, g in ipairs(Idx().questGoals(index, qid)) do
    if finite(g.have) and finite(g.need) and g.need > 0 and g.have < g.need then
      local text = line(g.text, Recap.GOAL_MAX - 12)
      if text then return T.goalLine(text, g.have, g.need) end
    end
  end
  local e = questEntry(index, qid)
  local obj = e and type(e.objectives) == "string" and ns.Sanitize.longText(e.objectives) or nil
  if obj then
    local first = T.sentences(obj)[1]
    if first then return line(first) end
  end
  return nil
end

local function progressOf(index, log)
  local I, W = Idx(), Wel()
  local out = {}
  local touched = W and W.touchedQuests and W.touchedQuests() or {}
  for _, q in ipairs(log) do
    for _, g in ipairs(I.questGoals(index, q.questID)) do
      if finite(g.have) and finite(g.need) and g.need > 0 and g.have < g.need then
        out[#out + 1] = { questID = q.questID, title = q.title, have = floor(g.have), need = floor(g.need), t = touched[q.questID] or 0,
          ratio = g.have / g.need }
        break
      end
    end
  end
  table.sort(out, function(a, b)
    if a.t ~= b.t then return a.t > b.t end
    if a.ratio ~= b.ratio then return a.ratio > b.ratio end
    return a.questID < b.questID
  end)
  while #out > Recap.PROGRESS_MAX do table.remove(out) end
  for _, e in ipairs(out) do e.t, e.ratio = nil, nil end
  return out
end

-- accept time of a quest: char.quests[id].firstAt, else the newest QA line
local function acceptedAt(index, qid, qa)
  local e = questEntry(index, qid)
  if e and finite(e.firstAt) then return e.firstAt end
  return qa[qid] or 0
end

-- open: pin -> quests with progress -> the rest of the log (accepted last first), each with its goal line (list); plus to-dos, work
-- order and trainer (each only with its module). pin / progress stay as before for older readers.
local function openOf(index)
  local W, T, I = Wel(), RT(), Idx()
  local out = { progress = {}, todos = {}, list = {} }
  if not W then return out end
  local log = logQuests()
  local pin = W.pinned()
  if pin then out.pin = { questID = pin.questID, title = pin.title } end
  out.progress = progressOf(index, log)
  local seen = {}
  local function entry(kind, qid, title, group, zone)
    seen[qid] = true
    local goal = goalOf(index, qid)
    return { kind = kind, questID = qid, title = title, goal = goal, group = group, zone = zone, ready = goal ~= nil and goal == T.openReady() }
  end
  -- the zone of a quest: its log header, else the zone where it was accepted (QA); the current zone from the player's position
  local qa, qaMap = {}, {}
  for _, r in ipairs(I.list(index, "QA")) do
    local id = I.num(r, "QA", "questID")
    if id and finite(r.t) and (not qa[id] or r.t > qa[id]) then qa[id], qaMap[id] = r.t, I.num(r, "QA", "mapID") end
  end
  local hereMap = ns.Zone and type(ns.Zone.here) == "function" and call(ns.Zone.here) or nil
  if not finite(hereMap) then hereMap = W.lastMapID and W.lastMapID() or nil end
  local hereName = finite(hereMap) and zoneName(index, hereMap) or nil
  local function same(a, b) return a and b and string.lower(a) == string.lower(b) end
  local byID = {}
  for _, q in ipairs(log) do byID[q.questID] = q end
  local function zoneOfQuest(qid)
    local q = byID[qid]
    local z = q and q.header or nil
    if not z and finite(qaMap[qid]) then z = zoneName(index, qaMap[qid]) end
    return z
  end
  if out.pin then out.list[1] = entry("pin", out.pin.questID, out.pin.title, "pin", zoneOfQuest(out.pin.questID)) end
  -- candidates: progress first, then the rest of the log (accepted last first)
  local cand = {}
  for _, p in ipairs(out.progress) do
    if not seen[p.questID] then cand[#cand + 1] = { kind = "progress", q = { questID = p.questID, title = p.title }, at = huge } seen[p.questID] = true end
  end
  for _, q in ipairs(log) do
    if not seen[q.questID] then cand[#cand + 1] = { kind = "open", q = q, at = acceptedAt(index, q.questID, qa) } end
  end
  for _, c in ipairs(cand) do seen[c.q.questID] = nil end
  table.sort(cand, function(a, b)
    if (a.kind == "progress") ~= (b.kind == "progress") then return a.kind == "progress" end
    if a.at ~= b.at then return a.at > b.at end
    return (a.q.pos or 0) > (b.q.pos or 0)
  end)
  local here, away = {}, {}
  for _, c in ipairs(cand) do
    local z = zoneOfQuest(c.q.questID)
    if hereName and same(z, hereName) then here[#here + 1] = { c = c, z = z } else away[#away + 1] = { c = c, z = z } end
  end
  -- "Hier in der Gegend" first, "Anderswo" keeps up to two places when there is more
  local room = Recap.OPEN_MAX - #out.list
  local nAway = min(#away, max(min(2, #away), room - #here))
  local nHere = min(#here, room - nAway)
  nAway = min(#away, room - nHere)
  for i = 1, nHere do local h = here[i] out.list[#out.list + 1] = entry(h.c.kind, h.c.q.questID, h.c.q.title, "here", h.z) end
  for i = 1, nAway do local a = away[i] out.list[#out.list + 1] = entry(a.c.kind, a.c.q.questID, a.c.q.title, "away", a.z) end
  out.hereZone = hereName
  out.todos = W.todos(Recap.TODOS_MAX)
  local werk = W.werkOrder()
  if werk then out.werk = T.openWerk(werk) end
  if W.trainerOpen() then out.trainer = T.trainerShort() end
  return out
end

-- who the quest texts speak to ($N, $C, $R, $G)
local function whoAmI()
  local who = {}
  who.name = clean(call(UnitName, "player"))
  who.class = clean(call(UnitClass, "player"))
  who.race = clean(call(UnitRace, "player"))
  local sex = call(UnitSex, "player")
  who.sex = finite(sex) and floor(sex) or nil
  return who
end

-- "Zuletzt erledigt": the newest turn-ins of the window, each with 2..3 sentences of its written-down text and the full text
local function doneOf(index, from, to)
  local I, T, S = Idx(), RT(), ns.Sanitize
  local list = {}
  inWin(I.list(index, "QT"), from, to, function(r)
    local qid = I.num(r, "QT", "questID")
    if qid then list[#list + 1] = { qid = floor(qid), t = r.t, r = r } end
  end)
  table.sort(list, function(a, b) return a.t > b.t end)
  local out, seen, who = {}, {}, nil
  for _, d in ipairs(list) do
    if #out >= Recap.DONE_MAX then break end
    if not seen[d.qid] then
      seen[d.qid] = true
      local title = questTitleOf(index, d.qid)
      if title then
        who = who or whoAmI()
        local e = questEntry(index, d.qid) or {}
        local texts = { objectives = S.longText(e.objectives), reward = S.longText(e.reward), detail = S.longText(e.detail) }
        local goals = {}
        for _, g in ipairs(I.questGoals(index, d.qid)) do
          local text = line(g.text, 60)
          if text then goals[#goals + 1] = { text = text, have = g.have, need = g.need } end
        end
        local short, full = T.questText(texts, goals, who)
        -- retold in the past (giver and turn-in NPC with their zone); the full original text stays for the tooltip
        local giver = clean(e.giver) or npcName(index, finite(e.giverNpc) and floor(e.giverNpc) or nil)
        local tnID = I.num(d.r, "QT", "npcID")
        local turnin = (tnID and npcName(index, floor(tnID))) or clean(I.str(d.r, "QT", "npc"))
        local ok, told = pcall(T.retell, texts, { who = who,
          giver = giver and { name = giver, zone = finite(e.mapID) and zoneName(index, e.mapID) or nil } or nil,
          turnin = turnin and { name = turnin, zone = zoneName(index, I.num(d.r, "QT", "mapID")) } or nil })
        if ok and type(told) == "string" and told ~= "" then short = told end
        out[#out + 1] = { questID = d.qid, title = title, text = short, full = full, t = d.t }
      end
    end
  end
  return out
end

-- "Am Rande": a side note that is not in the paragraph: a reminder (Heute vor ...), the longest session so far, the way on foot
local function asideOf(index, from, to)
  local T, W = RT(), Wel()
  local out = {}
  if W and type(W.anniversary) == "function" then
    local st = W.state() or {}
    local anniv = type(st.anniv) == "table" and st.anniv.seen or nil
    local text = call(W.anniversary, anniv, time())
    if type(text) == "string" and text ~= "" then out[#out + 1] = text end
  end
  local list = sessionList()
  if type(list) == "table" and #list >= 3 then
    local best, bestWin = 0, 0
    for _, s in ipairs(list) do
      local d = s.stop - s.start
      if d > best then best = d end
      if s.stop > from and s.start < to and d > bestWin then bestWin = d end
    end
    local DT = Journal.DiaryTexts
    if bestWin >= 3600 and bestWin >= best and DT and type(DT.duration) == "function" then
      local text = T.asideLongest(call(DT.duration, bestWin))
      if text then out[#out + 1] = text end
    end
  end
  local Rest = ns.Rest
  if #out < Recap.ASIDE_MAX and Rest and type(Rest.distance) == "function" then
    local yards, approx = call(Rest.distance, index, from, to)
    if finite(yards) and approx ~= true then
      local text = T.asideWalk(yards * 0.9144 / 1000)
      if text then out[#out + 1] = text end
    end
  end
  while #out > Recap.ASIDE_MAX do table.remove(out) end
  return out
end

-- picture: the last route of the newest session in its main zone ------------------------------------------------------------------
-- The zone: the main zone of the newest trail block that has one (a continent or world map never; a city, cave or sub map counts
-- with its zone). Points of sub maps are projected onto the zone (Geo.zoneProjector, like the journey map); points on a continent
-- (flight) break the line. Marks: the turn-ins (QT with position) of the session in this zone.

local function pointsOf(block)
  local pts = {}
  for dt, x, y, mark in gmatch(block.text, "\n(%-?%d+)~(%-?%d+)~(%-?%d+)~?(%a?)") do
    dt, x, y = tonumber(dt), tonumber(x), tonumber(y)
    if dt and x and y and x >= 0 and x <= 10000 and y >= 0 and y <= 10000 then
      pts[#pts + 1] = { t = block.start + dt, x = x / 10000, y = y / 10000, mark = mark ~= "" and mark or nil }
    end
  end
  return pts
end

Recap.EDGE = 0.02 -- projected points this far outside the zone map still count (clamped), farther ones are dropped

local function projectorFor(zone)
  local Geo = Journal.Geo
  local fn
  if Geo and type(Geo.zoneProjector) == "function" then fn = call(Geo.zoneProjector, zone) end
  return function(map, x, y)
    if map == zone then return x, y end
    if type(fn) ~= "function" then return nil end
    local ok, px, py = pcall(fn, map, x, y)
    if not ok or not finite(px) or not finite(py) then return nil end
    local e = Recap.EDGE
    if px < -e or px > 1 + e or py < -e or py > 1 + e then return nil end
    return max(0, min(1, px)), max(0, min(1, py))
  end
end

Recap.MARK_WEIGHT = 25 -- a turn-in / accept counts like this many trail points when the zone of the picture is chosen

-- the zone of the picture: the main zone where the window happened (trail points plus quest turn-ins and accepts), not the place
-- of the last few minutes (a city visit at the end of the session must not take the picture)
local function pictureZone(index, blocks, from, to)
  local I = Idx()
  local score, last = {}, {}
  for i, b in ipairs(blocks) do
    local z = mainZone(index, b.map)
    if z then
      local _, nl = string.gsub(b.text, "\n", "")
      score[z] = (score[z] or 0) + nl
      last[z] = i
    end
  end
  for _, code in ipairs({ "QT", "QA" }) do
    inWin(I.list(index, code), from, to, function(r)
      local z = mainZone(index, I.num(r, code, "mapID"))
      if z then score[z] = (score[z] or 0) + Recap.MARK_WEIGHT end
    end)
  end
  local best, bestS
  for z, s in pairs(score) do
    if not best or s > bestS or (s == bestS and (last[z] or 0) > (last[best] or 0)) then best, bestS = z, s end
  end
  return best
end
Recap.pictureZone = pictureZone

local function pictureOf(index, from, to)
  local blocks = trailBlocks(index, from, to)
  local n = #blocks
  if n == 0 then return nil end
  local zone = pictureZone(index, blocks, from, to)
  if not zone then return nil end
  local project = projectorFor(zone)
  local function collect(list)
    local all, gap = {}, false
    for _, b in ipairs(list) do
      if mainZone(index, b.map) == zone then
        for _, p in ipairs(pointsOf(b)) do
          local x, y = project(b.map, p.x, p.y)
          if x then
            p.x, p.y = x, y
            if gap then p.mark, gap = p.mark or "l", false end
            all[#all + 1] = p
          else
            gap = true
          end
        end
      else
        gap = true -- a continent (flight) or another zone in between: the line breaks
      end
    end
    return all
  end
  -- every stretch of the window in this zone (other zones and continent flights in between break the line)
  local all = collect(blocks)
  if #all < Recap.POINTS_MIN then return nil end
  local x0, x1, y0, y1 = huge, -huge, huge, -huge
  for _, p in ipairs(all) do
    x0, x1, y0, y1 = min(x0, p.x), max(x1, p.x), min(y0, p.y), max(y1, p.y)
  end
  if (x1 - x0) < Recap.SPAN_MIN and (y1 - y0) < Recap.SPAN_MIN then return nil end
  -- thin out to at most POINTS_MAX; marks (flight, death, landing) stay
  local function special(p) return p.mark == "f" or p.mark == "l" or p.mark == "d" end
  local nSpecial = 0
  for _, p in ipairs(all) do if special(p) then nSpecial = nSpecial + 1 end end
  local k = max(1, math.ceil(#all / max(1, Recap.POINTS_MAX - nSpecial)))
  local kept
  repeat
    kept = {}
    for i, p in ipairs(all) do
      if (i - 1) % k == 0 or i == #all or special(p) then kept[#kept + 1] = p end
    end
    k = k + 1
  until #kept <= Recap.POINTS_MAX or k > #all + 1
  local points, prev, brkNext = {}, nil, false
  for _, p in ipairs(kept) do
    local brk = brkNext or (p.mark == "l")
    if prev and not brk then
      local dx, dy = p.x - prev.x, p.y - prev.y
      if p.t - prev.t > Recap.BREAK_GAP and dx * dx + dy * dy > Recap.BREAK_DIST * Recap.BREAK_DIST then brk = true end
    end
    if brk and prev then points[#points + 1] = { brk = true } end
    points[#points + 1] = { x = p.x, y = p.y }
    brkNext = (p.mark == "f" or p.mark == "d")
    prev = p
  end
  -- quest places of the window in this zone (position written with the line): turn-ins (QT) and accepts (QA), newest kept
  local I = Idx()
  local marks = {}
  for _, code in ipairs({ "QT", "QA" }) do
    local list = {}
    inWin(I.list(index, code), from, to, function(r) list[#list + 1] = r end)
    for i = #list, 1, -1 do
      local r = list[i]
      local m, x, y = I.num(r, code, "mapID"), I.num(r, code, "x"), I.num(r, code, "y")
      if #marks < Recap.MARKS_MAX and m and x and y and x >= 0 and x <= 10000 and y >= 0 and y <= 10000 and mainZone(index, m) == zone then
        local px, py = project(m, x / 10000, y / 10000)
        if px then
          local qid = I.num(r, code, "questID")
          marks[#marks + 1] = { x = px, y = py, kind = code == "QT" and "turnin" or "accept", questID = qid and floor(qid) or nil,
            title = qid and questTitleOf(index, floor(qid)) or nil }
        end
      end
    end
  end
  local first, last = kept[1], kept[#kept]
  return {
    kind = "route", mapID = zone, zoneName = zoneName(index, zone), t0 = first.t, t1 = last.t, points = points,
    startPt = { x = first.x, y = first.y }, endPt = { x = last.x, y = last.y }, marks = marks,
  }
end

-- get -------------------------------------------------------------------------------------------------------------------------

local function build(opts)
  local Store, I, T, M = ns.Store, Idx(), RT(), Journal.Meilensteine
  local char = Store and Store.char and Store.char() or nil
  if not char then return nil, "kein-charakter" end
  if not (I and T and M) then return nil, "keine-daten" end
  local st = Wel() and Wel().state() or {}
  local w = windowSessions(opts, st)
  if not w then return nil, "keine-daten" end
  local index, why = I.get({ noRebuild = true })
  if not index then
    if why == "baut" then return nil, "baut" end
    return nil, why == "kein-charakter" and "kein-charakter" or "keine-daten"
  end
  local explicit = finite(opts.from) and finite(opts.to)
  local from, to = w.from, w.to
  local sec = M.windowSummary(index, from, to + 1)
  if not sec then return nil, "keine-daten" end
  local facts = { zones = {}, highlights = {}, quests = sec.quests or 0, kills = sec.kills or 0, dungeons = sec.dungeons and sec.dungeons.runs or 0 }
  local blocks = trailBlocks(index, from, to)
  facts.zones = zonesOf(index, blocks)
  local ups = 0
  inWin(I.list(index, "LV"), from, to + 1, function() ups = ups + 1 end)
  facts.levelUps = ups
  facts.levelTo = levelAt(index, to)
  facts.levelFrom = levelAt(index, from - 1)
  if not facts.levelTo and not explicit then
    local Live = Journal.Live
    facts.levelTo = Live and call(Live.level) or nil
  end
  local deaths = 0
  inWin(I.list(index, "DE"), from, to + 1, function() deaths = deaths + 1 end)
  facts.deaths = deaths
  facts.highlights = highlightsOf(index, from, to + 1, sec)
  -- every section on its own: an error costs only that section
  local function section(fn, fallback, ...)
    local ok, v = pcall(fn, ...)
    if ok and v ~= nil then return v end
    return fallback
  end
  -- new zones (first arrival in the window, the rule of the milestones) and first times
  local fresh = {}
  for _, nm in ipairs(type(sec.zoneNames) == "table" and sec.zoneNames or {}) do
    local c = clean(nm)
    if c and #fresh < 3 then fresh[#fresh + 1] = c end
  end
  facts.newZones = fresh
  facts.firsts = section(firstsOf, {}, index, from, to + 1)
  local stand = section(standOf, { lines = {} }, index)
  -- "kurz vor Stufe X" only when the window ends at today's level (the stand is live)
  local ctx = { sessions = #w.sessions }
  if stand.level and facts.levelTo == stand.level then ctx.level, ctx.xpPct = stand.level, stand.xpPct end
  local okS, story = pcall(T.story, facts, ctx)
  if not okS or type(story) ~= "table" or #story == 0 then return nil, "leer" end
  local recap = {
    from = from, to = to, sessions = #w.sessions, days = w.days, gapSeconds = max(0, floor(time() - to)),
    story = story, facts = facts,
    stand = stand,
    open = section(openOf, { progress = {}, todos = {}, list = {} }, index),
    -- the newest turn-ins up to now (the running session too): "Zuletzt erledigt" is never empty while anything was turned in
    done = section(doneOf, {}, index, 0, huge),
    aside = section(asideOf, {}, index, from, to + 1),
    picture = section(pictureOf, nil, index, from, to + 1),
  }
  if opts.preview then recap.preview = true end
  return recap
end

function Recap.get(opts)
  opts = type(opts) == "table" and opts or {}
  local ok, rec, why = pcall(build, opts)
  if not ok then return nil, "keine-daten" end
  return rec, why
end

function Recap.last()
  local W = Wel()
  local st = W and W.state() or {}
  if not (finite(st.from) and finite(st.to)) then return nil, "keine-daten" end
  return Recap.get({ from = st.from, to = st.to, preview = true })
end

-- the recap was shown (book opened by itself or by a click): the next one starts after this moment
function Recap.markShown(recap)
  local W = Wel()
  if not W or type(recap) ~= "table" or recap.preview == true or not finite(recap.from) or not finite(recap.to) then return false end
  return W.putState({ at = floor(time()), from = floor(recap.from), to = floor(recap.to), n = floor(tonumber(recap.sessions) or 0) })
end

local waiting, registered = {}, false

local function flush()
  local list = waiting
  waiting = {}
  for _, fn in ipairs(list) do
    if ns.Core and ns.Core.safe then ns.Core.safe(fn) else pcall(fn) end
  end
end

-- fn() once the index is ready: after the next build, or at once (next frame) when an index is there already
function Recap.onReady(fn)
  if type(fn) ~= "function" then return false end
  local I = Idx()
  if not I then return false end
  for _, f in ipairs(waiting) do
    if f == fn then return true end
  end
  waiting[#waiting + 1] = fn
  if not registered then
    registered = true
    I.onReady(flush)
  end
  local ok, index = pcall(I.get, { noRebuild = true })
  if ok and index and type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(0, flush) end
  return true
end
