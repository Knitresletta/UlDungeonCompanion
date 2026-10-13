-- Quests: which dungeon, elite and raid quests this character can go for
-- right now, and where each one starts.
--
-- The data is UlDC.QUESTS (generated, see tools/build_quests.py). This
-- module adds what only the client knows: what the character has done
-- (C_QuestLog.IsQuestFlaggedCompleted, verified on Forever), what is in
-- the log, and the character's level, side, race and class.
--
-- A goal is a quest flagged dungeon, elite or raid. For every goal that
-- is not done, the chain is walked back along p until the first quest
-- that is not done: that is the step to show, with its giver. Goals in
-- the same chain share the step, so one pin can lead to several goals.
--
-- UlDC.CurrentSteps() returns the list the pins and the browser draw.

local RACE_BIT = { Human = 1, Orc = 2, Dwarf = 4, NightElf = 8, Scourge = 16, Tauren = 32, Gnome = 64, Troll = 128 }
local CLASS_BIT = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
local SIDE_MASK = { Alliance = 77, Horde = 178 }

local FLAG_DUNGEON, FLAG_ELITE, FLAG_RAID = 1, 2, 4
UlDC.FLAG_DUNGEON, UlDC.FLAG_ELITE, UlDC.FLAG_RAID = FLAG_DUNGEON, FLAG_ELITE, FLAG_RAID

-- How far around the character's level a goal counts as "fits". Goals
-- below the lower bound are long grey, above the upper bound not yet.
local LEVELS_BELOW, LEVELS_ABOVE = 8, 6

local completedCache = {}
local cacheVersion = 0
local exclusive = {}     -- exclusive group -> { questID, ... }
local stepsCache         -- result of CurrentSteps for the current cacheVersion
local stepsVersion = -1

------------------------------------------------------------------------
-- Character
------------------------------------------------------------------------

local function Player()
    local _, race = UnitRace("player")
    local _, class = UnitClass("player")
    return {
        level = UnitLevel("player"),
        side = SIDE_MASK[UnitFactionGroup("player") or ""] or 0,
        race = RACE_BIT[race],      -- nil for races vanilla data does not know (Skyborne)
        class = CLASS_BIT[class] or 0,
    }
end

-- Whether the character's side, race and class can take the quest.
local function Eligible(q, me)
    if q.r and q.r ~= 0 then
        if bit.band(q.r, me.side) == 0 then return false end
        if me.race and bit.band(q.r, me.race) == 0 then return false end
    end
    if q.c and q.c ~= 0 and bit.band(q.c, me.class) == 0 then return false end
    return true
end

------------------------------------------------------------------------
-- Completion
------------------------------------------------------------------------

local function IsCompleted(id)
    local known = completedCache[id]
    if known ~= nil then return known end
    local done = false
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local ok, result = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
        done = ok and result == true
    end
    -- A quest in an exclusive group counts as done when any other member
    -- of the group is done: only one of them can ever be taken.
    if not done then
        local q = UlDC.QUESTS[id]
        if q and q.x and q.x > 0 then
            for _, other in ipairs(exclusive[q.x] or {}) do
                if other ~= id and completedCache[other] == nil then
                    local ok, result = pcall(C_QuestLog.IsQuestFlaggedCompleted, other)
                    completedCache[other] = ok and result == true
                end
                if other ~= id and completedCache[other] then
                    done = true
                    break
                end
            end
        end
    end
    completedCache[id] = done
    return done
end
UlDC.IsQuestCompleted = IsCompleted

local function IsInLog(id)
    return C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) == true
end

local function Invalidate()
    completedCache = {}
    cacheVersion = cacheVersion + 1
end

------------------------------------------------------------------------
-- Steps
------------------------------------------------------------------------

-- Walks back from a goal to the first quest in its chain that is not
-- done. Returns the step's ID and how many quests lie between the step
-- and the goal, or nil when the chain loops.
local function FirstUndone(goalID)
    local id = goalID
    local hops = 0
    while true do
        local q = UlDC.QUESTS[id]
        if not q or not q.p or IsCompleted(q.p) then return id, hops end
        id = q.p
        hops = hops + 1
        if hops > 50 then return nil end
    end
end

local function LevelFits(q, me)
    return q.l >= me.level - LEVELS_BELOW and q.l <= me.level + LEVELS_ABOVE
end

