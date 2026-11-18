-- Werkauftrag (facade, 1.1.0): the one entry point "open this work order" for every place that shows one (to-do page, trackers,
-- recipe book, Handwerk page). A work order (single recipe or route) has no window of its own: while the profession window shows
-- the order's workbench, the bar there (journal/ProfessionBar.lua) switches to it; otherwise the facade says in chat where it goes
-- on (next step of ns.Werk.status: auction house, mailbox, workbench, trainer), with the texts of the bar (area "WerkBar").
--   Werkauftrag.open(id, opts)   -> true, "leiste" | "ort"  |  false, reason ("aus" | "kein-auftrag")
--                                   opts.quiet = true: no chat line (the caller shows the hint itself, Werkauftrag.hint)
--   Werkauftrag.hint(id)         -> the hint line of the next step | nil
--   Werkauftrag.where(id)        -> station and next step of the order (ns.Werk.status) | nil
local _, ns = ...

local Journal = ns.Journal
if not Journal then return end

local WA = {}
Journal.Werkauftrag = WA

local function plans() return ns.Plans end

local function openOrder(id)
  local P = plans()
  local p = P and type(P.raw) == "function" and P.raw(id) or nil
  if type(p) ~= "table" or p.done then return nil end
  if type(p.werk) ~= "table" and type(p.shop) ~= "table" then return nil end
  return p
end

function WA.where(id)
  local Wk = ns.Werk
  if not (Wk and type(Wk.status) == "function") then return nil end
  local ok, st = pcall(Wk.status, id)
  return ok and type(st) == "table" and st or nil
end

function WA.hint(id)
  local B = Journal.ProfessionBar
  local st = WA.where(id)
  return st and B and type(B.nextText) == "function" and B.nextText(st) or nil
end

function WA.open(id, opts)
  local Wk = ns.Werk
  if not (Wk and type(Wk.active) == "function" and Wk.active()) then return false, "aus" end
  local p = openOrder(id)
  if not p then return false, "kein-auftrag" end
  opts = type(opts) == "table" and opts or {}
  local B = Journal.ProfessionBar
  if B and type(B.focus) == "function" and B.focus(p.id) == true then return true, "leiste" end
  if not opts.quiet then
    local line = WA.hint(p.id)
    if line and ns.Core and ns.Core.print then ns.Core.print(line) end
  end
  return true, "ort"
end
