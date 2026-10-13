# UlDungeonCompanion

A companion for **World of Warcraft: Forever** players who want to level on their own terms but not miss the group content. It finds the dungeons, dungeon quests and elite quests that fit your level and shows them on the world map and in a browser window. Every feature can be switched off, and settings persist between sessions.

> **Status:** 0.1.0, first scaffold. Dungeon entrances on the map work in principle (same map plumbing as UlRemedyForever's flight paths) but are not yet verified on the Forever beta client. Quest features are not built yet; `/udc probe` exists to find out what the client offers.

## Features

**Dungeon Entrances**: Every dungeon and raid entrance on the world map, with the level range in the tooltip colored for your level: yellow fits, green is easy, orange is soon, red is too high, grey is outgrown. Instances with several wings (Scarlet Monastery, Blackrock Spire, Maraudon, Dire Maul) list each wing with its own range. Instances the map already draws itself keep the game's pin and get the level line added to its tooltip instead. Clicking a pin sets a map waypoint where the client supports it. `/udc dungeons` prints the whole list sorted by level, `/udc pins` prints diagnostics for the open map.

Entrance positions come from the vanilla 1.12 area trigger tables and are projected onto whichever map is open, so Forever's maps need no coordinate tables of their own. Level ranges are the classic ones. Forever-only instances are not included yet.

## Planned

In order. Each step depends on what `/udc probe` reveals about the client.

1. **Dungeon quests and elite quests on the map.** Pins for the quest givers of the quests you have not done and can take at your level. A dungeon quest is any quest, or any quest chain, that at some point requires entering an instance; the whole chain counts and the pin points at the first step you have not done. An elite quest is a group quest in the open world. Faction, race and class restrictions are read from the data, your character's from the client.
2. **A browser window.** The same quests as a list: by dungeon, by zone, by level, with what you have done ticked off.
3. **Learning in play.** Quest givers and instance entrances the shipped data does not know (Forever's new zones) are remembered when you meet them.

## Commands

Type `/udc` to open the options window. Every feature can also be toggled from chat, and `/udc help` prints the full command list.

| Command | Description |
|---------|-------------|
| `/udc dungeonpins` | Toggle dungeon entrance pins on the world map |
| `/udc dungeons` | Print the dungeons and raids sorted by level, colored for your level |
| `/udc pins` | Print dungeon pin diagnostics for the open map |
| `/udc probe` | Test which quest, map and journal APIs the client has; the result is kept in the saved variables |

## Installation

Copy the `UlDungeonCompanion` folder into the `Interface/AddOns/` folder of your World of Warcraft: Forever installation.
