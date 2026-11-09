-- Save reminder: small non-modal frame, no sound, no focus.
-- Reloading: the client blocks ReloadUI from addon code (ADDON_ACTION_BLOCKED, even straight from an OnClick). Every button
-- that reloads is therefore a secure action button running the macro "/reload" (Save.newReloadButton); the addon itself
-- never calls ReloadUI. Markers (Store.markReload, the share marker) are set in its PreClick.
local _, ns = ...

local Save = {}
ns.Save = Save

local floor = math.floor

local T = ns.Locale.ns("Save", {
  prompt = "Reise sichern? Letzte Sicherung vor %d min.",
  save = "Sichern",
  later = "Später",
  status = "Zuletzt gesichert vor %d min",
  combat = "Im Kampf nicht möglich. Bitte nach dem Kampf erneut versuchen.",
  typeReload = "Das Spiel lässt das Neuladen hier nicht zu. Bitte gebt /reload ein, dabei wird Euer Stand gespeichert.",
})
Save.TEXT = T

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

-- The reminder window is opt-in ("saveReminder", default off; the book setting lives in Journal.Pages). Without the
-- journal or without a stored value it stays off. Manual opening (/chronik sichern, settings) is not affected.
function Save.enabled()
  local Pages = ns.Journal and ns.Journal.Pages
  if not Pages or type(Pages.setting) ~= "function" then return false end
  return Pages.setting("saveReminder") == true
end

-- quiet status line (book "..." tooltip, settings row): computed when asked, never refreshed by a ticker
function Save.statusText()
  return T("status", minutesSinceSave())
end

Save.RELOAD_MACRO = "/reload"
Save.BUTTON_TEMPLATE = "UIPanelButtonTemplate"
Save.SECURE_TEMPLATE = "UIPanelButtonTemplate,SecureActionButtonTemplate"
Save.RELOAD_CHECK = 2 -- seconds: an interface that still runs this long after a reload click was not reloaded

function Save.inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function say(key)
  if ns.Core and ns.Core.print then ns.Core.print(T[key]) end
end
Save.say = say

-- ---------- light parchment for the small windows (reload prompt, share windows) ----------
-- The same note pad as the to-do note and the moments (Media/TodoPad, three pieces, no vertex colour, nothing dark beneath),
-- the texts are ink on it. Without the journal files a plain light sheet with a thin sepia edge takes its place.
local FALLBACK_COLOR = { ink = { 0.20, 0.13, 0.07 }, sepia = { 0.45, 0.32, 0.18 }, red = { 0.55, 0.16, 0.10 } }

Save.INK = FALLBACK_COLOR.ink

local function journalPart(name)
  local J = ns.Journal
  return J and J[name] or nil
end

