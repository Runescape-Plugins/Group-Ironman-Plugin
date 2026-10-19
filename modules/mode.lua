local M = {}

local api = require("core/api")
local isCompetitive = require("core/account").isCompetitive
local slot = require("core/request").slot
local session = require("modules/session")

local EVENT_ID = "groupIronman:mode"
local RETRY_TICKS = 250

local request = slot()

local now = 0
local retryAt = 0
local sent

local function reset()
    retryAt = 0
    sent = nil
end

local function onGameState(event)
    if event.newState == GameState.GAME then
        reset()
    end
end

function M.init()
    Event.GameStateChanged.Subscribe(EVENT_ID, onGameState)
end

function M.tick()
    now = now + 1

    if request.busy() or now < retryAt then
        return
    end

    local ready = session.current()
    if ready == nil then
        return
    end

    local mode = "normal"
    if isCompetitive() then
        mode = "competitive"
    end

    if mode == sent then
        return
    end

    request.hold(api.syncGroupMode(ready.who, mode, function(result)
        request.release()

        if not result.ok then
            retryAt = now + RETRY_TICKS
            return
        end

        sent = mode
    end))
end

function M.shutdown()
    request.cancel()
    reset()
end

function M.close()
    Event.GameStateChanged.Unsubscribe(EVENT_ID)
    M.shutdown()
end

return M
