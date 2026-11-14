-- Journey sub-page "Heatmap" (I15, change "heatmap" E2): the third sub-bookmark of Reise (Inhalt · Gesamtreise · Heatmap).
-- Left page: the zones with a trail (name, time, deaths; sorted by time, click chooses, default = most time), in the look of the
-- table of contents (journal/Contents.lua). Right page: the zone map like the journey map (same tiles, tint and "Karte aufdecken",
-- wheel zoom, drag, double click resets) with the embers as an own texture pool (not the route line pool): stay = soft amber ->
-- orange -> bright ember yellow, slightly additive; deaths = dark red -> glowing red. Stay scale: a high percentile as
-- reference, logarithmic in the middle (HV.stayHeat), so towns do not drown quest areas; deaths: square root of the hottest.
-- Switch "Aufenthalt | Todesorte" (remembered: Pages setting heatKind),
-- tooltip per cell, friendly empty states, small legend. No route, no kill marks on this view.
-- Data only via View (View.heatZones / View.heatGridStep -> journal/model/Heatmap.lua); a big zone is computed in slices over
-- several frames (gridStep, C_Timer.After(0)). No OnUpdate except while the pointer is on the map (hover/drag), no protected calls.
-- Frame.lua owns the sub-bookmark and calls HV.build / HV.show / HV.hide / HV.reset.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local HV = {}
Journal.HeatmapView = HV

local floor, min, max, sqrt = math.floor, math.min, math.max, math.sqrt

HV.TEXT = ns.Locale.ns("HeatmapView", {
  head = "Heatmap",
  headRight = "Glut der Reise",
  title = "Heatmap",
  zones_one = "%s Zone",
  zones_other = "%s Zonen",
  summary = "%s · Zeit ohne AFK, Stillstand gedeckelt",
  modeStay = "Aufenthalt",
  modeStayTip = "Wo Ihr wie lange wart: je heller die Glut, desto länger.",
  modeDeath = "Todesorte",
  modeDeathTip = "Wo Ihr in dieser Zone gestorben seid.",
  mapHint = "Mausrad: zoomen · Ziehen: verschieben · Doppelklick: zurück",
  statStay = "%s in dieser Zone",
  statCont = "%s auf diesem Kontinent",
  deaths_one = "%s Tod",
  deaths_other = "%s Tode",
  noDeathsShort = "keine Tode",
  stayTip = "ca. %s hier",
  stayBrief = "nur kurz hier",
  stayShare = "%s %% Eurer Zeit in dieser Zone",
  stayShareSmall = "unter 1 Prozent Eurer Zeit in dieser Zone",
  deathLine = "Stufe %s · %s",
  deathLineWhen = "Stufe %s · %s · %s",
  deathMore = "… und %s weitere",
  cause_enemy = "Gegner",
  cause_fall = "Sturz",
  cause_drown = "Ertrunken",
  cause_fatigue = "Erschöpfung",
  cause_lava = "Lava",
  cause_fire = "Feuer",
  cause_slime = "Schleim",
  cause_environment = "Umgebung",
  cause_unknown = "Ursache unbekannt",
  legendStayLow = "kurz",
  legendStayHigh = "lange",
  legendDeathLow = "ein Tod",
  legendDeathHigh = "viele",
  loading = "Die Glut wird angefacht …",
  noTrail = "Noch keine Spur. Sobald Ihr unterwegs seid, schreibt die Chronik Eure Wege mit – dann glüht hier, wo Ihr verweilt habt.",
  noTrailList = "Noch keine Zonen mit Spur.",
  noDeaths = "In dieser Zone seid Ihr nie gestorben. Möge es so bleiben!",
  noStay = "Hier wart Ihr nur auf der Durchreise.",
  noTrailZone = "Hier gibt es keine Spur – nur Todesorte.",
  otherLands = "Weitere Gebiete",
  failed = "Die Heatmap konnte nicht aufbereitet werden. Details: /chronik diag",
  tipZone = "Klick: Glut dieser Zone zeigen",
  tipContinent = "Klick: Glut des ganzen Kontinents zeigen",
  tipScroll = "Mausrad: weitere Zonen",
  tipTime = "Zeit: %s",
  tipDeaths = "Tode: %s",
})

local T = HV.TEXT

-- layout in spread pixels (1076 x 666; right page = + 538). Left like the table of contents, right like the journey map.
HV.LEFT_Y = 66             -- title (Contents: Frame.CARD_Y)
HV.HEAD_H = 58             -- title + summary + red rule, the rows start below
HV.LIST_BOTTOM = 500       -- the rows end here: below, the ink blot at the bottom left reaches into the text block (x 68..132 from y 503)
HV.ROW_H = 22
HV.NAME_X = 30             -- zone rows: indented below the continent heading (room for the red selection mark at 0)
HV.HEAD_X = 14             -- continent heading text (room for the red selection mark)
HV.ROWS_MAX = 30           -- row pool
HV.BAR = { gap = 6, track = 3, thumb = 5, minH = 12 } -- scroll bar right of the list (look of widgets/List.lua)
HV.DOTS_MAX = 120 -- dot leader: at most this many dots, the gap decides how many fit
HV.CTRL_Y = 118            -- switch (Frame.CTRL_Y)
HV.MAP_Y, HV.MAP_H = 150, 360
HV.LEGEND_GAP = 10         -- legend below the map
HV.LEGEND_W, HV.LEGEND_H, HV.LEGEND_STEPS = 120, 8, 12
HV.HEAT_MAX = 1500         -- ember textures (pool limit; the hottest cells come first)
HV.BLOB = { stay = 3.0, death = 3.4 }     -- blob diameter in cells (the embers overlap and flow into each other)
HV.BLOB_MIN = { stay = 7, death = 14 }    -- minimum diameter in px (single deaths stay visible)
HV.BLOB_MAX = 140
HV.ZOOM_MAX, HV.ZOOM_STEP = 8, 1.25
HV.DOUBLE_CLICK, HV.DRAG_MIN = 0.35, 4
HV.BUDGET_MS = 8           -- computing time per frame of a big zone (gridStep)
HV.TIP_DEATHS = 3          -- causes shown in a death tooltip
HV.KINDS = { stay = true, death = true }

