-- Sanitizing of foreign text (color codes, links, textures, control characters).
-- Quest/book text, names and chat messages are stored as data only, never treated as code.
local _, ns = ...

local Sanitize = {}
ns.Sanitize = Sanitize

local gsub, sub, byte, find = string.gsub, string.sub, string.byte, string.find

Sanitize.FIELD_MAX = 250   -- bytes per log field
Sanitize.LONG_MAX = 20000  -- bytes per long text (quest/book page)

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

function Sanitize.cut(s, max)
  if #s <= max then return s end
  local i = max
  while i > 0 do
    local b = byte(s, i + 1)
    if not b or b < 128 or b >= 192 then break end
    i = i - 1
  end
  return sub(s, 1, i)
end

-- strips WoW escape codes; hyperlinks keep their display text; nil for non-strings and secret values
function Sanitize.strip(s)
  if isSecret(s) or type(s) ~= "string" then return nil end
  s = gsub(s, "|H.-|h(.-)|h", "%1")          -- hyperlink |H<data>|h<text>|h -> <text>
  s = gsub(s, "|c%x%x%x%x%x%x%x%x", "")       -- color |cAARRGGBB
  s = gsub(s, "|cn[^:|]*:", "")               -- named color |cnIQ0: / |cnGREEN_FONT_COLOR:
  s = gsub(s, "|r", "")
  s = gsub(s, "|T.-|t", "")                   -- texture
  s = gsub(s, "|A.-|a", "")                   -- atlas
  s = gsub(s, "|K.-|k", "")                   -- protected text (KString)
  return s
end

local function dropControl(keepNewline)
  return function(c)
    if keepNewline and c == "\n" then return c end
    return ""
  end
end

-- log field: no codes, '~' -> '-', line breaks -> space, '|' -> '/', no control characters
function Sanitize.field(s)
  if type(s) == "string" and not isSecret(s) then s = Sanitize.cut(s, Sanitize.FIELD_MAX * 4) end
  s = Sanitize.strip(s)
  if not s then return "" end
  s = gsub(s, "|n", " ")
  s = gsub(s, "[\r\n\t]", " ")
  s = gsub(s, "~", "-")
  s = gsub(s, "|", "/")
  s = gsub(s, "%c", dropControl(false))
  s = gsub(s, "  +", " ")
  s = gsub(s, "^ +", "")
  s = gsub(s, " +$", "")
  return Sanitize.cut(s, Sanitize.FIELD_MAX)
end

-- long text (quest/book): no codes or control characters, paragraphs kept; nil if empty
function Sanitize.longText(s)
  if type(s) == "string" and not isSecret(s) then s = Sanitize.cut(s, Sanitize.LONG_MAX * 4) end
  s = Sanitize.strip(s)
  if not s then return nil end
  s = gsub(s, "|n", "\n")
  s = gsub(s, "\r\n?", "\n")
  s = gsub(s, "\t", " ")
  s = gsub(s, "|", "/")
  s = gsub(s, "%c", dropControl(true))
  s = gsub(s, " +\n", "\n")
  s = gsub(s, "\n\n\n+", "\n\n")
  s = gsub(s, "^[ \n]+", "")
  s = gsub(s, "[ \n]+$", "")
  if s == "" then return nil end
  return Sanitize.cut(s, Sanitize.LONG_MAX)
end

-- Display text (journal): SV texts for FontStrings and tooltips. Codes and control/bidi characters removed, single line,
-- length capped (UTF-8 safe, with an ellipsis), then every '|' doubled so the client reads no escape sequence. Display only, never execute.

Sanitize.DISPLAY_MAX = 120 -- bytes of text per display field (before '|' is doubled)
local ELLIPSIS = "\226\128\166"

-- Invisible Unicode in UTF-8: C1 controls, soft hyphen, ALM, Mongolian vowel separator, zero-width and bidi marks/overrides,
-- word joiner and invisible operators, BOM, tag characters, CGJ, Hangul fillers, Khmer vowel signs, variation selectors, interlinear anchors, U+2800
local INVISIBLE = { "\194[\128-\159]", "\194\173", "\205\143", "\216\156", "\225\133[\159-\160]",
  "\225\158[\180-\181]", "\225\160\142", "\226\128[\139-\143]", "\226\128[\168-\174]", "\226\129[\160-\175]",
  "\227\133\164", "\239\184[\128-\143]", "\239\187\191", "\239\190\160", "\239\191[\185-\187]",
  "\243\160[\128-\129][\128-\191]", "\243\160[\132-\134][\128-\191]", "\243\160\135[\128-\175]", "\226\160\128" }
