-- Evaluator for the Chronik page: profile, level flow, diary by day, XP sources, journey medals, forecast. Pure read
-- logic over the index and the character SV; the tiers for snapshots.medals are written by journal/Toast.lua
-- (Chronik.unsavedSteps).
-- Chronik.evaluate(index, opts) -> view; the expensive part is computed once per index (Chronik.static), each call only
-- the live parts. All view texts are display-ready.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Chronik = {}
Journal.Chronik = Chronik

local floor, huge, min, max = math.floor, math.huge, math.min, math.max
local format, find, match = string.format, string.find, string.match

Chronik.MAX_LEVEL = 60        -- WoW Forever and the fallback; the live value is Chronik.maxLevel()
Chronik.FORECAST_FROM = 10    -- forecast only from this level
Chronik.FORECAST_LEVELS = 5   -- last level durations that go into the extrapolation
Chronik.FACTOR_MIN, Chronik.FACTOR_MAX = 0.9, 1.08
Chronik.DIARY_MAX = 8000      -- diary entries (the newest are kept)
Chronik.LOOT_MIN_QUALITY = 3  -- finds in the diary from blue (green left out)
Chronik.NAME_MAX = 40         -- bytes for names in header and profile

-- highest player level of the client (Journal.MapSpace.maxLevel: Forever 60, Retail 80/90); fallback Chronik.MAX_LEVEL
function Chronik.maxLevel()
  local ms = Journal.MapSpace
  local v = ms and ms.maxLevel and ms.maxLevel() or nil
  return tonumber(v) or Chronik.MAX_LEVEL
end

-- locale scope "m.Chronik" (English in locales/enUS_model.lua); the catalogues (SOURCES, TIERS, FAMILIES, SEALS, EVENT_GROUPS)
-- read their labels on access (metatable), never at load
local Loc = ns.Locale
local TEXT = Loc.ns("m.Chronik", {
  unknown = "unbekannt",
  maxed = "Höchststufe erreicht",
  noXp = "Erfahrungsstand nicht lesbar",
  traveller = "Reisende/r",
  noFlow = "Noch keine Stufe abgeschlossen. Mit Stufe 2 wächst hier die erste Säule.",
  forecastTitle = "So weiter",
  forecastEarly = "Zu früh für eine Prognose",
  forecastNone = "Für eine Schätzung fehlen noch Stufen-Zeiten.",
  forecastDone = "Stufe %s ist erreicht. Die Reise geht trotzdem weiter.",
  src_quest = "Quests", src_kill = "Kills", src_explore = "Entdeckung", src_other = "Sonstiges",
  dm_first_blue = "das erste seltene Stück", dm_first_epic = "das erste epische Stück", dm_first_bag = "die erste Tasche",
  dm_mount = "das erste Reittier", dm_continent = "ein neuer Kontinent", dm_first_dungeon = "der erste Dungeon",
  dm_first_raid = "der erste Schlachtzug", dm_reputation = "eine neue Rufstufe", dm_profession = "ein Fortschritt im Handwerk",
  cls_elite = "Elite", cls_rare = "Rar", cls_rareelite = "Rar-Elite", cls_worldboss = "Boss",
  tier_bronze = "Bronze-Medaille", tierName_bronze = "Bronze",
  tier_silver = "Silber-Medaille", tierName_silver = "Silber",
  tier_gold = "Gold-Medaille", tierName_gold = "Gold",
  tier_legendary = "Legendäre Medaille", tierName_legendary = "Legendär",
  fam_travel = "Reise", fam_combat = "Kampf", fam_lore = "Quests & Wissen", fam_treasure = "Schätze", fam_fellows = "Gemeinschaft",
  fam_rest = "Rast", fam_survival = "Überleben", fam_instance = "Instanzen", fam_moments = "Momente",
  standing = { "Hasserfüllt", "Feindselig", "Unfreundlich", "Neutral", "Freundlich", "Wohlwollend", "Respektvoll", "Ehrfürchtig" },
  -- medals: title_/grid_/need_<id> (grid = label for the medal grid with manual hyphenation "-\n", words <=
  -- GRID_WORD_MAX characters), u_<id>_one/_other = threshold as text
  title_explorer = "Weltenbummler",
  grid_explorer = "Welten-\nbummler",
  need_explorer = "Verschiedene Gebiete betreten.",
  u_explorer_one = "%s Gebiet",
  u_explorer_other = "%s Gebiete",
  title_pathfinder = "Pfadfinder",
  grid_pathfinder = "Pfadfinder",
  need_pathfinder = "Neue Orte (Unterzonen) entdecken.",
  u_pathfinder_one = "%s Ort",
  u_pathfinder_other = "%s Orte",
  title_continent = "Jenseits des Meeres",
  grid_continent = "Jenseits des Meeres",
  need_continent = "Einen zweiten Kontinent betreten. Der Startkontinent zählt nicht.",
  title_flightmaster = "Flugmeister",
  grid_flightmaster = "Flugmeister",
  need_flightmaster = "Flugpunkte entdecken.",
  u_flightmaster_one = "%s Flugpunkt",
  u_flightmaster_other = "%s Flugpunkte",
  title_frequent_flyer = "Vielflieger",
  grid_frequent_flyer = "Vielflieger",
  need_frequent_flyer = "Mit einem Flugmeister fliegen.",
  u_frequent_flyer_one = "%s Flug",
  u_frequent_flyer_other = "%s Flüge",
  title_hunter = "Jäger",
  grid_hunter = "Jäger",
  need_hunter = "Gegner besiegen.",
  u_hunter_one = "%s Gegner",
  u_hunter_other = "%s Gegner",
  title_elite_hunter = "Elitejäger",
  grid_elite_hunter = "Elitejäger",
  need_elite_hunter = "Elite-Gegner besiegen.",
  u_elite_hunter_one = "%s Elite",
  u_elite_hunter_other = "%s Elite",
  title_rare_hunter = "Seltene Beute",
  grid_rare_hunter = "Seltene Beute",
  need_rare_hunter = "Seltene Gegner erlegen.",
  u_rare_hunter_one = "%s seltener Gegner",
  u_rare_hunter_other = "%s seltene Gegner",
  title_close_win = "Um Haaresbreite",
  grid_close_win = "Um Haares-\nbreite",
  need_close_win = "Kämpfe mit unter 10 % Leben überleben.",
  u_close_win_one = "%s Kampf",
  u_close_win_other = "%s Kämpfe",
  title_duel = "Ehrenhändel",
  grid_duel = "Ehrenhändel",
  need_duel = "Duelle gewinnen.",
  u_duel_one = "%s Duell",
  u_duel_other = "%s Duelle",
  title_quests = "Questbuch",
  grid_quests = "Questbuch",
  need_quests = "Quests abgeben.",
  u_quests_one = "%s Quest",
  u_quests_other = "%s Quests",
  title_reputation = "Freund der Fremden",
  grid_reputation = "Freund der Fremden",
  need_reputation = "Bei einer Fraktion eine hohe Rufstufe erreichen.",
  title_books = "Bibliothekar",
  grid_books = "Biblio-\nthekar",
  need_books = "Verschiedene Bücher oder Briefe mit mindestens zwei Seiten lesen. Schilder zählen nicht.",
  u_books_one = "%s Buch",
  u_books_other = "%s Bücher",
  title_profession = "Handwerker",
  grid_profession = "Handwerker",
  need_profession = "Einen Beruf meistern (bester Beruf zählt).",
  title_fortune = "Ein kleines Vermögen",
  grid_fortune = "Ein kleines Vermögen",
  need_fortune = "Viel Gold auf einmal besitzen (höchster Kontostand).",
  title_blue = "Blauer Schimmer",
  grid_blue = "Blauer Schimmer",
  need_blue = "Stücke der Güte Selten erbeuten oder erhalten.",
  u_blue_one = "%s seltenes Stück",
  u_blue_other = "%s seltene Stücke",
  title_epic = "Episches Stück",
  grid_epic = "Episches Stück",
  need_epic = "Ein episches Stück erbeuten oder anlegen.",
  title_angler = "Angler",
  grid_angler = "Angler",
  need_angler = "Fische angeln.",
  u_angler_one = "%s Fisch",
  u_angler_other = "%s Fische",
  title_gatherer = "Sammler",
  grid_gatherer = "Sammler",
  need_gatherer = "Erz, Kräuter oder Leder sammeln.",
  u_gatherer_one = "%s Stück",
  u_gatherer_other = "%s Stück",
  title_guild = "Im Bund",
  grid_guild = "Im Bund",
  need_guild = "Einer Gilde beitreten.",
  title_companions = "Weggefährten",
  grid_companions = "Weg-\ngefährten",
  need_companions = "Mit verschiedenen Mitspielern in einer Gruppe reisen.",
  u_companions_one = "%s Mitspieler",
  u_companions_other = "%s Mitspieler",
  title_social = "Gesellig",
  grid_social = "Gesellig",
  need_social = "Emotes benutzen.",
  u_social_one = "%s Emote",
  u_social_other = "%s Emotes",
  title_regular = "Stammgast",
  grid_regular = "Stammgast",
  need_regular = "Im Gasthaus oder in einer Stadt rasten.",
  u_regular_one = "%s Rast",
  u_regular_other = "%s Rasten",
  title_campfire = "Am Lagerfeuer",
  grid_campfire = "Am Lagerfeuer",
  need_campfire = "An einem Lagerfeuer rasten.",
  u_campfire_one = "%s Rast",
  u_campfire_other = "%s Rasten",
  title_rested = "Ausgeruht",
  grid_rested = "Ausgeruht",
  need_rested = "Erfahrung mit Ruhebonus sammeln.",
  title_hearth = "Heimkehr",
  grid_hearth = "Heimkehr",
  need_hearth = "Den Ruhestein benutzen.",
  u_hearth_one = "%s Heimkehr",
  u_hearth_other = "%s Heimkehren",
  title_tough = "Unverwüstlich",
  grid_tough = "Unver-\nwüstlich",
  need_tough = "Eine hohe Stufe erreichen, ohne oft gestorben zu sein.",
  title_flawless = "Ohne Fehltritt",
  grid_flawless = "Ohne Fehltritt",
  need_flawless = "Mehrere Stufen am Stück aufsteigen, ohne zu sterben.",
  u_flawless_one = "%s Stufe",
  u_flawless_other = "%s Stufen",
  title_unscathed = "Lange unverwundet",
  grid_unscathed = "Lange unverwundet",
  need_unscathed = "Lange am Stück spielen, ohne zu sterben (aktive Spielzeit).",
  title_dungeon = "Unter der Erde",
  grid_dungeon = "Unter der Erde",
  need_dungeon = "Verschiedene Dungeons betreten.",
  u_dungeon_one = "%s Dungeon",
  u_dungeon_other = "%s Dungeons",
  title_boss = "Bossbezwinger",
  grid_boss = "Boss-\nbezwinger",
  need_boss = "Verschiedene Bosse bezwingen (Dungeon-, Schlachtzugs- oder Weltboss).",
  u_boss_one = "%s Boss",
  u_boss_other = "%s Bosse",
  title_raid = "Der große Schlachtzug",
  grid_raid = "Der große Schlachtzug",
  need_raid = "Zum ersten Mal einen Schlachtzug betreten.",
  title_mount = "Auf vier Hufen",
  grid_mount = "Auf vier Hufen",
  need_mount = "Das erste Reittier lernen.",
  title_plans = "Eigene Wege",
  grid_plans = "Eigene Wege",
  need_plans = "Eigene Reiseziele erfüllen.",
  u_plans_one = "%s Reiseziel",
  u_plans_other = "%s Reiseziele",
  title_level60 = "Am Ziel der Reise",
  grid_level60 = "Am Ziel der Reise",
  need_level60 = "Stufe %s erreichen.",
  u_profession = "Fertigkeit %s",
  u_fortune = "%s Gold",
  u_rested = "%s EP",
  u_tough = "Stufe %s, höchstens %s Tode",
  date = "{d}.{m}.{y}, {H}:{M}",
  continents = "Kontinente: %s / %s",
  levelProgress = "Stufe %s / %s",
  toughProgress_one = "Bisher %s Tod · Stufe %s mit höchstens %s Toden bis %s",
  toughProgress_other = "Bisher %s Tode · Stufe %s mit höchstens %s Toden bis %s",
  progress = "%s / %s bis %s",
  repBest = "Beste Rufstufe: %s · %s bis %s",
  repBestAt = "Beste Rufstufe: %s bei %s · %s bis %s",
  repNone = "Noch keine Rufstufe erfasst · %s bis %s",
  flawlessRun = "%s (laufende Folge: %s)",
  unscathedNow = "%s (seit dem letzten Tod: %s)",
  earnedAt = "verdient am %s",
  earned = "verdient",
  evLevel = "Stufe %s",
  tierCount = "%s (%s von %s)",
  noStep = "Noch keine Stufe (0 von %s)",
  need = "Voraussetzung",
  allSteps = "Alle Stufen verdient",
  notEarned = "Noch nicht verdient",
  noMoreStep = "Keine weitere Stufe mehr erreichbar",
  sealCount = "%s von %s · %s von %s Stufen",
  sealTipTitle = "Medaillen der Reise",
  familyCount = "%s: %s von %s · %s von %s Stufen",
  pct = "%s %%",
  restedText = "davon Ruhebonus: %s EP",
  restedTip1 = "Ruhebonus",
  restedTip2 = "Ausgeruht gab es laut Spielmeldungen %s EP extra.",
  restedTip3 = "Ob dieser Bonus in den Anteilen oben schon steckt, verrät das Spiel leider nicht.",
  unclear_one = "%s Sprung über mehrere Stufen",
  unclear_other = "%s Sprünge über mehrere Stufen",
  unclearTip1 = "Mehrere Stufen auf einmal",
  unclearTip2 = "Hier kamen mehrere Stufen mit einem Schlag. Die Erfahrung dazwischen lässt sich keiner Quelle zuordnen und fehlt in den Anteilen.",
  diaryDay = "Aus dem Tagebuch · Tag %s",
  ev_combat = "Kämpfe und Kills",
  ev_quests = "Quests (angenommen, Ziele, abgegeben)",
  ev_loot = "Beute und Ausrüstung",
  ev_travel = "Orte und Reisen",
  ev_level = "Stufenaufstiege",
  ev_xp = "Erfahrung",
  ev_gold = "Gold",
  ev_trade = "Handel, Post und Auktionshaus",
  ev_death = "Tode und Wiederbelebung",
  ev_spells = "Zauber, Talente und Ruf",
  ev_group = "Gruppe und Gilde",
  ev_moments = "Momente, Bücher und Bilder",
  ev_other = "Sonstiges",
  evTitle = "Festgehaltene Ereignisse",
  evIntro = "Alles, was die Chronik seit Eurem ersten Login mitgeschrieben hat.",
  evTotal = "Zusammen: %s",
  evLine = "%s: %s",
  afkLine = "Insgesamt %s abwesend",
  afkTitle = "Abwesend (AFK)",
  afkIntro = "Zeit, in der Ihr als abwesend galt, von Hand per /afk oder von selbst nach einigen Minuten ohne Eingabe. Sie steckt in der Spielzeit.",
  afkTotal = "Insgesamt: %s",
  afkPhases_one = "%s Pause", afkPhases_other = "%s Pausen",
  afkLongest = "Längste Pause: %s",
  subtitleFaction = "%s der %s",
  sinceFmt = "%d.%m.%Y, %H:%M",
  approx = "ca. %s",
  head = "%s · %s · Stufe %s",
  xpLabel = "Auf dem Weg zu Stufe %s",
  restLeft = "heller Teil: noch %s Ruhe-EP übrig",
  restNone = "keine Ruhe-EP übrig",
  restSv = "%s (Stand der letzten Anmeldung)",
  colLevel = "Stufe %s",
  colLevelNow = "Stufe %s (läuft)",
  colDur = "Dauer: %s",
  colDurUnknown = "Dauer: nicht bekannt",
  deaths_one = "%s Tod",
  deaths_other = "%s Tode",
  over = "über %s Std.",
  forecastHead = "So weiter: Stufe %s in %s",
  forecastBody = "grobe Schätzung aus den letzten %s Stufen",
  fb_level = "Eine neue Stufe.", fb_quest = "Eine Quest abgegeben.", fb_loot = "Etwas Wertvolles erhalten.",
  fb_kill = "Ein besonderer Gegner fiel.", fb_close = "Ein knapper Sieg.", fb_death = "Gestorben.", fb_moment = "Ein Moment für die Chronik.",
  fb_campfire = "Am Lagerfeuer gerastet.", fb_zone = "Neues Land betreten.", fb_subzone = "Einen neuen Ort entdeckt.",
  fb_flight = "Einen Flugpunkt entdeckt.", fb_hearth = "Den Ruhestein neu gebunden.", fb_instance = "Eine Instanz betreten.",
  fb_encounter = "Einen Boss bezwungen.", fb_guild = "Etwas in Sachen Gilde.",
  probe = " (Probe)",
  quoted = "„%s“",
})
Chronik.TEXT = TEXT

