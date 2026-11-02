-- Settings menu under Options -> AddOns -> Ink & Embers (native Settings API). Every row is a proxy setting
-- (Settings.RegisterProxySetting) that reads and writes through the same functions as the book-page checkboxes,
-- /chronik commands and edit mode. Options.refresh() pushes outside changes to the open menu (setting:NotifyUpdate()).
-- Does not open in combat. Without the Settings API the addon stays fully usable via /chronik.
local ADDON_NAME, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Options = {}
Journal.Options = Options

Options.NAME = "Ink & Embers"
Options.PREFIX = "EveNChronicle_"
Options.settings = {}
Options.order = {}

-- Texts (Options locale area) are functions, read when the menu is built, never at load.
local TX = ns.Locale.ns("Options", {
  combat = "Die Einstellungen öffnen sich nicht im Kampf. Bitte nach dem Kampf noch einmal.",
  unavailable = "Das Einstellungsmenü ist in diesem Client nicht verfügbar. /chronik hilfe zeigt die Befehle.",
  failed = "Das Einstellungsmenü ließ sich nicht öffnen. Optionen -> AddOns -> Ink & Embers.",
  preview = "Probehören",
  perChar = "Gilt für diesen Charakter.",
  gBook = "Buch",
  gJourney = "Reise und Karte",
  gTodo = "To Do und Mini-Zettel",
  gQuick = "Schnellnotizen",
  gToasts = "Einblendungen",
  gMedals = "Medaillen",
  gMarks = "Markierung der To-Do-Gegner",
  gFire = "Lagerfeuer",
  gSounds = "Klänge",
  gMisc = "Sonstiges",
  scaleLabel = "Größe des Buchs",
  scaleTip = "Größe des Reisejournals in Prozent.",
  reduceLabel = "Bewegung reduzieren",
  reduceTip = "Keine Aufschlag-Animation und ruhigere Karten-Wiedergabe.",
  minimapLabel = "Minimap-Knopf zeigen",
  minimapTip = "Knopf am Rand der Minikarte: Linksklick öffnet das Buch, Rechtsklick diese Einstellungen.",
  soundsLabel = "Buchgeräusche",
  soundsTip = "Klänge beim Öffnen, Blättern und Schließen des Buchs, bei Begrüßung, Rückblick und erledigten To Dos.",
  resetBookLabel = "Lage und Größe des Buchs",
  resetButton = "Zurücksetzen",
  resetBookTip = "Setzt Größe und Position des Buchs auf den Standard (wie /chronik reset).",
  tutorialLabel = "Einführung",
  tutorialButton = "Ansehen",
  tutorialTip = "Zeigt die kleine Einführung zum Durchblättern noch einmal (wie /chronik tutorial).",
  mapColorLabel = "Kartenfarben",
  mapColorTip = "Gilt für alle Karten im Buch.",
  mapSepia = "Pergament (Sepia)",
  mapOriginal = "Originalfarben",
  killsLabel = "Kämpfe auf der Karte zeigen",
  killsTip = "Schwerter für Kämpfe auf der Zonenkarte (derselbe Haken wie unter der Karte).",
  speedLabel = "Tempo der Wiedergabe",
  speedTip = "Wie schnell die Reise auf der Karte abgespielt wird.",
  speedSlow = "Langsam",
  speedMid = "Mittel",
  speedFast = "Schnell",
  worldMapLabel = "Reise auf der Weltkarte zeigen",
  worldMapTip = "Route und Marken der Reise auch auf der Weltkarte des Spiels.",
  fbShown = "Mini-To-Do-Zettel",
  fbStyle = "Notizzettel-Stil",
  fbLocked = "Notizzettel sperren",
  fbCombat = "Im Kampf ausblenden",
  fbEmpty = "Ausblenden, wenn nichts offen ist",
  fbPad = "Notizblock",
  fbPlain = "Schlicht",
  todoShownTip = "Kleiner Notizzettel mit den offenen To Dos am Bildschirmrand.",
  todoStyleTip = "Aussehen des Mini-Zettels.",
  fbOpen = "Öffnen",
  fbOpenModes = { always = "Immer offen", hover = "Beim Überfahren", click = "Per Klick",
    auto = "Automatisch, sobald To Dos drauf stehen" },
  todoOpenTip = "Wann der Mini-Zettel ganz aufgeklappt ist. Eingeklappt bleibt nur der Kopf mit der Zahl offener To Dos stehen.",
  fbGrow = "Aufklappen nach",
  fbGrowNames = { down = "Unten", up = "Oben" },
  todoGrowTip = "Unten: der Zettel rollt unter dem Kopf auf. Oben: der Kopf bleibt an seiner Stelle, der Zettel rollt über ihm auf.",
  quickStyleLabel = "Stil der Schnellnotiz",
  quickStyleTip = "Aussehen der Schnellnotiz.",
  todoLockedTip = "Mini-Zettel lässt sich nicht verschieben oder in der Größe ändern.",
  todoCombatTip = "Mini-Zettel verschwindet während eines Kampfs.",
  todoEmptyTip = "Mini-Zettel nur zeigen, wenn ein To Do offen ist.",
  trainerTodoLabel = "Zum Lehrer automatisch eintragen",
  trainerTodoTip = "Nach einem Stufenaufstieg mit neuen Zaubern steht „Zum Lehrer“ als To Do auf der Liste; es hakt sich selbst ab, sobald alles gelernt ist (nur WoW Forever).",
  talentHintLabel = "Freie Talentpunkte melden",
  talentHintTip = "Kleine Einblendung, wenn Talentpunkte frei sind – einmal pro Stufe bzw. Sitzung, nie im Kampf (nur WoW Forever).",
  todoResetLabel = "Lage des Mini-Zettels",
  todoResetTip = "Position und Größe des Mini-Zettels auf den Standard (wie /chronik todo reset).",
  quickLabel = "Schnellnotizen zeigen",
  quickTip = "Kleines Feld am Bildschirmrand: schreiben, Enter, schon liegt die Notiz im Notizbuch.",
  toastLabel = "Einblendungen zeigen",
  toastTip = "Kleine Pergament-Einblendungen oben am Bildschirm (wie /chronik toast).",
  toastZoneLabel = "Neue Gebiete melden",
  toastZoneTip = "Einblendung beim ersten Betreten eines Gebiets.",
  toastSoundLabel = "Ton der Einblendungen",
  toastSoundTip = "Klang zu jeder Einblendung (wie /chronik ton). Welcher Klang, steht unter Klänge.",
  welcomeLabel = "Begrüßung beim Einloggen",
  welcomeTip = "Kurze Karte mit dem Stand der Reise beim Einloggen.",
  narratorLabel = "Erzähler auf der Willkommen-Karte",
  narratorTip = "Wer Euch auf der Begrüßungskarte empfängt: jemand Eures Volks, bei jeder Karte ein anderer oder immer derselbe.",
  narratorOwn = "Eigenes Volk",
  narratorRandom = "Zufällig",
  narratorNames = { human = "Mensch", dwarf = "Zwerg", nightelf = "Nachtelf", gnome = "Gnom", orc = "Orc", undead = "Untoter",
    tauren = "Tauren", troll = "Troll", skyborne = "Skyborne" },
  restLabel = "Rückblick bei der Rast",
  restTip = "Rückblick auf die letzte Etappe, wenn Ihr am Lagerfeuer oder im Gasthaus rastet.",
  medalLabel = "Neue Medaillen melden",
  medalTip = "Einblendung, sobald eine Medaillen-Stufe verdient ist. Die Medaillen stehen in der Chronik.",
  marksLabel = "To-Do-Gegner markieren",
  marksTip = "Zeile „To Do“ im Tooltip und Symbol an der Namensplakette von Gegnern, die ein offenes To Do braucht.",
  markSideLabel = "Lage des Symbols",
  markSideTip = "Wo das Symbol an der Namensplakette sitzt. Trägt dort schon ein anderes Addon (z. B. Questie) ein Symbol, rückt unseres automatisch nach außen oder auf die freie Seite.",
  markSideLeft = "Links",
  markSideRight = "Rechts",
  markSideTop = "Oben",
  fireNotesLabel = "Gesprächszettel am Lagerfeuer",
  fireNotesTip = "Sitzt Ihr am Lagerfeuer, schweben drei Zettel mit Gesprächsvorschlägen über dem Feuer. Linksklick sagt den Satz in /sagen, Rechtsklick verwirft ihn.",
  fireShowLabel = "Am Feuer zeigen",
  fireShowTip = "Rast-Karte und Zettel: erst die Karte, dann die Zettel (Standard) – beides zugleich – oder nur die Zettel (keine Rast-Karte am Lagerfeuer).",
  fireShowCard = "Karte, dann Zettel",
  fireShowBoth = "Beides",
  fireShowNotes = "Nur Zettel",
  fireAddressLabel = "Anrede in den Sätzen",
  fireAddressTip = "Wie die Vorschläge andere ansprechen: du, Ihr oder gemischt (je Zettel zufällig).",
  fireDu = "du",
  fireIhr = "Ihr",
  fireMix = "Gemischt",
  firePlatesLabel = "Plaketten beim Hinsetzen einschalten",
  firePlatesTip = "Schaltet beim Hinsetzen die Namensplaketten freundlicher Spieler ein, damit die Chronik erkennt, wer mit am Feuer sitzt; beim Aufstehen kommt die alte Einstellung zurück.",
  meterLabel = "Schadensanzeige automatisch einschalten",
  meterTip = "Schaltet die Schadensanzeige des Spiels ein, damit Kämpfe Schaden und Heilung festhalten (wie /chronik messer).",
  diagLabel = "Diagnose",
  diagButton = "In den Chat",
  diagTip = "Schreibt den Zustand des Addons in den Chat (wie /chronik diag).",
  soundTip = "Klang für „%s“. Beim Auswählen erklingt er zur Probe; „Aus“ macht das Ereignis still.",
  previewTip = "Spielt den gewählten Klang für „%s“ einmal ab.",
})
Options.TEXT = TX

