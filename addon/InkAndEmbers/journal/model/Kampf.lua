-- Evaluator for the Kampf page: totals, tally, stamps, most hunted (bestiary), rare entry, hunting grounds (heat grid,
-- else markers), last breath (death n from DE/DR/DC/DB), graves, close calls. Pure read logic over the index.
-- Kampf.evaluate(index, opts) -> view; opts: live, now, zone, death, hunted (zone choice for the whole page: uiMapID
-- with kills, or "all"/nil). The expensive part is computed once per index (Kampf.static).
-- All output texts are display-ready (Sanitize.display or constants); names from the SV and spell names from the client
-- never go out raw.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Kampf = {}
Journal.Kampf = Kampf

local floor, huge, min, max, sqrt, ceil = math.floor, math.huge, math.min, math.max, math.sqrt, math.ceil
local format, find = string.format, string.find

Kampf.TALLY_MAX = 100      -- max strokes in the tally (one line object per stroke in game)
Kampf.ZONE_MAX = 64        -- zones in the area dropdown
Kampf.HEAT_MAX = 256       -- blobs per map
Kampf.POINT_MAX = 400      -- exact kill points per map (as Index.POINT_MAX)
Kampf.SPOT_MAX = 6         -- enemy kinds in the tooltip of a blob/point
Kampf.MARKER_MAX = 64      -- markers per map (fallback without N1, deaths)
Kampf.HITS_MAX = 8         -- hits in the death report (the last ones before dying)
Kampf.GRAVE_MAX = 6        -- zones in the graveyard
Kampf.CLOSE_MAX = 3        -- close wins
Kampf.NAME_MAX = 40        -- bytes per name (enemy, zone)
Kampf.DEATH_MAX = 2000     -- deaths kept individually (the newest stay)

-- locale scope "m.Kampf" (English in locales/enUS_model.lua); stamps and causes are read on access
local Loc = ns.Locale
local TEXT = Loc.ns("m.Kampf", {
  noKills = "NOCH NICHTS ERLEGT",
  nothing = "Noch kein Gegner verzeichnet.",
  noHunted = "Noch keine Gegner im Bestiarium.",
  noDeath = "Noch nie gestorben. Möge es so bleiben.",
  noGraves = "Noch nirgends gestorben.",
  noHuntedZone = "In dieser Zone noch nichts erlegt.",
  allZones = "Alle Gebiete",
  killsHere = "ERLEGT IN DIESEM GEBIET",
  noClose = "Noch kein knapper Sieg.",
  noZone = "Noch keine Jagdgründe.",
  noPos = "Ohne Positionen: Marker für besondere Gegner und Tode",
  noSpots = "Für diese Zone sind keine Kill-Orte erfasst",
  closeFoot = "Kampfende mit unter 10 % Leben (Näherung)",
  noReport = "Kein lesbarer Todesbericht.",
  gap = "Eintrag nicht lesbar",
  unknownFoe = "Unbekannt",
  hunt = "Jagdgründe",
  moreKinds = "weitere Arten",
  sample = "Stichprobe: die letzten %s von %s Kills dieser Zone",
  stampLabel_normal = "Gewöhnl.", stampLabel_elite = "Elite", stampLabel_rare = "Rar", stampLabel_boss = "Boss",
  stamp_normal = "Gewöhnlich", stamp_elite = "Elite", stamp_rare = "Rar", stamp_boss = "Boss", stamp_unknown = "Klasse unbekannt",
  cause_enemy = "durch einen Gegner", cause_fall = "durch einen Sturz", cause_drown = "ertrunken", cause_fatigue = "vor Erschöpfung",
  cause_lava = "in der Lava", cause_fire = "im Feuer", cause_slime = "im Schleim", cause_environment = "durch die Umgebung",
  mapFallback = "Karte %s",
  day = "Tag %s",
  dayClock = "Tag %s, %s",
  dayRange = "Tag %s–%s",
  lv = "St. %s",
  lvRange = "St. %s–%s",
  tipKilled = "Erlegte Gegner: %s",
  tipAll = "Alle Kills: eigene, Begleiter und Gruppe (auch in Instanzen)",
  tipPlayed = "Zeit = gespielte Zeit (/played)",
  tipEstimated = "Zeit geschätzt aus den Sitzungen",
  killedIn = "ERLEGT IN %s",
  killedInApprox = "ERLEGT IN CA. %s",
  killed = "ERLEGT",
  tallyUnit = "Strichliste: ein Strich = %s Gegner",
  tallyOne = "Strichliste: ein Strich = ein Gegner",
  tallyKilled = "Erlegt: %s",
  kills_one = "%s Kill",
  kills_other = "%s Kills",
  footUnknown = "davon %s in Instanzen unbekannt",
  groupNote = "Gruppen-Kills zählen mit (%s)",
  huntedTip = "%s · %s× erlegt",
  huntedTipIn = "%s · %s× erlegt in %s",
  huntedTotal = "insgesamt %s×",
  huntedMostly = "Meist in %s",
  huntedGroup = "davon %s von der Gruppe erlegt",
  species_one = "%s Art",
  species_other = "%s Arten",
  speciesZone = "%s in dieser Zone",
  speciesAll = "%s verzeichnet",
  fightSec_one = "Kampf dauerte %s Sekunde",
  fightSec_other = "Kampf dauerte %s Sekunden",
  fightClock = "Kampf dauerte %s",
  fightNote = "%s (Kampfdauer, nicht Zeit bis zum Tod)",
  deathNo = "Tod %s",
  unknownPlace = "unbekannter Ort",
  deaths_one = "%s Tod",
  deaths_other = "%s Tode",
  ghost = "im Schnitt %s bis zurück ins Leben",
  fightVs = "Kampf gegen %s Gegner",
  fightAt = "Kampf bei %s, Tag %s",
  fightAtUnknown = "Kampf bei unbekanntem Ort, Tag %s",
  hpEnd = "Leben am Kampfende %s %%",
  hpEndUnknown = "Leben am Kampfende nicht lesbar",
  foeGuess = "Gegner geschätzt (Näherung)",
  pct = "%s %%",
  pctUnknown = "? %",
  zoneTip = "Erlegt in %s: %s",
  diedHere = "hier %s× gestorben",
  heatCaption = "%s Kills in dieser Zone",
  deathTitle = "Der letzte Atemzug · Tod %s",
  gapTip = "Der Client gab diesen Eintrag nicht heraus.",
  heal = "Heilung %s",
  healCrit = "Heilung %s (kritisch)",
  dmg = "Schaden %s",
  dmgCrit = "Schaden %s (kritisch)",
  hpBefore = "Leben davor %s",
  hpBeforeOf = "Leben davor %s von %s",
  agoS = "%s s vor dem Tod",
  span = "%s Sekunden.",
  lastOf = "die letzten %s von %s Einträgen",
  died = "Gestorben %s",
  diedGuess = "Gestorben %s (vermutet)",
  level = "Stufe %s",
  stoneDate = "!%d.%m.", -- date in the gravestone tooltip (date format, UTC of the local time)
})
Kampf.TEXT = TEXT

