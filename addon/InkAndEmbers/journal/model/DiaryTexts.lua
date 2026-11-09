-- Diary text snippets: DiaryTexts.entry(facts, opts) -> { title, sub, body, short } | nil builds a first-person entry
-- from the facts of one day (Days.facts). Variant choice is deterministic per day; a template with a missing variable
-- falls through to the next variant.
-- Foreign names reach the text only via Texts.fill or Sanitize.display; templates are code, never SV data.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local DiaryTexts = {}
Journal.DiaryTexts = DiaryTexts

local floor, huge, max = math.floor, math.huge, math.max
local format, match = string.format, string.match

DiaryTexts.ROUTE_MAX = 4      -- max further zones in the "route" sentence
DiaryTexts.MATES_MAX = 3      -- max companions named
DiaryTexts.NAME_MAX = 48      -- bytes per name in lists (Sanitize.display truncates with "…")
DiaryTexts.SMALL_SECONDS = 15 * 60

-- locale scope "m.DiaryTexts" = the templates V (same keys) plus the words below; English in locales/enUS_model.lua.
-- Read only when an entry is written (TX[...]), never at load.
local TX -- locale proxy, created below after V

-- templates: {x} = raw value (inserted via Sanitize.display), {=x} = display-ready (number, code text, display list)

local V = {}
DiaryTexts.V = V -- German source (tests); the active language supplies TX[kind]

