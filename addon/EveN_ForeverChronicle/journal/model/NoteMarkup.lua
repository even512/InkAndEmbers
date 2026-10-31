-- Note markup and its safety. Stored as simple markup ("# head", "- bullet", "[ ] / [x] check", "---", "**emph**",
-- "{rot}..{/}" ink colours, "{rt1}".."{rt8}" raid marks, "{stufe}" map icons, item/quest/spell links), rendered in the
-- read view.
-- Security: cleanBody runs before every save and rebuilds the text from checked pieces only ("||", item/quest/spell
-- links of a checked form, |T..|t only for an own icon); every other "|" becomes "||"; control and bidi characters are
-- dropped, length and lines are capped.
-- Display goes piecewise through Sanitize.display; only this code re-inserts colours, icons and checked links.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local M = {}
Journal.NoteMarkup = M

local byte, sub, find, gsub, match, lower = string.byte, string.sub, string.find, string.gsub, string.match, string.lower
local floor = math.floor

M.BODY_MAX = 4000      -- characters per note (stored text including markup)
M.TITLE_MAX = 80       -- characters per title
M.LINES_MAX = 300      -- lines per note
M.LINK_DATA_MAX = 200  -- bytes of link data (between |H and |h)
M.LINK_TEXT_MAX = 120  -- bytes of link text
M.DISPLAY_MAX = 8000   -- bytes per text piece in Sanitize.display

M.LINK_TYPES = { item = true, quest = true, spell = true }
-- ink on parchment (contrast >= 4.5 : 1, values from Theme.INK / Theme.C)
-- locale scope "m.NoteMarkup" for the toolbar labels (English in locales/enUS_model.lua), read on access.
-- The tokens in the text ("{stufe}", "rot") are syntax and stay German.
local TX = ns.Locale.ns("m.NoteMarkup", {
  color_schwarz = "Schwarz", color_rot = "Rot", color_blau = "Blau", color_gruen = "Grün",
  raid = { "Stern", "Kreis", "Diamant", "Dreieck", "Mond", "Quadrat", "Kreuz", "Totenkopf" },
  icon_stufe = "Stufenaufstieg", icon_meilenstein = "Meilenstein", icon_tod = "Tod", icon_selten = "Seltener Gegner",
  icon_elite = "Elite", icon_boss = "Boss", icon_foto = "Moment", icon_ruhestein = "Ruhestein", icon_flug = "Flugmeister",
  icon_kampf = "Kämpfe",
})
M.T = TX
local function lazyLabel(e, prefix)
  return setmetatable(e, { __index = function(t, k) if k == "label" then return TX[prefix .. t.key] end end })
end
M.COLORS = {
  schwarz = lazyLabel({ key = "schwarz", hex = "2B2118" }, "color_"),
  rot = lazyLabel({ key = "rot", hex = "8A2A1C" }, "color_"),
  blau = lazyLabel({ key = "blau", hex = "2F4E7A" }, "color_"),
  gruen = lazyLabel({ key = "gruen", hex = "2F552C" }, "color_"),
}
M.COLOR_ORDER = { "schwarz", "rot", "blau", "gruen" }
M.EMPH = "694613"     -- emphasis: ochre ink
M.HEAD = "4A2C18"     -- heading: dark red-brown (Theme.INK.head)
M.LINK_COLOR = { item = "5A3A78", quest = "694613", spell = "2F4E7A" }

M.RAID = {}
for i = 1, 8 do M.RAID[i] = { key = "rt" .. i, path = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i } end
M.RAID_NAMES = setmetatable({}, { __index = function(_, i) return TX.raid[i] end })
-- map icons (cells of Media/MapIcons, Theme.MAP_ICONS); key = token in the text
M.ICONS = {
  { key = "stufe", icon = "level" },
  { key = "meilenstein", icon = "milestone" },
  { key = "tod", icon = "death" },
  { key = "selten", icon = "rare" },
  { key = "elite", icon = "elite" },
  { key = "boss", icon = "boss" },
  { key = "foto", icon = "photo" },
  { key = "ruhestein", icon = "hearth" },
  { key = "flug", icon = "flightpoint" },
  { key = "kampf", icon = "kill" },
}
for _, it in ipairs(M.ICONS) do lazyLabel(it, "icon_") end
local ICON_BY_KEY = {}
for _, it in ipairs(M.ICONS) do ICON_BY_KEY[it.key] = it end
local RAID_BY_KEY = {}
for _, it in ipairs(M.RAID) do RAID_BY_KEY[it.key] = it end

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function theme() return Journal.Theme end

