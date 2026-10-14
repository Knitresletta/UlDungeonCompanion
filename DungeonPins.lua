-- Dungeon Pins: every instance entrance on the world map, with the level
-- range in the tooltip colored for the player's level.
--
-- Pins are drawn by our own MapCanvasDataProvider from UlDC.DUNGEONS, so
-- nothing of Blizzard's map is touched. The retail map can draw dungeon
-- entrances itself (C_EncounterJournal.GetDungeonEntrancesForMap); when
-- it does on a map, our pin for that entrance is skipped and the level
-- line is added to the game's own tooltip instead, so nothing shows twice.
--
-- /udc pins prints what happened on the open map, /udc dungeons prints the
-- whole list sorted by level.

local PIN_TEMPLATE = "UlDCDungeonPinTemplate"
local GAME_TEMPLATE = "DungeonEntrancePinTemplate"
local NEAR = 0.025  -- normalized map distance under which a game pin counts as ours

local ATLAS = { dungeon = "Dungeon", raid = "Raid" }
local FALLBACK_TEXTURE = "Interface\\Icons\\INV_Misc_Map_01"

local provider
local positions = {}     -- mapID -> { { node=, x=, y= }, ... }
local lastError
local lastDebug = {}     -- what the last refresh did, for /udc pins

------------------------------------------------------------------------
-- Level colors
------------------------------------------------------------------------

-- How an instance relates to the player's level, as text and color.
-- Below the range: red or orange (the game's own difficulty colors for
-- that gap). Inside: yellow. Just above: green. Far above: grey.
function UlDC.LevelFit(levels, playerLevel)
    local lo, hi = levels[1], levels[2]
    playerLevel = playerLevel or UnitLevel("player")
    if playerLevel < lo then
        if lo - playerLevel >= 5 then return "too high", 1, 0.1, 0.1 end
        return "soon", 1, 0.5, 0.25
    elseif playerLevel <= hi then
        return "fits", 1, 1, 0
    elseif playerLevel - hi <= 4 then
        return "easy", 0.25, 0.75, 0.25
    end
    return "outgrown", 0.5, 0.5, 0.5
end

local function LevelText(levels)
    if levels[1] == levels[2] then return tostring(levels[1]) end
    return levels[1] .. "-" .. levels[2]
end

------------------------------------------------------------------------
-- Placement
------------------------------------------------------------------------

-- Projects every node with a continent and world position onto the map
-- and returns the ones that land inside it, with normalized coordinates.
-- Forever-only entrances are stored as map percentages (map, mx, my);
-- turn them into world positions the first time they are needed.
local function ResolveNodes()
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    for _, node in ipairs(UlDC.DUNGEONS) do
        if node.map and not node.x then
            local continentID, world = C_Map.GetWorldPosFromMapPos(node.map, CreateVector2D(node.mx / 100, node.my / 100))
            if continentID and world then
                local wx, wy = world:GetXY()
                if wx and wy then node.continent, node.x, node.y = continentID, wx, wy end
            end
        end
    end
end

