-- Quest item buttons of the quest tracker (change "quest-tracker", step E3; WoW Forever only). A pool of secure action buttons
-- (SecureActionButtonTemplate, type1 = "item", item1 = "item:<id>"): addon code may not call UseQuestLogSpecialItem, the client's
-- secure code uses the item on the click.
--
-- Combat rule (the client blocks it otherwise): attributes, position, parent and visibility of a secure button (and of its holder)
-- only change OUTSIDE combat. In combat only the count, the cooldown and the range colour change in place (texts, colours, a
-- non-secure cooldown child); anything else (new button, moved row, released button) is noted and done at PLAYER_REGEN_ENABLED,
-- then the listeners of QIB.onRelayout are called so the window (E4) can rebuild its rows.
-- Anchoring: every button hangs on its OWN holder (a plain frame on UIParent covering the screen), never on a font string, a row of
-- the scrolling content or any other foreign region (lesson Share.lua:324: a protected button anchored to an unprotected region is
-- not laid out). The row frame E4 hands in is only measured (GetLeft/GetTop/GetEffectiveScale) and must be a Frame or Button.
-- Empty buttons are "fake hidden" like Questie's: attributes cleared, clicks unregistered, hidden, back in the pool.
--
-- PUBLIC API (all safe to call at any time; nothing raises):
--   QIB.acquire(questID, row, opts) -> button | nil, reason   reason: "ok" | "combat" (in place only / noted) | "retail" | "row" |
--       "noItem" | "pool" | "quest". opts = { size (px, default QIB.SIZE), dx, dy (offset of the button's TOPRIGHT from the row's
--       TOPLEFT, default -2, 0), clip (frame: the button hides when the row's centre lies outside it, e.g. the scroll frame),
--       scaled (true: size, dx and dy are in the row's own units and follow its effective scale; the item bar of E4 uses this) }
--   E4 (design template D10): the quest window has no buttons any more; the own item bar (journal/QuestItemBar.lua) is the "row":
--   a plain, movable frame that is only measured, never a parent or anchor of a secure button (so it may move or hide in combat
--   without a block; the buttons follow at the next QIB.layout() outside combat).
--   QIB.release(questID) -> bool     QIB.releaseAll() -> n     QIB.layout() -> bool (re-measure all rows; false = noted for later)
--   QIB.update() -> n (count/cooldown/range in place, also in combat)     QIB.button(questID) -> button | nil
--   QIB.onRelayout(fn) -> bool (fn(reason) once noted work is done: "combat" = end of combat, "item" = a quest/item went away)     QIB.setStrata(strata) -> bool
--   QIB.status() -> { bound, free, created, pending, holder, installed }
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local QIB = {}
Journal.QuestItemButtons = QIB

local floor = math.floor

QIB.TEMPLATE = "SecureActionButtonTemplate"
QIB.SIZE = 26
QIB.SIZE_MIN, QIB.SIZE_MAX = 12, 64
QIB.POOL_MAX = 25 -- one per watched quest at most (MAX_QUEST_WATCHES)
QIB.TICK_SEC = 0.3 -- range/cooldown refresh while buttons are shown
QIB.DX, QIB.DY = -2, 0
QIB.STRATA = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true }
QIB.ROW_TYPES = { Frame = true, Button = true, CheckButton = true }
-- default strata HIGH with a high frame level: the buttons lie above the quest panel (HIGH, levels below 100) but below dialogs,
-- popups (DIALOG) and tooltips; the full-screen holder takes no mouse
QIB.LEVEL = 200
QIB.OUT_OF_RANGE = { 1, 0.25, 0.25 }
QIB.EVENTS = { "PLAYER_REGEN_ENABLED", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED", "PLAYER_TARGET_CHANGED" }

local S = { holder = nil, free = {}, all = {}, byQuest = {}, pending = false, listeners = {}, ticker = nil, installed = false,
  created = 0, strata = "HIGH" }
QIB._state = S

-- ---------------------------------------------------------------- helpers

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function str(v)
  if isSecret(v) or type(v) ~= "string" then return nil end
  return v
end

local function flag(v)
  return not isSecret(v) and v == true
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d
end

local function try(obj, method, ...)
  local fn = type(obj) == "table" and obj[method]
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, obj, ...)
  if not ok then return nil end
  return a, b, c, d
end

local function inCombat()
  return type(InCombatLockdown) == "function" and flag(call(InCombatLockdown))
end

local function available()
  local QT = Journal.QuestTrack
  return QT ~= nil and type(QT.available) == "function" and QT.available() == true
end

local function questKey(id)
  id = num(id)
  if not id then return nil end
  id = floor(id)
  if id <= 0 or id > 10000000 then return nil end
  return id
end

local function report(err)
  if ns.Core and ns.Core.coreError then ns.Core.coreError("Quest-Item-Knöpfe: " .. tostring(err)) end
end

-- ---------------------------------------------------------------- item data (all through pcall + secret guard)

local function logIndexOf(questID)
  local cl = rawget(_G, "C_QuestLog")
  if type(cl) ~= "table" then return nil end
  local i = num(call(cl.GetLogIndexForQuestID, questID))
  if not i or i <= 0 then return nil end
  return floor(i)
end

-- { itemID, texture, charges, logIndex } of the quest's special item, nil when the quest has none (or the values are secret)
function QIB.itemOf(questID)
  local idx = logIndexOf(questID)
  if not idx then return nil end
  local link, texture, charges, showWhenComplete = call(rawget(_G, "GetQuestLogSpecialItemInfo"), idx)
  link = str(link)
  if not link then return nil end
  local itemID = num(tonumber(link:match("item:(%d+)")))
  if not itemID or itemID <= 0 then return nil end
  local cl = rawget(_G, "C_QuestLog")
  if type(cl) == "table" and flag(call(cl.ReadyForTurnIn, questID)) and not flag(showWhenComplete) then return nil end
  local tex = num(texture)
  if not tex then
    local t = str(texture)
    if t and #t <= 200 and not t:find("[%c|]") then tex = t end
  end
  return { itemID = floor(itemID), texture = tex, charges = num(charges), logIndex = idx }
end

local function countOf(b)
  local ci = rawget(_G, "C_Item")
  local n
  if type(ci) == "table" then n = num(call(ci.GetItemCount, b.itemID, false, true)) end
  if not n and type(GetItemCount) == "function" then n = num(call(GetItemCount, b.itemID, false, true)) end
  return n
end

-- ---------------------------------------------------------------- holder and pool

local function holder()
  if S.holder then return S.holder end
  if inCombat() then return nil end
  local ok, h = pcall(CreateFrame, "Frame", nil, UIParent)
  if not ok or not h then return nil end
  h:SetAllPoints(UIParent)
  try(h, "SetFrameStrata", S.strata)
  try(h, "SetFrameLevel", QIB.LEVEL)
  try(h, "EnableMouse", false)
  if S.alpha then try(h, "SetAlpha", S.alpha) end
  S.holder = h
  return h
end

local function hideTip(b)
  local tt = rawget(_G, "GameTooltip")
  if tt and type(tt.GetOwner) == "function" and tt:GetOwner() == b then pcall(tt.Hide, tt) end
end

local function onEnter(b)
  if not (b.questID and b.itemID) then return end
  local tt = rawget(_G, "GameTooltip")
  if not tt then return end
  pcall(tt.SetOwner, tt, b, "ANCHOR_LEFT")
  local idx = logIndexOf(b.questID)
  local done = false
  if idx and type(tt.SetQuestLogSpecialItem) == "function" then done = pcall(tt.SetQuestLogSpecialItem, tt, idx) end
  if not done and type(tt.SetItemByID) == "function" then pcall(tt.SetItemByID, tt, b.itemID) end
  pcall(tt.Show, tt)
end

-- new secure button (never in combat). Scripts and child regions are set once here; later only attributes change.
local function newButton()
  local h = holder()
  if not h or S.created >= QIB.POOL_MAX then return nil end
  local ok, b = pcall(CreateFrame, "Button", nil, h, QIB.TEMPLATE)
  if not ok or type(b) ~= "table" then return nil end
  S.created = S.created + 1
  b:SetSize(QIB.SIZE, QIB.SIZE)
  b:Hide()
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(b)
  local count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 2)
  local okC, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
  if okC and cd then
    cd:SetAllPoints(b)
    try(cd, "SetDrawEdge", false)
  else
    cd = nil
  end
  try(b, "SetHighlightTexture", "Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetScript("OnEnter", function(self)
    local okE, err = pcall(onEnter, self)
    if not okE then report(err) end
  end)
  b:SetScript("OnLeave", hideTip)
  b.icon, b.count, b.cooldown = icon, count, cd
  b.eveQuestItem = true
  S.all[#S.all + 1] = b
  return b
end

-- Questie's "FakeHide": no item, no click (outside combat only)
local function fakeHide(b)
  b:SetAttribute("type1", nil)
  b:SetAttribute("item1", nil)
  b:RegisterForClicks()
end

-- visual only (allowed in combat): the button looks empty until it can really be released
local function blank(b)
  try(b.icon, "SetTexture", nil)
  try(b.count, "SetText", "")
  if b.cooldown then try(b.cooldown, "Clear") end
end

local function take()
  local b = table.remove(S.free)
  if b then return b end
  return newButton()
end

local function putBack(b)
  hideTip(b)
  fakeHide(b)
  b:ClearAllPoints()
  b:Hide()
  blank(b)
  if b.questID then S.byQuest[b.questID] = nil end
  b.questID, b.itemID, b.row, b.opts, b.releaseWanted, b.stale = nil, nil, nil, nil, nil, nil
  S.free[#S.free + 1] = b
end

-- ---------------------------------------------------------------- in-place refresh (combat safe)

local function refresh(b)
  if not (b.questID and b.itemID) then return false end
  local idx = logIndexOf(b.questID)
  local item = idx and QIB.itemOf(b.questID)
  if not item or item.itemID ~= b.itemID then
    -- quest or item gone: look empty now, really released (or re-set) after combat / at once outside it
    blank(b)
    b.stale = true
    S.pending = true
    return false
  end
  if item.texture then try(b.icon, "SetTexture", item.texture) end
  local n = countOf(b) or item.charges
  try(b.count, "SetText", (n and n > 1) and tostring(floor(n)) or "")
  if b.cooldown then
    local start, duration, enable = call(rawget(_G, "GetQuestLogSpecialItemCooldown"), idx)
    start, duration = num(start), num(duration)
    local on = not isSecret(enable) and (enable == 1 or enable == true)
    if on and start and duration and duration > 0 then try(b.cooldown, "SetCooldown", start, duration) else try(b.cooldown, "Clear") end
  end
  local r = call(rawget(_G, "IsQuestLogSpecialItemInRange"), idx)
  local out = not isSecret(r) and (r == 0 or r == false)
  local c = QIB.OUT_OF_RANGE
  if out then try(b.icon, "SetVertexColor", c[1], c[2], c[3], 1) else try(b.icon, "SetVertexColor", 1, 1, 1, 1) end
  return true
end

local function stopTicker()
  local t = S.ticker
  S.ticker = nil
  if t and type(t.Cancel) == "function" then pcall(t.Cancel, t) end
end

local function startTicker()
  if S.ticker or next(S.byQuest) == nil then return end
  if type(C_Timer) ~= "table" or type(C_Timer.NewTicker) ~= "function" then return end
  local ok, t = pcall(C_Timer.NewTicker, QIB.TICK_SEC, function()
    if next(S.byQuest) == nil then
      stopTicker()
      return
    end
    QIB.update()
  end)
  if ok then S.ticker = t end
end

function QIB.update()
  local n = 0
  for _, b in pairs(S.byQuest) do
    local ok, r = pcall(refresh, b)
    if not ok then report(r) elseif r then n = n + 1 end
  end
  -- a quest/item that went away outside combat: tidy up at once
  if S.pending and not inCombat() and QIB._afterCombat then QIB._afterCombat("item") end
  return n
end

-- ---------------------------------------------------------------- placing (outside combat only)

local function validRow(row)
  if type(row) ~= "table" or isSecret(row) then return false end
  local t = try(row, "GetObjectType")
  if not (str(t) and QIB.ROW_TYPES[t]) then return false end
  if flag(try(row, "IsForbidden")) then return false end
  return true
end

local function sizeOf(opts)
  local s = num(opts and opts.size) or QIB.SIZE
  return math.max(QIB.SIZE_MIN, math.min(QIB.SIZE_MAX, s))
end

-- centre of the row inside the clip frame?
local function inClip(row, clip)
  if type(clip) ~= "table" then return true end
  local cx, cy = try(row, "GetCenter")
  local l, r, t, bt = num(try(clip, "GetLeft")), num(try(clip, "GetRight")), num(try(clip, "GetTop")), num(try(clip, "GetBottom"))
  cx, cy = num(cx), num(cy)
  if not (cx and cy and l and r and t and bt) then return true end
  local rs, cs = num(try(row, "GetEffectiveScale")) or 1, num(try(clip, "GetEffectiveScale")) or 1
  cx, cy = cx * rs / cs, cy * rs / cs
  return cx >= l and cx <= r and cy >= bt and cy <= t
end

-- measure the row and put the button there (relative to the holder); false = row not laid out / not visible / clipped
local function place(b)
  local row, h = b.row, S.holder
  if not (row and h) then return false end
  local left, top = num(try(row, "GetLeft")), num(try(row, "GetTop"))
  local visible = try(row, "IsVisible")
  if not (left and top) or visible == false or not inClip(row, b.opts and b.opts.clip) then
    b:Hide()
    return false
  end
  local rs, hs = num(try(row, "GetEffectiveScale")) or 1, num(try(h, "GetEffectiveScale")) or 1
  if hs <= 0 then hs = 1 end
  local o = b.opts or {}
  local dx, dy = num(o.dx) or QIB.DX, num(o.dy) or QIB.DY
  local size = sizeOf(o)
  if o.scaled then
    local k = rs / hs
    dx, dy, size = dx * k, dy * k, math.max(QIB.SIZE_MIN, math.min(QIB.SIZE_MAX * 2, size * k))
  end
  b:SetSize(size, size)
  b:ClearAllPoints()
  b:SetPoint("TOPRIGHT", h, "BOTTOMLEFT", left * rs / hs + dx, top * rs / hs + dy)
  local lvl = num(try(row, "GetFrameLevel"))
  if lvl then try(b, "SetFrameLevel", floor(lvl) + 5) end
  b:Show()
  return true
end

local function laterLayout()
  if S.layoutQueued or type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
  S.layoutQueued = true
  pcall(C_Timer.After, 0, function()
    S.layoutQueued = false
    QIB.layout()
  end)
end

-- ---------------------------------------------------------------- public API

function QIB.button(questID)
  local id = questKey(questID)
  return id and S.byQuest[id] or nil
end

function QIB.acquire(questID, row, opts)
  if not available() then return nil, "retail" end
  local id = questKey(questID)
  if not id then return nil, "quest" end
  local b = S.byQuest[id]
  if inCombat() then
    -- nothing secure may change now: an existing button only refreshes its texts, everything else waits for the end of combat
    if b and not b.releaseWanted then
      pcall(refresh, b)
      if b.row ~= row or b.opts ~= opts then
        b.row, b.opts = validRow(row) and row or b.row, type(opts) == "table" and opts or b.opts
        S.pending = true
      end
      return b, "combat"
    end
    S.pending = true
    return nil, "combat"
  end
  if not validRow(row) then return nil, "row" end
  local item = QIB.itemOf(id)
  if not item then
    if b then putBack(b) end
    return nil, "noItem"
  end
  if not b then
    b = take()
    if not b then return nil, "pool" end
    S.byQuest[id] = b
  end
  if b.itemID ~= item.itemID or b.questID ~= id or b.stale then
    b:SetAttribute("type1", "item")
    b:SetAttribute("item1", "item:" .. item.itemID)
    b:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
  end
  b.questID, b.itemID, b.stale, b.releaseWanted = id, item.itemID, nil, nil
  b.row, b.opts = row, type(opts) == "table" and opts or nil
  if not place(b) then laterLayout() end
  pcall(refresh, b)
  startTicker()
  return b, "ok"
end

function QIB.release(questID)
  local id = questKey(questID)
  local b = id and S.byQuest[id]
  if not b then return false end
  if inCombat() then
    blank(b)
    b.releaseWanted = true
    S.pending = true
    return true
  end
  putBack(b)
  if next(S.byQuest) == nil then stopTicker() end
  return true
end

function QIB.releaseAll()
  local ids = {}
  for id in pairs(S.byQuest) do ids[#ids + 1] = id end
  for _, id in ipairs(ids) do QIB.release(id) end
  return #ids
end

function QIB.layout()
  if inCombat() then
    S.pending = true
    return false
  end
  local ids = {}
  for id in pairs(S.byQuest) do ids[#ids + 1] = id end
  for _, id in ipairs(ids) do
    local b = S.byQuest[id]
    if b.releaseWanted or not validRow(b.row) then
      putBack(b)
    elseif b.stale then
      local row, opts = b.row, b.opts
      if not QIB.acquire(id, row, opts) and S.byQuest[id] == b then putBack(b) end
    else
      place(b)
    end
  end
  if next(S.byQuest) == nil then stopTicker() end
  return true
end

function QIB.setStrata(strata)
  if type(strata) ~= "string" or not QIB.STRATA[strata] then return false end
  S.strata = strata
  if not S.holder then return true end
  if inCombat() then
    S.pending = true
    return false
  end
  try(S.holder, "SetFrameStrata", strata)
  return true
end

-- visibility of all buttons at once (E4: the item bar goes away in combat). Only the holder's alpha changes, which the client
-- allows in combat; attributes, clicks and places stay until QIB.release/releaseAll after combat. nil/1 = visible again.
function QIB.setAlpha(a)
  a = num(a) or 1
  a = math.max(0, math.min(1, a))
  S.alpha = a
  if S.holder then try(S.holder, "SetAlpha", a) end
  return true
end

function QIB.onRelayout(fn)
  if type(fn) ~= "function" then return false end
  S.listeners[#S.listeners + 1] = fn
  return true
end

function QIB.status()
  local bound = 0
  for _ in pairs(S.byQuest) do bound = bound + 1 end
  return { bound = bound, free = #S.free, created = S.created, pending = S.pending, holder = S.holder ~= nil, installed = S.installed }
end

-- end of combat: do what was noted (release, re-set, move), then let the window rebuild its rows
local function afterCombat(reason)
  if not S.pending or inCombat() then return end
  S.pending = false
  QIB.layout()
  if S.holder then try(S.holder, "SetFrameStrata", S.strata) end
  for _, fn in ipairs(S.listeners) do
    local ok, err = pcall(fn, reason or "combat")
    if not ok then report(err) end
  end
end
QIB._afterCombat = afterCombat

local function onEvent(event)
  if event == "PLAYER_REGEN_ENABLED" then
    afterCombat()
  elseif next(S.byQuest) ~= nil then
    QIB.update()
  end
end

-- Forever only: in Retail nothing is registered and no frame is made
function QIB.install()
  if S.installed or not available() then return S.installed end
  local core = ns.Core
  if not (core and core.on) then return false end
  S.installed = true
  for _, ev in ipairs(QIB.EVENTS) do core.on(ev, onEvent) end
  return true
end

QIB.install()
