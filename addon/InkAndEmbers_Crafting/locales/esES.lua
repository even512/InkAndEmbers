-- Spanish strings of the module InkAndEmbers_Crafting (moved from the core locales in 1.1.0 by scripts/split-locales.mjs).
-- One L.add block per area, same keys as L.ns in the module's code (deDE is the source in the code).
local _, ns = ...
local L = ns.Locale

-- journal/model/Rezepte.lua and Handwerk.lua (1.0.12 data books)
L.add("esES", "m.Rezepte", {
  spellFallback = "Receta %s",
  profFallback = "Profesión %s",
  rankJ = "Oficial", rankE = "Experto", rankA = "Artesano",
  srcT = "Instructor", srcV = "Vendedor", srcQ = "Misión", srcD = "Botín", srcC = "Fabricación", srcO = "Hallazgo",
  favor = "%s Favor del mercader",
  repText = "Reputación: %s",
  repFallback = "Reputación con una facción",
  NO_RECIPES = "Falta la lista de recetas en el addon de datos (reinstálalo)",
  NO_API = "Las profesiones no se pueden leer ahora mismo",
})

L.add("esES", "m.Handwerk", {
  rank_75 = "Aprendiz", rank_150 = "Oficial", rank_225 = "Experto", rank_300 = "Artesano",
})

L.add("esES", "m.Rezeptbuch", {
  profFallback = "Profesión %s",
  recipeFallback = "Receta %s",
  diff_orange = "óptima", diff_yellow = "media", diff_green = "fácil", diff_grey = "sin avance",
})

L.add("esES", "p.Handwerk", {
  brand = "INK & EMBERS", book = "PROFESIONES", page = "OFICIOS", title = "Oficios",
  prof_one = "%s profesión", prof_other = "%s profesiones", rec_one = "%s receta", rec_other = "%s recetas",
  listHead = "PROFESIONES",
  listEmpty = "Aún no has aprendido ninguna profesión. En cuanto aprendas una, su curva se escribirá aquí sola.",
  primary = "Profesión principal", secondary = "Profesión secundaria",
  skillOf = "%s / %s",
  skillNow = "Habilidad %s de %s", skillRank = "%s · %s",
  balance = "BALANCE",
  mined = "extraído", picked = "recolectado", skinned = "desollado", fished = "pescado", crafted = "fabricado",
  minedTip = "Mineral y piedra de los filones", pickedTip = "Hierbas y flores de las plantas",
  skinnedTip = "Cuero y pieles de enemigos (estimado a partir de los hallazgos)", fishedTip = "Todo lo que picó en el anzuelo",
  craftedTip = "Objetos que has fabricado tú mismo, incluidos los de calidad inferior a Poco común",
  balanceEmpty = "Aún no se ha recolectado ni fabricado nada.",
  firstCraft = "Primera fabricación", firstCraftTip = "El primer objeto que fabricaste tú mismo, desde la calidad Poco común",
  level = "Nivel %s",
  curveHead = "HABILIDAD SEGÚN EL TIEMPO DE JUEGO", recipesHead = "Recetas aprendidas",
  hours = "%s h", minutes = "%s min",
  open = "aún no", milestoneTip = "Habilidad %s alcanzada",
  tipSkill = "Habilidad %s de %s", tipLearned = "Aprendida en el nivel %s", tipLast = "Última subida: %s",
  tipWhen = "%s · Nivel %s", tipPlay = "Tras %s de tiempo de juego",
  noRecipes = "Aún no has aprendido ninguna receta.",
  recipesUnsure = "Las recetas de esta profesión no se pueden asignar con seguridad. Las encontrarás todas en el libro de recetas.",
  emptyTitle = "El libro de oficios aún está vacío",
  emptyBody = "Aprende una profesión y cada punto de habilidad, cada receta y cada hito se anotará aquí solo.",
  date = "{d}/{m}/{y}",
})

