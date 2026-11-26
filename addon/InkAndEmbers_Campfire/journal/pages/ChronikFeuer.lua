-- Chronik sub-view "Am Feuer" (module Campfire, split off journal/pages/ChronikViews.lua in 1.1.0): behind the switch
-- "Gruppe | Am Feuer" of the bookmark "Weggefährten". Data: model/FireMates.lua (core). Grid, fonts and the switch come from
-- Journal.ChronikViewsKit (core). All foreign text goes through Sanitize.display. No ticker, no OnUpdate; frames are built on first open.
local _, ns = ...

-- Locale call with place names (core Grammar.lua): "in %s" -> "im Brachland" / "in the Barrens"
local function placeCall(TT, key, places, ...)
  local G = ns.Grammar
  if G then return G.call(TT, key, places, ...) end
  return TT(key, ...)
end

local Journal = ns.Journal
local W, Pages = Journal and Journal.Widgets, Journal and Journal.Pages
local D = W and W.Diary
local K, Mates = Journal and Journal.ChronikViewsKit, Journal and Journal.CompanionsView
if not (W and Pages and D and K and Mates) then return end

local floor, max, min = math.floor, math.max, math.min
local unpack = unpack or table.unpack

local Theme = Journal.Theme
local G = Theme.GRID
local SZ = G.size
local SL, SR, IN_X, BODY_X, BODY_W, TITLE_Y, SUB_Y = K.SL, K.SR, K.IN_X, K.BODY_X, K.BODY_W, K.TITLE_Y, K.SUB_Y
local fitName, disp, int, set, font = K.fitName, K.disp, K.int, K.set, K.font
local addSwitch, syncSwitch, dateText, countText = K.addSwitch, K.syncSwitch, K.dateText, K.countText
local MT = Mates.TEXT

-- Companions at the fire: like "Weggefährten" but for the people from the campfire (log line LF, model/FireMates.lua):
-- sort "zuletzt" / "am häufigsten", profile of the selected person with their latest fires. Also the tooltip of the
-- diary entries "Am Lagerfeuer in <Zone> mit ..." (Fire.entryTip).
-- Trial rounds (retail simulation) carry "(Probe)". A running round (ns.Campfire.session()) shows as "läuft gerade"
-- with its guests first (FireMates.withLive); with the view open, ns.onCampfire redraws at once, the end fetches the
-- new index (Pages.refresh).

local Fire = {}
Fire.__index = Fire
Journal.FireMatesView = Fire

Fire.TEXT = ns.Locale.ns("p.ChronikViews.Fire", {
  page = "AM FEUER", brand = "INK & EMBERS", title = "Weggefährten am Feuer", empty = "Noch kein Feuer geteilt.",
  emptyBody = "Setzt Euch an ein Lagerfeuer: Wer eine Weile mit Euch dort verweilt, wird hier festgehalten.",
  sortRecent = "zuletzt", sortCount = "am häufigsten", sortRecentTip = "Zuletzt am Feuer gesehen zuerst",
  sortCountTip = "Meiste gemeinsame Feuer zuerst", pick = "Für Details auf einen Namen klicken.",
  prevTip = "Vorige Seite", nextTip = "Nächste Seite", truncated = "Sehr viele Gäste: ältere sind nicht mehr aufgeführt.",
  fires = "Gemeinsame Feuer", first = "Zuerst am Feuer", last = "Zuletzt am Feuer", visits = "Die letzten Feuer",
  unknownZone = "unbekanntem Ort", tipMore = "und %s weitere", oneFire = "1 Feuer", manyFires = "%s Feuer",
  level = "Stufe %s", lastIn = "zuletzt in %s am %s", lastAt = "zuletzt am %s",
  probe = " (Probe)", live = "läuft gerade", liveIn = "läuft gerade in %s", liveRound = "Runde läuft gerade",
})
Fire.ROWS, Fire.ROW_H = Mates.ROWS, Mates.ROW_H
Fire.VISITS_MAX = 6

function Fire.fireCount(n)
  n = tonumber(n) or 0
  return n == 1 and Fire.TEXT.oneFire or Fire.TEXT("manyFires", int(n))
end

