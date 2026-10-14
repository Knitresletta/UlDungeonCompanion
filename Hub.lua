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
-- a step shows the chain, clicking it marks the giver on the map (own
-- markers, see Marks.lua, as many as wanted) and opens the map there; a
-- step whose giver stands inside the instance, or that starts from an
-- item found there, marks the entrance instead. The Map button on a
-- dungeon row marks the entrance. On the map a marker stays until it is
-- right-clicked. The Loot button folds out the drops inside: Forever's own
-- lists from ForeverChanges where they exist (UlDC.LOOT_FOREVER, see
-- tools/fetch_loot.py, dungeons only), else the vanilla loot tables
-- (UlDC.LOOT, tools/build_loot.py, the raids): one line per creature, its items
-- in quality colors with slot and drop chance, dimmed when the character
-- cannot use them. Hovering an item shows the game's item tooltip,
-- clicking it puts the link in an open chat box. Settings (the feature
-- switches) live behind the button in the top right, see Options.lua.

local WIDTH, HEIGHT = 660, 580
local ROW_H, STEP_H, HEADER_H = 20, 18, 24
local LEFT = 10
local INDENT = 22
local STATE_W = 150       -- right column of a step or item row
local QUESTS_W = 140      -- quest count column of a dungeon row
local MAP_W, LOOT_W = 48, 48
local BUTTONS_W = MAP_W + LOOT_W + 12

local window
local rows = {}
local expanded = {}       -- dungeon key -> true/false once the player has clicked
local unfolded = {}       -- section key -> true when a folded section is open
local lootOpen = {}       -- dungeon key -> true while its loot is folded out
local MARK = "|A:Waypoint-MapPin-Untracked:14:14|a"   -- glyph for a marked row

local SECTIONS = {
    { key = "now",      title = "For you now", fits = { fits = true, easy = true } },
    { key = "soon",     title = "Soon",        fits = { soon = true } },
    { key = "later",    title = "Later",       fits = { ["too high"] = true }, folded = true },
    { key = "outgrown", title = "Outgrown",    fits = { outgrown = true }, folded = true },
}

------------------------------------------------------------------------
-- Map
------------------------------------------------------------------------

-- Marks the step's location (giver or entrance) and opens the map there;
-- a second click takes the mark away again.
local function ToggleStep(step)
    local kind, _, mark = UlDC.StepLocation(step)
    if not kind then return end
    if UlDC.ToggleMark("q" .. step.id, mark) then UlDC.ShowMark(mark) end
end

local function ToggleEntrance(d)
    local node = d.nodes[1]
    local mark = node and UlDC.EntranceMark(node)
    if not mark then return end
    if UlDC.ToggleMark("e" .. d.key, mark) then UlDC.ShowMark(mark) end
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
-- Items
------------------------------------------------------------------------

-- LootData item fields: { id, name, quality, chance, class, subclass, inventoryType, allowableClass }.
local QUALITY_COLOR = { [0] = "|cff9d9d9d", "|cffffffff", "|cff1eff00", "|cff0070dd", "|cffa335ee", "|cffff8000" }

local CLASS_BIT = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }

local SLOT = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist", [7] = "Legs",
    [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Finger", [12] = "Trinket", [13] = "One-hand",
    [14] = "Shield", [15] = "Ranged", [16] = "Back", [17] = "Two-hand", [18] = "Bag", [19] = "Tabard",
    [20] = "Chest", [21] = "Main hand", [22] = "Off hand", [23] = "Held", [24] = "Ammo", [25] = "Thrown",
    [26] = "Ranged", [28] = "Relic",
}
local ARMOR = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate", [6] = "Shield", [7] = "Libram", [8] = "Idol", [9] = "Totem" }
local WEAPON = {
    [0] = "Axe", [1] = "Two-hand axe", [2] = "Bow", [3] = "Gun", [4] = "Mace", [5] = "Two-hand mace",
    [6] = "Polearm", [7] = "Sword", [8] = "Two-hand sword", [10] = "Staff", [13] = "Fist weapon",
    [15] = "Dagger", [16] = "Thrown", [17] = "Spear", [18] = "Crossbow", [19] = "Wand", [20] = "Fishing pole",
}
-- Armor types a class can wear (subclass -> level it opens at), shields
-- included as subclass 6.
local WEARS = {
    WARRIOR = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 }, PALADIN = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
    HUNTER = { [1] = 1, [2] = 1, [3] = 40 }, SHAMAN = { [1] = 1, [2] = 1, [3] = 40, [6] = 1 },
    ROGUE = { [1] = 1, [2] = 1 }, DRUID = { [1] = 1, [2] = 1 },
    PRIEST = { [1] = 1 }, MAGE = { [1] = 1 }, WARLOCK = { [1] = 1 },
}