-- look up a catalogue entry's label on read: fields = { field = function(entry) -> text }
local function lazy(entry, fields)
  return setmetatable(entry, { __index = function(t, k)
    local f = fields[k]
    if f then return f(t) end
  end })
end
Chronik.lazy = lazy

local SOURCES = {
  { key = "quest", color = "blue" },
  { key = "kill", color = "red" },
  { key = "explore", color = "treasure" },
  { key = "other", color = "sepia" },
}
for _, s in ipairs(SOURCES) do lazy(s, { label = function(t) return TEXT["src_" .. t.key] end }) end
Chronik.SOURCES = SOURCES

-- diary moment kinds (the other kinds already come via LV, KI, KF, DE, IB)
local DIARY_MOMENTS = { -- text: TEXT["dm_" .. kind]
  first_blue = true, first_epic = true, first_bag = true, mount = true, continent = true, first_dungeon = true,
  first_raid = true, reputation = true, profession = true,
}
local CLS_WORD = { elite = true, rare = true, rareelite = true, worldboss = true } -- text: TEXT["cls_" .. cls]

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function finite(v)
  return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local function S() return ns.Sanitize end
local function T() return Journal.Texts end
local function I() return Journal.Index end

local function display(v, n)
  local s = S()
  return s and s.display(v, n) or nil
end

local function int(n)
  local t = T()
  return t and t.int(n) or tostring(n)
end

-- entry of an SV table with a numeric key (Store.normKey stores numbers as numbers; falls back to text)
local function byId(tbl, id)
  if type(tbl) ~= "table" or id == nil then return nil end
  local v = tbl[id]
  if v == nil and type(id) == "number" then v = tbl[format("%.0f", id)] end
  return v
end

local function snapGroup(char, name)
  local s = type(char) == "table" and char.snapshots
  local g = type(s) == "table" and s[name]
  return type(g) == "table" and g or nil
end

local function nameIn(group, id)
  local e = byId(group, id)
  if type(e) == "table" then e = e.name end
  if type(e) ~= "string" or e == "" or isSecret(e) then return nil end
  return e
end

local function rawStr(v)
  if type(v) ~= "string" or v == "" or isSecret(v) then return nil end
  return v
end

local function posId(v) -- positive integer from field text or number
  if type(v) == "number" then
    if not finite(v) or v <= 0 or v ~= floor(v) or v >= 2147483648 then return nil end
    return v
  end
  if type(v) ~= "string" or not find(v, "^%d+$") or #v > 10 then return nil end
  local n = tonumber(v)
  if not n or n <= 0 or n >= 2147483648 then return nil end
  return n
end

function Chronik.duration(sec) -- via Fmt.duration ("6 Std. 27 Min.")
  sec = tonumber(sec)
  if not finite(sec) or sec < 0 then return TEXT.unknown end
  return ns.Journal.Fmt.duration(sec) or TEXT.unknown
end

-- "ca. 6 Std." for an estimated duration; below one minute the text itself already says "under 1 min", so no "ca."
function Chronik.approxText(text)
  local fmt = ns.Journal and ns.Journal.Fmt
  if fmt and text == fmt.duration(0) then return text end
  return TEXT("approx", text)
end
function Chronik.approxDuration(sec) return Chronik.approxText(Chronik.duration(sec)) end

-- local time of a moment by the index's time zone history (as Index.dayOf)
local function tzAt(index, t)
  local arr = type(index.tzT) == "table" and index.tzT or {}
  local lo, hi = 1, #arr
  if hi == 0 or arr[1] > t then return tonumber(index.tz0) or 0 end
  while lo < hi do
    local mid = floor((lo + hi + 1) / 2)
    if arr[mid] <= t then lo = mid else hi = mid - 1 end
  end
  return tonumber(index.tzV[lo]) or 0
end

local function clockOf(index, t)
  local s = (t + tzAt(index, t)) % 86400
  return format("%02d:%02d", floor(s / 3600), floor(s % 3600 / 60))
end

-- character level in a line (for KI, "level" is the enemy's level, the character's is in plevel)
local function levelOf(rec, code)
  local v = I().num(rec, code, code == "KI" and "plevel" or "level")
  if v and v >= 1 and v <= 200 then return floor(v) end
  return nil
end

-- times per level: reach[L] = seconds played when reaching L (PL: total - thisLevel), at[L] = epoch (LV)
local function levelTimes(index)
  local Idx = I()
  local reach, at = {}, {}
  for _, r in ipairs(Idx.list(index, "PL")) do
    local L = levelOf(r, "PL")
    local total, this = Idx.num(r, "PL", "total"), Idx.num(r, "PL", "thisLevel")
    if L and total and this and total >= 0 and this >= 0 and this <= total and reach[L] == nil then
      reach[L] = total - this
    end
  end
  for _, r in ipairs(Idx.list(index, "LV")) do
    local L = levelOf(r, "LV")
    if L and at[L] == nil and finite(r.t) then at[L] = r.t end
  end
  return reach, at
end

local function lastPlayed(index)
  local Idx = I()
  local list = Idx.list(index, "PL")
  for i = #list, 1, -1 do
    local total = Idx.num(list[i], "PL", "total")
    if total and total >= 0 and finite(list[i].t) then return total, list[i].t end
  end
  return nil
end

local function deathsByLevel(index)
  local by, noLevel, n = {}, 0, 0
  for _, r in ipairs(I().list(index, "DE")) do
    n = n + 1
    local L = levelOf(r, "DE")
    if L then by[L] = (by[L] or 0) + 1 else noLevel = noLevel + 1 end
  end
  return by, noLevel, n
end

-- medals: 35 medals in 9 families, 29 with three tiers (bronze -> silver -> gold), 6 one-off medals with a fixed tier;
-- 93 tiers in all.
-- No death medals: the "survival" family only rewards not dying. All thresholds live in Chronik.MEDAL_STEPS; earned
-- tiers stay (snapshots.medals).

-- medal tiers: tooltip label ("label"), short name ("name") and colour (r, g, b)
Chronik.TIER_ORDER = { "bronze", "silver", "gold" }
Chronik.TIERS = {
  bronze = { color = { 0.80, 0.50, 0.22 } },
  silver = { color = { 0.78, 0.83, 0.90 } },
  gold = { color = { 1.00, 0.82, 0.25 } },
  legendary = { color = { 1.00, 0.50, 0.10 } },
}
for id, t in pairs(Chronik.TIERS) do
  t.id = id
  lazy(t, { label = function(e) return TEXT["tier_" .. e.id] end, name = function(e) return TEXT["tierName_" .. e.id] end })
end
-- colours of the other tooltip lines (r, g, b)
Chronik.TIP_COLOR = {
  label = { 0.62, 0.58, 0.50 }, progress = { 1.00, 0.82, 0.30 }, earned = { 0.55, 0.85, 0.50 },
}

-- families in grid order; icon = character from Media/MomentIcons (Theme.MOMENT_ICONS) for the placeholder motif of new medals
Chronik.FAMILIES = {
  { id = "travel", icon = "place" },
  { id = "combat", icon = "fight" },
  { id = "lore", icon = "memory" },
  { id = "treasure", icon = "find" },
  { id = "fellows", icon = "level" },
  { id = "rest", icon = "memory" },
  { id = "survival", icon = "level" },
  { id = "instance", icon = "fight" },
  { id = "moments", icon = "level" },
}
for _, f in ipairs(Chronik.FAMILIES) do lazy(f, { label = function(e) return TEXT["fam_" .. e.id] end }) end

