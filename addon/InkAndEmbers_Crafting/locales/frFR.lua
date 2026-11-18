-- French strings of the module InkAndEmbers_Crafting (moved from the core locales in 1.1.0 by scripts/split-locales.mjs).
-- One L.add block per area, same keys as L.ns in the module's code (deDE is the source in the code).
local _, ns = ...
local L = ns.Locale

-- journal/model/Rezepte.lua and Handwerk.lua (1.0.12 data books)
L.add("frFR", "m.Rezepte", {
  spellFallback = "Recette %s",
  profFallback = "Métier %s",
  rankJ = "Compagnon", rankE = "Expert", rankA = "Artisan",
  srcT = "Instructeur", srcV = "Marchand", srcQ = "Quête", srcD = "Butin", srcC = "Fabrication", srcO = "Trouvaille",
  favor = "%s Faveur du marchand",
  repText = "Réputation : %s",
  repFallback = "Réputation auprès d'une faction",
  NO_RECIPES = "Liste de recettes absente de l'add-on de données (à réinstaller)",
  NO_API = "Les métiers ne sont pas lisibles pour le moment",
})

L.add("frFR", "m.Handwerk", {
  rank_75 = "Apprenti", rank_150 = "Compagnon", rank_225 = "Expert", rank_300 = "Artisan",
})

L.add("frFR", "m.Rezeptbuch", {
  profFallback = "Métier %s",
  recipeFallback = "Recette %s",
  diff_orange = "optimale", diff_yellow = "moyenne", diff_green = "facile", diff_grey = "sans gain",
})

L.add("frFR", "p.Handwerk", {
  brand = "INK & EMBERS", book = "MÉTIERS", page = "ARTISANAT", title = "Artisanat",
  prof_one = "%s métier", prof_other = "%s métiers", rec_one = "%s recette", rec_other = "%s recettes",
  listHead = "MÉTIERS",
  listEmpty = "Aucun métier appris pour l'instant. Dès que tu en apprends un, sa courbe s'écrit ici toute seule.",
  primary = "Métier principal", secondary = "Métier secondaire",
  skillOf = "%s / %s",
  skillNow = "Compétence %s sur %s", skillRank = "%s · %s",
  balance = "BILAN",
  mined = "miné", picked = "cueilli", skinned = "dépecé", fished = "pêché", crafted = "fabriqué",
  minedTip = "Minerai et pierre des filons", pickedTip = "Herbes et fleurs des plantes",
  skinnedTip = "Cuir et peaux des ennemis (estimé d'après les trouvailles)", fishedTip = "Tout ce qui s'est pris à l'hameçon",
  craftedTip = "Objets que tu as fabriqués toi-même, y compris ceux de qualité inférieure à Inhabituel",
  balanceEmpty = "Rien encore récolté ni fabriqué.",
  firstCraft = "Première fabrication", firstCraftTip = "Le premier objet que tu as fabriqué toi-même, à partir de la qualité Inhabituel",
  level = "Niveau %s",
  curveHead = "COMPÉTENCE SELON LE TEMPS DE JEU", recipesHead = "Recettes apprises",
  hours = "%s h", minutes = "%s min",
  open = "pas encore", milestoneTip = "Compétence %s atteinte",
  tipSkill = "Compétence %s sur %s", tipLearned = "Appris au niveau %s", tipLast = "Dernière hausse : %s",
  tipWhen = "%s · Niveau %s", tipPlay = "Après %s de temps de jeu",
  noRecipes = "Aucune recette apprise pour l'instant.",
  recipesUnsure = "Les recettes de ce métier ne peuvent pas être attribuées avec certitude. Tu les trouveras toutes dans le livre de recettes.",
  emptyTitle = "Le livre d'artisanat est encore vide",
  emptyBody = "Apprends un métier, et chaque point de compétence, chaque recette et chaque étape s'écrit ici tout seul.",
  date = "{d}/{m}/{y}",
})

