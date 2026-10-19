local M = {}

local api = require("core/api")
local slot = require("core/request").slot

local request = slot()
local names = {}
local loaded = false

function M.clear()
    names = {}
    loaded = false
    request.cancel()
end

function M.known()
    return names
end

function M.isLoaded()
    return loaded
end

function M.load(credentials, done)
    if request.busy() then
        return
    end

    request.hold(api.members(credentials, function(result, found)
        request.release()

        if not result.ok then
            done(false, {})
            return
        end

        names = found
        loaded = true
        done(true, found)
    end))
end

local function localName()
    if not Player.IsAvailable() then
        return nil
    end

    local entity = Player.GetEntity()
    if entity == nil then
        return nil
    end

    return entity.displayName
end

function M.isMember(name)
    for _, known in ipairs(names) do
        if known == name then
            return true
        end
    end

    return false
end

function M.membership()
    if not loaded then
        return "unknown"
    end

    local name = localName()
    if name == nil then
        return "unknown"
    end

    if M.isMember(name) then
        return "member"
    end

    return "stranger"
end

return M
