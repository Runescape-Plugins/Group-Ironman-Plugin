local M = {}

local api = require("core/api")
local slot = require("core/request").slot
local settings = require("core/settings")
local session = require("modules/session")

local EVENT_ID = "groupIronman:location"
local TICKS_BETWEEN_PUSHES = 1
local TICKS_BETWEEN_HEARTBEATS = 17

local request = slot()

local ticks = TICKS_BETWEEN_PUSHES
local beats = 0
local lastX = -1
local lastZ = -1
local lastLevel = -1
local sharing = true

local function forget()
    lastX = -1
    lastZ = -1
    lastLevel = -1
end

local function heartbeat()
    local ready = session.current()
    if ready == nil then
        return
    end

    beats = 0

    request.hold(api.setMemberOnline(ready.who, ready.name, true, false, function()
        request.release()
    end))
end

local function push()
    ticks = ticks + 1

    if ticks < TICKS_BETWEEN_PUSHES then
        return false
    end

    local ready = session.current()
    if ready == nil then
        return false
    end

    ticks = 0

    local entity = Player.GetEntity()
    if entity == nil then
        return false
    end

    local grid = entity.coordGrid
    if grid == nil then
        return false
    end

    local x = grid.mapSquareX * 64 + grid.localX
    local z = grid.mapSquareZ * 64 + grid.localZ
    local level = grid.level

    if x == lastX and z == lastZ and level == lastLevel then
        return false
    end

    request.hold(api.playerMoved(ready.who, ready.name, x, z, level, function(result)
        request.release()

        if not result.ok then
            return
        end

        lastX = x
        lastZ = z
        lastLevel = level
        beats = 0
    end))

    return true
end

local function onServerLogic()
    local shares = settings.sharesLocation()

    if shares ~= sharing then
        sharing = shares
        forget()
    end

    beats = beats + 1

    if request.busy() then
        return
    end

    if shares and push() then
        return
    end

    if beats >= TICKS_BETWEEN_HEARTBEATS then
        heartbeat()
    end
end

function M.init()
    Event.ServerLogic.Subscribe(EVENT_ID, onServerLogic)
end

function M.shutdown()
    request.cancel()
    forget()
    ticks = TICKS_BETWEEN_PUSHES
    beats = 0
end

function M.close()
    Event.ServerLogic.Unsubscribe(EVENT_ID)
    M.shutdown()
end

return M
