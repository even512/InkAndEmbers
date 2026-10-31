-- Notes store: chars[guid].notes (own SV table, not part of the log or index). Note = { id, title, body (markup),
-- created, updated, mapID, x, y (map fraction 0..1), zone, level, pinned, onMap, updZone, updLevel }.
-- Title and body always pass NoteMarkup.cleanTitle/cleanBody before saving; display only via NoteMarkup.render or
-- Sanitize.display.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Notes = {}
Journal.Notes = Notes

local floor = math.floor
Notes.MAX = 500
Notes.ZONE_MAX = 60 -- bytes of the zone name

local listeners = {}

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function M() return Journal.NoteMarkup end

local function now()
  local t = type(time) == "function" and time() or 0
  return num(t) or 0
end

-- once per session: clean titles/bodies again (the SV may be hand-edited or from an older version), cap the list at
-- Notes.MAX (oldest kept)
local checked = setmetatable({}, { __mode = "k" })

local function revalidate(n)
  local mk = M()
  if not mk or checked[n] then return end
  local list, out = n.list, {}
  for _, e in ipairs(list) do
    if #out >= Notes.MAX then break end
    if type(e) == "table" and num(e.id) then
      e.title = (not isSecret(e.title) and mk.cleanTitle(e.title)) or ""
      e.body = mk.cleanBody(e.body)
      out[#out + 1] = e
    end
  end
  n.list = out
  checked[n] = true
end

local function store(create)
  local Store = ns.Store
  local char = Store and Store.char and Store.char()
  if type(char) ~= "table" then return nil end
  local n = char.notes
  if type(n) ~= "table" then
    if not create then return nil end
    n = { nextId = 1, list = {} }
    char.notes = n
  end
  if type(n.list) ~= "table" then n.list = {} end
  if not num(n.nextId) then n.nextId = 1 end
  revalidate(n)
  return n
end

function Notes.ready()
  local Store = ns.Store
  return Store ~= nil and Store.char ~= nil and type(Store.char()) == "table"
end

local function valid(n)
  return type(n) == "table" and num(n.id) ~= nil
end

local function find(id)
  local s = store(false)
  id = num(id)
  if not s or not id then return nil end
  for i, n in ipairs(s.list) do
    if valid(n) and n.id == id then return n, i end
  end
  return nil
end

local function copy(n)
  local out = {}
  for k, v in pairs(n) do
    if type(v) ~= "table" and not isSecret(v) then out[k] = v end
  end
  out.title = type(n.title) == "string" and n.title or ""
  out.body = type(n.body) == "string" and n.body or ""
  out.pinned = n.pinned == true
  out.onMap = n.onMap == true
  return out
end

local function changed(id)
  for _, fn in ipairs(listeners) do pcall(fn, id) end
end

function Notes.onChange(fn)
  if type(fn) ~= "function" then return false end
  for _, f in ipairs(listeners) do
    if f == fn then return true end
  end
  listeners[#listeners + 1] = fn
  return true
end

function Notes.count()
  local s = store(false)
  if not s then return 0 end
  local c = 0
  for _, n in ipairs(s.list) do
    if valid(n) then c = c + 1 end
  end
  return c
end

function Notes.get(id)
  local n = find(id)
  return n and copy(n) or nil
end

local function zoneName(mapID)
  local Zone = ns.Zone
  if not (Zone and Zone.info) then return nil end
  local id = mapID
  if Zone.ancestor and Zone.TYPE_ZONE then
    local ok, z = pcall(Zone.ancestor, mapID, Zone.TYPE_ZONE)
    if ok and num(z) then id = z end
  end
  local ok, info = pcall(Zone.info, id)
  local name = ok and type(info) == "table" and info.name or nil
  if isSecret(name) or type(name) ~= "string" then return nil end
  name = ns.Sanitize.field(name)
  if name == "" then return nil end
  return ns.Sanitize.cut(name, Notes.ZONE_MAX)
end

function Notes.here()
  local out = {}
  local Zone = ns.Zone
  if Zone and Zone.raw then
    local ok, mapID, x, y = pcall(Zone.raw)
    if ok and num(mapID) and mapID > 0 then
      out.mapID = floor(mapID)
      if num(x) and num(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        out.x, out.y = floor(x * 10000 + 0.5) / 10000, floor(y * 10000 + 0.5) / 10000
      end
      out.zone = zoneName(out.mapID)
    end
  end
  if type(UnitLevel) == "function" then
    local ok, lv = pcall(UnitLevel, "player")
    lv = ok and num(lv) or nil
    if lv and lv > 0 then out.level = floor(lv) end
  end
  return out
end

function Notes.create(fields)
  local s = store(true)
  if not s then return nil, "nicht-bereit" end
  if Notes.count() >= Notes.MAX then return nil, "voll" end
  fields = type(fields) == "table" and fields or {}
  local mk = M()
  local t = now()
  local here = Notes.here()
  local id = floor(s.nextId)
  s.nextId = id + 1
  local body = mk and mk.cleanBody(fields.body) or ""
  local n = {
    id = id, title = (mk and mk.cleanTitle(fields.title)) or "", body = body, created = t, updated = t,
    mapID = here.mapID, x = here.x, y = here.y, zone = here.zone, level = here.level, pinned = false, onMap = false,
  }
  s.list[#s.list + 1] = n
  changed(id)
  return id
end

function Notes.update(id, fields)
  local n = find(id)
  if not n then return false, "unbekannt" end
  fields = type(fields) == "table" and fields or {}
  local mk = M()
  local dirty = false
  if fields.title ~= nil then
    local title = (mk and mk.cleanTitle(fields.title)) or ""
    if title ~= n.title then n.title, dirty = title, true end
  end
  if fields.body ~= nil then
    local body = mk and mk.cleanBody(fields.body) or ""
    if body ~= n.body then n.body, dirty = body, true end
  end
  if dirty then
    n.updated = now()
    local here = Notes.here()
    n.updZone, n.updLevel = here.zone, here.level
    changed(n.id)
  end
  return true
end

function Notes.remove(id)
  local n, i = find(id)
  if not n then return false end
  table.remove(store(false).list, i)
  changed(nil)
  return true
end

function Notes.setPinned(id, on)
  local n = find(id)
  if not n then return false end
  n.pinned = on == true
  changed(n.id)
  return true
end

function Notes.setOnMap(id, on)
  local n = find(id)
  if not n then return false, "unbekannt" end
  if on and not (num(n.mapID) and num(n.x) and num(n.y)) then return false, "kein-ort" end
  n.onMap = on == true
  changed(n.id)
  return true
end

function Notes.toggleCheck(id, line)
  local n = find(id)
  local mk = M()
  if not n or not mk then return false end
  local body = mk.toggleLine(n.body, num(line) and floor(line) or -1)
  if not body then return false end
  n.body = mk.cleanBody(body)
  n.updated = now()
  changed(n.id)
  return true
end

local function sortKey(n, sort)
  if sort == "title" then
    local mk = M()
    local t = n.title ~= "" and n.title or (mk and mk.firstLine(n.body)) or ""
    return mk and mk.lower(t) or t
  end
  return nil
end

function Notes.list(opts)
  opts = type(opts) == "table" and opts or {}
  local s = store(false)
  local out = {}
  if not s then return out end
  local mk = M()
  local q = type(opts.query) == "string" and not isSecret(opts.query) and opts.query or ""
  q = string.gsub(string.gsub(q, "^ +", ""), " +$", "")
  if mk then q = mk.lower(q) end
  for _, n in ipairs(s.list) do
    if valid(n) then
      local keep = true
      if q ~= "" and mk then
        local hay = mk.lower(type(n.title) == "string" and n.title or "") .. "\n" .. mk.plain(n.body)
        keep = string.find(hay, q, 1, true) ~= nil
      end
      if keep then out[#out + 1] = copy(n) end
    end
  end
  local sort = opts.sort == "old" and "old" or (opts.sort == "title" and "title" or "new")
  local keys = {}
  if sort == "title" then
    for _, n in ipairs(out) do keys[n.id] = sortKey(n, "title") end
  end
  table.sort(out, function(a, b)
    if a.pinned ~= b.pinned then return a.pinned end
    if sort == "title" then
      local ka, kb = keys[a.id], keys[b.id]
      if ka ~= kb then return ka < kb end
    elseif sort == "old" then
      if (a.created or 0) ~= (b.created or 0) then return (a.created or 0) < (b.created or 0) end
    else
      if (a.updated or 0) ~= (b.updated or 0) then return (a.updated or 0) > (b.updated or 0) end
    end
    return a.id > b.id
  end)
  return out
end

function Notes.between(t0, t1)
  t0, t1 = num(t0), num(t1)
  local s = store(false)
  local out = {}
  if not (s and t0 and t1) then return out end
  local mk = M()
  for _, n in ipairs(s.list) do
    local c = valid(n) and num(n.created)
    if c and c >= t0 and c < t1 then
      local title = (type(n.title) == "string" and n.title ~= "" and n.title) or (mk and mk.firstLine(n.body)) or nil
      if title then out[#out + 1] = { id = n.id, title = title, created = c } end
    end
  end
  table.sort(out, function(a, b) if a.created ~= b.created then return a.created < b.created end return a.id < b.id end)
  return out
end

function Notes.onMap()
  local s = store(false)
  local out = {}
  if not s then return out end
  local mk = M()
  for _, n in ipairs(s.list) do
    if valid(n) and n.onMap == true and num(n.mapID) and num(n.x) and num(n.y) then
      local title = (type(n.title) == "string" and n.title ~= "" and n.title) or (mk and mk.firstLine(n.body)) or ""
      out[#out + 1] = { id = n.id, title = title, mapID = n.mapID, x = n.x, y = n.y }
    end
  end
  return out
end
