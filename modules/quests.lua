local M = {}

local api = require("core/api")
local quests = require("core/quests")
local records = require("core/records")
local slot = require("core/request").slot
local session = require("modules/session")

local EVENT_ID = "groupIronman:quests"
local FLUSH_TICKS = 2

local request = slot()

local sent = {}
local watched = {}
local pending = {}
local baseline = false
local waiting = 0

local function reset()
    sent = {}
    watched = {}
    pending = {}
    baseline = false
    waiting = 0
end

local function onGameState(event)
    if event.newState == GameState.GAME then
        reset()
    end
end

local function onVar(event)
    if not baseline then
        return
    end

    local named, configName = pcall(function()
        return event.var.configName
    end)

    if not named or type(configName) ~= "string" then
        return
    end

    local affected = watched[configName]
    if affected == nil then
        return
    end

    for _, questID in ipairs(affected) do
        pending[questID] = true
    end
end

local function sendBaseline(who, member)
    local swept = quests.sweep()

    if swept == nil then
        return
    end

    watched = swept.vars

    local entries = {}
    local states = {}

    for questID, state in pairs(swept.states) do
        states[questID] = state
        entries[#entries + 1] = api.questEntry(questID, state)
    end

    request.hold(api.updateQuests(who, member, entries, true, function(result)
        request.release()

        if not result.ok then
            return
        end

        sent = states
        baseline = true
    end))
end

local function sendChanged(who, member)
    local batch = pending
    pending = {}

    local entries = {}
    local states = {}

    for questID in pairs(batch) do
        local state = quests.stateOf(questID)

        if state ~= nil and state ~= sent[questID] then
            states[questID] = state
            entries[#entries + 1] = api.questEntry(questID, state)
        end
    end

    if #entries == 0 then
        return
    end

    request.hold(api.updateQuests(who, member, entries, false, function(result)
        request.release()

        if not result.ok then
            for questID in pairs(batch) do
                pending[questID] = true
            end

            return
        end

        for questID, state in pairs(states) do
            sent[questID] = state
        end
    end))
end

function M.init()
    Event.VarTransmit.Subscribe(EVENT_ID, onVar)
    Event.GameStateChanged.Subscribe(EVENT_ID .. ":state", onGameState)
end

function M.tick()
    if request.busy() then
        return
    end

    local ready = session.current()
    if ready == nil then
        return
    end

    if not baseline then
        sendBaseline(ready.who, ready.name)
        return
    end

    if records.isEmpty(pending) then
        return
    end

    waiting = waiting + 1

    if waiting < FLUSH_TICKS then
        return
    end

    waiting = 0
    sendChanged(ready.who, ready.name)
end

function M.shutdown()
    request.cancel()
    reset()
end

function M.close()
    Event.VarTransmit.Unsubscribe(EVENT_ID)
    Event.GameStateChanged.Unsubscribe(EVENT_ID .. ":state")
    M.shutdown()
end

return M