V.open = {
  "{zone}, {=when}. Der Tee war kalt, die Laune gut.",
  "{zone}, {=when}. Stiefel geschnürt und los.",
  "{zone} war {=when} mein Ausgangspunkt.",
  "{=When} ging es los. Startpunkt: {zone}.",
  "{zone} sah mich {=when} aufbrechen.",
  "{zone}, {=when}: Bündel gepackt, auf geht's.",
  "{=When} stand ich da und überlegte, wohin. Ringsum: {zone}.",
}
V.openNoZone = {
  "{=When} ging es los.",
  "{=When} habe ich das Buch aufgeschlagen und bin aufgebrochen.",
  "{=When} war ich wieder unterwegs.",
  "Der Tag fing {=when} an, ohne große Pläne.",
  "{=When} habe ich mein Bündel geschnürt.",
}
V.route = {
  "Danach ging es weiter: {=route}.",
  "Die Stationen danach: {=route}.",
  "Weiter ging es, Station für Station: {=route}.",
  "Meine Stiefel haben danach noch mehr gesehen: {=route}.",
  "Mit ein paar Umwegen ging es weiter: {=route}.",
  "{=route}: auch dort war ich heute noch.",
}
V.stay = {
  "Ich bin den ganzen Tag dort geblieben.",
  "Weiter weg hat es mich heute nicht gezogen.",
  "Die Gegend hat mich nicht losgelassen.",
  "Ich habe mich dort gründlich umgesehen, statt weiterzuziehen.",
}
V.instance = {
  "{inst} stand auch auf dem Plan. Wir haben es überlebt, die meisten jedenfalls.",
  "{inst} war dunkel und eng, aber wir kamen wieder heraus.",
  "Ein gewagter Abstecher: {inst}. Danach habe ich lange die Sonne genossen.",
  "{inst} hat uns ordentlich gefordert. Mehr dazu, wenn meine Hände nicht mehr zittern.",
}
V.killsTop = {
  "{=n} Gegner haben heute den Kürzeren gezogen. Am häufigsten erwischt hat es: {top} ({=topn}-mal).",
  "{=n} Gegner niedergestreckt. Ganz oben auf meiner Liste: {top}, {=topn}-mal.",
  "{=n} Gegner gezählt. Ganz vorn dabei: {top}, {=topn} an der Zahl.",
  "{top} wird mich nicht vermissen. {=topn} von ihnen lagen am Ende am Boden, insgesamt waren es {=n}.",
  "Meine Waffe hatte zu tun: {=n} Gegner. Vor allem diese hier: {top} ({=topn}-mal).",
  "{top} hat heute {=topn}-mal den Kürzeren gezogen, bei {=n} Gegnern insgesamt.",
}
V.kills = {
  "{=n} Gegner haben heute den Kürzeren gezogen.",
  "Ich habe {=n} Gegner besiegt, und zwar alle, die zählen.",
  "{=n} Gegner gezählt. Meine Waffe braucht dringend Pflege.",
  "Heute waren es {=n} Gegner. Ruhig war anders.",
}
V.killsOne = {
  "Ein einziger Kampf heute, kaum der Rede wert.",
  "Nur ein Gegner hat sich mir in den Weg gestellt. Er bereut es.",
  "Einmal kurz die Waffe gezogen, mehr nicht.",
  "Ein Kampf, ein Sieg. So mag ich das.",
}
V.killsFew = {
  "Nur {=n} kleine Rangeleien, sonst war es ruhig.",
  "{=n} Gegner, mehr nicht. Ein friedlicher Tag.",
  "Ein paar Gegner, genau {=n}. Nichts, was mich aufgehalten hätte.",
  "{=n}-mal musste ich die Waffe ziehen. Hätte schlimmer kommen können.",
}
V.rare = {
  "Ein seltener Gegner heute: {rare}. Selten genug, dass ich es aufschreibe.",
  "{rare} kreuzte meinen Weg. Für einen von uns war das ein schlechter Tag.",
  "Ein echter Brocken heute: {rare}.",
  "{rare} stand plötzlich vor mir. Jetzt liegt da nur noch Beute.",
  "{rare} ist gefallen. Das erzähle ich noch am Lagerfeuer.",
}
V.elite = {
  "{rare} war zäh. Ich war zäher.",
  "{rare} hat mir ordentlich zu schaffen gemacht.",
  "{rare} hat sich gewehrt, aber am Ende stand nur noch ich.",
  "Harter Gegner heute: {rare}. Ich habe alles gebraucht, was ich habe. Hat gereicht.",
}
V.boss = {
  "{rare} ist gefallen. Ich zittere immer noch ein bisschen.",
  "Besiegt: {rare}. Ich schreibe das lieber zweimal auf. Besiegt: {rare}.",
  "{rare} liegt. Mein Herz klopft noch.",
  "Ein großer Gegner heute: {rare}. Wir haben gewonnen, daran werde ich mich erinnern.",
}
V.deathEnemy = {
  "{killer} hat mich erwischt. Ich nenne es einen taktischen Rückzug ins Jenseits.",
  "Mein Bezwinger heute: {killer}. Peinlich, aber lehrreich.",
  "{killer} war heute stärker als ich. Notiz an mich: nicht noch einmal.",
  "Kurzer Besuch beim Geistheiler. Schuld war: {killer}.",
  "{killer} hat mich auf den Friedhof geschickt. Der Weg zurück war lang.",
}
V.deathFall = {
  "Ich bin gestürzt. Die Schwerkraft gewinnt eben immer.",
  "Ein Schritt zu weit, ein Sturz zu tief. Der Geistheiler kennt mich jetzt.",
  "Gestorben am Fuß einer Klippe. Ich hätte schwören können, da war noch Weg.",
  "Lektion des Tages: Abgründe sind tiefer, als sie aussehen.",
}
V.deathDrown = {
  "Ertrunken. Ich wusste, dass ich nicht ewig die Luft anhalten kann.",
  "Das Wasser hat gewonnen. Beim nächsten Mal tauche ich früher auf.",
  "Kurz zu lange unter Wasser geblieben. Der Geistheiler hat nicht nachgefragt.",
  "Ich bin ertrunken. Fische lachen nicht, aber sie hätten allen Grund dazu.",
}
V.deathFatigue = {
  "Zu weit hinausgeschwommen, bis die Kräfte nicht mehr reichten. Dumm von mir.",
  "Das offene Meer war größer als mein Mut. Und als meine Ausdauer.",
  "Ich bin so weit geschwommen, bis nichts mehr ging. Kein Ruhmesblatt.",
  "Erschöpft im tiefen Wasser gestorben. Nächstes Mal nehme ich ein Boot.",
}
V.deathFire = {
  "Ich habe mich verbrannt. Gründlich.",
  "Feuer ist warm, bis es zu warm ist. Ich weiß das jetzt.",
  "Zu nah an der Glut gestanden. Der Geistheiler roch Rauch.",
  "Ich bin verbrannt. Wenigstens war mir dabei nicht kalt.",
}
V.death = {
  "Einmal gestorben. Wie genau, will ich gar nicht wissen.",
  "Ich lag kurz im Staub. Aufgestanden bin ich trotzdem.",
  "Ein Tod heute. Der Geistheiler und ich sind inzwischen per Du.",
  "Gestorben bin ich auch. Es passiert eben.",
}
V.deathsMore = {
  "Insgesamt {=n} Tode heute. Der Friedhof kennt mich mit Namen.",
  "Am Ende waren es {=n} Tode. Ich zähle lieber nicht nach.",
  "{=n}-mal gestorben. Das Grab wird langsam gemütlich.",
  "Es blieb nicht bei einem: {=n} Tode. Morgen bin ich vorsichtiger.",
}
V.questsNamed = {
  "{=n} Quests erledigt, darunter „{quest}“.",
  "Ich habe {=n} Aufgaben abgehakt. Im Kopf geblieben ist mir „{quest}“.",
  "{=n} Quests abgegeben. „{quest}“ war die letzte davon, und die Belohnung kam gerade recht.",
  "Für {=n} Leute habe ich heute etwas erledigt, zuletzt „{quest}“.",
  "Die Liste wurde kürzer: {=n} Aufgaben, zuletzt „{quest}“.",
}
V.questOneNamed = {
  "Eine Aufgabe erledigt: „{quest}“.",
  "Nur „{quest}“ abgegeben, aber immerhin.",
  "„{quest}“ ist erledigt. Eine weniger.",
  "Heute habe ich „{quest}“ abgeschlossen.",
}
V.quests = {
  "{=n} Quests erledigt.",
  "Ich habe {=n} Aufgaben abgehakt.",
  "{=n} Quests abgegeben. Die Leute hier haben viele Sorgen.",
  "Die Liste wurde um {=n} Aufgaben kürzer.",
}
V.questOne = {
  "Eine Quest erledigt.",
  "Eine Aufgabe abgegeben, mehr nicht.",
  "Immerhin eine Quest geschafft.",
  "Eine Quest weniger auf der Liste.",
}
V.loot = {
  "Bester Fund des Tages: {item}.",
  "Neu im Rucksack: {item}. Gefällt mir.",
  "{item} gehört jetzt mir.",
  "{item} lag einfach da. Eingepackt, bevor es sich jemand anders überlegt.",
  "Mein Fundstück heute: {item}. Passt gut zu mir.",
}
V.lootEpic = {
  "Fund des Tages: {item}. Ich musste zweimal hinsehen.",
  "{item}! Ich habe es dreimal angefasst, um sicherzugehen.",
  "{item} fiel mir heute in die Hände. Ich grinse immer noch.",
  "{item} ist meins. Das schreibe ich in Großbuchstaben, nur im Kopf.",
}
V.lootCount = {
  "{=n} brauchbare Fundstücke eingesteckt.",
  "Mein Rucksack ist um {=n} nützliche Dinge schwerer.",
  "{=n} Fundstücke, die sich sehen lassen können.",
  "Ich habe {=n} gute Sachen aufgesammelt.",
}
V.level = {
  "Stufe {=lv} erreicht. Ich fühle mich ein kleines bisschen stärker.",
  "Ab heute Stufe {=lv}. Das wird gefeiert, später.",
  "Stufe {=lv}! Die Rüstung sitzt gleich besser.",
  "Ich bin jetzt Stufe {=lv}. Langsam merke ich den Unterschied.",
  "Stufe {=lv}. Ich habe kurz innegehalten und gelächelt.",
}
V.levels = {
  "Gleich {=k} Stufen geschafft, jetzt bin ich {=lv}.",
  "{=k} Stufen an einem Tag, am Ende Stufe {=lv}. Nicht schlecht.",
  "Heute ging es {=k} Stufen hinauf, bis {=lv}.",
  "Stufe {=lv} am Abend, {=k} mehr als am Morgen.",
}
V.mate = {
  "{mate} ging ein Stück des Weges mit mir.",
  "{mate} war heute an meiner Seite. Gute Gesellschaft.",
  "{mate} und ich: zu zweit ging alles etwas leichter.",
  "{mate} hat mich begleitet und kaum gemeckert.",
  "Mein Reisegefährte heute: {mate}. Zu zweit reist es sich besser.",
}
V.mates = {
  "Unterwegs in Gesellschaft: {=mates}.",
  "{=mates} haben mich ein Stück begleitet. Allein wäre es stiller gewesen.",
  "Heute mit dabei: {=mates}.",
  "Meine Begleiter: {=mates}. Die Zeit ging schnell vorbei.",
}
-- campfire: {=who} = display-ready "Kuno und Mira (2)", {=again} = "Kuno kenne ich schon vom Feuer in Westfall."
V.campfire = {
  "{zone}: Am Lagerfeuer saß ich mit {=who} zusammen.",
  "{zone}: Rast am Lagerfeuer, mit {=who} an meiner Seite.",
  "{zone}: Das Feuer war warm, die Gesellschaft von {=who} noch wärmer.",
  "{zone}: Ich habe am Feuer gerastet, in Gesellschaft von {=who}.",
}
V.campfireNoZone = {
  "Am Lagerfeuer saß ich mit {=who} zusammen.",
  "Eine Rast am Feuer, in Gesellschaft von {=who}.",
  "Rast am Lagerfeuer, mit {=who} an meiner Seite.",
  "Das Feuer war warm, die Gesellschaft von {=who} noch wärmer.",
}
V.campfireAlone = {
  "{zone}: Am Lagerfeuer habe ich allein gesessen, nur die Funken leisteten mir Gesellschaft.",
  "{zone}: Allein am Lagerfeuer. Auch das tut gut.",
  "{zone}: Am Feuer gerastet, ganz für mich.",
  "{zone}: Ein stilles Feuer, nur ich und das Knistern.",
}
V.campfireAloneNoZone = {
  "Am Lagerfeuer habe ich allein gesessen und den Funken zugesehen.",
  "Eine Rast am Feuer, ganz für mich.",
  "Allein am Lagerfeuer. Auch das tut gut.",
  "Ein stilles Feuer, nur ich und das Knistern.",
}
V.campfireMore = {
  "Insgesamt saß ich {=n}-mal am Lagerfeuer.",
  "{=n} Feuer an einem Tag, das nenne ich gemütlich.",
  "Am Lagerfeuer war ich an diesem Tag {=n}-mal.",
  "Zum Feuer zog es mich heute {=n}-mal.",
}
V.campfireAgain = {
  "{=again}",
  "Ein bekanntes Gesicht war auch dabei. {=again}",
  "Wiedergesehen: {=again}",
  "Das Feuer brachte uns wieder zusammen. {=again}",
}