-- Every step worth showing, one entry per step quest:
-- { id, quest, goals = { goalID, ... }, inLog, tooLow, flags, keys, hops }
-- flags and keys are the union over the goals the step leads to, hops
-- the longest way from the step to one of its goals.
function UlDC.CurrentSteps()
    if stepsCache and stepsVersion == cacheVersion then return stepsCache end
    local me = Player()
    local byStep = {}
    local list = {}
    for id, q in pairs(UlDC.QUESTS) do
        if q.f and Eligible(q, me) and LevelFits(q, me) and not IsCompleted(id) then
            local stepID, hops = FirstUndone(id)
            local stepQ = stepID and UlDC.QUESTS[stepID]
            if stepQ and Eligible(stepQ, me) then
                local step = byStep[stepID]
                if not step then
                    step = { id = stepID, quest = stepQ, goals = {}, flags = 0, keys = {}, hops = 0,
                             inLog = IsInLog(stepID), tooLow = me.level < (stepQ.m or 0) }
                    byStep[stepID] = step
                    list[#list + 1] = step
                end
                step.goals[#step.goals + 1] = id
                if hops > step.hops then step.hops = hops end
                step.flags = bit.bor(step.flags, q.f)
                for _, k in ipairs(q.d or {}) do step.keys[k] = true end
            end
        end
    end
    for _, step in ipairs(list) do
        table.sort(step.goals, function(a, b) return UlDC.QUESTS[a].l < UlDC.QUESTS[b].l end)
    end
    table.sort(list, function(a, b)
        if a.quest.l ~= b.quest.l then return a.quest.l < b.quest.l end
        return a.quest.t < b.quest.t
    end)
    stepsCache, stepsVersion = list, cacheVersion
    return list
end

function UlDC.DungeonName(key)
    for _, d in ipairs(UlDC.DUNGEONS) do
        if d.key == key then return d.name end
    end
    return key
end

function UlDC.FlagText(flags)
    local parts = {}
    if bit.band(flags, FLAG_DUNGEON) ~= 0 then parts[#parts + 1] = "Dungeon" end
    if bit.band(flags, FLAG_ELITE) ~= 0 then parts[#parts + 1] = "Elite" end
    if bit.band(flags, FLAG_RAID) ~= 0 then parts[#parts + 1] = "Raid" end
    return table.concat(parts, ", ")
end

-- The game's own color for a quest level against the character's level.
function UlDC.LevelColor(level)
    if GetQuestDifficultyColor then
        local c = GetQuestDifficultyColor(level)
        if c then return c.r, c.g, c.b end
    end
    return 1, 1, 1
end

------------------------------------------------------------------------
-- Index and events
------------------------------------------------------------------------

local function BuildIndex()
    for id, q in pairs(UlDC.QUESTS) do
        if q.x and q.x > 0 then
            exclusive[q.x] = exclusive[q.x] or {}
            table.insert(exclusive[q.x], id)
        end
    end
end

local function Refresh()
    Invalidate()
    if UlDC.RefreshQuestPins then UlDC.RefreshQuestPins() end
    if UlDC.RefreshQuestBrowser then UlDC.RefreshQuestBrowser() end
end
UlDC.RefreshQuests = Refresh

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_REMOVED")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        BuildIndex()
        Invalidate()
    else
        Refresh()
    end
end)

------------------------------------------------------------------------
-- /udc qd
------------------------------------------------------------------------

function UlDC.QuestDebug()
    local me = Player()
    local total = 0
    for _ in pairs(UlDC.QUESTS) do total = total + 1 end
    UlDC.Print(string.format("%d quests in data; level %d, side %d, race %s, class %d", total, me.level, me.side,
        tostring(me.race), me.class))
    local steps = UlDC.CurrentSteps()
    print("  current steps: " .. #steps)
    for i, step in ipairs(steps) do
        if i > 25 then print("  ...") break end
        local goals = {}
        for _, g in ipairs(step.goals) do goals[#goals + 1] = UlDC.QUESTS[g].t .. " (" .. UlDC.QUESTS[g].l .. ")" end
        local giver = step.quest.g and step.quest.g[1] and step.quest.g[1].n or (step.quest.gi and ("inside " .. step.quest.gi)) or "?"
        print(string.format("  [%d] %s (%d) %s%s, giver %s -> %s", step.id, step.quest.t, step.quest.l,
            UlDC.FlagText(step.flags), step.inLog and ", in log" or (step.tooLow and ", too low" or ""), giver,
            table.concat(goals, "; ")))
    end
end
