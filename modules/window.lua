local M = {}

local api = require("core/api")
local slot = require("core/request").slot
local isGroupIronman = require("core/account").isGroupIronman
local roster = require("core/roster")
local session = require("modules/session")
local settings = require("core/settings")

local STATE_ID = "groupIronman:window"
local LAYER_ID = "groupIronman:window:layer"

local TICKS_PER_SECOND = 50
local CHECK_TIMEOUT_TICKS = TICKS_PER_SECOND * 15

local PADDING = 8
local FIELD_WIDTH = -(PADDING * 2)
local FIELD_ANCHOR = 1
local FIELD_GAP = 10
local MAX_GROUP_NAME = 50
local BUTTON_WIDTH = 160
local LIST_ENTRY_HEIGHT = 22
local FANCY_BUTTON_HEIGHT = 27
local NOTICE_TEXT = 48
local NOTICE_GAP = 8
local NOTICE_SPINNER = 56
local ROW_BUTTON_HEIGHT = 24
local ROW_BUTTON_GAP = 8
local ROW_BUTTON_MIN = 60
local FALLBACK_PANEL_WIDTH = 220

local TOKEN_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
local TOKEN_HINT = "Your token should look like 550e8400-e29b-41d4-a716-446655440000"
local NOT_IN_GROUP = "This account is not in the group"

local view
local parentComponent
local groupField
local tokenField
local doneButton
local statusLine

local groupText = ""
local tokenText = ""
local waited = 0
local attemptID = 0
local check = slot()
local mounting = false
local stage = "form"
local failure = ""
local verified
local lastAttempt

local render
local attempt

local function trim(value)
    if value == nil then
        return ""
    end

    local trimmed = string.gsub(value, "^%s*(.-)%s*$", "%1")
    return trimmed
end

local function validToken(value)
    return string.match(value, TOKEN_PATTERN) ~= nil
end

local function canSubmit()
    local group = trim(groupText)
    return group ~= "" and #group <= MAX_GROUP_NAME and validToken(trim(tokenText))
end

local function say(message)
    if statusLine ~= nil then
        statusLine.content = message
    end
end

local function refreshDone(busy)
    if doneButton ~= nil then
        doneButton:SetDisabled(busy or not canSubmit())
    end
end

local function fieldText(field, captured)
    if captured ~= "" then
        return captured
    end

    if field == nil then
        return ""
    end

    local ok, text = pcall(function()
        return field:GetText()
    end)

    if not ok or type(text) ~= "string" then
        return ""
    end

    return text
end

local function panelWidth(panel)
    local ok, value = pcall(function()
        return panel.root.width
    end)

    if not ok or type(value) ~= "number" or value <= 0 then
        return FALLBACK_PANEL_WIDTH
    end

    return value
end

local function stopWaitingToMount()
    mounting = false
end

local function teardown()
    local current = view

    view = nil
    groupField = nil
    tokenField = nil
    doneButton = nil
    statusLine = nil

    if current ~= nil and current.root ~= nil then
        pcall(function()
            current:Destroy()
        end)
    end
end

local function fail(message)
    failure = message
    stage = "error"
    render()
end

local function back()
    check.cancel()
    attemptID = attemptID + 1
    waited = 0
    stage = "form"
    render()
end

local function retry()
    if lastAttempt == nil then
        back()
        return
    end

    attempt(lastAttempt)
end

local function submit()
    if check.busy() then
        return
    end

    local group = trim(fieldText(groupField, groupText))
    local token = trim(fieldText(tokenField, tokenText))

    if group == "" then
        say("Enter your group name.")
        return
    end

    if token == "" then
        say("Enter your group token.")
        return
    end

    if not validToken(token) then
        say(TOKEN_HINT)
        return
    end

    attempt({ group = group, token = token })
end

local function pushLocationSharing(shared)
    local ready = session.current()
    if ready == nil then
        return
    end

    api.setLocationSharing(ready.who, ready.name, shared, function() end)
end

local function loadRoster(who)
    roster.clear()
    roster.load(who, function(ok)
        session.rosterChanged()

        if ok then
            pushLocationSharing(settings.sharesLocation())
            render()
        end
    end)
end

