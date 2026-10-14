-- Marks: the player's own map markers, as many as wanted at once.
--
-- The game's user waypoint allows one at a time, so the hub and the pins
-- keep their own set instead: UlDungeonCompanionDB.marks, keyed "q<questID>"
-- for a quest step and "e<dungeonKey>" for an entrance. Each mark holds a
-- label and a world position (continent, x, y), or a map position
-- (map, mx, my in percent) for Forever entrances, resolved on first draw.
-- A MapCanvasDataProvider projects every mark onto whatever map is open,
-- zone or continent, the way the dungeon pins are placed. A marker stays
-- until it is right-clicked (Jonatan's call, 15.10.2026); a quest mark
-- also goes away by itself once the quest is done. Nothing here touches the game's own waypoint.

local PIN_TEMPLATE = "UlDCMarkPinTemplate"
local ATLAS = "Waypoint-MapPin-Untracked"
local SCALE = 0.85

local provider
local lastError

-- Continent instance ID -> the continent's uiMapID, used to find the zone
-- under a world position. Retail IDs, verified on Forever (Stormwind's
-- parent is 1415). The hub and the quest pin diagnostics read this too.
local CONTINENT_MAP = { [0] = 1415, [1] = 1414 }
UlDC.CONTINENT_MAP = CONTINENT_MAP

------------------------------------------------------------------------
-- The set
------------------------------------------------------------------------

local function Marks()
    if not UlDC.db then return {} end
    UlDC.db.marks = UlDC.db.marks or {}
    return UlDC.db.marks
end

function UlDC.IsMarked(key)
    return Marks()[key] ~= nil
end

function UlDC.MarkCount()
    local n = 0
    for _ in pairs(Marks()) do n = n + 1 end
    return n
end

-- Adds the mark under key, or removes it when it is already there.
-- Returns true when the mark is set afterwards.
function UlDC.ToggleMark(key, mark)
    local marks = Marks()
    if marks[key] then
        marks[key] = nil
    elseif mark then
        marks[key] = mark
    end
    UlDC.RefreshMarks()
    if UlDC.RefreshHub then UlDC.RefreshHub() end
    return marks[key] ~= nil
end

function UlDC.ClearMarks()
    local marks = Marks()
    for key in pairs(marks) do marks[key] = nil end
    UlDC.RefreshMarks()
    if UlDC.RefreshHub then UlDC.RefreshHub() end
end

-- A mark on an entrance node from DungeonData.
function UlDC.EntranceMark(node)
    local label = node.name
    if node.label then label = label .. " (" .. node.label .. ")" end
    local mark = { label = label, note = "Entrance" }
    if node.x then
        mark.continent, mark.x, mark.y = node.continent, node.x, node.y
    elseif node.map then
        mark.map, mark.mx, mark.my = node.map, node.mx, node.my
    else
        return nil
    end
    return mark
end

-- Quest marks whose quest has been done since are dropped.
local function Prune()
    if not UlDC.IsQuestCompleted then return end
    local marks = Marks()
    for key, mark in pairs(marks) do
        if mark.quest and UlDC.IsQuestCompleted(mark.quest) then marks[key] = nil end
    end
end

------------------------------------------------------------------------
-- Positions
------------------------------------------------------------------------

-- The zone map and normalized position for a world position.
function UlDC.ZoneForWorldPos(continent, x, y)
    local continentMap = CONTINENT_MAP[continent]
    if not continentMap then return nil end
    local _, pos = C_Map.GetMapPosFromWorldPos(continent, CreateVector2D(x, y), continentMap)
    if not pos then return nil end
    local cx, cy = pos:GetXY()
    local zone = C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(continentMap, cx, cy)
    local mapID = zone and zone.mapID or continentMap
    local _, zpos = C_Map.GetMapPosFromWorldPos(continent, CreateVector2D(x, y), mapID)
    local zx, zy
    if zpos then zx, zy = zpos:GetXY() end
    return mapID, zx, zy
end

-- World position of a mark, converting a map position once.
local function WorldPos(mark)
    if mark.x then return mark.continent, mark.x, mark.y end
    if mark.map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local continentID, world = C_Map.GetWorldPosFromMapPos(mark.map, CreateVector2D(mark.mx / 100, mark.my / 100))
        if continentID and world then
            local wx, wy = world:GetXY()
            if wx and wy then mark.continent, mark.x, mark.y = continentID, wx, wy end
        end
    end
    return mark.continent, mark.x, mark.y
end

-- Opens the world map on the zone that holds the mark.
function UlDC.ShowMark(mark)
    local mapID
    local continent, x, y = WorldPos(mark)
    if continent and x then
        local ok, zone = pcall(UlDC.ZoneForWorldPos, continent, x, y)
        if ok then mapID = zone end
    end
    mapID = mapID or mark.map
    if not mapID then return end
    if OpenWorldMap then
        OpenWorldMap(mapID)
    elseif WorldMapFrame then
        WorldMapFrame:SetMapID(mapID)
        if not WorldMapFrame:IsShown() then ShowUIPanel(WorldMapFrame) end
    end
end

-- Every mark that lands on this map, with normalized coordinates.
local function Place(mapID)
    local list = {}
    local mapInfo = C_Map.GetMapInfo(mapID)
    local tooBig = mapInfo and (mapInfo.mapType == Enum.UIMapType.World or mapInfo.mapType == Enum.UIMapType.Cosmic)
    local continentID = (not tooBig) and C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0.5, 0.5))
    if not continentID then return list end
    for key, mark in pairs(Marks()) do
        local continent, wx, wy = WorldPos(mark)
        if continent == continentID and wx then
            local _, pos = C_Map.GetMapPosFromWorldPos(continentID, CreateVector2D(wx, wy), mapID)
            local x, y
            if pos then x, y = pos:GetXY() end
            if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                list[#list + 1] = { key = key, mark = mark, x = x, y = y }
            end
        end
    end
    return list
end

------------------------------------------------------------------------
-- Pin
------------------------------------------------------------------------

UlDCMarkPinMixin = CreateFromMixins(MapCanvasPinMixin)

-- The map canvas lets right-clicks fall through pins so a right-click
-- zooms the map out; this pin wants them itself. Cleared on load and
-- again on every acquire, since the canvas sets the pass-through after
-- creating a pin.
local function KeepRightClicks(pin)
    if pin.SetPassThroughButtons then pcall(pin.SetPassThroughButtons, pin) end
end

function UlDCMarkPinMixin:OnLoad()
    self:SetScalingLimits(1, 1.0, 1.2)
    -- Above the quest and entrance pins, since a mark sits on top of one.
    if not pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_WAYPOINT_LOCATION") then
        if not pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_AREA_POI") then
            self:UseFrameLevelType("PIN_FRAME_LEVEL_FLIGHT_POINT")
        end
    end
    KeepRightClicks(self)
end

function UlDCMarkPinMixin:OnAcquired(entry)
    self.entry = entry
    KeepRightClicks(self)
    local ok, err = pcall(function()
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ATLAS) then
            self.Texture:SetAtlas(ATLAS, true)
            self.Highlight:SetAtlas(ATLAS, true)
            local w, h = self.Texture:GetSize()
            self.Texture:SetSize(w * SCALE, h * SCALE)
            self.Highlight:SetSize(w * SCALE, h * SCALE)
        end
        self:SetSize(self.Texture:GetSize())
    end)
    if not ok and err ~= lastError then
        lastError = err
        UlDC.Print("mark pin error: " .. tostring(err))
    end
    self:SetPosition(entry.x, entry.y)
