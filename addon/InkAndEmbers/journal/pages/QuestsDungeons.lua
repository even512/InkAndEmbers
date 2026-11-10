-- Sub-view "Dungeon-Quests" of the tab Dungeons (pages/Dungeons.lua; until I12 under Quests), WoW Forever only. Data: journal/model/DungeonQuests.lua.
-- Goal: see at a glance which quests a dungeon has, which are done and which are missing, with their prerequisites.
-- First view: left the dungeons (level span, "done/for you"), right ALREADY the quest sheet of the chosen dungeon (the one that
-- fits the character); switch "Quests | Karte" shows the entrances instead. Second level ("Dungeon öffnen", double click, click on
-- a quest of the sheet): left the same sheet, right map and details of the chosen quest.
-- Long chains (a quest line can touch 106 quests; View.flatten): the quests of the dungeon and everything that can be accepted or
-- is in the log stay as rows, everything else of a chain with more than FOLD_FROM quests folds into lines with counts. A click on
-- such a line or on "... und n weitere" opens the chain in one step and jumps to the first hidden row.
-- Quests of the dungeon are told apart from chain additions by a red margin stroke, a stronger font and ink (never by colour alone).
-- Foreign text comes from the model already sanitized and is shown via SetText/AddLine only: as such or as an argument of a fixed
-- template of this file (only sanitized names as arguments of fixed templates, never as the format string); the search text is only
-- compared by the model (plain find). No ticker; OnUpdate only inside Map.lua; rows and pins are pooled.
-- Keep-outs (DecorKeepout quests): left everything ends before y 474 (blot), title from y 72 (wax drop); right everything stays
-- left of x 446 and above y 578.
local _, ns = ...

local Journal = ns.Journal
local W, Pages, DQ, OQ = Journal and Journal.Widgets, Journal and Journal.Pages, Journal and Journal.DungeonQuests, Journal and Journal.OpenQuests
local D = W and W.Diary
if not (W and Pages and DQ and OQ and D) then return end

local floor, max, min = math.floor, math.max, math.min
local Theme = Journal.Theme
local G = Theme.GRID
local GREEN = Theme.INK and Theme.INK.green or "ink"

local View = {}
View.__index = View
Journal.DungeonQuestsView = View

-- texts (German here, English in locales/enUS_pages.lua, scope "p.QuestsDungeons"; read only on build/draw)
local T = ns.Locale.ns("p.QuestsDungeons", {
  brand = "INK & EMBERS", book = "QUESTBUCH", page = "DUNGEON-QUESTS", title = "Dungeons",
  countDungeons = "%s Dungeons", countHidden = "%s ohne Quests für Euch ausgeblendet",
  forMe = "Für mich", all = "Alle", forMeTip = { "Für mich", "Nur Quests, die zu Fraktion, Volk und Klasse passen" },
  allTip = { "Alle", "Auch Dungeons und Quests für andere Fraktionen, Völker und Klassen" },
  searchHint = "Dungeon oder Quest suchen …", searchClear = "Suche leeren",
  levelSpan = "Stufe %s–%s", levelOne = "Stufe %s",
  rel = { fit = "passend", coming = "kommend", below = "darunter" },
  doneOf = "%s/%s", doneOfLong = "%s von %s erledigt",
  nOpen = "%s annehmbar", nLog = "%s im Log", nLocked = "%s gesperrt", nHits = "%s Treffer", noneForYou = "keine für Euch",
  empty = "Kein Dungeon passt zu dieser Suche.", emptySheet = "Für diesen Charakter gibt es hier keine Quests.",
  emptySheetAll = "Unter „Alle“ stehen die Quests anderer Fraktionen und Klassen.",
  noData = "Questdaten nicht geladen", noDataHint = "Prüfen mit /chronik diag",
  noDataRight = "Die Quests erscheinen, sobald die Questdaten geladen sind.",
  showQuests = "Quests", showMap = "Karte", showQuestsTip = { "Quests", "Alle Quests des gewählten Dungeons" },
  showMapTip = { "Karte", "Eingänge der Dungeons; die Zahl nennt die annehmbaren Quests" },
  openDungeon = "Dungeon öffnen", openDungeonTip = { "Dungeon öffnen", "Quests links, Karte und Einzelheiten der gewählten Quest rechts" },
  toEntrance = "Eingang als To Do", toEntranceTip = { "Eingang als To Do", "Legt ein Ort-Ziel am Dungeon-Eingang an (Pläne -> To Do)." },
  todoEntrance = "Dungeon betreten: %s",
  back = "Zur Dungeon-Übersicht", foreign = "Andere Fraktion/Klasse",
  foreignTip = { "Andere Fraktion/Klasse", "Zeigt auch Quests, die dieser Charakter nicht annehmen kann" },
  legend = "Roter Strich, kräftig: Quest dieses Dungeons · blass: Vor- oder Folgequest",
  state = { done = "erledigt", log = "im Log", open = "annehmbar", locked = "gesperrt", foreign = "andere Fraktion/Klasse" },
  lockLevel = "gesperrt · Stufe %s", lockPre = "gesperrt · Vorquest", voided = "entfällt",
  voidTip = "Entfällt, wenn %s erledigt ist", altTip = "Schließt sich mit %s aus",
  chain = "Kette: %s", chainDone = "%s/%s erledigt", chainSeeds = "%s davon gehören zu diesem Dungeon", chainNoSeeds = "Keine davon gehört zu diesem Dungeon",
  chainOpenTip = "Klicken: aufklappen", chainCloseTip = "Klicken: zuklappen",
  singles = "Einzelquests", additions = "Nur Vor- und Folgequests",
  foldPre = "%s Vorquests", foldPost = "%s Folgequests", foldDone = "%s erledigt", foldSeeds = "%s des Dungeons", foldOpen = "aufklappen",
  foldTip = "Klicken: ganze Kette zeigen",
  more = "… und %s weitere (Kette öffnen)", less = "Kette wieder kürzen", moreTip = "Klicken: springt zur ersten ausgelassenen Quest",
  after = "nach: %s", afterAll = " · ", afterAny = " oder ", see = "siehe %s", seeMore = " (+%s)",
  continues = "führt weiter: %s Quests", continuesTip = "Raid- und Gruppenquests ohne Dungeon sind nicht aufgelistet",
  dann = "dann", entweder = "entweder", oder = "oder",
  outside = "draußen · %s", outsideNoZone = "draußen", elsewhere = "gehört zu einem anderen Dungeon",
  rowOpen = "Klicken: Einzelheiten",
  level = "Stufe %s", levelUnknown = "Stufe ?", minLevel = "ab Stufe %s", giverZone = "Geber: %s · %s",
  entrance = "Eingang: %s", entranceTip = "Dungeon-Eingang",
  noEntrance = "Eingang unbekannt", estimated = "Zuordnung geschätzt: %s",
  preAll = "Vorquests (alle nötig)", preAny = "Vorquests (eine genügt)", exclHead = "Entfällt, wenn erledigt", moreLines = "… und %s weitere (Klick zeigt alle)",
  chainStep = "Kette: Schritt %s von %s",
  faction = { Alliance = "Nur Allianz", Horde = "Nur Horde" },
  classes = { WARRIOR = "Krieger", PALADIN = "Paladin", HUNTER = "Jäger", ROGUE = "Schurke", PRIEST = "Priester", SHAMAN = "Schamane",
    MAGE = "Magier", WARLOCK = "Hexenmeister", DRUID = "Druide" },
  races = { Human = "Mensch", Orc = "Orc", Dwarf = "Zwerg", NightElf = "Nachtelf", Scourge = "Untoter", Tauren = "Tauren", Gnome = "Gnom", Troll = "Troll" },
  toTodo = "Als To Do", toTodoTip = { "Als To Do", "Legt ein Ort-Ziel am Questgeber an, beim Geber im Dungeon am Eingang." },
  toTodoOff = { "Als To Do", "Die Quest beginnt mit einem Gegenstand: es gibt keinen Ort." },
  readText = "Questtext lesen", readTextTip = { "Questtext lesen", "Öffnet den Questtext in der Historie" },
  todoDone = "To Do angelegt.", todoEntranceDone = "To Do am Dungeon-Eingang angelegt.", todoFail = "Kein To Do angelegt: ",
  todoReasons = { voll = "To-Do-Liste ist voll", ["nicht-bereit"] = "To Do noch nicht bereit", ["kein-plan"] = "To Do nicht verfügbar",
    ["kein-ort"] = "kein Kartenpunkt", doppelt = "To Do liegt schon vor", ["item-start"] = "Start per Gegenstand", unbekannt = "Quest unbekannt" },
  noMap = "Für dieses Gebiet liefert der Client keine Karte.", unplaced = "%s Eingänge ohne Lage auf dieser Karte",
  pinOpen = "Klicken: Dungeon wählen, noch einmal: öffnen", pinGiver = "Klicken: To Do an diesem Punkt", pinCount = "%s annehmbar",
  partial = "Reise wird noch gelesen: Stand vorläufig", prevPage = "Vorige Seite", nextPage = "Nächste Seite",
})
View.TEXT = T

