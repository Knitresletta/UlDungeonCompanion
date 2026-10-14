-- Core: the shared table, saved settings, the feature list and /udc.
--
-- Every module hangs its functions on UlDC and reads UlDC.enabled[key] to
-- know whether it is on. Core never calls a module directly except through
-- the optional hooks in NotifyModules, so a module can be left out of the
-- TOC without breaking anything else.

UlDC = { name = "UlDungeonCompanion", enabled = {} }

local DEFAULTS = {
    dungeonpins = true,
    questpins   = true,
}

local function InitDB()
    if not UlDungeonCompanionDB then UlDungeonCompanionDB = {} end
    local db = UlDungeonCompanionDB
    if not db.enabled then db.enabled = {} end
    for k, v in pairs(DEFAULTS) do
        if db.enabled[k] == nil then db.enabled[k] = v end
    end
    for k in pairs(db.enabled) do
        if DEFAULTS[k] == nil then db.enabled[k] = nil end
    end
    UlDC.enabled = db.enabled
    UlDC.db = db
end

function UlDC.Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = get and get(UlDC.name, "Version")
    return v and ("v" .. v) or "(unknown version)"
end

function UlDC.Print(text)
    print("|cff66ccff" .. UlDC.name .. "|r: " .. text)
end

-- Every toggleable feature. Options.lua (Settings) draws one checkbox per entry;
-- /udc <key> toggles it from chat. desc is the one-line explanation shown
-- next to the checkbox and in /udc help.
local FEATURES = {
    { key = "dungeonpins", group = "Map", label = "Dungeon Entrances", desc = "Every dungeon and raid entrance on the world map, with its level range." },
    { key = "questpins",   group = "Map", label = "Quest Givers",      desc = "Givers of the dungeon and elite quests you can go for, on zone maps." },
}
UlDC.FEATURE_GROUPS = { "Map" }
UlDC.FEATURES = FEATURES

-- Commands that are not on/off switches. Options.lua shows a button for
-- the ones with a label.
local COMMANDS = {
    { key = "quests", desc = "open the hub (same as /udc): dungeons and quests for your level",
      fn = function() if UlDC.ToggleHub then UlDC.ToggleHub() end end },
    { key = "settings", desc = "open the settings window: feature switches and tools",
      fn = function() if UlDC.ToggleOptions then UlDC.ToggleOptions() end end },
    { key = "qd", desc = "print the current quest steps and the character filters",
      fn = function() if UlDC.QuestDebug then UlDC.QuestDebug() end end },
    { key = "qpins", desc = "print quest pin diagnostics for the open map",
      fn = function() if UlDC.QuestPinDebug then UlDC.QuestPinDebug() end end },
    { key = "dungeons", label = "List dungeons", desc = "print the dungeons and raids sorted by level, colored for your level",
      fn = function() if UlDC.PrintDungeonList then UlDC.PrintDungeonList() end end },
    { key = "pins", desc = "print dungeon pin diagnostics for the open map",
      fn = function() if UlDC.DungeonPinDebug then UlDC.DungeonPinDebug() end end },
    { key = "probe", label = "Probe client", desc = "test which quest and map APIs this client has; the result is kept in the saved variables",
      fn = function() if UlDC.RunProbe then UlDC.RunProbe() end end },
}
UlDC.COMMANDS = COMMANDS

local function PrintHelp()
    UlDC.Print("/udc opens the hub. Chat commands:")
    for _, f in ipairs(FEATURES) do
        local state = UlDC.enabled[f.key] and "|cff00ff00on|r" or "|cffff4444off|r"
        print("  /udc " .. f.key .. ": " .. f.label .. " (" .. state .. "): " .. f.desc)
    end
    for _, c in ipairs(COMMANDS) do
        print("  /udc " .. c.key .. ": " .. c.desc)
    end
end

-- Modules that need a nudge when a feature changes state.
local function NotifyModules()
    if UlDC.RefreshDungeonPins then UlDC.RefreshDungeonPins() end
    if UlDC.RefreshQuestPins then UlDC.RefreshQuestPins() end
    if UlDC.RefreshHub then UlDC.RefreshHub() end
    if UlDC.RefreshOptions then UlDC.RefreshOptions() end
end

-- Shared by the chat command and the options window.
function UlDC.SetFeature(key, enabled)
    local feature
    for _, f in ipairs(FEATURES) do
        if f.key == key then feature = f end
    end
    if not feature then return end
    UlDC.enabled[key] = enabled and true or false
    local state = UlDC.enabled[key] and "|cff00ff00enabled|r" or "|cffff4444disabled|r"
    UlDC.Print(feature.label .. " " .. state .. ".")
    NotifyModules()
end

SLASH_ULDUNGEONCOMPANION1 = "/udc"
SLASH_ULDUNGEONCOMPANION2 = "/dungeoncompanion"
SlashCmdList["ULDUNGEONCOMPANION"] = function(msg)
    local cmd = strtrim(msg):lower()
    if cmd == "" then
        if UlDC.ToggleHub then UlDC.ToggleHub()
        elseif UlDC.ToggleOptions then UlDC.ToggleOptions()
        else PrintHelp() end
        return
    end
    if cmd == "help" then
        PrintHelp()
        return
    end
    for _, c in ipairs(COMMANDS) do
        if cmd == c.key then
            c.fn()
            return
        end
    end
    for _, f in ipairs(FEATURES) do
        if cmd == f.key then
            UlDC.SetFeature(f.key, not UlDC.enabled[f.key])
            return
        end
    end
    PrintHelp()
end

local frame = CreateFrame("Frame", "UlDCCoreFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == UlDC.name then
        InitDB()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        UlDC.Print(UlDC.Version() .. " loaded. Type |cffffcc00/udc|r for the hub.")
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
