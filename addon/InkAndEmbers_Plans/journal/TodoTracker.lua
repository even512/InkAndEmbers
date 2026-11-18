-- On-screen to-do note: a small own window (unprotected, no secure template) showing the open to-dos: icon per kind, text
-- (wraps to two lines), progress "4/10" or distance. Collapsible; styles "pad" (note pad) and "plain".
local _, ns = ...

local Journal = ns.Journal
local W = Journal and Journal.Widgets
local D = W and W.Diary
local Slip = W and W.Slip -- note slip building blocks (core, journal/widgets/Slip.lua; shared with the quick note)
if not (W and D and Slip) then return end
local Theme = Journal.Theme

local floor, max, min = math.floor, math.max, math.min

local TodoTracker = {}
Journal.TodoTracker = TodoTracker

TodoTracker.NAME = "EveNChronicleTodoTracker"
TodoTracker.ROWS_MAX = 8      -- to-dos shown (the material lines of a shopping list come on top, see cap)
TodoTracker.ROWS_POOL = 24    -- row frames built
TodoTracker.SUB_INDENT = 12
TodoTracker.SUB_MAX = 5
TodoTracker.SUB_MAX_WERK = 3  -- material lines under a work order (chain and next step come on top)
TodoTracker.LINGER = 4
TodoTracker.DIST_EVERY = 1
TodoTracker.TEXT_BYTES = 400
TodoTracker.SIZE = { minW = 180, minH = 110, maxW = 480, maxH = 560 }
TodoTracker.STYLES = { "pad", "plain" }
TodoTracker.OPEN_MODES = { "always", "hover", "click", "auto" }
TodoTracker.ANIM = 0.24
TodoTracker.HOVER_GRACE = 0.12
TodoTracker.GROW_MODES = { "down", "up" }
TodoTracker.BOOK_W, TodoTracker.BOOK_H = 18, 16
TodoTracker.CLOSE_W = Slip.CLOSE_W
TodoTracker.DEFAULTS = { shown = false, style = "pad", locked = false, combatHide = false, hideEmpty = true, marks = true, w = 250, h = 250,
  open = "always", grow = "down", autoShow = true, dismissed = false, dock = false, dockSide = "below", dockCollapsed = false }
TodoTracker.KINDS = { free = true, place = true, kill = true, item = true }

TodoTracker.TEXT = ns.Locale.ns("TodoTracker", {
  title = "To Do",
  count = "%d offen",
  more = "+%d weitere",
  empty = "Keine offenen To Dos.",
  styleLabel = "Notizzettel-Stil",
  style = { pad = "Notizblock", plain = "Schlicht" },
  section = "Notizzettel",
  optShown = "Mini-To-Do-Zettel",
  optShownTip = { "Mini-To-Do-Zettel", "Zeigt einen kleinen Notizzettel mit Euren offenen To Dos am Bildschirmrand." },
  optLocked = "Notizzettel sperren",
  optCombat = "Im Kampf ausblenden",
  optEmpty = "Ausblenden, wenn nichts offen ist",
  optAuto = "Zettel automatisch zeigen, wenn To Dos offen sind",
  lock = "Notizzettel sperren",
  unlock = "Notizzettel entsperren",
  lockHint = "Gesperrt: nicht verschiebbar, Größe fest.",
  unlockHint = "Ziehen am Kopf verschiebt, der Griff unten rechts ändert die Größe.",
  rowHint = "Klick: Reisejournal auf der To-Do-Seite öffnen",
  grip = "Größe ändern",
  on = "Notizzettel eingeblendet.",
  onEmpty = "Notizzettel eingeschaltet. Er erscheint, sobald Ihr offene To Dos habt.",
  off = "Notizzettel ausgeblendet. /chronik todo blendet ihn wieder ein.",
  reset = "Notizzettel: Lage und Größe zurückgesetzt.",
  notReady = "Der Notizzettel wartet noch auf Euren Charakter.",
  usage = "/chronik todo [an|aus|reset] - Notizzettel ein-/ausblenden bzw. Lage und Größe zurücksetzen",
  openLabel = "Öffnen",
  openModes = { always = "Immer offen", hover = "Beim Überfahren", click = "Per Klick",
    auto = "Automatisch, sobald To Dos drauf stehen" },
  toggleOpen = "Zettel aufklappen",
  toggleClose = "Zettel zuklappen",
  toggleHint = "Ein Klick auf den Kopf klappt den Zettel auf und zu.",
  growLabel = "Aufklappen nach",
  grow = { down = "Unten", up = "Oben" },
  growDesc = "Unten: der Zettel rollt unter dem Kopf auf. Oben: der Kopf bleibt stehen, der Zettel rollt über ihm auf.",
  close = "Notizzettel ausblenden",
  closeHint = "/chronik todo blendet ihn wieder ein.",
  openBook = "To Do im Buch öffnen",
  openBookHint = "Öffnet das Reisejournal auf der To-Do-Seite.",
  kind = { free = "Freies Ziel", place = "Ort erreichen", kill = "Gegner töten", item = "Gegenstände finden" },
  shopKind = "Einkaufszettel",
  shopHint = "Klick öffnet den Einkaufszettel.",
  werkKind = "Werkauftrag",
  werkHint = "Klick zeigt, wo der Werkauftrag weitergeht.",
  stage1 = "Planen", stage2 = "Einkaufen", stage3 = "Herstellen",
  chainCur = "[%d %s]",
  nextBuy = "Weiter im Auktionshaus: %s× %s fehlt",
  nextBuyAny = "Weiter im Auktionshaus: Material fehlt",
  nextMail = "Gekauftes liegt in der Post: am Briefkasten abholen",
  nextCraft = "Alles da – öffnet das Berufsfenster %s",
  nextCraftAny = "Alles da – öffnet das Berufsfenster",
  nextTrainer = "Zum Lehrer: %s lernen",
  nextTrainerAny = "Zum Lehrer: neues Rezept lernen",
  nextDone = "Fertig",
  whereBuy = "Der Einkaufszettel liegt am Auktionshaus: dort die fehlenden Materialien kaufen.",
  whereMail = "Gekauftes liegt in der Post. Am Briefkasten abholen, dann zur Werkbank.",
  whereCraft = "Alles da. Öffnet das Berufsfenster %s, dort steht der Werkauftrag in der Leiste.",
  whereCraftAny = "Alles da. Öffnet das Berufsfenster, dort steht der Werkauftrag in der Leiste.",
  whereTrainer = "Zum Lehrer: %s lernen. Die Leiste am Berufsfenster setzt den Wegpunkt.",
  whereTrainerAny = "Zum Lehrer: neues Rezept lernen. Die Leiste am Berufsfenster setzt den Wegpunkt.",
  optDock = "To Dos am Questtracker andocken",
  dockSideLabel = "Lage am Questtracker",
  dockSide = { below = "Unter den Quests", above = "Über den Quests" },
  dockCollapse = "To Dos einklappen",
  dockExpand = "To Dos aufklappen",
  dockToggleHint = "Klappt auch mit dem Questtracker ein und aus. Klick auf eine Zeile öffnet das Reisejournal auf der To-Do-Seite.",
  dockHeadCount = "%s (%d)",
  dockedSlash = "Die To Dos hängen am Questtracker. Abdocken: Optionen -> AddOns -> Ink & Embers -> „To Dos am Questtracker andocken“.",
  questsSlash = "Die To Dos stehen im Quest-Tracker von Ink & Embers. Mini-Zettel zurück: /chronik quests aus.",
})
local T = TodoTracker.TEXT

TodoTracker.METRICS = Slip.METRICS
TodoTracker.PLAIN = Slip.PLAIN
TodoTracker.PAD = Slip.PAD
TodoTracker.RULES_MAX = 24
TodoTracker.PAD_SLICE = Slip.PAD_SLICE

local st = { rows = {}, prevOrder = {}, lingering = {}, ticker = nil, tickEvery = nil, inCombat = false,
  memory = {}, shownList = {}, hover = false, clickOpen = false }
-- Collapse state: st.expanded = target (nil = undecided), st.shape = "open" | "closed" (how the content is laid out right now;
-- while rolling up it stays "open" until the motion ends), st.anim = running motion { from, to, t, closing },
-- st.collapsedH = height of the collapsed note
TodoTracker.state = st

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function say(msg)
  if ns.Core and ns.Core.print then ns.Core.print(msg) end
end

local function now() return type(GetTime) == "function" and GetTime() or 0 end

local function inCombat()
  if st.inCombat then return true end
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local POINTS = { TOPLEFT = true }

local function charStore(create)
  local Store = ns.Store
  local char = Store and Store.char and Store.char()
  if type(char) ~= "table" then return nil end
  local t = char.todoTracker
  if type(t) ~= "table" or isSecret(t) then
    if not create then return nil end
    t = {}
    char.todoTracker = t
  end
  return t
end

local function validStyle(v) return v == "pad" or v == "plain" end

local function validOpen(v)
  for _, m in ipairs(TodoTracker.OPEN_MODES) do
    if v == m then return true end
  end
  return false
end

local function validGrow(v) return v == "down" or v == "up" end

local function clampSize(w, h)
  local S = TodoTracker.SIZE
  w, h = num(w), num(h)
  w = w and max(S.minW, min(S.maxW, floor(w + 0.5))) or TodoTracker.DEFAULTS.w
  h = h and max(S.minH, min(S.maxH, floor(h + 0.5))) or TodoTracker.DEFAULTS.h
  return w, h
end

local screenSize = Slip.screenSize

TodoTracker.clampPos = Slip.clampPos

