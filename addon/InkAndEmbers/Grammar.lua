-- Place names in sentences: preposition + article per place, German (deDE) and English (enUS); other languages get the
-- name unchanged (their text blocks are written case-neutral, docs/i18n.md). Loads in the core right after Names.lua
-- (GrammarLexicon.lua first), before the collectors, the journal and the modules (Campfire), so all of them can use it. Reads no game data; names come in already sanitized and only constant words
-- (prepositions, articles) are added.
--   Grammar.place(name, case, opts) -> phrase, known
--     case: "in" (where: "im Alteracgebirge" | "in the Barrens"), "to" (where to: "ins Brachland" | "to the Barrens"),
--     "from" ("aus dem Brachland" | "from the Barrens"), "nom" (inside a sentence, article in lower case: "das Brachland"),
--     "acc", "dat", or a preposition word ("von", "seit", "über", "of", ...).
--     opts = { lang = "deDE" | "enUS" (default Locale.active), kind = "zone" | "dungeon" | "point", mapID, upper = true }
--     known = false: neither lexicon nor a safe rule knew the name; the phrase then is a case-neutral apposition
--     ("im Gebiet X").
--   Grammar.info(name, opts) -> { g, core, the, island, known } | nil
--   Grammar.fill(tpl, get, places, lang) -> text, missing: fills "{key}" / "{=key}"; get(key, eq) -> string | nil;
--     places[key] = kind. In German and English a preposition directly before a place placeholder ("in {zone}",
--     "nach {to}", "von {from}") is replaced together with the name by Grammar.place; in English a bare place
--     placeholder gets its "the". The placeholders themselves stay the same in every language.
local _, ns = ...

local Grammar = {}
ns.Grammar = Grammar

local type, ipairs = type, ipairs
local find, sub, lower, upper, match, gsub, byte = string.find, string.sub, string.lower, string.upper, string.match,
  string.gsub, string.byte

-- lexicon index -----------------------------------------------------------------------------------------------------------

local index = nil -- index[lang].byName[name] = { g, island }; index[lang].byId[mapID] = { g, island }

local function parseClass(c)
  if type(c) ~= "string" then return nil end
  local island = sub(c, -1) == "@"
  if island then c = sub(c, 1, -2) end
  return c, island
end

local function build()
  index = { de = { byName = {}, byId = {} }, en = { byName = {}, byId = {} } }
  local rows = type(ns.GrammarLexicon) == "table" and ns.GrammarLexicon or {}
  for _, row in ipairs(rows) do
    for _, lang in ipairs({ "de", "en" }) do
      local list = row[lang]
      if type(list) == "table" then
        for i = 1, #list - 1, 2 do
          local name, g, island = list[i], parseClass(list[i + 1])
          if type(name) == "string" and g then
            local e = { g = g, island = island }
            index[lang].byName[name] = index[lang].byName[name] or e
            if i == 1 then
              for _, id in ipairs(row.ids or {}) do index[lang].byId[id] = index[lang].byId[id] or e end
            end
          end
        end
      end
    end
  end
end

function Grammar.reset() index = nil end

local function lex(lang)
  if not index then build() end
  return index[lang]
end

local LANG = { deDE = "de", enUS = "en", enGB = "en", frFR = "fr", esES = "es", esMX = "es", itIT = "it", ptBR = "pt",
  ruRU = "ru" }

local function langOf(opts)
  local l = type(opts) == "table" and opts.lang or (ns.Locale and ns.Locale.active)
  return LANG[l]
end
Grammar.langOf = langOf

-- German rules for unknown names (G3) -----------------------------------------------------------------------------------
-- head word = last word before an attribute ("von", "des", "der", ...) or the last part after a hyphen; longest ending wins

