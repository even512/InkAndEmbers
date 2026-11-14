-- Sub-view "Rezeptbuch" of the tab Handwerk (change "runde3", package R; WoW Forever only): every recipe of the character's professions,
-- learned and not yet learned. Left: the professions (choose one), filter (all / learned / open), a note whether the book knows the
-- details (recipe cache) and the colour key. Right: the recipes of the chosen profession as a paged list (name in the colour of the
-- difficulty, state, materials) and below the chosen recipe with its output and materials. Every item (output and materials) has the
-- original item tooltip (Widgets.tip with item = "item:<id>", text tooltip as fallback).
-- Data: journal/model/Rezeptbuch.lua (cache from collectors/RecipeScan.lua, else the recipe data). Hook for the shopping list:
-- Journal.Rezeptbuch.rowExtra (see the model): every row has a free frame "row.extra" (104 x 13) at its lower right.
-- Grid (docs/raster.md): left everything above y 474 (blot bottom left), right left of x 438 and above y 574. No ticker, no OnUpdate;
-- rows and material lines are pooled / fixed in number.
local _, ns = ...

local Journal = ns.Journal
local W, Pages, RB = Journal and Journal.Widgets, Journal and Journal.Pages, Journal and Journal.Rezeptbuch
local D = W and W.Diary
if not (W and Pages and RB and D) then return end

local floor, max, min = math.floor, math.max, math.min
local Theme = Journal.Theme
local G = Theme.GRID

local View = {}
View.__index = View
Journal.RezeptbuchView = View

-- texts (German here, English in locales/enUS_pages.lua, scope "p.HandwerkRezeptbuch"; read only on build/draw)
local T = ns.Locale.ns("p.HandwerkRezeptbuch", {
  brand = "INK & EMBERS", book = "REZEPTBUCH", page = "HANDWERK",
  title = "Rezeptbuch", sub = "Alle Rezepte Eurer Berufe, gelernt und noch offen",
  listHead = "BERUFE", recipesHead = "REZEPTE",
  fAll = "Alle", fLearned = "Gelernt", fOpen = "Offen",
  fAllTip = { "Alle", "Gelernte und noch nicht gelernte Rezepte" },
  fLearnedTip = { "Gelernt", "Nur die Rezepte, die Ihr schon beherrscht" },
  fOpenTip = { "Offen", "Nur die Rezepte, die Euch noch fehlen" },
  profSub = "Fertigkeit %s von %s", profSubNoMax = "Fertigkeit %s",
  profCount = "%s von %s", profNoCount = "–",
  countLine = "%s gelernt · %s offen",
  hintNoCache = "Öffnet Euer Berufsfenster einmal, damit das Buch alle Details kennt.",
  hintCache = "Stand vom letzten Öffnen des Berufsfensters. Neu Gelerntes erscheint, sobald Ihr es wieder öffnet.",
  legend = "Farbe:",
  learned = "gelernt", open = "offen", fromSkill = "ab %s",
  skillWord = "Fertigkeit %s",
  tipSource = "Quelle: %s", tipDifficulty = "Schwierigkeit: %s", tipUps = "Fertigkeitspunkte je Herstellung: bis zu %s",
  tipCost = "Preis: %s", tipStock = "Im Beutel: %s · Bank: %s",
  tipNeeds = "Braucht: %s", tipMore = "Klicken: Einzelheiten unten",
  needs = "BRAUCHT", output = "Ergibt: %s", outputQty = "Ergibt: %s× %s",
  noMats = "Dieses Rezept braucht kein Material.",
  detailNoCache = "Ergebnis und Material kennt das Buch erst, wenn Ihr Euer Berufsfenster einmal geöffnet habt.",
  moreMats = "… und %s weitere",
  itemNo = "Gegenstand #%s",
  pick = "Wählt ein Rezept.",
  emptyList = "Für diesen Beruf liegen noch keine Rezepte vor.",
  emptyFilterLearned = "Noch kein Rezept gelernt.", emptyFilterOpen = "Alle Rezepte dieses Berufs sind gelernt.",
  noProfTitle = "Noch kein Beruf mit Rezepten",
  noProfBody = "Lernt einen Beruf. Dann zeigt dieses Blatt alle seine Rezepte, gelernte und offene.",
  prevPage = "Vorige Seite", nextPage = "Nächste Seite",
})
View.TEXT = T

