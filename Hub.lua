-- Hub: /udc opens one window that answers "what group content can I do
-- right now?" the moment it opens.
--
-- Every dungeon and raid the character's faction can enter is listed
-- once (several entrances collapse into one row), sorted by level and
-- grouped by how it relates to the character's level (UlDC.LevelFit, the
-- same colors as the map pins): "For you now" (fits or easy), "Soon"
-- (within five levels), then "Later" and "Outgrown" folded into one line
-- of names each, click the heading to unfold. Elite quests in the open
-- world get a row of their own under "For you now".
--
-- A dungeon row shows the level range, the zone and how many quest steps
-- lead there (UlDC.CurrentSteps, see Quests.lua). Clicking the row folds
-- the steps out underneath, the same rows the old quest browser had:
-- level in the game's difficulty color, title, giver or state. Hovering
-- a step shows the chain, clicking it opens the world map on the giver
-- with a waypoint. The Map button on a dungeon row does the same for the
-- entrance. Settings (the feature switches) live behind the button in
-- the top right, see Options.lua.

local WIDTH, HEIGHT = 660, 580
local ROW_H, STEP_H, HEADER_H = 20, 18, 24
local LEFT = 10
local INDENT = 22
local STATE_W = 150       -- right column of a step row (giver or state)
local QUESTS_W = 140      -- quest count column of a dungeon row
local MAP_W = 48

local window
local rows = {}
local expanded = {}       -- dungeon key -> true/false once the player has clicked
local unfolded = {}       -- section key -> true when a folded section is open

-- Continent instance ID -> the continent's uiMapID, used to find the zone
-- under a world position. Retail IDs, verified on Forever (Stormwind's
-- parent is 1415). QuestPins reads this too.
local CONTINENT_MAP = { [0] = 1415, [1] = 1414 }
UlDC.CONTINENT_MAP = CONTINENT_MAP

local SECTIONS = {
    { key = "now",      title = "For you now", fits = { fits = true, easy = true } },
    { key = "soon",     title = "Soon",        fits = { soon = true } },
    { key = "later",    title = "Later",       fits = { ["too high"] = true }, folded = true },
    { key = "outgrown", title = "Outgrown",    fits = { outgrown = true }, folded = true },
}

------------------------------------------------------------------------
-- Map
------------------------------------------------------------------------

-- The zone map and normalized position for a world position.
local function ZoneFor(continent, x, y)
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

local function OpenMapAt(mapID, x, y)
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

local function ShowGiver(step)
    local giver = step.quest.g and step.quest.g[1]
    local p = giver and giver.pos and giver.pos[1]
    if not p then return end
    local ok, mapID, x, y = pcall(ZoneFor, p[1], p[2], p[3])
    if ok and mapID then OpenMapAt(mapID, x, y) end
end

-- Forever entrances carry a map and percentages; vanilla ones a continent
-- and world position (DungeonPins resolves the former into the latter at
-- first draw, but the hub may open before the map ever did).
local function ShowEntrance(node)
    if node.map and node.mx then
        OpenMapAt(node.map, node.mx / 100, node.my / 100)
        return
    end
    if not node.x then return end
    local ok, mapID, x, y = pcall(ZoneFor, node.continent, node.x, node.y)
    if ok and mapID then OpenMapAt(mapID, x, y) end
end

------------------------------------------------------------------------
-- Model
------------------------------------------------------------------------

local function Color(r, g, b)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function RangeText(levels)
    if levels[1] == levels[2] then return tostring(levels[1]) end
    return levels[1] .. "-" .. levels[2]
end

