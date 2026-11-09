-- "Printed" widgets (page head, rule, ink button, rect, outline): ink and thin lines, no backing, no shadows.
-- Shared by the map and the journal pages.
local _, ns = ...

local Widgets = ns.Journal.Widgets
local TX = ns.Locale.ns("w.Print", { level = "Stufe %d" })

Widgets.HEAD = { x = 40, y = 28, ruleGap = 16, size = 11 }

function Widgets.NewRule(parent, x, y, w, alpha)
  local r = parent:CreateTexture(nil, "ARTWORK")
  r:SetColorTexture(Widgets.color("sepia", alpha or 0.35))
  r:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, -(y or 0))
  r:SetSize(w or 100, 1)
  return r
end

function Widgets.NewRect(parent, color, alpha, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetColorTexture(Widgets.color(color, alpha))
  return t
end

function Widgets.NewOutline(parent, w, h, color, alpha)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
    { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local e = Widgets.NewRect(f, color or "ink", alpha or 0.8, "BORDER")
    e:SetPoint(p[1], f, p[1], 0, 0)
    e:SetPoint(p[2], f, p[2], 0, 0)
    if i <= 2 then e:SetHeight(1) else e:SetWidth(1) end
  end
  return f
end

local Head = {}
Head.__index = Head

function Widgets.NewPageHead(parent, opts)
  opts = type(opts) == "table" and opts or {}
  local H = Widgets.HEAD
  local x, y = tonumber(opts.x) or H.x, tonumber(opts.y) or H.y
  local w = tonumber(opts.width)
  local Theme = ns.Journal.Theme
  local G = Theme and Theme.GRID
  if G and (opts.side == "L" or opts.side == "R") then
    x, w = Theme.gridX(opts.side, 1, G.cols, opts.spread)
    y = G.head.y
    opts.ruleGap = G.head.ruleGap
  end
  if not w then w = (Widgets.size(parent, 538, 0)) - x - 36 end
  local self = setmetatable({ x = x, y = y, width = w }, Head)
  local l = Widgets.font(parent, "label", H.size, "sepia")
  l:SetJustifyH("LEFT")
  l:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  l:SetWordWrap(false)
  local r = Widgets.font(parent, "label", H.size, "sepia")
  r:SetJustifyH("RIGHT")
  r:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + w, -y)
  r:SetWordWrap(false)
  self.left, self.right = l, r
  self.rule = Widgets.NewRule(parent, x, y + (tonumber(opts.ruleGap) or H.ruleGap), w)
  return self
end

local function upper(t) return ns.Journal.Fmt.upper(t) end

function Head:SetTexts(left, right)
  Widgets.setText(self.left, left)
  Widgets.setText(self.right, upper(right))
  local rw = self.right.GetStringWidth and tonumber(self.right:GetStringWidth()) or 0
  self.left:SetWidth(math.max(20, self.width - rw - 12))
end

function Widgets.playerLine(data)
  if type(data) ~= "table" then return nil end
  local info = type(data.char) == "table" and type(data.char.info) == "table" and data.char.info or {}
  local S = ns.Sanitize
  local function d(v) return S and S.display(v, 32) or nil end
  local parts = {}
  local who = d(ns.Names and ns.Names.fullName(info) or info.name) -- "Vorname Nachname" on Forever (Names.lua)
  if who then parts[#parts + 1] = who end
  local rc = {}
  local race, class = d(info.race), d(info.class)
  if race then rc[#rc + 1] = race end
  if class then rc[#rc + 1] = class end
  if #rc > 0 then parts[#parts + 1] = table.concat(rc, " ") end
  local level = type(data.live) == "table" and type(data.live.level) == "function" and data.live.level() or nil
  local Index = ns.Journal.Index
  if not level and Index and data.index then
    local last = Index.list(data.index, "LV")
    last = last[#last]
    level = last and Index.num(last, "LV", "level") or nil
  end
  if tonumber(level) then parts[#parts + 1] = TX("level", math.floor(tonumber(level))) end
  if #parts == 0 then return nil end
  return table.concat(parts, " · ")
end

local Ink = {}

local function inkColor(b)
  if b.disabled then
    b.text:SetTextColor(Widgets.color("sepia", 0.4))
    b.line:Hide()
    return
  end
  local c = b.active and "ink" or (b.hover and "red" or "sepia")
  b.text:SetTextColor(Widgets.color(c))
  b.line:SetShown(b.active and true or false)
end

function Widgets.NewInkButton(parent, text, opts)
  opts = type(opts) == "table" and opts or {}
  local b = CreateFrame("Button", nil, parent)
  b.pad = tonumber(opts.pad) or 4
  local size = tonumber(opts.size) or 12
  b:SetHeight(size + 8)
  local fs = Widgets.font(b, opts.kind or "label", size, "sepia")
  fs:SetPoint("CENTER", b, "CENTER", 0, 1)
  b.text = fs
  local line = b:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(Widgets.color("ink", 0.8))
  line:SetHeight(1)
  line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", b.pad, 2)
  line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -b.pad, 2)
  b.line = line
  for k, v in pairs(Ink) do b[k] = v end
  b:SetScript("OnEnter", function(self) self.hover = true inkColor(self) end)
  b:SetScript("OnLeave", function(self)
    self.hover = false
    inkColor(self)
    if GameTooltip then GameTooltip:Hide() end
  end)
  b:SetLabel(text)
  inkColor(b)
  return b
end

function Ink:SetLabel(text)
  Widgets.setText(self.text, text)
  local w = self.text.GetStringWidth and tonumber(self.text:GetStringWidth()) or 0
  self:SetWidth(math.floor(w + 2 * self.pad + 0.5))
end

function Ink:SetEnabled(on)
  self.disabled = not on
  inkColor(self)
end

function Ink:SetActive(on)
  self.active = on and true or false
  inkColor(self)
end
