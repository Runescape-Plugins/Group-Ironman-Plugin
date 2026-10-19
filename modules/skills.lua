local M = {}

local api = require("core/api")
local records = require("core/records")
local slot = require("core/request").slot
local skills = require("core/skills")
local session = require("modules/session")

local EVENT_ID = "groupIronman:skills"
local FLUSH_TICKS = 5

local request = slot()

local dirty = {}
local waiting = 0
local baseline = false

local function reset()
    baseline = false
    dirty = {}
    waiting = 0
end

local function onGameState(event)
    if event.newState == GameState.GAME then
        reset()
    end
end

local function onSkill(event)
    if event.newXP == event.oldXP and event.newGameplayLevel == event.oldGameplayLevel then
        return
    end

    local id = skills.idFor(event.skill)
    if id ~= nil then
        dirty[id] = true
    end
end

local function send(who, member, payload, isBaseline, restore)
    if payload == nil then
        baseline = baseline or isBaseline
        return
    end

    request.hold(api.updateSkills(who, member, payload, isBaseline, function(result)
        request.release()

        if result.ok then
            baseline = baseline or isBaseline
            return
        end

        if restore ~= nil then
            for id in pairs(restore) do
                dirty[id] = true
            end
        end
    end))
end

function M.init()
    Event.SkillTransmit.Subscribe(EVENT_ID, onSkill)
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
        send(ready.who, ready.name, skills.snapshot(), true)
        return
    end

    if records.isEmpty(dirty) then
        return
    end

    waiting = waiting + 1

    if waiting < FLUSH_TICKS then
        return
    end

    local changed = dirty
    dirty = {}
    waiting = 0

    send(ready.who, ready.name, skills.snapshot(changed), false, changed)
end

function M.shutdown()
    request.cancel()
    reset()
end

function M.close()
    Event.SkillTransmit.Unsubscribe(EVENT_ID)
    Event.GameStateChanged.Unsubscribe(EVENT_ID .. ":state")
    M.shutdown()
end

return M
