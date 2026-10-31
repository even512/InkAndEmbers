-- Design constants: palette from the style sheet, client fonts, textures, atlases. Constants and small helpers only; creates no frames at load.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Theme = {}
Journal.Theme = Theme

local function hex(s)
  return { tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255 }
end

-- Palette. Small text (< 12 px) is never lighter than sepia.
Theme.C = {
  ink = hex("2B2118"),
  sepia = hex("6B5034"),
  red = hex("9B2C1F"),
  gold = hex("C9A14A"),
  blue = hex("2F4E7A"),
  memory = hex("5A3A78"),
  treasure = hex("3D6B3A"),
  parchment = hex("F4EBD6"),
  faint = hex("CDB586"),
  cover = hex("4D2B19"),
  card = hex("F8F1E0"),
  glow = hex("E0A24A"),
}
Theme.C.binding = Theme.C.cover

-- Client fonts only (no own TTF here). If Morpheus mis-renders umlauts, ss or quotes, switch Theme.FONT.title to Friz Quadrata.
Theme.FONT = {
  title = "Fonts\\MORPHEUS.TTF",
  text = "Fonts\\FRIZQT__.TTF",
  label = "Fonts\\ARIALN.TTF",
}
Theme.FONT.note = Theme.FONT.title

local MEDIA = "Interface\\AddOns\\EveN_ForeverChronicle\\Media\\"
Theme.MEDIA = MEDIA
Theme.TEX = {
  book = MEDIA .. "Book",
  bookmarks = MEDIA .. "Bookmarks", tabBands = MEDIA .. "BookmarksBronze", markers = MEDIA .. "Markers", grain = MEDIA .. "Grain",
  tape = MEDIA .. "Tape", card = MEDIA .. "Card", minimap = MEDIA .. "MinimapIcon", round = MEDIA .. "RoundRect",
  ring = MEDIA .. "RoundRing", dash = MEDIA .. "Dash", mapFade = MEDIA .. "MapFade", pageFade = MEDIA .. "PageFade",
  seals = MEDIA .. "Seals", zoneSeal = MEDIA .. "ZoneSeal",
  toast = MEDIA .. "Toast", glow = MEDIA .. "Glow", disc = MEDIA .. "Disc",
  welcomeCard = MEDIA .. "WelcomeCard",
  hatch = MEDIA .. "Hatch",
  sword = MEDIA .. "Sword", swordIcon = MEDIA .. "SwordIcon",
  mapKill = MEDIA .. "MapKill",
  btnTotal = MEDIA .. "BtnTotal",
}
Theme.HAS_SWORD_ICON = true
Theme.HAS_MAP_KILL = true

-- Book base image (Media/Book.tga, 1024 x 1024 = crop BOOK_CROP in scripts/render-media.mjs): the whole open book with cover, metal
-- caps and page block. Stretched in 15 pieces in game (Frame.bookPieces). Measures are pixels of the crop (1888 x 1275 source
-- pixels, same numbers as BOOK_SLICE_SRC in render-media.mjs).
Theme.BOOK_SLICE = { w = 1888, h = 1275, margin = 48, ring = 72, corner = 160, spine0 = 884, spine1 = 1005 }

-- Parchment per tab: one page pair per tab, split at the fold from one image (Media/Page_<tab>_L/_R, SPREAD_CROPS in
-- scripts/render-media.mjs). Unknown tabs get the journey parchment.
function Theme.paper(id)
  local known = false
  for _, tab in ipairs(Theme.TABS) do
    if tab.id == id then known = true end
  end
  if not known then id = Theme.TABS[1].id end
  return MEDIA .. "Page_" .. id .. "_L", MEDIA .. "Page_" .. id .. "_R"
end

-- Marker atlas (Media/Markers.tga, 4 x 4 cells). Order = scripts/render-media.mjs.
Theme.ATLAS = {
  level = 0, milestone = 1, death = 2, rare = 3, elite = 4, boss = 5, photo = 6, hearth = 7, flightpoint = 8, gap = 9,
  current = 10, pulse = 11, play = 12, pause = 13, disc = 14, close = 15,
}
Theme.MARKER_SIZE = {
  level = 22, milestone = 28, death = 24, rare = 24, elite = 24, boss = 28, photo = 24, hearth = 24, flightpoint = 24,
  gap = 22, current = 26,
}

-- Map event icons (Media/MapIcons.tga 512 x 512, 4 x 4 tiles of 128 px, 12 used; scripts/cut-icons.mjs). Order = MAP_ICON_IDS in
-- cut-icons.mjs (a test keeps both equal). current = player position, an own file (Media/MapCurrent.tga) because the whole
-- texture is rotated with SetRotation to the facing; the arrow points up in the file.
Theme.TEX.mapIcons = MEDIA .. "MapIcons"
-- Note pin (Media/NotePin.tga 64 x 64): tip at the bottom left (tipX/tipY as share of the edge).
Theme.TEX.notePin = MEDIA .. "NotePin"
Theme.NOTE_PIN = { size = 26, tipX = 7 / 64, tipY = 57 / 64 }
Theme.TEX.mapCurrent = MEDIA .. "MapCurrent"
-- Quest giver mark "!" (Media/QuestMark.tga 64 x 64), untinted; locked = desaturated
Theme.TEX.questMark = MEDIA .. "QuestMark"
for i = 1, 5 do Theme.TEX["fireNote" .. i] = MEDIA .. "FireNote" .. i end
Theme.HAS_MAP_ICONS = true
Theme.HAS_MAP_CURRENT = true
Theme.MAP_ICONS = {
  level = 0, milestone = 1, death = 2, rare = 3, elite = 4, boss = 5, photo = 6, hearth = 7, flightpoint = 8, gap = 9,
  current = 10, kill = 11,
}
Theme.MAP_ICON_ATLAS = { cols = 4, size = 512, cell = 128 }
-- texcoords of tile kind in MapIcons (nil if there is none); half a texel away from the neighbour
function Theme.mapIconCoords(kind)
  local i = Theme.MAP_ICONS[kind]
  if not i then return nil end
  local a = Theme.MAP_ICON_ATLAS
  local col, row = i % a.cols, math.floor(i / a.cols)
  local e = 0.5 / a.size
  return (col * a.cell) / a.size + e, ((col + 1) * a.cell) / a.size - e, (row * a.cell) / a.size + e, ((row + 1) * a.cell) / a.size - e
