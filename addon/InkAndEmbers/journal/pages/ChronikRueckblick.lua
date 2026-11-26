-- Chronik sub-view "Zuvor auf Eurer Reise" (the recap after a long break), WITHOUT a bookmark of its own: it opens from the button
-- on the profile page (pages/Chronik.lua Page.OpenRecap), from the note "Lange nicht gesehen ..." / the welcome note (click),
-- by itself after a break of three days (journal/Begleiter.lua) and with /chronik rueckblick; Esc leads back to the profile.
-- Data: journal/model/Recap.lua (Journal.Recap.get / last): finished, sanitized texts; this file only decides how they look.
-- Left page: title, sub line (days, sessions), the narrated paragraphs as printed text (the best find inside as a coloured item
-- link with the game tooltip), "Am Rande" (a real side note in red handwriting, only when the model has one), at the foot the
-- picture of the last session as a "polaroid": the uncovered zone map like the journey map (same art and "Karte aufdecken"), the
-- route in red ink, start and end mark, small marks at the turn-ins, handwritten caption. Without an uncovered zone map: no picture.
-- Right page: "Wo Ihr steht" (one compact line), "Zuletzt erledigt" (the last three turn-ins, each with two or three sentences of
-- its quest text, the full text on hover) and "Was offen ist" (pin, progress, the rest of the log, each with its goal line; to-dos
-- and work order only with their module). The text takes the largest font size at which everything fits; what is shortened has its
-- full text on hover. Foreign text only via Sanitize.display. No ticker, no OnUpdate; frames are built on first open.
local _, ns = ...

local Journal = ns.Journal
local W, Pages = Journal and Journal.Widgets, Journal and Journal.Pages
local D = W and W.Diary
if not (W and Pages and D) then return end

local floor, max, min = math.floor, math.max, math.min
local format = string.format -- date parts

-- grid as in pages/ChronikMeilensteine.lua (docs/raster.md)
local Theme = Journal.Theme
local G = Theme.GRID
local SZ = G.size
local SL, SR = {}, {}
SL.x, SL.w = Theme.gridX("L")
SR.x, SR.w = Theme.gridX("R")
local IN_X = Theme.gridX("L", 2) + 4
local TITLE_Y = G.slots.title.y - 4
local SUB_Y = G.slots.title.y + 34

local View = {}
View.__index = View
Journal.RecapView = View

View.TEXT = ns.Locale.ns("p.ChronikRueckblick", {
  page = "RÜCKBLICK", brand = "INK & EMBERS", title = "Zuvor auf Eurer Reise",
  date = "{d}.{m}.{y}", dateRange = "{from} – {to}", preview = "Vorschau",
  sessions_one = "%s Sitzung", sessions_other = "%s Sitzungen",
  standHead = "Wo Ihr steht", openHead = "Was offen ist", noteHead = "Am Rande", doneHead = "Zuletzt erledigt",
  standNone = "Noch nichts festgehalten.", openNone = "Gerade steht nichts offen.",
  pin = "Angepinnt: %s", progress = "%s (%s von %s)", quoted = "„%s“", bestLine = "Bester Fund: %s",
  moreTip = "Alles, was offen ist", clickTip = "Klicken: im Questlog zeigen",
  questCombat = "Im Kampf öffnet sich das Questlog nicht. Versuch es danach noch einmal.",
  questFailed = "Das Questlog lässt sich gerade nicht öffnen.",
  picCaption = "%s", picCaptionDate = "%s · %s", picTipHead = "Die letzte Route", picTipRange = "%s bis %s",
  picTipQuests_one = "%s Quest abgegeben", picTipQuests_other = "%s Quests abgegeben",
  picTipAccepts_one = "%s Quest angenommen", picTipAccepts_other = "%s Quests angenommen",
  openHere = "Hier in der Gegend", openAway = "Anderswo",
  building = "Die Chronik sortiert noch. Gleich noch einmal ansehen.",
  empty = "Für einen Rückblick ist noch zu wenig geschehen.",
  notReady = "Der Rückblick steht noch nicht bereit.",
})
local T = View.TEXT

-- measures (px): the polaroid sits at the foot of the left page; the printed text takes the room above it
View.TEXT_Y = G.slots.ctrl.y                -- story below the title and the sub line
View.RIGHT_Y = G.slots.title.y + 38         -- first printed block of the right page (below its section head)
View.BODY_BOTTOM = G.slots.body.bottom
View.TEXT_SIZES = { 14, 13, 12 }            -- printed text: font sizes tried from the largest
View.NOTE_SIZE = 17                         -- remarks in red handwriting
View.GOAL_SIZE = SZ.s                       -- goal line below an open quest
View.SUB_SIZE, View.SUB_H = 18, 30          -- sub heads of "Was offen ist" (handwriting) and their height
View.GAP = 16                               -- between two blocks
View.ROW_GAP = 6                            -- between two quests of a block
View.HEAD_H = 38                            -- section head (size 22) and the distance to its text
View.PARA_GAP = 4                           -- extra line spacing in the text
View.BEST_H = 22                            -- the line "Bester Fund: ..." (only when the find is not inside the paragraph)
View.ROW_GAP_MIN = 2                        -- tighter gap when the right page is full (quest texts are never cut)
View.DONE_ROWS, View.OPEN_ROWS = 3, 9  -- open: up to 6 quests (Recap.OPEN_MAX) plus the sub heads
View.POLA = { w = 300, pad = 12, mapH = 150, capH = 40, gap = 14 }
View.POLA.h = View.POLA.pad + View.POLA.mapH + View.POLA.capH
View.MIN_SPAN = 0.16                        -- narrowest map section (share of the map width): short walks do not zoom to dust
View.MARGIN = 1.5                           -- the route fills about 2/3 of the section
View.LINE_W = 2.2                           -- route line width (px)
View.MARK_SIZE = 7                          -- turn-in mark (px)
View.NAME_MAX = 64                          -- bytes of a zone / quest name kept
View.TEXT_MAX = 900                         -- bytes of one narrated paragraph
View.LINE_MAX = 200                         -- bytes of one printed line
View.DONE_MAX = 320                         -- bytes of a quest text on the page
View.TIP_MAX = 400                          -- bytes of one tooltip paragraph
View.TILES_MAX, View.OVERLAYS_MAX, View.LINES_MAX, View.MARKS_MAX = 64, 200, 160, 12

local function disp(v, n)
  local S = ns.Sanitize
  return S and S.display(v, n) or nil
end

local function num(v)
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  if type(issecretvalue) == "function" and issecretvalue(v) == true then return nil end
  return v
end

