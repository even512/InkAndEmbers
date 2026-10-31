-- Campfire talk UI ("notes at the fire"). While sitting at a campfire (session from collectors/Campfire.lua), up to three
-- singed paper scraps float above the fire, each with a conversation suggestion (journal/model/CampfireTalk.lua). Left click
-- says it in /say, right click discards; a new note floats in. Standing up, moving or combat removes everything.
-- Sending: C_ChatInfo.SendChatMessage(text, "SAY") (fallback: global SendChatMessage) directly in the note's OnClick
-- (hardware event, required for SAY in the open world), no timer in between, in pcall. At most one line per FireNotes.THROTTLE s;
-- the text is cleaned again with CampfireTalk.clean. On failure the note stays, a hint goes to the own chat and the line is
-- put into the edit box if possible.
-- Looks: five shapes (Media/FireNote1..5.tga), random shape and mirroring per note, each with a fixed text area
-- (journal/FireNoteAreas.lua, generated, mirrored with it). Text that does not fit shrinks down to FireNotes.FONT.min,
-- else another suggestion is drawn. The reduceMotion setting turns off floating and fading.
-- Flow: after your first sent line all notes vanish and a small spark stays; clicking it brings 1-2 follow-up notes. After
-- FireNotes.SILENCE s of silence one follow-up appears by itself (at most FireNotes.AUTO_MAX per session).
-- Position: edit mode element "fire" (journal/EditMode.lua) via FireNotes.hud.place, else FireNotes.DEFAULT_POS.
-- Settings (EveNChronicleDB.campfire): notes, show = "cardFirst" | "both" | "notesOnly".
local _, ns = ...

local Journal = ns.Journal
if not Journal then return end

local FireNotes = {}
Journal.FireNotes = FireNotes

FireNotes.COUNT = 3
FireNotes.NOTE_W, FireNotes.NOTE_H = 220, 110      -- note texture is 512 x 256, so 2:1
FireNotes.GAP = 14
FireNotes.STAGGER = { 0, 14, 4 }
FireNotes.FLOAT = 4
FireNotes.FLOAT_TIME = { 3.4, 3.8, 3.1 }
FireNotes.FLOAT_PHASE = { 0, 1.1, 2.0 }
FireNotes.FADE = 0.4
FireNotes.REFILL = 1.0
FireNotes.THROTTLE = 3
FireNotes.FONT = { max = 15, min = 10 }
FireNotes.PICK_TRIES = 4
FireNotes.SHAPES = 5
FireNotes.CARD_GRACE = 2
FireNotes.CARD_POLL = 0.5
FireNotes.CARD_WAIT_MAX = 60
FireNotes.TEST_TIME = 120
FireNotes.SILENCE = 30
FireNotes.AUTO_MAX = 2
FireNotes.SPARK_N = 2
FireNotes.SPARK_THROTTLE = 3
FireNotes.SPARK_SIZE = 34
FireNotes.FOLLOW_AVOID = 4
FireNotes.TOPICS = { death = true, rare = true, quest = true, newzone = true, level = true }
FireNotes.W = FireNotes.COUNT * FireNotes.NOTE_W + (FireNotes.COUNT - 1) * FireNotes.GAP
FireNotes.H = FireNotes.NOTE_H + 2 * FireNotes.FLOAT + 16
FireNotes.DEFAULT_POS = { point = "CENTER", x = 0, y = 60 }
FireNotes.DEFAULTS = { notes = true, show = "cardFirst" }
FireNotes.SHOW_MODES = { cardFirst = true, both = true, notesOnly = true }

