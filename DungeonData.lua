-- Dungeon Data: every instance, with the level range Forever gives it and
-- where its entrance is on the map.
--
-- Forever sources only (Jonatan, 06.11.2026), nothing from vanilla tables:
--  * Level ranges are ForeverChanges' (https://foreverchanges.pro, the
--    dungeon list on every /dungeons/<slug> page, read 06.11.2026), wings
--    with their own ranges where the site lists them.
--  * Entrance positions are map percentages on retail map IDs
--    (map, mx, my), converted to world positions at runtime (DungeonPins).
--    They are the client's own entrance points as ForeverDB reads them
--    (https://foreverdb.net/dungeon/<id>, 06.11.2026), except where Jonatan
--    has stood at the entrance in game, which wins (noted per entry).
--    The client's point can be the portal rather than where you walk in
--    (Hall of Thanes). An instance without a position has none in any
--    Forever source yet: the hub still lists it, the map shows no pin and
--    the Map button does nothing.
--  * The map can draw entrances itself (C_EncounterJournal); DungeonPins
--    skips ours where it does.
--
-- key ties an instance to the quests in QuestData.lua. One entry per
-- instance. faction limits who can enter the city it sits in. Blackwing
-- Lair is entered from inside Blackrock Spire and has no pin of its own.

UlDC.DUNGEONS = {
    -- Dungeons, by level.
    { key = "hot", name = "The Hall of Thanes", kind = "dungeon", levels = { 13, 18 }, zone = "Ironforge", faction = "Alliance", forever = true,
      map = 1455, mx = 43.5, my = 52.0, label = "Passage from the High Seat",
      note = "Enter the throne room, turn left into the web-covered passage, follow the stairs down past the lava to the bridge. Horde has to get through the city. Position seen in game 14.10.2026; the client's own point (77.1, 51.3) is the portal under the city." },
    { key = "rfc", name = "Ragefire Chasm", kind = "dungeon", levels = { 13, 18 }, zone = "Orgrimmar", faction = "Horde",
      map = 1454, mx = 53.0, my = 48.9 },
    { key = "rol", name = "Ruins of Lordaeron", kind = "dungeon", levels = { 15, 20 }, zone = "Tirisfal Glades", forever = true,
      map = 1420, mx = 63.3, my = 67.5, note = "The ruined capital above the Undercity." },
    { key = "wc", name = "Wailing Caverns", kind = "dungeon", levels = { 17, 24 }, zone = "The Barrens",
      map = 1413, mx = 47.7, my = 35.0 },
    { key = "deadmines", name = "The Deadmines", kind = "dungeon", levels = { 17, 26 }, zone = "Westfall",
      map = 1436, mx = 41.8, my = 72.5, label = "Mine house in Moonbrook",
      note = "Where you walk in, seen in game 14.10.2026; the client's own point (38.2, 77.5) is the portal at the end of the tunnel." },
    { key = "sfk", name = "Shadowfang Keep", kind = "dungeon", levels = { 22, 30 }, zone = "Silverpine Forest" },
    { key = "bfd", name = "Blackfathom Deeps", kind = "dungeon", levels = { 24, 32 }, zone = "Ashenvale",
      map = 1440, mx = 16.5, my = 11.0 },
    { key = "stockade", name = "The Stockade", kind = "dungeon", levels = { 24, 32 }, zone = "Stormwind City", faction = "Alliance" },
    { key = "excav", name = "Excavation Site: Wetlands", kind = "dungeon", levels = { 26, 31 }, zone = "Wetlands", forever = true,
      map = 1437, mx = 47.7, my = 61.8,
      note = "In the hills south of the road, between Whelgar's Excavation Site and Dun Algaz. Seen in game 14.10.2026; the client's own point (24.5, 73.4) is far to the south-west." },
    { key = "dalaran", name = "City of Dalaran", kind = "dungeon", levels = { 28, 33 }, zone = "Silverpine Forest", forever = true,
      map = 1421, mx = 69.6, my = 46.1, label = "Sewer gate",
      note = "Through the sewers; the gate needs the Dalaran Sewer Key (Heart of Disruption). Alliance enters from inside the city." },
    { key = "gnomeregan", name = "Gnomeregan", kind = "dungeon", levels = { 29, 38 }, zone = "Dun Morogh",
      map = 1426, mx = 17.7, my = 39.1 },
    { key = "rfk", name = "Razorfen Kraul", kind = "dungeon", levels = { 29, 38 }, zone = "The Barrens",
      map = 1413, mx = 42.3, my = 89.9 },
    { key = "sm", name = "Scarlet Monastery", kind = "dungeon", levels = { 30, 46 }, zone = "Tirisfal Glades",
      map = 1420, mx = 85.1, my = 31.4,
      wings = {
          { name = "Graveyard", levels = { 30, 38 } },
          { name = "Library",   levels = { 33, 41 } },
          { name = "Armory",    levels = { 36, 44 } },
          { name = "Cathedral", levels = { 38, 46 } },
      } },
    { key = "drowned", name = "The Drowned City", kind = "dungeon", levels = { 35, 40 }, zone = "Stranglethorn Vale", forever = true,
      note = "No entrance position in any Forever source yet." },
    { key = "rfd", name = "Razorfen Downs", kind = "dungeon", levels = { 37, 46 }, zone = "The Barrens",
      map = 1413, mx = 50.9, my = 92.9 },
    { key = "kroldok", name = "Krol'dok Stronghold", kind = "dungeon", levels = { 40, 45 }, zone = "Riverglades", forever = true,
      note = "No entrance position in any Forever source yet." },
    { key = "uldaman", name = "Uldaman", kind = "dungeon", levels = { 41, 51 }, zone = "Badlands",
      map = 1418, mx = 35.2, my = 10.3 },
    { key = "zf", name = "Zul'Farrak", kind = "dungeon", levels = { 44, 54 }, zone = "Tanaris",
      map = 1446, mx = 38.7, my = 19.9 },
    { key = "maraudon", name = "Maraudon", kind = "dungeon", levels = { 46, 55 }, zone = "Desolace",
      map = 1443, mx = 29.1, my = 62.9 },
    { key = "alcaz", name = "Alcaz Prison", kind = "dungeon", levels = { 48, 53 }, zone = "Dustwallow Marsh", forever = true,
      note = "No entrance position in any Forever source yet." },
    { key = "st", name = "The Temple of Atal'Hakkar", kind = "dungeon", levels = { 50, 60 }, zone = "Swamp of Sorrows",
      map = 1435, mx = 77.3, my = 35.9 },
    { key = "brd", name = "Blackrock Depths", kind = "dungeon", levels = { 52, 60 }, zone = "Searing Gorge",
      map = 1427, mx = 27.1, my = 72.5 },
    { key = "dm", name = "Dire Maul", kind = "dungeon", levels = { 54, 60 }, zone = "Feralas",
      map = 1444, mx = 62.0, my = 33.3,
      wings = {
          { name = "East",  levels = { 54, 60 } },
          { name = "North", levels = { 56, 60 } },
          { name = "West",  levels = { 56, 60 } },
      } },
    { key = "blackmaw", name = "Blackmaw Hold", kind = "dungeon", levels = { 55, 60 }, zone = "Azshara", forever = true,
      note = "No entrance position in any Forever source yet." },
    { key = "brs", name = "Blackrock Spire", kind = "dungeon", levels = { 55, 60 }, zone = "Burning Steppes",
      map = 1428, mx = 33.0, my = 25.2,
      wings = {
          { name = "Lower", levels = { 55, 60 } },
          { name = "Upper", levels = { 59, 60 } },
      },
      note = "Blackwing Lair is entered from Upper Blackrock Spire." },
    { key = "scholo", name = "Scholomance", kind = "dungeon", levels = { 58, 60 }, zone = "Western Plaguelands",
      map = 1422, mx = 69.0, my = 73.0 },
    { key = "shapers", name = "Shaper's Terrace", kind = "dungeon", levels = { 58, 60 }, zone = "Un'Goro Crater", forever = true,
      note = "No entrance position in any Forever source yet." },
    { key = "strat", name = "Stratholme", kind = "dungeon", levels = { 58, 60 }, zone = "Eastern Plaguelands",
      wings = {
          { name = "Main Gate",    levels = { 58, 60 } },
          { name = "Service Gate", levels = { 58, 60 } },
      },
      note = "No entrance position in any Forever source yet." },
    -- Raids. Level ranges from ForeverChanges' quest categories (all 60).
    { key = "onyxia", name = "Onyxia's Lair", kind = "raid", levels = { 60, 60 }, zone = "Dustwallow Marsh",
      map = 1445, mx = 52.9, my = 77.7 },
    { key = "mc", name = "Molten Core", kind = "raid", levels = { 60, 60 }, zone = "Burning Steppes",
      map = 1428, mx = 26.3, my = 24.6,
      note = "The window in Blackrock Mountain; the walk goes through Blackrock Depths." },
    { key = "bwl", name = "Blackwing Lair", kind = "raid", levels = { 60, 60 }, zone = "Burning Steppes",
      note = "Entered from Upper Blackrock Spire." },
    { key = "zg", name = "Zul'Gurub", kind = "raid", levels = { 60, 60 }, zone = "Stranglethorn Vale",
      note = "No entrance position in any Forever source yet." },
    { key = "aq20", name = "Ruins of Ahn'Qiraj", kind = "raid", levels = { 60, 60 }, zone = "Silithus",
      map = 1451, mx = 29.0, my = 92.8 },
    { key = "aq40", name = "Temple of Ahn'Qiraj", kind = "raid", levels = { 60, 60 }, zone = "Silithus",
      map = 1451, mx = 29.0, my = 92.7 },
    { key = "naxx", name = "Naxxramas", kind = "raid", levels = { 60, 60 }, zone = "Eastern Plaguelands",
      note = "No entrance position in any Forever source yet." },
}