-- display of an icon: fixed path from this code, never from data
function M.symbolCode(key)
  local r = RAID_BY_KEY[key]
  if r then return "|T" .. r.path .. ":0|t" end
  local it = ICON_BY_KEY[key]
  local T = theme()
  if it and T and T.TEX and T.TEX.mapIcons and T.MAP_ICONS and T.MAP_ICONS[it.icon] and T.MAP_ICON_ATLAS then
    local a = T.MAP_ICON_ATLAS
    local i = T.MAP_ICONS[it.icon]
    local col, row = i % a.cols, floor(i / a.cols)
    return string.format("|T%s:0:0:0:0:%d:%d:%d:%d:%d:%d|t", T.TEX.mapIcons, a.size, a.size, col * a.cell + 1, (col + 1) * a.cell - 1,
      row * a.cell + 1, (row + 1) * a.cell - 1)
  end
  return nil
end

-- length of the UTF-8 sequence at i; nil if invalid (lead byte without the matching continuation bytes, lone
-- continuation byte, 0xC0/0xC1/0xF5..).
-- An invalid lead byte must never swallow the following bytes (e.g. a "|").
local function seqLen(s, i)
  local b = byte(s, i)
  if not b then return nil end
  if b < 128 then return 1 end
  local n = (b >= 194 and b <= 223 and 2) or (b >= 224 and b <= 239 and 3) or (b >= 240 and b <= 244 and 4) or nil
  if not n then return nil end
  for k = 1, n - 1 do
    local c = byte(s, i + k)
    if not c or c < 128 or c > 191 then return nil end
  end
  return n
end

-- step width when counting: a valid sequence at once, otherwise a single byte
local function charLen(s, i)
  return seqLen(s, i) or 1
end

function M.chars(s)
  if type(s) ~= "string" then return 0 end
  local n, i, len = 0, 1, #s
  while i <= len do
    n = n + 1
    i = i + charLen(s, i)
  end
  return n
end

-- keep valid UTF-8 sequences only
local function validUtf8(s)
  local out, n, i, len = {}, 0, 1, #s
  while i <= len do
    local cl = seqLen(s, i)
    if cl then
      n = n + 1
      out[n] = sub(s, i, i + cl - 1)
      i = i + cl
    else
      i = i + 1
    end
  end
  return table.concat(out, "", 1, n)
end

local function cutChars(s, n)
  local count, i, len = 0, 1, #s
  while i <= len do
    count = count + 1
    if count > n then return sub(s, 1, i - 1) end
    i = i + charLen(s, i)
  end
  return s
end

-- invisible/bidi characters (zero-width, overrides, isolates, BOM, line/paragraph separators)
local INVISIBLE = { "\226\128[\139-\143]", "\226\128[\168-\174]", "\226\129[\160-\175]", "\239\187\191", "\194\173" }

-- link at position i (s:sub(i, i) == "|"): -> canonical, next position | nil. A colour before / |r after are swallowed.
local function scanLink(s, i)
  local j = i
  local c = match(s, "^|c%x%x%x%x%x%x%x%x", j) or match(s, "^|cnIQ%d:", j)
  if c then j = j + #c end
  local ltype, data, text = match(s, "^|H(%a+):([%w:%-]*)|h%[([^|%]\n]*)%]|h", j)
  if not ltype or not M.LINK_TYPES[ltype] then return nil end
  if #data > M.LINK_DATA_MAX or #text > M.LINK_TEXT_MAX or text == "" then return nil end
  local raw = "|H" .. ltype .. ":" .. data .. "|h[" .. text .. "]|h"
  j = j + #raw
  if c and sub(s, j, j + 1) == "|r" then j = j + 2 end
  return raw, j, ltype
end

function M.canonLink(link)
  if isSecret(link) or type(link) ~= "string" or #link > 400 then return nil end
  if sub(link, 1, 1) ~= "|" then return nil end
  local raw, j = scanLink(link, 1)
  if not raw or j <= #link then return nil end
  return raw
end

function M.linkOk(link)
  local raw = M.canonLink(link)
  if not raw then return nil end
  return (match(raw, "^|H(%a+):"))
end

