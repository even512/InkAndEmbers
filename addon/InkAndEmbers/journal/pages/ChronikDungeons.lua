-- Sub-view "Durchläufe" (dungeon runs) of the tab Dungeons, opened via its first sub-bookmark (pages/Dungeons.lua; until I12 it
-- sat in the Chronik). The page passed to View.new is the Dungeons page module.
-- Data: model/Dungeons.lua (runs folded from the instance visits) plus model/Companions.lua for the group. Left: list of the
-- runs (newest first), right: the chosen run as a book page (when, how long, level, kills, bosses with failed attempts, group,
-- deaths, finds, quests). All foreign text (instance, boss, player, item and quest names) goes through Sanitize.display.
-- No ticker, no OnUpdate; frames are built on first open, the list pool is bounded, the heavy parts of a run (group, deaths,
-- finds, quests, experience) are computed only for the visible rows / the chosen run.
local _, ns = ...

local Journal = ns.Journal
local W, Pages = Journal and Journal.Widgets, Journal and Journal.Pages
local D = W and W.Diary
local Mates, Dungeons = Journal and Journal.CompanionsView, Journal and Journal.Dungeons
if not (W and Pages and D and Mates and Dungeons) then return end

local floor, max, min = math.floor, math.max, math.min
local format = string.format
local unpack = unpack or table.unpack

-- grid as in pages/ChronikViews.lua (docs/raster.md): left list from the text block + 4, right page down to the ink splash
local Theme = Journal.Theme
local G = Theme.GRID
local SZ = G.size
local SL, SR = {}, {}
SL.x, SL.w = Theme.gridX("L")
SR.x, SR.w = Theme.gridX("R")
local IN_X = Theme.gridX("L", 2) + 4
local BODY_X, BODY_W = SL.x + 4, SL.w - 4
local TITLE_Y = G.slots.title.y - 4
local SUB_Y = G.slots.title.y + 34

local View = {}
View.__index = View
Journal.DungeonsView = View

View.TEXT = ns.Locale.ns("p.ChronikDungeons", {
  page = "DUNGEONS", brand = "INK & EMBERS", title = "Dungeons", empty = "Noch kein Dungeon besucht.",
  emptyBody = "Sobald Ihr einen Dungeon betretet, hält das Buch jeden Durchlauf fest: wann, wie lange, mit wem, die Bosse, Tode und Beute.",
  pick = "Für Details auf einen Durchlauf klicken.", prevTip = "Vorige Seite", nextTip = "Nächste Seite", pageOf = "Seite %s von %s",
  runs_one = "%s Durchlauf", runs_other = "%s Durchläufe", truncated = "Sehr viele Durchläufe: ältere sind nicht aufgeführt.",
  date = "{d}.{m}.{y}", dateShort = "{d}.{m}.",
  bosses_one = "%s Boss besiegt", bosses_other = "%s Bosse besiegt", complete = "abgeschlossen", live = "läuft gerade",
  endUnknown = "Ende unbekannt", deaths_one = "%s Tod", deaths_other = "%s Tode", noDeaths = "ohne Tod",
  unknownInstance = "Unbekannter Dungeon", unknownBoss = "Unbekannter Boss",
  when = "Wann", duration = "Dauer", level = "Stufe", kills = "Kills", xp = "Erfahrung",
  visits_one = "%s Instanzeintritt", visits_other = "%s Instanzeintritte", lv = "Stufe %s", levelRange = "Stufe %s bis %s",
  you = "Ihr", roll_need = "Bedarf", roll_greed = "Gier", roll_de = "Entzaubern", roll_tmog = "Transmog",
  whenSame = "{date}, {from}–{to}", whenOther = "{from} – {to}", whenLive = "{date}, ab {from}",
  secBosses = "Bosse", secBossesN = "Bosse · %s besiegt", secBossesOf = "Bosse · %s von %s besiegt",
  secGroup = "Gruppe", secDeaths = "Tode", secLoot = "Funde (ab Grün)", secQuests = "Quests",
  tries_one = "%s Fehlversuch", tries_other = "%s Fehlversuche", bossWon = "besiegt", bossNot = "nicht besiegt",
  bossCountOnly = "Der Client hat die Bosskämpfe nicht gemeldet, nur die Zahl ist bekannt.",
  noGroup = "Keine Gruppenmitglieder aufgezeichnet.",
  cause_enemy = "durch einen Gegner", cause_fall = "durch einen Sturz", cause_drown = "ertrunken", cause_fatigue = "vor Erschöpfung",
  cause_lava = "in der Lava", cause_fire = "im Feuer", cause_slime = "im Schleim", cause_environment = "durch die Umgebung",
  byFoe = "durch %s", guess = "%s (vermutet)", died = "gestorben", more = "… und %s weitere",
  questDone = "abgegeben", questTaken = "angenommen", questFallback = "Quest #%s", itemFallback = "Gegenstand #%s",
  xpUnit = "%s EP", reward = "Belohnung: %s", groupTip = "Gruppe",
})
local T = View.TEXT

