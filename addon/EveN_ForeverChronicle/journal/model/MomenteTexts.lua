-- Text snippets for the Momente page, registered through Texts.add.
-- {name} = raw SV value (sanitized on insert), {=name} = number or display-ready text from the evaluator.
local _, ns = ...

local Texts = ns.Journal and ns.Journal.Texts
if not Texts then return end

-- entry.kind carries the moment kind; Texts.pick checks it before calling when
local KIND_OF = {}
local function add(group, id, text, when, w)
  Texts.add(group, { area = "m.MomenteTexts", id = id, text = text, when = when, w = w, kind = KIND_OF[when] })
end

local function kind(k, extra)
  local f = function(c)
    if extra then return extra(c) == true end
    return true
  end
  KIND_OF[f] = k
  return f
end

add("moment", "mo_level_1", "Stufe {=level}. Die Reise ist noch lang.", kind("level"))
add("moment", "mo_level_2", "Wieder ein Stück weiter: Stufe {=level}.", kind("level"))
add("moment", "mo_level_3", "Der Ring füllt sich: Stufe {=level}.", kind("level"))
add("moment", "mo_level_4", "Hier in {zone} wurde ich Stufe {=level}.", kind("level", function(c) return c.zone ~= nil end), 2)
add("moment", "mo_level_5", "Stufe {=level} – und {zone} sieht schon anders aus.", kind("level", function(c) return c.zone ~= nil end))
add("moment", "mo_level_6", "Stufe {=level}! Das muss gefeiert werden.", kind("level", function(c) return c.milestone == true end), 3)
add("moment", "mo_level_7", "Ein runder Meilenstein: Stufe {=level}.", kind("level", function(c) return c.milestone == true end), 3)

add("moment", "mo_death_1", "Der erste Tod – lehrreich, wenn auch unschön.", kind("first_death"))
add("moment", "mo_death_2", "Hier endete mein erster Lauf.", kind("first_death"))
add("moment", "mo_death_3", "Lehrgeld gezahlt, in {zone}.", kind("first_death", function(c) return c.zone ~= nil end), 2)

add("moment", "mo_kill_1", "Ein Seltener fiel: {npc}.", kind("kill", function(c) return c.npc ~= nil end), 2)
add("moment", "mo_kill_2", "{npc} – nun nur noch eine Geschichte.", kind("kill", function(c) return c.npc ~= nil end))
add("moment", "mo_kill_3", "Das war ein harter Brocken.", kind("kill"))
add("moment", "mo_first_rare_1", "Mein erster Seltener: {npc}.", kind("first_rare", function(c) return c.npc ~= nil end), 2)
add("moment", "mo_first_rare_2", "Zum ersten Mal etwas Seltenes erlegt.", kind("first_rare"))
add("moment", "mo_first_elite_1", "Der erste Elite-Gegner liegt am Boden.", kind("first_elite"))
add("moment", "mo_first_boss_1", "Der erste Boss – und ich stehe noch.", kind("first_boss"))

add("moment", "mo_close_1", "Das war knapp. Nur noch {=hp} % Leben.", kind("close_win", function(c) return c.hp ~= nil end), 2)
add("moment", "mo_close_2", "Um Haaresbreite davongekommen.", kind("close_win"))
add("moment", "mo_boss_1", "Ein Boss bezwungen: {enc}.", kind("boss", function(c) return c.enc ~= nil end), 2)
add("moment", "mo_boss_2", "Der Boden bebt noch nach.", kind("boss"))