local function tx(key) return function() return TX[key] end end
local function txp(key) return function() return TX[key] .. " " .. TX.perChar end end

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function say(msg)
  local Core = ns.Core
  if Core and type(Core.print) == "function" then Core.print(msg) elseif type(print) == "function" then print(msg) end
end

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, res = pcall(fn, ...)
  if ok then return res end
  return nil
end

local function F() return Journal.Frame end
local function V() return Journal.View end
local function TT() return Journal.TodoTracker end
local function QN() return Journal.QuickNote end
local function Toast() return Journal.Toast end
local function Sound() return Journal.Sound end

local function ttSetting(key)
  local T = TT()
  local s = T and call(T.settings)
  if type(s) ~= "table" then return nil end
  return s[key]
end

local function peek(key)
  local View = V()
  return View and call(View.peek, key)
end

local function bool(v) return v and true or false end

local function scaleGet()
  local Fr = F()
  local s = Fr and call(Fr.currentScale) or 1
  if type(s) ~= "number" or s ~= s then s = 1 end
  local pct = math.floor(s * 100 + 0.5)
  return math.max(50, math.min(200, pct))
end

local function scaleSet(pct)
  local Fr = F()
  if Fr and type(pct) == "number" then call(Fr.setScale, pct / 100) end
end

local function speedSet(v)
  local Fr = F()
  if Fr and Fr.state and Fr.state.st then
    call(Fr.setSpeed, v)
  else
    local View = V()
    if View then call(View.set, "speed", v) end
  end
