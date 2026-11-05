-- Travel companion cards: welcome back, campfire recap, "plan done". No frame of its own: the cards run through the
-- journal/Toast.lua queue. Data comes from the core (ns.Welcome, ns.Rest, ns.Plans); this file only picks and words.
-- All foreign text goes through Sanitize.display before SetText, numbers through format("%d"). The welcome greeting never
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
  welcomeUsage = "/chronik willkommen zeigt den Willkommen-Gruß als Vorschau.",
  welcomeNotReady = "Der Willkommen-Gruß ist noch nicht bereit.",
  restUsage = "/chronik rast zeigt den Rückblick als Vorschau.",
  welcomeOn = "Willkommen-Gruß eingeschaltet.",
  welcomeOff = "Willkommen-Gruß ausgeschaltet.",
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
-- the welcome-back note no longer has a switch of its own (one option "Welcome greeting" covers the first greeting and the return);
-- the old names stay as aliases so nothing that still calls them breaks
Begleiter.slipOn = Begleiter.welcomeOn
Begleiter.setSlip = Begleiter.setWelcome
-- "Show after an absence of": seconds (0 = at every login, not on /reload); default 1 hour
Begleiter.AFTER = { 0, 3600, 7200, 14400, 28800, 86400 }
Begleiter.AFTER_DEFAULT = 3600
function Begleiter.afterSeconds()
  local P = Pages()
  local v = P and type(P.setting) == "function" and P.setting("welcomeAfter") or nil
  if type(v) ~= "number" then return Begleiter.AFTER_DEFAULT end
  return v
end
function Begleiter.setAfter(seconds)
  local P = Pages()
  return P ~= nil and P.setSetting("welcomeAfter", seconds) or false
end
-- info lines of the return note: seen (zone + how long ago), quests (open quests), rested (rested bonus), plan (to-do nearby / last accepted quest)
Begleiter.INFOS = { "seen", "quests", "rested", "plan" }
local INFO_KEY = { seen = "welcomeSeen", quests = "welcomeQuests", rested = "welcomeRested", plan = "welcomePlan" }
function Begleiter.infoOn(info) return INFO_KEY[info] ~= nil and setting(INFO_KEY[info]) end
function Begleiter.setInfo(info, on) return INFO_KEY[info] ~= nil and setSetting(INFO_KEY[info], on) end
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
function Begleiter.setRest(on)
  local ok = setSetting("restReview", on)
  -- the campfire recap is an edit-mode element only while this option is on
  local EM = Journal.EditMode
  if EM and type(EM.syncPreview) == "function" then pcall(EM.syncPreview) end
  return ok
