-- Column chart widget (e.g. level flow), pooled, at most Widgets.LIMITS.columns.
local _, ns = ...

local Widgets = ns.Journal.Widgets

local floor, max = math.floor, math.max

local HATCH_TILE_DEFAULT = 24   -- px per hatch tile (64 px texture, four strokes per tile)
local JITTER = 0.8

-- fixed pseudo-random number in [-1, 1] per column and part: same data, same picture
local function jit(i, k)
  local v = (i * 7919 + k * 104729 + (i * k) * 31) % 11
  return (v - 5) / 5
end

local Columns = {}
Columns.__index = Columns
Columns.HATCH_TILE = HATCH_TILE_DEFAULT

function Widgets.NewColumns(parent, opts)
  opts = type(opts) == "table" and opts or {}
  local self = setmetatable({ opts = opts }, Columns)
  local f = CreateFrame("Frame", nil, parent)
  self.frame = f
  local pw, ph = Widgets.size(parent, 300, 80)
  self.width, self.height = tonumber(opts.width) or pw, tonumber(opts.height) or ph
  f:SetSize(self.width, self.height)
  local limit = Widgets.LIMITS.columns
  self.bars = Widgets.Pool(function() return f:CreateTexture(nil, "ARTWORK") end, nil, limit)
  self.hatch = Widgets.Pool(function() return f:CreateTexture(nil, "ARTWORK", nil, 1) end, nil, limit)
  self.edges = Widgets.Pool(function() return f:CreateTexture(nil, "ARTWORK", nil, 2) end, nil, 3 * limit)
  self.marks = Widgets.Pool(function() return f:CreateTexture(nil, "OVERLAY") end, nil, limit)
  self.hits = Widgets.Pool(function()
    local h = CreateFrame("Frame", nil, f)
    h:EnableMouse(true)
    h:SetScript("OnEnter", function(hit)
      if hit.item ~= nil and type(opts.tip) == "function" then
        local ok, lines = Widgets.call(opts.tip, hit.item, hit.index)
        if ok then Widgets.tip(hit, lines) end
      end
    end)
    h:SetScript("OnLeave", function(hit) Widgets.hideTip(hit) end)
    return h
  end, function(h)
    Widgets.hideTip(h)
    h.item, h.index = nil, nil
  end, limit)
  return self
end

local function valueOf(item)
  local v = type(item) == "table" and tonumber(item.value) or nil
  if not v or v ~= v or v < 0 or v == math.huge then return 0 end
  return v
end

function Columns:SetData(items, maxValue)
  self.bars:ReleaseAll()
  self.hatch:ReleaseAll()
  self.edges:ReleaseAll()
  self.marks:ReleaseAll()
  self.hits:ReleaseAll()
  items = type(items) == "table" and items or {}
  local n = math.min(#items, Widgets.LIMITS.columns)
  if n == 0 then return end
  local top = tonumber(maxValue)
  if not top or top ~= top or top <= 0 then
    top = 0
    for i = 1, n do top = max(top, valueOf(items[i])) end
  end
  local gap = tonumber(self.opts.gap) or 2
  local colW = (self.width - gap * (n - 1)) / n
  if colW < 1 then colW, gap = 1, 0 end
  local markSize = math.min(6, max(3, floor(colW)))
  local f, H = self.frame, self.height - markSize - 2
  local Theme = ns.Journal.Theme
  local hatchTex = self.opts.sketch and Theme and Theme.TEX and Theme.TEX.hatch or nil
  local wash = tonumber(self.opts.wash) or 0.4
  for i = 1, n do
    local item = items[i]
    local v = valueOf(item)
    local x = (i - 1) * (colW + gap)
    local h = top > 0 and v / top * H or 0
    if v > 0 and h < 1 then h = 1 end
    local bar = self.bars:Acquire()
    if bar then
      local color = type(item) == "table" and item.color or self.opts.color or "sepia"
      bar:SetColorTexture(Widgets.color(color, hatchTex and wash or 0.85))
      bar:SetSize(colW, max(h, 0.01))
      bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 0)
      if h <= 0 then bar:Hide() end
      if hatchTex and h > 0 then self:Sketch(i, x, colW, h, color, hatchTex) end
    end
    if type(item) == "table" and item.mark then
      local m = self.marks:Acquire()
      if m then
        m:SetColorTexture(Widgets.color(self.opts.markColor or "red"))
        m:SetSize(markSize, markSize)
        m:SetPoint("BOTTOM", f, "BOTTOMLEFT", x + colW / 2, h + 2)
      end
    end
    if type(self.opts.tip) == "function" then
      local hit = self.hits:Acquire()
      if hit then
        hit.item, hit.index = item, i
        hit:SetSize(colW + gap, self.height)
        hit:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 0)
      end
    end
  end
end

function Columns:Sketch(i, x, w, h, color, hatchTex)
  local f = self.frame
  local tile = Columns.HATCH_TILE
  local hat = self.hatch:Acquire()
  if hat then
    hat:SetTexture(hatchTex, "REPEAT", "REPEAT")
    hat:SetTexCoord(0, w / tile, 0, h / tile)
    hat:SetVertexColor(Widgets.color(color, 0.85))
    hat:SetSize(w, h)
    hat:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 0)
  end
  local er, eg, eb = Widgets.color(self.opts.edge or "ink")
  local function edge(ex, ey, ew, eh)
    local t = self.edges:Acquire()
    if not t then return end
    t:SetColorTexture(er, eg, eb, 0.9)
    t:SetSize(max(ew, 0.5), max(eh, 0.5))
    t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", ex, ey)
    if type(t.SetRotation) == "function" then t:SetRotation(0) end
  end
  local base = w >= 3 and 1 or 0.6
  local tl, tr, tt = base + jit(i, 1) * JITTER * 0.5, base + jit(i, 3) * JITTER * 0.5, 1 + (jit(i, 5) + 1) * JITTER * 0.5
  edge(x, 0, tl, h)
  edge(x + w - tr, 0, tr, h)
  edge(x, max(0, h - tt), w, tt)
end

function Columns:Count() return self.bars:Count() end
