-- Text library: hand-written German snippets with condition and weight, picked deterministically (seed from
-- info.firstSeen and the entry key, never repeated within a page). Snippets are code, never SV data.
-- Texts.add(group, entry), entry = { id, text = "template with {name} and {=number}", w, kind, when(ctx) };
-- Texts.pick(group, ctx, seed, key, used) -> text, id | nil. {name} = raw value (inserted via Sanitize.display),
-- {=name} = display-ready text or number (checked: a lone "|", a secret value or text over Texts.SAFE_MAX bytes ->
-- nil).
-- Texts.money(copper, mode, size): mode nil = all places, "short", "compact", "plain" (letters instead of icons);
-- Texts.itemString(key) builds "item:..." from a stored item key.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Texts = {}
Journal.Texts = Texts

local floor, huge, max, min = math.floor, math.huge, math.max, math.min
local byte, gsub, format, find = string.byte, string.gsub, string.format, string.find
local MAX_INT = 2 ^ 53 -- print with "%.0f", not "%d" (undefined or an error beyond 2^31 in the test VM / 2^63 in the client)

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

Texts.VAR_MAX = 60 -- bytes per inserted raw value
Texts.SAFE_MAX = 400 -- bytes per {=name} text (already display-ready; longer is a caller error)
Texts.GROUPS = { margin = true, diary = true, moment = true, curio = true, motto = true, seal = true }
local NBSP = "\194\160"

local lib = {}  -- group -> { entries }
local ids = {}  -- group -> { id -> true }
for g in pairs(Texts.GROUPS) do
  lib[g], ids[g] = {}, {}
end

