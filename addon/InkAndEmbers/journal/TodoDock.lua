-- To-dos docked to the quest tracker (option "dock", default off): an own, unprotected section on UIParent drawn in the
-- tracker's look (its width, ObjectiveTrackerHeaderFont / ObjectiveTrackerLineFont, a section header with a collapse button,
-- progress "3/10" in front of the line like quest objectives). It is NOT a module of Blizzard's tracker: nothing is registered
-- there, nothing is written into Blizzard tables, the tracker is never moved and our frame is never anchored to it (anchoring to
-- a frame with secure children would make our frame anchor-restricted in combat). Instead the tracker's rectangle is only read
-- (GetLeft/GetTop/GetBottom) and our frame is placed on UIParent next to it; post-hooks (hooksecurefunc / HookScript) and a
-- light poll while shown follow its moves. Questie (Questie_BaseFrame) and Kaliel's Tracker replace Blizzard's tracker and are
-- docked to instead. Data and clicks are the mini note's (TodoTracker.entries, Plans.onChange, click opens the book).
local _, ns = ...

local Journal = ns.Journal
local TT = Journal and Journal.TodoTracker
if not TT then return end

local floor, max, min = math.floor, math.max, math.min

local Dock = {}
Journal.TodoDock = Dock
TT.Dock = Dock

