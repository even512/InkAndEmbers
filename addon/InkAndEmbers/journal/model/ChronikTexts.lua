-- Text snippets for the Chronik page, registered through Texts.add.
-- {name} = raw SV value (sanitized on insert), {=name} = number or display-ready text from the evaluator.
local _, ns = ...

local Texts = ns.Journal and ns.Journal.Texts
if not Texts then return end

-- locale scope "m.ChronikTexts"; English lives in locales/enUS_model.lua under the same ids
local function add(group, id, text, when, w)
  Texts.add(group, { area = "m.ChronikTexts", id = id, text = text, when = when, w = w })
end

local function kind(k, extra)
  return function(c)
    if c.kind ~= k then return false end
    if extra then return extra(c) == true end
    return true
  end
end

add("diary", "diary_level_zone_dur", "Stufe {=level} erreicht, mitten in {zone}. Hat {=dur} gedauert.",
  kind("level", function(c) return c.zone ~= nil and c.dur ~= nil end), 3)
add("diary", "diary_level_zone", "Stufe {=level} erreicht, in {zone}.", kind("level"), 1)
add("diary", "diary_level_dur", "Stufe {=level} – nach {=dur} auf der letzten.", kind("level"), 1)
add("diary", "diary_level_milestone", "Stufe {=level}! Ein Meilenstein der Reise.",
  kind("level", function(c) return c.milestone == true end), 4)
add("diary", "diary_quest_xp", "„{title}“ abgegeben · {=xp} EP", kind("quest"), 3)
add("diary", "diary_quest_done", "„{title}“ ist erledigt.", kind("quest"), 1)
add("diary", "diary_quest_plain", "Eine Quest abgegeben · {=xp} EP", kind("quest", function(c) return c.title == nil end), 2)
-- ctx.how: the loot window reads "gefunden"; buy, mail, trade, craft and reward have their own lines
local function loot(how, extra)
  return kind("loot", function(c) return c.how == how and (not extra or extra(c)) end)
end
add("diary", "diary_loot_from", "Gefunden: {item}, von {from}.", loot("found", function(c) return c.from ~= nil end), 3)
add("diary", "diary_loot", "Gefunden: {item}.", loot("found"), 1)
add("diary", "diary_loot_epic", "Ein episches Stück! {item}.", loot("found", function(c) return c.epic == true end), 4)
add("diary", "diary_loot_bought", "Gekauft: {item}.", loot("bought"), 1)
add("diary", "diary_loot_reward", "Als Belohnung erhalten: {item}.", loot("reward"), 1)
add("diary", "diary_loot_crafted", "Selbst hergestellt: {item}.", loot("crafted"), 1)
add("diary", "diary_loot_mail", "Per Post erhalten: {item}.", loot("mail"), 1)
add("diary", "diary_loot_trade", "Eingetauscht: {item}.", loot("trade"), 1)
add("diary", "diary_loot_ah", "Im Auktionshaus erstanden: {item}.", loot("ah"), 1)
add("diary", "diary_loot_other", "Erhalten: {item}.", loot("other"), 1)
add("diary", "diary_kill", "{=cls} {npc} besiegt.", kind("kill"), 3)
add("diary", "diary_kill_rare", "Den seltenen {npc} gestellt und erlegt.", kind("kill", function(c) return c.rare == true end), 2)
add("diary", "diary_kill_anon", "Ein Gegner der Klasse {=cls} fiel.", kind("kill", function(c) return c.npc == nil end), 2)
add("diary", "diary_close_hp", "Knapp gewonnen, mit {=hp} % Leben.", kind("close"), 3)
add("diary", "diary_close_hair", "Um Haaresbreite: nur noch {=hp} % Leben übrig.", kind("close"), 2)
add("diary", "diary_close", "Ein Kampf, der fast schiefging.", kind("close"), 1)
add("diary", "diary_death_zone", "Gestorben in {zone}.", kind("death"), 2)
add("diary", "diary_death_took", "Der Tod holte mich in {zone}. Nur kurz.", kind("death"), 1)
add("diary", "diary_death", "Gestorben. Der Geistheiler wartet schon.", kind("death"), 1)
add("diary", "diary_moment", "Festgehalten: {=what}.", kind("moment"), 2)
add("diary", "diary_moment_zone", "In {zone}: {=what}.", kind("moment"), 1)
-- ctx.who = display-ready "Kuno und Mira (2)", ctx.again = "..." | nil, ctx.zone raw
local function fire(extra)
  return kind("campfire", extra)