function Texts.add(group, entry)
  if not Texts.GROUPS[group] or type(entry) ~= "table" then return false end
  if type(entry.id) ~= "string" or entry.id == "" or ids[group][entry.id] then return false end
  if type(entry.text) ~= "string" or entry.text == "" then return false end
  if entry.when ~= nil and type(entry.when) ~= "function" then return false end
  local w = tonumber(entry.w) or 1
  if w ~= w or w <= 0 or w == huge then return false end
  local kind = type(entry.kind) == "string" and entry.kind or nil
  -- locale: with entry.area the German text is registered under area/id and looked up only on pick
  local area = type(entry.area) == "string" and entry.area or nil
  if area and ns.Locale then ns.Locale.add("deDE", area, { [entry.id] = entry.text }) end
  local e = { id = entry.id, text = entry.text, w = w, when = entry.when, kind = kind, area = area }
  lib[group][#lib[group] + 1] = e
  ids[group][e.id] = true
  return true
end

function Texts.count(group)
  return lib[group] and #lib[group] or 0
end

function Texts.hash(s)
  s = type(s) == "string" and s or tostring(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + byte(s, i)) % 2147483647 end
  return h
end

function Texts.seed(firstSeen)
  local n = tonumber(firstSeen)
  if not n or n ~= n or n == huge or n == -huge then return "0" end
  if n > MAX_INT then n = MAX_INT elseif n < -MAX_INT then n = -MAX_INT end
  return format("%.0f", floor(n) + 0)
end

-- coin icon: Texts.coin(unit, size) -> "|T...|t" escape with the original client coins (as Blizzard's
-- GetCoinTextureString). The client icons are low resolution, so the coin is only COIN_SCALE (0.65) times the font size
-- and never larger than COIN_MAX px.
-- The escape consists of constants and rounded numbers only: foreign data never gets in. A higher-resolution atlas is
-- preferred at runtime: C_Texture.GetAtlasInfo must report an atlas of width >= COIN_ATLAS_MIN px for ALL three coins;
-- otherwise the MoneyFrame files, at most COIN_FILE_MAX px. The result is remembered once (Texts.resetCoinSource()
-- forgets it, tests only). Texts.coinReport() = lines for "/chronik muenzen".
Texts.COIN_SIZE = 14
Texts.COIN_SCALE = 0.65       -- coin in running text/table: 0.65 x font (14 px -> 9 px)
Texts.COIN_MAX = 18           -- hard cap: edge in text never larger (= COIN_FILE_MAX)
Texts.COIN_FILE_MAX = 18      -- file coin (MoneyFrame) at most this large
Texts.COIN_MIN = 8
Texts.COIN_GAP = 0.2
Texts.COIN_DY = 0
Texts.COIN_ATLAS_MIN = 24     -- atlas only from this width (px) in the source
Texts.COIN_BAG_ATLAS = 25     -- bag at the top with atlas: about the cap height of the 34 px number (24-26 px)
local COIN_FILE = {
  g = "Interface\\MoneyFrame\\UI-GoldIcon",
  s = "Interface\\MoneyFrame\\UI-SilverIcon",
  k = "Interface\\MoneyFrame\\UI-CopperIcon",
}
Texts.COIN_ATLAS = {
  g = { "coin-gold", "auctionhouse-icon-coin-gold" },
  s = { "coin-silver", "auctionhouse-icon-coin-silver" },
  k = { "coin-copper", "auctionhouse-icon-coin-copper" },
}
local UNITS = { "g", "s", "k" }
local UNIT_NAME = { g = "Gold", s = "Silber", k = "Kupfer" }

Texts.COIN_FILE = COIN_FILE -- texture paths (constants) for pages that set the coin as a real texture object

local coinSrc -- remembered result of resolveCoins

local function numOrNil(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == huge or v == -huge then return nil end
  return v
end

-- first candidate per unit that the client knows and that is wide enough. Returns { kind = "atlas"|"file", why, atlas =
-- { g, s, k }, width = { g, s, k } } (atlas)
-- or best = { g, s, k } (largest reported width, even if too small; nil = unknown)
local function resolveCoins()
  local api = type(C_Texture) == "table" and C_Texture.GetAtlasInfo or nil
  if type(api) ~= "function" then return { kind = "file", why = "keine C_Texture-API", whyKey = "coinWhyApi", best = {} } end
  local atlas, width, best, missing = {}, {}, {}, 0
  for _, unit in ipairs(UNITS) do
    for _, name in ipairs(Texts.COIN_ATLAS[unit]) do
      local ok, info = pcall(api, name)
      local w = ok and type(info) == "table" and numOrNil(info.width) or nil
      if w and (not best[unit] or w > best[unit]) then best[unit] = w end
      if w and w >= Texts.COIN_ATLAS_MIN and not atlas[unit] then atlas[unit], width[unit] = name, w end
    end
    if not atlas[unit] then missing = missing + 1 end
  end
  if missing > 0 then
    return { kind = "file", why = format("kein Atlas mit Breite >= %d px (%d von 3 Muenzen gefunden)", Texts.COIN_ATLAS_MIN, 3 - missing), whyKey = "coinWhyAtlas",
      whyArg = Texts.COIN_ATLAS_MIN, whyArg2 = 3 - missing, best = best }
  end
  return { kind = "atlas", why = "Atlas gefunden", atlas = atlas, width = width, best = best }
end

local function coinSource()
  if not coinSrc then coinSrc = resolveCoins() end
  return coinSrc
end

function Texts.resetCoinSource() coinSrc = nil end

-- Texts.coinSource(unit) -> kind ("atlas"|"file"), name (atlas name or file path), width (atlas width px | nil);
-- unknown unit -> nil
function Texts.coinSource(unit)
  if not COIN_FILE[unit] then return nil end
  local s = coinSource()
  if s.kind == "atlas" then return "atlas", s.atlas[unit], s.width[unit] end
  return "file", COIN_FILE[unit], nil
end

-- edge length (px) of the coin at the top of the bag (real texture object): with an atlas about the cap height of the
-- big number (but never above the atlas width, no upscaling),
-- with a file at most COIN_FILE_MAX
function Texts.bagCoinPx(unit)
  local kind, _, w = Texts.coinSource(unit)
  if kind == "atlas" then return min(Texts.COIN_BAG_ATLAS, w) end
  return Texts.COIN_FILE_MAX
end

-- edge length of the coin in px for a font size (COIN_SCALE x font, between COIN_MIN and COIN_MAX)
function Texts.coinPx(size)
  size = (not isSecret(size)) and tonumber(size) or Texts.COIN_SIZE
  if size ~= size or size < 6 then size = Texts.COIN_SIZE elseif size > 80 then size = 80 end
  return max(Texts.COIN_MIN, min(Texts.COIN_MAX, floor(size * Texts.COIN_SCALE + 0.5)))
end

function Texts.coin(unit, size)
  if not COIN_FILE[unit] then return "" end
  local px = Texts.coinPx(size)
  local gap = floor(px * Texts.COIN_GAP + 0.5)
  local dy = Texts.COIN_DY
  local kind, name = Texts.coinSource(unit)
  if kind == "atlas" then return format("|A:%s:%d:%d:%d:%d|a", name, px, px, gap, dy) end
  return format("|T%s:%d:%d:%d:%d|t", name, px, px, gap, dy)
end

-- texts of the coin diagnostics (scope "m.Texts", like the snippets below)
local CT = ns.Locale.ns("m.Texts", {
  coinAtlas = "Münzen: hoch aufgelöste Client-Grafik (Atlas) wird genutzt.",
  coinAtlasRow = "  %s: Atlas \"%s\", Quelle %d px, Beutel %d px.",
  coinFile = "Münzen: Datei Interface\\MoneyFrame (klein aufgelöst), höchstens %d px groß. Grund: %s.",
  coinFileRow = "  %s: Datei, größter gemeldeter Atlas %s.",
  coinPx = "%d px",
  coinNone = "keiner",
  coinTable = "Tabelle: %d px bei Schrift %d px; Beutel oben: %d px.",
  coinWhyApi = "keine C_Texture-API",
  coinWhyAtlas = "kein Atlas mit Breite >= %d px (%d von 3 Muenzen gefunden)",
  unitG = "Gold",
  unitS = "Silber",
  unitK = "Kupfer",
})
UNIT_NAME = { g = "unitG", s = "unitS", k = "unitK" }

-- Texts.coinReport() -> { line, ... } (active language): chosen coin source with resolution, for "/chronik muenzen"
function Texts.coinReport()
  local s = coinSource()
  local out = {}
  local why = s.why
  if s.whyKey then why = CT(s.whyKey, s.whyArg, s.whyArg2) end
  if s.kind == "atlas" then
    out[1] = CT.coinAtlas
    for _, unit in ipairs(UNITS) do
      out[#out + 1] = CT("coinAtlasRow", CT[UNIT_NAME[unit]], s.atlas[unit], s.width[unit], Texts.bagCoinPx(unit))
    end
  else
    out[1] = CT("coinFile", Texts.COIN_FILE_MAX, why)
    for _, unit in ipairs(UNITS) do
      local b = s.best[unit]
      out[#out + 1] = CT("coinFileRow", CT[UNIT_NAME[unit]], b and CT("coinPx", b) or CT.coinNone)
    end
  end
  out[#out + 1] = CT("coinTable", Texts.coinPx(Texts.COIN_SIZE), Texts.COIN_SIZE, Texts.bagCoinPx("g"))
  return out
end

local PLAIN = { g = " g", s = " s", k = " k" }

local function coins(copper)
  if isSecret(copper) then return nil end
  local c = tonumber(copper)
  if not c or c ~= c or c == huge or c == -huge then return nil end
  local neg = c < 0
  c = floor((neg and -c or c) + 0.5)
  if c > MAX_INT then c = MAX_INT end
  return floor(c / 10000), floor(c % 10000 / 100), c % 100, neg and c > 0
end

function Texts.money(copper, mode, size)
  local g, s, k, neg = coins(copper)
  if not g then return "?" end
  local plain = mode == "plain"
  local parts = {}
  local function put(n, unit, pad)
    parts[#parts + 1] = (pad and format("%02d", n) or Texts.int(n)) .. (plain and PLAIN[unit] or Texts.coin(unit, size))
  end
  if mode == "compact" then
    if g > 0 then put(g, "g") end
    if s > 0 then put(s, "s") end
    if k > 0 or #parts == 0 then put(k, "k") end
  elseif g > 0 then
    put(g, "g")
    if mode ~= "short" or s > 0 then put(s, "s", true) end
    if mode ~= "short" then put(k, "k", true) end
  elseif s > 0 then
    put(s, "s")
    if mode ~= "short" or k > 0 then put(k, "k", mode ~= "short") end
  else
    put(k, "k")
  end
  return (neg and "-" or "") .. table.concat(parts, " ")
end

-- Texts.moneyParts(copper) -> { { n = "12", unit = "g" }, { n = "21", unit = "s" }, { n = "07", unit = "k" } }, neg
-- Same places and digits as Texts.money(copper) (mode nil) but without escapes: for big displays that set each coin as
-- a real texture object of fixed pixel size
-- (a |T escape would grow with a large font in the client). Non-number -> nil.
function Texts.moneyParts(copper)
  local g, s, k, neg = coins(copper)
  if not g then return nil end
  local parts = {}
  local function put(n, unit, pad)
    parts[#parts + 1] = { n = pad and format("%02d", n) or Texts.int(n), unit = unit }
  end
  if g > 0 then
    put(g, "g"); put(s, "s", true); put(k, "k", true)
  elseif s > 0 then
    put(s, "s"); put(k, "k", true)
  else
    put(k, "k")
  end
  return parts, neg
end

function Texts.moneyCols(copper, size)
  local g, s, k = coins(copper)
  if not g then return "", "", "?" end
  local cg = g > 0 and (Texts.int(g) .. Texts.coin("g", size)) or ""
  local cs = (g > 0 or s > 0) and (format(g > 0 and "%02d" or "%d", s) .. Texts.coin("s", size)) or ""
  local ck = format((g > 0 or s > 0) and "%02d" or "%d", k) .. Texts.coin("k", size)
  return cg, cs, ck
end

local ID_MAX = 2147483647
local function posInt(v)
  v = tonumber(v)
  if not v or v ~= v or v < 1 or v > ID_MAX or v ~= floor(v) then return nil end
  return format("%d", v)
end

function Texts.itemString(key)
  if isSecret(key) then return nil end
  if type(key) == "number" then
    local id = posInt(key)
    return id and ("item:" .. id) or nil
  end
  if type(key) ~= "string" or #key > 200 then return nil end
  local idText, rest = string.match(key, "^(%d+)(.*)$")
  local id = posInt(idText)
  if not id then return nil end
  local suffix, bonus = "", {}
  for part in string.gmatch(rest, "[^.]+") do
    local kind, n = string.match(part, "^([sb])(%-?%d+)$")
    if not kind then return nil end
    if kind == "s" then
      local v = tonumber(n)
      if not v or v == 0 or v <= -ID_MAX or v >= ID_MAX then return nil end
      suffix = format("%d", v)
    else
      local b = posInt(n)
      if not b then return nil end
      if #bonus < 16 then bonus[#bonus + 1] = b end
    end
  end
  if rest ~= "" and string.sub(rest, 1, 1) ~= "." then return nil end
  if suffix == "" and #bonus == 0 then return "item:" .. id end
  -- itemID : enchant : gem1..gem4 : suffix : unique : linkLevel : spec : modMask : context : numBonus : bonus...
  local out = "item:" .. id .. ":::::" .. ":" .. suffix .. ":::::"
  if #bonus > 0 then
    out = out .. ":" .. #bonus .. ":" .. table.concat(bonus, ":")
  end
  return out
end

function Texts.int(n)
  if isSecret(n) then return "?" end
  n = tonumber(n)
  if not n or n ~= n or n == huge or n == -huge then return "?" end
  local neg = n < 0
  local mag = neg and -n or n
  if mag > MAX_INT then mag = MAX_INT end
  local s = format("%.0f", floor(mag + 0.5) + 0)
  local out = s
  while true do
    local a, k = gsub(out, "^(%d+)(%d%d%d)", "%1" .. NBSP .. "%2")
    out = a
    if k == 0 then break end
  end
  return neg and ("-" .. out) or out
end

function Texts.fill(tpl, vars)
  if type(tpl) ~= "string" then return nil end
  vars = type(vars) == "table" and vars or {}
  local missing = false
  local display = ns.Sanitize and ns.Sanitize.display
  local out = gsub(tpl, "{(=?)([%a_][%w_]*)}", function(safe, name)
    local v = vars[name]
    if safe == "=" then
      if isSecret(v) then
        missing = true
        return ""
      end
      if type(v) == "number" then return Texts.int(v) end
      -- defence in depth: a {=} text counts as display-ready but is checked. A lone "|" (not doubled as "||") would be
      -- read as an escape by the client;
      -- too long texts are a caller error.
      if type(v) == "string" and v ~= "" and #v <= Texts.SAFE_MAX and not find((gsub(v, "||", "")), "|", 1, true) then
        return v
      end
      missing = true
      return ""
    end
    local s = display and display(v, Texts.VAR_MAX)
    if not s then
      missing = true
      return ""
    end
    return s
  end)
  if missing then return nil end
  return out
end

local function fits(e, ctx)
  if not e.when then return true end
  local ok, v = pcall(e.when, ctx)
  return ok and v == true
end

function Texts.pick(group, ctx, seed, key, used)
  local list = lib[group]
  if not list then return nil end
  ctx = type(ctx) == "table" and ctx or {}
  used = type(used) == "table" and used or {}
  local cand, total = {}, 0
  for _, e in ipairs(list) do
    if not used[e.id] and (e.kind == nil or e.kind == ctx.kind) and fits(e, ctx) then
      cand[#cand + 1] = e
      total = total + e.w
    end
  end
  local h = Texts.hash(tostring(seed or "0") .. "|" .. group .. "|" .. tostring(key or ""))
  while #cand > 0 do
    local r = (h % 1000003) / 1000003 * total
    local idx = #cand
    for i, e in ipairs(cand) do
      r = r - e.w
      if r < 0 then
        idx = i
        break
      end
    end
    local e = cand[idx]
    local tpl = e.area and ns.Locale and ns.Locale.get(e.area, e.id) or e.text
    if type(tpl) ~= "string" then tpl = e.text end
    local text = Texts.fill(tpl, ctx)
    if text then
      used[e.id] = true
      return text, e.id
    end
    total = total - e.w
    table.remove(cand, idx)
    h = Texts.hash(h .. "+")
  end
  return nil
end

-- scaffold snippets: scope "m.Texts" (English in locales/enUS_model.lua)
local AREA = "m.Texts"

-- motto per race (ctx.raceFile = info.raceFile); general mottos as fallback
Texts.add("motto", { area = AREA, id = "motto_any_1", text = "Jeder Weg beginnt mit einem Schritt." })
Texts.add("motto", { area = AREA, id = "motto_any_2", text = "Wer reist, erzählt." })
Texts.add("motto", { area = AREA, id = "motto_scourge_1", w = 3, text = "Die Toten reisen weit.",
  when = function(c) return c.raceFile == "Scourge" end })
Texts.add("motto", { area = AREA, id = "motto_scourge_2", w = 3, text = "Kein Grab hält mich auf.",
  when = function(c) return c.raceFile == "Scourge" end })

Texts.add("margin", { area = AREA, id = "margin_fast_level", text = "Stufe {=level} ging im Flug: {=duration}.",
  when = function(c) return c.kind == "fastest" end })
Texts.add("margin", { area = AREA, id = "margin_slow_level", text = "Auf Stufe {=level} blieb ich hängen: {=duration}.",
  when = function(c) return c.kind == "slowest" end })

Texts.add("diary", { area = AREA, id = "diary_level", text = "Stufe {=level} erreicht.", when = function(c) return c.kind == "level" end })
Texts.add("diary", { area = AREA, id = "diary_quest", text = "Quest „{title}“ erledigt.", when = function(c) return c.kind == "quest" end })

Texts.add("moment", { area = AREA, id = "moment_level", text = "Stufe {=level}, endlich.", when = function(c) return c.kind == "level" end })
Texts.add("moment", { area = AREA, id = "moment_death", text = "Hier fiel ich zum ersten Mal.",
  when = function(c) return c.kind == "first_death" end })

Texts.add("curio", { area = AREA, id = "curio_bow", text = "{=count} × verbeugt", when = function(c) return c.token == "BOW" end })

Texts.add("seal", { area = AREA, id = "seal_epic", text = "Etwas Violettes wartet noch.",
  when = function(c) return c.seal == "epic" end })
