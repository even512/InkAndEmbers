-- Collector 'Money': gold history, income/expenses by source/purpose, auction house.
-- PLAYER_MONEY gives no delta, so the last state is kept. Source/purpose come from open windows (ns.Context) and short hook hints (repair, flight, mail); otherwise 'other'.
-- A single repair has no hookable call: detected by an open merchant + InRepairMode() (approximation). Logout state in snapshots.state.money; a deviation at the next start is booked as 'gap'.
local _, ns = ...
local Core, Store, Patterns, Context = ns.Core, ns.Store, ns.Patterns, ns.Context

local floor, abs, min = math.floor, math.abs, math.min

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
  local ok, a, b, c = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c
end

local function callAll(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  table.remove(r, 1)
  return r
end

local function playerLevel()
  return num(call(UnitLevel, "player"))
end

local function active(name)
  return Context ~= nil and Context.active(name) == true
end

local MAILSEEN_NAME_MAX, MAILSEEN_PARTNER_MAX = 80, 60 -- bytes in the invoice key (the whole key stays under 250)
local REPAIR_TTL = 3     -- seconds: repair hint applies to the next expense
local TAXI_TTL = 4       -- seconds: flight hint (TakeTaxiNode)
local MAIL_TTL = 3       -- seconds: hint 'money taken from mail'
local MONEY_MSG_TTL = 3  -- seconds: loot money message (CHAT_MSG_MONEY) applies to the next income
local INBOX_MAX = 50
local AH_HOURS = { [1] = 12, [2] = 24, [3] = 48 }
local PENDING_TTL = 30   -- seconds: an auction action waits this long for its confirmation

local Money = {
  requires = { "GetMoney" },
  events = {
    "PLAYER_MONEY", "CHAT_MSG_MONEY", "MAIL_INBOX_UPDATE", "AUCTION_HOUSE_AUCTION_CREATED", "COMMODITY_PURCHASE_SUCCEEDED",
    "COMMODITY_PRICE_UPDATED", "PLAYER_LOGOUT",
  },
}
local handlers = {}

local function inRepairMode()
  return not isSecret(InRepairMode) and type(InRepairMode) == "function" and call(InRepairMode) == true
end

local function recent(t, ttl)
  return t ~= nil and GetTime() - t <= ttl
end

-- Source / purpose

-- Retail (Warband bank): gold moved between the purse and the account bank is a transfer, neither income nor expense. Forever has no
-- gold in the bank (a bought bank slot there stays an expense), so this only applies to a retail client. Unknown client = no.
local function retailClient()
  local ms = ns.Journal and ns.Journal.MapSpace
  if not (ms and type(ms.retailClient) == "function") then return false end
  local ok, r = pcall(ms.retailClient)
  return ok and r == true
end

local function classify(self, delta)
  if delta < 0 then
    if recent(self.repairAt, REPAIR_TTL) then return "repair" end
    if active("merchant") and inRepairMode() then return "repair" end -- single repair with the repair cursor
    if recent(self.taxiAt, TAXI_TTL) or active("taxi") then return "taxi" end
    if active("trainer") then return "training" end
    if active("merchant") then return "vendor_buy" end
    if active("ah") then return "ah" end
    if active("mail") then return "mail" end
    if active("trade") then return "trade" end
    if active("guildbank") then return "guildbank" end
    if active("bank") and retailClient() then return "warband" end
    return "other"
  end
  if recent(self.mailAt, MAIL_TTL) and self.mailSource then return self.mailSource end
  if active("merchant") then return "vendor_sell" end
  if active("ah") then return "ah" end
  if active("mail") then return "mail" end
  if active("trade") then return "trade" end
  if active("guildbank") then return "guildbank" end
  if active("bank") and retailClient() then return "warband" end
  if active("quest") then return "quest" end
  if active("loot") or recent(self.lootMsgAt, MONEY_MSG_TTL) then return "loot" end
  return "other"
end

local function writeChange(self, delta, balance, source)
  local mapID = ns.Zone.here()
  Store.append("GD", delta, balance, source, playerLevel(), mapID)
  if delta and delta ~= 0 then
    Store.count(delta > 0 and "money_in" or "money_out", source, abs(delta))
  end
end

local function savedBalance()
  local char = Store.char()
  local st = char and char.snapshots and char.snapshots.state
  local m = type(st) == "table" and st.money or nil
  return type(m) == "table" and num(m.balance) or nil
end

-- At a real logout the game APIs return 0 (GetMoney = 0), so only a plausible value is stored:
-- the freshly read one if > 0, else the last known (self.last; may legitimately be 0).
local function persist(self)
  local now = num(call(GetMoney))
  if now and now > 0 then
    now = floor(now)
  else
    now = self.last
  end
  if now then Store.putSnapshot("state", "money", { balance = now }, true) end
end

handlers.PLAYER_MONEY = function(self)
  local now = num(call(GetMoney))
  if not now then return end
  now = floor(now)
  local last = self.last
  self.last = now
  if last == nil then
    writeChange(self, nil, now, "start")
    return
  end
  local delta = now - last
  if delta == 0 then return end
  local source = classify(self, delta)
  -- transfer to/from the Warband bank: the balance is booked (holdings stay true), the amount counts as neither income nor
  -- expense (a line without delta, like 'start': the index and the counters skip it)
  if source == "warband" then delta = nil end
  writeChange(self, delta, now, source)
end

handlers.CHAT_MSG_MONEY = function(self, text)
  if isSecret(text) then
    Store.count("unreadable", "money_msg")
    return
  end
  self.lootMsgAt = GetTime()
end

handlers.PLAYER_LOGOUT = function(self)
  persist(self)
end

-- Hooks: repair, flight, mail

local function onMailTake(self, index)
  local inv = callAll(GetInboxInvoiceInfo, index)
  self.mailAt = GetTime()
  self.mailSource = (inv and str(inv[1]) == "seller") and "ah_sale" or "mail"
end

-- Auction house

local function ahLine(self, action, fields)
  fields = fields or {}
  local mapID = ns.Zone.here()
  Store.append("AH", action, fields.itemID, fields.name, fields.count, fields.price, fields.deposit, fields.hours,
    fields.partner, playerLevel(), mapID)
  Store.count("ah", action, fields.count or 1)
end

-- action with a confirmation event: held until the event arrives; if the client lacks the event, written at once.
local function eventKnown(event)
  local e = Core.collector("Money")
  return not (e and e.unknown and string.find(e.unknown, event, 1, true))
end

local function pendAh(self, key, event, action, fields)
  if not eventKnown(event) then return ahLine(self, action, fields) end
  fields.at = GetTime()
  self.pending[key] = { action = action, fields = fields }
end

local function settleAh(self, key)
  local p = self.pending[key]
  self.pending[key] = nil
  if p and recent(p.fields.at, PENDING_TTL) then ahLine(self, p.action, p.fields) end
end

local function itemIdOf(item)
  if item == nil then return nil end
  local id = num(call(C_Item and C_Item.GetItemID, item))
  return id and floor(id) or nil
end

local function onPostItem(self, item, duration, quantity, bid, buyout)
  local price = num(buyout)
  if not price or price <= 0 then price = num(bid) end
  local d = num(duration)
  pendAh(self, "post", "AUCTION_HOUSE_AUCTION_CREATED", "post", {
    itemID = itemIdOf(item), count = num(quantity), price = price, hours = d and AH_HOURS[floor(d)] or nil,
    deposit = num(call(C_AuctionHouse and C_AuctionHouse.CalculateItemDeposit, item, duration, quantity)),
  })
end

local function onPostCommodity(self, item, duration, quantity, unitPrice)
  local d = num(duration)
  pendAh(self, "post", "AUCTION_HOUSE_AUCTION_CREATED", "post", {
    itemID = itemIdOf(item), count = num(quantity), price = num(unitPrice), hours = d and AH_HOURS[floor(d)] or nil,
    deposit = num(call(C_AuctionHouse and C_AuctionHouse.CalculateCommodityDeposit, itemIdOf(item), duration, quantity)),
  })
end

local function onPlaceBid(self, auctionID, amount)
  ahLine(self, "bid", { price = num(amount) })
end

local function onConfirmPurchase(self, itemID, quantity)
  local unit = self.commodityUnit
  pendAh(self, "buy", "COMMODITY_PURCHASE_SUCCEEDED", "buy", { itemID = num(itemID), count = num(quantity), price = unit })
end

local function onCancel(self)
  ahLine(self, "cancel", {})
end

handlers.AUCTION_HOUSE_AUCTION_CREATED = function(self)
  settleAh(self, "post")
end

handlers.COMMODITY_PURCHASE_SUCCEEDED = function(self)
  settleAh(self, "buy")
end

handlers.COMMODITY_PRICE_UPDATED = function(self, unitPrice)
  self.commodityUnit = num(unitPrice)
end

-- Invoices in the mailbox: booked exactly once each (also across re-logins: snapshots.mailseen[key].n).
-- key: kind:name:partner:price:bid:quantity, each part sanitized (name/partner shortened, ':' replaced), numbers via Store.int; gone invoices leave mailseen (Store.dropSnapshot).
-- if a new key no longer fits under Store.LIMITS.mailseen, its state goes to self.seenMem (this session, diag.limits['mailseen.session']) so an invoice is never booked twice.
local function keyPart(v, max)
  local p = ns.Sanitize.cut(ns.Sanitize.field(str(v) or ""), max)
  return (string.gsub(p, ":", "/"))
end

local function invoiceKey(inv)
  return table.concat({
    inv[1],
    keyPart(inv[2], MAILSEEN_NAME_MAX),
    keyPart(inv[3], MAILSEEN_PARTNER_MAX),
    Store.int(floor(num(inv[4]) or 0)),
    Store.int(floor(num(inv[5]) or 0)),
    Store.int(floor(num(inv[11]) or 1)),
  }, ":")
end

handlers.MAIL_INBOX_UPDATE = function(self)
  local count = num(call(GetInboxNumItems))
  if not count or type(GetInboxInvoiceInfo) ~= "function" then return end
  local now, firstOf = {}, {}
  for i = 1, min(floor(count), INBOX_MAX) do
    local inv = callAll(GetInboxInvoiceInfo, i)
    local kind = inv and str(inv[1])
    if kind == "seller" or kind == "buyer" then
      local key = invoiceKey(inv)
      now[key] = (now[key] or 0) + 1
      firstOf[key] = firstOf[key] or inv
    end
  end
  local char = Store.char()
  local seenGroup = char and char.snapshots and char.snapshots.mailseen
  if type(seenGroup) ~= "table" then seenGroup = nil end
  for key, n in pairs(now) do
    local entry = seenGroup and seenGroup[key]
    local seen = (type(entry) == "table" and num(entry.n)) or self.seenMem[key] or 0
    if n > seen then
      local inv = firstOf[key]
      local price = num(inv[4])
      if not price or price <= 0 then price = num(inv[5]) end
      for _ = 1, n - seen do
        ahLine(self, inv[1] == "seller" and "sold" or "bought", {
          name = str(inv[2]), partner = str(inv[3]), price = price, deposit = num(inv[7]), count = num(inv[11]),
        })
      end
    end
    if n ~= seen then
      if Store.putSnapshot("mailseen", key, { n = n }, true) then
        self.seenMem[key] = nil
      else
        self.seenMem[key] = n
        Store.noteLimit("mailseen.session")
      end
    end
  end
  -- invoices no longer in the mailbox: remove the entry (a later identical invoice is new)
  if seenGroup then
    local gone
    for key in pairs(seenGroup) do
      if now[key] == nil then
        gone = gone or {}
        gone[#gone + 1] = key
      end
    end
    if gone then
      for _, key in ipairs(gone) do Store.dropSnapshot("mailseen", key) end
    end
  end
  for key in pairs(self.seenMem) do
    if now[key] == nil then self.seenMem[key] = nil end
  end
end


function Money:init()
  self.pending = {}
  self.seenMem = {}
  local now = num(call(GetMoney))
  self.last = now and floor(now) or nil
  if self.last then
    local saved = savedBalance()
    if saved == nil then
      writeChange(self, nil, self.last, "start")
    elseif floor(saved) <= 0 and self.last > 0 then
      writeChange(self, nil, self.last, "start") -- 0 balance from logout: no gap over the whole balance
      persist(self)
    elseif floor(saved) ~= self.last then
      writeChange(self, self.last - floor(saved), self.last, "gap")
    end
  end
  Core.hook(self, "RepairAllItems", function(s) s.repairAt = GetTime() end)
  Core.hook(self, "TakeTaxiNode", function(s) s.taxiAt = GetTime() end)
  Core.hook(self, "TakeInboxMoney", onMailTake)
  Core.hook(self, "AutoLootMailItem", onMailTake)
  local AH = C_AuctionHouse
  if type(AH) == "table" and not isSecret(AH) then
    Core.hook(self, AH, "PostItem", onPostItem)
    Core.hook(self, AH, "PostCommodity", onPostCommodity)
    Core.hook(self, AH, "PlaceBid", onPlaceBid)
    Core.hook(self, AH, "ConfirmCommoditiesPurchase", onConfirmPurchase)
    Core.hook(self, AH, "CancelAuction", onCancel)
  end
end

function Money:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("Money", Money)