local LX, LW = Theme.gridX("L")
local RX, RW = Theme.gridX("R")
local TITLE_Y = G.slots.title.y
local TITLE_L_Y = 72 -- wax drop top left (keep-out x 128..196 down to y 72): the left title starts below it, like the quest text
local SUB_Y = TITLE_Y + 34
local BAR_Y = SUB_Y + 15
local CTRL_CY = G.slots.ctrl.y + 12
local BODY_Y = G.slots.body.y
local LEFT_END = 474 -- blot bottom left (keep-out y 478..601) stays free
local LIST_Y = BODY_Y + 34
local DG_ROW_H = 34
local DG_ROWS = floor((LEFT_END - LIST_Y) / DG_ROW_H)
local ROW_H = G.line.row
local PAGE_ROWS = floor((LEFT_END - 14 - BODY_Y) / ROW_H) -- the legend line stays above y 474
local SHEET_ROWS = 16
local LEGEND_R_Y = BODY_Y + SHEET_ROWS * ROW_H + 2
local STICKER_Y = LEGEND_R_Y + 18
local STICKER_H = 36
local MSG_Y = STICKER_Y + STICKER_H + 3
local OVER_MAP_H = 262
local PANEL_Y = BODY_Y + OVER_MAP_H + 8
local QUEST_SUB_Y = TITLE_Y + 24
local PAGE_MAP_Y = QUEST_SUB_Y + 18
local PAGE_MAP_H = 176
local DETAIL_Y = PAGE_MAP_Y + PAGE_MAP_H + 8
local DETAIL_LINE = 16
local DETAIL_MAX = floor((STICKER_Y - DETAIL_Y) / DETAIL_LINE)
local STATION_MAX = 22
local STATION = 9
local PIN, PIN_SEL, PIN_MAX = 18, 26, 60
local INDENT = 12
local STATE_W = 122
local HINT_W = 30
local WHOLE = { x0 = 0, x1 = 1, y0 = 0, y1 = 1 }
local DOUBLE_CLICK = 0.4

View.FOLD_FROM = 12 -- a chain with more quests than this folds what is neither its own nor actionable
View.FOLD_RUN = 2   -- at least this many rows in one fold line
View.DONE_RUN = 3   -- shorter chains: this many done rows in a row fold
View.FOLD_TIP_MAX = 24 -- tooltip of a fold line: this many names at most (all of them below that), then "and n more" + click
View.DG_ROWS, View.PAGE_ROWS, View.SHEET_ROWS, View.DETAIL_MAX = DG_ROWS, PAGE_ROWS, SHEET_ROWS, DETAIL_MAX

local function int(n) return Journal.Texts.int(n) end
local function kit() return Journal.QuestsPage and Journal.QuestsPage.kit end

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function label(parent, kind, size, color, justify)
  local fs = W.font(parent, kind, size, color)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

local function now()
  if type(GetTime) ~= "function" then return 0 end
  local ok, t = pcall(GetTime)
  return ok and num(t) or 0
end

-- the client's localized name of a dungeon (key = area ID) before the name of the data table
local areaNames = {}
local function dungeonName(dg)
  local key = dg and dg.key
  if not key then return "" end
  local name = areaNames[key]
  if name == nil then
    name = false
    local id = tonumber(key)
    if id and type(C_Map) == "table" and type(C_Map.GetAreaInfo) == "function" then
      local ok, s = pcall(C_Map.GetAreaInfo, id)
      if ok and type(s) == "string" and not isSecret(s) and ns.Sanitize then name = ns.Sanitize.display(s, DQ.NAME_MAX) or false end
    end
    areaNames[key] = name
  end
  return name or dg.name or key
end
View.dungeonName = dungeonName

local function levelText(dg)
  if dg.minLevel == dg.maxLevel then return T("levelOne", int(dg.minLevel)) end
  return T("levelSpan", int(dg.minLevel), int(dg.maxLevel))
end

-- ---------------------------------------------------------------- state marks (shared by rows and detail lines)

local function newMarks(parent)
  local m = {}
  m.done = D.mark(parent, "tick", 18, GREEN)
  m.log = D.mark(parent, "arrow", 13, "blue")
  m.open = parent:CreateTexture(nil, "ARTWORK")
  m.open:SetTexture(Theme.TEX.questMark)
  m.open:SetSize(15, 15)
  m.locked = parent:CreateTexture(nil, "ARTWORK")
  m.locked:SetTexture(Theme.TEX.todoMarks)
  m.locked:SetTexCoord(Theme.todoMarkCoords("locked"))
  m.locked:SetVertexColor(W.color("sepia", 0.85))
  m.locked:SetSize(13, 13)
  m.foreign = W.NewRect(parent, "sepia", 0.55, "ARTWORK")
  m.foreign:SetSize(9, 2)
  m.down = D.mark(parent, "down", 13, "ink")
  m.closed = D.mark(parent, "next", 13, "ink")
  m.all = { m.done, m.log, m.open, m.locked, m.foreign, m.down, m.closed }
  for _, t in ipairs(m.all) do t:Hide() end
  return m
end

