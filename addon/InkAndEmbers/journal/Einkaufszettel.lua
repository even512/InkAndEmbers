-- Shopping list window (WoW Forever): a small paper slip for one recipe. Count (+/- buttons or typed), optionally resolved intermediate
-- products, one line per material with the live bag count ("Kupfererz 4/20", bank only as a hint), "Auf die To-do" (makes / updates the
-- to-do, collectors/Einkaufszettel.lua) and, once everything is there, "Jetzt herstellen" (C_TradeSkillUI.CraftRecipe, only from this
-- click, needs the profession window of that profession). Fallback: if the game blocks CraftRecipe (the call fails, or Core.actionLog
-- reports ADDON_ACTION_BLOCKED/FORBIDDEN for InkAndEmbers, diag.actionBlocked), the button only opens the profession window and a
-- hint says to craft there (collectors/Einkaufszettel.lua: Einkauf.craftBlocked, reason "gesperrt"). Opened from a recipe book row (Einkaufszettel.attach hangs a small button on
-- any row frame), from the to-do page and from the quest tracker dock (row click on a shopping list).
-- Everything foreign (item and recipe names) goes through Sanitize.display (the collector already did); no ticker, no OnUpdate:
-- redraw on the plan change signal (Plans.onChange, batched) only while the slip is open.
local _, ns = ...

local Journal = ns.Journal
local W = Journal and Journal.Widgets
local D = W and W.Diary
local E = ns.Einkauf
if not (Journal and W and D and E) then return end

local floor, max, min = math.floor, math.max, math.min

local Zettel = {}
Journal.Einkaufszettel = Zettel

Zettel.NAME = "EveNChronicleEinkaufszettel"
Zettel.W = 372
Zettel.ROWS = 14
Zettel.ROW_H = 20
Zettel.TOP = 142      -- y of the first material line

Zettel.TEXT = ns.Locale.ns("j.Einkaufszettel", {
  title = "Einkaufszettel",
  countLabel = "Anzahl",
  minusTip = "Eins weniger (Umschalt: zehn)",
  plusTip = "Eins mehr (Umschalt: zehn)",
  resolve = "Zwischenprodukte auflösen",
  resolveTip = "Materialien, die Ihr selbst herstellen könnt, werden durch deren Zutaten ersetzt. Was schon in den Taschen liegt, wird nicht noch einmal gerechnet.",
  add = "Auf die To-do",
  addTip = "Legt den Einkaufszettel als To-do ab und zählt die Materialien in den Taschen mit.",
  update = "Zettel ändern",
  craft = "Jetzt herstellen",
  craftTip = "Stellt die gewählte Anzahl her. Das Berufsfenster muss offen sein.",
  craftWait = "Erst wenn alle Materialien da sind.",
  remove = "Vom To-do nehmen",
  close = "Schließen",
  bank = "%s in der Bank",
  viaOne = "Vorstufe: %s× herstellen",
  made = "Hergestellt: %s von %s",
  saved = "Auf der To-do.",
  changed = "Zettel geändert.",
  removed = "Vom To-do genommen.",
  noRecipe = "Dieses Rezept ist noch nicht gespeichert. Öffnet das Berufsfenster einmal.",
  rowTip = "Einkaufszettel",
  rowTip2 = "Legt dieses Rezept mit einer Anzahl auf die To-do und zählt die Materialien mit.",
  empty = "Keine Materialien bekannt.",
  rowAdd = "+ Einkaufszettel",
  rowOpen = "Zettel: %s×",
})
local T = Zettel.TEXT

local st = { count = 1, resolve = false, rows = {} }
Zettel.state = st

local function safe(fn, ...)
  if ns.Core then return ns.Core.safe(fn, ...) end
  return pcall(fn, ...)
end

local function shown(s, n)
  if type(s) ~= "string" then return "" end
  local S = ns.Sanitize
  return S and S.display and S.display(s, n or 80) or s
end

local function int(n) return Journal.Texts and Journal.Texts.int and Journal.Texts.int(n) or tostring(floor(tonumber(n) or 0)) end

local function plans() return ns.Plans end

-- current shop table: the stored one of an open list, else a preview of the chosen recipe
local function current()
  local P = plans()
  if st.id then
    local p = P and P.raw and P.raw(st.id)
    if p and not p.done and type(p.shop) == "table" then return p.shop, true end
    st.id = nil
  end
  if st.recipe then
    local shop = E.build(st.prof, st.recipe, st.count, st.resolve)
    return shop, false
  end
  return nil, false
end

