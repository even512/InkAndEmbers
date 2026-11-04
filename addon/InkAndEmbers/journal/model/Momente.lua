-- Evaluator for the Momente page: album (handwritten notes, one per moment), play-time clock, library (read books,
-- letters, signs) and curiosities. Pure read logic over the index and the character SV.
-- Momente.evaluate(index, opts) -> view = { album, clock, library, curios } | nil; the expensive part is computed once
-- per index (Momente.static). All view texts are display-ready.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Momente = {}
Journal.Momente = Momente

local floor, huge, min, max = math.floor, math.huge, math.min, math.max
local format, find, match, lower, upper, sub = string.format, string.find, string.match, string.lower, string.upper, string.sub
local tsort = table.sort

Momente.GROUPS = { "all", "levels", "fights", "finds", "places" }
Momente.FILTER_OK = { all = true, levels = true, fights = true, finds = true, places = true }
Momente.ALBUM_MAX = 4000     -- album entries (the newest stay)
Momente.SHOT_WINDOW = 12     -- seconds: a screenshot belongs to a moment if it is at most this far off
Momente.BOOK_MAX = 500       -- books in the library
Momente.BOOK_SCAN = 5000     -- entries read from the book table (unusually large SV)
Momente.PAGE_MAX = 999       -- highest page number of a book
Momente.PAGES_PER_BOOK = 200 -- pages per book (the rest is not read)
Momente.NAME_MAX = 60        -- bytes for names and titles
Momente.CURIO_LINES = 7      -- lines under "Kurioses"
Momente.EMOTE_SCAN = 500     -- emote counters read
Momente.HOUR_PIECES = 400000 -- hour pieces for the clock (unusually large SV -> truncated)
Momente.SESSION_DAYS = 400   -- longest session the clock still counts

-- locale scope "m.Momente" (English in locales/enUS_model.lua); KINDS read badge/title on access
local Loc = ns.Locale
local TEXT = Loc.ns("m.Momente", {
  noTitle = "Ohne Titel", shot = "Screenshot",
  noClock = "Noch keine Spielzeit erfasst.",
  badge_level = "STUFE", title_level = "Stufe erreicht",
  badge_kill = "ERLEGT", title_kill = "Besonderer Gegner erlegt",
  badge_first_rare = "ERSTER RARER", title_first_rare = "Erster seltener Gegner",
  badge_first_elite = "ERSTER ELITE", title_first_elite = "Erster Elite-Gegner",
  badge_first_boss = "ERSTER BOSS", title_first_boss = "Erster Boss",
  badge_close_win = "KNAPP", title_close_win = "Knapp überlebt",
  badge_first_death = "ERSTER TOD", title_first_death = "Der erste Tod",
  badge_boss = "BOSSKAMPF", title_boss = "Boss bezwungen",
  badge_first_blue = "ERSTES SELTENES", title_first_blue = "Erstes seltenes Stück",
  badge_first_epic = "ERSTES EPISCHES", title_first_epic = "Erstes episches Stück",
  badge_first_bag = "ERSTE TASCHE", title_first_bag = "Erste Tasche",
  badge_first_fish = "ERSTER FANG", title_first_fish = "Erster Fang",
  badge_mount = "REITTIER", title_mount = "Neues Reittier",
  badge_reputation = "RUF", title_reputation = "Neue Rufstufe",
  badge_profession = "HANDWERK", title_profession = "Fortschritt im Handwerk",
  badge_continent = "KONTINENT", title_continent = "Neuer Kontinent",
  badge_first_dungeon = "DUNGEON", title_first_dungeon = "Erster Dungeon",
  badge_first_raid = "SCHLACHTZUG", title_first_raid = "Erster Schlachtzug",
  badge_zone = "NEUE ZONE", title_zone = "Neue Zone entdeckt",
  badge_other = "MOMENT", title_other = "Ein Moment",
  badge_shot = "SCREENSHOT", title_shot = "Screenshot",
  clsTitle_rare = "Seltener Gegner erlegt", clsTitle_rareelite = "Seltener Elite-Gegner erlegt", clsTitle_elite = "Elite-Gegner erlegt",
  clsTitle_worldboss = "Weltboss erlegt",
  clsBadge_rare = "RAR", clsBadge_rareelite = "RAR", clsBadge_elite = "ELITE", clsBadge_worldboss = "BOSS",
  reason_levelup = "Stufe", reason_zone = "neue Zone", reason_kill = "Kampf", reason_boss = "Boss", reason_close_win = "knapper Sieg",
  reason_death = "Tod", reason_item = "Fund", reason_manual = "selbst aufgenommen",
  levelBadge = "STUFE %s",
  levelTitle = "Stufe %s erreicht",
  milestone = "Meilenstein",
  closeHp = "mit %s %% Leben",
  day = "Tag %s",
  dayClock = "Tag %s, %s",
  cap_level = "Wieder ein Stück weiter.", cap_kill = "Ein besonderer Gegner fiel.", cap_first_death = "Der erste Tod.",
  cap_close_win = "Das war knapp.", cap_zone = "Neues Land.", cap_shot = "Ein Bild für die Erinnerung.",
  favHours = "%d bis %d Uhr",
  mat_parchment = "Pergament", mat_stone = "Stein", mat_marble = "Marmor", mat_silver = "Silber", mat_bronze = "Bronze",
  mat_valentine = "Liebesbrief", mat_plaque = "Tafel", mat_metal = "Metall", mat_wood = "Holz",
  emoteOwn = "%s × eigene Emote-Texte",
  emoteNamed = "Emote „%s“ × %s",
  emoteAny = "%s × Emote",
  meals_one = "%s Mahlzeit oder Getränk", meals_other = "%s Mahlzeiten und Getränke",
  potions_one = "%s Trank oder Elixier", potions_other = "%s Tränke, Elixiere und Fläschchen",
  falls_one = "%s Sturz", falls_other = "%s Stürze",
  guessed = "%s (vermutet)",
  guessedSome = "%s (davon %s vermutet)",
  fish_one = "%s Fisch geangelt", fish_other = "%s Fische geangelt",
  afkDozed = "%s abwesend",
})
Momente.TEXT = TEXT

