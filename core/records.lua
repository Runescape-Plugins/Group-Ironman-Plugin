local M = {}

function M.isEmpty(record)
    for _ in pairs(record) do
        return false
    end

    return true
end

function M.totals(slots)
    local out = {}
    local i = 1

    while i + 1 <= #slots do
        local objID = slots[i]

        if objID > 0 then
            out[objID] = (out[objID] or 0) + slots[i + 1]
        end

        i = i + 2
    end

    return out
end

function M.deltas(before, after)
    local out = {}

    for objID, count in pairs(after) do
        if before[objID] ~= count then
            out[#out + 1] = objID
            out[#out + 1] = count
        end
    end

    for objID in pairs(before) do
        if after[objID] == nil then
            out[#out + 1] = objID
            out[#out + 1] = 0
        end
    end

    return out
end

return M
