-- Equipment finds (jump from the Schaetze page): every LT line of quality green or better whose item is equippable
-- becomes a table row; quest rewards are matched to the nearest turn-in (QT) that lists the item.
-- Computed at display time, no new SV or index fields. Funde.build(index) -> book = { rows, total, pending, qualities,
-- slots, zones }; Funde.source replaces the client API in tests.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Funde = {}
Journal.Funde = Funde

local floor, huge, max = math.floor, math.huge, math.max
local format, find, match = string.format, string.find, string.match

Funde.NAME_MAX = 48          -- bytes per item name
Funde.TEXT_MAX = 40          -- bytes per enemy, quest and area name
Funde.QUEST_WINDOW = 15      -- seconds: a turn-in (QT) must be this close to a quest reward (LT)
Funde.ROW_MAX = 20000        -- find lines read (like Index.LIST_MAX)
Funde.EQUIP_WINDOW = 86400   -- seconds after the find in which an equip (GW) still counts for it
Funde.TIP_MAX = 80           -- bytes per tooltip line
Funde.TIMELINE_MAX = 60      -- points on the timeline of a slot
Funde.source = nil

-- locale scope "m.Funde" (English in locales/enUS_model.lua); qualities, slots and origins read their labels on access
-- (metatable)
local Loc = ns.Locale
local TEXT = Loc.ns("m.Funde", {
  q2 = "Ungewöhnlich", q3 = "Selten", q4 = "Episch", q5 = "Legendär", q6 = "Artefakt", q7 = "Erbstück", q8 = "Marke",
  INVTYPE_HEAD = "Kopf", INVTYPE_NECK = "Hals", INVTYPE_SHOULDER = "Schultern", INVTYPE_CLOAK = "Rücken",
  INVTYPE_CHEST = "Brust", INVTYPE_ROBE = "Brust", INVTYPE_BODY = "Hemd", INVTYPE_TABARD = "Wappenrock",
  INVTYPE_WRIST = "Handgelenke", INVTYPE_HAND = "Hände", INVTYPE_WAIST = "Taille", INVTYPE_LEGS = "Beine",
  INVTYPE_FEET = "Füße", INVTYPE_FINGER = "Finger", INVTYPE_TRINKET = "Schmuck",
  INVTYPE_WEAPON = "Einhändig", INVTYPE_2HWEAPON = "Zweihändig", INVTYPE_WEAPONMAINHAND = "Waffenhand",
  INVTYPE_WEAPONOFFHAND = "Schildhand", INVTYPE_SHIELD = "Schild", INVTYPE_HOLDABLE = "Nebenhand",
  INVTYPE_RANGED = "Distanz", INVTYPE_RANGEDRIGHT = "Distanz", INVTYPE_THROWN = "Wurfwaffe",
  INVTYPE_RELIC = "Relikt", INVTYPE_AMMO = "Munition", INVTYPE_PROFESSION_TOOL = "Berufswerkzeug",
  INVTYPE_PROFESSION_GEAR = "Berufsausrüstung", INVTYPE_BAG = "Tasche", INVTYPE_QUIVER = "Köcher",
  slotOther = "Sonstiges",
  origin_mob = "Beute von einem Gegner", origin_object = "Beute aus einem Objekt", origin_container = "Aus einem Behälter",
  origin_fishing = "Angeln", origin_vendor = "Händler", origin_craft = "Handwerk", origin_quest = "Questbelohnung",
  origin_mail = "Post", origin_trade = "Handel", origin_ah = "Auktionshaus", origin_bonus = "Bonuswurf", origin_other = "Sonstiges",
  day = "Tag %s",
  dayClock = "Tag %s, %s",
  questFallback = "Quest #%s",
  lootFrom = "Beute von %s",
  questReward = "Questbelohnung %s",
  mapFallback = "Karte %s",
  itemFallback = "Gegenstand #%s",
})
Funde.TEXT = TEXT

local function lazyLabel(e, key)
  return setmetatable(e, { __index = function(_, k) if k == "label" then return TEXT[key] end end })
end

Funde.QUALITY = {}
for q = 2, 8 do Funde.QUALITY[q] = lazyLabel({}, "q" .. q) end

