-- Evaluator for the Schaetze page: ledger (income/expense per source), gold flow, gear over time, "first blue" and
-- quality counters. Pure read logic over the index and the character SV.
-- Schaetze.evaluate(index, opts) -> view; the expensive part is computed once per index (Schaetze.static). Every
-- section is guarded on its own (view.partial = true). Ledger: income - expense + start/unbooked = balance (= bag).
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Schaetze = {}
Journal.Schaetze = Schaetze

local floor, huge, min, max = math.floor, math.huge, math.min, math.max
local format, find = string.format, string.find

Schaetze.MAX_LEVEL = 60      -- WoW Forever and the fallback; the live value is Schaetze.maxLevel()
Schaetze.FLOW_NODES = 7      -- nodes per side in the gold flow (rest -> "Weitere")
Schaetze.FLOW_HEIGHT = 140   -- height of the area (px)
Schaetze.FLOW_GAP = 5        -- gap between nodes at the sides (px)
Schaetze.FLOW_MIN = 2        -- minimum height of a node (px)
Schaetze.LABEL_STEP = 13     -- minimum distance of labels (px)
Schaetze.NAME_MAX = 40       -- bytes for item names
Schaetze.GEAR_MAX = 20000    -- gear changes read
Schaetze.PER_HOUR_MIN = 600  -- "per play hour" only from 10 min of play time
Schaetze.LEVEL_COLS = 60     -- max level columns in the gold flow (the newest)

-- highest player level of the client (Journal.MapSpace.maxLevel: Forever 60, Retail 80/90); the gear strip spans 1..maxLevel
function Schaetze.maxLevel()
  local ms = Journal.MapSpace
  local v = ms and ms.maxLevel and ms.maxLevel() or nil
  return tonumber(v) or Schaetze.MAX_LEVEL
end

-- locale scope "m.Schaetze" (English in locales/enUS_model.lua); rows, qualities and slots read their labels on access
-- (metatable)
local Loc = ns.Locale
local TEXT = Loc.ns("m.Schaetze", {
  noMoney = "Noch kein Gold bewegt.",
  beutel = "Im Beutel",
  unknown = "unbekannt",
  noItem = "Platz leer",
  noEntry = "Kein Eintrag",
  noBlue = "Noch kein seltenes Stück gefunden.",
  restLabel = "Startgeld und Sonstiges",
  repairNote = "Einzelreparaturen sind eine Näherung.",
  totalLabel = "Bestand",
  incomeHead = "EINNAHMEN", expenseHead = "AUSGABEN",
  sumIn = "Summe Einnahmen", sumOut = "Summe Ausgaben",
  rest = "Weitere", inBag = "Im Beutel", unbooked = "Unverbucht", start = "Anfang",
  in_loot = "Beute", in_quest = "Quests", in_vendor = "Händler", in_ah = "Auktionshaus", in_mail = "Post", in_trade = "Handel",
  in_guildbank = "Gildenbank", in_other = "Sonstiges",
  out_training = "Training", out_repair = "Reparatur", out_vendor_buy = "Händlerkäufe", out_taxi = "Flüge", out_ah = "Auktionshaus",
  out_mail = "Post", out_trade = "Handel", out_guildbank = "Gildenbank", out_other = "Sonstiges",
  slot_1 = "Kopf", slot_3 = "Schultern", slot_5 = "Brust", slot_7 = "Beine", slot_8 = "Füße", slot_16 = "Haupthand", slot_17 = "Nebenhand",
  slot_4 = "Hemd", slot_6 = "Taille", slot_9 = "Handgelenke", slot_10 = "Hände", slot_15 = "Umhang", slot_18 = "Distanz", slot_19 = "Wappenrock",
  level = "Stufe %s",
  levels = "Stufen %s–%s",
  itemFallback = "Gegenstand %s",
  quality = "Güte: %s",
  aRareItem = "Ein seltenes Stück",
  firstBlue = "Erstes Seltenes",
  firstBlueLv = "Erstes Seltenes · St. %s",
  epicTip = "Epische und legendäre Funde zusammen",
  grey = "Dazu %s Stücke der Güte Schlecht",
  ofSum = "%s der Summe",
  under1 = "unter 1 %",
  pct = "%s %%",
  ahNote = "Käufe, Pfand und Gebühren; die Rechnung trennt sie nicht",
  restTip1 = "Startgeld plus alles, was keiner Zeile zugeordnet wurde",
  restTip2 = "(z. B. Änderungen zwischen zwei Sitzungen).",
  ofFlow = "%s des Flusses",
  income = "Einnahmen: %s",
  expense = "Ausgaben: %s",
  saldo = "Saldo: %s",
  traveller = "Reisende/r",
  headLevel = "Stufe %s",
  day = "Tag %s",
  perHour = "ca. %s je Spielstunde",
  holdTop = "Höchster Besitz: %s",
  holdEnd = "Am Stufenende: %s",
  holdNow = "Jetzt im Beutel: %s",
  holdJump = "Zur Vorstufe: %s",
  holdPeak = "Höchststand insgesamt",
  -- gold flow view "Handel": auction house, mail, trade (P4)
  tr_ahHead = "Auktionshaus", tr_mailHead = "Post", tr_tradeHead = "Handel",
  tr_ahIncome = "Einnahmen", tr_ahSold = "Verkäufe", tr_ahSpent = "Ausgaben", tr_ahBought = "Käufe",
  tr_ahFee = "Provision", tr_ahDeposit = "Pfand gezahlt",
  tr_ahTip = "Nach den Rechnungen im Briefkasten; das Haushaltsbuch bleibt unberührt.",
  tr_ahIncomeTip = "Verkaufspreise laut Rechnung, vor Abzug der Provision.",
  tr_ahFeeTip = "Abzug der Auktionshaus-Provision bei Verkäufen.",
  tr_ahDepositTip = "Pfand beim Einstellen, für %s Einstellungen. Was davon verfiel oder zurückkam, steht in keiner Rechnung.",
  tr_ahCount = "%s Rechnungen",
  tr_mailGold = "Goldpost von %s", tr_mailItem = "Päckchen von %s", tr_cod = "Nachnahme gezahlt",
  tr_mailGoldTip = "Größte Goldsendung, die du aus einem Brief genommen hast.",
  tr_mailItemTip = "Größter Stapel, den du aus einem Brief genommen hast.",
  tr_codTip = "Zur Orientierung; keine zusätzliche Ausgabe im Haushaltsbuch.",
  tr_tradeGold = "Gold von %s", tr_tradeItem = "Gabe von %s",
  tr_tradeGoldTip = "Der größte Goldbetrag, den du im Handel bekommen hast.",
  tr_tradeItemTip = "Der größte Stapel, den du im Handel bekommen hast.",
  tr_stack = "%s× %s",
  tr_from = "Von: %s",
})
Schaetze.TEXT = TEXT

-- label on read: field "label" = TEXT[prefix .. entry[idField]]
local function lazyLabel(list, prefix, idField)
  for _, e in pairs(list) do
    setmetatable(e, { __index = function(t, k) if k == "label" then return TEXT[prefix .. tostring(t[idField])] end end })
  end
end

