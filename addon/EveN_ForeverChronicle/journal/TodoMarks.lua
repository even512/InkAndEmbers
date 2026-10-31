-- To-do enemy marks. Enemies that are an open kill goal get a "To Do: 3/10" line in their tooltip (at most TIP_MAX) and a
-- small book icon on the nameplate (own texture on an own frame, parented to the plate).
-- Unprotected paths only: TooltipDataProcessor.AddTooltipPostCall (fallback GameTooltip OnTooltipSetUnit),
-- C_NamePlate.GetNamePlateForUnit, NAME_PLATE_UNIT_ADDED/REMOVED. No OnUpdate; re-evaluated when a plate appears (now and
-- one frame later), on tooltips and after a to-do change.
-- Midnight secret values: GUID and name can be secret in combat and instances. They are checked with issecretvalue before
-- any use and silently skipped (never compared, used as table key or printed). Forbidden tooltips and plates are not touched.
-- Placement (left | right | top) avoids icons of other addons (Questie ...): place() only reads their rects and shifts
-- the own icon outward; if the distance gets too large it switches to the side with the shortest one.
local _, ns = ...

local Journal = ns.Journal
if not Journal then return end
local Theme = Journal.Theme

local floor, lower, match = math.floor, string.lower, string.match

local TodoMarks = {}
Journal.TodoMarks = TodoMarks

TodoMarks.TIP_MAX = 3
TodoMarks.ICON = 16
TodoMarks.TIP_ICON = 14
TodoMarks.TEXT = ns.Locale.ns("TodoMarks", {
  tip = "To Do: %s",
  opt = "To-Do-Gegner markieren",
  reason_forbidden = "verbotene Plakette",
  reason_noPlate = "keine Plakette zur Einheit",
  reason_secret = "GUID/Name gesperrt",
  reason_noAnchor = "kein Anker (UnitFrame fehlt)",
  reason_noMatch = "kein Treffer",
  reason_noTargets = "keine offenen Kill-Ziele",
  reason_off = "ausgeschaltet",
  reason_badUnit = "ungültige Einheit",
  how_guid = "GUID",
  how_name = "Name",
  how_tooltip = "Tooltip-Daten",
  diagMain = "Namensplaketten-Markierung: %s; Plaketten gesehen %d, verboten %d, jetzt markiert %d, bisher %d",
  stateOn = "an",
  stateOff = "aus",
  diagHow = "; letzter Treffer über %s an %s",
  diagBase = "Grundrahmen",
  diagFail = "; letzter Ausfall: %s",
  diagPlace = "; Lage des Symbols: %s",
  diagShift = ", %d px nach außen (Fremdsymbol: %s)",
  side_left = "links",
  side_right = "rechts",
  side_top = "oben",
  diagPlace = "; Lage des Symbols: %s",
  diagShift = ", %d px nach außen (Fremdsymbol: %s)",
  side_left = "links",
  side_right = "rechts",
  side_top = "oben",
  diagNoEvent = " (noch kein NAME_PLATE_UNIT_ADDED angekommen - Namensplaketten an?)",
  diagSecret = "; Ziel-Identität gesperrt: %s",
  yes = "ja",
  no = "nein",
})
TodoMarks.COLOR = { 0.98, 0.82, 0.45 }

