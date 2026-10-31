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
  follow = true,
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
