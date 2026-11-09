-- Milestone note (WoW Forever only): at level 10, 20, ... 60 the narrator note (journal/Begleiter.lua, showNote, kind "milestone")
-- sums up the stretch of ten levels in a few sentences: time without away time, new zones, kills, deaths, best find, a look ahead;
-- at the highest level two closing sentences about the whole journey. Numbers from journal/model/Meilensteine.lua (nothing stored).
-- Order at a milestone: first the level-up note (collectors/Trainer.lua), then this one, then the "Zum Lehrer" toast
-- (Begleiter.afterSlip queue: notes go ahead of waiting toasts). Trigger: a chain around Store.observer for the LV line
-- (Toast.install keeps its predecessor the same way); in combat it waits for PLAYER_REGEN_ENABLED; while the index is still
-- building it tries again a few times. Click: opens the book at Chronik -> Meilensteine on that section (in combat: chat hint,
-- the note stays); the small x only closes. Setting milestoneSlip (default on) switches only the note off; the book view stays.
-- Preview: /chronik meilenstein [n] (also with the option off). The same sentence kit writes the narrator line of the book page
-- (one fixed variant per section there, so the page never flickers).
-- Foreign text (player, zone, item names) only via Sanitize.display, numbers via format("%d") / Texts.int, the item colour from
-- our own quality table (Fmt.qualityHex), never from foreign text.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Meilenstein = {}
Journal.Meilenstein = Meilenstein

local floor, format = math.floor, string.format

Meilenstein.DELAY = 6          -- s after the LV line (after Trainer.LEVEL_DELAY 2 s: the level-up note comes first)
Meilenstein.RETRY = 10         -- s between tries while the index is still building
Meilenstein.TRIES = 3
Meilenstein.REGEN_DELAY = 1    -- s after combat: the level-up note (PLAYER_REGEN_ENABLED in the collector) goes first
Meilenstein.HOLD = 20          -- s the note stays (the other notes: Begleiter.SLIP.hold)
Meilenstein.NAME_MAX = 64      -- bytes per player / zone / item name in a sentence