-- own icon codes (|T...|t exactly as M.symbolCode) -> token
local function symbolTable()
  local out = {}
  for _, r in ipairs(M.RAID) do
    local c = M.symbolCode(r.key)
    if c then out[#out + 1] = { code = c, key = r.key } end
  end
  for _, it in ipairs(M.ICONS) do
    local c = M.symbolCode(it.key)
    if c then out[#out + 1] = { code = c, key = it.key } end
  end
  return out
end

function M.cleanBody(s)
  if isSecret(s) or type(s) ~= "string" then return "" end
  s = sub(s, 1, M.BODY_MAX * 4 + 4096) -- cap before working
  s = gsub(s, "\r\n?", "\n")
  s = gsub(s, "\t", "  ")
  s = gsub(s, "[%z\1-\8\11-\31\127]", "")
  for _, p in ipairs(INVISIBLE) do s = gsub(s, p, "") end
  local syms = find(s, "|T", 1, true) and symbolTable() or nil
  local out, n, budget = {}, 0, M.BODY_MAX
  local i, len = 1, #s
  local function put(piece, chars)
    if chars > budget then return false end
    budget = budget - chars
    n = n + 1
    out[n] = piece
    return true
  end
  while i <= len do
    local b = byte(s, i)
    if b == 124 then -- "|"
      if byte(s, i + 1) == 124 then
        if not put("||", 1) then break end
        i = i + 2
      else
        local raw, j = scanLink(s, i)
        local sym
        if not raw and syms and sub(s, i + 1, i + 1) == "T" then
          for _, e in ipairs(syms) do
            if sub(s, i, i + #e.code - 1) == e.code then sym = e break end
          end
        end
        if raw then
          if not put(raw, M.chars(raw)) then break end
          i = j
        elseif sym then
          local tok = "{" .. sym.key .. "}"
          if not put(tok, #tok) then break end
          i = i + #sym.code
        else
          if not put("||", 1) then break end -- single "|": visible, never code
          i = i + 1
        end
      end
    else
      local cl = seqLen(s, i)
      if cl then
        if not put(sub(s, i, i + cl - 1), 1) then break end
        i = i + cl
      else
        i = i + 1 -- drop an invalid UTF-8 byte (does not swallow a following "|")
      end
    end
  end
  local body = table.concat(out, "", 1, n)
  -- cap lines, trim trailing whitespace
  local lines, count = {}, 0
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    count = count + 1
    if count > M.LINES_MAX then break end
    lines[count] = (gsub(line, " +$", ""))
  end
  body = table.concat(lines, "\n")
  body = gsub(body, "\n+$", "")
  return body
end

function M.cleanTitle(s)
  if isSecret(s) or type(s) ~= "string" then return nil end
  s = gsub(validUtf8(sub(s, 1, M.TITLE_MAX * 4 + 256)), "||", "|")
  local S = ns.Sanitize
  s = S and S.field(s) or ""
  s = cutChars(s, M.TITLE_MAX)
  s = gsub(s, " +$", "")
  if s == "" then return nil end
  return s
end

local function lines(body)
  local out = {}
  if type(body) ~= "string" or body == "" then return out end
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = line end
  return out
end

function M.parse(body)
  local blocks = {}
  for i, line in ipairs(lines(body)) do
    if i > M.LINES_MAX then break end
    local b
    local h = match(line, "^#+ +(.*)$")
    if h then
      b = { kind = "head", text = h }
    elseif match(line, "^%-%-%-+ *$") then
      b = { kind = "rule", text = "" }
    elseif match(line, "^%[[ xX]%] ") or match(line, "^%[[ xX]%]$") then
      local mark = sub(line, 2, 2)
      b = { kind = "check", text = sub(line, 5), checked = mark == "x" or mark == "X" }
    elseif match(line, "^%- ") then
      b = { kind = "bullet", text = sub(line, 3) }
    elseif match(line, "^ *$") then
      b = { kind = "blank", text = "" }
    else
      b = { kind = "text", text = line }
    end
    b.line = i
    blocks[#blocks + 1] = b
  end
  return blocks
end

function M.toggleLine(body, line)
  local list = lines(body)
  local l = list[line]
  if type(l) ~= "string" then return nil end
  local mark = match(l, "^%[([ xX])%]")
  if not mark then return nil end
  list[line] = "[" .. ((mark == " ") and "x" or " ") .. "]" .. sub(l, 4)
  return table.concat(list, "\n")
end

-- text piece display-ready: Sanitize.display (codes out, "|" -> "||"), spaces at the edges stay
local function safeRun(run)
  if run == "" then return "" end
  local lead, core, trail = match(run, "^( *)(.-)( *)$")
  local S = ns.Sanitize
  local shown = (core ~= "" and S and S.display(core, M.DISPLAY_MAX)) or ""
  return lead .. shown .. trail
end

local TOKEN = "^{([%w/]+)}"

-- split text without links (stored form, every "|" as "||") into runs and output them coloured
local function textPiece(piece, st, out)
  local literal = gsub(piece, "||", "|")
  local buf = {}
  local function flush()
    if #buf == 0 then return end
    local run = table.concat(buf)
    buf = {}
    local shown = safeRun(run)
    if shown == "" then return end
    local color = st.emph and M.EMPH or st.color or st.base
    if color then
      out[#out + 1] = "|cff" .. color .. shown .. "|r"
    else
      out[#out + 1] = shown
    end
  end
  local i, len = 1, #literal
  while i <= len do
    local c = sub(literal, i, i)
    if c == "*" and sub(literal, i + 1, i + 1) == "*" then
      flush()
      st.emph = not st.emph
      i = i + 2
    elseif c == "{" then
      local key = match(literal, TOKEN, i)
      local code = key and M.symbolCode(key)
      if key == "/" then
        flush()
        st.color = nil
        i = i + 3
      elseif key and M.COLORS[key] then
        flush()
        st.color = M.COLORS[key].hex
        i = i + #key + 2
      elseif code then
        flush()
        out[#out + 1] = code
        i = i + #key + 2
      else
        buf[#buf + 1] = c
        i = i + 1
      end
    else
      local cl = charLen(literal, i)
      buf[#buf + 1] = sub(literal, i, i + cl - 1)
      i = i + cl
    end
  end
  flush()
end

-- line (stored form) -> display-ready text, link count. Colour and emphasis last until the end of the line.
function M.inline(text, opts)
  if type(text) ~= "string" or text == "" then return "", 0 end
  opts = type(opts) == "table" and opts or {}
  local st = { base = opts.color }
  local out, links = {}, 0
  local i, len, start = 1, #text, 1
  while i <= len do
    if byte(text, i) == 124 and byte(text, i + 1) == 124 then
      i = i + 2
    elseif byte(text, i) == 124 then
      local raw, j, ltype = scanLink(text, i)
      if raw then
        textPiece(sub(text, start, i - 1), st, out)
        out[#out + 1] = "|cff" .. (M.LINK_COLOR[ltype] or M.LINK_COLOR.item) .. raw .. "|r"
        links = links + 1
        i, start = j, j
      else
        i = i + 1 -- cannot occur after cleanBody: a single "|" stays text and is doubled in safeRun
      end
    else
      i = i + 1
    end
  end
  textPiece(sub(text, start), st, out)
  return table.concat(out), links
end

function M.render(body)
  local blocks = M.parse(body)
  for _, b in ipairs(blocks) do
    if b.kind == "head" then
      b.display, b.links = M.inline(b.text, { color = M.HEAD })
    elseif b.kind == "rule" or b.kind == "blank" then
      b.display, b.links = "", 0
    else
      b.display, b.links = M.inline(b.text)
    end
  end
  return blocks
end

local UPPER_UMLAUT = { ["\195\132"] = "\195\164", ["\195\150"] = "\195\182", ["\195\156"] = "\195\188" }

function M.lower(s)
  s = lower(s)
  return (gsub(s, "\195[\132\150\156]", UPPER_UMLAUT))
end

local function plainLine(line)
  line = gsub(line, "|H%a+:[%w:%-]*|h%[([^|%]\n]*)%]|h", "%1")
  line = gsub(line, "||", "|")
  line = gsub(line, "^#+ +", "")
  line = gsub(line, "^%[[ xX]%] ?", "")
  line = gsub(line, "^%- ", "")
  line = gsub(line, "^%-%-%-+ *$", "")
  line = gsub(line, "%*%*", "")
  line = gsub(line, "{[%w/]+}", "")
  return line
end

function M.plain(body)
  local out = {}
  for _, line in ipairs(lines(body)) do out[#out + 1] = plainLine(line) end
  return M.lower(table.concat(out, "\n"))
end

function M.firstLine(body)
  for _, line in ipairs(lines(body)) do
    local p = plainLine(line)
    p = gsub(gsub(p, "^ +", ""), " +$", "")
    if p ~= "" then return M.cleanTitle(p) end
  end
  return nil
end
