-- Docking bar at the Blizzard auction house, station 2 "Einkaufen" of the Werkauftrag (WoW Forever only; Retail has no recipe cache, the
-- bar never exists there): a dark plate beside AuctionHouseFrame (design "Ink & Embers - Werkauftrag", board AH-Einkaufen) with ONE
-- shopping list over all open work orders (ns.Werk.shoppingList, read only: need - bags - on the way by mail, bank only as a hint).
--   * header "Einkaufszettel - for N orders", the chain (1 Planen done, 2 Einkaufen, 3 Herstellen, Journal.WerkBarKit);
--   * "Noch zu zahlen" (sum of the known prices), "Euer Gold", "Preise von eben - neu holen";
--   * one row per material: icon, "N x Name", unit price + what it is for, the sum or a check mark (bought / on the way);
--   * ONE main button, always at the same spot: "Kaufen - N x Name" -> (second click) "Bestaetigen - Endpreis", plus "Abbrechen" /
--     "Ueberspringen"; when nothing is left: "Alles gekauft - pick up the mail at the mailbox, then go to the workbench".
-- Prices come by themselves: when the house opens, journal/Preisabfrage.lua asks the price of every missing material one after the
-- other (no click, no "Suchen"); the sum for N pieces runs over all offers (Journal.Preise.priceFor). The purchase: click 1
-- StartCommoditiesPurchase(itemID, n) (works without a search; the price arrives with COMMODITY_PRICE_UPDATED), the window shows the
-- final price the GAME names (and a clear warning when it is more than 5 % over the estimate), only click 2 ("Bestaetigen") calls
-- ConfirmCommoditiesPurchase. Never automatic, never without a displayed price, "Abbrechen" calls CancelCommoditiesPurchase. The bought
-- goods arrive by mail: Werk.expectPurchase(itemID, n) is announced right before click 2, the collector books the "on the way" count.
-- Safeguards: not enough gold -> main button off ("Euch fehlen X"); combat / house closes during the confirmation -> Cancel and back to
-- "Kaufen"; quote run out (GetQuoteDurationRemaining <= 0) -> started again from the click; too few offers -> the available amount is
-- offered, the rest stays on the list; single auctions (no commodity) only get the price hint, bought in Blizzard's window; item data
-- that never loads -> "Preis unbekannt", the row stays buyable (the game names the final price). If the game blocks a call (pcall
-- error, ADDON_ACTION_BLOCKED in Core.actionLog) or COMMODITY_PURCHASE_FAILED comes, buying is off for the rest of the session
-- (AD.buyBlocked), the prices stay visible.
--
-- Taint rules (everything towards Blizzard's frames is READ ONLY, exactly like journal/ProfessionBar.lua):
--   * the dock is a frame of UIParent; only a SetPoint anchors it to AuctionHouseFrame, and only outside combat (in combat nothing is built
--     or moved);
--   * no HookScript / SetScript / hooksecurefunc on a Blizzard frame, no write into a Blizzard frame or table, no Show/Hide on it;
--   * the window is found lazily (rawget(_G, "AuctionHouseFrame"): Blizzard_AuctionHouseUI loads on demand; ADDON_LOADED and
--     AUCTION_HOUSE_SHOW wake the dock); visibility: AUCTION_HOUSE_SHOW / AUCTION_HOUSE_CLOSED plus a light poll of AuctionHouseFrame:IsShown()
--     while the house is open (the poll frame is our own and stays hidden, no OnUpdate, while it is closed).
-- Foreign text (item and order names) only through Sanitize.display (the collector did it already). No glyph outside the safe character
-- set: the check mark is a game texture. Option "auctionDock" (Pages setting, default on; Options: "Leiste am Auktionshaus").
local _, ns = ...

local Journal = ns.Journal
local W = Journal and Journal.Widgets
local E = ns.Einkauf
local Kit = Journal and Journal.WerkBarKit
if not (Journal and W and E and Kit) then return end

local floor, max, min = math.floor, math.max, math.min

local AD = {}
Journal.AuctionDock = AD

AD.NAME = "EveNChronicleAuctionDock"
AD.WINDOW = "AuctionHouseFrame"
AD.W = 360              -- width of the dock
AD.PAD = 12
AD.GAP = 3              -- distance to the window
AD.POLL = 0.25          -- seconds between two looks at the window while the house is open
AD.GRACE = 3            -- seconds after AUCTION_HOUSE_SHOW in which a not yet visible window is waited for
AD.ROWS_MAX = 10        -- material rows shown
AD.ROW_H = 42
AD.BOX_H = 58
AD.BUY_MAX = 99999      -- most items of one purchase
AD.PRICE_WAIT = 8       -- seconds until a price must have arrived
AD.BUY_WAIT = 15        -- seconds until the result of a confirmed purchase must have arrived
AD.CONFIRM_DELAY = 0.5  -- seconds the final price must stand in the window before "Bestaetigen" works (no double click through click 1)
AD.SLOT_H = 44          -- fixed room for the message / warning lines above the main button (the button never jumps)
AD.WARN_OVER = 1.05     -- final price over estimate x this: clear warning before "Bestaetigen"
AD.CHECK_TEX = "Interface\\Buttons\\UI-CheckBox-Check"
AD.EVENTS = {
  "ADDON_LOADED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
  "PLAYER_LOGIN", "UPDATE_PENDING_MAIL", "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED",
  "COMMODITY_PURCHASE_FAILED", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_KEY_ITEM_INFO_RECEIVED",
}
local C = Kit.COLORS

-- deDE is the source (L.ns in the code), the other six languages in locales/<lang>_werkdock.lua
AD.TEXT = ns.Locale.ns("WerkDock", {
  head = "EINKAUFSZETTEL",
  ordersOne = "für 1 Auftrag",
  ordersMany = "für %s Aufträge",
  toPay = "NOCH ZU ZAHLEN",
  toPayFrom = "ab %s",
  yourGold = "Euer Gold: %s",
  pricesNow = "Preise von eben",
  pricesAgo = "Preise von vor %s Min.",
  pricesFetching = "Preise werden geholt …",
  refresh = "neu holen",
  refreshTip = "Fragt die Preise aller fehlenden Materialien im Auktionshaus noch einmal ab.",
  rowTitle = "%s× %s",
  subUnit = "%s je Stück · %s",
  subPartial = "nur %s× im Angebot · %s",
  subNone = "kein Angebot · %s",
  subSingle = "Einzelauktion ab %s · %s",
  subUnknown = "Preis unbekannt · %s",
  subPending = "Preis wird geholt … · %s",
  subMail = "%s× unterwegs per Post · %s",
  subBought = "gekauft · %s",
  forRoute = "für %s bis %s",
  forOne = "für %s× %s",
  forMore = "%s und %s weitere",
  buyIdle = "Kaufen",
  buyLabel = "Kaufen · %s× %s",
  buyHintEst = "ca. %s – danach bestätigen",
  buyHintUnknown = "Endpreis nennt das Spiel – danach bestätigen",
  buyHintPartial = "Nur %s× im Angebot, ca. %s – Rest bleibt auf dem Zettel",
  fetching = "Preis wird geholt …",
  goldUnknown = "Gold unbekannt",
  more = "und %s weitere",
  confirmLabel = "Bestätigen · %s",
  endPrice = "Endpreis vom Spiel",
  endPriceMore = "Endpreis vom Spiel: %s mehr als geschätzt",
  priceUp = "Achtung: Der Endpreis liegt %s über der Schätzung (+%s %%).",
  changed = "Der Preis hat sich geändert.",
  buying = "Kauf läuft …",
  cancelBtn = "Abbrechen",
  skipBtn = "Überspringen",
  twoClicks = "Kauf = 2 Klicks, verlangt das Spiel",
  doneTitle = "Alles gekauft",
  doneMail = "Post am Briefkasten abholen, dann zur Werkbank.",
  doneBags = "Alle Materialien sind da. Weiter zur Werkbank.",
  cantSingle = "Einzelauktion: Kauf im Auktionshaus-Fenster.",
  cantNone = "Kein Angebot im Auktionshaus.",
  noBuyable = "Hier lässt sich nichts kaufen.",
  unknownNote = "Weiteres Material zeigt das Spiel erst nach dem Lernen.",
  tipNeed = "Benötigt: %s",
  tipHave = "In den Taschen: %s",
  tipMail = "Unterwegs per Post: %s",
  tipMissing = "Fehlt: %s",
  tipBank = "In der Bank: %s",
  tipFor = "Für: %s",
  tipUnit = "Billigstes Angebot: %s je Stück",
  bought = "%s× %s gekauft. Die Ware kommt per Post.",
  unavailable = "Dazu gibt es kein Angebot in dieser Menge.",
  failed = "Der Kauf hat nicht geklappt. Kaufen ist bis zum nächsten Neuladen aus, die Preise bleiben sichtbar.",
  blocked = "Das Spiel sperrt das Kaufen von hier. Gekauft wird im Auktionshaus-Fenster, die Preise stehen hier.",
  blockedNote = "Kaufen ist gesperrt: gekauft wird im Auktionshaus-Fenster.",
  noPrice = "Es kam kein Preis an. Der Kauf wurde abgebrochen.",
  unknownResult = "Kein Ergebnis gemeldet. Schaut in die Taschen und in die Post.",
  quoteExpired = "Der Preis war abgelaufen – hier der neue. Bitte noch einmal prüfen.",
  combatCancel = "Kampf: Der Kauf wurde abgebrochen.",
  optLabel = "Leiste am Auktionshaus",
  optTip = "Eine Leiste am Auktionshaus mit dem Einkaufszettel aller Werkaufträge: die Preise kommen von selbst, gekauft wird mit zwei Klicks und angezeigtem Endpreis (nur WoW Forever).",
})
local T = AD.TEXT

-- state: frame, open (house is open), cur (item id of the selected row), buy = { id, n, name, state = "price" | "confirm" | "buying",
-- est, unit, total, shown, deadline, changed, warn }
local st = { open = false, poll = 0, sig = nil, placeSig = nil, msg = nil, dirty = false }
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

local function textOf(s, n)
  if type(s) ~= "string" or isSecret(s) or s == "" then return nil end
  local S = ns.Sanitize
  s = S and S.display and S.display(s, n or 60) or s
  if type(s) ~= "string" or s == "" then return nil end
  return s
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

local function gold()
  if type(GetMoney) ~= "function" then return nil end
  local ok, have = pcall(GetMoney)
  return ok and num(have) or nil
end

function AD.enoughGold(total)
  total = num(total)
  if not total then return false end
  local have = gold()
  if not have then return false end -- money unreadable (no GetMoney / secret value): fail closed, nothing is bought
  return have >= total
end

local function prices() return Journal.Preise end
local function queryer() return Journal.Preisabfrage end

local function fetching()
  local PA = queryer()
  return PA ~= nil and type(PA.busy) == "function" and PA.busy() == true
end

-- Content (pure data) ----------------------------------------------------------------------------------------------------------------

-- what an order is for: "fuer Schmiedekunst bis 100" / "fuer 5x Bronzebarren" (several orders: first one and the number of the others)
local function forWhat(ids)
  local Wk = ns.Werk
  if not (Wk and type(Wk.get) == "function" and type(ids) == "table") then return "" end
  local parts = {}
  for _, id in ipairs(ids) do
    local w = Wk.get(id)
    if type(w) == "table" then
      if w.goal then
        local cache = E.cache and E.cache()
        local entry = type(cache) == "table" and cache[w.prof] or nil
        local pn = textOf(entry and entry.name, 40) or tostring(w.prof)
        parts[#parts + 1] = T("forRoute", pn, int(w.goal))
      else
        parts[#parts + 1] = T("forOne", int(posInt(w.n) or 1), textOf(w.name, 40) or "?")
      end
    end
  end
  if #parts == 0 then return "" end
  if #parts == 1 then return parts[1] end
  return T("forMore", parts[1], int(#parts - 1))
end

-- price state of one list line -> state, cost (copper of the qty), qty (what one purchase buys), cheapest (single auction hint)
--   "bought" (nothing missing any more), "pending" (price on its way), "ready", "partial" (fewer offers than missing), "none", "single",
--   "unknown" (item data never loaded / no answer: still buyable, the game names the price)
local function priceState(l)
  if l.missing <= 0 then return "bought" end
  local Pr = prices()
  if not (Pr and queryer()) then return "unknown", nil, min(l.missing, AD.BUY_MAX) end
  local e = Pr.get(l.id)
  if not e then return "pending", nil, min(l.missing, AD.BUY_MAX) end
  if e.kind == "commodity" then
    local total, got = Pr.priceFor(l.id, l.missing)
    if total and got and got > 0 then
      if got >= l.missing then return "ready", total, min(l.missing, AD.BUY_MAX) end
      return "partial", total, min(got, AD.BUY_MAX)
    end
    return "none"
  end
  if e.kind == "single" then return "single", nil, nil, e.cheapest end
  if e.kind == "none" then return "none" end
  return "unknown", nil, min(l.missing, AD.BUY_MAX)
end

local BUYABLE = { pending = true, ready = true, partial = true, unknown = true }

-- { orders = n, rows = { { id, name, need, have, mail, bank, missing, bought, state, cost, qty, cheapest, buyable, forWhat } },
--   open = rows with something missing, total = known cost of the open rows, priced / unpriced = open rows with / without a cost,
--   mailRows = rows on the way by mail, unknown = names of materials the game shows only after learning }
function AD.content()
  local c = { orders = 0, rows = {}, open = 0, total = 0, priced = 0, unpriced = 0, mailRows = 0, unknown = 0 }
  local Wk = ns.Werk
  if not (Wk and type(Wk.shoppingList) == "function") then return c end
  local ok, sl = pcall(Wk.shoppingList)
  if not ok or type(sl) ~= "table" then return c end
  c.orders = posInt(sl.orders) or 0
  c.unknown = type(sl.unknown) == "table" and #sl.unknown or 0
  for _, l in ipairs(type(sl.lines) == "table" and sl.lines or {}) do
    local missing = max(0, floor(num(l.missing) or 0))
    local mail = max(0, floor(num(l.mail) or 0))
    local bought = max(0, floor(num(l.bought) or 0))
    if type(l.id) == "number" and (missing > 0 or mail > 0 or bought > 0) then
      local row = { id = l.id, name = textOf(l.name, 60) or E.itemName(l.id) or ("#" .. l.id), need = num(l.need) or 0, have = num(l.have) or 0,
        mail = mail, bank = max(0, floor(num(l.bank) or 0)), missing = missing, bought = bought, orderIds = l.orders }
      row.state, row.cost, row.qty, row.cheapest = priceState(row)
      row.buyable = BUYABLE[row.state] == true
      row.forWhat = forWhat(l.orders)
      c.rows[#c.rows + 1] = row
      if missing > 0 then
        c.open = c.open + 1
        if row.cost then
          c.total = c.total + row.cost
          c.priced = c.priced + 1
        else
          c.unpriced = c.unpriced + 1
        end
      end
      if mail > 0 then c.mailRows = c.mailRows + 1 end
    end
  end
  return c
end

-- the selected row: the chosen one while it can still be bought, else the first buyable row
local function curRow(c)
  local first
  for _, r in ipairs(c.rows) do
    if r.buyable then
      first = first or r
      if r.id == st.cur then return r end
    end
  end
  st.cur = first and first.id or nil
  return first
end

local function nextBuyable(c, afterId)
  local list = {}
  for _, r in ipairs(c.rows) do if r.buyable then list[#list + 1] = r end end
  if #list == 0 then return nil end
  for i, r in ipairs(list) do
    if r.id == afterId then return list[i % #list + 1] end
  end
  return list[1]
end

local function openIds(c)
  local ids = {}
  for _, r in ipairs(c.rows) do if r.missing > 0 then ids[#ids + 1] = r.id end end
  return ids
end

-- age of the oldest price of the open rows in seconds | nil
local function priceAge(c)
  local Pr = prices()
  if not Pr then return nil end
  local oldest
  for _, r in ipairs(c.rows) do
    local e = r.missing > 0 and Pr.get(r.id) or nil
    local at = e and num(e.at)
    if at and (not oldest or at < oldest) then oldest = at end
  end
  return oldest and max(0, now() - oldest) or nil
end

-- cheap signature of everything the dock shows (a redraw only when it changes)
local function signature(c)
  local age = priceAge(c)
  local parts = { tostring(ns.Locale and ns.Locale.active), tostring(st.msg), tostring(st.dirty), tostring(AD.buyBlocked), tostring(st.cur),
    tostring(inCombat()), tostring(gold()), tostring(fetching()), tostring(c.orders), tostring(c.open), tostring(c.total),
    tostring(age and floor(age / 60)) }
  local b = st.buy
  if b then parts[#parts + 1] = table.concat({ b.id, b.n, b.state, tostring(b.total), tostring(b.changed),
    tostring(b.shownAt ~= nil and now() - b.shownAt >= AD.CONFIRM_DELAY) }, ":") end
  for _, r in ipairs(c.rows) do
    parts[#parts + 1] = table.concat({ r.id, r.name, r.missing, r.mail, r.bought, r.bank, r.state, tostring(r.cost), tostring(r.qty), r.forWhat }, ":")
  end
  return table.concat(parts, "|")
end

-- the one main button of the bar -> Kit.mainState table | nil (nothing left to buy), the row it is about
function AD.mainState(c)
  c = c or st.content or AD.content()
  local row = curRow(c)
  local combat = inCombat()
  local have = gold()
  local b = st.buy
  if b then
    local r = row
    if b.state == "confirm" then
      -- the button is released CONFIRM_DELAY seconds after the price stands in the window (visibly locked until then)
      local ripe = b.shownAt ~= nil and now() - b.shownAt >= AD.CONFIRM_DELAY
      local s = Kit.mainState({ label = T("confirmLabel", money(b.total)), confirm = true, combat = combat, cost = b.total, money = have,
        busy = not ripe,
        hint = (b.total > (b.est or b.total) and T("endPriceMore", money(b.total - (b.est or b.total)))) or T.endPrice })
      if s.enabled and have == nil then s = Kit.mainState({ label = s.label, confirm = true, disabled = true, hint = T.goldUnknown }) end
      return s, r
    elseif b.state == "buying" then
      return Kit.mainState({ label = T.buying, busy = true }), r
    end
    local s = Kit.mainState({ label = T("buyLabel", int(b.n), b.name), busy = true })
    s.hint = T.fetching
    return s, r
  end
  if not row then
    if c.open == 0 then return nil end
    local hint = T.noBuyable
    for _, r in ipairs(c.rows) do
      if r.missing > 0 then
        hint = r.state == "single" and T.cantSingle or (r.state == "none" and T.cantNone or hint)
        break
      end
    end
    return Kit.mainState({ label = T.buyIdle, disabled = true, hint = hint }), nil
  end
  local label = T("buyLabel", int(row.qty), row.name)
  if AD.buyBlocked or not AD.canBuy() then
    return Kit.mainState({ label = label, disabled = true, hint = T.blockedNote, combat = combat }), row
  end
  if row.state == "pending" then
    local s = Kit.mainState({ label = label, busy = true })
    s.hint = T.fetching
    return s, row
  end
  local hint
  if row.state == "unknown" then
    hint = T.buyHintUnknown
  elseif row.state == "partial" then
    hint = T("buyHintPartial", int(row.qty), money(row.cost))
  else
    hint = T("buyHintEst", money(row.cost))
  end
  local s = Kit.mainState({ label = label, combat = combat, cost = row.cost, money = have, busy = fetching(), hint = hint })
  if s.enabled and have == nil then s = Kit.mainState({ label = label, disabled = true, hint = T.goldUnknown }) end
  return s, row
end

-- Drawing ------------------------------------------------------------------------------------------------------------------------

local function font(parent, kind, size, color, justify)
  return Kit.font(parent, kind, size, color, justify)
end

local function setColor(fs, c2) fs:SetTextColor(c2[1], c2[2], c2[3], c2[4] or 1) end

local function frameRect(parent, color, alpha)
  local r = W.NewRect(parent, color, alpha, "BACKGROUND")
  return r
end

local function build()
  if st.frame then return st.frame end
  local f = CreateFrame("Frame", AD.NAME, UIParent)
  f:SetSize(AD.W, 200)
  f:SetFrameStrata("MEDIUM")
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  if f.SetDontSavePosition then f:SetDontSavePosition(true) end
  f:EnableMouse(true)
  Kit.skin(f)
  f:Hide()
  local inner = AD.W - AD.PAD * 2
  local nameW = inner - 42 - 76

  f.head = font(f, "label", 14, C.gold)
  f.head:SetText(T.head)
  f.orders = font(f, "label", 12, C.dim, "RIGHT")
  f.orders:SetWidth(inner - 130)
  f.orders:SetWordWrap(false)
  f.chain = Kit.chain(f, inner)

  -- sum box
  local box = CreateFrame("Frame", nil, f)
  box:SetSize(inner, AD.BOX_H)
  box.fill = frameRect(box, C.gold, 0.09)
  box.fill:SetAllPoints(box)
  box.label = font(box, "label", 11, C.dim)
  box.label:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -8)
  box.label:SetText(T.toPay)
  box.total = font(box, "label", 20, C.text)
  box.total:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -24)
  box.total:SetWidth(150)
  box.total:SetWordWrap(false)
  box.gold = font(box, "label", 12, C.dim, "RIGHT")
  box.gold:SetPoint("TOPRIGHT", box, "TOPRIGHT", -10, -9)
  box.gold:SetWidth(inner - 170)
  box.gold:SetWordWrap(false)
  box.age = CreateFrame("Button", nil, box)
  box.age:SetSize(inner - 150, 16)
  box.age:SetPoint("TOPRIGHT", box, "TOPRIGHT", -10, -30)
  box.age.label = font(box.age, "label", 11, C.dim, "RIGHT")
  box.age.label:SetAllPoints(box.age)
  box.age.label:SetWordWrap(false)
  box.age:SetScript("OnEnter", function(self) W.tip(self, { T.refresh, T.refreshTip }) end)
  box.age:SetScript("OnLeave", function(self) W.hideTip(self) end)
  box.age:SetScript("OnClick", function(self) if not self.off then safe(AD.refresh) end end)
  f.box = box

  f.msg = font(f, "label", 11, C.ok)
  f.msg:SetWidth(inner)
  f.msg:SetWordWrap(true)
  f.msg:SetHeight(AD.SLOT_H)
  if f.msg.SetJustifyV then f.msg:SetJustifyV("TOP") end
  if f.msg.SetMaxLines then f.msg:SetMaxLines(3) end
  f.note = font(f, "label", 11, C.dim)
  f.note:SetWidth(inner)
  f.note:SetWordWrap(true)

  f.rows = {}
  for i = 1, AD.ROWS_MAX do
    local row = CreateFrame("Button", nil, f)
    row:SetSize(inner, AD.ROW_H - 3)
    row.hl = frameRect(row, C.gold, 0.10)
    row.hl:SetAllPoints(row)
    row.edges = {}
    for k = 1, 4 do
      local e = W.NewRect(row, C.gold, 0.9, "BORDER")
      row.edges[k] = e
    end
    row.edges[1]:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0) row.edges[1]:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0) row.edges[1]:SetHeight(1)
    row.edges[2]:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0) row.edges[2]:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0) row.edges[2]:SetHeight(1)
    row.edges[3]:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0) row.edges[3]:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0) row.edges[3]:SetWidth(1)
    row.edges[4]:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0) row.edges[4]:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0) row.edges[4]:SetWidth(1)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -4)
    row.name = font(row, "label", 13, C.text)
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 42, -5)
    row.name:SetWidth(nameW)
    row.name:SetWordWrap(false)
    row.sub = font(row, "label", 11, C.dim)
    row.sub:SetPoint("TOPLEFT", row, "TOPLEFT", 42, -22)
    row.sub:SetWidth(nameW)
    row.sub:SetWordWrap(false)
    row.right = font(row, "label", 13, C.text, "RIGHT")
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
    row.right:SetWidth(72)
    row.right:SetWordWrap(false)
    row.check = row:CreateTexture(nil, "OVERLAY")
    row.check:SetSize(20, 20)
    row.check:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -8)
    row.check:SetTexture(AD.CHECK_TEX)
    if row.check.SetVertexColor then row.check:SetVertexColor(C.ok[1], C.ok[2], C.ok[3], 1) end
    row:SetScript("OnEnter", function(self) if self.tipLines then W.tip(self, self.tipLines) end end)
    row:SetScript("OnLeave", function(self) W.hideTip(self) end)
    row:SetScript("OnClick", function(self) if self.rowId then safe(AD.select, self.rowId) end end)
    row:Hide()
    f.rows[i] = row
  end
  f.more = font(f, "label", 11, C.dim)

  -- the one main button (always at the same spot under the rows) and its two links
  f.main = Kit.mainButton(f, inner, 34)
  f.main.act = function() AD.mainClick() end
  f.cancelBtn = Kit.button(f, 120, 18, 11)
  f.cancelBtn.label:SetText(T.cancelBtn)
  f.cancelBtn.act = function() AD.cancel() end
  f.skipBtn = Kit.button(f, 120, 18, 11)
  f.skipBtn.label:SetText(T.skipBtn)
  f.skipBtn.act = function() AD.skip() end
  f.twoClicks = font(f, "label", 11, C.dim, "RIGHT")
  f.twoClicks:SetWidth(inner - 128)
  f.twoClicks:SetWordWrap(false)
  f.twoClicks:SetText(T.twoClicks)

  -- final box
  local done = CreateFrame("Frame", nil, f)
  done:SetSize(inner, 60)
  done.fill = frameRect(done, C.ok, 0.12)
  done.fill:SetAllPoints(done)
  done.title = font(done, "label", 15, C.ok)
  done.title:SetPoint("TOPLEFT", done, "TOPLEFT", 12, -10)
  done.title:SetText(T.doneTitle)
  done.text = font(done, "label", 12, C.text)
  done.text:SetPoint("TOPLEFT", done, "TOPLEFT", 12, -30)
  done.text:SetWidth(inner - 24)
  done.text:SetWordWrap(true)
  done:Hide()
  f.done = done

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
  if r.mail > 0 then lines[#lines + 1] = T("tipMail", int(r.mail)) end
  if r.missing > 0 then lines[#lines + 1] = T("tipMissing", int(r.missing)) end
  if r.bank > 0 then lines[#lines + 1] = T("tipBank", int(r.bank)) end
  if r.forWhat ~= "" then lines[#lines + 1] = T("tipFor", r.forWhat) end
  if r.state == "ready" or r.state == "partial" then
    lines[#lines + 1] = T("tipUnit", money(floor(r.cost / max(1, r.qty) + 0.5)))
  elseif r.state == "single" and r.cheapest then
    lines[#lines + 1] = T("subSingle", money(r.cheapest), "")
  end
  lines.item = "item:" .. tostring(r.id)
  lines.itemExtra = { unpack(lines, 2) }
  return lines
end

local function subText(r)
  local why = r.forWhat
  if r.missing <= 0 then
    if r.mail > 0 then return T("subMail", int(r.mail), why) end
    return T("subBought", why)
  end
  if r.state == "ready" then return T("subUnit", money(floor(r.cost / max(1, r.qty) + 0.5)), why) end
  if r.state == "partial" then return T("subPartial", int(r.qty), why) end
  if r.state == "none" then return T("subNone", why) end
  if r.state == "single" then return T("subSingle", money(r.cheapest or 0), why) end
  if r.state == "unknown" then return T("subUnknown", why) end
  return T("subPending", why)
end

local function ordersText(n)
  if n == 1 then return T.ordersOne end
  return T("ordersMany", int(n))
end

-- paints the dock from AD.content(); positions every part from the top (the height follows the content)
local function draw(c)
  local f = st.frame
  if not f then return end
  st.content = c
  local x, inner = AD.PAD, AD.W - AD.PAD * 2
  local y = 10
  pt(f.head, f, x, y)
  f.orders:ClearAllPoints()
  f.orders:SetPoint("TOPRIGHT", f, "TOPRIGHT", -AD.PAD, -y - 2)
  W.setText(f.orders, ordersText(c.orders))
  y = y + 24
  pt(f.chain, f, x, y)
  f.chain:SetStation(c.open == 0 and 3 or 2)
  y = y + 26

  -- sum box
  pt(f.box, f, x, y)
  local total
  if c.open == 0 then
    total = money(0)
  elseif c.priced == 0 then
    total = "…"
  elseif c.unpriced > 0 then
    total = T("toPayFrom", money(c.total))
  else
    total = money(c.total)
  end
  W.setText(f.box.total, total)
  local have = gold()
  W.setText(f.box.gold, have and T("yourGold", money(have)) or "")
  local age = priceAge(c)
  local busy = fetching()
  local line
  if busy then
    line = T.pricesFetching
  elseif age then
    local head = age < 90 and T.pricesNow or T("pricesAgo", int(floor(age / 60)))
    line = head .. " · |cFFF59E80" .. T.refresh .. "|r"
  else
    line = ""
  end
  W.setText(f.box.age.label, line)
  f.box.age.off = busy or st.buy ~= nil or c.open == 0
  f.box.age:SetShown(line ~= "")
  y = y + AD.BOX_H + 8

  f.msg:Hide() f.note:Hide() f.more:Hide() f.main:Hide() f.main.hint:Hide() f.cancelBtn:Hide() f.skipBtn:Hide()
  f.twoClicks:Hide() f.done:Hide()
  for _, row in ipairs(f.rows) do
    W.hideTip(row)
    row:Hide()
  end

  if c.unknown > 0 then
    W.setText(f.note, T.unknownNote)
    pt(f.note, f, x, y)
    f.note:Show()
    y = y + textHeight(f.note, 13) + 6
  end

  -- the price of a purchase stands in the window from now on: click 2 counts from this moment
  local b0 = st.buy
  if b0 and b0.state == "confirm" and not b0.shownAt then b0.shownAt = now() end

  -- material rows
  local state, selRow = AD.mainState(c)
  local sel = selRow and selRow.id or nil
  local shown, hidden = 0, 0
  for _, r in ipairs(c.rows) do
    if shown >= AD.ROWS_MAX then
      hidden = hidden + 1
    else
      shown = shown + 1
      local row = f.rows[shown]
      pt(row, f, x, y)
      row.rowId = r.id
      row.icon:SetTexture(itemIcon(r.id))
      local done = r.missing <= 0
      W.setText(row.name, done and r.name or T("rowTitle", int(r.missing), r.name))
      W.setText(row.sub, subText(r))
      local right = ""
      if r.missing > 0 then
        if r.cost then right = money(r.cost)
        elseif r.state == "single" and r.cheapest then right = ""
        elseif r.state == "pending" then right = "…"
        else right = "?" end
      end
      W.setText(row.right, right)
      row.check:SetShown(done)
      local on = sel == r.id and not done
      row.hl:SetShown(on)
      for _, e in ipairs(row.edges) do e:SetShown(on) end
      setColor(row.name, done and C.dim or C.text)
      row.tipLines = rowTip(r)
      row:Show()
      y = y + AD.ROW_H
    end
  end
  if hidden > 0 then
    W.setText(f.more, T("more", int(hidden)))
    pt(f.more, f, x, y)
    f.more:Show()
    y = y + 14
  end
  y = y + 6

  -- fixed slot for message and warning lines (reserved even when empty: the main button stays where it is between click 1 and click 2)
  local b = st.buy
  local lines, warn = {}, false
  if st.msg then
    lines[#lines + 1] = st.msg
    warn = st.msgBad
  end
  if b and b.state == "confirm" then
    b.shown = true -- the price stands in the window: only now a click may confirm
    if b.warn then
      lines[#lines + 1] = T("priceUp", money(b.total - (b.est or 0)), int(floor((b.total / (b.est or b.total) - 1) * 100 + 0.5)))
      warn = true
    end
    if b.changed then
      lines[#lines + 1] = T.changed
      warn = true
    end
  end
  if #lines > 0 then
    W.setText(f.msg, table.concat(lines, "\n"))
    setColor(f.msg, warn and C.need or C.ok)
    f.msg:Show()
  end
  pt(f.msg, f, x, y)
  y = y + AD.SLOT_H

  if not state then
    -- nothing left to buy: the final box
    W.setText(f.done.text, c.mailRows > 0 and T.doneMail or T.doneBags)
    pt(f.done, f, x, y)
    f.done:SetHeight(34 + textHeight(f.done.text, 15) + 10)
    f.done:Show()
    y = y + f.done:GetHeight()
  else
    pt(f.main, f, x, y)
    f.main:Apply(state)
    f.main:Show()
    f.main.tipLines = nil
    y = y + 34 + 3 + 16
    -- link line: Abbrechen while a purchase runs, else Ueberspringen
    if b and (b.state == "price" or b.state == "confirm") then
      pt(f.cancelBtn, f, x, y)
      f.cancelBtn:Show()
    elseif not b then
      pt(f.skipBtn, f, x, y)
      f.skipBtn:Show()
      local nxt = nextBuyable(c, sel)
      setColor(f.skipBtn.label, (not nxt or nxt.id == sel) and C.dim or C.text)
    end
    f.twoClicks:ClearAllPoints()
    f.twoClicks:SetPoint("TOPRIGHT", f, "TOPRIGHT", -AD.PAD, -y - 3)
    f.twoClicks:Show()
    y = y + 24
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
  W.hideTip(f.main)
  W.hideTip(f.box.age)
end

-- Prices: ask the missing materials of the open rows (Journal.Preisabfrage works one request at a time; known ones are skipped) ---------------

local function ensurePrices(c)
  local PA = queryer()
  if not (PA and PA.state and PA.state.open and type(PA.request) == "function") then return end
  if st.buy then return end -- a purchase in progress is never disturbed by a search
  local ids = openIds(c)
  if #ids > 0 then pcall(PA.request, ids) end
end

-- Update: the one place where visibility, placement and content come together ------------------------------------------------------------

-- force: redraw even if nothing changed
function AD.update(force)
  if not (AD.enabled() and st.open and windowShown()) then
    hideBar()
    return false
  end
  local c = AD.content()
  if c.orders == 0 then
    hideBar() -- no open work order: nothing to show
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
  ensurePrices(c)
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

-- buying is off for the rest of the session; the prices stay
local function blockBuying(text)
  AD.buyBlocked = true
  st.buy = nil
  local Wk = ns.Werk
  if Wk and Wk.cancelPurchase then Wk.cancelPurchase() end
  say(text or T.blocked, true)
end

-- asks the price of this item again (after a purchase / a vanished offer): only while the house is open and nothing is being bought
local function repriceLater(id)
  local PA = queryer()
  if PA and type(PA.request) == "function" and not st.buy then pcall(PA.request, { id }, true) end
end

-- "neu holen": every open row's price again
function AD.refresh()
  if st.buy or not st.open then return false end
  local PA = queryer()
  local c = st.content or AD.content()
  local ids = openIds(c)
  if not (PA and type(PA.refresh) == "function") or #ids == 0 then return false end
  pcall(PA.refresh, ids)
  AD.update(true)
  return true
end

-- click on a row: that material becomes the one the main button buys (not while a purchase runs)
function AD.select(id)
  id = posInt(id)
  if not id or st.buy then return false end
  local c = st.content or AD.content()
  for _, r in ipairs(c.rows) do
    if r.id == id and r.buyable then
      st.cur = id
      AD.update(true)
      return true
    end
  end
  return false
end

-- "Ueberspringen": the next buyable row
function AD.skip()
  if st.buy then return false end
  local c = st.content or AD.content()
  local row = curRow(c)
  local nxt = nextBuyable(c, row and row.id)
  if not nxt or (row and nxt.id == row.id) then return false end
  st.cur = nxt.id
  AD.update(true)
  return true
end

-- click 1: start the purchase, the price comes with COMMODITY_PRICE_UPDATED -> true | nil, reason
function AD.buy(id, qty)
  id, qty = posInt(id), posInt(qty)
  if not (id and qty and st.open) then return nil, "eingabe" end
  if not AD.canBuy() then return nil, "gesperrt" end
  if st.buy then return nil, "laeuft" end
  if inCombat() then return nil, "kampf" end
  local Pr = prices()
  local e = Pr and Pr.get(id)
  if e and e.kind == "single" then return nil, "einzel" end
  if e and e.kind == "none" then return nil, "kein-angebot" end
  if fetching() then return nil, "preise" end
  if loggedBlock() then
    blockBuying()
    AD.update(true)
    return nil, "gesperrt"
  end
  qty = min(qty, AD.BUY_MAX)
  local est = Pr and Pr.priceFor(id, qty) or nil
  if gold() == nil or (est and not AD.enoughGold(est)) then
    AD.update(true)
    return nil, "gold"
  end
  local start = apiFn("StartCommoditiesPurchase")
  local before = actionTotal()
  local ok = pcall(start, id, qty)
  if not ok or actionTotal() > before then
    blockBuying()
    AD.update(true)
    return nil, "gesperrt"
  end
  st.buy = { id = id, n = qty, name = E.itemName(id) or ("#" .. id), state = "price", est = est, deadline = now() + AD.PRICE_WAIT }
  st.cur = id
  say(nil)
  AD.update(true)
  return true
end

-- the one main button: click 1 "Kaufen" or click 2 "Bestaetigen"
function AD.mainClick()
  local b = st.buy
  if b then return AD.confirm() end
  local c = st.content or AD.content()
  local row = curRow(c)
  if not row or not row.buyable or not row.qty then return nil, "keine-zeile" end
  return AD.buy(row.id, row.qty)
end

-- "Abbrechen" (also when the house closes, combat begins or the price does not come): CancelCommoditiesPurchase, the box disappears
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

-- click 2: only with a displayed price -> true | nil, reason
function AD.confirm()
  local b = st.buy
  if not (b and b.state == "confirm" and b.shown and num(b.total)) then return nil, "kein-preis" end
  if not (b.shownAt and now() - b.shownAt >= AD.CONFIRM_DELAY) then return nil, "zu-frueh" end
  if inCombat() then
    AD.cancel(true)
    say(T.combatCancel, true)
    AD.update(true)
    return nil, "kampf"
  end
  if not AD.enoughGold(b.total) then return nil, "gold" end
  local confirmFn = apiFn("ConfirmCommoditiesPurchase")
  if not (confirmFn and not AD.buyBlocked) then return nil, "gesperrt" end
  -- quote run out: start again from this very click, the new final price has to be shown and confirmed once more
  local quote = apiFn("GetQuoteDurationRemaining")
  if quote then
    local ok, left = pcall(quote)
    left = ok and num(left) or nil
    if left and left <= 0 then
      local id, n = b.id, b.n
      AD.cancel(true)
      AD.buy(id, n)
      say(T.quoteExpired, true)
      AD.update(true)
      return nil, "abgelaufen"
    end
  end
  local Wk = ns.Werk
  if Wk and Wk.expectPurchase then Wk.expectPurchase(b.id, b.n) end -- the collector books "on the way by mail" at COMMODITY_PURCHASE_SUCCEEDED
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

-- Events and poll --------------------------------------------------------------------------------------------------------------------

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
  if b.state == "confirm" and b.total ~= total then
    b.changed = true
    b.shownAt = nil -- a changed final price gets the confirm delay again (set when it is drawn)
  end
  b.state, b.unit, b.total = "confirm", num(unit), total
  b.warn = b.est ~= nil and b.est > 0 and total > b.est * AD.WARN_OVER or false
  b.deadline = nil
  AD.update(true)
end

-- a purchase in the confirmation ends (house closed, combat): Cancel, back to "Kaufen"
local function abortPurchase(text)
  local b = st.buy
  if b and (b.state == "price" or b.state == "confirm") then
    local cancel = apiFn("CancelCommoditiesPurchase")
    if cancel then pcall(cancel) end
    st.buy = nil
    if text then say(text, true) end
    return true
  end
  return false
end

local function onEvent(_, event, arg1, arg2)
  if event == "ADDON_LOADED" then
    if arg1 == "Blizzard_AuctionHouseUI" and st.open then AD.startPoll() end
  elseif event == "AUCTION_HOUSE_SHOW" then
    st.open = true
    st.cur, st.buy, st.msg = nil, nil, nil
    AD.startPoll()
    AD.update()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    local aborted = abortPurchase()
    st.open = false
    st.buy, st.msg = nil, nil
    if aborted then st.dirty = true end
    hideBar()
  elseif event == "PLAYER_REGEN_DISABLED" then
    if abortPurchase(T.combatCancel) and st.open then AD.update(true) end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if st.wantBuild or st.open then
      st.wantBuild = false
      AD.update()
    end
  elseif event == "BAG_UPDATE_DELAYED" or event == "UPDATE_PENDING_MAIL" then
    E.invalidate()
    st.dirty = true
    if st.open then AD.update() end
  elseif event == "COMMODITY_PRICE_UPDATED" then
    onPrice(arg1, arg2)
  elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
    local b = st.buy
    if b and b.state ~= "buying" then
      st.buy = nil
      say(T.unavailable, true)
      repriceLater(b.id)
      AD.update(true)
    end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    local b = st.buy
    E.invalidate()
    if b then
      st.buy = nil
      say(T("bought", int(b.n), b.name))
      -- on to the next material; the offers of the bought one changed, its price is asked again
      local nxt = st.content and nextBuyable(st.content, b.id)
      st.cur = nxt and nxt.id ~= b.id and nxt.id or nil
      repriceLater(b.id)
    end
    st.dirty = true
    if st.open then AD.update(true) end
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    if st.buy then
      blockBuying(T.failed)
      st.dirty = true
      if st.open then AD.update(true) end
    end
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
    st.dirty = true -- a price answer (journal/Preisabfrage.lua) or item data: the next poll tick repaints
  end
end

function AD.startPoll()
  st.graceUntil = now() + AD.GRACE
  st.poll = 0
  if st.pollFrame then st.pollFrame:Show() end
end

-- quote of the running purchase run out (GetQuoteDurationRemaining <= 0): back to "Kaufen" (the click starts it again)
local function quoteGone()
  local b = st.buy
  if not (b and b.state == "confirm") then return false end
  local quote = apiFn("GetQuoteDurationRemaining")
  if not quote then return false end
  local ok, left = pcall(quote)
  left = ok and num(left) or nil
  return left ~= nil and left <= 0
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
  elseif b and quoteGone() then
    AD.cancel(true)
    say(T.quoteExpired, true)
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
  local PA = queryer()
  if PA and type(PA.onChange) == "function" then
    PA.onChange(function()
      st.dirty = true
      if st.open then AD.update() end
    end)
  end
end

init()
