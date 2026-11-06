-- Evaluator for the quest book: pure read logic over the index (QA/QT/QX/QR/SH/KF, kill series) and the character's
-- text tables. All returned texts are display-ready (Sanitize.display per paragraph); use them only via
-- SetText/AddLine.
-- QuestBook.build(index) -> book = { quests, byId, counts, zones, history, areas, levels, truncated }; quest.state:
-- done = a turn-in (QT) exists, abandoned = QX after the last accept, open = accepted but not finished, seen = only
-- texts archived.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local QuestBook = {}
Journal.QuestBook = QuestBook

-- locale scope "m.QuestBook" (English in locales/enUS_model.lua)
QuestBook.T = ns.Locale.ns("m.QuestBook", {
  mapFallback = "Karte %s",
  questNo = "Quest Nr. %s",
  goal = "Ziel",
  -- verb per objective kind; if it is already in the objective text (lowercase) it is not appended
  verbs = { monster = "getötet", item = "gesammelt", object = "benutzt", player = "besiegt" },
  withVerb = "%s %s",
  -- words that may stay lowercase inside a bare name ("Spion der Dunkeleisenzwerge") and first words that open a sentence
  glue = "der die das des dem den von vom zu zur zum im in an auf und",
  actions = "benutzt nutzt setzt erhaltet sprecht redet sammelt tötet besiegt findet bringt geht holt rettet erforscht untersucht zerstört begebt reitet fliegt kauft lernt seht betretet öffnet gebt bergt entzündet plündert fangt besucht überlebt entkommt erreicht löst vertreibt stehlt tretet wendet",
  progress = "%s: %s %%",
  doneN = "%s× %s",
  haveOf = "%s: %s von %s",
  date = "{d}.{m}.{y}",
  meters = "ca. %s m",
  km = "ca. %s km",
})

local floor, huge, max, min = math.floor, math.huge, math.max, math.min
local gmatch, match, sub, find, format = string.gmatch, string.match, string.sub, string.find, string.format
local tsort = table.sort

QuestBook.MAX = 2000          -- quests in the book
QuestBook.SCAN_MAX = 20000    -- entries read from the text table (unusually large SV)
QuestBook.ZONE_MAX = 64       -- zone chips (the rest drops out, the quests stay in the book)
QuestBook.REWARD_MAX = 10     -- reward items per quest (choice + fixed)
QuestBook.CHAIN_SPAN = 5      -- stations of the quest chain
QuestBook.CHAIN_MAX = 200     -- positions of a quest line (as the collector)
QuestBook.EVENT_MAX = 5       -- nodes in the timeline
QuestBook.TEXT_MAX = 6000     -- bytes per long text (displayed)
QuestBook.TITLE_MAX = 80
QuestBook.NAME_MAX = 48
QuestBook.GOAL_MAX = 4        -- quest objectives in the timeline
QuestBook.GOAL_TEXT = 60      -- bytes per objective name
QuestBook.TABLE_CACHE = 8     -- remembered table settings
QuestBook.TRAIL_POINTS = 40000 -- trail points read at most for a distance
QuestBook.TRAIL_BLOCKS = 50000 -- trail blocks in the directory
QuestBook.WALK_GAP, QuestBook.WALK_JUMP = 120, 200 -- seconds without a point and more than 2 % of the map: a gap, not walked
QuestBook.WALK_SPEED = 40     -- yards/s: faster is a jump (hearthstone, portal), not a path

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function finite(v)
  return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local function int(v) -- integer >= 0 and < 2^31 (IDs), else nil
  if isSecret(v) then return nil end
  if type(v) == "string" then
    if not find(v, "^%d+$") or #v > 10 then return nil end
    v = tonumber(v)
  end
  if not finite(v) or v < 0 or v >= 2147483648 or v ~= floor(v) then return nil end
  return v
end

local function disp(v, n)
  if isSecret(v) or type(v) ~= "string" then return nil end
  local S = ns.Sanitize
  return S and S.display(v, n or QuestBook.NAME_MAX) or nil
end

local function tbl(v)
  if type(v) == "table" and not isSecret(v) then return v end
  return nil
end

-- entry of a text table by number or number text (the SV can hold either)
local function entry(t, id)
  t = tbl(t)
  if not t then return nil end
  local e = t[id]
  if e == nil then e = t[format("%.0f", id)] end
  return e
end

function QuestBook.money(copper)
  if not finite(copper) or copper < 0 then return nil end
  if copper > 2 ^ 50 then copper = 2 ^ 50 end
  copper = floor(copper)
  return { g = floor(copper / 10000), s = floor(copper / 100) % 100, k = copper % 100 }
end

function QuestBook.duration(sec) -- via Fmt.duration, seconds below 1 min
  if not finite(sec) or sec < 0 then return nil end
  return ns.Journal.Fmt.duration(min(floor(sec + 0.5), 99999 * 3600), { seconds = true })
end

