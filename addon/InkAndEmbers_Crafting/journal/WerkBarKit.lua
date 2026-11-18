-- WerkBarKit (Werkauftrag): shared building blocks of the two bars (profession window: journal/ProfessionBar.lua, auction house:
-- journal/AuctionDock.lua). Look of the design: dark plate #0B0D11 with a bronze edge, gold text #E8C77A, the main button red
-- #7A1A10 (one per place), "Bestätigen" green. Only own frames; nothing here touches a Blizzard frame, nothing is built in combat.
--   Kit.COLORS, Kit.font(parent, kind, size, color, justify), Kit.skin(frame), Kit.button(parent, w, h, size) (flat text button)
--   Kit.mainButton(parent, w, h)  -> button; button:Apply(state) with a state of Kit.mainState
--   Kit.mainState(o) (pure)       -> { enabled, label, hint, color = "red" | "green" | "off" }
--       o = { label, confirm (green), combat, cost (copper), money (copper), busy, disabled, hint }
--       order: combat ("Nach dem Kampf") > busy > gold ("Euch fehlen X") > disabled > ready
--   Kit.chain(parent)             -> frame with the three stations; chain:SetStation(station) (1 | 2 | 3 | "done")
--   Kit.chainState(station) (pure)-> { { key, label, state = "done" | "current" | "todo" } x3 }
--   Kit.inCombat(), Kit.money(copper) (coin text), Kit.TEXT
-- The station numbers are drawn as small rings with a digit (the circled digits are not in the game fonts).
local _, ns = ...

local Journal = ns.Journal
local W = Journal and Journal.Widgets
if not (Journal and W) then return end

local floor = math.floor

local Kit = {}
Journal.WerkBarKit = Kit

Kit.COLORS = {
  bg = { 0.043, 0.051, 0.067, 0.94 },        -- #0B0D11
  edge = { 0.62, 0.47, 0.27, 0.85 },         -- bronze
  gold = { 0.91, 0.78, 0.48 },               -- #E8C77A
  text = { 0.96, 0.93, 0.85 }, dim = { 0.74, 0.70, 0.62 },
  need = { 0.96, 0.62, 0.50 }, ok = { 0.62, 0.84, 0.52 },
  red = { 0.478, 0.102, 0.063, 1 },          -- #7A1A10
  redHover = { 0.60, 0.15, 0.09, 1 },
  green = { 0.20, 0.42, 0.20, 1 }, greenHover = { 0.26, 0.52, 0.26, 1 },
  off = { 0.25, 0.24, 0.22, 1 },
  btn = { 0.91, 0.78, 0.48, 0.20 }, btnHover = { 0.91, 0.78, 0.48, 0.38 },
  todo = { 0.45, 0.42, 0.36 },
  orange = { 0.95, 0.55, 0.16 }, yellow = { 0.96, 0.86, 0.28 }, greenSkill = { 0.45, 0.78, 0.35 }, grey = { 0.55, 0.55, 0.55 },
}

local T = ns.Locale.ns("WerkBarKit", {
  stepPlan = "Planen",
  stepBuy = "Einkaufen",
  stepMake = "Herstellen",
  afterCombat = "Nach dem Kampf",
  goldShort = "Euch fehlen %s",
  busy = "Einen Moment …",
})
Kit.TEXT = T

-- areas of the stages W2-W4 (texts in locales/<lang>_werkbar|_werkdock|_werkplan.lua), registered empty here so every language file
-- has its German original from the start; each stage fills its area with ns.Locale.ns("<area>", { ... }) in its own file
Kit.AREAS = { bar = "WerkBar", dock = "WerkDock", plan = "WerkPlan" }
for _, area in pairs(Kit.AREAS) do ns.Locale.ns(area, {}) end

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

function Kit.inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, r = pcall(InCombatLockdown)
  return not ok or r == true
end

function Kit.money(copper)
  local Tx = Journal.Texts
  if Tx and type(Tx.money) == "function" then return Tx.money(copper) end
  return tostring(copper)
end

-- Pure states ----------------------------------------------------------------------------------------------------------------------

function Kit.mainState(o)
  o = type(o) == "table" and o or {}
  local label = type(o.label) == "string" and o.label or ""
  local color = o.confirm and "green" or "red"
  if o.combat then return { enabled = false, label = label, hint = T.afterCombat, color = "off", why = "combat" } end
  if o.busy then return { enabled = false, label = label, hint = T.busy, color = "off", why = "busy" } end
  local cost, money = num(o.cost), num(o.money)
  if cost and money and cost > money then
    return { enabled = false, label = label, hint = T("goldShort", Kit.money(floor(cost - money))), color = "off", why = "gold",
      short = floor(cost - money) }
  end
  if o.disabled then return { enabled = false, label = label, hint = o.hint, color = "off", why = "disabled" } end
  return { enabled = true, label = label, hint = o.hint, color = color }
end

local KEYS = { { "plan", "stepPlan" }, { "buy", "stepBuy" }, { "make", "stepMake" } }

function Kit.chainState(station)
  local cur = station == "done" and 4 or num(station) or 1
  local out = {}
  for i, k in ipairs(KEYS) do
    out[i] = { key = k[1], label = T[k[2]], index = i, state = (i < cur and "done") or (i == cur and "current") or "todo" }
  end
  return out
end

-- Drawing ----------------------------------------------------------------------------------------------------------------------------

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end

function Kit.font(parent, kind, size, color, justify)
  local fs = W.font(parent, kind or "text", size or 12, color or Kit.COLORS.text)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

