-- Sub-view "Zonen" of the Quests page (registered by pages/Quests.lua, last sub-bookmark), WoW Forever only (change
-- "zonenuebersicht", builds on "zone-abgeschlossen"). Goal: see at a glance how far every zone of the journey is done.
-- Left page: title, "Zonen abgeschlossen x / y", progress of the medal "Zonenkenner", below the zones of the first continent (the one
-- where the journey began, else the one with the lowest zones). Right page: counting rule and legend, below the other continent(s).
-- Every row: zone name, level span, progress bar and "NN % (x/y)" (the same text as the zone row of the chapter card,
-- Frame.zoneRowInfo); 100 %: gold with the stamp of the medal like on the chapter card. Zones never entered stay pale but visible.
-- Tooltip: the tooltip of ZoneProgress (open quests, "... und N weitere", unsure beta data). Click: sub-view "Offen" of that zone.
-- Values only from journal/model/ZoneProgress.lua (no own counting, no saved fields). The list is built when the view opens, kept
-- and built again only when a sweep finished (ZoneProgress.summary changes), the quest data changed (OpenQuests.generation) or the
-- journey index changed (zones entered). Without a sweep yet the existing sweep of ZoneProgress is started once (time budget per
-- frame) and the view waits for it.
-- Foreign text (zone names, quest names in the tooltip) comes from OpenQuests/ZoneProgress already sanitized and is shown via
-- SetText/AddLine only. No ticker, no OnUpdate; rows are pooled (List).
-- Keep-outs (DecorKeepout quests): left everything ends before y 474 (blot), title from y 72 (wax drop); right everything stays
-- left of x 446 and above y 578.
local _, ns = ...

local Journal = ns.Journal
local W, Pages, ZP, OQ = Journal and Journal.Widgets, Journal and Journal.Pages, Journal and Journal.ZoneProgress, Journal and Journal.OpenQuests
local D = W and W.Diary
if not (W and Pages and ZP and OQ and D) then return end

local floor, max, min, sort = math.floor, math.max, math.min, table.sort
local Theme = Journal.Theme
local G = Theme.GRID
local GREEN = Theme.INK and Theme.INK.green or "ink"

local View = {}
View.__index = View
Journal.ZonesView = View

-- texts (German here, English in locales/enUS_pages.lua, scope "p.QuestsZonen"; read only on build/draw)
local T = ns.Locale.ns("p.QuestsZonen", {
  brand = "INK & EMBERS", book = "QUESTBUCH", page = "ZONENÜBERSICHT", title = "Zonen",
  head = "Zonen abgeschlossen %s / %s", partial = "Tagebuch wird noch gelesen: vorläufiger Stand",
  medalNone = "Medaille „%s“: %s von %s Zonen bis %s",
  medalNext = "Medaille „%s“: %s · %s von %s Zonen bis %s",
  medalMax = "Medaille „%s“: %s · %s Zonen",
  medalTipSteps = "Bronze %s · Silber %s · Gold %s Zonen",
  medalTipKeep = "Eine abgeschlossene Zone bleibt gezählt, auch wenn neue Quests dazukommen.",
  contHead = "%s von %s abgeschlossen",
  otherCont = "Weitere Gebiete",
  levelSpan = "Stufe %s–%s", levelOne = "Stufe %s",
  rule = "Gezählt werden Zonen mit mindestens %s Quests für Euch (eigene Fraktion, eigenes Volk und eigene Klasse). Gruppen-, wiederholbare und Berufsquests zählen nicht.",
  legendDone = "abgeschlossen", legendPale = "blass: noch nicht betreten", legendClick = "Klick: offene Quests",
  clickTip = "Klicken: offene Quests dieser Zone", notVisited = "Diese Zone habt Ihr noch nicht betreten.",
  noData = "Questdaten nicht geladen", noDataHint = "Prüfen mit /chronik diag",
  noDataRight = "Die Zonen erscheinen, sobald die Questdaten geladen sind.",
  computing = "Die Zonen werden berechnet …", computingRight = "Einen Augenblick: die Quests aller Zonen werden gezählt.",
  combat = "Im Kampf wird nichts berechnet.", combatRight = "Die Übersicht erscheint nach dem Kampf.",
  empty = "Noch keine Zone zählt.", emptyBody = "Eine Zone erscheint hier, sobald sie mindestens %s Quests für Euch hat.",
  prevPage = "Vorige Seite", nextPage = "Nächste Seite",
})
View.TEXT = T

