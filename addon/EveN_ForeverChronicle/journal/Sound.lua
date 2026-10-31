-- Book sounds: Sound.TABLE (name -> file and/or SoundKit id) decides what plays when, plus the short open animation
-- (alpha 0 -> 1, at most Sound.OPEN_TIME seconds). Files are under Media/Sounds (CC0, see LICENSES.txt) and play via
-- PlaySoundFile on the SFX channel; if the client rejects one, the SoundKit id plays via PlaySound, else silence.
-- Stored choice per event in EveNChronicleDB.ui.sounds[event]: "default", "off", "kit:<id>", "file:<name>.ogg", "lsm:<name>".
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Sound = {}
Journal.Sound = Sound

Sound.DIR = "Interface\\AddOns\\EveN_ForeverChronicle\\Media\\Sounds\\"
Sound.CHANNEL = "SFX"
Sound.OPEN_TIME = 0.2

Sound.TABLE = {
  open = { file = "book_open.ogg", id = 829 },
  page = { files = { "page_1.ogg", "page_2.ogg" }, id = 836 },
  close = { file = "book_close_2.ogg", id = 830 },
  feather = { files = { "quill_3b.ogg", "quill_4b.ogg" }, id = 878 },
  todoDone = { id = 43502 },
}

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function Pages() return Journal.Pages end

function Sound.enabled()
  local P = Pages()
  if not P or type(P.setting) ~= "function" then return true end
  return P.setting("bookSounds") ~= false
end

function Sound.setEnabled(on)
  local P = Pages()
  return P and P.setSetting("bookSounds", on and true or false) or false
end

local function validId(id)
  return type(id) == "number" and not isSecret(id) and id > 0 and id == math.floor(id)
end

-- file name from the table: harmless names only (letters, digits, _ . -), never a path from foreign data
local function validFile(name)
  return type(name) == "string" and string.match(name, "^[%w_%.%-]+%.ogg$") ~= nil
end

