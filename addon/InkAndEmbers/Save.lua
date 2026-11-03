-- Save reminder: small non-modal frame, no sound, no focus.
-- ReloadUI is only called from the button's OnClick (needs a hardware event).
local _, ns = ...

local Save = {}
ns.Save = Save

local floor = math.floor

local T = ns.Locale.ns("Save", {
  prompt = "Reise sichern? Letzte Sicherung vor %d min.",
  save = "Sichern",
  later = "Später",
})

Save.INTERVAL = 1800 -- seconds without a save before prompting (WoW only writes the saved variables on logout/reload)
Save.SNOOZE = 1800
Save.TICK = 30
-- extra occasions (takeoff of a flight, level-up): only when the last save is at least MIN_AGE ago and the window was
-- not shown within MIN_GAP seconds; in combat/instances the request waits at most PENDING_FOR seconds
Save.MIN_AGE = 600
Save.MIN_GAP = 600
Save.PENDING_FOR = 120
Save.TAKEOFF_DELAY = 2

local function minutesSinceSave()
  local last = Save.lastSave or (ns.Store and ns.Store.loginAt) or time()
  return floor(math.max(0, time() - last) / 60)
end

-- no prompt during combat or in an instance
function Save.blocked()
  if InCombatLockdown() then return true end
  if IsInInstance() then return true end
  return false
end

function Save.refresh()
  if Save.text then
    Save.text:SetText(T("prompt", minutesSinceSave()))
  end
end

local function build()
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetSize(270, 74)
  f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -220)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.8)
  end

  local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12)
  text:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -12)
  text:SetJustifyH("LEFT")

  local saveButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  saveButton:SetSize(110, 22)
  saveButton:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
  saveButton:SetText(T.save)
  saveButton:SetScript("OnClick", function()
    if ns.Store then ns.Store.markReload() end
    ReloadUI()
  end)

  local laterButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  laterButton:SetSize(110, 22)
  laterButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
  laterButton:SetText(T.later)
  laterButton:SetScript("OnClick", function() Save.later() end)

  f:Hide()
  Save.frame, Save.text, Save.saveButton, Save.laterButton = f, text, saveButton, laterButton
end

function Save.isShown()
  return Save.frame ~= nil and Save.frame:IsShown() and true or false
end

function Save.show()
  if not Save.frame then build() end
  Save.lastShown = time()
  Save.pendingUntil = nil
  Save.refresh()
  Save.frame:Show()
end

function Save.hide()
  if Save.frame then Save.frame:Hide() end
end

function Save.later()
  Save.dueAt = time() + Save.SNOOZE
  Save.hide()
end

-- Extra occasion: show the window if the last save is old enough and it was not shown a moment ago.
-- During combat/instances the request is kept for a short while and shown by the next check.
function Save.request(reason)
  if Save.isShown() then return false end
  local now = time()
  if minutesSinceSave() * 60 < Save.MIN_AGE then return false end
  if Save.lastShown and now - Save.lastShown < Save.MIN_GAP then return false end
  if Save.blocked() then
    Save.pendingUntil = now + Save.PENDING_FOR
    Save.pendingReason = reason
    return false
  end
  Save.show()
  return true
end

function Save.check()
  if Save.isShown() then
    Save.refresh()
    return
  end
  if Save.pendingUntil then
    if time() > Save.pendingUntil then
      Save.pendingUntil = nil
    elseif not Save.blocked() then
      if Save.request(Save.pendingReason or "pending") then return end
    end
  end
  if not Save.dueAt or time() < Save.dueAt then return end
  if Save.blocked() then return end
  Save.show()
end

-- 'saved' = last login or reload
function Save.start()
  if Save.ticker then return end
  Save.lastSave = (ns.Store and ns.Store.loginAt) or time()
  Save.dueAt = Save.lastSave + Save.INTERVAL
  Save.ticker = C_Timer.NewTicker(Save.TICK, function() ns.Core.safe(Save.check) end)
end

-- takeoff: control is lost, a moment later the client reports UnitOnTaxi (fear/charm do not count)
ns.Core.on("PLAYER_CONTROL_LOST", function()
  C_Timer.After(Save.TAKEOFF_DELAY, function()
    ns.Core.safe(function()
      if type(UnitOnTaxi) ~= "function" then return end
      local ok, onTaxi = pcall(UnitOnTaxi, "player")
      -- unreadable (secret) counts as 'no'
      if ok and not (type(issecretvalue) == "function" and issecretvalue(onTaxi)) and onTaxi == true then
        Save.request("flight")
      end
    end)
  end)
end)
ns.Core.on("PLAYER_LEVEL_UP", function() Save.request("level") end)

ns.Core.on("PLAYER_ENTERING_WORLD", function()
  if Save.ticker then Save.check() else Save.start() end
end)
ns.Core.on("PLAYER_REGEN_ENABLED", function() Save.check() end)
ns.Core.on("ZONE_CHANGED_NEW_AREA", function() Save.check() end)