function TodoTracker.settings()
  local raw = charStore(false) or st.memory
  local d = TodoTracker.DEFAULTS
  local out = {}
  for _, k in ipairs({ "shown", "locked", "combatHide", "hideEmpty", "marks", "autoShow", "dismissed", "dock", "dockCollapsed" }) do
    local v = raw[k]
    if type(v) == "boolean" and not isSecret(v) then out[k] = v else out[k] = d[k] end
  end
  -- migration: whoever had switched the note off before "dismissed" existed counts as having closed it by hand (no forced pop-up
  -- at the first login after the update; it opens at the next new to-do). A character that never touched it (no key) is not dismissed.
  if type(raw.dismissed) ~= "boolean" or isSecret(raw.dismissed) then out.dismissed = raw.shown == false end
  out.style = validStyle(raw.style) and raw.style or d.style
  out.open = validOpen(raw.open) and raw.open or d.open
  out.grow = validGrow(raw.grow) and raw.grow or d.grow
  out.dockSide = (raw.dockSide == "below" or raw.dockSide == "above") and raw.dockSide or d.dockSide
  out.w, out.h = clampSize(raw.w, raw.h)
  local p = raw.pos
  if type(p) == "table" and not isSecret(p) and POINTS[p.point] and num(p.x) and num(p.y) and math.abs(p.x) <= 10000
    and math.abs(p.y) <= 10000 then
    out.pos = { point = p.point, x = p.x, y = p.y }
  end
  return out
end

function TodoTracker.set(key, value)
  local t = charStore(true) or st.memory
  if key == "shown" or key == "locked" or key == "combatHide" or key == "hideEmpty" or key == "marks" or key == "autoShow"
    or key == "dismissed" or key == "dock" or key == "dockCollapsed" then
    if type(value) ~= "boolean" then return false end
    t[key] = value
  elseif key == "style" then
    if not validStyle(value) then return false end
    t.style = value
  elseif key == "open" then
    if not validOpen(value) then return false end
    t.open = value
  elseif key == "grow" then
    if not validGrow(value) then return false end
    t.grow = value
  elseif key == "dockSide" then
    if value ~= "below" and value ~= "above" then return false end
    t.dockSide = value
  elseif key == "size" then
    if type(value) ~= "table" then return false end
    t.w, t.h = clampSize(value.w, value.h)
  elseif key == "pos" then
    if value == nil then
      t.pos = nil
      return true
    end
    if type(value) ~= "table" or not POINTS[value.point] or not num(value.x) or not num(value.y) then return false end
    t.pos = { point = value.point, x = floor(value.x + 0.5), y = floor(value.y + 0.5) }
  else
    return false
  end
  return true
end

function TodoTracker.formatDist(m)
  m = num(m)
  if not m or m < 0 then return nil end
  if m < 1000 then
    local r = m < 100 and floor(m + 0.5) or floor(m / 10 + 0.5) * 10
    if r >= 1000 then return "1" .. ns.Locale.get("Fmt", "decimal") .. "0 km" end
    return tostring(r) .. " m"
  end
  local km = m / 1000
  if km >= 100 then return tostring(floor(km + 0.5)) .. " km" end
  return (string.format("%.1f", km):gsub("%.", ns.Locale.get("Fmt", "decimal"))) .. " km"
end

local function shown(s, n)
  if isSecret(s) or type(s) ~= "string" then return nil end
  return ns.Sanitize.display(s, n or TodoTracker.TEXT_BYTES)
end

local function extraOf(p)
  local prog = shown(p.progress, 24)
  if not prog then
    local need, have = num(p.need), num(p.have)
    if need and have and need > 0 then prog = string.format("%d/%d", floor(min(have, need)), floor(need)) end
  end
  if prog then return prog, false end
  local dist = TodoTracker.formatDist(p.dist)
  if dist then return dist, true end
  return nil, false
end

local function rowOf(p, done)
  local kind = (type(p.kind) == "string" and TodoTracker.KINDS[p.kind]) and p.kind or "free"
  local text = shown(p.text) or ""
  local extra, isDist = extraOf(p)
  local shop = p.shop == true
  if shop then kind = "item" end -- shopping list (Einkaufszettel) / work order: bag icon (the quest tracker draws a hammer for werk)
  return { id = p.id, kind = kind, text = text, extra = extra, dist = isDist, done = done and true or false, shop = shop or nil,
    werk = (p.werk == true) or nil }
end

-- Work order (collectors/Werkauftrag.lua, Plans.copy flag c.werk): the chain of the three stations and the next step as text lines.
-- The circled digits are not in the safe character set: "1 > [2 Einkaufen] > 3" (the position says what is done).
local function werkStatus(id)
  local Wk, P = ns.Werk, ns.Plans
  if not (Wk and type(Wk.status) == "function" and P and type(P.raw) == "function") then return nil end
  local p = P.raw(id)
  if type(p) ~= "table" or type(p.werk) ~= "table" or p.done then return nil end
  local ok, st = pcall(Wk.status, id)
  if ok and type(st) == "table" then return st end
  return nil
end

-- Colours of the label lines of a work order (row.tone): the next step in red-brown (all there: green), the chain muted.
-- Paper (pad): the template's #8A2A1C / #2F5A20; dark ground (plain note, dock): lighter tones with enough contrast.
TodoTracker.TONE_PAPER = { next = "red", ready = { 0.184, 0.353, 0.125, 1 } }
TodoTracker.TONE_DARK = { next = { 0.93, 0.48, 0.36, 1 }, ready = { 0.55, 0.85, 0.45, 1 } }

-- the tool (hammer) symbol of a work order: first atlas this client has, else nil (the bag icon stays)
TodoTracker.TOOL_ATLAS = { "worldquest-icon-blacksmithing", "Professions-Crafting-Orders-Icon" }
function TodoTracker.toolAtlas()
  local CT = rawget(_G, "C_Texture")
  if type(CT) ~= "table" or type(CT.GetAtlasInfo) ~= "function" then return nil end
  for _, name in ipairs(TodoTracker.TOOL_ATLAS) do
    local ok, info = pcall(CT.GetAtlasInfo, name)
    if ok and type(info) == "table" then return name end
  end
  return nil
end

function TodoTracker.chainText(station)
  local at = (station == 1 or station == 2 or station == 3) and station or nil
  local parts = {}
  for i = 1, 3 do
    parts[i] = i == at and T("chainCur", i, T["stage" .. i]) or tostring(i)
  end
  return table.concat(parts, " > ")
end

local function profName(prof)
  local E = ns.Einkauf
  if type(prof) ~= "number" or not (E and type(E.cache) == "function") then return nil end
  local ok, c = pcall(E.cache)
  local e = ok and type(c) == "table" and c[prof] or nil
  return type(e) == "table" and shown(e.name, 40) or nil
end

-- the next step of a status (ns.Werk.status().next) -> short line, long hint (where it goes on)
function TodoTracker.nextText(nx)
  if type(nx) ~= "table" then return nil, nil end
  local k = nx.kind
  if k == "buy" then
    local name = shown(nx.name, 60)
    if name and num(nx.n) then return T("nextBuy", tostring(floor(nx.n)), name), T.whereBuy end
    return T.nextBuyAny, T.whereBuy
  elseif k == "mail" then
    return T.nextMail, T.whereMail
  elseif k == "craft" then
    local pn = profName(nx.prof)
    if pn then return T("nextCraft", pn), T("whereCraft", pn) end
    return T.nextCraftAny, T.whereCraftAny
  elseif k == "trainer" then
    local name = shown(nx.name, 60)
    if name then return T("nextTrainer", name), T("whereTrainer", name) end
    return T.nextTrainerAny, T.whereTrainerAny
  elseif k == "done" then
    return T.nextDone, T.nextDone
  end
  return nil, nil
end

-- Shopping list / work order rows (collectors/Einkaufszettel.lua, collectors/Werkauftrag.lua): material lines in the tooltip, a click
-- opens the order where it goes on instead of the book.
function TodoTracker.rowKind(r)
  if r and r.werk then return T.werkKind end
  if r and r.shop then return T.shopKind end
  return r and T.kind[r.kind] or nil
end

function TodoTracker.rowHint(r)
  if r and r.werk then return T.werkHint end
  return r and r.shop and T.shopHint or T.rowHint
end

function TodoTracker.rowTipExtra(r)
  if not (r and r.shop and not r.sub and GameTooltip and ns.Einkauf and not r.done) then return end
  local st = r.werk and werkStatus(r.id) or nil
  if st then
    GameTooltip:AddLine(TodoTracker.chainText(st.station), 0.95, 0.9, 0.8)
    local line = TodoTracker.nextText(st.next)
    if line then GameTooltip:AddLine(line, 1, 0.82, 0, true) end
  end
  local ok, lines = pcall(ns.Einkauf.tipLines, r.id)
  if not (ok and type(lines) == "table") then return end
  for _, l in ipairs(lines) do
    if l.done then GameTooltip:AddLine(l.text, 0.6, 0.6, 0.6) else GameTooltip:AddLine(l.text, 0.95, 0.9, 0.8) end
  end
end