local STAMPS = {
  { key = "normal", color = "ink" },
  { key = "elite", color = "sepia" },
  { key = "rare", color = "blue" },
  { key = "boss", color = "red" },
}
for _, s in ipairs(STAMPS) do
  setmetatable(s, { __index = function(t, k)
    if k == "label" then return TEXT["stampLabel_" .. t.key] end
    if k == "word" then return TEXT["stamp_" .. t.key] end
  end })
end
Kampf.STAMPS = STAMPS
-- rune per stamp: cell of the map symbol atlas (Theme.ATLAS), no image of its own
Kampf.RUNE = { normal = "disc", elite = "elite", rare = "rare", boss = "boss", unknown = "gap" }
-- word per stamp in the active language (common/elite/rare/boss/class unknown)
local STAMP_WORD = setmetatable({}, { __index = function(_, k)
  if k == "normal" or k == "elite" or k == "rare" or k == "boss" or k == "unknown" then return TEXT["stamp_" .. k] end
end })

local CAUSE = setmetatable({}, { __index = function(_, k)
  if k == "enemy" or k == "fall" or k == "drown" or k == "fatigue" or k == "lava" or k == "fire" or k == "slime"
    or k == "environment" then return TEXT["cause_" .. k] end
end })

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function finite(v)
  return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local function I() return Journal.Index end

local function display(v, n)
  local S = ns.Sanitize
  return S and S.display(v, n or Kampf.NAME_MAX) or nil
end

local function int(n)
  local T = Journal.Texts
  return T and T.int(n) or tostring(n)
end

-- number with plural key (<key>_one / <key>_other, "%s" = the number)
local function plural(n, key) return TEXT(Loc.plural(n, key .. "_one", key .. "_other"), int(n)) end

local function byId(tbl, id)
  if type(tbl) ~= "table" or id == nil then return nil end
  local v = tbl[id]
  if v == nil and type(id) == "number" then v = tbl[format("%.0f", id)] end
  return v
end

local function rawName(e)
  if type(e) == "table" then e = e.name end
  if type(e) ~= "string" or e == "" or isSecret(e) then return nil end
  return e
end

local function posId(v)
  if type(v) == "number" then
    if not finite(v) or v <= 0 or v ~= floor(v) or v >= 2147483648 then return nil end
    return v
  end
  if type(v) ~= "string" or not find(v, "^%d+$") or #v > 10 then return nil end
  local n = tonumber(v)
  if not n or n <= 0 or n >= 2147483648 then return nil end
  return n
end

local function mapsOf(char)
  local s = type(char) == "table" and char.snapshots
  local m = type(s) == "table" and s.maps
  return type(m) == "table" and m or nil
end

local function zoneName(st, mapID)
  if not mapID then return nil end
  local c = st.zoneNames[mapID]
  if c == nil then
    c = display(rawName(byId(st.maps, mapID))) or ((ns.Journal.View and ns.Journal.View.mapName and ns.Journal.View.mapName(mapID)) or TEXT("mapFallback", format("%.0f", mapID)))
    st.zoneNames[mapID] = c
  end
  return c
end

local function npcName(st, id)
  return id and display(rawName(byId(st.npcs, id))) or nil
end

-- local time (as Chronik): time zone history of the index
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

local function whenText(index, t)
  if not finite(t) then return nil end
  local s = (t + tzAt(index, t)) % 86400
  return TEXT("dayClock", int(I().dayOf(index, t)), format("%02d:%02d", floor(s / 3600), floor(s % 3600 / 60)))
end

