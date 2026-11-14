-- Heat map core (I15): where the character stayed how long, and where it died, per zone map. Pure read logic over the journey
-- model (Model.heatSource: raw trail blocks, away intervals, deaths, play breaks); no UI, no SavedVariables, no new log format.
--
-- Weighting "standstill capped": every trail point gets the time up to the next point of the SAME block.
--   - gap <= Model.IDLE_GAP (66 s): the whole gap; gap > IDLE_GAP (standing, fighting on the spot, AFK): at most GAP_CAP (300 s)
--   - away time (AF lines) inside the gap does not count (the gap is reduced first, then capped)
--   - the last point of a block, the gap after a take-off mark (f, flight) and a gap that contains a play break (login/reload,
--     L line) count 0; time across block borders (map change, login, full block) is never counted
--
-- PUBLIC API (results are shared, read-only; cached per model = per character, they are dropped with the next build):
--   Heatmap.zones(model)                -> list { mapID, name, seconds (weighted), deaths (count) } sorted by seconds (desc, then mapID)
--   Heatmap.grid(model, mapID, kind)    -> { mapID, kind, size = 64, cells = { [1..4096] }, max, total, count (cells > 0), tips? } | nil
--        kind "stay":  cells[i] = weighted seconds, total = sum
--        kind "death": cells[i] = number of deaths, total = deaths with a position, tips[i] = { { level, cause, npc, source, at }, ... }
--                      newest first (cause = enemy | fall | drown | fatigue | lava | fire | slime | environment | "")
--        cell index i = (row - 1) * size + column; column from x (west -> east), row from y (north -> south), both 1..size
--   Heatmap.gridStep(model, mapID, kind, opts) -> grid | nil, job    resumable variant of grid (opts.budgetMs, default 8): returns the
--        finished grid, or nil and a job to pass back as opts.job to continue (call once per frame); a cached grid comes at once
--   Heatmap.cell(x, y)                  -> index of the cell of a map fraction x, y (0..1), nil outside
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Heatmap = {}
Journal.Heatmap = Heatmap

local floor, min, max, sort = math.floor, math.min, math.max, table.sort
local type, ipairs = type, ipairs
local clock = type(debugprofilestop) == "function" and function() return debugprofilestop() / 1000 end or os.clock

Heatmap.SIZE = 64          -- cells per side (decision of the change: 64 x 64)
Heatmap.GAP_CAP = 300      -- s: a standstill (gap > Model.IDLE_GAP) counts at most this long
Heatmap.CACHE_GRIDS = 16   -- finished grids kept per model (then the cache starts over)
Heatmap.CHUNK = 1024       -- trail points per slice of a resumable run, between two clock checks
Heatmap.CAUSES = { enemy = true, fall = true, drown = true, fatigue = true, lava = true, fire = true, slime = true, environment = true }
Heatmap.SOURCE_MAX = 40    -- display length of the killer name from the saved data

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge or isSecret(v) then return nil end
  return v
end

local function model() return Journal.Model end

local function idleGap()
  local M = model()
  return M and num(M.IDLE_GAP) or 66
end

-- cell of 0..9999 coordinates (the unit of the trail and of DE lines) -> column/row 1..size
local function cellOf(x, y)
  local n = Heatmap.SIZE
  local cx, cy = floor(x * n / 10000) + 1, floor(y * n / 10000) + 1
  if cx < 1 then cx = 1 elseif cx > n then cx = n end
  if cy < 1 then cy = 1 elseif cy > n then cy = n end
  return (cy - 1) * n + cx
end

function Heatmap.cell(x, y)
  x, y = num(x), num(y)
  if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  return cellOf(min(x * 10000, 9999), min(y * 10000, 9999))
end

-- per-model cache: lives and dies with the model (a new build after data growth makes a new model)
local function cacheOf(m)
  local c = m._heat
  if not c then
    c = { grids = {}, nGrids = 0 }
    m._heat = c
  end
  return c
end

