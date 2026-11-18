-- English strings of the module InkAndEmbers_Crafting (moved from the core locales in 1.1.0 by scripts/split-locales.mjs).
-- One L.add block per area, same keys as L.ns in the module's code (deDE is the source in the code).
local _, ns = ...
local L = ns.Locale

-- journal/model/Rezepte.lua
L.add("enUS", "m.Rezepte", {
  spellFallback = "Recipe %s",
  profFallback = "Profession %s",
  rankJ = "Journeyman", rankE = "Expert", rankA = "Artisan",
  srcT = "Trainer", srcV = "Vendor", srcQ = "Quest", srcD = "Drop", srcC = "Crafted", srcO = "Found",
  favor = "%s Merchant's Favor",
  repText = "Reputation: %s",
  repFallback = "Reputation with a faction",
  NO_RECIPES = "Recipe list missing in the data add-on (reinstall it)",
  NO_API = "Professions cannot be read right now",
})

L.add("enUS", "m.Rezeptbuch", {
  profFallback = "Profession %s",
  recipeFallback = "Recipe %s",
  diff_orange = "optimal", diff_yellow = "medium", diff_green = "easy", diff_grey = "no gain",
})

L.add("enUS", "m.Handwerk", {
  rank_75 = "Apprentice", rank_150 = "Journeyman", rank_225 = "Expert", rank_300 = "Artisan",
})

-- journal/pages/PlaeneHandwerk.lua
L.add("enUS", "p.PlaeneHandwerk", {
  brand = "INK & EMBERS", page = "CRAFTING",
  fTrainer = "Trainer", fNow = "Now", fSoon = "Soon",
  fTrainerTip = { "Trainer", "What a profession trainer teaches you right now" },
  fNowTip = { "Now", "Everything you can learn at your skill, including vendors, quests and drops" },
  fSoonTip = { "Soon", "What the next 25 skill points add" },
  info = "Professions: %s · %s now · %s soon",
  skillWord = "Skill %s",
  free = "free",
  sNow = "now", sSoon = "in %s points", sLevel = "from level %s", sLater = "from skill %s", sLearned = "learned",
  learnable = "learnable at the trainer",
  costLine = "Training fees %s · in your bag %s",
  costNone = "The profession trainer has nothing new for you right now.",
  short = "You are still short %s.", enough = "Your bag covers everything.",
  profHead = "Your professions",
  profLine = "%s %s/%s · %s now · %s soon",
  profLineNoMax = "%s %s · %s now · %s soon",
  todoOn = "The to-do \"To the profession trainer\" is on your list.",
  todoOff = "As soon as a trainer has something new for you, Ink adds \"To the profession trainer\" to your to-do list.",
  retailHead = "WoW Forever only",
  retailBody = "The recipe data is for WoW Forever. This sheet stays empty on Retail.",
  noDataHead = "No recipe data",
  noProfHead = "No profession yet",
  noProfBody = "Learn a profession. This sheet then shows which recipes come next.",
  noProfDataHead = "No recipes for your professions",
  noProfDataBody = "There is no recipe data for your professions.",
  noApiBody = "Your professions cannot be read right now. Try again in a moment.",
  emptyTrainer = "The profession trainer has nothing new right now. More skill brings new recipes.",
  emptyNow = "Nothing is learnable right now.",
  emptySoon = "Nothing new in the next 25 points.",
  prevPage = "Previous page", nextPage = "Next page",
  tipSource = "Source: %s", tipCost = "Price: %s", tipLevel = "Level %s required", tipRank = "Profession rank: %s",
  tipFavor = "Merchant's Favor: %s", tipNeed = "%s more skill points",
})