V.seal = {
  "Eine Medaille gab es auch: „{seal}“.",
  "Neu in meiner Sammlung: die Medaille „{seal}“.",
  "„{seal}“, so heißt meine neue Medaille. Ich habe sie gleich poliert.",
  "Für „{seal}“ gab es eine Medaille. Ich tue so, als wäre das nichts Besonderes.",
}
V.seals = {
  "Gleich {=n} Medaillen heute, darunter „{seal}“.",
  "{=n} neue Medaillen, eine davon „{seal}“. Mein Gürtel wird schwer.",
  "Ich habe {=n} Medaillen verdient, zuerst „{seal}“.",
  "Medaillen heute: {=n}. Am meisten freut mich „{seal}“.",
}
V.plan = {
  "Ein To Do erledigt: {plan}.",
  "Von meiner Liste gestrichen: {plan}.",
  "Endlich erledigt: {plan}.",
  "Ich hatte mir vorgenommen: {plan}. Geschafft.",
}
-- notes of the day: {=notes} = quoted title(s), each via Sanitize.display
V.notes = {
  "Notiert: {=notes}.",
  "Ins Buch geschrieben: {=notes}.",
  "Für später festgehalten: {=notes}.",
  "Eine Zeile für mich: {=notes}.",
}
V.close = {
  "Jetzt ist Schluss für heute.",
  "Genug für einen Tag. Das Lager ruft.",
  "Die Feder wird stumpf, ich mache Schluss.",
  "Morgen geht es weiter.",
  "Zeit fürs Lagerfeuer.",
  "Nach {=dur} unterwegs reicht es mir.",
  "Die Beine sind schwer. Gute Nacht.",
}
V.closeLate = {
  "Viel zu spät geworden. Schon wieder.",
  "Draußen ist es längst dunkel. Ich sollte schlafen.",
  "Nach {=dur} unterwegs fallen mir die Augen zu.",
  "Die Kerze ist fast heruntergebrannt. Gute Nacht.",
}
V.short = {
  "{zone}, {=when}: nur kurz vorbeigeschaut. Nichts Besonderes passiert, und das ist auch mal schön.",
  "{zone}, {=when}, nur ein paar Schritte. Mehr gibt es nicht zu berichten.",
  "Ein kurzer Besuch, {=when}: {zone}. Dann rief das echte Leben.",
  "{zone} sah mich {=when} nur kurz. Ich habe mich umgesehen und bin wieder gegangen.",
}
V.shortNoZone = {
  "{=When} nur kurz hereingeschaut. Nichts Besonderes passiert, und das ist auch mal schön.",
  "Ein kurzer Tag. Mehr als ein paar Schritte waren nicht drin.",
  "{=When} kurz vorbeigeschaut, dann rief das echte Leben.",
  "Heute ist wenig passiert. Auch das gehört dazu.",
}

