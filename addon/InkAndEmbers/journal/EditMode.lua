-- HUD elements in edit mode via the embedded LibEditMode: toast, slip (welcome greeting), card (campfire recap), todo, quick, fire, smoke. Each has an unprotected holder on UIParent
-- (size = scale, opacity = alpha), saved per layout in chars[guid].editMode.layouts. The draft is committed when Blizzard saves
-- (hooksecurefunc SaveLayouts + EventRegistry "EditMode.SavedLayouts"), discarded on revert. Writing into EditModeManagerFrame would taint: own section.
local ADDON_NAME, ns = ...

local Journal = ns.Journal
if not Journal then return end

local floor, max, min = math.floor, math.max, math.min

local EditMode = {}
Journal.EditMode = EditMode

EditMode.IDS = { "toast", "slip", "card", "todo", "quick", "fire", "smoke" }
EditMode.SCALE = { min = 50, max = 150, step = 5, default = 100 }
-- Toasts and cards start smaller (80 %) than the other HUD elements; saved sizes stay as they are. The welcome note keeps its
-- real size by default (125 % x BASE_SCALE 0.8 = 1.0). The smoke signal starts at 100 % (80 % of its real size), as set by hand.
EditMode.SCALE_DEFAULTS = { toast = 80, card = 80, slip = 125, smoke = 100 }
-- Default place of the welcome note: left screen edge, a figure's inset away (Begleiter.CUTOUTS inset), Begleiter.SLIP.y
EditMode.SLIP_INSET = 12
-- Default position of the toasts and cards: the top edge sits TOAST_BELOW_FRAC x screen height under the screen centre (not in the middle of the view)
EditMode.TOAST_BELOW_FRAC = 0.12 -- of the screen height (see Toast.below)
function EditMode.scaleDefault(id) return EditMode.SCALE_DEFAULTS[id] or EditMode.SCALE.default end
EditMode.BASE_SCALE = 0.8   -- 100 % in edit mode = 80 % of the base size
EditMode.ALPHA = { min = 20, max = 100, step = 5, default = 100 }
EditMode.DURATION = { min = 2, max = 30, step = 1 }
EditMode.LEVEL = { toast = 30, slip = 20, card = 10, todo = 10, quick = 10, fire = 10, smoke = 10 }
EditMode.LAYOUTS_MAX = 64
EditMode.NAME_BYTES = 64
EditMode.POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true, BOTTOMLEFT = true,
  BOTTOM = true, BOTTOMRIGHT = true }

EditMode.TEXT = ns.Locale.ns("EditMode", {
  name = { toast = "Chronik: Einblendungen", slip = "Chronik: Willkommen-Gruß", card = "Chronik: Rast-Rückblick",
    todo = "Chronik: Mini-To-Do-Zettel", quick = "Chronik: Schnellnotizen", fire = "Chronik: Zettel am Feuer", smoke = "Chronik: Rauchzeichen" },
  scale = "Größe",
  scaleDesc = "Größe des Elements, 50 bis 150 %.",
  alpha = "Deckkraft",
  alphaDesc = "Wie stark das Element deckt (100 % = voll sichtbar).",
  duration = "Anzeigedauer",
  durationDesc = "So viele Sekunden bleibt eine Einblendung stehen (ohne Ein- und Ausblenden).",
  grow = "Wuchsrichtung",
  growDesc = "Größere Einblendungen wachsen von hier aus nach unten oder nach oben.",
  growDown = "Nach unten",
  growUp = "Nach oben",
  style = "Design",
  styleDesc = "Notizblock oder Schlicht (wie in den Einstellungen).",
  styleQuickDesc = "Notizblock oder Schlicht (wie in den Einstellungen).",
  open = "Öffnen",
  openDesc = "Wann der Zettel ganz aufgeklappt ist (wie in den Einstellungen). Im Bearbeitungsmodus ist er immer offen.",
  locked = "Sperren",
  lockedDesc = "Außerhalb des Bearbeitungsmodus nicht verschiebbar, Größe fest.",
  combat = "Im Kampf ausblenden",
  showTodo = "Mini-To-Do-Zettel",
  showQuick = "Schnellnotizen",
  showDesc = "Standard aus. Dieselbe Einstellung wie auf den Buchseiten und in den Einstellungen.",
  sampleHead = "Neues Gebiet",
  sampleTitle = "Tirisfal",
  sampleSub = { down = "Beispiel · wächst nach unten", up = "Beispiel · wächst nach oben" },
  cardHead = "Am Lagerfeuer",
  cardTitle = "Seit der letzten Rast …",
  cardLines = { "2 Std. unterwegs, 5 km", "12 Kills · 3 Quests abgegeben" },
  slipTitle = "Willkommen zurück,",
  slipName = "Reisende.",
  slipLines = { "Zuletzt: Tirisfal · vor 9 Std.", "3 offene Quests · Ruhebonus 40 %" },
  todoSamples = {
    { kind = "item", text = "Hasenpfoten sammeln", extra = "4/10" },
    { kind = "place", text = "Den Leuchtturm besuchen", extra = "120 m" },
    { kind = "kill", text = "Kobolde vertreiben", extra = "7/12" },
    { kind = "free", text = "Gewürzbrot backen" },
  },
  panelTitle = "Ink & Embers",
  panelHint = "Im Bearbeitungsmodus zeigen",
  panelNames = { toast = "Einblendungen", slip = "Willkommen-Gruß", card = "Rast-Rückblick", todo = "Mini-To-Do-Zettel", quick = "Schnellnotizen", fire = "Zettel am Feuer", smoke = "Rauchzeichen" },
  dirty = "Ungespeicherte Änderungen",
  clean = "Alles gespeichert",
  save = "Speichern",
  discard = "Verwerfen",
  confirm = "Chronik: Die Änderungen an den HUD-Elementen sind noch nicht gespeichert.",
  diagOff = "Bearbeitungsmodus: nicht angebunden (LibEditMode oder Bearbeitungsmodus fehlt).",
  diagMain = "Bearbeitungsmodus: %d Elemente; Haken Speichern %s, Ereignis %s, Rückgängig %s, Änderungsflag %s; Entwurf %s.",
  yes = "ja",
  no = "nein",
  draftDirty = "ungespeichert",
  draftOpen = "offen",
  draftNone = "keiner",
})
local T = EditMode.TEXT

