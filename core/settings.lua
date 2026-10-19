local M = {}

local GROUP_KEY = "group.name"
local TOKEN_KEY = "group.token"
local SHARE_LOCATION_KEY = "share.location"

function M.savedCredentials()
    local group = PersistentDB:GetString(GROUP_KEY)
    local token = PersistentDB:GetString(TOKEN_KEY)

    if group == nil or token == nil or group == "" or token == "" then
        return nil
    end

    return { group = group, token = token }
end

function M.saveCredentials(credentials)
    PersistentDB:SetString(GROUP_KEY, credentials.group)
    PersistentDB:SetString(TOKEN_KEY, credentials.token)
end

function M.forgetCredentials()
    PersistentDB:Delete(GROUP_KEY)
    PersistentDB:Delete(TOKEN_KEY)
end

function M.sharesLocation()
    return PersistentDB:GetBool(SHARE_LOCATION_KEY) ~= false
end

function M.setSharesLocation(value)
    PersistentDB:SetBool(SHARE_LOCATION_KEY, value)
end

return M
