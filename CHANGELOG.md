# Changelog

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
