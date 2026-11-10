-- Page management. Pages register themselves; the journal window (journal/Frame.lua) switches tabs and hands out its two
-- sheet halves. A page is built lazily on first show, called in pcall, and shows a notice on errors instead of crashing.
-- No ticker, no OnUpdate: redraw on show and when the index finishes in the background (only while the journal is open).
-- Page module contract (journal/pages/<page>.lua), registered at file load with Pages.register(id, page):
-- page = {
--   needs = { index = true, model = false },   defaults
--   Build(page, left, right)    once, on first show; an error leaves the page broken until /reload
--   Refresh(page, data)         on every show and when new data is ready; data = { index, model (only with
--                               needs.model, may be nil), char (read only), live, texts, now, stale, changed, guest }
--                               In the guest mode (another character's book, read only) data.live = nil (no live API of the
--                               logged-in character), data.guest = { guid, name (raw SV text), lastSeen }, index/model/char
--                               belong to the guest; otherwise data.guest = nil.
--   OnHide(page)                optional
--   subs / GetSub / ShowSub     optional sub-bookmarks (pages with at least two subpages)
-- }
-- Rules: SV/client text only via Sanitize.display (or Texts.fill) and only via SetText/AddLine; no tickers or OnUpdate;
-- list entries through the pool widgets. The window must call Pages.close() on combat start and on close (Pages.hide() when
-- it only switches to the map).
-- Guest mode (Twinks, read only; character list: journal/model/Roster.lua):
--   Pages.setGuest(guid | nil) -> ok, reason   open another character's book (Roster.canOpen decides) or go back (nil);
--                               releases the old guest slots (Index/Model.releaseGuest), sets View.setGuest, calls the
--                               Pages.onGuestChange listeners (fn(guid)), redraws the current page if it stays allowed
--   Pages.guest() -> { guid, name, lastSeen } | nil      Pages.close()  hide + back to the own book (frees the guest)
--   Pages.guestAllows(id, sub) -> bool    Pages.GUEST_HIDDEN / GUEST_HIDDEN_SUBS: pages and sub-bookmarks that stay with
--                               the logged-in character (live data or writing); Pages.subs and Pages.tabs (row.hidden)
--                               already leave them out, Pages.show refuses a hidden page ("nur-eigen"). The journey
--                               sub-bookmarks live in Frame (Frame.SUBTABS_REISE): the UI filters them with guestAllows.
--   Pages.escape(id)           Esc in a sub-view of tab id: back to where a cross-tab jump came from (Frame.jumpBack), otherwise
--                               to the first visible sub-bookmark of the tab
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Pages = {}
Journal.Pages = Pages

