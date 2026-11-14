-- Auction house table (sub-bookmark "Auktionshaus" of the Schaetze page): every invoice of the auction house (AH lines
-- sold/bought, kept as records by journal/model/Index.lua) becomes one table row: date, kind, item, quantity, price in total
-- and per piece. Sorting, filter (all/sales/purchases) and sums are pure functions on the rows (tested without the page).
-- Computed at display time, no new SV or index fields. Auktionshaus.build(index) -> book = { rows, total, pending, sold, bought }.
-- Items: the invoice often carries only the name; the itemID is looked up by that name (item snapshot, then the client) so the
-- row can show the original item tooltip. Names are only shown sanitized (Sanitize.display). Auktionshaus.source replaces the client
-- API in tests, Auktionshaus.rowsSource(index) replaces the whole data source (tests, preview).
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Auktionshaus = {}
Journal.Auktionshaus = Auktionshaus

local floor, huge = math.floor, math.huge
local format, find, gsub, lower = string.format, string.find, string.gsub, string.lower

Auktionshaus.NAME_MAX = 48     -- bytes per item name
Auktionshaus.ROW_MAX = 20000   -- invoices read (like Index.LIST_MAX)
Auktionshaus.COUNT_MAX = 1000000
Auktionshaus.PRICE_MAX = 1e12  -- copper (100 million gold): everything above counts as unreadable
Auktionshaus.source = nil
Auktionshaus.rowsSource = nil

-- locale scope "m.Auktionshaus" (English in locales/enUS_model.lua)
local Loc = ns.Locale
local TEXT = Loc.ns("m.Auktionshaus", {
  kind_sold = "Verkauf", kind_bought = "Kauf",
  itemFallback = "Unbekannter Gegenstand", itemNo = "Gegenstand #%s",
  dateTime = "{d}.{m}. {H}:{M}", dateOnly = "{d}.{m}.", dateUnknown = "–",
  sumAll = "Saldo", sumSold = "Summe Verkäufe", sumBought = "Summe Käufe",
})
Auktionshaus.TEXT = TEXT

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function finite(v)
  return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local function display(v, n)
  local S = ns.Sanitize
  if isSecret(v) or type(v) ~= "string" then return nil end
  return S and S.display(v, n) or nil
end

local function posId(v)
  if isSecret(v) then return nil end
  if type(v) == "string" then
    if not find(v, "^%d+$") or #v > 10 then return nil end
    v = tonumber(v)
  end
  if not finite(v) or v <= 0 or v >= 2147483648 or v ~= floor(v) then return nil end
  return v
end

local function rawName(e)
  if type(e) == "table" then e = e.name end
  if isSecret(e) or type(e) ~= "string" or e == "" or e == "?" then return nil end
  return e
end

local function resolve(path)
  local src = Auktionshaus.source
  if type(src) == "table" then
    local f = src[path]
    return type(f) == "function" and f or nil
  end
  local v = _G
  for part in string.gmatch(path, "[^%.]+") do
    if type(v) ~= "table" then return nil end
    v = v[part]
  end
  return type(v) == "function" and v or nil
end

local function call(path, ...)
  local f = resolve(path)
  if not f then return nil end
  local ok, a = pcall(f, ...)
  if not ok then return nil end
  return a
end

-- name of an item from the client (raw; display only via display)
local function clientName(itemID)
  local n = call("C_Item.GetItemNameByID", itemID)
  if isSecret(n) or type(n) ~= "string" or n == "" then return nil end
  return n
end

-- itemID of a name from the client (cached items only); nil if unknown
local function clientId(name)
  local id = call("C_Item.GetItemInfoInstant", name)
  return posId(id)
end

-- "13.11." (short, for the column) and "13.11. 14:05" (full, for the tooltip) in the character's local time
-- (Index.dateOf/timeOfDay); nil without a usable time
local function whenText(index, t)
  local I = Journal.Index
  if not (I and finite(t)) then return nil end
  local d, m = I.dateOf(index, t)
  if not d then return nil end
  local h, mi = I.timeOfDay(index, t)
  local map = { d = format("%02d", d), m = format("%02d", m) }
  local short = gsub(TEXT.dateOnly, "{(%a)}", map)
  if not h then return short, short end
  map.H, map.M = format("%02d", h), format("%02d", mi)
  return short, (gsub(TEXT.dateTime, "{(%a)}", map))