-- colour ramps (r, g, b): amber -> orange -> bright ember yellow; dark red -> glowing red
HV.RAMP = {
  -- clearly separated steps: dim amber, orange, bright ember yellow (the former amber and orange were too alike)
  stay = { { 0.70, 0.38, 0.10 }, { 0.96, 0.52, 0.09 }, { 1.00, 0.90, 0.46 } },
  death = { { 0.34, 0.04, 0.03 }, { 0.62, 0.07, 0.04 }, { 0.98, 0.20, 0.08 } },
}
HV.ADD_FROM = 0.45         -- from this heat on the ember is drawn additively (glows on the parchment)
-- stay: values smoothed 3 x 3 (weights 1-2-1) before drawing, so the 64 cells do not show as a raster; cells below MIN_HEAT
-- (after smoothing, on the display scale HV.stayHeat) are left out, so the pool limit suffices
HV.SMOOTH = { 1, 2, 1 }
HV.MIN_HEAT = 0.12
-- display scale of the stay embers (only the drawing; tooltip and core keep the real seconds), from the smoothed values of the
-- cells with own time: lo = percentile LO (the paths), hi = percentile HI (the strongest quest areas), max = hottest (town).
--   - flat zone (hi / lo < FLAT_RATIO, e.g. only passed through): as before, square root relative to the hottest cell
--   - quest zone: below lo FLOOR * sqrt(v / lo) (paths glow faintly); lo..hi logarithmic (^GAMMA) from FLOOR to KNEE (quest areas of
--     different length get clearly different steps amber -> orange -> yellow); above hi only the last bit to full ember by log
--     ratio up to the hottest cell (towns stay a little brighter than the strongest quest areas, not dominant)
HV.STAY_SCALE = { lo = 0.25, hi = 0.96, floor = 0.22, knee = 0.88, gamma = 1.3, flatRatio = 4 }

local function W() return Journal.Widgets end
local function D() return Journal.Widgets and Journal.Widgets.Diary end
local function Theme() return Journal.Theme end
local function View() return Journal.View end
local function Fmt() return Journal.Fmt end

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge or isSecret(v) then return nil end
  return v
end

local function int(n)
  local F = Fmt()
  return (F and F.int(n)) or tostring(floor(tonumber(n) or 0))
end

local function plural(n, one, other)
  local L = ns.Locale
  return T(L.plural(n, one, other), int(n))
end

local function duration(sec)
  local F = Fmt()
  return (F and F.duration(sec)) or T.stayBrief
end

local function report(err)
  HV.errors = (HV.errors or 0) + 1
  if ns.Core and ns.Core.coreError then ns.Core.coreError("Heatmap-Ansicht: " .. tostring(err)) end
end

