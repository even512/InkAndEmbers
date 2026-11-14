-- "To Do" sub-page of the tab Pläne (internally Vorhaben): a real double page on the grid (docs/raster.md, Theme.GRID). The window
-- (journal/Frame.lua) builds the sheet over its page holders (Vorhaben.build); pages/Plaene.lua opens/closes it with the
-- sub-bookmark "To Do".
local _, ns = ...

local Journal = ns.Journal
local W = Journal and Journal.Widgets
local D = W and W.Diary
if not (W and D) then return end

local floor, ceil, min, max, sqrt = math.floor, math.ceil, math.min, math.max, math.sqrt

local Vorhaben = {}
Journal.Vorhaben = Vorhaben

-- Grid (double-page pixels 1076 x 666; left page x 92..494, right 582..984). The list ends before the blot at the bottom
-- left (keepout from y 503, x up to 132); on the right everything ends before the doodle (y 560) and the blot (x 957).
Vorhaben.ROWS = 7
Vorhaben.ROW_H = 36
Vorhaben.LIST_Y = 212
Vorhaben.ZONES_MAX = 150
Vorhaben.TEXT_BYTES = 400      -- display width of a to-do (120 chars = at most 480 bytes, then "…")
Vorhaben.DONE_MAX = 6
Vorhaben.ARCHIVE_DELAY = 30
Vorhaben.LAYOUT = {
  L = { x = 92, w = 402 }, R = { x = 582, w = 402 },
  titleY = 64, subY = 102, ctrlY = 116, slipW = 264, slipH = 28, dropW = 98,
  kindY = 116, slipY = 148, optY = 184, countW = 58, popupW = 300, popupRows = 8,
  card = { y = 152, w = 368, h = 112 }, doneY = 284, doneStep = 26, hintY = 492, miniY = 548, footY = 576,
}
Vorhaben.GREY = { 0.47, 0.44, 0.40, 1 }
Vorhaben.YARD_KM = 0.0009144
Vorhaben.SUB_Y = 22
Vorhaben.PROGRESS_W = 50
Vorhaben.SEARCH_LIMIT = 30
Vorhaben.SEARCH_MIN = 2
Vorhaben.SEARCH_DELAY = 0.15
Vorhaben.PIN_COLOR = { 0.78, 0.22, 0.16 }
Vorhaben.KIND_ICON = { free = "memory", place = "place", kill = "fight", item = "find" }

Vorhaben.TEXT = ns.Locale.ns("Vorhaben", {
  sticker = "To Do",
  stickerTip = { "To Do", "Eigene Reiseziele eintragen und abhaken" },
  head = "To Do",
  brand = "INK & EMBERS",
  dateShort = "%d.%m.",
  title = "Meine To Dos",
  hint = "Neues Ziel …",
  anyZone = "Ort: beliebig",
  add = "Eintragen",
  addTip = { "To Do eintragen", "Enter speichert ebenso." },
  zoneTip = { "Ort wählen", "Kommt Ihr an diesem Ort an, ist das To Do erledigt." },
  empty = "Noch keine To Dos.",
  emptySub = "Tragt oben ein, wohin die Reise gehen soll.",
  emptyHint = "Oben in den Zettel schreiben, Enter speichert.",
  viewOpen = "Offen", viewArchive = "Archiv (%d)",
  viewOpenTip = { "Offen", "Eure offenen To Dos (eben erledigte stehen noch kurz durchgestrichen da)." },
  viewArchiveTip = { "Archiv", "Erledigte To Dos. Dort lassen sie sich zurückholen oder endgültig löschen." },
  archiveTitle = "Archiv",
  archiveCount = "%d erledigt",
  archiveHelp = "Haken entfernen holt ein To Do zurück, × löscht es endgültig.",
  archiveEmpty = "Das Archiv ist leer.",
  archiveEmptySub = "Erledigte To Dos landen nach kurzer Zeit hier.",
  restoreTip = "Zurückholen (wieder offen, Zähler bleiben)",
  deleteForeverTip = "Endgültig löschen",
  confirmDelete = "„%s“ endgültig löschen?",
  confirmYes = "Löschen",
  confirmNo = "Behalten",
  tickTip = "Abhaken",
  untickTip = "Wieder öffnen",
  deleteTip = "Löschen",
  created = "eingetragen %s",
  done = "erledigt %s",
  noZone = "ohne festen Ort",
  errEmpty = "Bitte zuerst einen Text eintragen.",
  errFull = "Die Liste ist voll (höchstens %d To Dos).",
  errNotReady = "Die Chronik ist noch nicht bereit.",
  errUnavailable = "To Dos sind gerade nicht verfügbar.",
  openCount = "%d offen",
  counts = "%d offen · %d erledigt",
  pageOf = "Seite %d von %d",
  nextTitle = "Als Nächstes",
  nextSub = "Das nächste offene Ziel in Eurer Nähe",
  progress = "%d von %d erledigt",
  progressNone = "Noch nichts eingetragen",
  nextEmpty = "Hier erscheint Euer nächstes Ziel.",
  nextAllDone = "Alles erledigt. Zeit für ein neues Ziel!",
  distHere = "Ihr seid schon in der Gegend.",
  distNear = "ganz in der Nähe",
  distKm = "ca. %s km entfernt",
  distFar = "auf einem anderen Kontinent",
  doneHead = "Zuletzt erledigt",
  doneEmpty = "Noch nichts abgehakt.",
  hintText = "Orte, Gegner und Gegenstände haken sich von selbst ab, sobald Ihr das Ziel erreicht habt.",
  miniZettel = "Mini-To-Do-Zettel",
  miniZettelTip = { "Mini-To-Do-Zettel", "Zeigt einen kleinen Notizzettel mit Euren offenen To Dos am Bildschirmrand." },
  kindFree = "Frei", kindPlace = "Ort", kindKill = "Gegner", kindItem = "Gegenstand",
  kindFreeTip = { "Frei", "Nur Text. Abgehakt wird von Hand." },
  kindPlaceTip = { "Ort erreichen", "Eine Stelle auf der Karte. Erledigt, sobald Ihr dort steht." },
  kindKillTip = { "Gegner töten", "Wählt einen Gegner und die Anzahl. Jeder Kill zählt mit." },
  kindItemTip = { "Gegenstände finden", "Wählt einen Gegenstand und die Anzahl. Beute, Questbelohnungen und Handwerk zählen." },
  hintPlace = "Name des Orts (frei) …",
  hintKill = "Gegner suchen …",
  hintItem = "Gegenstand suchen …",
  pickPlace = "Ort auf der Karte wählen",
  pickPlaceTip = { "Ort wählen", "Öffnet eine kleine Karte. Klickt auf die Stelle und übernehmt sie: das To Do wird gleich eingetragen." },
  placeNone = "Noch kein Ort gewählt.",
  placeSet = "Gewählt: %s",
  placeSetXY = "Gewählt: %s (%d, %d)",
  placeUnknown = "ein Ort auf der Karte",
  takeTarget = "Aktuelles Ziel übernehmen",
  takeTargetTip = { "Aktuelles Ziel", "Übernimmt den Gegner, den Ihr gerade im Ziel habt." },
  noTarget = "Ihr habt keinen Gegner im Ziel.",
  targetSet = "Gewählt: %s",
  targetLevel = "Stufe %d",
  freeName = "Wird nach dem Namen gezählt.",
  noData = "Ohne Gegnerliste: Namen genau wie im Spiel eintragen.",
  noDataItem = "Ohne Liste: Namen eintragen oder Umschalt+Klick auf einen Gegenstand.",
  itemHint = "Umschalt+Klick auf einen Gegenstand fügt ihn ein.",
  freeHint = "",
  countTip = { "Anzahl", "Wie viele? (1 bis 999)" },
  errPlace = "Bitte zuerst einen Ort auf der Karte wählen.",
  errTarget = "Bitte einen Namen eintragen oder aus der Liste wählen.",
  errLink = "Nur Gegenstandslinks lassen sich hier einfügen.",
  rankElite = "Elite", rankRare = "Selten", rankBoss = "Boss",
  progressKill = "%d von %d besiegt",
  progressItem = "%d von %d gefunden",
  distM = "ca. %d m entfernt",
  pickTitle = "Ort auf der Karte wählen",
  pickFor = "To Do: %s",
  pickHint = "Klickt auf den Ort, den Ihr erreichen wollt.",
  pickSub = "Mausrad zoomt, Ziehen verschiebt die Karte. Oben rechts wählt Ihr das Gebiet.",
  pickZone = "Gebiet",
  pickZoneTip = { "Gebiet", "Welche Karte gezeigt wird: Eure aktuelle Zone und die Zonen, die Ihr schon bereist habt." },
  pickOk = "Übernehmen",
  pickOkTip = { "Übernehmen", "Trägt das To Do mit diesem Ort sofort ein." },
  pickOkOff = { "Übernehmen", "Klickt zuerst auf die Karte, um den Ort zu wählen." },
  pickNone = "Klickt zuerst auf die Karte, um den Ort zu wählen.",
  pickNoArt = "Für dieses Gebiet gibt es keine Kartenzeichnung. Ein Klick wählt trotzdem die Stelle.",
  pickPinTitle = "Gewählter Ort",
  pickPinHint = "Hier soll es hingehen.",
  pickEsc = "Esc bricht ab",
  pickCancel = "Abbrechen",
  pickMiss = "Dort lässt sich kein Ort wählen. Bitte auf die Karte klicken.",
  errName = "Gebt dem Ziel zuerst einen Namen.",
  errNoZone = "Noch kein Gebiet bekannt. Wählt den Ort, sobald Ihr unterwegs seid.",
  searchTipKill = { "Gegner suchen", "Ab zwei Buchstaben klappt die Liste auf. Ein Klick übernimmt den Gegner." },
  searchTipItem = { "Gegenstand suchen", "Ab zwei Buchstaben klappt die Liste auf. Umschalt+Klick auf einen Gegenstand fügt ihn ein." },
  dataOff = "Die Liste ist ausgeschaltet. Aktiviert „Ink & Embers - Data“ im Addon-Menü (Charakterauswahl, AddOns) und ladet neu (/reload).",
  dataMissing = "Liste nicht geladen: %s. Namen genau wie im Spiel eintragen.",
  noDataOff = "Gegnerliste im Addon-Menü aus: Namen genau wie im Spiel eintragen.",
  noDataItemOff = "Liste im Addon-Menü aus: Namen eintragen oder Umschalt+Klick.",
  pinHint = "To Do: Ort erreichen",
})

local T = Vorhaben.TEXT
local LY = Vorhaben.LAYOUT

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function shown(s, maxBytes)
  if isSecret(s) or type(s) ~= "string" then return nil end
  return ns.Sanitize.display(s, maxBytes or Vorhaben.TEXT_BYTES)
end

local function safeDate(t)
  t = num(t)
  if not t then return nil end
  local ok, s = pcall(date, Vorhaben.TEXT.dateShort, t)
  return (ok and type(s) == "string") and s or nil
end

local function plans()
  return ns.Plans
end

local function allPlans(filter)
  local P = plans()
  if not P or type(P.list) ~= "function" then return {} end
  local ok, list = pcall(P.list, filter)
  return (ok and type(list) == "table") and list or {}
end

local function zoneName(mapID)
  local B = Journal.Begleiter
  if B and B.mapName then return B.mapName(mapID) end
  return nil
end