local T = TodoMarks.TEXT
local st = { index = nil, plates = {}, marks = setmetatable({}, { __mode = "k" }), hooked = false }
-- icon frames (weak keys; never write a field onto a Blizzard frame, it would taint it)
TodoMarks.state = st

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function str(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if not ok then return nil end
  return a, b
end

local function forbidden(f)
  if type(f) ~= "table" then return true end
  if type(f.IsForbidden) == "function" then
    local ok, v = pcall(f.IsForbidden, f)
    if not ok or isSecret(v) or v then return true end
  end
  return false
end

local function iconFile()
  return (Theme and Theme.TEX and (Theme.TEX.minimapIcon or Theme.TEX.minimap))
    or "Interface\\AddOns\\EveN_ForeverChronicle\\Media\\MinimapIcon"
end

function TodoMarks.npcIdOf(guid)
  guid = str(guid)
  if not guid then return nil end
  local kind, id = match(guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if (kind == "Creature" or kind == "Vehicle") and id then return tonumber(id) end
  return nil
end

function TodoMarks.enabled()
  local TT = Journal.TodoTracker
  if not (TT and TT.settings) then return true end
  local ok, s = pcall(TT.settings)
  if not ok or type(s) ~= "table" then return true end
  return s.marks ~= false
end

local function buildIndex()
  local idx = { byId = {}, byName = {}, any = false }
  local Plans = ns.Plans
  local list = Plans and type(Plans.list) == "function" and call(Plans.list, "open") or nil
  if type(list) ~= "table" then return idx end
  for _, p in ipairs(list) do
    if type(p) == "table" and not p.done and p.kind == "kill" and type(p.target) == "table" then
      local entry = { plan = p }
      local id = num(p.target.id)
      local nm = str(p.target.name)
      if id then
        idx.byId[id] = idx.byId[id] or {}
        table.insert(idx.byId[id], entry)
        idx.any = true
      end
      if nm then
        local key = lower(nm)
        idx.byName[key] = idx.byName[key] or {}
        table.insert(idx.byName[key], entry)
        idx.any = true
      end
    end
  end
  return idx
end

local function index()
  if st.index then return st.index end
  local idx = buildIndex()
  local Store = ns.Store
  if Store and type(Store.ready) == "function" and Store.ready() then st.index = idx end
  return idx
end

function TodoMarks.invalidate()
  st.index = nil
end

local function progressOf(p)
  if type(p.progress) == "string" and not isSecret(p.progress) and match(p.progress, "^%d+/%d+$") then return p.progress end
  local need, have = num(p.need) or 1, num(p.have) or 0
  return string.format("%d/%d", floor(have), floor(need))
end

function TodoMarks.match(npcID, name)
  local idx = index()
  if not idx.any then return {} end
  local out, seen = {}, {}
  local id = num(npcID)
  local nm = str(name)
  local function take(list)
    for _, e in ipairs(list or {}) do
      if not seen[e] then
        seen[e] = true
        out[#out + 1] = e.plan
      end
    end
  end
  if id then take(idx.byId[id]) end
  if nm then take(idx.byName[lower(nm)]) end
  return out
end

-- Unit identity: npcID (from the GUID) and name, unsecret values only. Midnight makes GUID/name of non-player units outside
-- the group secret (SecretWhenUnitIdentityRestricted). If both are secret, fall back to C_TooltipInfo.GetUnit (the data the
-- enemy tooltip gets its GUID from, works in combat), checked before use as well.
-- -> id, name, how ("guid" | "name" | "tooltip" | nil), secret (true if GUID or name was secret)
function TodoMarks.identify(unit)
  if not str(unit) then return nil, nil, nil, isSecret(unit) end
  local guid = call(UnitGUID, unit)
  local rawName = call(UnitName, unit)
  local secret = isSecret(guid) or isSecret(rawName)
  local id = TodoMarks.npcIdOf(guid)
  local name = str(rawName)
  if id then return id, name, "guid", secret end
  if name then return nil, name, "name", secret end
  local CTI = C_TooltipInfo
  local data = type(CTI) == "table" and call(CTI.GetUnit, unit) or nil
  if type(data) ~= "table" or isSecret(data) then return nil, nil, nil, secret end
  local g = data.guid -- only assign, never test (may be secret)
  id = TodoMarks.npcIdOf(g)
  local lines = data.lines
  if type(lines) == "table" and not isSecret(lines) then
    local l1 = lines[1]
    if type(l1) == "table" and not isSecret(l1) then name = str(l1.leftText) end
  end
  if id or name then return id, name, "tooltip", secret end
  return nil, nil, nil, secret
end

function TodoMarks.forUnit(unit)
  if not str(unit) then return {} end
  if not index().any then return {} end
  local isPlayer = call(UnitIsPlayer, unit)
  if not isSecret(isPlayer) and isPlayer == true then return {} end
  local id, name, how, secret = TodoMarks.identify(unit)
  return TodoMarks.match(id, name), how, secret
end

function TodoMarks.tipLines(plans)
  local out = {}
  local icon = string.format("|T%s:%d:%d|t ", iconFile(), TodoMarks.TIP_ICON, TodoMarks.TIP_ICON)
  for i = 1, math.min(#plans, TodoMarks.TIP_MAX) do
    out[#out + 1] = icon .. string.format(T.tip, progressOf(plans[i]))
  end
  return out
end

function TodoMarks.onTooltip(tooltip, data)
  if not TodoMarks.enabled() or forbidden(tooltip) or type(tooltip.AddLine) ~= "function" then return end
  if not index().any then return end
  local plans
  local guid
  if type(data) == "table" and not isSecret(data) then guid = data.guid end -- only assign, never test (may be secret)
  local id = TodoMarks.npcIdOf(guid)
  local unit
  if type(tooltip.GetUnit) == "function" then
    local ok, _, u = pcall(tooltip.GetUnit, tooltip)
    if ok then unit = str(u) end
  end
  if unit then
    plans = TodoMarks.forUnit(unit)
    if #plans == 0 and id then plans = TodoMarks.match(id, nil) end
  else
    plans = TodoMarks.match(id, nil)
  end
  if #plans == 0 then return end
  local c = TodoMarks.COLOR
  for _, line in ipairs(TodoMarks.tipLines(plans)) do
    pcall(tooltip.AddLine, tooltip, line, c[1], c[2], c[3])
  end
  if type(tooltip.Show) == "function" then pcall(tooltip.Show, tooltip) end
end

local function hookTooltip()
  if st.hooked then return true end
  local TDP = TooltipDataProcessor
  local kind = type(Enum) == "table" and type(Enum.TooltipDataType) == "table" and Enum.TooltipDataType.Unit or nil
  if type(TDP) == "table" and type(TDP.AddTooltipPostCall) == "function" and kind ~= nil then
    local ok = pcall(TDP.AddTooltipPostCall, kind, function(tooltip, data) pcall(TodoMarks.onTooltip, tooltip, data) end)
    if ok then
      st.hooked = "processor"
      return true
    end
  end
  local GT = GameTooltip
  if type(GT) == "table" and type(GT.HookScript) == "function" then
    local ok = pcall(GT.HookScript, GT, "OnTooltipSetUnit", function(tooltip) pcall(TodoMarks.onTooltip, tooltip, nil) end)
    if ok then
      st.hooked = "script"
      return true
    end
  end
  return false
end
TodoMarks.hookTooltip = hookTooltip

-- Nameplates (Retail 12.x): the plate itself is only the base frame set by the client; the visible UnitFrame comes from a
-- pool, is borrowed on every NAME_PLATE_UNIT_ADDED and returned on REMOVED (hidden, anchors cleared). So the icon is
-- re-anchored to the current UnitFrame on every show (own frame only, never a field on the Blizzard frame), one level
-- above it, and evaluated once more a frame later (the event can reach us before Blizzard's driver, with no UnitFrame yet).
-- Forbidden plates (FORBIDDEN_NAME_PLATE_UNIT_ADDED, e.g. in instances) are not returned to unprotected code by
-- GetNamePlateForUnit and their rect is unreadable: no icon possible, only counted (/chronik diag).

TodoMarks.REASON = setmetatable({}, { __index = function(_, k) return T["reason_" .. tostring(k)] end })
TodoMarks.HOW = setmetatable({}, { __index = function(_, k)
  if k == "guid" or k == "name" or k == "tooltip" then return T["how_" .. k] end
  return nil
end })
local R = TodoMarks.REASON

local function clock() return num(call(GetTime)) or 0 end

st.diag = { seen = 0, forbidden = 0, marked = 0, reason = nil, reasonUnit = nil, reasonAt = nil, how = nil, anchor = nil,
  side = nil, shift = nil, who = nil }
local D = st.diag

local function fail(reason, unit)
  D.reason, D.reasonUnit, D.reasonAt = reason, str(unit), clock()
  return false
end

local function plateOf(unit)
  local CN = C_NamePlate
  if type(CN) ~= "table" then return nil end
  local plate = call(CN.GetNamePlateForUnit, unit)
  if type(plate) ~= "table" or isSecret(plate) or forbidden(plate) then return nil end
  return plate
end

local function anchorOf(plate)
  local uf = plate.UnitFrame
  if type(uf) ~= "table" or isSecret(uf) or forbidden(uf) then return nil end
  for _, key in ipairs({ "HealthBarsContainer", "healthBar", "name" }) do
    local a = uf[key]
    if type(a) == "table" and not isSecret(a) and not forbidden(a) then return a, uf, key end
  end
  return uf, uf, "UnitFrame"
end

function TodoMarks.markOf(plate)
  return st.marks[plate]
end

local function markFor(plate)
  local m = st.marks[plate]
  if m then return m end
  local ok, f = pcall(CreateFrame, "Frame", nil, plate)
  if not ok or type(f) ~= "table" then return nil end
  f:SetSize(TodoMarks.ICON, TodoMarks.ICON)
  local t = f:CreateTexture(nil, "OVERLAY")
  t:SetAllPoints(f)
  pcall(t.SetTexture, t, iconFile())
  f.icon = t
  f:Hide()
  st.marks[plate] = f
  return f
end

TodoMarks.SIDES = { "left", "right", "top" }
TodoMarks.GAP = 2
TodoMarks.MAX_SHIFT = 96   -- beyond this many pixels outward we stop shifting and pick the shortest side
TodoMarks.FOREIGN_MAX = 80 -- foreign objects up to this size (px) count as icons; larger ones are containers (UnitFrame, auras)
TodoMarks.SCAN_MAX = 40
-- Names of known foreign icons count regardless of the size limits (Questie: "QuestieNameplate...")
TodoMarks.KNOWN = { "^Questie", "^Plater", "^Kui", "^TidyPlates" }
local FALLBACK = { left = { "left", "right", "top" }, right = { "right", "left", "top" }, top = { "top", "left", "right" } }

local function validSide(v)
  return v == "left" or v == "right" or v == "top"
end

local function charTable()
  local Store = ns.Store
  local char = Store and type(Store.char) == "function" and call(Store.char) or nil
  if type(char) ~= "table" or isSecret(char) then return nil end
  return char
end

function TodoMarks.side()
  local char = charTable()
  local v = char and char.todoMarkSide or st.side
  if type(v) == "string" and not isSecret(v) and validSide(v) then return v end
  return "left"
end

function TodoMarks.setSide(v)
  if type(v) ~= "string" or isSecret(v) or not validSide(v) then return false end
  local char = charTable()
  if char then char.todoMarkSide = v else st.side = v end
  TodoMarks.refreshPlates()
  return true
end

local function rectOf(o)
  if type(o) ~= "table" or isSecret(o) or type(o.GetLeft) ~= "function" then return nil end
  local ok, l, r, t, b = pcall(function() return o:GetLeft(), o:GetRight(), o:GetTop(), o:GetBottom() end)
  if not ok then return nil end
  l, r, t, b = num(l), num(r), num(t), num(b)
  if not (l and r and t and b) then return nil end
  local s = type(o.GetEffectiveScale) == "function" and num(call(o.GetEffectiveScale, o)) or 1
  if s <= 0 then s = 1 end
  return l * s, r * s, t * s, b * s
end

local function nameOf(o)
  if type(o.GetName) ~= "function" then return nil end
  return str(call(o.GetName, o))
end

local function objectType(o)
  if type(o.GetObjectType) ~= "function" then return nil end
  return str(call(o.GetObjectType, o))
end

local function isKnown(name)
  if not name then return false end
  for _, pat in ipairs(TodoMarks.KNOWN) do
    if match(name, pat) then return true end
  end
  return false
end

local function foreignRect(o, skip)
  if type(o) ~= "table" or isSecret(o) or skip[o] or forbidden(o) then return nil end
  local kind = objectType(o)
  if kind == "FontString" then return nil end
  local vis = type(o.IsVisible) == "function" and call(o.IsVisible, o) or nil
  if isSecret(vis) or vis ~= true then return nil end
  if type(o.GetAlpha) == "function" then
    local a = num(call(o.GetAlpha, o))
    if a and a <= 0.05 then return nil end
  end
  local l, r, t, b = rectOf(o)
  if not l then return nil end
  local name = nameOf(o)
  local w, h = r - l, t - b
  if w <= 0 or h <= 0 then return nil end
  if not isKnown(name) and (w < 4 or h < 4 or w > TodoMarks.FOREIGN_MAX or h > TodoMarks.FOREIGN_MAX) then return nil end
  return l, r, t, b, name or kind or "?"
end

local function kidsOf(parent, method, out)
  if type(parent) ~= "table" or isSecret(parent) or forbidden(parent) or type(parent[method]) ~= "function" then return end
  local ok, list = pcall(function() return { parent[method](parent) } end)
  if not ok or type(list) ~= "table" then return end
  for i = 1, math.min(#list, TodoMarks.SCAN_MAX) do out[#out + 1] = list[i] end
end

local function foreignList(plate, uf, skip)
  local objs = {}
  for _, parent in ipairs({ plate, uf }) do
    kidsOf(parent, "GetChildren", objs)
    kidsOf(parent, "GetRegions", objs)
  end
  local out, seen = {}, {}
  for _, o in ipairs(objs) do
    if not seen[o] then
      seen[o] = true
      local l, r, t, b, name = foreignRect(o, skip)
      if l then out[#out + 1] = { l = l, r = r, t = t, b = b, name = name } end
    end
  end
  return out
end

local function slotOf(side, g, o)
  local gap, sz = g.gap, g.size
  if side == "left" then
    local r = g.l - gap - o
    return r - sz, r, g.cy + sz / 2, g.cy - sz / 2
  elseif side == "right" then
    local l = g.r + gap + o
    return l, l + sz, g.cy + sz / 2, g.cy - sz / 2
  end
  local b = g.top + gap + o
  return g.cx - sz / 2, g.cx + sz / 2, b + sz, b
end

local function clearance(side, g, foreign)
  local o, who = 0, nil
  for _ = 1, 8 do
    local sl, sr, stp, sb = slotOf(side, g, o)
    local need, hit
    for _, f in ipairs(foreign) do
      if f.l < sr - 0.5 and f.r > sl + 0.5 and f.b < stp - 0.5 and f.t > sb + 0.5 then
        local n
        if side == "left" then n = g.l - f.l elseif side == "right" then n = f.r - g.r else n = f.t - g.top end
        if n <= o then n = o + 1 end
        if not need or n > need then need, hit = n, f.name end
      end
    end
    if not need then return o, who end
    o, who = need, hit
    if o > TodoMarks.MAX_SHIFT then return o, who end
  end
  return o, who
end

local function place(m, plate)
  local anchor, uf, key = anchorOf(plate)
  m:ClearAllPoints()
  local pref = TodoMarks.side()
  if not anchor then
    m:SetPoint("RIGHT", plate, "LEFT", -TodoMarks.GAP, 0) -- no UnitFrame yet: base frame, more precise one frame later
    return nil, "left", 0, nil
  end
  local side, shift, who = pref, 0, nil
  local l, r, t, b = rectOf(anchor)
  local topAnchor = anchor
  if l then
    local ms = type(m.GetEffectiveScale) == "function" and num(call(m.GetEffectiveScale, m)) or 1
    if ms <= 0 then ms = 1 end
    local g = { l = l, r = r, top = t, cx = (l + r) / 2, cy = (t + b) / 2, gap = TodoMarks.GAP * ms, size = TodoMarks.ICON * ms }
    local nameFs = uf.name
    if type(nameFs) == "table" and not isSecret(nameFs) and not forbidden(nameFs) then
      local nl, _, nt = rectOf(nameFs)
      if nl and nt > g.top then topAnchor, g.top = nameFs, nt end
    end
    local skip = { [m] = true, [anchor] = true, [uf] = true, [plate] = true, [topAnchor] = true }
    for _, other in pairs(st.marks) do skip[other] = true end
    local foreign = foreignList(plate, uf, skip)
    if #foreign > 0 then
      local prefO, prefWho = clearance(pref, g, foreign)
      if prefO <= TodoMarks.MAX_SHIFT then
        side, shift, who = pref, prefO, prefWho
      else
        local best, bestO, bestWho
        for _, sd in ipairs(FALLBACK[pref]) do
          local o, w = clearance(sd, g, foreign)
          if not best or o < bestO then best, bestO, bestWho = sd, o, w end
        end
        if bestO <= TodoMarks.MAX_SHIFT then side, shift, who = best, bestO, bestWho end
      end
      shift = shift / ms
    end
  end
  local off = TodoMarks.GAP + shift
  if side == "left" then
    m:SetPoint("RIGHT", anchor, "LEFT", -off, 0)
  elseif side == "right" then
    m:SetPoint("LEFT", anchor, "RIGHT", off, 0)
  else
    m:SetPoint("BOTTOM", topAnchor, "TOP", 0, off)
  end
  local lvl = type(uf.GetFrameLevel) == "function" and num(call(uf.GetFrameLevel, uf)) or nil
  if lvl and type(m.SetFrameLevel) == "function" then pcall(m.SetFrameLevel, m, floor(lvl) + 10) end
  return key, side, shift, who
end

local function hideMark(m)
  if not m then return end
  m:Hide()
  m:ClearAllPoints() -- release the old anchor (the UnitFrame goes back to the pool)
end

local function hideUnit(unit)
  local m = st.plates[unit]
  st.plates[unit] = nil
  hideMark(m)
end

function TodoMarks.updateUnit(unit)
  unit = str(unit)
  if not unit then return fail(R.badUnit) end
  local plate = plateOf(unit)
  if not plate then
    hideUnit(unit)
    return fail(R.noPlate, unit)
  end
  local plans, how, secret = {}, nil, false
  local reason
  if not TodoMarks.enabled() then
    reason = R.off
  elseif not index().any then
    reason = R.noTargets
  else
    plans, how, secret = TodoMarks.forUnit(unit)
    if #plans == 0 then reason = (how == nil and secret) and R.secret or R.noMatch end
  end
  if reason then
    hideMark(st.marks[plate])
    st.plates[unit] = nil
    return fail(reason, unit)
  end
  local m = markFor(plate)
  if not m then return fail(R.noAnchor, unit) end
  local key, side, shift, who = place(m, plate)
  if not m:IsShown() then D.marked = D.marked + 1 end
  m:Show()
  st.plates[unit] = m
  D.how, D.anchor = TodoMarks.HOW[how] or how, key
  D.side, D.shift, D.who = side, shift, who
  if not key then fail(R.noAnchor, unit) end
  return true
end

function TodoMarks.removeUnit(unit)
  unit = str(unit)
  if unit then hideUnit(unit) end
end

-- NAME_PLATE_UNIT_ADDED: now and one frame later (by then Blizzard's driver has created its UnitFrame)
function TodoMarks.onPlateAdded(unit)
  D.seen = D.seen + 1
  if not TodoMarks.enabled() then return false end
  local u = str(unit)
  local shown = TodoMarks.updateUnit(u)
  if u and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    pcall(C_Timer.After, 0, function()
      if TodoMarks.enabled() then pcall(TodoMarks.updateUnit, u) end
    end)
  end
  return shown
end

function TodoMarks.onForbiddenPlate(unit)
  D.forbidden = D.forbidden + 1
  fail(R.forbidden, unit)
end

function TodoMarks.refreshPlates()
  local units = {}
  for unit in pairs(st.plates) do units[unit] = true end
  local CN = C_NamePlate
  local list = type(CN) == "table" and call(CN.GetNamePlates) or nil
  if type(list) == "table" and not isSecret(list) then
    for _, plate in ipairs(list) do
      if type(plate) == "table" and not forbidden(plate) then
        local u = str(plate.namePlateUnitToken) or str(plate.unitToken)
        if u then units[u] = true end
      end
    end
  end
  for unit in pairs(units) do TodoMarks.updateUnit(unit) end
end

function TodoMarks.diagLine()
  local shown = 0
  for _ in pairs(st.plates) do shown = shown + 1 end
  local line = T("diagMain", TodoMarks.enabled() and T.stateOn or T.stateOff, D.seen, D.forbidden, shown, D.marked)
  if D.how then line = line .. T("diagHow", D.how, D.anchor or T.diagBase) end
  if D.side then
    line = line .. T("diagPlace", T["side_" .. D.side] or D.side)
    if (D.shift or 0) >= 1 then line = line .. T("diagShift", floor(D.shift + 0.5), D.who or "?") end
  end
  if D.reason then
    line = line .. T("diagFail", D.reason .. (D.reasonUnit and (" (" .. D.reasonUnit .. ")") or ""))
  end
  if D.seen == 0 then line = line .. T.diagNoEvent end
  local CS = C_Secrets
  if type(CS) == "table" and type(CS.ShouldUnitIdentityBeSecret) == "function" then
    local v = call(CS.ShouldUnitIdentityBeSecret, "target")
    if not isSecret(v) and type(v) == "boolean" then line = line .. T("diagSecret", v and T.yes or T.no) end
  end
  return line .. "."
end

function TodoMarks.setEnabled(on)
  local TT = Journal.TodoTracker
  if TT and TT.set then TT.set("marks", on and true or false) end
  TodoMarks.refreshPlates()
  return TodoMarks.enabled()
end

function TodoMarks.onPlansChanged()
  TodoMarks.invalidate()
  TodoMarks.refreshPlates()
end

local function attachPlans()
  local Plans = ns.Plans
  if st.attached or not (Plans and type(Plans.onChange) == "function") then return end
  st.attached = call(Plans.onChange, TodoMarks.onPlansChanged) and true or false
end

if ns.Core and ns.Core.on then
  ns.Core.on("PLAYER_ENTERING_WORLD", function()
    hookTooltip()
    attachPlans()
    TodoMarks.invalidate()
  end)
  ns.Core.on("NAME_PLATE_UNIT_ADDED", function(_, unit)
    attachPlans()
    TodoMarks.onPlateAdded(unit)
  end)
  ns.Core.on("FORBIDDEN_NAME_PLATE_UNIT_ADDED", function(_, unit) TodoMarks.onForbiddenPlate(unit) end)
  ns.Core.on("NAME_PLATE_UNIT_REMOVED", function(_, unit) TodoMarks.removeUnit(unit) end)
end
