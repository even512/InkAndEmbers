-- Data safety (0.9.4): a mirror of the own character in the per-character SavedVariables InkAndEmbersCharDB, the restore
-- decision at login, the load-failure hint, the constants guard, the warning window and /chronik sicherung.
--
-- Rules (never lose data):
--   * The mirror shares the character table with EveNChronicleDB.chars[guid] at runtime (no second copy in memory); WoW writes
--     both files on logout and reload.
--   * At login the mirror replaces the character of the main file only if the main file lacks it, holds it without lines, or holds
--     an older state (more lines in the mirror AND its newest block header is not older). Otherwise the main file stays.
--   * The losing state is kept in EveNChronicleDB.archive[guid] whenever it holds a log or trail block the winner does not have
--     (or a newer block header). Nothing is deleted automatically.
--   * When anything goes wrong in the decision, the loaded mirror stays untouched (WoW writes it back unchanged).
local _, ns = ...

local Guard = {}
ns.Guard = Guard

local floor, format, concat = math.floor, string.format, table.concat
local find, sub, match = string.find, string.sub, string.match

local T = ns.Locale.ns("Guard", {
  title = "Ink & Embers: Datensicherung",
  ok = "Verstanden",
  restored = "Die Daten dieses Charakters wurden aus seiner eigenen Sicherungskopie wiederhergestellt (%d Einträge), weil die Hauptdatei sie %s. Es ist nichts verloren gegangen. Details: /chronik sicherung",
  reasonMissing = "nicht enthielt",
  reasonEmpty = "ohne Einträge enthielt",
  reasonOlder = "nur in einem älteren Stand enthielt",
  archived = "Ein abweichender Stand dieses Charakters wurde in EveNChronicleDB.archive aufbewahrt (nichts gelöscht).",
  missingChars = "In der Hauptdatei fehlen die Daten von %d weiteren Charakteren. Sie werden beim Einloggen dieser Charaktere aus deren eigener Sicherungskopie zurückgeholt. Am sichersten: jetzt, bei laufendem Spiel, die Dateien InkAndEmbers.lua und InkAndEmbers.lua.bak aus WTF\\Account\\<Konto>\\SavedVariables an einen sicheren Ort kopieren (Anleitung: README, \"Keeping your data safe\").",
  freshSuspect = "Ink & Embers hat keine gespeicherten Daten gefunden und ein neues Tagebuch begonnen. Benutzt Ihr das Addon zum ersten Mal, ist alles in Ordnung. Habt Ihr es schon benutzt, hat das Spiel die Datei nicht geladen: Spiel jetzt beenden (kein /reload), dann InkAndEmbers.lua.bak zurückkopieren. Anleitung: README, \"Keeping your data safe\".",
  constantsAlert = "Die Hauptdatei von Ink & Embers ist zu %s gefüllt. Ab 100 %% kann das Spiel sie nicht mehr laden. Eure Charaktere sind über ihre eigenen Sicherungskopien geschützt, trotzdem: bitte den Ordner WTF sichern und uns Bescheid geben (Feedback: README oder CurseForge).",
  constantsHint = "Die Hauptdatei ist zu %s gefüllt; ab 100 %% kann das Spiel sie nicht mehr laden. Bitte den Ordner WTF ab und zu sichern. Details: /chronik sicherung",
  pct = "%d,%d %%",
  dateFmt = "%d.%m.%Y %H:%M",
  backupTitle = "Datensicherung:",
  mirrorState = "Sicherungskopie dieses Charakters: zuletzt geschrieben %s (%d Einträge).",
  mirrorNone = "Sicherungskopie dieses Charakters: noch keine; sie entsteht beim nächsten Sichern oder Ausloggen.",
  mirrorOff = "Sicherungskopie dieses Charakters: in dieser Sitzung nicht geschrieben (siehe EveNChronicleDB.diag.recovery).",
  lastSave = "Zuletzt gespeichert: %s.",
  constantsState = "Füllstand der Hauptdatei: %s (%d von %d Konstanten, gezählt %s).",
  constantsPending = "Füllstand der Hauptdatei: wird noch gezählt.",
  recoveryLast = "Letzte Wiederherstellung: %s (%s).",
  recoveryNone = "Bisher keine Wiederherstellung.",
  archiveCount = "Aufbewahrte Altstände: %d (in EveNChronicleDB.archive).",
  missingState = "Charaktere, die in der Hauptdatei fehlen: %d.",
})

