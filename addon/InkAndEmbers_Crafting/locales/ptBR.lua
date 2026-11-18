-- Brazilian Portuguese strings of the module InkAndEmbers_Crafting (moved from the core locales in 1.1.0 by scripts/split-locales.mjs).
-- One L.add block per area, same keys as L.ns in the module's code (deDE is the source in the code).
local _, ns = ...
local L = ns.Locale

-- journal/model/Rezepte.lua and Handwerk.lua (1.0.12 data books)
L.add("ptBR", "m.Rezepte", {
  spellFallback = "Receita %s",
  profFallback = "Profissão %s",
  rankJ = "Oficial", rankE = "Perito", rankA = "Artesão",
  srcT = "Instrutor", srcV = "Vendedor", srcQ = "Missão", srcD = "Saque", srcC = "Fabricação", srcO = "Achado",
  favor = "%s Favor do Mercador",
  repText = "Reputação: %s",
  repFallback = "Reputação com uma facção",
  NO_RECIPES = "Lista de receitas ausente no add-on de dados (reinstale-o)",
  NO_API = "As profissões não podem ser lidas agora",
})

L.add("ptBR", "m.Handwerk", {
  rank_75 = "Aprendiz", rank_150 = "Oficial", rank_225 = "Perito", rank_300 = "Artesão",
})

L.add("ptBR", "m.Rezeptbuch", {
  profFallback = "Profissão %s",
  recipeFallback = "Receita %s",
  diff_orange = "ideal", diff_yellow = "média", diff_green = "fácil", diff_grey = "sem ganho",
})

L.add("ptBR", "p.Handwerk", {
  brand = "INK & EMBERS", book = "PROFISSÕES", page = "OFÍCIOS", title = "Ofícios",
  prof_one = "%s profissão", prof_other = "%s profissões", rec_one = "%s receita", rec_other = "%s receitas",
  listHead = "PROFISSÕES",
  listEmpty = "Nenhuma profissão aprendida ainda. Assim que você aprender uma, a curva dela se escreve aqui sozinha.",
  primary = "Profissão principal", secondary = "Profissão secundária",
  skillOf = "%s / %s",
  skillNow = "Habilidade %s de %s", skillRank = "%s · %s",
  balance = "BALANÇO",
  mined = "minerado", picked = "colhido", skinned = "esfolado", fished = "pescado", crafted = "fabricado",
  minedTip = "Minério e pedra dos veios", pickedTip = "Ervas e flores das plantas",
  skinnedTip = "Couro e peles de inimigos (estimado a partir dos achados)", fishedTip = "Tudo o que ficou preso no anzol",
  craftedTip = "Itens que você mesmo fabricou, inclusive os abaixo da qualidade Incomum",
  balanceEmpty = "Nada coletado nem fabricado ainda.",
  firstCraft = "Primeira fabricação", firstCraftTip = "O primeiro item que você mesmo fabricou, a partir da qualidade Incomum",
  level = "Nível %s",
  curveHead = "HABILIDADE AO LONGO DO TEMPO DE JOGO", recipesHead = "Receitas aprendidas",
  hours = "%s h", minutes = "%s min",
  open = "ainda não", milestoneTip = "Habilidade %s alcançada",
  tipSkill = "Habilidade %s de %s", tipLearned = "Aprendida no nível %s", tipLast = "Último aumento: %s",
  tipWhen = "%s · Nível %s", tipPlay = "Após %s de tempo de jogo",
  noRecipes = "Nenhuma receita aprendida ainda.",
  recipesUnsure = "As receitas desta profissão não podem ser atribuídas com certeza. Você encontra todas no livro de receitas.",
  emptyTitle = "O livro de ofícios ainda está vazio",
  emptyBody = "Aprenda uma profissão, e cada ponto de habilidade, cada receita e cada marco se escreve aqui sozinho.",
  date = "{d}/{m}/{y}",
})

