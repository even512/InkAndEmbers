-- Collector 'Trainer' (WoW Forever only; on retail it stays idle): class trainer, Lehrplan and talent points.
-- 1. Silent visit collector: on TRAINER_SHOW/TRAINER_UPDATE (batched) the services of a CLASS trainer are read (a hunter pet
--    trainer window - Beast Training - is never taken for one, see isPetWindow) (name, rank text,
--    type, level, cost) into snapshots.trainerSpells["<name> #<rank>"] and the trainer's place (player position at the visit) into
--    snapshots.trainers[npcID] (read by Journal.Lehrplan: nearest trainer). The service names offered as "available" go to
--    snapshots.state.trainerVisit (level, names): the Lehrplan then knows which entries this trainer really offered.
-- 2. To-do "Zum Lehrer": after a level-up (and at login, once per level: marker snapshots.state.trainerTodo) with spells learnable
--    now, one free to-do (Plans.upsertAuto "trainer"); it is updated or completed (Plans.finishAuto) as soon as nothing learnable
--    is left (spell learned, trainer closed). Login never adds a second one while an automatic or a Lehrplan place to-do is open.
--    Setting trainerTodo.
-- 3. Talent points: free points (Journal.Lehrplan.unspentTalents) -> one toast per level and session, never in combat (the
--    toast queue waits). Setting talentHint.
-- 3b. Announcement of the automatic to-do: a newly created "Zum Lehrer" to-do (not an update) queues one toast "Neues To Do /
--    Zum Lehrer / 2 neue Zauber" (Toast kind "todo", setting todoToast). At a level-up it waits until the narrator note has left
--    (Begleiter.slipKind/afterSlip), never in combat. To-dos the player adds by hand never get a toast.
-- 4. Level-up note: after PLAYER_LEVEL_UP the narrator note (journal/Begleiter.lua, showNote) glides in from the left and speaks in
--    flowing text (6 random variants per case): congratulation with the player name, what is learnable (up to 3 spell names),
--    total cost (or what is missing), nearest trainer, free talent points (then no talent toast at the level-up). Nothing
--    learnable: the note still comes (next level with new spells). Click: opens the book at Pläne -> Lehrplan and closes the note
--    (in combat: chat hint, note stays); the small x only closes. In combat it waits for PLAYER_REGEN_ENABLED, an open
--    welcome note first. Setting levelSlip (default on); /chronik stufe shows it as a preview.
-- Only reading APIs, each in pcall with secret-value guards; nothing is bought or clicked.
local _, ns = ...
local Core, Store = ns.Core, ns.Store

local floor, min = math.floor, math.min

local Trainer = {}
ns.Trainer = Trainer

Trainer.READ_DELAY = 0.3      -- seconds after TRAINER_SHOW (the list fills right after the event)
Trainer.UPDATE_DELAY = 0.5    -- TRAINER_UPDATE comes often: batched
Trainer.CHECK_DELAY = 1.0     -- learned spell / spells changed / trainer closed -> re-check of the to-do
Trainer.LEVEL_DELAY = 2.0     -- after PLAYER_LEVEL_UP (UnitLevel and the spellbook follow a moment later)
Trainer.LOGIN_DELAY = 8.0     -- after login: re-check of the to-do and the talent notice (once per session)
Trainer.MAX_SERVICES = 300    -- services read per visit
Trainer.MAX_TRAINERS = 200    -- snapshots.trainers (soft cap)
Trainer.MAX_SPELLS = 800      -- snapshots.trainerSpells (soft cap)
Trainer.MAX_NAMES = 120       -- names in snapshots.state.trainerVisit
Trainer.TAG = "trainer"       -- Plans.upsertAuto tag
Trainer.SLIP_SPELLS = 3       -- spell names on the level-up note (the rest: "… and n more")
Trainer.SLIP_NAME_MAX = 40    -- characters per spell / zone name on the note
Trainer.SERVICE_TYPES = { available = true, unavailable = true, used = true, header = true }

