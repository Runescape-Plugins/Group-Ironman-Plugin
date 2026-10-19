local M = {}

local REMEMBER_TICKS = 20
local NEAR_TILES = 12

local recent = {}
local now = 0

local function tileOf(grid)
    local read, value = pcall(function()
        return {
            x = grid.mapSquareX * 64 + grid.localX,
            z = grid.mapSquareZ * 64 + grid.localZ,
            level = grid.level,
        }
    end)

    if not read then
        return nil
    end

    return value
end

function M.advance()
    now = now + 1

    local oldest = recent[1]

    if oldest == nil or now - oldest.at <= REMEMBER_TICKS then
        return
    end

    local keep = {}

    for _, kill in ipairs(recent) do
        if now - kill.at <= REMEMBER_TICKS then
            keep[#keep + 1] = kill
        end
    end

    recent = keep
end

function M.remember(npc)
    local read, named = pcall(function()
        return npc.displayName
    end)

    if not read or type(named) ~= "string" or named == "" then
        return
    end

    local located, grid = pcall(function()
        return npc.coordGrid
    end)

    if not located or grid == nil then
        return
    end

    local tile = tileOf(grid)
    if tile == nil then
        return
    end

    recent[#recent + 1] = {
        name = named,
        x = tile.x,
        z = tile.z,
        level = tile.level,
        at = now,
    }
end

function M.near(grid)
    local tile = tileOf(grid)

    if tile == nil then
        return nil
    end

    local best
    local bestAt = -1

    for _, kill in ipairs(recent) do
        if kill.level == tile.level then
            local dx = math.abs(kill.x - tile.x)
            local dz = math.abs(kill.z - tile.z)

            if dx <= NEAR_TILES and dz <= NEAR_TILES and kill.at > bestAt then
                best = kill.name
                bestAt = kill.at
            end
        end
    end

    return best
end

function M.latest()
    local best
    local bestAt = -1

    for _, kill in ipairs(recent) do
        if kill.at > bestAt then
            best = kill.name
            bestAt = kill.at
        end
    end

    return best
end

function M.clear()
    recent = {}
    now = 0
end

return M