local function ProjectNodes(mapID)
    local list = {}
    ResolveNodes()
    local mapInfo = C_Map.GetMapInfo(mapID)
    local tooBig = mapInfo and (mapInfo.mapType == Enum.UIMapType.World or mapInfo.mapType == Enum.UIMapType.Cosmic)
    local continentID = (not tooBig) and C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0.5, 0.5))
    if not continentID then return list end

    for _, node in ipairs(UlDC.DUNGEONS) do
        if node.continent == continentID and node.x then
            local _, pos = C_Map.GetMapPosFromWorldPos(continentID, CreateVector2D(node.x, node.y), mapID)
            if pos then
                local x, y = pos:GetXY()
                if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                    list[#list + 1] = { node = node, x = x, y = y }
                end
            end
        end
    end
    return list
end

local function PositionsFor(mapID)
    local list = positions[mapID]
    if list then return list end
    list = ProjectNodes(mapID)
    positions[mapID] = list
    return list
end

-- Entrances the game draws itself on this map, as a list of normalized
-- positions with names. Empty when the client has no such API.
local function GameEntrances(mapID)
    local list = {}
    if C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap then
        local ok, entrances = pcall(C_EncounterJournal.GetDungeonEntrancesForMap, mapID)
        if ok and type(entrances) == "table" then
            for _, e in ipairs(entrances) do
                if e.position then
                    local x, y = e.position:GetXY()
                    list[#list + 1] = { name = e.name, x = x, y = y }
                end
            end
        end
    end
    return list
end

local function NearGamePin(entry, gamePins)
    for _, g in ipairs(gamePins) do
        local dx, dy = entry.x - g.x, entry.y - g.y
        if dx * dx + dy * dy <= NEAR * NEAR then return g end
    end
    return nil
end

------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------

local function AddLevelLines(node)
    local fit, r, g, b = UlDC.LevelFit(node.levels)
    local kind = node.kind == "raid" and "Raid" or "Dungeon"
    GameTooltip:AddDoubleLine(kind .. ", level " .. LevelText(node.levels), fit, 0.8, 0.8, 0.8, r, g, b)
    if node.wings then
        for _, wing in ipairs(node.wings) do
            local _, wr, wg, wb = UlDC.LevelFit(wing.levels)
            GameTooltip:AddDoubleLine("  " .. wing.name, LevelText(wing.levels), 0.7, 0.7, 0.7, wr, wg, wb)
        end
    end
    if node.entry and UnitLevel("player") < node.entry then
        GameTooltip:AddLine("Requires level " .. node.entry .. " to enter", 1, 0.3, 0.3)
    end
    if node.note then
        GameTooltip:AddLine(node.note, 0.6, 0.6, 0.6, true)
    end
end

-- The game's own entrance pins: append our level lines to their tooltip.
-- Matched by name, so an entrance we do not know is left as it is.
local byName = {}
for _, node in ipairs(UlDC.DUNGEONS) do
    byName[node.name] = byName[node.name] or node
end

local function HookGamePins()
    if DungeonEntrancePinMixin and not DungeonEntrancePinMixin.UlDCHooked then
        DungeonEntrancePinMixin.UlDCHooked = true
        hooksecurefunc(DungeonEntrancePinMixin, "OnMouseEnter", function(pin)
            if not UlDC.enabled.dungeonpins or not GameTooltip:IsShown() then return end
            local name = pin.name or (pin.poiInfo and pin.poiInfo.name)
            local node = name and byName[name]
            if not node then return end
            local ok, err = pcall(AddLevelLines, node)
            if ok then
                GameTooltip:Show()
            elseif err ~= lastError then
                lastError = err
                UlDC.Print("dungeon tooltip error: " .. tostring(err))
            end
        end)
    end
end

------------------------------------------------------------------------
-- Pin
------------------------------------------------------------------------

UlDCDungeonPinMixin = CreateFromMixins(MapCanvasPinMixin)

function UlDCDungeonPinMixin:OnLoad()
    self:SetScalingLimits(1, 1.0, 1.2)
    -- The dungeon entrance level exists on retail; fall back to the flight
    -- point level, which the Forever client is known to have.
    if not pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_DUNGEON_ENTRANCE") then
        self:UseFrameLevelType("PIN_FRAME_LEVEL_FLIGHT_POINT")
    end
end

local function SetIcon(texture, kind)
    local atlas = ATLAS[kind] or ATLAS.dungeon
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        texture:SetAtlas(atlas, true)
        return true
    end
    texture:SetTexture(FALLBACK_TEXTURE)
    texture:SetSize(20, 20)
    return false
end

-- On continent maps the pins are drawn smaller than on zone maps, where
-- the full atlas size stays (Jonatan's call, 14.10.2026).
local CONTINENT_SCALE = 0.75

local function PinScale(map)
    local mapID = map and map.GetMapID and map:GetMapID()
    local info = mapID and C_Map.GetMapInfo(mapID)
    if info and info.mapType == Enum.UIMapType.Continent then return CONTINENT_SCALE end
    return 1
end

function UlDCDungeonPinMixin:OnAcquired(entry)
    self.entry = entry
    local ok, err = pcall(function()
        SetIcon(self.Texture, entry.node.kind)
        SetIcon(self.Highlight, entry.node.kind)
        local scale = PinScale(self:GetMap())
        if scale ~= 1 then
            local w, h = self.Texture:GetSize()
            self.Texture:SetSize(w * scale, h * scale)
            self.Highlight:SetSize(w * scale, h * scale)
        end
        self:SetSize(self.Texture:GetSize())
        local fit = UlDC.LevelFit(entry.node.levels)
        self.Texture:SetDesaturated(fit == "outgrown")
        self:SetAlpha(fit == "outgrown" and 0.6 or 1)
    end)
    if not ok and err ~= lastError then
        lastError = err
        UlDC.Print("dungeon pin error: " .. tostring(err))
    end
    self:SetPosition(entry.x, entry.y)
end

function UlDCDungeonPinMixin:CanSetWaypoint()
    local map = self:GetMap()
    return map ~= nil and C_Map.SetUserWaypoint ~= nil and C_Map.CanSetUserWaypointOnMap ~= nil
        and C_Map.CanSetUserWaypointOnMap(map:GetMapID())
end

function UlDCDungeonPinMixin:OnMouseEnter()
    local node = self.entry.node
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local title = node.name
    if node.label then title = title .. " (" .. node.label .. ")" end
    GameTooltip:AddLine(title, 1, 1, 1)
    AddLevelLines(node)
    if self:CanSetWaypoint() then
        GameTooltip:AddLine("Click to set a waypoint", 0.4, 0.8, 1)
    end
    GameTooltip:Show()
end

function UlDCDungeonPinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

function UlDCDungeonPinMixin:OnMouseClickAction(button)
    if button ~= "LeftButton" or not self:CanSetWaypoint() then return end
    local point = { uiMapID = self:GetMap():GetMapID(), position = CreateVector2D(self.entry.x, self.entry.y) }
    local ok = pcall(C_Map.SetUserWaypoint, point)
    if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
end

------------------------------------------------------------------------
-- Data provider
------------------------------------------------------------------------

local ProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function ProviderMixin:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
end

function ProviderMixin:RefreshAllData()
    self:RemoveAllData()
    if not UlDC.enabled.dungeonpins then return end

    local map = self:GetMap()
    local mapID = map:GetMapID()
    if not mapID then return end

    local gamePins = GameEntrances(mapID)
    local playerFaction = UnitFactionGroup("player")
    local placed, skipped = 0, 0
    for _, entry in ipairs(PositionsFor(mapID)) do
        local node = entry.node
        if node.faction == nil or node.faction == playerFaction then
            if NearGamePin(entry, gamePins) then
                skipped = skipped + 1
            else
                map:AcquirePin(PIN_TEMPLATE, entry)
                placed = placed + 1
            end
        end
    end
    lastDebug = { mapID = mapID, gamePins = #gamePins, placed = placed, skipped = skipped }
end

function UlDC.RefreshDungeonPins()
    if provider and WorldMapFrame and WorldMapFrame:IsShown() then
        provider:RefreshAllData()
    end
end

local function InstallProvider()
    HookGamePins()
    if provider or not WorldMapFrame or not WorldMapFrame.AddDataProvider then return end
    provider = CreateFromMixins(ProviderMixin)
    WorldMapFrame:AddDataProvider(provider)
end

------------------------------------------------------------------------
-- /udc dungeons and /udc pins
------------------------------------------------------------------------

function UlDC.PrintDungeonList()
    local level = UnitLevel("player")
    local playerFaction = UnitFactionGroup("player")
    local seen, list = {}, {}
    for _, node in ipairs(UlDC.DUNGEONS) do
        if not seen[node.name] and (node.faction == nil or node.faction == playerFaction) then
            seen[node.name] = true
            list[#list + 1] = node
        end
    end
    table.sort(list, function(a, b)
        if a.levels[1] ~= b.levels[1] then return a.levels[1] < b.levels[1] end
        return a.name < b.name
    end)
    UlDC.Print("dungeons and raids for level " .. level .. " (yellow fits, green easy, orange soon, red too high, grey outgrown):")
    for _, node in ipairs(list) do
        local fit, r, g, b = UlDC.LevelFit(node.levels)
        local color = string.format("|cff%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
        local kind = node.kind == "raid" and " (raid)" or ""
        print(string.format("  %s%s %s|r  %s%s", color, LevelText(node.levels), node.name, node.zone or "", kind))
    end
end

function UlDC.DungeonPinDebug()
    local mapOpen = WorldMapFrame and WorldMapFrame:IsShown()
    local mapID = (mapOpen and WorldMapFrame:GetMapID()) or C_Map.GetBestMapForUnit("player")
    if not mapID then
        UlDC.Print("no map to inspect.")
        return
    end
    local info = C_Map.GetMapInfo(mapID)
    local continentID = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0.5, 0.5))
    local projected = PositionsFor(mapID)
    local gamePins = GameEntrances(mapID)
    local shown = 0
    if mapOpen then
        for _ in WorldMapFrame:EnumeratePinsByTemplate(PIN_TEMPLATE) do shown = shown + 1 end
    end
    UlDC.Print(string.format("map %d (%s, type %s), continent %s", mapID, info and info.name or "?",
        info and tostring(info.mapType) or "?", tostring(continentID)))
    print(string.format("  entrances projected onto this map: %d, our pins shown: %d, game entrance pins: %d",
        #projected, shown, #gamePins))
    if lastDebug.mapID == mapID then
        print(string.format("  last refresh: placed %d, skipped %d (near a game pin)", lastDebug.placed, lastDebug.skipped))
    end
    for _, entry in ipairs(projected) do
        local near = NearGamePin(entry, gamePins)
        print(string.format("  %s at %.3f, %.3f%s", entry.node.name, entry.x, entry.y,
            near and (" (game draws: " .. tostring(near.name) .. ")") or ""))
    end
    for _, g in ipairs(gamePins) do
        print(string.format("  game: %s at %.3f, %.3f", tostring(g.name), g.x, g.y))
    end
    print("  provider installed: " .. tostring(provider ~= nil) .. ", atlas Dungeon: "
        .. tostring(C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Dungeon") ~= nil)
        .. ", last error: " .. tostring(lastError))
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        InstallProvider()
    elseif event == "PLAYER_LEVEL_UP" then
        -- Colors and dimming depend on the level; redraw if the map is open.
        UlDC.RefreshDungeonPins()
    end
end)
