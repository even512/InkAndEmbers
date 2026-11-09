# Changelog

## 1.0.9

### New
- **Books of your other characters:** a round button "Other books" at the edge of the book (shown once the saved file knows a second character) opens a list of all your characters with class colour, level, race, class, ruleset (WoW Forever) or realm (Retail) and last played. Click one to read its book - Journey, Chronicle, Combat, Quest history, Treasures and Moments - read only; nothing of that character is ever changed. A band over the right page ("You are reading the book of ...") with a "Back to your book" button always shows whose book is open. What belongs to the character you are logged in with (To Do, open quests, trainer plan, notes, live map position, a running campfire round) stays out of the borrowed book. Characters without entries or recorded in another game are greyed out with the reason; right-click an entry to take a deleted character off the list (the data stay) and bring it back with "Show hidden characters" in the settings.
- **Milestones (WoW Forever):** at level 10, 20, 30, 40, 50 and 60 the narrator sums up the last ten levels in a few sentences: time on the road (without AFK), new zones, enemies fallen, deaths, and your best find; at level 60 two closing sentences look back on the whole journey. A click on the note opens the new Chronicle bookmark "Milestones" with one page per stretch ("Level 1-10" to "50-60") and a final "Journey's End" page with the numbers of the whole trip. Long texts and names are shown in full, never cut off with "...". Everything is read from your existing log, so milestones you reached before this update are in the book at once (without a note); where the book started recording late, it says so and invents nothing. The option "Milestone" (on by default) turns only the note off; `/chronik milestone [level]` shows a preview. Not in Retail.
- **Reunion in the tooltip:** when you look at a player you have been out with before (mouse over, unit frame, target frame), the tooltip shows up to two short memory lines, e.g. "Cleared The Hall of Thanes together, 11/03", "Fought in The Hall of Thanes with you, 11/03", "Sat with you at the fire in Goldshire, 11/03", or else "Travelled with you, last on 11/03 in Goldshire". Nothing is shown for strangers, NPCs, yourself or your current group. It reads the existing log only and is built in small time slices, never in combat; if the game hides a name, the line is left out. Switch "Reunion in the tooltip" (on by default) under Options > AddOns > Ink & Embers.
- **Gear Journey (Treasures):** a new bookmark shows your character as a 3D model wearing the gear it had at the end of a level, with the timeline of the journey map (play / pause, three speeds, drag the knob). A slim list names the pieces of that level in quality colour with the original item tooltip; new pieces are marked "new". The record starts at the level where the book first saw your gear. Pieces the game has not loaded yet are requested and retried. Only for your own character; if the game cannot show the model, the note says so and the list keeps working.
- **Zone completed (WoW Forever):** every chapter card of the journey shows how many of the zone's quests you have done, e.g. "Zone completed: 62% (41/66)". The tooltip lists up to eight quests still open and the data source. Counted are the quests of your faction, race and class in that zone, also those you can only take later; group, dungeon, raid, repeatable, profession and reputation quests do not count, and zones with fewer than 10 countable quests show no share. At 100% the line turns gold with a small medal stamp; the whole journey card shows "Zones completed: 3 / 24". Not shown in Retail or in another character's book.
- **New medal "Zone Master" (Quests & Lore):** bronze, silver and gold for 1, 4 and 10 completed zones; the tooltip lists them. Zones you have already completed are entered quietly at the first login after the update, without a flood of pop-ups. WoW Forever only.
- **Zone overview (WoW Forever):** the Quests tab has a new last bookmark "Zones" with every zone that counts for your character, grouped by continent (the one your journey began on comes first) and sorted by level range, e.g. "Tirisfal Glades, Level 1-12, 100% · completed" or "Silverpine Forest, Level 10-22, 51% (27/52)". Each row has a progress bar; completed zones turn gold with the medal stamp, zones you have not entered yet stay pale. The top shows "Zones completed 4 / 30" and your progress towards the "Zone Master" medal. Hover a zone for its open quests, click it to jump to the "Open" bookmark of that zone. The numbers are the same as on the chapter cards. Not shown in Retail or in another character's book.
- **Share with a link:** a new "Share" sticker on the journey card (and the row "Share your journey" in the "..." menu) leads to the web page where you can read your book on screen. "Save & show link" saves your journey (the interface reloads once, only on your click, through a secure /reload button) and after the reload the link window opens by itself - never during combat; "Without saving" shows it at once with the state of your last logout or reload. The link only carries the character's ID and the view (as a part after the #, which your browser never sends anywhere; no name, no realm); drag the file InkAndEmbers.lua onto the page and your character is already selected. Both windows ("Share your journey", "Link to the web page") and the save window use the light parchment of the other notes.