-- Forever data carries the slot as text in field 9; vanilla data the
-- inventory type number in field 7.
local function SlotText(item)
    local class, sub, inv = item[5], item[6], item[7]
    local slot = (item[9] and item[9] ~= "") and item[9] or SLOT[inv]
    if class == 4 then
        local kind = ARMOR[sub]
        if kind and slot and sub >= 1 and sub <= 4 then return kind .. " " .. slot:lower() end
        return kind or slot or ""
    elseif class == 2 then
        return WEAPON[sub] or slot or "Weapon"
    elseif class == 9 then
        return "Recipe"
    end
    return slot or ""
end

-- Whether the character can use the item, as far as class and armor type
-- tell. Weapon skills are not checked.
local function Usable(item)
    local _, class = UnitClass("player")
    local mask = item[8]
    if mask and mask > 0 and mask ~= 32767 and CLASS_BIT[class] and bit.band(mask, CLASS_BIT[class]) == 0 then
        return false
    end
    if item[5] == 4 and (item[6] >= 1 and item[6] <= 4 or item[6] == 6) then
        local wears = WEARS[class]
        local from = wears and wears[item[6]]
        if not from or UnitLevel("player") < from then return false end
    end
    return true
end

local function ItemTooltip(self)
    local item = self.item
    if not item then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local shown = false
    if GameTooltip.SetItemByID then
        shown = pcall(GameTooltip.SetItemByID, GameTooltip, item[1])
    end
    if not shown then
        GameTooltip:AddLine((QUALITY_COLOR[item[3]] or "") .. item[2] .. "|r")
        GameTooltip:AddLine(SlotText(item), 0.8, 0.8, 0.8)
    end
    if item[4] and item[4] > 0 then
        GameTooltip:AddLine(string.format("Drops from %s, about %g%%", self.source or "?", item[4]), 0.6, 0.8, 1)
    else
        GameTooltip:AddLine("Drops from " .. (self.source or "?"), 0.6, 0.8, 1)
    end
    if item[10] == "new" then GameTooltip:AddLine("New in Forever", 0.4, 1, 0.4) end
    if not Usable(item) then GameTooltip:AddLine("Not for your class", 1, 0.4, 0.4) end
    GameTooltip:Show()
end

