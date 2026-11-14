-- "Flight and hearthstone book" (data package P3): compact block on the left page of "Journey > Whole journey", directly under
-- the total values and above the stations. Shows number of flights with fares, hearthstone trips, favourite route, longest
-- flight and favourite bind place. Data: Journal.Flugbuch.build (model/Flugbuch.lua), delivered as model.total.flightBook.
-- Nothing to show (no flight, no hearthstone trip) -> the block stays away and takes no space.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local FlightBook = {}
Journal.FlightBook = FlightBook

local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
local type, ipairs = type, ipairs

FlightBook.COLS = 2
FlightBook.HEAD_H = 22
FlightBook.HEAD_SIZE = 18
FlightBook.ROW_H = 16
FlightBook.LABEL_SIZE = 11
FlightBook.VALUE_SIZE = 12
FlightBook.GAP_AFTER = 4        -- space below the block (px)
FlightBook.MAX_CELLS = 5
FlightBook.TEXT = ns.Locale.ns("FlightBook", {
  title = "Flug- und Ruhesteinbuch",
  flights = "Flüge",
  hearths = "Ruhestein",
  hearthsValue_one = "%s Heimweg",
  hearthsValue_other = "%s Heimwege",
  route = "Lieblingsroute",
  routeValue = "%s – %s (%s×)",
  longest = "Längster Flug",
  bind = "Lieblingsbindeort",
  bindValue = "%s (%s×)",
  tipFlights_one = "%s Flug",
  tipFlights_other = "%s Flüge",
  tipCost = "Flugkosten zusammen: %s",
  tipHearths_one = "%s Heimweg mit dem Ruhestein",
  tipHearths_other = "%s Heimwege mit dem Ruhestein",
  tipRoute = "%s – %s, %s-mal geflogen",
  tipLongest = "Dauer: %s",
  tipLongestRoute = "%s – %s",
  tipBind = "%s, %s-mal als Bindeort beim Heimweg",
})

local function W() return Journal.Widgets end

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function int(n)
  local F, Tx = Journal.Fmt, Journal.Texts
  if F and F.int then return F.int(n) end
  if Tx and Tx.int then return Tx.int(n) end
  return tostring(floor(tonumber(n) or 0))
end