-- value of a key "<prefix><k>" only for known k (else nil, as the old tables)
local function keyed(prefix, known)
  return setmetatable({}, { __index = function(_, k)
    if type(k) == "string" and known[k] then return TEXT[prefix .. k] end
  end })
end

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
  return s and s.display(v, n or Momente.NAME_MAX) or nil
end

local function int(n)
  local t = T()
  return t and t.int(n) or tostring(n)
end

local function rawStr(v)
  if type(v) ~= "string" or v == "" or isSecret(v) then return nil end
  return v
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

local function byId(tbl, id)
  if type(tbl) ~= "table" or isSecret(tbl) or id == nil then return nil end
  local v = tbl[id]
  if v == nil and type(id) == "number" then v = tbl[format("%.0f", id)] end
  return v
end

local function snapGroup(char, name)
  local s = type(char) == "table" and char.snapshots
  local g = type(s) == "table" and s[name]
  return type(g) == "table" and g or nil
end

-- name of an entry in a text/snapshot table (text or { name = text }); raw text
local function nameIn(group, id)
  local e = byId(group, id)
  if type(e) == "table" then e = e.name end
  return rawStr(e)
end

-- group: album filter; badge/title: badge and occasion; icon: symbol in the marker atlas (Theme.ATLAS); color: palette name
local KINDS = {
  level = { group = "levels", icon = "level", color = "gold" },
  kill = { group = "fights", icon = "rare", color = "red" },
  first_rare = { group = "fights", icon = "rare", color = "red" },
  first_elite = { group = "fights", icon = "elite", color = "red" },
  first_boss = { group = "fights", icon = "boss", color = "red" },
  close_win = { group = "fights", icon = "elite", color = "memory" },
  first_death = { group = "fights", icon = "death", color = "memory" },
  boss = { group = "fights", icon = "boss", color = "red" },
  first_blue = { group = "finds", icon = "milestone", color = "blue" },
  first_epic = { group = "finds", icon = "milestone", color = "blue" },
  first_bag = { group = "finds", icon = "milestone", color = "blue" },
  first_fish = { group = "finds", icon = "milestone", color = "blue" },
  mount = { group = "finds", icon = "flightpoint", color = "blue" },
  reputation = { group = "finds", icon = "milestone", color = "blue" },
  profession = { group = "finds", icon = "milestone", color = "blue" },
  continent = { group = "places", icon = "flightpoint", color = "treasure" },
  first_dungeon = { group = "places", icon = "boss", color = "treasure" },
  first_raid = { group = "places", icon = "boss", color = "treasure" },
  zone = { group = "places", icon = "flightpoint", color = "treasure" },
  other = { group = "finds", icon = "milestone", color = "blue" },
  shot = { group = nil, icon = "photo", color = "memory" },
}
for id, def in pairs(KINDS) do
  def.id, def.badge, def.title = id, nil, nil
  setmetatable(def, { __index = function(t, k)
    if k == "badge" then return TEXT["badge_" .. t.id] end
    if k == "title" then return TEXT["title_" .. t.id] end
  end })
