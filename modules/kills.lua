local M = {}

local api = require("core/api")
local records = require("core/records")
local slot = require("core/request").slot
local session = require("modules/session")
local target = require("modules/target")

local EVENT_ID = "groupIronman:kills"
local TICKS_BETWEEN_SENDS = 50

local request = slot()

local tally = {}
local ticks = 0

local function onGameState(event)
    if event.newState ~= GameState.GAME then
        tally = {}
    end
end

local function onNPCRemoved(event)
    local read, name = pcall(function()
        return event.npcEntity.displayName
    end)

    if not read or type(name) ~= "string" or name == "" then
        return
    end

    if name ~= target.engagedName() then
        return
    end

    tally[name] = (tally[name] or 0) + 1
end

function M.init()
    Event.NPCEntityRemoved.Subscribe(EVENT_ID, onNPCRemoved)
    Event.GameStateChanged.Subscribe(EVENT_ID .. ":state", onGameState)
end

function M.tick()
    ticks = ticks + 1

    if ticks < TICKS_BETWEEN_SENDS or request.busy() then
        return
    end

    ticks = 0

    if records.isEmpty(tally) then
        return
    end

    local ready = session.current()
    if ready == nil then
        return
    end

    local batch = tally
    tally = {}

    local entries = {}

    for npc, count in pairs(batch) do
        entries[#entries + 1] = { npc = npc, kills = count }
    end

    request.hold(api.reportKills(ready.who, ready.name, entries, function(result)
        request.release()

        if not result.ok then
            for npc, kills in pairs(batch) do
                tally[npc] = (tally[npc] or 0) + kills
            end
        end
    end))
end

function M.shutdown()
    request.cancel()
    tally = {}
    ticks = 0
end

function M.close()
    Event.NPCEntityRemoved.Unsubscribe(EVENT_ID)
    Event.GameStateChanged.Unsubscribe(EVENT_ID .. ":state")
    M.shutdown()
end

return M