-- thresholds bronze / silver / gold per tiered medal (starting values, reference curve classic 1-60)
Chronik.MEDAL_STEPS = {
  explorer = { 6, 15, 26 },             -- distinct areas (ZN mapType 3)
  pathfinder = { 60, 180, 350 },        -- discovered subzones (SZ)
  flightmaster = { 5, 12, 20 },         -- discovered flight points (FP)
  frequent_flyer = { 10, 60, 150 },     -- flights (TF)
  hunter = { 1500, 5000, 9000 },        -- enemies defeated (kills.total)
  elite_hunter = { 25, 150, 400 },      -- elite enemies (KI elite/rareelite)
  rare_hunter = { 1, 5, 12 },           -- rare enemies (KI rare/rareelite)
  close_win = { 5, 20, 50 },            -- close wins (KF close)
  duel = { 1, 10, 30 },                 -- duels won (DU win)
  quests = { 75, 250, 500 },            -- quests turned in (QT)
  reputation = { 6, 7, 8 },             -- best standing: honored / revered / exalted
  books = { 3, 12, 30 },                -- distinct books/letters with at least two pages (BK)
  profession = { 150, 225, 300 },       -- best profession (skill)
  fortune = { 10, 100, 300 },           -- highest balance in gold (Index.RICH_STEPS)
  blue = { 1, 10, 25 },                 -- rare (blue) pieces (LT quality 3)
  angler = { 10, 100, 400 },            -- fish caught (counters.fishing)
  gatherer = { 100, 750, 2000 },        -- ore, herbs, leather gathered (counters.gather)
  companions = { 5, 25, 60 },           -- distinct fellow players (counters.mates)
  social = { 25, 150, 500 },            -- emotes (counters.emotes)
  regular = { 40, 150, 350 },           -- rests at inns / in cities (RA inn)
  campfire = { 3, 15, 50 },             -- rests at campfires (RA fire)
  rested = { 20000, 150000, 400000 },   -- rested XP (index.xp.rested)
  hearth = { 15, 60, 150 },             -- hearthstone uses (HS)
  tough = { 20, 40, 60 },               -- reach the level with at most Chronik.TOUGH_DEATHS[k] deaths until then
  flawless = { 3, 6, 10 },              -- levels in a row without dying (LV, DE)
  unscathed = { 3 * 3600, 8 * 3600, 16 * 3600 }, -- active play time in a row without dying (s)
  dungeon = { 1, 5, 10 },               -- distinct dungeons (IE party)
  boss = { 5, 25, 60 },                 -- distinct bosses (IB, MO boss, KI worldboss)
  plans = { 1, 5, 15 },                 -- own to-dos completed (VE)
}
Chronik.TOUGH_DEATHS = { 10, 25, 50 }  -- "tough": at most this many deaths until level 20 / 40 / 60
Chronik.CONTINENT_SEAL = 2             -- continents (the starting continent counts)
-- standing levels 1-8 (MO reputation detail): German source; Chronik.standingName(n) shows the active language
Chronik.STANDING = { "Hasserfüllt", "Feindselig", "Unfreundlich", "Neutral", "Freundlich", "Wohlwollend", "Respektvoll",
  "Ehrfürchtig" }

local function plain(n) return int(floor(n)) end
-- threshold as text: key u_<id>_one / u_<id>_other ("%s Gebiet" / "%s Gebiete")
local function unit(id)
  return function(n) return TEXT(Loc.plural(n, "u_" .. id .. "_one", "u_" .. id .. "_other"), plain(n)) end
end
function Chronik.standingName(n) return TEXT.standing[n] end
local function standing(n) return Chronik.standingName(n) or plain(n) end
local function hours(n) return Chronik.duration(n) end

-- catalogue (order = grid = cells of the future motif atlas Media/Seals.tga). id, title, family, need = requirement
-- sentence; steps = Chronik.MEDAL_STEPS entry, nil = one-off medal with fixed tier;
-- unit(n) / value(n) = threshold / counter as text; art = old image in the current atlas, nil = family placeholder
-- motif; live = counter without a log line (char.counters), read fresh on every call;
-- watch = prefilter for the observer (journal/Toast.lua): { code, test(F), value(F), always, elapsed, first }; F(name)
-- = field text
local M = Chronik.MEDAL_STEPS
local function fieldIs(name, ...)
  local want = { ... }
  return function(F)
    local v = F(name)
    for _, w in ipairs(want) do if v == w then return true end end
    return false
  end
end
local function fieldNum(name, scale)
  return function(F) local v = tonumber(F(name)) return v and v / (scale or 1) or nil end
end
local TICK = { "QT", "ZN", "SZ", "LV", "KF", "RA", "FP", "HS" } -- frequent but not massive lines (time medals)

-- grid (optional): label in the medal grid with manual hyphenation. A grid cell is about 62 px wide; a single word of
-- 12+ characters does not fit
-- and the client truncates it instead of wrapping ("Weltenbumm"). Hyphenate with "-\n".
Chronik.GRID_WORD_MAX = 11
Chronik.SEALS = {
  -- travel
  { id = "explorer", family = "travel", steps = M.explorer, unit = unit("explorer"),
    watch = { { code = "ZN", test = fieldIs("mapType", "3") } } },
  { id = "pathfinder", family = "travel", steps = M.pathfinder, unit = unit("pathfinder"),
    watch = { { code = "SZ" } } },
  { id = "continent", family = "travel", tier = "silver", art = "continent",
    watch = { { code = "MO", test = fieldIs("kind", "continent") } } },
  { id = "flightmaster", family = "travel", steps = M.flightmaster, unit = unit("flightmaster"),
    watch = { { code = "FP" } } },
  { id = "frequent_flyer", family = "travel", steps = M.frequent_flyer, unit = unit("frequent_flyer"),
    art = "first_flight", watch = { { code = "TF" } } },
  -- combat
  { id = "hunter", family = "combat", steps = M.hunter, unit = unit("hunter"),
    watch = { { code = "KI" } } },
  { id = "elite_hunter", family = "combat", steps = M.elite_hunter, unit = unit("elite_hunter"),
    watch = { { code = "KI", test = fieldIs("cls", "elite", "rareelite") } } },
  { id = "rare_hunter", family = "combat", steps = M.rare_hunter, art = "first_rare",
    unit = unit("rare_hunter"), watch = { { code = "KI", test = fieldIs("cls", "rare", "rareelite") } } },
  { id = "close_win", family = "combat", steps = M.close_win, art = "close_win",
    unit = unit("close_win"), watch = { { code = "KF", test = fieldIs("close", "1") } } },
  { id = "duel", family = "combat", steps = M.duel, art = "duel", unit = unit("duel"),
    watch = { { code = "DU", test = fieldIs("result", "win") } } },
  -- quests & lore
  { id = "quests", family = "lore", steps = M.quests, unit = unit("quests"),
    watch = { { code = "QT" } } },
  { id = "reputation", family = "lore", steps = M.reputation, art = "reputation",
    unit = standing, value = standing, watch = { { code = "MO", test = fieldIs("kind", "reputation"), value = fieldNum("detail") } } },
  { id = "books", family = "lore", steps = M.books, art = "first_book", unit = unit("books"),
    watch = { { code = "BK", test = function(F) return (tonumber(F("page")) or 0) >= 2 end } } },
  { id = "profession", family = "lore", steps = M.profession, art = "profession",
    unit = function(n) return TEXT("u_profession", plain(n)) end, watch = { { code = "SK", value = fieldNum("rank") }, { code = "MO", test = fieldIs("kind", "profession"), value = fieldNum("detail") } } },
  -- treasure
  { id = "fortune", family = "treasure", steps = M.fortune, art = "fortune",
    unit = function(n) return TEXT("u_fortune", plain(n)) end, watch = { { code = "GD", value = fieldNum("balance", 10000) } } },
  { id = "blue", family = "treasure", steps = M.blue, art = "first_blue",
    unit = unit("blue"), watch = { { code = "LT", test = fieldIs("quality", "3") }, { code = "MO", test = fieldIs("kind", "first_blue") } } },
  { id = "epic", family = "treasure", tier = "gold", art = "first_epic",
    watch = { { code = "LT", test = fieldIs("quality", "4", "5") }, { code = "MO", test = fieldIs("kind", "first_epic") } } },
  { id = "angler", family = "treasure", steps = M.angler, art = "first_fish", unit = unit("angler"),
    live = "fishing" },
  { id = "gatherer", family = "treasure", steps = M.gatherer, unit = unit("gatherer"),
    live = "gather" },
  -- fellows
  { id = "guild", family = "fellows", tier = "bronze", art = "guild", watch = { { code = "GU", test = fieldIs("action", "join", "seen", "change") } } },
  { id = "companions", family = "fellows", steps = M.companions,
    unit = unit("companions"), live = "mates" },
  { id = "social", family = "fellows", steps = M.social, unit = unit("social"),
    live = "emotes" },
  -- rest
  { id = "regular", family = "rest", steps = M.regular, unit = unit("regular"),
    watch = { { code = "RA", test = fieldIs("kind", "inn") } } },
  { id = "campfire", family = "rest", steps = M.campfire, unit = unit("campfire"),
    watch = { { code = "RA", test = fieldIs("kind", "fire") } } },
  { id = "rested", family = "rest", steps = M.rested, unit = function(n) return TEXT("u_rested", plain(n)) end,
    watch = { { code = "XP", test = function(F) return (tonumber(F("rested")) or 0) > 0 end,
      add = fieldNum("rested") } } },
  { id = "hearth", family = "rest", steps = M.hearth, art = "hearth", unit = unit("hearth"),
    watch = { { code = "HS" } } },
  -- survival (no death medals)
  { id = "tough", family = "survival", steps = M.tough,
    unit = function(n, k) return TEXT("u_tough", plain(n), plain(Chronik.TOUGH_DEATHS[k] or 0)) end,
    watch = { { code = "LV", value = fieldNum("level") } } },
  { id = "flawless", family = "survival", steps = M.flawless, unit = unit("flawless"),
    watch = { { code = "LV", value = fieldNum("level"), first = false } } },
  { id = "unscathed", family = "survival", steps = M.unscathed, unit = hours, value = hours,
    watch = { { codes = TICK, elapsed = true } } },
  -- instances
  { id = "dungeon", family = "instance", steps = M.dungeon, art = "first_dungeon",
    unit = unit("dungeon"), watch = { { code = "IE", test = fieldIs("type", "party") } } },
  { id = "boss", family = "instance", steps = M.boss, art = "boss", unit = unit("boss"),
    watch = { { code = "IB", test = fieldIs("success", "1") }, { code = "KI", test = fieldIs("cls", "worldboss") },
      { code = "MO", test = fieldIs("kind", "boss") } } },
  { id = "raid", family = "instance", tier = "gold", art = "first_raid",
    watch = { { code = "IE", test = fieldIs("type", "raid") } } },
  -- moments
  { id = "mount", family = "moments", tier = "gold", art = "mount", watch = { { code = "MO", test = fieldIs("kind", "mount") } } },
  { id = "plans", family = "moments", steps = M.plans, unit = unit("plans"),
    watch = { { code = "VE" } } },
  { id = "level60", family = "moments", tier = "legendary", art = "level60",
    watch = { { code = "LV", value = fieldNum("level") }, { code = "PL", value = fieldNum("level") } } },
}
-- name, grid label (only if it differs from the name) and requirement in the active language
local SEAL_TEXT = {
  title = function(s) return TEXT["title_" .. s.id] end,
  need = function(s)
    if s.id == "level60" then return TEXT("need_level60", int(Chronik.maxLevel())) end
    return TEXT["need_" .. s.id]
  end,
  grid = function(s)
    local g, t = TEXT["grid_" .. s.id], TEXT["title_" .. s.id]
    if g ~= t then return g end
  end,
}
Chronik.SEAL_BY_ID = {}
for i, s in ipairs(Chronik.SEALS) do
  s.index = i
  Chronik.SEAL_BY_ID[s.id] = s
  lazy(s, SEAL_TEXT)
end

-- medal evaluation: per medal a counter value and per tier a proof { t, level, zone } (each field may be missing; {} =
-- earned without a time, e.g. pure counters).
-- The index part is computed once per index (medalCache); live counters and saved tiers (snapshots.medals) are added
-- cheaply on every call.

Chronik.ZONE_MAX = 40 -- bytes for a place name in the tooltip