L.add("ptBR", "p.PlaeneHandwerk", {
  brand = "INK & EMBERS", page = "OFÍCIOS",
  fTrainer = "Instrutor", fNow = "Agora", fSoon = "Em breve",
  fTrainerTip = { "Instrutor", "O que um instrutor de profissão ensina a você agora" },
  fNowTip = { "Agora", "Tudo o que você pode aprender com a sua habilidade, inclusive de vendedores, missões e saques" },
  fSoonTip = { "Em breve", "O que os próximos 25 pontos de habilidade trazem" },
  info = "Profissões: %s · %s agora · %s em breve",
  skillWord = "Habilidade %s",
  free = "grátis",
  sNow = "agora", sSoon = "em %s pontos", sLevel = "a partir do nível %s", sLater = "a partir da habilidade %s", sLearned = "aprendida",
  learnable = "aprendível com o instrutor",
  costLine = "Custo do treinamento %s · nas suas bolsas %s",
  costNone = "O instrutor de profissão não tem nada de novo para você agora.",
  short = "Ainda faltam %s para você.", enough = "Suas bolsas cobrem tudo.",
  profHead = "Suas profissões",
  profLine = "%s %s/%s · %s agora · %s em breve",
  profLineNoMax = "%s %s · %s agora · %s em breve",
  todoOn = "A tarefa “Ao instrutor de profissão” está na sua lista.",
  todoOff = "Assim que um instrutor tiver algo novo para você, o Ink adiciona “Ao instrutor de profissão” à sua lista de tarefas.",
  retailHead = "Somente WoW Forever",
  retailBody = "Os dados de receitas são do WoW Forever. Esta folha fica vazia no Retail.",
  noDataHead = "Sem dados de receitas",
  noProfHead = "Ainda sem profissão",
  noProfBody = "Aprenda uma profissão. Esta folha mostra então quais receitas vêm a seguir.",
  noProfDataHead = "Sem receitas para as suas profissões",
  noProfDataBody = "Não há dados de receitas para as suas profissões.",
  noApiBody = "Suas profissões não podem ser lidas agora. Tente de novo daqui a pouco.",
  emptyTrainer = "O instrutor de profissão não tem nada de novo agora. Mais habilidade traz novas receitas.",
  emptyNow = "Não há nada para aprender agora.",
  emptySoon = "Nada de novo nos próximos 25 pontos.",
  prevPage = "Página anterior", nextPage = "Próxima página",
  tipSource = "Fonte: %s", tipCost = "Preço: %s", tipLevel = "Requer nível %s", tipRank = "Grau da profissão: %s",
  tipFavor = "Favor do Mercador: %s", tipNeed = "Mais %s pontos de habilidade",
})

L.add("ptBR", "p.Handwerk", {
  subBerufe = "Profissões", subBerufeTip = "Curva de habilidade, marcos e balanço das suas profissões",
  subRezept = "Livro de receitas", subRezeptTip = "Todas as receitas das suas profissões, aprendidas e ainda abertas, com materiais (só WoW Forever)",
})

-- journal/pages/HandwerkRezeptbuch.lua (change "runde3", package R)
L.add("ptBR", "p.HandwerkRezeptbuch", {
  brand = "INK & EMBERS", book = "LIVRO DE RECEITAS", page = "OFÍCIOS",
  title = "Livro de receitas", sub = "Todas as receitas das suas profissões, aprendidas e ainda abertas",
  listHead = "PROFISSÕES", recipesHead = "RECEITAS",
  fAll = "Todas", fLearned = "Aprendidas", fOpen = "Abertas",
  fAllTip = { "Todas", "Receitas aprendidas e ainda não aprendidas" },
  fLearnedTip = { "Aprendidas", "Só as receitas que você já conhece" },
  fOpenTip = { "Abertas", "Só as receitas que ainda faltam" },
  profSub = "Habilidade %s de %s", profSubNoMax = "Habilidade %s",
  profCount = "%s de %s", profNoCount = "–",
  countLine = "%s aprendidas · %s abertas",
  hintNoCache = "Abra a janela da profissão uma vez para o livro conhecer todos os detalhes.",
  hintCache = "No estado da última vez que você abriu a janela da profissão. Receitas recém-aprendidas aparecem quando você a abre de novo.",
  legend = "Cor:",
  learned = "aprendida", open = "aberta", fromSkill = "a partir de %s",
  skillWord = "Habilidade %s",
  tipSource = "Origem: %s", tipDifficulty = "Dificuldade: %s", tipUps = "Pontos de habilidade por fabricação: até %s",
  tipCost = "Preço: %s", tipStock = "Nas bolsas: %s · Banco: %s",
  tipNeeds = "Precisa de: %s", tipMore = "Clique: detalhes abaixo",
  needs = "PRECISA DE", output = "Fabrica: %s", outputQty = "Fabrica: %s× %s",
  noMats = "Esta receita não precisa de materiais.",
  detailNoCache = "O livro só conhece o resultado e os materiais depois que você abrir a janela da profissão.",
  moreMats = "… e mais %s",
  itemNo = "Item nº %s",
  pick = "Escolha uma receita.",
  emptyList = "Ainda não há receitas para esta profissão.",
  emptyFilterLearned = "Nenhuma receita aprendida ainda.", emptyFilterOpen = "Todas as receitas desta profissão estão aprendidas.",
  noProfTitle = "Ainda nenhuma profissão com receitas",
  noProfBody = "Aprenda uma profissão. Esta folha mostrará então todas as receitas dela, aprendidas e abertas.",
  prevPage = "Página anterior", nextPage = "Próxima página",
})

-- journal/WerkBarKit.lua (Werkauftrag, 1.1.0)
L.add("ptBR", "WerkBarKit", {
  stepPlan = "Planejar",
  stepBuy = "Comprar",
  stepMake = "Fabricar",
  afterCombat = "Depois do combate",
  goldShort = "Faltam %s",
  busy = "Um momento …",
})
