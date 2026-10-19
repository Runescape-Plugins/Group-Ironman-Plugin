local M = {}

local FIRST_ID = 0
local SCAN_LIMIT = 800
local MISSES_BEFORE_STOP = 40

local function add(index, configName, questID)
    if configName == nil or configName == "" then
        return
    end

    local existing = index[configName]

    if existing == nil then
        index[configName] = { questID }
        return
    end

    for _, known in ipairs(existing) do
        if known == questID then
            return
        end
    end

    existing[#existing + 1] = questID
end

local function proxyOf(questID)
    local found, proxy = pcall(function()
        return config.Quest.FromID(questID)
    end)

    if not found or proxy == nil then
        return nil
    end

    return proxy
end

local function stateOfProxy(quest)
    local read, state = pcall(function()
        if quest.hasFinishedQuest then
            return "finished"
        end

        if quest.hasStartedQuest then
            return "started"
        end

        return "not_started"
    end)

    if not read or state == nil then
        return nil
    end

    return state
end

function M.stateOf(questID)
    local quest = proxyOf(questID)

    if quest == nil then
        return nil
    end

    return stateOfProxy(quest)
end

local function indexVars(index, quest, questID)
    return pcall(function()
        for _, progress in ipairs(quest.masterQuestVars) do
            local varPlayer = progress.varPlayer

            if varPlayer ~= nil then
                add(index, varPlayer.configName, questID)

                local base = varPlayer.baseVar

                if varPlayer.isVarBit and base ~= nil then
                    add(index, base.configName, questID)
                end
            end
        end
    end)
end

function M.sweep()
    local states = {}
    local vars = {}
    local misses = 0
    local seen = 0
    local questID = FIRST_ID

    while questID < SCAN_LIMIT do
        local quest = proxyOf(questID)

        if quest == nil then
            misses = misses + 1

            if misses >= MISSES_BEFORE_STOP and seen > 0 then
                break
            end
        else
            local state = stateOfProxy(quest)

            if state ~= nil then
                misses = 0
                seen = seen + 1
                states[questID] = state
                indexVars(vars, quest, questID)
            end
        end

        questID = questID + 1
    end

    if seen == 0 then
        return nil
    end

    return { states = states, vars = vars, seen = seen }
end

return M