-- equip slot (itemEquipLoc) -> display name and order (head to bag)
local SLOTS = {}
for i, loc in ipairs({
  "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST", "INVTYPE_ROBE", "INVTYPE_BODY",
  "INVTYPE_TABARD", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_FINGER",
  "INVTYPE_TRINKET", "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD",
  "INVTYPE_HOLDABLE", "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC", "INVTYPE_AMMO",
  "INVTYPE_PROFESSION_TOOL", "INVTYPE_PROFESSION_GEAR", "INVTYPE_BAG", "INVTYPE_QUIVER",
}) do
  SLOTS[loc] = lazyLabel({ order = i }, loc)
end
Funde.SLOTS = SLOTS
local SLOT_OTHER = lazyLabel({ order = 99 }, "slotOther")
-- not equippable although the client returns an INVTYPE text
local NOT_EQUIP = { INVTYPE_NON_EQUIP = true, INVTYPE_NON_EQUIP_IGNORE = true }

-- origin per LT source (enemy and quest are shown by name instead)
local ORIGINS = { mob = true, object = true, container = true, fishing = true, vendor = true, craft = true, quest = true,
  mail = true, trade = true, ah = true, bonus = true, other = true }
Funde.ORIGIN = setmetatable({}, { __index = function(_, k)
  if type(k) == "string" and ORIGINS[k] then return TEXT["origin_" .. k] end
end })

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

local function int(n)
  local T = Journal.Texts
  return T and T.int(n) or format("%.0f", n)
end

local function idText(n) return format("%.0f", n) end -- ids without thousands separators

local function posId(v)
  if isSecret(v) then return nil end
  if type(v) == "string" then
    if not find(v, "^%d+$") or #v > 10 then return nil end
    v = tonumber(v)
  end
  if not finite(v) or v <= 0 or v >= 2147483648 or v ~= floor(v) then return nil end
  return v
end

local function byId(tbl, id)
  if type(tbl) ~= "table" or id == nil then return nil end
  local v = tbl[id]
  if v == nil then v = tbl[format("%.0f", id)] end
  return v
end

local function rawName(e)
  if type(e) == "table" then e = e.name end
  if isSecret(e) or type(e) ~= "string" or e == "" then return nil end
  return e
end

local function resolve(path)
  local src = Funde.source
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
  local ok, a, b, c, d, e = pcall(f, ...)
  if not ok then return nil end
  return a, b, c, d, e
end

-- itemEquipLoc (4th return of GetItemInfoInstant): "INVTYPE_*" | false (not equippable) | nil (unknown)
local function equipLoc(itemID)
  local _, _, _, loc = call("C_Item.GetItemInfoInstant", itemID)
  if loc == nil and not resolve("C_Item.GetItemInfoInstant") then
    _, _, _, loc = call("GetItemInfoInstant", itemID)
  end
  if isSecret(loc) or type(loc) ~= "string" then return nil end
  if loc == "" or NOT_EQUIP[loc] then return false end
  if not find(loc, "^INVTYPE_[%u%d_]+$") then return nil end
  return loc
end

-- name from the client (raw text; display only via display): GetItemNameByID, else GetItemInfo
local function clientName(itemID)
  local n = call("C_Item.GetItemNameByID", itemID)
  if isSecret(n) or type(n) ~= "string" or n == "" then
    n = call("GetItemInfo", itemID)
    if not resolve("GetItemInfo") then n = call("C_Item.GetItemInfo", itemID) end
  end
  if isSecret(n) or type(n) ~= "string" or n == "" then return nil end
  return n
end

local function clientQuality(itemID)
  local q = call("C_Item.GetItemQualityByID", itemID)
  if isSecret(q) or not finite(q) then return nil end
  return q
end

-- "Tag n, hh:mm" in the character's local time (as in Kampf/Momente)
local function whenText(index, t)
  local I = Journal.Index
  if not (I and finite(t)) then return nil end
  local h, m = I.timeOfDay(index, t)
  if not h then return TEXT("day", int(I.dayOf(index, t))) end
  return TEXT("dayClock", int(I.dayOf(index, t)), format("%02d:%02d", h, m))
end

-- quest rewards: turn-ins (QT) with their reward list

local function rewardSet(e, qt, qr)
  local set = {}
  local function add(v)
    if type(v) == "table" and not isSecret(v) then v = v.id end
    v = posId(v)
    if v then set[v] = true end
  end
  if type(e) == "table" then
    for _, key in ipairs({ "rewardItems", "rewardChoices" }) do
      local list = e[key]
      if type(list) == "table" and not isSecret(list) then
        for i = 1, 16 do
          if list[i] == nil then break end
          add(list[i])
        end
      end
    end
  end
  add(qt)
  add(qr)
  return set
end