### Changes
- **Save reminder is now off by default:** the small "Save your journey?" window no longer pops up on its own. Turn on "Save reminder" (Options > AddOns > Ink & Embers > Miscellaneous) to get the old behaviour. WoW only writes your data on logout or reload, so after a crash everything since your last login is lost; the tooltip says so.
- **Quiet save status:** the settings show "Save your journey: Last saved N min ago" with a "Save now" button (it does not reload by itself: it opens the save window, whose "Save" reloads the interface through a secure /reload button; if the game still refuses, a chat line asks you to type /reload); the tooltip of the "..." button shows the same line. `/chronik save` still opens the save window on demand.
- **Quest data updated to QuestieDB 1.0.13:** corrected quest details (givers, prerequisites, level and race requirements) for about 25 quests and two adjusted quest giver positions on the map. No quests were added or removed; the dungeon quest lists are unchanged.
- **Full names and ruleset instead of the hidden server shard (WoW Forever):** the book now shows your character as "First name Surname" with the ruleset, e.g. "Lenu Barrowstone · Roleplay (PvE)", in the book header, the character profile, the list of your other characters, the band of a borrowed book and the print header; the internal server name ("CAMWOW ...") is never shown. Companions, campfire guests, dungeon groups and the diary also name players with their surname. Your own name in chat messages (loot, emotes, duels) is recognised with and without surname. Characters you have not logged in with since the update show their first name until the next login. Retail keeps showing the realm.
- **Sub-bookmarks stay left of the fold:** they start at the left edge of the book, and their width and font follow their number and the language.

### Fixes
- **Reward names in the quest history:** rewards of recently completed quests no longer show "Item #281..." instead of the name. When the game had not loaded an item at turn-in, the book kept no name; now the name is read when the page is drawn, requested once if still unknown, and saved. The same applies to the finds of the Dungeons tab and the equipment finds.

- **Save buttons did nothing in WoW Forever:** the game blocked the reload from the "Save" and "Save & show link" buttons, so nothing happened. They now reload through a secure `/reload` button; if a reload is still refused, a chat line says how to save by hand.

### Internal
- Zone progress is counted in small steps per frame, 30 seconds after login, never in combat; the dungeon quest counts use the same counting code. New counter group `zonedone` in the saved file; `/chronik diag` shows the zone numbers and the Reunion state.
- The journal index and the journey model can hold one other character of the saved file next to yours, so opening a borrowed book never rebuilds your own; the book now remembers the game client a character was last played in.
- Every button that reloads the interface ("Save" in the save window, "Save & show link") is now a secure button running `/reload`; the addon no longer calls ReloadUI itself, which the game blocked from the share window. If a reload is still refused, a chat line asks you to type /reload; in combat these windows do not open and say why.
- Narrator notes wait in a queue (notes ahead of toasts) instead of a single slot, each with its own display time; the Chronicle can hold five sub-bookmarks.

## 1.0.8

### New
- **Dungeons page in the Chronicle:** a new bookmark "Dungeons" lists every dungeon run, newest first: instance, date, duration, bosses defeated, deaths and your group as class symbols. Click a run to read it on the right-hand page: when and how long you were inside, your level, kills and experience, the bosses in the order of the fights with failed attempts and fight duration, your group (class, level), your deaths with the cause, the finds from green quality up (with the original item tooltip) and the quests you accepted or handed in inside. Visits to the same dungeon with short breaks in between (ghost run, disconnect, a trip to the vendor, up to 30 minutes) count as one run. A run is only marked "completed" when the game itself names the bosses of the dungeon; otherwise it just says how many bosses you defeated. Everything is read from your existing log, so it works for past runs as well.

