-- Italian strings of the Werkauftrag: to-do, trackers and book entries of the work order, stage W4. Registered empty in stage W1, filled by its stage.
-- One L.add block per area, same keys as L.ns in the module's code (deDE is the source in the code).
local _, ns = ...
local L = ns.Locale

L.add("itIT", "WerkPlan", {
  rowAdd = "+ Ordine",
  rowOpen = "Ordine: %s×",
  rowTip = "Ordine di lavoro",
  rowTip2 = "Mette questa ricetta nella tua lista di cose da fare come ordine di lavoro. I materiali si comprano alla casa d'aste, si crea al banco di lavoro.",
  rowTipOpen = "L'ordine di lavoro è nella tua lista. Un clic mostra dove prosegue.",
  created = "Ordine di lavoro creato: %s. Compra i materiali alla casa d'aste e crea nella finestra del mestiere.",
  failed = "Impossibile creare l'ordine di lavoro.",
})