local SUFFIX = {
  -- plural first (longer endings)
  { "länder", "pl" }, { "marschen", "pl" }, { "inseln", "pl" }, { "höhlen", "pl" }, { "minen", "pl" }, { "tiefen", "pl" },
  { "ruinen", "pl" }, { "hallen", "pl" }, { "lande", "pl" }, { "felder", "pl" }, { "berge", "pl" }, { "wälder", "pl" },
  { "sümpfe", "pl" }, { "gärten", "pl" }, { "reiche", "pl" },
  -- neuter
  { "gebirge", "n" }, { "hochland", "n" }, { "land", "n" }, { "tal", "n" }, { "moor", "n" }, { "dorf", "n" },
  { "becken", "n" }, { "kloster", "n" }, { "lager", "n" }, { "ufer", "n" }, { "verlies", "n" }, { "plateau", "n" },
  { "dickicht", "n" }, { "gehölz", "n" }, { "riff", "n" }, { "feld", "n" }, { "tor", "n" }, { "nest", "n" }, { "reich", "n" },
  -- masculine
  { "wald", "m" }, { "hain", "m" }, { "pass", "m" }, { "sumpf", "m" }, { "hort", "m" }, { "krater", "m" },
  { "hafen", "m" }, { "abgrund", "m" }, { "turm", "m" }, { "gipfel", "m" }, { "strand", "m" }, { "posten", "m" },
  { "friedhof", "m" }, { "hof", "m" }, { "tempel", "m" }, { "kral", "m" }, { "schlund", "m" }, { "kamm", "m" },
  { "steinbruch", "m" }, { "bruch", "m" }, { "see", "m" }, { "weg", "m" }, { "wall", "m" }, { "kessel", "m" },
  { "rücken", "m" }, { "park", "m" }, { "platz", "m" }, { "markt", "m" },
  -- feminine
  { "küste", "f" }, { "ebene", "f" }, { "insel", "f" }, { "schlucht", "f" }, { "feste", "f" }, { "höhle", "f" },
  { "steppe", "f" }, { "mine", "f" }, { "grotte", "f" }, { "bucht", "f" }, { "abtei", "f" }, { "kapelle", "f" },
  { "kathedrale", "f" }, { "festung", "f" }, { "halle", "f" }, { "spitze", "f" }, { "tiefe", "f" }, { "zuflucht", "f" },
  { "lichtung", "f" }, { "oase", "f" }, { "quelle", "f" }, { "mühle", "f" }, { "ruine", "f" }, { "siedlung", "f" },
  { "brücke", "f" }, { "wiese", "f" }, { "senke", "f" }, { "klippe", "f" }, { "warte", "f" }, { "kluft", "f" },
  { "grube", "f" }, { "heide", "f" }, { "lagune", "f" }, { "wacht", "f" }, { "burg", "f" }, { "stadt", "f" },
}
table.sort(SUFFIX, function(a, b) return #a[1] > #b[1] end)

-- attribute words: everything from here on is not declined ("Sümpfe des Elends", "Wald von Elwynn")
local ATTR = { von = true, vom = true, des = true, der = true, zu = true, zum = true, zur = true, am = true, im = true,
  bei = true, auf = true, ["an"] = true }

local function words(s)
  local list = {}
  for w in string.gmatch(s, "%S+") do list[#list + 1] = w end
  return list
end

-- splits the core into the declinable front (adjectives + head noun) and the rest (attribute, unchanged)
local function splitHead(core)
  local list = words(core)
  local front, rest = {}, {}
  local inRest = false
  for i, w in ipairs(list) do
    if not inRest and i > 1 and ATTR[w] then inRest = true end
    if inRest then rest[#rest + 1] = w else front[#front + 1] = w end
  end
  return front, rest
end

local function ruleClass(core)
  local front = splitHead(core)
  local head = front[#front]
  if not head then return nil end
  -- "Burg X" (Burg Schattenfang): a castle with its name, feminine ("in der Burg Schattenfang")
  if #front >= 2 and front[1] == "Burg" then return "f" end
  -- Saxon genitive ("Tarrens Mühle", "Onyxias Hort"): a name, no article. Not an adjective in "-es" ("Dunkles Moor",
  -- "Verfluchtes Land"): that one is declined and the last word decides by its ending
  if #front == 2 and sub(front[1], -1) == "s" and sub(front[1], -2) ~= "es" and not find(front[1], "^%l") then
    return "-"
  end
  local last = match(head, "%-([^%-]+)$") or head
  local w = lower(last)
  for _, r in ipairs(SUFFIX) do
    local suf = r[1]
    if #w >= #suf and sub(w, -#suf) == suf then
      -- a single word that IS the ending (e.g. "Tor") counts; a short proper name only ending in it does not
      if #w == #suf or #w >= #suf + 3 then return r[2] end
    end
  end
  -- one single word without a known ending: a proper name without an article (Westfall, Brill, Gnomeregan)
  if #front == 1 and #(words(core)) == 1 then return "-" end
  return nil
end

-- German declension after the definite article (weak): case "nom" | "acc" | "dat"
local function decline(core, g, case)
  if g == "-" then return core end
  local front, rest = splitHead(core)
  local n = #front
  for i = 1, n - 1 do
    local w = front[i]
    local stem = match(w, "^(.-)en$") or match(w, "^(.-)er$") or match(w, "^(.-)es$") or match(w, "^(.-)e$")
    if stem and stem ~= "" and #w >= 4 then
      local ending = "e"
      if case == "dat" or g == "pl" or (case == "acc" and g == "m") then ending = "en" end
      front[i] = stem .. ending
    end
  end
  if case == "dat" and g == "pl" and n >= 1 then
    local head = front[n]
    local tail = sub(head, -1)
    if tail ~= "n" and tail ~= "s" then front[n] = head .. "n" end
  end
  local out = table.concat(front, " ")
  if #rest > 0 then out = out .. " " .. table.concat(rest, " ") end
  return out
end
Grammar.decline = decline

-- info --------------------------------------------------------------------------------------------------------------------

local DE_ART = { Das = "n", Der = "m", Die = "f", Den = "pl" }

local function infoOne(name, opts, lang)
  local L = lex(lang)
  local byIdE = opts.mapID and L.byId[opts.mapID] or nil
  if lang == "en" then
    local core = match(name, "^The (.+)$") or match(name, "^the (.+)$")
    local e = L.byName[name] or (core and L.byName[core]) or nil
    if e then return { g = e.g, the = e.g == "the", island = e.island, core = core or name, known = true } end
    if core then return { g = "the", the = true, core = core, known = true } end
    if byIdE then return { g = byIdE.g, the = byIdE.g == "the", island = byIdE.island, core = name, known = true } end
    -- rule: "Swamp of Sorrows", "Ruins of ..." and plural landscapes take "the"
    local lastWord = match(name, "(%S+)$") or name
    local THE = { Mountains = true, Lands = true, Plaguelands = true, Highlands = true, Barrens = true, Hinterlands = true,
      Wetlands = true, Badlands = true, Steppes = true, Islands = true, Isles = true, Caverns = true, Marshes = true }
    if find(name, " of ", 1, true) or THE[lastWord] then return { g = "the", the = true, core = name, known = true } end
    return { g = "-", the = false, core = name, known = true }
  end
  -- German: article of the client name first ("Das Brachland", "Die Todesminen")
  local art, rest = match(name, "^(D%l%l) (.+)$")
  local artG = art and DE_ART[art] or nil
  local core = artG and rest or name
  local e = L.byName[name] or L.byName[core]
  if e then return { g = e.g, island = e.island, core = core, known = true, article = artG ~= nil } end
  if artG == "n" or artG == "m" then return { g = artG, core = core, known = true, article = true } end
  if artG == "f" then
    -- "Die ...": feminine or plural, decided by the ending (plural endings), else feminine
    -- after "Die" an adjective in "-en" is the plural form ("Die Östlichen Königreiche"); feminine would end in "-e"
    local g = ruleClass(core)
    if g ~= "pl" then
      local front = splitHead(core)
      for i = 1, #front - 1 do
        if sub(front[i], -2) == "en" then g = "pl" end
      end
    end
    return { g = (g == "pl") and "pl" or "f", core = core, known = true, article = true }
  end
  if byIdE then return { g = byIdE.g, island = byIdE.island, core = core, known = true } end
  local g = ruleClass(core)
  if g then return { g = g, core = core, known = true } end
  return { g = nil, core = core, known = false }
end

function Grammar.info(name, opts)
  if type(name) ~= "string" or name == "" then return nil end
  opts = type(opts) == "table" and opts or {}
  local lang = langOf(opts)
  if lang ~= "de" and lang ~= "en" then return nil end
  local info
  -- "Sturmwind, Elwynn" (flight points, places with their zone): the part before the comma decides, the rest follows
  local head, tail = match(name, "^(.-)(, .+)$")
  if head and head ~= "" and not lex(lang).byName[name] then
    info = infoOne(head, opts, lang)
    info.tail = tail
  else
    info = infoOne(name, opts, lang)
  end
  -- a point (town, flight point) without a known class is a proper name without an article
  if not info.known and opts.kind == "point" then info.g, info.known = "-", true end
  -- German coasts take "an": "an der Dunkelküste", "zur Dunkelküste", "von der Dunkelküste"
  if lang == "de" and info.g and info.g ~= "-" and not info.island then
    local front = splitHead(info.core)
    local head = front[#front]
    if head and sub(lower(head), -#"küste") == "küste" then info.coast = true end
  end
  return info
end

-- German phrase -----------------------------------------------------------------------------------------------------------

local ART = {
  m = { nom = "der", acc = "den", dat = "dem" },
  f = { nom = "die", acc = "die", dat = "der" },
  n = { nom = "das", acc = "das", dat = "dem" },
  pl = { nom = "die", acc = "die", dat = "den" },
}
local CONTRACT = {
  ["in dem"] = "im", ["in das"] = "ins", ["an dem"] = "am", ["an das"] = "ans", ["von dem"] = "vom", ["zu dem"] = "zum",
  ["zu der"] = "zur", ["bei dem"] = "beim",
}
local DE_DAT = { an = true, aus = true, bei = true, mit = true, seit = true, von = true, zu = true, nahe = true,
  ["gegenüber"] = true, ab = true }
local DE_ACC = { ["über"] = true, durch = true, ["für"] = true, um = true, gegen = true, ohne = true, entlang = true }
Grammar.DE_PREPS = { ["in"] = "in", nach = "to", aus = "from" }

local function withArticle(prep, g, case, core)
  local art = ART[g] and ART[g][case]
  if not art then return (prep and (prep .. " ") or "") .. core end
  local np = decline(core, g, case)
  if not prep then return art .. " " .. np end
  local c = CONTRACT[prep .. " " .. art]
  if c then return c .. " " .. np end
  return prep .. " " .. art .. " " .. np
end

-- case-neutral apposition for an unknown name: "im Gebiet X", "ins Gebiet X", "aus dem Gebiet X"
local NEUTRAL = { zone = { "Gebiet", "n" }, dungeon = { "Gebiet", "n" }, point = { "Ort", "m" } }

local function dePhrase(info, case, kind)
  local core, g = info.core, info.g
  if not info.known then
    local nn = NEUTRAL[kind] or NEUTRAL.zone
    if case == "nom" or case == "acc" or case == "dat" then return core end
    core, g = nn[1] .. " " .. core, nn[2]
    info = { core = core, g = g, known = true }
  end
  if case == "nom" or case == "acc" or case == "dat" then
    if g == "-" then return core end
    return withArticle(nil, g, case, core)
  end
  local isl = info.island
  if info.coast and (case == "in" or case == "to" or case == "nach" or case == "from" or case == "aus") then
    if case == "in" then return withArticle("an", g, "dat", core) end
    if case == "to" or case == "nach" then return withArticle("zu", g, "dat", core) end
    return withArticle("von", g, "dat", core)
  end
  if case == "in" then
    if g == "-" then return (isl and "auf " or "in ") .. core end
    return withArticle(isl and "auf" or "in", g, "dat", core)
  end
  if case == "to" or case == "nach" then
    if g == "-" then return "nach " .. core end
    if kind == "point" and not isl then return withArticle("zu", g, "dat", core) end
    return withArticle(isl and "auf" or "in", g, "acc", core)
  end
  if case == "from" or case == "aus" then
    if g == "-" then return (isl and "von " or "aus ") .. core end
    return withArticle((isl or kind == "point") and "von" or "aus", g, "dat", core)
  end
  if DE_DAT[case] then
    if g == "-" then return case .. " " .. core end
    return withArticle(case, g, "dat", core)
  end
  if DE_ACC[case] then
    if g == "-" then return case .. " " .. core end
    return withArticle(case, g, "acc", core)
  end
  return nil
end

-- English phrase ------------------------------------------------------------------------------------------------------------

local function enPhrase(info, case)
  local np = info.the and ("the " .. info.core) or info.core
  if case == "nom" or case == "acc" or case == "dat" then return np end
  local prep = case
  if case == "in" then prep = info.island and "on" or "in"
  elseif case == "to" then prep = "to"
  elseif case == "from" then prep = "from" end
  return prep .. " " .. np
end

-- first letter up/down: ASCII, Latin-1 (UTF-8 C3 xx) and Cyrillic (D0/D1 xx); anything else stays
local function upperFirst(s)
  local b, b2 = byte(s, 1), byte(s, 2)
  if not b then return s end
  if b >= 97 and b <= 122 then return upper(sub(s, 1, 1)) .. sub(s, 2) end
  if b == 0xC3 and b2 and b2 >= 0xA0 and b2 <= 0xBE and b2 ~= 0xB7 then return string.char(0xC3, b2 - 32) .. sub(s, 3) end
  if b == 0xD0 and b2 and b2 >= 0xB0 and b2 <= 0xBF then return string.char(0xD0, b2 - 32) .. sub(s, 3) end
  if b == 0xD1 and b2 and b2 >= 0x80 and b2 <= 0x8F then return string.char(0xD0, b2 + 32) .. sub(s, 3) end
  return s
end
Grammar.upperFirst = upperFirst

local function lowerFirst(s)
  local b, b2 = byte(s, 1), byte(s, 2)
  if not b then return s end
  if b >= 65 and b <= 90 then return lower(sub(s, 1, 1)) .. sub(s, 2) end
  if b == 0xC3 and b2 and b2 >= 0x80 and b2 <= 0x9E and b2 ~= 0x97 then return string.char(0xC3, b2 + 32) .. sub(s, 3) end
  if b == 0xD0 and b2 and b2 >= 0x90 and b2 <= 0x9F then return string.char(0xD0, b2 + 32) .. sub(s, 3) end
  if b == 0xD0 and b2 and b2 >= 0xA0 and b2 <= 0xAF then return string.char(0xD1, b2 - 32) .. sub(s, 3) end
  return s
end

local function isUpperFirst(s)
  return lowerFirst(s) ~= s
end

-- other languages (G6): no lexicon. A preposition directly before a place becomes a case-neutral apposition with a generic
-- noun and the name in quotes ("à {zone}" -> "dans la zone « Les Tarides »", "в {zone}" -> "в зоне «Степи»"), so no
-- article or case of the name is ever guessed. %s = the name.
local OTHER = {
  fr = {
    zone = { ["à"] = "dans la zone « %s »", dans = "dans la zone « %s »", en = "dans la zone « %s »",
      de = "de la zone « %s »", depuis = "depuis la zone « %s »", sur = "sur la zone « %s »", par = "par la zone « %s »",
      vers = "vers la zone « %s »", pour = "pour la zone « %s »" },
    dungeon = { ["à"] = "dans le donjon « %s »", dans = "dans le donjon « %s »", en = "dans le donjon « %s »",
      de = "du donjon « %s »", depuis = "depuis le donjon « %s »", sur = "sur le donjon « %s »", vers = "vers le donjon « %s »",
      pour = "pour le donjon « %s »" },
    point = { ["à"] = "à « %s »", de = "de « %s »", depuis = "depuis « %s »", vers = "vers « %s »", dans = "dans « %s »" },
    cases = { ["in"] = "dans", to = "vers", from = "de" },
  },
  es = {
    zone = { en = "en la zona «%s»", a = "a la zona «%s»", de = "de la zona «%s»", desde = "desde la zona «%s»",
      sobre = "sobre la zona «%s»", por = "por la zona «%s»", hacia = "hacia la zona «%s»", hasta = "hasta la zona «%s»",
      para = "para la zona «%s»" },
    dungeon = { en = "en la mazmorra «%s»", a = "a la mazmorra «%s»", de = "de la mazmorra «%s»",
      desde = "desde la mazmorra «%s»", sobre = "sobre la mazmorra «%s»", por = "por la mazmorra «%s»",
      hacia = "hacia la mazmorra «%s»", hasta = "hasta la mazmorra «%s»", para = "para la mazmorra «%s»" },
    point = { en = "en «%s»", a = "a «%s»", de = "de «%s»", desde = "desde «%s»", hacia = "hacia «%s»", hasta = "hasta «%s»" },
    cases = { ["in"] = "en", to = "a", from = "de" },
  },
  it = {
    zone = { ["in"] = "nella zona «%s»", a = "nella zona «%s»", da = "dalla zona «%s»", di = "della zona «%s»",
      su = "sulla zona «%s»", per = "per la zona «%s»", verso = "verso la zona «%s»" },
    dungeon = { ["in"] = "nella spedizione «%s»", a = "nella spedizione «%s»", da = "dalla spedizione «%s»",
      di = "della spedizione «%s»", su = "sulla spedizione «%s»", per = "per la spedizione «%s»",
      verso = "verso la spedizione «%s»" },
    point = { ["in"] = "a «%s»", a = "a «%s»", da = "da «%s»", di = "di «%s»", verso = "verso «%s»" },
    cases = { ["in"] = "in", to = "verso", from = "da" },
  },
  pt = {
    zone = { em = "na região “%s”", de = "da região “%s”", desde = "desde a região “%s”", a = "à região “%s”",
      para = "para a região “%s”", sobre = "sobre a região “%s”", por = "pela região “%s”" },
    dungeon = { em = "na masmorra “%s”", de = "da masmorra “%s”", desde = "desde a masmorra “%s”", a = "à masmorra “%s”",
      para = "para a masmorra “%s”", sobre = "sobre a masmorra “%s”", por = "pela masmorra “%s”" },
    point = { em = "em “%s”", de = "de “%s”", desde = "desde “%s”", a = "a “%s”", para = "para “%s”" },
    cases = { ["in"] = "em", to = "para", from = "de" },
  },
  ru = {
    zone = { ["в"] = "в зоне «%s»", ["на"] = "в зоне «%s»", ["из"] = "из зоны «%s»", ["о"] = "о зоне «%s»",
      ["об"] = "о зоне «%s»", ["через"] = "через зону «%s»", ["от"] = "от зоны «%s»", ["над"] = "над зоной «%s»",
      ["по"] = "по зоне «%s»", ["до"] = "до зоны «%s»", ["с"] = "с зоны «%s»", ["к"] = "к зоне «%s»",
      ["у"] = "у зоны «%s»", ["посреди"] = "посреди зоны «%s»", ["около"] = "около зоны «%s»" },
    dungeon = { ["в"] = "в подземелье «%s»", ["на"] = "в подземелье «%s»", ["из"] = "из подземелья «%s»",
      ["о"] = "о подземелье «%s»", ["через"] = "через подземелье «%s»", ["от"] = "от подземелья «%s»",
      ["над"] = "над подземельем «%s»", ["по"] = "по подземелью «%s»", ["до"] = "до подземелья «%s»",
      ["к"] = "к подземелью «%s»" },
    point = { ["в"] = "в пункт «%s»", ["из"] = "из пункта «%s»", ["с"] = "с пункта «%s»", ["до"] = "до пункта «%s»",
      ["от"] = "от пункта «%s»", ["к"] = "к пункту «%s»" },
    cases = { ["in"] = "в", to = "в", from = "из" },
  },
}
Grammar.OTHER = OTHER

-- neutral phrase in another language: prep (lower case) + kind -> phrase | nil
local function otherPhrase(lang, prep, name, kind)
  local t = OTHER[lang]
  local map = t and (t[kind] or t.zone)
  local f = map and map[prep]
  if not f then return nil end
  return (gsub(f, "%%s", function() return name end))
end

function Grammar.place(name, case, opts)
  if type(name) ~= "string" or name == "" then return nil, false end
  opts = type(opts) == "table" and opts or {}
  case = type(case) == "string" and case or "in"
  local lang = langOf(opts)
  local info = lang and Grammar.info(name, opts) or nil
  local phrase
  if lang == "de" then
    phrase = dePhrase(info, case, opts.kind)
  elseif lang == "en" then
    phrase = enPhrase(info, case)
  end
  if phrase and info and info.tail then phrase = phrase .. info.tail end
  local known = info == nil or info.known == true
  if not phrase and lang and OTHER[lang] then
    local c = OTHER[lang].cases[case] or case
    phrase = otherPhrase(lang, c, name, opts.kind or "zone")
  end
  if not phrase then
    -- the name stays, the text block carries the preposition
    phrase = name
  end
  if opts.upper then phrase = upperFirst(phrase) end
  return phrase, known
end

-- template filling ------------------------------------------------------------------------------------------------------------

local LETTERS = "[%a\128-\255]"

local EN_PREPS = { ["in"] = "in", to = "to", from = "from", of = "of", at = "at", through = "through", across = "across",
  over = "over", around = "around", near = "near", into = "into", toward = "toward", towards = "towards", about = "about",
  ["for"] = "for", by = "by", on = "on", since = "since", past = "past", beyond = "beyond", inside = "inside",
  outside = "outside", within = "within", under = "under", above = "above", behind = "behind", onto = "onto" }

local function prepCase(lang, word)
  local w = lower(word)
  if lang == "de" then
    if w == "in" then return "in" end
    if w == "nach" then return "to" end
    if w == "aus" then return "from" end
    if DE_DAT[w] or DE_ACC[w] then return w end
    return nil
  end
  if lang == "en" and EN_PREPS[w] then return w end
  return nil
end

local function atSentenceStart(buf)
  local s = table.concat(buf)
  if not find(s, "%S") then return true end
  return find(s, "[%.!%?]%s+$") ~= nil
end

function Grammar.fill(tpl, get, places, lang)
  if type(tpl) ~= "string" then return nil, true end
  local L
  if lang ~= nil then L = langOf({ lang = lang }) else L = langOf() end
  places = type(places) == "table" and places or {}
  local buf, pos, missing = {}, 1, false
  while true do
    local s, e, eq, key = find(tpl, "{(=?)([%w_]+)}", pos)
    if not s then
      buf[#buf + 1] = sub(tpl, pos)
      break
    end
    local before = sub(tpl, pos, s - 1)
    local v = get(key, eq == "=")
    if v == nil then
      missing = true
      v = ""
    end
    local kind = places[key]
    if kind and L and type(v) == "string" and v ~= "" and eq ~= "=" then
      local opts = { lang = L == "de" and "deDE" or "enUS", kind = kind ~= true and kind or "zone" }
      if L ~= "de" and L ~= "en" then opts.lang = nil end
      local head, word = match(before, "^(.-)(" .. LETTERS .. "+) $")
      local pc = word and prepCase(L, word) or nil
      if OTHER[L] then
        local w = word and lowerFirst(word) or nil
        local phrase = w and otherPhrase(L, w, v, opts.kind) or nil
        if phrase then
          -- keep the writer's capital ("В {zone}" -> "В зоне «…»", "À {zone}" -> "Dans la zone « … »")
          if sub(phrase, 1, #w + 1) == w .. " " then
            phrase = word .. sub(phrase, #w + 1)
          elseif isUpperFirst(word) then
            phrase = upperFirst(phrase)
          end
          before, v = head, phrase
        end
      elseif pc then
        local phrase = Grammar.place(v, pc, opts)
        local first = byte(word, 1)
        if first and first >= 65 and first <= 90 then phrase = upperFirst(phrase) end
        before, v = head, phrase
      elseif L == "en" then
        local phrase = Grammar.place(v, "nom", opts)
        buf[#buf + 1] = before
        before = ""
        if atSentenceStart(buf) then phrase = upperFirst(phrase) end
        v = phrase
      end
    end
    buf[#buf + 1] = before
    buf[#buf + 1] = v
    pos = e + 1
  end
  return table.concat(buf), missing
end

-- "{key}"-style fill with a plain table (Locale.fmt semantics: an absent key stays as "{key}")
function Grammar.fmt(tpl, args, places, lang)
  args = type(args) == "table" and args or {}
  local out = Grammar.fill(tpl, function(k, eq)
    if eq then return "{=" .. k .. "}" end
    local v = args[k]
    if v == nil then return "{" .. k .. "}" end
    return tostring(v)
  end, places, lang)
  return out
end

-- positional format strings ("erster Tod in %s", "Flug von %s nach %s"): places[i] = kind for the i-th argument.
-- Returns nil when an argument does not fit its format spec (the caller then uses its normal Locale call).
function Grammar.format(tpl, places, ...)
  if type(tpl) ~= "string" then return nil end
  local args, n = { ... }, select("#", ...)
  local byKey = {}
  for k, v in pairs(type(places) == "table" and places or {}) do byKey[tostring(k)] = v end
  local specs, i, bad = {}, 0, false
  local tmp = gsub(tpl, "%%%%", "\1")
  tmp = gsub(tmp, "%%([-+ #0]*%d*%.?%d*[diouxXeEfgGqsc])", function(spec)
    i = i + 1
    specs[i] = spec
    return "{" .. i .. "}"
  end)
  if i > n then return nil end
  local out = Grammar.fill(tmp, function(k)
    local idx = tonumber(k)
    if not idx or not specs[idx] then return "{" .. k .. "}" end
    local ok, s = pcall(string.format, "%" .. specs[idx], args[idx])
    if not ok then
      bad = true
      return ""
    end
    return s
  end, byKey)
  if bad or type(out) ~= "string" then return nil end
  return (gsub(out, "\1", "%%"))
end

-- Locale.ns call with place arguments: Grammar.call(T, "firstDeathIn", { [1] = "zone" }, where)
function Grammar.call(T, key, places, ...)
  local s = Grammar.format(T[key], places, ...)
  if s == nil then return T(key, ...) end
  return s
end
