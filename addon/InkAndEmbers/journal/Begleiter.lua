-- Travel companion cards: welcome back, campfire recap, "plan done". No frame of its own: the cards run through the
-- journal/Toast.lua queue. Data comes from the core (ns.Welcome, ns.Rest, ns.Plans); this file only picks and words.
-- All foreign text goes through Sanitize.display before SetText, numbers through format("%d"). The welcome card never
-- shows on /reload or in combat; the recap only if ns.Rest.shouldShow allows it.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Begleiter = {}
Journal.Begleiter = Begleiter

local floor, format = math.floor, string.format

Begleiter.NAME_MAX = 40
Begleiter.LINE_MAX = 90
Begleiter.RETRY = 10
Begleiter.TRIES = 3

Begleiter.TEXT = ns.Locale.ns("Begleiter", {
  welcomePre = "Willkommen zurück, ",
  welcomeNoName = "Willkommen zurück.",
  firstPre = "Willkommen, ",
  firstNoName = "Willkommen.",
  namePost = ".",
  firstLine1 = "Eure Reise beginnt hier.",
  firstLine2 = "Die Chronik schreibt ab jetzt mit.",
  firstLine3 = "Das Buch öffnet Ihr über den Knopf an der Minimap oder mit /chronik.",
  lastSeenPre = "Zuletzt: ",
  lastSeenSep = " · ",
  lastSeenAgo = "Zuletzt gesehen %s",
  openOne = "1 offene Quest",
  openMany = "%d offene Quests",
  rested = "Ruhebonus %d %%",
  restedPlain = "Ruhebonus",
  sep = " · ",
  noQuests = "Keine offenen Quests",
  nearbyPre = "To Do in der Nähe: ",
  acceptedPre = "Zuletzt angenommen: „",
  acceptedPost = "“",
  tipTitle = "Offene Quests",
  tipMore = "… und %d weitere",
  restHeadFire = "Am Lagerfeuer",
  restHeadInn = "Im Gasthaus",
  restHead = "Rast",
  restTitle = "Seit der letzten Rast …",
  restTitleFirst = "Seit Beginn der Reise …",
  restNothing = "Noch nichts Neues seit der letzten Rast.",
  restWalk = "%s unterwegs, %s km",
  restWalkApprox = "%s unterwegs, ca. %s km",
  restTime = "%s unterwegs",
  restKm = "%s km zu Fuß",
  restKmApprox = "ca. %s km zu Fuß",
  restKills = "%d Kills",
  restKill = "1 Kill",
  restQuests = "%d Quests abgegeben",
  restQuest = "1 Quest abgegeben",
  restLevel = "Stufe %d erreicht",
  restLevels = "Stufen %d bis %d erreicht",
  restBest = "Bester Fund: %s",
  restBuilding = "Die Chronik sortiert noch. Gleich noch einmal versuchen.",
  planHead = "To Do erledigt",
  planDonePre = "Erledigt: ",
  planZone = "Angekommen: %s",
  planPlace = "Ort erreicht",
  planPlaceIn = "Ort erreicht in %s",
  planKill = "%d Gegner besiegt",
  planKillOne = "Gegner besiegt",
  planItem = "%d Stück gefunden",
  planItemOne = "Gefunden",
  planOpen = "Noch %d offene To Dos",
  planOneOpen = "Noch ein offenes To Do",
  planNoneOpen = "Keine offenen To Dos mehr",
  welcomeUsage = "/chronik willkommen zeigt die Begrüßungskarte als Vorschau.",
  welcomeNotReady = "Die Begrüßungskarte ist noch nicht bereit.",
  restUsage = "/chronik rast zeigt den Rückblick als Vorschau.",
  welcomeOn = "Begrüßung beim Einloggen eingeschaltet.",
  welcomeOff = "Begrüßung beim Einloggen ausgeschaltet.",
  agoNow = "gerade eben",
  agoMin_one = "vor 1 Minute", agoMin_other = "vor %d Minuten",
  agoHour_one = "vor 1 Stunde", agoHour_other = "vor %d Stunden",
  agoDay_one = "vor 1 Tag", agoDay_other = "vor %d Tagen",
  agoWeek_one = "vor 1 Woche", agoWeek_other = "vor %d Wochen",
  agoMonth_one = "vor 1 Monat", agoMonth_other = "vor %d Monaten",
  agoYear = "vor über einem Jahr",
  agoShortMin = "vor %d Min.",
  agoShortHour = "vor %d Std.",
})

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function Pages() return Journal.Pages end
local function Toast() return Journal.Toast end