local V = { page = 1, zone = nil, open = false, kind = "free", place = nil, target = nil, picking = false,
  view = "open", doneAtOpen = nil }
Vorhaben.state = V

local function distText(dist)
  if dist == "here" then return T.distHere end
  if dist == "far" then return T.distFar end
  if type(dist) ~= "number" then return "" end
  if dist < 0.5 then return T.distNear end
  local s = dist < 10 and string.format("%.1f", dist) or tostring(floor(dist + 0.5))
  return string.format(T.distKm, (s:gsub("%.", ns.Locale.get("Fmt", "decimal"))))
end
Vorhaben.distText = distText

local function nowT()
  local ok, t = pcall(time)
  return (ok and num(t)) or 0
end

local function archived(p)
  local d = num(p.done)
  if not d then return false end
  if not V.doneAtOpen or V.doneAtOpen[p.id] then return true end
  return nowT() - d >= Vorhaben.ARCHIVE_DELAY
end
Vorhaben.isArchived = archived

local function viewPlans()
  local out, arch = {}, V.view == "archive"
  local TT = Journal.TodoTracker
  for _, p in ipairs(allPlans()) do
    if archived(p) == arch then
      out[#out + 1] = p
      -- an open shopping list (Einkaufszettel) is followed by its material lines, each on a line of the ruled paper
      if p.shop == true and not arch and not (p.done ~= nil and p.done ~= false) and TT and type(TT.shopSubRows) == "function" then
        local ok, subs = pcall(TT.shopSubRows, { id = p.id, shop = true, done = false })
        if ok and type(subs) == "table" then
          for _, s in ipairs(subs) do
            s.mat = true
            out[#out + 1] = s
          end
        end
      end
    end
  end
  return out
end

function Vorhaben.archiveCount()
  local n = 0
  for _, p in ipairs(allPlans("done")) do if archived(p) then n = n + 1 end end
  return n
end

function Vorhaben.pages()
  return max(1, ceil(#viewPlans() / Vorhaben.ROWS))
end

function Vorhaben.counts()
  local open, done = 0, 0
  for _, p in ipairs(allPlans()) do
    if p.done ~= nil and p.done ~= false then done = done + 1 else open = open + 1 end
  end
  return open, done
end

local function kindOf(p)
  local k = type(p) == "table" and p.kind
  if k == "place" or k == "kill" or k == "item" then return k end
  return "free"
end

local function metersText(m)
  m = num(m)
  if not m then return nil end
  if m >= 1000 then return distText(m / 1000) end
  return string.format(T.distM, max(1, floor(m + 0.5)))
end
Vorhaben.metersText = metersText

local function progressOf(p)
  local k = kindOf(p)
  if k ~= "kill" and k ~= "item" then return nil end
  if type(p.progress) == "string" then return shown(p.progress, 16) end
  local need, have = num(p.need) or 1, num(p.have) or 0
  return string.format("%d/%d", floor(have), floor(need))
end

function Vorhaben.rows(page)
  local list = viewPlans()
  page = max(1, min(floor(tonumber(page) or 1), max(1, ceil(#list / Vorhaben.ROWS))))
  local out = {}
  for i = (page - 1) * Vorhaben.ROWS + 1, min(#list, page * Vorhaben.ROWS) do
    local p = list[i]
    local done = p.done ~= nil and p.done ~= false
    local kind = kindOf(p)
    local shop = p.shop == true
    if p.mat then
      -- material line of a shopping list: name + count, no tick box, nothing to delete
      out[#out + 1] = { plan = p, id = p.id, planId = p.planId, mat = true, shop = true, kind = "item", done = done,
        text = shown(p.more and p.text or (p.name or p.text)) or "", date = "", sub = "",
        progress = (not p.more and num(p.have) and num(p.need)) and string.format("%d/%d", p.have, p.need) or nil }
    else
    if shop then kind = "item" end -- shopping list (Einkaufszettel): bag icon, progress "3/5", click opens the slip
    local zone = p.mapID and zoneName(p.mapID) or nil
    local d = safeDate(done and p.done or p.created)
    local dateText = d and string.format(done and T.done or T.created, d) or ""
    local dist = (kind == "place" and not done) and metersText(p.dist) or nil
    local parts = {}
    if zone then parts[#parts + 1] = zone end
    if dist then parts[#parts + 1] = dist end
    if dateText ~= "" then parts[#parts + 1] = dateText end
    out[#out + 1] = { plan = p, id = p.id, text = shown(p.text) or "", zone = zone, date = dateText, done = done,
      kind = kind, progress = shop and shown(p.progress, 16) or progressOf(p), dist = dist, sub = table.concat(parts, " · "),
      shop = shop or nil }
    end
  end
  return out, page
end

function Vorhaben.doneRows(n)
  local out = {}
  for _, p in ipairs(allPlans("done")) do
    if #out >= (n or Vorhaben.DONE_MAX) then break end
    local d = safeDate(p.done)
    local label = p.text
    local P = plans()
    if P and type(P.label) == "function" then
      local ok, l = pcall(P.label, p)
      if ok and type(l) == "string" then label = l end
    end
    out[#out + 1] = { id = p.id, text = shown(label) or "", date = d or "" }
  end
  return out
end

local function onContinent(mapID, cont, player)
  local Geo = Journal.Geo
  if not (Geo and Geo.affine) then return nil end
  local ok, a, b, c, d = pcall(Geo.affine, mapID, cont)
  if not ok or not (num(a) and num(b) and num(c) and num(d)) then return nil end
  local x, y = 0.5, 0.5
  if player and C_Map and type(C_Map.GetPlayerMapPosition) == "function" then
    local okP, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if okP and type(pos) == "table" then
      local okXY, px, py = pcall(function() return pos:GetXY() end)
      if not okXY and type(pos.x) == "number" then px, py, okXY = pos.x, pos.y, true end
      if okXY and num(px) and num(py) and px >= 0 and px <= 1 and py >= 0 and py <= 1 then x, y = px, py end
    end
  end
  return a + b * x, c + d * y
end

local function distanceTo(mapID)
  local Geo, Zone = Journal.Geo, ns.Zone
  if not (Geo and Zone and Geo.continentOf) then return nil end
  local okH, here = pcall(Zone.here)
  here = okH and num(here) or nil
  if not here then return nil end
  local okA, c1 = pcall(Geo.continentOf, here)
  local okB, c2 = pcall(Geo.continentOf, mapID)
  if not (okA and okB and c1 and c2) then return nil end
  if c1 ~= c2 then return "far" end
  local x1, y1 = onContinent(here, c1, true)
  local x2, y2 = onContinent(mapID, c1, false)
  if not (x1 and x2) then return nil end
  local okS, w, h = pcall(Geo.mapSize, c1)
  if not (okS and num(w) and num(h)) then return nil end
  local dx, dy = (x1 - x2) * w, (y1 - y2) * h
  return sqrt(dx * dx + dy * dy) * Vorhaben.YARD_KM
end

function Vorhaben.nextPlan()
  local open = allPlans("open")
  if #open == 0 then return nil end
  local P = plans()
  local pick, dist
  if P and type(P.nearby) == "function" then
    local ok, near = pcall(P.nearby)
    if ok and type(near) == "table" and type(near[1]) == "table" then pick, dist = near[1], "here" end
  end
  if not pick then
    local best = math.huge
    for _, p in ipairs(open) do
      if p.mapID then
        local d = (kindOf(p) == "place" and num(p.dist)) and p.dist / 1000 or distanceTo(p.mapID)
        local rank = (type(d) == "number" and d) or (d == "far" and 1e8) or 1e9
        if rank < best then pick, dist, best = p, d, rank end
      end
    end
  end
  pick = pick or open[1]
  local kind = kindOf(pick)
  local text = distText(dist)
  if kind == "place" and num(pick.dist) then
    text = metersText(pick.dist)
  elseif kind == "kill" or kind == "item" then
    local need, have = floor(num(pick.need) or 1), floor(num(pick.have) or 0)
    text = string.format(kind == "kill" and T.progressKill or T.progressItem, have, need)
  end
  return { id = pick.id, text = shown(pick.text) or "", zone = pick.mapID and zoneName(pick.mapID) or nil, dist = dist,
    distText = text, kind = kind, progress = progressOf(pick) }
end

function Vorhaben.zoneItems()
  local items = { { text = T.anyZone, value = false, active = V.zone == nil } }
  local Zone = ns.Zone
  if not Zone then return items end
  local seen, list = {}, {}
  local function add(id, first)
    id = num(id)
    if not id or id <= 0 or id ~= floor(id) or seen[id] then return end
    local name = zoneName(id)
    if not name then return end
    seen[id] = true
    local it = { text = name, value = id, active = V.zone == id }
    if first then table.insert(items, 2, it) else list[#list + 1] = it end
  end
  local okHere, here = pcall(Zone.here)
  if okHere and here then
    local okZ, zone = pcall(Zone.ancestor, here, Zone.TYPE_ZONE)
    if okZ then add(zone, true) end
  end
  local Store = ns.Store
  local char = Store and Store.char and Store.char()
  local snaps = type(char) == "table" and char.snapshots
  local maps = type(snaps) == "table" and snaps.maps
  if type(maps) == "table" then
    local n = 0
    for key in pairs(maps) do
      n = n + 1
      if n > 600 then break end
      local id = tonumber(key)
      local info = id and Zone.info(id)
      if info and num(info.mapType) == Zone.TYPE_ZONE then add(id) end
    end
  end
  table.sort(list, function(a, b) if a.text ~= b.text then return a.text < b.text end return a.value < b.value end)
  for i = 1, min(#list, Vorhaben.ZONES_MAX) do items[#items + 1] = list[i] end
  return items
end

local function countValue()
  local n = V.countBox and tonumber(V.countBox:GetText())
  if not n or n ~= n then return 1 end
  return max(1, min(floor(n), 999))
end

local function setEditText(text)
  if not V.edit then return end
  V.quiet = true
  V.edit:SetText(text or "")
  V.quiet = false
  if V.edit.hint then V.edit.hint:SetShown(text == nil or text == "") end
end

function Vorhaben.submit()
  local P = plans()
  if not P or type(P.add) ~= "function" then
    Vorhaben.message(T.errUnavailable)
    return false, "nicht-verfuegbar"
  end
  local text = V.edit and V.edit:GetText() or ""
  if type(text) ~= "string" then text = "" end
  local kind = V.kind or "free"
  local ok, id, why
  if kind == "place" then
    if not V.place then
      Vorhaben.message(T.errPlace)
      return false, "ort"
    end
    ok, id, why = pcall(P.add, { kind = "place", text = text, mapID = V.place.mapID, x = V.place.x, y = V.place.y })
  elseif kind == "kill" or kind == "item" then
    local target = V.target
    if not (target and target.name == text) then target = { name = text } end
    ok, id, why = pcall(P.add, { kind = kind, target = { id = target.id, name = target.name }, need = countValue() })
  else
    ok, id, why = pcall(P.add, text)
  end
  if not ok then
    Vorhaben.message(T.errUnavailable)
    return false, "fehler"
  end
  if not id then
    local msg = (why == "leer" and ((kind == "kill" or kind == "item") and T.errTarget or T.errEmpty))
      or (why == "ziel" and T.errTarget) or (why == "ort" and T.errPlace)
      or (why == "voll" and string.format(T.errFull, P.MAX or 200))
      or (why == "nicht-bereit" and T.errNotReady) or T.errUnavailable
    Vorhaben.message(msg)
    return false, why
  end
  setEditText("")
  if V.edit and V.edit.ClearFocus then V.edit:ClearFocus() end
  V.zone, V.place, V.target = nil, nil, nil
  if V.zoneDrop then V.zoneDrop:SetText(T.anyZone) end
  if V.countBox then V.countBox:SetText("1") end
  if V.searchDrop and V.searchDrop:IsOpen() then V.searchDrop:Close() end
  V.page = 1
  Vorhaben.message("")
  Vorhaben.paintOptions()
  Vorhaben.refresh()
  return true, id
end

function Vorhaben.message(text)
  if not V.msg then return end
  V.msg:SetText(text or "")
  if V.counts then V.counts:SetShown(text == nil or text == "") end
end

local function toggleDone(id)
  local P = plans()
  if P and P.toggle then P.toggle(id) end
  if V.doneAtOpen then V.doneAtOpen[id] = nil end
  Vorhaben.refresh()
end

local function delete(id)
  local P = plans()
  if P and P.remove then P.remove(id) end
  Vorhaben.refresh()
end

local function step(delta)
  local pages = Vorhaben.pages()
  local page = max(1, min(pages, (V.page or 1) + delta))
  if page == V.page then return end
  V.page = page
  if Journal.Sound then pcall(Journal.Sound.play, "page") end
  Vorhaben.refresh()
end

local function strWidth(fs, fallback)
  local ok, w = pcall(fs.GetStringWidth, fs)
  return (ok and type(w) == "number" and w > 0) and w or fallback
end

local function paintDel(row)
  local on = (row.hoverRow or row.hoverDel) and row.data ~= nil
  row.delBtn:SetAlpha(on and 1 or 0)
  row.delBtn.x:SetTextColor(W.color(row.hoverDel and "red" or "sepia"))
end

local function paintRow(row)
  local d = row.data
  if not d then
    row:Hide()
    return
  end
  row:Show()
  -- a material line of a shopping list: indented name + count on its own ruled line, no tick box, nothing to delete
  row.subLabel:SetShown(d.mat == true)
  row.tickBtn:SetShown(d.mat ~= true)
  row.delBtn:SetShown(d.mat ~= true)
  if d.mat then
    W.setText(row.label, "")
    W.setText(row.subLabel, d.text)
    row.subLabel:SetTextColor(W.color(d.done and "sepia" or "ink"))
    W.setText(row.progress, d.progress or "")
    row.progress:SetShown(d.progress ~= nil)
    row.progress:SetTextColor(W.color(d.done and "sepia" or "red"))
    row.kindIcon:Hide()
    row.pin:Hide()
    row.tick:Hide()
    row.strike:SetShown(d.done)
    if d.done then row.strike:SetWidth(max(8, min(strWidth(row.subLabel, #d.text * 7) + 6, row.textW - 20))) end
    row.strike:ClearAllPoints()
    row.strike:SetPoint("LEFT", row, "TOPLEFT", 53, -17)
    W.setText(row.zone, "")
    W.setText(row.date, "")
    return
  end
  row.strike:ClearAllPoints()
  row.strike:SetPoint("LEFT", row, "TOPLEFT", 29, -13)
  W.setText(row.label, d.text)
  row.label:SetTextColor(W.color(d.done and "sepia" or "ink"))
  local prog = d.progress
  W.setText(row.progress, prog or "")
  row.progress:SetShown(prog ~= nil)
  row.progress:SetTextColor(W.color(d.done and "sepia" or "red"))
  row.label:SetWidth(prog and (row.textW - Vorhaben.PROGRESS_W) or row.textW)
  local kindIcon = d.kind ~= nil and d.kind ~= "free"
  if kindIcon and row.kindIcon.setKind then row.kindIcon.setKind(d.kind) end
  row.kindIcon:SetShown(kindIcon)
  local sub = d.zone or ""
  if d.dist then sub = (sub ~= "" and (sub .. " · ") or "") .. d.dist end
  W.setText(row.zone, sub)
  row.pin:SetShown(d.zone ~= nil and not kindIcon)
  W.setText(row.date, d.date)
  row.tick:SetShown(d.done)
  row.strike:SetShown(d.done)
  if d.done then row.strike:SetWidth(max(8, min(strWidth(row.label, #d.text * 8) + 6, (row.label:GetWidth() or row.textW) + 6))) end
  paintDel(row)
end

function Vorhaben.paintMini()
  local b = V.miniBox
  if not b then return end
  local TT = Journal.TodoTracker
  b:SetShown(TT ~= nil and type(TT.settings) == "function")
  if TT and type(TT.settings) == "function" then b:SetChecked(TT.settings().shown == true, true) end
end

local function paintRight()
  Vorhaben.paintMini()
  local open, done = Vorhaben.counts()
  local total = open + done
  W.setText(V.progress, total > 0 and string.format(T.progress, done, total) or T.progressNone)
  local frac = total > 0 and done / total or 0
  V.barFill:SetShown(frac > 0)
  V.barFill:SetWidth(max(1, floor(V.barW * frac + 0.5)))
  local nx = Vorhaben.nextPlan()
  V.next = nx
  local has = nx ~= nil
  V.nextText:SetShown(has)
  if V.nextHover then V.nextHover:SetShown(has) end
  V.nextIcon:SetShown(has)
  V.nextRing:SetShown(has)
  V.nextZone:SetShown(has)
  V.nextPin:SetShown(has and nx.zone ~= nil)
  V.nextDist:SetShown(has)
  V.nextEmpty:SetShown(not has)
  if has then
    W.setText(V.nextText, nx.text)
    W.setText(V.nextZone, nx.zone or T.noZone)
    W.setText(V.nextDist, nx.distText or "")
  else
    W.setText(V.nextEmpty, total > 0 and T.nextAllDone or T.nextEmpty)
  end
  local rows = Vorhaben.doneRows(Vorhaben.DONE_MAX)
  for i, r in ipairs(V.doneRows) do
    local d = rows[i]
    r:SetShown(d ~= nil)
    if d then
      W.setText(r.label, d.text)
      W.setText(r.date, d.date)
      r.data = d
    else
      r.data = nil
    end
  end
  V.doneEmpty:SetShown(#rows == 0)
  local F = Journal.Frame
  local line = F and F.state and F.state.headLine and F.state.headLine.GetText and F.state.headLine:GetText()
  V.headR:SetTexts(type(line) == "string" and line or "", T.head)
end

function Vorhaben.setView(view)
  if view ~= "open" and view ~= "archive" then return false end
  Vorhaben.cancelDelete()
  if view == "archive" then Vorhaben.cancelPick() end
  V.view = view
  V.page = 1
  if V.viewToggle then V.viewToggle:SetValue(view) end
  if V.panel then
    local arch = view == "archive"
    V.kindToggle.frame:SetShown(not arch)
    V.slip:SetShown(not arch)
    V.add:SetShown(not arch)
    V.archiveHelp:SetShown(arch)
    W.setText(V.title, arch and T.archiveTitle or T.title)
    if V.searchDrop and V.searchDrop:IsOpen() then V.searchDrop:Close() end
    if arch and V.edit and V.edit.ClearFocus then V.edit:ClearFocus() end
    Vorhaben.message("")
    Vorhaben.paintOptions()
    Vorhaben.refresh()
  end
  return true
end

function Vorhaben.view() return V.view end

local function buildConfirm()
  if V.confirm then return V.confirm end
  local L = LY.L
  local c = CreateFrame("Frame", nil, V.panel)
  c:SetSize(L.w + 8, Vorhaben.ROW_H + 2)
  c.slip = D.NewSlip(c)
  c:SetFrameLevel((V.panel:GetFrameLevel() or 1) + 30)
  c:EnableMouse(true)
  local txt = D.font(c, "text", 13, "ink")
  txt:SetPoint("LEFT", c, "LEFT", 10, 0)
  txt:SetWidth(L.w - 214)
  txt:SetJustifyH("LEFT")
  txt:SetWordWrap(false)
  c.text = txt
  local no = D.NewOpenLink(c, T.confirmNo, function() Vorhaben.cancelDelete() end, { size = 12 })
  no:SetPoint("RIGHT", c, "RIGHT", -8, 0)
  c.no = no
  local yes = D.NewOpenLink(c, T.confirmYes, function() Vorhaben.confirmDelete() end, { size = 12, tip = { T.deleteForeverTip } })
  yes:SetPoint("RIGHT", no, "LEFT", -10, 0)
  yes.text:SetTextColor(W.color("red"))
  c.yes = yes
  D.escKeys(c, function() Vorhaben.cancelDelete() end)
  c:Hide()
  V.confirm = c
  return c
end

function Vorhaben.askDelete(id, row)
  if V.view ~= "archive" or not V.panel then return false end
  local p
  for _, q in ipairs(viewPlans()) do if q.id == id then p = q break end end
  if not p then return false end
  local c = buildConfirm()
  c:ClearAllPoints()
  if row then
    c:SetPoint("LEFT", row, "LEFT", -4, 0)
  else
    c:SetPoint("TOPLEFT", V.panel, "TOPLEFT", LY.L.x, -Vorhaben.LIST_Y)
  end
  c.id = id
  W.setText(c.text, string.format(T.confirmDelete, shown(p.text, 120) or ""))
  W.fitLine(c.text, LY.L.w - 214, 10)
  c:Show()
  return true
end

function Vorhaben.cancelDelete()
  if V.confirm then
    V.confirm.id = nil
    V.confirm:Hide()
  end
end

function Vorhaben.confirmDelete()
  local c = V.confirm
  local id = c and c.id
  Vorhaben.cancelDelete()
  if not id then return false end
  delete(id)
  return true
end

local function scheduleArchive()
  if V.view ~= "open" or not (type(C_Timer) == "table" and type(C_Timer.After) == "function") then return end
  local soonest
  local t = nowT()
  for _, p in ipairs(allPlans("done")) do
    local d = num(p.done)
    if d and not archived(p) then
      local left = Vorhaben.ARCHIVE_DELAY - (t - d)
      if not soonest or left < soonest then soonest = left end
    end
  end
  if not soonest then return end
  V.archiveToken = (V.archiveToken or 0) + 1
  local my = V.archiveToken
  C_Timer.After(max(0.1, soonest + 0.1), function()
    if my ~= V.archiveToken or not Vorhaben.isOpen() then return end
    W.call(Vorhaben.refresh)
  end)
end

function Vorhaben.refresh()
  if not V.panel then return end
  local rows, page = Vorhaben.rows(V.page)
  V.page = page
  local pages = Vorhaben.pages()
  for i, row in ipairs(V.rows) do
    row.data = rows[i]
    paintRow(row)
  end
  local empty = #rows == 0
  local arch = V.view == "archive"
  V.emptyText:SetText(arch and T.archiveEmpty or T.empty)
  V.emptySub:SetText(arch and T.archiveEmptySub or T.emptySub)
  V.emptyText:SetShown(empty)
  V.emptySub:SetShown(empty)
  V.emptyHint:SetShown(empty and not arch)
  local nArch = Vorhaben.archiveCount()
  if V.viewToggle and V.viewToggle.buttons and V.viewToggle.buttons[2] then
    local b = V.viewToggle.buttons[2]
    if b.text then W.setText(b.text, string.format(T.viewArchive, nArch)) end
  end
  if V.confirm and V.confirm:IsShown() and not arch then Vorhaben.cancelDelete() end
  scheduleArchive()
  V.nav.frame:SetShown(pages > 1)
  V.nav:SetEnabled(page > 1, page < pages)
  V.pageText:SetShown(pages > 1)
  V.pageText:SetText(string.format(T.pageOf, page, pages))
  local open, done = Vorhaben.counts()
  V.count:SetText(string.format(T.openCount, open))
  if arch then
    V.counts:SetText(string.format(T.archiveCount, nArch))
  else
    V.counts:SetText((open + done) > 0 and string.format(T.counts, open, done) or "")
  end
  paintRight()
end

local function buildRow(panel, i)
  local L = LY.L
  local row = CreateFrame("Button", nil, panel)
  row:SetSize(L.w, Vorhaben.ROW_H)
  row:SetPoint("TOPLEFT", panel, "TOPLEFT", L.x, -(Vorhaben.LIST_Y + (i - 1) * Vorhaben.ROW_H))
  local tickBtn = CreateFrame("Button", nil, row)
  tickBtn:SetSize(24, 24)
  tickBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
  local box = D.mark(tickBtn, "box", 20, "ink")
  box:SetPoint("CENTER", tickBtn, "CENTER", 0, 0)
  local tick = D.mark(tickBtn, "tick", 26, "red", "OVERLAY")
  tick:SetPoint("CENTER", box, "CENTER", 4, 4)
  tick:Hide()
  row.box, row.tick = box, tick
  row.textW = L.w - 32 - 28
  local label = D.font(row, "hand", 21, "ink")
  label:SetPoint("TOPLEFT", row, "TOPLEFT", 32, -1)
  label:SetWidth(row.textW)
  label:SetJustifyH("LEFT")
  label:SetWordWrap(false)
  row.label = label
  local subLabel = D.font(row, "text", 14, "ink")
  subLabel:SetPoint("TOPLEFT", row, "TOPLEFT", 52, -9)
  subLabel:SetWidth(row.textW - 20 - Vorhaben.PROGRESS_W)
  subLabel:SetJustifyH("LEFT")
  subLabel:SetWordWrap(false)
  subLabel:Hide()
  row.subLabel = subLabel
  local strike = D.NewInkStroke(row, 40, "ink", 0.8, "OVERLAY")
  strike:SetPoint("LEFT", row, "TOPLEFT", 29, -13)
  strike:Hide()
  row.strike = strike
  local pin = row:CreateTexture(nil, "ARTWORK")
  pin:SetSize(13, 13)
  pin:SetPoint("TOPLEFT", row, "TOPLEFT", 33, -Vorhaben.SUB_Y)
  local Theme = Journal.Theme
  local u0, u1, v0, v1
  if Theme and Theme.mapIconCoords then u0, u1, v0, v1 = Theme.mapIconCoords("gap") end
  if Theme and Theme.HAS_MAP_ICONS and u0 and pcall(pin.SetTexture, pin, Theme.TEX.mapIcons) then
    pin:SetTexCoord(u0, u1, v0, v1)
    pin:SetVertexColor(W.color("sepia"))
  else
    pin:SetColorTexture(W.color("sepia", 0.5))
    pin:SetSize(5, 5)
  end
  pin:Hide()
  row.pin = pin
  local zone = D.font(row, "label", 11, "sepia")
  zone:SetPoint("TOPLEFT", row, "TOPLEFT", 50, -Vorhaben.SUB_Y)
  zone:SetWidth(L.w - 50 - 120)
  zone:SetJustifyH("LEFT")
  zone:SetWordWrap(false)
  row.zone = zone
  local dateFs = D.font(row, "label", 11, "sepia")
  dateFs:SetTextColor(W.color(Vorhaben.GREY))
  dateFs:SetPoint("TOPRIGHT", row, "TOPRIGHT", -28, -Vorhaben.SUB_Y)
  dateFs:SetWidth(110)
  dateFs:SetJustifyH("RIGHT")
  dateFs:SetWordWrap(false)
  row.date = dateFs
  local ki = row:CreateTexture(nil, "ARTWORK")
  ki:SetSize(15, 15)
  ki:SetPoint("TOPLEFT", row, "TOPLEFT", 32, -(Vorhaben.SUB_Y - 1))
  local hasIcons = Theme and Theme.TEX and Theme.TEX.momentIcons and Theme.momentIconCoords and pcall(ki.SetTexture, ki, Theme.TEX.momentIcons)
  ki.setKind = function(kind)
    if hasIcons then
      ki:SetTexCoord(Theme.momentIconCoords(Vorhaben.KIND_ICON[kind] or "memory"))
    else
      ki:SetColorTexture(W.color(kind == "kill" and "red" or "sepia", 0.6))
    end
  end
  ki:Hide()
  row.kindIcon = ki
  local prog = D.font(row, "label", 14, "red")
  prog:SetPoint("TOPRIGHT", row, "TOPRIGHT", -28, -4)
  prog:SetWidth(Vorhaben.PROGRESS_W - 4)
  prog:SetJustifyH("RIGHT")
  prog:SetWordWrap(false)
  prog:Hide()
  row.progress = prog
  local del = CreateFrame("Button", nil, row)
  del:SetSize(24, 24)
  del:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
  local x = D.font(del, "hand", 26, "sepia")
  x:SetPoint("CENTER", del, "CENTER", 0, 1)
  x:SetText("×")
  del.x = x
  del:SetAlpha(0)
  row.tickBtn, row.delBtn = tickBtn, del
  tickBtn:SetScript("OnClick", function()
    local d = row.data
    if d then W.call(toggleDone, d.id) end
  end)
  tickBtn:SetScript("OnEnter", function(b)
    box:SetVertexColor(W.color("red", box.diaryOk and 1 or 0.25))
    row.hoverRow = true
    paintDel(row)
    local d = row.data
    if d then W.tip(b, { (V.view == "archive" and T.restoreTip) or (d.done and T.untickTip) or T.tickTip }) end
  end)
  tickBtn:SetScript("OnLeave", function(b)
    box:SetVertexColor(W.color("ink", box.diaryOk and 1 or 0.25))
    row.hoverRow = false
    paintDel(row)
    W.hideTip(b)
  end)
  del:SetScript("OnClick", function()
    local d = row.data
    if not d then return end
    if V.view == "archive" then W.call(Vorhaben.askDelete, d.id, row) else W.call(delete, d.id) end
  end)
  del:SetScript("OnEnter", function(b)
    row.hoverDel = true
    paintDel(row)
    W.tip(b, { V.view == "archive" and T.deleteForeverTip or T.deleteTip })
  end)
  del:SetScript("OnLeave", function(b)
    row.hoverDel = false
    paintDel(row)
    W.hideTip(b)
  end)
  row:SetScript("OnEnter", function(r)
    r.hoverRow = true
    paintDel(r)
    local d = r.data
    if d and d.text ~= "" then
      local lines = { d.text }
      if d.sub ~= "" then lines[2] = d.sub end
      if d.shop and Journal.TodoTracker then lines[#lines + 1] = Journal.TodoTracker.TEXT.shopHint end
      W.tip(r, lines)
    end
  end)
  row:SetScript("OnClick", function(r)
    local d = r.data
    local Z = Journal.Einkaufszettel
    if d and d.shop and not d.done and Z and type(Z.open) == "function" then W.call(Z.open, { id = d.planId or d.id, anchor = r }) end
  end)
  row:SetScript("OnLeave", function(r)
    r.hoverRow = false
    paintDel(r)
    W.hideTip(r)
  end)
  return row
end

local function slipFrame(parent, x, y, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  f.slip = D.NewSlip(f)
  return f
end

local function setFont(eb, size)
  local Theme = Journal.Theme
  local hand = Theme and Theme.FONT and Theme.FONT.hand
  local ok, res = false, nil
  if hand then ok, res = pcall(eb.SetFont, eb, hand, size, "") end
  if ok and res ~= false then return end
  pcall(eb.SetFont, eb, (W.FONT and W.FONT.text) or (Theme and Theme.FONT and Theme.FONT.text), floor(size * 0.75 + 0.5), "")
end

local function buildLeft(panel)
  local L = LY.L
  V.headL = W.NewPageHead(panel, { side = "L" })
  V.headL:SetTexts(T.brand, T.head)
  local title = D.font(panel, "hand", 34, "ink")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", L.x, -LY.titleY)
  title:SetText(T.title)
  V.title = title
  local counts = D.font(panel, "label", 12, "sepia")
  counts:SetPoint("TOPLEFT", panel, "TOPLEFT", L.x, -LY.subY)
  counts:SetJustifyH("LEFT")
  V.counts = counts
  local count = D.font(panel, "label", 12, "sepia")
  count:SetPoint("TOPRIGHT", panel, "TOPLEFT", L.x + L.w, -LY.subY)
  count:SetJustifyH("RIGHT")
  count:Hide()
  V.count = count
  local msg = D.font(panel, "label", 12, "red")
  msg:SetPoint("TOPLEFT", panel, "TOPLEFT", L.x, -LY.subY)
  msg:SetWidth(L.w)
  msg:SetJustifyH("LEFT")
  msg:SetWordWrap(false)
  V.msg = msg

  local toggle = D.NewToggle(panel, { size = 14, gap = 14, value = V.kind, items = {
      { key = "free", label = T.kindFree, tip = T.kindFreeTip },
      { key = "place", label = T.kindPlace, tip = T.kindPlaceTip },
      { key = "kill", label = T.kindKill, tip = T.kindKillTip },
      { key = "item", label = T.kindItem, tip = T.kindItemTip },
    },
    onChange = function(key) Vorhaben.setKind(key) end })
  toggle.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", L.x, -LY.kindY)
  V.kindToggle = toggle

  local slip = slipFrame(panel, L.x, LY.slipY, LY.slipW, LY.slipH)
  V.slip = slip
  local fieldW = LY.slipW - LY.dropW - 14
  local eb = CreateFrame("EditBox", nil, slip)
  eb:SetSize(fieldW, LY.slipH - 4)
  eb:SetPoint("LEFT", slip, "LEFT", 4, 0)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters((plans() and plans().TEXT_MAX) or 120)
  eb:SetTextInsets(6, 4, 0, 0)
  setFont(eb, 19)
  eb:SetTextColor(W.color("ink"))
  eb.hint = D.font(eb, "hand", 19, "sepia")
  eb.hint:SetPoint("LEFT", eb, "LEFT", 6, 0)
  eb.hint:SetText(T.hint)
  eb.hint:SetAlpha(0.75)
  eb:SetScript("OnTextChanged", function(box)
    local text = box:GetText()
    box.hint:SetShown(type(text) ~= "string" or text == "")
    if V.quiet then return end
    Vorhaben.message("")
    W.call(Vorhaben.typed, text)
  end)
  eb:SetScript("OnEnter", function(box)
    local ok, lines = pcall(Vorhaben.searchTip)
    if ok and lines then W.tip(box, lines) end
  end)
  eb:SetScript("OnLeave", function(box) W.hideTip(box) end)
  eb:SetScript("OnEnterPressed", function() W.call(Vorhaben.submit) end)
  eb:SetScript("OnEscapePressed", function(box)
    if V.searchDrop and V.searchDrop:IsOpen() then V.searchDrop:Close() return end
    box:ClearFocus()
  end)
  V.edit = eb
  local sep = W.NewRect(slip, "ink", 0.3, "ARTWORK")
  sep:SetSize(1, LY.slipH - 12)
  sep:SetPoint("LEFT", slip, "LEFT", fieldW + 6, 0)
  V.sep = sep
  local dd = D.NewDropdown(slip, { width = LY.dropW, size = 12, text = T.anyZone, items = Vorhaben.zoneItems(), rows = 10,
    popupWidth = 230, tip = T.zoneTip,
    onPick = function(it) V.zone = (type(it.value) == "number") and it.value or nil end })
  dd:SetPoint("LEFT", slip, "LEFT", fieldW + 9, 0)
  if dd.line then dd.line:Hide() end
  V.zoneDrop = dd

  local times = D.font(slip, "hand", 19, "sepia")
  times:SetText("×")
  times:Hide()
  V.countTimes = times
  local cb = CreateFrame("EditBox", nil, slip)
  cb:SetSize(LY.countW - 22, LY.slipH - 4)
  cb:SetAutoFocus(false)
  if cb.SetNumeric then cb:SetNumeric(true) end
  cb:SetMaxLetters(3)
  cb:SetTextInsets(2, 2, 0, 0)
  setFont(cb, 19)
  cb:SetTextColor(W.color("ink"))
  cb:SetText("1")
  cb:SetScript("OnEnterPressed", function() W.call(Vorhaben.submit) end)
  cb:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
  cb:SetScript("OnEditFocusLost", function(box) box:SetText(tostring(countValue())) end)
  cb:SetScript("OnEnter", function(box) W.tip(box, T.countTip) end)
  cb:SetScript("OnLeave", function(box) W.hideTip(box) end)
  cb:Hide()
  V.countBox = cb

  local sd = D.NewDropdown(slip, { width = fieldW, size = 12, keepText = true, rows = LY.popupRows, popupWidth = LY.popupW,
    onPick = function(it) Vorhaben.pickTarget(it) end })
  sd:ClearAllPoints()
  sd:SetPoint("BOTTOMLEFT", slip, "BOTTOMLEFT", 4, 2)
  sd:SetAlpha(0)
  sd:EnableMouse(false)
  V.searchDrop = sd

  local nav = D.NewNavPair(panel, { size = 20, onPrev = function() step(-1) end, onNext = function() step(1) end })
  nav.frame:SetPoint("RIGHT", panel, "TOPLEFT", L.x + L.w + 4, -(LY.slipY + LY.slipH / 2))
  V.nav = nav
  local pageText = D.font(panel, "label", 12, "sepia")
  pageText:SetPoint("RIGHT", nav.frame, "LEFT", -4, 0)
  pageText:SetJustifyH("RIGHT")
  V.pageText = pageText

  local pick = D.NewOpenLink(panel, T.pickPlace, function() Vorhaben.startPick() end, { size = 13, tip = T.pickPlaceTip })
  pick:SetPoint("TOPLEFT", panel, "TOPLEFT", L.x, -LY.optY)
  pick:Hide()
  V.pickBtn = pick
  local take = D.NewOpenLink(panel, T.takeTarget, function() Vorhaben.takeTarget() end, { size = 13, tip = T.takeTargetTip })
  take:SetPoint("TOPLEFT", panel, "TOPLEFT", L.x, -LY.optY)
  take:Hide()
  V.takeBtn = take
  local status = D.font(panel, "label", 12, "sepia")
  status:SetJustifyH("LEFT")
  status:SetWordWrap(false)
  V.optStatus = status

  for i = 1, Vorhaben.ROWS do
    local line = W.NewRect(panel, D.ROW_LINE.color, D.ROW_LINE.alpha, "BORDER")
    line:SetSize(L.w, 1)
    line:SetPoint("TOPLEFT", panel, "TOPLEFT", L.x, -(Vorhaben.LIST_Y + i * Vorhaben.ROW_H - 1))
  end
  V.rows = {}
  for i = 1, Vorhaben.ROWS do V.rows[i] = buildRow(panel, i) end

  local cx = L.x + L.w / 2
  local empty = D.font(panel, "hand", 28, "ink")
  empty:SetPoint("TOP", panel, "TOPLEFT", cx, -(Vorhaben.LIST_Y + 87))
  empty:SetWidth(L.w - 40)
  empty:SetJustifyH("CENTER")
  empty:SetText(T.empty)
  V.emptyText = empty
  local esub = D.font(panel, "hand", 21, "sepia")
  esub:SetPoint("TOP", panel, "TOPLEFT", cx, -(Vorhaben.LIST_Y + 136))
  esub:SetWidth(L.w - 40)
  esub:SetJustifyH("CENTER")
  esub:SetText(T.emptySub)
  V.emptySub = esub
  local ehint = D.font(panel, "label", 12, "sepia")
  ehint:SetPoint("TOP", panel, "TOPLEFT", cx, -(Vorhaben.LIST_Y + 184))
  ehint:SetWidth(L.w - 40)
  ehint:SetJustifyH("CENTER")
  ehint:SetText(T.emptyHint)
  V.emptyHint = ehint

  local add = D.NewSticker(panel, T.add, function() Vorhaben.submit() end, { height = 30, size = 18, tip = T.addTip })
  add:SetPoint("TOPRIGHT", panel, "TOPLEFT", L.x + L.w, -LY.footY)
  V.add = add

  local vt = D.NewToggle(panel, { size = 14, gap = 14, value = V.view, items = {
      { key = "open", label = T.viewOpen, tip = T.viewOpenTip },
      { key = "archive", label = string.format(T.viewArchive, 0), tip = T.viewArchiveTip },
    },
    onChange = function(key) Vorhaben.setView(key) end })
  vt.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", L.x + 60, -(LY.footY + 8))
  V.viewToggle = vt
  local help = D.font(panel, "label", 12, "sepia")
  help:SetPoint("TOPLEFT", panel, "TOPLEFT", L.x, -(LY.kindY + 4))
  help:SetWidth(L.w)
  help:SetJustifyH("LEFT")
  help:SetText(T.archiveHelp)
  help:Hide()
  V.archiveHelp = help
end

local function buildRight(panel)
  local R, C = LY.R, LY.card
  local Theme = Journal.Theme
  V.headR = W.NewPageHead(panel, { side = "R", spread = true })
  V.headR:SetTexts("", T.head)
  local title = D.font(panel, "hand", 34, "ink")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", R.x, -LY.titleY)
  title:SetText(T.nextTitle)
  V.titleR = title
  local sub = D.font(panel, "label", 12, "sepia")
  sub:SetPoint("TOPLEFT", panel, "TOPLEFT", R.x, -LY.subY)
  sub:SetText(T.nextSub)
  V.subR = sub
  local progress = D.font(panel, "label", 14, "ink")
  progress:SetPoint("LEFT", panel, "TOPLEFT", R.x, -(LY.ctrlY + LY.slipH / 2))
  progress:SetWidth(150)
  progress:SetJustifyH("LEFT")
  progress:SetWordWrap(false)
  V.progress = progress
  V.barW = 180
  local bar = W.NewRect(panel, "ink", 0.14, "ARTWORK")
  bar:SetSize(V.barW, 4)
  bar:SetPoint("LEFT", panel, "TOPLEFT", R.x + 160, -(LY.ctrlY + LY.slipH / 2))
  V.bar = bar
  local fill = W.NewRect(panel, "red", 0.8, "OVERLAY")
  fill:SetSize(1, 4)
  fill:SetPoint("LEFT", bar, "LEFT", 0, 0)
  V.barFill = fill

  local card = slipFrame(panel, R.x, C.y, C.w, C.h)
  V.card = card
  local icon = card:CreateTexture(nil, "ARTWORK")
  icon:SetSize(28, 28)
  icon:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -16)
  local u0, u1, v0, v1
  if Theme and Theme.mapIconCoords then u0, u1, v0, v1 = Theme.mapIconCoords("current") end
  if Theme and Theme.HAS_MAP_ICONS and u0 and pcall(icon.SetTexture, icon, Theme.TEX.mapIcons) then
    icon:SetTexCoord(u0, u1, v0, v1)
  else
    icon:SetColorTexture(W.color("gold", 0.8))
    icon:SetSize(10, 10)
  end
  V.nextIcon = icon
  local ring = card:CreateTexture(nil, "OVERLAY")
  if Theme and Theme.HAS_DIARY and pcall(ring.SetTexture, ring, Theme.TEX.diaryCircle) then
    ring:SetVertexColor(W.color("red"))
  else
    ring:SetColorTexture(W.color("red", 0.12))
  end
  ring:SetSize(42, 38)
  ring:SetPoint("CENTER", icon, "CENTER", 0, 0)
  V.nextRing = ring
  local nt = D.font(card, "hand", 24, "ink")
  nt:SetPoint("TOPLEFT", card, "TOPLEFT", 58, -12)
  nt:SetWidth(C.w - 58 - 14)
  nt:SetJustifyH("LEFT")
  nt:SetWordWrap(true)
  if nt.SetMaxLines then nt:SetMaxLines(2) end
  V.nextText = nt
  -- up to 120 characters but only 2 lines: full text on hover
  local nh = CreateFrame("Frame", nil, card)
  nh:SetPoint("TOPLEFT", nt, "TOPLEFT", 0, 0)
  nh:SetSize(C.w - 58 - 14, 56)
  nh:SetScript("OnEnter", function(self)
    local nx = V.next
    if nx and type(nx.text) == "string" and nx.text ~= "" then W.tip(self, { nx.text }) end
  end)
  nh:SetScript("OnLeave", function(self) W.hideTip(self) end)
  V.nextHover = nh
  local pin = card:CreateTexture(nil, "ARTWORK")
  pin:SetSize(14, 14)
  pin:SetPoint("TOPLEFT", card, "TOPLEFT", 58, -70)
  if Theme and Theme.mapIconCoords then u0, u1, v0, v1 = Theme.mapIconCoords("gap") end
  if Theme and Theme.HAS_MAP_ICONS and u0 and pcall(pin.SetTexture, pin, Theme.TEX.mapIcons) then
    pin:SetTexCoord(u0, u1, v0, v1)
    pin:SetVertexColor(W.color("sepia"))
  else
    pin:SetColorTexture(W.color("sepia", 0.5))
    pin:SetSize(5, 5)
  end
  V.nextPin = pin
  local nz = D.font(card, "label", 12, "sepia")
  nz:SetPoint("TOPLEFT", card, "TOPLEFT", 76, -70)
  nz:SetWidth(C.w - 76 - 14)
  nz:SetJustifyH("LEFT")
  nz:SetWordWrap(false)
  V.nextZone = nz
  local nd = D.font(card, "label", 12, "red")
  nd:SetPoint("TOPLEFT", card, "TOPLEFT", 58, -88)
  nd:SetWidth(C.w - 58 - 14)
  nd:SetJustifyH("LEFT")
  nd:SetWordWrap(false)
  V.nextDist = nd
  local ne = D.font(card, "hand", 22, "sepia")
  ne:SetPoint("CENTER", card, "CENTER", 0, 0)
  ne:SetWidth(C.w - 40)
  ne:SetJustifyH("CENTER")
  V.nextEmpty = ne

  local head = D.NewSectionHead(panel, T.doneHead, { width = C.w })
  head:SetPoint("TOPLEFT", panel, "TOPLEFT", R.x, -LY.doneY)
  V.doneHead = head
  V.doneRows = {}
  local y0 = LY.doneY + 36
  for i = 1, Vorhaben.DONE_MAX do
    local r = CreateFrame("Frame", nil, panel)
    r:SetSize(C.w, LY.doneStep)
    r:SetPoint("TOPLEFT", panel, "TOPLEFT", R.x, -(y0 + (i - 1) * LY.doneStep))
    local t = D.mark(r, "tick", 18, "red", "OVERLAY")
    t:SetPoint("LEFT", r, "LEFT", 0, 2)
    local l = D.font(r, "hand", 18, "ink")
    l:SetPoint("LEFT", r, "LEFT", 24, 0)
    l:SetWidth(C.w - 24 - 70)
    l:SetJustifyH("LEFT")
    l:SetWordWrap(false)
    local dt = D.font(r, "label", 11, "sepia")
    dt:SetTextColor(W.color(Vorhaben.GREY))
    dt:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    dt:SetWidth(64)
    dt:SetJustifyH("RIGHT")
    r.tick, r.label, r.date = t, l, dt
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self) if self.data and self.data.text ~= "" then W.tip(self, { self.data.text }) end end)
    r:SetScript("OnLeave", function(self) W.hideTip(self) end)
    r:Hide()
    V.doneRows[i] = r
  end
  local de = D.font(panel, "label", 12, "sepia")
  de:SetPoint("TOPLEFT", panel, "TOPLEFT", R.x + 4, -(y0 + 4))
  de:SetText(T.doneEmpty)
  V.doneEmpty = de

  local hi = panel:CreateTexture(nil, "ARTWORK")
  hi:SetSize(24, 24)
  hi:SetPoint("TOPLEFT", panel, "TOPLEFT", R.x, -LY.hintY)
  if Theme and Theme.mapIconCoords then u0, u1, v0, v1 = Theme.mapIconCoords("flightpoint") end
  if Theme and Theme.HAS_MAP_ICONS and u0 and pcall(hi.SetTexture, hi, Theme.TEX.mapIcons) then
    hi:SetTexCoord(u0, u1, v0, v1)
  else
    hi:SetColorTexture(W.color("gold", 0.6))
  end
  V.hintIcon = hi
  local ht = D.font(panel, "label", 12, "sepia")
  ht:SetPoint("TOPLEFT", panel, "TOPLEFT", R.x + 32, -(LY.hintY + 2))
  ht:SetWidth(C.w - 32)
  ht:SetJustifyH("LEFT")
  ht:SetWordWrap(true)
  ht:SetText(T.hintText)
  V.hintText = ht
  local mini = D.NewCheck(panel, T.miniZettel, { size = 14, tip = T.miniZettelTip, onChange = function(on)
    local TT = Journal.TodoTracker
    if TT and type(TT.setShown) == "function" then TT.setShown(on and true or false) end
    Vorhaben.paintMini()
  end })
  mini:SetPoint("TOPLEFT", panel, "TOPLEFT", R.x, -LY.miniY)
  V.miniBox = mini
  local TT = Journal.TodoTracker
  if TT and TT.listeners and not V.miniListening then
    V.miniListening = true
    TT.listeners[#TT.listeners + 1] = Vorhaben.paintMini
  end
end

local function todoData()
  return Journal.TodoData
end

local function dataAvailable(kind)
  local TD = todoData()
  if not (TD and type(TD.available) == "function") then return false end
  local ok, r = pcall(TD.available, kind)
  return ok and r == true
end

local function dataDisabled()
  local TD = todoData()
  if not (TD and type(TD.disabled) == "function") then return false end
  local ok, r = pcall(TD.disabled)
  return ok and r == true
end

function Vorhaben.searchTip()
  local kind = V.kind
  if kind ~= "kill" and kind ~= "item" then return nil end
  local base = kind == "kill" and T.searchTipKill or T.searchTipItem
  local lines = { base[1], base[2] }
  if not dataAvailable(kind) then
    if dataDisabled() then
      lines[#lines + 1] = T.dataOff
    else
      local TD = todoData()
      if TD and type(TD.status) == "function" and type(TD.reasonText) == "function" then
        local okS, st = pcall(TD.status)
        local okR, why = pcall(TD.reasonText, okS and type(st) == "table" and st.reason or nil)
        if okR and type(why) == "string" then lines[#lines + 1] = string.format(T.dataMissing, why) end
      end
    end
  end
  return lines
end

local function dataName(kind, id)
  local TD = todoData()
  if not (TD and type(TD.name) == "function") then return nil end
  local ok, n = pcall(TD.name, kind, id)
  return (ok and type(n) == "string" and not isSecret(n)) and n or nil
end

local function cleanName(s)
  if isSecret(s) or type(s) ~= "string" then return nil end
  local P = plans()
  if P and type(P.cleanText) == "function" then
    local ok, c = pcall(P.cleanText, s)
    return (ok and type(c) == "string") and c or nil
  end
  local c = ns.Sanitize.field(s)
  return c ~= "" and c or nil
end

Vorhaben.KINDS = { free = true, place = true, kill = true, item = true }

local function layoutSlip(kind)
  if not V.edit then return end
  local fieldW
  if kind == "free" or kind == "place" then
    fieldW = LY.slipW - 8
  else
    fieldW = LY.slipW - LY.countW - 10
  end
  V.edit:SetWidth(fieldW)
  V.edit.hint:SetText((kind == "place" and T.hintPlace) or (kind == "kill" and T.hintKill) or (kind == "item" and T.hintItem) or T.hint)
  V.sep:ClearAllPoints()
  V.sep:SetPoint("LEFT", V.slip, "LEFT", fieldW + 6, 0)
  V.sep:SetShown(kind == "kill" or kind == "item")
  V.zoneDrop:Hide()
  local counted = kind == "kill" or kind == "item"
  V.countTimes:ClearAllPoints()
  V.countTimes:SetPoint("LEFT", V.slip, "LEFT", fieldW + 12, 0)
  V.countTimes:SetShown(counted)
  V.countBox:ClearAllPoints()
  V.countBox:SetPoint("LEFT", V.slip, "LEFT", fieldW + 24, 0)
  V.countBox:SetShown(counted)
  V.searchDrop:SetWidth(fieldW)
end

function Vorhaben.paintOptions()
  if not V.optStatus then return end
  if V.view == "archive" then
    V.pickBtn:Hide()
    V.takeBtn:Hide()
    W.setText(V.optStatus, "")
    return
  end
  local kind = V.kind or "free"
  local btn = (kind == "place" and V.pickBtn) or (kind == "kill" and V.takeBtn) or nil
  V.pickBtn:SetShown(kind == "place")
  V.takeBtn:SetShown(kind == "kill")
  local text
  if kind == "free" then
    text = ""
  elseif kind == "place" then
    local pl = V.place
    if pl then
      local name = zoneName(pl.mapID) or T.placeUnknown
      text = (num(pl.x) and num(pl.y)) and string.format(T.placeSetXY, name, floor(pl.x * 100 + 0.5), floor(pl.y * 100 + 0.5))
        or string.format(T.placeSet, name)
    else
      text = T.placeNone
    end
  else
    local tg = V.target
    if tg and tg.name then
      local name = shown(tg.name, 80) or ""
      text = string.format(T.targetSet, name)
      if num(tg.level) then text = text .. " · " .. string.format(T.targetLevel, floor(tg.level)) end
    elseif kind == "kill" then
      text = dataAvailable("kill") and "" or (dataDisabled() and T.noDataOff or T.noData)
    else
      text = dataAvailable("item") and T.itemHint or (dataDisabled() and T.noDataItemOff or T.noDataItem)
    end
  end
  local status = V.optStatus
  status:ClearAllPoints()
  local L = LY.L
  if btn then
    local okW, bw = pcall(btn.GetWidth, btn)
    bw = (okW and num(bw) and bw > 0) and bw or 180
    status:SetPoint("LEFT", btn, "RIGHT", 10, 0)
    status:SetWidth(max(40, L.w - bw - 10))
  else
    status:SetPoint("TOPLEFT", V.panel, "TOPLEFT", L.x, -(LY.optY + 7))
    status:SetWidth(L.w)
  end
  W.setText(status, text or "")
end

function Vorhaben.kind() return V.kind end

function Vorhaben.setKind(kind)
  if not Vorhaben.KINDS[kind] then return false end
  if kind ~= V.kind then V.target = nil end
  V.kind = kind
  if V.kindToggle then V.kindToggle:SetValue(kind) end
  if V.searchDrop and V.searchDrop:IsOpen() then V.searchDrop:Close() end
  layoutSlip(kind)
  Vorhaben.message("")
  Vorhaben.paintOptions()
  return true
end

local RANK = { elite = "rankElite", rareelite = "rankRare", rare = "rankRare", boss = "rankBoss", worldboss = "rankBoss" }

local function resultItem(r)
  if type(r) ~= "table" then return nil end
  local id = num(r.id)
  local name = cleanName(r.name)
  if not (id and id > 0 and name) then return nil end
  local label = shown(name, 80) or ""
  local rank = (not isSecret(r.rank) and type(r.rank) == "string") and r.rank or nil
  local rk = rank and RANK[string.lower(rank)] or nil
  if rk then
    label = label .. " (" .. T[rk] .. ")"
  elseif rank and rank ~= "" and string.lower(rank) ~= "normal" then
    label = label .. " (" .. (shown(rank, 24) or "") .. ")"
  end
  local zone = (type(r.zone) == "string" and shown(r.zone, 40)) or (num(r.zone) and zoneName(r.zone)) or nil
  if zone and zone ~= "" then label = label .. " · " .. zone end
  return { text = label, count = num(r.level), value = floor(id), rec = { id = floor(id), name = name, level = num(r.level) } }
end

function Vorhaben.search(text)
  local sd = V.searchDrop
  local kind = V.kind
  if not sd or (kind ~= "kill" and kind ~= "item") then return 0 end
  local TD = todoData()
  if isSecret(text) or type(text) ~= "string" or #text < Vorhaben.SEARCH_MIN or not (TD and type(TD.search) == "function") then
    if sd:IsOpen() then sd:Close() end
    return 0
  end
  local ok, res = pcall(TD.search, kind, text, Vorhaben.SEARCH_LIMIT)
  local items = {}
  if ok and type(res) == "table" then
    for i = 1, min(#res, Vorhaben.SEARCH_LIMIT) do
      local it = resultItem(res[i])
      if it then items[#items + 1] = it end
    end
  end
  if #items == 0 then
    if sd:IsOpen() then sd:Close() end
    return 0
  end
  sd:SetItems(items)
  if not sd:IsOpen() then sd:Open() end
  return #items
end

function Vorhaben.typed(text)
  if V.kind ~= "kill" and V.kind ~= "item" then return end
  if V.target and V.target.name ~= text then
    V.target = nil
    Vorhaben.paintOptions()
  end
  V.searchToken = (V.searchToken or 0) + 1
  local my = V.searchToken
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(Vorhaben.SEARCH_DELAY, function()
      if my ~= V.searchToken or not V.edit then return end
      W.call(Vorhaben.search, V.edit:GetText())
    end)
  else
    Vorhaben.search(text)
  end
end

local function setTarget(id, name, level)
  V.target = { id = id, name = name, level = level }
  setEditText(name)
  if V.searchDrop and V.searchDrop:IsOpen() then V.searchDrop:Close() end
  Vorhaben.message("")
  Vorhaben.paintOptions()
end

function Vorhaben.pickTarget(it)
  if type(it) ~= "table" or type(it.rec) ~= "table" then return false end
  local id = num(it.rec.id) or num(it.value)
  local name = cleanName(it.rec.name)
  if not name then return false end
  setTarget(id and floor(id) or nil, name, num(it.rec.level))
  return true
end

-- npcID from the target GUID (creatures only), name from UnitName (secret -> data list / #ID)
function Vorhaben.takeTarget()
  local okG, guid = pcall(UnitGUID, "target")
  if not okG or isSecret(guid) or type(guid) ~= "string" then
    Vorhaben.message(T.noTarget)
    return false
  end
  local kind, id = string.match(guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  id = tonumber(id)
  if not ((kind == "Creature" or kind == "Vehicle") and id and id > 0) then
    Vorhaben.message(T.noTarget)
    return false
  end
  local okN, name = pcall(UnitName, "target")
  name = (okN and cleanName(name)) or cleanName(dataName("kill", id)) or ("#" .. tostring(id))
  local okL, lvl = pcall(UnitLevel, "target")
  lvl = okL and num(lvl) or nil
  if V.kind ~= "kill" then Vorhaben.setKind("kill") end
  setTarget(id, name, (lvl and lvl > 0) and lvl or nil)
  return true
end

-- Shift+click on a link (ChatEdit_InsertLink / HandleModifiedItemClick), only for "item" with focus in the search field
local lastLink, lastLinkT
function Vorhaben.onInsertLink(link)
  if V.kind ~= "item" or not (V.edit and V.edit.HasFocus and V.edit:HasFocus()) then return false end
  if isSecret(link) or type(link) ~= "string" then return false end
  local t = type(GetTime) == "function" and GetTime() or 0
  if link == lastLink and t == lastLinkT then return false end -- the same click arrived through both hooks
  lastLink, lastLinkT = link, t
  local Pt = ns.Patterns
  local id, name
  if Pt and Pt.itemLink then
    local a, _, _, d = Pt.itemLink(link)
    id, name = a, d
  end
  if not id then
    Vorhaben.message(T.errLink)
    return false
  end
  name = cleanName(name) or cleanName(dataName("item", id)) or ("#" .. tostring(id))
  setTarget(id, name, nil)
  return true
end

local linksHooked = false
local function hookLinks()
  if linksHooked or type(hooksecurefunc) ~= "function" then return end
  linksHooked = true
  if type(ChatEdit_InsertLink) == "function" then
    hooksecurefunc("ChatEdit_InsertLink", function(link) W.call(Vorhaben.onInsertLink, link) end)
  end
  if type(HandleModifiedItemClick) == "function" then
    hooksecurefunc("HandleModifiedItemClick", function(link)
      if type(IsModifiedClick) == "function" and not IsModifiedClick("CHATLINK") then return end
      W.call(Vorhaben.onInsertLink, link)
    end)
  end
end

local function in01(x, y)
  return num(x) ~= nil and num(y) ~= nil and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

function Vorhaben.pointToMap(vx, vy, scene)
  if type(scene) ~= "table" or not in01(vx, vy) then return nil end
  if scene.mode == "zone" and num(scene.zoneID) then return scene.zoneID, vx, vy end
  if scene.mode == "continent" and num(scene.contID) then
    local Vw, G = Journal.View, Journal.Geo
    if Vw and Vw.zoneInfoAt and G and G.affine then
      local okZ, z = pcall(Vw.zoneInfoAt, scene.contID, vx, vy)
      if okZ and type(z) == "table" and num(z.id) then
        local okA, a, b, c, d = pcall(G.affine, z.id, scene.contID)
        if okA and num(a) and num(b) and num(c) and num(d) and b ~= 0 and d ~= 0 then
          local zx, zy = (vx - a) / b, (vy - c) / d
          if in01(zx, zy) then return z.id, zx, zy end
        end
      end
    end
    return scene.contID, vx, vy
  end
  if scene.mode == "map" and num(scene.mapID) then return scene.mapID, vx, vy end
  return nil
end

local function frameState()
  local F = Journal.Frame
  return F, F and F.state
end

Vorhaben.PICK = { w = 600, h = 500, pad = 22, mapY = 104, mapH = 320, zoneW = 190 }

local function hidePick()
  local win = V.pickWin
  if not win then return end
  V.pickHiding = true
  win:Hide()
  V.pickHiding = false
end

local function pickStatus(text, red)
  local win = V.pickWin
  if not win then return end
  win.status:SetTextColor(W.color(red and "red" or "sepia"))
  W.setText(win.status, text or "")
end

local function placeText(pl)
  if not pl then return T.placeNone end
  local name = zoneName(pl.mapID) or T.placeUnknown
  if num(pl.x) and num(pl.y) then
    return string.format(T.placeSetXY, name, floor(pl.x * 100 + 0.5), floor(pl.y * 100 + 0.5))
  end
  return string.format(T.placeSet, name)
end

local function pickZoneItems(active)
  local out = {}
  for _, it in ipairs(Vorhaben.zoneItems()) do
    if type(it.value) == "number" then out[#out + 1] = { text = it.text, value = it.value, active = it.value == active } end
  end
  return out
end

local function pickStartZone()
  if V.place and num(V.place.mapID) then return V.place.mapID end
  if num(V.zone) then return V.zone end
  local items = pickZoneItems(nil)
  if items[1] then return items[1].value end
  local Zone = ns.Zone
  if Zone and type(Zone.raw) == "function" then
    local ok, mapID = pcall(Zone.raw)
    if ok and num(mapID) and mapID > 0 then return floor(mapID) end
  end
  return nil
end

local function pickScene(zoneID)
  local scene = { mode = "zone", zoneID = zoneID, key = "todo-pick:" .. tostring(zoneID), focus = { x0 = 0, x1 = 1, y0 = 0, y1 = 1 },
    project = function(mapID, x, y) if mapID == zoneID then return x, y end return nil end, pins = {} }
  local Zone = ns.Zone
  if Zone and type(Zone.raw) == "function" then
    local ok, mapID, px, py = pcall(Zone.raw)
    if ok and mapID == zoneID and in01(px, py) then scene.current = { vx = px, vy = py } end
    -- the arrow follows the player while the picker is open (Map.liveSync): vx, vy, facing | false = elsewhere | nil
    scene.live = function()
      local okL, mapL, lx, ly = pcall(Zone.raw)
      if not okL or not num(mapL) then return nil end
      if mapL ~= zoneID then return false end
      if not in01(lx, ly) then return nil end
      local Vw = Journal.View
      return lx, ly, Vw and Vw.facing and Vw.facing() or nil
    end
  end
  local pl = V.pending
  if pl and pl.mapID == zoneID then
    scene.pins[1] = { id = "todo-pick", vx = pl.x, vy = pl.y, title = shown(V.pickName, 120) or T.pickPinTitle, hint = T.pickPinHint,
      color = Vorhaben.PIN_COLOR }
  end
  return scene
end

local function pickArt(zoneID)
  local Vw = Journal.View
  if not Vw then return nil, 1.5 end
  local okA, art = pcall(Vw.zoneArt, zoneID)
  if okA and type(art) == "table" then return art, nil end
  local okR, aspect = pcall(Vw.mapAspect, zoneID)
  return nil, (okR and num(aspect)) or 1.5
end

local function drawPick(keep)
  local win, Map = V.pickWin, Journal.Map
  if not (win and win.map and Map and num(V.pickZone)) then return false end
  local scene = pickScene(V.pickZone)
  V.pickScene = scene
  local art, aspect = pickArt(V.pickZone)
  local Vw = Journal.View
  local color = Vw and Vw.peek and Vw.peek("mapColor") or nil
  local ok = pcall(Map.render, win.map, scene, { art = art, aspect = aspect, clip = { x0 = 0, y0 = 0, x1 = 1, y1 = 1 },
    color = color, showKills = false, pad = 10, keepView = keep and true or false })
  win.noArt:SetShown(art == nil)
  return ok
end

local function paintPick()
  local win = V.pickWin
  if not win then return end
  win.ok:SetEnabled(V.pending ~= nil)
  if V.pending then pickStatus(placeText(V.pending)) else pickStatus(T.placeNone) end
end

function Vorhaben.pickZone(zoneID)
  zoneID = num(zoneID)
  if not zoneID or zoneID <= 0 then return false end
  zoneID = floor(zoneID)
  V.pickZone = zoneID
  if V.pending and V.pending.mapID ~= zoneID then V.pending = nil end
  local win = V.pickWin
  if win then
    win.zone:SetText(zoneName(zoneID) or T.placeUnknown)
    win.zone:SetItems(pickZoneItems(zoneID))
  end
  drawPick(false)
  paintPick()
  return true
end

local function buildPick()
  if V.pickWin then return V.pickWin end
  local panel = V.panel
  if not panel then return nil end
  local PK, Theme = Vorhaben.PICK, Journal.Theme
  local F = Journal.Frame
  local spreadW, spreadH = (F and F.SPREAD_W) or 1076, (F and F.SPREAD_H) or 666
  local win = CreateFrame("Frame", nil, panel)
  win:SetSize(PK.w, PK.h)
  win:SetPoint("TOPLEFT", panel, "TOPLEFT", floor((spreadW - PK.w) / 2), -floor((spreadH - PK.h) / 2))
  win:SetFrameLevel((panel:GetFrameLevel() or 1) + 60)
  win:EnableMouse(true)
  if win.EnableMouseWheel then win:EnableMouseWheel(true) end
  win:SetScript("OnMouseWheel", function() end) -- do not trigger page flipping underneath
  local shadow = W.NewRect(win, "ink", 0.35, "BACKGROUND")
  shadow:SetDrawLayer("BACKGROUND", -8)
  shadow:SetPoint("TOPLEFT", win, "TOPLEFT", 6, -8)
  shadow:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 8, -10)
  local paper = win:CreateTexture(nil, "BACKGROUND", nil, -6)
  paper:SetAllPoints(win)
  local tex = Theme and Theme.paper and Theme.paper((F and F.HOME) or "reise")
  if tex and pcall(paper.SetTexture, paper, tex) then
    paper:SetTexCoord(0.18, 0.82, 0.16, 0.84)
  else
    paper:SetColorTexture(W.color("parchment", 1))
  end
  win.paper = paper
  local function rule(inset, alpha, thick)
    local e = {}
    for i = 1, 4 do e[i] = W.NewRect(win, "ink", alpha, "BORDER") end
    e[1]:SetPoint("TOPLEFT", win, "TOPLEFT", inset, -inset) e[1]:SetPoint("TOPRIGHT", win, "TOPRIGHT", -inset, -inset) e[1]:SetHeight(thick)
    e[2]:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", inset, inset) e[2]:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -inset, inset) e[2]:SetHeight(thick)
    e[3]:SetPoint("TOPLEFT", win, "TOPLEFT", inset, -inset) e[3]:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", inset, inset) e[3]:SetWidth(thick)
    e[4]:SetPoint("TOPRIGHT", win, "TOPRIGHT", -inset, -inset) e[4]:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -inset, inset) e[4]:SetWidth(thick)
    return e
  end
  win.rules = { rule(0, 0.7, 2), rule(6, 0.3, 1) }

  local P = PK.pad
  local title = D.font(win, "hand", 30, "ink")
  title:SetPoint("TOPLEFT", win, "TOPLEFT", P, -16)
  title:SetText(T.pickTitle)
  win.title = title
  local forName = D.font(win, "label", 12, "sepia")
  forName:SetPoint("TOPLEFT", win, "TOPLEFT", P, -50)
  forName:SetWidth(PK.w - 2 * P - PK.zoneW - 70)
  forName:SetJustifyH("LEFT")
  forName:SetWordWrap(false)
  win.forName = forName
  local how = D.font(win, "text", 15, "ink")
  how:SetPoint("TOPLEFT", win, "TOPLEFT", P, -70)
  how:SetWidth(PK.w - 2 * P)
  how:SetJustifyH("LEFT")
  how:SetText(T.pickHint)
  win.how = how
  local sub = D.font(win, "label", 12, "sepia")
  sub:SetPoint("TOPLEFT", win, "TOPLEFT", P, -88)
  sub:SetWidth(PK.w - 2 * P)
  sub:SetJustifyH("LEFT")
  sub:SetText(T.pickSub)
  win.sub = sub

  local Map = Journal.Map
  if Map and type(Map.create) == "function" then
    local mw = PK.w - 2 * P
    local okM, m = pcall(Map.create, win, P, PK.mapY, mw, PK.mapH, { noteMax = 0 })
    if okM and type(m) == "table" then
      m.onPoint = function(vx, vy) W.call(Vorhaben.pickAt, vx, vy, V.pickScene) end
      win.map = m
      local fr = {}
      for i = 1, 4 do fr[i] = W.NewRect(win, "sepia", 0.6, "BORDER") end
      fr[1]:SetPoint("TOPLEFT", win, "TOPLEFT", P - 1, -(PK.mapY - 1)) fr[1]:SetSize(mw + 2, 1)
      fr[2]:SetPoint("TOPLEFT", win, "TOPLEFT", P - 1, -(PK.mapY + PK.mapH)) fr[2]:SetSize(mw + 2, 1)
      fr[3]:SetPoint("TOPLEFT", win, "TOPLEFT", P - 1, -(PK.mapY - 1)) fr[3]:SetSize(1, PK.mapH + 2)
      fr[4]:SetPoint("TOPLEFT", win, "TOPLEFT", P + mw, -(PK.mapY - 1)) fr[4]:SetSize(1, PK.mapH + 2)
      win.mapFrame = fr
    end
  end
  local noArt = D.font(win, "label", 12, "sepia")
  noArt:SetPoint("TOP", win, "TOPLEFT", PK.w / 2, -(PK.mapY + PK.mapH - 20))
  noArt:SetText(T.pickNoArt)
  noArt:Hide()
  win.noArt = noArt

  local zl = D.font(win, "label", 12, "sepia")
  zl:SetText(T.pickZone)
  win.zoneLabel = zl
  local zd = D.NewDropdown(win, { width = PK.zoneW, size = 13, text = "", items = {}, rows = 10, popupWidth = 230, tip = T.pickZoneTip,
    onPick = function(it) Vorhaben.pickZone(it.value) end })
  zd:SetPoint("TOPRIGHT", win, "TOPRIGHT", -P, -44)
  zl:SetPoint("RIGHT", zd, "LEFT", -8, 0)
  win.zone = zd

  local status = D.font(win, "label", 13, "sepia")
  status:SetPoint("TOPLEFT", win, "TOPLEFT", P, -(PK.mapY + PK.mapH + 18))
  status:SetWidth(PK.w - 2 * P - 250)
  status:SetJustifyH("LEFT")
  status:SetWordWrap(false)
  win.status = status
  local ok = D.NewSticker(win, T.pickOk, function() Vorhaben.confirmPick() end, { height = 34, size = 19, tilt = -1.5,
    tip = T.pickOkTip, disabledTip = T.pickOkOff })
  ok:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -P, 14)
  win.ok = ok
  local cancel = D.NewOpenLink(win, T.pickCancel, function() Vorhaben.cancelPick() end, { size = 13, tip = { T.pickCancel, T.pickEsc } })
  cancel:SetPoint("RIGHT", ok, "LEFT", -18, 0)
  win.cancel = cancel

  D.escKeys(win, function() Vorhaben.cancelPick() end)
  win:Hide()
  win:HookScript("OnHide", function()
    if V.picking and not V.pickHiding then
      V.picking, V.pending = false, nil
    end
  end)
  V.pickWin = win
  return win
end

function Vorhaben.pickActive()
  return V.picking == true
end

function Vorhaben.startPick()
  if not V.panel then
    Vorhaben.message(T.errUnavailable)
    return false, "nicht-verfuegbar"
  end
  if V.searchDrop and V.searchDrop:IsOpen() then V.searchDrop:Close() end
  if V.kind ~= "place" then Vorhaben.setKind("place") end
  local name = cleanName(V.edit and V.edit:GetText() or "")
  if not name then
    Vorhaben.message(T.errName)
    if V.edit and V.edit.SetFocus then V.edit:SetFocus() end
    return false, "name"
  end
  local zone = pickStartZone()
  if not zone then
    Vorhaben.message(T.errNoZone)
    return false, "zone"
  end
  local win = buildPick()
  if not win then
    Vorhaben.message(T.errUnavailable)
    return false, "nicht-verfuegbar"
  end
  if V.edit and V.edit.ClearFocus then V.edit:ClearFocus() end
  Vorhaben.message("")
  V.pickName = name
  W.setText(win.forName, string.format(T.pickFor, shown(name, 160) or ""))
  V.pending = V.place and { mapID = V.place.mapID, x = V.place.x, y = V.place.y } or nil
  V.picking = true
  win:Show()
  Vorhaben.pickZone(zone)
  return true
end

function Vorhaben.cancelPick()
  local was = V.picking == true
  V.picking, V.pending = false, nil
  hidePick()
  return was
end

function Vorhaben.pickAt(vx, vy, scene)
  if not V.picking then return false end
  local mapID, x, y = Vorhaben.pointToMap(vx, vy, scene or V.pickScene)
  if not mapID then
    pickStatus(T.pickMiss, true)
    return true
  end
  V.pending = { mapID = floor(mapID), x = x, y = y }
  if V.pickZone ~= V.pending.mapID then
    Vorhaben.pickZone(V.pending.mapID)
  else
    drawPick(true)
    paintPick()
  end
  return true
end

function Vorhaben.confirmPick()
  if not V.picking then return false, "kein-fenster" end
  if not V.pending then
    pickStatus(T.pickNone, true)
    return false, "ort"
  end
  V.place = V.pending
  V.picking, V.pending = false, nil
  hidePick()
  if V.kind ~= "place" then Vorhaben.setKind("place") end
  Vorhaben.paintOptions()
  return Vorhaben.submit()
end

function Vorhaben.mapPins(scene)
  local out = {}
  if type(scene) ~= "table" or type(scene.project) ~= "function" then return out end
  for _, p in ipairs(allPlans("open")) do
    if kindOf(p) == "place" and num(p.mapID) and num(p.x) and num(p.y) then
      local ok, vx, vy = pcall(scene.project, p.mapID, p.x, p.y)
      if ok and num(vx) and num(vy) then
        out[#out + 1] = { id = "todo:" .. tostring(p.id), vx = vx, vy = vy, title = shown(p.text, 120) or "", hint = T.pinHint,
          color = Vorhaben.PIN_COLOR }
      end
    end
  end
  return out
end

local function placeSig()
  local parts = {}
  for _, p in ipairs(allPlans("open")) do
    if kindOf(p) == "place" then parts[#parts + 1] = tostring(p.id) end
  end
  return table.concat(parts, ",")
end

local function refreshMap()
  local F, J = frameState()
  if F and J and J.frame and J.frame.IsShown and J.frame:IsShown() and J.page == F.HOME and J.model and not Vorhaben.isOpen()
    and type(F.refresh) == "function" then
    V.pinsDirty = false
    pcall(F.refresh, true)
    return true
  end
  return false
end

function Vorhaben.plansChanged()
  if Vorhaben.isOpen() then Vorhaben.refresh() end
  local sig = placeSig()
  if sig ~= V.pinSig then
    V.pinSig = sig
    V.pinsDirty = true
    refreshMap()
  end
end

do
  local P = ns.Plans
  if P and type(P.onChange) == "function" then P.onChange(function() W.call(Vorhaben.plansChanged) end) end
end

function Vorhaben.open()
  if not V.panel then return false end
  V.open = true
  V.page = 1
  V.panel:Show()
  Vorhaben.cancelPick()
  if V.zoneDrop then V.zoneDrop:SetItems(Vorhaben.zoneItems()) end
  layoutSlip(V.kind or "free")
  V.doneAtOpen = {}
  for _, p in ipairs(allPlans("done")) do V.doneAtOpen[p.id] = true end
  Vorhaben.setView("open")
  if Vorhaben.onChange then pcall(Vorhaben.onChange, true) end
  return true
end

function Vorhaben.close()
  if not V.panel then return false end
  V.open = false
  if V.edit and V.edit.ClearFocus then V.edit:ClearFocus() end
  if V.zoneDrop and V.zoneDrop:IsOpen() then V.zoneDrop:Close() end
  if V.searchDrop and V.searchDrop:IsOpen() then V.searchDrop:Close() end
  local was = V.panel:IsShown()
  V.panel:Hide()
  if was and Vorhaben.onChange then pcall(Vorhaben.onChange, false) end
  if was and V.pinsDirty then refreshMap() end
  return true
end

function Vorhaben.isOpen()
  return V.open == true and V.panel ~= nil and V.panel:IsShown() == true
end

function Vorhaben.toggle()
  if Vorhaben.isOpen() then return Vorhaben.close() end
  return Vorhaben.open()
end

function Vorhaben.build(over)
  if V.panel and V.over == over then return V end
  local Theme = Journal.Theme
  local F = Journal.Frame
  V.over = over

  local spreadW, spreadH = (F and F.SPREAD_W) or 1076, (F and F.SPREAD_H) or 666
  local panel = CreateFrame("Frame", nil, over)
  panel:SetSize(spreadW, spreadH)
  panel:SetPoint("TOPLEFT", over, "TOPLEFT", 0, 0)
  panel:SetFrameLevel((over:GetFrameLevel() or 1) + 16)
  panel:EnableMouse(true)
  if panel.EnableMouseWheel then panel:EnableMouseWheel(true) end
  panel:SetScript("OnMouseWheel", function(_, delta) W.call(step, (tonumber(delta) or 0) > 0 and -1 or 1) end)
  local texL, texR
  if Theme and Theme.paper then texL, texR = Theme.paper((F and F.HOME) or "reise") end
  local rim = (F and F.RIM) or 30
  local ppx, ppy, ppw, pph = rim, rim, spreadW, spreadH
  if F and F.paperRect then ppx, ppy, ppw, pph = F.paperRect() end
  local pl = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
  local pr = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
  if not (texL and pcall(pl.SetTexture, pl, texL) and pcall(pr.SetTexture, pr, texR)) then
    pl:SetColorTexture(W.color("parchment", 1))
    pr:SetColorTexture(W.color("parchment", 1))
  end
  pl:SetPoint("TOPLEFT", panel, "TOPLEFT", ppx - rim, rim - ppy)
  pl:SetSize(ppw / 2, pph)
  pr:SetPoint("TOPLEFT", panel, "TOPLEFT", spreadW / 2, rim - ppy)
  pr:SetSize(ppw / 2, pph)
  V.paperL, V.paperR = pl, pr
  V.panel = panel

  -- no own Esc catcher: To Do is the first sub-bookmark of the tab Pläne, so Esc closes the book as on every first sub-page
  buildLeft(panel)
  buildRight(panel)
  layoutSlip(V.kind or "free")
  Vorhaben.paintOptions()
  hookLinks()

  panel:Hide()
  return V
end
