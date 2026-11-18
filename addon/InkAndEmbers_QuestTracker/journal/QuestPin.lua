-- Pinned quest of the quest tracker (change "modular", addendum "Quest anpinnen", 1.1.0). ONE quest (title, level, type pill,
-- objectives with progress) stands permanently on screen as a mini slid-out panel of the grip, cast in one piece with it (style
-- template Gemini draft 2, addendum 16.11.): docked at the grip's left edge, centred on the plaque, same smoky ground and bronze edge,
-- no seam, nothing of the grip covered; the fonts, colours and objective lines of the tracker itself (QTR.ui). It is visible while the
-- tracker is slid in; while the panel is out it fades out and the pinned row in the list carries a small pin instead (no double
-- display). While a quest is pinned the progress toast stays away (QuestTracker.lua detectProgress): progress of the pinned quest
-- makes the panel flash and shake instead; only the test toast (/chronik quests hinweis) still makes it step aside.
--
-- Pinning: context menu of a quest row ("Anpinnen" / "Nicht mehr anpinnen"). A manual pin is kept per character
-- (char.questTrackerState.pin) and is never replaced automatically; it goes when the quest leaves the log.
-- Ready to hand in (both kinds of pin): the panel shows "Fertig!" with a flash for QP.DONE_HOLD seconds, then it retracts
-- towards the grip (slide + fade over QP.RETRACT, fade only with "Bewegung reduzieren") and the pin goes - a manual pin is deleted
-- from the saved state as well. A quest pinned by hand while it is already ready stays (no "became ready" event).
-- Automatic (option panel.autoPin, default on): when an objective of a quest counts up (QuestTracker.lua detectProgress compares
-- the readable objective counts of two quest log reads; secret or missing values count as "no change"), that quest is pinned and
-- marked "auto" - unless a manual pin exists. An auto pin goes when its quest is ready (it shows "Fertig!" for a moment first), after
-- QP.idle() seconds without progress (option panel.autoPinIdle, minutes, default 5), when the player leaves the zone in which the progress happened, when the quest leaves the log,
-- or when the option is switched off. An auto pin dismissed by hand does not come back for that quest in this session.
-- Combat: only own, non-secure frames are shown and filled; nothing here is protected. The mini panel takes no mouse input.
-- Security: every text comes display-safe from QuestTrack (Sanitize.display) and only goes into FontStrings.
--
-- PUBLIC API: QP.current() -> questID | nil, auto (bool); QP.pin(questID) -> bool (manual); QP.unpin() -> bool; QP.status() -> table.
-- Hooks for QuestTracker.lua: QTR.pinnedId(), QTR.pinProgress(rec, objIndex, becameReady, t, view), QTR.pinRefresh(view, s),
-- QTR.pinStep(elapsed, t, slideOut), QTR.pinHide(), QTR.pinShown(); the grip side: handle.setDock(need, gap).
local _, ns = ...

local Journal = ns.Journal
if not Journal then return end
local QTR = Journal.QuestTracker
if not (QTR and QTR.ui) then return end
local U = QTR.ui
local T = QTR.TEXT

local QP = {}
Journal.QuestPin = QP

local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil

QP.W = 210 -- width of the mini panel (a little narrower than the tracker's content, 230)
QP.PAD = { x = 12, top = 8, bottom = 8, right = 10 }
QP.R = 8 -- corner radius of the body (left corners; the right ones are clipped square at the grip)
-- ground, smoke, edge and corner filigree: the same values as the grip (QuestTracker.lua paintGrip), times the grip's current opacity
QP.BG_ALPHA, QP.SMOKE_ALPHA, QP.EDGE_ALPHA, QP.CORNER_ALPHA = 0.85, 0.22, 0.3, 0.35
QP.FEATHER = 10 -- width of the feathered rim of the ground
QP.SEAM_IN = 8 -- how far the ground runs under the grip (its feathered end fades out there)
QP.CORNER = 16 -- size of the corner filigree
QP.SEAM_W, QP.SEAM_ALPHA = 22, 0.22 -- warm glow on the joint with the grip
-- progress of the pinned quest: edge and body flash (on, off; peak of the additive plate), the changed line glows a little longer,
-- the content shakes sideways (amp px, freq per second, time s; decays to 0; none with reduceMotion)
QP.FLASH = { on = 0.12, off = 0.45, peak = 0.16, row = 0.9, rowPeak = 0.22 }
QP.SHAKE = { amp = 3, freq = 11, time = 0.32 }
QP.IDLE_MIN = 5 -- auto pin: released after this many minutes without progress (default of the option panel.autoPinIdle)
QP.DONE_HOLD = 3 -- a pinned quest that got ready: "Fertig!" stays this long (seconds while it is visible) ...
QP.DONE_MAX = 30 -- ... and at the latest this long after the quest got ready
QP.FADE = 0.3 -- fade in/out
QP.RETRACT, QP.RETRACT_PX = 0.45, 40 -- after "Fertig!": the panel slides this far towards the grip while it fades out (seconds, px)

local st = { id = nil, auto = false, last = 0, zone = nil, doneAt = nil, doneLeft = nil, dismissed = {}, a = 0, frame = nil,
  loaded = false, reason = nil }
QP.state = st

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end
local function whole(v)
  v = U.num(v)
  if not v or v <= 0 or v ~= floor(v) then return nil end
  return v
end
local function QT() return Journal.QuestTrack end

-- ---------------------------------------------------------------- state

-- char.questTrackerState.pin = questID of the MANUAL pin (an auto pin is never stored)
local function charState(create)
  local Store = ns.Store
  local char = Store and Store.char and Store.char() or nil
  if type(char) ~= "table" or isSecret(char) then return nil end
  local t = char.questTrackerState
  if type(t) ~= "table" or isSecret(t) then
    if not create then return nil end
    t = {}
    char.questTrackerState = t
  end
  return t
end

local function store(id)
  local t = charState(id ~= nil)
  if t then t.pin = id end
end

local function load()
  if st.loaded then return end
  local t = charState(false)
  local Store = ns.Store
  if not (t or (Store and Store.char and type(Store.char()) == "table")) then return end -- saved variables not there yet
  st.loaded = true
  local id = t and whole(t.pin) or nil
  if id and not st.id then st.id, st.auto = id, false end
end

-- seconds without progress until an auto pin goes (tracker settings: "Automatisch lösen nach", 1-30 min)
function QP.idle()
  local s = U.settings()
  local m = s and s.panel and U.num(s.panel.autoPinIdle) or nil
  if not m or m < 1 or m > 30 then m = QP.IDLE_MIN end
  return m * 60
end

local function autoOn()
  local s = U.settings()
  return not (s and s.panel and s.panel.autoPin == false)
end

local function release(reason)
  if not st.id then return false end
  if not st.auto then store(nil) end
  st.id, st.auto, st.zone, st.doneAt, st.doneLeft, st.reason = nil, false, nil, nil, nil, reason
  QTR.request()
  return true
end

function QP.current()
  load()
  return st.id, st.id ~= nil and st.auto == true
end

function QTR.pinnedId() return (QP.current()) end

-- manual pin (menu entry "Anpinnen" / "Fest anpinnen"); replaces any other pin
function QP.pin(questID)
  load()
  local id = whole(questID)
  local Q = QT()
  if not (id and Q and Q.record and Q.record(id)) then return false end
  st.id, st.auto, st.zone, st.doneAt, st.doneLeft, st.reason = id, false, nil, nil, nil, nil
  st.dismissed[id] = nil
  store(id)
  QTR.request()
  return true
end

function QP.unpin()
  load()
  if not st.id then return false end
  if st.auto then st.dismissed[st.id] = true end -- a dismissed auto pin does not come back for this quest (session)
  return release("manual")
end

-- an objective of rec counted up (objIndex) and/or the quest got ready (QuestTracker.lua detectProgress)
function QTR.pinProgress(rec, objIndex, becameReady, t, view)
  load()
  local id = type(rec) == "table" and whole(rec.questID) or nil
  if not id then return end
  t = U.num(t) or U.now()
  if st.id == id then
    st.last = t
    if becameReady then st.doneAt, st.doneLeft = t, QP.DONE_HOLD end
    QP.flash(t, objIndex)
    return
  end
  if st.id and not st.auto then return end -- the manual pin has priority and is never replaced
  if not autoOn() or st.dismissed[id] then return end
  st.id, st.auto, st.last, st.reason = id, true, t, nil
  st.zone = type(view) == "table" and whole(view.zoneMapID) or nil
  st.doneAt, st.doneLeft = nil, nil
  if becameReady then st.doneAt, st.doneLeft = t, QP.DONE_HOLD end
  QP.flash(t, objIndex)
end

-- ---------------------------------------------------------------- mini panel
-- One piece with the grip (style template draft 2): the panel's right edge IS the grip's left edge (anchor RIGHT -> grip LEFT, x = 0,
-- vertically centred on the plaque). Soft look: the ground is feathered all round (QTR.softPlate) and runs QP.SEAM_IN
-- under the grip, where its feathered end meets the grip's feathered rim - a gradient, no hard vertical line. The faint bronze edge
-- has no right side; its top and bottom line fade out towards the grip, whose left edge opens for exactly the panel's height and
-- fades out there too (grip h.setDock). Nothing of the grip is covered (the panel sits one frame level below the grip, the plaque
-- above all). A soft warm glow lies on the joint. Ground, smoke and edge follow the grip's
-- current opacity (QTR.state.gripA, option "Griff-Deckkraft", floored at QTR.PIN_GROUND while docked), so both read as one ground.
-- The texts sit on f.content: on progress of the pinned quest only the content shakes (the body stays docked, the joint never
-- opens), while edge and changed line flash (QP.flash).

local function theme() return ns.Journal and ns.Journal.Theme end

local function layer(parts, name, sub, blend)
  for _, t in ipairs(parts or {}) do
    if t.SetDrawLayer then t:SetDrawLayer(name, sub) end
    if blend and t.SetBlendMode then t:SetBlendMode(blend) end
  end
end

local function build()
  local R = QP.R
  local f = CreateFrame("Frame", nil, UIParent)
  U.size(f, QP.W, 60)
  f:SetFrameStrata(QTR.STRATA)
  f:SetFrameLevel(28) -- below the grip (30) and its plaque (33): the panel never covers any of it
  if f.EnableMouse then f:EnableMouse(false) end
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  -- body: runs SEAM_IN under the grip; its feathered right end fades out there (soft joint, no clipping)
  f.body = CreateFrame("Frame", nil, f)
  if f.body.SetFrameLevel then f.body:SetFrameLevel(28) end
  U.pt(f.body, "TOPLEFT", f, "TOPLEFT", 0, 0)
  U.pt(f.body, "BOTTOMRIGHT", f, "BOTTOMRIGHT", QP.SEAM_IN, 0)
  f.bg = U.softPlate(f.body, QTR.C.ground, QP.BG_ALPHA, QP.FEATHER)
  f.smoke = U.gripPiece(f.body, "smoke", "BORDER", 0, QTR.C.smoke, QP.SMOKE_ALPHA)
  U.pt(f.smoke, "TOPLEFT", f.body, "TOPLEFT", R, -2)
  U.pt(f.smoke, "BOTTOMRIGHT", f.body, "BOTTOMRIGHT", -2, 2)
  -- faint edge without a right side: it ends at the grip (top and bottom line fade out towards it, QP paint)
  f.edgeFrame = CreateFrame("Frame", nil, f.body)
  if f.edgeFrame.SetFrameLevel then f.edgeFrame:SetFrameLevel(28) end
  U.pt(f.edgeFrame, "TOPLEFT", f, "TOPLEFT", 0, 0)
  U.pt(f.edgeFrame, "BOTTOMRIGHT", f, "BOTTOMRIGHT", R, 0)
  f.edge = U.plate(f.edgeFrame, QTR.C.bronze, QP.EDGE_ALPHA, R, true)
  if f.edge then
    layer(f.edge.parts, "BORDER", 2)
    for _, i in ipairs({ 3, 6, 9 }) do f.edge.parts[i]:Hide() end
  end
  -- corner filigree top left and (mirrored) bottom left, dezent
  f.cornerT = U.gripPiece(f.body, "corner", "ARTWORK", 0, QTR.C.bronze, QP.CORNER_ALPHA)
  U.size(f.cornerT, QP.CORNER, QP.CORNER)
  U.pt(f.cornerT, "TOPLEFT", f.body, "TOPLEFT", 1, -1)
  f.cornerB = U.gripPiece(f.body, "corner", "ARTWORK", 0, QTR.C.bronze, QP.CORNER_ALPHA, true)
  U.size(f.cornerB, QP.CORNER, QP.CORNER)
  U.pt(f.cornerB, "BOTTOMLEFT", f.body, "BOTTOMLEFT", 1, 1)
  -- warm glow on the joint (centred on the right edge, the clipped half shines into the panel)
  f.seam = U.tex(f, nil, "ARTWORK", nil, 1)
  local Th = theme()
  if Th and Th.TEX and Th.TEX.glow then f.seam:SetTexture(Th.TEX.glow) end
  if f.seam.SetBlendMode then f.seam:SetBlendMode("ADD") end
  U.setColor(f.seam, QTR.C.bronzeLight, QP.SEAM_ALPHA)
  -- flash: an additive plate over the body, and a strip behind the changed objective line
  f.flash = U.plate(f.body, QTR.C.bronzeLight, 0, R)
  if f.flash then layer(f.flash.parts, "ARTWORK", 3, "ADD") end
  f.rowFlash = U.solid(f.body, QTR.C.bronzeLight, "ARTWORK", 2)
  if f.rowFlash.SetBlendMode then f.rowFlash:SetBlendMode("ADD") end
  U.setColor(f.rowFlash, QTR.C.bronzeLight, 0)
  f.rowFlash:Hide()
  -- content (shakes on progress)
  f.content = CreateFrame("Frame", nil, f)
  if f.content.SetFrameLevel then f.content:SetFrameLevel(29) end
  U.pt(f.content, "TOPLEFT", f, "TOPLEFT", 0, 0)
  local c = f.content
  f.pinIcon = U.icon(c, "pin", 9, QTR.C.copper, 2)
  f.label = U.font(c, "text", 9, QTR.C.copper, "LEFT")
  if f.label.SetWordWrap then f.label:SetWordWrap(false) end
  f.lv = U.font(c, "text", 10, QTR.C.title, "LEFT")
  f.title = U.font(c, "text", 12, QTR.C.title, "LEFT")
  if f.title.SetWordWrap then f.title:SetWordWrap(true) end
  if f.title.SetMaxLines then f.title:SetMaxLines(2) end
  -- type pill (same look as in the tracker row: QTR.PILL)
  f.pill = CreateFrame("Frame", nil, c)
  U.size(f.pill, 46, 12)
  f.pill.edge = U.solid(f.pill, QTR.C.groupEdge, "BORDER")
  f.pill.edge:SetAllPoints(f.pill)
  f.pill.fill = U.solid(f.pill, QTR.C.bg, "ARTWORK")
  U.pt(f.pill.fill, "TOPLEFT", f.pill, "TOPLEFT", 1, -1)
  U.pt(f.pill.fill, "BOTTOMRIGHT", f.pill, "BOTTOMRIGHT", -1, 1)
  f.pill.text = U.font(f.pill, "text", 8, QTR.C.group, "CENTER")
  U.pt(f.pill.text, "CENTER", f.pill, "CENTER", 0, 0)
  f.pill:Hide()
  f.objs = {}
  f:SetAlpha(0)
  f:Hide()
  return f
end

local function frame()
  if not st.frame then st.frame = build() end
  return st.frame
end
QP.frame = frame

local function fill(f, rec, s)
  local k = QTR.lineK and QTR.lineK() or 1
  local P = QP.PAD
  local x = P.x
  local inner = QP.W - P.x - P.right
  local y = P.top
  local c = f.content
  local ready = rec.complete == true
  local done = st.doneAt ~= nil
  -- label: pin + "ANGEPINNT" / "AUTOMATISCH ANGEPINNT" / "FERTIG!" (got ready while pinned) / "BEREIT ZUR ABGABE" (pinned while ready)
  local labelText = (done and T.pinDone) or (ready and T.ready) or (st.auto and T.pinAutoLabel) or T.pinLabel
  local lc = (done or ready) and QTR.C.check or QTR.C.copper
  f.label:SetText(U.upper(labelText))
  U.setColor(f.label, lc)
  f.pinIcon.color(lc)
  U.clear(f.pinIcon)
  U.pt(f.pinIcon, "TOPLEFT", c, "TOPLEFT", x, -y)
  U.clear(f.label)
  U.pt(f.label, "TOPLEFT", c, "TOPLEFT", x + 13, -y)
  U.width(f.label, inner - 13)
  y = y + ceil(11 * k) + 3
  -- [level] title (level in the difficulty colour, with the suffix of the type: [25+] [20D] [60R])
  local dc = U.diffColor(rec)
  f.lv:SetText(rec.level and ("[" .. tostring(rec.level) .. (rec.levelSuffix or "") .. "]") or "")
  U.setColor(f.lv, dc)
  U.clear(f.lv)
  U.pt(f.lv, "TOPLEFT", c, "TOPLEFT", x, -(y + 1))
  local lw = rec.level and ((U.num(f.lv:GetStringWidth()) or 18) + 4) or 0
  U.width(f.title, max(40, inner - lw))
  f.title:SetText(rec.title or "")
  U.setColor(f.title, ready and QTR.C.turnin or QTR.C.title)
  U.clear(f.title)
  U.pt(f.title, "TOPLEFT", c, "TOPLEFT", x + lw, -y)
  y = y + max(ceil(15 * k), ceil(U.num(f.title:GetStringHeight()) or 14)) + 2
  -- type pill under the title (not when ready, like the tracker row)
  local pd = rec.pill and QTR.PILL and QTR.PILL[rec.pill] or nil
  local showPill = pd ~= nil and not ready
  f.pill:SetShown(showPill)
  U.clear(f.pill)
  if showPill then
    f.pill.text:SetText(T[pd.key])
    U.setColor(f.pill.text, pd.text)
    U.setColor(f.pill.edge, pd.edge)
    U.size(f.pill, ceil((U.num(f.pill.text:GetStringWidth()) or 40) + 10), ceil(12 * k))
    U.pt(f.pill, "TOPLEFT", c, "TOPLEFT", x, -y)
    y = y + ceil(12 * k) + 3
  end
  -- objectives: the tracker's own lines (warm dot, count, text; finished ones ticked and pale, or hidden by "look.doneObj")
  for _, o in ipairs(f.objs) do o:Hide() end
  local n = 0
  for i, o in ipairs(rec.objectives or {}) do
    if not (o.done and s and s.look and s.look.doneObj == "hide") then
      n = n + 1
      local line = f.objs[n]
      if not line then
        line = U.newObj(c)
        f.objs[n] = line
      end
      line:Show()
      line.objIndex = i
      U.clear(line)
      U.pt(line, "TOPLEFT", c, "TOPLEFT", x, -y)
      y = y + U.fillObj(line, o, 0, inner, false, rec) + 1
      if line.mark then U.setColor(line.mark, QTR.C.copper) end
    end
  end
  local hgt = y + P.bottom
  U.size(f, QP.W, hgt)
  U.size(c, QP.W, hgt)
  U.clear(f.seam)
  U.size(f.seam, QP.SEAM_W, max(8, hgt - 6))
  U.pt(f.seam, "CENTER", f, "RIGHT", 0, 0)
  f.rec = rec
end

-- grip units per panel unit (the panel has the tracker's scale, the grip its own)
local function ratio(f, h)
  local fs, hs = U.num(f:GetScale()) or 1, U.num(h:GetScale()) or 1
  if fs <= 0 or hs <= 0 then return 1 end
  return fs / hs
end

-- tell the grip how much room the docked panel needs and whether its left edge must open (only while the panel shows)
local function dock(open)
  local fr = QTR.state.frames
  local h = fr and fr.handle
  if not (h and h.setDock) then return end
  local f = st.frame
  local need, dh
  if (st.id or st.retract) and f and f.rec then -- a retracting panel keeps its place at the grip until it is gone
    dh = (U.num(f:GetHeight()) or 60) * ratio(f, h)
    -- the panel is centred on the plaque (badgeY below the middle): room above AND below = corner radius + dock margin
    need = ceil(dh + 2 * (QTR.HANDLE.r + QTR.HANDLE.dock + math.abs(QTR.HANDLE.badgeY)))
  end
  local gap = (open and need) and dh or nil
  local key = tostring(need) .. ":" .. tostring(gap)
  if st.dockKey == key then return end
  st.dockKey = key
  h.setDock(need, gap)
end
QP.dock = dock

-- after every render of the tracker: drop a pin whose quest is gone (or whose reason ended), fill and place the mini panel
function QTR.pinRefresh(view, s)
  load()
  if not st.id then
    dock(st.retract ~= nil)
    return
  end
  local Q = QT()
  local rec = Q and Q.record and Q.record(st.id) or nil
  if not rec then return release("gone") end
  if st.auto then
    if not autoOn() then return release("option") end
    local here = type(view) == "table" and whole(view.zoneMapID) or nil
    if st.zone and here and here ~= st.zone then return release("zone") end
    if not st.zone and here then st.zone = here end
  end
  local f = frame()
  local fr = QTR.state.frames
  s = s or U.settings()
  f:SetScale((s and s.panel and s.panel.scale) or 1)
  fill(f, rec, s)
  if fr and fr.handle then
    U.clear(f)
    U.pt(f, "RIGHT", fr.handle, "LEFT", 0, QTR.HANDLE.badgeY / ratio(f, fr.handle))
  end
  st.dockKey = nil -- height may have changed
  dock(st.a > 0.01)
end

-- progress of the pinned quest: flash + shake (QTR.pinProgress); objIndex = the objective that counted up (nil = the quest got ready)
function QP.flash(t, objIndex)
  st.flashAt, st.flashObj = U.num(t) or U.now(), objIndex
end

-- the ground follows the grip's current opacity; flash k (0..1) lifts the edge and lays the additive plate over the body
local function paint(f, ga, k)
  if f.bg then f.bg.color(QTR.C.ground, QP.BG_ALPHA * ga) end
  U.setColor(f.smoke, QTR.C.smoke, QP.SMOKE_ALPHA * ga)
  local ea = QP.EDGE_ALPHA * ga
  if f.edge then
    local ec, a = k > 0 and QTR.C.bronzeLight or QTR.C.bronze, ea + (1 - ea) * k
    f.edge.color(ec, a)
    -- top and bottom line fade out towards the grip (soft joint)
    U.fade(f.edge.parts[2], "HORIZONTAL", ec, a, a * 0.1)
    U.fade(f.edge.parts[8], "HORIZONTAL", ec, a, a * 0.1)
  end
  U.setColor(f.cornerT, QTR.C.bronze, QP.CORNER_ALPHA * ga)
  U.setColor(f.cornerB, QTR.C.bronze, QP.CORNER_ALPHA * ga)
  U.setColor(f.seam, QTR.C.bronzeLight, QP.SEAM_ALPHA * max(ga, k))
  if f.flash then f.flash.color(QTR.C.bronzeLight, QP.FLASH.peak * k) end
end

-- flash curve (on QP.FLASH.on, off QP.FLASH.off) and shake offset of the content at e seconds after the progress
function QP.flashK(e)
  local F = QP.FLASH
  if e < 0 then return 0 end
  if e < F.on then return e / F.on end
  if e < F.on + F.off then return 1 - (e - F.on) / F.off end
  return 0
end
function QP.shakeX(e)
  local S = QP.SHAKE
  if e < 0 or e >= S.time then return 0 end
  return S.amp * math.sin(2 * math.pi * S.freq * e) * (1 - e / S.time)
end

-- per frame (QTR.step): fade (hidden while the panel is out, while a toast shows and in the edit mode), the auto timeouts, shared
-- ground with the grip, flash and shake
function QTR.pinStep(elapsed, t, slideOut)
  elapsed = U.num(elapsed) or 0
  t = U.num(t) or U.now()
  local f = st.frame
  local out = U.num(slideOut) or 0
  if st.id and st.doneAt then
    -- "Fertig!" (both kinds of pin): count down while it is visible, then retract towards the grip and release
    if st.a * (1 - out) > 0.9 then st.doneLeft = (st.doneLeft or QP.DONE_HOLD) - elapsed end
    if (st.doneLeft or 0) <= 0 or t - st.doneAt >= QP.DONE_MAX then
      if f and st.a > 0.01 then st.retract = { t = t, a = st.a } end
      release("done")
    end
  elseif st.id and st.auto and t - (st.last or t) >= QP.idle() then
    release("idle")
  end
  if not f then return end
  local fr = QTR.state.frames
  local toast = QTR.state.toast ~= nil and fr ~= nil and fr.toast:IsShown()
  local want = (st.id ~= nil and f.rec ~= nil and not toast and not (QTR.editing and QTR.editing())) and 1 or 0
  local rt = st.retract
  if rt and st.id then st.retract, rt = nil, nil end -- pinned again meanwhile
  if rt then
    -- retract after "Fertig!": fade over QP.RETRACT, sliding towards the grip (not with reduceMotion)
    local e = min(1, (t - rt.t) / QP.RETRACT)
    st.a = rt.a * (1 - e)
    local fr2 = QTR.state.frames
    if fr2 and fr2.handle then
      local k = ratio(f, fr2.handle)
      local x = U.reduceMotion() and 0 or QP.RETRACT_PX * U.ease(e)
      U.clear(f)
      U.pt(f, "RIGHT", fr2.handle, "LEFT", x, QTR.HANDLE.badgeY / k)
    end
    if e >= 1 then st.retract = nil end
  elseif U.reduceMotion() then
    st.a = want
  else
    local d = elapsed / QP.FADE
    st.a = want > st.a and min(want, st.a + d) or max(want, st.a - d)
  end
  local a = st.a * (1 - out)
  f:SetAlpha(a)
  if a <= 0.001 then
    if f:IsShown() then f:Hide() end
    if not st.id then f.rec = nil end
  elseif not f:IsShown() then
    f:Show()
  end
  dock(a > 0.01)
  if a <= 0.001 then return end
  -- flash + shake after progress of the pinned quest
  local k, dx = 0, 0
  if st.flashAt then
    local e = t - st.flashAt
    if e > max(QP.FLASH.on + QP.FLASH.off, QP.FLASH.row, QP.SHAKE.time) then
      st.flashAt, st.flashObj = nil, nil
    else
      k = QP.flashK(e)
      if not U.reduceMotion() then dx = QP.shakeX(e) end
      local line
      for _, o in ipairs(f.objs) do
        if o:IsShown() and st.flashObj and o.objIndex == st.flashObj then line = o end
      end
      if line then
        U.clear(f.rowFlash)
        U.pt(f.rowFlash, "TOPLEFT", line, "TOPLEFT", -4, 1)
        U.size(f.rowFlash, QP.W - QP.PAD.x - QP.PAD.right + 8, (U.num(line:GetHeight()) or 15) + 1)
        U.setColor(f.rowFlash, QTR.C.bronzeLight, QP.FLASH.rowPeak * max(0, 1 - e / QP.FLASH.row))
        f.rowFlash:Show()
      else
        f.rowFlash:Hide()
      end
    end
  end
  if not st.flashAt then f.rowFlash:Hide() end
  if dx ~= st.dx then
    st.dx = dx
    U.clear(f.content)
    U.pt(f.content, "TOPLEFT", f, "TOPLEFT", dx, 0)
  end
  local ga = U.num(QTR.state.gripA) or 1
  if k > 0 or st.k ~= k or not st.ga or math.abs(st.ga - ga) > 0.003 then
    st.ga, st.k = ga, k
    paint(f, ga, k)
  end
end

-- the grip lifts its resting opacity to QTR.PIN_GROUND while the panel shows (QuestTracker.lua QTR.step)
function QTR.pinShown()
  return st.id ~= nil and st.a > 0.01
end

function QTR.pinHide()
  st.a = 0
  if st.frame then
    st.frame:SetAlpha(0)
    st.frame:Hide()
  end
  dock(false)
end

function QP.status()
  local f = st.frame
  return { id = st.id, auto = st.id ~= nil and st.auto == true, zone = st.zone, done = st.doneAt ~= nil, reason = st.reason,
    shown = f ~= nil and f:IsShown() == true, alpha = st.a, flashing = st.flashAt ~= nil, retracting = st.retract ~= nil }
end
