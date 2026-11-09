-- Reunion in the tooltip: whoever you look at (mouse over a character, unit frame, target frame) and have been out with before gets
-- up to two short memory lines in the tooltip ("Cleared Halle der Thanen together, 03.11.", "Sat with you at the fire in Goldhain,
-- 03.11."). The data comes from the lookup table of journal/model/Reunion.lua (built once per index, never while hovering).
-- Unprotected paths only: TooltipDataProcessor.AddTooltipPostCall (fallback GameTooltip OnTooltipSetUnit); own post call, enemy and
-- NPC tooltips are not touched (see TodoMarks). No OnUpdate.
-- Midnight secret values: name, realm, GUID and every unit check can be secret (combat, instances, PvP). Each value is checked with
-- issecretvalue before use; a secret value is never compared, used as table key or printed, the line is simply left out. Forbidden
-- tooltips are not touched. Only own saved text (zone/dungeon, via Sanitize.display) is shown, never the name from the tooltip.
-- The person key is formed exactly like collectors/Companions.lua readUnit (name-realm, own realm if missing, Sanitize.field + cut).
local _, ns = ...

local Journal = ns.Journal
if not Journal then return end
local Theme = Journal.Theme

local match = string.match

local Reunion = {}
Journal.Reunion = Reunion

Reunion.TIP_ICON = 14
Reunion.INDENT = "      "     -- second line: indented under the icon, without it
Reunion.NAME_MAX = 64         -- like NAME_MAX in collectors/Companions.lua
Reunion.COLOR = { 0.98, 0.82, 0.45 } -- like TodoMarks.COLOR

Reunion.TEXT = ns.Locale.ns("Reunion", {
  stateOn = "an",
  stateOff = "aus",
  built_done = "fertig",
  built_running = "läuft (%d von %d Läufen)",
  built_none = "noch nicht gebaut",
  diagMain = "Wiedersehen im Tooltip: %s, %d Personen, Aufbau %s; Spieler-Tooltips %d, Treffer %d, Name gesperrt %d, GUID gesperrt %d, Fehler %d",
  diagFail = "; letzte Auslassung: %s",
  diagSecret = "; Identität des letzten Spielers gesperrt: %s",
  yes = "ja",
  no = "nein",
  reason_forbidden = "verbotener Tooltip",
  reason_self = "die eigene Figur",
  reason_group = "Gruppenmitglied",
  reason_secret = "Name/GUID oder Einheitenprüfung gesperrt",
  reason_noTable = "Tabelle noch nicht gebaut",
  reason_noMatch = "kein Treffer",
})

local T = Reunion.TEXT
local st = { hooked = false }
Reunion.state = st
st.diag = { seen = 0, hits = 0, secretName = 0, secretGuid = 0, errors = 0, reason = nil, should = nil }
local D = st.diag

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function str(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if not ok then return nil end
  return a, b
end

local function forbidden(f)
  if type(f) ~= "table" then return true end
  if type(f.IsForbidden) == "function" then
    local ok, v = pcall(f.IsForbidden, f)
    if not ok or isSecret(v) or v then return true end
  end
  return false
end

local function iconFile()
  return (Theme and Theme.TEX and (Theme.TEX.minimapIcon or Theme.TEX.minimap))
    or "Interface\\AddOns\\InkAndEmbers\\Media\\MinimapIcon"
end

local function Model() return Journal.ReunionModel end

-- setting ----------------------------------------------------------------------------------------------------------------

-- account wide: EveNChronicleDB.reunion = { enabled = true }; without a value it is on
function Reunion.enabled()
  local db = EveNChronicleDB
  if type(db) ~= "table" or isSecret(db) then return true end
  local r = db.reunion
  if type(r) ~= "table" or isSecret(r) then return true end
  return r.enabled ~= false
end

function Reunion.setEnabled(on)
  local db = EveNChronicleDB
  if type(db) ~= "table" or isSecret(db) then return Reunion.enabled() end
  if type(db.reunion) ~= "table" then db.reunion = {} end
  db.reunion.enabled = on and true or false
  local O = Journal.Options
  if O and type(O.refresh) == "function" then pcall(O.refresh) end
  return Reunion.enabled()
end

-- identity of a unit --------------------------------------------------------------------------------------------------------

-- own realm as name part: same as collectors/Companions.lua ownRealm
local function ownRealm()
  local r = str(call(GetNormalizedRealmName))
  if not r then
    r = str(call(GetRealmName))
    if r then r = string.gsub(r, "[%s%-]", "") end
  end
  return r
end

-- -> full (name-realm as the collector writes it) | nil, guid (a player GUID) | nil, secret (true if a value was secret)
-- Secret or empty values give nil; they are never compared or used as a key.
function Reunion.identify(unit)
  if not str(unit) then return nil, nil, isSecret(unit) end
  local secret = false
  local name, realm
  if type(UnitFullName) == "function" then
    name, realm = call(UnitFullName, unit)
  else
    name, realm = call(UnitName, unit)
  end
  local full
  if isSecret(name) or isSecret(realm) then
    secret = true
    D.secretName = D.secretName + 1
  else
    name = str(name)
    local unknown = _G.UNKNOWNOBJECT
    if name and not (type(unknown) == "string" and not isSecret(unknown) and name == unknown) then
      realm = str(realm) or ownRealm()
      full = realm and (name .. "-" .. realm) or name
      full = ns.Sanitize.cut(ns.Sanitize.field(full), Reunion.NAME_MAX)
      if full == "" then full = nil end
    end
  end
  local guid = call(UnitGUID, unit)
  if isSecret(guid) then
    secret = true
    D.secretGuid = D.secretGuid + 1
    guid = nil
  else
    guid = str(guid)
    if guid and not match(guid, "^Player%-") then guid = nil end
  end
  return full, guid, secret
end

-- true only if it is certain: a secret or missing answer counts as "do not know"
local function certainly(fn, ...)
  local v = call(fn, ...)
  if isSecret(v) then return nil end
  if v == nil or v == false then return false end
  return true
end

-- group member? -> true | false | nil (not certain)
local function inGroup(unit)
  local party = certainly(UnitInParty, unit)
  local raid = certainly(UnitInRaid, unit)
  if party == true or raid == true then return true end
  if party == nil or raid == nil then return nil end
  return false
end

local function fail(reason)
  D.reason = T["reason_" .. reason]
end

-- tooltip -----------------------------------------------------------------------------------------------------------------

function Reunion.tipLines(lines)
  local out = {}
  local icon = string.format("|T%s:%d:%d|t ", iconFile(), Reunion.TIP_ICON, Reunion.TIP_ICON)
  for i = 1, math.min(#lines, 2) do
    out[#out + 1] = (i == 1 and icon or Reunion.INDENT) .. lines[i]
  end
  return out
end

-- the lines for a unit token (nil: nothing to show). Checks everything; leaves the reason in the diagnosis.
function Reunion.forUnit(unit)
  if not str(unit) then return nil end
  local isPlayer = call(UnitIsPlayer, unit)
  if isSecret(isPlayer) then return nil end
  if isPlayer ~= true then return nil end -- enemies, NPCs, pets: not our business (no counter either)
  D.seen = D.seen + 1
  local me = certainly(UnitIsUnit, unit, "player")
  if me == nil then fail("secret") return nil end
  if me then fail("self") return nil end
  local grouped = inGroup(unit)
  if grouped == nil then fail("secret") return nil end
  if grouped then fail("group") return nil end
  local CS = C_Secrets
  if type(CS) == "table" and type(CS.ShouldUnitIdentityBeSecret) == "function" then
    local v = call(CS.ShouldUnitIdentityBeSecret, unit)
    if not isSecret(v) and type(v) == "boolean" then D.should = v end
  end
  local M = Model()
  if not (M and M.ready()) then fail("noTable") return nil end
  local full, guid = Reunion.identify(unit)
  if not full and not guid then fail("secret") return nil end
  local lines = M.lookup(full, guid)
  if not lines then fail("noMatch") return nil end
  D.hits = D.hits + 1
  return lines
end

function Reunion.onTooltip(tooltip)
  if not Reunion.enabled() or forbidden(tooltip) or type(tooltip.AddLine) ~= "function" then return end
  local unit
  if type(tooltip.GetUnit) == "function" then
    local ok, _, u = pcall(tooltip.GetUnit, tooltip)
    if ok then unit = str(u) end
  end
  if not unit then return end
  local lines = Reunion.forUnit(unit)
  if not lines then return end
  local c = Reunion.COLOR
  for _, line in ipairs(Reunion.tipLines(lines)) do
    pcall(tooltip.AddLine, tooltip, line, c[1], c[2], c[3], true)
  end
  if type(tooltip.Show) == "function" then pcall(tooltip.Show, tooltip) end
end

local function safeTooltip(tooltip)
  local ok = pcall(Reunion.onTooltip, tooltip)
  if not ok then D.errors = D.errors + 1 end
end

local function hookTooltip()
  if st.hooked then return true end
  local TDP = TooltipDataProcessor
  local kind = type(Enum) == "table" and type(Enum.TooltipDataType) == "table" and Enum.TooltipDataType.Unit or nil
  if type(TDP) == "table" and type(TDP.AddTooltipPostCall) == "function" and kind ~= nil then
    local ok = pcall(TDP.AddTooltipPostCall, kind, function(tooltip) safeTooltip(tooltip) end)
    if ok then
      st.hooked = "processor"
      return true
    end
  end
  local GT = GameTooltip
  if type(GT) == "table" and type(GT.HookScript) == "function" then
    local ok = pcall(GT.HookScript, GT, "OnTooltipSetUnit", function(tooltip) safeTooltip(tooltip) end)
    if ok then
      st.hooked = "script"
      return true
    end
  end
  return false
end
Reunion.hookTooltip = hookTooltip

-- diagnosis ---------------------------------------------------------------------------------------------------------------

function Reunion.diagLine()
  local M = Model()
  local built
  if M and M.building() then
    built = T("built_running", M.state.runsDone, M.state.runsTotal)
  elseif M and M.ready() then
    built = T.built_done
  else
    built = T.built_none
  end
  local line = T("diagMain", Reunion.enabled() and T.stateOn or T.stateOff, M and M.count() or 0, built,
    D.seen, D.hits, D.secretName, D.secretGuid, D.errors + (M and M.state.errors or 0))
  if D.reason then line = line .. T("diagFail", D.reason) end
  if D.should ~= nil then line = line .. T("diagSecret", D.should and T.yes or T.no) end
  return line .. "."
end

-- index connection --------------------------------------------------------------------------------------------------------

-- after every finished build of the own index (never the guest slot) the lookup table is rebuilt in time slices
function Reunion.onIndexReady(index)
  local M = Model()
  if not M then return false end
  local ok, started = pcall(M.start, index)
  if not ok then D.errors = D.errors + 1 end
  return ok and started or false
end

local Index = Journal.Index
if Index and type(Index.onReady) == "function" then Index.onReady(Reunion.onIndexReady) end

if ns.Core and ns.Core.on then
  ns.Core.on("PLAYER_ENTERING_WORLD", function() hookTooltip() end)
end
