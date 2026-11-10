-- Map: Blizzard map art (continent or zone with uncovered overlays, sepia-tinted or original colours), red route with glow,
-- dashed flights, markers with tooltips, margin notes, location dot and gap marks. Canvas zoom: everything is re-set through one
-- transformation (view coordinates -> pixels); lines are clipped at the map frame (Liang-Barsky), never clamped.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Map = {}
Journal.Map = Map

local floor, ceil, sqrt, max, min, huge = math.floor, math.ceil, math.sqrt, math.max, math.min, math.huge
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

Map.ROUTE_WIDTH = 1.4
Map.GLOW_WIDTH = 7
Map.GLOW = false
Map.FLIGHT_WIDTH = 1.2
Map.DASH = 16
Map.LINE_POOL_MAX = 1000
Map.OUTLINES_MAX = 12
Map.SAFE_MARGIN = 12
Map.FIT_PAD = 22
Map.NOTE_MAX = 3
Map.NOTE_SIZE = 16
Map.NOTE_GAP = 10
Map.SAFE_MIN = 80
Map.ZOOM_STEP = 1.25
Map.MIN_SPAN = 0.08
Map.DRAG_START = 4
Map.DRAG_FPS = 40
Map.DOUBLE_CLICK = 0.35
Map.TILE_TINT = { 1.0, 0.93, 0.78 }
Map.TILE_ALPHA = 0.6
Map.ORIGINAL_ALPHA = 0.95
Map.GRAIN_ALPHA = 0.18
-- Fraction of the mask edge by which the art mask (Media/MapFade) exceeds the map art on each side (0 = the fade lies directly
-- on the art).
Map.ART_INSET = 0

-- Transformation fitting the focus rect (view coordinates) with the same aspect into the W x H area minus inset. artW/artH:
-- map pixels per view unit (map art) or aspect. Result T: px = T.ox + vx * T.sx, py = T.oy + vy * T.sy
function Map.fit(focus, artW, artH, W, H, inset)
  inset = inset or { l = 0, t = 0, r = 0, b = 0 }
  local x0, x1, y0, y1 = focus.x0, focus.x1, focus.y0, focus.y1
  if not (x1 > x0) then x0, x1 = x0 - 0.01, x0 + 0.01 end
  if not (y1 > y0) then y0, y1 = y0 - 0.01, y0 + 0.01 end
  local aw, ah = max(W - inset.l - inset.r, 10), max(H - inset.t - inset.b, 10)
  local fw, fh = (x1 - x0) * artW, (y1 - y0) * artH
  local s = min(aw / fw, ah / fh)
  local sx, sy = artW * s, artH * s
  local ox = inset.l + (aw - fw * s) / 2 - x0 * sx
  local oy = inset.t + (ah - fh * s) / 2 - y0 * sy
  return { sx = sx, sy = sy, ox = ox, oy = oy, W = W, H = H, scale = s }
end

function Map.toPixel(T, vx, vy)
  return T.ox + vx * T.sx, T.oy + vy * T.sy
end

function Map.toView(T, px, py)
  return (px - T.ox) / T.sx, (py - T.oy) / T.sy
end

local function copyT(T)
  return { sx = T.sx, sy = T.sy, ox = T.ox, oy = T.oy, W = T.W, H = T.H, scale = T.scale }
end