local LX, LW = Theme.gridX("L")
local RX, RW = Theme.gridX("R")
local TITLE_Y = G.slots.title.y
local TITLE_L_Y = 72 -- wax drop top left (keep-out x 128..196 down to y 72): the left title starts below it
local SUB_Y = TITLE_Y + 34
local CTRL_CY = G.slots.ctrl.y + 12
local BODY_Y = G.slots.body.y
local LEFT_END = 474 -- blot bottom left (keep-out y 478..601) stays free
local RIGHT_END = 574 -- right page: above y 578
local ROW_H = 32
local PAGER_H = 28 -- page switch under each list (right-aligned: the blot bottom left is x 40..154, the pager stays right of it)
local ROWS_L = floor((LEFT_END - BODY_Y) / ROW_H)
local ROWS_R = floor((RIGHT_END - PAGER_H - BODY_Y) / ROW_H)
local PAGER_L_CY = BODY_Y + ROWS_L * ROW_H + 14
local PAGER_R_CY = BODY_Y + ROWS_R * ROW_H + 14
local VALUE_W = 140
local LEVEL_W = 84
local BAR_H = 4
local STAMP = 16
local MEDAL = 24
View.ROWS_L, View.ROWS_R, View.ROW_H = ROWS_L, ROWS_R, ROW_H

local EMPTY = {}

local function int(n) return Journal.Texts.int(n) end
local function kit() return Journal.QuestsPage and Journal.QuestsPage.kit end

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function label(parent, kind, size, color, justify)
  local fs = W.font(parent, kind, size, color)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

local function strWidth(fs, text)
  for _, m in ipairs({ "GetUnboundedStringWidth", "GetStringWidth" }) do
    local fn = fs[m]
    if type(fn) == "function" then
      local ok, v = pcall(fn, fs)
      v = ok and tonumber(v) or nil
      if v and v == v and v > 0 then return v end
    end
  end
  return #(text or "") * 6
end

-- ---------------------------------------------------------------- data (only ZoneProgress, OpenQuests, the journey index)