local SPECIAL = "[%c|\194\205\216\225\226\227\239\243]" -- bytes a sanitizing round can change
Sanitize.PLAIN_ROUNDS = 8 -- max sanitizing rounds until a fixed point

-- One round: control and invisible characters first (else '|' + ZW + 'cFF...' becomes a new code once removed), then WoW codes.
-- strip can also join new codes ('|c|rFFFFFFFF' -> '|cFFFFFFFF'), so plain loops until a fixed point.
local function plainRound(s)
  s = gsub(s, "[\r\n\t]", " ")
  s = gsub(s, "%c", dropControl(false))
  for _, p in ipairs(INVISIBLE) do s = gsub(s, p, "") end
  s = Sanitize.strip(s)
  s = gsub(s, "|n", " ")
  return s
end

-- plain text without codes or control characters, '|' not yet doubled (for composing); nil if empty.
-- WARNING: never display plain directly (SetText, AddLine, format argument): a lone '|' survives and the client reads it as an escape.
-- Display only via Sanitize.display (doubles every '|').
function Sanitize.plain(s, max)
  if type(s) == "number" and not isSecret(s) then
    if s ~= s or s == math.huge or s == -math.huge then return nil end -- NaN/Inf: format('%d') is undefined
    if s > 2 ^ 53 then s = 2 ^ 53 elseif s < -(2 ^ 53) then s = -(2 ^ 53) end -- above this %d is no longer safe
    s = string.format("%.0f", math.floor(s) + 0) -- '%.0f' instead of '%d': safe above 2^31 too (test VM)
  end
  if isSecret(s) or type(s) ~= "string" then return nil end
  max = (type(max) == "number" and max == max and max >= 8) and math.floor(max) or Sanitize.DISPLAY_MAX
  s = Sanitize.cut(s, max * 4 + 64)
  local stable = false
  for _ = 1, Sanitize.PLAIN_ROUNDS do
    -- nothing to do without '|', control characters or invisible start bytes
    if not find(s, SPECIAL) then
      stable = true
      break
    end
    local before = s
    s = plainRound(s)
    if s == before then
      stable = true
      break
    end
  end
  if not stable then -- fallback without a fixed point: no '|', control or invisible characters left
    s = gsub(s, "|", "")
    s = gsub(s, "%c", "")
    for _, p in ipairs(INVISIBLE) do s = gsub(s, p, "") end
  end
  s = gsub(s, "  +", " ")
  s = gsub(s, "^ +", "")
  s = gsub(s, " +$", "")
  if s == "" then return nil end
  if #s > max then s = Sanitize.cut(s, max - #ELLIPSIS) .. ELLIPSIS end
  return s
end

-- display text: plain, then '|' -> '||' (WoW shows '||' as one '|'); nil if empty
function Sanitize.display(s, max)
  s = Sanitize.plain(s, max)
  if not s then return nil end
  return (gsub(s, "|", "||"))
end

-- &lt; and &gt; stay on purpose: resolving them could turn the text back into a tag
local ENTITIES = { quot = '"', apos = "'", nbsp = " " }

-- book text (ITEM_TEXT): HTML tags removed, <BR/>, <P> and </P> become line breaks, a few entities (quot, apos, nbsp, amp) resolved,
-- then longText applies. nil for non-strings, secret values and empty text.
function Sanitize.bookText(s)
  if isSecret(s) or type(s) ~= "string" then return nil end
  s = Sanitize.cut(s, Sanitize.LONG_MAX * 4)
  s = gsub(s, "<[Bb][Rr][^>]*>", "\n")
  s = gsub(s, "</[Pp]>", "\n")
  s = gsub(s, "<[Pp]>", "\n")
  s = gsub(s, "<[Pp]%s[^>]*>", "\n")
  s = gsub(s, "</?[Hh]%d[^>]*>", "\n")
  s = gsub(s, "<[^>]*>", "")
  s = gsub(s, "&(%a+);", function(name) return ENTITIES[string.lower(name)] end)
  s = gsub(s, "&amp;", "&")
  return Sanitize.longText(s)
end