ns.Locale.ns("m.DiaryTexts", V)
TX = ns.Locale.ns("m.DiaryTexts", {
  weekdays = { "Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag" },
  months = { "Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember" },
  -- daytime words per DAYTIME row: { sentence start, mid-sentence }
  daytime = {
    { "Spät in der Nacht", "spät in der Nacht" },
    { "Früh am Morgen", "früh am Morgen" },
    { "Am Vormittag", "am Vormittag" },
    { "Mittags", "mittags" },
    { "Am Nachmittag", "am Nachmittag" },
    { "Am Abend", "am Abend" },
    { "Spät am Abend", "spät am Abend" },
  },
  date = "{d}. {month} {y}",
  dateWeekday = "{wd}, {date}",
  noDate = "Ein Tag ohne Datum",
  subDay = "{n}. Reisetag · {dur} unterwegs",
  subNoDay = "{dur} unterwegs",
  little = "Heute ist wenig passiert.",
  probe = " (Probe)",
  andWord = " und ",
  quoted = "„%s“",
  durHour = "gut einer Stunde",
  durHalf = "anderthalb Stunden",
  durHours = "gut %s Stunden",
  numwords = { "einer", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf" },
})

-- daytime: from hour (words in TX.daytime, same row)
local DAYTIME = { 0, 5, 9, 12, 14, 18, 22 }

local function finite(v)
  return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local function hash(s)
  local T = Journal.Texts
  if T and T.hash then return T.hash(s) end
  local h = 5381
  for i = 1, #s do h = (h * 33 + string.byte(s, i)) % 2147483647 end
  return h
end

local function fill(tpl, vars)
  local T = Journal.Texts
  return T and T.fill(tpl, vars) or nil
end

local function int(n)
  local T = Journal.Texts
  return T and T.int(n) or tostring(n)
end

-- deterministic: first variant from date + kind, then in order until one fills completely
local function pick(seed, kind, vars)
  local list = TX[kind]
  if type(list) ~= "table" or #list == 0 then return nil end
  local start = hash(seed .. ":" .. kind) % #list
  for i = 0, #list - 1 do
    local s = fill(list[(start + i) % #list + 1], vars)
    if s and s ~= "" then return s end
  end
  return nil
end

-- name for lists (display; companions as "Vorname Nachname" on Forever, else without realm, Names.mateName); nil if nothing
-- readable remains
local function mateRaw(v)
  local N = ns.Names
  if N then return N.mateName(v) end
  return match(v, "^([^%-]+)") or v
end

local function shown(v, dropRealm)
  if type(v) ~= "string" then return nil end
  if dropRealm then v = mateRaw(v) or v end
  local S = ns.Sanitize
  return S and S.display(v, DiaryTexts.NAME_MAX) or nil
end

-- "A", "A und B", "A, B und C" from display texts
local function joinList(list)
  local n = #list
  if n == 0 then return nil end
  if n == 1 then return list[1] end
  return table.concat(list, ", ", 1, n - 1) .. TX.andWord .. list[n]
end

local function daytime(clock)
  local h = type(clock) == "table" and tonumber(clock[1]) or nil
  if not finite(h) then return nil end
  local row = 1
  for i, from in ipairs(DAYTIME) do if h >= from then row = i end end
  return TX.daytime[row]
end

function DiaryTexts.duration(seconds) -- via Fmt.duration, rounded to whole minutes
  seconds = finite(seconds) and seconds or 0
  return ns.Journal.Fmt.duration(floor(seconds / 60 + 0.5) * 60)
end

-- duration as words for the closing ("eine knappe Stunde", "gut drei Stunden")
local function durWords(seconds)
  local m = floor((finite(seconds) and seconds or 0) / 60)
  if m < 45 then return nil end
  if m < 75 then return TX.durHour end
  if m < 110 then return TX.durHalf end
  local h = max(2, floor(m / 60))
  local w = TX.numwords[h] or int(h)
  return TX("durHours", w)
end

function DiaryTexts.dateTitle(f)
  if type(f) ~= "table" then return "" end
  local d, m, y = tonumber(f.day), tonumber(f.month), tonumber(f.year)
  local months = TX.months
  if not (d and m and y and months[m]) then return TX.noDate end
  local wd = finite(f.key) and TX.weekdays[(floor(f.key) + 4) % 7 + 1] or nil -- day 0 (1970-01-01) was a Thursday
  local date = TX("date", { d = format("%d", d), month = months[m], y = format("%d", y) })
  return wd and TX("dateWeekday", { wd = wd, date = date }) or date
end

local DEATH_KIND = { fall = "deathFall", drown = "deathDrown", fatigue = "deathFatigue", fire = "deathFire", lava = "deathFire" }

function DiaryTexts.entry(f, opts)
  if type(f) ~= "table" then return nil end
  opts = type(opts) == "table" and opts or {}
  local seed = format("diary:%s-%s-%s", tostring(f.year), tostring(f.month), tostring(f.day))
  local dt = daytime(f.firstClock) or TX.daytime[4]
  local base = { When = dt[1], when = dt[2] }
  local function with(extra)
    local v = { When = base.When, when = base.when }
    for k, x in pairs(extra or {}) do v[k] = x end
    return v
  end

  local zones = type(f.zones) == "table" and f.zones or {}
  local firstZone = zones[1] and zones[1].name or nil
  local paras, cur = {}, {}
  local function add(s) if s then cur[#cur + 1] = s end end
  local function para()
    if #cur > 0 then paras[#paras + 1] = table.concat(cur, " ") end
    cur = {}
  end

  local durText = DiaryTexts.duration(f.seconds)
  local sub = finite(opts.dayNo) and TX("subDay", { n = int(opts.dayNo), dur = durText }) or TX("subNoDay", { dur = durText })
  local res = { title = DiaryTexts.dateTitle(f), sub = sub }

  local kills = type(f.kills) == "table" and f.kills or { total = 0 }
  local deaths = type(f.deaths) == "table" and f.deaths or { count = 0, list = {} }
  local quests = type(f.quests) == "table" and f.quests or { count = 0 }
  local loot = type(f.loot) == "table" and f.loot or { count = 0 }
  local levels = type(f.levels) == "table" and f.levels or {}
  local mates = type(f.companions) == "table" and type(f.companions.list) == "table" and f.companions.list or {}
  local seals = type(f.seals) == "table" and f.seals or {}
  local plans = type(f.plansDone) == "table" and f.plansDone or {}
  local notes = type(f.notes) == "table" and f.notes or {}
  local rares = type(f.rares) == "table" and f.rares or {}
  local insts = type(f.instances) == "table" and f.instances or {}

  local events = (kills.total or 0) + (deaths.count or 0) + (quests.count or 0) + (loot.count or 0) + #levels + #mates + #seals + #plans
    + #insts + #notes + (type(f.campfires) == "table" and tonumber(f.campfires.count) or 0)
  if f.empty or (events == 0 and #zones <= 1) or (events == 0 and (tonumber(f.seconds) or 0) < DiaryTexts.SMALL_SECONDS) then
    local s = firstZone and pick(seed, "short", with({ zone = firstZone })) or nil
    res.body = s or pick(seed, "shortNoZone", with()) or TX.little
    res.short = true
    return res
  end

  add(firstZone and pick(seed, "open", with({ zone = firstZone })) or nil)
  if #cur == 0 then add(pick(seed, "openNoZone", with())) end
  local route = {}
  for i = 2, #zones do
    if #route >= DiaryTexts.ROUTE_MAX then break end
    local n = shown(zones[i].name)
    if n then route[#route + 1] = n end
  end
  if #route > 0 then
    add(pick(seed, "route", { route = joinList(route) }))
  elseif #zones == 1 and (tonumber(f.seconds) or 0) >= 3600 then
    add(pick(seed, "stay", {}))
  end
  for _, inst in ipairs(insts) do
    if inst.name then
      add(pick(seed, "instance", { inst = inst.name }))
      break
    end
  end
  para()

  local n = tonumber(kills.total) or 0
  if n == 1 then
    add(pick(seed, "killsOne", {}))
  elseif n > 1 and n < 5 then
    add(pick(seed, "killsFew", { n = n }))
  elseif n >= 5 then
    local top = kills.top
    local s = (type(top) == "table" and top.name and (tonumber(top.n) or 0) >= 3)
      and pick(seed, "killsTop", { n = n, top = top.name, topn = top.n }) or nil
    add(s or pick(seed, "kills", { n = n }))
  end
  local r = rares[1]
  if type(r) == "table" and r.name then
    add(pick(seed, (r.cls == "boss" and "boss") or (r.cls == "elite" and "elite") or "rare", { rare = r.name }))
  end
  local dc = tonumber(deaths.count) or 0
  if dc > 0 then
    local d1 = type(deaths.list) == "table" and deaths.list[1] or {}
    local s
    if d1.cause == "enemy" and d1.killer then s = pick(seed, "deathEnemy", { killer = d1.killer }) end
    if not s and DEATH_KIND[d1.cause] then s = pick(seed, DEATH_KIND[d1.cause], {}) end
    -- without a known cause "death" speaks of exactly one death: with several only the total is shown
    if not s and dc == 1 then s = pick(seed, "death", {}) end
    add(s)
    if dc > 1 then add(pick(seed, "deathsMore", { n = dc })) end
  end
  para()

  local qn = tonumber(quests.count) or 0
  local qt = type(quests.named) == "table" and quests.named.title or nil
  if qn == 1 then
    add((qt and pick(seed, "questOneNamed", { quest = qt })) or pick(seed, "questOne", {}))
  elseif qn > 1 then
    add((qt and pick(seed, "questsNamed", { n = qn, quest = qt })) or pick(seed, "quests", { n = qn }))
  end
  local best = loot.best
  if type(best) == "table" and best.name then
    add(pick(seed, (tonumber(best.quality) or 0) >= 4 and "lootEpic" or "loot", { item = best.name }))
  elseif (tonumber(loot.count) or 0) > 1 then
    add(pick(seed, "lootCount", { n = loot.count }))
  end
  if #levels == 1 or (#levels > 1 and f.levelEnd) then
    local lv = f.levelEnd or levels[1].level
    if #levels == 1 then add(pick(seed, "level", { lv = lv })) else add(pick(seed, "levels", { lv = lv, k = #levels })) end
  end
  para()

  local names = {}
  for _, p in ipairs(mates) do
    if #names >= DiaryTexts.MATES_MAX then break end
    local s = shown(p.name, true)
    if s then names[#names + 1] = s end
  end
  if #names == 1 then
    add(pick(seed, "mate", { mate = mateRaw(mates[1].name or "") or mates[1].name }))
  elseif #names > 1 then
    add(pick(seed, "mates", { mates = joinList(names) }))
  end
  -- campfire: first entry of the day (zone, company, recognition), with the count if there are several
  local fires = type(f.campfires) == "table" and f.campfires or { count = 0, list = {} }
  local fire = type(fires.list) == "table" and fires.list[1] or nil
  if fire then
    local s
    if fire.who then
      s = (fire.zone and pick(seed, "campfire", { zone = fire.zone, who = fire.who })) or pick(seed, "campfireNoZone", { who = fire.who })
    else
      s = (fire.zone and pick(seed, "campfireAlone", { zone = fire.zone })) or pick(seed, "campfireAloneNoZone", {})
    end
    if s and fire.sim then s = s .. TX.probe end -- trial round from the retail simulation
    add(s)
    if fire.again then add(pick(seed, "campfireAgain", { again = fire.again })) end
    if (tonumber(fires.count) or 0) > 1 then add(pick(seed, "campfireMore", { n = fires.count })) end
  end
  local sealTitle = seals[1] and seals[1].title or nil
  if #seals == 1 and sealTitle then
    add(pick(seed, "seal", { seal = sealTitle }))
  elseif #seals > 1 and sealTitle then
    add(pick(seed, "seals", { n = #seals, seal = sealTitle }))
  end
  for _, p in ipairs(plans) do
    if p.text then
      add(pick(seed, "plan", { plan = p.text }))
      break
    end
  end
  local noted = {}
  for _, n in ipairs(notes) do
    local s = shown(n.title)
    if s then noted[#noted + 1] = TX("quoted", s) end
  end
  if #noted > 0 then add(pick(seed, "notes", { notes = joinList(noted) })) end
  para()

  local late = type(f.lastClock) == "table" and ((tonumber(f.lastClock[1]) or 12) >= 23 or (tonumber(f.lastClock[1]) or 12) < 4)
  local dur = durWords(f.seconds)
  local closing = pick(seed, late and "closeLate" or "close", { dur = dur })
  add(closing)
  para()

  res.body = table.concat(paras, "\n\n")
  if res.body == "" then
    res.body = pick(seed, "shortNoZone", with()) or TX.little
    res.short = true
  end
  return res
end