Dock.NAME = "EveNChronicleTodoDock"
Dock.GAP = 4            -- vertical gap between tracker and section
Dock.HEAD_H = 26        -- like Blizzard's module header
Dock.INDENT = 20        -- text start of a line (the nub sits left of it)
Dock.ROW_GAP = 3
Dock.PAD_B = 4
Dock.W = { min = 180, max = 480, fallback = 260 }
Dock.POLL = 0.25        -- seconds between geometry checks while shown
Dock.SIDES = { "below", "above" }
-- Frames that may hold the quest tracker, in priority order (replacements first: Kaliel's Tracker draws its own frame,
-- Questie hides Blizzard's tracker and draws Questie_BaseFrame in its place). The first visible one wins.
Dock.TARGETS = {
  { kind = "kaliel", name = "!KalielsTrackerFrame" },
  { kind = "kaliel", name = "KT_ObjectiveTrackerFrame" },
  { kind = "questie", name = "Questie_BaseFrame" },
  { kind = "blizzard", name = "ObjectiveTrackerFrame" },
  { kind = "blizzard", name = "WatchFrame" },
  { kind = "blizzard", name = "QuestWatchFrame" },
}
Dock.ATLAS = { collapse = "ui-questtrackerbutton-secondary-collapse", expand = "ui-questtrackerbutton-secondary-expand",
  header = "ui-questtracker-secondary-objective-header", nub = "ui-questtracker-objective-nub", check = "ui-questtracker-tracker-check" }
-- OBJECTIVE_TRACKER_COLOR (Blizzard) is read when present, these are the same values as fallback
Dock.COLOR = { Header = { 1, 0.82, 0 }, Normal = { 0.8, 0.8, 0.8 }, Highlight = { 1, 1, 1 }, Complete = { 0.6, 0.6, 0.6 },
  line = { 1, 0.82, 0, 0.35 } }

local T = TT.TEXT

local st = { rows = {}, list = {}, hooked = {}, poll = 0 }
-- st.trackerCollapsed = collapse state of the tracker last seen; st.override = own choice while the tracker is collapsed
-- (cleared as soon as the tracker's state changes); st.lastRect = last usable tracker rectangle; st.lastName = last target
Dock.state = st

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function safe(fn, ...)
  if ns.Core and ns.Core.safe then return ns.Core.safe(fn, ...) end
  return pcall(fn, ...)
end

local function call(obj, method)
  if type(obj) ~= "table" or type(obj[method]) ~= "function" then return nil end
  local ok, v = pcall(obj[method], obj)
  if not ok then return nil end
  return v
end

local function visible(f)
  if type(f) ~= "table" then return false end
  local v
  if type(f.IsVisible) == "function" then v = call(f, "IsVisible") else v = call(f, "IsShown") end
  return v == true
end

local function screenSize()
  local sw = UIParent and num(call(UIParent, "GetWidth")) or nil
  local sh = UIParent and num(call(UIParent, "GetHeight")) or nil
  return (sw and sw > 0) and sw or 1920, (sh and sh > 0) and sh or 1080
end

local function color(key)
  local C = rawget(_G, "OBJECTIVE_TRACKER_COLOR")
  local c = type(C) == "table" and C[key]
  if type(c) == "table" and num(c.r) and num(c.g) and num(c.b) then return c.r, c.g, c.b, 1 end
  local d = Dock.COLOR[key] or Dock.COLOR.Normal
  return d[1], d[2], d[3], d[4] or 1
end

local function hasAtlas(name)
  local CT = rawget(_G, "C_Texture")
  if type(CT) ~= "table" or type(CT.GetAtlasInfo) ~= "function" then return false end
  local ok, info = pcall(CT.GetAtlasInfo, name)
  return ok and type(info) == "table"
end

local function useAtlas(tex, name)
  if not hasAtlas(name) or type(tex.SetAtlas) ~= "function" then return false end
  local ok, res = pcall(tex.SetAtlas, tex, name, false)
  return ok and res ~= false
end

-- Blizzard's font objects follow the tracker's text size option; without them (other clients, tests) the addon's text font
local function trackerFont(fs, objName, size)
  local obj = rawget(_G, objName)
  if type(obj) == "table" then
    if type(fs.SetFontObject) == "function" and pcall(fs.SetFontObject, fs, obj) then return objName end
    if type(obj.GetFont) == "function" then
      local ok, file, sz, flags = pcall(obj.GetFont, obj)
      if ok and type(file) == "string" and num(sz) then
        fs:SetFont(file, sz, flags or "")
        return objName
      end
    end
  end
  TT.setFont(fs, "text", size)
  return nil
end

-- Settings ------------------------------------------------------------------------------------------------------------------

function Dock.validSide(v) return v == "below" or v == "above" end

function Dock.enabled()
  local s = TT.settings()
  return s.dock == true
end

-- Target ----------------------------------------------------------------------------------------------------------------------

function Dock.findTarget()
  local found = {}
  for _, c in ipairs(Dock.TARGETS) do
    local f = rawget(_G, c.name)
    if type(f) == "table" and type(f.GetTop) == "function" and type(f.GetLeft) == "function" then
      found[#found + 1] = { kind = c.kind, name = c.name, frame = f }
    end
  end
  for _, t in ipairs(found) do
    if visible(t.frame) then return t end
  end
  -- none visible (no quests, tracker switched off): stay with the last one if it still exists, else the first by priority
  if st.lastName then
    for _, t in ipairs(found) do
      if t.name == st.lastName then return t end
    end
  end
  return found[1]
end

local function flag(f)
  if type(f) ~= "table" then return nil end
  local v = f.isCollapsed
  if v == nil then v = f.collapsed end
  if type(v) == "boolean" and not isSecret(v) then return v end
  return nil
end

function Dock.trackerCollapsed(t)
  if not t then return false end
  local ok, v = pcall(function()
    if t.kind == "questie" then
      local Q = rawget(_G, "Questie")
      local db = type(Q) == "table" and Q.db
      if type(db) ~= "table" then return false end
      for _, part in ipairs({ "char", "profile" }) do
        local p = db[part]
        if type(p) == "table" and type(p.isTrackerExpanded) == "boolean" then return not p.isTrackerExpanded end
      end
      return false
    end
    local c = flag(t.frame)
    if c == nil and t.kind == "kaliel" then c = flag(rawget(_G, "KT_ObjectiveTrackerFrame")) end
    return c == true
  end)
  return ok and v == true
end

-- Rectangle of the tracker in UIParent coordinates: left, top (outer top edge), bottom (bottom of the visible content), width.
-- A hidden tracker counts as zero height at its top edge (the section moves up to where the tracker starts).
function Dock.trackerRect(t)
  if not t then return nil end
  local f = t.frame
  local ues = num(call(UIParent, "GetEffectiveScale")) or 1
  local tes = num(call(f, "GetEffectiveScale")) or ues
  if ues <= 0 then ues = 1 end
  local k = tes / ues
  local left, top, width = num(call(f, "GetLeft")), num(call(f, "GetTop")), num(call(f, "GetWidth"))
  if not left or not top then return nil end
  local bottom
  if visible(f) then
    if t.kind == "blizzard" then
      local collapsed = Dock.trackerCollapsed(t)
      local header, nine = f.Header, f.NineSlice
      if collapsed and type(header) == "table" then bottom = num(call(header, "GetBottom")) end
      if not bottom and not collapsed and type(nine) == "table" and visible(nine) then bottom = num(call(nine, "GetBottom")) end
    end
    if not bottom then bottom = num(call(f, "GetBottom")) end
  end
  if not bottom or bottom > top then bottom = top end
  return { left = left * k, top = top * k, bottom = bottom * k, width = width and width * k or nil }
end

-- Section width: the tracker's width (clamped), else the fallback
function Dock.width(rect)
  local w = rect and num(rect.width)
  if not w or w <= 0 then w = Dock.W.fallback end
  return floor(max(Dock.W.min, min(Dock.W.max, w)) + 0.5)
end

-- Where the section goes: preferred side, the other one if the screen edge leaves too little room (if neither fits, the
-- preferred one). Returns point, x, y (for SetPoint(point, UIParent, "BOTTOMLEFT", x, y)) and the side used.
function Dock.anchorFor(rect, w, h, side)
  local sw, sh = screenSize()
  if not rect then
    local x = sw - w - 40
    return "TOPLEFT", floor(max(0, x) + 0.5), floor(sh - 250 + 0.5), "free"
  end
  local belowTop = rect.bottom - Dock.GAP
  local aboveBottom = rect.top + Dock.GAP
  local fits = { below = belowTop - h >= 0, above = aboveBottom + h <= sh }
  local other = side == "above" and "below" or "above"
  local use = side
  if not fits[side] and fits[other] then use = other end
  local x = floor(max(0, min(rect.left, sw - w)) + 0.5)
  if use == "above" then return "BOTTOMLEFT", x, floor(aboveBottom + 0.5), "above" end
  return "TOPLEFT", x, floor(belowTop + 0.5), "below"
end

-- Hooks (read-only post-hooks; they only schedule an update of our own frame for the next frame) --------------------------------

local pending = false
function Dock.poke()
  if pending then return end
  pending = true
  local function run()
    pending = false
    safe(Dock.update)
  end
  if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end

local function hookScript(f, name)
  if type(f) == "table" and type(f.HookScript) == "function" then pcall(f.HookScript, f, name, Dock.poke) end
end

function Dock.hook(t)
  if not t or st.hooked[t.frame] then return end
  local f = t.frame
  st.hooked[f] = true
  if type(f.SetCollapsed) == "function" and type(hooksecurefunc) == "function" then pcall(hooksecurefunc, f, "SetCollapsed", Dock.poke) end
  for _, name in ipairs({ "OnShow", "OnHide", "OnSizeChanged" }) do hookScript(f, name) end
  if type(f.NineSlice) == "table" then hookScript(f.NineSlice, "OnSizeChanged") end
end

-- Frame -------------------------------------------------------------------------------------------------------------------------

local function rowTooltip(row)
  local r = row.data
  if not r or not GameTooltip then return end
  GameTooltip:SetOwner(row, "ANCHOR_LEFT")
  GameTooltip:AddLine(r.text, 1, 0.82, 0, true)
  local kind = T.kind[r.kind]
  if kind then GameTooltip:AddLine(r.extra and (kind .. " · " .. r.extra) or kind, 0.9, 0.9, 0.9) end
  GameTooltip:AddLine(T.rowHint, 0.6, 0.75, 1, true)
  GameTooltip:Show()
end

local function paintRow(row)
  local r = row.data
  if r and r.done then
    row.text:SetTextColor(color("Complete"))
  elseif row.hover then
    row.text:SetTextColor(color("Highlight"))
  else
    row.text:SetTextColor(color("Normal"))
  end
end

local function buildRow(i)
  local row = CreateFrame("Button", nil, st.frame)
  row:RegisterForClicks("LeftButtonUp")
  row.nub = row:CreateTexture(nil, "ARTWORK")
  row.nubAtlas = useAtlas(row.nub, Dock.ATLAS.nub)
  row.dash = TT.fontString(row)
  row.dash:SetText("-")
  row.text = TT.fontString(row)
  row.text:SetJustifyH("LEFT")
  if row.text.SetJustifyV then row.text:SetJustifyV("TOP") end
  row.text:SetWordWrap(true)
  if row.text.SetMaxLines then row.text:SetMaxLines(2) end
  row:SetScript("OnClick", function()
    if GameTooltip then GameTooltip:Hide() end
    safe(TT.openBook)
  end)
  row:SetScript("OnEnter", function(self)
    self.hover = true
    paintRow(self)
    rowTooltip(self)
  end)
  row:SetScript("OnLeave", function(self)
    self.hover = false
    paintRow(self)
    if GameTooltip then GameTooltip:Hide() end
  end)
  row:Hide()
  st.rows[i] = row
  return row
end

local function headTooltip(owner)
  if not GameTooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  GameTooltip:AddLine(Dock.collapsed() and T.dockExpand or T.dockCollapse, 1, 0.82, 0)
  GameTooltip:AddLine(T.dockToggleHint, 0.8, 0.8, 0.8, true)
  GameTooltip:Show()
end

function Dock.build()
  if st.frame then return st.frame end
  local f = CreateFrame("Frame", Dock.NAME, UIParent)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:EnableMouse(false)
  if f.SetDontSavePosition then f:SetDontSavePosition(true) end
  f:Hide()
  st.frame = f

  local head = CreateFrame("Button", nil, f)
  head:RegisterForClicks("LeftButtonUp")
  head:SetHeight(Dock.HEAD_H)
  head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  head.bg = head:CreateTexture(nil, "BACKGROUND")
  head.bg:SetAllPoints(head)
  head.atlas = useAtlas(head.bg, Dock.ATLAS.header)
  if not head.atlas then head.bg:SetColorTexture(0, 0, 0, 0) end
  head.line = head:CreateTexture(nil, "BORDER")
  head.line:SetColorTexture(color("line"))
  head.line:SetHeight(1)
  head.line:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 2)
  head.line:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, 2)
  head.line:SetShown(not head.atlas)
  head.text = TT.fontString(head)
  head.text:SetJustifyH("LEFT")
  head.text:SetWordWrap(false)
  head.text:SetPoint("LEFT", head, "LEFT", 7, 0)
  head.font = trackerFont(head.text, "ObjectiveTrackerHeaderFont", 14)
  head:SetScript("OnClick", function()
    if GameTooltip then GameTooltip:Hide() end
    safe(Dock.toggle)
  end)
  head:SetScript("OnEnter", function(self) headTooltip(self) end)
  head:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  st.head = head

  local btn = CreateFrame("Button", nil, head)
  btn:SetSize(16, 16)
  btn:RegisterForClicks("LeftButtonUp")
  btn:SetPoint("RIGHT", head, "RIGHT", -1, 0)
  btn.tex = btn:CreateTexture(nil, "ARTWORK")
  btn.tex:SetAllPoints(btn)
  btn.atlas = hasAtlas(Dock.ATLAS.collapse) and hasAtlas(Dock.ATLAS.expand)
  btn.label = TT.fontString(btn)
  btn.label:SetPoint("CENTER", btn, "CENTER", 0, 0)
  TT.setFont(btn.label, "text", 14)
  btn.label:SetShown(not btn.atlas)
  btn:SetScript("OnClick", function()
    if GameTooltip then GameTooltip:Hide() end
    safe(Dock.toggle)
  end)
  btn:SetScript("OnEnter", function(self) headTooltip(self) end)
  btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  st.button = btn

  st.more = TT.fontString(f)
  st.more:SetJustifyH("LEFT")
  st.more:SetWordWrap(false)
  st.empty = TT.fontString(f)
  st.empty:SetJustifyH("LEFT")
  st.empty:SetWordWrap(true)

  f:SetScript("OnUpdate", function(_, dt)
    st.poll = st.poll + (num(dt) or 0)
    if st.poll < Dock.POLL then return end
    st.poll = 0
    safe(Dock.update)
  end)
  return f
end

function Dock.collapsed()
  if st.override ~= nil then return st.override end
  return st.trackerCollapsed == true or TT.settings().dockCollapsed == true
end

-- Follow the tracker's collapse state; a change clears the own choice made while it was collapsed. True if it changed.
function Dock.syncCollapse(t)
  local c = Dock.trackerCollapsed(t)
  if c ~= st.trackerCollapsed then
    local first = st.trackerCollapsed == nil
    st.trackerCollapsed = c
    if not first then st.override = nil end
    return true
  end
  return false
end

function Dock.toggle()
  local now = Dock.collapsed()
  if st.trackerCollapsed then
    st.override = not now
  else
    st.override = nil
    TT.set("dockCollapsed", not now)
  end
  st.sig = nil
  Dock.layout()
  Dock.place()
  return not now
end

local function lineText(r)
  local text = r.text or ""
  if r.extra and r.extra ~= "" then
    if r.dist then return text .. " (" .. r.extra .. ")" end
    return r.extra .. " " .. text
  end
  return text
end
Dock.lineText = lineText

function Dock.layout()
  local f = st.frame
  if not f then return end
  local rect = st.rect
  local w = Dock.width(rect)
  f:SetWidth(w)
  local closed = Dock.collapsed()
  local list = st.list or {}
  local open = 0
  for _, r in ipairs(list) do if not r.done then open = open + 1 end end
  st.head.text:SetText(closed and string.format(T.dockHeadCount, T.title, open) or T.title)
  st.head.text:SetTextColor(color("Header"))
  st.head.text:SetWidth(max(40, w - 30))
  local b = st.button
  if b.atlas then
    useAtlas(b.tex, closed and Dock.ATLAS.expand or Dock.ATLAS.collapse)
  else
    b.label:SetText(closed and "+" or "-")
    b.label:SetTextColor(color("Header"))
  end
  local y = Dock.HEAD_H + 2
  local used, hasDist = 0, false
  local lineFont
  for i = 1, max(#st.rows, min(#list, TT.ROWS_MAX)) do
    local row, r = st.rows[i], list[i]
    if not row and r and i <= TT.ROWS_MAX then row = buildRow(i) end
    if row then
      if r and not closed and i <= TT.ROWS_MAX then
        row.data = r
        lineFont = trackerFont(row.text, "ObjectiveTrackerLineFont", 12)
        trackerFont(row.dash, "ObjectiveTrackerLineFont", 12)
        local tw = max(40, w - Dock.INDENT - 4)
        row.text:SetWidth(tw)
        row.text:SetText(lineText(r))
        local _, size = row.text:GetFont()
        size = num(size) or 12
        local lineH = math.ceil(size * 1.2)
        local th = num(row.text:GetStringHeight()) or lineH
        if th <= 0 then th = lineH end
        th = min(th, 2 * lineH)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
        row:SetSize(w, th + Dock.ROW_GAP)
        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", row, "TOPLEFT", Dock.INDENT, 0)
        row.text:SetHeight(th)
        local doneMark = r.done and useAtlas(row.nub, Dock.ATLAS.check)
        if not r.done and row.nubAtlas then useAtlas(row.nub, Dock.ATLAS.nub) end
        local icon = doneMark or row.nubAtlas
        row.nub:ClearAllPoints()
        row.nub:SetSize(doneMark and 14 or 10, doneMark and 14 or 10)
        row.nub:SetPoint("TOPRIGHT", row, "TOPLEFT", Dock.INDENT - 3, -floor((lineH - (doneMark and 14 or 10)) / 2))
        row.nub:SetShown(icon and true or false)
        row.dash:ClearAllPoints()
        row.dash:SetPoint("TOPRIGHT", row, "TOPLEFT", Dock.INDENT - 5, 0)
        row.dash:SetShown(not icon)
        row.dash:SetTextColor(color(r.done and "Complete" or "Normal"))
        paintRow(row)
        row:Show()
        if r.dist and not r.done then hasDist = true end
        y = y + th + Dock.ROW_GAP
        used = i
      else
        row.data = nil
        row:Hide()
      end
    end
  end
  local rest = closed and 0 or (#list - used)
  if rest > 0 then
    trackerFont(st.more, "ObjectiveTrackerLineFont", 12)
    st.more:ClearAllPoints()
    st.more:SetPoint("TOPLEFT", f, "TOPLEFT", Dock.INDENT, -y)
    st.more:SetText(string.format(T.more, rest))
    st.more:SetTextColor(color("Complete"))
    st.more:Show()
    y = y + 14
  else
    st.more:SetText("")
    st.more:Hide()
  end
  if #list == 0 and not closed then
    trackerFont(st.empty, "ObjectiveTrackerLineFont", 12)
    st.empty:ClearAllPoints()
    st.empty:SetPoint("TOPLEFT", f, "TOPLEFT", Dock.INDENT, -y)
    st.empty:SetWidth(max(40, w - Dock.INDENT - 4))
    st.empty:SetText(T.empty)
    st.empty:SetTextColor(color("Complete"))
    st.empty:Show()
    y = y + 16
  else
    st.empty:SetText("")
    st.empty:Hide()
  end
  local h = closed and Dock.HEAD_H or (y + Dock.PAD_B)
  f:SetHeight(floor(h + 0.5))
  st.used, st.rest, st.hasDist, st.lineFont, st.closed = used, rest, hasDist, lineFont, closed
end

-- Place our frame next to the tracker (only our own frame gets points, relative to UIParent)
function Dock.place()
  local f = st.frame
  if not f then return end
  local t = st.target
  local rect = Dock.trackerRect(t)
  if rect then st.lastRect = rect else rect = st.lastRect end
  st.rect = rect
  local w, h = num(f:GetWidth()) or Dock.width(rect), num(f:GetHeight()) or Dock.HEAD_H
  local point, x, y, side = Dock.anchorFor(rect, w, h, TT.settings().dockSide)
  local sig = point .. ":" .. x .. ":" .. y
  st.side = side
  if sig == st.placed then return end
  st.placed = sig
  f:ClearAllPoints()
  f:SetPoint(point, UIParent, "BOTTOMLEFT", x, y)
end

-- Poll / hook step: target changed, collapse state, width or position
function Dock.update()
  local f = st.frame
  if not (f and f:IsShown()) then return end
  local t = Dock.findTarget()
  if (t and t.frame) ~= (st.target and st.target.frame) then
    st.target = t
    Dock.hook(t)
  end
  if t then st.lastName = t.name end
  local changed = Dock.syncCollapse(t)
  local rect = Dock.trackerRect(t) or st.lastRect
  if Dock.width(rect) ~= Dock.width(st.rect) then changed = true end
  st.rect = rect
  if changed then Dock.layout() end
  Dock.place()
end

function Dock.render(list)
  local f = Dock.build()
  st.list = list or {}
  local t = Dock.findTarget()
  st.target = t
  if t then
    st.lastName = t.name
    Dock.hook(t)
  end
  Dock.syncCollapse(t)
  st.rect = Dock.trackerRect(t) or st.lastRect
  Dock.layout()
  st.placed = nil
  Dock.place()
  f:Show()
  return true
end

function Dock.hide()
  if st.frame then st.frame:Hide() end
end

function Dock.isShown()
  return st.frame ~= nil and st.frame:IsShown() and true or false
end

function Dock.hasDist()
  return Dock.isShown() and st.hasDist == true
end
