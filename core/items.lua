local M = {}

local function read(invID, keepEmpty)
    local found, inventory = pcall(function()
        return Inventory.Find(invID)
    end)

    if not found or inventory == nil then
        return nil
    end

    local ok, valid = pcall(function()
        return inventory.isValid
    end)

    if not ok or valid ~= true then
        return nil
    end

    local listed, slots = pcall(function()
        return inventory:GetSlots()
    end)

    if not listed or slots == nil then
        return nil
    end

    local out = {}

    local walked = pcall(function()
        for _, slot in ipairs(slots) do
            local obj = slot.obj
            local objID = 0

            if obj ~= nil then
                objID = obj.id
            end

            if type(objID) == "number" and objID > 0 then
                out[#out + 1] = objID
                out[#out + 1] = math.max(0, math.floor(slot.count))
            elseif keepEmpty then
                out[#out + 1] = 0
                out[#out + 1] = 0
            end
        end
    end)

    if not walked then
        return nil
    end

    return out
end

function M.backpack()
    return read(id.Inv.INV, true)
end

function M.worn()
    return read(id.Inv.WORN, true)
end

function M.moneyPouch()
    return read(id.Inv.MONEY_POUCH, false)
end

function M.contents(invID)
    return read(invID, false)
end

function M.valueOf(objID)
    local found, proxy = pcall(function()
        return config.Obj.FromID(objID)
    end)

    if not found or proxy == nil then
        return 0
    end

    local ok, cost = pcall(function()
        return proxy.cost
    end)

    if not ok or type(cost) ~= "number" then
        return 0
    end

    return math.max(0, math.floor(cost))
end

function M.nameOf(objID)
    local fallback = "Item " .. tostring(objID)

    local found, proxy = pcall(function()
        return config.Obj.FromID(objID)
    end)

    if not found or proxy == nil then
        return fallback
    end

    local ok, name = pcall(function()
        return proxy.name
    end)

    if not ok or type(name) ~= "string" or name == "" then
        return fallback
    end

    return name
end

function M.isOpen(interfaceID)
    local found, panel = pcall(function()
        return ui.Interfaces:GetInterface(interfaceID)
    end)

    return found and panel ~= nil
end

return M