-- draft: draft of the layout values (nil = none open), gear: gear values on entering, blizzChanges / blizzPrev: Blizzard's change
-- flag now / before the last SetHasActiveChanges, revertPending: revert scheduled (next frame), hooks: which Blizzard hooks sit
local st = { holders = {}, editing = false, layout = nil, draft = nil, gear = nil, blizzChanges = false, blizzPrev = false,
  revertPending = false, hooks = {} }
EditMode.state = st
EditMode.active = false

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end
local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end
local function safe(fn, ...)
  if ns.Core and ns.Core.safe then return ns.Core.safe(fn, ...) end
  return pcall(fn, ...)
end

local function Toast() return Journal.Toast end
local function TT() return Journal.TodoTracker end
local function QN() return Journal.QuickNote end
local function FN() return Journal.FireNotes end
local function SM() return Journal.Smoke end
local function BG() return Journal.Begleiter end

local function layoutKey(name)
  if isSecret(name) or type(name) ~= "string" or name == "" then return "_" end
  return string.sub(name, 1, EditMode.NAME_BYTES)
end

local function emStore(create)
  local Store = ns.Store
  local char = Store and Store.char and Store.char()
  if type(char) ~= "table" then return nil end
  local em = char.editMode
  if type(em) ~= "table" or isSecret(em) then
    if not create then return nil end
    em = { base = EditMode.BASE_SCALE }
    char.editMode = em
  end
  return em
end

local function layouts(create)
  local em = emStore(create)
  if not em then return nil end
  if type(em.layouts) ~= "table" or isSecret(em.layouts) then
    if not create then return nil end
    em.layouts = {}
    em.base = EditMode.BASE_SCALE
  end
  local base = type(em.base) == "number" and em.base > 0 and em.base or 1
  if base ~= EditMode.BASE_SCALE then
    local f = base / EditMode.BASE_SCALE
    for _, l in pairs(em.layouts) do
      if type(l) == "table" then
        for _, e in pairs(l) do
          local p = type(e) == "table" and e.pos
          if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then p.x, p.y = p.x * f, p.y * f end
        end
      end
    end
    em.base = EditMode.BASE_SCALE
  end
  return em.layouts
end

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function copy(t, depth)
  if type(t) ~= "table" or depth > 4 then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v, depth + 1) end
  return out
end

local function same(a, b, depth)
  if type(a) ~= "table" or type(b) ~= "table" or depth > 4 then return a == b end
  for k, v in pairs(a) do
    if not same(v, b[k], depth + 1) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function working(create)
  if st.draft then return st.draft end
  return layouts(create)
end

local function entry(id, create, layout)
  local all = working(create)
  if not all then return nil end
  local key = layoutKey(layout or st.layout)
  local l = all[key]
  if type(l) ~= "table" or isSecret(l) then
    if not create or count(all) >= EditMode.LAYOUTS_MAX then return nil end
    l = {}
    all[key] = l
  end
  local e = l[id]
  if type(e) ~= "table" or isSecret(e) then
    if not create then return nil end
    e = {}
    l[id] = e
  end
  return e
end

local function clampPct(v, R)
  v = num(v)
  if not v then return nil end
  return max(R.min, min(R.max, floor(v + 0.5)))
end

function EditMode.values(id, layout)
  local e = entry(id, false, layout) or {}
  local out = {
    scale = clampPct(e.scale, EditMode.SCALE) or EditMode.scaleDefault(id),
    alpha = clampPct(e.alpha, EditMode.ALPHA) or EditMode.ALPHA.default,
    duration = clampPct(e.duration, EditMode.DURATION),
    grow = (e.grow == "up") and "up" or "down",
  }
  local p = e.pos
  if type(p) == "table" and not isSecret(p) and EditMode.POINTS[p.point] and (p.rel == nil or EditMode.POINTS[p.rel])
    and num(p.x) and num(p.y) and math.abs(p.x) <= 10000 and math.abs(p.y) <= 10000 then
    out.pos = { point = p.point, rel = p.rel or p.point, x = p.x, y = p.y }
  end
  return out
end

function EditMode.set(id, key, value, layout)
  local e = entry(id, value ~= nil, layout)
  if not e then return value == nil end
  if key == "scale" or key == "alpha" or key == "duration" then
    local R = key == "scale" and EditMode.SCALE or (key == "alpha" and EditMode.ALPHA or EditMode.DURATION)
    if value ~= nil then
      value = clampPct(value, R)
      if not value then return false end
    end
    if key == "scale" and type(e.pos) == "table" and num(e.pos.x) and num(e.pos.y) then
      local dflt = key == "scale" and EditMode.scaleDefault(id) or R.default
      local old = (clampPct(e.scale, R) or dflt) / 100
      local new = (value or dflt) / 100
      e.pos.x, e.pos.y = e.pos.x * old / new, e.pos.y * old / new
    end
    e[key] = value
  elseif key == "grow" then
    if value ~= nil and value ~= "up" and value ~= "down" then return false end
    e.grow = value
  elseif key == "pos" then
    if value == nil then
      e.pos = nil
      return true
    end
    if type(value) ~= "table" or not EditMode.POINTS[value.point] or (value.rel ~= nil and not EditMode.POINTS[value.rel])
      or not num(value.x) or not num(value.y) then return false end
    e.pos = { point = value.point, rel = value.rel, x = floor(value.x * 10 + 0.5) / 10, y = floor(value.y * 10 + 0.5) / 10 }
  else
    return false
  end
  return true
end

local function screenSize()
  local sw = UIParent and UIParent.GetWidth and num(UIParent:GetWidth()) or nil
  local sh = UIParent and UIParent.GetHeight and num(UIParent:GetHeight()) or nil
  return (sw and sw > 0) and sw or 1920, (sh and sh > 0) and sh or 1080
end

function EditMode.natural(id)
  local To = Toast()
  if id == "toast" then return To and To.W or 288, To and To.H or 120 end
  if id == "card" then return To and To.CARD.w or 640, To and To.CARD.h or 381 end
  if id == "slip" then return BG() and BG().SLIP.w or 420, BG() and BG().SLIP.h or 232 end
  if id == "todo" then
    local s = TT() and TT().settings()
    return s and s.w or 250, s and s.h or 250
  end
  if id == "fire" then
    local F = FN()
    return F and F.W or 688, F and F.H or 134
  end
  if id == "smoke" then
    local S = SM()
    return S and S.W or 660, S and S.H or 160
  end
  local Q = QN()
  return Q and Q.W or 250, Q and Q.H or 130