-- journal/pages/Handwerk.lua (change "datenbuecher", P5)
L.add("enUS", "p.Handwerk", {
  brand = "INK & EMBERS", book = "PROFESSIONS", page = "CRAFTING", title = "Crafting",
  prof_one = "%s profession", prof_other = "%s professions", rec_one = "%s recipe", rec_other = "%s recipes",
  listHead = "PROFESSIONS",
  listEmpty = "No profession learned yet. As soon as you learn one, its curve writes itself here.",
  primary = "Primary profession", secondary = "Secondary profession",
  skillOf = "%s / %s",
  skillNow = "Skill %s of %s", skillRank = "%s · %s",
  subBerufe = "Professions", subBerufeTip = "Skill curve, milestones and tally of your professions",
  subRezept = "Recipe book", subRezeptTip = "Every recipe of your professions, learned and still open, with materials (WoW Forever only)",
  balance = "TALLY",
  mined = "mined", picked = "picked", skinned = "skinned", fished = "fished", crafted = "crafted",
  minedTip = "Ore and stone from resource nodes", pickedTip = "Herbs and flowers from plants",
  skinnedTip = "Leather and hides from enemies (estimated from the finds)", fishedTip = "Everything that hung on the hook",
  craftedTip = "Items you made yourself, including those below Uncommon quality",
  balanceEmpty = "Nothing gathered or crafted yet.",
  firstCraft = "First craft", firstCraftTip = "The first item you made yourself, from Uncommon quality",
  level = "Level %s",
  curveHead = "SKILL OVER PLAY TIME", recipesHead = "Learned recipes",
  hours = "%s hr", minutes = "%s min",
  open = "not yet", milestoneTip = "Skill %s reached",
  tipSkill = "Skill %s of %s", tipLearned = "Learned at level %s", tipLast = "Last rise: %s",
  tipWhen = "%s · Level %s", tipPlay = "After %s of play time",
  noRecipes = "No recipe learned yet.",
  recipesUnsure = "The recipes of this profession cannot be assigned with certainty. You will find all of them in the recipe book.",
  emptyTitle = "The crafting book is still empty",
  emptyBody = "Learn a profession, and every skill point, every recipe and every milestone writes itself down here.",
  date = "{m}/{d}/{y}",
})

-- journal/pages/HandwerkRezeptbuch.lua (change "runde3", package R)
L.add("enUS", "p.HandwerkRezeptbuch", {
  brand = "INK & EMBERS", book = "RECIPE BOOK", page = "CRAFTING",
  title = "Recipe book", sub = "Every recipe of your professions, learned and still open",
  listHead = "PROFESSIONS", recipesHead = "RECIPES",
  fAll = "All", fLearned = "Learned", fOpen = "Open",
  fAllTip = { "All", "Learned and not yet learned recipes" },
  fLearnedTip = { "Learned", "Only the recipes you already know" },
  fOpenTip = { "Open", "Only the recipes you are still missing" },
  profSub = "Skill %s of %s", profSubNoMax = "Skill %s",
  profCount = "%s of %s", profNoCount = "–",
  countLine = "%s learned · %s open",
  hintNoCache = "Open your profession window once so the book knows every detail.",
  hintCache = "As of the last time you opened the profession window. Newly learned recipes appear when you open it again.",
  legend = "Colour:",
  learned = "learned", open = "open", fromSkill = "from %s",
  skillWord = "Skill %s",
  tipSource = "Source: %s", tipDifficulty = "Difficulty: %s", tipUps = "Skill points per craft: up to %s",
  tipCost = "Price: %s", tipStock = "In bags: %s · Bank: %s",
  tipNeeds = "Needs: %s", tipMore = "Click: details below",
  needs = "NEEDS", output = "Makes: %s", outputQty = "Makes: %s× %s",
  noMats = "This recipe needs no materials.",
  detailNoCache = "The book only knows the result and the materials once you have opened your profession window.",
  moreMats = "… and %s more",
  itemNo = "Item #%s",
  pick = "Choose a recipe.",
  emptyList = "There are no recipes for this profession yet.",
  emptyFilterLearned = "No recipe learned yet.", emptyFilterOpen = "Every recipe of this profession is learned.",
  noProfTitle = "No profession with recipes yet",
  noProfBody = "Learn a profession. This sheet then shows all its recipes, learned and open.",
  prevPage = "Previous page", nextPage = "Next page",
})

-- journal/WerkBarKit.lua (Werkauftrag, 1.1.0)
L.add("enUS", "WerkBarKit", {
  stepPlan = "Plan",
  stepBuy = "Buy",
  stepMake = "Craft",
  afterCombat = "After combat",
  goldShort = "You are short %s",
  busy = "One moment …",
})
