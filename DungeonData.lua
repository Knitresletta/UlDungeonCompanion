-- Dungeon Data: every instance entrance, with the level range the
-- instance is meant for.
--
-- Entrance positions are world coordinates on a continent (0 = Eastern
-- Kingdoms, 1 = Kalimdor) from the vanilla 1.12 data (vmangos). Where the
-- instance has a Meeting Stone, the pin sits on the stone, which stands
-- at the entrance you walk into (for the Deadmines that is the mine
-- house in Moonbrook, not the portal at the end of the tunnel). Instances
-- without a stone use the instance portal's area trigger. At runtime the
-- positions are projected onto whatever map is open, so no map IDs are
-- hard coded; verified on the Forever client 14.10.2026 (Westfall).
-- Level ranges are the classic ones; Forever may tune them, and the entry
-- level is the one the portal enforces.
--
-- key ties an instance to the quests in QuestData.lua. One entry per pin. An instance with entrances far apart (Uldaman,
-- Stratholme) has one entry per entrance with a label; wings with their
-- own level ranges (Scarlet Monastery, Blackrock Spire) are listed under
-- wings and share one pin. Blackwing Lair has no pin of its own since it
-- is entered from inside Blackrock Spire.
--
-- Forever-only instances are not known yet; add them here when the client
-- reveals them (see /udc probe and the learned entrances planned in the
-- README).

