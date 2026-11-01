-- Tick ring widget. The client has no arc primitive: small tick textures are rotated with SetRotation and
-- placed on the circle. Tick 1 is at 12 o'clock, clockwise. Pooled, at most Widgets.LIMITS.ringTicks.
local _, ns = ...

local Widgets = ns.Journal.Widgets

local floor, sin, cos, pi = math.floor, math.sin, math.cos, math.pi

local Ring = {}
Ring.__index = Ring

function Widgets.NewRing(parent, opts)
  opts = type(opts) == "table" and opts or {}
  local self = setmetatable({ opts = opts }, Ring)
  local size = tonumber(opts.size) or 120
  self.size = size
  self.length = tonumber(opts.length) or 12
  self.thickness = tonumber(opts.thickness) or 3
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  self.frame = f
  self.ticks = Widgets.Pool(function() return f:CreateTexture(nil, "ARTWORK") end, nil, Widgets.LIMITS.ringTicks)
  local c = Widgets.font(f, "title", 22, "ink")
  c:SetPoint("CENTER", f, "CENTER", 0, 0)
  self.center = c
  return self
end

function Ring:SetData(count, filled, lengthOf)
  self.ticks:ReleaseAll()
  count = floor(tonumber(count) or 0)
  if count < 1 then return end
  if count > Widgets.LIMITS.ringTicks then count = Widgets.LIMITS.ringTicks end
  local opts = self.opts
  local fillN = tonumber(filled)
  local r0 = self.size / 2 - self.length / 2
  for i = 1, count do
    local t = self.ticks:Acquire()
    if not t then break end
    local color, alpha
    if type(filled) == "function" then
      local ok, c, a = Widgets.call(filled, i)
      if ok and c then color, alpha = c, tonumber(a) end
      if not color then color = opts.off or "faint" end
    else
      color = (fillN and i <= fillN) and (opts.on or "gold") or (opts.off or "faint")
    end
    local len = self.length
    if type(lengthOf) == "function" then
      local ok, part = Widgets.call(lengthOf, i)
      part = ok and tonumber(part) or 1
      if not part or part ~= part then part = 1 end
      if part < 0.05 then part = 0.05 elseif part > 1 then part = 1 end
      len = self.length * part
    end
    local a = (i - 1) / count * 2 * pi
    local r = r0 - (self.length - len) / 2
    if opts.tex then
      local pad = type(opts.texPad) == "table" and opts.texPad or {}
      local px, py = tonumber(pad.x) or 0, tonumber(pad.y) or 0
      t:SetTexture(opts.tex)
      t:SetVertexColor(Widgets.color(color, alpha))
      t:SetSize(self.thickness / (1 - 2 * px), len / (1 - 2 * py))
      if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
      if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
      t:ClearAllPoints()
      t:SetPoint("CENTER", self.frame, "CENTER", floor(r * sin(a) + 0.5), floor(r * cos(a) + 0.5))
    else
      t:SetColorTexture(Widgets.color(color, alpha))
      t:SetSize(self.thickness, len)
      t:SetPoint("CENTER", self.frame, "CENTER", r * sin(a), r * cos(a))
    end
    t:SetRotation(-a)
  end
end

function Ring:Count() return self.ticks:Count() end