-- Material lines of an open shopping list as rows of their own, like quest objectives (indented, no icon): "Kupfererz 4/20", done ones
-- struck through / dim, at most SUB_MAX and then "… n weitere". They carry planId (click opens the slip) and sub = true (not counted).
function TodoTracker.shopSubRows(r)
  local E = ns.Einkauf
  if not (r and r.shop and not r.done and E and type(E.objectiveLines) == "function") then return {} end
  local out = {}
  -- work order: first the chain of the stations and the next step (label lines), then fewer material lines
  local st = werkStatus(r.id)
  local maxN = TodoTracker.SUB_MAX
  if st then
    out[#out + 1] = { id = tostring(r.id) .. "#c", planId = r.id, kind = "item", text = TodoTracker.chainText(st.station), done = false,
      shop = true, sub = true, more = true, info = "chain", tone = "chain" }
    local line = TodoTracker.nextText(st.next)
    if line then
      out[#out + 1] = { id = tostring(r.id) .. "#n", planId = r.id, kind = "item", text = line, done = false,
        shop = true, sub = true, more = true, info = "next", tone = st.station == 3 and "ready" or "next" }
    end
    maxN = TodoTracker.SUB_MAX_WERK
  end
  local ok, res = pcall(E.objectiveLines, r.id, maxN)
  if not (ok and type(res) == "table" and type(res.lines) == "table") then return out end
  for i, l in ipairs(res.lines) do
    local text = shown(l.text, 80)
    if text then
      out[#out + 1] = { id = tostring(r.id) .. "#" .. i, planId = r.id, kind = "item", text = text, name = shown(l.name, 60), have = l.have,
        need = l.need, itemID = l.id, done = l.done == true, shop = true, sub = true }
    end
  end
  if (res.more or 0) > 0 and E.TEXT then
    out[#out + 1] = { id = tostring(r.id) .. "#m", planId = r.id, kind = "item", text = E.TEXT("moreLines", tostring(res.more)), done = false,
      shop = true, sub = true, more = true }
  end
  return out
end

