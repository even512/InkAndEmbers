-- Тексты на русском языке для journal/pages/*.lua. По одному блоку L.add на модуль, с теми же ключами, что и в L.ns.
local _, ns = ...
local L = ns.Locale

-- journal/pages/Chronik.lua
L.add("ruRU", "p.Chronik", {
  ofSeals = "%s из %s", longest = "самый долгий: %s", noLevel = "%s без уровня", pageOf = "Страница %s из %s",
  brand = "INK & EMBERS", profile = "ПРОФИЛЬ", page = "ХРОНИКА", traveller = "ПУТНИК", travellerM = "ПУТНИК", travellerF = "ПУТНИЦА",
  standDate = "По состоянию на %s", standXp = "По состоянию на %s · %s", standFmt = "%d.%m.%Y",
  since = "В пути с", played = "Всего времени в игре", perDay = "В среднем за день игры", sessions = "Сеансы", entries = "Записанные события",
  seals = "МЕДАЛИ ПУТЕШЕСТВИЯ", flow = "Ход уровней", flowSub = "Сколько длился каждый уровень",
  legend = "красные точки = смерть", xpTotal = "ВСЕГО ОПЫТА", sources = "ИСТОЧНИКИ ОПЫТА",
  noXp = "Опыт пока не получен.", diaryEmpty = "Пока ничего не пережито – дневник ждёт.",
  diaryNone = "Из дневника", ofMax = "ИЗ %s", ringStart = "В путь!", prevTip = "Предыдущий день", nextTip = "Следующий день",
  toDiary = "Дневник", toDiaryTip = "Читать дневник", toDiaryTip2 = "Каждый игровой день – запись, день за днём",
  toMates = "Спутники", toMatesTip = "Смотреть спутников", toMatesTip2 = "Кто путешествовал с вами",
  toProfile = "Профиль", toProfileTip = "Профиль, ход уровней и отрывок из дневника",
  toMilestones = "Вехи", toMilestonesTip = "Смотреть вехи", toMilestonesTip2 = "Каждые десять уровней – итоги пути, на 60 уровне – последняя страница",
})

-- journal/pages/ChronikViews.lua
L.add("ruRU", "p.ChronikViews.Diary", {
  page = "ДНЕВНИК", brand = "INK & EMBERS", prevTip = "На день назад", nextTip = "На день вперёд",
  empty = "Записей пока нет", emptyBody = "Как только вы отправитесь в путь, здесь каждый день будет сама писаться запись.",
  blank = "Следующая страница ещё чиста.", blankBody = "То, что случится завтра, появится здесь, когда это произойдёт.",
  dayPair = "Дни %s и %s из %s", dayOne = "День 1 из 1",
})
L.add("ruRU", "p.ChronikViews.Switch", {
  group = "Группа", fire = "У костра", groupTip = "Спутники из вашей группы", fireTip = "Кто сидел с вами у костра",
})
L.add("ruRU", "p.ChronikViews.Mates", {
  levelRange = "Уровни с %s по %s", level = "Уровень %s", date = "{d}.{m}.{y}", togetherFmt = "%s вместе",
  quests_one = "%s задание", quests_other = "заданий: %s", kills_one = "%s убийство", kills_other = "убийств: %s",
  firstMet = "первая встреча: %s, %s", pageOf = "Страница %s из %s", persons_one = "%s человек", persons_other = "человек: %s",
  classes = {
    WARRIOR = "Воин", PALADIN = "Паладин", HUNTER = "Охотник", ROGUE = "Разбойник", PRIEST = "Жрец", DEATHKNIGHT = "Рыцарь смерти",
    SHAMAN = "Шаман", MAGE = "Маг", WARLOCK = "Чернокнижник", MONK = "Монах", DRUID = "Друид", DEMONHUNTER = "Охотник на демонов",
    EVOKER = "Эвокер",
  },
  races = {
    Human = "Человек", Orc = "Орк", Dwarf = "Дворф", NightElf = "Ночной эльф", Scourge = "Нежить", Tauren = "Таурен", Gnome = "Гном",
    Troll = "Тролль", Goblin = "Гоблин", BloodElf = "Эльф крови", Draenei = "Дреней", Worgen = "Ворген", Pandaren = "Пандарен",
    Dracthyr = "Драктир", EarthenDwarf = "Земельник", VoidElf = "Эльф Бездны", Nightborne = "Ночнорождённый",
    HighmountainTauren = "Таурен Крутогорья", LightforgedDraenei = "Озарённый дреней", ZandalariTroll = "Зандалар",
    KulTiran = "Култирасец", DarkIronDwarf = "Дворф из клана Черного Железа", Vulpera = "Вульпера", MagharOrc = "Маг'хар", Mechagnome = "Механогном",
  },
  page = "СПУТНИКИ", brand = "INK & EMBERS", title = "Спутники", empty = "Пока путешествуете в одиночку.",
  emptyBody = "Все, кто путешествует с вами в группе, записываются здесь.", sortRecent = "недавние", sortLong = "самые долгие",
  sortRecentTip = "Сначала те, с кем встречались недавно", sortLongTip = "Сначала те, с кем провели больше всего времени", pick = "Щёлкните по имени, чтобы узнать подробности.",
  prevTip = "Предыдущая страница", nextTip = "Следующая страница",
  truncated = "Очень много встреч: старые больше не полны.", now = "сейчас в вашей группе",
  first = "Первая встреча", last = "Последняя встреча", together = "Время вместе", sessions = "Общие сеансы",
  quests = "Общие задания", kills = "Общие убийства", deaths = "Собственные смерти за это время", unknownZone = "неизвестное место",
  zones = "Общие места", lastQuests = "Недавно сделано вместе", noQuests = "Вместе пока не сдано ни одного задания.",
})
-- journal/pages/ChronikDungeons.lua
L.add("ruRU", "p.ChronikDungeons", {
  page = "ПОДЗЕМЕЛЬЯ", brand = "INK & EMBERS", title = "Подземелья", empty = "Ни одно подземелье пока не посещено.",
  emptyBody = "Как только вы войдёте в подземелье, книга запишет каждое прохождение: когда, как долго, с кем, боссов, смерти и добычу.",
  pick = "Щёлкните по прохождению, чтобы узнать подробности.", prevTip = "Предыдущая страница", nextTip = "Следующая страница", pageOf = "Страница %s из %s",
  runs_one = "%s прохождение", runs_other = "прохождений: %s", truncated = "Очень много прохождений: старые не показываются.",
  date = "{d}.{m}.{y}", dateShort = "{d}.{m}",
  bosses_one = "%s босс повержен", bosses_other = "боссов повержено: %s", complete = "завершено", live = "идёт",
  endUnknown = "конец неизвестен", deaths_one = "%s смерть", deaths_other = "смертей: %s", noDeaths = "без смертей",
  unknownInstance = "Неизвестное подземелье", unknownBoss = "Неизвестный босс",
  when = "Когда", duration = "Длительность", level = "Уровень", kills = "Убито", xp = "Опыт",
  visits_one = "%s вход в подземелье", visits_other = "входов в подземелье: %s", lv = "Уровень %s", levelRange = "Уровни с %s по %s",
  you = "Вы", roll_need = "Мне это нужно", roll_greed = "Не откажусь", roll_de = "Распылить", roll_tmog = "Трансмогрификация",
  whenSame = "{date}, {from}–{to}", whenOther = "{from} – {to}", whenLive = "{date}, с {from}",
  secBosses = "Боссы", secBossesN = "Боссы · повержено: %s", secBossesOf = "Боссы · повержено: %s из %s",
  secGroup = "Группа", secDeaths = "Смерти", secLoot = "Находки (зелёные и лучше)", secQuests = "Задания",
  tries_one = "%s неудачная попытка", tries_other = "неудачных попыток: %s", bossWon = "повержен", bossNot = "не повержен",
  bossCountOnly = "Клиент не сообщил о боях с боссами, известно только их число.",
  noGroup = "Члены группы не записаны.",
  cause_enemy = "от врага", cause_fall = "от падения", cause_drown = "от утопления", cause_fatigue = "от истощения",
  cause_lava = "в лаве", cause_fire = "в огне", cause_slime = "в слизи", cause_environment = "от окружения",
  byFoe = "от: %s", guess = "%s (предположительно)", died = "погиб", more = "… и ещё %s",
  questDone = "сдано", questTaken = "принято", questFallback = "Задание №%s", itemFallback = "Предмет №%s",
  xpUnit = "опыт: %s", reward = "Награда: %s", groupTip = "Группа",
})

-- journal/pages/ChronikMeilensteine.lua
L.add("ruRU", "p.ChronikMeilensteine", {
  page = "ВЕХИ", brand = "INK & EMBERS", title = "Вехи",
  reachedOf = "достигнуто: %s из %s", range = "Уровни %s–%s", final = "Конец пути", finalSub = "Весь путь · уровни 1–%s",
  date = "{d}.{m}.{y}", dateRange = "{from} – {to}", running = "идёт", runningSince = "идёт с {date}", open = "ещё не достигнута",
  before = "до начала записи", noRecord = "ничего не записано", soFar = "%s на данный момент", reachedIn = "достигнута за %s",
  openBody = "Вы ещё не достигли этой вехи. Как только вы достигнете уровня, рассказчик подведёт здесь итог.",
  beforeBody = "Об этом отрезке записей нет: книга пишется только с уровня %s.",
  emptyBody = "Об этом отрезке ничего не записано.",
  truncated = "Очень долгий путь: старые строки обрезаны, числа – это минимумы.",
  kTime = "Время (без AFK)", kZones = "Новые зоны", kKills = "Убито", kQuests = "Задания", kDeaths = "Смерти", kDungeons = "Подземелья",
  kBest = "Лучшая находка", kDays = "Дни игры", kSeals = "Медали", kTotal = "Общее время (без AFK)",
  noDeaths = "без смертей", runs_one = "%s прохождение", runs_other = "прохождений: %s", bosses_one = "%s босс", bosses_other = "боссов: %s",
  sealsOf = "%s из %s", about = "около %s", roughly = "около %s", atLeast = "не менее %s",
  colsHead = "Время на отрезок", colDur = "%s:%s ч", colTip = "Уровни %s–%s", colUnknown = "Время неизвестно", itemFallback = "Предмет №%s",
  zonesMore = "… и ещё %s",
})

-- journal/pages/Kampf.lua
L.add("ruRU", "p.Kampf", {
  pageOf = "Страница %s из %s", deathOf = "Смерть %s из %s", moreZones = "+ ещё зон: %s", closeCount = "победы на грани: %s · %s",
  brand = "INK & EMBERS", page = "БЕСТИАРИЙ", right = "БОЙ", hunted = "ЧАЩЕ ВСЕГО ДОБЫТО", rare = "РЕДКИЙ ВРАГ",
  zoneLabel = "ЗОНА",
  graves = "ГДЕ ПОСТИГЛА СМЕРТЬ", gravesTip = "Зоны, где вы погибали – по одному надгробию на каждую смерть",
  close = "НА ВОЛОСКЕ", prevDeath = "Предыдущая смерть", openDeath = "Щелчок: отчёт об этой смерти",
  openLastDeath = "Щелчок: отчёт о последней смерти здесь", deathNo = "Смерть %s",
  nextDeath = "Следующая смерть", prevCards = "Предыдущие враги", nextCards = "Ещё враги",
  hintHunted = "Победите врага – и он появится здесь.", hintHuntedZone = "Победите здесь врага – и он появится в этом списке.",
  hintGraves = "Каждая смерть получает здесь надгробие.", hintClose = "Выиграйте бой при малом здоровье – и он появится здесь.",
  hintZone = "Победите врага – и ваши охотничьи угодья обретут форму.",
  zoneEmpty = "Пока нет зон с убийствами.", krit = "крит", unknownPic = "?", here = "здесь",
  lowGraves = "Смерти", lowClose = "На волоске", backToGraves = "Назад к смертям",
  noDeathTitle = "Последний вздох",
  modeHot = "Горячие точки", modePoints = "Точно",
  modeHotTip = "Горячие точки: одно пятно на ячейку сетки, больше и темнее при большем числе убийств",
  modePointsTip = "Точно: каждая точка – убитый враг (выборка последних убийств)",
  mapHint = "Колесо мыши: масштаб · Перетаскивание: сдвиг · Двойной щелчок: сброс",
  hotspot = "Горячая точка", killsWord = "%s · убито: %s", onePoint = "Точка убийства", pointsHere = "убито здесь: %s",
  sample = "Выборка: последние %s из %s убийств в этой зоне",
  openLens = "Щелчок: рассмотреть модель вблизи", lensHint = "Перетаскивание: вращать · Колесо мыши: масштаб · Esc или щелчок снаружи: закрыть",
  lowGravesTip = "Где я погиб: зоны с одним надгробием на каждую смерть (щелчок по надгробию: отчёт о смерти)",
  lowCloseTip = "Самые тесные победы",
  huntedTip = "Выберите зону – тогда вся страница покажет только эту зону (при открытии: ваша текущая зона)",
})

-- journal/pages/Momente.lua
L.add("ruRU", "p.Momente", {
  level = "Уровень %s", day = "День %s", readAt = "Прочитано: %s", ofWhich = "из них %s", hour = "%s:00",
  brand = "INK & EMBERS", page = "МГНОВЕНИЯ", moment = "мгновение", moments = "мгн.",
  kept = "записано", zoneOne = "новая зона", zonesOf = "нов. зон.", prevTip = "Более новые мгновения", nextTip = "Более старые мгновения", pageOf = "Страница %d из %d",
  emptyHead = "Ни одно мгновение пока не вклеено.", emptyBody = "Уровни, редкие враги, первые находки и новые места попадают сюда, в альбом.",
  emptyFilter = "В эту группу пока ничего не вклеено.",
  unreadable = "Запись не читается",
  filters = { all = "Все", levels = "Уровни", fights = "Бои", finds = "Находки", places = "Места" },
  clock = "ИГРОВОЕ ВРЕМЯ ПО ЧАСАМ СУТОК", fav = "Любимый час", longest = "Самый долгий сеанс", sessions = "Сеансы",
  interrupted = "прерван", noClock = "Игровое время пока не записано.",
  noClockHand = "Скоро часы покажут, в какое время суток вам больше всего нравится путешествовать.",
  jumpFirst = "Shift+щелчок: к самому новому листу", jumpLast = "Shift+щелчок: к самому старому листу",
  library = "БИБЛИОТЕКА", libEmpty = "Ни одной книги пока не прочитано.", book = "книга", books = "кн.", pageW = "страница", pagesW = "стр.",
  readPages = "прочитано", curios = "ДИКОВИНКИ", curiosEmpty = "Ничего диковинного пока не пережито.",
  back = "Назад к альбому", pagePrev = "Предыдущая страница", pageNext = "Следующая страница", pageGone = "Эта страница не читается.",
})

-- journal/pages/Notizen.lua (сами сокращения разметки остаются)
L.add("ruRU", "p.Notizen", {
  inkTip = "Чернила: %s", inkInsert = "Вставляет {%s}…{/}.", symInsert = "Вставляет {%s}.", reopen = "Открыть снова", tick = "Отметить",
  whenFmt = "%d.%m %H:%M",
  brand = "INK & EMBERS", page = "ЗАМЕТКИ",
  note = "заметка", notes = "зам.", pinnedN = "закреплено: %d", lastEdit = "изменена %s",
  pageOf = "Страница %d из %d", prevTip = "Предыдущая страница", nextTip = "Следующая страница",
  sortNew = "Сначала новые", sortOld = "Сначала старые", sortTitle = "По заголовку",
  sortTip = { "Сортировка", "Закреплённые заметки всегда остаются сверху." },
  searchHint = "Искать в заголовке и тексте …", searchClear = "Очистить поиск",
  newNote = "Новая заметка", newTip = { "Новая заметка", "Создаёт заметку с текущим местом, уровнем и временем." },
  untitled = "Без названия", emptyList = "Заметок пока нет.", emptyListBody = "Нажмите «Новая заметка» ниже, чтобы создать первую.",
  noMatch = "Ни одна заметка не подходит под поиск.", noChar = "Для этого персонажа пока нет хроники.",
  pickNote = "Выберите заметку слева или создайте новую.",
  edit = "Править", read = "Читать", editTip = { "Править", "Пишите текст с разметкой (сохраняется само)." },
  readTip = { "Читать", "Показывает заметку с оформлением; флажки можно щёлкать." },
  pin = "Закреплена", pinTip = { "Закрепить", "Закреплённые заметки остаются вверху списка." },
  onMap = "На карте", onMapTip = { "Показать на карте", "Ставит метку на карте там, где была написана заметка." },
  noPlace = "У этой заметки нет точки на карте (при создании место не читалось).",
  titleHint = "Заголовок …",
  bodyHint = "Пишите здесь … (# заголовок, - список, [ ] флажок)\nShift+щелчок по предмету, заданию или заклинанию вставляет ссылку.",
  created = "создана %s", changed = "изменена %s", levelW = "Уровень %d",
  emptyRead = "Пока пусто. Выберите «Править», чтобы писать.",
  delete = "Удалить", deleteTip = { "Удалить заметку", "Спросит ещё раз." }, confirm = "Точно удалить?",
  confirmTip = { "Точно удалить?", "Повторный щелчок удаляет заметку навсегда." },
  full = "Блокнот заполнен (не больше заметок: %d).", notReady = "Хроника ещё не готова.",
  tooLong = "Заметка заполнена (не больше символов: %d).", linkType = "Можно вставлять только предметы, задания и заклинания.",
  chars = "%d / %d",
  quick = "Быстрые заметки",
  quickTip = { "Быстрые заметки", "Показывает маленькое поле у края экрана: напишите, нажмите Enter – и заметка в блокноте." },
  ink = "Чернила", symbols = "Символы",
  tools = {
    head = { label = "Заголовок", tip = { "Заголовок", "Ставит «# » перед строкой." } },
    emph = { label = "Выделение", tip = { "Выделение", "Вставляет **…** (текст между ними выделяется)." } },
    bullet = { label = "Список", tip = { "Маркированный список", "Ставит «- » перед строкой." } },
    check = { label = "Флажок", tip = { "Список с флажками", "Ставит «[ ] » перед строкой; в режиме «Читать» его можно отметить." } },
    rule = { label = "Линия", tip = { "Разделитель", "Вставляет линию «---»." } },
  },
  symbolsTip = { "Символы", "Вставьте метки рейда и символы карты.", "Ссылки: Shift+щелчок по предмету, заданию или заклинанию." },
  truncated = "… (остальные строки – только в режиме «Править»)",
})

-- journal/pages/Quests.lua
L.add("ruRU", "p.Dungeons", {
  subRuns = "Прохождения",
  subRunsTip = "Каждое прохождение: когда, как долго, с кем, боссы, смерти и добыча",
  subQuests = "Задания подземелий",
  subQuestsTip = "Все задания подземелий и их цепочки (данные: QuestieDB, только WoW Forever)",
})

L.add("ruRU", "p.Quests", {
  subHistory = "История",
  subHistoryTip = "Выполненные задания с текстом, хронологией и наградой",
  subOpen = "Открытые",
  subOpenTip = "Задания, которые можно взять прямо сейчас, с картой квестодателей (данные: QuestieDB)",
  subZones = "Зоны",
  subZonesTip = "Насколько выполнены задания каждой зоны, с медалью «Мастер зон» (только WoW Forever)",
  pageOf = "Страница %d из %d", prevPage = "Предыдущая страница", nextPage = "Следующая страница", level = "Уровень %s",
  filterName = "Название «%s»", filterArea = "Зона %s", filterLevel = "Уровень %s",
  countOf = "заданий: %s из %s", count_one = "%s задание", count_other = "заданий: %s", questLevel = "Уровень задания %s",
  goalsMore_one = "+ ещё %s цель", goalsMore_other = "+ ещё целей: %s", walked = "пройдено: %s", day = "День %s",
  after = "через %s", afterApprox = "примерно через %s", vanished = "пропало из журнала заданий", itemNo = "Предмет №%s",
  chosenOf = "%s (1 из %s)", countX = "%s × · %s", moreItems = "+ ещё предметов: %s", choiceItemsUnknown = "Предметы на выбор не записаны.",
  abandonedN = "брошено: %s",
  book = "КНИГА ЗАДАНИЙ", title = "INK & EMBERS", quests = "ЗАДАНИЯ",
  colName = "Название", colArea = "Зона", colLevel = "Уровень", colDate = "Сдано",
  search = "Искать по названию …", all = "Все", sortLbl = "Сортировка и фильтр",
  sortUpTip = "По возрастанию", sortDownTip = "По убыванию", clearTip = "Сбросить фильтр",
  headTip = "Щелчок: сортировка и фильтр", headTipSort = "Щелчок: сортировка", filterLbl = "Фильтр: ",
  toTable = "Назад к таблице",
  noMatch = "Ни одно задание не подходит под этот фильтр.",
  sortAsc = "Сортировка: по возрастанию", sortDesc = "Сортировка: по убыванию",
  goals = "Цели", turnIn = "Сдача", life = "Хронология", rewardHead = "Награда",
  noDetail = "Текст описания не записан.", noGoals = "Цели не записаны.", noReward = "Текст сдачи не записан.",
  emptyHead = "Выполненных заданий пока нет.",
  emptyBody = "Как только вы выполните задание, хроника запишет его здесь. Какие задания ещё ждут вас, видно в разделе «Открытые».",
  emptyRight = "Хронология и награды появятся с первым выполненным заданием.",
  accepted = "Принято", abandoned = "Брошено", turned = "Сдано", between = "По пути",
  done = "выполнено",
  stateWord = { done = "выполнено", open = "открыто", abandoned = "брошено", seen = "только прочитано" },
  xpUnit = "опыт",
  chosen = "выбрано", notChosen = "не выбрано", received = "получено", choiceNotRecorded = "Выбор не записан", fixed = "Награда", choice = "на выбор",
  noItems = "без наград-предметов", noRewardData = "награда не записана",
  partial = "Остальные награды на выбор неизвестны.",
  speakPlay = "Прочитать вслух (Spoken)", speakStop = "Стоп", speakNone = "В Spoken нет записи",
  partAccept = "Текст задания", partProgress = "Текст о ходе выполнения", partComplete = "Текст сдачи",
})

-- journal/pages/Schaetze.lua
L.add("ruRU", "p.Schaetze", {
  level = "Уровень %s", levels = "Уровни %s–%s", total = "Всего %s", gearSub = "изменений: %s · уровни с 1 по %s", gearSubNone = "Изменений пока нет · наденьте что-нибудь новое",
  brand = "INK & EMBERS", page = "СОКРОВИЩА", book = "КОШЕЛЁК", bag = "В КОШЕЛЬКЕ",
  ledger = "Бухгалтерская книга", flow = "Движение золота", flowSub = "Откуда пришло золото и куда ушло",
  toBars = "Источники", toBand = "Уровни", noMoney = "Золото пока не двигалось.",
  bagEmpty = "Пустой кошелёк",
  ledgerEmpty = "Золото пока не двигалось. Добыча, награды за задания и торговцы записываются здесь сами.",
  flowEmpty = "Золото пока не двигалось. Как только зазвенят монеты, здесь будет видно, откуда они пришли и куда ушли.",
  gearEmptyHand = "Снаряжение пока не записано. С каждым надетым предметом здесь растёт хронология от 1 уровня до %s.",
  qualityEmpty = "Каждая находка считается здесь по качеству.",
  flowLevels = "Доходы и расходы по уровням", income = "Доходы", expense = "Расходы", net = "Итого",
  toHold = "Запасы", holdTip = "Запасы по уровням", holdTip2 = "Больше всего золота в кошельке на каждом уровне",
  flowHold = "Наибольшее золото в кошельке по уровням", holdPeak = "Пик %s · уровень %s", holdJump = "Крупнейший скачок +%s · уровень %s",
  gear = "Снаряжение во времени", gearEmpty = "Снаряжение пока не записано.", quality = "НАХОДКИ ПО КАЧЕСТВУ",
  incomeBar = "ДОХОДЫ", expenseBar = "РАСХОДЫ И КОШЕЛЁК", blue = "Первый редкий предмет",
  toOverview = "Обзор", overviewTip = "Кошелёк, бухгалтерская книга и движение золота",
  toFunde = "Находки снаряжения", fundeTip = "Все находки снаряжения необычного качества и лучше",
  fundeTipEpic = "«Эпическое» объединяет эпические и легендарные находки.",
  fundeTip2 = "Таблица: откуда, где и на каком уровне",
  toAnprobe = "Путь снаряжения", anprobeTip = "Ваш персонаж со снаряжением каждого уровня",
  anprobeTip2 = "3D-модель и хронология: примеряйте уровень за уровнем",
})

-- journal/pages/SchaetzeAnprobe.lua
L.add("ruRU", "p.SchaetzeAnprobe", {
  brand = "INK & EMBERS", book = "СНАРЯЖЕНИЕ", page = "ПУТЬ СНАРЯЖЕНИЯ",
  title = "Путь снаряжения", recordFrom = "Записано с уровня %s",
  level = "Уровень %s", startState = "Начальное снаряжение", noChange = "без изменений", newPieces = "новых: %s",
  empty = "Снаряжение пока не записано.",
  emptyBody = "Путь снаряжения заполнится при следующей смене снаряжения.",
  slotEmpty = "пусто", itemNo = "Предмет №%s", newTag = "новое",
  notShown = "На модели не показывается",
  modelCombat = "Модель появится после боя.", modelMissing = "Модель здесь показать нельзя.",
})

-- journal/pages/SchaetzeFunde.lua
L.add("ruRU", "p.SchaetzeFunde", {
  prevPage = "Предыдущая страница", nextPage = "Следующая страница", clock = "%s", itemNo = "Предмет №%s",
  countOf = "находок: %s из %s", count_one = "%s находка", count_other = "находок: %s",
  brand = "INK & EMBERS", book = "СНАРЯЖЕНИЕ", page = "НЕОБЫЧНОЕ И ЛУЧШЕ",
  title = "Находки снаряжения", sub = "Всё необычное и лучше, что можно надеть",
  colItem = "Предмет", colSlot = "Ячейка", colLevel = "Уровень", colTime = "Получено",
  back = "Назад к обзору", all = "Все", sortLbl = "Сортировка и фильтр", sortOnlyLbl = "Сортировка",
  sortUpTip = "По возрастанию", sortDownTip = "По убыванию", clearTip = "Сбросить фильтр",
  headTip = "Щелчок: сортировка и фильтр", headTipSort = "Щелчок: сортировка", headTipZone = "Щелчок: сортировка, фильтр по зоне",
  filterWord = { quality = "Качество", slot = "Ячейка", zone = "Зона" },
  pick = "Выберите находку слева.", secFound = "Найдено", secStats = "Характеристики", secLine = "Хронология",
  labWhen = "Когда", labWhere = "Где", labSource = "Источник", labReplaced = "Заменено",
  whenNone = "Время неизвестно", whereNone = "Место неизвестно", levelWord = "Уровень персонажа ",
  replacedNone = "предмет неизвестен", replacedEmpty = "ничего (ячейка была пуста)", notWorn = "не надето",
  statsHint = "Характеристики показывает подсказка: наведите курсор на значок.", itemLevelWord = "Уровень предмета ",
  lineNone = "Для этой ячейки нет сведений об уровнях.", lineLevel = "Уровень ",
  lineHead = "Хронология: ", lineCount = { " находка", " шт." },
  sortAsc = "Сортировка: по возрастанию", sortDesc = "Сортировка: по убыванию", filterLbl = "Фильтр: ",
  empty = "Снаряжения необычного качества и лучше пока не найдено.",
  emptyBody = "Как только вы получите зелёное или лучшее снаряжение, хроника запишет его здесь.",
  noMatch = "Ни одна находка не подходит под этот фильтр.",
})

-- 1.0.12 data books
L.add("ruRU", "p.Schaetze", {
  toTrade = "Торговля",
  tradeTip = "Аукцион, почта и обмен",
  tradeTip2 = "Цифры из счетов, писем и обменов",
  tradeSub = "Аукцион, почта и обмен",
})

-- change "runde3" (packages A, R, E, L)
-- journal/pages/ChronikVermaechtnis.lua
L.add("ruRU", "p.ChronikVermaechtnis", {
  challengesHead = "Испытания", tabClasses = "Классы", pageOf = "Страница %s из %s", tipProgress = "Прогресс: %s из %s", progress = "%s/%s", colAch = "Испытание", colState = "Состояние", colPoints = "Очки", prevPage = "Предыдущая страница", nextPage = "Следующая страница",
  page = "НАСЛЕДИЕ", brand = "INK & EMBERS", title = "Наследие",
  subLabel = "Наследие", subTip = "Очки, задания классов, деревья талантов и награды системы «Наследие»",
  subTip2 = "Действует для всей учётной записи; только WoW Forever",
  points = "Очки: %s из %s", pointsOnly = "Очки: %s", pointsMax = "Возможные очки: %s",
  level = "Путь наследия: уровень %s", levelOf = "Путь наследия: уровень %s из %s",
  classesHead = "Задания классов", tier1 = "Новичок", tier2 = "Опытный", tier3 = "Мастер",
  date = "{d}.{m}.{y}", doneShort = "готово", openShort = "открыто",
  tipDone = "Выполнено: %s", tipDoneNoDate = "Выполнено", tipOpen = "Ещё не выполнено", tipPoints_other = "Очков: %s",
  tipPoints_one = "Очков: %s", tipOther = "Получено другим персонажем вашей учётной записи",
  tipTier = "%s · %s", classesUnreadable = "Сейчас задания классов прочитать нельзя.",
  rewardsHead = "Награды пути", rewardLevel = "Уровень %s", rewardFallback = "Предмет № %s", rewardUnknown = "Награда",
  collected = "получена", ready = "можно получить", reached = "достигнуто",
  missing_one = "осталось очков: %s", missing_other = "осталось очков: %s", tipNeed = "Доступно с уровня %s пути наследия",
  rewardsUnreadable = "Сейчас награды прочитать нельзя.",
  treesTitle = "Деревья талантов", tree_professions = "Профессии", tree_adventure = "Приключения", tree_progression = "Развитие",
  rank = "%s/%s", tipRank = "Ранг %s из %s", unknown = "Неизвестно", treeUnreadable = "Сейчас это дерево прочитать нельзя.",
  treeEmpty = "Узлы не найдены.",
  hintCombat = "Во время боя книга не читает наследие. Вернитесь после боя.",
  hintUnreadable = "Сейчас наследие прочитать нельзя. Попробуйте ещё раз чуть позже.",
  reread = "Прочитать снова",
  staleCombat = "В бою: сохранённое состояние от {date}", staleUnreadable = "Сейчас не читается: сохранённое состояние от {date}",
})

L.add("ruRU", "p.Schaetze", {
  toAuktion = "Аукцион", auktionTip = "Все продажи и покупки на аукционе",
  auktionTip2 = "Таблица с сортировкой: дата, предмет, количество и цена",
})

-- journal/pages/SchaetzeAuktion.lua
L.add("ruRU", "p.SchaetzeAuktion", {
  brand = "INK & EMBERS", book = "АУКЦИОН", page = "СВОДКА",
  title = "Аукцион", count_one = "%s счёт", count_other = "Счетов: %s", countOf = "Счетов: %s из %s",
  prevPage = "Предыдущая страница", nextPage = "Следующая страница",
  colTime = "Дата", colKind = "Тип", colItem = "Предмет", colCount = "Кол.", colPrice = "Всего", colUnit = "За шт.",
  fAll = "Все", fSold = "Продажи", fBought = "Покупки",
  fAllTip = "Все счета", fSoldTip = "Только продажи", fBoughtTip = "Только покупки",
  sortAsc = "Сортировка: по возрастанию", sortDesc = "Сортировка: по убыванию", headTip = "Щелчок: сортировать, ещё щелчок: перевернуть",
  tipCount = "Количество: %s", tipTotal = "Общая цена: %s", tipUnit = "За штуку: %s", tipFee = "Комиссия: %s", tipNoPrice = "Цена не читается",
  empty = "Счетов аукциона пока нет.",
  emptyBody = "Как только вы опустошите почтовый ящик и там окажутся счета за продажи или покупки, хроника запишет их здесь.",
  noMatch = "Ни один счёт не подходит под этот фильтр.",
  balTitle = "Сводка", balSub = "Все счета, независимо от фильтра",
  secSold = "Продажи", secBought = "Покупки", secSaldo = "Итог",
  labSoldN = "Продано предметов", labIncome = "Доход", labFee = "Комиссия", labBoughtN = "Куплено предметов", labSpent = "Расходы",
  labSaldo = "Сальдо", saldoPlus = "Заработано больше, чем потрачено", saldoMinus = "Потрачено больше, чем заработано", saldoZero = "В ноль",
  balNote = "Основа — счета из вашего почтового ящика. Ставки, залоги и истёкшие аукционы ни в одном счёте не появляются.",
  noPrice = "–",
})