end

function EditMode.defaultPos(id)
  local To = Toast()
  if id == "toast" or id == "card" then
    -- both share one place: top edge slightly below the screen centre (holder is centred, so half its height is added)
    local k = EditMode.values(id).scale / 100 * EditMode.BASE_SCALE
    local _, hh = EditMode.natural(id)
    return { point = "CENTER", x = 0, y = -((To and To.below and To.below() or 90) + hh * k / 2) }
  end
  if id == "slip" then return { point = "LEFT", x = EditMode.SLIP_INSET, y = BG() and BG().SLIP.y or -40 } end
  if id == "todo" then return { point = "TOPRIGHT", x = -40, y = -250 } end
  if id == "fire" then
    local p = FN() and FN().DEFAULT_POS or { point = "CENTER", x = 0, y = 60 }
    return { point = p.point, x = p.x, y = p.y }
  end
  if id == "smoke" then
    return { point = "TOP", x = 0, y = SM() and SM().defaultY() or -10 }
  end
  return { point = "TOPRIGHT", x = -40, y = -530 }
end

local function fallbackPos(id, k)
  local p
  if id == "todo" and TT() then p = TT().settings().pos
  elseif id == "quick" and QN() then p = QN().settings().pos end
  if p and num(p.x) and num(p.y) then
    local w, h = EditMode.natural(id)
    local sw, sh = screenSize()
    local x = max(0, min(p.x, sw - w * k))
    local y = min(sh, max(p.y, h * k))
    return { point = "TOPLEFT", rel = "BOTTOMLEFT", x = x / k, y = y / k }
  end
  local d = EditMode.defaultPos(id)
  return { point = d.point, rel = d.point, x = d.x / k, y = d.y / k }
end

local function sampleLine(parent, Theme, kind, size, color, x, y, w)
  local fs = Theme.fontString(parent, kind, size, color, "OVERLAY", "CENTER", true)
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  fs:SetWidth(w)
  fs:SetWordWrap(false)
  return fs
end

-- Welcome note preview: the same layers as the real note (Begleiter.slipFrame): narrator backdrop and figure behind the frame
-- texture, the cut-out in front, sample text on the parchment. refresh() picks the narrator again (own race / random / fixed).
local function buildSlipPreview(h)
  local Theme, B = Journal.Theme, BG()
  if not (Theme and B and B.SLIP) then return nil end
  local S = B.SLIP
  local p = CreateFrame("Frame", nil, h)
  p:SetAllPoints(h)
  p.portrait = p:CreateTexture(nil, "BACKGROUND")
  local ps = B.slipPortraitTex()
  p.portrait:SetSize(ps, ps)
  p.portrait:SetPoint("CENTER", p, "TOPLEFT", S.circleX, -(S.circleY + floor(6 * ps / 512 + 0.5)))
  p.figIn = p:CreateTexture(nil, "BACKGROUND", nil, 1)
  p.cutout = p:CreateTexture(nil, "OVERLAY", nil, 3)
  p.paper = p:CreateTexture(nil, "ARTWORK")
  p.paper:SetAllPoints(p)
  if Theme.TEX.welcomeBack then p.paper:SetTexture(Theme.TEX.welcomeBack) end
  local TT = Journal.TodoTracker
  local function text(size, r, g, b)
    local fs
    if TT and TT.fontString and TT.setFont then
      fs = TT.fontString(p, "OVERLAY")
      TT.setFont(fs, "text", size)
    else
      fs = p:CreateFontString(nil, "OVERLAY")
    end
    fs:SetTextColor(r, g, b)
    fs:SetWidth(S.textW)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    return fs
  end
  p.title = text(S.titleSize, 0.36, 0.12, 0.07)
  p.body = text(S.bodySize, 0.20, 0.13, 0.07)
  p.body:SetSpacing(3)
  p.title:SetText(T.slipTitle .. "\n" .. T.slipName)
  p.body:SetText(table.concat(T.slipLines, "\n"))
  -- text block centred on the parchment like the real note (two lines of title, then the body)
  local th, bh = 2 * (S.titleSize + 4), #T.slipLines * (S.bodySize + 5)
  local top = floor(max(S.textTop, S.textTop + ((S.textBottom - S.textTop) - (th + 4 + bh)) / 2) + 0.5)
  p.title:SetPoint("TOPLEFT", p, "TOPLEFT", S.textX, -top)
  p.body:SetPoint("TOPLEFT", p, "TOPLEFT", S.textX, -(top + th + 4))
  function p.refresh()
    local nar = B.narrator()
    local tex = nar and Theme.narratorTex and Theme.narratorTex(nar) or nil
    local co = nar and B.CUTOUTS[nar] or nil
    local out = co and Theme.TEX["narratorFigOut_" .. nar] or nil
    local inn = co and Theme.TEX["narratorFigIn_" .. nar] or nil
    p.portrait:SetShown(tex ~= nil)
    if tex then p.portrait:SetTexture(tex) end
    p.portrait:SetVertexColor(1, 1, 1)
    p.figIn:Hide()
    p.cutout:Hide()
    if out and inn then
      for _, t in ipairs({ { p.cutout, out }, { p.figIn, inn } }) do
        t[1]:SetTexture(t[2])
        t[1]:SetSize(co.w, co.h)
        t[1]:ClearAllPoints()
        t[1]:SetPoint("TOPLEFT", p, "TOPLEFT", co.x, -co.y)
        t[1]:Show()
      end
      local bg = Theme.TEX["narratorBG_" .. nar]
      if bg then p.portrait:SetTexture(bg) end
      p.portrait:SetVertexColor(co.dim, co.dim, co.dim)
    end
  end
  p.refresh()
  p:Hide()
  return p
end