end
local function withWho(c) return c.who ~= nil end
local function withAgain(c) return c.who ~= nil and c.again ~= nil end
add("diary", "diary_fire_again", "Am Lagerfeuer in {zone} mit {=who}. {=again}", fire(withAgain), 6)
add("diary", "diary_fire_again_sat", "Gerastet am Lagerfeuer in {zone}, in Gesellschaft von {=who}. {=again}", fire(withAgain), 3)
add("diary", "diary_fire_again_nozone", "Am Lagerfeuer gesessen, mit {=who}. {=again}",
  fire(function(c) return withAgain(c) and c.zone == nil end), 3)
add("diary", "diary_fire_who", "Am Lagerfeuer in {zone} mit {=who}.", fire(withWho), 4)
add("diary", "diary_fire_who_sat", "Gerastet am Lagerfeuer in {zone}, in Gesellschaft von {=who}.", fire(withWho), 2)
add("diary", "diary_fire_who_warm", "Ein Feuer in {zone}, dazu {=who}.", fire(withWho), 1)
add("diary", "diary_fire_who_nozone", "Am Lagerfeuer gesessen, mit {=who}.",
  fire(function(c) return withWho(c) and c.zone == nil end), 4)
add("diary", "diary_fire_alone", "Am Lagerfeuer in {zone} gesessen, allein mit den Funken.",
  fire(function(c) return c.who == nil end), 3)
add("diary", "diary_fire_alone_2", "Allein am Lagerfeuer in {zone}.", fire(function(c) return c.who == nil end), 2)
add("diary", "diary_fire_alone_nozone", "Am Lagerfeuer gerastet, allein mit den Funken.",
  fire(function(c) return c.who == nil and c.zone == nil end), 4)
add("diary", "diary_zone_first", "Zum ersten Mal in {zone}.", kind("zone"), 2)
add("diary", "diary_zone_new", "Neues Land: {zone}.", kind("zone"), 1)
add("diary", "diary_subzone", "Entdeckt: {name}.", kind("subzone"), 2)
add("diary", "diary_subzone_way", "Unterwegs nach {name} gekommen.", kind("subzone"), 1)
add("diary", "diary_flight_npc", "Neuer Flugpunkt bei {npc}.", kind("flight"), 2)
add("diary", "diary_flight_zone", "Flugpunkt in {zone} entdeckt.", kind("flight"), 1)
add("diary", "diary_hearth", "Ruhestein gebunden: {bind}.", kind("hearth"), 2)
add("diary", "diary_hearth_home", "Neues Zuhause: {bind}.", kind("hearth"), 1)
add("diary", "diary_instance", "Hinein nach {inst}.", kind("instance"), 2)
add("diary", "diary_instance_enter", "{inst} betreten.", kind("instance"), 1)
add("diary", "diary_raid", "Mit dem Schlachtzug in {inst}.", kind("instance", function(c) return c.raid == true end), 3)
add("diary", "diary_encounter", "Boss {enc} bezwungen.", kind("encounter"), 2)
add("diary", "diary_guild_join", "Der Gilde „{guild}“ beigetreten.", kind("guild", function(c) return c.leave ~= true end), 2)
add("diary", "diary_guild_leave", "Die Gilde „{guild}“ verlassen.", kind("guild", function(c) return c.leave == true end), 2)

add("margin", "margin_fast_1", "{=duration} – schnellste Stufe!", kind("fastest"), 3)
add("margin", "margin_fast_2", "Stufe {=level} in {=duration} Wie im Rausch.", kind("fastest"), 1)
add("margin", "margin_fast_3", "Kaum angekommen, schon Stufe {=level} vorbei: {=duration}", kind("fastest"), 1)
add("margin", "margin_slow_1", "{=duration} – die längste.", kind("slowest"), 3)
add("margin", "margin_slow_2", "Stufe {=level} zog sich: {=duration}", kind("slowest"), 1)
add("margin", "margin_slow_3", "Auf Stufe {=level} verging die Zeit langsam: {=duration}", kind("slowest"), 1)

-- ctx.raceFile = info.raceFile; the two undead mottos are already in Texts.lua