-- date and time of a death for the gravestone tooltip: "07.11. · 19:52 · Tag 13" (character local time as whenText) ->
-- string | nil
local function stoneWhen(index, t)
  if not (finite(t) and type(index) == "table") then return nil end
  local lt = t + tzAt(index, t)
  local s = lt % 86400
  local clock = format("%02d:%02d", floor(s / 3600), floor(s % 3600 / 60))
  local d = rawget(_G, "date")
  local day
  if type(d) == "function" then
    local ok, v = pcall(d, TEXT.stoneDate, floor(lt))
    if ok and type(v) == "string" then day = v:match("^(%d%d[%./]%d%d%.?)$") end
  end
  local parts = {}
  if day then parts[#parts + 1] = day end
  parts[#parts + 1] = clock
  parts[#parts + 1] = TEXT("day", int(I().dayOf(index, t)))
  return table.concat(parts, " · ")
end

local function levelsText(lmin, lmax)
  if not lmin then return nil end
  if lmax and lmax ~= lmin then return TEXT("lvRange", int(lmin), int(lmax)) end
  return TEXT("lv", int(lmin))
end

-- "6,4" / "6.4" (one decimal, decimal separator of the active language from Fmt)
local function dec1(v)
  local sep = Journal.Fmt and Journal.Fmt.T and Journal.Fmt.T.decimal or ","
  return (format("%.1f", v):gsub("%.", (sep:gsub("%%", "%%%%"))))
end

-- short duration "1:37 Min." (Fmt.clock, bilingual)
local function clockMin(sec)
  return Journal.Fmt.clock(sec) or ""
end

local function playedSeconds(index)
  local Idx = I()
  local list = Idx.list(index, "PL")
  for i = #list, 1, -1 do
    local total = Idx.num(list[i], "PL", "total")
    if total and total >= 0 then return total, true end
  end
  local s0, s1 = tonumber(index.startT), tonumber(index.lastT)
  if finite(s0) and finite(s1) and s1 > s0 then return (Idx.activeSeconds(index, s0, s1)), false end
  return nil
end

local function buildSummary(index, kills)
  local total = kills.total or 0
  local sec, exact = playedSeconds(index)
  local out = { total = total, totalText = int(total), seconds = sec, exact = exact }
  out.tip = { TEXT("tipKilled", int(total)), TEXT.tipAll }
  if sec and sec > 0 then
    out.tip[#out.tip + 1] = exact and TEXT.tipPlayed or TEXT.tipEstimated
  end
  if total <= 0 then
    out.label = TEXT.noKills
    return out
  end
  if sec and sec > 0 then
    -- duration as everywhere via Fmt ("30 MIN.", "6 STD. 27 MIN.", "2 TG. 3 STD."), upper case with umlauts
    local F = Journal.Fmt
    local unit = F.upper(F.duration(max(60, sec)) or "")
    out.label = TEXT(exact and "killedIn" or "killedInApprox", unit)
  else
    out.label = TEXT.killed
  end
  return out
end

-- tally: up to Kampf.TALLY_MAX kills one stroke per kill, above that 10, 100, ... per stroke (the smallest power of ten
-- that gives at most TALLY_MAX strokes).
-- Five strokes make a bundle (four vertical, one across); the last bundle is partial. The remainder below one stroke is
-- dropped (the big number next to it is exact).
function Kampf.tally(total)
  total = tonumber(total) or 0
  if not finite(total) or total < 0 then total = 0 end
  total = floor(total)
  local cap = Kampf.TALLY_MAX
  local unit = 1
  while total > unit * cap and unit < 1e15 do unit = unit * 10 end
  local strokes = min(cap, floor(total / unit))
  local bundles = {}
  local full = floor(strokes / 5)
  for i = 1, full do bundles[i] = 5 end
  if strokes > full * 5 then bundles[#bundles + 1] = strokes - full * 5 end
  local out = { unit = unit, strokes = strokes, bundles = bundles }
  if unit > 1 then
    out.legend = "= " .. int(unit)
    out.tip = { TEXT("tallyUnit", int(unit)), TEXT("tallyKilled", int(total)) }
  else
    out.tip = { TEXT.tallyOne, TEXT("tallyKilled", int(total)) }
  end
  return out
end

local function buildStamps(kills)
  local st = type(kills.stamp) == "table" and kills.stamp or {}
  local out = { list = {} }
  for i, s in ipairs(STAMPS) do
    local v = tonumber(st[s.key]) or 0
    out.list[i] = { key = s.key, label = s.label, word = s.word, value = v, valueText = int(v), color = s.color,
      tip = { s.word, plural(v, "kills") } }
  end
  out.unknown = tonumber(st.unknown) or 0
  if out.unknown > 0 then out.footnote = TEXT("footUnknown", int(out.unknown)) end
  if (kills.group or 0) > 0 then out.groupNote = TEXT("groupNote", int(kills.group)) end
  return out
end

local function topMap(map)
  local best, bn
  for m, n in pairs(type(map) == "table" and map or {}) do
    if type(n) == "number" and (not bn or n > bn or (n == bn and m < best)) then best, bn = m, n end
  end
  return best
end

-- one bestiary card, built on demand (a page shows a handful; keeping a card table per species would cost memory)
local function huntedItem(st, mapID, here, id, e, n)
  local name = npcName(st, id) or (TEXT.unknownFoe .. " #" .. format("%.0f", id))
  local m = topMap(e.map)
  local zone = m and zoneName(st, m) or nil
  local levels = levelsText(I().npcLevels(e))
  local stamp = STAMP_WORD[e.stamp] and e.stamp or "unknown"
  local parts = {}
  if mapID then
    parts[#parts + 1] = STAMP_WORD[stamp]
  elseif zone then
    parts[#parts + 1] = zone
  end
  if levels then parts[#parts + 1] = levels end
  local tip = { name, here and TEXT("huntedTipIn", STAMP_WORD[stamp], int(n), here) or TEXT("huntedTip", STAMP_WORD[stamp], int(n)) }
  if mapID and n ~= e.n then tip[#tip + 1] = TEXT("huntedTotal", int(e.n)) end
  if zone and not mapID then tip[#tip + 1] = TEXT("huntedMostly", zone) end
  if levels then tip[#tip + 1] = levels end
  if (e.group or 0) > 0 then tip[#tip + 1] = TEXT("huntedGroup", int(e.group)) end
  return { id = id, name = name, zone = zone, levels = levels, meta = table.concat(parts, " · "), count = n,
    countText = "× " .. int(n), stamp = stamp, rune = Kampf.RUNE[stamp], tip = tip }
end

-- mapID = nil: all zones (count = all kills of the kind); otherwise only kinds with kills in this zone (count = kills there).
-- All kinds are listed (most killed first, elite and rare ones included); the card of position i is built by hunted.item(i), the
-- view only keeps two number arrays (ids, kills) so that thousands of kinds stay cheap.
local function buildHunted(st, kills, mapID)
  local arr = {}
  local npcs = type(kills.npc) == "table" and kills.npc or {}
  for id, e in pairs(npcs) do
    if type(id) == "number" and type(e) == "table" and type(e.n) == "number" then
      local n = e.n
      if mapID then n = type(e.map) == "table" and tonumber(e.map[mapID]) or 0 end
      if finite(n) and n > 0 then arr[#arr + 1] = { id = id, n = n } end
    end
  end
  table.sort(arr, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return a.id < b.id
  end)
  local ids, counts = {}, {}
  for i = 1, #arr do ids[i], counts[i] = arr[i].id, arr[i].n end
  local here = mapID and zoneName(st, mapID) or nil
  local function item(i)
    local id = ids[i]
    if not id then return nil end
    return huntedItem(st, mapID, here, id, npcs[id], counts[i])
  end
  local species = mapID and #ids or (tonumber(kills.npcCount) or 0)
  local word = plural(species, "species")
  return { zone = mapID, zoneName = here, count = #ids, item = item, ids = ids, counts = counts, species = species,
    unknown = tonumber(kills.npcUnknown) or 0, speciesText = TEXT(mapID and "speciesZone" or "speciesAll", word) }
end

local function killName(st, rec)
  local Idx = I()
  local id = posId(Idx.str(rec, "KI", "npcID"))
  return npcName(st, id) or display(Idx.str(rec, "KI", "name")) or TEXT.unknownFoe
end

local function stampOf(rec)
  local Idx = I()
  local lv = Idx.num(rec, "KI", "level")
  if lv == -1 then return "boss" end
  local cls = Idx.str(rec, "KI", "cls")
  if cls == "elite" then return "elite" end
  if cls == "rare" or cls == "rareelite" then return "rare" end
  if cls == "worldboss" then return "boss" end
  return nil
end

local function buildRare(index, st, kills, onlyMap)
  local Idx = I()
  local list = Idx.list(index, "KI")
  for i = #list, 1, -1 do
    local r = list[i]
    if stampOf(r) == "rare" and finite(r.t) and (not onlyMap or posId(Idx.str(r, "KI", "mapID")) == onlyMap) then
      local name = killName(st, r)
      local lv = Idx.num(r, "KI", "level")
      local parts = { STAMP_WORD.rare }
      if lv and lv > 0 then parts[#parts + 1] = TEXT("lv", int(lv)) end
      local when = whenText(index, r.t)
      if when then parts[#parts + 1] = when end
      local d = type(kills.fight) == "table" and kills.fight[r.ln] or nil
      local fight = finite(d) and (d < 60 and plural(floor(d + 0.5), "fightSec") or TEXT("fightClock", clockMin(d))) or nil
      local zone = zoneName(st, posId(Idx.str(r, "KI", "mapID")))
      local tip = { name, table.concat(parts, " · ") }
      if zone then tip[#tip + 1] = zone end
      if fight then tip[#tip + 1] = TEXT("fightNote", fight) end
      return { title = name, meta = table.concat(parts, " · "), fight = fight, tip = tip }
    end
  end
  return nil
end

local function buildZones(st, kills)
  local arr = {}
  for m, n in pairs(type(kills.map) == "table" and kills.map or {}) do
    if type(m) == "number" and type(n) == "number" then arr[#arr + 1] = { mapID = m, n = n } end
  end
  table.sort(arr, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return a.mapID < b.mapID
  end)
  local out = {}
  for i = 1, min(#arr, Kampf.ZONE_MAX) do
    out[i] = { mapID = arr[i].mapID, n = arr[i].n, name = zoneName(st, arr[i].mapID) }
  end
  return out
end

-- deaths: DE with the following DR/DC/DB (up to the next DE), in log order (rec.ln)
local function buildDeaths(index)
  local Idx = I()
  local des = Idx.list(index, "DE")
  local deaths = {}
  local from = max(1, #des - Kampf.DEATH_MAX + 1)
  for i = from, #des do
    local r = des[i]
    if finite(r.t) and finite(r.ln) then deaths[#deaths + 1] = { rec = r, ln = r.ln, t = r.t, hits = {} } end
  end
  if #deaths == 0 then return deaths end
  local lns = {}
  for i, d in ipairs(deaths) do lns[i] = d.ln end
  -- largest death with ln < x
  local function owner(ln)
    if not finite(ln) then return nil end
    local lo, hi = 1, #lns
    if lns[1] >= ln then return nil end
    while lo < hi do
      local mid = floor((lo + hi + 1) / 2)
      if lns[mid] < ln then lo = mid else hi = mid - 1 end
    end
    return deaths[lo]
  end
  for _, r in ipairs(Idx.list(index, "DR")) do
    local d = owner(r.ln)
    if d and #d.hits < 64 then d.hits[#d.hits + 1] = r end
  end
  for _, r in ipairs(Idx.list(index, "DC")) do
    local d = owner(r.ln)
    if d and not d.dc then d.dc = r end
  end
  for _, r in ipairs(Idx.list(index, "DB")) do
    local d = owner(r.ln)
    if d and not d.db then d.db = r end
  end
  return deaths
end

local function deathPlace(st, rec)
  local Idx = I()
  local sub = display(Idx.str(rec, "DE", "sub"))
  if sub then return sub end
  return zoneName(st, posId(Idx.str(rec, "DE", "mapID")))
end

local function buildGraves(st, deaths, index)
  index = index or st.index
  local Idx = I()
  local by, order = {}, {}
  for i, d in ipairs(deaths) do
    local m = posId(Idx.str(d.rec, "DE", "mapID")) or 0
    local g = by[m]
    if not g then
      g = { mapID = m, n = 0, first = d.t, last = d.t, idx = {}, tips = {} }
      by[m] = g
      order[#order + 1] = g
    end
    g.n, g.last = g.n + 1, d.t
    g.idx[#g.idx + 1] = i -- number of the death (opts.death) in exactly this list: clicking a gravestone opens it
    local lv = Idx.num(d.rec, "DE", "level")
    local okW, when = pcall(stoneWhen, index, d.t)
    local tip = TEXT("deathNo", int(i)) .. ((okW and when) and (" · " .. when) or "") .. ((lv and lv >= 1) and (" · " .. TEXT("lv", int(lv))) or "")
    g.tips[#g.tips + 1] = tip
    if lv and lv >= 1 then
      if not g.lmin or lv < g.lmin then g.lmin = lv end
      if not g.lmax or lv > g.lmax then g.lmax = lv end
    end
  end
  -- zones with the most recent deaths, shown by first death time
  local recent = {}
  for i, g in ipairs(order) do recent[i] = g end
  table.sort(recent, function(a, b) return a.last > b.last end)
  local pick = {}
  for i = 1, min(#recent, Kampf.GRAVE_MAX) do pick[i] = recent[i] end
  table.sort(pick, function(a, b) return a.first < b.first end)
  local list = {}
  for i, g in ipairs(pick) do
    local name = g.mapID > 0 and zoneName(st, g.mapID) or TEXT.unknownPlace
    local levels = levelsText(g.lmin, g.lmax)
    local nText = plural(g.n, "deaths")
    list[i] = { mapID = g.mapID > 0 and g.mapID or nil, name = name, n = g.n, nText = nText,
      levels = levels, deaths = g.idx, stoneTips = g.tips, tip = { name, nText .. (levels and (" · " .. levels) or "") } }
  end
  -- way back: mean seconds until revival for corpse run and spirit healer
  local sum, n = 0, 0
  for _, d in ipairs(deaths) do
    local b = d.db
    if b then
      local how = Idx.str(b, "DB", "how")
      local s = Idx.num(b, "DB", "seconds")
      if (how == "spirit" or how == "corpse") and s and s >= 0 and s < 86400 then sum, n = sum + s, n + 1 end
    end
  end
  return { list = list, total = #deaths, more = max(0, #order - #list), empty = #deaths == 0,
    ghost = n > 0 and TEXT("ghost", clockMin(sum / n)) or nil }
end

-- close win: the enemy name is not in KF. Approximation: elite/rare/boss kill within the fight's time window, else the
-- kill count of the fight, else "Kampf bei <place>"
local function buildClose(index, st, onlyMap)
  local Idx = I()
  local fights = Idx.list(index, "KF")
  local specials = Idx.list(index, "KI")
  local arr = {}
  for _, r in ipairs(fights) do
    local hp = Idx.num(r, "KF", "hpEnd")
    if Idx.str(r, "KF", "close") == "1" and finite(r.t) and (not onlyMap or posId(Idx.str(r, "KF", "mapID")) == onlyMap) then
      arr[#arr + 1] = { r = r, hp = hp }
    end
  end
  table.sort(arr, function(a, b)
    local ha, hb = a.hp or huge, b.hp or huge
    if ha ~= hb then return ha < hb end
    return (a.r.ln or 0) > (b.r.ln or 0)
  end)
  local list = {}
  for i = 1, min(#arr, Kampf.CLOSE_MAX) do
    local r, hp = arr[i].r, arr[i].hp
    local d = Idx.num(r, "KF", "duration") or 0
    local t0, t1 = r.t - d - Idx.FIGHT_SLACK, r.t + Idx.FIGHT_SLACK
    local foe, foeLv
    for j = #specials, 1, -1 do
      local k = specials[j]
      if finite(k.t) and k.t <= t1 then
        if k.t < t0 then break end
        local lv = Idx.num(k, "KI", "level") or 0
        if not foe or lv > foeLv then foe, foeLv = killName(st, k), lv end
      end
    end
    local where = zoneName(st, posId(Idx.str(r, "KF", "mapID")))
    local name, guess = foe, true
    if not name then
      local kn = Idx.num(r, "KF", "kills")
      if kn and kn > 1 then
        name = TEXT("fightVs", int(kn)) .. (where and (" · " .. where) or "")
      elseif where then
        name = TEXT("fightAt", where, int(Idx.dayOf(index, r.t)))
      else
        name = TEXT("fightAtUnknown", int(Idx.dayOf(index, r.t)))
      end
    end
    local pct = (hp and hp >= 0 and hp <= 100) and floor(hp + 0.5) or nil
    local tip = { name, pct and TEXT("hpEnd", int(pct)) or TEXT.hpEndUnknown }
    local when = whenText(index, r.t)
    if when then tip[#tip + 1] = when .. (where and (" · " .. where) or "") end
    if d > 0 then tip[#tip + 1] = d < 60 and plural(floor(d + 0.5), "fightSec") or TEXT("fightClock", clockMin(d)) end
    tip[#tip + 1] = TEXT.foeGuess
    list[i] = { name = name, pct = pct, pctText = pct and TEXT("pct", int(pct)) or TEXT.pctUnknown, guess = guess, tip = tip }
  end
  return { list = list, total = #arr, footnote = TEXT.closeFoot }
end

local function buildStatic(index)
  local char = type(index.char) == "table" and index.char or {}
  local kills = type(index.kills) == "table" and index.kills or { total = 0, stamp = {} }
  local st = { char = char, maps = mapsOf(char), npcs = type(char.npcs) == "table" and char.npcs or nil, zoneNames = {} }
  st.summary = buildSummary(index, kills)
  st.tally = Kampf.tally(kills.total)
  st.stamps = buildStamps(kills)
  st.hunted = buildHunted(st, kills, nil)
  st.huntedBy = {}
  st.rare = buildRare(index, st, kills)
  st.zones = buildZones(st, kills)
  st.deaths = buildDeaths(index)
  st.index = index
  st.graves = buildGraves(st, st.deaths, index)
  st.close = buildClose(index, st)
  st.hunts = {}
  st.zoneViews = {}
  return st
end

-- view of a single zone (zone choice top left: the whole page follows it): totals, tally, stamps, rare entry, deaths,
-- graves and close wins from this zone only.
-- Stamps from kills.npc[id].map[zone] (class per kind); whatever is not assigned to a kind (instance kills without
-- npcID) counts as unknown. The index has no group kills per zone.
local function buildZoneView(index, st, mapID)
  local Idx = I()
  local kills = type(index.kills) == "table" and index.kills or {}
  local total = type(kills.map) == "table" and tonumber(kills.map[mapID]) or 0
  if not finite(total) or total < 0 then total = 0 end
  local by = { normal = 0, elite = 0, rare = 0, boss = 0 }
  local known = 0
  for _, e in pairs(type(kills.npc) == "table" and kills.npc or {}) do
    local n = type(e) == "table" and type(e.map) == "table" and tonumber(e.map[mapID]) or 0
    if finite(n) and n > 0 and by[e.stamp] and known + n <= total then
      by[e.stamp] = by[e.stamp] + n
      known = known + n
    end
  end
  by.unknown = total - known
  local zv = { mapID = mapID }
  local name = zoneName(st, mapID)
  zv.summary = { total = total, totalText = int(total), label = TEXT.killsHere,
    tip = { TEXT("zoneTip", name, int(total)), TEXT.tipAll } }
  zv.tally = Kampf.tally(total)
  zv.stamps = buildStamps({ stamp = by, group = 0 })
  zv.rare = buildRare(index, st, kills, mapID)
  local deaths = {}
  for _, d in ipairs(st.deaths) do
    if posId(Idx.str(d.rec, "DE", "mapID")) == mapID then deaths[#deaths + 1] = d end
  end
  -- death n (buildDeath) reads st.deaths: put the zone list in front of the general one
  zv.st = setmetatable({ deaths = deaths }, { __index = st })
  zv.deaths = deaths
  zv.graves = buildGraves(st, deaths)
  zv.close = buildClose(index, st, mapID)
  return zv
end

local cache = setmetatable({}, { __mode = "k" })

function Kampf.static(index)
  local st = cache[index]
  if not st then
    st = buildStatic(index)
    cache[index] = st
  end
  return st
end

local function hasKills(st, mapID)
  if not mapID then return false end
  for _, z in ipairs(st.zones) do
    if z.mapID == mapID then return true end
  end
  return false
end

function Kampf.huntedZone(index, current, saved)
  if type(index) ~= "table" then return "all" end
  local st = Kampf.static(index)
  local here = posId(current)
  if hasKills(st, here) then return here end
  local s = posId(saved)
  if hasKills(st, s) then return s end
  return "all"
end

local function inUnit(v) -- field value 0..9999 -> 0..1
  if not v or v < 0 or v > 9999 then return nil end
  return v / 10000
end

local function buildHunt(index, st, mapID)
  local Idx = I()
  local kills = type(index.kills) == "table" and index.kills or {}
  local grid = Idx.HEAT_GRID
  local h = { zone = mapID, grid = grid, cells = {}, markers = {}, kills = 0, deaths = 0 }
  h.zoneName = mapID and zoneName(st, mapID) or nil
  h.kills = mapID and type(kills.map) == "table" and tonumber(kills.map[mapID]) or 0
  local function addMarker(x, y, kind, tip)
    if #h.markers >= Kampf.MARKER_MAX then return end
    h.markers[#h.markers + 1] = { x = x, y = y, kind = kind, tip = tip }
  end
  -- deaths in this zone (also with heat); newest first so that the cap hits the old ones
  if mapID then
    for i = #st.deaths, 1, -1 do
      local r = st.deaths[i].rec
      if posId(Idx.str(r, "DE", "mapID")) == mapID then
        h.deaths = h.deaths + 1
        local x, y = inUnit(Idx.num(r, "DE", "x")), inUnit(Idx.num(r, "DE", "y"))
        if x and y then addMarker(x, y, "death", { TEXT("deathNo", int(i)), whenText(index, r.t) or "" }) end
      end
    end
  end
  -- elite/rare/boss with position (since F17); without N1 they are the only positions in the heat grid
  local special, specialPos = {}, 0
  if mapID then
    local list = Idx.list(index, "KI")
    for i = #list, 1, -1 do
      local r = list[i]
      if posId(Idx.str(r, "KI", "mapID")) == mapID then
        local x, y = inUnit(Idx.num(r, "KI", "x")), inUnit(Idx.num(r, "KI", "y"))
        local kind = stampOf(r)
        if x and y and kind then
          specialPos = specialPos + 1
          if #special < Kampf.MARKER_MAX then special[#special + 1] = { x, y, kind, { killName(st, r), STAMP_WORD[kind] .. " · " .. (whenText(index, r.t) or "") } } end
        end
      end
    end
  end
  -- heat (N1: positions on all kills). Only if more kills carry a position than the special ones: otherwise all blobs
  -- come from old lines
  -- before N1 (elite/rare/boss only) and the map shows markers
  local heat = mapID and type(kills.heat) == "table" and kills.heat[mapID] or nil
  local arr, heatSum = {}, 0
  if type(heat) == "table" then
    for cell, n in pairs(heat) do
      if type(cell) == "number" and type(n) == "number" and n > 0 then
        arr[#arr + 1] = { cell = cell, n = n }
        heatSum = heatSum + n
      end
    end
  end
  if heatSum > specialPos then
    table.sort(arr, function(a, b)
      if a.n ~= b.n then return a.n > b.n end
      return a.cell < b.cell
    end)
    local top = arr[1] and arr[1].n or 1
    for i = 1, min(#arr, Kampf.HEAT_MAX) do
      local c = arr[i]
      local gx, gy = c.cell % grid, floor(c.cell / grid)
      if gx >= 0 and gy >= 0 and gy < grid then
        h.cells[#h.cells + 1] = { gx = gx, gy = gy, n = c.n, alpha = 0.25 + 0.65 * sqrt(c.n / top) }
      end
    end
  end
  local pts = mapID and type(kills.pts) == "table" and kills.pts[mapID] or nil
  if type(pts) == "table" and type(pts.pos) == "table" and heatSum > specialPos then
    local cap = Idx.POINT_MAX or Kampf.POINT_MAX
    local n = min(floor(tonumber(pts.n) or 0), cap)
    local list = {}
    for i = 1, n do
      local pos = pts.pos[i]
      if type(pos) == "number" and pos >= 0 then
        list[#list + 1] = { x = (floor(pos / 10000) + 0.5) / 10000, y = (pos % 10000 + 0.5) / 10000 }
      end
    end
    if #list > 0 then
      h.points = { list = list, n = #list, total = h.kills, sample = (tonumber(pts.n) or 0) > cap }
      -- count enemies in the rectangle (cells/surroundings of a point) from the sample; names only via display()
      h.spot = function(x0, y0, x1, y1)
        local agg, order, count = {}, {}, 0
        for i = 1, n do
          local pos, nl, t = pts.pos[i], pts.nl and pts.nl[i], pts.t and pts.t[i]
          if type(pos) == "number" then
            local px, py = floor(pos / 10000) / 10000, pos % 10000 / 10000
            if px >= x0 and px < x1 and py >= y0 and py < y1 then
              count = count + 1
              local npc = type(nl) == "number" and floor(nl / 128) or 0
              local lv = type(nl) == "number" and nl % 128 or 0
              local e = agg[npc]
              if not e then
                e = { id = npc, n = 0 }
                agg[npc] = e
                order[#order + 1] = e
              end
              e.n = e.n + 1
              if lv > 0 then
                if not e.l0 or lv < e.l0 then e.l0 = lv end
                if not e.l1 or lv > e.l1 then e.l1 = lv end
              end
              if finite(t) then
                if not e.t0 or t < e.t0 then e.t0 = t end
                if not e.t1 or t > e.t1 then e.t1 = t end
              end
            end
          end
        end
        table.sort(order, function(a, b)
          if a.n ~= b.n then return a.n > b.n end
          return a.id < b.id
        end)
        local lines = {}
        for i = 1, min(#order, Kampf.SPOT_MAX) do
          local e = order[i]
          local parts = { (e.id > 0 and npcName(st, e.id) or TEXT.unknownFoe) .. " · " .. int(e.n) .. "×" }
          local lt = levelsText(e.l0, e.l1)
          if lt then parts[#parts + 1] = lt end
          if e.t0 then
            local d0, d1 = Idx.dayOf(index, e.t0), Idx.dayOf(index, e.t1)
            parts[#parts + 1] = d0 == d1 and TEXT("day", int(d0)) or TEXT("dayRange", int(d0), int(d1))
          end
          lines[#lines + 1] = table.concat(parts, " · ")
        end
        if #order > Kampf.SPOT_MAX then lines[#lines + 1] = "+ " .. int(#order - Kampf.SPOT_MAX) .. " " .. TEXT.moreKinds end
        return lines, count
      end
    end
  end
  if #h.cells > 0 then
    h.mode = "heat"
  else
    for _, m in ipairs(special) do addMarker(m[1], m[2], m[3], m[4]) end
    h.mode = (#h.markers > 0) and "markers" or "empty"
  end
  if h.deaths > 0 then h.note = TEXT("diedHere", int(h.deaths)) end
  if h.mode == "heat" then
    h.caption = TEXT("heatCaption", int(h.kills))
  elseif h.mode == "markers" then
    h.caption = TEXT.noPos
  else
    h.caption = mapID and TEXT.noSpots or TEXT.noZone
  end
  return h
end

local function hitWho(st, r, live)
  local Idx = I()
  local who = npcName(st, posId(Idx.str(r, "DR", "npcID"))) or display(Idx.str(r, "DR", "source"))
  local env = display(Idx.str(r, "DR", "env"))
  local spellID = posId(Idx.str(r, "DR", "spellID"))
  local spell = nil
  if spellID and type(live) == "table" and type(live.spellName) == "function" then
    local ok, n = pcall(live.spellName, spellID)
    if ok then spell = display(n) end
  end
  return who or env or TEXT.unknownFoe, spell
end

local function buildDeath(index, st, i, live)
  local Idx = I()
  local d = st.deaths[i]
  local r = d.rec
  local lv = Idx.num(r, "DE", "level")
  local parts = {}
  local when = whenText(index, r.t)
  if when then parts[#parts + 1] = when end
  local place = deathPlace(st, r)
  if place then parts[#parts + 1] = place end
  if lv and lv >= 1 then parts[#parts + 1] = TEXT("lv", int(lv)) end
  local view = { n = #st.deaths, i = i, title = TEXT("deathTitle", int(i)), sub = table.concat(parts, " · "), hits = {} }
  local maxHP = d.dc and Idx.num(d.dc, "DC", "maxHP") or nil
  if maxHP and maxHP <= 0 then maxHP = nil end
  -- oldest first: largest "ago" first, the client order on ties
  local hits = {}
  for j, h in ipairs(d.hits) do hits[j] = { r = h, j = j, ago = Idx.num(h, "DR", "ago") } end
  table.sort(hits, function(a, b)
    local aa, ba = a.ago or -1, b.ago or -1
    if aa ~= ba then return aa > ba end
    return a.j < b.j
  end)
  local from = max(1, #hits - Kampf.HITS_MAX + 1)
  local span = 0
  for k = from, #hits do
    local h = hits[k].r
    local ev = Idx.str(h, "DR", "event")
    local item
    if ev == nil then
      item = { who = TEXT.gap, amountText = "?", gap = true, tip = { TEXT.gap, TEXT.gapTip } }
    else
      local who, spell = hitWho(st, h, live)
      local amt = Idx.num(h, "DR", "amount")
      local heal = find(ev, "HEAL", 1, true) ~= nil
      local crit = Idx.str(h, "DR", "crit") == "1"
      local hp = Idx.num(h, "DR", "hp")
      local frac = (hp and maxHP and hp >= 0) and min(1, hp / maxHP) or nil
      local amountText = amt and ((heal and "+" or "") .. int(amt)) or "?"
      local tip = { who }
      if spell then tip[#tip + 1] = spell end
      tip[#tip + 1] = TEXT((heal and "heal" or "dmg") .. (crit and "Crit" or ""), amountText)
      if hp then tip[#tip + 1] = maxHP and TEXT("hpBeforeOf", int(hp), int(maxHP)) or TEXT("hpBefore", int(hp)) end
      local ago = hits[k].ago
      if ago and ago > 0 then tip[#tip + 1] = TEXT("agoS", dec1(ago / 10)) end
      item = { who = who, spell = spell, amountText = amountText, crit = crit, hp = frac, heal = heal, tip = tip }
    end
    local ago = hits[k].ago
    if ago and ago > span then span = ago end
    view.hits[#view.hits + 1] = item
  end
  if #view.hits > 0 and span > 0 then view.span = TEXT("span", dec1(span / 10)) end
  if #hits > Kampf.HITS_MAX then view.note = TEXT("lastOf", int(Kampf.HITS_MAX), int(#hits)) end
  if d.dc then
    local c = Idx.str(d.dc, "DC", "cause")
    local word = c and CAUSE[c]
    if word then view.cause = TEXT(Idx.str(d.dc, "DC", "guess") == "1" and "diedGuess" or "died", word) end
  end
  if #view.hits == 0 then view.cause = view.cause or TEXT.noReport end
  return view
end

local function headOf(index, live)
  local char = type(index.char) == "table" and index.char or {}
  local info = type(char.info) == "table" and char.info or {}
  local parts = {}
  local who = display(info.name, 32)
  if who then parts[#parts + 1] = who end
  local rc = {}
  local race, class = display(info.race, 32), display(info.class, 32)
  if race then rc[#rc + 1] = race end
  if class then rc[#rc + 1] = class end
  if #rc > 0 then parts[#parts + 1] = table.concat(rc, " ") end
  local level
  if type(live) == "table" and type(live.level) == "function" then
    local ok, v = pcall(live.level)
    if ok and finite(v) then level = v end
  end
  if not level then
    local list = I().list(index, "LV")
    local last = list[#list]
    level = last and I().num(last, "LV", "level") or nil
  end
  if level then parts[#parts + 1] = TEXT("level", int(level)) end
  return table.concat(parts, " · ")
end

function Kampf.evaluate(index, opts)
  if type(index) ~= "table" then return nil end
  opts = type(opts) == "table" and opts or {}
  local st = Kampf.static(index)
  -- zone choice of the page (opts.hunted): a zone with kills filters the whole page, "all"/nil/unknown shows everything
  local hz = posId(opts.hunted)
  if not (hz and hasKills(st, hz)) then hz = nil end
  local zv
  if hz then
    zv = st.zoneViews[hz]
    if not zv then
      zv = buildZoneView(index, st, hz)
      st.zoneViews[hz] = zv
    end
  end
  local view = {
    head = headOf(index, opts.live), summary = zv and zv.summary or st.summary, tally = zv and zv.tally or st.tally,
    stamps = zv and zv.stamps or st.stamps, hunted = st.hunted, rare = st.rare, zones = st.zones,
    graves = zv and zv.graves or st.graves, close = zv and zv.close or st.close, closeTotal = st.close and st.close.total or 0, allTotal = st.summary.total, zoneKey = hz,
  }
  if zv then view.rare = zv.rare end -- no "zv and zv.rare or ...": an area without a rare enemy shows none
  -- hunting grounds: the chosen zone of the page, else opts.zone, else the zone with the most kills
  local zone = hz or posId(opts.zone)
  local known = false
  for _, z in ipairs(st.zones) do
    if z.mapID == zone then known = true break end
  end
  if not known then zone = st.zones[1] and st.zones[1].mapID or nil end
  local key = zone or 0
  local hunt = st.hunts[key]
  if not hunt then
    hunt = buildHunt(index, st, zone)
    st.hunts[key] = hunt
  end
  view.hunt = hunt
  -- bestiary: all zones or the chosen zone (computed once per zone)
  if hz then
    local h = st.huntedBy[hz]
    if not h then
      h = buildHunted(st, type(index.kills) == "table" and index.kills or {}, hz)
      st.huntedBy[hz] = h
    end
    view.hunted = h
  end
  local deaths = zv and zv.deaths or st.deaths
  local n = #deaths
  if n > 0 then
    local i = tonumber(opts.death)
    if not finite(i) or i < 1 or i > n then i = n end
    i = floor(i)
    view.death = buildDeath(index, zv and zv.st or st, i, opts.live)
  end
  return view
end
