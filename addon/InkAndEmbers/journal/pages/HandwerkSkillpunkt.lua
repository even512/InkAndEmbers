-- Block "Für den nächsten Skillpunkt" (right page of the tab Handwerk and the bar at the profession window): ONE clear recommendation on top,
-- then a few compact alternatives (ranking: journal/model/Skillpunkt.lua; data: the recipe cache).
--   Recommendation (HS.newRec, shared by the page and the bar):  "Effizientester Skillpunkt: <recipe> (optimal)" with the colour dot,
--   below "Material reicht für N" or "Es fehlen: 4× Kupferbarren, 1× Grobes Garn" (every item with its original tooltip), the expected
--   number of crafts until the next point ("Bis zum nächsten Punkt ca. 1 Herstellung" / 2 / "4+") and the button "Auf den Einkaufszettel"
--   (the shopping list for exactly those crafts). Without an orange/yellow recipe a hint with a click to Pläne > Handwerk takes its place.
--   Alternatives: dot, name, level word of the recipe book (optimal / medium / easy), "reicht für N" (own book only).
-- Pure drawing: no ticker, rows and chips are fixed in number. HS.build(parent, x, y, w) builds the page block, HS.draw fills it.
local _, ns = ...

local Journal = ns.Journal
local Widgets = Journal and Journal.Widgets
local D = Widgets and Widgets.Diary
local Model = Journal and Journal.Skillpunkt
if not (Journal and Widgets and D and Model) then return end

local Theme = Journal.Theme or {}
local G = Theme.GRID or { size = { xs = 11, s = 12, m = 14 } }
local floor, max, min = math.floor, math.max, math.min

local HS = {}
Journal.HandwerkSkillpunkt = HS

HS.ROW_H = 17
HS.ALTS = 2          -- alternatives on the page (the bar shows fewer or the same)
HS.MISS_MAX = 4      -- missing materials listed as chips
-- difficulty colours (dark enough for the parchment)
HS.RGB = { orange = { 0.82, 0.40, 0.06 }, yellow = { 0.70, 0.56, 0.04 }, green = { 0.24, 0.52, 0.18 } }

HS.TEXT = ns.Locale.ns("p.HandwerkSkillpunkt", {
  head = "FÜR DEN NÄCHSTEN SKILLPUNKT",
  orange = "Orange: fast jede Herstellung bringt einen Skillpunkt",
  yellow = "Gelb: etwa jede zweite Herstellung bringt einen Skillpunkt",
  green = "Grün: nur selten bringt eine Herstellung einen Skillpunkt",
  mats_one = "%s Material", mats_other = "%s Materialien",
  enough = "reicht für %s",
  enoughNone = "nichts da",
  ups = "bis zu %s Skillpunkte je Herstellung",
  more = "+%s weitere",
  best = "Effizientester Skillpunkt: %s",
  enoughLine = "Material reicht für %s",
  missingLabel = "Es fehlen:",
  expect_one = "Bis zum nächsten Punkt ca. %s Herstellung",
  expect_other = "Bis zum nächsten Punkt ca. %s Herstellungen",
  addList = "Auf den Einkaufszettel",
  addTip = { "Auf den Einkaufszettel", "Legt das Rezept für die Herstellungen bis zum nächsten Punkt auf den Einkaufszettel." },
  onList = "Auf dem Zettel",
  onListTip = { "Auf dem Zettel", "Klick öffnet den Einkaufszettel." },
  noSure = "Kein orangenes oder gelbes Rezept mehr – lernt neue beim Lehrer.",
  noSureTip = { "Handwerk", "Klick: zeigt, welche Rezepte Ihr als Nächstes lernen könnt." },
  nocache = "Öffnet das Berufsfenster einmal, dann zeigt sich hier, welches Rezept den nächsten Skillpunkt bringt.",
  nolearned = "Noch kein Rezept dieses Berufs gelernt.",
})
local T = HS.TEXT

