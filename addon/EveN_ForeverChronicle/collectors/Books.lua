-- Collector 'Books': books, letters and signs with full text.
-- Each page read is stored once in chars[guid].books[key] (fields p1, p2, ...), plus a BK log line.
-- Never turns pages itself (no ItemTextNextPage/PrevPage); only what the player opens is read.
local _, ns = ...
local Core, Store, Sanitize = ns.Core, ns.Store, ns.Sanitize

local floor, byte, sub = math.floor, string.byte, string.sub

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

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a = pcall(fn, ...)
  if not ok then return nil end
  return a
end

local HASH_BYTES = 2000 -- only the start of the first page goes into the key

local HEX = "0123456789abcdef"

-- 32-bit number (Lua number < 2^32) -> 8 hex digits, without bit operators or %x (Lua 5.1, 32-bit long)
local function hex8(n)
  local out = {}
  for i = 8, 1, -1 do
    local d = n % 16
    out[i] = sub(HEX, d + 1, d + 1)
    n = (n - d) / 16
  end
  return table.concat(out)
end

-- Key limits: it is based on the FIRST NON-EMPTY page of this reading session (an empty page 1 is skipped). Starting mid-book
-- (ItemTextGetPage > 1) or text changes (e.g. an inserted player name) give a different key. Intended: better a book twice than merged wrongly.
-- Stable key: two simple polynomial hashes (Lua 5.1, numbers stay below 2^53) over title, material and the start of the first page.
-- Same text -> same key, across reloads and machines.
local function bookKey(title, material, firstPage)
  local s = (title or "") .. "\1" .. (material or "") .. "\1" .. sub(firstPage or "", 1, HASH_BYTES)
  local h1, h2 = 5381, 52711
  for i = 1, #s do
    local b = byte(s, i)
    h1 = (h1 * 33 + b) % 4294967291
    h2 = (h2 * 131 + b) % 4294967279
  end
  return hex8(h1) .. hex8(h2)
end

local function playerLevel()
  return num(call(UnitLevel, "player"))
end

local Books = {
  requires = { "ItemTextGetText" },
  events = { "ITEM_TEXT_BEGIN", "ITEM_TEXT_READY", "ITEM_TEXT_CLOSED" },
}
local handlers = {}

function Books:init()
  self.session = nil
  self.repeats = {} -- '<key>:<page>' -> true: BK with new=0 only once per book and page per login
end

handlers.ITEM_TEXT_BEGIN = function(self)
  self.session = { seen = {} }
end

handlers.ITEM_TEXT_READY = function(self)
  local sess = self.session
  if not sess then
    sess = { seen = {} }
    self.session = sess
  end
  local text = Sanitize.bookText(call(ItemTextGetText))
  if not text then return end -- empty or unreadable (empty pages set neither key nor seen)
  local page = num(call(ItemTextGetPage))
  page = (page and page >= 1) and floor(page) or 1
  if sess.seen[page] then return end
  sess.seen[page] = true

  local title = Sanitize.field(call(ItemTextGetItem))
  if title == "" then title = nil end
  local material = str(call(ItemTextGetMaterial))
  if not sess.key then
    sess.title = title
    sess.key = bookKey(title, material, text)
  end
  local key = sess.key

  local char = Store.char()
  local book = char and char.books and char.books[key]
  local existed = type(book) == "table" and book["p" .. page] ~= nil

  local mapID = ns.Zone and ns.Zone.here() or nil
  local fields = { title = sess.title or title, material = material, mapID = mapID }
  fields["p" .. page] = text
  if call(ItemTextHasNextPage) == false then fields.pages = page end -- last page known (query only, no paging)
  local added = Store.putText("books", key, fields)
  book = char and char.books and char.books[key]
  -- new = 1 only if this page was actually stored (LIMITS.books can prevent it)
  local stored = not existed and added > 0 and type(book) == "table" and book["p" .. page] ~= nil
  if not stored then
    local tag = key .. ":" .. page
    if self.repeats[tag] then return end
    self.repeats[tag] = true
  end
  Store.append("BK", key, page, playerLevel(), mapID, stored and 1 or 0)
end

handlers.ITEM_TEXT_CLOSED = function(self)
  self.session = nil
end

function Books:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("Books", Books)
