-- Live client values (money, level, XP, icons, spell names) read when the journal opens.
-- Every call runs in pcall; secret values and nil give nil. Live.source replaces the client API in tests.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Live = {}
Journal.Live = Live

local floor, huge = math.floor, math.huge

Live.source = nil

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function resolve(path)
  local src = Live.source
  if type(src) == "table" then
    local f = src[path]
    return type(f) == "function" and f or nil
  end
  local v = _G
  for part in string.gmatch(path, "[^%.]+") do
    if type(v) ~= "table" then return nil end
    v = v[part]
  end
  return type(v) == "function" and v or nil
end

local function call(path, ...)
  local f = resolve(path)
  if not f then return nil end
  local ok, a, b, c, d, e = pcall(f, ...)
  if not ok then return nil end
  return a, b, c, d, e
end

local function number(v, lo, hi)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == huge or v == -huge then return nil end
  if (lo and v < lo) or (hi and v > hi) then return nil end
  return v
end

local function validID(v)
  if isSecret(v) then return nil end
  if type(v) == "string" then
    if not string.find(v, "^%d+$") or #v > 10 then return nil end
    v = tonumber(v)
  end
  if type(v) ~= "number" or v ~= v or v <= 0 or v >= 2147483648 or v ~= floor(v) then return nil end
  return v
end
Live.validID = validID

function Live.money()
  return number((call("GetMoney")), 0)
end

function Live.level()
  local v = number((call("UnitLevel", "player")), 1, 200)
  return v and floor(v) or nil
end

function Live.xp()
  local cur = number((call("UnitXP", "player")), 0)
  local max = number((call("UnitXPMax", "player")), 1)
  if not cur or not max then return nil end
  return cur, max
end

function Live.rested()
  return number((call("GetXPExhaustion")), 0)
end

function Live.itemIcon(itemID)
  itemID = validID(itemID)
  if not itemID then return nil end
  local _, _, _, _, icon = call("C_Item.GetItemInfoInstant", itemID)
  if isSecret(icon) then return nil end
  if type(icon) == "number" and icon > 0 and icon == floor(icon) then return icon end
  return nil -- string paths are rejected: texture paths must be literals
end

function Live.spellName(spellID)
  spellID = validID(spellID)
  if not spellID then return nil end
  local name = call("C_Spell.GetSpellName", spellID)
  if isSecret(name) or type(name) ~= "string" or name == "" then return nil end
  return name
end