-- Free area (safe area): largest rect in W x H touching none of the obstacles (note, title, pills, timeline; each { x0, y0,
-- x1, y1 } in area pixels, distance margin), scored by how large a focus of aspect aspect gets inside. -> inset { l, t, r, b }
function Map.safeInset(W, H, obstacles, aspect, margin)
  margin = margin or Map.SAFE_MARGIN
  aspect = (aspect and aspect > 0) and aspect or 1
  local obs = {}
  for _, o in ipairs(obstacles or {}) do
    if o.x1 > 0 and o.y1 > 0 and o.x0 < W and o.y0 < H and o.x1 > o.x0 and o.y1 > o.y0 then
      obs[#obs + 1] = { x0 = o.x0 - margin, y0 = o.y0 - margin, x1 = o.x1 + margin, y1 = o.y1 + margin }
    end
  end
  local ls, rs, ts, bs = { 0 }, { W }, { 0 }, { H }
  for _, o in ipairs(obs) do
    ls[#ls + 1], rs[#rs + 1], ts[#ts + 1], bs[#bs + 1] = o.x1, o.x0, o.y1, o.y0
  end
  local best, bestScore, bestArea = nil, -1, -1
  for _, l in ipairs(ls) do
    for _, r in ipairs(rs) do
      if l >= 0 and r <= W and r - l >= Map.SAFE_MIN then
        for _, t in ipairs(ts) do
          for _, b in ipairs(bs) do
            if t >= 0 and b <= H and b - t >= Map.SAFE_MIN then
              local free = true
              for _, o in ipairs(obs) do
                if l < o.x1 and r > o.x0 and t < o.y1 and b > o.y0 then free = false break end
              end
              if free then
                local score = min(r - l, (b - t) * aspect)
                local area = (r - l) * (b - t)
                if score > bestScore + 0.5 or (score > bestScore - 0.5 and area > bestArea) then
                  best, bestScore, bestArea = { l = l, t = t, r = W - r, b = H - b }, score, area
                end
              end
            end
          end
        end
      end
    end
  end
  return best or { l = 0, t = 0, r = 0, b = 0 }
end

-- Zoom limits for the base view: weakest zoom = the whole map (base.minSx, set by Map.render; zooming out always reaches the
-- full view even if the base view is zoomed on the route or a chapter), strongest = Map.MIN_SPAN of the width still visible.
-- -> minSx, maxSx
function Map.zoomLimits(base)
  local maxSx = base.W / Map.MIN_SPAN
  local lo = min(base.sx, base.minSx or base.sx)
  return lo, max(base.sx, maxSx)
end

function Map.panBox(base, focus)
  local cx, cy = Map.toView(base, base.W / 2, base.H / 2)
  local x0, y0, x1, y1 = min(0, cx), min(0, cy), max(1, cx), max(1, cy)
  if focus then
    x0, y0, x1, y1 = min(x0, focus.x0), min(y0, focus.y0), max(x1, focus.x1), max(y1, focus.y1)
  end
  return { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
end

function Map.clampView(T, base, box)
  local R = copyT(T)
  local lo, hi = Map.zoomLimits(base)
  local k = 1
  if R.sx < lo then k = lo / R.sx elseif R.sx > hi then k = hi / R.sx end
  if k ~= 1 then
    local vx, vy = Map.toView(R, R.W / 2, R.H / 2)
    R.sx, R.sy = R.sx * k, R.sy * k
    R.scale = (R.scale or 1) * k
    R.ox, R.oy = R.W / 2 - vx * R.sx, R.H / 2 - vy * R.sy
  end
  if box then
    local cx, cy = Map.toView(R, R.W / 2, R.H / 2)
    local nx, ny = max(box.x0, min(box.x1, cx)), max(box.y0, min(box.y1, cy))
    R.ox, R.oy = R.W / 2 - nx * R.sx, R.H / 2 - ny * R.sy
  end
  return R
end

-- Zoom around the point (px, py) by factor f within the limits; the map point under the cursor stays put.
function Map.zoomAt(T, base, box, f, px, py)
  local lo, hi = Map.zoomLimits(base)
  local nsx = max(lo, min(hi, T.sx * f))
  local k = nsx / T.sx
  local R = copyT(T)
  local vx, vy = Map.toView(T, px, py)
  R.sx, R.sy, R.scale = T.sx * k, T.sy * k, (T.scale or 1) * k
  R.ox, R.oy = px - vx * R.sx, py - vy * R.sy
  return Map.clampView(R, base, box)
end

function Map.panBy(T, base, box, dx, dy)
  local R = copyT(T)
  R.ox, R.oy = T.ox + dx, T.oy + dy
  return Map.clampView(R, base, box)
end

function Map.isZoomed(T, base)
  if not T or not base then return false end
  return math.abs(T.sx / base.sx - 1) > 1e-3 or math.abs(T.ox - base.ox) > 0.5 or math.abs(T.oy - base.oy) > 0.5
end

function Map.clip(x1, y1, x2, y2, xmin, ymin, xmax, ymax)
  local dx, dy = x2 - x1, y2 - y1
  local t0, t1 = 0, 1
  local p = { -dx, dx, -dy, dy }
  local q = { x1 - xmin, xmax - x1, y1 - ymin, ymax - y1 }
  for i = 1, 4 do
    if p[i] == 0 then
      if q[i] < 0 then return nil end
    else
      local r = q[i] / p[i]
      if p[i] < 0 then
        if r > t1 then return nil end
        if r > t0 then t0 = r end
      else
        if r < t0 then return nil end
        if r < t1 then t1 = r end
      end
    end
  end
  return x1 + t0 * dx, y1 + t0 * dy, x1 + t1 * dx, y1 + t1 * dy
end

-- Tiles of a map layer (row by row like GetMapArtLayerTextures). Edge tiles get texcoords < 1.
-- -> { { file, x0, y0, x1, y1 (map pixels), u1, v1 } }
function Map.tiles(art)
  local out = {}
  if type(art) ~= "table" or not art.w or not art.tileW then return out end
  local cols, rows = ceil(art.w / art.tileW), ceil(art.h / art.tileH)
  local i = 0
  for row = 0, rows - 1 do
    for col = 0, cols - 1 do
      i = i + 1
      local file = art.files[i]
      if file then
        local w = min(art.tileW, art.w - col * art.tileW)
        local h = min(art.tileH, art.h - row * art.tileH)
        out[#out + 1] = { file = file, x0 = col * art.tileW, y0 = row * art.tileH, x1 = col * art.tileW + w,
          y1 = row * art.tileH + h, u1 = w / art.tileW, v1 = h / art.tileH }
      end
    end
  end
  return out
end

function Map.glow(segs, group)
  local out = {}
  group = max(1, group or 6)
  local cur, n = nil, 0
  for _, s in ipairs(segs or {}) do
    if s.kind ~= "flight" then
      if cur and n < group and math.abs(cur.x2 - s.x1) < 1e-9 and math.abs(cur.y2 - s.y1) < 1e-9 then
        cur.x2, cur.y2, cur.p = s.x2, s.y2, s.p
        n = n + 1
      else
        if cur then out[#out + 1] = cur end
        cur, n = { x1 = s.x1, y1 = s.y1, x2 = s.x2, y2 = s.y2, p0 = s.p0, p = s.p }, 1
      end
    end
  end
  if cur then out[#out + 1] = cur end
  return out
end

-- Shortest drawn walking segment in pixels. Zoomed out, many of the up to 800 route segments are shorter than a pixel; a
-- texture line shorter than its thickness (1.4 px) is not drawn by the client and the route vanished. So connected short
-- walking pieces are merged into lines of at least Map.MIN_LINE_PX straight-line length.
Map.MIN_LINE_PX = 4

Map.MERGE_PATH_MAX = 3
function Map.mergeShort(list, minLen)
  minLen = minLen or Map.MIN_LINE_PX
  local out = {}
  local cur, path
  for _, s in ipairs(list or {}) do
    local len = sqrt((s.x2 - s.x1) ^ 2 + (s.y2 - s.y1) ^ 2)
    local open = false
    if cur and cur.kind ~= "flight" and path < minLen * Map.MERGE_PATH_MAX then
      open = sqrt((cur.x2 - cur.x1) ^ 2 + (cur.y2 - cur.y1) ^ 2) < minLen
    end
    if open and s.kind ~= "flight" and math.abs(cur.x2 - s.x1) < 0.01 and math.abs(cur.y2 - s.y1) < 0.01 then
      cur.x2, cur.y2, cur.p = s.x2, s.y2, s.p
      path = path + len
    else
      if cur then out[#out + 1] = cur end
      cur = { x1 = s.x1, y1 = s.y1, x2 = s.x2, y2 = s.y2, p0 = s.p0, p = s.p, kind = s.kind }
      path = len
    end
  end
  if cur then out[#out + 1] = cur end
  return out
end

-- Kill mini icons: bundled in a grid of Map.KILL_CELL pixel cells (in view coordinates: depends on zoom, not panning), one sword
-- per cell, count in the tooltip. Kills are scattered (2-4 % of the map width apart), so a minimum per cell dropped nearly all
-- swords. At most Map.KILL_MAX icons per image (richest cells first).
Map.KILL_CELL = 44
Map.KILL_MIN = 1
Map.KILL_MAX = 60
Map.LVUP_SIZE = 18
Map.TIP_ROWS = 6
Map.NAME_MAX = 32

function Map.bundleKills(kills, cellX, cellY, minCount)
  local out = {}
  if type(kills) ~= "table" or not kills.n or kills.n < 1 or not (cellX > 0) or not (cellY > 0) then return out end
  local cells = {}
  local vxs, vys, ps, ts = kills.vx, kills.vy, kills.p, kills.t
  for i = 1, kills.n do
    local cx, cy = floor(vxs[i] / cellX), floor(vys[i] / cellY)
    local key = (cx + 1048576) * 2097152 + (cy + 1048576)
    local b = cells[key]
    if not b then
      b = { n = 0, sx = 0, sy = 0, p0 = ps[i], t0 = ts[i], t1 = ts[i], cx = cx, cy = cy, cw = cellX, ch = cellY }
      cells[key] = b
      out[#out + 1] = b
    end
    b.n, b.sx, b.sy = b.n + 1, b.sx + vxs[i], b.sy + vys[i]
    if ps[i] < b.p0 then b.p0 = ps[i] end
    if ts[i] < b.t0 then b.t0 = ts[i] end
    if ts[i] > b.t1 then b.t1 = ts[i] end
  end
  local kept = {}
  for _, b in ipairs(out) do
    if b.n >= (minCount or Map.KILL_MIN) then
      b.vx, b.vy, b.sx, b.sy = b.sx / b.n, b.sy / b.n, nil, nil
      kept[#kept + 1] = b
    end
  end
  table.sort(kept, function(a, b)
    if a.p0 ~= b.p0 then return a.p0 < b.p0 end
    return a.vx < b.vx
  end)
  return kept
end

function Map.bundleDetail(kills, b)
  local out = {}
  if type(kills) ~= "table" or type(b) ~= "table" or not b.cw or not b.ch then return out end
  local vxs, vys, ids, lvs = kills.vx, kills.vy, kills.id, kills.lv
  local rows, order = {}, {}
  for i = 1, kills.n or 0 do
    if floor(vxs[i] / b.cw) == b.cx and floor(vys[i] / b.ch) == b.cy then
      local id = ids and ids[i] or false
      local key = id or "?"
      local r = rows[key]
      if not r then
        r = { id = id, n = 0 }
        rows[key] = r
        order[#order + 1] = r
      end
      r.n = r.n + 1
      local lv = lvs and lvs[i]
      if lv == -1 then
        r.boss = true
      elseif type(lv) == "number" and lv > 0 then
        if not r.lo or lv < r.lo then r.lo = lv end
        if not r.hi or lv > r.hi then r.hi = lv end
      end
    end
  end
  for _, r in ipairs(order) do out[#out + 1] = r end
  table.sort(out, function(a, c)
    if (a.id == false) ~= (c.id == false) then return c.id == false end
    if a.n ~= c.n then return a.n > c.n end
    return (a.id or 0) < (c.id or 0)
  end)
  return out
end

function Map.timeSpan(fmt, t0, t1)
  if type(fmt) ~= "function" then return nil end
  local ok, a = pcall(fmt, t0)
  if not ok or type(a) ~= "string" or a == "" then return nil end
  local ok2, b = pcall(fmt, t1)
  if not ok2 or type(b) ~= "string" or b == "" or b == a then return a end
  local d0, h0 = a:match("^(%d%d[%./]%d%d%.?) (%d%d:%d%d)$")
  local d1, h1 = b:match("^(%d%d[%./]%d%d%.?) (%d%d:%d%d)$")
  if d0 and d1 and d0 == d1 then return d0 .. " " .. h0 .. "–" .. h1 end
  return a .. " – " .. b
end

local MT = ns.Locale.ns("Map", {
  lvOne = " (St. %s)",
  lvRange = " (St. %s–%s)",
  lvBoss = " (St. ??)",
  killHead = "Erlegte Gegner:",
  unknownFoe = "Unbekannter Gegner",
  andMore = "und %s weitere",
  hoverHint = "Linksklick: Zonenkarte öffnen",
  gapHint = "Lücke in der Route: hier fehlen Positionsdaten.",
  pinHint = "Klicken: Notiz öffnen",
})

function Map.levelText(t)
  if t.lo then
    local lo, hi = floor(t.lo), floor(t.hi or t.lo)
    return lo == hi and MT("lvOne", lo) or MT("lvRange", lo, hi)
  end
  return t.boss and MT.lvBoss or ""
end

function Map.killTip(kills, b)
  local n = floor(b.n)
  local lines = { MT.killHead }
  local colors = { { 1, 0.82, 0 } }
  local S = ns.Sanitize
  local types, byName = {}, {}
  for _, r in ipairs(Map.bundleDetail(kills, b)) do
    local name
    if r.id and type(kills.name) == "function" then
      local ok, v = pcall(kills.name, r.id)
      if ok then name = v end
    end
    name = (type(name) == "string" and S and S.display and S.display(name, Map.NAME_MAX)) or MT.unknownFoe
    local t = byName[name]
    if not t then
      t = { name = name, n = 0, order = #types + 1 }
      byName[name] = t
      types[#types + 1] = t
    end
    t.n = t.n + r.n
    if r.lo and (not t.lo or r.lo < t.lo) then t.lo = r.lo end
    if r.hi and (not t.hi or r.hi > t.hi) then t.hi = r.hi end
    if r.boss then t.boss = true end
  end
  table.sort(types, function(x, y)
    if x.n ~= y.n then return x.n > y.n end
    return x.order < y.order
  end)
  local limit = #types > Map.TIP_ROWS and Map.TIP_ROWS - 1 or #types
  local shown = 0
  for i = 1, limit do
    local t = types[i]
    lines[#lines + 1] = (t.n > 1 and (floor(t.n) .. "× ") or "") .. t.name .. Map.levelText(t)
    colors[#lines] = { 0.9, 0.87, 0.78 }
    shown = shown + t.n
  end
  if limit < #types then
    lines[#lines + 1] = MT("andMore", n - shown)
    colors[#lines] = { 0.7, 0.68, 0.62 }
  end
  local span = Map.timeSpan(kills.stamp, b.t0, b.t1)
  if span then
    lines[#lines + 1] = span
    colors[#lines] = { 0.6, 0.6, 0.6 }
  end
  return lines, colors
end

function Map.pickBundles(list, maxCount)
  maxCount = maxCount or Map.KILL_MAX
  if #list <= maxCount then return list end
  local idx = {}
  for i = 1, #list do idx[i] = i end
  table.sort(idx, function(a, b)
    if list[a].n ~= list[b].n then return list[a].n > list[b].n end
    return a < b
  end)
  local keep = {}
  for i = 1, maxCount do keep[idx[i]] = true end
  local out = {}
  for i, b in ipairs(list) do if keep[i] then out[#out + 1] = b end end
  return out
end

function Map.bundlesFor(m, scene, T)
  local kills = scene and scene.kills
  if type(kills) ~= "table" or not kills.n or kills.n < 1 then return {} end
  local c = m.bundleCache
  if c and c.kills == kills and c.sx == T.sx and c.sy == T.sy then return c.list end
  local list = Map.bundleKills(kills, Map.KILL_CELL / T.sx, Map.KILL_CELL / T.sy)
  m.bundleCache = { kills = kills, sx = T.sx, sy = T.sy, list = list }
  m.bundleRuns = (m.bundleRuns or 0) + 1
  return list
end

function Map.countText(n)
  if n > 999 then return "999+" end
  return tostring(floor(n))
end

-- Kill mark size by kill count and zoom. Base size in the base view: single kill 16 px, bundle 18 to 20 px. It scales with
-- the square root of the zoom ratio to the base view, between x0.75 and x1.3 (single kill 12 to 21 px, bundle at most 26 px).
-- zoom = T.sx / base.sx (nil = base view)
Map.KILL_ZOOM_MIN = 0.75
Map.KILL_ZOOM_MAX = 1.3
function Map.killBase(n)
  if n >= 100 then return 20 end
  if n >= 10 then return 19 end
  if n >= 2 then return 18 end
  return 16
end
function Map.killSize(n, zoom)
  local f = 1
  if type(zoom) == "number" and zoom > 0 then f = max(Map.KILL_ZOOM_MIN, min(Map.KILL_ZOOM_MAX, math.sqrt(zoom))) end
  return Map.killBase(n) * f
end

-- Keep a kill mark clear of level-up icons ups = { { px, py } }: nudge to the nearest free spot (at most Map.KILL_NUDGE px;
-- away from the icon or the eight compass directions), else drop it. The crossed swords have transparent corners, so
-- Map.KILL_CLEAR (< 1) of half the edge sum is enough. -> x, y (nudged) or nil (hide)
Map.KILL_CLEAR = 0.85
Map.KILL_NUDGE = 16
local DIRS = { { 1, 0 }, { 0.7071, -0.7071 }, { 0, -1 }, { -0.7071, -0.7071 }, { -1, 0 }, { -0.7071, 0.7071 }, { 0, 1 }, { 0.7071, 0.7071 } }
function Map.avoidLevelUps(px, py, size, ups)
  if not ups or #ups == 0 then return px, py end
  local function needOf(u) return (size + (u[3] or Map.LVUP_SIZE)) / 2 * Map.KILL_CLEAR end
  local function clear(x, y)
    for _, u in ipairs(ups) do
      local dx, dy = x - u[1], y - u[2]
      if math.sqrt(dx * dx + dy * dy) < needOf(u) - 0.01 then return false end
    end
    return true
  end
  if clear(px, py) then return px, py end
  local cands = {}
  for _, u in ipairs(ups) do
    local dx, dy = px - u[1], py - u[2]
    local d = math.sqrt(dx * dx + dy * dy)
    local need = needOf(u)
    if d < need - 0.01 then
      if d > 1e-6 then cands[#cands + 1] = { u[1] + dx / d * need, u[2] + dy / d * need } end
      for _, v in ipairs(DIRS) do cands[#cands + 1] = { u[1] + v[1] * need, u[2] + v[2] * need } end
    end
  end
  local bx, by, bs = nil, nil, Map.KILL_NUDGE + 1e-6
  for _, c in ipairs(cands) do
    local sx, sy = c[1] - px, c[2] - py
    local s = math.sqrt(sx * sx + sy * sy)
    if s < bs - 1e-9 and clear(c[1], c[2]) then bx, by, bs = c[1], c[2], s end
  end
  return bx, by
end

Map.HOVER_SCALE = 1.15
Map.SHADOW_ALPHA = 0.5

-- Zone hover on the continent map (like Blizzard's world map): highlighted zone area + tooltip with the zone name, left click
-- jumps into the zone. Queried only while the mouse is over the map, only after movement and at most every
-- Map.HOVER_INTERVAL seconds.
Map.HOVER_INTERVAL = 0.05
Map.HIGHLIGHT_ALPHA = 0.5  -- like Blizzard's MapHighlightPinTemplate (blend "ADD", alpha 0.5)

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function plainNum(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == huge or v == -huge then return nil end
  return v
end

-- Highlighted zone area under (vx, vy) on map mapID (0..1), shaped like Blizzard's MapHighlightDataProvider results: fileDataID,
-- atlasID, texPercentageX/Y, textureX/Y, scrollChildX/Y (size and top left normalised to the map, texPercentage = used share
-- of the texture). All values are unchecked foreign data: secret, missing or implausible -> nil (tooltip only).
function Map.highlightAt(mapID, vx, vy)
  local api = type(C_Map) == "table" and C_Map.GetMapHighlightInfoAtPosition or nil
  if type(api) ~= "function" or not plainNum(mapID) or not plainNum(vx) or not plainNum(vy) then return nil end
  local ok, fid, atlas, tx, ty, w, h, x0, y0 = pcall(api, mapID, vx, vy)
  if not ok then return nil end
  fid = plainNum(fid)
  if fid and fid <= 0 then fid = nil end
  if isSecret(atlas) or type(atlas) ~= "string" or atlas == "" then atlas = nil end
  if not fid and not atlas then return nil end
  w, h, x0, y0 = plainNum(w), plainNum(h), plainNum(x0), plainNum(y0)
  if not (w and h and x0 and y0) or w <= 0 or h <= 0 or w > 4 or h > 4 then return nil end
  tx, ty = plainNum(tx), plainNum(ty)
  if not tx or tx <= 0 or tx > 1 then tx = 1 end
  if not ty or ty <= 0 or ty > 1 then ty = 1 end
  return { file = (not atlas) and fid or nil, atlas = atlas, x0 = x0, y0 = y0, w = w, h = h, u1 = tx, v1 = ty }
end

-- Player arrow (location and playback head): the painted gold arrow Media/MapCurrent.tga (Theme.HAS_MAP_CURRENT; cell 11 of
-- the icon sheet), rotated to the heading. The file points up (north). Without it the client's minimap arrow (ARROW_TEX); if
-- that is missing too, the old dot.
Map.ARROW_TEX = "Interface\\Minimap\\MinimapArrow"
Map.ARROW_SIZE = 24
-- Zoom dependent: base size per map kind (continent 15 px, zone 20 px), scaled by the square root of the zoom ratio to the
-- base view (like the kill marks), between x0.9 and x1.6, never above ARROW_SIZE.
Map.ARROW_BASE = { continent = 15, zone = 20 }
Map.ARROW_ZOOM_MIN, Map.ARROW_ZOOM_MAX = 0.9, 1.6
function Map.arrowSize(mode, zoom)
  local f = 1
  if type(zoom) == "number" and zoom > 0 then f = max(Map.ARROW_ZOOM_MIN, min(Map.ARROW_ZOOM_MAX, math.sqrt(zoom))) end
  return min(Map.ARROW_SIZE, (Map.ARROW_BASE[mode] or Map.ARROW_BASE.zone) * f)
end
Map.ARROW_MIN_STEP = 2     -- shorter pieces give no heading (the arrow would jitter); the last useful one counts

-- Does the arrow texture exist in the client? GetFileIDFromPath only knows existing files (nil = unknown); if the function
-- itself is missing, assume the file exists (Retail 12.x has MinimapArrow).
function Map.arrowAvailable()
  local fn = _G and _G.GetFileIDFromPath
  if type(fn) ~= "function" then return true end
  local ok, id = pcall(fn, Map.ARROW_TEX)
  if not ok then return true end
  return id ~= nil
end

-- Rotation angle (radians for SetRotation: positive = counter-clockwise) for a segment in map pixels (y grows downward). The
-- arrow in the file points up: north 0, west +pi/2, east -pi/2, south +-pi. nil if the segment is shorter than Map.ARROW_MIN_STEP.
function Map.headingAngle(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  if dx * dx + dy * dy < Map.ARROW_MIN_STEP * Map.ARROW_MIN_STEP then return nil end
  return atan2(-dx, -dy)
end

function Map.headingAt(segs, idx)
  if type(segs) ~= "table" then return nil end
  for i = min(idx or #segs, #segs), 1, -1 do
    local s = segs[i]
    local a = Map.headingAngle(s.x1, s.y1, s.x2, s.y2)
    if a then return a end
  end
  return nil
end

local function styleHead(m, tex, Theme)
  if m.arrow then
    tex:SetTexture(Theme.HAS_MAP_CURRENT and Theme.TEX.mapCurrent or Map.ARROW_TEX)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetSize(Map.ARROW_SIZE, Map.ARROW_SIZE)
  else
    tex:SetTexture(Theme.TEX.markers)
    tex:SetTexCoord(Theme.atlasCoords(Theme.ATLAS.current))
    tex:SetSize(Theme.MARKER_SIZE.current, Theme.MARKER_SIZE.current)
  end
end

local function turnHead(m, tex, key, angle)
  if not m.arrow then return end
  if angle then m[key] = angle end
  if tex.SetRotation then tex:SetRotation(m[key] or 0) end
end

local function lerp(a, b, f) return a + (b - a) * f end

local Theme, View

local function deps()
  Theme, View = Journal.Theme, Journal.View
end

function Map.setKillArt(icon, shadow)
  deps()
  local kind = Theme.HAS_MAP_KILL and "mapKill" or "sword"
  for _, t in ipairs({ icon, shadow }) do
    if kind == "mapKill" then
      t:SetTexture(Theme.TEX.mapKill)
    else
      t:SetTexture(Theme.HAS_SWORD_ICON and Theme.TEX.swordIcon or Theme.TEX.sword)
    end
    t:SetTexCoord(0, 1, 0, 1)
  end
  icon:SetVertexColor(1, 1, 1, 1)
  shadow:SetVertexColor(0, 0, 0, Map.SHADOW_ALPHA)
  return kind
end

function Map.sizeKillArt(b, hover)
  local s = (b.baseSize or b:GetWidth() or 22) * (hover and Map.HOVER_SCALE or 1)
  b.icon:SetSize(s, s)
  if b.shadow then b.shadow:SetSize(s, s) end
end

local function newMarker(m)
  local b = CreateFrame("Button", nil, m.markerLayer)
  b:SetSize(22, 22)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(b)
  icon:SetTexture(Theme.TEX.markers)
  b.icon = icon
  local label = b:CreateFontString(nil, "OVERLAY")
  Theme.font(label, "text", 10, Theme.C.ink)
  label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.label = label
  local pulse = b:CreateTexture(nil, "BACKGROUND")
  pulse:SetPoint("CENTER", b, "CENTER")
  pulse:SetTexture(Theme.TEX.markers)
  pulse:SetTexCoord(Theme.atlasCoords(Theme.ATLAS.pulse))
  pulse:Hide()
  local ag = pulse:CreateAnimationGroup()
  local sc = ag:CreateAnimation("Scale")
  sc:SetScaleFrom(1, 1)
  sc:SetScaleTo(2.6, 2.6)
  sc:SetDuration(2.6)
  local al = ag:CreateAnimation("Alpha")
  al:SetFromAlpha(0.9)
  al:SetToAlpha(0)
  al:SetDuration(2.6)
  ag:SetLooping("REPEAT")
  b.pulse, b.pulseAnim = pulse, ag
  b:SetScript("OnEnter", function(self)
    if self.tip then Theme.tooltip(self, self.tip, self.extra) end
  end)
  b:SetScript("OnLeave", Theme.hideTooltip)
  return b
end

Map.LEVEL_MARK_SIZE = 18
Map.MILESTONE_MARK_SIZE = 26
local function isLevelKind(kind) return kind == "level" or kind == "milestone" end

local function setMarker(m, b, kind, px, py, entry)
  local size = Theme.MARKER_SIZE[kind] or 22
  local lvl = isLevelKind(kind)
  if lvl then size = (kind == "milestone") and Map.MILESTONE_MARK_SIZE or Map.LEVEL_MARK_SIZE end
  b:SetSize(size, size)
  b:ClearAllPoints()
  b:SetPoint("CENTER", m.content, "TOPLEFT", px, -py)
  b.markKind = kind
  local painted = Theme.HAS_MAP_ICONS and Theme.MAP_ICONS[kind] ~= nil
  if painted then
    b.icon:SetTexture(Theme.TEX.mapIcons)
    b.icon:SetTexCoord(Theme.mapIconCoords(kind))
    b.icon:SetVertexColor(1, 1, 1, 1)
  else
    b.icon:SetTexture(Theme.TEX.markers)
    b.icon:SetTexCoord(Theme.atlasCoords(lvl and Theme.ATLAS.level or (Theme.ATLAS[kind] or Theme.ATLAS.level)))
    if lvl then Theme.color(b.icon, Theme.C.gold, 1) else b.icon:SetVertexColor(1, 1, 1, 1) end
  end
  if b.SetFrameLevel and m.markerLayer.GetFrameLevel then
    b:SetFrameLevel(m.markerLayer:GetFrameLevel() + (lvl and 2 or 1))
  end
  local lv = entry and entry.level
  if lvl and lv and not painted then
    b.label:SetText(tostring(floor(lv)))
    Theme.font(b.label, "text", kind == "milestone" and 10 or 9, Theme.C.ink)
    b.label:Show()
  else
    b.label:SetText("")
    b.label:Hide()
  end
  local animate = kind == "milestone" and not m.reduceMotion
  if animate then
    b.pulse:SetSize(size, size)
    b.pulse:Show()
    b.pulseAnim:Play()
  else
    b.pulseAnim:Stop()
    b.pulse:Hide()
  end
end

local function newMini(m, kind)
  local b = CreateFrame("Button", nil, kind == "kills" and m.killLayer or m.miniLayer)
  b:SetSize(14, 14)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(b)
  icon:SetTexture(Theme.TEX.markers)
  local label = b:CreateFontString(nil, "OVERLAY")
  label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.icon, b.label, b.kind = icon, label, kind
  if kind == "kills" then
    local shadow = b:CreateTexture(nil, "ARTWORK", nil, -1)
    b.shadow = shadow
    b.artKind = Map.setKillArt(icon, shadow)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    shadow:ClearAllPoints()
    shadow:SetPoint("CENTER", b, "CENTER", 1, -1.5)
    Theme.font(label, "text", 8, Theme.C.ink)
  else
    if Theme.HAS_MAP_ICONS then
      icon:SetTexture(Theme.TEX.mapIcons)
      icon:SetTexCoord(Theme.mapIconCoords("level"))
      icon:SetVertexColor(1, 1, 1, 1)
      label:Hide()
    else
      icon:SetTexCoord(Theme.atlasCoords(Theme.ATLAS.level))
      Theme.color(icon, Theme.C.gold, 1)
    end
    Theme.font(label, "text", 9, Theme.C.ink)
  end
  b:SetScript("OnEnter", function(self)
    if self.kind == "kills" then Map.sizeKillArt(self, true) end
    Map.miniTip(m, self)
  end)
  b:SetScript("OnLeave", function(self)
    if self.kind == "kills" then Map.sizeKillArt(self, false) end
    Theme.hideTooltip()
  end)
  return b
end

function Map.miniTip(m, b)
  local d = b.data
  if not d then return end
  if b.kind == "kills" then
    local c = m.bundleCache
    local W = Journal.Widgets
    local ok, lines, colors = pcall(Map.killTip, c and c.kills, d)
    if ok and W and W.tip then W.tip(b, lines, colors) end
  elseif d.tip then
    Theme.tooltip(b, d.tip)
  end
end

local function acquire(pool, i, make)
  local o = pool[i]
  if not o then
    o = make()
    pool[i] = o
  end
  return o
end

local function hideFrom(pool, n)
  for i = n + 1, #pool do
    local o = pool[i]
    if o.Hide then o:Hide() end
    if o.pulseAnim then o.pulseAnim:Stop() end
    if o.fs then o.fs:Hide() o.num:Hide() o.pin:Hide() end
  end
end

local function cursorIn(m)
  local content = m.content
  local s = content:GetEffectiveScale() or 1
  local cx, cy = GetCursorPosition()
  local left, top = content:GetLeft(), content:GetTop()
  if not (cx and cy and left and top and s > 0) then return nil end
  return cx / s - left, top - cy / s
end

local function clock() return type(GetTime) == "function" and GetTime() or 0 end

local function stopPress(m)
  m.press = nil
  m.content:SetScript("OnUpdate", nil)
end

local function pressUpdate(m, dt)
  local pr = m.press
  if not pr then return stopPress(m) end
  if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
    return stopPress(m)
  end
  local x, y = cursorIn(m)
  if not x then return end
  local dx, dy = x - pr.x, y - pr.y
  if not pr.moved and (dx * dx + dy * dy) >= Map.DRAG_START * Map.DRAG_START then pr.moved = true end
  if not pr.moved then return end
  pr.acc = (pr.acc or 0) + (dt or 0)
  if pr.acc < 1 / Map.DRAG_FPS then return end
  pr.acc = 0
  Map.setView(m, Map.panBy(pr.T, m.base, m.box, dx, dy))
end

-- Zone hover: m.zoneAt(vx, vy) (set by Frame) -> { id, name, mapID } of the clickable zone or nil; m.hover = { zone, name,
-- hl } (hl = Map.highlightAt, normalised), m.hoverPos = last queried cursor position.

local function hideHover(m)
  if m.highlight then m.highlight:Hide() end
  if m.hoverTip then
    m.hoverTip = nil
    Theme.hideTooltip()
  end
  m.hover = nil
end

local function placeHighlight(m)
  local tex, hl = m.highlight, m.hover and m.hover.hl
  if not tex then return end
  if not hl or not m.T then
    tex:Hide()
    return
  end
  local x0, y0 = Map.toPixel(m.T, hl.x0, hl.y0)
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", m.content, "TOPLEFT", x0, -y0)
  tex:SetSize(max(1, hl.w * m.T.sx), max(1, hl.h * m.T.sy))
  tex:Show()
end

local function styleHighlight(tex, hl)
  if hl.atlas then
    tex:SetAtlas(hl.atlas, false)
  else
    tex:SetTexture(hl.file)
    tex:SetTexCoord(0, hl.u1, 0, hl.v1)
  end
  if tex.SetBlendMode then tex:SetBlendMode("ADD") end
  tex:SetVertexColor(1, 1, 1, 1)
  tex:SetAlpha(Map.HIGHLIGHT_ALPHA)
end

function Map.hoverUpdate(m, force)
  if not m.zoneAt or not m.T or (m.press and m.press.moved) then
    hideHover(m)
    return nil
  end
  local px, py = cursorIn(m)
  if not px or px < 0 or py < 0 or px > m.W or py > m.H then
    hideHover(m)
    m.hoverPos = nil
    return nil
  end
  local last = m.hoverPos
  if not force and not m.hoverDirty and last and last[1] == px and last[2] == py then return m.hover end
  local pos = last or {}
  pos[1], pos[2] = px, py
  m.hoverPos, m.hoverDirty = pos, false
  m.hoverQueries = (m.hoverQueries or 0) + 1
  local vx, vy = Map.toView(m.T, px, py)
  local ok, z = pcall(m.zoneAt, vx, vy)
  if not ok or type(z) ~= "table" or not z.id then
    hideHover(m)
    return nil
  end
  if m.hover and m.hover.zone == z.id then return m.hover end
  hideHover(m)
  local okH, hl = pcall(Map.highlightAt, z.mapID, vx, vy)
  m.hover = { zone = z.id, name = z.name, hl = (okH and type(hl) == "table") and hl or nil }
  if m.hover.hl and m.highlight and not pcall(styleHighlight, m.highlight, m.hover.hl) then m.hover.hl = nil end
  placeHighlight(m)
  local tt = GameTooltip
  if type(z.name) == "string" and z.name ~= "" and tt then
    m.hoverTip = pcall(function()
      tt:SetOwner(m.content, "ANCHOR_CURSOR")
      tt:AddLine(z.name, 1, 1, 1)
      tt:AddLine(MT.hoverHint, 0.6, 0.6, 0.6)
      tt:Show()
    end) or nil
  end
  return m.hover
end

-- Query tick only while the mouse is over the map (OnEnter/OnLeave) AND the continent view is shown (only there are zones
-- clickable; in the zone view no OnUpdate runs); at most one query per tick. Map.render re-syncs after every scene change.
function Map.hoverSync(m)
  if not m.hoverFrame then return end
  local want = m.mouseOver and m.zoneAt and m.scene and m.scene.mode == "continent" or false
  if want == (m.hoverRunning or false) then return end
  m.hoverRunning = want
  if not want then
    m.hoverFrame:SetScript("OnUpdate", nil)
    return
  end
  m.hoverAcc = Map.HOVER_INTERVAL
  m.hoverFrame:SetScript("OnUpdate", function(_, dt)
    m.hoverAcc = (m.hoverAcc or 0) + (dt or 0)
    if m.hoverAcc < Map.HOVER_INTERVAL then return end
    m.hoverAcc = 0
    Map.hoverUpdate(m)
  end)
end

function Map.hoverStart(m)
  m.mouseOver = true
  Map.hoverSync(m)
end

function Map.hoverStop(m)
  m.mouseOver = false
  Map.hoverSync(m)
  hideHover(m)
  m.hoverPos = nil
end

-- Create the map: viewport (clips at the image edge), content, markerLayer, noteLayer. No frame around the map; art and grain
-- fade into the paper at the sides (m.viewMask). Note texts stand in opts.notes (left page, width opts.noteW), only their red
-- number on the map. Wheel zooms around the cursor, drag pans, left click = m.onPoint, right/double click = m.onBack.
function Map.create(parent, x, y, w, h, opts)
  deps()
  opts = opts or {}
  local m = { W = w, H = h, tiles = {}, overlays = {}, lines = {}, glows = {}, outlines = {}, markers = {}, notes = {}, segs = {},
    glowSegs = {}, p = huge, killBtns = {}, lvupBtns = {}, minis = {}, pins = {} }
  local vp = CreateFrame("Frame", nil, parent)
  vp:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  vp:SetSize(w, h)
  vp:SetClipsChildren(true)
  m.viewport, m.x, m.y = vp, x, y
  local content = CreateFrame("Frame", nil, vp)
  content:SetPoint("TOPLEFT", vp, "TOPLEFT", 0, 0)
  content:SetSize(w, h)
  content:EnableMouse(true)
  content:EnableMouseWheel(true)
  m.content = content
  -- Soft edge on the map art itself (a mask that moves with it) and at the sides of the map area (m.viewMask, fixed). Without
  -- the mask API: hard edges, otherwise the same.
  local function mask()
    if type(content.CreateMaskTexture) ~= "function" then return nil end
    local ok, mk = pcall(content.CreateMaskTexture, content)
    if not ok or not mk then return nil end
    mk:SetTexture(Theme.TEX.mapFade, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    return mk
  end
  m.artMask = mask()
  if type(content.CreateMaskTexture) == "function" then
    local ok, mk = pcall(content.CreateMaskTexture, content)
    if ok and mk then
      mk:SetTexture(Theme.TEX.pageFade, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      mk:SetAllPoints(content)
      m.viewMask = mk
    end
  end
  local grain = content:CreateTexture(nil, "ARTWORK", nil, 1)
  grain:SetAllPoints(content)
  grain:SetTexture(Theme.TEX.grain, "REPEAT", "REPEAT")
  grain:SetHorizTile(true)
  grain:SetVertTile(true)
  grain:SetAlpha(Map.GRAIN_ALPHA)
  m.grain = grain
  if m.viewMask and grain.AddMaskTexture then pcall(grain.AddMaskTexture, grain, m.viewMask) end
  local hl = content:CreateTexture(nil, "BORDER")
  if hl.AddMaskTexture then
    if m.artMask then pcall(hl.AddMaskTexture, hl, m.artMask) end
    if m.viewMask then pcall(hl.AddMaskTexture, hl, m.viewMask) end
  end
  hl:Hide()
  m.highlight = hl
  m.hoverFrame = CreateFrame("Frame", nil, vp)
  m.liveFrame = CreateFrame("Frame", nil, vp)
  m.noteBox, m.noteW, m.noteMax = opts.notes, opts.noteW or 300, opts.noteMax
  local killLayer = CreateFrame("Frame", nil, content)
  killLayer:SetAllPoints(content)
  killLayer:SetFrameLevel(content:GetFrameLevel() + 1)
  m.killLayer = killLayer
  local miniLayer = CreateFrame("Frame", nil, content)
  miniLayer:SetAllPoints(content)
  miniLayer:SetFrameLevel(content:GetFrameLevel() + 2)
  m.miniLayer = miniLayer
  local layer = CreateFrame("Frame", nil, content)
  layer:SetAllPoints(content)
  layer:SetFrameLevel(content:GetFrameLevel() + 3)
  m.markerLayer = layer
  local noteLayer = CreateFrame("Frame", nil, content)
  noteLayer:SetAllPoints(content)
  noteLayer:SetFrameLevel(content:GetFrameLevel() + 4)
  m.noteLayer = noteLayer

  m.arrow = Theme.HAS_MAP_CURRENT or Map.arrowAvailable()
  m.current = layer:CreateTexture(nil, "OVERLAY")
  styleHead(m, m.current, Theme)
  m.current:Hide()
  m.walker = layer:CreateTexture(nil, "OVERLAY", nil, 1)
  styleHead(m, m.walker, Theme)
  m.walker:Hide()

  content:SetScript("OnMouseWheel", function(_, delta) Map.wheel(m, delta) end)
  content:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" or not m.T then return end
    local px, py = cursorIn(m)
    if not px then return end
    m.press = { x = px, y = py, T = m.T, moved = false }
    content:SetScript("OnUpdate", function(_, dt) pressUpdate(m, dt) end)
  end)
  content:SetScript("OnEnter", function() Map.hoverStart(m) end)
  content:SetScript("OnLeave", function() Map.hoverStop(m) end)
  content:SetScript("OnMouseUp", function(_, button)
    local pr = m.press
    stopPress(m)
    m.hoverDirty = true
    if button == "RightButton" then
      m.lastClick = nil
      local fn = m.onRight or m.onBack
      if fn then fn() end
      return
    end
    if button ~= "LeftButton" then return end
    local px, py = cursorIn(m)
    if pr and pr.moved then
      if px and m.base then Map.setView(m, Map.panBy(pr.T, m.base, m.box, px - pr.x, py - pr.y)) end
      m.lastClick = nil
      return
    end
    local t = clock()
    local last = m.lastClick
    if last and px and t - last.t <= Map.DOUBLE_CLICK and (px - last.x) ^ 2 + (py - last.y) ^ 2 < 64 then
      m.lastClick = nil
      if m.onBack then m.onBack() end
      return
    end
    m.lastClick = px and { t = t, x = px, y = py } or nil
    if m.onPoint and m.T and px then
      m.onPoint(Map.toView(m.T, px, py))
    end
  end)
  vp:SetScript("OnHide", function()
    stopPress(m)
    Map.hoverStop(m)
    if m.liveFrame then
      m.liveRunning = false
      m.liveFrame:SetScript("OnUpdate", nil)
    end
  end)
  return m
end

function Map.wheel(m, delta)
  if not m.T or not m.base or type(delta) ~= "number" or delta ~= delta or delta == 0 then return false end
  local px, py = cursorIn(m)
  if not px then px, py = m.W / 2, m.H / 2 end
  local sw = Map.zoomSwitchWheel(m, delta, px, py)
  if sw ~= nil then return sw end
  local before = m.T
  local T = Map.zoomAt(before, m.base, m.box, Map.ZOOM_STEP ^ max(-3, min(3, delta)), px, py)
  if math.abs(T.sx - before.sx) < 1e-9 and math.abs(T.ox - before.ox) < 1e-6 and math.abs(T.oy - before.oy) < 1e-6 then
    return false
  end
  Map.setView(m, T)
  return true
end

-- Zoom switch continent <-> zone: the wheel leads into the zone map under the cursor and back. Two pcall'd UI callbacks:
-- m.zoomTarget(dir, vx, vy) -> { a, b, c, d, artW, artH } or nil (a..d = Geo.affine(zone, continent); nil = no switch) and
-- m.zoomApply(dir, target). Hysteresis: in at most Map.SWITCH_ENTER of the continent width; out only below the zone's minimum zoom.
Map.SWITCH_ENTER = 0.3
Map.SWITCH_LEAVE = 0.4
Map.SWITCH_FIT = Map.SWITCH_LEAVE / Map.SWITCH_ENTER
Map.SWITCH_SHIFT = 1.5
Map.SWITCH_FADE = 0.25
Map.SWITCH_ALPHA = 0.2

local function finite(v) return plainNum(v) ~= nil end

-- Convert view T (outer coordinates, e.g. continent) into inner coordinates (zone), outer = a + b * inner (x) resp. c + d *
-- inner (y). Every point stays on its pixel. -> new transformation or nil (unusable)
function Map.viewToInner(T, a, b, c, d)
  if not (T and finite(a) and finite(b) and finite(c) and finite(d)) or b <= 0 or d <= 0 then return nil end
  local R = copyT(T)
  R.sx, R.sy = T.sx * b, T.sy * d
  R.ox, R.oy = T.ox + a * T.sx, T.oy + c * T.sy
  R.scale = (T.scale or 1) * b
  return R
end

function Map.viewToOuter(T, a, b, c, d)
  if not (T and finite(a) and finite(b) and finite(c) and finite(d)) or b <= 0 or d <= 0 then return nil end
  local R = copyT(T)
  R.sx, R.sy = T.sx / b, T.sy / d
  R.ox, R.oy = T.ox - a * R.sx, T.oy - c * R.sy
  R.scale = (T.scale or 1) / b
  return R
end

function Map.spanOf(T)
  if not T or not (T.sx and T.sx > 0) then return huge end
  return (T.W or 0) / T.sx
end

function Map.baseFor(m, focus, artW, artH, obstacles)
  local f = focus or { x0 = 0, x1 = 1, y0 = 0, y1 = 1 }
  local fw, fh = max((f.x1 - f.x0) * artW, 1e-6), max((f.y1 - f.y0) * artH, 1e-6)
  local inset = Map.safeInset(m.W, m.H, obstacles, fw / fh)
  local pad = (m.opts and m.opts.pad) or Map.FIT_PAD
  if m.W - inset.l - inset.r > 2 * pad + Map.SAFE_MIN and m.H - inset.t - inset.b > 2 * pad + Map.SAFE_MIN then
    inset = { l = inset.l + pad, t = inset.t + pad, r = inset.r + pad, b = inset.b + pad }
  end
  local base = Map.fit(f, artW, artH, m.W, m.H, inset)
  base.minSx = base.sx
  return base
end

function Map.shouldEnter(Tc, Tz, zoneBase)
  if not (Tc and Tz and zoneBase) then return false end
  if not (Map.spanOf(Tc) < Map.SWITCH_ENTER) then return false end
  local lo = Map.zoomLimits(zoneBase)
  if not (Tz.sx >= lo * Map.SWITCH_FIT) then return false end
  local C = Map.clampView(Tz, zoneBase, Map.panBox(zoneBase, { x0 = 0, x1 = 1, y0 = 0, y1 = 1 }))
  return math.abs(C.ox - Tz.ox) <= Map.SWITCH_SHIFT and math.abs(C.oy - Tz.oy) <= Map.SWITCH_SHIFT
    and math.abs(C.sx - Tz.sx) <= 1e-6 * Tz.sx
end

function Map.shouldLeave(want, zoneBase)
  if not (want and zoneBase) then return false end
  local lo = Map.zoomLimits(zoneBase)
  return want.sx < lo * (1 - 1e-9)
end

local function switchLog(msg)
  local C = ns.Core
  if C and C.coreError then pcall(C.coreError, "Reisejournal (Zoom-Wechsel): " .. tostring(msg)) end
end

local function askTarget(m, dir, vx, vy)
  if type(m.zoomTarget) ~= "function" then return nil end
  local ok, t = pcall(m.zoomTarget, dir, vx, vy)
  if not ok then
    switchLog(t)
    return nil
  end
  if type(t) ~= "table" or not finite(t.a) or not finite(t.b) or not finite(t.c) or not finite(t.d)
    or t.b <= 0 or t.d <= 0 then
    return nil
  end
  return t
end

local function applySwitch(m, dir, target, make)
  if type(m.zoomApply) ~= "function" then return false end
  local ok, res = pcall(m.zoomApply, dir, target)
  if not ok then
    switchLog(res)
    return false
  end
  if not res or not m.base then return false end
  local T = make()
  if T then Map.setView(m, Map.clampView(T, m.base, m.box)) end
  m.switchCount = (m.switchCount or 0) + 1
  return true
end

local function setFade(m, a)
  if m.viewport and m.viewport.SetAlpha then m.viewport:SetAlpha(a) end
end

function Map.switchFinish(m)
  local sw = m.switching
  m.switching = nil
  if m.switchFrame then m.switchFrame:SetScript("OnUpdate", nil) end
  setFade(m, 1)
  return sw ~= nil
end

-- K2 zone change while replaying: the new map (already drawn) fades in from Map.SWITCH_ALPHA over Map.SWITCH_FADE s. With
-- reduced motion (or without the frame API) it just stands there. -> true if a fade runs
function Map.fadeIn(m)
  if m.reduceMotion or type(CreateFrame) ~= "function" or not m.viewport then
    setFade(m, 1)
    return false
  end
  if m.switching then return false end -- a zoom switch fades on its own
  if not m.fadeFrame then
    m.fadeFrame = CreateFrame("Frame", nil, m.viewport)
    if m.viewport.HookScript then
      m.viewport:HookScript("OnHide", function()
        if m.fadeFrame then m.fadeFrame:SetScript("OnUpdate", nil) end
        setFade(m, 1)
      end)
    end
  end
  local t = 0
  setFade(m, Map.SWITCH_ALPHA)
  m.fadeFrame:SetScript("OnUpdate", function(self, dt)
    t = t + (tonumber(dt) or 0)
    local f = min(1, t / Map.SWITCH_FADE)
    setFade(m, Map.SWITCH_ALPHA + (1 - Map.SWITCH_ALPHA) * f)
    if f >= 1 then self:SetScript("OnUpdate", nil) end
  end)
  return true
end

-- Perform the switch: with reduced motion (or without the frame API) hard, else fade out -> switch -> fade in. While fading
-- out the wheel does nothing; if the scene changes meanwhile (new data, toggle) the switch is dropped.
local function runSwitch(m, dir, target, make)
  if m.reduceMotion or type(CreateFrame) ~= "function" or not m.viewport then
    return applySwitch(m, dir, target, make)
  end
  if not m.switchFrame then
    m.switchFrame = CreateFrame("Frame", nil, m.viewport)
    if m.viewport.HookScript then
      m.viewport:HookScript("OnHide", function() Map.switchFinish(m) end)
    end
  end
  local half = Map.SWITCH_FADE / 2
  local sw = { phase = "out", t = 0, scene = m.scene }
  m.switching = sw
  m.switchFrame:SetScript("OnUpdate", function(_, dt)
    if m.switching ~= sw then return end
    sw.t = sw.t + (tonumber(dt) or 0)
    local f = min(1, sw.t / half)
    if sw.phase == "out" then
      setFade(m, 1 - (1 - Map.SWITCH_ALPHA) * f)
      if f >= 1 then
        if m.scene == sw.scene then applySwitch(m, dir, target, make) end
        sw.phase, sw.t = "in", 0
      end
    else
      setFade(m, Map.SWITCH_ALPHA + (1 - Map.SWITCH_ALPHA) * f)
      if f >= 1 then Map.switchFinish(m) end
    end
  end)
  setFade(m, 1)
  return true
end

function Map.zoomSwitchWheel(m, delta, px, py)
  local sw = m.switching
  if sw and sw.phase == "out" then return true end
  if sw or not m.zoomTarget or not m.zoomApply or not m.scene then return nil end
  local f = Map.ZOOM_STEP ^ max(-3, min(3, delta))
  local mode = m.scene.mode
  if mode == "continent" and delta > 0 then
    local Tc = Map.zoomAt(m.T, m.base, m.box, f, px, py)
    if not (Map.spanOf(Tc) < Map.SWITCH_ENTER) then return nil end
    local vx, vy = Map.toView(Tc, px, py)
    if not (finite(vx) and finite(vy)) then return nil end
    local t = askTarget(m, "in", vx, vy)
    if not t or not finite(t.artW) or not finite(t.artH) or t.artW <= 0 or t.artH <= 0 then return nil end
    local Tz = Map.viewToInner(Tc, t.a, t.b, t.c, t.d)
    local zb = Tz and Map.baseFor(m, nil, t.artW, t.artH, m.opts and m.opts.obstacles)
    if not Map.shouldEnter(Tc, Tz, zb) then return nil end
    Map.setView(m, Tc)
    runSwitch(m, "in", t, function() return Map.viewToInner(Tc, t.a, t.b, t.c, t.d) end)
    return true
  elseif mode == "zone" and delta < 0 then
    local want = copyT(m.T)
    local vx, vy = Map.toView(m.T, px, py)
    want.sx, want.sy, want.scale = m.T.sx * f, m.T.sy * f, (m.T.scale or 1) * f
    want.ox, want.oy = px - vx * want.sx, py - vy * want.sy
    if not (finite(want.ox) and finite(want.oy)) or not Map.shouldLeave(want, m.base) then return nil end
    local t = askTarget(m, "out")
    if not t then return nil end
    runSwitch(m, "out", t, function() return Map.viewToOuter(want, t.a, t.b, t.c, t.d) end)
    return true
  end
  return nil
end

local function line(m, pool, i, sub)
  return acquire(pool, i, function()
    return m.content:CreateLine(nil, "ARTWORK", nil, sub)
  end)
end

local function drawLine(m, l, x1, y1, x2, y2)
  local cp = m.clipPx
  local a, b, c, d
  if cp then
    a, b, c, d = Map.clip(x1, y1, x2, y2, cp.x0, cp.y0, cp.x1, cp.y1)
  else
    a, b, c, d = Map.clip(x1, y1, x2, y2, 0, 0, m.W, m.H)
  end
  if not a then
    l:Hide()
    return false
  end
  l:SetStartPoint("TOPLEFT", m.content, a, -b)
  l:SetEndPoint("TOPLEFT", m.content, c, -d)
  l:Show()
  return true, sqrt((c - a) ^ 2 + (d - b) ^ 2)
end

local function styleRoute(l, kind)
  if kind == "flight" then
    l:SetTexture(Theme.TEX.dash, "REPEAT", "CLAMP")
    Theme.color(l, Theme.C.blue, 1)
    l:SetThickness(Map.FLIGHT_WIDTH)
  else
    l:SetColorTexture(Theme.C.red[1], Theme.C.red[2], Theme.C.red[3], 1)
    l:SetThickness(Map.ROUTE_WIDTH)
  end
end

function Map.tintTile(tex, original)
  tex:SetDesaturated(not original)
  if original then
    tex:SetVertexColor(1, 1, 1)
    tex:SetAlpha(Map.ORIGINAL_ALPHA)
  else
    tex:SetVertexColor(Map.TILE_TINT[1], Map.TILE_TINT[2], Map.TILE_TINT[3])
    tex:SetAlpha(Map.TILE_ALPHA)
  end
end

local function placeTiles(m, pool, list, art, T, original, sub, subTop)
  local n = 0
  for _, t in ipairs(list) do
    local x0, y0 = Map.toPixel(T, t.x0 / art.w, t.y0 / art.h)
    local x1, y1 = Map.toPixel(T, t.x1 / art.w, t.y1 / art.h)
    if x1 > 0 and y1 > 0 and x0 < m.W and y0 < m.H then
      n = n + 1
      local tex = acquire(pool, n, function() return m.content:CreateTexture(nil, "BACKGROUND", nil, sub) end)
      if subTop and tex.SetDrawLayer then tex:SetDrawLayer("BACKGROUND", t.top and subTop or sub) end
      tex:ClearAllPoints()
      tex:SetPoint("TOPLEFT", m.content, "TOPLEFT", x0, -y0)
      tex:SetSize(x1 - x0, y1 - y0)
      tex:SetTexture(t.file)
      tex:SetTexCoord(0, t.u1, 0, t.v1)
      Map.tintTile(tex, original)
      if not tex.masked and tex.AddMaskTexture then
        if m.artMask then pcall(tex.AddMaskTexture, tex, m.artMask) end
        if m.viewMask then pcall(tex.AddMaskTexture, tex, m.viewMask) end
        tex.masked = true
      end
      tex:Show()
    end
  end
  hideFrom(pool, n)
  return n
end

local function renderTiles(m, art, T, original)
  if art and m.artMask then
    local x0, y0 = Map.toPixel(T, 0, 0)
    local x1, y1 = Map.toPixel(T, 1, 1)
    local k = 1 / (1 - 2 * Map.ART_INSET)
    local mw, mh = max(1, (x1 - x0) * k), max(1, (y1 - y0) * k)
    m.artMask:ClearAllPoints()
    m.artMask:SetPoint("TOPLEFT", m.content, "TOPLEFT", x0 - mw * Map.ART_INSET, -(y0 - mh * Map.ART_INSET))
    m.artMask:SetSize(mw, mh)
  end
  local n = placeTiles(m, m.tiles, art and Map.tiles(art) or {}, art, T, original, 1)
  local o = placeTiles(m, m.overlays, art and art.overlays or {}, art, T, original, 2, 3)
  return n, o
end

local function renderOutlines(m, rects, T)
  local n = 0
  for _, r in ipairs(rects or {}) do
    local x0, y0 = Map.toPixel(T, r.x0, r.y0)
    local x1, y1 = Map.toPixel(T, r.x1, r.y1)
    local edges = { { x0, y0, x1, y0 }, { x1, y0, x1, y1 }, { x1, y1, x0, y1 }, { x0, y1, x0, y0 } }
    for _, e in ipairs(edges) do
      n = n + 1
      local l = line(m, m.outlines, n, 0)
      l:SetColorTexture(Theme.C.sepia[1], Theme.C.sepia[2], Theme.C.sepia[3], 0.45)
      l:SetThickness(1.2)
      drawLine(m, l, e[1], e[2], e[3], e[4])
    end
  end
  hideFrom(m.outlines, n)
  return n
end

local function viewKey(scene)
  local sel = scene.sel or {}
  return tostring(scene.key) .. "|" .. tostring(sel.chapter) .. "|" .. tostring(sel.zone) .. "|" .. tostring(sel.continent)
end

-- Draw the scene. opts = { art, aspect, outlines, reduceMotion, obstacles, keepView, color, clip, axis }. axis: fn(p) ->
-- playback axis (idle compressed), default played seconds 1:1. art: { w, h, tileW, tileH, files, overlays? }. color: "original"
-- or sepia. showKills = false hides kill marks. clip: { x0, y0, x1, y1 } in view coordinates (zone map 0..1). keepView keeps the player's zoom.
function Map.render(m, scene, opts)
  opts = opts or {}
  m.scene, m.reduceMotion, m.opts = scene, opts.reduceMotion and true or false, opts
  hideHover(m)
  m.hoverDirty = true
  Map.hoverSync(m)
  Map.liveSync(m)
  local artW, artH = 1, 1
  if opts.art then
    artW, artH = opts.art.w, opts.art.h
  elseif opts.aspect then
    artW, artH = opts.aspect, 1
  end
  local f = scene.focus or { x0 = 0, x1 = 1, y0 = 0, y1 = 1 }
  local fw, fh = max((f.x1 - f.x0) * artW, 1e-6), max((f.y1 - f.y0) * artH, 1e-6)
  local inset = Map.safeInset(m.W, m.H, opts.obstacles, fw / fh)
  local pad = opts.pad or Map.FIT_PAD
  if m.W - inset.l - inset.r > 2 * pad + Map.SAFE_MIN and m.H - inset.t - inset.b > 2 * pad + Map.SAFE_MIN then
    inset = { l = inset.l + pad, t = inset.t + pad, r = inset.r + pad, b = inset.b + pad }
  end
  m.inset = inset
  m.free = { x0 = inset.l, y0 = inset.t, x1 = m.W - inset.r, y1 = m.H - inset.b }
  local base = Map.fit(f, artW, artH, m.W, m.H, inset)
  local whole = Map.fit({ x0 = 0, x1 = 1, y0 = 0, y1 = 1 }, artW, artH, m.W, m.H, inset)
  base.minSx = min(base.sx, whole.sx)
  m.base, m.box = base, Map.panBox(base, f)
  local key = viewKey(scene)
  local T = base
  if opts.keepView and m.userT and m.viewKey == key then
    T = Map.clampView(m.userT, base, m.box)
  end
  m.viewKey = key
  m.userT = Map.isZoomed(T, base) and T or nil
  m.T = T
  m.p = huge
  return Map.draw(m)
end

function Map.setView(m, T)
  if not m.scene or not m.base or not T then return false end
  m.T = T
  m.userT = Map.isZoomed(T, m.base) and T or nil
  local p = m.p
  Map.draw(m, p)
  if m.onView then m.onView(m.userT ~= nil) end
  return true
end

function Map.resetView(m)
  if not m.userT or not m.base then return false end
  return Map.setView(m, m.base)
end

function Map.zoomed(m) return m.userT ~= nil end

-- Live tail: the trail is sampled every 3-6 s and the model is rebuilt at most every 2.5 s, so the drawn route ends a few
-- metres behind the arrow and then jumps forward. A thin line from the last route point (scene.route.tail) to the arrow
-- closes that gap on every live step. Only while the whole route is shown (no playback), when the last trail point is recent
-- (Map.TAIL_MAX_AGE s: no line across a teleport, hearth or logout) and the arrow is near it (Map.TAIL_MAX_VIEW of the view).
Map.TAIL_MAX_AGE = 30
Map.TAIL_MAX_VIEW = 0.25
-- A step of the arrow farther than max(Map.JUMP_MIN_YD, Map.JUMP_SPEED * seconds) yards is a blink/teleport, not walking (fastest
-- skyriding is ~80 yd/s): the tail of that trail point is switched off, a new trail point brings it back.
Map.JUMP_MIN_YD = 15
Map.JUMP_SPEED = 110
-- The tail must join the last drawn route segment without a visible seam (same pixel within Map.TAIL_JOIN_PX).
Map.TAIL_JOIN_PX = 2

local function lastWalk(m)
  for i = #(m.segs or {}), 1, -1 do
    if m.segs[i].kind ~= "flight" then return m.segs[i] end
  end
  return nil
end

function Map.placeTail(m)
  local scene = m.scene
  local tail = scene and scene.route and scene.route.tail
  local cur = scene and scene.current
  local show = false
  local x1, y1, x2, y2
  if tail and cur and m.T and (m.p == nil or m.p == huge) and type(time) == "function" and m.tailOffT ~= tail.t then
    local age = time() - (tail.t or 0)
    local dx, dy = cur.vx - tail.vx, cur.vy - tail.vy
    if age >= 0 and age <= Map.TAIL_MAX_AGE and dx * dx + dy * dy <= Map.TAIL_MAX_VIEW ^ 2 and (dx ~= 0 or dy ~= 0) then
      x1, y1 = Map.toPixel(m.T, tail.vx, tail.vy)
      x2, y2 = Map.toPixel(m.T, cur.vx, cur.vy)
      show = x1 ~= nil and x2 ~= nil
      -- starts exactly where the last drawn segment ends (else the route was cut: no loose piece)
      local ls = show and lastWalk(m)
      if show and not (ls and math.abs(ls.x2 - x1) <= Map.TAIL_JOIN_PX and math.abs(ls.y2 - y1) <= Map.TAIL_JOIN_PX) then
        show = false
      elseif show then
        x1, y1 = ls.x2, ls.y2
      end
    end
  end
  if not show then
    if m.tailLine then m.tailLine:Hide() end
    return false
  end
  if not m.tailLine then
    m.tailLine = m.content:CreateLine(nil, "ARTWORK", nil, 3)
    styleRoute(m.tailLine, "walk")
  end
  return drawLine(m, m.tailLine, x1, y1, x2, y2)
end

-- Player arrow at scene.current (position, heading: the player's facing if known, else the end of the route). Also used by
-- the live tick, which moves only the arrow; cp = clip in pixels (default: the visible clip of the last draw).
function Map.placeCurrent(m, cp)
  local cur = m.scene and m.scene.current
  cp = cp or m.clipPx or { x0 = 0, y0 = 0, x1 = m.W, y1 = m.H }
  local cpx, cpy
  if cur and m.T then cpx, cpy = Map.toPixel(m.T, cur.vx, cur.vy) end
  if cpx and cpx >= cp.x0 and cpy >= cp.y0 and cpx <= cp.x1 and cpy <= cp.y1 then
    m.current:ClearAllPoints()
    m.current:SetPoint("CENTER", m.content, "TOPLEFT", cpx, -cpy)
    if m.arrow then m.current:SetSize(m.headSize, m.headSize) end
    turnHead(m, m.current, "currentAngle", cur.facing or Map.headingAt(m.segs, #m.segs))
    m.current:Show()
  else
    m.current:Hide()
  end
  Map.placeTail(m)
end

-- Live arrow: while the map with a live scene (scene.live) is visible, a tick (Map.LIVE_INTERVAL) moves the arrow to the
-- player's position and facing without redrawing the map. scene.live = true uses View.liveHead, or a function(scene) with the
-- same result: vx, vy, facing | false (player not on this map: hide the arrow) | nil (no position: leave it).
Map.LIVE_INTERVAL = 0.15

local function visible(f)
  if not f then return false end
  if type(f.IsVisible) == "function" then return f:IsVisible() and true or false end
  return type(f.IsShown) == "function" and f:IsShown() and true or false
end

-- -> true if the arrow was moved or hidden
function Map.liveStep(m)
  local scene = m.scene
  if not (scene and scene.live and m.T and m.current) then return false end
  local fn = type(scene.live) == "function" and scene.live or (View and View.liveHead)
  if type(fn) ~= "function" then return false end
  local ok, vx, vy, facing = pcall(fn, scene)
  if not ok or vx == nil then return false end
  if vx == false then
    if not scene.current then return false end
    scene.current = nil
    m.current:Hide()
    Map.placeTail(m)
    return true
  end
  if type(vx) ~= "number" or type(vy) ~= "number" then return false end
  local cur = scene.current
  if cur and cur.vx == vx and cur.vy == vy and cur.facing == facing then return false end
  -- a sudden step (blink, port without event) switches the tail of the current trail point off
  local tail, yd = scene.route and scene.route.tail, scene.yards
  if cur and tail and yd then
    local now = type(GetTime) == "function" and GetTime() or nil
    local dt = (now and m.liveT) and (now - m.liveT) or 0
    local dx, dy = (vx - cur.vx) * yd[1], (vy - cur.vy) * yd[2]
    if sqrt(dx * dx + dy * dy) > max(Map.JUMP_MIN_YD, Map.JUMP_SPEED * dt) then m.tailOffT = tail.t end
  end
  m.liveT = type(GetTime) == "function" and GetTime() or nil
  scene.current = { vx = vx, vy = vy, facing = facing }
  Map.placeCurrent(m)
  return true
end

function Map.liveSync(m)
  if not m.liveFrame then return end
  local want = m.scene ~= nil and m.scene.live ~= nil and m.scene.live ~= false and visible(m.viewport) or false
  if want == (m.liveRunning or false) then return end
  m.liveRunning = want
  if not want then
    m.liveFrame:SetScript("OnUpdate", nil)
    return
  end
  m.liveAcc = 0
  m.liveFrame:SetScript("OnUpdate", function(_, dt)
    m.liveAcc = (m.liveAcc or 0) + (dt or 0)
    if m.liveAcc < Map.LIVE_INTERVAL then return end
    m.liveAcc = 0
    if not (m.scene and m.scene.live and visible(m.viewport)) then return Map.liveSync(m) end
    Map.liveStep(m)
  end)
end

function Map.draw(m, p)
  local scene, opts, T = m.scene, m.opts or {}, m.T
  local ax = opts.axis or function(v) return v end
  local cl = opts.clip
  if cl then
    local x0, y0 = Map.toPixel(T, cl.x0, cl.y0)
    local x1, y1 = Map.toPixel(T, cl.x1, cl.y1)
    m.clipPx = { x0 = max(0, x0), y0 = max(0, y0), x1 = min(m.W, x1), y1 = min(m.H, y1) }
  else
    m.clipPx = nil
  end
  local cp = m.clipPx or { x0 = 0, y0 = 0, x1 = m.W, y1 = m.H }
  local tiles, overlays = renderTiles(m, opts.art, T, opts.color == "original")
  placeHighlight(m)
  m.hoverDirty = true
  m.stats = { tiles = tiles, overlays = overlays, outlines = renderOutlines(m, opts.outlines, T) }

  local segs = scene.route and scene.route.segments or {}
  local maxLines = Map.LINE_POOL_MAX - #(opts.outlines or {}) * 4 - 3
  local n = 0
  m.segs = {}
  local px = {}
  for i, s in ipairs(segs) do
    local x1, y1 = Map.toPixel(T, s.x1, s.y1)
    local x2, y2 = Map.toPixel(T, s.x2, s.y2)
    px[i] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, p0 = ax(s.p0 or 0), p = ax(s.p or s.p0 or 0), kind = s.kind }
  end
  for _, s in ipairs(Map.mergeShort(px)) do
    if n >= maxLines then break end
    n = n + 1
    local l = line(m, m.lines, n, 3)
    styleRoute(l, s.kind)
    s.line = l
    m.segs[n] = s
  end
  hideFrom(m.lines, n)
  local gl = Map.GLOW and Map.glow(segs, View.GLOW_GROUP) or {}
  local g = 0
  m.glowSegs = {}
  for _, s in ipairs(gl) do
    if n + g >= maxLines then break end
    g = g + 1
    local x1, y1 = Map.toPixel(T, s.x1, s.y1)
    local x2, y2 = Map.toPixel(T, s.x2, s.y2)
    local l = line(m, m.glows, g, 2)
    l:SetColorTexture(Theme.C.glow[1], Theme.C.glow[2], Theme.C.glow[3], 0.25)
    l:SetThickness(Map.GLOW_WIDTH)
    m.glowSegs[g] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, p0 = ax(s.p0 or 0), p = ax(s.p or 0), line = l }
  end
  hideFrom(m.glows, g)

  local k = 0
  m.marks = {}
  local lvPos = {}
  for _, e in ipairs(scene.levelUps or {}) do
    local px, py = Map.toPixel(T, e.vx, e.vy)
    if px >= cp.x0 and py >= cp.y0 and px <= cp.x1 and py <= cp.y1 then lvPos[#lvPos + 1] = { px, py, e = e } end
  end
  local lvAll = {}
  for _, u in ipairs(lvPos) do lvAll[#lvAll + 1] = u end
  for _, e in ipairs(scene.markers or {}) do
    local mk = e.marker
    if isLevelKind(mk.kind) then
      local px, py = Map.toPixel(T, e.vx, e.vy)
      lvAll[#lvAll + 1] = { px, py, mk.kind == "milestone" and Map.MILESTONE_MARK_SIZE or Map.LEVEL_MARK_SIZE }
    end
  end
  local function put(kind, vx, vy, p, entry, tip, extra)
    local px, py = Map.toPixel(T, vx, vy)
    if px < cp.x0 or py < cp.y0 or px > cp.x1 or py > cp.y1 then return end
    if not isLevelKind(kind) and #lvAll > 0 then
      local kx, ky = Map.avoidLevelUps(px, py, Theme.MARKER_SIZE[kind] or 22, lvAll)
      if kx then px, py = kx, ky end
    end
    k = k + 1
    local b = acquire(m.markers, k, function() return newMarker(m) end)
    setMarker(m, b, kind, px, py, entry)
    b.tip, b.extra = tip, extra
    m.marks[k] = { b = b, p = ax(p or 0) }
  end
  for _, e in ipairs(scene.markers or {}) do
    local mk = e.marker
    put(mk.kind, e.vx, e.vy, mk.p, mk, mk.tip)
  end
  for _, e in ipairs(scene.gaps or {}) do
    if e.vx and e.vy then put("gap", e.vx, e.vy, e.gap.p0, nil, e.gap.tip, MT.gapHint) end
  end
  hideFrom(m.markers, k)
  m.stats.pins = Map.drawPins(m, scene, T, cp)

  m.minis = {}
  local nk, nl = 0, 0
  local bundles = opts.showKills == false and {} or Map.bundlesFor(m, scene, T)
  local visible = {}
  for _, b in ipairs(bundles) do
    local px, py = Map.toPixel(T, b.vx, b.vy)
    if px >= cp.x0 and py >= cp.y0 and px <= cp.x1 and py <= cp.y1 then
      visible[#visible + 1] = b
      b.px, b.py = px, py
    end
  end
  local zoom = (m.base and m.base.sx and m.base.sx > 0) and (T.sx / m.base.sx) or 1
  m.headSize = Map.arrowSize(scene.mode, zoom)
  if m.arrow then m.walker:SetSize(m.headSize, m.headSize) end
  for _, b in ipairs(Map.pickBundles(visible, Map.KILL_MAX)) do
    local size = Map.killSize(b.n, zoom)
    local kx, ky = Map.avoidLevelUps(b.px, b.py, size, lvAll)
    if kx then
      nk = nk + 1
      local btn = acquire(m.killBtns, nk, function() return newMini(m, "kills") end)
      btn:SetSize(size, size)
      btn.baseSize = size
      Map.sizeKillArt(btn, false)
      btn:ClearAllPoints()
      btn:SetPoint("CENTER", m.content, "TOPLEFT", kx, -ky)
      btn.label:SetText("")
      btn.data = b
      m.minis[#m.minis + 1] = { b = btn, p = ax(b.p0) }
    end
  end
  for _, lp in ipairs(lvPos) do
    local e, px, py = lp.e, lp[1], lp[2]
    do
      nl = nl + 1
      local btn = acquire(m.lvupBtns, nl, function() return newMini(m, "level") end)
      btn:SetSize(Map.LVUP_SIZE, Map.LVUP_SIZE)
      btn:ClearAllPoints()
      btn:SetPoint("CENTER", m.content, "TOPLEFT", px, -py)
      btn.label:SetText(tostring(floor(e.level)))
      btn.data = e
      m.minis[#m.minis + 1] = { b = btn, p = ax(e.p or 0) }
    end
  end
  hideFrom(m.killBtns, nk)
  hideFrom(m.lvupBtns, nl)

  -- Margin notes (at most Map.NOTE_MAX): the text stands as red handwriting on the left page (m.noteBox), listed and numbered;
  -- on the map only the red number marks the spot. Whether a note belongs to the view is decided by the zone frame (opts.clip),
  -- not by the zoom.
  local nn = 0
  m.noteList = {}
  local box = m.noteBox or m.noteLayer
  local textW = max(60, (m.noteBox and m.noteW or m.W * 0.4) - 18)
  local y = m.noteBox and 0 or 12
  local xText = m.noteBox and 18 or 30
  for _, note in ipairs(scene.notes or {}) do
    if nn >= (m.noteMax or Map.NOTE_MAX) then break end
    local inView = true
    if note.vx and note.vy and cl then
      inView = note.vx >= cl.x0 and note.vx <= cl.x1 and note.vy >= cl.y0 and note.vy <= cl.y1
    end
    if inView then
      nn = nn + 1
      local o = acquire(m.notes, nn, function()
        local fs = box:CreateFontString(nil, "OVERLAY")
        local num = box:CreateFontString(nil, "OVERLAY")
        local pin = m.markerLayer:CreateFontString(nil, "OVERLAY", nil, 2)
        return { fs = fs, num = num, pin = pin }
      end)
      local color = note.kind == "longest_flight" and Theme.C.blue or Theme.C.red
      Theme.font(o.fs, "note", Map.NOTE_SIZE, color)
      Theme.font(o.num, "note", Map.NOTE_SIZE, color)
      Theme.font(o.pin, "note", 15, color)
      o.fs:SetText(note.text)
      o.fs:SetJustifyH("LEFT")
      o.fs:SetWidth(textW)
      if o.fs.SetSpacing then o.fs:SetSpacing(2) end
      o.fs:ClearAllPoints()
      o.fs:SetPoint("TOPLEFT", box, "TOPLEFT", xText, -y)
      local hasPoint = note.vx and note.vy and true or false
      o.num:SetText(hasPoint and tostring(nn) or "")
      o.num:ClearAllPoints()
      o.num:SetPoint("TOPRIGHT", box, "TOPLEFT", xText - 6, -y)
      local th = o.fs.GetStringHeight and tonumber(o.fs:GetStringHeight()) or Map.NOTE_SIZE
      y = y + max(th, Map.NOTE_SIZE) + Map.NOTE_GAP
      local hasPin = false
      if hasPoint then
        local px, py = Map.toPixel(T, note.vx, note.vy)
        if px >= cp.x0 and py >= cp.y0 and px <= cp.x1 and py <= cp.y1 then
          o.pin:SetText(tostring(nn))
          o.pin:ClearAllPoints()
          o.pin:SetPoint("BOTTOMLEFT", m.content, "TOPLEFT", px + 7, -(py - 7))
          hasPin = true
        end
      end
      o.fs:Show()
      o.num:Show()
      o.pin:SetShown(hasPin)
      m.noteList[nn] = { o = o, p = ax(note.p or 0), hasPin = hasPin }
    end
  end
  hideFrom(m.notes, nn)

  Map.placeCurrent(m, cp)
  m.stats.lines, m.stats.glows, m.stats.markers, m.stats.notes = n, g, k, nn
  m.stats.kills, m.stats.levelUps = nk, nl
  Map.setProgress(m, p or huge)
  return m.stats
end

-- Note pins: scene.pins = { { id, title, vx, vy, hint, color }, ... } in view coordinates (hint = second tooltip line instead
-- of MT.pinHint, color = tint for to-do places). The tip sits on the place (Media/NotePin, Theme.NOTE_PIN), above all markers;
-- click calls m.onPin(id). Always visible, only if the tip is in the image. At most Map.PIN_MAX.
Map.PIN_MAX = 100

local function newPin(m)
  local P = Theme.NOTE_PIN or { size = 26, tipX = 0.1, tipY = 0.9 }
  local b = CreateFrame("Button", nil, m.markerLayer)
  b:SetSize(P.size, P.size)
  local icon = b:CreateTexture(nil, "OVERLAY")
  icon:SetAllPoints(b)
  icon:SetTexture(Theme.TEX.notePin)
  b.icon = icon
  if b.SetFrameLevel and m.markerLayer.GetFrameLevel then
    local lvl = m.markerLayer:GetFrameLevel()
    if type(lvl) == "number" then b:SetFrameLevel(lvl + 4) end
  end
  b:SetScript("OnEnter", function(self)
    local W = Journal.Widgets
    if self.title and W and W.tip then W.tip(self, { self.title, self.hint or MT.pinHint }) end
  end)
  b:SetScript("OnLeave", function(self)
    local W = Journal.Widgets
    if W and W.hideTip then W.hideTip(self) else Theme.hideTooltip() end
  end)
  b:SetScript("OnClick", function(self)
    if self.noteId and m.onPin then pcall(m.onPin, self.noteId) end
  end)
  return b
end

function Map.drawPins(m, scene, T, cp)
  local P = Theme.NOTE_PIN or { size = 26, tipX = 0.1, tipY = 0.9 }
  local n = 0
  m.pinList = {}
  for _, e in ipairs(scene.pins or {}) do
    if n >= Map.PIN_MAX then break end
    if type(e.vx) == "number" and type(e.vy) == "number" then
      local px, py = Map.toPixel(T, e.vx, e.vy)
      if px >= cp.x0 and py >= cp.y0 and px <= cp.x1 and py <= cp.y1 then
        n = n + 1
        local b = acquire(m.pins, n, function() return newPin(m) end)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", m.content, "TOPLEFT", px - P.tipX * P.size, -(py - P.tipY * P.size))
        b.noteId, b.title, b.hint = e.id, e.title, e.hint
        local c = type(e.color) == "table" and e.color or nil
        b.icon:SetVertexColor(c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, 1)
        b:Show()
        m.pinList[n] = b
      end
    end
  end
  hideFrom(m.pins, n)
  return n
end

function Map.setProgress(m, p)
  m.p = p
  local tipX, tipY, tipIdx
  for i, s in ipairs(m.segs) do
    local l = s.line
    if s.p0 > p then
      if s.shown ~= false then l:Hide() s.shown = false end
    elseif s.p <= p or s.p <= s.p0 then
      if s.shown ~= true then
        local ok, len = drawLine(m, l, s.x1, s.y1, s.x2, s.y2)
        if ok and s.kind == "flight" then l:SetTexCoord(0, len / Map.DASH, 0, 1) end
        s.shown = true
      end
      tipX, tipY, tipIdx = s.x2, s.y2, i
    else
      local f = (p - s.p0) / (s.p - s.p0)
      local x2, y2 = lerp(s.x1, s.x2, f), lerp(s.y1, s.y2, f)
      local ok, len = drawLine(m, l, s.x1, s.y1, x2, y2)
      if ok and s.kind == "flight" then l:SetTexCoord(0, len / Map.DASH, 0, 1) end
      s.shown = "partial"
      tipX, tipY, tipIdx = x2, y2, i
    end
  end
  for _, s in ipairs(m.glowSegs) do
    local vis = s.p0 <= p
    if vis ~= s.shown then
      if vis then drawLine(m, s.line, s.x1, s.y1, s.x2, s.y2) else s.line:Hide() end
      s.shown = vis
    end
  end
  for _, e in ipairs(m.marks or {}) do
    local vis = e.p <= p
    if vis ~= e.shown then
      e.b:SetShown(vis)
      e.shown = vis
    end
  end
  for _, e in ipairs(m.minis or {}) do
    local vis = e.p <= p
    if vis ~= e.shown then
      e.b:SetShown(vis)
      e.shown = vis
    end
  end
  local playing = p ~= huge
  -- before the first drawn segment (K2: the click on an act/chapter jumps to its start): the arrow waits at the start point
  if playing and not tipX then
    for i, s in ipairs(m.segs) do
      if s.p0 >= p then
        tipX, tipY, tipIdx = s.x1, s.y1, i
        break
      end
    end
  end
  for _, e in ipairs(m.noteList or {}) do
    local vis = not playing or e.p <= p
    e.o.fs:SetShown(vis)
    e.o.num:SetShown(vis)
    e.o.pin:SetShown(vis and e.hasPin)
  end
  if playing and tipX then
    m.walker:ClearAllPoints()
    m.walker:SetPoint("CENTER", m.content, "TOPLEFT", tipX, -tipY)
    turnHead(m, m.walker, "walkerAngle", Map.headingAt(m.segs, tipIdx))
    m.walker:Show()
    m.current:SetAlpha(0.35)
  else
    m.walker:Hide()
    m.current:SetAlpha(1)
  end
  Map.placeTail(m)
end

function Map.counts(m)
  local lines, marks = 0, 0
  for _, s in ipairs(m.segs or {}) do if s.shown then lines = lines + 1 end end
  for _, e in ipairs(m.marks or {}) do if e.shown then marks = marks + 1 end end
  return lines, marks
end
