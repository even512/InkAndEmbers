-- Collector 'CraftTodo' (WoW Forever only; on retail it stays idle): the automatic to-do "Zum Berufslehrer" (Pläne > To Do).
-- When recipes of the character's professions are learnable from a trainer right now (Journal.Rezepte: skill reached, not known,
-- source trainer), one free to-do is created (Plans.upsertAuto "craft"): "Zum Berufslehrer: 3 neue Rezepte (12 S)". It follows the
-- count and the price while it is open and completes itself (Plans.finishAuto) as soon as nothing is learnable from a trainer.
-- Once per skill threshold: snapshots.state.craftTodo = { sig = "<skillLine>=<highest trainer recipe skill of the last notice>;..." }.
-- A new to-do is only made when a profession reaches a higher threshold than the stored one, so a to-do ticked off or deleted does
-- not come back for the same recipes, and there is never a second open one. Same switch as "Zum Lehrer" (setting trainerTodo).
-- Checks: login (once, after the data had time to load), skill change, learned spell, trainer window closed, level-up; all batched.
-- Only reads APIs (through Journal.Rezepte); nothing is bought or clicked.
local _, ns = ...
local Core, Store = ns.Core, ns.Store

local floor = math.floor

local CraftTodo = {}
ns.CraftTodo = CraftTodo

CraftTodo.TAG = "craft"       -- Plans.upsertAuto tag
CraftTodo.LOGIN_DELAY = 9.0   -- seconds after login (the data add-on and the profession list are ready by then)
CraftTodo.CHECK_DELAY = 1.5   -- skill change / learned spell / trainer closed: batched re-check

local T = ns.Locale.ns("col.CraftTodo", {
  todo_one = "Zum Berufslehrer: %s neues Rezept (%s)",
  todo_other = "Zum Berufslehrer: %s neue Rezepte (%s)",
  unitG = "G",
  unitS = "S",
  unitK = "K",
})
CraftTodo.TEXT = T

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function R() return ns.Journal and ns.Journal.Rezepte end

local function setting(key)
  local P = ns.Journal and ns.Journal.Pages
  if not P or type(P.setting) ~= "function" then return true end
  return P.setting(key) ~= false
end

function CraftTodo.active()
  local Rz = R()
  return Rz ~= nil and Rz.active()
end

-- price text of the to-do: stored sanitized (no coin icons), so capital unit letters: "5 S 10 K"
local function moneyText(copper)
  local Tx = ns.Journal and ns.Journal.Texts
  if Tx and type(Tx.money) == "function" then
    local units = { g = T.unitG, s = T.unitS, k = T.unitK }
    return (Tx.money(copper, "plain"):gsub("(%d) ([gsk])%f[%A]", function(d, u) return d .. " " .. units[u] end))
  end
  return tostring(copper)
end

function CraftTodo.todoText(n, cost)
  local LC = ns.Locale
  local key = LC and LC.plural and LC.plural(n, "todo_one", "todo_other") or (n == 1 and "todo_one" or "todo_other")
  return T(key, n, moneyText(cost or 0))
end

-- Marker (additive snapshot, no schema change): sig = "171=50;164=75"
local function readMarks()
  local c = Store.char()
  local st = c and type(c.snapshots) == "table" and type(c.snapshots.state) == "table" and c.snapshots.state.craftTodo or nil
  local sig = type(st) == "table" and type(st.sig) == "string" and st.sig or ""
  local marks = {}
  for line, skill in string.gmatch(sig, "(%d+)=(%d+)") do marks[tonumber(line)] = tonumber(skill) end
  return marks
end

local function writeMarks(marks)
  local keys = {}
  for line in pairs(marks) do keys[#keys + 1] = line end
  table.sort(keys)
  local parts = {}
  for _, line in ipairs(keys) do parts[#parts + 1] = line .. "=" .. floor(marks[line]) end
  return Store.putSnapshot("state", "craftTodo", { sig = table.concat(parts, ";") }, true)
end

-- Trainer recipes learnable now: { n, cost, marks = { [skillLine] = highest min skill among them } } or nil (no data / nothing)
function CraftTodo.state()
  local Rz = R()
  if not (Rz and Rz.active()) then return nil end
  local view = Rz.evaluate({ names = false })
  if not view.available then return nil end
  local marks = {}
  local n, cost = 0, 0
  for _, r in ipairs(view.rows) do
    if r.state == "now" and r.trainer then
      n = n + 1
      cost = cost + (r.cost or 0)
      if (marks[r.line] or -1) < r.skill then marks[r.line] = r.skill end
    end
  end
  return { n = n, cost = cost, marks = marks }
end

-- Is there a threshold above the stored one? (a profession reached a higher skill step with recipes to learn)
local function fresh(marks)
  local old = readMarks()
  for line, skill in pairs(marks) do
    if skill > (old[line] or -1) then return true end
  end
  return false
end

-- Creates / updates / completes the to-do. Returns "new" | "open" | "done" | nil (nothing done)
function CraftTodo.check()
  local P = ns.Plans
  if not (CraftTodo.active() and setting("trainerTodo") and P and Store.ready()) then return nil end
  local st = CraftTodo.state()
  if not st then return nil end
  local open = P.findAuto(CraftTodo.TAG)
  if st.n < 1 then
    if open then
      P.finishAuto(CraftTodo.TAG, "trainer")
      return "done"
    end
    return nil
  end
  if open then
    P.upsertAuto(CraftTodo.TAG, CraftTodo.todoText(st.n, st.cost))
    writeMarks(st.marks)
    return "open"
  end
  if not fresh(st.marks) then return nil end
  local id, how = P.upsertAuto(CraftTodo.TAG, CraftTodo.todoText(st.n, st.cost))
  if not id then return nil end -- no marker: the next check tries again
  writeMarks(st.marks)
  return how == "new" and "new" or "open"
end

local Collector = {
  requires = { "UnitLevel" },
  events = { "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "TRAINER_CLOSED", "PLAYER_LEVEL_UP" },
}
CraftTodo.collector = Collector

function Collector:init()
  self.pending = false
  if not CraftTodo.active() then return end
  Core.after(self, CraftTodo.LOGIN_DELAY, function() CraftTodo.check() end)
end

local function schedule(self)
  if self.pending then return end
  self.pending = true
  if not Core.after(self, CraftTodo.CHECK_DELAY, function(s)
    s.pending = false
    CraftTodo.check()
  end) then
    self.pending = false
  end
end

function Collector:onEvent()
  if CraftTodo.active() then schedule(self) end
end

-- Diagnostics (/chronik diag)
function CraftTodo.diagLine()
  local Rz = R()
  if not Rz then return "?" end
  if not Rz.active() then return "off (Retail)" end
  local view = Rz.evaluate({ names = false })
  if not view.available then return "no data (" .. tostring(view.reason) .. ")" end
  local st = CraftTodo.state()
  return string.format("%d professions, learnable now %d, from the trainer %d, to-do %s", #view.profs, view.now.n, st and st.n or 0,
    ns.Plans and ns.Plans.findAuto(CraftTodo.TAG) and "open" or "none")
end

ns.RegisterCollector("CraftTodo", Collector)