-- away intervals sorted and merged -> { a = {t0}, b = {t1} }
local function mergedAway(c, src)
  if c.away then return c.away end
  local list = {}
  for _, r in ipairs(src.afk) do
    if type(r) == "table" and num(r.t0) and num(r.t1) and r.t1 > r.t0 then list[#list + 1] = r end
  end
  sort(list, function(p, q)
    if p.t0 ~= q.t0 then return p.t0 < q.t0 end
    return p.t1 < q.t1
  end)
  local A, B, n = {}, {}, 0
  for _, r in ipairs(list) do
    if n > 0 and r.t0 <= B[n] then
      if r.t1 > B[n] then B[n] = r.t1 end
    else
      n = n + 1
      A[n], B[n] = r.t0, r.t1
    end
  end
  c.away = { a = A, b = B, n = n }
  return c.away
end

-- sorted play breaks (L lines): copy of the numbers only
local function sortedBreaks(c, src)
  if c.breaks then return c.breaks end
  local out = {}
  for _, t in ipairs(src.breaks) do
    if num(t) then out[#out + 1] = t end
  end
  sort(out)
  c.breaks = out
  return out
end

-- first index i in 1..n+1 with arr[i] > v (arr ascending)
local function firstAbove(arr, n, v)
  local lo, hi = 1, n + 1
  while lo < hi do
    local mid = floor((lo + hi) / 2)
    if arr[mid] > v then hi = mid else lo = mid + 1 end
  end
  return lo
end

-- blocks per mapID (in time order), once per model
local function blocksByMap(c, src)
  if c.byMap then return c.byMap end
  local by = {}
  for _, b in ipairs(src.blocks) do
    local id = type(b) == "table" and num(b.map)
    if id and b.n and b.n > 0 then
      local l = by[id]
      if not l then
        l = {}
        by[id] = l
      end
      l[#l + 1] = b
    end
  end
  c.byMap = by
  return by
end

-- Weighs the points i0..i1 of one block: sink(cellIndexSource, i, w) is called with w > 0 only. The AFK/break pointers belong to
-- the block run (st): st.ai (first away interval ending after the current point), st.bi (first break after it).
local function weighBlock(b, st, away, breaks, G, CAP, sink, arg, i0, i1)
  local ts, marks = b.t, b.mk
  local A, B, nA = away.a, away.b, away.n
  local nB = #breaks
  local ai, bi = st.ai, st.bi
  for i = i0, i1 do
    local t1, t2 = ts[i], ts[i + 1]
    local gap = t2 - t1
    if gap > 0 and marks[i] ~= "f" then
      while bi <= nB and breaks[bi] <= t1 do bi = bi + 1 end
      if not (bi <= nB and breaks[bi] < t2) then
        local w = gap
        if nA > 0 then
          while ai <= nA and B[ai] <= t1 do ai = ai + 1 end
          local j = ai
          while j <= nA and A[j] < t2 do
            local lo, hi = A[j], B[j]
            if lo < t1 then lo = t1 end
            if hi > t2 then hi = t2 end
            if hi > lo then w = w - (hi - lo) end
            j = j + 1
          end
        end
        if gap > G and w > CAP then w = CAP end
        if w > 0 then sink(arg, b, i, w) end
      end
    end
  end
  st.ai, st.bi = ai, bi
end

local function startBlock(b, away, breaks)
  local t0 = b.t[1]
  return { ai = firstAbove(away.b, away.n, t0), bi = firstAbove(breaks, #breaks, t0) }
end

-- ---- zone list ----------------------------------------------------------------------------------------------------------------

local function secondsSink(acc, b, i, w) acc.s = acc.s + w end

function Heatmap.zones(m)
  if type(m) ~= "table" then return {} end
  local c = cacheOf(m)
  if c.zones then return c.zones end
  local M = model()
  local src = M and M.heatSource and M.heatSource(m)
  if not src then return {} end
  local away, breaks, G, CAP = mergedAway(c, src), sortedBreaks(c, src), idleGap(), Heatmap.GAP_CAP
  local deaths = {}
  for _, d in ipairs(src.deaths) do
    local id = num(d.map)
    if id then deaths[id] = (deaths[id] or 0) + 1 end
  end
  local list = {}
  for id, blocks in pairs(blocksByMap(c, src)) do
    local acc = { s = 0 }
    for _, b in ipairs(blocks) do
      weighBlock(b, startBlock(b, away, breaks), away, breaks, G, CAP, secondsSink, acc, 1, b.n - 1)
    end
    list[#list + 1] = { mapID = id, name = M.mapName(m, id), seconds = acc.s, deaths = deaths[id] or 0 }
  end
  sort(list, function(p, q)
    if p.seconds ~= q.seconds then return p.seconds > q.seconds end
    return p.mapID < q.mapID
  end)
  c.zones = list
  return list
end

-- ---- grids --------------------------------------------------------------------------------------------------------------------

local function newGrid(mapID, kind)
  local n = Heatmap.SIZE
  local cells = {}
  for i = 1, n * n do cells[i] = 0 end
  return { mapID = mapID, kind = kind, size = n, cells = cells, max = 0, total = 0, count = 0 }
end

local function cellSink(g, b, i, w)
  local x, y = b.x[i], b.y[i]
  local aff = g.aff
  if aff then
    -- zone point on a continent grid: continent fraction = a + x * w (Geo.affine), back to 0..9999
    x = max(0, min(9999, floor((aff[1] + (x / 10000) * aff[2]) * 10000)))
    y = max(0, min(9999, floor((aff[3] + (y / 10000) * aff[4]) * 10000)))
  end
  local idx = cellOf(x, y)
  local v = g.cells[idx]
  if v == 0 then g.count = g.count + 1 end
  v = v + w
  g.cells[idx] = v
  g.total = g.total + w
  if v > g.max then g.max = v end
end

local function cleanSource(s)
  if type(s) ~= "string" or s == "" or isSecret(s) then return nil end
  local S = ns.Sanitize
  if S and S.display then return S.display(s, Heatmap.SOURCE_MAX) end
  return nil
end

-- Continent grids (heading of a continent on the heat map page): the continent's own trail/death points plus those of its zones,
-- projected onto the continent map (Geo.affine). Only a map that is its own continent counts (Geo.continentOf(id) == id); without
-- Geo (or without a rect) only the own points are used.
local function contAffine(mapID)
  local G = Journal.Geo
  if not (G and G.continentOf and G.affine) then return nil end
  local okC, cont = pcall(G.continentOf, mapID)
  if not okC or num(cont) ~= mapID then return nil end
  local memo = {}
  return function(id)
    if id == mapID then return nil end
    local e = memo[id]
    if e == nil then
      e = false
      local okK, c = pcall(G.continentOf, id)
      if okK and num(c) == mapID then
        local ok, a, bw, cc, dh = pcall(G.affine, id, mapID)
        if ok and num(a) and num(bw) and num(cc) and num(dh) then e = { a, bw, cc, dh } end
      end
      memo[id] = e
    end
    return e or nil
  end
end

local function buildDeaths(src, mapID)
  local g = newGrid(mapID, "death")
  local project = contAffine(mapID)
  local tips = {}
  g.tips = tips
  for _, d in ipairs(src.deaths) do
    local x, y = num(d.x), num(d.y)
    local dm = num(d.map)
    local aff = project and dm and dm ~= mapID and project(dm) or nil
    local inRange = x and y and x >= 0 and x <= 9999 and y >= 0 and y <= 9999
    if aff and inRange then
      x = max(0, min(9999, floor((aff[1] + (x / 10000) * aff[2]) * 10000)))
      y = max(0, min(9999, floor((aff[3] + (y / 10000) * aff[4]) * 10000)))
    end
    if (dm == mapID or aff) and inRange then
      local idx = cellOf(x, y)
      local v = g.cells[idx]
      if v == 0 then g.count = g.count + 1 end
      v = v + 1
      g.cells[idx] = v
      g.total = g.total + 1
      if v > g.max then g.max = v end
      local list = tips[idx]
      if not list then
        list = {}
        tips[idx] = list
      end
      local cause = d.cause
      if type(cause) ~= "string" or not Heatmap.CAUSES[cause] then cause = "" end
      list[#list + 1] = { level = num(d.level), cause = cause, npc = num(d.npc), source = cleanSource(d.source), at = num(d.t) }
    end
  end
  for _, list in pairs(tips) do
    sort(list, function(p, q) return (p.at or 0) > (q.at or 0) end)
  end
  return g
end

local function storeGrid(c, key, g)
  if c.nGrids >= Heatmap.CACHE_GRIDS then c.grids, c.nGrids = {}, 0 end
  c.grids[key] = g
  c.nGrids = c.nGrids + 1
end

local function gridKey(mapID, kind) return kind .. ":" .. mapID end

-- Resumable run of the stay grid: job = { c, key, g, blocks, bi (block), i (next point), st, away, breaks, G, CAP }
local function newStayJob(c, src, mapID)
  local by = blocksByMap(c, src)
  local blocks, affs = by[mapID] or {}, nil
  local project = contAffine(mapID)
  if project then
    -- continent: own blocks first, then the blocks of its zones (sorted by map id, stable), each with its affine
    local ids = {}
    for id in pairs(by) do
      if id ~= mapID and project(id) then ids[#ids + 1] = id end
    end
    if #ids > 0 then
      sort(ids)
      local all = {}
      affs = {}
      for _, b in ipairs(blocks) do all[#all + 1] = b end
      for _, id in ipairs(ids) do
        local aff = project(id)
        for _, b in ipairs(by[id]) do
          all[#all + 1] = b
          affs[#all] = aff
        end
      end
      blocks = all
    end
  end
  return { c = c, key = gridKey(mapID, "stay"), g = newGrid(mapID, "stay"), blocks = blocks, affs = affs, bi = 1, i = 1,
    away = mergedAway(c, src), breaks = sortedBreaks(c, src), G = idleGap(), CAP = Heatmap.GAP_CAP }
end

-- works until the budget (seconds) is used up; -> true when finished
local function runStayJob(job, budget)
  local deadline = budget and (clock() + budget) or nil
  local blocks = job.blocks
  while job.bi <= #blocks do
    local b = blocks[job.bi]
    local last = b.n - 1
    job.g.aff = job.affs and job.affs[job.bi] or nil
    if not job.st then job.st = startBlock(b, job.away, job.breaks) end
    while job.i <= last do
      local i1 = min(last, job.i + Heatmap.CHUNK - 1)
      weighBlock(b, job.st, job.away, job.breaks, job.G, job.CAP, cellSink, job.g, job.i, i1)
      job.i = i1 + 1
      if deadline and job.i <= last and clock() >= deadline then return false end
    end
    job.bi, job.i, job.st = job.bi + 1, 1, nil
    if deadline and job.bi <= #blocks and clock() >= deadline then return false end
  end
  job.g.aff = nil
  return true
end

local function checkArgs(m, mapID, kind)
  if type(m) ~= "table" or not num(mapID) or (kind ~= "stay" and kind ~= "death") then return false end
  return true
end

function Heatmap.gridStep(m, mapID, kind, opts)
  if not checkArgs(m, mapID, kind) then return nil end
  opts = opts or {}
  local M = model()
  local src = M and M.heatSource and M.heatSource(m)
  if not src then return nil end
  local c = cacheOf(m)
  local key = gridKey(mapID, kind)
  local hit = c.grids[key]
  if hit then return hit end
  if kind == "death" then
    local g = buildDeaths(src, mapID)
    storeGrid(c, key, g)
    return g
  end
  local job = opts.job
  if type(job) ~= "table" or job.c ~= c or job.key ~= key then job = newStayJob(c, src, mapID) end
  local budget = num(opts.budgetMs) and opts.budgetMs / 1000 or 0.008
  if runStayJob(job, budget) then
    storeGrid(c, key, job.g)
    return job.g
  end
  return nil, job
end

function Heatmap.grid(m, mapID, kind)
  if not checkArgs(m, mapID, kind) then return nil end
  local M = model()
  local src = M and M.heatSource and M.heatSource(m)
  if not src then return nil end
  local c = cacheOf(m)
  local key = gridKey(mapID, kind)
  local hit = c.grids[key]
  if hit then return hit end
  if kind == "death" then
    local g = buildDeaths(src, mapID)
    storeGrid(c, key, g)
    return g
  end
  local job = newStayJob(c, src, mapID)
  runStayJob(job, nil)
  storeGrid(c, key, job.g)
  return job.g
end