local function guarded(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then report(err) end
  end
end

-- heat 0..1 of a cell value: square root relative to the hottest cell (short stays stay visible)
function HV.heat(v, maxV)
  v, maxV = num(v), num(maxV)
  if not v or not maxV or v <= 0 or maxV <= 0 then return 0 end
  return min(1, sqrt(v / maxV))
end

-- scale of a zone from the values of the cells with own time (list, sorted in place) and the hottest value -> { lo, hi, max, flat }
function HV.stayScale(own, maxV)
  local S = HV.STAY_SCALE
  maxV = num(maxV) or 0
  local lo, hi = HV.percentile(own, S.lo), HV.percentile(own, S.hi)
  if not lo or not hi or lo <= 0 or maxV <= 0 then return { max = maxV, flat = true } end
  return { lo = lo, hi = hi, max = maxV, flat = hi / lo < S.flatRatio }
end

-- stay heat 0..1 of a (smoothed) value v on the scale sc (HV.stayScale)
function HV.stayHeat(v, sc)
  v = num(v)
  if not v or v <= 0 or type(sc) ~= "table" then return 0 end
  if sc.flat then return HV.heat(v, sc.max) end
  local S = HV.STAY_SCALE
  local lo, hi, maxV = sc.lo, sc.hi, sc.max
  if v <= lo then return S.floor * sqrt(v / lo) end
  -- nothing far above hi (no town): the quest areas themselves run up to full ember
  local top = maxV <= hi * 1.001 and 1 or S.knee
  if v <= hi then return S.floor + (top - S.floor) * (math.log(v / lo) / math.log(hi / lo)) ^ S.gamma end
  if top == 1 then return 1 end
  return min(1, S.knee + (1 - S.knee) * math.log(v / hi) / math.log(maxV / hi))
end

-- value at percentile pct (0..1, nearest rank) of a list of numbers (sorted in place)
function HV.percentile(list, pct)
  local n = #list
  if n == 0 then return nil end
  table.sort(list)
  local k = math.ceil(pct * n)
  if k < 1 then k = 1 elseif k > n then k = n end
  return list[k]
end

-- colour of an ember: kind "stay" | "death", heat 0..1 -> r, g, b, a, blend ("ADD" for the hottest, else "BLEND")
function HV.color(kind, h)
  local ramp = HV.RAMP[kind] or HV.RAMP.stay
  h = max(0, min(1, num(h) or 0))
  local a, b, f
  if h <= 0.5 then
    a, b, f = ramp[1], ramp[2], h / 0.5
  else
    a, b, f = ramp[2], ramp[3], (h - 0.5) / 0.5
  end
  local r = a[1] + (b[1] - a[1]) * f
  local g = a[2] + (b[2] - a[2]) * f
  local bl = a[3] + (b[3] - a[3]) * f
  local alpha
  if kind == "death" then
    alpha = 0.55 + 0.40 * h
  else
    alpha = 0.14 + 0.46 * h
  end
  -- deaths always BLEND: added onto the light parchment/map, dark to glowing red brightens it instead of darkening it and the
  -- mark is all but invisible (playtest 13.11.: "Todesorte zeigt nichts"); only the stay embers glow additively
  local blend = (kind ~= "death" and h >= HV.ADD_FROM) and "ADD" or "BLEND"
  return r, g, bl, alpha, blend
end

-- cells to draw, hottest first: { { i, v (raw value), h (heat 0..1), col, row }, ... }. Deaths: every cell with a death, heat
-- from the raw count. Stay: values smoothed 3 x 3 (HV.SMOOTH, edge cells averaged over the neighbours present), heat from the
-- smoothed value on the scale HV.stayHeat (percentiles of the zone), cells below HV.MIN_HEAT dropped (also cells without own time next to a hot one get a
-- soft ember: the embers flow together instead of showing the 64 x 64 raster)
function HV.hotList(grid)
  local out = {}
  if type(grid) ~= "table" or type(grid.cells) ~= "table" then return out end
  local n = num(grid.size) or 64
  local cells = grid.cells
  if grid.kind == "death" then
    for i, v in ipairs(cells) do
      if type(v) == "number" and v > 0 then
        out[#out + 1] = { i = i, v = v, s = v, h = HV.heat(v, grid.max), col = (i - 1) % n + 1, row = floor((i - 1) / n) + 1 }
      end
    end
  else
    local K = HV.SMOOTH
    local sm, smax = {}, 0
    for i, v in ipairs(cells) do
      if type(v) == "number" and v > 0 then
        local col, row = (i - 1) % n + 1, floor((i - 1) / n) + 1
        for dy = -1, 1 do
          local r = row + dy
          if r >= 1 and r <= n then
            for dx = -1, 1 do
              local c = col + dx
              if c >= 1 and c <= n then
                local j = (r - 1) * n + c
                sm[j] = (sm[j] or 0) + v * K[dx + 2] * K[dy + 2]
              end
            end
          end
        end
      end
    end
    -- weight sum per cell (edges have fewer neighbours): 16 inside
    for j, v in pairs(sm) do
      local col, row = (j - 1) % n + 1, floor((j - 1) / n) + 1
      local wx = (col > 1 and 1 or 0) + 2 + (col < n and 1 or 0)
      local wy = (row > 1 and 1 or 0) + 2 + (row < n and 1 or 0)
      v = v / (wx * wy)
      sm[j] = v
      if v > smax then smax = v end
    end
    -- reference: percentile of the smoothed values of the cells with own time
    local own = {}
    for j, v in pairs(sm) do
      local raw = cells[j]
      if type(raw) == "number" and raw > 0 then own[#own + 1] = v end
    end
    local sc = HV.stayScale(own, smax)
    for j, v in pairs(sm) do
      local h = HV.stayHeat(v, sc)
      if h >= HV.MIN_HEAT then
        local raw = cells[j]
        out[#out + 1] = { i = j, v = type(raw) == "number" and raw or 0, s = v, h = h, col = (j - 1) % n + 1, row = floor((j - 1) / n) + 1 }
      end
    end
  end
  table.sort(out, function(p, q)
    if p.s ~= q.s then return p.s > q.s end
    return p.i < q.i
  end)
  return out
end

-- ---- state -------------------------------------------------------------------------------------------------------------------

local function kindSetting()
  local P = Journal.Pages
  local v = P and P.setting and P.setting("heatKind")
  return HV.KINDS[v] and v or "stay"
end

local function saveKind(kind)
  local P = Journal.Pages
  if P and P.setSetting and not (P.guest and P.guest()) then P.setSetting("heatKind", kind) end
end

-- continent entry of the list (heading), nil when id is no continent heading
function HV.contZone(p, id)
  if not id then return nil end
  local list = p.contZones
  if not list then
    list = {}
    for _, e in ipairs(HV.entries(p.zones)) do
      if e.kind == "head" and e.zone then list[e.zone.mapID] = e.zone end
    end
    p.contZones = list
  end
  return list[id]
end

-- ---- left page: zone list ------------------------------------------------------------------------------------------------------

local function paintRow(b)
  local red = b.selected or b.hover
  b.name:SetTextColor(W().color(red and "red" or "ink"))
  if b.kind == "head" then
    b.headText:SetTextColor(W().color(red and "red" or "sepia"))
    b.right:SetTextColor(W().color(red and "red" or "sepia"))
  end
  b.mark:SetShown(b.selected and true or false)
end

local function zoneRight(z)
  local s = duration(z.seconds or 0)
  if (z.deaths or 0) > 0 then s = s .. " · " .. plural(z.deaths, "deaths_one", "deaths_other") end
  return s
end

local function newRow(p)
  local Th = Theme()
  local b = CreateFrame("Button", nil, p.list)
  b:SetHeight(HV.ROW_H)
  b.name = Th.fontString(b, "text", 14, Th.C.ink, "OVERLAY", "LEFT")
  b.name:SetWordWrap(false)
  b.right = Th.fontString(b, "label", 12, Th.C.sepia, "OVERLAY", "RIGHT")
  b.right:SetWordWrap(false)
  b.dots = Th.fontString(b, "label", 12, Th.C.sepia, "OVERLAY", "LEFT")
  b.dots:SetWordWrap(false)
  b.mark = D().mark(b, "next", 12, "red")
  b.mark:SetPoint("LEFT", b, "LEFT", 0, 0)
  -- continent heading (same button, other look): small capitals in sepia with a fine rule to the right
  b.headText = Th.fontString(b, "label", 11, Th.C.sepia, "OVERLAY", "LEFT")
  b.headText:SetWordWrap(false)
  b.headText:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", HV.HEAD_X, 4)
  b.headRule = W().NewRule(b, 0, 0, 10, 0.35)
  b:SetScript("OnClick", guarded(function(self) if self.zoneID then HV.selectZone(p, self.zoneID) end end))
  b:SetScript("OnEnter", function(self)
    self.hover = true
    paintRow(self)
    local z = self.zone
    if z then
      local lines = { z.name or "", T("tipTime", duration(z.seconds or 0)), T("tipDeaths", int(z.deaths or 0)),
        z.continent and T.tipContinent or T.tipZone }
      if p.maxOffset and p.maxOffset > 0 then lines[#lines + 1] = T.tipScroll end
      W().tip(self, lines)
    end
  end)
  b:SetScript("OnLeave", function(self)
    self.hover = false
    paintRow(self)
    W().hideTip(self)
  end)
  return b
end

-- continent of a zone (View.continentOf: parent chain C_Map/Geo, like the other pages) -> id | false
local function continentOf(mapID)
  local V = View()
  local c = V and V.continentOf and V.continentOf(mapID)
  return c or false
end

-- list lines of the zones: per continent a heading, then its zones (each by time, as delivered); continents ordered by their
-- time (then deaths). Zones without a known continent come last under "Weitere Gebiete".
-- -> { { kind = "head", text, contID, zone (continent entry | nil) }, { kind = "zone", zone }, ... }
function HV.entries(zones)
  local groups, byId = {}, {}
  for _, z in ipairs(zones or {}) do
    local c = continentOf(z.mapID)
    local g = byId[c]
    if not g then
      g = { id = c, zones = {}, seconds = 0, deaths = 0 }
      byId[c] = g
      groups[#groups + 1] = g
    end
    -- the continent's own map is no zone row: its trail points belong to the (clickable) continent heading
    if c and z.mapID == c then g.own = z else g.zones[#g.zones + 1] = z end
    g.seconds = g.seconds + (z.seconds or 0)
    g.deaths = g.deaths + (z.deaths or 0)
  end
  table.sort(groups, function(a, b)
    if (a.id == false) ~= (b.id == false) then return b.id == false end
    if a.seconds ~= b.seconds then return a.seconds > b.seconds end
    if a.deaths ~= b.deaths then return a.deaths > b.deaths end
    return (a.id or 0) < (b.id or 0)
  end)
  local out = {}
  local V = View()
  for _, g in ipairs(groups) do
    local name = g.id and V and V.mapName and V.mapName(g.id) or nil
    -- heading of a continent = selectable "zone" of its own (the continent map; total time of the group, deaths summed)
    local cz = g.id and { mapID = g.id, name = name or (g.own and g.own.name) or "", seconds = g.seconds, deaths = g.deaths,
      continent = true, noTrail = (g.own == nil and g.seconds <= 0) or nil } or nil
    out[#out + 1] = { kind = "head", text = name or T.otherLands, contID = g.id or nil, zone = cz }
    for _, z in ipairs(g.zones) do out[#out + 1] = { kind = "zone", zone = z } end
  end
  return out
end

-- number of zone rows (continent headings are no zones)
function HV.zoneCount(p)
  local n = 0
  for _, e in ipairs(HV.entries(p.zones)) do
    if e.kind == "zone" then n = n + 1 end
  end
  return n
end

function HV.rowsRoom(p)
  return max(1, floor((p.listH or 0) / HV.ROW_H))
end

local function showHead(b, e, w)
  for _, r in ipairs({ b.name, b.dots }) do r:Hide() end
  b.right:Hide()
  b.headText:SetText(ns.Journal.Fmt.upper(e.text or ""))
  b.headText:Show()
  local rw = 0
  if e.zone then
    -- clickable continent heading: total time (and deaths) at the right, the rule runs in between
    b.right:ClearAllPoints()
    b.right:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 3)
    b.right:SetText(zoneRight(e.zone))
    b.right:Show()
    rw = (tonumber(b.right:GetStringWidth()) or 0) + 8
  end
  local tw = min(tonumber(b.headText:GetStringWidth()) or 0, w - HV.HEAD_X - 30 - rw)
  b.headRule:ClearAllPoints()
  b.headRule:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", HV.HEAD_X + tw + 8, 9)
  b.headRule:SetWidth(max(10, w - HV.HEAD_X - tw - 8 - rw))
  b.headRule:Show()
  if b.EnableMouse then b:EnableMouse(e.zone ~= nil) end
end

local function showZone(p, b, z)
  b.headText:Hide()
  b.headRule:Hide()
  b.name:Show()
  b.right:Show()
  if b.EnableMouse then b:EnableMouse(true) end
  b.right:ClearAllPoints()
  b.right:SetPoint("RIGHT", b, "RIGHT", 0, 0)
  b.right:SetText(zoneRight(z))
  local rw = tonumber(b.right:GetStringWidth()) or 0
  local avail = max(40, p.listW - HV.NAME_X - rw - 12)
  b.name:ClearAllPoints()
  b.name:SetPoint("LEFT", b, "LEFT", HV.NAME_X, 0)
  b.name:SetText(z.name or "")
  W().fitLine(b.name, avail, 10)
  -- dot leader: between the end of the name and the figures (two anchors), as many dots as fit the gap (measured, not cut)
  local nw = min(tonumber(b.name:GetStringWidth()) or 0, avail)
  if nw > 0 then b.name:SetWidth(nw + 1) end
  local gap = p.listW - HV.NAME_X - nw - rw - 8
  b.dots:ClearAllPoints()
  b.dots:SetPoint("LEFT", b, "LEFT", HV.NAME_X + nw + 4, 0)
  b.dots:SetPoint("RIGHT", b.right, "LEFT", -4, 0)
  b.dots:SetText(". ")
  local dw = tonumber(b.dots:GetStringWidth()) or 0
  local count = (dw > 0 and gap > 8) and min(floor(gap / dw), HV.DOTS_MAX) or 0
  b.dots:SetText(string.rep(". ", count))
  b.dots:SetShown(count > 0)
  paintRow(b)
end

function HV.layoutList(p)
  local entries = HV.entries(p.zones)
  p.entries = entries
  p.contZones = {}
  for _, e in ipairs(entries) do
    if e.kind == "head" and e.zone then p.contZones[e.zone.mapID] = e.zone end
  end
  local room = HV.rowsRoom(p)
  p.maxOffset = max(0, #entries - room)
  p.offset = max(0, min(p.maxOffset, p.offset or 0))
  local used = 0
  for k = p.offset + 1, #entries do
    if used >= room or used >= HV.ROWS_MAX then break end
    used = used + 1
    local e = entries[k]
    local b = p.rows[used]
    if not b then
      b = newRow(p)
      p.rows[used] = b
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", p.list, "TOPLEFT", 0, -(used - 1) * HV.ROW_H)
    b:SetSize(p.listW, HV.ROW_H)
    b.kind = e.kind
    if e.kind == "head" then
      local cz = e.zone
      b.zone, b.zoneID, b.selected, b.hover = cz, cz and cz.mapID or nil, cz ~= nil and cz.mapID == p.zoneID, false
      showHead(b, e, p.listW)
      paintRow(b)
    else
      local z = e.zone
      b.zone, b.zoneID, b.selected = z, z.mapID, z.mapID == p.zoneID
      showZone(p, b, z)
    end
    b:Show()
  end
  for k = used + 1, #p.rows do
    local b = p.rows[k]
    b.zone, b.zoneID, b.selected, b.kind = nil, nil, false, nil
    b:Hide()
  end
  p.shownRows = used
  HV.updateThumb(p)
  return used
end

-- scroll bar of the zone list (only when the list is longer than the page): thumb height = visible share, position = offset
function HV.updateThumb(p)
  if not (p.thumb and p.track) then return end
  local maxOff = p.maxOffset or 0
  if maxOff <= 0 then
    p.track:Hide()
    p.thumb:Hide()
    return
  end
  local h, total, room = p.listH, #(p.entries or {}), HV.rowsRoom(p)
  local th = max(HV.BAR.minH, floor(h * room / max(1, total)))
  p.thumb:SetHeight(th)
  p.thumb:ClearAllPoints()
  p.thumb:SetPoint("TOP", p.track, "TOP", 0, -floor((h - th) * (p.offset or 0) / maxOff))
  p.track:Show()
  p.thumb:Show()
end

function HV.scrollTo(p, offset)
  local o = max(0, min(p.maxOffset or 0, floor((tonumber(offset) or 0) + 0.5)))
  if o == (p.offset or 0) then return false end
  p.offset = o
  HV.layoutList(p)
  return true
end

local function endDrag(p)
  if p.thumb then p.thumb:SetScript("OnUpdate", nil) end
  p.drag = nil
end

local function beginDrag(p)
  if type(GetCursorPosition) ~= "function" then return end
  local _, cy = GetCursorPosition()
  local scale = p.list.GetEffectiveScale and p.list:GetEffectiveScale() or 1
  if not (num(cy) and num(scale) and scale > 0) then return end
  p.drag = { y = cy / scale, offset = p.offset or 0, scale = scale }
  p.thumb:SetScript("OnUpdate", function()
    local d = p.drag
    local _, y = GetCursorPosition()
    if not (d and num(y)) then return end
    local span = p.listH - (p.thumb:GetHeight() or 0)
    if span <= 0 then return end
    local ok, err = pcall(HV.scrollTo, p, d.offset + (d.y - y / d.scale) / span * (p.maxOffset or 0))
    if not ok then
      report(err)
      endDrag(p)
    end
  end)
end

-- ---- right page: map, embers, tooltip --------------------------------------------------------------------------------------------

local function masked(p, t)
  if p.mapMask and t.AddMaskTexture then pcall(t.AddMaskTexture, t, p.mapMask) end
  return t
end

-- zone art like the journey map (View.zoneArt with "Karte aufdecken", View.mapArt as fallback); remembered per zone and setting
function HV.zoneArt(p, mapID)
  local V = View()
  local reveal = V and V.peek and V.peek("revealMap") == true or false
  local c = p.artCache
  if c and c.id == mapID and c.reveal == reveal then return c.art or nil end
  local art
  local function valid(a) return type(a) == "table" and num(a.w) and num(a.h) and a.w > 0 and a.h > 0 end
  if V and V.zoneArt then
    local ok, a = pcall(V.zoneArt, mapID, reveal)
    if ok and valid(a) then art = a end
  end
  if not art and V and V.mapArt then
    local ok, a = pcall(V.mapArt, mapID)
    if ok and valid(a) then art = a end
  end
  p.artCache = { id = mapID, reveal = reveal, art = art or false }
  return art
end

local function drawArt(p, mapID)
  p.tiles:ReleaseAll()
  p.overlays:ReleaseAll()
  local Map, V = Journal.Map, View()
  local art = HV.zoneArt(p, mapID)
  local MW, MH = p.mapW, p.mapH
  if not art or not (Map and Map.tiles) then return 0, 0, MW, MH end
  local mv = p.mv
  local s = min(MW / art.w, MH / art.h)
  local w, h = art.w * s, art.h * s
  local ox, oy = (MW - w) / 2, (MH - h) / 2
  local z, tx0, ty0 = mv.z, mv.tx, mv.ty
  local original = V and V.peek and V.peek("mapColor") == "original"
  local function place(pool, list, top)
    for _, t in ipairs(list) do
      local tex = pool:Acquire()
      if not tex then break end
      if top ~= nil and tex.SetDrawLayer then tex:SetDrawLayer("BACKGROUND", t.top and 3 or 2) end
      tex:SetTexture(t.file)
      tex:SetTexCoord(0, t.u1, 0, t.v1)
      if Map.tintTile then Map.tintTile(tex, original) end
      tex:SetSize((t.x1 - t.x0) * s * z, (t.y1 - t.y0) * s * z)
      tex:SetPoint("TOPLEFT", p.map, "TOPLEFT", ox + t.x0 * s * z + tx0, -(oy + t.y0 * s * z + ty0))
    end
  end
  place(p.tiles, Map.tiles(art))
  place(p.overlays, type(art.overlays) == "table" and art.overlays or {}, true)
  return ox, oy, w, h
end

local function clampView(mv, a)
  mv.tx = max(a.w * (1 - mv.z), min(0, mv.tx))
  mv.ty = max(a.h * (1 - mv.z), min(0, mv.ty))
end

local function blobSize(kind, a, z, n)
  return min(HV.BLOB_MAX, max(HV.BLOB_MIN[kind] or 7, a.w * z / n * (HV.BLOB[kind] or 2.6)))
end

-- draws tiles and embers with zoom/shift p.mv; p.art = rectangle of the art in the box. -> number of embers drawn
function HV.paintMap(p)
  p.heat:ReleaseAll()
  local g = p.grid
  if not (p.zoneID and g) then
    p.tiles:ReleaseAll()
    p.overlays:ReleaseAll()
    p.drawn = 0
    return 0
  end
  local ox, oy, w, h = drawArt(p, p.zoneID)
  local a = { ox = ox, oy = oy, w = w, h = h }
  p.art = a
  local mv, kind = p.mv, g.kind
  local z, n = mv.z, num(g.size) or 64
  local size = blobSize(kind, a, z, n)
  local half = size / 2
  local drawn = 0
  local hot = p.hot or {}
  for k = 1, #hot do
    local c = hot[k]
    local x = ox + mv.tx + (c.col - 0.5) / n * w * z
    local y = oy + mv.ty + (c.row - 0.5) / n * h * z
    if x >= -half and x <= p.mapW + half and y >= -half and y <= p.mapH + half then
      local t = p.heat:Acquire()
      if not t then break end
      local heat = c.h or HV.heat(c.v, g.max)
      local r, gg, b, al, blend = HV.color(kind, heat)
      if t.SetBlendMode then t:SetBlendMode(blend) end
      if t.SetDrawLayer then t:SetDrawLayer("ARTWORK", min(7, floor(heat * 7))) end
      t:SetVertexColor(r, gg, b, al)
      t:SetSize(size, size)
      t:SetPoint("CENTER", p.map, "TOPLEFT", x, -y)
      drawn = drawn + 1
    end
  end
  p.drawn = drawn
  return drawn
end

-- cell under the pointer (cx, cy in the box) -> index, value of the nearest non-empty cell within the ember radius, else nil
function HV.hitCell(p, cx, cy)
  local g, a, mv = p.grid, p.art, p.mv
  if not (g and a and mv) or type(cx) ~= "number" or type(cy) ~= "number" then return nil end
  local n, z = num(g.size) or 64, mv.z
  local cw, ch = a.w * z / n, a.h * z / n
  if cw <= 0 or ch <= 0 then return nil end
  local fx, fy = (cx - a.ox - mv.tx) / cw, (cy - a.oy - mv.ty) / ch
  local col0, row0 = floor(fx) + 1, floor(fy) + 1
  local reach = blobSize(g.kind, a, z, n) * 0.45
  local span = max(1, math.ceil(reach / min(cw, ch)))
  local best, bv, bd = nil, nil, reach * reach + 1e-6
  for row = row0 - span, row0 + span do
    for col = col0 - span, col0 + span do
      if col >= 1 and col <= n and row >= 1 and row <= n then
        local i = (row - 1) * n + col
        local v = g.cells[i]
        if type(v) == "number" and v > 0 then
          local dx = (col - 0.5) * cw - (cx - a.ox - mv.tx)
          local dy = (row - 0.5) * ch - (cy - a.oy - mv.ty)
          local d = dx * dx + dy * dy
          if d < bd then best, bv, bd = i, v, d end
        end
      end
    end
  end
  return best, bv
end

local function causeText(tip)
  local c = type(tip) == "table" and tip.cause or ""
  if c == "enemy" and type(tip.source) == "string" and tip.source ~= "" then return tip.source end
  if type(c) == "string" and c ~= "" then
    local s = T["cause_" .. c]
    if type(s) == "string" and s ~= "cause_" .. c then return s end
  end
  return T.cause_unknown
end

-- tooltip lines of cell i (value v) in the current grid
function HV.cellTip(p, i, v)
  local g = p.grid
  if not g or not i then return nil end
  if g.kind == "death" then
    local lines = { plural(v, "deaths_one", "deaths_other") }
    local list = type(g.tips) == "table" and g.tips[i] or {}
    local V = View()
    for k = 1, min(#list, HV.TIP_DEATHS) do
      local d = list[k]
      local lvl = d.level and int(d.level) or "?"
      local when = d.at and V and V.formatWhen and p.model and V.formatWhen(p.model, d.at)
      if type(when) == "string" and when ~= "" then
        lines[#lines + 1] = T("deathLineWhen", lvl, causeText(d), when)
      else
        lines[#lines + 1] = T("deathLine", lvl, causeText(d))
      end
    end
    if #list > HV.TIP_DEATHS then lines[#lines + 1] = T("deathMore", int(#list - HV.TIP_DEATHS)) end
    return lines
  end
  local lines = { v < 60 and T.stayBrief or T("stayTip", duration(v)) }
  local total = num(g.total) or 0
  if total > 0 then
    local pct = v / total * 100
    if pct < 1 then
      lines[#lines + 1] = T.stayShareSmall
    else
      lines[#lines + 1] = T("stayShare", int(pct))
    end
  end
  return lines
end

local function cursorIn(frame)
  if type(GetCursorPosition) ~= "function" then return nil end
  local s = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
  local cx, cy = GetCursorPosition()
  local left, top = frame:GetLeft(), frame:GetTop()
  if not (num(cx) and num(cy) and num(left) and num(top) and num(s) and s > 0) then return nil end
  return cx / s - left, top - cy / s
end

local function now() return type(GetTime) == "function" and GetTime() or 0 end

local function mouseDown()
  if type(IsMouseButtonDown) ~= "function" then return true end
  local ok, v = pcall(IsMouseButtonDown, "LeftButton")
  return not ok or v == true
end

function HV.zoom(p, delta, cx, cy)
  local mv, a = p.mv, p.art
  if not (mv and a and p.grid) or type(delta) ~= "number" or delta ~= delta or delta == 0 then return false end
  if not (cx and cy) then
    cx, cy = cursorIn(p.map)
    if not cx then cx, cy = a.ox + a.w / 2, a.oy + a.h / 2 end
  end
  local z0 = mv.z
  local z1 = max(1, min(HV.ZOOM_MAX, z0 * HV.ZOOM_STEP ^ max(-3, min(3, delta))))
  if math.abs(z1 - z0) < 1e-9 then return false end
  local nx, ny = (cx - a.ox - mv.tx) / z0, (cy - a.oy - mv.ty) / z0
  mv.z = z1
  mv.tx, mv.ty = cx - a.ox - nx * z1, cy - a.oy - ny * z1
  clampView(mv, a)
  p.hoverKey = nil
  W().hideTip(p.map)
  HV.paintMap(p)
  return true
end

function HV.resetView(p)
  p.mv = { z = 1, tx = 0, ty = 0 }
  p.hoverKey = nil
  W().hideTip(p.map)
  HV.paintMap(p)
end

function HV.mapTick(p)
  if not p.map:IsShown() then return end
  local cx, cy = cursorIn(p.map)
  if not cx then return end
  local pr = p.press
  if pr and not mouseDown() then
    pr = nil
    p.press = nil
  end
  if pr then
    local dx, dy = cx - pr.x, cy - pr.y
    if not pr.moved and dx * dx + dy * dy >= HV.DRAG_MIN * HV.DRAG_MIN then pr.moved = true end
    if pr.moved then
      local mv, a = p.mv, p.art
      if mv and a and mv.z > 1 then
        local tx, ty = mv.tx, mv.ty
        mv.tx, mv.ty = pr.tx + dx, pr.ty + dy
        clampView(mv, a)
        if mv.tx ~= tx or mv.ty ~= ty then
          p.hoverKey = nil
          W().hideTip(p.map)
          HV.paintMap(p)
        end
      end
      return
    end
  end
  local i, v = HV.hitCell(p, cx, cy)
  local key = i and (p.grid.kind .. i) or nil
  if key ~= p.hoverKey then
    p.hoverKey = key
    if key then W().tip(p.map, HV.cellTip(p, i, v)) else W().hideTip(p.map) end
  end
end

local function stopHover(p)
  p.press, p.hoverKey = nil, nil
  p.map:SetScript("OnUpdate", nil)
  W().hideTip(p.map)
end

local function wireMap(p, box)
  box:EnableMouse(true)
  if box.EnableMouseWheel then box:EnableMouseWheel(true) end
  box:SetScript("OnMouseWheel", guarded(function(_, delta) HV.zoom(p, delta) end))
  box:SetScript("OnMouseDown", guarded(function(f, button)
    if button ~= nil and button ~= "LeftButton" then return end
    local cx, cy = cursorIn(f)
    if not (cx and p.mv) then return end
    p.press = { x = cx, y = cy, tx = p.mv.tx, ty = p.mv.ty, moved = false }
  end))
  box:SetScript("OnMouseUp", guarded(function(_, button)
    local pr = p.press
    p.press = nil
    if button == "RightButton" then
      HV.resetView(p)
      return
    end
    if button ~= nil and button ~= "LeftButton" then return end
    if not pr or pr.moved then
      p.lastClick = nil
      return
    end
    local t = now()
    local last = p.lastClick
    if last and t - last.t <= HV.DOUBLE_CLICK and (pr.x - last.x) ^ 2 + (pr.y - last.y) ^ 2 < 64 then
      p.lastClick = nil
      HV.resetView(p)
    else
      p.lastClick = { t = t, x = pr.x, y = pr.y }
    end
  end))
  box:SetScript("OnEnter", guarded(function(f)
    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
      acc = acc + (tonumber(dt) or 0)
      if acc < 0.05 then return end
      acc = 0
      local ok, err = pcall(HV.mapTick, p)
      if not ok then
        report(err)
        stopHover(p)
      end
    end)
  end))
  box:SetScript("OnLeave", guarded(function() stopHover(p) end))
  box:SetScript("OnHide", function() stopHover(p) end)
end

-- legend: strip of LEGEND_STEPS colour fields from little to much, words left and right
local function paintLegend(p, kind)
  local L = p.legend
  for k, t in ipairs(L.steps) do
    local h = (k - 0.5) / #L.steps
    local r, g, b = HV.color(kind, h)
    t:SetColorTexture(r, g, b, 1)
  end
  L.low:SetText(kind == "death" and T.legendDeathLow or T.legendStayLow)
  L.high:SetText(kind == "death" and T.legendDeathHigh or T.legendStayHigh)
end

-- ---- build ---------------------------------------------------------------------------------------------------------------------

function HV.build(parent, level)
  local Th, Wd, Dd = Theme(), W(), D()
  if not (Th and Wd and Dd) then return nil end
  local G = Th.GRID
  local SZ = G.size
  local lx, lw = Th.gridX("L", 1, G.cols, true)
  local rx, rw = Th.gridX("R", 1, G.cols, true)
  local p = { rows = {}, offset = 0, mv = { z = 1, tx = 0, ty = 0 }, kind = kindSetting(), token = 0 }
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints(parent)
  if level and f.SetFrameLevel then f:SetFrameLevel(level) end
  f:Hide()
  p.frame = f

  -- left page: head, title, summary, red rule, rows
  local leftHead = Wd.NewPageHead(f, { side = "L", spread = true })
  local rightHead = Wd.NewPageHead(f, { side = "R", spread = true })
  p.leftHead, p.rightHead = leftHead, rightHead
  local title = Th.fontString(f, "title", SZ.xl, Th.C.ink, "OVERLAY", "LEFT")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", lx, -HV.LEFT_Y)
  title:SetText(T.title)
  p.title = title
  local sum = Th.fontString(f, "label", SZ.s, Th.C.sepia, "OVERLAY", "LEFT")
  sum:SetPoint("TOPLEFT", f, "TOPLEFT", lx, -(HV.LEFT_Y + 36))
  sum:SetWidth(lw)
  sum:SetWordWrap(false)
  p.summary = sum
  local rule = Dd.NewInkStroke(f, nil, "red", 0.35)
  rule:SetPoint("TOPLEFT", f, "TOPLEFT", lx, -(HV.LEFT_Y + HV.HEAD_H - 6))
  rule:SetPoint("TOPRIGHT", f, "TOPLEFT", lx + lw, -(HV.LEFT_Y + HV.HEAD_H - 6))
  p.rule = rule
  local listY = HV.LEFT_Y + HV.HEAD_H
  local list = CreateFrame("Frame", nil, f)
  list:SetPoint("TOPLEFT", f, "TOPLEFT", lx, -listY)
  p.listW, p.listH = lw, HV.LIST_BOTTOM - listY
  list:SetSize(p.listW, p.listH)
  if list.EnableMouseWheel then list:EnableMouseWheel(true) end
  list:SetScript("OnMouseWheel", guarded(function(_, delta)
    if type(delta) ~= "number" or (p.maxOffset or 0) <= 0 then return end
    p.offset = max(0, min(p.maxOffset, (p.offset or 0) - (delta > 0 and 1 or -1)))
    HV.layoutList(p)
  end))
  p.list = list
  local track = f:CreateTexture(nil, "ARTWORK")
  track:SetColorTexture(Wd.color("sepia", 0.2))
  track:SetPoint("TOPLEFT", f, "TOPLEFT", lx + lw + HV.BAR.gap, -listY)
  track:SetSize(HV.BAR.track, p.listH)
  track:Hide()
  p.track = track
  local thumb = CreateFrame("Button", nil, f)
  thumb:SetWidth(HV.BAR.thumb)
  local tt = thumb:CreateTexture(nil, "OVERLAY")
  tt:SetAllPoints(thumb)
  tt:SetColorTexture(Wd.color("sepia", 0.75))
  thumb:SetScript("OnMouseDown", guarded(function() beginDrag(p) end))
  thumb:SetScript("OnMouseUp", function() endDrag(p) end)
  thumb:SetScript("OnHide", function() endDrag(p) end)
  if thumb.EnableMouseWheel then thumb:EnableMouseWheel(true) end
  thumb:SetScript("OnMouseWheel", guarded(function(_, delta)
    if type(delta) == "number" then HV.scrollTo(p, (p.offset or 0) - (delta > 0 and 1 or -1)) end
  end))
  thumb:Hide()
  p.thumb = thumb
  local listEmpty = Dd.emptyNote(f, lw - 40)
  listEmpty:SetPoint("TOP", f, "TOPLEFT", lx + lw / 2, -(listY + 40))
  listEmpty:Hide()
  p.listEmpty = listEmpty

  -- right page: zone name, figures, switch, map, legend
  local zname = Th.fontString(f, "title", SZ.xl, Th.C.ink, "OVERLAY", "LEFT")
  zname:SetPoint("TOPLEFT", f, "TOPLEFT", rx, -HV.LEFT_Y)
  zname:SetWordWrap(false)
  p.zoneName = zname
  local stats = Th.fontString(f, "label", SZ.s, Th.C.sepia, "OVERLAY", "LEFT")
  stats:SetPoint("TOPLEFT", f, "TOPLEFT", rx, -(HV.LEFT_Y + 36))
  stats:SetWidth(rw)
  stats:SetWordWrap(false)
  p.stats = stats
  local tipStay = { T.modeStay, T.modeStayTip, T.mapHint }
  local tipDeath = { T.modeDeath, T.modeDeathTip, T.mapHint }
  p.toggle = Dd.NewToggle(f, { size = SZ.m, gap = 14, value = p.kind,
    items = { { key = "stay", label = T.modeStay, tip = tipStay }, { key = "death", label = T.modeDeath, tip = tipDeath } },
    onChange = guarded(function(key) HV.setKind(p, key) end) })
  p.toggle.frame:SetPoint("LEFT", f, "TOPLEFT", rx - 3, -(HV.CTRL_Y + 12))

  local mapX = rx
  p.mapW, p.mapH = rw, HV.MAP_H
  local box = CreateFrame("Frame", nil, f)
  box:SetPoint("TOPLEFT", f, "TOPLEFT", mapX, -HV.MAP_Y)
  box:SetSize(p.mapW, p.mapH)
  if box.SetClipsChildren then box:SetClipsChildren(true) end
  p.map = box
  wireMap(p, box)
  -- soft edge like the journey and Kampf maps (Media/MapFade as mask); the fine outline stays only without a mask API
  local outline = Wd.NewOutline(f, p.mapW, p.mapH, "sepia", 0.5)
  outline:SetPoint("TOPLEFT", f, "TOPLEFT", mapX, -HV.MAP_Y)
  if type(box.CreateMaskTexture) == "function" and Th.TEX and Th.TEX.mapFade then
    local ok, mk = pcall(box.CreateMaskTexture, box)
    if ok and mk then
      mk:SetTexture(Th.TEX.mapFade, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      mk:SetAllPoints(box)
      p.mapMask = mk
    end
  end
  outline:SetShown(p.mapMask == nil)
  p.outline = outline
  p.tiles = Wd.Pool(function()
    local t = box:CreateTexture(nil, "BACKGROUND")
    if t.SetDesaturated then t:SetDesaturated(true) end
    return masked(p, t)
  end, nil, 64)
  p.overlays = Wd.Pool(function()
    return masked(p, box:CreateTexture(nil, "BACKGROUND", nil, 2))
  end, nil, (View() and View().OVERLAY_MAX) or 400)
  -- the embers: an own texture pool (never the route line pool of journal/Map.lua)
  p.heat = Wd.Pool(function()
    local t = box:CreateTexture(nil, "ARTWORK")
    t:SetTexture(Th.TEX.heatBlob or Th.TEX.disc)
    return masked(p, t)
  end, nil, HV.HEAT_MAX)
  local note = Dd.emptyNote(f, p.mapW - 60)
  note:SetPoint("CENTER", f, "TOPLEFT", mapX + p.mapW / 2, -(HV.MAP_Y + p.mapH / 2))
  note:Hide()
  p.mapNote = note

  local ly = HV.MAP_Y + p.mapH + HV.LEGEND_GAP
  local L = { steps = {} }
  L.low = Th.fontString(f, "label", SZ.xs, Th.C.sepia, "OVERLAY", "LEFT")
  L.low:SetPoint("LEFT", f, "TOPLEFT", mapX, -(ly + HV.LEGEND_H / 2))
  L.frame = CreateFrame("Frame", nil, f)
  L.frame:SetSize(HV.LEGEND_W, HV.LEGEND_H)
  L.frame:SetPoint("LEFT", L.low, "RIGHT", 8, 0)
  local sw = HV.LEGEND_W / HV.LEGEND_STEPS
  for k = 1, HV.LEGEND_STEPS do
    local t = L.frame:CreateTexture(nil, "ARTWORK")
    t:SetSize(sw, HV.LEGEND_H)
    t:SetPoint("LEFT", L.frame, "LEFT", (k - 1) * sw, 0)
    L.steps[k] = t
  end
  L.high = Th.fontString(f, "label", SZ.xs, Th.C.sepia, "OVERLAY", "LEFT")
  L.high:SetPoint("LEFT", L.frame, "RIGHT", 8, 0)
  L.hint = Th.fontString(f, "label", SZ.xs, Th.C.sepia, "OVERLAY", "LEFT")
  L.hint:SetPoint("TOPLEFT", f, "TOPLEFT", mapX, -(ly + HV.LEGEND_H + 8))
  L.hint:SetWidth(rw - 70) -- ends before the doodle at the bottom right of the page
  L.hint:SetWordWrap(false)
  L.hint:SetText(T.mapHint)
  p.legend = L
  paintLegend(p, p.kind)
  return p
end

-- ---- state changes ---------------------------------------------------------------------------------------------------------------

local function setNote(p, text)
  if text then
    p.mapNote:SetText(text)
    p.mapNote:Show()
  else
    p.mapNote:Hide()
  end
end

-- a zone of the list, or a continent heading (its own entry: total time of the continent)
local function zoneById(p, id)
  if not id then return nil end
  local cz = HV.contZone(p, id)
  if cz then return cz end
  for _, z in ipairs(p.zones or {}) do
    if z.mapID == id then return z end
  end
  return nil
end

local function updateHeads(p)
  p.leftHead:SetTexts(T.head, plural(HV.zoneCount(p), "zones_one", "zones_other"))
  p.rightHead:SetTexts(T.headRight, p.kind == "death" and T.modeDeath or T.modeStay)
end

local function updateZoneHead(p)
  local z = zoneById(p, p.zoneID)
  if not z then
    p.zoneName:SetText("")
    p.stats:SetText("")
    return
  end
  p.zoneName:SetText(z.name or "")
  W().fitLine(p.zoneName, p.mapW, 16)
  local deaths = (z.deaths or 0) > 0 and plural(z.deaths, "deaths_one", "deaths_other") or T.noDeathsShort
  p.stats:SetText(T(z.continent and "statCont" or "statStay", duration(z.seconds or 0)) .. " · " .. deaths)
end

-- shows the finished grid (or the empty state of the mode)
local function showGrid(p, g)
  p.grid, p.job = g, nil
  p.hot = HV.hotList(g)
  p.hoverKey = nil
  W().hideTip(p.map)
  if (num(g.total) or 0) <= 0 or #p.hot == 0 then
    p.grid, p.hot = nil, {}
    HV.paintMap(p)
    p.map:Hide()
    p.outline:Hide()
    local z = zoneById(p, p.zoneID)
    setNote(p, g.kind == "death" and T.noDeaths or ((z and z.noTrail) and T.noTrailZone or T.noStay))
    p.empty = g.kind
    return
  end
  p.empty = nil
  setNote(p, nil)
  p.map:Show()
  p.outline:SetShown(p.mapMask == nil)
  HV.paintMap(p)
end

-- one slice of the computation; schedules the next one (next frame) until the grid is done
function HV.step(p, token)
  if token ~= p.token or not p.frame:IsShown() or not p.model or not p.zoneID then return end
  local V = View()
  local g, job, failed = V.heatGridStep(p.model, p.zoneID, p.kind, { job = p.job, budgetMs = HV.BUDGET_MS })
  if g then
    showGrid(p, g)
    return
  end
  if failed or not job then
    p.job, p.grid, p.hot = nil, nil, {}
    HV.paintMap(p)
    p.map:Hide()
    setNote(p, T.failed)
    p.failed = true
    return
  end
  p.job = job
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(0, guarded(function() HV.step(p, token) end))
  end
end

function HV.load(p)
  p.token = (p.token or 0) + 1
  p.job, p.grid, p.hot, p.failed, p.empty = nil, nil, {}, nil, nil
  p.hoverKey = nil
  HV.paintMap(p)
  if not p.zoneID then return end
  p.map:Show()
  setNote(p, T.loading)
  HV.step(p, p.token)
end

function HV.selectZone(p, mapID)
  if not zoneById(p, mapID) then return false end
  if p.zoneID ~= mapID then
    p.zoneID = mapID
    p.mv = { z = 1, tx = 0, ty = 0 }
  end
  HV.layoutList(p)
  updateZoneHead(p)
  HV.load(p)
  return true
end

function HV.setKind(p, kind)
  if not HV.KINDS[kind] then return false end
  p.kind = kind
  saveKind(kind)
  p.toggle:SetValue(kind)
  paintLegend(p, kind)
  updateHeads(p)
  HV.load(p)
  return true
end

local function setContentShown(p, on)
  for _, r in ipairs({ p.title, p.summary, p.rule, p.list, p.zoneName, p.stats, p.toggle.frame, p.legend.low, p.legend.frame,
    p.legend.high, p.legend.hint }) do
    r:SetShown(on and true or false)
  end
  if not on then
    p.track:Hide()
    p.thumb:Hide()
  end
end

-- msg: status text of the journey (loading, no data, error) instead of the content; otherwise the model of the journey
function HV.show(p, model, msg)
  if not p then return end
  p.frame:Show()
  if msg or type(model) ~= "table" then
    p.model, p.zones, p.contZones = nil, {}, nil
    p.token = (p.token or 0) + 1
    p.grid, p.hot, p.job = nil, {}, nil
    HV.paintMap(p)
    setContentShown(p, false)
    p.listEmpty:Hide()
    p.map:Hide()
    p.outline:Hide()
    p.leftHead:SetTexts(T.head, "")
    p.rightHead:SetTexts(T.headRight, "")
    setNote(p, msg or T.loading)
    return
  end
  setContentShown(p, true)
  local kind = kindSetting()
  if kind ~= p.kind then
    p.kind = kind
    paintLegend(p, kind)
  end
  p.toggle:SetValue(p.kind)
  local fresh = model ~= p.model
  if fresh then
    p.model = model
    p.zones = View().heatZones(model)
    p.contZones = nil
    if not zoneById(p, p.zoneID) then
      -- default = the zone with the most time (a continent's own map does not count as a zone: take the next one)
      local first = p.zones[1]
      for _, z in ipairs(p.zones) do
        if not HV.contZone(p, z.mapID) then
          first = z
          break
        end
      end
      p.zoneID = first and first.mapID or nil
      p.mv, p.offset = { z = 1, tx = 0, ty = 0 }, 0
    end
  end
  updateHeads(p)
  local n = #(p.zones or {})
  p.summary:SetText(T("summary", plural(HV.zoneCount(p), "zones_one", "zones_other")))
  W().fitLine(p.summary, p.listW, 10)
  if n == 0 then
    p.zoneID = nil
    HV.layoutList(p)
    p.listEmpty:SetText(T.noTrailList)
    p.listEmpty:Show()
    for _, r in ipairs({ p.zoneName, p.stats, p.toggle.frame, p.legend.low, p.legend.frame, p.legend.high, p.legend.hint }) do r:Hide() end
    p.grid, p.hot = nil, {}
    HV.paintMap(p)
    p.map:Hide()
    p.outline:Hide()
    setNote(p, T.noTrail)
    p.empty = "trail"
    return
  end
  p.listEmpty:Hide()
  HV.layoutList(p)
  updateZoneHead(p)
  -- a new model (data grew) recomputes; the same model (switching back to the sub-page) redraws the cached grid at once
  if fresh or not (p.grid or p.empty or p.failed) or p.job then
    HV.load(p)
  else
    HV.paintMap(p)
  end
end

function HV.hide(p)
  if not p then return end
  p.token = (p.token or 0) + 1
  p.job = nil
  if p.map then stopHover(p) end
  p.frame:Hide()
end

-- another character's book (or back): start from scratch
function HV.reset(p)
  if not p then return end
  HV.hide(p)
  p.model, p.zones, p.zoneID, p.grid, p.hot, p.offset, p.contZones = nil, {}, nil, nil, {}, 0, nil
  p.mv = { z = 1, tx = 0, ty = 0 }
  p.artCache = nil
end