end

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
  -- the player picks which info lines show (options); a deselected part is left out, the order stays
  local wantSeen, wantQuests = Begleiter.infoOn("seen"), Begleiter.infoOn("quests")
  local wantRested, wantPlan = Begleiter.infoOn("rested"), Begleiter.infoOn("plan")
  local zone = shown(s.lastZone)
  local ago = Begleiter.agoShort(s.lastSeenAgo)
  if wantSeen then
    if zone and ago then
      lines[#lines + 1] = fitted("line", T.lastSeenPre, zone, T.lastSeenSep .. ago)
    elseif zone then
      lines[#lines + 1] = fitted("line", T.lastSeenPre, zone, "")
    elseif ago then
      lines[#lines + 1] = format(T.lastSeenAgo, ago)
    end
  end
  local q = type(s.openQuests) == "table" and s.openQuests or nil
  local count = q and num(q.count) or 0
  local parts = {}
  if wantQuests and count >= 1 then
    parts[#parts + 1] = floor(count) == 1 and T.openOne or format(T.openMany, floor(count))
  end
  local pct = num(s.restedPct)
  if wantRested then
    if pct and pct > 0 then
      parts[#parts + 1] = format(T.rested, floor(pct))
    elseif num(s.restedXP) and s.restedXP > 0 then
      parts[#parts + 1] = T.restedPlain
    end
  end
  if #parts > 0 then lines[#lines + 1] = table.concat(parts, T.sep) end
  local near = type(s.vorhabenNearby) == "table" and s.vorhabenNearby or {}
  local plan = wantPlan and #near > 0 and shown(near[1] and near[1].text, Begleiter.LINE_MAX) or nil
  local accepted = wantPlan and q and shown(q.lastAccepted, Begleiter.LINE_MAX) or nil
  if plan then
    lines[#lines + 1] = fitted("line", T.nearbyPre, plan, "")
  elseif accepted then
    lines[#lines + 1] = fitted("line", T.acceptedPre, accepted, T.acceptedPost)
  end
  -- the "no open quests" placeholder only stands in for the quest info; with it deselected the greeting stands alone
  if #lines == 0 and wantQuests then lines[1] = T.noQuests end
  local names = {}
  for i = 1, math.min(5, q and type(q.names) == "table" and #q.names or 0) do
    local n = shown(q.names[i])
    if n then names[#names + 1] = n end
  end
  if wantQuests and count >= 1 and #names > 0 then
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

-- Quiet first login: on the very first login of the account only the introduction (journal/Tutorial.lua) shows. No area pop-up
-- for the starting zone and no welcome card. Journal/Toast.lua stays untouched: its enqueue is wrapped here and turns zone items
-- down while the login is quiet. Quiet = the introduction is still to come (not seen yet, before this file's login hook ran)
-- or it is open (until it is closed).
Begleiter.QUIET_MAX = 600 -- s: the area-toast mute never lasts longer than this
local quiet, handled = false, false
function Begleiter.quietLogin()
  if quiet then return true end
  local Tu = Journal.Tutorial
  return not handled and Tu ~= nil and Tu.AUTO == true and type(Tu.seen) == "function" and not Tu.seen()
end

do
  local T = Toast()
  if T and type(T.enqueue) == "function" and not T.quietWrapped then
    local orig = T.enqueue
    T.enqueue = function(item, ...)
      if type(item) == "table" and item.kind == "zone" and Begleiter.quietLogin() then return false end
      return orig(item, ...)
    end
    T.quietWrapped = true
  end
end

-- Welcome-back note, "all of one piece": Media/WelcomeBack.tga (art/toast/welcome_back_v2.jpg: round wood-bronze frame with lantern and
-- quill, parchment with red bookmark) IS the whole note. The narrator portrait (the main element, same narratorIcon() as the card) lies
-- UNDER the frame, exactly in the frame's transparent circle. It glides in from the LEFT screen edge and back out. Only after a longer
-- break (more than the chosen absence, Begleiter.afterSeconds(), default 1 hour; "at once" = every login), 3 s after the area text has gone. Not on /reload (the login
-- hook does not run there). On a character's very first session the same note greets with the first-time text ("Willkommen, <name>.").
-- Its place, size and opacity come from the edit-mode element "slip" (Begleiter.slipSpot).
-- Measures: texture crop 2584 x 1430 source px shown at w x h = 420 x 232 (scale 420 / 2584, measures in scripts/render-media.mjs ->
-- WELCOME_BACK_CROP / WELCOME_BACK_CIRCLE): circle centre (circleX | circleY) from the top left, circle radius circleR (transparent hole).
-- portrait = diameter of the narrator's circle (a few px more than the hole, the overlap is hidden under the frame); the narrator
-- texture is 512 px with its circle (r 176) at (256 | 250), so the texture is drawn portrait * 512 / 352 wide.
-- textX/textW/textTop/textBottom = the parchment area (right of the bookmark, inside the paper edge), the text block is centred there.
Begleiter.SLIP = { w = 420, h = 232, circleX = 104, circleY = 107, circleR = 61, portrait = 128,
  textX = 214, textW = 182, textTop = 44, textBottom = 196, titleSize = 14, bodySize = 11,
  glow = { x = 26, y = 172, w = 34, h = 54, u1 = 0.0635, u2 = 0.1436, v1 = 0.74, v2 = 0.97, min = 0.08, max = 0.3, period = 3.2 },
  anim = 0.4, hold = 12, delay = 3, y = -40, maxLines = 3, maxLinesFirst = 3, tries = 3, retry = 10, glideEdge = 210 }
-- Pop-out figure per race (Media/NarratorFigIn_<id>.tga + NarratorFigOut_<id>.tga, scripts/render-media.mjs NARRATOR_CUTOUTS, measures from
-- scripts/measure-cutout.py): the figure stands BEHIND the ring, inside the circle. Layers bottom to top: backdrop (f.portrait,
-- NarratorBG_<id>), figIn (the figure masked to the circle), the frame, cutout (the same figure: only above a cut line plus everything
-- outside the outer ring, so head, shoulders, arms reach out in front of the ring). Both figure layers share the box
-- x, y (px from the frame's top left, negative y = above the note), w x h. Races without an entry keep the plain portrait in the circle.
-- inset = px the whole note stops right of the screen edge, so the arm reaching out on the left is not cut off. dim = backdrop tint.
Begleiter.CUTOUTS = {
  undead = { x = 25.9, y = -21.8, w = 166.8, h = 199.8, inset = 12, dim = 1 },
  human = { x = -8.2, y = -21.9, w = 202.8, h = 199.9, inset = 12, dim = 1 },
  dwarf = { x = -8.0, y = -21.7, w = 207.0, h = 199.7, inset = 12, dim = 1 },
  nightelf = { x = -8.1, y = -21.8, w = 185.0, h = 199.8, inset = 12, dim = 1 },
  gnome = { x = 28.0, y = -21.7, w = 159.9, h = 199.7, inset = 12, dim = 1 },
  orc = { x = 21.0, y = -21.7, w = 161.2, h = 199.7, inset = 12, dim = 1 },
  tauren = { x = -8.0, y = -21.7, w = 191.9, h = 199.7, inset = 12, dim = 1 },
  troll = { x = -8.2, y = -60.0, w = 198.5, h = 238.0, inset = 12, dim = 1 },
  skyborne = { x = 8.9, y = -21.8, w = 191.1, h = 199.8, inset = 12, dim = 1 },
}
local slip = { frame = nil, phase = nil, t = 0, glowT = 0 }
Begleiter.slipState = slip

function Begleiter.slipTotalW()
  return Begleiter.SLIP.w
end

function Begleiter.slipTextX()
  return Begleiter.SLIP.textX
end

function Begleiter.slipTextW()
  return Begleiter.SLIP.textW
end

-- size of the narrator texture so that its circle (352 of 512 px) has the diameter SLIP.portrait
function Begleiter.slipPortraitTex()
  return floor(Begleiter.SLIP.portrait * 512 / 352 + 0.5)
end

-- Where the note rests: the edit-mode element "slip" (journal/EditMode.lua: saved position, size, opacity per layout). Without a
-- saved position it is the old default (left screen edge, SLIP.y, a figure's inset), so nothing changes unless the player moves it.
-- -> { point, rel, x, y (rest anchor in the note's own scale), scale, alpha, custom }
function Begleiter.slipSpot()
  local S, EM = Begleiter.SLIP, Journal.EditMode
  local v = EM and type(EM.values) == "function" and EM.values("slip") or nil
  local k = v and num(v.scale) and floor(v.scale / 100 * (EM.BASE_SCALE or 1) * 1000 + 0.5) / 1000 or 1
  local alpha = v and num(v.alpha) and v.alpha / 100 or 1
  local p = v and v.pos
  if type(p) == "table" and type(p.point) == "string" and num(p.x) and num(p.y) then
    return { point = p.point, rel = p.rel or p.point, x = p.x, y = p.y, scale = k, alpha = alpha, custom = true }
  end
  -- default: screen distances stay the same at any size (offsets are in the note's own scale)
  return { point = "LEFT", rel = "LEFT", x = 0, y = S.y / k, scale = k, alpha = alpha, custom = false }
end

local LEFT_POINTS = { LEFT = true, TOPLEFT = true, BOTTOMLEFT = true }

-- Rest position and entrance: the note glides in from the left screen edge when it rests close to it (its left edge within
-- SLIP.glideEdge, in the note's own scale), otherwise it fades in and out where it is: a glide across half the screen to a free
-- position looks like a flying window, a short fade is calmer. -> spot + restX (x at rest) + startX (glide start, nil = fade)
local function slipPlan(f, inset)
  local sp = Begleiter.slipSpot()
  sp.restX = sp.x + (sp.custom and 0 or inset / sp.scale)
  local left
  if LEFT_POINTS[sp.point] and LEFT_POINTS[sp.rel] then
    left = sp.restX
  elseif f.GetLeft then
    f:ClearAllPoints()
    f:SetPoint(sp.point, UIParent, sp.rel, sp.restX, sp.y)
    left = num(f:GetLeft())
  end
  if left and left <= Begleiter.SLIP.glideEdge then sp.startX = sp.restX - (left + Begleiter.slipTotalW()) end
  return sp
end

-- x offset of the whole note along its anchor: startX (fully outside the left edge) .. restX (in place)
local function slipX(f, x)
  f.slipOffset = x
  f:ClearAllPoints()
  f:SetPoint(f.slipSpot.point, UIParent, f.slipSpot.rel, x, f.slipSpot.y)
end

-- t: 0 (gone) .. 1 (in place), as glide position or fade opacity
local function slipProgress(f, t)
  local sp = f.slipSpot
  if sp.startX then
    slipX(f, sp.startX + (sp.restX - sp.startX) * t)
  else
    slipX(f, sp.restX)
    f:SetAlpha(sp.alpha * t)
  end
end

local function slipFrame()
  if slip.frame then return slip.frame end
  local S = Begleiter.SLIP
  local TT = Journal.TodoTracker
  local Theme = Journal.Theme
  local tex = Theme and Theme.TEX and Theme.TEX.welcomeBack
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(S.w, S.h)
  f:SetPoint("LEFT", UIParent, "LEFT", -S.w, S.y)
  f:SetFrameStrata("DIALOG")
  f:EnableMouse(true)
  f:Hide()
  -- narrator portrait: the main element, UNDER the frame texture, centred on the circle
  f.portrait = f:CreateTexture(nil, "BACKGROUND")
  local ps = Begleiter.slipPortraitTex()
  f.portrait:SetSize(ps, ps)
  -- the narrator circle sits 6 of 512 px above the texture centre
  f.portrait:SetPoint("CENTER", f, "TOPLEFT", S.circleX, -(S.circleY + floor(6 * ps / 512 + 0.5)))
  f.portrait:Hide()
  -- the note itself (frame, parchment)
  f.art = f:CreateTexture(nil, "ARTWORK")
  f.art:SetAllPoints(f)
  if tex then f.art:SetTexture(tex) end
  -- the figure stands behind the ring inside the circle (between backdrop and frame) ...
  f.figIn = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  f.figIn:Hide()
  -- ... and its upper part in front of the ring (only for races with an entry in CUTOUTS)
  f.cutout = f:CreateTexture(nil, "OVERLAY", nil, 3)
  f.cutout:Hide()
  -- lantern: the lantern region of the same texture, additive, pulses softly (no extra graphic)
  local G = S.glow
  f.glow = f:CreateTexture(nil, "OVERLAY")
  if tex then f.glow:SetTexture(tex) end
  f.glow:SetTexCoord(G.u1, G.u2, G.v1, G.v2)
  f.glow:SetSize(G.w, G.h)
  f.glow:SetPoint("TOPLEFT", f, "TOPLEFT", G.x, -G.y)
  if f.glow.SetBlendMode then f.glow:SetBlendMode("ADD") end
  f.glow:SetAlpha(G.min)
  local fontString, setFont
  if TT then fontString, setFont = TT.fontString, TT.setFont end
  if fontString then
    f.title = fontString(f, "OVERLAY")
    setFont(f.title, "text", S.titleSize)
    f.setFont = setFont
    f.body = fontString(f, "OVERLAY")
    setFont(f.body, "text", S.bodySize)
  else
    f.title = f:CreateFontString(nil, "OVERLAY")
    f.body = f:CreateFontString(nil, "OVERLAY")
  end
  f.title:SetTextColor(0.36, 0.12, 0.07) -- dark red-brown ink
  f.body:SetTextColor(0.20, 0.13, 0.07)  -- dark brown ink
  for _, fs in ipairs({ f.title, f.body }) do
    fs:SetWidth(S.textW)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
  end
  f.body:SetSpacing(3)
  f:SetScript("OnMouseUp", function() Begleiter.closeSlip() end)
  f:SetScript("OnHide", function(self)
    slip.phase = nil
    self:SetScript("OnUpdate", nil)
  end)
  slip.frame = f
  return f
end

-- decelerating glide (ease-out cubic)
local function ease(p)
  local q = 1 - p
  return 1 - q * q * q
end

function Begleiter.slipStep(dt)
  local f, S = slip.frame, Begleiter.SLIP
  if not f or not slip.phase then return end
  slip.t = slip.t + (num(dt) or 0)
  local G = S.glow
  slip.glowT = slip.glowT + (num(dt) or 0)
  if f.glow then f.glow:SetAlpha(G.min + (G.max - G.min) * (0.5 + 0.5 * math.sin(slip.glowT * 2 * math.pi / G.period))) end
  if slip.phase == "open" then
    local p = math.min(1, slip.t / S.anim)
    slipProgress(f, ease(p))
    if p >= 1 then slip.phase, slip.t = "hold", 0 end
  elseif slip.phase == "hold" then
    if slip.t >= S.hold then Begleiter.closeSlip() end
  elseif slip.phase == "close" then
    local p = math.min(1, slip.t / S.anim)
    slipProgress(f, 1 - ease(p))
    if p >= 1 then
      f:Hide()
      local w = slip.waiting
      slip.waiting = nil
      if w then w() end
    end
  end
end

-- the narrator leaves to the left again (click or after SLIP.hold seconds)
function Begleiter.closeSlip()
  local f = slip.frame
  if not f or not f:IsShown() or slip.phase == "close" then return false end
  slip.phase, slip.t = "close", 0
  return true
end

function Begleiter.slipShown()
  return slip.frame ~= nil and slip.frame:IsShown() and true or false
end

-- is the break long enough? s.lastSeenAgo = seconds since the character's last session (nil: unknown -> no note). With the
-- choice "at once" (0) every real login qualifies (the login hook does not run on /reload).
function Begleiter.slipDue(s)
  if type(s) ~= "table" then return false end
  local pause = Begleiter.afterSeconds()
  if pause <= 0 then return true end
  local ago = num(s.lastSeenAgo)
  return ago ~= nil and ago > pause
end

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return ok and not isSecret(v) and v == true
end

-- Draws the note with prepared content (the welcome greeting and the level-up note share frame, narrator, glide and sound):
-- content = { kind = "welcome" | "level", title = text (may hold "\n"), variants = { { line, ... }, ... } }. The variants run from
-- the fullest to the leanest set of body lines: the first one that fits the parchment is shown (the last one always is).
function Begleiter.showNote(content)
  local S = Begleiter.SLIP
  if type(content) ~= "table" then return false end
  local f = slipFrame()
  -- the title may be two lines (welcome: "Willkommen zurück," / name) so even long names stay on the parchment; if it is still
  -- wider than the text area, the font shrinks step by step (TITLE_SIZES)
  f.title:SetText(content.title or "")
  if f.setFont and f.title.SetWidth and f.title.GetStringWidth then
    f.title:SetWidth(1000)
    for _, size in ipairs({ S.titleSize, 13, 12, 11, 10 }) do
      if size <= S.titleSize then
        f.setFont(f.title, "text", size)
        local w = num(f.title:GetStringWidth())
        if not w or w <= S.textW then break end
      end
    end
    f.title:SetWidth(S.textW)
  end
  local variants = type(content.variants) == "table" and #content.variants > 0 and content.variants or { {} }
  f.body:ClearAllPoints()
  f.title:ClearAllPoints()
  local th, bh
  local gap = 4
  for vi, lines in ipairs(variants) do
    f.body:SetText(table.concat(lines, "\n"))
    th = num(f.title.GetStringHeight and f.title:GetStringHeight()) or 18
    if th < 8 then th = 18 end
    if #lines == 0 then
      bh, gap = 0, 0 -- no body lines: the title stands alone
      break
    end
    bh = num(f.body.GetStringHeight and f.body:GetStringHeight()) or (14 * #lines)
    if bh < 8 then bh = 14 * math.max(1, #lines) end
    if th + 4 + bh <= S.textBottom - S.textTop or #lines <= 1 or vi == #variants then break end
  end
  slip.kind = content.kind or "welcome"
  -- text block centred on the parchment (not above the bookmark: textX is right of it)
  local block = th + gap + bh
  local top = S.textTop + ((S.textBottom - S.textTop) - block) / 2
  if top < S.textTop then top = S.textTop end
  top = floor(top + 0.5)
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", S.textX, -top)
  f.body:SetPoint("TOPLEFT", f, "TOPLEFT", S.textX, -(top + th + gap))
  local nar = narratorIcon()
  if nar and nar.tex then f.portrait:SetTexture(nar.tex) end
  f.portrait:SetShown(nar ~= nil and nar.tex ~= nil)
  -- pop-out figure: the portrait becomes the landscape backdrop, the figure stands in the circle behind the ring, upper body in front
  local Theme = Journal.Theme
  local co = nar and Begleiter.CUTOUTS[nar.narrator] or nil
  local cotex = co and Theme and Theme.TEX and Theme.TEX["narratorFigOut_" .. nar.narrator] or nil
  local intex = co and Theme and Theme.TEX and Theme.TEX["narratorFigIn_" .. nar.narrator] or nil
  if cotex and intex then
    for _, t in ipairs({ { f.cutout, cotex }, { f.figIn, intex } }) do
      t[1]:SetTexture(t[2])
      t[1]:SetSize(co.w, co.h)
      t[1]:ClearAllPoints()
      t[1]:SetPoint("TOPLEFT", f, "TOPLEFT", co.x, -co.y)
      t[1]:Show()
    end
    -- the circle shows the race's landscape backdrop (Media/NarratorBG_<id>.tga, same circle geometry as the portrait), not the portrait
    local bg = Theme.TEX["narratorBG_" .. tostring(nar.narrator)]
    if bg then f.portrait:SetTexture(bg) end
    f.portrait:SetVertexColor(co.dim, co.dim, co.dim)
    f.slipInset = co.inset or 0
  else
    f.cutout:Hide()
    f.figIn:Hide()
    f.portrait:SetVertexColor(1, 1, 1)
    f.slipInset = 0
  end
  f.slipNarrator = nar and nar.narrator or nil
  f.slipH = S.h
  slip.glowT = 0
  slip.phase, slip.t = "open", 0
  -- position, size and opacity from the edit-mode element (default: old place at the left edge)
  -- scale first: the glide/fade decision in slipPlan measures the note's left edge (GetLeft) with the current scale
  f:SetScale(Begleiter.slipSpot().scale)
  f.slipSpot = slipPlan(f, f.slipInset or 0)
  f:SetAlpha(f.slipSpot.startX and f.slipSpot.alpha or 0)
  slipProgress(f, 0)
  f:Show()
  f:SetScript("OnUpdate", function(_, dt)
    if ns.Core then ns.Core.safe(Begleiter.slipStep, dt) else Begleiter.slipStep(dt) end
  end)
  local T, Snd = Toast(), Journal.Sound
  if T and T.soundOn() and Snd and type(Snd.play) == "function" then pcall(Snd.play, "feather") end
  return true
end

-- which note is on screen: "welcome" | "level" | nil (none; a note that is just leaving still counts)
function Begleiter.slipKind()
  if slip.frame ~= nil and slip.frame:IsShown() then return slip.kind or "welcome" end
  return nil
end

-- Runs fn once, as soon as the note on screen has left again. false (fn not stored) if no note is on screen. A newer call replaces
-- the older one (only the latest state matters).
function Begleiter.afterSlip(fn)
  if type(fn) ~= "function" or not Begleiter.slipKind() then return false end
  slip.waiting = fn
  return true
end

-- show the note now (force: also for the preview /chronik willkommen zettel). Waits in combat and tries again a few times.
function Begleiter.showSlip(s, tries, force)
  local S = Begleiter.SLIP
  if type(s) ~= "table" then return false end
  if not force and not setting("welcome") then return false end
  if inCombat() then
    if (tries or 1) < S.tries and type(C_Timer) == "table" then
      C_Timer.After(S.retry, function() Begleiter.showSlip(s, (tries or 1) + 1, force) end)
    end
    return false
  end
  local item = Begleiter.welcomeItem(s)
  if not item then return false end
  -- title on two lines ("Willkommen zurück," / name)
  local title = item.title or ""
  local nm = shown(s.name, Begleiter.NAME_MAX)
  if nm then
    local pre = s.first and Begleiter.TEXT.firstPre or Begleiter.TEXT.welcomePre
    title = (pre:gsub("%s+$", "")) .. "\n" .. nm .. Begleiter.TEXT.namePost
  end
  -- up to three lines (the first visit: the three first-time lines, the last one says how to open the book; the return: the info
  -- lines the player picked); if they do not fit the parchment, the first visit drops the second line first, the return its last
  local lines = {}
  for i = 1, math.min(s.first and S.maxLinesFirst or S.maxLines, #item.lines) do lines[#lines + 1] = item.lines[i] end
  local variants = {}
  while true do
    local copy = {}
    for i, l in ipairs(lines) do copy[i] = l end
    variants[#variants + 1] = copy
    if #lines <= 1 then break end
    table.remove(lines, (s.first and #lines >= 3) and 2 or #lines)
  end
  return Begleiter.showNote({ kind = "welcome", title = title, variants = variants })
end

-- First login of the account: only the introduction (journal/Tutorial.lua); no card, no area pop-up while it is open.
-- Every later login: the note with the first-time text for a character's first session, otherwise the welcome-back note after a
-- long break. The big welcome card is gone (it only remains for the campfire recap, key "rest:").
function Begleiter.onWelcome(summary)
  handled = true
  local Tu = Journal.Tutorial
  local function release() quiet = false end
  if Tu and type(Tu.firstRun) == "function" and Tu.firstRun(release) then
    quiet = true
    -- safety net: if the introduction closes another way and the callback never runs, the mute still ends
    -- (when the window hides, at the latest after QUIET_MAX seconds)
    local f = type(Tu.state) == "table" and Tu.state.frame or nil
    if f and type(f.HookScript) == "function" then pcall(f.HookScript, f, "OnHide", release) end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(Begleiter.QUIET_MAX, release) end
    return true
  end
  if not setting("welcome") then return false end
  -- one switch covers both: the first greeting of a character and the return after the chosen absence
  local firstSession = type(summary) == "table" and summary.first == true
  if not firstSession and not Begleiter.slipDue(summary) then return false end
  if type(C_Timer) == "table" then
    C_Timer.After(Begleiter.SLIP.delay, function() Begleiter.showSlip(summary, 1) end)
    return true
  end
  return Begleiter.showSlip(summary, 1)
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

function Begleiter.slash(cmd, rest)
  local print_ = ns.Core and ns.Core.print or function() end
  local T = Begleiter.TEXT
  if cmd == "willkommen" then
    if not ns.Welcome or type(ns.Welcome.summary) ~= "function" then
      print_(T.welcomeNotReady)
      return true
    end
    -- the big welcome card no longer exists: the preview always shows the note ("zettel" / "note" stay as an optional word)
    Begleiter.showSlip(ns.Welcome.summary(), 1, true)
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