Guard.MIRROR_VERSION = 1
Guard.MAX_CONSTANTS = 262143 -- Lua 5.1: constants per chunk (MAXARG_Bx)
Guard.HINT_PCT = 60          -- chat hint once per session
Guard.ALERT_PCT = 80         -- warning window
Guard.SLICE = 2000           -- values per time slice of the constants count
Guard.COUNT_DELAY = 15       -- seconds after entering the world before counting starts
Guard.AUTO_COUNT = true      -- count on its own after login (the test VM turns it off unless asked)
Guard.COMBAT_RETRY = 2       -- seconds: paused slice in combat
Guard.RECOVERY_MAX = 50      -- entries in diag.recovery
Guard.MISSING_WARNINGS = 3   -- logins that report missing characters
Guard.FRESH_LEVEL = 5        -- load-failure hint from this level on
Guard.FRESH_PLAYED = 3600    -- ... or from this /played total on

-- restore notice in the log (F3). Defined here so the Types block in Store.lua stays untouched by this step.
ns.Types.GR = { order = 2900, name = "Daten wiederhergestellt", desc = "Beim Einloggen wurden die Daten dieses Charakters aus seiner Sicherungskopie (InkAndEmbersCharDB, eigene Datei pro Charakter) zurückgeholt, oder ein abweichender Stand wurde in EveNChronicleDB.archive aufbewahrt. Steht nach der L-Zeile der Sitzung.", fields = {
  { "reason", "Grund: main_missing (Hauptdatei ohne diesen Charakter), main_empty (ohne Einträge), main_older (älterer Stand, z. B. aus der .bak), mirror_diverged (Hauptdatei behalten, abweichende Kopie aufbewahrt)" },
  { "lines", "Einträge des Charakters nach der Entscheidung (vor dieser Zeile)" },
  { "mainLines", "Einträge, die die Hauptdatei für diesen Charakter hatte (leer, wenn er fehlte)" },
  { "mirrorLines", "Einträge der Sicherungskopie" },
  { "archived", "1 = der unterlegene Stand liegt in EveNChronicleDB.archive" },
} }

-- Pure helpers (tested directly)

local function isNum(v) return type(v) == "number" and v == v and v > -1e15 and v < 1e15 end

-- header epoch and session of a block string '#~<epoch>~<n>\n...', or nil
local function header(b)
  if type(b) ~= "string" then return nil end
  local e, n = match(b, "^#~(%-?%d+)~(%-?%d+)")
  if not e then return nil end
  return tonumber(e), tonumber(n)
end
Guard.header = header

-- number of log lines of a character: lineCount, else counted from the blocks
function Guard.lineCount(c)
  if type(c) ~= "table" then return 0 end
  if isNum(c.lineCount) and c.lineCount >= 0 then return floor(c.lineCount) end
  local n = 0
  if type(c.log) == "table" then
    for _, b in ipairs(c.log) do
      if type(b) == "string" then
        local _, k = string.gsub(b, "\n", "\n")
        n = n + k
      end
    end
  end
  return n
end

-- newest block header epoch of the log (0 = no blocks)
function Guard.lastHead(c)
  local best = 0
  if type(c) ~= "table" or type(c.log) ~= "table" then return 0 end
  for _, b in ipairs(c.log) do
    local e = header(b)
    if e and e > best then best = e end
  end
  return best
end

local function blockSet(list)
  local set = {}
  if type(list) == "table" then
    for _, b in ipairs(list) do
      if type(b) == "string" then set[b] = true end
    end
  end
  return set
end

-- true if the loser holds a log or trail block the winner lacks (byte-identical blocks count as the same)
function Guard.hasUnique(loser, winner)
  if type(loser) ~= "table" then return false end
  local w = type(winner) == "table" and winner or {}
  for _, key in ipairs({ "log", "trail" }) do
    local list = loser[key]
    if type(list) == "table" and #list > 0 then
      local have = blockSet(w[key])
      for _, b in ipairs(list) do
        if type(b) == "string" and not have[b] then return true end
      end
    end
  end
  return false
