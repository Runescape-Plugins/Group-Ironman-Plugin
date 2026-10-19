local M = {}

function M.quote(value)
    local out = ""

    for i = 1, #value do
        local character = string.sub(value, i, i)
        local code = string.byte(character)

        if character == "\"" then
            out = out .. "\\\""
        elseif code == 92 then
            out = out .. "\\\\"
        elseif code < 32 then
            out = out .. string.format("\\u%04x", code)
        else
            out = out .. character
        end
    end

    return "\"" .. out .. "\""
end

function M.bool(value)
    if value then
        return "true"
    end
    return "false"
end

function M.numbers(values)
    return "[" .. table.concat(values, ",") .. "]"
end

function M.object(fields)
    return "{" .. table.concat(fields, ",") .. "}"
end

function M.field(name, value)
    return "\"" .. name .. "\":" .. value
end

return M