Meilenstein.TEXT = ns.Locale.ns("Meilenstein", {
  title = "Meilenstein: Stufe %d",
  titleFinal = "Stufe %d – am Ziel",
  titlePreview = "%s (Vorschau)",
  hint = "Klick: Meilensteine im Buch öffnen",
  combat = "Im Kampf öffnet sich das Buch nicht. Versucht es danach noch einmal.",
  openFail = "Die Meilensteine lassen sich gerade nicht öffnen. Versucht es gleich noch einmal.",
  usage = "/chronik meilenstein [Stufe] zeigt die Bilanz eines Meilensteins als Vorschau (Stufe 10, 20, … bis %d).",
  retailOnly = "Die Meilensteine gibt es nur in WoW Forever.",
  notReady = "Die Chronik sortiert noch. Gleich noch einmal versuchen.",
  nameFallback = "Reisender",
  about = "etwa %s",
  roughly = "rund %s",
  atLeast = "mindestens %s",
  numWords = "zwei drei vier fünf sechs sieben acht neun zehn elf zwölf",
  andWord = " und ",
  -- Erzähler-Texte: mehrere Varianten je Baustein, zufällig gewählt (nie zweimal hintereinander dieselbe). Platzhalter in {Klammern}.
  open = {
    "Ein Abschnitt ist zu Ende, {name}: Stufe {n}!",
    "Stufe {n}, {name}. Zeit, einmal zurückzublicken.",
    "Zehn Stufen mehr, {name}! Das Buch hält fest, was dazwischen lag.",
    "Stufe {n}, {name}! Ein guter Moment, kurz innezuhalten.",
    "Seht an, {name}: Stufe {n}. Blättern wir zurück.",
    "Ein Kapitel schließt sich, {name}: Stufe {n}!",
  },
  openRunning = "Stufe {n} liegt noch vor Euch, {name}. Bisher steht im Buch:",
  partial = "Gezählt ist seit Beginn der Aufzeichnung (ab Stufe {from}).",
  time = {
    "{time} wart Ihr dafür unterwegs.",
    "Das hat Euch {time} gekostet.",
    "{time} habt Ihr für diesen Abschnitt gebraucht.",
    "Unterwegs wart Ihr dafür {time}.",
    "{time} Reisezeit stecken in diesen Stufen.",
  },
  -- Zonen: Satzanfang ohne Satzzeichen, der Code hängt die Namen („: A, B und C.“) oder den Punkt an
  zones_one = {
    "Eine neue Zone habt Ihr entdeckt",
    "Eine neue Gegend lag auf Eurem Weg",
    "Ihr habt eine neue Zone betreten",
    "Eine Zone kam neu auf Eure Karte",
    "Eine neue Zone durftet Ihr erkunden",
  },
  zones_other = {
    "{count} neue Zonen habt Ihr entdeckt",
    "{count} neue Gegenden lagen auf Eurem Weg",
    "Ihr habt {count} neue Zonen betreten",
    "{count} Zonen kamen neu auf Eure Karte",
    "{count} neue Zonen durftet Ihr erkunden",
  },
  kills = {
    "{kills} Gegner haben sich Euch in den Weg gestellt.",
    "{kills} Gegner mussten Euch weichen.",
    "{kills} Gegner habt Ihr besiegt.",
    "{kills} Gegner fielen durch Eure Hand.",
    "{kills} Gegner liegen hinter Euch im Staub.",
  },
  deaths0 = {
    "Kein einziges Mal musste der Geistheiler Euch holen.",
    "Gestorben seid Ihr dabei kein einziges Mal.",
    "Der Geistheiler hat Euch in dieser Zeit nicht ein Mal gesehen.",
    "Und das alles ohne einen einzigen Tod.",
  },
  deaths1 = {
    "Nur ein Mal rief der Geistheiler nach Euch.",
    "Ein einziges Mal musstet Ihr den Geistheiler besuchen.",
    "Einmal holte Euch der Geistheiler zurück.",
    "Nur ein Tod steht im Buch.",
  },
  deathsN = {
    "{times} holte Euch der Geistheiler zurück – wer zählt schon mit.",
    "{times} musstet Ihr den Geistheiler besuchen.",
    "Der Geistheiler sah Euch {times}.",
    "{count} Tode stehen im Buch, und doch seid Ihr hier.",
  },
  timesSuffix = "mal",
  timesDigits = "%s-mal",
  find = {
    "Euer bester Fund: {item}.",
    "Am meisten Freude machte {item}.",
    "Der schönste Fund unterwegs: {item}.",
    "Mit {item} hattet Ihr Glück.",
    "Glanzstück dieses Abschnitts: {item}.",
  },
  findNoName = {
    "Auch ein schöner Fund war dabei.",
    "Ein guter Fund war auch dabei.",
    "Leer ausgegangen seid Ihr nicht.",
  },
  next = {
    "Auf zu Stufe {next}!",
    "Stufe {next} wartet schon.",
    "Das nächste Kapitel endet bei Stufe {next}.",
    "Weiter geht's – Stufe {next} ruft.",
    "Mal sehen, was bis Stufe {next} geschieht.",
  },
  finalOpen = {
    "Stufe {n}, {name}. Der Weg ist zu Ende – und doch erst der Anfang.",
    "Ihr habt es geschafft, {name}: Stufe {n}!",
    "Stufe {n}! Was für eine Reise, {name}.",
    "Am Ziel, {name}: Stufe {n}. Die Chronik verneigt sich.",
    "Stufe {n}, {name}. Ein ganzes Buch voller Abenteuer liegt hinter Euch.",
    "Geschafft, {name}! Stufe {n} – die letzte Seite dieses Weges.",
  },
  finalOpenRunning = "Stufe {n} liegt noch vor Euch, {name}. So steht die ganze Reise bisher im Buch:",
  finalTime = {
    "Die ganze Reise dauerte {time}.",
    "Alles in allem wart Ihr {time} unterwegs.",
    "{time} stecken in dieser Reise.",
  },
  finalTally = {
    "{zones} und {deaths}: So steht es im Buch.",
    "Unterwegs: {zones} und {deaths}.",
    "Das Buch zählt {zones} und {deaths}.",
  },
  finalZones_one = "eine neue Zone",
  finalZones_other = "{count} neue Zonen",
  finalDeaths0 = "kein einziger Tod",
  finalDeaths1 = "ein einziger Tod",
  finalDeathsN = "{count} Tode",
  finalClose = {
    "Alles steht in Eurem Buch.",
    "Die Chronik bewahrt jeden Schritt.",
    "Was für eine Geschichte – und sie gehört Euch.",
    "Ruht Euch aus. Ihr habt es Euch verdient.",
    "Die letzte Seite? Nein – nur das Ende des ersten Bandes.",
    "Das Buch ist voll. Gut gemacht.",
  },
})
local T = Meilenstein.TEXT

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function setting(key)
  local P = Journal.Pages
  if not P or type(P.setting) ~= "function" then return true end
  return P.setting(key) ~= false
