-- Status Efficiency: the settings panel.
--
-- Where the icon sits on a button, and which icon each indication uses.
--
-- The panel is drawn with plain frames, textures and text only, so it does not
-- depend on any of the game's widget templates. It appears in two places: in the
-- game's own Options window under AddOns, and in a small window of its own that
-- /se options opens (which also works when the game's Options window will not).

local _, ns = ...

local Icons = ns.Icons

local Options = {}
ns.Options = Options

local pcall, type, tostring, pairs = pcall, type, tostring, pairs
local floor = math.floor

local TITLE = "Status Efficiency"
local WIDTH, HEIGHT = 640, 506
local ROW_HEIGHT = 104
local SWATCH, STEP, PER_LINE = 30, 34, 11

local GRID = {
    { "TOPLEFT", "TOP", "TOPRIGHT" },
    { "LEFT", "CENTER", "RIGHT" },
    { "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
}

local POSITION_NAMES = {
    TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right",
    LEFT = "Left", CENTER = "Middle", RIGHT = "Right",
    BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom right",
}
Options.POSITION_NAMES = POSITION_NAMES

local views = {} -- every copy of the panel that has been built
Options.views = views

local shownState = "none" -- the indication the position preview is drawn with

--------------------------------------------------------------------------------
-- Small building blocks
--------------------------------------------------------------------------------

local function Shown(region, visible)
    if visible then
        region:Show()
    else
        region:Hide()
    end
end

local function Text(parent, font, text)
    local label = parent:CreateFontString(nil, "ARTWORK", font)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    if text then
        label:SetText(text)
    end
    return label
end

local function Tip(frame, text)
    frame:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(text)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
end

--- A square button that shows one icon, with a gold frame when it is the one in use.
local function Swatch(parent, size)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)

    local ring = button:CreateTexture(nil, "BACKGROUND")
    ring:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
    ring:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
    ring:SetColorTexture(1, 0.82, 0, 1)
    ring:Hide()

    local back = button:CreateTexture(nil, "BORDER")
    back:SetAllPoints(button)
    back:SetColorTexture(0.1, 0.1, 0.12, 1)

    local art = button:CreateTexture(nil, "ARTWORK")
    art:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    art:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)

    local glow = button:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints(button)
    glow:SetColorTexture(1, 1, 1, 0.2)

    button.ring, button.art = ring, art
    return button
end

local function TextButton(parent, width, height, text)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)

    local edge = button:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints(button)
    edge:SetColorTexture(0.45, 0.45, 0.5, 1)

    local back = button:CreateTexture(nil, "BORDER")
    back:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    back:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    back:SetColorTexture(0.16, 0.16, 0.2, 1)

    local glow = button:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints(button)
    glow:SetColorTexture(1, 1, 1, 0.15)

    local label = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("CENTER", button, "CENTER", 0, 0)
    label:SetText(text)
    button.label = label
    return button
end

local function Input(parent, width)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, 20)
    box:EnableMouse(true)
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlightSmall)
    box:SetTextInsets(5, 5, 0, 0)
    box:SetMaxLetters(200)

    local edge = box:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", box, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0.45, 0.45, 0.5, 1)

    local back = box:CreateTexture(nil, "BORDER")
    back:SetAllPoints(box)
    back:SetColorTexture(0.03, 0.03, 0.05, 1)
    return box
end

--------------------------------------------------------------------------------
-- Changing a setting
--------------------------------------------------------------------------------

function Options.RefreshAll()
    for i = 1, #views do
        views[i].Refresh()
    end
end

--- Runs a change, then redraws the buttons and every open copy of the panel.
local function Change(fn, state)
    fn()
    if state then
        shownState = state
    end
    ns.Relayout()
    ns.MarkDirty()
    Options.RefreshAll()
end

Options.Change = Change

--- The same, for clicks in the panel: a failure is reported, not thrown at the game.
local function Click(fn, state)
    ns.Guard(Change, fn, state)
end

local function ApplyOwnTexture(stateKey, box)
    local text = box:GetText() or ""
    if not text:find("%S") then
        -- Emptied: go back to the default if the indication was using its own texture.
        if Icons.Current(stateKey) == "custom" then
            Change(function()
                Icons.Set(stateKey, nil)
            end, stateKey)
        end
        box:ClearFocus()
        return
    end
    local texture = Icons.ParseCustom(text)
    if not texture then
        ns.Print("that is not a texture. Type a file ID such as 136243, or a path such as "
            .. "Interface\\Icons\\INV_Misc_QuestionMark.")
        return
    end
    box:ClearFocus()
    Change(function()
        Icons.SetCustom(stateKey, texture)
    end, stateKey)
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