-- paper = { pad = note pad pieces | nil, body = frame (two levels above the pad) for texts and controls }
function Save.newPaper(f)
  local paper = { frame = f }
  local TT, Theme = journalPart("TodoTracker"), journalPart("Theme")
  if TT and Theme and Theme.HAS_TODO_PAD and Theme.TEX and Theme.TEX.todoPad and Theme.TODO_PAD_SLICE
     and type(TT.newPad) == "function" and type(TT.sizePad) == "function" and type(TT.padY) == "function" then
    local ok, pad = pcall(TT.newPad, f)
    if ok and type(pad) == "table" and pad.image then paper.pad = pad end
  end
  if not paper.pad then
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0.95, 0.90, 0.78, 1)
    local c = FALLBACK_COLOR.sepia
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                         { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
      local t = f:CreateTexture(nil, "BORDER")
      t:SetColorTexture(c[1], c[2], c[3], 1)
      t:SetPoint(e[1], f, e[1], 0, 0)
      t:SetPoint(e[2], f, e[2], 0, 0)
      if e[3] then t:SetHeight(1) else t:SetWidth(1) end
    end
  end
  local body = CreateFrame("Frame", nil, f)
  body:SetAllPoints(f)
  body:SetFrameLevel((f:GetFrameLevel() or 1) + 2)
  paper.body = body
  return paper
end

-- sizes the pad for a window of w x h and returns the free writing area as insets: left, right, top, bottom
function Save.layoutPaper(paper, w, h)
  local pad = paper and paper.pad
  if not pad then return 16, 16, 14, 14 end
  local TT, S = journalPart("TodoTracker"), journalPart("Theme").TODO_PAD_SLICE
  TT.sizePad(pad, w, h)
  local side = floor(w * (S.margin or 0.1) + 0.5)
  local top = floor((TT.padY(pad, (S.tab and S.tab[3]) or S.edge or 0.075) or 0) + 0.5) + 6
  local bottom = floor(w * 0.1 + 0.5) + 2
  return side, side - 6, top, bottom
end

-- a text on the paper: kind "text" | "hand", colour "ink" | "sepia" | "red"
function Save.paperText(paper, kind, size, color, width)
  local fs = paper.body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs.inkPlain = true
  local TT = journalPart("TodoTracker")
  if TT and type(TT.setFont) == "function" and type(TT.colorOf) == "function" then
    TT.setFont(fs, kind, size)
    fs:SetTextColor(TT.colorOf(color))
  else
    local c = FALLBACK_COLOR[color] or FALLBACK_COLOR.ink
    fs:SetTextColor(c[1], c[2], c[3])
  end
  if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
  fs:SetJustifyH("LEFT")
  if fs.SetJustifyV then fs:SetJustifyV("TOP") end
  if fs.SetWordWrap then fs:SetWordWrap(true) end
  if width then fs:SetWidth(width) end
  return fs
end

-- small "x" in the corner of the paper (the one of the to-do note), onClick closes the window
function Save.paperClose(paper, onClick, tip)
  local TT = journalPart("TodoTracker")
  if TT and type(TT.newClose) == "function" and type(TT.paintClose) == "function" then
    local b = TT.newClose(paper.body, onClick, tip)
    TT.paintClose(b, true)
    return b
  end
  local b = CreateFrame("Button", nil, paper.body, "UIPanelCloseButton")
  b:SetScript("OnClick", function() onClick() end)
  return b
end

function Save.textHeight(fs, fallback)
  local h = fs and fs.GetStringHeight and fs:GetStringHeight()
  if type(h) ~= "number" or h ~= h or h <= 0 then return fallback end
  return h
end

-- PreClick of a reload button (runs before the secure macro): prepare() sets the markers and returns false when there is
-- nothing to reload for; then the macro is switched off for this click and onSkip() runs instead. In combat the attributes
-- are locked (the windows are closed at PLAYER_REGEN_DISABLED anyway), so nothing is changed there.
function Save.preClick(b, prepare, onSkip)
  if Save.inCombat() then return end
  if b.reloadSecure then b:SetAttribute("type", nil) end
  local ok, ready = true, true
  if type(prepare) == "function" then ok, ready = pcall(prepare) end
  if not ok then
    if ns.Core and ns.Core.coreError then ns.Core.coreError(ready) end
    ready = false
  end
  if ready == false then
    if type(onSkip) == "function" then ns.Core.safe(onSkip) end
    return
  end
  if ns.Store then ns.Store.markReload() end
  if not b.reloadSecure then
    say("typeReload") -- no secure template in this client: the player reloads by hand, the markers are already set
    return
  end
  b:SetAttribute("type", "macro")
  -- never silent: when the interface is still there a moment later, the reload was refused - say how to save by hand
  local at = GetTime()
  Save.reloadAskedAt = at
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(Save.RELOAD_CHECK, function()
      if Save.reloadAskedAt == at then
        Save.reloadAskedAt = nil
        say("typeReload")
      end
    end)
  end
end

-- A button that saves = reloads the interface: secure action button with the macro "/reload" (the slash command runs in
-- secure code; ReloadUI from addon code is blocked). Registered for down and up: the secure handler acts on the one the
-- client's ActionButtonUseKeyDown setting asks for. Never built in combat (returns nil). Without the secure template the
-- button only sets the markers and asks for /reload in the chat.
function Save.newReloadButton(parent, text, prepare, onSkip)
  if Save.inCombat() then return nil end
  local ok, b = pcall(CreateFrame, "Button", nil, parent, Save.SECURE_TEMPLATE)
  local secure = ok and type(b) == "table"
  if not secure then b = CreateFrame("Button", nil, parent, Save.BUTTON_TEMPLATE) end
  b.reloadSecure = secure
  b:SetText(text)
  if secure then
    b:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", Save.RELOAD_MACRO)
    b:SetScript("PreClick", function(self) Save.preClick(self, prepare, onSkip) end)
  else
    b:SetScript("OnClick", function(self) Save.preClick(self, prepare, onSkip) end)
  end
  return b
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

Save.W = 310
Save.BTN_W, Save.BTN_H = 110, 22

local function build()
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetSize(Save.W, 130)
  f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -220)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  local paper = Save.newPaper(f)

  local text = Save.paperText(paper, "text", 13, "ink")

  local saveButton = Save.newReloadButton(f, T.save)
  saveButton:SetSize(Save.BTN_W, Save.BTN_H)

  local laterButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  laterButton:SetSize(Save.BTN_W, Save.BTN_H)
  laterButton:SetText(T.later)
  laterButton:SetScript("OnClick", function() Save.later() end)

  f:Hide()
  Save.frame, Save.paper, Save.text, Save.saveButton, Save.laterButton = f, paper, text, saveButton, laterButton
