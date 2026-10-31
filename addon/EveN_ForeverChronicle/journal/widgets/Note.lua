-- Margin note widget: thin sepia rule on the left, optional seal. Texts must avoid characters the client fonts
-- lack (no arrows, checkmarks, stars).
local _, ns = ...

local Widgets = ns.Journal.Widgets

local Note = {}
Note.__index = Note

local PAD = 8

function Widgets.NewNote(parent, opts)
  opts = type(opts) == "table" and opts or {}
  local self = setmetatable({ opts = opts }, Note)
  local w = tonumber(opts.width) or 180
  self.width = w
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, 60)
  self.frame = f
  local stroke = f:CreateTexture(nil, "BORDER")
  stroke:SetColorTexture(Widgets.color("sepia", 0.6))
  stroke:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  stroke:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  stroke:SetWidth(1)
  self.stroke = stroke
  local seal = f:CreateTexture(nil, "ARTWORK")
  seal:SetSize(22, 22)
  seal:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
  self.seal = seal
  local sealText = Widgets.font(f, "title", 11, "parchment")
  sealText:SetPoint("CENTER", seal, "CENTER", 0, 0)
  self.sealText = sealText
  local title = Widgets.font(f, "title", tonumber(opts.titleSize) or 14, "ink")
  title:SetJustifyH("LEFT")
  self.title = title
  local body = Widgets.font(f, "text", tonumber(opts.textSize) or 11, "sepia")
  body:SetJustifyH("LEFT")
  body:SetJustifyV("TOP")
  body:SetWordWrap(true)
  self.body = body
  self:SetSeal(opts.seal)
  return self
end

function Note:SetSeal(color)
  local left = PAD
  if color then
    self.seal:SetColorTexture(Widgets.color(color))
    self.seal:Show()
    self.sealText:Show()
    left = PAD + 22 + 6
  else
    self.seal:Hide()
    self.sealText:Hide()
  end
  local tw = self.width - left - PAD
  self.title:ClearAllPoints()
  self.title:SetPoint("TOPLEFT", self.frame, "TOPLEFT", left, -PAD)
  self.title:SetWidth(tw)
  self.body:ClearAllPoints()
  self.body:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -3)
  self.body:SetWidth(tw)
  self.hasSeal = color ~= nil
end

function Note:SetContent(title, body, sealText)
  Widgets.setText(self.title, title)
  Widgets.setText(self.body, body)
  Widgets.setText(self.sealText, sealText)
  local th = self.title.GetStringHeight and self.title:GetStringHeight()
  local bh = self.body.GetStringHeight and self.body:GetStringHeight()
  th = type(th) == "number" and th or 14
  bh = type(bh) == "number" and bh or 12
  local h = PAD + th + 3 + bh + PAD
  if self.hasSeal and h < 22 + 2 * PAD then h = 22 + 2 * PAD end
  self.frame:SetHeight(h)
end
