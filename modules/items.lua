local M = {}

local api = require("core/api")
local items = require("core/items")
local slot = require("core/request").slot
local session = require("modules/session")

local EVENT_ID = "groupIronman:items"
local FLUSH_TICKS = 5
local RECHECK_TICKS = 50

local request = slot()

local function tracked(read)
    return {
        read = read,
        sent = nil,
        key = nil,
        send = nil,
        seen = false,
    }
end

local packInv = tracked(items.backpack)
local wornInv = tracked(items.worn)
local pouchInv = tracked(items.moneyPouch)

local TRACKED = { packInv, wornInv, pouchInv }

local dirty = false
local waiting = 0
local baseline = false
local sinceCheck = 0

local function reset()
    for _, entry in ipairs(TRACKED) do
        entry.sent = nil
        entry.key = nil
        entry.send = nil
        entry.seen = false
    end

    baseline = false
    dirty = false
    waiting = 0
    sinceCheck = 0
end

local function onGameState(event)
    if event.newState == GameState.GAME then
        reset()
    end
end

local function onInventory()
    dirty = true
end

local function refresh(entry)
    local slots = entry.read()
    entry.seen = slots ~= nil

    if slots == nil then
        entry.key = entry.sent
        entry.send = nil
        return
    end

    local key = table.concat(slots, ",")
    entry.key = key

    if key == entry.sent then
        entry.send = nil
    else
        entry.send = slots
    end
end

local function due()
    if not baseline then
        return true
    end

    for _, entry in ipairs(TRACKED) do
        if entry.seen and entry.sent == nil then
            return true
        end
    end

    if dirty then
        waiting = waiting + 1

        if waiting >= FLUSH_TICKS then
            return true
        end
    end

    return sinceCheck >= RECHECK_TICKS
end

function M.init()
    Event.InventoryUpdated.Subscribe(EVENT_ID, onInventory)
    Event.InventoryAdded.Subscribe(EVENT_ID .. ":added", onInventory)
    Event.InventoryRemoved.Subscribe(EVENT_ID .. ":removed", onInventory)
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

    sinceCheck = sinceCheck + 1

    if not due() then
        return
    end

    dirty = false
    waiting = 0
    sinceCheck = 0

    for _, entry in ipairs(TRACKED) do
        refresh(entry)
    end

    local first = not baseline

    if packInv.send == nil and wornInv.send == nil and pouchInv.send == nil then
        baseline = baseline or packInv.seen or wornInv.seen or pouchInv.seen
        return
    end

    request.hold(api.updateItems(
        ready.who,
        ready.name,
        packInv.send,
        wornInv.send,
        pouchInv.send,
        first,
        function(result)
            request.release()

            if not result.ok then
                dirty = true
                return
            end

            for _, entry in ipairs(TRACKED) do
                if entry.send ~= nil then
                    entry.sent = entry.key
                end
            end

            baseline = true
        end
    ))
end

function M.shutdown()
    request.cancel()
    reset()
end

function M.close()
    Event.InventoryUpdated.Unsubscribe(EVENT_ID)
    Event.InventoryAdded.Unsubscribe(EVENT_ID .. ":added")
    Event.InventoryRemoved.Unsubscribe(EVENT_ID .. ":removed")
    Event.GameStateChanged.Unsubscribe(EVENT_ID .. ":state")
    M.shutdown()
end

return M