end

-- Kill emblems of the combat page (Media/KillEmblems.tga 512 x 512, 2 x 2 tiles of 256 px; scripts/cut-emblems.mjs). i = tile
-- (0-based, row by row), band = centre (u, v) and size (w, h) of the free band as share of the tile (measured per emblem; the
-- kill-emblems test checks them against the texture), ink = font colour on the metal, shade = shadow.
Theme.TEX.killEmblems = MEDIA .. "KillEmblems"
Theme.HAS_KILL_EMBLEMS = true
Theme.EMBLEM_ATLAS = { cols = 2, size = 512, cell = 256 }
Theme.EMBLEMS = {
  normal = { i = 0, band = { u = 0.498, v = 0.674, w = 0.46, h = 0.145 }, ink = { 0.13, 0.07, 0.03 }, shade = { 1, 0.85, 0.62, 0.55 } },
  elite = { i = 1, band = { u = 0.501, v = 0.691, w = 0.41, h = 0.135 }, ink = { 0.25, 0.14, 0.02 }, shade = { 1, 0.93, 0.6, 0.6 } },
  rare = { i = 2, band = { u = 0.489, v = 0.693, w = 0.46, h = 0.145 }, ink = { 0.10, 0.12, 0.17 }, shade = { 1, 1, 1, 0.65 } },
  boss = { i = 3, band = { u = 0.500, v = 0.711, w = 0.46, h = 0.10 }, ink = { 0.97, 0.91, 0.78 }, shade = { 0, 0, 0, 0.9 } },
}
-- texcoords of the tile of emblem kind (nil if there is none); half a texel away from the neighbour
function Theme.emblemCoords(kind)
  local e = Theme.EMBLEMS[kind]
  if not e then return nil end
  local a = Theme.EMBLEM_ATLAS
  local col, row = e.i % a.cols, math.floor(e.i / a.cols)
  local h = 0.5 / a.size
  return (col * a.cell) / a.size + h, ((col + 1) * a.cell) / a.size - h, (row * a.cell) / a.size + h, ((row + 1) * a.cell) / a.size - h
end

-- Moments page: album tape (art/journal/tape.jpg), icon atlas per moment kind (Media/MomentIcons.tga 512 x 256, 3 x 2 cells of
-- 128 px, 4th column empty; order = MOMENT_ICON_IDS in render-media.mjs) and the soft bar of the play-time clock
-- (Media/ClockBar.tga 32 x 128, white, border CLOCK_BAR_PAD per side, tinted via SetVertexColor).
Theme.TEX.momentTape = MEDIA .. "MomentTape"
Theme.TEX.momentIcons = MEDIA .. "MomentIcons"
Theme.TEX.clockBar = MEDIA .. "ClockBar"
Theme.MOMENT_ICONS = { level = 0, fight = 1, death = 2, find = 3, place = 4, memory = 5 }
Theme.CLOCK_BAR_PAD = { x = 8 / 32, y = 8 / 128 }
function Theme.momentIconCoords(name)
  local i = Theme.MOMENT_ICONS[name] or Theme.MOMENT_ICONS.memory
  local col, row = i % 3, math.floor(i / 3)
  return col * 128 / 512, (col + 1) * 128 / 512, row * 128 / 256, (row + 1) * 128 / 256
end

-- Polaroid sheets: one 3 x 3 sheet per theme group (Media/Polaroid_<sheet>.tga, 1024 x 1024); cell i (1..9, row by row) at
-- column (i-1) % 3, row floor((i-1) / 3), edge POLAROID_ATLAS.cell, picture centred, pad px transparent around.
-- HAS_POLAROIDS[sheet] = true once the TGA exists (a test keeps it equal to the Media folder).
Theme.TEX.polaroidPaper = MEDIA .. "PolaroidPaper"
Theme.POLAROID_SHEETS = { "orte", "kampf", "funde", "stufen", "zonen1", "zonen2", "zonen3", "zonen4", "zonen5", "zonen6", "start",
  "aufstieg", "slots1", "slots2", "rares" }
