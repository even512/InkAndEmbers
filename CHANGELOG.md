# Changelog

## 0.9.0-beta1 (first public beta)

First public version of EveN Forever Chronicle: a leveling journal that records your journey while you play.

### What it does
- Records the leveling journey in the background: level-ups, kills and fights, deaths, quests and quest text,
  discoveries, flight paths and travel, instances and bosses, loot, gear changes, gold, professions, reputation,
  talents, groups and guild events, and campfire company. Data is stored per character in the account-wide
  saved variable `EveNChronicleDB`.
- Travel journal (`/chronik`): a book with the pages Journey (map and chapters per zone), Chronicle, Quests,
  Treasures, Moments, Combat and Notes, with polaroid-style moment pictures, medals and seals.
- Open quests: lists the quests you can still pick up, with quest givers on the map (optional data add-ons, see below).
- To-do list on the screen edge: free goals, places, enemies and items; enemy tooltips and the map help you find them.
- Quick note field and notes with markup; pop-up toasts for new medals and areas; welcome card and a short
  introduction book (`/chronik tutorial`).
- HUD elements can be moved in the game's Edit Mode.
- English and German (`/chronik language auto|de|en`).

### Game versions
- WoW Forever (Interface 16001) and Retail (Interface 120105) from one download.

### Included add-ons (separate folders in the zip)
- `EveN_ForeverChronicle` - the main add-on (MIT license; graphics and media: all rights reserved, see `LICENSE`).
- `EveN_ForeverChronicle_QuestData` - quest list and quest givers, loaded on demand (GPL-3.0, data derived from QuestieDB).
- `EveN_ForeverChronicle_Data` - enemy and item lists for the to-do goals, loaded on demand (GPL-3.0, data derived from QuestieDB).

### Notes
- This is a beta. Please report errors with the exact message (`/console scriptErrors 1` shows Lua errors).
- Part of the artwork was created with AI tools (Google Gemini) and edited by the author.
- Third-party components and their licenses are listed in `THIRD-PARTY.md`.