-- ledger rows. keys = sources from GD.source (Index.money.source); always = row even at 0; "other" catches all remaining sources
-- (except start/gap, which sit in "Startgeld und Sonstiges"). color = colour in the gold flow.
Schaetze.IN_ROWS = {
  { key = "loot", keys = { "loot" }, always = true, color = "gold" },
  { key = "quest", keys = { "quest" }, always = true, color = "blue" },
  { key = "vendor", keys = { "vendor_sell" }, always = true, color = "treasure" },
  { key = "ah", keys = { "ah_sale", "ah" }, always = true, color = "memory" },
  { key = "mail", keys = { "mail" }, color = "sepia" },
  { key = "trade", keys = { "trade" }, color = "ink" },
  { key = "guildbank", keys = { "guildbank" }, color = "red" },
  { key = "other", keys = { "other" }, color = "faint", rest = true },
}
lazyLabel(Schaetze.IN_ROWS, "in_", "key")
Schaetze.OUT_ROWS = {
  { key = "training", keys = { "training" }, always = true, color = "red" },
  { key = "repair", keys = { "repair" }, always = true, color = "sepia" },
  { key = "vendor_buy", keys = { "vendor_buy" }, always = true, color = "gold" },
  { key = "taxi", keys = { "taxi" }, always = true, color = "blue" },
  { key = "ah", keys = { "ah", "ah_sale" }, always = true, color = "memory", tipNote = true },
  { key = "mail", keys = { "mail" }, color = "treasure" },
  { key = "trade", keys = { "trade" }, color = "ink" },
  { key = "guildbank", keys = { "guildbank" }, color = "faint" },
  { key = "other", keys = { "other" }, color = "faint", rest = true },
}
lazyLabel(Schaetze.OUT_ROWS, "out_", "key")
-- warband: transfers to/from the Warband bank (Retail) are neither income nor expense (new lines carry no amount; older ones are skipped here)
local SKIP_SOURCES = { gap = true, start = true, warband = true }
-- display name of the purpose in margin notes
local PURPOSE = { training = "training", repair = "repair", vendor_buy = "vendor_buy", taxi = "taxi", ah = "ah" }

-- qualities (one shade darker on parchment than in game). Names: Blizzard qualities (centrally Fmt.QUALITY)
Schaetze.QUALITY = {
  [0] = { q = 0, color = { 0.45, 0.45, 0.45 } },
  [1] = { q = 1, color = { 0.66, 0.62, 0.54 } },
  [2] = { q = 2, color = { 0.20, 0.48, 0.18 } },
  [3] = { q = 3, color = { 0.17, 0.31, 0.48 } },
  [4] = { q = 4, color = { 0.35, 0.23, 0.47 } },
  [5] = { q = 5, color = { 0.72, 0.34, 0.08 } },
}
-- quality name centrally via Fmt.qualityName (bilingual, Blizzard names only for a matching game language)
for _, e in pairs(Schaetze.QUALITY) do
  setmetatable(e, { __index = function(t, k) if k == "label" then return Journal.Fmt.qualityName(t.q) end end })
end
local QUALITY_UNKNOWN = { 0.42, 0.31, 0.20 } -- sepia: item known, quality not

-- selectable equipment slots (INVSLOT, 7 slots)
Schaetze.GEAR_SLOTS = {
  { slot = 1 }, { slot = 3 }, { slot = 5 }, { slot = 7 }, { slot = 8 }, { slot = 16 }, { slot = 17 },
}
lazyLabel(Schaetze.GEAR_SLOTS, "slot_", "slot")

-- slots that show on the character model (INVSLOT) in the order of the list; neck, rings and trinkets are invisible and left out.
-- hand = handSlotName for DressUpModel:TryOn (main hand / off hand), ranged = slot 18 (bow, wand ...)
Schaetze.WARDROBE_SLOTS = {
  { slot = 1 }, { slot = 3 }, { slot = 15 }, { slot = 5 }, { slot = 4 }, { slot = 19 }, { slot = 9 }, { slot = 10 }, { slot = 6 },
  { slot = 7 }, { slot = 8 }, { slot = 16, hand = "MAINHANDSLOT" }, { slot = 17, hand = "SECONDARYHANDSLOT" }, { slot = 18 },
}
lazyLabel(Schaetze.WARDROBE_SLOTS, "slot_", "slot")

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function finite(v)
  return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local function T() return Journal.Texts end
local function I() return Journal.Index end

local function display(v, n)
  local s = ns.Sanitize
  return s and s.display(v, n) or nil
end

local function int(n)
  local t = T()
  return t and t.int(n) or tostring(n)
end

local function num(v)
  if isSecret(v) then return nil end
  v = tonumber(v)
  if finite(v) then return v end
  return nil
end

-- entry of an SV table with a number key (number or text key)
local function byId(tbl, id)
  if type(tbl) ~= "table" or id == nil then return nil end
  local v = tbl[id]
  if v == nil and type(id) == "number" then v = tbl[format("%.0f", id)] end
  return v
end

local function snapGroup(char, name)
  local s = type(char) == "table" and char.snapshots
  local g = type(s) == "table" and s[name]
  return type(g) == "table" and g or nil
end

local function posId(v)
  if type(v) == "number" then
    if not finite(v) or v <= 0 or v ~= floor(v) or v >= 2147483648 then return nil end
    return v
  end
  if type(v) ~= "string" or not find(v, "^%d+$") or #v > 10 then return nil end
  local n = tonumber(v)
  if not n or n <= 0 or n >= 2147483648 then return nil end
  return n
end

-- copper -> gold, silver, copper (amount; the caller carries the sign)
function Schaetze.split(copper)
  local c = num(copper)
  if not c then return 0, 0, 0 end
  c = floor(math.abs(c) + 0.5)
  return floor(c / 10000), floor(c % 10000 / 100), c % 100
end

-- amount with coin icons (centrally Texts.money); short = the two largest places; plain = letters (for text snippets
-- whose {=} check allows no "|");
-- non-number -> "?". size = font size of the display in px (coin icon to match; default Texts.COIN_SIZE)
function Schaetze.moneyText(copper, short, plain, size)
  local c = num(copper)
  if not c then return "?" end
  return T().money(c, plain and "plain" or (short and "short" or nil), size)
end

-- column numbers for the right-aligned table (Texts.moneyCols): gold only from gold, silver only from silver, copper always
local function columns(copper, size)
  return T().moneyCols(num(copper) or 0, size)
end

-- display font sizes (px), matching pages/Schaetze.lua: bag large, table rows 14 (total row 16), chart label 10, total
-- at the flow 11, "per play hour" 12
Schaetze.FONT = { bag = 34, row = 14, total = 16, label = 10, flowTotal = 11, perHour = 12 }

local function row(kind, label, copper, extra)
  local r = { kind = kind, label = label, copper = copper }
  if copper ~= nil then
    r.g, r.s, r.k = columns(copper, kind == "total" and Schaetze.FONT.total or Schaetze.FONT.row)
    r.neg = copper < 0 and floor(math.abs(copper) + 0.5) > 0
    r.zero = floor(math.abs(copper) + 0.5) == 0
  end
  if extra then for k, v in pairs(extra) do r[k] = v end end
  return r
end

-- sums per source from the index (Index.money.source); fallback: the counters counters.money_in/money_out
local function sourceTotals(index, char)
  local m = type(index.money) == "table" and index.money or {}
  local gain, loss = {}, {}
  local any = false
  if type(m.source) == "table" then
    for k, e in pairs(m.source) do
      if type(k) == "string" and not SKIP_SOURCES[k] and type(e) == "table" then
        local g, l = num(e.gain), num(e.loss)
        if g and g > 0 then gain[k], any = g, true end
        if l and l > 0 then loss[k], any = l, true end
      end
    end
  end
  if not any then
    local counters = type(char) == "table" and type(char.counters) == "table" and char.counters or {}
    for group, into in pairs({ money_in = gain, money_out = loss }) do
      local g = counters[group]
      if type(g) == "table" then
        for k, v in pairs(g) do
          v = num(v)
          if type(k) == "string" and not SKIP_SOURCES[k] and v and v > 0 then into[k] = v end
        end
      end
    end
  end
  return gain, loss
end

