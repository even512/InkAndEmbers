-- Collector 'Extras': consumables, emotes, fishing, casts, jumps, PvP flag. Counters only, no log lines (exception: the first_fish moment).
-- counters.consumables[itemID], counters.consumed[kind] (potion|elixir|flask|food_drink|bandage|other), counters.emotes[TOKEN], counters.fishing[itemID];
-- counters.casts[spellID] (own successful casts), counters.misc.jumps, counters.misc.pvpFlagOn (PvP flag switched on);
-- counters.reagents[itemID] is an approximation: bag decrease shortly after an own cast (not at vendor, mail, trade, bank, AH).
local _, ns = ...
local Core, Store, Context = ns.Core, ns.Store, ns.Context

local floor, min = math.floor, math.min

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

local SCAN_DELAY = 0.3     -- seconds: BAG_UPDATE_DELAYED batched
local CAST_DELAY = 0.8     -- seconds after an own cast: recount reagents
local CAST_WINDOW = 3.0    -- seconds: a decrease belongs to a cast this recent (scan gap is 2 s)
local SCAN_GAP = 2.0       -- seconds: minimum gap between bag scans (a deferred scan catches up)
local EMOTE_WINDOW = 1.0   -- seconds: hook and text emote of the same emote
local BAGS = 5             -- bags 0 (backpack) to 4 and 5 (reagent bag; without it the client reports 0 slots)
local SLOTS_MAX = 40
local META_MAX = 3000
local CLASS_CONSUMABLE, CLASS_REAGENT = 0, 5
local KIND = { [1] = "potion", [2] = "elixir", [3] = "flask", [5] = "food_drink", [7] = "bandage" }

local Extras = {
  requires = { "UnitName" },
  events = { "CHAT_MSG_TEXT_EMOTE", "BAG_UPDATE_DELAYED", "PLAYER_PVP_FLAG_CHANGED" },
  unitEvents = { UNIT_SPELLCAST_SUCCEEDED = { "player" }, UNIT_FACTION = { "player" } },
  signals = { "FC_LOOT" },
}
local handlers = {}

-- Bags

local function scanBags(self)
  local C = C_Container
  if type(C) ~= "table" or isSecret(C) or type(C_Item) ~= "table" then return nil end
  local counts = {}
  for bag = 0, BAGS do
    local n = num(call(C.GetContainerNumSlots, bag))
    for slot = 1, min(n and floor(n) or 0, SLOTS_MAX) do
      local info = tbl(call(C.GetContainerItemInfo, bag, slot))
      local id = info and num(info.itemID)
      if id then
        id = floor(id)
        local meta = self.meta[id]
        if meta == nil then
          local r = callAll(C_Item.GetItemInfoInstant, id)
          meta = { class = r and num(r[6]), sub = r and num(r[7]) }
          if meta.class == CLASS_CONSUMABLE then
            local sp = callAll(C_Item.GetItemSpell, id)
            local spellID = sp and num(sp[2])
            if spellID then
              meta.spell = floor(spellID)
              self.spellItem[meta.spell] = id
            end
          end
          if self.metaCount < META_MAX then
            self.meta[id] = meta
            self.metaCount = self.metaCount + 1
          end
        end
        if meta.class == CLASS_REAGENT then counts[id] = (counts[id] or 0) + (num(info.stackCount) or 1) end
      end
    end
  end
  return counts
end

local function tradeContext()
  return Context ~= nil and Context.first("merchant", "mail", "trade", "ah", "guildbank", "bank") ~= nil
end

local function rescan(self)
  local counts = scanBags(self)
  if not counts then return end
  local base = self.reagents
  if base and self.castAt and GetTime() - self.castAt <= CAST_WINDOW and not tradeContext() then
    for id, old in pairs(base) do
      local drop = old - (counts[id] or 0)
      if drop > 0 then Store.count("reagents", id, drop) end
    end
  end
  self.reagents = counts
end

local function scheduleScan(self, delay)
  if self.scanOn then return end
  -- minimum gap: the scan is pushed back, not dropped, and then reads the current state
  local wait = delay
  if self.scanAt then wait = math.max(delay, self.scanAt + SCAN_GAP - GetTime()) end
  self.scanOn = true
  if not Core.after(self, wait, function(s)
    s.scanOn = false
    s.scanAt = GetTime()
    rescan(s)
  end) then
    self.scanOn = false
  end