L.add("frFR", "p.PlaeneHandwerk", {
  brand = "INK & EMBERS", page = "ARTISANAT",
  fTrainer = "Instructeur", fNow = "Maintenant", fSoon = "Bientôt",
  fTrainerTip = { "Instructeur", "Ce qu'un instructeur de métier t'enseigne tout de suite" },
  fNowTip = { "Maintenant", "Tout ce que tu peux apprendre avec ta compétence, y compris chez les marchands, par quêtes et sur le butin" },
  fSoonTip = { "Bientôt", "Ce qu'apportent les 25 prochains points de compétence" },
  info = "Métiers : %s · %s maintenant · %s bientôt",
  skillWord = "Compétence %s",
  free = "gratuit",
  sNow = "maintenant", sSoon = "dans %s points", sLevel = "à partir du niveau %s", sLater = "à partir de la compétence %s", sLearned = "appris",
  learnable = "apprenable chez l'instructeur",
  costLine = "Coût de l'entraînement %s · dans tes sacs %s",
  costNone = "L'instructeur de métier n'a rien de nouveau pour toi pour le moment.",
  short = "Il te manque encore %s.", enough = "Ta bourse couvre tout.",
  profHead = "Tes métiers",
  profLine = "%s %s/%s · %s maintenant · %s bientôt",
  profLineNoMax = "%s %s · %s maintenant · %s bientôt",
  todoOn = "La tâche « Chez l'instructeur de métier » figure sur ta liste.",
  todoOff = "Dès qu'un instructeur a du nouveau pour toi, Ink ajoute « Chez l'instructeur de métier » à ta liste de tâches.",
  retailHead = "WoW Forever uniquement",
  retailBody = "Les données de recettes sont celles de WoW Forever. Cette feuille reste vide sur Retail.",
  noDataHead = "Pas de données de recettes",
  noProfHead = "Pas encore de métier",
  noProfBody = "Apprends un métier. Cette feuille montre ensuite quelles recettes viennent après.",
  noProfDataHead = "Pas de recettes pour tes métiers",
  noProfDataBody = "Il n'y a pas de données de recettes pour tes métiers.",
  noApiBody = "Tes métiers ne sont pas lisibles pour le moment. Réessaie dans un instant.",
  emptyTrainer = "L'instructeur de métier n'a rien de nouveau pour le moment. Plus de compétence apporte de nouvelles recettes.",
  emptyNow = "Rien n'est apprenable pour le moment.",
  emptySoon = "Rien de nouveau dans les 25 prochains points.",
  prevPage = "Page précédente", nextPage = "Page suivante",
  tipSource = "Source : %s", tipCost = "Prix : %s", tipLevel = "Niveau %s requis", tipRank = "Rang du métier : %s",
  tipFavor = "Faveur du marchand : %s", tipNeed = "%s points de compétence en plus",
})

L.add("frFR", "p.Handwerk", {
  subBerufe = "Métiers", subBerufeTip = "Courbe de compétence, étapes et bilan de tes métiers",
  subRezept = "Livre de recettes", subRezeptTip = "Toutes les recettes de tes métiers, apprises et encore ouvertes, avec les matériaux (WoW Forever uniquement)",
})

-- journal/pages/HandwerkRezeptbuch.lua (change "runde3", package R)
L.add("frFR", "p.HandwerkRezeptbuch", {
  brand = "INK & EMBERS", book = "LIVRE DE RECETTES", page = "ARTISANAT",
  title = "Livre de recettes", sub = "Toutes les recettes de tes métiers, apprises et encore ouvertes",
  listHead = "MÉTIERS", recipesHead = "RECETTES",
  fAll = "Toutes", fLearned = "Apprises", fOpen = "Ouvertes",
  fAllTip = { "Toutes", "Recettes apprises et pas encore apprises" },
  fLearnedTip = { "Apprises", "Seulement les recettes que tu connais déjà" },
  fOpenTip = { "Ouvertes", "Seulement les recettes qui te manquent encore" },
  profSub = "Compétence %s sur %s", profSubNoMax = "Compétence %s",
  profCount = "%s sur %s", profNoCount = "–",
  countLine = "%s apprises · %s ouvertes",
  hintNoCache = "Ouvre une fois ta fenêtre de métier pour que le livre connaisse tous les détails.",
  hintCache = "Dans l'état de ta dernière ouverture de la fenêtre de métier. Les recettes récemment apprises apparaissent quand tu la rouvres.",
  legend = "Couleur :",
  learned = "apprise", open = "ouverte", fromSkill = "dès %s",
  skillWord = "Compétence %s",
  tipSource = "Source : %s", tipDifficulty = "Difficulté : %s", tipUps = "Points de compétence par fabrication : jusqu'à %s",
  tipCost = "Prix : %s", tipStock = "Dans les sacs : %s · Banque : %s",
  tipNeeds = "Requiert : %s", tipMore = "Clic : détails ci-dessous",
  needs = "REQUIERT", output = "Fabrique : %s", outputQty = "Fabrique : %s× %s",
  noMats = "Cette recette ne requiert aucun matériau.",
  detailNoCache = "Le livre ne connaît le résultat et les matériaux qu'après l'ouverture de ta fenêtre de métier.",
  moreMats = "… et %s de plus",
  itemNo = "Objet n° %s",
  pick = "Choisis une recette.",
  emptyList = "Il n'y a pas encore de recettes pour ce métier.",
  emptyFilterLearned = "Aucune recette apprise pour l'instant.", emptyFilterOpen = "Toutes les recettes de ce métier sont apprises.",
  noProfTitle = "Pas encore de métier avec des recettes",
  noProfBody = "Apprends un métier. Cette feuille montrera alors toutes ses recettes, apprises et ouvertes.",
  prevPage = "Page précédente", nextPage = "Page suivante",
})

-- journal/WerkBarKit.lua (Werkauftrag, 1.1.0)
L.add("frFR", "WerkBarKit", {
  stepPlan = "Planifier",
  stepBuy = "Acheter",
  stepMake = "Fabriquer",
  afterCombat = "Après le combat",
  goldShort = "Il vous manque %s",
  busy = "Un instant …",
})
