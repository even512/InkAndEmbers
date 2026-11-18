-- Docking bar at the Blizzard profession window (WoW Forever only; Retail has no recipe cache, the bar never exists there): the
-- work order ("Werkauftrag", 1.1.0) at the workbench, in two modes on the dark plate of journal/WerkBarKit.lua:
--   (1) Planen: head "Werkauftrag · profession skill/max", the chain 1-2-3, "Wohin wollt Ihr?" (goal chips of Route.goals plus
--       "Nur dieses Rezept" when the player chose a recipe in Blizzard's window), "Eure Route" as a time line (stages with colour dot,
--       skill range, "ca. N×", trainer diamonds; journal/model/Route.lua), "Material für die ganze Route" (bags / missing / made
--       oneself), the switch "Zwischenprodukte selbst herstellen", costs auction house + trainer and the one main button
--       "Auftrag anlegen" (everything there: "Herstellen", the order is made and the first step crafted from the same click).
--       A recipe chosen in Blizzard's window gives a single order of that recipe with an amount (+/-).
--   (3) Herstellen (an open order of this profession, or one whose current step belongs to it): the step list (done / current with
--       progress bar / to do), the main button "Herstellen · N× Name", "Beruf öffnen · X" (step in another profession: OpenRecipe
--       switches the window and chooses the recipe) or "Zum Lehrer · Wegpunkt setzen" (Journal.LehrerOrte + Journal.Waypoint); the
--       button follows the order (ns.Werk.status) after every step, a short line reports a finished step / stage / order.
-- Orders, stations and the shopping list live in the core (collectors/Werkauftrag.lua, ns.Werk); nothing is stored here but the
-- choices of this session (goal, amount, view).
--
-- Taint rules (everything towards Blizzard's frames is READ ONLY):
--   * the bar is a frame of UIParent; only a SetPoint anchors it to ProfessionsFrame, and only outside combat (in combat nothing is
--     built, moved or re-anchored; the bar only follows the window's visibility, with Hide()/alpha);
--   * no HookScript / SetScript / hooksecurefunc on a Blizzard frame, no write into a Blizzard frame or table, no Show/Hide on it;
--   * the window is found lazily (rawget(_G, "ProfessionsFrame"): Blizzard_Professions loads on demand; ADDON_LOADED and TRADE_SKILL_SHOW
--     wake the bar), without it the bar does nothing;
--   * visibility: TRADE_SKILL_SHOW / TRADE_SKILL_CLOSE plus a light poll (PB.POLL seconds) of ProfessionsFrame:IsShown() while the window
--     is open; the poll frame is our own and stays hidden (no OnUpdate) while no window is open;
--   * the chosen recipe comes from EventRegistry "ProfessionsRecipeListMixin.Event.OnRecipeSelected" (own owner table; the handler only
--     stores the recipe id, nothing is drawn inside Blizzard's call) or, without it, from SchematicForm:GetRecipeInfo() under pcall;
--   * C_TradeSkillUI.CraftRecipe / OpenRecipe / OpenTradeSkill and Journal.Waypoint.set are called ONLY from the OnClick of our own
--     buttons (from a timer the game blocks them: ADDON_ACTION_BLOCKED); blocked once (error or Core.actionLog) -> fallback for the
--     session: the button only chooses the recipe in the window and says so.
-- Option "professionBar" (Pages setting, default on; Options: "Leiste am Berufsfenster"). Texts: locale area "WerkBar"
-- (locales/<lang>_werkbar.lua).
local _, ns = ...

local Journal = ns.Journal
local W = Journal and Journal.Widgets
local E = ns.Einkauf
local Kit = Journal and Journal.WerkBarKit
local Route = Journal and Journal.Route
if not (Journal and W and E and Kit and Route) then return end

local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil

local PB = {}
Journal.ProfessionBar = PB

PB.NAME = "EveNChronicleProfessionBar"
PB.WINDOW = "ProfessionsFrame"
PB.EVENT = "ProfessionsRecipeListMixin.Event.OnRecipeSelected"
PB.W = 280              -- width of the bar
PB.PAD = 12
PB.GAP = 3              -- distance to the window
PB.POLL = 0.25          -- seconds between two looks at the window while it is open
PB.GRACE = 3            -- seconds after TRADE_SKILL_SHOW in which a not yet visible window is waited for
PB.SELECT_QUIET = 1     -- seconds after TRADE_SKILL_SHOW: the window's own first selection is not the player's choice
PB.SCAN_MAX = 160       -- frames looked at when searching Blizzard's side tabs
PB.TAB_MAX_W = 120      -- a side tab is narrower than this
PB.TAB_EDGE = 40        -- ... and starts within this distance of the window edge
PB.ROW_H = 16
PB.GOALS_MAX = 5        -- goal chips (Route.goals gives at most three, plus "Nur dieses Rezept")
PB.ROUTE_ROWS = 6       -- stages of the time line
PB.MAT_ROWS = 6
PB.STEP_ROWS = 7
PB.CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"
PB.COST_LABEL_W = 150   -- cost line: label left, the amount right of it (never overlapping), missing prices in a line below
PB.COST_GAP = 6
PB.COLORS = Kit.COLORS

PB.TEXT = ns.Locale.ns("WerkBar", {
  head = "WERKAUFTRAG",
  headGoal = "WERKAUFTRAG · BIS %s",
  skillOf = "%s %s / %s",
  goalHead = "Wohin wollt Ihr?",
  goalNext = "Nächster Punkt",
  goalNextTip = { "Nächster Punkt", "Plant genau einen Skillpunkt." },
  goalTip = { "Ziel-Skill", "Plant die Route bis zu diesem Skill." },
  goalRecipe = "Nur dieses Rezept",
  goalRecipeTip = { "Nur dieses Rezept", "Ein Werkauftrag für das im Berufsfenster gewählte Rezept, mit Anzahl." },
  routeHead = "EURE ROUTE",
  stageTitle = "%s× %s",
  stageTitleEst = "ca. %s× %s",
  stageRange = "%s – %s",
  stageLearned = "gelernt · %s",
  stageNew = "beim Lehrer · %s · Menge geschätzt",
  stageUnknown = "nach dem Lernen · Material zeigt das Spiel erst dann",
  orange = "orange", yellow = "gelb", green = "grün", grey = "grau",
  trainerTitle = "Lehrer: %s lernen",
  trainerAt = "bei %s",
  trainerCost = "kostet %s · kommt in den Auftrag",
  moreStages = "+%s weitere Etappen",
  matHead = "MATERIAL FÜR DIE GANZE ROUTE",
  matHeadOne = "MATERIAL",
  matName = "%s · %s",
  matBags = "%s in den Taschen",
  matSelf = "stellt Ihr selbst her",
  chipOk = "da",
  chipMissing = "%s fehlen",
  chipSelf = "%s× selbst",
  moreMats = "+%s weitere",
  resolve = "Zwischenprodukte selbst herstellen",
  resolveTip = { "Zwischenprodukte selbst herstellen",
    "Was Ihr mit einem gelernten Rezept selbst herstellen könnt (auch in einem anderen Beruf, z. B. Kupferbarren aus Bergbau), wird ein eigener Schritt statt Einkauf." },
  unknownMats = "Etappe „%s“: Material kommt von selbst auf den Einkaufszettel, sobald Ihr das Rezept gelernt habt.",
  costLabel = "Kosten Auktionshaus + Lehrer",
  costValue = "ca. %s",
  costPrices = "%s Preise fehlen noch (am Auktionshaus)",
  costNone = "Preise zeigt das Auktionshaus",
  countLabel = "Anzahl",
  minusTip = "Weniger (Umschalt: 10 weniger)",
  plusTip = "Mehr (Umschalt: 10 mehr)",
  create = "Auftrag anlegen · bis %s",
  createOne = "Auftrag anlegen · %s× %s",
  createHint = "Fehlendes kommt auf den Einkaufszettel",
  createMake = "Herstellen · %s× %s",
  createMakeHint = "Alles da: legt den Auftrag an und stellt her",
  saved = "Auftrag angelegt – nächster Halt: Auktionshaus.",
  savedReady = "Auftrag angelegt – alles da, weiter mit Herstellen.",
  changed = "Auftrag geändert.",
  nocache = "Öffnet das Berufsfenster einmal ganz, dann plant Ink & Embers die Route.",
  gap = "Ab Skill %s fehlt ein passendes Rezept – beim Lehrer gibt es neue.",
  limit = "Die Route endet bei %s (höchstens 60 Schritte); danach plant Ihr weiter.",
  reached = "Dieses Ziel habt Ihr schon erreicht.",
  nodata = "Für diesen Beruf lässt sich noch keine Route planen.",
  pick = "Wählt im Berufsfenster ein Rezept.",
  loading = "Dieses Rezept ist noch nicht im Rezeptbuch gespeichert. Es wird gleich gelesen.",
  orderOf = "Auftrag %s von %s",
  nextOrder = "Nächster Auftrag",
  newOrder = "Neuen Auftrag planen",
  backOrder = "Zum offenen Auftrag",
  stepCraft = "%s× %s",
  stepTrainer = "Lehrer: %s",
  stepDone = "erledigt",
  stepRange = "Skill %s – %s",
  stepRangeEst = "Skill %s – %s · Menge geschätzt",
  stepPre = "Vorstufe · %s",
  stepTrainerSub = "beim Berufslehrer · %s",
  stepUnknown = "Material zeigt das Spiel nach dem Lernen",
  stepStuck = "bringt kaum noch Punkte – lernt ein neues Rezept",
  moreSteps = "+%s weitere Schritte",
  make = "Herstellen · %s× %s",
  makeHint = "Danach springt der Knopf zum nächsten Schritt.",
  makePart = "Mit dem, was da ist; der Rest steht auf dem Einkaufszettel.",
  openProf = "Beruf öffnen · %s",
  openProfHint = "Öffnet das Fenster %s und wählt das Rezept vor.",
  trainer = "Zum Lehrer · Wegpunkt setzen",
  trainerHint = "Gelernt? Dann geht es hier von selbst weiter.",
  trainerNone = "Kein Lehrer-Ort bekannt – fragt eine Stadtwache.",
  buyFirst = "Erst einkaufen",
  buyHint = "Weiter im Auktionshaus: %s× %s fehlt",
  mailFirst = "Post abholen",
  mailHint = "Alles gekauft – Post am Briefkasten abholen, dann zurück zur Werkbank.",
  craftHint = "Alles da – weiter an der Werkbank: %s× %s",
  trainerNext = "Zum Lehrer: %s lernen",
  doneLabel = "Fertig",
  crafting = "Wird hergestellt: %s× %s",
  blocked = "Das Spiel lässt Ink & Embers hier nicht herstellen: das Rezept ist vorgewählt – klickt im Berufsfenster auf „Herstellen“.",
  noApi = "Herstellen geht in diesem Spiel nicht über die Leiste.",
  stepDoneMsg = "Schritt geschafft: %s",
  stageDoneMsg = "Etappe geschafft – Skill %s",
  orderDoneMsg = "Werkauftrag erledigt: %s",
  optLabel = "Leiste am Berufsfenster",
  optTip = "Eine Leiste direkt am Berufsfenster: Werkauftrag planen (Ziel-Skill, Route, Material) und Schritt für Schritt herstellen (nur WoW Forever).",
  pageHead = "WERKAUFTRAG",
  pageNone = "Kein offener Werkauftrag für diesen Beruf.",
  pageHint = "Öffnet das Berufsfenster: die Leiste plant Eure Route zum Ziel-Skill.",
  pageMore = "+%s weitere Aufträge",
  pageTip = { "Werkauftrag", "Klick: dort weitermachen, wo der Auftrag steht." },
})
local T = PB.TEXT

local st = { counts = {}, goals = {}, poll = 0, sig = nil, placeSig = nil, msg = nil, resolve = true, seen = {} }
PB.state = st

-- Reading helpers ----------------------------------------------------------------------------------------------------------------

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function posInt(v)
  v = num(v)
  if not v or v < 1 or v > 2147483647 then return nil end
  return floor(v)
end

local function safe(fn, ...)
  if ns.Core and ns.Core.safe then return ns.Core.safe(fn, ...) end
  return pcall(fn, ...)
end

local function inCombat() return Kit.inCombat() end

local function now()
  if type(GetTime) ~= "function" then return 0 end
  local ok, t = pcall(GetTime)
  return ok and num(t) or 0
end

-- guarded field read of a foreign table
local function field(t, k)
  if type(t) ~= "table" or isSecret(t) then return nil end
  local ok, v = pcall(function() return t[k] end)
  if not ok or isSecret(v) then return nil end
  return v
end

-- result of a foreign method under pcall (read only)
local function method(obj, name, ...)
  if type(obj) ~= "table" or isSecret(obj) then return nil end
  local f = field(obj, name)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(f, obj, ...)
  if not ok or isSecret(a) then return nil end
  return a, b, c, d
end

local function pageSetting()
  local P = Journal.Pages
  if not (P and type(P.setting) == "function") then return true end
  return P.setting("professionBar") ~= false
end

function PB.setting() return pageSetting() end

function PB.enabled()
  return E.active() and pageSetting()
end

function PB.setEnabled(on)
  local P = Journal.Pages
  if P and type(P.setSetting) == "function" then P.setSetting("professionBar", on and true or false) end
  PB.update()
end

-- Blizzard's window (nil as long as Blizzard_Professions is not loaded)
local function window()
  local w = rawget(_G, PB.WINDOW)
  if type(w) ~= "table" or isSecret(w) then return nil end
  return w
end

local function windowShown()
  local w = window()
  return w ~= nil and method(w, "IsShown") == true
end

local function textOf(s, n)
  if type(s) ~= "string" or isSecret(s) or s == "" then return nil end
  local S = ns.Sanitize
  s = S and S.display and S.display(s, n or 60) or s
  if type(s) ~= "string" or s == "" then return nil end
  return s
end

local function int(n) return Journal.Texts and Journal.Texts.int and Journal.Texts.int(n) or tostring(floor(tonumber(n) or 0)) end

-- coin text without zero parts ("25s", "3g 50s"), like elsewhere in the add-on
local function coins(c)
  local Tx = Journal.Texts
  c = floor(c or 0)
  if Tx and type(Tx.money) == "function" then return Tx.money(c, "compact") end
  return Kit.money(c)
end

-- the open profession (professionID of the base profession info), nil when unreadable
local function openProfession()
  local api = rawget(_G, "C_TradeSkillUI")
  if type(api) ~= "table" or type(api.GetBaseProfessionInfo) ~= "function" then return nil end
  local ok, info = pcall(api.GetBaseProfessionInfo)
  if not ok then return nil end
  return posInt(field(info, "professionID"))
end
PB.openProfession = openProfession

-- display name of a profession: recipe cache, else the id
local function profName(prof)
  local c = E.cache and E.cache()
  local p = type(c) == "table" and prof and c[prof] or nil
  return (type(p) == "table" and textOf(p.name, 40)) or (prof and ("#" .. tostring(prof))) or "?"
end
PB.profName = profName

-- the recipe chosen in Blizzard's window: from the callback, else read from the schematic form (pcall)
local function selectedRecipe()
  if st.selected then return st.selected end
  local w = window()
  local form = field(field(w, "CraftingPage"), "SchematicForm")
  local info = method(form, "GetRecipeInfo")
  return posInt(field(info, "recipeID"))
end

-- EventRegistry handler: only remembers the id (nothing is drawn inside Blizzard's call). A choice of the player (not the window's
-- own first selection right after opening, not our own OpenRecipe) switches the planning to "Nur dieses Rezept".
local function onRecipeSelected(...)
  for i = 1, select("#", ...) do
    local a = select(i, ...)
    if type(a) == "table" then
      local id = posInt(field(a, "recipeID"))
      if id then
        st.selected = id
        st.dirty = true
        if st.ownPick == id then
          st.ownPick = nil
        elseif now() - (st.openedAt or 0) >= PB.SELECT_QUIET then
          st.pick = "recipe"
        end
        return
      end
    end
  end
end

-- Content (pure data) ----------------------------------------------------------------------------------------------------------------

local function Wk() return ns.Werk end

local function bagCount(id) return E.count(id, false) or 0 end

local function priceOf(id, n)
  local Pr = Journal.Preise
  if not (Pr and n and n > 0) then return nil end
  local total = num((Pr.priceFor(id, n)))
  if total then return total end
  local u = num(Pr.unit(id))
  return u and u * n or nil
end

-- crafts the bags allow for a craft step (nil: reagents unknown)
local function craftable(step)
  local list, known = Wk().reagents(step)
  if not known then return nil end
  local n
  for _, r in ipairs(list) do
    local k = floor(bagCount(r.id) / r.qty)
    n = n and min(n, k) or k
  end
  return n
end
PB.craftable = craftable

-- next-step text of an order status (also the Handwerk page and the hint under the button)
function PB.nextText(s)
  local nx = type(s) == "table" and s.next or nil
  if not nx then return nil end
  if nx.kind == "buy" then return T("buyHint", int(nx.n or 0), textOf(nx.name) or "?") end
  if nx.kind == "mail" then return T.mailHint end
  if nx.kind == "craft" then return T("craftHint", int(nx.n or 0), textOf(nx.name) or "?") end
  if nx.kind == "trainer" then return T("trainerNext", textOf(nx.name) or "?") end
  if nx.kind == "done" then return T.doneLabel end
  return nil
end

-- open orders the workbench of `prof` shows: own profession, or one of its steps belongs to it (precursor in another profession;
-- after that step the button leads back with "Beruf öffnen")
function PB.ordersFor(prof)
  local out = {}
  local K = Wk()
  if not (K and prof) then return out end
  for _, s in ipairs(K.statusAll()) do
    local here = s.w.prof == prof
    if not here then
      for _, st2 in ipairs(s.w.steps or {}) do if st2.prof == prof then here = true break end end
    end
    if s.station ~= "done" and here then out[#out + 1] = s end
  end
  return out
end

-- material lines of a planned order (route.materials format) from Werk.compute
local function linesOf(w)
  local c = Wk().compute(w)
  local out, cost, unpriced = {}, 0, 0
  local ids = {}
  for id, n in pairs(c.need) do if n > 0 then ids[#ids + 1] = id end end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local need = c.need[id]
    local have = bagCount(id)
    local missing = max(0, need - have)
    if missing > 0 then
      local p = priceOf(id, missing)
      if p then cost = cost + p else unpriced = unpriced + 1 end
    end
    out[#out + 1] = { id = id, name = E.itemName(id) or ("#" .. id), need = need, have = min(have, need), missing = missing }
  end
  for id, n in pairs(c.selfMade) do
    if n > 0 then out[#out + 1] = { id = id, name = E.itemName(id) or ("#" .. id), need = n, have = 0, missing = 0, self = n } end
  end
  return out, cost, unpriced, c.unknown
end

local function goalChoice(prof, skill, cap)
  local goals = Route.goals(skill, cap)
  local want = st.goals[prof]
  for _, g in ipairs(goals) do if g.goal == want then return goals, want end end
  for _, g in ipairs(goals) do if g.key == "milestone" then return goals, g.goal end end
  return goals, goals[1] and goals[1].goal or nil
end

-- plan content (mode 1)
local function planContent(c)
  local prof = c.prof
  local goals, goal = goalChoice(prof, c.skill, c.max)
  c.goals, c.goal = goals, goal
  local rid = selectedRecipe()
  c.recipeId = rid
  if st.pick == "recipe" and rid then
    c.single = true
    local pid, rec = E.recipe(prof, rid)
    if not pid then pid, rec = E.recipe(nil, rid) end
    if not (pid and rec) then
      c.state = "loading"
      return c
    end
    local count = max(1, min(st.counts[rid] or 1, E.COUNT_MAX))
    c.count = count
    c.recipeName = textOf(rec.n) or ("#" .. rid)
    c.recipeProf = pid
    local w = Wk().planRecipe(pid, rid, count, st.resolve)
    if not w then
      c.state = "loading"
      return c
    end
    c.plan = w
    c.mats, c.cost, c.unpriced, c.unknown = linesOf(w)
    c.trainerCost = 0
    c.state = "ok"
    c.first = { kind = "craft", recipe = rid, prof = pid, n = count, name = c.recipeName }
    for _, s in ipairs(w.steps) do if s.kind == "craft" then c.first = s break end end
    return c
  end
  c.single = false
  if not goal then
    c.state = "reason"
    c.reason = c.skill and "done" or "nodata"
    return c
  end
  local route = Route.plan(prof, goal, { resolve = st.resolve })
  c.route = route
  c.mats = route.materials or {}
  c.cost, c.unpriced, c.trainerCost = route.cost and route.cost.ah or 0, route.cost and route.cost.unknownPrices or 0,
    route.cost and route.cost.trainer or 0
  c.unknown = route.unknown or {}
  c.reason = route.reason
  c.state = (#(route.steps or {}) > 0) and "ok" or "reason"
  c.first = route.steps and route.steps[1] or nil
  return c
end

-- { mode = "plan" | "make", prof, profName, skill, max, orders, order, ... }
function PB.content()
  local c = { prof = openProfession() }
  if not c.prof then
    local rid = selectedRecipe()
    if rid then c.prof = (E.recipe(nil, rid)) end
  end
  c.profName = profName(c.prof)
  local K = Wk()
  if K and c.prof then c.skill, c.max = K.skill(c.prof) end
  c.orders = PB.ordersFor(c.prof)
  if #c.orders > 0 and st.view ~= "plan" then
    c.mode = "make"
    local idx = 1
    for i, o in ipairs(c.orders) do if o.id == st.orderId then idx = i end end
    c.index, c.order = idx, c.orders[idx]
    return c
  end
  c.mode = "plan"
  if not (K and c.prof) then
    c.state = "pick"
    return c
  end
  return planContent(c)
end

-- cheap signature of everything the bar shows (a redraw only when it changes)
local function signature()
  local prof = openProfession()
  local rid = selectedRecipe()
  local cache = E.cache()
  local p = cache and prof and cache[prof]
  local stamp = type(p) == "table" and tostring(p.at) or "-"
  return table.concat({ tostring(prof), tostring(rid), tostring(st.counts[rid or 0]), tostring(E.gen), stamp, tostring(st.view),
    tostring(st.pick), tostring(st.goals[prof or 0]), tostring(st.resolve), tostring(st.orderId), tostring(st.msg), tostring(st.dirty),
    tostring(inCombat()), tostring(ns.Locale and ns.Locale.active) }, "|")
end

-- Drawing ------------------------------------------------------------------------------------------------------------------------

local function font(parent, kind, size, color, justify) return Kit.font(parent, kind, size, color, justify) end

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end

local function rect(parent, color, layer)
  return W.NewRect(parent, color, color[4] or 1, layer or "ARTWORK")
end

-- goal chip: selected = gold frame and fill
local function chip(parent, h)
  local C = PB.COLORS
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(60, h or 20)
  b.edge = rect(b, C.edge, "BACKGROUND")
  b.edge:SetAllPoints(b)
  b.bg = rect(b, C.bg, "BORDER")
  b.bg:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  b.bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  b.label = font(b, "label", 12, C.text, "CENTER")
  b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.label:SetWordWrap(false)
  function b:SetOn(on)
    self.on = on
    local fill = on and { C.gold[1], C.gold[2], C.gold[3], 0.24 } or C.bg
    self.bg:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
    setColor(self.label, on and C.gold or C.text)
  end
  b:SetScript("OnEnter", function(self)
    if not self.on then self.bg:SetColorTexture(C.btnHover[1], C.btnHover[2], C.btnHover[3], C.btnHover[4]) end
    if self.tipLines then W.tip(self, self.tipLines) end
  end)
  b:SetScript("OnLeave", function(self)
    self:SetOn(self.on)
    W.hideTip(self)
  end)
  b:SetScript("OnClick", function(self) if self.act then safe(self.act, self) end end)
  b:SetOn(false)
  b:Hide()
  return b
end

-- a time line row (route) or a step row (make): marker left, title + range, sub line, optional progress bar
local function lineRow(parent, w)
  local C = PB.COLORS
  local r = CreateFrame("Frame", nil, parent)
  r:SetSize(w, 30)
  r:EnableMouse(true)
  r.hl = rect(r, { C.gold[1], C.gold[2], C.gold[3], 0.10 }, "BACKGROUND")
  r.hl:SetAllPoints(r)
  r.hl:Hide()
  r.ring = rect(r, C.todo, "ARTWORK")
  r.ring:SetSize(14, 14)
  r.ring:SetPoint("TOPLEFT", r, "TOPLEFT", 2, -2)
  r.digit = font(r, "label", 10, C.bg, "CENTER")
  r.digit:SetPoint("CENTER", r.ring, "CENTER", 0, 0)
  r.check = r:CreateTexture(nil, "OVERLAY")
  r.check:SetSize(14, 14)
  r.check:SetPoint("CENTER", r.ring, "CENTER", 0, 0)
  r.check:SetTexture(PB.CHECK)
  r.check:Hide()
  r.line = rect(r, { C.edge[1], C.edge[2], C.edge[3], 0.6 }, "BORDER")
  r.line:SetWidth(1)
  r.line:SetPoint("TOP", r.ring, "BOTTOM", 0, -1)
  r.line:SetPoint("BOTTOM", r, "BOTTOM", 0, 0)
  r.title = font(r, "label", 12, C.text)
  r.title:SetPoint("TOPLEFT", r, "TOPLEFT", 22, -2)
  r.title:SetWidth(w - 22 - 58)
  r.title:SetWordWrap(false)
  r.range = font(r, "label", 11, C.dim, "RIGHT")
  r.range:SetPoint("TOPRIGHT", r, "TOPRIGHT", -2, -3)
  r.range:SetWidth(56)
  r.range:SetWordWrap(false)
  r.sub = font(r, "text", 11, C.dim)
  r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", 22, -18)
  r.sub:SetWidth(w - 24)
  r.sub:SetWordWrap(false)
  r.barBg = rect(r, { 1, 1, 1, 0.08 }, "ARTWORK")
  r.barBg:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 22, 2)
  r.barBg:SetSize(w - 26, 3)
  r.bar = rect(r, C.gold, "OVERLAY")
  r.bar:SetPoint("LEFT", r.barBg, "LEFT", 0, 0)
  r.bar:SetHeight(3)
  r.barBg:Hide() r.bar:Hide()
  r:SetScript("OnEnter", function(self) if self.tipLines then W.tip(self, self.tipLines) end end)
  r:SetScript("OnLeave", function(self) W.hideTip(self) end)
  r:Hide()
  return r
end

-- marker of a row: "done" (check), "current" (gold ring), "todo" (grey ring), "trainer" (gold diamond), or a colour (route stage)
local function marker(r, kind, digit, color)
  local C = PB.COLORS
  r.check:Hide()
  r.digit:SetText("")
  if r.ring.SetRotation then pcall(r.ring.SetRotation, r.ring, 0) end
  r.ring:SetSize(14, 14)
  if kind == "done" then
    r.ring:SetColorTexture(C.ok[1], C.ok[2], C.ok[3], 1)
    r.check:Show()
  elseif kind == "trainer" then
    r.ring:SetSize(10, 10)
    r.ring:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    if r.ring.SetRotation then pcall(r.ring.SetRotation, r.ring, math.pi / 4) end
  elseif kind == "current" or kind == "todo" then
    local c = kind == "current" and C.gold or C.todo
    r.ring:SetColorTexture(c[1], c[2], c[3], 1)
    if digit then r.digit:SetText(tostring(digit)) end
  else
    local c = color or C.todo
    r.ring:SetSize(10, 10)
    r.ring:SetColorTexture(c[1], c[2], c[3], 1)
  end
end

local function itemIcon(id)
  local api = rawget(_G, "C_Item")
  local fn = type(api) == "table" and api.GetItemIconByID or rawget(_G, "GetItemIcon")
  if type(fn) ~= "function" then return nil end
  local ok, icon = pcall(fn, id)
  if not ok or isSecret(icon) then return nil end
  return icon
end

local function matRow(parent, w)
  local C = PB.COLORS
  local r = CreateFrame("Frame", nil, parent)
  r:SetSize(w, 30)
  r:EnableMouse(true)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(20, 20)
  r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
  r.name = font(r, "label", 12, C.text)
  r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 26, -1)
  r.name:SetWidth(w - 26 - 74)
  r.name:SetWordWrap(false)
  r.detail = font(r, "text", 11, C.dim)
  r.detail:SetPoint("TOPLEFT", r, "TOPLEFT", 26, -17)
  r.detail:SetWidth(w - 26 - 74)
  r.detail:SetWordWrap(false)
  r.chipBg = rect(r, { 1, 1, 1, 0.12 }, "BACKGROUND")
  r.chipBg:SetPoint("RIGHT", r, "RIGHT", 0, 0)
  r.chipBg:SetSize(70, 16)
  r.chip = font(r, "label", 11, C.ok, "CENTER")
  r.chip:SetPoint("CENTER", r.chipBg, "CENTER", 0, 0)
  r.chip:SetWidth(68)
  r.chip:SetWordWrap(false)
  r:SetScript("OnEnter", function(self) if self.item then W.tip(self, { self.title or "", item = self.item }) end end)
  r:SetScript("OnLeave", function(self) W.hideTip(self) end)
  r:Hide()
  return r
end

local function build()
  if st.frame then return st.frame end
  local C = PB.COLORS
  local f = CreateFrame("Frame", PB.NAME, UIParent)
  f:SetSize(PB.W, 200)
  f:SetFrameStrata("MEDIUM")
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  if f.SetDontSavePosition then f:SetDontSavePosition(true) end
  f:EnableMouse(true)
  Kit.skin(f)
  f:Hide()
  local inner = PB.W - PB.PAD * 2

  -- every text has a fixed width and does not wrap (cut with "..." by the game) unless it is a hint that may grow downwards
  f.head = font(f, "label", 13, C.gold)
  f.head:SetWidth(inner)
  f.head:SetWordWrap(false)
  f.skill = font(f, "label", 12, C.dim)
  f.skill:SetWidth(inner)
  f.skill:SetWordWrap(false)
  f.skillBg = rect(f, { 1, 1, 1, 0.08 }, "ARTWORK")
  f.skillBg:SetSize(inner, 5)
  f.skillBar = rect(f, C.gold, "OVERLAY")
  f.skillBar:SetHeight(5)
  f.goalBar = rect(f, { C.gold[1], C.gold[2], C.gold[3], 0.35 }, "OVERLAY")
  f.goalBar:SetHeight(5)
  f.chain = Kit.chain(f, inner)

  f.note = font(f, "text", 12, C.dim)
  f.note:SetWidth(inner)
  f.note:SetWordWrap(true)

  -- plan
  f.goalHead = font(f, "text", 13, C.text)
  f.goalHead:SetWidth(inner)
  f.goalHead:SetWordWrap(false)
  f.goalHead:SetText(T.goalHead)
  f.chips = {}
  for i = 1, PB.GOALS_MAX do f.chips[i] = chip(f, 20) end
  f.countLabel = font(f, "label", 12, C.dim)
  f.countLabel:SetWidth(inner - 90)
  f.countLabel:SetWordWrap(false)
  f.minus = Kit.button(f, 20, 18, 14)
  f.minus.label:SetText("-")
  f.minus.act = function() PB.step(-1) end
  f.plus = Kit.button(f, 20, 18, 14)
  f.plus.label:SetText("+")
  f.plus.act = function() PB.step(1) end
  f.countText = font(f, "label", 13, C.text, "CENTER")
  f.countText:SetWidth(40)
  f.routeHead = font(f, "label", 11, C.gold)
  f.routeHead:SetWidth(inner)
  f.routeHead:SetWordWrap(false)
  f.routes = {}
  for i = 1, PB.ROUTE_ROWS do f.routes[i] = lineRow(f, inner) end
  f.routeMore = font(f, "label", 11, C.dim)
  f.routeMore:SetWidth(inner - 22)
  f.routeMore:SetWordWrap(false)
  f.rule = rect(f, { C.edge[1], C.edge[2], C.edge[3], 0.5 }, "ARTWORK")
  f.rule:SetHeight(1)
  f.matHead = font(f, "label", 11, C.gold)
  f.matHead:SetWidth(inner)
  f.matHead:SetWordWrap(false)
  f.mats = {}
  for i = 1, PB.MAT_ROWS do f.mats[i] = matRow(f, inner) end
  f.matMore = font(f, "label", 11, C.dim)
  f.matMore:SetWidth(inner - 26)
  f.matMore:SetWordWrap(false)
  f.resolve = CreateFrame("Button", nil, f)
  f.resolve:SetSize(inner, 18)
  f.resolve.box = rect(f.resolve, C.edge, "ARTWORK")
  f.resolve.box:SetSize(12, 12)
  f.resolve.box:SetPoint("LEFT", f.resolve, "LEFT", 0, 0)
  f.resolve.fill = rect(f.resolve, C.gold, "OVERLAY")
  f.resolve.fill:SetSize(8, 8)
  f.resolve.fill:SetPoint("CENTER", f.resolve.box, "CENTER", 0, 0)
  f.resolve.label = font(f.resolve, "label", 12, C.text)
  f.resolve.label:SetPoint("LEFT", f.resolve, "LEFT", 18, 0)
  f.resolve.label:SetWidth(inner - 18)
  f.resolve.label:SetWordWrap(false)
  f.resolve:SetScript("OnEnter", function(self) W.tip(self, T.resolveTip) end)
  f.resolve:SetScript("OnLeave", function(self) W.hideTip(self) end)
  f.resolve:SetScript("OnClick", function() safe(PB.toggleResolve) end)
  f.unknown = font(f, "text", 11, C.dim)
  f.unknown:SetWidth(inner)
  f.unknown:SetWordWrap(true)
  f.costLabel = font(f, "label", 12, C.dim)
  f.costLabel:SetWidth(PB.COST_LABEL_W)
  f.costLabel:SetWordWrap(false)
  f.cost = font(f, "label", 12, C.gold, "RIGHT")
  f.cost:SetWidth(inner - PB.COST_LABEL_W - PB.COST_GAP)
  f.cost:SetWordWrap(false)
  f.costHint = font(f, "text", 11, C.dim)
  f.costHint:SetWidth(inner)
  f.costHint:SetWordWrap(true)

  -- make
  f.orderOf = font(f, "label", 11, C.dim)
  f.steps = {}
  for i = 1, PB.STEP_ROWS do f.steps[i] = lineRow(f, inner) end
  f.stepMore = font(f, "label", 11, C.dim)
  f.stepMore:SetWidth(inner - 22)
  f.stepMore:SetWordWrap(false)

  -- the one main button, its hint (Kit) and the message
  f.main = Kit.mainButton(f, inner, 30)
  f.main.act = function() PB.main() end
  f.main.hint:SetWordWrap(true) -- the hint may grow downwards; its height decides where the next part starts
  f.msg = font(f, "text", 11, C.ok)
  f.msg:SetWidth(inner)
  f.msg:SetWordWrap(true)
  -- view switch (small, below)
  f.switch = Kit.button(f, floor(inner / 2) - 2, 18, 11)
  f.switch.act = function() PB.switchView() end
  f.nextOrder = Kit.button(f, floor(inner / 2) - 2, 18, 11)
  f.nextOrder.label:SetText(T.nextOrder)
  f.nextOrder.act = function() PB.cycleOrder() end

  st.frame = f
  return f
end

local function textHeight(fs, fallback)
  local ok, h = pcall(fs.GetStringHeight, fs)
  h = ok and num(h) or nil
  if not h or h <= 0 then return fallback end
  return h
end

local function pt(obj, anchor, parent, x, y)
  obj:ClearAllPoints()
  obj:SetPoint(anchor, parent, "TOPLEFT", x, -y)
end

local function colorOf(name)
  local C = PB.COLORS
  if name == "orange" then return C.orange end
  if name == "yellow" then return C.yellow end
  if name == "green" then return C.greenSkill end
  return C.grey
end

local function hideAll(f)
  for _, k in ipairs({ "note", "goalHead", "countLabel", "minus", "plus", "countText", "routeHead", "routeMore", "rule", "matHead",
    "matMore", "resolve", "unknown", "costLabel", "cost", "costHint", "orderOf", "stepMore", "msg", "switch", "nextOrder" }) do
    f[k]:Hide()
  end
  for _, b in ipairs(f.chips) do b:Hide() end
  for _, r in ipairs(f.routes) do r:Hide() r.hl:Hide() r.barBg:Hide() r.bar:Hide() end
  for _, r in ipairs(f.mats) do r:Hide() end
  for _, r in ipairs(f.steps) do r:Hide() r.hl:Hide() r.barBg:Hide() r.bar:Hide() end
end

-- head: title, skill, skill bar with the goal part, chain
local function drawHead(f, c, x, y, inner, station, goal)
  local C = PB.COLORS
  W.setText(f.head, goal and T("headGoal", int(goal)) or T.head)
  pt(f.head, "TOPLEFT", f, x, y)
  if c.skill then
    W.setText(f.skill, T("skillOf", c.profName or "", int(c.skill), int(c.max or c.skill)))
  else
    W.setText(f.skill, c.profName or "")
  end
  pt(f.skill, "TOPLEFT", f, x, y + 17)
  y = y + 34
  pt(f.skillBg, "TOPLEFT", f, x, y)
  local cap = c.max and c.max > 0 and c.max or nil
  local frac = (cap and c.skill) and max(0, min(1, c.skill / cap)) or 0
  f.skillBar:ClearAllPoints()
  f.skillBar:SetPoint("TOPLEFT", f.skillBg, "TOPLEFT", 0, 0)
  f.skillBar:SetWidth(max(1, floor(inner * frac)))
  f.skillBar:SetShown(frac > 0)
  local gfrac = (cap and goal and c.skill) and max(0, min(1, (goal - c.skill) / cap)) or 0
  f.goalBar:ClearAllPoints()
  f.goalBar:SetPoint("TOPLEFT", f.skillBg, "TOPLEFT", floor(inner * frac), 0)
  f.goalBar:SetWidth(max(1, floor(inner * gfrac)))
  f.goalBar:SetShown(gfrac > 0)
  y = y + 12
  pt(f.chain, "TOPLEFT", f, x, y)
  f.chain:SetStation(station)
  return y + 26
end

local function sayLine(f, x, y)
  local C = PB.COLORS
  if not st.msg then return y end
  W.setText(f.msg, st.msg)
  setColor(f.msg, st.msgBad and C.need or C.ok)
  pt(f.msg, "TOPLEFT", f, x, y)
  f.msg:Show()
  return y + textHeight(f.msg, 13) + 6
end

-- the main button: always below the content, its hint right under it
local function drawMain(f, x, y, state)
  pt(f.main, "TOPLEFT", f, x, y)
  f.main:Apply(state)
  f.main:Show()
  y = y + 32
  if state.hint and state.hint ~= "" then y = y + textHeight(f.main.hint, 13) + 4 end
  return y + 4
end

local function stageSub(s)
  if s.unknown or s.known == false then return T.stageUnknown end
  local word = T[s.color or "grey"]
  if s.learned == false then return T("stageNew", word) end
  return T("stageLearned", word)
end

local function drawPlan(f, c, x, y, inner)
  local C = PB.COLORS
  y = drawHead(f, c, x, y, inner, 1, (not c.single) and c.goal or nil)
  -- goal chips
  pt(f.goalHead, "TOPLEFT", f, x, y)
  f.goalHead:Show()
  y = y + 20
  local cx, row = x, 0
  local chips = {}
  for _, g in ipairs(c.goals or {}) do
    chips[#chips + 1] = { label = g.key == "next" and T.goalNext or int(g.goal), on = (not c.single) and g.goal == c.goal,
      tip = g.key == "next" and T.goalNextTip or T.goalTip, act = function() PB.pickGoal(g.goal) end }
  end
  if c.recipeId then
    chips[#chips + 1] = { label = T.goalRecipe, on = c.single == true, tip = T.goalRecipeTip, act = function() PB.pickRecipe() end }
  end
  for i, b in ipairs(f.chips) do
    local d = chips[i]
    if d then
      W.setText(b.label, d.label)
      local tw = 0
      local ok, w2 = pcall(b.label.GetStringWidth, b.label)
      tw = ok and num(w2) or 0
      local bw = max(36, min(inner, floor(tw + 18)))
      if cx > x and cx + bw > x + inner then
        cx, row = x, row + 1
      end
      b:SetSize(bw, 20)
      b.label:SetWidth(bw - 6)
      pt(b, "TOPLEFT", f, cx, y + row * 24)
      b:SetOn(d.on)
      b.tipLines, b.act = d.tip, d.act
      b:Show()
      cx = cx + bw + 6
    end
  end
  y = y + (row + 1) * 24 + 6

  if c.state == "pick" or c.state == "loading" then
    W.setText(f.note, c.state == "loading" and T.loading or T.pick)
    pt(f.note, "TOPLEFT", f, x, y)
    f.note:Show()
    y = y + textHeight(f.note, 14) + 8
    st.action = nil
    y = sayLine(f, x, y)
    return drawMain(f, x, y, Kit.mainState({ label = c.goal and T("create", int(c.goal)) or "", disabled = true, combat = inCombat() }))
  end

  if c.single then
    W.setText(f.countLabel, T.countLabel)
    pt(f.countLabel, "TOPLEFT", f, x, y + 2)
    f.countLabel:Show()
    pt(f.plus, "TOPLEFT", f, x + inner - 20, y - 1)
    pt(f.countText, "TOPLEFT", f, x + inner - 20 - 42, y + 1)
    pt(f.minus, "TOPLEFT", f, x + inner - 20 - 44 - 20, y - 1)
    W.setText(f.countText, int(c.count))
    f.minus.tipLines, f.plus.tipLines = { T.minusTip }, { T.plusTip }
    f.minus:Show() f.plus:Show() f.countText:Show()
    y = y + 24
  else
    W.setText(f.routeHead, T.routeHead)
    pt(f.routeHead, "TOPLEFT", f, x, y)
    f.routeHead:Show()
    y = y + 16
    local shown = {}
    for _, s in ipairs(c.route and c.route.steps or {}) do
      if s.kind == "trainer" or not s.pre then shown[#shown + 1] = s end
    end
    for i, r in ipairs(f.routes) do
      local s = shown[i]
      if s then
        if s.kind == "trainer" then
          marker(r, "trainer")
          W.setText(r.title, T("trainerTitle", textOf(s.name) or "?"))
          setColor(r.title, C.gold)
          W.setText(r.range, T("trainerAt", int(s.at or 0)))
          W.setText(r.sub, T("trainerCost", coins(s.cost)))
        else
          marker(r, "stage", nil, colorOf(s.color))
          local est = (s.chance or 1) < 1 or s.learned == false
          W.setText(r.title, T(est and "stageTitleEst" or "stageTitle", int(s.n), textOf(s.name) or "?"))
          setColor(r.title, C.text)
          W.setText(r.range, T("stageRange", int(s.from or 0), int(s.to or 0)))
          W.setText(r.sub, stageSub(s))
        end
        r.line:SetShown(i < min(#shown, PB.ROUTE_ROWS))
        r:SetHeight(32)
        pt(r, "TOPLEFT", f, x, y)
        r.tipLines = nil
        r:Show()
        y = y + 32
      end
    end
    if #shown > PB.ROUTE_ROWS then
      W.setText(f.routeMore, T("moreStages", int(#shown - PB.ROUTE_ROWS)))
      pt(f.routeMore, "TOPLEFT", f, x + 22, y)
      f.routeMore:Show()
      y = y + 14
    end
    if c.reason and c.reason ~= "done" then
      local reasonText = (c.reason == "nocache" and T.nocache) or (c.reason == "gap" and T("gap", int((c.route and c.route.to) or c.skill or 0)))
        or (c.reason == "limit" and T("limit", int((c.route and c.route.to) or 0))) or T.nodata
      W.setText(f.note, reasonText)
      pt(f.note, "TOPLEFT", f, x, y + 2)
      f.note:Show()
      y = y + textHeight(f.note, 14) + 6
    elseif c.state ~= "ok" then
      W.setText(f.note, c.reason == "done" and T.reached or T.nodata)
      pt(f.note, "TOPLEFT", f, x, y + 2)
      f.note:Show()
      y = y + textHeight(f.note, 14) + 6
    end
  end

  -- materials
  if c.state == "ok" then
    f.rule:ClearAllPoints()
    f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(y + 2))
    f.rule:SetWidth(inner)
    f.rule:Show()
    y = y + 8
    W.setText(f.matHead, c.single and T.matHeadOne or T.matHead)
    pt(f.matHead, "TOPLEFT", f, x, y)
    f.matHead:Show()
    y = y + 16
    local mats = c.mats or {}
    for i, r in ipairs(f.mats) do
      local m = mats[i]
      if m then
        local icon = itemIcon(m.id)
        r.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        W.setText(r.name, T("matName", textOf(m.name) or ("#" .. m.id), int(m.need)))
        local col
        if m.self then
          W.setText(r.detail, T.matSelf)
          W.setText(r.chip, T("chipSelf", int(m.self)))
          col = C.gold
        elseif m.missing > 0 then
          W.setText(r.detail, T("matBags", int(m.have)))
          W.setText(r.chip, T("chipMissing", int(m.missing)))
          col = C.need
        else
          W.setText(r.detail, T("matBags", int(m.have)))
          W.setText(r.chip, T.chipOk)
          col = C.ok
        end
        setColor(r.chip, col)
        r.chipBg:SetColorTexture(col[1], col[2], col[3], 0.15)
        r.item, r.title = "item:" .. tostring(m.id), textOf(m.name)
        pt(r, "TOPLEFT", f, x, y)
        r:Show()
        y = y + 30
      end
    end
    if #mats > PB.MAT_ROWS then
      W.setText(f.matMore, T("moreMats", int(#mats - PB.MAT_ROWS)))
      pt(f.matMore, "TOPLEFT", f, x + 26, y)
      f.matMore:Show()
      y = y + 14
    end
    W.setText(f.resolve.label, T.resolve)
    f.resolve.fill:SetShown(st.resolve == true)
    pt(f.resolve, "TOPLEFT", f, x, y + 2)
    f.resolve:Show()
    y = y + 22
    if c.unknown and #c.unknown > 0 then
      local names = {}
      for i = 1, min(3, #c.unknown) do names[i] = textOf(c.unknown[i]) or "?" end
      W.setText(f.unknown, T("unknownMats", table.concat(names, ", ")))
      pt(f.unknown, "TOPLEFT", f, x, y)
      f.unknown:Show()
      y = y + textHeight(f.unknown, 14) + 6
    end
    -- costs
    W.setText(f.costLabel, T.costLabel)
    pt(f.costLabel, "TOPLEFT", f, x, y + 2)
    f.costLabel:Show()
    local total = (c.cost or 0) + (c.trainerCost or 0)
    local anyMissing = false
    for _, m in ipairs(mats) do if (m.missing or 0) > 0 then anyMissing = true end end
    local unpriced = c.unpriced or 0
    local costHint
    if unpriced > 0 and total <= 0 then
      W.setText(f.cost, "")
      costHint = T.costNone
    else
      W.setText(f.cost, T("costValue", coins(total)))
      if unpriced > 0 then costHint = T("costPrices", int(unpriced)) end
    end
    pt(f.cost, "TOPRIGHT", f, x + inner, y + 2)
    f.cost:Show()
    y = y + 18
    if costHint then
      W.setText(f.costHint, costHint)
      pt(f.costHint, "TOPLEFT", f, x, y)
      f.costHint:Show()
      y = y + textHeight(f.costHint, 13) + 2
    end
    y = y + 4
    y = sayLine(f, x, y)
    -- main button: everything there and the first step can be made here -> "Herstellen"
    local first = c.first
    local ready = not anyMissing and #(c.unknown or {}) == 0 and first and first.kind == "craft"
    local nMake = ready and min(posInt(first.n) or 1, craftable(first) or 0) or 0
    if ready and nMake > 0 then
      st.action = { kind = "create", craft = true }
      return drawMain(f, x, y, Kit.mainState({ label = T("createMake", int(nMake), textOf(first.name) or "?"), hint = T.createMakeHint,
        combat = inCombat() }))
    end
    st.action = { kind = "create" }
    local label = c.single and T("createOne", int(c.count), c.recipeName or "?") or T("create", int(c.goal or 0))
    return drawMain(f, x, y, Kit.mainState({ label = label, hint = T.createHint, combat = inCombat() }))
  end
  st.action = nil
  y = sayLine(f, x, y)
  return drawMain(f, x, y, Kit.mainState({ label = c.goal and T("create", int(c.goal)) or "", disabled = true, combat = inCombat() }))
end

-- remembers the current step of each shown order; a step further = a short message
local function noteProgress(c)
  local K = Wk()
  if not K then return end
  local open = {}
  for _, o in ipairs(c.orders or {}) do open[o.id] = o end
  for id, seen in pairs(st.seen) do
    if not open[id] then
      local _, p = K.get(id)
      if not p and not st.msgLock then st.msg, st.msgBad = T("orderDoneMsg", seen.title or "?"), false end
      st.seen[id] = nil
    end
  end
  for _, o in ipairs(c.orders or {}) do
    local seen = st.seen[o.id]
    local cur = o.cur or 0
    if seen and cur > seen.cur and not st.msgLock then
      local prev = o.steps[seen.cur] and o.steps[seen.cur].step
      if prev and prev.to then
        st.msg = T("stageDoneMsg", int(prev.to))
      else
        st.msg = T("stepDoneMsg", textOf(prev and prev.name) or "?")
      end
      st.msgBad = false
    end
    st.seen[o.id] = { cur = cur, title = textOf(K.titleText(o.w)) }
  end
  st.msgLock = nil
end

local function stepSub(s, row)
  if row.done then return T.stepDone end
  if s.kind == "trainer" then return T("stepTrainerSub", coins(s.cost)) end
  if row.known == false then return T.stepUnknown end
  if row.stuck then return T.stepStuck end
  if s.pre then return T("stepPre", profName(s.prof)) end
  if s.to then return T((s.y and s.to > s.y) and "stepRangeEst" or "stepRange", int(s.from or 0), int(s.to)) end
  return ""
end

local function drawMake(f, c, x, y, inner)
  local C = PB.COLORS
  local o = c.order
  local w = o.w
  y = drawHead(f, c, x, y, inner, o.station, w.goal)
  if #c.orders > 1 then
    W.setText(f.orderOf, T("orderOf", int(c.index), int(#c.orders)) .. " · " .. (textOf(Wk().titleText(w)) or ""))
    pt(f.orderOf, "TOPLEFT", f, x, y)
    f.orderOf:SetWidth(inner)
    f.orderOf:SetWordWrap(false)
    f.orderOf:Show()
    y = y + 16
  elseif not w.goal then
    W.setText(f.orderOf, textOf(Wk().titleText(w)) or "")
    pt(f.orderOf, "TOPLEFT", f, x, y)
    f.orderOf:SetWidth(inner)
    f.orderOf:SetWordWrap(false)
    f.orderOf:Show()
    y = y + 16
  end
  local rows = o.steps or {}
  local cur = o.cur or #rows
  local first = max(1, min(cur - 1, #rows - PB.STEP_ROWS + 1))
  for i, r in ipairs(f.steps) do
    local k = first + i - 1
    local row = rows[k]
    if row then
      local s = row.step
      local isCur = k == cur
      if row.done then marker(r, "done")
      elseif s.kind == "trainer" then marker(r, "trainer")
      else marker(r, isCur and "current" or "todo", k) end
      if s.kind == "trainer" then
        W.setText(r.title, T("stepTrainer", textOf(s.name) or "?"))
      else
        W.setText(r.title, T("stepCraft", int(row.done and (s.n or 0) or (row.left or s.n or 0)), textOf(s.name) or "?"))
      end
      setColor(r.title, row.done and C.dim or (isCur and C.gold or C.text))
      W.setText(r.range, "")
      W.setText(r.sub, stepSub(s, row))
      r.hl:SetShown(isCur)
      r.line:SetShown(false)
      local h = 32
      if isCur and s.kind == "craft" then
        local total = max(1, (row.left or 0) + floor((s.made or 0) / (s.q or 1)))
        local frac = max(0, min(1, 1 - (row.left or 0) / total))
        r.barBg:Show()
        r.bar:SetWidth(max(1, floor((inner - 26) * frac)))
        r.bar:SetShown(frac > 0)
        h = 36
      end
      r:SetHeight(h)
      pt(r, "TOPLEFT", f, x, y)
      r:Show()
      y = y + h + 2
    end
  end
  local hidden = #rows - (first + PB.STEP_ROWS - 1)
  if hidden > 0 then
    W.setText(f.stepMore, T("moreSteps", int(hidden)))
    pt(f.stepMore, "TOPLEFT", f, x + 22, y)
    f.stepMore:Show()
    y = y + 14
  end
  y = y + 4
  y = sayLine(f, x, y)
  -- the main button follows the current step
  local row = rows[cur]
  local s = row and row.step
  local state
  st.action = nil
  if o.station == "done" or not s then
    state = Kit.mainState({ label = T.doneLabel, disabled = true })
  elseif s.kind == "trainer" then
    local LO = Journal.LehrerOrte
    local e = LO and LO.nearest(s.prof or w.prof, { skill = s.at }) or nil
    if e then st.action = { kind = "trainer", prof = s.prof or w.prof, at = s.at } end
    state = Kit.mainState({ label = T.trainer, hint = e and T.trainerHint or T.trainerNone, disabled = e == nil, combat = inCombat() })
  elseif s.prof and c.prof and s.prof ~= c.prof then
    st.action = { kind = "open", recipe = s.recipe, prof = s.prof }
    local pn = profName(s.prof)
    state = Kit.mainState({ label = T("openProf", pn), hint = T("openProfHint", pn), combat = inCombat() })
  else
    local can = craftable(s)
    local n = min(row.left or 1, can or 0)
    if can == nil then
      state = Kit.mainState({ label = T.buyFirst, hint = T.stepUnknown, disabled = true })
    elseif n > 0 then
      st.action = { kind = "craft", recipe = s.recipe, prof = s.prof or w.prof, n = n, name = textOf(s.name) }
      state = Kit.mainState({ label = T("make", int(n), textOf(s.name) or "?"),
        hint = o.station == 2 and T.makePart or T.makeHint, combat = inCombat() })
    elseif o.next and o.next.kind == "mail" then
      state = Kit.mainState({ label = T.mailFirst, hint = T.mailHint, disabled = true })
    else
      state = Kit.mainState({ label = T.buyFirst, hint = PB.nextText(o) or "", disabled = true })
    end
  end
  y = drawMain(f, x, y, state)
  -- switches
  W.setText(f.switch.label, T.newOrder)
  pt(f.switch, "TOPLEFT", f, x, y)
  f.switch:Show()
  if #c.orders > 1 then
    pt(f.nextOrder, "TOPLEFT", f, x + floor(inner / 2) + 2, y)
    f.nextOrder:Show()
  end
  return y + 22
end

-- paints the bar from PB.content(); positions every part from the top (the height follows the content)
local function draw()
  local f = st.frame
  if not f then return end
  local c = PB.content()
  st.content = c
  local x, inner = PB.PAD, PB.W - PB.PAD * 2
  hideAll(f)
  noteProgress(c)
  local y = 10
  if c.mode == "make" then
    y = drawMake(f, c, x, y, inner)
  else
    y = drawPlan(f, c, x, y, inner)
    if #(c.orders or {}) > 0 then
      W.setText(f.switch.label, T.backOrder)
      pt(f.switch, "TOPLEFT", f, x, y)
      f.switch:Show()
      y = y + 22
    end
  end
  f:SetHeight(y + 6)
end

-- Placement (outside combat only) --------------------------------------------------------------------------------------------------------

local function scaleOf(f)
  local v = method(f, "GetEffectiveScale")
  v = num(v)
  return (v and v > 0) and v or nil
end

-- children of a foreign frame (read only), at most `limit`
local function childrenOf(f, limit)
  local fn = field(f, "GetChildren")
  if type(fn) ~= "function" then return {} end
  local ok, t = pcall(function() return { fn(f) } end)
  if not ok or type(t) ~= "table" then return {} end
  local out = {}
  for i = 1, min(#t, limit) do
    if type(t[i]) == "table" and not isSecret(t[i]) then out[#out + 1] = t[i] end
  end
  return out
end

-- Blizzard's vertical profession tabs sit at the window's side edge and stick out of it. Read only: how far shown small frames
-- (up to two levels below the window) protrude to the right / to the left of the window within the bar's vertical range
-- (window units; l, b, ww = rectangle of the window, barH = height of the bar). -> right, left
local function protrusion(w, ew, l, b, ww, barH)
  local right, left = 0, 0
  local budget = PB.SCAN_MAX
  local function visit(f, depth)
    for _, c in ipairs(childrenOf(f, budget)) do
      if budget <= 0 then return end
      budget = budget - 1
      if method(c, "IsShown") == true then
        local cl, cb, cw, ch = method(c, "GetRect")
        cl, cb, cw, ch = num(cl), num(cb), num(cw), num(ch)
        if cl and cb and cw and ch and cw > 0 and ch > 0 then
          local k = (scaleOf(c) or ew) / ew
          cl, cb, cw, ch = cl * k, cb * k, cw * k, ch * k
          local cr = cl + cw
          if cw <= PB.TAB_MAX_W and cb < b + barH and cb + ch > b then
            if cr > l + ww + 1 and cl >= l + ww - PB.TAB_EDGE then right = max(right, cr - (l + ww)) end
            if cl < l - 1 and cr <= l + PB.TAB_EDGE then left = max(left, l - cl) end
          end
        end
        if depth < 2 then visit(c, depth + 1) end
      end
    end
  end
  visit(w, 1)
  return right, left
end

-- anchors the bar to the window: bottom aligned right of it (clear of the tab column), or left when the screen edge leaves no
-- room; scale follows the window
local function place()
  local f, w = st.frame, window()
  if not (f and w) or inCombat() then return false end
  local sw = UIParent and num(method(UIParent, "GetWidth")) or nil
  local ew, eu = scaleOf(w), UIParent and scaleOf(UIParent) or nil
  local k = (ew and eu) and max(0.5, min(2, ew / eu)) or 1
  local l, b, ww = method(w, "GetRect")
  l, b, ww = num(l), num(b), num(ww)
  local barH = num(f:GetHeight()) or 0
  local extraR, extraL = 0, 0
  if l and b and ww then extraR, extraL = protrusion(w, ew or 1, l, b, ww, barH) end
  local side = "right"
  if l and ww and sw and sw > 0 then
    local r = (l + ww + extraR) * k
    if r + PB.GAP + PB.W * k > sw and (l - extraL) * k - PB.GAP - PB.W * k >= 0 then side = "left" end
  end
  local sig = table.concat({ side, tostring(k), tostring(l), tostring(ww), tostring(sw), tostring(extraR), tostring(extraL),
    tostring(barH) }, "|")
  if sig == st.placeSig and st.anchored then return true end
  st.placeSig = sig
  f:SetScale(k)
  f:ClearAllPoints()
  if side == "right" then
    f:SetPoint("BOTTOMLEFT", w, "BOTTOMRIGHT", PB.GAP + extraR, 0)
  else
    f:SetPoint("BOTTOMRIGHT", w, "BOTTOMLEFT", -(PB.GAP + extraL), 0)
  end
  st.anchored, st.side = true, side
  return true
end

local function hideBar()
  local f = st.frame
  if not f then return end
  pcall(f.Hide, f)
  if f.SetAlpha then pcall(f.SetAlpha, f, 0) end
  for _, row in ipairs(f.mats) do W.hideTip(row) end
  for _, row in ipairs(f.routes) do W.hideTip(row) end
  for _, row in ipairs(f.steps) do W.hideTip(row) end
  for _, b in ipairs(f.chips) do W.hideTip(b) end
  W.hideTip(f.main)
end

-- Update: the one place where visibility, placement and content come together ------------------------------------------------------------

-- force: redraw even if nothing changed
function PB.update(force)
  if not (PB.enabled() and windowShown()) then
    hideBar()
    return false
  end
  if not st.frame then
    if inCombat() then
      st.wantBuild = true -- built after combat (PLAYER_REGEN_ENABLED)
      return false
    end
    build()
    force = true
  end
  local f = st.frame
  local wasHidden = not (f:IsShown() == true) or (f.GetAlpha and f:GetAlpha() == 0)
  if inCombat() and not st.anchored then
    return false -- never placed yet: wait for the end of combat, show nothing at a wrong place
  end
  local sig = signature()
  if force or wasHidden or sig ~= st.sig then
    st.sig, st.dirty = sig, false
    draw()
    st.sig = signature()
  end
  if not inCombat() then place() end -- after drawing: the bar's height decides which tabs it could touch
  if wasHidden then
    if f.SetAlpha then f:SetAlpha(1) end
    f:Show()
  end
  return true
end

-- Actions (all from a click of our own buttons) ---------------------------------------------------------------------------------

local function say(text, bad)
  st.msg, st.msgBad = text, bad and true or false
  st.msgLock = true -- the progress note of the next draw does not overwrite this
end

function PB.pickGoal(goal)
  local c = st.content
  if not (c and c.prof and posInt(goal)) then return false end
  st.goals[c.prof] = posInt(goal)
  st.pick = "goal"
  say(nil)
  PB.update(true)
  return true
end

function PB.pickRecipe()
  st.pick = "recipe"
  say(nil)
  PB.update(true)
  return true
end

function PB.toggleResolve()
  st.resolve = not st.resolve
  say(nil)
  PB.update(true)
  return st.resolve
end

function PB.step(dir)
  local c = st.content
  if not (c and c.single and c.recipeId) then return false end
  local stepBy = (type(IsShiftKeyDown) == "function" and IsShiftKeyDown()) and 10 or 1
  local n = max(1, min((c.count or 1) + dir * stepBy, E.COUNT_MAX))
  st.counts[c.recipeId] = n
  say(nil)
  PB.update(true)
  return true
end

function PB.switchView()
  local c = st.content
  if c and c.mode == "make" then st.view = "plan" else st.view = nil end
  say(nil)
  PB.update(true)
  return true
end

-- the facade (journal/Werkauftrag.lua): while the profession window shows the workbench of order `id`, the bar switches to it
-- (mode "Herstellen") -> true; otherwise false (the facade then says where the order goes on)
function PB.focus(id)
  id = posInt(id)
  if not (id and PB.enabled() and windowShown()) then return false end
  local prof = openProfession()
  if not prof then return false end
  for _, o in ipairs(PB.ordersFor(prof)) do
    if o.id == id then
      st.orderId, st.view = id, nil
      say(nil)
      PB.update(true)
      return true
    end
  end
  return false
end

function PB.cycleOrder()
  local c = st.content
  if not (c and c.orders and #c.orders > 1) then return false end
  local i = (c.index or 1) % #c.orders + 1
  st.orderId = c.orders[i].id
  say(nil)
  PB.update(true)
  return true
end

-- choosing a recipe in Blizzard's window: only through an unprotected API, from a click, outside combat; if the game blocks the call
-- once (error or ADDON_ACTION_BLOCKED in Core.actionLog) it is not tried again in this session
PB.openBlocked = false
PB.craftBlocked = false

local function actionTotal()
  local log = ns.Core and ns.Core.actionLog
  return log and num(log.total) or 0
end

function PB.canOpenRecipe()
  local api = rawget(_G, "C_TradeSkillUI")
  return not PB.openBlocked and type(api) == "table" and type(api.OpenRecipe) == "function"
end

function PB.chooseRecipe(recipeID)
  recipeID = posInt(recipeID)
  if not recipeID or inCombat() or not PB.canOpenRecipe() then return false end
  local before = actionTotal()
  st.ownPick = recipeID
  local ok = pcall(C_TradeSkillUI.OpenRecipe, recipeID)
  if not ok or actionTotal() > before then
    PB.openBlocked = true
    st.ownPick = nil
    return false
  end
  st.selected = recipeID
  st.dirty = true
  return true
end

-- the step lies in another profession: OpenRecipe switches the window and chooses the recipe, else OpenTradeSkill(prof)
local function openStep(a)
  if inCombat() then return false end
  if PB.chooseRecipe(a.recipe) then return true end
  local api = rawget(_G, "C_TradeSkillUI")
  if type(api) == "table" and type(api.OpenTradeSkill) == "function" and posInt(a.prof) then
    local before = actionTotal()
    local ok = pcall(api.OpenTradeSkill, posInt(a.prof))
    if ok and actionTotal() <= before then return true end
  end
  return false
end

-- CraftRecipe from this click; blocked -> only choose the recipe (fallback) and say why
local function craft(a)
  if inCombat() then return false end
  local api = rawget(_G, "C_TradeSkillUI")
  if type(api) ~= "table" or type(api.CraftRecipe) ~= "function" then
    say(T.noApi, true)
    return false
  end
  if openProfession() ~= posInt(a.prof) then return openStep(a) end
  if not PB.craftBlocked then
    local before = actionTotal()
    local ok = pcall(api.CraftRecipe, posInt(a.recipe), posInt(a.n) or 1)
    if ok and actionTotal() <= before then
      say(T("crafting", int(a.n or 1), a.name or "?"))
      return true
    end
    PB.craftBlocked = true
  end
  PB.chooseRecipe(a.recipe)
  say(T.blocked, true)
  return false
end

local function trainer(a)
  local LO, WP = Journal.LehrerOrte, Journal.Waypoint
  if not (LO and WP) then return false end
  local e = LO.nearest(a.prof, { skill = a.at })
  if not e then
    say(T.trainerNone, true)
    return false
  end
  local ok, why = WP.set(e.mapID, e.x, e.y)
  if ok then
    say(WP.TEXT("set", textOf(e.name) or "?"))
  else
    say(WP.reasonText(why), true)
  end
  return ok == true
end

local function create(a)
  local c = st.content
  local K = Wk()
  if not (c and K and c.mode == "plan") then return false end
  local id, how
  if c.single then
    id, how = K.addRecipe(c.recipeProf or c.prof, c.recipeId, c.count, st.resolve)
  else
    id, how = K.addRoute(c.route)
  end
  if not id then
    say(K.reasonText(how, c.single and nil or "route") or "", true)
    PB.update(true)
    return false
  end
  st.view, st.orderId, st.pick = nil, id, "goal"
  local s = K.status(id)
  st.seen[id] = s and { cur = s.cur or 0, title = textOf(K.titleText(s.w)) } or nil
  if how == "update" then say(T.changed)
  elseif s and s.station == 3 then say(T.savedReady)
  else say(T.saved) end
  if a.craft and s and s.next and s.next.kind == "craft" then
    local step = s.next.step
    local can = craftable(step) or 0
    local n = min(s.next.n or 1, can)
    if n > 0 then craft({ recipe = step.recipe, prof = step.prof or c.prof, n = n, name = textOf(step.name) }) end
  end
  return true
end

-- the one main button (OnClick only)
function PB.main()
  local a = st.action
  if not a or inCombat() then return false end
  local ok
  if a.kind == "create" then ok = create(a)
  elseif a.kind == "craft" then ok = craft(a)
  elseif a.kind == "open" then ok = openStep(a)
  elseif a.kind == "trainer" then ok = trainer(a) end
  st.dirty = true
  PB.update(true)
  return ok == true
end

-- Events and poll --------------------------------------------------------------------------------------------------------------------

local function startPoll()
  st.graceUntil = now() + PB.GRACE
  st.poll = 0
  if st.pollFrame then st.pollFrame:Show() end
end

local function onPoll(_, dt)
  st.poll = st.poll + (num(dt) or 0)
  if st.poll < PB.POLL then return end
  st.poll = 0
  if not PB.enabled() then
    PB.update()
    st.pollFrame:Hide()
    return
  end
  PB.update()
  if not windowShown() and now() > (st.graceUntil or 0) then st.pollFrame:Hide() end
end

local function onEvent(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= "Blizzard_Professions" then return end
    PB.register()
    if st.open then startPoll() end
  elseif event == "TRADE_SKILL_SHOW" then
    if not st.open then st.openedAt = now() end
    st.open = true
    PB.register()
    startPoll()
    PB.update()
  elseif event == "TRADE_SKILL_CLOSE" then
    st.open, st.selected, st.msg, st.view, st.pick, st.ownPick = false, nil, nil, nil, nil, nil
    hideBar()
  elseif event == "PLAYER_REGEN_ENABLED" then
    st.dirty = true
    if st.wantBuild or st.open then
      st.wantBuild = false
      PB.update()
    end
  elseif event == "PLAYER_REGEN_DISABLED" then
    st.dirty = true
    if st.open then PB.update() end
  elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    PB.register()
  else
    st.dirty = true -- bags, skill, money, recipes
  end
end

-- EventRegistry callback (own owner), once; the registry exists from the start, the event name needs no loaded addon
function PB.register()
  if st.registered then return true end
  local ER = rawget(_G, "EventRegistry")
  if type(ER) ~= "table" or type(ER.RegisterCallback) ~= "function" then return false end
  st.owner = st.owner or {}
  local ok = pcall(ER.RegisterCallback, ER, PB.EVENT, onRecipeSelected, st.owner)
  st.registered = ok
  return ok
end

local function init()
  if type(CreateFrame) ~= "function" then return end
  local ok, ev = pcall(CreateFrame, "Frame")
  if not (ok and type(ev) == "table") then return end
  st.events = ev
  for _, name in ipairs({ "ADDON_LOADED", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE", "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED", "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "SKILL_LINES_CHANGED", "NEW_RECIPE_LEARNED", "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD" }) do
    pcall(ev.RegisterEvent, ev, name)
  end
  ev:SetScript("OnEvent", function(self, event, arg1) safe(onEvent, self, event, arg1) end)
  -- poll frame: hidden (so without any OnUpdate) while no profession window is open
  local pf = CreateFrame("Frame")
  pf:SetScript("OnUpdate", function(self, dt) safe(onPoll, self, dt) end)
  pf:Hide()
  st.pollFrame = pf
  local P = ns.Plans
  if P and type(P.onChange) == "function" then P.onChange(function() st.dirty = true end) end
  PB.register()
end

init()