-- calendar date to "days since 1970-01-01" (civil calendar, as date("!%d.%m.%Y") without depending on os/date)
local function civil(z)
  z = z + 719468
  local era = floor(z / 146097)
  local doe = z - era * 146097
  local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
  local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
  local mp = floor((5 * doy + 2) / 153)
  local d = doy - floor((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  local y = yoe + era * 400
  if m <= 2 then y = y + 1 end
  return y, m, d
end

-- "27.10.2026, 21:14" in the character's local time (time zone history of the index); nil for an unusable time
local function dateText(index, t)
  if not finite(t) or t < 0 or t > 4102444800 then return nil end
  local loc = t + tzAt(index, t)
  local y, m, d = civil(floor(loc / 86400))
  local s = loc % 86400
  return TEXT("date", { d = format("%02d", d), m = format("%02d", m), y = format("%04d", y), H = format("%02d", floor(s / 3600)),
    M = format("%02d", floor(s % 3600 / 60)) })
end

Chronik.dateText = dateText -- for tests

local function validLevel(L)
  L = tonumber(L)
  if finite(L) and L >= 1 and L <= 200 then return floor(L) end
  return nil
end

local function bsearchLE(arr, v) -- largest index i with arr[i] <= v, 0 if none
  local lo, hi = 1, #arr
  if hi == 0 or not (arr[1] <= v) then return 0 end
  while lo < hi do
    local mid = floor((lo + hi + 1) / 2)
    if arr[mid] <= v then lo = mid else hi = mid - 1 end
  end
  return lo
end

-- sum of the counters of a group (counters[group]); count = true: number of keys with a value > 0 (distinct fellow players)
local LIVE_COUNT = { mates = true }
local function counterValue(char, group)
  local c = type(char) == "table" and type(char.counters) == "table" and char.counters[group] or nil
  if type(c) ~= "table" then return 0 end
  local n = 0
  for _, v in pairs(c) do
    if type(v) == "number" and finite(v) and v > 0 then n = n + (LIVE_COUNT[group] and 1 or v) end
  end
  return floor(n)
end

-- counter value of a medal without a log line (fishing, gathering, emotes, fellows) straight from the SV; nil for other medals.
-- Cheap (one loop over the counter group): the observer checks it on rest, zone change and combat end.
function Chronik.counterValue(id, char)
  local s = Chronik.SEAL_BY_ID[id]
  if not s or not s.live then return nil end
  return counterValue(char, s.live)
end

-- field text as Index.str (empty and "?" = nil), for direct r[pos] access in hot loops
local function fieldText(v)
  if type(v) ~= "string" or v == "" or v == "?" then return nil end
  return v
end

-- shared helpers of an evaluation (once per index)
local function medalCtx(index, char)
  local Idx = I()
  local C = { index = index, char = char, Idx = Idx }
  local maps = snapGroup(char, "maps")
  local lvT, lvL, lvRec = {}, {}, {}
  for _, r in ipairs(Idx.list(index, "LV")) do
    local L = levelOf(r, "LV")
    if L and finite(r.t) then lvT[#lvT + 1], lvL[#lvL + 1], lvRec[#lvRec + 1] = r.t, L, r end
  end
  C.lvT, C.lvL, C.lvRec = lvT, lvL, lvRec
  -- level at time t from the level-ups (before the first LV: one below); unknown without LV lines
  function C.levelAt(t)
    if not finite(t) or #lvT == 0 then return nil end
    local i = bsearchLE(lvT, t)
    if i == 0 then return lvL[1] > 1 and lvL[1] - 1 or nil end
    return lvL[i]
  end
  local function zoneOf(r, code)
    local sub = rawStr(Idx.str(r, code, "sub"))
    if sub then return sub end
    local m = posId(Idx.str(r, code, "mapID"))
    return m and nameIn(maps, m) or nil
  end
  function C.hit(r, code)
    return { t = r.t, level = levelOf(r, code) or C.levelAt(r.t), zone = zoneOf(r, code) }
  end
  function C.at(t) return { t = t, level = C.levelAt(t) } end
  function C.list(code) return Idx.list(index, code) end
  function C.filter(code, test)
    local out = {}
    for _, r in ipairs(Idx.list(index, code)) do
      if not test or test(r) then out[#out + 1] = r end
    end
    return out
  end
  -- first line per key (distinct areas, dungeons, books ...), in log order
  function C.distinct(code, keyOf)
    local out, seen = {}, {}
    for _, r in ipairs(Idx.list(index, code)) do
      local k = keyOf(r)
      if k ~= nil and not seen[k] then
        seen[k] = true
        out[#out + 1] = r
      end
    end
    return out
  end
  function C.str(r, code, name) return Idx.str(r, code, name) end
  function C.num(r, code, name) return Idx.num(r, code, name) end
  -- field position of a code (nil if unknown). Hot loops over long lists (LT, KI, MO, ZN) read r[pos] directly instead of C.str:
  -- saves three function calls per line (first-build performance).
  function C.pos(code, name)
    local f = Idx.fields(code)
    return f and f[name] or nil
  end
  -- MO lines per kind (one pass), KI lines per class (one pass): several medals read the same lists
  local moKind = {}
  local moK = C.pos("MO", "kind")
  for _, r in ipairs(moK and Idx.list(index, "MO") or {}) do
    local k = fieldText(r[moK])
    if k then
      local l = moKind[k]
      if not l then
        l = {}
        moKind[k] = l
      end
      l[#l + 1] = r
    end
  end
  function C.moList(kind) return moKind[kind] or {} end
  -- first MO line of a kind (optionally with detail >= min)
  function C.mo(kind, min_)
    for _, r in ipairs(moKind[kind] or {}) do
      if not min_ then return r end
      local d = Idx.num(r, "MO", "detail")
      if d and d >= min_ then return r end
    end
    return nil
  end
  local kiCls = {}
  local kiC = C.pos("KI", "cls")
  for _, r in ipairs(kiC and Idx.list(index, "KI") or {}) do
    local c = fieldText(r[kiC])
    if c then
      local l = kiCls[c]
      if not l then
        l = {}
        kiCls[c] = l
      end
      l[#l + 1] = r
    end
  end
  -- KI lines of the classes (log order across classes by line number)
  function C.ki(a, b)
    local la, lb = kiCls[a] or {}, b and kiCls[b] or {}
    if #lb == 0 then return la end
    local out, i, j = {}, 1, 1
    while i <= #la or j <= #lb do
      local x, y = la[i], lb[j]
      if y == nil or (x ~= nil and (x.ln or 0) <= (y.ln or 0)) then
        out[#out + 1] = x
        i = i + 1
      else
        out[#out + 1] = y
        j = j + 1
      end
    end
    return out
  end
  local moments = snapGroup(char, "moments") or {}
  function C.snap(kind) -- snapshots.moments[kind] (first time, without place)
    local e = moments[kind]
    if type(e) ~= "table" or e.seen ~= true then return nil end
    return { t = tonumber(e.at), level = validLevel(e.level) }
  end
  return C
end

-- proofs of a counting medal: tier k is earned when value >= steps[k]; proof = the steps[k]-th record (else {})
local function byRecords(C, steps, value, recs, code)
  local earned = {}
  for k, need in ipairs(steps) do
    if value >= need then
      local r = recs and recs[need]
      earned[k] = r and C.hit(r, code) or {}
    end
  end
  return earned
end

local function byTimes(C, steps, value, times)
  local earned = {}
  for k, need in ipairs(steps) do
    if value >= need then
      local t = times and times[need]
      earned[k] = finite(t) and C.at(t) or {}
    end
  end
  return earned
end

local function countOf(code, test) -- medal = number of lines of a code (optionally filtered: test(C, r))
  return function(C, steps)
    local recs = C.filter(code, test and function(r) return test(C, r) end or nil)
    return #recs, byRecords(C, steps, #recs, recs, code)
  end
end

local function bestDetail(C, kind)
  local best
  for _, r in ipairs(C.moList(kind)) do
    local d = C.num(r, "MO", "detail")
    if d and (not best or d > best) then best = d end
  end
  return best
end

local function onceOf(ev) return ev and 1 or 0, { ev } end

-- evaluation per medal: (C, steps) -> value, earned (earned[k] = proof of tier k or nil; one-off medals only k = 1)
local EVAL = {}

EVAL.explorer = function(C, steps)
  local pT, pM = C.pos("ZN", "mapType"), C.pos("ZN", "mapID")
  local recs, seen = {}, {}
  if pT and pM then
    for _, r in ipairs(C.list("ZN")) do
      if r[pT] == "3" then
        local k = posId(fieldText(r[pM]))
        if k and not seen[k] then
          seen[k] = true
          recs[#recs + 1] = r
        end
      end
    end
  end
  return #recs, byRecords(C, steps, #recs, recs, "ZN")
end
EVAL.pathfinder = countOf("SZ")
EVAL.flightmaster = countOf("FP")
EVAL.frequent_flyer = countOf("TF")
EVAL.hunter = function(C, steps)
  local k = type(C.index.kills) == "table" and C.index.kills or {}
  local value = finite(k.total) and k.total or 0
  local ks = C.index.killSeries
  local earned = {}
  for i, need in ipairs(steps) do
    if value >= need then
      local ev = {}
      if type(ks) == "table" and type(ks.c) == "table" then
        for j = 1, #ks.c do
          if ks.c[j] >= need then
            ev = C.at(ks.b[j] * ks.size + ks.size - 1) -- end of the minute in which the threshold fell
            break
          end
        end
      end
      earned[i] = ev
    end
  end
  return value, earned
end
EVAL.elite_hunter = function(C, steps)
  local recs = C.ki("elite", "rareelite")
  local stamp = type(C.index.kills) == "table" and type(C.index.kills.stamp) == "table" and C.index.kills.stamp.elite or 0
  local value = math.max(#recs, finite(stamp) and stamp or 0)
  return value, byRecords(C, steps, value, recs, "KI")
end
EVAL.rare_hunter = function(C, steps)
  local recs = C.ki("rare", "rareelite")
  local stamp = type(C.index.kills) == "table" and type(C.index.kills.stamp) == "table" and C.index.kills.stamp.rare or 0
  local value = math.max(#recs, finite(stamp) and stamp or 0)
  return value, byRecords(C, steps, value, recs, "KI")
end
EVAL.close_win = countOf("KF") -- index.lists.KF holds only close wins (close = 1)
EVAL.duel = countOf("DU", function(C, r) return C.str(r, "DU", "result") == "win" end)
EVAL.quests = countOf("QT")
EVAL.reputation = function(C, steps)
  local best = bestDetail(C, "reputation") or 0
  local earned = {}
  for k, need in ipairs(steps) do
    local r = C.mo("reputation", need)
    if r then earned[k] = C.hit(r, "MO") end
  end
  return best, earned
end
EVAL.books = function(C, steps)
  local recs = C.distinct("BK", function(r)
    local p = C.num(r, "BK", "page")
    if not p or p < 2 then return nil end
    return C.str(r, "BK", "key")
  end)
  return #recs, byRecords(C, steps, #recs, recs, "BK")
end
EVAL.profession = function(C, steps)
  local value = bestDetail(C, "profession") or 0
  for _, e in pairs(type(C.index.skills) == "table" and C.index.skills or {}) do
    if type(e) == "table" and finite(e.rank) and e.rank > value then value = e.rank end
  end
  local earned = {}
  for k, need in ipairs(steps) do
    local r = C.mo("profession", need)
    if r then earned[k] = C.hit(r, "MO") elseif value >= need then earned[k] = {} end
  end
  return floor(value), earned
end
EVAL.fortune = function(C, steps)
  local peak = type(C.index.money) == "table" and C.index.money.peak
  local value = (type(peak) == "table" and finite(peak.balance) and peak.balance > 0) and floor(peak.balance / 10000) or 0
  local gd = C.list("GD")
  local earned = {}
  for k, need in ipairs(steps) do
    if value >= need then
      local ev = {}
      for _, r in ipairs(gd) do
        local b = C.num(r, "GD", "balance")
        if b and b >= need * 10000 then
          ev = C.hit(r, "GD")
          break
        end
      end
      earned[k] = ev
    end
  end
  return value, earned
end
-- quality of an LT line: field quality, else snapshots.items[itemID].quality (old data without quality); nil = unknown
local function lootQuality(r, pQ, pI, items)
  local qs = fieldText(r[pQ])
  local q = qs and tonumber(qs) or nil
  if q == nil and pI then
    local key = fieldText(r[pI])
    local snap = key and byId(items, posId(match(key, "^(%d+)")))
    q = type(snap) == "table" and tonumber(snap.quality) or nil
  end
  return q
end

EVAL.blue = function(C, steps)
  local items = snapGroup(C.char, "items")
  local pQ, pI = C.pos("LT", "quality"), C.pos("LT", "item")
  local recs = {}
  if pQ then
    for _, r in ipairs(C.list("LT")) do
      -- hot path (thousands of finds): text "3" without detour, otherwise number or fallback to the item snapshot
      if r[pQ] == "3" or (r[pQ] ~= "2" and lootQuality(r, pQ, pI, items) == 3) then recs[#recs + 1] = r end
    end
  end
  local value = #recs
  local earned = byRecords(C, steps, value, recs, "LT")
  if value == 0 then -- old data: moment "first rare piece" without an LT line
    local mo = C.mo("first_blue")
    local ev = mo and C.hit(mo, "MO") or C.snap("first_blue")
    if ev then value, earned[1] = 1, ev end
  end
  return value, earned
end
EVAL.epic = function(C)
  local mo = C.mo("first_epic")
  if mo then return onceOf(C.hit(mo, "MO")) end
  local pQ = C.pos("LT", "quality")
  for _, r in ipairs(pQ and C.list("LT") or {}) do -- the first line of epic or better is enough (breaks)
    local q = tonumber(fieldText(r[pQ]))
    if finite(q) and q >= 4 then return onceOf(C.hit(r, "LT")) end
  end
  return onceOf(C.snap("first_epic"))
end
EVAL.guild = function(C)
  local r = C.filter("GU", function(x)
    local a = C.str(x, "GU", "action")
    return a == "join" or a == "seen" or a == "change"
  end)[1]
  return onceOf(r and C.hit(r, "GU") or nil)
end
EVAL.regular = function(C, steps)
  local times = type(C.index.restInnT) == "table" and C.index.restInnT or {}
  return #times, byTimes(C, steps, #times, times)
end
EVAL.campfire = function(C, steps)
  local times = type(C.index.restFireT) == "table" and C.index.restFireT or {}
  return #times, byTimes(C, steps, #times, times)
end
EVAL.rested = function(C, steps)
  local x = type(C.index.xp) == "table" and C.index.xp.rested
  local value = (finite(x) and x > 0) and floor(x) or 0
  return value, byTimes(C, steps, value, nil)
end
EVAL.hearth = countOf("HS")
-- tough: level steps[k] reached with at most TOUGH_DEATHS[k] deaths until then (each level on its own)
EVAL.tough = function(C, steps)
  local deathT = {}
  for _, r in ipairs(C.list("DE")) do if finite(r.t) then deathT[#deathT + 1] = r.t end end
  table.sort(deathT)
  local earned = {}
  for k, L in ipairs(steps) do
    for i, lv in ipairs(C.lvL) do
      if lv >= L then
        local before = bsearchLE(deathT, C.lvT[i] - 0.001)
        if before <= (Chronik.TOUGH_DEATHS[k] or 0) then earned[k] = C.hit(C.lvRec[i], "LV") end
        break
      end
    end
  end
  C.toughDeaths = #deathT
  return C.lvL[#C.lvL] or 1, earned
end
-- flawless: longest run of whole levels without dying (after a death only the next full level counts)
EVAL.flawless = function(C, steps)
  local ev = {}
  for i, t in ipairs(C.lvT) do ev[#ev + 1] = { t = t, lv = i } end
  for _, r in ipairs(C.list("DE")) do if finite(r.t) then ev[#ev + 1] = { t = r.t, de = true, ln = r.ln } end end
  table.sort(ev, function(a, b)
    if a.t ~= b.t then return a.t < b.t end
    return (a.de and 0 or 1) < (b.de and 0 or 1) -- same second: the death first (the level after it does not count fully)
  end)
  local run, best, clean, top = 0, 0, true, 0
  local earned = {}
  for _, e in ipairs(ev) do
    if e.de then
      run, clean = 0, false
    elseif C.lvL[e.lv] <= top then
      -- same level again (duplicate LV line): does not count
    elseif clean then
      run = run + 1
      if run > best then
        best = run
        for k, need in ipairs(steps) do
          if not earned[k] and run >= need then earned[k] = C.hit(C.lvRec[e.lv], "LV") end
        end
      end
    else
      clean = true
    end
    if e.lv and C.lvL[e.lv] > top then top = C.lvL[e.lv] end
  end
  C.flawlessRun, C.flawlessTop = run, top
  return best, earned
end
-- unscathed: longest active play time between two deaths (or since the start, up to the last line)
EVAL.unscathed = function(C, steps)
  local Idx, index = C.Idx, C.index
  local bounds = {}
  local start = finite(index.startT) and index.startT or index.firstT
  if not finite(start) then return 0, {} end
  bounds[1] = start
  for _, r in ipairs(C.list("DE")) do if finite(r.t) and r.t >= start then bounds[#bounds + 1] = r.t end end
  table.sort(bounds)
  local stop = finite(index.lastT) and index.lastT or start
  bounds[#bounds + 1] = math.max(stop, bounds[#bounds])
  local best = 0
  local earned = {}
  for i = 1, #bounds - 1 do
    local a, b = bounds[i], bounds[i + 1]
    local len = (Idx.activeSeconds(index, a, b)) or 0
    if len > best then best = len end
    for k, need in ipairs(steps) do
      if not earned[k] and len >= need then
        local lo, hi = a, b -- smallest time t with active time [a, t] >= need (active time grows with t)
        for _ = 1, 40 do
          if hi - lo <= 30 then break end
          local mid = floor((lo + hi) / 2)
          if ((Idx.activeSeconds(index, a, mid)) or 0) >= need then hi = mid else lo = mid end
        end
        earned[k] = C.at(hi)
      end
    end
  end
  C.unscathedNow = (Idx.activeSeconds(index, bounds[#bounds - 1], bounds[#bounds])) or 0
  return floor(best), earned
end
EVAL.dungeon = function(C, steps)
  local recs = C.distinct("IE", function(r)
    if C.str(r, "IE", "type") ~= "party" then return nil end
    return posId(C.str(r, "IE", "instanceID")) or C.str(r, "IE", "instanceID")
  end)
  return #recs, byRecords(C, steps, #recs, recs, "IE")
end
-- boss: distinct encounters (IB success, MO boss = encounterID) and world bosses (KI worldboss, npcID), by time
EVAL.boss = function(C, steps)
  local hits, seen = {}, {}
  local function add(key, r, code)
    if key and not seen[key] then
      seen[key] = true
      hits[#hits + 1] = C.hit(r, code)
    end
  end
  for _, r in ipairs(C.list("IB")) do
    if C.str(r, "IB", "success") == "1" then add("e" .. tostring(C.str(r, "IB", "encounterID")), r, "IB") end
  end
  for _, r in ipairs(C.moList("boss")) do add("e" .. tostring(C.str(r, "MO", "value")), r, "MO") end
  for _, r in ipairs(C.ki("worldboss")) do add("n" .. tostring(C.str(r, "KI", "npcID")), r, "KI") end
  table.sort(hits, function(a, b) return (finite(a.t) and a.t or 0) < (finite(b.t) and b.t or 0) end)
  local earned = {}
  for k, need in ipairs(steps) do
    if #hits >= need then earned[k] = hits[need] end
  end
  return #hits, earned
end
EVAL.raid = function(C)
  local r = C.filter("IE", function(x) return C.str(x, "IE", "type") == "raid" end)[1]
  if r then return onceOf(C.hit(r, "IE")) end
  local mo = C.mo("first_raid")
  return onceOf(mo and C.hit(mo, "MO") or C.snap("first_raid"))
end
EVAL.mount = function(C)
  local mo = C.mo("mount")
  return onceOf(mo and C.hit(mo, "MO") or C.snap("mount"))
end
EVAL.plans = countOf("VE")
-- continent: the first recorded continent is the start, earned at the second (MO continent or snapshots)
EVAL.continent = function(C)
  local n = 0
  for _, r in ipairs(C.moList("continent")) do
    n = n + 1
    if n == Chronik.CONTINENT_SEAL then return onceOf(C.hit(r, "MO")) end
  end
  local c, seen = snapGroup(C.char, "continents"), 0
  if c then
    for _, v in pairs(c) do if type(v) == "table" then seen = seen + 1 end end
  end
  C.continents = math.max(n, seen)
  if seen >= Chronik.CONTINENT_SEAL then return onceOf({}) end
  return onceOf(nil)
end
EVAL.level60 = function(C)
  local top = Chronik.maxLevel()
  local function first(code)
    for _, r in ipairs(C.list(code)) do
      local L = levelOf(r, code)
      if L and L >= top then return C.hit(r, code) end
    end
  end
  return onceOf(first("LV") or first("PL"))
end
-- counter without a log line: value from char.counters, no time (the date comes from snapshots.medals)
local function liveEval(C, steps, seal)
  local value = counterValue(C.char, seal.live)
  return value, byTimes(C, steps, value, nil)
end

-- tiered medals: tier k from a monotonic counter (for distribution test and prefilter); tough does not count
function Chronik.stepsFor(id, value)
  local s = Chronik.SEAL_BY_ID[id]
  if not s or not s.steps or id == "tough" then return nil end
  local n = 0
  for _, need in ipairs(s.steps) do if (tonumber(value) or 0) >= need then n = n + 1 end end
  return n
end

local function stepTiers(seal) return seal.steps and Chronik.TIER_ORDER or { seal.tier } end

-- progress of one-off medals (only where countable and reliably available)
local ONCE_PROGRESS = {
  continent = function(C)
    local n = C.continents or 0
    if n < 1 then return nil end
    return TEXT("continents", int(min(n, Chronik.CONTINENT_SEAL)), int(Chronik.CONTINENT_SEAL))
  end,
}

local function levelProgress(level)
  local top = Chronik.maxLevel()
  return TEXT("levelProgress", int(min(floor(level), top)), int(top))
end

-- faction of the best standing (MO reputation value = factionID or name), display-ready | nil
local function bestFaction(C)
  local best, rec
  for _, r in ipairs(C.list("MO")) do
    if C.str(r, "MO", "kind") == "reputation" then
      local d = C.num(r, "MO", "detail")
      if d and d >= 1 and d <= #Chronik.STANDING and d == floor(d) and (not best or d > best) then best, rec = d, r end -- 8 standing levels
    end
  end
  if not rec then return nil end
  local value = C.str(rec, "MO", "value")
  local id = posId(value)
  local faction = id and nameIn(snapGroup(C.char, "factions"), id) or (not id and rawStr(value)) or nil
  return display(faction, Chronik.NAME_MAX)
end

-- progress line of a tiered medal towards the next open tier k
local function stepProgress(seal, C, value, k)
  local tierName = Chronik.TIERS[Chronik.TIER_ORDER[k]].name
  local need = seal.steps[k]
  if seal.id == "tough" then
    local d = C.toughDeaths or 0
    return TEXT(Loc.plural(d, "toughProgress_one", "toughProgress_other"), int(d), int(need), int(Chronik.TOUGH_DEATHS[k]), tierName)
  end
  local fmt = seal.value or plain
  local shown = min(value or 0, need)
  local line = TEXT("progress", fmt(shown), fmt(need), tierName)
  if seal.id == "reputation" then
    local faction = bestFaction(C)
    if (value or 0) >= 1 then
      if faction then
        line = TEXT("repBestAt", standing(value), faction, standing(need), tierName)
      else
        line = TEXT("repBest", standing(value), standing(need), tierName)
      end
    else
      line = TEXT("repNone", standing(need), tierName)
    end
  elseif seal.id == "flawless" and (C.flawlessRun or 0) > 0 and C.flawlessRun < (value or 0) then
    line = TEXT("flawlessRun", line, plain(C.flawlessRun))
  elseif seal.id == "unscathed" and (C.unscathedNow or 0) > 0 and (C.unscathedNow or 0) < (value or 0) then
    line = TEXT("unscathedNow", line, hours(C.unscathedNow))
  end
  return line
end

local function evidenceText(s)
  local parts = { s.when and TEXT("earnedAt", s.when) or TEXT.earned }
  if s.level then parts[#parts + 1] = TEXT("evLevel", int(s.level)) end
  if s.zone then parts[#parts + 1] = s.zone end
  return table.concat(parts, " · ")
end

-- tooltip: name, tier ("Silber-Medaille (2 von 3)"), "Voraussetzung", sentence, then per tier threshold and proof
-- (earned = green),
-- progress "312 / 500 bis Gold" or "Alle Stufen verdient". One-off medals: proof, progress or "Noch nicht verdient".
local function sealTip(seal, e)
  local CT = Chronik.TIP_COLOR
  local lines, colors = { seal.title }, {}
  if seal.steps then
    local top = e.tier and Chronik.TIERS[e.tier]
    if top then
      lines[2], colors[2] = TEXT("tierCount", top.label, int(e.count), int(#seal.steps)), top.color
    else
      lines[2], colors[2] = TEXT("noStep", int(#seal.steps)), CT.label
    end
  else
    local tier = Chronik.TIERS[seal.tier] or Chronik.TIERS.bronze
    lines[2], colors[2] = tier.label, tier.color
  end
  lines[3], colors[3] = TEXT.need, CT.label
  lines[4] = seal.need
  if seal.steps then
    for k, need in ipairs(seal.steps) do
      local tierName = Chronik.TIERS[Chronik.TIER_ORDER[k]].name
      local s = e.steps[k]
      local line = tierName .. " " .. (seal.unit and seal.unit(need, k) or plain(need))
      if s then line = line .. ": " .. evidenceText(s) end
      lines[#lines + 1] = line
      colors[#lines] = s and CT.earned or CT.label
    end
    if e.progress then
      lines[#lines + 1] = e.progress
      colors[#lines] = CT.progress
    elseif e.count >= #seal.steps then
      lines[#lines + 1] = TEXT.allSteps
      colors[#lines] = CT.earned
    end
  else
    local s = e.steps[1]
    if s then
      local text = evidenceText(s)
      lines[5], colors[5] = string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2), CT.earned
    elseif e.progress then
      lines[5], colors[5] = e.progress, CT.progress
    else
      lines[5] = TEXT.notEarned
    end
  end
  return lines, colors
end

-- entry of a medal from counter, proofs and saved tiers (snapshots.medals["<id>:<tier>"] = { t, level })
local function sealEntry(seal, C, value, earned, saved)
  local index = C.index
  local tiers = stepTiers(seal)
  local e = { id = seal.id, title = seal.title, family = seal.family, stepped = seal.steps ~= nil, max = #tiers,
    value = value, steps = {}, count = 0 }
  local top
  for k, tierName in ipairs(tiers) do
    local ev = earned[k]
    local p = saved and saved[seal.id .. ":" .. tierName]
    p = type(p) == "table" and p or nil
    if not ev and p then ev = { t = tonumber(p.t), level = p.level } end           -- earned once stays earned
    if ev and not finite(ev.t) and p and finite(tonumber(p.t)) then             -- date from the saved state
      ev = { t = tonumber(p.t), level = ev.level or p.level, zone = ev.zone }
    end
    if ev then
      local s = { tier = tierName, k = k, at = finite(ev.t) and ev.t or nil, level = validLevel(ev.level),
        zone = display(ev.zone, Chronik.ZONE_MAX) }
      s.when = s.at and dateText(index, s.at) or nil
      e.steps[k] = s
      e.count = e.count + 1
      top = s
    end
  end
  e.broken = e.count > 0
  if top then
    e.tier, e.at, e.when, e.level, e.zone = top.tier, top.at, top.when, top.level, top.zone
  elseif not seal.steps then
    e.tier = seal.tier
  end
  if seal.steps then
    for k in ipairs(seal.steps) do
      local reachable = not (seal.id == "tough" and (C.toughDeaths or 0) > (Chronik.TOUGH_DEATHS[k] or 0))
      if not e.steps[k] and reachable then
        e.nextK, e.nextTier, e.nextNeed = k, Chronik.TIER_ORDER[k], seal.steps[k]
        e.progress = stepProgress(seal, C, value, k)
        -- time medal: the running stretch since the last death counts (observer prefilter)
        if seal.id == "unscathed" then e.left = seal.steps[k] - (C.unscathedNow or 0) end
        -- levels in a row: the running run counts (every LV line can extend it)
        if seal.id == "flawless" then
          e.left = seal.steps[k] - (C.flawlessRun or 0)
          -- only an LV line of this level can complete the run (without LV lines: counted from level 1)
          e.watchNext = math.max(C.flawlessTop or 0, 1) + e.left
        end
        break
      end
    end
    if not e.nextK and e.count < #seal.steps then e.progress = TEXT.noMoreStep end
  elseif not top and ONCE_PROGRESS[seal.id] then
    e.progress = ONCE_PROGRESS[seal.id](C)
  end
  e.tip, e.tipColors = sealTip(seal, e)
  return e
end

-- index part of the evaluation (once per index): counters and proofs of all medals except the live counters
local medalCache = setmetatable({}, { __mode = "k" })

local function medalBase(index)
  local base = medalCache[index]
  if base then return base end
  local char = type(index.char) == "table" and index.char or {}
  local C = medalCtx(index, char)
  base = { C = C, value = {}, earned = {} }
  for _, seal in ipairs(Chronik.SEALS) do
    if not seal.live then
      local fn = EVAL[seal.id]
      local v, earned = 0, {}
      if fn then v, earned = fn(C, seal.steps, seal) end
      base.value[seal.id], base.earned[seal.id] = v or 0, earned or {}
    end
  end
  medalCache[index] = base
  return base
end

local function savedMedals(char)
  local g = snapGroup(char, "medals")
  local n = 0
  if g then for _ in pairs(g) do n = n + 1 end end
  return g, n
end

-- full list: { broken, total, steps, stepsTotal, list, families = { { id, label, broken, total, steps, stepsTotal } }
-- }. Same inputs -> the same table (cached).
local function buildSeals(index)
  local base = medalBase(index)
  local C = base.C
  local char = C.char
  local saved, nSaved = savedMedals(char)
  local live, sig = {}, { tostring(nSaved) }
  for _, seal in ipairs(Chronik.SEALS) do
    if seal.live then
      live[seal.id] = counterValue(char, seal.live)
      sig[#sig + 1] = live[seal.id]
    end
  end
  sig = table.concat(sig, ":")
  if base.result and base.sig == sig then return base.result end
  local out, broken, steps, stepsTotal = {}, 0, 0, 0
  local fam = {}
  for _, f in ipairs(Chronik.FAMILIES) do fam[f.id] = { id = f.id, label = f.label, broken = 0, total = 0, steps = 0, stepsTotal = 0 } end
  for i, seal in ipairs(Chronik.SEALS) do
    local v, earned
    if seal.live then
      v, earned = liveEval(C, seal.steps, seal)
    else
      v, earned = base.value[seal.id], base.earned[seal.id]
    end
    local e = sealEntry(seal, C, v, earned, saved)
    out[i] = e
    local f = fam[seal.family]
    if e.broken then broken = broken + 1 end
    steps, stepsTotal = steps + e.count, stepsTotal + e.max
    if f then
      f.total, f.steps, f.stepsTotal = f.total + 1, f.steps + e.count, f.stepsTotal + e.max
      if e.broken then f.broken = f.broken + 1 end
    end
  end
  local families = {}
  for _, f in ipairs(Chronik.FAMILIES) do families[#families + 1] = fam[f.id] end
  local res = { broken = broken, total = #Chronik.SEALS, steps = steps, stepsTotal = stepsTotal, list = out, families = families }
  res.countText = TEXT("sealCount", int(broken), int(#Chronik.SEALS), int(steps), int(stepsTotal))
  local tip, colors = { TEXT.sealTipTitle, res.countText }, { [2] = Chronik.TIP_COLOR.label }
  for _, f in ipairs(families) do
    tip[#tip + 1] = TEXT("familyCount", f.label, int(f.broken), int(f.total), int(f.steps), int(f.stepsTotal))
  end
  res.countTip, res.countTipColors = tip, colors
  base.result, base.sig = res, sig
  return res
end

-- the list with the running level for "Am Ziel der Reise" (one entry is replaced, the rest stays shared)
local function liveSeals(seals, level)
  local seal = Chronik.SEAL_BY_ID.level60
  local i = seal and seal.index
  local cur = i and seals.list[i]
  if not cur or cur.broken then return seals end
  local e = {}
  for k, v in pairs(cur) do e[k] = v end
  e.progress = levelProgress(level)
  e.tip, e.tipColors = sealTip(seal, e)
  local list = {}
  for j, x in ipairs(seals.list) do list[j] = x end
  list[i] = e
  local out = {}
  for k, v in pairs(seals) do out[k] = v end
  out.list = list
  return out
end

-- tiers not yet saved: { { key = "<id>:<tier>", t, level }, ... } for snapshots.medals. t only if known (proof from the
-- log) or now is set
-- (reached live, after the baseline); level then from opts.level.
function Chronik.unsavedSteps(seals, char, opts)
  local out = {}
  if type(seals) ~= "table" or type(seals.list) ~= "table" then return out end
  opts = type(opts) == "table" and opts or {}
  local saved = snapGroup(char, "medals") or {}
  for _, e in ipairs(seals.list) do
    for _, s in pairs(e.steps or {}) do
      local key = e.id .. ":" .. s.tier
      if saved[key] == nil then
        local t, level = s.at, s.level
        if not t and finite(opts.now) then t, level = opts.now, level or validLevel(opts.level) end
        out[#out + 1] = { key = key, t = t, level = level }
      end
    end
  end
  return out
end

local function buildSources(index)
  local x = type(index.xp) == "table" and index.xp or { total = 0, source = {}, rested = 0, unclear = 0 }
  local total = 0
  local amounts = {}
  for _, s in ipairs(SOURCES) do
    local e = x.source and x.source[s.key]
    local a = (type(e) == "table" and finite(e.amount) and e.amount > 0) and e.amount or 0
    amounts[s.key] = a
    total = total + a
  end
  local parts = {}
  for _, s in ipairs(SOURCES) do
    local a = amounts[s.key]
    if a > 0 then
      local pct = a / total * 100
      parts[#parts + 1] = { key = s.key, label = s.label, color = s.color, amount = a, pct = pct,
        pctText = TEXT("pct", int(floor(pct + 0.5))) }
    end
  end
  local function short(n) return ns.Journal.Fmt.big(n) end -- "4,79 Mio." instead of "4 790 k"
  local rested = (finite(x.rested) and x.rested > 0) and x.rested or 0
  local unclear = (finite(x.unclear) and x.unclear > 0) and x.unclear or 0
  return {
    total = total, totalText = short(total), parts = parts, rested = rested,
    -- short line for the page, the explanation is in the tooltip (restedTip/unclearTip)
    restedText = rested > 0 and TEXT("restedText", short(rested)) or nil,
    restedTip = rested > 0 and { TEXT.restedTip1, TEXT("restedTip2", short(rested)), TEXT.restedTip3 } or nil,
    unclear = unclear,
    unclearText = unclear > 0 and TEXT(Loc.plural(unclear, "unclear_one", "unclear_other"), int(unclear)) or nil,
    unclearTip = unclear > 0 and { TEXT.unclearTip1, TEXT.unclearTip2 } or nil,
  }
end

-- origin of a find (LT.source): only loot window sources are "found", the rest get their own sentences
local LOOT_HOW = {
  mob = "found", object = "found", container = "found", fishing = "found",
  vendor = "bought", quest = "reward", craft = "crafted", mail = "mail", trade = "trade", ah = "ah",
}

-- diary: events from the lists, by day. Sentences are built only when shown (Chronik.entryText).
local function buildDiary(index, char, flowDur)
  local Idx = I()
  local maps, items = snapGroup(char, "maps"), snapGroup(char, "items")
  local instances, encounters = snapGroup(char, "instances"), snapGroup(char, "encounters")
  local npcs, quests = type(char.npcs) == "table" and char.npcs or nil, type(char.quests) == "table" and char.quests or nil
  local function zone(rec, code)
    local m = posId(Idx.str(rec, code, "mapID"))
    return m and nameIn(maps, m) or nil
  end
  local function npc(id)
    local n = byId(npcs, id)
    return rawStr(n)
  end
  local list = {}
  -- tie-break within the same second: running line number of the index (rec.ln, across all codes); without it the list order
  local function add(r, kind, ctx)
    local t = r.t
    if not finite(t) then return end
    ctx.kind = kind
    list[#list + 1] = { t = t, kind = kind, ctx = ctx, seq = finite(r.ln) and r.ln or #list }
  end

  for _, r in ipairs(Idx.list(index, "LV")) do
    local L = levelOf(r, "LV")
    if L then
      local d = flowDur[L - 1]
      add(r, "level", { level = L, zone = rawStr(Idx.str(r, "LV", "sub")) or zone(r, "LV"),
        dur = d and Chronik.duration(d) or nil, milestone = (L % 10 == 0) or nil })
    end
  end
  for _, r in ipairs(Idx.list(index, "QT")) do
    local q = posId(Idx.str(r, "QT", "questID"))
    local e = q and byId(quests, q)
    local xp = Idx.num(r, "QT", "xp")
    add(r, "quest", { title = type(e) == "table" and rawStr(e.title) or nil, xp = (xp and xp > 0) and xp or nil })
  end
  -- finds: most lines are green (quality "2") and drop out anyway. They are skipped before any other work (first-build
  -- performance:
  -- thousands of LT lines); lines without quality still use the snapshot.
  local ltQ = (Idx.fields("LT") or {}).quality
  for _, r in ipairs(Idx.list(index, "LT")) do
    local q, key, snap
    if not (ltQ and r[ltQ] == "2") then
      key = Idx.str(r, "LT", "item")
      local id = key and posId(match(key, "^(%d+)"))
      snap = id and byId(items, id)
      q = Idx.num(r, "LT", "quality")
      if q == nil and type(snap) == "table" then q = tonumber(snap.quality) end
    end
    if q and q >= Chronik.LOOT_MIN_QUALITY then
      local name = type(snap) == "table" and rawStr(snap.name) or nil
      local src = Idx.str(r, "LT", "source")
      local how = LOOT_HOW[src or ""] or "other"
      local from
      if src == "mob" then from = npc(posId(Idx.str(r, "LT", "srcID"))) end
      -- link = item string for the original tooltip (Texts.itemString, only checked numbers from the key)
      if name then
        add(r, "loot", { item = name, from = from, epic = (q >= 4) or nil, how = how,
          link = Journal.Texts and Journal.Texts.itemString(key) or nil })
      end
    end
  end
  for _, r in ipairs(Idx.list(index, "KI")) do -- index.lists.KI: elite, rare, boss only
    local cls = Idx.str(r, "KI", "cls")
    local word = (CLS_WORD[cls] and TEXT["cls_" .. cls]) or ((Idx.num(r, "KI", "level") == -1) and TEXT.cls_worldboss) or nil
    local name = npc(posId(Idx.str(r, "KI", "npcID"))) or rawStr(Idx.str(r, "KI", "name"))
    if word then add(r, "kill", { cls = word, npc = name, rare = (cls == "rare" or cls == "rareelite") or nil }) end
  end
  for _, r in ipairs(Idx.list(index, "KF")) do -- close wins only
    local hp = Idx.num(r, "KF", "hpEnd")
    add(r, "close", { hp = (hp and hp >= 0 and hp <= 100) and floor(hp + 0.5) or nil })
  end
  for _, r in ipairs(Idx.list(index, "DE")) do
    add(r, "death", { zone = rawStr(Idx.str(r, "DE", "sub")) or zone(r, "DE") })
  end
  local skipStartContinent = true -- the starting continent is no news (the medal still counts it)
  for _, r in ipairs(Idx.list(index, "MO")) do
    local kind = Idx.str(r, "MO", "kind")
    local what = kind and DIARY_MOMENTS[kind] and TEXT["dm_" .. kind]
    if kind == "continent" and skipStartContinent then
      skipStartContinent = false
    elseif what then add(r, "moment", { what = what, zone = rawStr(Idx.str(r, "MO", "sub")) or zone(r, "MO") }) end
  end
  -- campfire rounds (LF): "Am Lagerfeuer in <zone> mit A, B (n)"; who/again are display-ready, people (raw values) only
  -- for the tooltip
  local FM = Journal.FireMates
  for _, rd in ipairs(FM and FM.rounds(index) or {}) do
    add({ t = rd.t, ln = rd.ln }, "campfire", { zone = rd.zone, who = FM.who(rd), again = FM.again(rd, "ihr"),
      people = FM.tipPeople(rd), n = rd.n, seconds = rd.seconds, sim = rd.sim })
  end
  local skipStartZone = true -- the starting zone is no news either
  for _, r in ipairs(Idx.list(index, "ZN")) do
    if Idx.str(r, "ZN", "mapType") == "3" then
      local name = zone(r, "ZN")
      if skipStartZone then
        skipStartZone = false
      elseif name then add(r, "zone", { zone = name }) end
    end
  end
  for _, r in ipairs(Idx.list(index, "SZ")) do
    local name = rawStr(Idx.str(r, "SZ", "name"))
    if name then add(r, "subzone", { name = name }) end
  end
  for _, r in ipairs(Idx.list(index, "FP")) do
    add(r, "flight", { npc = npc(posId(Idx.str(r, "FP", "npcID"))) or rawStr(Idx.str(r, "FP", "name")),
      zone = zone(r, "FP") })
  end
  for _, r in ipairs(Idx.list(index, "HB")) do
    add(r, "hearth", { bind = rawStr(Idx.str(r, "HB", "bind")) })
  end
  for _, r in ipairs(Idx.list(index, "IE")) do
    if Idx.str(r, "IE", "resumed") ~= "1" then
      add(r, "instance", { inst = nameIn(instances, posId(Idx.str(r, "IE", "instanceID"))),
        raid = (Idx.str(r, "IE", "type") == "raid") or nil })
    end
  end
  for _, r in ipairs(Idx.list(index, "IB")) do
    if Idx.str(r, "IB", "success") == "1" then
      add(r, "encounter", { enc = nameIn(encounters, posId(Idx.str(r, "IB", "encounterID"))) })
    end
  end
  for _, r in ipairs(Idx.list(index, "GU")) do
    local a = Idx.str(r, "GU", "action")
    if a == "join" or a == "change" or a == "leave" then
      add(r, "guild", { guild = rawStr(Idx.str(r, "GU", "guild")), leave = (a == "leave") or nil })
    end
  end

  table.sort(list, function(a, b)
    if a.t ~= b.t then return a.t < b.t end
    return a.seq < b.seq
  end)
  local truncated = false
  if #list > Chronik.DIARY_MAX then
    local keep = {}
    for i = #list - Chronik.DIARY_MAX + 1, #list do keep[#keep + 1] = list[i] end
    list, truncated = keep, true
  end
  local days, byDay = {}, {}
  for _, e in ipairs(list) do
    local d = Idx.dayOf(index, e.t)
    local bucket = byDay[d]
    if not bucket then
      bucket = { day = d, title = TEXT("diaryDay", int(d)), entries = {} }
      byDay[d] = bucket
      days[#days + 1] = bucket
    end
    e.clock = clockOf(index, e.t)
    e.key = e.kind .. ":" .. format("%.0f", e.t) .. ":" .. e.seq
    bucket.entries[#bucket.entries + 1] = e
    e.bucket = bucket
  end
  -- newest first: reverse once per day (append and flip instead of inserting at the front, which would be O(n^2))
  for _, b in ipairs(days) do
    local en = b.entries
    for i = 1, floor(#en / 2) do en[i], en[#en - i + 1] = en[#en - i + 1], en[i] end
  end
  table.sort(days, function(a, b) return a.day < b.day end)
  return { days = days, count = #list, truncated = truncated }
end

local function buildStatic(index)
  local char = type(index.char) == "table" and index.char or {}
  local reach, at = levelTimes(index)
  -- duration of completed levels: reach[L+1] - reach[L]; otherwise active time between the level-ups
  local dur, approx = {}, {}
  local top = 0
  for L in pairs(reach) do if L > top then top = L end end
  for L in pairs(at) do if L > top then top = L end end
  -- play time counts from character creation: level 1 starts at 0 (same time base as the PL differences)
  if reach[1] == nil and reach[2] ~= nil then reach[1] = 0 end
  for L = 1, top - 1 do
    local d
    if reach[L] and reach[L + 1] then
      d = reach[L + 1] - reach[L]
    else
      local t0 = (L == 1) and index.startT or at[L]
      local t1 = at[L + 1]
      if finite(t0) and finite(t1) and t1 > t0 then d = (I().activeSeconds(index, t0, t1)) end
      if d then approx[L] = true end -- no /played answer: active time from the log only, the tooltip shows "ca."
    end
    if d and finite(d) and d >= 0 then dur[L] = d end
  end
  local deaths, deathsNoLevel, deathsTotal = deathsByLevel(index)
  local st = {
    char = char, reach = reach, at = at, dur = dur, approx = approx, top = top,
    deaths = deaths, deathsNoLevel = deathsNoLevel, deathsTotal = deathsTotal,
    sources = buildSources(index),
  }
  st.diary = buildDiary(index, char, dur)
  return st
end

local cache = setmetatable({}, { __mode = "k" })

function Chronik.static(index)
  local st = cache[index]
  if not st then
    st = buildStatic(index)
    cache[index] = st
  end
  return st
end

-- medals of one index only (same evaluation as view.seals, without diary/flow/sources): for the moment toast
-- (journal/Toast.lua) and the days.
-- Index part computed once per index; live counters and saved tiers (snapshots.medals) are added on every call (same
-- state -> same table).
function Chronik.sealsOf(index)
  if type(index) ~= "table" then return nil end
  return buildSeals(index)
end

local function median(arr)
  local c = {}
  for i, v in ipairs(arr) do c[i] = v end
  table.sort(c)
  local n = #c
  if n == 0 then return nil end
  if n % 2 == 1 then return c[(n + 1) / 2] end
  return (c[n / 2] + c[n / 2 + 1]) / 2
end

function Chronik.project(durations, level, progress, maxLevel)
  maxLevel = tonumber(maxLevel) or Chronik.maxLevel()
  level = tonumber(level)
  if type(durations) ~= "table" or not finite(level) or level < 1 or level >= maxLevel then return nil end
  local d = {}
  for _, v in ipairs(durations) do
    if finite(v) and v > 0 then d[#d + 1] = v end
  end
  if #d == 0 then return nil end
  local ratios = {}
  for i = 2, #d do ratios[#ratios + 1] = d[i] / d[i - 1] end
  local f = median(ratios) or 1
  if not finite(f) then f = 1 end
  f = max(Chronik.FACTOR_MIN, min(Chronik.FACTOR_MAX, f))
  progress = tonumber(progress)
  if not finite(progress) or progress < 0 then progress = 0 end
  local est = d[#d] * f
  local remaining = est - progress
  if remaining < est * 0.05 then remaining = est * 0.05 end -- the running level still costs something
  local series = { remaining }
  for _ = floor(level) + 1, maxLevel - 1 do
    est = est * f
    remaining = remaining + est
    series[#series + 1] = remaining
  end
  return remaining, series, f
end

local function sessionCount(db, guid)
  local meta = type(db) == "table" and type(db.meta) == "table" and db.meta or nil
  local list = meta and type(meta.sessions) == "table" and meta.sessions or nil
  if not list then return 0 end
  local n = 0
  for _, s in ipairs(list) do
    if type(s) == "table" and s.guid == guid then n = n + 1 end
  end
  return n
end

local function lastRS(index)
  local Idx = I()
  local list = Idx.list(index, "RS")
  local r = list[#list]
  if not r then return nil end
  return { xp = Idx.num(r, "RS", "xp"), xpMax = Idx.num(r, "RS", "xpMax"), rested = Idx.num(r, "RS", "rested"),
    level = levelOf(r, "RS") }
end

-- "recorded events" (profile.entries = number of raw log lines): breakdown by kind for the tooltip, counted from
-- index.counts (lines per code; display time only).
-- Every known code belongs to exactly one group; everything else (new/unknown codes, session lines, played queries)
-- lands in "Sonstiges".
Chronik.EVENT_GROUPS = {
  { id = "combat", codes = { "KI", "KF", "PK", "DU" } },
  { id = "quests", codes = { "QA", "QO", "QT", "QR", "QX" } },
  { id = "loot", codes = { "LT", "GW" } },
  { id = "travel", codes = { "ZN", "SZ", "EX", "FP", "TP", "TF", "TL", "HS", "HB", "TB", "IE", "IL", "IB", "GI" } },
  { id = "level", codes = { "LV" } },
  { id = "xp", codes = { "XP", "RS" } },
  { id = "gold", codes = { "GD" } },
  { id = "trade", codes = { "TH", "PM", "PS", "AH" } },
  { id = "death", codes = { "DE", "DR", "DC", "DB", "PD" } },
  { id = "spells", codes = { "SP", "TA", "SK", "RP", "RT" } },
  { id = "group", codes = { "GS", "GM", "GL", "GE", "GU" } },
  { id = "moments", codes = { "MO", "BK", "SH" } },
}
for _, g in ipairs(Chronik.EVENT_GROUPS) do lazy(g, { label = function(e) return TEXT["ev_" .. e.id] end }) end
-- "Sonstiges" in the active language (Chronik.EVENT_OTHER reads it on access)
setmetatable(Chronik, { __index = function(_, k) if k == "EVENT_OTHER" then return TEXT.ev_other end end })

-- -> lines, colors (tooltip lines, colour per line as Widgets.tip). Broken/missing index: total only.
local function eventTip(index, total)
  local lines = { TEXT.evTitle, TEXT.evIntro }
  local colors = { [1] = { 1, 0.95, 0.85 }, [2] = { 0.62, 0.58, 0.5 } }
  local counts = type(index) == "table" and type(index.counts) == "table" and index.counts or nil
  local function cnt(code)
    local v = counts and counts[code]
    if type(v) ~= "number" or not finite(v) or v < 0 then return 0 end
    return floor(v)
  end
  if counts then
    local known = 0
    for _, g in ipairs(Chronik.EVENT_GROUPS) do
      local n = 0
      for _, code in ipairs(g.codes) do n = n + cnt(code) end
      known = known + n
      if n > 0 then lines[#lines + 1] = TEXT("evLine", g.label, int(n)) end
    end
    -- rest: all other counted codes plus lines without a known code (index.lines counts everything)
    local all = 0
    for _, v in pairs(counts) do
      if type(v) == "number" and finite(v) and v > 0 then all = all + floor(v) end
    end
    local lineN = tonumber(index.lines)
    if finite(lineN) and lineN > all then all = floor(lineN) end
    local rest = all - known
    if rest > 0 then lines[#lines + 1] = TEXT("evLine", TEXT.ev_other, int(rest)) end
  end
  lines[#lines + 1] = TEXT("evTotal", int(total))
  colors[#lines] = { 1, 0.95, 0.85 }
  return lines, colors
end

-- Away time (AFK) of a character from its SV: counters.afk = { seconds, phases } and snapshots.state.afk = { since, seen, longest },
-- written by collectors/Afk.lua. An open phase counts live while its heartbeat ('seen') is fresh (the collector marks it every
-- minute; a stale mark means a crash or another character). -> { seconds, phases, longest, open } | nil without any away time.
Chronik.AFK_LIVE = 150       -- seconds: how old the heartbeat of an open phase may be to count it
Chronik.AFK_MIN_SHOWN = 60   -- seconds: the page shows the line from this total
function Chronik.afk(char, now)
  if type(char) ~= "table" or isSecret(char) then return nil end
  local function nn(v)
    if isSecret(v) or not finite(v) or v < 0 then return nil end
    return v
  end
  local c = type(char.counters) == "table" and char.counters.afk or nil
  local snaps = type(char.snapshots) == "table" and char.snapshots.state or nil
  local s = type(snaps) == "table" and snaps.afk or nil
  if type(c) ~= "table" or isSecret(c) then c = {} end
  if type(s) ~= "table" or isSecret(s) then s = {} end
  local seconds, phases, longest = nn(c.seconds) or 0, nn(c.phases) or 0, nn(s.longest) or 0
  local open = 0
  local since, seen = nn(s.since), nn(s.seen)
  now = tonumber(now)
  if since and seen and finite(now) and now >= since and now - seen <= Chronik.AFK_LIVE then open = floor(now - since) end
  seconds = floor(seconds + open)
  if open > longest then longest = open end
  if seconds <= 0 then return nil end
  return { seconds = seconds, phases = floor(phases) + (open > 0 and 1 or 0), longest = floor(longest), open = open }
end

-- view of the away time for the profile: text (nil below AFK_MIN_SHOWN) and tooltip lines + colours
local function afkOf(char, now)
  local a = Chronik.afk(char, now)
  if not a then return nil end
  a.text = a.seconds >= Chronik.AFK_MIN_SHOWN and TEXT("afkLine", Chronik.duration(a.seconds)) or nil
  local lines = { TEXT.afkTitle, TEXT.afkIntro, TEXT("afkTotal", Chronik.duration(a.seconds)) }
  if a.phases > 0 then lines[#lines + 1] = TEXT(Loc.plural(a.phases, "afkPhases_one", "afkPhases_other"), int(a.phases)) end
  if a.longest > 0 then lines[#lines + 1] = TEXT("afkLongest", Chronik.duration(a.longest)) end
  a.tip = lines
  a.tipColors = { [1] = { 1, 0.95, 0.85 }, [2] = { 0.62, 0.58, 0.5 } }
  return a
end

local function profileOf(index, st, level, playedSec, exact, db, now)
  local Texts = T()
  local info = type(st.char.info) == "table" and st.char.info or {}
  local name = display(info.name, Chronik.NAME_MAX) or TEXT.traveller
  local race, class = display(info.race, Chronik.NAME_MAX), display(info.class, Chronik.NAME_MAX)
  local faction = display(info.factionName, Chronik.NAME_MAX)
  local parts = {}
  if race then parts[#parts + 1] = race end
  if class then parts[#parts + 1] = class end
  local subtitle = table.concat(parts, " ")
  if faction and subtitle ~= "" then subtitle = TEXT("subtitleFaction", subtitle, faction) end
  local seed = Texts and Texts.seed(info.firstSeen) or "0"
  local raceFile = type(info.raceFile) == "string" and not isSecret(info.raceFile) and info.raceFile or ""
  local motto = Texts and Texts.pick("motto", { raceFile = raceFile }, seed, "motto", {}) or nil
  local first = tonumber(info.firstSeen)
  local since = TEXT.unknown
  if finite(first) and first > 0 and type(date) == "function" then
    local ok, s = pcall(date, TEXT.sinceFmt, first)
    if ok and type(s) == "string" then since = s end
  end
  local entries = tonumber(st.char.lineCount)
  entries = finite(entries) and entries >= 0 and entries or (index.lines or 0)
  local tip, tipColors = eventTip(index, entries)
  -- average per play day: total play time / number of calendar days with play time (Days.list); unknown without play time or days
  local perDay, dayCount = TEXT.unknown, 0
  if finite(playedSec) then
    if st.playDays == nil then -- once per index (Days.list computes every day)
      st.playDays = 0
      if Journal.Days and type(Journal.Days.list) == "function" then
        local ok, list = pcall(Journal.Days.list, index)
        if ok and type(list) == "table" then st.playDays = #list end
      end
    end
    if st.playDays > 0 then
      dayCount = st.playDays
      perDay = Chronik.duration(playedSec / dayCount)
    end
  end
  return {
    name = name, subtitle = subtitle, motto = motto and TEXT("quoted", motto) or nil, level = level,
    maxLevel = Chronik.maxLevel(), since = since,
    played = playedSec and (exact and Chronik.duration(playedSec) or Chronik.approxDuration(playedSec)) or TEXT.unknown,
    playedSec = playedSec, playedExact = exact, sessions = sessionCount(db, index.guid), perDay = perDay, playDays = dayCount,
    entries = entries, entriesTip = tip, entriesTipColors = tipColors, afk = afkOf(st.char, now),
    head = TEXT("head", name, class or race or "", int(level)),
  }
end

local function xpOf(index, live, level)
  local out = { level = level, nextLevel = level + 1 }
  if level >= Chronik.maxLevel() then
    out.maxed, out.label, out.pct, out.pctText = true, TEXT.maxed, 1, ""
    return out
  end
  local cur, mx, rested
  if live and live.xp then cur, mx = live.xp() end
  if cur and mx then
    out.source = "live"
    rested = live.rested and live.rested() or nil
  else
    local rs = lastRS(index)
    if rs and rs.xp and rs.xpMax and rs.xpMax > 0 and rs.level == level then
      cur, mx, rested, out.source = rs.xp, rs.xpMax, rs.rested, "sv"
    end
  end
  out.label = TEXT("xpLabel", int(level + 1))
  if not cur or not mx or mx <= 0 then
    out.pctText, out.restText = "", TEXT.noXp
    return out
  end
  local pct = max(0, min(1, cur / mx))
  out.cur, out.max, out.pct = cur, mx, pct
  out.pctText = TEXT("pct", int(floor(pct * 100)))
  if rested and finite(rested) and rested > 0 then
    out.rested = rested
    out.restText = TEXT("restLeft", int(rested))
  else
    out.restText = TEXT.restNone
  end
  if out.source == "sv" then out.restText = TEXT("restSv", out.restText) end
  return out
end

local function flowOf(index, st, level, playedSec, now, texts)
  local Idx = I()
  local cols = {}
  -- running level: time played since reaching it
  local curDur
  if playedSec and st.reach[level] then
    curDur = playedSec - st.reach[level]
  elseif st.at[level] or level == 1 then
    local t0 = st.at[level] or index.startT
    if finite(t0) and now > t0 then curDur = (Idx.activeSeconds(index, t0, now)) end
  end
  if curDur and (not finite(curDur) or curDur < 0) then curDur = nil end
  local first = max(1, level - 59)
  local fastL, slowL, complete = nil, nil, 0
  for L = first, level - 1 do
    local d = st.dur[L]
    if d then
      complete = complete + 1
      if not fastL or d < st.dur[fastL] then fastL = L end
      if not slowL or d > st.dur[slowL] then slowL = L end
    end
  end
  local total, deaths = 0, 0
  local top = 0
  for L = first, level do
    local d = (L == level) and curDur or st.dur[L]
    local n = st.deaths[L] or 0
    deaths = deaths + n
    if d then total = total + d end
    if d and d > top then top = d end
    local col = { level = L, value = d or 0, known = d ~= nil, deaths = n, mark = n > 0, current = L == level,
      fastest = L == fastL, slowest = L == slowL and slowL ~= fastL }
    col.color = col.current and "red" or ((col.fastest or col.slowest) and "gold" or "ink")
    local tip = { TEXT(col.current and "colLevelNow" or "colLevel", int(L)) }
    local durText = d and Chronik.duration(d)
    if d and st.approx[L] and not col.current then durText = Chronik.approxText(durText) end
    tip[#tip + 1] = d and TEXT("colDur", durText) or TEXT.colDurUnknown
    if n > 0 then tip[#tip + 1] = TEXT(Loc.plural(n, "deaths_one", "deaths_other"), int(n)) end
    col.tip = tip
    cols[#cols + 1] = col
  end
  -- deaths beyond the shown levels (e.g. a level from the SV above the current one) count as without level
  local shownDeaths = 0
  for _, c in ipairs(cols) do shownDeaths = shownDeaths + c.deaths end
  local notes = {}
  local used = {}
  local seed = texts and texts.seed(type(st.char.info) == "table" and st.char.info.firstSeen) or "0"
  if texts and fastL and complete >= 2 then -- "fastest" only from two completed levels
    local n = texts.pick("margin", { kind = "fastest", level = fastL, duration = Chronik.duration(st.dur[fastL]) }, seed,
      "fast:" .. fastL, used)
    if n then notes[#notes + 1] = n end
  end
  if texts and slowL and slowL ~= fastL and complete >= 2 then
    local n = texts.pick("margin", { kind = "slowest", level = slowL, duration = Chronik.duration(st.dur[slowL]) }, seed,
      "slow:" .. slowL, used)
    if n then notes[#notes + 1] = n end
  end
  local axis = {}
  for i, c in ipairs(cols) do
    if i == 1 or c.current or c.level % 5 == 0 then axis[#axis + 1] = { i = i, text = int(c.level) } end
  end
  return {
    cols = cols, total = total, deaths = shownDeaths, deathsTotal = st.deathsTotal,
    deathsNoLevel = st.deathsTotal - shownDeaths, fastest = fastL, slowest = slowL, notes = notes, axis = axis,
    -- "longest" only among completed levels (as the margin note), the running one does not count
    maxText = (slowL and complete >= 2) and Chronik.duration(st.dur[slowL]) or nil, empty = complete == 0, complete = complete, current = curDur,
  }
end

local function forecastOf(st, level, curDur)
  local out = { ok = false, title = TEXT.forecastTitle }
  local top = Chronik.maxLevel()
  if level >= top then
    out.body = TEXT("forecastDone", int(top))
    return out
  end
  if level < Chronik.FORECAST_FROM then
    out.body = TEXT.forecastEarly
    return out
  end
  local d = {}
  for L = max(1, level - Chronik.FORECAST_LEVELS), level - 1 do
    if st.dur[L] and st.dur[L] > 0 then d[#d + 1] = st.dur[L] end
  end
  local remaining = Chronik.project(d, level, curDur or 0, top)
  if not remaining or not finite(remaining) then
    out.body = TEXT.forecastNone
    return out
  end
  out.ok, out.hours = true, remaining / 3600
  local h = remaining > 9999 * 3600 and TEXT("over", int(9999)) or Chronik.approxDuration(remaining)
  out.title = TEXT("forecastHead", int(top), h)
  out.body = TEXT("forecastBody", int(#d))
  return out
end

function Chronik.evaluate(index, opts)
  if type(index) ~= "table" then return nil end
  opts = type(opts) == "table" and opts or {}
  local now = tonumber(opts.now) or time()
  local live = opts.live
  local db = opts.db or EveNChronicleDB
  local st = Chronik.static(index)
  local Idx = I()

  -- level: live, else last LV/PL line
  local level = live and live.level and live.level() or nil
  if not level then
    local lv = Idx.list(index, "LV")
    level = lv[#lv] and levelOf(lv[#lv], "LV") or nil
  end
  if not level then
    local pl = Idx.list(index, "PL")
    level = pl[#pl] and levelOf(pl[#pl], "PL") or nil
  end
  level = level or 1

  -- play time now: last PL.total plus active time since the answer; without PL the active time since the start (approx.)
  local playedSec, exact
  local total, at = lastPlayed(index)
  if total then
    local extra = now > at and (Idx.activeSeconds(index, at, now)) or 0
    playedSec, exact = total + extra, true
  elseif finite(index.startT) and now >= index.startT then
    playedSec, exact = (Idx.activeSeconds(index, index.startT, now)), false
  end

  local view = { now = now, level = level }
  view.profile = profileOf(index, st, level, playedSec, exact, db, now)
  view.xp = xpOf(index, live, level)
  view.seals = liveSeals(Chronik.sealsOf(index), level)
  view.flow = flowOf(index, st, level, playedSec, now, T())
  view.diary = st.diary
  view.sources = st.sources
  view.forecast = forecastOf(st, level, view.flow.current)
  view.seed = T() and T().seed(type(st.char.info) == "table" and st.char.info.firstSeen) or "0"
  return view
end

-- sentence of a diary entry (deterministic per entry, computed once). Fallback: fixed text per kind.
local FALLBACK = { -- text: TEXT["fb_" .. kind]
  level = true, quest = true, loot = true, kill = true, close = true, death = true, moment = true, campfire = true, zone = true,
  subzone = true, flight = true, hearth = true, instance = true, encounter = true, guild = true,
}
local function fallback(kind) return FALLBACK[kind] and TEXT["fb_" .. kind] or "" end

-- trial rounds of the retail simulation get the suffix "(Probe)" in the diary
local function withProbe(e, s)
  if s ~= "" and type(e.ctx) == "table" and e.ctx.kind == "campfire" and e.ctx.sim then return s .. TEXT.probe end
  return s
end

-- set the sentences of a whole day in fixed order (oldest first): per event kind a pattern is only taken again once all
-- fitting ones have been used
-- (repetition within a page as rare as possible). Deterministic because the order is fixed, whatever order entryText is
-- called in.
local function fillDay(view, bucket)
  local Texts = T()
  local seed = view and view.seed or "0"
  local used = {}
  local en = bucket.entries
  for i = #en, 1, -1 do
    local e = en[i]
    if not e.text then
      local u = used[e.kind]
      if not u then
        u = {}
        used[e.kind] = u
      end
      local s = Texts and Texts.pick("diary", e.ctx, seed, e.key, u) or nil
      if not s and Texts and next(u) then
        for k in pairs(u) do u[k] = nil end -- all patterns of this kind were used: start over
        s = Texts.pick("diary", e.ctx, seed, e.key, u)
      end
      e.text = withProbe(e, s or fallback(e.kind))
    end
  end
end

function Chronik.entryText(view, entry)
  if type(entry) ~= "table" then return nil end
  if entry.text then return entry.text end
  if entry.bucket then
    fillDay(view, entry.bucket)
    if entry.text then return entry.text end
  end
  local Texts = T()
  local s = Texts and Texts.pick("diary", entry.ctx, view and view.seed or "0", entry.key, {}) or nil
  entry.text = withProbe(entry, s or fallback(entry.kind))
  return entry.text
end