local function buildPreview(h, id)
  local Theme, To = Journal.Theme, Toast()
  if not (Theme and To and Theme.fontString) then return nil end
  if id == "slip" then return buildSlipPreview(h) end
  local p = CreateFrame("Frame", nil, h)
  p:SetAllPoints(h)
  local paper = p:CreateTexture(nil, "BACKGROUND")
  paper:SetAllPoints(p)
  local icon = p:CreateTexture(nil, "ARTWORK")
  local seal = Theme.TEX.zoneSeal or Theme.TEX.toast
  icon:SetTexture(seal)
  if id == "card" then
    local C = To.CARD
    paper:SetTexture(Theme.TEX[C.tex] or Theme.TEX.toast)
    icon:SetSize(C.iconSize, C.iconSize)
    icon:SetPoint("CENTER", p, "TOPLEFT", C.iconX, -C.iconY)
    local y = C.textY.center - 50
    p.head = sampleLine(p, Theme, "title", C.FONT.head, Theme.C.sepia, C.textX, y, C.textW)
    p.title = sampleLine(p, Theme, "title", C.FONT.title, Theme.C.ink, C.textX, y + C.headH, C.textW)
    p.lines = {}
    for i, text in ipairs(T.cardLines) do
      p.lines[i] = sampleLine(p, Theme, "text", C.FONT.line, i == 1 and Theme.C.ink or Theme.C.sepia, C.textX,
        y + C.headH + C.titleH + C.gap + (i - 1) * (C.pitch + C.entryGap), C.textW)
      p.lines[i]:SetText(text)
    end
    p.head:SetText(T.cardHead)
    p.title:SetText(T.cardTitle)
  else
    paper:SetTexture(Theme.TEX.toast)
    icon:SetSize(To.ICON_ZONE, To.ICON_ZONE)
    icon:SetPoint("CENTER", p, "TOPLEFT", To.ICON_X, -To.ICON_Y)
    local w = To.W - To.TEXT_X - To.TEXT_RIGHT
    p.head = sampleLine(p, Theme, "title", To.FONT.head, Theme.C.sepia, To.TEXT_X, To.TEXT_Y.head, w)
    p.title = sampleLine(p, Theme, "title", To.FONT.title, Theme.C.ink, To.TEXT_X, To.TEXT_Y.title, w)
    p.sub = sampleLine(p, Theme, "text", To.FONT.sub, Theme.C.sepia, To.TEXT_X, To.TEXT_Y.sub, w)
    p.head:SetText(T.sampleHead)
    p.title:SetText(T.sampleTitle)
  end
  p.paper, p.icon = paper, icon
  p:Hide()
  return p
end

local function holder(id) return st.holders[id] end
EditMode.holder = holder

local function newHolder(id)
  local h = CreateFrame("Frame", "EveNChronicleEditMode" .. string.upper(string.sub(id, 1, 1)) .. string.sub(id, 2), UIParent)
  local w, hh = EditMode.natural(id)
  h:SetSize(w, hh)
  h:SetFrameStrata((id == "toast" or id == "card" or id == "slip") and "DIALOG" or "MEDIUM")
  if h.SetClampedToScreen then h:SetClampedToScreen(true) end
  if h.SetDontSavePosition then h:SetDontSavePosition(true) end
  h:EnableMouse(false)
  h:SetFrameLevel(EditMode.LEVEL[id] or 10)
  h.editModeName = T.name[id]
  h.elementId = id
  if id == "toast" or id == "card" or id == "slip" then h.preview = buildPreview(h, id) end
  if id == "fire" and FN() and FN().buildPreview then h.preview = FN().buildPreview(h) end
  if id == "smoke" and SM() and SM().buildPreview then h.preview = SM().buildPreview(h) end
  h:Show()
  st.holders[id] = h
  return h
end

function EditMode.apply(id)
  local h = holder(id)
  if not h then return false end
  local v = EditMode.values(id)
  local k = v.scale / 100 * EditMode.BASE_SCALE
  h:SetScale(k)
  h:SetAlpha(v.alpha / 100)
  local w, hh = EditMode.natural(id)
  h:SetSize(w, hh)
  local p = v.pos or fallbackPos(id, k)
  local d, d0 = st.defaults and st.defaults[id], EditMode.defaultPos(id)
  if d then d.x, d.y = d0.x / k, d0.y / k end
  h:ClearAllPoints()
  h:SetPoint(p.point, UIParent, p.rel or p.point, p.x, p.y)
  if h.preview and h.preview.sub then h.preview.sub:SetText(T.sampleSub[v.grow]) end
  return true
end

local function attachCurrentToast()
  local To = Toast()
  local f, item = To and To.getFrame and To.getFrame(), To and To.getCurrent and To.getCurrent()
  if f and item and To.hud then To.hud.place(f, item) end
end

function EditMode.applyAll()
  for _, id in ipairs(EditMode.IDS) do EditMode.apply(id) end
  attachCurrentToast()
  if TT() and TT().state.frame then TT().place() end
  if QN() and QN().state.frame then QN().place() end
  if FN() and FN().state.frame then FN().place() end
  if SM() and SM().state.frame then SM().place() end
end

function EditMode.toastId(item)
  local key = type(item) == "table" and item.key or nil
  -- the big card is only the campfire recap now; the welcome greeting is the note ("slip", Begleiter.slipSpot)
  if type(key) == "string" and string.sub(key, 1, 5) == "rest:" then return "card" end
  return "toast"
end

local hud = {}

function hud.toastPlace(f, item)
  local id = EditMode.toastId(item)
  local h = holder(id)
  if not h then return false end
  local v = EditMode.values(id)
  if f:GetParent() ~= h then f:SetParent(h) end
  f:SetFrameStrata("DIALOG")
  f:SetScale(1)
  f:ClearAllPoints()
  if v.grow == "up" then f:SetPoint("BOTTOM", h, "BOTTOM", 0, 0) else f:SetPoint("TOP", h, "TOP", 0, 0) end
  return true
end

function hud.toastDuration(item)
  return EditMode.values(EditMode.toastId(item)).duration
end

local function framePlace(id, f)
  local h = holder(id)
  if not h then return false end
  EditMode.apply(id)
  if f:GetParent() ~= h then f:SetParent(h) end
  f:SetFrameStrata("MEDIUM")
  f:ClearAllPoints()
  -- Mini to-do note, unfold upward: the collapsed head sits at the bottom edge of the holder, the note rolls out above it
  if id == "todo" and TT() and TT().settings().grow == "up" then
    f:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
  else
    f:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
  end
  return true
