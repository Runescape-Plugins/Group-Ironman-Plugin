local M = {}

local api = require("core/api")
local slot = require("core/request").slot
local vitals = require("core/vitals")
local session = require("modules/session")

local EVENT_ID = "groupIronman:vitals"
local TICKS_BETWEEN_PUSHES = 100
local TICKS_BETWEEN_PRESENCE_TRIES = 50

local request = slot()

local ticks = TICKS_BETWEEN_PUSHES
local sent = ""
local presenceWait = 0
local presence
local lastName

local function sendPresence(wanted)
    local who = session.signedIn()

    if who == nil then
        presence = nil
        return
    end

    request.hold(api.setMemberOnline(who, wanted.name, wanted.online, wanted.lobby, function(result)
        request.release()

        if not result.ok then
            return
        end

        if presence == wanted then
            presence = nil
        end
    end))
end

local function onGameState(event)
    sent = ""
    ticks = TICKS_BETWEEN_PUSHES

    if event.newState == GameState.GAME then
        presence = nil
        return
    end

    local name = lastName
    if name == nil then
        return
    end

    local lobby = event.newState == GameState.LOBBY
    local wanted = { name = name, online = lobby, lobby = lobby }

    presence = wanted
    presenceWait = 0
    request.cancel()
end

local function reportPresence()
    local wanted = presence

    if wanted == nil then
        return false
    end

    if request.busy() then
        return true
    end

    presenceWait = presenceWait + 1

    if presenceWait < TICKS_BETWEEN_PRESENCE_TRIES then
        return true
    end

    presenceWait = 0
    sendPresence(wanted)
    return true
end

function M.init()
    Event.GameStateChanged.Subscribe(EVENT_ID, onGameState)
end

function M.tick()
    if reportPresence() then
        return
    end

    local ready = session.current()
    if ready ~= nil then
        lastName = ready.name
    end

    ticks = ticks + 1

    if ticks < TICKS_BETWEEN_PUSHES or request.busy() then
        return
    end

    if ready == nil then
        return
    end

    ticks = 0

    local stats = vitals.toStats(vitals.read())
    local key = table.concat(stats, ",")

    if key == sent then
        return
    end

    request.hold(api.updateStats(ready.who, ready.name, stats, function(result)
        request.release()

        if not result.ok then
            return
        end

        sent = key
    end))
end

function M.shutdown()
    request.cancel()
    sent = ""
    presence = nil
    presenceWait = 0
end

function M.close()
    Event.GameStateChanged.Unsubscribe(EVENT_ID)
    M.shutdown()
end

return M
