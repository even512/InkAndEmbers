-- Preise (Werkauftrag, station 2 "Einkaufen"): auction prices of this session and the request queue, as pure logic (no events,
-- no client calls: everything the queue needs comes in as functions, journal/Preisabfrage.lua wires it to the game).
--   Preise.sum(results, n)        -> { total, got, short, unit (average), cheapest } | nil   (price for N over ALL offers, cheapest
--                                    first; per offer avail = quantity - numOwnerItems, take = min(avail, rest): the Blizzard rule
--                                    AuctionHouseUtil.AggregateSearchResultsByQuantity; own auctions are never bought)
--   Preise.put(itemID, kind, results) / Preise.get(itemID) / Preise.unit(itemID) / Preise.priceFor(itemID, n) / Preise.reset()
--     entry = { kind = "commodity" | "single" | "none" | "unknown", levels = { { unit, qty } } (cheapest first, at most LEVELS),
--               cheapest, at (GetTime of the result) }; "single" = no commodity (one auction each: price hint only, bought in
--               Blizzard's window); "unknown" = the item data never loaded or no answer came ("Preis unbekannt")
--   Preise.newQueue(deps)         -> queue: exactly one request in flight; before it the item data is loaded (at most LOAD_TRIES
--                                    tries, LOAD_WAIT seconds apart, else "unknown"); the next request only after the result and when
--                                    deps.ready() (IsThrottledMessageSystemReady) says yes; no result within RESULT_WAIT -> "unknown".
--     deps = { now() -> seconds, cached(id) -> bool, load(id), ready() -> bool, send(id) -> bool, done(id, entry) | nil }
--     queue:push(id) (dedupe), queue:tick(), queue:result(id, kind, results) -> stored?, queue:busy(), queue:clear(), queue:phase(id)
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Preise = {}
Journal.Preise = Preise

local floor, min, max = math.floor, math.min, math.max

Preise.LEVELS = 40          -- price levels kept per item
Preise.RESULTS_MAX = 200    -- result rows read per search
Preise.LOAD_TRIES = 3
Preise.LOAD_WAIT = 0.5      -- seconds between two item-data load tries
Preise.RESULT_WAIT = 5      -- seconds until a search result must have arrived
Preise.SEND_TRIES = 3
Preise.QUEUE_MAX = 60

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function posInt(v)
  v = num(v)
  if not v or v < 1 or v > 2147483647 then return nil end
  return floor(v)
end

local function nonNeg(v)
  v = num(v)
  if not v or v < 0 then return nil end
  return floor(v)
end

-- result rows -> price levels { { unit, qty } } (qty = what may be bought: quantity - numOwnerItems), cheapest first
function Preise.levels(results)
  local out = {}
  if type(results) ~= "table" or isSecret(results) then return out end
  for i, r in ipairs(results) do
    if i > Preise.RESULTS_MAX then break end
    if type(r) == "table" then
      local unit = posInt(r.unitPrice or r.unit or r.buyoutAmount)
      local qty = nonNeg(r.quantity or r.qty) or 0
      local own = nonNeg(r.numOwnerItems) or 0
      local avail = max(0, qty - own)
      if unit and avail > 0 then out[#out + 1] = { unit = unit, qty = avail } end
    end
  end
  table.sort(out, function(a, b) return a.unit < b.unit end)
  return out
end

function Preise.sum(results, n, sorted)
  n = posInt(n)
  if not n then return nil end
  local lv = sorted and results or Preise.levels(results)
  if #lv == 0 then return nil end
  local rest, total, got = n, 0, 0
  for _, l in ipairs(lv) do
    if rest <= 0 then break end
    local take = min(l.qty, rest)
    total = total + take * l.unit
    got = got + take
    rest = rest - take
  end
  return { total = total, got = got, short = rest, unit = got > 0 and total / got or nil, cheapest = lv[1].unit }
end

-- Session prices --------------------------------------------------------------------------------------------------------------------

local known = {}
Preise._known = known

local function clock()
  if type(GetTime) ~= "function" then return 0 end
  local ok, t = pcall(GetTime)
  return ok and num(t) or 0
end

function Preise.put(itemID, kind, results, at)
  itemID = posInt(itemID)
  if not itemID then return nil end
  local e = { kind = kind, at = num(at) or clock(), levels = {} }
  if kind == "commodity" or kind == "single" then
    local lv = Preise.levels(results)
    for i = 1, min(#lv, Preise.LEVELS) do e.levels[i] = lv[i] end
    e.cheapest = lv[1] and lv[1].unit or nil
    if #lv == 0 then e.kind = "none" end
  elseif kind ~= "none" then
    e.kind = "unknown"
  end
  known[itemID] = e
  return e
end

function Preise.get(itemID)
  return known[posInt(itemID) or 0]
end

-- cheapest unit price (any kind) | nil
function Preise.unit(itemID)
  local e = Preise.get(itemID)
  return e and e.cheapest or nil
end

-- price of n commodities -> total, got (got < n: not enough offered) | nil (no price)
function Preise.priceFor(itemID, n)
  local e = Preise.get(itemID)
  if not (e and e.kind == "commodity") then return nil end
  local s = Preise.sum(e.levels, n, true)
  if not s then return nil end
  return s.total, s.got
end

function Preise.reset()
  for k in pairs(known) do known[k] = nil end
end

-- Queue ----------------------------------------------------------------------------------------------------------------------------

local Queue = {}
Queue.__index = Queue

function Preise.newQueue(deps)
  deps = type(deps) == "table" and deps or {}
  return setmetatable({ deps = deps, list = {}, flight = nil, phases = {} }, Queue)
end

function Queue:push(id)
  id = posInt(id)
  if not id then return false end
  if self.phases[id] == "load" or self.phases[id] == "send" or self.phases[id] == "wait" then return false end
  if #self.list >= Preise.QUEUE_MAX then return false end
  self.list[#self.list + 1] = { id = id, phase = "load", tries = 0, sends = 0 }
  self.phases[id] = "load"
  return true
end

function Queue:phase(id) return self.phases[posInt(id) or 0] end
function Queue:busy() return self.flight ~= nil or #self.list > 0 end

function Queue:clear()
  self.list, self.flight = {}, nil
  for k in pairs(self.phases) do self.phases[k] = nil end
end

local function finish(self, id, entry)
  self.phases[id] = entry and entry.kind or "unknown"
  local done = self.deps.done
  if type(done) == "function" then pcall(done, id, entry) end
end

function Queue:tick()
  local d = self.deps
  local now = d.now and num(d.now()) or 0
  local f = self.flight
  if f then
    if now - f.sent < Preise.RESULT_WAIT then return "wait" end
    self.flight = nil
    finish(self, f.id, Preise.put(f.id, "unknown"))
  end
  while self.list[1] do
    local h = self.list[1]
    if h.phase == "load" then
      if d.cached and d.cached(h.id) then
        h.phase = "send"
        self.phases[h.id] = "send"
      elseif h.tries >= Preise.LOAD_TRIES then
        if now - (h.at or 0) < Preise.LOAD_WAIT then return "load" end
        table.remove(self.list, 1)
        finish(self, h.id, Preise.put(h.id, "unknown"))
      else
        if h.tries == 0 or now - (h.at or 0) >= Preise.LOAD_WAIT then
          h.tries = h.tries + 1
          h.at = now
          if d.load then pcall(d.load, h.id) end
        end
        return "load"
      end
    end
    if h.phase == "send" then
      if d.ready and not d.ready() then return "throttle" end
      local ok, sent = pcall(d.send, h.id)
      if ok and sent then
        table.remove(self.list, 1)
        self.flight = { id = h.id, sent = now }
        self.phases[h.id] = "wait"
        return "sent"
      end
      h.sends = h.sends + 1
      if h.sends >= Preise.SEND_TRIES then
        table.remove(self.list, 1)
        finish(self, h.id, Preise.put(h.id, "unknown"))
      else
        return "retry"
      end
    end
  end
  return "idle"
end

-- a result event: stored for any item (a search sends two events: the second one only refreshes); frees the queue for the next one
function Queue:result(id, kind, results)
  id = posInt(id)
  if not id then return false end
  local e = Preise.put(id, kind, results)
  if self.flight and self.flight.id == id then
    self.flight = nil
    finish(self, id, e)
  end
  return true
end
