-- Russian strings of the module InkAndEmbers_Crafting (moved from the core locales in 1.1.0 by scripts/split-locales.mjs).
-- One L.add block per area, same keys as L.ns in the module's code (deDE is the source in the code).
local _, ns = ...
local L = ns.Locale

-- journal/model/Rezepte.lua and Handwerk.lua (1.0.12 data books)
L.add("ruRU", "m.Rezepte", {
  spellFallback = "Рецепт %s",
  profFallback = "Профессия %s",
  rankJ = "Подмастерье", rankE = "Эксперт", rankA = "Мастер",
  srcT = "Учитель", srcV = "Торговец", srcQ = "Задание", srcD = "Добыча", srcC = "Создание", srcO = "Находка",
  favor = "Благосклонность торговца: %s",
  repText = "Репутация: %s",
  repFallback = "Репутация у фракции",
  NO_RECIPES = "В дополнении с данными нет списка рецептов (переустановите его)",
  NO_API = "Профессии сейчас недоступны для чтения",
})

L.add("ruRU", "m.Handwerk", {
  rank_75 = "Ученик", rank_150 = "Подмастерье", rank_225 = "Эксперт", rank_300 = "Мастер",
})

L.add("ruRU", "m.Rezeptbuch", {
  profFallback = "Профессия %s",
  recipeFallback = "Рецепт %s",
  diff_orange = "оптимально", diff_yellow = "средне", diff_green = "легко", diff_grey = "без прироста",
})

L.add("ruRU", "p.Handwerk", {
  brand = "INK & EMBERS", book = "ПРОФЕССИИ", page = "РЕМЁСЛА", title = "Ремёсла",
  prof_one = "%s профессия", prof_other = "Профессий: %s", rec_one = "%s рецепт", rec_other = "Рецептов: %s",
  listHead = "ПРОФЕССИИ",
  listEmpty = "Профессий пока нет. Как только вы выучите одну, её кривая запишется здесь сама.",
  primary = "Основная профессия", secondary = "Дополнительная профессия",
  skillOf = "%s / %s",
  skillNow = "Навык: %s из %s", skillRank = "%s · %s",
  balance = "СВОДКА",
  mined = "добыто", picked = "собрано", skinned = "снято шкур", fished = "выловлено", crafted = "создано",
  minedTip = "Руда и камень из месторождений", pickedTip = "Травы и цветы с растений",
  skinnedTip = "Кожа и шкуры врагов (оценка по находкам)", fishedTip = "Всё, что попалось на крючок",
  craftedTip = "Предметы, созданные вами самим, в том числе качеством ниже «Необычное»",
  balanceEmpty = "Пока ничего не добыто и не создано.",
  firstCraft = "Первое создание", firstCraftTip = "Первый созданный вами предмет, начиная с качества «Необычное»",
  level = "Уровень %s",
  curveHead = "НАВЫК ПО ВРЕМЕНИ ИГРЫ", recipesHead = "Изученные рецепты",
  hours = "%s ч", minutes = "%s мин",
  open = "ещё нет", milestoneTip = "Навык %s достигнут",
  tipSkill = "Навык: %s из %s", tipLearned = "Изучено на уровне %s", tipLast = "Последний рост: %s",
  tipWhen = "%s · Уровень %s", tipPlay = "Через %s игрового времени",
  noRecipes = "Рецептов пока нет.",
  recipesUnsure = "Рецепты этой профессии нельзя отнести к ней с уверенностью. Все они есть в книге рецептов.",
  emptyTitle = "Книга ремёсел пока пуста",
  emptyBody = "Выучите профессию, и каждое очко навыка, каждый рецепт и каждая веха запишутся здесь сами.",
  date = "{d}.{m}.{y}",
})

