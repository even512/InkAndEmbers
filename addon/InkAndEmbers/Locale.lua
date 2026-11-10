-- UI language. Loads first so modules can register texts; translation tables are in locales/enUS_*.lua and locales/ptBR_*.lua (docs/i18n.md).
-- EveNChronicleDB.locale = 'auto' | 'deDE' | 'enUS' | 'ptBR'; a change applies after /reload.
-- German is the source (Locale.ns); fallback: active language -> Locale.FALLBACK[active] -> German -> the key (noted in Locale.unknown).
-- Stored data is never translated.
local _, ns = ...

local Locale = {}
ns.Locale = Locale
ns.L = Locale

local format, type, pairs, pcall, tostring = string.format, type, pairs, pcall, tostring

Locale.DEFAULT = "deDE"
Locale.LANGS = { deDE = true, enUS = true, ptBR = true }
Locale.SETTINGS = { "auto", "deDE", "enUS", "ptBR" } -- menu order
-- languages between the active one and German: a missing Portuguese text shows in English, never in German
Locale.FALLBACK = { ptBR = { "enUS" } }

local tables = { deDE = {}, enUS = {}, ptBR = {} } -- tables[lang][area] = { key = text }
Locale.tables = tables
Locale.unknown = {} -- 'area.key' -> true (in neither the active language nor German)

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function validSetting(s)
  return s == "auto" or Locale.LANGS[s] == true
end

function Locale.clientLocale()
  if type(GetLocale) ~= "function" then return "enUS" end
  local ok, loc = pcall(GetLocale)
  if not ok or isSecret(loc) or type(loc) ~= "string" or loc == "" then return "enUS" end
  return loc
end

function Locale.resolve(setting, client)
  if Locale.LANGS[setting] then return setting end
  if client == "deDE" or client == "ptBR" then return client end
  return "enUS"
end

Locale.client = Locale.clientLocale()
Locale.setting = "auto"
Locale.active = Locale.resolve("auto", Locale.client)

function Locale.isEnglish() return Locale.active == "enUS" end

function Locale.matchesClient()
  return Locale.active == Locale.resolve("auto", Locale.client) and (Locale.active ~= "enUS" or Locale.client:sub(1, 2) == "en")
end

function Locale.apply(db)
  if db == nil then db = rawget(_G, "EveNChronicleDB") end
  local s = type(db) == "table" and db.locale or nil
  if isSecret(s) or not validSetting(s) then s = "auto" end
  Locale.client = Locale.clientLocale()
  Locale.setting = s
  Locale.active = Locale.resolve(s, Locale.client)
  return Locale.active
end

-- saves the setting; the active language stays until /reload (else the book would be half German, half English)
function Locale.set(setting)
  if not validSetting(setting) then return false, false end
  local db = rawget(_G, "EveNChronicleDB")
  if type(db) ~= "table" then return false, false end
  db.locale = setting
  Locale.setting = setting
  return true, Locale.resolve(setting, Locale.client) ~= Locale.active
end

-- Tables

local shape -- placeholder/form signature of a text (defined under Checks)
local fits = {} -- fits[lang][area][key] = true/false (table texts of fallback languages only; cleared on every merge)

local function merge(lang, area, texts)
  fits = {}
  local byLang = tables[lang]
  local t = byLang[area]
  if not t then
    t = {}
    byLang[area] = t
  end
  for k, v in pairs(texts) do t[k] = v end
  return t
end

function Locale.add(lang, area, texts)
  if not Locale.LANGS[lang] or type(area) ~= "string" or type(texts) ~= "table" then return false end
  merge(lang, area, texts)
  return true
end