local LX, LW = Theme.gridX("L")
local RX, RW = Theme.gridX("R")
local CW = RW - 8
local TITLE_Y = G.slots.title.y

-- left
local LIST_HEAD_Y, LIST_Y, P_ROW_H, P_ROWS = 126, 150, 34, 6
local FILTER_Y = LIST_Y + P_ROWS * P_ROW_H + 24      -- centre of the filter
local COUNT_Y = FILTER_Y + 22
local NOTE_Y = COUNT_Y + 20
local LEGEND_Y = 452
local LEFT_END = 474
-- right
local REC_HEAD_Y, REC_PAGER_CY, REC_RULE_Y, REC_Y, REC_ROW_H, REC_ROWS = 122, 130, 146, 150, 30, 8
local DET_Y = REC_Y + REC_ROWS * REC_ROW_H + 10       -- detail head
local MAT_LINES, MAT_H = 5, 17
local ICON_BOX, ICON_SIZE, MAT_BOX, MAT_SIZE = 19, 17, 17, 15   -- icon with a thin rim (recipe rows / materials)
local ICON_FALLBACK = 134400                                   -- question mark
local EXTRA_W, EXTRA_H = 104, 13
View.LAYOUT = { listY = LIST_Y, recY = REC_Y, recRowH = REC_ROW_H, recRows = REC_ROWS, detailY = DET_Y, leftEnd = LEFT_END, matLines = MAT_LINES }

local DIFF_COLOR = {
  -- stronger than the brown ink, so the difficulty is told at a glance (relativeDifficulty 0 orange, 1 yellow, 2 green, 3 grey)
  orange = { 0.90, 0.36, 0.00 }, yellow = { 0.80, 0.62, 0.00 }, green = { 0.10, 0.55, 0.15 }, grey = { 0.55, 0.55, 0.55 },
}
View.DIFF_COLOR = DIFF_COLOR

local function int(n) return Journal.Texts and Journal.Texts.int(n) or tostring(floor(tonumber(n) or 0)) end

local function label(parent, kind, size, color, justify)
  local fs = W.font(parent, kind, size, color)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

local function kit() return Journal.QuestsPage and Journal.QuestsPage.kit end

local function diffColor(rec)
  local key = rec and RB.DIFF[rec.diff]
  return key and DIFF_COLOR[key] or nil
end

-- Icons: the original game icons (file ids only; a texture path from outside is never used). Cache icon first, else the client:
-- C_Item.GetItemIconByID(output item) / C_Spell.GetSpellTexture(spell); the question mark when nothing is known.
local function fileId(v)
  if type(v) ~= "number" or v ~= v or v < 1 or v ~= floor(v) or (type(issecretvalue) == "function" and issecretvalue(v)) then return nil end
  return v
end

local function itemIcon(id)
  local ci = rawget(_G, "C_Item")
  if type(ci) == "table" and type(ci.GetItemIconByID) == "function" then
    local ok, v = pcall(ci.GetItemIconByID, id)
    if ok and fileId(v) then return v end
  end
  local L = Journal.Live
  return L and type(L.itemIcon) == "function" and fileId(L.itemIcon(id)) or nil
end

local function spellIcon(id)
  local cs = rawget(_G, "C_Spell")
  if type(cs) == "table" and type(cs.GetSpellTexture) == "function" then
    local ok, v = pcall(cs.GetSpellTexture, id)
    if ok and fileId(v) then return v end
  end
  return nil
end

local function recipeIcon(rec)
  return fileId(rec.icon) or (rec.out and itemIcon(rec.out)) or spellIcon(rec.id) or ICON_FALLBACK
end

-- icon with a thin rim: neutral rim (BORDER), coloured rim on top (ARTWORK, shown only with a colour), the icon (OVERLAY) inset by 1 px
local function newIcon(parent, box, size, x, y)
  local ic = { box = box }
  ic.rim = parent:CreateTexture(nil, "BORDER")
  ic.rim:SetSize(box, box)
  ic.rim:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  ic.rim:SetColorTexture(W.color("ink", 0.6))
  ic.edge = parent:CreateTexture(nil, "ARTWORK")
  ic.edge:SetSize(box, box)
  ic.edge:SetPoint("TOPLEFT", ic.rim, "TOPLEFT", 0, 0)
  ic.edge:Hide()
  ic.tex = parent:CreateTexture(nil, "OVERLAY")
  ic.tex:SetSize(size, size)
  ic.tex:SetPoint("CENTER", ic.rim, "CENTER", 0, 0)
  return ic