FireNotes.TEXT = ns.Locale.ns("FireNotes", {
  tipTitle = "Zettel am Feuer",
  tipHow = "Linksklick: sagen · Rechtsklick: verwerfen",
  tipWhy = "weil: %s",
  tipTest = "Testanzeige – gesagt wird trotzdem.",
  wait = "Lagerfeuer: Einen Moment – höchstens ein Satz alle %d Sekunden.",
  combat = "Lagerfeuer: Im Kampf wird nichts gesagt.",
  failed = "Lagerfeuer: Der Satz ließ sich nicht senden.",
  inEditBox = "Lagerfeuer: Der Satz liegt in der Eingabezeile, Enter sagt ihn.",
  testOn = "Lagerfeuer: Testzettel – Linksklick sagt den Satz wirklich in /sagen, Rechtsklick verwirft. \"/chronik feuer test\" blendet sie aus.",
  testOff = "Lagerfeuer: Testzettel ausgeblendet.",
  testEmpty = "Lagerfeuer: Keine Vorschläge verfügbar.",
  testCombat = "Lagerfeuer: Im Kampf gibt es keine Testzettel.",
  sparkTitle = "Funke",
  sparkHow = "Klick: eine Nachfrage holen",
  sparkEmpty = "Lagerfeuer: Gerade fällt mir keine Nachfrage ein.",
  samples = {
    "Ein Feuer in Durotar – besser hätte der Tag nicht enden können.",
    "Woher kommst du gerade, Kuno?",
    "Was war euer bester Fund heute?",
  },
})
local T = FireNotes.TEXT

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end
local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end
local function safe(fn, ...)
  if ns.Core and ns.Core.safe then return ns.Core.safe(fn, ...) end
  return pcall(fn, ...)
end
local function say(msg)
  if ns.Core and type(ns.Core.print) == "function" then ns.Core.print(msg) end
end
local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end
local function now()
  return type(GetTime) == "function" and GetTime() or 0
end
local function after(sec, fn)
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(sec, function() safe(fn) end)
    return true
  end
  return false
end

local function Talk() return Journal.CampfireTalk end
local function Campfire() return ns.Campfire end
local function Theme() return Journal.Theme end

local function cfTable(create)
  local db = EveNChronicleDB
  if type(db) ~= "table" or isSecret(db) then return nil end
  local c = db.campfire
  if type(c) ~= "table" or isSecret(c) then
    if not create then return nil end
    c = {}
    db.campfire = c
  end
  return c
end

function FireNotes.settings()
  local c = cfTable(false) or {}
  local out = { notes = FireNotes.DEFAULTS.notes, show = FireNotes.DEFAULTS.show }
  if c.notes == true or c.notes == false then out.notes = c.notes end
  if type(c.show) == "string" and not isSecret(c.show) and FireNotes.SHOW_MODES[c.show] then out.show = c.show end
  return out
end

local function changed()
  local O = Journal.Options
  if O and type(O.refresh) == "function" then pcall(O.refresh) end
end

function FireNotes.setEnabled(on)
  local c = cfTable(true)
  if not c then return false end
  c.notes = on and true or false
  if not c.notes then FireNotes.stop("off") elseif FireNotes.state.session and not FireNotes.state.active then
    FireNotes.onCampfire("start", FireNotes.state.session)
  end
  changed()
  return true
end

function FireNotes.setShow(mode)
  if isSecret(mode) or type(mode) ~= "string" or not FireNotes.SHOW_MODES[mode] then return false end
  local c = cfTable(true)
  if not c then return false end
  c.show = mode
  changed()
  return true
end

function FireNotes.suppressesCard()
  local s = FireNotes.settings()
  return s.notes and s.show == "notesOnly"
end

-- Adapter: campfire session (E1) -> shape for CampfireTalk (E2). E1: person.past = { n, firstT, lastT, lastMapID, lastZone,
-- lastLevel }; E2 expects past = { count, mapID | zone, level }. talk remembers the templates used in this session.

