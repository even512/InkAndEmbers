-- Campfire talk template library: hand-written German sentences as data, never SV data. def = { id, cat, w, du, ihr,
-- why, fact, person, when }.
-- Selection, placeholder filling and sanitizing live in CampfireTalk.lua; foreign text only enters through placeholders
-- (CampfireTalk.fill).
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local CampfireTexts = {}
Journal.CampfireTexts = CampfireTexts

local gmatch, find = string.gmatch, string.find

CampfireTexts.CATEGORIES = {
  arrive = true, time = true, death = true, rare = true, quest = true, zone = true, level = true, medal = true,
  person = true, group = true, alone = true, past = true, place = true, general = true, farewell = true, fire = true,
  follow = true, elite = true, bag = true, profession = true, rep = true, subzone = true, streak = true,
}

-- classes: nominative m/f, accusative m (weak declension)
CampfireTexts.CLASSES = {
  WARRIOR = { m = "Krieger", f = "Kriegerin", mAkk = "Krieger" },
  PALADIN = { m = "Paladin", f = "Paladin", mAkk = "Paladin" },
  HUNTER = { m = "Jäger", f = "Jägerin", mAkk = "Jäger" },
  ROGUE = { m = "Schurke", f = "Schurkin", mAkk = "Schurken" },
  PRIEST = { m = "Priester", f = "Priesterin", mAkk = "Priester" },
  DEATHKNIGHT = { m = "Todesritter", f = "Todesritterin", mAkk = "Todesritter" },
  SHAMAN = { m = "Schamane", f = "Schamanin", mAkk = "Schamanen" },
  MAGE = { m = "Magier", f = "Magierin", mAkk = "Magier" },
  WARLOCK = { m = "Hexenmeister", f = "Hexenmeisterin", mAkk = "Hexenmeister" },
  MONK = { m = "Mönch", f = "Mönch", mAkk = "Mönch" },
  DRUID = { m = "Druide", f = "Druidin", mAkk = "Druiden" },
  DEMONHUNTER = { m = "Dämonenjäger", f = "Dämonenjägerin", mAkk = "Dämonenjäger" },
  EVOKER = { m = "Rufer", f = "Ruferin", mAkk = "Rufer" },
}

-- races: dative plural for "von den ..."; an unknown token skips templates that use {volk}
CampfireTexts.RACES = {
  Human = "Menschen", Dwarf = "Zwergen", NightElf = "Nachtelfen", Gnome = "Gnomen", Draenei = "Draenei",
  Worgen = "Worgen", Pandaren = "Pandaren", Orc = "Orcs", Scourge = "Untoten", Tauren = "Tauren", Troll = "Trollen",
  BloodElf = "Blutelfen", Goblin = "Goblins", Nightborne = "Nachtgeborenen", HighmountainTauren = "Hochbergtauren",
  VoidElf = "Leerenelfen", LightforgedDraenei = "Lichtgeschmiedeten", ZandalariTroll = "Zandalaritrollen",
  KulTiran = "Kul Tiranern", DarkIronDwarf = "Dunkeleisenzwergen", Vulpera = "Vulpera", MagharOrc = "Mag'har",
  Mechagnome = "Mechagnomen", Dracthyr = "Dracthyr", EarthenDwarf = "Irdenen", Earthen = "Irdenen",
}

-- locale scope "m.CampfireTexts": per template a key <id> = { du, ihr, why } (registered from the German template),
-- plus classes, races, ordinals and articles.
-- English in locales/enUS_model.lua: "du" casual, "ihr" slightly more formal/roleplay. CLASSES/RACES above stay the
-- German source.
local L = ns.Locale
local AREA = "m.CampfireTexts"
local TX = L.ns(AREA, {
  classes = CampfireTexts.CLASSES,
  races = CampfireTexts.RACES,
  numbers = { "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf" },
  ordinals = { "erste", "zweite", "dritte", "vierte", "fünfte", "sechste", "siebte", "achte", "neunte", "zehnte" },
  ordSt = "%d.", ordNd = "%d.", ordRd = "%d.", ordTh = "%d.",
  -- indefinite article before the class (accusative): m/f, "Vowel" = name starts with a vowel (English "an")
  einM = "einen %s", einF = "eine %s", einMVowel = "einen %s", einFVowel = "eine %s",
})
CampfireTexts.T = TX

function CampfireTexts.ordinal(n)
  if type(n) ~= "number" or n ~= n or n < 2 or n > 999 then return nil end
  n = math.floor(n)
  local w = TX.ordinals[n]
  if w then return w end
  local last, two = n % 10, n % 100
  local key = "ordTh"
  if two < 11 or two > 13 then
    if last == 1 then key = "ordSt" elseif last == 2 then key = "ordNd" elseif last == 3 then key = "ordRd" end
  end
  return TX(key, n)
end

-- number of people as a word ("drei" | "three"), digits above twelve
function CampfireTexts.countWord(n)
  if type(n) ~= "number" or n ~= n or n < 1 or n > 999 then return nil end
  n = math.floor(n)
  local w = TX.numbers[n]
  return type(w) == "string" and w or tostring(n)
end

-- class in the active language: name (nominative matching sex), withArticle ("einen Krieger" | "a Warrior") | nil
function CampfireTexts.className(token, sex)
  local cls = type(token) == "string" and TX.classes[token] or nil
  if type(cls) ~= "table" or (sex ~= "m" and sex ~= "f") then return nil end
  local name = sex == "f" and cls.f or cls.m
  local akk = sex == "f" and cls.f or cls.mAkk
  local vowel = string.find(akk, "^[AEIOUaeiou]") ~= nil
  local key = (sex == "f" and "einF" or "einM") .. (vowel and "Vowel" or "")
  return name, TX(key, akk)
end

-- race ("Zwergen" | "Dwarves") in the active language | nil
function CampfireTexts.raceName(token)
  local r = type(token) == "string" and TX.races[token] or nil
  return type(r) == "string" and r or nil
end