function Kit.skin(f)
  local C, Theme = Kit.COLORS, Journal.Theme
  if f.kitSkin then return f end
  if Theme and Theme.roundRect then
    f.kitEdge = Theme.roundRect(f, { 1, 1, 1 }, 1, 6, "BACKGROUND", Theme.TEX and Theme.TEX.ring)
    f.kitEdge.color(C.edge, C.edge[4])
    f.kitPlate = Theme.roundRect(f, { 1, 1, 1 }, 1, 6, "BACKGROUND")
    f.kitPlate.color(C.bg, C.bg[4])
  else
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    f.kitPlate = bg
  end
  f.kitSkin = true
  return f
end

local function safe(fn, ...)
  local Core = ns.Core
  if Core and type(Core.safe) == "function" then return Core.safe(fn, ...) end
  return pcall(fn, ...)
end

function Kit.button(parent, w, h, size)
  local C = Kit.COLORS
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b.bg = W.NewRect(b, C.btn, C.btn[4], "BACKGROUND")
  b.bg:SetAllPoints(b)
  b.label = Kit.font(b, "label", size or 12, C.text, "CENTER")
  b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.label:SetWidth(w - 6)
  b.label:SetWordWrap(false)
  b:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(C.btnHover[1], C.btnHover[2], C.btnHover[3], C.btnHover[4])
    if self.tipLines then W.tip(self, self.tipLines) end
  end)
  b:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(C.btn[1], C.btn[2], C.btn[3], C.btn[4])
    W.hideTip(self)
  end)
  b:SetScript("OnClick", function(self) if self.act then safe(self.act, self) end end)
  return b
end

local function fill(b, hover)
  local C = Kit.COLORS
  local key = b.kitColor or "red"
  local c = (key == "green" and (hover and C.greenHover or C.green)) or (key == "off" and C.off) or (hover and C.redHover or C.red)
  b.bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

-- the one main button of a place: always at the same spot; :Apply(Kit.mainState(...)); the hint line sits below it
function Kit.mainButton(parent, w, h)
  local C = Kit.COLORS
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h or 26)
  b.bg = W.NewRect(b, C.red, 1, "BACKGROUND")
  b.bg:SetAllPoints(b)
  b.label = Kit.font(b, "label", 13, C.gold, "CENTER")
  b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.label:SetWidth(w - 8)
  b.label:SetWordWrap(false)
  b.hint = Kit.font(parent, "text", 11, C.dim, "CENTER")
  b.hint:SetPoint("TOP", b, "BOTTOM", 0, -3)
  b.hint:SetWidth(w)
  b.kitColor, b.kitEnabled = "red", true
  b:SetScript("OnEnter", function(self)
    if self.kitEnabled then fill(self, true) end
    if self.tipLines then W.tip(self, self.tipLines) end
  end)
  b:SetScript("OnLeave", function(self)
    fill(self, false)
    W.hideTip(self)
  end)
  b:SetScript("OnClick", function(self)
    if self.kitEnabled and self.act then safe(self.act, self) end
  end)
  function b:Apply(state)
    state = type(state) == "table" and state or Kit.mainState({})
    self.kitColor, self.kitEnabled = state.color or "red", state.enabled == true
    W.setText(self.label, state.label or "")
    setColor(self.label, self.kitEnabled and C.gold or C.dim)
    if state.hint and state.hint ~= "" then
      W.setText(self.hint, state.hint)
      self.hint:Show()
    else
      self.hint:SetText("")
      self.hint:Hide()
    end
    fill(self, false)
  end
  b:Apply(Kit.mainState({}))
  return b
end

-- chain of the three stations (ring with digit + label, a thin line between)
function Kit.chain(parent, w)
  local C = Kit.COLORS
  local f = CreateFrame("Frame", nil, parent)
  w = w or 210
  f:SetSize(w, 18)
  f.nodes = {}
  local step = w / 3
  for i = 1, 3 do
    local n = CreateFrame("Frame", nil, f)
    n:SetSize(step, 18)
    n:SetPoint("LEFT", f, "LEFT", (i - 1) * step, 0)
    n.ring = W.NewRect(n, C.todo, 1, "ARTWORK")
    n.ring:SetSize(14, 14)
    n.ring:SetPoint("LEFT", n, "LEFT", 0, 0)
    n.digit = Kit.font(n, "label", 10, C.bg, "CENTER")
    n.digit:SetPoint("CENTER", n.ring, "CENTER", 0, 0)
    n.digit:SetText(tostring(i))
    n.label = Kit.font(n, "label", 11, C.dim)
    n.label:SetPoint("LEFT", n.ring, "RIGHT", 4, 0)
    if i < 3 then
      n.line = W.NewRect(n, C.edge, 0.6, "BORDER")
      n.line:SetHeight(1)
      n.line:SetPoint("LEFT", n.label, "RIGHT", 4, 0)
      n.line:SetPoint("RIGHT", n, "RIGHT", -4, 0)
    end
    f.nodes[i] = n
  end
  function f:SetStation(station)
    for i, s in ipairs(Kit.chainState(station)) do
      local n = self.nodes[i]
      local c = (s.state == "done" and C.ok) or (s.state == "current" and C.gold) or C.todo
      n.ring:SetColorTexture(c[1], c[2], c[3], 1)
      W.setText(n.label, s.label)
      setColor(n.label, s.state == "todo" and C.dim or C.text)
    end
  end
  f:SetStation(1)
  return f
end