local function int(n) return Journal.Texts and Journal.Texts.int and Journal.Texts.int(n) or tostring(floor(tonumber(n) or 0)) end

local function font(parent, kind, size, color, justify)
  local fs = Widgets.font(parent, kind, size, color)
  if justify then fs:SetJustifyH(justify) end
  return fs
end

local function plural(n, key) return T(ns.Locale.plural(n, key .. "_one", key .. "_other"), int(n)) end

-- level word of the recipe book ("optimal" / "medium" / "easy", language of the client)
function HS.levelWord(color)
  local RB = Journal.Rezeptbuch
  local t = RB and RB.TEXT
  local w = t and t["diff_" .. tostring(color)]
  return type(w) == "string" and w or tostring(color)
end

local function safe(fn, ...)
  if ns.Core and ns.Core.safe then return ns.Core.safe(fn, ...) end
  return pcall(fn, ...)
end

-- Pure texts (tested) ----------------------------------------------------------------------------------------------------------------

-- expected crafts until the next point as text: orange 1, yellow 2, green "4+"
function HS.expectText(row)
  local n = row and row.crafts or 1
  local shown = (row and row.d == 2) and (int(n) .. "+") or int(n)
  return T(ns.Locale.plural(n, "expect_one", "expect_other"), shown)
end

-- everything the recommendation says, display-ready:
-- { headline, level, color, status = "enough" | "missing" | nil, enoughLine, missing = { { id, qty, name, text } }, expect }
function HS.describe(row)
  if type(row) ~= "table" then return nil end
  local E = ns.Einkauf
  local d = { color = row.color, level = HS.levelWord(row.color), expect = HS.expectText(row), out = row.out }
  d.headline = T("best", row.name) .. " (" .. d.level .. ")"
  if row.missing ~= nil then
    if #row.missing == 0 then
      d.status = "enough"
      d.enoughLine = T("enoughLine", int(row.n or row.crafts or 1))
    else
      d.status = "missing"
      d.missing = {}
      for i, m in ipairs(row.missing) do
        local nm = E and E.itemName and E.itemName(m.id) or nil
        nm = nm or ("#" .. tostring(m.id))
        d.missing[i] = { id = m.id, qty = m.qty, name = nm, text = int(m.qty) .. "× " .. nm }
      end
    end
  end
  return d
end

-- the shopping list for the crafts of the recommendation: id of the open list of that recipe, or nil
function HS.listed(row)
  local E = ns.Einkauf
  return row and E and E.find and E.find(row.id) or nil
end

-- puts the recommendation on the shopping list (crafts = expected crafts until the next point); an open list is only opened
function HS.addToList(row)
  local E, Z = ns.Einkauf, Journal.Einkaufszettel
  if not (row and E) then return nil end
  local open = HS.listed(row)
  if open then
    if Z and Z.open then Z.open({ id = open }) end
    return open, "open"
  end
  return E.add(row.profID, row.id, row.crafts or 1, false)
end

-- Pläne > Handwerk (what to learn next), opens the book when it is closed
function HS.openPlans()
  local A, F = Journal.Access, Journal.Frame
  if not (A and F) then return false end
  if not A.isOpen() and not A.open() then return false end
  if not F.showPage("plaene") then return false end
  if F.currentSub() ~= "handwerk" then F.showSub("handwerk") end
  return F.currentSub() == "handwerk"
end

-- Recommendation widget ----------------------------------------------------------------------------------------------------------------

