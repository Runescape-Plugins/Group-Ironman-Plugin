local M = {}

local FRIENDS_TITLES = {
    function()
        return id.Component.TOPLEVEL_V2_PARENT_SUBOVERLAY_FRIENDS__FRIENDS_TITLE
    end,
    function()
        return id.Component.FRIENDS2__FRIENDS_TITLE
    end,
}

local POINTS_PER_LEVEL = 10
local LIFE_POINTS_PER_LEVEL = 100
local TENTHS = 10

local function varValue(varID)
    local ok, proxy = pcall(function()
        return var.VarPlayer.FromID(varID)
    end)

    if not ok or proxy == nil then
        return 0
    end

    local value = proxy.value
    if type(value) ~= "number" then
        return 0
    end

    return math.max(0, math.floor(value))
end

local function level(skill)
    local ok, value = pcall(function()
        return Player.GetLevelUncapped(skill)
    end)

    if not ok or type(value) ~= "number" then
        return 0
    end

    return math.max(0, math.floor(value))
end

local function componentText(combined)
    local ok, component = pcall(function()
        return ui.Interfaces:GetComponent(combined)
    end)

    if not ok or component == nil then
        return nil
    end

    if type(component.text) == "string" then
        return component.text
    end

    if type(component.content) == "string" then
        return component.content
    end

    return nil
end

local function world()
    for _, title in ipairs(FRIENDS_TITLES) do
        local resolved, combined = pcall(title)

        if resolved and type(combined) == "number" then
            local text = componentText(combined)

            if text ~= nil then
                local digits = string.match(text, "RuneScape%s*(%d+)")

                if digits ~= nil then
                    local parsed = tonumber(digits)

                    if parsed ~= nil then
                        return math.floor(parsed)
                    end
                end
            end
        end
    end

    return 0
end

local function weight()
    local ok, value = pcall(function()
        return Player.GetWeight()
    end)

    if not ok or type(value) ~= "number" then
        return 0
    end

    return math.floor(value * TENTHS + 0.5) / TENTHS
end

function M.read()
    local hp = varValue(id.VarPlayer.LIFEPOINTS)
    local prayer = math.floor(varValue(id.VarPlayer.PRAYER_POINTS) / TENTHS)
    local summoning = math.floor(varValue(id.VarPlayer.LORE_POINTS) / TENTHS)

    return {
        hp = hp,
        hpMax = math.max(hp, level(SkillType.HITPOINTS) * LIFE_POINTS_PER_LEVEL),
        prayer = prayer,
        prayerMax = math.max(prayer, level(SkillType.PRAYER) * POINTS_PER_LEVEL),
        summoning = summoning,
        summoningMax = math.max(summoning, level(SkillType.SUMMONING) * POINTS_PER_LEVEL),
        world = world(),
        weight = weight(),
    }
end

function M.toStats(current)
    return {
        current.hp,
        current.hpMax,
        current.prayer,
        current.prayerMax,
        current.summoning,
        current.summoningMax,
        current.world,
        current.weight,
    }
end

return M