-- initial: first character of a text (ASCII letter or Latin-1 letter as UTF-8), then the rest
function QuestBook.initial(text)
  if type(text) ~= "string" or text == "" then return nil, text end
  local head = match(text, "^%a") or match(text, "^\195[\128-\191]")
  if not head then return nil, text end
  return head, sub(text, #head + 1)
end

-- long text for display. The SV text is already sanitized (Sanitize.longText), but the SV can be edited from outside:
-- every paragraph goes through Sanitize.display again (codes, control and bidi characters out, "|" doubled).
-- Paragraphs stay ("\n"), at most one blank line in a row, total length capped (UTF-8-safe, with "…").
function QuestBook.longText(v, limit)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  local S = ns.Sanitize
  if not S then return nil end
  limit = (type(limit) == "number" and limit >= 16) and floor(limit) or QuestBook.TEXT_MAX
  local src = S.cut(v, limit * 4 + 64)
  local out, used, blank, cut = {}, 0, false, false
  for para in gmatch(src .. "\n", "([^\n]*)\n") do
    local room = limit - used
    if room < 16 then
      cut = true
      break
    end
    local p = S.display(para, room)
    if p then
      out[#out + 1] = p
      used = used + #p + 1
      blank = false
    elseif not blank and #out > 0 then
      out[#out + 1] = ""
      used = used + 1
      blank = true
    end
  end
  while out[#out] == "" do out[#out] = nil end
  if #out == 0 then return nil end
  local text = table.concat(out, "\n")
  if (cut or #src < #v) and sub(text, -3) ~= "…" then text = text .. "…" end
  return text
end

local function mapName(char, mapID)
  local snaps = tbl(char.snapshots)
  local m = snaps and entry(snaps.maps, mapID)
  local n = tbl(m) and disp(m.name, QuestBook.NAME_MAX) or nil
  return n or ((ns.Journal.View and ns.Journal.View.mapName and ns.Journal.View.mapName(mapID)) or QuestBook.T("mapFallback", format("%.0f", mapID)))
end

local function numField(e, key) -- number > 0 from a field of the text entry
  local v = type(e) == "table" and e[key] or nil
  if isSecret(v) or not finite(v) then return nil end
  return v
end

-- QA/QT/QX by questID: first/last time, count, record of the first accept / last turn-in
local function collect(index)
  local I = Journal.Index
  local qa, qt, qx, qr = {}, {}, {}, {}
  for _, rec in ipairs(I.list(index, "QA")) do
    local id = I.num(rec, "QA", "questID")
    if id then
      local e = qa[id]
      if not e then
        qa[id] = { first = rec.t, last = rec.t, n = 1, rec = rec, all = { rec } }
      else
        if rec.t < e.first then e.first, e.rec = rec.t, rec end
        if rec.t > e.last then e.last = rec.t end
        e.n = e.n + 1
        e.all[e.n] = rec
      end
    end
  end
  for _, rec in ipairs(I.list(index, "QT")) do
    local id = I.num(rec, "QT", "questID")
    if id then
      local e = qt[id]
      if not e then
        qt[id] = { first = rec.t, last = rec.t, n = 1, rec = rec }
      else
        if rec.t < e.first then e.first = rec.t end
        if rec.t >= e.last then e.last, e.rec = rec.t, rec end
        e.n = e.n + 1
      end
    end
  end
  for _, rec in ipairs(I.list(index, "QX")) do
    local id = I.num(rec, "QX", "questID")
    if id then
      local e = qx[id]
      if not e then
        qx[id] = { first = rec.t, last = rec.t, n = 1, rec = rec, all = { rec } }
      else
        if rec.t < e.first then e.first = rec.t end
        if rec.t >= e.last then e.last, e.rec = rec.t, rec end
        e.n = e.n + 1
        e.all[e.n] = rec
      end
    end
  end
  for _, rec in ipairs(I.list(index, "QR")) do
    local id, item = I.num(rec, "QR", "questID"), I.num(rec, "QR", "itemID")
    if id and item then qr[id] = item end
  end
  return qa, qt, qx, qr
end

local function stateOf(a, t, x)
  if t then return "done" end
  if x and (not a or x.last >= a.last) then return "abandoned" end
  if a then return "open" end
  return "seen"
end

-- the newest "limit" rows { id, order } from list, in book order. Bounded min-heap instead of sorting all IDs
-- (a large SV can yield ~80,000 distinct questIDs): O(n log limit), only the remainder is sorted.
local function before(p, q) -- p comes before q in the book
  if p.order ~= q.order then return p.order < q.order end
  return p.id < q.id
end

local function newest(list, limit)
  local heap, n = {}, 0
  for _, row in ipairs(list) do
    if n < limit then
      n = n + 1
      local i = n
      heap[i] = row
      while i > 1 do -- sift up: the oldest row is at the root
        local par = floor(i / 2)
        if not before(heap[i], heap[par]) then break end
        heap[i], heap[par] = heap[par], heap[i]
        i = par
      end
    elseif before(heap[1], row) then
      heap[1] = row
      local i = 1
      while true do
        local l, rr, m = i * 2, i * 2 + 1, i
        if l <= n and before(heap[l], heap[m]) then m = l end
        if rr <= n and before(heap[rr], heap[m]) then m = rr end
        if m == i then break end
        heap[i], heap[m] = heap[m], heap[i]
        i = m
      end
    end
  end
  tsort(heap, before)
  return heap
end

function QuestBook.build(index)
  local book = { quests = {}, byId = {}, counts = { done = 0, open = 0, abandoned = 0, seen = 0, total = 0 }, zones = {},
    truncated = false, filters = {}, history = {}, historyZones = {}, historyFilters = {}, areas = {}, levels = {},
    tables = {}, tableKeys = {} }
  if type(index) ~= "table" then return book end
  local I = Journal.Index
  local char = tbl(index.char) or {}
  local texts = tbl(char.quests) or {}
  local qa, qt, qx, qr = collect(index)
  -- all IDs: text table (read bounded) and log
  local ids, scanned = {}, 0
  for k, e in pairs(texts) do
    scanned = scanned + 1
    if scanned > QuestBook.SCAN_MAX then
      book.truncated = true
      break
    end
    local id = int(k)
    if id and id > 0 and type(e) == "table" then ids[id] = true end
  end
  for _, set in ipairs({ qa, qt, qx }) do
    for id in pairs(set) do ids[id] = true end
  end
  local list = {}
  for id in pairs(ids) do
    local e = entry(texts, id)
    local a, t, x = qa[id], qt[id], qx[id]
    local first = numField(e, "firstAt")
    for _, s in ipairs({ a, t, x }) do
      if s and (not first or s.first < first) then first = s.first end
    end
    list[#list + 1] = { id = id, order = first or 0 }
  end
  if #list > QuestBook.MAX then book.truncated = true end
  list = newest(list, QuestBook.MAX)
  local zoneCount, zoneOrder = {}, {}
  local histCount, histOrder = {}, {}
  for _, row in ipairs(list) do
    local id = row.id
    local e = entry(texts, id)
    local a, t, x = qa[id], qt[id], qx[id]
    local q = { id = id, state = stateOf(a, t, x),
      -- sources for detail(): all records of this quest, stored once here (paging scans no lists)
      src = { qa = a and a.all, qx = x and x.all, qt = t and t.rec, qr = qr[id] } }
    q.title = (type(e) == "table" and disp(e.title, QuestBook.TITLE_MAX)) or QuestBook.T("questNo", format("%.0f", id))
    q.hasText = type(e) == "table" and (type(e.detail) == "string" or type(e.progress) == "string"
      or type(e.reward) == "string" or type(e.objectives) == "string") or false
    q.mapID = (int(type(e) == "table" and e.mapID or nil) or (a and I.num(a.rec, "QA", "mapID")) or (t and I.num(t.rec, "QT", "mapID"))
      or (x and I.num(x.rec, "QX", "mapID")))
    if q.mapID and q.mapID <= 0 then q.mapID = nil end
    q.level = numField(e, "qlevel") or (a and I.num(a.rec, "QA", "qlevel")) or (t and I.num(t.rec, "QT", "qlevel")) or nil
    q.xp = t and I.num(t.rec, "QT", "xp") or nil
    q.line = int(type(e) == "table" and e.questLine or nil)
    q.linePos = int(type(e) == "table" and e.questLinePos or nil)
    q.acceptT = a and a.first or nil
    q.turnT = t and t.last or nil
    q.abandonT = x and x.last or nil
    -- area: head of the quest in the quest log (from the collector on accept), else the map of the accept, else the quest's zone
    q.area = type(e) == "table" and disp(e.category, QuestBook.NAME_MAX) or nil
    if not q.area then
      local am = a and int(I.num(a.rec, "QA", "mapID"))
      if am and am > 0 then q.area = mapName(char, am) end
    end
    if q.mapID then
      q.zone = mapName(char, q.mapID)
      if not zoneCount[q.mapID] then
        zoneCount[q.mapID] = 0
        zoneOrder[#zoneOrder + 1] = q.mapID
      end
      zoneCount[q.mapID] = zoneCount[q.mapID] + 1
    end
    book.quests[#book.quests + 1] = q
    book.byId[id] = q
    if q.state == "done" or q.state == "abandoned" then
      book.history[#book.history + 1] = q
      if q.mapID then
        if not histCount[q.mapID] then
          histCount[q.mapID] = 0
          histOrder[#histOrder + 1] = q.mapID
        end
        histCount[q.mapID] = histCount[q.mapID] + 1
      end
    end
    if not q.area then q.area = q.zone end
    book.counts[q.state] = book.counts[q.state] + 1
  end
  book.counts.total = #book.quests
  -- filter values of the table: areas (by name) and quest levels (ascending), over the history only
  local areaN, levelN = {}, {}
  for _, q in ipairs(book.history) do
    if q.area then
      if not areaN[q.area] then
        areaN[q.area] = 0
        book.areas[#book.areas + 1] = { name = q.area }
      end
      areaN[q.area] = areaN[q.area] + 1
    end
    local lv = q.level and q.level >= 0 and q.level < 1000 and floor(q.level) or nil
    if lv then
      if not levelN[lv] then
        levelN[lv] = 0
        book.levels[#book.levels + 1] = { level = lv }
      end
      levelN[lv] = levelN[lv] + 1
    end
  end
  for _, z in ipairs(book.areas) do z.count = areaN[z.name] end
  for _, z in ipairs(book.levels) do z.count = levelN[z.level] end
  tsort(book.areas, function(p, r) return p.name < r.name end)
  while #book.areas > QuestBook.ZONE_MAX do book.areas[#book.areas] = nil end
  tsort(book.levels, function(p, r) return p.level < r.level end)
  local function zoneList(order, count, out)
    for _, m in ipairs(order) do
      out[#out + 1] = { mapID = m, name = mapName(char, m), count = count[m] }
    end
    tsort(out, function(p, q)
      if p.count ~= q.count then return p.count > q.count end
      if p.name ~= q.name then return p.name < q.name end
      return p.mapID < q.mapID
    end)
    while #out > QuestBook.ZONE_MAX do out[#out] = nil end
  end
  zoneList(zoneOrder, zoneCount, book.zones)
  zoneList(histOrder, histCount, book.historyZones)
  return book
end

function QuestBook.filter(book, mapID)
  if type(book) ~= "table" then return {} end
  if mapID == nil then return book.quests end
  local f = book.filters[mapID]
  if f then return f end
  f = {}
  for _, q in ipairs(book.quests) do
    if q.mapID == mapID then f[#f + 1] = q end
  end
  book.filters[mapID] = f
  return f
end

function QuestBook.historyFilter(book, mapID)
  if type(book) ~= "table" or type(book.history) ~= "table" then return {} end
  if mapID == nil then return book.history end
  local f = book.historyFilters[mapID]
  if f then return f end
  f = {}
  for _, q in ipairs(book.history) do
    if q.mapID == mapID then f[#f + 1] = q end
  end
  book.historyFilters[mapID] = f
  return f
end

function QuestBook.position(list, id)
  for i, q in ipairs(list or {}) do
    if q.id == id then return i end
  end
  return nil
end

-- comparison form of a text: lowercase, including Latin-1 capitals as UTF-8 (Ä -> ä)
local function fold(s)
  s = string.lower(s)
  return (string.gsub(s, "\195([\128-\158])", function(c) return "\195" .. string.char(c:byte() + 32) end))
end
QuestBook.fold = fold

-- search and sort key: like fold, plus umlauts as their base letter (DIN 5007-1: ä = a, ß = ss)
-- so "Ärger" sorts under A and the search "wolfe" also finds "Wölfe"
local BASE = { ["\195\164"] = "a", ["\195\182"] = "o", ["\195\188"] = "u", ["\195\159"] = "ss" }
local function sortKey(s)
  return (string.gsub(fold(s), "\195[\164\182\188\159]", BASE))
end
QuestBook.sortKey = sortKey

local function dateKey(q) return q.turnT end

local SORTERS = {
  name = function(q) return q.titleKey end,
  area = function(q) return q.areaKey end,
  level = function(q) return q.level end,
  date = dateKey,
}

function QuestBook.table(book, opts)
  if type(book) ~= "table" or type(book.history) ~= "table" then return {} end
  opts = type(opts) == "table" and opts or {}
  local sortBy = SORTERS[opts.sort] and opts.sort or "date"
  local desc = opts.desc and true or false
  local needle = type(opts.name) == "string" and opts.name ~= "" and sortKey(opts.name) or nil
  local area = type(opts.area) == "string" and opts.area or nil
  local level = type(opts.level) == "number" and opts.level or nil
  local ck = table.concat({ sortBy, desc and "d" or "a", needle or "", area or "", level and format("%.0f", level) or "" }, "\1")
  local hit = book.tables[ck]
  if hit then return hit end
  local out = {}
  for i, q in ipairs(book.history) do
    if not q.titleKey then
      q.titleKey = sortKey(q.title)
      q.areaKey = q.area and sortKey(q.area) or nil
    end
    q.order = q.order or i
    if (not needle or find(q.titleKey, needle, 1, true)) and (not area or q.area == area)
      and (not level or (q.level and floor(q.level) == level)) then
      out[#out + 1] = q
    end
  end
  local get = SORTERS[sortBy]
  tsort(out, function(p, r)
    local a, b = get(p), get(r)
    if a ~= b then
      if a == nil then return false end -- missing values always go last
      if b == nil then return true end
      if desc then return a > b end
      return a < b
    end
    if p.order ~= r.order then
      if desc then return p.order > r.order end
      return p.order < r.order
    end
    return p.id < r.id
  end)
  -- small memo: the oldest settings drop out
  local keys = book.tableKeys
  keys[#keys + 1] = ck
  book.tables[ck] = out
  while #keys > QuestBook.TABLE_CACHE do
    book.tables[table.remove(keys, 1)] = nil
  end
  return out
end

local VERB_KINDS = { monster = true, item = true, object = true, player = true }
local BARE_WORDS_MAX = 4
local LOWER_LATIN = { [164] = true, [182] = true, [188] = true, [159] = true } -- second byte of a, o, u umlauts and sharp s

local function wordSet(text)
  local set = {}
  for w in string.gmatch(text or "", "%S+") do set[w] = true end
  return set
end

-- true for a bare name ("Mondrudel-Worg", "Spion der Dunkeleisenzwerge") that still needs a verb; false when the client's
-- objective text is already a phrase ("Ratten gefangen", "Benutzt Farsens Fernsicht", "Use the Farsight"): a lowercase word
-- that is no glue word, an opening verb, or more than a handful of words
local function looksBare(name)
  local T = QuestBook.T
  local glue, actions = wordSet(T.glue), wordSet(T.actions)
  local n = 0
  for w in string.gmatch(name, "%S+") do
    n = n + 1
    local lw = fold(w)
    if n == 1 and actions[lw] then return false end
    if n > 1 and not glue[lw] and (string.find(w, "^[a-z]") or (string.byte(w, 1) == 195 and LOWER_LATIN[string.byte(w, 2)])) then return false end
  end
  return n >= 1 and n <= BARE_WORDS_MAX
end

function QuestBook.objectiveText(o)
  if type(o) ~= "table" then return nil end
  local T = QuestBook.T
  local have = finite(o.have) and floor(o.have) or 0
  local need = finite(o.need) and o.need > 0 and floor(o.need) or nil
  local name = disp(o.text, QuestBook.GOAL_TEXT) or T.goal
  if o.kind == "progressbar" then
    return T("progress", name, format("%d", min(100, have)))
  end
  local done = need and have >= need or (not need and have > 0)
  local verb = VERB_KINDS[o.kind] and T.verbs[o.kind] or nil
  if verb and (find(fold(name), verb, 1, true) or not looksBare(name)) then verb = nil end -- the text already names the verb or reads as a phrase
  local base = verb and T("withVerb", name, verb) or name
  if done then
    if need and need > 1 then return T("doneN", format("%d", have), base) end
    return base
  end
  if need then return T("haveOf", base, format("%d", have), format("%d", need)) end
  return base
end

-- "28.10.2026" in the character's local time | nil
function QuestBook.dateText(index, t)
  local I = Journal.Index
  if not (I and I.dateOf) then return nil end
  local dd, mm, yy = I.dateOf(index, t)
  if not (dd and mm and yy) then return nil end
  return QuestBook.T("date", { d = format("%02d", dd), m = format("%02d", mm), y = format("%04d", yy) })
end

function QuestBook.distance(m)
  if not finite(m) or m < 20 then return nil end
  if m < 1000 then return QuestBook.T("meters", format("%d", floor(m / 10 + 0.5) * 10)) end
  local km = ns.Journal.Fmt.km(floor(m / 100 + 0.5) / 10)
  return QuestBook.T("km", km)
end

-- directory of the trail blocks (start time, map, text) per index, weak; the Store's open block counts too
local trailDir = setmetatable({}, { __mode = "k" })

local function trailHeads(index)
  local d = trailDir[index]
  if d then return d end
  d = { heads = {}, walks = {} }
  trailDir[index] = d
  local char = tbl(index.char) or {}
  local trail = tbl(char.trail) or {}
  local n = 0
  for i = 1, min(#trail, QuestBook.TRAIL_BLOCKS) do
    local b = trail[i]
    if type(b) == "string" then
      local s, m = match(b, "^#~(%-?%d+)~(%d+)")
      s, m = tonumber(s), tonumber(m)
      if finite(s) and m and m > 0 then
        n = n + 1
        d.heads[n] = { t = s, map = m, text = b }
      end
    end
  end
  local Store = ns.Store
  local open = Store and Store.current == index.char and tbl(Store.trailBlock) or nil
  if open and type(open.lines) == "table" and finite(open.start) and finite(open.mapID) then
    n = n + 1
    d.heads[n] = { t = open.start, map = open.mapID, lines = open.lines }
  end
  tsort(d.heads, function(p, q) return p.t < q.t end)
  return d
end

local function mapYards(map)
  local Geo = Journal.Geo
  if not (Geo and Geo.mapSize) then return nil end
  local ok, w, h = pcall(Geo.mapSize, map)
  if ok and finite(w) and finite(h) and w > 0 and h > 0 then return w, h end
  return nil
end

function QuestBook.walked(index, t0, t1)
  if type(index) ~= "table" or not finite(t0) or not finite(t1) or t1 <= t0 then return nil end
  local d = trailHeads(index)
  local ck = format("%.0f:%.0f", t0, t1)
  local hit = d.walks[ck]
  if hit ~= nil then return hit or nil end
  local heads = d.heads
  local yards, read = 0, 0
  local sqrt = math.sqrt
  local G2 = QuestBook.WALK_JUMP * QuestBook.WALK_JUMP
  for i, h in ipairs(heads) do
    local nextT = heads[i + 1] and heads[i + 1].t or huge
    if h.t > t1 then break end
    if nextT >= t0 then
      local w, hh = mapYards(h.map)
      if w then
        local pt, px, py, pm
        local function point(dt, x, y, mark)
          local t = h.t + (tonumber(dt) or 0)
          x, y = tonumber(x), tonumber(y)
          if not (x and y) then return end
          if mark == "" then mark = nil end
          if t >= t0 and t <= t1 and pt and pt >= t0 then
            local dx, dy = x - px, y - py
            local skip = pm == "d" or pm == "f" or mark == "z" or (t - pt > QuestBook.WALK_GAP and dx * dx + dy * dy > G2)
            if not skip then
              local yd = sqrt((dx / 10000 * w) ^ 2 + (dy / 10000 * hh) ^ 2)
              if t - pt <= 0 or yd / (t - pt) <= QuestBook.WALK_SPEED then yards = yards + yd end
            end
          end
          pt, px, py, pm = t, x, y, mark
        end
        if h.text then
          for dt, x, y, mark in gmatch(h.text, "\n(%-?%d+)~(%d+)~(%d+)~?(%a?)") do
            read = read + 1
            if read > QuestBook.TRAIL_POINTS then break end
            point(dt, x, y, mark)
          end
        else
          for _, line in ipairs(h.lines) do
            read = read + 1
            if read > QuestBook.TRAIL_POINTS then break end
            if type(line) == "string" then
              local dt, x, y, mark = match(line, "^(%-?%d+)~(%d+)~(%d+)~?(%a?)")
              if dt then point(dt, x, y, mark) end
            end
          end
        end
      end
    end
    if read > QuestBook.TRAIL_POINTS then break end
  end
  local m = yards > 0 and yards * 0.9144 or nil
  d.walks[ck] = m or false
  return m
end

local function eventOf(index, kind, t, level, mapID, char, confirmed)
  local I = Journal.Index
  local h, m = I.timeOfDay(index, t)
  return { kind = kind, t = t, day = I.dayOf(index, t), clock = h and format("%02d:%02d", h, m) or nil,
    level = (level and level > 0 and level < 1000) and floor(level) or nil,
    zone = mapID and mapID > 0 and mapName(char, mapID) or nil, confirmed = confirmed }
end

local SHOT_KEY = "^%d%d%d%d%d%d_%d%d%d%d%d%d$"

-- time lists for KF (close wins) and SH (photos), built sorted once per index (weak): paging then uses binary search
-- instead of scanning the whole lists
local auxCache = setmetatable({}, { __mode = "k" })

local function aux(index)
  local a = auxCache[index]
  if a then return a end
  local I = Journal.Index
  local kf = {}
  for _, rec in ipairs(I.list(index, "KF")) do
    if finite(rec.t) then kf[#kf + 1] = rec.t end
  end
  tsort(kf)
  local sh = { t = {}, rec = {} }
  local recs = {}
  for _, rec in ipairs(I.list(index, "SH")) do
    if finite(rec.t) then recs[#recs + 1] = rec end
  end
  tsort(recs, function(p, q) return p.t < q.t end)
  for i, rec in ipairs(recs) do sh.t[i], sh.rec[i] = rec.t, rec end
  a = { kf = kf, sh = sh }
  auxCache[index] = a
  return a
end

local function lowerBound(arr, t) -- first index with arr[i] >= t (#arr + 1 if none)
  local lo, hi = 1, #arr + 1
  while lo < hi do
    local mid = floor((lo + hi) / 2)
    if arr[mid] < t then lo = mid + 1 else hi = mid end
  end
  return lo
end

local function countBetween(arr, t0, t1) -- entries with t0 <= t < t1
  return max(0, lowerBound(arr, t1) - lowerBound(arr, t0))
end

-- the kill series is capped (Index.KILLT_MAX) and the period reaches past its end, or there is no series:
-- then the count is unknown (instead of "no kills")
local function killsUnknown(index, t1)
  local ks = type(index.killSeries) == "table" and index.killSeries or nil
  if not ks or type(ks.b) ~= "table" then return true end
  local tr = type(index.truncated) == "table" and index.truncated or nil
  if not (tr and tr.killT) then return false end
  local last = ks.b[#ks.b]
  return not finite(last) or t1 >= (last + 1) * (tonumber(ks.size) or 60)
end

QuestBook.INFER_WINDOW = 60 -- seconds around the turn-in in which a received item (LT line) counts as the choice

-- item IDs of an archived reward list ({ { id = n }, ... } or plain numbers) into the set; returns the number added
local function idSet(list, ids)
  list = tbl(list)
  if not list or isSecret(list) then return 0 end
  local n = 0
  for i = 1, QuestBook.REWARD_MAX do
    local v = list[i]
    if v == nil then break end
    local id = int(type(v) == "table" and not isSecret(v) and v.id or v)
    if id and id > 0 and not ids[id] then
      ids[id] = true
      n = n + 1
    end
  end
  return n
end

-- itemID -> number of turned-in quests of the character that offer it (choice or fixed); cached per index and QT count
local offerCache = setmetatable({}, { __mode = "k" })
local function offers(index)
  local I = Journal.Index
  local qts = I.list(index, "QT")
  local c = offerCache[index]
  if c and c.n == #qts then return c.map end
  local char = tbl(index and index.char) or {}
  local map, done = {}, {}
  for _, rec in ipairs(qts) do
    local qid = int(I.num(rec, "QT", "questID"))
    if qid and not done[qid] then
      done[qid] = true
      local e = tbl(entry(char.quests, qid))
      if e then
        local ids = {}
        idSet(e.rewardChoices, ids)
        idSet(e.rewardItems, ids)
        for id in pairs(ids) do map[id] = (map[id] or 0) + 1 end
      end
    end
  end
  offerCache[index] = { n = #qts, map = map }
  return map
end

-- itemID of the chosen reward from what was received, or nil. Exactly one choice item has to fit (no guessing):
-- first an LT line from the quest context close to the turn-in (green and better), else the counter of
-- received quest items (char.counters.quest_items, grey/white, without time). The counter knows no quest, so it
-- only counts if no other turned-in quest of the character offers that item as well.
function QuestBook.inferChoice(index, choices, t)
  local ids = {}
  if idSet(choices, ids) == 0 then return nil end
  local I = Journal.Index
  local function only(test)
    local hit
    for id in pairs(ids) do
      if test(id) then
        if hit then return nil end -- two fit: unclear
        hit = id
      end
    end
    return hit
  end
  if finite(t) then
    local near = {}
    for _, rec in ipairs(I.list(index, "LT")) do
      if finite(rec.t) and math.abs(rec.t - t) <= QuestBook.INFER_WINDOW then
        local kind = I.str(rec, "LT", "source")
        local id = int(tonumber(match(I.str(rec, "LT", "item") or "", "^(%d+)")))
        if id and (kind == "quest" or kind == "other") then near[id] = true end
      end
    end
    local hit = only(function(id) return near[id] end)
    if hit then return hit end
  end
  local char = tbl(index and index.char)
  local counters = char and tbl(char.counters)
  local got = counters and tbl(counters.quest_items)
  if not got then return nil end
  local hit = only(function(id)
    local c = entry(got, id)
    return finite(c) and c > 0
  end)
  if hit and (offers(index)[hit] or 0) > 1 then return nil end -- also offered by another quest: unclear
  return hit
end

function QuestBook.detail(index, q, now)
  local I = Journal.Index
  local char = tbl(index and index.char) or {}
  local e = entry(char.quests, q.id)
  e = tbl(e) or {}
  local d = { id = q.id, title = q.title, state = q.state, level = q.level, zone = q.zone, texts = {}, events = {} }
  -- quest giver: name from the text archive, else the NPC table, else the name from the accept line
  d.giver = disp(e.giver, QuestBook.NAME_MAX)
  if not d.giver then
    local npc = int(e.giverNpc)
    local n = npc and entry(char.npcs, npc)
    if type(n) == "string" then d.giver = disp(n, QuestBook.NAME_MAX) end
  end
  for _, key in ipairs({ "detail", "objectives", "progress", "reward" }) do
    d.texts[key] = QuestBook.longText(e[key])
  end
  -- timeline: all accepts and abandons, the last turn-in; sorted by time, with too little room the start and end
  local ev = {}
  local src = type(q.src) == "table" and q.src or {}
  local lastQT = src.qt
  for _, rec in ipairs(src.qa or {}) do
    ev[#ev + 1] = eventOf(index, "accepted", rec.t, I.num(rec, "QA", "level"), I.num(rec, "QA", "mapID"), char)
    if not d.giver then d.giver = disp(I.str(rec, "QA", "npc"), QuestBook.NAME_MAX) end
  end
  for _, rec in ipairs(src.qx or {}) do
    ev[#ev + 1] = eventOf(index, "abandoned", rec.t, I.num(rec, "QX", "level"), I.num(rec, "QX", "mapID"), char,
      I.num(rec, "QX", "confirmed") == 1)
  end
  if lastQT then
    ev[#ev + 1] = eventOf(index, "turned", lastQT.t, I.num(lastQT, "QT", "level"), I.num(lastQT, "QT", "mapID"), char)
  end
  tsort(ev, function(p, r)
    if p.t ~= r.t then return p.t < r.t end
    return p.kind < r.kind
  end)
  local firstA, outcome
  for _, x in ipairs(ev) do
    if x.kind == "accepted" and not firstA then firstA = x end
    if x.kind ~= "accepted" then
      outcome = x
    elseif q.state ~= "done" then
      outcome = nil -- abandoned, then accepted again: the quest is open again and the period runs until now
    end
  end
  if #ev > QuestBook.EVENT_MAX - 1 then -- leave room for the "Unterwegs" node: first entry and the last ones
    local keep = { ev[1] }
    for i = #ev - (QuestBook.EVENT_MAX - 3), #ev do keep[#keep + 1] = ev[i] end
    ev = keep
  end
  d.events = ev
  -- period first accept to end (turn-in/abandon), open: until now
  if firstA then
    local t0 = firstA.t
    local t1, open = outcome and outcome.t or nil, false
    if not t1 or t1 < t0 then
      t1, open = tonumber(now) or index.lastT or t0, true
      if not finite(t1) or t1 < t0 then t1 = t0 end
    end
    if t1 > t0 then
      local kills, exact = I.killsBetween(index, t0, t1)
      local close = countBetween(aux(index).kf, t0, t1)
      local active, activeExact = I.activeSeconds(index, t0, t1)
      d.way = { kills = kills, exact = exact, close = close, active = active, activeExact = activeExact, open = open,
        seconds = t1 - t0, killsUnknown = killsUnknown(index, t1) }
    end
  end
  -- "Unterwegs": final state per quest objective (QO), else the distance walked between accept and end
  d.goals = {}
  for _, o in ipairs(I.questGoals(index, q.id)) do
    if #d.goals >= QuestBook.GOAL_MAX then
      d.goalsMore = (d.goalsMore or 0) + 1
    else
      local text = QuestBook.objectiveText(o)
      if text then
        local need = finite(o.need) and o.need or nil
        d.goals[#d.goals + 1] = { text = text, done = (need and finite(o.have) and o.have >= need) or false,
          steps = finite(o.n) and o.n or 1 }
      end
    end
  end
  if #d.goals == 0 and d.way and not d.way.open and firstA and outcome then
    d.walked = QuestBook.walked(index, firstA.t, outcome.t)
  end
  if lastQT then d.turnDate = QuestBook.dateText(index, lastQT.t) end
  -- screenshot around the turn-in (+-10 s): file name from the key (strictly checked)
  if lastQT then
    local best, bestDt
    local shots = aux(index).sh
    for i = lowerBound(shots.t, lastQT.t - 10), #shots.t do
      if shots.t[i] > lastQT.t + 10 then break end
      local rec = shots.rec[i]
      local dt = math.abs(rec.t - lastQT.t)
      if not bestDt or dt < bestDt then
        local key = I.str(rec, "SH", "key")
        if key and find(key, SHOT_KEY) then best, bestDt = key, dt end
      end
    end
    if best then d.shot = "WoWScrnShot_" .. best .. ".jpg" end
  end
  if lastQT or numField(e, "rewardMoney") then
    local r = { xp = lastQT and I.num(lastQT, "QT", "xp") or nil, money = lastQT and I.num(lastQT, "QT", "money") or nil }
    if (r.money == nil or r.money == 0) and numField(e, "rewardMoney") then r.money = numField(e, "rewardMoney") end
    local choices = numField(e, "choices")
    r.choices = (choices and choices > 0 and choices < 100) and floor(choices) or nil
    local item = lastQT and I.num(lastQT, "QT", "itemID") or nil
    if not item then item = src.qr end
    item = int(item)
    if (not item or item <= 0) and lastQT and r.choices then
      -- choice not recorded (quest UI without the GetQuestReward hook, before 1.0.2): derive it from received items
      item = QuestBook.inferChoice(index, e.rewardChoices, lastQT.t)
      if item then r.inferred = true end
    end
    if item and item > 0 then
      r.itemID = item
      local snaps = tbl(char.snapshots)
      local it = snaps and entry(snaps.items, item)
      if type(it) == "table" then
        r.itemName = disp(it.name, QuestBook.NAME_MAX)
        local qual = it.quality
        if finite(qual) and qual >= 0 and qual <= 8 then r.itemQuality = floor(qual) end
      end
      r.chosen = true
    end
    -- all reward items (choice and fixed) as far as archived; the chosen one gets chosen
    local snaps = tbl(char.snapshots)
    local items, seen = {}, {}
    local function add(id, n, kind)
      id = int(id)
      if not id or id <= 0 or seen[kind .. id] or #items >= QuestBook.REWARD_MAX then return end
      seen[kind .. id] = true
      local it = { itemID = id, kind = kind, chosen = (kind == "choice" and id == r.itemID) or false }
      local c = int(n)
      if c and c > 1 and c < 100000 then it.count = c end
      local snap = snaps and entry(snaps.items, id)
      if type(snap) == "table" then
        it.name = disp(snap.name, QuestBook.NAME_MAX)
        local qual = snap.quality
        if finite(qual) and qual >= 0 and qual <= 8 then it.quality = floor(qual) end
      end
      items[#items + 1] = it
    end
    local function each(list, kind)
      list = tbl(list)
      if not list then return 0 end
      local n = 0
      for i = 1, QuestBook.REWARD_MAX do
        local v = list[i]
        if v == nil then break end
        if type(v) == "table" and not isSecret(v) then
          add(v.id, v.n, kind)
          n = n + 1
        elseif type(v) == "number" then
          add(v, nil, kind)
          n = n + 1
        end
      end
      return n
    end
    local listed = each(e.rewardChoices, "choice")
    if r.itemID and not seen["choice" .. r.itemID] then add(r.itemID, nil, "choice") end -- old data: only the chosen one
    each(e.rewardItems, "fixed")
    r.items = items
    r.partial = (r.choices and r.choices > 1 and listed < r.choices) and true or nil
    -- turned in, choice items known, but which one was taken is not: say so instead of "not chosen"
    if lastQT and listed > 0 and not r.itemID then r.choiceNotRecorded = true end
    d.reward = r
  end
  local line = int(e.questLine)
  if line then
    d.chain = { name = disp(e.questLineName, QuestBook.NAME_MAX), pos = int(e.questLinePos), len = int(e.questLineLen) }
  end
  return d
end

-- quest chain: stations from all quests of the book with the same quest line

local function chainLines(book)
  local l = book.lines
  if l then return l end
  l = {}
  for _, q in ipairs(book.quests or {}) do
    if q.line and q.linePos and q.linePos >= 1 and q.linePos <= QuestBook.CHAIN_MAX then
      local c = l[q.line]
      if not c then
        c = { max = 0 }
        l[q.line] = c
      end
      local old = c[q.linePos]
      -- two quests at the same position (faction/class variants): the completed one wins, else the first
      if not old or (old.state ~= "done" and q.state == "done") then c[q.linePos] = q end
      if q.linePos > c.max then c.max = q.linePos end
    end
  end
  book.lines = l
  return l
end

function QuestBook.chain(book, q, chain, span)
  if type(book) ~= "table" or type(q) ~= "table" or not q.line then return nil end
  chain = type(chain) == "table" and chain or {}
  local c = chainLines(book)[q.line]
  local pos = q.linePos or chain.pos
  if not c or not pos then return nil end
  local len = chain.len
  if not len or len < c.max then len = c.max end
  if len < pos then len = pos end
  if len > QuestBook.CHAIN_MAX then len = QuestBook.CHAIN_MAX end
  span = (type(span) == "number" and span >= 1) and floor(span) or QuestBook.CHAIN_SPAN
  local from = pos - floor((span - 1) / 2)
  if from + span - 1 > len then from = len - span + 1 end
  if from < 1 then from = 1 end
  local to = min(len, from + span - 1)
  local out = { name = chain.name, pos = pos, len = len, stations = {}, before = from - 1, after = len - to }
  for p = from, to do
    local x = c[p]
    if p == pos then x = q end
    out.stations[#out.stations + 1] = { pos = p, id = x and x.id or nil, title = x and x.title or nil,
      state = x and x.state or nil, current = p == pos }
  end
  return out
end
