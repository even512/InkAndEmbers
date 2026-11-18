-- Collector 'LehrerBesuch' (Werkauftrag, WoW Forever only; idle in Retail): remembers every profession trainer the player visits.
-- When a trainer window opens (TRAINER_SHOW, read after Trainer.READ_DELAY-like settle time) and it is a profession trainer, the npc
-- (UnitGUID "npc"), its name and the player's position (Zone.raw: mapID, x, y) go to chars[guid].werkTrainers through
-- Journal.LehrerOrte.remember. Own visits win over the QuestieDB data when the next trainer is chosen.
-- Which profession: the npc's line in the QuestieDB data (ProfTrainers.lua), else the profession whose cached recipe names
-- (recipe cache, collectors/RecipeScan.lua) appear among the trainer's services. A class or pet trainer is never stored
-- (IsTradeskillTrainer, when the client has it, must say yes; without a line the visit is not stored).
-- Only reading APIs, each in pcall with secret-value guards; nothing is clicked or bought.
local _, ns = ...
local Core = ns.Core

local floor, min = math.floor, math.min

local Besuch = {}
ns.LehrerBesuch = Besuch

Besuch.DELAY = 0.4        -- seconds after TRAINER_SHOW (the service list fills right after the event)
Besuch.MAX_SERVICES = 200 -- services looked at

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

local function callAll(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  table.remove(r, 1)
  return r
end

local function retail()
  local ms = ns.Journal and ns.Journal.MapSpace
  return ms ~= nil and type(ms.retailClient) == "function" and ms.retailClient() == true
end

local function npcOf()
  local r = callAll(rawget(_G, "UnitGUID"), "npc")
  local guid = r and str(r[1])
  if not guid then return nil end
  local kind, id = string.match(guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if kind ~= "Creature" or not id then return nil end
  return tonumber(id)
end

-- profession of the trainer from its services: the cached profession with the most recipe names among them
local function lineFromServices()
  local E = ns.Einkauf
  local cache = E and E.cache and E.cache()
  if not cache then return nil end
  local r = callAll(rawget(_G, "GetNumTrainerServices"))
  local n = r and num(r[1])
  if not n or n < 1 then return nil end
  local names = {}
  for i = 1, min(floor(n), Besuch.MAX_SERVICES) do
    local v = callAll(rawget(_G, "GetTrainerServiceInfo"), i)
    local nm = v and str(v[1])
    if nm then names[nm] = true end
  end
  local best, bestN = nil, 0
  for prof, p in pairs(cache) do
    if type(prof) == "number" and type(p) == "table" and type(p.recipes) == "table" then
      local hits = 0
      for _, rec in pairs(p.recipes) do
        if type(rec) == "table" and type(rec.n) == "string" and names[rec.n] then hits = hits + 1 end
      end
      if hits > bestN or (hits == bestN and hits > 0 and prof < best) then best, bestN = prof, hits end
    end
  end
  return best
end

-- reads the open trainer window -> true when a profession trainer was stored
function Besuch.read()
  local LO = ns.Journal and ns.Journal.LehrerOrte
  if not LO or retail() then return false end
  local isTs = rawget(_G, "IsTradeskillTrainer")
  if type(isTs) == "function" then
    local r = callAll(isTs)
    if not r or r[1] ~= true then return false end
  end
  local npc = npcOf()
  if not npc then return false end
  local d = LO.dataOf(npc)
  local line = d and d.line or lineFromServices()
  if not line then return false end
  local Z = ns.Zone
  local m, x, y
  if Z and type(Z.raw) == "function" then
    local ok, a, b, c = pcall(Z.raw)
    if ok then m, x, y = a, b, c end
  end
  local nm = callAll(rawget(_G, "UnitName"), "npc")
  return LO.remember(npc, line, m, x, y, nm and str(nm[1]))
end

local Collector = {
  requires = { "UnitGUID" },
  events = { "TRAINER_SHOW" },
}
Besuch.collector = Collector

function Collector:init()
  self.pending = false
end

function Collector:onEvent()
  if self.pending or retail() then return end
  self.pending = true
  if not Core.after(self, Besuch.DELAY, function(s)
    s.pending = false
    Besuch.read()
  end) then
    self.pending = false
  end
end

ns.RegisterCollector("LehrerBesuch", Collector)