-- "Orc · Krieger" with the class form by sex (sex 3 = female) if the client knows it
function Fire.kindText(p)
  local race = Mates.RACE_NAME[p.race] or disp(p.race, 24)
  local cls = Mates.className(p.class, p.sex) or disp(p.class, 24)
  if race and cls then return race .. " · " .. cls end
  return race or cls
end

-- shown name of a campfire guest (raw): Forever "Vorname Nachname" (never a shard), Retail the first name (Names.mateName)
function Fire.personName(p)
  local N = ns.Names
  if not N or type(p) ~= "table" then return nil end
  if type(p.name) == "string" then return N.mateName(p.name, p.realm) end
  return N.mateName(p.full)
end

-- a person in the diary entry tooltip: "Kuno · Orc · Krieger · Stufe 12" (raw values from the log, all via display)
function Fire.personLine(p)
  local raw = p.name or p.full
  local first = type(raw) == "string" and (string.match(raw, "^([^%-]+)") or raw) or nil
  if first and ns.Names then first = Fire.personName(p) or first end
  local parts = { disp(first, 48) or "?" }
  local kind = Fire.kindText(p)
  if kind then parts[#parts + 1] = kind end
  local lv = tonumber(p.level)
  if lv then parts[#parts + 1] = Fire.TEXT("level", int(lv)) end
  return table.concat(parts, " · ")
end

-- tooltip of a diary entry "Am Lagerfeuer ...": time, sentence, then one line per person in class colour
function Fire.entryTip(e, text)
  local ctx = type(e) == "table" and e.ctx
  if type(ctx) ~= "table" or type(ctx.people) ~= "table" or #ctx.people == 0 then return nil end
  local lines, colors = { e.clock or "", text or "" }, {}
  for _, p in ipairs(ctx.people) do
    lines[#lines + 1] = Fire.personLine(p)
    colors[#lines] = Mates.classColor(p.class)
  end
  local more = (tonumber(ctx.n) or #ctx.people) - #ctx.people
  if more > 0 then lines[#lines + 1] = Fire.TEXT("tipMore", int(more)) end
  return lines, colors
end

function Fire:DateText(t)
  return dateText(self.index, t)
end

local function levelOf(p)
  local lv = tonumber(p.level)
  return lv and Fire.TEXT("level", int(lv)) or ""
end

-- display-ready texts of a person
function Fire:Lines(p)
  local T = Fire.TEXT
  if p.live then
    local lz = disp(p.liveZone, 40)
    return {
      name = disp(Fire.personName(p) or p.name or p.full, 48) or "?",
      level = levelOf(p),
      kind = Fire.kindText(p),
      fires = Fire.fireCount(p.n),
      last = (lz and placeCall(T, "liveIn", { [1] = "zone" }, lz) or T.live) .. (p.liveSim and T.probe or ""),
      lastZone = lz,
      lastText = T.live .. (p.liveSim and T.probe or ""),
    }
  end
  local zone = disp(p.lastZone, 40)
  local probe = p.lastSim and T.probe or ""
  return {
    name = disp(Fire.personName(p) or p.name or p.full, 48) or "?",
    level = levelOf(p),
    kind = Fire.kindText(p),
    fires = Fire.fireCount(p.n),
    last = (zone and placeCall(Fire.TEXT, "lastIn", { [1] = "zone" }, zone, self:DateText(p.lastT)) or Fire.TEXT("lastAt", self:DateText(p.lastT))) .. probe,
    lastZone = zone,
    lastText = self:DateText(p.lastT) .. (zone and (", " .. zone) or "") .. probe,
  }
end

function Fire:Tip(p)
  local T = Fire.TEXT
  local s = self:Lines(p)
  local lines = { s.name }
  if s.kind or s.level ~= "" then lines[#lines + 1] = table.concat({ s.kind or "", s.level }, (s.kind and s.level ~= "") and " · " or "") end
  lines[#lines + 1] = T.fires .. ": " .. int(p.n or 0)
  local fz = disp(p.firstZone, 40)
  lines[#lines + 1] = T.first .. ": " .. self:DateText(p.firstT) .. (fz and (", " .. fz) or "")
  lines[#lines + 1] = T.last .. ": " .. s.lastText
  return lines, { Mates.classColor(p.class) }
end

local function buildFireRow(self, row)
  local nm = font(row, "title", SZ.m, "ink", "LEFT")
  nm:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
  nm:SetWidth(BODY_W - 120)
  nm:SetWordWrap(false)
  local lv = font(row, "label", SZ.s, "sepia", "RIGHT")
  lv:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
  lv:SetWidth(110)
  local kind = font(row, "label", SZ.s, "sepia", "LEFT")
  kind:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -23)
  kind:SetWidth(BODY_W - 16)
  kind:SetWordWrap(false)
  local stats = font(row, "label", SZ.s, "ink", "LEFT")
  stats:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -37)
  stats:SetWidth(BODY_W - 16)
  stats:SetWordWrap(false)
  row.label:SetText("")
  row.name, row.lv, row.kind, row.stats = nm, lv, kind, stats
  -- set own hover scripts before RowStyle (RowStyle hooks in behind them with HookScript)
  row:SetScript("OnEnter", function(r)
    if r.person then
      local lines, colors = self:Tip(r.person)
      W.tip(r, lines, colors)
    end
  end)
  row:SetScript("OnLeave", function(r) W.hideTip(r) end)
  D.RowStyle(row, { texts = { stats } })
end

function Fire.new(page, left, right)
  local self = setmetatable({ page = page, sort = "recent" }, Fire)
  local T = Fire.TEXT
  local l, r = CreateFrame("Frame", nil, left), CreateFrame("Frame", nil, right)
  l:SetAllPoints(left)
  r:SetAllPoints(right)
  self.l, self.r = l, r
  local headL = W.NewPageHead(l, { side = "L" })
  headL:SetTexts(T.brand, T.page)
  addSwitch(self, l, "fire", headL)
  W.NewPageHead(r, { side = "R" }):SetTexts("", T.page)
  D.escKeys(l, function() page:CloseSub() end) -- Esc -> overview
  local head = D.NewSectionHead(l, T.title, { size = SZ.xl })
  head:SetPoint("TOPLEFT", l, "TOPLEFT", IN_X, -(TITLE_Y - 6))
  self.count = font(l, "label", SZ.s, "sepia", "LEFT")
  self.count:SetPoint("TOPLEFT", l, "TOPLEFT", IN_X, -SUB_Y)
  local cy = -(G.slots.ctrl.y + G.slots.ctrl.h / 2)
  self.toggle = D.NewToggle(l, { size = SZ.m, gap = 12, value = "recent",
    items = { { key = "recent", label = T.sortRecent, tip = { T.sortRecentTip } }, { key = "count", label = T.sortCount, tip = { T.sortCountTip } } },
    onChange = function(key) self:SetSort(key) end })
  self.toggle.frame:SetPoint("LEFT", l, "TOPLEFT", IN_X - 3, cy)
  self.nav = D.NewNavPair(l, { onPrev = function() self:Page(-1) end, onNext = function() self:Page(1) end,
    tipPrev = { T.prevTip }, tipNext = { T.nextTip } })
  self.nav.frame:SetPoint("RIGHT", l, "TOPLEFT", SL.x + SL.w + 4, cy)
  self.pos = font(l, "label", SZ.s, "sepia", "RIGHT")
  self.pos:SetPoint("RIGHT", self.nav.frame, "LEFT", -6, 0)
  self.list = W.NewList(l, { rows = Fire.ROWS, rowHeight = Fire.ROW_H, width = BODY_W, empty = T.empty, emptyHand = true,
    build = function(row) buildFireRow(self, row) end,
    clear = function(row)
      row.person = nil
      for _, k in ipairs({ "name", "lv", "kind", "stats" }) do set(row[k], "") end
      if row.SetSelected then row:SetSelected(false) end
      W.hideTip(row)
    end,
    fill = function(row, p)
      row.person = p
      local s = self:Lines(p)
      set(row.name, s.name)
      row.name:SetTextColor(unpack(Mates.classColor(p.class)))
      set(row.lv, s.level)
      set(row.kind, s.kind or "")
      set(row.stats, s.fires .. " · " .. s.last)
      if row.SetSelected then row:SetSelected(self.sel ~= nil and self.sel == p.key) end
      D.rowFilled(row)
    end,
    onClick = function(p) self:Select(p) end })
  self.list.frame:SetPoint("TOPLEFT", l, "TOPLEFT", BODY_X, -G.slots.body.y)
  local refresh = self.list.Refresh
  self.list.Refresh = function(list)
    refresh(list)
    self:UpdatePager()
  end
  self.note = font(l, "label", SZ.xs, "sepia", "RIGHT")
  local pt, fx, fy = Theme.gridFoot("L")
  self.note:SetPoint(pt, l, "TOPLEFT", fx, -(fy + 6))
  self.note:SetWidth(SL.x + SL.w - Theme.gridX("L", 4))

  -- right page: profile of the selected person
  local u = {}
  u.name = font(r, "title", SZ.xl, "ink", "LEFT")
  u.name:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -G.slots.title.y)
  u.name:SetWidth(SR.w - 30)
  u.name:SetWordWrap(false)
  u.nameHover = CreateFrame("Frame", nil, r)
  u.nameHover:SetPoint("TOPLEFT", u.name, "TOPLEFT", 0, 0)
  u.nameHover:SetSize(SR.w - 30, 34)
  u.nameHover:EnableMouse(false)
  u.nameHover:SetScript("OnEnter", function(h) if h.full then W.tip(h, { h.full }) end end)
  u.nameHover:SetScript("OnLeave", function(h) W.hideTip(h) end)
  u.kind = font(r, "text", SZ.s, "sepia", "LEFT")
  u.kind:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -SUB_Y)
  u.kind:SetWidth(SR.w)
  u.leads = {}
  for i, key in ipairs({ "fires", "first", "last" }) do
    local y = -G.slots.body.y - (i - 1) * 28
    local k = font(r, "label", SZ.s, "sepia", "LEFT")
    k:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, y)
    set(k, T[key])
    local v = font(r, "title", SZ.m, "ink", "RIGHT")
    v:SetPoint("TOPRIGHT", r, "TOPLEFT", SR.x + SR.w, y + 1)
    v:SetWidth(SR.w - 170)
    v:SetWordWrap(false)
    u.leads[key] = { k = k, v = v }
  end
  u.hint = D.emptyNote(r, SR.w - 40)
  u.hint:SetPoint("TOP", r, "TOPLEFT", SR.x + SR.w / 2, -(G.slots.body.y + 40))
  -- below it the latest fires of this person (date · zone · level), newest first
  local vy = G.slots.body.y + 3 * 28 + 14
  u.visitsHead = D.NewSectionHead(r, T.visits, { width = SR.w, size = 18 })
  u.visitsHead:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -vy)
  u.visits = {}
  for j = 1, Fire.VISITS_MAX do
    local fs = font(r, "text", SZ.s, "ink", "LEFT")
    fs:SetWidth(SR.w)
    fs:SetWordWrap(false)
    fs:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -(vy + 30 + (j - 1) * G.line.text))
    u.visits[j] = fs
  end
  self.card = u
  l:Hide()
  r:Hide()
  return self
end

function Fire:IsOpen() return self.open == true end

function Fire:Page(delta)
  local list = self.list
  if not list then return end
  list:SetOffset(list:GetOffset() + (tonumber(delta) or 0) * Fire.ROWS)
end

function Fire:UpdatePager()
  local list = self.list
  if not (list and self.nav) then return end
  local n = #(list.items or {})
  local pages = max(1, math.ceil(n / Fire.ROWS))
  local off = list:GetOffset()
  local p = (off >= list:MaxOffset()) and pages or min(pages, floor(off / Fire.ROWS) + 1)
  self.nav:SetEnabled(off > 0, off < list:MaxOffset())
  self.nav.frame:SetShown(pages > 1)
  set(self.pos, pages > 1 and MT("pageOf", int(p), int(pages)) or "")
end

function Fire:SetSort(key)
  self.sort = key == "count" and "count" or "recent"
  self.toggle:SetValue(self.sort)
  self.list:SetOffset(0)
  self:Render()
end

function Fire:Select(p)
  self.sel = p and p.key or nil
  self.list:Refresh()
  self:RenderCard()
end

function Fire:RenderCard()
  local T, u = Fire.TEXT, self.card
  local p
  for _, x in ipairs(self.items or {}) do if x.key == self.sel then p = x end end
  local show = p ~= nil
  for _, l in pairs(u.leads) do
    l.k:SetShown(show)
    l.v:SetShown(show)
  end
  u.visitsHead:SetShown(show)
  for _, fs in ipairs(u.visits) do set(fs, "") end
  if not p then
    set(u.name, "")
    u.nameHover.full = nil
    u.nameHover:EnableMouse(false)
    set(u.kind, "")
    set(u.hint, (#(self.items or {}) == 0) and T.emptyBody or T.pick)
    return
  end
  set(u.hint, "")
  local s = self:Lines(p)
  set(u.name, s.name)
  fitName(u, SR.w - 30)
  u.name:SetTextColor(unpack(Mates.classColor(p.class)))
  local kind = s.kind or ""
  set(u.kind, (kind ~= "" and s.level ~= "") and (kind .. " · " .. s.level) or (kind .. s.level))
  set(u.leads.fires.v, int(p.n or 0))
  local fz = disp(p.firstZone, 40)
  set(u.leads.first.v, self:DateText(p.firstT) .. (fz and (", " .. fz) or ""))
  set(u.leads.last.v, s.lastText)
  -- the latest fires, newest first (up to VISITS_MAX)
  local n = #(p.visits or {})
  for j = 1, min(n, Fire.VISITS_MAX) do
    local v = p.visits[n - j + 1]
    local parts = { self:DateText(v.t), disp(v.zone, 40) or T.unknownZone }
    if tonumber(v.level) then parts[#parts + 1] = Fire.TEXT("level", int(v.level)) end
    set(u.visits[j], table.concat(parts, " · ") .. (v.sim and T.probe or ""))
  end
end

function Fire:Render()
  local res = self.res
  self.items = Journal.FireMates.sorted(res, self.sort)
  local n = #self.items
  local fires = res and tonumber(res.rounds) or 0
  local count = n == 0 and "" or (countText(MT, n, "persons") .. " · " .. Fire.fireCount(fires))
  local live = res and res.live
  if live then
    local T = Fire.TEXT
    count = count .. (count ~= "" and " · " or "") .. T.liveRound .. (live.sim and T.probe or "")
  end
  set(self.count, count)
  self.toggle.frame:SetShown(n > 1)
  set(self.note, (res and res.truncated) and Fire.TEXT.truncated or "")
  local found = false
  for _, x in ipairs(self.items) do if x.key == self.sel then found = true end end
  if not found then self.sel = n > 0 and self.items[1].key or nil end
  self.list:SetItems(self.items)
  self.list:Refresh()
  self:RenderCard()
end

function Fire:Load(index)
  self.index = index
  local FM = Journal.FireMates
  local res = FM.aggregate(index) or { list = {}, count = 0, rounds = 0 }
  -- another character's book (read only): no running campfire round of the logged-in character is mixed in
  local C = ns.Campfire
  local guest = Pages and type(Pages.guest) == "function" and Pages.guest() or nil
  local ok, live = false, nil
  if not guest then ok, live = pcall(function() return C and C.session and C.session() end) end
  self.res = FM.withLive(res, ok and live or nil)
end

function Fire:Open(index)
  self.open = true
  syncSwitch(self, "fire", Fire.TEXT)
  self:Load(index)
  self.l:Show()
  self.r:Show()
  self:Render()
end

function Fire:Refresh(index)
  if not self.open then return end
  self:Load(index)
  self:Render()
end

-- a campfire round starts/changes/ends while the view is open: redraw at once; the end wrote a new LF line, so fetch fresh data
-- (Pages.refresh: old state at once, the new one via onReady after the background build).
function Fire.onCampfire(what)
  local pg = Journal.ChronikPage
  local v = pg and pg.fireView
  if not (v and v:IsOpen()) or (what ~= "start" and what ~= "update" and what ~= "end") then return end
  if what == "end" and Pages and type(Pages.refresh) == "function" then
    Pages.refresh()
  else
    v:Refresh(v.index)
  end
end
if type(ns.onCampfire) == "function" then
  ns.onCampfire(function(what)
    local ok, err = pcall(Fire.onCampfire, what)
    if not ok and Pages and type(Pages.fail) == "function" then Pages.fail("chronik", err) end
  end)
end

function Fire:Close()
  self.open = false
  self.l:Hide()
  self.r:Hide()
  for _, row in ipairs(self.list.rows) do W.hideTip(row) end
  for _, b in ipairs(self.toggle.buttons) do W.hideTip(b) end
  for _, b in ipairs(self.switch.buttons) do W.hideTip(b) end
  W.hideTip(self.nav.prev)
  W.hideTip(self.nav.next)
end