end

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return ok and not isSecret(v) and v == true
end

local function print_(msg)
  if ns.Core and type(ns.Core.print) == "function" then ns.Core.print(msg) end
end

-- foreign text for a sentence: Sanitize.display (codes, bidi, "|" -> "||"); nil when empty
local function shown(v, n)
  if isSecret(v) or type(v) ~= "string" then return nil end
  local s = ns.Sanitize.display(v, n or Meilenstein.NAME_MAX)
  if s == "" then return nil end
  return s
end

-- WoW Forever only (the trainer plan module knows the client; same switch as the level-up note)
function Meilenstein.active()
  local L = Journal.Lehrplan
  return L ~= nil and type(L.active) == "function" and L.active() == true
end

function Meilenstein.on() return setting("milestoneSlip") end

-- Sentence helpers (copied from collectors/Trainer.lua so the level-up note stays untouched) ------------------------------

-- Random variant of a text list. Meilenstein.random(n) -> 1..n (tests replace it); Meilenstein.picks[kind] = last index per kind:
-- the same variant never comes twice in a row.
Meilenstein.random = function(n) return math.random(n) end
Meilenstein.picks = {}

local function listOf(v)
  if type(v) == "table" and #v > 0 then return v end
  return { tostring(v) }
end

local function randomPick(kind, list)
  list = listOf(list)
  local n = #list
  local r = Meilenstein.random(n)
  local i = num(r) and floor(r) or 1
  if i < 1 or i > n then i = ((i - 1) % n) + 1 end
  if n > 1 and Meilenstein.picks[kind] == i then i = i % n + 1 end
  Meilenstein.picks[kind] = i
  return list[i]
end