for _, name in ipairs(Theme.POLAROID_SHEETS) do Theme.TEX["polaroid_" .. name] = MEDIA .. "Polaroid_" .. name end
Theme.HAS_POLAROIDS = {
  orte = true, kampf = true, funde = true, stufen = true,
  zonen1 = true, zonen2 = true, zonen3 = true, zonen4 = true, zonen5 = true, zonen6 = true,
  start = true, aufstieg = true, slots1 = true, slots2 = true, rares = true,
}
-- Painted frame Media/PolaroidFrame.tga (512 x 512, crop POLAROID_FRAME; picture area transparent = hole). The page puts the
-- frame OVER the picture, which fills exactly the hole. POLAROID_HOLE: aspect (w / h) of the crop and the hole as share of
-- the crop width (l, r) / height (t, b), computed from the source pixels (a test recomputes).
Theme.TEX.polaroidFrame = MEDIA .. "PolaroidFrame"
Theme.HAS_POLAROID_FRAME = true
Theme.POLAROID_HOLE = { aspect = 953 / 1150, l = 63 / 953, t = 71 / 1150, r = 887 / 953, b = 909 / 1150 }
-- Each cell carries the picture only in the middle (edge cell - 2 * pad = 293 px) with a transparent border of pad px, so the
-- picture can be shown as a truly rotated rectangle (Theme.polaroidTilt): the rotated edges lie in the border, never in the
-- neighbour cell. tiltMax = largest tilt (degrees) the border covers; matches POLAROID_ATLAS in render-media.mjs.
Theme.POLAROID_ATLAS = { size = 1024, cell = 341, inset = 2, pad = 24, tiltMax = 3 }
Theme.TEX.polaroidGround = MEDIA .. "PolaroidGround"
Theme.POLAROID_GROUND = { size = 256, inset = 1, pad = 18 }
-- texcoords of cell i (1..9) of a sheet, inset by inset texture pixels so no neighbour bleeds in
function Theme.polaroidCoords(i)
  local a = Theme.POLAROID_ATLAS
  local idx = math.max(1, math.min(9, math.floor(tonumber(i) or 1))) - 1
  local col, row = idx % 3, math.floor(idx / 3)
  local x0, y0 = col * a.cell + a.inset, row * a.cell + a.inset
  local x1, y1 = (col + 1) * a.cell - a.inset, (row + 1) * a.cell - a.inset
  return x0 / a.size, x1 / a.size, y0 / a.size, y1 / a.size
end

-- Tab bookmarks (Media/Bookmarks.tga, one cell per tab id). The label is looked up when read (the language is only known at
-- ADDON_LOADED, docs/i18n.md).
local TT = ns.Locale.ns("Theme", {
  tab_reise = "Reise",
  tab_chronik = "Chronik",
  tab_kampf = "Kampf",
  tab_quests = "Quests",
  tab_schaetze = "Schätze",
  tab_momente = "Momente",
  tab_notizen = "Notizen",
})
local function tab(id, active)
  return setmetatable({ id = id, active = active }, { __index = function(_, k)
    if k == "label" then return TT["tab_" .. id] end
    return nil
  end })
end
Theme.TABS = {
  tab("reise", true),
  tab("chronik"),
  tab("kampf"),
  tab("quests"),
  tab("schaetze"),
  tab("momente"),
  tab("notizen"),
}

function Theme.atlasCoords(index)
  local col, row = index % 4, math.floor(index / 4)
  return col / 4, (col + 1) / 4, row / 4, (row + 1) / 4
end

-- Medal image = motif + metal ring, stacked. Media/Seals.tga (1024 x 1024, 8 x 8 cells, catalog order) and Media/SealFrames.tga
-- (512 x 512, 2 x 2: bronze, silver, gold, legendary). Motif at SEAL_MOTIF_SCALE of the edge (ring opening is 0.664), ring of the
-- highest earned tier on top; not earned yet: ring of the first tier (the page desaturates both).
Theme.SEAL_LAYERED = true
Theme.SEAL_ATLAS = { cols = 8, rows = 8 }
Theme.TEX.sealFrames = MEDIA .. "SealFrames"
Theme.SEAL_FRAME_ATLAS = { cols = 2, rows = 2 }
Theme.SEAL_FRAME_CELL = { bronze = 0, silver = 1, gold = 2, legendary = 3 }
Theme.SEAL_MOTIF_SCALE = 0.68                    -- share of the edge; ring opening is 0.664
Theme.SEAL_ICON_SCALE = 0.62
Theme.SEAL_METAL = {
  bronze = { 0.80, 0.52, 0.28 }, silver = { 0.80, 0.84, 0.90 }, gold = { 0.98, 0.80, 0.30 }, legendary = { 1.00, 0.55, 0.15 },
  none = { 0.80, 0.71, 0.53 },
}

function Theme.sealCoords(i)
  local a = Theme.SEAL_ATLAS
  local idx = (tonumber(i) or 1) - 1
  local col, row = idx % a.cols, math.floor(idx / a.cols)
  return col / a.cols, (col + 1) / a.cols, row / a.rows, (row + 1) / a.rows
end

function Theme.sealFrameCoords(tier)
  local a = Theme.SEAL_FRAME_ATLAS
  local idx = Theme.SEAL_FRAME_CELL[tier] or 0
  local col, row = idx % a.cols, math.floor(idx / a.cols)
  return col / a.cols, (col + 1) / a.cols, row / a.rows, (row + 1) / a.rows
end

function Theme.sealLayers(seal, tier)
  if type(seal) ~= "table" then return { tex = Theme.TEX.disc, color = Theme.SEAL_METAL.none }, nil end
  local shown = tier or seal.tier or "bronze"
  if Theme.SEAL_LAYERED then
    return { tex = Theme.TEX.seals, coords = { Theme.sealCoords(seal.index) }, scale = Theme.SEAL_MOTIF_SCALE },
      { tex = Theme.TEX.sealFrames, coords = { Theme.sealFrameCoords(shown) } }
  end
  local icon = "memory"
  local C = ns.Journal and ns.Journal.Chronik
  for _, f in ipairs(C and C.FAMILIES or {}) do
    if f.id == seal.family then icon = f.icon end
  end
  return { tex = Theme.TEX.disc, color = Theme.SEAL_METAL[tier or "none"] or Theme.SEAL_METAL.none },
    { tex = Theme.TEX.momentIcons, coords = { Theme.momentIconCoords(icon) }, scale = Theme.SEAL_ICON_SCALE }