L.add("ruRU", "p.PlaeneHandwerk", {
  brand = "INK & EMBERS", page = "РЕМЁСЛА",
  fTrainer = "Учитель", fNow = "Сейчас", fSoon = "Скоро",
  fTrainerTip = { "Учитель", "Чему учитель профессий учит вас прямо сейчас" },
  fNowTip = { "Сейчас", "Всё, что можно выучить при вашем навыке, включая торговцев, задания и добычу" },
  fSoonTip = { "Скоро", "Что дадут следующие 25 очков навыка" },
  info = "Профессии: %s · сейчас %s · скоро %s",
  skillWord = "Навык %s",
  free = "бесплатно",
  sNow = "сейчас", sSoon = "ещё очков: %s", sLevel = "с уровня %s", sLater = "с навыка %s", sLearned = "изучено",
  learnable = "можно выучить у учителя",
  costLine = "Стоимость обучения %s · в сумках %s",
  costNone = "Сейчас у учителя профессий для вас нет ничего нового.",
  short = "Вам ещё не хватает %s.", enough = "Содержимого сумок хватит на всё.",
  profHead = "Ваши профессии",
  profLine = "%s %s/%s · сейчас %s · скоро %s",
  profLineNoMax = "%s %s · сейчас %s · скоро %s",
  todoOn = "Дело «К учителю профессий» есть в вашем списке.",
  todoOff = "Как только у учителя появится что-то новое для вас, Ink добавит «К учителю профессий» в ваш список дел.",
  retailHead = "Только WoW Forever",
  retailBody = "Данные о рецептах относятся к WoW Forever. В Retail этот лист остаётся пустым.",
  noDataHead = "Нет данных о рецептах",
  noProfHead = "Пока нет профессии",
  noProfBody = "Выучите профессию. Тогда этот лист покажет, какие рецепты идут дальше.",
  noProfDataHead = "Нет рецептов для ваших профессий",
  noProfDataBody = "Для ваших профессий нет данных о рецептах.",
  noApiBody = "Ваши профессии сейчас недоступны для чтения. Попробуйте ещё раз чуть позже.",
  emptyTrainer = "Сейчас у учителя профессий нет ничего нового. Больше навыка – больше рецептов.",
  emptyNow = "Сейчас нечего учить.",
  emptySoon = "В ближайших 25 очках нет ничего нового.",
  prevPage = "Предыдущая страница", nextPage = "Следующая страница",
  tipSource = "Источник: %s", tipCost = "Цена: %s", tipLevel = "Нужен уровень %s", tipRank = "Ранг профессии: %s",
  tipFavor = "Благосклонность торговца: %s", tipNeed = "Не хватает очков навыка: %s",
})

L.add("ruRU", "p.Handwerk", {
  subBerufe = "Профессии", subBerufeTip = "Кривая навыка, вехи и сводка ваших профессий",
  subRezept = "Книга рецептов", subRezeptTip = "Все рецепты ваших профессий, изученные и ещё нет, с материалами (только WoW Forever)",
})

-- journal/pages/HandwerkRezeptbuch.lua (change "runde3", package R)
L.add("ruRU", "p.HandwerkRezeptbuch", {
  brand = "INK & EMBERS", book = "КНИГА РЕЦЕПТОВ", page = "РЕМЁСЛА",
  title = "Книга рецептов", sub = "Все рецепты ваших профессий, изученные и ещё нет",
  listHead = "ПРОФЕССИИ", recipesHead = "РЕЦЕПТЫ",
  fAll = "Все", fLearned = "Изученные", fOpen = "Неизученные",
  fAllTip = { "Все", "Изученные и ещё не изученные рецепты" },
  fLearnedTip = { "Изученные", "Только рецепты, которые вы уже знаете" },
  fOpenTip = { "Неизученные", "Только рецепты, которых вам ещё не хватает" },
  profSub = "Навык: %s из %s", profSubNoMax = "Навык: %s",
  profCount = "%s из %s", profNoCount = "–",
  countLine = "Изучено: %s · не изучено: %s",
  hintNoCache = "Один раз откройте окно профессии, чтобы книга узнала все подробности.",
  hintCache = "Состояние на момент последнего открытия окна профессии. Только что изученные рецепты появятся, когда вы откроете его снова.",
  legend = "Цвет:",
  learned = "изучен", open = "не изучен", fromSkill = "с навыка %s",
  skillWord = "Навык: %s",
  tipSource = "Источник: %s", tipDifficulty = "Сложность: %s", tipUps = "Очков навыка за создание: до %s",
  tipCost = "Цена: %s", tipStock = "В сумках: %s · В банке: %s",
  tipNeeds = "Нужно: %s", tipMore = "Щелчок: подробности ниже",
  needs = "НУЖНО", output = "Создаёт: %s", outputQty = "Создаёт: %s× %s",
  noMats = "Для этого рецепта материалы не нужны.",
  detailNoCache = "Книга узнает результат и материалы только после того, как вы откроете окно профессии.",
  moreMats = "… и ещё: %s",
  itemNo = "Предмет № %s",
  pick = "Выберите рецепт.",
  emptyList = "Для этой профессии рецептов пока нет.",
  emptyFilterLearned = "Изученных рецептов пока нет.", emptyFilterOpen = "Все рецепты этой профессии изучены.",
  noProfTitle = "Пока нет профессии с рецептами",
  noProfBody = "Выучите профессию. Тогда на этом листе появятся все её рецепты, изученные и неизученные.",
  prevPage = "Предыдущая страница", nextPage = "Следующая страница",
})

-- journal/WerkBarKit.lua (Werkauftrag, 1.1.0)
L.add("ruRU", "WerkBarKit", {
  stepPlan = "План",
  stepBuy = "Покупка",
  stepMake = "Изготовление",
  afterCombat = "После боя",
  goldShort = "Не хватает %s",
  busy = "Минутку …",
})
