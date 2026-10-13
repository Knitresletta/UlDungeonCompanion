-- Quest Pins: the giver of every current step (see Quests.lua) on the
-- world map, as a quest marker with a small dungeon, elite or raid badge.
--
-- Givers are world positions from the data, projected onto the open map
-- like the dungeon entrances. Several steps from the same giver share one
-- pin and one tooltip. Steps already in the log get no pin: the game's
-- own objective tracking takes over from there. Zone maps only; the
-- continent maps would drown in markers.

local PIN_TEMPLATE = "UlDCQuestPinTemplate"
local MERGE = 0.012  -- normalized map distance under which givers share a pin

local provider
local lastError
local lastDebug = {}

------------------------------------------------------------------------
-- Placement
------------------------------------------------------------------------

-- Every step giver on this map: { x, y, steps = { step, ... }, giver = name }.
local function Place(mapID)
    local list = {}
    local mapInfo = C_Map.GetMapInfo(mapID)
    if not mapInfo or (mapInfo.mapType ~= Enum.UIMapType.Zone and mapInfo.mapType ~= Enum.UIMapType.Micro) then
        return list
    end
    local continentID = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0.5, 0.5))
    if not continentID then return list end

    for _, step in ipairs(UlDC.CurrentSteps()) do
        if not step.inLog and step.quest.g then
            for _, giver in ipairs(step.quest.g) do
                for _, p in ipairs(giver.pos or {}) do
                    if p[1] == continentID then
                        -- "pos and pos:GetXY()" would keep only the first value.
                        local _, pos = C_Map.GetMapPosFromWorldPos(continentID, CreateVector2D(p[2], p[3]), mapID)
                        local x, y
                        if pos then x, y = pos:GetXY() end
                        if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                            local entry
                            for _, e in ipairs(list) do
                                if math.abs(e.x - x) < MERGE and math.abs(e.y - y) < MERGE then entry = e break end
                            end
                            if not entry then
                                entry = { x = x, y = y, steps = {}, giver = giver.n }
                                list[#list + 1] = entry
                            end
                            entry.steps[#entry.steps + 1] = step
                        end
                    end
                end
            end
        end
    end
    return list
end

------------------------------------------------------------------------
-- Pin
------------------------------------------------------------------------

UlDCQuestPinMixin = CreateFromMixins(MapCanvasPinMixin)

function UlDCQuestPinMixin:OnLoad()
    self:SetScalingLimits(1, 1.0, 1.2)
    if not pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_QUEST_OFFER") then
        self:UseFrameLevelType("PIN_FRAME_LEVEL_FLIGHT_POINT")
    end
end

local function EntryFlags(entry)
    local flags = 0
    for _, step in ipairs(entry.steps) do flags = bit.bor(flags, step.flags) end
    return flags
end

function UlDCQuestPinMixin:OnAcquired(entry)
    self.entry = entry
    local ok, err = pcall(function()
        local flags = EntryFlags(entry)
        local badge = bit.band(flags, UlDC.FLAG_RAID) ~= 0 and "Raid" or
                      bit.band(flags, UlDC.FLAG_DUNGEON) ~= 0 and "Dungeon" or nil
        if badge then
            self.Badge:SetAtlas(badge)
            self.Badge:Show()
        else
            self.Badge:Hide()
        end
        -- Elite-only steps get the marker tinted so they stand apart.
        if not badge then
            self.Texture:SetVertexColor(1, 0.7, 0.7)
        else
            self.Texture:SetVertexColor(1, 1, 1)
        end
        local tooLow = true
        for _, step in ipairs(entry.steps) do
            if not step.tooLow then tooLow = false end
        end
        self:SetAlpha(tooLow and 0.5 or 1)
    end)
    if not ok and err ~= lastError then
        lastError = err
        UlDC.Print("quest pin error: " .. tostring(err))
    end
    self:SetPosition(entry.x, entry.y)
end

function UlDCQuestPinMixin:CanSetWaypoint()
    local map = self:GetMap()
    return map ~= nil and C_Map.SetUserWaypoint ~= nil and C_Map.CanSetUserWaypointOnMap ~= nil
        and C_Map.CanSetUserWaypointOnMap(map:GetMapID())
end

-- Tooltip lines for one step: the step itself, then what it leads to.
function UlDC.AddStepLines(step, playerLevel)
    local q = step.quest
    local r, g, b = UlDC.LevelColor(q.l)
    GameTooltip:AddDoubleLine(q.t, "[" .. q.l .. "]", 1, 1, 1, r, g, b)
    if step.tooLow then
        GameTooltip:AddLine("  Requires level " .. (q.m or 0), 1, 0.3, 0.3)
    end
    for _, goalID in ipairs(step.goals) do
        if goalID ~= step.id then
            local goal = UlDC.QUESTS[goalID]
            local gr, gg, gb = UlDC.LevelColor(goal.l)
            local where = {}
            for _, k in ipairs(goal.d or {}) do where[#where + 1] = UlDC.DungeonName(k) end
            local label = UlDC.FlagText(goal.f)
            if #where > 0 then label = label .. ": " .. table.concat(where, ", ") end
            GameTooltip:AddDoubleLine("  leads to " .. goal.t, "[" .. goal.l .. "] " .. label, 0.8, 0.8, 0.8, gr, gg, gb)
        else
            local where = {}
            for _, k in ipairs(q.d or {}) do where[#where + 1] = UlDC.DungeonName(k) end
            local label = UlDC.FlagText(q.f or 0)
            if #where > 0 then label = label .. ": " .. table.concat(where, ", ") end
            GameTooltip:AddLine("  " .. label, 0.8, 0.8, 0.8)
        end
    end
end

function UlDCQuestPinMixin:OnMouseEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.entry.giver or "Quest giver", 1, 0.82, 0)
    local level = UnitLevel("player")
    for _, step in ipairs(self.entry.steps) do
        UlDC.AddStepLines(step, level)
    end
    if self:CanSetWaypoint() then
        GameTooltip:AddLine("Click to set a waypoint", 0.4, 0.8, 1)
    end
    GameTooltip:Show()
end

function UlDCQuestPinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

function UlDCQuestPinMixin:OnMouseClickAction(button)
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
    if not UlDC.enabled.questpins then return end
    local map = self:GetMap()
    local mapID = map:GetMapID()
    if not mapID then return end
    local ok, entries = pcall(Place, mapID)
    if not ok then
        if entries ~= lastError then
            lastError = entries
            UlDC.Print("quest pin placement error: " .. tostring(entries))
        end
        return
    end
    for _, entry in ipairs(entries) do
        map:AcquirePin(PIN_TEMPLATE, entry)
    end
    lastDebug = { mapID = mapID, placed = #entries }
end

function UlDC.RefreshQuestPins()
    if provider and WorldMapFrame and WorldMapFrame:IsShown() then
        provider:RefreshAllData()
    end
end

local function InstallProvider()
    if provider or not WorldMapFrame or not WorldMapFrame.AddDataProvider then return end
    provider = CreateFromMixins(ProviderMixin)
    WorldMapFrame:AddDataProvider(provider)
end

function UlDC.QuestPinDebug()
    local mapOpen = WorldMapFrame and WorldMapFrame:IsShown()
    local mapID = (mapOpen and WorldMapFrame:GetMapID()) or C_Map.GetBestMapForUnit("player")
    if not mapID then UlDC.Print("no map to inspect.") return end
    local info = C_Map.GetMapInfo(mapID)
    local continentID = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0.5, 0.5))
    local steps = UlDC.CurrentSteps()
    local onContinent, placeable = 0, 0
    for _, step in ipairs(steps) do
        local here = false
        for _, giver in ipairs(step.quest.g or {}) do
            for _, pos in ipairs(giver.pos or {}) do
                if pos[1] == continentID then here = true end
            end
        end
        if here then onContinent = onContinent + 1 end
        if here and not step.inLog then placeable = placeable + 1 end
    end
    local ok, entries = pcall(Place, mapID)
    UlDC.Print(string.format("quest pins on map %d (%s, type %s, continent %s): %s", mapID, info and info.name or "?",
        info and tostring(info.mapType) or "?", tostring(continentID),
        ok and tostring(#entries) or ("error " .. tostring(entries))))
    print(string.format("  steps: %d in all, %d with a giver on this continent, %d of those not in the log",
        #steps, onContinent, placeable))
    -- Where each continent step's giver is, by zone, so an empty map can
    -- be told apart from a placement fault.
    local continentMap = UlDC.CONTINENT_MAP and UlDC.CONTINENT_MAP[continentID]
    for _, step in ipairs(steps) do
        local giver = step.quest.g and step.quest.g[1]
        local pos = giver and giver.pos and giver.pos[1]
        if pos and pos[1] == continentID then
            local zone = "?"
            if continentMap then
                local _, cpos = C_Map.GetMapPosFromWorldPos(continentID, CreateVector2D(pos[2], pos[3]), continentMap)
                local cx, cy
                if cpos then cx, cy = cpos:GetXY() end
                local info = cx and cy and C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(continentMap, cx, cy)
                zone = info and info.name or "?"
            end
            print(string.format("  %s (%d) by %s in %s%s", step.quest.t, step.quest.l, giver.n, zone,
                step.inLog and " (in log)" or ""))
        end
    end
    if ok then
        for i, e in ipairs(entries) do
            if i > 20 then print("  ...") break end
            local titles = {}
            for _, s in ipairs(e.steps) do titles[#titles + 1] = s.quest.t end
            print(string.format("  %s at %.3f, %.3f: %s", tostring(e.giver), e.x, e.y, table.concat(titles, "; ")))
        end
    end
    print("  provider installed: " .. tostring(provider ~= nil) .. ", last error: " .. tostring(lastError))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function() InstallProvider() end)