local function setting(key)
  local P = Pages()
  if not P or type(P.setting) ~= "function" then return true end
  return P.setting(key) ~= false
end

local function setSetting(key, on)
  local P = Pages()
  return P and P.setSetting(key, on and true or false) or false
end

function Begleiter.welcomeOn() return setting("welcome") end
function Begleiter.setWelcome(on) return setSetting("welcome", on) end
function Begleiter.restOn() return setting("restReview") end

-- Narrator of the welcome card (portrait in the ring, Theme.NARRATORS): setting "narrator" = "own" (default, race of the
-- character), "random" (new pick per card) or a fixed id. Race from UnitRace("player") (English token, second return value).
Begleiter.RACE_NARRATOR = { Human = "human", Dwarf = "dwarf", NightElf = "nightelf", Gnome = "gnome", Orc = "orc",
  Scourge = "undead", Undead = "undead", Tauren = "tauren", Troll = "troll" }

local function narratorIds()
  local Theme = Journal.Theme
  return Theme and type(Theme.NARRATORS) == "table" and Theme.NARRATORS or {}
end

local function isNarrator(id)
  for _, n in ipairs(narratorIds()) do
    if n == id then return true end
  end
  return false
end

-- race token (+ localized name, faction) -> narrator id. Skyborne: the Forever client's token is not known for sure, so any
-- token/name containing "sky" counts (Skyborne, Skyborn, ...). Unknown race: Horde -> orc, everything else -> human.
function Begleiter.narratorForRace(token, name, faction)
  if type(token) == "string" and not isSecret(token) then
    local hit = Begleiter.RACE_NARRATOR[token]
    if hit then return hit end
    if string.find(string.lower(token), "sky", 1, true) then return "skyborne" end
  end
  if type(name) == "string" and not isSecret(name) and string.find(string.lower(name), "sky", 1, true) then return "skyborne" end
  if faction == "Horde" then return "orc" end
  return "human"
end

function Begleiter.narratorChoice()
  local P = Pages()
  local v = P and type(P.setting) == "function" and P.setting("narrator") or nil
  if v == "own" or v == "random" or isNarrator(v) then return v end
  return "own"
end

function Begleiter.setNarrator(v)
  if v ~= "own" and v ~= "random" and not isNarrator(v) then return false end
  local P = Pages()
  return P and type(P.setSetting) == "function" and P.setSetting("narrator", v) or false
end