local T = ns.Locale.ns("col.Trainer", {
  todo_one = "Zum Lehrer: %s neuer Zauber (%s)",
  todo_other = "Zum Lehrer: %s neue Zauber (%s)",
  unitG = "G",
  unitS = "S",
  unitK = "K",
  talentHead = "Talentpunkte",
  talent_one = "%s Punkt wartet auf Euch",
  talent_other = "%s Punkte warten auf Euch",
  talentSub = "Im Talentfenster verteilen",
  todoToastHead = "Neues To Do",
  todoToastTitle = "Zum Lehrer",
  todoToast_one = "%s neuer Zauber",
  todoToast_other = "%s neue Zauber",
  diag = "Lehrplan: %s",
  diagRetail = "aus (Retail: Klassenzauber kommen von selbst)",
  diagOn = "Klasse %s, %s Einträge, jetzt lernbar %s, Lehrer bekannt %s, Besuche %s, freie Talentpunkte %s%s",
  diagNoData = "keine Daten für Klasse %s",
  diagShape = ", Lehrerliste: %s",
  unknown = "?",
  unknownArg = "Unbekannter Zusatz \"%s\". /chronik lehrplan öffnet die Seite, /chronik lehrplan status zeigt den Stand.",
  retailOnly = "Den Lehrplan gibt es nur in WoW Forever (in Retail kommen Klassenzauber von selbst).",
  slipTitle = "Stufe %d erreicht",
  slipHint = "Klick: Lehrplan im Buch öffnen",
  slipOpenFail = "Der Lehrplan lässt sich gerade nicht öffnen. Versucht es gleich noch einmal.",
  slipCombat = "Im Kampf öffnet sich das Buch nicht. Versucht es danach noch einmal.",
  slipNameFallback = "Reisender",
  -- Erzähler-Texte: je Fall 6 Varianten, zufällig gewählt (nie zweimal hintereinander dieselbe). Platzhalter in {geschweiften Klammern}.
  slipGreet = {
    "Meinen Glückwunsch, {name}! Ihr werdet stärker, das sieht man.",
    "Gut gemacht, {name}! Wieder eine Stufe geschafft.",
    "Seht an, {name}, Ihr seid aufgestiegen! Das war verdient.",
    "Bravo, {name}! Die Reise macht Euch stärker.",
    "Glückwunsch, {name}! Ihr wachst mit jeder Meile.",
    "Wohlan, {name}, eine neue Stufe! Die Chronik vermerkt es gern.",
  },
  -- Lernbar: Satzanfang ohne Satzzeichen ({where} = Ort, {count} = Anzahl), der Satz wird per Code großgeschrieben und beendet
  slipLearn_one = {
    "{where} wartet {count} auf Euch",
    "{where} steht {count} für Euch bereit",
    "Ein Besuch {where} lohnt sich – {count} wartet auf Euch",
    "Dank der neuen Stufe wartet {where} {count} auf Euch",
    "Kommt {where} vorbei – {count} wartet bereits auf Euch",
    "{where} gibt es Unterricht – {count} steht auf dem Lehrplan",
  },
  slipLearn_other = {
    "{where} warten {count} auf Euch",
    "{where} stehen {count} für Euch bereit",
    "Ein Besuch {where} lohnt sich – {count} warten auf Euch",
    "Dank der neuen Stufe warten {where} {count} auf Euch",
    "Kommt {where} vorbei – {count} warten bereits auf Euch",
    "{where} gibt es Unterricht – {count} stehen auf dem Lehrplan",
  },
  slipSpell = "%s (%s)",
  slipCountOne = "ein neuer Zauber",
  slipCountOther = "{n} neue Zauber",
  slipWhereBoth = "bei {trainer} in {zone}",
  slipWhereTrainer = "bei {trainer}",
  slipWhereZone = "bei Eurem Lehrer in {zone}",
  slipWhereAny = "bei den Lehrern Eurer Klasse in den Hauptstädten",
  slipWhereShort = "bei Eurem Lehrer",
  slipNames = ": {names}.",
  slipNamesNone = ".",
  slipAnd = " und ",
  slipMoreOne = "und noch ein weiterer",
  slipMoreOther = "und noch {n} weitere",
  slipCost = {
    "Das kostet Euch {cost}.",
    "Rechnet mit {cost} für das Lehrgeld.",
    "Der Unterricht kostet {cost}.",
    "Dafür verlangt der Lehrer {cost}.",
    "Das Lehrgeld beträgt {cost}.",
    "Das Wissen hat seinen Preis: {cost}.",
  },
  slipCostShort = {
    "Das kostet {cost}, doch Euch fehlen noch {short}.",
    "Rechnet mit {cost} Lehrgeld – Euch fehlen leider noch {short}.",
    "Der Unterricht kostet {cost}; Euer Beutel ist um {short} zu leicht.",
    "Dafür verlangt der Lehrer {cost}. Euch fehlen noch {short}.",
    "Das Lehrgeld beträgt {cost}, Euch fehlen dafür noch {short}.",
    "Das Wissen hat seinen Preis: {cost}. Spart noch {short} zusammen.",
  },
  slipNext = {
    "Diesmal hat der Lehrer nichts Neues für Euch. Ab Stufe {next} gibt es wieder Zauber.",
    "Neue Zauber gibt es erst ab Stufe {next}. Bis dahin zieht ruhig weiter!",
    "Beim Lehrer wartet diesmal nichts. Kommt wieder, wenn Ihr Stufe {next} erreicht habt.",
    "Die nächsten Zauber lernt Ihr ab Stufe {next}. Bis dahin reicht, was Ihr schon könnt.",
    "Es gibt nichts Neues zu lernen – erst ab Stufe {next} lohnt sich der Weg zum Lehrer wieder.",
    "Diesmal bleibt der Lehrer ohne Neuigkeiten. Stufe {next} bringt die nächsten Zauber.",
  },
  slipNothing = {
    "Diesmal gibt es beim Lehrer nichts Neues zu lernen.",
    "Neue Zauber stehen diesmal nicht an. Zieht getrost weiter!",
    "Der Lehrer hat diesmal nichts für Euch – das Abenteuer ruft.",
    "Zum Lehrer müsst Ihr diesmal nicht. Es gibt nichts Neues.",
    "Nichts Neues zu lernen. Eure Zauber reichen vorerst.",
    "Diesmal bleibt das Zauberbuch, wie es ist. Weiter geht die Reise!",
  },
  slipTalent_one = {
    "Und vergesst Euren Talentpunkt nicht!",
    "Ein Talentpunkt wartet außerdem darauf, verteilt zu werden.",
    "Übrigens ist noch ein Talentpunkt frei.",
    "Auch Euer Talentpunkt will eingesetzt werden.",
    "Und ein Talentpunkt wartet noch auf Euch.",
    "Denkt außerdem an Euren Talentpunkt!",
  },
  slipTalent_other = {
    "Und vergesst Eure {count} Talentpunkte nicht!",
    "{count} Talentpunkte warten außerdem darauf, verteilt zu werden.",
    "Übrigens sind noch {count} Talentpunkte frei.",
    "Auch Eure {count} Talentpunkte wollen eingesetzt werden.",
    "Und {count} Talentpunkte warten noch auf Euch.",
    "Denkt außerdem an Eure {count} Talentpunkte!",
  },
  -- Zahlwörter ab 2 (bis 12), danach Ziffern
  slipNumWords = "zwei drei vier fünf sechs sieben acht neun zehn elf zwölf",
  slipNoData = "Der Stufenzettel ist gerade nicht verfügbar (Lehrplan: /chronik lehrplan status).",
})
Trainer.TEXT = T

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function str(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

local function callAll(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  table.remove(r, 1)
  return r
end

local function L() return ns.Journal and ns.Journal.Lehrplan end

local function setting(key)
  local P = ns.Journal and ns.Journal.Pages
  if not P or type(P.setting) ~= "function" then return true end
  return P.setting(key) ~= false
end

function Trainer.active()
  local LP = L()
  return LP ~= nil and LP.active()
end

local function moneyText(copper)
  local Tx = ns.Journal and ns.Journal.Texts
  if Tx and type(Tx.money) == "function" then
    -- The to-do text is stored sanitized (no |T/|A coin icons survive), so the units are capital letters: "5 S 10 K"
    local units = { g = T.unitG, s = T.unitS, k = T.unitK }
    return (Tx.money(copper, "plain"):gsub("(%d) ([gsk])%f[%A]", function(d, u) return d .. " " .. units[u] end))
  end
  return tostring(copper)
end

local function playerLevel()
  local r = callAll(UnitLevel, "player")
  local l = r and num(r[1])
  return l and floor(l) or nil
end

-- Services of the open trainer window. Signature in the Mainline TrainerUI: name, serviceType, texture, reqLevel
-- (some builds: name, rank, type, ...). Read robustly: the type is the first value from SERVICE_TYPES, the rank text the first
-- other string after the name, the level the first number 1..100 after the type. shape = types of the first row (diag).
function Trainer.readServices()
  local r = callAll(GetNumTrainerServices)
  local n = r and num(r[1])
  if not n or n < 1 then return {}, nil end
  n = min(floor(n), Trainer.MAX_SERVICES)
  local out, shape = {}, nil
  for i = 1, n do
    local v = callAll(GetTrainerServiceInfo, i)
    if v then
      if not shape then
        local t = {}
        local last = 0
        for k = 1, 8 do
          local x = v[k]
          t[k] = (x == nil and "-") or (isSecret(x) and "x") or string.sub(type(x), 1, 1)
          if x ~= nil then last = k end
        end
        shape = table.concat(t, ",", 1, math.max(last, 1))
      end
      local name = str(v[1])
      local stype, rank, level
      for k = 2, 8 do
        local x = v[k]
        if not stype and str(x) and Trainer.SERVICE_TYPES[x] then
          stype = x
        elseif not stype and not rank and str(x) then
          rank = x
        elseif stype and not level and num(x) and x >= 1 and x <= 100 and x == floor(x) then
          level = x
        end
      end
      local c = callAll(GetTrainerServiceCost, i)
      local cost = c and num(c[1])
      local isProf = c and not isSecret(c[2]) and c[2] == true
      if name and stype ~= "header" then
        out[#out + 1] = { name = ns.Sanitize.field(name), rank = rank and ns.Sanitize.field(rank) or nil, type = stype,
          level = level, cost = cost and floor(cost) or nil, profession = isProf or nil }
      end
    end
  end
  return out, shape
end

-- class trainer? at least one service (no profession) whose name is a spell of the own class plan
-- Pet trainer (hunter Beast Training): its window never counts as class trainer (no trainerVisit, no trainer place)
local function petNames()
  local LP = L()
  local p = LP and LP.player()
  if not (p and type(LP.petIds) == "function") then return nil end
  local set, n = {}, 0
  for _, id in ipairs(LP.petIds(p.class)) do
    local info = LP.spellInfo(id)
    if info and not info.missing and info.name then
      set[info.name] = true
      n = n + 1
    end
  end
  return n > 0 and set or nil
end

local function classNames()
  local LP = L()
  local p = LP and LP.player()
  local plan = p and LP.parse(p.class)
  if not plan then return nil end
  local set = {}
  for _, e in ipairs(plan.list) do
    local info = LP.spellInfo(e.id)
    if info and not info.missing then set[info.name] = true end
  end
  return set
end

-- C_Trainer.GetTrainerType() == Enum.TrainerType.Pet (only where both exist; pcall, secret-safe)
local function petWindowType()
  local CT = rawget(_G, "C_Trainer")
  if type(CT) ~= "table" or isSecret(CT) or type(CT.GetTrainerType) ~= "function" then return false end
  local E = rawget(_G, "Enum")
  local TT = type(E) == "table" and not isSecret(E) and E.TrainerType or nil
  local petType = type(TT) == "table" and not isSecret(TT) and num(TT.Pet) or nil
  if not petType then return false end
  local r = callAll(CT.GetTrainerType)
  return r ~= nil and num(r[1]) == petType
end

-- Pet trainer window: the window type says Pet, or (fallback) its rows name pet abilities and no row names a class spell
function Trainer.isPetWindow(services)
  if petWindowType() then return true end
  local pets = petNames()
  if not pets then return false end
  local classSet = classNames() or {}
  local anyPet = false
  for _, s in ipairs(services) do
    if not s.profession and s.name then
      if pets[s.name] then
        anyPet = true
      elseif classSet[s.name] then
        return false
      end
    end
  end
  return anyPet
end

function Trainer.isClassTrainer(services)
  if Trainer.isPetWindow(services) then return false end
  local set = classNames()
  if not set then return false end
  for _, s in ipairs(services) do
    if not s.profession and set[s.name] then return true end
  end
  return false
end

local function npcID()
  local r = callAll(UnitGUID, "npc")
  local guid = r and str(r[1])
  if not guid then return nil end
  local kind, id = string.match(guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if kind ~= "Creature" or not id then return nil end
  return tonumber(id)
end

local function groupSize(group)
  local c = Store.char()
  local g = c and type(c.snapshots) == "table" and c.snapshots[group]
  local n = 0
  if type(g) == "table" then for _ in pairs(g) do n = n + 1 end end
  return n, g
end

local function put(group, key, values, cap)
  local n, g = groupSize(group)
  if (type(g) ~= "table" or g[key] == nil) and n >= cap then return false end
  return Store.putSnapshot(group, key, values, true)
end

local Collector = {
  requires = { "UnitLevel" },
  events = { "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "PLAYER_LEVEL_UP", "LEARNED_SPELL_IN_SKILL_LINE",
    "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED" },
}
Trainer.collector = Collector
local handlers = {}

function Collector:init()
  self.open, self.readPending, self.checkPending = false, false, false
  self.visits, self.shape = 0, nil
  self.toldLevel, self.toldLogin = nil, false
  self.pendingTalent, self.pendingSlip = nil, nil
  if not Trainer.active() then return end
  Core.after(self, Trainer.LOGIN_DELAY, function(s)
    Trainer.checkTodo()
    Trainer.loginTodo()
    Trainer.talentNotice(s, playerLevel(), "login")
    Trainer.flushTodoToast(s)
  end)
end

-- 1. Visit

function Trainer.readVisit(self)
  self = self or Collector
  if not (Trainer.active() and Store.ready()) then return false end
  local services, shape = Trainer.readServices()
  if shape then self.shape = shape end
  if #services == 0 or not Trainer.isClassTrainer(services) then return false end
  local LP = L()
  local p = LP.player()
  local level = playerLevel()
  self.visits = (self.visits or 0) + 1
  -- place of the trainer = player position at the visit (you stand next to them)
  local mapID, x, y = ns.Zone.here()
  local nr = callAll(UnitName, "npc")
  local npcName = nr and str(nr[1])
  local key = npcID() or (npcName and ("n:" .. ns.Sanitize.field(npcName)))
  if key and mapID and x and y then
    put("trainers", key, { name = npcName, mapID = mapID, x = x, y = y, class = p.class, level = level }, Trainer.MAX_TRAINERS)
  end
  local names = {}
  for _, s in ipairs(services) do
    if not s.profession then
      put("trainerSpells", s.rank and (s.name .. " #" .. s.rank) or s.name, { name = s.name, rank = s.rank, type = s.type, level = s.level,
        cost = s.cost, seenLevel = level }, Trainer.MAX_SPELLS)
      if s.type == "available" and #names < Trainer.MAX_NAMES then names[#names + 1] = s.name end
    end
  end
  if level then Store.putSnapshot("state", "trainerVisit", { level = level, names = names }, true) end
  return true
end

local function scheduleRead(self, delay)
  if self.readPending then return end
  self.readPending = true
  if not Core.after(self, delay, function(s)
    s.readPending = false
    if s.open then Trainer.readVisit(s) end
  end) then
    self.readPending = false
  end
end

-- 2. To-do "Zum Lehrer"

function Trainer.todoText(n, cost)
  local LC = ns.Locale
  local key = LC and LC.plural and LC.plural(n, "todo_one", "todo_other") or (n == 1 and "todo_one" or "todo_other")
  return T(key, n, moneyText(cost))
end

-- Marker snapshots.state.<key> (additive, no schema change): trainerTodo = { level } (level for which the to-do was created or found
-- open: a to-do ticked off or deleted does not come back at the next login), trainerPlace = { id } (to-do made via "Als To Do" in the
-- Lehrplan, see Trainer.markPlace)
local function stateEntry(key)
  local c = Store.char()
  local st = c and type(c.snapshots) == "table" and type(c.snapshots.state) == "table" and c.snapshots.state[key] or nil
  return type(st) == "table" and st or nil
end

local function todoMarkLevel()
  local m = stateEntry("trainerTodo")
  return m and num(m.level) or nil
end

local function markTodoLevel(level)
  level = num(level)
  if not level then return false end
  return Store.putSnapshot("state", "trainerTodo", { level = floor(level) }, true)
end

-- Called by the Lehrplan page after "Als To Do": remembers the place to-do (id) so that a login does not add a second one
function Trainer.markPlace(id)
  id = num(id)
  if not (id and Store.ready()) then return false end
  return Store.putSnapshot("state", "trainerPlace", { id = floor(id) }, true)
end

-- Is a place to-do made via "Als To Do" in the Lehrplan still open? New entries: by the remembered id (state.trainerPlace). Older
-- entries (made before the marker existed): an open place to-do with the exact spot (map, x, y) AND the name of a trainer known for
-- this class. A free to-do typed by hand is never guessed.
function Trainer.lehrplanTodoOpen()
  local P = ns.Plans
  if not (P and type(P.get) == "function" and type(P.list) == "function" and type(P.cleanText) == "function") then return false end
  local m = stateEntry("trainerPlace")
  local mid = m and num(m.id)
  if mid then
    local p = P.get(mid)
    if p and p.kind == "place" and not p.done then return true end
  end
  local LP = L()
  local trainers = LP and type(LP.trainers) == "function" and LP.trainers() or {}
  if #trainers == 0 then return false end
  for _, p in ipairs(P.list("open")) do
    if p.kind == "place" and num(p.mapID) and num(p.x) and num(p.y) and type(p.text) == "string" then
      for _, t in ipairs(trainers) do
        if t.mapID == p.mapID and math.abs(t.x - p.x) < 0.0001 and math.abs(t.y - p.y) < 0.0001
          and P.cleanText(t.name) == p.text then
          return true
        end
      end
    end
  end
  return false
end

-- level-up: create/update the to-do if something is learnable now; returns the to-do id or nil
function Trainer.levelUp(level)
  if not (Trainer.active() and setting("trainerTodo") and ns.Plans) then return nil end
  local LP = L()
  local view = LP.evaluate({ level = level, names = true })
  if not view.available or view.todo.n < 1 then return nil end
  local id, how = ns.Plans.upsertAuto(Trainer.TAG, Trainer.todoText(view.todo.n, view.todo.cost))
  if id and how == "new" then Collector.pendingTodoToast = view.todo.n end -- announced by Trainer.flushTodoToast
  if id then markTodoLevel(level or playerLevel()) end
  return id
end

-- login: creates the to-do "Zum Lehrer" once per level if spells are learnable now. Never a second one: an open automatic to-do
-- (any level, only its text follows the count; checkTodo has done that) or an open Lehrplan place to-do counts as "there is one".
-- Returns "new" | "open" | nil (nothing done)
function Trainer.loginTodo()
  local P = ns.Plans
  if not (Trainer.active() and setting("trainerTodo") and P and Store.ready()) then return nil end
  local level = playerLevel()
  if not level then return nil end
  local view = L().evaluate({ names = true })
  if not view.available or view.todo.n < 1 then return nil end
  if P.findAuto(Trainer.TAG) or Trainer.lehrplanTodoOpen() then
    markTodoLevel(level)
    return "open"
  end
  if todoMarkLevel() == level then return nil end
  local id, how = P.upsertAuto(Trainer.TAG, Trainer.todoText(view.todo.n, view.todo.cost))
  if not id then return nil end -- no marker: the next login tries again
  markTodoLevel(level)
  if how == "new" then
    Collector.pendingTodoToast = view.todo.n
    return "new"
  end
  return "open"
end

-- open to-do: completed when nothing learnable is left, else the text follows the count. Returns "done" | "open" | nil
function Trainer.checkTodo()
  local P = ns.Plans
  if not (Trainer.active() and P and P.findAuto(Trainer.TAG)) then return nil end
  local view = L().evaluate({ names = true })
  if not view.available then return nil end
  if view.todo.n < 1 then
    P.finishAuto(Trainer.TAG, "trainer")
    return "done"
  end
  P.upsertAuto(Trainer.TAG, Trainer.todoText(view.todo.n, view.todo.cost))
  return "open"
end

local function scheduleCheck(self)
  if self.checkPending then return end
  self.checkPending = true
  if not Core.after(self, Trainer.CHECK_DELAY, function(s)
    s.checkPending = false
    Trainer.checkTodo()
  end) then
    self.checkPending = false
  end
end

-- 3. Talent points

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

function Trainer.talentItem(n)
  local Theme = ns.Journal and ns.Journal.Theme
  local LC = ns.Locale
  local key = LC and LC.plural and LC.plural(n, "talent_one", "talent_other") or (n == 1 and "talent_one" or "talent_other")
  local icon
  if Theme and Theme.TEX and Theme.TEX.markers and Theme.ATLAS and type(Theme.atlasCoords) == "function" then
    icon = { tex = Theme.TEX.markers, coords = { Theme.atlasCoords(Theme.ATLAS.milestone) }, color = Theme.C and Theme.C.sepia, size = 40 }
  end
  return { kind = "talent", key = "talent:" .. tostring(n), head = T.talentHead, title = T(key, n), sub = T.talentSub,
    icon = icon, noOpen = true }
end

function Trainer.todoToastItem(n)
  local Theme = ns.Journal and ns.Journal.Theme
  local LC = ns.Locale
  local key = LC and LC.plural and LC.plural(n, "todoToast_one", "todoToast_other") or (n == 1 and "todoToast_one" or "todoToast_other")
  local icon
  if Theme and Theme.TEX and Theme.TEX.markers and Theme.ATLAS and type(Theme.atlasCoords) == "function" then
    icon = { tex = Theme.TEX.markers, coords = { Theme.atlasCoords(Theme.ATLAS.milestone) }, color = Theme.C and Theme.C.sepia, size = 40 }
  end
  local TT = ns.Journal and ns.Journal.TodoTracker
  return { kind = "todo", key = "todo:" .. Trainer.TAG, head = T.todoToastHead, title = T.todoToastTitle, sub = T(key, n), icon = icon,
    after = TT and TT.openBook or nil }
end

-- Queues the pending to-do toast: not in combat, not while a level-up note is pending or on screen (then it re-registers with
-- Begleiter.afterSlip and comes when the note has left). Returns true if it is queued or still waiting.
function Trainer.flushTodoToast(self)
  self = self or Collector
  local n = self.pendingTodoToast
  if not n then return false end
  local Toast = ns.Journal and ns.Journal.Toast
  if not (Toast and type(Toast.enqueue) == "function") then
    self.pendingTodoToast = nil
    return false
  end
  if inCombat() or self.pendingSlip then return true end -- PLAYER_REGEN_ENABLED / flushSlip call this again
  local B = ns.Journal and ns.Journal.Begleiter
  if B and type(B.slipKind) == "function" and B.slipKind() and type(B.afterSlip) == "function"
    and B.afterSlip(function() Trainer.flushTodoToast(self) end, { key = "todoToast" }) then
    return true
  end
  self.pendingTodoToast = nil
  return Toast.enqueue(Trainer.todoToastItem(n)) and true or false
end

-- why: "login" (once per session) | "level" (once per level). Returns true if a toast was queued.
function Trainer.talentNotice(self, level, why)
  self = self or Collector
  if not (Trainer.active() and setting("talentHint")) then return false end
  local LP = L()
  local n = LP.unspentTalents()
  if not n or n < 1 then return false end
  if why == "login" then
    if self.toldLogin then return false end
  elseif level and self.toldLevel == level then
    return false
  end
  local Toast = ns.Journal and ns.Journal.Toast
  if not (Toast and type(Toast.enqueue) == "function") then return false end
  if inCombat() then
    self.pendingTalent = { level = level, why = why }
    return false
  end
  local ok = Toast.enqueue(Trainer.talentItem(n))
  if ok then
    self.toldLogin = true
    if level then self.toldLevel = level end
  end
  return ok and true or false
end

-- 4. Level-up note

local function shownText(v)
  if type(v) ~= "string" or isSecret(v) then return nil end
  local s = ns.Sanitize.display(v, Trainer.SLIP_NAME_MAX)
  if s == "" then return nil end
  return s
end

-- Random variant of a text list. Trainer.random(n) -> 1..n (tests replace it); Trainer.picks[kind] = last index per kind:
-- the same variant never comes twice in a row.
Trainer.random = function(n) return math.random(n) end
Trainer.picks = {}

local function listOf(v)
  if type(v) == "table" and #v > 0 then return v end
  return { tostring(v) }
end

local function pick(kind, list)
  list = listOf(list)
  local n = #list
  local r = Trainer.random(n)
  local i = num(r) and floor(r) or 1
  if i < 1 or i > n then i = ((i - 1) % n) + 1 end
  if n > 1 and Trainer.picks[kind] == i then i = i % n + 1 end
  Trainer.picks[kind] = i
  return list[i]
end

local function fill(text, args)
  return ns.Locale.fmt(text, args)
end

local function cap(s)
  return (s:gsub("^%l", string.upper))
end

-- number word for 2..12 ("zwei"), otherwise the digits
local function numWord(n)
  n = floor(n)
  if n >= 2 and n <= 12 then
    local i = 1
    for w in string.gmatch(T.slipNumWords, "%S+") do
      i = i + 1
      if i == n then return w end
    end
  end
  return string.format("%d", n)
end

local function compose(...)
  local out = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if type(v) == "string" and v ~= "" then out[#out + 1] = v end
  end
  return table.concat(out, " ")
end

local function playerName()
  local r = callAll(UnitName, "player")
  return shownText(r and str(r[1])) or T.slipNameFallback
end

-- first sentence of a greeting up to the first "!" (the leaner form); the whole greeting if there is none
local function shortGreet(g)
  return g:match("^(.-!)") or g
end

-- "A, B and C", with a rest: "A, B, C and n more"
local function nameList(names, k, n)
  local more
  if n > k then
    local m = n - k
    more = m == 1 and T.slipMoreOne or fill(T.slipMoreOther, { n = numWord(m) })
  end
  if more or k == 1 then
    return table.concat(names, ", ", 1, k) .. (more and (" " .. more) or "")
  end
  return table.concat(names, ", ", 1, k - 1) .. T.slipAnd .. names[k]
end

-- Content of the level-up note for a level: nil (not Forever / no plan data) or
-- { kind = "level", level, title, variants = { { text }, ... }, learnable = n, cost, short, talents = n|nil, trainer = zone|nil,
--   hint, closable = true, onClick }.
-- The narrator speaks in flowing text: greeting, what can be learned (names up to 3), cost, talent points - one variant text per
-- step. variants run from the fullest to the leanest (Begleiter.showNote takes the first that fits the parchment): first single
-- spell names fall away (into "... and n more"), then the trainer's place ("at your trainer"), last the greeting's second sentence;
-- greeting, cost and talent sentence stay. The wording is picked at random from 6 variants per case (see pick).
-- Spell, zone, trainer and player names are foreign text: Sanitize.display; numbers go through format("%d").
function Trainer.levelSlipContent(level)
  if not Trainer.active() then return nil end
  local LP = L()
  local view = LP.evaluate({ level = num(level) and floor(level) or nil, names = true })
  if not view.available then return nil end
  local lv = floor(num(view.level) or num(level) or 1)
  local out = { kind = "level", level = lv, title = T("slipTitle", lv), learnable = view.todo.n,
    hint = T.slipHint, closable = true, onClick = Trainer.openLehrplan }
  local greet = fill(pick("slipGreet", T.slipGreet), { name = playerName() })
  local greetShort = shortGreet(greet)
  local talents = setting("talentHint") and LP.unspentTalents() or nil
  local talentLine
  if talents and talents >= 1 then
    out.talents = talents
    local key = talents == 1 and "slipTalent_one" or "slipTalent_other"
    talentLine = cap(fill(pick(key, T[key]), { count = numWord(talents) }))
  end
  if view.todo.n < 1 then
    local nx = view.next[1]
    local body
    if nx then
      body = fill(pick("slipNext", T.slipNext), { next = string.format("%d", floor(nx.level)) })
    else
      body = pick("slipNothing", T.slipNothing)
    end
    out.variants = { { compose(greet, body, talentLine) }, { compose(greetShort, body, talentLine) } }
    return out
  end
  -- learnable now and offered by the trainer (sorted by level)
  local names = {}
  for _, r in ipairs(LP.rows(view, "now")) do
    if r.state == "now" and r.offered then
      local nm = shownText(r.name) or shownText(LP.TEXT("spellFallback", floor(r.id)))
      local rk = shownText(r.rank)
      if nm then names[#names + 1] = rk and T("slipSpell", nm, rk) or nm end
    end
  end
  local n = view.todo.n
  local cost = view.todo.cost
  out.cost = cost
  local costLine
  if num(cost) and cost > 0 then
    if view.money and cost > view.money then
      out.short = cost - view.money
      costLine = fill(pick("slipCostShort", T.slipCostShort), { cost = moneyText(cost), short = moneyText(out.short) })
    else
      costLine = fill(pick("slipCost", T.slipCost), { cost = moneyText(cost) })
    end
  end
  local near = LP.nearestTrainer(LP.player())
  local tname = near and shownText(near.name) or nil
  local zone = near and shownText(near.zone) or nil
  out.trainer = zone or tname
  local whereFull
  if tname and zone then
    whereFull = fill(T.slipWhereBoth, { trainer = tname, zone = zone })
  elseif zone then
    whereFull = fill(T.slipWhereZone, { zone = zone })
  elseif tname then
    whereFull = fill(T.slipWhereTrainer, { trainer = tname })
  else
    whereFull = T.slipWhereAny
  end
  local one = n == 1
  local template = pick(one and "slipLearn_one" or "slipLearn_other", one and T.slipLearn_one or T.slipLearn_other)
  local count = one and T.slipCountOne or fill(T.slipCountOther, { n = numWord(n) })
  local function learnSentence(where, k)
    local head = cap(fill(template, { where = where, count = count }))
    if k < 1 then return head .. T.slipNamesNone end
    return head .. fill(T.slipNames, { names = nameList(names, k, n) })
  end
  local maxK = math.min(Trainer.SLIP_SPELLS, #names, n)
  out.variants = {}
  for _, where in ipairs({ whereFull, T.slipWhereShort }) do
    for k = maxK, 0, -1 do
      out.variants[#out.variants + 1] = { compose(greet, learnSentence(where, k), costLine, talentLine) }
    end
  end
  out.variants[#out.variants + 1] = { compose(greetShort, learnSentence(T.slipWhereShort, 0), costLine, talentLine) }
  return out
end

-- Click on the note: open the book at Pläne -> Lehrplan. In combat the book stays shut (chat hint) and the note stays. Returns
-- false = keep the note (also when the page could not be opened: chat hint), otherwise Begleiter closes it.
function Trainer.openLehrplan()
  if inCombat() then
    Core.print(T.slipCombat)
    return false
  end
  local LP = L()
  local ok, opened = false, false
  if LP and type(LP.openPage) == "function" then ok, opened = pcall(LP.openPage) end
  if not ok or opened ~= true then
    Core.print(T.slipOpenFail)
    return false
  end
  return true
end

-- Shows the pending level-up note now, or waits: in combat (until PLAYER_REGEN_ENABLED, then evaluated afresh), behind an open
-- welcome note (until it has left). Returns true if a note is shown or still waiting, false if nothing will come (the caller then
-- shows the old talent toast).
function Trainer.flushSlip(self)
  self = self or Collector
  local level = self.pendingSlip
  if not level then return false end
  local B = ns.Journal and ns.Journal.Begleiter
  if not (B and type(B.showNote) == "function") then
    self.pendingSlip = nil
    return false
  end
  if inCombat() then return true end
  local kind = type(B.slipKind) == "function" and B.slipKind() or nil
  if kind and kind ~= "level" and type(B.afterSlip) == "function"
    and B.afterSlip(function() Trainer.flushSlip(self) end, { note = true, key = "levelSlip" }) then
    return true
  end
  self.pendingSlip = nil
  local content = Trainer.levelSlipContent(level)
  if content and B.showNote(content) then
    if content.talents then self.toldLevel = level end
    Trainer.flushTodoToast(self)
    return true
  end
  Trainer.flushTodoToast(self)
  return false
end

-- PLAYER_LEVEL_UP: true if the note takes over (then no talent toast for this level)
function Trainer.levelSlip(self, level)
  self = self or Collector
  if not (Trainer.active() and setting("levelSlip")) then return false end
  local B = ns.Journal and ns.Journal.Begleiter
  if not (B and type(B.showNote) == "function") then return false end
  level = level or playerLevel()
  if not level or not L().evaluate({ level = level, names = false }).available then return false end
  self.pendingSlip = level -- several level-ups in a row: the newest state wins
  return Trainer.flushSlip(self)
end

-- /chronik stufe: preview for the current level (also when the option is off)
function Trainer.slashLevel()
  local print_ = Core.print
  if not Trainer.active() then
    print_(T.retailOnly)
    return false
  end
  local B = ns.Journal and ns.Journal.Begleiter
  local content = Trainer.levelSlipContent(playerLevel())
  if not (B and type(B.showNote) == "function" and content) then
    print_(T.slipNoData)
    return false
  end
  return B.showNote(content)
end

-- Events

handlers.TRAINER_SHOW = function(self)
  if not Trainer.active() then return end
  self.open = true
  scheduleRead(self, Trainer.READ_DELAY)
end

handlers.TRAINER_UPDATE = function(self)
  if not (Trainer.active() and self.open) then return end
  scheduleRead(self, Trainer.UPDATE_DELAY)
end

handlers.TRAINER_CLOSED = function(self)
  if not Trainer.active() then return end
  self.open = false
  scheduleCheck(self)
end

handlers.PLAYER_LEVEL_UP = function(self, level)
  if not Trainer.active() then return end
  local lv = num(level)
  lv = lv and floor(lv) or nil
  Core.after(self, Trainer.LEVEL_DELAY, function(s)
    Trainer.levelUp(lv)
    if not Trainer.levelSlip(s, lv or playerLevel()) then Trainer.talentNotice(s, lv or playerLevel(), "level") end
    Trainer.flushTodoToast(s)
  end)
end

handlers.LEARNED_SPELL_IN_SKILL_LINE = function(self)
  if Trainer.active() then scheduleCheck(self) end
end
handlers.SPELLS_CHANGED = handlers.LEARNED_SPELL_IN_SKILL_LINE

handlers.PLAYER_REGEN_ENABLED = function(self)
  if self.pendingSlip and not Trainer.flushSlip(self) then
    Trainer.talentNotice(self, playerLevel(), "level")
  end
  local p = self.pendingTalent
  if p then
    self.pendingTalent = nil
    Trainer.talentNotice(self, p.level, p.why)
  end
  Trainer.flushTodoToast(self)
end

function Collector:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

-- Diagnostics (/chronik diag)
function Trainer.diagLine()
  local LP = L()
  if not LP then return T("diag", T.unknown) end
  if not LP.active() then return T("diag", T.diagRetail) end
  local p = LP.player()
  local plan = LP.parse(p.class)
  if not plan then return T("diag", T("diagNoData", p.class or T.unknown)) end
  local view = LP.evaluate({ names = false })
  local _, known = LP.nearestTrainer(p)
  local free = LP.unspentTalents()
  local self = Collector
  return T("diag", T("diagOn", p.class, #plan.list, view.now.n, known or 0, self.visits or 0,
    free ~= nil and free or T.unknown, self.shape and T("diagShape", self.shape) or ""))
end

-- /chronik lehrplan [status]: open the page (Pläne -> Lehrplan) or print the state line
function Trainer.slash(rest)
  local print_ = Core.print
  local LP = L()
  if type(rest) == "string" and rest ~= "" and rest ~= "status" and rest ~= "diag" then
    print_(T("unknownArg", ns.Sanitize.field(rest)))
    return false
  end
  if rest == "status" or rest == "diag" then
    print_(Trainer.diagLine())
    return true
  end
  if not (LP and LP.active()) then
    print_(T.retailOnly)
    return false
  end
  if type(LP.openPage) ~= "function" or not LP.openPage() then
    print_(Trainer.diagLine())
    return false
  end
  return true
end

ns.RegisterCollector("Trainer", Collector)