local function expandShop(list)
  local out = {}
  for _, r in ipairs(list) do
    out[#out + 1] = r
    if r.shop and not r.done then
      for _, s in ipairs(TodoTracker.shopSubRows(r)) do out[#out + 1] = s end
    end
  end
  return out
end

-- true if the row was a shopping list (or one of its material lines) and its slip was opened
function TodoTracker.cap(list)
  local n, mains = 0, 0
  for i, r in ipairs(list) do
    if not r.sub then
      mains = mains + 1
      if mains > TodoTracker.ROWS_MAX then break end
    end
    n = i
  end
  return math.min(n, TodoTracker.ROWS_POOL)
end

-- Click on a work order / shopping list row: opens the order where it goes on (Journal.Werkauftrag, module Crafting): the bar at
-- the open profession window switches to it, else the click explains the place in chat (the long hint of this note, else the
-- facade's line). true = handled (the book stays shut), false = not a list / module off / no open order.
function TodoTracker.openRow(r, anchor)
  if not (r and r.shop) then return false end
  local id = r.planId or r.id
  local WA = Journal.Werkauftrag
  if not (WA and type(WA.open) == "function") then return false end
  local ok, res, reason = pcall(WA.open, id, { anchor = anchor, quiet = true })
  if not (ok and res == true) then return false end
  if reason == "ort" then
    local st = werkStatus(id)
    local _, where = TodoTracker.nextText(st and st.next)
    if not where and type(WA.hint) == "function" then
      local okH, line = pcall(WA.hint, id)
      where = okH and type(line) == "string" and line or nil
    end
    if where then say(where) end
  end
  return true
end

local function planList(filter)
  local P = ns.Plans
  if not P or type(P.list) ~= "function" then return {} end
  local ok, list = pcall(P.list, filter)
  if not ok or type(list) ~= "table" then return {} end
  local out = {}
  for _, p in ipairs(list) do
    if type(p) == "table" and num(p.id) and type(p.text) == "string" then out[#out + 1] = p end
  end
  return out
end

function TodoTracker.entries()
  local open = planList("open")
  local openById = {}
  for _, p in ipairs(open) do openById[p.id] = p end
  local t = now()
  local doneById
  for _, id in ipairs(st.prevOrder) do
    if not openById[id] and not st.lingering[id] then
      if not doneById then
        doneById = {}
        for _, p in ipairs(planList("done")) do doneById[p.id] = p end
      end
      local p = doneById[id]
      if p then
        st.lingering[id] = { row = rowOf(p, true), untilT = t + TodoTracker.LINGER }
        if C_Timer and C_Timer.After then
          C_Timer.After(TodoTracker.LINGER + 0.05, function()
            if ns.Core then ns.Core.safe(TodoTracker.refresh) else TodoTracker.refresh() end
          end)
        end
      end
    end
  end
  local out, seen = {}, {}
  for _, id in ipairs(st.prevOrder) do
    local p, l = openById[id], st.lingering[id]
    if p then
      out[#out + 1] = rowOf(p, false)
      seen[id] = true
    elseif l then
      if l.untilT > t then
        out[#out + 1] = l.row
        seen[id] = true
      else
        st.lingering[id] = nil
      end
    end
  end
  for _, p in ipairs(open) do
    if not seen[p.id] then out[#out + 1] = rowOf(p, false) end
  end
  for id, l in pairs(st.lingering) do
    if l.untilT <= t then st.lingering[id] = nil end
  end
  local order = {}
  for i, r in ipairs(out) do order[i] = r.id end
  st.prevOrder = order
  return expandShop(out)
end

function TodoTracker.openCount()
  local n = 0
  for _, r in ipairs(st.shownList) do if not r.done and not r.sub then n = n + 1 end end
  return n
end

function TodoTracker.openBook()
  local Access, Frame = Journal.Access, Journal.Frame
  if not Access or not Frame then return false end
  if not Access.isOpen() and not Access.open() then return false end
  if type(Frame.openTodo) == "function" then return Frame.openTodo() and true or false end -- tab Pläne, "To Do"
  return false
end

local setFont, fontString, colorOf, rect, useTex = Slip.setFont, Slip.fontString, Slip.colorOf, Slip.rect, Slip.useTex

local function setIcon(row, kind, style)
  local t = row.icon
  local done = false
  t:SetVertexColor(1, 1, 1, 1)
  if kind == "place" and Theme.TEX.notePin then
    done = useTex(t, Theme.TEX.notePin)
    if done then t:SetTexCoord(0, 1, 0, 1) end
  elseif kind == "kill" and Theme.HAS_MAP_ICONS and Theme.mapIconCoords then
    local u0, u1, v0, v1 = Theme.mapIconCoords("kill")
    done = u0 ~= nil and useTex(t, Theme.TEX.mapIcons)
    if done then t:SetTexCoord(u0, u1, v0, v1) end
  elseif kind == "item" and Theme.TEX.momentIcons and Theme.momentIconCoords then
    local u0, u1, v0, v1 = Theme.momentIconCoords("find")
    done = useTex(t, Theme.TEX.momentIcons)
    if done then t:SetTexCoord(u0, u1, v0, v1) end
  elseif kind == "free" and Theme.HAS_DIARY and Theme.diaryCoords then
    local u0, u1, v0, v1 = Theme.diaryCoords("box")
    done = u0 ~= nil and useTex(t, Theme.TEX.diaryMarks)
    if done then
      t:SetTexCoord(u0, u1, v0, v1)
      if style == "plain" then t:SetVertexColor(colorOf(TodoTracker.PLAIN.text)) else t:SetVertexColor(W.color("ink")) end
    end
  end
  if not done then
    if style == "plain" then t:SetColorTexture(colorOf(TodoTracker.PLAIN.extra, 0.8)) else t:SetColorTexture(W.color("sepia", 0.6)) end
  end
end

local function paintLock(b)
  local s = TodoTracker.settings()
  local c = s.style == "plain" and TodoTracker.PLAIN.extra or "sepia"
  if b.hover then c = s.style == "plain" and TodoTracker.PLAIN.hover or "red" end
  local r, g, bl, a = colorOf(c)
  if b.mark then
    b.mark:SetTexCoord(Theme.todoMarkCoords(s.locked and "locked" or "unlocked"))
    b.mark:SetVertexColor(r, g, bl, a)
    return
  end
  for _, t in ipairs({ b.body, b.left, b.right, b.top }) do t:SetColorTexture(r, g, bl, a) end
  local lift = s.locked and 0 or 4
  b.left:ClearAllPoints()
  b.left:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 3, 8 + lift)
  b.right:ClearAllPoints()
  b.right:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 8 + lift)
  b.top:ClearAllPoints()
  b.top:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 3, 14 + lift)
  b.left:SetShown(s.locked and true or false)
end

function TodoTracker.paintBook()
  local b = st.book
  if not b then return end
  local isPad = TodoTracker.settings().style ~= "plain"
  local ink = isPad and "sepia" or TodoTracker.PLAIN.extra
  local mark = isPad and "red" or TodoTracker.PLAIN.title
  if b.hover then ink = isPad and "red" or TodoTracker.PLAIN.hover end
  for _, t in ipairs(b.parts) do t:SetColorTexture(colorOf(t.role == "mark" and mark or ink)) end
end

local function paintGrip(g)
  local s = TodoTracker.settings()
  local c = s.style == "plain" and TodoTracker.PLAIN.extra or "sepia"
  if g.hover then c = s.style == "plain" and TodoTracker.PLAIN.hover or "red" end
  local r, gg, b, a = colorOf(c)
  if g.mark then
    g.mark:SetVertexColor(r, gg, b, a)
    return
  end
  for _, t in ipairs(g.dots) do t:SetColorTexture(r, gg, b, a) end
end

-- HUD hook (journal/EditMode.lua): TodoTracker.hud = { place(f), moved(f), reset(), sync() }; place/moved -> true if the
-- position is managed there (per layout). In edit mode st.preview is set (sample rows).
local function savePos(f)
  if TodoTracker.hud and TodoTracker.hud.moved(f) then return end
  local l, t = num(f:GetLeft()), num(f:GetTop())
  if not l or not t then return end
  local w, h = clampSize(f:GetWidth(), f:GetHeight())
  local s = TodoTracker.settings()
  if st.shape == "closed" or st.anim then h = s.h end
  -- Grow upward: the saved position is the top edge of the full-size note; the collapsed head sits at its bottom edge
  if s.grow == "up" and f.GetBottom then
    local b = num(f:GetBottom())
    if b then t = b + h end
  end
  local x, y = TodoTracker.clampPos(l, t, w, h)
  TodoTracker.set("pos", { point = "TOPLEFT", x = x, y = y })
end

function TodoTracker.place()
  local f = st.frame
  if not f then return end
  local s = TodoTracker.settings()
  local fh = s.h
  if st.shape == "closed" and st.collapsedH then fh = st.collapsedH end
  if st.anim then fh = f:GetHeight() or fh end
  f:SetSize(s.w, fh)
  if TodoTracker.hud and TodoTracker.hud.place(f) then return end
  local sw, sh = screenSize()
  local x, y
  if s.pos then
    x, y = s.pos.x, s.pos.y
  else
    x, y = sw - s.w - 40, sh - 250
  end
  x, y = TodoTracker.clampPos(x, y, s.w, s.h)
  f:ClearAllPoints()
  if s.grow == "up" then
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y - s.h)
  else
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
  end
end

local function rowTooltip(row)
  local r = row.data
  if not r or not GameTooltip then return end
  GameTooltip:SetOwner(row, "ANCHOR_LEFT")
  GameTooltip:AddLine(r.text, 1, 0.82, 0, true)
  local kind = TodoTracker.rowKind(r)
  if kind then GameTooltip:AddLine(r.extra and (kind .. " · " .. r.extra) or kind, 0.9, 0.9, 0.9) end
  TodoTracker.rowTipExtra(r)
  GameTooltip:AddLine(TodoTracker.rowHint(r), 0.6, 0.75, 1, true)
  GameTooltip:Show()
end

local function paintRow(row)
  local s = TodoTracker.settings()
  local P = s.style == "plain" and TodoTracker.PLAIN or TodoTracker.PAD
  local r = row.data
  local c = (r and r.done) and P.done or ((row.hover and r and not r.done) and P.hover or (r and r.sub and P.extra or P.text))
  if r and r.tone and not r.done and (r.tone == "next" or r.tone == "ready") then
    c = (s.style == "plain" and TodoTracker.TONE_DARK or TodoTracker.TONE_PAPER)[r.tone]
  end
  row.text:SetTextColor(colorOf(c))
  row.extra:SetTextColor(colorOf((r and r.done) and P.done or P.extra))
  row.icon:SetAlpha((r and r.done) and 0.5 or 1)
end

local function buildRow(f, i)
  local row = CreateFrame("Button", nil, f)
  row:RegisterForClicks("LeftButtonUp")
  row.icon = rect(row, "ARTWORK")
  row.text = fontString(row)
  row.text:SetJustifyH("LEFT")
  if row.text.SetJustifyV then row.text:SetJustifyV("TOP") end
  row.text:SetWordWrap(true)
  if row.text.SetMaxLines then row.text:SetMaxLines(2) end
  row.extra = fontString(row)
  row.extra:SetJustifyH("RIGHT")
  row.extra:SetWordWrap(false)
  row.strike = rect(row, "OVERLAY")
  row.strike2 = rect(row, "OVERLAY")
  row.line = rect(row, "BACKGROUND", 2)
  row.line2 = rect(row, "BACKGROUND", 2)
  row:SetScript("OnClick", function(self)
    if TodoTracker.openRow(self.data) then return end
    if ns.Core then ns.Core.safe(TodoTracker.openBook) else TodoTracker.openBook() end
  end)
  row:SetScript("OnEnter", function(self)
    self.hover = true
    paintRow(self)
    rowTooltip(self)
  end)
  row:SetScript("OnLeave", function(self)
    self.hover = false
    paintRow(self)
    if GameTooltip then GameTooltip:Hide() end
  end)
  row:Hide()
  st.rows[i] = row
  return row
end

local function startMove(f)
  if TodoTracker.settings().locked then return end
  f.moving = true
  f:StartMoving()
end

local function stopMove(f)
  if not f.moving then return end
  f.moving = false
  f:StopMovingOrSizing()
  savePos(f)
  TodoTracker.place()
end

-- paper of the note (pad image or paper fallback, plain box), close button: core building blocks (journal/widgets/Slip.lua)
TodoTracker.newPad, TodoTracker.sizePad, TodoTracker.padY, TodoTracker.newPlain = Slip.newPad, Slip.sizePad, Slip.padY, Slip.newPlain
TodoTracker.fontString, TodoTracker.setFont, TodoTracker.colorOf = fontString, setFont, colorOf

TodoTracker.newClose, TodoTracker.paintClose = Slip.newClose, Slip.paintClose

function TodoTracker.build()
  if st.frame then return st.frame end
  local f = CreateFrame("Frame", TodoTracker.NAME, UIParent)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  if f.SetResizeBounds then
    f:SetResizeBounds(TodoTracker.SIZE.minW, TodoTracker.SIZE.minH, TodoTracker.SIZE.maxW, TodoTracker.SIZE.maxH)
  else
    if f.SetMinResize then f:SetMinResize(TodoTracker.SIZE.minW, TodoTracker.SIZE.minH) end
    if f.SetMaxResize then f:SetMaxResize(TodoTracker.SIZE.maxW, TodoTracker.SIZE.maxH) end
  end
  if f.SetDontSavePosition then f:SetDontSavePosition(true) end -- the addon saves the position per character
  f:EnableMouse(true)
  f:Hide()

  st.pad = TodoTracker.newPad(f)
  st.plain = TodoTracker.newPlain(f)

  local body = CreateFrame("Frame", nil, f)
  body:SetAllPoints(f)
  body:SetFrameLevel((f:GetFrameLevel() or 1) + 2)
  st.body = body

  local head = CreateFrame("Frame", nil, body)
  head:EnableMouse(true)
  head:RegisterForDrag("LeftButton")
  head:SetScript("OnMouseDown", function(self) self.dragged = false end)
  head:SetScript("OnDragStart", function(self)
    self.dragged = true
    startMove(f)
  end)
  head:SetScript("OnDragStop", function() stopMove(f) end)
  head:SetScript("OnMouseUp", function(self, button)
    if self.dragged or (button and button ~= "LeftButton") then return end
    if ns.Core then ns.Core.safe(TodoTracker.headClick) else TodoTracker.headClick() end
  end)
  head:SetScript("OnHide", function() stopMove(f) end)
  st.head = head
  st.title = fontString(head)
  st.title:SetJustifyH("LEFT")
  st.title:SetWordWrap(false)
  st.count = fontString(head)
  st.count:SetJustifyH("RIGHT")
  st.count:SetWordWrap(false)

  local chev = CreateFrame("Button", nil, head)
  chev:SetSize(16, 16)
  chev:RegisterForClicks("LeftButtonUp")
  chev.closed = D.mark(chev, "next", 12, "sepia")
  chev.open = D.mark(chev, "down", 12, "sepia")
  chev.closed:SetPoint("CENTER", chev, "CENTER", 0, 0)
  chev.open:SetPoint("CENTER", chev, "CENTER", 0, 0)
  chev:SetScript("OnClick", function()
    if ns.Core then ns.Core.safe(TodoTracker.headClick) else TodoTracker.headClick() end
  end)
  chev:SetScript("OnEnter", function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine(st.expanded and T.toggleClose or T.toggleOpen, 1, 0.82, 0)
      GameTooltip:AddLine(T.toggleHint, 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end
  end)
  chev:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  chev:Hide()
  st.chev = chev

  local lock = CreateFrame("Button", nil, head)
  lock:SetSize(16, 18)
  if Theme.HAS_TODO_MARKS and Theme.TEX.todoMarks then
    local m = rect(lock, "ARTWORK")
    if useTex(m, Theme.TEX.todoMarks) then
      m:SetSize(16, 16)
      m:SetPoint("CENTER", lock, "CENTER", 0, 0)
      lock.mark = m
    end
  end
  lock.body = rect(lock, "ARTWORK")
  lock.body:SetSize(12, 8)
  lock.body:SetPoint("BOTTOM", lock, "BOTTOM", 0, 1)
  lock.left, lock.right, lock.top = rect(lock, "ARTWORK"), rect(lock, "ARTWORK"), rect(lock, "ARTWORK")
  lock.left:SetSize(2, 7)
  lock.right:SetSize(2, 7)
  lock.top:SetSize(10, 2)
  lock:RegisterForClicks("LeftButtonUp")
  lock:SetScript("OnClick", function()
    if ns.Core then ns.Core.safe(TodoTracker.setLocked, not TodoTracker.settings().locked) else TodoTracker.setLocked(not TodoTracker.settings().locked) end
  end)
  lock:SetScript("OnEnter", function(self)
    self.hover = true
    paintLock(self)
    if GameTooltip then
      local locked = TodoTracker.settings().locked
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine(locked and T.unlock or T.lock, 1, 0.82, 0)
      GameTooltip:AddLine(locked and T.lockHint or T.unlockHint, 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end
  end)
  lock:SetScript("OnLeave", function(self)
    self.hover = false
    paintLock(self)
    if GameTooltip then GameTooltip:Hide() end
  end)
  st.lock = lock

  -- Little ink book (like the one on the quick note): opens the Travel Journal on the To-Do page
  local book = CreateFrame("Button", nil, head)
  book:SetSize(TodoTracker.BOOK_W, TodoTracker.BOOK_H)
  book:RegisterForClicks("LeftButtonUp")
  book.parts = {}
  local function piece(w, h, x, y, role)
    local t = book:CreateTexture(nil, "ARTWORK")
    t:SetSize(w, h)
    t:SetPoint("BOTTOMLEFT", book, "BOTTOMLEFT", x, y)
    t.role = role
    book.parts[#book.parts + 1] = t
    return t
  end
  piece(14, 1, 2, 3, "ink")
  piece(14, 1, 2, 12, "ink")
  piece(1, 10, 2, 3, "ink")
  piece(1, 10, 15, 3, "ink")
  piece(1, 10, 8, 3, "ink")
  piece(4, 1, 10, 9, "ink")
  piece(4, 1, 10, 6, "ink")
  piece(3, 6, 4, 0, "mark")
  book:SetScript("OnClick", function()
    if GameTooltip then GameTooltip:Hide() end
    if ns.Core then ns.Core.safe(TodoTracker.openBook) else TodoTracker.openBook() end
  end)
  book:SetScript("OnEnter", function(self)
    self.hover = true
    TodoTracker.paintBook()
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine(T.openBook, 1, 0.82, 0)
      GameTooltip:AddLine(T.openBookHint, 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end
  end)
  book:SetScript("OnLeave", function(self)
    self.hover = false
    TodoTracker.paintBook()
    if GameTooltip then GameTooltip:Hide() end
  end)
  st.book = book
  st.close = TodoTracker.newClose(head, function()
    TodoTracker.setShown(false)
    say(T.off)
  end, T.close, T.closeHint)

  local grip = CreateFrame("Button", nil, body)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
  grip.dots = {}
  local gm = Theme.HAS_TODO_MARKS and Theme.TEX.todoMarks and rect(grip, "OVERLAY")
  if gm and useTex(gm, Theme.TEX.todoMarks) then
    gm:SetTexCoord(Theme.todoMarkCoords("grip"))
    gm:SetAllPoints(grip)
    grip.mark = gm
  else
    for i, xy in ipairs({ { 1, 1 }, { 5, 1 }, { 9, 1 }, { 5, 5 }, { 9, 5 }, { 9, 9 } }) do
      local t = rect(grip, "OVERLAY")
      t:SetSize(2, 2)
      t:SetPoint("BOTTOMLEFT", grip, "BOTTOMLEFT", xy[1], xy[2])
      grip.dots[i] = t
    end
  end
  grip:SetScript("OnMouseDown", function()
    if TodoTracker.settings().locked then return end
    f.sizing = true
    -- Grow upward: the head sits at the bottom edge and stays put, so the handle is at the top right and resizes from there
    f:StartSizing(TodoTracker.settings().grow == "up" and "TOPRIGHT" or "BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    if not f.sizing then return end
    f.sizing = false
    f:StopMovingOrSizing()
    TodoTracker.set("size", { w = f:GetWidth(), h = f:GetHeight() })
    savePos(f)
    TodoTracker.place()
    TodoTracker.layout()
  end)
  grip:SetScript("OnEnter", function(self)
    self.hover = true
    paintGrip(self)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine(T.grip, 1, 0.82, 0)
      GameTooltip:Show()
    end
  end)
  grip:SetScript("OnLeave", function(self)
    self.hover = false
    paintGrip(self)
    if GameTooltip then GameTooltip:Hide() end
  end)
  st.grip = grip

  st.more = fontString(body)
  st.more:SetJustifyH("LEFT")
  st.more:SetWordWrap(false)
  st.empty = fontString(body)
  st.empty:SetJustifyH("CENTER")
  st.empty:SetWordWrap(true)
  for i = 1, TodoTracker.ROWS_POOL do buildRow(body, i) end
  st.rules = {}
  for i = 1, TodoTracker.RULES_MAX do
    local t = rect(body, "BACKGROUND", 2)
    t:Hide()
    st.rules[i] = t
  end

  f:SetScript("OnSizeChanged", function()
    if f.sizing then TodoTracker.layout() end
  end)
  f:SetScript("OnHide", function()
    if f.moving or f.sizing then
      f.moving, f.sizing = false, false
      f:StopMovingOrSizing()
    end
    st.hover = false
    if st.anim then TodoTracker.finishAnim() end
  end)
  -- Hover mode: every child reports enter/leave; collapse only after a short grace period once the mouse is really outside
  -- (the client reports leaving the parent when the mouse moves onto a child frame).
  for _, w in ipairs({ f, head, chev, lock, book, st.close, grip }) do TodoTracker.watch(w) end
  for _, row in ipairs(st.rows) do TodoTracker.watch(row) end

  st.frame = f
  TodoTracker.applyStyle()
  TodoTracker.place()
  return f
end

function TodoTracker.applyStyle()
  if not st.frame then return end
  local s = TodoTracker.settings()
  local M = TodoTracker.METRICS[s.style]
  local isPad = s.style == "pad"
  st.pad:SetShown(isPad)
  st.plain:SetShown(not isPad)
  local textKind = isPad and "hand" or "text"
  setFont(st.title, isPad and "hand" or "text", M.titleSize)
  setFont(st.count, isPad and "label" or "text", M.extraSize)
  setFont(st.more, isPad and "label" or "text", M.moreSize)
  setFont(st.empty, textKind, M.textSize)
  local P = isPad and TodoTracker.PAD or TodoTracker.PLAIN
  st.title:SetTextColor(colorOf(P.title))
  st.count:SetTextColor(colorOf(P.extra))
  st.more:SetTextColor(colorOf(P.extra))
  st.empty:SetTextColor(colorOf(P.text))
  local shadow = { st.title, st.count, st.more, st.empty }
  for _, row in ipairs(st.rows) do
    setFont(row.text, textKind, M.textSize)
    setFont(row.extra, isPad and "label" or "text", M.extraSize)
    shadow[#shadow + 1] = row.text
    shadow[#shadow + 1] = row.extra
    if isPad then
      row.line:SetColorTexture(colorOf(TodoTracker.PAD.line))
      row.line2:SetColorTexture(colorOf(TodoTracker.PAD.line))
    end
    row.line:SetShown(isPad)
    row.line2:SetShown(false)
    if row.text.SetSpacing then row.text:SetSpacing(isPad and max(0, M.rule - M.textSize) or 0) end
    for _, t in ipairs({ row.strike, row.strike2 }) do
      t:SetColorTexture(colorOf(isPad and "ink" or TodoTracker.PLAIN.text, isPad and 0.75 or 0.8))
    end
    paintRow(row)
  end
  for _, fs in ipairs(shadow) do
    if fs.SetShadowOffset then fs:SetShadowOffset(isPad and 0 or 1, isPad and 0 or -1) end
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, isPad and 0 or 0.9) end
  end
  for _, t in ipairs(st.rules) do
    t:SetColorTexture(colorOf(TodoTracker.PAD.line))
    if not isPad then t:Hide() end
  end
  st.title:SetText(T.title)
  for _, m in ipairs({ st.chev.closed, st.chev.open }) do m:SetVertexColor(colorOf(isPad and "sepia" or TodoTracker.PLAIN.extra)) end
  paintLock(st.lock)
  TodoTracker.paintBook()
  TodoTracker.paintClose(st.close, isPad)
  paintGrip(st.grip)
  st.style = s.style
end

function TodoTracker.layout()
  local f = st.frame
  if not f then return end
  local s = TodoTracker.settings()
  local M = TodoTracker.METRICS[s.style]
  local closed = st.shape == "closed"
  local w, h = f:GetWidth() or s.w, f:GetHeight() or s.h
  if not num(w) or w <= 0 then w = s.w end
  if not num(h) or h <= 0 then h = s.h end
  if closed or st.anim then h = s.h end
  local isPad = s.style == "pad"
  local img = isPad and st.pad.image
  local S = Theme.TODO_PAD_SLICE
  -- Grow upward: everything is anchored to the bottom edge (offset = h - y), so the head keeps its screen position while
  -- the frame grows; in layout coordinates (y down from the top of the full-size note) the head sits `shift` lower.
  local up = s.grow == "up"
  local function at(obj, x, y)
    obj:ClearAllPoints()
    if up then obj:SetPoint("TOPLEFT", f, "BOTTOMLEFT", x, h - y) else obj:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y) end
  end
  local padL = max(M.padLMin, floor(w * M.padL + 0.5))
  if isPad then padL = padL + 8 end
  local padR, padB = M.padR, M.padB
  if img then
    TodoTracker.sizePad(st.pad, w, h)
    padR = max(M.padR, floor(w * 0.07 + 0.5))
  end
  local list = st.shownList
  local open = TodoTracker.openCount()
  local showCount = open > 0 or s.open ~= "always" or st.preview
  st.count:SetText(showCount and string.format(T.count, open) or "")
  local top, below = M.top, false
  if img and S.edge then top = max(top, floor((TodoTracker.padY(st.pad, S.edge) or 0) + 0.5) + 2) end
  if img and S.tab then
    local tabL, tabR = S.tab[1] * w, S.tab[2] * w
    local titleR = padL + (num(st.title:GetStringWidth()) or 0)
    local countW = showCount and (num(st.count:GetStringWidth()) or 0) or 0
    local countL = w - padR + 3 - TodoTracker.CLOSE_W - 2 - 16 - 4 - TodoTracker.BOOK_W - 6 - countW
    if titleR > tabL - 4 or countL < tabR + 4 then
      top = max(top, floor((TodoTracker.padY(st.pad, S.tab[3]) or 0) + 2.5))
      below = true
    end
  end
  do
    local fixed
    if isPad then
      if img then
        local a = S.aspect or 1
        fixed = ((S.top[2] - S.top[1]) + (S.bottom[2] - S.bottom[1])) * a * w + 8
      else
        fixed = 2 * (TodoTracker.PAD_SLICE.edge or 38) + 8
      end
    end
    local headBottom = top + M.head
    st.collapsedH = max(floor(max(fixed or 0, headBottom + (isPad and 14 or M.padB)) + 0.5), 20)
  end
  local shift = up and max(0, h - st.collapsedH) or 0
  st.head:ClearAllPoints()
  if up then
    st.head:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, st.collapsedH)
    st.head:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, st.collapsedH)
  else
    st.head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    st.head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  end
  st.head:SetHeight(top + M.head)
  st.close:ClearAllPoints()
  if up then
    st.close:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", -padR + 3, st.collapsedH - (top + floor((M.head - 16) / 2)))
  else
    st.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -padR + 3, -(top + floor((M.head - 16) / 2)))
  end
  st.lock:ClearAllPoints()
  st.lock:SetPoint("RIGHT", st.close, "LEFT", -2, 0)
  st.book:ClearAllPoints()
  st.book:SetPoint("RIGHT", st.lock, "LEFT", -4, 0)
  at(st.title, padL, top + shift)
  st.title:SetHeight(M.head)
  if st.title.SetJustifyV then st.title:SetJustifyV("MIDDLE") end
  st.count:ClearAllPoints()
  st.count:SetPoint("RIGHT", st.book, "LEFT", -6, 0)
  st.grip:SetShown(not s.locked and not closed)
  st.chev:ClearAllPoints()
  st.chev:SetPoint("LEFT", st.title, "LEFT", (num(st.title:GetStringWidth()) or 0) + 4, 0)
  st.chev:SetShown(s.open == "click" and not st.preview)
  st.chev.closed:SetShown(not st.expanded)
  st.chev.open:SetShown(st.expanded and true or false)
  if closed then
    for i = 1, TodoTracker.ROWS_POOL do
      st.rows[i]:Hide()
      st.rows[i].data = nil
    end
    st.more:SetText("")
    st.more:Hide()
    st.empty:SetText("")
    st.empty:Hide()
    for _, t in ipairs(st.rules) do t:Hide() end
    st.grip:Hide()
    if not st.anim then f:SetHeight(st.collapsedH) end
    if img then TodoTracker.sizePad(st.pad, w, f:GetHeight()) end
    st.used, st.rest, st.hasDist, st.rulesShown = 0, #list, false, 0
    return
  end
  st.grip:ClearAllPoints()
  if up then
    -- the handle moves to the top right corner (and is mirrored): the note grows upward from the head at the bottom
    if img then
      local gu = S.grip and S.grip[1] or 0.875
      st.grip:SetSize(20, 20)
      st.grip:SetPoint("CENTER", f, "TOPLEFT", floor(w * gu + 0.5), -floor((TodoTracker.padY(st.pad, S.edge or 0.05) or 0) + 10.5))
    else
      st.grip:SetSize(14, 14)
      st.grip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    end
  elseif img then
    local gu, gv = S.grip and S.grip[1] or 0.875, S.grip and S.grip[2] or 0.885
    st.grip:SetSize(20, 20)
    st.grip:SetPoint("CENTER", f, "TOPLEFT", floor(w * gu + 0.5), -floor((TodoTracker.padY(st.pad, gv) or h) + 0.5))
  else
    st.grip:SetSize(14, 14)
    st.grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
  end
  if st.grip.mark then
    local u0, u1, v0, v1 = Theme.todoMarkCoords("grip")
    if u0 then
      if up then st.grip.mark:SetTexCoord(u0, u1, v1, v0) else st.grip.mark:SetTexCoord(u0, u1, v0, v1) end
    end
  else
    for i, xy in ipairs({ { 1, 1 }, { 5, 1 }, { 9, 1 }, { 5, 5 }, { 9, 5 }, { 9, 9 } }) do
      local t = st.grip.dots[i]
      if t then
        t:ClearAllPoints()
        t:SetPoint(up and "TOPLEFT" or "BOTTOMLEFT", st.grip, up and "TOPLEFT" or "BOTTOMLEFT", xy[1], up and -xy[2] or xy[2])
      end
    end
  end

  local R = M.rule or 0
  local lineH = math.ceil(M.textSize * 1.2)
  local asc = floor(M.textSize * 1.05 + 0.5)
  local bodyTop = top + M.head + (below and floor(M.bodyGap / 2) or M.bodyGap)
  if img and S.tab then bodyTop = max(bodyTop, floor((TodoTracker.padY(st.pad, S.tab[3]) or 0) + 0.5) + 6 - (R - asc)) end
  local nar = img and not up -- torn lower edge / curl narrows the rows only when the content lies above it (grow down)
  local bottom = h - padB
  if up then
    -- the content sits above the head: from below the top edge (and tape) down to just above the head
    bodyTop = M.top + floor(M.bodyGap / 2)
    if img and S.edge then bodyTop = max(bodyTop, floor((TodoTracker.padY(st.pad, S.edge) or 0) + 0.5) + 4) end
    if img and S.tab then bodyTop = max(bodyTop, floor((TodoTracker.padY(st.pad, S.tab[3]) or 0) + 0.5) + 6 - (R - asc)) end
    bottom = top + shift - floor(M.bodyGap / 2)
  elseif img and S.curl then
    bottom = floor((TodoTracker.padY(st.pad, S.curl[2]) or bottom) + 0.5)
  end
  local y = bodyTop
  local textX = padL + M.icon + M.gap
  local lineX0 = img and floor(w * ((S.margin or 0.133) + 0.035) + 0.5) or (padL - 6)
  local lineX1 = w - padR + 4
  local moreH = isPad and R or (M.moreSize + 6)
  local lastY, curlX = bottom, lineX1
  if nar and S.paper and S.curl then
    lastY = max(bottom, floor((TodoTracker.padY(st.pad, S.paper - 0.04) or bottom) + 0.5))
    curlX = floor(S.curl[1] * w + 0.5) - 6
  end
  local used = 0
  local hasDist = false
  local cap = TodoTracker.cap(list)
  for i = 1, TodoTracker.ROWS_POOL do
    local row, r = st.rows[i], (i <= cap) and list[i] or nil
    if r then
      row.data = r
      setIcon(row, r.kind, s.style)
      row.icon:SetShown(not r.sub) -- a material line of a shopping list has no icon, it hangs indented below its list
      local subInd = r.sub and TodoTracker.SUB_INDENT or 0
      row.extra:SetText(r.extra or "")
      local ew = r.extra and (row.extra:GetStringWidth() or 0) or 0
      if ew > 0 then ew = ew + 6 end
      local narrow = nar and (y + R - 1 > bottom)
      local rowR, tw, th, two
      local function measure()
        rowR = narrow and curlX or (w - padR)
        tw = max(40, rowR - textX - ew - subInd)
        row.text:SetWidth(tw)
        if row.text.SetMaxLines then row.text:SetMaxLines(r.sub and 1 or 2) end
        row.text:SetText(r.text)
        th = row.text:GetStringHeight() or M.textSize
        if not num(th) or th <= 0 then th = M.textSize end
        th = min(th, 2 * lineH)
        two = th > lineH * 1.5
      end
      measure()
      if nar and two and not narrow and y + 2 * R - 1 > bottom then
        narrow = true
        measure()
      end
      local rx1 = narrow and min(lineX1, curlX) or lineX1
      local rh
      if isPad then rh = (two and 2 or 1) * R else rh = max(M.icon, th) + M.rowGap end
      local restAfter = #list - i
      local limit = lastY - (restAfter > 0 and moreH or 0)
      local oneH = isPad and R or (max(M.icon, lineH) + M.rowGap)
      if y + rh > limit and th > lineH and y + oneH <= limit then
        th, two, rh = lineH, false, oneH
        if narrow and not (y + R - 1 > bottom) then
          narrow = false
          rowR = w - padR
          tw = max(40, rowR - textX - ew - subInd)
          row.text:SetWidth(tw)
          rx1 = lineX1
        end
        if row.text.SetMaxLines then row.text:SetMaxLines(1) end
      end
      if y + rh > limit and i > 1 then
        row:Hide()
        row.data = nil
        for k = i + 1, TodoTracker.ROWS_POOL do
          st.rows[k]:Hide()
          st.rows[k].data = nil
        end
        break
      end
      local textOff = isPad and (R - asc) or 0
      row:ClearAllPoints()
      at(row, padL, y)
      row:SetSize(rowR - padL, rh)
      row.icon:ClearAllPoints()
      row.icon:SetSize(M.icon, M.icon)
      row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(textOff + max(0, floor((min(th, lineH) - M.icon) / 2))))
      row.text:ClearAllPoints()
      row.text:SetPoint("TOPLEFT", row, "TOPLEFT", M.icon + M.gap + subInd, -textOff)
      row.text:SetHeight(isPad and (two and (R + lineH) or lineH) or th)
      row.extra:ClearAllPoints()
      if isPad then
        row.extra:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -(R - floor(M.extraSize * 1.05 + 0.5)))
      else
        row.extra:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -floor((lineH - M.extraSize) / 2))
      end
      -- Strike-through: one stroke per text line (GetStringWidth = width without wrapping; the second line gets the rest)
      if r.done then
        local full = num(row.text:GetStringWidth()) or tw
        local thick = isPad and 2 or 1
        local mid1 = isPad and floor(M.textSize * 0.62 + 0.5) or floor(lineH / 2)
        local mid2 = isPad and (R + mid1) or floor(lineH * 1.5)
        row.strike:ClearAllPoints()
        row.strike:SetPoint("TOPLEFT", row.text, "TOPLEFT", -2, -mid1)
        row.strike:SetSize(max(8, min(tw, full) + 4), thick)
        row.strike:Show()
        if th > lineH and full > tw then
          row.strike2:ClearAllPoints()
          row.strike2:SetPoint("TOPLEFT", row.text, "TOPLEFT", -2, -mid2)
          row.strike2:SetSize(max(8, min(tw, full - tw) + 4), thick)
          row.strike2:Show()
        else
          row.strike2:Hide()
        end
      else
        row.strike:Hide()
        row.strike2:Hide()
      end
      row.line:ClearAllPoints()
      at(row.line, lineX0, y + R - 1)
      row.line:SetSize(max(1, rx1 - lineX0), 1)
      row.line2:ClearAllPoints()
      at(row.line2, lineX0, y + 2 * R - 1)
      row.line2:SetSize(max(1, rx1 - lineX0), 1)
      row.line2:SetShown(isPad and two)
      if r.dist and not r.done then hasDist = true end
      paintRow(row)
      row:Show()
      y = y + rh
      used = i
    else
      row.data = nil
      row:Hide()
    end
  end
  local rest = #list - used
  if rest > 0 then
    st.more:ClearAllPoints()
    if isPad then
      at(st.more, textX, y + R - floor(M.moreSize * 1.05 + 0.5))
    else
      at(st.more, textX, y + 2)
    end
    st.more:SetText(string.format(T.more, rest))
    st.more:Show()
  else
    st.more:SetText("")
    st.more:Hide()
  end
  if #list == 0 then
    st.empty:ClearAllPoints()
    at(st.empty, padL, bodyTop + (isPad and (R - asc) or 6))
    st.empty:SetWidth(max(40, w - padL - padR))
    st.empty:SetText(T.empty)
    st.empty:Show()
  else
    st.empty:SetText("")
    st.empty:Hide()
  end
  local ry = y
  local k = 0
  for i = 1, TodoTracker.RULES_MAX do
    local t = st.rules[i]
    local ly = ry + i * R - 1
    if isPad and R > 0 and ly <= lastY then
      local x1 = ly > bottom and min(lineX1, curlX) or lineX1
      t:ClearAllPoints()
      at(t, lineX0, ly)
      t:SetSize(max(1, x1 - lineX0), 1)
      t:Show()
      k = i
    else
      t:Hide()
    end
  end
  st.used, st.rest, st.hasDist, st.rulesShown = used, rest, hasDist, k
end

function TodoTracker.wanted()
  if TodoTracker.suppressed() then return false end
  local s = TodoTracker.settings()
  if not s.shown then return false end
  local Store = ns.Store
  if not (Store and Store.char and Store.char()) then return false end
  if s.combatHide and inCombat() then return false end
  if s.hideEmpty and #st.shownList == 0 then return false end
  return true
end

local function stopTicker()
  if st.ticker then st.ticker:Cancel() end
  st.ticker, st.tickEvery = nil, nil
end

local function updateTicker()
  if TodoTracker.suppressed() then return stopTicker() end
  local s = TodoTracker.settings()
  local every
  if (s.shown or TodoTracker.docked()) and not (s.combatHide and inCombat()) then
    if st.frame and st.frame:IsShown() and st.hasDist then every = TodoTracker.DIST_EVERY end
    if TodoTracker.Dock and TodoTracker.Dock.hasDist() then every = TodoTracker.DIST_EVERY end
  end
  if every == st.tickEvery then return end
  stopTicker()
  if every and C_Timer and C_Timer.NewTicker then
    st.ticker = C_Timer.NewTicker(every, function()
      if ns.Core then ns.Core.safe(TodoTracker.refresh) else TodoTracker.refresh() end
    end)
    st.tickEvery = every
  end
end

local function signature(list, style)
  local parts = { style or "" }
  local cap = TodoTracker.cap(list)
  for i, r in ipairs(list) do
    parts[#parts + 1] = table.concat({ tostring(r.id), r.kind, r.text, r.extra or "", r.done and "1" or "0" }, "\1")
    if i > cap + 1 then parts[#parts + 1] = tostring(#list) break end
  end
  return table.concat(parts, "\2")
end

local function reduceMotion()
  local V = Journal.View
  if not V or type(V.peek) ~= "function" then return false end
  local ok, v = pcall(V.peek, "reduceMotion")
  return ok and v == true
end

function TodoTracker.wantOpen()
  if st.preview then return true end
  local mode = TodoTracker.settings().open
  if mode == "hover" then return st.hover == true end
  if mode == "click" then return st.clickOpen == true end
  if mode == "auto" then return #st.shownList > 0 end
  return true
end

function TodoTracker.finishAnim()
  local a, f = st.anim, st.frame
  if not a then return end
  st.anim = nil
  if f then
    f:SetScript("OnUpdate", nil)
    if f.SetClipsChildren then f:SetClipsChildren(false) end
  end
  if a.closing then st.shape = "closed" end
  st.sig = nil
  if f then
    if a.closing then TodoTracker.layout() else f:SetHeight(TodoTracker.settings().h) end
    if st.pad and st.pad.image then TodoTracker.sizePad(st.pad, f:GetWidth(), f:GetHeight()) end
  end
end

function TodoTracker.animStep(dt)
  local a, f = st.anim, st.frame
  if not (a and f) then return end
  a.t = a.t + (num(dt) or 0)
  local p = min(1, a.t / TodoTracker.ANIM)
  local e = p * p * (3 - 2 * p)
  local h = a.from + (a.to - a.from) * e
  f:SetHeight(h)
  if st.pad and st.pad.image then TodoTracker.sizePad(st.pad, f:GetWidth(), h) end
  if p >= 1 then TodoTracker.finishAnim() end
end

local function startAnim(from, to, closing)
  local f = st.frame
  st.anim = { from = from, to = to, t = 0, closing = closing }
  if f.SetClipsChildren then f:SetClipsChildren(true) end
  f:SetScript("OnUpdate", function(_, dt)
    if ns.Core then ns.Core.safe(TodoTracker.animStep, dt) else TodoTracker.animStep(dt) end
  end)
end

function TodoTracker.syncOpen()
  local f = st.frame
  if not f then return false end
  local want = TodoTracker.wantOpen()
  if st.expanded == want then return false end
  local first = st.expanded == nil
  st.expanded = want
  local s = TodoTracker.settings()
  local cur = num(f:GetHeight()) or s.h
  local animate = not first and f:IsShown() and s.style == "pad" and st.collapsedH ~= nil and not reduceMotion()
  if st.anim then
    st.anim = nil
    f:SetScript("OnUpdate", nil)
  end
  st.sig = nil
  if want then
    st.shape = "open"
    if animate then
      st.anim = { from = cur, to = s.h, t = 0 }
      TodoTracker.layout()
      st.anim = nil
      startAnim(cur, s.h, false)
    else
      f:SetHeight(s.h)
      if f.SetClipsChildren then f:SetClipsChildren(false) end
      TodoTracker.layout()
    end
  elseif animate then
    startAnim(cur, st.collapsedH, true)
  else
    st.shape = "closed"
    if f.SetClipsChildren then f:SetClipsChildren(false) end
    TodoTracker.layout()
  end
  return true
end

function TodoTracker.headClick()
  if TodoTracker.settings().open ~= "click" or st.preview then return false end
  st.clickOpen = not st.clickOpen
  TodoTracker.syncOpen()
  return true
end

local function hoverIn()
  if st.hover then return end
  st.hover = true
  if TodoTracker.settings().open == "hover" then TodoTracker.syncOpen() end
end

local function hoverOut()
  local function check()
    local f = st.frame
    if f and f.IsMouseOver and f:IsMouseOver() and f:IsShown() then return end
    if st.hover then
      st.hover = false
      if TodoTracker.settings().open == "hover" then TodoTracker.syncOpen() end
    end
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(TodoTracker.HOVER_GRACE, function()
      if ns.Core then ns.Core.safe(check) else check() end
    end)
  else
    check()
  end
end

function TodoTracker.watch(frame)
  if frame.HookScript then
    frame:HookScript("OnEnter", hoverIn)
    frame:HookScript("OnLeave", hoverOut)
  end
end

-- Docked to the quest tracker (journal/TodoDock.lua): the mini note stays hidden and the section draws the same entries. It shows
-- whenever to-dos are open (or always with "hide when empty" off), independent of the mini note's on/off switch.
function TodoTracker.docked()
  return not TodoTracker.suppressed() and TodoTracker.Dock ~= nil and TodoTracker.settings().dock == true
end

-- The own quest tracker (journal/QuestTrackerHide.lua, WoW Forever, option off by default) is on: mini note, dock, distance
-- ticker, automatic show and the edit-mode entry "todo" rest. Plans.onChange/hookPlans/changed keep running and call the
-- onPlansChanged listeners, so the quest tracker can draw TodoTracker.entries() itself. Option off: exactly the baseline.
function TodoTracker.suppressed()
  local Q = Journal.QuestTrackerHide
  if Q == nil then return false end
  if type(Q.active) == "function" and Q.active() == true then return true end
  -- the saved wish counts too: at login/reload this module's PLAYER_ENTERING_WORLD runs before QuestTrackerHide applies
  return type(Q.wanted) == "function" and Q.wanted() == true
end

TodoTracker.plansListeners = {}
function TodoTracker.onPlansChanged(fn)
  if type(fn) == "function" then TodoTracker.plansListeners[#TodoTracker.plansListeners + 1] = fn end
end

local function refreshSuppressed()
  if st.frame then st.frame:Hide() end
  if TodoTracker.Dock then TodoTracker.Dock.hide() end
  stopTicker()
  if TodoTracker.hookPlans then TodoTracker.hookPlans() end
  for _, fn in ipairs(TodoTracker.plansListeners) do pcall(fn) end
  return false
end

local function refreshDocked(s)
  if st.frame then st.frame:Hide() end
  local Dock = TodoTracker.Dock
  local Store = ns.Store
  if not (Store and Store.char and Store.char()) then
    Dock.hide()
    return false
  end
  if s.combatHide and inCombat() then
    Dock.hide()
    stopTicker()
    return false
  end
  if TodoTracker.hookPlans then TodoTracker.hookPlans() end
  st.shownList = TodoTracker.entries()
  local want = #st.shownList > 0 or not s.hideEmpty
  if want then Dock.render(st.shownList) else Dock.hide() end
  updateTicker()
  return want
end

function TodoTracker.refresh()
  if st.preview then return true end
  if TodoTracker.suppressed() then return refreshSuppressed() end
  local s = TodoTracker.settings()
  if TodoTracker.docked() then return refreshDocked(s) end
  if TodoTracker.Dock then TodoTracker.Dock.hide() end
  if not s.shown then
    if st.frame then st.frame:Hide() end
    stopTicker()
    st.prevOrder, st.lingering, st.shownList = {}, {}, {}
    return false
  end
  local Store = ns.Store
  if not (Store and Store.char and Store.char()) then return false end
  if s.combatHide and inCombat() then
    if st.frame then st.frame:Hide() end
    stopTicker()
    return false
  end
  if TodoTracker.hookPlans then TodoTracker.hookPlans() end
  st.shownList = TodoTracker.entries()
  local want = TodoTracker.wanted()
  if want then
    local f = TodoTracker.build()
    if st.style ~= s.style then TodoTracker.applyStyle() st.sig = nil end
    TodoTracker.syncOpen()
    local sig = signature(st.shownList, s.style) .. "\3" .. tostring(f:GetWidth()) .. "x" .. (st.anim and "anim" or tostring(f:GetHeight()))
      .. "\3" .. tostring(st.shape) .. "\3" .. s.open .. "\3" .. s.grow
    if sig ~= st.sig or not f:IsShown() then
      st.sig = sig
      TodoTracker.layout()
    end
    f:Show()
  elseif st.frame then
    st.frame:Hide()
  end
  updateTicker()
  return want
end

-- Automatic show: with the option autoShow (default on) the note opens by itself while to-dos are open. First scan of a session
-- (login/reload): it opens if something is open and the player has not closed it (x, /chronik todo aus, checkbox: "dismissed").
-- Later scans: a to-do id not seen before in this session (a new one, not a re-opened one) opens it again and lifts the
-- dismissal. The collapsed/expanded state is not touched. Returns true if the note was switched on.
function TodoTracker.autoScan()
  if TodoTracker.hookPlans then TodoTracker.hookPlans() end -- listen for changes even while the note is off
  local Store = ns.Store
  if not (Store and Store.char and Store.char()) then return false end
  local P = ns.Plans
  if not P or type(P.list) ~= "function" then return false end
  local list = planList(nil)
  local initial = st.known == nil
  local known, fresh, open = {}, false, 0
  for _, p in ipairs(list) do
    known[p.id] = true
    if not p.done then
      open = open + 1
      if not initial and not st.known[p.id] then fresh = true end
    end
  end
  st.known = known
  local s = TodoTracker.settings()
  if st.preview or not s.autoShow or s.shown or open == 0 or TodoTracker.docked() or TodoTracker.suppressed() then return false end
  if fresh or (initial and not s.dismissed) then
    TodoTracker.setShown(true)
    return true
  end
  return false
end

local pending = false
function TodoTracker.changed()
  if pending then return end
  pending = true
  local function run()
    pending = false
    if ns.Core then ns.Core.safe(TodoTracker.autoScan) else TodoTracker.autoScan() end
    if ns.Core then ns.Core.safe(TodoTracker.refresh) else TodoTracker.refresh() end
  end
  if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end

-- Data source: Plans.onChange, else wrap the changing functions (add/remove/toggle/check) with a batched refresh after the
-- original; plus ns.onPlanDone. Once per Plans table, no ticker needed.
local WRAP = { "add", "remove", "toggle", "check" }
local function hookPlans()
  local P = ns.Plans
  if type(P) ~= "table" or st.hooked == P then return end
  st.hooked = P
  if type(P.onChange) == "function" then
    pcall(P.onChange, TodoTracker.changed)
  else
    for _, name in ipairs(WRAP) do
      local orig = P[name]
      if type(orig) == "function" then
        P[name] = function(...)
          local a, b, c = orig(...)
          TodoTracker.changed()
          return a, b, c
        end
      end
    end
  end
  if not st.doneHook and type(ns.onPlanDone) == "function" then
    st.doneHook = true
    pcall(ns.onPlanDone, TodoTracker.changed)
  end
end
TodoTracker.hookPlans = hookPlans

TodoTracker.listeners = {}

local function syncSettings()
  for _, fn in ipairs(TodoTracker.listeners) do pcall(fn) end
  if TodoTracker.hud and TodoTracker.hud.sync then pcall(TodoTracker.hud.sync) end
end
TodoTracker.syncSettings = syncSettings

function TodoTracker.setShown(on)
  TodoTracker.set("shown", on and true or false)
  TodoTracker.set("dismissed", not on) -- closed by hand (x, slash, checkbox): stays closed until a new to-do arrives
  st.sig = nil
  TodoTracker.refresh()
  syncSettings()
  return on and true or false
end

function TodoTracker.setStyle(style)
  if type(TodoTracker.beforeStyle) == "function" then pcall(TodoTracker.beforeStyle) end
  if not TodoTracker.set("style", style) then return false end
  st.sig = nil
  if st.frame then TodoTracker.applyStyle() TodoTracker.layout() end
  TodoTracker.refresh()

  syncSettings()
  return true
end

function TodoTracker.setOpen(mode)
  if not TodoTracker.set("open", mode) then return false end
  st.sig = nil
  if st.frame then
    TodoTracker.syncOpen()
    TodoTracker.layout()
  end
  TodoTracker.refresh()
  syncSettings()
  return true
end

-- Unfold direction: "down" (head on top, the note rolls out below) | "up" (head stays at the bottom, the note rolls out above it)
function TodoTracker.setGrow(mode)
  if not TodoTracker.set("grow", mode) then return false end
  st.sig = nil
  if st.anim then TodoTracker.finishAnim() end
  if st.frame then
    TodoTracker.place()
    TodoTracker.layout()
  end
  TodoTracker.refresh()
  syncSettings()
  return true
end

function TodoTracker.setLocked(on)
  TodoTracker.set("locked", on and true or false)
  if st.frame then
    paintLock(st.lock)
    st.grip:SetShown(not on)
    if on and (st.frame.moving or st.frame.sizing) then
      st.frame.moving, st.frame.sizing = false, false
      st.frame:StopMovingOrSizing()
      savePos(st.frame)
    end
  end
  syncSettings()
  return on and true or false
end

function TodoTracker.setCombatHide(on)
  TodoTracker.set("combatHide", on and true or false)
  TodoTracker.refresh()
  syncSettings()
end

function TodoTracker.setHideEmpty(on)
  TodoTracker.set("hideEmpty", on and true or false)
  st.sig = nil
  TodoTracker.refresh()
  syncSettings()
end

function TodoTracker.setAutoShow(on)
  TodoTracker.set("autoShow", on and true or false)
  if on then
    st.known = nil -- like a fresh login: open to-dos open the note unless it was closed by hand
    if ns.Core then ns.Core.safe(TodoTracker.autoScan) else TodoTracker.autoScan() end
  end
  syncSettings()
end

function TodoTracker.setDock(on)
  TodoTracker.set("dock", on and true or false)
  st.sig = nil
  TodoTracker.refresh()
  syncSettings()
  return on and true or false
end

function TodoTracker.setDockSide(side)
  if not TodoTracker.set("dockSide", side) then return false end
  if TodoTracker.Dock and TodoTracker.Dock.state then TodoTracker.Dock.state.placed = nil end
  TodoTracker.refresh()
  syncSettings()
  return true
end

function TodoTracker.reset()
  TodoTracker.set("pos", nil)
  TodoTracker.set("size", { w = TodoTracker.DEFAULTS.w, h = TodoTracker.DEFAULTS.h })
  if TodoTracker.hud and TodoTracker.hud.reset then TodoTracker.hud.reset() end
  if st.frame then
    TodoTracker.place()
    st.sig = nil
  end
  TodoTracker.refresh()
end

function TodoTracker.isShown()
  return st.frame ~= nil and st.frame:IsShown() and true or false
end

function TodoTracker.slash(arg)
  arg = type(arg) == "string" and string.lower(arg) or ""
  local Store = ns.Store
  if not (Store and Store.char and Store.char()) then
    say(T.notReady)
    return false
  end
  if TodoTracker.suppressed() then
    say(T.questsSlash) -- the quest tracker holds the to-dos: nothing is written (shown/dismissed/pos stay as they are)
    return false
  end
  if arg == "reset" then
    TodoTracker.reset()
    say(T.reset)
    return true
  end
  local on
  on = ns.Core and ns.Core.onOff(arg)
  if on ~= nil then
  elseif arg == "" then on = not TodoTracker.settings().shown
  else
    say(T.usage)
    return false
  end
  if TodoTracker.docked() then
    TodoTracker.set("shown", on and true or false)
    TodoTracker.set("dismissed", not on)
    syncSettings()
    say(T.dockedSlash)
    return on
  end
  TodoTracker.setShown(on)
  if not on then say(T.off)
  elseif TodoTracker.isShown() then say(T.on)
  else say(T.onEmpty) end
  return on
end

if ns.Core and ns.Core.on then
  ns.Core.on("PLAYER_ENTERING_WORLD", function()
    if ns.Core then ns.Core.safe(TodoTracker.autoScan) else TodoTracker.autoScan() end
    if ns.Core then ns.Core.safe(TodoTracker.refresh) else TodoTracker.refresh() end
  end)
  ns.Core.on("PLAYER_REGEN_DISABLED", function()
    st.inCombat = true
    if TodoTracker.settings().combatHide then TodoTracker.refresh() end
  end)
  ns.Core.on("PLAYER_REGEN_ENABLED", function()
    st.inCombat = false
    if TodoTracker.settings().combatHide then TodoTracker.refresh() end
  end)
end