end

local function frameMoved(id, f)
  local h = holder(id)
  if not h then return false end
  local l, t = num(f:GetLeft()), num(f:GetTop())
  if not l or not t then return true end
  if id == "todo" and TT() and TT().settings().grow == "up" and f.GetBottom then
    local b = num(f:GetBottom())
    if b then t = b + select(2, EditMode.natural(id)) end
  end
  EditMode.set(id, "pos", { point = "TOPLEFT", rel = "BOTTOMLEFT", x = l, y = t })
  EditMode.apply(id)
  return true
end

local function refreshDialog(id)
  local lib, h = st.lib, holder(id)
  if lib and h and type(lib.RefreshFrameSettings) == "function" then pcall(lib.RefreshFrameSettings, lib, h) end
end
EditMode.refreshDialog = refreshDialog

local GEAR = { style = "setStyle", locked = "setLocked", combatHide = "setCombatHide", open = "setOpen", grow = "setGrow" }

local function gearNow()
  local Tr = TT()
  if not (Tr and holder("todo") and Tr.settings) then return nil end
  local s = Tr.settings()
  local out = {}
  for key in pairs(GEAR) do out[key] = s[key] end
  local Q = QN()
  if Q and Q.settings then out.quickStyle = Q.settings().style end
  return out
end

local function gearChanged()
  local g, now = st.gear, gearNow()
  if not (g and now) then return false end
  for key in pairs(GEAR) do
    if g[key] ~= now[key] then return true end
  end
  return g.quickStyle ~= now.quickStyle
end

function EditMode.isDirty()
  if not st.draft then return false end
  return not same(st.draft, layouts(false) or {}, 0) or gearChanged()
end

local function beginDraft()
  local all = layouts(true)
  st.draft = all and copy(all, 0) or nil
  st.gear = gearNow()
end

local function endDraft()
  st.draft, st.gear = nil, nil
end

local updatePanel, hideConfirm

function EditMode.commit()
  st.revertPending = false -- MakeNewLayout: RevertAllChanges first, then SaveLayouts -> the draft stays and is committed
  if not st.draft then return false end
  local em = emStore(true)
  if em then em.layouts = copy(st.draft, 0) end
  if st.editing then
    st.gear = gearNow()
  else
    endDraft()
  end
  hideConfirm()
  updatePanel()
  return true
end

function EditMode.revert()
  st.revertPending = false
  if not st.draft then return false end
  local g = st.gear
  if st.editing then
    st.draft = copy(layouts(false) or {}, 0)
  else
    endDraft()
  end
  local Tr = TT()
  if g and Tr and Tr.settings then
    local s = Tr.settings()
    for key, setter in pairs(GEAR) do
      if s[key] ~= g[key] and type(Tr[setter]) == "function" then safe(Tr[setter], g[key]) end
    end
  end
  local Q = QN()
  if g and g.quickStyle and Q and Q.settings and Q.settings().style ~= g.quickStyle then safe(Q.setStyle, g.quickStyle) end
  EditMode.applyAll()
  for _, id in ipairs(EditMode.IDS) do refreshDialog(id) end
  hideConfirm()
  updatePanel()
  return true
end

local function onBlizzardSave() safe(EditMode.commit) end

-- Hook: Blizzard reverts changes (also on a normal leave): discard the draft only if Blizzard itself had unsaved changes.
-- RevertAllChanges resets the flag before this post-hook runs, so the state before the last SetHasActiveChanges (blizzPrev) decides.
-- Discard one frame later (or at once on leaving): MakeNewLayout reverts and saves right after.
local function flushRevert()
  if st.revertPending then safe(EditMode.revert) end
end
EditMode.flushRevert = flushRevert

local function onBlizzardRevert()
  local M = EditModeManagerFrame
  local open = type(M) == "table" and type(M.IsShown) == "function" and M:IsShown() and true or false
  local had
  if st.hooks.SetHasActiveChanges then had = st.blizzPrev or st.blizzChanges else had = open end
  if not had or not st.draft then return end
  st.revertPending = true
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(0, flushRevert)
  else
    flushRevert()
  end
end

-- Track Blizzard's change flag exactly (also false: change turned back by hand, saved, reverted)
local function onBlizzardChanges(_, has)
  st.blizzPrev = st.blizzChanges
  st.blizzChanges = has and true or false
end

-- Only post-hooks (hooksecurefunc) and an EventRegistry callback: nothing is written into Blizzard tables, no method replaced
local function hookBlizzard()
  local M = EditModeManagerFrame
  if type(M) ~= "table" or type(hooksecurefunc) ~= "function" then return end
  local hooks = { { "SaveLayouts", onBlizzardSave }, { "RevertAllChanges", onBlizzardRevert },
    { "SetHasActiveChanges", onBlizzardChanges } }
  for _, hk in ipairs(hooks) do
    if type(M[hk[1]]) == "function" and pcall(hooksecurefunc, M, hk[1], hk[2]) then st.hooks[hk[1]] = true end
  end
  local ER = rawget(_G, "EventRegistry")
  if type(ER) == "table" and type(ER.RegisterCallback) == "function" then
    if pcall(ER.RegisterCallback, ER, "EditMode.SavedLayouts", onBlizzardSave, EditMode) then st.hooks.SavedLayouts = true end
  end
end
EditMode.hookBlizzard = hookBlizzard

-- is the element in use at all? The campfire recap only exists while its option is on (default off).
function EditMode.available(id)
  if id == "card" then
    local B = BG()
    return B ~= nil and type(B.restOn) == "function" and B.restOn() == true
  end
  -- the to-do note docked to the quest tracker follows the tracker: no own position, no edit-mode entry
  if id == "todo" then
    local Tr = TT()
    return not (Tr and type(Tr.docked) == "function" and Tr.docked())
  end
  return true
end

function EditMode.shownInEdit(id)
  local em = emStore(false)
  local hid = em and em.hidden
  return not (type(hid) == "table" and not isSecret(hid) and hid[id] == true)
end

local function backdrop(f)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)
  end
end

