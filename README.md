# UlDungeonCompanion

A companion for **World of Warcraft: Forever** players who want to level on their own terms but not miss the group content. It finds the dungeons, dungeon quests and elite quests that fit your level and shows them on the world map and in a browser window. Every feature can be switched off, and settings persist between sessions.

> **Status:** 0.5.0, first release, tested on the Forever beta client (build 1.60.1). Dungeon entrances and quest markers are verified in game. Forever's own dungeons and quests come from community data (see below) and grow with the beta.

## Features

**Dungeon Entrances**: Every dungeon and raid entrance on the world map, with the level range in the tooltip colored for your level: yellow fits, green is easy, orange is soon, red is too high, grey is outgrown. Instances with several wings (Scarlet Monastery, Blackrock Spire, Maraudon, Dire Maul) list each wing with its own range. Instances the map already draws itself keep the game's pin and get the level line added to its tooltip instead. On the continent maps the pins are drawn a quarter smaller so they do not crowd the map; zone maps keep the full size. Clicking a pin sets a map waypoint where the client supports it. `/udc dungeons` prints the whole list sorted by level, `/udc pins` prints diagnostics for the open map.

Entrance positions come from the vanilla 1.12 area trigger tables and are projected onto whichever map is open, so Forever's maps need no coordinate tables of their own. Level ranges are the classic ones. The four Forever dungeons open in the beta (The Hall of Thanes, Ruins of Lordaeron, Excavation Site: Wetlands, City of Dalaran) use the map positions the client shows, as read by [ForeverDB](https://foreverdb.net); the five announced for later (The Drowned City, Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold, Shaper's Terrace) are added when the beta opens them.

**Zone Levels**: The level range a zone is meant for and whose territory it is (Alliance, Horde, Contested), under the zone's name when the mouse rests on it on a continent map, colored for your level like the dungeon ranges. The ranges are Forever's own, read from the beta client by ForeverChanges, and they differ from the classic ones in most zones. Zones the client has no range for yet (Mount Hyjal, Shen'dralas) show nothing. `/udc zones` prints every zone with its range and the zone maps the data does not know.

**Quest Givers**: The givers of the dungeon quests and elite quests you can go for, as quest markers on zone maps: pastel pink with a small dungeon or raid badge for steps that lead into an instance, pastel light blue for elite quests in the open world. A dungeon quest is any quest, or any quest chain, that at some point requires entering an instance. The whole chain counts, and the marker points at the first step you have not done yet, so a chain that ends in the Deadmines starts with its first quest in Westfall. The tooltip lists the step, what it leads to and in which instance, with levels in the game's difficulty colors. Quests you have already completed are left out (the client knows, even for quests never in your log), and so are steps already in your log, since the game tracks those itself. Faction, race and class restrictions come from the data, your character's from the client. Shown are goals from eight levels below you to six above. Clicking a marker sets a waypoint.

**Quest Browser**: `/udc quests` (or the button in `/udc`) opens a window with the same steps grouped by the dungeon they lead to, then elite quests and raids. Hover a row for the chain, click it to open the map on the giver's zone with a waypoint.

The quest data is generated from the vanilla 1.12 database by `tools/build_quests.py` (1400 quests: every dungeon, elite and raid quest plus every quest leading up to one, with givers and positions). Every quest the addon is about to show is checked against the server once: quests Forever has removed are hidden, and Forever's own title and level are used where they differ from the old data. The answers are kept between sessions and refreshed after a week.

Quests that are new in Forever (the new dungeons' quests and the reworked chains, such as Alba Fairmoon's road to the Deadmines) come from [ForeverChanges](https://foreverchanges.pro), which reads the beta client and Wowhead's Forever database, via `tools/fetch_forever.py` (78 quests, givers with map positions). The beta only has content up to its current level cap, so the data grows with the beta; vanilla quests Forever kept are covered by the vanilla data.

## Planned

**Learning in play.** Quest givers and instance entrances the shipped data does not know are remembered when you meet them, as a safety net for content no database has yet.

## Commands

Type `/udc` to open the options window. Every feature can also be toggled from chat, and `/udc help` prints the full command list.

| Command | Description |
|---------|-------------|
| `/udc dungeonpins` | Toggle dungeon entrance pins on the world map |
| `/udc questpins` | Toggle quest giver markers on zone maps |
| `/udc zonelevels` | Toggle zone level ranges under the zone name on continent maps |
| `/udc quests` | Open or close the quest browser |
| `/udc qd` | Print the current quest steps and the character filters |
| `/udc qpins` | Print quest marker diagnostics for the open map |
| `/udc dungeons` | Print the dungeons and raids sorted by level, colored for your level |
| `/udc pins` | Print dungeon pin diagnostics for the open map |
| `/udc zones` | Print the zone level ranges and the zones the data does not know |
| `/udc probe` | Test which quest, map and journal APIs the client has; the result is kept in the saved variables |

## Installation

Copy the `UlDungeonCompanion` folder into the `Interface/AddOns/` folder of your World of Warcraft: Forever installation.