--- Fills `host` with the controls and returns a view: { zones, swatches, inputs,
--- reset, Refresh }.
local function Build(host, withTitle)
    local view = { zones = {}, swatches = {}, inputs = {} }

    if withTitle then
        local title = Text(host, "GameFontNormalLarge", TITLE)
        title:SetPoint("TOPLEFT", host, "TOPLEFT", 16, -16)
    end

    local blurb = Text(host, "GameFontHighlightSmall",
        "A small icon on each action button shows whether casting that spell again would spread "
            .. "its status effect. Choose where the icon sits and what each indication looks like. "
            .. "Changes apply straight away.")
    blurb:SetPoint("TOPLEFT", host, "TOPLEFT", 16, withTitle and -42 or -18)
    blurb:SetWidth(370)

    -- Position: a pretend action button with nine spots to click.
    local where = Text(host, "GameFontNormal", "Icon position")
    where:SetPoint("TOPLEFT", host, "TOPLEFT", 420, -16)

    local preview = CreateFrame("Frame", nil, host)
    preview:SetSize(72, 72)
    preview:SetPoint("TOPLEFT", host, "TOPLEFT", 420, -36)

    local face = preview:CreateTexture(nil, "BACKGROUND")
    face:SetAllPoints(preview)
    face:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    for row = 1, 3 do
        for column = 1, 3 do
            local position = GRID[row][column]
            local zone = CreateFrame("Button", nil, preview)
            zone:SetSize(24, 24)
            zone:SetPoint("TOPLEFT", preview, "TOPLEFT", (column - 1) * 24, -(row - 1) * 24)

            local ghost = zone:CreateTexture(nil, "ARTWORK")
            ghost:SetSize(8, 8)
            ghost:SetPoint("CENTER", zone, "CENTER", 0, 0)
            ghost:SetColorTexture(1, 1, 1, 0.4)

            local art = zone:CreateTexture(nil, "OVERLAY")
            art:SetAllPoints(zone)

            local glow = zone:CreateTexture(nil, "HIGHLIGHT")
            glow:SetAllPoints(zone)
            glow:SetColorTexture(1, 1, 1, 0.25)

            zone.ghost, zone.art = ghost, art
            zone:SetScript("OnClick", function()
                Click(function()
                    ns.db.corner = position
                end)
            end)
            Tip(zone, POSITION_NAMES[position])
            view.zones[position] = zone
        end
    end

    local hint = Text(host, "GameFontHighlightSmall", "Click the spot on the button where the icon should sit.")
    hint:SetPoint("TOPLEFT", preview, "TOPRIGHT", 12, -6)
    hint:SetWidth(118)

    -- One block per indication: every icon on offer, plus a box for your own.
    local top = -128
    for index = 1, #Icons.STATES do
        local state = Icons.STATES[index]

        local name = Text(host, "GameFontNormal", state.title)
        name:SetPoint("TOPLEFT", host, "TOPLEFT", 16, top)
        local detail = Text(host, "GameFontHighlightSmall", state.detail)
        detail:SetPoint("LEFT", name, "RIGHT", 10, 0)

        local swatches = {}
        for i = 1, #Icons.CHOICES do
            local choice = Icons.CHOICES[i]
            local line = floor((i - 1) / PER_LINE)
            local column = (i - 1) - line * PER_LINE
            local swatch = Swatch(host, SWATCH)
            swatch:SetPoint("TOPLEFT", host, "TOPLEFT", 18 + column * STEP, top - 24 - line * STEP)
            swatch.art:SetTexture(choice.texture)
            swatch:SetScript("OnClick", function()
                Click(function()
                    Icons.Set(state.key, choice.key)
                end, state.key)
            end)
            Tip(swatch, choice.name)
            swatches[choice.key] = swatch
        end
        view.swatches[state.key] = swatches

        local own = Text(host, "GameFontHighlightSmall", "Or your own texture")
        own:SetPoint("TOPLEFT", host, "TOPLEFT", 410, top - 22)
        local ok, box = pcall(Input, host, 200)
        if ok and box then
            box:SetPoint("TOPLEFT", host, "TOPLEFT", 411, top - 40)
            box:SetScript("OnEnterPressed", function(self)
                ns.Guard(ApplyOwnTexture, state.key, self)
            end)
            box:SetScript("OnEscapePressed", function(self)
                self:ClearFocus()
                ns.Guard(view.Refresh)
            end)
            view.inputs[state.key] = box
            local help = Text(host, "GameFontDisableSmall", "A file ID or a path, then Enter.")
            help:SetPoint("TOPLEFT", host, "TOPLEFT", 410, top - 64)
        else
            own:SetText("Your own texture:\n/se icon " .. state.key .. " <file ID or path>")
        end

        top = top - ROW_HEIGHT
    end

    local reset = TextButton(host, 190, 22, "Reset position and icons")
    reset:SetPoint("TOPLEFT", host, "TOPLEFT", 16, top - 4)
    reset:SetScript("OnClick", function()
        Click(function()
            ns.db.corner = "TOPLEFT"
            Icons.ResetAll()
        end, "none")
    end)
    view.reset = reset

    function view.Refresh()
        local art = Icons.Texture(shownState)
        for position, zone in pairs(view.zones) do
            local chosen = ns.db.corner == position
            Shown(zone.art, chosen)
            Shown(zone.ghost, not chosen)
            if chosen then
                zone.art:SetTexture(art)
            end
        end
        for i = 1, #Icons.STATES do
            local key = Icons.STATES[i].key
            local current, custom = Icons.Current(key)
            for choiceKey, swatch in pairs(view.swatches[key]) do
                Shown(swatch.ring, choiceKey == current)
            end
            local box = view.inputs[key]
            if box and not box:HasFocus() then
                box:SetText(current == "custom" and tostring(custom) or "")
            end
        end
    end

    views[#views + 1] = view
    view.Refresh()
    return view
end

--------------------------------------------------------------------------------
-- A window of its own: /se options
--------------------------------------------------------------------------------

local WINDOW_NAME = "StatusEfficiencyOptions"
local window

local function BuildWindow()
    local frame = CreateFrame("Frame", WINDOW_NAME, UIParent)
    frame:Hide()
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    local edge = frame:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints(frame)
    edge:SetColorTexture(0.4, 0.4, 0.45, 1)

    local back = frame:CreateTexture(nil, "BORDER")
    back:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    back:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    back:SetColorTexture(0.06, 0.06, 0.08, 0.97)

    local bar = frame:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    bar:SetHeight(26)
    bar:SetColorTexture(0.16, 0.16, 0.2, 1)

    local caption = Text(frame, "GameFontNormal", TITLE)
    caption:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -7)

    local close = TextButton(frame, 22, 20, "X")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)
    Tip(close, "Close")

    local host = CreateFrame("Frame", nil, frame)
    host:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -28)
    host:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    local view = Build(host, false)
    frame:SetScript("OnShow", function()
        ns.Guard(view.Refresh)
    end)
    frame.view = view

    -- Lets the Escape key close it, like the game's own windows.
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = WINDOW_NAME
    end
    return frame
