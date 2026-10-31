-- Pool list widget: fixed number of visible rows (max Widgets.LIMITS.listRows), any number of items.
-- Scrolling refills the rows. No OnUpdate except while the bar is dragged.
local _, ns = ...

local Widgets = ns.Journal.Widgets

local floor, max, min = math.floor, math.max, math.min

local TX = ns.Locale.ns("w.List", { notReadable = "Eintrag nicht lesbar" })

local List = {}
List.__index = List

local function clampRows(n)
  n = tonumber(n) or 12
  n = floor(n)
  if n < 1 then n = 1 end
  if n > Widgets.LIMITS.listRows then n = Widgets.LIMITS.listRows end
  return n
end

function Widgets.NewList(parent, opts)
  opts = type(opts) == "table" and opts or {}
  local self = setmetatable({}, List)
  self.opts = opts
  self.nRows = clampRows(opts.rows)
  self.rowHeight = tonumber(opts.rowHeight) or 18
  self.step = tonumber(opts.step) or 3
  self.items, self.offset, self.rows = {}, 0, {}

  local f = CreateFrame("Frame", nil, parent)
  self.frame = f
  local w = tonumber(opts.width) or (Widgets.size(parent, 300, 0))
  self.width = w
  f:SetSize(w, self.nRows * self.rowHeight)
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta)
    self:Scroll(-(tonumber(delta) or 0) * self.step)
  end)

  local track = f:CreateTexture(nil, "ARTWORK")
  track:SetColorTexture(Widgets.color("sepia", 0.2))
  track:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  track:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  track:SetWidth(3)
  self.track = track
  local thumb = CreateFrame("Button", nil, f)
  thumb:SetWidth(5)
  local tt = thumb:CreateTexture(nil, "OVERLAY")
  tt:SetAllPoints(thumb)
  tt:SetColorTexture(Widgets.color("sepia", 0.75))
  thumb:SetScript("OnMouseDown", function() self:BeginDrag() end)
  thumb:SetScript("OnMouseUp", function() self:EndDrag() end)
  thumb:SetScript("OnHide", function() self:EndDrag() end)
  self.thumb = thumb

  local hand = opts.emptyHand and Widgets.Diary and Widgets.Diary.emptyNote
  local empty = hand and hand(f, w - 12, 18) or Widgets.font(f, "text", 12, "sepia")
  empty:SetPoint("TOPLEFT", f, "TOPLEFT", 4, hand and -2 or -4)
  empty:SetWidth(w - 12)
  empty:SetJustifyH("LEFT")
  self.emptyText = empty

  for i = 1, self.nRows do
    local row = CreateFrame("Button", nil, f)
    row:SetSize(w - 10, self.rowHeight)
    row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(i - 1) * self.rowHeight)
    local label = Widgets.font(row, "text", 12, "ink")
    label:SetPoint("LEFT", row, "LEFT", 4, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    row.label = label
    row:SetScript("OnClick", function()
      local idx = row.index
      if idx and self.items[idx] ~= nil and type(opts.onClick) == "function" then
        Widgets.call(opts.onClick, self.items[idx], idx)
      end
    end)
    if type(opts.build) == "function" then Widgets.call(opts.build, row) end
    self.rows[i] = row
  end
  self:Refresh()
  return self
end

function List:MaxOffset()
  return max(0, #self.items - self.nRows)
end

function List:SetItems(items)
  self.items = type(items) == "table" and items or {}
  self.offset = min(self.offset, self:MaxOffset())
  self:Refresh()
end

function List:GetOffset() return self.offset end

function List:SetOffset(n)
  n = floor(tonumber(n) or 0)
  n = max(0, min(n, self:MaxOffset()))
  if n == self.offset then return end
  self.offset = n
  self:Refresh()
end

function List:Scroll(delta)
  self:SetOffset(self.offset + (tonumber(delta) or 0))
end

function List:ScrollTo(i)
  i = tonumber(i)
  if not i then return end
  if i <= self.offset then
    self:SetOffset(i - 1)
  elseif i > self.offset + self.nRows then
    self:SetOffset(i - self.nRows)
  end
end

function List:Refresh()
  local opts, n = self.opts, #self.items
  Widgets.setText(self.emptyText, n == 0 and opts.empty or "")
  for i, row in ipairs(self.rows) do
    local idx = self.offset + i
    local item = self.items[idx]
    if type(opts.clear) == "function" then Widgets.call(opts.clear, row) end
    if item ~= nil then
      row.index = idx
      row:Show()
      Widgets.setText(row.label, "")
      if type(opts.fill) == "function" then
        if not Widgets.call(opts.fill, row, item, idx) then
          if type(opts.clear) == "function" then Widgets.call(opts.clear, row) end
          Widgets.setText(row.label, TX.notReadable)
        end
      elseif type(item) == "string" then
        Widgets.setText(row.label, item)
      end
    else
      row.index = nil
      Widgets.setText(row.label, "")
      row:Hide()
    end
  end
  self:UpdateThumb()
end

function List:UpdateThumb()
  local total, maxOff = #self.items, self:MaxOffset()
  local h = self.nRows * self.rowHeight
  if maxOff == 0 then
    self.thumb:Hide()
    self.track:Hide()
    return
  end
  self.track:Show()
  self.thumb:Show()
  local th = max(12, floor(h * self.nRows / total))
  local y = floor((h - th) * self.offset / maxOff)
  self.thumb:SetHeight(th)
  self.thumb:ClearAllPoints()
  self.thumb:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 1, -y)
end

function List:BeginDrag()
  if type(GetCursorPosition) ~= "function" then return end
  local _, cy = GetCursorPosition()
  local scale = self.frame.GetEffectiveScale and self.frame:GetEffectiveScale() or 1
  if type(cy) ~= "number" or type(scale) ~= "number" or scale <= 0 then return end
  self.dragY, self.dragOffset, self.dragScale = cy / scale, self.offset, scale
  self.thumb:SetScript("OnUpdate", function()
    local _, y = GetCursorPosition()
    if type(y) ~= "number" then return end
    local h = self.nRows * self.rowHeight
    local th = max(12, floor(h * self.nRows / max(1, #self.items)))
    local span = h - th
    if span <= 0 then return end
    local dy = self.dragY - y / self.dragScale
    self:SetOffset(self.dragOffset + floor(dy / span * self:MaxOffset() + 0.5))
  end)
end

function List:EndDrag()
  if self.thumb then self.thumb:SetScript("OnUpdate", nil) end
  self.dragY = nil
end