function FireNotes.adapt(session, talk)
  talk = type(talk) == "table" and talk or {}
  local s = type(session) == "table" and not isSecret(session) and session or {}
  talk.mapID, talk.zone, talk.startT, talk.level = s.mapID, s.zone, s.startT, s.level
  local people = {}
  local list = type(s.people) == "table" and not isSecret(s.people) and s.people or {}
  for _, p in ipairs(list) do
    if type(p) == "table" and not isSecret(p) then
      local q = { guid = p.guid, name = p.name, class = p.class, race = p.race, sex = p.sex, level = p.level, sure = p.sure == true }
      local past = p.past
      if type(past) == "table" and not isSecret(past) then
        local n = num(past.count) or num(past.n)
        if n and n >= 1 then
          q.past = { count = n, mapID = past.mapID or past.lastMapID, zone = past.zone or past.lastZone,
            level = past.level or past.lastLevel }
        end
      end
      people[#people + 1] = q
    end
  end
  talk.people = people
  return talk
end

local st = { active = false, test = false, waiting = false, session = nil, talk = nil, notes = {}, buttons = {}, gen = 0,
  slotGen = {}, lastSend = -math.huge, frame = nil, phase = nil, autoN = 0, lastTalk = nil, speaker = nil, topic = nil,
  recentFollow = {}, lastSpark = -math.huge, spark = nil, silenceGen = nil }
FireNotes.state = st

local function reduceMotion()
  local View = Journal.View
  if not View or type(View.peek) ~= "function" then return false end
  local ok, v = pcall(View.peek, "reduceMotion")
  return ok and v == true
end

local function areaOf(shape, flip)
  local list = Journal.FIRE_NOTE_AREAS
  local a = type(list) == "table" and list[shape] or nil
  if type(a) ~= "table" then a = { x = 0.2, y = 0.2, w = 0.6, h = 0.6 } end
  local x = flip and (1 - a.x - a.w) or a.x
  return { x = x, y = a.y, w = a.w, h = a.h }
end
FireNotes.areaOf = areaOf

local function texPath(shape)
  local Th = Theme()
  local t = Th and Th.TEX and Th.TEX["fireNote" .. shape]
  return t or ("Interface\\AddOns\\EveN_ForeverChronicle\\Media\\FireNote" .. shape)
end

local function setFont(fs, size)
  local Th = Theme()
  if Th and Th.font then
    Th.font(fs, "title", size, Th.C and Th.C.ink)
  else
    pcall(fs.SetFont, fs, "Fonts\\MORPHEUS.TTF", size, "")
  end
end

local function fitText(b, text, area)
  local fs = b.text
  local W, H = FireNotes.NOTE_W, FireNotes.NOTE_H
  local aw, ah = area.w * W, area.h * H
  local shown = (ns.Sanitize and ns.Sanitize.display(text, 300)) or nil
  if not shown then return false end
  for size = FireNotes.FONT.max, FireNotes.FONT.min, -1 do
    setFont(fs, size)
    fs:SetWidth(aw)
    fs:SetText(shown)
    local h = num(fs:GetStringHeight()) or 0
    local truncated = fs.IsTruncated and fs:IsTruncated() or false
    -- a single word wider than the area never fits (the line would overflow): measure each word with the probe
    local wordOk = true
    local probe = b.probe
    if probe then
      setFont(probe, size)
      for word in string.gmatch(shown, "%S+") do
        probe:SetText(word)
        if (num(probe:GetStringWidth()) or 0) > aw then
          wordOk = false
          break
        end
      end
    end
    if h > 0 and h <= ah and not truncated and wordOk then
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", b, "TOPLEFT", area.x * W, -(area.y * H + (ah - h) / 2))
      fs.fontSize = size
      return true
    end
  end
  return false
end
FireNotes.fitText = fitText

local function hideTip(b)
  if GameTooltip and (type(GameTooltip.GetOwner) ~= "function" or GameTooltip:GetOwner() == b) then pcall(GameTooltip.Hide, GameTooltip) end
end

local function showTip(b)
  local note = b.note
  if not note or not GameTooltip then return end
  pcall(function()
    GameTooltip:SetOwner(b, "ANCHOR_TOP")
    GameTooltip:SetText(T.tipTitle, 1, 0.82, 0)
    GameTooltip:AddLine(T.tipHow, 1, 1, 1)
    local why = ns.Sanitize and ns.Sanitize.display(note.why, 200) or nil
    if why then GameTooltip:AddLine(string.format(T.tipWhy, why), 0.85, 0.75, 0.55, true) end
    if st.test then GameTooltip:AddLine(T.tipTest, 0.7, 0.7, 0.7) end
    GameTooltip:Show()
  end)
end

local function makeAnims(b, slot)
  if type(b.CreateAnimationGroup) ~= "function" then return end
  local fin = b:CreateAnimationGroup()
  if type(fin) ~= "table" or type(fin.CreateAnimation) ~= "function" then return end
  local a = fin:CreateAnimation("Alpha")
  a:SetFromAlpha(0)
  a:SetToAlpha(1)
  a:SetDuration(FireNotes.FADE)
  if fin.SetToFinalAlpha then fin:SetToFinalAlpha(true) end
  b.fadeIn = fin
  local fl = b:CreateAnimationGroup()
  local half = (FireNotes.FLOAT_TIME[slot] or 3.5) / 2
  local up = fl:CreateAnimation("Translation")
  up:SetOffset(0, FireNotes.FLOAT)
  up:SetDuration(half)
  up:SetOrder(1)
  if up.SetSmoothing then up:SetSmoothing("IN_OUT") end
  local down = fl:CreateAnimation("Translation")
  down:SetOffset(0, -FireNotes.FLOAT)
  down:SetDuration(half)
  down:SetOrder(2)
  if down.SetSmoothing then down:SetSmoothing("IN_OUT") end
  if fl.SetLooping then fl:SetLooping("REPEAT") end
  b.float = fl
end

local function newNote(parent, slot, interactive)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(FireNotes.NOTE_W, FireNotes.NOTE_H)
  b.slot = slot
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetAllPoints(b)
  b.text = b:CreateFontString(nil, "OVERLAY")
  if b.text.SetWordWrap then b.text:SetWordWrap(true) end
  if b.text.SetJustifyH then b.text:SetJustifyH("CENTER") end
  if b.text.SetJustifyV then b.text:SetJustifyV("TOP") end
  setFont(b.text, FireNotes.FONT.max)
  b.probe = b:CreateFontString(nil, "OVERLAY")
  b.probe:Hide()
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", (slot - 1) * (FireNotes.NOTE_W + FireNotes.GAP),
    -(FireNotes.FLOAT + (FireNotes.STAGGER[slot] or 0)))
  if interactive then
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    -- Left click sends here, in the same call (hardware event): no timer or queue in between.
    b:SetScript("OnClick", function(self, button) FireNotes.click(self.slot, button) end)
    b:SetScript("OnEnter", function(self) showTip(self) end)
    b:SetScript("OnLeave", function(self) hideTip(self) end)
    makeAnims(b, slot)
  else
    b:EnableMouse(false)
  end
  b:Hide()
  return b
