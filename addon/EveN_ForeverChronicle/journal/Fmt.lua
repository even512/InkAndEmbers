-- Central text helpers: durations, umlaut-aware upper-casing, item quality names/colors, big numbers, km.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Fmt = {}
Journal.Fmt = Fmt

local floor, format, huge = math.floor, string.format, math.huge
local NBSP = "\194\160"
local L = ns.Locale

local T = L.ns("Fmt", {
  sec = "%d Sek.",
  underMin = "unter 1 Min.",
  min = "%d Min.",
  hr = "%d Std.",
  hrMin = "%d Std. %d Min.",
  day_one = "%d Tg.",
  day_other = "%d Tg.",
  dayHr_one = "%d Tg. %d Std.",
  dayHr_other = "%d Tg. %d Std.",
  clock = "%d:%02d Min.",
  q0 = "Schlecht",
  q1 = "Gewöhnlich",
  q2 = "Ungewöhnlich",
  q3 = "Selten",
  q4 = "Episch",
  q5 = "Legendär",
  q6 = "Artefakt",
  q7 = "Erbstück",
  thousands = NBSP,
  decimal = ",",
  million = "%s Mio.",
})
Fmt.T = T

-- Escaped for gsub replacement: a "%" in the separator would be a capture reference.
local function repl(s) return (s:gsub("%%", "%%%%")) end

local function finite(v)
  if type(issecretvalue) == "function" and issecretvalue(v) then return false end
  return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

function Fmt.duration(sec, opts)
  sec = tonumber(sec)
  if not finite(sec) or sec < 0 then return nil end
  if sec < 60 then
    if type(opts) == "table" and opts.seconds then return T("sec", floor(sec + 0.5)) end
    return T.underMin
  end
  local m = floor(sec / 60)
  if m < 60 then return T("min", m) end
  local h = floor(m / 60)
  m = m % 60
  if h < 24 then
    if m == 0 then return T("hr", h) end
    return T("hrMin", h, m)
  end
  local d = floor(h / 24)
  h = h % 24
  if h == 0 then return T(L.plural(d, "day_one", "day_other"), d) end
  return T(L.plural(d, "dayHr_one", "dayHr_other"), d, h)
end

function Fmt.clock(sec)
  sec = tonumber(sec)
  if not finite(sec) or sec < 0 then return nil end
  sec = floor(sec + 0.5)
  return T("clock", floor(sec / 60), sec % 60)
end

function Fmt.upper(s)
  if type(s) ~= "string" then return s end
  return (s:gsub("ä", "Ä"):gsub("ö", "Ö"):gsub("ü", "Ü"):upper())
end

Fmt.QUALITY = {
  [0] = { name = "Schlecht", hex = "524D46", dark = "9D9D9D" },
  [1] = { name = "Gewöhnlich", hex = "2B2118", dark = "FFFFFF" },
  [2] = { name = "Ungewöhnlich", hex = "175820", dark = "1EFF00" },
  [3] = { name = "Selten", hex = "1A4E86", dark = "0070DD" },
  [4] = { name = "Episch", hex = "642A84", dark = "A335EE" },
  [5] = { name = "Legendär", hex = "7A3C00", dark = "FF8000" },
  [6] = { name = "Artefakt", hex = "5C4E16", dark = "E6CC80" },
  [7] = { name = "Erbstück", hex = "1C5058", dark = "00CCFF" },
}

local function qKey(q)
  q = tonumber(q)
  if not finite(q) then return nil end
  q = floor(q)
  return Fmt.QUALITY[q] and q or nil
end

function Fmt.qualityName(q)
  q = qKey(q)
  if not q then return nil end
  if L.matchesClient() then
    local g = rawget(_G, "ITEM_QUALITY" .. q .. "_DESC")
    if type(g) == "string" and g ~= "" and not (type(issecretvalue) == "function" and issecretvalue(g)) then return g end
  end
  return T["q" .. q]
end

function Fmt.qualityHex(q, onDark)
  q = qKey(q)
  if not q then return nil end
  if onDark then
    local c = rawget(_G, "ITEM_QUALITY_COLORS")
    c = type(c) == "table" and c[q] or nil
    if type(c) == "table" and finite(c.r) and finite(c.g) and finite(c.b) then
      return format("%02X%02X%02X", floor(c.r * 255 + 0.5), floor(c.g * 255 + 0.5), floor(c.b * 255 + 0.5))
    end
    return Fmt.QUALITY[q].dark
  end
  return Fmt.QUALITY[q].hex
end

function Fmt.qualityRGB(q, onDark)
  local h = Fmt.qualityHex(q, onDark)
  if not h then return nil end
  return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end

function Fmt.colorize(text, q, onDark)
  if type(text) ~= "string" then return text end
  local h = Fmt.qualityHex(q, onDark)
  if not h then return text end
  return "|cff" .. h .. text .. "|r"
end

function Fmt.qualityText(q, onDark)
  local n = Fmt.qualityName(q)
  return n and Fmt.colorize(n, q, onDark) or nil
end

function Fmt.int(n)
  n = tonumber(n)
  if not finite(n) then return "?" end
  local neg = n < 0
  local s = format("%.0f", floor((neg and -n or n) + 0.5) + 0)
  while true do
    local a, k = s:gsub("^(%d+)(%d%d%d)", "%1" .. repl(T.thousands) .. "%2")
    s = a
    if k == 0 then break end
  end
  return neg and ("-" .. s) or s
end

function Fmt.big(n)
  n = tonumber(n)
  if not finite(n) then return "?" end
  local mag = n < 0 and -n or n
  if mag >= 999500 then
    local v = mag / 1000000
    local s = v >= 100 and format("%.0f", v) or (v >= 10 and format("%.1f", v) or format("%.2f", v))
    if s:find("%.") then s = s:gsub("0+$", ""):gsub("%.$", "") end
    s = s:gsub("%.", repl(T.decimal))
    return T("million", (n < 0 and "-" or "") .. s)
  end
  return Fmt.int(n)
end

function Fmt.km(km)
  km = tonumber(km)
  if not finite(km) then return "?" end
  if km >= 99.95 then return Fmt.int(km) end
  return (format("%.1f", floor(km * 10 + 0.5) / 10):gsub("%.", repl(T.decimal)))
end