local function canResolve(shop)
  if not shop then return false end
  local _, rec = E.recipe(shop.prof, shop.recipe)
  if not rec then return false end
  for _, rg in ipairs(E.reagents(rec)) do
    if E.producer(rg.id, shop.prof) then return true end
  end
  return false
end

local function message(text, color)
  if not st.frame then return end
  W.setText(st.msg, text or "")
  st.msg:SetTextColor(W.color(color or "red"))
end

-- Rows --------------------------------------------------------------------------------------------------------------------------

local function buildRow(f, i)
  local row = CreateFrame("Button", nil, f)
  row:SetSize(Zettel.W - 36, Zettel.ROW_H)
  row:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -(Zettel.TOP + (i - 1) * Zettel.ROW_H))
  row.tick = D.mark(row, "tick", 16, "red", "OVERLAY")
  row.tick:SetPoint("LEFT", row, "LEFT", 0, 1)
  row.tick:Hide()
  row.name = D.font(row, "text", 13, "ink")
  row.name:SetPoint("LEFT", row, "LEFT", 22, 0)
  row.name:SetWidth(Zettel.W - 36 - 22 - 96)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)
  row.cnt = D.font(row, "label", 13, "ink")
  row.cnt:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  row.cnt:SetWidth(92)
  row.cnt:SetJustifyH("RIGHT")
  row.cnt:SetWordWrap(false)
  row:SetScript("OnEnter", function(self)
    local d = self.data
    if not d then return end
    local extra = {}
    if d.bank and d.bank > 0 then extra[#extra + 1] = T("bank", int(d.bank)) end
    if d.craft then extra[#extra + 1] = T("viaOne", int(d.craft)) end
    W.tip(self, { d.name, item = "item:" .. tostring(d.id), itemExtra = extra })
  end)
  row:SetScript("OnLeave", function(self) W.hideTip(self) end)
  row:Hide()
  return row
end

local function paintRow(row, d)
  row.data = d
  if not d then
    row:Hide()
    return
  end
  row:Show()
  local name = shown(d.name, 60)
  if d.craft then name = name .. " ‹" end
  W.setText(row.name, d.sub and ("   " .. name) or name)
  row.name:SetTextColor(W.color((d.done or d.sub) and "sepia" or "ink"))
  local cnt = string.format("%s/%s", int(min(d.have, 99999)), int(d.need))
  if d.bank and d.bank > 0 and not d.done then cnt = cnt .. " (+" .. int(d.bank) .. ")" end
  W.setText(row.cnt, cnt)
  row.cnt:SetTextColor(W.color(d.done and "sepia" or "red"))
  row.tick:SetShown(d.done)
end

-- Redraw ------------------------------------------------------------------------------------------------------------------------

function Zettel.refresh()
  local f = st.frame
  if not (f and f:IsShown()) then return end
  local shop, stored = current()
  local status = shop and E.status(shop) or nil
  W.setText(st.name, shop and shown(shop.name, 60) or T.noRecipe)
  f.nameHit.item = shop and shop.out and ("item:" .. tostring(shop.out)) or nil
  if shop then
    st.count = shop.count
    st.resolve = shop.resolve == true
  end
  if not st.edit:HasFocus() then st.edit:SetText(tostring(st.count)) end
  local resolvable = canResolve(shop)
  st.resolveBox:SetShown(resolvable)
  st.resolveBox:SetChecked(st.resolve, true)
  local n = status and #status.lines or 0
  for i = 1, Zettel.ROWS do paintRow(st.rows[i], status and status.lines[i] or nil) end
  W.setText(st.empty, (shop and n == 0) and T.empty or "")
  -- footer
  local y = Zettel.TOP + max(n, 1) * Zettel.ROW_H + 12
  local info
  if stored and status and status.target > 1 or (stored and status and status.made > 0) then
    info = T("made", int(min(status.made, status.target)), int(status.target))
  end
  W.setText(st.info, info or "")
  st.info:ClearAllPoints()
  st.info:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -y)
  st.msg:ClearAllPoints()
  st.msg:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -(y + 18))
  local by = y + 40
  st.add:ClearAllPoints()
  st.craft:ClearAllPoints()
  st.remove:ClearAllPoints()
  st.add:SetLabel(stored and T.update or T.add)
  st.add:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -by)
  st.add:SetShown(shop ~= nil)
  st.craft:SetShown(stored)
  if stored then st.craft:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -by) end
  local ready = status and status.ready or false
  st.craft:SetEnabled(ready)
  st.craft:SetTip(ready and { T.craft, T.craftTip } or { T.craft, T.craftWait })
  st.remove:SetShown(stored)
  if stored then st.remove:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -(by + 44)) end
  f:SetHeight(by + (stored and 78 or 50))