local function int(n) return Journal.Texts.int(n) end
local function set(fs, text) W.setText(fs, text) end

local function font(parent, kind, size, color, justify)
  local fs = W.font(parent, kind, size, color)
  if justify then fs:SetJustifyH(justify) end
  return fs
end

local function setSize(fs, size)
  local file, _, flags = fs:GetFont()
  if file then fs:SetFont(file, size, flags or "") end
end

local function height(fs) return tonumber(fs:GetStringHeight()) or 0 end

local function wrap(fs, width)
  fs:SetWidth(width)
  fs:SetJustifyV("TOP")
  fs:SetJustifyH("LEFT")
  if fs.SetWordWrap then fs:SetWordWrap(true) end
  if fs.SetMaxLines then fs:SetMaxLines(0) end
end

local function dateText(index, t)
  local I = Journal.Index
  if not (I and type(I.dateOf) == "function") or not num(t) then return nil end
  local d, m, y = I.dateOf(index, t)
  if not d then return nil end
  return T("date", { d = format("%02d", d), m = format("%02d", m), y = format("%04d", y) })
end

-- display lines of a multi-paragraph text (tooltip): each paragraph sanitized on its own
local function tipParas(text)
  local out = {}
  if type(text) ~= "string" then return out end
  for para in string.gmatch(text .. "\n\n", "(.-)\n\n") do
    local t = disp(para, View.TIP_MAX)
    if t then out[#out + 1] = t end
  end
  return out
end

-- texts of the page ---------------------------------------------------------------------------------------------------------

-- a line of a model list: a string, or a table with text / title / label
local function lineOf(v)
  if type(v) == "table" then v = v.text or v.title or v.label end
  return disp(v, View.LINE_MAX)
end

-- sub line: "2.11.2026 – 9.11.2026 · 3 Sitzungen" (+ " · Vorschau")
function View.subText(index, recap, preview)
  local parts = {}
  local from, to = dateText(index, recap.from), dateText(index, recap.to)
  if from and to then
    parts[#parts + 1] = from == to and from or T("dateRange", { from = from, to = to })
  elseif from or to then
    parts[#parts + 1] = from or to
  end
  local n = num(recap.sessions)
  if n and n >= 1 then parts[#parts + 1] = T(ns.Locale.plural(floor(n), "sessions_one", "sessions_other"), int(floor(n))) end
  if preview then parts[#parts + 1] = T.preview end
  return table.concat(parts, " · ")
end

-- the best find of the model: { name, link, quality } | nil
function View.bestItem(recap)
  local facts = type(recap.facts) == "table" and recap.facts or {}
  for _, h in ipairs(type(facts.highlights) == "table" and facts.highlights or {}) do
    if type(h) == "table" and h.kind == "best" and (h.name or h.text) then
      return { name = h.name or h.text, link = h.link, key = h.key, itemID = h.itemID, quality = h.quality }
    end
  end
  return nil
end

-- the narrated paragraphs, one blank line between them; the best find becomes a coloured link when its name is in the text.
-- -> text, linked (true: the find stands inside as a link); plainOnly: no link in the text (the find then gets its own line)
function View.storyText(recap, plainOnly)
  local out = {}
  for _, p in ipairs(type(recap.story) == "table" and recap.story or {}) do
    local t = disp(p, View.TEXT_MAX)
    if t then out[#out + 1] = t end
  end
  local best = View.bestItem(recap)
  local linked = false
  if best and not plainOnly then
    for i, t in ipairs(out) do
      local s, ok = W.linkItem(t, best.name, best.link or best.key or best.itemID, best.quality)
      if ok then
        out[i], linked = s, true
        break
      end
    end
  end
  return table.concat(out, "\n\n"), linked
end

-- "Wo Ihr steht": the stand lines in one compact text ("Stufe 34, 62 % zur nächsten · Ort: Alteracgebirge · ...")
function View.standText(recap)
  local out = {}
  local stand = type(recap.stand) == "table" and recap.stand or {}
  for _, l in ipairs(type(stand.lines) == "table" and stand.lines or {}) do
    local t = lineOf(l)
    if t then out[#out + 1] = t end
  end
  return table.concat(out, " · ")
end

-- "Was offen ist": rows { title, goal|nil, tip } from open.list (pin, progress, the rest of the log), else from pin/progress (an
-- older model); then the plain lines of to-dos, work order and trainer
function View.openRows(recap)
  local rows, lines = {}, {}
  local open = type(recap.open) == "table" and recap.open or {}
  local list = type(open.list) == "table" and open.list or nil
  if list and #list > 0 then
    -- pin on top; then "Hier in der Gegend" and "Anderswo" (with the zone of each quest), each with a small sub head
    local group
    for _, q in ipairs(list) do
      local title = type(q) == "table" and disp(q.title, View.NAME_MAX) or nil
      if title and #rows < View.OPEN_ROWS then
        local g = q.group
        if (g == "here" or g == "away") and g ~= group then
          rows[#rows + 1] = { sub = true, title = g == "here" and T.openHere or T.openAway }
        end
        group = g
        local goal = disp(q.goal, View.LINE_MAX)
        local zone = g == "away" and disp(q.zone, View.NAME_MAX) or nil
        -- symbol before the name: pin, yellow "?" (ready to turn in), yellow "!" (open)
        local icon = q.kind == "pin" and "pin" or ((q.ready == true or q.goal == View.readyText()) and "ready" or "quest")
        rows[#rows + 1] = { title = title, goal = goal, zone = zone, icon = icon, questID = num(q.questID) }
      end
    end
  else
    local pin = type(open.pin) == "table" and disp(open.pin.title, View.NAME_MAX) or nil
    if pin then rows[#rows + 1] = { title = T("pin", pin), icon = "pin" } end
    for _, q in ipairs(type(open.progress) == "table" and open.progress or {}) do
      local title = type(q) == "table" and disp(q.title, View.NAME_MAX) or nil
      local have, need = type(q) == "table" and num(q.have), type(q) == "table" and num(q.need)
      if title and #rows < View.OPEN_ROWS then
        if have and need and need > 0 then
          rows[#rows + 1] = { title = T("progress", title, int(floor(have)), int(floor(need))) }
        else
          rows[#rows + 1] = { title = title }
        end
      end
    end
  end
  for _, todo in ipairs(type(open.todos) == "table" and open.todos or {}) do
    local t = lineOf(todo)
    if t then lines[#lines + 1] = t end
  end
  for _, key in ipairs({ "werk", "trainer" }) do
    local t = lineOf(open[key])
    if t then lines[#lines + 1] = t end
  end
  return rows, lines
end

-- the whole "Was offen ist" as plain lines (tooltip, tests)
function View.openText(recap)
  local rows, lines = View.openRows(recap)
  local out = {}
  for _, r in ipairs(rows) do
    out[#out + 1] = r.goal and (r.title .. " – " .. r.goal) or r.title
  end
  for _, l in ipairs(lines) do out[#out + 1] = l end
  return table.concat(out, "\n")
end

-- "Zuletzt erledigt": rows { title = "„Name“", body|nil, tip = { title, paragraphs ... } }
function View.doneRows(recap)
  local out = {}
  for _, d in ipairs(type(recap.done) == "table" and recap.done or {}) do
    local name = type(d) == "table" and disp(d.title, View.NAME_MAX) or nil
    if name and #out < View.DONE_ROWS then
      local title = T("quoted", name)
      local tip = { title }
      for _, p in ipairs(tipParas(d.full)) do tip[#tip + 1] = p end
      if #tip == 1 and d.text then tip[2] = disp(d.text, View.TIP_MAX) end
      out[#out + 1] = { title = title, body = disp(d.text, View.DONE_MAX), tip = tip }
    end
  end
  return out
end

-- "Am Rande": the model's side notes (never the highlights of the paragraph again)
function View.notes(recap)
  local out = {}
  for _, a in ipairs(type(recap.aside) == "table" and recap.aside or {}) do
    local t = lineOf(a)
    if t and #out < 2 then out[#out + 1] = t end
  end
  return out
end

-- the picture: points inside a section of the zone map; nil without route points or art. -> view window in art pixels
-- { x, y, w, h (art px), s (box px per art px) }
function View.window(art, points, boxW, boxH)
  if type(art) ~= "table" or not num(art.w) or not num(art.h) or art.w <= 0 or art.h <= 0 then return nil end
  local x0, y0, x1, y1
  for _, p in ipairs(type(points) == "table" and points or {}) do
    local x, y = type(p) == "table" and num(p.x), type(p) == "table" and num(p.y)
    if x and y then
      x, y = max(0, min(1, x)), max(0, min(1, y))
      x0, y0 = min(x0 or x, x), min(y0 or y, y)
      x1, y1 = max(x1 or x, x), max(y1 or y, y)
    end
  end
  if not x0 then return nil end
  local aspect = boxW / boxH
  local bw, bh = (x1 - x0) * art.w, (y1 - y0) * art.h
  local w = max(bw * View.MARGIN, bh * View.MARGIN * aspect, View.MIN_SPAN * art.w)
  local h = w / aspect
  if w > art.w then w, h = art.w, art.w / aspect end
  if h > art.h then h, w = art.h, art.h * aspect end
  local cx, cy = (x0 + x1) / 2 * art.w, (y0 + y1) / 2 * art.h
  local wx, wy = max(0, min(art.w - w, cx - w / 2)), max(0, min(art.h - h, cy - h / 2))
  return { x = wx, y = wy, w = w, h = h, s = boxW / w }
end

-- the uncovered zone map like the journey map (View.zoneArt with "Karte aufdecken"): only a ZONE (map type 3 when the client
-- knows it), only with art and at least one uncovered piece (explored or revealed); else nil (no picture, never bare tiles)
function View.zoneArt(mapID)
  local V = Journal.View
  if not (V and V.zoneArt) or not num(mapID) then return nil end
  local info = ns.Zone and type(ns.Zone.info) == "function" and ns.Zone.info(mapID) or nil
  if type(info) == "table" and num(info.mapType) and info.mapType ~= 3 then return nil end
  local reveal = V.peek and V.peek("revealMap") == true or false
  local ok, a = pcall(V.zoneArt, mapID, reveal)
  if not ok or type(a) ~= "table" or not num(a.w) or not num(a.h) or a.w <= 0 or a.h <= 0 then return nil end
  if type(a.overlays) ~= "table" or #a.overlays == 0 then return nil end
  return a
end

-- frames ----------------------------------------------------------------------------------------------------------------------

-- polaroid: shadow, paper, the map section (clipped box with own pools of tiles, uncovered pieces, route lines and marks), tape,
-- handwritten caption
local function buildPicture(self, l)
  local P = View.POLA
  local f = CreateFrame("Frame", nil, l)
  f:SetSize(P.w, P.h)
  f:SetPoint("TOPLEFT", l, "TOPLEFT", SL.x + floor((SL.w - P.w) / 2), -(View.BODY_BOTTOM - P.h))
  f:EnableMouse(true)
  local shadow = W.NewRect(f, "ink", 0.16, "BACKGROUND")
  shadow:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
  shadow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
  local paper = W.NewRect(f, "card", 1, "BACKGROUND")
  paper:SetAllPoints(f)
  local edge = W.NewOutline(f, P.w, P.h, "sepia", 0.45)
  edge:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  local box = CreateFrame("Frame", nil, f)
  box:SetSize(P.w - 2 * P.pad, P.mapH)
  box:SetPoint("TOPLEFT", f, "TOPLEFT", P.pad, -P.pad)
  if box.SetClipsChildren then box:SetClipsChildren(true) end
  local ground = W.NewRect(box, "faint", 0.5, "BACKGROUND")
  ground:SetAllPoints(box)
  local frame = W.NewOutline(f, P.w - 2 * P.pad, P.mapH, "ink", 0.55)
  frame:SetPoint("TOPLEFT", f, "TOPLEFT", P.pad, -P.pad)
  local pic = { frame = f, box = box, w = P.w - 2 * P.pad, h = P.mapH }
  pic.tiles = W.Pool(function()
    local t = box:CreateTexture(nil, "BACKGROUND", nil, 1)
    if t.SetDesaturated then t:SetDesaturated(true) end
    return t
  end, nil, View.TILES_MAX)
  pic.overlays = W.Pool(function() return box:CreateTexture(nil, "BACKGROUND", nil, 2) end, nil, View.OVERLAYS_MAX)
  pic.lines = W.Pool(function()
    return box.CreateLine and box:CreateLine(nil, "ARTWORK", nil, 2) or box:CreateTexture(nil, "ARTWORK", nil, 2)
  end, nil, View.LINES_MAX)
  pic.quests = W.Pool(function()
    local m = box:CreateTexture(nil, "ARTWORK", nil, 4)
    if Theme.TEX.disc then m:SetTexture(Theme.TEX.disc) end
    m:SetVertexColor(W.color("ink", 0.85))
    m:SetSize(View.MARK_SIZE, View.MARK_SIZE)
    return m
  end, nil, View.MARKS_MAX)
  pic.marks = {}
  for i, def in ipairs({ { "sepia", 8 }, { "red", 11 } }) do
    local m = box:CreateTexture(nil, "OVERLAY")
    if Theme.TEX.disc then m:SetTexture(Theme.TEX.disc) end
    m:SetVertexColor(W.color(def[1], 1))
    m:SetSize(def[2], def[2])
    m:Hide()
    pic.marks[i] = m
  end
  local tape = f:CreateTexture(nil, "OVERLAY", nil, 2)
  tape:SetSize(64, 18)
  tape:SetPoint("CENTER", f, "TOP", 0, 1)
  if Theme.TEX.diaryTape then tape:SetTexture(Theme.TEX.diaryTape) end
  tape:SetAlpha(0.9)
  pic.caption = D.font(f, "hand", 19, "red")
  pic.caption:SetPoint("TOPLEFT", f, "TOPLEFT", P.pad, -(P.pad + P.mapH + 6))
  pic.caption:SetWidth(P.w - 2 * P.pad)
  pic.caption:SetJustifyH("CENTER")
  pic.caption:SetWordWrap(false)
  f:SetScript("OnEnter", function(x) if x.tip then W.tip(x, x.tip) end end)
  f:SetScript("OnLeave", function(x) W.hideTip(x) end)
  f:Hide()
  self.pic = pic
end

-- a quest row (right page): title line, body below; the whole row shows its tooltip
-- quest symbols as in the quest log: the game's atlases (yellow "!" / "?", map pin), else the classic gossip textures
View.ICONS = {
  quest = { atlas = { "QuestNormal" }, file = "Interface\\GossipFrame\\AvailableQuestIcon" },
  ready = { atlas = { "QuestTurnin" }, file = "Interface\\GossipFrame\\ActiveQuestIcon" },
  pin = { atlas = { "Waypoint-MapPin-Untracked" } },
}
View.ICON_SIZE, View.ICON_W = 15, 19 -- symbol size, room it takes before the name
View.ZONE_W = 130                    -- room of the small zone name behind an "Anderswo" quest

function View.readyText()
  local RTx = Journal.RecapTexts
  return RTx and type(RTx.openReady) == "function" and RTx.openReady() or nil
end

local function hasAtlas(name)
  local CT = rawget(_G, "C_Texture")
  if type(CT) ~= "table" or type(CT.GetAtlasInfo) ~= "function" then return false end
  local ok, info = pcall(CT.GetAtlasInfo, name)
  return ok and type(info) == "table"
end

-- -> true if a symbol shows
function View.setIcon(tex, kind)
  local def = View.ICONS[kind]
  if not def then tex:Hide() return false end
  tex:SetVertexColor(1, 1, 1, 1)
  for _, a in ipairs(def.atlas or {}) do
    if hasAtlas(a) and tex.SetAtlas and tex:SetAtlas(a) ~= false then tex:Show() return true end
  end
  if def.file then
    tex:SetTexture(def.file)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:Show()
    return true
  end
  -- pin without the atlas: a small red dot
  if Theme.TEX.disc then
    tex:SetTexture(Theme.TEX.disc)
    tex:SetVertexColor(W.color("red", 1))
    tex:Show()
    return true
  end
  tex:Hide()
  return false
end

-- a click on an open quest: the game's quest log on this quest. With the Quest tracker module its tested action (combat and
-- controller mode checked, hint in the chat); else QuestMapFrame_OpenToQuestDetails out of combat. The book closes on success
-- (the quest log / world map takes the screen). -> ok, reason
function View.openQuest(questID)
  questID = num(questID)
  if not questID then return false, "noQuest" end
  local QT = Journal.QuestTrack
  local A = type(QT) == "table" and type(QT.actions) == "table" and QT.actions or nil
  local ok, reason
  if A and type(A.details) == "function" then
    local okC, r1, r2 = pcall(A.details, questID, {quiet = true})
    if okC then ok, reason = r1, r2 end
    if ok or (reason ~= "retail" and reason ~= "api" and reason ~= nil) then
      if ok then View.closeBook() end
      return ok == true, reason
    end
  end
  local function chat(msg) if ns.Core and ns.Core.print and msg then ns.Core.print(msg) end end
  if type(InCombatLockdown) == "function" then
    local okL, c = pcall(InCombatLockdown)
    if okL and c == true then chat(T.questCombat) return false, "combat" end
  end
  if A and type(A.controllerMode) == "function" then
    local okM, c = pcall(A.controllerMode)
    if okM and c == true then chat(T.questFailed) return false, "controller" end
  end
  local fn = rawget(_G, "QuestMapFrame_OpenToQuestDetails")
  if type(fn) == "function" and pcall(fn, questID) then
    View.closeBook()
    return true, "opened"
  end
  chat(T.questFailed)
  return false, "api"
end

function View.closeBook()
  local Acc = Journal.Access
  if Acc and type(Acc.close) == "function" then pcall(Acc.close) end
end

local function newRow(parent, kind)
  local row = CreateFrame("Frame", nil, parent)
  row:EnableMouse(true)
  local open = kind ~= "done"
  -- open quests: the name a little stronger (book title font), the goal line indented below it
  row.title = font(row, open and "title" or "text", SZ.m, "ink", "LEFT")
  row.body = font(row, kind == "done" and "text" or "label", kind == "done" and SZ.m or View.GOAL_SIZE, kind == "done" and "ink" or "sepia",
    "LEFT")
  wrap(row.title, SR.w - (open and View.ICON_W or 0))
  wrap(row.body, SR.w - (kind == "done" and 0 or (View.ICON_W + 8)))
  row.title:SetPoint("TOPLEFT", row, "TOPLEFT", open and View.ICON_W or 0, 0)
  if open then
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(View.ICON_SIZE, View.ICON_SIZE)
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.icon:Hide()
    row.zone = font(row, "label", SZ.xs, "sepia", "RIGHT")
    row.zone:SetWidth(View.ZONE_W)
    row.zone:SetWordWrap(false)
    row.zone:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
    -- sub head "Hier in der Gegend" / "Anderswo": red handwriting with an ink line like the other section heads, a size smaller
    row.head = D.NewSectionHead(row, "", { size = View.SUB_SIZE, width = SR.w })
    row.head:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.head:Hide()
    -- hover: soft highlight and hand cursor; click: the quest in the game's quest log (View.openQuest)
    row.hl = W.NewRect(row, "sepia", 0.12, "BACKGROUND")
    row.hl:SetPoint("TOPLEFT", row, "TOPLEFT", -4, 2)
    row.hl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 4, -2)
    row.hl:Hide()
    row:SetScript("OnMouseUp", function(x, button)
      if x.questID and (button == nil or button == "LeftButton") then View.openQuest(x.questID) end
    end)
  end
  row:SetScript("OnEnter", function(x)
    if x.tip then W.tip(x, x.tip) end
    if x.questID and x.hl then
      x.hl:Show()
      if type(SetCursor) == "function" then pcall(SetCursor, "INTERACT_CURSOR") end
    end
  end)
  row:SetScript("OnLeave", function(x)
    W.hideTip(x)
    if x.hl then x.hl:Hide() end
    if type(ResetCursor) == "function" then pcall(ResetCursor) end
  end)
  row:Hide()
  return row
end

function View.new(page, left, right)
  local self = setmetatable({ page = page }, View)
  local l, r = CreateFrame("Frame", nil, left), CreateFrame("Frame", nil, right)
  l:SetAllPoints(left)
  r:SetAllPoints(right)
  self.l, self.r = l, r
  W.NewPageHead(l, { side = "L" }):SetTexts(T.brand, T.page)
  W.NewPageHead(r, { side = "R" }):SetTexts("", T.page)
  D.escKeys(l, function() page:CloseSub() end) -- Esc -> profile
  -- left: title, sub line, the narrated paragraphs (in a frame with item links), the best find, "Am Rande", the polaroid
  local u = {}
  u.head = D.NewSectionHead(l, T.title, { size = SZ.xl, width = SL.w - (IN_X - SL.x) })
  u.head:SetPoint("TOPLEFT", l, "TOPLEFT", IN_X, -(TITLE_Y - 6))
  W.fitLine(u.head.text, SL.w - (IN_X - SL.x) - 12, 16) -- a longer title (other languages) shrinks instead of running off
  u.sub = font(l, "label", SZ.s, "sepia", "LEFT")
  u.sub:SetPoint("TOPLEFT", l, "TOPLEFT", IN_X, -SUB_Y)
  u.sub:SetWidth(SL.w - (IN_X - SL.x))
  u.sub:SetWordWrap(false)
  u.storyBox = CreateFrame("Frame", nil, l)
  u.storyBox:SetPoint("TOPLEFT", l, "TOPLEFT", SL.x, -View.TEXT_Y)
  u.storyBox:SetSize(SL.w, 20)
  W.enableItemLinks(u.storyBox) -- the best find in the paragraph: game tooltip on hover
  u.story = font(u.storyBox, "text", SZ.m, "ink", "LEFT")
  u.story:SetPoint("TOPLEFT", u.storyBox, "TOPLEFT", 0, 0)
  wrap(u.story, SL.w)
  if u.story.SetSpacing then u.story:SetSpacing(View.PARA_GAP) end
  u.storyHit = CreateFrame("Frame", nil, l)
  u.storyHit:EnableMouse(true)
  u.storyHit:SetScript("OnEnter", function(x) if x.full then W.tip(x, x.full) end end)
  u.storyHit:SetScript("OnLeave", function(x) W.hideTip(x) end)
  u.storyHit:Hide()
  u.best = W.NewItemLink(l, { width = SL.w, height = View.BEST_H - 4, size = SZ.m, prefix = T.bestLine })
  u.noteHead = D.NewSectionHead(l, T.noteHead, { width = SL.w })
  u.notes = D.font(l, "hand", View.NOTE_SIZE, "red")
  wrap(u.notes, SL.w)
  u.notes:SetSpacing(2)
  u.empty = D.emptyNote(l, SL.w - 40)
  u.empty:SetPoint("TOP", l, "TOPLEFT", SL.x + SL.w / 2, -(G.slots.body.y + 40))
  self.L = u
  buildPicture(self, l)
  -- right: "Wo Ihr steht", "Zuletzt erledigt", "Was offen ist"
  local v = {}
  v.standHead = D.NewSectionHead(r, T.standHead, { width = SR.w })
  v.standHead:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -(TITLE_Y - 6))
  v.stand = font(r, "text", SZ.m, "ink", "LEFT")
  wrap(v.stand, SR.w)
  v.stand:SetSpacing(View.PARA_GAP)
  v.doneHead = D.NewSectionHead(r, T.doneHead, { width = SR.w })
  v.done = {}
  for i = 1, View.DONE_ROWS do v.done[i] = newRow(r, "done") end
  v.openHead = D.NewSectionHead(r, T.openHead, { width = SR.w })
  v.openRows = {}
  for i = 1, View.OPEN_ROWS do v.openRows[i] = newRow(r, "open") end
  v.open = font(r, "text", SZ.m, "ink", "LEFT") -- to-dos, work order, trainer (and "nothing open")
  wrap(v.open, SR.w)
  v.open:SetSpacing(View.PARA_GAP)
  v.openHit = CreateFrame("Frame", nil, r)
  v.openHit:EnableMouse(true)
  v.openHit:SetScript("OnEnter", function(x) if x.full then W.tip(x, x.full) end end)
  v.openHit:SetScript("OnLeave", function(x) W.hideTip(x) end)
  v.openHit:Hide()
  self.R = v
  l:Hide()
  r:Hide()
  return self
end

function View:IsOpen() return self.open == true end

-- model -----------------------------------------------------------------------------------------------------------------------

-- the recap to show: the one handed over (the automatic opening, the click on the late note), else the last shown one, else a
-- fresh preview over the last session; want.preview: the fresh preview first. -> recap | nil, reason
function View:Pick(want)
  local R = Journal.Recap
  if type(want) == "table" and type(want.recap) == "table" then return want.recap, nil, false end
  if not (R and type(R.get) == "function") then return nil, "kein-modul" end
  local function call(fn, ...)
    if type(fn) ~= "function" then return nil, "kein-modul" end
    local ok, a, b = pcall(fn, ...)
    if not ok then
      if ns.Core and ns.Core.coreError then ns.Core.coreError(a) end
      return nil, "fehler"
    end
    return a, b
  end
  local preview = type(want) == "table" and want.preview == true
  if not preview then
    local last = call(R.last)
    if type(last) == "table" then return last, nil, false end
  end
  local recap, why = call(R.get, { preview = true })
  if type(recap) == "table" then return recap, nil, true end
  if preview then
    local last = call(R.last)
    if type(last) == "table" then return last, nil, false end
  end
  return nil, why
end

function View:Load(index, want)
  self.index = index
  local recap, why, preview = self:Pick(want)
  self.recap, self.why = recap, why
  self.isPreview = preview == true or (type(recap) == "table" and recap.preview == true)
  -- the index may still be building: look again when the model says it is ready (a few times at most: the core may answer at once)
  local R = Journal.Recap
  if not recap and (why == "baut" or why == "keine-daten") and not self.waiting and (self.readyTries or 0) < 3
      and R and type(R.onReady) == "function" then
    self.waiting = true
    self.readyTries = (self.readyTries or 0) + 1
    pcall(R.onReady, function()
      self.waiting = false
      if self.open and not self.recap then
        self:Load(self.index)
        self:Render()
      end
    end)
  end
end

-- drawing ---------------------------------------------------------------------------------------------------------------------

local function lineH(z, extra) return math.ceil(z * 1.2) + (extra or View.PARA_GAP) end

local function place(fs, parent, x, y)
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
end

local function drawTiles(pool, list, win, box, original, top)
  local Map = Journal.Map
  for _, t in ipairs(list) do
    if t.x1 > win.x and t.x0 < win.x + win.w and t.y1 > win.y and t.y0 < win.y + win.h then
      local tex = pool:Acquire()
      if not tex then break end
      if top and tex.SetDrawLayer then tex:SetDrawLayer("BACKGROUND", t.top and 3 or 2) end
      tex:SetTexture(t.file)
      tex:SetTexCoord(0, t.u1, 0, t.v1)
      if Map.tintTile then Map.tintTile(tex, original) end
      tex:SetSize((t.x1 - t.x0) * win.s, (t.y1 - t.y0) * win.s)
      tex:SetPoint("TOPLEFT", box, "TOPLEFT", (t.x0 - win.x) * win.s, -((t.y0 - win.y) * win.s))
    end
  end
end

function View:DrawPicture(recap) -- -> true if the polaroid shows
  local pic = self.pic
  pic.tiles:ReleaseAll()
  pic.overlays:ReleaseAll()
  pic.lines:ReleaseAll()
  pic.quests:ReleaseAll()
  for _, m in ipairs(pic.marks) do m:Hide() end
  pic.frame:Hide()
  pic.frame.tip = nil
  local pict = type(recap) == "table" and type(recap.picture) == "table" and recap.picture or nil
  if not pict or not num(pict.mapID) then return false end
  local Map = Journal.Map
  local art = View.zoneArt(pict.mapID)
  -- the section fits the route AND the quest places (like the journey map frames what happened there)
  local fitPts = {}
  for _, p in ipairs(type(pict.points) == "table" and pict.points or {}) do fitPts[#fitPts + 1] = p end
  for _, q in ipairs(type(pict.marks) == "table" and pict.marks or {}) do fitPts[#fitPts + 1] = q end
  local win = art and View.window(art, fitPts, pic.w, pic.h) or nil
  if not (win and Map and type(Map.tiles) == "function") then return false end
  local V = Journal.View
  local original = V and V.peek and V.peek("mapColor") == "original"
  drawTiles(pic.tiles, Map.tiles(art), win, pic.box, original)
  drawTiles(pic.overlays, art.overlays, win, pic.box, original, true)
  local function at(p) return (p.x * art.w - win.x) * win.s, (p.y * art.h - win.y) * win.s end
  local prev
  for _, p in ipairs(pict.points or {}) do
    if type(p) == "table" and p.brk then
      prev = nil
    elseif type(p) == "table" and num(p.x) and num(p.y) then
      local cur = { x = max(0, min(1, p.x)), y = max(0, min(1, p.y)) }
      if prev then
        local l = pic.lines:Acquire()
        if not l then break end
        local x1, y1 = at(prev)
        local x2, y2 = at(cur)
        if l.SetStartPoint then
          l:SetColorTexture(W.color("red", 0.95))
          l:SetThickness(View.LINE_W)
          l:SetStartPoint("TOPLEFT", pic.box, x1, -y1)
          l:SetEndPoint("TOPLEFT", pic.box, x2, -y2)
        end
      end
      prev = cur
    end
  end
  -- quest places: turn-ins as ink dots, accepts as smaller sepia dots (only inside the section)
  local quests, nTurn, nAcc = {}, 0, 0
  for _, q in ipairs(type(pict.marks) == "table" and pict.marks or {}) do
    if type(q) == "table" and num(q.x) and num(q.y) then
      local x, y = at({ x = max(0, min(1, q.x)), y = max(0, min(1, q.y)) })
      if x >= 0 and y >= 0 and x <= pic.w and y <= pic.h then
        local m = pic.quests:Acquire()
        if not m then break end
        local accept = q.kind == "accept"
        m:SetVertexColor(W.color(accept and "sepia" or "ink", accept and 0.9 or 0.85))
        m:SetSize(accept and View.MARK_SIZE - 2 or View.MARK_SIZE, accept and View.MARK_SIZE - 2 or View.MARK_SIZE)
        m:SetPoint("CENTER", pic.box, "TOPLEFT", x, -y)
        if accept then nAcc = nAcc + 1 else nTurn = nTurn + 1 end
        local title = disp(q.title, View.NAME_MAX)
        if title and #quests < 5 then quests[#quests + 1] = T("quoted", title) end
      end
    end
  end
  for i, key in ipairs({ "startPt", "endPt" }) do
    local p = pict[key]
    if type(p) == "table" and num(p.x) and num(p.y) then
      local x, y = at({ x = max(0, min(1, p.x)), y = max(0, min(1, p.y)) })
      pic.marks[i]:ClearAllPoints()
      pic.marks[i]:SetPoint("CENTER", pic.box, "TOPLEFT", x, -y)
      pic.marks[i]:Show()
    end
  end
  local zone = disp(pict.zoneName, View.NAME_MAX)
  local when = dateText(self.index, pict.t1 or pict.t0)
  set(pic.caption, zone and when and T("picCaptionDate", zone, when) or (zone and T("picCaption", zone)) or when or "")
  W.fitLine(pic.caption, pic.w, 12)
  local tip = { T.picTipHead }
  if zone then tip[#tip + 1] = zone end
  local t0, t1 = dateText(self.index, pict.t0), dateText(self.index, pict.t1)
  if t0 and t1 then tip[#tip + 1] = t0 == t1 and t0 or T("picTipRange", t0, t1) end
  if nTurn > 0 then tip[#tip + 1] = T(ns.Locale.plural(nTurn, "picTipQuests_one", "picTipQuests_other"), int(nTurn)) end
  if nAcc > 0 then tip[#tip + 1] = T(ns.Locale.plural(nAcc, "picTipAccepts_one", "picTipAccepts_other"), int(nAcc)) end
  for _, q in ipairs(quests) do tip[#tip + 1] = q end
  pic.frame.tip = tip
  pic.frame:Show()
  return true
end

-- left page: story (+ the find as its own line when it is not inside), "Am Rande" below, all above the polaroid
function View:DrawLeft(recap)
  local u = self.L
  local text, linked = "", false
  if recap then text, linked = View.storyText(recap) end
  set(u.sub, recap and View.subText(self.index, recap, self.isPreview) or "")
  local picture = self:DrawPicture(recap)
  u.storyHit:Hide()
  u.storyHit.full = nil
  u.best:Clear()
  u.noteHead:Hide()
  u.notes:Hide()
  set(u.notes, "")
  if not recap or text == "" then
    set(u.story, "")
    local why, msg = self.why, T.notReady
    if recap or why == "leer" then
      msg = T.empty
    elseif why == "baut" or why == "keine-daten" then
      msg = T.building
    end
    set(u.empty, msg)
    return
  end
  set(u.empty, "")
  local x, y0 = SL.x, View.TEXT_Y
  local bottom = picture and (View.BODY_BOTTOM - View.POLA.h - View.POLA.gap) or View.BODY_BOTTOM
  local best = (not linked) and recap and View.bestItem(recap) or nil
  local notes = View.notes(recap)
  local hb = (best and u.best:Set(best)) and View.BEST_H or 0
  set(u.story, text)
  set(u.notes, table.concat(notes, "\n"))
  local chosen, hs, hn
  if u.story.SetMaxLines then u.story:SetMaxLines(0) end
  local hNotes = #notes > 0 and (View.GAP + View.HEAD_H + height(u.notes)) or 0
  -- first everything (the text shrinks), then without the side note
  for _, withNotes in ipairs({ true, false }) do
    if not chosen and (withNotes == false or hNotes > 0) then
      for _, z in ipairs(View.TEXT_SIZES) do
        setSize(u.story, z)
        hs = height(u.story)
        hn = withNotes and hNotes or 0
        if y0 + hs + hb + hn <= bottom then
          chosen = z
          break
        end
      end
    end
  end
  if not chosen then
    -- smallest size, text limited to the room (full text on hover); no side note
    local z = View.TEXT_SIZES[#View.TEXT_SIZES]
    if linked then
      -- the hover frame over the clipped text would swallow the item tooltip: the find leaves the text and gets its own line
      best = View.bestItem(recap)
      set(u.story, (View.storyText(recap, true)))
      hb = (best and u.best:Set(best)) and View.BEST_H or 0
    end
    setSize(u.story, z)
    local room = max(lineH(z), bottom - y0 - hb)
    local lines = max(1, floor(room / lineH(z)))
    if u.story.SetMaxLines then u.story:SetMaxLines(lines) end
    hs, hn = lines * lineH(z), 0
    local full = {}
    for _, p in ipairs(type(recap.story) == "table" and recap.story or {}) do
      local t = disp(p, View.TEXT_MAX)
      if t then full[#full + 1] = t end
    end
    u.storyHit.full = full
    u.storyHit:ClearAllPoints()
    u.storyHit:SetPoint("TOPLEFT", self.l, "TOPLEFT", x, -y0)
    u.storyHit:SetSize(SL.w, hs)
    u.storyHit:Show()
  end
  u.storyBox:SetSize(SL.w, max(1, hs))
  local y = y0 + hs
  if hb > 0 then
    u.best.frame:ClearAllPoints()
    u.best.frame:SetPoint("TOPLEFT", self.l, "TOPLEFT", x, -(y + 4))
    y = y + hb
  else
    u.best:Clear()
  end
  if hn > 0 then
    u.noteHead:ClearAllPoints()
    u.noteHead:SetPoint("TOPLEFT", self.l, "TOPLEFT", x, -(y + View.GAP))
    place(u.notes, self.l, x, y + View.GAP + View.HEAD_H)
    u.noteHead:Show()
    u.notes:Show()
  end
end

-- right page: stand, the last turn-ins, what is open. Sizes from 14 down; at the smallest fewer open quests, tighter gaps, fewer
-- turn-ins (whole entries, a quest text is never cut); the to-do lines last (everything open stays in the tooltip of the open block)
function View:DrawRight(recap)
  local v = self.R
  v.openHit:Hide()
  v.openHit.full = nil
  for _, row in ipairs(v.done) do row:Hide() row.tip = nil end
  for _, row in ipairs(v.openRows) do row:Hide() row.tip = nil end
  if not recap then
    for _, k in ipairs({ "standHead", "stand", "doneHead", "openHead", "open" }) do v[k]:Hide() end
    return
  end
  for _, k in ipairs({ "standHead", "stand", "openHead", "open" }) do v[k]:Show() end
  local stand = View.standText(recap)
  if stand == "" then stand = T.standNone end
  local done = View.doneRows(recap)
  local rows, lines = View.openRows(recap)
  local extra = table.concat(lines, "\n")
  if #rows == 0 and extra == "" then extra = T.openNone end
  set(v.stand, stand)
  set(v.open, extra)
  for i, row in ipairs(v.done) do
    local d = done[i]
    set(row.title, d and d.title or "")
    set(row.body, d and d.body or "")
    row.tip = d and d.tip or nil
  end
  for i, row in ipairs(v.openRows) do
    local o = rows[i]
    row.isSub = o and o.sub == true or false
    if row.isSub then
      row.head:SetText(o.title)
      row.head:Show()
      set(row.title, "")
      set(row.body, "")
      set(row.zone, "")
      row.icon:Hide()
      row.tip = nil
      row.questID = nil
    else
      row.head:Hide()
      set(row.title, o and o.title or "")
      set(row.body, o and o.goal or "")
      set(row.zone, o and o.zone or "")
      row.title:SetWidth(SR.w - View.ICON_W - ((o and o.zone) and (View.ZONE_W + 6) or 0))
      if o then View.setIcon(row.icon, o.icon or "quest") else row.icon:Hide() end
      local tip = nil
      if o then
        tip = { o.title }
        if o.zone then tip[#tip + 1] = o.zone end
        if o.goal then tip[#tip + 1] = o.goal end
      end
      row.tip = tip
      row.questID = o and o.questID or nil
      if tip and row.questID then tip[#tip + 1] = T.clickTip end
    end
  end
  local y0, bottom = View.RIGHT_Y, View.BODY_BOTTOM
  -- heights at size z with nDone / nOpen rows and a line limit for the quest texts (0 = none)
  local function rowH(row, hasBody)
    local h = height(row.title)
    if hasBody then h = h + 2 + height(row.body) end
    return h
  end
  local rowGap = View.ROW_GAP
  local function measure(z, nDone, nOpen, doneLines)
    for _, fs in ipairs({ v.stand, v.open }) do setSize(fs, z) end
    local total = height(v.stand)
    local hd = {}
    if nDone > 0 then
      total = total + View.GAP + View.HEAD_H
      for i = 1, nDone do
        local row = v.done[i]
        setSize(row.title, z)
        setSize(row.body, z)
        if row.body.SetMaxLines then row.body:SetMaxLines(doneLines) end
        hd[i] = rowH(row, done[i].body ~= nil)
        total = total + hd[i] + (i > 1 and rowGap or 0)
      end
    end
    total = total + View.GAP + View.HEAD_H
    local ho = {}
    for i = 1, nOpen do
      local row = v.openRows[i]
      setSize(row.title, z)
      ho[i] = row.isSub and View.SUB_H or rowH(row, rows[i].goal ~= nil) -- sub heads "Hier in der Gegend" / "Anderswo"
      total = total + ho[i] + (i > 1 and rowGap or 0)
    end
    local he = (extra ~= "") and height(v.open) or 0
    if he > 0 then total = total + (nOpen > 0 and rowGap or 0) + he end
    return y0 + total <= bottom, hd, ho, he, total
  end
  if v.open.SetMaxLines then v.open:SetMaxLines(0) end
  local clamped = false
  local nDone, nOpen = #done, #rows
  local z, doneLines, fit, hd, ho, he
  for _, s in ipairs(View.TEXT_SIZES) do
    fit, hd, ho, he = measure(s, nDone, nOpen, 0)
    if fit then z, doneLines = s, 0 break end
  end
  if not z then
    -- never cut a quest text (by design): first fewer open quests, then tighter gaps, then fewer turn-ins (whole entries)
    z, doneLines = View.TEXT_SIZES[#View.TEXT_SIZES], 0
    fit, hd, ho, he = measure(z, nDone, nOpen, doneLines)
    while not fit and nOpen > 1 do
      nOpen = nOpen - 1
      while nOpen > 1 and rows[nOpen].sub do nOpen = nOpen - 1 end -- no sub head without a quest below it
      if nOpen == 1 and rows[1].sub then nOpen = min(2, #rows) break end
      fit, hd, ho, he = measure(z, nDone, nOpen, doneLines)
    end
    if not fit then
      rowGap = View.ROW_GAP_MIN
      fit, hd, ho, he = measure(z, nDone, nOpen, doneLines)
    end
    while not fit and nDone > 1 do
      nDone = nDone - 1
      fit, hd, ho, he = measure(z, nDone, nOpen, doneLines)
    end
    if not fit and he > 0 and v.open.SetMaxLines then
      -- last resort: the extra lines (to-dos, work order) limited to the room left; the whole list stays in the tooltip
      local _, _, _, heFull, total = measure(z, nDone, nOpen, doneLines)
      local room = bottom - (y0 + total - heFull)
      v.open:SetMaxLines(max(1, floor(room / lineH(z))))
      clamped = true
      fit, hd, ho, he = measure(z, nDone, nOpen, doneLines)
    end
  end
  -- place
  place(v.stand, self.r, SR.x, y0)
  local y = y0 + height(v.stand)
  if nDone > 0 then
    v.doneHead:ClearAllPoints()
    v.doneHead:SetPoint("TOPLEFT", self.r, "TOPLEFT", SR.x, -(y + View.GAP))
    v.doneHead:Show()
    y = y + View.GAP + View.HEAD_H
    for i = 1, nDone do
      local row = v.done[i]
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", self.r, "TOPLEFT", SR.x, -y)
      row:SetSize(SR.w, max(1, hd[i]))
      row.body:ClearAllPoints()
      row.body:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
      row.body:SetShown(done[i].body ~= nil)
      row:Show()
      y = y + hd[i] + rowGap
    end
    y = y - rowGap
  else
    v.doneHead:Hide()
  end
  v.openHead:ClearAllPoints()
  v.openHead:SetPoint("TOPLEFT", self.r, "TOPLEFT", SR.x, -(y + View.GAP))
  y = y + View.GAP + View.HEAD_H
  local yOpen = y
  for i = 1, nOpen do
    local row = v.openRows[i]
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.r, "TOPLEFT", SR.x, -y)
    row:SetSize(SR.w, max(1, ho[i]))
    row.body:ClearAllPoints()
    row.body:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 8, -2)
    row.body:SetShown(rows[i].goal ~= nil)
    row:Show()
    y = y + ho[i] + rowGap
  end
  if nOpen > 0 then y = y - rowGap end
  if he > 0 then
    if nOpen > 0 then y = y + rowGap end
    place(v.open, self.r, SR.x, y)
    v.open:Show()
    y = y + he
  else
    v.open:Hide()
  end
  -- shortened: the whole open list in the tooltip of the block
  if nOpen < #rows or clamped then
    local full = { T.moreTip }
    for l in string.gmatch(View.openText(recap) .. "\n", "(.-)\n") do
      if l ~= "" then full[#full + 1] = l end
    end
    v.openHit.full = full
    v.openHit:ClearAllPoints()
    v.openHit:SetPoint("TOPLEFT", self.r, "TOPLEFT", SR.x, -yOpen)
    v.openHit:SetSize(SR.w, max(1, y - yOpen))
    v.openHit:Show()
  end
end

local function stamp(index)
  if type(index) ~= "table" or index.stale == true then return nil end
  return tonumber(index.lines)
end

function View:Render()
  local recap = self.recap
  self:DrawLeft(recap)
  self:DrawRight(recap)
end

function View:Open(index, _, want)
  self.open = true
  local page = self.page
  if want == nil and page then
    want = page.recapWant
    page.recapWant = nil
  end
  self.want = want
  self.readyTries = 0
  self:Load(index, want)
  self.stamp = stamp(index)
  self.l:Show()
  self.r:Show()
  self:Render()
end

-- the index changed: a recap that is already there stays (it does not flicker); one that was missing is looked for again
-- A recap the page picked itself (not handed over) is built again when the index grew (new lines: e.g. a turn-in of the running
-- session for "Zuletzt erledigt"; the model reads the index as it was when the page opened)

function View:Refresh(index)
  if not self.open then return end
  self.index = index
  local s = stamp(index)
  local handed = type(self.want) == "table" and type(self.want.recap) == "table"
  if not self.recap or (not handed and s and self.stamp and s ~= self.stamp) then
    self:Load(index, self.want)
  end
  self.stamp = s or self.stamp
  self:Render()
end

function View:Close()
  self.open = false
  self.l:Hide()
  self.r:Hide()
  W.hideTip(self.pic.frame)
  W.hideTip(self.L.storyHit)
  W.hideTip(self.L.storyBox)
  W.hideTip(self.L.best.frame)
  W.hideTip(self.R.openHit)
  for _, row in ipairs(self.R.done) do W.hideTip(row) end
  for _, row in ipairs(self.R.openRows) do W.hideTip(row) end
end