Pages.HOME = "reise"
Pages.ORDER = { "reise", "chronik", "dungeons", "kampf", "quests", "plaene", "schaetze", "momente", "notizen" }
Pages.TEXT = ns.Locale.ns("Pages", {
  building = "Tinte trocknet …",
  empty = "Noch keine Einträge in dieser Chronik.",
  noChar = "Für diesen Charakter gibt es noch keine Chronik.",
  error = "Seite konnte nicht gezeichnet werden.",
  soon = "kommt bald",
  tab_reise = "Reise",
  tab_chronik = "Chronik",
  tab_dungeons = "Dungeons",
  tab_kampf = "Kampf",
  tab_quests = "Quests",
  tab_plaene = "Pläne",
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

-- Twinks: what another character's book leaves out (live data of the logged-in character or writing into the SV). Pläne (to-dos,
-- training) belongs wholly to the logged-in character; Dungeons keeps only the runs, Quests only the history (no open quests, zones).
Pages.GUEST_HIDDEN = { notizen = true, plaene = true }
Pages.GUEST_HIDDEN_SUBS = {
  dungeons = { quests = true },
  quests = { offen = true, zonen = true },
  schaetze = { anprobe = true }, -- the model is the logged-in character (SetUnit "player")
}

-- I12 (book reordered, 9 tabs): where the sub-pages of the old order live now. Pages.resolve(id, sub) -> id, sub of the new place
-- (unchanged when nothing moved), so an old call or an old saved marker never leads into the void.
Pages.MOVED = {
  reise = { vorhaben = { "plaene", "vorhaben" } },
  quests = { lehrplan = { "plaene", "lehrplan" }, dungeons = { "dungeons", "quests" } },
  plaene = { offen = { "quests", "offen" } }, -- the open quests were under Pläne for a day (09.11.2026), now back under Quests
  chronik = { dungeons = { "dungeons", "laeufe" } },
}
function Pages.resolve(id, sub)
  local m = type(id) == "string" and Pages.MOVED[id]
  local to = m and type(sub) == "string" and m[sub]
  if to then return to[1], to[2] end
  return id, sub
end

local guestGuid = nil
local guestFns = {}

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
  saveReminder = function(v) return type(v) == "boolean" end, -- reminder window "Save your journey?" (Save.lua); missing = off
  autoShots = function(v) return type(v) == "boolean" end, -- automatic screenshots at special moments (collectors/Moments.lua)
  bookSounds = function(v) return type(v) == "boolean" end,
  worldMap = function(v) return type(v) == "boolean" end,
  worldPins = function(v) return type(v) == "boolean" end, -- note and place to-do pins on the world map (own filter entry); missing = on
  showHiddenChars = function(v) return type(v) == "boolean" end, -- Twinks list: also show the characters taken off the list; missing = off
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
  -- toast when the addon creates a to-do by itself (collectors/Trainer.lua "Zum Lehrer"); missing = on
  todoToast = function(v) return type(v) == "boolean" end,
  -- narrator note at a level-up (what can be learned; collectors/Trainer.lua levelSlip); missing = on
  levelSlip = function(v) return type(v) == "boolean" end,
  -- narrator note at level 10, 20, ... 60 (journal/Meilenstein.lua: the stretch's tally); only the note, the book view stays; missing = on
  milestoneSlip = function(v) return type(v) == "boolean" end,
  trainFilter = function(v) return v == "now" or v == "next" or v == "learned" or v == "all" end,
  kampfHunted = function(v)
    return v == nil or v == "all" or (type(v) == "number" and v == v and v > 0 and v < 2147483648 and v == math.floor(v))
  end,
}
local DEFAULT = { toast = true, toastSound = true, toastMedal = true, toastZone = true, welcome = true, narrator = "own", restReview = false, saveReminder = false, autoShots = true, welcomeAfter = 3600, welcomeSeen = true,
  welcomeQuests = true, welcomeRested = true, welcomePlan = true, bookSounds = true, worldMap = true, worldPins = true,
  albumFilter = "all", showHiddenChars = false, openLocked = false, openGroup = false, openRepeat = false, openClass = true,
  openCategory = false, trainerTodo = true, talentHint = true, todoToast = true, levelSlip = true, milestoneSlip = true, trainFilter = "now" }

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

-- true when page id (and sub-bookmark sub, optional) is shown in the current mode; in the own book always true
function Pages.guestAllows(id, sub)
  if guestGuid == nil then return true end
  if Pages.GUEST_HIDDEN[id] then return false end
  local subs = sub ~= nil and Pages.GUEST_HIDDEN_SUBS[id]
  if subs and subs[sub] then return false end
  return true
end

-- row.hidden = true: the tab is left out in the guest book (not dimmed, gone)
function Pages.tabs()
  local out = {}
  for i, id in ipairs(Pages.ORDER) do
    out[i] = { id = id, label = Pages.LABELS[id], available = pages[id] ~= nil, active = id == currentId,
      hidden = not Pages.guestAllows(id) }
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
  if hiddenSubs[id] or (guestGuid ~= nil and Pages.GUEST_HIDDEN_SUBS[id]) then
    local shown = {}
    for _, s in ipairs(list) do
      if not subHidden(id, s.key) and Pages.guestAllows(id, s.key) then shown[#shown + 1] = s end
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

-- Esc in a sub-view (I12): a cross-tab jump leads back once (Frame.jumpBack), otherwise the first sub-bookmark of the tab
function Pages.escape(id)
  local F = Journal.Frame
  if F and type(F.jumpBack) == "function" then
    local ok, done = pcall(F.jumpBack, id)
    if not ok then note(done) elseif done then return true end
  end
  local list = Pages.subs(id)
  if not list then return false end
  return Pages.showSub(id, list[1].key)
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
-- guest mode: index and model of the guest (the own slots stay untouched), no live object, data.guest set
local function fetch(page, quiet)
  local needs = type(page.needs) == "table" and page.needs or {}
  local g = guestGuid
  local data = { live = (g == nil) and Journal.Live or nil, texts = Journal.Texts, now = time() }
  if g ~= nil then
    data.guest = Pages.guest()
    if not data.guest then return nil, "kein-charakter" end
  end
  if needs.index ~= false then
    local Index = Journal.Index
    if not Index then return nil, "fehler" end
    local index, why = Index.get({ guid = g, noRebuild = quiet })
    if not index then return nil, why end
    if g ~= nil and index.guid ~= g then return nil, "fehler" end -- never draw another character's index by mistake
    data.index, data.char, data.stale = index, index.char, index.stale == true
  end
  if needs.model then
    local Model = Journal.Model
    local model, why
    if Model and Model.get then model, why = Model.get({ guid = g, now = data.now, noRebuild = quiet }) end
    data.model, data.modelReason = model, why
    if model and model.stale then data.stale = true end
    if not data.char then
      if g ~= nil then
        local db = EveNChronicleDB
        data.char = type(db) == "table" and type(db.chars) == "table" and db.chars[g] or nil
      elseif ns.Store and ns.Store.char then
        data.char = ns.Store.char()
      end
    end
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
  if not Pages.guestAllows(id) then -- stays with the logged-in character: nothing is drawn in a guest book
    setStatus(st, nil)
    return "nur-eigen"
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
  if not Pages.guestAllows(id) then return false, "nur-eigen" end
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

-- Guest mode (see the head comment). The name stays raw SV text: the UI shows it only via Sanitize.display.
function Pages.guest()
  local g = guestGuid
  if g == nil then return nil end
  local db = EveNChronicleDB
  local char = type(db) == "table" and type(db.chars) == "table" and db.chars[g] or nil
  if type(char) ~= "table" then return nil end
  local info = type(char.info) == "table" and char.info or {}
  local name = info.name
  name = (type(name) == "string" and not isSecret(name) and name ~= "") and name or nil
  local seen = info.lastSeen
  seen = (type(seen) == "number" and not isSecret(seen) and seen == seen and seen > 0 and seen < 2 ^ 40) and seen or nil
  -- fullName: "Vorname Nachname" (Forever, Names.lua) or the name; also raw, shown only via Sanitize.display
  local Names = ns.Names
  local full = name and Names and Names.fullName(info) or name
  return { guid = g, name = name, fullName = full, lastSeen = seen }
end

function Pages.onGuestChange(fn)
  if type(fn) ~= "function" then return false end
  for _, f in ipairs(guestFns) do
    if f == fn then return true end
  end
  guestFns[#guestFns + 1] = fn
  return true
end

local function releaseGuest()
  local Index, Model, View = Journal.Index, Journal.Model, Journal.View
  if Index and type(Index.releaseGuest) == "function" then pcall(Index.releaseGuest) end
  if Model and type(Model.releaseGuest) == "function" then pcall(Model.releaseGuest) end
  if View and type(View.setGuest) == "function" then pcall(View.setGuest, nil) end
end

function Pages.setGuest(guid)
  if guid ~= nil then
    if type(guid) ~= "string" or isSecret(guid) then return false, "unbekannt" end
    local R = Journal.Roster
    if not R or type(R.canOpen) ~= "function" then return false, "fehler" end
    local ok, why = R.canOpen(guid)
    if not ok then return false, why end
  end
  if guid == guestGuid then return true end
  if guestGuid ~= nil then releaseGuest() end
  guestGuid = guid
  local View = Journal.View
  if guid ~= nil and View and type(View.setGuest) == "function" then pcall(View.setGuest, guid) end
  for _, st in pairs(state) do st.lastIndex = nil end -- the next draw counts as changed (other character)
  for _, fn in ipairs(guestFns) do
    local ok, err = pcall(fn, guid)
    if not ok then note(err) end
  end
  if shown and currentId and Pages.guestAllows(currentId) then
    local key = Pages.sub(currentId)
    local page, st = pages[currentId], state[currentId]
    -- the page may still show a sub-bookmark the guest book leaves out: switch to the first allowed one
    if key and st and st.built and type(page.GetSub) == "function" then
      local ok, cur = pcall(page.GetSub, page)
      if ok and cur ~= key then Pages.showSub(currentId, key) end
    end
    draw(currentId)
  end
  return true
end

function Pages.close()
  Pages.hide()
  Pages.setGuest(nil)
end

local function onData()
  if shown and currentId then draw(currentId, true) end
end

local function onModelData()
  local page = currentId and pages[currentId]
  if page and type(page.needs) == "table" and page.needs.model then onData() end
end

-- own builds redraw only the own book, guest builds only the open guest book
if Journal.Index and Journal.Index.onReady then
  Journal.Index.onReady(function() if guestGuid == nil then onData() end end)
end
if Journal.Index and type(Journal.Index.onGuestReady) == "function" then
  Journal.Index.onGuestReady(function(_, guid) if guid ~= nil and guid == guestGuid then onData() end end)
end
if Journal.Model and type(Journal.Model.onReady) == "function" then
  Journal.Model.onReady(function() if guestGuid == nil then onModelData() end end)
end
if Journal.Model and type(Journal.Model.onGuestReady) == "function" then
  Journal.Model.onGuestReady(function(_, guid) if guid ~= nil and guid == guestGuid then onModelData() end end)
end
