# Changelog

## 1.0.3

### New
- **To the trainer, at login (WoW Forever):** the automatic "To the trainer" to-do is now also created when you log in with spells waiting for you, not only when you level up. It appears once per level: if you tick it off or delete it, it stays gone until your next level-up.
- **Diagnostics:** `/chronik diag` now lists blocked-action messages caused by Ink & Embers (what, which function, call path), to help track down interface taint. This only observes; nothing changes in how the add-on behaves.
- **Place to-dos on the world map:** open place to-dos now show a pin on the world map, with their text as a tooltip.
- **Own filter entry for the pins:** note and place to-do pins now have their own entry "Places (Ink & Embers)" in the world map filter, separate from "Journey (Ink & Embers)" (route, level-ups, fight marks). Each can be switched on or off on its own, also in the settings ("Show places on the world map", on by default); pins stay visible when the journey is switched off.

### Changed
- **To-do section at the quest tracker:** line heights, spacing, fonts, sizes, colors and the header now follow the tracker you use (Blizzard, Kaliel's or Questie) and keep up when you change the tracker's font options.

### Fixes
- **Trainers you have visited:** the Training tab and the level-up note now find the trainers you have visited again (the saved places were not read), and the "As to-do" button is back.

## 1.0.2

### New
- **To-dos at the quest tracker:** new option "Dock to-dos to the quest tracker" (off by default; the mini note stays the default): your to-dos then sit right at the quest tracker as a section in its look (same width and fonts, header with collapse button, progress "3/10" like quest objectives), below the quests or above them ("Position at the quest tracker"), moving to the other side when the screen edge leaves no room. It also docks to Questie's and Kaliel's tracker, collapses with the tracker, stays in place when the tracker is empty, and while docked the mini note's edit mode entry rests. Blizzard's tracker itself is never touched.

### Changed
- **Level-up note speaks in flowing text:** instead of a list, the narrator now talks to you: he congratulates you by name, tells you where new spells are waiting (with up to three spell names, the cost or what you are short of, and a reminder about free talent points). Each case has six wordings, picked at random and never the same one twice in a row. If the text does not fit the parchment it shortens itself (spell names first, then the trainer's place) and never runs over the edge. A click on the note opens the book at Quests, Training, and the note leaves; the small x in the corner only closes it; a small line says so. In combat the book stays shut (a chat hint tells you) and the note stays. The welcome greeting is unchanged.
- **To-do note opens by itself:** the mini to-do note now opens on its own while to-dos are open (at login and whenever a new one arrives); close it with the x and it stays shut until a new to-do shows up (option "Show the note automatically while to-dos are open", on by default). When the addon adds a to-do itself (e.g. "To the trainer" after a level-up) a small pop-up announces it, after the narrator note and never in combat (option "Announce automatic to-dos", on by default, WoW Forever); to-dos you add yourself stay quiet.
- **Campfire notes, more variety:** about three times as many conversation suggestions (169 instead of 55, German and English), new topics from your journey (first elite kill, first bag, a new profession, a reputation tier, a newly found subzone, a long kill streak) and guest sentences that compare race, class and level with your own character; if someone sure is at the fire, one of the three notes is always about a guest, a guest who sits down late replaces the weakest note, guest sentences are locked per guest, a topic you already talked about steps back for the rest of the round and follow-ups do not repeat within the last ten.

### Fixes
- **World map markers:** the markers on the world map appear right away again instead of one every few seconds.
- **Chosen quest reward:** the reward you pick is now recorded even with a quest UI replacement such as DialogueUI (read from the loot message); for older turn-ins the quest book works out the choice from the items you received, and if that is not possible it says "Choice not recorded" instead of marking every item "not chosen".
- **Campfire embers:** a glowing "New note" ember bed now sits below the campfire notes as soon as they appear; hover lights it up with a tooltip, a click draws a fresh conversation note (before your first line it replaces the weakest note, afterwards it brings follow-ups or, if none are left, an ordinary note).
- **Bestiary pictures:** enemy cards no longer keep a "?" for creatures the game had not cached yet; the card asks for the model again a few times, so it shows up just like in the enlarged view.

## 1.0.1

### New
- **Level-up note (WoW Forever):** when you level up, your narrator glides in from the left like the welcome greeting and tells you what the trainer can teach you now: up to three spells (the rest as "... and n more"), the total cost (and what you are short of), the nearest known trainer and any free talent points (then there is no separate talent pop-up). With nothing to learn it still congratulates you and names the next level with new spells. In combat it waits until the fight is over, after an open welcome note it comes next. New option "Level-up: narrator tells what you can learn" (on by default; off keeps the old talent pop-up) and the preview command `/chronik level` (`/chronik stufe`).

### Fixes
- **Crafted gear is recognised:** items you made yourself (e.g. a Rough Copper Vest) carry the crafter in their link, which the addon could not read, so the slot was noted as empty. Those links are read now, an unreadable link no longer counts as an empty slot, and after login the worn gear is compared with the last noted state so missed changes are filled in (without repeating first-blue/epic/bag moments).
- **World map route:** the journey route on the world map is now drawn the first time you open the map (no need to open the book or save first) and keeps up while the map is open: new trail points extend the line and a thin live tail runs to your position.

## 1.0.0

First stable version. It collects everything from the 0.9 line; the details are in the entries below.

### What's in 1.0
- **Travel journal from level 1:** the book (`/chronik`) fills itself while you play: Journey with a map and a replay of your
  route, Chronicle, Quests, Treasures, Moments, Combat and Notes. Moments are small handwritten diary notes.
- **One download for WoW Forever and Retail:** the add-on tells them apart by the interface version. Forever-only parts
  (Training tab, campfire talk, live QuestieDB) are hidden in Retail, and Retail reads its maximum level from the client.
- **Open quests:** the quests you can still pick up, with quest givers on the map. In Forever the data comes from QuestieDB
  (live if the QuestieDB add-on is installed, otherwise the bundled extract, stable releases only); in Retail from the game's
  own world map. QuestieDB is optional.
- **To-do list that ticks itself off:** places, enemies and items, with a tooltip line and a nameplate icon for the enemies
  you still need, a note at the screen edge and a trainer to-do after a level-up (Forever).
- **Training tab (WoW Forever):** what your class trainer teaches at which level, what you can learn now and what it costs.
- **Campfire conversation starters (WoW Forever):** notes above the fire with a line to say, drawn from your own journey and
  the people sitting with you, plus a "Since your last rest" recap.
- **Data safety:** a second copy of every character's data, automatic restore, warnings, size watch, save reminders and
  `/chronik backup`. Everything stays on your computer.
- **English and German**, welcome greeting, introduction book, toasts, HUD elements for the Edit Mode.

### New
- **Automatic screenshots:** a new option (on by default) lets you turn off the screenshots the Chronicle takes at special moments.
- **Short commands:** `/inkembers`, `/inkember` and `/ie` do the same as `/chronik`.
- **Training page in the introduction (WoW Forever):** the introduction now explains the training plan.
- **Quieter first login:** on the very first login only the introduction shows, with no area pop-up and no welcome card.

### Changes
- **Welcome-back note:** the welcome-back note is now a wooden frame with a lantern that slides in from the left, with a narrator of your race in the circle and your greeting on the parchment. One option, "Welcome greeting", turns it (and a character's first greeting) on or off. By default it shows after 1 hour away; you can choose the delay ("Show after an absence of": at once, 1, 2, 4, 8 or 24 hours) and which info lines it shows (last seen, open quests, rested bonus, to-do nearby) in the options.
- **German texts:** German texts address the reader consistently ("Ihr"); typos in the introduction are fixed.
- **Notification queue:** Notifications now queue up and appear one at a time, and wait while the game's own zone text is showing. Many similar ones (e.g. medals) are merged instead of dropped.
- **Notification size and position:** Notifications are smaller by default and appear slightly below the screen center; they remain movable in Edit Mode, and only sizes you never changed become smaller, while saved sizes and positions are kept.
- **Rest recap off by default:** The rest recap is now off by default; you can turn it on in the options.

### Fixes
- **Long names:** Long zone, quest and character names no longer get cut off in the journal and in notifications; hover shows the full text where space is short.
- **Clients without Edit Mode:** the bundled Edit Mode library now steps aside quietly if the game lacks the Edit Mode interfaces; the HUD elements then keep using the settings panel instead of throwing errors at login.
- **Dates in English:** journey chapters show month/day (for example "10/26 08:33") instead of the German day.month form.
- **Starting point is no news:** the zone and continent you start in are no longer listed as a Moment or a diary discovery (the "Beyond the Sea" medal still counts the starting continent).
- **Wording:** "Quest Book" is used everywhere in English; "Avg. per play day" replaces the "Ø" sign; no "approx." in front of "under 1 min".
- **Trainer to-do:** the money amount is written "5 S 10 K" (capital letters) instead of "5 s 10 k".
- **Slash commands:** `/chronik open` and `/chronik lehrplan` with an unknown word now say so instead of silently opening the page. `/chronik diag` no longer breaks if a game interface is missing. Developer lines (test mode, quest probe, auras, coins) only show in the help with the development tools.
- **Welcome greeting in Edit Mode:** the welcome-back note (wooden frame, lantern, narrator) now has its own Edit Mode element "Chronicle: Welcome greeting" to move, resize and fade; the old large welcome card is gone from the Edit Mode and no longer appears as a greeting (a new character's first session uses the note too). The large card is now only the campfire recap, which shows up in Edit Mode as "Chronicle: Campfire recap" only while that option is on.
- **First greeting:** a character's first welcome note now shows all three lines, including the hint how to open the book (minimap button or `/chronik`), and only depends on the option "Welcome greeting", not on the chosen absence or info lines.


## 0.9.5

### Fixes
- **Combat page:** the "Hunting Grounds" map is now always drawn at full size. Before, characters with many kills but no
  recorded kill positions got a squashed map with "Kills per zone" bars underneath. The bars are gone; where there is
  nothing to draw, the map line says that no kill locations are recorded for the zone. Kills per zone stay in the zone list.
- **Open quests:** some quests started by an item (e.g. a dropped letter or book) showed a wrong quest giver: an NPC with
  the item's number. Such quests now show no giver, as in QuestieDB itself (35 quests lost a wrong map point).
- **WoW Forever, Open quests with QuestieDB:** reading QuestieDB live needs much less memory. Entries that match the bundled
  data are reused instead of copied, so after the switch the tab holds about as much as with the bundled data alone.

### New
- **WoW Forever, Open quests:** if QuestieDB is installed (e.g. together with Questie), the Open quests tab reads it live,
  so it always shows the quest data of the QuestieDB you actually run (the footer says "live"); otherwise the bundled data is
  used as before. It is read in small steps and never during combat. Retail is unchanged.

### Changes
- Quest and to-do data updated to QuestieDB 1.0.10 (stable release). The data now comes from the stable QuestieDB releases
  only, checked against their checksum, instead of the unstable preview channel. Small corrections: two enemies now show as
  elite and one quest has its corrected level.
- `/chronik diag` now also shows which version of the separate QuestieDB add-on is installed (only its version and contract
  number are read) and where the Open quests data comes from ("live" or the bundled extract with its version and the
  reason). Not shown in Retail.
- The Open quests tab now shows where its data comes from at the bottom of the page.

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
