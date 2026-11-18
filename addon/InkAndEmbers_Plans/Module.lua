-- Module InkAndEmbers_Plans of Ink & Embers (1.1.0): first file of the add-on. Hangs the own `...` table onto the namespace of
-- the core (global InkAndEmbers, Core.lua) so the module code below reads and writes the shared namespace unchanged, then
-- registers the module (diagnostics, module overview). Without the core (not loaded, too old) the module stays silent.
local addonName, ns = ...
local api = rawget(_G, "InkAndEmbers")
if type(api) ~= "table" or type(api.ns) ~= "table" or type(api.registerModule) ~= "function" then return end
-- test VM: one namespace for core and modules (no metatable on itself)
if api.ns ~= ns then setmetatable(ns, { __index = api.ns, __newindex = api.ns }) end
api.registerModule("plans", { addon = addonName, apiVersion = 1 })
