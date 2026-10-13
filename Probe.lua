-- Probe: /udc probe tests which quest, map and journal APIs this client
-- has, so the quest side of the addon is designed against what Forever
-- actually offers instead of retail or Classic assumptions.
--
-- The chat gets a short summary. The full result is stored in the saved
-- variables (UlDungeonCompanionDB.probe), written when the game saves
-- them (logout or /reload), so it can be read from the SavedVariables
-- file afterwards. A few quest IDs are also requested from the server to
-- see whether quest data for quests not in the log can be loaded at all.

-- Vanilla dungeon quests that exist on any 1.12-based client.
local SAMPLE_QUESTS = {
    { id = 166,  title = "The Defias Brotherhood" },
    { id = 2040, title = "Underground Assault" },
    { id = 1486, title = "Deviate Hides" },
    { id = 914,  title = "Leaders of the Fang" },
    { id = 1014, title = "Arugal Must Die" },
    -- Forever seems to have remade some vanilla quests under new IDs; the
    -- vanilla "Wanted: Gath'Ilzogg" and a bogus ID show how the client
    -- answers for a quest that does not exist.
    { id = 169, title = "Wanted: Gath'Ilzogg (vanilla ID)" },
    { id = 7999999, title = "bogus ID" },
}

-- Global paths to look up, grouped so the summary can say which areas
-- are covered. Order matters only for the printout.
local GROUPS = {
    { name = "quest log", paths = {
        "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetInfo", "C_QuestLog.GetLogIndexForQuestID",
        "C_QuestLog.IsOnQuest", "C_QuestLog.GetQuestObjectives", "C_QuestLog.GetQuestDifficultyLevel",
        "C_QuestLog.GetSuggestedGroupSize", "C_QuestLog.GetQuestType", "C_QuestLog.GetQuestTagInfo",
        "C_QuestLog.GetQuestWatchType", "C_QuestLog.AddQuestWatch", "GetNumQuestLogEntries", "GetQuestLogTitle",
        "GetQuestLink", "QuestUtils_GetQuestName", "GetQuestDifficultyColor", "GetQuestGreenRange",
    } },
    { name = "quests not in the log", paths = {
        "C_QuestLog.IsQuestFlaggedCompleted", "C_QuestLog.GetAllCompletedQuestIDs", "C_QuestLog.RequestLoadQuestByID",
        "C_QuestLog.GetTitleForQuestID", "C_QuestLog.GetQuestsOnMap", "C_QuestLog.GetMapForQuestPOIs",
        "C_QuestLog.GetQuestAdditionalHighlights", "C_QuestLog.GetZoneStoryInfo", "C_QuestLog.IsQuestTask",
        "C_QuestLine.GetAvailableQuestLines", "C_QuestLine.GetQuestLineQuests", "C_QuestLine.GetQuestLineInfo",
        "C_TaskQuest.GetQuestsForPlayerByMapID", "C_TaskQuest.GetQuestsOnMap", "C_QuestOffer.GetQuestRequiredCurrencyInfo",
        "C_QuestInfoSystem.GetQuestClassification", "C_PlayerInfo.GetContentDifficultyQuestForPlayer",
        "C_GossipInfo.GetAvailableQuests", "C_GossipInfo.GetActiveQuests", "GetQuestID",
        "C_ContentTracking.GetTrackedIDs", "C_QuestHub.GetQuestHubStatus",
    } },
    { name = "map", paths = {
        "C_Map.GetBestMapForUnit", "C_Map.GetMapInfo", "C_Map.GetPlayerMapPosition", "C_Map.GetMapPosFromWorldPos",
        "C_Map.GetWorldPosFromMapPos", "C_Map.SetUserWaypoint", "C_Map.CanSetUserWaypointOnMap",
        "C_Map.GetMapChildrenInfo", "C_Map.GetMapArtID", "C_SuperTrack.SetSuperTrackedUserWaypoint",
        "C_SuperTrack.SetSuperTrackedQuestID", "C_AreaPoiInfo.GetAreaPOIForMap", "UnitPosition",
        "WorldMapFrame.AddDataProvider", "WorldMapFrame.EnumeratePinsByTemplate", "MapCanvasDataProviderMixin",
        "MapCanvasPinMixin", "DungeonEntrancePinMixin", "FlightPointPinMixin", "QuestPinMixin",
        "QuestOfferPinMixin", "QuestHubPinMixin",
    } },
    { name = "instances", paths = {
        "C_EncounterJournal.GetDungeonEntrancesForMap", "C_EncounterJournal.GetInstanceForGameMap",
        "EJ_GetInstanceInfo", "EJ_GetNumTiers", "EJ_SelectTier", "EJ_GetInstanceByIndex",
        "GetInstanceInfo", "IsInInstance", "GetNumSavedInstances", "C_LFGList.GetActiveEntryInfo",
        "C_LFGList.GetSearchResults", "LFGListFrame",
    } },
    { name = "textures", paths = {
        "C_Texture.GetAtlasInfo",
    } },
}

