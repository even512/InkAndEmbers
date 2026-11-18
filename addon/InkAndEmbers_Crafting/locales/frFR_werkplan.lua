-- French strings of the Werkauftrag: to-do, trackers and book entries of the work order, stage W4. Registered empty in stage W1, filled by its stage.
-- One L.add block per area, same keys as L.ns in the module's code (deDE is the source in the code).
local _, ns = ...
local L = ns.Locale

L.add("frFR", "WerkPlan", {
  rowAdd = "+ Commande",
  rowOpen = "Commande : %s×",
  rowTip = "Commande",
  rowTip2 = "Place cette recette sur votre liste de tâches comme commande. Le matériel s'achète à l'hôtel des ventes, la fabrication se fait à l'établi.",
  rowTipOpen = "La commande est sur votre liste de tâches. Un clic montre où elle continue.",
  created = "Commande créée : %s. Achetez le matériel à l'hôtel des ventes, fabriquez dans la fenêtre de métier.",
  failed = "La commande n'a pas pu être créée.",
})