local function button(parent, text, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  b:SetText(text)
  b:SetScript("OnClick", function() safe(onClick) end)
  return b
end

local function setEnabled(b, on)
  if b.SetEnabled then b:SetEnabled(on) end
  b.enabled = on
end

local PANEL = { w = 210, row = 24, top = 30 }

local function buildPanel()
  local p = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  p:SetSize(PANEL.w, PANEL.top + 18 + #EditMode.IDS * PANEL.row + 64)
  -- next to Blizzard's edit window: only our frame is attached, Blizzard's frame stays untouched
  p:SetPoint("TOPLEFT", EditModeManagerFrame, "TOPRIGHT", 6, 0)
  p:SetFrameStrata("DIALOG")
  p:SetClampedToScreen(true)
  p:EnableMouse(true)
  backdrop(p)
  local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -10)
  title:SetText(T.panelTitle)
  local hint = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -PANEL.top)
  hint:SetText(T.panelHint)
  p.checks = {}
  for i, id in ipairs(EditMode.IDS) do
    local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -(PANEL.top + 14 + (i - 1) * PANEL.row))
    local label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    label:SetText(T.panelNames[id] or id)
    cb.label = label
    cb:SetScript("OnClick", function() safe(EditMode.setShown, id, not EditMode.shownInEdit(id)) end)
    p.checks[id] = cb
  end
  local status = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 12, 38)
  p.status = status
  p.save = button(p, T.save, 90, EditMode.commit)
  p.save:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 10, 10)
  p.discard = button(p, T.discard, 90, EditMode.revert)
  p.discard:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -10, 10)
  p:Hide()
  st.panel = p
  return p
end

updatePanel = function()
  local p = st.panel
  if not p then return end
  -- rows of unavailable elements (campfire recap with its option off) are left out and the rest moves up
  local row = 0
  for _, id in ipairs(EditMode.IDS) do
    local cb = p.checks[id]
    if cb then
      local on = EditMode.shownInEdit(id)
      cb:SetChecked(on)
      cb.checked = on
      local avail = EditMode.available(id)
      cb:SetShown(avail)
      if avail then
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -(PANEL.top + 14 + row * PANEL.row))
        row = row + 1
      end
    end
  end
  p:SetHeight(PANEL.top + 18 + row * PANEL.row + 64)
  local dirty = EditMode.isDirty()
  p.status:SetText(dirty and T.dirty or T.clean)
  setEnabled(p.save, dirty)
  setEnabled(p.discard, dirty)
end
EditMode.updatePanel = updatePanel

local function buildConfirm()
  local c = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  c:SetSize(330, 84)
  c:SetPoint("TOP", UIParent, "TOP", 0, -160)
  c:SetFrameStrata("DIALOG")
  c:SetClampedToScreen(true)
  c:EnableMouse(true)
  backdrop(c)
  local text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -12)
  text:SetPoint("TOPRIGHT", c, "TOPRIGHT", -14, -12)
  text:SetJustifyH("CENTER")
  text:SetText(T.confirm)
  c.text = text
  c.save = button(c, T.save, 110, EditMode.commit)
  c.save:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 14, 10)
  c.discard = button(c, T.discard, 110, EditMode.revert)
  c.discard:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -14, 10)
  c:Hide()
  st.confirm = c
  return c
end

local function showConfirm()
  local c = st.confirm or buildConfirm()
  c:Show()
end

hideConfirm = function()
  if st.confirm then st.confirm:Hide() end
end

function EditMode.isConfirmShown() return st.confirm ~= nil and st.confirm:IsShown() and true or false end

local function sampleRows()
  local out = {}
  for i, r in ipairs(T.todoSamples) do
    out[i] = { id = -i, kind = r.kind, text = r.text, extra = r.extra, dist = false, done = false }
  end
  return out
end

local function wantsPreview(id)
  local M = id == "todo" and TT() or QN()
  return M ~= nil and M.settings().shown == true
end

local function startPreview(id)
  if id == "todo" then
    local Tr = TT()
    if not Tr or Tr.state.preview then return end
    local s = Tr.state
    s.preview = true
    local f = Tr.build()
    s.shownList = sampleRows()
    s.sig = nil
    Tr.applyStyle()
    if Tr.syncOpen then Tr.syncOpen() end
    Tr.place()
    Tr.layout()
    f:Show()
  elseif id == "quick" then
    local Q = QN()
    if not Q or Q.state.preview then return end
    Q.state.preview = true
    local f = Q.build()
    Q.place()
    f:Show()
  end
end

local function stopPreview(id)
  if id == "todo" then
    local Tr = TT()
    if not (Tr and Tr.state.preview) then return end
    local s = Tr.state
    s.preview = false
    s.shownList, s.sig = {}, nil
    if s.frame then s.frame:Hide() end
    Tr.refresh()
  elseif id == "quick" then
    local Q = QN()
    if not (Q and Q.state.preview) then return end
    Q.state.preview = false
    if Q.state.frame then Q.state.frame:Hide() end
    Q.refresh()
  end
end

local function showElement(id)
  local h = holder(id)
  if not h then return end
  if not (EditMode.shownInEdit(id) and EditMode.available(id)) then
    if h.preview then h.preview:Hide() end
    if id == "todo" or id == "quick" then stopPreview(id) end
    h:Hide()
    return
  end
  h:Show()
  if h.preview then
    if h.preview.refresh then h.preview.refresh() end
    h.preview:Show()
  end
  if id == "todo" or id == "quick" then
    if wantsPreview(id) then startPreview(id) else stopPreview(id) end
  end
end

local function hideElement(id)
  local h = holder(id)
  if not h then return end
  if h.preview then h.preview:Hide() end
  stopPreview(id)
end

function EditMode.syncPreview()
  if not st.editing then return end
  showElement("todo")
  showElement("quick")
  showElement("card")
  updatePanel()
end

function EditMode.setShown(id, on)
  if not holder(id) then return false end
  local em = emStore(true)
  if not em then return false end
  if type(em.hidden) ~= "table" or isSecret(em.hidden) then em.hidden = {} end
  em.hidden[id] = (not on) and true or nil
  if st.editing then
    if on then
      showElement(id)
    else
      hideElement(id)
      holder(id):Hide()
    end
  end
  updatePanel()
  return true
end