-- -> narrator id for the next card. rnd(n) -> 1..n (tests); default math.random
function Begleiter.narrator(choice, rnd)
  choice = choice or Begleiter.narratorChoice()
  if isNarrator(choice) then return choice end
  local ids = narratorIds()
  if choice == "random" and #ids > 0 then
    local ok, i = pcall(rnd or math.random, #ids)
    i = ok and tonumber(i) or 1
    if i ~= i or i == math.huge or i == -math.huge then i = 1 end
    return ids[math.max(1, math.min(#ids, floor(i)))]
  end
  local name, token, faction
  if type(UnitRace) == "function" then
    local ok, n, t = pcall(UnitRace, "player")
    if ok then name, token = n, t end
  end
  if type(UnitFactionGroup) == "function" then
    local ok, f = pcall(UnitFactionGroup, "player")
    if ok and not isSecret(f) then faction = f end
  end
  return Begleiter.narratorForRace(token, name, faction)
end

local function narratorIcon()
  local Theme = Journal.Theme
  if not Theme or not Theme.HAS_NARRATORS or type(Theme.narratorTex) ~= "function" then return nil end
  local id = Begleiter.narrator()
  local tex = Theme.narratorTex(id)
  return tex and { tex = tex, portrait = true, narrator = id } or nil
end
function Begleiter.setRest(on) return setSetting("restReview", on) end

-- Foreign text for display: only via Sanitize.display (codes, bidi, "|" -> "||"); nil if empty
local function shown(s, max)
  if isSecret(s) or type(s) ~= "string" then return nil end
  return ns.Sanitize.display(s, max or Begleiter.LINE_MAX)
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function plural(n, base)
  return Begleiter.TEXT(ns.Locale.plural(n, base .. "_one", base .. "_other"), n)
end

function Begleiter.agoText(seconds)
  seconds = num(seconds)
  if not seconds then return nil end
  if seconds < 0 then seconds = 0 end
  if seconds < 60 then return Begleiter.TEXT.agoNow end
  local minutes = floor(seconds / 60)
  if minutes < 60 then return plural(minutes, "agoMin") end
  local hours = floor(minutes / 60)
  if hours < 24 then return plural(hours, "agoHour") end
  local days = floor(hours / 24)
  if days < 14 then return plural(days, "agoDay") end
  if days < 60 then return plural(floor(days / 7), "agoWeek") end
  if days < 365 then return plural(floor(days / 30), "agoMonth") end
  return Begleiter.TEXT.agoYear
end

function Begleiter.agoShort(seconds)
  seconds = num(seconds)
  if not seconds then return nil end
  if seconds < 0 then seconds = 0 end
  if seconds < 60 then return Begleiter.TEXT.agoNow end
  local minutes = floor(seconds / 60)
  if minutes < 60 then return Begleiter.TEXT("agoShortMin", minutes) end
  local hours = floor(minutes / 60)
  if hours < 24 then return Begleiter.TEXT("agoShortHour", hours) end
  local days = floor(hours / 24)
  if days < 14 then return plural(days, "agoDay") end
  if days < 60 then return plural(floor(days / 7), "agoWeek") end
  if days < 365 then return plural(floor(days / 30), "agoMonth") end
  return Begleiter.TEXT.agoYear
end

local function durationText(seconds)
  seconds = num(seconds) or 0
  local minutes = floor(seconds / 60 + 0.5)
  if minutes < 1 then return nil end
  return Journal.Fmt.duration(minutes * 60)
end

local function kmText(km)
  km = num(km)
  if not km or km < 0.1 then return nil end
  return Journal.Fmt.km(km)
end

local function seal()
  local Theme = Journal.Theme
  local T = Toast()
  if Theme and Theme.TEX and Theme.TEX.zoneSeal then return { tex = Theme.TEX.zoneSeal, size = T and T.ICON_ZONE or 58 } end
  if T and T.zoneIcon then return T.zoneIcon() end
  return nil
end

local function fitted(kind, prefix, name, suffix)
  local T = Toast()
  if kind == "title" and T and type(T.fit) == "function" then
    local ok, line = pcall(T.fit, kind, prefix, name, suffix)
    if ok and type(line) == "string" then return line end
  end
  return prefix .. name .. (suffix or "")
end

function Begleiter.welcomeItem(s)
  if type(s) ~= "table" then return nil end
  local T = Begleiter.TEXT
  local name = shown(s.name, Begleiter.NAME_MAX)
  local item = { kind = "card", key = "welcome", always = true, noOpen = true, hold = true, sound = "feather",
    duration = Toast() and Toast().CARD.duration or 10, icon = narratorIcon() or seal(), lines = {} }
  local lines = item.lines
  if s.first then
    item.title = name and fitted("title", T.firstPre, name, T.namePost) or T.firstNoName
    lines[1], lines[2], lines[3] = T.firstLine1, T.firstLine2, T.firstLine3
    return item
  end
  item.title = name and fitted("title", T.welcomePre, name, T.namePost) or T.welcomeNoName
  local zone = shown(s.lastZone)
  local ago = Begleiter.agoShort(s.lastSeenAgo)
  if zone and ago then
    lines[#lines + 1] = fitted("line", T.lastSeenPre, zone, T.lastSeenSep .. ago)
  elseif zone then
    lines[#lines + 1] = fitted("line", T.lastSeenPre, zone, "")
  elseif ago then
    lines[#lines + 1] = format(T.lastSeenAgo, ago)
  end
  local q = type(s.openQuests) == "table" and s.openQuests or nil
  local count = q and num(q.count) or 0
  local parts = {}
  if count >= 1 then
    parts[#parts + 1] = floor(count) == 1 and T.openOne or format(T.openMany, floor(count))
  end
  local pct = num(s.restedPct)
  if pct and pct > 0 then
    parts[#parts + 1] = format(T.rested, floor(pct))
  elseif num(s.restedXP) and s.restedXP > 0 then
    parts[#parts + 1] = T.restedPlain
  end
  if #parts > 0 then lines[#lines + 1] = table.concat(parts, T.sep) end
  local near = type(s.vorhabenNearby) == "table" and s.vorhabenNearby or {}
  local plan = #near > 0 and shown(near[1] and near[1].text, Begleiter.LINE_MAX) or nil
  local accepted = q and shown(q.lastAccepted, Begleiter.LINE_MAX) or nil
  if plan then
    lines[#lines + 1] = fitted("line", T.nearbyPre, plan, "")
  elseif accepted then
    lines[#lines + 1] = fitted("line", T.acceptedPre, accepted, T.acceptedPost)
  end
  if #lines == 0 then lines[1] = T.noQuests end
  local names = {}
  for i = 1, math.min(5, q and type(q.names) == "table" and #q.names or 0) do
    local n = shown(q.names[i])
    if n then names[#names + 1] = n end
  end
  if count >= 1 and #names > 0 then
    item.tooltip = { title = T.tipTitle, lines = names, more = floor(count) > #names and format(T.tipMore, floor(count) - #names) or nil }
  end
  return item
end

function Begleiter.restItem(sum, kind)
  local T = Begleiter.TEXT
  local item = { kind = "card", key = "rest:" .. tostring(sum and sum.to or "x"), always = true, noOpen = true, sound = "feather",
    duration = 7, icon = seal(), lines = {} }
  item.head = kind == "fire" and T.restHeadFire or (kind == "inn" and T.restHeadInn or T.restHead)
  item.title = (type(sum) == "table" and sum.first) and T.restTitleFirst or T.restTitle
  local lines = item.lines
  if type(sum) ~= "table" then return item end
  local dur, km = durationText(sum.seconds), kmText(sum.km)
  if dur and km then
    lines[#lines + 1] = format(sum.kmApprox and T.restWalkApprox or T.restWalk, dur, km)
  elseif dur then
    lines[#lines + 1] = format(T.restTime, dur)
  elseif km then
    lines[#lines + 1] = format(sum.kmApprox and T.restKmApprox or T.restKm, km)
  end
  local parts = {}
  local kills = num(sum.kills) or 0
  if kills > 0 then parts[#parts + 1] = kills == 1 and T.restKill or format(T.restKills, floor(kills)) end
  local quests = num(sum.quests) or 0
  if quests > 0 then parts[#parts + 1] = quests == 1 and T.restQuest or format(T.restQuests, floor(quests)) end
  if #parts > 0 then lines[#lines + 1] = table.concat(parts, " · ") end
  local levels = type(sum.levels) == "table" and sum.levels or {}
  local lo, hi
  for _, l in ipairs(levels) do
    l = num(l)
    if l then
      lo = (not lo or l < lo) and l or lo
      hi = (not hi or l > hi) and l or hi
    end
  end
  if hi then
    lines[#lines + 1] = (lo and lo < hi) and format(T.restLevels, floor(lo), floor(hi)) or format(T.restLevel, floor(hi))
  end
  local best = type(sum.loot) == "table" and sum.loot.best or nil
  local name = type(best) == "table" and shown(best.name, 50) or nil
  if name and #lines < Toast().CARD.maxLines then lines[#lines + 1] = format(T.restBest, name) end
  if #lines == 0 then lines[1] = T.restNothing end
  return item
end

local function mapName(mapID)
  mapID = num(mapID)
  if not mapID then return nil end
  local Store = ns.Store
  local char = Store and Store.char and Store.char()
  local snaps = type(char) == "table" and char.snapshots
  local maps = type(snaps) == "table" and snaps.maps
  local e = type(maps) == "table" and maps[mapID] or nil
  local name = type(e) == "table" and e.name or nil
  if (isSecret(name) or type(name) ~= "string" or name == "") and ns.Zone then
    local info = ns.Zone.info(mapID)
    name = info and info.name or nil
  end
  return shown(name, Toast() and Toast().NAME_MAX or 40)
end
Begleiter.mapName = mapName

-- Waits longer in combat than other toasts (maxAge) so it does not expire after a long fight.
Begleiter.PLAN_DURATION = 7
Begleiter.PLAN_MAX_AGE = 300

local function openCount()
  local P = ns.Plans
  if not P or type(P.list) ~= "function" then return nil end
  local ok, list = pcall(P.list, "open")
  return (ok and type(list) == "table") and #list or nil
end

function Begleiter.planItem(plan)
  if type(plan) ~= "table" then return nil end
  local T = Begleiter.TEXT
  local name = shown(type(plan.label) == "string" and plan.label or plan.text, Begleiter.LINE_MAX) or ""
  local zone = mapName(plan.mapID)
  local item = { kind = "card", key = "plan:" .. tostring(plan.id), always = true, open = "reise", sound = "todoDone",
    hold = true, duration = Begleiter.PLAN_DURATION, maxAge = Begleiter.PLAN_MAX_AGE, icon = seal(), lines = {},
    head = T.planHead, title = fitted("title", T.planDonePre, name, ""), sub = zone }
  item.after = function()
    local F = Journal.Frame
    if F and type(F.showSub) == "function" then F.showSub("vorhaben") end
  end
  local lines = item.lines
  local how = plan.how
  local need = tonumber(plan.need)
  if how == "place" then
    lines[1] = zone and format(T.planPlaceIn, zone) or T.planPlace
  elseif how == "kill" and need then
    lines[1] = need == 1 and T.planKillOne or format(T.planKill, floor(need))
  elseif how == "item" and need then
    lines[1] = need == 1 and T.planItemOne or format(T.planItem, floor(need))
  elseif zone then
    lines[1] = format(T.planZone, zone)
  end
  local n = openCount()
  if n then lines[#lines + 1] = (n == 0 and T.planNoneOpen) or (n == 1 and T.planOneOpen) or format(T.planOpen, n) end
  return item
end

local function enqueue(item)
  local T = Toast()
  if not T or not item then return false end
  return T.enqueue(item)
end

local function welcomeCard(summary)
  if not setting("welcome") then return false end
  return enqueue(Begleiter.welcomeItem(summary))
end

-- First login of the account: the intro (journal/Tutorial.lua) goes first, the card follows once it is closed.
function Begleiter.onWelcome(summary)
  local Tu = Journal.Tutorial
  if Tu and type(Tu.firstRun) == "function" and Tu.firstRun(function() welcomeCard(summary) end) then return true end
  return welcomeCard(summary)
end

-- recap; the index may still be building right after login: retry a few times
local function review(info, tries)
  if not setting("restReview") then return false end
  local FN = Journal.FireNotes
  if info.kind == "fire" and FN and type(FN.suppressesCard) == "function" and FN.suppressesCard() then return false end
  local Rest = ns.Rest
  if not Rest or type(Rest.summary) ~= "function" or type(Rest.shouldShow) ~= "function" then return false end
  if not Rest.shouldShow(info.t) then return false end
  local sum, why = Rest.summary(nil, { from = info.prev or false, to = info.t })
  if not sum then
    if (why == "baut" or why == "keine-daten") and tries < Begleiter.TRIES and type(C_Timer) == "table" then
      C_Timer.After(Begleiter.RETRY, function() review(info, tries + 1) end)
    end
    return false
  end
  if sum.empty then return false end
  local ok = enqueue(Begleiter.restItem(sum, info.kind))
  if ok and type(Rest.markShown) == "function" then Rest.markShown(info.t) end
  return ok
end

function Begleiter.onRest(info)
  if type(info) ~= "table" then return false end
  return review(info, 1)
end

-- Sound right on completion (also in combat; the toast itself waits), then the card without a second sound.
function Begleiter.onPlanDone(plan)
  local item = Begleiter.planItem(plan)
  if not item then return false end
  local T, S = Toast(), Journal.Sound
  if T and T.soundOn() and S and type(S.play) == "function" then
    pcall(S.play, "todoDone")
    item.silent = true
  end
  return enqueue(item)
end

function Begleiter.slash(cmd)
  local print_ = ns.Core and ns.Core.print or function() end
  local T = Begleiter.TEXT
  if cmd == "willkommen" then
    if not ns.Welcome or type(ns.Welcome.summary) ~= "function" then
      print_(T.welcomeNotReady)
      return true
    end
    local item = Begleiter.welcomeItem(ns.Welcome.summary())
    if item then
      item.key = "welcome:preview"
      enqueue(item)
    end
    return true
  elseif cmd == "rast" then
    local Rest = ns.Rest
    if not Rest or type(Rest.summary) ~= "function" then
      print_(T.restBuilding)
      return true
    end
    local sum = Rest.summary(nil, {})
    if not sum then
      print_(T.restBuilding)
      return true
    end
    local item = Begleiter.restItem(sum, nil)
    item.key = "rest:preview"
    enqueue(item)
    return true
  end
  return false
end

local function safeHook(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok and ns.Core and ns.Core.coreError then ns.Core.coreError(err) end
  end
end

if type(ns.onLoginWelcome) == "function" then ns.onLoginWelcome(safeHook(Begleiter.onWelcome)) end
if type(ns.onRestStart) == "function" then ns.onRestStart(safeHook(Begleiter.onRest)) end
if type(ns.onPlanDone) == "function" then ns.onPlanDone(safeHook(Begleiter.onPlanDone)) end
