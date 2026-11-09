-- Character names and realm display (1.0.9). WoW Forever has regionally unique names: UnitName("player") returns first name and
-- surname ("Lenu", "Barrowstone"), GetRealmName() a hidden server shard ("CAMWOW EU4 Realm 10 RP") that is never shown. Instead the
-- book shows "Vorname Nachname" and the ruleset (C_GameRules, like Questie's AceDB key). Retail keeps name and realm as before.
-- Stored (Store.login, additive): info.surname (second value of UnitName("player")) and info.ruleset ("hardcore"|"rp"|"pvp"|"pve").
-- Companions stay keyed "Vorname-Nachname" (collectors/Companions.lua); the display shows the part after "-" as surname only on
-- Forever and only if it is no shard (no digits, whitespace, hyphens or control characters), otherwise only the first name.
-- All functions return raw text (not display-ready): callers pass it through Sanitize.display as before.
local _, ns = ...

local Names = {}
ns.Names = Names

local type, pcall, find, match, sub, rawget = type, pcall, string.find, string.match, string.sub, rawget

Names.SURNAME_MAX = 40        -- bytes
Names.FOREVER_PROJECT = 18    -- WOW_PROJECT_ID of WoW Forever
Names.RULESETS = { hardcore = true, rp = true, pvp = true, pve = true }

-- Texts (German here, English in locales/enUS_core.lua, section 'Names')
local T = ns.Locale.ns("Names", {
  hardcore = "Hardcore",
  rp = "Rollenspiel (PvE)",
  pvp = "PvP",
  pve = "PvE",
})
Names.TEXT = T

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function str(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

-- surname (or the part after "-" of a companion key) that may be shown: string, not secret, 1..40 bytes, no digits, whitespace,
-- hyphens, control characters or '|' (a shard like "CAMWOW EU4 Realm 10 RP" never passes)
function Names.surnameOk(s)
  s = str(s)
  if not s or #s > Names.SURNAME_MAX then return false end
  return not find(s, "[%s%d%c%-|]")
end

local function apiTrue(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if not ok or isSecret(v) then return nil end
  return v == true
end

local function project()
  local p = rawget(_G, "WOW_PROJECT_ID")
  if isSecret(p) or type(p) ~= "number" then return nil end
  return p
end

-- the running client has regionally unique names (WoW Forever)
function Names.foreverClient()
  if apiTrue(rawget(_G, "RegionalUniqueNamesEnabled")) then return true end
  return project() == Names.FOREVER_PROJECT
end

-- surname of the logged-in character (second value of UnitName("player")) | nil
function Names.readSurname()
  if type(UnitName) ~= "function" then return nil end
  local ok, _, surname = pcall(UnitName, "player")
  if not ok or not Names.surnameOk(surname) then return nil end
  return surname
end

-- ruleset of the logged-in character | nil. Order Hardcore > RP > PvP > PvE, as Questie. Only on a client with regionally unique
-- names and C_GameRules.IsGameRuleActive (Retail stays nil); an unreadable rule (error, secret) gives nil rather than a guess.
function Names.readRuleset()
  if not Names.foreverClient() then return nil end
  local G = rawget(_G, "C_GameRules")
  local E = rawget(_G, "Enum")
  if type(G) ~= "table" or isSecret(G) or type(G.IsGameRuleActive) ~= "function" then return nil end
  local rules = type(E) == "table" and not isSecret(E) and type(E.GameRule) == "table" and E.GameRule or nil
  if not rules then return nil end
  local function active(key)
    local id = rules[key]
    if id == nil or isSecret(id) then return false end
    local ok, v = pcall(G.IsGameRuleActive, id)
    if not ok or isSecret(v) then return nil end
    return v == true
  end
  local hc = active("HardcoreRuleset")
  if hc == nil then return nil end
  if hc or apiTrue(G.IsHardcoreActive) then return "hardcore" end
  local rp = active("RPRuleset")
  if rp == nil then return nil end
  if rp then return "rp" end
  local pvp = active("PvPRuleset")
  if pvp == nil then return nil end
  return pvp and "pvp" or "pve"
end

-- "Vorname Nachname" of a character info table (raw), only the first name if no usable surname; nil without a name
function Names.fullName(info)
  if type(info) ~= "table" then return nil end
  local name = str(info.name)
  if not name then return nil end
  local surname = info.surname
  if Names.surnameOk(surname) then return name .. " " .. surname end
  return name
end

-- does this character info belong to WoW Forever? ruleset stored -> yes; known client id -> that; else the running client
function Names.isForever(info)
  if type(info) ~= "table" then return Names.foreverClient() end
  if Names.RULESETS[info.ruleset] then return true end
  local p = info.project
  if type(p) == "number" and not isSecret(p) then
    if p == Names.FOREVER_PROJECT then return true end
    local cur = project()
    if cur ~= nil and p ~= cur then return false end
  end
  return Names.foreverClient()
end

-- text for the realm slot: Forever -> the ruleset ("Rollenspiel (PvE)") or nil, never the shard; Retail -> the realm (raw)
function Names.realmText(info)
  if type(info) ~= "table" then return nil end
  if Names.isForever(info) then
    local r = info.ruleset
    return Names.RULESETS[r] and T[r] or nil
  end
  return str(info.realm)
end

-- display name of a companion/guest (raw). raw = "Vorname-Nachname" (key as stored) or the first name with realm/surname given
-- separately. Forever: "Vorname Nachname" if the second part is a surname (no shard), else "Vorname". Retail: the first name, or
-- with keepRealm the unchanged "Name-Realm" (places that showed the realm before keep it).
function Names.mateName(raw, realm, keepRealm)
  raw = str(raw)
  if not raw then return nil end
  local first, rest = raw, str(realm)
  if not rest then
    local n, r = match(raw, "^([^%-]+)%-(.+)$")
    if n then first, rest = n, r end
  end
  if Names.foreverClient() then
    if Names.surnameOk(rest) then return first .. " " .. rest end
    return first
  end
  if keepRealm then return rest and (first .. "-" .. rest) or first end
  return first
end

-- is "who" (a name from a chat message) the logged-in character? Accepts "Vorname", "Vorname Nachname", "Vorname-Nachname" and
-- "Vorname-<shard/realm>". With a known surname another surname is someone else (Forever names are only unique with the surname);
-- without one (Retail) any "Name-Realm" counts, as before. Never a name that only starts with ours.
function Names.isMe(who)
  who = str(who)
  if not who or type(UnitName) ~= "function" then return false end
  local ok, me, surname = pcall(UnitName, "player")
  me = ok and str(me) or nil
  if not me then return false end
  if not Names.surnameOk(surname) then surname = nil end
  if who == me then return true end
  if #who < #me + 2 or sub(who, 1, #me) ~= me then return false end
  local sep, rest = sub(who, #me + 1, #me + 1), sub(who, #me + 2)
  if sep == " " then return surname ~= nil and rest == surname end
  if sep ~= "-" then return false end
  if surname then return rest == surname or not Names.surnameOk(rest) end
  return true
end