function EditMode.enter()
  st.editing = true
  if not st.draft then beginDraft() end
  hideConfirm()
  for _, id in ipairs(EditMode.IDS) do showElement(id) end
  local p = st.panel or buildPanel()
  updatePanel()
  p:Show()
end

function EditMode.exit()
  -- "Leave without saving": Blizzard's ExitEditMode reverts before this callback -> discard now instead of asking
  flushRevert()
  st.editing = false
  for _, id in ipairs(EditMode.IDS) do
    hideElement(id)
    local h = holder(id)
    if h then h:Show() end
  end
  if st.panel then st.panel:Hide() end
  if EditMode.isDirty() then
    showConfirm()
  else
    endDraft()
  end
end

function EditMode.isEditing() return st.editing end

function EditMode.onLayout(name)
  st.layout = layoutKey(name)
  EditMode.applyAll()
end

-- Create / rename / delete is saved by Blizzard at once: follow in the saved values and in the open draft
local function eachTable(fn)
  local all = layouts(false)
  if all then fn(all) end
  if st.draft and st.draft ~= all then fn(st.draft) end
end

function EditMode.onCreate(name, _, source)
  if source == nil then return end
  eachTable(function(all)
    local from = all[layoutKey(source)]
    if type(from) == "table" and count(all) < EditMode.LAYOUTS_MAX then all[layoutKey(name)] = copy(from, 0) end
  end)
end

function EditMode.onRename(old, new)
  local a, b = layoutKey(old), layoutKey(new)
  eachTable(function(all)
    if a ~= b and all[a] ~= nil then
      all[b], all[a] = all[a], nil
    end
  end)
  if st.layout == a then st.layout = b end
end

function EditMode.onDelete(name)
  eachTable(function(all) all[layoutKey(name)] = nil end)
end

local function pctFormat(v) return string.format("%d %%", floor((tonumber(v) or 0) + 0.5)) end
local function secFormat(v) return string.format("%d s", floor((tonumber(v) or 0) + 0.5)) end

local function after(id)
  EditMode.apply(id)
  if id == "toast" or id == "card" then attachCurrentToast() end
  if id == "todo" and TT() and TT().state.frame then TT().place() end
  if id == "quick" and QN() and QN().state.frame then QN().place() end
  if id == "fire" and FN() and FN().state.frame then FN().place() end
  if id == "smoke" and SM() and SM().state.frame then SM().place() end
  updatePanel()
end

local function pctSetting(lib, id, key, R, name, desc)
  return {
    kind = lib.SettingType.Slider, name = name, desc = desc, default = key == "scale" and EditMode.scaleDefault(id) or R.default,
    minValue = R.min, maxValue = R.max, valueStep = R.step, formatter = pctFormat,
    get = function(layout) return EditMode.values(id, layout)[key] end,
    set = function(layout, value, fromReset)
      safe(function()
        EditMode.set(id, key, fromReset and nil or value, layout)
        after(id)
      end)
    end,
  }
end

local function styleSetting(lib, desc, owner)
  local Tr = TT()
  return {
    kind = lib.SettingType.Dropdown, name = T.style, desc = desc, default = Tr.DEFAULTS.style,
    values = { { text = Tr.TEXT.style.pad, value = "pad" }, { text = Tr.TEXT.style.plain, value = "plain" } },
    get = function() return (owner or Tr).settings().style end,
    set = function(_, value)
      safe((owner or Tr).setStyle, value)
      updatePanel()
    end,
  }
end

local function checkSetting(lib, name, desc, key, setter)
  local Tr = TT()
  return {
    kind = lib.SettingType.Checkbox, name = name, desc = desc, default = Tr.DEFAULTS[key],
    get = function() return Tr.settings()[key] end,
    set = function(_, value)
      safe(setter, value and true or false)
      updatePanel()
    end,
  }
end