local function LinkItem(item)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo then return end
    local _, link = getInfo(item[1])
    if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
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
        GameTooltip:AddLine(UlDC.IsMarked("e" .. d.key) and "Map removes the marker on the entrance"
            or "Map marks the entrance and opens the world map", 0.4, 0.8, 1)
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
    local kind, where = UlDC.StepLocation(step)
    if kind == "entrance" then
        GameTooltip:AddLine("Starts inside " .. where, 0.8, 0.8, 0.8)
    end
    if kind then
        GameTooltip:AddLine(UlDC.IsMarked("q" .. step.id) and "Click to remove the marker"
            or ("Click to mark " .. (kind == "entrance" and "the entrance" or "the giver") .. " on the map"), 0.4, 0.8, 1)
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
        if d then ToggleEntrance(d) end
    end)

    row.loot = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.loot:SetSize(LOOT_W, 18)
    row.loot:SetPoint("RIGHT", row.map, "LEFT", -4, 0)
    row.loot:SetText("Loot")
    row.loot:SetScript("OnClick", function(self)
        local d = self:GetParent().dungeon
        if not d then return end
        lootOpen[d.key] = not lootOpen[d.key]
        UlDC.RefreshHub()
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
        if self.item then ItemTooltip(self)
        elseif self.step then StepTooltip(self)
        elseif self.dungeon then DungeonTooltip(self) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if self.item then
            LinkItem(self.item)
        elseif self.step then
            ToggleStep(self.step)
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
    row.item, row.source = nil, nil
    row.loot:Hide()
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
            r.label:SetPoint("RIGHT", r, "RIGHT", -(QUESTS_W + BUTTONS_W), 0)
        else
            r.label:SetPoint("RIGHT", r, "LEFT", 240, 0)
            local _, cr, cg, cb = UlDC.LevelFit(d.levels)
            r.range:SetPoint("LEFT", r, "LEFT", 244, 0)
            r.range:SetWidth(50)
            r.range:SetText(Color(cr, cg, cb) .. RangeText(d.levels) .. "|r")
            r.zone:SetPoint("LEFT", r, "LEFT", 298, 0)
            r.zone:SetPoint("RIGHT", r, "RIGHT", -(QUESTS_W + BUTTONS_W), 0)
            r.zone:SetText((d.zone or "") .. (d.kind == "raid" and " |cff999999(raid)|r" or ""))
            r.map:Show()
            r.map:SetText(UlDC.IsMarked("e" .. d.key) and "|cffffd100Map|r" or "Map")
            r.loot:Show()
            r.loot:SetText(lootOpen[d.key] and "|cffffd100Loot|r" or "Loot")
        end
        r.right:SetPoint("RIGHT", r, "RIGHT", -BUTTONS_W, 0)
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
        local marked = UlDC.IsMarked("q" .. step.id) and (MARK .. " ") or ""
        r.label:SetText(marked .. level .. " " .. UlDC.QuestTitle(step.id) .. goalNote)
        local state = step.inLog and "|cff66ccffin log|r" or (step.tooLow and ("|cffff6666needs " .. (q.m or 0) .. "|r") or "")
        local giver = q.g and q.g[1]
        r.right:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        r.right:SetWidth(STATE_W - 2)
        r.right:SetText(state ~= "" and state or (giver and giver.n or (q.gi and "inside") or ""))
    end

    -- The notable drops inside one instance: a line per creature, its
    -- items underneath.
    local function lootRows(d)
        local sources = UlDC.LOOT_FOREVER and UlDC.LOOT_FOREVER[d.key]
        if not sources or #sources == 0 then sources = UlDC.LOOT and UlDC.LOOT[d.key] end
        if not sources or #sources == 0 then
            local r = row(STEP_H, INDENT)
            r.highlight:Hide()
            r:EnableMouse(false)
            r.label:SetFontObject("GameFontHighlightSmall")
            r.label:SetTextColor(0.6, 0.6, 0.6)
            r.label:SetText("No loot data for this instance yet.")
            return
        end
        for _, source in ipairs(sources) do
            local h = row(STEP_H, INDENT)
            h.highlight:Hide()
            h:EnableMouse(false)
            h.label:SetFontObject("GameFontHighlightSmall")
            local parts = {}
            if source.w then parts[#parts + 1] = source.w end
            if source.kind == "rare" then parts[#parts + 1] = "rare spawn" end
            if source.l and source.l > 0 then parts[#parts + 1] = "level " .. source.l else parts[#parts + 1] = "chest" end
            h.label:SetText("|cffffd100" .. source.n .. "|r |cff999999(" .. table.concat(parts, ", ") .. ")|r")
            if #source.items == 0 then
                local r = row(STEP_H, INDENT * 2)
                r.highlight:Hide()
                r:EnableMouse(false)
                r.label:SetFontObject("GameFontHighlightSmall")
                r.label:SetTextColor(0.5, 0.5, 0.5)
                r.label:SetText("No notable drops, world drops only.")
            end
            for _, item in ipairs(source.items) do
                local r = row(STEP_H, INDENT * 2)
                r.item, r.source = item, source.n
                r.label:SetFontObject("GameFontHighlightSmall")
                r.label:SetPoint("RIGHT", r, "RIGHT", -STATE_W, 0)
                local usable = Usable(item)
                local name = (QUALITY_COLOR[item[3]] or "") .. item[2] .. "|r"
                if not usable then name = "|cff777777" .. item[2] .. "|r" end
                if item[10] == "new" then name = name .. " |cff66ff66new|r" end
                r.label:SetText(name)
                r.right:SetPoint("RIGHT", r, "RIGHT", 0, 0)
                r.right:SetWidth(STATE_W - 2)
                local chance = (item[4] and item[4] > 0) and string.format("  %g%%", item[4]) or ""
                r.right:SetText((usable and "|cffb0b0b0" or "|cff777777") .. SlotText(item) .. chance .. "|r")
            end
        end
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
                    local open = dungeonRow(d, section)
                    if open then
                        for _, step in ipairs(d.steps) do stepRow(step) end
                    end
                    if lootOpen[d.key] and not d.pseudo then
                        lootRows(d)
                    end
                    if open or lootOpen[d.key] then y = y - 2 end
                end
            end
            y = y - 8
        end
    end

    for i = used + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(-y + 8, 1))

    local name = UnitName("player") or "You"
    window.who:SetText(string.format("%s, level %d", name, UnitLevel("player")))
    local marks = UlDC.MarkCount and UlDC.MarkCount() or 0
    window.clear:SetText(string.format("Clear %d mark%s", marks, marks == 1 and "" or "s"))
    window.clear:SetShown(marks > 0)
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

    f.clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.clear:SetSize(110, 20)
    f.clear:SetPoint("RIGHT", settings, "LEFT", -6, 0)
    f.clear:SetScript("OnClick", function() if UlDC.ClearMarks then UlDC.ClearMarks() end end)
    f.clear:Hide()

    local scroll = CreateFrame("ScrollFrame", "UlDCHubScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -54)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 30)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - 40, 1)
    scroll:SetScrollChild(content)
    f.content = content

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
    hint:SetText("Click a dungeon for its quests, a quest to mark its giver on the map. Hover a row for details.")

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