local function race(r) return function(c) return c.raceFile == r end end
add("motto", "motto_scourge_3", "Was tot ist, kann nicht verloren gehen.", race("Scourge"), 3)
add("motto", "motto_orc_1", "Blut und Donner, Schritt für Schritt.", race("Orc"), 3)
add("motto", "motto_orc_2", "Stärke zeigt sich auf dem Weg.", race("Orc"), 3)
add("motto", "motto_tauren_1", "Die Erdmutter führt meine Hufe.", race("Tauren"), 3)
add("motto", "motto_tauren_2", "Weites Land, ruhiges Herz.", race("Tauren"), 3)
add("motto", "motto_troll_1", "Immer locker bleiben, Mann.", race("Troll"), 3)
add("motto", "motto_troll_2", "Die Loa sehen jeden Schritt.", race("Troll"), 3)
add("motto", "motto_human_1", "Für Ruhm und für das Licht.", race("Human"), 3)
add("motto", "motto_human_2", "Jeder Weg führt zurück nach Hause.", race("Human"), 3)
add("motto", "motto_dwarf_1", "Ein Bier am Ende jedes Weges.", race("Dwarf"), 3)
add("motto", "motto_dwarf_2", "Fest wie der Fels von Eisenschmiede.", race("Dwarf"), 3)
add("motto", "motto_nightelf_1", "Unter den Sternen ist Zeit genug.", race("NightElf"), 3)
add("motto", "motto_nightelf_2", "Elune wacht über die Reise.", race("NightElf"), 3)
add("motto", "motto_gnome_1", "Klein ist nur der erste Schritt.", race("Gnome"), 3)
add("motto", "motto_gnome_2", "Jedes Problem hat ein Zahnrad.", race("Gnome"), 3)
add("motto", "motto_any_3", "Die Straße ist das Ziel.")
add("motto", "motto_any_4", "Ein Tag, ein Schritt, eine Seite.")

-- riddle hints per medal (ctx.seal = medal id); no longer shown by the UI, kept for later use

local function seal(id) return function(c) return c.seal == id end end
add("seal", "seal_explorer", "von Land zu Land", seal("explorer"))
add("seal", "seal_pathfinder", "jeder Winkel zählt", seal("pathfinder"))
add("seal", "seal_continent", "jenseits des Meeres", seal("continent"))
add("seal", "seal_flightmaster", "neue Landeplätze", seal("flightmaster"))
add("seal", "seal_frequent_flyer", "hoch über dem Land", seal("frequent_flyer"))
add("seal", "seal_hunter", "viele Klingen gekreuzt", seal("hunter"))
add("seal", "seal_elite_hunter", "die Großen zuerst", seal("elite_hunter"))
add("seal", "seal_rare_hunter", "ein seltener Gegner", seal("rare_hunter"))
add("seal", "seal_close_win", "mit letzter Kraft", seal("close_win"))
add("seal", "seal_duel", "Klinge gegen Klinge", seal("duel"))
add("seal", "seal_quests", "ein dickes Questbuch", seal("quests"))
add("seal", "seal_reputation", "ein fremdes Banner", seal("reputation"))
add("seal", "seal_books", "zwischen zwei Buchdeckeln", seal("books"))
add("seal", "seal_profession", "mit eigenen Händen", seal("profession"))
add("seal", "seal_fortune", "ein voller Beutel", seal("fortune"))
add("seal", "seal_blue", "ein blauer Schimmer", seal("blue"))
add("seal", "seal_angler", "etwas zappelt an der Leine", seal("angler"))
add("seal", "seal_gatherer", "Kraut und Erz", seal("gatherer"))
add("seal", "seal_guild", "nicht mehr allein", seal("guild"))
add("seal", "seal_companions", "viele Gesichter", seal("companions"))
add("seal", "seal_social", "ein Winken hier, ein Lachen da", seal("social"))
add("seal", "seal_regular", "der Wirt kennt Euch", seal("regular"))
add("seal", "seal_campfire", "Funken in der Nacht", seal("campfire"))
add("seal", "seal_rested", "gut geschlafen", seal("rested"))
add("seal", "seal_hearth", "ein Dach über dem Kopf", seal("hearth"))
add("seal", "seal_tough", "zäh wie Leder", seal("tough"))
add("seal", "seal_flawless", "kein Fehltritt", seal("flawless"))
add("seal", "seal_unscathed", "ohne Kratzer", seal("unscathed"))
add("seal", "seal_dungeon", "unter der Erde", seal("dungeon"))
add("seal", "seal_boss", "ein Herr der Tiefe", seal("boss"))
add("seal", "seal_raid", "mit vierzig Gefährten", seal("raid"))
add("seal", "seal_mount", "auf vier Hufen", seal("mount"))
add("seal", "seal_plans", "eigene Wege", seal("plans"))
add("seal", "seal_level60", "ganz oben angekommen", seal("level60"))
