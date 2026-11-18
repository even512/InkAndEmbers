-- Brazilian Portuguese strings of the module InkAndEmbers_Quests (moved from the core locales in 1.1.0 by scripts/split-locales.mjs).
-- One L.add block per area, same keys as L.ns in the module's code (deDE is the source in the code).
local _, ns = ...
local L = ns.Locale

L.add("ptBR", "p.QuestsOffen", {
  brand = "INK & EMBERS", book = "LIVRO DE MISSÕES", page = "MISSÕES DISPONÍVEIS",
  allZones = "Todas as zonas", zoneTip = "Escolha uma zona", zoneTip2 = "Número = missões disponíveis nesta zona",
  locked = "Bloqueadas", lockedTip = { "Mostrar missões bloqueadas", "Missões que você ainda não pode aceitar aparecem em cinza com o motivo." },
  group = "Grupo", groupTip = { "Missões de grupo, masmorra, raide, PvP e evento", "Padrão: ocultas" },
  repeatable = "Repetíveis", repeatTip = { "Missões repetíveis", "Padrão: ocultas" },
  class = "Classe", classTip = { "Missões de classe", "Padrão: exibidas" },
  category = "Profissão", categoryTip = { "Missões de profissão e de outras categorias de coleta", "Padrão: ocultas" },
  open = "disponíveis", lockedCount = "bloqueadas", hidden = "ocultas",
  empty = "Nenhuma missão disponível nesta zona.", emptyAll = "Nenhuma missão disponível encontrada.",
  noData = "Dados de missões não carregados", noDataHint = "Verifique com /chronik diag",
  noDataRight = "O mapa aparecerá assim que os dados de missões forem carregados.",
  retailHead = "Mapa-múndi sem ofertas de missões", retailRight = "Sem a interface do mapa-múndi do jogo, não há mapa aqui.",
  retailHint = "Do mapa-múndi do jogo: somente missões que você pode aceitar, sem responsáveis ou motivos de bloqueio",
  retailLoading = "Carregando missões do mapa-múndi do jogo …",
  retailCombat = "Em combate – o mapa-múndi será consultado depois.",
  retailEmpty = "O mapa-múndi do jogo não mostra missões que você possa aceitar aqui agora.",
  retailEmptyAll = "O mapa-múndi do jogo não mostra missões que você possa aceitar nas zonas carregadas.",
  lineWord = "Série de missões: ",
  noMap = "O cliente não fornece um mapa para esta área.", noMapTest = "Modo de teste: esta zona não tem mapa no Retail.",
  unplaced = "%d zonas sem posição neste mapa",
  pick = "Escolha uma missão à esquerda ou clique em um ! no mapa.",
  levelWord = "Nível ", levelUnknown = "Nível ?", minWord = "Requer nível ",
  toTodo = "Adicionar à lista de tarefas", toTodoTip = { "Adicionar à lista de tarefas", "Adiciona um objetivo de local no responsável pela missão (Jornada -> Tarefas)." },
  todoDone = "Tarefa adicionada.", todoFail = "Nenhuma tarefa adicionada: ", todoNoPlace = "Responsável pela missão sem ponto no mapa",
  todoReasons = { voll = "Lista de tarefas cheia", ["nicht-bereit"] = "Lista de tarefas ainda não está pronta", ["kein-plan"] = "Lista de tarefas indisponível",
    ["kein-ort"] = "Responsável pela missão sem ponto no mapa" },
  zoneTipOpen = "disponíveis", zoneTipLocked = "bloqueadas", zoneTipClick = "Clique: abrir zona",
  pinTipClick = "Clique: mostrar na lista", pinLocked = "(bloqueada)",
  giverWord = "Responsável pela missão: ", noGiver = "Responsável pela missão desconhecido",
  more = " e mais %d",
  prevPage = "Página anterior", nextPage = "Próxima página",
})
