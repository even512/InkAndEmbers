-- Collector 'Trainer' (WoW Forever only; on retail it stays idle): class trainer, Lehrplan and talent points.
-- 1. Silent visit collector: on TRAINER_SHOW/TRAINER_UPDATE (batched) the services of a CLASS trainer are read (name, rank text,
--    type, level, cost) into snapshots.trainerSpells["<name> #<rank>"] and the trainer's place (player position at the visit) into
--    snapshots.trainers[npcID] (read by Journal.Lehrplan: nearest trainer). The service names offered as "available" go to
--    snapshots.state.trainerVisit (level, names): the Lehrplan then knows which entries this trainer really offered.
-- 2. To-do "Zum Lehrer": after a level-up with spells learnable now, one free to-do (Plans.upsertAuto "trainer"); it is updated
--    or completed (Plans.finishAuto) as soon as nothing learnable is left (spell learned, trainer closed). Setting trainerTodo.
-- 3. Talent points: free points (Journal.Lehrplan.unspentTalents) -> one toast per level and session, never in combat (the
--    toast queue waits). Setting talentHint.
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
  diag = "Lehrplan: %s",
  diagRetail = "aus (Retail: Klassenzauber kommen von selbst)",
  diagOn = "Klasse %s, %s Einträge, jetzt lernbar %s, Lehrer bekannt %s, Besuche %s, freie Talentpunkte %s%s",
  diagNoData = "keine Daten für Klasse %s",
  diagShape = ", Lehrerliste: %s",
  unknown = "?",
  unknownArg = "Unbekannter Zusatz \"%s\". /chronik lehrplan öffnet die Seite, /chronik lehrplan status zeigt den Stand.",
  retailOnly = "Den Lehrplan gibt es nur in WoW Forever (in Retail kommen Klassenzauber von selbst).",
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

function Trainer.isClassTrainer(services)
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
  self.pendingTalent = nil
  if not Trainer.active() then return end
  Core.after(self, Trainer.LOGIN_DELAY, function(s)
    Trainer.checkTodo()
    Trainer.talentNotice(s, playerLevel(), "login")
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

-- level-up: create/update the to-do if something is learnable now; returns the to-do id or nil
function Trainer.levelUp(level)
  if not (Trainer.active() and setting("trainerTodo") and ns.Plans) then return nil end
  local LP = L()
  local view = LP.evaluate({ level = level, names = true })
  if not view.available or view.todo.n < 1 then return nil end
  local id = ns.Plans.upsertAuto(Trainer.TAG, Trainer.todoText(view.todo.n, view.todo.cost))
  return id
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
    Trainer.talentNotice(s, lv or playerLevel(), "level")
  end)
end

handlers.LEARNED_SPELL_IN_SKILL_LINE = function(self)
  if Trainer.active() then scheduleCheck(self) end
end
handlers.SPELLS_CHANGED = handlers.LEARNED_SPELL_IN_SKILL_LINE

handlers.PLAYER_REGEN_ENABLED = function(self)
  local p = self.pendingTalent
  if not p then return end
  self.pendingTalent = nil
  Trainer.talentNotice(self, p.level, p.why)
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

-- /chronik lehrplan [status]: open the page (Quests -> Lehrplan) or print the state line
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
