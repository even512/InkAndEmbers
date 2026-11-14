-- Collector 'Plans' (to-do list, stored as 'vorhaben'): own travel goals of four kinds (kind): free (text + optional goal map, done on entering it or by hand),
-- place (point x, y 0..1 on mapID, done within Plans.RADIUS m), kill / item (target = { id, name }, need = count; count FC_KILL / FC_LOOT after creation, purchases, mail, trade and AH do not count).
-- Stored in chars[guid].vorhaben, additive only: { { id, text, kind, mapID, x, y, target = { id, name }, need, have, created, done = nil | time }, ... }. Old entries (no kind) count as 'free', never rewritten.
local _, ns = ...
local Core, Store = ns.Core, ns.Store

local floor, min, max, sqrt, lower = math.floor, math.min, math.max, math.sqrt, string.lower

local Plans = ns.Plans or {}
ns.Plans = Plans

Plans.TEXT_MAX = 120   -- characters (UTF-8) per to-do
Plans.MAX = 200        -- to-dos per character (open and done together)
Plans.NEED_MAX = 999   -- highest count (kill/item)
Plans.RADIUS = 15      -- meters: how close you must get to a place goal
Plans.PLACE_EVERY = 1.5 -- seconds: position check interval (only while open place goals exist)
Plans.CHANGE_DELAY = 0.25 -- seconds: Plans.onChange batches changes this long
Plans.YARD_M = 0.9144
Plans.KINDS = { free = true, place = true, kill = true, item = true }
-- loot sources (FC_LOOT kind) that do NOT count for 'find items'
Plans.ITEM_SKIP = { vendor = true, mail = true, trade = true, ah = true }
local CHECK_DELAY = 0.5 -- seconds: map info is current only shortly after the zone event
local CHAIN_DEPTH = 8

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function str(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a = pcall(fn, ...)
  if not ok then return nil end
  return a
end

local function callN(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d
end

-- cut to n characters (not bytes) without splitting a UTF-8 character
local function cutChars(s, n)
  local count, i, len = 0, 1, #s
  while i <= len do
    local b = string.byte(s, i)
    local size = (b < 128 and 1) or (b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or 1
    count = count + 1
    if count > n then return string.sub(s, 1, i - 1) end
    i = i + size
  end
  return s
end

function Plans.cleanText(text)
  if isSecret(text) or type(text) ~= "string" then return nil end
  local s = ns.Sanitize.field(text)
  s = string.gsub(s, "^ +", "")
  s = string.gsub(s, " +$", "")
  if s == "" then return nil end
  s = cutChars(s, Plans.TEXT_MAX)
  s = string.gsub(s, " +$", "")
  if s == "" then return nil end
  return s
end

local function store()
  local char = Store.char()
  if not char then return nil end
  if type(char.vorhaben) ~= "table" then char.vorhaben = {} end
  return char.vorhaben
end

local function kindOf(p)
  local k = p.kind
  if k == "place" or k == "kill" or k == "item" then return k end
  return "free"
end
Plans.kindOf = kindOf

local function validMap(mapID)
  mapID = num(mapID)
  if not mapID or mapID <= 0 or mapID > 2147483647 or mapID ~= floor(mapID) then return nil end
  return floor(mapID)
end

local function coord01(v)
  v = num(v)
  if not v or v < 0 or v > 1 then return nil end
  return v
end

local function needOf(p)
  local n = num(p.need)
  if not n or n < 1 then return 1 end
  return min(floor(n), Plans.NEED_MAX)
end

local function haveOf(p)
  local n = num(p.have)
  if not n or n < 0 then return 0 end
  return floor(n)
end

function Plans.label(p)
  if type(p) ~= "table" or type(p.text) ~= "string" then return nil end
  local k = kindOf(p)
  if (k == "kill" or k == "item") and needOf(p) > 1 then return string.format("%d× %s", needOf(p), p.text) end
  return p.text
end

-- The automatic teacher to-do keeps the text of the language it was made in ("Zum Lehrer: 3 neue Zauber (5 S 10 K)"). For display it is
-- rebuilt in the current language from the count and the price in it, so archived ones are not left in the other language.
-- The stored text stays as it is (data). Texts like collectors/Trainer.lua (todo_one/todo_other); English in locales/enUS_core.lua.
local PT = ns.Locale.ns("col.Plans", {
  trainerOne = "Zum Lehrer: %s neuer Zauber (%s)",
  trainerOther = "Zum Lehrer: %s neue Zauber (%s)",
  petOne = "Zum Tierausbilder: %s neue Fähigkeit (%s)",
  petOther = "Zum Tierausbilder: %s neue Fähigkeiten (%s)",
  unitG = "G",
  unitS = "S",
  unitK = "K",
})
-- pattern per stored language and the unit letters of its price: { pattern, g, s, k }
local TRAINER_SHAPES = {
  { "^Zum Lehrer: (%d+) neue[r]? Zauber %((.+)%)$", "G", "S", "K" },
  { "^To the trainer: (%d+) new spells? %((.+)%)$", "g", "s", "c" },
}

-- same for the pet trainer to-do (hunter): "Zum Tierausbilder: 2 neue Fähigkeiten (5 S 10 K)"
local PET_SHAPES = {
  { "^Zum Tierausbilder: (%d+) neue[r]? Fähigkeit[en]* %((.+)%)$", "G", "S", "K" },
  { "^To the pet trainer: (%d+) new abilit[a-z]* %((.+)%)$", "g", "s", "c" },
}

local function displayText(p)
  if (p.auto ~= "trainer" and p.auto ~= "pettrainer") or isSecret(p.text) or type(p.text) ~= "string" then return p.text end
  local pet = p.auto == "pettrainer"
  for _, shape in ipairs(pet and PET_SHAPES or TRAINER_SHAPES) do
    local n, price = string.match(p.text, shape[1])
    if n and #price <= 40 then
      local units = { [shape[2]] = PT.unitG, [shape[3]] = PT.unitS, [shape[4]] = PT.unitK }
      price = string.gsub(price, "(%d) (%a)%f[%A]", function(d, u) return d .. " " .. (units[u] or u) end)
      local one, other = "trainerOne", "trainerOther"
      if pet then one, other = "petOne", "petOther" end
      return PT(ns.Locale.plural(tonumber(n), one, other), n, price)
    end
  end
  return p.text
end

local function copy(p)
  local k = kindOf(p)
  local c = { id = p.id, text = displayText(p), kind = k, mapID = p.mapID, created = p.created, done = p.done, doneAt = p.done,
    auto = type(p.auto) == "string" and p.auto or nil }
  if k == "place" then c.x, c.y = coord01(p.x), coord01(p.y) end
  if type(p.target) == "table" then
    c.target = { id = validMap(p.target.id), name = type(p.target.name) == "string" and p.target.name or nil }
  end
  if k == "kill" or k == "item" then
    c.need = needOf(p)
    c.have = min(haveOf(p), c.need)
    if p.done then c.have = c.need end
    c.progress = string.format("%d/%d", c.have, c.need)
  end
  -- shopping list (collectors/Einkaufszettel.lua): own text, progress "3/5" (material lines ticked) and p.shop flag, read live
  if type(p.shop) == "table" and ns.Einkauf and type(ns.Einkauf.decorate) == "function" then pcall(ns.Einkauf.decorate, p, c) end
  return c
end

local function find(list, id)
  for i, p in ipairs(list) do
    if type(p) == "table" and p.id == id then return p, i end
  end
  return nil
end

local function valid(p)
  return type(p) == "table" and type(p.id) == "number" and type(p.text) == "string"
end

local doneHooks = {}

function ns.onPlanDone(fn)
  if type(fn) ~= "function" then return false end
  for _, f in ipairs(doneHooks) do
    if f == fn then return false end
  end
  doneHooks[#doneHooks + 1] = fn
  return true
end

-- change callbacks (book page, note): batched so a chain of kills does not redraw every time
local changeHooks = {}
local changePending = false

function Plans.onChange(fn)
  if type(fn) ~= "function" then return false end
  for _, f in ipairs(changeHooks) do
    if f == fn then return false end
  end
  changeHooks[#changeHooks + 1] = fn
  return true
end

local function runChange()
  changePending = false
  for i = 1, #changeHooks do Core.safe(changeHooks[i]) end
end

local function changed()
  if changePending or #changeHooks == 0 then return end
  changePending = true
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    local ok = pcall(C_Timer.After, Plans.CHANGE_DELAY, runChange)
    if ok then return end
  end
  runChange()
end
Plans.changed = changed

-- distance (place goals): both points on the same map (else the shared continent map), map size in yards from journal/Geo.lua, result in meters

local function geo()
  return ns.Journal and ns.Journal.Geo
end

local function metersOn(mapID, x1, y1, x2, y2)
  local G = geo()
  if not (G and G.mapSize) then return nil end
  local w, h = callN(G.mapSize, mapID)
  w, h = num(w), num(h)
  if not (w and h) or w <= 0 or h <= 0 then return nil end
  local dx, dy = (x1 - x2) * w, (y1 - y2) * h
  return sqrt(dx * dx + dy * dy) * Plans.YARD_M
end

local function onMap(mapID, contID, x, y)
  if mapID == contID then return x, y end
  local G = geo()
  local a, b, c, d = callN(G.affine, mapID, contID)
  a, b, c, d = num(a), num(b), num(c), num(d)
  if not (a and b and c and d) then return nil end
  return a + b * x, c + d * y
end

function Plans.distance(p)
  if type(p) ~= "table" or kindOf(p) ~= "place" then return nil end
  local tm, tx, ty = validMap(p.mapID), coord01(p.x), coord01(p.y)
  if not (tm and tx and ty) then return nil end
  local hm, hx, hy = callN(ns.Zone.raw)
  hm, hx, hy = validMap(hm), coord01(hx), coord01(hy)
  if not (hm and hx and hy) then return nil end
  if hm == tm then return metersOn(tm, hx, hy, tx, ty) end
  local G = geo()
  if not (G and G.continentOf and G.affine) then return nil end
  local c1, c2 = validMap(call(G.continentOf, hm)), validMap(call(G.continentOf, tm))
  if not c1 or c1 ~= c2 then return nil end
  local px, py = onMap(hm, c1, hx, hy)
  local qx, qy = onMap(tm, c1, tx, ty)
  if not (px and qx) then return nil end
  return metersOn(c1, px, py, qx, qy)
end

-- Fulfilling

local function level()
  local l = num(call(UnitLevel, "player"))
  return l and floor(l) or nil
end

-- automatically fulfilled: done, VE (how), hooks, change.
-- Each to-do counts only on the FIRST completion (p.counted, additive): reopening and completing again writes no VE line and fires no hook
-- (sound, banner); otherwise any count (medal 'Eigene Wege', diary) could be inflated by ticking/unticking.
local function complete(p, how)
  if p.done then return end
  p.done = floor(time())
  local k = kindOf(p)
  if k == "kill" or k == "item" then p.have = needOf(p) end
  if p.counted then
    changed()
    return
  end
  p.counted = true
  local mapID, x, y = ns.Zone.here()
  local label = Plans.label(p)
  Store.append("VE", p.id, p.mapID or (k == "place" and mapID) or nil, level(), x, y, label, how ~= "zone" and how or nil)
  local plan = copy(p)
  plan.how, plan.label = how, label
  for i = 1, #doneHooks do Core.safe(doneHooks[i], plan) end
  changed()
end

-- API

local function nextId(list)
  local id = 0
  for _, p in ipairs(list) do
    if type(p) == "table" and type(p.id) == "number" and p.id > id then id = p.id end
  end
  return id + 1
end

local function zoneLabel(mapID)
  local info = ns.Zone.info(mapID)
  return info and Plans.cleanText(info.name) or nil
end

-- name of a target without a given name: data list (Journal.TodoData), else names remembered by the chronicle
local function targetName(kind, id)
  local TD = ns.Journal and ns.Journal.TodoData
  if TD and type(TD.name) == "function" then
    local n = Plans.cleanText(call(TD.name, kind, id))
    if n then return n end
  end
  if kind == "kill" then
    local char = Store.char()
    local npcs = type(char) == "table" and char.npcs or nil
    local n = type(npcs) == "table" and npcs[id] or nil
    if type(n) == "table" then n = n.name end
    n = Plans.cleanText(n)
    if n then return n end
  end
  if kind == "item" then
    local n = Plans.cleanText(call(C_Item and C_Item.GetItemNameByID, id) or call(GetItemInfo, id))
    if n then return n end
  end
  return nil
end

function Plans.add(a, b)
  local spec
  if type(a) == "table" and not isSecret(a) then
    spec = a
  else
    spec = { kind = "free", text = a, mapID = b }
  end
  local list = store()
  if not list then return nil, "nicht-bereit" end
  local kind = spec.kind
  if kind == nil then kind = "free" end
  if isSecret(kind) or not Plans.KINDS[kind] then return nil, "art" end
  local e = { kind = kind, created = floor(time()) }
  if kind == "free" then
    e.text = Plans.cleanText(spec.text)
    if not e.text then return nil, "leer" end
    e.mapID = validMap(spec.mapID)
    if type(spec.shop) == "table" and not isSecret(spec.shop) then e.shop = spec.shop end -- shopping list data (Einkaufszettel)
  elseif kind == "place" then
    e.mapID, e.x, e.y = validMap(spec.mapID), coord01(spec.x), coord01(spec.y)
    if not (e.mapID and e.x and e.y) then return nil, "ort" end
    e.text = Plans.cleanText(spec.text) or zoneLabel(e.mapID) or "Ort"
  else
    local t = (type(spec.target) == "table" and not isSecret(spec.target)) and spec.target or {}
    local tid = validMap(t.id)
    local tname = Plans.cleanText(t.name) or (tid and targetName(kind, tid)) or nil
    if not (tid or tname) then
      if Plans.cleanText(spec.text) == nil then return nil, "leer" end
      tname = Plans.cleanText(spec.text) -- free text only: the text is the name
    end
    e.target = { id = tid, name = tname }
    e.need = max(1, min(floor(num(spec.need) or 1), Plans.NEED_MAX))
    e.have = 0
    e.text = Plans.cleanText(spec.text) or tname or ("#" .. tostring(tid))
  end
  if #list >= Plans.MAX then return nil, "voll" end
  e.id = nextId(list)
  list[#list + 1] = e
  Plans.watchPlaces()
  changed()
  return e.id
end

function Plans.remove(id)
  local list = store()
  if not list then return false end
  local _, i = find(list, num(id))
  if not i then return false end
  table.remove(list, i)
  Plans.watchPlaces()
  changed()
  return true
end

function Plans.toggle(id)
  local list = store()
  if not list then return nil end
  local p = find(list, num(id))
  if not p then return nil end
  if p.done then
    p.done = nil
    p.counted = true -- already done (also old data without the marker): never counts again
  else
    p.done = floor(time())
    -- by hand: only the diary learns of it (VE how = 'hand'), no hook, no sound; first completion only
    if valid(p) and not p.counted then
      p.counted = true
      local _, x, y = ns.Zone.here()
      Store.append("VE", p.id, p.mapID, level(), x, y, Plans.label(p), "hand")
    end
  end
  Plans.watchPlaces()
  changed()
  return p.done ~= nil
end

-- Automatic to-dos (e.g. "Zum Lehrer", collectors/Trainer.lua): a free to-do with a tag (p.auto, lower-case letters). At most one
-- open to-do per tag: Plans.upsertAuto creates it or updates its text; Plans.finishAuto completes it without a VE line (an
-- automatic to-do is no own travel goal: medal "Eigene Wege" and diary stay untouched), the done hooks (sound, card) still run.
local function autoTag(tag)
  if isSecret(tag) or type(tag) ~= "string" or not string.match(tag, "^%l+$") or #tag > 24 then return nil end
  return tag
end

function Plans.findAuto(tag)
  tag = autoTag(tag)
  local list = tag and store()
  if not list then return nil end
  for _, p in ipairs(list) do
    if valid(p) and not p.done and p.auto == tag then return p.id end
  end
  return nil
end

function Plans.upsertAuto(tag, text)
  tag = autoTag(tag)
  if not tag then return nil, "art" end
  local clean = Plans.cleanText(text)
  if not clean then return nil, "leer" end
  local list = store()
  if not list then return nil, "nicht-bereit" end
  local id = Plans.findAuto(tag)
  if id then
    local p = find(list, id)
    if p.text ~= clean then
      p.text = clean
      changed()
    end
    return id, "update"
  end
  local newId, err = Plans.add({ kind = "free", text = clean })
  if not newId then return nil, err end
  local p = find(list, newId)
  if p then p.auto = tag end
  return newId, "new"
end

function Plans.finishAuto(tag, how)
  local id = Plans.findAuto(tag)
  local list = id and store()
  local p = list and find(list, id)
  if not p then return false end
  p.done = floor(time())
  p.counted = true
  local plan = copy(p)
  plan.how, plan.label = type(how) == "string" and how or "auto", Plans.label(p)
  for i = 1, #doneHooks do Core.safe(doneHooks[i], plan) end
  Plans.watchPlaces()
  changed()
  return true
end

-- Shopping list (collectors/Einkaufszettel.lua): the stored entry itself (raw, for that collector only) and a completion by id
-- without a VE line (like finishAuto: a shopping list is no own travel goal), the done hooks (sound, card) still run.
function Plans.raw(id)
  local list = store()
  return list and find(list, num(id)) or nil
end

function Plans.rawList()
  return store()
end

function Plans.finishPlan(id, how)
  local list = store()
  local p = list and find(list, num(id))
  if not (p and valid(p)) or p.done then return false end
  p.done = floor(time())
  p.counted = true
  local plan = copy(p)
  plan.how, plan.label = type(how) == "string" and how or "auto", Plans.label(p)
  for i = 1, #doneHooks do Core.safe(doneHooks[i], plan) end
  Plans.watchPlaces()
  changed()
  return true
end

function Plans.get(id)
  local list = store()
  local p = list and find(list, num(id))
  if not (p and valid(p)) then return nil end
  local c = copy(p)
  if c.kind == "place" and not c.done then c.dist = Plans.distance(c) end
  return c
end

function Plans.list(filter)
  local list = store()
  local open, done = {}, {}
  if list then
    for _, p in ipairs(list) do
      if valid(p) then
        local c = copy(p)
        if p.done then
          done[#done + 1] = c
        else
          if c.kind == "place" then c.dist = Plans.distance(c) end
          open[#open + 1] = c
        end
      end
    end
  end
  table.sort(open, function(x, y) if x.created ~= y.created then return (x.created or 0) < (y.created or 0) end return x.id < y.id end)
  table.sort(done, function(x, y) if x.done ~= y.done then return x.done > y.done end return x.id > y.id end)
  if filter == "open" then return open end
  if filter == "done" then return done end
  for _, p in ipairs(done) do open[#open + 1] = p end
  return open
end

-- map chain: the map itself, its parent maps (parentMapID) and, if present, the UI's geo chain

local function chainOf(mapID)
  local set = {}
  local id, depth = validMap(mapID), 0
  while id and depth < CHAIN_DEPTH do
    set[id] = true
    local info = ns.Zone.info(id)
    id = info and validMap(info.parentMapID) or nil
    depth = depth + 1
  end
  local Geo = geo()
  if Geo and validMap(mapID) then
    for _, fn in ipairs({ Geo.zoneOf, Geo.mainZoneOf }) do
      local z = type(fn) == "function" and validMap(call(fn, mapID)) or nil
      if z then set[z] = true end
    end
  end
  return set
end

local function mainZone(mapID)
  local Geo = geo()
  local z = Geo and type(Geo.mainZoneOf) == "function" and validMap(call(Geo.mainZoneOf, mapID)) or nil
  return z or ns.Zone.ancestor(mapID, ns.Zone.TYPE_ZONE)
end

function Plans.nearby()
  local out = {}
  local mapID = ns.Zone.here()
  if not mapID then return out end
  local cur = chainOf(mapID)
  local curZone = mainZone(mapID)
  for _, p in ipairs(Plans.list("open")) do
    if p.mapID and (cur[p.mapID] or (curZone ~= nil and mainZone(p.mapID) == curZone)) then out[#out + 1] = p end
  end
  return out
end

-- Collector: entering the goal map (free), position (place), kills (kill), loot (item)

local Collector = {
  requires = { "C_Map.GetBestMapForUnit" },
  events = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" },
  signals = { "FC_KILL", "FC_LOOT" },
}
local handlers = {}

function Collector:init()
  self.prev = nil        -- map chain at the last check (nil = not checked yet)
  self.checkOn = false
  self.placeTicker = nil -- position check ticker (only with open place goals)
end

function Plans.check()
  local self = Collector
  if not Store.ready() then return end
  local list = store()
  if not list then return end
  local mapID = ns.Zone.here()
  if not mapID then return end
  local cur = chainOf(mapID)
  local first = self.prev == nil
  -- start of the running session (stays the same after /reload; Store.loginAt would be the reload time)
  local sess = Store.db and Store.db.meta and Store.db.meta.sessions and Store.db.meta.sessions[Store.session]
  local sessionStart = (type(sess) == "table" and tonumber(sess.start)) or Store.loginAt or time()
  for _, p in ipairs(list) do
    if valid(p) and not p.done and kindOf(p) == "free" and type(p.mapID) == "number" and cur[p.mapID] then
      -- entering = was not inside before. The first check after login only counts for plans from earlier sessions.
      local entered = (self.prev ~= nil and not self.prev[p.mapID]) or (first and (tonumber(p.created) or 0) < sessionStart)
      if entered then complete(p, "zone") end
    end
  end
  self.prev = cur
end

local function openPlaces(list)
  local n = 0
  for _, p in ipairs(list or {}) do
    if valid(p) and not p.done and kindOf(p) == "place" then n = n + 1 end
  end
  return n
end

function Plans.checkPlaces()
  if not Store.ready() then return 0 end
  local list = store()
  if not list then return 0 end
  local hits = 0
  for _, p in ipairs(list) do
    if valid(p) and not p.done and kindOf(p) == "place" then
      local d = Plans.distance(p)
      if d and d <= Plans.RADIUS then
        complete(p, "place")
        hits = hits + 1
      end
    end
  end
  if hits > 0 then Plans.watchPlaces() end
  return hits
end

-- switch the position ticker on/off: only while open place goals exist
function Plans.watchPlaces()
  local self = Collector
  local need = Store.ready() and openPlaces(store()) > 0
  if need and not self.placeTicker then
    local h = Core.ticker(self, Plans.PLACE_EVERY, function() Plans.checkPlaces() end)
    if h and not (h.IsCancelled and h:IsCancelled()) then self.placeTicker = h end
  elseif not need and self.placeTicker then
    self.placeTicker:Cancel()
    self.placeTicker = nil
  end
  return self.placeTicker ~= nil
end

local function scheduleCheck(self)
  if self.checkOn then return end
  self.checkOn = true
  if not Core.after(self, CHECK_DELAY, function(s)
    s.checkOn = false
    Plans.check()
    Plans.watchPlaces()
  end) then
    self.checkOn = false
  end
end

local function sameName(a, b)
  return type(a) == "string" and type(b) == "string" and a ~= "" and lower(a) == lower(b)
end

-- kill (FC_KILL: npcID, level, cls, by, name): same npcID or same name
handlers.FC_KILL = function(_, npcID, _, _, _, name)
  local id, nm = validMap(npcID), str(name)
  if not (id or nm) or not Store.ready() then return end
  local list = store()
  if not list then return end
  local any = false
  for _, p in ipairs(list) do
    if valid(p) and not p.done and kindOf(p) == "kill" and type(p.target) == "table" then
      local t = p.target
      if (id and validMap(t.id) == id) or (nm and sameName(t.name, nm)) then
        p.have = haveOf(p) + 1
        any = true
        if p.have >= needOf(p) then complete(p, "kill") end
      end
    end
  end
  if any then changed() end
end

-- loot (FC_LOOT: itemID, count, quality, kind, srcID, name): same itemID or same name, not bought/mailed
handlers.FC_LOOT = function(_, itemID, count, _, kind, _, name)
  if Plans.ITEM_SKIP[kind] or not Store.ready() then return end
  local id, nm = validMap(itemID), str(name)
  if not (id or nm) then return end
  local n = num(count)
  n = (n and n >= 1) and floor(n) or 1
  local list = store()
  if not list then return end
  local any = false
  for _, p in ipairs(list) do
    if valid(p) and not p.done and kindOf(p) == "item" and type(p.target) == "table" then
      local t = p.target
      if (id and validMap(t.id) == id) or (nm and sameName(t.name, nm)) then
        p.have = min(haveOf(p) + n, needOf(p))
        any = true
        if p.have >= needOf(p) then complete(p, "item") end
      end
    end
  end
  if any then changed() end
end

handlers.PLAYER_ENTERING_WORLD = scheduleCheck
handlers.ZONE_CHANGED = scheduleCheck
handlers.ZONE_CHANGED_INDOORS = scheduleCheck
handlers.ZONE_CHANGED_NEW_AREA = scheduleCheck

function Collector:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("Plans", Collector)
