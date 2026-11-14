-- Docking window at the Blizzard auction house (WoW Forever only; Retail has no recipe cache, the window never exists there): a small
-- plate beside AuctionHouseFrame with the materials that are still missing for all open shopping lists (collectors/Einkaufszettel.lua
-- ns.Einkauf, read only): per list the missing materials (needed - bags, bank only as a hint) with item icon and the original item
-- tooltip, and per material two buttons:
--   "Suchen"  : C_AuctionHouse.MakeItemKey + SendSearchQuery for exactly this item (the result arrives as COMMODITY_SEARCH_RESULTS_UPDATED
--               or ITEM_SEARCH_RESULTS_UPDATED; the cheapest unit price is read and shown in the row);
--   "Kaufen (N)": only for commodities (stackable goods), only after the search of this item: StartCommoditiesPurchase(itemID, N); the
--               window shows "N× Name für <Preis> - Bestätigen?" as soon as COMMODITY_PRICE_UPDATED brings the price; only a SECOND click
--               ("Bestätigen") calls ConfirmCommoditiesPurchase. Never automatic, never without a displayed price; "Abbrechen" calls
--               CancelCommoditiesPurchase. Single auctions get only "Suchen".
-- If the game blocks a call (pcall error, ADDON_ACTION_BLOCKED in Core.actionLog) or COMMODITY_PURCHASE_FAILED comes, "Kaufen" is off for the
-- rest of the session (AD.buyBlocked), the hint says so and only "Suchen" stays. After a purchase BAG_UPDATE_DELAYED recounts the lists.
--
-- Taint rules (everything towards Blizzard's frames is READ ONLY, exactly like journal/ProfessionBar.lua):
--   * the dock is a frame of UIParent; only a SetPoint anchors it to AuctionHouseFrame, and only outside combat (in combat nothing is built
--     or moved);
--   * no HookScript / SetScript / hooksecurefunc on a Blizzard frame, no write into a Blizzard frame or table, no Show/Hide on it;
--   * the window is found lazily (rawget(_G, "AuctionHouseFrame"): Blizzard_AuctionHouseUI loads on demand; ADDON_LOADED and
--     AUCTION_HOUSE_SHOW wake the dock); visibility: AUCTION_HOUSE_SHOW / AUCTION_HOUSE_CLOSED plus a light poll of AuctionHouseFrame:IsShown()
--     while the house is open (the poll frame is our own and stays hidden, no OnUpdate, while it is closed).
-- Option "auctionDock" (Pages setting, default on; Options: "Einkaufszettel am Auktionshaus").
local _, ns = ...

local Journal = ns.Journal
local W = Journal and Journal.Widgets
local E = ns.Einkauf
if not (Journal and W and E) then return end

local floor, max, min = math.floor, math.max, math.min

local AD = {}
Journal.AuctionDock = AD

AD.NAME = "EveNChronicleAuctionDock"
AD.WINDOW = "AuctionHouseFrame"
AD.W = 320              -- width of the dock
AD.PAD = 10
AD.GAP = 3              -- distance to the window
AD.POLL = 0.25          -- seconds between two looks at the window while the house is open
AD.GRACE = 3            -- seconds after AUCTION_HOUSE_SHOW in which a not yet visible window is waited for
AD.ROWS_MAX = 10        -- material rows shown
AD.HEADS_MAX = 4        -- lists shown
AD.ROW_H = 31
AD.HEAD_H = 17
AD.BUY_MAX = 99999      -- most items of one purchase
AD.PRICE_WAIT = 8       -- seconds until a price must have arrived
AD.BUY_WAIT = 15        -- seconds until the result of a confirmed purchase must have arrived
AD.EVENTS = {
  "ADDON_LOADED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGIN",
  "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
  "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "ITEM_KEY_ITEM_INFO_RECEIVED",
}
AD.COLORS = {
  bg = { 0.024, 0.031, 0.047, 0.86 }, edge = { 0.91, 0.78, 0.48, 0.55 },
  head = { 0.91, 0.78, 0.48 }, text = { 0.96, 0.93, 0.85 }, dim = { 0.74, 0.70, 0.62 },
  need = { 0.96, 0.62, 0.50 }, ok = { 0.62, 0.84, 0.52 }, hover = { 1, 0.93, 0.7 },
  btn = { 0.91, 0.78, 0.48, 0.20 }, btnHover = { 0.91, 0.78, 0.48, 0.38 },
}

AD.TEXT = ns.Locale.ns("AuctionDock", {
  head = "EINKAUFSZETTEL",
  allDone = "Alle Materialien sind da.",
  listHead = "%s× %s",
  need = "fehlt %s",
  bank = "Bank: %s",
  price = "ab %s",
  search = "Suchen",
  searchTip = "Sucht diesen Gegenstand im Auktionshaus und zeigt hier das billigste Angebot.",
  buy = "Kaufen (%s)",
  buyTip = "Holt den Gesamtpreis für %s×. Gekauft wird erst, wenn Ihr danach „Bestätigen“ klickt.",
  buyNeedSearch = "Erst „Suchen“ klicken: Der Kauf braucht die Angebotsliste dieses Gegenstands.",
  buyBusy = "Es läuft schon ein Kauf.",
  single = "Einzelauktion: Kaufen im Auktionshaus-Fenster.",
  unitFrom = "Billigstes Angebot: %s je Stück",
  tipNeed = "Benötigt: %s",
  tipHave = "In den Taschen: %s",
  tipMissing = "Fehlt: %s",
  tipBank = "In der Bank: %s",
  priceWait = "Preis für %s× %s wird geholt …",
  confirm = "%s× %s für %s – Bestätigen?",
  changed = "Der Preis hat sich geändert.",
  noGold = "Dafür reicht das Gold nicht.",
  confirmBtn = "Bestätigen",
  cancelBtn = "Abbrechen",
  buying = "Kauf läuft …",
  bought = "%s× %s gekauft.",
  unavailable = "Dazu gibt es kein Angebot in dieser Menge.",
  failed = "Der Kauf hat nicht geklappt. „Kaufen“ ist bis zum nächsten Neuladen aus, „Suchen“ geht weiter.",
  blocked = "Das Spiel sperrt das Kaufen von hier. „Suchen“ geht weiter, gekauft wird im Auktionshaus-Fenster.",
  blockedNote = "Kaufen ist gesperrt, nur „Suchen“.",
  busy = "Das Auktionshaus ist gerade beschäftigt. Gleich noch einmal.",
  noSearch = "Die Suche ist hier nicht möglich.",
  noPrice = "Es kam kein Preis an. Der Kauf wurde abgebrochen.",
  unknownResult = "Kein Ergebnis gemeldet. Schaut in die Taschen.",
  more = "… %s weitere",
  optLabel = "Einkaufszettel am Auktionshaus",
  optTip = "Ein kleines Fenster am Auktionshaus mit den fehlenden Materialien aller offenen Einkaufszettel: „Suchen“ und Waren schnell kaufen (nur WoW Forever). Gekauft wird erst nach einem zweiten Klick, mit angezeigtem Preis.",
})
local T = AD.TEXT

-- state: frame, open (house is open), resultsFor (item id whose commodity results are the current search), commodity[id] = true | false
-- (known kind), unit[id] = cheapest unit price, buy = { id, n, name, state = "price" | "confirm" | "buying", unit, total, shown, deadline }
local st = { open = false, commodity = {}, unit = {}, poll = 0, sig = nil, placeSig = nil, msg = nil, dirty = false }
AD.state = st
AD.buyBlocked = false

-- Reading helpers ----------------------------------------------------------------------------------------------------------------

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

local function safe(fn, ...)
  if ns.Core and ns.Core.safe then return ns.Core.safe(fn, ...) end
  return pcall(fn, ...)
end

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return not ok or isSecret(v) or v == true
end

local function now()
  if type(GetTime) ~= "function" then return 0 end
  local ok, t = pcall(GetTime)
  return ok and num(t) or 0
end

-- guarded field read of a foreign table
local function field(t, k)
  if type(t) ~= "table" or isSecret(t) then return nil end
  local ok, v = pcall(function() return t[k] end)
  if not ok or isSecret(v) then return nil end
  return v
end

-- result of a foreign method under pcall (read only)
local function method(obj, name, ...)
  if type(obj) ~= "table" or isSecret(obj) then return nil end
  local f = field(obj, name)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(f, obj, ...)
  if not ok or isSecret(a) then return nil end
  return a, b, c, d
end

local function int(n) return Journal.Texts and Journal.Texts.int and Journal.Texts.int(n) or tostring(floor(tonumber(n) or 0)) end

local function money(c)
  local Tx = Journal.Texts
  if Tx and Tx.money then return Tx.money(c, "compact") end
  return tostring(floor(tonumber(c) or 0))
end

local function pageSetting()
  local P = Journal.Pages
  if not (P and type(P.setting) == "function") then return true end
  return P.setting("auctionDock") ~= false
end

function AD.setting() return pageSetting() end

function AD.enabled()
  return E.active() and pageSetting()
end

function AD.setEnabled(on)
  local P = Journal.Pages
  if P and type(P.setSetting) == "function" then P.setSetting("auctionDock", on and true or false) end
  AD.update()
end

-- Blizzard's window (nil as long as Blizzard_AuctionHouseUI is not loaded)
local function window()
  local w = rawget(_G, AD.WINDOW)
  if type(w) ~= "table" or isSecret(w) then return nil end
  return w
end

local function windowShown()
  local w = window()
  return w ~= nil and method(w, "IsShown") == true
end

-- the auction house API table (nil without it)
local function api()
  local a = rawget(_G, "C_AuctionHouse")
  if type(a) ~= "table" or isSecret(a) then return nil end
  return a
end

local function apiFn(name)
  local a = api()
  local f = a and field(a, name)
  return type(f) == "function" and f or nil
end

function AD.canSearch() return apiFn("MakeItemKey") ~= nil and apiFn("SendSearchQuery") ~= nil end

function AD.canBuy()
  return not AD.buyBlocked and apiFn("StartCommoditiesPurchase") ~= nil and apiFn("ConfirmCommoditiesPurchase") ~= nil
    and apiFn("CancelCommoditiesPurchase") ~= nil
end

local function itemIcon(id)
  local fn = C_Item and C_Item.GetItemIconByID
  if type(fn) == "function" then
    local ok, icon = pcall(fn, id)
    if ok and not isSecret(icon) and (type(icon) == "number" or type(icon) == "string") then return icon end
  end
  return 134400 -- question mark
end

-- Content (pure data) ----------------------------------------------------------------------------------------------------------------

-- { lists = { { id, title, rows = { { id, name, need, have, missing, bank } } } }, open = number of open lists, hidden = rows not shown }
-- The bag count of an item is handed out list by list (what one list covers is not counted again for the next), so the missing amounts
-- of all lists add up to what is really still to buy.
function AD.content()
  local c = { lists = {}, open = 0 }
  local P = ns.Plans
  local list = P and P.rawList and P.rawList()
  if type(list) ~= "table" then return c end
  local pool = {}
  for _, p in ipairs(list) do
    if type(p) == "table" and not p.done and type(p.shop) == "table" then
      c.open = c.open + 1
      local status = E.status(p.shop)
      if status then
        local rows = {}
        for _, r in ipairs(status.lines) do
          local avail = pool[r.id]
          if avail == nil then avail = r.have end
          local use = min(avail, r.need)
          pool[r.id] = avail - use
          local missing = r.need - use
          if missing > 0 then
            rows[#rows + 1] = { id = r.id, name = r.name, need = r.need, have = use, missing = missing, bank = r.bank or 0 }
          end
        end
        if #rows > 0 then
          local count = posInt(p.shop.count) or 1
          local name = type(p.shop.name) == "string" and p.shop.name or "?"
          c.lists[#c.lists + 1] = { id = p.id, title = T("listHead", int(count), name), rows = rows }
        end
      end
    end
  end
  return c
end

-- kind of an item: true = commodity, false = single auction, nil = not known (yet); read from the game's item key info once
local function commodityKind(id)
  local known = st.commodity[id]
  if known ~= nil then return known end
  local make, info = apiFn("MakeItemKey"), apiFn("GetItemKeyInfo")
  if not (make and info) then return nil end
  local ok, key = pcall(make, id)
  if not ok or type(key) ~= "table" or isSecret(key) then return nil end
  local ok2, res = pcall(info, key)
  if not ok2 or type(res) ~= "table" or isSecret(res) then return nil end
  local v = field(res, "isCommodity")
  if v == true or v == false then
    st.commodity[id] = v
    return v
  end
  return nil
end

-- cheap signature of everything the dock shows (a redraw only when it changes)
local function signature(c)
  local parts = { tostring(ns.Locale and ns.Locale.active), tostring(st.msg), tostring(st.dirty), tostring(AD.buyBlocked),
    tostring(st.resultsFor), tostring(c.open) }
  local b = st.buy
  if b then parts[#parts + 1] = table.concat({ b.id, b.n, b.state, tostring(b.total), tostring(b.changed) }, ":") end
  for _, l in ipairs(c.lists) do
    parts[#parts + 1] = tostring(l.id) .. l.title
    for _, r in ipairs(l.rows) do
      parts[#parts + 1] = table.concat({ r.id, r.name, r.missing, r.bank, tostring(st.unit[r.id]), tostring(st.commodity[r.id]) }, ":")
    end
  end
  return table.concat(parts, "|")
end

-- Drawing ------------------------------------------------------------------------------------------------------------------------

local function font(parent, kind, size, color, justify)
  local fs = W.font(parent, kind, size, color)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end

local function setOff(b, off)
  local C = AD.COLORS
  b.off = off and true or false
  setColor(b.label, off and C.dim or C.text)
end

-- flat text button on the dark plate; a button that is "off" shows its tooltip but does nothing
local function button(parent, w, h, size)
  local C = AD.COLORS
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b.bg = W.NewRect(b, C.btn, C.btn[4], "BACKGROUND")
  b.bg:SetAllPoints(b)
  b.label = font(b, "label", size or 12, C.text, "CENTER")
  b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.label:SetWidth(w - 4)
  b.label:SetWordWrap(false)
  b:SetScript("OnEnter", function(self)
    if not self.off then self.bg:SetColorTexture(C.btnHover[1], C.btnHover[2], C.btnHover[3], C.btnHover[4]) end
    if self.tipLines then W.tip(self, self.tipLines) end
  end)
  b:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(C.btn[1], C.btn[2], C.btn[3], C.btn[4])
    W.hideTip(self)
  end)
  b:SetScript("OnClick", function(self) if self.act and not self.off then safe(self.act, self) end end)
  return b
end

local function build()
  if st.frame then return st.frame end
  local C = AD.COLORS
  local Theme = Journal.Theme
  local f = CreateFrame("Frame", AD.NAME, UIParent)
  f:SetSize(AD.W, 120)
  f:SetFrameStrata("MEDIUM")
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  if f.SetDontSavePosition then f:SetDontSavePosition(true) end
  f:EnableMouse(true)
  if Theme and Theme.roundRect then
    f.edge = Theme.roundRect(f, { 1, 1, 1 }, 1, 6, "BACKGROUND", Theme.TEX and Theme.TEX.ring)
    f.edge.color(C.edge, C.edge[4])
    f.plate = Theme.roundRect(f, { 1, 1, 1 }, 1, 6, "BACKGROUND")
    f.plate.color(C.bg, C.bg[4])
  else
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
  end
  f:Hide()
  local inner = AD.W - AD.PAD * 2
  local nameW = inner - 32 - 112

  f.head = font(f, "label", 12, C.head)
  f.head:SetText(T.head)
  f.note = font(f, "label", 11, C.dim)
  f.note:SetWidth(inner)
  f.note:SetWordWrap(true)
  f.msg = font(f, "label", 11, C.ok)
  f.msg:SetWidth(inner)
  f.msg:SetWordWrap(true)

  -- purchase box: price / confirmation text and its two buttons
  f.buyText = font(f, "label", 12, C.text)
  f.buyText:SetWidth(inner)
  f.buyText:SetWordWrap(true)
  f.confirmBtn = button(f, 110, 22, 12)
  f.confirmBtn.label:SetText(T.confirmBtn)
  f.confirmBtn.act = function() AD.confirm() end
  f.cancelBtn = button(f, 110, 22, 12)
  f.cancelBtn.label:SetText(T.cancelBtn)
  f.cancelBtn.act = function() AD.cancel() end

  f.heads = {}
  for i = 1, AD.HEADS_MAX do
    local h = font(f, "label", 12, C.head)
    h:SetWidth(inner)
    h:SetWordWrap(false)
    h:Hide()
    f.heads[i] = h
  end
  f.rows = {}
  for i = 1, AD.ROWS_MAX do
    local row = CreateFrame("Frame", nil, f)
    row:SetSize(inner, AD.ROW_H - 2)
    row:EnableMouse(true)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    row.name = font(row, "label", 12, C.text)
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 32, -2)
    row.name:SetWidth(nameW)
    row.name:SetWordWrap(false)
    row.need = font(row, "label", 11, C.need)
    row.need:SetPoint("TOPLEFT", row, "TOPLEFT", 32, -16)
    row.need:SetWidth(66)
    row.need:SetWordWrap(false)
    row.extra = font(row, "label", 11, C.dim)
    row.extra:SetPoint("TOPLEFT", row, "TOPLEFT", 32 + 68, -16)
    row.extra:SetWidth(nameW - 68)
    row.extra:SetWordWrap(false)
    row.search = button(row, 52, 20, 11)
    row.search:SetPoint("TOPRIGHT", row, "TOPRIGHT", -62, -4)
    row.search.label:SetText(T.search)
    row.search.act = function() AD.search(row.id) end
    row.buy = button(row, 60, 20, 11)
    row.buy:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -4)
    row.buy.act = function() AD.buy(row.id, row.missing) end
    row:SetScript("OnEnter", function(self)
      if self.tipLines then W.tip(self, self.tipLines) end
    end)
    row:SetScript("OnLeave", function(self) W.hideTip(self) end)
    row:Hide()
    f.rows[i] = row
  end
  f.more = font(f, "label", 11, C.dim)

  st.frame = f
  return f
end

local function textHeight(fs, fallback)
  local ok, h = pcall(fs.GetStringHeight, fs)
  h = ok and num(h) or nil
  if not h or h <= 0 then return fallback end
  return h
end

local function pt(obj, parent, x, y)
  obj:ClearAllPoints()
  obj:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
end

-- tooltip of a row: the original item tooltip, our numbers appended
local function rowTip(r)
  local lines = { r.name }
  lines[#lines + 1] = T("tipNeed", int(r.need))
  lines[#lines + 1] = T("tipHave", int(min(r.have, 99999)))
  lines[#lines + 1] = T("tipMissing", int(r.missing))
  if r.bank > 0 then lines[#lines + 1] = T("tipBank", int(r.bank)) end
  if st.unit[r.id] then lines[#lines + 1] = T("unitFrom", money(st.unit[r.id])) end
  if st.commodity[r.id] == false then lines[#lines + 1] = T.single end
  lines.item = "item:" .. tostring(r.id)
  lines.itemExtra = { unpack(lines, 2) }
  return lines
end

-- paints the dock from AD.content(); positions every part from the top (the height follows the content)
local function draw(c)
  local f = st.frame
  if not f then return end
  local C = AD.COLORS
  st.content = c
  local x, inner = AD.PAD, AD.W - AD.PAD * 2
  local y = 8
  pt(f.head, f, x, y)
  y = y + 17
  f.note:Hide() f.msg:Hide() f.buyText:Hide() f.confirmBtn:Hide() f.cancelBtn:Hide() f.more:Hide()
  for _, h in ipairs(f.heads) do h:Hide() end
  for _, row in ipairs(f.rows) do
    W.hideTip(row)
    row:Hide()
  end

  -- message of the last action
  if st.msg then
    W.setText(f.msg, st.msg)
    setColor(f.msg, st.msgBad and C.need or C.ok)
    pt(f.msg, f, x, y)
    f.msg:Show()
    y = y + textHeight(f.msg, 13) + 4
  end
  if AD.buyBlocked and st.msg ~= T.blocked and st.msg ~= T.failed then
    W.setText(f.note, T.blockedNote)
    pt(f.note, f, x, y)
    f.note:Show()
    y = y + textHeight(f.note, 13) + 4
  end

  -- purchase box (one purchase at a time)
  local b = st.buy
  if b then
    local text
    if b.state == "price" then
      text = T("priceWait", int(b.n), b.name)
    elseif b.state == "confirm" then
      text = T("confirm", int(b.n), b.name, money(b.total))
      if b.changed then text = text .. "\n" .. T.changed end
      if not AD.enoughGold(b.total) then text = text .. "\n" .. T.noGold end
    else
      text = T.buying
    end
    W.setText(f.buyText, text)
    pt(f.buyText, f, x, y)
    f.buyText:Show()
    y = y + textHeight(f.buyText, 15) + 5
    if b.state == "confirm" then
      pt(f.confirmBtn, f, x, y)
      setOff(f.confirmBtn, not AD.enoughGold(b.total))
      f.confirmBtn:Show()
      b.shown = true -- the price stands in the window: only now a click may confirm
    end
    if b.state == "price" or b.state == "confirm" then
      pt(f.cancelBtn, f, x + (b.state == "confirm" and 116 or 0), y)
      f.cancelBtn:Show()
      y = y + 28
    end
    y = y + 2
  end

  -- lists with their missing materials
  local rowsLeft, headsLeft, hidden, ri, hi = AD.ROWS_MAX, AD.HEADS_MAX, 0, 0, 0
  local canSearch, canBuy = AD.canSearch(), AD.canBuy()
  for _, l in ipairs(c.lists) do
    if rowsLeft <= 0 or headsLeft <= 0 then
      hidden = hidden + #l.rows
    else
      hi = hi + 1
      headsLeft = headsLeft - 1
      local h = f.heads[hi]
      W.setText(h, l.title)
      pt(h, f, x, y)
      h:Show()
      y = y + AD.HEAD_H
      for _, r in ipairs(l.rows) do
        if rowsLeft <= 0 then
          hidden = hidden + 1
        else
          rowsLeft = rowsLeft - 1
          ri = ri + 1
          local row = f.rows[ri]
          pt(row, f, x, y)
          row.id, row.missing = r.id, r.missing
          row.icon:SetTexture(itemIcon(r.id))
          W.setText(row.name, r.name)
          W.setText(row.need, T("need", int(r.missing)))
          local extra = st.unit[r.id] and T("price", money(st.unit[r.id])) or (r.bank > 0 and T("bank", int(r.bank)) or "")
          W.setText(row.extra, extra)
          row.tipLines = rowTip(r)
          -- search
          row.search:SetShown(canSearch)
          row.search.tipLines = { T.search, T.searchTip }
          -- buy: only commodities (a known single auction gets "Suchen" only), enabled after the search of this very item
          local kind = commodityKind(r.id)
          local showBuy = canBuy and kind ~= false
          row.buy:SetShown(showBuy)
          if showBuy then
            row.buy.label:SetText(T("buy", int(min(r.missing, AD.BUY_MAX))))
            local needSearch = st.resultsFor ~= r.id
            local busy = st.buy ~= nil
            setOff(row.buy, needSearch or busy)
            row.buy.tipLines = { row.buy.label:GetText() or T.buy,
              busy and T.buyBusy or (needSearch and T.buyNeedSearch or T("buyTip", int(min(r.missing, AD.BUY_MAX)))) }
          end
          row:Show()
          y = y + AD.ROW_H
        end
      end
      y = y + 3
    end
  end
  if #c.lists == 0 then
    W.setText(f.note, T.allDone)
    if not st.msg and not AD.buyBlocked then
      pt(f.note, f, x, y)
      f.note:Show()
      y = y + textHeight(f.note, 13) + 4
    end
  end
  if hidden > 0 then
    W.setText(f.more, T("more", int(hidden)))
    pt(f.more, f, x, y)
    f.more:Show()
    y = y + 14
  end
  f:SetHeight(y + 6)
end

-- Placement (outside combat only) --------------------------------------------------------------------------------------------------------

local function scaleOf(f)
  local v = num(method(f, "GetEffectiveScale"))
  return (v and v > 0) and v or nil
end

-- anchors the dock to the window: top aligned right of it, or left when the screen edge leaves no room; scale follows the window
local function place()
  local f, w = st.frame, window()
  if not (f and w) or inCombat() then return false end
  local sw = UIParent and num(method(UIParent, "GetWidth")) or nil
  local ew, eu = scaleOf(w), UIParent and scaleOf(UIParent) or nil
  local k = (ew and eu) and max(0.5, min(2, ew / eu)) or 1
  local l, b, ww = method(w, "GetRect")
  l, b, ww = num(l), num(b), num(ww)
  local side = "right"
  if l and ww and sw and sw > 0 then
    local r = (l + ww) * k
    if r + AD.GAP + AD.W * k > sw and l * k - AD.GAP - AD.W * k >= 0 then side = "left" end
  end
  local sig = table.concat({ side, tostring(k), tostring(l), tostring(b), tostring(ww), tostring(sw) }, "|")
  if sig == st.placeSig and st.anchored then return true end
  st.placeSig = sig
  f:SetScale(k)
  f:ClearAllPoints()
  if side == "right" then
    f:SetPoint("TOPLEFT", w, "TOPRIGHT", AD.GAP, 0)
  else
    f:SetPoint("TOPRIGHT", w, "TOPLEFT", -AD.GAP, 0)
  end
  st.anchored, st.side = true, side
  return true
end

local function hideBar()
  local f = st.frame
  if not f then return end
  pcall(f.Hide, f)
  for _, row in ipairs(f.rows) do W.hideTip(row) end
  W.hideTip(f.confirmBtn)
  W.hideTip(f.cancelBtn)
end

-- Update: the one place where visibility, placement and content come together ------------------------------------------------------------

-- force: redraw even if nothing changed
function AD.update(force)
  if not (AD.enabled() and st.open and windowShown()) then
    hideBar()
    return false
  end
  local c = AD.content()
  if c.open == 0 then
    hideBar() -- no open shopping list: nothing to show
    return false
  end
  if not st.frame then
    if inCombat() then
      st.wantBuild = true -- built after combat (PLAYER_REGEN_ENABLED)
      return false
    end
    build()
    force = true
  end
  local f = st.frame
  local wasHidden = not (f:IsShown() == true)
  if inCombat() and not st.anchored then
    return false -- never placed yet: wait for the end of combat, show nothing at a wrong place
  end
  local sig = signature(c)
  if force or wasHidden or sig ~= st.sig then
    st.dirty = false
    draw(c)
    st.sig = signature(c)
  end
  if not inCombat() then place() end
  if wasHidden then f:Show() end
  return true
end

-- Actions -----------------------------------------------------------------------------------------------------------------------------

local function say(text, bad)
  st.msg, st.msgBad = text, bad and true or false
end

local function actionTotal()
  local log = ns.Core and ns.Core.actionLog
  return log and num(log.total) or 0
end

-- an earlier ADDON_ACTION_BLOCKED / FORBIDDEN already named a purchase call
local function loggedBlock()
  local log = ns.Core and ns.Core.actionLog
  if type(log) ~= "table" or type(log.entries) ~= "table" then return false end
  for _, en in ipairs(log.entries) do
    if type(en) == "table" and type(en.func) == "string" and string.find(en.func, "CommoditiesPurchase", 1, true) then return true end
  end
  return false
end

-- Kaufen is off for the rest of the session; only "Suchen" stays
local function blockBuying(text)
  AD.buyBlocked = true
  st.buy = nil
  say(text or T.blocked, true)
end

function AD.enoughGold(total)
  total = num(total)
  if not total then return false end
  if type(GetMoney) ~= "function" then return true end
  local ok, have = pcall(GetMoney)
  have = ok and num(have) or nil
  if not have then return true end
  return have >= total
end

-- "Suchen": search the auction house for exactly this item -> true | false
function AD.search(id)
  id = posInt(id)
  if not id or not st.open then return false end
  local make, send = apiFn("MakeItemKey"), apiFn("SendSearchQuery")
  if not (make and send) then
    say(T.noSearch, true)
    AD.update(true)
    return false
  end
  local ready = apiFn("IsThrottledMessageSystemReady")
  if ready then
    local ok, v = pcall(ready)
    if ok and v == false then
      say(T.busy, true)
      AD.update(true)
      return false
    end
  end
  local ok, key = pcall(make, id)
  if not ok or type(key) ~= "table" then
    say(T.noSearch, true)
    AD.update(true)
    return false
  end
  local sorts = {}
  local E2 = rawget(_G, "Enum")
  local order = type(E2) == "table" and type(E2.AuctionHouseSortOrder) == "table" and E2.AuctionHouseSortOrder.Price or nil
  if order ~= nil then sorts = { { sortOrder = order, reverseSort = false } } end
  local sent = pcall(send, key, sorts, false)
  if not sent then
    say(T.noSearch, true)
    AD.update(true)
    return false
  end
  st.resultsFor = nil -- the old results are gone, the purchase needs the list of this item
  st.unit[id] = nil
  say(nil)
  AD.update(true)
  return true
end

-- "Kaufen (N)": first step only (start the purchase, the price comes with COMMODITY_PRICE_UPDATED) -> true | nil, reason
function AD.buy(id, qty)
  id, qty = posInt(id), posInt(qty)
  if not (id and qty and st.open) then return nil, "eingabe" end
  if not AD.canBuy() then return nil, "gesperrt" end
  if st.buy then return nil, "laeuft" end
  if inCombat() then return nil, "kampf" end
  if st.commodity[id] == false then return nil, "einzel" end
  if st.resultsFor ~= id then
    say(T.buyNeedSearch, true)
    AD.update(true)
    return nil, "suchen"
  end
  if loggedBlock() then
    blockBuying()
    AD.update(true)
    return nil, "gesperrt"
  end
  qty = min(qty, AD.BUY_MAX)
  local start = apiFn("StartCommoditiesPurchase")
  local before = actionTotal()
  local ok = pcall(start, id, qty)
  if not ok or actionTotal() > before then
    blockBuying()
    AD.update(true)
    return nil, "gesperrt"
  end
  st.buy = { id = id, n = qty, name = E.itemName(id) or ("#" .. id), state = "price", deadline = now() + AD.PRICE_WAIT }
  say(nil)
  AD.update(true)
  return true
end

-- "Bestätigen": second click; only with a displayed price -> true | nil, reason
function AD.confirm()
  local b = st.buy
  if not (b and b.state == "confirm" and b.shown and num(b.total)) then return nil, "kein-preis" end
  if not AD.enoughGold(b.total) then return nil, "gold" end
  local confirmFn = apiFn("ConfirmCommoditiesPurchase")
  if not (confirmFn and not AD.buyBlocked) then return nil, "gesperrt" end
  local before = actionTotal()
  local ok = pcall(confirmFn, b.id, b.n)
  if not ok or actionTotal() > before then
    local cancel = apiFn("CancelCommoditiesPurchase")
    if cancel then pcall(cancel) end
    blockBuying()
    AD.update(true)
    return nil, "gesperrt"
  end
  b.state, b.deadline = "buying", now() + AD.BUY_WAIT
  AD.update(true)
  return true
end

-- "Abbrechen" (also when the house closes or the price does not come): CancelCommoditiesPurchase, the box disappears
function AD.cancel(quiet)
  local b = st.buy
  if not b then return false end
  if b.state == "price" or b.state == "confirm" then
    local cancel = apiFn("CancelCommoditiesPurchase")
    if cancel then pcall(cancel) end
  end
  st.buy = nil
  if not quiet then say(nil) end
  AD.update(true)
  return true
end

-- Events and poll --------------------------------------------------------------------------------------------------------------------

local function readResults(id)
  local qty, info = apiFn("GetCommoditySearchResultsQuantity"), apiFn("GetCommoditySearchResultInfo")
  if not (qty and info) then return end
  local ok, n = pcall(qty, id)
  n = ok and num(n) or nil
  if not n or n < 1 then
    st.unit[id] = nil
    return
  end
  local ok2, first = pcall(info, id, 1)
  local unit = ok2 and posInt(field(first, "unitPrice")) or nil
  st.unit[id] = unit
end

local function onPrice(unit, total)
  local b = st.buy
  if not b or (b.state ~= "price" and b.state ~= "confirm") then return end
  total = num(total)
  if not total or total < 0 then
    AD.cancel(true)
    say(T.unavailable, true)
    AD.update(true)
    return
  end
  if b.state == "confirm" and b.total ~= total then b.changed = true end
  b.state, b.unit, b.total = "confirm", num(unit), total
  b.deadline = nil
  AD.update(true)
end

local function onEvent(_, event, arg1, arg2)
  if event == "ADDON_LOADED" then
    if arg1 == "Blizzard_AuctionHouseUI" and st.open then AD.startPoll() end
  elseif event == "AUCTION_HOUSE_SHOW" then
    st.open = true
    st.resultsFor = nil
    AD.startPoll()
    AD.update()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    st.open = false
    st.resultsFor, st.buy, st.msg = nil, nil, nil
    hideBar()
  elseif event == "PLAYER_REGEN_ENABLED" then
    if st.wantBuild or st.open then
      st.wantBuild = false
      AD.update()
    end
  elseif event == "BAG_UPDATE_DELAYED" then
    E.invalidate()
    st.dirty = true
    if st.open then AD.update() end
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    local id = posInt(arg1)
    if id then
      st.commodity[id] = true
      st.resultsFor = id
      readResults(id)
      if st.open then AD.update(true) end
    end
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    local id = posInt(field(arg1, "itemID"))
    if id then
      st.commodity[id] = false
      if st.resultsFor == id then st.resultsFor = nil end
      if st.open then AD.update(true) end
    end
  elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
    st.dirty = true
  elseif event == "COMMODITY_PRICE_UPDATED" then
    onPrice(arg1, arg2)
  elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
    if st.buy and st.buy.state ~= "buying" then
      st.buy = nil
      say(T.unavailable, true)
      AD.update(true)
    end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    local b = st.buy
    E.invalidate()
    if b then
      st.buy = nil
      st.resultsFor = nil -- the purchase used up the offers; a new search shows the new state
      st.unit[b.id] = nil
      say(T("bought", int(b.n), b.name))
    end
    st.dirty = true
    if st.open then AD.update(true) end
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    if st.buy then
      blockBuying(T.failed)
      st.dirty = true
      if st.open then AD.update(true) end
    end
  end
end

function AD.startPoll()
  st.graceUntil = now() + AD.GRACE
  st.poll = 0
  if st.pollFrame then st.pollFrame:Show() end
end

local function onPoll(_, dt)
  st.poll = st.poll + (num(dt) or 0)
  if st.poll < AD.POLL then return end
  st.poll = 0
  -- a price or a result that never comes: release the box
  local b = st.buy
  if b and b.deadline and now() > b.deadline then
    if b.state == "price" then
      AD.cancel(true)
      say(T.noPrice, true)
    else
      st.buy = nil
      say(T.unknownResult, true)
    end
    st.dirty = true
  end
  if not st.open or not AD.enabled() then
    AD.update()
    st.pollFrame:Hide()
    return
  end
  if windowShown() then
    AD.update()
  else
    AD.update()
    if now() > (st.graceUntil or 0) then st.pollFrame:Hide() end
  end
end

local function init()
  if type(CreateFrame) ~= "function" then return end
  local ok, ev = pcall(CreateFrame, "Frame")
  if not (ok and type(ev) == "table") then return end
  st.events = ev
  for _, name in ipairs(AD.EVENTS) do
    pcall(ev.RegisterEvent, ev, name) -- an event the client does not know is no error
  end
  ev:SetScript("OnEvent", function(self, event, arg1, arg2) safe(onEvent, self, event, arg1, arg2) end)
  -- poll frame: hidden (so without any OnUpdate) while the auction house is closed
  local pf = CreateFrame("Frame")
  pf:SetScript("OnUpdate", function(self, dt) safe(onPoll, self, dt) end)
  pf:Hide()
  st.pollFrame = pf
  local P = ns.Plans
  if P and type(P.onChange) == "function" then P.onChange(function() st.dirty = true end) end
end

init()
