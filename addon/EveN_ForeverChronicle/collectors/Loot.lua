-- Collector 'Loot': finds from green up individually, below only counters. Finds come from the chat message (patterns from GlobalStrings); LOOT_OPENED only gives source and quality.
-- A secret message is never guessed (counters.unreadable.loot_msg). Items are stored as item key (Patterns.itemLink); signal FC_LOOT(itemID, count, quality, source, srcID, name).
-- Unreadable source (Retail 12.x): a fresh kill nearby (KILL_TTL_*) gives source 'mob', srcID only if unambiguous and newer than KILL_SRC_MAX s; an approximation (a chest after a kill can count as an enemy).
local _, ns = ...
local Core, Store, Patterns, Context = ns.Core, ns.Store, ns.Patterns, ns.Context

local floor, min, match = math.floor, math.min, string.match

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

-- true only for a readable true (comparing secret values would throw)
local function isTrue(v)
  return not isSecret(v) and v == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function str(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c
end

local function callAll(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  table.remove(r, 1)
  return r
end

local function playerLevel()
  return num(call(UnitLevel, "player"))
end

local GOOD = 2          -- quality green: individually from here
local SLOT_TTL = 20     -- seconds: loot window data stays valid for the message this long
local SLOT_MAX = 60     -- slots per loot window
local KILL_TTL_WINDOW = 20   -- seconds: a kill counts as source when a loot window accompanies the message
local KILL_SRC_MAX = 8        -- seconds: only a kill this fresh and unambiguous provides the npcID (else 'mob' without srcID)
local KILL_TTL_NOWINDOW = 15  -- seconds: same without a loot window (looting without a window, window unreadable)
local KILL_MAX = 8            -- remembered kills
local KILL_DEDUPE = 5         -- seconds: the same kill via FC_KILL_SEEN and FC_KILL

-- messages (GlobalStrings) in order: variants with a quantity first. Columns: name, kind, has quantity.
local MESSAGES = {
  { "LOOT_ITEM_SELF_MULTIPLE", "loot" }, { "LOOT_ITEM_SELF", "loot" },
  { "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "pushed" }, { "LOOT_ITEM_PUSHED_SELF", "pushed" },
  { "LOOT_ITEM_CREATED_SELF_MULTIPLE", "craft" }, { "LOOT_ITEM_CREATED_SELF", "craft" },
  { "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", "bonus" }, { "LOOT_ITEM_BONUS_ROLL_SELF", "bonus" },
}

-- counter group per source
local GROUP = { vendor = "bought", craft = "crafted", mail = "received", trade = "received", ah = "received", quest = "quest_items" }

local Loot = {
  requires = { "UnitGUID" },
  events = { "LOOT_OPENED", "CHAT_MSG_LOOT" },
  signals = { "FC_KILL", "FC_KILL_SEEN" },
}
local handlers = {}

function Loot:init()
  self.slots = {} -- itemID -> { kind, srcID, quality, at }
  self.kills = {} -- fresh kills: { id = npcID or nil (unreadable), at }
  self.window = nil -- last opened loot window: { at, fishing }
end

-- kill from Combat (FC_KILL): the npcID can be secret ('?'), then id stays empty.
local function recentKills(self, ttl)
  local t, out = GetTime(), {}
  for _, k in ipairs(self.kills) do
    if t - k.at <= ttl then out[#out + 1] = k end
  end
  return out
end

local function fallbackMob(self, ttl)
  local list = recentKills(self, ttl)
  if #list == 0 then return nil end
  local id, newest = list[1].id, list[1].at
  for i = 2, #list do
    if list[i].id ~= id then id = nil end
    if list[i].at > newest then newest = list[i].at end
  end
  if GetTime() - newest > KILL_SRC_MAX then id = nil end -- too old for a safe match: only the kind, no ID
  return "mob", id
end

-- source from the loot GUID: mob (npcID), object (object ID), container (opened bag)
local function sourceOf(guid)
  guid = str(guid)
  if not guid then return nil end
  local kind, id = match(guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if kind == "Creature" or kind == "Vehicle" then return "mob", tonumber(id) end
  if kind == "GameObject" then return "object", tonumber(id) end
  if match(guid, "^Item%-") then return "container", nil end
  return nil
end

-- FC_KILL_SEEN fires right at the kill (Combat then waits briefly for XP before FC_KILL); auto-loot can arrive before FC_KILL.
-- The same kill via both signals is remembered once (same npcID within KILL_DEDUPE s).
local function noteKill(self, npcID)
  local id, t, k = num(npcID), GetTime(), self.kills
  for i = #k, 1, -1 do
    if k[i].id == id and t - k[i].at <= KILL_DEDUPE then
      -- duplicate (second signal or second kill of the same npcID): do not create anew, but move the timestamp to the newer kill,
      -- else the younger kill is judged 'too old' for srcID (KILL_SRC_MAX) too early.
      k[i].at = t
      return
    end
  end
  k[#k + 1] = { id = id, at = t }
  while #k > KILL_MAX do table.remove(k, 1) end
end

handlers.FC_KILL = noteKill
handlers.FC_KILL_SEEN = noteKill

handlers.LOOT_OPENED = function(self)
  local t = GetTime()
  for id, s in pairs(self.slots) do
    if t - s.at > SLOT_TTL then self.slots[id] = nil end
  end
  self.window = { at = t, fishing = isTrue(call(IsFishingLoot)) } -- also when the slots are unreadable
  local n = num(call(GetNumLootItems))
  if not n then return end
  local fishing = self.window.fishing
  for slot = 1, min(floor(n), SLOT_MAX) do
    local id = Patterns.itemLink(call(GetLootSlotLink, slot))
    if id then
      local kind, srcID
      if fishing then
        kind = "fishing"
      else
        local src = callAll(GetLootSourceInfo, slot)
        kind, srcID = sourceOf(src and src[1])
      end
      local info = callAll(GetLootSlotInfo, slot)
      self.slots[id] = { kind = kind, srcID = srcID, quality = info and num(info[5]) or nil, at = t }
    end
  end
end

-- source for items without a loot window, from context
local function contextSource(how)
  if how == "craft" then return "craft" end
  if how == "bonus" then return "bonus" end
  if Context then
    local w = Context.first("merchant", "quest", "mail", "trade", "ah")
    if w == "merchant" then return "vendor" end
    if w then return w end
  end
  return "other"
end

local function gotItem(self, link, count, how)
  local id, bonus, quality, name = Patterns.itemLink(link)
  if not id then return end
  count = (num(count) and count >= 1) and floor(count) or 1
  local slot = self.slots[id]
  if slot and GetTime() - slot.at > SLOT_TTL then slot = nil end
  if quality == nil and slot then quality = slot.quality end
  if quality == nil then quality = num(call(C_Item and C_Item.GetItemQualityByID, id)) end
  local kind, srcID
  if slot and how == "loot" and slot.kind then
    kind, srcID = slot.kind, slot.srcID
  elseif how == "loot" then
    -- source unreadable or no window seen: loot window or fresh kill instead of 'other'
    local w = self.window
    local windowFresh = w ~= nil and GetTime() - w.at <= SLOT_TTL
    if windowFresh and w.fishing then
      kind = "fishing"
    elseif windowFresh then
      kind, srcID = fallbackMob(self, KILL_TTL_WINDOW)
    else
      kind, srcID = fallbackMob(self, KILL_TTL_NOWINDOW)
    end
    if not kind then kind, srcID = contextSource(how), nil end
  else
    kind = contextSource(how)
  end
  Store.noteItem(id, name, quality)
  if quality ~= nil then Store.count("loot_quality", quality) end
  if quality ~= nil and quality < GOOD then
    Store.count(GROUP[kind] or "loot", id, count)
  else
    local mapID, x, y = ns.Zone.here()
    Store.append("LT", Patterns.itemKey(id, bonus), count, quality, kind, srcID, playerLevel(), mapID, x, y)
  end
  Core.emit("FC_LOOT", id, count, quality, kind, srcID, name) -- name last (to-do counters match by name)
  if quality == 3 then
    Core.emit("FC_MOMENT", "first_blue", id, 3, "item", true)
  elseif quality ~= nil and quality >= 4 then
    Core.emit("FC_MOMENT", "first_epic", id, quality, "item", true)
  end
end

handlers.CHAT_MSG_LOOT = function(self, text)
  if isSecret(text) then
    Store.count("unreadable", "loot_msg")
    return
  end
  if type(text) ~= "string" then return end
  for i = 1, #MESSAGES do
    local m = MESSAGES[i]
    local matcher = Patterns.compile(m[1])
    if matcher then
      local link, qty = matcher(text)
      if link then
        gotItem(self, link, qty, m[2])
        return
      end
    end
  end
end

function Loot:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("Loot", Loot)