end

-- Actions -----------------------------------------------------------------------------------------------------------------------

function Zettel.setCount(n)
  n = tonumber(n)
  if not n or n ~= n then n = st.count end
  n = max(1, min(floor(n), E.COUNT_MAX))
  message("")
  if st.id then
    local P = plans()
    local p = P and P.raw and P.raw(st.id)
    if not (p and type(p.shop) == "table" and p.shop.count == n) then
      local ok, why = E.rebuild(st.id, { count = n })
      if not ok then message(E.reasonText(why) or "") end
    end
  end
  st.count = n
  Zettel.refresh()
end

function Zettel.setResolve(on)
  st.resolve = on and true or false
  message("")
  if st.id then
    local ok, why = E.rebuild(st.id, { resolve = st.resolve })
    if not ok then message(E.reasonText(why) or "") end
  end
  Zettel.refresh()
end

function Zettel.commit()
  if not st.recipe and not st.id then return false end
  if st.id then
    -- changes are stored at once; only the count typed in the field may still be waiting
    Zettel.setCount(tonumber(st.edit:GetText()) or st.count)
    message(T.changed, "sepia")
    return true
  end
  local n = tonumber(st.edit:GetText()) or st.count
  st.count = max(1, min(floor(n), E.COUNT_MAX))
  local id, how = E.add(st.prof, st.recipe, st.count, st.resolve)
  if not id then
    message(E.reasonText(how) or "")
    return false
  end
  st.id = id
  Zettel.refresh()
  message(how == "update" and T.changed or T.saved, "sepia")
  return true
end

function Zettel.craft()
  if not st.id then return false end
  local ok, why, extra = E.craft(st.id)
  if not ok then
    message(E.reasonText(why, extra) or "")
    return false
  end
  message("", "sepia")
  return true
end

function Zettel.removeList()
  local P = plans()
  if not (st.id and P and P.remove) then return false end
  P.remove(st.id)
  st.id = nil
  Zettel.refresh()
  message(T.removed, "sepia")
  return true
end

-- Build -------------------------------------------------------------------------------------------------------------------------

