-- Share: a link to the web page (https://even512.github.io/InkAndEmbers-web/) that preselects a character there.
-- Flow: "Share" button on the journey card (next to playback) or a row in the "..." menu -> small window "Share your journey"
-- -> "Save & show link" writes a short-lived marker into the saved file (EveNChronicleDB.meta.pendingShare) and reloads the
-- interface (secure "/reload" button from Save.newReloadButton, the marker is set in its PreClick; the client blocks
-- ReloadUI from addon code) -> after the reload the link window opens by itself
-- (never in combat: it waits for PLAYER_REGEN_ENABLED) and the marker is deleted. "Without saving" shows the link at once.
-- The link carries only the character GUID and the view in the fragment (#...), which the browser never sends to a server.
-- Nothing else is stored; the marker lives at most MAX_AGE seconds and is removed as soon as it was shown (or has expired).
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Share = {}
Journal.Share = Share

local format, floor = string.format, math.floor

Share.BASE = "https://even512.github.io/InkAndEmbers-web/"
Share.VIEWS = { journey = true, chronicle = true }
Share.DEFAULT_VIEW = "journey"
Share.MAX_AGE = 300       -- seconds a marker counts after the click (reload takes seconds, 5 min is generous)
Share.MAX_FUTURE = 60     -- tolerated clock skew into the future
Share.MAX_GUID = 64       -- bytes of a GUID; longer values are not plausible and are refused
Share.DIALOG_NAME = "InkAndEmbersShareDialog"
Share.LINK_NAME = "InkAndEmbersShareLink"

local T = ns.Locale.ns("Share", {
  button = "Teilen",
  buttonTip = "Erstellt einen Link zu einer Webseite, auf der Ihr all Eure Daten aufbereitet zum Teilen vorfindet.",
  dialogTitle = "Reise teilen",
  explain = "Die Webseite liest Eure gespeicherte Datei. Damit sie Euren neuesten Stand zeigt, lädt „Speichern & Link zeigen“ die Oberfläche kurz neu. Danach erscheint der Link von selbst.",
  saveShow = "Speichern & Link zeigen",
  noSave = "Ohne Speichern",
  noSaveHint = "Ohne Speichern zeigt die Webseite den Stand vom letzten Ausloggen oder Neuladen.",
  linkTitle = "Link zur Webseite",
  copyHint = "Strg+C zum Kopieren, Esc schließt.",
  steps = "1. Link im Browser öffnen.\n2. Die Datei InkAndEmbers.lua aus\nWorld of Warcraft\\%s\\WTF\\Account\\<Euer Konto>\\SavedVariables\\\nauf die Seite ziehen.",
  staleNote = "Dieser Link zeigt den Stand vom letzten Ausloggen oder Neuladen.",
  noName = "Der Charakter dieses Buchs ist nicht erkennbar. Es lässt sich nicht teilen.",
  close = "Schließen",
})
Share.TEXT = T

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

-- ---------- link ----------

-- percent-encoding of every byte except unreserved characters (RFC 3986)
function Share.encode(s)
  if type(s) ~= "string" then return "" end
  return (s:gsub("[^A-Za-z0-9%-_%.~]", function(c) return format("%%%02X", c:byte()) end))
end

-- a character GUID as the addon keys chars[guid] ("Player-6945-0003049D"): only letters, digits and hyphens, plausible length | nil
local function validGuid(g)
  if type(g) ~= "string" or isSecret(g) then return nil end
  if #g < 8 or #g > Share.MAX_GUID or not g:find("^[A-Za-z0-9%-]+$") then return nil end
  return g
end
Share.validGuid = validGuid

-- https://…/InkAndEmbers-web/#g=<GUID>&v=<view>   (no name, no realm: names are not unique, the GUID is) | nil without a GUID
function Share.link(guid, view)
  guid = validGuid(guid)
  if not guid then return nil end
  if not Share.VIEWS[view] then view = Share.DEFAULT_VIEW end
  return Share.BASE .. "#g=" .. Share.encode(guid) .. "&v=" .. view
end

-- "Player-3726-0A1B2C3D" -> "3726-0A1B2C3D"
local function shortGuid(guid)
  if type(guid) ~= "string" or isSecret(guid) or guid == "" then return nil end
  return (guid:gsub("^Player%-", ""))
end
Share.shortGuid = shortGuid

local function db()
  local d = rawget(_G, "EveNChronicleDB")
  return type(d) == "table" and d or nil
end

local function ownGuid()
  if type(UnitGUID) ~= "function" then return nil end
  local ok, g = pcall(UnitGUID, "player")
  if not ok then return nil end
  return validGuid(g)
end

-- the character whose book is on screen: { guid } (own book or the open guest book) | nil when no GUID is readable
function Share.target()
  local P = Journal.Pages
  local g = P and type(P.guest) == "function" and P.guest() or nil
  local guid
  if g then guid = validGuid(g.guid) else guid = ownGuid() end
  if not guid then return nil end
  return { guid = guid }
end

-- the character of a short guid (own character first, then the saved file) | nil
local function targetByShort(short)
  local own = ownGuid()
  if own and shortGuid(own) == short then return { guid = own } end
  local d = db()
  if not (d and type(d.chars) == "table") then return nil end
  for g in pairs(d.chars) do
    if validGuid(g) and shortGuid(g) == short then return { guid = g } end
  end
  return nil
end

-- folder of the client under "World of Warcraft": _retail_ in Retail, _forever_ in WoW Forever
function Share.clientFolder()
  local MS = Journal.MapSpace
  if MS and type(MS.retailClient) == "function" then
    local ok, retail = pcall(MS.retailClient)
    if ok and retail == true then return "_retail_" end
  end
  return "_forever_"
end

-- ---------- marker (short-lived, in the saved file) ----------

local function metaTable()
  local d = db()
  local m = d and d.meta
  return type(m) == "table" and m or nil
end

-- writes the marker; false when the saved file is not available
function Share.setPending(view, target)
  local m = metaTable()
  local by = shortGuid(ownGuid())
  if not (m and by and target) then return false end
  if not Share.VIEWS[view] then view = Share.DEFAULT_VIEW end
  m.pendingShare = { view = view, guid = shortGuid(target.guid) or by, by = by, at = time() }
  return true
end

function Share.clearPending()
  local m = metaTable()
  if m then m.pendingShare = nil end
end

-- the marker as a plain table, or nil (none / damaged / expired - the last two are removed)
function Share.pending()
  local m = metaTable()
  local p = m and m.pendingShare
  if p == nil then return nil end
  local now = time()
  if type(p) ~= "table" or isSecret(p.at) or type(p.at) ~= "number" or p.at ~= p.at
     or now - p.at > Share.MAX_AGE or p.at - now > Share.MAX_FUTURE
     or type(p.guid) ~= "string" or type(p.by) ~= "string" or not Share.VIEWS[p.view] then
    m.pendingShare = nil
    return nil
  end
  return p
end

-- ---------- windows ----------

local dialog, linkWin

local PAGE_PAD = 8 -- gap between title and first element

local function blocked()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

-- light parchment window: the note pad of the to-do note (Save.newPaper), ink texts, small "x" in the corner. All elements hang
-- on the window or on its body frame, never on a font string (a protected button is not laid out when anchored to an
-- unprotected region).
local function frameBase(name, w, h)
  local parent = rawget(_G, "UIParent")
  local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
  f.winW = w
  f:SetSize(w, h)
  f:SetPoint("CENTER", parent, "CENTER", 0, 80)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.paper = ns.Save.newPaper(f)
  f.title = ns.Save.paperText(f.paper, "hand", 24, "red")
  f.close = ns.Save.paperClose(f.paper, function() f:Hide() end, T.close)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, name) end -- Esc closes
  f:Hide()
  return f
end

local function label(f, kind, size, color)
  return ns.Save.paperText(f.paper, kind, size, color)
end

local function textHeight(fs, fallback)
  return ns.Save.textHeight(fs, fallback)
end

-- writing area of the window: left, right, top (below the tape), bottom; places title and "x"; returns also the y of the first element
local function frameArea(f)
  local l, r, t, b = ns.Save.layoutPaper(f.paper, f.winW, 1000)
  f.title:ClearAllPoints()
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", l, -t)
  f.title:SetWidth(f.winW - l - r - 24)
  f.close:ClearAllPoints()
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(r - 2), -(t + 3))
  return l, r, t, b, floor(t + textHeight(f.title, 26) + PAGE_PAD + 0.5)
