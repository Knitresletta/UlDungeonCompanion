# UlDungeonCompanion

A companion for **World of Warcraft: Forever** players who want to level on their own terms but not miss the group content. It finds the dungeons, dungeon quests and elite quests that fit your level and shows them on the world map and in a browser window. Every feature can be switched off, and settings persist between sessions.

> **Status:** 0.16.0, tested on the Forever launch client (build 1.60.1). Dungeon entrances and quest markers are verified in game. All data comes from Forever sources, nothing from vanilla databases (see below).

## Features

**Dungeon Entrances**: Every dungeon and raid entrance on the world map, with the level range in the tooltip colored for your level: yellow fits, green is easy, orange is soon, red is too high, grey is outgrown. Instances with several wings (Scarlet Monastery, Blackrock Spire, Maraudon, Dire Maul) list each wing with its own range. Instances the map already draws itself keep the game's pin and get the level line added to its tooltip instead. On the continent maps the pins are drawn a quarter smaller so they do not crowd the map; zone maps keep the full size. Clicking a pin marks the entrance. `/udc dungeons` prints the whole list sorted by level, `/udc pins` prints diagnostics for the open map.

Entrance positions are the Forever client's own entrance points as [ForeverDB](https://foreverdb.net) reads them, as map percentages on retail map IDs, except where the author has stood at the entrance in game (The Deadmines, The Hall of Thanes, Excavation Site: Wetlands), which wins. Level ranges are Forever's, from [ForeverChanges](https://foreverchanges.pro). Instances no Forever source places yet (Shadowfang Keep, The Stockade, Stratholme, Zul'Gurub, Naxxramas and the five dungeons announced for later) are listed in the hub without a pin until a source has them.

**Quest Givers**: The givers of the dungeon quests and elite quests you can go for, as quest markers on zone maps: pastel pink with a small dungeon or raid badge for steps that lead into an instance, pastel light blue for elite quests in the open world. A dungeon quest is any quest, or any quest chain, that at some point requires entering an instance. The whole chain counts, and the marker points at the first step you have not done yet, so a chain that ends in the Deadmines starts with its first quest in Westfall. The tooltip lists the step, what it leads to and in which instance, with levels in the game's difficulty colors. Quests you have already completed are left out (the client knows, even for quests never in your log), and so are steps already in your log, since the game tracks those itself. Faction, race and class restrictions come from the data, your character's from the client. Shown are goals from eight levels below you to six above. Clicking a marker on the map marks the giver (see the hub).

**Hub**: `/udc` opens one window that answers "what can I do now?" the moment it opens. Every dungeon and raid your faction can enter is listed once, sorted by level, under "For you now" (fits or easy), "Soon" (within five levels), and "Later" and "Outgrown" folded into a line of names each (click the heading to unfold). A row shows the level range in the colors above, the zone and how many quest steps lead there; the rows start folded, click one to fold its quests out underneath, hover a quest for the chain, click it to mark the giver on the map and open the map there. Markers are the addon's own, so any number can be set at once; a marker stays on the map until you right-click it (or click the row again), and a quest's marker goes away when the quest is done. Quests whose giver stands inside the instance, or that start from an item found there, mark the entrance instead. The Map button marks the entrance, the Loot button folds out the notable drops inside: one line per boss or named creature, its items in quality colors with slot and drop chance, dimmed when your class cannot use them. Hover an item for the game's tooltip, click it to put the link in an open chat box. Elite quests in the open world have a row of their own. The feature switches live behind the Settings button.

The loot comes from [ForeverChanges](https://foreverchanges.pro) via `tools/fetch_loot.py`: every boss and rare spawn of the dungeons it covers, with the drops players have seen on Forever, Forever's own additions marked new, and drop chances where known. The raids are not on the site yet, so their rows say so; nothing is filled in from vanilla loot tables.

The quest data is generated from [ForeverChanges](https://foreverchanges.pro) by `tools/fetch_forever.py`, which reads every quest page the site lists (about 5200) and the quest lists of its dungeon pages: every dungeon, elite and raid quest Forever has, plus every quest leading up to one, with givers and map positions, chains, sides and classes as Forever has them. Breadcrumb quests ("speak with X", where X then gives the real quest) are recognised and count as done once the quest they lead to is in your log. Every quest the addon is about to show is also checked against the server once: removed quests are hidden, and the server's own title and level win. The answers are kept between sessions and refreshed after a week.

Forever sources only: the vanilla 1.12 database is not used for anything, not even as a fallback. Where a Forever source does not know something yet (a loot table, an entrance, where a quest item drops), the addon says so instead of guessing from vanilla.

**Minimap menu**: No minimap button of its own. When [UlRemedyForever](https://github.com/Knitresletta/UlRemedyForever) is installed, its minimap button's right-click menu gets a "Dungeon Companion" row that opens the hub. UlDungeonCompanion registers itself there at login and works unchanged without it. One optional dependency in the TOC, one global read, nothing else shared.

## Planned

**Learning in play.** Quest givers and instance entrances the shipped data does not know are remembered when you meet them, as a safety net for content no database has yet.

## Commands

Type `/udc` to open the hub. Every feature can also be toggled from chat, and `/udc help` prints the full command list.

| Command | Description |
|---------|-------------|
| `/udc dungeonpins` | Toggle dungeon entrance pins on the world map |
| `/udc questpins` | Toggle quest giver markers on zone maps |
| `/udc quests` | Open or close the hub (same as `/udc`) |
| `/udc marks` | List the map markers |
| `/udc clearmarks` | Remove every map marker |
| `/udc settings` | Open or close the settings window |
| `/udc qd` | Print the current quest steps and the character filters |
| `/udc qpins` | Print quest marker diagnostics for the open map |
| `/udc dungeons` | Print the dungeons and raids sorted by level, colored for your level |
| `/udc pins` | Print dungeon pin diagnostics for the open map |
| `/udc probe` | Test which quest, map and journal APIs the client has; the result is kept in the saved variables |

## Installation

Copy the `UlDungeonCompanion` folder into the `Interface/AddOns/` folder of your World of Warcraft: Forever installation.