-- o: w, wrap (lines may break, bar) | false (one line, page), kind ("label" / "text"), sizes = { head, line }, col = { head, ok, need, dim }
-- (colour specs of Widgets.color), rgb = dot colours per level, newButton(parent) -> button, setLabel(button, text), onPick(row) (click on the
-- headline), onChange() (after the list changed), buttonInline (button right of the "expect" line instead of below it)
function HS.newRec(parent, o)
  local r = { o = o, w = o.w }
  local sizes, col = o.sizes, o.col
  r.dot = Widgets.NewRect(parent, o.rgb.orange, 1, "ARTWORK")
  r.dot:SetSize(8, 8)
  r.head = font(parent, o.kind, sizes.head, col.head, "LEFT")
  r.head:SetWordWrap(o.wrap and true or false)
  r.headHit = CreateFrame("Button", nil, parent)
  r.headHit:SetScript("OnEnter", function(self)
    local row = self.row
    if not row then return end
    local d = HS.describe(row)
    local lines = { row.name, T[row.color or "green"] or "", d and d.expect or "" }
    lines.item = row.out and ("item:" .. tostring(row.out)) or nil
    lines.itemExtra = { lines[2], lines[3] }
    Widgets.tip(self, lines)
  end)
  r.headHit:SetScript("OnLeave", function(self) Widgets.hideTip(self) end)
  r.headHit:SetScript("OnClick", function(self) if self.row and o.onPick then safe(o.onPick, self.row) end end)
  r.status = font(parent, o.kind, sizes.line, col.dim, "LEFT")
  r.status:SetWordWrap(false)
  r.chips = {}
  for i = 1, HS.MISS_MAX do
    local c = CreateFrame("Frame", nil, parent)
    c:EnableMouse(true)
    c.fs = font(c, o.kind, sizes.line, col.need, "LEFT")
    c.fs:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
    c.fs:SetWordWrap(false)
    c:SetScript("OnEnter", function(self)
      if self.id then Widgets.tip(self, { self.title or "", item = "item:" .. tostring(self.id) }) end
    end)
    c:SetScript("OnLeave", function(self) Widgets.hideTip(self) end)
    c:Hide()
    r.chips[i] = c
  end
  r.more = font(parent, o.kind, sizes.line, col.need, "LEFT")
  r.expect = font(parent, o.kind, sizes.line, col.dim, "LEFT")
  r.expect:SetWordWrap(false)
  r.btn = o.newButton(parent)
  r.btn:SetScript("OnClick", function(self)
    if not self.row then return end
    local id = HS.addToList(self.row)
    if o.onChange then safe(o.onChange, id) end
  end)
  r.btn:HookScript("OnEnter", function(self)
    local t = self.listed and T.onListTip or T.addTip
    Widgets.tip(self, t)
  end)
  r.btn:HookScript("OnLeave", function(self) Widgets.hideTip(self) end)
  r.hintBtn = CreateFrame("Button", nil, parent)
  r.hint = font(r.hintBtn, o.kind, sizes.line, col.need, "LEFT")
  r.hint:SetAllPoints(r.hintBtn)
  r.hint:SetWordWrap(o.wrap and true or false)
  r.hintBtn:SetScript("OnClick", function() safe(HS.openPlans) end)
  r.hintBtn:SetScript("OnEnter", function(self)
    local tip = { unpack(T.noSureTip) }
    tip[1] = Journal.PlaenePage and Journal.PlaenePage.TEXT and Journal.PlaenePage.TEXT.subCraft or tip[1]
    Widgets.tip(self, tip)
  end)
  r.hintBtn:SetScript("OnLeave", function(self) Widgets.hideTip(self) end)
  setmetatable(r, { __index = HS.Rec })
  r:Hide()
  return r
end

HS.Rec = {}

local function textHeight(fs, fallback)
  local ok, h = pcall(fs.GetStringHeight, fs)
  h = ok and tonumber(h) or nil
  if not h or h <= 0 then return fallback end
  return h
end

local function textWidth(fs, text)
  local ok, w = pcall(fs.GetStringWidth, fs)
  w = ok and tonumber(w) or nil
  if not w or w <= 0 then return #text * 6 end
  return w
end

