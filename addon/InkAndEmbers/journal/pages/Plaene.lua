-- Tab "Pläne" (I12, book reordered): a host for existing sub-views, nothing is drawn here itself.
--   To Do         (key "vorhaben", first and default) = journal/Vorhaben.lua (sheet over the whole double page, built by Frame),
--                                                       until I12 under Reise
--   Lehrplan      (key "lehrplan", WoW Forever only)   = pages/QuestsLehrplan.lua (Journal.LehrplanView), until I12 under Quests
--   Tierausbildung (key "tierausbildung", hunters only, or the development preview /chronik sim jaeger) = the same file in pet mode
--                 (Journal.TierView); tierView/tierOpen
-- (The open quests stay under the tab Quests, key "offen": pages/Quests.lua + pages/QuestsOffen.lua.)
-- The views get this page as their owner (View.new(page, left, right)): page.data = last Refresh data. Fields kept as before for
-- the slash commands and the diagnostics: trainView/trainOpen. Esc in "Lehrplan" leads to "To Do" (Pages.escape); on "To Do" Esc
-- closes the book.
-- Everything here belongs to the logged-in character: the guest book leaves out the whole tab (Pages.GUEST_HIDDEN).
-- Retail: only To Do (no Lehrplan), so no sub-bookmarks. No ticker, no OnUpdate.
local _, ns = ...

local Journal = ns.Journal
local W, Pages = Journal and Journal.Widgets, Journal and Journal.Pages
if not (W and Pages) then return end

-- no index needed: To Do reads its own source, so the tab never waits for "Tinte trocknet" (the player line of the Lehrplan takes
-- the logged-in character from the Store, see Refresh)
local Page = { needs = { index = false } }
Journal.PlaenePage = Page

-- locale scope "p.Plaene" (English in locales/enUS_pages.lua), read when drawing
local T = ns.Locale.ns("p.Plaene", {
  subTodo = "To Do",
  subTodoTip = "Eigene Reiseziele eintragen und abhaken",
  subTrain = "Lehrplan",
  subTrainTip = "Was Euch der Klassenlehrer ab welcher Stufe beibringt (nur WoW Forever)",
  subPets = "Tierausbildung",
  subPetsTip = "Was der Tierausbilder Eurem Tier ab welcher Stufe beibringt (nur Jäger)",
})
Page.TEXT = T

local function subTab(key, label, tip)
  return setmetatable({ key = key }, { __index = function(_, k)
    if k == "label" then return T[label] end
    if k == "tip" then return { T[label], T[tip] } end
  end })
end
Page.subs = {
  subTab("vorhaben", "subTodo", "subTodoTip"),
  subTab("lehrplan", "subTrain", "subTrainTip"),
  subTab("tierausbildung", "subPets", "subPetsTip"),
}
Page.FIRST = "vorhaben"

-- the To Do sheet itself is built by journal/Frame.lua with the window (Vorhaben.build on the left page holder, over the whole
-- double page); here it is only opened and closed
function Page.Build(self, left, right)
  self.holderL, self.holderR = left, right
end

function Page:GetSub()
  if self.trainOpen then return "lehrplan" end
  if self.tierOpen then return "tierausbildung" end
  return "vorhaben"
end

local function todoOpen()
  local V = Journal.Vorhaben
  return V ~= nil and type(V.isOpen) == "function" and V.isOpen() == true
end

function Page:ShowSub(key)
  local V = Journal.Vorhaben
  if key ~= "vorhaben" and todoOpen() then
    if V.cancelPick then V.cancelPick() end
    V.close()
  end
  if key ~= "lehrplan" and self.trainView and self.trainOpen then self.trainView:Close() end
  if key ~= "lehrplan" then self.trainOpen = false end
  if key ~= "tierausbildung" and self.tierView and self.tierOpen then self.tierView:Close() end
  if key ~= "tierausbildung" then self.tierOpen = false end
  if key == "tierausbildung" then
    local TV = Journal.TierView
    if not (TV and self.holderL) then return end
    if not self.tierView then self.tierView = TV.new(self, self.holderL, self.holderR) end
    if not self.tierOpen then
      self.tierOpen = true
      self.tierView:Open()
    end
  elseif key == "lehrplan" then
    local LV = Journal.LehrplanView
    if not (LV and self.holderL) then return end
    if not self.trainView then self.trainView = LV.new(self, self.holderL, self.holderR) end
    if not self.trainOpen then
      self.trainOpen = true
      self.trainView:Open()
    end
  elseif V and not todoOpen() then
    V.open()
  end
end

function Page:Refresh(data)
  if data.char == nil and ns.Store and type(ns.Store.char) == "function" then data.char = ns.Store.char() end
  self.data = data
  -- Pages.sub falls back to the first visible bookmark; without bookmarks (Retail: only To Do) it stays "To Do"
  local key = Pages.sub(self.id or "plaene") or Page.FIRST
  if key ~= self:GetSub() or (key == "vorhaben" and not todoOpen()) then
    self:ShowSub(key)
  elseif key == "lehrplan" then
    self.trainView:Refresh()
  elseif key == "tierausbildung" and self.tierView then
    self.tierView:Refresh()
  end
end

-- on leaving: the To Do sheet closes (with the place picker), tooltips off, pins back; the sub-bookmark stays for the next show
function Page:OnHide()
  local V = Journal.Vorhaben
  if V then
    if V.cancelPick then pcall(V.cancelPick, true) end
    if todoOpen() then pcall(V.close) end
  end
  for _, view in ipairs({ self.trainView or false, self.tierView or false }) do
    if view then
      for _, r in ipairs(view.ui.rowsList.rows) do W.hideTip(r) end
    end
  end
end

Pages.register("plaene", Page)

-- To Do needs journal/Vorhaben.lua (it bails out without the widgets)
Pages.hideSub("plaene", "vorhaben", function() return Journal.Vorhaben == nil end)

-- Retail: the trainer plan (Lehrplan) exists only in WoW Forever, so its bookmark stays out (then only To Do is left: no bookmarks)
Pages.hideSub("plaene", "lehrplan", function()
  local L = Journal.Lehrplan
  return L ~= nil and type(L.active) == "function" and L.active() == false
end)

-- Tierausbildung: hunters only (class of the logged-in character), or the development preview; never in Retail (like the Lehrplan)
Pages.hideSub("plaene", "tierausbildung", function()
  local L = Journal.Lehrplan
  return not (L ~= nil and type(L.petTabVisible) == "function" and L.petTabVisible() == true)
end)