function Sound.resolve(name)
  local e = Sound.TABLE[name]
  if type(e) ~= "table" then return nil end
  local file
  if validFile(e.file) then
    file = e.file
  elseif type(e.files) == "table" and #e.files > 0 then
    local pick = e.files[math.random(1, #e.files)]
    if validFile(pick) then file = pick end
  end
  if file then return { kind = "file", path = Sound.DIR .. file, id = validId(e.id) and e.id or nil } end
  if validId(e.id) then return { kind = "id", id = e.id } end
  return nil
end

local function playId(id)
  if type(PlaySound) ~= "function" then return false end
  local ok, willPlay = pcall(PlaySound, id, Sound.CHANNEL)
  return ok and willPlay ~= false
end

local function playFile(path)
  if type(PlaySoundFile) ~= "function" then return false end
  local ok, willPlay = pcall(PlaySoundFile, path, Sound.CHANNEL)
  return ok and willPlay ~= false
end

local function playDefault(name)
  local r = Sound.resolve(name)
  if not r then return nil end
  if r.kind == "file" and playFile(r.path) then return "file" end
  if r.id and playId(r.id) then return "id" end
  return nil
end

function Sound.play(name)
  if not Sound.enabled() then return nil end
  local chosen = Sound.playChoice(name)
  if chosen == "off" then return nil end
  if chosen then return chosen end
  return playDefault(name)
end

Sound.EVENTS = {
  { key = "open", label = "Buch öffnen" },
  { key = "page", label = "Seite umblättern" },
  { key = "close", label = "Buch schließen" },
  { key = "feather", label = "Begrüßung und Rückblick" },
  { key = "todoDone", label = "To Do erledigt" },
  { key = "zone", label = "Neues Gebiet" },
  { key = "medal", label = "Medaille verdient" },
}
local EVENT = {}
for _, e in ipairs(Sound.EVENTS) do EVENT[e.key] = e end

Sound.FILES = {
  { file = "book_open.ogg", name = "Buch aufschlagen" },
  { file = "book_close_2.ogg", name = "Buch zuklappen" },
  { file = "page_1.ogg", name = "Seite blättern 1" },
  { file = "page_2.ogg", name = "Seite blättern 2" },
  { file = "quill_3b.ogg", name = "Bleistift" },
  { file = "quill_4b.ogg", name = "Feder auf Papier" },
}
local FILE = {}
for _, f in ipairs(Sound.FILES) do FILE[f.file] = f end

do
  local de = {
    default = "Standard",
    off = "Aus",
    missing = "%s (fehlt, Standard)",
    game = "Spielklänge",
    own = "Eigene Klänge",
    lsm = "SharedMedia",
    lsmEmpty = "Keine Klänge von anderen Addons",
  }
  for _, e in ipairs(Sound.EVENTS) do de["ev_" .. e.key] = e.label end
  for _, f in ipairs(Sound.FILES) do de["f_" .. (f.file:gsub("%.ogg$", ""))] = f.name end
  Sound.TEXT = ns.Locale.ns("Sound", de)
end

function Sound.eventLabel(e)
  if type(e) ~= "table" then return "?" end
  return Sound.TEXT["ev_" .. tostring(e.key)]
end

function Sound.fileName(f)
  if type(f) ~= "table" then return "?" end
  return Sound.TEXT["f_" .. (tostring(f.file):gsub("%.ogg$", ""))]
end
Sound.LSM_NAME_MAX = 100

local function kits() return Journal.SoundKits end

local function lsmName(key)
  if type(key) ~= "string" or isSecret(key) then return nil end
  local name = string.match(key, "^lsm:(.+)$")
  if not name or #name > Sound.LSM_NAME_MAX or string.find(name, "%c") then return nil end
  return name
end

function Sound.validKey(key)
  if isSecret(key) or type(key) ~= "string" then return false end
  if key == "default" or key == "off" then return true end
  local id = string.match(key, "^kit:(%d+)$")
  if id then
    local K = kits()
    return K ~= nil and K.byId(tonumber(id)) ~= nil
  end
  local file = string.match(key, "^file:(.+)$")
  if file then return validFile(file) and FILE[file] ~= nil end
  return lsmName(key) ~= nil
end

local function soundTable(create)
  local db = EveNChronicleDB
  if type(db) ~= "table" then return nil end
  local ui = db.ui
  if type(ui) ~= "table" or isSecret(ui) then
    if not create then return nil end
    ui = {}
    db.ui = ui
  end
  local t = ui.sounds
  if type(t) ~= "table" or isSecret(t) then
    if not create then return nil end
    t = {}
    ui.sounds = t
  end
  return t
end

function Sound.choice(event)
  if not EVENT[event] then return "default" end
  local t = soundTable(false)
  local v = t and t[event]
  if Sound.validKey(v) then return v end
  return "default"
end

function Sound.setChoice(event, key)
  if not EVENT[event] or not Sound.validKey(key) then return false end
  local t = soundTable(true)
  if not t then return false end
  if key == "default" then t[event] = nil else t[event] = key end
  return true
end

local lsmCache, lsmHooked = nil, false
local mediaListeners = {}

function Sound.lsm()
  local LS = rawget(_G, "LibStub")
  if LS == nil then return nil end
  local ok, lib = pcall(LS, "LibSharedMedia-3.0", true)
  if not ok or type(lib) ~= "table" then return nil end
  if not lsmHooked and type(lib.RegisterCallback) == "function" then
    lsmHooked = true
    pcall(lib.RegisterCallback, Sound, "LibSharedMedia_Registered", function(_, mediatype)
      if mediatype ~= "sound" then return end
      lsmCache = nil
      for _, fn in ipairs(mediaListeners) do pcall(fn) end
    end)
  end
  return lib
end

function Sound.onMedia(fn)
  if type(fn) == "function" then mediaListeners[#mediaListeners + 1] = fn end
end

function Sound.lsmNames()
  if lsmCache then return lsmCache end
  local out = {}
  local lib = Sound.lsm()
  if lib and type(lib.List) == "function" then
    local ok, list = pcall(lib.List, lib, "sound")
    if ok and type(list) == "table" then
      for _, name in ipairs(list) do
        if type(name) == "string" and not isSecret(name) and name ~= "None" and lsmName("lsm:" .. name) then
          out[#out + 1] = name
        end
      end
    end
  end
  table.sort(out)
  lsmCache = out
  return out
end

local function lsmFetch(name)
  if not name then return nil end
  local lib = Sound.lsm()
  if not lib or type(lib.Fetch) ~= "function" then return nil end
  local ok, data = pcall(lib.Fetch, lib, "sound", name, true)
  if not ok or isSecret(data) then return nil end
  if type(data) == "string" and data ~= "" and data ~= "None" then return data end
  if type(data) == "number" and data > 1 and data == math.floor(data) then return data end
  return nil
end

function Sound.resolveKey(key)
  if not Sound.validKey(key) or key == "default" then return nil end
  if key == "off" then return { kind = "off" } end
  local id = string.match(key, "^kit:(%d+)$")
  if id then
    local K = kits()
    local real = K.idOf(K.byId(tonumber(id)))
    return validId(real) and { kind = "kit", id = real } or nil
  end
  local file = string.match(key, "^file:(.+)$")
  if file then return { kind = "file", path = Sound.DIR .. file } end
  local data = lsmFetch(lsmName(key))
  if data then return { kind = "lsm", data = data } end
  return nil
end

function Sound.playKey(key)
  local r = Sound.resolveKey(key)
  if not r then return nil end
  if r.kind == "off" then return "off" end
  if r.kind == "kit" then return playId(r.id) and "kit" or nil end
  if r.kind == "file" then return playFile(r.path) and "file" or nil end
  if r.kind == "lsm" then return playFile(r.data) and "lsm" or nil end
  return nil
end

-- nil means take the default (nothing chosen, sound missing, or the client refuses)
function Sound.playChoice(event)
  local key = Sound.choice(event)
  if key == "default" then return nil end
  return Sound.playKey(key)
end

function Sound.preview(event, key)
  if not EVENT[event] then return nil end
  if key == nil then key = Sound.choice(event) end
  if key == "off" then return nil end
  if key ~= "default" then
    local r = Sound.playKey(key)
    if r then return r end
  end
  if Sound.TABLE[event] then return playDefault(event) end
  local T = Journal.Toast
  if T and type(T.playDefault) == "function" then
    return T.playDefault(event) and "id" or nil
  end
  return nil
end

function Sound.label(key)
  if key == nil or key == "default" then return Sound.TEXT.default end
  if key == "off" then return Sound.TEXT.off end
  if not Sound.validKey(key) then return Sound.TEXT.default end
  local id = string.match(key, "^kit:(%d+)$")
  if id then return kits().nameOf(kits().byId(tonumber(id))) end
  local file = string.match(key, "^file:(.+)$")
  if file then return Sound.fileName(FILE[file]) end
  local name = lsmName(key)
  local S = ns.Sanitize
  local shown = (S and S.display(name, 60)) or "?"
  if not lsmFetch(name) then return string.format(Sound.TEXT.missing, shown) end
  return shown
end

local anims = setmetatable({}, { __mode = "k" })

local function reduceMotion()
  local View = Journal.View
  return View and type(View.peek) == "function" and View.peek("reduceMotion") == true
end

local function build(f)
  if type(f.CreateAnimationGroup) ~= "function" then return false end
  local ok, group = pcall(f.CreateAnimationGroup, f)
  if not ok or type(group) ~= "table" then return false end
  local a = group:CreateAnimation("Alpha")
  if type(a) ~= "table" then return false end
  group:SetToFinalAlpha(true)
  a:SetFromAlpha(0)
  a:SetToAlpha(1)
  a:SetDuration(Sound.OPEN_TIME)
  a:SetOrder(1)
  return { group = group, alpha = a }
end

function Sound.animateOpen(f)
  if type(f) ~= "table" or reduceMotion() then return false end
  local a = anims[f]
  if a == nil then
    local ok, made = pcall(build, f)
    a = (ok and made) or false
    anims[f] = a
  end
  if not a then return false end
  a.group:Stop()
  a.group:Play()
  return true
end

function Sound.stopAnimation(f)
  local a = type(f) == "table" and anims[f]
  if a then
    a.group:Stop()
    if type(f.SetAlpha) == "function" then f:SetAlpha(1) end
  end
end
