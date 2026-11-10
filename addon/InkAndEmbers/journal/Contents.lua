-- Table of contents of the journey (K4, 10.11.2026): the left
-- page of Reise › Akte. "INHALT" with a summary line, then up to three volumes (Band I / II / III = level bands 1–20 / 21–40 /
-- 41–60 by the act's start level; only volumes with acts; with a single volume its line is left out), the acts of the open volume
-- (small wax seal with the embossed number from Media/ActSeals, zone name, dot leader, "St. 1–13 · 17 Std. 52 Min.") and the
-- chapters of the open act, indented. Accordion: one volume and one act open. Clicks go to journal/Frame.lua (cb.onBand, onAct,
-- onChapter); hover shows the figures. If a volume is too long for the page, the list scrolls with the mouse wheel (fallback).
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Contents = {}
Journal.Contents = Contents

local floor, max, min = math.floor, math.max, math.min

Contents.TEXT = ns.Locale.ns("Contents", {
  head = "Inhalt",
  acts_one = "%s Akt",
  acts_other = "%s Akte",
  chapters_one = "%s Kapitel",
  chapters_other = "%s Kapitel",
  levels = "Stufe %s",
  band = "Band %s",
  chapter = "Kapitel %s · %s",
  levelShort = "St. %s",
  tipPlayed = "Spielzeit: %s",
  tipLevels = "Stufe %s",
  tipKills = "Kills: %s",
  tipDeaths = "Tode: %s",
  tipQuests = "Quests: %s",
  tipMoments = "Momente: %s",
  tipClick = "Klick: Karte springt an den Anfang (ohne Abspielen)",
  tipBand = "Klick: Band aufschlagen",
  tipScroll = "Mausrad: weitere Einträge",
})

-- level bands of the volumes; acts above the last band belong to it
Contents.BANDS = { { 1, 20 }, { 21, 40 }, { 41, 60 } }
Contents.ROMAN = { "I", "II", "III" }
Contents.ROW = { band = 24, act = 22, chapter = 19 }
Contents.HEAD_H = 58
Contents.SEAL = 19
Contents.INDENT = 26
Contents.GAP = 6
Contents.POOL = 60

local function W() return Journal.Widgets end
local function int(n) return tostring(floor(tonumber(n) or 0)) end
local function T(k, ...) return Contents.TEXT(k, ...) end

function Contents.bandOf(level)
  level = tonumber(level) or 1
  for i, b in ipairs(Contents.BANDS) do
    if level <= b[2] then return i end
  end
  return #Contents.BANDS
end

local function span(from, to)
  from, to = tonumber(from), tonumber(to)
  if not from then return "" end
  if to and floor(to) > floor(from) then return int(from) .. "–" .. int(to) end
  return int(from)
end
Contents.span = span

-- volumes with their acts: { { index, roman, from, to, acts = { act indices } } } (only volumes with acts, in order)
function Contents.bands(model)
  local out, byIndex = {}, {}
  for n, a in ipairs(type(model) == "table" and model.acts or {}) do
    local b = Contents.bandOf(a.levelFrom)
    local e = byIndex[b]
    if not e then
      local B = Contents.BANDS[b]
      e = { index = b, roman = Contents.ROMAN[b], from = B[1], to = B[2], acts = {} }
      byIndex[b] = e
      out[#out + 1] = e
    end
    e.acts[#e.acts + 1] = n
  end
  table.sort(out, function(x, y) return x.index < y.index end)
  return out
end

function Contents.summary(model)
  local acts, chs = #(model.acts or {}), #(model.chapters or {})
  local L = ns.Locale
  local bits = { T(L.plural(acts, "acts_one", "acts_other"), int(acts)), T(L.plural(chs, "chapters_one", "chapters_other"), int(chs)) }
  local tot = model.total
  if tot and tot.levelFrom then bits[#bits + 1] = T("levels", span(tot.levelFrom, tot.levelTo)) end
  local h = model.header
  if h and type(h.playedText) == "string" then bits[#bits + 1] = h.playedText end
  return table.concat(bits, " · ")
end

-- flat list of the visible lines for state { band = open volume, act = open act, selAct, selChapter }:
-- { kind = "band"|"act"|"chapter", index, text, right, open, selected, depth, roman }
function Contents.rows(model, state)
  state = state or {}
  local out = {}
  local bands = Contents.bands(model)
  local single = #bands <= 1
  for _, b in ipairs(bands) do
    local openBand = single or b.index == state.band
    if not single then
      local L = ns.Locale
      out[#out + 1] = { kind = "band", index = b.index, text = T("band", b.roman), open = openBand, depth = 0,
        right = T("levels", b.from .. "–" .. b.to) .. " · " .. T(L.plural(#b.acts, "acts_one", "acts_other"), int(#b.acts)) }
    end
    if openBand then
      for _, n in ipairs(b.acts) do
        local a = model.acts[n]
        local openAct = n == state.act
        local st = a.stats or {}
        out[#out + 1] = { kind = "act", index = n, roman = a.roman, text = a.zoneName or a.title or "", open = openAct,
          selected = n == state.selAct and not state.selChapter, depth = single and 0 or 1,
          right = T("levelShort", span(a.levelFrom, a.levelTo)) .. (st.playedText and (" · " .. st.playedText) or "") }
        if openAct then
          for _, i in ipairs(a.chapters or {}) do
            local c = model.chapters[i]
            if c then
              out[#out + 1] = { kind = "chapter", index = i, text = T("chapter", c.roman or int(i), c.zoneName or ""),
                selected = i == state.selChapter, depth = (single and 0 or 1) + 1,
                right = c.stats and c.stats.playedText or "" }
            end
          end
        end
      end
    end
  end
  return out
end

-- tooltip lines of an act or chapter (the figures of the former value card)
function Contents.tip(model, kind, index)
  local e = kind == "act" and model.acts[index] or model.chapters[index]
  if not e then return nil end
  local st = e.stats or {}
  local lines = { e.title or "" }
  if kind == "chapter" and e.zoneName then lines[1] = T("chapter", e.roman or int(index), e.zoneName) end
  lines[#lines + 1] = T("tipLevels", span(e.levelFrom, e.levelTo))
  if st.playedText then lines[#lines + 1] = T("tipPlayed", st.playedText) end
  lines[#lines + 1] = T("tipQuests", int(st.quests)) .. " · " .. T("tipKills", int(st.kills)) .. " · " .. T("tipDeaths", int(st.deaths))
  if (st.moments or 0) > 0 then lines[#lines + 1] = T("tipMoments", int(st.moments)) end
  if type(e.story) == "string" and e.story ~= "" then lines[#lines + 1] = e.story end
  if type(e.detourText) == "string" then lines[#lines + 1] = e.detourText end
  lines[#lines + 1] = T("tipClick")
  return lines
end

local function strW(fs, text)
  fs:SetText(text or "")
  return tonumber(fs:GetStringWidth()) or 0
end

local function newRow(ui)
  local D = W().Diary
  local Theme = Journal.Theme
  local b = CreateFrame("Button", nil, ui.list)
  b:SetHeight(Contents.ROW.act)
  b.name = Theme.fontString(b, "text", 14, Theme.C.ink, "OVERLAY", "LEFT")
  b.name:SetWordWrap(false)
  b.right = Theme.fontString(b, "label", 12, Theme.C.sepia, "OVERLAY", "RIGHT")
  b.right:SetWordWrap(false)
  b.dots = Theme.fontString(b, "label", 12, Theme.C.sepia, "OVERLAY", "LEFT")
  b.dots:SetWordWrap(false)
  b.seal = b:CreateTexture(nil, "ARTWORK")
  b.seal:SetTexture(Theme.TEX.actSeals)
  b.seal:SetSize(Contents.SEAL, Contents.SEAL)
  b.sealNum = Theme.fontString(b, "title", 7, { 0.30, 0.05, 0.04 }, "OVERLAY", "CENTER")
  b.mark = D.mark(b, "next", 12, "red")
  b:SetScript("OnClick", function(self)
    local cb = ui.cb
    local fn = cb and cb["on" .. (self.kind == "band" and "Band" or self.kind == "act" and "Act" or "Chapter")]
    if fn then fn(self.index) end
  end)
  b:SetScript("OnEnter", function(self)
    self.hover = true
    Contents.paint(self)
    local lines = self.kind ~= "band" and ui.model and Contents.tip(ui.model, self.kind, self.index) or { self.name:GetText(), T("tipBand") }
    -- extra lines from the frame (zone progress of the line's zone), before the click hint
    local extra
    if self.kind ~= "band" and lines and type(ui.cb.tipExtra) == "function" then
      local ok, res = pcall(ui.cb.tipExtra, self.kind, self.index)
      extra = ok and res or nil
    end
    if type(extra) == "table" then
      for _, l in ipairs(extra) do table.insert(lines, #lines, l) end
    end
    if lines then W().tip(self, lines) end
  end)
  b:SetScript("OnLeave", function(self)
    self.hover = false
    Contents.paint(self)
    W().hideTip(self)
  end)
  return b
end

-- colour of a line: selected or hovered red, open volume/act ink, the rest ink (chapters a little lighter)
function Contents.paint(b)
  local red = b.selected or b.hover
  local col = red and "red" or ((b.kind == "chapter" and not b.selected) and "sepia" or "ink")
  b.name:SetTextColor(W().color(col))
  b.mark:SetShown(b.selected and true or false)
end

function Contents.create(parent, x, y, w, h, cb)
  local D, Theme = W().Diary, Journal.Theme
  local ui = { cb = cb or {}, rows = {}, w = w, h = h, offset = 0 }
  local f = CreateFrame("Frame", nil, parent)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  f:SetSize(w, h)
  ui.frame = f
  local head = Theme.fontString(f, "title", 28, Theme.C.ink, "OVERLAY", "LEFT")
  head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  head:SetText(Contents.TEXT.head)
  ui.head = head
  local sum = Theme.fontString(f, "label", 12, Theme.C.sepia, "OVERLAY", "LEFT")
  sum:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -36)
  sum:SetWidth(w)
  sum:SetWordWrap(false)
  ui.sum = sum
  local rule = D.NewInkStroke(f, nil, "red", 0.35)
  rule:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(Contents.HEAD_H - 6))
  rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(Contents.HEAD_H - 6))
  ui.rule = rule
  local list = CreateFrame("Frame", nil, f)
  list:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -Contents.HEAD_H)
  list:SetSize(w, h - Contents.HEAD_H)
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, delta)
    if type(delta) ~= "number" or not ui.scroll then return end
    ui.offset = max(0, min(ui.maxOffset or 0, ui.offset - (delta > 0 and 1 or -1)))
    Contents.layout(ui)
  end)
  ui.list = list
  ui.measure = Theme.fontString(f, "label", 12, Theme.C.sepia, "OVERLAY", "LEFT")
  ui.measure:Hide()
  f:Hide()
  return ui
end

local function rowHeight(e) return Contents.ROW[e.kind] or Contents.ROW.act end

-- fill and place the lines; -> height used (header + lines)
function Contents.set(ui, model, state)
  ui.model = model
  ui.entries = Contents.rows(model, state)
  ui.sum:SetText(Contents.summary(model))
  W().fitLine(ui.sum, ui.w, 10)
  -- scroll fallback: keep the selected/open line in view when the list is longer than the page
  local total = 0
  for _, e in ipairs(ui.entries) do total = total + rowHeight(e) end
  local room = ui.h - Contents.HEAD_H
  ui.scroll = total > room
  if not ui.scroll then
    ui.offset = 0
  else
    local focus
    for k, e in ipairs(ui.entries) do if e.selected or (e.kind == "act" and e.open) then focus = k end end
    local need, k0 = 0, 1
    for k = #ui.entries, 1, -1 do
      need = need + rowHeight(ui.entries[k])
      if need > room then k0 = k + 1 break end
    end
    ui.maxOffset = max(0, k0 - 1)
    if state and state.follow and focus then ui.offset = max(0, min(ui.maxOffset, focus - 3)) end
    ui.offset = min(ui.offset or 0, ui.maxOffset)
  end
  return Contents.layout(ui)
end

function Contents.layout(ui)
  local Theme = Journal.Theme
  local room = ui.h - Contents.HEAD_H
  local y, used = 0, 0
  for k, e in ipairs(ui.entries or {}) do
    local rh = rowHeight(e)
    if k > (ui.offset or 0) and y + rh > room then break end
    local visible = k > (ui.offset or 0)
    local b = ui.rows[used + 1]
    if visible then
      used = used + 1
      if not b then
        if used > Contents.POOL then break end
        b = newRow(ui)
        ui.rows[used] = b
      end
      b.kind, b.index, b.selected = e.kind, e.index, e.selected
      local x = e.depth * Contents.INDENT
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", ui.list, "TOPLEFT", x, -y)
      b:SetSize(ui.w - x, rh)
      local size = e.kind == "band" and 16 or (e.kind == "act" and 14 or 13)
      Theme.font(b.name, e.kind == "band" and "title" or "text", size, Theme.C.ink)
      local nameX = 0
      if e.kind == "act" then
        local S = Theme.ACT_SEALS
        local n = tonumber(e.index) or 0
        b.seal:SetTexCoord(Theme.actSealCoords((n >= 1 and n <= S.count) and (n - 1) or S.empty))
        b.seal:ClearAllPoints()
        b.seal:SetPoint("LEFT", b, "LEFT", 0, 0)
        b.seal:Show()
        -- from act XXXI on: the empty seal with the number pressed in (dark letters)
        b.sealNum:SetText((n > S.count) and tostring(e.roman or "") or "")
        b.sealNum:ClearAllPoints()
        b.sealNum:SetPoint("CENTER", b.seal, "CENTER", 0, 0)
        b.sealNum:SetShown(n > S.count)
        nameX = Contents.SEAL + 6
      else
        b.seal:Hide()
        b.sealNum:Hide()
        if e.kind == "chapter" then nameX = 14 end
      end
      b.mark:ClearAllPoints()
      b.mark:SetPoint("LEFT", b, "LEFT", 0, 0)
      b.name:ClearAllPoints()
      b.name:SetPoint("LEFT", b, "LEFT", nameX, 0)
      b.right:ClearAllPoints()
      b.right:SetPoint("RIGHT", b, "RIGHT", 0, 0)
      b.right:SetText(e.right or "")
      local rw = tonumber(b.right:GetStringWidth()) or 0
      local avail = (ui.w - x) - nameX - rw - 12
      b.name:SetText(e.text)
      W().fitLine(b.name, max(40, avail), 10)
      local nw = min(tonumber(b.name:GetStringWidth()) or 0, max(40, avail))
      -- dot leader between name and figures
      local gap = (ui.w - x) - nameX - nw - rw - 8
      local dw = strW(ui.measure, ". ")
      local count = (dw > 0 and gap > dw) and floor(gap / dw) or 0
      b.dots:SetText(string.rep(". ", count))
      b.dots:ClearAllPoints()
      b.dots:SetPoint("RIGHT", b.right, "LEFT", -4, 0)
      b.dots:SetShown(count > 0)
      Contents.paint(b)
      b:Show()
      y = y + rh
    end
  end
  for k = used + 1, #ui.rows do ui.rows[k]:Hide() end
  ui.shown = used
  ui.height = Contents.HEAD_H + y
  return ui.height
end

function Contents.setShown(ui, on)
  if ui and ui.frame then ui.frame:SetShown(on and true or false) end
end
