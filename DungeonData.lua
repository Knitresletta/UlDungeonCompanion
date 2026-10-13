-- Dungeon Data: every instance entrance, with the level range the
-- instance is meant for.
--
-- Entrance positions are world coordinates on a continent (0 = Eastern
-- Kingdoms, 1 = Kalimdor), taken from the vanilla 1.12 area trigger tables
-- (vmangos, areatrigger_teleport joined with areatrigger_template). At
-- runtime they are projected onto whatever map is open, so no map IDs
-- are hard coded. Level ranges are the classic ones; Forever may tune
-- them, and the entry level is the one the trigger enforces.
--
-- One entry per pin. An instance with entrances far apart (Uldaman,
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
    { name = "Ragefire Chasm", kind = "dungeon", levels = { 13, 18 }, entry = 8, zone = "Orgrimmar", faction = "Horde",
      continent = 1, x = 1818.40, y = -4427.26 },
    { name = "Wailing Caverns", kind = "dungeon", levels = { 17, 24 }, entry = 10, zone = "The Barrens",
      continent = 1, x = -753.60, y = -2212.78 },
    { name = "The Deadmines", kind = "dungeon", levels = { 18, 23 }, entry = 10, zone = "Westfall",
      continent = 0, x = -11208.50, y = 1685.34 },
    { name = "Shadowfang Keep", kind = "dungeon", levels = { 22, 30 }, entry = 10, zone = "Silverpine Forest",
      continent = 0, x = -229.49, y = 1576.35 },
    { name = "The Stockade", kind = "dungeon", levels = { 22, 30 }, entry = 15, zone = "Stormwind City", faction = "Alliance",
      continent = 0, x = -8758.86, y = 851.10 },
    { name = "Blackfathom Deeps", kind = "dungeon", levels = { 24, 32 }, entry = 10, zone = "Ashenvale",
      continent = 1, x = 4252.37, y = 756.97 },
    { name = "Gnomeregan", kind = "dungeon", levels = { 29, 38 }, entry = 15, zone = "Dun Morogh", label = "Main entrance",
      continent = 0, x = -5161.33, y = 939.62 },
    { name = "Gnomeregan", kind = "dungeon", levels = { 29, 38 }, entry = 15, zone = "Dun Morogh", label = "Back entrance",
      continent = 0, x = -4858.27, y = 785.03 },
    { name = "Razorfen Kraul", kind = "dungeon", levels = { 29, 38 }, entry = 15, zone = "The Barrens",
      continent = 1, x = -4456.70, y = -1655.99 },
    { name = "Scarlet Monastery", kind = "dungeon", levels = { 28, 45 }, entry = 20, zone = "Tirisfal Glades",
      continent = 0, x = 2924.38, y = -798.43,
      wings = {
          { name = "Graveyard", levels = { 28, 38 } },
          { name = "Library",   levels = { 29, 39 } },
          { name = "Armory",    levels = { 32, 42 } },
          { name = "Cathedral", levels = { 35, 45 } },
      } },
    { name = "Razorfen Downs", kind = "dungeon", levels = { 37, 46 }, entry = 25, zone = "The Barrens",
      continent = 1, x = -4666.52, y = -2536.82 },
    { name = "Uldaman", kind = "dungeon", levels = { 41, 51 }, entry = 30, zone = "Badlands", label = "Front entrance",
      continent = 0, x = -6053.73, y = -2954.63 },
    { name = "Uldaman", kind = "dungeon", levels = { 41, 51 }, entry = 30, zone = "Badlands", label = "Back entrance",
      continent = 0, x = -6606.48, y = -3762.19 },
    { name = "Zul'Farrak", kind = "dungeon", levels = { 44, 54 }, entry = 35, zone = "Tanaris",
      continent = 1, x = -6773.49, y = -2889.77 },
    { name = "Maraudon", kind = "dungeon", levels = { 46, 55 }, entry = 30, zone = "Desolace",
      continent = 1, x = -1333.00, y = 2739.76,
      wings = {
          { name = "Orange side", levels = { 46, 52 } },
          { name = "Purple side", levels = { 48, 55 } },
      } },
    { name = "The Temple of Atal'Hakkar", kind = "dungeon", levels = { 50, 60 }, entry = 35, zone = "Swamp of Sorrows",
      continent = 0, x = -10162.70, y = -3998.65 },
    { name = "Blackrock Depths", kind = "dungeon", levels = { 52, 60 }, entry = 40, zone = "Blackrock Mountain",
      continent = 0, x = -7176.63, y = -937.67 },
    { name = "Blackrock Spire", kind = "dungeon", levels = { 55, 60 }, entry = 45, zone = "Blackrock Mountain",
      continent = 0, x = -7518.19, y = -1239.13,
      wings = {
          { name = "Lower", levels = { 55, 60 } },
          { name = "Upper", levels = { 58, 60 } },
      },
      note = "Blackwing Lair is entered from Upper Blackrock Spire." },
    { name = "Scholomance", kind = "dungeon", levels = { 58, 60 }, entry = 45, zone = "Western Plaguelands",
      continent = 0, x = 1282.05, y = -2548.73 },
    { name = "Stratholme", kind = "dungeon", levels = { 58, 60 }, entry = 45, zone = "Eastern Plaguelands", label = "Main gate",
      continent = 0, x = 3392.46, y = -3396.77 },
    { name = "Stratholme", kind = "dungeon", levels = { 58, 60 }, entry = 45, zone = "Eastern Plaguelands", label = "Service entrance",
      continent = 0, x = 3237.46, y = -4060.60 },
    { name = "Dire Maul", kind = "dungeon", levels = { 58, 60 }, entry = 45, zone = "Feralas",
      continent = 1, x = -3806.80, y = 899.50,
      wings = {
          { name = "East",  levels = { 55, 60 } },
          { name = "West",  levels = { 58, 60 } },
          { name = "North", levels = { 58, 60 } },
      } },

    -- Raids.
    { name = "Onyxia's Lair", kind = "raid", levels = { 60, 60 }, entry = 50, zone = "Dustwallow Marsh",
      continent = 1, x = -4768.61, y = -3752.11 },
    { name = "Molten Core", kind = "raid", levels = { 60, 60 }, entry = 50, zone = "Blackrock Mountain",
      continent = 0, x = -7513.22, y = -1033.77,
      note = "The window in Blackrock Mountain; the walk goes through Blackrock Depths." },
    { name = "Blackwing Lair", kind = "raid", levels = { 60, 60 }, entry = 50, zone = "Blackrock Mountain",
      note = "Entered from Upper Blackrock Spire." },
    { name = "Zul'Gurub", kind = "raid", levels = { 60, 60 }, entry = 50, zone = "Stranglethorn Vale",
      continent = 0, x = -11915.80, y = -1236.43 },
    { name = "Ruins of Ahn'Qiraj", kind = "raid", levels = { 60, 60 }, entry = 50, zone = "Silithus",
      continent = 1, x = -8424.94, y = 1508.65 },
    { name = "Temple of Ahn'Qiraj", kind = "raid", levels = { 60, 60 }, entry = 50, zone = "Silithus",
      continent = 1, x = -8230.40, y = 2005.33 },
    { name = "Naxxramas", kind = "raid", levels = { 60, 60 }, entry = 51, zone = "Eastern Plaguelands",
      continent = 0, x = 3133.15, y = -3730.29 },
}
