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
-- Every goal and step is also checked against the server once
-- (C_QuestLog.RequestLoadQuestByID): a quest the server has no data for
-- is hidden as removed, and the server's title and level replace the
-- data's, since Forever renames and retunes quests. The answers are kept
-- in the saved variables (UlDungeonCompanionDB.server) and refreshed
-- after a week.
--
-- UlDC.CurrentSteps() returns the list the pins and the hub draw, and
-- UlDC.StepLocation(step) says where a chain is picked up: the giver of
-- the first step not done. The marks (Marks.lua) are re-resolved through
-- it on every quest event, so a mark set on a chain moves along as steps
-- get done, and goes away once the step is in the log.

local RACE_BIT = { Human = 1, Orc = 2, Dwarf = 4, NightElf = 8, Scourge = 16, Tauren = 32, Gnome = 64, Troll = 128 }
local CLASS_BIT = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
local SIDE_MASK = { Alliance = 77, Horde = 178 }

local FLAG_DUNGEON, FLAG_ELITE, FLAG_RAID = 1, 2, 4
UlDC.FLAG_DUNGEON, UlDC.FLAG_ELITE, UlDC.FLAG_RAID = FLAG_DUNGEON, FLAG_ELITE, FLAG_RAID

-- How far around the character's level a goal counts as "fits". Goals
-- below the lower bound are long grey, above the upper bound not yet.
local LEVELS_BELOW, LEVELS_ABOVE = 8, 6

-- Forever's own quests (QuestDataForever.lua, see tools/fetch_forever.py)
-- join the vanilla table; vanilla wins when both know an ID.
for id, q in pairs(UlDC.QUESTS_FOREVER or {}) do
    if not UlDC.QUESTS[id] then UlDC.QUESTS[id] = q end
end