end

-- text, buttons and pad size follow the text height; absolute offsets from the window itself (a protected button is never
-- anchored to an unprotected region). Only called out of combat (Save.show).
function Save.layout()
  local f, paper = Save.frame, Save.paper
  if not f then return end
  local W = Save.W
  local l, r, t, b = Save.layoutPaper(paper, W, 1000)
  Save.text:ClearAllPoints()
  Save.text:SetPoint("TOPLEFT", f, "TOPLEFT", l, -t)
  Save.text:SetWidth(W - l - r)
  local th = math.max(Save.textHeight(Save.text, 32), 30)
  local by = floor(t + th + 10 + 0.5)
  Save.saveButton:ClearAllPoints()
  Save.saveButton:SetPoint("TOPLEFT", f, "TOPLEFT", l, -by)
  Save.laterButton:ClearAllPoints()
  Save.laterButton:SetPoint("TOPLEFT", f, "TOPLEFT", l + Save.BTN_W + 10, -by)
  local H = by + Save.BTN_H + b
  f:SetHeight(H)
  Save.layoutPaper(paper, W, H)
end

function Save.isShown()
  return Save.frame ~= nil and Save.frame:IsShown() and true or false
end

-- the window holds a secure button: it is never built, shown or hidden in combat (it is closed at PLAYER_REGEN_DISABLED)
function Save.show(strata)
  if Save.inCombat() then
    say("combat")
    return false
  end
  if not Save.frame then build() end
  Save.frame:SetFrameStrata(strata or "MEDIUM")
  Save.lastShown = time()
  Save.pendingUntil = nil
  Save.refresh()
  Save.layout()
  Save.frame:Show()
  return true
end

-- opened by hand (settings "Save now"): above the settings panel
function Save.offer()
  return Save.show("DIALOG")
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
  if not Save.enabled() then
    Save.pendingUntil = nil
    return false
  end
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
  if not Save.enabled() then
    Save.pendingUntil = nil
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
-- last moment before the lockdown: close the window with the secure button (it could not be hidden in combat)
ns.Core.on("PLAYER_REGEN_DISABLED", function() Save.hide() end)
ns.Core.on("ZONE_CHANGED_NEW_AREA", function() Save.check() end)
