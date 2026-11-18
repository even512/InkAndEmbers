-- Brazilian Portuguese strings of the Werkauftrag: to-do, trackers and book entries of the work order, stage W4. Registered empty in stage W1, filled by its stage.
-- One L.add block per area, same keys as L.ns in the module's code (deDE is the source in the code).
local _, ns = ...
local L = ns.Locale

L.add("ptBR", "WerkPlan", {
  rowAdd = "+ Ordem",
  rowOpen = "Ordem: %s×",
  rowTip = "Ordem de trabalho",
  rowTip2 = "Coloca esta receita na sua lista de tarefas como ordem de trabalho. Os materiais são comprados na casa de leilões e a fabricação é feita na bancada.",
  rowTipOpen = "A ordem de trabalho está na sua lista de tarefas. Um clique mostra onde ela continua.",
  created = "Ordem de trabalho criada: %s. Compre os materiais na casa de leilões e fabrique na janela da profissão.",
  failed = "Não foi possível criar a ordem de trabalho.",
})