local function questTurnIns(index, char)
  local I = Journal.Index
  local quests = type(char) == "table" and type(char.quests) == "table" and char.quests or nil
  local qr = {}
  for _, rec in ipairs(I.list(index, "QR")) do
    local id = posId(I.str(rec, "QR", "questID"))
    if id then qr[id] = I.str(rec, "QR", "itemID") end
  end
  local out = {}
  for _, rec in ipairs(I.list(index, "QT")) do
    local id = posId(I.str(rec, "QT", "questID"))
    if id and finite(rec.t) then
      local e = byId(quests, id)
      out[#out + 1] = { t = rec.t, id = id, entry = e, items = nil, qt = I.str(rec, "QT", "itemID"), qr = qr[id] }
    end
  end
  return out
end

-- turn-in for a quest reward: within QUEST_WINDOW s; a turn-in that lists the item among its rewards wins
local function questFor(turnIns, t, itemID)
  local best, bestDt, any, anyDt
  for _, q in ipairs(turnIns) do
    local dt = math.abs(q.t - t)
    if dt <= Funde.QUEST_WINDOW then
      if not q.items then q.items = rewardSet(q.entry, q.qt, q.qr) end
      if q.items[itemID] and (not bestDt or dt < bestDt) then best, bestDt = q, dt end
      if not anyDt or dt < anyDt then any, anyDt = q, dt end
    end
  end
  return best or any
end

local function questTitle(q)
  local e = q.entry
  local title = type(e) == "table" and display(rawName(e.title), Funde.TEXT_MAX) or nil
  return title or TEXT("questFallback", idText(q.id))
end

-- equips (GW): per itemID the changes in time order; a find takes the first free equip shortly after it

local function itemIdOf(key)
  return type(key) == "string" and posId(match(key, "^(%d+)")) or nil
end

local function equipLog(index)
  local I = Journal.Index
  local out, seen = {}, 0
  for _, rec in ipairs(I.list(index, "GW")) do
    seen = seen + 1
    if seen > Funde.ROW_MAX then break end
    local slot = I.num(rec, "GW", "slot")
    local item = I.str(rec, "GW", "item")
    local id = slot and slot >= 1 and itemIdOf(item)
    if id and finite(rec.t) then
      local list = out[id]
      if not list then
        list = { n = 0 }
        out[id] = list
      end
      local prev, locked = I.str(rec, "GW", "prev")
      list[#list + 1] = { t = rec.t, ilvl = I.num(rec, "GW", "ilvl"), prev = prev, prevKnown = locked ~= true }
    end
  end
  for _, list in pairs(out) do
    table.sort(list, function(a, b) return a.t < b.t end)
  end
  return out
end

-- first free equip of the item within [t, t + EQUIP_WINDOW]
local function equipFor(log, itemID, t)
  local list = log[itemID]
  if not (list and finite(t)) then return nil end
  for i = list.n + 1, #list do
    local e = list[i]
    if e.t >= t then
      if e.t > t + Funde.EQUIP_WINDOW then return nil end
      list.n = i
      return e
    end
  end
  return nil
end

local function replacedOf(e, items, names)
  if not e.prevKnown then return nil end
  if not e.prev then return false end -- the slot was empty
  local id = itemIdOf(e.prev)
  if not id then return nil end
  local snap = byId(items, id)
  local name = type(snap) == "table" and display(rawName(snap), Funde.NAME_MAX) or names[id]
  if not name and names[id] == nil then
    name = display(clientName(id), Funde.NAME_MAX) or false
    names[id] = name
  end
  local q = type(snap) == "table" and finite(snap.quality) and floor(snap.quality) or clientQuality(id)
  return { itemID = id, name = name or nil, quality = (q and q >= 0 and q <= 8) and q or nil, -- grey/white too (not in QUALITY)
    link = Journal.Texts and Journal.Texts.itemString(e.prev) or nil }
end

local cache = setmetatable({}, { __mode = "k" })

local function counted(map, list, value, text, order)
  local e = map[value]
  if not e then
    e = { value = value, text = text, count = 0, order = order }
    map[value] = e
    list[#list + 1] = e
  end
  e.count = e.count + 1
end

local function buildBook(index)
  local I = Journal.Index
  local char = type(index.char) == "table" and index.char or {}
  local snaps = type(char.snapshots) == "table" and char.snapshots or {}
  local items = type(snaps.items) == "table" and snaps.items or nil
  local maps = type(snaps.maps) == "table" and snaps.maps or nil
  local npcs = type(char.npcs) == "table" and char.npcs or nil
  local book = { rows = {}, pending = {}, qualities = {}, slots = {}, zones = {} }
  local locs, names, zoneNames, replacedNames = {}, {}, {}, {}
  local turnIns
  local gwLog = equipLog(index)
  local qMap, sMap, zMap = {}, {}, {}
  local seen = 0
  for _, rec in ipairs(I.list(index, "LT")) do
    seen = seen + 1
    if seen > Funde.ROW_MAX then break end
    local key = I.str(rec, "LT", "item")
    local itemID = key and posId(match(key, "^(%d+)"))
    if itemID then
      local snap = byId(items, itemID)
      local q = I.num(rec, "LT", "quality")
      if q == nil and type(snap) == "table" and finite(snap.quality) then q = snap.quality end
      if q == nil then q = clientQuality(itemID) end
      q = q and floor(q) or nil
      local loc = q and q >= 2 and Funde.QUALITY[q] and locs[itemID]
      if q and q >= 2 and Funde.QUALITY[q] and loc == nil then
        loc = equipLoc(itemID) or false
        locs[itemID] = loc
      end
      if loc then
        local def = SLOTS[loc] or SLOT_OTHER
        local row = { id = rec.ln or seen, itemID = itemID, quality = q, loc = loc, slot = def.label, slotOrder = def.order,
          t = rec.t, link = Journal.Texts and Journal.Texts.itemString(key) or nil }
        local n = I.num(rec, "LT", "count")
        if n and n > 1 and n < 100000 then row.count = floor(n) end
        -- name: stored at the find (snapshots.items), else from the client, else load later
        local name = names[itemID]
        if name == nil then
          name = (type(snap) == "table" and display(rawName(snap), Funde.NAME_MAX)) or display(clientName(itemID), Funde.NAME_MAX) or false
          names[itemID] = name
        end
        row.name = name or nil
        if not name then book.pending[itemID] = true end
        local src = I.str(rec, "LT", "source")
        src = (src and Funde.ORIGIN[src]) and src or "other"
        row.originKind = src
        if src == "mob" then
          local npc = posId(I.str(rec, "LT", "srcID"))
          local who = npc and display(rawName(byId(npcs, npc)), Funde.TEXT_MAX)
          row.origin = who and TEXT("lootFrom", who) or Funde.ORIGIN.mob
        elseif src == "quest" then
          turnIns = turnIns or questTurnIns(index, char)
          local qt = finite(rec.t) and questFor(turnIns, rec.t, itemID) or nil
          row.origin = qt and TEXT("questReward", questTitle(qt)) or Funde.ORIGIN.quest
          row.questID = qt and qt.id or nil
        else
          row.origin = Funde.ORIGIN[src]
        end
        local mapID = posId(I.str(rec, "LT", "mapID"))
        if mapID then
          local z = zoneNames[mapID]
          if z == nil then
            z = display(rawName(byId(maps, mapID)), Funde.TEXT_MAX) or ((ns.Journal.View and ns.Journal.View.mapName and ns.Journal.View.mapName(mapID)) or TEXT("mapFallback", idText(mapID)))
            zoneNames[mapID] = z
          end
          row.mapID, row.zone = mapID, z
        end
        local L = I.num(rec, "LT", "level")
        if L and L >= 1 and L <= 200 then row.level = floor(L) end
        row.when = whenText(index, rec.t)
        -- equipped? item level and replaced item come from the GW line
        local eq = equipFor(gwLog, itemID, rec.t)
        if eq then
          if eq.ilvl and eq.ilvl >= 1 and eq.ilvl < 10000 then row.ilvl = floor(eq.ilvl) end
          row.equippedT = eq.t
          row.replaced = replacedOf(eq, items, replacedNames)
        end
        book.rows[#book.rows + 1] = row
        counted(qMap, book.qualities, q, Funde.QUALITY[q].label, q)
        counted(sMap, book.slots, row.slot, row.slot, def.order)
        if row.zone then counted(zMap, book.zones, row.zone, row.zone) end
      end
    end
  end
  table.sort(book.qualities, function(a, b) return a.order < b.order end)
  table.sort(book.slots, function(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.text < b.text
  end)
  table.sort(book.zones, function(a, b) return a.text < b.text end)
  book.total = #book.rows
  return book
end

function Funde.build(index, fresh)
  if type(index) ~= "table" then return { rows = {}, pending = {}, qualities = {}, slots = {}, zones = {}, total = 0 } end
  local book = not fresh and cache[index] or nil
  if not book then
    book = buildBook(index)
    cache[index] = book
  end
  return book
end

function Funde.label(row)
  return row.name or TEXT("itemFallback", idText(row.itemID))
end

-- re-read names for book.pending; request the missing ones once from the client (ITEM_DATA_LOAD_RESULT follows)
function Funde.resolve(book, request)
  if type(book) ~= "table" or type(book.pending) ~= "table" then return 0 end
  local found = {}
  local n = 0
  for id in pairs(book.pending) do
    local name = display(clientName(id), Funde.NAME_MAX)
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
      if not row.name and found[row.itemID] then row.name = found[row.itemID] end
    end
  end
  return n
end

local SORTS = { item = true, slot = true, origin = true, zone = true, level = true, time = true }
Funde.SORTS = SORTS

local function sortValue(row, key)
  if key == "item" then return Funde.label(row) end
  if key == "slot" then return row.slotOrder end
  if key == "origin" then return row.origin end
  if key == "zone" then return row.zone end
  if key == "level" then return row.level end
  return nil
end

function Funde.list(book, opts)
  opts = type(opts) == "table" and opts or {}
  local key = SORTS[opts.sort] and opts.sort or "time"
  local desc = opts.desc
  if desc == nil then desc = key == "time" end
  local out = {}
  for _, row in ipairs(type(book) == "table" and book.rows or {}) do
    if (opts.quality == nil or row.quality == opts.quality) and (opts.slot == nil or row.slot == opts.slot)
      and (opts.zone == nil or row.zone == opts.zone) then
      out[#out + 1] = row
    end
  end
  local function newer(a, b) -- time, the log order within the same second
    local ta, tb = a.t or 0, b.t or 0
    if ta ~= tb then return ta > tb end
    return a.id > b.id
  end
  table.sort(out, function(a, b)
    if key == "time" then
      if desc then return newer(a, b) end
      return newer(b, a)
    end
    local va, vb = sortValue(a, key), sortValue(b, key)
    if va ~= vb then
      if va == nil then return false end -- no value always goes last
      if vb == nil then return true end
      if desc then return va > vb end
      return va < vb
    end
    return newer(a, b)
  end)
  return out
end


function Funde.itemLevel(row)
  if type(row) ~= "table" then return nil end
  if row.ilvl then return row.ilvl end
  if type(row.link) ~= "string" then return nil end
  local v = call("C_Item.GetDetailedItemLevelInfo", row.link)
  if isSecret(v) or not finite(v) or v < 1 or v >= 10000 then return nil end
  return floor(v)
end

-- values as in the tooltip (without the name line): text lines from C_TooltipInfo; raw text only via display
function Funde.statLines(row, limit)
  local out = {}
  if type(row) ~= "table" or type(row.link) ~= "string" then return out end
  limit = limit or 8
  local data = call("C_TooltipInfo.GetHyperlink", row.link)
  if isSecret(data) or type(data) ~= "table" then return out end
  local surface = resolve("TooltipUtil.SurfaceArgs")
  if surface then pcall(surface, data) end
  local lines = data.lines
  if isSecret(lines) or type(lines) ~= "table" then return out end
  for i = 2, 40 do -- line 1 is the name
    local l = lines[i]
    if l == nil or #out >= limit then break end
    if type(l) == "table" and not isSecret(l) then
      if surface then pcall(surface, l) end
      local left, right = display(l.leftText, Funde.TIP_MAX), display(l.rightText, Funde.TIP_MAX)
      local text = (left and right) and (left .. "  " .. right) or left or right
      if text and text ~= "" then out[#out + 1] = text end
    end
  end
  return out
end

-- all finds of the same equip slot (with level), oldest first; row itself is included (index)
function Funde.timeline(book, row)
  local out = { rows = {}, lo = nil, hi = nil, index = nil }
  if type(book) ~= "table" or type(row) ~= "table" then return out end
  local list = {}
  for _, r in ipairs(book.rows) do
    if r.slot == row.slot and r.level then list[#list + 1] = r end
  end
  table.sort(list, function(a, b)
    if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) < (b.t or 0) end
    return a.id < b.id
  end)
  while #list > Funde.TIMELINE_MAX do table.remove(list, 1) end -- the newest stay
  for i, r in ipairs(list) do
    out.rows[i] = r
    out.lo = (not out.lo or r.level < out.lo) and r.level or out.lo
    out.hi = (not out.hi or r.level > out.hi) and r.level or out.hi
    if r == row then out.index = i end
  end
  return out
end
