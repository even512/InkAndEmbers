-- Testi in italiano per journal/pages/*.lua. Un blocco L.add per modulo, con le stesse chiavi di L.ns.
local _, ns = ...
local L = ns.Locale

-- journal/pages/Chronik.lua
L.add("itIT", "p.Chronik", {
  ofSeals = "%s di %s", longest = "più lungo: %s", noLevel = "%s senza livello", pageOf = "Pagina %s di %s",
  brand = "INK & EMBERS", profile = "PROFILO", page = "CRONACA", traveller = "VIANDANTE", travellerM = "VIANDANTE", travellerF = "VIANDANTE",
  standDate = "Stato al %s", standXp = "Stato al %s · %s", standFmt = "%d/%m/%Y",
  since = "In cammino dal", played = "Tempo di gioco totale", perDay = "Media per giorno di gioco", sessions = "Sessioni", entries = "Eventi registrati",
  seals = "MEDAGLIE DEL VIAGGIO", flow = "Andamento dei livelli", flowSub = "Quanto è durato ogni livello",
  legend = "punti rossi = morto", xpTotal = "ESPERIENZA TOTALE", sources = "FONTI DI ESPERIENZA",
  noXp = "Ancora nessuna esperienza guadagnata.", diaryEmpty = "Ancora nulla vissuto – il diario aspetta.",
  diaryNone = "Dal diario", ofMax = "DI %s", ringStart = "Si parte!", prevTip = "Giorno precedente", nextTip = "Giorno successivo",
  toDiary = "Diario", toDiaryTip = "Leggi il diario", toDiaryTip2 = "Ogni giorno di gioco come una voce, giorno per giorno",
  toMates = "Compagni", toMatesTip = "Guarda i compagni", toMatesTip2 = "Chi ha viaggiato con te",
  toProfile = "Profilo", toProfileTip = "Profilo, andamento dei livelli ed estratto del diario",
  toMilestones = "Tappe", toMilestonesTip = "Guarda le tappe", toMilestonesTip2 = "Ogni dieci livelli un bilancio del viaggio, al livello 60 la pagina finale",
  toRecap = "Prima, nel tuo viaggio", toRecapTip = "Vedi il riepilogo", toRecapTip2 = "Cosa è successo di recente e cosa viene dopo",
})

-- journal/pages/ChronikViews.lua
L.add("itIT", "p.ChronikViews.Diary", {
  page = "DIARIO", brand = "INK & EMBERS", prevTip = "Un giorno indietro", nextTip = "Un giorno avanti",
  empty = "Ancora nessuna voce", emptyBody = "Appena ti metti in cammino, ogni giorno qui si scrive da solo una voce.",
  blank = "La prossima pagina è ancora bianca.", blankBody = "Quello che accadrà domani comparirà qui una volta accaduto.",
  dayPair = "Giorni %s e %s di %s", dayOne = "Giorno 1 di 1",
})
L.add("itIT", "p.ChronikViews.Switch", {
  group = "Gruppo", fire = "Accanto al fuoco", groupTip = "Compagni del tuo gruppo", fireTip = "Chi si è seduto con te al falò",
})
L.add("itIT", "p.ChronikViews.Mates", {
  levelRange = "Livello da %s a %s", level = "Livello %s", date = "{d}/{m}/{y}", togetherFmt = "%s insieme",
  quests_one = "%s missione", quests_other = "%s missioni", kills_one = "%s uccisione", kills_other = "%s uccisioni",
  firstMet = "incontrato la prima volta a %s il %s", pageOf = "Pagina %s di %s", persons_one = "%s persona", persons_other = "%s persone",
  classes = {
    WARRIOR = "Guerriero", PALADIN = "Paladino", HUNTER = "Cacciatore", ROGUE = "Ladro", PRIEST = "Sacerdote", DEATHKNIGHT = "Cavaliere della Morte",
    SHAMAN = "Sciamano", MAGE = "Mago", WARLOCK = "Stregone", MONK = "Monaco", DRUID = "Druido", DEMONHUNTER = "Cacciatore di Demoni",
    EVOKER = "Evocatore",
  },
  races = {
    Human = "Umano", Orc = "Orco", Dwarf = "Nano", NightElf = "Elfo della Notte", Scourge = "Non Morto", Tauren = "Tauren", Gnome = "Gnomo",
    Troll = "Troll", Goblin = "Goblin", BloodElf = "Elfo del Sangue", Draenei = "Draenei", Worgen = "Worgen", Pandaren = "Pandaren",
    Dracthyr = "Dracthyr", EarthenDwarf = "Terrigeno", VoidElf = "Elfo del Vuoto", Nightborne = "Nobile Oscuro",
    HighmountainTauren = "Tauren di Alto Monte", LightforgedDraenei = "Draenei Forgialuce", ZandalariTroll = "Troll Zandalari",
    KulTiran = "Kul Tirano", DarkIronDwarf = "Nano Ferroscuro", Vulpera = "Vulpera", MagharOrc = "Orco Mag'har", Mechagnome = "Meccagnomo",
  },
  page = "COMPAGNI", brand = "INK & EMBERS", title = "Compagni", empty = "Ancora in viaggio da solo.",
  emptyBody = "Chiunque viaggi con te in gruppo viene registrato qui.", sortRecent = "recenti", sortLong = "più a lungo",
  sortRecentTip = "Prima quelli incontrati più di recente", sortLongTip = "Prima chi è stato insieme più a lungo", pick = "Clicca su un nome per i dettagli.",
  prevTip = "Pagina precedente", nextTip = "Pagina successiva",
  truncated = "Moltissimi incontri: quelli più vecchi non sono più completi.", now = "nel tuo gruppo in questo momento",
  first = "Primo incontro", last = "Visto l'ultima volta", together = "Tempo insieme", sessions = "Sessioni condivise",
  quests = "Missioni condivise", kills = "Uccisioni condivise", deaths = "Morti proprie nel frattempo", unknownZone = "un luogo sconosciuto",
  zones = "Luoghi condivisi", lastQuests = "Ultime fatte insieme", noQuests = "Ancora nessuna missione consegnata insieme.",
})
-- journal/pages/ChronikDungeons.lua
L.add("itIT", "p.ChronikDungeons", {
  page = "SPEDIZIONI", brand = "INK & EMBERS", title = "Spedizioni", empty = "Ancora nessuna spedizione visitata.",
  emptyBody = "Appena entri in una spedizione, il libro registra ogni percorso: quando, quanto è durato, con chi, i boss, le morti e il bottino.",
  pick = "Clicca su un percorso per i dettagli.", prevTip = "Pagina precedente", nextTip = "Pagina successiva", pageOf = "Pagina %s di %s",
  runs_one = "%s percorso", runs_other = "%s percorsi", truncated = "Moltissimi percorsi: quelli più vecchi non sono elencati.",
  date = "{d}/{m}/{y}", dateShort = "{d}/{m}",
  bosses_one = "%s boss sconfitto", bosses_other = "%s boss sconfitti", complete = "completata", live = "in corso",
  endUnknown = "fine sconosciuta", deaths_one = "%s morte", deaths_other = "%s morti", noDeaths = "nessuna morte",
  unknownInstance = "Spedizione sconosciuta", unknownBoss = "Boss sconosciuto",
  when = "Quando", duration = "Durata", level = "Livello", kills = "Uccisioni", xp = "Esperienza",
  visits_one = "%s ingresso nell'istanza", visits_other = "%s ingressi nell'istanza", lv = "Livello %s", levelRange = "Livello da %s a %s",
  you = "Tu", roll_need = "Necessità", roll_greed = "Cupidigia", roll_de = "Disincanta", roll_tmog = "Trasmogrificazione",
  whenSame = "{date}, {from}–{to}", whenOther = "{from} – {to}", whenLive = "{date}, dalle {from}",
  secBosses = "Boss", secBossesN = "Boss · %s sconfitti", secBossesOf = "Boss · %s di %s sconfitti",
  secGroup = "Gruppo", secDeaths = "Morti", secLoot = "Ritrovamenti (verdi e superiori)", secQuests = "Missioni",
  tries_one = "%s tentativo fallito", tries_other = "%s tentativi falliti", bossWon = "sconfitto", bossNot = "non sconfitto",
  bossCountOnly = "Il client non ha comunicato gli scontri coi boss, si conosce solo il numero.",
  noGroup = "Nessun membro del gruppo registrato.",
  cause_enemy = "per mano di un nemico", cause_fall = "per una caduta", cause_drown = "per annegamento", cause_fatigue = "per sfinimento",
  cause_lava = "nella lava", cause_fire = "nel fuoco", cause_slime = "nella melma", cause_environment = "per l'ambiente",
  byFoe = "per mano di %s", guess = "%s (presunto)", died = "morto", more = "… e altri %s",
  questDone = "consegnata", questTaken = "accettata", questFallback = "Missione n. %s", itemFallback = "Oggetto n. %s",
  xpUnit = "%s esperienza", reward = "Ricompensa: %s", groupTip = "Gruppo",
})

-- journal/pages/ChronikMeilensteine.lua
L.add("itIT", "p.ChronikMeilensteine", {
  page = "TAPPE", brand = "INK & EMBERS", title = "Tappe",
  reachedOf = "%s di %s raggiunte", range = "Livello %s–%s", final = "La fine del viaggio", finalSub = "L'intero viaggio · livello 1–%s",
  date = "{d}/{m}/{y}", dateRange = "{from} – {to}", running = "in corso", runningSince = "in corso dal {date}", open = "non ancora raggiunta",
  before = "prima della registrazione", noRecord = "nulla registrato", soFar = "%s finora", reachedIn = "raggiunta in %s",
  openBody = "Non hai ancora raggiunto questa tappa. Appena raggiungi il livello, il narratore ne tira qui le somme.",
  beforeBody = "Per questo tratto non c'è alcuna registrazione: il libro scrive solo dal livello %s in poi.",
  emptyBody = "Per questo tratto non è registrato nulla.",
  truncated = "Un viaggio lunghissimo: le righe più vecchie sono tagliate, i numeri sono minimi.",
  kTime = "Tempo (senza AFK)", kZones = "Nuove zone", kKills = "Uccisioni", kQuests = "Missioni", kDeaths = "Morti", kDungeons = "Spedizioni",
  kBest = "Ritrovamento migliore", kDays = "Giorni di gioco", kSeals = "Medaglie", kTotal = "Tempo totale (senza AFK)",
  noDeaths = "nessuna morte", runs_one = "%s percorso", runs_other = "%s percorsi", bosses_one = "%s boss", bosses_other = "%s boss",
  sealsOf = "%s di %s", about = "circa %s", roughly = "circa %s", atLeast = "almeno %s",
  colsHead = "Tempo per tratto", colDur = "%s:%s h", colTip = "Livello %s–%s", colUnknown = "Tempo sconosciuto", itemFallback = "Oggetto n. %s",
  zonesMore = "… e altre %s",
})

-- journal/pages/Kampf.lua
L.add("itIT", "p.Kampf", {
  pageOf = "Pagina %s di %s", deathOf = "Morte %s di %s", moreZones = "+ altre %s zone", closeCount = "%s vittorie di misura · %s",
  brand = "INK & EMBERS", page = "BESTIARIO", right = "COMBATTIMENTO", hunted = "I PIÙ CACCIATI", rare = "NEMICO RARO",
  zoneLabel = "ZONA",
  graves = "DOVE SONO MORTO", gravesTip = "Zone in cui sei morto – una lapide per ogni morte",
  close = "PER UN SOFFIO", prevDeath = "Morte precedente", openDeath = "Clic: rapporto di questa morte",
  openLastDeath = "Clic: rapporto dell'ultima morte qui", deathNo = "Morte %s",
  nextDeath = "Morte successiva", prevCards = "Nemici precedenti", nextCards = "Altri nemici",
  hintHunted = "Abbatti un nemico e comparirà qui.", hintHuntedZone = "Abbatti un nemico qui e comparirà in questa lista.",
  hintGraves = "Ogni morte ottiene qui una lapide.", hintClose = "Vinci uno scontro con pochi punti ferita e comparirà qui.",
  hintZone = "Abbatti un nemico e le tue terre di caccia prendono forma.",
  zoneEmpty = "Ancora nessuna zona con uccisioni.", krit = "critico", unknownPic = "?", here = "qui",
  lowGraves = "Morti", lowClose = "Vittorie di misura", backToGraves = "Torna alle morti",
  noDeathTitle = "L'ultimo respiro",
  modeHot = "Punti caldi", modePoints = "Esatto",
  modeHotTip = "Punti caldi: una macchia per ogni cella della griglia, più grande e più scura con più uccisioni",
  modePointsTip = "Esatto: ogni punto è un nemico abbattuto (campione delle uccisioni più recenti)",
  mapHint = "Rotella del mouse: zoom · Trascina: sposta · Doppio clic: ripristina",
  hotspot = "Punto caldo", killsWord = "%s · %s uccisioni", onePoint = "Punto di uccisione", pointsHere = "%s uccisioni qui",
  sample = "Campione: le ultime %s di %s uccisioni in questa zona",
  openLens = "Clic: guarda il modello da vicino", lensHint = "Trascina: ruota · Rotella del mouse: zoom · Esc o clic all'esterno: chiudi",
  lowGravesTip = "Dove sono morto: zone con una lapide per ogni morte (clic su una lapide: rapporto della morte)",
  lowCloseTip = "Le vittorie di misura più risicate",
  huntedTip = "Scegli una zona – l'intera pagina mostra poi solo questa zona (all'apertura: la tua zona attuale)",
})

-- journal/pages/Momente.lua
L.add("itIT", "p.Momente", {
  level = "Livello %s", day = "Giorno %s", readAt = "Letto: %s", ofWhich = "di cui %s", hour = "%s:00",
  brand = "INK & EMBERS", page = "MOMENTI", moment = "momento", moments = "momenti",
  kept = "registrati", zoneOne = "nuova zona", zonesOf = "nuove zone", prevTip = "Momenti più recenti", nextTip = "Momenti più vecchi", pageOf = "Pagina %d di %d",
  emptyHead = "Ancora nessun momento incollato.", emptyBody = "Livelli, nemici rari, primi ritrovamenti e luoghi nuovi finiscono qui nell'album.",
  emptyFilter = "In questo gruppo non è ancora stato incollato nulla.",
  unreadable = "Voce non leggibile",
  filters = { all = "Tutti", levels = "Livelli", fights = "Scontri", finds = "Ritrovamenti", places = "Luoghi" },
  clock = "TEMPO DI GIOCO PER ORA DEL GIORNO", fav = "Ora preferita", longest = "Sessione più lunga", sessions = "Sessioni",
  interrupted = "interrotta", noClock = "Ancora nessun tempo di gioco registrato.",
  noClockHand = "Presto l'orologio mostrerà in quale ora del giorno ti piace viaggiare di più.",
  jumpFirst = "Maiusc+clic: al foglio più recente", jumpLast = "Maiusc+clic: al foglio più vecchio",
  library = "BIBLIOTECA", libEmpty = "Ancora nessun libro letto.", book = "libro", books = "libri", pageW = "pagina", pagesW = "pagine",
  readPages = "lette", curios = "CURIOSITÀ", curiosEmpty = "Ancora nulla di curioso vissuto.",
  back = "Torna all'album", pagePrev = "Pagina precedente", pageNext = "Pagina successiva", pageGone = "Questa pagina non è leggibile.",
})

-- journal/pages/Notizen.lua (le scorciatoie di formattazione restano com'è)
L.add("itIT", "p.Notizen", {
  inkTip = "Inchiostro: %s", inkInsert = "Inserisce {%s}…{/}.", symInsert = "Inserisce {%s}.", reopen = "Riapri", tick = "Spunta",
  whenFmt = "%d/%m %H:%M",
  brand = "INK & EMBERS", page = "NOTE",
  note = "nota", notes = "note", pinnedN = "%d fissate", lastEdit = "ultima %s",
  pageOf = "Pagina %d di %d", prevTip = "Pagina precedente", nextTip = "Pagina successiva",
  sortNew = "Prima le più recenti", sortOld = "Prima le più vecchie", sortTitle = "Per titolo",
  sortTip = { "Ordinamento", "Le note fissate restano sempre in cima." },
  searchHint = "Cerca nel titolo e nel testo …", searchClear = "Cancella la ricerca",
  newNote = "Nuova nota", newTip = { "Nuova nota", "Crea una nota con il luogo, il livello e l'ora attuali." },
  untitled = "Senza titolo", emptyList = "Ancora nessuna nota.", emptyListBody = "Usa “Nuova nota” qui sotto per creare la prima.",
  noMatch = "Nessuna nota corrisponde alla ricerca.", noChar = "Per questo personaggio non c'è ancora una cronaca.",
  pickNote = "Scegli una nota a sinistra oppure creane una nuova.",
  edit = "Modifica", read = "Leggi", editTip = { "Modifica", "Scrivi testo con la formattazione (si salva da solo)." },
  readTip = { "Leggi", "Mostra la nota formattata; le caselle si possono cliccare." },
  pin = "Fissata", pinTip = { "Fissa", "Le note fissate restano in cima alla lista." },
  onMap = "Sulla mappa", onMapTip = { "Mostra sulla mappa", "Mette una puntina sulla mappa dove è stata scritta la nota." },
  noPlace = "Questa nota non ha alcun punto sulla mappa (alla creazione non era leggibile nessun luogo).",
  titleHint = "Titolo …",
  bodyHint = "Scrivi qui … (# titolo, - elenco, [ ] casella)\nMaiusc+clic su un oggetto, una missione o un incantesimo per inserire un collegamento.",
  created = "creata %s", changed = "modificata %s", levelW = "Livello %d",
  emptyRead = "Ancora vuota. Scegli “Modifica” per scrivere.",
  delete = "Elimina", deleteTip = { "Elimina la nota", "Chiede ancora una volta." }, confirm = "Eliminare davvero?",
  confirmTip = { "Eliminare davvero?", "Un altro clic elimina la nota per sempre." },
  full = "Il taccuino è pieno (al massimo %d note).", notReady = "La cronaca non è ancora pronta.",
  tooLong = "La nota è piena (al massimo %d caratteri).", linkType = "Si possono inserire solo oggetti, missioni e incantesimi.",
  chars = "%d / %d",
  quick = "Note rapide",
  quickTip = { "Note rapide", "Mostra un piccolo campo al bordo dello schermo: scrivi, premi Invio e la nota è nel taccuino." },
  ink = "Inchiostro", symbols = "Simboli",
  tools = {
    head = { label = "Titolo", tip = { "Titolo", "Mette “# ” davanti alla riga." } },
    emph = { label = "Enfasi", tip = { "Enfasi", "Inserisce **…** (il testo in mezzo viene messo in evidenza)." } },
    bullet = { label = "Elenco", tip = { "Elenco puntato", "Mette “- ” davanti alla riga." } },
    check = { label = "Casella", tip = { "Lista di controllo", "Mette “[ ] ” davanti alla riga; si può spuntare in “Leggi”." } },
    rule = { label = "Linea", tip = { "Divisore", "Inserisce una riga “---”." } },
  },
  symbolsTip = { "Simboli", "Inserisci i segni del raid e i simboli della mappa.", "Collegamenti: Maiusc+clic su un oggetto, una missione o un incantesimo." },
  truncated = "… (altre righe solo in “Modifica”)",
})

-- journal/pages/Quests.lua
L.add("itIT", "p.Dungeons", {
  subRuns = "Percorsi",
  subRunsTip = "Ogni percorso: quando, quanto è durato, con chi, boss, morti e bottino",
  subQuests = "Missioni delle spedizioni",
  subQuestsTip = "Tutte le missioni delle spedizioni e le loro catene di missioni (dati: QuestieDB, solo WoW Forever)",
})

L.add("itIT", "p.Quests", {
  subHistory = "Cronologia",
  subHistoryTip = "Missioni completate con testo, cronologia e ricompensa",
  subOpen = "Aperte",
  subOpenTip = "Missioni che puoi accettare adesso, con una mappa dei donatori (dati: QuestieDB)",
  subZones = "Zone",
  subZonesTip = "A che punto sono le missioni di ogni zona, con la medaglia Maestro di zona (solo WoW Forever)",
  pageOf = "Pagina %d di %d", prevPage = "Pagina precedente", nextPage = "Pagina successiva", level = "Livello %s",
  filterName = "Nome “%s”", filterArea = "Zona %s", filterLevel = "Livello %s",
  countOf = "%s di %s missioni", count_one = "%s missione", count_other = "%s missioni", questLevel = "Livello della missione %s",
  goalsMore_one = "+ %s altro obiettivo", goalsMore_other = "+ altri %s obiettivi", walked = "%s a piedi", day = "Giorno %s",
  after = "dopo %s", afterApprox = "dopo circa %s", vanished = "sparita dal registro delle missioni", itemNo = "Oggetto n. %s",
  chosenOf = "%s (1 di %s)", countX = "%s × · %s", moreItems = "+ altri %s oggetti", choiceItemsUnknown = "Gli oggetti fra cui scegliere non sono stati registrati.",
  abandonedN = "%s abbandonate",
  book = "LIBRO DELLE MISSIONI", title = "INK & EMBERS", quests = "MISSIONI",
  colName = "Nome", colArea = "Zona", colLevel = "Livello", colDate = "Consegnata il",
  search = "Cerca nome …", all = "Tutte", sortLbl = "Ordina e filtra",
  sortUpTip = "Ordine crescente", sortDownTip = "Ordine decrescente", clearTip = "Cancella il filtro",
  headTip = "Clic: ordina e filtra", headTipSort = "Clic: ordina", filterLbl = "Filtro: ",
  toTable = "Torna alla tabella",
  noMatch = "Nessuna missione corrisponde a questo filtro.",
  sortAsc = "Ordinate: crescente", sortDesc = "Ordinate: decrescente",
  goals = "Obiettivi", turnIn = "Consegna", life = "Cronologia", rewardHead = "Ricompensa",
  noDetail = "Nessun testo di descrizione registrato.", noGoals = "Nessun obiettivo registrato.", noReward = "Nessun testo di consegna registrato.",
  emptyHead = "Ancora nessuna missione completata.",
  emptyBody = "Appena completi una missione, la cronaca la scrive qui. Quali missioni ci sono ancora là fuori lo vedi sotto \"Aperte\".",
  emptyRight = "Cronologia e ricompense compaiono con la prima missione completata.",
  accepted = "Accettata", abandoned = "Abbandonata", turned = "Consegnata", between = "Lungo la strada",
  done = "completata",
  stateWord = { done = "completata", open = "aperta", abandoned = "abbandonata", seen = "solo letta" },
  xpUnit = "esperienza",
  chosen = "scelta", notChosen = "non scelta", received = "ricevuta", choiceNotRecorded = "Scelta non registrata", fixed = "Ricompensa", choice = "a scelta",
  noItems = "nessun oggetto come ricompensa", noRewardData = "nessuna ricompensa registrata",
  partial = "Le altre ricompense a scelta sono sconosciute.",
  speakPlay = "Leggi ad alta voce (Spoken)", speakStop = "Ferma", speakNone = "Nessuna registrazione in Spoken",
  partAccept = "Testo della missione", partProgress = "Testo di progresso", partComplete = "Testo di consegna",
})

-- journal/pages/Schaetze.lua
L.add("itIT", "p.Schaetze", {
  level = "Livello %s", levels = "Livello %s–%s", total = "Totale %s", gearSub = "%s cambiamenti · dal livello 1 a %s", gearSubNone = "Ancora nessun cambiamento · equipaggia qualcosa di nuovo",
  brand = "INK & EMBERS", page = "TESORI", book = "BORSA", bag = "NELLA BORSA",
  ledger = "Registro", flow = "Flusso dell'oro", flowSub = "Da dove è arrivato l'oro e dove è andato",
  toBars = "Fonti", toBand = "Livelli", noMoney = "Ancora nessun oro mosso.",
  bagEmpty = "Borsa vuota",
  ledgerEmpty = "Ancora nessun oro mosso. Bottino, ricompense delle missioni e mercanti compaiono qui da soli.",
  flowEmpty = "Ancora nessun oro mosso. Appena le monete tintinnano, qui si vede da dove sono arrivate e dove sono andate.",
  gearEmptyHand = "Ancora nessun equipaggiamento registrato. A ogni pezzo che equipaggi, qui cresce la cronologia dal livello 1 a %s.",
  qualityEmpty = "Qui ogni ritrovamento viene contato per qualità.",
  flowLevels = "Entrate e uscite per livello", income = "Entrate", expense = "Uscite", net = "Saldo",
  toHold = "Possedimenti", holdTip = "Possedimenti per livello", holdTip2 = "La maggior quantità di oro nella borsa in ogni livello",
  flowHold = "Maggior oro posseduto per livello", holdPeak = "Picco %s · livello %s", holdJump = "Balzo maggiore +%s · livello %s",
  gear = "Equipaggiamento nel tempo", gearEmpty = "Ancora nessun equipaggiamento registrato.", quality = "RITROVAMENTI PER QUALITÀ",
  incomeBar = "ENTRATE", expenseBar = "USCITE E BORSA", blue = "Primo oggetto raro",
  toOverview = "Panoramica", overviewTip = "Borsa, registro e flusso dell'oro",
  toFunde = "Ritrovamenti d'equipaggiamento", fundeTip = "Tutti i ritrovamenti d'equipaggiamento di qualità non comune o superiore",
  fundeTipEpic = "Epico conta insieme i ritrovamenti epici e leggendari.",
  fundeTip2 = "Tabella: da dove, dove e a quale livello",
  toAnprobe = "Viaggio dell'equipaggiamento", anprobeTip = "Il tuo personaggio con l'equipaggiamento di ogni livello",
  anprobeTip2 = "Modello 3D e cronologia: prova livello dopo livello",
})

-- journal/pages/SchaetzeAnprobe.lua
L.add("itIT", "p.SchaetzeAnprobe", {
  brand = "INK & EMBERS", book = "EQUIPAGGIAMENTO", page = "VIAGGIO DELL'EQUIPAGGIAMENTO",
  title = "Viaggio dell'equipaggiamento", recordFrom = "Registrato dal livello %s",
  level = "Livello %s", startState = "Equipaggiamento iniziale", noChange = "nessun cambiamento", newPieces = "%s nuovi",
  empty = "Ancora nessun equipaggiamento registrato.",
  emptyBody = "Il viaggio dell'equipaggiamento si riempie con il tuo prossimo cambio di equipaggiamento.",
  slotEmpty = "vuoto", itemNo = "Oggetto n. %s", newTag = "nuovo",
  notShown = "Non può essere mostrato sul modello",
  modelCombat = "Il modello compare dopo lo scontro.", modelMissing = "Il modello non può essere mostrato qui.",
})

-- journal/pages/SchaetzeFunde.lua
L.add("itIT", "p.SchaetzeFunde", {
  prevPage = "Pagina precedente", nextPage = "Pagina successiva", clock = "%s", itemNo = "Oggetto n. %s",
  countOf = "%s di %s ritrovamenti", count_one = "%s ritrovamento", count_other = "%s ritrovamenti",
  brand = "INK & EMBERS", book = "EQUIPAGGIAMENTO", page = "NON COMUNE E SUPERIORE",
  title = "Ritrovamenti d'equipaggiamento", sub = "Tutto ciò che è di qualità non comune o superiore e che si può equipaggiare",
  colItem = "Oggetto", colSlot = "Slot", colLevel = "Livello", colTime = "Ricevuto",
  back = "Torna alla panoramica", all = "Tutti", sortLbl = "Ordina e filtra", sortOnlyLbl = "Ordina",
  sortUpTip = "Ordine crescente", sortDownTip = "Ordine decrescente", clearTip = "Cancella il filtro",
  headTip = "Clic: ordina e filtra", headTipSort = "Clic: ordina", headTipZone = "Clic: ordina, filtra per zona",
  filterWord = { quality = "Qualità", slot = "Slot", zone = "Zona" },
  pick = "Scegli un ritrovamento a sinistra.", secFound = "Trovato", secStats = "Statistiche", secLine = "Cronologia",
  labWhen = "Quando", labWhere = "Dove", labSource = "Fonte", labReplaced = "Sostituito",
  whenNone = "Ora sconosciuta", whereNone = "Luogo sconosciuto", levelWord = "Livello del personaggio ",
  replacedNone = "nessun oggetto noto", replacedEmpty = "nulla (lo slot era vuoto)", notWorn = "non equipaggiato",
  statsHint = "Il tooltip mostra le statistiche: passa il mouse sull'icona.", itemLevelWord = "Livello dell'oggetto ",
  lineNone = "Per questo slot non ci sono informazioni sui livelli.", lineLevel = "Livello ",
  lineHead = "Cronologia: ", lineCount = { " ritrovamento", " ritrovamenti" },
  sortAsc = "Ordinati: crescente", sortDesc = "Ordinati: decrescente", filterLbl = "Filtro: ",
  empty = "Ancora nessun equipaggiamento non comune o superiore trovato.",
  emptyBody = "Appena ricevi equipaggiamento verde o superiore, la cronaca lo scrive qui.",
  noMatch = "Nessun ritrovamento corrisponde a questo filtro.",
})

-- 1.0.12 data books
L.add("itIT", "p.Schaetze", {
  toTrade = "Commercio",
  tradeTip = "Casa d'Aste, posta e scambi",
  tradeTip2 = "Cifre da fatture, lettere e scambi",
  tradeSub = "Casa d'Aste, posta e scambi",
})

-- change "runde3" (packages A, R, E, L)
-- journal/pages/ChronikVermaechtnis.lua
L.add("itIT", "p.ChronikVermaechtnis", {
  challengesHead = "Sfide", tabClasses = "Classi", pageOf = "Pagina %s di %s", tipProgress = "Progresso: %s di %s", progress = "%s/%s", colAch = "Sfida", colState = "Stato", colPoints = "Punti", prevPage = "Pagina precedente", nextPage = "Pagina successiva",
  page = "EREDITÀ", brand = "INK & EMBERS", title = "Eredità",
  subLabel = "Eredità", subTip = "Punti, sfide di classe, alberi dei talenti e ricompense del sistema Eredità",
  subTip2 = "Vale per tutto il tuo account; solo WoW Forever",
  points = "Punti: %s su %s", pointsOnly = "Punti: %s", pointsMax = "Punti possibili: %s",
  level = "Percorso dell'Eredità: livello %s", levelOf = "Percorso dell'Eredità: livello %s su %s",
  classesHead = "Sfide di classe", tier1 = "Novizio", tier2 = "Esperto", tier3 = "Maestro",
  date = "{d}/{m}/{y}", doneShort = "fatto", openShort = "aperto",
  tipDone = "Completata il %s", tipDoneNoDate = "Completata", tipOpen = "Non ancora completata", tipPoints_other = "Vale %s punti",
  tipPoints_one = "Vale %s punto", tipOther = "Ottenuta da un altro personaggio del tuo account",
  tipTier = "%s · %s", classesUnreadable = "Al momento le sfide di classe non si possono leggere.",
  rewardsHead = "Ricompense del percorso", rewardLevel = "Livello %s", rewardFallback = "Oggetto n. %s", rewardUnknown = "Ricompensa",
  collected = "ritirata", ready = "pronta da ritirare", reached = "raggiunto",
  missing_one = "manca %s punto", missing_other = "mancano %s punti", tipNeed = "Disponibile dal livello %s del percorso dell'Eredità",
  rewardsUnreadable = "Al momento le ricompense non si possono leggere.",
  treesTitle = "Alberi dei talenti", tree_professions = "Professioni", tree_adventure = "Avventura", tree_progression = "Progressione",
  rank = "%s/%s", tipRank = "Rango %s su %s", unknown = "Sconosciuto", treeUnreadable = "Al momento questo albero non si può leggere.",
  treeEmpty = "Nessun nodo trovato.",
  hintCombat = "Il libro non legge l'Eredità durante il combattimento. Torna dopo lo scontro.",
  hintUnreadable = "Al momento l'Eredità non si può leggere. Riprova tra un attimo.",
  reread = "Rileggi",
  staleCombat = "In combattimento: stato salvato del {date}", staleUnreadable = "Al momento non leggibile: stato salvato del {date}",
})

L.add("itIT", "p.Schaetze", {
  toAuktion = "Casa d'Aste", auktionTip = "Tutte le vendite e gli acquisti alla Casa d'Aste",
  auktionTip2 = "Tabella ordinabile: data, oggetto, quantità e prezzo",
})

-- journal/pages/SchaetzeAuktion.lua
L.add("itIT", "p.SchaetzeAuktion", {
  brand = "INK & EMBERS", book = "CASA D'ASTE", page = "BILANCIO",
  title = "Casa d'Aste", count_one = "%s fattura", count_other = "%s fatture", countOf = "%s di %s fatture",
  prevPage = "Pagina precedente", nextPage = "Pagina successiva",
  colTime = "Data", colKind = "Tipo", colItem = "Oggetto", colCount = "Q.tà", colPrice = "Totale", colUnit = "Unità",
  fAll = "Tutto", fSold = "Vendite", fBought = "Acquisti",
  fAllTip = "Tutte le fatture", fSoldTip = "Solo vendite", fBoughtTip = "Solo acquisti",
  sortAsc = "Ordine: crescente", sortDesc = "Ordine: decrescente", headTip = "Clic: ordina, di nuovo clic: inverti",
  tipCount = "Quantità: %s", tipTotal = "Prezzo totale: %s", tipUnit = "Per pezzo: %s", tipFee = "Commissione: %s", tipNoPrice = "Prezzo non leggibile",
  empty = "Ancora nessuna fattura della Casa d'Aste.",
  emptyBody = "Appena svuoti la cassetta della posta e ci sono fatture di vendite o acquisti, la cronaca le annota qui.",
  noMatch = "Nessuna fattura corrisponde a questo filtro.",
  balTitle = "Bilancio", balSub = "Tutte le fatture, a prescindere dal filtro",
  secSold = "Vendite", secBought = "Acquisti", secSaldo = "In conclusione",
  labSoldN = "Oggetti venduti", labIncome = "Entrate", labFee = "Commissione", labBoughtN = "Oggetti acquistati", labSpent = "Spese",
  labSaldo = "Saldo", saldoPlus = "Incassato più di quanto speso", saldoMinus = "Speso più di quanto incassato", saldoZero = "In pareggio",
  balNote = "Si basa sulle fatture della tua cassetta della posta. Offerte, depositi e aste scadute non compaiono in nessuna fattura.",
  noPrice = "–",
})

-- journal/pages/ChronikRueckblick.lua
L.add("itIT", "p.ChronikRueckblick", {
  page = "RIEPILOGO", brand = "INK & EMBERS", title = "Prima, nel tuo viaggio", date = "{d}/{m}/{y}",
  dateRange = "{from} – {to}", preview = "Anteprima", sessions_one = "%s sessione", sessions_other = "%s sessioni",
  standHead = "A che punto sei", openHead = "Cosa è ancora aperto", noteHead = "A margine", standNone = "Ancora niente annotato.",
  openNone = "Al momento non c'è nulla di aperto.", pin = "Fissata: %s", progress = "%s (%s su %s)", picCaption = "%s",
  picCaptionDate = "%s · %s", picTipHead = "L'ultimo percorso", picTipRange = "%s al %s", building = "La cronaca sta ancora riordinando. Riguarda tra un attimo.",
  empty = "È successo ancora troppo poco per un riepilogo.", notReady = "Il riepilogo non è ancora pronto.",
  doneHead = "Completato di recente",
  quoted = "«%s»",
  bestLine = "Miglior ritrovamento: %s",
  moreTip = "Tutto ciò che è aperto",
  picTipQuests_one = "%s missione consegnata",
  picTipQuests_other = "%s missioni consegnate",
  picTipAccepts_one = "%s missione accettata",
  picTipAccepts_other = "%s missioni accettate",
  openHere = "Da queste parti",
  openAway = "Altrove",
  clickTip = "Clic: mostra nel registro missioni",
  questCombat = "Il registro missioni non si apre in combattimento. Riprova dopo.",
  questFailed = "Il registro missioni non si può aprire in questo momento.",
})
