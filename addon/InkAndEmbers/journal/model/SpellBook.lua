-- SpellBook (core, 1.1.0): what the client knows about one spell, shared by the modules Plans (journal/model/Lehrplan.lua) and
-- Crafting (journal/model/Rezepte.lua). Split off the Lehrplan so the recipe plan works without the module Plans.
--   SpellBook.clientKnows(id) -> bool   learned according to the client spellbook (C_SpellBook / IsPlayerSpell / IsSpellKnown)
--   SpellBook.spellInfo(id) -> { name, rank, icon, missing }   name in the client language (cached); missing data is requested
--                                once, the name is then a fallback ("Zauber 123") with missing = true
--   SpellBook.resetNames()              forget the cached names
-- Every client call runs in pcall with secret-value guards; names go through Sanitize.field.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local SpellBook = {}
Journal.SpellBook = SpellBook

-- locale scope "m.SpellBook" (English in locales/enUS_model.lua)
local T = ns.Locale.ns("m.SpellBook", {
  spellFallback = "Zauber %s",
})
SpellBook.TEXT = T

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function str(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

local function tbl(v)
  if type(v) == "table" and not isSecret(v) then return v end
  return nil
end

local function isTrue(v)
  return not isSecret(v) and v == true
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d
end

local function bankPlayer()
  local E = rawget(_G, "Enum")
  local B = type(E) == "table" and not isSecret(E) and tbl(E.SpellBookSpellBank) or nil
  return B and B.Player or nil
end

-- one spell, client only (no rank rules: those are the Lehrplan's)
function SpellBook.clientKnows(id)
  id = num(id)
  if not id then return false end
  local SB = tbl(C_SpellBook)
  if SB then
    local bank = bankPlayer()
    if isTrue((call(SB.IsSpellKnown, id, bank))) then return true end
    if isTrue((call(SB.IsSpellInSpellBook, id, bank, false))) then return true end
  end
  if isTrue((call(rawget(_G, "IsPlayerSpell"), id))) then return true end
  if isTrue((call(rawget(_G, "IsSpellKnown"), id))) then return true end
  return false
end

-- Spell names (client, in its language); missing data is requested once and filled on the next draw
local infoCache = {}

function SpellBook.spellInfo(id)
  id = num(id)
  if not id then return nil end
  local hit = infoCache[id]
  if hit then return hit end
  local CS = tbl(C_Spell)
  local name, rank, icon
  if CS then
    name = str((call(CS.GetSpellName, id)))
    rank = str((call(CS.GetSpellSubtext, id)))
    icon = (call(CS.GetSpellTexture, id))
  end
  if not name then
    local n, _, ic = call(rawget(_G, "GetSpellInfo"), id)
    name, icon = str(n), icon or ic
  end
  if isSecret(icon) or (type(icon) ~= "number" and type(icon) ~= "string") then icon = nil end
  if not name then
    if CS then call(CS.RequestLoadSpellData, id) end
    return { name = T("spellFallback", id), missing = true, icon = icon }
  end
  local info = { name = ns.Sanitize.field(name), rank = rank and ns.Sanitize.field(rank) or nil, icon = icon }
  infoCache[id] = info
  return info
end

function SpellBook.resetNames()
  infoCache = {}
end
