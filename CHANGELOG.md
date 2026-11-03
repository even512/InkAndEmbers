# Changelog

## 0.9.4

### New
- **Data safety:** every character's data is now also mirrored into a second file that belongs to that character
  (`WTF/Account/<ACCOUNT>/<Realm>/<Character>/SavedVariables/InkAndEmbers.lua`). If the main file is missing, damaged or
  holds an older state when you log in, the character is restored from its copy automatically, without losing a line.
  Newer data is never replaced by older data, and a differing older state is kept aside instead of being deleted.
  Tips for keeping your own backup are in the README under "Keeping your data safe".
- **`/chronik backup`:** shows the state of your data safety: when this character's copy was last written, the last save,
  how full the main file is and the last restore. (`/chronik sicherung` works too.)
- **Warnings:** a window tells you when data was restored, when the data of other characters is missing from the main file,
  or when the add-on found no saved data for a character that is clearly not new. It says what to do (do not log out, copy
  the `.bak` file). The add-on also keeps an eye on the size of the main file and warns long before the game could no longer
  load it.
- **Save reminder:** the reminder to save now comes every 30 minutes instead of 60, and also when you take off on a flight
  or gain a level (at least 10 minutes after the last save, never in combat or in an instance).

### Changes
- Errors: if one part of the add-on runs into errors, only that part pauses for a few minutes and then carries on, instead
  of being switched off for the rest of the session. `/chronik status` and `/chronik diag` name paused parts.
- Every session now notes which version of the add-on recorded it, which makes bug reports easier to follow.
- More is recorded for your journal: game rules of your character (WoW Forever experience setting, Hardcore, game mode),
  your pet (summoned, dismissed, tamed, stable slots), loot rolls, spells cast, jumps, PvP flag, gear durability, day or
  night, quest details (elite, group size) and a few more character values.

### Fixes
- A damaged value in the saved file is no longer thrown away and replaced by an empty one; it is kept aside so nothing is
  lost.
- The add-on version written into the saved file is now the real version instead of a placeholder.

## 0.9.3

### New
- **Training (WoW Forever):** new "Training" tab under Quests. It lists what your class trainer teaches at which
  level, marks what you already know, sums up what you can learn now against the gold in your bags, and shows the
  next levels, free talent points, the training fees paid so far and the nearest trainer you have visited ("As to-do"
  adds a place goal). After a level-up with new spells, a "To the trainer" to-do appears and ticks itself off once
  everything is learned (setting under To Do). Free talent points get a small pop-up once per level or session
  (setting under Pop-ups). `/chronik training` opens the tab, `training status` prints the state. Off on Retail.
- **Open quests in Retail:** the list and map pins now come from the game's own world map (quests you can accept
  right now, shown by quest line). Quest givers and locked quests with reasons are not available in Retail.
- **Away time (AFK):** the chronicle now tracks the time you spend marked as away. The profile card shows the total
  with a tooltip for breaks and the longest break, and the Moments page lists it under Curiosities. Reloads continue
  a break; logging out or a crash ends it cleanly.
- **Gold holdings:** the gold flow chart in Treasures has a new "Holdings" view showing the most gold you held in your
  purse at each level, as a staircase with the all-time peak highlighted and the biggest jump between two levels.
  It also works for levels you have already played.

### Changes
- Moments page: moments are now small handwritten diary notes instead of polaroid pictures. Each note shows the
  symbol of its kind, the title, a short diary line and the day and time in handwriting, slightly tilted and taped
  into the album. Collecting, the filter chips, paging, tooltips, the play-time clock, the library and curiosities
  work as before. The polaroid picture files were removed from the add-on, which makes the download smaller.
- Journey: short zone visits without anything of note no longer start a new chapter. They are listed as
  "Detours: X, Y" in the running chapter, their trail is still drawn, and returning simply continues the chapter.
  A visit becomes a chapter once something happens there (kill, quest, level, death, discovery, instance, notable
  find, ...). Applies to existing journeys too.
