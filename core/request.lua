local M = {}

function M.slot()
    local current

    local function cancel()
        local request = current
        current = nil

        if request ~= nil and not request.finished then
            pcall(function()
                request:Cancel()
            end)
        end
    end

    return {
        busy = function()
            return current ~= nil
        end,
        hold = function(request)
            current = request
        end,
        release = function()
            current = nil
        end,
        cancel = cancel,
    }
end

return M