local function textButton(parent, text, onClick, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  local fs = D.font(b, "hand", 24, "sepia")
  fs:SetPoint("CENTER", b, "CENTER", 0, 1)
  fs:SetText(text)
  b.text = fs
  b:SetScript("OnEnter", function(self) self.text:SetTextColor(W.color("red")) if self.tipLines then W.tip(self, self.tipLines) end end)
  b:SetScript("OnLeave", function(self) self.text:SetTextColor(W.color("sepia")) W.hideTip(self) end)
  b:SetScript("OnClick", function(self) safe(onClick, self) end)
  return b
end

function Zettel.build()
  if st.frame then return st.frame end
  local f = CreateFrame("Frame", Zettel.NAME, UIParent)
  f:SetSize(Zettel.W, 300)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f.slip = D.NewSlip(f)
  f:Hide()

  local title = D.font(f, "hand", 24, "ink")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -12)
  title:SetText(T.title)
  st.title = title
  local close = textButton(f, "×", function() Zettel.close() end, 24)
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
  close.tipLines = { T.close }

  -- recipe name (hover: the made item)
  local nameHit = CreateFrame("Frame", nil, f)
  nameHit:SetSize(Zettel.W - 36, 22)
  nameHit:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -46)
  nameHit:EnableMouse(true)
  nameHit:SetScript("OnEnter", function(self)
    if self.item then W.tip(self, { st.name:GetText() or "", item = self.item }) end
  end)
  nameHit:SetScript("OnLeave", function(self) W.hideTip(self) end)
  f.nameHit = nameHit
  st.name = D.font(f, "text", 16, "ink")
  st.name:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -46)
  st.name:SetWidth(Zettel.W - 36)
  st.name:SetJustifyH("LEFT")
  st.name:SetWordWrap(false)

  -- count: label, minus, field, plus
  local lab = D.font(f, "label", 13, "sepia")
  lab:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -78)
  lab:SetText(T.countLabel)
  local minus = textButton(f, "-", function()
    local step = (type(IsShiftKeyDown) == "function" and IsShiftKeyDown()) and 10 or 1
    Zettel.setCount((tonumber(st.edit:GetText()) or st.count) - step)
  end, 26)
  minus:SetPoint("TOPLEFT", f, "TOPLEFT", 96, -72)
  minus.tipLines = { T.minusTip }
  local eb = CreateFrame("EditBox", nil, f)
  eb:SetSize(52, 22)
  eb:SetPoint("TOPLEFT", f, "TOPLEFT", 126, -74)
  eb:SetAutoFocus(false)
  eb:SetNumeric(true)
  eb:SetMaxLetters(3)
  eb:SetJustifyH("CENTER")
  local okFont = false
  local Theme = Journal.Theme or {}
  if eb.SetFont and Theme.FONT and Theme.FONT.text then okFont = pcall(eb.SetFont, eb, Theme.FONT.text, 15, "") end
  if not okFont and eb.SetFontObject and ChatFontNormal then pcall(eb.SetFontObject, eb, ChatFontNormal) end
  if eb.SetTextColor then eb:SetTextColor(W.color("ink")) end
  local line = W.NewRect(f, "ink", 0.6, "ARTWORK")
  line:SetPoint("TOPLEFT", f, "TOPLEFT", 124, -96)
  line:SetSize(56, 1)
  eb:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    safe(Zettel.setCount, tonumber(self:GetText()))
  end)
  eb:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    safe(Zettel.refresh)
  end)
  eb:SetScript("OnEditFocusLost", function(self) safe(Zettel.setCount, tonumber(self:GetText())) end)
  st.edit = eb
  local plus = textButton(f, "+", function()
    local step = (type(IsShiftKeyDown) == "function" and IsShiftKeyDown()) and 10 or 1
    Zettel.setCount((tonumber(st.edit:GetText()) or st.count) + step)
  end, 26)
  plus:SetPoint("TOPLEFT", f, "TOPLEFT", 184, -72)
  plus.tipLines = { T.plusTip }
  st.minus, st.plus = minus, plus

  st.resolveBox = D.NewCheck(f, T.resolve, { size = 13, tip = { T.resolve, T.resolveTip },
    onChange = function(on) safe(Zettel.setResolve, on) end })
  st.resolveBox:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -106)

  local rule = W.NewRule and W.NewRule(f, 18, 134, Zettel.W - 36, 0.3)
  st.rule = rule
  for i = 1, Zettel.ROWS do st.rows[i] = buildRow(f, i) end
  st.empty = D.font(f, "label", 13, "sepia")
  st.empty:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -Zettel.TOP)
  st.info = D.font(f, "label", 12, "sepia")
  st.msg = D.font(f, "label", 12, "red")
  st.msg:SetWidth(Zettel.W - 36)
  st.msg:SetJustifyH("LEFT")
  st.msg:SetWordWrap(true)
  st.add = D.NewSticker(f, T.add, function() safe(Zettel.commit) end, { size = 18, height = 36, tip = { T.add, T.addTip } })
  st.craft = D.NewSticker(f, T.craft, function() safe(Zettel.craft) end, { size = 18, height = 36 })
  st.remove = D.NewOpenLink(f, T.remove, function() safe(Zettel.removeList) end, { size = 12 })
  D.escKeys(f, function() Zettel.close() end)
  f:SetScript("OnHide", function(self)
    self:StopMovingOrSizing()
    st.edit:ClearFocus()
    W.hideTip(self.nameHit)
    for _, r in ipairs(st.rows) do W.hideTip(r) end
  end)
  st.frame = f
  return f
end

-- API ---------------------------------------------------------------------------------------------------------------------------

