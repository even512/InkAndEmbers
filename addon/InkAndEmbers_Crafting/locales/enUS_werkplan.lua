-- English strings of the Werkauftrag: to-do, trackers and book entries of the work order, stage W4. Registered empty in stage W1, filled by its stage.
-- One L.add block per area, same keys as L.ns in the module's code (deDE is the source in the code).
local _, ns = ...
local L = ns.Locale

L.add("enUS", "WerkPlan", {
  rowAdd = "+ Work order",
  rowOpen = "Work order: %s×",
  rowTip = "Work order",
  rowTip2 = "Puts this recipe on your to-do as a work order. You buy the materials at the auction house and craft at the workbench.",
  rowTipOpen = "The work order is on your to-do. Click shows where it goes on.",
  created = "Work order created: %s. Buy the materials at the auction house, craft at the profession window.",
  failed = "The work order could not be created.",
})