-- show the mark of a state, centred on (x, parent's vertical centre)
local function showMark(m, kind, parent, x)
  for _, t in ipairs(m.all) do t:Hide() end
  local t = kind and m[kind]
  if not t then return end
  t:ClearAllPoints()
  t:SetPoint("CENTER", parent, "LEFT", x, kind == "done" and 1 or 0)
  t:Show()
end

-- ---------------------------------------------------------------- long chains: the rows of a dungeon sheet

local function questRowCount(rows)
  local n = 0
  for _, r in ipairs(rows) do
    if not r.ref then n = n + 1 end
  end
  return n
end

local function foldCounts(run)
  local c = { done = 0, log = 0, open = 0, locked = 0, foreign = 0, seeds = 0 }
  for _, r in ipairs(run) do
    c[r.state] = (c[r.state] or 0) + 1
    if r.seed then c.seeds = c.seeds + 1 end
  end
  return c
end

-- prefix mark of a row: "dann"/"entweder" on the first follow-up of a fork, "oder" on rows that exclude another one
local function prefixOf(res, row)
  local p = row.parent and res.byId[row.parent]
  if p and p.fork and p.firstChild == row.id then return p.fork.kind == "either" and "entweder" or "dann" end
  if row.alt and #row.alt > 0 then return "oder" end
  return nil
end

local function nameOfId(res, id)
  local r = res.byId and res.byId[id]
  return r and r.name or tostring(id)
end

-- names of quests, variants of one quest (same name for each faction or class) as "name ×3"
local function namesOf(res, ids)
  local order, count = {}, {}
  for _, id in ipairs(ids or {}) do
    local name = nameOfId(res, id)
    if not count[name] then
      count[name] = 0
      order[#order + 1] = name
    end
    count[name] = count[name] + 1
  end
  local out = {}
  for _, name in ipairs(order) do
    out[#out + 1] = count[name] > 1 and (name .. " ×" .. int(count[name])) or name
  end
  return out
end

local function afterText(res, row)
  local text = table.concat(namesOf(res, row.after), row.afterMode == "any" and T.afterAny or T.afterAll)
  if row.afterAny and #row.afterAny > 0 then
    text = text .. T.afterAll .. table.concat(namesOf(res, row.afterAny), T.afterAny)
  end
  return T("after", text)
end

local function emitQuest(out, res, chainKey, row, withAfter)
  out[#out + 1] = { kind = "quest", row = row, chainKey = chainKey, prefix = prefixOf(res, row) }
  if withAfter and row.after then
    out[#out + 1] = { kind = "note", text = afterText(res, row), indent = (row.indent or 0) + 1, row = row }
  end
end

-- the items of one chain; state[chain.id] = "closed" | "open" | "full" (nil: closed when done or without a quest of the dungeon)
-- dense (first view): no "after ..." and "see ..." lines, they stay in the tooltip and on the dungeon page
local function chainItems(out, res, c, state, dense)
  local quests = questRowCount(c.all)
  local seeds = 0
  for _, r in ipairs(c.all) do
    if not r.ref and r.seed then seeds = seeds + 1 end
  end
  local st = state[c.id]
  if st == nil then st = (c.collapsed or seeds == 0) and "closed" or "open" end
  out[#out + 1] = { kind = "chain", chain = c, seeds = seeds, closed = st == "closed", quests = quests }
  if st == "closed" then return end
  local full = st == "full"
  local compact = not full and quests > View.FOLD_FROM
  -- sequence: quest rows and groups of reference rows ("see ...": consecutive ones of the same quest make one line)
  local seq, lastSeed = {}, 0
  for _, r in ipairs(c.all) do
    if r.ref then
      local last = seq[#seq]
      if last and last.refs and last.of == r.of then
        last.refs[#last.refs + 1] = r.id
      else
        seq[#seq + 1] = { refs = { r.id }, of = r.of, indent = r.indent }
      end
    else
      seq[#seq + 1] = { row = r }
      if r.seed then lastSeed = #seq end
    end
  end
  local function foldable(row)
    if full then return false end
    if row.state == "done" then return true end
    -- long chains: what this character can do something about stays; other factions' variants of a quest fold even when they are its own
    if not compact then return false end
    if row.state == "foreign" then return true end
    return not row.seed and row.state ~= "open" and row.state ~= "log"
  end
  local shown = 0
  local start = #out + 1
  local i = 1
  while i <= #seq do
    local e = seq[i]
    if e.refs then
      if not compact and not dense then
        local first = nameOfId(res, e.refs[1])
        local text = T("see", first)
        if #e.refs > 1 then text = text .. T("seeMore", int(#e.refs - 1)) end
        out[#out + 1] = { kind = "note", text = text, indent = e.indent, refs = e.refs }
      end
      i = i + 1
    elseif foldable(e.row) then
      local run, j, onlyDone = {}, i, true
      while j <= #seq do
        local x = seq[j]
        if x.refs then
          j = j + 1
        elseif foldable(x.row) then
          run[#run + 1] = x.row
          if x.row.state ~= "done" then onlyDone = false end
          j = j + 1
        else
          break
        end
      end
      local need = (compact and not onlyDone) and View.FOLD_RUN or View.DONE_RUN
      if #run >= need then
        out[#out + 1] = { kind = "fold", chainKey = c.id, rows = run, n = #run, counts = foldCounts(run), onlyDone = onlyDone,
          pre = i < lastSeed, first = run[1].id, indent = run[1].indent }
        i = j
      else
        emitQuest(out, res, c.id, e.row, not compact and not dense)
        shown = shown + 1
        i = i + 1
      end
    else
      emitQuest(out, res, c.id, e.row, not compact and not dense)
      shown = shown + 1
      i = i + 1
    end
  end
  if full then
    if quests > View.FOLD_FROM then out[#out + 1] = { kind = "less", chainKey = c.id } end
    return
  end
  -- lid: at most CHAIN_MAX quest rows; the rest (with the folded ones) is one click away
  if quests > DQ.CHAIN_MAX then
    local kept, cut, firstHidden = 0, nil, nil
    for k = start, #out do
      if out[k].kind == "quest" then
        kept = kept + 1
        if kept > DQ.CHAIN_MAX and not cut then
          cut = k
          firstHidden = out[k].row.id
        end
      end
    end
    if cut then
      for k = #out, cut, -1 do out[k] = nil end
      kept = DQ.CHAIN_MAX
    else
      for k = start, #out do
        if out[k].kind == "fold" then firstHidden = out[k].first break end
      end
    end
    if quests > kept then
      out[#out + 1] = { kind = "more", chainKey = c.id, n = quests - kept, first = firstHidden }
    end
  end
end

-- quests() result -> flat list for the sheet: chains with quests of the dungeon, single quests of the dungeon, then what only came
-- along with a chain. state = per chain id "closed" | "open" | "full".
function View.flatten(res, state, dense)
  local out = {}
  state = type(state) == "table" and state or {}
  local later = {}
  for _, c in ipairs(res.chains or {}) do
    local has = false
    for _, r in ipairs(c.all) do
      if not r.ref and r.seed then has = true break end
    end
    if has then chainItems(out, res, c, state, dense) else later[#later + 1] = c end
  end
  local own, other = {}, {}
  for _, r in ipairs(res.singles or {}) do
    if r.seed then own[#own + 1] = r else other[#other + 1] = r end
  end
  if #own > 0 then
    local done = 0
    for _, r in ipairs(own) do
      if r.state == "done" then done = done + 1 end
    end
    out[#out + 1] = { kind = "section", text = T.singles, right = T("doneOf", int(done), int(#own)) }
    for _, r in ipairs(own) do emitQuest(out, res, nil, r, false) end
  end
  if #later > 0 or #other > 0 then
    out[#out + 1] = { kind = "section", text = T.additions }
    for _, c in ipairs(later) do chainItems(out, res, c, state, dense) end
    for _, r in ipairs(other) do emitQuest(out, res, nil, r, false) end
  end
  if (res.continues or 0) > 0 then
    out[#out + 1] = { kind = "note", text = T("continues", int(res.continues)), indent = 0, tip = T.continuesTip }
  end
  return out
end

local function indexOfQuest(items, id)
  for i, it in ipairs(items or {}) do
    if it.kind == "quest" and it.row.id == id then return i end
  end
  return nil
end

-- ---------------------------------------------------------------- row of a sheet

local HINT_MARK = { unsure = "?", estimated = "~", giverInside = "^", giverNone = "i", notChecked = "i", raceUnsure = "i", foreverNew = "*", learned = "+" }

local function hintMarks(notes)
  local seen, out = {}, {}
  for _, n in ipairs(notes or {}) do
    local m = HINT_MARK[n.kind]
    if m and not seen[m] then
      seen[m] = true
      out[#out + 1] = m
    end
  end
  return table.concat(out, " ")
end
View.hintMarks = hintMarks

local function stateText(res, row)
  if row.state == "locked" then
    local r = row.reasons and row.reasons[1]
    if r and r.kind == "level" then return T("lockLevel", int(r.need or 0)) end
    if r and r.kind == "prequest" then return T.lockPre end
    if r and r.kind == "exclusive" then return T.voided end
    return T.state.locked
  end
  if row.state == "foreign" then
    local r = row.reasons and row.reasons[1]
    return r and r.text or T.state.foreign
  end
  return T.state[row.state] or ""
end
View.stateText = stateText

local function stateColor(state)
  if state == "done" then return GREEN end
  if state == "log" then return "blue" end
  if state == "open" then return "red" end
  return "sepia"
end

local function rowTip(self, res, row)
  local tip = { row.name }
  tip[#tip + 1] = row.level and T("level", int(row.level)) or T.levelUnknown
  if row.minLevel and row.minLevel > 0 then tip[#tip + 1] = T("minLevel", int(row.minLevel)) end
  tip[#tip + 1] = T.state[row.state] or ""
  for _, r in ipairs(row.reasons or {}) do tip[#tip + 1] = r.text end
  if row.outside then
    tip[#tip + 1] = row.zone and T("outside", row.zone) or T.outsideNoZone
    if row.elsewhere then tip[#tip + 1] = T.elsewhere end
  end
  if row.after then tip[#tip + 1] = afterText(res, row) end
  for _, x in ipairs(row.alt or {}) do
    local s = res.byId[x]
    local gone = s and (s.state == "done" or s.state == "log")
    tip[#tip + 1] = T(gone and "voidTip" or "altTip", nameOfId(res, x))
  end
  for _, n in ipairs(row.notes or {}) do
    tip[#tip + 1] = n.tip and (n.text .. ": " .. n.tip) or n.text
  end
  return tip
end

local function clearParts(row)
  row:SetSelected(false)
  row.tipLines = nil
  row.seedBar:Hide()
  row.headBg:Hide()
  row.deep:Hide()
  W.setText(row.label, "")
  W.setText(row.hand, "")
  W.setText(row.state, "")
  W.setText(row.hint, "")
  showMark(row.marks, nil, row)
  row.label:SetTextColor(W.color("ink"))
end

-- fill: quest row. Indentation + state mark + (prefix in handwriting) + name · zone; right the hint marks and the state in words.
local function fillQuest(self, row, it, res)
  local q = it.row
  local x = 9 + (q.indent or 0) * INDENT
  showMark(row.marks, q.state, row, x)
  row.seedBar:SetShown(q.seed == true)
  if q.deep then
    row.deep:ClearAllPoints()
    row.deep:SetPoint("LEFT", row, "LEFT", x - 11, 0)
    row.deep:Show()
  end
  local nameX = x + 11
  local hand = it.prefix and T[it.prefix] or ""
  W.setText(row.hand, hand)
  if hand ~= "" then
    row.hand:ClearAllPoints()
    row.hand:SetPoint("LEFT", row, "LEFT", nameX, 0)
    nameX = nameX + (it.prefix == "entweder" and 52 or it.prefix == "dann" and 30 or 28)
  end
  row.label:ClearAllPoints()
  row.label:SetPoint("LEFT", row, "LEFT", nameX, 0)
  row.label:SetWidth(max(60, row:GetWidth() - nameX - STATE_W - HINT_W - 6))
  if q.seed then
    pcall(row.label.SetFont, row.label, W.FONT.text, 13, "")
  else
    pcall(row.label.SetFont, row.label, W.FONT.label, G.size.s, "")
  end
  local name = q.name
  if q.outside and q.zone then name = name .. " · " .. q.zone end
  W.setText(row.label, name)
  local grey = q.state == "locked" or q.state == "foreign"
  local alpha = q.state == "foreign" and 0.6 or (grey and 0.8 or 1)
  row.label:SetTextColor(W.color(q.seed and "ink" or "sepia", q.seed and alpha or alpha * 0.9))
  W.setText(row.state, stateText(res, q))
  row.state:SetTextColor(W.color(stateColor(q.state), q.state == "foreign" and 0.7 or 1))
  W.setText(row.hint, hintMarks(q.notes))
  row:SetSelected(q.id == self.sel and self.level == 2)
  local tip = rowTip(self, res, q)
  tip[#tip + 1] = T.rowOpen
  row.tipLines = tip
end

local function foldLine(it)
  if it.onlyDone then return T("foldDone", int(it.n)) end
  local c = it.counts
  local parts = {}
  if c.done > 0 then parts[#parts + 1] = int(c.done) .. " " .. T.state.done end
  if c.locked > 0 then parts[#parts + 1] = int(c.locked) .. " " .. T.state.locked end
  if c.foreign > 0 then parts[#parts + 1] = int(c.foreign) .. " " .. T.state.foreign end
  if c.seeds > 0 then parts[#parts + 1] = T("foldSeeds", int(c.seeds)) end
  local head = T(it.pre and "foldPre" or "foldPost", int(it.n))
  return #parts > 0 and (head .. ": " .. table.concat(parts, " · ")) or head
end
View.foldLine = foldLine

-- tooltip of a fold line: the head, then every folded name in chain order (up to FOLD_TIP_MAX; no name is dropped silently), then
-- "and n more" with the click hint if the run is longer
function View.foldTipLines(it)
  local tip = { foldLine(it) }
  local rows = it.rows or {}
  local cap = View.FOLD_TIP_MAX
  for i = 1, min(#rows, cap) do tip[#tip + 1] = rows[i].name end
  if #rows > cap then tip[#tip + 1] = T("moreLines", int(#rows - cap)) end
  tip[#tip + 1] = T.foldTip
  return tip
end

local function fillItem(self, row, it, res)
  if it.kind == "quest" then
    fillQuest(self, row, it, res)
  elseif it.kind == "chain" then
    row.headBg:Show()
    showMark(row.marks, it.closed and "closed" or "down", row, 9)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", 20, 0)
    row.label:SetWidth(row:GetWidth() - 20 - STATE_W - 4)
    pcall(row.label.SetFont, row.label, W.FONT.title, G.size.m, "")
    W.setText(row.label, T("chain", it.chain.name))
    row.label:SetTextColor(W.color("ink"))
    local n = it.chain.counts
    W.setText(row.state, T("chainDone", int(n.done), int(n.total)))
    row.state:SetTextColor(W.color(n.complete and GREEN or "sepia"))
    row.tipLines = { T("chain", it.chain.name), T("chainDone", int(n.done), int(n.total)),
      it.seeds > 0 and T("chainSeeds", int(it.seeds)) or T.chainNoSeeds, it.closed and T.chainOpenTip or T.chainCloseTip }
  elseif it.kind == "fold" then
    local x = 9 + (it.indent or 0) * INDENT
    showMark(row.marks, it.onlyDone and "done" or "closed", row, x)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", x + 11, 0)
    row.label:SetWidth(max(60, row:GetWidth() - x - 11 - 64))
    pcall(row.label.SetFont, row.label, W.FONT.label, G.size.s, "")
    W.setText(row.label, foldLine(it))
    row.label:SetTextColor(W.color("sepia"))
    W.setText(row.state, T.foldOpen)
    row.state:SetTextColor(W.color("blue"))
    row.tipLines = View.foldTipLines(it)
  elseif it.kind == "more" or it.kind == "less" then
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", 20, 0)
    row.label:SetWidth(row:GetWidth() - 24)
    pcall(row.label.SetFont, row.label, W.FONT.text, 13, "")
    W.setText(row.label, it.kind == "more" and T("more", int(it.n)) or T.less)
    row.label:SetTextColor(W.color("blue"))
    if it.kind == "more" then row.tipLines = { T("more", int(it.n)), T.moreTip } end
  elseif it.kind == "section" then
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.label:SetWidth(row:GetWidth() - STATE_W - 8)
    pcall(row.label.SetFont, row.label, W.FONT.title, G.size.m, "")
    W.setText(row.label, it.text)
    row.label:SetTextColor(W.color("red"))
    W.setText(row.state, it.right or "")
    row.state:SetTextColor(W.color("sepia"))
  elseif it.kind == "note" then
    local x = 20 + (it.indent or 0) * INDENT
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", x, 0)
    row.label:SetWidth(max(60, row:GetWidth() - x - 4))
    pcall(row.label.SetFont, row.label, W.FONT.label, G.size.xs, "")
    W.setText(row.label, it.text)
    row.label:SetTextColor(W.color("sepia", 0.9))
    local tip = { it.text }
    if it.tip then tip[2] = it.tip end
    for _, id in ipairs(it.refs or {}) do tip[#tip + 1] = nameOfId(res, id) end
    row.tipLines = tip
  end
  D.rowFilled(row)
end

local function newSheet(self, parent, x, y, width, rows)
  local list = W.NewList(parent, { rows = rows, rowHeight = ROW_H, width = width + 10, step = 3, empty = T.emptySheet, emptyHand = true,
    build = function(row)
      row.headBg = W.NewRect(row, "sepia", 0.1, "BACKGROUND")
      row.headBg:SetAllPoints(row)
      row.seedBar = W.NewRect(row, "red", 0.8, "ARTWORK")
      row.seedBar:SetSize(3, ROW_H - 6)
      row.seedBar:SetPoint("LEFT", row, "LEFT", 0, 0)
      row.deep = label(row, "label", G.size.xs, "sepia")
      row.deep:SetText("»")
      row.marks = newMarks(row)
      row.hand = D.font(row, "hand", 15, "red")
      row.hand:SetWordWrap(false)
      row.state = label(row, "label", G.size.xs, "sepia", "RIGHT")
      row.state:SetWidth(STATE_W)
      row.state:SetPoint("RIGHT", row, "RIGHT", -3, 0)
      row.hint = label(row, "label", G.size.xs, "sepia", "RIGHT")
      row.hint:SetAlpha(0.75)
      row.hint:SetWidth(HINT_W)
      row.hint:SetPoint("RIGHT", row.state, "LEFT", -2, 0)
      D.RowStyle(row, { texts = { row.label, row.state } })
      row:HookScript("OnEnter", function(r) if r.tipLines then W.tip(r, r.tipLines) end end)
      row:HookScript("OnLeave", function(r) W.hideTip(r) end)
    end,
    clear = clearParts,
    fill = function(row, it) fillItem(self, row, it, self.res) end,
    onClick = function(it, idx) self:OnItem(it, idx) end })
  list.frame:ClearAllPoints()
  list.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  return list
end

-- ---------------------------------------------------------------- progress bar (filled rects; numbers stand next to it)

local function newBar(parent, x, y, width)
  local bar = { width = width }
  bar.bg = W.NewRect(parent, "sepia", 0.22, "ARTWORK")
  bar.bg:SetSize(width, 4)
  bar.bg:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  bar.done = W.NewRect(parent, GREEN, 0.9, "ARTWORK")
  bar.done:SetHeight(4)
  bar.done:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  bar.active = W.NewRect(parent, "gold", 0.9, "ARTWORK")
  bar.active:SetHeight(4)
  bar.active:SetPoint("TOPLEFT", bar.done, "TOPRIGHT", 0, 0)
  function bar:Set(n)
    local total = n and n.total or 0
    local dw = total > 0 and floor(self.width * n.done / total + 0.5) or 0
    local aw = total > 0 and floor(self.width * ((n.log or 0) + (n.open or 0)) / total + 0.5) or 0
    self.done:SetWidth(max(dw, 1))
    self.done:SetShown(dw > 0)
    self.active:SetWidth(max(aw, 1))
    self.active:SetShown(aw > 0)
  end
  function bar:SetShown(on)
    self.bg:SetShown(on)
    if not on then
      self.done:Hide()
      self.active:Hide()
    end
  end
  return bar
end

local function summary(n)
  local parts = { T("doneOfLong", int(n.done), int(n.total)) }
  if (n.open or 0) > 0 then parts[#parts + 1] = T("nOpen", int(n.open)) end
  if (n.log or 0) > 0 then parts[#parts + 1] = T("nLog", int(n.log)) end
  if (n.locked or 0) > 0 then parts[#parts + 1] = T("nLocked", int(n.locked)) end
  return table.concat(parts, " · ")
end

-- ---------------------------------------------------------------- map with pins

local function newMap(self, parent, y, height)
  local Map = Journal.Map
  local m = Map.create(parent, RX, y, RW, height, { noteMax = 0 })
  local o = { m = m, h = height, data = {} }
  m.onView = function() W.call(function() self:PlacePins(o) end) end
  m.onBack = function() return Map.resetView(m) end
  local layer = CreateFrame("Frame", nil, m.content)
  layer:SetAllPoints(m.content)
  if layer.SetFrameLevel and m.content.GetFrameLevel then layer:SetFrameLevel(m.content:GetFrameLevel() + 6) end
  o.layer = layer
  o.pins = W.Pool(function()
    local b = CreateFrame("Button", nil, layer)
    b:SetSize(PIN, PIN)
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetTexture(Theme.TEX.glow)
    b.glow:SetVertexColor(W.color("gold", 0.9))
    b.glow:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.glow:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.count = label(b, "title", G.size.xs, "parchment", "CENTER")
    b.count:SetPoint("CENTER", b, "CENTER", 0, 0)
    b:SetScript("OnEnter", function(f) if f.tipLines then W.tip(f, f.tipLines) end end)
    b:SetScript("OnLeave", function(f) W.hideTip(f) end)
    b:SetScript("OnClick", function(f) W.call(function() self:ClickPin(f.data) end) end)
    if b.EnableMouseWheel then b:EnableMouseWheel(true) end
    b:SetScript("OnMouseWheel", function(_, delta) W.call(function() Map.wheel(m, delta) end) end)
    return b
  end, function(b)
    W.hideTip(b)
    b.tipLines, b.data = nil, nil
  end, PIN_MAX)
  o.note = label(parent, "text", G.size.s, "sepia", "CENTER")
  o.note:SetWidth(RW - 40)
  o.note:SetPoint("CENTER", m.viewport, "CENTER", 0, 0)
  return o
end

function View:PlacePins(o)
  o.pins:ReleaseAll()
  local m = o.m
  if not (self.open and m and m.T) then return end
  local Map = Journal.Map
  for _, p in ipairs(o.data or {}) do
    local px, py = Map.toPixel(m.T, p.x, p.y)
    if px >= -PIN and py >= 0 and px <= RW + PIN and py <= o.h + PIN then
      local b = o.pins:Acquire()
      if not b then break end
      local size = p.sel and PIN_SEL or PIN
      b:SetSize(size, size)
      b.glow:SetSize(size * 2.2, size * 2.2)
      b.glow:SetShown(p.sel == true)
      if p.kind == "giver" then
        b.icon:SetTexture(Theme.TEX.questMark)
        b.icon:SetVertexColor(1, 1, 1, 1)
        b.count:SetText("")
      else
        b.icon:SetTexture(Theme.TEX.disc)
        b.icon:SetVertexColor(W.color("ink", 0.95))
        b.count:SetText(p.count and p.count > 0 and (p.count > 99 and "99+" or tostring(p.count)) or "")
      end
      b.data = p
      b.tipLines = p.tip
      if b.SetFrameLevel and o.layer.GetFrameLevel then b:SetFrameLevel(o.layer:GetFrameLevel() + (p.sel and 3 or 1)) end
      b:ClearAllPoints()
      if p.kind == "giver" then
        b:SetPoint("BOTTOM", m.content, "TOPLEFT", px, -py + 2) -- the foot of the ! stands on the giver
      else
        b:SetPoint("CENTER", m.content, "TOPLEFT", px, -py)
      end
    end
  end
end

local function renderMap(o, mapID, continent)
  local Map, Vw, OV = Journal.Map, Journal.View, Journal.OpenQuestsView
  local art = mapID and OV and OV.artOf and OV.artOf(mapID) or nil
  local scene = continent and { mode = "continent", contID = mapID, key = "dq:c:" .. tostring(mapID), focus = WHOLE }
    or { mode = "zone", zoneID = mapID, key = "dq:z:" .. tostring(mapID), focus = WHOLE }
  local aspect = (not art and Vw and Vw.mapAspect) and Vw.mapAspect(mapID) or nil
  Map.render(o.m, scene, { art = art, aspect = aspect, clip = not continent and WHOLE or nil, color = Vw and Vw.peek and Vw.peek("mapColor") or nil,
    reduceMotion = Vw and Vw.peek and Vw.peek("reduceMotion") or nil, showKills = false, pad = 6, keepView = true })
  return art ~= nil
end

-- ---------------------------------------------------------------- building

local function buildOverview(self, tab, tabR)
  local ui = self.ui
  local f = CreateFrame("Frame", nil, tab)
  f:SetAllPoints(tab)
  ui.overL = f
  ui.title = label(f, "title", G.size.l, "ink")
  ui.title:SetPoint("TOPLEFT", f, "TOPLEFT", LX, -TITLE_L_Y)
  ui.title:SetText(T.title)
  ui.count = label(f, "label", G.size.s, "sepia")
  ui.count:SetWidth(LW)
  ui.count:SetPoint("TOPLEFT", f, "TOPLEFT", LX, -SUB_Y)
  ui.scope = D.NewToggle(f, { size = G.size.m, gap = 14, items = { { key = "me", label = T.forMe, tip = T.forMeTip }, { key = "all", label = T.all, tip = T.allTip } },
    onChange = function(key) self:SetAll(key == "all") end })
  ui.scope.frame:SetPoint("LEFT", f, "TOPLEFT", LX, -CTRL_CY)
  -- search box: Dungeon or quest name; own input, only compared by the model
  local sb = CreateFrame("EditBox", nil, f)
  sb:SetSize(LW, 24)
  sb:SetPoint("TOPLEFT", f, "TOPLEFT", LX, -BODY_Y)
  sb:SetAutoFocus(false)
  sb:SetMaxLetters(DQ.SEARCH_MAX)
  sb:SetTextInsets(8, 26, 0, 0)
  pcall(sb.SetFont, sb, W.FONT.text, G.size.m, "")
  sb:SetTextColor(W.color("ink"))
  sb.edge = W.NewOutline(sb, LW, 24, "sepia", 0.6)
  sb.edge:SetAllPoints(sb)
  sb.hint = D.font(sb, "text", G.size.m, "sepia")
  sb.hint:SetPoint("LEFT", sb, "LEFT", 8, 0)
  sb.hint:SetText(T.searchHint)
  sb.hint:SetAlpha(0.7)
  sb:SetScript("OnTextChanged", function(box)
    local text = box:GetText()
    local empty = type(text) ~= "string" or text == ""
    box.hint:SetShown(empty)
    ui.clear:SetShown(not empty)
    W.call(self.SetSearch, self, empty and "" or text)
  end)
  sb:SetScript("OnEnterPressed", function(box)
    box:ClearFocus()
    if self.key then W.call(self.OpenDungeon, self, self.key) end
  end)
  sb:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
  ui.search = sb
  local clear = CreateFrame("Button", nil, sb)
  clear:SetSize(20, 20)
  clear:SetPoint("RIGHT", sb, "RIGHT", -3, 0)
  clear.x = D.font(clear, "label", 18, "sepia")
  clear.x:SetPoint("CENTER", clear, "CENTER", 0, 1)
  clear.x:SetText("×")
  clear:SetScript("OnClick", function() sb:SetText("") sb:ClearFocus() end)
  clear:SetScript("OnEnter", function(b) b.x:SetTextColor(W.color("red")) W.tip(b, { T.searchClear }) end)
  clear:SetScript("OnLeave", function(b) b.x:SetTextColor(W.color("sepia")) W.hideTip(b) end)
  clear:Hide()
  ui.clear = clear
  -- dungeon rows: name + "done/for you" + tick, below level span and what is missing
  local nameW = LW - 22 - 66
  ui.dgList = W.NewList(f, { rows = DG_ROWS, rowHeight = DG_ROW_H, width = LW + 10, step = 3, empty = T.empty, emptyHand = true,
    build = function(row)
      row.label:ClearAllPoints()
      row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -3)
      row.label:SetWidth(nameW)
      pcall(row.label.SetFont, row.label, W.FONT.text, G.size.m, "")
      row.frac = label(row, "title", G.size.m, "ink", "RIGHT")
      row.frac:SetWidth(50)
      row.frac:SetPoint("TOPRIGHT", row, "TOPRIGHT", -22, -3)
      row.tick = D.mark(row, "tick", 18, GREEN)
      row.tick:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -1)
      row.lvl = label(row, "label", G.size.xs, "sepia")
      row.lvl:SetWidth(170)
      row.lvl:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -19)
      row.miss = label(row, "label", G.size.xs, "sepia", "RIGHT")
      row.miss:SetWidth(LW - 180)
      row.miss:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -19)
      D.RowStyle(row, { texts = { row.label, row.frac } })
      row:HookScript("OnEnter", function(r) if r.tipLines then W.tip(r, r.tipLines) end end)
      row:HookScript("OnLeave", function(r) W.hideTip(r) end)
    end,
    clear = function(row)
      row:SetSelected(false)
      row.frac:SetText("")
      row.lvl:SetText("")
      row.miss:SetText("")
      row.tick:Hide()
      row.tipLines = nil
      row.label:SetTextColor(W.color("ink"))
    end,
    fill = function(row, dg)
      local name = dungeonName(dg)
      W.setText(row.label, name)
      row.label:SetTextColor(W.color(dg.empty and "sepia" or "ink", dg.empty and 0.7 or 1))
      row.frac:SetText(T("doneOf", int(dg.done), int(dg.total)))
      row.frac:SetTextColor(W.color(dg.empty and "sepia" or (dg.complete and GREEN or "ink"), dg.empty and 0.7 or 1))
      row.tick:SetShown(dg.complete == true)
      local rel = T.rel[dg.levelRel] or ""
      W.setText(row.lvl, levelText(dg) .. " · " .. rel)
      row.lvl:SetTextColor(W.color(dg.levelRel == "fit" and GREEN or "sepia", dg.levelRel == "below" and 0.75 or 1))
      local miss = {}
      if (dg.hits or 0) > 0 then miss[#miss + 1] = T("nHits", int(dg.hits)) end
      if dg.empty then miss[#miss + 1] = T.noneForYou end
      if dg.open > 0 then miss[#miss + 1] = T("nOpen", int(dg.open)) end
      if dg.log > 0 then miss[#miss + 1] = T("nLog", int(dg.log)) end
      if dg.locked > 0 then miss[#miss + 1] = T("nLocked", int(dg.locked)) end
      W.setText(row.miss, table.concat(miss, " · "))
      row:SetSelected(dg.key == self.key)
      local tip = { name, levelText(dg) .. " · " .. rel, T("doneOfLong", int(dg.done), int(dg.total)) }
      if (dg.estimated or 0) > 0 then tip[#tip + 1] = T("estimated", int(dg.estimated)) end
      tip[#tip + 1] = T.openDungeonTip[2]
      row.tipLines = tip
      D.rowFilled(row)
    end,
    onClick = function(dg) self:ClickDungeon(dg.key) end })
  ui.dgList.frame:ClearAllPoints()
  ui.dgList.frame:SetPoint("TOPLEFT", f, "TOPLEFT", LX, -LIST_Y)
  local K = kit()
  if K and K.pager then ui.dgPager = K.pager(f, ui.dgList, LX, LW, CTRL_CY, { T.prevPage, T.nextPage }) end
  D.escKeys(f, function() Pages.escape(self.page.id or "dungeons") end) -- Esc -> "Durchläufe", the first sub-bookmark

  -- right page: the quests of the chosen dungeon at once
  local r = CreateFrame("Frame", nil, tabR)
  r:SetAllPoints(tabR)
  ui.overR = r
  ui.dgTitle = label(r, "title", G.size.xl, "ink")
  ui.dgTitle:SetPoint("TOPLEFT", r, "TOPLEFT", RX, -TITLE_Y)
  ui.dgTitle:SetWidth(RW)
  ui.dgSum = label(r, "label", G.size.s, "ink")
  ui.dgSum:SetWidth(RW)
  ui.dgSum:SetPoint("TOPLEFT", r, "TOPLEFT", RX, -SUB_Y)
  ui.dgBar = newBar(r, RX, BAR_Y, RW)
  ui.mode = D.NewToggle(r, { size = G.size.m, gap = 14, items = { { key = "quests", label = T.showQuests, tip = T.showQuestsTip }, { key = "map", label = T.showMap, tip = T.showMapTip } },
    onChange = function(key) self:SetMode(key) end })
  ui.mode.frame:SetPoint("LEFT", r, "TOPLEFT", RX, -CTRL_CY)
  ui.sheet = newSheet(self, r, RX, BODY_Y, RW, SHEET_ROWS)
  if K and K.pager then ui.sheetPager = K.pager(r, ui.sheet, RX, RW, CTRL_CY, { T.prevPage, T.nextPage }) end
  ui.legendR = label(r, "label", G.size.xs, "sepia")
  ui.legendR:SetWidth(RW)
  ui.legendR:SetPoint("TOPLEFT", r, "TOPLEFT", RX, -LEGEND_R_Y)
  ui.legendR:SetText(T.legend)
  local items = {}
  for _, c in ipairs(OQ.continents()) do items[#items + 1] = { key = c.id, label = c.name } end
  ui.cont = D.NewToggle(r, { items = items, size = 13, gap = 14, onChange = function(key) self:SetContinent(key) end })
  ui.cont.frame:SetPoint("RIGHT", r, "TOPLEFT", RX + RW, -CTRL_CY)
  ui.panelName = label(r, "title", G.size.m, "ink")
  ui.panelName:SetWidth(RW)
  ui.panelName:SetPoint("TOPLEFT", r, "TOPLEFT", RX, -PANEL_Y)
  ui.panelEntr = label(r, "label", G.size.xs, "sepia")
  ui.panelEntr:SetWidth(RW)
  ui.panelEntr:SetPoint("TOPLEFT", r, "TOPLEFT", RX, -(PANEL_Y + 19))
  ui.panelEst = label(r, "label", G.size.xs, "sepia")
  ui.panelEst:SetWidth(RW)
  ui.panelEst:SetPoint("TOPLEFT", r, "TOPLEFT", RX, -(PANEL_Y + 34))
  ui.openBtn = D.NewSticker(r, T.openDungeon, function() if self.key then self:OpenDungeon(self.key) end end, { tip = T.openDungeonTip, height = STICKER_H, size = 18 })
  ui.openBtn:SetPoint("TOPLEFT", r, "TOPLEFT", RX, -STICKER_Y)
  ui.entrBtn = D.NewSticker(r, T.toEntrance, function() self:EntranceTodo() end, { tip = T.toEntranceTip, height = STICKER_H, size = 18 })
  ui.entrBtn:SetPoint("LEFT", ui.openBtn, "RIGHT", 10, 0)
  ui.overMsg = label(r, "label", G.size.xs, "sepia")
  ui.overMsg:SetWidth(RW)
  ui.overMsg:SetPoint("TOPLEFT", r, "TOPLEFT", RX, -MSG_Y)
end

local function buildPage(self, tab, tabR)
  local ui = self.ui
  local f = CreateFrame("Frame", nil, tab)
  f:SetAllPoints(tab)
  ui.pageL = f
  ui.back = D.NewBack(f, T.back, function() self:ShowOverview() end, { size = G.size.m })
  D.placeBack(ui.back, f)
  ui.pgTitle = label(f, "title", G.size.l, "ink")
  ui.pgTitle:SetPoint("TOPLEFT", f, "TOPLEFT", LX, -TITLE_L_Y)
  ui.pgTitle:SetWidth(LW)
  ui.pgSum = label(f, "label", G.size.s, "ink")
  ui.pgSum:SetWidth(LW)
  ui.pgSum:SetPoint("TOPLEFT", f, "TOPLEFT", LX, -SUB_Y)
  ui.pgBar = newBar(f, LX, BAR_Y, LW)
  ui.foreign = D.NewCheck(f, T.foreign, { size = 12, checked = false, tip = T.foreignTip, onChange = function(on) self:SetAll(on) end })
  ui.foreign:SetPoint("LEFT", f, "TOPLEFT", LX, -CTRL_CY)
  ui.list = newSheet(self, f, LX, BODY_Y, LW, PAGE_ROWS)
  local K = kit()
  if K and K.pager then ui.pager = K.pager(f, ui.list, LX, LW, CTRL_CY, { T.prevPage, T.nextPage }) end
  ui.legendL = label(f, "label", G.size.xs, "sepia")
  ui.legendL:SetWidth(LW)
  ui.legendL:SetPoint("TOPLEFT", f, "TOPLEFT", LX, -(BODY_Y + PAGE_ROWS * ROW_H + 1))
  ui.legendL:SetText(T.legend)

  local r = CreateFrame("Frame", nil, tabR)
  r:SetAllPoints(tabR)
  ui.pageR = r
  ui.qName = label(r, "title", G.size.l, "ink")
  ui.qName:SetWidth(RW)
  ui.qName:SetPoint("TOPLEFT", r, "TOPLEFT", RX, -TITLE_Y)
  ui.qSub = label(r, "label", G.size.xs, "sepia")
  ui.qSub:SetWidth(RW)
  ui.qSub:SetPoint("TOPLEFT", r, "TOPLEFT", RX, -QUEST_SUB_Y)
  ui.lines = {}
  for i = 1, DETAIL_MAX do
    local b = CreateFrame("Button", nil, r)
    b:SetSize(RW, DETAIL_LINE)
    b:SetPoint("TOPLEFT", r, "TOPLEFT", RX, -(DETAIL_Y + (i - 1) * DETAIL_LINE))
    b.marks = newMarks(b)
    b.text = label(b, "label", G.size.s, "ink")
    b.text:SetWidth(RW - 2)
    b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
    b:SetScript("OnEnter", function(x)
      if x.goId then x.text:SetTextColor(W.color("red")) end
      if x.tipLines then W.tip(x, x.tipLines) end
    end)
    b:SetScript("OnLeave", function(x)
      if x.goId and x.col then x.text:SetTextColor(W.color(x.col[1], x.col[2])) end
      W.hideTip(x)
    end)
    b:SetScript("OnClick", function(x) if x.goId then W.call(self.SelectQuest, self, x.goId, true) end end)
    b:Hide()
    ui.lines[i] = b
  end
  -- stations of the chain: filled = done, red and larger = chosen, hollow = still open
  ui.stations = {}
  for i = 1, STATION_MAX do
    local dot = r:CreateTexture(nil, "ARTWORK")
    dot:SetTexture(Theme.TEX.disc)
    dot:Hide()
    local hole = r:CreateTexture(nil, "OVERLAY")
    hole:SetTexture(Theme.TEX.disc)
    hole:SetVertexColor(W.color("parchment", 1))
    hole:SetPoint("CENTER", dot, "CENTER", 0, 0)
    hole:Hide()
    ui.stations[i] = { dot = dot, hole = hole }
  end
  ui.todo = D.NewSticker(r, T.toTodo, function() self:QuestTodo() end, { tip = T.toTodoTip, disabledTip = T.toTodoOff, height = STICKER_H, size = 18 })
  ui.todo:SetPoint("TOPLEFT", r, "TOPLEFT", RX, -STICKER_Y)
  ui.read = D.NewSticker(r, T.readText, function() self:ReadText() end, { tip = T.readTextTip, height = STICKER_H, size = 18 })
  ui.read:SetPoint("LEFT", ui.todo, "RIGHT", 10, 0)
  ui.pgMsg = label(r, "label", G.size.xs, "sepia")
  ui.pgMsg:SetWidth(RW)
  ui.pgMsg:SetPoint("TOPLEFT", r, "TOPLEFT", RX, -MSG_Y)
end

function View.new(page, left, right)
  local self = setmetatable({ page = page, ui = {}, level = 1, mode = "quests", all = false, search = "", chains = {} }, View)
  local ui = self.ui
  local tab = CreateFrame("Frame", nil, left)
  tab:SetAllPoints(left)
  tab:SetFrameLevel(left:GetFrameLevel() + 12)
  ui.table = tab
  local tabR = CreateFrame("Frame", nil, right)
  tabR:SetAllPoints(right)
  ui.tableR = tabR
  ui.headL = W.NewPageHead(tab, { side = "L" })
  ui.headR = W.NewPageHead(tabR, { side = "R" })
  ui.headR:SetTexts("", T.page)
  buildOverview(self, tab, tabR)
  buildPage(self, tab, tabR)
  ui.emptyHead = label(tab, "title", G.size.l, "ink", "CENTER")
  ui.emptyHead:SetWidth(LW)
  ui.emptyHead:SetPoint("TOP", tab, "TOPLEFT", LX + LW / 2, -230)
  ui.emptyBody = D.emptyNote(tab, LW - 60)
  ui.emptyBody:SetPoint("TOP", tab, "TOPLEFT", LX + LW / 2, -270)
  ui.emptyRight = D.emptyNote(tabR, RW - 60)
  ui.emptyRight:SetPoint("TOP", tabR, "TOPLEFT", RX + RW / 2, -290)
  -- source line in the footer: flush with the fold, right of x 154 (blot bottom left stays free)
  local fp, fx, fy = Theme.gridFoot("L")
  ui.foot = W.font(tab, "label", G.size.xs, "sepia")
  ui.foot:SetJustifyH("RIGHT")
  ui.foot:SetPoint(fp, tab, "TOPLEFT", fx, -fy)
  ui.foot:SetWidth(LW - 100)
  ui.foot:SetJustifyV("TOP")
  DQ.onChange(function() if self.open then self:Render() end end)
  -- data blocked by combat on the first open: read again right after the fight
  tab:SetScript("OnEvent", function(fr)
    if fr.UnregisterEvent then fr:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    if self.open then W.call(self.Render, self) end
  end)
  tab:Hide()
  tabR:Hide()
  return self
end

function View:IsOpen() return self.open == true end

-- ---------------------------------------------------------------- actions

function View:CurrentSheet()
  return self.level == 2 and self.ui.list or self.ui.sheet
end

function View:ChainState(key)
  key = key or self.key
  local st = self.chains[key]
  if not st then
    st = {}
    self.chains[key] = st
  end
  return st
end

function View:SetAll(on)
  self.all = on and true or false
  self.todoText = nil
  self:Render()
end

function View:SetSearch(text)
  text = type(text) == "string" and not isSecret(text) and text or ""
  if text == self.search then return end
  self.search = text
  self.ui.dgList:SetOffset(0)
  self:Render()
end

function View:SetMode(mode)
  self.mode = mode == "map" and "map" or "quests"
  self:Render()
end

function View:SetContinent(id)
  self.cont = tonumber(id)
  self:Render()
end

function View:SelectDungeon(key)
  if key ~= self.key then self.ui.sheet:SetOffset(0) end
  self.key = key
  self.todoText = nil
  self:Render()
end

-- click = choose (the sheet on the right shows it at once); second click soon after = open
function View:ClickDungeon(key)
  local t = now()
  if key == self.key and self.lastClick and t - self.lastClick <= DOUBLE_CLICK then
    self.lastClick = nil
    self:OpenDungeon(key)
    return
  end
  self.lastClick = t
  self:SelectDungeon(key)
end

function View:OpenDungeon(key, questId)
  self.key = key
  self.level = 2
  self.sel = questId
  self.pinAt = nil
  self.todoText = nil
  self.ui.list:SetOffset(0)
  self:Render()
  if questId then self:Reveal(questId) end
end

function View:ShowOverview()
  self.level = 1
  self.sel, self.pinAt, self.todoText = nil, nil, nil
  self:Render()
end

-- make a quest visible in the sheet: opens its chain if needed and scrolls to it
function View:Reveal(id)
  local sheet = self:CurrentSheet()
  local pos = indexOfQuest(self.items, id)
  if not pos then
    local row = self.res and self.res.byId and self.res.byId[id]
    if row and row.chainId then
      self:ChainState()[row.chainId] = "full"
      self:Render()
      pos = indexOfQuest(self.items, id)
    end
  end
  if pos then sheet:ScrollTo(pos) end
  return pos
end

function View:SelectQuest(id, reveal)
  self.sel = id
  self.pinAt = nil
  self.todoText = nil
  self:Render()
  if reveal then self:Reveal(id) end
end

-- open a chain completely; first = first quest that was hidden. jump: the list moves to it (lid line at the end of the chain)
function View:OpenChain(chainKey, first, jump)
  self:ChainState()[chainKey] = "full"
  self:Render()
  local sheet = self:CurrentSheet()
  local pos = first and indexOfQuest(self.items, first)
  if pos then
    if jump then sheet:SetOffset(pos - 1) else sheet:ScrollTo(pos) end
  end
end

function View:OnItem(it)
  if it.kind == "quest" then
    if self.level == 2 then
      self:SelectQuest(it.row.id)
    else
      self:OpenDungeon(self.key, it.row.id)
    end
  elseif it.kind == "chain" then
    local st = self:ChainState()
    st[it.chain.id] = it.closed and "open" or "closed"
    self:Render()
  elseif it.kind == "fold" then
    self:OpenChain(it.chainKey, it.first, false)
  elseif it.kind == "more" then
    self:OpenChain(it.chainKey, it.first, true)
  elseif it.kind == "less" then
    self:ChainState()[it.chainKey] = "open"
    self:Render()
  elseif it.kind == "note" and it.refs and self.level == 2 then
    self:SelectQuest(it.refs[1], true)
  end
end

function View:ClickPin(p)
  if type(p) ~= "table" then return end
  if p.kind == "entrance" then
    if p.key and self.level == 1 then
      if p.key == self.key then self:OpenDungeon(p.key) else self:SelectDungeon(p.key) end
    end
  elseif p.kind == "giver" then
    self.pinAt = { mapID = p.mapID, x = p.x, y = p.y }
    self:Render()
  end
end

local function todoMessage(goal, why, via)
  if goal then return via == "entrance" and T.todoEntranceDone or T.todoDone end
  return T.todoFail .. (T.todoReasons[why] or T.todoReasons["kein-plan"])
end

function View:QuestTodo()
  if not (self.sel and self.key) then return end
  local goal, why, via = DQ.addTodo(self.key, self.sel, { pin = self.pinAt })
  self.todoText = todoMessage(goal, why, via)
  self:Render()
end

function View:EntranceTodo()
  local dg = self.dungeon
  local e = dg and dg.entrances and dg.entrances[1]
  if not e then
    self.todoText = T.todoFail .. T.noEntrance
  else
    local goal, why = OQ.addTodo({ id = 0, name = dungeonName(dg) }, { mapID = e.mapID, x = e.x, y = e.y,
      text = T("todoEntrance", dungeonName(dg)), unique = true })
    self.todoText = todoMessage(goal, why, "entrance")
  end
  self:Render()
end

function View:ReadText()
  local P = self.page
  if P and P.OpenFromDungeons and self.sel then P:OpenFromDungeons(self.sel) end
end

-- the quest is in the quest book (done or abandoned): "Questtext lesen" (the condition of Quests:Select)
local function inBook(page, id)
  local q = page and page.book and page.book.byId and page.book.byId[id]
  return q ~= nil and (q.state == "done" or q.state == "abandoned")
end

-- ---------------------------------------------------------------- drawing

local function pickDefault(res)
  local first, coming
  for _, dg in ipairs(res.dungeons) do
    first = first or dg
    if not dg.empty and not dg.complete then
      if dg.levelRel == "fit" then return dg.key end
      if dg.levelRel == "coming" and not coming then coming = dg.key end
    end
  end
  return coming or (first and first.key) or nil
end

local function findDungeon(res, key)
  for i, dg in ipairs(res.dungeons) do
    if dg.key == key then return dg, i end
  end
  return nil
end

function View:ShowEmpty(reason)
  local ui = self.ui
  ui.overL:Hide()
  ui.overR:Hide()
  ui.pageL:Hide()
  ui.pageR:Hide()
  ui.emptyHead:Show()
  ui.emptyBody:Show()
  ui.emptyRight:Show()
  W.setText(ui.emptyHead, T.noData)
  W.setText(ui.emptyBody, DQ.reasonText(reason) .. ". " .. T.noDataHint)
  W.setText(ui.emptyRight, T.noDataRight)
  W.setText(ui.foot, "")
  ui.headL:SetTexts(T.brand, T.book)
  if reason == "COMBAT" and ui.table.RegisterEvent then ui.table:RegisterEvent("PLAYER_REGEN_ENABLED") end
  if self.mapOver then self.mapOver.pins:ReleaseAll() end
  if self.mapPage then self.mapPage.pins:ReleaseAll() end
end

function View:LoadSheet(list)
  local q = DQ.quests(self.key, { locked = true, foreign = self.all })
  self.res = q
  self.items = View.flatten(q, self:ChainState(), self.level ~= 2)
  list.opts.empty = (q.hiddenForeign or 0) > 0 and (T.emptySheet .. " " .. T.emptySheetAll) or T.emptySheet
  list:SetItems(self.items)
  list:Refresh()
  return q
end

-- continent of an entrance map
local function continentOf(mapID)
  local OV = Journal.OpenQuestsView
  return OV and OV.continentOfZone and OV.continentOfZone(mapID) or nil
end

function View:RenderOverMap(res, dg)
  local ui = self.ui
  if not self.mapOver then self.mapOver = newMap(self, ui.overR, BODY_Y, OVER_MAP_H) end
  local o = self.mapOver
  local conts = OQ.continents()
  local e = dg and dg.entrances and dg.entrances[1]
  if e and self.contFor ~= dg.key then
    self.contFor = dg.key
    self.cont = continentOf(e.mapID) or self.cont
  end
  if not self.cont then self.cont = conts[1] and conts[1].id end
  ui.cont:SetValue(self.cont)
  local Geo = Journal.Geo
  local project = self.cont and Geo and Geo.projector and select(1, Geo.projector(self.cont)) or nil
  local data, unplaced = {}, 0
  for _, d2 in ipairs(res.dungeons) do
    for _, en in ipairs(d2.entrances or {}) do
      if continentOf(en.mapID) == self.cont then
        local x, y
        if en.mapID == self.cont then x, y = en.x, en.y elseif project then x, y = project(en.mapID, en.x, en.y) end
        x, y = num(x), num(y)
        if x and y then
          local name = dungeonName(d2)
          data[#data + 1] = { kind = "entrance", key = d2.key, mapID = en.mapID, x = x, y = y, count = d2.open, sel = d2.key == self.key,
            tip = { name, levelText(d2), T("doneOfLong", int(d2.done), int(d2.total)), T("pinCount", int(d2.open)), T.pinOpen } }
        else
          unplaced = unplaced + 1
        end
      end
    end
  end
  o.data = data
  local hasArt = renderMap(o, self.cont, true)
  W.setText(o.note, not hasArt and T.noMap or (#data == 0 and unplaced > 0 and T("unplaced", int(unplaced))) or "")
  self:PlacePins(o)
end

function View:RenderOverview()
  local ui = self.ui
  local res = DQ.list({ all = self.all, search = self.search ~= "" and self.search or nil })
  if res.unavailable then return self:ShowEmpty(res.reason) end
  self.listRes = res
  ui.emptyHead:Hide()
  ui.emptyBody:Hide()
  ui.emptyRight:Hide()
  ui.pageL:Hide()
  ui.pageR:Hide()
  ui.overL:Show()
  ui.headL:SetTexts(T.brand, T.book)
  ui.scope:SetValue(self.all and "all" or "me")
  local sum = { T("countDungeons", int(#res.dungeons)) }
  if (res.hiddenEmpty or 0) > 0 then sum[#sum + 1] = T("countHidden", int(res.hiddenEmpty)) end
  local testText = OQ.testLabel()
  if testText then sum[#sum + 1] = testText elseif res.partial then sum[#sum + 1] = T.partial end
  W.setText(ui.count, table.concat(sum, " · "))
  W.setText(ui.foot, DQ.footer())
  if not self.key or not findDungeon(res, self.key) then self.key = pickDefault(res) end
  local dg, pos = findDungeon(res, self.key)
  self.dungeon = dg
  ui.dgList:SetItems(res.dungeons)
  if pos and self.scrollDg ~= self.key then
    ui.dgList:ScrollTo(pos)
    self.scrollDg = self.key
  end
  ui.dgList:Refresh()
  if not dg then
    ui.overR:Hide()
    self.res, self.items = nil, {}
    ui.emptyRight:Show()
    W.setText(ui.emptyRight, T.empty)
    return
  end
  ui.overR:Show()
  W.setText(ui.dgTitle, dungeonName(dg))
  W.fitLine(ui.dgTitle, RW, G.size.l)
  W.setText(ui.dgSum, levelText(dg) .. " · " .. summary(dg))
  ui.dgBar:Set(dg)
  ui.mode:SetValue(self.mode)
  local isMap = self.mode == "map"
  ui.sheet.frame:SetShown(not isMap)
  ui.legendR:SetShown(not isMap)
  if ui.sheetPager then
    ui.sheetPager.pair.frame:SetShown(not isMap)
    ui.sheetPager.label:SetShown(not isMap)
  end
  ui.cont.frame:SetShown(isMap)
  ui.panelName:SetShown(isMap)
  ui.panelEntr:SetShown(isMap)
  ui.panelEst:SetShown(isMap)
  self:LoadSheet(ui.sheet)
  if isMap then
    if self.mapOver then self.mapOver.m.viewport:Show() end
    self:RenderOverMap(res, dg)
    self.mapOver.m.viewport:Show()
    W.setText(ui.panelName, dungeonName(dg))
    local e = dg.entrances and dg.entrances[1]
    W.setText(ui.panelEntr, e and T("entrance", e.name or OQ.mapName(e.mapID) or "") or T.noEntrance)
    W.setText(ui.panelEst, (dg.estimated or 0) > 0 and T("estimated", int(dg.estimated)) or "")
  elseif self.mapOver then
    self.mapOver.pins:ReleaseAll()
    self.mapOver.m.viewport:Hide()
    W.setText(self.mapOver.note, "")
  end
  ui.entrBtn:SetEnabled(dg.entrances and dg.entrances[1] ~= nil)
  W.setText(ui.overMsg, self.todoText or "")
end

local function hideStations(ui)
  for _, s in ipairs(ui.stations) do
    s.dot:Hide()
    s.hole:Hide()
  end
end

-- the line "Kette: Schritt 3 von 5" with its stations (window around the chosen quest if there are too many)
local function drawStations(ui, line, d)
  hideStations(ui)
  local list = d.stations or {}
  if #list < 2 then return end
  local cur = 1
  for i, s in ipairs(list) do
    if s.current then cur = i end
  end
  local from = max(1, min(cur - floor(STATION_MAX / 2), #list - STATION_MAX + 1))
  local x = 136
  for i = 0, STATION_MAX - 1 do
    local s = list[from + i]
    local dotUi = ui.stations[i + 1]
    if s and dotUi then
      local size = s.current and STATION + 3 or STATION
      dotUi.dot:ClearAllPoints()
      dotUi.dot:SetPoint("CENTER", line, "LEFT", x + i * 12, 0)
      dotUi.dot:SetSize(size, size)
      dotUi.dot:SetVertexColor(W.color(s.current and "red" or (s.state == "done" and GREEN or "ink"), 1))
      dotUi.dot:Show()
      local hollow = not s.current and s.state ~= "done"
      dotUi.hole:SetSize(size * 0.55, size * 0.55)
      dotUi.hole:SetShown(hollow)
    end
  end
end

local function chipLine(d)
  local c = d.chips or {}
  local parts = {}
  if c.faction and T.faction[c.faction] then parts[#parts + 1] = T.faction[c.faction] end
  for _, tok in ipairs(c.classes or {}) do parts[#parts + 1] = T.classes[tok] or tok end
  -- "Nur Horde" already says all four races of a faction
  if not (c.faction and #(c.races or {}) == 4) then
    for _, tok in ipairs(c.races or {}) do parts[#parts + 1] = T.races[tok] or tok end
  end
  return table.concat(parts, " · ")
end

-- what the detail sheet says, as lines: { text, color, alpha, mark, id (clickable), tip, kind }
local function detailLines(self, res, d)
  local head, tail = {}, {}
  local stateLine = T.state[d.state] or ""
  local first = d.reasons and d.reasons[1]
  if first then stateLine = stateLine .. " · " .. first.text end
  head[#head + 1] = { text = stateLine, mark = d.state, color = stateColor(d.state) }
  for i = 2, #(d.reasons or {}) do head[#head + 1] = { text = d.reasons[i].text, color = "sepia", inset = true } end
  local function refs(title, list)
    if #list == 0 then return end
    head[#head + 1] = { text = title, color = "sepia" }
    for _, p in ipairs(list) do
      local s = p.state
      head[#head + 1] = { text = p.name or tostring(p.id), mark = s, id = (res.byId and res.byId[p.id]) and p.id or nil, color = "ink", ref = true,
        tip = { p.name or tostring(p.id), T.state[s] or "" } }
    end
  end
  refs(T.preAll, d.prereqAll)
  refs(T.preAny, d.prereqAny)
  refs(T.exclHead, d.excl)
  if d.steps and d.steps > 1 then
    tail[#tail + 1] = { text = T("chainStep", int(d.step or 1), int(d.steps)), color = "sepia", stations = true,
      tip = d.chain and d.chain.name and { T("chain", d.chain.name) } or nil }
  end
  local chips = chipLine(d)
  if chips ~= "" then tail[#tail + 1] = { text = chips, color = "sepia" } end
  local notes, tip = {}, {}
  for _, n in ipairs(d.notes or {}) do
    notes[#notes + 1] = n.text
    tip[#tip + 1] = n.tip and (n.text .. ": " .. n.tip) or n.text
  end
  if #notes > 0 then tail[#tail + 1] = { text = table.concat(notes, " · "), color = "sepia", alpha = 0.8, tip = tip } end
  -- keep state + tail; a long list of prerequisites is cut with "+ n weitere"
  local room = DETAIL_MAX - #tail
  local out = {}
  if #head > room then
    for i = 1, room - 1 do out[i] = head[i] end
    out[#out + 1] = { text = T("moreLines", int(#head - room + 1)), color = "sepia", alpha = 0.8 }
  else
    out = head
  end
  for _, l in ipairs(tail) do out[#out + 1] = l end
  return out
end
View.detailLines = detailLines

function View:RenderDetail(res)
  local ui = self.ui
  local d = self.sel and DQ.detail(self.sel, self.key, { locked = true, foreign = self.all }) or nil
  self.detail = d
  hideStations(ui)
  for _, b in ipairs(ui.lines) do
    b:Hide()
    b.goId, b.tipLines = nil, nil
  end
  ui.todo:SetShown(d ~= nil)
  ui.read:SetShown(d ~= nil and inBook(self.page, d.id))
  if not self.mapPage then self.mapPage = newMap(self, ui.pageR, PAGE_MAP_Y, PAGE_MAP_H) end
  local o = self.mapPage
  if not d then
    W.setText(ui.qName, "")
    W.setText(ui.qSub, "")
    W.setText(ui.pgMsg, "")
    o.data = {}
    self:PlacePins(o)
    return
  end
  W.setText(ui.qName, d.name)
  W.fitLine(ui.qName, RW, G.size.s)
  local g = d.givers and d.givers[1]
  local sub = { d.level and T("level", int(d.level)) or T.levelUnknown }
  if d.minLevel and d.minLevel > 0 then sub[#sub + 1] = T("minLevel", int(d.minLevel)) end
  if g then sub[#sub + 1] = T("giverZone", g.name, OQ.mapName(g.mapID) or "") end
  W.setText(ui.qSub, table.concat(sub, " · "))
  -- map: zone of the giver (else of the entrance), with its giver points and the dungeon entrance
  local dg = d.dungeon
  local entr = dg and dg.entrances or {}
  local mapID = g and g.mapID or (entr[1] and entr[1].mapID) or nil
  local data = {}
  for _, gv in ipairs(d.givers or {}) do
    if gv.mapID == mapID then
      for _, pt in ipairs(gv.points or {}) do
        if #data < PIN_MAX - 4 then
          local at = self.pinAt
          data[#data + 1] = { kind = "giver", mapID = gv.mapID, x = pt[1], y = pt[2], sel = at ~= nil and at.mapID == gv.mapID and at.x == pt[1] and at.y == pt[2],
            tip = { gv.name, OQ.mapName(gv.mapID) or "", T.pinGiver } }
        end
      end
    end
  end
  for _, e in ipairs(entr) do
    if e.mapID == mapID then
      data[#data + 1] = { kind = "entrance", mapID = e.mapID, x = e.x, y = e.y, tip = { dg.name or "", T.entranceTip } }
    end
  end
  o.data = data
  local hasArt = mapID and renderMap(o, mapID, false) or false
  W.setText(o.note, not hasArt and T.noMap or "")
  self:PlacePins(o)
  -- lines
  local lines = detailLines(self, res, d)
  for i, l in ipairs(lines) do
    local b = ui.lines[i]
    if not b then break end
    b:Show()
    local indent = (l.ref or l.inset) and 10 or 0
    local tx = indent
    if l.mark then
      showMark(b.marks, l.mark, b, indent + 8)
      tx = indent + 18
    else
      showMark(b.marks, nil, b)
    end
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", b, "LEFT", tx, 0)
    b.text:SetWidth(l.stations and 130 or (RW - tx - 2))
    W.setText(b.text, l.text)
    b.col = { l.color or "ink", l.alpha or 1 }
    b.text:SetTextColor(W.color(b.col[1], b.col[2]))
    b.goId = l.id
    b.tipLines = l.tip
    if b.EnableMouse then b:EnableMouse(l.id ~= nil or l.tip ~= nil) end
    if l.stations then drawStations(ui, b, d) end
  end
  ui.todo:SetEnabled(d.todo and d.todo.via ~= nil)
  W.setText(ui.pgMsg, self.todoText or "")
end

function View:RenderPage()
  local ui = self.ui
  local dgRes = DQ.list({ all = true })
  if dgRes.unavailable then return self:ShowEmpty(dgRes.reason) end
  local dg = findDungeon(dgRes, self.key)
  if not dg then
    self.level = 1
    return self:RenderOverview()
  end
  self.dungeon = dg
  ui.emptyHead:Hide()
  ui.emptyBody:Hide()
  ui.emptyRight:Hide()
  ui.overL:Hide()
  ui.overR:Hide()
  ui.pageL:Show()
  ui.pageR:Show()
  ui.headL:SetTexts("", T.book)
  W.setText(ui.foot, DQ.footer())
  W.setText(ui.pgTitle, dungeonName(dg))
  W.fitLine(ui.pgTitle, LW, G.size.s)
  local q = self:LoadSheet(ui.list)
  local n = q.counts or dg
  W.setText(ui.pgSum, levelText(dg) .. " · " .. summary(n))
  ui.pgBar:Set(n)
  ui.foreign:SetChecked(self.all, true)
  if not (self.sel and q.byId and q.byId[self.sel]) then
    -- default: what can be done next among the visible rows, a quest of the dungeon first
    self.sel = nil
    local off = ui.list:GetOffset()
    local function pick(seedOnly, wanted)
      for i = off + 1, min(#self.items, off + PAGE_ROWS) do
        local it = self.items[i]
        if it.kind == "quest" and (not seedOnly or it.row.seed) and (not wanted or it.row.state == wanted) then return it.row.id end
      end
      return nil
    end
    self.sel = pick(true, "log") or pick(true, "open") or pick(false, "log") or pick(false, "open") or pick(true) or pick(false)
    if not self.sel then
      for _, it in ipairs(self.items) do
        if it.kind == "quest" then self.sel = it.row.id break end
      end
    end
    ui.list:Refresh()
  end
  self:RenderDetail(q)
end

function View:Render()
  if not self.open then return end
  if self.level == 2 then
    self:RenderPage()
  else
    self:RenderOverview()
  end
end

function View:Open()
  self.open = true
  self.ui.table:Show()
  self.ui.tableR:Show()
  self:Render()
end

function View:Refresh()
  if self.open then self:Render() end
end

-- tooltips off, pins back (page hidden; the view stays as it is)
function View:OnPageHide()
  local ui = self.ui
  local function off(list)
    for _, r in ipairs(list and list.rows or {}) do W.hideTip(r) end
  end
  off(ui.dgList)
  off(ui.sheet)
  off(ui.list)
  for _, b in ipairs(ui.lines) do W.hideTip(b) end
  if ui.search and ui.search.ClearFocus then ui.search:ClearFocus() end
  if self.mapOver then self.mapOver.pins:ReleaseAll() end
  if self.mapPage then self.mapPage.pins:ReleaseAll() end
end

function View:Close()
  self.open = false
  self:OnPageHide()
  self.ui.table:Hide()
  self.ui.tableR:Hide()
end
