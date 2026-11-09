-- Live client values (money, level, XP, icons, spell names) read when the journal opens.
-- Every call runs in pcall; secret values and nil give nil. Live.source replaces the client API in tests.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Live = {}
Journal.Live = Live

local floor, huge = math.floor, math.huge

Live.source = nil

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function resolve(path)
  local src = Live.source
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

local function number(v, lo, hi)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == huge or v == -huge then return nil end
  if (lo and v < lo) or (hi and v > hi) then return nil end
  return v
end

local function validID(v)
  if isSecret(v) then return nil end
  if type(v) == "string" then
    if not string.find(v, "^%d+$") or #v > 10 then return nil end
    v = tonumber(v)
  end
  if type(v) ~= "number" or v ~= v or v <= 0 or v >= 2147483648 or v ~= floor(v) then return nil end
  return v
end
Live.validID = validID

function Live.money()
  return number((call("GetMoney")), 0)
end

function Live.level()
  local v = number((call("UnitLevel", "player")), 1, 200)
  return v and floor(v) or nil
end

function Live.xp()
  local cur = number((call("UnitXP", "player")), 0)
  local max = number((call("UnitXPMax", "player")), 1)
  if not cur or not max then return nil end
  return cur, max
end

function Live.rested()
  return number((call("GetXPExhaustion")), 0)
end

function Live.itemIcon(itemID)
  itemID = validID(itemID)
  if not itemID then return nil end
  local _, _, _, _, icon = call("C_Item.GetItemInfoInstant", itemID)
  if isSecret(icon) then return nil end
  if type(icon) == "number" and icon > 0 and icon == floor(icon) then return icon end
  return nil -- string paths are rejected: texture paths must be literals
end

-- client name of an item (raw text, nil while the client has not loaded it): GetItemNameByID, else GetItemInfo
function Live.itemName(itemID)
  itemID = validID(itemID)
  if not itemID then return nil end
  local n = call("C_Item.GetItemNameByID", itemID)
  if isSecret(n) or type(n) ~= "string" or n == "" then
    if resolve("GetItemInfo") then n = call("GetItemInfo", itemID) else n = call("C_Item.GetItemInfo", itemID) end
  end
  if isSecret(n) or type(n) ~= "string" or n == "" then return nil end
  return n
end

-- Name resolver for pages that show item names from snapshots.items. A missing name comes from the client; if that has not loaded
-- the item either, it is asked for ONCE (C_Item.RequestLoadItemDataByID) and redraw() runs once, bundled, when ITEM_DATA_LOAD_RESULT
-- arrives. Until then the caller shows its placeholder. A name found this way is added to snapshots.items (Store.noteItem).
-- Event only registered while something is pending; no ticker; stop() when the page is left.
function Live.itemNames(parent, redraw, maxLen)
  local w = { pending = {}, asked = {}, dirty = false }
  local ev = type(CreateFrame) == "function" and CreateFrame("Frame", nil, parent) or nil
  w.events = ev
  local function listen(on)
    if not (ev and ev.RegisterEvent and ev.UnregisterEvent) then return end
    pcall(on and ev.RegisterEvent or ev.UnregisterEvent, ev, "ITEM_DATA_LOAD_RESULT")
  end
  local function fire()
    if not w.dirty then return end -- stop() ran in between
    w.dirty = false
    if type(redraw) == "function" then pcall(redraw) end
  end
  if ev and ev.SetScript then
    ev:SetScript("OnEvent", function(_, event, itemID, success)
      if event ~= "ITEM_DATA_LOAD_RESULT" then return end
      itemID = validID(itemID)
      if not itemID or not w.pending[itemID] then return end
      w.pending[itemID] = nil
      if next(w.pending) == nil then listen(false) end
      if success == false or w.dirty then return end
      w.dirty = true
      if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(0.15, fire) else fire() end
    end)
  end
  -- display name of the item, nil if unknown (then loading has been requested)
  function w.name(itemID)
    itemID = validID(itemID)
    if not itemID then return nil end
    local raw = Live.itemName(itemID)
    local S = ns.Sanitize
    local name = raw and S and S.display(raw, maxLen or 80) or nil
    if name and name ~= "" then
      if ns.Store and ns.Store.noteItem then pcall(ns.Store.noteItem, itemID, raw) end
      return name
    end
    if not w.asked[itemID] then
      w.asked[itemID] = true
      if resolve("C_Item.RequestLoadItemDataByID") then
        call("C_Item.RequestLoadItemDataByID", itemID)
        w.pending[itemID] = true
        listen(true)
      end
    end
    return nil
  end
  function w.stop()
    w.pending, w.asked, w.dirty = {}, {}, false
    listen(false)
  end
  return w
end

function Live.spellName(spellID)
  spellID = validID(spellID)
  if not spellID then return nil end
  local name = call("C_Spell.GetSpellName", spellID)
  if isSecret(name) or type(name) ~= "string" or name == "" then return nil end
  return name
end