-- template text (field = "du" | "ihr" | "why") in the active language; falls back to the template's own text
function CampfireTexts.text(def, field)
  if type(def) ~= "table" then return nil end
  local loc = L.get(AREA, def.id)
  local v = type(loc) == "table" and loc[field] or nil
  if type(v) == "string" and v ~= "" then return v end
  return def[field]
end

function CampfireTexts.placeholders(text)
  local out = {}
  if type(text) ~= "string" then return out end
  for k in gmatch(text, "{(%a+)}") do out[k] = true end
  return out
end

local lib, byId = {}, {}
CampfireTexts.list = lib

function CampfireTexts.get(id) return byId[id] end
function CampfireTexts.count() return #lib end

local function samePlaceholders(a, b)
  for k in pairs(a) do if not b[k] then return false end end
  for k in pairs(b) do if not a[k] then return false end end
  return true
end

function CampfireTexts.add(def)
  if type(def) ~= "table" then return false end
  if type(def.id) ~= "string" or def.id == "" or byId[def.id] then return false end
  if not CampfireTexts.CATEGORIES[def.cat] then return false end
  for _, k in ipairs({ "du", "ihr", "why" }) do
    if type(def[k]) ~= "string" or def[k] == "" or find(def[k], "|", 1, true) then return false end
  end
  if not samePlaceholders(CampfireTexts.placeholders(def.du), CampfireTexts.placeholders(def.ihr)) then return false end
  if def.when ~= nil and type(def.when) ~= "function" then return false end
  local w = tonumber(def.w) or 1
  if w ~= w or w <= 0 or w == math.huge then return false end
  local e = { id = def.id, cat = def.cat, w = w, du = def.du, ihr = def.ihr, why = def.why, fact = def.fact,
    person = def.person == true, when = def.when }
  lib[#lib + 1] = e
  byId[e.id] = e
  L.add("deDE", AREA, { [e.id] = { du = e.du, ihr = e.ihr, why = e.why } })
  return true
end

local function add(id, cat, du, ihr, why, extra)
  extra = extra or {}
  extra.id, extra.cat, extra.du, extra.ihr, extra.why = id, cat, du, ihr or du, why
  return CampfireTexts.add(extra)
end

-- arrival (only in the first minutes of the session)
local function early(c) return c.sinceStart == nil or c.sinceStart <= 600 end

add("arrive_fire", "arrive", "Ein Feuer in {zone}, besser hätte der Tag nicht enden können.", nil,
  "Ihr habt Euch gerade am Feuer in {zone} niedergelassen.", { when = early })
add("arrive_seat", "arrive", "Ist noch ein Platz frei? Meine Füße tragen mich keinen Schritt weiter.", nil,
  "Ihr seid gerade erst am Feuer angekommen.", { when = early })
add("arrive_wood", "arrive", "Gut, dass hier jemand Holz gesammelt hat. Danke euch.",
  "Gut, dass hier jemand Holz gesammelt hat. Danke Euch.", "Ihr seid gerade erst am Feuer angekommen.", { when = early })

-- time of day
add("time_morning", "time", "Schon so früh unterwegs? Ein warmes Feuer am Morgen ist die halbe Rüstung.", nil,
  "Es ist Morgen.", { when = function(c) return c.part == "morning" end })
add("time_evening", "time", "Die Sonne geht über {zone} unter. Zeit für Geschichten.", nil,
  "Es ist Abend in {zone}.", { when = function(c) return c.part == "evening" end })
add("time_night", "time", "Nachts klingt {zone} ganz anders. Hört ihr das auch?",
  "Nachts klingt {zone} ganz anders. Hört Ihr das auch?", "Es ist Nacht in {zone}.",
  { when = function(c) return c.part == "night" end })
add("time_day", "time", "Eine kurze Rast zwischendurch, dann geht's weiter.", nil,
  "Es ist Tag.", { when = function(c) return c.part == "day" end })

-- death
add("death_place", "death", "Ich bin vorhin in {todort} gestorben. Erzählt das bitte niemandem.", nil,
  "Ihr seid vor Kurzem in {todort} gestorben.", { fact = "death" })
add("death_foe", "death", "{toter} hat mich vorhin erwischt. Beim nächsten Mal bin ich vorbereitet.", nil,
  "{toter} hat Euch vor Kurzem besiegt.", { fact = "death" })
add("death_healer", "death", "Der Geistheiler kennt mich inzwischen beim Namen.", nil,
  "Ihr seid vor Kurzem gestorben.", { fact = "death" })

-- rare
add("rare_killed", "rare", "Ich habe {rare} erlegt. Fragt mich nicht, wie oft ich dafür weglaufen musste.", nil,
  "Ihr habt vor Kurzem {rare} erlegt.", { fact = "rare" })
add("rare_met", "rare", "Seid ihr schon mal {rare} begegnet? Ein zäher Brocken.",
  "Seid Ihr schon mal {rare} begegnet? Ein zäher Brocken.", "Ihr habt vor Kurzem {rare} erlegt.", { fact = "rare" })

-- quest
add("quest_done", "quest", "Endlich „{quest}“ abgeschlossen. Ich hätte nicht gedacht, dass das so lange dauert.", nil,
  "Ihr habt vor Kurzem „{quest}“ abgegeben.", { fact = "quest" })
add("quest_asked", "quest", "Hat jemand von euch auch „{quest}“ gemacht? Was für eine Geschichte.",
  "Hat jemand von Euch auch „{quest}“ gemacht? Was für eine Geschichte.", "Ihr habt vor Kurzem „{quest}“ abgegeben.",
  { fact = "quest" })

-- new zone
add("zone_first", "zone", "Ich bin zum ersten Mal in {neuzone}. Was sollte ich gesehen haben?", nil,
  "Ihr seid kürzlich zum ersten Mal in {neuzone} angekommen.", { fact = "newzone" })
add("zone_new", "zone", "{neuzone} ist neu für mich. Gibt es hier etwas, wovor man sich hüten muss?", nil,
  "Ihr seid kürzlich zum ersten Mal in {neuzone} angekommen.", { fact = "newzone" })

-- level
add("level_a", "level", "Stufe {stufe}, langsam fühle ich mich wie ein echter Abenteurer.", nil,
  "Ihr habt kürzlich Stufe {stufe} erreicht.", { fact = "level" })
add("level_b", "level", "Gerade Stufe {stufe} erreicht. Darauf einen Becher Tee.", nil,
  "Ihr habt kürzlich Stufe {stufe} erreicht.", { fact = "level" })

-- medal
add("medal", "medal", "Mein Tagebuch sagt, ich hätte mir „{medaille}“ verdient. Ich nehme es mal als Lob.", nil,
  "Ihr habt kürzlich die Medaille „{medaille}“ verdient.", { fact = "medal" })

-- person (only people surely at the fire)
add("person_class", "person", "{name}, wie ist das Leben als {klasse} hier draußen?",
  "{name}, wie ergeht es Euch als {klasse} hier draußen?", "{name} sitzt am Feuer.", { person = true })
add("person_class_glad", "person", "Gut, {einKlasse} am Feuer zu haben. Da schlafe ich ruhiger.", nil,
  "{name} sitzt am Feuer.", { person = true })
add("person_higher", "person", "{name}, du bist schon Stufe {stufe}? Hast du einen Tipp für mich?",
  "{name}, Ihr seid schon Stufe {stufe}? Habt Ihr einen Tipp für mich?", "{name} sitzt am Feuer und ist weiter als Ihr.",
  { person = true, when = function(c) return c.myLevel ~= nil and c.person.level ~= nil and c.person.level > c.myLevel end })
add("person_lower", "person", "{name}, genieß die ersten Stufen, die vergisst man nie.",
  "{name}, genießt die ersten Stufen, die vergisst man nie.", "{name} sitzt am Feuer und ist noch früh auf dem Weg.",
  { person = true, when = function(c) return c.myLevel ~= nil and c.person.level ~= nil and c.person.level < c.myLevel end })
add("person_equal", "person", "{name}, wir sind ja gleich weit. Wohin geht's als Nächstes?", nil,
  "{name} sitzt am Feuer und hat Eure Stufe.",
  { person = true, when = function(c) return c.myLevel ~= nil and c.person.level == c.myLevel end })
add("person_race", "person", "Erzähl mir von den {volk}, {name}. Ich kenne nur Geschichten.",
  "Erzählt mir von den {volk}, {name}. Ich kenne nur Geschichten.", "{name} sitzt am Feuer.", { person = true })
add("person_general", "person", "Woher kommst du gerade, {name}?", "Woher kommt Ihr gerade, {name}?",
  "{name} sitzt am Feuer.", { person = true })

-- round
add("group_many", "group", "So viele Leute an einem Feuer, fast wie in einer Taverne.", nil,
  "Mehrere Leute sitzen am Feuer.", { when = function(c) return c.others >= 2 end })
add("group_some", "group", "Wenn wir schon zusammen sitzen: Hat jemand Lust, gemeinsam weiterzuziehen?", nil,
  "Jemand sitzt mit Euch am Feuer.", { when = function(c) return c.others >= 1 end })
add("alone", "alone", "Nur ich und das Knistern. Auch schön.", nil,
  "Niemand sonst ist am Feuer zu sehen.", { w = 0.2, when = function(c) return c.nearby == 0 end })

-- past (the person was at an earlier fire)
local function past(c) return type(c.person.past) == "table" end
add("past_seen", "past", "{name}! Wir saßen doch schon in {altzone} zusammen am Feuer.", nil,
  "Ihr kennt {name} von einem früheren Feuer.", { person = true, when = past })
add("past_tradition", "past", "Schon das {mal} Feuer mit dir, {name}. Langsam wird das eine Tradition.",
  "Schon das {mal} Feuer mit Euch, {name}. Langsam wird das eine Tradition.", "Ihr kennt {name} von früheren Feuern.",
  { person = true, when = past })
add("past_levels", "past", "{name}, seit {altzone} hast du ordentlich Stufen gesammelt.",
  "{name}, seit {altzone} habt Ihr ordentlich Stufen gesammelt.", "{name} ist seit dem letzten gemeinsamen Feuer gestiegen.",
  { person = true, when = function(c) return past(c) and c.person.past.level ~= nil and c.person.level ~= nil and c.person.level - c.person.past.level >= 3 end })
add("past_hello", "past", "Schön, dich wiederzusehen, {name}. Wie ist es dir seit {altzone} ergangen?",
  "Schön, Euch wiederzusehen, {name}. Wie ist es Euch seit {altzone} ergangen?", "Ihr kennt {name} von einem früheren Feuer.",
  { person = true, when = past })

-- place
add("place_know", "place", "Was weiß man eigentlich über {zone}? Ich habe nur Gerüchte gehört.", nil,
  "Ihr sitzt in {zone}.")
add("place_fish", "place", "In {zone} gibt es bestimmt gute Plätze zum Angeln. Kennt jemand einen?", nil,
  "Ihr sitzt in {zone}.")

-- general
add("gen_armor", "general", "Ich muss dringend meine Rüstung flicken lassen. Kennt jemand einen Schmied in der Nähe?", nil,
  "Ein Satz für die Runde am Feuer.")
add("gen_food", "general", "Hat jemand etwas zu essen übrig? Ich biete eine gute Geschichte im Tausch.", nil,
  "Ein Satz für die Runde am Feuer.")
add("gen_find", "general", "Was war euer bester Fund heute?", "Was war Euer bester Fund heute?",
  "Ein Satz für die Runde am Feuer.")
add("gen_leave", "general", "Noch fünf Minuten am Feuer, dann breche ich auf.", nil,
  "Ein Satz für die Runde am Feuer.")

-- farewell (after sitting a while or when the caller asks, ctx.farewell)
local function late(c) return c.farewell == true end
add("bye_group", "farewell", "Danke für die Gesellschaft. Möge euer Weg sicher sein.",
  "Danke für die Gesellschaft. Möge Euer Weg sicher sein.", "Ihr sitzt schon eine Weile am Feuer.", { when = late })
add("bye_person", "farewell", "Pass auf dich auf, {name}. Vielleicht sieht man sich am nächsten Feuer.",
  "Passt auf Euch auf, {name}. Vielleicht sieht man sich am nächsten Feuer.", "{name} sitzt am Feuer.",
  { person = true, when = late })

-- the fire itself
add("fire_who", "fire", "Wer hat dieses Feuer gemacht? Sehr gemütlich.", nil, "Ihr sitzt an einem Lagerfeuer.")

-- ---------------------------------------------------------------------------------------------------------------
-- 1.0.2: more variety (about three times the templates). Same rules as above: short, said to the others at the fire,
-- placeholders only for foreign text.
local function withOthers(c) return c.others >= 1 end
local function many(c) return c.others >= 2 end
local function lvlDiff(c) return c.myLevel ~= nil and c.person.level ~= nil and c.person.level - c.myLevel or nil end
local function sameRace(c) return c.myRace ~= nil and c.person.raceToken == c.myRace end
local function otherRace(c) return c.myRace ~= nil and c.person.raceToken ~= nil and c.person.raceToken ~= c.myRace end
local function sameClass(c) return c.myClass ~= nil and c.person.classToken == c.myClass end
local function otherClass(c) return c.myClass ~= nil and c.person.classToken ~= nil and c.person.classToken ~= c.myClass end
local function partIs(p) return function(c) return c.part == p end end

-- arrival
add("arrive_join", "arrive", "Darf ich mich zu euch setzen?", "Darf ich mich zu Euch setzen?",
  "Ihr seid gerade erst am Feuer angekommen.", { when = function(c) return early(c) and withOthers(c) end })
add("arrive_road", "arrive", "Was für ein Weg bis hierher. Das Feuer kommt genau richtig.", nil,
  "Ihr seid gerade erst am Feuer angekommen.", { when = early })
add("arrive_cold", "arrive", "Endlich ein Feuer. Meine Hände sind ganz kalt.", nil,
  "Ihr seid gerade erst am Feuer angekommen.", { when = early })
add("arrive_short", "arrive", "Ich bleibe nicht lange, nur kurz aufwärmen.", nil,
  "Ihr seid gerade erst am Feuer angekommen.", { when = early })
add("arrive_smoke", "arrive", "Den Rauch habe ich schon von Weitem gesehen. Gut, dass ich ihm gefolgt bin.", nil,
  "Ihr seid gerade erst am Feuer angekommen.", { when = early })

-- time of day, partly with the zone
add("time_morning_zone", "time", "Morgens ist {zone} am schönsten, bevor alle wach sind.", nil,
  "Es ist Morgen in {zone}.", { when = partIs("morning") })
add("time_evening_dark", "time", "Bald wird es dunkel. Ich bleibe lieber am Feuer.", nil,
  "Es ist Abend.", { when = partIs("evening") })
add("time_night_awake", "time", "Wer ist um diese Zeit noch wach? Ich kann nicht schlafen.", nil,
  "Es ist Nacht.", { when = partIs("night") })
add("time_day_zone", "time", "Mittag in {zone}, und ich habe schon einiges hinter mir.", nil,
  "Es ist Tag in {zone}.", { when = partIs("day") })

-- death
add("death_rest", "death", "Nach meinem Tod in {todort} brauche ich erst mal Ruhe.", nil,
  "Ihr seid vor Kurzem in {todort} gestorben.", { fact = "death" })
add("death_warn", "death", "{toter}: Haltet Abstand. Ich spreche aus Erfahrung.", nil, "{toter} hat Euch vor Kurzem besiegt.", { fact = "death" })
add("death_lesson", "death", "Vorhin einmal gestorben. Ich nehme es als Lehrgeld.", nil,
  "Ihr seid vor Kurzem gestorben.", { fact = "death" })

-- rare
add("rare_found", "rare", "{rare} ist erledigt. Ich habe lange danach gesucht.", nil,
  "Ihr habt vor Kurzem {rare} erlegt.", { fact = "rare" })
add("rare_luck", "rare", "Wer jagt hier noch seltene Beute? Ich hatte vorhin Glück mit {rare}.", nil,
  "Ihr habt vor Kurzem {rare} erlegt.", { fact = "rare" })
add("rare_hard", "rare", "Mit {rare} hatte ich vorhin einen harten Kampf. Es hat sich gelohnt.", nil,
  "Ihr habt vor Kurzem {rare} erlegt.", { fact = "rare" })
add("rare_chance", "rare", "Kennt jemand {rare}? Ich bin vorhin zufällig darauf gestoßen.", nil,
  "Ihr habt vor Kurzem {rare} erlegt.", { fact = "rare" })

-- quest
add("quest_happy", "quest", "„{quest}“ ist erledigt. Der Questgeber war zufrieden, ich auch.", nil,
  "Ihr habt vor Kurzem „{quest}“ abgegeben.", { fact = "quest" })
add("quest_tip", "quest", "Wer „{quest}“ noch vor sich hat: Ich kann einen Tipp geben.", nil,
  "Ihr habt vor Kurzem „{quest}“ abgegeben.", { fact = "quest" })
add("quest_break", "quest", "Nach „{quest}“ brauchte ich dringend eine Pause.", nil,
  "Ihr habt vor Kurzem „{quest}“ abgegeben.", { fact = "quest" })
add("quest_walk", "quest", "Für „{quest}“ bin ich ganz schön herumgelaufen. Jetzt sitze ich erst mal.", nil,
  "Ihr habt vor Kurzem „{quest}“ abgegeben.", { fact = "quest" })

-- new zone
add("zone_trader", "zone", "Ich bin noch nicht lange in {neuzone}. Wo findet man hier einen Händler?", nil,
  "Ihr seid kürzlich zum ersten Mal in {neuzone} angekommen.", { fact = "newzone" })
add("zone_other", "zone", "{neuzone} hatte ich mir anders vorgestellt. Größer irgendwie.", nil,
  "Ihr seid kürzlich zum ersten Mal in {neuzone} angekommen.", { fact = "newzone" })
add("zone_lost", "zone", "Kennt sich jemand in {neuzone} aus? Ich habe mich schon zweimal verlaufen.", nil,
  "Ihr seid kürzlich zum ersten Mal in {neuzone} angekommen.", { fact = "newzone" })
add("zone_danger", "zone", "Ist {neuzone} gefährlich? Ich bin neu hier.", nil,
  "Ihr seid kürzlich zum ersten Mal in {neuzone} angekommen.", { fact = "newzone" })

-- level
add("level_pack", "level", "Stufe {stufe}. Ich merke, dass mir die Kämpfe leichter fallen.", nil,
  "Ihr habt kürzlich Stufe {stufe} erreicht.", { fact = "level" })
add("level_trainer", "level", "Stufe {stufe} erreicht. Jetzt erst mal zum Lehrer.", nil,
  "Ihr habt kürzlich Stufe {stufe} erreicht.", { fact = "level" })
add("level_further", "level", "Mit Stufe {stufe} traue ich mich endlich etwas weiter hinaus.", nil,
  "Ihr habt kürzlich Stufe {stufe} erreicht.", { fact = "level" })
add("level_party", "level", "Stufe {stufe}. Wer feiert mit mir?", nil,
  "Ihr habt kürzlich Stufe {stufe} erreicht.", { fact = "level" })

-- medal
add("medal_entry", "medal", "„{medaille}“ steht jetzt in meinem Tagebuch. Ein schöner Eintrag.", nil,
  "Ihr habt kürzlich die Medaille „{medaille}“ verdient.", { fact = "medal" })
add("medal_alone", "medal", "Ich habe mir kürzlich „{medaille}“ verdient. Ganz ohne Hilfe.", nil,
  "Ihr habt kürzlich die Medaille „{medaille}“ verdient.", { fact = "medal" })
add("medal_who", "medal", "Wer von euch hat auch „{medaille}“? Ich habe sie vor Kurzem bekommen.",
  "Wer von Euch hat auch „{medaille}“? Ich habe sie vor Kurzem bekommen.",
  "Ihr habt kürzlich die Medaille „{medaille}“ verdient.", { fact = "medal" })
add("medal_proud", "medal", "„{medaille}“, schreibt mein Tagebuch. Ich bin ein bisschen stolz.", nil,
  "Ihr habt kürzlich die Medaille „{medaille}“ verdient.", { fact = "medal" })
add("medal_fuller", "medal", "Mein Tagebuch wird voller. Vor Kurzem kam „{medaille}“ dazu.", nil,
  "Ihr habt kürzlich die Medaille „{medaille}“ verdient.", { fact = "medal" })

-- elite kill
add("elite_beat", "elite", "{elite}: besiegt. Vor ein paar Tagen hätte ich mich das nicht getraut.", nil,
  "Ihr habt vor Kurzem {elite} besiegt.", { fact = "elite" })
add("elite_tough", "elite", "Mein letzter harter Kampf: {elite}. Meine Arme spüre ich immer noch.", nil,
  "Ihr habt vor Kurzem {elite} besiegt.", { fact = "elite" })
add("elite_first", "elite", "Mein erster richtig starker Gegner: {elite}. Ich zittere noch ein bisschen.", nil,
  "Ihr habt vor Kurzem zum ersten Mal einen Elitegegner besiegt: {elite}.",
  { fact = "elite", when = function(c) return c.facts.elite.first == true end })
add("elite_potions", "elite", "{elite}? Nur mit Tränken. Glaubt mir.", nil,
  "Ihr habt vor Kurzem {elite} besiegt.", { fact = "elite" })
add("elite_help", "elite", "{elite}: Da hätte ich Hilfe gebraucht. Ging dann aber doch.", nil,
  "Ihr habt vor Kurzem {elite} besiegt.", { fact = "elite" })

-- first bag
add("bag_finally", "bag", "Endlich eine richtige Tasche. Jetzt muss ich nicht mehr alles liegen lassen.", nil,
  "Ihr habt vor Kurzem Eure erste Tasche bekommen.", { fact = "bag" })
add("bag_joy", "bag", "Meine erste Tasche. Wer hätte gedacht, dass mich so etwas so freut.", nil,
  "Ihr habt vor Kurzem Eure erste Tasche bekommen.", { fact = "bag" })
add("bag_fits", "bag", "Ich habe jetzt eine Tasche. Was da alles reinpasst, glaubt ihr nicht.",
  "Ich habe jetzt eine Tasche. Was da alles reinpasst, glaubt Ihr nicht.",
  "Ihr habt vor Kurzem Eure erste Tasche bekommen.", { fact = "bag" })
add("bag_long", "bag", "Hat noch jemand so lange ohne Tasche durchgehalten wie ich?", nil,
  "Ihr habt vor Kurzem Eure erste Tasche bekommen.", { fact = "bag" })

-- profession
add("prof_start", "profession", "Ich habe mit {beruf} angefangen. Hat jemand einen Rat für den Anfang?", nil,
  "Ihr lernt seit Kurzem {beruf}.", { fact = "profession" })
add("prof_fun", "profession", "{beruf} macht mehr Spaß, als ich dachte.", nil,
  "Ihr lernt seit Kurzem {beruf}.", { fact = "profession" })
add("prof_who", "profession", "Wer von euch kennt sich mit {beruf} aus?", "Wer von Euch kennt sich mit {beruf} aus?",
  "Ihr lernt seit Kurzem {beruf}.", { fact = "profession" })
add("prof_need", "profession", "Ich übe mich gerade in {beruf}. Braucht jemand etwas?", nil,
  "Ihr lernt seit Kurzem {beruf}.", { fact = "profession" })
add("prof_eyes", "profession", "Seit ich {beruf} lerne, schaue ich unterwegs ganz anders hin.", nil,
  "Ihr lernt seit Kurzem {beruf}.", { fact = "profession" })

-- reputation tier
add("rep_better", "rep", "Mein Ruf bei {fraktion} wird langsam besser.", nil,
  "Euer Ruf bei {fraktion} ist kürzlich gestiegen.", { fact = "rep" })
add("rep_known", "rep", "Für {fraktion} habe ich einiges erledigt. Man kennt mich dort langsam.", nil,
  "Euer Ruf bei {fraktion} ist kürzlich gestiegen.", { fact = "rep" })
add("rep_who", "rep", "Arbeitet jemand von euch auch für {fraktion}?", "Arbeitet jemand von Euch auch für {fraktion}?",
  "Euer Ruf bei {fraktion} ist kürzlich gestiegen.", { fact = "rep" })
add("rep_nod", "rep", "Bei {fraktion} nickt man mir inzwischen freundlich zu.", nil,
  "Euer Ruf bei {fraktion} ist kürzlich gestiegen.", { fact = "rep" })
add("rep_errands", "rep", "Ein paar Gefallen für {fraktion}, und schon bin ich dort gern gesehen.", nil,
  "Euer Ruf bei {fraktion} ist kürzlich gestiegen.", { fact = "rep" })

-- new subzone
add("sub_been", "subzone", "Wart ihr schon in {unterzone}? Ich bin vorhin dort vorbeigekommen.",
  "Wart Ihr schon in {unterzone}? Ich bin vorhin dort vorbeigekommen.", "Ihr wart vor Kurzem zum ersten Mal in {unterzone}.",
  { fact = "subzone" })
add("sub_odd", "subzone", "In {unterzone} war ich vorhin zum ersten Mal. Seltsamer Ort.", nil,
  "Ihr wart vor Kurzem zum ersten Mal in {unterzone}.", { fact = "subzone" })
add("sub_again", "subzone", "{unterzone} habe ich vorhin entdeckt. Da muss ich noch mal hin.", nil,
  "Ihr wart vor Kurzem zum ersten Mal in {unterzone}.", { fact = "subzone" })
add("sub_story", "subzone", "Kennt jemand {unterzone}? Ich wüsste gern, was es damit auf sich hat.", nil,
  "Ihr wart vor Kurzem zum ersten Mal in {unterzone}.", { fact = "subzone" })
add("sub_quiet", "subzone", "Auf dem Weg hierher kam ich durch {unterzone}. Ruhig dort, fast zu ruhig.", nil,
  "Ihr wart vor Kurzem zum ersten Mal in {unterzone}.", { fact = "subzone" })

-- kill streak
add("streak_pause", "streak", "{kills} Gegner in der letzten halben Stunde. Ich brauche eine Pause.", nil,
  "Ihr habt in der letzten halben Stunde {kills} Gegner besiegt.", { fact = "streak" })
add("streak_arms", "streak", "Mir tun die Arme weh. {kills} Kämpfe am Stück.", nil,
  "Ihr habt in der letzten halben Stunde {kills} Gegner besiegt.", { fact = "streak" })
add("streak_fire", "streak", "Nach {kills} Kämpfen am Stück tut so ein Feuer richtig gut.", nil,
  "Ihr habt in der letzten halben Stunde {kills} Gegner besiegt.", { fact = "streak" })
add("streak_count", "streak", "Irgendwann habe ich aufgehört zu zählen. Es waren um die {kills}.", nil,
  "Ihr habt in der letzten halben Stunde {kills} Gegner besiegt.", { fact = "streak" })

-- guests (only people surely at the fire): race, class and level compared with your own character
add("person_same_race", "person", "Noch jemand von den {volk}. Schön, dich hier zu treffen, {name}.",
  "Noch jemand von den {volk}. Schön, Euch hier zu treffen, {name}.", "{name} sitzt am Feuer und ist von Eurem Volk.",
  { person = true, when = sameRace })
add("person_other_race", "person", "{name}, ich hatte bisher wenig mit den {volk} zu tun. Wie lebt man bei euch?",
  "{name}, ich hatte bisher wenig mit den {volk} zu tun. Wie lebt man bei Euch?", "{name} sitzt am Feuer.",
  { person = true, when = otherRace })
add("person_same_class", "person", "Schön, noch {einKlasse} zu treffen, {name}. Wir sind selten genug.", nil,
  "{name} sitzt am Feuer und hat Eure Klasse.", { person = true, when = sameClass })
add("person_class_why", "person", "Was hat dich dazu gebracht, {klasse} zu werden, {name}?",
  "Was hat Euch dazu gebracht, {klasse} zu werden, {name}?", "{name} sitzt am Feuer.", { person = true, when = otherClass })
add("person_much_higher", "person", "{name}, Stufe {stufe}? Dann hast du schon mehr gesehen als ich.",
  "{name}, Stufe {stufe}? Dann habt Ihr schon mehr gesehen als ich.", "{name} sitzt am Feuer und ist Euch weit voraus.",
  { person = true, when = function(c) local d = lvlDiff(c) return d ~= nil and d >= 5 end })
add("person_much_lower", "person", "{name}, wenn du bei einer Aufgabe Hilfe brauchst, sag Bescheid.",
  "{name}, wenn Ihr bei einer Aufgabe Hilfe braucht, sagt Bescheid.", "{name} sitzt am Feuer und ist noch früh auf dem Weg.",
  { person = true, when = function(c) local d = lvlDiff(c) return d ~= nil and d <= -5 end })
add("person_zone", "person", "Was führt dich nach {zone}, {name}?", "Was führt Euch nach {zone}, {name}?",
  "{name} sitzt am Feuer.", { person = true })
add("person_others", "person", "{name}, kennst du die anderen hier schon?", "{name}, kennt Ihr die anderen hier schon?",
  "{name} sitzt mit mehreren am Feuer.", { person = true, when = many })

-- round
add("group_count", "group", "Schon {anzahl} Leute an einem Feuer. Hier ist ja richtig was los.", nil,
  "Mehrere Leute sitzen am Feuer.", { when = many })
add("group_story", "group", "Wir sind {anzahl} am Feuer. Wer erzählt die erste Geschichte?", nil,
  "Mehrere Leute sitzen am Feuer.", { when = many })
add("group_hands", "group", "Hat jemand von euch eine Aufgabe, bei der ein paar Hände mehr helfen?",
  "Hat jemand von Euch eine Aufgabe, bei der ein paar Hände mehr helfen?", "Jemand sitzt mit Euch am Feuer.",
  { when = withOthers })
add("alone_flames", "alone", "Ganz allein am Feuer. Dann rede ich eben mit den Flammen.", nil,
  "Niemand sonst ist am Feuer zu sehen.", { w = 0.2, when = function(c) return c.nearby == 0 end })
add("alone_wait", "alone", "Niemand da. Vielleicht kommt noch jemand vorbei.", nil,
  "Niemand sonst ist am Feuer zu sehen.", { w = 0.2, when = function(c) return c.nearby == 0 end })

-- earlier fire
add("past_luck", "past", "{name}, schon wieder ein Feuer zusammen. Das Glück meint es gut mit uns.", nil,
  "Ihr kennt {name} von einem früheren Feuer.", { person = true, when = past })
add("past_hoped", "past", "Ich hatte gehofft, dich wiederzusehen, {name}.", "Ich hatte gehofft, Euch wiederzusehen, {name}.",
  "Ihr kennt {name} von einem früheren Feuer.", { person = true, when = past })
add("past_road", "past", "Wie war der Weg von {altzone} hierher, {name}?", nil,
  "Ihr kennt {name} von einem früheren Feuer in {altzone}.", { person = true, when = past })
add("past_remember", "past", "{name}, weißt du noch, das Feuer in {altzone}? Da war es kälter.",
  "{name}, wisst Ihr noch, das Feuer in {altzone}? Da war es kälter.", "Ihr kennt {name} von einem früheren Feuer in {altzone}.",
  { person = true, when = past })
add("past_travel", "past", "Das {mal} Feuer mit dir, {name}. Wir sollten langsam zusammen reisen.",
  "Das {mal} Feuer mit Euch, {name}. Wir sollten langsam zusammen reisen.", "Ihr kennt {name} von mehreren Feuern.",
  { person = true, when = function(c) return past(c) and c.person.past.count >= 2 end })
add("past_fate", "past", "{name}, ich glaube langsam, wir treffen uns nicht zufällig.", nil,
  "Ihr kennt {name} von einem früheren Feuer.", { person = true, when = past })
add("past_face", "past", "Gut, ein bekanntes Gesicht zu sehen, {name}. Die Wege sind einsam genug.", nil,
  "Ihr kennt {name} von einem früheren Feuer.", { person = true, when = past })
add("past_news", "past", "{name}, seit {altzone} ist bei mir einiges passiert. Und bei dir?",
  "{name}, seit {altzone} ist bei mir einiges passiert. Und bei Euch?", "Ihr kennt {name} von einem früheren Feuer in {altzone}.",
  { person = true, when = past })
add("past_was_level", "past", "{name}, beim letzten Feuer warst du noch Stufe {altstufe}. Jetzt schon {stufe}.",
  "{name}, beim letzten Feuer wart Ihr noch Stufe {altstufe}. Jetzt schon {stufe}.",
  "{name} ist seit dem letzten gemeinsamen Feuer gestiegen.",
  { person = true, when = function(c) return past(c) and c.person.past.level ~= nil and c.person.level ~= nil and c.person.level > c.person.past.level end })

-- place
add("place_city", "place", "Wie kommt man von {zone} am schnellsten in die nächste Stadt?", nil, "Ihr sitzt in {zone}.")
add("place_quiet", "place", "Ich mag {zone}. Wenig Leute, viel Ruhe.", nil, "Ihr sitzt in {zone}.")
add("place_sight", "place", "Gibt es in {zone} etwas, das man unbedingt gesehen haben muss?", nil, "Ihr sitzt in {zone}.")
add("place_people", "place", "Wer lebt eigentlich in {zone}, wenn nicht gerade Abenteurer durchziehen?", nil,
  "Ihr sitzt in {zone}.")
add("place_noise", "place", "In {zone} hört man nachts seltsame Geräusche. Weiß jemand, was das ist?", nil,
  "Ihr sitzt in {zone}.")
add("place_calm", "place", "Hier in {zone} ist es ruhiger, als ich dachte.", nil, "Ihr sitzt in {zone}.")

-- general
add("gen_bandage", "general", "Hat jemand Verbände übrig? Meine sind aufgebraucht.", nil, "Ein Satz für die Runde am Feuer.")
add("gen_herbs", "general", "Wo kann man hier in der Gegend gut Kräuter sammeln?", nil, "Ein Satz für die Runde am Feuer.")
add("gen_boots", "general", "Ich brauche dringend neue Stiefel. Die alten haben Löcher.", nil, "Ein Satz für die Runde am Feuer.")
add("gen_home", "general", "Was macht ihr, wenn ihr nicht gerade unterwegs seid?",
  "Was macht Ihr, wenn Ihr nicht gerade unterwegs seid?", "Ein Satz für die Runde am Feuer.")
add("gen_inn", "general", "Kennt jemand ein gutes Gasthaus in der Nähe?", nil, "Ein Satz für die Runde am Feuer.")

-- farewell
add("bye_seat", "farewell", "Ich muss weiter. Hebt mir einen Platz am Feuer auf.", nil,
  "Ihr sitzt schon eine Weile am Feuer.", { when = late })
add("bye_smaller", "farewell", "Das Feuer wird kleiner, ich mache mich auf den Weg. Bis bald.", nil,
  "Ihr sitzt schon eine Weile am Feuer.", { when = late })
add("bye_person_nice", "farewell", "{name}, war schön, mit dir am Feuer zu sitzen.",
  "{name}, es war schön, mit Euch am Feuer zu sitzen.", "{name} sitzt am Feuer.", { person = true, when = late })

-- the fire itself
add("fire_wood", "fire", "Das Holz knackt so schön. Ist das Eiche?", nil, "Ihr sitzt an einem Lagerfeuer.")
add("fire_friendly", "fire", "Riecht ihr das Harz im Rauch? Das mag ich.", "Riecht Ihr das Harz im Rauch? Das mag ich.", "Ihr sitzt an einem Lagerfeuer.")
add("fire_fetch", "fire", "Soll ich noch Holz holen? Das Feuer wird kleiner.", nil, "Ihr sitzt an einem Lagerfeuer.")
add("fire_bread", "fire", "Am Feuer schmeckt sogar trockenes Brot gut.", nil, "Ihr sitzt an einem Lagerfeuer.")
add("fire_watch", "fire", "Wer passt heute Nacht auf das Feuer auf?", nil, "Ihr sitzt an einem Lagerfeuer.",
  { when = function(c) return c.part == "evening" or c.part == "night" end })
add("fire_closer", "fire", "Rückt ruhig zusammen, das Feuer reicht für alle.", nil, "Ihr sitzt mit anderen an einem Lagerfeuer.",
  { when = withOthers })
add("fire_hands", "fire", "Ich wärme mir nur kurz die Hände, dann geht es weiter.", nil, "Ihr sitzt an einem Lagerfeuer.")

-- follow-ups (category "follow"): only via CampfireTalk.pick with opts.follow. Person follow-ups address ctx.person
-- (last speaker),
-- topic follow-ups carry fact and check ctx.topic; the rest are general
add("follow_p_ask", "follow", "Und wie war es bei dir, {name}?", "Und wie war es bei Euch, {name}?",
  "{name} hat zuletzt am Feuer gesprochen.", { person = true })
add("follow_p_more", "follow", "Erzähl ruhig mehr, {name}. Ich höre gern zu.", "Erzählt ruhig mehr, {name}. Ich höre gern zu.",
  "{name} hat zuletzt am Feuer gesprochen.", { person = true })
add("follow_p_next", "follow", "{name}, wohin zieht es dich als Nächstes?", "{name}, wohin zieht es Euch als Nächstes?",
  "{name} hat zuletzt am Feuer gesprochen.", { person = true })
add("follow_p_class", "follow", "Als {klasse} hast du sicher schon einiges erlebt, {name}.",
  "Als {klasse} habt Ihr sicher schon einiges erlebt, {name}.", "{name} hat zuletzt am Feuer gesprochen.", { person = true })
local function topic(kind) return function(c) return c.topic == kind end end
add("follow_rare", "follow", "Falls ihr {rare} sucht: Nehmt lieber Verstärkung mit.",
  "Falls Ihr {rare} sucht: Nehmt lieber Verstärkung mit.", "Ihr habt zuletzt von {rare} erzählt.",
  { fact = "rare", when = topic("rare") })
add("follow_quest", "follow", "Wer „{quest}“ noch vor sich hat: Lasst euch Zeit, es lohnt sich.",
  "Wer „{quest}“ noch vor sich hat: Lasst Euch Zeit, es lohnt sich.", "Ihr habt zuletzt von „{quest}“ erzählt.",
  { fact = "quest", when = topic("quest") })
add("follow_death", "follow", "In {todort} passe ich jetzt besser auf. Habt ihr einen Rat?",
  "In {todort} passe ich jetzt besser auf. Habt Ihr einen Rat?", "Ihr habt zuletzt von Eurem Tod in {todort} erzählt.",
  { fact = "death", when = topic("death") })
add("follow_zone", "follow", "Was sollte man in {neuzone} auf keinen Fall verpassen?", nil,
  "Ihr habt zuletzt von {neuzone} erzählt.", { fact = "newzone", when = topic("newzone") })
add("follow_level", "follow", "Mit Stufe {stufe} geht es jetzt richtig los. Wie war das bei euch?",
  "Mit Stufe {stufe} geht es jetzt richtig los. Wie war das bei Euch?", "Ihr habt zuletzt von Stufe {stufe} erzählt.",
  { fact = "level", when = topic("level") })
add("follow_next", "follow", "Und, wohin zieht es euch als Nächstes?", "Und, wohin zieht es Euch als Nächstes?",
  "Eine Nachfrage, damit das Gespräch weiterläuft.")
add("follow_story", "follow", "Hat jemand noch eine Geschichte für das Feuer?", nil,
  "Eine Nachfrage, damit das Gespräch weiterläuft.")
add("follow_why", "follow", "Was hat euch heute eigentlich hergeführt?", "Was hat Euch heute eigentlich hergeführt?",
  "Eine Nachfrage, damit das Gespräch weiterläuft.")
add("follow_tea", "follow", "Noch jemand einen Becher Tee, bevor es weitergeht?", nil,
  "Eine Nachfrage, damit das Gespräch weiterläuft.")

-- 1.0.2: more follow-ups (FireNotes keeps a ring of the last ones so they do not come round again too soon)
add("follow_p_journey", "follow", "{name}, das klingt nach einer langen Reise.", nil,
  "{name} hat zuletzt am Feuer gesprochen.", { person = true })
add("follow_p_right", "follow", "Da hast du recht, {name}.", "Da habt Ihr recht, {name}.",
  "{name} hat zuletzt am Feuer gesprochen.", { person = true })
add("follow_elite", "follow", "{elite}: Da würde ich nicht noch mal allein antreten. Und ihr?",
  "{elite}: Da würde ich nicht noch mal allein antreten. Und Ihr?", "Ihr habt zuletzt von {elite} erzählt.",
  { fact = "elite", when = topic("elite") })
add("follow_profession", "follow", "Falls jemand Material für {beruf} übrig hat: Ich nehme alles.", nil,
  "Ihr habt zuletzt von {beruf} erzählt.", { fact = "profession", when = topic("profession") })
add("follow_first_day", "follow", "Das erinnert mich an meinen ersten Tag unterwegs.", nil,
  "Eine Nachfrage, damit das Gespräch weiterläuft.")
add("follow_log", "follow", "Soll ich noch ein Scheit nachlegen?", nil, "Eine Nachfrage, damit das Gespräch weiterläuft.")
add("follow_quiet", "follow", "Schön, einfach mal still am Feuer zu sitzen.", nil,
  "Eine Nachfrage, damit das Gespräch weiterläuft.")
add("follow_advice", "follow", "Hat jemand einen Rat für mich, bevor ich weiterziehe?", nil,
  "Eine Nachfrage, damit das Gespräch weiterläuft.")
add("follow_go_on", "follow", "Erzählt ruhig weiter, ich höre zu.", nil, "Eine Nachfrage, damit das Gespräch weiterläuft.")
add("follow_best", "follow", "Was war das Schönste, das ihr unterwegs gesehen habt?",
  "Was war das Schönste, das Ihr unterwegs gesehen habt?", "Eine Nachfrage, damit das Gespräch weiterläuft.")