end

local function paintIcon(ic, fileID, color)
  ic.tex:SetTexture(fileID or ICON_FALLBACK)
  if ic.tex.SetTexCoord then ic.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  ic.rim:Show()
  ic.tex:Show()
  if color then
    ic.edge:SetColorTexture(color[1], color[2], color[3], 1)
    ic.edge:Show()
  else
    ic.edge:Hide()
  end
end

local function hideIcon(ic)
  ic.rim:Hide()
  ic.edge:Hide()
  ic.tex:Hide()
end

-- name of an item: from the client (loaded on demand, the view redraws once), else "Gegenstand #id"
local function itemName(self, id)
  local n = self.names and self.names.name(id)
  return n or T("itemNo", tostring(floor(tonumber(id) or 0)))
end

local function itemLink(id)
  if type(id) ~= "number" or id < 1 or id ~= floor(id) then return nil end
  return "item:" .. floor(id)
end

-- "4× Kupfererz, 1× Wetzstein" for the list line
local function materialsText(self, rec)
  local parts = {}
  for _, m in ipairs(rec.reagents or {}) do parts[#parts + 1] = int(m.qty) .. "× " .. itemName(self, m.id) end
  return table.concat(parts, ", ")
end

local function stateText(rec)
  if rec.learned then return T.learned end
  if rec.skill then return T("fromSkill", int(rec.skill)) end
  return T.open
end

-- ---------------------------------------------------------------- hook of the shopping list

local function extraCall(row, what, rec)
  local hook = RB.rowExtra
  if type(hook) ~= "table" or not row.extra then return end
  if type(hook.build) == "function" and row.extraBuilt ~= hook then
    row.extraBuilt = hook
    pcall(hook.build, row, row.extra)
  end
  local fn = hook[what]
  if type(fn) == "function" then pcall(fn, row, row.extra, rec) end
end

-- ---------------------------------------------------------------- left

local function buildProfRow(self, row)
  local nm = label(row, "title", G.size.m, "ink", "LEFT")
  nm:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -3)
  nm:SetWidth(LW - 120)
  nm:SetWordWrap(false)
  local sub = label(row, "label", G.size.xs, "sepia", "LEFT")
  sub:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -20)
  sub:SetWidth(LW - 120)
  sub:SetWordWrap(false)
  local val = label(row, "title", G.size.m, "ink", "RIGHT")
  val:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -3)
  val:SetWidth(104)
  val:SetWordWrap(false)
  local note = label(row, "label", G.size.xs, "sepia", "RIGHT")
  note:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -20)
  note:SetWidth(104)
  note:SetWordWrap(false)
  row.name, row.subline, row.val, row.note = nm, sub, val, note
  row.label:SetText("")
  D.RowStyle(row, { texts = { nm, val } })
end

local function fillProfRow(self, row, e)
  row.entry = e
  W.setText(row.name, e.name)
  if e.rank and e.max then
    W.setText(row.subline, T("profSub", int(e.rank), int(e.max)))
  elseif e.rank then
    W.setText(row.subline, T("profSubNoMax", int(e.rank)))
  else
    W.setText(row.subline, "")
  end
  W.setText(row.val, e.cached and T("profCount", int(e.learned), int(e.count)) or T.profNoCount)
  W.setText(row.note, "")
  row:SetSelected(self.profKey == e.key)
  D.rowFilled(row)
end