UlDC.DUNGEONS = {
    -- Dungeons, by level.
    { key = "rfc", name = "Ragefire Chasm", kind = "dungeon", levels = { 13, 18 }, entry = 8, zone = "Orgrimmar", faction = "Horde",
      continent = 1, x = 1818.30, y = -4402.10 },
    { key = "wc", name = "Wailing Caverns", kind = "dungeon", levels = { 17, 24 }, entry = 10, zone = "The Barrens",
      continent = 1, x = -793.30, y = -2135.60 },
    { key = "deadmines", name = "The Deadmines", kind = "dungeon", levels = { 18, 23 }, entry = 10, zone = "Westfall",
      continent = 0, x = -11089.30, y = 1561.10 },
    { key = "sfk", name = "Shadowfang Keep", kind = "dungeon", levels = { 22, 30 }, entry = 10, zone = "Silverpine Forest",
      continent = 0, x = -247.10, y = 1509.00 },
    { key = "stockade", name = "The Stockade", kind = "dungeon", levels = { 22, 30 }, entry = 15, zone = "Stormwind City", faction = "Alliance",
      continent = 0, x = -8810.50, y = 798.00 },
    { key = "bfd", name = "Blackfathom Deeps", kind = "dungeon", levels = { 24, 32 }, entry = 10, zone = "Ashenvale",
      continent = 1, x = 4075.20, y = 814.20 },
    { key = "gnomeregan", name = "Gnomeregan", kind = "dungeon", levels = { 29, 38 }, entry = 15, zone = "Dun Morogh", label = "Main entrance",
      continent = 0, x = -5203.70, y = 606.70 },
    { key = "gnomeregan", name = "Gnomeregan", kind = "dungeon", levels = { 29, 38 }, entry = 15, zone = "Dun Morogh", label = "Back entrance",
      continent = 0, x = -4858.27, y = 785.03 },
    { key = "rfk", name = "Razorfen Kraul", kind = "dungeon", levels = { 29, 38 }, entry = 15, zone = "The Barrens",
      continent = 1, x = -4465.70, y = -1807.10 },
    { key = "sm", name = "Scarlet Monastery", kind = "dungeon", levels = { 28, 45 }, entry = 20, zone = "Tirisfal Glades",
      continent = 0, x = 2655.90, y = -678.20,
      wings = {
          { name = "Graveyard", levels = { 28, 38 } },
          { name = "Library",   levels = { 29, 39 } },
          { name = "Armory",    levels = { 32, 42 } },
          { name = "Cathedral", levels = { 35, 45 } },
      } },
    { key = "rfd", name = "Razorfen Downs", kind = "dungeon", levels = { 37, 46 }, entry = 25, zone = "The Barrens",
      continent = 1, x = -4666.52, y = -2536.82 },
    { key = "uldaman", name = "Uldaman", kind = "dungeon", levels = { 41, 51 }, entry = 30, zone = "Badlands", label = "Front entrance",
      continent = 0, x = -6116.50, y = -3299.50 },
    { key = "uldaman", name = "Uldaman", kind = "dungeon", levels = { 41, 51 }, entry = 30, zone = "Badlands", label = "Back entrance",
      continent = 0, x = -6606.48, y = -3762.19 },
    { key = "zf", name = "Zul'Farrak", kind = "dungeon", levels = { 44, 54 }, entry = 35, zone = "Tanaris",
      continent = 1, x = -6829.20, y = -2874.30 },
    { key = "maraudon", name = "Maraudon", kind = "dungeon", levels = { 46, 55 }, entry = 30, zone = "Desolace",
      continent = 1, x = -1333.00, y = 2739.76,
      wings = {
          { name = "Orange side", levels = { 46, 52 } },
          { name = "Purple side", levels = { 48, 55 } },
      } },
    { key = "st", name = "The Temple of Atal'Hakkar", kind = "dungeon", levels = { 50, 60 }, entry = 35, zone = "Swamp of Sorrows",
      continent = 0, x = -10457.80, y = -3807.80 },
    { key = "brd", name = "Blackrock Depths", kind = "dungeon", levels = { 52, 60 }, entry = 40, zone = "Blackrock Mountain",
      continent = 0, x = -7176.63, y = -937.67 },
    { key = "brs", name = "Blackrock Spire", kind = "dungeon", levels = { 55, 60 }, entry = 45, zone = "Blackrock Mountain",
      continent = 0, x = -7518.19, y = -1239.13,
      wings = {
          { name = "Lower", levels = { 55, 60 } },
          { name = "Upper", levels = { 58, 60 } },
      },
      note = "Blackwing Lair is entered from Upper Blackrock Spire." },
    { key = "scholo", name = "Scholomance", kind = "dungeon", levels = { 58, 60 }, entry = 45, zone = "Western Plaguelands",
      continent = 0, x = 1232.20, y = -2571.80 },
    { key = "strat", name = "Stratholme", kind = "dungeon", levels = { 58, 60 }, entry = 45, zone = "Eastern Plaguelands", label = "Main gate",
      continent = 0, x = 3372.40, y = -3379.60 },
    { key = "strat", name = "Stratholme", kind = "dungeon", levels = { 58, 60 }, entry = 45, zone = "Eastern Plaguelands", label = "Service entrance",
      continent = 0, x = 3237.46, y = -4060.60 },
    { key = "dm", name = "Dire Maul", kind = "dungeon", levels = { 58, 60 }, entry = 45, zone = "Feralas",
      continent = 1, x = -4427.50, y = 1412.90,
      wings = {
          { name = "East",  levels = { 55, 60 } },
          { name = "West",  levels = { 58, 60 } },
          { name = "North", levels = { 58, 60 } },
      } },

    -- Raids.
    { key = "onyxia", name = "Onyxia's Lair", kind = "raid", levels = { 60, 60 }, entry = 50, zone = "Dustwallow Marsh",
      continent = 1, x = -4768.61, y = -3752.11 },
    { key = "mc", name = "Molten Core", kind = "raid", levels = { 60, 60 }, entry = 50, zone = "Blackrock Mountain",
      continent = 0, x = -7513.22, y = -1033.77,
      note = "The window in Blackrock Mountain; the walk goes through Blackrock Depths." },
    { key = "bwl", name = "Blackwing Lair", kind = "raid", levels = { 60, 60 }, entry = 50, zone = "Blackrock Mountain",
      note = "Entered from Upper Blackrock Spire." },
    { key = "zg", name = "Zul'Gurub", kind = "raid", levels = { 60, 60 }, entry = 50, zone = "Stranglethorn Vale",
      continent = 0, x = -11915.80, y = -1236.43 },
    { key = "aq20", name = "Ruins of Ahn'Qiraj", kind = "raid", levels = { 60, 60 }, entry = 50, zone = "Silithus",
      continent = 1, x = -8424.94, y = 1508.65 },
    { key = "aq40", name = "Temple of Ahn'Qiraj", kind = "raid", levels = { 60, 60 }, entry = 50, zone = "Silithus",
      continent = 1, x = -8230.40, y = 2005.33 },
    { key = "naxx", name = "Naxxramas", kind = "raid", levels = { 60, 60 }, entry = 51, zone = "Eastern Plaguelands",
      continent = 0, x = 3133.15, y = -3730.29 },

    -- Forever additions. Positions are map percentages on retail map IDs
    -- (map, mx, my), read from the beta client by ForeverDB
    -- (https://foreverdb.net) and converted at runtime. Level ranges are
    -- Blizzard's. Five more are announced but not open in the beta yet:
    -- The Drowned City (35-40, Stranglethorn), Krol'dok Stronghold (40-45,
    -- Riverglades), Alcaz Prison (48-53, Dustwallow), Blackmaw Hold (55-60,
    -- Azshara), Shaper's Terrace (58-60, Un'Goro).
    { key = "hot", name = "The Hall of Thanes", kind = "dungeon", levels = { 13, 18 }, zone = "Ironforge", forever = true,
      map = 1455, mx = 43.5, my = 52.0, label = "Passage from the High Seat",
      note = "Enter the throne room, turn left into the web-covered passage, follow the stairs down past the lava to the bridge. Horde has to get through the city." },
    { key = "rol", name = "Ruins of Lordaeron", kind = "dungeon", levels = { 15, 20 }, zone = "Tirisfal Glades", forever = true,
      map = 1420, mx = 63.3, my = 67.5, note = "The ruined capital above the Undercity." },
    { key = "excav", name = "Excavation Site: Wetlands", kind = "dungeon", levels = { 26, 31 }, zone = "Wetlands", forever = true,
      map = 1437, mx = 30.4, my = 40.0, note = "At Whelgar's Excavation Site, east of Menethil Harbor.", },
    { key = "dalaran", name = "City of Dalaran", kind = "dungeon", levels = { 28, 33 }, zone = "Silverpine Forest", forever = true,
      map = 1421, mx = 69.6, my = 46.1, label = "Sewer gate",
      note = "Through the sewers; the gate needs the Dalaran Sewer Key (Heart of Disruption). Alliance enters from inside the city." },
}
