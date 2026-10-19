local M = {}

local api = require("core/api")
local items = require("core/items")
local kills = require("core/kills")
local records = require("core/records")
local slot = require("core/request").slot
local session = require("modules/session")

local EVENT_ID = "groupIronman:drops"
local SETTLE_TICKS = 2
local MAX_QUEUED = 8
local PICKUP_TICKS = 100
local FIRST_RETRY_TICKS = 50
local MAX_RETRY_TICKS = 1500

local HANDLING_WINDOWS = {
    function()
        return id.Interface.BANK
    end,
    function()
        return id.Interface.GROUP_IRONMAN_STORAGE
    end,
    function()
        return id.Interface.STOCKMARKET
    end,
    function()
        return id.Interface.STOCKCOLLECT
    end,
    function()
        return id.Interface.SHOP_MAIN
    end,
    function()
        return id.Interface.TRADEMAIN
    end,
    function()
        return id.Interface.TRADECONFIRM
    end,
}

local request = slot()

local changed = false
local settling = 0
local now = 0
local fromGround = {}
local before
local queue = {}
local rules
local askedForRules = false
local retryAt = 0
local retryDelay = 0

local function justCameOffTheFloor(objID)
    local at = fromGround[objID]
    return at ~= nil and now - at <= PICKUP_TICKS
end

local function worthReporting(objID, quantity)
    if rules == nil then
        return false
    end

    if rules.items[objID] == true then
        local window = rules.windows[objID]

        if window == nil then
            return true
        end

        if window.min > 0 and quantity < window.min then
            return false
        end

        return window.max == 0 or quantity <= window.max
    end

    return rules.threshold > 0 and items.valueOf(objID) >= rules.threshold
end

local function add(objID, count, source)
    local quantity = math.max(1, math.floor(count))

    if #queue >= MAX_QUEUED or not worthReporting(objID, quantity) then
        return
    end

    queue[#queue + 1] = { objID = objID, quantity = quantity, source = source }
end

local function movingItemsByHand()
    for _, window in ipairs(HANDLING_WINDOWS) do
        local known, interfaceID = pcall(window)

        if known and type(interfaceID) == "number" and items.isOpen(interfaceID) then
            return true
        end
    end

    return false
end

local function readBackpack()
    local pack = items.backpack()

    if pack == nil then
        return
    end

    local after = records.totals(pack)
    local previous = before
    before = after

    if previous == nil or movingItemsByHand() then
        return
    end

    for objID, count in pairs(after) do
        local had = previous[objID] or 0

        if count > had and not justCameOffTheFloor(objID) then
            add(objID, count - had, kills.latest())
        end
    end
end

local function onInventory()
    changed = true
    settling = 0
end

local function onGameState(event)
    fromGround = {}

    if event.newState == GameState.GAME then
        rules = nil
        askedForRules = false
        retryAt = 0
        retryDelay = 0
        return
    end

    kills.clear()
    before = nil
    queue = {}
end

local function onNPCRemoved(event)
    kills.remember(event.npcEntity)
end

local function onGroundItem(event)
    if not event.isOwner then
        return
    end

    local objType = event.objType
    if objType == nil then
        return
    end

    local read, objID = pcall(function()
        return objType.id
    end)

    if not read or type(objID) ~= "number" then
        return
    end

    fromGround[objID] = now
    add(objID, event.count, kills.near(event.coordGrid))
end

local function fetchRules(who)
    if askedForRules or request.busy() or now < retryAt then
        return
    end

    askedForRules = true

    request.hold(api.dropRules(who, function(result, fetched)
        request.release()

        if not result.ok or fetched == nil then
            askedForRules = false

            if retryDelay == 0 then
                retryDelay = FIRST_RETRY_TICKS
            else
                retryDelay = math.min(retryDelay * 2, MAX_RETRY_TICKS)
            end

            retryAt = now + retryDelay
            return
        end

        rules = fetched
        retryDelay = 0
        retryAt = 0
    end))
end

local function send(who, member)
    local find = queue[1]
    local rest = {}

    for i = 2, #queue do
        rest[#rest + 1] = queue[i]
    end

    queue = rest

    local name = items.nameOf(find.objID)
    local worth = items.valueOf(find.objID)

    request.hold(api.reportDrop(who, member, find.objID, find.quantity, name, worth, find.source,
        function()
            request.release()
        end))
end

function M.init()
    Event.NPCEntityRemoved.Subscribe(EVENT_ID, onNPCRemoved)
    Event.ObjStackEntityAdded.Subscribe(EVENT_ID .. ":ground", onGroundItem)
    Event.GameStateChanged.Subscribe(EVENT_ID .. ":state", onGameState)
    Event.InventoryUpdated.Subscribe(EVENT_ID .. ":inv", onInventory)
    Event.InventoryAdded.Subscribe(EVENT_ID .. ":added", onInventory)
    Event.InventoryRemoved.Subscribe(EVENT_ID .. ":removed", onInventory)
end

function M.tick()
    kills.advance()
    now = now + 1

    local ready = session.current()
    if ready == nil then
        before = nil
        return
    end

    if rules == nil then
        fetchRules(ready.who)
        before = nil
        return
    end

    if changed then
        settling = settling + 1

        if settling < SETTLE_TICKS then
            return
        end

        changed = false
        settling = 0
        readBackpack()
    end

    if request.busy() or #queue == 0 then
        return
    end

    send(ready.who, ready.name)
end

function M.shutdown()
    request.cancel()
    kills.clear()
    before = nil
    queue = {}
    changed = false
    settling = 0
    fromGround = {}
    rules = nil
    askedForRules = false
    retryAt = 0
    retryDelay = 0
end

function M.close()
    Event.NPCEntityRemoved.Unsubscribe(EVENT_ID)
    Event.ObjStackEntityAdded.Unsubscribe(EVENT_ID .. ":ground")
    Event.GameStateChanged.Unsubscribe(EVENT_ID .. ":state")
    Event.InventoryUpdated.Unsubscribe(EVENT_ID .. ":inv")
    Event.InventoryAdded.Unsubscribe(EVENT_ID .. ":added")
    Event.InventoryRemoved.Unsubscribe(EVENT_ID .. ":removed")
    M.shutdown()
end

return M