end
Momente.KINDS = KINDS

local CLS = { rare = true, rareelite = true, elite = true, worldboss = true }
local CLS_TITLE = keyed("clsTitle_", CLS)
local CLS_BADGE = keyed("clsBadge_", CLS)
local SHOT_REASON = keyed("reason_", { levelup = true, zone = true, kill = true, boss = true, close_win = true, death = true,
  item = true, manual = true })
local SHOT_KEY = "^%d%d%d%d%d%d_%d%d%d%d%d%d$"

local function clockText(index, t)
  local h, m = I().timeOfDay(index, t)
  if not h then return nil end
  return format("%02d:%02d", h, m)
end

-- entry from a MO/ZN line -> entry (with entry.ctx = variables for the caption, raw values) | nil
local function momentEntry(index, char, r, code, maps)
  local Idx = I()
  local kind, value, detail, level, mapID, subz
  if code == "ZN" then
    if Idx.str(r, "ZN", "mapType") ~= "3" then return nil end
    kind, mapID, level = "zone", posId(Idx.str(r, "ZN", "mapID")), Idx.num(r, "ZN", "level")
  else
    kind = Idx.str(r, "MO", "kind")
    if not kind or not find(kind, "^[%a_]+$") or #kind > 24 or not KINDS[kind] or kind == "zone" or kind == "shot" then kind = "other" end
    value, detail = Idx.str(r, "MO", "value"), Idx.str(r, "MO", "detail")
    level, mapID, subz = Idx.num(r, "MO", "level"), posId(Idx.str(r, "MO", "mapID")), rawStr(Idx.str(r, "MO", "sub"))
  end
  local def = KINDS[kind]
  if level and (level < 1 or level > 200) then level = nil end
  if level then level = floor(level) end
  local zoneRaw = mapID and nameIn(maps, mapID) or nil
  local ctx = { kind = kind, level = level, zone = subz or zoneRaw }
  local badge, title, what, itemLink, itemID = def.badge, def.title, nil, nil, nil
  local npcs, items = type(char.npcs) == "table" and char.npcs or nil, snapGroup(char, "items")

  if kind == "level" then
    local L = Idx.num(r, "MO", "value")
    if L and L >= 1 and L <= 200 then level = floor(L) end
    ctx.level = level
    if level then
      badge, title = TEXT("levelBadge", int(level)), TEXT("levelTitle", int(level))
    end
    if detail == "1" then
      what = TEXT.milestone
      ctx.milestone = true
    end
  elseif kind == "kill" or kind == "first_rare" or kind == "first_elite" or kind == "first_boss" then
    local npc = nameIn(npcs, posId(value))
    ctx.npc = npc
    what = npc
    if kind == "kill" and detail then
      title = CLS_TITLE[detail] or title
      badge = CLS_BADGE[detail] or badge
    end
  elseif kind == "close_win" then
    local hp = tonumber(value)
    if finite(hp) and hp >= 0 and hp <= 100 then
      ctx.hp = floor(hp + 0.5)
      what = TEXT("closeHp", int(ctx.hp))
    end
  elseif kind == "boss" then
    local enc = nameIn(snapGroup(char, "encounters"), posId(value))
    ctx.enc, what = enc, enc
  elseif kind == "first_blue" or kind == "first_epic" or kind == "first_bag" or kind == "first_fish" then
    local item = nameIn(items, posId(value))
    ctx.item, what = item, item
    -- original item tooltip (first blue/epic/bag/catch): item string only from the checked itemID
    itemLink = Journal.Texts and Journal.Texts.itemString(posId(value)) or nil
    itemID = posId(value)
  elseif kind == "first_dungeon" or kind == "first_raid" then
    local inst = nameIn(snapGroup(char, "instances"), posId(value))
    ctx.inst, what = inst, inst
  elseif kind == "continent" then
    local c = nameIn(maps, posId(value))
    ctx.zone = c or ctx.zone
    what = c
  elseif kind == "mount" then
    local m = rawStr(value)
    ctx.mount, what = m, m
  elseif kind == "reputation" then
    local f = rawStr(value)
    ctx.faction = f
    local st = tonumber(detail)
    local Chronik = Journal.Chronik
    local word = Chronik and Chronik.standingName and st and Chronik.standingName(floor(st)) or nil
    if f then what = word and (f .. ": " .. word) or f end
  elseif kind == "profession" then
    local sk = rawStr(value)
    ctx.skill = sk
    local v = tonumber(detail)
    if sk then what = (finite(v) and v > 0) and (sk .. " " .. int(floor(v))) or sk end
  end

  local t = r.t
  if not finite(t) then return nil end
  local clock = clockText(index, t)
  local day = I().dayOf(index, t)
  local Chronik = Journal.Chronik
  local e = {
    key = code .. ":" .. format("%.0f", r.ln or 0), kind = kind, group = def.group, t = t, ln = r.ln or 0,
    badge = badge, title = title, what = what and display(what, Momente.NAME_MAX) or nil, level = level,
    sub = subz and display(subz, 40) or nil, zone = zoneRaw and display(zoneRaw, 40) or nil, day = day, clock = clock,
    when = clock and TEXT("dayClock", int(day), clock) or TEXT("day", int(day)),
    date = Chronik and Chronik.dateText and Chronik.dateText(index, t) or nil,
    icon = def.icon, color = def.color, ctx = ctx, item = itemLink, mapID = mapID, itemID = itemID,
  }
  e.place = e.sub or e.zone
  return e