end

-- true if a character table holds anything besides its info (lines, blocks or any non-empty table)
function Guard.hasContent(c)
  if type(c) ~= "table" then return c ~= nil end
  if Guard.lineCount(c) > 0 then return true end
  for k, v in pairs(c) do
    if k ~= "info" and k ~= "lineCount" and (type(v) ~= "table" or next(v) ~= nil) then return true end
  end
  return false
end

-- rewrites the session index in the first line of each block: map[old] = new, unknown -> 0. Returns the number of changed blocks.
function Guard.remapHeaders(log, map)
  if type(log) ~= "table" then return 0 end
  map = type(map) == "table" and map or {}
  local changed = 0
  for i, b in ipairs(log) do
    local e, n = header(b)
    if e then
      local to = map[n] or 0
      if to ~= n then
        local nl = find(b, "\n", 1, true)
        log[i] = "#~" .. format("%.0f", e) .. "~" .. format("%.0f", to) .. (nl and sub(b, nl) or "")
        changed = changed + 1
      end
    end
  end
  return changed
end

-- a mirror of this character in the format this version writes
function Guard.validMirror(m, guid)
  return type(m) == "table" and m.v == Guard.MIRROR_VERSION and type(guid) == "string" and m.guid == guid
    and type(m.char) == "table" and type(m.char.log) == "table"
end

-- the restore decision for main state C and mirror state M (both may be nil).
-- returns action ("keep" | "restore"), reason, archiveLoser (true when the loser must be kept in db.archive)
function Guard.decide(C, M)
  if type(M) ~= "table" then
    return "keep", nil, false
  end
  if type(C) ~= "table" then
    if not Guard.hasContent(M) then return "keep", nil, false end
    return "restore", "main_missing", C ~= nil
  end
  local cl, ml = Guard.lineCount(C), Guard.lineCount(M)
  local cBlocks = type(C.log) == "table" and #C.log or 0
  if cl == 0 and cBlocks == 0 then
    if ml == 0 and not Guard.hasContent(M) then return "keep", nil, false end
    return "restore", "main_empty", Guard.hasContent(C)
  end
  local ch, mh = Guard.lastHead(C), Guard.lastHead(M)
  if ml > cl and mh >= ch then
    return "restore", "main_older", ch > mh or Guard.hasUnique(C, M)
  end
  if mh > ch or Guard.hasUnique(M, C) then
    return "keep", "mirror_diverged", true
  end
  return "keep", nil, false
end

-- Notes and archive (EveNChronicleDB)

-- moves a non-table value aside under a free name (key_bad, key_bad2, ...), never overwrites
function Guard.keepAside(t, key, value)
  local name, i = key .. "_bad", 1
  while t[name] ~= nil do
    i = i + 1
    name = key .. "_bad" .. i
  end
  t[name] = value
  return name
end

