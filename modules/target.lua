local M = {}

local api = require("core/api")
local flags = require("core/flags")
local slot = require("core/request").slot
local target = require("core/target")
local session = require("modules/session")

local IDLE_NAME = "No Target"
local TICKS_BETWEEN_READS = 2
local TICKS_OF_STILL_HEALTH = 8
local TICKS_BETWEEN_SENDS = 8
local CREDIT_TICKS = 10

local request = slot()

local ticks = 0
local now = 0
local sinceSend = 0
local lastHp = -1
local stillFor = 0
local lastName
local lastNameAt = -1
local sent

local function send(who, member, fighting)
    local was = sent
    sent = fighting
    sinceSend = 0

    if not flags.reportTarget then
        return
    end

    local name = IDLE_NAME
    local hp = -1
    local percent = -1

    if fighting ~= nil then
        name = fighting.name
        hp = fighting.hp
        percent = fighting.percent
    end

    request.hold(api.setTarget(who, member, name, hp, percent, function(result)
        request.release()

        if not result.ok then
            sent = was
            return
        end
    end))
end

function M.tick()
    now = now + 1
    sinceSend = sinceSend + 1
    ticks = ticks + 1

    if ticks < TICKS_BETWEEN_READS or request.busy() then
        return
    end

    ticks = 0

    local ready = session.current()
    if ready == nil then
        sent = nil
        lastHp = -1
        return
    end

    local visible = target.overlayVisible()

    if visible == false then
        lastHp = -1
        stillFor = 0

        if sent ~= nil then
            send(ready.who, ready.name, nil)
        end

        return
    end

    local fighting = target.read()

    if fighting == nil then
        lastHp = -1
        stillFor = 0

        if sent ~= nil then
            send(ready.who, ready.name, nil)
        end

        return
    end

    local changedTarget = sent == nil or sent.name ~= fighting.name
    local movedHealth = fighting.hp ~= lastHp
    lastHp = fighting.hp

    if movedHealth then
        lastName = fighting.name
        lastNameAt = now
    end

    if changedTarget or movedHealth then
        stillFor = 0

        if (changedTarget or sinceSend >= TICKS_BETWEEN_SENDS) and not target.sameAs(sent, fighting) then
            send(ready.who, ready.name, fighting)
        end

        return
    end

    if sent == nil or visible == true then
        return
    end

    stillFor = stillFor + 1

    if stillFor == TICKS_OF_STILL_HEALTH then
        send(ready.who, ready.name, nil)
    end
end

function M.engagedName()
    if sent ~= nil then
        return sent.name
    end

    if lastName ~= nil and now - lastNameAt <= CREDIT_TICKS then
        return lastName
    end

    return nil
end

function M.shutdown()
    request.cancel()
    sent = nil
    ticks = 0
    sinceSend = 0
    lastHp = -1
    stillFor = 0
    lastName = nil
    lastNameAt = -1
end

return M