-- level span of a zone from the levels of its counted quests: from the 5th to the 80th percentile, so stray quests do not stretch
-- the span (Tirisfal carries a few level 53-60 quests besides the 1-12 ones) -> lo, hi | nil
function View.levelBand(units)
  local lv = {}
  for _, u in ipairs(units or EMPTY) do
    local r = OQ.record(u.id, true)
    local l = r and num(r.level or r.minLevel)
    if l and l > 0 then lv[#lv + 1] = floor(l) end
  end
  local n = #lv
  if n == 0 then return nil end
  sort(lv)
  return lv[1 + floor((n - 1) * 0.05)], lv[1 + floor((n - 1) * 0.8 + 0.5)]
end

-- zones the character has entered: ZN lines (map and its main zone) of the journey index -> { [mapID] = order of the first
-- arrival (1 = the first zone of the journey) }
local function visitedSet(index)
  local out, n = {}, 0
  local Idx = Journal.Index
  if type(index) ~= "table" or not Idx then return out end
  for _, r in ipairs(Idx.list(index, "ZN")) do
    for _, field in ipairs({ "mapID", "zone" }) do
      local id = num(Idx.num(r, "ZN", field))
      if id and not out[id] then
        n = n + 1
        out[id] = n
      end
    end
  end
  return out
end

local function continentOf(mapID)
  local OV = Journal.OpenQuestsView
  return OV and OV.continentOfZone and OV.continentOfZone(mapID) or nil
end

-- the text of the chapter card (identical values), else the same format here
local function valueText(res)
  local F = Journal.Frame
  if F and type(F.zoneRowInfo) == "function" then
    local ok, info = pcall(F.zoneRowInfo, { zoneID = res.mapID })
    if ok and type(info) == "table" and type(info.value) == "string" then return info.value end
  end
  return tostring(res.pct or 0) .. " % (" .. tostring(res.done) .. "/" .. tostring(res.total) .. ")"
end

-- the overview: { groups = { { id, name, zones = { row... }, complete }... }, total, complete, partial, combat } | nil, reason.
-- row = { mapID, name, lo, hi, pct, done, total, log, open, complete, partial, unsure, visited, value }
function View.build(index)
  local ok, why = ZP.available()
  if not ok then return nil, why end
  local visited = visitedSet(index)
  local byCont, groups = {}, {}
  local out = { groups = groups, total = 0, complete = 0, partial = false, combat = false }
  for id in pairs(OQ.zoneIndex() or EMPTY) do
    if ZP.zoneKey(id) then
      local res, reason = ZP.of(id)
      if not res and reason == "COMBAT" then out.combat = true end
      if res and not res.small and res.pct then
        local lo, hi = View.levelBand(res.units)
        local row = { mapID = res.mapID, name = OQ.mapName(res.mapID) or tostring(res.mapID), lo = lo, hi = hi, pct = res.pct,
          done = res.done, total = res.total, log = res.log or 0, open = res.open or 0, complete = res.complete == true,
          partial = res.partial == true, unsure = res.unsure or 0 }
        row.visited = visited[row.mapID] ~= nil or (row.done or 0) > 0
        row.value = valueText(res)
        local cid = continentOf(row.mapID) or 0
        local g = byCont[cid]
        if not g then
          g = { id = cid, zones = {}, complete = 0 }
          byCont[cid] = g
          groups[#groups + 1] = g
        end
        g.zones[#g.zones + 1] = row
        local first = visited[row.mapID]
        if first and (not g.first or first < g.first) then g.first = first end
        if row.complete then g.complete = g.complete + 1 end
        out.total = out.total + 1
        if row.complete then out.complete = out.complete + 1 end
        if row.partial then out.partial = true end
      end
    end
  end
  local names = {}
  for _, c in ipairs(OQ.continents()) do names[c.id] = c.name end
  for _, g in ipairs(groups) do
    g.name = names[g.id] or T.otherCont
    sort(g.zones, function(a, b)
      local la, lb = a.lo or 999, b.lo or 999
      if la ~= lb then return la < lb end
      local ha, hb = a.hi or 999, b.hi or 999
      if ha ~= hb then return ha < hb end
      if a.name ~= b.name then return a.name < b.name end
      return a.mapID < b.mapID
    end)
    g.lo = g.zones[1] and g.zones[1].lo or 999
  end
  -- the continent where the journey began first (earliest entered zone), else the one with the lowest zone; zones without a
  -- continent last
  sort(groups, function(a, b)
    if (a.id == 0) ~= (b.id == 0) then return b.id == 0 end
    if (a.first ~= nil) ~= (b.first ~= nil) then return a.first ~= nil end
    if a.first and a.first ~= b.first then return a.first < b.first end
    if a.lo ~= b.lo then return a.lo < b.lo end
    return a.id < b.id
  end)
  return out
end

-- medal "Zonenkenner": counter value, earned tiers, next step
function View.medal()
  local C = Journal.Chronik
  local seal = C and C.SEAL_BY_ID and C.SEAL_BY_ID.zone_master
  if not seal then return nil end
  local char = ns.Store and ns.Store.current or nil
  local v = (C.counterValue and C.counterValue("zone_master", char)) or 0
  local n = (C.stepsFor and C.stepsFor("zone_master", v)) or 0
  local steps = seal.steps or EMPTY
  local tier = n > 0 and C.TIER_ORDER[n] or nil
  local nextTier = C.TIER_ORDER[n + 1]
  local function tierName(id) return id and C.TIERS and C.TIERS[id] and C.TIERS[id].name or "" end
  local m = { seal = seal, value = v, n = n, tier = tier, need = steps[n + 1], tierName = tierName(tier), nextName = tierName(nextTier) }
  if not tier then
    m.text = T("medalNone", seal.title, int(v), int(m.need or 0), m.nextName)
  elseif m.need then
    m.text = T("medalNext", seal.title, m.tierName, int(v), int(m.need), m.nextName)
  else
    m.text = T("medalMax", seal.title, m.tierName, int(v))
  end
  m.tip = { seal.title, seal.need or "", T("medalTipSteps", int(steps[1] or 0), int(steps[2] or 0), int(steps[3] or 0)), T.medalTipKeep }
  return m
end

-- ---------------------------------------------------------------- stamp (motif + ring of the medal, like the chapter card)

local function newStamp(parent, size, layer)
  local s = { size = size }
  s.motif = parent:CreateTexture(nil, layer or "ARTWORK")
  s.ring = parent:CreateTexture(nil, "OVERLAY")
  s.ring:SetSize(size, size)
  s.motif:SetPoint("CENTER", s.ring, "CENTER", 0, 0)
  s.motif:Hide()
  s.ring:Hide()
  return s
end

local function setStamp(s, tier, alpha)
  local C = Journal.Chronik
  local seal = C and C.SEAL_BY_ID and C.SEAL_BY_ID.zone_master
  local motif, ring = Theme.sealLayers(seal, tier or "bronze")
  for _, pair in ipairs({ { s.motif, motif }, { s.ring, ring } }) do
    local t, layer = pair[1], pair[2]
    if layer and layer.tex then
      t:SetTexture(layer.tex)
      local co = layer.coords
      if co then t:SetTexCoord(co[1], co[2], co[3], co[4]) else t:SetTexCoord(0, 1, 0, 1) end
      local px = floor(s.size * (layer.scale or 1) + 0.5)
      t:SetSize(px, px)
      local col = layer.color or { 1, 1, 1 }
      t:SetVertexColor(col[1], col[2], col[3], alpha or 1)
      t:Show()
    else
      t:Hide()
    end
  end
end

local function hideStamp(s)
  s.motif:Hide()
  s.ring:Hide()
end

-- ---------------------------------------------------------------- rows

local function rowTip(row)
  local lines, colors = ZP.tooltip(row.mapID)
  local out, cols = {}, {}
  for i, l in ipairs(lines or { row.name }) do
    out[i] = l
    cols[i] = colors and colors[i] or nil
  end
  local label = ZP.TIP_COLOR and ZP.TIP_COLOR.label or nil
  if not row.visited then
    out[#out + 1] = T.notVisited
    cols[#out] = label
  end
  out[#out + 1] = T.clickTip
  return out, cols
end

local function levelText(row)
  if not row.lo then return "" end
  if row.lo == row.hi then return T("levelOne", int(row.lo)) end
  return T("levelSpan", int(row.lo), int(row.hi))
end

local function newList(self, parent, x, rows, width)
  local nameW = width - VALUE_W - 12
  local barX = LEVEL_W + 6
  local barW = width - barX - 8
  local list = W.NewList(parent, { rows = rows, rowHeight = ROW_H, width = width + 10, step = 3, empty = "", emptyHand = true,
    build = function(row)
      row.label:ClearAllPoints()
      row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -3)
      row.label:SetWidth(nameW)
      pcall(row.label.SetFont, row.label, W.FONT.text, G.size.m, "")
      row.value = label(row, "label", G.size.s, "ink", "RIGHT")
      row.value:SetWidth(VALUE_W)
      row.value:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -4)
      row.lvl = label(row, "label", G.size.xs, "sepia")
      row.lvl:SetWidth(LEVEL_W)
      row.lvl:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -19)
      row.barBg = W.NewRect(row, "sepia", 0.22, "ARTWORK")
      row.barBg:SetSize(barW, BAR_H)
      row.barBg:SetPoint("TOPLEFT", row, "TOPLEFT", barX, -23)
      row.barDone = W.NewRect(row, GREEN, 0.9, "ARTWORK")
      row.barDone:SetHeight(BAR_H)
      row.barDone:SetPoint("TOPLEFT", row.barBg, "TOPLEFT", 0, 0)
      row.barW = barW
      row.stamp = newStamp(row, STAMP)
      -- continent head (handwriting, red) with its count
      row.hand = D.font(row, "hand", 20, "red")
      row.hand:SetWordWrap(false)
      row.hand:SetJustifyH("LEFT")
      row.hand:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 4)
      row.handCount = label(row, "label", G.size.xs, "sepia", "RIGHT")
      row.handCount:SetWidth(VALUE_W + 40)
      row.handCount:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 6)
      row.handLine = D.NewInkStroke(row, nil, "red", 0.35)
      row.handLine:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)
      row.handLine:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 1)
      D.RowStyle(row, { texts = { row.label, row.value } })
      row:HookScript("OnEnter", function(r) if r.tipLines then W.tip(r, r.tipLines, r.tipColors) end end)
      row:HookScript("OnLeave", function(r) W.hideTip(r) end)
    end,
    clear = function(row)
      row:SetSelected(false)
      row.value:SetText("")
      row.lvl:SetText("")
      row.hand:SetText("")
      row.handCount:SetText("")
      row.handLine:Hide()
      row.barBg:Hide()
      row.barDone:Hide()
      hideStamp(row.stamp)
      row.tipLines, row.tipColors, row.isHead = nil, nil, nil
      row.label:SetTextColor(W.color("ink"))
      row.label:SetAlpha(1)
      row.lvl:SetAlpha(1)
      row.value:SetAlpha(1)
    end,
    fill = function(row, it)
      if it.head then
        row.isHead = true
        W.setText(row.hand, it.name)
        W.setText(row.handCount, T("contHead", int(it.complete), int(#it.zones)))
        row.handLine:Show()
        return
      end
      local z = it
      local pale = not z.visited
      local a = pale and 0.55 or 1
      W.setText(row.label, z.name)
      row.label:SetTextColor(W.color(pale and "sepia" or "ink"))
      W.setText(row.value, z.value)
      row.value:SetTextColor(W.color(z.complete and "gold" or (pale and "sepia" or "ink")))
      W.setText(row.lvl, levelText(z))
      row.label:SetAlpha(pale and 0.8 or 1)
      row.lvl:SetAlpha(pale and 0.75 or 1)
      row.value:SetAlpha(pale and 0.8 or 1)
      row.barBg:SetAlpha(pale and 0.6 or 1)
      row.barBg:Show()
      local w = z.total > 0 and floor(row.barW * z.done / z.total + 0.5) or 0
      row.barDone:SetColorTexture(W.color(z.complete and "gold" or GREEN, 0.9 * a))
      row.barDone:SetWidth(max(w, 1))
      row.barDone:SetShown(w > 0)
      if z.complete then
        local sw = strWidth(row.value, z.value)
        row.stamp.ring:ClearAllPoints()
        row.stamp.ring:SetPoint("RIGHT", row, "TOPRIGHT", -(4 + min(sw, VALUE_W) + 4), -4 - 7)
        setStamp(row.stamp, self.tier, a)
      end
      row.tipLines, row.tipColors = rowTip(z)
      D.rowFilled(row)
    end,
    onClick = function(it) if not it.head then self:OpenZone(it.mapID) end end })
  list.frame:ClearAllPoints()
  list.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -BODY_Y)
  return list
end

local function setPagerShown(p, on)
  if not p then return end
  p.pair.frame:SetShown(on)
  p.label:SetShown(on)
end

-- ---------------------------------------------------------------- building

function View.new(page, left, right)
  local self = setmetatable({ page = page, ui = {} }, View)
  local ui = self.ui
  local tab = CreateFrame("Frame", nil, left)
  tab:SetAllPoints(left)
  tab:SetFrameLevel(left:GetFrameLevel() + 12)
  ui.table = tab
  local tabR = CreateFrame("Frame", nil, right)
  tabR:SetAllPoints(right)
  ui.tableR = tabR
  ui.headL = W.NewPageHead(tab, { side = "L" })
  ui.headL:SetTexts(T.brand, T.book)
  ui.headR = W.NewPageHead(tabR, { side = "R" })
  ui.headR:SetTexts("", T.page)

  -- left: title, count, medal; below the first continent
  local f = CreateFrame("Frame", nil, tab)
  f:SetAllPoints(tab)
  ui.mainL = f
  ui.title = label(f, "title", G.size.l, "ink")
  ui.title:SetPoint("TOPLEFT", f, "TOPLEFT", LX, -TITLE_L_Y)
  ui.title:SetText(T.title)
  ui.count = label(f, "label", G.size.s, "ink")
  ui.count:SetWidth(LW)
  ui.count:SetPoint("TOPLEFT", f, "TOPLEFT", LX, -SUB_Y)
  local medal = CreateFrame("Frame", nil, f)
  medal:SetSize(LW, MEDAL + 4)
  medal:SetPoint("LEFT", f, "TOPLEFT", LX, -CTRL_CY)
  medal:EnableMouse(true)
  medal:SetScript("OnEnter", function(m) if m.tipLines then W.tip(m, m.tipLines, { [3] = ZP.TIP_COLOR and ZP.TIP_COLOR.label, [4] = ZP.TIP_COLOR and ZP.TIP_COLOR.label }) end end)
  medal:SetScript("OnLeave", function(m) W.hideTip(m) end)
  ui.medal = medal
  ui.medalStamp = newStamp(medal, MEDAL)
  ui.medalStamp.ring:SetPoint("LEFT", medal, "LEFT", 0, 0)
  ui.medalText = label(medal, "label", G.size.s, "ink")
  ui.medalText:SetWidth(LW - MEDAL - 6)
  ui.medalText:SetPoint("LEFT", medal, "LEFT", MEDAL + 6, 0)
  ui.listL = newList(self, f, LX, ROWS_L, LW)
  local K = kit()
  if K and K.pager then ui.pagerL = K.pager(f, ui.listL, LX, LW, PAGER_L_CY, { T.prevPage, T.nextPage }) end
  D.escKeys(f, function() Pages.escape(self.page.id or "quests") end)

  -- right: rule and legend; below the other continent(s)
  local r = CreateFrame("Frame", nil, tabR)
  r:SetAllPoints(tabR)
  ui.mainR = r
  ui.rule = W.font(r, "label", G.size.xs, "sepia")
  ui.rule:SetJustifyH("LEFT")
  ui.rule:SetJustifyV("TOP")
  ui.rule:SetWidth(RW)
  ui.rule:SetPoint("TOPLEFT", r, "TOPLEFT", RX, -(TITLE_Y + 10)) -- below the top right decoration (keep-out to y 72)
  ui.legendStamp = newStamp(r, STAMP)
  ui.legendStamp.ring:SetPoint("LEFT", r, "TOPLEFT", RX, -CTRL_CY)
  ui.legend = label(r, "label", G.size.xs, "sepia")
  ui.legend:SetWidth(RW - STAMP - 4)
  ui.legend:SetPoint("LEFT", r, "TOPLEFT", RX + STAMP + 4, -CTRL_CY)
  ui.listR = newList(self, r, RX, ROWS_R, RW)
  if K and K.pager then ui.pagerR = K.pager(r, ui.listR, RX, RW, PAGER_R_CY, { T.prevPage, T.nextPage }) end

  -- empty states (no data, computing, combat, no zone)
  ui.emptyHead = label(tab, "title", G.size.l, "ink", "CENTER")
  ui.emptyHead:SetWidth(LW)
  ui.emptyHead:SetPoint("TOP", tab, "TOPLEFT", LX + LW / 2, -230)
  ui.emptyBody = D.emptyNote(tab, LW - 60)
  ui.emptyBody:SetPoint("TOP", tab, "TOPLEFT", LX + LW / 2, -270)
  ui.emptyRight = D.emptyNote(tabR, RW - 60)
  ui.emptyRight:SetPoint("TOP", tabR, "TOPLEFT", RX + RW / 2, -290)
  -- source line in the footer: flush with the fold, right of x 154 (blot bottom left stays free)
  local fp, fx, fy = Theme.gridFoot("L")
  ui.foot = W.font(tab, "label", G.size.xs, "sepia")
  ui.foot:SetJustifyH("RIGHT")
  ui.foot:SetPoint(fp, tab, "TOPLEFT", fx, -fy)
  ui.foot:SetWidth(LW - 100)
  ui.foot:SetJustifyV("TOP")
  ZP.onChange(function() if self.open then W.call(self.OnZonesChanged, self) end end)
  -- combat blocked the first build: build right after the fight
  tab:SetScript("OnEvent", function(fr)
    if fr.UnregisterEvent then fr:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    if self.open then
      self.model = nil
      W.call(self.Render, self)
    end
  end)
  tab:Hide()
  tabR:Hide()
  return self
end

function View:IsOpen() return self.open == true end

-- ---------------------------------------------------------------- actions

-- click on a zone: sub-view "Offen" with this zone
function View:OpenZone(mapID)
  mapID = num(mapID)
  if not mapID then return false end
  local page = self.page
  page:ShowSub("offen")
  Pages.subChanged("quests")
  if page.openView and page.openOpen then
    page.openView:SetZone(mapID)
    return true
  end
  return false
end

-- key of the state the list was built from: a finished sweep, the quest data and the journey index
local function stateKey(self)
  local g, n = OQ.generation()
  local data = self.page and self.page.data
  return { summary = ZP.summary(), g = g, n = n, index = data and data.index or nil }
end

local function sameKey(a, b)
  return a and b and a.summary == b.summary and a.g == b.g and a.n == b.n and a.index == b.index
end

-- a sweep finished or the quest state changed: build again only when the state is a new one
function View:OnZonesChanged()
  if not self.open then return end
  if self.waiting or not sameKey(self.key, stateKey(self)) then self:Render() end
end

function View:ShowEmpty(head, body, right)
  local ui = self.ui
  ui.mainL:Hide()
  ui.mainR:Hide()
  ui.emptyHead:Show()
  ui.emptyBody:Show()
  ui.emptyRight:Show()
  W.setText(ui.emptyHead, head)
  W.setText(ui.emptyBody, body)
  W.setText(ui.emptyRight, right)
end

local function hideEmpty(ui)
  ui.emptyHead:Hide()
  ui.emptyBody:Hide()
  ui.emptyRight:Hide()
end

-- items of one page: per continent a head row, then its zones
local function itemsOf(groups)
  local items = {}
  for _, g in ipairs(groups) do
    items[#items + 1] = { head = true, name = g.name, complete = g.complete, zones = g.zones }
    for _, z in ipairs(g.zones) do items[#items + 1] = z end
  end
  return items
end

function View:Render()
  if not self.open then return end
  local ui = self.ui
  self.waiting = false
  -- load the quest data like "Offen" and "Dungeons" (never in combat; OpenQuests keeps the reason)
  if not ZP.available() then OQ.available() end
  local ok, why = ZP.available()
  W.setText(ui.foot, ok and OQ.footer() or "")
  if not ok then
    self.model = nil
    if why == "COMBAT" and ui.table.RegisterEvent then ui.table:RegisterEvent("PLAYER_REGEN_ENABLED") end
    return self:ShowEmpty(T.noData, (OQ.reasonText and OQ.reasonText(why) or tostring(why)) .. ". " .. T.noDataHint, T.noDataRight)
  end
  -- no sweep yet (shortly after login): start the existing one; it may finish at once or report via onChange
  if ZP.summary() == nil then
    local started, reason = ZP.sweep()
    if ZP.summary() == nil then
      self.waiting = true
      if reason == "COMBAT" and ui.table.RegisterEvent then ui.table:RegisterEvent("PLAYER_REGEN_ENABLED") end
      if started or reason == "COMBAT" then return self:ShowEmpty(T.computing, "", T.computingRight) end
    end
  end
  local key = stateKey(self)
  if not (self.model and sameKey(self.key, key)) then
    local data = self.page and self.page.data
    local model, reason = View.build(data and data.index)
    if not model then
      self.model = nil
      return self:ShowEmpty(T.noData, (OQ.reasonText and OQ.reasonText(reason) or tostring(reason)) .. ". " .. T.noDataHint, T.noDataRight)
    end
    if model.combat and model.total == 0 then
      self.model = nil
      if ui.table.RegisterEvent then ui.table:RegisterEvent("PLAYER_REGEN_ENABLED") end
      return self:ShowEmpty(T.combat, "", T.combatRight)
    end
    self.model, self.key = model, key
    if model.combat and ui.table.RegisterEvent then ui.table:RegisterEvent("PLAYER_REGEN_ENABLED") end
  end
  local m = self.model
  if m.total == 0 then return self:ShowEmpty(T.empty, T("emptyBody", int(ZP.MIN_QUESTS)), "") end
  hideEmpty(ui)
  ui.mainL:Show()
  ui.mainR:Show()
  local medal = View.medal()
  self.tier = medal and medal.tier or "bronze"
  local head = T("head", int(m.complete), int(m.total))
  local testText = OQ.testLabel()
  if testText then head = head .. " · " .. testText elseif m.partial then head = head .. " · " .. T.partial end
  W.setText(ui.count, head)
  W.setText(ui.medalText, medal and medal.text or "")
  ui.medal.tipLines = medal and medal.tip or nil
  if medal then setStamp(ui.medalStamp, medal.tier, medal.tier and 1 or 0.45) else hideStamp(ui.medalStamp) end
  W.setText(ui.rule, T("rule", int(ZP.MIN_QUESTS)))
  W.setText(ui.legend, T.legendDone .. " · " .. T.legendPale .. " · " .. T.legendClick)
  setStamp(ui.legendStamp, self.tier, 1)
  local left, right = {}, {}
  for i, g in ipairs(m.groups) do
    if i == 1 then left[1] = g else right[#right + 1] = g end
  end
  ui.listL:SetItems(itemsOf(left))
  ui.listL:Refresh()
  ui.listR:SetItems(itemsOf(right))
  ui.listR:Refresh()
  setPagerShown(ui.pagerL, ui.listL:MaxOffset() > 0)
  setPagerShown(ui.pagerR, ui.listR:MaxOffset() > 0)
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

-- tooltips off (page hidden; the view stays as it is)
function View:OnPageHide()
  local ui = self.ui
  for _, list in ipairs({ ui.listL, ui.listR }) do
    for _, r in ipairs(list and list.rows or EMPTY) do W.hideTip(r) end
  end
  W.hideTip(ui.medal)
end

function View:Close()
  self.open = false
  self:OnPageHide()
  self.ui.table:Hide()
  self.ui.tableR:Hide()
end