end

-- final height: sizes the window and the pad together
local function frameHeight(f, h)
  h = floor(h + 0.5)
  f:SetHeight(h)
  ns.Save.layoutPaper(f.paper, f.winW, h)
end

function Share.closeDialog()
  if dialog then dialog:Hide() end
end

function Share.closeLink()
  if linkWin then linkWin:Hide() end
end

local function buildLink()
  local W = 520
  local f = frameBase(Share.LINK_NAME, W, 240)
  f.title:SetText(T.linkTitle)
  -- the link field sits on a slightly darker ink wash, so it reads as a field on the light paper
  local wash = f.paper.body:CreateTexture(nil, "BACKGROUND")
  wash:SetColorTexture(0.30, 0.20, 0.10, 0.10)
  f.wash = wash
  local box = CreateFrame("EditBox", nil, f.paper.body, "InputBoxTemplate")
  box:SetHeight(24)
  box:SetAutoFocus(false)
  box:SetMaxLetters(0)
  if type(ChatFontNormal) ~= "nil" then box:SetFontObject(ChatFontNormal) end
  if box.SetTextColor then box:SetTextColor(ns.Save.INK[1], ns.Save.INK[2], ns.Save.INK[3]) end
  box:SetScript("OnEscapePressed", function() Share.closeLink() end)
  box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  -- read only: any edit is undone, the link stays whole and selected
  box:SetScript("OnTextChanged", function(self)
    local want = f.linkText
    if want and self:GetText() ~= want then
      self:SetText(want)
      self:HighlightText()
    end
  end)
  f.box = box
  f.hint = label(f, "text", 12, "sepia")
  f.hint:SetText(T.copyHint)
  f.steps = label(f, "text", 14, "ink")
  f.note = label(f, "text", 12, "sepia")
  f:SetScript("OnHide", function() f.linkText = nil end)
  return f