-- search order for the active language: itself, its fallbacks, German (each once; cached per language)
local chains = {}
local function chain(lang)
  local cached = chains[lang]
  if cached then return cached end
  local list, seen = {}, {}
  local function push(l)
    if tables[l] and not seen[l] then
      seen[l] = true
      list[#list + 1] = l
    end
  end
  push(lang)
  local fb = Locale.FALLBACK[lang]
  if type(fb) == "table" then for _, l in ipairs(fb) do push(l) end end
  push(Locale.DEFAULT)
  if tables[lang] then chains[lang] = list end
  return list
end
Locale.chain = chain

-- in a language with a fallback chain (Locale.FALLBACK, e.g. ptBR) a table text (list/record) is only used when its
-- form matches the German one; otherwise single entries could be missing (e.g. a newer panel name) and the next
-- language in the chain is used. German and English tables are passed through unchecked.
local function lookup(lang, area, key)
  local a = tables[lang][area]
  local v = a and a[key]
  if type(v) ~= "table" or Locale.FALLBACK[lang] == nil then return v end
  local byLang = fits[lang]
  if not byLang then
    byLang = {}
    fits[lang] = byLang
  end
  local byArea = byLang[area]
  if not byArea then
    byArea = {}
    byLang[area] = byArea
  end
  local ok = byArea[key]
  if ok == nil then
    local d = tables[Locale.DEFAULT][area]
    d = d and d[key]
    ok = d == nil or shape(d) == shape(v)
    byArea[key] = ok
  end
  if ok then return v end
  return nil
end

function Locale.get(area, key)
  for _, lang in ipairs(chain(Locale.active)) do
    local v = lookup(lang, area, key)
    if v ~= nil then return v end
  end
  Locale.unknown[tostring(area) .. "." .. tostring(key)] = true
  return key
end

-- Formatting

local function named(s, args)
  return (s:gsub("{([%w_]+)}", function(k)
    local v = args[k]
    if v == nil then return "{" .. k .. "}" end
    return tostring(v)
  end))
end

function Locale.fmt(s, ...)
  if type(s) ~= "string" then return s end
  local n = select("#", ...)
  if n == 0 then return s end
  local first = ...
  if n == 1 and type(first) == "table" then return named(s, first) end
  local ok, res = pcall(format, s, ...)
  if ok then return res end
  return s
end

function Locale.plural(n, one, other)
  return tonumber(n) == 1 and one or other
end

-- formats a key: if a text fails (wrong placeholders), the next language in the chain is used (German last)
local function fmtKey(area, key, ...)
  local s = Locale.get(area, key)
  if type(s) ~= "string" then return s end
  if select("#", ...) == 0 then return s end
  local first = ...
  if select("#", ...) == 1 and type(first) == "table" then return named(s, first) end
  local ok, res = pcall(format, s, ...)
  if ok then return res end
  local after = false
  for _, lang in ipairs(chain(Locale.active)) do
    local a = tables[lang][area]
    local d = a and a[key]
    if after and type(d) == "string" then
      ok, res = pcall(format, d, ...)
      if ok then return res end
    end
    if d == s then after = true end
  end
  return s
end

function Locale.ns(area, deDE)
  if type(area) ~= "string" then error("Locale.ns: Bereich fehlt") end
  if type(deDE) == "table" then merge("deDE", area, deDE) end
  return setmetatable({}, {
    __index = function(_, key) return Locale.get(area, key) end,
    __call = function(_, key, ...) return fmtKey(area, key, ...) end,
    __newindex = function() error("Locale: Texte nur ueber Locale.ns/Locale.add setzen") end,
  })
end

-- Checks (tests, diagnostics)

-- placeholder sequence of a text: '%d %s {name}' -> 'd,s,{name}' (%% does not count)
local function specs(s)
  if type(s) ~= "string" then return type(s) end
  local list = {}
  for spec in s:gsub("%%%%", ""):gmatch("%%[-+ #0]*%d*%.?%d*([diouxXeEfgGqsc])") do list[#list + 1] = spec end
  local names = {}
  for k in s:gmatch("{([%w_]+)}") do names[#names + 1] = k end
  table.sort(names)
  for _, k in ipairs(names) do list[#list + 1] = "{" .. k .. "}" end
  return table.concat(list, ",")
end
Locale.specs = specs

function shape(v)
  if type(v) ~= "table" then return specs(v) end
  local parts = {}
  for i = 1, #v do parts[i] = shape(v[i]) end
  local keys = {}
  for k in pairs(v) do if type(k) ~= "number" then keys[#keys + 1] = tostring(k) end end
  table.sort(keys)
  for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. shape(v[k]) end
  return "{" .. #v .. ":" .. table.concat(parts, ";") .. "}"
end

function Locale.missing(lang, area)
  local de = tables.deDE[area] or {}
  local other = (tables[lang] or {})[area] or {}
  local report = { missing = {}, extra = {}, mismatch = {} }
  for k, v in pairs(de) do
    local o = other[k]
    if o == nil then
      report.missing[#report.missing + 1] = tostring(k)
    elseif shape(o) ~= shape(v) then
      report.mismatch[#report.mismatch + 1] = tostring(k)
    end
  end
  for k in pairs(other) do
    if de[k] == nil then report.extra[#report.extra + 1] = tostring(k) end
  end
  table.sort(report.missing)
  table.sort(report.extra)
  table.sort(report.mismatch)
  return report
end

function Locale.areas()
  local seen, list = {}, {}
  for _, byLang in pairs(tables) do
    for area in pairs(byLang) do
      if not seen[area] then
        seen[area] = true
        list[#list + 1] = area
      end
    end
  end
  table.sort(list)
  return list
end

local T = Locale.ns("Locale", {
  name = "Sprache",
  auto = "Automatisch (Spielsprache)",
  deDE = "Deutsch",
  enUS = "English",
  ptBR = "Português (Brasil)",
  tip = "Sprache des Reisejournals. Automatisch: Deutsch oder brasilianisches Portugiesisch entsprechend dem Client, sonst Englisch. Wirkt nach /reload.",
  reloadLabel = "Sprache übernehmen",
  reloadButton = "Sichern und neu laden",
  reloadTip = "Öffnet das Sichern-Fenster (wie /chronik sichern): Sichern lädt die Oberfläche neu, danach gilt die gewählte Sprache.",
  changed = "Sprache: %s. Wirkt nach /reload (oder /chronik sichern).",
  unchanged = "Sprache: %s.",
  usage = "Sprache: /chronik sprache auto | de | en | ptbr (jetzt: %s).",
})
Locale.T = T

function Locale.label(setting)
  if setting == "deDE" then return T.deDE end
  if setting == "enUS" then return T.enUS end
  if setting == "ptBR" then return T.ptBR end
  return T.auto
end

local ALIASES = {
  auto = "auto", automatisch = "auto", automatic = "auto",
  de = "deDE", dede = "deDE", deutsch = "deDE", german = "deDE",
  en = "enUS", enus = "enUS", englisch = "enUS", english = "enUS",
  pt = "ptBR", ptbr = "ptBR", portugues = "ptBR",
}

-- /chronik sprache <auto|de|en|ptbr>; returns the chat line (Core prints it)
function Locale.slash(rest)
  local key = type(rest) == "string" and ALIASES[string.lower(rest)] or nil
  if not key then return T("usage", Locale.label(Locale.setting)) end
  local ok, changed = Locale.set(key)
  if not ok then return T("usage", Locale.label(Locale.setting)) end
  return T(changed and "changed" or "unchanged", Locale.label(key))
end
