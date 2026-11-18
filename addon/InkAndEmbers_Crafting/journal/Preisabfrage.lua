-- Preisabfrage (Werkauftrag, station 2): the thin game layer of the price queue (journal/model/Preise.lua holds the logic). While
-- the auction house is open, Preisabfrage.request({ itemID, ... }) asks the prices of the materials one after the other without a
-- click (searches need no hardware event; probe 17.11.: answer 0.1-0.4 s, two result events per search; a search for an item whose
-- data is not loaded is dropped silently, so the data is loaded first: C_Item.RequestLoadItemDataByID).
--   * one request in flight, the next one after its result event and C_AuctionHouse.IsThrottledMessageSystemReady() (or
--     AUCTION_HOUSE_THROTTLED_SYSTEM_READY); a small own ticker (Preisabfrage.TICK) runs only while the queue is busy;
--   * results: COMMODITY_SEARCH_RESULTS_UPDATED (itemID) -> every offer (GetNumCommoditySearchResults + GetCommoditySearchResultInfo),
--     ITEM_SEARCH_RESULTS_UPDATED (itemKey) -> single auctions (price hint only);
--   * prices count for the visit at the house ("Preise von eben · neu holen": Preisabfrage.refresh); closing the house stops the
--     queue, opening it again forgets the old prices (Preise.reset).
-- Listeners: Preisabfrage.onChange(fn) -> fn(itemID, entry) after each answer (the dock redraws). Never buys anything; all calls in
-- pcall. Without C_AuctionHouse (Retail without the module, tests) it does nothing.
local _, ns = ...

local Journal = ns.Journal
local Preise = Journal and Journal.Preise
if not (Journal and Preise) then return end

local floor = math.floor

local PA = {}
Journal.Preisabfrage = PA

PA.TICK = 0.1
PA.EVENTS = { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
  "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" }

local st = { open = false, ticker = nil, listeners = {} }
PA.state = st

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

local function ah(name)
  local t = rawget(_G, "C_AuctionHouse")
  local f = type(t) == "table" and not isSecret(t) and t[name] or nil
  return type(f) == "function" and f or nil
end

local function field(t, k)
  if type(t) ~= "table" or isSecret(t) then return nil end
  local ok, v = pcall(function() return t[k] end)
  if not ok or isSecret(v) then return nil end
  return v
end

local function now()
  if type(GetTime) ~= "function" then return 0 end
  local ok, t = pcall(GetTime)
  return ok and num(t) or 0
end

-- deps of the queue against the game
local deps = {
  now = now,
  cached = function(id)
    local ci = rawget(_G, "C_Item")
    local f = type(ci) == "table" and ci.IsItemDataCachedByID or nil
    if type(f) ~= "function" then return true end
    local ok, v = pcall(f, id)
    return ok and v == true
  end,
  load = function(id)
    local ci = rawget(_G, "C_Item")
    local f = type(ci) == "table" and ci.RequestLoadItemDataByID or nil
    if type(f) == "function" then pcall(f, id) end
  end,
  ready = function()
    local f = ah("IsThrottledMessageSystemReady")
    if not f then return true end
    local ok, v = pcall(f)
    return not ok or v ~= false
  end,
  send = function(id)
    local make, send = ah("MakeItemKey"), ah("SendSearchQuery")
    if not (st.open and make and send) then return false end
    local ok, key = pcall(make, id)
    if not ok or type(key) ~= "table" then return false end
    local sorts = {}
    local E2 = rawget(_G, "Enum")
    local order = type(E2) == "table" and type(E2.AuctionHouseSortOrder) == "table" and E2.AuctionHouseSortOrder.Price or nil
    if order ~= nil then sorts = { { sortOrder = order, reverseSort = false } } end
    return (pcall(send, key, sorts, false))
  end,
  done = function(id, entry)
    for _, fn in ipairs(st.listeners) do pcall(fn, id, entry) end
  end,
}

local queue = Preise.newQueue(deps)
PA.queue = queue

local function stopTicker()
  if st.ticker then
    pcall(st.ticker.Cancel, st.ticker)
    st.ticker = nil
  end
end

local function step()
  queue:tick()
  if not queue:busy() then stopTicker() end
end

local function startTicker()
  if st.ticker or type(C_Timer) ~= "table" or type(C_Timer.NewTicker) ~= "function" then return end
  local ok, h = pcall(C_Timer.NewTicker, PA.TICK, step)
  if ok then st.ticker = h end
end

function PA.onChange(fn)
  if type(fn) ~= "function" then return false end
  for _, f in ipairs(st.listeners) do if f == fn then return false end end
  st.listeners[#st.listeners + 1] = fn
  return true
end

-- asks the prices of these items (only those not known in this session, unless force) -> number queued
function PA.request(ids, force)
  if not st.open or type(ids) ~= "table" then return 0 end
  local n = 0
  for _, id in ipairs(ids) do
    id = posInt(id)
    if id and (force or not Preise.get(id)) and queue:push(id) then n = n + 1 end
  end
  if n > 0 then
    step()
    if queue:busy() then startTicker() end
  end
  return n
end

-- "neu holen": the prices of these items again
function PA.refresh(ids)
  return PA.request(ids, true)
end
function PA.busy() return queue:busy() end
function PA.get(id) return Preise.get(id) end

local function commodityRows(id)
  local info = ah("GetCommoditySearchResultInfo")
  if not info then return {} end
  local countFn = ah("GetNumCommoditySearchResults")
  local n
  if countFn then
    local ok, v = pcall(countFn, id)
    n = ok and posInt(v) or 0
  end
  local rows = {}
  for i = 1, n or Preise.RESULTS_MAX do
    if i > Preise.RESULTS_MAX then break end
    local ok, r = pcall(info, id, i)
    if not ok or type(r) ~= "table" then break end
    rows[#rows + 1] = { unitPrice = num(field(r, "unitPrice")), quantity = num(field(r, "quantity")), numOwnerItems = num(field(r, "numOwnerItems")) }
  end
  return rows
end

local function itemRows(key)
  local countFn, info = ah("GetNumItemSearchResults"), ah("GetItemSearchResultInfo")
  if not (countFn and info) then return {} end
  local ok, n = pcall(countFn, key)
  n = ok and posInt(n) or 0
  local rows = {}
  for i = 1, math.min(n, Preise.RESULTS_MAX) do
    local ok2, r = pcall(info, key, i)
    if ok2 and type(r) == "table" then
      rows[#rows + 1] = { unitPrice = num(field(r, "buyoutAmount")), quantity = 1, numOwnerItems = field(r, "containsOwnerItem") == true and 1 or 0 }
    end
  end
  return rows
end

local function onEvent(_, event, arg1)
  if event == "AUCTION_HOUSE_SHOW" then
    st.open = true
    Preise.reset()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    st.open = false
    queue:clear()
    stopTicker()
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    local id = posInt(arg1)
    if id and (queue:phase(id) == "wait" or Preise.get(id)) then
      queue:result(id, "commodity", commodityRows(id))
      step()
    end
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    local id = posInt(field(arg1, "itemID"))
    if id and queue:phase(id) == "wait" then
      queue:result(id, "single", itemRows(arg1))
      step()
    end
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    if queue:busy() then step() end
  end
end
PA._onEvent = onEvent

local function boot()
  if type(CreateFrame) ~= "function" then return end
  local ok, f = pcall(CreateFrame, "Frame")
  if not ok or not f then return end
  for _, e in ipairs(PA.EVENTS) do pcall(f.RegisterEvent, f, e) end
  f:SetScript("OnEvent", onEvent)
  PA.frame = f
end
boot()