local function signOut()
    roster.clear()
    session.setCredentials(nil)
    session.rosterChanged()
    check.cancel()

    verified = nil
    lastAttempt = nil
    groupText = ""
    tokenText = ""
    failure = ""
    stage = "form"

    settings.forgetCredentials()
    render()
end

attempt = function(credentials)
    if check.busy() then
        return
    end

    attemptID = attemptID + 1
    local thisAttempt = attemptID

    waited = 0
    lastAttempt = credentials
    stage = "checking"
    render()

    check.hold(api.verify(credentials, function(result)
        if thisAttempt ~= attemptID then
            return
        end

        check.release()
        waited = 0

        if not result.ok then
            fail(result.message)
            return
        end

        verified = credentials
        session.setCredentials(credentials)
        settings.saveCredentials(credentials)
        stage = "form"
        loadRoster(credentials)
        render()
    end))

    if not check.busy() and stage == "checking" then
        fail("Could not reach the server.")
    end
end

local function centredText(panel, text, height, lines, marginTop)
    panel:AddText({
        text = text,
        x = PADDING,
        height = height,
        maxLines = lines,
        marginTop = marginTop,
        alignHorizontal = ui.AlignMode.CENTRE,
        width = FIELD_WIDTH,
        widthAnchor = FIELD_ANCHOR,
    })
end

local function buildNotice(panel, sprite, icon, message)
    local block = icon + NOTICE_GAP + NOTICE_TEXT

    panel:AddSprite(sprite, {
        width = icon,
        height = icon,
        x = -(icon / 2),
        xAnchor = 0.5,
        y = -(block / 2),
        yAnchor = 0.5,
    })

    panel:AddText({
        text = message,
        x = PADDING,
        y = -(block / 2) + icon + NOTICE_GAP,
        yAnchor = 0.5,
        height = NOTICE_TEXT,
        maxLines = 3,
        alignHorizontal = ui.AlignMode.CENTRE,
        alignVertical = ui.AlignMode.CENTRE,
        width = FIELD_WIDTH,
        widthAnchor = FIELD_ANCHOR,
    })
end

local function buildChecking(panel)
    local block = NOTICE_SPINNER + NOTICE_GAP + NOTICE_TEXT

    panel:AddSpinner({
        size = NOTICE_SPINNER,
        x = -(NOTICE_SPINNER / 2),
        xAnchor = 0.5,
        y = -(block / 2),
        yAnchor = 0.5,
    })

    panel:AddText({
        text = "Authenticating...",
        x = PADDING,
        y = -(block / 2) + NOTICE_SPINNER + NOTICE_GAP,
        yAnchor = 0.5,
        height = NOTICE_TEXT,
        maxLines = 2,
        alignHorizontal = ui.AlignMode.CENTRE,
        alignVertical = ui.AlignMode.CENTRE,
        width = FIELD_WIDTH,
        widthAnchor = FIELD_ANCHOR,
    })
end

local function buildError(panel)
    local icon = 52
    local block = icon + NOTICE_GAP + NOTICE_TEXT + NOTICE_GAP + ROW_BUTTON_HEIGHT
    local top = -(block / 2)

    panel:AddSprite(id.Sprite.SEPT16_ICON_EMPTY_WARNING_52PX, {
        width = icon,
        height = icon,
        x = -(icon / 2),
        xAnchor = 0.5,
        y = top,
        yAnchor = 0.5,
    })

    local message = failure
    if message == "" then
        message = "Could not sign in."
    end

    panel:AddText({
        text = message,
        x = PADDING,
        y = top + icon + NOTICE_GAP,
        yAnchor = 0.5,
        height = NOTICE_TEXT,
        maxLines = 3,
        alignHorizontal = ui.AlignMode.CENTRE,
        alignVertical = ui.AlignMode.CENTRE,
        width = FIELD_WIDTH,
        widthAnchor = FIELD_ANCHOR,
    })

    local buttonsY = top + icon + NOTICE_GAP + NOTICE_TEXT + NOTICE_GAP
    local width = math.max(
        ROW_BUTTON_MIN,
        math.floor((panelWidth(panel) - PADDING * 2 - ROW_BUTTON_GAP) / 2)
    )

    panel:AddSimpleButton("Back", back, {
        width = width,
        height = ROW_BUTTON_HEIGHT,
        x = -(width + ROW_BUTTON_GAP / 2),
        xAnchor = 0.5,
        y = buttonsY,
        yAnchor = 0.5,
    })

    panel:AddSimpleButton("Try again", retry, {
        width = width,
        height = ROW_BUTTON_HEIGHT,
        x = ROW_BUTTON_GAP / 2,
        xAnchor = 0.5,
        y = buttonsY,
        yAnchor = 0.5,
    })
