-- Texts of the welcome note (model/Welcome.lua, plan) and of the recap "Zuvor auf Eurer Reise" (model/Recap.lua): short blocks
-- with several variants per situation, "Ihr" form. Everything here turns finished DATA (names already sanitized by the caller)
-- into finished text; it reads no game data. German is the source (Locale.ns), English and the other languages in locales/*_model.lua
-- (area "m.RecapTexts"). Texts with {gap} start with the pause in words ("nach zwei Tagen" / "seit gestern Abend"); the sentence
-- gets its capital letter afterwards (upperFirst).
--   RecapTexts.gap(seconds, prevEnd, now) -> { seconds, word, kind = "after" | "since" }
--   RecapTexts.title(name) -> "Willkommen zurück, <Name>."
--   RecapTexts.note(parts, gap, rnd) -> sentences, variants   (parts = { activity, goal, anniversary } as in Welcome.plan)
--   RecapTexts.lateNote(gap, rnd) -> text
--   RecapTexts.story(facts, ctx) -> { paragraph, ... }     RecapTexts.standLines(stand) -> { line, ... }
--   RecapTexts.anniversary(a, rnd) -> sentence             RecapTexts.inZone(name) -> "in Westfall" / "im Brachland"
--   RecapTexts.questText(e, goals, who) -> short (2..3 whole sentences), full   RecapTexts.sentences(s) / cutWords(s, max)
--   RecapTexts.questPlaceholders(s, who) ($N $C $R $B $G)   RecapTexts.goalLine(text, have, need), openReady()
--   RecapTexts.asideLongest(dur), asideWalk(km)              ("Am Rande", nachtrag R2)
-- Place names get their preposition and article from the core Grammar (Grammar.lua): "in {dungeon}" -> "in den Todesminen",
-- "von {from} nach {to}" -> "vom Wegekreuz nach Sturmwind"; quest titles only stand in quotes after "die Quest".
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local RT = {}
Journal.RecapTexts = RT

local floor, max, min = math.floor, math.max, math.min
local sub, byte, gsub = string.sub, string.byte, string.gsub

local T = ns.Locale.ns("m.RecapTexts", {
  -- title and pause in words ----------------------------------------------------------------------------------------------
  title = "Willkommen zurück, {name}.",
  titleAnon = "Willkommen zurück.",
  minutes = "nach wenigen Minuten",
  hour1 = "nach einer Stunde",
  hoursN = "nach {n} Stunden",
  day1 = "nach einem Tag",
  daysN = "nach {n} Tagen",
  week1 = "nach einer Woche",
  weeksN = "nach {n} Wochen",
  month1 = "nach einem Monat",
  monthsN = "nach {n} Monaten",
  yearPlus = "nach mehr als einem Jahr",
  -- part of the day: morning, afternoon, evening, night
  sinceYesterday = { "seit gestern Morgen", "seit gestern Nachmittag", "seit gestern Abend", "seit gestern Nacht" },
  sinceToday = { "seit heute Morgen", "seit heute Mittag", "seit heute Abend", "seit heute Nacht" },
  -- number words for 2 to 12 (other values stay digits)
  numWords = { "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf" },
  inZone = "in {zone}",
  -- last activity (first sentence of the note) -------------------------------------------------------------------------------
  actQuestZoneAfter = {
    "{gap} seid Ihr wieder da: Ihr habt {zone} aufgehört, mitten in der Quest „{quest}“.",
    "{gap} geht die Reise weiter – zuletzt wart Ihr {zone} an der Quest „{quest}“.",
    "{gap} wartet {zone} noch die Quest „{quest}“ auf Euch.",
  },
  actQuestZoneSince = {
    "{gap} ruht Eure Reise: Ihr habt {zone} aufgehört, mitten in der Quest „{quest}“.",
    "{gap} lag Eure Reise still – zuletzt wart Ihr {zone} an der Quest „{quest}“.",
    "{gap} wartet {zone} noch die Quest „{quest}“ auf Euch.",
  },
  actQuestAfter = {
    "{gap} seid Ihr wieder da: Ihr habt mitten in der Quest „{quest}“ aufgehört.",
    "{gap} geht die Reise weiter – zuletzt wart Ihr an der Quest „{quest}“.",
  },
  actQuestSince = {
    "{gap} ruht Eure Reise: Ihr habt mitten in der Quest „{quest}“ aufgehört.",
    "{gap} lag Eure Reise still – zuletzt wart Ihr an der Quest „{quest}“.",
  },
  actDungeonAfter = {
    "{gap} seid Ihr wieder da. Zuletzt hat Euch ein Abenteuer in {dungeon} in Atem gehalten.",
    "{gap} geht es weiter – zuletzt wart Ihr in {dungeon} unterwegs.",
  },
  actDungeonSince = {
    "{gap} ruht Eure Reise. Zuletzt hat Euch ein Abenteuer in {dungeon} in Atem gehalten.",
    "{gap} lag alles still – zuletzt wart Ihr in {dungeon} unterwegs.",
  },
  actCraftAfter = {
    "{gap} seid Ihr wieder da: Zuletzt habt Ihr an Eurem Handwerk gefeilt: {skill}.",
    "{gap} geht es weiter – zuletzt wart Ihr bei {skill} fleißig.",
  },
  actCraftSince = {
    "{gap} ruht Eure Reise: Zuletzt habt Ihr an Eurem Handwerk gefeilt: {skill}.",
    "{gap} lag alles still – zuletzt wart Ihr bei {skill} fleißig.",
  },
  actFlightAfter = {
    "{gap} seid Ihr wieder da: Zuletzt wart Ihr in der Luft, von {from} nach {to}.",
    "{gap} geht es weiter – zuletzt ging der Flug von {from} nach {to}.",
  },
  actFlightSince = {
    "{gap} ruht Eure Reise: Zuletzt wart Ihr in der Luft, von {from} nach {to}.",
    "{gap} lag alles still – zuletzt ging der Flug von {from} nach {to}.",
  },
  actFlightPlainAfter = {
    "{gap} seid Ihr wieder da: Zuletzt wart Ihr hoch in der Luft.",
    "{gap} geht es weiter – zuletzt wart Ihr auf einem Flug unterwegs.",
  },
  actFlightPlainSince = {
    "{gap} ruht Eure Reise: Zuletzt wart Ihr hoch in der Luft.",
    "{gap} lag alles still – zuletzt wart Ihr auf einem Flug unterwegs.",
  },
  -- only a goal: the pause opens the note
  backAfter = { "{gap} seid Ihr wieder da.", "{gap} geht Eure Reise weiter." },
  backSince = { "{gap} ruht Eure Reise.", "{gap} lag alles still." },
  -- next goal (second sentence) ------------------------------------------------------------------------------------------------
  goalPin = {
    "Als Nächstes wartet „{text}“ auf Euch.",
    "Angepinnt ist noch „{text}“.",
    "Euer Fokus liegt auf „{text}“.",
  },
  goalLevel = {
    "Noch etwa {n} Quests, dann ist Stufe {level} erreicht.",
    "Bis Stufe {level} sind es etwa {n} Quests.",
  },
  goalLevelOne = {
    "Etwa eine Quest noch, dann ist Stufe {level} erreicht.",
    "Etwa eine Quest trennt Euch von Stufe {level}.",
  },
  goalLevelClose = {
    "Stufe {level} ist nicht mehr weit.",
    "Bis Stufe {level} fehlt nur noch ein Stück.",
  },
  goalLevelAlmost = {
    "Stufe {level} liegt fast zum Greifen nah.",
    "Nur ein winziges Stück noch bis Stufe {level}.",
  },
  goalTrainer = { "Beim Lehrer wartet Neues auf Euch.", "Ein Besuch beim Lehrer steht noch aus." },
  goalTodo = { "Auf Eurem To Do steht noch „{text}“.", "Offen ist noch Euer To Do „{text}“." },
  goalWerk = { "Auf der Werkbank wartet noch „{text}“.", "Euer Werkauftrag „{text}“ ist noch offen." },
  trainerShort = "Beim Lehrer wartet Neues",
  -- reminder (anniversary) -----------------------------------------------------------------------------------------------------
  -- ago words for 7, 14, 30, 60, 90, 180 and 365 days
  agoWords = { "vor einer Woche", "vor zwei Wochen", "vor einem Monat", "vor zwei Monaten", "vor drei Monaten", "vor einem halben Jahr", "vor einem Jahr" },
  annivLevel = "Heute {ago} habt Ihr Stufe {level} erreicht.",
  annivMedal = "Heute {ago} habt Ihr die Medaille „{title}“ errungen.",
  annivContinent = "Heute {ago} habt Ihr neues Land betreten: {zone}.",
  annivDungeon = "Heute {ago} wart Ihr zum ersten Mal in {dungeon}.",
  annivRaid = "Heute {ago} habt Ihr zum ersten Mal einen Schlachtzug betreten: {dungeon}.",
  -- waiting note (K5): the book does not open by itself in combat or an instance
  lateNote = { "Lange nicht gesehen – ein Klick öffnet den Rückblick.", "Es ist lange her. Ein Klick öffnet den Rückblick auf Eure Reise." },
  -- recap story ---------------------------------------------------------------------------------------------------------------
  spanOne = "In Eurer letzten Sitzung",
  spanMany = "In Euren letzten {n} Sitzungen",
  -- {zones}: finished place phrases ("im Alteracgebirge und im Arathihochland"), {places}: names inside a sentence
  storyWhere = "{span} wart Ihr {zones} unterwegs.",
  storyNoZone = "{span} habt Ihr Eure Reise fortgesetzt.",
  storyNewZones = "Zum ersten Mal habt Ihr dabei {places} betreten.",
  listAnd = "{a} und {b}",
  storyLevelUp = "Dabei seid Ihr von Stufe {from} auf Stufe {to} aufgestiegen.",
  storyLevelNew = "Dabei habt Ihr Stufe {to} erreicht.",
  storyLevelClose = "Stufe {level} liegt jetzt zum Greifen nah.",
  quests_one = "Eine Quest habt Ihr abgeschlossen.",
  quests_other = "{n} Quests habt Ihr abgeschlossen.",
  storyKills = "{n} Gegner gingen zu Boden.",
  storyDungeonNamed = "Ein Abstecher führte Euch nach {dungeon}.",
  storyDungeons_one = "Einmal ging es unter die Erde.",
  storyDungeons_other = "{n} Mal ging es unter die Erde.",
  storyBest = "Euer schönster Fund war {item}.",
  storyRare = "Ein seltener Gegner ging Euch ins Netz: {npc}.",
  storyMedal = "Neu in Eurer Chronik: die Medaille „{title}“.",
  storyMount = "Neu ist Euer eigenes Reittier: {name}.",
  storyMountPlain = "Neu ist Euer eigenes Reittier.",
  storyCloseWin = "Einmal ging ein Kampf haarscharf aus – Ihr standet am Ende noch.",
  storyFish = "Zum ersten Mal hat beim Angeln etwas angebissen.",
  storyElite = "Zum ersten Mal habt Ihr einen Elitegegner bezwungen.",
  -- "Zuletzt erledigt": goals when no quest text was written down
  doneGoals = "Eure Ziele: {list}.",
  goalCount = "{text}: {have}/{need}",
  openReady = "Bereit zur Abgabe",
  -- "Am Rande": a real side note (never a repeat of the paragraph)
  asideLongest = "Eure bisher längste Sitzung fiel in diese Zeit: {dur}.",
  asideWalk = "Zu Fuß habt Ihr dabei {km} km zurückgelegt.",
  kmFmt = "{a},{b}",
  -- retelling a turned-in quest ("Zuletzt erledigt"): {aux} = auxHave / auxBe, {body} = the clauses in the past
  auxHave = "habt", auxBe = "seid",
  retellPlain = "Ihr {aux} {body}.",
  retellFor = "{place} hatte Euch {giver} beauftragt, und Ihr {aux} {body}.",
  retellForNoPlace = "{giver} hatte Euch beauftragt, und Ihr {aux} {body}.",
  retellClose = "Abgeschlossen habt Ihr die Sache bei {npc}.",
  retellTask = "Die Quest verlangte: „{text}“",
  storyDeaths_one = "Einmal hat Euch der Tod ereilt.",
  storyDeaths_other = "{n} Mal hat Euch der Tod ereilt.",
  storyNoDeath = "Und kein einziges Mal seid Ihr gefallen.",
  -- stand lines ----------------------------------------------------------------------------------------------------------------
  standLevel = "Stufe {level}",
  standLevelPct = "Stufe {level}, {pct} % zur nächsten",
  standZone = "Ort: {zone}",
  standRested = "Ausgeruht ({pct} %)",
  standGold = "Geldbeutel: {gold}",
  goldG = "{g} Gold {s} Silber",
  goldS = "{s} Silber {k} Kupfer",
  goldK = "{k} Kupfer",
  openWerk = "Werkauftrag: {text}",
  hlMedal = "Medaille „{title}“",
})
RT.T = T

-- placeholders with place names per text group (Grammar.fill): the activity's {zone} is already a finished phrase
local PLACES_ACT = { dungeon = "dungeon", from = "point", to = "point" }
local PLACES_ANNIV = { zone = "zone", dungeon = "dungeon" }
local PLACES_STORY = { dungeon = "dungeon" }

local function gfmt(s, args, places)
  local G = ns.Grammar
  if G and places then return G.fmt(s, args, places) end
  return ns.Locale.fmt(s, args)
end

local function fmtList(list, i, args, places)
  local s = type(list) == "table" and list[i] or nil
  if type(s) ~= "string" then return nil end
  return gfmt(s, args, places)
end

-- capital letter at the start of a sentence: ASCII, Latin-1 and Cyrillic (UTF-8); anything else stays
local function upperFirst(s)
  if type(s) ~= "string" or s == "" then return s end
  local b = byte(s, 1)
  if b >= 97 and b <= 122 then return string.upper(sub(s, 1, 1)) .. sub(s, 2) end
  local b2 = byte(s, 2)
  if b == 0xC3 and b2 and b2 >= 0xA0 and b2 <= 0xBE and b2 ~= 0xB7 then return string.char(0xC3, b2 - 32) .. sub(s, 3) end
  if b == 0xD0 and b2 and b2 >= 0xB0 and b2 <= 0xBF then return string.char(0xD0, b2 - 32) .. sub(s, 3) end
  if b == 0xD1 and b2 and b2 >= 0x80 and b2 <= 0x8F then return string.char(0xD0, b2 + 32) .. sub(s, 3) end
  return s
end
RT.upperFirst = upperFirst

local function pick(rnd, n)
  if n <= 1 then return 1 end
  local i = type(rnd) == "function" and rnd(n) or nil
  if type(i) ~= "number" or i ~= i then i = math.random(n) end
  i = floor(i)
  if i < 1 then i = 1 elseif i > n then i = n end
  return i
end

local function count(list)
  return type(list) == "table" and #list or 0
end

local function numWord(n)
  n = floor(n)
  if n >= 2 and n <= 12 then
    local w = T.numWords
    if type(w) == "table" and type(w[n - 1]) == "string" then return w[n - 1] end
  end
  return tostring(n)
end

local function int(n)
  local Fmt = Journal.Fmt
  if Fmt and type(Fmt.int) == "function" then return Fmt.int(n) end
  return tostring(floor(n))
end

-- "in Westfall", "im Alteracgebirge", "in den Westlichen Pestländern", "in the Barrens" (Grammar.place via the text inZone)
function RT.inZone(name)
  if type(name) ~= "string" or name == "" then return nil end
  return gfmt(T.inZone, { zone = name }, { zone = "zone" })
end

-- zone name inside a sentence (nominative): "das Alteracgebirge", "the Barrens"; other languages: the name as it is
local function inSentence(name)
  local G = ns.Grammar
  local lang = G and G.langOf() or nil
  if lang == "de" or lang == "en" then return (G.place(name, "nom")) end
  return name
end
RT.inSentence = inSentence

-- pause in words; never a clock time. prevEnd/now (epoch) give "yesterday evening"; without them only hours/days
function RT.gap(seconds, prevEnd, now, tz)
  seconds = max(0, floor(tonumber(seconds) or 0))
  local out = { seconds = seconds, kind = "after" }
  local h, d = floor(seconds / 3600), floor(seconds / 86400)
  local function fmt(key, n) return ns.Locale.fmt(T[key], { n = numWord(n) }) end
  if seconds < 3600 then
    out.word = T.minutes
  elseif seconds < 21600 then
    local hr = max(1, floor(seconds / 3600 + 0.5))
    out.word = hr == 1 and T.hour1 or fmt("hoursN", hr)
  elseif seconds < 172800 then
    local word
    if type(prevEnd) == "number" and type(now) == "number" then
      tz = tonumber(tz) or 0
      local dayDiff = floor((now + tz) / 86400) - floor((prevEnd + tz) / 86400)
      local hour = floor(((prevEnd + tz) % 86400) / 3600)
      local part = (hour >= 5 and hour <= 11) and 1 or (hour >= 12 and hour <= 16) and 2 or (hour >= 17 and hour <= 21) and 3 or 4
      local list = dayDiff == 0 and T.sinceToday or dayDiff == 1 and T.sinceYesterday or nil
      word = type(list) == "table" and list[part] or nil
    end
    if word then
      out.word, out.kind = word, "since"
    else
      if h < 24 then out.word = fmt("hoursN", h)
      elseif h < 36 then out.word = T.day1
      else out.word = fmt("daysN", 2) end
    end
  elseif d < 7 then
    out.word = fmt("daysN", d)
  elseif d < 14 then
    out.word = T.week1
  elseif d < 30 then
    out.word = fmt("weeksN", floor(d / 7))
  elseif d < 365 then
    local m = floor(d / 30)
    out.word = m == 1 and T.month1 or fmt("monthsN", m)
  else
    out.word = T.yearPlus
  end
  return out
end

function RT.title(name)
  if type(name) == "string" and name ~= "" then return ns.Locale.fmt(T.title, { name = name }) end
  return T.titleAnon
end

-- first sentence variants of the activity (all alternatives, rendered)
local function activityVariants(a, gap)
  local since = gap and gap.kind == "since"
  local args = { gap = gap and gap.word or "" }
  local list
  if a.kind == "quest" then
    args.quest = a.quest
    if a.zone then
      args.zone = RT.inZone(a.zone)
      list = since and T.actQuestZoneSince or T.actQuestZoneAfter
    else
      list = since and T.actQuestSince or T.actQuestAfter
    end
  elseif a.kind == "dungeon" then
    args.dungeon = a.dungeon or a.zone
    list = since and T.actDungeonSince or T.actDungeonAfter
  elseif a.kind == "craft" or a.kind == "werk" then
    args.skill = a.skill or a.quest
    list = since and T.actCraftSince or T.actCraftAfter
  elseif a.kind == "flight" then
    if a.from and a.to then
      args.from, args.to = a.from, a.to
      list = since and T.actFlightSince or T.actFlightAfter
    else
      list = since and T.actFlightPlainSince or T.actFlightPlainAfter
    end
  end
  local out = {}
  for i = 1, count(list) do out[i] = upperFirst(fmtList(list, i, args, PLACES_ACT)) end
  return out
end

local function goalVariants(g)
  local list, args = nil, { text = g.text }
  if g.kind == "pin" then
    list = T.goalPin
  elseif g.kind == "level" then
    args.level = g.level
    args.n = g.n
    if g.words == "almost" then list = T.goalLevelAlmost
    elseif g.words then list = T.goalLevelClose
    elseif g.n == 1 then list = T.goalLevelOne
    else list = T.goalLevel end
  elseif g.kind == "trainer" then
    list = T.goalTrainer
  elseif g.kind == "todo" then
    list = T.goalTodo
  elseif g.kind == "werk" then
    list = T.goalWerk
  end
  local out = {}
  for i = 1, count(list) do out[i] = upperFirst(fmtList(list, i, args)) end
  return out
end

-- note(parts, gap, rnd) -> sentences (1..2), variants. No activity and no goal -> nil.
function RT.note(parts, gap, rnd)
  if type(parts) ~= "table" then return nil end
  local a, g = parts.activity, parts.goal
  local s1, s2
  local s1list = a and activityVariants(a, gap) or nil
  local s2list = g and goalVariants(g) or nil
  if s1list and #s1list > 0 then
    s1 = s1list[pick(rnd, #s1list)]
  elseif (s2list and #s2list > 0) or parts.backOnly then
    local since = gap and gap.kind == "since"
    local list = since and T.backSince or T.backAfter
    s1 = upperFirst(fmtList(list, pick(rnd, count(list)), { gap = gap and gap.word or "" }))
  end
  if not s1 then return nil end
  if s2list and #s2list > 0 then
    s2 = s2list[pick(rnd, #s2list)]
  elseif parts.anniversary then
    s2 = parts.anniversary
  end
  local sentences = { s1 }
  if s2 and s2 ~= "" then sentences[2] = s2 end
  local variants = { { s1, sentences[2] }, { s1 } }
  if not sentences[2] then variants = { { s1 } } end
  return sentences, variants
end

function RT.lateNote(gap, rnd)
  local list = T.lateNote
  local n = count(list)
  if n == 0 then return nil end
  return list[pick(rnd, n)]
end

local AGO_DAYS = { 7, 14, 30, 60, 90, 180, 365 }
RT.AGO_DAYS = AGO_DAYS

-- a = { kind = "level" | "medal" | "continent" | "dungeon" | "raid", days, level, title, zone, dungeon }
function RT.anniversary(a)
  if type(a) ~= "table" then return nil end
  local ago
  for i, d in ipairs(AGO_DAYS) do
    if d == a.days then
      local w = T.agoWords
      ago = type(w) == "table" and w[i] or nil
    end
  end
  if not ago then return nil end
  local args = { ago = ago, level = a.level, title = a.title, zone = a.zone, dungeon = a.dungeon }
  local key = a.kind == "level" and "annivLevel" or a.kind == "medal" and "annivMedal" or a.kind == "continent" and "annivContinent"
    or a.kind == "dungeon" and "annivDungeon" or a.kind == "raid" and "annivRaid" or nil
  if not key then return nil end
  return upperFirst(gfmt(T[key], args, PLACES_ANNIV))
end

-- "A, B und C"
local function joinNames(list, zones)
  local n = #list
  if n == 0 then return nil end
  local items = {}
  for i, v in ipairs(list) do items[i] = zones and inSentence(v) or v end
  if n == 1 then return items[1] end
  local head = {}
  for i = 1, n - 1 do head[i] = items[i] end
  return ns.Locale.fmt(T.listAnd, { a = table.concat(head, ", "), b = items[n] })
end
RT.joinNames = joinNames

local function plural(n, key)
  local one, other = key .. "_one", key .. "_other"
  return ns.Locale.fmt(T[ns.Locale.plural(n, one, other)], { n = int(n) })
end

-- "im Alteracgebirge und im Arathihochland" (each name with its own preposition, Grammar via inZone)
local function whereList(names)
  local items = {}
  for _, v in ipairs(names) do
    local p = RT.inZone(v)
    if p then items[#items + 1] = p end
  end
  if #items == 0 then return nil end
  if #items == 1 then return items[1] end
  local head = {}
  for i = 1, #items - 1 do head[i] = items[i] end
  return ns.Locale.fmt(T.listAnd, { a = table.concat(head, ", "), b = items[#items] })
end
RT.whereList = whereList

-- names as objects of a sentence: German accusative with article ("das Arathihochland"), English "the Barrens"
local function objectList(names)
  local G = ns.Grammar
  local lang = G and G.langOf() or nil
  local items = {}
  for i, v in ipairs(names) do
    if lang == "de" then items[i] = (G.place(v, "acc")) or v
    elseif lang == "en" then items[i] = (G.place(v, "nom")) or v
    else items[i] = v end
  end
  local n = #items
  if n == 0 then return nil end
  if n == 1 then return items[1] end
  local head = {}
  for i = 1, n - 1 do head[i] = items[i] end
  return ns.Locale.fmt(T.listAnd, { a = table.concat(head, ", "), b = items[n] })
end

RT.STORY_HIGHLIGHTS_MAX = 5 -- sentences in paragraph 2 besides the deaths
RT.KILLS_MIN = 10           -- fewer kills are not worth a sentence
RT.CLOSE_PCT = 80           -- "Stufe X liegt zum Greifen nah" from this share of the level on

-- story(facts, ctx): paragraph 1 = the way (zones, new zones, levels, quests, kills), paragraph 2 = the highlights and falls.
-- facts as in Recap (zones, newZones, levelFrom, levelTo, levelUps, deaths, kills, quests, dungeons, highlights, firsts),
-- ctx = { sessions, level (now), xpPct (now) }. Only zones count as places (never a continent: the caller filters), exact numbers,
-- the level only when it says something (a rise, or close to the next level). The best find stands with its plain name: the page
-- turns it into a coloured item link.
function RT.story(facts, ctx)
  facts, ctx = type(facts) == "table" and facts or {}, type(ctx) == "table" and ctx or {}
  local sessions = floor(tonumber(ctx.sessions) or 1)
  local span = sessions > 1 and ns.Locale.fmt(T.spanMany, { n = numWord(sessions) }) or T.spanOne
  local p1, p2 = {}, {}
  local zones = type(facts.zones) == "table" and facts.zones or {}
  local where = #zones > 0 and whereList(zones) or nil
  if where then
    p1[#p1 + 1] = upperFirst(ns.Locale.fmt(T.storyWhere, { span = span, zones = where }))
  elseif (facts.quests or 0) > 0 or (facts.kills or 0) > 0 then
    p1[#p1 + 1] = upperFirst(ns.Locale.fmt(T.storyNoZone, { span = span }))
  end
  local fresh = type(facts.newZones) == "table" and facts.newZones or {}
  if #fresh > 0 and #p1 > 0 then -- "dabei": only after the sentence of the way
    local places = objectList(fresh)
    if places then p1[#p1 + 1] = ns.Locale.fmt(T.storyNewZones, { places = places }) end
  end
  local lf, lt = tonumber(facts.levelFrom), tonumber(facts.levelTo)
  if lf and lt and lt > lf + 1 then
    p1[#p1 + 1] = ns.Locale.fmt(T.storyLevelUp, { from = floor(lf), to = floor(lt) })
  elseif lt and ((lf and lt == lf + 1) or (not lf and (facts.levelUps or 0) > 0)) then
    p1[#p1 + 1] = ns.Locale.fmt(T.storyLevelNew, { to = floor(lt) })
  else
    local now, pct = tonumber(ctx.level), tonumber(ctx.xpPct)
    if now and pct and pct >= RT.CLOSE_PCT then p1[#p1 + 1] = ns.Locale.fmt(T.storyLevelClose, { level = floor(now) + 1 }) end
  end
  if (facts.quests or 0) > 0 then p1[#p1 + 1] = plural(facts.quests, "quests") end
  if (facts.kills or 0) >= RT.KILLS_MIN then p1[#p1 + 1] = ns.Locale.fmt(T.storyKills, { n = int(floor(facts.kills)) }) end
  -- highlights: dungeon, medal, rare, first times, best find (at most STORY_HIGHLIGHTS_MAX; the find always has its place)
  local by = {}
  for _, h in ipairs(type(facts.highlights) == "table" and facts.highlights or {}) do
    if type(h) == "table" and h.kind and not by[h.kind] then by[h.kind] = h end
  end
  local list = {}
  if by.dungeon and (facts.dungeons or 0) <= 1 then
    list[#list + 1] = gfmt(T.storyDungeonNamed, { dungeon = by.dungeon.name or by.dungeon.text }, PLACES_STORY)
  elseif (facts.dungeons or 0) > 0 then
    list[#list + 1] = plural(facts.dungeons, "storyDungeons")
  end
  if by.medal then list[#list + 1] = ns.Locale.fmt(T.storyMedal, { title = by.medal.name or by.medal.text }) end
  if by.rare then list[#list + 1] = ns.Locale.fmt(T.storyRare, { npc = by.rare.name or by.rare.text }) end
  for _, f in ipairs(type(facts.firsts) == "table" and facts.firsts or {}) do
    local s
    if type(f) == "table" then
      if f.kind == "mount" then
        s = (type(f.name) == "string" and f.name ~= "") and ns.Locale.fmt(T.storyMount, { name = f.name }) or T.storyMountPlain
      elseif f.kind == "close_win" then s = T.storyCloseWin
      elseif f.kind == "fish" then s = T.storyFish
      elseif f.kind == "elite" then s = T.storyElite end
    end
    if type(s) == "string" then list[#list + 1] = s end
  end
  local bestS = by.best and ns.Locale.fmt(T.storyBest, { item = by.best.name or by.best.text }) or nil
  local room = RT.STORY_HIGHLIGHTS_MAX - (bestS and 1 or 0)
  for i = 1, math.min(#list, room) do p2[#p2 + 1] = list[i] end
  if bestS then p2[#p2 + 1] = bestS end
  if (facts.deaths or 0) > 0 then
    p2[#p2 + 1] = plural(facts.deaths, "storyDeaths")
  elseif (facts.kills or 0) >= 20 and #p2 > 0 then
    p2[#p2 + 1] = T.storyNoDeath
  end
  local out = {}
  if #p1 > 0 then out[#out + 1] = table.concat(p1, " ") end
  if #p2 > 0 then out[#out + 1] = table.concat(p2, " ") end
  return out
end

-- quest texts ("Zuletzt erledigt") ------------------------------------------------------------------------------------------

RT.DONE_SENTENCES = 3   -- sentences of a short quest text
RT.DONE_MAX = 260       -- bytes of a short quest text
RT.DONE_FULL_MAX = 900  -- bytes of the full text in the tooltip
local ELLIPSIS = "\226\128\166"

-- placeholders of quest texts: $N name, $C class, $R race, $B line break, $G male:female; (others removed)
function RT.questPlaceholders(s, who)
  if type(s) ~= "string" then return nil end
  who = type(who) == "table" and who or {}
  local female = who.sex == 3
  s = gsub(s, "%$[Gg]%s*([^:;]*):([^;]*);", function(m, f) return female and f or m end)
  s = gsub(s, "%$[Bb]", " ")
  s = gsub(s, "%$([NnCcRr])", function(c)
    c = string.lower(c)
    local v = c == "n" and who.name or c == "c" and who.class or c == "r" and who.race or nil
    return type(v) == "string" and v or ""
  end)
  s = gsub(s, "%$%a", "")
  s = gsub(s, "%s+([,%.!%?])", "%1")
  s = gsub(s, "%s%s+", " ")
  return s
end

-- closing marks after the end of a sentence: quotes and brackets (ASCII and the UTF-8 quotes “ ” « »)
local CLOSERS = { ['"'] = 1, ["'"] = 1, [")"] = 1, ["\226\128\156"] = 3, ["\226\128\157"] = 3, ["\194\187"] = 2, ["\194\171"] = 2 }

local function closerAt(s, i)
  for c, n in pairs(CLOSERS) do
    if sub(s, i, i + n - 1) == c then return n end
  end
  return nil
end

-- whole sentences of a text (ends: . ! ? … with closing quotes, then a space or the end); without an end the text is one sentence
function RT.sentences(s)
  local out = {}
  if type(s) ~= "string" then return out end
  s = gsub(s, "%s+", " ")
  s = gsub(s, "^ ", "")
  s = gsub(s, " $", "")
  local n, i, start = #s, 1, 1
  while i <= n do
    local c = sub(s, i, i)
    local stop
    if c == "." or c == "!" or c == "?" then
      stop = i
      while stop < n and string.find(sub(s, stop + 1, stop + 1), "[%.!%?]") do stop = stop + 1 end
    elseif sub(s, i, i + 2) == ELLIPSIS then
      stop = i + 2
    end
    if stop then
      local k = closerAt(s, stop + 1)
      while k do
        stop = stop + k
        k = closerAt(s, stop + 1)
      end
      if stop >= n or sub(s, stop + 1, stop + 1) == " " then
        out[#out + 1] = sub(s, start, stop)
        start = stop + 2
        i = start
      else
        i = stop + 1
      end
    else
      i = i + 1
    end
  end
  if start <= n then
    local rest = sub(s, start)
    if string.find(rest, "%S") then out[#out + 1] = rest end
  end
  return out
end

-- cut at the last space before maxB bytes, with an ellipsis (never inside a word or a UTF-8 character)
local function cutWords(s, maxB)
  if type(s) ~= "string" or #s <= maxB then return s end
  local cut = sub(s, 1, maxB - #ELLIPSIS)
  local sp
  for p = #cut, 1, -1 do
    if sub(cut, p, p) == " " then sp = p break end
  end
  if sp and sp > 1 then
    cut = sub(cut, 1, sp - 1)
  else
    cut = ns.Sanitize.cut(s, maxB - #ELLIPSIS)
  end
  cut = gsub(cut, "[%s,;:%-]+$", "")
  return cut .. ELLIPSIS
end
RT.cutWords = cutWords

-- e = the written-down quest texts (objectives, reward = completion text, detail), goals = { { text, have, need } } (log/index),
-- who = { name, class, race, sex }. -> short (2..3 whole sentences, at most DONE_MAX bytes) | nil, full (tooltip) | nil.
-- Plain text: the caller sanitizes.
function RT.questText(e, goals, who)
  e = type(e) == "table" and e or {}
  local function clean(v)
    if type(v) ~= "string" or v == "" then return nil end
    v = RT.questPlaceholders(v, who)
    v = gsub(v, "^%s+", "")
    v = gsub(v, "%s+$", "")
    return v ~= "" and v or nil
  end
  local obj, rew, det = clean(e.objectives), clean(e.reward), clean(e.detail)
  local picked, used = {}, 0
  local function take(text, n)
    local k = 0
    for _, s in ipairs(RT.sentences(text)) do
      if #picked >= RT.DONE_SENTENCES or k >= n then return end
      if used > 0 and used + #s + 1 > RT.DONE_MAX then return end
      picked[#picked + 1] = s
      used = used + #s + 1
      k = k + 1
    end
  end
  if obj then take(obj, 2) end
  if rew then take(rew, obj and 1 or 2) end
  if #picked < 2 and det then take(det, 2) end
  local short
  if #picked > 0 then
    short = cutWords(table.concat(picked, " "), RT.DONE_MAX)
  else
    local names = {}
    for _, g in ipairs(type(goals) == "table" and goals or {}) do
      if type(g) == "table" and type(g.text) == "string" and g.text ~= "" and #names < 3 then
        local need = tonumber(g.need)
        -- have = need on purpose: the quest is handed in, so every goal counts as done
        names[#names + 1] = (need and need > 1) and ns.Locale.fmt(T.goalCount, { text = g.text, have = int(floor(need)), need = int(floor(need)) })
          or g.text
      end
    end
    if #names > 0 then short = cutWords(ns.Locale.fmt(T.doneGoals, { list = joinNames(names) }), RT.DONE_MAX) end
  end
  local parts = {}
  for _, v in ipairs({ det, obj, rew }) do parts[#parts + 1] = v end
  local full = #parts > 0 and cutWords(table.concat(parts, "\n\n"), RT.DONE_FULL_MAX) or nil
  return short, full
end

-- goal line of an open quest: "Kobold getötet: 4/8"
function RT.goalLine(text, have, need)
  if type(text) ~= "string" or text == "" then return nil end
  have, need = tonumber(have), tonumber(need)
  if have and need and need > 0 then return ns.Locale.fmt(T.goalCount, { text = text, have = int(floor(have)), need = int(floor(need)) }) end
  return text
end
function RT.openReady() return T.openReady end

-- retelling a quest ("Zuletzt erledigt") -----------------------------------------------------------------------------------
-- Rule based, no guessing: the imperative objectives become the past ("Bringt X zu Y." -> "Ihr habt X zu Y gebracht."), two
-- clauses joined, the giver as the opening ("Für Magistrat Maleb ..."), the turn-in NPC as the closing ("... bei Stormpike in
-- Ironforge abgeschlossen."). NPC speech (praise, thanks, the player's name) is never retold. A sentence with an unknown verb
-- falls back to "Euer Auftrag lautete: „…“". German and English; other languages only the fallback form.

-- German: imperative (2nd person plural) -> { participle, aux ("h" = haben, "s" = sein), refl (reflexive "Euch"),
-- sep = { particle = { participle, aux } } for separable verbs ("Kehrt ... zurück") }
local DE_VERBS = {
  ["tötet"] = { "getötet" }, ["erschlagt"] = { "erschlagen" }, ["vernichtet"] = { "vernichtet" }, ["erlegt"] = { "erlegt" },
  ["besiegt"] = { "besiegt" }, ["bezwingt"] = { "bezwungen" }, ["jagt"] = { "gejagt" },
  ["bringt"] = { "gebracht", sep = { ["zurück"] = { "zurückgebracht" }, mit = { "mitgebracht" } } },
  ["überbringt"] = { "überbracht" }, ["tragt"] = { "getragen" },
  ["sammelt"] = { "gesammelt", sep = { ein = { "eingesammelt" } } }, ["besorgt"] = { "besorgt" }, ["beschafft"] = { "beschafft" },
  ["holt"] = { "geholt", sep = { ab = { "abgeholt" }, ["zurück"] = { "zurückgeholt" } } }, ["erbeutet"] = { "erbeutet" },
  ["findet"] = { "gefunden", sep = { heraus = { "herausgefunden" } } },
  ["sucht"] = { "gesucht", sep = { auf = { "aufgesucht" } } },
  ["sprecht"] = { "gesprochen" }, ["redet"] = { "geredet" },
  ["begebt"] = { "begeben", refl = true }, ["meldet"] = { "gemeldet", refl = true, sep = { ["zurück"] = { "zurückgemeldet" } } },
  ["reist"] = { "gereist", "s" }, ["geht"] = { "gegangen", "s" }, ["lauft"] = { "gelaufen", "s" }, ["fliegt"] = { "geflogen", "s" },
  ["kehrt"] = { nil, sep = { ["zurück"] = { "zurückgekehrt", "s" }, heim = { "heimgekehrt", "s" } } },
  ["kommt"] = { "gekommen", "s", sep = { ["zurück"] = { "zurückgekommen", "s" } } },
  ["liefert"] = { "geliefert", sep = { ab = { "abgeliefert" }, aus = { "ausgeliefert" } } },
  ["übergebt"] = { "übergeben" }, ["gebt"] = { "gegeben", sep = { ab = { "abgegeben" } } },
  ["untersucht"] = { "untersucht" }, ["erkundet"] = { "erkundet" }, ["befreit"] = { "befreit" }, ["rettet"] = { "gerettet" },
  ["beschützt"] = { "beschützt" }, ["eskortiert"] = { "eskortiert" }, ["begleitet"] = { "begleitet" }, ["helft"] = { "geholfen" },
  ["verwendet"] = { "verwendet" }, ["benutzt"] = { "benutzt" }, ["zerstört"] = { "zerstört" }, ["verbrennt"] = { "verbrannt" },
  ["legt"] = { "gelegt", sep = { ab = { "abgelegt" } } }, ["platziert"] = { "platziert" }, ["pflückt"] = { "gepflückt" },
  ["nehmt"] = { "genommen" }, ["lest"] = { "gelesen" }, ["zeigt"] = { "gezeigt" }, ["wartet"] = { "gewartet" },
  ["fangt"] = { "gefangen", sep = { ein = { "eingefangen" } } }, ["reinigt"] = { "gereinigt" }, ["säubert"] = { "gesäubert" },
  ["grabt"] = { "gegraben", sep = { aus = { "ausgegraben" } } }, ["bergt"] = { "geborgen" }, ["stehlt"] = { "gestohlen" },
  ["erobert"] = { "erobert" }, ["vergiftet"] = { "vergiftet" }, ["zündet"] = { nil, sep = { an = { "angezündet" } } },
  ["schlagt"] = { "geschlagen", sep = { ["zurück"] = { "zurückgeschlagen" } } }, ["überprüft"] = { "überprüft" },
  ["erledigt"] = { "erledigt" }, ["berichtet"] = { "berichtet" }, ["kauft"] = { "gekauft" }, ["stellt"] = { "gestellt", sep = { sicher = { "sichergestellt" } } },
  ["macht"] = { "gemacht", sep = { ausfindig = { "ausfindig gemacht" } } },
}
-- English: imperative -> past ("Speak with" works as "spoke with": only the first word changes)
local EN_VERBS = {
  kill = "killed", slay = "slew", destroy = "destroyed", defeat = "defeated", hunt = "hunted", bring = "brought",
  collect = "collected", gather = "gathered", obtain = "obtained", acquire = "acquired", retrieve = "retrieved", recover = "recovered",
  find = "found", locate = "located", seek = "sought", search = "searched", speak = "spoke", talk = "talked", travel = "travelled",
  go = "went", head = "headed", venture = "ventured", ["return"] = "returned", deliver = "delivered", take = "took", give = "gave",
  escort = "escorted", protect = "protected", defend = "defended", use = "used", investigate = "investigated", explore = "explored",
  report = "reported", free = "freed", rescue = "rescued", help = "helped", burn = "burned", place = "placed", put = "put",
  get = "got", steal = "stole", capture = "captured", read = "read", wait = "waited", show = "showed", inspect = "inspected",
  check = "checked", purchase = "purchased", buy = "bought", carry = "carried", clear = "cleared", fetch = "fetched",
}
-- German conjunctions that open a subordinate clause after a comma: the participle goes before the comma
local DE_SUB = { der = true, die = true, das = true, dem = true, den = true, deren = true, dessen = true, welche = true, welcher = true,
  welches = true, damit = true, um = true, wo = true, wenn = true, weil = true, bevor = true, als = true, dass = true, ["daß"] = true,
  ob = true, sobald = true, nachdem = true, bis = true, falls = true }
RT.DE_VERBS, RT.EN_VERBS = DE_VERBS, EN_VERBS

local function firstWord(s)
  local w, rest = string.match(s, "^(%S+)%s*(.*)$")
  return w, rest or ""
end

local function lowerAll(s)
  s = string.lower(s)
  -- the umlauts the verbs start with (Ü)
  return (gsub(s, "\195\156", "\195\188"))
end

-- one German imperative clause -> { aux = "h"|"s", text = "4 Schattenmagier getötet", refl } | nil
local function deClause(c)
  c = gsub(c, "^%s+", "")
  c = gsub(c, "[%s%.!]+$", "")
  if c == "" or string.find(c, "%?") then return nil end
  local w, rest = firstWord(c)
  local v = w and DE_VERBS[lowerAll(w)]
  if not v then return nil end
  local refl = v.refl == true
  if refl then
    local e, r2 = firstWord(rest)
    if e == "Euch" then rest = r2 else refl = false end
  end
  local part, aux = v[1], v[2] or "h"
  -- "kehrt dann zurück zu X": the particle (after an optional "dann") right behind the verb
  local lead = gsub(rest, "^dann%s+", "")
  local p1, after1 = firstWord(lead)
  if p1 and v.sep and v.sep[lowerAll(p1)] then
    local s = v.sep[lowerAll(p1)]
    return { aux = s[2] or "h", text = (refl and "Euch " or "") .. (after1 ~= "" and (after1 .. " ") or "") .. s[1] }
  end
  local last = string.match(rest, "(%S+)$")
  if last and v.sep and v.sep[lowerAll(last)] then
    local s = v.sep[lowerAll(last)]
    part, aux = s[1], s[2] or "h"
    rest = gsub(rest, "%s*%S+$", "")
  end
  if not part then return nil end
  -- the participle before a subordinate clause (", der ..."), else at the end
  local before, after
  for a, word in string.gmatch(rest, "()%s*,%s+([%a\128-\255]+)") do
    if DE_SUB[lowerAll(word)] then
      before, after = string.sub(rest, 1, a - 1), string.sub(rest, a)
      break
    end
  end
  local text
  if before then text = (before ~= "" and (before .. " ") or "") .. part .. after
  else text = (rest ~= "" and (rest .. " ") or "") .. part end
  if refl then text = "Euch " .. text end
  return { aux = aux, text = text }
end

local function enClause(c)
  c = gsub(c, "^%s+", "")
  c = gsub(c, "[%s%.!]+$", "")
  if c == "" or string.find(c, "%?") then return nil end
  local w, rest = firstWord(c)
  local past = w and EN_VERBS[string.lower(w)]
  if not past then return nil end
  return { aux = "h", text = past .. (rest ~= "" and (" " .. rest) or "") }
end

-- clauses of one objective sentence ("Sammelt X und bringt sie zu Y." -> two clauses); nil when any part is unknown.
-- Split only before " und <verb>" / ", dann <verb>" (English " and <verb>" / ", then <verb>") with a known verb.
local function clausesOf(sentence, lang)
  local conv = lang == "de" and deClause or enClause
  local seps = lang == "de" and { ",?%s+und%s+", ",%s+dann%s+", ",%s+" } or { ",?%s+and%s+", ",%s+then%s+", ",%s+" }
  local cuts = {}
  for _, sp in ipairs(seps) do
    local pos = 1
    while true do
      local a, b = string.find(sentence, sp, pos)
      if not a then break end
      local word = string.match(sentence, "^([%a\128-\255]+)", b + 1)
      local known = word and (lang == "de" and DE_VERBS[lowerAll(word)] or (lang ~= "de" and EN_VERBS[string.lower(word)]))
      if known then cuts[#cuts + 1] = { a = a, b = b } end
      pos = b + 1
    end
  end
  table.sort(cuts, function(x, y) return x.a < y.a end)
  local parts, pos = {}, 1
  for _, c in ipairs(cuts) do
    if c.a >= pos then
      local cl = conv(string.sub(sentence, pos, c.a - 1))
      if not cl then return nil end
      parts[#parts + 1] = cl
      pos = c.b + 1
    end
  end
  local last = conv(string.sub(sentence, pos))
  if not last then return nil end
  parts[#parts + 1] = last
  return parts
end
RT.clausesOf = clausesOf

-- joined body: "4 X getötet und den Kopf zu Y gebracht" with the aux of the first clause; a change of aux names the new one
local function joinClauses(clauses, lang)
  local first = clauses[1]
  local out = { first.text }
  for i = 2, #clauses do
    local c = clauses[i]
    local word = lang == "de" and "und" or "and"
    if lang == "de" and c.aux ~= clauses[i - 1].aux then
      out[#out + 1] = word .. " " .. (c.aux == "s" and T.auxBe or T.auxHave) .. " " .. c.text
    else
      out[#out + 1] = word .. " " .. c.text
    end
  end
  return table.concat(out, " "), first.aux
end

-- is a sentence NPC speech (praise, thanks, the player's name, a question, first person)? -> never retold
local PRAISE = { "gut gemacht", "danke", "dank", "weise", "ausgezeichnet", "hervorragend", "well done", "thank", "wise", "excellent" }
function RT.isSpeech(s, who)
  if type(s) ~= "string" then return true end
  local l = string.lower(s)
  if string.find(s, "[!?]") then return true end
  for _, p in ipairs(PRAISE) do if string.find(l, p, 1, true) then return true end end
  if type(who) == "table" and type(who.name) == "string" and who.name ~= "" and string.find(s, who.name, 1, true) then return true end
  local w = string.match(s, "^(%S+)")
  w = w and string.lower(w) or ""
  if w == "ich" or w == "wir" or w == "i" or w == "we" or w == "mein" or w == "my" then return true end
  return false
end

RT.RETELL_MAX = 260

-- "Darren Malvew aus Southshore will, dass Ihr 8 Berglöwen tötet." -> clause "8 Berglöwen getötet", by "Darren Malvew aus Southshore"
-- (English: "X wants you to kill 8 lions." -> "killed 8 lions")
local DE_WISH = { will = true, ["möchte"] = true, ["wünscht"] = true, braucht = true }
function RT.wishClause(sentence, lang)
  if type(sentence) ~= "string" then return nil end
  local s = gsub(sentence, "[%s%.]+$", "")
  if lang == "de" then
    local by, wish, rest, verb = string.match(s, "^(.-)%s+(%S+),%s+dass%s+Ihr%s+(.+)%s+(%S+)$")
    if not (by and DE_WISH[lowerAll(wish)]) then return nil end
    local v = DE_VERBS[lowerAll(verb)]
    if not (v and v[1]) or string.find(rest, ",") then return nil end
    return { aux = v[2] or "h", text = rest .. " " .. v[1] }, by
  elseif lang == "en" then
    local by, verb, rest = string.match(s, "^(.-)%s+wants%s+you%s+to%s+(%a+)%s+(.+)$")
    local past = verb and EN_VERBS[string.lower(verb)]
    if not (by and past) then return nil end
    return { aux = "h", text = past .. " " .. rest }, by
  end
  return nil
end

-- retell(e, ctx) -> text | nil
--   e = { objectives, reward, detail } (plain, placeholders not yet replaced), ctx = { who, giver = { name, zone }, turnin = { name, zone } }
function RT.retell(e, ctx)
  e = type(e) == "table" and e or {}
  ctx = type(ctx) == "table" and ctx or {}
  local G = ns.Grammar
  local lang = G and G.langOf() or nil
  local obj = type(e.objectives) == "string" and RT.questPlaceholders(e.objectives, ctx.who) or nil
  if not obj or not string.find(obj, "%S") then return nil end
  local sentences = RT.sentences(obj)
  if #sentences == 0 then return nil end
  local function person(p)
    if type(p) ~= "table" or type(p.name) ~= "string" or p.name == "" then return nil end
    local place = p.zone and RT.inZone(p.zone) or nil
    return place and (p.name .. " " .. place) or p.name
  end
  local task, wishGiver
  if lang == "de" or lang == "en" then
    local clauses = {}
    for i = 1, min(2, #sentences) do
      local cs
      if i == 1 then
        local c, by = RT.wishClause(sentences[1], lang)
        if c then cs, wishGiver = { c }, by end
      end
      cs = cs or clausesOf(sentences[i], lang)
      if not cs then
        if i == 1 then task = sentences[1] end
        break
      end
      for _, c in ipairs(cs) do clauses[#clauses + 1] = c end
    end
    -- a person already named in the text (surname is enough: "Magistrat Henry Maleb" / "Magistrat Maleb") is not named again
    local function named(text, name)
      if type(name) ~= "string" or name == "" then return false end
      if string.find(text, name, 1, true) then return true end
      local last = string.match(name, "(%S+)$")
      return last ~= nil and #last >= 3 and string.find(text, last, 1, true) ~= nil
    end
    if #clauses > 0 and not task then
      local function build(list)
        local body, aux = joinClauses(list, lang)
        local auxW = aux == "s" and T.auxBe or T.auxHave
        local gName = wishGiver or (type(ctx.giver) == "table" and type(ctx.giver.name) == "string" and ctx.giver.name ~= "" and ctx.giver.name) or nil
        local place = (not wishGiver) and type(ctx.giver) == "table" and ctx.giver.zone and RT.inZone(ctx.giver.zone) or nil
        local s
        if gName and (wishGiver or not named(body, gName)) then
          -- the giver in the nominative ("Im Vorgebirge von Hillsbrad hatte Euch Meister der Lehren Dibbs beauftragt, und Ihr ...")
          if place then
            s = ns.Locale.fmt(T.retellFor, { place = upperFirst(place), giver = gName, aux = auxW, body = body })
          else
            s = ns.Locale.fmt(T.retellForNoPlace, { giver = gName, aux = auxW, body = body })
          end
        else
          s = ns.Locale.fmt(T.retellPlain, { aux = auxW, body = body })
        end
        return upperFirst(s)
      end
      local s1 = build(clauses)
      if #s1 > RT.RETELL_MAX and #clauses > 1 then s1 = build({ clauses[1] }) end
      local out = { s1 }
      local tn = ctx.turnin
      local closing = person(tn)
      if closing and not named(s1, tn.name)
          and not (type(ctx.giver) == "table" and ctx.giver.name == tn.name and not wishGiver) then
        local s2 = ns.Locale.fmt(T.retellClose, { npc = closing })
        if #s1 + #s2 + 1 <= RT.RETELL_MAX then out[#out + 1] = s2 end
      end
      local text = table.concat(out, " ")
      if #text > RT.RETELL_MAX then text = cutWords(text, RT.RETELL_MAX) end
      return text
    end
  end
  task = task or sentences[1]
  if #task > RT.RETELL_MAX - 30 then task = cutWords(task, RT.RETELL_MAX - 30) end
  return ns.Locale.fmt(T.retellTask, { text = task })
end

-- "Am Rande" ----------------------------------------------------------------------------------------------------------------

function RT.asideLongest(dur)
  if type(dur) ~= "string" or dur == "" then return nil end
  local s = ns.Locale.fmt(T.asideLongest, { dur = dur })
  return (gsub(s, "%.%.$", ".")) -- "10 Min." at the end: one full stop
end

function RT.asideWalk(km)
  km = tonumber(km)
  if not km or km < 1 then return nil end
  local tenth = floor(km * 10 + 0.5)
  local a, b = floor(tenth / 10), tenth % 10
  local txt = b == 0 and int(a) or ns.Locale.fmt(T.kmFmt, { a = int(a), b = b })
  return ns.Locale.fmt(T.asideWalk, { km = txt })
end

local function money(copper)
  copper = floor(tonumber(copper) or 0)
  local g, s, k = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
  if g > 0 then return ns.Locale.fmt(T.goldG, { g = int(g), s = s }) end
  if s > 0 then return ns.Locale.fmt(T.goldS, { s = s, k = k }) end
  return ns.Locale.fmt(T.goldK, { k = k })
end
RT.money = money

function RT.standLines(st)
  local lines = {}
  if type(st) ~= "table" or not st.level then return lines end
  if st.xpPct then
    lines[#lines + 1] = ns.Locale.fmt(T.standLevelPct, { level = floor(st.level), pct = floor(st.xpPct) })
  else
    lines[#lines + 1] = ns.Locale.fmt(T.standLevel, { level = floor(st.level) })
  end
  if st.zone then lines[#lines + 1] = ns.Locale.fmt(T.standZone, { zone = st.zone }) end
  if st.restedPct then lines[#lines + 1] = ns.Locale.fmt(T.standRested, { pct = floor(st.restedPct) }) end
  if st.gold and st.gold > 0 then lines[#lines + 1] = ns.Locale.fmt(T.standGold, { gold = money(st.gold) }) end
  return lines
end

function RT.openWerk(text)
  return ns.Locale.fmt(T.openWerk, { text = text })
end
function RT.trainerShort() return T.trainerShort end
function RT.medalText(title)
  return ns.Locale.fmt(T.hlMedal, { title = title })
end