View.ROWS, View.ROW_H = 6, 52          -- list: 6 rows down to above the seals bottom left, paging in the control line
View.DETAIL_ROWS, View.DETAIL_H = 20, G.line.row
View.ICONS = 5                          -- class symbols per list row
View.TIP_PEOPLE = 8

local function disp(v, n)
  local S = ns.Sanitize
  return S and S.display(v, n) or nil
end

local function int(n) return Journal.Texts.int(n) end
local function set(fs, text) W.setText(fs, text) end

local function font(parent, kind, size, color, justify)
  local fs = W.font(parent, kind, size, color)
  if justify then fs:SetJustifyH(justify) end
  return fs
end

local function count(n, key) return T(ns.Locale.plural(n, key .. "_one", key .. "_other"), int(n)) end

local function dateText(index, t)
  local d, m, y = Journal.Index.dateOf(index, t)
  if not d then return "?" end
  return T("date", { d = format("%02d", d), m = format("%02d", m), y = format("%04d", y) })
end

local function shortDate(index, t)
  local d, m = Journal.Index.dateOf(index, t)
  if not d then return "?" end
  return T("dateShort", { d = format("%02d", d), m = format("%02d", m) })
end

local function clock(index, t)
  local h, m = Journal.Index.timeOfDay(index, t)
  if not h then return "?" end
  return format("%02d:%02d", h, m)
end

local function mmss(s)
  s = floor(tonumber(s) or 0)
  return format("%d:%02d", floor(s / 60), s % 60)
end

local function duration(seconds)
  return Journal.DiaryTexts.duration(seconds) or ""
end

local function sameDay(index, a, b)
  local Idx = Journal.Index
  return Idx.dayOf(index, a) == Idx.dayOf(index, b)
end

-- texts of a run ----------------------------------------------------------------------------------------------------------

function View.runName(run)
  return disp(run.name, Dungeons.NAME_MAX) or T.unknownInstance
end

-- "4 Bosse besiegt", with completion from the game when it is sure ("abgeschlossen")
function View.bossText(run)
  local text = count(run.bossesDefeated or 0, "bosses")
  local c = Dungeons.completion(run)
  if c and c.complete then text = text .. " · " .. T.complete end
  return text, c
end

function View.deathText(run)
  local n = run.deathsCount or 0
  return n > 0 and count(n, "deaths") or T.noDeaths
end

