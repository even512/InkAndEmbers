-- Evaluator for "since the last rest": numbers between two rests from the index (kill series, lists QT, LV, LT, rest times RA)
-- and chars[guid].trail. Rest detection, ns.onRestStart and the shouldShow/markShown gate live in collectors/Rest.lua.
-- Rest.summary(index, opts) -> sum | nil, reason; Rest.distance(index, from, to) -> yards, approx.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Rest = ns.Rest or {}
ns.Rest = Rest

local floor, huge, sqrt = math.floor, math.huge, math.sqrt
local match, gmatch = string.match, string.gmatch

Rest.BREAK_GAP = 120      -- seconds without a trail point ...
Rest.BREAK_DIST = 200     -- ... and more than 2 % of the map apart: no path in between (same as Model.BREAK_GAP / BREAK_DIST)
Rest.YARDS_PER_STEP = 30  -- estimate per trail point when the map size is unknown (same as Model.YARDS_PER_STEP)
Rest.EMPTY_YARDS = 100    -- less distance does not count as travelled

local function finite(v)
  return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

-- trail: blocks "#~<epoch>~<mapID>" with lines "<dt>~<x>~<y>[~<mark>]"
local function trailBlocks(index)
  local out = {}
  local char = type(index) == "table" and index.char
  local trail = type(char) == "table" and type(char.trail) == "table" and char.trail or {}
  for i = 1, #trail do
    local b = trail[i]
    if type(b) == "string" then
      local start, map = match(b, "^#~(%-?%d+)~(%-?%d+)")
      if start then out[#out + 1] = { start = tonumber(start), map = tonumber(map), text = b } end
    end
  end
  local Store = ns.Store
  local open = Store and Store.current == char and Store.trailBlock
  if type(open) == "table" and finite(tonumber(open.start)) and type(open.lines) == "table" and #open.lines > 0 then
    out[#out + 1] = { start = tonumber(open.start), map = tonumber(open.mapID), lines = open.lines }
  end
  return out
end

function Rest.distance(index, from, to)
  if not finite(from) or not finite(to) or to <= from then return 0, false end
  local Geo = Journal.Geo
  local blocks = trailBlocks(index)
  local yards, approx = 0, false
  local BG, BD2, YPS = Rest.BREAK_GAP, Rest.BREAK_DIST * Rest.BREAK_DIST, Rest.YARDS_PER_STEP
  for bi, b in ipairs(blocks) do
    local nextStart = blocks[bi + 1] and blocks[bi + 1].start or huge
    if b.start <= to and nextStart > from then
      local sw, sh
      if Geo and type(Geo.mapSize) == "function" and b.map then
        local ok, w, h = pcall(Geo.mapSize, b.map)
        if ok and finite(w) and finite(h) and w > 0 and h > 0 then sw, sh = w, h end
      end
      local pT, pX, pY, pMark
      local function point(dt, x, y, mark)
        x, y, dt = tonumber(x), tonumber(y), tonumber(dt)
        if not (finite(x) and finite(y) and finite(dt)) then return end
        local t = b.start + dt
        if t > to then return "stop" end
        if t >= from then
          if pT and pT >= from and pMark ~= "f" and pMark ~= "d" then
            local dx, dy = x - pX, y - pY
            if not (t - pT > BG and dx * dx + dy * dy > BD2) then
              if sw then
                local ex, ey = dx / 10000 * sw, dy / 10000 * sh
                yards = yards + sqrt(ex * ex + ey * ey)
              else
                approx = true
                if dx ~= 0 or dy ~= 0 then yards = yards + YPS end
              end
            end
          end
        end
        pT, pX, pY, pMark = t, x, y, (mark ~= "" and mark or nil)
      end
      if b.lines then
        for _, line in ipairs(b.lines) do
          local dt, x, y, mark = match(line, "^(%-?%d+)~(%-?%d+)~(%-?%d+)~?(%a?)")
          if dt and point(dt, x, y, mark) == "stop" then break end
        end
      else
        for dt, x, y, mark in gmatch(b.text, "\n(%-?%d+)~(%-?%d+)~(%-?%d+)~?(%a?)") do
          if point(dt, x, y, mark) == "stop" then break end
        end
      end
    end
  end
  return yards, approx
end

local function inRange(list, from, to, fn)
  if type(list) ~= "table" then return end
  for i = 1, #list do
    local r = list[i]
    if r.t >= from and r.t < to then fn(r) end
  end
end

function Rest.summary(index, opts)
  opts = opts or {}
  local Index = Journal.Index
  if type(index) ~= "table" then
    if not Index then return nil, "keine-daten" end
    local why
    index, why = Index.get({ noRebuild = true })
    if not index then return nil, why or "keine-daten" end
  end
  local to = finite(opts.to) and opts.to or time()
  local from, first = opts.from, false
  if from == false then
    from, first = index.startT or 0, true
  elseif not finite(from) then
    local rt = index.restT or {}
    local prev
    for i = #rt, 1, -1 do
      if (opts.to == nil and rt[i] <= to) or (opts.to ~= nil and rt[i] < to - 0.5) then
        prev = rt[i]
        break
      end
    end
    if prev then from = prev else from, first = index.startT or 0, true end
  end
  if from > to then from = to end

  local sum = { from = from, to = to, first = first, levels = {}, loot = { count = 0 } }
  sum.seconds = Index and Index.activeSeconds and (Index.activeSeconds(index, from, to)) or (to - from)
  local yards, approx = Rest.distance(index, from, to)
  sum.km, sum.kmApprox = floor(yards * 0.9144 / 100 + 0.5) / 10, approx
  if Index and Index.killsBetween then
    sum.kills, sum.killsExact = Index.killsBetween(index, from, to)
  else
    sum.kills, sum.killsExact = 0, false
  end
  local lists = index.lists or {}
  local q = 0
  inRange(lists.QT, from, to, function() q = q + 1 end)
  sum.quests = q
  inRange(lists.LV, from, to, function(r)
    local lv = Index and Index.num(r, "LV", "level")
    if lv then
      sum.levels[#sum.levels + 1] = floor(lv)
      if not sum.level or lv > sum.level then sum.level = floor(lv) end
    end
  end)
  local best
  inRange(lists.LT, from, to, function(r)
    local key = Index and Index.str(r, "LT", "item")
    local id = key and match(key, "^(%d+)")
    local count = Index and Index.num(r, "LT", "count") or 1
    local quality = Index and Index.num(r, "LT", "quality") or -1
    sum.loot.count = sum.loot.count + 1
    if id and (not best or quality >= best.quality) then best = { itemID = tonumber(id), quality = quality, count = floor(count) } end
  end)
  if best then
    local snaps = type(index.char) == "table" and index.char.snapshots
    local items = type(snaps) == "table" and snaps.items
    local it = type(items) == "table" and items[best.itemID]
    local name = type(it) == "table" and type(it.name) == "string" and ns.Sanitize.field(it.name) or nil
    best.name = (name and name ~= "") and name or nil
    if best.quality < 0 then best.quality = nil end
    sum.loot.best = best
  end
  sum.empty = (sum.kills == 0 and sum.quests == 0 and #sum.levels == 0 and sum.loot.count == 0 and yards < Rest.EMPTY_YARDS)
  return sum
end