add("moment", "mo_blue_1", "Das erste seltene Stück: {item}.", kind("first_blue", function(c) return c.item ~= nil end), 2)
add("moment", "mo_blue_2", "Endlich etwas Schimmerndes in der Tasche.", kind("first_blue"))
add("moment", "mo_epic_1", "Episch: {item}!", kind("first_epic", function(c) return c.item ~= nil end), 2)
add("moment", "mo_epic_2", "Ein violetter Schatz.", kind("first_epic"))
add("moment", "mo_bag_1", "Mehr Platz im Rucksack: {item}.", kind("first_bag", function(c) return c.item ~= nil end), 2)
add("moment", "mo_bag_2", "Die erste Tasche – nun passt mehr hinein.", kind("first_bag"))
add("moment", "mo_fish_1", "Der erste Fisch zappelt an der Angel.", kind("first_fish"))
add("moment", "mo_mount_1", "Nie wieder zu Fuß: {mount}.", kind("mount", function(c) return c.mount ~= nil end), 2)
add("moment", "mo_mount_2", "Auf vier Hufen unterwegs.", kind("mount"))
add("moment", "mo_rep_1", "Man kennt mich: {faction}.", kind("reputation", function(c) return c.faction ~= nil end), 2)
add("moment", "mo_rep_2", "Der Ruf wächst.", kind("reputation"))
add("moment", "mo_prof_1", "Das Handwerk lohnt sich: {skill}.", kind("profession", function(c) return c.skill ~= nil end), 2)
add("moment", "mo_prof_2", "Die Hände werden geschickter.", kind("profession"))

add("moment", "mo_continent_1", "Neues Land, neue Wege: {zone}.", kind("continent", function(c) return c.zone ~= nil end), 2)
add("moment", "mo_continent_2", "Hinaus aufs Meer – ein neuer Kontinent.", kind("continent"))
add("moment", "mo_dungeon_1", "Zum ersten Mal unter der Erde: {inst}.", kind("first_dungeon", function(c) return c.inst ~= nil end), 2)
add("moment", "mo_dungeon_2", "Der erste Dungeon. Fackeln wären gut.", kind("first_dungeon"))
add("moment", "mo_raid_1", "Der erste Schlachtzug: {inst}.", kind("first_raid", function(c) return c.inst ~= nil end), 2)
add("moment", "mo_raid_2", "Ein Schlachtzug, und nicht allein.", kind("first_raid"))
add("moment", "mo_zone_1", "Neue Zone: {zone}.", kind("zone", function(c) return c.zone ~= nil end), 2)
add("moment", "mo_zone_2", "{zone} – hier war ich noch nie.", kind("zone", function(c) return c.zone ~= nil end))
add("moment", "mo_zone_3", "Wieder eine Ecke der Welt gesehen.", kind("zone"))

add("moment", "mo_other_1", "Ein Augenblick für die Chronik.", kind("other"))
add("moment", "mo_shot_1", "Ein Bild für die Erinnerung.", kind("shot"))
add("moment", "mo_shot_2", "Festgehalten, bevor es vergeht.", kind("shot"))

-- one line per emote token (client token names); "BOW" is already in Texts.lua

local CURIO = {
  WAVE = "gewinkt", HELLO = "Hallo gesagt", BYE = "Lebewohl gewinkt", CHEER = "gejubelt", CLAP = "applaudiert",
  DANCE = "getanzt", LAUGH = "gelacht", CRY = "geweint", SALUTE = "salutiert", SIT = "Platz genommen",
  SLEEP = "ein Nickerchen gemacht", KNEEL = "gekniet", FLEX = "die Muskeln spielen lassen", THANK = "Danke gesagt",
  HUG = "umarmt", KISS = "Küsschen verteilt", POINT = "den Weg gezeigt", ROAR = "gebrüllt",
  SHRUG = "mit den Schultern gezuckt", BEG = "gebettelt", CHICKEN = "gegackert", VICTORY = "Sieg gerufen",
  SIGH = "geseufzt", BORED = "gelangweilt gegähnt", CHARGE = "zum Angriff geblasen", SHY = "schüchtern weggeschaut",
  YES = "genickt", NO = "den Kopf geschüttelt", FLIRT = "geflirtet", CONFUSED = "ratlos geschaut",
}
for token, phrase in pairs(CURIO) do
  add("curio", "curio_" .. string.lower(token), "{=count} × " .. phrase, function(c) return c.token == token end)
end
