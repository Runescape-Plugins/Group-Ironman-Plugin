local M = {}

local isGroupIronman = require("core/account").isGroupIronman
local roster = require("core/roster")

local inGame = false
local member = false
local eligible = false
local name
local who

local function capture()
    if not Player.IsAvailable() then
        return
    end

    local entity = Player.GetEntity()
    if entity == nil then
        return
    end

    inGame = true
    name = entity.displayName
    eligible = isGroupIronman()
    member = eligible and roster.isMember(name)
end

local function onGameState(event)
    inGame = event.newState == GameState.GAME

    if not inGame then
        name = nil
        member = false
        eligible = false
        return
    end

    capture()
end

local function onPlayerAdded()
    if name == nil then
        capture()
    end
end

function M.init()
    Event.GameStateChanged.Subscribe("groupIronman:session", onGameState)
    Event.PlayerEntityAdded.Subscribe("groupIronman:session:player", onPlayerAdded)
end

function M.tick()
    if name == nil then
        capture()
    end
end

function M.setCredentials(next)
    who = next
end

function M.rosterChanged()
    member = eligible and name ~= nil and roster.isMember(name)
end

function M.signedIn()
    return who
end

function M.current()
    if who == nil or not inGame or name == nil or not member then
        return nil
    end

    return { who = who, name = name }
end

function M.refusal()
    if who == nil then
        return "not signed in"
    end

    if not inGame or name == nil then
        return "the player is not loaded yet"
    end

    if not eligible then
        return "this account is not a group ironman"
    end

    if not roster.isLoaded() then
        return "the group members have not been read yet"
    end

    return name .. " is not a member of this group"
end

function M.shutdown()
    Event.GameStateChanged.Unsubscribe("groupIronman:session")
    Event.PlayerEntityAdded.Unsubscribe("groupIronman:session:player")

    inGame = false
    name = nil
    member = false
    eligible = false
end

return M