end

local function dress(b, text, shape, flip)
  b.tex:SetTexture(texPath(shape))
  if flip then b.tex:SetTexCoord(1, 0, 0, 1) else b.tex:SetTexCoord(0, 1, 0, 1) end
  b.shape, b.flip = shape, flip and true or false
  b.area = areaOf(shape, flip)
  return fitText(b, text, b.area)
end
FireNotes.dress = dress

function FireNotes.place()
  local f = st.frame
  if not f then return end
  if FireNotes.hud and FireNotes.hud.place and FireNotes.hud.place(f) then return end
  local p = FireNotes.DEFAULT_POS
  f:SetParent(UIParent)
  f:ClearAllPoints()
  f:SetPoint(p.point, UIParent, p.point, p.x, p.y)
end

local function build()
  if st.frame then return st.frame end
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(FireNotes.W, FireNotes.H)
  f:SetFrameStrata("MEDIUM")
  f:EnableMouse(false)
  for slot = 1, FireNotes.COUNT do st.buttons[slot] = newNote(f, slot, true) end
  local sp = CreateFrame("Button", nil, f)
  sp:SetSize(FireNotes.SPARK_SIZE, FireNotes.SPARK_SIZE)
  sp:SetPoint("BOTTOM", f, "TOP", 0, 2)
  sp.tex = sp:CreateTexture(nil, "ARTWORK")
  sp.tex:SetAllPoints(sp)
  local Th = Theme()
  sp.tex:SetTexture(Th and Th.TEX and Th.TEX.glow or "Interface\\AddOns\\EveN_ForeverChronicle\\Media\\Glow")
  sp.tex:SetVertexColor(1, 0.55, 0.15, 1)
  if sp.RegisterForClicks then sp:RegisterForClicks("LeftButtonUp") end
  sp:SetScript("OnClick", function() FireNotes.spark() end)
  sp:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    pcall(function()
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(T.sparkTitle, 1, 0.82, 0)
      GameTooltip:AddLine(T.sparkHow, 1, 1, 1)
      GameTooltip:Show()
    end)
  end)
  sp:SetScript("OnLeave", function(self) hideTip(self) end)
  if type(sp.CreateAnimationGroup) == "function" then
    local g = sp:CreateAnimationGroup()
    if type(g) == "table" and type(g.CreateAnimation) == "function" then
      local a = g:CreateAnimation("Alpha")
      a:SetFromAlpha(1)
      a:SetToAlpha(0.45)
      a:SetDuration(1.2)
      if a.SetSmoothing then a:SetSmoothing("IN_OUT") end
      if g.SetLooping then g:SetLooping("BOUNCE") end
      sp.pulse = g
    end
  end
  sp:Hide()
  st.spark = sp
  st.frame = f
  FireNotes.place()
  f:Hide()
  return f
