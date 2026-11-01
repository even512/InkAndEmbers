Eingebettete Bibliotheken (unveraendert uebernommen, nicht anpassen)
=====================================================================

LibEditMode  (libs/LibEditMode/)
  Quelle:   https://github.com/p3lim-wow/LibEditMode
  Version:  Tag 18 (MINOR = 18), Commit 550a52e7a0a56649d962c3fa2ceccaf50c3c77ed vom 28.09.2026
  Client:   Interface 120100, 120105, 16001, 20506, 50504 (laut LibEditMode.toc)
  Lizenz:   libs/LibEditMode/LICENSE.txt (p3lim, "All rights reserved" mit Erlaubnis zum Einbetten in ein
            WoW-AddOn, solange die Dateien unveraendert bleiben; Weglassen von Dateien ist erlaubt).
  Uebernommen: LibEditMode.lua, pools.lua, embed.xml, widgets/*.lua, LICENSE.txt.
  Weggelassen: LibEditMode.toc, namespaced.lua, README.md, tests/, utils/ (nicht noetig fuer die Einbettung).
  Geladen ueber libs\LibEditMode\embed.xml in der TOC (nur der Client; die Lua-Attrappe der Tests laedt sie nicht).

LibStub  (libs/LibStub/LibStub.lua)
  Quelle:   https://repos.curseforge.com/wow/libstub/trunk/LibStub.lua
  Version:  LIBSTUB_MINOR = 2
  Lizenz:   Public Domain (siehe Kopf der Datei)

Genutzt von journal/EditMode.lua (HUD-Elemente im Bearbeitungsmodus). Fehlt LibEditMode oder der
Bearbeitungsmodus des Clients, bleibt alles wie vorher (eigene Lage und Zahnrad-Einstellungen).
Neue Version: Dateien ersetzen, Version oben nachtragen, Tests laufen lassen.

LibSharedMedia-3.0  (libs/LibSharedMedia-3.0/)
  Quelle:   https://repos.wowace.com/wow/libsharedmedia-3-0/trunk/LibSharedMedia-3.0/ (abgerufen 30.10.2026)
  Version:  MINOR = 12000005 ("12.0.0 v5")
  Lizenz:   LGPL v2.1 (Kopf der Datei); Lizenztext libs/LibSharedMedia-3.0/LICENSE.txt
            (https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt). Unveraendert eingebettet.
  Uebernommen: LibSharedMedia-3.0.lua, lib.xml. Weggelassen: .toc, tests/, .pkgmeta.
  Geladen ueber libs\LibSharedMedia-3.0\lib.xml in der TOC (nur der Client).

CallbackHandler-1.0  (libs/CallbackHandler-1.0/), von LibSharedMedia-3.0 benoetigt
  Quelle:   https://repos.wowace.com/wow/callbackhandler/trunk/CallbackHandler-1.0/ (abgerufen 30.10.2026)
  Version:  MINOR = 8
  Lizenz:   Ace3-Lizenz (BSD-artig, Weitergabe nur eingebettet, nicht als Einzelpaket);
            libs/CallbackHandler-1.0/LICENSE.txt (https://repos.wowace.com/wow/ace3/trunk/LICENSE.txt).
  Uebernommen: CallbackHandler-1.0.lua, CallbackHandler-1.0.xml.
  Geladen ueber libs\CallbackHandler-1.0\CallbackHandler-1.0.xml in der TOC (vor LibSharedMedia).

Genutzt von journal/Sound.lua und journal/Options.lua (Klangauswahl im Einstellungsmenue, Gruppe "Klänge"): die Sound-Liste
von LibSharedMedia wird beim Oeffnen des Menues gelesen, spaeter registrierte Klaenge melden sich ueber den Callback
LibSharedMedia_Registered. Fehlt die Bibliothek, gibt es nur Spielklaenge und eigene Klaenge.
