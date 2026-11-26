-- Textes français pour journal/pages/*.lua. Un bloc L.add par module, avec les mêmes clés que L.ns.
local _, ns = ...
local L = ns.Locale

-- journal/pages/Chronik.lua
L.add("frFR", "p.Chronik", {
  ofSeals = "%s sur %s", longest = "le plus long : %s", noLevel = "%s sans niveau", pageOf = "Page %s sur %s",
  brand = "INK & EMBERS", profile = "PROFIL", page = "CHRONIQUE", traveller = "VOYAGEUR", travellerM = "VOYAGEUR", travellerF = "VOYAGEUSE",
  standDate = "État au %s", standXp = "État au %s · %s", standFmt = "%d/%m/%Y",
  since = "En route depuis", played = "Temps de jeu total", perDay = "Moy. par jour de jeu", sessions = "Sessions", entries = "Événements consignés",
  seals = "MÉDAILLES DU VOYAGE", flow = "Déroulé des niveaux", flowSub = "Combien de temps a pris chaque niveau",
  legend = "points rouges = mort", xpTotal = "EXPÉRIENCE TOTALE", sources = "SOURCES D'EXPÉRIENCE",
  noXp = "Aucune expérience gagnée pour l'instant.", diaryEmpty = "Rien vécu pour l'instant – le journal attend.",
  diaryNone = "Du journal", ofMax = "SUR %s", ringStart = "En route !", prevTip = "Jour précédent", nextTip = "Jour suivant",
  toDiary = "Journal", toDiaryTip = "Lire le journal", toDiaryTip2 = "Chaque jour de jeu en une entrée, jour après jour",
  toMates = "Compagnons", toMatesTip = "Voir les compagnons", toMatesTip2 = "Qui a voyagé avec toi",
  toProfile = "Profil", toProfileTip = "Profil, déroulé des niveaux et extrait du journal",
  toMilestones = "Étapes", toMilestonesTip = "Voir les étapes", toMilestonesTip2 = "Tous les dix niveaux, un bilan du voyage, au niveau 60 la page finale",
  toRecap = "Auparavant, dans ton voyage", toRecapTip = "Voir le récapitulatif", toRecapTip2 = "Ce qui s'est passé récemment et ce qui vient ensuite",
})

-- journal/pages/ChronikViews.lua
L.add("frFR", "p.ChronikViews.Diary", {
  page = "JOURNAL", brand = "INK & EMBERS", prevTip = "Un jour en arrière", nextTip = "Un jour en avant",
  empty = "Aucune entrée pour l'instant", emptyBody = "Dès que tu te mets en route, une entrée s'écrit ici chaque jour.",
  blank = "La page suivante est encore vierge.", blankBody = "Ce qui se passera demain apparaîtra ici une fois que ce sera arrivé.",
  dayPair = "Jours %s et %s sur %s", dayOne = "Jour 1 sur 1",
})
L.add("frFR", "p.ChronikViews.Switch", {
  group = "Groupe", fire = "Au coin du feu", groupTip = "Compagnons de ton groupe", fireTip = "Qui s'est assis avec toi au feu de camp",
})
L.add("frFR", "p.ChronikViews.Mates", {
  levelRange = "Niveau %s à %s", level = "Niveau %s", date = "{d}/{m}/{y}", togetherFmt = "%s ensemble",
  quests_one = "%s quête", quests_other = "%s quêtes", kills_one = "%s victoire", kills_other = "%s victoires",
  firstMet = "rencontrés à %s le %s", pageOf = "Page %s sur %s", persons_one = "%s personne", persons_other = "%s personnes",
  classes = {
    WARRIOR = "Guerrier", PALADIN = "Paladin", HUNTER = "Chasseur", ROGUE = "Voleur", PRIEST = "Prêtre", DEATHKNIGHT = "Chevalier de la mort",
    SHAMAN = "Chaman", MAGE = "Mage", WARLOCK = "Démoniste", MONK = "Moine", DRUID = "Druide", DEMONHUNTER = "Chasseur de démons",
    EVOKER = "Évocateur",
  },
  races = {
    Human = "Humain", Orc = "Orc", Dwarf = "Nain", NightElf = "Elfe de la nuit", Scourge = "Mort-vivant", Tauren = "Tauren", Gnome = "Gnome",
    Troll = "Troll", Goblin = "Gobelin", BloodElf = "Elfe de sang", Draenei = "Draeneï", Worgen = "Worgen", Pandaren = "Pandaren",
    Dracthyr = "Dracthyr", EarthenDwarf = "Terrestre", VoidElf = "Elfe du Vide", Nightborne = "Sacrenuit",
    HighmountainTauren = "Tauren de Haut-Roc", LightforgedDraenei = "Draeneï sancteforge", ZandalariTroll = "Troll zandalari",
    KulTiran = "Kultirassien", DarkIronDwarf = "Nain sombrefer", Vulpera = "Vulpérin", MagharOrc = "Orc mag'har", Mechagnome = "Mécagnome",
  },
  page = "COMPAGNONS", brand = "INK & EMBERS", title = "Compagnons", empty = "Tu voyages encore seul.",
  emptyBody = "Quiconque voyage avec toi en groupe est consigné ici.", sortRecent = "récents", sortLong = "plus longs",
  sortRecentTip = "Rencontrés le plus récemment d'abord", sortLongTip = "Plus long temps ensemble d'abord", pick = "Clique sur un nom pour les détails.",
  prevTip = "Page précédente", nextTip = "Page suivante",
  truncated = "Très nombreuses rencontres : les plus anciennes ne sont plus complètes.", now = "dans ton groupe en ce moment",
  first = "Première rencontre", last = "Vu pour la dernière fois", together = "Temps ensemble", sessions = "Sessions communes",
  quests = "Quêtes communes", kills = "Victoires communes", deaths = "Tes morts entre-temps", unknownZone = "un lieu inconnu",
  zones = "Lieux communs", lastQuests = "Dernières accomplies ensemble", noQuests = "Aucune quête rendue ensemble pour l'instant.",
})
-- journal/pages/ChronikDungeons.lua
L.add("frFR", "p.ChronikDungeons", {
  page = "DONJONS", brand = "INK & EMBERS", title = "Donjons", empty = "Aucun donjon visité pour l'instant.",
  emptyBody = "Dès que tu entres dans un donjon, le livre consigne chaque parcours : quand, combien de temps, avec qui, les boss, les morts et le butin.",
  pick = "Clique sur un parcours pour les détails.", prevTip = "Page précédente", nextTip = "Page suivante", pageOf = "Page %s sur %s",
  runs_one = "%s parcours", runs_other = "%s parcours", truncated = "Très nombreux parcours : les plus anciens ne sont pas listés.",
  date = "{d}/{m}/{y}", dateShort = "{d}/{m}",
  bosses_one = "%s boss vaincu", bosses_other = "%s boss vaincus", complete = "terminé", live = "en cours",
  endUnknown = "fin inconnue", deaths_one = "%s mort", deaths_other = "%s morts", noDeaths = "aucune mort",
  unknownInstance = "Donjon inconnu", unknownBoss = "Boss inconnu",
  when = "Quand", duration = "Durée", level = "Niveau", kills = "Victoires", xp = "Expérience",
  visits_one = "%s entrée dans l'instance", visits_other = "%s entrées dans l'instance", lv = "Niveau %s", levelRange = "Niveau %s à %s",
  you = "Toi", roll_need = "Besoin", roll_greed = "Cupidité", roll_de = "Désenchantement", roll_tmog = "Transmog",
  whenSame = "{date}, {from}–{to}", whenOther = "{from} – {to}", whenLive = "{date}, depuis {from}",
  secBosses = "Boss", secBossesN = "Boss · %s vaincus", secBossesOf = "Boss · %s vaincus sur %s",
  secGroup = "Groupe", secDeaths = "Morts", secLoot = "Trouvailles (vertes et mieux)", secQuests = "Quêtes",
  tries_one = "%s tentative échouée", tries_other = "%s tentatives échouées", bossWon = "vaincu", bossNot = "non vaincu",
  bossCountOnly = "Le client n'a pas signalé les combats de boss, seul le nombre est connu.",
  noGroup = "Aucun membre du groupe consigné.",
  cause_enemy = "face à un ennemi", cause_fall = "d'une chute", cause_drown = "par noyade", cause_fatigue = "d'épuisement",
  cause_lava = "dans la lave", cause_fire = "dans le feu", cause_slime = "dans la vase", cause_environment = "à cause de l'environnement",
  byFoe = "face à %s", guess = "%s (supposé)", died = "mort", more = "… et %s de plus",
  questDone = "rendue", questTaken = "acceptée", questFallback = "Quête n°%s", itemFallback = "Objet n°%s",
  xpUnit = "%s d'expérience", reward = "Récompense : %s", groupTip = "Groupe",
})

-- journal/pages/ChronikMeilensteine.lua
L.add("frFR", "p.ChronikMeilensteine", {
  page = "ÉTAPES", brand = "INK & EMBERS", title = "Étapes",
  reachedOf = "%s sur %s atteintes", range = "Niveau %s–%s", final = "Fin du voyage", finalSub = "Tout le voyage · niveau 1–%s",
  date = "{d}/{m}/{y}", dateRange = "{from} – {to}", running = "en cours", runningSince = "en cours depuis le {date}", open = "pas encore atteinte",
  before = "avant l'enregistrement", noRecord = "rien de consigné", soFar = "%s jusqu'ici", reachedIn = "atteinte en %s",
  openBody = "Tu n'as pas encore atteint cette étape. Dès que tu atteins le niveau, le narrateur en fait le bilan ici.",
  beforeBody = "Il n'y a aucun enregistrement pour ce tronçon : le livre n'écrit qu'à partir du niveau %s.",
  emptyBody = "Rien n'est consigné pour ce tronçon.",
  truncated = "Un très long voyage : les lignes plus anciennes sont élaguées, les chiffres sont des minimums.",
  kTime = "Temps (hors AFK)", kZones = "Nouvelles zones", kKills = "Victoires", kQuests = "Quêtes", kDeaths = "Morts", kDungeons = "Donjons",
  kBest = "Meilleure trouvaille", kDays = "Jours de jeu", kSeals = "Médailles", kTotal = "Temps total (hors AFK)",
  noDeaths = "aucune mort", runs_one = "%s parcours", runs_other = "%s parcours", bosses_one = "%s boss", bosses_other = "%s boss",
  sealsOf = "%s sur %s", about = "environ %s", roughly = "environ %s", atLeast = "au moins %s",
  colsHead = "Temps par tronçon", colDur = "%s:%s h", colTip = "Niveau %s–%s", colUnknown = "Temps inconnu", itemFallback = "Objet n°%s",
  zonesMore = "… et %s de plus",
})

-- journal/pages/Kampf.lua
L.add("frFR", "p.Kampf", {
  pageOf = "Page %s sur %s", deathOf = "Mort %s sur %s", moreZones = "+ %s zones de plus", closeCount = "%s victoires de justesse · %s",
  brand = "INK & EMBERS", page = "BESTIAIRE", right = "COMBAT", hunted = "LES PLUS CHASSÉS", rare = "ENNEMI RARE",
  zoneLabel = "ZONE",
  graves = "OÙ JE SUIS MORT", gravesTip = "Zones où tu es mort – une pierre tombale par mort",
  close = "DE JUSTESSE", prevDeath = "Mort précédente", openDeath = "Clic : rapport de cette mort",
  openLastDeath = "Clic : rapport de la dernière mort ici", deathNo = "Mort %s",
  nextDeath = "Mort suivante", prevCards = "Ennemis précédents", nextCards = "Plus d'ennemis",
  hintHunted = "Tue un ennemi et il apparaît ici.", hintHuntedZone = "Tue un ennemi ici et il apparaît dans cette liste.",
  hintGraves = "Chaque mort reçoit ici une pierre tombale.", hintClose = "Gagne un combat avec peu de vie et il apparaît ici.",
  hintZone = "Tue un ennemi et tes terrains de chasse prennent forme.",
  zoneEmpty = "Aucune zone avec des victoires pour l'instant.", krit = "crit.", unknownPic = "?", here = "ici",
  lowGraves = "Morts", lowClose = "Frayeurs", backToGraves = "Retour aux morts",
  noDeathTitle = "Le dernier souffle",
  modeHot = "Points chauds", modePoints = "Exact",
  modeHotTip = "Points chauds : une tache par case de la grille, plus grande et plus sombre avec plus de victoires",
  modePointsTip = "Exact : chaque point est un ennemi tué (échantillon des dernières victoires)",
  mapHint = "Molette : zoom · Glisser : déplacer · Double-clic : réinitialiser",
  hotspot = "Point chaud", killsWord = "%s · %s victoires", onePoint = "Point de victoire", pointsHere = "%s victoires ici",
  sample = "Échantillon : les %s dernières victoires sur %s dans cette zone",
  openLens = "Clic : voir le modèle de près", lensHint = "Glisser : pivoter · Molette : zoom · Échap ou clic à l'extérieur : fermer",
  lowGravesTip = "Où je suis mort : zones avec une pierre tombale par mort (clic sur une pierre tombale : rapport de mort)",
  lowCloseTip = "Les victoires les plus serrées",
  huntedTip = "Choisis une zone – toute la page n'affiche alors que cette zone (à l'ouverture : ta zone actuelle)",
})

-- journal/pages/Momente.lua
L.add("frFR", "p.Momente", {
  level = "Niveau %s", day = "Jour %s", readAt = "Lu : %s", ofWhich = "dont %s", hour = "%s h",
  brand = "INK & EMBERS", page = "MOMENTS", moment = "moment", moments = "moments",
  kept = "consignés", zoneOne = "nouvelle zone", zonesOf = "nouvelles zones", prevTip = "Moments plus récents", nextTip = "Moments plus anciens", pageOf = "Page %d sur %d",
  emptyHead = "Aucun moment collé pour l'instant.", emptyBody = "Niveaux, ennemis rares, premières trouvailles et nouveaux lieux atterrissent ici dans l'album.",
  emptyFilter = "Rien de collé dans ce groupe pour l'instant.",
  unreadable = "Entrée illisible",
  filters = { all = "Tous", levels = "Niveaux", fights = "Combats", finds = "Trouvailles", places = "Lieux" },
  clock = "TEMPS DE JEU SELON L'HEURE", fav = "Heure préférée", longest = "Plus longue session", sessions = "Sessions",
  interrupted = "interrompue", noClock = "Aucun temps de jeu consigné pour l'instant.",
  noClockHand = "Bientôt l'horloge montrera à quelle heure de la journée tu aimes le plus voyager.",
  jumpFirst = "Maj+clic : vers la feuille la plus récente", jumpLast = "Maj+clic : vers la feuille la plus ancienne",
  library = "BIBLIOTHÈQUE", libEmpty = "Aucun livre lu pour l'instant.", book = "livre", books = "livres", pageW = "page", pagesW = "pages",
  readPages = "lues", curios = "CURIOSITÉS", curiosEmpty = "Rien de curieux vécu pour l'instant.",
  back = "Retour à l'album", pagePrev = "Page précédente", pageNext = "Page suivante", pageGone = "Cette page est illisible.",
})

-- journal/pages/Notizen.lua (les raccourcis de balisage restent tels quels)
L.add("frFR", "p.Notizen", {
  inkTip = "Encre : %s", inkInsert = "Insère {%s}…{/}.", symInsert = "Insère {%s}.", reopen = "Rouvrir", tick = "Cocher",
  whenFmt = "%d/%m %H:%M",
  brand = "INK & EMBERS", page = "NOTES",
  note = "note", notes = "notes", pinnedN = "%d épinglées", lastEdit = "dernière %s",
  pageOf = "Page %d sur %d", prevTip = "Page précédente", nextTip = "Page suivante",
  sortNew = "Plus récentes d'abord", sortOld = "Plus anciennes d'abord", sortTitle = "Par titre",
  sortTip = { "Tri", "Les notes épinglées restent toujours en haut." },
  searchHint = "Chercher dans le titre et le texte …", searchClear = "Effacer la recherche",
  newNote = "Nouvelle note", newTip = { "Nouvelle note", "Crée une note avec le lieu, le niveau et l'heure actuels." },
  untitled = "Sans titre", emptyList = "Aucune note pour l'instant.", emptyListBody = "Utilise « Nouvelle note » ci-dessous pour créer la première.",
  noMatch = "Aucune note ne correspond à la recherche.", noChar = "Il n'y a pas encore de chronique pour ce personnage.",
  pickNote = "Choisis une note à gauche ou crées-en une nouvelle.",
  edit = "Modifier", read = "Lire", editTip = { "Modifier", "Écris du texte avec balisage (sauvegarde automatique)." },
  readTip = { "Lire", "Affiche la note mise en forme ; les cases à cocher sont cliquables." },
  pin = "Épinglée", pinTip = { "Épingler", "Les notes épinglées restent en haut de la liste." },
  onMap = "Sur la carte", onMapTip = { "Afficher sur la carte", "Place une épingle sur la carte là où la note a été écrite." },
  noPlace = "Cette note n'a pas de point sur la carte (aucun lieu n'était lisible à sa création).",
  titleHint = "Titre …",
  bodyHint = "Écris ici … (# titre, - liste, [ ] case à cocher)\nMaj+clic sur un objet, une quête ou un sort pour insérer un lien.",
  created = "créée %s", changed = "modifiée %s", levelW = "Niveau %d",
  emptyRead = "Encore vide. Choisis « Modifier » pour écrire.",
  delete = "Supprimer", deleteTip = { "Supprimer la note", "Demande une dernière confirmation." }, confirm = "Vraiment supprimer ?",
  confirmTip = { "Vraiment supprimer ?", "Un nouveau clic supprime la note pour de bon." },
  full = "Le carnet est plein (%d notes au maximum).", notReady = "La chronique n'est pas encore prête.",
  tooLong = "La note est pleine (%d caractères au maximum).", linkType = "Seuls les objets, quêtes et sorts peuvent être insérés.",
  chars = "%d / %d",
  quick = "Notes rapides",
  quickTip = { "Notes rapides", "Affiche un petit champ au bord de l'écran : tape, appuie sur Entrée, et la note est dans le carnet." },
  ink = "Encre", symbols = "Symboles",
  tools = {
    head = { label = "Titre", tip = { "Titre", "Place « # » devant la ligne." } },
    emph = { label = "Accent", tip = { "Accentuation", "Insère **…** (le texte entre les deux est mis en valeur)." } },
    bullet = { label = "Liste", tip = { "Liste à puces", "Place « - » devant la ligne." } },
    check = { label = "Case", tip = { "Liste de contrôle", "Place « [ ] » devant la ligne ; se coche dans « Lire »." } },
    rule = { label = "Ligne", tip = { "Séparateur", "Insère une ligne « --- »." } },
  },
  symbolsTip = { "Symboles", "Insère des marqueurs de raid et des symboles de carte.", "Liens : Maj+clic sur un objet, une quête ou un sort." },
  truncated = "… (d'autres lignes seulement dans « Modifier »)",
})

-- journal/pages/Quests.lua
L.add("frFR", "p.Dungeons", {
  subRuns = "Parcours",
  subRunsTip = "Chaque parcours : quand, combien de temps, avec qui, boss, morts et butin",
  subQuests = "Quêtes de donjon",
  subQuestsTip = "Toutes les quêtes de donjon et leurs séries de quêtes (données : QuestieDB, WoW Forever uniquement)",
})

L.add("frFR", "p.Quests", {
  subHistory = "Historique",
  subHistoryTip = "Quêtes terminées avec leur texte, leur chronologie et leur récompense",
  subOpen = "En cours",
  subOpenTip = "Quêtes que tu peux accepter maintenant, avec une carte des donneurs de quêtes (données : QuestieDB)",
  subZones = "Zones",
  subZonesTip = "Où en sont les quêtes de chaque zone, avec la médaille Maître de zone (WoW Forever uniquement)",
  pageOf = "Page %d sur %d", prevPage = "Page précédente", nextPage = "Page suivante", level = "Niveau %s",
  filterName = "Nom « %s »", filterArea = "Zone %s", filterLevel = "Niveau %s",
  countOf = "%s quêtes sur %s", count_one = "%s quête", count_other = "%s quêtes", questLevel = "Niveau de la quête %s",
  goalsMore_one = "+ %s objectif de plus", goalsMore_other = "+ %s objectifs de plus", walked = "%s parcourus", day = "Jour %s",
  after = "après %s", afterApprox = "après env. %s", vanished = "disparue du journal de quêtes", itemNo = "Objet n°%s",
  chosenOf = "%s (1 sur %s)", countX = "%s × · %s", moreItems = "+ %s objets de plus", choiceItemsUnknown = "Les objets au choix n'ont pas été consignés.",
  abandonedN = "%s abandonnées",
  book = "LIVRE DE QUÊTES", title = "INK & EMBERS", quests = "QUÊTES",
  colName = "Nom", colArea = "Zone", colLevel = "Niveau", colDate = "Rendue le",
  search = "Chercher un nom …", all = "Toutes", sortLbl = "Trier et filtrer",
  sortUpTip = "Tri croissant", sortDownTip = "Tri décroissant", clearTip = "Effacer le filtre",
  headTip = "Clic : trier et filtrer", headTipSort = "Clic : trier", filterLbl = "Filtre : ",
  toTable = "Retour au tableau",
  noMatch = "Aucune quête ne correspond à ce filtre.",
  sortAsc = "Trié : croissant", sortDesc = "Trié : décroissant",
  goals = "Objectifs", turnIn = "Remise", life = "Chronologie", rewardHead = "Récompense",
  noDetail = "Aucun texte de description consigné.", noGoals = "Aucun objectif consigné.", noReward = "Aucun texte de remise consigné.",
  emptyHead = "Aucune quête terminée pour l'instant.",
  emptyBody = "Dès que tu termines une quête, la chronique la note ici. Les quêtes qui t'attendent encore, tu les vois sous « En cours ».",
  emptyRight = "La chronologie et les récompenses apparaissent avec la première quête terminée.",
  accepted = "Acceptée", abandoned = "Abandonnée", turned = "Rendue", between = "En chemin",
  done = "terminée",
  stateWord = { done = "terminée", open = "en cours", abandoned = "abandonnée", seen = "seulement lue" },
  xpUnit = "d'expérience",
  chosen = "choisie", notChosen = "non choisie", received = "reçue", choiceNotRecorded = "Choix non consigné", fixed = "Récompense", choice = "au choix",
  noItems = "aucun objet en récompense", noRewardData = "aucune récompense consignée",
  partial = "Les autres récompenses au choix sont inconnues.",
  speakPlay = "Lire à voix haute (Spoken)", speakStop = "Arrêter", speakNone = "Aucun enregistrement dans Spoken",
  partAccept = "Texte de la quête", partProgress = "Texte de progression", partComplete = "Texte de remise",
})

-- journal/pages/Schaetze.lua
L.add("frFR", "p.Schaetze", {
  level = "Niveau %s", levels = "Niveau %s–%s", total = "Total %s", gearSub = "%s changements · niveau 1 à %s", gearSubNone = "Aucun changement pour l'instant · équipe quelque chose de nouveau",
  brand = "INK & EMBERS", page = "TRÉSORS", book = "BOURSE", bag = "DANS LA BOURSE",
  ledger = "Registre", flow = "Flux d'or", flowSub = "D'où l'or est venu et où il est parti",
  toBars = "Sources", toBand = "Niveaux", noMoney = "Aucun or n'a encore bougé.",
  bagEmpty = "Bourse vide",
  ledgerEmpty = "Aucun or n'a encore bougé. Le butin, les récompenses de quêtes et les marchands s'y inscrivent tout seuls.",
  flowEmpty = "Aucun or n'a encore bougé. Dès que les pièces tintent, tu verras ici d'où elles sont venues et où elles sont parties.",
  gearEmptyHand = "Aucun équipement consigné pour l'instant. Avec chaque pièce que tu équipes, la chronologie du niveau 1 au %s s'étoffe ici.",
  qualityEmpty = "Chaque trouvaille est comptée ici selon sa qualité.",
  flowLevels = "Revenus et dépenses par niveau", income = "Revenus", expense = "Dépenses", net = "Net",
  toHold = "Avoirs", holdTip = "Avoirs par niveau", holdTip2 = "Le plus d'or dans la bourse au sein de chaque niveau",
  flowHold = "Plus d'or détenu par niveau", holdPeak = "Pic %s · niveau %s", holdJump = "Plus grand bond +%s · niveau %s",
  gear = "Équipement au fil du temps", gearEmpty = "Aucun équipement consigné pour l'instant.", quality = "TROUVAILLES PAR QUALITÉ",
  incomeBar = "REVENUS", expenseBar = "DÉPENSES ET BOURSE", blue = "Premier objet rare",
  toOverview = "Aperçu", overviewTip = "Bourse, registre et flux d'or",
  toFunde = "Trouvailles d'équipement", fundeTip = "Toutes les trouvailles d'équipement de qualité Inhabituel ou supérieure",
  fundeTipEpic = "Épique compte ensemble les trouvailles épiques et légendaires.",
  fundeTip2 = "Tableau : d'où, où et à quel niveau",
  toAnprobe = "Parcours d'équipement", anprobeTip = "Ton personnage avec l'équipement de chaque niveau",
  anprobeTip2 = "Modèle 3D et chronologie : essaie niveau par niveau",
})

-- journal/pages/SchaetzeAnprobe.lua
L.add("frFR", "p.SchaetzeAnprobe", {
  brand = "INK & EMBERS", book = "ÉQUIPEMENT", page = "PARCOURS D'ÉQUIPEMENT",
  title = "Parcours d'équipement", recordFrom = "Consigné à partir du niveau %s",
  level = "Niveau %s", startState = "Équipement de départ", noChange = "aucun changement", newPieces = "%s nouvelles",
  empty = "Aucun équipement consigné pour l'instant.",
  emptyBody = "Le parcours d'équipement se remplit à ton prochain changement d'équipement.",
  slotEmpty = "vide", itemNo = "Objet n°%s", newTag = "nouveau",
  notShown = "Ne peut pas être affiché sur le modèle",
  modelCombat = "Le modèle apparaît après le combat.", modelMissing = "Le modèle ne peut pas être affiché ici.",
})

-- journal/pages/SchaetzeFunde.lua
L.add("frFR", "p.SchaetzeFunde", {
  prevPage = "Page précédente", nextPage = "Page suivante", clock = "%s", itemNo = "Objet n°%s",
  countOf = "%s trouvailles sur %s", count_one = "%s trouvaille", count_other = "%s trouvailles",
  brand = "INK & EMBERS", book = "ÉQUIPEMENT", page = "INHABITUEL ET PLUS",
  title = "Trouvailles d'équipement", sub = "Tout ce qui est équipable en qualité Inhabituel ou supérieure",
  colItem = "Objet", colSlot = "Emplacement", colLevel = "Niveau", colTime = "Reçu",
  back = "Retour à l'aperçu", all = "Tous", sortLbl = "Trier et filtrer", sortOnlyLbl = "Trier",
  sortUpTip = "Tri croissant", sortDownTip = "Tri décroissant", clearTip = "Effacer le filtre",
  headTip = "Clic : trier et filtrer", headTipSort = "Clic : trier", headTipZone = "Clic : trier, filtrer par zone",
  filterWord = { quality = "Qualité", slot = "Emplacement", zone = "Zone" },
  pick = "Choisis une trouvaille à gauche.", secFound = "Trouvé", secStats = "Caractéristiques", secLine = "Chronologie",
  labWhen = "Quand", labWhere = "Où", labSource = "Source", labReplaced = "Remplacé",
  whenNone = "Heure inconnue", whereNone = "Lieu inconnu", levelWord = "Niveau du personnage ",
  replacedNone = "aucun objet connu", replacedEmpty = "rien (l'emplacement était vide)", notWorn = "non équipé",
  statsHint = "L'infobulle affiche les caractéristiques : survole l'icône.", itemLevelWord = "Niveau d'objet ",
  lineNone = "Il n'y a aucune information de niveau pour cet emplacement.", lineLevel = "Niveau ",
  lineHead = "Chronologie : ", lineCount = { " trouvaille", " trouvailles" },
  sortAsc = "Trié : croissant", sortDesc = "Trié : décroissant", filterLbl = "Filtre : ",
  empty = "Aucun équipement de qualité Inhabituel ou supérieure trouvé pour l'instant.",
  emptyBody = "Dès que tu reçois un équipement vert ou mieux, la chronique le note ici.",
  noMatch = "Aucune trouvaille ne correspond à ce filtre.",
})

-- 1.0.12 data books
L.add("frFR", "p.Schaetze", {
  toTrade = "Commerce",
  tradeTip = "Hôtel des ventes, courrier et échanges",
  tradeTip2 = "Chiffres issus des factures, courriers et échanges",
  tradeSub = "Hôtel des ventes, courrier et échanges",
})

-- change "runde3" (packages A, R, E, L)
-- journal/pages/ChronikVermaechtnis.lua
L.add("frFR", "p.ChronikVermaechtnis", {
  challengesHead = "Défis", tabClasses = "Classes", pageOf = "Page %s sur %s", tipProgress = "Progression : %s sur %s", progress = "%s/%s", colAch = "Défi", colState = "État", colPoints = "Points", prevPage = "Page précédente", nextPage = "Page suivante",
  page = "HÉRITAGE", brand = "INK & EMBERS", title = "Héritage",
  subLabel = "Héritage", subTip = "Points, défis de classe, arbres de talents et récompenses du système d'héritage",
  subTip2 = "Valable pour tout ton compte ; WoW Forever uniquement",
  points = "Points : %s sur %s", pointsOnly = "Points : %s", pointsMax = "Points possibles : %s",
  level = "Voie de l'héritage : niveau %s", levelOf = "Voie de l'héritage : niveau %s sur %s",
  classesHead = "Défis de classe", tier1 = "Novice", tier2 = "Expérimenté", tier3 = "Maître",
  date = "{d}/{m}/{y}", doneShort = "fait", openShort = "ouvert",
  tipDone = "Accompli le %s", tipDoneNoDate = "Accompli", tipOpen = "Pas encore accompli", tipPoints_other = "Vaut %s points",
  tipPoints_one = "Vaut %s point", tipOther = "Obtenu par un autre personnage de ton compte",
  tipTier = "%s · %s", classesUnreadable = "Les défis de classe ne peuvent pas être lus pour l'instant.",
  rewardsHead = "Récompenses de la voie", rewardLevel = "Niveau %s", rewardFallback = "Objet n° %s", rewardUnknown = "Récompense",
  collected = "récupérée", ready = "à récupérer", reached = "atteint",
  missing_one = "encore %s point", missing_other = "encore %s points", tipNeed = "Disponible à partir du niveau %s de la voie de l'héritage",
  rewardsUnreadable = "Les récompenses ne peuvent pas être lues pour l'instant.",
  treesTitle = "Arbres de talents", tree_professions = "Métiers", tree_adventure = "Aventure", tree_progression = "Progression",
  rank = "%s/%s", tipRank = "Rang %s sur %s", unknown = "Inconnu", treeUnreadable = "Cet arbre ne peut pas être lu pour l'instant.",
  treeEmpty = "Aucun nœud trouvé.",
  hintCombat = "Le livre ne lit pas l'héritage pendant un combat. Reviens après le combat.",
  hintUnreadable = "L'héritage ne peut pas être lu pour l'instant. Réessaie dans un instant.",
  reread = "Relire",
  staleCombat = "En combat : état enregistré du {date}", staleUnreadable = "Illisible pour l'instant : état enregistré du {date}",
})

L.add("frFR", "p.Schaetze", {
  toAuktion = "Hôtel des ventes", auktionTip = "Toutes les ventes et tous les achats à l'hôtel des ventes",
  auktionTip2 = "Tableau triable : date, objet, quantité et prix",
})

-- journal/pages/SchaetzeAuktion.lua
L.add("frFR", "p.SchaetzeAuktion", {
  brand = "INK & EMBERS", book = "HÔTEL DES VENTES", page = "BILAN",
  title = "Hôtel des ventes", count_one = "%s facture", count_other = "%s factures", countOf = "%s sur %s factures",
  prevPage = "Page précédente", nextPage = "Page suivante",
  colTime = "Date", colKind = "Type", colItem = "Objet", colCount = "Qté", colPrice = "Total", colUnit = "Unité",
  fAll = "Tout", fSold = "Ventes", fBought = "Achats",
  fAllTip = "Toutes les factures", fSoldTip = "Ventes uniquement", fBoughtTip = "Achats uniquement",
  sortAsc = "Tri : croissant", sortDesc = "Tri : décroissant", headTip = "Clic : trier, nouveau clic : inverser",
  tipCount = "Quantité : %s", tipTotal = "Prix total : %s", tipUnit = "Par pièce : %s", tipFee = "Frais : %s", tipNoPrice = "Prix illisible",
  empty = "Aucune facture de l'hôtel des ventes pour l'instant.",
  emptyBody = "Dès que tu vides ta boîte aux lettres et qu'il y a des factures de ventes ou d'achats, la chronique les note ici.",
  noMatch = "Aucune facture ne correspond à ce filtre.",
  balTitle = "Bilan", balSub = "Toutes les factures, quel que soit le filtre",
  secSold = "Ventes", secBought = "Achats", secSaldo = "Résultat",
  labSoldN = "Objets vendus", labIncome = "Recettes", labFee = "Frais", labBoughtN = "Objets achetés", labSpent = "Dépensé",
  labSaldo = "Solde", saldoPlus = "Gagné plus que dépensé", saldoMinus = "Dépensé plus que gagné", saldoZero = "À l'équilibre",
  balNote = "D'après les factures de ta boîte aux lettres. Les enchères, les dépôts et les ventes expirées n'apparaissent dans aucune facture.",
  noPrice = "–",
})

-- journal/pages/ChronikRueckblick.lua
L.add("frFR", "p.ChronikRueckblick", {
  page = "RÉCAPITULATIF", brand = "INK & EMBERS", title = "Auparavant, dans ton voyage", date = "{d}/{m}/{y}",
  dateRange = "{from} – {to}", preview = "Aperçu", sessions_one = "%s session", sessions_other = "%s sessions",
  standHead = "Où tu en es", openHead = "Ce qui est en cours", noteHead = "En marge", standNone = "Rien de noté pour l'instant.",
  openNone = "Rien n'est en cours pour le moment.", pin = "Épinglée : %s", progress = "%s (%s sur %s)", picCaption = "%s",
  picCaptionDate = "%s · %s", picTipHead = "Le dernier trajet", picTipRange = "%s au %s", building = "La chronique trie encore. Regarde de nouveau dans un instant.",
  empty = "Il ne s'est pas encore passé assez de choses pour un récapitulatif.", notReady = "Le récapitulatif n'est pas encore prêt.",
  doneHead = "Terminé récemment",
  quoted = "« %s »",
  bestLine = "Meilleure trouvaille : %s",
  moreTip = "Tout ce qui reste ouvert",
  picTipQuests_one = "%s quête rendue",
  picTipQuests_other = "%s quêtes rendues",
  picTipAccepts_one = "%s quête acceptée",
  picTipAccepts_other = "%s quêtes acceptées",
  openHere = "Dans les environs",
  openAway = "Ailleurs",
  clickTip = "Clic : afficher dans le journal de quêtes",
  questCombat = "Le journal de quêtes ne s'ouvre pas en combat. Réessaie ensuite.",
  questFailed = "Le journal de quêtes ne peut pas s'ouvrir pour le moment.",
})
