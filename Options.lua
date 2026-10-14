-- Options: the Settings window, one checkbox per feature and a button
-- per labeled command. Opened from the Settings button in the hub
-- (Hub.lua) or with /udc settings; /udc itself opens the hub.
--
-- Built from BasicFrameTemplateWithInset and UICheckButtonTemplate so it
-- looks like the rest of the game's windows. Features and commands come
-- from Core (UlDC.FEATURES, UlDC.COMMANDS), so a new module only needs
-- a line there. Clicking a box goes through UlDC.SetFeature, the same
-- path as the chat command. Escape closes the window (UISpecialFrames).

local ROW_H = 30
local HEADER_H = 24
local LEFT = 16
local WIDTH = 520

local window
local rows = {}

local function CreateRow(parent, y, feature)
    local box = CreateFrame("CheckButton", "UlDCOption" .. feature.key, parent, "UICheckButtonTemplate")
    box:SetSize(26, 26)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT + 8, y)
    if box.Text then box.Text:SetText("") end
    box.key = feature.key
    box:SetScript("OnClick", function(self)
        UlDC.SetFeature(self.key, self:GetChecked() and true or false)
    end)

    local name = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, -2)
    name:SetText(feature.label)
    name:SetJustifyH("LEFT")

    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
    desc:SetPoint("RIGHT", parent, "RIGHT", -LEFT, 0)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(false)
    desc:SetTextColor(0.7, 0.7, 0.7)
    desc:SetText(feature.desc)

    -- Clicking the name toggles too, like a settings panel.
    local hit = CreateFrame("Button", nil, parent)
    hit:SetPoint("LEFT", box, "RIGHT", 0, 0)
    hit:SetPoint("RIGHT", parent, "RIGHT", -LEFT, 0)
    hit:SetHeight(ROW_H - 2)
    hit:SetScript("OnClick", function() box:Click() end)

    return box
end

local function CreateHeader(parent, y, text)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT, y)
    label:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    line:SetPoint("RIGHT", parent, "RIGHT", -LEFT, 0)
end

-- Features grouped in the order Core lists the groups; anything with an
-- unknown group lands under "Other" at the end.
local function GroupedFeatures()
    local groups, byName = {}, {}
    for _, name in ipairs(UlDC.FEATURE_GROUPS or {}) do
        local g = { name = name, features = {} }
        groups[#groups + 1] = g
        byName[name] = g
    end
    for _, feature in ipairs(UlDC.FEATURES or {}) do
        local g = byName[feature.group or "Other"]
        if not g then
            g = { name = feature.group or "Other", features = {} }
            groups[#groups + 1] = g
            byName[g.name] = g
        end
        g.features[#g.features + 1] = feature
    end
    local kept = {}
    for _, g in ipairs(groups) do
        if #g.features > 0 then kept[#kept + 1] = g end
    end
    return kept
end

local function LabeledCommands()
    local list = {}
    for _, c in ipairs(UlDC.COMMANDS or {}) do
        if c.label then list[#list + 1] = c end
    end
    return list
end

local function CreateWindow()
    local groups = GroupedFeatures()
    local commands = LabeledCommands()
    local height = 36 + 64
    for _, g in ipairs(groups) do
        height = height + HEADER_H + 6 + #g.features * ROW_H + 6
    end

    local f = CreateFrame("Frame", "UlDCOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(WIDTH, height)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    tinsert(UISpecialFrames, "UlDCOptionsFrame")
    -- The template's close button goes through the panel manager, which
    -- ignores windows it does not manage; close directly instead.
    if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end

    local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
    if title then title:SetText(UlDC.name .. " settings") end

    local y = -32
    for _, g in ipairs(groups) do
        CreateHeader(f, y, g.name)
        y = y - HEADER_H - 6
        for _, feature in ipairs(g.features) do
            rows[feature.key] = CreateRow(f, y, feature)
            y = y - ROW_H
        end
        y = y - 6
    end

    if #commands > 0 then
        local buttonW = math.floor((WIDTH - 2 * LEFT - (#commands - 1) * 8) / #commands)
        local previous
        for _, c in ipairs(commands) do
            local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            b:SetSize(buttonW, 22)
            if previous then
                b:SetPoint("LEFT", previous, "RIGHT", 8, 0)
            else
                b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", LEFT, 36)
            end
            b:SetText(c.label)
            b:SetScript("OnClick", c.fn)
            previous = b
        end
    end

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", f, "BOTTOM", 0, 11)
    hint:SetText("Chat works too: /udc <feature> toggles, /udc settings opens this, /udc help lists every command.")

    f:SetScript("OnShow", function() if UlDC.RefreshOptions then UlDC.RefreshOptions() end end)
    -- A new frame is visible from the start; hide it so the first toggle
    -- shows it instead of hiding it.
    f:Hide()
    return f
end

function UlDC.RefreshOptions()
    if not window or not window:IsShown() then return end
    for key, box in pairs(rows) do
        box:SetChecked(UlDC.enabled[key] and true or false)
    end
end

function UlDC.ToggleOptions()
    if not window then window = CreateWindow() end
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
end