- Retail: the max level is read from the client (80/90) - level ring, "Journey's End" medal, forecast, chapter
  highlight and gear timeline now go up to it; WoW Forever stays at 60.
- Retail: the campfire conversation options, tutorial page and the Chronicle "By the Fire" tab are hidden, since the
  conversation never starts there.
- Retail: WoW Forever-only parts (trainer plan tab, trainer to-do and talent hint options) are hidden, and the
  introduction no longer mentions level 60 or the campfire.
- Retail: the foe/item search for to-dos now shows names only; level and zone from the Classic/Forever data are
  hidden there. Kill and loot goals still count and complete as before.
- Retail detection now also checks the interface version, so WoW Forever is never mistaken for Retail.

### Fixes
- Journey map: the route line no longer breaks or jumps when you cross between a zone and a neighbouring or sub-area
  map (e.g. leaving Deathknell), and it now runs seamlessly up to your arrow instead of lagging behind it.
- Medals already earned by a character's existing state on its first login with the add-on (gold, level, professions,
  guild, gear) are added quietly to the book instead of popping a toast.
- The welcome tutorial's first picture (minimap button) still showed the old minimap icon with the "W"; it now shows
  the current book icon.

## 0.9.2

### Changed
- Retail: the "Open" tab under Quests is turned off in the Retail client and shows a short note instead. Its quest
  data comes from WoW Forever (classic quests) and does not match the reworked retail zones, so the list would show
  quests that no longer exist there. The quest data add-on is no longer loaded in Retail at all.
  WoW Forever is not affected.
- A Retail source for open quests, based on the game's own quest information, is planned for a later version.

## 0.9.1

### New
- The quick note field and the to-do note now each have a small close button ("x") in the top right corner of their
  header. It hides only that note; the other one stays where it is. Bring it back with `/chronik note` or
  `/chronik todo`, or in the add-on settings (Options > AddOns > Ink & Embers).

### Changed
- First regular release: the version no longer carries a "beta" suffix.
- The README now links to the CurseForge project page.

## 0.9.0-beta1 (first public beta)

First public version of Ink & Embers: An Adventurer's Journal: a leveling journal that records your journey while you play.

### What it does
- Records the leveling journey in the background: level-ups, kills and fights, deaths, quests and quest text,
  discoveries, flight paths and travel, instances and bosses, loot, gear changes, gold, professions, reputation,
  talents, groups and guild events, and campfire company. Data is stored per character in the account-wide
  saved variable `EveNChronicleDB`.
- Travel journal (`/chronik`): a book with the pages Journey (map and chapters per zone), Chronicle, Quests,
  Treasures, Moments, Combat and Notes, with polaroid-style moment pictures, medals and seals.
- Open quests: lists the quests you can still pick up, with quest givers on the map (optional data add-ons, see below).
- To-do list on the screen edge: free goals, places, enemies and items; enemy tooltips and the map help you find them.
  The enemy, item and zone search uses English names when the add-on language is English, German names otherwise.
- Quick note field and notes with markup; pop-up toasts for new medals and areas; welcome card and a short
  introduction book (`/chronik tutorial`).
- HUD elements can be moved in the game's Edit Mode.
- English and German (`/chronik language auto|de|en`).

### Game versions
- WoW Forever (Interface 16001) and Retail (Interface 120105) from one download.

### Included add-ons (separate folders in the zip)
- `InkAndEmbers` - the main add-on (MIT license; graphics and media: all rights reserved, see `LICENSE`).
- `InkAndEmbers_QuestData` - quest list and quest givers, loaded on demand (GPL-3.0, data derived from QuestieDB).
- `InkAndEmbers_Data` - enemy and item lists for the to-do goals, loaded on demand (GPL-3.0, data derived from QuestieDB).

### Notes
- This is a beta. Please report errors with the exact message (`/console scriptErrors 1` shows Lua errors).
- Part of the artwork was created with AI tools (Google Gemini) and edited by the author.
- Third-party components and their licenses are listed in `THIRD-PARTY.md`.
