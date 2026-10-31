-- Journal widget base: pool, palette, fonts, text and tooltip helpers. The widgets live in their own files under
-- ns.Journal.Widgets. Frames are only created when a page is built (never at load), unprotected, and never touch Blizzard tables.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Widgets = {}
Journal.Widgets = Widgets

Widgets.LIMITS = { listRows = 25, columns = 60, ringTicks = 100, chips = 24 }
Widgets.errors = 0

-- Palette and fonts come from Theme.lua (TOC: Theme first). Without Theme the tables stay empty instead of aborting the load.
local Theme = Journal.Theme or { C = {}, FONT = {} }
Widgets.COLOR = Theme.C
Widgets.FONT = Theme.FONT
Widgets.ink = Theme.ink or function(fs) return fs end

local function pack(...) return { n = select("#", ...), ... } end

function Widgets.call(fn, ...)
  if type(fn) ~= "function" then return false end
  local res = pack(pcall(fn, ...))
  if not res[1] then
    Widgets.errors = Widgets.errors + 1
    local ok, s = pcall(tostring, res[2])
    Widgets.lastError = (ns.Sanitize and ns.Sanitize.field(ok and s or "?")) or "?"
    return false
  end
  return unpack(res, 1, res.n)
end

function Widgets.Pool(create, reset, max)
  local p = { free = {}, used = {}, created = 0, max = max or 100 }
  function p:Acquire()
    local o = table.remove(self.free)
    if not o then
      if self.created >= self.max then return nil end
      o = create()
      self.created = self.created + 1
    end
    self.used[#self.used + 1] = o
    if o.Show then o:Show() end
    return o
  end
  function p:ReleaseAll()
    for i = #self.used, 1, -1 do
      local o = self.used[i]
      self.used[i] = nil
      if reset then reset(o) end
      if o.Hide then o:Hide() end
      if o.ClearAllPoints then o:ClearAllPoints() end
      self.free[#self.free + 1] = o
    end
  end
  function p:Count() return #self.used end
  return p
end

function Widgets.color(c, a)
  c = type(c) == "string" and Widgets.COLOR[c] or c
  if type(c) ~= "table" then c = Widgets.COLOR.ink or {} end
  return c[1] or 0, c[2] or 0, c[3] or 0, a or c[4] or 1
end

function Widgets.font(parent, kind, size, color, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  local path = Widgets.FONT[kind] or Widgets.FONT.text
  local ok = fs:SetFont(path, size or 12, "")
  if ok == false and GameFontNormal then fs:SetFontObject(GameFontNormal) end
  Widgets.ink(fs, kind, ok ~= false and path or nil, size or 12)
  fs:SetTextColor(Widgets.color(color or "ink"))
  fs:SetText("")
  return fs
end

function Widgets.setText(fs, text)
  if not fs then return end
  fs:SetText(type(text) == "string" and text or "")
end

function Widgets.fitLine(fs, maxW, minSize)
  if not fs or type(maxW) ~= "number" or maxW <= 0 then return nil end
  fs:SetWidth(maxW)
  fs:SetWordWrap(false)
  local file, base, flags = fs:GetFont()
  if not file then return nil end
  base = tonumber(base) or 12
  fs.fitBase = fs.fitBase or base
  base = fs.fitBase
  local floor = tonumber(minSize) or math.max(8, math.floor(base * 0.8))
  if fs.SetMaxLines then fs:SetMaxLines(0) end
  local size = base
  fs:SetFont(file, size, flags or "")
  while size > floor and (tonumber(fs:GetStringWidth()) or 0) > maxW do
    size = size - 1
    fs:SetFont(file, size, flags or "")
  end
  if (tonumber(fs:GetStringWidth()) or 0) > maxW and fs.SetMaxLines then fs:SetMaxLines(1) end
  return size
end

local function tipColor(colors, i, dr, dg, db)
  local c = type(colors) == "table" and colors[i] or nil
  if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then
    return c[1], c[2], c[3]
  end
  return dr, dg, db
end

-- Original game item tooltip. Everything in pcall: an invalid link or client error returns false and the caller shows
-- its text tooltip. extra = display-ready lines appended below the item tooltip.
local function itemTip(tt, owner, link, extra)
  if type(link) ~= "string" or #link > 300 or not string.find(link, "^item:%d+[%d:%-]*$") then return false end
  if type(tt.SetHyperlink) ~= "function" then return false end
  local ok = pcall(function()
    tt:SetOwner(owner, "ANCHOR_RIGHT")
    tt:SetHyperlink(link)
    if type(extra) == "table" then
      for i = 1, #extra do
        if type(extra[i]) == "string" then tt:AddLine(extra[i], 0.85, 0.8, 0.7, true) end
      end
    end
    tt:Show()
  end)
  if not ok and tt.Hide then pcall(tt.Hide, tt) end
  return ok
end

-- Own item tooltip. With "always compare items" the game attaches the comparison tooltips only to the global GameTooltip
-- (supportsItemComparison / shoppingTooltips); a GameTooltipTemplate tooltip lacks that, so only the item shows.
-- Created lazily, unprotected, strata TOOLTIP; if that fails the global GameTooltip is used (with comparison).
Widgets.ITEM_TIP_NAME = "EveNChronicleItemTip"
local itemTipFrame, itemTipFailed, itemTipOwner

local function getItemTip()
  if itemTipFrame then return itemTipFrame end
  if itemTipFailed or type(CreateFrame) ~= "function" or not UIParent then return nil end
  local ok, tt = pcall(CreateFrame, "GameTooltip", Widgets.ITEM_TIP_NAME, UIParent, "GameTooltipTemplate")
  if not ok or type(tt) ~= "table" then
    itemTipFailed = true
    return nil
  end
  pcall(function()
    tt:SetFrameStrata("TOOLTIP")
    tt.supportsItemComparison = false
    tt.shoppingTooltips = nil
  end)
  itemTipFrame = tt
  return tt
end

function Widgets.itemTipFrame()
  return getItemTip() or GameTooltip
end

function Widgets.hideItemTip(owner)
  if not itemTipFrame then return end
  if owner ~= nil and itemTipOwner ~= owner then return end
  itemTipOwner = nil
  pcall(itemTipFrame.Hide, itemTipFrame)
end

function Widgets.itemTip(owner, link)
  local tt = Widgets.itemTipFrame()
  if not tt then return false end
  local ok = itemTip(tt, owner, link)
  if ok and tt == itemTipFrame then itemTipOwner = owner end
  return ok
end

function Widgets.tip(owner, lines, colors)
  local tt = GameTooltip
  if type(lines) ~= "table" then return end
  if lines.item ~= nil then
    local it = Widgets.itemTipFrame()
    if it and itemTip(it, owner, lines.item, lines.itemExtra) then
      if it == itemTipFrame then itemTipOwner = owner end
      return
    end
  end
  if not tt then return end
  Widgets.hideItemTip()
  if type(lines[1]) ~= "string" then return end
  tt:SetOwner(owner, "ANCHOR_RIGHT")
  local r, g, b = tipColor(colors, 1, 1, 0.95, 0.85)
  tt:SetText(lines[1], r, g, b)
  for i = 2, #lines do
    if type(lines[i]) == "string" then
      r, g, b = tipColor(colors, i, 0.85, 0.8, 0.7)
      tt:AddLine(lines[i], r, g, b, true)
    end
  end
  tt:Show()
end

function Widgets.hideTip(owner)
  Widgets.hideItemTip(owner)
  local tt = GameTooltip
  if tt and tt.GetOwner and tt:GetOwner() == owner then tt:Hide() end
end

-- width/height with fallback: before the first layout the client returns 0
function Widgets.size(frame, w, h)
  local fw = frame.GetWidth and frame:GetWidth()
  local fh = frame.GetHeight and frame:GetHeight()
  if type(fw) ~= "number" or fw <= 0 then fw = w end
  if type(fh) ~= "number" or fh <= 0 then fh = h end
  return fw, fh
end