local function buildLeft(self, tab)
  local ui = self.ui
  ui.headL = W.NewPageHead(tab, { side = "L" })
  ui.headL:SetTexts(T.brand, T.book)
  ui.title = label(tab, "title", G.size.xl, "ink", "RIGHT")
  ui.title:SetPoint("TOPRIGHT", tab, "TOPLEFT", LX + LW, -TITLE_Y)
  W.setText(ui.title, T.title)
  ui.sub = label(tab, "label", G.size.s, "sepia", "RIGHT")
  ui.sub:SetPoint("TOPRIGHT", tab, "TOPLEFT", LX + LW, -(TITLE_Y + 34))
  ui.sub:SetWidth(LW)
  ui.sub:SetWordWrap(false)
  W.setText(ui.sub, T.sub)

  ui.listHead = label(tab, "label", G.size.xs, "sepia", "LEFT")
  ui.listHead:SetPoint("TOPLEFT", tab, "TOPLEFT", LX, -LIST_HEAD_Y)
  W.setText(ui.listHead, T.listHead)
  W.NewRule(tab, LX, LIST_HEAD_Y + 18, LW)
  ui.profList = W.NewList(tab, { rows = P_ROWS, rowHeight = P_ROW_H, width = LW, step = 2, empty = T.noProfTitle, emptyHand = true,
    build = function(row) buildProfRow(self, row) end,
    clear = function(row)
      row.entry = nil
      for _, k in ipairs({ "name", "subline", "val", "note" }) do if row[k] then W.setText(row[k], "") end end
      if row.SetSelected then row:SetSelected(false) end
    end,
    fill = function(row, e) fillProfRow(self, row, e) end,
    onClick = function(e) self:SelectProfession(e.key) end })
  ui.profList.frame:SetPoint("TOPLEFT", tab, "TOPLEFT", LX, -LIST_Y)

  local items = {}
  for _, key in ipairs(RB.FILTERS) do
    local k = key == "all" and "fAll" or key == "learned" and "fLearned" or "fOpen"
    items[#items + 1] = { key = key, label = T[k], tip = T[k .. "Tip"] }
  end
  ui.filter = D.NewToggle(tab, { items = items, size = 13, gap = 14, value = "all", onChange = function(key) self:SetFilter(key) end })
  ui.filter.frame:SetPoint("LEFT", tab, "TOPLEFT", LX, -FILTER_Y)
  ui.count = label(tab, "label", G.size.s, "ink", "LEFT")
  ui.count:SetPoint("TOPLEFT", tab, "TOPLEFT", LX, -COUNT_Y)
  ui.count:SetWidth(LW)
  ui.count:SetWordWrap(false)
  ui.note = label(tab, "label", G.size.xs, "sepia", "LEFT")
  ui.note:SetPoint("TOPLEFT", tab, "TOPLEFT", LX, -NOTE_Y)
  ui.note:SetWidth(LW - 6)
  ui.note:SetWordWrap(true)
  -- colour key: the word of every difficulty in its colour
  ui.legendHead = label(tab, "label", G.size.xs, "sepia", "LEFT")
  ui.legendHead:SetPoint("TOPLEFT", tab, "TOPLEFT", LX, -LEGEND_Y)
  ui.legendHead:SetWidth(46)
  ui.legendHead:SetWordWrap(false)
  W.setText(ui.legendHead, T.legend)
  ui.legend = {}
  local cellW = floor((LW - 50) / 4)
  for i, key in ipairs({ "orange", "yellow", "green", "grey" }) do
    local fs = label(tab, "label", G.size.xs, DIFF_COLOR[key], "LEFT")
    fs:SetPoint("TOPLEFT", tab, "TOPLEFT", LX + 50 + (i - 1) * cellW, -LEGEND_Y)
    fs:SetWidth(cellW - 4)
    fs:SetWordWrap(false)
    ui.legend[i] = { fs = fs, d = i - 1 }
  end
end

-- ---------------------------------------------------------------- right: recipe list

-- Tooltips: always the ORIGINAL game tooltip, our own text only as the fallback when the client gives nothing.
--   spec = { item = itemID | nil, spell = spellID | nil, text = { fallback lines }, extra = { lines below }, stock = true (add bag/bank) }
-- An item shows the item tooltip (hyperlink item:<id>), a recipe without output item (enchantments) and every recipe without
-- cache details the spell tooltip (GameTooltip:SetSpellByID), then the extra lines (source, cost, minimum skill, stock).
local function stockLine(itemID)
  local ci = rawget(_G, "C_Item")
  local fn = type(ci) == "table" and ci.GetItemCount or nil
  if type(fn) ~= "function" then return nil end
  local okB, bag = pcall(fn, itemID, false)
  local okT, total = pcall(fn, itemID, true)
  local function n(v) return type(v) == "number" and v == v and not (type(issecretvalue) == "function" and issecretvalue(v)) and v or nil end
  bag, total = okB and n(bag) or nil, okT and n(total) or nil
  if not bag then return nil end
  return T("tipStock", int(bag), int(max(0, (total or bag) - bag)))
end

-- spell tooltip of the client; counts only when it holds a line of text -> true when shown
local function spellTip(owner, spellID, extra)
  local tt = rawget(_G, "GameTooltip")
  if type(tt) ~= "table" or type(tt.SetSpellByID) ~= "function" or type(spellID) ~= "number" then return false end
  local ok, shown = pcall(function()
    tt:SetOwner(owner, "ANCHOR_RIGHT")
    tt:SetSpellByID(spellID)
    local lines = type(tt.NumLines) == "function" and tt:NumLines() or 1
    if type(lines) ~= "number" or lines < 1 then return false end
    for _, line in ipairs(extra or {}) do tt:AddLine(line, 0.85, 0.8, 0.7, true) end
    tt:Show()
    return true
  end)
  if ok and shown then return true end
  if tt.Hide then pcall(tt.Hide, tt) end
  return false
end

local function showTip(owner, spec)
  if type(spec) ~= "table" then return end
  local extra = {}
  for _, line in ipairs(spec.extra or {}) do extra[#extra + 1] = line end
  if spec.stock and spec.item then
    local st = stockLine(spec.item)
    if st then extra[#extra + 1] = st end
  end
  local text = {}
  for _, line in ipairs(spec.text or {}) do text[#text + 1] = line end
  for _, line in ipairs(extra) do text[#text + 1] = line end
  if spec.item then
    text.item, text.itemExtra = itemLink(spec.item), extra
    W.tip(owner, text) -- item tooltip; the text lines when the client refuses the link
    return
  end
  if spec.spell and spellTip(owner, spec.spell, extra) then return end
  W.tip(owner, text)
end

local function recipeTip(self, rec)
  local extra = { stateText(rec) }
  local d = RB.diffText(rec.diff)
  if d then extra[#extra + 1] = T("tipDifficulty", d) end
  if rec.skill and not rec.learned then extra[#extra + 1] = T("skillWord", int(rec.skill)) end
  if rec.src then extra[#extra + 1] = T("tipSource", rec.src) end
  if rec.cost and rec.cost > 0 and Journal.Texts and Journal.Texts.money then extra[#extra + 1] = T("tipCost", Journal.Texts.money(rec.cost, "short")) end
  if #(rec.reagents or {}) > 0 then extra[#extra + 1] = T("tipNeeds", materialsText(self, rec)) end
  extra[#extra + 1] = T.tipMore
  -- output item: item tooltip; without one (enchantments) and without cache details: the spell of the recipe
  return { item = rec.out, spell = (not rec.out) and rec.id or nil, text = { rec.name }, extra = extra }
end

local function buildRecipeRow(self, row)
  local nm = label(row, "title", G.size.m, "ink", "LEFT")
  nm:SetPoint("TOPLEFT", row, "TOPLEFT", 30, -2)
  nm:SetWidth(CW - 142)
  nm:SetWordWrap(false)
  -- the original icon of the recipe; its rim carries the colour of the difficulty (also readable where the ink hides the text colour)
  local icon = newIcon(row, ICON_BOX, ICON_SIZE, 4, -5)
  local tag = label(row, "label", G.size.s, "sepia", "RIGHT")
  tag:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -4)
  tag:SetWidth(104)
  tag:SetWordWrap(false)
  local sub = label(row, "label", G.size.xs, "sepia", "LEFT")
  sub:SetPoint("TOPLEFT", row, "TOPLEFT", 30, -17)
  sub:SetWidth(CW - EXTRA_W - 44)
  sub:SetWordWrap(false)
  local extra = CreateFrame("Frame", nil, row)
  extra:SetSize(EXTRA_W, EXTRA_H)
  extra:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -16)
  row.name, row.tag, row.subline, row.extra, row.icon, row.dot = nm, tag, sub, extra, icon, icon.edge
  row.label:SetText("")
  D.RowStyle(row, { texts = { nm, tag, sub } })
  row:HookScript("OnEnter", function(r) if r.tipSpec then showTip(r, r.tipSpec) end end)
  row:HookScript("OnLeave", function(r) W.hideTip(r) end)
end

local function fillRecipeRow(self, row, rec)
  row.rec = rec
  W.setText(row.name, rec.name)
  -- the colour is set AFTER the text; only learned recipes with a known difficulty carry one (nothing is faked for the others)
  local c = rec.learned and diffColor(rec) or nil
  if c then
    row.name:SetTextColor(c[1], c[2], c[3], 1)
  else
    row.name:SetTextColor(W.color(rec.learned and "ink" or "sepia", rec.learned and 1 or 0.85))
  end
  paintIcon(row.icon, recipeIcon(rec), c)
  row.icon.tex:SetDesaturated(not rec.learned)
  W.setText(row.tag, c and RB.diffText(rec.diff) or stateText(rec))
  if c then row.tag:SetTextColor(c[1], c[2], c[3], 1) else row.tag:SetTextColor(W.color(rec.learned and "ink" or "sepia")) end
  local mats = materialsText(self, rec)
  W.setText(row.subline, mats ~= "" and mats or (rec.src or ""))
  row.tipSpec = recipeTip(self, rec)
  row:SetSelected(self.sel == rec.id)
  D.rowFilled(row)
  extraCall(row, "fill", rec)
end

local function clearRecipeRow(row)
  row.rec = nil
  row.tipSpec = nil
  if row.name then
    W.setText(row.name, "")
    row.name:SetTextColor(W.color("ink"))
  end
  if row.icon then hideIcon(row.icon) end
  for _, k in ipairs({ "tag", "subline" }) do if row[k] then W.setText(row[k], "") end end
  if row.SetSelected then row:SetSelected(false) end
  W.hideTip(row)
  extraCall(row, "clear", nil)
end

local function buildRight(self, tabR)
  local ui = self.ui
  ui.headR = W.NewPageHead(tabR, { side = "R" })
  ui.headR:SetTexts("", T.page)
  ui.rTitle = label(tabR, "title", G.size.xl, "ink", "LEFT")
  ui.rTitle:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -TITLE_Y)
  ui.rTitle:SetWidth(CW)
  ui.rTitle:SetWordWrap(false)
  ui.rSub = label(tabR, "label", G.size.s, "sepia", "LEFT")
  ui.rSub:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -(TITLE_Y + 34))
  ui.rSub:SetWidth(CW)
  ui.rSub:SetWordWrap(false)
  ui.recHead = label(tabR, "label", G.size.xs, "sepia", "LEFT")
  ui.recHead:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -REC_HEAD_Y)
  W.setText(ui.recHead, T.recipesHead)
  ui.recRule = W.NewRule(tabR, RX, REC_RULE_Y, CW)
  ui.recList = W.NewList(tabR, { rows = REC_ROWS, rowHeight = REC_ROW_H, width = CW + 10, step = 3, empty = T.emptyList, emptyHand = true,
    build = function(row) buildRecipeRow(self, row) end,
    clear = clearRecipeRow,
    fill = function(row, rec) fillRecipeRow(self, row, rec) end,
    onClick = function(rec) self:SelectRecipe(rec.id) end })
  ui.recList.frame:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -REC_Y)
  local K = kit()
  if K and K.pager then ui.pager = K.pager(tabR, ui.recList, RX, CW, REC_PAGER_CY, { T.prevPage, T.nextPage }) end

  -- detail of the chosen recipe
  ui.dHead = label(tabR, "title", G.size.l, "ink", "LEFT")
  ui.dHead:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -DET_Y)
  ui.dHead:SetWidth(CW)
  ui.dHead:SetWordWrap(false)
  ui.dRule = W.NewRule(tabR, RX, DET_Y + 24, CW)
  ui.dMeta = label(tabR, "label", G.size.xs, "sepia", "LEFT")
  ui.dMeta:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -(DET_Y + 30))
  ui.dMeta:SetWidth(CW)
  ui.dMeta:SetWordWrap(false)
  ui.dOut = CreateFrame("Frame", nil, tabR)
  ui.dOut:SetSize(CW, 16)
  ui.dOut:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -(DET_Y + 48))
  ui.dOut:SetSize(CW, ICON_BOX)
  ui.dOutIcon = newIcon(ui.dOut, MAT_BOX, MAT_SIZE, 0, 0)
  ui.dOutText = label(ui.dOut, "text", G.size.s, "ink", "LEFT")
  ui.dOutText:SetPoint("TOPLEFT", ui.dOut, "TOPLEFT", 24, -2)
  ui.dOutText:SetWidth(CW - 26)
  ui.dOutText:SetWordWrap(false)
  ui.dOut:EnableMouse(true)
  ui.dOut:SetScript("OnEnter", function(f) if f.tipSpec then showTip(f, f.tipSpec) end end)
  ui.dOut:SetScript("OnLeave", function(f) W.hideTip(f) end)
  ui.needs = label(tabR, "label", G.size.xs, "sepia", "LEFT")
  ui.needs:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -(DET_Y + 70))
  W.setText(ui.needs, T.needs)
  ui.mats = {}
  for i = 1, MAT_LINES do
    local f = CreateFrame("Frame", nil, tabR)
    f:SetSize(CW, MAT_H)
    f:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -(DET_Y + 86 + (i - 1) * MAT_H))
    local icon = newIcon(f, MAT_BOX, MAT_SIZE, 6, 0)
    local fs = label(f, "text", G.size.s, "ink", "LEFT")
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -2)
    fs:SetWidth(CW - 34)
    fs:SetWordWrap(false)
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self_) if self_.tipSpec then showTip(self_, self_.tipSpec) end end)
    f:SetScript("OnLeave", function(self_) W.hideTip(self_) end)
    ui.mats[i] = { frame = f, fs = fs, icon = icon }
  end
  ui.dHint = D.emptyNote(tabR, CW - 20, 17)
  ui.dHint:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX + 4, -(DET_Y + 52))
  ui.rEmpty = D.emptyNote(tabR, CW - 60, 19)
  ui.rEmpty:SetPoint("CENTER", tabR, "TOPLEFT", RX + CW / 2, -250)
