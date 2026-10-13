-- Quest Browser: /udc quests opens a window listing every current step
-- (see Quests.lua), grouped by the dungeon it leads to, with elite and
-- raid quests in their own groups at the end.
--
-- Each row is the step quest, its level in the game's difficulty color,
-- and the giver. Hovering a row shows the same tooltip as the map pin.
-- Clicking a row opens the world map on the giver's zone and sets a
-- waypoint there when the client allows it.

local WIDTH, HEIGHT = 560, 520
local ROW_H = 18
local LEFT = 14

local window
local rows = {}

-- Continent instance ID -> the continent's uiMapID, used to find the zone
-- under a world position. Retail IDs, verified on Forever (Stormwind's
-- parent is 1415).
local CONTINENT_MAP = { [0] = 1415, [1] = 1414 }

-- The zone map and normalized position for a giver's world position.
local function ZoneFor(continent, x, y)
    local continentMap = CONTINENT_MAP[continent]
    if not continentMap then return nil end
    local _, pos = C_Map.GetMapPosFromWorldPos(continent, CreateVector2D(x, y), continentMap)
    if not pos then return nil end
    local cx, cy = pos:GetXY()
    local zone = C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(continentMap, cx, cy)
    local mapID = zone and zone.mapID or continentMap
    local _, zpos = C_Map.GetMapPosFromWorldPos(continent, CreateVector2D(x, y), mapID)
    local zx, zy = zpos and zpos:GetXY()
    return mapID, zx, zy
end

local function ShowOnMap(step)
    local giver = step.quest.g and step.quest.g[1]
    local p = giver and giver.pos and giver.pos[1]
    if not p then return end
    local ok, mapID, x, y = pcall(ZoneFor, p[1], p[2], p[3])
    if not ok or not mapID then return end
    if OpenWorldMap then
        OpenWorldMap(mapID)
    elseif WorldMapFrame then
        WorldMapFrame:SetMapID(mapID)
        if not WorldMapFrame:IsShown() then ShowUIPanel(WorldMapFrame) end
    end
    if x and y and C_Map.SetUserWaypoint and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mapID) then
        pcall(C_Map.SetUserWaypoint, { uiMapID = mapID, position = CreateVector2D(x, y) })
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    end
end

-- Groups in display order: dungeons by level, then Elite, then Raids.
local function Grouped()
    local steps = UlDC.CurrentSteps()
    local groups, byKey = {}, {}
    local function group(key, name, order)
        local g = byKey[key]
        if not g then
            g = { key = key, name = name, order = order, steps = {} }
            byKey[key] = g
            groups[#groups + 1] = g
        end
        return g
    end
    local dungeonOrder = {}
    for i, d in ipairs(UlDC.DUNGEONS) do
        if d.key and not dungeonOrder[d.key] then dungeonOrder[d.key] = d.levels[1] * 100 + i end
    end
    for _, step in ipairs(steps) do
        local placed = false
        for key in pairs(step.keys) do
            placed = true
            local name = UlDC.DungeonName(key)
            local d
            for _, entry in ipairs(UlDC.DUNGEONS) do
                if entry.key == key then d = entry break end
            end
            local g = group(key, name .. (d and (" (" .. d.levels[1] .. "-" .. d.levels[2] .. ")") or ""), dungeonOrder[key] or 9000)
            g.steps[#g.steps + 1] = step
        end
        if not placed then
            local g = bit.band(step.flags, UlDC.FLAG_RAID) ~= 0 and group("_raid", "Raids", 20000)
                or group("_elite", "Elite quests", 10000)
            g.steps[#g.steps + 1] = step
        end
    end
    table.sort(groups, function(a, b) return a.order < b.order end)
    return groups
end

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("LEFT", parent, "LEFT", LEFT, 0)
    row:SetPoint("RIGHT", parent, "RIGHT", -LEFT, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -120, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.right:SetJustifyH("RIGHT")
    row.right:SetWidth(118)
    row.right:SetWordWrap(false)
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.08)
    row:SetScript("OnEnter", function(self)
        if not self.step then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local giver = self.step.quest.g and self.step.quest.g[1]
        GameTooltip:AddLine(giver and giver.n or (self.step.quest.gi and ("Inside " .. UlDC.DungeonName(self.step.quest.gi))) or "Unknown giver", 1, 0.82, 0)
        UlDC.AddStepLines(self.step, UnitLevel("player"))
        if giver and giver.pos then
            GameTooltip:AddLine("Click to show on the map", 0.4, 0.8, 1)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if self.step then ShowOnMap(self.step) end
    end)
    return row
end

local function Fill()
    if not window then return end
    local content = window.content
    local groups = Grouped()
    local y = -4
    local used = 0
    local function row()
        used = used + 1
        local r = rows[used]
        if not r then
            r = CreateRow(content, used)
            rows[used] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT, y)
        r:SetPoint("RIGHT", content, "RIGHT", -LEFT, 0)
        r:Show()
        y = y - ROW_H
        return r
    end
    for _, g in ipairs(groups) do
        local header = row()
        header.step = nil
        header.text:SetText("|cffffd100" .. g.name .. "|r")
        header.right:SetText("")
        for _, step in ipairs(g.steps) do
            local r = row()
            r.step = step
            local q = step.quest
            local cr, cg, cb = UlDC.LevelColor(q.l)
            local level = string.format("|cff%02x%02x%02x[%d]|r", math.floor(cr * 255), math.floor(cg * 255), math.floor(cb * 255), q.l)
            local goalNote = ""
            if step.hops > 0 then
                goalNote = string.format(" |cff999999(+%d step%s)|r", step.hops, step.hops == 1 and "" or "s")
            end
            local state = step.inLog and "|cff66ccffin log|r" or (step.tooLow and ("|cffff6666needs " .. (q.m or 0) .. "|r") or "")
            r.text:SetText(level .. " " .. q.t .. goalNote)
            local giver = q.g and q.g[1]
            r.right:SetText(state ~= "" and state or (giver and giver.n or (q.gi and "inside") or ""))
        end
        y = y - 6
    end
    for i = used + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(-y + 8, 1))
    window.count:SetText(#UlDC.CurrentSteps() .. " steps for level " .. UnitLevel("player"))
end

local function CreateWindow()
    local f = CreateFrame("Frame", "UlDCQuestBrowser", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    tinsert(UISpecialFrames, "UlDCQuestBrowser")
    if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end
    local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
    if title then title:SetText("Dungeon and elite quests") end

    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.count:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT, -30)

    local scroll = CreateFrame("ScrollFrame", "UlDCQuestBrowserScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -48)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 30)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - 40, 1)
    scroll:SetScrollChild(content)
    f.content = content

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
    hint:SetText("Hover a row for the chain, click it to show the giver on the map.")

    f:SetScript("OnShow", Fill)
    f:Hide()
    return f
end

function UlDC.RefreshQuestBrowser()
    if window and window:IsShown() then Fill() end
end

function UlDC.ToggleQuestBrowser()
    if not window then window = CreateWindow() end
    if window:IsShown() then window:Hide() else window:Show() end
end