-- fixed variant per seed, section and part (book page: the same sentence on every redraw)
local function seededPicker(seed, n)
  local Tx = Journal.Texts
  return function(kind, list)
    list = listOf(list)
    local h = Tx and Tx.hash(tostring(seed) .. ":" .. tostring(n) .. ":" .. kind) or 0
    return list[(h % #list) + 1]
  end
end

local function fill(text, args)
  return ns.Locale.fmt(text, args)
end

local function cap(s)
  return (s:gsub("^%l", string.upper))
end

local function compose(...)
  local out = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if type(v) == "string" and v ~= "" then out[#out + 1] = v end
  end
  -- a sentence that ends on an abbreviation ("12 Min.") gets no second full stop
  return (table.concat(out, " "):gsub("%.%.(%s)", ".%1"):gsub("%.%.$", "."))
end

-- number word for 2..12 ("zwei"), otherwise the digits
local function numWord(n)
  n = floor(n)
  if n >= 2 and n <= 12 then
    local i = 1
    for w in string.gmatch(T.numWords, "%S+") do
      i = i + 1
      if i == n then return w end
    end
  end
  return format("%d", n)
end
Meilenstein.numWord = numWord

-- first sentence of an opening up to the first "!" or "." (the leaner form)
local function shortOpen(s)
  return s:match("^(.-[!.])%s") or s
end

local function int(n)
  local Tx = Journal.Texts
  return Tx and Tx.int(n) or format("%d", floor(n))
end

local function durationText(seconds, approx)
  seconds = num(seconds)
  if not seconds then return nil end
  local minutes = floor(seconds / 60 + 0.5)
  if minutes < 1 then return nil end
  local d = Journal.Fmt and Journal.Fmt.duration(minutes * 60)
  if not d then return nil end
  return approx and T("about", d) or d
end
Meilenstein.durationText = durationText

local function amount(n, sec, rough)
  local s = int(n)
  if sec.truncated then return T("atLeast", s) end
  if rough then return T("roughly", s) end
  return s
end

-- "A, B und C"
local function nameList(names)
  local k = #names
  if k == 1 then return names[1] end
  return table.concat(names, ", ", 1, k - 1) .. T.andWord .. names[k]
end

-- item name in its quality colour (own table; the name itself sanitized); nil without a name
function Meilenstein.itemText(best)
  if type(best) ~= "table" then return nil end
  local name = shown(best.name)
  if not name then return nil end
  local F = Journal.Fmt
  local hex = F and type(F.qualityHex) == "function" and F.qualityHex(best.quality) or nil
  if hex and string.match(hex, "^%x%x%x%x%x%x$") then return "|cff" .. hex .. name .. "|r" end
  return name
end

-- Sentence parts of a section (or the final tally) -> { open, openShort, partial, time, zonesFull, zonesShort, kills, deaths, find,
-- findShort, next, finalTime, finalTally, close }; pick(kind, list) chooses the variant
function Meilenstein.parts(sec, res, pick, name)
  local p = {}
  if type(sec) ~= "table" then return p end
  local n = sec.n
  local running = sec.state ~= "done"
  name = name or T.nameFallback
  if sec.final then
    p.open = running and fill(T.finalOpenRunning, { n = format("%d", n), name = name })
      or fill(pick("finalOpen", T.finalOpen), { n = format("%d", n), name = name })
  else
    p.open = running and fill(T.openRunning, { n = format("%d", n), name = name })
      or fill(pick("open", T.open), { n = format("%d", n), name = name })
  end
  p.openShort = shortOpen(p.open)
  if sec.partial and sec.since then p.partial = fill(T.partial, { from = format("%d", sec.since) }) end
  -- the final note: the last section's numbers plus two closing sentences about the whole journey
  -- (a final preview before the last section has begun has no section of its own: then only the find and the tally)
  local body, sectionPart = sec, true
  if sec.final then
    local last = type(res) == "table" and res.sections and res.sections[#res.sections]
    if last and not last.nodata and last.state ~= "open" then body = last else sectionPart = false end
  end
  local dur = sectionPart and durationText(body.seconds, body.secondsApprox) or nil
  if dur then p.time = cap(fill(pick("time", T.time), { time = dur })) end
  local z = sectionPart and num(body.zonesNew) or 0
  if z >= 1 then
    local one = z == 1
    local head = cap(fill(pick(one and "zones_one" or "zones_other", one and T.zones_one or T.zones_other),
      { count = body.truncated and T("atLeast", numWord(z)) or numWord(z) }))
    p.zonesShort = head .. "."
    local names = {}
    for _, nm in ipairs(type(body.zoneNames) == "table" and body.zoneNames or {}) do
      local s = shown(nm)
      if s then names[#names + 1] = s end
    end
    p.zonesFull = #names > 0 and (head .. ": " .. nameList(names) .. ".") or p.zonesShort
  end
  local k = sectionPart and num(body.kills) or 0
  if k >= 1 then p.kills = cap(fill(pick("kills", T.kills), { kills = amount(k, body, not body.killsExact) })) end
  local d = num(body.deaths) or 0
  if sectionPart and (not body.empty or d > 0) then
    if d == 0 then
      p.deaths = pick("deaths0", T.deaths0)
    elseif d == 1 then
      p.deaths = pick("deaths1", T.deaths1)
    else
      local times = (d <= 12) and (numWord(d) .. T.timesSuffix) or T("timesDigits", format("%d", d))
      p.deaths = cap(fill(pick("deathsN", T.deathsN), { times = times, count = d <= 12 and numWord(d) or format("%d", d) }))
    end
  end
  if body.best then
    local item = Meilenstein.itemText(body.best)
    p.findShort = pick("findNoName", T.findNoName)
    p.find = item and fill(pick("find", T.find), { item = item }) or p.findShort
  end
  local top = type(res) == "table" and res.maxLevel or n
  if not sec.final and not running and n < top then
    p.next = fill(pick("next", T.next), { next = format("%d", n + (type(res) == "table" and res.step or 10)) })
  end
  if sec.final then
    local fd = durationText(sec.seconds, sec.secondsApprox)
    if fd then p.finalTime = cap(fill(pick("finalTime", T.finalTime), { time = fd })) end
    local fz = num(sec.zonesNew) or 0
    local zones = fz == 1 and T.finalZones_one or fill(T.finalZones_other, { count = fz <= 12 and numWord(fz) or int(fz) })
    if fz == 0 then zones = fill(T.finalZones_other, { count = "0" }) end
    local fdth = num(sec.deaths) or 0
    local deaths = (fdth == 0 and T.finalDeaths0) or (fdth == 1 and T.finalDeaths1)
      or fill(T.finalDeathsN, { count = fdth <= 12 and numWord(fdth) or int(fdth) })
    p.finalTally = cap(fill(pick("finalTally", T.finalTally), { zones = zones, deaths = deaths }))
    if not running then p.close = pick("finalClose", T.finalClose) end
  end
  return p
end

-- Variants from the fullest to the leanest (Begleiter.showNote takes the first that fits the parchment): first the zone names
-- fall away, then the kills, then the zones, then the look ahead; opening, time, deaths and find stay, at the very end the find
-- loses its name. The final note keeps its two closing sentences in every variant.
function Meilenstein.variants(sec, res, pick, name)
  local p = Meilenstein.parts(sec, res, pick, name)
  local tail = sec and sec.final and { p.finalTime, p.finalTally } or { p.next }
  local function v(open, zones, kills, find, withTail)
    return compose(open, p.partial, p.time, zones, kills, p.deaths, find,
      withTail and tail[1] or nil, withTail and tail[2] or nil, withTail and sec and sec.final and p.close or nil)
  end
  local out, seen = {}, {}
  local function add(s)
    if s ~= "" and not seen[s] then
      seen[s] = true
      out[#out + 1] = s
    end
  end
  local final = sec and sec.final
  add(v(p.open, p.zonesFull, p.kills, p.find, true))
  add(v(p.open, p.zonesShort, p.kills, p.find, true))
  add(v(p.open, p.zonesShort, nil, p.find, true))
  add(v(p.open, nil, nil, p.find, true))
  add(v(p.open, nil, nil, p.find, final))
  add(v(p.openShort, nil, nil, p.find, final))
  add(v(p.openShort, nil, nil, p.findShort, final))
  if final then
    -- the final note: the section's numbers may go entirely, the closing tally stays
    add(compose(p.openShort, p.partial, p.finalTime, p.finalTally))
  end
  return out, p
end

-- narrator paragraph of the book page, fixed per section (seed from the character): a section takes the fullest variant; the
-- closing page only the journey (opening, total time, tally, best find, closing sentence; the numbers stand below it)
function Meilenstein.pageText(sec, res, seed, name)
  if type(sec) ~= "table" or sec.state == "open" or sec.nodata then return nil end
  local pick = seededPicker(seed or "0", sec.key or sec.n)
  if sec.final then
    local p = Meilenstein.parts(sec, nil, pick, name)
    return compose(p.open, p.partial, p.finalTime, p.finalTally, p.find, p.close)
  end
  local list = Meilenstein.variants(sec, res, pick, name)
  return list[1]
end

-- player name for the note (own character only; the note never shows for another character's book)
local function playerName()
  if type(UnitName) ~= "function" then return T.nameFallback end
  local ok, n = pcall(UnitName, "player")
  return ok and shown(n) or T.nameFallback
end

-- Content of the note for a section key (10, 20, ... or the highest level -> the final tally): nil without data.
-- opts.preview: the title says "(Vorschau)" (also for a section not yet reached: its numbers so far).
function Meilenstein.content(res, key, opts)
  opts = opts or {}
  local M = Journal.Meilensteine
  if not (M and type(res) == "table") then return nil end
  local isFinal = key == res.maxLevel or key == "final"
  local sec = isFinal and res.final or M.find(res, key)
  if not sec or sec.state == "open" or sec.nodata then return nil end
  local title = isFinal and T("titleFinal", res.maxLevel) or T("title", sec.n)
  if opts.preview then title = T("titlePreview", title) end
  local list = Meilenstein.variants(sec, res, randomPick, (opts.name ~= nil and shown(opts.name)) or playerName())
  local variants = {}
  for i, s in ipairs(list) do variants[i] = { s } end
  local open = isFinal and "final" or sec.n
  return { kind = "milestone", key = open, title = title, variants = variants, hint = T.hint, closable = true, hold = Meilenstein.HOLD,
    onClick = function() return Meilenstein.openBook(open) end }
end

-- Click on the note: back to the own book, Chronik -> Meilensteine on the section. In combat the book stays shut (chat hint) and
-- the note stays. false = keep the note.
function Meilenstein.openBook(key)
  if inCombat() then
    print_(T.combat)
    return false
  end
  local A, F, P = Journal.Access, Journal.Frame, Journal.Pages
  local ok = pcall(function()
    if P and type(P.guest) == "function" and P.guest() and type(P.setGuest) == "function" then P.setGuest(nil) end
    if A and type(A.isOpen) == "function" and not A.isOpen() and type(A.open) == "function" then A.open() end
  end)
  local page = Journal.ChronikPage
  local shown_ = ok and F and type(F.showPage) == "function" and F.showPage("chronik")
  if shown_ and page then
    page.milestoneSel = key
    if page:GetSub() ~= "meilensteine" and type(F.showSub) == "function" then F.showSub("meilensteine") end
    local v = page.milestonesView
    if v and v:IsOpen() then v:SelectKey(key) end
  end
  if not (shown_ and page and page:GetSub() == "meilensteine") then
    print_(T.openFail)
    return false
  end
  return true
end

-- Live: pending milestone (a level-up crossed a mark of ten) ---------------------------------------------------------------

Meilenstein.pending = nil

local function after(sec, fn)
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(sec, function()
      if ns.Core and ns.Core.safe then ns.Core.safe(fn) else pcall(fn) end
    end)
    return true
  end
  return false
end

-- Shows the pending note now or waits: in combat (until PLAYER_REGEN_ENABLED), behind another note (Begleiter.afterSlip; a note
-- goes ahead of the waiting toasts), while the index builds (a few tries). Returns true if shown or still waiting.
function Meilenstein.flush()
  local pend = Meilenstein.pending
  if not pend then return false end
  local B = Journal.Begleiter
  if not (Meilenstein.active() and Meilenstein.on() and B and type(B.showNote) == "function") then
    Meilenstein.pending = nil
    return false
  end
  if inCombat() then return true end -- PLAYER_REGEN_ENABLED calls this again
  if type(B.slipKind) == "function" and B.slipKind() and type(B.afterSlip) == "function"
    and B.afterSlip(function() Meilenstein.flush() end, { note = true, key = "milestone" }) then
    return true
  end
  local Idx, M = Journal.Index, Journal.Meilensteine
  if not (Idx and M) then
    Meilenstein.pending = nil
    return false
  end
  local index = Idx.get()
  local res = index and M.build(index) or nil
  local sec = res and (pend.n >= res.maxLevel and res.final or M.find(res, pend.n)) or nil
  local ready = index and not index.stale and sec and sec.state == "done"
  if not ready and pend.tries < Meilenstein.TRIES then
    pend.tries = pend.tries + 1
    if after(Meilenstein.RETRY, Meilenstein.flush) then return true end
  end
  Meilenstein.pending = nil
  -- after the last try a section that is still not complete in the index gets no note (no half-true tally)
  if not (sec and sec.state == "done") then return false end
  local content = Meilenstein.content(res, pend.n)
  return content ~= nil and B.showNote(content) == true
end

-- a level-up crossed a mark of ten: note n after DELAY seconds (several marks at once: the highest)
function Meilenstein.schedule(n)
  if not (Meilenstein.active() and Meilenstein.on()) then return false end
  Meilenstein.pending = { n = n, tries = 0 }
  if not after(Meilenstein.DELAY, Meilenstein.flush) then return Meilenstein.flush() end
  return true
end

-- level at the start of the session (PLAYER_ENTERING_WORLD, before any level-up): so the first level-up of a session also sees
-- a jump over a mark (e.g. 8 -> 11)
function Meilenstein.noteLevel()
  if Meilenstein.lastLevel ~= nil or type(UnitLevel) ~= "function" then return end
  local ok, v = pcall(UnitLevel, "player")
  if ok and not isSecret(v) and num(v) and v >= 1 and v <= 200 then Meilenstein.lastLevel = floor(v) end
end

-- LV line from the store: new level vs. the last one seen in this session (unknown: one below)
function Meilenstein.onLine(code, fields)
  if code ~= "LV" or type(fields) ~= "table" then return end
  local lv = tonumber(fields[1])
  if not lv or lv ~= lv or lv < 2 or lv > 200 or lv ~= floor(lv) then return end
  local old = Meilenstein.lastLevel
  if not old or old >= lv then old = lv - 1 end
  Meilenstein.lastLevel = lv
  local step = Journal.Meilensteine and Journal.Meilensteine.STEP or 10
  if floor(lv / step) > floor(old / step) then
    local n = floor(lv / step) * step
    local C = Journal.Chronik
    local top = C and C.maxLevel() or 60
    if n > top then n = top end
    Meilenstein.schedule(n)
  end
end

-- /chronik meilenstein [n]: preview (also with the option off). Without a number the last milestone reached (else the running
-- one); a number not reached yet shows the numbers so far. n must be a multiple of ten in 10 .. highest level.
function Meilenstein.slash(rest)
  local C = Journal.Chronik
  local top = C and C.maxLevel() or 60
  if not Meilenstein.active() then
    print_(T.retailOnly)
    return false
  end
  local n
  if type(rest) == "string" and rest ~= "" then
    n = tonumber(rest)
    if not n or n ~= floor(n) or n < 10 or n > top or n % 10 ~= 0 then
      print_(T("usage", top))
      return false
    end
  end
  local Idx, M, B = Journal.Index, Journal.Meilensteine, Journal.Begleiter
  local index = Idx and Idx.get({ noRebuild = true }) or nil
  local res = index and M and M.build(index) or nil
  if not res then
    print_(T.notReady)
    return false
  end
  if not n then
    n = res.latest
    if not n then
      for _, s in ipairs(res.sections) do
        if s.state == "running" then n = s.n end
      end
    end
    n = n or 10
  end
  local content = Meilenstein.content(res, n, { preview = true })
  if not (content and B and type(B.showNote) == "function") then
    print_(T.notReady)
    return false
  end
  return B.showNote(content)
end

-- store observer chain (as Toast.install: the predecessor keeps running) and the combat end
do
  local Store = ns.Store
  if Store and not Meilenstein.installed then
    Meilenstein.installed = true
    local prev = Store.observer
    Store.observer = function(code, fields)
      if type(prev) == "function" then pcall(prev, code, fields) end
      if code == "LV" then Meilenstein.onLine(code, fields) end
    end
  end
  if ns.Core and type(ns.Core.on) == "function" then
    ns.Core.on("PLAYER_ENTERING_WORLD", function() Meilenstein.noteLevel() end)
    ns.Core.on("PLAYER_REGEN_ENABLED", function()
      if Meilenstein.pending then after(Meilenstein.REGEN_DELAY, Meilenstein.flush) end
    end)
  end
end