-- rows (definition + sums per source) -> list { key, label, copper, color, always, tipNote }, total
local function sumRows(defs, amounts)
  local used = {}
  for _, d in ipairs(defs) do
    if not d.rest then for _, k in ipairs(d.keys) do used[k] = true end end
  end
  local out, total = {}, 0
  for _, d in ipairs(defs) do
    local c = 0
    if d.rest then
      for k, v in pairs(amounts) do
        if not used[k] then c = c + v end
      end
    else
      for _, k in ipairs(d.keys) do c = c + (amounts[k] or 0) end
    end
    total = total + c
    out[#out + 1] = { key = d.key, label = d.label, copper = c, color = d.color, always = d.always == true,
      tipNote = d.tipNote }
  end
  return out, total
end

local function moneyStatic(index, char)
  local gain, loss = sourceTotals(index, char)
  local inRows, inTotal = sumRows(Schaetze.IN_ROWS, gain)
  local outRows, outTotal = sumRows(Schaetze.OUT_ROWS, loss)
  local m = type(index.money) == "table" and index.money or {}
  local last = type(m.last) == "table" and num(m.last.balance) or nil
  return { inRows = inRows, inTotal = inTotal, outRows = outRows, outTotal = outTotal, last = last, levels = m.level,
    hold = m.hold }
end

-- bag: live (GetMoney), else last balance from the log, else the saved state
local function beutelOf(index, st, live)
  local c, source
  local v = live and live.money and live.money() or nil
  if num(v) and v >= 0 then
    c, source = floor(v), "live"
  elseif st.money and st.money.last then
    c, source = floor(st.money.last), "sv"
  else
    local state = snapGroup(index.char, "state")
    local m = state and state.money
    local b = type(m) == "table" and num(m.balance) or nil
    if b and b >= 0 then c, source = floor(b), "sv" end
  end
  return c, source
end

local function levelOf(rec, code)
  local v = I().num(rec, code, "level")
  if v and v >= 1 and v <= 200 then return floor(v) end
  return nil
end

