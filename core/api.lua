local M = {}

local isGroupIronman = require("core/account").isGroupIronman
local json = require("core/json")

local SHARED_MEMBER = "@SHARED"
local ROSTER_FROM_TIME = "2999"

local function pathTo(group, endpoint)
    return "/api/group/" .. group .. "/" .. endpoint
end

local function describe(request)
    local status = request.responseCode

    if request.cancelled then
        return { ok = false, status = status, message = "cancelled" }
    end

    if request.timedOut then
        return { ok = false, status = status, message = "the server did not answer in time" }
    end

    if status == 401 or status == 403 then
        return { ok = false, status = status, message = "that group name and token were rejected" }
    end

    if status == 404 then
        return { ok = false, status = status, message = "no group by that name" }
    end

    if status ~= nil and status >= 500 then
        return { ok = false, status = status, message = "the server is having trouble, try again shortly" }
    end

    if not request.successful or status == nil or status < 200 or status >= 300 then
        local detail = request.errorInfo
        if detail == nil or detail == "" then
            detail = "could not reach the server"
        end
        return { ok = false, status = status, message = detail }
    end

    return { ok = true, status = status, message = "ok" }
end

function M.allowed()
    return Plugin.HasPermission(PluginPermissions.httpAccess)
end

local function open(path, done)
    local ok, made = pcall(function()
        return HTTPRequest.new(Plugin.urls.api, path)
    end)

    if not ok then
        local reason = string.gsub(tostring(made), "^%[string \"[^\"]*\"%]:%d+:%s*", "")
        done({ ok = false, status = nil, message = reason })
        return nil
    end

    return made
end

local function call(credentials, endpoint, body, done, read)
    local path = pathTo(credentials.group, endpoint)
    local request = open(path, done)

    if request == nil then
        return nil
    end

    request:AddHeader("Authorization", credentials.token)

    if body ~= nil then
        request:AddHeader("Content-Type", "application/json")
    end

    local function finish()
        local result = describe(request)

        if not result.ok then
            local verb = "GET"
            if body ~= nil then
                verb = "POST"
            end
        end

        if read ~= nil then
            read(request, result)
            return
        end

        done(result)
    end

    if body == nil then
        request:Get(finish, finish)
    else
        request:Post(body, finish, finish)
    end

    return request
end

