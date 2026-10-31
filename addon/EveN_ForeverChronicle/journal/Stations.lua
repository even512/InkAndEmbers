-- "Stations of the journey" (overall journey, bottom of the left page): compact two-column timeline of milestones
-- (levels 10/20/..., new continent, first instance, first rare, longest day, favourite zone).
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Stations = {}
Journal.Stations = Stations

local floor, max, min, huge = math.floor, math.max, math.min, math.huge

Stations.LEVEL_STEP = 10
Stations.MAX = 40              -- safety cap (SV can be edited from outside)
Stations.COLS = 2
Stations.ROWS = 5
Stations.ROW_H = 34
Stations.HEAD_H = 26
Stations.HEAD_SIZE = 20
Stations.NAME_SIZE = 17
Stations.SUB_SIZE = 11
Stations.DOT = 9
Stations.TEXT = ns.Locale.ns("Stations", {
  title = "Stationen der Reise",
  empty = "Noch keine Stationen. Die Reise beginnt gerade.",
  level = "Stufe %d",
  continent = "Ankunft: ",
  newContinent = "Neuer Kontinent",
  instance = "Erste Instanz",
  rare = "Erster Seltener",
  day = "Längster Tag",
  zone = "Lieblingszone",
  tipJump = "Klick: die Wiedergabe springt hierher",
  afterPlayed = "nach %s Spielzeit",
  playedInDay = "%s an einem Tag gespielt",
  spentThere = "%s dort verbracht",
  tipPrev = "Frühere Stationen",
  tipNext = "Spätere Stationen",
  pageOf = "Seite %s von %s",
  dateFmt = "%d.%m.",
})

local function finite(v) return type(v) == "number" and v == v and v ~= huge and v ~= -huge end

local function display(s, n)
  local S = ns.Sanitize
  if type(s) ~= "string" or not (S and S.display) then return nil end
  return S.display(s, n or 40)
end

function Stations.dayText(when)
  if type(when) ~= "string" then return nil end
  return when:match("^(%S+ %d+)")
end

function Stations.dateText(t)
  if not finite(t) then return nil end
  local ok, s = pcall(date, Stations.TEXT.dateFmt, t)
  return (ok and type(s) == "string" and s ~= "") and s or nil
end