local function indexLevel(index, char)
  local Idx = I()
  local lv = Idx.list(index, "LV")
  local L = lv[#lv] and levelOf(lv[#lv], "LV")
  if L then return L end
  local pl = Idx.list(index, "PL")
  L = pl[#pl] and levelOf(pl[#pl], "PL")
  return L
end

-- seconds played now: last PL.total plus active time since the answer (as Chronik, local there)
local function playedSeconds(index, now)
  local Idx = I()
  local list = Idx.list(index, "PL")
  for i = #list, 1, -1 do
    local total = Idx.num(list[i], "PL", "total")
    if total and total >= 0 and finite(list[i].t) then
      local extra = now > list[i].t and (Idx.activeSeconds(index, list[i].t, now)) or 0
      return total + extra
    end
  end
  if finite(index.startT) and now >= index.startT then
    return (Idx.activeSeconds(index, index.startT, now))
  end
  return nil
end

local function itemIdOf(key)
  if type(key) == "number" then return posId(key) end
  if type(key) ~= "string" then return nil end
  return posId(string.match(key, "^(%d+)"))
end

local function slotValue(snap, slot)
  local v = snap[slot]
  if v == nil then v = snap[format("%d", slot)] end
  if v == nil or isSecret(v) then return false end
  if type(v) == "number" then v = format("%.0f", v) end
  if type(v) ~= "string" or v == "" then return false end
  return v
end

local function levelLabel(from, to)
  if from == to then return TEXT("level", from) end
  return TEXT("levels", from, to)
end

-- Shared by gearHistory and wardrobe: the snapshots (sorted by level) and the GW lines per slot (slots 1..19) of a character.
-- -> snaps { { level, t, v } }, bySlot { [slot] = { { level, ord = 1, t, seq, item = key|false, prev = key|false|nil } } }, number of
-- GW lines of the slots read. A GW line with "?" (not readable) is no proof and is left out; prev nil = unknown, false = empty.
local function collectGear(index, char)
  local Idx = I()
  local snaps = {}
  for k, v in pairs(snapGroup(char, "gear") or {}) do
    local L = num(k)
    if L and L >= 1 and L <= 200 and type(v) == "table" then
      snaps[#snaps + 1] = { level = floor(L), t = num(v.at) or 0, v = v }
    end
  end
  table.sort(snaps, function(a, b) return a.level < b.level end)

  local bySlot, total, seen = {}, 0, 0
  local lastLevel = 1
  for _, r in ipairs(Idx.list(index, "GW")) do
    seen = seen + 1
    if seen > Schaetze.GEAR_MAX then break end
    local slot = Idx.num(r, "GW", "slot")
    local L = levelOf(r, "GW")
    if L then lastLevel = L end
    if slot and slot >= 1 and slot <= 19 then
      slot = floor(slot)
      total = total + 1
      local item, locked = Idx.str(r, "GW", "item")
      local before, beforeLocked = Idx.str(r, "GW", "prev")
      local list = bySlot[slot]
      if not list then
        list = {}
        bySlot[slot] = list
      end
      if not locked then -- "?" = not readable: no proof
        local prev = nil
        if not beforeLocked then prev = before or false end -- "" = the slot was empty, "?" = unknown
        list[#list + 1] = { level = L or lastLevel, ord = 1, t = r.t or 0, seq = seen, item = item or false, prev = prev }
      end
    end
  end
  return snaps, bySlot, total
end

-- Observations of one slot in order (level, snapshot before change, time, line): snapshots (ord 0) and changes (ord 1). A sequence
-- that starts with a change begins with that change's previous item (valid from level 1).
local function slotObservations(snaps, bySlot, slot)
  local obs = {}
  for i, s in ipairs(snaps) do
    obs[#obs + 1] = { level = s.level, ord = 0, t = s.t, seq = -1000000 + i, item = slotValue(s.v, slot) }
  end
  for _, o in ipairs(bySlot[slot] or {}) do obs[#obs + 1] = o end
  table.sort(obs, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    if a.ord ~= b.ord then return a.ord < b.ord end
    if a.t ~= b.t then return a.t < b.t end
    return a.seq < b.seq
  end)
  if obs[1] and obs[1].ord == 1 and obs[1].prev ~= nil then
    table.insert(obs, 1, { level = 1, ord = -1, t = 0, seq = -2000000, item = obs[1].prev })
  end
  return obs
end

local function gearHistory(index, char, level)
  local items = snapGroup(char, "items")
  local snaps, bySlot, total = collectGear(index, char)

  local top = Schaetze.maxLevel()
  local cap = min(max(level or 1, 1), top)
  local rows = {}
  for _, def in ipairs(Schaetze.GEAR_SLOTS) do
    local obs = slotObservations(snaps, bySlot, def.slot)
    -- state at the end of each level: last observation with level <= L
    local runs, cur, p = {}, nil, 1
    local run
    for L = 1, cap do
      while p <= #obs and obs[p].level <= L do
        cur = obs[p].item
        p = p + 1
      end
      local key = cur -- nil = unknown, false = empty, text = item
      local same = run and run.key == key
      if same then
        run.to = L
      else
        run = { from = L, to = L, key = key }
        runs[#runs + 1] = run
      end
    end
    local last
    for _, r in ipairs(runs) do
      r.empty = r.key == false
      r.unknown = r.key == nil
      local q
      if r.key then
        local id = itemIdOf(r.key)
        local e = id and byId(items, id)
        if type(e) == "table" then
          r.name = display(e.name, Schaetze.NAME_MAX)
          q = num(e.quality)
          if q then q = floor(q) end
          if q and not Schaetze.QUALITY[q] then q = nil end
        end
        r.quality = q
        r.color = q and Schaetze.QUALITY[q].color or QUALITY_UNKNOWN
        last = r
      end
      local tip = {}
      if r.key then
        tip[1] = r.name or TEXT("itemFallback", itemIdOf(r.key) and int(itemIdOf(r.key)) or "?")
        tip[2] = levelLabel(r.from, r.to)
        tip[3] = q and TEXT("quality", Schaetze.QUALITY[q].label) or nil
      else
        tip[1] = r.empty and TEXT.noItem or TEXT.noEntry
        tip[2] = levelLabel(r.from, r.to)
      end
      tip.item = r.key and T().itemString(r.key) or nil -- original tooltip (item string only from checked numbers)
      r.tip = tip
      r.key = nil -- the raw key stays in the evaluator
    end
    local changes = #(bySlot[def.slot] or {})
    local lastInfo
    if last then lastInfo = { name = last.name, level = last.to, quality = last.quality } end
    rows[#rows + 1] = { slot = def.slot, label = def.label, changes = changes, runs = runs, last = lastInfo }
  end
  -- empty: not a single proof (neither snapshot nor change)
  local empty = #snaps == 0 and total == 0
  return { level = cap, maxLevel = top, changes = total, changesText = int(total), rows = rows, empty = empty }
end

-- Heals holes of the snapshots of one slot (before 1.0.1 a crafted item with an unreadable link left its slot out of the snapshot,
-- which looks like "empty"). A snapshot value "empty" counts as worn when the evidence on both sides names the same item: the
-- observation before it holds it (or there is none and the change after it says it was worn before), and the next observation
-- confirms it (next snapshot value, or the previous item of the next change). Works in place; returns the number of healed holes.
local function healHoles(obs)
  local healed = 0
  for i, o in ipairs(obs) do
    if o.ord == 0 and o.item == false then
      local before, after = obs[i - 1], obs[i + 1]
      local evidence = after and (after.ord == 0 and after.item or (after.ord == 1 and after.prev)) or nil
      if type(evidence) == "string" and ((before and before.item == evidence) or (not before and after.ord == 1)) then
        o.item = evidence
        healed = healed + 1
      end
    end
  end
  return healed
end

-- Equipment of the visible slots at the end of every recorded level, for the "Ausrüstungsreise" (journey of the equipment).
-- Schaetze.wardrobe(index, char, level) -> {
--   first = first recorded level (first snapshot, else first change), last = current level (level, else the highest known),
--   levels = { [L] = { [slot] = itemKey | false (empty) } } for first..last (a slot without any proof is missing),
--   changed = { [L] = { slot, ... } } slots whose item differs from the level before (level first: all worn slots),
--   slots = Schaetze.WARDROBE_SLOTS, healed = healed snapshot holes, empty = nothing recorded }
-- Levels before the first record are left out on purpose (nothing is invented). Same mixing rules as gearHistory
-- (snapshot before change on the same level; "?" lines are no proof). The raw item keys go to the UI only through
-- Texts.itemString (checked numbers).
function Schaetze.wardrobe(index, char, level)
  local snaps, bySlot = collectGear(index, char)
  local out = { levels = {}, changed = {}, slots = Schaetze.WARDROBE_SLOTS, healed = 0, empty = true }
  local obsOf, first, highest = {}, nil, 0 -- highest = highest level with any record
  for _, def in ipairs(Schaetze.WARDROBE_SLOTS) do
    local obs = slotObservations(snaps, bySlot, def.slot)
    out.healed = out.healed + healHoles(obs)
    obsOf[def.slot] = obs
    for _, o in ipairs(obs) do
      if o.ord ~= -1 and o.level > highest then highest = o.level end
    end
  end
  if #snaps > 0 then
    first = snaps[1].level
  else
    for _, def in ipairs(Schaetze.WARDROBE_SLOTS) do
      for _, o in ipairs(bySlot[def.slot] or {}) do
        if not first or o.level < first then first = o.level end
      end
    end
  end
  if not first then return out end
  out.empty = false
  local top = Schaetze.maxLevel()
  local last = num(level)
  last = last and floor(last) or nil
  if snaps[#snaps] and snaps[#snaps].level > highest then highest = snaps[#snaps].level end
  if not last or last < 1 then last = highest end
  last = min(max(last, first), max(top, first))
  out.first, out.last = first, last

  local pos, cur = {}, {}
  for _, def in ipairs(Schaetze.WARDROBE_SLOTS) do pos[def.slot] = 1 end
  local prevState = {}
  for L = first, last do
    local state, changed = {}, {}
    for _, def in ipairs(Schaetze.WARDROBE_SLOTS) do
      local obs, p = obsOf[def.slot], pos[def.slot]
      while p <= #obs and obs[p].level <= L do
        cur[def.slot] = obs[p].item
        p = p + 1
      end
      pos[def.slot] = p
      local v = cur[def.slot]
      state[def.slot] = v
      if v ~= prevState[def.slot] and (v ~= nil) and (L > first or v ~= false) then changed[#changed + 1] = def.slot end
    end
    out.levels[L], out.changed[L] = state, changed
    prevState = state
  end
  return out
end

-- display data of one item key for the UI: { id, name (display-ready or nil), quality (0..7 or nil), color, string (item: string) }
function Schaetze.itemInfo(char, key)
  local id = itemIdOf(key)
  if not id then return nil end
  local e = byId(snapGroup(char, "items"), id)
  local info = { id = id, string = T().itemString(key) }
  if type(e) == "table" then
    info.name = display(e.name, Schaetze.NAME_MAX)
    local q = num(e.quality)
    if q then q = floor(q) end
    if q and Schaetze.QUALITY[q] then info.quality = q end
  end
  info.color = info.quality and Schaetze.QUALITY[info.quality].color or QUALITY_UNKNOWN
  return info
end

local function firstBlue(index, char)
  local Idx = I()
  local Chronik = Journal.Chronik
  local maps = snapGroup(char, "maps")
  local items = snapGroup(char, "items")
  local mo
  for _, r in ipairs(Idx.list(index, "MO")) do
    if Idx.str(r, "MO", "kind") == "first_blue" then
      mo = r
      break
    end
  end
  local moments = snapGroup(char, "moments")
  local snap = moments and moments.first_blue
  if type(snap) ~= "table" or snap.seen ~= true then snap = nil end
  if not mo and not snap then return nil end
  local level = mo and levelOf(mo, "MO")
  if not level and snap then
    local L = num(snap.level)
    if L and L >= 1 and L <= 200 then level = floor(L) end
  end
  local itemID = (mo and posId(Idx.str(mo, "MO", "value"))) or (snap and posId(snap.value))
  -- item key with bonus IDs: the first find (LT) of this item, else only the itemID
  local link
  if itemID then
    local seen = 0
    for _, r in ipairs(Idx.list(index, "LT")) do
      seen = seen + 1
      if seen > Schaetze.GEAR_MAX then break end
      local key = Idx.str(r, "LT", "item")
      if key and itemIdOf(key) == itemID then
        link = T().itemString(key)
        break
      end
    end
    link = link or T().itemString(itemID)
  end
  local name
  if itemID then
    local e = byId(items, itemID)
    if type(e) == "table" then name = display(e.name, Schaetze.NAME_MAX) end
  end
  local t = (mo and mo.t) or (snap and num(snap.at))
  local zone
  if mo then
    zone = display(Idx.str(mo, "MO", "sub"), 48)
    if not zone then
      local m = posId(Idx.str(mo, "MO", "mapID"))
      local e = m and byId(maps, m)
      if type(e) == "table" then zone = display(e.name, 48) end
    end
  end
  local parts = {}
  parts[#parts + 1] = name or TEXT.aRareItem
  local when = t and Chronik and Chronik.dateText and Chronik.dateText(index, t) or nil
  if when and zone then
    parts[#parts + 1] = when .. " · " .. zone
  elseif when or zone then
    parts[#parts + 1] = when or zone
  end
  return {
    title = level and TEXT("firstBlueLv", level) or TEXT.firstBlue,
    body = table.concat(parts, "\n"),
    item = link,
  }
end

local function qualityOf(char)
  local counters = type(char) == "table" and type(char.counters) == "table" and char.counters or {}
  local g = type(counters.loot_quality) == "table" and counters.loot_quality or {}
  local function count(q)
    local v = num(byId(g, q))
    return (v and v > 0) and floor(v) or 0
  end
  local epic = count(4) + count(5)
  local gems = {
    { key = "epic", label = Schaetze.QUALITY[4].label, q = 4, count = epic, color = Schaetze.QUALITY[4].color,
      tip = { Schaetze.QUALITY[4].label, TEXT.epicTip } },
    { key = "rare", label = Schaetze.QUALITY[3].label, q = 3, count = count(3), color = Schaetze.QUALITY[3].color },
    { key = "green", label = Schaetze.QUALITY[2].label, q = 2, count = count(2), color = Schaetze.QUALITY[2].color },
    { key = "white", label = Schaetze.QUALITY[1].label, q = 1, count = count(1), color = Schaetze.QUALITY[1].color },
  }
  local total = epic + count(3) + count(2) + count(1) + count(0)
  for _, gm in ipairs(gems) do
    gm.text = int(gm.count) -- epic shows 0 too (formerly "?"), the explanation is in the tooltip
  end
  local grey = count(0)
  return { total = total, gems = gems, grey = grey,
    greyText = grey > 0 and TEXT("grey", int(grey)) or nil }
end

local function marginInfo(st)
  local levels = st.money and st.money.levels
  if type(levels) ~= "table" then return nil end
  local bestOut, bestLvl, bestPurpose = 0, nil, nil
  local bestIn, bestInLvl = 0, nil
  for L, e in pairs(levels) do
    if type(L) == "number" and type(e) == "table" then
      local gain = num(e.gain)
      if gain and gain > bestIn then bestIn, bestInLvl = gain, L end
      if type(e.out) == "table" then
        for src, v in pairs(e.out) do
          v = num(v)
          if type(src) == "string" and not SKIP_SOURCES[src] and v and v > bestOut then bestOut, bestLvl, bestPurpose = v, L, src end
        end
      end
    end
  end
  return { out = bestOut, outLevel = bestLvl, purpose = bestPurpose, income = bestIn, inLevel = bestInLvl }
end

local function marginNotes(st, index)
  local info = marginInfo(st)
  local Texts = T()
  if not info or not Texts then return {} end
  local seed = Texts.seed(type(index.char) == "table" and type(index.char.info) == "table" and index.char.info.firstSeen)
  local used, out = {}, {}
  if info.outLevel and info.out >= 100 then -- from 1 silver
    local ctx = { kind = "spend", level = info.outLevel, amount = Schaetze.moneyText(info.out, true, true),
      purpose = PURPOSE[info.purpose] or "other" }
    local s = Texts.pick("margin", ctx, seed, "spend", used)
    if s then out[#out + 1] = s end
  end
  if info.inLevel and info.income >= 100 and info.inLevel ~= info.outLevel then
    local ctx = { kind = "earn", level = info.inLevel, amount = Schaetze.moneyText(info.income, true, true) }
    local s = Texts.pick("margin", ctx, seed, "earn", used)
    if s then out[#out + 1] = s end
  end
  return out
end

-- ---- view "Handel" in the gold flow: auction house, mail, trade (spec Datenbuecher P4) ----
-- Raw numbers once per index (language-free); the display texts are built in Schaetze.tradeView on every evaluation.
-- Sources: index.ah[action] = { n, deposit, price } (AH lines), the lists PM/PS/TH (Index.LISTS). Only readable numbers:
-- AH sums come from the invoices (sold/bought); the deposit that expired or came back is in no line and is not guessed.
-- No double counting: nothing here feeds the ledger or the gold flow; AH mails (ah = 1) stay out of the mail rows.
Schaetze.TRADE_LIST_MAX = 20000 -- records read per list (Index.LIST_MAX)
Schaetze.TRADE_NAME_MAX = 16    -- bytes of a partner/sender name
Schaetze.TRADE_ITEM_MAX = 22    -- bytes of an item name in a value

local function ahSum(ah, action)
  local e = ah[action]
  if type(e) ~= "table" then return nil end
  local n = num(e.n)
  if not n or n <= 0 then return nil end
  local dep, price = num(e.deposit), num(e.price)
  return { n = floor(n), deposit = dep and dep > 0 and floor(dep) or 0, price = price and price > 0 and floor(price) or 0 }
end

-- "key*count,key,..." (item text of TH/PM/PS) -> largest single stack { key, count } or nil
local function bestStack(text, best)
  if type(text) ~= "string" or text == "" then return best end
  for part in string.gmatch(text, "[^,]+") do
    local key, c = string.match(part, "^(.-)%*(%d+)$")
    if not key then key, c = part, "1" end
    local count = tonumber(c)
    if count and count >= 1 and count < 1e7 and find(key, "^%d+[%.:%d]*$") and itemIdOf(key) and (not best or count > best.count) then
      best = { key = key, count = floor(count) }
    end
  end
  return best
end

-- name of a record field: sanitized, nil if empty/unreadable ("?" = locked name)
local function who(rec, pos)
  local v = pos and rec[pos]
  if type(v) ~= "string" or v == "" or v == "?" then return nil end
  return display(v, Schaetze.TRADE_NAME_MAX)
end

local function tradeData(index, char)
  local Idx = I()
  local d = {}
  local ah = type(index.ah) == "table" and index.ah or {}
  local sold, bought, posted = ahSum(ah, "sold"), ahSum(ah, "bought"), ahSum(ah, "post")
  if (sold and sold.price > 0) or (bought and bought.price > 0) or (sold and sold.deposit > 0) or (posted and posted.deposit > 0) then
    d.ah = { sold = sold, bought = bought, posted = posted }
  end

  local pm = Idx.fields("PM")
  if pm then
    local gold, item, cod = nil, nil, 0
    local list = Idx.list(index, "PM")
    for i = 1, math.min(#list, Schaetze.TRADE_LIST_MAX) do
      local r = list[i]
      if type(r) == "table" and r[pm.ah] ~= "1" then -- AH payouts are already in the AH rows
        local m = num(r[pm.money])
        if m and m > 0 and (not gold or m > gold.amount) then gold = { amount = floor(m), who = who(r, pm.sender) } end
        local s = bestStack(r[pm.items], nil)
        if s and (not item or s.count > item.count) then item = { key = s.key, count = s.count, who = who(r, pm.sender) } end
        local c = num(r[pm.cod])
        if c and c > 0 then cod = cod + floor(c) end
      end
    end
    if gold or item or cod > 0 then d.mail = { gold = gold, item = item, cod = cod > 0 and cod or nil } end
  end

  local th = Idx.fields("TH")
  if th then
    local gold, item = nil, nil
    local list = Idx.list(index, "TH")
    for i = 1, math.min(#list, Schaetze.TRADE_LIST_MAX) do
      local r = list[i]
      if type(r) == "table" then
        local g = num(r[th.getGold])
        if g and g > 0 and (not gold or g > gold.amount) then gold = { amount = floor(g), who = who(r, th.partner) } end
        local s = bestStack(r[th.get], nil)
        if s and (not item or s.count > item.count) then item = { key = s.key, count = s.count, who = who(r, th.partner) } end
      end
    end
    if gold or item then d.trade = { gold = gold, item = item } end
  end
  if not (d.ah or d.mail or d.trade) then return nil end
  return d
end

-- item name for a value: from the item snapshot, sanitized and shortened; else "Gegenstand <id>"
local function stackText(char, key, count)
  local id = itemIdOf(key)
  local e = id and byId(snapGroup(char, "items"), id) or nil
  local name = type(e) == "table" and display(e.name, Schaetze.TRADE_ITEM_MAX) or nil
  return TEXT("tr_stack", int(count), name or TEXT("itemFallback", int(id or 0)))
end

local function money(c) return Schaetze.moneyText(c, true, false, 11) end

-- display-ready sections { { key, head, rows = { { key, label, value, tip } } } } or nil. Rows without readable numbers are left out.
function Schaetze.tradeView(raw, char)
  if type(raw) ~= "table" then return nil end
  local sections = {}
  local function add(key, head, rows) if #rows > 0 then sections[#sections + 1] = { key = key, head = head, rows = rows } end end
  local function nameOf(w) return w or TEXT.unknown end

  if raw.ah then
    local rows, a = {}, raw.ah
    local ahTip = TEXT.tr_ahTip
    if a.sold and a.sold.price > 0 then
      rows[#rows + 1] = { key = "ahIncome", label = TEXT.tr_ahIncome, value = money(a.sold.price),
        tip = { TEXT.tr_ahIncome, TEXT.tr_ahIncomeTip, TEXT("tr_ahCount", int(a.sold.n)), ahTip } }
    end
    if a.sold then
      rows[#rows + 1] = { key = "ahSold", label = TEXT.tr_ahSold, value = int(a.sold.n), tip = { TEXT.tr_ahSold, ahTip } }
    end
    if a.bought and a.bought.price > 0 then
      rows[#rows + 1] = { key = "ahSpent", label = TEXT.tr_ahSpent, value = money(a.bought.price),
        tip = { TEXT.tr_ahSpent, TEXT("tr_ahCount", int(a.bought.n)), ahTip } }
    end
    if a.bought then
      rows[#rows + 1] = { key = "ahBought", label = TEXT.tr_ahBought, value = int(a.bought.n), tip = { TEXT.tr_ahBought, ahTip } }
    end
    if a.sold and a.sold.deposit > 0 then
      rows[#rows + 1] = { key = "ahFee", label = TEXT.tr_ahFee, value = money(a.sold.deposit),
        tip = { TEXT.tr_ahFee, TEXT.tr_ahFeeTip, ahTip } }
    end
    if a.posted and a.posted.deposit > 0 then
      rows[#rows + 1] = { key = "ahDeposit", label = TEXT.tr_ahDeposit, value = money(a.posted.deposit),
        tip = { TEXT.tr_ahDeposit, TEXT("tr_ahDepositTip", int(a.posted.n)), ahTip } }
    end
    add("ah", TEXT.tr_ahHead, rows)
  end

  if raw.mail then
    local rows, m = {}, raw.mail
    if m.gold then
      rows[#rows + 1] = { key = "mailGold", label = TEXT("tr_mailGold", nameOf(m.gold.who)), value = money(m.gold.amount),
        tip = { TEXT("tr_from", nameOf(m.gold.who)), TEXT.tr_mailGoldTip } }
    end
    if m.item then
      local info = Schaetze.itemInfo(char, m.item.key)
      rows[#rows + 1] = { key = "mailItem", label = TEXT("tr_mailItem", nameOf(m.item.who)), value = stackText(char, m.item.key, m.item.count),
        tip = { TEXT("tr_from", nameOf(m.item.who)), TEXT.tr_mailItemTip, item = info and info.string or nil } }
    end
    if m.cod then
      rows[#rows + 1] = { key = "cod", label = TEXT.tr_cod, value = money(m.cod), tip = { TEXT.tr_cod, TEXT.tr_codTip } }
    end
    add("mail", TEXT.tr_mailHead, rows)
  end

  if raw.trade then
    local rows, t = {}, raw.trade
    if t.gold then
      rows[#rows + 1] = { key = "tradeGold", label = TEXT("tr_tradeGold", nameOf(t.gold.who)), value = money(t.gold.amount),
        tip = { TEXT("tr_from", nameOf(t.gold.who)), TEXT.tr_tradeGoldTip } }
    end
    if t.item then
      local info = Schaetze.itemInfo(char, t.item.key)
      rows[#rows + 1] = { key = "tradeItem", label = TEXT("tr_tradeItem", nameOf(t.item.who)), value = stackText(char, t.item.key, t.item.count),
        tip = { TEXT("tr_from", nameOf(t.item.who)), TEXT.tr_tradeItemTip, item = info and info.string or nil } }
    end
    add("trade", TEXT.tr_tradeHead, rows)
  end
  if #sections == 0 then return nil end
  return sections
end

local cache = setmetatable({}, { __mode = "k" })

local function buildStatic(index)
  local char = index.char
  local st = { char = char, errors = {} }
  local function try(name, fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then return res end
    st.errors[name] = true
    return nil
  end
  st.money = try("money", moneyStatic, index, char)
  local level = indexLevel(index, char)
  st.level = level
  if not level then -- without LV/PL: highest level of the gear snapshots
    for k in pairs(snapGroup(char, "gear") or {}) do
      local L = num(k)
      if L and L >= 1 and L <= 200 and (not level or L > level) then level = floor(L) end
    end
    st.level = level
  end
  st.gear = try("gear", gearHistory, index, char, level or 1)
  st.blue = try("blue", firstBlue, index, char)
  st.quality = try("quality", qualityOf, char)
  st.margin = try("margin", marginNotes, st, index) or {}
  st.trade = try("trade", tradeData, index, char)
  return st
end

function Schaetze.static(index)
  local st = cache[index]
  if not st then
    st = buildStatic(index)
    cache[index] = st
  end
  return st
end

local function tipOf(label, copper, pct, extra)
  local t = { label, Schaetze.moneyText(copper) }
  if pct then t[#t + 1] = TEXT("ofSum", pct) end
  if extra then t[#t + 1] = extra end
  return t
end

local function pctText(copper, total)
  if not total or total <= 0 then return nil end
  local p = copper / total * 100
  if p > 0 and p < 1 then return TEXT.under1 end
  return TEXT("pct", floor(p + 0.5))
end

local function ledgerOf(st, beutel)
  local m = st.money
  if not m then return { empty = true, rows = {}, notes = {} } end
  local rows = {}
  local inTotal, outTotal = m.inTotal, m.outTotal
  rows[#rows + 1] = row("head", TEXT.incomeHead)
  for _, r in ipairs(m.inRows) do
    if r.always or r.copper > 0 then
      rows[#rows + 1] = row("row", r.label, r.copper, { tip = tipOf(r.label, r.copper, pctText(r.copper, inTotal)) })
    end
  end
  rows[#rows + 1] = row("sum", TEXT.sumIn, inTotal)
  rows[#rows + 1] = row("head", TEXT.expenseHead)
  for _, r in ipairs(m.outRows) do
    if r.always or r.copper > 0 then
      local note = (r.tipNote and TEXT.ahNote) or ((r.key == "repair" and r.copper > 0) and TEXT.repairNote) or nil
      rows[#rows + 1] = row("row", r.label, r.copper, { tip = tipOf(r.label, r.copper, pctText(r.copper, outTotal), note) })
    end
  end
  rows[#rows + 1] = row("sum", TEXT.sumOut, outTotal)
  local ledger = { rows = rows, income = inTotal, expense = outTotal, notes = {} }
  if beutel then
    local rest = beutel - (inTotal - outTotal)
    ledger.rest, ledger.balance, ledger.hasBalance = rest, beutel, true
    rows[#rows + 1] = row("rest", TEXT.restLabel, rest,
      { tip = { TEXT.restLabel, TEXT.restTip1, TEXT.restTip2 } })
    rows[#rows + 1] = row("total", TEXT.totalLabel, beutel)
  end
  ledger.empty = inTotal == 0 and outTotal == 0 and not beutel
  -- the repair note sits in the tooltip of the "Reparatur" row (TEXT.repairNote), no longer as a note
  return ledger
end

-- nodes of a side: rows > 0; with more than Schaetze.FLOW_NODES the smallest are merged into "Weitere"
local function nodesOf(rows, total, extra)
  local list = {}
  for _, r in ipairs(rows) do
    if r.copper > 0 then list[#list + 1] = { key = r.key, label = r.label, copper = r.copper, color = r.color } end
  end
  for _, e in ipairs(extra or {}) do
    if e.copper > 0 then list[#list + 1] = e end
  end
  if #list > Schaetze.FLOW_NODES then
    local byAmount = {}
    for i, n in ipairs(list) do byAmount[i] = n end
    table.sort(byAmount, function(a, b) return a.copper > b.copper end)
    local keep, rest = {}, 0
    for i, n in ipairs(byAmount) do
      if i < Schaetze.FLOW_NODES then keep[n] = true else rest = rest + n.copper end
    end
    local out = {}
    for _, n in ipairs(list) do
      if keep[n] then out[#out + 1] = n end
    end
    out[#out + 1] = { key = "more", label = TEXT.rest, copper = rest, color = "faint" }
    list = out
  end
  for _, n in ipairs(list) do
    n.text = Schaetze.moneyText(n.copper, true, false, Schaetze.FONT.label)
    n.pct = total > 0 and n.copper / total or 0
    n.pctText = pctText(n.copper, total)
    n.tip = { n.label, Schaetze.moneyText(n.copper), n.pctText and TEXT("ofFlow", n.pctText) or nil }
  end
  return list
end

-- heights and positions of the nodes. Sides: nodes with gap, middle: gapless. All within an area of height (from the top).
-- Minimum height minH per node; if it does not fit, the others shrink. Labels keep LABEL_STEP distance.
function Schaetze.layout(left, right, total, height, gap, minH)
  height, gap, minH = tonumber(height) or Schaetze.FLOW_HEIGHT, tonumber(gap) or Schaetze.FLOW_GAP, tonumber(minH) or Schaetze.FLOW_MIN
  local nl, nr = #left, #right
  local gaps = gap * (max(nl, nr) - 1)
  if gaps < 0 then gaps = 0 end
  local scale = total > 0 and (height - gaps) / total or 0
  local function heights(nodes, sc)
    local sum, flexible = 0, 0
    for _, n in ipairs(nodes) do
      local h = n.copper * sc
      if h < minH then h = minH else flexible = flexible + h end
      n.h = h
      sum = sum + h
    end
    return sum, flexible
  end
  for _ = 1, 6 do
    local sl, fl = heights(left, scale)
    local sr, fr = heights(right, scale)
    local over = max(sl + gap * max(nl - 1, 0) - height, sr + gap * max(nr - 1, 0) - height)
    if over <= 0.01 then break end
    local flex = max(fl, fr)
    if flex <= 0 then break end
    scale = scale * max(0.05, 1 - over / flex)
  end
  local sumL = heights(left, scale)
  local sumR = heights(right, scale)
  local function place(nodes, sum, useGap, field)
    local g = useGap and gap or 0
    local top = (height - (sum + g * max(#nodes - 1, 0))) / 2
    local y = top
    for _, n in ipairs(nodes) do
      n[field] = y
      y = y + n.h + g
    end
    return top
  end
  place(left, sumL, true, "y")
  place(right, sumR, true, "y")
  place(left, sumL, false, "my")
  place(right, sumR, false, "my")
  local function labels(nodes)
    local prev
    for _, n in ipairs(nodes) do
      local c = n.y + n.h / 2
      if prev and c < prev + Schaetze.LABEL_STEP then c = prev + Schaetze.LABEL_STEP end
      n.labelY, prev = c, c
    end
    local limit = height - 6
    for i = #nodes, 1, -1 do
      local n = nodes[i]
      if n.labelY > limit then n.labelY = limit end
      limit = n.labelY - Schaetze.LABEL_STEP
    end
    for _, n in ipairs(nodes) do
      if n.labelY < 6 then n.labelY = 6 end
    end
  end
  labels(left)
  labels(right)
  return { top = (height - max(sumL, sumR)) / 2, leftH = sumL, rightH = sumR, height = height }
end

local function flowOf(st, beutel, rest, level)
  local m = st.money
  local flow = { empty = true, total = 0, left = {}, right = {}, height = Schaetze.FLOW_HEIGHT }
  if not m then return flow end
  local leftExtra, rightExtra = {}, {}
  local bag = beutel
  if not bag then
    bag = max(m.inTotal - m.outTotal, 0)
    rest = 0
  end
  if rest and rest > 0 then leftExtra[1] = { key = "start", label = TEXT.start, copper = rest, color = "faint" } end
  if rest and rest < 0 then rightExtra[#rightExtra + 1] = { key = "unbooked", label = TEXT.unbooked, copper = -rest, color = "faint" } end
  if bag > 0 then rightExtra[#rightExtra + 1] = { key = "bag", label = TEXT.inBag, copper = bag, color = "treasure" } end
  local leftTotal = m.inTotal + ((rest and rest > 0) and rest or 0)
  local rightTotal = m.outTotal + bag + ((rest and rest < 0) and -rest or 0)
  local total = max(leftTotal, rightTotal)
  if total <= 0 then return flow end
  flow.total, flow.totalText, flow.empty = total, Schaetze.moneyText(total, true, false, Schaetze.FONT.flowTotal), false
  flow.left = nodesOf(m.inRows, leftTotal, leftExtra)
  flow.right = nodesOf(m.outRows, rightTotal, rightExtra)
  flow.mid = Schaetze.layout(flow.left, flow.right, total, Schaetze.FLOW_HEIGHT, Schaetze.FLOW_GAP, Schaetze.FLOW_MIN)
  flow.levels = Schaetze.levelSeries(m.levels, level)
  -- holdings per level: its own section, a failure here must not take the flow with it
  local ok, hold = pcall(Schaetze.holdSeries, m.hold, level, beutel)
  flow.hold = ok and hold or nil
  return flow
end

-- gold flow per level: income and expense per level from Index.money.level, gapless from the first level with money
-- movement to the current level
-- (at most Schaetze.LEVEL_COLS, the newest). Expense without the unbooked sources (gap/start), income as booked.
-- -> { cols = { { level, gain, loss, net, tip } }, maxGain, maxLoss, from, to } | nil (no level data)
function Schaetze.levelSeries(levels, current)
  if type(levels) ~= "table" then return nil end
  local lo, hi
  local data = {}
  for L, e in pairs(levels) do
    if type(L) == "number" and L >= 1 and L <= 200 and L == floor(L) and type(e) == "table" then
      local gain = num(e.gain) or 0
      local loss = num(e.loss) or 0
      if type(e.out) == "table" then
        for src in pairs(SKIP_SOURCES) do loss = loss - (num(e.out[src]) or 0) end
      end
      gain, loss = max(gain, 0), max(loss, 0)
      if gain > 0 or loss > 0 then
        data[L] = { gain = gain, loss = loss }
        lo = lo and min(lo, L) or L
        hi = hi and max(hi, L) or L
      end
    end
  end
  if not lo then return nil end
  current = num(current)
  if current and current >= hi and current <= 200 then hi = floor(current) end
  if hi - lo + 1 > Schaetze.LEVEL_COLS then lo = hi - Schaetze.LEVEL_COLS + 1 end
  local out = { cols = {}, maxGain = 0, maxLoss = 0, from = lo, to = hi }
  for L = lo, hi do
    local d = data[L] or { gain = 0, loss = 0 }
    local net = d.gain - d.loss
    local tip = { TEXT("level", int(L)), TEXT("income", Schaetze.moneyText(d.gain)),
      TEXT("expense", Schaetze.moneyText(d.loss)), TEXT("saldo", (net > 0 and "+" or "") .. Schaetze.moneyText(net)) }
    out.cols[#out.cols + 1] = { level = L, gain = d.gain, loss = d.loss, net = net, tip = tip }
    out.maxGain = max(out.maxGain, d.gain)
    out.maxLoss = max(out.maxLoss, d.loss)
  end
  out.maxGainText = Schaetze.moneyText(out.maxGain, true, false, Schaetze.FONT.label)
  out.maxLossText = Schaetze.moneyText(out.maxLoss, true, false, Schaetze.FONT.label)
  return out
end

-- holdings per level: the highest balance in the purse within each level (Index.money.hold, built from the GD lines, so
-- it reaches back over the whole log). A level without any GD line keeps the balance it started with (carried on from the
-- last line before); in the current level the live purse counts as well. Gapless from the first logged level to the
-- current one (at most Schaetze.LEVEL_COLS, the newest).
-- -> { cols = { { level, top, last, jump, peak, current, tip } }, max, maxLevel, maxText, jump = { level, amount, ... } | nil,
--      from, to } | nil (no level data)
function Schaetze.holdSeries(hold, current, bag)
  if type(hold) ~= "table" then return nil end
  local lo, hi
  local data = {}
  for L, e in pairs(hold) do
    if type(L) == "number" and L >= 1 and L <= 200 and L == floor(L) and type(e) == "table" then
      local top = num(e.top)
      if top and top >= 0 then
        data[L] = { top = top, last = num(e.last) or top }
        lo = lo and min(lo, L) or L
        hi = hi and max(hi, L) or L
      end
    end
  end
  if not lo then return nil end
  current = num(current)
  if current and current >= hi and current <= 200 then hi = floor(current) end
  bag = num(bag)
  if bag and bag < 0 then bag = nil end
  local all, prev = {}, nil
  for L = lo, hi do
    local d = data[L]
    if not d then -- no balance change in this level: it began (and stays) with the balance before
      d = { top = prev and prev.last or 0, last = prev and prev.last or 0 }
    end
    if bag and L == hi and (current == nil or current == hi) then
      d = { top = max(d.top, bag), last = bag, current = true }
    end
    all[L], prev = d, d
  end
  if hi - lo + 1 > Schaetze.LEVEL_COLS then lo = hi - Schaetze.LEVEL_COLS + 1 end
  local out = { cols = {}, max = -1, from = lo, to = hi }
  for L = lo, hi do
    local d = all[L]
    local before = all[L - 1]
    local col = { level = L, top = d.top, last = d.last, current = d.current == true }
    if L > lo and before then col.jump = d.top - before.top end
    out.cols[#out.cols + 1] = col
    if d.top > out.max then out.max, out.maxLevel = d.top, L end
    if col.jump and col.jump > 0 and (not out.jump or col.jump > out.jump.amount) then
      out.jump = { level = L, amount = col.jump }
    end
  end
  for _, col in ipairs(out.cols) do
    col.peak = col.level == out.maxLevel and out.max > 0
    local tip = { TEXT("level", int(col.level)), TEXT("holdTop", Schaetze.moneyText(col.top)) }
    if col.last ~= col.top or col.current then
      tip[#tip + 1] = TEXT(col.current and "holdNow" or "holdEnd", Schaetze.moneyText(col.last))
    end
    if col.jump and col.jump ~= 0 then
      tip[#tip + 1] = TEXT("holdJump", (col.jump > 0 and "+" or "") .. Schaetze.moneyText(col.jump))
    end
    if col.peak then tip[#tip + 1] = TEXT.holdPeak end
    col.tip = tip
  end
  out.maxText = Schaetze.moneyText(out.max, true, false, Schaetze.FONT.label)
  if out.jump then
    out.jump.text = Schaetze.moneyText(out.jump.amount, true, false, Schaetze.FONT.label)
  end
  return out
end

function Schaetze.evaluate(index, opts)
  if type(index) ~= "table" then return nil end
  opts = type(opts) == "table" and opts or {}
  local now = num(opts.now) or time()
  local live = opts.live
  local st = Schaetze.static(index)
  local Idx = I()
  local view = { now = now, partial = next(st.errors) ~= nil }

  local level = live and live.level and live.level() or nil
  view.level = level or st.level or 1
  view.day = Idx.dayOf(index, now)
  local info = type(index.char) == "table" and type(index.char.info) == "table" and index.char.info or {}
  local who = display(info.name, 32) or TEXT.traveller
  local kind = display(info.class, 32) or display(info.race, 32)
  view.head = who .. (kind and (" · " .. kind) or "") .. " · " .. TEXT("headLevel", int(view.level))

  local c, source = beutelOf(index, st, live)
  local b = { copper = c, source = source, dayText = TEXT("day", int(view.day)) }
  if c then
    b.g, b.s, b.k = Schaetze.split(c)
    b.text = Schaetze.moneyText(c, false, false, Schaetze.FONT.bag)
  else
    b.text = TEXT.noMoney
  end
  view.beutel = b

  local played = playedSeconds(index, now)
  -- net gain (income - expense) per play hour, only from Schaetze.PER_HOUR_MIN seconds of play time
  if st.money and played and played >= Schaetze.PER_HOUR_MIN then
    local net = st.money.inTotal - st.money.outTotal
    local per = net / (played / 3600)
    per = per < 0 and -floor(-per + 0.5) or floor(per + 0.5)
    if per ~= 0 then
      view.perHour = { copper = per, text = TEXT("perHour", Schaetze.moneyText(per, true, false, Schaetze.FONT.perHour)) }
    end
  end

  local rest
  view.ledger = ledgerOf(st, c)
  rest = view.ledger.rest
  view.margin = st.margin
  view.flow = flowOf(st, c, rest, view.level)
  view.gear = st.gear
  view.blue = st.blue
  view.quality = st.quality
  if st.trade then
    local ok, sections = pcall(Schaetze.tradeView, st.trade, st.char)
    if ok then view.trade = sections else view.partial = true end
  end
  return view
end

-- text snippets of the margin notes (code, never SV data). {=level} number, {=amount} display-ready amount.

do
  local Texts = Journal.Texts
  if Texts then
    local function add(id, text, when, w)
      Texts.add("margin", { area = "m.Schaetze", id = id, text = text, when = when, w = w })
    end
    local function spend(purpose)
      return function(c) return c.kind == "spend" and c.purpose == purpose end
    end
    add("margin_sch_training_1", "Training auf {=level} hat mich ruiniert: {=amount}.", spend("training"), 3)
    add("margin_sch_training_2", "Auf Stufe {=level} lernte ich viel und zahlte {=amount} dafür.", spend("training"))
    add("margin_sch_repair_1", "Auf Stufe {=level} fraß die Reparatur {=amount}.", spend("repair"), 3)
    add("margin_sch_repair_2", "Stufe {=level}: Die Rüstung hielt, mein Beutel nicht ({=amount}).", spend("repair"))
    add("margin_sch_vendor_1", "Auf Stufe {=level} wanderten {=amount} über den Händlertisch.", spend("vendor_buy"), 3)
    add("margin_sch_vendor_2", "Stufe {=level} war Einkaufsbummel: {=amount}.", spend("vendor_buy"))
    add("margin_sch_taxi_1", "Auf Stufe {=level} flog ich für {=amount} durch die Lüfte.", spend("taxi"), 3)
    add("margin_sch_taxi_2", "Flugmeister, Stufe {=level}: {=amount}. Es war eine schöne Aussicht.", spend("taxi"))
    add("margin_sch_ah_1", "Das Auktionshaus holte sich auf Stufe {=level} {=amount}.", spend("ah"), 3)
    add("margin_sch_ah_2", "Stufe {=level}: {=amount} im Auktionshaus gelassen.", spend("ah"))
    add("margin_sch_other_1", "Auf Stufe {=level} ging am meisten drauf: {=amount}.", spend("other"))
    add("margin_sch_other_2", "Stufe {=level} war die teuerste: {=amount}.", spend("other"))
    local function earn(c) return c.kind == "earn" end
    add("margin_sch_earn_1", "Am meisten kam auf Stufe {=level} herein: {=amount}.", earn, 2)
    add("margin_sch_earn_2", "Stufe {=level} füllte den Beutel um {=amount}.", earn)
    add("margin_sch_earn_3", "Auf Stufe {=level} lohnte sich das Wandern: {=amount}.", earn)
  end
end
