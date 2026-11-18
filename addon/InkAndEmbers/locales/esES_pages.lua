-- Textos en español para journal/pages/*.lua (también para esMX mediante respaldo). Un bloque L.add por módulo, con las mismas claves que L.ns.
local _, ns = ...
local L = ns.Locale

-- journal/pages/Chronik.lua
L.add("esES", "p.Chronik", {
  ofSeals = "%s de %s", longest = "la más larga: %s", noLevel = "%s sin nivel", pageOf = "Página %s de %s",
  brand = "INK & EMBERS", profile = "PERFIL", page = "CRÓNICA", traveller = "VIAJERO", travellerM = "VIAJERO", travellerF = "VIAJERA",
  standDate = "A fecha de %s", standXp = "A fecha de %s · %s", standFmt = "%d/%m/%Y",
  since = "En el camino desde", played = "Tiempo de juego total", perDay = "Media por día de juego", sessions = "Sesiones", entries = "Eventos registrados",
  seals = "MEDALLAS DEL VIAJE", flow = "Flujo de niveles", flowSub = "Cuánto tardó cada nivel",
  legend = "puntos rojos = muerte", xpTotal = "EXPERIENCIA TOTAL", sources = "FUENTES DE EXPERIENCIA",
  noXp = "Aún no has ganado experiencia.", diaryEmpty = "Aún no has vivido nada: el diario está esperando.",
  diaryNone = "Del diario", ofMax = "DE %s", ringStart = "¡Allá vamos!", prevTip = "Día anterior", nextTip = "Día siguiente",
  toDiary = "Diario", toDiaryTip = "Leer el diario", toDiaryTip2 = "Cada día de juego como una entrada, día a día",
  toMates = "Compañeros", toMatesTip = "Ver compañeros", toMatesTip2 = "Quién viajó contigo",
  toProfile = "Perfil", toProfileTip = "Perfil, flujo de niveles y extracto del diario",
  toMilestones = "Hitos", toMilestonesTip = "Ver hitos", toMilestonesTip2 = "Cada diez niveles, un recuento del viaje; en el nivel 60, la página final",
})

-- journal/pages/ChronikViews.lua
L.add("esES", "p.ChronikViews.Diary", {
  page = "DIARIO", brand = "INK & EMBERS", prevTip = "Un día atrás", nextTip = "Un día adelante",
  empty = "Aún no hay entrada", emptyBody = "En cuanto te pongas en camino, cada día se escribirá aquí una entrada por sí sola.",
  blank = "La página siguiente sigue en blanco.", blankBody = "Lo que ocurra mañana aparecerá aquí cuando haya ocurrido.",
  dayPair = "Días %s y %s de %s", dayOne = "Día 1 de 1",
})
L.add("esES", "p.ChronikViews.Switch", {
  group = "Grupo", fire = "Junto al fuego", groupTip = "Compañeros de tu grupo", fireTip = "Quién se sentó contigo junto a la hoguera",
})
L.add("esES", "p.ChronikViews.Mates", {
  levelRange = "Nivel %s a %s", level = "Nivel %s", date = "{d}/{m}/{y}", togetherFmt = "%s juntos",
  quests_one = "%s misión", quests_other = "%s misiones", kills_one = "%s baja", kills_other = "%s bajas",
  firstMet = "primer encuentro en %s el %s", pageOf = "Página %s de %s", persons_one = "%s persona", persons_other = "%s personas",
  classes = {
    WARRIOR = "Guerrero", PALADIN = "Paladín", HUNTER = "Cazador", ROGUE = "Pícaro", PRIEST = "Sacerdote", DEATHKNIGHT = "Caballero de la Muerte",
    SHAMAN = "Chamán", MAGE = "Mago", WARLOCK = "Brujo", MONK = "Monje", DRUID = "Druida", DEMONHUNTER = "Cazador de demonios",
    EVOKER = "Evocador",
  },
  races = {
    Human = "Humano", Orc = "Orco", Dwarf = "Enano", NightElf = "Elfo de la noche", Scourge = "No-muerto", Tauren = "Tauren", Gnome = "Gnomo",
    Troll = "Trol", Goblin = "Goblin", BloodElf = "Elfo de sangre", Draenei = "Draenei", Worgen = "Huargen", Pandaren = "Pandaren",
    Dracthyr = "Dracthyr", EarthenDwarf = "Terráneo", VoidElf = "Elfo del Vacío", Nightborne = "Nocheterna",
    HighmountainTauren = "Tauren de Altamontaña", LightforgedDraenei = "Draenei forjado por la Luz", ZandalariTroll = "Trol zandalari",
    KulTiran = "Kultirano", DarkIronDwarf = "Enano Hierro Negro", Vulpera = "Vulpera", MagharOrc = "Orco mag'har", Mechagnome = "Mecagnomo",
  },
  page = "COMPAÑEROS", brand = "INK & EMBERS", title = "Compañeros", empty = "Todavía viajas en solitario.",
  emptyBody = "Quien viaje contigo en grupo queda registrado aquí.", sortRecent = "recientes", sortLong = "más tiempo",
  sortRecentTip = "Primero los que viste más recientemente", sortLongTip = "Primero los que pasaron más tiempo contigo", pick = "Haz clic en un nombre para ver los detalles.",
  prevTip = "Página anterior", nextTip = "Página siguiente",
  truncated = "Muchísimos encuentros: los más antiguos ya no están completos.", now = "en tu grupo ahora mismo",
  first = "Primer encuentro", last = "Visto por última vez", together = "Tiempo juntos", sessions = "Sesiones compartidas",
  quests = "Misiones compartidas", kills = "Bajas compartidas", deaths = "Muertes propias entretanto", unknownZone = "un lugar desconocido",
  zones = "Lugares compartidos", lastQuests = "Lo último hecho juntos", noQuests = "Aún no han entregado ninguna misión juntos.",
})
-- journal/pages/ChronikDungeons.lua
L.add("esES", "p.ChronikDungeons", {
  page = "MAZMORRAS", brand = "INK & EMBERS", title = "Mazmorras", empty = "Aún no has visitado ninguna mazmorra.",
  emptyBody = "En cuanto entres en una mazmorra, el libro registra cada expedición: cuándo, cuánto duró, con quién, los jefes, las muertes y el botín.",
  pick = "Haz clic en una expedición para ver los detalles.", prevTip = "Página anterior", nextTip = "Página siguiente", pageOf = "Página %s de %s",
  runs_one = "%s expedición", runs_other = "%s expediciones", truncated = "Muchísimas expediciones: las más antiguas no aparecen en la lista.",
  date = "{d}/{m}/{y}", dateShort = "{d}/{m}",
  bosses_one = "%s jefe derrotado", bosses_other = "%s jefes derrotados", complete = "completada", live = "en curso",
  endUnknown = "final desconocido", deaths_one = "%s muerte", deaths_other = "%s muertes", noDeaths = "sin muertes",
  unknownInstance = "Mazmorra desconocida", unknownBoss = "Jefe desconocido",
  when = "Cuándo", duration = "Duración", level = "Nivel", kills = "Bajas", xp = "Experiencia",
  visits_one = "%s entrada a la instancia", visits_other = "%s entradas a la instancia", lv = "Nivel %s", levelRange = "Nivel %s a %s",
  you = "Tú", roll_need = "Necesidad", roll_greed = "Codicia", roll_de = "Desencantar", roll_tmog = "Transfiguración",
  whenSame = "{date}, {from}–{to}", whenOther = "{from} – {to}", whenLive = "{date}, desde {from}",
  secBosses = "Jefes", secBossesN = "Jefes · %s derrotados", secBossesOf = "Jefes · %s de %s derrotados",
  secGroup = "Grupo", secDeaths = "Muertes", secLoot = "Hallazgos (verdes o mejores)", secQuests = "Misiones",
  tries_one = "%s intento fallido", tries_other = "%s intentos fallidos", bossWon = "derrotado", bossNot = "no derrotado",
  bossCountOnly = "El cliente no informó de los combates contra jefes, solo se conoce la cantidad.",
  noGroup = "No se registraron miembros del grupo.",
  cause_enemy = "a manos de un enemigo", cause_fall = "por una caída", cause_drown = "ahogado", cause_fatigue = "de agotamiento",
  cause_lava = "en lava", cause_fire = "en el fuego", cause_slime = "en limo", cause_environment = "por el entorno",
  byFoe = "a manos de %s", guess = "%s (supuesto)", died = "murió", more = "… y %s más",
  questDone = "entregada", questTaken = "aceptada", questFallback = "Misión n.º %s", itemFallback = "Objeto n.º %s",
  xpUnit = "%s de experiencia", reward = "Recompensa: %s", groupTip = "Grupo",
})

-- journal/pages/ChronikMeilensteine.lua
L.add("esES", "p.ChronikMeilensteine", {
  page = "HITOS", brand = "INK & EMBERS", title = "Hitos",
  reachedOf = "%s de %s alcanzados", range = "Nivel %s–%s", final = "Fin del viaje", finalSub = "El viaje entero · nivel 1–%s",
  date = "{d}/{m}/{y}", dateRange = "{from} – {to}", running = "en curso", runningSince = "en curso desde {date}", open = "aún sin alcanzar",
  before = "antes del registro", noRecord = "nada registrado", soFar = "%s hasta ahora", reachedIn = "alcanzado en %s",
  openBody = "Aún no has alcanzado este hito. En cuanto llegues a ese nivel, el narrador hará aquí el balance.",
  beforeBody = "No hay registro de este tramo: el libro solo escribe a partir del nivel %s.",
  emptyBody = "No hay nada registrado de este tramo.",
  truncated = "Un viaje larguísimo: las líneas más antiguas se recortan, las cifras son mínimos.",
  kTime = "Tiempo (sin ausencias)", kZones = "Zonas nuevas", kKills = "Bajas", kQuests = "Misiones", kDeaths = "Muertes", kDungeons = "Mazmorras",
  kBest = "Mejor hallazgo", kDays = "Días de juego", kSeals = "Medallas", kTotal = "Tiempo total (sin ausencias)",
  noDeaths = "sin muertes", runs_one = "%s expedición", runs_other = "%s expediciones", bosses_one = "%s jefe", bosses_other = "%s jefes",
  sealsOf = "%s de %s", about = "alrededor de %s", roughly = "alrededor de %s", atLeast = "al menos %s",
  colsHead = "Tiempo por tramo", colDur = "%s:%s h", colTip = "Nivel %s–%s", colUnknown = "Tiempo desconocido", itemFallback = "Objeto n.º %s",
  zonesMore = "… y %s más",
})

-- journal/pages/Kampf.lua
L.add("esES", "p.Kampf", {
  pageOf = "Página %s de %s", deathOf = "Muerte %s de %s", moreZones = "+ %s zonas más", closeCount = "%s victorias por los pelos · %s",
  brand = "INK & EMBERS", page = "BESTIARIO", right = "COMBATE", hunted = "MÁS CAZADOS", rare = "ENEMIGO RARO",
  zoneLabel = "ZONA",
  graves = "DÓNDE MORÍ", gravesTip = "Zonas donde moriste: una lápida por muerte",
  close = "POR LOS PELOS", prevDeath = "Muerte anterior", openDeath = "Clic: informe de esta muerte",
  openLastDeath = "Clic: informe de la última muerte aquí", deathNo = "Muerte %s",
  nextDeath = "Muerte siguiente", prevCards = "Enemigos anteriores", nextCards = "Más enemigos",
  hintHunted = "Abate a un enemigo y aparecerá aquí.", hintHuntedZone = "Abate aquí a un enemigo y aparecerá en esta lista.",
  hintGraves = "Cada muerte recibe aquí una lápida.", hintClose = "Gana un combate con poca vida y aparecerá aquí.",
  hintZone = "Abate a un enemigo y tus cotos de caza irán tomando forma.",
  zoneEmpty = "Aún no hay ninguna zona con bajas.", krit = "crít.", unknownPic = "?", here = "aquí",
  lowGraves = "Muertes", lowClose = "Por los pelos", backToGraves = "Volver a las muertes",
  noDeathTitle = "El último aliento",
  modeHot = "Zonas calientes", modePoints = "Exacto",
  modeHotTip = "Zonas calientes: una mancha por celda de la cuadrícula, más grande y más oscura cuantas más bajas",
  modePointsTip = "Exacto: cada punto es un enemigo abatido (muestra de las últimas bajas)",
  mapHint = "Rueda del ratón: zoom · Arrastrar: mover · Doble clic: restablecer",
  hotspot = "Zona caliente", killsWord = "%s · %s bajas", onePoint = "Punto de baja", pointsHere = "%s bajas aquí",
  sample = "Muestra: las últimas %s de %s bajas en esta zona",
  openLens = "Clic: ver el modelo de cerca", lensHint = "Arrastrar: girar · Rueda del ratón: zoom · Esc o clic fuera: cerrar",
  lowGravesTip = "Dónde morí: zonas con una lápida por muerte (clic en una lápida: informe de la muerte)",
  lowCloseTip = "Las victorias más ajustadas",
  huntedTip = "Elige una zona: toda la página mostrará entonces solo esa zona (al abrir: tu zona actual)",
})

-- journal/pages/Momente.lua
L.add("esES", "p.Momente", {
  level = "Nivel %s", day = "Día %s", readAt = "Leído: %s", ofWhich = "de ellos %s", hour = "%s:00",
  brand = "INK & EMBERS", page = "MOMENTOS", moment = "momento", moments = "momentos",
  kept = "registrados", zoneOne = "zona nueva", zonesOf = "zonas nuevas", prevTip = "Momentos más recientes", nextTip = "Momentos más antiguos", pageOf = "Página %d de %d",
  emptyHead = "Aún no hay ningún momento pegado.", emptyBody = "Niveles, enemigos raros, primeros hallazgos y lugares nuevos acaban aquí, en el álbum.",
  emptyFilter = "Aún no hay nada pegado en este grupo.",
  unreadable = "Entrada ilegible",
  filters = { all = "Todos", levels = "Niveles", fights = "Combates", finds = "Hallazgos", places = "Lugares" },
  clock = "TIEMPO DE JUEGO SEGÚN LA HORA DEL DÍA", fav = "Hora favorita", longest = "Sesión más larga", sessions = "Sesiones",
  interrupted = "interrumpida", noClock = "Aún no se ha registrado tiempo de juego.",
  noClockHand = "Pronto el reloj mostrará a qué hora del día te gusta más viajar.",
  jumpFirst = "Mayús+clic: a la hoja más reciente", jumpLast = "Mayús+clic: a la hoja más antigua",
  library = "BIBLIOTECA", libEmpty = "Aún no has leído ningún libro.", book = "libro", books = "libros", pageW = "página", pagesW = "páginas",
  readPages = "leídas", curios = "CURIOSIDADES", curiosEmpty = "Aún no has vivido nada curioso.",
  back = "Volver al álbum", pagePrev = "Página anterior", pageNext = "Página siguiente", pageGone = "Esta página no se puede leer.",
})

-- journal/pages/Notizen.lua (los atajos de marcado en sí se mantienen)
L.add("esES", "p.Notizen", {
  inkTip = "Tinta: %s", inkInsert = "Inserta {%s}…{/}.", symInsert = "Inserta {%s}.", reopen = "Reabrir", tick = "Marcar como hecho",
  whenFmt = "%d/%m %H:%M",
  brand = "INK & EMBERS", page = "NOTAS",
  note = "nota", notes = "notas", pinnedN = "%d fijadas", lastEdit = "última %s",
  pageOf = "Página %d de %d", prevTip = "Página anterior", nextTip = "Página siguiente",
  sortNew = "Primero las más recientes", sortOld = "Primero las más antiguas", sortTitle = "Por título",
  sortTip = { "Orden", "Las notas fijadas siempre se quedan arriba." },
  searchHint = "Buscar en título y texto …", searchClear = "Borrar búsqueda",
  newNote = "Nueva nota", newTip = { "Nueva nota", "Crea una nota con el lugar, el nivel y la hora actuales." },
  untitled = "Sin título", emptyList = "Aún no hay notas.", emptyListBody = "Usa “Nueva nota” abajo para crear la primera.",
  noMatch = "Ninguna nota coincide con la búsqueda.", noChar = "Todavía no hay crónica para este personaje.",
  pickNote = "Elige una nota a la izquierda o crea una nueva.",
  edit = "Editar", read = "Leer", editTip = { "Editar", "Escribe texto con marcado (se guarda solo)." },
  readTip = { "Leer", "Muestra la nota con formato; las casillas se pueden marcar con un clic." },
  pin = "Fijada", pinTip = { "Fijar", "Las notas fijadas se quedan arriba en la lista." },
  onMap = "En el mapa", onMapTip = { "Mostrar en el mapa", "Pone una chincheta en el mapa donde se escribió la nota." },
  noPlace = "Esta nota no tiene punto en el mapa (no se pudo leer ningún lugar cuando se creó).",
  titleHint = "Título …",
  bodyHint = "Escribe aquí … (# título, - lista, [ ] casilla)\nMayús+clic en un objeto, misión o hechizo para insertar un enlace.",
  created = "creada %s", changed = "modificada %s", levelW = "Nivel %d",
  emptyRead = "Aún está vacía. Elige “Editar” para escribir.",
  delete = "Borrar", deleteTip = { "Borrar nota", "Pregunta una vez más." }, confirm = "¿Borrar de verdad?",
  confirmTip = { "¿Borrar de verdad?", "Si haces clic otra vez, la nota se borra para siempre." },
  full = "El cuaderno está lleno (como máximo %d notas).", notReady = "La crónica aún no está lista.",
  tooLong = "La nota está llena (como máximo %d caracteres).", linkType = "Solo se pueden insertar objetos, misiones y hechizos.",
  chars = "%d / %d",
  quick = "Notas rápidas",
  quickTip = { "Notas rápidas", "Muestra un pequeño campo en el borde de la pantalla: escribe, pulsa Intro y la nota ya está en el cuaderno." },
  ink = "Tinta", symbols = "Símbolos",
  tools = {
    head = { label = "Título", tip = { "Título", "Pone “# ” delante de la línea." } },
    emph = { label = "Énfasis", tip = { "Énfasis", "Inserta **…** (el texto de en medio queda resaltado)." } },
    bullet = { label = "Lista", tip = { "Lista con viñetas", "Pone “- ” delante de la línea." } },
    check = { label = "Casilla", tip = { "Lista de comprobación", "Pone “[ ] ” delante de la línea; se puede marcar en “Leer”." } },
    rule = { label = "Línea", tip = { "Separador", "Inserta una línea “---”." } },
  },
  symbolsTip = { "Símbolos", "Inserta marcas de banda y símbolos del mapa.", "Enlaces: Mayús+clic en un objeto, misión o hechizo." },
  truncated = "… (más líneas solo en “Editar”)",
})

-- journal/pages/Quests.lua
L.add("esES", "p.Dungeons", {
  subRuns = "Expediciones",
  subRunsTip = "Cada expedición: cuándo, cuánto duró, con quién, jefes, muertes y botín",
  subQuests = "Misiones de mazmorra",
  subQuestsTip = "Todas las misiones de mazmorra y sus cadenas de misiones (datos: QuestieDB, solo WoW Forever)",
})

L.add("esES", "p.Quests", {
  subHistory = "Historial",
  subHistoryTip = "Misiones completadas con texto de la misión, línea de tiempo y recompensa",
  subOpen = "Abiertas",
  subOpenTip = "Misiones que puedes aceptar ahora mismo, con un mapa de los dadores de misiones (datos: QuestieDB)",
  subZones = "Zonas",
  subZonesTip = "Cuánto está hecho de las misiones de cada zona, con la medalla Maestro de zonas (solo WoW Forever)",
  pageOf = "Página %d de %d", prevPage = "Página anterior", nextPage = "Página siguiente", level = "Nivel %s",
  filterName = "Nombre “%s”", filterArea = "Zona %s", filterLevel = "Nivel %s",
  countOf = "%s de %s misiones", count_one = "%s misión", count_other = "%s misiones", questLevel = "Nivel de misión %s",
  goalsMore_one = "+ %s objetivo más", goalsMore_other = "+ %s objetivos más", walked = "%s caminados", day = "Día %s",
  after = "tras %s", afterApprox = "tras aprox. %s", vanished = "desapareció del registro de misiones", itemNo = "Objeto n.º %s",
  chosenOf = "%s (1 de %s)", countX = "%s × · %s", moreItems = "+ %s objetos más", choiceItemsUnknown = "No se registraron los objetos entre los que elegir.",
  abandonedN = "%s abandonadas",
  book = "LIBRO DE MISIONES", title = "INK & EMBERS", quests = "MISIONES",
  colName = "Nombre", colArea = "Zona", colLevel = "Nivel", colDate = "Entregada el",
  search = "Buscar nombre …", all = "Todas", sortLbl = "Ordenar y filtrar",
  sortUpTip = "Orden ascendente", sortDownTip = "Orden descendente", clearTip = "Borrar filtro",
  headTip = "Clic: ordenar y filtrar", headTipSort = "Clic: ordenar", filterLbl = "Filtro: ",
  toTable = "Volver a la tabla",
  noMatch = "Ninguna misión coincide con este filtro.",
  sortAsc = "Orden: ascendente", sortDesc = "Orden: descendente",
  goals = "Objetivos", turnIn = "Entrega", life = "Línea de tiempo", rewardHead = "Recompensa",
  noDetail = "No se registró ningún texto de descripción.", noGoals = "No se registraron objetivos.", noReward = "No se registró ningún texto de entrega.",
  emptyHead = "Aún no hay misiones completadas.",
  emptyBody = "En cuanto completes una misión, la crónica la anota aquí. Qué misiones quedan por ahí, lo ves en \"Abiertas\".",
  emptyRight = "La línea de tiempo y las recompensas aparecen con la primera misión completada.",
  accepted = "Aceptada", abandoned = "Abandonada", turned = "Entregada", between = "Por el camino",
  done = "completada",
  stateWord = { done = "completada", open = "abierta", abandoned = "abandonada", seen = "solo leída" },
  xpUnit = "experiencia",
  chosen = "elegida", notChosen = "no elegida", received = "recibida", choiceNotRecorded = "Elección no registrada", fixed = "Recompensa", choice = "a elegir",
  noItems = "sin recompensa de objeto", noRewardData = "ninguna recompensa registrada",
  partial = "Se desconocen las demás recompensas a elegir.",
  speakPlay = "Leer en voz alta (Spoken)", speakStop = "Parar", speakNone = "Sin grabación en Spoken",
  partAccept = "Texto de la misión", partProgress = "Texto de progreso", partComplete = "Texto de entrega",
})

-- journal/pages/Schaetze.lua
L.add("esES", "p.Schaetze", {
  level = "Nivel %s", levels = "Nivel %s–%s", total = "Total %s", gearSub = "%s cambios · nivel 1 a %s", gearSubNone = "Aún ningún cambio · equípate algo nuevo",
  brand = "INK & EMBERS", page = "TESOROS", book = "BOLSA", bag = "EN LA BOLSA",
  ledger = "Libro de cuentas", flow = "Flujo de oro", flowSub = "De dónde vino el oro y adónde fue",
  toBars = "Fuentes", toBand = "Niveles", noMoney = "Aún no se ha movido oro.",
  bagEmpty = "Bolsa vacía",
  ledgerEmpty = "Aún no se ha movido oro. El botín, las recompensas de misión y los vendedores se anotan aquí solos.",
  flowEmpty = "Aún no se ha movido oro. En cuanto tintineen las monedas, aquí verás de dónde vinieron y adónde fueron.",
  gearEmptyHand = "Aún no hay equipo registrado. Con cada pieza que te equipes, la línea de tiempo del nivel 1 al %s crece aquí.",
  qualityEmpty = "Cada hallazgo se cuenta aquí por calidad.",
  flowLevels = "Ingresos y gastos por nivel", income = "Ingresos", expense = "Gastos", net = "Neto",
  toHold = "Fondos", holdTip = "Fondos por nivel", holdTip2 = "La mayor cantidad de oro en la bolsa dentro de cada nivel",
  flowHold = "Mayor cantidad de oro en mano por nivel", holdPeak = "Máximo %s · nivel %s", holdJump = "Mayor salto +%s · nivel %s",
  gear = "Equipo a lo largo del tiempo", gearEmpty = "Aún no hay equipo registrado.", quality = "HALLAZGOS POR CALIDAD",
  incomeBar = "INGRESOS", expenseBar = "GASTOS Y BOLSA", blue = "Primer objeto raro",
  toOverview = "Resumen", overviewTip = "Bolsa, libro de cuentas y flujo de oro",
  toFunde = "Hallazgos de equipo", fundeTip = "Todos los hallazgos de equipo de calidad poco común o superior",
  fundeTipEpic = "Épico cuenta juntos los hallazgos épicos y legendarios.",
  fundeTip2 = "Tabla: de dónde, dónde y en qué nivel",
  toAnprobe = "Viaje de equipo", anprobeTip = "Tu personaje con el equipo de cada nivel",
  anprobeTip2 = "Modelo 3D y línea de tiempo: pruébatelo nivel por nivel",
})

-- journal/pages/SchaetzeAnprobe.lua
L.add("esES", "p.SchaetzeAnprobe", {
  brand = "INK & EMBERS", book = "EQUIPO", page = "VIAJE DE EQUIPO",
  title = "Viaje de equipo", recordFrom = "Registrado desde el nivel %s",
  level = "Nivel %s", startState = "Equipo inicial", noChange = "sin cambios", newPieces = "%s nuevas",
  empty = "Aún no hay equipo registrado.",
  emptyBody = "El viaje de equipo se llena con tu próximo cambio de equipo.",
  slotEmpty = "vacío", itemNo = "Objeto n.º %s", newTag = "nuevo",
  notShown = "No se puede mostrar en el modelo",
  modelCombat = "El modelo aparece después del combate.", modelMissing = "El modelo no se puede mostrar aquí.",
})

-- journal/pages/SchaetzeFunde.lua
L.add("esES", "p.SchaetzeFunde", {
  prevPage = "Página anterior", nextPage = "Página siguiente", clock = "%s", itemNo = "Objeto n.º %s",
  countOf = "%s de %s hallazgos", count_one = "%s hallazgo", count_other = "%s hallazgos",
  brand = "INK & EMBERS", book = "EQUIPO", page = "POCO COMÚN Y SUPERIOR",
  title = "Hallazgos de equipo", sub = "Todo lo de calidad poco común o superior que se puede equipar",
  colItem = "Objeto", colSlot = "Ranura", colLevel = "Nivel", colTime = "Recibido",
  back = "Volver al resumen", all = "Todos", sortLbl = "Ordenar y filtrar", sortOnlyLbl = "Ordenar",
  sortUpTip = "Orden ascendente", sortDownTip = "Orden descendente", clearTip = "Borrar filtro",
  headTip = "Clic: ordenar y filtrar", headTipSort = "Clic: ordenar", headTipZone = "Clic: ordenar, filtrar por zona",
  filterWord = { quality = "Calidad", slot = "Ranura", zone = "Zona" },
  pick = "Elige un hallazgo a la izquierda.", secFound = "Encontrado", secStats = "Atributos", secLine = "Línea de tiempo",
  labWhen = "Cuándo", labWhere = "Dónde", labSource = "Origen", labReplaced = "Reemplazado",
  whenNone = "Hora desconocida", whereNone = "Lugar desconocido", levelWord = "Nivel del personaje ",
  replacedNone = "ningún objeto conocido", replacedEmpty = "nada (la ranura estaba vacía)", notWorn = "no equipado",
  statsHint = "El tooltip muestra los atributos: pasa el ratón sobre el icono.", itemLevelWord = "Nivel de objeto ",
  lineNone = "No hay información de nivel para esta ranura.", lineLevel = "Nivel ",
  lineHead = "Línea de tiempo: ", lineCount = { " hallazgo", " hallazgos" },
  sortAsc = "Orden: ascendente", sortDesc = "Orden: descendente", filterLbl = "Filtro: ",
  empty = "Aún no se ha encontrado equipo poco común o superior.",
  emptyBody = "En cuanto recibas equipo verde o mejor, la crónica lo anota aquí.",
  noMatch = "Ningún hallazgo coincide con este filtro.",
})

-- 1.0.12 data books
L.add("esES", "p.Schaetze", {
  toTrade = "Comercio",
  tradeTip = "Casa de subastas, correo y comercio",
  tradeTip2 = "Cifras de facturas, cartas y comercios",
  tradeSub = "Casa de subastas, correo y comercio",
})

-- change "runde3" (packages A, R, E, L)
-- journal/pages/ChronikVermaechtnis.lua
L.add("esES", "p.ChronikVermaechtnis", {
  challengesHead = "Desafíos", tabClasses = "Clases", pageOf = "Página %s de %s", tipProgress = "Progreso: %s de %s", progress = "%s/%s", colAch = "Desafío", colState = "Estado", colPoints = "Puntos", prevPage = "Página anterior", nextPage = "Página siguiente",
  page = "LEGADO", brand = "INK & EMBERS", title = "Legado",
  subLabel = "Legado", subTip = "Puntos, desafíos de clase, árboles de talentos y recompensas del sistema de legado",
  subTip2 = "Vale para toda tu cuenta; solo WoW Forever",
  points = "Puntos: %s de %s", pointsOnly = "Puntos: %s", pointsMax = "Puntos posibles: %s",
  level = "Senda del legado: nivel %s", levelOf = "Senda del legado: nivel %s de %s",
  classesHead = "Desafíos de clase", tier1 = "Novato", tier2 = "Experto", tier3 = "Maestro",
  date = "{d}/{m}/{y}", doneShort = "hecho", openShort = "abierto",
  tipDone = "Completado el %s", tipDoneNoDate = "Completado", tipOpen = "Aún sin completar", tipPoints_other = "Vale %s puntos",
  tipPoints_one = "Vale %s punto", tipOther = "Conseguido por otro personaje de tu cuenta",
  tipTier = "%s · %s", classesUnreadable = "Los desafíos de clase no se pueden leer ahora mismo.",
  rewardsHead = "Recompensas de la senda", rewardLevel = "Nivel %s", rewardFallback = "Objeto n.º %s", rewardUnknown = "Recompensa",
  collected = "recogida", ready = "lista para recoger", reached = "alcanzado",
  missing_one = "falta %s punto", missing_other = "faltan %s puntos", tipNeed = "Disponible desde el nivel %s de la senda del legado",
  rewardsUnreadable = "Las recompensas no se pueden leer ahora mismo.",
  treesTitle = "Árboles de talentos", tree_professions = "Profesiones", tree_adventure = "Aventura", tree_progression = "Progreso",
  rank = "%s/%s", tipRank = "Rango %s de %s", unknown = "Desconocido", treeUnreadable = "Este árbol no se puede leer ahora mismo.",
  treeEmpty = "No se encontraron nodos.",
  hintCombat = "El libro no lee el legado durante el combate. Vuelve después de la pelea.",
  hintUnreadable = "El legado no se puede leer ahora mismo. Inténtalo de nuevo en un momento.",
  reread = "Leer de nuevo",
  staleCombat = "En combate: estado guardado del {date}", staleUnreadable = "Ahora no se puede leer: estado guardado del {date}",
})

L.add("esES", "p.Schaetze", {
  toAuktion = "Casa de subastas", auktionTip = "Todas las ventas y compras en la casa de subastas",
  auktionTip2 = "Tabla ordenable: fecha, objeto, cantidad y precio",
})

-- journal/pages/SchaetzeAuktion.lua
L.add("esES", "p.SchaetzeAuktion", {
  brand = "INK & EMBERS", book = "CASA DE SUBASTAS", page = "BALANCE",
  title = "Casa de subastas", count_one = "%s factura", count_other = "%s facturas", countOf = "%s de %s facturas",
  prevPage = "Página anterior", nextPage = "Página siguiente",
  colTime = "Fecha", colKind = "Tipo", colItem = "Objeto", colCount = "Cant.", colPrice = "Total", colUnit = "Unidad",
  fAll = "Todo", fSold = "Ventas", fBought = "Compras",
  fAllTip = "Todas las facturas", fSoldTip = "Solo ventas", fBoughtTip = "Solo compras",
  sortAsc = "Orden: ascendente", sortDesc = "Orden: descendente", headTip = "Clic: ordenar, otro clic: invertir",
  tipCount = "Cantidad: %s", tipTotal = "Precio total: %s", tipUnit = "Por unidad: %s", tipFee = "Comisión: %s", tipNoPrice = "Precio no legible",
  empty = "Aún no hay ninguna factura de la casa de subastas.",
  emptyBody = "En cuanto vacíes tu buzón y haya facturas de ventas o compras, la crónica las anotará aquí.",
  noMatch = "Ninguna factura coincide con este filtro.",
  balTitle = "Balance", balSub = "Todas las facturas, sin importar el filtro",
  secSold = "Ventas", secBought = "Compras", secSaldo = "Resultado final",
  labSoldN = "Objetos vendidos", labIncome = "Ingresos", labFee = "Comisión", labBoughtN = "Objetos comprados", labSpent = "Gastos",
  labSaldo = "Saldo", saldoPlus = "Ingresado más de lo gastado", saldoMinus = "Gastado más de lo ingresado", saldoZero = "Equilibrado",
  balNote = "Se basa en las facturas de tu buzón. Las pujas, los depósitos y las subastas caducadas no aparecen en ninguna factura.",
  noPrice = "–",
})

