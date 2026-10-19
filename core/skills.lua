local M = {}

local SKILLS = {
    { id = "attack", skill = SkillType.ATTACK },
    { id = "defence", skill = SkillType.DEFENCE },
    { id = "strength", skill = SkillType.STRENGTH },
    { id = "constitution", skill = SkillType.HITPOINTS },
    { id = "ranged", skill = SkillType.RANGED },
    { id = "prayer", skill = SkillType.PRAYER },
    { id = "magic", skill = SkillType.MAGIC },
    { id = "cooking", skill = SkillType.COOKING },
    { id = "woodcutting", skill = SkillType.WOODCUTTING },
    { id = "fletching", skill = SkillType.FLETCHING },
    { id = "fishing", skill = SkillType.FISHING },
    { id = "firemaking", skill = SkillType.FIREMAKING },
    { id = "crafting", skill = SkillType.CRAFTING },
    { id = "smithing", skill = SkillType.SMITHING },
    { id = "mining", skill = SkillType.MINING },
    { id = "herblore", skill = SkillType.HERBLORE },
    { id = "agility", skill = SkillType.AGILITY },
    { id = "thieving", skill = SkillType.THIEVING },
    { id = "slayer", skill = SkillType.SLAYER },
    { id = "farming", skill = SkillType.FARMING },
    { id = "runecrafting", skill = SkillType.RUNECRAFTING },
    { id = "hunter", skill = SkillType.HUNTER },
    { id = "construction", skill = SkillType.CONSTRUCTION },
    { id = "summoning", skill = SkillType.SUMMONING },
    { id = "dungeoneering", skill = SkillType.DUNGEONEERING },
    { id = "divination", skill = SkillType.DIVINATION },
    { id = "invention", skill = SkillType.INVENTION },
    { id = "archaeology", skill = SkillType.ARCHAEOLOGY },
    { id = "necromancy", skill = SkillType.NECROMANCY },
}

local function number(reader)
    local ok, value = pcall(reader)

    if not ok or type(value) ~= "number" then
        return nil
    end

    return math.max(0, math.floor(value))
end

function M.idFor(skill)
    for _, entry in ipairs(SKILLS) do
        if entry.skill == skill then
            return entry.id
        end
    end

    return nil
end

function M.snapshot(only)
    local parts = {}

    for _, entry in ipairs(SKILLS) do
        if only == nil or only[entry.id] == true then
            local xp = number(function()
                return Player.GetXPUncapped(entry.skill)
            end)

            local level = number(function()
                return Player.GetLevelGameplay(entry.skill)
            end)

            if xp ~= nil and level ~= nil then
                parts[#parts + 1] = "\"" .. entry.id .. "\":{\"xp\":" .. tostring(xp)
                    .. ",\"level\":" .. tostring(level) .. "}"
            end
        end
    end

    if #parts == 0 then
        return nil
    end

    return "{" .. table.concat(parts, ",") .. "}"
end

return M