end

-- screenshot without a moment: own entry (only under "Alle")
local function shotEntry(index, char, r, maps)
  local Idx = I()
  local key = Idx.str(r, "SH", "key")
  if not key or not find(key, SHOT_KEY) then return nil end
  local t = r.t
  if not finite(t) then return nil end
  local def = KINDS.shot
  local level = Idx.num(r, "SH", "level")
  if level and (level < 1 or level > 200) then level = nil end
  local mapID = posId(Idx.str(r, "SH", "mapID"))
  local zoneRaw = mapID and nameIn(maps, mapID) or nil
  local subz = rawStr(Idx.str(r, "SH", "sub"))
  local words = {}
  local reasons = Idx.str(r, "SH", "reasons")
  if reasons then
    for token in string.gmatch(reasons, "[%a_]+") do
      local w = SHOT_REASON[token]
      if w then
        local dup = false
        for _, x in ipairs(words) do if x == w then dup = true end end
        if not dup then words[#words + 1] = w end
      end
    end
  end
  local clock = clockText(index, t)
  local day = I().dayOf(index, t)
  local Chronik = Journal.Chronik
  local e = {
    key = "SH:" .. format("%.0f", r.ln or 0), kind = "shot", group = nil, t = t, ln = r.ln or 0, badge = def.badge,
    title = def.title, what = #words > 0 and table.concat(words, ", ") or nil, level = level and floor(level) or nil,
    sub = subz and display(subz, 40) or nil, zone = zoneRaw and display(zoneRaw, 40) or nil, day = day, clock = clock,
    when = clock and TEXT("dayClock", int(day), clock) or TEXT("day", int(day)),
    date = Chronik and Chronik.dateText and Chronik.dateText(index, t) or nil,
    icon = def.icon, color = def.color, shot = "WoWScrnShot_" .. key .. ".jpg", ctx = { kind = "shot", level = level },
  }
  e.place = e.sub or e.zone
  return e
end

local function lowerBound(arr, t) -- first index i with arr[i].t >= t (#arr + 1 if none)
  local lo, hi = 1, #arr + 1
  while lo < hi do
    local mid = floor((lo + hi) / 2)
    if arr[mid].t < t then lo = mid + 1 else hi = mid end
  end
  return lo
end

local FALLBACK_CAPTION = keyed("cap_", { level = true, kill = true, first_death = true, close_win = true, zone = true, shot = true })

-- caption of an entry (text library, group "moment"): deterministic per entry, computed only when shown. used
-- (optional) = ids already on this page; a snippet is not repeated there while others exist. The result is
-- display-ready.
function Momente.caption(album, e, used)
  if type(e) ~= "table" then return "" end
  local Texts = T()
  local seed = type(album) == "table" and album.seed or "0"
  if not e.capText then
    local text, id
    if Texts and e.ctx then text, id = Texts.pick("moment", e.ctx, seed, e.key, {}) end
    e.capText, e.capId = text or FALLBACK_CAPTION[e.kind] or FALLBACK_CAPTION.shot, id
  end
  if type(used) ~= "table" then return e.capText end
  if e.capId and used[e.capId] and Texts and e.ctx then
    local text, id = Texts.pick("moment", e.ctx, seed, e.key, used)
    if text then
      used[id] = true
      return text
    end
  end
  if e.capId then used[e.capId] = true end
  return e.capText
end

local function buildAlbum(index, char)
  local Idx = I()
  local maps = snapGroup(char, "maps")
  local list = {}
  -- The starting continent and the starting zone (the first of each in the log) are no moments: nothing was
  -- discovered, the character just woke up there. (The "Jenseits des Meeres" medal still counts the start continent.)
  local skipContinent = true
  for _, r in ipairs(Idx.list(index, "MO")) do
    local ok, e = pcall(momentEntry, index, char, r, "MO", maps)
    if ok and e and e.kind == "continent" and skipContinent then
      skipContinent = false
    elseif ok and e then
      list[#list + 1] = e
    end
  end
  local zones = 0
  local skipZone = true
  for _, r in ipairs(Idx.list(index, "ZN")) do
    local ok, e = pcall(momentEntry, index, char, r, "ZN", maps)
    if ok and e and skipZone then
      skipZone = false
    elseif ok and e then
      list[#list + 1] = e
      zones = zones + 1
    end
  end
  local cmp = function(a, b)
    if a.t ~= b.t then return a.t < b.t end
    return a.ln < b.ln
  end
  tsort(list, cmp)
  local truncated = false
  if #list > Momente.ALBUM_MAX then
    local keep = {}
    for i = #list - Momente.ALBUM_MAX + 1, #list do keep[#keep + 1] = list[i] end
    list, truncated = keep, true
  end
  local info = type(char.info) == "table" and char.info or {}

  -- screenshots: at most the next one within the window per moment; the rest become loose entries
  local loose, shots = {}, 0
  for _, r in ipairs(Idx.list(index, "SH")) do
    local key = Idx.str(r, "SH", "key")
    if key and find(key, SHOT_KEY) and finite(r.t) then
      shots = shots + 1
      local best, bestDt
      if #list > 0 then
        local i = lowerBound(list, r.t)
        for j = max(1, i - 2), min(#list, i + 1) do
          local dt = math.abs(list[j].t - r.t)
          if dt <= Momente.SHOT_WINDOW and (not bestDt or dt < bestDt) then best, bestDt = list[j], dt end
        end
      end
      local looseRec = r
      if best and (not best.shotDt or bestDt < best.shotDt) then
        if best.shotRec then loose[#loose + 1] = best.shotRec end
        best.shot, best.shotDt, best.shotRec = "WoWScrnShot_" .. key .. ".jpg", bestDt, r
        looseRec = nil
      end
      if looseRec then loose[#loose + 1] = looseRec end
    end
  end
  for _, e in ipairs(list) do e.shotDt, e.shotRec = nil, nil end
  local nLoose = 0
  local shotList = {}
  for _, r in ipairs(loose) do
    local ok, e = pcall(shotEntry, index, char, r, maps)
    if ok and e then
      shotList[#shotList + 1] = e
      nLoose = nLoose + 1
    end
  end
  local entries = {}
  for _, e in ipairs(list) do entries[#entries + 1] = e end
  for _, e in ipairs(shotList) do entries[#entries + 1] = e end
  tsort(entries, function(a, b) -- newest first
    if a.t ~= b.t then return a.t > b.t end
    return a.ln > b.ln
  end)
  local counts = { all = #entries, levels = 0, fights = 0, finds = 0, places = 0 }
  for _, e in ipairs(entries) do
    if e.group then counts[e.group] = counts[e.group] + 1 end
  end
  return { entries = entries, total = #list, zones = zones, shots = shots, loose = nLoose, counts = counts,
    truncated = truncated, lists = { all = entries }, seed = T() and T().seed(info.firstSeen) or "0" }
end

function Momente.filter(album, group)
  if type(album) ~= "table" then return {} end
  if group == nil or group == "all" then return album.entries or {} end
  album.lists = album.lists or {}
  local l = album.lists[group]
  if l then return l end
  l = {}
  for _, e in ipairs(album.entries or {}) do
    if e.group == group then l[#l + 1] = e end
  end
  album.lists[group] = l
  return l
end

-- spread the period [t0, t1] over the 24 hours (character local time); budget.n = remaining pieces
local function addHours(index, hours, t0, t1, budget)
  local Idx = I()
  local cur = t0
  while cur < t1 and budget.n > 0 do
    local h, m, s = Idx.timeOfDay(index, cur)
    if not h then break end
    local piece = min(t1 - cur, 3600 - (m * 60 + s))
    hours[h + 1] = hours[h + 1] + piece
    cur = cur + piece
    budget.n = budget.n - 1
  end
  if cur < t1 then budget.cut = true end
end

local function clampSpan(t0, t1)
  local cap = Momente.SESSION_DAYS * 86400
  if t1 - t0 > cap then t1 = t0 + cap end
  return t0, t1
end

local function buildClock(index)
  local hours = {}
  for h = 1, 24 do hours[h] = 0 end
  local budget = { n = Momente.HOUR_PIECES }
  local sp = type(index.sessions) == "table" and index.sessions or nil
  local longest, openFrom = 0, nil
  if sp and type(sp.t0) == "table" then
    for i = 1, #sp.t0 do
      local a, b = sp.t0[i], sp.t1[i]
      if finite(a) then
        if b == huge then
          openFrom = a
        elseif finite(b) and b > a then
          local x, y = clampSpan(a, b)
          addHours(index, hours, x, y, budget)
          if y - x > longest then longest = y - x end
        end
      end
    end
  end
  return { hours = hours, longest = longest, openFrom = openFrom, truncated = budget.cut == true }
end

-- sessions of the character (count, of which interrupted) from meta.sessions
local function sessionStats(db, guid)
  local meta = type(db) == "table" and type(db.meta) == "table" and db.meta or nil
  local list = meta and type(meta.sessions) == "table" and meta.sessions or nil
  local n, broken = 0, 0
  if not list then return 0, 0 end
  local from = max(1, #list - I().SESSION_MAX + 1)
  for i = from, #list do
    local s = list[i]
    if type(s) == "table" and s.guid == guid then
      n = n + 1
      if s.interrupted then broken = broken + 1 end
    end
  end
  return n, broken
end

local function clockView(index, st, db, now)
  local hours = {}
  for h = 1, 24 do hours[h] = st.hours[h] end
  local longest, cut = st.longest, st.truncated
  if st.openFrom and finite(now) and now > st.openFrom then
    local x, y = clampSpan(st.openFrom, now)
    local budget = { n = Momente.HOUR_PIECES }
    addHours(index, hours, x, y, budget)
    if y - x > longest then longest = y - x end
    cut = cut or budget.cut == true
  end
  local total, top, fav = 0, 0, nil
  for h = 1, 24 do
    total = total + hours[h]
    if hours[h] > top then top, fav = hours[h], h - 1 end
  end
  local sessions, interrupted = sessionStats(db, index.guid)
  local Chronik = Journal.Chronik
  local v = { hours = hours, total = total, hasData = total > 0, fav = fav, longest = longest, sessions = sessions,
    interrupted = interrupted, truncated = cut }
  if fav then v.favText = TEXT("favHours", fav, (fav + 1) % 24) end
  if longest > 0 then v.longestText = Chronik and Chronik.duration(longest) or nil end
  return v
end

local MATERIAL = keyed("mat_", { parchment = true, stone = true, marble = true, silver = true, bronze = true, valentine = true,
  plaque = true, metal = true, wood = true })

local function buildLibrary(index, char)
  local Idx = I()
  local books = type(char.books) == "table" and not isSecret(char.books) and char.books or nil
  local out, pagesTotal, truncated = {}, 0, false
  if not books then return { books = out, count = 0, pages = 0, truncated = false } end
  -- first read time per book from the BK lines
  local first = {}
  for _, r in ipairs(Idx.list(index, "BK")) do
    local key = Idx.str(r, "BK", "key")
    if key and not first[key] and finite(r.t) then first[key] = r end
  end
  local maps = snapGroup(char, "maps")
  local scanned = 0
  for key, b in pairs(books) do
    scanned = scanned + 1
    if scanned > Momente.BOOK_SCAN then
      truncated = true
      break
    end
    if type(key) == "string" and type(b) == "table" and not isSecret(b) then
      local pages = {}
      for k, v in pairs(b) do
        if type(k) == "string" and #k <= 4 and type(v) == "string" and v ~= "" and not isSecret(v) then
          local n = match(k, "^p(%d+)$")
          n = n and tonumber(n)
          if n and n >= 1 and n <= Momente.PAGE_MAX then pages[#pages + 1] = n end
        end
      end
      if #pages > 0 then
        tsort(pages)
        while #pages > Momente.PAGES_PER_BOOK do pages[#pages] = nil end
        local rec = first[key]
        local t = rec and rec.t or tonumber(b.firstAt)
        if not finite(t) then t = 0 end
        local mapID = posId(b.mapID) or (rec and posId(Idx.str(rec, "BK", "mapID"))) or nil
        local zone = mapID and nameIn(maps, mapID) or nil
        local mat = type(b.material) == "string" and not isSecret(b.material) and lower(sub(b.material, 1, 24)) or nil
        local book = {
          key = key, title = display(b.title, Momente.NAME_MAX) or TEXT.noTitle, material = mat and MATERIAL[mat] or nil,
          nPages = #pages, last = pages[#pages], pages = pages, t = t,
          day = t > 0 and Idx.dayOf(index, t) or nil, level = rec and Idx.num(rec, "BK", "level") or nil,
          zone = zone and display(zone, 40) or nil,
        }
        if book.level and (book.level < 1 or book.level > 200) then book.level = nil end
        out[#out + 1] = book
        pagesTotal = pagesTotal + #pages
      end
    end
  end
  tsort(out, function(a, b)
    if a.t ~= b.t then return a.t > b.t end
    if a.title ~= b.title then return a.title < b.title end
    return a.key < b.key
  end)
  if #out > Momente.BOOK_MAX then
    for i = #out, Momente.BOOK_MAX + 1, -1 do
      pagesTotal = pagesTotal - out[i].nPages
      out[i] = nil
    end
    truncated = true
  end
  return { books = out, count = #out, pages = pagesTotal, truncated = truncated }
end

-- wording of a book page (long text, sanitized, capped). nil: missing or unreadable.
function Momente.bookPage(index, book, n)
  if type(index) ~= "table" or type(book) ~= "table" then return nil end
  local char = index.char
  local books = type(char) == "table" and type(char.books) == "table" and char.books or nil
  local b = books and type(book.key) == "string" and books[book.key] or nil
  n = tonumber(n)
  if type(b) ~= "table" or not finite(n) or n < 1 or n > Momente.PAGE_MAX then return nil end
  local QB = Journal.QuestBook
  if not QB then return nil end
  return QB.longText(b["p" .. format("%.0f", floor(n))], QB.TEXT_MAX)
end

local function counterGroup(char, name)
  local c = type(char) == "table" and type(char.counters) == "table" and char.counters or nil
  local g = c and c[name]
  return type(g) == "table" and not isSecret(g) and g or nil
end

local function count(v)
  if isSecret(v) or not finite(v) or v < 0 then return nil end
  if v > 2 ^ 40 then v = 2 ^ 40 end
  return floor(v)
end

-- number with plural key (<key>_one / <key>_other, "%s" = the number)
local function plural(n, key)
  return TEXT(Loc.plural(n, key .. "_one", key .. "_other"), int(n))
end

local function emoteLines(char, seed, room)
  local g = counterGroup(char, "emotes")
  if not g or room < 1 then return {} end
  local list, scanned = {}, 0
  for token, n in pairs(g) do
    scanned = scanned + 1
    if scanned > Momente.EMOTE_SCAN then break end
    n = count(n)
    if type(token) == "string" and n and n > 0 then list[#list + 1] = { token = token, n = n } end
  end
  tsort(list, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return a.token < b.token
  end)
  local Texts = T()
  local out, used = {}, {}
  for i = 1, min(room, #list) do
    local e = list[i]
    local tokenUp = upper(sub(e.token, 1, 24))
    local text
    if find(tokenUp, "^[A-Z_]+$") and tokenUp ~= "UNKNOWN" and Texts then
      text = Texts.pick("curio", { token = tokenUp, count = e.n }, seed, tokenUp, used)
    end
    if not text then
      if tokenUp == "UNKNOWN" then
        text = TEXT("emoteOwn", int(e.n))
      else
        local name = display(lower(sub(e.token, 1, 24)), 24)
        text = name and TEXT("emoteNamed", name, int(e.n)) or TEXT("emoteAny", int(e.n))
      end
    end
    out[#out + 1] = text
  end
  return out
end

local function sumGroup(g, keys)
  local total = 0
  if not g then return 0 end
  for _, k in ipairs(keys) do total = total + (count(g[k]) or 0) end
  return total
end

local function fallCount(index)
  local Idx = I()
  local n, guessed = 0, 0
  for _, r in ipairs(Idx.list(index, "DC")) do
    if Idx.str(r, "DC", "cause") == "fall" then
      n = n + 1
      if Idx.str(r, "DC", "guess") == "1" then guessed = guessed + 1 end
    end
  end
  return n, guessed
end

local function buildCurios(index, char, seed, falls, now)
  local facts = {}
  -- away time (AFK) from the character SV, read by Chronik.afk (journal/model/Chronik.lua)
  local Chr = Journal.Chronik
  local afk = Chr and Chr.afk and Chr.afk(char, now) or nil
  if afk and afk.seconds >= Chr.AFK_MIN_SHOWN then facts[#facts + 1] = TEXT("afkDozed", Chr.duration(afk.seconds)) end
  local consumed = counterGroup(char, "consumed")
  local meals = sumGroup(consumed, { "food_drink" })
  if meals > 0 then facts[#facts + 1] = plural(meals, "meals") end
  local potions = sumGroup(consumed, { "potion", "elixir", "flask" })
  if potions > 0 then facts[#facts + 1] = plural(potions, "potions") end
  if falls.n > 0 then
    local word = plural(falls.n, "falls")
    if falls.guessed >= falls.n then
      word = TEXT("guessed", word)
    elseif falls.guessed > 0 then
      word = TEXT("guessedSome", word, int(falls.guessed))
    end
    facts[#facts + 1] = word
  end
  local fish = 0
  local fg = counterGroup(char, "fishing")
  if fg then
    local scanned = 0
    for _, v in pairs(fg) do
      scanned = scanned + 1
      if scanned > Momente.EMOTE_SCAN then break end
      fish = fish + (count(v) or 0)
    end
  end
  local lines = emoteLines(char, seed, max(1, Momente.CURIO_LINES - #facts - 1))
  for _, f in ipairs(facts) do lines[#lines + 1] = f end
  if fish > 0 or #lines > 0 then lines[#lines + 1] = plural(fish, "fish") end
  while #lines > Momente.CURIO_LINES do lines[#lines] = nil end
  return { lines = lines, any = #lines > 0 }
end

local cache = setmetatable({}, { __mode = "k" })

function Momente.static(index)
  local st = cache[index]
  if not st then
    local char = type(index.char) == "table" and index.char or {}
    local falls = { n = 0 }
    falls.n, falls.guessed = fallCount(index)
    st = { album = buildAlbum(index, char), clock = buildClock(index), library = buildLibrary(index, char), falls = falls,
      char = char }
    local info = type(char.info) == "table" and char.info or {}
    st.seed = T() and T().seed(info.firstSeen) or "0"
    cache[index] = st
  end
  return st
end

function Momente.evaluate(index, opts)
  if type(index) ~= "table" then return nil end
  opts = type(opts) == "table" and opts or {}
  local now = tonumber(opts.now) or time()
  local db = opts.db or EveNChronicleDB
  local st = Momente.static(index)
  return {
    now = now, album = st.album, library = st.library,
    clock = clockView(index, st.clock, db, now),
    curios = buildCurios(index, st.char, st.seed, st.falls, now),
  }
end
