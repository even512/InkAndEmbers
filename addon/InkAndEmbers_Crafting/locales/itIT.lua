-- Italian strings of the module InkAndEmbers_Crafting (moved from the core locales in 1.1.0 by scripts/split-locales.mjs).
-- One L.add block per area, same keys as L.ns in the module's code (deDE is the source in the code).
local _, ns = ...
local L = ns.Locale

-- journal/model/Rezepte.lua and Handwerk.lua (1.0.12 data books)
L.add("itIT", "m.Rezepte", {
  spellFallback = "Ricetta %s",
  profFallback = "Professione %s",
  rankJ = "Garzone", rankE = "Esperto", rankA = "Artigiano",
  srcT = "Istruttore", srcV = "Venditore", srcQ = "Missione", srcD = "Bottino", srcC = "Creazione", srcO = "Ritrovamento",
  favor = "%s Favore del mercante",
  repText = "Reputazione: %s",
  repFallback = "Reputazione con una fazione",
  NO_RECIPES = "Elenco delle ricette mancante nell'add-on dei dati (reinstallalo)",
  NO_API = "Le professioni non sono leggibili al momento",
})

L.add("itIT", "m.Handwerk", {
  rank_75 = "Apprendista", rank_150 = "Garzone", rank_225 = "Esperto", rank_300 = "Artigiano",
})

L.add("itIT", "m.Rezeptbuch", {
  profFallback = "Professione %s",
  recipeFallback = "Ricetta %s",
  diff_orange = "ottimale", diff_yellow = "media", diff_green = "facile", diff_grey = "nessun avanzamento",
})

L.add("itIT", "p.Handwerk", {
  brand = "INK & EMBERS", book = "PROFESSIONI", page = "MESTIERI", title = "Mestieri",
  prof_one = "%s professione", prof_other = "%s professioni", rec_one = "%s ricetta", rec_other = "%s ricette",
  listHead = "PROFESSIONI",
  listEmpty = "Nessuna professione ancora imparata. Appena ne impari una, la sua curva si scrive qui da sola.",
  primary = "Professione principale", secondary = "Professione secondaria",
  skillOf = "%s / %s",
  skillNow = "Abilità %s su %s", skillRank = "%s · %s",
  balance = "BILANCIO",
  mined = "estratto", picked = "raccolto", skinned = "scuoiato", fished = "pescato", crafted = "creato",
  minedTip = "Minerali e pietra dai filoni", pickedTip = "Erbe e fiori dalle piante",
  skinnedTip = "Cuoio e pelli dai nemici (stimati dai ritrovamenti)", fishedTip = "Tutto ciò che è finito all'amo",
  craftedTip = "Oggetti che hai creato tu stesso, compresi quelli sotto la qualità Non comune",
  balanceEmpty = "Ancora nulla raccolto o creato.",
  firstCraft = "Prima creazione", firstCraftTip = "Il primo oggetto che hai creato tu stesso, dalla qualità Non comune",
  level = "Livello %s",
  curveHead = "ABILITÀ NEL TEMPO DI GIOCO", recipesHead = "Ricette imparate",
  hours = "%s h", minutes = "%s min",
  open = "non ancora", milestoneTip = "Abilità %s raggiunta",
  tipSkill = "Abilità %s su %s", tipLearned = "Imparata al livello %s", tipLast = "Ultimo aumento: %s",
  tipWhen = "%s · Livello %s", tipPlay = "Dopo %s di tempo di gioco",
  noRecipes = "Nessuna ricetta ancora imparata.",
  recipesUnsure = "Le ricette di questa professione non si possono assegnare con certezza. Le trovi tutte nel libro delle ricette.",
  emptyTitle = "Il libro dei mestieri è ancora vuoto",
  emptyBody = "Impara una professione, e ogni punto abilità, ogni ricetta e ogni traguardo si scrive qui da solo.",
  date = "{d}/{m}/{y}",
})