function Guard.note(db, entry)
  if type(db) ~= "table" or type(entry) ~= "table" then return end
  if type(db.diag) ~= "table" then return end
  local list = db.diag.recovery
  if type(list) ~= "table" then
    list = {}
    db.diag.recovery = list
  end
  entry.at = entry.at or floor(time())
  list[#list + 1] = entry
  while #list > Guard.RECOVERY_MAX do table.remove(list, 1) end
end

-- keeps value under db.archive[guid] (never twice the same state). Returns true when stored.
function Guard.archive(db, guid, value, reason)
  if value == nil or type(guid) ~= "string" then return false end
  local arch = db.archive
  if arch ~= nil and type(arch) ~= "table" then
    Guard.keepAside(db, "archive", arch)
    arch = nil
  end
  if arch == nil then
    arch = {}
    db.archive = arch
  end
  local list = arch[guid]
  if list ~= nil and type(list) ~= "table" then
    Guard.keepAside(arch, guid, list)
    list = nil
  end
  if list == nil then
    list = {}
    arch[guid] = list
  end
  local lines, head = Guard.lineCount(value), Guard.lastHead(value)
  for _, e in ipairs(list) do
    if type(e) == "table" and (e.char == value or (type(value) == "table" and e.lineCount == lines and e.lastBlockAt == head
      and not Guard.hasUnique(value, e.char))) then
      return true
    end
  end
  list[#list + 1] = { at = floor(time()), reason = reason, lineCount = lines, lastBlockAt = head, char = value }
  return true
end

-- copies the scalar fields of a session (numbers, strings, booleans)
local function copySession(s)
  local out = {}
  for k, v in pairs(s) do
    local t = type(v)
    if type(k) == "string" and (t == "number" or t == "string" or t == "boolean") then out[k] = v end
  end
  return out
end

-- puts the mirror's sessions into meta.sessions: a session already there (same guid and start) is reused (and updated
-- if the mirror's copy was saved later), every other one is appended. Returns the map old index -> new index.
function Guard.mergeSessions(db, guid, list)
  local sessions = db.meta.sessions
  local map = {}
  if type(list) ~= "table" then return map end
  local byStart = {}
  for i, s in ipairs(sessions) do
    if type(s) == "table" and s.guid == guid and isNum(s.start) and byStart[s.start] == nil then byStart[s.start] = i end
  end
  for _, s in ipairs(list) do
    if type(s) == "table" and isNum(s.idx) and (s.guid == nil or s.guid == guid) then
      local old = floor(s.idx)
      local copy = copySession(s)
      copy.idx, copy.guid = nil, guid
      local at = isNum(s.start) and byStart[s.start]
      if at then
        local cur = sessions[at]
        if (tonumber(s.lastSave) or 0) > (tonumber(cur.lastSave) or 0) then
          for k, v in pairs(copy) do cur[k] = v end
          if s.stop == nil then cur.stop = nil end
        end
        map[old] = at
      else
        sessions[#sessions + 1] = copy
        map[old] = #sessions
        if isNum(copy.start) then byStart[copy.start] = #sessions end
      end
    end
  end
  return map
end

-- Login (called from Store.login)

Guard.state = {}

local function playerLevel()
  if type(UnitLevel) ~= "function" then return nil end
  local ok, v = pcall(UnitLevel, "player")
  if ok and not (type(issecretvalue) == "function" and issecretvalue(v)) and isNum(v) then return v end
  return nil
end

local function prepare(db, guid)
  local st = { guid = guid, warnings = {} }
  Guard.state = st
  local m = InkAndEmbersCharDB
  local C = db.chars[guid]
  st.mainLines = type(C) == "table" and Guard.lineCount(C) or nil

  -- what was loaded
  if m == nil then
    st.mirror = "none"
  elseif type(m) ~= "table" then
    st.mirror = "bad"
    Guard.note(db, { guid = guid, reason = "mirror_bad" })
  elseif isNum(m.v) and m.v > Guard.MIRROR_VERSION then
    -- written by a newer version: not understood, left untouched (WoW writes it back unchanged)
    st.mirror, st.readOnly = "future", true
    Guard.note(db, { guid = guid, reason = "mirror_future", v = m.v })
  elseif Guard.validMirror(m, guid) then
    st.mirror = "ok"
    st.loaded = { savedAt = isNum(m.savedAt) and m.savedAt or nil, lines = Guard.lineCount(m.char),
      addonVersion = type(m.addonVersion) == "string" and m.addonVersion or nil }
  else
    st.mirror = "bad"
    Guard.note(db, { guid = guid, reason = "mirror_bad" })
    -- the copy of another character (e.g. same name, new character): keep it if the main file does not hold that state
    if type(m.char) == "table" and type(m.guid) == "string" and m.guid ~= guid then
      local other = db.chars[m.guid]
      if Guard.lineCount(m.char) > Guard.lineCount(other) or Guard.hasUnique(m.char, other) then
        Guard.archive(db, m.guid, m.char, "mirror_other_char")
        Guard.note(db, { guid = m.guid, reason = "mirror_other_char", lines = Guard.lineCount(m.char) })
      end
    end
  end

  -- characters the mirror knew in the main file that are missing now
  if st.mirror == "ok" then
    local missing = {}
    local known = type(m.accountChars) == "table" and m.accountChars or {}
    for g, n in pairs(known) do
      if type(g) == "string" and g ~= guid and db.chars[g] == nil then
        missing[g] = { lines = isNum(n) and n or 0, warned = 0 }
      end
    end
    if type(m.missingChars) == "table" then
      for g, e in pairs(m.missingChars) do
        if type(g) == "string" and g ~= guid and db.chars[g] == nil and type(e) == "table" then
          missing[g] = { lines = isNum(e.lines) and e.lines or 0, since = isNum(e.since) and e.since or nil,
            warned = isNum(e.warned) and e.warned or 0 }
        end
      end
    end
    local count, warn = 0, false
    for _, e in pairs(missing) do
      count = count + 1
      e.since = e.since or floor(time())
      if e.warned < Guard.MISSING_WARNINGS then
        warn = true
        e.warned = e.warned + 1
      end
    end
    st.missing, st.missingCount = missing, count
    if warn then
      st.warnings[#st.warnings + 1] = { kind = "missingChars", text = T("missingChars", count) }
      Guard.note(db, { guid = guid, reason = "chars_missing", count = count })
    end
  end

  -- the decision
  local M = st.mirror == "ok" and m.char or nil
  local action, reason, keepLoser = Guard.decide(C, M)
  if action == "restore" then
    local mirrorLines = Guard.lineCount(M)
    local archived = false
    if keepLoser then archived = Guard.archive(db, guid, C, reason) end
    st.undo = { sessions = #db.meta.sessions, C = C }
    local map = Guard.mergeSessions(db, guid, m.sessions)
    -- the mirror's own tables stay untouched: the restored character is a shallow copy with a rewritten copy of the log
    -- (subtables are shared, nothing is doubled; after attach the mirror points at the copy)
    local R = {}
    for k, v in pairs(M) do R[k] = v end
    local log = {}
    for i, b in ipairs(M.log) do log[i] = b end
    Guard.remapHeaders(log, map)
    R.log = log
    db.chars[guid] = R
    st.undo.swapped = true
    st.restored = { reason = reason, lines = mirrorLines, mainLines = st.mainLines, mirrorLines = mirrorLines, archived = archived }
    Guard.note(db, { guid = guid, from = "mirror", reason = reason, lines = mirrorLines, mainLines = st.mainLines, archived = archived or nil })
    local why = (reason == "main_missing" and T.reasonMissing) or (reason == "main_empty" and T.reasonEmpty) or T.reasonOlder
    st.warnings[#st.warnings + 1] = { kind = "restored", text = T("restored", mirrorLines, why) }
    if archived then st.warnings[#st.warnings + 1] = { kind = "archived", text = T.archived, chatOnly = true } end
  elseif keepLoser and M then
    Guard.archive(db, guid, M, reason)
    st.restored = { reason = reason, lines = st.mainLines, mainLines = st.mainLines, mirrorLines = Guard.lineCount(M), archived = true }
    Guard.note(db, { guid = guid, from = "main", reason = reason, lines = st.mainLines, mirrorLines = Guard.lineCount(M), archived = true })
    st.warnings[#st.warnings + 1] = { kind = "archived", text = T.archived, chatOnly = true }
  elseif C ~= nil and type(C) ~= "table" then
    -- damaged entry and nothing to restore it from: keep the value, the character starts anew
    Guard.archive(db, guid, C, "main_bad_entry")
    db.chars[guid] = nil
    Guard.note(db, { guid = guid, reason = "main_bad_entry" })
  end

  -- load-failure hint (S2): no main file, no usable mirror, character not new
  if not st.restored and ns.Store.mainMissing and st.mirror ~= "future" and C == nil then
    local level = playerLevel()
    if level and level >= Guard.FRESH_LEVEL then
      Guard.freshSuspect(db, "level")
    else
      st.playedCheck = true
      ns.Core.on("TIME_PLAYED_MSG", Guard.onPlayed)
    end
  end
end

-- before the character table is created: decide main file against mirror. Never throws; on failure the mirror stays untouched.
function Guard.prepare(db, guid)
  Guard.failed = nil
  local ok, err = pcall(prepare, db, guid)
  if not ok then
    Guard.failed = true
    Guard.state = Guard.state or {}
    -- a failed restore is rolled back: the character runs on the main file's state and the loaded mirror (whose subtables the
    -- copy would share) stays exactly as loaded; the next login decides again (nothing is lost, see Guard.decide)
    local undo = Guard.state.undo
    if type(undo) == "table" then
      pcall(function()
        local list = db.meta.sessions
        for i = #list, undo.sessions + 1, -1 do list[i] = nil end
        if undo.swapped or db.chars[guid] ~= undo.C then db.chars[guid] = undo.C end
      end)
    end
    Guard.state.error = tostring(err)
    pcall(Guard.note, db, { guid = guid, reason = "guard_error", error = ns.Sanitize.field(tostring(err)) })
  end
  return ok
end

function Guard.freshSuspect(db, via)
  local st = Guard.state
  if st.freshWarned then return end
  st.freshWarned = true
  Guard.note(db, { guid = st.guid, reason = "fresh_suspect", via = via })
  local w = { kind = "freshSuspect", text = T.freshSuspect }
  if Guard.entered then Guard.queue(w) else st.warnings[#st.warnings + 1] = w end
end

function Guard.onPlayed(_, total)
  local st = Guard.state
  if not st.playedCheck or st.freshWarned then return end
  if type(issecretvalue) == "function" and issecretvalue(total) then return end
  if isNum(total) and total > Guard.FRESH_PLAYED then
    st.playedCheck = nil
    Guard.freshSuspect(ns.Store.db, "played")
  end
end

-- builds the mirror for the logged-in character (shares the character table). meta = account chars and own sessions.
local function build(db, guid, char)
  local st = Guard.state
  local own = {}
  for i, s in ipairs(db.meta.sessions) do
    if type(s) == "table" and s.guid == guid then
      local c = copySession(s)
      c.idx = i
      own[#own + 1] = c
    end
  end
  local acc = {}
  for g, c in pairs(db.chars) do
    if type(g) == "string" and type(c) == "table" then acc[g] = Guard.lineCount(c) end
  end
  local missing = nil
  if type(st.missing) == "table" then
    for g, e in pairs(st.missing) do
      if db.chars[g] == nil then
        missing = missing or {}
        missing[g] = e
      end
    end
  end
  return {
    v = Guard.MIRROR_VERSION,
    guid = guid,
    savedAt = floor(time()),
    addonVersion = ns.version,
    lineCount = Guard.lineCount(char),
    lastBlockAt = Guard.lastHead(char),
    sessions = own,
    accountChars = acc,
    missingChars = missing,
    char = char,
  }
end

local function writable()
  local st = Guard.state
  return not Guard.failed and type(st) == "table" and not st.readOnly and type(st.guid) == "string"
end

-- after Store.login created the character: the mirror points at the same table from now on
function Guard.attach(db, guid, char)
  if not writable() or Guard.state.guid ~= guid or type(char) ~= "table" then return false end
  local ok = pcall(function() InkAndEmbersCharDB = build(db, guid, char) end)
  if not ok then Guard.failed = true end
  return ok
end

-- Store.logout (after the last flush): refresh the markers. Never throws.
function Guard.write(db)
  if not writable() or type(db) ~= "table" then return false end
  local guid = Guard.state.guid
  local char = type(db.chars) == "table" and db.chars[guid]
  if type(char) ~= "table" then char = ns.Store.current end
  if type(char) ~= "table" then return false end
  local ok = pcall(function() InkAndEmbersCharDB = build(db, guid, char) end)
  return ok
end

-- Warnings: chat line at once, window outside combat

Guard.pending = {}

local function pctText(p)
  local tenth = floor((p or 0) * 10 + 0.5)
  return T("pct", floor(tenth / 10), tenth % 10)
end

local function buildWindow()
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetSize(380, 150)
  f:SetPoint("TOP", UIParent, "TOP", 0, -140)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)
  end
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
  title:SetText(T.title)
  local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -30)
  text:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -30)
  text:SetJustifyH("LEFT")
  if text.SetWordWrap then text:SetWordWrap(true) end
  local button = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  button:SetSize(120, 22)
  button:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
  button:SetText(T.ok)
  button:SetScript("OnClick", function() Guard.dismiss() end)
  f:Hide()
  Guard.frame, Guard.text, Guard.button = f, text, button
end

function Guard.isShown()
  return Guard.frame ~= nil and Guard.frame:IsShown() and true or false
end

-- shows all queued warnings in one window (waits outside combat)
function Guard.flush()
  if #Guard.pending == 0 then return false end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return false end
  if not Guard.frame then buildWindow() end
  local parts = {}
  for _, w in ipairs(Guard.pending) do parts[#parts + 1] = w.text end
  Guard.text:SetText(concat(parts, "\n\n"))
  local h = tonumber(Guard.text.GetStringHeight and Guard.text:GetStringHeight())
  Guard.frame:SetHeight(math.max(110, (h or (#parts * 60)) + 76))
  Guard.frame:Show()
  return true
end

function Guard.dismiss()
  Guard.pending = {}
  if Guard.frame then Guard.frame:Hide() end
end

-- one warning: chat line now, window (unless chatOnly) as soon as possible; each kind once per session
function Guard.queue(w)
  Guard.shown = Guard.shown or {}
  if Guard.shown[w.kind] then return false end
  Guard.shown[w.kind] = true
  ns.Core.print(w.text)
  if not w.chatOnly then
    Guard.pending[#Guard.pending + 1] = w
    Guard.flush()
  end
  return true
end

-- first PLAYER_ENTERING_WORLD: GR line after the session's L line, warnings, start of the constants count
function Guard.onEnterWorld()
  if Guard.entered then return end
  Guard.entered = true
  local st = Guard.state or {}
  local r = st.restored
  if r and ns.Store.ready() then
    ns.Store.append("GR", r.reason, r.lines, r.mainLines, r.mirrorLines, r.archived and 1 or 0)
  end
  for _, w in ipairs(st.warnings or {}) do Guard.queue(w) end
  if Guard.AUTO_COUNT and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(Guard.COUNT_DELAY, function() ns.Core.safe(Guard.startCount) end)
  end
end

-- Constants guard (S4): distinct strings and numbers of EveNChronicleDB as WoW writes it, in time slices

-- new counter over root (array part 1..#t is written without keys)
function Guard.newCount(root)
  return { seen = {}, strs = {}, nums = {}, bools = {}, n = 0, stack = { { t = root } }, values = 0 }
end

local function add(c, v)
  local t = type(v)
  if t == "string" then
    if not c.strs[v] then c.strs[v] = true c.n = c.n + 1 end
  elseif t == "number" then
    if not c.nums[v] then c.nums[v] = true c.n = c.n + 1 end
  elseif t == "boolean" then
    if not c.bools[v] then c.bools[v] = true c.n = c.n + 1 end
  end
end

-- processes up to budget values; returns true when done
function Guard.countStep(c, budget)
  local stack = c.stack
  while budget > 0 do
    local fr = stack[#stack]
    if not fr then return true end
    if not fr.keys then
      -- key list of the table, built over several slices for large tables (next resumes at the last key; if that key was
      -- removed in between, the list ends there: the count is an estimate anyway)
      local keys, last = fr.partial or {}, fr.last
      while budget > 0 do
        local ok, k = pcall(next, fr.t, last)
        if not ok or k == nil then
          last = nil
          break
        end
        keys[#keys + 1] = k
        last = k
        budget = budget - 1
      end
      if last ~= nil then
        fr.partial, fr.last = keys, last
        return false
      end
      fr.keys, fr.i, fr.alen, fr.partial, fr.last = keys, 0, #fr.t, nil, nil
      if budget <= 0 then return false end
    end
    fr.i = fr.i + 1
    local k = fr.keys[fr.i]
    if k == nil then
      stack[#stack] = nil
    else
      budget = budget - 1
      c.values = c.values + 1
      if not (type(k) == "number" and k >= 1 and k <= fr.alen and k == floor(k)) then add(c, k) end
      local v = fr.t[k]
      if type(v) == "table" then
        if not c.seen[v] then
          c.seen[v] = true
          stack[#stack + 1] = { t = v }
        end
      else
        add(c, v)
      end
    end
  end
  return #stack == 0
end

-- whole count at once (tests, diagnostics)
function Guard.countNow(root)
  local c = Guard.newCount(root)
  while not Guard.countStep(c, 1e9) do end
  return c.n
end

-- stores the result and warns from HINT_PCT / ALERT_PCT
function Guard.evaluate(n)
  local db = ns.Store.db
  local pct = floor(n * 1000 / Guard.MAX_CONSTANTS) / 10
  if type(db) == "table" and type(db.diag) == "table" then
    db.diag.constants = { n = n, at = floor(time()), pct = pct }
  end
  if pct >= Guard.ALERT_PCT then
    Guard.queue({ kind = "constants", text = T("constantsAlert", pctText(pct)) })
  elseif pct >= Guard.HINT_PCT then
    Guard.queue({ kind = "constantsHint", text = T("constantsHint", pctText(pct)), chatOnly = true })
  end
  return pct
end

function Guard.startCount()
  if Guard.counting or Guard.counted or type(ns.Store.db) ~= "table" then return false end
  local c = Guard.newCount(ns.Store.db)
  Guard.counting = c
  local function slice()
    if Guard.counting ~= c then return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
      C_Timer.After(Guard.COMBAT_RETRY, function() ns.Core.safe(slice) end)
      return
    end
    if Guard.countStep(c, Guard.SLICE) then
      local n = c.n
      Guard.counting, Guard.counted = nil, true -- done; the sets are released
      Guard.evaluate(n)
    else
      C_Timer.After(0, function() ns.Core.safe(slice) end)
    end
  end
  slice()
  return true
end

-- /chronik sicherung (alias backup): display only

local function when(epoch)
  if not isNum(epoch) then return "?" end
  return date(T.dateFmt, epoch)
end

function Guard.report()
  local out = { T.backupTitle }
  local st = Guard.state or {}
  local db = ns.Store.db
  if not writable() then
    out[#out + 1] = T.mirrorOff
  elseif st.loaded and st.loaded.savedAt then
    out[#out + 1] = T("mirrorState", when(st.loaded.savedAt), st.loaded.lines or 0)
  else
    out[#out + 1] = T.mirrorNone
  end
  local last = (ns.Save and ns.Save.lastSave) or ns.Store.loginAt
  if isNum(last) then out[#out + 1] = T("lastSave", when(last)) end
  local cst = type(db) == "table" and type(db.diag) == "table" and db.diag.constants or nil
  if type(cst) == "table" and isNum(cst.n) then
    out[#out + 1] = T("constantsState", pctText(cst.pct), cst.n, Guard.MAX_CONSTANTS, when(cst.at))
  else
    out[#out + 1] = T.constantsPending
  end
  local rec = type(db) == "table" and type(db.diag) == "table" and db.diag.recovery or nil
  local lastRec = nil
  if type(rec) == "table" then
    for i = #rec, 1, -1 do
      local e = rec[i]
      if type(e) == "table" and (e.from == "mirror" or e.reason == "mirror_diverged") then
        lastRec = e
        break
      end
    end
  end
  if lastRec then
    out[#out + 1] = T("recoveryLast", when(lastRec.at), ns.Sanitize.field(tostring(lastRec.reason)))
  else
    out[#out + 1] = T.recoveryNone
  end
  local arch = type(db) == "table" and type(db.archive) == "table" and db.archive or nil
  if arch then
    local n = 0
    for _, list in pairs(arch) do
      if type(list) == "table" then n = n + #list end
    end
    if n > 0 then out[#out + 1] = T("archiveCount", n) end
  end
  if isNum(st.missingCount) and st.missingCount > 0 then out[#out + 1] = T("missingState", st.missingCount) end
  return out
end

function Guard.slash()
  for _, line in ipairs(Guard.report()) do ns.Core.print(line) end
end

ns.Core.on("PLAYER_ENTERING_WORLD", function() Guard.onEnterWorld() end)
ns.Core.on("PLAYER_REGEN_ENABLED", function() Guard.flush() end)