L.add("esES", "p.PlaeneHandwerk", {
  brand = "INK & EMBERS", page = "OFICIOS",
  fTrainer = "Instructor", fNow = "Ahora", fSoon = "Pronto",
  fTrainerTip = { "Instructor", "Lo que un instructor de profesión te enseña ahora mismo" },
  fNowTip = { "Ahora", "Todo lo que puedes aprender con tu habilidad, incluidos vendedores, misiones y botín" },
  fSoonTip = { "Pronto", "Lo que aportan los próximos 25 puntos de habilidad" },
  info = "Profesiones: %s · %s ahora · %s pronto",
  skillWord = "Habilidad %s",
  free = "gratis",
  sNow = "ahora", sSoon = "en %s puntos", sLevel = "desde el nivel %s", sLater = "desde habilidad %s", sLearned = "aprendida",
  learnable = "aprendible con el instructor",
  costLine = "Coste de entrenamiento %s · en tus bolsas %s",
  costNone = "El instructor de profesión no tiene nada nuevo para ti por ahora.",
  short = "Aún te faltan %s.", enough = "Tus bolsas cubren todo.",
  profHead = "Tus profesiones",
  profLine = "%s %s/%s · %s ahora · %s pronto",
  profLineNoMax = "%s %s · %s ahora · %s pronto",
  todoOn = "La tarea «Al instructor de profesión» está en tu lista.",
  todoOff = "En cuanto un instructor tenga algo nuevo para ti, Ink añade «Al instructor de profesión» a tu lista de tareas.",
  retailHead = "Solo WoW Forever",
  retailBody = "Los datos de recetas son de WoW Forever. Esta hoja queda vacía en Retail.",
  noDataHead = "Sin datos de recetas",
  noProfHead = "Aún sin profesión",
  noProfBody = "Aprende una profesión. Esta hoja mostrará entonces qué recetas vienen después.",
  noProfDataHead = "Sin recetas para tus profesiones",
  noProfDataBody = "No hay datos de recetas para tus profesiones.",
  noApiBody = "Tus profesiones no se pueden leer ahora mismo. Inténtalo de nuevo en un momento.",
  emptyTrainer = "El instructor de profesión no tiene nada nuevo por ahora. Más habilidad trae nuevas recetas.",
  emptyNow = "Ahora mismo no hay nada que aprender.",
  emptySoon = "Nada nuevo en los próximos 25 puntos.",
  prevPage = "Página anterior", nextPage = "Página siguiente",
  tipSource = "Origen: %s", tipCost = "Precio: %s", tipLevel = "Requiere nivel %s", tipRank = "Rango de la profesión: %s",
  tipFavor = "Favor del mercader: %s", tipNeed = "%s puntos de habilidad más",
})

L.add("esES", "p.Handwerk", {
  subBerufe = "Profesiones", subBerufeTip = "Curva de habilidad, hitos y balance de tus profesiones",
  subRezept = "Libro de recetas", subRezeptTip = "Todas las recetas de tus profesiones, aprendidas y aún abiertas, con materiales (solo WoW Forever)",
})

-- journal/pages/HandwerkRezeptbuch.lua (change "runde3", package R)
L.add("esES", "p.HandwerkRezeptbuch", {
  brand = "INK & EMBERS", book = "LIBRO DE RECETAS", page = "OFICIOS",
  title = "Libro de recetas", sub = "Todas las recetas de tus profesiones, aprendidas y aún abiertas",
  listHead = "PROFESIONES", recipesHead = "RECETAS",
  fAll = "Todas", fLearned = "Aprendidas", fOpen = "Abiertas",
  fAllTip = { "Todas", "Recetas aprendidas y aún no aprendidas" },
  fLearnedTip = { "Aprendidas", "Solo las recetas que ya conoces" },
  fOpenTip = { "Abiertas", "Solo las recetas que aún te faltan" },
  profSub = "Habilidad %s de %s", profSubNoMax = "Habilidad %s",
  profCount = "%s de %s", profNoCount = "–",
  countLine = "%s aprendidas · %s abiertas",
  hintNoCache = "Abre una vez tu ventana de profesión para que el libro conozca todos los detalles.",
  hintCache = "Según la última vez que abriste la ventana de profesión. Las recetas recién aprendidas aparecen al abrirla de nuevo.",
  legend = "Color:",
  learned = "aprendida", open = "abierta", fromSkill = "desde %s",
  skillWord = "Habilidad %s",
  tipSource = "Origen: %s", tipDifficulty = "Dificultad: %s", tipUps = "Puntos de habilidad por fabricación: hasta %s",
  tipCost = "Precio: %s", tipStock = "En las bolsas: %s · Banco: %s",
  tipNeeds = "Necesita: %s", tipMore = "Clic: detalles abajo",
  needs = "NECESITA", output = "Fabrica: %s", outputQty = "Fabrica: %s× %s",
  noMats = "Esta receta no necesita materiales.",
  detailNoCache = "El libro solo conoce el resultado y los materiales después de que hayas abierto tu ventana de profesión.",
  moreMats = "… y %s más",
  itemNo = "Objeto n.º %s",
  pick = "Elige una receta.",
  emptyList = "Aún no hay recetas para esta profesión.",
  emptyFilterLearned = "Aún no has aprendido ninguna receta.", emptyFilterOpen = "Todas las recetas de esta profesión están aprendidas.",
  noProfTitle = "Aún no hay profesión con recetas",
  noProfBody = "Aprende una profesión. Esta hoja mostrará entonces todas sus recetas, aprendidas y abiertas.",
  prevPage = "Página anterior", nextPage = "Página siguiente",
})

-- journal/WerkBarKit.lua (Werkauftrag, 1.1.0)
L.add("esES", "WerkBarKit", {
  stepPlan = "Planificar",
  stepBuy = "Comprar",
  stepMake = "Fabricar",
  afterCombat = "Después del combate",
  goldShort = "Os faltan %s",
  busy = "Un momento …",
})
