# Ink & Embers: An Adventurer's Journal

A World of Warcraft addon that writes down your leveling journey while you play and turns it into a travel journal you can
open in the game with `/chronik`. I made it for WoW Forever (Interface 16001) and it runs on Retail (Interface 120105) too, from the
same download. Version 1.0 is the first stable release; the changes are in `CHANGELOG.md`.

The addon only records what the game shows to addons. In combat and in instances Blizzard hides some values from addons, so
a few entries are approximations or stay empty. The log format below says where.

## What it does

The addon logs the trip from level 1 on: level-ups, kills and fights, deaths, quests with their texts, discoveries, flights,
loot, gear changes, gold, professions, reputation, talents, groups, guild events and the people you sat with at a campfire.
The journal is a book with these pages:

- Journey: a map with your route for every zone, a chapter bar, and a playback that replays the trip at three speeds.
  A To Do sub-page keeps your own goals (a zone, a place, an enemy to kill, items to collect).
- Chronicle: a diary, a list of travel companions, medals and seals.
- Quests: what you accepted and turned in, the quest texts and quest chains. The Open tab lists quests you can still
  pick up, with the quest givers on the map. In WoW Forever the data comes from QuestieDB: read live from the QuestieDB add-on
  if it is installed (optional), otherwise from the bundled extract in `InkAndEmbers_QuestData`. In Retail the list comes from
  the game's own world map (no quest givers there). The Training tab (WoW Forever only) shows what your class trainer teaches
  at which level, what you can learn now and what it costs.
- Treasures: the gold flow, notable loot and how your gear changed over the levels.
- Moments: milestones as small handwritten diary notes, play time by hour of day, books you read and curiosities.
- Combat: kills, a bestiary and the death reports.
- Notes: your own notes, with a quick note field on the screen.

The to-do goals also show up outside the book. Enemies you still have to kill get a "To Do: 3/10" line in their tooltip and
a small book icon on their nameplate. A note at the screen edge lists the open goals. The enemy and item search for the goals uses
`InkAndEmbers_Data`.

When you sit down at a campfire (WoW Forever), a few singed scraps of paper float above the flames. Each one holds a conversation starter
that you can say in /say with a click, or throw away. Who sat with you is written to the log and shows up in the journal.

Smaller things: pop-ups for new medals and areas, a welcome greeting, a short introduction book (`/chronik tutorial`), and
HUD elements that can be moved in the game's Edit Mode. The interface and the texts are available in English, German and
Brazilian Portuguese. The Portuguese interface is selected automatically on a ptBR client; use the language setting or
`/chronik language ptbr` to select it on another client, then reload. Tutorial illustrations and bundled offline search
names are available in English and German only; Portuguese uses the English versions.

## Installation

