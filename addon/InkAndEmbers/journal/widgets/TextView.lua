-- Long-text widget: word-wrapped FontString in a clipped frame, scrolled by moving the text. The mouse wheel is
-- only active while the text is longer than the window (otherwise the page gets it for flipping).
local _, ns = ...

local Widgets = ns.Journal.Widgets

local floor, max, min = math.floor, math.max, math.min

local TextView = {}
TextView.__index = TextView

local BAR_W = 5

function Widgets.NewTextView(parent, opts)
  opts = type(opts) == "table" and opts or {}
  local self = setmetatable({ opts = opts, offset = 0, shown = "" }, TextView)
  self.width, self.height = tonumber(opts.width) or 300, tonumber(opts.height) or 120
  self.size = tonumber(opts.size) or 13
  self.spacing = tonumber(opts.spacing) or 3
  self.step = tonumber(opts.step) or (self.size + self.spacing) * 3

  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(self.width, self.height)
  f:SetClipsChildren(true)
  f:SetScript("OnMouseWheel", function(_, delta)
    self:Scroll(-(tonumber(delta) or 0) * self.step)
  end)
  self.frame = f

  local fs = Widgets.font(f, opts.font or "text", self.size, opts.color or "ink")
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  fs:SetWordWrap(true)
  if fs.SetSpacing then fs:SetSpacing(self.spacing) end
  self.text = fs

  local track = f:CreateTexture(nil, "ARTWORK")
  track:SetColorTexture(Widgets.color("sepia", 0.2))
  track:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  track:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  track:SetWidth(3)
  self.track = track
  local thumb = CreateFrame("Button", nil, f)
  thumb:SetWidth(BAR_W)
  local tt = thumb:CreateTexture(nil, "OVERLAY")
  tt:SetAllPoints(thumb)
  tt:SetColorTexture(Widgets.color("sepia", 0.75))
  thumb:SetScript("OnMouseDown", function() self:BeginDrag() end)
  thumb:SetScript("OnMouseUp", function() self:EndDrag() end)
  thumb:SetScript("OnHide", function() self:EndDrag() end)
  self.thumb = thumb

  self:Resize(self.width, self.height)
  return self
end

function TextView:Resize(w, h)
  self.width, self.height = tonumber(w) or self.width, tonumber(h) or self.height
  self.frame:SetSize(self.width, self.height)
  self:Place()
end

function TextView:TextWidth()
  return max(20, self.width - BAR_W - 6 - (self.inset or 0))
end

function TextView:SetInset(px)
  px = max(0, tonumber(px) or 0)
  if px == (self.inset or 0) then return end
  self.inset = px
  self:Place()
end

function TextView:SetAccessory(frame, inset)
  self.accessory, self.accessoryInset = frame, tonumber(inset) or 0
  if frame.SetParent then frame:SetParent(self.frame) end
  self:Place()
end

function TextView:Place()
  self.text:SetWidth(self:TextWidth())
  self.text:ClearAllPoints()
  self.text:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, self.offset)
  local a = self.accessory
  if a then
    a:ClearAllPoints()
    a:SetPoint("TOPLEFT", self.text, "TOPLEFT", self:TextWidth() + 2, 1)
  end
  self:UpdateBar()
end

function TextView:TextHeight()
  local h = self.text.GetStringHeight and self.text:GetStringHeight()
  if type(h) ~= "number" or h ~= h or h < 0 then return 0 end
  return h
end

function TextView:MaxOffset()
  return max(0, floor(self:TextHeight() - self.height + 0.5))
end

function TextView:Scrollable() return self:MaxOffset() > 0 end

function TextView:GetOffset() return self.offset end

function TextView:SetOffset(px)
  px = tonumber(px) or 0
  if px ~= px then px = 0 end
  px = max(0, min(floor(px), self:MaxOffset()))
  if px == self.offset then return end
  self.offset = px
  self:Place()
end

function TextView:Scroll(px)
  self:SetOffset(self.offset + (tonumber(px) or 0))
end

function TextView:GetText() return self.shown end

function TextView:SetText(text, keepOffset)
  local shown = type(text) == "string" and text or (type(self.opts.empty) == "string" and self.opts.empty or "")
  self.shown = shown
  Widgets.setText(self.text, shown)
  if not keepOffset then self.offset = 0 end
  self.offset = min(self.offset, self:MaxOffset())
  self:Place()
end

function TextView:UpdateBar()
  local maxOff = self:MaxOffset()
  self.frame:EnableMouseWheel(maxOff > 0)
  if maxOff == 0 then
    self.thumb:Hide()
    self.track:Hide()
    return
  end
  self.track:Show()
  self.thumb:Show()
  local total = self:TextHeight()
  local th = max(12, floor(self.height * self.height / max(1, total)))
  local y = floor((self.height - th) * self.offset / maxOff)
  self.thumb:SetHeight(th)
  self.thumb:ClearAllPoints()
  self.thumb:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 1, -y)
end

function TextView:BeginDrag()
  if type(GetCursorPosition) ~= "function" then return end
  local _, cy = GetCursorPosition()
  local scale = self.frame.GetEffectiveScale and self.frame:GetEffectiveScale() or 1
  if type(cy) ~= "number" or type(scale) ~= "number" or scale <= 0 then return end
  self.dragY, self.dragOffset, self.dragScale = cy / scale, self.offset, scale
  self.thumb:SetScript("OnUpdate", function()
    local _, y = GetCursorPosition()
    if type(y) ~= "number" then return end
    local th = max(12, floor(self.height * self.height / max(1, self:TextHeight())))
    local span = self.height - th
    if span <= 0 then return end
    local dy = self.dragY - y / self.dragScale
    self:SetOffset(self.dragOffset + dy / span * self:MaxOffset())
  end)
end

function TextView:EndDrag()
  if self.thumb then self.thumb:SetScript("OnUpdate", nil) end
  self.dragY = nil
end