end

local function speedOptions()
  local P = Journal.Playback
  local names = (P and P.SPEED_NAMES) or { [20] = TX.speedSlow, [60] = TX.speedMid, [180] = TX.speedFast }
  return { { value = 20, label = names[20] }, { value = 60, label = names[60] }, { value = 180, label = names[180] } }
end

local function ttText(key, fallback)
  local T = TT()
  local t = T and T.TEXT and T.TEXT[key]
  return type(t) == "string" and t or fallback
end

local function LT() return ns.Locale.T end

local function reload()
  local Save = ns.Save
  if Save and type(Save.show) == "function" then call(Save.show) end
end

-- Parts that only make sense in WoW Forever are hidden in Retail (items and groups with hidden = function; read on registering).
-- foreverOnly: trainer plan (Lehrplan) items; fireHidden: the campfire talk never starts in Retail (MapSpace.fireTalkHidden).
local function foreverOnly()
  local L = Journal.Lehrplan
  return L ~= nil and type(L.active) == "function" and L.active() == false
end

local function fireHidden()
  local ms = Journal.MapSpace
  return ms ~= nil and type(ms.fireTalkHidden) == "function" and ms.fireTalkHidden() == true
end

function Options.isHidden(entry)
  if type(entry.hidden) ~= "function" then return false end
  local ok, v = pcall(entry.hidden)
  return ok and v == true
end