function HS.Rec:Hide()
  self.dot:Hide() self.head:Hide() self.headHit:Hide() self.status:Hide() self.more:Hide() self.expect:Hide() self.btn:Hide()
  self.hintBtn:Hide()
  for _, c in ipairs(self.chips) do c:Hide() Widgets.hideTip(c) end
  Widgets.hideTip(self.headHit)
  Widgets.hideTip(self.btn)
end

-- The hint "no orange or yellow recipe left" (click: Pläne > Handwerk) at (x, y); does not touch the rest -> height
function HS.Rec:Hint(x, y)
  local o = self.o
  local lineH = o.sizes.line + 4
  self.hintBtn:ClearAllPoints()
  self.hintBtn:SetPoint("TOPLEFT", self.head:GetParent(), "TOPLEFT", x, -y)
  self.hintBtn:SetSize(self.w, lineH)
  Widgets.setText(self.hint, T.noSure)
  if not o.wrap then Widgets.fitLine(self.hint, self.w, 9) end
  self.hintBtn:Show()
  local h = o.wrap and textHeight(self.hint, lineH) or lineH
  self.hintBtn:SetHeight(h)
  return h + 2
end

-- Draws the recommendation with its top left at (x, y) of the parent. row = Skillpunkt row | nil; ctx = { own, noSure } -> height used
function HS.Rec:Set(row, ctx, x, y)
  local o = self.o
  ctx = ctx or {}
  self:Hide()
  local lineH = o.sizes.line + 4
  local headH = max(o.sizes.head, o.sizes.line) + 4
  if not row then
    if not ctx.noSure then return 0 end
    return self:Hint(x, y)
  end
  local d = HS.describe(row)
  local parent = self.head:GetParent()
  local cy = y
  local rgb = o.rgb[row.color] or o.rgb.green
  self.dot:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
  self.dot:ClearAllPoints()
  self.dot:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(cy + 3))
  self.dot:Show()
  self.head:ClearAllPoints()
  self.head:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 14, -cy)
  self.head:SetWidth(self.w - 14)
  Widgets.setText(self.head, d.headline)
  if not o.wrap then Widgets.fitLine(self.head, self.w - 14, 10) end
  self.head:Show()
  local hh = o.wrap and textHeight(self.head, headH) or headH
  self.headHit:ClearAllPoints()
  self.headHit:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -cy)
  self.headHit:SetSize(self.w, hh)
  self.headHit.row = row
  self.headHit:Show()
  cy = cy + hh + 2
  -- status: material is enough / what is missing (chips)
  if d.status == "enough" then
    self.status:ClearAllPoints()
    self.status:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 14, -cy)
    self.status:SetWidth(self.w - 14)
    self.status:SetTextColor(Widgets.color(o.col.ok))
    Widgets.setText(self.status, d.enoughLine)
    self.status:Show()
    cy = cy + lineH
  elseif d.status == "missing" then
    self.status:ClearAllPoints()
    self.status:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 14, -cy)
    self.status:SetTextColor(Widgets.color(o.col.need))
    Widgets.setText(self.status, T.missingLabel)
    self.status:SetWidth(textWidth(self.status, T.missingLabel) + 2)
    self.status:Show()
    local cx = x + 14 + textWidth(self.status, T.missingLabel) + 6
    local right = x + self.w
    local lineTop, shownN = cy, 0
    for i, m in ipairs(d.missing) do
      local c = self.chips[i]
      if not c then break end
      local label = m.text .. (i < #d.missing and "," or "")
      c.fs:SetText(label)
      local w = textWidth(c.fs, label)
      local reserve = (i < #d.missing) and 34 or 0
      if cx + w + reserve > right then
        if o.wrap then
          cx = x + 14
          lineTop = lineTop + lineH
        else
          break
        end
      end
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", parent, "TOPLEFT", cx, -lineTop)
      c:SetSize(w, lineH)
      c.id, c.title = m.id, m.name
      c:Show()
      cx = cx + w + 4
      shownN = i
    end
    local rest = #d.missing - shownN
    if rest > 0 then
      self.more:ClearAllPoints()
      self.more:SetPoint("TOPLEFT", parent, "TOPLEFT", cx, -lineTop)
      self.more:SetTextColor(Widgets.color(o.col.need))
      Widgets.setText(self.more, "+" .. int(rest))
      self.more:Show()
    end
    cy = lineTop + lineH
  end
  -- expected crafts (+ button inline on the page, below it in the bar)
  self.expect:ClearAllPoints()
  self.expect:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 14, -cy)
  Widgets.setText(self.expect, d.expect)
  local showBtn = ctx.own and (d.status == "missing" or HS.listed(row) ~= nil)
  local listed = ctx.own and HS.listed(row) ~= nil
  if o.buttonInline then
    self.expect:SetWidth(self.w - 14 - 150)
    self.expect:Show()
    if showBtn then
      o.setLabel(self.btn, listed and T.onList or T.addList)
      self.btn.row, self.btn.listed = row, listed
      self.btn:ClearAllPoints()
      self.btn:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + self.w, -(cy - 2))
      self.btn:Show()
    end
    cy = cy + lineH
  else
    self.expect:SetWidth(self.w - 14)
    self.expect:Show()
    cy = cy + lineH + 2
    if showBtn then
      o.setLabel(self.btn, listed and T.onList or T.addList)
      self.btn.row, self.btn.listed = row, listed
      self.btn:ClearAllPoints()
      self.btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -cy)
      self.btn:Show()
      cy = cy + (o.btnH or 22) + 2
    end
  end
  return cy - y
