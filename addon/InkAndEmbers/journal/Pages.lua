-- Page management. Pages register themselves; the journal window (journal/Frame.lua) switches tabs and hands out its two
-- sheet halves. A page is built lazily on first show, called in pcall, and shows a notice on errors instead of crashing.
-- No ticker, no OnUpdate: redraw on show and when the index finishes in the background (only while the journal is open).
-- Page module contract (journal/pages/<page>.lua), registered at file load with Pages.register(id, page):
-- page = {
--   needs = { index = true, model = false },   defaults
--   Build(page, left, right)    once, on first show; an error leaves the page broken until /reload
--   Refresh(page, data)         on every show and when new data is ready; data = { index, model (only with
--                               needs.model, may be nil), char (read only), live, texts, now, stale, changed }
--   OnHide(page)                optional
--   subs / GetSub / ShowSub     optional sub-bookmarks (pages with at least two subpages)
-- }
-- Rules: SV/client text only via Sanitize.display (or Texts.fill) and only via SetText/AddLine; no tickers or OnUpdate;
-- list entries through the pool widgets. The window must call Pages.hide() on combat start and on close.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Pages = {}
Journal.Pages = Pages

Pages.HOME = "reise"
Pages.ORDER = { "reise", "chronik", "kampf", "quests", "schaetze", "momente", "notizen" }
Pages.TEXT = ns.Locale.ns("Pages", {
  building = "Tinte trocknet …",
  empty = "Noch keine Einträge in dieser Chronik.",
  noChar = "Für diesen Charakter gibt es noch keine Chronik.",
  error = "Seite konnte nicht gezeichnet werden.",
  soon = "kommt bald",
  tab_reise = "Reise",
  tab_chronik = "Chronik",
  tab_kampf = "Kampf",
  tab_quests = "Quests",
  tab_schaetze = "Schätze",
  tab_momente = "Momente",
  tab_notizen = "Notizen",
})
-- Tab labels per page id (looked up lazily: the language is only known at ADDON_LOADED)
Pages.LABELS = setmetatable({}, { __index = function(_, id) return Pages.TEXT["tab_" .. tostring(id)] end })
Pages.ALBUM_FILTERS = { all = true, levels = true, fights = true, finds = true, places = true }
Pages.errors = 0

local KNOWN = {}
for i, id in ipairs(Pages.ORDER) do KNOWN[id] = i end

local pages = {}
local state = {}
local changeFns = {}
local left, right = nil, nil
local currentId, shown = nil, false

local function note(err)
  Pages.errors = Pages.errors + 1
  local ok, s = pcall(tostring, err)
  Pages.lastError = (ns.Sanitize and ns.Sanitize.field(ok and s or "?")) or "?"
end

local function uiTable(create)
  local db = EveNChronicleDB
  if type(db) ~= "table" then return nil end
  if type(db.ui) ~= "table" then
    if not create then return nil end
    db.ui = {}
  end
  return db.ui