-- opts: { prof, recipe } (a recipe of the cache) or { id } (an existing list); returns true if the slip is open
function Zettel.open(opts)
  if not E.active() then return false end
  opts = type(opts) == "table" and opts or {}
  local P = plans()
  st.id, st.prof, st.recipe = nil, nil, nil
  local id = opts.id
  local p = id and P and P.raw and P.raw(id) or nil
  if p and not p.done and type(p.shop) == "table" then
    st.id, st.prof, st.recipe = p.id, p.shop.prof, p.shop.recipe
    st.count, st.resolve = p.shop.count, p.shop.resolve == true
  elseif opts.recipe then
    st.prof, st.recipe = tonumber(opts.prof), tonumber(opts.recipe)
    local existing = E.find(st.recipe)
    if existing then
      local q = P.raw(existing)
      st.id, st.prof = existing, q.shop.prof
      st.count, st.resolve = q.shop.count, q.shop.resolve == true
    else
      st.count, st.resolve = tonumber(opts.count) or 1, opts.resolve == true
    end
  else
    return false
  end
  local f = Zettel.build()
  message("")
  f:ClearAllPoints()
  local a = opts.anchor
  if type(a) == "table" and a.GetLeft and (tonumber(a:GetLeft()) or 0) > 0 then
    f:SetPoint("TOPLEFT", a, "TOPRIGHT", 8, 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
  f:Show()
  Zettel.refresh()
  return true
end

function Zettel.close()
  if st.frame then st.frame:Hide() end
end

function Zettel.isOpen()
  return st.frame ~= nil and st.frame:IsShown() == true
end

-- Hangs a small "Einkaufszettel" button on a recipe row frame (recipe book). Safe to call again for a recycled row with another recipe.
-- The caller keeps the row's own layout: the button sits at the right end of the row, `placeAfter` (optional frame) moves it left of that.
function Zettel.attach(row, profID, recipeID, placeAfter)
  if type(row) ~= "table" or not row.CreateFontString or not E.active() then return nil end
  local b = row.einkaufBtn
  if not b then
    b = CreateFrame("Button", nil, row)
    b:SetSize(22, 18)
    local fs = D.font(b, "hand", 20, "sepia")
    fs:SetPoint("CENTER", b, "CENTER", 0, 1)
    fs:SetText("+")
    b.text = fs
    b:SetScript("OnEnter", function(self)
      self.text:SetTextColor(W.color("red"))
      W.tip(self, { T.rowTip, T.rowTip2 })
    end)
    b:SetScript("OnLeave", function(self)
      self.text:SetTextColor(W.color("sepia"))
      W.hideTip(self)
    end)
    b:SetScript("OnClick", function(self) safe(Zettel.open, { prof = self.prof, recipe = self.recipe, anchor = self:GetParent() }) end)
    row.einkaufBtn = b
  end
  b.prof, b.recipe = profID, recipeID
  b:ClearAllPoints()
  if placeAfter then b:SetPoint("RIGHT", placeAfter, "LEFT", -4, 0) else b:SetPoint("RIGHT", row, "RIGHT", -4, 0) end
  b:SetFrameLevel((row:GetFrameLevel() or 1) + 3)
  b:Show()
  return b
end

function Zettel.detach(row)
  if type(row) == "table" and row.einkaufBtn then row.einkaufBtn:Hide() end
end

-- Hook of the recipe book (journal/model/Rezeptbuch.lua, Rezeptbuch.rowExtra): on every recipe row, in the free frame "extra" (104 x 13)
-- at its lower right, a small text button "+ Einkaufszettel" ("Zettel: 20×" while an open list of that recipe exists).
local function extraPaint(b)
  local id = b.recipe and E.find(b.recipe)
  local p = id and ns.Plans and ns.Plans.raw and ns.Plans.raw(id)
  if p and type(p.shop) == "table" then
    W.setText(b.text, T("rowOpen", int(p.shop.count)))
    b.text:SetTextColor(W.color(b.hover and "red" or "ink"))
  else
    W.setText(b.text, T.rowAdd)
    b.text:SetTextColor(W.color(b.hover and "red" or "sepia"))
  end
end

Zettel.rowExtra = {
  build = function(row, extra)
    local b = CreateFrame("Button", nil, extra)
    b:SetAllPoints(extra)
    b.text = D.font(b, "label", 11, "sepia")
    b.text:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    b.text:SetWidth(104)
    b.text:SetJustifyH("RIGHT")
    b.text:SetWordWrap(false)
    b:SetScript("OnEnter", function(self)
      self.hover = true
      extraPaint(self)
      W.tip(self, { T.rowTip, T.rowTip2 })
    end)
    b:SetScript("OnLeave", function(self)
      self.hover = false
      extraPaint(self)
      W.hideTip(self)
    end)
    b:SetScript("OnClick", function(self)
      safe(Zettel.open, { prof = self.prof, recipe = self.recipe, anchor = self.row })
    end)
    b.row = row
    extra.einkaufBtn = b
    b:Hide()
  end,
  fill = function(row, extra, rec)
    local b = extra.einkaufBtn
    if not b then return end
    local usable = E.active() and type(rec) == "table" and rec.details == true and type(rec.reagents) == "table" and #rec.reagents > 0
    b.prof, b.recipe = usable and rec.prof or nil, usable and rec.id or nil
    b.row = row
    b:SetShown(usable and true or false)
    if usable then extraPaint(b) end
  end,
  clear = function(row, extra)
    local b = extra and extra.einkaufBtn
    if b then
      b.prof, b.recipe = nil, nil
      b:Hide()
    end
  end,
}
if Journal.Rezeptbuch then Journal.Rezeptbuch.rowExtra = Zettel.rowExtra end

-- the slip and the recipe book follow every change of the to-do lists (Plans.onChange is batched)
do
  local P = plans()
  if P and type(P.onChange) == "function" then
    P.onChange(function()
      if st.frame and st.frame:IsShown() then Zettel.refresh() end
      local RB = Journal.Rezeptbuch
      if RB and type(RB.redraw) == "function" then RB.redraw() end
    end)
  end
end