-- copper -> "2g 40s" (gold and silver; copper only below one silver); nil without a number
function FlightBook.moneyText(copper)
  local Tx = Journal.Texts
  if not finite(copper) or copper < 0 or not (Tx and Tx.moneyParts) then return nil end
  local parts = Tx.moneyParts(copper)
  if type(parts) ~= "table" then return nil end
  local out = {}
  for _, p in ipairs(parts) do
    local unit = p.unit
    if unit == "g" or (unit == "s" and #out < 2) or (unit == "k" and #out == 0) then
      out[#out + 1] = tostring(p.n) .. unit
    end
  end
  if #out == 0 then return nil end
  return table.concat(out, " ")
end

local function duration(sec)
  local F = Journal.Fmt
  return F and F.duration and F.duration(sec, { seconds = true }) or nil
end

-- data (Flugbuch.build) -> list of cells { key, label, value, tip = { lines }, span (1|2) } in display order; nil/empty data -> {}
function FlightBook.cells(data)
  local T = FlightBook.TEXT
  local out = {}
  if type(data) ~= "table" then return out end
  local flights = tonumber(data.flights) or 0
  local hearths = tonumber(data.hearths) or 0
  if flights > 0 then
    local money = FlightBook.moneyText(data.cost)
    local tip = { T(ns.Locale.plural(flights, "tipFlights_one", "tipFlights_other"), int(flights)) }
    if money then tip[#tip + 1] = T("tipCost", money) end
    out[#out + 1] = { key = "flights", label = T.flights, value = int(flights) .. (money and (" · " .. money) or ""), tip = tip, span = 1 }
  end
  if hearths > 0 then
    local value = T(ns.Locale.plural(hearths, "hearthsValue_one", "hearthsValue_other"), int(hearths))
    out[#out + 1] = { key = "hearths", label = T.hearths, value = value,
      tip = { T(ns.Locale.plural(hearths, "tipHearths_one", "tipHearths_other"), int(hearths)) }, span = 1 }
  end
  local r = data.route
  if type(r) == "table" and r.from and r.to and tonumber(r.count) then
    out[#out + 1] = { key = "route", label = T.route, value = T("routeValue", r.from, r.to, int(r.count)),
      tip = { T("tipRoute", r.fromFull or r.from, r.toFull or r.to, int(r.count)) }, span = 2 }
  end
  local l = data.longest
  local dur = type(l) == "table" and duration(l.sec) or nil
  if dur then
    local tip = { T("tipLongest", dur) }
    if l.from and l.to then tip[#tip + 1] = T("tipLongestRoute", l.fromFull or l.from, l.toFull or l.to) end
    out[#out + 1] = { key = "longest", label = T.longest, value = dur, tip = tip, span = 1 }
  end
  local b = data.bind
  if type(b) == "table" and b.name and tonumber(b.count) then
    out[#out + 1] = { key = "bind", label = T.bind, value = T("bindValue", b.name, int(b.count)),
      tip = { T("tipBind", b.name, int(b.count)) }, span = 1 }
  end
  return out
end

-- sets cell.row / cell.col (1-based); a cell of span 2 takes a whole row. -> number of rows
function FlightBook.pack(cells)
  local row, col = 1, 1
  for _, c in ipairs(cells) do
    if c.span >= FlightBook.COLS then
      if col > 1 then row, col = row + 1, 1 end
      c.row, c.col = row, 1
      row, col = row + 1, 1
    else
      c.row, c.col = row, col
      col = col + 1
      if col > FlightBook.COLS then row, col = row + 1, 1 end
    end
  end
  return col > 1 and row or row - 1
end

-- height of the block for the given data (0 = not shown)
function FlightBook.heightFor(data)
  local cells = FlightBook.cells(data)
  if #cells == 0 then return 0 end
  return FlightBook.HEAD_H + 3 + FlightBook.pack(cells) * FlightBook.ROW_H + FlightBook.GAP_AFTER
end

local function newCell(ui)
  local D = W().Diary
  local f = CreateFrame("Frame", nil, ui.frame)
  if f.EnableMouse then f:EnableMouse(true) end
  local label = D.font(f, "label", FlightBook.LABEL_SIZE, "sepia")
  label:SetPoint("LEFT", f, "LEFT", 0, 0)
  label:SetJustifyH("LEFT")
  label:SetWordWrap(false)
  local value = D.font(f, "label", FlightBook.VALUE_SIZE, "ink")
  value:SetPoint("LEFT", label, "RIGHT", 5, 0)
  value:SetJustifyH("LEFT")
  value:SetWordWrap(false)
  local cell = { frame = f, label = label, value = value }
  f:SetScript("OnEnter", function(self)
    if cell.tip then W().tip(self, cell.tip) end
  end)
  f:SetScript("OnLeave", function(self) W().hideTip(self) end)
  f:SetScript("OnHide", function(self) W().hideTip(self) end)
  f:Hide()
  return cell
end

function FlightBook.create(parent, x, y, w)
  local D, Theme = W().Diary, Journal.Theme
  local ui = { w = w, cells = {}, height = 0 }
  local f = CreateFrame("Frame", nil, parent)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  f:SetSize(w, FlightBook.HEAD_H)
  ui.frame = f
  ui.colGap = 14
  ui.colW = floor((w - ui.colGap * (FlightBook.COLS - 1)) / FlightBook.COLS)
  local head = D.font(f, "hand", FlightBook.HEAD_SIZE, "red")
  head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  head:SetJustifyH("LEFT")
  head:SetWordWrap(false)
  head:SetWidth(w)
  ui.head = head
  local rule = D.NewInkStroke(f, nil, "red", 0.35)
  rule:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(FlightBook.HEAD_H - 4))
  rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(FlightBook.HEAD_H - 4))
  ui.rule = rule
  for i = 1, FlightBook.MAX_CELLS do ui.cells[i] = newCell(ui) end
  f:Hide()
  return ui
end

-- fills the block; -> height (0 = nothing to show, the block is hidden)
function FlightBook.set(ui, data)
  if not (ui and ui.frame) then return 0 end
  local cells = FlightBook.cells(data)
  if #cells == 0 then
    ui.height = 0
    ui.frame:Hide()
    for _, c in ipairs(ui.cells) do c.frame:Hide() end
    return 0
  end
  local rows = FlightBook.pack(cells)
  ui.head:SetText(FlightBook.TEXT.title)
  W().fitLine(ui.head, ui.w, 13)
  for i, c in ipairs(ui.cells) do
    local d = cells[i]
    if not d then
      c.tip = nil
      c.frame:Hide()
    else
      local cw = d.span >= FlightBook.COLS and ui.w or ui.colW
      c.tip = d.tip
      c.frame:ClearAllPoints()
      c.frame:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", (d.col - 1) * (ui.colW + ui.colGap),
        -(FlightBook.HEAD_H + 3 + (d.row - 1) * FlightBook.ROW_H))
      c.frame:SetSize(cw, FlightBook.ROW_H)
      W().setText(c.label, d.label)
      -- the label keeps its own width (at most 55 % of the cell), the value gets the rest and shrinks before it is cut
      local lw = tonumber(c.label:GetStringWidth()) or 0
      lw = min(max(lw, 10) + 2, floor(cw * 0.55))
      W().fitLine(c.label, lw, 9)
      W().setText(c.value, d.value)
      W().fitLine(c.value, max(20, cw - lw - 5), 9)
      c.frame:Show()
    end
  end
  ui.height = FlightBook.HEAD_H + 3 + rows * FlightBook.ROW_H + FlightBook.GAP_AFTER
  ui.frame:SetHeight(ui.height)
  ui.frame:Show()
  return ui.height
end

function FlightBook.place(ui, parent, x, y)
  if not (ui and ui.frame) then return end
  ui.frame:ClearAllPoints()
  ui.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
end

function FlightBook.setShown(ui, on)
  if ui and ui.frame then ui.frame:SetShown(on and ui.height > 0 or false) end
end
