-- Schaetze sub-view "Ausrüstungsreise" (journey of the equipment): your own character as a 3D model (DressUpModel) wearing what it
-- wore at the end of the chosen level. Right page: the level big, the model, below it the timeline of the journey map (the
-- Playback widget: play / pause, slow | medium | fast, drag the knob). Left page: a slim list of the worn pieces of that level
-- (name in the quality colour, original item tooltip, newly equipped pieces marked). Data: Schaetze.wardrobe (journal/model/Schaetze.lua).
-- Rules: the model is created only when the view opens and never in combat; SetUnit("player") once per opening, never per step
-- (a level change only changes the slots that differ: UndressSlot / TryOn); TryOn answer 3 (data pending) requests the item and
-- tries again (at most RETRY_MAX times); the time lapse is a C_Timer chain (no OnUpdate except the short drag of the knob, which the
-- Playback widget owns) and stops in combat, on leaving the view and while dragging. Without a DressUpModel or when SetUnit fails the
-- model says so, slider and list keep working. Guest books (Twinks) do not have this view (Pages.GUEST_HIDDEN_SUBS).
local _, ns = ...

local Journal = ns.Journal
local W, Pages, Schaetze = Journal and Journal.Widgets, Journal and Journal.Pages, Journal and Journal.Schaetze
local D = W and W.Diary
if not (W and Pages and Schaetze and D) then return end

local floor, max, min = math.floor, math.max, math.min

local View = {}
View.__index = View
Journal.AnprobeView = View

-- locale scope "p.SchaetzeAnprobe" (English in locales/enUS_pages.lua), read when drawing
local T = ns.Locale.ns("p.SchaetzeAnprobe", {
  brand = "INK & EMBERS", book = "AUSRÜSTUNG", page = "AUSRÜSTUNGSREISE",
  title = "Ausrüstungsreise", recordFrom = "Aufzeichnung ab Stufe %s",
  level = "Stufe %s", startState = "Ausgangsstand", noChange = "keine Änderung", newPieces = "%s neu",
  empty = "Noch keine Ausrüstung aufgezeichnet.",
  emptyBody = "Die Ausrüstungsreise füllt sich mit deinem nächsten Ausrüstungswechsel.",
  slotEmpty = "leer", itemNo = "Gegenstand #%s", newTag = "neu",
  notShown = "Am Modell nicht darstellbar",
  modelCombat = "Das Modell erscheint nach dem Kampf.", modelMissing = "Das Modell kann hier nicht angezeigt werden.",
})
View.TEXT = T

-- measures from the grid (Theme.GRID; double page 1076 x 666, fold at 538): list left in the text block (x 92, 402 wide), model and
-- timeline right in the text block (x 44, 402 wide). The keep-out zones: left bottom (x 36..155, y 478..601), right x from 405 at y 582,
-- from 440 at y 347..426: the model (x 95..395) and the timeline (x 44..404, the same place as on the journey map) stay clear of them.
local G = Journal.Theme.GRID
local LX, LW = Journal.Theme.gridX("L")
local RX, RW = Journal.Theme.gridX("R")
local TITLE_X, TITLE_W = Journal.Theme.gridX("L", 2, 11)
local TITLE_Y = G.slots.title.y
local ROWS_Y, ROW_H = G.slots.body.y, G.line.row
local SLOT_W, TAG_W = 96, 34
local MODEL_W, MODEL_H = 300, 404
local MODEL_Y = 124
local TIMELINE = { x = RX, y = 546, w = 360, h = 54, speedW = 140 }
local TICK = 0.1                                  -- seconds between two steps of the time lapse (C_Timer chain)
local RATE = { [20] = 1.2, [60] = 2.4, [180] = 6 } -- levels per second for slow | medium | fast (medium: 1 to 60 in about 25 s)
View.RATE = RATE
View.TICK = TICK
View.RETRY_MAX = 3                                -- reload attempts for a slot whose TryOn says "data pending"
View.RETRY_WAIT = 0.6
View.LOAD_WAIT = 1.5                              -- seconds to wait for OnModelLoaded after SetUnit
local lastSpeed = nil                             -- speed of the last run (kept while the game runs)

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return ok and v == true
end

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

-- guarded method call on a widget: "ok", result | "fehlt" | "fehler"
local function method(obj, name, ...)
  if type(obj) ~= "table" or type(obj[name]) ~= "function" then return "fehlt" end
  local ok, a = pcall(obj[name], obj, ...)
  if not ok then return "fehler" end
  return "ok", a
