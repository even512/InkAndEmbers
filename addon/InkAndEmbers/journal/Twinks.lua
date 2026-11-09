-- Twinks user interface (read another character's book, read only; core: journal/model/Roster.lua and journal/Pages.lua):
--   * round button "Other books" below the "..." button at the book edge (only when Roster.hasOthers())
--   * character list on a paper slip (name in class colour, level, race/class, realm, last seen; own book on top; entries that
--     cannot be opened are greyed with the reason; right click = take off the list, undo in the settings)
--   * guest band over the right page ("You are reading the book of <name>" + "Back to your book") with a small seal
-- Nothing here writes into a character: the list only calls Roster.hide/unhide (UI marker), opening goes through
-- Pages.setGuest. All SV text (names, realms) is shown only through Sanitize.display. No ticker, no OnUpdate.
-- Frame.lua builds it (Twinks.build) and tells it about guest changes (Twinks.onGuest).
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Twinks = {}
Journal.Twinks = Twinks

local floor, max, min = math.floor, math.max, math.min

Twinks.ROWS = 9           -- visible list rows (more entries scroll)
Twinks.ROW_H = 46
Twinks.LIST_W = 420
Twinks.BAND_H = 28
Twinks.DEFER = 0.05       -- seconds between "ink is drying" and the (synchronous) guest build

Twinks.TEXT = ns.Locale.ns("Twinks", {
  buttonTitle = "Andere Bücher",
  buttonTip = "Die Bücher Eurer anderen Charaktere lesen – nur lesend, nichts wird verändert.",
  listTitle = "ANDERE BÜCHER",
  listHint = "Klick: Buch lesen · Rechtsklick: aus der Liste nehmen",
  empty = "Keine anderen Charaktere.",
  ownTag = "Euer Buch",
  ownTip = "Das Buch des Charakters, mit dem Ihr eingeloggt seid.",
  level = "Stufe %s",
  seen = "zuletzt am %s",
  dateFmt = "%d.%m.%Y",
  unknownName = "Unbekannter Charakter",
  hiddenTag = "ausgeblendet",
  shortLeer = "noch leer",
  shortFehlt = "nur in der Sicherung",
  shortAnderes = "anderes Spiel",
  reasonLeer = "Noch keine Einträge – dieser Charakter hat noch nichts festgehalten.",
  reasonFehlt = "Die Daten liegen nur in der Sicherung dieses Charakters. Einmal mit ihm einloggen.",
  reasonAnderes = "Aus einem anderen Spiel aufgezeichnet (andere Karten). Hier nicht lesbar.",
  openTip = "Klick: dieses Buch lesen",
  hideTip = "Rechtsklick: aus der Liste nehmen (die Daten bleiben)",
  hideAction = "Aus der Liste nehmen",
  unhideAction = "Wieder in die Liste",
  bandReading = "Ihr lest das Buch von %s",
  bandLoading = "Die Tinte trocknet … Buch von %s",
  backToOwn = "Zurück zu Eurem Buch",
  backTip = "Zurück zum eigenen Buch",
  backTipText = "Das gelesene Buch wird wieder geschlossen. Auch beim Schließen des Buchs.",
  hereTitle = "Zuletzt hier",
  hereText = "Letzter bekannter Ort von %s",
  standDate = "Stand: %s",
})
local T = Twinks.TEXT

local state = { listOpen = false, items = {}, pending = nil }
Twinks.state = state

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function W() return Journal.Widgets end
local function D() local w = Journal.Widgets return w and w.Diary end
local function Theme() return Journal.Theme end

local function disp(s, n)
  local S = ns.Sanitize
  return S and S.display(s, n or 32) or nil
end

local function int(n)
  local Tx = Journal.Texts
  return Tx and Tx.int(n) or tostring(floor(tonumber(n) or 0))
end

local function dateText(t)
  if type(t) ~= "number" or t ~= t or t <= 0 or t >= 2 ^ 40 then return nil end
  local ok, s = pcall(date, T.dateFmt, t)
  return (ok and type(s) == "string" and s ~= "") and s or nil
end
Twinks.dateText = dateText

local function pagesApi() return Journal.Pages end

local function guestNow()
  local P = pagesApi()
  return P and type(P.guest) == "function" and P.guest() or nil
end

-- class colour / names through the Weggefährten view (one table for the whole book)
local function mates() return Journal.CompanionsView end

local function classColor(classFile)
  local M = mates()
  if M and type(M.classColor) == "function" then return M.classColor(classFile) end
  local w = W()
  return { w.color("ink") }
end

local function kindText(r)
  local M = mates()
  local race = (M and r.raceFile and M.RACE_NAME[r.raceFile]) or disp(r.race, 24)
  local cls = (M and r.classFile and M.className and M.className(r.classFile)) or disp(r.class, 24)
  if race and cls then return race .. " · " .. cls end
  return race or cls
end

-- one list entry from a Roster row (display ready strings; raw SV text only through Sanitize.display)
function Twinks.itemOf(r)
  -- "Vorname Nachname" and the ruleset on Forever (never the hidden shard), the realm on Retail (Names.lua)
  local Names = ns.Names
  local name = disp(Names and Names.fullName(r) or r.name, 40) or T.unknownName
  local it = { guid = r.guid, own = r.own, hidden = r.hidden, openable = r.openable, reason = r.reason }
  it.name = name
  it.color = classColor(r.classFile)
  it.levelText = r.level and T("level", int(r.level)) or ""
  local kind, realm = kindText(r), disp(Names and Names.realmText(r) or (not Names and r.realm) or nil, 32)
  it.sub = (kind and realm) and (kind .. " · " .. realm) or kind or realm or ""
  local d = dateText(r.lastSeen)
  if r.own then
    it.right = T.ownTag
  elseif r.hidden then
    it.right = T.hiddenTag
  elseif not r.openable then
    it.right = (r.reason == "fehlt" and T.shortFehlt) or (r.reason == "anderes-spiel" and T.shortAnderes) or T.shortLeer
  else
    it.right = d and T("seen", d) or ""
  end
  local lines, colors = { name }, { it.color }
  local second = {}
  if it.levelText ~= "" then second[#second + 1] = it.levelText end
  if it.sub ~= "" then second[#second + 1] = it.sub end
  if #second > 0 then lines[#lines + 1] = table.concat(second, " · ") end
  if d and not r.own then lines[#lines + 1] = T("seen", d) end
  if r.own then
    lines[#lines + 1] = T.ownTip
  elseif not r.openable then
    lines[#lines + 1] = (r.reason == "fehlt" and T.reasonFehlt) or (r.reason == "anderes-spiel" and T.reasonAnderes) or T.reasonLeer
  else
    lines[#lines + 1] = T.openTip
  end
  if not r.own then lines[#lines + 1] = T.hideTip end
  it.tip, it.tipColors = lines, colors
  return it
end

function Twinks.items()
  local R = Journal.Roster
  local P = pagesApi()
  if not R then return {} end
  local show = P and P.setting("showHiddenChars") == true
  local ok, rows = pcall(R.list, { hidden = show })
  local out = {}
  if not ok or type(rows) ~= "table" then return out end
  for _, r in ipairs(rows) do out[#out + 1] = Twinks.itemOf(r) end
  return out
end

---------------------------------------------------------------------------------------------------------------- button

local function glyph(btn)
  local th = Theme()
  local back = btn:CreateTexture(nil, "OVERLAY", nil, 1)
  back:SetColorTexture(th.C.parchment[1], th.C.parchment[2], th.C.parchment[3], 0.5)
  back:SetSize(11, 15)
  back:SetPoint("CENTER", btn, "CENTER", -3, 1)
  local front = btn:CreateTexture(nil, "OVERLAY", nil, 2)
  front:SetColorTexture(th.C.parchment[1], th.C.parchment[2], th.C.parchment[3], 1)
  front:SetSize(11, 15)
  front:SetPoint("CENTER", btn, "CENTER", 3, -1)
  local spine = btn:CreateTexture(nil, "OVERLAY", nil, 3)
  spine:SetColorTexture(th.C.cover[1], th.C.cover[2], th.C.cover[3], 1)
  spine:SetSize(2, 15)
  spine:SetPoint("LEFT", front, "LEFT", 0, 0)
  return { back, front, spine }
end

local function buildButton(f, gear)
  local th = Theme()
  local b = CreateFrame("Button", nil, f)
  b:SetSize(34, 34)
  local _, _, _, gx, gy = gear:GetPoint(1)
  b:SetPoint("TOPLEFT", f, "TOPRIGHT", gx or -2, (gy or -330) - 40)
  local disc = b:CreateTexture(nil, "BACKGROUND")
  disc:SetAllPoints(b)
  disc:SetTexture(th.TEX.markers)
  disc:SetTexCoord(th.atlasCoords(th.ATLAS.disc))
  th.color(disc, th.C.cover)
  local ring = b:CreateTexture(nil, "BORDER")
  ring:SetAllPoints(b)
  ring:SetTexture(th.TEX.markers)
  ring:SetTexCoord(th.atlasCoords(th.ATLAS.pulse))
  b.ring = ring
  glyph(b)
  b:SetScript("OnClick", function() Twinks.toggleList() end)
  b:SetScript("OnEnter", function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(T.buttonTitle, 1, 0.82, 0)
      GameTooltip:AddLine(T.buttonTip, 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", th.hideTooltip)
  b:Hide()
  state.button = b
end

-- shown only with at least one other visible character (a single character has no button)
function Twinks.updateButton()
  local b = state.button
  if not b then return false end
  local R = Journal.Roster
  local ok, has = false, false
  if R and type(R.hasOthers) == "function" then ok, has = pcall(R.hasOthers) end
  has = ok and has == true
  -- a hidden-but-shown guest book keeps its button so that the way back is never lost
  if not has and guestNow() then has = true end
  b:SetShown(has)
  local th = Theme()
  if guestNow() then b.ring:SetVertexColor(th.C.gold[1], th.C.gold[2], th.C.gold[3]) else b.ring:SetVertexColor(1, 1, 1) end
  if not has and state.listOpen then Twinks.closeList() end
  return has
end

------------------------------------------------------------------------------------------------------------------- list

local function paintRow(row, it)
  local w = W()
  local grey = not it.openable and not it.own
  local c = it.color or { w.color("ink") }
  row.name:SetTextColor(c[1], c[2], c[3], grey and 0.55 or 1)
  row.level:SetTextColor(w.color(grey and "faint" or "sepia"))
  row.sub:SetTextColor(w.color("sepia", grey and 0.7 or 1))
  row.right:SetTextColor(w.color(it.own and "red" or "sepia", grey and 0.8 or 1))
  row.name:SetText(it.name)
  row.level:SetText(it.levelText)
  row.sub:SetText(it.sub)
  row.right:SetText(it.right)
  row.hl:SetShown(row.hover and (it.openable or it.own) and true or false)
end

local function buildRow(row)
  local w = W()
  local Lw = Twinks.LIST_W - 12 - 10
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row.hl = row:CreateTexture(nil, "BACKGROUND")
  row.hl:SetColorTexture(w.color("gold", 0.18))
  row.hl:SetAllPoints(row)
  row.hl:Hide()
  local line = row:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(w.color("sepia", 0.2))
  line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 0)
  line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 0)
  line:SetHeight(1)
  row.label:Hide() -- the list's default label stays unused
  local name = w.font(row, "text", 14, "ink")
  name:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -7)
  name:SetWidth(Lw - 120)
  name:SetJustifyH("LEFT")
  name:SetWordWrap(false)
  row.name = name
  local level = w.font(row, "label", 12, "sepia")
  level:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -9)
  level:SetJustifyH("RIGHT")
  level:SetWordWrap(false)
  row.level = level
  local sub = w.font(row, "label", 12, "sepia")
  sub:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -26)
  sub:SetWidth(Lw - 130)
  sub:SetJustifyH("LEFT")
  sub:SetWordWrap(false)
  row.sub = sub
  local right = w.font(row, "label", 11, "sepia")
  right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -27)
  right:SetWidth(122)
  right:SetJustifyH("RIGHT")
  right:SetWordWrap(false)
  row.right = right
  row:SetScript("OnEnter", function(self)
    self.hover = true
    local it = state.list and state.list.items[self.index]
    if it then
      paintRow(self, it)
      local ww = W()
      if ww then ww.tip(self, it.tip, it.tipColors) end
    end
  end)
  row:SetScript("OnLeave", function(self)
    self.hover = false
    local it = state.list and state.list.items[self.index]
    if it then paintRow(self, it) end
    local ww = W()
    if ww then ww.hideTip(self) end
  end)
  row:SetScript("OnClick", function(self, button)
    local it = state.list and state.list.items[self.index]
    if not it then return end
    if button == "RightButton" then
      if not it.own then Twinks.openMenu(self, it) end
    else
      Twinks.pick(it)
    end
  end)
end

local function clearRow(row)
  row.hover = false
  if row.hl then row.hl:Hide() end
end

local function fillRow(row, it)
  paintRow(row, it)
  return true
end

local function listHeight(n)
  return 12 + 26 + max(1, min(n, Twinks.ROWS)) * Twinks.ROW_H + 26
end

local function buildList(f, over)
  local w, d = W(), D()
  local pop = CreateFrame("Frame", nil, f)
  pop:SetFrameLevel(over:GetFrameLevel() + 40)
  pop:EnableMouse(true)
  pop:SetSize(Twinks.LIST_W, listHeight(1))
  pop:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(Journal.Frame.RIM + 8), -(Journal.Frame.RIM + 44))
  pop.slip = d.NewSlip(pop)
  local P = d.SLIP.pad
  local title = w.font(pop, "label", 11, "sepia")
  title:SetPoint("TOPLEFT", pop, "TOPLEFT", 16, -14)
  title:SetText(T.listTitle)
  pop.title = title
  local rule = pop:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(w.color("sepia", 0.45))
  rule:SetPoint("TOPLEFT", pop, "TOPLEFT", 10, -30)
  rule:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -10, -30)
  rule:SetHeight(1)
  local list = w.NewList(pop, { rows = Twinks.ROWS, rowHeight = Twinks.ROW_H, width = Twinks.LIST_W - 2 * P - 8, step = 2,
    empty = T.empty, build = buildRow, clear = clearRow, fill = fillRow })
  list.frame:ClearAllPoints()
  list.frame:SetPoint("TOPLEFT", pop, "TOPLEFT", P + 4, -34)
  pop.list = list
  state.list = list
  local hint = w.font(pop, "label", 11, "sepia")
  hint:SetPoint("BOTTOMLEFT", pop, "BOTTOMLEFT", 16, 10)
  hint:SetWidth(Twinks.LIST_W - 32)
  hint:SetJustifyH("LEFT")
  hint:SetWordWrap(false)
  hint:SetText(T.listHint)
  pop.hint = hint

  -- context slip (right click on a row): one action
  local ctx = CreateFrame("Frame", nil, pop)
  ctx:SetFrameLevel(pop:GetFrameLevel() + 10)
  ctx:EnableMouse(true)
  ctx:SetSize(200, 34)
  ctx.slip = d.NewSlip(ctx)
  local cb = CreateFrame("Button", nil, ctx)
  cb:SetPoint("TOPLEFT", ctx, "TOPLEFT", 8, -6)
  cb:SetPoint("BOTTOMRIGHT", ctx, "BOTTOMRIGHT", -8, 6)
  cb.text = w.font(cb, "text", 13, "ink")
  cb.text:SetPoint("LEFT", cb, "LEFT", 4, 0)
  cb.text:SetJustifyH("LEFT")
  cb:SetScript("OnEnter", function(self) self.text:SetTextColor(w.color("red")) end)
  cb:SetScript("OnLeave", function(self) self.text:SetTextColor(w.color("ink")) end)
  cb:SetScript("OnClick", function(self)
    local it = self.item
    Twinks.closeMenu()
    if it then Twinks.toggleHidden(it) end
  end)
  ctx.button = cb
  ctx:Hide()
  local ctxCatcher = CreateFrame("Button", nil, pop)
  ctxCatcher:SetAllPoints(pop)
  ctxCatcher:SetFrameLevel(pop:GetFrameLevel() + 8)
  ctxCatcher:SetScript("OnClick", function() Twinks.closeMenu() end)
  ctxCatcher:Hide()
  pop.ctx, pop.ctxCatcher = ctx, ctxCatcher

  d.escKeys(pop, function()
    if ctx:IsShown() then Twinks.closeMenu() else Twinks.closeList() end
  end)
  local catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  if catcher.SetFrameStrata then catcher:SetFrameStrata("HIGH") end
  if catcher.RegisterForClicks then catcher:RegisterForClicks("AnyUp") end
  catcher:SetScript("OnClick", function() Twinks.closeList() end)
  catcher:Hide()
  pop.catcher = catcher
  pop:HookScript("OnShow", function(p)
    catcher:SetFrameLevel(max(1, (p:GetFrameLevel() or 3) - 2))
    catcher:Show()
  end)
  pop:HookScript("OnHide", function()
    catcher:Hide()
    ctx:Hide()
    ctxCatcher:Hide()
    state.listOpen = false
  end)
  pop:Hide()
  state.pop = pop
end

function Twinks.refreshList()
  local pop = state.pop
  if not (pop and pop:IsShown()) then return end
  local items = Twinks.items()
  state.items = items
  pop:SetHeight(listHeight(#items))
  pop.list.frame:SetHeight(max(1, min(#items, Twinks.ROWS)) * Twinks.ROW_H)
  pop.list:SetItems(items)
  pop.list:Refresh()
end

function Twinks.openList()
  local pop = state.pop
  if not pop then return false end
  state.listOpen = true
  pop:Show()
  Twinks.refreshList()
  return true
end

function Twinks.closeList()
  local pop = state.pop
  state.listOpen = false
  if not pop then return false end
  Twinks.closeMenu()
  local w = W()
  for _, row in ipairs(pop.list.rows) do if w then w.hideTip(row) end end
  pop:Hide()
  return true
end

function Twinks.toggleList()
  if state.listOpen then return Twinks.closeList() end
  return Twinks.openList()
end

function Twinks.openMenu(row, it)
  local pop = state.pop
  if not (pop and it and not it.own) then return false end
  local ctx = pop.ctx
  ctx.button.item = it
  ctx.button.text:SetText(it.hidden and T.unhideAction or T.hideAction)
  ctx:ClearAllPoints()
  ctx:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", -6, 6)
  pop.ctxCatcher:Show()
  ctx:Show()
  return true
end

function Twinks.closeMenu()
  local pop = state.pop
  if not pop then return end
  pop.ctx:Hide()
  pop.ctxCatcher:Hide()
end

-- "take off the list" is a pure UI marker (Roster.hide/unhide); the character's data stay untouched
function Twinks.toggleHidden(it)
  local R = Journal.Roster
  if not (R and it and it.guid) then return false end
  local ok = false
  if it.hidden then ok = R.unhide(it.guid) else ok = R.hide(it.guid) end
  Twinks.updateButton()
  Twinks.refreshList()
  return ok
end

-- open a book (or go back with the own row). The synchronous guest build would freeze the frame before anything is drawn, so
-- the band shows "ink is drying" first and the build starts one short moment later.
function Twinks.pick(it)
  if type(it) ~= "table" then return false end
  local P = pagesApi()
  if not P then return false end
  if it.own then
    Twinks.closeList()
    if guestNow() then P.setGuest(nil) end
    return true
  end
  if not it.openable then return false end
  Twinks.closeList()
  state.pending = it.guid
  Twinks.showBand(it.name, true)
  local function go()
    if state.pending ~= it.guid then return end
    state.pending = nil
    local ok = P.setGuest(it.guid)
    if not ok then Twinks.onGuest(guestNow() and guestNow().guid or nil) end
  end
  if C_Timer and C_Timer.After then C_Timer.After(Twinks.DEFER, go) else go() end
  return true
end

-------------------------------------------------------------------------------------------------------------------- band

local function buildBand(f, over)
  local th, w, d = Theme(), W(), D()
  local F = Journal.Frame
  local R = F.RIGHT
  local band = CreateFrame("Frame", nil, f)
  band:SetFrameLevel(over:GetFrameLevel() + 8)
  band:SetSize(R.w, Twinks.BAND_H)
  band:SetPoint("TOPLEFT", f, "TOPLEFT", F.RIM + R.x, -(F.RIM + 4))
  band.slip = d.NewSlip(band)
  -- small seal ("on loan"): bronze ring with the books motif, deliberately quiet
  local seal = CreateFrame("Frame", nil, band)
  seal:SetSize(36, 36)
  seal:SetPoint("LEFT", band, "LEFT", -8, -1)
  seal:SetFrameLevel(band:GetFrameLevel() + 2)
  local motif = seal:CreateTexture(nil, "ARTWORK")
  motif:SetSize(36 * th.SEAL_MOTIF_SCALE, 36 * th.SEAL_MOTIF_SCALE)
  motif:SetPoint("CENTER", seal, "CENTER", 0, 0)
  motif:SetTexture(th.TEX.seals)
  motif:SetTexCoord(th.sealCoords(Twinks.SEAL_INDEX))
  motif:SetAlpha(0.85)
  local ringTex = seal:CreateTexture(nil, "OVERLAY")
  ringTex:SetAllPoints(seal)
  ringTex:SetTexture(th.TEX.sealFrames)
  ringTex:SetTexCoord(th.sealFrameCoords("bronze"))
  ringTex:SetAlpha(0.9)
  band.seal = seal
  local text = d.font(band, "hand", 17, "ink")
  text:SetPoint("LEFT", band, "LEFT", 34, 0)
  text:SetJustifyH("LEFT")
  text:SetWordWrap(false)
  band.text = text
  local back = d.NewBack(band, T.backToOwn, function()
    local P = pagesApi()
    if P then P.setGuest(nil) end
  end, { size = 13, esc = false, tip = { T.backTip, T.backTipText } })
  back:SetPoint("RIGHT", band, "RIGHT", -14, 0)
  band.back = back
  band:Hide()
  state.band = band
end

-- atlas cell of the "books" motif in Media/Seals (Chronik.SEALS field cell = position in SEAL_MOTIF_IDS)
Twinks.SEAL_INDEX = 13

function Twinks.showBand(name, loading)
  local band = state.band
  if not band then return false end
  local nm = name or T.unknownName
  band.text:SetText(loading and T("bandLoading", nm) or T("bandReading", nm))
  local backW = tonumber(band.back:GetWidth()) or 150
  local avail = max(80, band:GetWidth() - 34 - backW - 14)
  local w = W()
  if w and w.fitLine then w.fitLine(band.text, avail, 11) end
  band.back:SetShown(not loading)
  band:Show()
  return true
end

function Twinks.hideBand()
  if state.band then state.band:Hide() end
end

-- Pages.onGuestChange (Frame forwards): band and button follow the mode
function Twinks.onGuest(guid)
  state.pending = nil
  local g = guid ~= nil and guestNow() or nil
  if g then
    Twinks.showBand(disp(g.fullName or g.name, 40) or T.unknownName, false)
  else
    Twinks.hideBand()
  end
  Twinks.updateButton()
  if state.listOpen then Twinks.refreshList() end
end

function Twinks.build(f, over, gear)
  if state.built then return end
  if not (Journal.Widgets and Journal.Widgets.Diary and Journal.Frame and Theme()) then return end
  state.built = true
  buildButton(f, gear)
  buildList(f, over)
  buildBand(f, over)
  local R = Journal.Roster
  if R and type(R.onChange) == "function" then
    R.onChange(function()
      Twinks.updateButton()
      Twinks.refreshList()
    end)
  end
end

-- the book closes: list and loading state off (Pages.close already returned to the own book)
function Twinks.onClose()
  state.pending = nil
  Twinks.closeList()
  Twinks.hideBand()
end
