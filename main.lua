local flags = require("core/flags")

local AVAILABLE = {
    { name = "session", module = require("modules/session") },
    { name = "mode", module = require("modules/mode") },
    { name = "window", module = require("modules/window") },
    { name = "vitals", module = require("modules/vitals") },
    { name = "items", module = require("modules/items") },
    { name = "location", module = require("modules/location") },
    { name = "skills", module = require("modules/skills") },
    { name = "quests", module = require("modules/quests") },
    { name = "target", module = require("modules/target") },
    { name = "kills", module = require("modules/kills") },
    { name = "drops", module = require("modules/drops") },
    { name = "bank", module = require("modules/bank") },
}

local LOGIC_ID = "groupIronman:logic"

local MODULES = {}

for _, entry in ipairs(AVAILABLE) do
    if flags.modules[entry.name] == true then
        MODULES[#MODULES + 1] = entry.module
    end
end

local function guard(fn, arg)
    if fn ~= nil then
        pcall(fn, arg)
    end
end

local function onLogic(event)
    for _, module in ipairs(MODULES) do
        guard(module.tick, event.logicTick)
    end
end

PluginShutdown = function()
    Event.Logic.Unsubscribe(LOGIC_ID)

    for i = #MODULES, 1, -1 do
        local module = MODULES[i]
        guard(module.close or module.shutdown)
    end
end

for _, module in ipairs(MODULES) do
    guard(module.init)
end

Event.Logic.Subscribe(LOGIC_ID, onLogic)