local function Lookup(path)
    local value = _G
    for part in string.gmatch(path, "[^%.]+") do
        if type(value) ~= "table" then return nil end
        value = value[part]
        if value == nil then return nil end
    end
    return value
end

local function AtlasExists(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function Describe(value)
    local t = type(value)
    if t == "table" then
        local n = 0
        for _ in pairs(value) do n = n + 1 end
        return "table(" .. n .. ")"
    end
    return tostring(value)
end

-- Calls fn in pcall and returns a printable result.
local function Try(fn, ...)
    local results = { pcall(fn, ...) }
    if not results[1] then return "error: " .. tostring(results[2]) end
    local parts = {}
    for i = 2, #results do parts[#parts + 1] = Describe(results[i]) end
    if #parts == 0 then return "nil" end
    return table.concat(parts, ", ")
end

local probe   -- the result table being filled in, also stored in the DB

local function Record(section, key, value)
    probe[section] = probe[section] or {}
    probe[section][key] = value
end

local function ProbeFunctions()
    local present, missing = 0, {}
    for _, group in ipairs(GROUPS) do
        for _, path in ipairs(group.paths) do
            local value = Lookup(path)
            Record("api", path, value ~= nil and type(value) or false)
            if value ~= nil then
                present = present + 1
            else
                missing[#missing + 1] = path
            end
        end
    end
    return present, missing
end

local function ProbePlayer()
    local _, class = UnitClass("player")
    local _, race = UnitRace("player")
    Record("player", "level", UnitLevel("player"))
    Record("player", "class", class)
    Record("player", "race", race)
    Record("player", "faction", UnitFactionGroup("player"))
    Record("player", "mapID", C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    if GetQuestDifficultyColor then
        local level = UnitLevel("player")
        for _, delta in ipairs({ -10, -5, 0, 3, 6 }) do
            Record("difficultyColor", tostring(delta), Try(function()
                local c = GetQuestDifficultyColor(level + delta)
                return c and string.format("%.2f %.2f %.2f", c.r, c.g, c.b) or nil
            end))
        end
    end
end

local function ProbeQuestLog()
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        Record("questLog", "count", Try(C_QuestLog.GetNumQuestLogEntries))
    end
    if C_QuestLog and C_QuestLog.GetInfo then
        local shown = 0
        for index = 1, 60 do
            local ok, info = pcall(C_QuestLog.GetInfo, index)
            if not ok or not info then break end
            if not info.isHeader and shown < 5 then
                shown = shown + 1
                local line = string.format("id %s, level %s, difficulty %s, tag %s, group %s, frequency %s, task %s",
                    tostring(info.questID), tostring(info.level), tostring(info.difficultyLevel),
                    tostring(info.questClassification), tostring(info.suggestedGroup),
                    tostring(info.frequency), tostring(info.isTask))
                Record("questLogEntries", tostring(info.title), line)
                if C_QuestLog.GetQuestTagInfo and info.questID then
                    Record("questLogTags", tostring(info.title), Try(function()
                        local tag = C_QuestLog.GetQuestTagInfo(info.questID)
                        if type(tag) ~= "table" then return tag end
                        return string.format("tagID %s, tagName %s, worldQuestType %s", tostring(tag.tagID),
                            tostring(tag.tagName), tostring(tag.worldQuestType))
                    end))
                end
            end
        end
    end
    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if mapID and C_QuestLog and C_QuestLog.GetQuestsOnMap then
        Record("questLog", "questsOnMap", Try(function()
            local quests = C_QuestLog.GetQuestsOnMap(mapID)
            if type(quests) ~= "table" then return quests end
            local ids = {}
            for i, q in ipairs(quests) do
                if i > 8 then break end
                ids[#ids + 1] = tostring(q.questID) .. (q.isMapIndicatorQuest and "*" or "")
            end
            return #quests .. ": " .. table.concat(ids, " ")
        end))
    end
    if mapID and C_QuestLine and C_QuestLine.GetAvailableQuestLines then
        Record("questLog", "questLinesOnMap", Try(function()
            local lines = C_QuestLine.GetAvailableQuestLines(mapID)
            return type(lines) == "table" and #lines or lines
        end))
    end
    if mapID and C_TaskQuest and C_TaskQuest.GetQuestsForPlayerByMapID then
        Record("questLog", "taskQuestsOnMap", Try(function()
            local quests = C_TaskQuest.GetQuestsForPlayerByMapID(mapID)
            return type(quests) == "table" and #quests or quests
        end))
    end
end

local function ProbeCompleted()
    if not (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then return end
    for _, q in ipairs(SAMPLE_QUESTS) do
        Record("flaggedCompleted", tostring(q.id), Try(C_QuestLog.IsQuestFlaggedCompleted, q.id))
    end
    if C_QuestLog.GetAllCompletedQuestIDs then
        Record("flaggedCompleted", "all", Try(function()
            local ids = C_QuestLog.GetAllCompletedQuestIDs()
            if type(ids) ~= "table" then return ids end
            local first = {}
            for i = 1, math.min(10, #ids) do first[#first + 1] = tostring(ids[i]) end
            -- The whole list too, for running the quest logic outside the game.
            probe.completedAll = {}
            for i, id in ipairs(ids) do probe.completedAll[i] = id end
            return #ids .. ": " .. table.concat(first, " ")
        end))
    end
end

local function ProbeMap()
    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    Record("map", "current", info and string.format("%d %s type %s parent %s", mapID, info.name,
        tostring(info.mapType), tostring(info.parentMapID)) or tostring(mapID))
    if C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap then
        Record("map", "dungeonEntrances", Try(function()
            local list = C_EncounterJournal.GetDungeonEntrancesForMap(mapID)
            if type(list) ~= "table" then return list end
            local names = {}
            for i, e in ipairs(list) do
                if i > 6 then break end
                names[#names + 1] = tostring(e.name) .. "/" .. tostring(e.atlasName)
            end
            return #list .. ": " .. table.concat(names, ", ")
        end))
    end
    if C_Map.CanSetUserWaypointOnMap then
        Record("map", "canSetWaypoint", Try(C_Map.CanSetUserWaypointOnMap, mapID))
    end
    if C_Map.GetWorldPosFromMapPos then
        Record("map", "continentOfCurrent", Try(function()
            local continent = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0.5, 0.5))
            return continent
        end))
    end
    if UnitPosition then
        Record("map", "unitPosition", Try(function()
            local y, x, _, instance = UnitPosition("player")
            return string.format("x %.1f y %.1f instance %s", x or 0, y or 0, tostring(instance))
        end))
    end
    for _, atlas in ipairs({ "Dungeon", "Raid", "QuestNormal", "QuestDaily", "QuestLegendary", "QuestRepeatableTurnin",
        "UI-QuestPoi-OuterGlow", "TaxiNode_Neutral", "poi-door", "Waypoint-MapPin-Untracked" }) do
        Record("atlas", atlas, AtlasExists(atlas))
    end
    if EJ_GetNumTiers then
        Record("journal", "tiers", Try(EJ_GetNumTiers))
    end
    if EJ_GetInstanceByIndex and EJ_SelectTier then
        Record("journal", "firstInstances", Try(function()
            EJ_SelectTier(1)
            local names = {}
            for i = 1, 6 do
                local id, name = EJ_GetInstanceByIndex(i, false)
                if not id then break end
                names[#names + 1] = tostring(id) .. " " .. tostring(name)
            end
            return table.concat(names, ", ")
        end))
    end
end

-- Loading quest data for quests not in the log is asynchronous; the
-- answer lands in QUEST_DATA_LOAD_RESULT.
local waiting = {}
local loadFrame = CreateFrame("Frame")

local function ProbeQuestLoad()
    if not (C_QuestLog and C_QuestLog.RequestLoadQuestByID) then return end
    loadFrame:RegisterEvent("QUEST_DATA_LOAD_RESULT")
    for _, q in ipairs(SAMPLE_QUESTS) do
        waiting[q.id] = q
        Record("questLoad", tostring(q.id), "requested (" .. q.title .. ")")
        pcall(C_QuestLog.RequestLoadQuestByID, q.id)
    end
    -- Titles may already be cached.
    if C_QuestLog.GetTitleForQuestID then
        for _, q in ipairs(SAMPLE_QUESTS) do
            Record("questTitleBefore", tostring(q.id), Try(C_QuestLog.GetTitleForQuestID, q.id))
        end
    end
    -- And again a few seconds later, whether or not the event fired.
    if C_Timer and C_Timer.After then
        C_Timer.After(5, function()
            if not probe then return end
            for _, q in ipairs(SAMPLE_QUESTS) do
                local parts = {}
                if C_QuestLog.GetTitleForQuestID then
                    parts[#parts + 1] = "title " .. Try(C_QuestLog.GetTitleForQuestID, q.id)
                end
                if C_QuestLog.GetQuestDifficultyLevel then
                    parts[#parts + 1] = "difficulty " .. Try(C_QuestLog.GetQuestDifficultyLevel, q.id)
                end
                if C_QuestLog.GetQuestTagInfo then
                    parts[#parts + 1] = "tag " .. Try(function()
                        local tag = C_QuestLog.GetQuestTagInfo(q.id)
                        if type(tag) ~= "table" then return tag end
                        return tostring(tag.tagID) .. "/" .. tostring(tag.tagName)
                    end)
                end
                if HaveQuestData then
                    parts[#parts + 1] = "haveData " .. Try(HaveQuestData, q.id)
                end
                Record("questTitleAfter5s", tostring(q.id), table.concat(parts, ", "))
                print("  questTitleAfter5s." .. q.id .. " = " .. table.concat(parts, ", "))
            end
            UlDC.Print("late quest check done. /reload to write it to the saved variables.")
        end)
    end
end

loadFrame:SetScript("OnEvent", function(self, event, questID, success)
    local q = waiting[questID]
    if not q or not probe then return end
    waiting[questID] = nil
    local parts = { "success " .. tostring(success) }
    if C_QuestLog.GetTitleForQuestID then
        parts[#parts + 1] = "title " .. Try(C_QuestLog.GetTitleForQuestID, questID)
    end
    if C_QuestLog.GetQuestTagInfo then
        parts[#parts + 1] = "tag " .. Try(function()
            local tag = C_QuestLog.GetQuestTagInfo(questID)
            if type(tag) ~= "table" then return tag end
            return tostring(tag.tagID) .. "/" .. tostring(tag.tagName)
        end)
    end
    if C_QuestLog.GetQuestDifficultyLevel then
        parts[#parts + 1] = "difficulty " .. Try(C_QuestLog.GetQuestDifficultyLevel, questID)
    end
    if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification then
        parts[#parts + 1] = "classification " .. Try(C_QuestInfoSystem.GetQuestClassification, questID)
    end
    if C_QuestLog.GetQuestObjectives then
        parts[#parts + 1] = "objectives " .. Try(function()
            local objectives = C_QuestLog.GetQuestObjectives(questID)
            if type(objectives) ~= "table" then return objectives end
            local texts = {}
            for _, o in ipairs(objectives) do texts[#texts + 1] = tostring(o.text) end
            return #objectives .. ": " .. table.concat(texts, "; ")
        end)
    end
    Record("questLoad", tostring(questID), table.concat(parts, ", "))
    UlDC.Print("quest " .. questID .. " (" .. q.title .. "): " .. table.concat(parts, ", "))
    if next(waiting) == nil then
        self:UnregisterEvent("QUEST_DATA_LOAD_RESULT")
        UlDC.Print("probe complete. Log out or /reload to write it to the saved variables.")
    end
end)

function UlDC.RunProbe()
    probe = { version = UlDC.Version(), time = date("%Y-%m-%d %H:%M:%S"), build = { GetBuildInfo() } }
    UlDC.db.probe = probe

    local present, missing = ProbeFunctions()
    ProbePlayer()
    ProbeQuestLog()
    ProbeCompleted()
    ProbeMap()
    ProbeQuestLoad()

    UlDC.Print(string.format("probe: %d of %d APIs present.", present, present + #missing))
    if #missing > 0 then
        print("  missing: " .. table.concat(missing, ", "))
    end
    for section, values in pairs(probe) do
        if type(values) == "table" and section ~= "api" and section ~= "build" and section ~= "completedAll" then
            local keys = {}
            for k in pairs(values) do keys[#keys + 1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do
                print("  " .. section .. "." .. k .. " = " .. tostring(values[k]))
            end
        end
    end
    if next(waiting) == nil then
        UlDC.Print("probe complete. Log out or /reload to write it to the saved variables.")
    else
        UlDC.Print("waiting for quest data from the server...")
    end
end