end

-- Page block --------------------------------------------------------------------------------------------------------------------------

local function rowTip(r)
  local lines = { r.name }
  if r.color then lines[#lines + 1] = T[r.color] end
  lines[#lines + 1] = plural(r.mats, "mats")
  if r.n ~= nil then lines[#lines + 1] = r.n > 0 and T("enough", int(r.n)) or T.enoughNone end
  local t = { lines = lines }
  if r.out then t.item = "item:" .. tostring(r.out) end
  return t
end

HS.REC_H = 54       -- height of the recommendation on the page (headline, material line, expectation line)
HS.ALT_Y = 22 + HS.REC_H + 4

function HS.build(parent, x, y, w)
  local b = { rows = {}, x = x, y = y, w = w, parent = parent }
  b.head = font(parent, "label", G.size.xs, "sepia", "LEFT")
  b.head:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  b.head:SetText(T.head)
  b.more = font(parent, "label", G.size.xs, "sepia", "RIGHT")
  b.more:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + w, -y)
  b.more:SetWidth(120)
  b.rule = Widgets.NewRule(parent, x, y + 16, w, 0.3)
  b.rec = HS.newRec(parent, { w = w, wrap = false, kind = "label", sizes = { head = G.size.m, line = G.size.s },
    col = { head = "ink", ok = "sepia", need = "red", dim = "sepia" }, rgb = HS.RGB, buttonInline = true,
    newButton = function(p) return D.NewOpenLink(p, T.addList, nil, { size = 11 }) end,
    setLabel = function(btn, text) btn:SetLabel(text) end,
    onChange = function() if b.redraw then b.redraw() end end })
  for i = 1, HS.ALTS do
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(w, HS.ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(y + HS.ALT_Y + (i - 1) * HS.ROW_H))
    row:EnableMouse(true)
    row.dot = Widgets.NewRect(row, "ink", 1, "ARTWORK")
    row.dot:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.dot:SetSize(7, 7)
    row.name = font(row, "label", G.size.s, "ink", "LEFT")
    row.name:SetPoint("LEFT", row, "LEFT", 16, 0)
    row.name:SetWidth(w - 16 - 190 - 24)
    row.name:SetWordWrap(false)
    row.val = font(row, "label", G.size.xs, "sepia", "RIGHT")
    row.val:SetPoint("RIGHT", row, "RIGHT", -26, 0)
    row.val:SetWidth(188)
    row.val:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
      local t = self.tip
      if not t then return end
      -- the item tooltip with the lines below it; the plain text tooltip (all lines) if the client cannot show the item
      local l = { unpack(t.lines) }
      l.item = t.item
      l.itemExtra = { unpack(t.lines, 2) }
      Widgets.tip(self, l)
    end)
    row:SetScript("OnLeave", function(self) Widgets.hideTip(self) end)
    row:Hide()
    b.rows[i] = row
  end
  b.empty = font(parent, "label", G.size.s, "sepia", "LEFT")
  b.empty:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, -(y + 24))
  b.empty:SetWidth(w - 8)
  b.empty:SetWordWrap(true)
  return b
