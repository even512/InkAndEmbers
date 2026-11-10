-- Tab "Dungeons" (I12, book reordered): a host for two existing sub-views, nothing is drawn here itself.
--   Durchläufe     (key "laeufe", first and default) = pages/ChronikDungeons.lua (Journal.DungeonsView), until I12 under Chronik
--   Dungeon-Quests (key "quests", WoW Forever only)  = pages/QuestsDungeons.lua (Journal.DungeonQuestsView), until I12 under Quests
-- The views get this page as their owner (View.new(page, left, right)): page.data (last Refresh data), page.book (the quest book
-- for "Questtext lesen", built here only while the dungeon quests are shown), page:OpenFromDungeons(id) (jump to the tab Quests,
-- "Zurück" there leads back here: Frame.jump / Frame.jumpBack). Esc in "Dungeon-Quests" leads to "Durchläufe" (Pages.escape).
-- Guest book: only the runs. Retail: only the runs (Pages.subs then has no bookmarks). No ticker, no OnUpdate.
local _, ns = ...

local Journal = ns.Journal
local Pages = Journal and Journal.Pages
if not Pages then return end

local Page = { needs = { index = true } }
Journal.DungeonsPage = Page

-- locale scope "p.Dungeons" (English in locales/enUS_pages.lua), read when drawing
local T = ns.Locale.ns("p.Dungeons", {
  subRuns = "Durchläufe",
  subRunsTip = "Jeder Durchlauf: wann, wie lange, mit wem, Bosse, Tode und Beute",
  subQuests = "Dungeon-Quests",
  subQuestsTip = "Alle Dungeon-Quests und ihre Questketten (Daten: QuestieDB, nur WoW Forever)",
})
Page.TEXT = T

local function subTab(key, label, tip)
  return setmetatable({ key = key }, { __index = function(_, k)
    if k == "label" then return T[label] end
    if k == "tip" then return { T[label], T[tip] } end
  end })
end
Page.subs = {
  subTab("laeufe", "subRuns", "subRunsTip"),
  subTab("quests", "subQuests", "subQuestsTip"),
}
Page.FIRST = "laeufe"

function Page.Build(self, left, right)
  self.holderL, self.holderR = left, right
  self.cur = Page.FIRST
end

function Page:GetSub()
  return self.cur or Page.FIRST
end

-- quest book of the shown character (Quests:Select's condition "in the book"), rebuilt only when the index changed
local function ensureBook(self)
  local Book, data = Journal.QuestBook, self.data
  if not (Book and data and data.index) then return end
  if self.bookIndex ~= data.index or not self.book then
    self.book = Book.build(data.index)
    self.bookIndex = data.index
  end
end

local function openRuns(self)
  local V = Journal.DungeonsView
  if not (V and self.holderL and self.data) then return false end
  if not self.runsView then self.runsView = V.new(self, self.holderL, self.holderR) end
  self.runsView:Open(self.data.index, self.data.now)
  return true
end

function Page:ShowSub(key)
  if key == "quests" then
    local V = Journal.DungeonQuestsView
    if not (V and self.holderL) then return end
    if self.runsView and self.runsView:IsOpen() then self.runsView:Close() end
    if not self.questsView then self.questsView = V.new(self, self.holderL, self.holderR) end
    ensureBook(self)
    self.cur = "quests"
    if not self.questsView:IsOpen() then self.questsView:Open() end
    return
  end
  if self.questsView and self.questsView:IsOpen() then self.questsView:Close() end
  self.cur = Page.FIRST
  if not (self.runsView and self.runsView:IsOpen()) then openRuns(self) end
end

function Page:Refresh(data)
  self.data = data
  -- the shown sub-bookmark may have been hidden meanwhile (guest book, Retail): Pages.sub falls back to the first visible one
  local key = Pages.sub(self.id or "dungeons") or Page.FIRST
  if key ~= self:GetSub() then
    self:ShowSub(key)
  elseif key == "quests" then
    ensureBook(self)
    if self.questsView and self.questsView:IsOpen() then self.questsView:Refresh() else self:ShowSub("quests") end
  elseif self.runsView and self.runsView:IsOpen() then
    self.runsView:Refresh(data.index, data.now)
  else
    openRuns(self)
  end
end

-- "Questtext lesen" of the dungeon quests: tab Quests, history, the quest text; "Zurück" there leads back here once
function Page:OpenFromDungeons(id)
  local F, Q = Journal.Frame, Journal.QuestsPage
  if not (F and Q and type(F.jump) == "function") then return false end
  if not F.jump("quests", "historie") then return false end
  if Q:OpenFromDungeons(id) == true then return true end
  -- the quest is not in the history after all: back to the dungeon page instead of leaving the player on the quest table
  if type(F.jumpBack) == "function" then F.jumpBack("quests") end
  return false
end

-- on leaving: tooltips off (the runs view opens afresh on the next show, the dungeon quests keep their state)
function Page:OnHide()
  if self.runsView and self.runsView:IsOpen() then self.runsView:Close() end
  if self.questsView then self.questsView:OnPageHide() end
end

Pages.register("dungeons", Page)

-- Another character's book: the dungeon quests belong to the logged-in character (Pages.GUEST_HIDDEN_SUBS); an open view makes
-- way before the redraw, the runs open with the guest's data in Refresh.
if Pages.onGuestChange then
  Pages.onGuestChange(function(guid)
    if guid ~= nil and Page.cur == "quests" then
      if Page.questsView and Page.questsView:IsOpen() then Page.questsView:Close() end
      Page.cur = Page.FIRST
    end
  end)
end

-- Retail: the dungeon quests exist only in WoW Forever (no bookmark, nothing is loaded); the test mode keeps them like the model
Pages.hideSub("dungeons", "quests", function()
  local OQ = Journal.OpenQuests
  if not (OQ and OQ.retailClient()) then return false end
  return not (OQ.test() ~= nil or OQ.ALLOW_RETAIL)
end)
