-- Zone Data: the level range each zone is meant for, keyed by the zone's
-- English name as the client reports it (C_Map.GetMapInfo(...).name).
--
-- The ranges are the classic 1.12 ones. Forever may tune a zone, and its
-- own new zones are not here yet: /udc zones prints the zone maps the
-- client knows that this table does not, so they can be added once their
-- ranges are known. Zones without a range (cities, Moonglade) are left
-- out on purpose; nothing is shown for them.
--
-- Names are matched at runtime (ZoneLabels.lua), so no map IDs are hard
-- coded. DungeonData.lua refers to the same names in its zone field.

UlDC.ZONES = {
    -- Eastern Kingdoms
    ["Elwynn Forest"]        = { levels = { 1, 10 } },
    ["Dun Morogh"]           = { levels = { 1, 10 } },
    ["Tirisfal Glades"]      = { levels = { 1, 10 } },
    ["Westfall"]             = { levels = { 10, 20 } },
    ["Loch Modan"]           = { levels = { 10, 20 } },
    ["Silverpine Forest"]    = { levels = { 10, 20 } },
    ["Redridge Mountains"]   = { levels = { 15, 25 } },
    ["Duskwood"]             = { levels = { 18, 30 } },
    ["Wetlands"]             = { levels = { 20, 30 } },
    ["Hillsbrad Foothills"]  = { levels = { 20, 30 } },
    ["Alterac Mountains"]    = { levels = { 30, 40 } },
    ["Arathi Highlands"]     = { levels = { 30, 40 } },
    ["Stranglethorn Vale"]   = { levels = { 30, 45 } },
    ["Badlands"]             = { levels = { 35, 45 } },
    ["Swamp of Sorrows"]     = { levels = { 35, 45 } },
    ["The Hinterlands"]      = { levels = { 40, 50 } },
    ["Searing Gorge"]        = { levels = { 43, 50 } },
    ["Blasted Lands"]        = { levels = { 45, 55 } },
    ["Burning Steppes"]      = { levels = { 50, 58 } },
    ["Western Plaguelands"]  = { levels = { 51, 58 } },
    ["Eastern Plaguelands"]  = { levels = { 53, 60 } },
    ["Deadwind Pass"]        = { levels = { 55, 60 } },

    -- Kalimdor
    ["Durotar"]              = { levels = { 1, 10 } },
    ["Mulgore"]              = { levels = { 1, 10 } },
    ["Teldrassil"]           = { levels = { 1, 10 } },
    ["The Barrens"]          = { levels = { 10, 25 } },
    ["Darkshore"]            = { levels = { 10, 20 } },
    ["Stonetalon Mountains"] = { levels = { 15, 27 } },
    ["Ashenvale"]            = { levels = { 18, 30 } },
    ["Thousand Needles"]     = { levels = { 25, 35 } },
    ["Desolace"]             = { levels = { 30, 40 } },
    ["Dustwallow Marsh"]     = { levels = { 35, 45 } },
    ["Feralas"]              = { levels = { 40, 50 } },
    ["Tanaris"]              = { levels = { 40, 50 } },
    ["Azshara"]              = { levels = { 45, 55 } },
    ["Felwood"]              = { levels = { 48, 55 } },
    ["Un'Goro Crater"]       = { levels = { 48, 55 } },
    ["Winterspring"]         = { levels = { 55, 60 } },
    ["Silithus"]             = { levels = { 55, 60 } },
}