end

-- shows the link window; stale = true adds the note that the file may be older than the game state
function Share.showLink(target, view, stale)
  local link = target and Share.link(target.guid, view)
  if not link then return false end
  if not linkWin then linkWin = buildLink() end
  local f = linkWin
  f.linkText = link
  f.box:SetText(link)
  f.steps:SetText(T("steps", Share.clientFolder()))
  f.note:SetText(stale and T.staleNote or "")
  local l, r, _, b, y = frameArea(f)
  local w = f.winW - l - r
  f.box:ClearAllPoints()
  f.box:SetPoint("TOPLEFT", f, "TOPLEFT", l + 6, -y)
  f.box:SetWidth(w - 8)
  f.wash:ClearAllPoints()
  f.wash:SetPoint("TOPLEFT", f, "TOPLEFT", l, -(y - 2))
  f.wash:SetSize(w, 28)
  y = y + 30
  for _, fs in ipairs({ f.hint, f.steps, f.note }) do fs:SetWidth(w) end
  f.hint:ClearAllPoints()
  f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", l, -y)
  y = y + textHeight(f.hint, 14) + 10
  f.steps:ClearAllPoints()
  f.steps:SetPoint("TOPLEFT", f, "TOPLEFT", l, -floor(y + 0.5))
  y = y + textHeight(f.steps, 64) + 10
  f.note:ClearAllPoints()
  f.note:SetPoint("TOPLEFT", f, "TOPLEFT", l, -floor(y + 0.5))
  if stale then y = y + textHeight(f.note, 14) + 4 else y = y - 10 end
  frameHeight(f, y + b)
  f:Show()
  f.box:SetFocus()
  f.box:HighlightText()
  return true
end

local function buildDialog()
  local W = 440
  local f = frameBase(Share.DIALOG_NAME, W, 240)
  f.title:SetText(T.dialogTitle)
  f.explain = label(f, "text", 14, "ink")
  f.explain:SetText(T.explain)
  -- secure "/reload" button (built out of combat only, Share.open checks): the PreClick writes the marker
  local saveBtn = ns.Save.newReloadButton(f, T.saveShow, Share.prepareSave, Share.showNow)
  saveBtn:SetSize(190, 24)
  f.saveBtn = saveBtn
  local noBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  noBtn:SetSize(150, 24)
  noBtn:SetText(T.noSave)
  noBtn:SetScript("OnClick", function() Share.showNow() end)
  f.noBtn = noBtn
  f.hint = label(f, "text", 12, "sepia")
  f.hint:SetText(T.noSaveHint)
  return f