end

--- Opens the settings window, or closes it if it is open.
function Options.Toggle()
    if not window then
        local ok, frame = pcall(BuildWindow)
        if not ok or not frame then
            ns.Print("the settings window could not be built on this client. The same settings work as "
                .. "commands: /se corner and /se icon. (" .. tostring(frame) .. ")")
            return
        end
        window = frame
    end
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
end

function Options.Window()
    return window
end

--------------------------------------------------------------------------------
-- The game's own Options window: Options > AddOns > Status Efficiency
--------------------------------------------------------------------------------

local function Nothing() end

--- Adds the panel to the game's Options window. Safe to call more than once.
function Options.Register()
    if Options.canvas then
        return
    end
    local ok, problem = pcall(function()
        local canvas = CreateFrame("Frame")
        canvas:Hide()
        Options.canvas = canvas

        local view, tried
        canvas:SetScript("OnShow", function()
            if view then
                ns.Guard(view.Refresh)
            elseif not tried then
                tried = true -- one attempt: a half-built panel is not built over again
                local built, result = pcall(Build, canvas, true)
                if built then
                    view = result
                    canvas.view = view
                else
                    Options.problem = tostring(result)
                    ns.Print("the settings panel could not be drawn here. /se options opens it in a window "
                        .. "of its own. (" .. Options.problem .. ")")
                end
            end
        end)

        -- The Options window may call these on any panel it shows.
        canvas.OnCommit, canvas.OnDefault, canvas.OnRefresh = Nothing, Nothing, Nothing
        canvas.name = TITLE

        if type(Settings) == "table" and type(Settings.RegisterCanvasLayoutCategory) == "function" then
            local category = Settings.RegisterCanvasLayoutCategory(canvas, TITLE)
            if category and type(Settings.RegisterAddOnCategory) == "function" then
                Settings.RegisterAddOnCategory(category)
            end
            Options.category = category
            Options.registered = category ~= nil
        elseif type(InterfaceOptions_AddCategory) == "function" then
            InterfaceOptions_AddCategory(canvas) -- clients from before the Settings window
            Options.registered = true
        end
    end)
    if not ok then
        -- Not worth a chat message: /se options still works without it.
        Options.problem = tostring(problem)
    end
end