From [CurseForge](https://www.curseforge.com/wow/addons/ink-embers-an-adventurers-journal): install "Ink & Embers: An Adventurer's Journal" with your usual addon manager. It brings all three folders below.

By hand: copy these three folders from `addon/` into `Interface/AddOns` of your game folder (`_forever_` or `_retail_`):

- `InkAndEmbers`, the addon itself
- `InkAndEmbers_QuestData`, quest and quest giver data for the Open tab in WoW Forever (loaded on demand; not used in Retail)
- `InkAndEmbers_Data`, enemy, item and zone names for the to-do goals (loaded on demand)

The add-on `QuestieDB` (optional, from the Questie team) is not part of this repository or download. If it is installed, WoW Forever
reads the open quests from it live.

New files such as textures and fonts are only picked up after a full restart of the game. For changes to Lua files `/reload` is enough.

## Commands

`/chronik` opens and closes the journal (`/inkembers`, `/inkember` and `/ie` do the same). The minimap button, the addon compartment and a key binding do the same.

| Command | What it does |
|---|---|
| `/chronik options` | open the settings |
| `/chronik status` | status line: recording since, number of events, last save, active collectors |
| `/chronik minimap` | show or hide the minimap button |
| `/chronik toast` | pop-ups for new medals and areas on or off (`toast test` shows examples) |
| `/chronik sound` | pop-up sound on or off |
| `/chronik todo` | show or hide the open to-dos at the screen edge (`todo reset` restores position and size) |
| `/chronik note` | show or hide the quick note field |
| `/chronik open` | open the Open tab under Quests |
| `/chronik training` | open the Training tab under Quests (WoW Forever only; `training status` prints the state) |
| `/chronik language` | `auto`, `de`, `en` or `ptbr`; takes effect after `/reload` |
| `/chronik save` | open the save window; saving reloads the interface |
| `/chronik backup` | state of the data safety: this character's backup copy, last save, how full the main file is, last restore |
| `/chronik reset` | reset size and position of the journal |
| `/chronik welcome`, `rest`, `tutorial` | show the welcome greeting, the "Since your last rest" recap, the introduction book |
| `/chronik diag` | self-test of all interfaces, result in `EveNChronicleDB.diag` |
| `/chronik help` | list all commands |

The German command names (`optionen`, `sichern`, `rast`, `feuer` and so on) work as well. After 30 minutes without
a save a small window asks whether to save the journey. It also asks when you take off on a flight or gain a level (if
your last save is at least 10 minutes old, and not more often than every 10 minutes). In combat and in instances it waits
for the next quiet moment.

## Data and privacy

Everything stays on your computer. The data is saved in the account-wide SavedVariables file
`WTF/Account/<ACCOUNT>/SavedVariables/InkAndEmbers.lua`, in the variable `EveNChronicleDB`, one entry per character. WoW writes
that file on logout and on reload. The addon only says something to other players when you click a campfire note yourself.

### Keeping your data safe

Your journal can hold weeks of play, so the add-on takes some care, but please read the honest limits below.

- **A second copy per character.** Besides the account-wide file, the add-on mirrors each character's own data into a separate
  file of that character: `WTF/Account/<ACCOUNT>/<Realm>/<Character>/SavedVariables/InkAndEmbers.lua` (variable
  `InkAndEmbersCharDB`). If the main file is missing, damaged or older than the copy when you log in, the add-on restores the
  character from the copy and tells you. It never replaces newer data with older data.
- **It is not a real backup.** The copy lives in the same `WTF` folder on the same disk. It does not help if the disk dies,
  or if the game fails to load saved variables at all. **If you want to be safe, copy your `WTF` folder now and then**
  (copying while the game runs is fine). The game writes the files only on logout and reload, so a crash loses what happened
  since the last save; that is why the add-on reminds you every 30 minutes.
- **If the add-on shows a warning** that data was missing or restored, or that it started a new journal although you used it before:
  1. **Do not log out and do not reload yet.** Every write replaces `InkAndEmbers.lua.bak` with the current state, and that file
     is your last good copy.
  2. While the game is still running, copy the files `InkAndEmbers.lua` and `InkAndEmbers.lua.bak` from
     `WTF/Account/<ACCOUNT>/SavedVariables` (and the ones in the character's folder) to a safe place.
  3. Quit the game completely. Then take your saved copy of `InkAndEmbers.lua.bak`, rename that copy to `InkAndEmbers.lua` and put
     it into the same folder, replacing the file that is there. Start the game again.
  `/chronik backup` shows the state of the character's copy, the last save, how full the main file is and the last restore;
  `/chronik diag` shows what the add-on found, and bug reports are welcome (see Feedback).

## Building from the source

You need Node 20 or newer, and only for the helper scripts. The addon itself needs nothing.

1. `npm install`
2. Copy `.env.example` to `.env` and set `WOW_DIR`, for example `WOW_DIR=D:\World of Warcraft`. The file stays local.
3. `npm run install-addon` copies the three addon folders to `_forever_`. Add `-- --retail` for `_retail_`, or `-- --dry-run` to only
   list what would change. The script only writes into those addon folders and does not follow symlinks.

`npm run check` parses all Lua files with luaparse (Lua 5.1).

The two data add-ons are generated and checked in. They only have to be regenerated for a new QuestieDB version or a new game
build, with `npm run data`. It first fetches the newest **stable** QuestieDB release (`node scripts/fetch-questiedb-release.mjs`:
SHA-256 checked against the release's `release.json`, only GitHub hosts, the archive is unpacked in memory and nothing in it is
run; `--tag vX.Y.Z` pins a version, the unstable `preview` channel is used only with `--preview`). The result lands in the
git-ignored folder `data-capture/questiedb-release`. Then it runs `scripts/build-todo-data.mjs` and `scripts/build-quest-data.mjs`
(`--help` lists the options). Accepted residual risk: `release.json` and the ZIP come from the same host (GitHub), so the
checksum protects against damage and a swapped file, not against a compromised release. To close that, pin a version and the
checksum you got from another trusted source: `node scripts/fetch-questiedb-release.mjs --tag vX.Y.Z --sha256 <64 hex digits>`
(refused if the release's archive hash differs). Offline, use `node scripts/fetch-questiedb-release.mjs --from-zip <QuestieDB-Forever.zip> --release-json <release.json>`.
The two generators read local files only and write only into the target folder. The output is sorted and has no
timestamps, so the same inputs give identical files. The inputs:

| Input | Option / variable | Where from |
|---|---|---|
| QuestieDB for Forever (`QuestieDB_Forever.toc`, quests, NPCs, objects, items) | `--questie`; otherwise the fetched release in `data-capture/questiedb-release`, then `CHRONICLE_QUESTIE_TOC`, then `WOW_DIR\_forever_\Interface\AddOns\QuestieDB` | the stable releases of https://github.com/Questie/QuestieDB (contract 1 to 4 and newer are accepted; a release that only guarantees a higher contract is rejected) |
| Corrections per faction (`src/corrections/` of QuestieDB, parsed only, never run) | `--corrections`; otherwise next to the TOC (the fetch script stores them there, byte-identical from the release) | the same release. If they are missing the generator warns, and Alliance quest givers can be wrong |
| Zones, German names, quest types | `--forever` / `CHRONICLE_FOREVER_DB` | a dump of the Forever database from https://data.morthen.net: `data/forever/zones.json`, `search.json`, `l10n/deDE/search.json` and `quest/*.json`. It is not in this repo, and I cannot promise it stays available |
| Map overlays (revealed zone maps) | `--overlays`, `--overlays-retail` / `CHRONICLE_OVERLAYS`, `CHRONICLE_OVERLAYS_RETAIL` | snapshot in `scripts/data` (about 0.8 MB): the wago.tools tables `UiMapXMapArt`, `WorldMapOverlay`, `WorldMapOverlayTile` for each build |

If an input is missing, the generator stops and names the missing path and the option for it.

The training plan (`addon/InkAndEmbers/data/TrainerSpells.lua`) comes from "What's Training?" (MIT, branch `forever`, pinned commit).
Regenerate it with `node scripts/build-trainer-data.mjs --src <local copy of github.com/fusionpit/WhatsTraining>`; the script checks
the SHA-256 of every source file against the pinned commit and stops on a difference (`--unpinned` allows it and marks the output).

Releases are built by the BigWigs packager from a tag `v*` (`.pkgmeta`, `.github/workflows/release.yml`). The development
simulation `journal/SimPanel.lua` is left out of the package.

## Licenses and data sources

- The main addon `addon/InkAndEmbers` is under the MIT license (c) 2026 EveN. The graphics and media (folder `Media`, all image
  files) are not covered by it: all rights reserved, as far as protection exists. See `addon/InkAndEmbers/LICENSE`.
- The data add-ons `InkAndEmbers_QuestData` and `InkAndEmbers_Data` are under GPL-3.0. They are derived from QuestieDB
  (Questie team and contributors, https://github.com/Questie/QuestieDB). QuestieDB has no clear license of its own. Its maintainers
  allow copies under the GPLv3, but for older contributions that is not guaranteed, and the name and logo "Questie" are excluded.
  That is why the derived data lives in separate add-ons that you can switch off. Details are in `LICENSE` and `LICENSE-NOTE.md`
  in each folder. German names and zone assignments come from the Forever database (data.morthen.net), the map overlay
  numbers from wago.tools.
- Embedded libraries, fonts (SIL OFL), sounds (CC0) and the class trainer data from "What's Training?" (MIT,
  `addon/InkAndEmbers/data/LICENSE-WhatsTraining.txt`) keep their own licenses, listed in `addon/InkAndEmbers/THIRD-PARTY.md`.
- World of Warcraft and its game content are (c) Blizzard Entertainment. This addon is not affiliated with or endorsed by Blizzard.

## AI notice

I wrote the code with Claude Code, and most of the images were made with Google Gemini and then edited by me. I plan, test and
maintain the addon myself.

## Support

If you enjoy the add-on and want to support its development, you can do so on Ko-fi: https://ko-fi.com/even512

## Feedback

Bugs, wishes and questions go to https://github.com/even512/InkAndEmbers/issues. For an error please include the exact message
(`/console scriptErrors 1` shows Lua errors in the game).

## Log format

This part is for people who want to read the saved file with their own tools. The format has a schema version, and a reader
should check it first.

### File and schema

```
EveNChronicleDB = {
  schema = 1,                 -- format version
  addonVersion = "<version from the TOC>",
  meta = {
    sessions = { {            -- account-wide, chronological
      guid, start, stop,      -- epoch (UTC); stop = logout, missing for an open (reload) or interrupted session
      lastSave,               -- last save (logout or reload)
      build, buildNumber, interface, locale, tz,
      reloads,                -- number of reloads in the session
      interrupted, lastKnown, -- crash detected: true + last known time
    }, ... },
    tzOffset,                 -- local time minus UTC (seconds) of the last session
    reloadAt,                 -- only set between a reload logout and the next login
  },
  diag = { collectors, apis, patterns, client, restrictions, state, core, lastRun,
    recovery = { { at, guid, reason, from, lines, ... }, ... },   -- data safety events (restore, kept states, damaged values)
    constants = { n, at, pct },                                    -- distinct constants of this file (game limit 262143)
  },
  archive = { ["Player-..."] = { { at, reason, lineCount, lastBlockAt, char }, ... } },  -- only if needed, see below
  chars = { ["Player-..."] = {
    info = { name, realm, race, raceFile, class, classFile, faction, factionName, firstSeen, lastSeen },
    lineCount,                -- number of all log lines
    log = { "<block>", ... }, -- strings only, never line tables
    trail = { "<trail block>", ... },   -- position trail, separate stream (see below)
    quests = { [questID] = { firstAt, <field>, <field>At, ... } }, books = { [key] = { firstAt, ... } },
    npcs = { [npcID] = "name" },
    counters = { [group] = { [key] = n } },
    snapshots = { [kind] = { [key] = { at, ... } } },   -- e.g. gear and stats per level
    shots = { ["MMDDYY_HHMMSS"] = { at, ... } },        -- screenshot mapping (local time in the file name)
  } },
}
```

Each character also has its own file `WTF/Account/<ACCOUNT>/<Realm>/<Character>/SavedVariables/InkAndEmbers.lua`
(`## SavedVariablesPerCharacter`), a mirror of that character only:

```
InkAndEmbersCharDB = {
  v = 1,                      -- mirror format
  guid = "Player-...",
  savedAt, addonVersion,      -- when and by which version it was written (logout or reload)
  lineCount, lastBlockAt,     -- markers: number of log lines, epoch of the newest log block header
  sessions = { { <copy of the character's meta.sessions entry>, idx = <index in meta.sessions> }, ... },
  accountChars = { ["Player-..."] = <lineCount>, ... },   -- all characters of the main file at that time
  missingChars = { ["Player-..."] = { lines, since, warned } },   -- only while characters are missing from the main file
  char = { <the same table as EveNChronicleDB.chars[guid]> },
}
```

At login the add-on compares the main file with the mirror. The mirror wins only if the main file lacks the character, holds it
without lines, or holds an older state (more lines in the mirror and its newest block header is not older). Its sessions are then
added to `meta.sessions` and the session index in each block header is rewritten. A losing state that holds a log or trail block
the winner does not have is kept under `archive[guid]` (nothing is deleted automatically); the log gets a `GR` line. A value that
is not a table where a table belongs is never dropped either: it moves aside (`recovered`, `chars_bad`, `<key>_bad`) and
`diag.recovery` notes it. Readers only need `EveNChronicleDB`; the mirror is a safety copy.

A session runs from login to logout (`O`, `stop`). A reload (save button, `/reload`) continues the same session: `S` when the
interface reloads (`stop` stays empty, `reloadAt` is set), `R` afterwards, and `reloads` goes up by one. If the end of a session is missing at
the next login, the game crashed: the session gets `interrupted = true` and the character gets an `X` line. A crash before
the first save leaves no trace at all.

### Blocks

- Every entry in `log` is one string with 1 to 500 lines separated by `\n`.
- The first line is the block header `#~<epoch>~<session>`. `<epoch>` is `time()` (UTC seconds) when the block was opened,
  `<session>` the index into `meta.sessions` (0 = unknown).
- Every other line is `<dt>~<code>~<field1>~<field2>~...`. `<dt>` is the number of seconds since the epoch of the header, so
  the absolute time is `epoch + dt`.
- A new block starts after 500 lines and after every login or reload.
- Empty fields at the end of a line are dropped. A reader treats missing fields as empty.

### Trail

The position trail is a separate stream per character. Each entry is a string with 1 to 500 points. The header is
`#~<epoch>~<mapID>`, followed by lines `<dt>~<x>~<y>` or `<dt>~<x>~<y>~<mark>`. `x` and `y` are map coordinates in tenths of a
permille (0 to 9999) on the map `<mapID>` (uiMapID). Marks are `z` zone change, `d` death, `f` takeoff, `l` landing. A point without a mark
is a movement point: set at 22 yards of distance (or 0.3 % of the map if there is no world position), checked every 3 seconds. The trail
pauses during flights. Where the position is unreadable (instances) the log gets one `TP` line per pause. A new block starts when
the map changes, after 500 points and after login or reload.

### Values and escaping

- Numbers are always integers, never `1e+09` or decimals. Fractions are scaled first (map coordinates as above).
- Booleans are `1` and `0`. An empty field means "no value". `?` means the client hid the value from addons (secret value).
- Text in fields is cleaned: color codes, textures and control characters are removed, links are reduced to their display text, `~` becomes
  `-`, a line break becomes a space and `|` becomes `/`. At most 250 bytes.
- Long texts (quest and book texts) are not in the log but in `quests` and `books`. They are cleaned the same way but keep their paragraphs
  (`\n`). Each field is written once; `firstAt` is the time of the first entry, and a field added later gets its own `<field>At`.
  If you show this data on a web page, escape it and never insert it as HTML.
- Quests: `quests[questID]` has `title`, `detail` (accept text), `objectives`, `progress`, `reward`, `rewardMoney`, `choices`,
  `rewardChoices`, `rewardItems`, `giver`/`giverNpc`, `qlevel`, `mapID`, `category` (the header above the quest in the quest log) and,
  where the client provides them, `questLine`, `questLineName`, `questLinePos`, `questLineLen`, and (0.9.4) `group` (suggested group size), `elite`, `tag` (quest tag name), `freq`
  (0 normal, 1 daily, 2 weekly). Older entries may lack newer fields.
- Books: `books[key]` has `title`, `material`, `mapID`, the pages as `p1`, `p2`, ... and `pages`. The key is a stable 16-digit hash of title,
  material and first page. Only pages the player opens are read.
- Item keys (in `LT`, `GW`, `TH`, `PM`, `PS`, `snapshots.gear`) are `<itemID>`, or `<itemID>.s<suffix>.b<bonusID>...` for random suffixes and bonus IDs.
  Never a link. Names and quality are in `snapshots.items`.
- Counters (`counters[group][key] = n`): gold in copper, everything else counts pieces. Groups include `money_in`, `money_out`, `ah`, `loot`,
  `loot_quality`, `gather`, `mates`, `duels`, `pvp`, `trade`, `mail`, `consumables`, `consumed`, `reagents`, `emotes`, `fishing` and `unreadable`.
  `unreadable` counts messages that were hidden from the addon.
- Snapshots (`snapshots[kind][key]`): numbers with at most 2 decimals, texts cleaned, `at` is the time. Fixed groups: `items`, `spells`, `factions`, `skills`,
  `gear[level]`, `stats[level]`, `talents[spent]`, `talentNodes`, `maps`, `zones`, `subzones`, `continents`, `instances`, `encounters`, `moments`
  and `state.*` (internal state across reloads).
- Screenshots: the key of `shots` is `MMDDYY_HHMMSS`, the local time in the file name `WoWScrnShot_MMDDYY_HHMMSS.jpg`. `at` is the epoch (UTC),
  so match files with a tolerance of about 2 seconds. Further fields: `reasons`, `auto` (1 = taken by the addon), `level`, `mapID`.
- Limits: at most 2000 quests, 500 books, 5000 NPC names, 2000 keys per counter group (6000 for `loot` and `consumables`) and similar caps
  for the snapshot groups. Past a cap no new entries are created, and `diag.limits` notes it.
- Combat: the combat log event is restricted and never registered. A kill (`KI`) comes from `PARTY_KILL`. "Close win" (`KF.close`) is an
  approximation: health below 10 % at the end of the fight. Causes in `DC` and ways back in `DB` with `guess = 1` are guesses.

### Line codes

| Group | Codes |
|---|---|
| Session | `L` login, `R` reload, `S` saved, `O` logout, `X` interrupted session |
| Progress | `LV` level-up, `PL` /played, `XP` experience, `RS` rested state |
| Quests and books | `QA` accepted, `QT` turned in, `QR` reward choice added later, `QX` abandoned, `QO` objective progress, `BK` book page read |
| Combat | `KI` kill, `KF` fight ended |
| Death | `DE` death, `DR` death recap hit, `DC` cause of death, `DB` back alive |
| World | `ZN` new map, `SZ` new subzone, `EX` discovered area, `FP` new flight point, `TP` trail paused |
| Travel | `TF` flight started, `TL` flight landed, `HS` hearthstone used, `HB` new home, `TB` crossing (guessed) |
| Instances | `IE` entered, `IL` left, `IB` boss fight |
| Moments | `MO` milestone, `SH` screenshot |
| Gold and loot | `GD` gold change, `AH` auction house, `LT` loot |
| Character | `GW` gear change, `SP` spell learned, `TA` talent, `SK` skill, `RP` reputation change, `RT` reputation standing |
| Social | `GS` group formed, `GM` member joined, `GL` member left, `GE` group ended, `GI` group in instance, `GU` guild, `DU` duel, `PK` PvP kill, `PD` PvP death, `TH` trade, `PM` mail received, `PS` mail sent, `WB` companion joins, `WV` companion leaves |
| Camp | `RA` rest, `LF` campfire round |
| Goals | `VE` own to-do completed |

Field names and their order for every code are defined in `ns.Types` in `addon/InkAndEmbers/Store.lua`. The descriptions there are in German.

