-- Docking bar at the Blizzard profession window (WoW Forever only; Retail has no recipe cache, the bar never exists there): a narrow
-- plate beside ProfessionsFrame with (1) the shopping list of the recipe chosen in Blizzard's window (materials with bag counts, count
-- +/-, "Auf den Einkaufszettel", data and actions of collectors/Einkaufszettel.lua) and (2) the block "Für den nächsten Skillpunkt"
-- (journal/model/Skillpunkt.lua, widget HS.newRec of pages/HandwerkSkillpunkt.lua: the recommendation "Effizientester Skillpunkt" with
-- material line and button, then two alternatives; a click on a recipe chooses it in Blizzard's window, only if
-- C_TradeSkillUI.OpenRecipe exists and the game lets us call it, else just the tooltip).
--
-- Taint rules (everything towards Blizzard's frames is READ ONLY):
--   * the bar is a frame of UIParent; only a SetPoint anchors it to ProfessionsFrame, and only outside combat (in combat nothing is
--     built, moved or re-anchored; the bar only follows the window's visibility, with Hide()/alpha);
--   * no HookScript / SetScript / hooksecurefunc on a Blizzard frame, no write into a Blizzard frame or table, no Show/Hide on it;
--   * the window is found lazily (rawget(_G, "ProfessionsFrame"): Blizzard_Professions loads on demand; ADDON_LOADED and TRADE_SKILL_SHOW
--     wake the bar), without it the bar does nothing;
--   * visibility: TRADE_SKILL_SHOW / TRADE_SKILL_CLOSE plus a light poll (PB.POLL seconds) of ProfessionsFrame:IsShown() while the window
--     is open; the poll frame is our own and stays hidden (no OnUpdate) while no window is open;
--   * the chosen recipe comes from EventRegistry "ProfessionsRecipeListMixin.Event.OnRecipeSelected" (own owner table; the handler only
--     stores the recipe id, nothing is drawn inside Blizzard's call) or, without it, from SchematicForm:GetRecipeInfo() under pcall.
-- Option "professionBar" (Pages setting, default on; Options: "Leiste am Berufsfenster"). Texts of Einkaufszettel and Skillpunkt are reused.
local _, ns = ...

local Journal = ns.Journal
local W = Journal and Journal.Widgets
local E = ns.Einkauf
local Z = Journal and Journal.Einkaufszettel
local HS = Journal and Journal.HandwerkSkillpunkt
local Model = Journal and Journal.Skillpunkt
if not (Journal and W and E and Z and HS and Model) then return end

local floor, max, min = math.floor, math.max, math.min

local PB = {}
Journal.ProfessionBar = PB

PB.NAME = "EveNChronicleProfessionBar"
PB.WINDOW = "ProfessionsFrame"
PB.EVENT = "ProfessionsRecipeListMixin.Event.OnRecipeSelected"
PB.W = 232              -- width of the bar
PB.PAD = 10
PB.GAP = 3              -- distance to the window
PB.POLL = 0.25          -- seconds between two looks at the window while it is open
PB.GRACE = 3            -- seconds after TRADE_SKILL_SHOW in which a not yet visible window is waited for
PB.MAT_ROWS = 7
PB.SCAN_MAX = 160       -- frames looked at when searching Blizzard's side tabs
PB.TAB_MAX_W = 120      -- a side tab is narrower than this
PB.TAB_EDGE = 40        -- ... and starts within this distance of the window edge
PB.ROW_H = 16
PB.ALT_ROWS = 2            -- alternatives below the recommendation
PB.SKILL_ROWS = 1 + PB.ALT_ROWS
PB.COLORS = {
  bg = { 0.024, 0.031, 0.047, 0.82 }, edge = { 0.91, 0.78, 0.48, 0.55 },
  head = { 0.91, 0.78, 0.48 }, text = { 0.96, 0.93, 0.85 }, dim = { 0.74, 0.70, 0.62 },
  need = { 0.96, 0.62, 0.50 }, ok = { 0.62, 0.84, 0.52 }, hover = { 1, 0.93, 0.7 },
  btn = { 0.91, 0.78, 0.48, 0.20 }, btnHover = { 0.91, 0.78, 0.48, 0.38 },
  orange = { 0.95, 0.55, 0.16 }, yellow = { 0.96, 0.86, 0.28 }, green = { 0.45, 0.78, 0.35 },
}

PB.TEXT = ns.Locale.ns("ProfessionBar", {
  head = "EINKAUFSZETTEL",
  pick = "Wählt im Berufsfenster ein Rezept.",
  loading = "Dieses Rezept ist noch nicht im Rezeptbuch gespeichert. Es wird gleich gelesen.",
  add = "Auf den Einkaufszettel",
  open = "Zettel öffnen",
  openTip = "Öffnet den Einkaufszettel mit allen Einstellungen.",
  choose = "Klick: Rezept im Berufsfenster wählen",
  optLabel = "Leiste am Berufsfenster",
  optTip = "Eine schmale Leiste direkt am Berufsfenster: Einkaufszettel zum gewählten Rezept und „Für den nächsten Skillpunkt“ (nur WoW Forever).",
})
local T = PB.TEXT
local ZT, HT = Z.TEXT, HS.TEXT

local st = { counts = {}, poll = 0, sig = nil, placeSig = nil, msg = nil }
PB.state = st

-- Reading helpers ----------------------------------------------------------------------------------------------------------------

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function posInt(v)
  v = num(v)
  if not v or v < 1 or v > 2147483647 then return nil end
  return floor(v)
end

local function safe(fn, ...)
  if ns.Core and ns.Core.safe then return ns.Core.safe(fn, ...) end
  return pcall(fn, ...)
end

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return not ok or isSecret(v) or v == true
end

local function now()
  if type(GetTime) ~= "function" then return 0 end
  local ok, t = pcall(GetTime)
  return ok and num(t) or 0
end

-- guarded field read of a foreign table
local function field(t, k)
  if type(t) ~= "table" or isSecret(t) then return nil end
  local ok, v = pcall(function() return t[k] end)
  if not ok or isSecret(v) then return nil end
  return v
end

-- result of a foreign method under pcall (read only)
local function method(obj, name, ...)
  if type(obj) ~= "table" or isSecret(obj) then return nil end
  local f = field(obj, name)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(f, obj, ...)
  if not ok or isSecret(a) then return nil end
  return a, b, c, d
end

local function pageSetting()
  local P = Journal.Pages
  if not (P and type(P.setting) == "function") then return true end
  return P.setting("professionBar") ~= false
end

function PB.setting() return pageSetting() end

function PB.enabled()
  return E.active() and pageSetting()
end

function PB.setEnabled(on)
  local P = Journal.Pages
  if P and type(P.setSetting) == "function" then P.setSetting("professionBar", on and true or false) end
  PB.update()
end

-- Blizzard's window (nil as long as Blizzard_Professions is not loaded)
local function window()
  local w = rawget(_G, PB.WINDOW)
  if type(w) ~= "table" or isSecret(w) then return nil end
  return w
end

local function windowShown()
  local w = window()
  return w ~= nil and method(w, "IsShown") == true
end

local function textOf(s, n)
  if type(s) ~= "string" or isSecret(s) or s == "" then return nil end
  local S = ns.Sanitize
  s = S and S.display and S.display(s, n or 60) or s
  if type(s) ~= "string" or s == "" then return nil end
  return s
end

local function int(n) return Journal.Texts and Journal.Texts.int and Journal.Texts.int(n) or tostring(floor(tonumber(n) or 0)) end

-- the open profession (professionID of the base profession info), nil when unreadable
local function openProfession()
  local api = rawget(_G, "C_TradeSkillUI")
  if type(api) ~= "table" or type(api.GetBaseProfessionInfo) ~= "function" then return nil end
  local ok, info = pcall(api.GetBaseProfessionInfo)
  if not ok then return nil end
  return posInt(field(info, "professionID"))
end

-- the recipe chosen in Blizzard's window: from the callback, else read from the schematic form (pcall)
local function selectedRecipe()
  if st.selected then return st.selected end
  local w = window()
  local form = field(field(w, "CraftingPage"), "SchematicForm")
  local info = method(form, "GetRecipeInfo")
  return posInt(field(info, "recipeID"))
end

-- EventRegistry handler: only remembers the id (nothing is drawn inside Blizzard's call)
local function onRecipeSelected(...)
  for i = 1, select("#", ...) do
    local a = select(i, ...)
    if type(a) == "table" then
      local id = posInt(field(a, "recipeID"))
      if id then
        st.selected = id
        st.dirty = true
        return
      end
    end
  end
end

-- Content (pure data) ----------------------------------------------------------------------------------------------------------------

-- { recipe = { id, prof, name, out, count, listed, mats = { { id, name, need, have, done } }, extra } | nil, state = "pick" | "loading" | "ok",
--   skill = Skillpunkt.rank result | nil, prof = professionID }
function PB.content()
  local c = { state = "pick" }
  local prof = openProfession()
  local rid = selectedRecipe()
  if rid then
    local pid, rec = E.recipe(prof, rid)
    if not pid then pid, rec = E.recipe(nil, rid) end
    if pid and rec then
      local listId = E.find(rid)
      local listed = listId and ns.Plans and ns.Plans.raw and ns.Plans.raw(listId) or nil
      local count = st.counts[rid] or 1
      if listed and type(listed.shop) == "table" then count = posInt(listed.shop.count) or count end
      count = max(1, min(count, E.COUNT_MAX))
      local mats = {}
      for _, rg in ipairs(E.reagents(rec)) do
        local need = rg.qty * count
        local have = E.count(rg.id, false) or 0
        mats[#mats + 1] = { id = rg.id, name = E.itemName(rg.id) or ("#" .. rg.id), need = need, have = have, done = have >= need }
      end
      local extra = max(0, #mats - PB.MAT_ROWS)
      for i = #mats, PB.MAT_ROWS + 1, -1 do mats[i] = nil end
      c.state = "ok"
      c.recipe = { id = rid, prof = pid, name = textOf(rec.n) or ("#" .. rid), out = posInt(rec.o), count = count,
        listed = listed ~= nil and type(listed.shop) == "table", mats = mats, extra = extra }
      prof = prof or pid
    else
      c.state = "loading"
    end
  end
  c.prof = prof or (c.recipe and c.recipe.prof) or nil
  if c.prof then c.skill = Model.rank(c.prof, { count = Model.bagCount, limit = PB.SKILL_ROWS }) end
  return c
end

-- cheap signature of everything the bar shows (a redraw only when it changes)
local function signature()
  local prof = openProfession()
  local rid = selectedRecipe()
  local cache = E.cache()
  local p = cache and prof and cache[prof]
  local stamp = type(p) == "table" and tostring(p.at) or "-"
  local list = rid and E.find(rid)
  return table.concat({ tostring(prof), tostring(rid), tostring(st.counts[rid or 0]), tostring(E.gen), stamp, tostring(list),
    tostring(st.msg), tostring(st.dirty), tostring(ns.Locale and ns.Locale.active) }, "|")
end

-- Drawing ------------------------------------------------------------------------------------------------------------------------

local function font(parent, kind, size, color, justify)
  local fs = W.font(parent, kind, size, color)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end

-- flat text button on the dark plate
local function button(parent, w, h, size)
  local C = PB.COLORS
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b.bg = W.NewRect(b, C.btn, C.btn[4], "BACKGROUND")
  b.bg:SetAllPoints(b)
  b.label = font(b, "label", size or 12, C.text, "CENTER")
  b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.label:SetWidth(w - 6)
  b.label:SetWordWrap(false)
  b:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(C.btnHover[1], C.btnHover[2], C.btnHover[3], C.btnHover[4])
    if self.tipLines then W.tip(self, self.tipLines) end
  end)
  b:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(C.btn[1], C.btn[2], C.btn[3], C.btn[4])
    W.hideTip(self)
  end)
  b:SetScript("OnClick", function(self) if self.act then safe(self.act, self) end end)
  return b
end

local function build()
  if st.frame then return st.frame end
  local C = PB.COLORS
  local Theme = Journal.Theme
  local f = CreateFrame("Frame", PB.NAME, UIParent)
  f:SetSize(PB.W, 200)
  f:SetFrameStrata("MEDIUM")
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  if f.SetDontSavePosition then f:SetDontSavePosition(true) end
  f:EnableMouse(true)
  if Theme and Theme.roundRect then
    f.edge = Theme.roundRect(f, { 1, 1, 1 }, 1, 6, "BACKGROUND", Theme.TEX and Theme.TEX.ring)
    f.edge.color(C.edge, C.edge[4])
    f.plate = Theme.roundRect(f, { 1, 1, 1 }, 1, 6, "BACKGROUND")
    f.plate.color(C.bg, C.bg[4])
  else
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
  end
  f:Hide()
  local inner = PB.W - PB.PAD * 2

  f.head = font(f, "label", 12, C.head)
  f.head:SetText(T.head)
  f.name = font(f, "text", 13, C.text)
  f.name:SetWidth(inner)
  f.name:SetWordWrap(false)
  f.nameHit = CreateFrame("Frame", nil, f)
  f.nameHit:SetSize(inner, 18)
  f.nameHit:EnableMouse(true)
  f.nameHit:SetScript("OnEnter", function(self)
    if self.item then W.tip(self, { self.title or "", item = self.item }) end
  end)
  f.nameHit:SetScript("OnLeave", function(self) W.hideTip(self) end)
  f.note = font(f, "label", 12, C.dim)
  f.note:SetWidth(inner)
  f.note:SetWordWrap(true)

  f.countLabel = font(f, "label", 12, C.dim)
  f.countLabel:SetText(ZT.countLabel)
  f.minus = button(f, 20, 18, 14)
  f.minus.label:SetText("-")
  f.minus.tipLines = { ZT.minusTip }
  f.minus.act = function() PB.step(-1) end
  f.plus = button(f, 20, 18, 14)
  f.plus.label:SetText("+")
  f.plus.tipLines = { ZT.plusTip }
  f.plus.act = function() PB.step(1) end
  f.countText = font(f, "label", 13, C.text, "CENTER")
  f.countText:SetWidth(40)

  f.mats = {}
  for i = 1, PB.MAT_ROWS do
    local row = CreateFrame("Frame", nil, f)
    row:SetSize(inner, PB.ROW_H)
    row:EnableMouse(true)
    row.name = font(row, "label", 12, C.text)
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetWidth(inner - 66)
    row.name:SetWordWrap(false)
    row.cnt = font(row, "label", 12, C.need, "RIGHT")
    row.cnt:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.cnt:SetWidth(64)
    row.cnt:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
      if self.item then W.tip(self, { self.title or "", item = self.item }) end
    end)
    row:SetScript("OnLeave", function(self) W.hideTip(self) end)
    row:Hide()
    f.mats[i] = row
  end
  f.more = font(f, "label", 11, C.dim)

  f.add = button(f, inner, 22, 12)
  f.add.act = function() PB.addList() end
  f.openSlip = button(f, inner, 18, 11)
  f.openSlip.label:SetText(T.open)
  f.openSlip.tipLines = { T.open, T.openTip }
  f.openSlip.act = function() PB.openSlip() end
  f.msg = font(f, "label", 11, C.ok)
  f.msg:SetWidth(inner)
  f.msg:SetWordWrap(true)

  f.rule = W.NewRect(f, C.edge, 0.4, "ARTWORK")
  f.skillHead = font(f, "label", 12, C.head)
  f.skillHead:SetText(HT.head)
  f.skillHead:SetWidth(PB.W - PB.PAD * 2)
  f.skillHead:SetWordWrap(false)
  f.skillMore = font(f, "label", 11, C.dim)
  f.skills = {}
  f.rec = HS.newRec(f, { w = inner, wrap = true, kind = "label", sizes = { head = 12, line = 11 }, btnH = 22,
    col = { head = C.text, ok = C.ok, need = C.need, dim = C.dim },
    rgb = { orange = C.orange, yellow = C.yellow, green = C.green },
    newButton = function(p) return button(p, inner, 22, 12) end,
    setLabel = function(b, text) b.label:SetText(text) end,
    onPick = function(row) PB.chooseRecipe(row.id) end,
    onChange = function() PB.update(true) end })
  for i = 1, PB.ALT_ROWS do
    local row = CreateFrame("Button", nil, f)
    row:SetSize(inner, PB.ROW_H + 1)
    row.dot = W.NewRect(row, C.text, 1, "ARTWORK")
    row.dot:SetPoint("LEFT", row, "LEFT", 1, 0)
    row.dot:SetSize(7, 7)
    row.name = font(row, "label", 12, C.text)
    row.name:SetPoint("LEFT", row, "LEFT", 14, 0)
    row.name:SetWidth(inner - 14 - 112)
    row.name:SetWordWrap(false)
    row.val = font(row, "label", 11, C.dim, "RIGHT")
    row.val:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.val:SetWidth(110)
    row.val:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
      self.name:SetTextColor(C.hover[1], C.hover[2], C.hover[3], 1)
      local t = self.tip
      if not t then return end
      local lines = { unpack(t.lines) }
      if PB.canOpenRecipe() then lines[#lines + 1] = T.choose end
      lines.item = t.item
      lines.itemExtra = { unpack(lines, 2) }
      W.tip(self, lines)
    end)
    row:SetScript("OnLeave", function(self)
      self.name:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
      W.hideTip(self)
    end)
    row:SetScript("OnClick", function(self) if self.recipe then safe(PB.chooseRecipe, self.recipe) end end)
    row:Hide()
    f.skills[i] = row
  end
  f.skillNote = font(f, "label", 11, C.dim)
  f.skillNote:SetWidth(inner)
  f.skillNote:SetWordWrap(true)

  st.frame = f
  return f
end

local function textHeight(fs, fallback)
  local ok, h = pcall(fs.GetStringHeight, fs)
  h = ok and num(h) or nil
  if not h or h <= 0 then return fallback end
  return h
end

local function pt(obj, anchor, parent, x, y)
  obj:ClearAllPoints()
  obj:SetPoint(anchor, parent, "TOPLEFT", x, -y)
end

local function plural(n, key) return HT(ns.Locale.plural(n, key .. "_one", key .. "_other"), int(n)) end

local function skillTip(r)
  local lines = { r.name }
  if r.color then lines[#lines + 1] = HT[r.color] end
  lines[#lines + 1] = plural(r.mats, "mats")
  if r.n ~= nil then lines[#lines + 1] = r.n > 0 and HT("enough", int(r.n)) or HT.enoughNone end
  if (r.u or 1) > 1 then lines[#lines + 1] = HT("ups", int(r.u)) end
  return { lines = lines, item = r.out and ("item:" .. tostring(r.out)) or nil }
end

-- paints the bar from PB.content(); positions every part from the top (the height follows the content)
local function draw()
  local f = st.frame
  if not f then return end
  local C = PB.COLORS
  local c = PB.content()
  st.content = c
  local x, inner = PB.PAD, PB.W - PB.PAD * 2
  local y = 8
  pt(f.head, "TOPLEFT", f, x, y)
  y = y + 16
  local r = c.recipe
  f.note:Hide() f.name:Hide() f.nameHit:Hide() f.countLabel:Hide() f.minus:Hide() f.plus:Hide() f.countText:Hide()
  f.more:Hide() f.add:Hide() f.openSlip:Hide() f.msg:Hide()
  for _, row in ipairs(f.mats) do row:Hide() end
  if c.state ~= "ok" then
    f.note:SetText(c.state == "loading" and T.loading or T.pick)
    pt(f.note, "TOPLEFT", f, x, y)
    f.note:Show()
    y = y + textHeight(f.note, 14) + 8
  else
    W.setText(f.name, r.name)
    pt(f.name, "TOPLEFT", f, x, y)
    f.name:Show()
    pt(f.nameHit, "TOPLEFT", f, x, y - 2)
    f.nameHit.item, f.nameHit.title = r.out and ("item:" .. tostring(r.out)) or nil, r.name
    f.nameHit:Show()
    y = y + 22
    pt(f.countLabel, "TOPLEFT", f, x, y + 2)
    f.countLabel:Show()
    pt(f.plus, "TOPLEFT", f, x + inner - 20, y - 1)
    pt(f.countText, "TOPLEFT", f, x + inner - 20 - 42, y + 1)
    pt(f.minus, "TOPLEFT", f, x + inner - 20 - 44 - 20, y - 1)
    W.setText(f.countText, int(r.count))
    f.minus:Show() f.plus:Show() f.countText:Show()
    y = y + 24
    for i, row in ipairs(f.mats) do
      local m = r.mats[i]
      if m then
        pt(row, "TOPLEFT", f, x, y)
        W.setText(row.name, m.name)
        setColor(row.name, m.done and C.dim or C.text)
        W.setText(row.cnt, string.format("%s/%s", int(min(m.have, 99999)), int(m.need)))
        setColor(row.cnt, m.done and C.ok or C.need)
        row.item, row.title = "item:" .. tostring(m.id), m.name
        row:Show()
        y = y + PB.ROW_H
      end
    end
    if r.extra > 0 then
      W.setText(f.more, HT("more", int(r.extra)))
      pt(f.more, "TOPLEFT", f, x, y)
      f.more:Show()
      y = y + 14
    end
    y = y + 4
    f.add.label:SetText(r.listed and ZT.update or T.add)
    f.add.tipLines = { ZT.add, ZT.addTip }
    pt(f.add, "TOPLEFT", f, x, y)
    f.add:Show()
    y = y + 26
    if r.listed then
      pt(f.openSlip, "TOPLEFT", f, x, y)
      f.openSlip:Show()
      y = y + 22
    end
    if st.msg and st.msgRecipe == r.id then
      W.setText(f.msg, st.msg)
      f.msg:SetTextColor(st.msgBad and C.need[1] or C.ok[1], st.msgBad and C.need[2] or C.ok[2], st.msgBad and C.need[3] or C.ok[3], 1)
      pt(f.msg, "TOPLEFT", f, x, y)
      f.msg:Show()
      y = y + textHeight(f.msg, 13) + 4
    end
  end
  -- block "Für den nächsten Skillpunkt": the recommendation, then a few alternatives
  local sk = c.skill
  for _, row in ipairs(f.skills) do row:Hide() end
  f.skillHead:Hide() f.skillMore:Hide() f.skillNote:Hide() f.rule:Hide()
  f.rec:Hide()
  if sk then
    y = y + 4
    f.rule:ClearAllPoints()
    f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
    f.rule:SetSize(inner, 1)
    f.rule:Show()
    y = y + 6
    pt(f.skillHead, "TOPLEFT", f, x, y)
    f.skillHead:Show()
    y = y + 18
    if sk.best then
      y = y + f.rec:Set(sk.best, { own = true }, x, y) + 2
    end
    local altN = 0
    for i, row in ipairs(f.skills) do
      local s2 = sk.rows[i + 1]
      if s2 and not (sk.noSure and i == PB.ALT_ROWS) then
        altN = altN + 1
        pt(row, "TOPLEFT", f, x, y)
        local col = C[s2.color] or C.green
        row.dot:SetColorTexture(col[1], col[2], col[3], 1)
        W.setText(row.name, s2.name)
        local val = { HS.levelWord(s2.color) }
        if s2.n ~= nil then val[#val + 1] = s2.n > 0 and HT("enough", int(s2.n)) or HT.enoughNone end
        W.setText(row.val, table.concat(val, " · "))
        row.tip, row.recipe = skillTip(s2), s2.id
        row:Show()
        y = y + PB.ROW_H + 1
      end
    end
    local extra = (sk.total or 0) - 1 - altN
    if extra > 0 and not sk.noSure then
      W.setText(f.skillMore, HT("more", int(extra)))
      pt(f.skillMore, "TOPLEFT", f, x + 14, y)
      f.skillMore:Show()
      y = y + 14
    end
    if sk.noSure and sk.reason ~= "nolearned" then
      y = y + f.rec:Hint(x, y)
    end
    local msg
    if sk.reason == "nocache" then msg = HT.nocache
    elseif sk.reason == "nolearned" then msg = HT.nolearned end
    if msg then
      W.setText(f.skillNote, msg)
      pt(f.skillNote, "TOPLEFT", f, x, y)
      f.skillNote:Show()
      y = y + textHeight(f.skillNote, 14) + 2
    end
  end
  f:SetHeight(y + 8)
end

-- Placement (outside combat only) --------------------------------------------------------------------------------------------------------

local function scaleOf(f)
  local v = method(f, "GetEffectiveScale")
  v = num(v)
  return (v and v > 0) and v or nil
end

-- children of a foreign frame (read only), at most `limit`
local function childrenOf(f, limit)
  local fn = field(f, "GetChildren")
  if type(fn) ~= "function" then return {} end
  local ok, t = pcall(function() return { fn(f) } end)
  if not ok or type(t) ~= "table" then return {} end
  local out = {}
  for i = 1, min(#t, limit) do
    if type(t[i]) == "table" and not isSecret(t[i]) then out[#out + 1] = t[i] end
  end
  return out
end

-- Blizzard's vertical profession tabs sit at the window's side edge and stick out of it. Read only: how far shown small frames
-- (up to two levels below the window) protrude to the right / to the left of the window within the bar's vertical range
-- (window units; l, b, ww = rectangle of the window, barH = height of the bar). -> right, left
local function protrusion(w, ew, l, b, ww, barH)
  local right, left = 0, 0
  local budget = PB.SCAN_MAX
  local function visit(f, depth)
    for _, c in ipairs(childrenOf(f, budget)) do
      if budget <= 0 then return end
      budget = budget - 1
      if method(c, "IsShown") == true then
        local cl, cb, cw, ch = method(c, "GetRect")
        cl, cb, cw, ch = num(cl), num(cb), num(cw), num(ch)
        if cl and cb and cw and ch and cw > 0 and ch > 0 then
          local k = (scaleOf(c) or ew) / ew
          cl, cb, cw, ch = cl * k, cb * k, cw * k, ch * k
          local cr = cl + cw
          if cw <= PB.TAB_MAX_W and cb < b + barH and cb + ch > b then
            if cr > l + ww + 1 and cl >= l + ww - PB.TAB_EDGE then right = max(right, cr - (l + ww)) end
            if cl < l - 1 and cr <= l + PB.TAB_EDGE then left = max(left, l - cl) end
          end
        end
        if depth < 2 then visit(c, depth + 1) end
      end
    end
  end
  visit(w, 1)
  return right, left
end

-- anchors the bar to the window: bottom aligned right of it (clear of the tab column), or left when the screen edge leaves no
-- room; scale follows the window
local function place()
  local f, w = st.frame, window()
  if not (f and w) or inCombat() then return false end
  local sw = UIParent and num(method(UIParent, "GetWidth")) or nil
  local ew, eu = scaleOf(w), UIParent and scaleOf(UIParent) or nil
  local k = (ew and eu) and max(0.5, min(2, ew / eu)) or 1
  local l, b, ww = method(w, "GetRect")
  l, b, ww = num(l), num(b), num(ww)
  local barH = num(f:GetHeight()) or 0
  local extraR, extraL = 0, 0
  if l and b and ww then extraR, extraL = protrusion(w, ew or 1, l, b, ww, barH) end
  local side = "right"
  if l and ww and sw and sw > 0 then
    local r = (l + ww + extraR) * k
    if r + PB.GAP + PB.W * k > sw and (l - extraL) * k - PB.GAP - PB.W * k >= 0 then side = "left" end
  end
  local sig = table.concat({ side, tostring(k), tostring(l), tostring(ww), tostring(sw), tostring(extraR), tostring(extraL),
    tostring(barH) }, "|")
  if sig == st.placeSig and st.anchored then return true end
  st.placeSig = sig
  f:SetScale(k)
  f:ClearAllPoints()
  if side == "right" then
    f:SetPoint("BOTTOMLEFT", w, "BOTTOMRIGHT", PB.GAP + extraR, 0)
  else
    f:SetPoint("BOTTOMRIGHT", w, "BOTTOMLEFT", -(PB.GAP + extraL), 0)
  end
  st.anchored, st.side = true, side
  return true
end

local function hideBar()
  local f = st.frame
  if not f then return end
  pcall(f.Hide, f)
  if f.SetAlpha then pcall(f.SetAlpha, f, 0) end
  for _, row in ipairs(f.mats) do W.hideTip(row) end
  for _, row in ipairs(f.skills) do W.hideTip(row) end
  if f.rec then f.rec:Hide() end
  W.hideTip(f.nameHit)
end

-- Update: the one place where visibility, placement and content come together ------------------------------------------------------------

-- force: redraw even if nothing changed
function PB.update(force)
  if not (PB.enabled() and windowShown()) then
    hideBar()
    return false
  end
  if not st.frame then
    if inCombat() then
      st.wantBuild = true -- built after combat (PLAYER_REGEN_ENABLED)
      return false
    end
    build()
    force = true
  end
  local f = st.frame
  local wasHidden = not (f:IsShown() == true) or (f.GetAlpha and f:GetAlpha() == 0)
  if inCombat() and not st.anchored then
    return false -- never placed yet: wait for the end of combat, show nothing at a wrong place
  end
  local sig = signature()
  if force or wasHidden or sig ~= st.sig then
    st.sig, st.dirty = sig, false
    draw()
    st.sig = signature()
  end
  if not inCombat() then place() end -- after drawing: the bar's height decides which tabs it could touch
  if wasHidden then
    if f.SetAlpha then f:SetAlpha(1) end
    f:Show()
  end
  return true
end

-- Actions -----------------------------------------------------------------------------------------------------------------------------

local function currentRecipe()
  local c = st.content
  return c and c.recipe or nil
end

local function say(text, bad)
  local r = currentRecipe()
  st.msg, st.msgBad, st.msgRecipe = text, bad and true or false, r and r.id or nil
end

function PB.step(dir)
  local r = currentRecipe()
  if not r then return false end
  local stepBy = (type(IsShiftKeyDown) == "function" and IsShiftKeyDown()) and 10 or 1
  local n = max(1, min(r.count + dir * stepBy, E.COUNT_MAX))
  st.counts[r.id] = n
  say(nil)
  if r.listed then
    local id = E.find(r.id)
    if id then
      local ok, why = E.rebuild(id, { count = n })
      if not ok then say(E.reasonText(why) or "", true) end
    end
  end
  PB.update(true)
  return true
end

function PB.addList()
  local r = currentRecipe()
  if not r then return false end
  local id, how = E.add(r.prof, r.id, r.count, false)
  if not id then
    say(E.reasonText(how) or "", true)
  else
    say(how == "update" and ZT.changed or ZT.saved)
  end
  PB.update(true)
  return id ~= nil
end

function PB.openSlip()
  local r = currentRecipe()
  if not r then return false end
  return Z.open({ prof = r.prof, recipe = r.id, anchor = st.frame }) == true
end

-- choosing a recipe in Blizzard's window: only through an unprotected API, from a click, outside combat; if the game blocks the call
-- once (error or ADDON_ACTION_BLOCKED in Core.actionLog) the rows are tooltip only for the rest of the session
PB.openBlocked = false

local function actionTotal()
  local log = ns.Core and ns.Core.actionLog
  return log and num(log.total) or 0
end

function PB.canOpenRecipe()
  local api = rawget(_G, "C_TradeSkillUI")
  return not PB.openBlocked and type(api) == "table" and type(api.OpenRecipe) == "function"
end

function PB.chooseRecipe(recipeID)
  recipeID = posInt(recipeID)
  if not recipeID or inCombat() or not PB.canOpenRecipe() then return false end
  local before = actionTotal()
  local ok = pcall(C_TradeSkillUI.OpenRecipe, recipeID)
  if not ok or actionTotal() > before then
    PB.openBlocked = true
    return false
  end
  st.selected = recipeID
  st.dirty = true
  return true
end

-- Events and poll --------------------------------------------------------------------------------------------------------------------

local function startPoll()
  st.graceUntil = now() + PB.GRACE
  st.poll = 0
  if st.pollFrame then st.pollFrame:Show() end
end

local function onPoll(_, dt)
  st.poll = st.poll + (num(dt) or 0)
  if st.poll < PB.POLL then return end
  st.poll = 0
  if not PB.enabled() then
    PB.update()
    st.pollFrame:Hide()
    return
  end
  if windowShown() then
    PB.update()
  else
    PB.update()
    if now() > (st.graceUntil or 0) then st.pollFrame:Hide() end
  end
end

local function onEvent(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= "Blizzard_Professions" then return end
    PB.register()
    if st.open then startPoll() end
  elseif event == "TRADE_SKILL_SHOW" then
    st.open = true
    PB.register()
    startPoll()
    PB.update()
  elseif event == "TRADE_SKILL_CLOSE" then
    st.open, st.selected, st.msg = false, nil, nil
    hideBar()
  elseif event == "PLAYER_REGEN_ENABLED" then
    if st.wantBuild or st.open then
      st.wantBuild = false
      PB.update()
    end
  elseif event == "BAG_UPDATE_DELAYED" or event == "TRADE_SKILL_LIST_UPDATE" then
    st.dirty = true
  elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    PB.register()
  end
end

-- EventRegistry callback (own owner), once; the registry exists from the start, the event name needs no loaded addon
function PB.register()
  if st.registered then return true end
  local ER = rawget(_G, "EventRegistry")
  if type(ER) ~= "table" or type(ER.RegisterCallback) ~= "function" then return false end
  st.owner = st.owner or {}
  local ok = pcall(ER.RegisterCallback, ER, PB.EVENT, onRecipeSelected, st.owner)
  st.registered = ok
  return ok
end

local function init()
  if type(CreateFrame) ~= "function" then return end
  local ok, ev = pcall(CreateFrame, "Frame")
  if not (ok and type(ev) == "table") then return end
  st.events = ev
  for _, name in ipairs({ "ADDON_LOADED", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE", "PLAYER_REGEN_ENABLED",
    "BAG_UPDATE_DELAYED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" }) do
    pcall(ev.RegisterEvent, ev, name)
  end
  ev:SetScript("OnEvent", function(self, event, arg1) safe(onEvent, self, event, arg1) end)
  -- poll frame: hidden (so without any OnUpdate) while no profession window is open
  local pf = CreateFrame("Frame")
  pf:SetScript("OnUpdate", function(self, dt) safe(onPoll, self, dt) end)
  pf:Hide()
  st.pollFrame = pf
  local P = ns.Plans
  if P and type(P.onChange) == "function" then P.onChange(function() st.dirty = true end) end
  PB.register()
end

init()