-- One entry per instance the character's faction can enter, with every
-- entrance node and every current step that leads there. Steps that lead
-- nowhere in the dungeon list land in the pseudo entries (elite quests in
-- the open world, raid quests, anything else).
local function Model()
    local playerFaction = UnitFactionGroup("player")
    local list, byKey = {}, {}
    for i, node in ipairs(UlDC.DUNGEONS or {}) do
        if node.faction == nil or node.faction == playerFaction then
            local d = byKey[node.key]
            if not d then
                d = { key = node.key, name = node.name, kind = node.kind, levels = node.levels, zone = node.zone,
                      nodes = {}, steps = {}, inLog = 0, order = i }
                byKey[node.key] = d
                list[#list + 1] = d
            end
            d.nodes[#d.nodes + 1] = node
        end
    end
    local pseudo = {
        { key = "_elite", name = "Elite quests", desc = "Group quests in the open world.", steps = {}, inLog = 0, pseudo = true },
        { key = "_raid",  name = "Raid quests",  desc = "Quests that lead into a raid.", steps = {}, inLog = 0, pseudo = true },
        { key = "_other", name = "Other dungeon quests", desc = "Quests for an instance the dungeon list does not know.", steps = {}, inLog = 0, pseudo = true },
    }
    local function add(d, step)
        d.steps[#d.steps + 1] = step
        if step.inLog then d.inLog = d.inLog + 1 end
    end
    local steps = UlDC.CurrentSteps and UlDC.CurrentSteps() or {}
    for _, step in ipairs(steps) do
        local placed = false
        for key in pairs(step.keys) do
            if byKey[key] then
                add(byKey[key], step)
                placed = true
            end
        end
        if not placed then
            if bit.band(step.flags, UlDC.FLAG_RAID) ~= 0 then
                add(pseudo[2], step)
            elseif bit.band(step.flags, UlDC.FLAG_DUNGEON) ~= 0 then
                add(pseudo[3], step)
            else
                add(pseudo[1], step)
            end
        end
    end
    table.sort(list, function(a, b)
        if a.levels[1] ~= b.levels[1] then return a.levels[1] < b.levels[1] end
        if a.levels[2] ~= b.levels[2] then return a.levels[2] < b.levels[2] end
        return a.order < b.order
    end)
    return list, pseudo, #steps
end

local function IsExpanded(d, section)
    if expanded[d.key] ~= nil then return expanded[d.key] end
    -- Folded out by default only where it matters most: the rows at the
    -- top that actually have quests.
    return section.key == "now" and #d.steps > 0
end

------------------------------------------------------------------------
-- Tooltips
------------------------------------------------------------------------

local function DungeonTooltip(self)
    local d = self.dungeon
    if not d then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(d.name, 1, 0.82, 0)
    if d.pseudo then
        GameTooltip:AddLine(d.desc, 0.8, 0.8, 0.8)
    else
        local fit, r, g, b = UlDC.LevelFit(d.levels)
        GameTooltip:AddDoubleLine((d.kind == "raid" and "Raid" or "Dungeon") .. ", level " .. RangeText(d.levels), fit, 0.8, 0.8, 0.8, r, g, b)
        local first = d.nodes[1]
        for _, wing in ipairs(first.wings or {}) do
            local _, wr, wg, wb = UlDC.LevelFit(wing.levels)
            GameTooltip:AddDoubleLine("  " .. wing.name, RangeText(wing.levels), 0.8, 0.8, 0.8, wr, wg, wb)
        end
        if first.entry then
            GameTooltip:AddLine("Entry level " .. first.entry, 0.8, 0.8, 0.8)
        end
        for _, node in ipairs(d.nodes) do
            GameTooltip:AddLine((node.label or "Entrance") .. ", " .. (node.zone or "?"), 0.8, 0.8, 0.8)
        end
        if first.note then
            GameTooltip:AddLine(first.note, 0.6, 0.6, 0.6, true)
        end
    end
    if #d.steps > 0 then
        GameTooltip:AddLine("Click to " .. (self.open and "hide" or "list") .. " the quests", 0.4, 0.8, 1)
    end
    if not d.pseudo then
        GameTooltip:AddLine("Map opens the world map on the entrance", 0.4, 0.8, 1)
    end
    GameTooltip:Show()
end

local function StepTooltip(self)
    local step = self.step
    if not step then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local giver = step.quest.g and step.quest.g[1]
    GameTooltip:AddLine(giver and giver.n or (step.quest.gi and ("Inside " .. UlDC.DungeonName(step.quest.gi))) or "Unknown giver", 1, 0.82, 0)
    UlDC.AddStepLines(step, UnitLevel("player"))
    if giver and giver.pos and giver.pos[1] then
        GameTooltip:AddLine("Click to show on the map", 0.4, 0.8, 1)
    end
    GameTooltip:Show()
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------

-- One pool of rows for everything; Fill decides the role of each.
local function CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetJustifyV("TOP")

    row.range = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.range:SetJustifyH("LEFT")
    row.range:SetWordWrap(false)

    row.zone = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.zone:SetJustifyH("LEFT")
    row.zone:SetWordWrap(false)
    row.zone:SetTextColor(0.7, 0.7, 0.7)

    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetJustifyH("RIGHT")
    row.right:SetWordWrap(false)

    row.map = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.map:SetSize(MAP_W, 18)
    row.map:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.map:SetText("Map")
    row.map:SetScript("OnClick", function(self)
        local d = self:GetParent().dungeon
        if d and d.nodes[1] then ShowEntrance(d.nodes[1]) end
    end)

    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetColorTexture(1, 0.82, 0, 0.25)
    row.line:SetHeight(1)
    row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
    row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 2)

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.08)

    row:SetScript("OnEnter", function(self)
        if self.step then StepTooltip(self) elseif self.dungeon then DungeonTooltip(self) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if self.step then
            ShowGiver(self.step)
        elseif self.dungeon and #self.dungeon.steps > 0 then
            expanded[self.dungeon.key] = not self.open
            UlDC.RefreshHub()
        elseif self.section then
            unfolded[self.section] = not unfolded[self.section]
            UlDC.RefreshHub()
        end
    end)
    return row
end

-- Everything hidden and detached; the role fills in what it needs.
local function Reset(row)
    row.step, row.dungeon, row.section, row.open = nil, nil, nil, nil
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.label:SetWordWrap(false)
    row.label:SetFontObject("GameFontHighlight")
    row.label:SetTextColor(1, 1, 1)
    row.label:SetText("")
    row.range:ClearAllPoints()
    row.range:SetText("")
    row.zone:ClearAllPoints()
    row.zone:SetText("")
    row.right:ClearAllPoints()
    row.right:SetText("")
    row.map:Hide()
    row.line:Hide()
    row.highlight:Show()
    row:EnableMouse(true)
end

------------------------------------------------------------------------
-- Fill
------------------------------------------------------------------------

local function Fill()
    if not window then return end
    local content = window.content
    local dungeons, pseudo, stepCount = Model()
    local y = -4
    local used = 0

    local function row(height, indent)
        used = used + 1
        local r = rows[used]
        if not r then
            r = CreateRow(content)
            rows[used] = r
        end
        Reset(r)
        r:SetHeight(height)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT + (indent or 0), y)
        r:SetPoint("RIGHT", content, "RIGHT", -LEFT, 0)
        r:Show()
        y = y - height
        return r
    end

    local function header(section, count)
        local r = row(HEADER_H)
        r.label:SetFontObject("GameFontNormal")
        local text = section.title
        if section.folded then
            text = (unfolded[section.key] and "- " or "+ ") .. text
            r.section = section.key
        else
            r.highlight:Hide()
            r:EnableMouse(false)
        end
        r.label:SetText(text .. " |cff999999(" .. count .. ")|r")
        r.line:Show()
    end

    local function dungeonRow(d, section)
        local r = row(ROW_H)
        r.dungeon = d
        r.open = IsExpanded(d, section)
        local marker = ""
        if #d.steps > 0 then marker = (r.open and "- " or "+ ") else marker = "  " end
        r.label:SetText(marker .. d.name)
        if d.pseudo then
            r.label:SetPoint("RIGHT", r, "RIGHT", -(QUESTS_W + MAP_W + 8), 0)
        else
            r.label:SetPoint("RIGHT", r, "LEFT", 240, 0)
            local _, cr, cg, cb = UlDC.LevelFit(d.levels)
            r.range:SetPoint("LEFT", r, "LEFT", 244, 0)
            r.range:SetWidth(50)
            r.range:SetText(Color(cr, cg, cb) .. RangeText(d.levels) .. "|r")
            r.zone:SetPoint("LEFT", r, "LEFT", 298, 0)
            r.zone:SetPoint("RIGHT", r, "RIGHT", -(QUESTS_W + MAP_W + 8), 0)
            r.zone:SetText((d.zone or "") .. (d.kind == "raid" and " |cff999999(raid)|r" or ""))
            r.map:Show()
        end
        r.right:SetPoint("RIGHT", r, "RIGHT", -(MAP_W + 8), 0)
        r.right:SetWidth(QUESTS_W)
        local n = #d.steps
        local quests
        if n == 0 then
            quests = "|cff777777no quests|r"
        else
            quests = n .. (n == 1 and " quest" or " quests")
            if d.inLog > 0 then quests = quests .. ", |cff66ccff" .. d.inLog .. " in log|r" end
        end
        r.right:SetText(quests)
        return r.open
    end

    local function stepRow(step)
        local r = row(STEP_H, INDENT)
        r.step = step
        r.label:SetFontObject("GameFontHighlightSmall")
        r.label:SetPoint("RIGHT", r, "RIGHT", -STATE_W, 0)
        local q = step.quest
        local stepLevel = UlDC.QuestLevel(step.id)
        local cr, cg, cb = UlDC.LevelColor(stepLevel)
        local level = Color(cr, cg, cb) .. "[" .. stepLevel .. "]|r"
        local goalNote = ""
        if step.hops > 0 then
            goalNote = string.format(" |cff999999(+%d step%s)|r", step.hops, step.hops == 1 and "" or "s")
        end
        r.label:SetText(level .. " " .. UlDC.QuestTitle(step.id) .. goalNote)
        local state = step.inLog and "|cff66ccffin log|r" or (step.tooLow and ("|cffff6666needs " .. (q.m or 0) .. "|r") or "")
        local giver = q.g and q.g[1]
        r.right:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        r.right:SetWidth(STATE_W - 2)
        r.right:SetText(state ~= "" and state or (giver and giver.n or (q.gi and "inside") or ""))
    end

    local function namesRow(members)
        local names = {}
        for _, d in ipairs(members) do names[#names + 1] = d.name end
        local r = row(STEP_H)
        r.highlight:Hide()
        r:EnableMouse(false)
        r.label:SetFontObject("GameFontHighlightSmall")
        r.label:SetTextColor(0.6, 0.6, 0.6)
        r.label:SetWordWrap(true)
        r.label:ClearAllPoints()
        r.label:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -2)
        r.label:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        r.label:SetText(table.concat(names, ", "))
        -- The wrapped text decides the row's height.
        local h = r.label:GetStringHeight()
        if h and h > STEP_H then
            r:SetHeight(h + 2)
            y = y - (h + 2 - STEP_H)
        end
    end

    for _, section in ipairs(SECTIONS) do
        local members = {}
        for _, d in ipairs(dungeons) do
            local fit = UlDC.LevelFit(d.levels)
            if section.fits[fit] then members[#members + 1] = d end
        end
        if section.key == "now" then
            for _, p in ipairs(pseudo) do
                if #p.steps > 0 then members[#members + 1] = p end
            end
        end
        if #members > 0 then
            header(section, #members)
            if section.folded and not unfolded[section.key] then
                namesRow(members)
            else
                for _, d in ipairs(members) do
                    if dungeonRow(d, section) then
                        for _, step in ipairs(d.steps) do stepRow(step) end
                        y = y - 2
                    end
                end
            end
            y = y - 8
        end
    end

    for i = used + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(-y + 8, 1))

    local name = UnitName("player") or "You"
    window.who:SetText(string.format("%s, level %d", name, UnitLevel("player")))
    window.count:SetText(string.format("%d quest step%s", stepCount, stepCount == 1 and "" or "s"))
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

local function CreateWindow()
    local f = CreateFrame("Frame", "UlDCHub", UIParent, "BasicFrameTemplateWithInset")
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
    tinsert(UISpecialFrames, "UlDCHub")
    -- The template's close button goes through the panel manager, which
    -- ignores windows it does not manage; close directly instead.
    if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end
    local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
    if title then title:SetText(UlDC.name .. " " .. UlDC.Version()) end

    f.who = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.who:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT + 4, -32)

    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.count:SetPoint("LEFT", f.who, "RIGHT", 10, 0)

    local settings = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    settings:SetSize(80, 20)
    settings:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -28)
    settings:SetText("Settings")
    settings:SetScript("OnClick", function() if UlDC.ToggleOptions then UlDC.ToggleOptions() end end)

    local scroll = CreateFrame("ScrollFrame", "UlDCHubScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -54)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 30)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - 40, 1)
    scroll:SetScrollChild(content)
    f.content = content

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
    hint:SetText("Click a dungeon for its quests, a quest for the giver on the map. Hover a row for details.")

    f:SetScript("OnShow", Fill)
    f:Hide()
    return f
end

function UlDC.RefreshHub()
    if window and window:IsShown() then Fill() end
end

function UlDC.ToggleHub()
    if not window then window = CreateWindow() end
    if window:IsShown() then window:Hide() else window:Show() end
end