function Stations.subText(when, t, detail)
  local bits = {}
  local d = Stations.dayText(when)
  if d then bits[#bits + 1] = d end
  local dt = Stations.dateText(t)
  if dt then bits[#bits + 1] = dt end
  if type(detail) == "string" and detail ~= "" then bits[#bits + 1] = detail end
  return table.concat(bits, " · ")
end

local function chapterAt(model, t)
  local best
  for _, c in ipairs(model.chapters or {}) do
    if finite(c.t0) and c.t0 <= t then best = c else break end
  end
  return best
end

local function longestDay(index)
  local D = Journal.Days
  if type(index) ~= "table" or not (D and D.list) then return nil end
  local ok, list = pcall(D.list, index)
  if not ok or type(list) ~= "table" then return nil end
  local best
  for _, d in ipairs(list) do
    if type(d) == "table" and finite(d.seconds) and finite(d.t0) and (not best or d.seconds > best.seconds) then best = d end
  end
  if not best then return nil end
  local t = best.t0
  if D.facts then
    local okF, f = pcall(D.facts, index, best.key)
    if okF and type(f) == "table" and finite(f.firstT) then t = f.firstT end
  end
  return { t = t, seconds = best.seconds }
end

-- fmt = { when(t), played(sec), mapName(id) } supplies the display texts; index may be nil (then no "longest day").
-- -> { { key, kind, t, head, sub, tip }, ... } sorted by time
function Stations.build(model, index, fmt)
  local out = {}
  if type(model) ~= "table" or model.empty then return out end
  fmt = type(fmt) == "table" and fmt or {}
  local function when(t)
    if type(fmt.when) ~= "function" then return nil end
    local ok, s = pcall(fmt.when, t)
    return ok and type(s) == "string" and s or nil
  end
  local function played(sec)
    if type(fmt.played) ~= "function" or not finite(sec) then return nil end
    local ok, s = pcall(fmt.played, sec)
    return ok and type(s) == "string" and s or nil
  end
  local function zoneAt(t)
    local c = chapterAt(model, t)
    return c and type(c.zoneName) == "string" and c.zoneName or nil
  end
  local function add(key, kind, t, head, detail, tip)
    if not finite(t) or #out >= Stations.MAX then return end
    local w = when(t)
    local lines = { head }
    if w then lines[#lines + 1] = w .. (Stations.dateText(t) and (" · " .. Stations.dateText(t)) or "") end
    for _, l in ipairs(tip or {}) do if type(l) == "string" and l ~= "" then lines[#lines + 1] = l end end
    lines[#lines + 1] = Stations.TEXT.tipJump
    out[#out + 1] = { key = key, kind = kind, t = t, head = head, sub = Stations.subText(w, t, detail), tip = lines }
  end

  local seenLv = {}
  for _, l in ipairs(model.timeline and model.timeline.levels or {}) do
    local lv = tonumber(l.level)
    if lv and lv == floor(lv) and lv >= Stations.LEVEL_STEP and lv % Stations.LEVEL_STEP == 0 and not seenLv[lv] and finite(l.t) then
      seenLv[lv] = true
      local pt = finite(l.p) and played(l.p) or nil
      add("lv" .. lv, "level", l.t, string.format(Stations.TEXT.level, lv), zoneAt(l.t), { pt and Stations.TEXT("afterPlayed", pt) or nil })
    end
  end

  local seenCont, first = {}, true
  local stay = {}
  for _, c in ipairs(model.chapters or {}) do
    local cont = tonumber(c.continentID)
    if cont then
      if first then
        seenCont[cont], first = true, false
      elseif not seenCont[cont] then
        seenCont[cont] = true
        local name = type(fmt.mapName) == "function" and fmt.mapName(cont) or nil
        local head = type(name) == "string" and name ~= "" and (Stations.TEXT.continent .. name) or Stations.TEXT.newContinent
        add("co" .. tostring(floor(cont)), "continent", c.t0, head, c.zoneName, nil)
      end
    end
    local z = tonumber(c.zoneID)
    local sec = c.stats and tonumber(c.stats.played)
    if z and finite(sec) and sec > 0 and finite(c.t0) then
      local s = stay[z]
      if not s then
        s = { sec = 0, best = 0, name = c.zoneName }
        stay[z] = s
      end
      s.sec = s.sec + sec
      if sec > s.best then s.best, s.t = sec, c.t0 end
    end
  end

  for _, g in ipairs(model.gaps or {}) do
    if g.kind == "instance" and finite(g.t0) then
      local title = g.tip and type(g.tip.title) == "string" and g.tip.title or nil
      local name = title and title:match("^[^:]+: (.+)$") or nil
      add("in", "instance", g.t0, Stations.TEXT.instance, name or zoneAt(g.t0), { g.tip and g.tip.detail or nil })
      break
    end
  end

  local rare
  for _, m in ipairs(model.markers or {}) do
    if m.kind == "rare" and finite(m.t) and (not rare or m.t < rare.t) then rare = m end
  end
  if rare then
    local title = rare.tip and type(rare.tip.title) == "string" and rare.tip.title or nil
    local name = title and title:match("^[^:]+: (.+)$") or title
    add("ra", "rare", rare.t, Stations.TEXT.rare, name or zoneAt(rare.t), { rare.tip and rare.tip.place or nil })
  end

  local ld = longestDay(index)
  if ld then
    local pt = played(ld.seconds)
    add("dy", "day", ld.t, Stations.TEXT.day, pt, { pt and Stations.TEXT("playedInDay", pt) or nil })
  end

  local fav
  for _, s in pairs(stay) do
    if not fav or s.sec > fav.sec or (s.sec == fav.sec and (s.t or huge) < (fav.t or huge)) then fav = s end
  end
  if fav and fav.t then
    local pt = played(fav.sec)
    local name = type(fav.name) == "string" and fav.name or nil
    add("fz", "zone", fav.t, Stations.TEXT.zone, name, { pt and Stations.TEXT("spentThere", pt) or nil })
  end

  table.sort(out, function(a, b)
    if a.t ~= b.t then return a.t < b.t end
    return a.key < b.key
  end)
  return out
end

function Stations.pageCount(n, per)
  per = per or (Stations.COLS * Stations.ROWS)
  return max(1, floor(((tonumber(n) or 0) + per - 1) / per))
end

function Stations.pageOf(list, key, per)
  per = per or (Stations.COLS * Stations.ROWS)
  for i, s in ipairs(list or {}) do
    if s.key == key then return floor((i - 1) / per) + 1 end
  end
  return 1
end

Stations.display = display

local function W() return Journal.Widgets end

local function paintRow(b)
  local red = b.hover or b.selected
  b.head:SetTextColor(W().color(red and "red" or "ink"))
  b.sub:SetTextColor(W().color(b.selected and "red" or "sepia"))
  b.dot:SetSize(b.selected and Stations.DOT + 4 or Stations.DOT, b.selected and Stations.DOT + 4 or Stations.DOT)
end

local function newRow(ui)
  local D, Theme = W().Diary, Journal.Theme
  local b = CreateFrame("Button", nil, ui.frame)
  b:SetSize(ui.colW, Stations.ROW_H)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp") end
  local dot = D.mark(b, "badgeRed", Stations.DOT, nil, "ARTWORK")
  dot:ClearAllPoints()
  dot:SetPoint("CENTER", b, "TOPLEFT", 5, -11)
  local head = D.font(b, "hand", Stations.NAME_SIZE, "ink")
  head:SetPoint("TOPLEFT", b, "TOPLEFT", 16, 0)
  head:SetJustifyH("LEFT")
  head:SetWordWrap(false)
  head:SetWidth(ui.colW - 18)
  local sub = D.font(b, "label", Stations.SUB_SIZE, "sepia")
  sub:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 1)
  sub:SetJustifyH("LEFT")
  sub:SetWordWrap(false)
  sub:SetWidth(ui.colW - 18)
  if Theme and Theme.C and dot.diaryOk == false then dot:SetColorTexture(Theme.C.red[1], Theme.C.red[2], Theme.C.red[3], 0.9) end
  b.dot, b.head, b.sub = dot, head, sub
  b:SetScript("OnEnter", function(self)
    self.hover = true
    paintRow(self)
    if self.station then W().tip(self, self.station.tip) end
  end)
  b:SetScript("OnLeave", function(self)
    self.hover = false
    paintRow(self)
    W().hideTip(self)
  end)
  b:SetScript("OnHide", function(self)
    self.hover = false
    W().hideTip(self)
  end)
  b:SetScript("OnClick", function(self)
    if self.station and ui.cb and ui.cb.onPick then ui.cb.onPick(self.station) end
  end)
  return b
end

function Stations.create(parent, x, y, w, h, cb)
  local D, Theme = W().Diary, Journal.Theme
  local ui = { cb = cb or {}, rows = {}, page = 1, list = {}, w = w, h = h }
  local f = CreateFrame("Frame", nil, parent)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  f:SetSize(w, h)
  ui.frame = f
  ui.colGap = 14
  ui.colW = floor((w - ui.colGap * (Stations.COLS - 1)) / Stations.COLS)
  local head = D.font(f, "hand", Stations.HEAD_SIZE, "red")
  head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  head:SetJustifyH("LEFT")
  head:SetWordWrap(false)
  head:SetText(Stations.TEXT.title)
  ui.head = head
  local rule = D.NewInkStroke(f, nil, "red", 0.35)
  rule:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(Stations.HEAD_H - 4))
  rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(Stations.HEAD_H - 4))
  ui.rule = rule
  ui.lines = {}
  for c = 1, Stations.COLS do
    local ln = f:CreateTexture(nil, "BACKGROUND")
    local C = Theme and Theme.C and Theme.C.sepia or { 0.42, 0.31, 0.2 }
    ln:SetColorTexture(C[1], C[2], C[3], 0.35)
    ln:SetWidth(1)
    ln:Hide()
    ui.lines[c] = ln
  end
  local empty = D.font(f, "label", 12, "sepia")
  empty:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(Stations.HEAD_H + 6))
  empty:SetWidth(w)
  empty:SetJustifyH("LEFT")
  empty:SetText(Stations.TEXT.empty)
  empty:Hide()
  ui.empty = empty
  local nav = D.NewNavPair(f, { size = 18, tipPrev = { Stations.TEXT.tipPrev }, tipNext = { Stations.TEXT.tipNext },
    onPrev = function() Stations.turn(ui, -1) end, onNext = function() Stations.turn(ui, 1) end })
  nav.frame:Hide()
  ui.nav = nav
  local range = f:CreateFontString(nil, "OVERLAY")
  if Theme and Theme.font then Theme.font(range, "label", 12, Theme.C.sepia) end
  range:SetJustifyH("RIGHT")
  range:SetWordWrap(false)
  range:Hide()
  ui.range = range
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta)
    if type(delta) ~= "number" or delta ~= delta then return end
    Stations.turn(ui, delta > 0 and -1 or 1)
  end)
  return ui
end

function Stations.turn(ui, delta)
  ui.page = (ui.page or 1) + (tonumber(delta) or 0)
  Stations.layout(ui)
end

function Stations.set(ui, list, sel)
  local changed = ui.list ~= list
  ui.list = type(list) == "table" and list or {}
  if changed or ui.sel ~= sel then
    ui.page = sel and Stations.pageOf(ui.list, sel, Stations.COLS * (ui.nRows or Stations.ROWS)) or (changed and 1 or ui.page)
  end
  ui.sel = sel
  Stations.layout(ui)
end

function Stations.layout(ui)
  local list = ui.list or {}
  local nRows = ui.nRows or Stations.ROWS
  local per = Stations.COLS * nRows
  local pages = Stations.pageCount(#list, per)
  ui.page = max(1, min(ui.page or 1, pages))
  ui.pages = pages
  local prevOn, nextOn = ui.page > 1, ui.page < pages
  ui.nav:SetEnabled(prevOn, nextOn)
  ui.nav.frame:SetShown(prevOn or nextOn)
  local txt = pages > 1 and Stations.TEXT("pageOf", tostring(ui.page), tostring(pages)) or ""
  ui.range:SetText(txt)
  ui.range:SetShown(txt ~= "")
  ui.empty:SetShown(#list == 0)
  local first = (ui.page - 1) * per + 1
  local used, colsUsed = 0, {}
  for i = first, min(#list, first + per - 1) do
    used = used + 1
    local slot = i - first
    local col, row = floor(slot / nRows) + 1, slot % nRows
    local b = ui.rows[used]
    if not b then
      b = newRow(ui)
      ui.rows[used] = b
    end
    local s = list[i]
    b.station = s
    W().setText(b.head, s.head)
    W().setText(b.sub, s.sub)
    W().fitLine(b.head, ui.colW - 18)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", (col - 1) * (ui.colW + ui.colGap), -(Stations.HEAD_H + 4 + row * Stations.ROW_H))
    b.selected = ui.sel ~= nil and s.key == ui.sel
    paintRow(b)
    b:Show()
    colsUsed[col] = row + 1
  end
  for k = used + 1, #ui.rows do
    ui.rows[k].station = nil
    ui.rows[k]:Hide()
  end
  for c, ln in ipairs(ui.lines) do
    local n = colsUsed[c]
    if n and n > 1 then
      local x = (c - 1) * (ui.colW + ui.colGap) + 5
      local y0 = Stations.HEAD_H + 4 + 11
      ln:ClearAllPoints()
      ln:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", x, -y0)
      ln:SetHeight((n - 1) * Stations.ROW_H)
      ln:Show()
    else
      ln:Hide()
    end
  end
  ui.shown = used
  return used
end

function Stations.place(ui, parent, x, y, rows)
  if not (ui and ui.frame) then return end
  rows = max(1, floor(tonumber(rows) or Stations.ROWS))
  ui.frame:ClearAllPoints()
  ui.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  ui.frame:SetHeight(Stations.HEAD_H + 4 + rows * Stations.ROW_H)
  if ui.nRows ~= rows then
    ui.nRows = rows
    ui.page = ui.sel and Stations.pageOf(ui.list, ui.sel, Stations.COLS * rows) or 1
    Stations.layout(ui)
  end
end

function Stations.setShown(ui, on)
  if ui and ui.frame then ui.frame:SetShown(on and true or false) end
end