end

handlers.BAG_UPDATE_DELAYED = function(self)
  scheduleScan(self, SCAN_DELAY)
end

handlers.UNIT_SPELLCAST_SUCCEEDED = function(self, unit, castGUID, spellID)
  if unit ~= "player" then return end
  spellID = num(spellID)
  if not spellID then return end
  spellID = floor(spellID)
  self.castAt = GetTime()
  -- every own cast counts once (B2): one table increment, the same castGUID twice in a row counts once
  local gid = str(castGUID)
  if not (gid and self.lastCastGUID == gid) then
    self.lastCastGUID = gid
    Store.count("casts", spellID)
  end
  local itemID = self.spellItem[spellID]
  if itemID and not (str(castGUID) and self.lastCast[spellID] == castGUID) then
    self.lastCast[spellID] = str(castGUID)
    local meta = self.meta[itemID]
    Store.count("consumables", itemID)
    Store.count("consumed", KIND[meta and meta.sub or 0] or "other")
  end
  -- recount reagents only if bags hold any (saves querying all bags on every cast)
  if self.reagents and next(self.reagents) then scheduleScan(self, CAST_DELAY) end
end

-- PvP flag (B12): counts the switch from off to on; the state at start is only remembered. PLAYER_PVP_FLAG_CHANGED exists on Forever,
-- UNIT_FACTION covers both clients.
local function readPvp()
  local v = call(UnitIsPVP, "player")
  if isSecret(v) or type(v) ~= "boolean" then return nil end
  return v
end

local function checkPvp(self)
  local now = readPvp()
  if now == nil then return end
  local was = self.pvp
  self.pvp = now
  if now == true and was == false then Store.count("misc", "pvpFlagOn") end
end

handlers.PLAYER_PVP_FLAG_CHANGED = function(self) checkPvp(self) end
handlers.UNIT_FACTION = function(self, unit)
  if unit == "player" then checkPvp(self) end
end

-- Emotes

local function onEmote(self, token)
  local t = str(token)
  if not t then return end
  self.emoteAt = GetTime()
  Store.count("emotes", string.upper(t))
end

handlers.CHAT_MSG_TEXT_EMOTE = function(self, text, sender)
  if isSecret(text) or isSecret(sender) then
    Store.count("unreadable", "emote_msg")
    return
  end
  local me = str(call(UnitName, "player"))
  local name = str(sender)
  if not me or not name then return end
  -- own emote: "Name", "Name-Realm" or on Forever "Vorname Nachname"/"Vorname-Nachname" (Names.isMe)
  local mine
  if ns.Names then mine = ns.Names.isMe(name) else mine = string.match(name, "^[^%-]+") == me end
  if not mine then return end
  if self.emoteAt and GetTime() - self.emoteAt <= EMOTE_WINDOW then return end -- the hook already counted this emote
  Store.count("emotes", "unknown")
end

-- Fishing

-- true if the character has fished before (counters.fishing not empty)
local function hasFished()
  local char = Store.char()
  local c = char and type(char.counters) == "table" and char.counters.fishing
  return type(c) == "table" and next(c) ~= nil
end

handlers.FC_LOOT = function(self, itemID, count, quality, source)
  if source ~= "fishing" then return end
  local first = not hasFished() -- before counting: else every catch would be the first
  if Store.count("fishing", itemID, num(count) or 1) and first then
    Core.emit("FC_MOMENT", "first_fish", itemID, nil, nil, true)
  end
end


function Extras:init()
  self.meta, self.metaCount, self.spellItem, self.lastCast = {}, 0, {}, {}
  self.reagents = nil
  self.pvp = readPvp()
  Core.hook(self, "DoEmote", onEmote)
  Core.hook(self, "JumpOrAscendStart", function() Store.count("misc", "jumps") end) -- B8: one increment per jump
  Core.after(self, 2, function(s)
    s.scanAt = GetTime()
    rescan(s)
  end) -- learn the bags at start (without counting)
end

function Extras:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("Extras", Extras)