end

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local CHECK = {
  toast = function(v) return type(v) == "boolean" end,
  toastSound = function(v) return type(v) == "boolean" end,
  toastMedal = function(v) return type(v) == "boolean" end,
  toastZone = function(v) return type(v) == "boolean" end,
  welcome = function(v) return type(v) == "boolean" end,
  -- welcome note: minimum absence in seconds (0 = at every login) and which info lines the return note shows
  welcomeAfter = function(v) return v == 0 or v == 3600 or v == 7200 or v == 14400 or v == 28800 or v == 86400 end,
  welcomeSeen = function(v) return type(v) == "boolean" end,
  welcomeQuests = function(v) return type(v) == "boolean" end,
  welcomeRested = function(v) return type(v) == "boolean" end,
  welcomePlan = function(v) return type(v) == "boolean" end,
  -- narrator of the welcome card: "own" | "random" | an id of Theme.NARRATORS
  narrator = function(v)
    if v == "own" or v == "random" then return true end
    local Theme = Journal.Theme
    for _, id in ipairs(Theme and Theme.NARRATORS or {}) do
      if v == id then return true end
    end
    return false
  end,
  restReview = function(v) return type(v) == "boolean" end,
  autoShots = function(v) return type(v) == "boolean" end, -- automatic screenshots at special moments (collectors/Moments.lua)
  bookSounds = function(v) return type(v) == "boolean" end,
  worldMap = function(v) return type(v) == "boolean" end,
  albumFilter = function(v) return type(v) == "string" and Pages.ALBUM_FILTERS[v] == true end,
  openZone = function(v)
    return v == "all" or (type(v) == "number" and v == v and v > 0 and v < 2147483648 and v == math.floor(v))
  end,
  openLocked = function(v) return type(v) == "boolean" end,
  openGroup = function(v) return type(v) == "boolean" end,
  openRepeat = function(v) return type(v) == "boolean" end,
  openClass = function(v) return type(v) == "boolean" end,
  openCategory = function(v) return type(v) == "boolean" end,
  -- Lehrplan (WoW Forever): automatic to-do "Zum Lehrer" after a level-up, notice about free talent points, list filter
  trainerTodo = function(v) return type(v) == "boolean" end,
  talentHint = function(v) return type(v) == "boolean" end,
  trainFilter = function(v) return v == "now" or v == "next" or v == "learned" or v == "all" end,
  kampfHunted = function(v)
    return v == nil or v == "all" or (type(v) == "number" and v == v and v > 0 and v < 2147483648 and v == math.floor(v))
  end,
}
local DEFAULT = { toast = true, toastSound = true, toastMedal = true, toastZone = true, welcome = true, narrator = "own", restReview = false, autoShots = true, welcomeAfter = 3600, welcomeSeen = true,
  welcomeQuests = true, welcomeRested = true, welcomePlan = true, bookSounds = true, worldMap = true,
  albumFilter = "all", openLocked = false, openGroup = false, openRepeat = false, openClass = true,
  openCategory = false, trainerTodo = true, talentHint = true, trainFilter = "now" }

-- Old saved games had two switches: "welcome" (greeting) and "welcomeSlip" (welcome-back note). Now there is one: on only if both
-- were on (nil = default on). The old key is removed, so this runs once per saved game.
local function migrateWelcome(ui)
  if ui.welcomeSlip == nil then return end
  if ui.welcomeSlip == false then ui.welcome = false end
  ui.welcomeSlip = nil
end

function Pages.setting(key)
  local check = CHECK[key]
  if not check then return nil end
  local ui = uiTable(false)
  if ui and ui.welcomeSlip ~= nil then migrateWelcome(ui) end
  local v = ui and ui[key]
  if v ~= nil and not isSecret(v) and check(v) then return v end
  return DEFAULT[key]
end

function Pages.setSetting(key, value)
  local check = CHECK[key]
  if not check or isSecret(value) or not check(value) then return false end
  local ui = uiTable(true)
  if not ui then return false end
  if ui.welcomeSlip ~= nil then migrateWelcome(ui) end
  ui[key] = value
  return true
end

function Pages.register(id, page)
  if type(id) ~= "string" or not KNOWN[id] or pages[id] or type(page) ~= "table" then return false end
  if type(page.Build) ~= "function" or type(page.Refresh) ~= "function" then return false end
  if page.OnHide ~= nil and type(page.OnHide) ~= "function" then return false end
  page.id = id
  pages[id] = page
  return true
end

function Pages.isAvailable(id)
  return type(id) == "string" and pages[id] ~= nil
end

function Pages.tabs()
  local out = {}
  for i, id in ipairs(Pages.ORDER) do
    out[i] = { id = id, label = Pages.LABELS[id], available = pages[id] ~= nil, active = id == currentId }
  end
  return out
end

function Pages.initial()
  return Pages.HOME
end

function Pages.statusText(id)
  local st = state[id]
  if not st or not st.overlay or not st.overlay:IsShown() then return nil end
  local t = st.status:GetText()
  return (type(t) == "string" and t ~= "") and t or nil
end

function Pages.current() return currentId end
function Pages.isShown() return shown end

