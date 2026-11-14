-- Collector 'RecipeScan' (change "runde3", package R; WoW Forever only, idle in Retail): when the profession window opens
-- (TRADE_SKILL_SHOW) or its list changes (TRADE_SKILL_LIST_UPDATE) every recipe of that profession is read - learned and not yet
-- learned ones - and stored in the recipe cache (RecipeCache.put, schema in RecipeCache.lua).
-- Only the modern C_TradeSkillUI is read (Forever has no GetTradeSkill*): GetBaseProfessionInfo, GetAllRecipeIDs, GetRecipeInfo,
-- GetRecipeSchematic (reagents, output). Nothing is clicked, selected, filtered or crafted. Every call runs in pcall, secret values are
-- skipped, nothing is read in combat. The events are batched (SETTLE); the recipes are read in small chunks (CHUNK per step) so the
-- window never hitches; a new scan of the same profession waits GAP_SHOW / GAP_UPDATE seconds. Windows of other players (linked,
-- guild, NPC crafting) are never stored.
local _, ns = ...
local Core = ns.Core

local floor, min = math.floor, math.min

local RecipeScan = {
  requires = { "C_TradeSkillUI.GetBaseProfessionInfo", "C_TradeSkillUI.GetAllRecipeIDs", "C_TradeSkillUI.GetRecipeInfo",
    "C_TradeSkillUI.GetRecipeSchematic" },
  events = { "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE" },
}
ns.RecipeScan = RecipeScan

RecipeScan.SETTLE = 0.8       -- seconds: events are batched this long, then one scan starts
RecipeScan.STEP = 0.05        -- seconds between two chunks
RecipeScan.CHUNK = 25         -- recipes read per chunk
RecipeScan.GAP_SHOW = 5       -- seconds before the same profession is read again after the window opened
RecipeScan.GAP_UPDATE = 30    -- ... after a list update (they come often: sorting, filtering, searching)
RecipeScan.RETRIES = 3        -- repeats of a scan whose learned recipes lack their difficulty
RecipeScan.RETRY_DELAY = 2    -- seconds between them
RecipeScan.MAX_IDS = 1000     -- recipe ids looked at per profession

local handlers = {}
local queue

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
  if isSecret(v) or type(v) ~= "table" then return nil end
  return v
end

-- first result of fn(...) under pcall; nil on an error or a secret value
local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a = pcall(fn, ...)
  if not ok or isSecret(a) then return nil end
  return a
end

-- guarded field read
local function field(t, k)
  if not tbl(t) then return nil end
  local ok, v = pcall(function() return t[k] end)
  if not ok or isSecret(v) then return nil end
  return v
end

local function api()
  local t = rawget(_G, "C_TradeSkillUI")
  return tbl(t)
end

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, r = pcall(InCombatLockdown)
  return not ok or isSecret(r) or r == true
end

-- Retail client: the shared check of the journal (project id AND interface version); Forever stays on
local function retail()
  local ms = ns.Journal and ns.Journal.MapSpace
  return ms ~= nil and type(ms.retailClient) == "function" and ms.retailClient() == true
end

-- the window shows the own profession (not a linked, guild or NPC window)
local function ownWindow(ui)
  for _, name in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting" }) do
    local fn = ui[name]
    if type(fn) == "function" and call(fn) == true then return false end
  end
  return true
end

-- { id, name, skill, max } of the open profession; nil when it cannot be read
local function baseInfo(ui)
  local info = tbl(call(ui.GetBaseProfessionInfo))
  if not info then return nil end
  local id = num(field(info, "professionID"))
  if not id or id < 1 then return nil end
  local name = str(field(info, "professionName")) or str(field(info, "name"))
  local skill = num(field(info, "skillLevel"))
  local max = num(field(info, "maxSkillLevel")) or num(field(info, "maxSkill")) or num(field(info, "max"))
  return { id = floor(id), name = name, skill = skill and floor(skill), max = max and floor(max) }
end