end

-- Bookmark atlas (Media/Bookmarks.tga, 512 x 1024): seven cells of 512 x 96 stacked, one per tab id (not per order). Matches
-- BOOKMARK_IDS/BOOKMARK_ATLAS in render-media.mjs; cell ratio 512 : 96 = Frame.TAB.w : h.
Theme.BOOKMARK_ATLAS = { w = 512, h = 1024, cellW = 512, cellH = 96 }
Theme.BOOKMARK_CELL = { reise = 0, chronik = 1, kampf = 2, quests = 3, schaetze = 4, momente = 5, notizen = 6 }
function Theme.bookmarkCoords(id)
  local i = Theme.BOOKMARK_CELL[id]
  if i == nil then return nil end
  local a = Theme.BOOKMARK_ATLAS
  return 0, 1, i * a.cellH / a.h, (i + 1) * a.cellH / a.h
end

-- Main tabs "Forever bronze" (Media/BookmarksBronze.tga, 512 x 1024): seven leather tabs with bronze cap of 480 x 102 stacked,
-- one cell per tab id as Theme.BOOKMARK_CELL (sub-bookmarks stay on Media/Bookmarks.tga). Matches TAB_BAND_ATLAS in
-- render-media.mjs; ratio 480 : 102 = Frame.TAB.w : h.
Theme.TAB_BAND_ATLAS = { w = 512, h = 1024, cellW = 480, cellH = 102 }
function Theme.tabBandCoords(id)
  local i = Theme.BOOKMARK_CELL[id]
  if i == nil then return nil end
  local a = Theme.TAB_BAND_ATLAS
  return 0, a.cellW / a.w, i * a.cellH / a.h, (i + 1) * a.cellH / a.h
end

-- Tilted texcoords of an atlas cell (SetRotation would shear and sample beyond the cell). Window u0..u1, v0..v1 on a w x h pixel
-- area, tilted deg degrees counter-clockwise, aspect-corrected; the sampling area shrinks if the corners cross the bounds
-- (bu0..bv1). Returns UL, LL, UR, LR texcoords and the sampling scale as ninth value.
function Theme.rotCoords(u0, u1, v0, v1, w, h, deg, bu0, bu1, bv0, bv1)
  local us, vs = u1 - u0, v1 - v0
  local cu, cv = (u0 + u1) / 2, (v0 + v1) / 2
  local a = math.rad(tonumber(deg) or 0)
  local c, sn = math.cos(a), math.sin(a)
  local hw, hh = w / 2, h / 2
  local maxX, maxY = hw * c + hh * math.abs(sn), hw * math.abs(sn) + hh * c
  local roomX = math.min(cu - (bu0 or u0), (bu1 or u1) - cu) / us * w
  local roomY = math.min(cv - (bv0 or v0), (bv1 or v1) - cv) / vs * h
  local s = math.min(1, roomX / maxX, roomY / maxY)
  local function at(sx, sy)
    local ix, iy = sx * c + sy * sn, -sx * sn + sy * c
    return cu + s * ix / w * us, cv - s * iy / h * vs
  end
  local ulu, ulv = at(-hw, hh)
  local llu, llv = at(-hw, -hh)
  local uru, urv = at(hw, hh)
  local lru, lrv = at(hw, -hh)
  return ulu, ulv, llu, llv, uru, urv, lru, lrv, s
end
function Theme.rotCoords8(...)
  local ulu, ulv, llu, llv, uru, urv, lru, lrv = Theme.rotCoords(...)
  return ulu, ulv, llu, llv, uru, urv, lru, lrv
end

function Theme.polaroidQuad(w, h, tiltMax)
  local a = math.rad(tiltMax or Theme.POLAROID_ATLAS.tiltMax)
  local c, s = math.cos(a), math.sin(a)
  return math.ceil(w * c + h * s) + 2, math.ceil(w * s + h * c) + 2
end

-- Whole texture rotated rigidly. SetRotation shears on a non-square area (polaroid frame), so paper, shadow, photo and ground
-- rotate through the same texcoords on an area of Theme.polaroidQuad(w, h) (room for the corners); nothing lies outside 0..1
-- (the texture is transparent at all four edges).
function Theme.polaroidTiltFull(w, h, deg)
  local qw, qh = Theme.polaroidQuad(w, h)
  local uw, vh = qw / w, qh / h
  return Theme.rotCoords(0.5 - uw / 2, 0.5 + uw / 2, 0.5 - vh / 2, 0.5 + vh / 2, qw, qh, deg, -16, 17, -16, 17)
end

-- Texcoords for a rotated rectangle from a padded cell: the cell carries the picture as a content-px square in the middle,
-- transparent around. Shown on Theme.polaroidQuad(w, h), the picture itself on w x h pixels (no zoom-in); the rotated area
-- corners only sample the transparent border while deg <= tiltMax.
function Theme.polaroidTilt(bu0, bu1, bv0, bv1, content, size, w, h, deg)
  local qw, qh = Theme.polaroidQuad(w, h)
  local cu, cv = (bu0 + bu1) / 2, (bv0 + bv1) / 2
  local uw, vh = qw * (content / w) / size, qh * (content / h) / size
  return Theme.rotCoords(cu - uw / 2, cu + uw / 2, cv - vh / 2, cv + vh / 2, qw, qh, deg, bu0, bu1, bv0, bv1)
