-- Chips widget: small buttons with text and count, wrapped left to right. Pooled, at most Widgets.LIMITS.chips.
local _, ns = ...

local Widgets = ns.Journal.Widgets

local Chips = {}
Chips.__index = Chips

local PAD = 7

function Widgets.NewChips(parent, opts)
  opts = type(opts) == "table" and opts or {}
  local self = setmetatable({ opts = opts }, Chips)
  local f = CreateFrame("Frame", nil, parent)
  self.frame = f
  self.width = tonumber(opts.width) or (Widgets.size(parent, 300, 0))
  self.height = tonumber(opts.height) or 18
  self.gap = tonumber(opts.gap) or 6
  f:SetSize(self.width, self.height)
  self.pool = Widgets.Pool(function()
    local b = CreateFrame("Button", nil, f)
    b:SetHeight(self.height)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    b.bg = bg
    local label = Widgets.font(b, "label", 11, "ink")
    label:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.label = label
    b:SetScript("OnClick", function(btn)
      if btn.item ~= nil and type(opts.onClick) == "function" then Widgets.call(opts.onClick, btn.item.key, btn.item) end
    end)
    return b
  end, function(b) b.item = nil end, Widgets.LIMITS.chips)
  return self
end

function Chips:SetItems(items)
  self.pool:ReleaseAll()
  items = type(items) == "table" and items or {}
  local x, y = 0, 0
  local Texts = ns.Journal.Texts
  for i = 1, math.min(#items, Widgets.LIMITS.chips) do
    local item = items[i]
    if type(item) == "table" then
      local b = self.pool:Acquire()
      if not b then break end
      b.item = item
      local text = type(item.label) == "string" and item.label or ""
      local count = tonumber(item.count)
      if count and Texts then text = text .. " · " .. Texts.int(count) end
      Widgets.setText(b.label, text)
      local sw = b.label.GetStringWidth and b.label:GetStringWidth()
      if type(sw) ~= "number" or sw <= 0 then sw = #text * 6 end
      local w = math.floor(sw + 2 * PAD + 0.5)
      if x > 0 and x + w > self.width then
        x, y = 0, y + self.height + 4
      end
      b:SetWidth(w)
      b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
      if item.active then
        b.bg:SetColorTexture(Widgets.color("sepia", 0.85))
        b.label:SetTextColor(Widgets.color("parchment"))
      else
        b.bg:SetColorTexture(Widgets.color("sepia", 0.15))
        b.label:SetTextColor(Widgets.color("ink"))
      end
      x = x + w + self.gap
    end
  end
  self.frame:SetHeight(y + self.height)
end

function Chips:Count() return self.pool:Count() end