end

local function int(n) return Journal.Texts.int(n) end

local function label(parent, kind, size, color, justify)
  local fs = W.font(parent, kind, size, color)
  if justify then fs:SetJustifyH(justify) end
  return fs
end

local function place(region, parent, x, y, point)
  region:ClearAllPoints()
  region:SetPoint(point or "TOPLEFT", parent, "TOPLEFT", x, -y)
end

-- frame of four lines
local function newRim(parent, w, h, r, g, b, a)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
    { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local e = f:CreateTexture(nil, "OVERLAY")
    e:SetPoint(p[1], f, p[1], 0, 0)
    e:SetPoint(p[2], f, p[2], 0, 0)
    if i <= 2 then e:SetHeight(1) else e:SetWidth(1) end
    e:SetColorTexture(r, g, b, a)
  end
  return f
end

-- ---------- building ----------

local function buildLeft(self, tab)
  local ui = self.ui
  ui.headL = W.NewPageHead(tab, { side = "L" })
  ui.headL:SetTexts(T.brand, T.book)
  ui.title = label(tab, "title", G.size.xl, "ink")
  ui.title:SetPoint("TOPLEFT", tab, "TOPLEFT", TITLE_X, -TITLE_Y)
  W.setText(ui.title, T.title)
  ui.sub = label(tab, "label", G.size.s, "sepia")
  ui.sub:SetWidth(TITLE_W)
  ui.sub:SetWordWrap(false)
  ui.sub:SetPoint("TOPLEFT", tab, "TOPLEFT", TITLE_X, -(TITLE_Y + 34))
  ui.rows = {}
  for i, def in ipairs(Schaetze.WARDROBE_SLOTS) do
    local row = CreateFrame("Frame", nil, tab)
    row:SetSize(LW, ROW_H)
    row:EnableMouse(true)
    row.slot = def.slot
    row.glow = row:CreateTexture(nil, "BACKGROUND")
    row.glow:SetAllPoints(row)
    row.glow:SetColorTexture(W.color("gold", 0.2))
    row.glow:Hide()
    row.slotText = label(row, "label", G.size.s, "sepia", "LEFT")
    row.slotText:SetWidth(SLOT_W - 6)
    row.slotText:SetWordWrap(false)
    row.slotText:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.name = label(row, "text", G.size.m, "ink", "LEFT")
    row.name:SetWidth(LW - SLOT_W - TAG_W - 8)
    row.name:SetWordWrap(false)
    row.name:SetPoint("LEFT", row, "LEFT", SLOT_W, 0)
    row.tag = label(row, "label", G.size.xs, "red", "RIGHT")
    row.tag:SetWidth(TAG_W)
    row.tag:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row:SetScript("OnEnter", function(r)
      if r.tipLines then W.tip(r, r.tipLines) end
    end)
    row:SetScript("OnLeave", function(r) W.hideTip(r) end)
    row:Hide()
    ui.rows[def.slot] = row
    row.order = i
  end
  ui.emptyHead = label(tab, "title", G.size.l, "ink", "CENTER")
  ui.emptyHead:SetWidth(LW)
  ui.emptyHead:SetPoint("TOP", tab, "TOPLEFT", LX + LW / 2, -250)
  ui.emptyBody = label(tab, "text", G.size.m, "sepia", "CENTER")
  ui.emptyBody:SetWidth(380)
  ui.emptyBody:SetPoint("TOP", tab, "TOPLEFT", LX + LW / 2, -290)
end

local function buildRight(self, tabR)
  local ui = self.ui
  ui.headR = W.NewPageHead(tabR, { side = "R" })
  ui.headR:SetTexts("", T.page)
  -- the level, large (nothing else lies over the model)
  ui.big = label(tabR, "title", G.size.xl, "ink", "CENTER")
  ui.big:SetWidth(RW)
  ui.big:SetPoint("TOP", tabR, "TOPLEFT", RX + RW / 2, -TITLE_Y)
  -- the stage of the model: parchment shade with a thin rim; the model sits inside, text never over it
  local holder = CreateFrame("Frame", nil, tabR)
  holder:SetSize(MODEL_W, MODEL_H)
  holder:SetPoint("TOP", tabR, "TOPLEFT", RX + RW / 2, -MODEL_Y)
  holder.bg = holder:CreateTexture(nil, "BACKGROUND")
  holder.bg:SetAllPoints(holder)
  holder.bg:SetColorTexture(W.color("sepia", 0.1))
  holder.rim = newRim(holder, MODEL_W + 4, MODEL_H + 4, W.color("sepia", 0.55))
  holder.rim:SetPoint("CENTER", holder, "CENTER", 0, 0)
  ui.stage = holder
  -- note instead of the model (no model class, SetUnit failed, combat)
  ui.modelNote = label(tabR, "text", G.size.m, "sepia", "CENTER")
  ui.modelNote:SetWidth(MODEL_W - 30)
  ui.modelNote:SetPoint("CENTER", holder, "CENTER", 0, 0)
  -- timeline of the journey map: Playback widget (play, speeds, track with knob, level scale)
  local PB = Journal.Playback
  if PB and PB.create then
    ui.pb = PB.create(tabR, TIMELINE.x, TIMELINE.y, TIMELINE.w, TIMELINE.h, {
      onToggle = function() W.call(function() self:Toggle() end) end,
      onSpeed = function(speed) W.call(function() self:SetSpeed(speed) end) end,
      onSeek = function(frac) W.call(function() self:Seek(frac) end) end,
      onScrubStart = function() W.call(function() self:ScrubStart() end) end,
      onScrubEnd = function(aborted) W.call(function() self:ScrubEnd(aborted) end) end,
      onChapter = function() end,
      onUpdate = function() end,
    }, { compact = true, speedW = TIMELINE.speedW })
    if ui.pb.nav and ui.pb.nav.frame then ui.pb.nav.frame:Hide() end
    if ui.pb.range then ui.pb.range:Hide() end
  end
  ui.emptyHeadR = label(tabR, "title", G.size.l, "ink", "CENTER")
  ui.emptyHeadR:SetWidth(RW)
  ui.emptyHeadR:SetPoint("TOP", tabR, "TOPLEFT", RX + RW / 2, -250)
  ui.emptyBodyR = label(tabR, "text", G.size.m, "sepia", "CENTER")
  ui.emptyBodyR:SetWidth(360)
  ui.emptyBodyR:SetPoint("TOP", tabR, "TOPLEFT", RX + RW / 2, -290)
end

function View.new(page, left, right)
  local self = setmetatable({ page = page, ui = {}, worn = {}, failed = {}, tries = {}, gen = 0, chain = 0, dressGen = 0 }, View)
  local ui = self.ui
  local tab = CreateFrame("Frame", nil, left)
  tab:SetAllPoints(left)
  tab:SetFrameLevel(left:GetFrameLevel() + 12)
  ui.tab = tab
  local tabR = CreateFrame("Frame", nil, right)
  tabR:SetAllPoints(right)
  ui.tabR = tabR
  buildLeft(self, tab)
  buildRight(self, tabR)
  -- item names the client has not loaded yet: asked for once, the list redraws when they arrive
  if Journal.Live and Journal.Live.itemNames then
    self.names = Journal.Live.itemNames(tab, function()
      if self.open then self:RenderList() end
    end, Schaetze.NAME_MAX)
  end
  D.escKeys(tab, function() page:CloseAnprobe() end)
  tab:Hide()
  tabR:Hide()
  return self
end

-- ---------- data ----------

function View:IsOpen() return self.open == true end

local function keyAt(self, level, slot)
  local lv = self.wd and self.wd.levels[level]
  return lv and lv[slot] or nil
end

-- text under the level: what changed on this level
local function changeText(self, level)
  local wd = self.wd
  if level == wd.first then return T.startState end
  local n = #(wd.changed[level] or {})
  if n == 0 then return T.noChange end
  return T("newPieces", int(n))
end

function View:Prepare(index, level)
  local char = type(index) == "table" and index.char or nil
  self.char = char
  local ok, wd = pcall(Schaetze.wardrobe, index, char, level)
  if not ok or type(wd) ~= "table" then wd = { empty = true, levels = {}, changed = {}, slots = Schaetze.WARDROBE_SLOTS } end
  self.wd = wd
  self.used = {}
  self.order = {}
  if not wd.empty then
    for L = wd.first, wd.last do
      for slot, key in pairs(wd.levels[L] or {}) do
        if key then self.used[slot] = true end
      end
    end
    for _, def in ipairs(wd.slots) do
      if self.used[def.slot] then self.order[#self.order + 1] = def end
    end
    if #self.order == 0 then wd.empty = true end
  end
  return wd
end

-- timeline of the widget: range first..last, ticks every 5 levels, marks where something changed
function View:SetupTimeline()
  local pb, wd = self.ui.pb, self.wd
  if not pb or wd.empty then return end
  local PB = Journal.Playback
  local axis, marks = {}, {}
  for L = wd.first, wd.last do
    axis[#axis + 1] = { p = L, level = L }
    if L > wd.first and #(wd.changed[L] or {}) > 0 then marks[#marks + 1] = { p = L, level = L } end
  end
  PB.setTicks(pb, PB.ticks(axis, wd.first, wd.last, pb.trackW))
  PB.setLevelMarks(pb, PB.levelFracs(marks, wd.first, wd.last))
end

-- ---------- drawing ----------

function View:RenderList()
  local ui, wd = self.ui, self.wd
  if not wd or wd.empty then return end
  local L = self.level
  local changed = {}
  for _, slot in ipairs(wd.changed[L] or {}) do changed[slot] = true end
  local y = ROWS_Y
  local shown = {}
  for _, def in ipairs(self.order) do
    local row = ui.rows[def.slot]
    shown[def.slot] = true
    place(row, ui.tab, LX, y)
    y = y + ROW_H
    W.setText(row.slotText, def.label)
    local key = keyAt(self, L, def.slot)
    row.tipLines = nil
    local isNew = key and L > wd.first and changed[def.slot]
    if key then
      local info = Schaetze.itemInfo(self.char, key)
      if info then
        local name = info.name or (self.names and self.names.name(info.id)) or T("itemNo", int(info.id))
        W.setText(row.name, name)
        local c = info.color
        row.name:SetTextColor(c[1], c[2], c[3])
        local tip = { name, T("level", int(L)), item = info.string }
        if self.failed[def.slot] then tip.itemExtra = { T.notShown } end
        row.tipLines = tip
      else
        W.setText(row.name, "?")
        row.name:SetTextColor(W.color("sepia"))
      end
    else
      W.setText(row.name, T.slotEmpty)
      row.name:SetTextColor(W.color("sepia", 0.6))
    end
    W.setText(row.tag, isNew and T.newTag or "")
    row.glow:SetShown(isNew and true or false)
    row:Show()
  end
  for slot, row in pairs(ui.rows) do
    if not shown[slot] then
      W.hideTip(row)
      row:Hide()
    end
  end
end

-- everything that depends on the position of the knob: level, list, model; the widget (knob, text)
function View:Sync(force)
  local wd, st, ui = self.wd, self.st, self.ui
  if not wd or wd.empty or not st then return end
  local L = max(wd.first, min(wd.last, floor(st.p + 0.5)))
  if L ~= self.level or force then
    self.level = L
    W.setText(ui.big, T("level", int(L)))
    self:RenderList()
    self:Dress()
  end
  local PB = Journal.Playback
  if ui.pb and PB then PB.show(ui.pb, st, { when = T("level", int(L)), played = changeText(self, L) }) end
end

function View:RenderEmpty(on)
  local ui = self.ui
  W.setText(ui.emptyHead, on and T.empty or "")
  W.setText(ui.emptyBody, on and T.emptyBody or "")
  W.setText(ui.emptyHeadR, on and T.empty or "")
  W.setText(ui.emptyBodyR, on and T.emptyBody or "")
  ui.stage:SetShown(not on)
  if ui.pb then ui.pb.frame:SetShown(not on) end
  W.setText(ui.big, on and "" or ui.big:GetText())
  if on then
    W.setText(ui.sub, "")
    W.setText(ui.modelNote, "")
    for _, row in pairs(ui.rows) do row:Hide() end
  end
end

-- ---------- the model ----------

local function modelNote(self, text)
  W.setText(self.ui.modelNote, text or "")
end

-- creates the DressUpModel (once, never in combat); nil + reason
function View:EnsureModel()
  if self.model then return self.model end
  if inCombat() then return nil, "combat" end
  if type(CreateFrame) ~= "function" then return nil, "missing" end
  local ok, m = pcall(CreateFrame, "DressUpModel", nil, self.ui.stage)
  if not ok or type(m) ~= "table" then return nil, "missing" end
  m:SetAllPoints(self.ui.stage)
  self.model = m
  return m
end

-- SetUnit once per opening; OnModelLoaded (or the wait) starts the dressing
function View:LoadModel()
  self.ready = false
  self.worn, self.failed, self.tries = {}, {}, {}
  local model, why = self:EnsureModel()
  if not model then
    modelNote(self, why == "combat" and T.modelCombat or T.modelMissing)
    return
  end
  pcall(function() model:Show() end)
  modelNote(self, "")
  local gen = self.gen + 1
  self.gen = gen
  pcall(function()
    model:SetScript("OnModelLoaded", function()
      W.call(function() self:OnModelLoaded(gen) end)
    end)
  end)
  local st, ok = method(model, "SetUnit", "player", false, true)
  if st ~= "ok" or ok == false then
    -- a model that cannot show the player is of no use: hidden, the next opening tries again
    modelNote(self, T.modelMissing)
    pcall(function() model:Hide() end)
    return
  end
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(View.LOAD_WAIT, function() W.call(function() self:OnModelLoaded(gen) end) end)
  else
    self:OnModelLoaded(gen)
  end
end

function View:OnModelLoaded(gen)
  if gen ~= self.gen or self.ready or not self.open or not self.model then return end
  if inCombat() then return end
  self.ready = true
  method(self.model, "Undress")
  method(self.model, "SetSheathed", false) -- weapons drawn
  method(self.model, "SetFacing", 0.3)      -- slightly turned, the whole figure
  self.worn = {}
  self:Dress()
end

-- one slot: item string or nil
local function itemString(key)
  return key and Journal.Texts.itemString(key) or nil
end

-- Puts the level on the model. Only slots that differ from what is worn are touched; the hands always together (a two-hander
-- pushes the off hand away). TryOn answer 3 (data pending): the item is requested, the slot tried again after RETRY_WAIT.
function View:Dress()
  local model, wd = self.model, self.wd
  if not (model and self.ready and wd and not wd.empty and self.level) then return end
  self.dressGen = self.dressGen + 1
  local dressGen = self.dressGen
  local state = wd.levels[self.level] or {}
  local pending = false
  local function target(slot) return state[slot] or false end
  local function todo(slot) return (self.worn[slot] or false) ~= target(slot) end
  local function wear(def)
    local key = target(def.slot)
    local str = itemString(key)
    if not str then
      self.worn[def.slot] = key
      return
    end
    local st, code
    if def.hand then st, code = method(model, "TryOn", str, def.hand) else st, code = method(model, "TryOn", str) end
    if st ~= "ok" then
      self.failed[def.slot] = "error"
      self.worn[def.slot] = key
      return
    end
    if type(code) ~= "number" or isSecret(code) then code = 0 end
    if code == 3 then
      local n = (self.tries[def.slot] or 0) + 1
      self.tries[def.slot] = n
      if n <= View.RETRY_MAX then
        local id = tonumber(string.match(str, "^item:(%d+)"))
        if id and C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then pcall(C_Item.RequestLoadItemDataByID, id) end
        pending = true
        self.worn[def.slot] = nil -- not on the model yet: tried again
        return
      end
      self.failed[def.slot] = 3
    elseif code ~= 0 then
      self.failed[def.slot] = code
    else
      self.failed[def.slot] = nil
    end
    self.tries[def.slot] = nil
    self.worn[def.slot] = key
  end
  local full = false
  local handsChanged = todo(16) or todo(17)
  if type(model.UndressSlot) ~= "function" then
    -- no UndressSlot: whenever a slot has to be emptied (or the hands change) one Undress and everything again
    for _, def in ipairs(wd.slots) do
      if todo(def.slot) and (target(def.slot) == false or def.slot == 16 or def.slot == 17) then full = true end
    end
  end
  for _, def in ipairs(wd.slots) do
    if not full and def.slot ~= 16 and def.slot ~= 17 and todo(def.slot) then
      if target(def.slot) == false then
        local st = method(model, "UndressSlot", def.slot)
        if st == "ok" then
          self.worn[def.slot], self.failed[def.slot] = false, nil
        else
          full = true
        end
      else
        wear(def)
      end
    end
  end
  if handsChanged and not full then
    for _, slot in ipairs({ 16, 17 }) do
      if method(model, "UndressSlot", slot) ~= "ok" then full = true end
      self.worn[slot], self.failed[slot] = false, nil
    end
  end
  if full then
    -- no UndressSlot (or it failed): one Undress and everything of this level again
    method(model, "Undress")
    self.worn = {}
    for _, def in ipairs(wd.slots) do
      if not wd.levels[self.level][def.slot] then self.worn[def.slot] = false end
    end
  end
  if handsChanged or full then
    for _, def in ipairs(wd.slots) do
      if (def.slot == 16 or def.slot == 17 or full) and target(def.slot) then wear(def) end
    end
  end
  if pending and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(View.RETRY_WAIT, function()
      if dressGen ~= self.dressGen or not self.open then return end
      W.call(function() self:Dress() end)
    end)
  end
  if self.open then self:RenderList() end
end

-- ---------- playback (time lapse) ----------

function View:StartChain()
  if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
    self.st.playing = false
    return false
  end
  self.chain = self.chain + 1
  local id = self.chain
  C_Timer.After(TICK, function() W.call(function() self:Tick(id) end) end)
  return true
end

function View:StopChain()
  self.chain = self.chain + 1
end

function View:Tick(id)
  local st = self.st
  if id ~= self.chain or not self.open or not st or not st.playing then return end
  if inCombat() then
    st.playing = false
    self:Sync()
    return
  end
  Journal.Playback.step(st, TICK * RATE[st.speed] / st.speed)
  self:Sync()
  if st.playing then
    C_Timer.After(TICK, function() W.call(function() self:Tick(id) end) end)
  end
end

function View:Toggle()
  local st = self.st
  if not st or not self.open or inCombat() then return end
  local playing = Journal.Playback.toggle(st)
  if playing then
    if not self:StartChain() then playing = false end
  else
    self:StopChain()
  end
  self:Sync(true)
  return playing
end

function View:Pause()
  if self.st then self.st.playing = false end
  self:StopChain()
end

function View:SetSpeed(speed)
  local PB = Journal.Playback
  if not self.st or not PB.SPEED_NAMES[speed] then return false end
  self.st.speed = speed
  lastSpeed = speed
  self:Sync()
  return true
end

function View:Seek(frac)
  if not self.st or not self.open then return end
  Journal.Playback.seek(self.st, frac)
  self:Sync()
end

function View:ScrubStart()
  if not self.st or self.scrub then return end
  self.scrub = { was = self.st.playing and true or false }
  if self.scrub.was then self:Pause() end
end

function View:ScrubEnd(aborted)
  local sc = self.scrub
  self.scrub = nil
  if not sc or aborted or not self.open then return end
  if sc.was and self.st.p < self.st.p1 and not inCombat() then
    self.st.playing = true
    self:StartChain()
  end
  self:Sync()
end

-- jump to a level (hand, tests)
function View:GoTo(level)
  local wd, st = self.wd, self.st
  if not wd or wd.empty or not st then return false end
  level = max(wd.first, min(wd.last, floor(tonumber(level) or wd.last)))
  st.p = level
  self:Sync()
  return true
end

-- ---------- open / close ----------

local function setup(self, index, level, keep)
  local ui = self.ui
  local wd = self:Prepare(index, level)
  if wd.empty then
    self:Pause()
    self.st, self.level = nil, nil
    self:RenderEmpty(true)
    return
  end
  self:RenderEmpty(false)
  W.setText(ui.sub, T("recordFrom", int(wd.first)))
  local PB = Journal.Playback
  local st = PB.new(lastSpeed)
  PB.setRange(st, wd.first, wd.last)
  if keep and self.st and keep >= wd.first and keep <= wd.last then st.p = keep end -- stays on the same level
  st.speed = PB.validSpeed(self.st and self.st.speed or lastSpeed)
  self.st = st
  self:SetupTimeline()
  self.level = nil
  self:Sync(true)
end

function View:Open(index, level)
  self.open = true
  self.ui.tab:Show()
  self.ui.tabR:Show()
  setup(self, index, level)
  if self.wd and not self.wd.empty then self:LoadModel() end
end

-- new index with the view open: the data again, the knob stays on the level (follows the end if it was there)
function View:Refresh(index, level)
  if not self.open then return end
  local keep = self.level
  local atEnd = self.wd and not self.wd.empty and keep == self.wd.last
  local playing = self.st and self.st.playing
  setup(self, index, level, keep)
  if self.st and atEnd then self.st.p = self.wd.last self:Sync(true) end
  if playing and self.st and self.st.p < self.st.p1 then
    self.st.playing = true
    self:StartChain()
  end
end

function View:Close()
  local ui = self.ui
  self.open = false
  self:Pause()
  self.scrub = nil
  self.gen = self.gen + 1
  self.dressGen = self.dressGen + 1
  self.ready = false
  if self.names then self.names.stop() end
  for _, row in pairs(ui.rows) do W.hideTip(row) end
  ui.tab:Hide()
  ui.tabR:Hide()
end