Options.GROUPS = {
  {
    title = "Sprache / Language",
    items = {
      { kind = "dropdown", key = "locale", label = function() return LT().name end, default = "auto", varType = "string",
        tip = function() return LT().tip end,
        options = function()
          local Lc = ns.Locale
          local list = {}
          for i, s in ipairs(Lc.SETTINGS) do list[i] = { value = s, label = Lc.label(s) } end
          return list
        end,
        get = function() return ns.Locale.setting end,
        set = function(v)
          local Lc = ns.Locale
          local ok, changed = Lc.set(v)
          if ok and changed then say(LT()("changed", Lc.label(v))) end
        end },
      { kind = "button", key = "localeReload", label = function() return LT().reloadLabel end,
        button = function() return LT().reloadButton end, tip = function() return LT().reloadTip end,
        click = reload },
    },
  },
  {
    title = tx("gBook"),
    items = {
      { kind = "slider", key = "scale", label = tx("scaleLabel"), tip = tx("scaleTip"),
        min = 50, max = 200, step = 5, default = 75, get = scaleGet, set = scaleSet },
      { kind = "check", key = "reduceMotion", label = tx("reduceLabel"), default = false,
        tip = tx("reduceTip"),
        get = function() return bool(peek("reduceMotion")) end,
        set = function(v)
          local View, Fr = V(), F()
          if View then call(View.set, "reduceMotion", v) end
          if Fr then call(Fr.refresh) end
        end },
      { kind = "check", key = "minimap", label = tx("minimapLabel"), default = true,
        tip = tx("minimapTip"),
        get = function() return peek("minimap") ~= false end,
        set = function(v) local A = Journal.Access if A then call(A.setMinimap, v) end end },
      { kind = "check", key = "bookSounds", label = tx("soundsLabel"), default = true,
        tip = tx("soundsTip"),
        get = function() local S = Sound() return not S or S.enabled() end,
        set = function(v) local S = Sound() if S then S.setEnabled(v) end end },
      { kind = "button", key = "resetBook", label = tx("resetBookLabel"), button = tx("resetButton"),
        tip = tx("resetBookTip"),
        click = function() local A = Journal.Access if A then call(A.reset) end end },
      { kind = "button", key = "tutorial", label = tx("tutorialLabel"), button = tx("tutorialButton"),
        tip = tx("tutorialTip"),
        click = function() local Tu = Journal.Tutorial if Tu then call(Tu.open, 1) end end },
    },
  },
  {
    title = tx("gJourney"),
    items = {
      { kind = "dropdown", key = "mapColor", label = tx("mapColorLabel"), default = "sepia", varType = "string",
        tip = tx("mapColorTip"),
        options = function() return { { value = "sepia", label = TX.mapSepia }, { value = "original", label = TX.mapOriginal } } end,
        get = function() return peek("mapColor") == "original" and "original" or "sepia" end,
        set = function(v) local Fr = F() if Fr then call(Fr.setMapColor, v) end end },
      { kind = "check", key = "showKills", label = tx("killsLabel"), default = true,
        tip = tx("killsTip"),
        get = function() return peek("showKills") ~= false end,
        set = function(v) local Fr = F() if Fr then call(Fr.setShowKills, v) end end },
      { kind = "dropdown", key = "speed", label = tx("speedLabel"), default = 60, varType = "number",
        tip = tx("speedTip"),
        options = speedOptions,
        get = function() local v = peek("speed") return (v == 20 or v == 60 or v == 180) and v or 60 end,
        set = speedSet },
      { kind = "check", key = "worldMap", label = tx("worldMapLabel"), default = true,
        tip = tx("worldMapTip"),
        get = function() local WL = Journal.WorldLayer return not WL or WL.enabled() end,
        set = function(v) local WL = Journal.WorldLayer if WL then call(WL.setEnabled, v) end end },
    },
  },
  {
    title = tx("gTodo"),
    items = {
      { kind = "check", key = "todoShown", label = function() return ttText("optShown", TX.fbShown) end, default = false,
        tip = txp("todoShownTip"),
        get = function() return ttSetting("shown") == true end,
        set = function(v) local T = TT() if T then call(T.setShown, v) end end },
      { kind = "dropdown", key = "todoStyle", label = function() return ttText("styleLabel", TX.fbStyle) end, default = "pad", varType = "string",
        tip = txp("todoStyleTip"),
        options = function()
          local T = TT()
          local names = (T and T.TEXT and T.TEXT.style) or { pad = TX.fbPad, plain = TX.fbPlain }
          return { { value = "pad", label = names.pad }, { value = "plain", label = names.plain } }
        end,
        get = function() return ttSetting("style") == "plain" and "plain" or "pad" end,
        set = function(v) local T = TT() if T then call(T.setStyle, v) end end },
      { kind = "dropdown", key = "todoOpen", label = function() return ttText("openLabel", TX.fbOpen) end, default = "always", varType = "string",
        tip = txp("todoOpenTip"),
        options = function()
          local T = TT()
          local names = (T and T.TEXT and T.TEXT.openModes) or TX.fbOpenModes
          local list = {}
          for i, m in ipairs((T and T.OPEN_MODES) or { "always", "hover", "click", "auto" }) do list[i] = { value = m, label = names[m] } end
          return list
        end,
        get = function() local v = ttSetting("open") return type(v) == "string" and v or "always" end,
        set = function(v) local T = TT() if T and T.setOpen then call(T.setOpen, v) end end },
      { kind = "dropdown", key = "todoGrow", label = function() return ttText("growLabel", TX.fbGrow) end, default = "down", varType = "string",
        tip = txp("todoGrowTip"),
        options = function()
          local T = TT()
          local names = (T and T.TEXT and T.TEXT.grow) or TX.fbGrowNames
          return { { value = "down", label = names.down }, { value = "up", label = names.up } }
        end,
        get = function() local v = ttSetting("grow") return v == "up" and "up" or "down" end,
        set = function(v) local T = TT() if T and T.setGrow then call(T.setGrow, v) end end },
      { kind = "check", key = "todoLocked", label = function() return ttText("optLocked", TX.fbLocked) end, default = false,
        tip = txp("todoLockedTip"),
        get = function() return ttSetting("locked") == true end,
        set = function(v) local T = TT() if T then call(T.setLocked, v) end end },
      { kind = "check", key = "todoCombat", label = function() return ttText("optCombat", TX.fbCombat) end, default = false,
        tip = txp("todoCombatTip"),
        get = function() return ttSetting("combatHide") == true end,
        set = function(v) local T = TT() if T then call(T.setCombatHide, v) end end },
      { kind = "check", key = "todoEmpty", label = function() return ttText("optEmpty", TX.fbEmpty) end, default = true,
        tip = txp("todoEmptyTip"),
        get = function() return ttSetting("hideEmpty") == true end,
        set = function(v) local T = TT() if T then call(T.setHideEmpty, v) end end },
      { kind = "check", key = "trainerTodo", hidden = foreverOnly, label = tx("trainerTodoLabel"), default = true,
        tip = tx("trainerTodoTip"),
        get = function() local P = Journal.Pages return not P or P.setting("trainerTodo") ~= false end,
        set = function(v) local P = Journal.Pages if P then P.setSetting("trainerTodo", bool(v)) end end },
      { kind = "button", key = "todoReset", label = tx("todoResetLabel"), button = tx("resetButton"),
        tip = tx("todoResetTip"),
        click = function() local T = TT() if T then call(T.reset) end end },
    },
  },
  {
    title = tx("gQuick"),
    items = {
      { kind = "check", key = "quickShown", label = tx("quickLabel"), default = false,
        tip = txp("quickTip"),
        get = function() local Q = QN() local s = Q and call(Q.settings) return type(s) == "table" and s.shown == true end,
        set = function(v) local Q = QN() if Q then call(Q.setShown, v) end end },
      { kind = "dropdown", key = "quickStyle", label = tx("quickStyleLabel"), default = "pad", varType = "string",
        tip = txp("quickStyleTip"),
        options = function()
          local T = TT()
          local names = (T and T.TEXT and T.TEXT.style) or { pad = TX.fbPad, plain = TX.fbPlain }
          return { { value = "pad", label = names.pad }, { value = "plain", label = names.plain } }
        end,
        get = function() local Q = QN() local s = Q and call(Q.settings) return type(s) == "table" and s.style == "plain" and "plain" or "pad" end,
        set = function(v) local Q = QN() if Q then call(Q.setStyle, v) end end },
    },
  },
  {
    title = tx("gToasts"),
    items = {
      { kind = "check", key = "toast", label = tx("toastLabel"), default = true,
        tip = tx("toastTip"),
        get = function() local T = Toast() return not T or T.enabled() end,
        set = function(v) local T = Toast() if T then call(T.setEnabled, v) end end },
      { kind = "check", key = "toastZone", label = tx("toastZoneLabel"), default = true,
        tip = tx("toastZoneTip"),
        get = function() local T = Toast() return not T or T.kindOn("zone") end,
        set = function(v) local T = Toast() if T then call(T.setKind, "zone", v) end end },
      { kind = "check", key = "toastSound", label = tx("toastSoundLabel"), default = true,
        tip = tx("toastSoundTip"),
        get = function() local T = Toast() return not T or T.soundOn() end,
        set = function(v) local T = Toast() if T then call(T.setSound, v) end end },
      { kind = "check", key = "talentHint", hidden = foreverOnly, label = tx("talentHintLabel"), default = true,
        tip = tx("talentHintTip"),
        get = function() local P = Journal.Pages return not P or P.setting("talentHint") ~= false end,
        set = function(v) local P = Journal.Pages if P then P.setSetting("talentHint", bool(v)) end end },
      { kind = "check", key = "welcome", label = tx("welcomeLabel"), default = true,
        tip = tx("welcomeTip"),
        get = function() local B = Journal.Begleiter return not B or B.welcomeOn() end,
        set = function(v) local B = Journal.Begleiter if B then call(B.setWelcome, v) end end },
      { kind = "dropdown", key = "narrator", label = tx("narratorLabel"), default = "own", varType = "string",
        tip = tx("narratorTip"),
        options = function()
          local list = { { value = "own", label = TX.narratorOwn }, { value = "random", label = TX.narratorRandom } }
          local names = TX.narratorNames or {}
          for _, id in ipairs((Journal.Theme and Journal.Theme.NARRATORS) or {}) do
            list[#list + 1] = { value = id, label = names[id] or id }
          end
          return list
        end,
        get = function() local B = Journal.Begleiter return B and B.narratorChoice() or "own" end,
        set = function(v) local B = Journal.Begleiter if B then call(B.setNarrator, v) end end },
      { kind = "check", key = "restReview", label = tx("restLabel"), default = true,
        tip = tx("restTip"),
        get = function() local B = Journal.Begleiter return not B or B.restOn() end,
        set = function(v) local B = Journal.Begleiter if B then call(B.setRest, v) end end },
    },
  },
  {
    title = tx("gMedals"),
    items = {
      { kind = "check", key = "toastMedal", label = tx("medalLabel"), default = true,
        tip = tx("medalTip"),
        get = function() local T = Toast() return not T or T.kindOn("medal") end,
        set = function(v) local T = Toast() if T then call(T.setKind, "medal", v) end end },
    },
  },
  {
    title = tx("gMarks"),
    items = {
      { kind = "check", key = "todoMarks", label = tx("marksLabel"), default = true,
        tip = txp("marksTip"),
        get = function() return ttSetting("marks") ~= false end,
        set = function(v) local TM = Journal.TodoMarks if TM then call(TM.setEnabled, v) end end },
      { kind = "dropdown", key = "todoMarkSide", label = tx("markSideLabel"), default = "left", varType = "string",
        tip = txp("markSideTip"),
        options = function()
          return { { value = "left", label = TX.markSideLeft }, { value = "right", label = TX.markSideRight },
            { value = "top", label = TX.markSideTop } }
        end,
        get = function() local TM = Journal.TodoMarks return TM and TM.side() or "left" end,
        set = function(v) local TM = Journal.TodoMarks if TM then call(TM.setSide, v) end end },
    },
  },
  {
    title = tx("gFire"), hidden = fireHidden,
    items = {
      { kind = "check", key = "fireNotes", label = tx("fireNotesLabel"), default = true,
        tip = tx("fireNotesTip"),
        get = function() local F = Journal.FireNotes return not F or F.settings().notes end,
        set = function(v) local F = Journal.FireNotes if F then call(F.setEnabled, v) end end },
      { kind = "dropdown", key = "fireShow", label = tx("fireShowLabel"), default = "cardFirst", varType = "string",
        tip = tx("fireShowTip"),
        options = function()
          return { { value = "cardFirst", label = TX.fireShowCard }, { value = "both", label = TX.fireShowBoth },
            { value = "notesOnly", label = TX.fireShowNotes } }
        end,
        get = function() local F = Journal.FireNotes return F and F.settings().show or "cardFirst" end,
        set = function(v) local F = Journal.FireNotes if F then call(F.setShow, v) end end },
      { kind = "dropdown", key = "fireAddress", label = tx("fireAddressLabel"), default = "du", varType = "string",
        tip = tx("fireAddressTip"),
        options = function()
          return { { value = "du", label = TX.fireDu }, { value = "ihr", label = TX.fireIhr }, { value = "mix", label = TX.fireMix } }
        end,
        get = function() local CT = Journal.CampfireTalk return CT and CT.settings().address or "du" end,
        set = function(v) local CT = Journal.CampfireTalk if CT then call(CT.setAddress, v) end end },
      { kind = "check", key = "firePlates", label = tx("firePlatesLabel"), default = true,
        tip = tx("firePlatesTip"),
        get = function() local C = ns.Campfire return not C or C.settings().showFriendPlates ~= false end,
        set = function(v) local C = ns.Campfire if C then call(C.set, "showFriendPlates", v and true or false) end end },
    },
  },
  { title = tx("gSounds"), sounds = true, items = {} },
  {
    title = tx("gMisc"),
    items = {
      { kind = "check", key = "meterAuto", label = tx("meterLabel"), default = true,
        tip = tx("meterTip"),
        get = function() return type(ns.meterAutoOn) ~= "function" or ns.meterAutoOn() end,
        set = function(v) if type(ns.meterSlash) == "function" then call(ns.meterSlash, v and "an" or "aus") end end },
      { kind = "button", key = "diag", label = tx("diagLabel"), button = tx("diagButton"),
        tip = tx("diagTip"),
        click = function() local Core = ns.Core if Core then call(Core.runDiag) end end },
    },
  },
}

do
  local S = Sound()
  for _, g in ipairs(Options.GROUPS) do
    if g.sounds and S then
      for _, e in ipairs(S.EVENTS) do
        g.items[#g.items + 1] = { kind = "sound", key = "sound_" .. e.key, event = e.key, default = "default",
          varType = "string",
          label = function() return S.eventLabel(e) end,
          tip = function() return TX("soundTip", S.eventLabel(e)) end,
          get = function() return S.choice(e.key) end,
          set = function(v) if S.setChoice(e.key, v) then S.preview(e.key, v) end end }
      end
    end
  end
end

local applying = false

local function varType(kind, item)
  local VT = type(Settings) == "table" and Settings.VarType or nil
  local t = item.varType or (kind == "check" and "boolean") or (kind == "slider" and "number") or "string"
  if VT then
    if t == "boolean" then return VT.Boolean or t end
    if t == "number" then return VT.Number or t end
    return VT.String or t
  end
  return t
end

local function txt(v)
  if type(v) == "function" then
    local ok, s = pcall(v)
    return ok and s or ""
  end
  return v
end

local function textContainer(list)
  local c = Settings.CreateControlTextContainer()
  for _, o in ipairs(list) do c:Add(o.value, o.label) end
  return c:GetData()
end

local function soundMenu(item, setting)
  return function(root)
    local S, K, San = Sound(), Journal.SoundKits, ns.Sanitize
    if not S or type(root) ~= "table" or type(root.CreateButton) ~= "function" then return end
    local function radio(desc, text, key)
      desc:CreateRadio(text, function() return S.choice(item.event) == key end, function() setting:SetValue(key) end, key)
    end
    if K then
      local game = root:CreateButton(S.TEXT.game)
      for _, g in ipairs(K.GROUPS) do
        local sub = game:CreateButton(K.groupLabel(g))
        for _, e in ipairs(K.LIST) do
          if e.g == g.key then radio(sub, K.nameOf(e), "kit:" .. e.id) end
        end
      end
    end
    local own = root:CreateButton(S.TEXT.own)
    for _, f in ipairs(S.FILES) do radio(own, S.fileName(f), "file:" .. f.file) end
    local lsm = root:CreateButton(S.TEXT.lsm)
    local names = S.lsmNames()
    if #names == 0 then
      if type(lsm.CreateTitle) == "function" then lsm:CreateTitle(S.TEXT.lsmEmpty) end
    else
      if type(lsm.SetScrollMode) == "function" then lsm:SetScrollMode(480) end
      for _, n in ipairs(names) do radio(lsm, (San and San.display(n, 60)) or "?", "lsm:" .. n) end
    end
  end
end

local function register(category, layout, item)
  local var = Options.PREFIX .. item.key
  if item.kind == "button" then
    if type(CreateSettingsButtonInitializer) ~= "function" then return end
    local init = CreateSettingsButtonInitializer(txt(item.label), txt(item.button), function() item.click() end, txt(item.tip), true)
    layout:AddInitializer(init)
    return
  end
  local get, set = item.get, item.set
  local label, tip = txt(item.label), txt(item.tip)
  local setting = Settings.RegisterProxySetting(category, var, varType(item.kind, item), label, item.default,
    function()
      local ok, v = pcall(get)
      if not ok or v == nil or isSecret(v) then return item.default end
      return v
    end,
    function(v)
      applying = true
      pcall(set, v)
      applying = false
    end)
  Options.settings[item.key] = setting
  Options.order[#Options.order + 1] = item.key
  if item.kind == "check" then
    Settings.CreateCheckbox(category, setting, tip)
  elseif item.kind == "slider" then
    local opts = Settings.CreateSliderOptions(item.min, item.max, item.step)
    local M = rawget(_G, "MinimalSliderWithSteppersMixin")
    if type(opts.SetLabelFormatter) == "function" and type(M) == "table" and type(M.Label) == "table" and M.Label.Right then
      opts:SetLabelFormatter(M.Label.Right, function(v) return string.format("%d %%", math.floor((tonumber(v) or 0) + 0.5)) end)
    end
    Settings.CreateSlider(category, setting, opts, tip)
  elseif item.kind == "dropdown" then
    Settings.CreateDropdown(category, setting, function() return textContainer(item.options()) end, tip)
  elseif item.kind == "sound" then
    local S = Sound()
    local init = Settings.CreateDropdown(category, setting, function()
      return textContainer({ { value = "default", label = S.TEXT.default }, { value = "off", label = S.TEXT.off } })
    end, tip)
    if type(init) == "table" then
      init.customOptionHandler = soundMenu(item, setting)
      init.getSelectionTextFunc = function() return S.label(S.choice(item.event)) end
    end
    if type(CreateSettingsButtonInitializer) == "function" then
      local btn = CreateSettingsButtonInitializer(label, Options.TEXT.preview, function() S.preview(item.event) end,
        TX("previewTip", label), false)
      layout:AddInitializer(btn)
    end
  end
end

function Options.register()
  if Options.category then return true end
  if type(Settings) ~= "table" or type(Settings.RegisterVerticalLayoutCategory) ~= "function"
    or type(Settings.RegisterProxySetting) ~= "function" then
    return false
  end
  local function fail(err)
    Options.lastError = tostring(err)
    local Core = ns.Core
    if Core and type(Core.coreError) == "function" then pcall(Core.coreError, err) end
  end
  local ok, category, layout = pcall(Settings.RegisterVerticalLayoutCategory, Options.NAME)
  if not ok or type(category) ~= "table" or type(layout) ~= "table" then
    fail(category)
    return false
  end
  Options.category = category
  for _, g in ipairs(Options.GROUPS) do
    if not Options.isHidden(g) then
      if type(CreateSettingsListSectionHeaderInitializer) == "function" then
        local okH, err = pcall(function() layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(txt(g.title))) end)
        if not okH then fail(err) end
      end
      for _, item in ipairs(g.items) do
        if not Options.isHidden(item) then
          local okI, err = pcall(register, category, layout, item)
          if not okI then fail(err) end
        end
      end
    end
  end
  local okR, err = pcall(Settings.RegisterAddOnCategory, category)
  if not okR then fail(err) end
  Options.categoryID = type(category.GetID) == "function" and category:GetID() or category.ID
  return true
end

function Options.open()
  if inCombat() then
    say(Options.TEXT.combat)
    return false
  end
  if not Options.register() then
    say(Options.TEXT.unavailable)
    return false
  end
  if type(Settings.OpenToCategory) ~= "function" or Options.categoryID == nil then
    say(Options.TEXT.unavailable)
    return false
  end
  local ok = pcall(Settings.OpenToCategory, Options.categoryID)
  if not ok then say(Options.TEXT.failed) end
  return ok
end

function Options.refresh()
  if applying or not Options.category then return end
  local panel = rawget(_G, "SettingsPanel")
  if type(panel) == "table" and type(panel.IsShown) == "function" and not panel:IsShown() then return end
  for _, key in ipairs(Options.order) do
    local s = Options.settings[key]
    if type(s) == "table" and type(s.NotifyUpdate) == "function" then pcall(s.NotifyUpdate, s) end
  end
end

do
  local T, Q = TT(), QN()
  if T and type(T.listeners) == "table" then T.listeners[#T.listeners + 1] = function() Options.refresh() end end
  if Q and type(Q.listeners) == "table" then Q.listeners[#Q.listeners + 1] = function() Options.refresh() end end
  local C = ns.Campfire
  if C and type(C.onSettingsChanged) == "function" then C.onSettingsChanged(function() Options.refresh() end) end
  local S = Sound()
  if S and type(S.onMedia) == "function" then
    S.onMedia(function() Options.refresh() end)
    S.lsm()
  end
end

-- Register on ADDON_LOADED, after Locale.apply: the chosen language is only known once the SavedVariables are loaded.
do
  local Core = ns.Core
  local hooked = Core and type(Core.on) == "function"
    and Core.on("ADDON_LOADED", function(_, name) if name == ADDON_NAME then Options.register() end end)
  if not hooked then Options.register() end
end