local function forMember(member, fields)
    local all = { json.field("name", json.quote(member)) }

    for _, entry in ipairs(fields) do
        all[#all + 1] = entry
    end

    return json.object(all)
end

local function memberNames(body)
    local names = {}

    if body == nil then
        return names
    end

    for name in string.gmatch(body, "{\"name\":\"(.-)\"") do
        if name ~= SHARED_MEMBER then
            names[#names + 1] = name
        end
    end

    return names
end

local function roster(credentials, lean, done)
    local endpoint = "get-group-data"
    if lean then
        endpoint = endpoint .. "?from_time=" .. ROSTER_FROM_TIME
    end

    local chained

    local function plain(why)
        chained = roster(credentials, false, done)
    end

    local made = call(credentials, endpoint, nil, function(result)
        if lean then
            plain("could not be built")
            return
        end
        done(result, {})
    end, function(request, result)
        if result.ok then
            done(result, memberNames(request.data))
            return
        end

        if lean and (result.status == 400 or result.status == 404) then
            plain("was rejected")
            return
        end

        done(result, {})
    end)

    return made or chained
end

function M.members(credentials, done)
    return roster(credentials, true, done)
end

function M.verify(credentials, done)
    if not isGroupIronman() then
        done({ ok = false, status = nil, message = "this account is not a group ironman" })
        return nil
    end

    return call(credentials, "am-i-logged-in", nil, done)
end

function M.setMemberOnline(credentials, member, online, inLobby, done)
    return call(
        credentials,
        "set-member-online",
        forMember(member, {
            json.field("online", json.bool(online)),
            json.field("in_lobby", json.bool(inLobby)),
        }),
        done
    )
end

function M.updateStats(credentials, member, stats, done)
    return call(
        credentials,
        "update-group-member",
        forMember(member, { json.field("stats", json.numbers(stats)) }),
        done
    )
end

function M.updateItems(credentials, member, inventory, equipment, pouch, isBaseline, done)
    local fields = {}

    if inventory ~= nil then
        fields[#fields + 1] = json.field("inventory", json.numbers(inventory))
    end

    if equipment ~= nil then
        fields[#fields + 1] = json.field("equipment", json.numbers(equipment))
    end

    if pouch ~= nil then
        fields[#fields + 1] = json.field(
            "inventories",
            json.object({ json.field("money_pouch", json.numbers(pouch)) })
        )
    end

    if #fields == 0 then
        done({ ok = true, status = nil, message = "nothing to send" })
        return nil
    end

    if isBaseline then
        fields[#fields + 1] = json.field("baseline", json.bool(true))
    end

    return call(credentials, "update-group-member", forMember(member, fields), done)
end

function M.updateSkills(credentials, member, skills, isBaseline, done)
    local fields = { json.field("skills", skills) }

    if isBaseline then
        fields[#fields + 1] = json.field("achievements", json.bool(false))
        fields[#fields + 1] = json.field("baseline", json.bool(true))
    end

    return call(credentials, "update-group-member", forMember(member, fields), done)
end

local function bound(entry, name)
    local digits = string.match(entry, "\"" .. name .. "\":%s*(%d+)")

    if digits == nil then
        return 0
    end

    return tonumber(digits) or 0
end

local function parseWindows(body)
    local windows = {}
    local text = string.match(body, "\"quantities\":%s*%[(.-)%]")

    if text == nil then
        return windows
    end

    for entry in string.gmatch(text, "{(.-)}") do
        local digits = string.match(entry, "\"item_id\":%s*(%d+)")

        if digits ~= nil then
            local objID = tonumber(digits)

            if objID ~= nil then
                windows[objID] = {
                    min = bound(entry, "min"),
                    max = bound(entry, "max"),
                }
            end
        end
    end

    return windows
end

local function parseRules(body)
    if body == nil then
        return nil
    end

    local thresholdText = string.match(body, "\"threshold\":%s*(%d+)")
    local itemsText = string.match(body, "\"items\":%s*%[(.-)%]")
    local items = {}

    if itemsText ~= nil then
        for digits in string.gmatch(itemsText, "(%d+)") do
            local objID = tonumber(digits)

            if objID ~= nil then
                items[objID] = true
            end
        end
    end

    local threshold = 0
    if thresholdText ~= nil then
        threshold = tonumber(thresholdText) or 0
    end

    return {
        threshold = threshold,
        items = items,
        windows = parseWindows(body),
    }
end

local function wasRecorded(body)
    if body == nil then
        return false
    end

    return string.match(body, "\"recorded\":%s*(%a+)") == "true"
end

function M.dropRules(credentials, done)
    return call(credentials, "drop-rules", nil, function(result)
        done(result, nil)
    end, function(request, result)
        if result.ok then
            done(result, parseRules(request.data))
        else
            done(result, nil)
        end
    end)
end

function M.reportDrop(credentials, member, objID, quantity, name, worth, source, done)
    local fields = {
        json.field("item_id", tostring(objID)),
        json.field("quantity", tostring(quantity)),
        json.field("item_name", json.quote(name)),
        json.field("value", tostring(worth)),
    }

    if source ~= nil then
        fields[#fields + 1] = json.field("source", json.quote(source))
    end

    return call(credentials, "report-drop", forMember(member, fields), function(result)
        done(result, false)
    end, function(request, result)
        done(result, result.ok and wasRecorded(request.data))
    end)
end

function M.reportKills(credentials, member, kills, done)
    if #kills == 0 then
        done({ ok = true, status = nil, message = "nothing to send" })
        return nil
    end

    local entries = {}

    for _, entry in ipairs(kills) do
        entries[#entries + 1] = json.object({
            json.field("npc", json.quote(entry.npc)),
            json.field("kills", tostring(entry.kills)),
        })
    end

    return call(
        credentials,
        "report-kills",
        forMember(member, { json.field("kills", "[" .. table.concat(entries, ",") .. "]") }),
        done
    )
end

function M.setTarget(credentials, member, target, hp, percent, done)
    local fields = {}

    if target ~= nil then
        fields[#fields + 1] = json.field("target", json.quote(target))

        if hp >= 0 then
            fields[#fields + 1] = json.field("hp", tostring(hp))
        end

        if percent >= 0 then
            fields[#fields + 1] = json.field("percent", tostring(percent))
        end
    end

    return call(credentials, "set-target", forMember(member, fields), done)
end

function M.updateInventories(credentials, member, pushes, done)
    local fields = {}
    local changes = {}

    for _, push in ipairs(pushes) do
        if push.full then
            fields[#fields + 1] = json.field(push.field, json.numbers(push.pairs))
        else
            changes[#changes + 1] = json.field(push.field, json.numbers(push.pairs))
        end
    end

    if #changes > 0 then
        fields[#fields + 1] = json.field("inventory_changes", json.object(changes))
    end

    if #fields == 0 then
        done({ ok = true, status = nil, message = "nothing to send" })
        return nil
    end

    return call(credentials, "update-group-member", forMember(member, fields), done)
end

function M.questEntry(questID, state)
    return json.object({
        json.field("quest_id", tostring(questID)),
        json.field("state", json.quote(state)),
    })
end

function M.updateQuests(credentials, member, quests, isBaseline, done)
    if #quests == 0 then
        done({ ok = true, status = nil, message = "nothing to send" })
        return nil
    end

    local fields = { json.field("quests", "[" .. table.concat(quests, ",") .. "]") }

    if isBaseline then
        fields[#fields + 1] = json.field("full", json.bool(true))
        fields[#fields + 1] = json.field("achievements", json.bool(false))
    end

    return call(credentials, "update-member-quests", forMember(member, fields), done)
end

function M.playerMoved(credentials, member, x, z, level, done)
    return call(
        credentials,
        "player-moved",
        forMember(member, { json.field("coordinates", json.numbers({ x, z, level })) }),
        done
    )
end

function M.syncGroupMode(credentials, mode, done)
    return call(
        credentials,
        "sync-group-mode",
        json.object({ json.field("mode", json.quote(mode)) }),
        done
    )
end

function M.setLocationSharing(credentials, member, shared, done)
    return call(
        credentials,
        "set-location-sharing",
        forMember(member, { json.field("shared", json.bool(shared)) }),
        done
    )
end

return M