end
FireNotes.build = build

local function index()
  local I = Journal.Index
  if not I or type(I.get) ~= "function" then return nil end
  local ok, idx = pcall(I.get)
  return ok and type(idx) == "table" and idx or nil
end

local function rnd() return math.random() end

local function visibleNotes(extra)
  local out = {}
  for slot = 1, FireNotes.COUNT do
    if st.notes[slot] then out[#out + 1] = st.notes[slot] end
  end
  for _, n in ipairs(extra or {}) do out[#out + 1] = n end
  return out
end

local function hideSlot(slot)
  local b = st.buttons[slot]
  st.notes[slot] = nil
  if not b then return end
  if b.float then b.float:Stop() end
  if b.fadeIn then b.fadeIn:Stop() end
  hideTip(b)
  b.note = nil
  b:Hide()
end

local function fill(slot, follow)
  local CT = Talk()
  if not (st.active and CT and st.buttons[slot]) or st.notes[slot] then return false end
  if st.session and not st.test then st.talk = FireNotes.adapt(st.session, st.talk) end
  local state = st.test and { recent = {}, rejected = {} } or CT.state()
  local idx = index()
  local failed = {}
  for _ = 1, FireNotes.PICK_TRIES do
    local o = { visible = visibleNotes(failed) }
    if follow then
      o.follow, o.speaker, o.topic, o.avoid = true, st.speaker, st.topic, {}
      for _, id in ipairs(st.recentFollow) do o.avoid[id] = true end
    end
    local ok, note = pcall(CT.pick, st.talk, idx, state, o)
    if not ok or type(note) ~= "table" or type(note.text) ~= "string" then return false end
    local b = st.buttons[slot]
    local shape = math.random(1, FireNotes.SHAPES)
    if dress(b, note.text, shape, rnd() < 0.5) then
      if follow then
        note.auto = follow == "auto" or nil
        table.insert(st.recentFollow, note.id)
        while #st.recentFollow > FireNotes.FOLLOW_AVOID do table.remove(st.recentFollow, 1) end
      end
      st.notes[slot] = note
      b.note = note
      local motion = not reduceMotion()
      b:SetAlpha(motion and b.fadeIn and 0 or 1)
      b:Show()
      if motion and b.fadeIn then b.fadeIn:Play() end
      if motion and b.float then
        local g = st.gen
        local function go() if st.gen == g and st.notes[slot] == note and b.float then b.float:Play() end end
        local phase = FireNotes.FLOAT_PHASE[slot] or 0
        if phase <= 0 or not after(phase, go) then go() end
      end
      return true
    end
    failed[#failed + 1] = note
  end
  return false
end
FireNotes.fill = fill

local function fillAll()
  if not st.active or (st.phase == "talk" and not st.test) then return 0 end
  build()
  st.frame:Show()
  FireNotes.place()
  local n = 0
  for slot = 1, FireNotes.COUNT do
    if not st.notes[slot] and not st.slotGen[slot] and fill(slot) then n = n + 1 end
  end
  return n
end

local function refill(slot)
  local g = st.gen
  local token = {}
  st.slotGen[slot] = token
  local function run()
    if st.gen ~= g or st.slotGen[slot] ~= token then return end
    st.slotGen[slot] = nil
    if st.active and not st.waiting and not inCombat() then fill(slot) end
  end
  if not after(FireNotes.REFILL, run) then run() end
end

local function showSpark(on)
  local sp = st.spark
  if not sp then return end
  if on then
    sp:Show()
    if sp.pulse and not reduceMotion() then sp.pulse:Play() end
  else
    if sp.pulse then sp.pulse:Stop() end
    hideTip(sp)
    sp:Hide()
  end
end

function FireNotes.stop(why)
  st.gen = st.gen + 1
  st.active, st.waiting, st.test = false, false, false
  st.phase, st.silenceGen = nil, nil
  st.slotGen = {}
  for slot = 1, FireNotes.COUNT do hideSlot(slot) end
  showSpark(false)
  if st.frame then st.frame:Hide() end
  st.lastStop = why
  return true
end

function FireNotes.cardBusy()
  local To = Journal.Toast
  if not To then return false end
  local function isCard(item)
    local key = type(item) == "table" and item.key or nil
    return key == "welcome" or (type(key) == "string" and string.sub(key, 1, 5) == "rest:")
  end
  if type(To.getCurrent) == "function" and isCard(To.getCurrent()) then return true end
  for _, q in ipairs(type(To.queue) == "table" and To.queue or {}) do
    if isCard(q) then return true end
  end
  return false
end

local function waitForCard(g, since)
  if st.gen ~= g or not st.active then return end
  if FireNotes.cardBusy() and now() - since < FireNotes.CARD_WAIT_MAX then
    if after(FireNotes.CARD_POLL, function() waitForCard(g, since) end) then return end
  end
  st.waiting = false
  fillAll()
end

local function begin(session)
  FireNotes.stop("restart")
  if inCombat() then return false end
  st.session = session
  st.talk = FireNotes.adapt(session, nil)
  st.active = true
  st.phase, st.autoN, st.lastTalk, st.speaker, st.topic, st.recentFollow = "start", 0, nil, nil, nil, {}
  local mode = FireNotes.settings().show
  if mode == "cardFirst" then
    st.waiting = true
    local g, t0 = st.gen, now()
    if after(FireNotes.CARD_GRACE, function() waitForCard(g, t0) end) then return true end
    st.waiting = false
  end
  fillAll()
  return true
end

function FireNotes.onCampfire(what, session)
  if what == "end" then
    if not st.test then FireNotes.stop("end") end
    st.session = nil
    return
  end
  if what == "start" then
    st.session = session
    if not FireNotes.settings().notes then return end
    begin(session)
    return
  end
  if what == "update" and st.active and not st.test and not st.waiting and not inCombat() then
    st.session = session or st.session
    fillAll()
  end
  if what == "talk" then
    local t = type(session) == "table" and not isSecret(session) and session.talk or nil
    if type(t) == "table" then FireNotes.heard(t.who, t.guid) end
  end
end

local function hideAll(onlyAuto)
  for slot = 1, FireNotes.COUNT do
    local n = st.notes[slot]
    if n and (not onlyAuto or n.auto) then hideSlot(slot) end
    if not onlyAuto then st.slotGen[slot] = nil end
  end
end

local function showFollow(n, how)
  if not st.active or st.phase ~= "talk" or inCombat() then return 0 end
  if st.session then st.talk = FireNotes.adapt(st.session, st.talk) end
  local got = 0
  for slot = 1, FireNotes.COUNT do
    if got >= n then break end
    if not st.notes[slot] and fill(slot, how) then got = got + 1 end
  end
  return got
end

local function silenceCheck(g)
  if st.gen ~= g or st.silenceGen ~= g then return end
  if not st.active or st.phase ~= "talk" or not st.lastTalk then
    st.silenceGen = nil
    return
  end
  local left = FireNotes.SILENCE - (now() - st.lastTalk)
  if left > 0.05 and after(left, function() silenceCheck(g) end) then return end
  st.silenceGen = nil
  if st.autoN >= FireNotes.AUTO_MAX or inCombat() then return end
  for slot = 1, FireNotes.COUNT do
    if st.notes[slot] then return end
  end
  if showFollow(1, "auto") > 0 then st.autoN = st.autoN + 1 end
end

local function armSilence()
  if st.autoN >= FireNotes.AUTO_MAX then return end
  local g = st.gen
  if st.silenceGen == g then return end
  st.silenceGen = g
  if not after(FireNotes.SILENCE, function() silenceCheck(g) end) then st.silenceGen = nil end
end

local function enterTalk()
  st.phase, st.waiting = "talk", false
  hideAll(false)
  build()
  st.frame:Show()
  FireNotes.place()
  showSpark(true)
end

-- Someone spoke: who = "self" | "other" (guid). Never chat text, only who.
function FireNotes.heard(who, guid)
  if not st.active or st.test then return false end
  if who == "self" then
    st.speaker = nil
    if st.phase == "talk" then hideAll(false) else enterTalk() end
  elseif who == "other" then
    st.speaker = type(guid) == "string" and not isSecret(guid) and guid or nil
    if st.phase == "talk" then hideAll(true) end
  else
    return false
  end
  if st.phase ~= "talk" then return true end
  st.lastTalk = now()
  armSilence()
  return true
end

function FireNotes.spark()
  if not st.active or st.phase ~= "talk" then return false end
  if inCombat() then
    say(T.combat)
    return false
  end
  local t = now()
  if t - st.lastSpark < FireNotes.SPARK_THROTTLE then return false end
  st.lastSpark = t
  local C = Campfire()
  if C and type(C.touch) == "function" then pcall(C.touch) end
  hideAll(false)
  local n = showFollow(FireNotes.SPARK_N, "spark")
  if n == 0 then say(T.sparkEmpty) end
  return n > 0
end

local function sendSay(text)
  -- Retail simulation (E5): without "loud" only a local line instead of /say
  local C = ns.Campfire
  if C and type(C.simSay) == "function" then
    local ok, local_ = pcall(C.simSay, text)
    if ok and local_ then return true end
  end
  local CI = C_ChatInfo
  local fn = type(CI) == "table" and type(CI.SendChatMessage) == "function" and CI.SendChatMessage or nil
  if not fn and type(SendChatMessage) == "function" then fn = SendChatMessage end
  if not fn then return false end
  local ok = pcall(fn, text, "SAY")
  return ok
end
FireNotes.sendSay = sendSay

local function intoEditBox(text)
  local CFU = rawget(_G, "ChatFrameUtil")
  if type(CFU) == "table" and type(CFU.OpenChat) == "function" and pcall(CFU.OpenChat, text) then return true end
  local open = rawget(_G, "ChatFrame_OpenChat")
  if type(open) == "function" and pcall(open, text) then return true end
  return false
end

function FireNotes.click(slot, button)
  local note = st.notes[slot]
  local CT = Talk()
  if not note or not CT then return false end
  if button == "RightButton" then
    if not st.test then
      pcall(CT.rejected, note)
      local C = Campfire()
      if C and type(C.touch) == "function" then pcall(C.touch) end
    end
    hideSlot(slot)
    if st.phase ~= "talk" or st.test then refill(slot) end
    return true
  end
  if button ~= "LeftButton" then return false end
  if inCombat() then
    say(T.combat)
    return false
  end
  local t = now()
  if t - st.lastSend < FireNotes.THROTTLE then
    say(string.format(T.wait, FireNotes.THROTTLE))
    return false
  end
  local text = CT.clean(note.text)
  if not text then
    hideSlot(slot)
    refill(slot)
    return false
  end
  if not sendSay(text) then
    say(T.failed)
    if intoEditBox(text) then say(T.inEditBox) end
    return false
  end
  st.lastSend = t
  if not st.test then
    pcall(CT.sent, note)
    local kind = type(note.fact) == "string" and string.match(note.fact, "^(%a+):") or nil
    if kind and FireNotes.TOPICS[kind] then st.topic = kind end
    local C = Campfire()
    if C and type(C.noteSaid) == "function" then pcall(C.noteSaid) end
    FireNotes.heard("self")
    return true
  end
  hideSlot(slot)
  refill(slot)
  return true
end

function FireNotes.test()
  if st.test then
    FireNotes.stop("test")
    if st.session and FireNotes.settings().notes then begin(st.session) end
    say(T.testOff)
    return false
  end
  if inCombat() then
    say(T.testCombat)
    return false
  end
  FireNotes.stop("test")
  st.test, st.active = true, true
  st.talk = { startT = time and time() or nil, people = {} }
  local n = fillAll()
  if n == 0 then
    FireNotes.stop("test")
    say(T.testEmpty)
    return false
  end
  local g = st.gen
  after(FireNotes.TEST_TIME, function() if st.gen == g and st.test then FireNotes.stop("test") end end)
  say(T.testOn)
  return true
end

function FireNotes.buildPreview(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints(parent)
  p.notes = {}
  local shapes = { 1, 4, 3 }
  for slot = 1, FireNotes.COUNT do
    local b = newNote(p, slot, false)
    dress(b, T.samples[slot], shapes[slot], slot == 2)
    b:Show()
    p.notes[slot] = b
  end
  p:Hide()
  return p
end

if type(ns.onCampfire) == "function" then
  ns.onCampfire(function(what, session) safe(FireNotes.onCampfire, what, session) end)
end
if ns.Core and ns.Core.on then
  ns.Core.on("PLAYER_REGEN_DISABLED", function() if st.active then safe(FireNotes.stop, "combat") end end)
  ns.Core.on("PLAYER_STARTED_MOVING", function() if st.test then safe(FireNotes.stop, "move") end end)
end