end

-- positive whole number inside the limit, else nil
local function amount(v, limit)
  if type(v) == "string" then
    if v == "" or v == "?" then return nil end
    v = tonumber(v)
  end
  if isSecret(v) or not finite(v) or v < 0 or v > limit then return nil end
  return floor(v)
end

-- raw entries { id, t, kind = "sold"|"bought", itemID?, name?, count?, price?, fee? } from the index
local function entriesOf(index)
  local I = Journal.Index
  local out = {}
  local seen = 0
  for _, rec in ipairs(I.list(index, "AH")) do
    seen = seen + 1
    if seen > Auktionshaus.ROW_MAX then break end
    local action = I.str(rec, "AH", "action")
    if action == "sold" or action == "bought" then
      out[#out + 1] = { id = rec.ln or seen, t = rec.t, kind = action, itemID = posId(I.str(rec, "AH", "itemID")),
        name = I.str(rec, "AH", "name"), count = I.num(rec, "AH", "count"), price = I.num(rec, "AH", "price"),
        fee = I.num(rec, "AH", "deposit") }
    end
  end
  return out
end

local function buildBook(index)
  local char = type(index.char) == "table" and index.char or {}
  local snaps = type(char.snapshots) == "table" and char.snapshots or {}
  local items = type(snaps.items) == "table" and snaps.items or nil
  local book = { rows = {}, pending = {}, sold = { n = 0, qty = 0, price = 0, fee = 0 }, bought = { n = 0, qty = 0, price = 0, fee = 0 } }
  local entries = type(Auktionshaus.rowsSource) == "function" and Auktionshaus.rowsSource(index) or entriesOf(index)
  -- name -> itemID from the item snapshot, built once and only if a name is needed
  local byName
  local function idByName(name)
    if not byName then
      byName = {}
      if items then
        for id, e in pairs(items) do
          local n = rawName(e)
          local pid = posId(id)
          if n and pid and byName[n] == nil then byName[n] = pid end
        end
      end
    end
    return byName[name] or clientId(name)
  end
  local names = {}
  for i, e in ipairs(type(entries) == "table" and entries or {}) do
    if i > Auktionshaus.ROW_MAX then break end
    if type(e) == "table" and (e.kind == "sold" or e.kind == "bought") then
      local raw = (type(e.name) == "string" and not isSecret(e.name) and e.name ~= "" and e.name ~= "?") and e.name or nil
      local itemID = posId(e.itemID) or (raw and idByName(raw)) or nil
      local count = amount(e.count, Auktionshaus.COUNT_MAX)
      if not count or count < 1 then count = 1 end
      local price = amount(e.price, Auktionshaus.PRICE_MAX)
      local row = { id = e.id or i, t = finite(e.t) and e.t or nil, kind = e.kind, itemID = itemID, count = count, price = price,
        fee = amount(e.fee, Auktionshaus.PRICE_MAX) }
      if price and price > 0 then row.unit = floor(price / count + 0.5) end
      row.when, row.whenFull = whenText(index, row.t)
      row.kindText = TEXT["kind_" .. e.kind]
      if itemID then
        row.link = Journal.Texts and Journal.Texts.itemString(itemID) or nil
        local nm = names[itemID]
        if nm == nil then
          local snap = items and (items[itemID] or items[format("%.0f", itemID)])
          nm = display(rawName(snap), Auktionshaus.NAME_MAX) or display(clientName(itemID), Auktionshaus.NAME_MAX) or display(raw, Auktionshaus.NAME_MAX) or false
          names[itemID] = nm
        end
        row.name = nm or nil
        if not nm then book.pending[itemID] = true end
      else
        row.name = raw and display(raw, Auktionshaus.NAME_MAX) or nil
      end
      book.rows[#book.rows + 1] = row
      local s = book[e.kind]
      s.n = s.n + 1
      s.qty = s.qty + count
      if price then s.price = s.price + price end
      if row.fee then s.fee = s.fee + row.fee end
    end
  end
  book.total = #book.rows
  return book
end

local cache = setmetatable({}, { __mode = "k" })

function Auktionshaus.build(index, fresh)
  if type(index) ~= "table" then
    return { rows = {}, pending = {}, total = 0, sold = { n = 0, qty = 0, price = 0, fee = 0 }, bought = { n = 0, qty = 0, price = 0, fee = 0 } }
  end
  local book = not fresh and cache[index] or nil
  if not book then
    book = buildBook(index)
    cache[index] = book
  end
  return book
end

function Auktionshaus.label(row)
  if row.name then return row.name end
  if row.itemID then return TEXT("itemNo", format("%.0f", row.itemID)) end
  return TEXT.itemFallback
end

-- re-read names for book.pending (the client may have loaded them since); asks the client once for the missing ones
function Auktionshaus.resolve(book, request)
  if type(book) ~= "table" or type(book.pending) ~= "table" then return 0 end
  local found, n = {}, 0
  for id in pairs(book.pending) do
    local name = display(clientName(id), Auktionshaus.NAME_MAX)
    if name then
      found[id] = name
      n = n + 1
    elseif request then
      call("C_Item.RequestLoadItemDataByID", id)
    end
  end
  if n > 0 then
    for id in pairs(found) do book.pending[id] = nil end
    for _, row in ipairs(book.rows) do
      if not row.name and row.itemID and found[row.itemID] then row.name = found[row.itemID] end
    end
  end
  return n
end

Auktionshaus.FILTERS = { all = true, sold = true, bought = true }
Auktionshaus.SORTS = { time = true, kind = true, item = true, count = true, price = true, unit = true }

local function sortValue(row, key)
  if key == "kind" then return row.kind end
  if key == "item" then return lower(Auktionshaus.label(row)) end
  if key == "count" then return row.count end
  if key == "price" then return row.price end
  if key == "unit" then return row.unit end
  return nil
end

-- rows of the book: filter (all/sold/bought), sorted by key (default time, newest first). Rows without a value of the sort key go last,
-- ties by time (newest first) and line number: the order is stable and does not depend on the sort algorithm.
function Auktionshaus.list(book, opts)
  opts = type(opts) == "table" and opts or {}
  local key = Auktionshaus.SORTS[opts.sort] and opts.sort or "time"
  local filter = Auktionshaus.FILTERS[opts.filter] and opts.filter or "all"
  local desc = opts.desc
  if desc == nil then desc = key == "time" end
  local out = {}
  for _, row in ipairs(type(book) == "table" and book.rows or {}) do
    if filter == "all" or row.kind == filter then out[#out + 1] = row end
  end
  local function newer(a, b)
    local ta, tb = a.t or 0, b.t or 0
    if ta ~= tb then return ta > tb end
    return a.id > b.id
  end
  table.sort(out, function(a, b)
    if key == "time" then
      local ta, tb = a.t or 0, b.t or 0
      if ta ~= tb then
        if desc then return ta > tb end
        return ta < tb
      end
      if desc then return a.id > b.id end
      return a.id < b.id
    end
    local va, vb = sortValue(a, key), sortValue(b, key)
    if va ~= vb then
      if va == nil then return false end
      if vb == nil then return true end
      if desc then return va > vb end
      return va < vb
    end
    return newer(a, b)
  end)
  return out
end

-- sums over listed rows. Filter all: balance (sales minus purchases, may be negative), otherwise the sum of the kind.
-- Result: { filter, label, n, qty (nil for all), price (copper, signed), unit (average per piece, nil for all or without price),
--   sold = { n, price }, bought = { n, price } }
function Auktionshaus.sum(rows, filter)
  filter = Auktionshaus.FILTERS[filter] and filter or "all"
  local out = { filter = filter, n = 0, qty = 0, sold = { n = 0, price = 0 }, bought = { n = 0, price = 0 } }
  local priced = 0
  for _, r in ipairs(type(rows) == "table" and rows or {}) do
    out.n = out.n + 1
    out.qty = out.qty + (r.count or 1)
    local s = out[r.kind]
    if s then
      s.n = s.n + 1
      if r.price then
        s.price = s.price + r.price
        if r.price > 0 then priced = priced + (r.count or 1) end
      end
    end
  end
  if filter == "all" then
    out.label = TEXT.sumAll
    out.price = out.sold.price - out.bought.price
    out.qty = nil
  else
    out.label = filter == "sold" and TEXT.sumSold or TEXT.sumBought
    out.price = out[filter].price
    if priced > 0 and out.price > 0 then out.unit = floor(out.price / priced + 0.5) end
  end
  return out
end