end

function UlDCMarkPinMixin:OnMouseEnter()
    local mark = self.entry.mark
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(mark.label or "Marker", 1, 1, 1)
    if mark.note then GameTooltip:AddLine(mark.note, 0.8, 0.8, 0.8) end
    GameTooltip:AddLine("Right-click to remove the marker", 0.4, 0.8, 1)
    GameTooltip:Show()
end

function UlDCMarkPinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

function UlDCMarkPinMixin:OnMouseClickAction(button)
    if button ~= "RightButton" then return end
    UlDC.ToggleMark(self.entry.key)
end

-- The canvas routes clicks to OnMouseClickAction through OnMouseUp; take
-- the right button here too, in case that route only carries the left.
function UlDCMarkPinMixin:OnMouseUp(button, upInside)
    if button == "RightButton" and upInside ~= false then
        UlDC.ToggleMark(self.entry.key)
        return
    end
    if MapCanvasPinMixin.OnMouseUp then MapCanvasPinMixin.OnMouseUp(self, button, upInside) end
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
    local map = self:GetMap()
    local mapID = map:GetMapID()
    if not mapID then return end
    Prune()
    local ok, entries = pcall(Place, mapID)
    if not ok then
        if entries ~= lastError then
            lastError = entries
            UlDC.Print("mark placement error: " .. tostring(entries))
        end
        return
    end
    for _, entry in ipairs(entries) do
        map:AcquirePin(PIN_TEMPLATE, entry)
    end
end

function UlDC.RefreshMarks()
    if provider and WorldMapFrame and WorldMapFrame:IsShown() then
        provider:RefreshAllData()
    end
end

local function InstallProvider()
    if provider or not WorldMapFrame or not WorldMapFrame.AddDataProvider then return end
    provider = CreateFromMixins(ProviderMixin)
    WorldMapFrame:AddDataProvider(provider)
end

function UlDC.PrintMarks()
    local n = UlDC.MarkCount()
    UlDC.Print(n == 0 and "no map markers." or (n .. " map marker" .. (n == 1 and "" or "s") .. ":"))
    for key, mark in pairs(Marks()) do
        print("  " .. tostring(mark.label) .. (mark.note and (" (" .. mark.note .. ")") or "") .. "  [" .. key .. "]")
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function() InstallProvider() end)