end

local function buildNotInGroup(panel, group)
    local icon = 38

    panel:AddTitle({
        text = "Group Tracking: " .. group,
        font = id.Font.CINZEL_15PT_BOLD,
        height = 24,
        maxLines = 1,
        alignHorizontal = ui.AlignMode.CENTRE,
        x = PADDING,
        width = FIELD_WIDTH,
        widthAnchor = FIELD_ANCHOR,
    })

    panel:AddSprite(id.Sprite.SEPT16_ICON_EMPTY_WARNING_52PX, {
        width = icon,
        height = icon,
        x = -(icon / 2),
        xAnchor = 0.5,
        marginTop = -6,
    })

    centredText(panel, NOT_IN_GROUP, 18, 1, -4)

    local names = roster.known()
    local entries = names
    if #names == 0 then
        entries = { "none loaded" }
    end

    panel:AddList({
        entries = entries,
        entryHeight = LIST_ENTRY_HEIGHT,
        height = math.max(1, #names) * LIST_ENTRY_HEIGHT + 4,
        marginTop = 4,
        disabled = true,
        x = PADDING,
        width = FIELD_WIDTH,
        widthAnchor = FIELD_ANCHOR,
    })

    panel:AddFancyButton("Log out", signOut, {
        variant = "negative",
        marginTop = 8,
        width = BUTTON_WIDTH,
        x = -(BUTTON_WIDTH / 2),
        xAnchor = 0.5,
    })

    panel:SetScrollable(true)
end

local function buildSignIn(panel)
    panel:AddTitle({
        text = "SIGN IN",
        font = id.Font.CINZEL_18PT_BOLD,
        height = 30,
        maxLines = 1,
        alignHorizontal = ui.AlignMode.CENTRE,
        x = PADDING,
        width = FIELD_WIDTH,
        widthAnchor = FIELD_ANCHOR,
    })

    panel:AddText({
        text = "Enter your group name and token.",
        height = 16,
        maxLines = 1,
        alignHorizontal = ui.AlignMode.CENTRE,
        x = PADDING,
        width = FIELD_WIDTH,
        widthAnchor = FIELD_ANCHOR,
    })

    groupField = panel:AddTextField({
        placeholder = "Group name",
        text = groupText,
        maxLength = 64,
        onChange = function(_field, _reason, content)
            groupText = content
            refreshDone(check.busy())
        end,
        onSubmit = submit,
        marginTop = FIELD_GAP,
        width = FIELD_WIDTH,
        widthAnchor = FIELD_ANCHOR,
    })

    tokenField = panel:AddTextField({
        placeholder = "Group token",
        text = tokenText,
        maxLength = 128,
        onChange = function(_field, _reason, content)
            tokenText = content

            local token = trim(content)
            if token ~= "" and not validToken(token) then
                say(TOKEN_HINT)
            else
                say("")
            end

            refreshDone(check.busy())
        end,
        onSubmit = submit,
        marginTop = FIELD_GAP,
        width = FIELD_WIDTH,
        widthAnchor = FIELD_ANCHOR,
    })

    doneButton = panel:AddFancyButton("Done", submit, {
        variant = "positive",
        disabled = true,
        marginTop = FIELD_GAP,
        width = BUTTON_WIDTH,
        x = -(BUTTON_WIDTH / 2),
        xAnchor = 0.5,
    })

    statusLine = panel:AddText({
        text = "",
        height = 54,
        maxLines = 3,
        alignHorizontal = ui.AlignMode.CENTRE,
        x = PADDING,
        width = FIELD_WIDTH,
        widthAnchor = FIELD_ANCHOR,
    })
end

local TOGGLES = {
    {
        key = "location",
        label = "Share my location",
        tooltip = "Sends your position to the group map while you are logged in.",
        read = function()
            return settings.sharesLocation()
        end,
        write = function(on)
            settings.setSharesLocation(on)
            pushLocationSharing(on)
        end,
    },
}

local function buildSettings(panel, current)
    panel:AddTitle({
        text = "Group: " .. current.group,
        font = id.Font.CINZEL_15PT_BOLD,
        height = 24,
        maxLines = 1,
        alignHorizontal = ui.AlignMode.CENTRE,
        x = PADDING,
        width = FIELD_WIDTH,
        widthAnchor = FIELD_ANCHOR,
    })

    for _, toggle in ipairs(TOGGLES) do
        panel:AddCheckboxButton({
            {
                text = toggle.label,
                value = toggle.key,
                selected = toggle.read(),
                tooltip = toggle.tooltip,
            },
        }, {
            marginTop = 4,
            x = PADDING,
            width = FIELD_WIDTH,
            widthAnchor = FIELD_ANCHOR,
            onChange = function(_control, _values, _value, selected)
                toggle.write(selected)
            end,
        })
    end

    panel:AddFancyButton("Sign out", signOut, {
        variant = "negative",
        width = BUTTON_WIDTH,
        x = -(BUTTON_WIDTH / 2),
        xAnchor = 0.5,
        y = -(FANCY_BUTTON_HEIGHT + PADDING),
        yAnchor = 1,
    })
end

local function build(parent)
    view = prettyui.SimpleView.new(parent, {
        width = 0,
        height = 0,
        widthAnchor = 1,
        heightAnchor = 1,
        layout = {
            startY = 4,
            paddingLeft = PADDING,
            paddingRight = PADDING,
            paddingBottom = PADDING,
            rowGap = 4,
        },
    })

    local panel = view

    if not api.allowed() then
        buildNotice(panel, id.Sprite.SEPT16_ICON_EMPTY_WARNING_52PX, 52, "This plugin needs network access.")
        return
    end

    if not isGroupIronman() then
        buildNotice(
            panel,
            id.Sprite.ACHIEVEMENT_ICON_IRONMAN_GROUP_50PX,
            50,
            "You need to be on a Group Ironman account to use this plugin."
        )
        return
    end

    if verified ~= nil then
        if roster.membership() == "stranger" then
            buildNotInGroup(panel, verified.group)
            return
        end

        buildSettings(panel, verified)
        return
    end

    if stage == "checking" then
        buildChecking(panel)
        return
    end

    if stage == "error" then
        buildError(panel)
        return
    end

    buildSignIn(panel)
end

render = function()
    local parent = parentComponent
    if parent == nil then
        return
    end

    teardown()

    local built, err = pcall(build, parent)
    if not built then
        teardown()
    end
end

local function onContentLayer(event)
    parentComponent = event.component
    teardown()
    mounting = true
end

local function onGameState(event)
    if event.newState ~= GameState.GAME then
        M.shutdown()
        return
    end

    if verified ~= nil then
        loadRoster(verified)
    end
end

function M.credentials()
    return verified
end

function M.init()
    Event.GameStateChanged.Subscribe(STATE_ID, onGameState)
    Event.ContentLayerReady.Subscribe(LAYER_ID, onContentLayer)

    local saved = settings.savedCredentials()
    if saved ~= nil then
        verified = saved
        session.setCredentials(saved)
        loadRoster(saved)
    end
end

function M.tick()
    if mounting then
        mounting = false
        render()
    end

    if not check.busy() then
        waited = 0
        return
    end

    waited = waited + 1
    if waited < CHECK_TIMEOUT_TICKS then
        return
    end

    attemptID = attemptID + 1
    check.cancel()
    waited = 0
    fail("The server did not answer.")
end

function M.shutdown()
    check.cancel()
    stopWaitingToMount()
    parentComponent = nil
    teardown()
end

function M.close()
    Event.GameStateChanged.Unsubscribe(STATE_ID)
    Event.ContentLayerReady.Unsubscribe(LAYER_ID)
    M.shutdown()
end

return M
