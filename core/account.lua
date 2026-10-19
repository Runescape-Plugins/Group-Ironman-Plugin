local M = {}

local function read(varID)
    local ok, proxy = pcall(function()
        return var.VarPlayer.FromID(varID)
    end)

    if not ok or proxy == nil then
        return -1
    end

    local value = proxy.value
    if type(value) ~= "number" then
        return -1
    end

    return value
end

function M.isGroupIronman()
    return read(id.VarPlayer.GROUP_IRONMAN_ENABLED) == 1
end

function M.isCompetitive()
    return read(id.VarPlayer.GROUP_IRONMAN_CACHE_RULESET) == 1
end

return M