end

function Theme.color(region, c, a)
  if region and c then
    if region.SetTextColor then
      region:SetTextColor(c[1], c[2], c[3], a or 1)
    elseif region.SetVertexColor then
      region:SetVertexColor(c[1], c[2], c[3], a or 1)
    end
  end
  return region
end

-- Ink on parchment: Theme.ink(fs, kind) removes the drop shadow and replaces SetTextColor of THIS FontString by inkSetTextColor:
-- palette colours become their ink (Theme.INK_MAP; fonts only), headings get INK.head, dark colours get opacity INK.alpha.
-- Light colours (brightness above INK.light) are left alone.
Theme.INK = {
  alpha = 0.9,
  light = 0.5,
  text = Theme.C.ink,
  soft = hex("5E4630"),      -- darker than Theme.C.sepia so it keeps >= 4.5 : 1 with transparency
  head = hex("4A2C18"),
  red = hex("8A2A1C"),
  ochre = hex("694613"),     -- ochre instead of gold leaf (gold text would only reach 1.8 : 1 on parchment)
  green = hex("2F552C"),
  bigSize = 20,
  big = hex("50301C"),
  bigAlpha = 0.9,
  bleed = { x = 1, y = -1, alpha = 0.18 },
  paperAlpha = 0.18,
  maxOverlays = 48,
  quality = { [0] = hex("524D46"), [1] = Theme.C.ink, [2] = hex("175820"), [3] = hex("1A4E86"), [4] = hex("642A84"),
    [5] = hex("7A3C00"), [6] = hex("5C4E16"), [7] = hex("1C5058") },
}
Theme.INK_MAP = {
  { Theme.C.sepia, Theme.INK.soft }, { Theme.C.red, Theme.INK.red }, { Theme.C.gold, Theme.INK.ochre },
  { Theme.C.treasure, Theme.INK.green },
}

local function same(c, r, g, b)
  return math.abs(c[1] - r) < 0.003 and math.abs(c[2] - g) < 0.003 and math.abs(c[3] - b) < 0.003
end

function Theme.inkColor(r, g, b, a, head, big)
  if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return r, g, b, a end
  local INK = Theme.INK
  if head and big and same(Theme.C.ink, r, g, b) then
    r, g, b = INK.big[1], INK.big[2], INK.big[3]
  elseif head and same(Theme.C.ink, r, g, b) then
    r, g, b = INK.head[1], INK.head[2], INK.head[3]
  else
    for _, m in ipairs(Theme.INK_MAP) do
      if same(m[1], r, g, b) then
        r, g, b = m[2][1], m[2][2], m[2][3]
        break
      end
    end
  end
  a = type(a) == "number" and a or 1
  if 0.2126 * r + 0.7152 * g + 0.0722 * b < INK.light then a = a * (big and INK.bigAlpha or INK.alpha) end
  return r, g, b, a
end

-- Big titles (title font from INK.bigSize px): colour INK.big / INK.bigAlpha, bleed (the client's shadow, 1 px offset, faint;
-- no second FontString needed) and paper fibre (a cutout of the SAME page texture at the same place, above the text).
local bigList, ovFree, ovCreated, flushPending, retries = {}, {}, 0, false, 0
local paper

local function isBig(fs)
  local file, size = fs.inkFile, fs.inkSize
  return type(file) == "string" and type(size) == "number" and size >= Theme.INK.bigSize
    and file:lower() == Theme.FONT.title:lower()
end

local function isNum(v) return type(v) == "number" and v == v end

