-- Rezepte (profession recipe plan, WoW Forever only): which recipes of the character's professions can be learned at the current skill
-- and are not known yet ("learnable now"), which come within the next 25 skill points ("soon"), with source (trainer, vendor, quest,
-- drop), price, minimum skill, Merchant's Favor and reputation. Display-ready data for pages/PlaeneHandwerk.lua (Pläne > Handwerk) and
-- collectors/CraftTodo.lua (to-do "Zum Berufslehrer").
-- Data: the data add-on InkAndEmbers_Data (LoadOnDemand), file Recipes.lua, global EveNChronicleRecipeData (MIT, from "What's
-- Training?", scripts/build-recipe-data.mjs; format there). It is loaded together with the to-do lists through TodoData (one load of
-- the add-on, in the right language state), adopted once and the global removed. Keys are skillLine ids = the SK field of the log.
-- Skill of a profession: GetProfessions / GetProfessionInfo (name, rank, max, skillLine). Known recipes: the client spellbook
-- (C_SpellBook.IsSpellKnown / IsPlayerSpell, each in pcall), supplemented by snapshots.spells (spells the collector saw being learned;
-- recipes learned in earlier sessions). Rank steps (Geselle/Experte/Meister) count as learned once the profession cap is at least
-- 150/225/300 (a higher rank replaces the lower one in the spellbook). No colour thresholds (the data has none).
-- Retail clients: off (the data is Forever's).
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Rezepte = {}
Journal.Rezepte = Rezepte

local floor, gmatch, match, sort = math.floor, string.gmatch, string.match, table.sort

Rezepte.GLOBAL = "EveNChronicleRecipeData"
Rezepte.ALLOW_RETAIL = false   -- tests: switch the retail block off
Rezepte.SOON = 25              -- "soon" = at most this many skill points away
Rezepte.MAX_PROFESSIONS = 6
Rezepte.FILTERS = { "trainer", "now", "soon" }
-- skill lines without recipes (herbalism, skinning, fishing, archaeology): alone they never need the recipe data
Rezepte.NO_RECIPE_LINES = { [182] = true, [393] = true, [356] = true, [794] = true }
-- rank step -> profession cap that proves it learned
Rezepte.RANK_CAP = { J = 150, E = 225, A = 300 }
-- skillLine -> a spell of that profession (its name is the profession name in the client language; same list as What's Training?)
Rezepte.NAME_SPELLS = { [129] = 3273, [186] = 2575, [185] = 2550, [393] = 8613, [182] = 9134, [164] = 2018, [356] = 7620,
  [171] = 2259, [165] = 2108, [197] = 3908, [333] = 7411, [202] = 4036 }

-- locale scope "m.Rezepte" (English in locales/enUS_model.lua)
local T = ns.Locale.ns("m.Rezepte", {
  spellFallback = "Rezept %s",
  profFallback = "Beruf %s",
  rankJ = "Geselle", rankE = "Experte", rankA = "Meister",
  srcT = "Lehrer", srcV = "Händler", srcQ = "Quest", srcD = "Beute", srcC = "Herstellung", srcO = "Fundort",
  favor = "%s Händlergunst",
  repText = "Ruf: %s",
  repFallback = "Ruf bei einer Fraktion",
  NO_RECIPES = "Rezeptliste fehlt im Zusatzaddon (neu installieren)",
  NO_API = "Berufe sind gerade nicht lesbar",
})
Rezepte.TEXT = T

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

local function tbl(v)
  if type(v) == "table" and not isSecret(v) then return v end
  return nil
end

-- results of fn(...) as a table (read by index, so nil holes such as GetProfessions' empty slots do no harm); nil on an error
local function pack(ok, ...)
  if not ok then return nil end
  return { ... }
end

local function callAll(fn, ...)
  if type(fn) ~= "function" then return nil end
  return pack(pcall(fn, ...))
end

-- Retail client: the shared check Journal.MapSpace.retailClient (project id AND interface version, so Forever is never Retail).
function Rezepte.active()
  local ms = Journal.MapSpace
  return Rezepte.ALLOW_RETAIL or not (ms ~= nil and ms.retailClient() == true)
end

-- Data (load on demand, adopt once)

local S = { data = nil, reason = nil, parsed = {} }
Rezepte._state = S

local function adopt()
  local g = rawget(_G, Rezepte.GLOBAL)
  if type(g) ~= "table" then return false end
  _G[Rezepte.GLOBAL] = nil
  if type(g.skills) ~= "table" then return false end
  S.data = g
  return true
end

-- Loads the data add-on (through TodoData, which knows the language and the failure reasons) -> loaded?
function Rezepte.load()
  if S.data then return true end
  if adopt() then
    S.reason = nil
    return true
  end
  local TD = Journal.TodoData
  if TD and type(TD.available) == "function" then TD.available("item") end
  if adopt() then
    S.reason = nil
    return true
  end
  local st = TD and type(TD.status) == "function" and TD.status() or nil
  if st and st.loaded then
    S.reason = "NO_RECIPES"
  else
    S.reason = st and st.reason or "NO_DATA"
  end
  return false
end

function Rezepte.reasonText()
  local r = S.reason
  if r == "NO_RECIPES" then return T.NO_RECIPES end
  local TD = Journal.TodoData
  if TD and type(TD.reasonText) == "function" then return TD.reasonText(r) end
  return T.NO_RECIPES
end

function Rezepte.dataInfo()
  local d = S.data
  if not d then return nil end
  return { source = d.source, commit = d.commit, date = d.date, license = d.license }
end

-- skills[line] = "<lines>" -> { { line, skill, id, src, cost, faction, favor, rank, level, rep = { { id, standing } }, idx } }
local LINE = "^(%d+)\t(%d+)\t([A-Z]*)\t(%d*)\t([AH]?)\t(%d*)\t([JEA]?)\t(%d*)\t([%d:,]*)$"

function Rezepte.parse(line)
  line = num(line)
  if not line then return nil end
  local hit = S.parsed[line]
  if hit then return hit end
  local text = S.data and S.data.skills[line]
  if type(text) ~= "string" then return nil end
  local list = {}
  for row in gmatch(text, "[^\n]+") do
    local sk, id, src, cost, fac, favor, rank, lvl, rep = match(row, LINE)
    if sk then
      local reps = {}
      for rid, st in gmatch(rep, "(%d+):(%d+)") do reps[#reps + 1] = { id = tonumber(rid), standing = tonumber(st) } end
      list[#list + 1] = { line = line, skill = tonumber(sk), id = tonumber(id), src = src, cost = tonumber(cost) or 0,
        faction = fac ~= "" and fac or nil, favor = tonumber(favor), rank = rank ~= "" and rank or nil, level = tonumber(lvl),
        rep = reps, idx = #list + 1 }
    end
  end
  S.parsed[line] = list
  return list
end

function Rezepte.hasSource(row, letter)
  return row.src ~= nil and string.find(row.src, letter, 1, true) ~= nil
end

-- Player and professions

function Rezepte.player()
  local r = callAll(UnitFactionGroup, "player")
  local fac = r and str(r[1])
  local lv = callAll(UnitLevel, "player")
  local level = lv and num(lv[1])
  return { faction = fac == "Alliance" and "A" or fac == "Horde" and "H" or nil, level = level and floor(level) or nil }
end

-- the character's professions: { { line, name, rank, max } } in the order of GetProfessions; nil = not readable
function Rezepte.professions()
  if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return nil end
  local idx = callAll(GetProfessions)
  if not idx then return nil end
  local out, seen = {}, {}
  for i = 1, Rezepte.MAX_PROFESSIONS do
    local v = num(idx[i])
    if v then
      local info = callAll(GetProfessionInfo, v)
      local line, rank, max = info and num(info[7]), info and num(info[3]), info and num(info[4])
      if line and rank and not seen[line] then
        seen[line] = true
        out[#out + 1] = { line = floor(line), name = info[1] and str(info[1]) and ns.Sanitize.field(info[1]) or nil, rank = floor(rank),
          max = max and floor(max) or nil }
      end
    end
  end
  return out
end

local function lehrplan() return Journal.Lehrplan end

-- profession name in the client language
local function professionName(p)
  if p.name then return p.name end
  local sp = Rezepte.NAME_SPELLS[p.line]
  local LP = lehrplan()
  local info = sp and LP and type(LP.spellInfo) == "function" and LP.spellInfo(sp) or nil
  if info and not info.missing then return info.name end
  return T("profFallback", p.line)
end

-- Known recipes

local function snapshotKnows(id)
  local S_ = ns.Store
  local c = S_ and type(S_.char) == "function" and S_.char() or nil
  local g = type(c) == "table" and type(c.snapshots) == "table" and c.snapshots.spells or nil
  return type(g) == "table" and g[id] ~= nil
end

function Rezepte.knows(id)
  local LP = lehrplan()
  if LP and type(LP.clientKnows) == "function" and LP.clientKnows(id) then return true end
  return snapshotKnows(id)
end

function Rezepte.spellInfo(id)
  local LP = lehrplan()
  if LP and type(LP.spellInfo) == "function" then return LP.spellInfo(id) end
  return nil
end

-- Evaluation. opts: names (false = no name lookups), level (override)
-- -> { available, reason, level, money, profs = { { line, name, rank, max, now, trainer, soon, learned, cost } }, rows = { row },
--      now = { n }, trainer = { n, cost }, soon = { n }, learned = { n }, short }
-- row: { line, prof, id, skill, src, cost, favor, rank, minLevel, rep, state, trainer, name, icon, missingName, need }
-- state: "learned" | "now" (skill reached) | "soon" (at most SOON points away, or the character level is still too low) | "later"
function Rezepte.evaluate(opts)
  opts = type(opts) == "table" and opts or {}
  local out = { available = false, rows = {}, profs = {}, now = { n = 0 }, trainer = { n = 0, cost = 0 }, soon = { n = 0 }, learned = { n = 0 } }
  if not Rezepte.active() then
    out.reason = "RETAIL"
    return out
  end
  -- the data add-on (about 1 MB) is only loaded when a profession with recipes is there: no profession, no load (login check)
  local profs = Rezepte.professions()
  if not profs then
    out.reason = "NOAPI"
    return out
  end
  if #profs == 0 then
    out.reason = "NOPROF"
    return out
  end
  local capable = false
  for _, prof in ipairs(profs) do
    if not Rezepte.NO_RECIPE_LINES[prof.line] then capable = true end
  end
  if not capable then
    out.reason = "NOPROFDATA"
    return out
  end
  if not Rezepte.load() then
    out.reason = "NODATA"
    return out
  end
  local p = Rezepte.player()
  local level = num(opts.level) or p.level
  out.level = level
  local names = opts.names ~= false
  local withData = 0
  for order, prof in ipairs(profs) do
    local list = Rezepte.parse(prof.line)
    if list then
      withData = withData + 1
      local pr = { line = prof.line, name = professionName(prof), rank = prof.rank, max = prof.max, order = order,
        now = 0, trainer = 0, soon = 0, learned = 0, cost = 0 }
      out.profs[#out.profs + 1] = pr
      for _, e in ipairs(list) do
        if not (e.faction and p.faction and e.faction ~= p.faction) then
          local r = { line = e.line, prof = pr.name, order = order, id = e.id, skill = e.skill, src = e.src, cost = e.cost, favor = e.favor,
            rank = e.rank, minLevel = e.rank and e.level or nil, rep = e.rep, idx = e.idx, trainer = Rezepte.hasSource(e, "T") }
          local cap = e.rank and Rezepte.RANK_CAP[e.rank] or nil
          if Rezepte.knows(e.id) or (cap and prof.max and prof.max >= cap) then
            r.state = "learned"
            pr.learned = pr.learned + 1
            out.learned.n = out.learned.n + 1
          else
            local gap = e.skill - prof.rank
            local levelShort = e.rank and e.level and level and e.level > level
            if gap <= 0 and not levelShort then
              r.state = "now"
              pr.now = pr.now + 1
              out.now.n = out.now.n + 1
              if r.trainer then
                pr.trainer = pr.trainer + 1
                pr.cost = pr.cost + e.cost
                out.trainer.n = out.trainer.n + 1
                out.trainer.cost = out.trainer.cost + e.cost
              end
            elseif gap <= Rezepte.SOON then
              r.state = "soon"
              r.need = gap > 0 and gap or 0
              r.levelShort = levelShort and true or nil
              pr.soon = pr.soon + 1
              out.soon.n = out.soon.n + 1
            else
              r.state = "later"
              r.need = gap
            end
          end
          if names then
            local info = Rezepte.spellInfo(e.id)
            if info then r.name, r.icon, r.missingName = info.name, info.icon, info.missing end
          end
          out.rows[#out.rows + 1] = r
        end
      end
    end
  end
  if #profs == 0 then
    out.reason = "NOPROF"
    return out
  end
  if withData == 0 then
    out.reason = "NOPROFDATA"
    return out
  end
  out.available = true
  local money = callAll(rawget(_G, "GetMoney"))
  money = money and num(money[1]) or nil
  out.money = money
  out.short = money and out.trainer.cost > money and (out.trainer.cost - money) or 0
  return out
end

-- Rows for the page. filter "trainer" = learnable now from the trainer, "now" = learnable now from any source (trainer first),
-- "soon" = within the next SOON skill points (or waiting for the character level), nearest first.
function Rezepte.rows(view, filter)
  local out = {}
  if type(view) ~= "table" or type(view.rows) ~= "table" then return out end
  for _, r in ipairs(view.rows) do
    local s = r.state
    local take
    if filter == "trainer" then
      take = s == "now" and r.trainer
    elseif filter == "now" then
      take = s == "now"
    elseif filter == "soon" then
      take = s == "soon"
    else
      take = true
    end
    if take then out[#out + 1] = r end
  end
  sort(out, function(a, b)
    if filter == "now" and a.trainer ~= b.trainer then return a.trainer end
    if filter == "soon" and (a.need or 0) ~= (b.need or 0) then return (a.need or 0) < (b.need or 0) end
    if a.order ~= b.order then return a.order < b.order end
    if a.skill ~= b.skill then return a.skill < b.skill end
    return a.id < b.id
  end)
  return out
end

-- Texts of a row

function Rezepte.sourceText(r)
  local parts = {}
  for _, c in ipairs({ "T", "V", "Q", "D", "C", "O" }) do
    if Rezepte.hasSource(r, c) then parts[#parts + 1] = T["src" .. c] end
  end
  return table.concat(parts, "/")
end

function Rezepte.rankText(r)
  return r.rank and T["rank" .. r.rank] or nil
end

-- name of a reputation faction (client; nil = not readable)
local repNames = {}

function Rezepte.factionName(id)
  id = num(id)
  if not id then return nil end
  if repNames[id] ~= nil then return repNames[id] or nil end
  local name
  local CR = tbl(rawget(_G, "C_Reputation"))
  if CR and type(CR.GetFactionDataByID) == "function" then
    local r = callAll(CR.GetFactionDataByID, id)
    local d = r and tbl(r[1])
    name = d and str(d.name)
  end
  if not name and type(rawget(_G, "GetFactionInfoByID")) == "function" then
    local r = callAll(GetFactionInfoByID, id)
    name = r and str(r[1])
  end
  name = name and ns.Sanitize.field(name) or nil
  repNames[id] = name or false
  return name
end

function Rezepte.repText(r)
  if not r.rep or #r.rep == 0 then return nil end
  local names = {}
  for _, e in ipairs(r.rep) do
    local n = Rezepte.factionName(e.id)
    if n then names[#names + 1] = n end
  end
  if #names == 0 then return T.repFallback end
  return T("repText", table.concat(names, " / "))
end

function Rezepte.resetCache()
  S.parsed = {}
  repNames = {}
end