-- "Normal · 1 Std. 2 Min. · 4 Bosse besiegt"
function View.infoText(run)
  local parts = {}
  local diff = Dungeons.difficultyName(run.difficultyID)
  if diff then parts[#parts + 1] = disp(diff, 40) end
  parts[#parts + 1] = run.live and T.live or duration(run.seconds)
  parts[#parts + 1] = View.bossText(run)
  return table.concat(parts, " · ")
end

local function whenText(index, run)
  if run.live then
    return T("whenLive", { date = dateText(index, run.t0), from = clock(index, run.t0) })
  end
  if sameDay(index, run.t0, run.t1) then
    return T("whenSame", { date = dateText(index, run.t0), from = clock(index, run.t0), to = clock(index, run.t1) })
  end
  return T("whenOther", { from = shortDate(index, run.t0) .. " " .. clock(index, run.t0),
    to = shortDate(index, run.t1) .. " " .. clock(index, run.t1) })
end

local function levelText(run, level1)
  local a, b = tonumber(run.level0), tonumber(level1 or run.level1)
  if a and b and a ~= b then return T("levelRange", int(a), int(b)) end
  if a or b then return T("lv", int(a or b)) end
  return nil
end

local function personKind(m)
  local cls = Mates.className(m.class) or disp(m.class, 24)
  local lv = tonumber(m.level)
  if cls and lv then return cls .. " · " .. T("lv", int(lv)) end
  return cls or (lv and T("lv", int(lv))) or ""
end

local function causeText(dth)
  local word = dth.cause and T["cause_" .. dth.cause]
  local text
  if dth.cause == "enemy" and dth.foe then
    text = T("byFoe", disp(dth.foe, 40) or "?")
  elseif type(word) == "string" and word ~= "cause_" .. tostring(dth.cause) then
    text = word
  end
  if not text then return T.died end
  return dth.guess and T("guess", text) or text
end

-- items of the detail list ----------------------------------------------------------------------------------------------

local function head(text) return { kind = "head", text = text } end
local function kv(k, v) return { kind = "kv", k = k, v = v } end
local function line(left, right, color) return { kind = "line", left = left, right = right, color = color } end
local function note(text) return { kind = "note", text = text } end

-- display name of a group member/recipient ("Vorname-Nachname" key): Forever "Vorname Nachname" (never a shard), Retail unchanged
local function mateText(raw)
  local N = ns.Names
  return disp(N and N.mateName(raw, nil, true) or raw, 48) or "?"
end

-- own character from the saved character data: name, class file, class/race text and the level range of the run; nil without a name
local function ownEntry(index, run, level1)
  local info = type(index) == "table" and type(index.char) == "table" and index.char.info
  if type(info) ~= "table" then return nil end
  local name = disp(ns.Names and ns.Names.fullName(info) or info.name, 48) -- "Vorname Nachname" on Forever (Names.lua)
  if not name or name == "" then return nil end
  local class = type(info.classFile) == "string" and info.classFile ~= "" and info.classFile or nil
  local cls = class and Mates.className(class) or disp(info.class, 24)
  local lvl = levelText(run, level1)
  local kind = (cls and lvl) and (cls .. " · " .. lvl) or cls or lvl or ""
  return { name = name, class = class, kind = kind }
end

function View:Items(run)
  local index = self.index
  local d = Dungeons.detail(index, run)
  local out = {}
  out[#out + 1] = kv(T.when, whenText(index, run))
  local dur = run.live and T.live or duration(run.seconds)
  if run.visits > 1 then dur = dur .. " · " .. count(run.visits, "visits") end
  out[#out + 1] = kv(T.duration, dur)
  local lvl = levelText(run, d.level1)
  if lvl then out[#out + 1] = kv(T.level, lvl) end
  if (run.kills or 0) > 0 then out[#out + 1] = kv(T.kills, int(run.kills)) end
  if d.xp then out[#out + 1] = kv(T.xp, T("xpUnit", int(d.xp))) end

  -- bosses in the order of the fights
  local _, comp = View.bossText(run)
  local title = comp and T("secBossesOf", int(comp.defeated), int(comp.total)) or ((run.bossesDefeated or 0) > 0 and T("secBossesN", int(run.bossesDefeated)) or T.secBosses)
  if comp and comp.complete then title = title .. " · " .. T.complete end
  if #run.bosses > 0 or run.bossesFromCount then
    out[#out + 1] = head(title)
    for i, b in ipairs(run.bosses) do
      local parts = {}
      if b.wipes > 0 then parts[#parts + 1] = count(b.wipes, "tries") end
      if b.defeated then
        parts[#parts + 1] = T.bossWon .. (b.seconds and (" " .. mmss(b.seconds)) or "")
      else
        parts[#parts + 1] = T.bossNot
      end
      local tip = { disp(b.name, 48) or T.unknownBoss }
      for _, p in ipairs(parts) do tip[#tip + 1] = p end
      local it = line(format("%d. %s", i, disp(b.name, 48) or T.unknownBoss), table.concat(parts, " · "))
      it.tip = tip
      out[#out + 1] = it
    end
    if run.bossesFromCount then out[#out + 1] = note(T.bossCountOnly) end
  end

  -- group (WB/WV)
  local group = Dungeons.group(index, run)
  out[#out + 1] = head(T.secGroup)
  -- the own character first, with the level of the run (detail only; list symbols and tooltip stay with the companions)
  local own = ownEntry(index, run, d.level1)
  if own then
    local it = line(own.name, own.kind, Mates.classColor(own.class))
    it.tip = { own.name, own.kind }
    it.tipColors = { Mates.classColor(own.class) }
    out[#out + 1] = it
  elseif #group == 0 then
    out[#out + 1] = note(T.noGroup)
  end
  for _, m in ipairs(group) do
    local mname = mateText(m.name)
    local it = line(mname, personKind(m), Mates.classColor(m.class))
    it.tip = { mname, personKind(m), duration(m.seconds) }
    it.tipColors = { Mates.classColor(m.class) }
    out[#out + 1] = it
  end

  -- deaths (DE + DC)
  if #d.deaths > 0 or d.deathMore > 0 then
    out[#out + 1] = head(T.secDeaths)
    for _, dth in ipairs(d.deaths) do
      local it = line(clock(index, dth.t) .. " · " .. causeText(dth), dth.sub and disp(dth.sub, 40) or "")
      it.tip = { clock(index, dth.t), causeText(dth), dth.sub and disp(dth.sub, 40) or nil }
      out[#out + 1] = it
    end
    if d.deathMore > 0 then out[#out + 1] = note(T("more", int(d.deathMore))) end
  end

  -- finds from green up: original item tooltip
  if #d.loot > 0 or d.lootMore > 0 then
    out[#out + 1] = head(T.secLoot)
    local F = Journal.Fmt
    -- recipients only when the run has group finds (LG); older runs look as before: item and time
    local hasGroup = false
    for _, l in ipairs(d.loot) do if l.who then hasGroup = true end end
    for _, l in ipairs(d.loot) do
      local name = disp(l.name, 48) or (self.names and self.names.name(l.itemID)) or T("itemFallback", format("%.0f", l.itemID))
      if l.count > 1 then name = name .. " ×" .. int(l.count) end
      local r, g, b
      if l.quality and F and F.qualityRGB then r, g, b = F.qualityRGB(l.quality) end
      local it = line(name, clock(index, l.t), r and { r, g, b } or nil)
      local recipient
      if hasGroup then
        -- between item and time: recipient (class colour; our own finds "Ihr") and, small behind it, the kind of roll when known
        local who = l.who and mateText(l.who) or T.you
        local rollWord = l.roll and T["roll_" .. l.roll]
        if type(rollWord) ~= "string" or rollWord == "roll_" .. tostring(l.roll) then rollWord = nil end
        it.who, it.roll = who, rollWord or ""
        it.whoColor = l.who and l.class and Mates.classColor(l.class) or nil
        recipient = rollWord and (who .. " · " .. rollWord) or who
      end
      local link = Journal.Texts.itemString(l.key)
      it.tip = { clock(index, l.t), name, recipient }
      if link then
        it.tip.item = link
        it.tip.itemExtra = { clock(index, l.t), recipient }
      end
      out[#out + 1] = it
    end
    if d.lootMore > 0 then out[#out + 1] = note(T("more", int(d.lootMore))) end
  end

  -- quests turned in or accepted inside
  if #d.quests > 0 or d.questMore > 0 then
    out[#out + 1] = head(T.secQuests)
    for _, q in ipairs(d.quests) do
      local right = q.done and T.questDone or T.questTaken
      local Tx = Journal.Texts
      if q.done and (q.money or 0) > 0 then right = right .. " · " .. Tx.money(q.money, "compact", 12) end
      local it = line(disp(q.title, 60) or T("questFallback", format("%.0f", q.id)), right)
      local tip = { disp(q.title, 60) or T("questFallback", format("%.0f", q.id)), q.done and T.questDone or T.questTaken }
      if q.done and (q.xp or 0) > 0 then tip[#tip + 1] = T("xpUnit", int(q.xp)) end
      if q.done and (q.money or 0) > 0 then tip[#tip + 1] = T("reward", Tx.money(q.money, "plain")) end
      it.tip = tip
      out[#out + 1] = it
    end
    if d.questMore > 0 then out[#out + 1] = note(T("more", int(d.questMore))) end
  end
  return out
end

-- class symbols (circle icons when the client has them, else a colour chip) ---------------------------------------------

local ICON_TEX = "Interface\\TargetingFrame\\UI-Classes-Circles"

local function paintIcon(t, class)
  local coords = type(CLASS_ICON_TCOORDS) == "table" and class and CLASS_ICON_TCOORDS[class] or nil
  if type(coords) == "table" and type(coords[1]) == "number" and type(coords[4]) == "number" then
    t:SetTexture(ICON_TEX)
    t:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    t:SetVertexColor(1, 1, 1, 1)
  else
    t:SetTexCoord(0, 1, 0, 1)
    t:SetColorTexture(unpack(Mates.classColor(class)))
  end
  t:Show()
end

-- left list ---------------------------------------------------------------------------------------------------------------

function View:RunTip(run)
  local index = self.index
  local lines, colors = { View.runName(run) }, {}
  lines[#lines + 1] = whenText(index, run)
  lines[#lines + 1] = View.infoText(run)
  lines[#lines + 1] = View.deathText(run)
  local group = Dungeons.group(index, run)
  if #group > 0 then
    lines[#lines + 1] = T.groupTip .. ":"
    for i = 1, min(#group, View.TIP_PEOPLE) do
      lines[#lines + 1] = mateText(group[i].name) .. " · " .. personKind(group[i])
      colors[#lines] = Mates.classColor(group[i].class)
    end
    if #group > View.TIP_PEOPLE then lines[#lines + 1] = T("more", int(#group - View.TIP_PEOPLE)) end
  end
  return lines, colors
end

local function buildRow(self, row)
  local nm = font(row, "title", SZ.m, "ink", "LEFT")
  nm:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
  nm:SetWidth(BODY_W - 120)
  nm:SetWordWrap(false)
  local dt = font(row, "label", SZ.s, "sepia", "RIGHT")
  dt:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
  dt:SetWidth(110)
  local info = font(row, "label", SZ.s, "sepia", "LEFT")
  info:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -23)
  info:SetWidth(BODY_W - 16)
  info:SetWordWrap(false)
  local dth = font(row, "label", SZ.s, "ink", "LEFT")
  dth:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -37)
  dth:SetWidth(BODY_W - 16 - View.ICONS * 17 - 40)
  dth:SetWordWrap(false)
  local icons = {}
  for i = 1, View.ICONS do
    local t = row:CreateTexture(nil, "ARTWORK")
    t:SetSize(14, 14)
    t:SetPoint("TOPRIGHT", row, "TOPRIGHT", -18 - (View.ICONS - i) * 17, -36)
    t:Hide()
    icons[i] = t
  end
  local more = font(row, "label", SZ.xs, "sepia", "RIGHT")
  more:SetPoint("TOPRIGHT", row, "TOPRIGHT", -18 - View.ICONS * 17 + 12, -38)
  row.label:SetText("")
  row.name, row.date, row.info, row.deaths, row.icons, row.more = nm, dt, info, dth, icons, more
  -- own hover scripts before RowStyle (RowStyle hooks in behind them)
  row:SetScript("OnEnter", function(r)
    if r.run then
      local lines, colors = self:RunTip(r.run)
      W.tip(r, lines, colors)
    end
  end)
  row:SetScript("OnLeave", function(r) W.hideTip(r) end)
  D.RowStyle(row, { texts = { info, dth } })
end

local function buildDetailRow(row)
  local k = font(row, "label", SZ.s, "sepia", "LEFT")
  k:SetPoint("LEFT", row, "LEFT", 2, 0)
  k:SetWidth(110)
  local v = font(row, "title", SZ.m, "ink", "RIGHT")
  v:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  v:SetWidth(SR.w - 130)
  v:SetWordWrap(false)
  local l = font(row, "title", SZ.m, "ink", "LEFT")
  l:SetPoint("LEFT", row, "LEFT", 2, 0)
  l:SetWidth(205)
  l:SetWordWrap(false)
  local r = font(row, "label", SZ.s, "sepia", "RIGHT")
  r:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  r:SetWidth(175)
  r:SetWordWrap(false)
  -- find with group data: [item] [recipient in class colour] [small roll word] [time in r]
  local x = font(row, "label", SZ.xs, "sepia", "RIGHT")
  x:SetPoint("RIGHT", row, "RIGHT", -48, 0)
  x:SetWidth(60)
  x:SetWordWrap(false)
  local w = font(row, "label", SZ.s, "ink", "RIGHT")
  w:SetPoint("RIGHT", row, "RIGHT", -48, 0)
  w:SetWidth(100)
  w:SetWordWrap(false)
  local n = font(row, "label", SZ.s, "sepia", "LEFT")
  n:SetPoint("LEFT", row, "LEFT", 2, 0)
  n:SetWidth(SR.w - 20)
  n:SetWordWrap(false)
  local h = D.font(row, "hand", 18, "red")
  h:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 3)
  h:SetWidth(SR.w - 20)
  h:SetJustifyH("LEFT")
  h:SetWordWrap(false)
  local rule = W.NewRect(row, "red", 0.35, "ARTWORK")
  rule:SetHeight(1)
  rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  rule:Hide()
  row.label:SetText("")
  row.k, row.v, row.l, row.r, row.w, row.x, row.n, row.h, row.rule = k, v, l, r, w, x, n, h, rule
  row:SetScript("OnEnter", function(x)
    local it = x.item
    if it and it.tip then W.tip(x, it.tip, it.tipColors) end
  end)
  row:SetScript("OnLeave", function(x) W.hideTip(x) end)
end

function View.new(page, left, right)
  local self = setmetatable({ page = page }, View)
  local l, r = CreateFrame("Frame", nil, left), CreateFrame("Frame", nil, right)
  l:SetAllPoints(left)
  r:SetAllPoints(right)
  self.l, self.r = l, r
  -- finds without a stored name: name from the client, loaded later and the card redrawn once (Live.itemNames)
  if Journal.Live and Journal.Live.itemNames then
    self.names = Journal.Live.itemNames(r, function() if self.open then self:RenderCard(false) end end, 48)
  end
  W.NewPageHead(l, { side = "L" }):SetTexts(T.brand, T.page)
  W.NewPageHead(r, { side = "R" }):SetTexts("", T.page)
  -- no Esc catcher: "Durchläufe" is the first sub-bookmark of the tab Dungeons (I12), so Esc closes the book there
  local headL = D.NewSectionHead(l, T.title, { size = SZ.xl })
  headL:SetPoint("TOPLEFT", l, "TOPLEFT", IN_X, -(TITLE_Y - 6))
  self.count = font(l, "label", SZ.s, "sepia", "LEFT")
  self.count:SetPoint("TOPLEFT", l, "TOPLEFT", IN_X, -SUB_Y)
  local cy = -(G.slots.ctrl.y + G.slots.ctrl.h / 2)
  self.nav = D.NewNavPair(l, { onPrev = function() self:Page(-1) end, onNext = function() self:Page(1) end,
    tipPrev = { T.prevTip }, tipNext = { T.nextTip } })
  self.nav.frame:SetPoint("RIGHT", l, "TOPLEFT", SL.x + SL.w + 4, cy)
  self.pos = font(l, "label", SZ.s, "sepia", "RIGHT")
  self.pos:SetPoint("RIGHT", self.nav.frame, "LEFT", -6, 0)
  self.list = W.NewList(l, { rows = View.ROWS, rowHeight = View.ROW_H, width = BODY_W, empty = T.empty, emptyHand = true,
    build = function(row) buildRow(self, row) end,
    clear = function(row)
      row.run = nil
      for _, k in ipairs({ "name", "date", "info", "deaths", "more" }) do set(row[k], "") end
      for _, t in ipairs(row.icons) do t:Hide() end
      if row.SetSelected then row:SetSelected(false) end
      W.hideTip(row)
    end,
    fill = function(row, run)
      row.run = run
      set(row.name, View.runName(run))
      set(row.date, dateText(self.index, run.t0))
      set(row.info, View.infoText(run))
      W.fitLine(row.info, BODY_W - 16)
      set(row.deaths, View.deathText(run))
      local group = Dungeons.group(self.index, run)
      for i, t in ipairs(row.icons) do
        if group[i] then paintIcon(t, group[i].class) else t:Hide() end
      end
      set(row.more, #group > View.ICONS and ("+" .. int(#group - View.ICONS)) or "")
      if row.SetSelected then row:SetSelected(self.sel ~= nil and self.sel == run.key) end
      D.rowFilled(row)
    end,
    onClick = function(run) self:Select(run) end })
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

  -- right page: title and sub title on the grid, the run as a scrolling list of lines (mouse wheel, bar)
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
  u.sub = font(r, "text", SZ.s, "sepia", "LEFT")
  u.sub:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -SUB_Y)
  u.sub:SetWidth(SR.w)
  u.sub:SetWordWrap(false)
  u.hint = D.emptyNote(r, SR.w - 40)
  u.hint:SetPoint("TOP", r, "TOPLEFT", SR.x + SR.w / 2, -(G.slots.body.y + 40))
  u.detail = W.NewList(r, { rows = View.DETAIL_ROWS, rowHeight = View.DETAIL_H, width = SR.w, empty = "", step = 3,
    build = buildDetailRow,
    clear = function(row)
      row.item = nil
      for _, k in ipairs({ "k", "v", "l", "r", "w", "x", "n", "h" }) do set(row[k], "") end
      row.rule:Hide()
      W.hideTip(row)
    end,
    fill = function(row, it)
      row.item = it
      if it.kind == "kv" then
        set(row.k, it.k)
        set(row.v, it.v)
      elseif it.kind == "head" then
        set(row.h, it.text)
        row.rule:Show()
      elseif it.kind == "note" then
        set(row.n, it.text)
      else
        row.l:SetTextColor(unpack(it.color or { W.color("ink") }))
        set(row.l, it.left)
        set(row.r, it.right)
        if it.who then
          local hasRoll = it.roll ~= nil and it.roll ~= ""
          row.w:ClearAllPoints()
          row.w:SetPoint("RIGHT", row, "RIGHT", hasRoll and -112 or -48, 0)
          row.w:SetTextColor(unpack(it.whoColor or { W.color("ink") }))
          set(row.w, it.who)
          set(row.x, hasRoll and it.roll or "")
        end
      end
    end })
  u.detail.frame:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -G.slots.ctrl.y)
  self.card = u
  l:Hide()
  r:Hide()
  return self
end

function View:IsOpen() return self.open == true end

function View:Page(delta)
  local list = self.list
  if not list then return end
  list:SetOffset(list:GetOffset() + (tonumber(delta) or 0) * View.ROWS)
end

function View:UpdatePager()
  local list = self.list
  if not (list and self.nav) then return end
  local n = #(list.items or {})
  local pages = max(1, math.ceil(n / View.ROWS))
  local off = list:GetOffset()
  local p = (off >= list:MaxOffset()) and pages or min(pages, floor(off / View.ROWS) + 1)
  self.nav:SetEnabled(off > 0, off < list:MaxOffset())
  self.nav.frame:SetShown(pages > 1)
  set(self.pos, pages > 1 and T("pageOf", int(p), int(pages)) or "")
end

function View:Select(run)
  self.sel = run and run.key or nil
  self.list:Refresh()
  self:RenderCard(true)
end

function View:Chosen()
  for _, run in ipairs(self.runs or {}) do
    if run.key == self.sel then return run end
  end
  return nil
end

function View:RenderCard(reset)
  local u = self.card
  local run = self:Chosen()
  if not run then
    set(u.name, "")
    u.nameHover.full = nil
    u.nameHover:EnableMouse(false)
    set(u.sub, "")
    u.detail.frame:Hide()
    u.detail:SetItems({})
    set(u.hint, (#(self.runs or {}) == 0) and T.emptyBody or T.pick)
    return
  end
  set(u.hint, "")
  u.detail.frame:Show()
  local name = View.runName(run)
  set(u.name, name)
  local size = W.fitLine(u.name, SR.w - 30, 18)
  local cut = size and (size < (u.name.fitBase or size) or (tonumber(u.name:GetStringWidth()) or 0) > SR.w - 30)
  u.nameHover.full = cut and name or nil
  u.nameHover:EnableMouse(cut and true or false)
  local parts = {}
  local diff = Dungeons.difficultyName(run.difficultyID)
  if diff then parts[#parts + 1] = disp(diff, 40) end
  parts[#parts + 1] = dateText(self.index, run.t0)
  if not run.endKnown and not run.live then parts[#parts + 1] = T.endUnknown end
  set(u.sub, table.concat(parts, " · "))
  u.detail:SetItems(self:Items(run))
  if reset then u.detail:SetOffset(0) end
  u.detail:Refresh()
end

function View:Render()
  local res = self.res
  self.runs = res and res.runs or {}
  local n = #self.runs
  set(self.count, n == 0 and "" or count(n, "runs"))
  set(self.note, (res and res.truncated) and T.truncated or "")
  local found = false
  for _, run in ipairs(self.runs) do if run.key == self.sel then found = true end end
  if not found then self.sel = n > 0 and self.runs[1].key or nil end
  self.list:SetItems(self.runs)
  self.list:Refresh()
  self:RenderCard(not found)
end

function View:Load(index, now)
  self.index, self.now = index, now
  self.res = Dungeons.build(index, { now = now })
end

function View:Open(index, now)
  self.open = true
  self:Load(index, now)
  self.l:Show()
  self.r:Show()
  self.list:SetOffset(0)
  self:Render()
end

function View:Refresh(index, now)
  if not self.open then return end
  self:Load(index, now)
  self:Render()
end

function View:Close()
  self.open = false
  if self.names then self.names.stop() end
  self.l:Hide()
  self.r:Hide()
  for _, row in ipairs(self.list.rows) do W.hideTip(row) end
  for _, row in ipairs(self.card.detail.rows) do W.hideTip(row) end
  W.hideTip(self.nav.prev)
  W.hideTip(self.nav.next)
end