local function releaseOverlay(fs)
  local ov = fs.inkPaper
  if ov then
    ov:Hide()
    fs.inkPaper = nil
    ovFree[#ovFree + 1] = ov
  end
end

local function acquireOverlay(fs)
  local parent = fs.GetParent and fs:GetParent()
  if type(parent) ~= "table" or not parent.CreateTexture then return nil end
  local ov
  while not ov and #ovFree > 0 do
    ov = table.remove(ovFree)
    if ov.SetParent then pcall(ov.SetParent, ov, parent) else ov = nil end
  end
  if not ov then
    if ovCreated >= Theme.INK.maxOverlays then return nil end
    ov = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    ovCreated = ovCreated + 1
    ov:SetVertexColor(1, 1, 1, 1)
    ov:SetAlpha(Theme.INK.paperAlpha)
  end
  fs.inkPaper = ov
  return ov
end

local function syncOne(fs)
  local P = paper
  local text = fs.GetText and fs:GetText()
  if not P or type(text) ~= "string" or text == "" or (fs.IsVisible and not fs:IsVisible()) then
    releaseOverlay(fs)
    return false
  end
  local l, t, w, h = fs:GetLeft(), fs:GetTop(), fs:GetWidth(), fs:GetHeight()
  local sw, sh = fs:GetStringWidth(), fs:GetStringHeight()
  if not (isNum(l) and isNum(t) and isNum(sw)) then
    releaseOverlay(fs)
    return true
  end
  if not isNum(w) or w <= 0 then w = sw end
  if not isNum(h) or h <= 0 then h = isNum(sh) and sh or 0 end
  if not isNum(sh) or sh <= 0 then sh = h end
  local tw, th = math.min(sw, w), math.min(sh, h)
  local jh = fs.GetJustifyH and fs:GetJustifyH() or "LEFT"
  local jv = fs.GetJustifyV and fs:GetJustifyV() or "MIDDLE"
  local x0, y0 = l, t
  if jh == "CENTER" then x0 = l + (w - tw) / 2 elseif jh == "RIGHT" then x0 = l + w - tw end
  if jv == "MIDDLE" then y0 = t - (h - th) / 2 elseif jv == "BOTTOM" then y0 = t - (h - th) end
  local page, tex = P.left, P.texL
  local rl = P.right:GetLeft()
  if isNum(rl) and x0 + tw / 2 >= rl then page, tex = P.right, P.texR end
  local pl, pt, pw, ph = page:GetLeft(), page:GetTop(), page:GetWidth(), page:GetHeight()
  if not (isNum(pl) and isNum(pt) and isNum(pw) and isNum(ph) and pw > 0 and ph > 0) then
    releaseOverlay(fs)
    return true
  end
  if not tex then
    releaseOverlay(fs)
    return false
  end
  local pad = 3
  local ex0, ex1 = math.max(x0 - pad, pl), math.min(x0 + tw + pad, pl + pw)
  local ey0, ey1 = math.min(y0 + pad, pt), math.max(y0 - th - pad, pt - ph)
  if ex1 <= ex0 or ey0 <= ey1 then
    releaseOverlay(fs)
    return false
  end
  local ov = fs.inkPaper or acquireOverlay(fs)
  if not ov then return false end
  ov:ClearAllPoints()
  ov:SetPoint("TOPLEFT", fs, "TOPLEFT", ex0 - l, ey0 - t)
  ov:SetSize(ex1 - ex0, ey0 - ey1)
  if ov.inkTex ~= tex then
    ov:SetTexture(tex)
    ov.inkTex = tex
  end
  ov:SetTexCoord((ex0 - pl) / pw, (ex1 - pl) / pw, (pt - ey0) / ph, (pt - ey1) / ph)
  ov:Show()
  return false
end

function Theme.syncPaper()
  local again = false
  for _, fs in ipairs(bigList) do
    local ok, retry = pcall(syncOne, fs)
    if ok and retry then again = true end
  end
  if again and retries < 3 then
    retries = retries + 1
    Theme.paperChanged()
  elseif not again then
    retries = 0
  end
end

function Theme.paperChanged()
  if flushPending then return end
  if not (C_Timer and C_Timer.After) then
    Theme.syncPaper()
    return
  end
  flushPending = true
  C_Timer.After(0, function()
    flushPending = false
    Theme.syncPaper()
  end)
end

function Theme.setPaper(left, right, texL, texR)
  paper = (left and right) and { left = left, right = right, texL = texL, texR = texR } or nil
  Theme.paperChanged()
end

local function wrapAfter(fs, name)
  local flag = "inkWrapped" .. name
  if fs[flag] or type(fs[name]) ~= "function" then return end
  fs[flag] = true
  local base = fs[name]
  fs[name] = function(self, ...)
    local res = base(self, ...)
    if self.inkBig then Theme.paperChanged() end
    return res
  end
end

function Theme.inkTitle(fs)
  if type(fs) ~= "table" or fs.inkPlain then return fs end
  local INK = Theme.INK
  local big, was = isBig(fs), fs.inkBig == true
  fs.inkBig = big or nil
  if big then
    if not fs.inkListed then
      fs.inkListed = true
      bigList[#bigList + 1] = fs
      wrapAfter(fs, "SetText")
      wrapAfter(fs, "SetPoint")
    end
    if fs.SetShadowOffset then fs:SetShadowOffset(INK.bleed.x, INK.bleed.y) end
  elseif was then
    for i = #bigList, 1, -1 do
      if bigList[i] == fs then table.remove(bigList, i) end
    end
    fs.inkListed = nil
    releaseOverlay(fs)
    if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0) end
  end
  local raw = fs.inkRaw
  if (big or was) and raw and fs.SetTextColor then fs:SetTextColor(raw[1], raw[2], raw[3], raw[4]) end
  if big then Theme.paperChanged() end
  return fs
end

local function inkSetTextColor(self, r, g, b, a)
  local raw = self.inkRaw
  if not raw then
    raw = {}
    self.inkRaw = raw
  end
  raw[1], raw[2], raw[3], raw[4] = r, g, b, a
  local r2, g2, b2, a2 = Theme.inkColor(r, g, b, a, self.inkHead, self.inkBig)
  local res = self.inkBase(self, r2, g2, b2, a2)
  if self.inkBig and isNum(r2) and self.SetShadowColor then
    self:SetShadowColor(r2, g2, b2, Theme.INK.bleed.alpha * (isNum(a) and a or 1))
  end
  return res
end

local function inkSetFont(self, file, size, flags)
  local res = self.inkFontBase(self, file, size, flags)
  if res ~= false then self.inkFile, self.inkSize = file, size end
  Theme.inkTitle(self)
  return res
end

function Theme.ink(fs, kind, file, size)
  if type(fs) ~= "table" or fs.inkPlain then return fs end
  if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
  if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0) end
  fs.inkHead = kind == "title"
  if file == nil and fs.inkFile == nil and type(fs.GetFont) == "function" then file, size = fs:GetFont() end
  if file ~= nil then fs.inkFile, fs.inkSize = file, size end
  if not fs.inkBase and type(fs.SetTextColor) == "function" then
    fs.inkBase = fs.SetTextColor
    fs.SetTextColor = inkSetTextColor
  end
  if not fs.inkFontBase and type(fs.SetFont) == "function" then
    fs.inkFontBase = fs.SetFont
    fs.SetFont = inkSetFont
  end
  Theme.inkTitle(fs)
  return fs
end

