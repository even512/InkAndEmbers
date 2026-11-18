-- Portuguese (Brazil) strings of the module InkAndEmbers_QuestTracker. Only the pinned-quest texts are translated so far (the
-- rest of the module falls back to English through Locale.FALLBACK).
local _, ns = ...
local L = ns.Locale

-- journal/QuestTracker.lua + journal/QuestPin.lua (pinned quest): only these texts so far, the rest falls back to English
L.add("ptBR", "QuestTracker", {
  sPin = "Missão fixada",
  pAuto = "Fixar automaticamente ao progredir",
  pIdle = "Soltar automaticamente após",
  pIdleMin = "%d min",
  pinLabel = "Fixada",
  pinAutoLabel = "Fixada automaticamente",
  pinDone = "Pronto!",
  pinMenu = "Fixar",
  pinFix = "Fixar de vez",
  unpinMenu = "Desafixar",
})