end

-- opens the first window for the book on screen. Returns false (and says why in the chat) when it cannot be shared.
-- Not in combat: the window holds a secure button (it can neither be built nor shown then).
function Share.open(view)
  local target = Share.target()
  if not target then
    if ns.Core and ns.Core.print then ns.Core.print(T.noName) end
    return false
  end
  local S = ns.Save
  if not (S and type(S.newReloadButton) == "function") then
    Share.showLink(target, view, true)
    return true
  end
  if blocked() then
    S.say("combat")
    return false
  end
  if not Share.VIEWS[view] then view = Share.DEFAULT_VIEW end
  if not dialog then dialog = buildDialog() end
  local f = dialog
  f.target, f.view = target, view
  Share.closeLink()
  f:Show()
  local l, r, _, b, y = frameArea(f)
  local w = f.winW - l - r
  f.explain:SetWidth(w)
  f.hint:SetWidth(w)
  f.explain:ClearAllPoints()
  f.explain:SetPoint("TOPLEFT", f, "TOPLEFT", l, -y)
  y = floor(y + textHeight(f.explain, 56) + 14 + 0.5)
  f.saveBtn:ClearAllPoints()
  f.saveBtn:SetPoint("TOPLEFT", f, "TOPLEFT", l, -y)
  f.saveBtn:Show()
  f.noBtn:ClearAllPoints()
  f.noBtn:SetPoint("TOPLEFT", f, "TOPLEFT", l + 190 + 10, -y)
  f.noBtn:Show()
  y = y + 24 + 10
  f.hint:ClearAllPoints()
  f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", l, -y)
  frameHeight(f, y + textHeight(f.hint, 28) + b)
  return true
end

-- "Without saving": the link now (it shows the state of the last logout or reload)
function Share.showNow()
  local f = dialog
  local target, view = f and f.target, f and f.view
  Share.closeDialog()
  if target then Share.showLink(target, view, true) end
end

-- "Save & show link", PreClick of the secure reload button: writes the marker; false (no saved file) switches the reload
-- off for this click and shows the link at once (Share.showNow). The macro "/reload" then reloads the interface.
function Share.prepareSave()
  local f = dialog
  local target, view = f and f.target, f and f.view
  if not target then return false end
  return Share.setPending(view, target)
end

-- after a reload: show the link window when a fresh marker of this character waits (never in combat: waits for the next check)
function Share.checkPending()
  local p = Share.pending()
  if not p then return false end
  local own = shortGuid(ownGuid())
  if not own or p.by ~= own then return false end -- another character is logged in: the marker expires on its own
  if blocked() then return false end
  Share.clearPending()
  local target = targetByShort(p.guid)
  if not target then return false end
  return Share.showLink(target, p.view, false)
end

-- ---------- button on the journey card ----------

-- Frame.lua calls this once after the playback bar exists. The sticker hangs on the bar's frame, so it follows its
-- visibility (hidden wherever the bar is hidden) and sits on the strip above the bar, right-aligned.
function Share.build(bar)
  if Share.button or type(bar) ~= "table" then return end
  local D = Journal.Widgets and Journal.Widgets.Diary
  if not (D and type(D.NewSticker) == "function") then return end
  local b = D.NewSticker(bar, T.button, function() ns.Core.safe(Share.open, Share.DEFAULT_VIEW) end,
    { height = 28, size = 16, tip = { T.button, T.buttonTip } })
  b:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 2)
  Share.button = b
end

ns.Core.on("PLAYER_ENTERING_WORLD", function() Share.checkPending() end)
ns.Core.on("PLAYER_REGEN_ENABLED", function() Share.checkPending() end)
-- last moment before the lockdown: close the window with the secure button (it could not be hidden in combat)
ns.Core.on("PLAYER_REGEN_DISABLED", function() Share.closeDialog() end)
