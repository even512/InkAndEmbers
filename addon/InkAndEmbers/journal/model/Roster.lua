-- Character list of the SV (Twinks: read other characters' books). Reads EveNChronicleDB.chars and the Guard status, never
-- writes into a character table. The only write is the UI marker EveNChronicleDB.ui.hiddenChars[guid] = true ("take off the
-- list"; the data stay).
--
-- API for the book UI (journal/Frame.lua; the read-only guest mode itself lives in journal/Pages.lua):
--   Roster.list(opts) -> rows, sorted: own character first, then lastSeen descending, then name; characters known only to
--     the Guard (missing in the main file) last. opts.hidden = true also returns hidden rows (settings "show hidden").
--     row = { guid, name, realm, surname, ruleset, level, class, classFile, race, raceFile, faction, lastSeen, lines, project,
--             own, empty, missing, otherClient, hidden, openable, reason }
--     Strings are raw SV text (or nil): show them only through Sanitize.display. level = last LV/PL line (cheap, no index),
--     else the highest level in snapshots.stats, else nil. empty = no log blocks yet; missing = known to the Guard mirror
--     but absent from the main file (only guid and lines); otherClient = info.project differs from this client's
--     WOW_PROJECT_ID (characters without the field count as this client). openable/reason as Roster.canOpen.
--   Roster.canOpen(guid) -> true | false, reason: "eigener" (the logged-in character: that is the normal book),
--     "unbekannt" (no such character), "fehlt" (only in the Guard backup), "leer" (no entries), "anderes-spiel" (recorded in
--     another client: its map data are in another map space)
--   Roster.row(guid) -> row | nil (also hidden ones)
--   Roster.hasOthers() -> true when at least one other visible character exists (the "other books" button is shown)
--   Roster.hide(guid) / Roster.unhide(guid) -> bool; Roster.unhideAll() -> number restored; Roster.hiddenCount() -> n
--     (never the own character; only well-formed player guids)
--   Roster.onChange(fn) -> fn() after hide/unhide
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Roster = {}
Journal.Roster = Roster

local floor, huge = math.floor, math.huge
local match, gmatch, find, sub = string.match, string.gmatch, string.find, string.sub

Roster.SCAN_BLOCKS = 40   -- newest log blocks searched for the last LV/PL line (cost bound per character)
Roster.MAX_ROWS = 200     -- characters per list
Roster.GUID_MAX = 64      -- bytes of an accepted guid

local listeners = {}

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == huge or v == -huge then return nil end
  return v
end

local function text(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

-- player guid as the client writes it ("Player-<server>-<hex>"); anything else is never accepted as a key
local function validGuid(g)
  return type(g) == "string" and not isSecret(g) and #g <= Roster.GUID_MAX and find(g, "^Player%-%d+%-%x+$") ~= nil
end
Roster.validGuid = validGuid

local function db()
  local d = EveNChronicleDB
  if type(d) ~= "table" or type(d.chars) ~= "table" then return nil end
  return d
end

local function ownGuid()
  local Index = Journal.Index
  if Index and type(Index.ownGuid) == "function" then return Index.ownGuid() end
  local Store = ns.Store
  return Store and type(Store.guid) == "string" and Store.guid or nil
end

local function clientProject()
  return num(rawget(_G, "WOW_PROJECT_ID"))
end

local function hiddenSet(create)
  local d = db()
  if not d then return nil end
  if type(d.ui) ~= "table" then
    if not create then return nil end
    d.ui = {}
  end
  if type(d.ui.hiddenChars) ~= "table" then
    if not create then return nil end
    d.ui.hiddenChars = {}
  end
  return d.ui.hiddenChars
end

local function levelOk(v)
  v = tonumber(v)
  if v and v >= 1 and v <= 200 then return floor(v) end
  return nil
end

-- last level of a character without building an index: newest LV ("<dt>~LV~<level>") or PL ("<dt>~PL~total~this~<level>")
-- line in the newest blocks, else the highest key of snapshots.stats
local function lastLevel(char)
  local log = type(char.log) == "table" and char.log or nil
  if log then
    local stop = math.max(1, #log - Roster.SCAN_BLOCKS + 1)
    for i = #log, stop, -1 do
      local b = log[i]
      if type(b) == "string" then
        local bestPos, best = 0, nil
        for pos, lv in gmatch(b, "()\n%-?%d+~LV~(%d+)") do
          if pos > bestPos then bestPos, best = pos, lv end
        end
        for pos, lv in gmatch(b, "()\n%-?%d+~PL~[^~\n]*~[^~\n]*~(%d+)") do
          if pos > bestPos then bestPos, best = pos, lv end
        end
        local l = levelOk(best)
        if l then return l end
      end
    end
  end
  local stats = type(char.snapshots) == "table" and char.snapshots.stats
  if type(stats) == "table" then
    local top = nil
    for k in pairs(stats) do
      local l = levelOk(k)
      if l and (not top or l > top) then top = l end
    end
    return top
  end
  return nil
end

local function lineCount(char)
  local G = ns.Guard
  if G and type(G.lineCount) == "function" then
    local ok, n = pcall(G.lineCount, char)
    if ok and num(n) then return n end
  end
  return 0
end

local function decide(row)
  if row.own then return false, "eigener" end
  if row.missing then return false, "fehlt" end
  if row.otherClient then return false, "anderes-spiel" end
  if row.empty then return false, "leer" end
  return true, nil
end

local function rowOf(guid, char, me, hidden, project)
  local info = type(char.info) == "table" and char.info or {}
  local log = type(char.log) == "table" and char.log or nil
  local p = num(info.project)
  local row = {
    guid = guid, name = text(info.name), realm = text(info.realm), surname = text(info.surname), ruleset = text(info.ruleset),
    class = text(info.class), classFile = text(info.classFile),
    race = text(info.race), raceFile = text(info.raceFile), faction = text(info.faction), lastSeen = num(info.lastSeen),
    level = lastLevel(char), lines = lineCount(char), project = p,
    own = guid == me, empty = not log or #log == 0, missing = false,
    otherClient = (p ~= nil and project ~= nil and p ~= project) or false,
    hidden = (hidden and hidden[guid] == true) or false,
  }
  -- the own character always has an open block: not "empty" for the list
  if row.own then row.empty = false end
  row.openable, row.reason = decide(row)
  return row
end

local function missingRows(d, hidden)
  local out = {}
  local G = ns.Guard
  local st = G and type(G.state) == "table" and G.state
  local miss = st and type(st.missing) == "table" and st.missing
  if not miss then return out end
  for g, e in pairs(miss) do
    if validGuid(g) and d.chars[g] == nil and type(e) == "table" then
      local row = { guid = g, lines = num(e.lines) or 0, own = false, empty = true, missing = true, otherClient = false,
        hidden = (hidden and hidden[g] == true) or false }
      row.openable, row.reason = decide(row)
      out[#out + 1] = row
    end
  end
  return out
end

local function before(a, b)
  if a.own ~= b.own then return a.own end
  if a.missing ~= b.missing then return b.missing end
  local la, lb = a.lastSeen or -1, b.lastSeen or -1
  if la ~= lb then return la > lb end
  local na, nb = a.name or "\255", b.name or "\255"
  if na ~= nb then return na < nb end
  return a.guid < b.guid
end

function Roster.list(opts)
  opts = opts or {}
  local d = db()
  if not d then return {} end
  local me, hidden, project = ownGuid(), hiddenSet(false), clientProject()
  local rows = {}
  for g, char in pairs(d.chars) do
    if type(g) == "string" and not isSecret(g) and type(char) == "table" then
      rows[#rows + 1] = rowOf(g, char, me, hidden, project)
    end
  end
  for _, r in ipairs(missingRows(d, hidden)) do rows[#rows + 1] = r end
  local out = {}
  for _, r in ipairs(rows) do
    if opts.hidden or not r.hidden or r.own then out[#out + 1] = r end
  end
  table.sort(out, before)
  for i = #out, Roster.MAX_ROWS + 1, -1 do out[i] = nil end
  return out
end

function Roster.row(guid)
  if type(guid) ~= "string" or isSecret(guid) then return nil end
  local d = db()
  if not d then return nil end
  local char = d.chars[guid]
  local hidden = hiddenSet(false)
  if type(char) == "table" then return rowOf(guid, char, ownGuid(), hidden, clientProject()) end
  for _, r in ipairs(missingRows(d, hidden)) do
    if r.guid == guid then return r end
  end
  return nil
end

function Roster.canOpen(guid)
  local row = Roster.row(guid)
  if not row then return false, "unbekannt" end
  return row.openable, row.reason
end

function Roster.hasOthers()
  for _, r in ipairs(Roster.list()) do
    if not r.own then return true end
  end
  return false
end

local function changed()
  for _, fn in ipairs(listeners) do pcall(fn) end
end

function Roster.onChange(fn)
  if type(fn) ~= "function" then return false end
  for _, f in ipairs(listeners) do
    if f == fn then return true end
  end
  listeners[#listeners + 1] = fn
  return true
end

function Roster.hide(guid)
  if not validGuid(guid) or guid == ownGuid() then return false end
  local d = db()
  if not d then return false end
  local G = ns.Guard
  local known = d.chars[guid] ~= nil
    or (G and type(G.state) == "table" and type(G.state.missing) == "table" and G.state.missing[guid] ~= nil)
  if not known then return false end
  local set = hiddenSet(true)
  if not set then return false end
  set[guid] = true
  changed()
  return true
end

function Roster.unhide(guid)
  if type(guid) ~= "string" or isSecret(guid) then return false end
  local set = hiddenSet(false)
  if not set or set[guid] == nil then return false end
  set[guid] = nil
  changed()
  return true
end

function Roster.unhideAll()
  local set = hiddenSet(false)
  if not set then return 0 end
  local n = 0
  for g in pairs(set) do
    set[g] = nil
    n = n + 1
  end
  if n > 0 then changed() end
  return n
end

function Roster.hiddenCount()
  local set = hiddenSet(false)
  local d = db()
  if not set or not d then return 0 end
  local n = 0
  for g, v in pairs(set) do
    if v == true and type(g) == "string" then n = n + 1 end
  end
  return n
end
