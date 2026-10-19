local M = {}

local api = require("core/api")
local items = require("core/items")
local records = require("core/records")
local slot = require("core/request").slot
local session = require("modules/session")

local EVENT_ID = "groupIronman:bank"
local SETTLE_TICKS = 3

local request = slot()

local function store(field, window, inv)
    return {
        field = field,
        window = window,
        inv = inv,
        windowID = -1,
        invID = -1,
        size = -1,
        seen = false,
        held = nil,
    }
end

local own = store("bank", function()
    return id.Interface.BANK
end, function()
    return id.Inv.BANK
end)

local group = store("shared_bank", function()
    return id.Interface.GROUP_IRONMAN_STORAGE
end, function()
    return id.Inv.GROUP_IRONMAN_STORAGE_CLAN_TEMP
end)

local STORES = { own, group }

local changed = false
local settling = 0

local function reset()
    for _, target in ipairs(STORES) do
        target.seen = false
        target.held = nil
    end

    changed = false
    settling = 0
end

local function resolve(known, lookup)
    if known >= 0 then
        return known
    end

    local ok, value = pcall(lookup)

    if ok and type(value) == "number" then
        return math.floor(value)
    end

    return -1
end

local function sizeOf(source)
    local ok, count = pcall(function()
        return source.slotCount
    end)

    if ok and type(count) == "number" then
        return math.floor(count)
    end

    return -1
end

local function windowOpen(target)
    target.windowID = resolve(target.windowID, target.window)
    return target.windowID >= 0 and items.isOpen(target.windowID)
end

local function measure(target)
    if target.size >= 0 then
        return
    end

    target.invID = resolve(target.invID, target.inv)

    if target.invID < 0 then
        return
    end

    local found, proxy = pcall(function()
        return Inventory.Find(target.invID)
    end)

    if found and proxy ~= nil then
        target.size = sizeOf(proxy)
    end
end

local function arm()
    changed = true
    settling = 0
end

local function note(source)
    if windowOpen(own) or windowOpen(group) then
        measure(own)
        measure(group)
        arm()
        return
    end

    local size = -1
    if source ~= nil then
        size = sizeOf(source)
    end

    if size >= 0 and (size == own.size or size == group.size) then
        arm()
    end
end

local function onInventory(event)
    note(event.inv)
end

local function onGameState(event)
    if event.newState == GameState.GAME then
        reset()
    end
end

local function snapshot(target)
    local showing = windowOpen(target)

    if showing then
        measure(target)
    elseif not target.seen then
        return nil
    end

    target.invID = resolve(target.invID, target.inv)

    if target.invID < 0 then
        return nil
    end

    local slots = items.contents(target.invID)

    if slots == nil then
        return nil
    end

    if not showing and #slots == 0 and target.held ~= nil then
        return nil
    end

    if showing then
        target.seen = true
    end

    return slots
end

function M.init()
    Event.InventoryUpdated.Subscribe(EVENT_ID, onInventory)
    Event.InventoryAdded.Subscribe(EVENT_ID .. ":added", onInventory)
    Event.InventoryRemoved.Subscribe(EVENT_ID .. ":removed", onInventory)
    Event.GameStateChanged.Subscribe(EVENT_ID .. ":state", onGameState)
end

function M.tick()
    if not changed or request.busy() then
        return
    end

    settling = settling + 1

    if settling < SETTLE_TICKS then
        return
    end

    local ready = session.current()
    if ready == nil then
        return
    end

    local pushes = {}
    local pending = {}
    local read = false

    for _, target in ipairs(STORES) do
        local slots = snapshot(target)

        if slots ~= nil then
            read = true

            local after = records.totals(slots)
            local before = target.held

            if before == nil then
                pushes[#pushes + 1] = { field = target.field, pairs = slots, full = true }
                pending[target.field] = after
            else
                local delta = records.deltas(before, after)

                if #delta > 0 then
                    pushes[#pushes + 1] = { field = target.field, pairs = delta, full = false }
                    pending[target.field] = after
                end
            end
        end
    end

    if not read then
        settling = 0
        return
    end

    changed = false
    settling = 0

    if #pushes == 0 then
        return
    end

    request.hold(api.updateInventories(ready.who, ready.name, pushes, function(result)
        request.release()

        if not result.ok then
            changed = true
            return
        end

        for _, target in ipairs(STORES) do
            local after = pending[target.field]

            if after ~= nil then
                target.held = after
            end
        end
    end))
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