L.add("itIT", "p.PlaeneHandwerk", {
  brand = "INK & EMBERS", page = "MESTIERI",
  fTrainer = "Istruttore", fNow = "Ora", fSoon = "Presto",
  fTrainerTip = { "Istruttore", "Cosa ti insegna subito un istruttore di professione" },
  fNowTip = { "Ora", "Tutto ciò che puoi imparare con la tua abilità, inclusi venditori, missioni e bottino" },
  fSoonTip = { "Presto", "Cosa aggiungono i prossimi 25 punti abilità" },
  info = "Professioni: %s · %s ora · %s presto",
  skillWord = "Abilità %s",
  free = "gratis",
  sNow = "ora", sSoon = "tra %s punti", sLevel = "dal livello %s", sLater = "dall'abilità %s", sLearned = "imparata",
  learnable = "imparabile dall'istruttore",
  costLine = "Costo dell'addestramento %s · nelle tue borse %s",
  costNone = "Al momento l'istruttore di professione non ha nulla di nuovo per te.",
  short = "Ti mancano ancora %s.", enough = "Le tue borse coprono tutto.",
  profHead = "Le tue professioni",
  profLine = "%s %s/%s · %s ora · %s presto",
  profLineNoMax = "%s %s · %s ora · %s presto",
  todoOn = "La voce «Dall'istruttore di professione» è nella tua lista.",
  todoOff = "Appena un istruttore avrà qualcosa di nuovo per te, Ink aggiunge «Dall'istruttore di professione» alla tua lista.",
  retailHead = "Solo WoW Forever",
  retailBody = "I dati delle ricette sono di WoW Forever. Questa pagina resta vuota su Retail.",
  noDataHead = "Nessun dato sulle ricette",
  noProfHead = "Ancora nessuna professione",
  noProfBody = "Impara una professione. Questa pagina mostra poi quali ricette arrivano dopo.",
  noProfDataHead = "Nessuna ricetta per le tue professioni",
  noProfDataBody = "Non ci sono dati sulle ricette per le tue professioni.",
  noApiBody = "Le tue professioni non sono leggibili al momento. Riprova tra un istante.",
  emptyTrainer = "Al momento l'istruttore di professione non ha nulla di nuovo. Più abilità porta nuove ricette.",
  emptyNow = "Al momento non c'è nulla da imparare.",
  emptySoon = "Niente di nuovo nei prossimi 25 punti.",
  prevPage = "Pagina precedente", nextPage = "Pagina successiva",
  tipSource = "Fonte: %s", tipCost = "Prezzo: %s", tipLevel = "Richiede il livello %s", tipRank = "Grado della professione: %s",
  tipFavor = "Favore del mercante: %s", tipNeed = "Ancora %s punti abilità",
})

L.add("itIT", "p.Handwerk", {
  subBerufe = "Professioni", subBerufeTip = "Curva dell'abilità, traguardi e bilancio delle tue professioni",
  subRezept = "Libro delle ricette", subRezeptTip = "Tutte le ricette delle tue professioni, imparate e ancora aperte, con i materiali (solo WoW Forever)",
})

-- journal/pages/HandwerkRezeptbuch.lua (change "runde3", package R)
L.add("itIT", "p.HandwerkRezeptbuch", {
  brand = "INK & EMBERS", book = "LIBRO DELLE RICETTE", page = "MESTIERI",
  title = "Libro delle ricette", sub = "Tutte le ricette delle tue professioni, imparate e ancora aperte",
  listHead = "PROFESSIONI", recipesHead = "RICETTE",
  fAll = "Tutte", fLearned = "Imparate", fOpen = "Aperte",
  fAllTip = { "Tutte", "Ricette imparate e non ancora imparate" },
  fLearnedTip = { "Imparate", "Solo le ricette che conosci già" },
  fOpenTip = { "Aperte", "Solo le ricette che ti mancano ancora" },
  profSub = "Abilità %s su %s", profSubNoMax = "Abilità %s",
  profCount = "%s su %s", profNoCount = "–",
  countLine = "%s imparate · %s aperte",
  hintNoCache = "Apri una volta la finestra della professione, così il libro conosce ogni dettaglio.",
  hintCache = "Come all'ultima apertura della finestra della professione. Le ricette appena imparate compaiono quando la riapri.",
  legend = "Colore:",
  learned = "imparata", open = "aperta", fromSkill = "da %s",
  skillWord = "Abilità %s",
  tipSource = "Fonte: %s", tipDifficulty = "Difficoltà: %s", tipUps = "Punti abilità per creazione: fino a %s",
  tipCost = "Prezzo: %s", tipStock = "Nelle borse: %s · Banca: %s",
  tipNeeds = "Richiede: %s", tipMore = "Clic: dettagli sotto",
  needs = "RICHIEDE", output = "Crea: %s", outputQty = "Crea: %s× %s",
  noMats = "Questa ricetta non richiede materiali.",
  detailNoCache = "Il libro conosce il risultato e i materiali solo dopo che hai aperto la finestra della professione.",
  moreMats = "… e altri %s",
  itemNo = "Oggetto n. %s",
  pick = "Scegli una ricetta.",
  emptyList = "Per questa professione non ci sono ancora ricette.",
  emptyFilterLearned = "Ancora nessuna ricetta imparata.", emptyFilterOpen = "Tutte le ricette di questa professione sono imparate.",
  noProfTitle = "Ancora nessuna professione con ricette",
  noProfBody = "Impara una professione. Questa pagina mostrerà poi tutte le sue ricette, imparate e aperte.",
  prevPage = "Pagina precedente", nextPage = "Pagina successiva",
})

-- journal/WerkBarKit.lua (Werkauftrag, 1.1.0)
L.add("itIT", "WerkBarKit", {
  stepPlan = "Pianificare",
  stepBuy = "Acquistare",
  stepMake = "Creare",
  afterCombat = "Dopo il combattimento",
  goldShort = "Vi mancano %s",
  busy = "Un momento …",
})