-- one recipe -> { n, l, d, u, o, q, r }; nil when it has no name
local function readRecipe(ui, rid)
  local info = tbl(call(ui.GetRecipeInfo, rid))
  local n = info and str(field(info, "name"))
  if not n then return nil end
  local rec = { n = n, l = field(info, "learned") == true, d = num(field(info, "relativeDifficulty")), u = num(field(info, "numSkillUps")), i = num(field(info, "icon")), r = {} }
  local sc = tbl(call(ui.GetRecipeSchematic, rid, false))
  if sc then
    rec.o, rec.q = num(field(sc, "outputItemID")), num(field(sc, "quantityMin"))
    local slots = tbl(field(sc, "reagentSlotSchematics"))
    local count = slots and num(call(function() return #slots end)) or 0
    for i = 1, min(count, 16) do
      local slot = tbl(field(slots, i))
      local rtype = field(slot, "reagentType")
      -- only the basic reagents (1); optional and finishing slots are no cost of the recipe
      if slot and (rtype == nil or num(rtype) == 1) then
        local need = num(field(slot, "quantityRequired"))
        local first = tbl(field(slot, "reagents")) and tbl(field(field(slot, "reagents"), 1))
        local item = first and num(field(first, "itemID"))
        if need and item and need >= 1 and item >= 1 then rec.r[#rec.r + 1] = { floor(item), floor(need) } end
      end
    end
  end
  -- no output item from the schematic: ask the client for it once more (an item link or id of the product); stays nil for enchantments
  if not rec.o and type(ui.GetRecipeOutputItemData) == "function" then
    local out = tbl(call(ui.GetRecipeOutputItemData, rid))
    local id = out and num(field(out, "itemID"))
    if not id and out then
      local link = str(field(out, "hyperlink"))
      id = link and tonumber(string.match(link, "item:(%d+)")) or nil
    end
    if id and id >= 1 then rec.o = floor(id) end
  end
  return rec
end

-- one chunk of the running job; schedules the next one, stores the result at the end
local function step(self, job)
  if self.job ~= job then return end -- replaced by a newer scan
  if inCombat() then
    self.job = nil -- never half a scan in combat: the next event starts again
    return
  end
  local ui = api()
  if not ui then
    self.job = nil
    return
  end
  local last = min(job.i + RecipeScan.CHUNK - 1, #job.ids)
  for i = job.i, last do
    local rid = job.ids[i]
    local ok, rec = pcall(readRecipe, ui, rid)
    if ok and rec then job.recipes[rid] = rec end
  end
  job.i = last + 1
  if job.i <= #job.ids then
    if not Core.after(self, RecipeScan.STEP, function(s) step(s, job) end) then self.job = nil end
    return
  end
  self.job = nil
  if ns.RecipeCache and ns.RecipeCache.put(job.prof.id, job.prof, job.recipes) then
    self.scans = (self.scans or 0) + 1
    -- the window sometimes shows its list before the difficulties are there: a learned recipe without one means "not ready yet";
    -- the scan counts only when none is missing (else it is repeated up to RETRIES times, RETRY_DELAY apart)
    local missing = 0
    for _, r in pairs(job.recipes) do
      if r.l == true and r.d == nil then missing = missing + 1 end
    end
    local tries = (self.tries[job.prof.id] or 0)
    if missing > 0 and tries < RecipeScan.RETRIES then
      self.tries[job.prof.id] = tries + 1
      self.last[job.prof.id] = nil
      queue(self, "show", RecipeScan.RETRY_DELAY)
    else
      self.tries[job.prof.id] = nil
      self.last[job.prof.id] = { at = GetTime and GetTime() or 0, kind = job.kind, skill = job.prof.skill }
    end
  end
end

-- start of a scan (after the settle time)
local function scan(self, kind)
  self.timer = false
  if retail() or inCombat() or self.job then return end
  local ui = api()
  if not ui or ns.RecipeCache == nil then return end
  if not ownWindow(ui) then return end
  local prof = baseInfo(ui)
  if not prof then return end
  local now = GetTime and GetTime() or 0
  local seen = self.last[prof.id]
  if seen then
    local gap = kind == "show" and RecipeScan.GAP_SHOW or RecipeScan.GAP_UPDATE
    -- a changed skill level changes the difficulty colours of the recipes: read again at once (after the batching time)
    local skillMoved = prof.skill ~= nil and seen.skill ~= nil and prof.skill ~= seen.skill
    if now - seen.at < gap and not skillMoved then return end
  end
  local list = tbl(call(ui.GetAllRecipeIDs))
  if not list then return end
  local count = num(call(function() return #list end)) or 0
  local ids = {}
  for i = 1, min(count, RecipeScan.MAX_IDS) do
    local id = num(field(list, i))
    if id and id >= 1 then ids[#ids + 1] = floor(id) end
  end
  if #ids == 0 then return end
  local job = { prof = prof, ids = ids, i = 1, recipes = {}, kind = kind }
  self.job = job
  step(self, job)
end

function queue(self, kind, delay)
  if retail() then return end
  -- "show" outranks "update" (the shorter gap wins when both come in one batch)
  if kind == "show" or not self.pendingKind then self.pendingKind = kind end
  if self.timer then return end
  self.timer = true
  if not Core.after(self, delay or RecipeScan.SETTLE, function(s)
    local k = s.pendingKind or "update"
    s.pendingKind = nil
    scan(s, k)
  end) then
    self.timer = false
  end
end

function RecipeScan:init()
  self.timer, self.job, self.pendingKind, self.last, self.scans, self.tries = false, nil, nil, {}, 0, {}
end

handlers.TRADE_SKILL_SHOW = function(self) queue(self, "show") end
handlers.TRADE_SKILL_LIST_UPDATE = function(self) queue(self, "update") end
handlers.TRADE_SKILL_CLOSE = function(self)
  self.job = nil -- the window is gone: a running scan stops (the next opening starts a new one)
end

function RecipeScan:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("RecipeScan", RecipeScan)
