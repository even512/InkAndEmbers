-- Russian strings of the Werkauftrag: to-do, trackers and book entries of the work order, stage W4. Registered empty in stage W1, filled by its stage.
-- One L.add block per area, same keys as L.ns in the module's code (deDE is the source in the code).
local _, ns = ...
local L = ns.Locale

L.add("ruRU", "WerkPlan", {
  rowAdd = "+ Заказ",
  rowOpen = "Заказ: %s×",
  rowTip = "Заказ",
  rowTip2 = "Добавляет этот рецепт в ваши задачи как заказ. Материалы покупаются на аукционе, создание – у верстака.",
  rowTipOpen = "Заказ есть в ваших задачах. Щелчок покажет, где он продолжается.",
  created = "Заказ создан: %s. Купите материалы на аукционе, создайте предмет в окне профессии.",
  failed = "Не удалось создать заказ.",
})