-- Givers from Forever data carry map percentages (mp = { mapID, x, y })
-- instead of world positions. The client converts them once at login, so
-- the pins and the hub only ever see pos = { continent, x, y }.
local function ResolveMapPositions()
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    for _, q in pairs(UlDC.QUESTS) do
        for _, g in ipairs(q.g or {}) do
            if g.mp and not g.pos then
                local pos = {}
                for _, mp in ipairs(g.mp) do
                    local continentID, world = C_Map.GetWorldPosFromMapPos(mp[1], CreateVector2D(mp[2] / 100, mp[3] / 100))
                    if continentID and world then
                        local wx, wy = world:GetXY()
                        if wx and wy then pos[#pos + 1] = { continentID, wx, wy } end
                    end
                end
                g.pos = pos
            end
        end
    end
end
UlDC.ResolveMapPositions = ResolveMapPositions

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
-- Server facts
------------------------------------------------------------------------

local RECHECK_AFTER = 7 * 24 * 3600   -- seconds before a server answer is asked again
local REQUEST_WAIT = 4                -- seconds to wait for QUEST_DATA_LOAD_RESULT
local BATCH = 25                      -- requests per second at most

local server            -- UlDC.db.server: id -> { t, l, tag, missing, seen }
local pending = {}      -- id -> true while a request is out
local queue = {}        -- ids waiting to be requested
local queued = {}       -- set of the same
local changeTimer       -- debounce for the refresh after answers arrive

-- Reads what the client has about a quest. Returns false when it has
-- nothing yet (or ever, for a quest that does not exist).
local function ReadServer(id)
    if HaveQuestData and not HaveQuestData(id) then return false end
    local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    if not title or title == "" then return false end
    -- "<UNUSED>" and friends: the server knows the ID but the quest is a placeholder.
    if title:sub(1, 1) == "<" then return false end
    local level = C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(id) or 0
    local ok, tag = pcall(C_QuestLog.GetQuestTagInfo, id)
    server[id] = { t = title, l = level > 0 and level or nil, tag = ok and tag and tag.tagID or nil, seen = time() }
    return true
end

local function Changed()
    if changeTimer then return end
    changeTimer = C_Timer.NewTimer(0.5, function()
        changeTimer = nil
        if UlDC.RefreshQuests then UlDC.RefreshQuests() end
    end)
end

local function Settle(id)
    if not pending[id] then return end
    pending[id] = nil
    if not ReadServer(id) then
        server[id] = { missing = true, seen = time() }
    end
    Changed()
end

local function SendBatch()
    local sent = 0
    while #queue > 0 and sent < BATCH do
        local id = table.remove(queue, 1)
        queued[id] = nil
        if not ReadServer(id) then
            pending[id] = true
            pcall(C_QuestLog.RequestLoadQuestByID, id)
            C_Timer.After(REQUEST_WAIT, function() Settle(id) end)
            sent = sent + 1
        end
    end
    if #queue > 0 then C_Timer.After(1, SendBatch) end
end

-- Asks the server about a quest unless a fresh answer is already kept.
local function Validate(id)
    if not server or not (C_QuestLog and C_QuestLog.RequestLoadQuestByID) then return end
    local known = server[id]
    if known and (time() - (known.seen or 0)) < RECHECK_AFTER then return end
    if pending[id] or queued[id] then return end
    queued[id] = true
    queue[#queue + 1] = id
    if #queue == 1 then C_Timer.After(0, SendBatch) end
end

local function IsMissing(id)
    local known = server and server[id]
    return known ~= nil and known.missing == true
end

-- Title and level with the server's answer first, the data's as fallback.
function UlDC.QuestTitle(id)
    local known = server and server[id]
    if known and known.t then return known.t end
    local q = UlDC.QUESTS[id]
    return q and q.t or ("quest " .. id)
end

function UlDC.QuestLevel(id)
    local known = server and server[id]
    if known and known.l then return known.l end
    local q = UlDC.QUESTS[id]
    return q and q.l or 0
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

local function LevelFits(id, me)
    local level = UlDC.QuestLevel(id)
    return level >= me.level - LEVELS_BELOW and level <= me.level + LEVELS_ABOVE
end

local function GiverName(q)
    return q.g and q.g[1] and q.g[1].n or q.gi or ""
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
        if q.f and Eligible(q, me) and LevelFits(id, me) and not IsCompleted(id) and not IsMissing(id) then
            Validate(id)
            local stepID, hops = FirstUndone(id)
            local stepQ = stepID and UlDC.QUESTS[stepID]
            if stepQ and Eligible(stepQ, me) and not IsMissing(stepID) then
                Validate(stepID)
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
    -- Several quests with the same name from the same giver (the six
    -- Sparklematic quests in Gnomeregan) collapse into one row.
    local seen = {}
    local deduped = {}
    for _, step in ipairs(list) do
        local key = UlDC.QuestTitle(step.id) .. "|" .. GiverName(step.quest)
        local first = seen[key]
        if first then
            for _, g in ipairs(step.goals) do first.goals[#first.goals + 1] = g end
            first.flags = bit.bor(first.flags, step.flags)
            for k in pairs(step.keys) do first.keys[k] = true end
            if step.hops > first.hops then first.hops = step.hops end
        else
            seen[key] = step
            deduped[#deduped + 1] = step
        end
    end
    list = deduped
    for _, step in ipairs(list) do
        table.sort(step.goals, function(a, b) return UlDC.QuestLevel(a) < UlDC.QuestLevel(b) end)
    end
    table.sort(list, function(a, b)
        local la, lb = UlDC.QuestLevel(a.id), UlDC.QuestLevel(b.id)
        if la ~= lb then return la < lb end
        return UlDC.QuestTitle(a.id) < UlDC.QuestTitle(b.id)
    end)
    stepsCache, stepsVersion = list, cacheVersion
    return list
end

-- A step built for one goal alone, the shape UlDC.CurrentSteps() uses,
-- without the level window: the marks follow their goal past it. nil when
-- the goal is done, unknown, or its chain loops.
function UlDC.StepForGoal(goalID)
    local goal = UlDC.QUESTS[goalID]
    if not goal or IsCompleted(goalID) then return nil end
    local stepID, hops = FirstUndone(goalID)
    local stepQ = stepID and UlDC.QUESTS[stepID]
    if not stepQ then return nil end
    local keys = {}
    for _, k in ipairs(goal.d or {}) do keys[k] = true end
    return { id = stepID, quest = stepQ, goals = { goalID }, flags = goal.f or 0, keys = keys, hops = hops,
             inLog = IsInLog(stepID), tooLow = UnitLevel("player") < (stepQ.m or 0) }
end

local function EntranceNode(key)
    for _, d in ipairs(UlDC.DUNGEONS or {}) do
        if d.key == key then return d end
    end
    return nil
end

-- A mark for Marks.lua, tagged with the step and its goals so the mark
-- can follow the chain as the steps get done (UlDC.FollowMarks).
local function StepMark(step, label, note, p)
    local mark = { label = label, note = note, quest = step.id, goals = {} }
    for i, g in ipairs(step.goals or {}) do mark.goals[i] = g end
    if p then mark.continent, mark.x, mark.y = p[1], p[2], p[3] end
    return mark
end

-- Where a step is picked up, which is where the character is in the
-- chain. Returns the kind, a name, and a mark table for Marks.lua; nil
-- when nothing is known, and nil for a step in the log: from there the
-- quest log leads, the marker is not needed (Jonatan, 16.10.2026).
--   "giver"    the step's giver.
--   "entrance" the step starts inside an instance (a giver standing in
--              there, or a quest started by an item found there): the
--              entrance.
function UlDC.StepLocation(step)
    if step.inLog then return nil end
    local q = step.quest
    local title = UlDC.QuestTitle(step.id)
    local giver = q.g and q.g[1]
    local p = giver and giver.pos and giver.pos[1]
    if p then
        return "giver", giver.n, StepMark(step, giver.n, title, p)
    end
    -- Started by an item with no known drop and not inside an instance:
    -- nowhere to point yet.
    if giver and giver.k == "i" and not q.gi then return nil end
    local key = q.gi or (q.d and q.d[1]) or (q.cd and q.cd[1])
    if not key then
        for k in pairs(step.keys or {}) do key = k break end
    end
    local node = key and EntranceNode(key)
    local mark = node and UlDC.EntranceMark and UlDC.EntranceMark(node)
    if not mark then return nil end
    local tagged = StepMark(step, mark.label, title .. ", starts inside")
    tagged.map, tagged.mx, tagged.my = mark.map, mark.mx, mark.my
    tagged.continent, tagged.x, tagged.y = mark.continent, mark.x, mark.y
    return "entrance", node.name, tagged
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
    if UlDC.FollowMarks then UlDC.FollowMarks() end
    if UlDC.RefreshQuestPins then UlDC.RefreshQuestPins() end
    if UlDC.RefreshHub then UlDC.RefreshHub() end
end
UlDC.RefreshQuests = Refresh

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_REMOVED")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("QUEST_DATA_LOAD_RESULT")
frame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "PLAYER_LOGIN" then
        ResolveMapPositions()
        if UlDC.db then
            UlDC.db.server = UlDC.db.server or {}
            server = UlDC.db.server
        end
        BuildIndex()
        Invalidate()
    elseif event == "QUEST_DATA_LOAD_RESULT" then
        if pending[arg1] then
            if arg2 then Settle(arg1) end
            -- A failed load is left to the timer: the data may still arrive.
        end
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
    local answered, missing, waiting = 0, 0, 0
    for _, v in pairs(server or {}) do
        if v.missing then missing = missing + 1 else answered = answered + 1 end
    end
    for _ in pairs(pending) do waiting = waiting + 1 end
    print(string.format("  server answers kept: %d, removed quests: %d, waiting: %d, queued: %d", answered, missing, waiting, #queue))
    print("  current steps: " .. #steps)
    -- Keep the steps and the character in the saved variables so they can
    -- be read from the file after a /reload.
    if UlDC.db then
        local saved = { time = date("%Y-%m-%d %H:%M:%S"), level = me.level, side = me.side, class = me.class, steps = {} }
        for _, step in ipairs(steps) do
            saved.steps[#saved.steps + 1] = { id = step.id, goals = step.goals, hops = step.hops,
                inLog = step.inLog, tooLow = step.tooLow }
        end
        UlDC.db.questDebug = saved
    end
    for i, step in ipairs(steps) do
        if i > 25 then print("  ...") break end
        local goals = {}
        for _, g in ipairs(step.goals) do goals[#goals + 1] = UlDC.QuestTitle(g) .. " (" .. UlDC.QuestLevel(g) .. ")" end
        local giver = step.quest.g and step.quest.g[1] and step.quest.g[1].n or (step.quest.gi and ("inside " .. step.quest.gi)) or "?"
        print(string.format("  [%d] %s (%d) %s%s, giver %s -> %s", step.id, UlDC.QuestTitle(step.id), UlDC.QuestLevel(step.id),
            UlDC.FlagText(step.flags), step.inLog and ", in log" or (step.tooLow and ", too low" or ""), giver,
            table.concat(goals, "; ")))
    end
end