function Theme.font(fs, kind, size, color, flags)
  local file = Theme.FONT[kind] or Theme.FONT.text
  local ok = pcall(fs.SetFont, fs, file, size or 12, flags or "")
  if not ok and fs.SetFontObject and GameFontNormal then fs:SetFontObject(GameFontNormal) end
  Theme.ink(fs, kind, ok and file or nil, size or 12)
  if color then Theme.color(fs, color) end
  return fs
end

function Theme.fontString(parent, kind, size, color, layer, justify, plain)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  if plain then fs.inkPlain = true end
  Theme.font(fs, kind, size, color)
  if justify then fs:SetJustifyH(justify) end
  return fs
end

function Theme.texture(parent, file, layer, sub)
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
  if file then t:SetTexture(file) end
  return t
end

function Theme.roundRect(parent, color, alpha, r, layer, file)
  r = r or 8
  local parts = {}
  local u = { 0, 0.25, 0.75, 1 }
  for row = 1, 3 do
    for col = 1, 3 do
      local t = parent:CreateTexture(nil, layer or "BACKGROUND")
      t:SetTexture(file or Theme.TEX.round)
      t:SetTexCoord(u[col], u[col + 1], u[row], u[row + 1])
      Theme.color(t, color or Theme.C.card, alpha or 1)
      parts[#parts + 1] = t
      if col ~= 2 then t:SetWidth(r) end
      if row ~= 2 then t:SetHeight(r) end
      local px = (col == 1) and "LEFT" or ((col == 3) and "RIGHT" or "")
      local py = (row == 1) and "TOP" or ((row == 3) and "BOTTOM" or "")
      if col ~= 2 and row ~= 2 then
        t:SetPoint(py .. px, parent, py .. px, 0, 0)
      end
    end
  end
  local p = parts
  p[2]:SetPoint("TOPLEFT", p[1], "TOPRIGHT") p[2]:SetPoint("BOTTOMRIGHT", p[3], "BOTTOMLEFT")
  p[8]:SetPoint("TOPLEFT", p[7], "TOPRIGHT") p[8]:SetPoint("BOTTOMRIGHT", p[9], "BOTTOMLEFT")
  p[4]:SetPoint("TOPLEFT", p[1], "BOTTOMLEFT") p[4]:SetPoint("BOTTOMRIGHT", p[7], "TOPRIGHT")
  p[6]:SetPoint("TOPLEFT", p[3], "BOTTOMLEFT") p[6]:SetPoint("BOTTOMRIGHT", p[9], "TOPRIGHT")
  p[5]:SetPoint("TOPLEFT", p[1], "BOTTOMRIGHT") p[5]:SetPoint("BOTTOMRIGHT", p[9], "TOPLEFT")
  local obj = { parts = parts }
  function obj.color(c, a) for _, t in ipairs(parts) do Theme.color(t, c, a) end end
  function obj.show(on) for _, t in ipairs(parts) do t:SetShown(on and true or false) end end
  return obj
end

function Theme.tooltip(owner, tip, extra)
  local tt = GameTooltip
  if not tt or type(tip) ~= "table" then return end
  tt:SetOwner(owner, "ANCHOR_RIGHT")
  if tip.title then tt:AddLine(tip.title, 1, 0.82, 0) end
  local where = tip.when
  if tip.place then where = where and (where .. " · " .. tip.place) or tip.place end
  if where then tt:AddLine(where, 0.9, 0.9, 0.9) end
  if tip.level then tt:AddLine(tip.level, 0.9, 0.9, 0.9) end
  if tip.detail then tt:AddLine(tip.detail, 0.8, 0.8, 0.8, true) end
  if extra then tt:AddLine(extra, 0.6, 0.75, 1, true) end
  tt:Show()
end

function Theme.hideTooltip()
  local W = Journal.Widgets
  if W and W.hideItemTip then W.hideItemTip() end
  if GameTooltip then GameTooltip:Hide() end
end

Theme.TEX.stroke = MEDIA .. "Stroke"
Theme.TEX.grave = MEDIA .. "Grave"

Theme.TEX.arrow = MEDIA .. "Arrow"

-- Diary kit (journal/widgets/Diary.lua). Handwriting Caveat Bold (SIL OFL, Media/Fonts/) only for sticker buttons and section heads;
-- if SetFont fails Diary uses Friz. Textures from render-media.mjs (DIARY_*). HAS_DIARY = true once the TGAs exist (a test keeps
-- it equal to the Media folder); false = colour-block fallback.
Theme.FONT.hand = MEDIA .. "Fonts\\Caveat-Bold.ttf"
-- Card text (welcome / rest / plan cards, journal/Toast.lua): Spectral (SIL OFL, Media/Fonts/Spectral/). Title and head SemiBold,
-- lines Regular. If the client cannot load the file, Toast falls back to FONT.title / FONT.text (Toast.cardFont).
Theme.FONT.card = MEDIA .. "Fonts\\Spectral\\Spectral-Regular.ttf"
Theme.FONT.cardTitle = MEDIA .. "Fonts\\Spectral\\Spectral-SemiBold.ttf"
-- Narrator portraits of the welcome card (Media/Narrator_<id>.tga, 512 x 512, scripts/render-media.mjs NARRATOR_*): circle centre
-- at (256 | 250), radius 176 px of the texture; the figure may reach out of the circle above. Order = options menu.
Theme.NARRATORS = { "human", "dwarf", "nightelf", "gnome", "orc", "undead", "tauren", "troll", "skyborne" }
Theme.NARRATOR_TEX = { size = 512, cx = 256, cy = 250, r = 176 }
Theme.HAS_NARRATORS = true
for _, id in ipairs(Theme.NARRATORS) do Theme.TEX["narrator_" .. id] = MEDIA .. "Narrator_" .. id end
function Theme.narratorTex(id)
  return type(id) == "string" and Theme.TEX["narrator_" .. id] or nil
end
Theme.TEX.diarySticker = MEDIA .. "DiarySticker"
Theme.TEX.diaryTape = MEDIA .. "DiaryTape"
Theme.TEX.diaryCircle = MEDIA .. "DiaryCircle"
Theme.TEX.diaryStroke = MEDIA .. "DiaryStroke"
Theme.TEX.diaryMarks = MEDIA .. "DiaryMarks"
Theme.HAS_DIARY = true
-- Sticker base 128 x 64: caps left/right cap px each (contain the rounding), border (die-cut edge + shadow) pad px per side
Theme.DIARY_STICKER = { w = 128, h = 64, cap = 32, pad = { l = 6, r = 6, t = 5, b = 9 } }
-- Mark atlas (Media/DiaryMarks.tga 256 x 256, 4 x 4 cells of 64 px), order = DIARY_ATLAS.ids in render-media.mjs
Theme.DIARY_ATLAS = { size = 256, cell = 64, box = 0, tick = 1, badgeGold = 2, badgeRed = 3, arrow = 4, back = 5, prev = 6,
  next = 7, down = 8 }
function Theme.diaryCoords(name)
  local a = Theme.DIARY_ATLAS
  local i = type(name) == "string" and name ~= "size" and name ~= "cell" and a[name] or nil
  if type(i) ~= "number" then return nil end
  local n = a.size / a.cell
  local col, row = i % n, math.floor(i / n)
  local e = 0.5 / a.size
  return col / n + e, (col + 1) / n - e, row / n + e, (row + 1) / n - e
end

-- Book grid shared by all pages. Page pixels 538 x 666 (x from the page's left edge, y from the top of the double page; map page:
-- right page + 538, Theme.gridX(side, ..., true)); docs/raster.md. Margins outer 92, inner 44; text block 402 (12 columns of 28, gap 6).
-- Slots (y = top): head 36 (rule 52), title 66, ctrl 118 (h 24), body 150..574, foot 580 (h 26). Lines: table 22, body 18, dense 16.
-- Font sizes: xs 11 (minimum), s 12, m 14, l 18, xl 28.
Theme.GRID = {
  pageW = 538, pageH = 666,
  outer = 92, inner = 44, top = 66, bottom = 606,
  L = { x = 92, w = 402 },
  R = { x = 44, w = 402 },
  cols = 12, col = 28, gutter = 6,
  head = { y = 36, size = 11, ruleGap = 16 },
  section = { before = 18, after = 8, h = 20 },
  line = { row = 22, text = 18, dense = 16 },
  size = { xs = 11, s = 12, m = 14, l = 18, xl = 28 },
  slots = {
    back = { y = 29, h = 24 },
    title = { y = 66 },
    ctrl = { y = 118, h = 24 },
    ctrlTop = { y = 66, h = 24 },
    body = { y = 150, bottom = 574 },
    bodyTop = { y = 98 },
    foot = { y = 580, h = 26 },
  },
}

function Theme.gridX(side, col, span, spread)
  local G = Theme.GRID
  local s = (side == "R") and G.R or G.L
  col = math.max(1, math.min(G.cols, math.floor(tonumber(col) or 1)))
  span = math.max(1, math.min(G.cols - col + 1, math.floor(tonumber(span) or (G.cols - col + 1))))
  local x = s.x + (col - 1) * (G.col + G.gutter)
  local w = span * G.col + (span - 1) * G.gutter
  if spread and side == "R" then x = x + G.pageW end
  return x, w
end

function Theme.gridSlot(side, name, spread)
  local G = Theme.GRID
  local sl = G.slots[name]
  if not sl then return nil end
  local x, w = Theme.gridX(side, 1, G.cols, spread)
  local h = sl.h or ((sl.bottom and (sl.bottom - sl.y)) or 0)
  return x, sl.y, w, h
end

function Theme.gridFoot(side, spread)
  local x, y, w = Theme.gridSlot(side, "foot", spread)
  if side == "R" then return "TOPLEFT", x, y end
  return "TOPRIGHT", x + w, y
end

-- Note pad (todo tracker, quick note): light note pad (Media/TodoPad.tga 512 x 1024, TODO_PAD in render-media.mjs). Stretched
-- vertically in three pieces in game so the tape (top) and the torn bottom edge do not distort: top/bottom = fixed pieces
-- (v range), mid = stretched part between. The pieces join seamlessly; the width is never distorted.
Theme.TEX.todoPad = MEDIA .. "TodoPad"
Theme.HAS_TODO_PAD = true
Theme.TODO_PAD_SLICE = { top = { 0, 0.12 }, mid = { 0.12, 0.88 }, bottom = { 0.88, 1 }, aspect = 2120 / 1560, margin = 0.115,
  tab = { 0.395, 0.605, 0.075 }, grip = { 0.92, 0.945 }, edge = 0.05, paper = 0.975 }
-- Note pad marks (Media/TodoMarks.tga 128 x 32, white, tinted): lock closed/open, grip
Theme.TEX.todoMarks = MEDIA .. "TodoMarks"
Theme.HAS_TODO_MARKS = true
Theme.TODO_MARKS = { locked = 0, unlocked = 1, grip = 2 }
function Theme.todoMarkCoords(name)
  local i = Theme.TODO_MARKS[name]
  if not i then return nil end
  return i / 4, (i + 1) / 4, 0, 1
end