function Pages.onChange(fn)
  if type(fn) ~= "function" then return false end
  for _, f in ipairs(changeFns) do
    if f == fn then return true end
  end
  changeFns[#changeFns + 1] = fn
  return true
end

local subFns = {}

-- Sub-bookmarks that a client hides (e.g. WoW Forever only parts in Retail): Pages.hideSub(id, key, fn), fn() -> true = hidden.
-- Read live in Pages.subs; the other bookmarks keep their order. A page with fewer than two visible bookmarks has none.
local hiddenSubs = {}

function Pages.hideSub(id, key, fn)
  if type(id) ~= "string" or type(key) ~= "string" or type(fn) ~= "function" then return false end
  hiddenSubs[id] = hiddenSubs[id] or {}
  hiddenSubs[id][key] = fn
  return true
end

local function subHidden(id, key)
  local fn = hiddenSubs[id] and hiddenSubs[id][key]
  if not fn then return false end
  local ok, hide = pcall(fn)
  return ok and hide == true
end

function Pages.subs(id)
  local page = type(id) == "string" and pages[id]
  local list = page and page.subs
  if type(list) ~= "table" then return nil end
  if hiddenSubs[id] then
    local shown = {}
    for _, s in ipairs(list) do
      if not subHidden(id, s.key) then shown[#shown + 1] = s end
    end
    list = shown
  end
  if #list < 2 then return nil end
  return list
end

function Pages.sub(id)
  local list = Pages.subs(id)
  if not list then return nil end
  local page, st = pages[id], state[id]
  if st and st.built and type(page.GetSub) == "function" then
    local ok, key = pcall(page.GetSub, page)
    if ok and type(key) == "string" then
      for _, s in ipairs(list) do
        if s.key == key then return key end
      end
    elseif not ok then
      note(key)
    end
  end
  return list[1].key
end

function Pages.showSub(id, key)
  local list = Pages.subs(id)
  local page, st = list and pages[id], state[id]
  if not (page and st and st.built and shown and currentId == id and type(page.ShowSub) == "function") then return false end
  local known = false
  for _, s in ipairs(list) do
    if s.key == key then known = true end
  end
  if not known then return false end
  local ok, err = pcall(page.ShowSub, page, key)
  if not ok then
    Pages.fail(id, err)
    return false
  end
  Pages.subChanged(id)
  return true
end

function Pages.onSubChange(fn)
  if type(fn) ~= "function" then return false end
  for _, f in ipairs(subFns) do
    if f == fn then return true end
  end
  subFns[#subFns + 1] = fn
  return true
end

function Pages.subChanged(id)
  for _, fn in ipairs(subFns) do
    local ok, err = pcall(fn, id)
    if not ok then note(err) end
  end
end

function Pages.attach(l, r)
  if type(l) ~= "table" or type(r) ~= "table" then return false end
  if l == left and r == right then return true end
  if currentId and shown then Pages.hide() end
  for _, st in pairs(state) do
    if st.left then st.left:Hide() end
    if st.right then st.right:Hide() end
  end
  left, right, state, currentId = l, r, {}, nil
  return true
end

local function holders(id)
  local st = state[id]
  if st then return st end
  st = {}
  st.left = CreateFrame("Frame", nil, left)
  st.left:SetAllPoints(left)
  st.right = CreateFrame("Frame", nil, right)
  st.right:SetAllPoints(right)
  local overlay = CreateFrame("Frame", nil, st.left)
  overlay:SetAllPoints(st.left)
  if overlay.SetFrameLevel and st.left.GetFrameLevel then
    local lvl = st.left:GetFrameLevel()
    if type(lvl) == "number" then overlay:SetFrameLevel(lvl + 20) end
  end
  local fs = overlay:CreateFontString(nil, "OVERLAY")
  local W = Journal.Widgets
  if W and W.FONT then fs:SetFont(W.FONT.title, 16, "") end
  if W and W.ink then W.ink(fs, "title") end
  if W and W.color then fs:SetTextColor(W.color("sepia")) end
  fs:SetPoint("CENTER", overlay, "CENTER", 0, 0)
  fs:SetText("")
  st.overlay, st.status = overlay, fs
  overlay:Hide()
  state[id] = st
  return st
end

local function setStatus(st, text)
  if text then
    st.status:SetText(text)
    st.overlay:Show()
  else
    st.status:SetText("")
    st.overlay:Hide()
  end
end

local function build(id)
  local page, st = pages[id], holders(id)
  if st.broken then return false end
  if st.built then return true end
  local ok, err = pcall(page.Build, page, st.left, st.right)
  if not ok then
    st.broken = true
    note(err)
    return false
  end
  st.built = true
  return true
end

-- quiet = redraw from an onReady callback: draw the existing state and do not trigger a rebuild, otherwise every finished
-- build that was followed by new rows would keep the next round going.
local function fetch(page, quiet)
  local needs = type(page.needs) == "table" and page.needs or {}
  local data = { live = Journal.Live, texts = Journal.Texts, now = time() }
  if needs.index ~= false then
    local Index = Journal.Index
    if not Index then return nil, "fehler" end
    local index, why = Index.get({ noRebuild = quiet })
    if not index then return nil, why end
    data.index, data.char, data.stale = index, index.char, index.stale == true
  end
  if needs.model then
    local Model = Journal.Model
    local model, why
    if Model and Model.get then model, why = Model.get({ now = data.now, noRebuild = quiet }) end
    data.model, data.modelReason = model, why
    if model and model.stale then data.stale = true end
    if not data.char and ns.Store and ns.Store.char then data.char = ns.Store.char() end
  end
  return data
end

local REASON_TEXT = { baut = "building", ["keine-daten"] = "noChar", ["kein-charakter"] = "noChar" }

local function draw(id, quiet)
  local page, st = pages[id], state[id]
  if not page or not st then return "fehler" end
  if st.broken then
    setStatus(st, Pages.TEXT.error)
    return "fehler"
  end
  local ok, data, why = pcall(fetch, page, quiet)
  if not ok then
    note(data)
    setStatus(st, Pages.TEXT.error)
    return "fehler"
  end
  if not data then
    local key = REASON_TEXT[why] or "error"
    setStatus(st, Pages.TEXT[key])
    if why == "baut" then return "baut" end
    if key == "noChar" then return "keine-daten" end
    return "fehler"
  end
  data.changed = data.index ~= st.lastIndex or data.index == nil
  local rok, err = pcall(page.Refresh, page, data)
  if not rok then
    note(err)
    setStatus(st, Pages.TEXT.error)
    return "fehler"
  end
  st.lastIndex = data.index
  setStatus(st, nil)
  return "ok"
end

local function hideCurrent()
  local id = currentId
  if not id then return end
  local page, st = pages[id], state[id]
  if page and page.OnHide and st and st.built then
    local ok, err = pcall(page.OnHide, page)
    if not ok then note(err) end
  end
  if st then
    st.left:Hide()
    st.right:Hide()
  end
end

function Pages.show(id)
  if not pages[id] then return false, "nicht-verfuegbar" end
  if not left or not right then return false, "fehler" end
  if currentId ~= id or not shown then
    if shown then hideCurrent() end
    currentId, shown = id, true
    for _, fn in ipairs(changeFns) do
      local ok, err = pcall(fn, id)
      if not ok then note(err) end
    end
  end
  local st = holders(id)
  st.left:Show()
  st.right:Show()
  build(id)
  return true, draw(id)
end

function Pages.refresh()
  if not shown or not currentId then return nil end
  return draw(currentId)
end

function Pages.fail(id, err)
  note(err)
  local st = type(id) == "string" and state[id] or nil
  if st then setStatus(st, Pages.TEXT.error) end
end

function Pages.hide()
  if not shown then return end
  hideCurrent()
  shown = false
end

local function onData()
  if shown and currentId then draw(currentId, true) end
end

if Journal.Index and Journal.Index.onReady then Journal.Index.onReady(onData) end
if Journal.Model and type(Journal.Model.onReady) == "function" then
  Journal.Model.onReady(function()
    local page = currentId and pages[currentId]
    if page and type(page.needs) == "table" and page.needs.model then onData() end
  end)
end
