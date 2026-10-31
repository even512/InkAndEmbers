-- Journal access: /chronik, minimap button (own code, no library), addon compartment, key binding.
-- Never opens in combat.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Access = {}
Journal.Access = Access

Access.TEXT = ns.Locale.ns("Access", {
  combat = "Das Reisejournal öffnet sich nicht im Kampf.",
  minimapOff = "Minimap-Knopf ausgeblendet. /chronik minimap blendet ihn wieder ein.",
  minimapOn = "Minimap-Knopf eingeblendet.",
  tooltip = "Reisejournal",
  tooltipHint = "Klick: öffnen/schließen · Rechtsklick: Einstellungen · Ziehen: verschieben",
  bindingToggle = "Reisejournal öffnen/schließen",
  resetDone = "Reisejournal: zurückgesetzt.",
  perf = "Reisejournal: zuletzt geöffnet in %d ms (Fensteraufbau %d ms, Zeichnen %d ms; Richtwert unter 200 ms).",
  perfWaited = " Enthält Wartezeit auf den Kern.",
})

local function setBindingNames()
  BINDING_HEADER_EVENCHRONICLE = "Forever Chronicle"
  BINDING_NAME_EVENCHRONICLE_TOGGLE = Access.TEXT.bindingToggle
end
setBindingNames()
if ns.Core and type(ns.Core.on) == "function" then ns.Core.on("ADDON_LOADED", setBindingNames) end

local function print(msg)
  if ns.Core and ns.Core.print then ns.Core.print(msg) end
end

function Access.isOpen()
  local F = Journal.Frame
  return F and F.state.frame ~= nil and F.state.frame:IsShown() and true or false
end

function Access.open()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    print(Access.TEXT.combat)
    return false
  end
  local F = Journal.Frame
  local t0 = F.clock()
  local f = F.build()
  F.beginOpen(t0)
  f:Show()
  return true
end

function Access.perfLine()
  local F = Journal.Frame
  local p = F and F.state.perf
  if not p or not p.open then return nil end
  local line = Access.TEXT("perf",
    math.floor(p.open + 0.5), math.floor((p.build or 0) + 0.5), math.floor((p.render or 0) + 0.5))
  if p.waited then line = line .. Access.TEXT.perfWaited end
  return line
end

function Access.close()
  local F = Journal.Frame
  if F and F.state.frame then F.state.frame:Hide() end
end

function Access.reset()
  local F = Journal.Frame
  if F and F.resetLayout then F.resetLayout() end
  print(F and F.TEXT and F.TEXT.reset or Access.TEXT.resetDone)
  return true
end

function Access.toggle()
  if Access.isOpen() then
    Access.close()
    return false
  end
  return Access.open()
end

function EveNChronicle_ToggleJournal()
  if ns.Core then ns.Core.safe(Access.toggle) else Access.toggle() end
end

function EveNChronicle_OnAddonCompartmentClick()
  EveNChronicle_ToggleJournal()
end

Access.MINIMAP_RADIUS_PAD = 10
Access.MINIMAP_SIZE = 34
Access.MINIMAP_GLOW = 0.4

function Access.minimapOffset(angle, radius)
  local r = math.rad(angle or 225)
  return math.cos(r) * radius, math.sin(r) * radius
end

function Access.angleFrom(dx, dy)
  local a = math.deg(math.atan2 and math.atan2(dy, dx) or math.atan(dy, dx))
  return a % 360
end

local function placeButton(b)
  local mm = Minimap
  local w = (mm and mm.GetWidth and mm:GetWidth()) or 140
  local x, y = Access.minimapOffset(Access.angle or 225, w / 2 + Access.MINIMAP_RADIUS_PAD)
  b:ClearAllPoints()
  b:SetPoint("CENTER", mm, "CENTER", x, y)
end

function Access.createMinimapButton()
  if Access.button or type(Minimap) ~= "table" then return Access.button end
  local Theme, View = Journal.Theme, Journal.View
  local b = CreateFrame("Button", "EveNChronicleMinimapButton", Minimap)
  b:SetSize(Access.MINIMAP_SIZE, Access.MINIMAP_SIZE)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(Theme.TEX.minimap)
  icon:SetAllPoints(b)
  local glow = b:CreateTexture(nil, "HIGHLIGHT")
  glow:SetTexture(Theme.TEX.minimap)
  glow:SetAllPoints(b)
  glow:SetBlendMode("ADD")
  glow:SetAlpha(Access.MINIMAP_GLOW)
  b.icon, b.glow = icon, glow
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then Access.openSettings() else EveNChronicle_ToggleJournal() end
  end)
  b:SetScript("OnEnter", function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine(Access.TEXT.tooltip, 1, 0.82, 0)
      GameTooltip:AddLine(Access.TEXT.tooltipHint, 0.8, 0.8, 0.8)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local s = Minimap:GetEffectiveScale() or 1
      local cx, cy = GetCursorPosition()
      if mx and my and cx and cy and s > 0 then
        Access.angle = Access.angleFrom(cx / s - mx, cy / s - my)
        placeButton(self)
      end
    end)
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    if Access.angle then View.set("minimapAngle", Access.angle) end
  end)
  Access.button = b
  Access.angle = View.peek("minimapAngle")
  placeButton(b)
  return b
end

function Access.openSettings()
  local O = Journal.Options
  return O and type(O.open) == "function" and O.open() and true or false
end

function Access.setMinimap(on)
  local View = Journal.View
  View.set("minimap", on and true or false)
  if on then
    local b = Access.createMinimapButton()
    if b then b:Show() end
  elseif Access.button then
    Access.button:Hide()
  end
end

function Access.toggleMinimap()
  local on = not Journal.View.peek("minimap")
  Access.setMinimap(on)
  print(on and Access.TEXT.minimapOn or Access.TEXT.minimapOff)
  return on
end

local loginDone = false
if ns.Core and ns.Core.on then
  ns.Core.on("PLAYER_ENTERING_WORLD", function()
    if loginDone then return end
    loginDone = true
    if Journal.View.peek("minimap") then Access.createMinimapButton() end
    Journal.View.prepareAfterLogin(Journal.View.PREPARE_DELAY)
  end)
  ns.Core.on("PLAYER_REGEN_ENABLED", function()
    Journal.View.combatEnded()
  end)
end
