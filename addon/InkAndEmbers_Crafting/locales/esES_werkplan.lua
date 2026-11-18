-- Spanish strings of the Werkauftrag: to-do, trackers and book entries of the work order, stage W4. Registered empty in stage W1, filled by its stage.
-- One L.add block per area, same keys as L.ns in the module's code (deDE is the source in the code).
local _, ns = ...
local L = ns.Locale

L.add("esES", "WerkPlan", {
  rowAdd = "+ Encargo",
  rowOpen = "Encargo: %s×",
  rowTip = "Encargo",
  rowTip2 = "Pone esta receta en tu lista de tareas como encargo. Compras los materiales en la casa de subastas y fabricas en la mesa de trabajo.",
  rowTipOpen = "El encargo está en tu lista de tareas. Un clic muestra dónde continúa.",
  created = "Encargo creado: %s. Compra los materiales en la casa de subastas y fabrica en la ventana de oficio.",
  failed = "No se pudo crear el encargo.",
})