end

-- ---------------------------------------------------------------- view

function View.new(page, left, right)
  local self = setmetatable({ page = page, ui = {}, filter = "all" }, View)
  local ui = self.ui
  local tab = CreateFrame("Frame", nil, left)
  tab:SetAllPoints(left)
  tab:SetFrameLevel(left:GetFrameLevel() + 12)
  ui.table = tab
  local tabR = CreateFrame("Frame", nil, right)
  tabR:SetAllPoints(right)
  ui.tableR = tabR
  -- names of items come late from the client: the view redraws once when they are there (only while it is open)
  if Journal.Live and Journal.Live.itemNames then
    self.names = Journal.Live.itemNames(tab, function() if self.open then self:Render() end end, 48)
  end
  buildLeft(self, tab)
  buildRight(self, tabR)
  D.escKeys(tab, function() Pages.escape(page.id or "handwerk") end) -- Esc -> the first sub-bookmark (professions)
  tab:Hide()
  tabR:Hide()
  View.current = self
  return self
end

function View:IsOpen() return self.open == true end

-- redraw of the open recipe book (RB.redraw)
function View.redraw()
  local v = View.current
  if v and v.open then v:Render() end
end

function View:SelectProfession(key)
  for _, e in ipairs(self.profs or {}) do
    if e.key == key then
      self.profKey, self.sel = key, nil
      self.ui.recList:SetOffset(0)
      self:Render()
      return true
    end
  end
  return false
