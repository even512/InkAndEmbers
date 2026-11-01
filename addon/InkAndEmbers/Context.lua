-- ns.Context: which UI windows are open (vendor, trainer, mail, trade, loot, ...).
-- Money and items often arrive after a window closes (PLAYER_MONEY is async), so a window stays active for LINGER seconds.
local _, ns = ...
local Core = ns.Core

local Context = {}
ns.Context = Context

Context.LINGER = 1.5    -- seconds
Context.MAX_OPEN = 900  -- seconds; an open window without a close event counts as closed after this

-- window -> { open event, close event }
Context.WINDOWS = {
  merchant = { "MERCHANT_SHOW", "MERCHANT_CLOSED" },
  trainer = { "TRAINER_SHOW", "TRAINER_CLOSED" },
  taxi = { "TAXIMAP_OPENED", "TAXIMAP_CLOSED" },
  ah = { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" },
  mail = { "MAIL_SHOW", "MAIL_CLOSED" },
  trade = { "TRADE_SHOW", "TRADE_CLOSED" },
  guildbank = { "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED" },
  bank = { "BANKFRAME_OPENED", "BANKFRAME_CLOSED" },
  loot = { "LOOT_OPENED", "LOOT_CLOSED" },
  quest = { "QUEST_COMPLETE", "QUEST_FINISHED" },
}

local state = {}

local function now()
  return type(GetTime) == "function" and GetTime() or 0
end

local function reset()
  state = {}
end

local function setOpen(name, open)
  local s = state[name]
  if not s then
    s = {}
    state[name] = s
  end
  local t = now()
  if open then
    s.open, s.openedAt, s.closedAt = true, t, nil
  else
    s.open, s.closedAt = false, t
  end
end

function Context.active(name)
  local s = state[name]
  if not s then return false end
  local t = now()
  if s.open then return t - (s.openedAt or t) <= Context.MAX_OPEN end
  return s.closedAt ~= nil and t - s.closedAt <= Context.LINGER
end

function Context.isOpen(name)
  local s = state[name]
  return s ~= nil and s.open == true and now() - (s.openedAt or now()) <= Context.MAX_OPEN
end

-- first active window of a list (order = priority), or nil
function Context.first(...)
  for i = 1, select("#", ...) do
    local name = select(i, ...)
    if Context.active(name) then return name end
  end
  return nil
end

if Core and Core.on then
  for name, ev in pairs(Context.WINDOWS) do
    Core.on(ev[1], function() setOpen(name, true) end)
    Core.on(ev[2], function() setOpen(name, false) end)
  end
  Core.on("PLAYER_ENTERING_WORLD", reset)
  Core.on("PLAYER_LOGIN", reset)
end
Context.reset = reset