function EditMode.settingsFor(lib, id)
  local out = {
    pctSetting(lib, id, "scale", EditMode.SCALE, T.scale, T.scaleDesc),
    pctSetting(lib, id, "alpha", EditMode.ALPHA, T.alpha, T.alphaDesc),
  }
  if id == "toast" or id == "card" then
    local To = Toast()
    local base = id == "card" and (To and To.CARD.duration or 10) or (To and To.DURATION or 5)
    out[#out + 1] = {
      kind = lib.SettingType.Slider, name = T.duration, desc = T.durationDesc, default = base,
      minValue = EditMode.DURATION.min, maxValue = EditMode.DURATION.max, valueStep = EditMode.DURATION.step, formatter = secFormat,
      get = function(layout) return EditMode.values(id, layout).duration or base end,
      set = function(layout, value, fromReset)
        safe(function()
          EditMode.set(id, "duration", fromReset and nil or value, layout)
          updatePanel()
        end)
      end,
    }
    out[#out + 1] = {
      kind = lib.SettingType.Dropdown, name = T.grow, desc = T.growDesc, default = "down",
      values = { { text = T.growDown, value = "down" }, { text = T.growUp, value = "up" } },
      get = function(layout) return EditMode.values(id, layout).grow end,
      set = function(layout, value, fromReset)
        safe(function()
          EditMode.set(id, "grow", (fromReset or value == "down") and nil or value, layout)
          after(id)
        end)
      end,
    }
  elseif id == "todo" then
    local Tr = TT()
    out[#out + 1] = styleSetting(lib, T.styleDesc)
    out[#out + 1] = {
      kind = lib.SettingType.Dropdown, name = T.open, desc = T.openDesc, default = Tr.DEFAULTS.open,
      values = (function()
        local list = {}
        for i, m in ipairs(Tr.OPEN_MODES) do list[i] = { text = Tr.TEXT.openModes[m], value = m } end
        return list
      end)(),
      get = function() return Tr.settings().open end,
      set = function(_, value)
        safe(Tr.setOpen, value)
        updatePanel()
      end,
    }
    out[#out + 1] = {
      kind = lib.SettingType.Dropdown, name = Tr.TEXT.growLabel, desc = Tr.TEXT.growDesc, default = Tr.DEFAULTS.grow,
      values = { { text = Tr.TEXT.grow.down, value = "down" }, { text = Tr.TEXT.grow.up, value = "up" } },
      get = function() return Tr.settings().grow end,
      set = function(_, value)
        safe(Tr.setGrow, value)
        updatePanel()
      end,
    }
    out[#out + 1] = checkSetting(lib, T.locked, T.lockedDesc, "locked", Tr.setLocked)
    out[#out + 1] = checkSetting(lib, T.combat, nil, "combatHide", Tr.setCombatHide)
    out[#out + 1] = checkSetting(lib, T.showTodo, T.showDesc, "shown", Tr.setShown)
  elseif id == "quick" then
    local Q = QN()
    out[#out + 1] = styleSetting(lib, T.styleQuickDesc, Q)
    out[#out + 1] = {
      kind = lib.SettingType.Checkbox, name = T.showQuick, desc = T.showDesc, default = false,
      get = function() return Q.settings().shown end,
      set = function(_, value) safe(Q.setShown, value and true or false) end,
    }
  end
  return out
end

function EditMode.findLib()
  if type(EditModeManagerFrame) ~= "table" then return nil end
  local LS = rawget(_G, "LibStub")
  if LS == nil then return nil end
  local ok, lib = pcall(LS, "LibEditMode", true)
  if not ok or type(lib) ~= "table" then return nil end
  for _, fn in ipairs({ "AddFrame", "AddFrameSettings", "RegisterCallback" }) do
    if type(lib[fn]) ~= "function" then return nil end
  end
  if type(lib.SettingType) ~= "table" then return nil end
  return lib
end

local function register(lib, id)
  local h = newHolder(id)
  local d = EditMode.defaultPos(id)
  st.defaults = st.defaults or {}
  st.defaults[id] = d
  lib:AddFrame(h, function(_, layoutName, point, x, y)
    safe(function()
      EditMode.set(id, "pos", { point = point, x = x, y = y }, layoutName)
      after(id)
    end)
  end, d, T.name[id])
  lib:AddFrameSettings(h, EditMode.settingsFor(lib, id))
  local sel = type(lib.frameSelections) == "table" and lib.frameSelections[h] or nil
  if sel and sel.SetFrameLevel then sel:SetFrameLevel((h:GetFrameLevel() or 1) + 50) end
end

function EditMode.init()
  if EditMode.active then return true end
  local lib = EditMode.findLib()
  if not lib then return false end
  local To, Tr, Q, F, S = Toast(), TT(), QN(), FN(), SM()
  st.lib = lib
  local ids = {}
  if To then ids[#ids + 1] = "toast" end
  if BG() then ids[#ids + 1] = "slip" end
  if To then ids[#ids + 1] = "card" end
  if Tr then ids[#ids + 1] = "todo" end
  if Q then ids[#ids + 1] = "quick" end
  if F then ids[#ids + 1] = "fire" end
  -- WoW Forever only; the Retail test preview (/chronik feuer rauch) falls back to the default position
  if S and S.active() then ids[#ids + 1] = "smoke" end
  local ok, err = pcall(function()
    for _, id in ipairs(ids) do register(lib, id) end
  end)
  if not ok then
    if ns.Core and ns.Core.coreError then ns.Core.coreError(err) end
    return false
  end
  EditMode.IDS = ids
  EditMode.active = true
  if type(lib.GetActiveLayoutName) == "function" then
    local okName, name = pcall(lib.GetActiveLayoutName, lib)
    st.layout = layoutKey(okName and name or nil)
  end
  if To then To.hud = { place = hud.toastPlace, duration = hud.toastDuration } end
  if Tr then
    Tr.hud = {
      place = function(f) return framePlace("todo", f) end,
      moved = function(f) return frameMoved("todo", f) end,
      reset = function() EditMode.set("todo", "pos", nil) EditMode.apply("todo") end,
      sync = function() EditMode.syncPreview() refreshDialog("todo") refreshDialog("quick") end,
    }
  end
  if Q then
    Q.hud = {
      place = function(f) return framePlace("quick", f) end,
      moved = function(f) return frameMoved("quick", f) end,
      sync = function() EditMode.syncPreview() refreshDialog("quick") end,
    }
  end
  if F then
    F.hud = {
      place = function(f)
        local h = holder("fire")
        if not h then return false end
        if f:GetParent() ~= h then f:SetParent(h) end
        f:SetFrameStrata("MEDIUM")
        f:ClearAllPoints()
        f:SetPoint("CENTER", h, "CENTER", 0, 0)
        return true
      end,
    }
  end
  if S and S.active() then
    S.hud = {
      place = function(f)
        local h = holder("smoke")
        if not h then return false end
        if f:GetParent() ~= h then f:SetParent(h) end
        f:SetFrameStrata("MEDIUM")
        f:ClearAllPoints()
        f:SetPoint("CENTER", h, "CENTER", 0, 0)
        return true
      end,
    }
  end
  hookBlizzard()
  lib:RegisterCallback("enter", function() safe(EditMode.enter) end)
  lib:RegisterCallback("exit", function() safe(EditMode.exit) end)
  lib:RegisterCallback("layout", function(name) safe(EditMode.onLayout, name) end)
  lib:RegisterCallback("create", function(name, index, source) safe(EditMode.onCreate, name, index, source) end)
  lib:RegisterCallback("rename", function(old, new) safe(EditMode.onRename, old, new) end)
  lib:RegisterCallback("delete", function(name) safe(EditMode.onDelete, name) end)
  EditMode.applyAll()
  if type(lib.IsInEditMode) == "function" and lib:IsInEditMode() then safe(EditMode.enter) end
  return true
end

function EditMode.diagLine()
  if not EditMode.active then
    return T.diagOff
  end
  local h = st.hooks
  local function yn(v) return v and T.yes or T.no end
  return T("diagMain",
    #EditMode.IDS, yn(h.SaveLayouts), yn(h.SavedLayouts), yn(h.RevertAllChanges), yn(h.SetHasActiveChanges),
    EditMode.isDirty() and T.draftDirty or (st.draft and T.draftOpen or T.draftNone))
end

do
  local hooked = ns.Core and type(ns.Core.on) == "function"
    and ns.Core.on("ADDON_LOADED", function(_, name) if name == ADDON_NAME then safe(EditMode.init) end end)
  if not hooked then safe(EditMode.init) end
end
if ns.Core and ns.Core.on then
  ns.Core.on("PLAYER_ENTERING_WORLD", function()
    if EditMode.active then safe(EditMode.applyAll) end
  end)
end