end

function HS.show(b, on)
  if not b then return end
  for _, e in ipairs({ b.head, b.rule, b.more, b.empty }) do
    if e.SetShown then e:SetShown(on) end
  end
  if not on then
    b.rec:Hide()
    for _, row in ipairs(b.rows) do
      row:Hide()
      Widgets.hideTip(row)
      local Z = Journal.Einkaufszettel
      if Z and Z.detach then Z.detach(row) end
    end
  end
end

-- opts: { line = skill line / professionID, char = the character table of the book, own = true for the own, live book }
function HS.draw(b, opts)
  if not b then return end
  opts = type(opts) == "table" and opts or {}
  b.redraw = function() HS.draw(b, opts) end
  HS.show(b, true)
  local E = ns.Einkauf
  local active = E and E.active and E.active()
  local H = Journal.Handwerk
  local line = tonumber(opts.line)
  if not active or not line or (H and H.NO_RECIPES and H.NO_RECIPES[line]) then
    HS.show(b, false)
    return
  end
  local res = Model.rank(opts.line, { char = opts.char, count = opts.own and Model.bagCount or nil, limit = 1 + HS.ALTS })
  if res.reason == "nocache" and not opts.own then
    HS.show(b, false) -- another character's book without a cache: nothing to say
    return
  end
  local Z = Journal.Einkaufszettel
  b.rec:Hide()
  Widgets.setText(b.empty, "")
  if res.best then
    b.rec:Set(res.best, { own = opts.own }, b.x, b.y + 22)
  elseif res.reason == "nocache" then
    Widgets.setText(b.empty, T.nocache)
  elseif res.reason == "nolearned" then
    Widgets.setText(b.empty, T.nolearned)
  else
    b.rec:Set(nil, { noSure = true }, b.x, b.y + 22)
  end
  -- no orange/yellow recipe left (only green): the hint takes the place of the last alternative
  local altN = HS.ALTS
  if res.best and res.noSure then
    altN = HS.ALTS - 1
    b.rec:Hint(b.x, b.y + HS.ALT_Y + altN * HS.ROW_H)
  end
  for i, row in ipairs(b.rows) do
    local r = i <= altN and res.rows[i + 1] or nil
    row.tip = nil
    if r then
      row:Show()
      local c = HS.RGB[r.color] or HS.RGB.green
      row.dot:SetColorTexture(c[1], c[2], c[3], 1)
      Widgets.setText(row.name, r.name)
      local parts = { HS.levelWord(r.color) }
      if r.n ~= nil then parts[#parts + 1] = r.n > 0 and T("enough", int(r.n)) or T.enoughNone end
      Widgets.setText(row.val, table.concat(parts, " · "))
      row.tip = rowTip(r)
      if opts.own and Z and Z.attach then Z.attach(row, r.profID, r.id) elseif Z and Z.detach then Z.detach(row) end
    else
      row:Hide()
      Widgets.hideTip(row)
      if Z and Z.detach then Z.detach(row) end
    end
  end
  local extra = (res.total or 0) - 1 - altN
  Widgets.setText(b.more, extra > 0 and T("more", int(extra)) or "")
  b.res = res
end