- **Dungeon finds of the whole group:** in a dungeon the book now also records the green-and-better items that your group mates receive (new log line type LG: item, amount, quality, recipient, class where the group units give it, and the kind of roll - Need, Greed, Disenchant, Transmog - where the game's win message for the same item and player was seen). The "Finds (green and better)" section of the Dungeons page lists them in order of time: the item in its quality colour with the original item tooltip, the recipient in class colour ("You" for your own finds) and the kind of roll small behind it. Older runs have no group finds and look as before. If the game hides the loot messages of others (it may in WoW Forever), nothing is recorded and nothing is guessed.

### Changes
- **Dungeon group = those who took part in a boss kill:** the group of a run (class symbols, "+N", tooltip and the Group section) now only lists people who were there for at least one successful boss fight. Short guests who left before the first boss, and people who were only present for a failed attempt, are no longer counted; a run without a boss kill has no group.
- **Your own character in the group list:** the Group section of a dungeon run now starts with your own character (class colour, level or level range of the run). The class symbols and the tooltip in the run list still show only your companions.
- **"Instance entries" instead of "visits":** the Dungeons page now says "N instance entries" (German "Instanzeintritte"), because the number counts how often you re-entered after a death or a trip out, not visits.
- **"By the Fire" moved into "Companions" (WoW Forever):** the Chronicle bookmark "By the Fire" is gone; the same view now sits behind a switch "Group | By the Fire" at the top of the Companions page. Its content and behavior are unchanged. In Retail there is no switch, as before.

### Fixes
- **Deaths in instances show the instance:** a death inside a dungeon no longer reads "unknown place" in the Combat tab ("Where I fell", the death report) and the Chronicle diary. The place is now the instance (found from your visit, for old deaths too, nothing is rewritten); the sub-area of the death is added in the tooltip. New deaths also record the instance directly. Deaths in instances still leave no map marker, as the game gives no position there.
- **Quests accepted inside a dungeon appear in the Dungeons tab:** quests you accept (or hand in) during a visit to a dungeon are now listed under that dungeon, marked "Accepted inside the instance", even if the quest database does not know where they belong. "An Ancient Grudge" and "The Treaty of Understanding" are now assigned to The Hall of Thanes in the data as well.
- **Dungeon runs interrupted by a logout or crash:** when you left the game (or it crashed) while inside a dungeon, the run could be shown as lasting until your next login, hours of offline time included. Such a run now ends with the session it started in and no longer counts the time you were offline.

## 1.0.7

### New
- **Smoke signal near a campfire (WoW Forever only):** when you come near a campfire, smoke blows in from the left across the top of the screen and uncovers the words "Campfire nearby", then fades into a small campfire with a rising column of smoke that stays for as long as the fire is close. It stays away in combat, while sitting and on flights, and with reduced motion it only fades. You can switch it off in the settings ("Smoke signal") and move it in Edit Mode; `/chronik feuer rauch` shows a preview.

### Changes
- **Close the campfire notes:** a small "x" next to the campfire notes ends them for the current rest (tooltip "Close the notes for this rest"). The notes and the embers fade out and nothing new appears until you sit down at a fire again; the round itself (companions, log, smoke signal) keeps running unchanged.
- **Quest data updated to QuestieDB 1.0.12:** more German names for quests, creatures and items, and a few corrected quest givers and prerequisites, including the "Camping 101" quests. The dungeon quest lists are unchanged by this update.

### Fixes
- **Chronicle, XP sources:** the note "of which rested bonus" no longer overlaps the last line of the legend; it now sits below it, whatever the number of rows or the language.

## 1.0.6

### New
- **Dungeons tab under Quests (WoW Forever only):** shows the quests and quest chains of each dungeon, which of them you have done, are carrying or are still missing, and what they need first (prerequisite quests, level, quests that rule each other out). Which dungeon a quest belongs to comes from the quest database; where that was derived rather than listed, the tab marks it as an estimate. Quests of the other faction, race or class are hidden unless you ask for them.

### Changes
- **Level 60 forecast:** the forecast now uses the experience you still need and your pace over the last levels, leaving out the time you were AFK. Where the game version has no documented experience table, or the experience cannot be read, it says so instead of showing a number.
- **Quest data updated to QuestieDB 1.0.11:** corrected quest names, levels and prerequisites, plus more German names for quests, creatures and items. The dungeon quest lists are unchanged by this update.

## 1.0.5

### Changes
- **Version number in the add-on settings:** Options → AddOns → Ink & Embers shows the installed version as the first line.
- **Rested XP is now recorded (WoW Forever):** the rested bonus of each XP gain is derived from the change of your rested pool, since the game's message did not carry it. Earlier entries stay as they are (they have no rested value).
- **"By a Hair" medal and "Close calls" tab hidden when the game locks your health:** the medal and the "Close calls" tab need your health at the end of a fight. Where the game does not let the add-on read it, they are now hidden instead of showing up empty, and the medal count stays consistent.
- **Bestiary lists all creatures:** no longer cut off at 24 species; elite kills are included.
- **Retail:** world quests and bonus objectives no longer count as abandoned quests, the profession medal that cannot be reached in Retail is hidden, and Warband bank transfers no longer count as income or expense.

### Fixes
- **Training costs (WoW Forever):** the training plan now uses the updated costs from before the launch; spells that were added or removed are updated too.
- **Companions:** the time you spent together is shown again (a duplicate text key hid it).
- **Moment counts match:** the journey and the album now show the same number of moments.
- **World map:** pins stay visible during combat and are redrawn when it ends; place pins also show for new characters without a journey yet, without constant retrying.
- **Wording:** the diary no longer calls kills "fights", the quest history reads as a proper sentence, no more doubled full stops after durations, remaining German diagnostic texts and archived trainer to-dos are translated in English, and the screenshot option's tooltip mentions elite kills.

## 1.0.4

### Fixes
- **Campfire notes at player-made campfires (WoW Forever):** conversation notes now also appear at campfires built by players, not only at permanent camps. Players sitting there are recognized too, and a short gap in the campfire buff no longer ends the round.

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