end

function View:SelectRecipe(id)
  for _, r in ipairs(self.items or {}) do
    if r.id == id then
      self.sel = id
      self:Render()
      return true
    end
  end
  return false
end

function View:SetFilter(key)
  if key ~= "all" and key ~= "learned" and key ~= "open" then return false end
  self.filter = key
  self.ui.recList:SetOffset(0)
  self:Render()
  return true
end

local function drawDetail(self, rec)
  local ui = self.ui
  for _, m in ipairs(ui.mats) do
    W.setText(m.fs, "")
    m.frame.tipSpec = nil
    m.frame:Hide()
  end
  ui.dOut.tipSpec = nil
  ui.dOut:Hide()
  ui.dHint:SetText("")
  ui.needs:Hide()
  if not rec then
    W.setText(ui.dHead, "")
    W.setText(ui.dMeta, "")
    W.setText(ui.dHint, T.pick)
    ui.dRule:Hide()
    return
  end
  ui.dRule:Show()
  W.setText(ui.dHead, rec.name)
  local c = diffColor(rec)
  ui.dHead:SetTextColor(W.color(rec.learned and c or "ink"))
  local meta = { stateText(rec) }
  local d = RB.diffText(rec.diff)
  if d then meta[#meta + 1] = T("tipDifficulty", d) end
  if rec.ups and rec.ups > 1 then meta[#meta + 1] = T("tipUps", int(rec.ups)) end
  if rec.src then meta[#meta + 1] = T("tipSource", rec.src) end
  W.setText(ui.dMeta, table.concat(meta, " · "))
  if not rec.details then
    W.setText(ui.dHint, T.detailNoCache)
    return
  end
  if rec.out then
    local name = itemName(self, rec.out)
    W.setText(ui.dOutText, (rec.qty and rec.qty > 1) and T("outputQty", int(rec.qty), name) or T("output", name))
    ui.dOut.tipSpec = { item = rec.out, text = { name }, stock = true }
    paintIcon(ui.dOutIcon, itemIcon(rec.out) or rec.icon or ICON_FALLBACK)
    ui.dOut:Show()
  end
  local n = #rec.reagents
  if n == 0 then
    W.setText(ui.dHint, T.noMats)
    return
  end
  ui.needs:Show()
  local shown = n > MAT_LINES and (MAT_LINES - 1) or n
  for i = 1, shown do
    local m, line = rec.reagents[i], ui.mats[i]
    local name = itemName(self, m.id)
    W.setText(line.fs, int(m.qty) .. "× " .. name)
    line.frame.tipSpec = { item = m.id, text = { name }, stock = true }
    paintIcon(line.icon, itemIcon(m.id) or ICON_FALLBACK)
    line.frame:Show()
  end
  if n > shown then
    local line = ui.mats[MAT_LINES]
    W.setText(line.fs, T("moreMats", int(n - shown)))
    hideIcon(line.icon)
    line.frame:Show()
  end
end

function View:Render()
  local ui = self.ui
  if not self.open then return end
  local profs = RB.professions()
  self.profs = profs
  local found
  for _, e in ipairs(profs) do
    if e.key == self.profKey then found = e end
  end
  if not found then
    found = profs[1]
    self.profKey = found and found.key or nil
    self.sel = nil
  end
  ui.profList:SetItems(profs)
  local player = W.playerLine and W.playerLine(self.page and self.page.data) or ""
  ui.headR:SetTexts(player or "", T.page)
  ui.filter:SetValue(self.filter)
  local none = found == nil
  ui.filter.frame:SetShown(not none)
  ui.recList.frame:SetShown(not none)
  ui.recHead:SetShown(not none)
  ui.recRule:SetShown(not none)
  ui.legendHead:SetShown(not none)
  for _, l in ipairs(ui.legend) do
    l.fs:SetShown(not none)
    W.setText(l.fs, RB.diffText(l.d) or "")
  end
  if ui.pager then
    ui.pager.pair.frame:SetShown(not none)
    ui.pager.label:SetShown(not none)
  end
  if none then
    self.items = {}
    W.setText(ui.rTitle, T.title)
    W.setText(ui.rSub, "")
    W.setText(ui.count, "")
    W.setText(ui.note, "")
    W.setText(ui.rEmpty, T.noProfBody)
    drawDetail(self, nil)
    ui.dHint:SetText("")
    ui.dHead:SetText("")
    return
  end
  W.setText(ui.rEmpty, "")
  local rows, counts = RB.recipes(found, self.filter)
  self.items = rows
  self.counts = counts
  -- the chosen recipe stays while it is in the list; else the first one
  local rec
  for _, r in ipairs(rows) do
    if r.id == self.sel then rec = r end
  end
  if not rec then
    rec = rows[1]
    self.sel = rec and rec.id or nil
  end
  local empty = T.emptyList
  if counts.all > 0 then empty = self.filter == "open" and T.emptyFilterOpen or T.emptyFilterLearned end
  ui.recList.opts.empty = empty
  ui.recList:SetItems(rows)
  W.setText(ui.rTitle, found.name)
  if found.rank and found.max then
    W.setText(ui.rSub, T("profSub", int(found.rank), int(found.max)))
  elseif found.rank then
    W.setText(ui.rSub, T("profSubNoMax", int(found.rank)))
  else
    W.setText(ui.rSub, "")
  end
  W.setText(ui.count, counts.all > 0 and T("countLine", int(counts.learned), int(counts.open)) or "")
  W.setText(ui.note, found.cached and T.hintCache or T.hintNoCache)
  drawDetail(self, rec)
end

function View:Open()
  self.open = true
  self.ui.table:Show()
  self.ui.tableR:Show()
  self:Render()
end

function View:Refresh()
  if self.open then self:Render() end
end

function View:Close()
  local ui = self.ui
  self.open = false
  for _, r in ipairs(ui.recList.rows) do W.hideTip(r) end
  for _, r in ipairs(ui.profList.rows) do W.hideTip(r) end
  W.hideTip(ui.dOut)
  for _, m in ipairs(ui.mats) do W.hideTip(m.frame) end
  if self.names and self.names.stop then self.names.stop() end
  ui.table:Hide()
  ui.tableR:Hide()
end
