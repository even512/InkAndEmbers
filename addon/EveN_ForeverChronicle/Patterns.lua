-- GlobalString -> Lua pattern (incl. positional args like %1$s), money text parser.
-- Chat message patterns are derived from the client's GlobalStrings, never hardcoded.
local _, ns = ...

local Patterns = {}
ns.Patterns = Patterns

local find, sub, match, gsub = string.find, string.sub, string.match, string.gsub

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

Patterns.missing = {}
local cache = {}

local function escape(s)
  return (gsub(s, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end
Patterns.escape = escape

local function toNumber(s)
  return tonumber((gsub(s, ",", ".")))
end

-- converts a format string to a Lua pattern
-- returns pattern, argOrder (capture i belongs to argument argOrder[i]), kinds ('s'/'n' per capture), argCount
function Patterns.build(fmt, anchored)
  local parts, order, kinds = {}, {}, {}
  local pos, seq, len, argCount = 1, 0, #fmt, 0
  while pos <= len do
    local s = find(fmt, "[%%|]", pos)
    if not s then
      parts[#parts + 1] = escape(sub(fmt, pos))
      break
    end
    if s > pos then parts[#parts + 1] = escape(sub(fmt, pos, s - 1)) end
    if sub(fmt, s, s) == "|" then
      -- grammar codes |4singular:plural; and |1a;b; -> the client picks one variant (no argument)
      local after = match(fmt, "^|4[^;]*;()", s) or match(fmt, "^|1[^;]*;[^;]*;()", s)
      if after then
        parts[#parts + 1] = ".-"
        pos = after
      else
        parts[#parts + 1] = "|" -- other |-codes (color, link) appear literally in the message
        pos = s + 1
      end
    elseif sub(fmt, s + 1, s + 1) == "%" then
      parts[#parts + 1] = "%%"
      pos = s + 2
    else
      local p, argi = s + 1, nil
      local n, after = match(fmt, "^(%d+)%$()", p)
      if n then
        argi, p = tonumber(n), after
      end
      local conv, nextPos = match(fmt, "^[%-%+ #0]*%d*%.?%d*([sdiufg])()", p)
      if not conv then
        parts[#parts + 1] = "%%" -- lone percent sign without a conversion: treat as text
        pos = s + 1
      else
        if not argi then
          seq = seq + 1
          argi = seq
        end
        if conv == "s" then
          parts[#parts + 1] = (nextPos > len) and "(.+)" or "(.-)"
          kinds[#kinds + 1] = "s"
        elseif conv == "f" or conv == "g" then
          parts[#parts + 1] = "(%-?%d+[%.,]?%d*)"
          kinds[#kinds + 1] = "n"
        else
          parts[#parts + 1] = "(%-?%d+)"
          kinds[#kinds + 1] = "n"
        end
        order[#order + 1] = argi
        if argi > argCount then argCount = argi end
        pos = nextPos
      end
    end
  end
  local pattern = table.concat(parts)
  if anchored ~= false then pattern = "^" .. pattern .. "$" end
  return pattern, order, kinds, argCount
end

local function noteMissing(globalName)
  if not Patterns.missing[globalName] then
    Patterns.missing[globalName] = true
    if ns.Core and ns.Core.syncDiag then ns.Core.syncDiag() end
  end
end

-- matcher for a GlobalString: returns the captures in argument order (%d as number),
-- or nil on mismatch or if the GlobalString is missing (adds a diag entry)
function Patterns.compile(globalName)
  local hit = cache[globalName]
  if hit then return hit end
  local fmt = _G[globalName]
  if type(fmt) ~= "string" or fmt == "" then
    noteMissing(globalName)
    return nil
  end
  local pattern, order, kinds, argCount = Patterns.build(fmt)
  local matcher = function(text)
    if isSecret(text) or type(text) ~= "string" then return nil end
    local caps = { match(text, pattern) }
    if caps[1] == nil then return nil end
    local out = {}
    for i = 1, #order do
      local v = caps[i]
      if kinds[i] == "n" then v = toNumber(v) end
      out[order[i]] = v
    end
    return unpack(out, 1, argCount)
  end
  cache[globalName] = matcher
  return matcher
end

function Patterns.match(globalName, text)
  local m = Patterns.compile(globalName)
  if not m then return nil end
  return m(text)
end

-- money text -> copper; handles localized units (GOLD_AMOUNT) and texture variants (GOLD_AMOUNT_TEXTURE);
-- thousands separators allowed; nil if nothing matches
local DENOMS = {
  { "GOLD_AMOUNT", 10000 },
  { "SILVER_AMOUNT", 100 },
  { "COPPER_AMOUNT", 1 },
}

local function moneyPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local pre, post = match(fmt, "^(.-)%%d(.*)$")
  if not pre then return nil end
  post = match(post, "^(.-)%%") or post -- texture variant: cut after the symbol name
  return escape(pre) .. "(%d[%d%.]*)" .. escape(post)
end

local function scanMoney(text, suffix)
  local total, found = 0, false
  for i = 1, #DENOMS do
    local name, factor = DENOMS[i][1], DENOMS[i][2]
    local fmt = _G[name .. suffix]
    if type(fmt) ~= "string" then
      noteMissing(name .. suffix)
    else
      local pat = moneyPattern(fmt)
      local amount = pat and match(text, pat)
      if amount then
        total = total + (tonumber((gsub(amount, "%.", ""))) or 0) * factor
        found = true
      end
    end
  end
  return found and total or nil
end

function Patterns.parseMoney(text)
  if isSecret(text) or type(text) ~= "string" then return nil end
  local copper = scanMoney(text, "_TEXTURE")
  if copper then return copper end
  local plain = ns.Sanitize and ns.Sanitize.strip(text) or text
  return scanMoney(plain, "")
end

-- item link -> data. Only the item key is stored, never the link:
--   <itemID>[.s<suffix>][.b<bonusID>...]  (suffix = suffixID ~= 0, at most 8 bonus IDs)
-- returns itemID, bonus ('s-37.b1486' or nil), quality (0-7 from the link color, nil if unknown), name;
-- nil if text has no item link. Format: item:itemID:enchant:gem1:gem2:gem3:gem4:suffixID:uniqueID:
-- linkLevel:specID:modifiersMask:itemContext:numBonusIDs:bonusID1:...
local QUALITY_BY_COLOR = {
  ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6, ["00ccff"] = 7,
}

local function whole(n)
  return string.format("%d", n)
end

function Patterns.itemLink(text)
  if isSecret(text) or type(text) ~= "string" then return nil end
  local s, e, data = find(text, "|Hitem:([%-%d:]*)|h")
  if not s then return nil end
  local fields = {}
  for part in string.gmatch(data .. ":", "([^:]*):") do fields[#fields + 1] = part end
  local id = tonumber(fields[1])
  if not id or id <= 0 or id ~= id or id > 2147483647 then return nil end
  local parts = {}
  local suffix = tonumber(fields[7])
  if suffix and suffix ~= 0 and suffix > -2147483648 and suffix < 2147483648 then parts[#parts + 1] = "s" .. whole(suffix) end
  local nb = tonumber(fields[13])
  if nb and nb > 0 then
    for i = 1, math.min(nb, 8) do
      local b = tonumber(fields[13 + i])
      if b and b > 0 and b < 2147483648 then parts[#parts + 1] = "b" .. whole(b) end
    end
  end
  local before = sub(text, 1, s - 1)
  local quality = match(before, "|cnIQ(%d+):$")
  if quality then
    quality = tonumber(quality)
  else
    local hex = match(before, "|c%x%x(%x%x%x%x%x%x)$")
    quality = hex and QUALITY_BY_COLOR[string.lower(hex)] or nil
  end
  local name = match(text, "|h%[(.-)%]|h", e - 1)
  return id, (#parts > 0) and table.concat(parts, ".") or nil, quality, name
end

function Patterns.itemKey(itemID, bonus)
  if type(itemID) ~= "number" or itemID ~= itemID then return nil end
  local key = whole(itemID)
  if bonus then return key .. "." .. bonus end
  return key
end
