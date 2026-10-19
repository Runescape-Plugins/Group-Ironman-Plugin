local M = {}

local PLACEHOLDERS = {
    "tap to find target",
    "click to find target",
    "no target",
    "select a target",
}

local function component(combined)
    local found, proxy = pcall(function()
        return ui.Interfaces:GetComponent(combined)
    end)

    if not found or proxy == nil then
        return nil
    end

    return proxy
end

local function textOf(combined)
    local target = component(combined)

    if target == nil then
        return nil
    end

    local read, value = pcall(function()
        return target.text
    end)

    if read and type(value) == "string" then
        return value
    end

    local readContent, content = pcall(function()
        return target.content
    end)

    if readContent and type(content) == "string" then
        return content
    end

    return nil
end

local function numberOf(text)
    if text == nil then
        return -1
    end

    local digits = string.gsub(text, "[^%d]", "")

    if digits == "" then
        return -1
    end

    local value = tonumber(digits)

    if value == nil then
        return -1
    end

    return math.floor(value)
end

local function widthOf(combined)
    local target = component(combined)

    if target == nil then
        return -1
    end

    local read, width = pcall(function()
        return target.width
    end)

    if read and type(width) == "number" then
        return width
    end

    return -1
end

local function percentOf()
    local filled = widthOf(id.Component.TOPLEVEL_V2_TARGET_INFO__PROBAR_ACTUAL_HEALTH_LAYER)
    local whole = widthOf(id.Component.TOPLEVEL_V2_TARGET_INFO__TARGET_HEALTH_BAR_LAYER)

    if filled < 0 or whole <= 0 then
        return -1
    end

    return math.max(0, math.min(100, math.floor(filled * 100 / whole)))
end

function M.overlayVisible()
    local target = component(id.Component.TOPLEVEL_V2_TARGET_INFO__NAME)

    if target == nil then
        return nil
    end

    local read, value = pcall(function()
        return target.visibleGlobal
    end)

    if read and type(value) == "boolean" then
        return value
    end

    return nil
end

local function clean(value)
    local withoutTags = string.gsub(value, "<[^>]*>", "")
    local trimmed = string.gsub(withoutTags, "^%s*(.-)%s*$", "%1")
    return trimmed
end

local function isPlaceholder(name)
    local text = string.lower(name)

    for _, entry in ipairs(PLACEHOLDERS) do
        if text == entry then
            return true
        end
    end

    return false
end

function M.read()
    local raw = textOf(id.Component.TOPLEVEL_V2_TARGET_INFO__NAME)

    if raw == nil then
        return nil
    end

    local name = clean(raw)

    if name == "" or isPlaceholder(name) then
        return nil
    end

    return {
        name = name,
        hp = numberOf(textOf(id.Component.TOPLEVEL_V2_TARGET_INFO__ENTITY_HEALTH_LEFT)),
        percent = percentOf(),
    }
end

function M.sameAs(before, after)
    if before == nil or after == nil then
        return before == after
    end

    return before.name == after.name
        and before.hp == after.hp
        and before.percent == after.percent
end

return M
