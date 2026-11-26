-- Status Efficiency: the settings panel.
--
-- Two tabs. "Appearance" has the on/off switch, when the icons appear and on
-- which skills, where the icon sits on a button, how big it is and which icon
-- each result uses, with a life-size preview of all three. "Spells" has one row
-- per spell on the action bars.
--
-- Buttons, tick boxes and the size slider are the game's own where this client
-- has them and they pass a quick test. Where one is missing, fails its test, or
-- breaks while the panel is being built, the panel draws its own from plain
-- frames and textures instead, without being asked: a control of the game's
-- that lets it down costs the look and nothing else. (/se plain asks for the
-- plain drawing outright.) Everything else here is plain frames and textures to
-- begin with.
--
-- Nothing is taken on trust about the text either. A font this client lacks is
-- replaced by its nearest neighbour, and every label is measured once it is
-- made: where the game's font, or the player's own, is too wide for the room a
-- label has, the label is drawn smaller until it fits.
--
-- The panel appears in two places: in the game's Options window under AddOns,
-- and in a window of its own that /se options opens (which also works when the
-- game's Options window will not). The copy in the Options window is drawn
-- smaller if the page it is given is smaller than the panel.

local _, ns = ...

local Icons, Spells, Tracker = ns.Icons, ns.Spells, ns.Tracker

local Options = {}
ns.Options = Options

local pcall, type, tostring, tonumber, pairs, select = pcall, type, tostring, tonumber, pairs, select
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local concat = table.concat

local TITLE = "Status Efficiency"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local STANDARD_FONT = "Fonts\\FRIZQT__.TTF" -- the game's everyday typeface, for a client with no fonts to borrow

-- Sizes and places, in the panel's own units. A page is the part under the tabs.
local L = {
    width = 640,
    pageHeight = 514, -- as tall as fits the game's Options window
    bar = 28, -- the window's title bar
    canvasTop = 86, -- the heading and the tabs above a page in the Options window
    right = 624, -- nothing on a page goes further right than this

    headTop = -68, -- the headings "Preview", "Icon size": what is under them hangs off this
    tile = 30, -- an icon to pick
    tileStep = 34,
    blockTop = -200, -- the first result's heading
    blockPitch = 92,

    slotWidth = 88, -- the room each pretend button gets in the preview
    slotHeight = 64,
    slotPitch = 92,
    previewMin = 36, -- a pretend button is drawn life-size, within these
    previewMax = 60,

    rows = 14, -- spells shown at once
    rowHeight = 30,
    listTop = -58,
}

local GOLD = { 1, 0.82, 0 }
local WARN = { 1, 0.6, 0.2 }
local BAD = { 1, 0.35, 0.3 }

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

-- When the icons appear at all. `words` is how chat messages put it.
local APPEAR_CHOICES = {
    { key = "always", label = "Always", width = 54, words = "always", tip = "Always",
        body = "Whenever there is something to judge: a buff at any time, a debuff whenever there is an enemy to check." },
    { key = "target", label = "When targeting an enemy", width = 150, words = "when targeting an enemy",
        tip = "When targeting an enemy",
        body = "Only while you have an enemy targeted. Buff icons wait for one too." },
    { key = "combat", label = "When in combat", width = 104, words = "when in combat", tip = "When in combat",
        body = "Only during a fight. Out of combat your buttons stay bare." },
}
Options.APPEAR_CHOICES = APPEAR_CHOICES

-- And on which skills: every one, or only those that can be used right now.
local USABLE_CHOICES = {
    { key = "always", label = "On every skill", width = 92, words = "on every skill", tip = "On every skill",
        body = "Whether or not you can use the skill right now." },
    { key = "usable", label = "Only when the skill is usable", width = 172,
        words = "only on skills you can use right now", tip = "Only when the skill is usable",
        body = "Not while the game says the skill cannot be used: you are too close or too far, in the wrong "
            .. "stance and the like. Being short of rage, mana or energy does not hide the icon, and neither "
            .. "does a cooldown." },
}
Options.USABLE_CHOICES = USABLE_CHOICES

local views = {} -- every copy of the panel that has been built
Options.views = views

--------------------------------------------------------------------------------
-- What this client turned out to lack
--
-- The panel checks what it is given and helps itself, so that nobody has to
-- tell it that something of the game's is missing or misbehaves. What it found
-- is kept in `notes` and saved with the settings (as `panel`), where it can be
-- read afterwards without anyone having to describe what the panel looked like.
--------------------------------------------------------------------------------

local notes = {
    controls = {}, -- kind of control -> "game", or "own: " and why the game's was not used
    fonts = {}, -- font wanted -> the font used in its place
    tight = {}, -- label -> "width/room", for labels that fill their room or more
}
Options.notes = notes

local forcedPlain = false -- a build with the game's controls in it failed: this session draws its own
local unusable = {} -- kinds of the game's controls found wanting this session
local tightKept = 0

--- True when the panel is to draw every control itself.
local function Plain()
    return forcedPlain or ns.db.plain == true
end

Options.Plain = Plain

--- An error, short enough to keep.
local function Brief(problem)
    local text = tostring(problem):gsub("^.-StatusEfficiency[\\/]", "")
    return text:sub(1, 140)
end

--- Copies the notes into the saved settings.
local function SaveNotes()
    local saved = {
        version = ns.VERSION, build = ns.BuildKey(), plain = Plain(),
        rebuilt = notes.rebuilt, failed = notes.failed, page = notes.page, scale = notes.scale,
        controls = {}, fonts = {}, tight = {},
    }
    for _, name in pairs({ "controls", "fonts", "tight" }) do
        for key, value in pairs(notes[name]) do
            saved[name][key] = value
        end
    end
    ns.db.panel = saved
end

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

--- Calls object:method(...) if this client's widget has such a method, and says
--- whether it worked. For calls the panel can do without.
local function Try(object, method, ...)
    local fn = object[method]
    if type(fn) ~= "function" then
        return false
    end
    return pcall(fn, object, ...)
end

-- The fonts to try, nearest look first, when this client lacks one.
local FONT_SPARES = {
    GameFontHighlightHuge = { "GameFontNormalLarge", "GameFontHighlight", "GameFontNormal" },
    GameFontNormalLarge = { "GameFontNormal", "GameFontHighlight" },
    GameFontNormal = { "GameFontHighlight", "GameFontNormalSmall", "GameFontHighlightSmall" },
    GameFontHighlight = { "GameFontNormal", "GameFontHighlightSmall", "GameFontNormalSmall" },
    GameFontDisable = { "GameFontHighlight", "GameFontNormal", "GameFontDisableSmall" },
    GameFontNormalSmall = { "GameFontHighlightSmall", "GameFontNormal", "GameFontHighlight" },
    GameFontHighlightSmall = { "GameFontNormalSmall", "GameFontHighlight", "GameFontNormal" },
    GameFontDisableSmall = { "GameFontHighlightSmall", "GameFontNormalSmall", "GameFontDisable", "GameFontNormal" },
}
local FONT_HEIGHTS = { GameFontHighlightHuge = 20, GameFontNormalLarge = 16 } -- the rest: 10 when small, else 12

local fontNames = {} -- font wanted -> the font to use, or false when the client has none of them

--- The name of a font this client has: the one asked for, or the nearest to it.
local function FontName(font)
    local name = fontNames[font]
    if name == nil then
        name = false
        if type(_G[font]) == "table" then
            name = font
        else
            local spares = FONT_SPARES[font]
            for i = 1, spares and #spares or 0 do
                if type(_G[spares[i]]) == "table" then
                    name = spares[i]
                    break
                end
            end
            notes.fonts[font] = name or "none"
        end
        fontNames[font] = name
    end
    return name or nil
end

local function FontHeight(font)
    return FONT_HEIGHTS[font] or (font:find("Small", 1, true) and 10 or 12)
end

--- A label in a font, or in the nearest font this client has.
local function Label(parent, layer, font)
    local name = FontName(font)
    if name then
        return parent:CreateFontString(nil, layer, name)
    end
    -- Not one font to borrow: a bare label in the game's everyday typeface.
    local label = parent:CreateFontString(nil, layer)
    label:SetFont(STANDARD_FONT, FontHeight(font), "")
    return label
end

local function Text(parent, font, text)
    local label = Label(parent, "ARTWORK", font)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    if text then
        label:SetText(text)
    end
    return label
end

local function Colour(label, colour)
    label:SetTextColor(colour[1], colour[2], colour[3])
end

--------------------------------------------------------------------------------
-- Labels that fit
--
-- The panel is laid out for the game's standard font. Another language's font,
-- or one the player has swapped in, can be a good deal wider, and a label that
-- outgrows its room would run into its neighbour or out of its button. So each
-- label is measured, and drawn smaller when it has to be.
--------------------------------------------------------------------------------

local SMALLEST = 0.7 -- how far letters shrink before a label is cut short instead: smaller cannot be read
local TIGHT = 0.85 -- a label that fills this much of its room is worth a note
local WRAPPED = 0.85 -- how much of its lines a label that wraps can be counted on to fill
local TIGHT_KEPT = 24

local fitted = {} -- label -> the build it was made in, for every label that has been fitted
local build = 0 -- counts attempts at building a copy of the panel

--- A width the client reports for a label, or nil when it has none to give.
local function Measure(label, method)
    local ok, width = Try(label, method)
    width = ok and ns.PlainNumber(width) or nil
    if width and width > 0 then
        return width
    end
    return nil
end

--- Draws a label's letters at a scale. False on a client whose labels cannot be scaled.
local function Scale(label, scale)
    return (Try(label, "SetTextScale", scale))
end

local function LabelText(label)
    local ok, text = Try(label, "GetText")
    return ok and ns.PlainString(text) or nil
end

local function NoteTight(label, width, room)
    if width <= room * TIGHT then
        return
    end
    local text = LabelText(label)
    if not text or text == "" then
        return
    end
    text = text:sub(1, 40)
    if notes.tight[text] == nil then
        if tightKept >= TIGHT_KEPT then
            return
        end
        tightKept = tightKept + 1
    end
    notes.tight[text] = floor(width + 0.5) .. "/" .. floor(room + 0.5)
end

--- Makes a one-line label fit the room it has. Its letters are drawn smaller,
--- down to SMALLEST; a label too long even then is cut short. Returns the scale.
--- Fitting again with the same words and room costs nothing unless `again`.
local function Fit(label, room, again)
    local text = LabelText(label)
    if not again and label.fitScale and label.fitRoom == room and label.fitText == text and not label.fitLines then
        return label.fitScale
    end
    fitted[label] = fitted[label] or build
    label.fitRoom, label.fitText, label.fitLines = room, text, nil
    if label.fitCut then
        label.fitCut = nil
        Try(label, "SetWidth", 0) -- as wide as its words again
        Try(label, "SetWordWrap", true)
    end
    local scale = 1
    if room > 0 and Scale(label, 1) then
        local width = Measure(label, "GetUnboundedStringWidth") or Measure(label, "GetStringWidth")
        if width then
            if width > room then
                scale = max(SMALLEST, room / width)
                Scale(label, scale)
                if width * scale > room + 0.5 then
                    label.fitCut = true
                    Try(label, "SetWidth", room)
                    Try(label, "SetWordWrap", false)
                end
            end
            NoteTight(label, width, room)
        end
    end
    label.fitScale = scale
    return scale
end

--- The same for a label that wraps: at most `lines` lines of `width`.
local function FitLines(label, width, lines, again)
    local text = LabelText(label)
    if not again and label.fitScale and label.fitRoom == width and label.fitText == text and label.fitLines == lines then
        return label.fitScale
    end
    fitted[label] = fitted[label] or build
    label.fitRoom, label.fitText, label.fitLines = width, text, lines
    Try(label, "SetMaxLines", lines) -- whatever its letters do, it never runs into what is under it
    local scale = 1
    if Scale(label, 1) then
        local natural = Measure(label, "GetUnboundedStringWidth")
        local room = width * lines * WRAPPED
        if natural then
            if natural > room then
                scale = max(SMALLEST, room / natural)
                Scale(label, scale)
            end
            NoteTight(label, natural, room)
        end
    end
    label.fitScale = scale
    return scale
end

--- Sets a label's words and fits them to its room in one go.
local function Say(label, text, room)
    label:SetText(text)
    Fit(label, room)
end

--- How wide a label is drawn, or `guess` when the client will not say.
local function Drawn(label, guess)
    return Measure(label, "GetStringWidth") or guess
end

--- How wide a frame is, or `guess` when the client will not say.
local function Wide(frame, guess)
    return Measure(frame, "GetWidth") or guess
end

--- Measures every fitted label afresh: a font may only have been ready, or
--- have changed, after the label was made.
local function Refit()
    for label in pairs(fitted) do
        if label.fitLines then
            FitLines(label, label.fitRoom, label.fitLines, true)
        else
            Fit(label, label.fitRoom, true)
        end
    end
end

Options.Refit = Refit

--- The game's own click, so the panel sounds like the rest of the Options window.
local function Sound(name)
    local kit = SOUNDKIT
    local id = type(kit) == "table" and kit[name]
    if id and type(PlaySound) == "function" then
        pcall(PlaySound, id)
    end
end

local function ShowTip(owner)
    local tip = GameTooltip
    if not tip or not owner.tipTitle then
        return
    end
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    tip:SetText(owner.tipTitle)
    if owner.tipBody then
        Try(tip, "AddLine", owner.tipBody, 1, 1, 1, true)
    end
    tip:Show()
end

local function HideTip()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

--- Gives a frame a tooltip: a title, and optionally a line or two under it.
--- Both can be changed later through frame.tipTitle and frame.tipBody.
local function Tip(frame, title, body)
    frame.tipTitle, frame.tipBody = title, body
    frame:SetScript("OnEnter", ShowTip)
    frame:SetScript("OnLeave", HideTip)
end

--- Runs fn when the button is clicked, with the click sound. A failure is
--- reported by the addon, not thrown at the game.
local function OnClick(button, fn)
    button:SetScript("OnClick", function(self)
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        ns.Guard(fn, self)
    end)
end

--------------------------------------------------------------------------------
-- The game's own controls, on probation
--------------------------------------------------------------------------------

--- False when a piece of a control's art is known not to exist on this client:
--- the control would be there, and work, and not be seen.
local function ArtMissing(texture)
    if type(texture) ~= "table" then
        return false
    end
    local ok, atlas = Try(texture, "GetAtlas")
    atlas = ok and ns.PlainString(atlas) or nil
    return atlas ~= nil and atlas ~= "" and ns.AtlasExists(atlas) == false
end

--- Fails when any of these pieces of art is known to be missing.
local function NeedArt(what, ...)
    for i = 1, select("#", ...) do
        if ArtMissing((select(i, ...))) then
            error("this client lacks the art for " .. what, 0)
        end
    end
end

--- What a widget's method gives, or nil when it has no such method or it fails.
local function Ask(object, method)
    local ok, answer = Try(object, method)
    if ok then
        return answer
    end
    return nil
end

--- Builds one of the game's own controls. `make` creates it, notes the frame in
--- the holder it is given, and puts it through its paces; if anything in there
--- fails, whatever it had made so far is hidden and nil comes back, and the
--- caller draws its own instead. A kind that failed once is not tried again
--- this session, so that a panel is all of a piece.
local function Native(kind, make, ...)
    if Plain() or unusable[kind] then
        return nil
    end
    local holder = {}
    local ok, problem = pcall(make, holder, ...)
    if ok and holder.frame then
        notes.controls[kind] = "game"
        return holder.frame
    end
    unusable[kind] = true
    notes.controls[kind] = "own: " .. Brief(ok and "nothing was made" or problem)
    if holder.frame then
        Try(holder.frame, "Hide")
    end
    return nil
end

--------------------------------------------------------------------------------
-- Controls
--------------------------------------------------------------------------------

local function PlainButton(parent, width, height, text)
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

    local label = Label(button, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("CENTER", button, "CENTER", 0, 0)
    Say(label, text, width - 6)

    -- Looks pressed while the mouse is down on it.
    button:SetScript("OnMouseDown", function()
        back:SetColorTexture(0.09, 0.09, 0.12, 1)
    end)
    button:SetScript("OnMouseUp", function()
        back:SetColorTexture(0.16, 0.16, 0.2, 1)
    end)

    button.edge, button.back, button.label = edge, back, label
    return button
end

--- The words on one of the game's buttons, as a label that can be fitted.
local function ButtonLabel(button)
    local label = Ask(button, "GetFontString")
    if type(label) ~= "table" then
        label = button.Text
    end
    return type(label) == "table" and label or nil
end

local function MakeGameButton(holder, parent, width, height, text)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    holder.frame = button
    NeedArt("the game's button", button.Left, button.Middle, button.Right)
    button:SetSize(width, height)
    button:SetText(text)
    if button:GetText() ~= text then
        error("the game's button does not keep its words", 0)
    end
end

--- A push button. button.SetLabel(text) changes what it says.
local function PushButton(parent, width, height, text)
    local button = Native("button", MakeGameButton, parent, width, height, text)
    if button then
        button.native = true
        button.label = ButtonLabel(button)
        if button.label then
            Fit(button.label, width - 20) -- the art at its two ends takes the rest
        end
        button.SetLabel = function(label)
            button:SetText(label)
            if button.label then
                Fit(button.label, width - 20)
            end
        end
    else
        button = PlainButton(parent, width, height, text)
        button.SetLabel = function(label)
            Say(button.label, label, width - 6)
        end
    end
    return button
end

local function MakeGameTick(holder, parent)
    local box = CreateFrame("CheckButton", nil, parent, "MinimalCheckboxTemplate")
    holder.frame = box
    NeedArt("the game's tick box", Ask(box, "GetNormalTexture"), Ask(box, "GetCheckedTexture"))
    -- Left at the size the game gives it, since its art does not stretch with the
    -- box, as long as that is a size the panel has room for.
    local width, height = ns.PlainNumber(box:GetWidth()), ns.PlainNumber(box:GetHeight())
    if not width or not height or width < 12 or width > 36 or height < 12 or height > 36 then
        error("the game's tick box is " .. tostring(width) .. " by " .. tostring(height), 0)
    end
    -- It has to keep the tick it is given.
    box:SetChecked(true)
    local ticked = box:GetChecked()
    box:SetChecked(false)
    if not ticked or box:GetChecked() then
        error("the game's tick box does not keep its tick", 0)
    end
end

--- A tick box with its words beside it: control.Set(ticked), and
--- control.onChange(ticked) is called when a click changes it. control.Fit(room)
--- says how much room the words have.
local function TickBox(parent, text, font)
    local control = { ticked = false }

    local mark
    local box = Native("tick", MakeGameTick, parent)
    if box then
        control.native = true
    else
        box = CreateFrame("Button", nil, parent)
        box:SetSize(20, 20)

        local edge = box:CreateTexture(nil, "BACKGROUND")
        edge:SetAllPoints(box)
        edge:SetColorTexture(0.45, 0.45, 0.5, 1)

        local back = box:CreateTexture(nil, "BORDER")
        back:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
        back:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)
        back:SetColorTexture(0.03, 0.03, 0.05, 1)

        local glow = box:CreateTexture(nil, "HIGHLIGHT")
        glow:SetAllPoints(box)
        glow:SetColorTexture(1, 1, 1, 0.15)

        mark = box:CreateTexture(nil, "ARTWORK")
        mark:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
        mark:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
        mark:SetTexture(Icons.Choice("check").texture)
    end

    local label = Text(parent, font or "GameFontHighlight", text)
    label:SetJustifyV("MIDDLE")
    label:SetPoint("LEFT", box, "RIGHT", 4, 0)

    -- A click on the words counts as a click on the box.
    local function Reach()
        local width = Drawn(label)
        if width then
            Try(box, "SetHitRectInsets", 0, -(width + 6), 0, 0)
        end
    end
    Reach()

    function control.Fit(room)
        Fit(label, room)
        Reach()
    end

    function control.Set(ticked)
        ticked = ticked and true or false
        control.ticked = ticked
        if mark then
            Shown(mark, ticked)
        else
            box:SetChecked(ticked)
        end
    end

    box:SetScript("OnClick", function()
        local ticked = not control.ticked
        control.Set(ticked) -- the game's own box has flipped itself already; this keeps both kinds in step
        Sound(ticked and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
        if control.onChange then
            ns.Guard(control.onChange, ticked)
        end
    end)

    control.frame, control.label = box, label
    control.Set(false)
    return control
end

local function MakeGameSlider(holder, parent, width, low, high, changed)
    local frame = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
    holder.frame = frame
    local slider = frame.Slider
    if type(slider) ~= "table" or type(slider.GetValue) ~= "function" then
        error("the game's slider has no slider in it", 0)
    end
    NeedArt("the game's slider", Ask(slider, "GetThumbTexture"), slider.Left, slider.Middle, slider.Right)
    frame:SetSize(width, 20)
    frame:Init(low, low, high, high - low) -- one step for each whole number

    -- It has to go where it is sent.
    frame:SetValue(low + 1)
    local moved = ns.PlainNumber(slider:GetValue())
    frame:SetValue(low)
    local back = ns.PlainNumber(slider:GetValue())
    if not moved or not back or abs(moved - (low + 1)) > 0.01 or abs(back - low) > 0.01 then
        error("the game's slider does not go where it is sent", 0)
    end

    -- And it has to say when the player moves it. It is asked in two ways, its
    -- own notice and the plain script under it, because neither can be tried
    -- out from here; a move that is told twice is acted on once.
    local function Moved(_, value)
        changed(value)
    end
    local told = false
    if type(frame.RegisterCallback) == "function" then
        local event = type(frame.Event) == "table" and frame.Event.OnValueChanged or "OnValueChanged"
        told = pcall(frame.RegisterCallback, frame, event, Moved, holder)
    end
    local hooked = Try(slider, "HookScript", "OnValueChanged", Moved)
    if not told and not hooked then
        error("the game's slider cannot say when it is moved", 0)
    end
end

--- A slider over whole numbers with a step button at each end:
--- control.Set(value) moves it without telling anyone, and control.onChange(value)
--- is called when the player moves it.
local function NumberSlider(parent, width, low, high)
    local control = { value = low }
    local setting = false

    local function Changed(value)
        value = ns.PlainNumber(value)
        if setting or not value then
            return
        end
        value = max(low, min(high, floor(value + 0.5)))
        if value == control.value then
            return -- where it already is: nothing to tell
        end
        control.value = value
        if control.onChange then
            ns.Guard(control.onChange, value)
        end
    end

    local frame = Native("slider", MakeGameSlider, parent, width, low, high, Changed)
    local widget
    if frame then
        control.native = true
        widget = frame.Slider
        function control.Set(value)
            control.value = value
            setting = true
            Try(frame, "SetValue", value)
            setting = false
        end
    else
        frame = CreateFrame("Frame", nil, parent)
        frame:SetSize(width, 20)

        widget = CreateFrame("Slider", nil, frame)
        widget:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -2)
        widget:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -22, 2)
        widget:EnableMouse(true)
        widget:SetOrientation("HORIZONTAL")
        widget:SetMinMaxValues(low, high)
        widget:SetValueStep(1)
        Try(widget, "SetObeyStepOnDrag", true)

        local track = widget:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("LEFT", widget, "LEFT", 0, 0)
        track:SetPoint("RIGHT", widget, "RIGHT", 0, 0)
        track:SetHeight(4)
        track:SetColorTexture(0.35, 0.35, 0.4, 1)

        local thumb = widget:CreateTexture(nil, "OVERLAY")
        thumb:SetSize(8, 16)
        thumb:SetColorTexture(0.8, 0.8, 0.85, 1)
        widget:SetThumbTexture(thumb)

        widget:SetScript("OnValueChanged", function(_, value)
            Changed(value)
        end)

        local less = PlainButton(frame, 18, 18, "-")
        less:SetPoint("LEFT", frame, "LEFT", 0, 0)
        OnClick(less, function()
            Changed(control.value - 1)
        end)
        local more = PlainButton(frame, 18, 18, "+")
        more:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        OnClick(more, function()
            Changed(control.value + 1)
        end)
        control.less, control.more = less, more

        function control.Set(value)
            control.value = value
            setting = true
            widget:SetValue(value)
            setting = false
        end
    end

    control.frame, control.widget = frame, widget
    return control
end

--- A square button that shows one icon, with a gold frame when it is the one in use.
local function Tile(parent, size)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)

    local ring = button:CreateTexture(nil, "BACKGROUND")
    ring:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
    ring:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
    ring:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
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

    button:SetScript("OnMouseDown", function()
        art:SetAlpha(0.6)
    end)
    button:SetScript("OnMouseUp", function()
        art:SetAlpha(1)
    end)

    button.ring, button.art = ring, art
    return button
end

--- A row of joined buttons of which one is picked: control.Set(key), and
--- control.onPick(key) is called on a click. Each choice is { key, label,
--- width, tip, body }.
local function Segmented(parent, choices)
    local control = { buttons = {} }
    local frame = CreateFrame("Frame", nil, parent)
    local x = 0
    for i = 1, #choices do
        local choice = choices[i]
        local button = CreateFrame("Button", nil, frame)
        button:SetSize(choice.width, 20)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
        x = x + choice.width - 1 -- neighbours share an edge

        local edge = button:CreateTexture(nil, "BACKGROUND")
        edge:SetAllPoints(button)

        local back = button:CreateTexture(nil, "BORDER")
        back:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        back:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)

        local glow = button:CreateTexture(nil, "HIGHLIGHT")
        glow:SetAllPoints(button)
        glow:SetColorTexture(1, 1, 1, 0.12)

        local label = Label(button, "ARTWORK", "GameFontHighlightSmall")
        label:SetPoint("CENTER", button, "CENTER", 0, 0)
        Say(label, choice.label, choice.width - 8)

        button.edge, button.back, button.label = edge, back, label
        OnClick(button, function()
            if control.onPick then
                control.onPick(choice.key)
            end
        end)
        Tip(button, choice.tip, choice.body)
        control.buttons[choice.key] = button
    end
    frame:SetSize(x + 1, 20)

    function control.Set(key)
        control.picked = key
        for name, button in pairs(control.buttons) do
            local picked = name == key
            button.picked = picked
            if picked then
                button.edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
                button.back:SetColorTexture(0.24, 0.2, 0.08, 1)
                button.label:SetTextColor(1, 1, 1)
                button:SetFrameLevel(frame:GetFrameLevel() + 2) -- its gold edge sits on top of its neighbours'
            else
                button.edge:SetColorTexture(0.35, 0.35, 0.4, 1)
                button.back:SetColorTexture(0.1, 0.1, 0.13, 1)
                button.label:SetTextColor(0.65, 0.65, 0.65)
                button:SetFrameLevel(frame:GetFrameLevel() + 1)
            end
        end
    end

    control.frame, control.width = frame, x + 1
    control.Set(nil)
    return control
end

local function Input(parent, width)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, 20)
    box:EnableMouse(true)
    box:SetAutoFocus(false)
    local font = FontName("GameFontHighlightSmall")
    if font then
        box:SetFontObject(_G[font])
    else
        box:SetFont(STANDARD_FONT, 10, "")
    end
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
local function Change(fn)
    fn()
    ns.Relayout()
    ns.MarkDirty()
    Options.RefreshAll()
end

Options.Change = Change

--- The same for a change to how a spell is treated, which the bars have to be
--- read again for.
local function SpellChanged()
    ns.MarkBarsDirty()
    Options.RefreshAll()
end

--- Tells the addon what the panel needs of it: sample icons on the real action
--- buttons while some copy is open on its Appearance tab, and the bars read
--- while any copy is open at all (the panel lists them even with the icons off).
function Options.UpdateSampling()
    local open, sampling = false, false
    for i = 1, #views do
        local view = views[i]
        if view.pages[view.tab]:IsVisible() then
            open = true
            sampling = sampling or view.tab == "appearance"
        end
    end
    ns.SetWatching(open)
    ns.SetSampling(sampling)
end

--------------------------------------------------------------------------------
-- The Appearance tab
--------------------------------------------------------------------------------

--- Pictures for the pretend buttons: spells from your own bars, those that get
--- an icon first.
local function PreviewFaces()
    local faces = {}
    local list = ns.BarSpells()
    for pass = 1, 2 do
        for i = 1, #list do
            if #faces >= #Icons.STATES then
                return faces
            end
            local tracked = Spells:Tracking(list[i]) and true or false
            if tracked == (pass == 1) then
                faces[#faces + 1] = ns.SpellIcon(list[i].id)
            end
        end
    end
    return faces
end

--- One pretend action button, with nine spots to click and the icon of one
--- result drawn on it where and as large as it is on the real ones.
local function BuildPreview(view, page, index, state)
    local preview = { zones = {} }

    -- The slot cuts off an icon that is set far larger than the button.
    local slot = CreateFrame("Frame", nil, page)
    slot:SetSize(L.slotWidth, L.slotHeight)
    slot:SetPoint("TOPLEFT", page, "TOPLEFT", 16 + (index - 1) * L.slotPitch, L.headTop - 18)
    Try(slot, "SetClipsChildren", true)

    local button = CreateFrame("Frame", nil, slot)
    button:SetPoint("CENTER", slot, "CENTER", 0, 0)
    button:SetSize(45, 45)

    local face = button:CreateTexture(nil, "BACKGROUND")
    face:SetAllPoints(button)
    face:SetTexture(QUESTION)
    Try(face, "SetTexCoord", 0.07, 0.93, 0.07, 0.93) -- trims the picture's own border, as action buttons do

    for row = 1, 3 do
        for column = 1, 3 do
            local position = GRID[row][column]
            local zone = CreateFrame("Button", nil, button)

            local ghost = zone:CreateTexture(nil, "ARTWORK")
            ghost:SetSize(3, 3)
            ghost:SetPoint("CENTER", zone, "CENTER", 0, 0)
            ghost:SetColorTexture(1, 1, 1, 0.45)

            local glow = zone:CreateTexture(nil, "HIGHLIGHT")
            glow:SetAllPoints(zone)
            glow:SetColorTexture(1, 1, 1, 0.3)

            zone.ghost, zone.row, zone.column = ghost, row, column
            OnClick(zone, function()
                Change(function()
                    ns.db.corner = position
                end)
            end)
            Tip(zone, POSITION_NAMES[position])
            preview.zones[position] = zone
        end
    end

    -- The icon is drawn above the spots, on a frame the mouse passes through.
    local top = CreateFrame("Frame", nil, button)
    top:SetAllPoints(button)
    top:SetFrameLevel(button:GetFrameLevel() + 5)
    local icon = top:CreateTexture(nil, "OVERLAY")

    local caption = Text(page, "GameFontHighlightSmall", state.title)
    caption:SetJustifyH("CENTER")
    caption:SetPoint("TOP", slot, "BOTTOM", 0, -4)

    preview.slot, preview.button, preview.face, preview.icon, preview.caption = slot, button, face, icon, caption
    return preview
end

--- The box for a texture of your own: somewhere to type, and a line that says
--- what to type or what went wrong. The tile beside it shows the texture.
local function BuildEditor(view, page, state, left, top)
    local editor = CreateFrame("Frame", nil, page)
    editor:SetSize(196, 54)
    editor:SetPoint("TOPLEFT", page, "TOPLEFT", left, top)
    editor:Hide()

    local note = Text(editor, "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", editor, "TOPLEFT", 2, -29)
    note:SetWidth(194)

    local function Tell(text, colour)
        note:SetText(text)
        FitLines(note, 194, 3) -- three lines is all the room there is above the next result
        Colour(note, colour or { 0.5, 0.5, 0.5 })
    end

    local function Apply(box)
        local text = box:GetText() or ""
        if not text:find("%S") then
            -- Emptied: back to the usual icon if this result was on a texture of its own.
            box:ClearFocus()
            view.editing[state.key] = nil
            if Icons.Current(state.key) == "custom" then
                Change(function()
                    Icons.Set(state.key, nil)
                end)
            else
                view.Refresh()
            end
            return
        end
        local texture = Icons.ParseCustom(text)
        if not texture then
            editor.problem = true
            Tell("Not a texture. Type a file ID such as 136243, or a path that starts with Interface.", BAD)
            return
        end
        box:ClearFocus()
        Change(function()
            Icons.SetCustom(state.key, texture)
        end)
    end

    local built, box = pcall(Input, editor, 192)
    if built and box then
        box:SetPoint("TOPLEFT", editor, "TOPLEFT", 2, -5)
        box:SetScript("OnEnterPressed", function(self)
            ns.Guard(Apply, self)
        end)
        box:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            if Icons.Current(state.key) ~= "custom" then
                view.editing[state.key] = nil
            end
            ns.Guard(view.Refresh)
        end)
        editor.box = box
    end

    --- Brings the box in line with the settings. `missing` says that the game
    --- has no texture where the player's own one points.
    function editor.Refresh(current, custom, missing)
        local open = current == "custom" or view.editing[state.key] == true
        Shown(editor, open)
        if not open then
            editor.problem = nil
            return
        end
        local focused = editor.box and editor.box:HasFocus()
        if editor.box and not focused then
            editor.box:SetText(current == "custom" and tostring(custom) or "")
            editor.problem = nil
        end
        editor.missing = current == "custom" and missing == true or nil
        if editor.problem then
            return -- the complaint stays up while the box is being corrected
        elseif not editor.box then
            Tell("/se icon " .. state.key .. " <file ID or path>")
        elseif editor.missing then
            Tell("The game has no texture there, so no icon shows.", WARN)
        elseif current == "custom" then
            Tell("In use. Empty the box and press Enter to undo.")
        else
            Tell("A file ID or a path, then Enter.")
        end
    end

    editor.note = note
    return editor
end

--- One result: its heading, every icon it can use, "no icon", and "your own".
local function BuildResult(view, page, index, state)
    local top = L.blockTop - (index - 1) * L.blockPitch
    local key = state.key

    local current = page:CreateTexture(nil, "ARTWORK")
    current:SetSize(16, 16)
    current:SetPoint("TOPLEFT", page, "TOPLEFT", 16, top + 2)
    view.current[key] = current

    local name = Text(page, "GameFontNormal", state.title)
    name:SetPoint("TOPLEFT", page, "TOPLEFT", 38, top)
    Fit(name, 200)
    local detail = Text(page, "GameFontHighlightSmall", state.detail)
    detail:SetPoint("LEFT", name, "RIGHT", 10, 0)
    view.names[key], view.details[key] = name, detail

    -- Says so when this result cannot be told from an earlier one.
    local clash = Text(page, "GameFontHighlightSmall")
    clash:SetJustifyH("RIGHT")
    clash:SetPoint("TOPRIGHT", page, "TOPLEFT", L.right, top - 1)
    Colour(clash, WARN)
    clash:Hide()
    view.clashes[key] = clash

    local tiles = {}
    local own, game = 0, 0
    for i = 1, #Icons.CHOICES do
        local choice = Icons.CHOICES[i]
        local column, line
        if choice.own then
            column, line, own = own, 0, own + 1 -- the addon's own icons on the first line
        else
            column, line, game = game, 1, game + 1 -- the game's on the second
        end
        local tile = Tile(page, L.tile)
        tile:SetPoint("TOPLEFT", page, "TOPLEFT", 18 + column * L.tileStep, top - 20 - line * L.tileStep)
        tile.art:SetTexture(choice.texture)
        OnClick(tile, function()
            view.editing[key] = nil
            Change(function()
                Icons.Set(key, choice.key)
            end)
        end)
        Tip(tile, choice.name)
        tiles[choice.key] = tile
    end

    -- No icon at all: a bare tile with a stroke through it, at the end of the first line.
    local hidden = Tile(page, L.tile)
    hidden:SetPoint("TOPLEFT", page, "TOPLEFT", 18 + own * L.tileStep, top - 20)
    local drawn, stroke = Try(hidden, "CreateLine", nil, "ARTWORK")
    if drawn and stroke and Try(stroke, "SetStartPoint", "BOTTOMLEFT", hidden, 8, 8)
        and Try(stroke, "SetEndPoint", "TOPRIGHT", hidden, -8, -8) then
        Try(stroke, "SetThickness", 2)
        Try(stroke, "SetColorTexture", 0.6, 0.6, 0.65, 1)
    else
        local dash = Label(hidden, "ARTWORK", "GameFontDisableSmall")
        dash:SetPoint("CENTER", hidden, "CENTER", 0, 0)
        Say(dash, "none", L.tile - 4)
    end
    OnClick(hidden, function()
        view.editing[key] = nil
        Change(function()
            Icons.SetHidden(key)
        end)
    end)
    Tip(hidden, Icons.HIDDEN_NAME, "Buttons stay bare for this result.")
    tiles[Icons.HIDDEN] = hidden

    -- A texture of your own: the tile opens a box to type it into.
    local editor = BuildEditor(view, page, state, 18 + (own + 2) * L.tileStep, top - 20)
    local custom = Tile(page, L.tile)
    custom:SetPoint("TOPLEFT", page, "TOPLEFT", 18 + (own + 1) * L.tileStep, top - 20)
    local dots = Label(custom, "ARTWORK", "GameFontHighlight")
    dots:SetPoint("CENTER", custom, "CENTER", 0, 3)
    Say(dots, "...", L.tile - 4)
    custom.dots = dots
    OnClick(custom, function()
        view.editing[key] = true
        view.Refresh()
        if editor.box then
            editor.box:SetFocus()
        end
    end)
    Tip(custom, "Your own texture", "Any picture in the game, by file ID or by path.")
    tiles.custom = custom

    view.swatches[key] = tiles
    view.editors[key] = editor
    view.inputs[key] = editor.box
end

local function BuildAppearance(view, page)
    view.previews, view.sets, view.current, view.clashes = {}, {}, {}, {}
    view.swatches, view.editors, view.inputs, view.editing = {}, {}, {}, {}
    view.names, view.details = {}, {}

    -- On or off, when, and on which skills: the three read as one sentence.
    local enable = TickBox(page, "Show status icons")
    enable.frame:SetPoint("LEFT", page, "TOPLEFT", 14, -22)
    enable.onChange = function(ticked)
        ns.SetEnabled(ticked)
        Options.RefreshAll()
    end
    view.enable = enable

    local appear = Segmented(page, APPEAR_CHOICES)
    appear.frame:SetPoint("LEFT", enable.label, "RIGHT", 14, 0)
    -- The words get what the box before them and the choices after them leave.
    enable.Fit(L.right - appear.width - 14 - (14 + Wide(enable.frame, 30) + 4))
    appear.onPick = function(key)
        Change(function()
            ns.SetAppear(key)
        end)
    end
    view.appear = appear

    local usable = Segmented(page, USABLE_CHOICES)
    usable.frame:SetPoint("TOPLEFT", appear.frame, "BOTTOMLEFT", 0, -4)
    usable.onPick = function(key)
        Change(function()
            ns.SetUsableOnly(key == "usable")
        end)
    end
    view.usable = usable

    -- A pretend button for each result.
    local previewLabel = Text(page, "GameFontNormal", "Preview")
    previewLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 16, L.headTop)
    Fit(previewLabel, 80)
    local hint = Text(page, "GameFontHighlightSmall", "Click a spot on any button to move the icon.")
    hint:SetPoint("BOTTOMLEFT", previewLabel, "BOTTOMRIGHT", 10, 1)
    view.previewLabel, view.hint = previewLabel, hint

    for index = 1, #Icons.STATES do
        local state = Icons.STATES[index]
        view.previews[state.key] = BuildPreview(view, page, index, state)
    end
    view.zones = view.previews[Icons.STATES[1].key].zones

    local sampleNote = Text(page, "GameFontDisableSmall")
    sampleNote:SetPoint("TOPLEFT", page, "TOPLEFT", 16, L.headTop - 112)
    view.sampleNote = sampleNote

    -- Size: a slider, or follow the button.
    local sizeLabel = Text(page, "GameFontNormal", "Icon size")
    sizeLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 300, L.headTop)
    Fit(sizeLabel, L.right - 300)

    local slider = NumberSlider(page, 200, ns.SIZE_MIN, ns.SIZE_MAX)
    slider.frame:SetPoint("TOPLEFT", page, "TOPLEFT", 300, L.headTop - 18)
    slider.onChange = function(value)
        Change(function()
            ns.db.size = value
        end)
    end

    local lowest = Text(page, "GameFontDisableSmall", tostring(ns.SIZE_MIN))
    lowest:SetJustifyH("CENTER")
    lowest:SetPoint("TOP", slider.frame, "BOTTOMLEFT", 22, -1)
    local highest = Text(page, "GameFontDisableSmall", tostring(ns.SIZE_MAX))
    highest:SetJustifyH("CENTER")
    highest:SetPoint("TOP", slider.frame, "BOTTOMRIGHT", -22, -1)

    local readout = Text(page, "GameFontHighlight")
    readout:SetJustifyH("CENTER")
    readout:SetJustifyV("MIDDLE")
    readout:SetPoint("CENTER", slider.frame, "RIGHT", 18, 0)

    local auto = TickBox(page, "Auto")
    auto.frame:SetPoint("LEFT", slider.frame, "RIGHT", 38, 0)
    auto.Fit(L.right - (300 + 200 + 38) - Wide(auto.frame, 30) - 4)
    auto.onChange = function(ticked)
        Change(function()
            -- Unticked, the icon stays the size it was, as a size of its own.
            ns.db.size = ticked and 0 or max(ns.SIZE_MIN, min(ns.SIZE_MAX, ns.AutoIconSize()))
        end)
    end
    Tip(auto.frame, "Auto", "Size the icon from the button it sits on.")

    view.size = { slider = slider, readout = readout, auto = auto }

    -- Sets: all three icons in one click.
    local setLabel = Text(page, "GameFontNormal", "Icon set")
    setLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 300, L.headTop - 58)
    Fit(setLabel, L.right - 300)
    for index = 1, #Icons.SETS do
        local set = Icons.SETS[index]
        local button = CreateFrame("Button", nil, page)
        button:SetSize(76, 30)
        button:SetPoint("TOPLEFT", page, "TOPLEFT", 300 + (index - 1) * 80, L.headTop - 76)

        local ring = button:CreateTexture(nil, "BACKGROUND")
        ring:SetAllPoints(button)
        ring:SetColorTexture(0.35, 0.35, 0.4, 1)

        local back = button:CreateTexture(nil, "BORDER")
        back:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        back:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        back:SetColorTexture(0.1, 0.1, 0.12, 1)

        local glow = button:CreateTexture(nil, "HIGHLIGHT")
        glow:SetAllPoints(button)
        glow:SetColorTexture(1, 1, 1, 0.15)

        for i = 1, #Icons.STATES do
            local art = button:CreateTexture(nil, "ARTWORK")
            art:SetSize(18, 18)
            art:SetPoint("LEFT", button, "LEFT", 7 + (i - 1) * 22, 0)
            art:SetTexture(Icons.Choice(set.icons[Icons.STATES[i].key]).texture)
        end

        button.ring = ring
        OnClick(button, function()
            ns.Wipe(view.editing)
            Change(function()
                Icons.ApplySet(set)
            end)
        end)
        Tip(button, set.name, "Uses these three icons for the three results.")
        view.sets[set.key] = button
    end

    -- Each result and the icons it can use.
    for index = 1, #Icons.STATES do
        BuildResult(view, page, index, Icons.STATES[index])
    end

    -- Reset, which asks first.
    local bottom = L.blockTop - #Icons.STATES * L.blockPitch - 4
    local reset = PushButton(page, 150, 22, "Reset appearance...")
    reset:SetPoint("TOPLEFT", page, "TOPLEFT", 16, bottom)

    local pointer = Text(page, "GameFontDisableSmall", "Spell by spell settings are on the Spells tab.")
    pointer:SetJustifyH("RIGHT")
    pointer:SetPoint("TOPRIGHT", page, "TOPLEFT", L.right, bottom - 6)
    Fit(pointer, L.right - (16 + 150) - 12) -- what the reset button leaves

    local confirm = CreateFrame("Frame", nil, page)
    confirm:SetSize(608, 22)
    confirm:SetPoint("TOPLEFT", page, "TOPLEFT", 16, bottom)
    confirm:Hide()
    local question = Text(confirm, "GameFontHighlight", "Put the position, size and icons back to how they started?")
    question:SetJustifyV("MIDDLE")
    question:SetPoint("LEFT", confirm, "LEFT", 0, 0)
    Fit(question, 608 - 12 - 90 - 6 - 90) -- what its two buttons leave
    view.pointer, view.question = pointer, question
    local yes = PushButton(confirm, 90, 22, "Reset")
    yes:SetPoint("LEFT", question, "RIGHT", 12, 0)
    local no = PushButton(confirm, 90, 22, "Cancel")
    no:SetPoint("LEFT", yes, "RIGHT", 6, 0)

    local function Asking(asking)
        Shown(confirm, asking)
        Shown(reset, not asking)
        Shown(pointer, not asking)
    end
    OnClick(reset, function()
        Asking(true)
    end)
    OnClick(no, function()
        Asking(false)
    end)
    OnClick(yes, function()
        Asking(false)
        ns.Wipe(view.editing)
        Change(function()
            ns.db.corner = "TOPLEFT"
            ns.db.size = 0
            Icons.ResetAll()
        end)
    end)
    view.reset, view.confirm = reset, { frame = confirm, yes = yes, no = no }

    --- Puts away whatever was half done when the panel closes.
    function view.Settle()
        Asking(false)
        for key in pairs(view.editing) do
            view.editing[key] = nil
        end
        for _, editor in pairs(view.editors) do
            if editor.box then
                editor.box:ClearFocus()
            end
        end
    end

    --- The three captions under the pretend buttons stand shoulder to shoulder,
    --- so they are fitted together: all three shrink until each pair of
    --- neighbours has a gap between them.
    local function FitCaptions()
        local scale, widths = 1, {}
        for index = 1, #Icons.STATES do
            local caption = view.previews[Icons.STATES[index].key].caption
            if not Scale(caption, 1) then
                return
            end
            widths[index] = Measure(caption, "GetUnboundedStringWidth")
                or (not caption.fitCut and Measure(caption, "GetStringWidth")) or nil
            if not widths[index] then
                return
            end
        end
        for index = 1, #widths - 1 do
            scale = min(scale, (L.slotPitch - 4) * 2 / (widths[index] + widths[index + 1]))
        end
        -- Nor may the first run off the page, or the last into the next column.
        local first = 16 + L.slotWidth / 2
        local last = first + (#widths - 1) * L.slotPitch
        scale = min(scale, (first - 4) * 2 / widths[1], (292 - last) * 2 / widths[#widths])
        -- Letters only shrink so far. Past that each caption is cut to its own slot.
        local cut = scale < SMALLEST
        scale = max(SMALLEST, scale)
        for index = 1, #widths do
            local caption = view.previews[Icons.STATES[index].key].caption
            Scale(caption, scale)
            caption.fitScale = scale
            if cut ~= (caption.fitCut == true) then
                caption.fitCut = cut
                Try(caption, "SetWidth", cut and L.slotPitch - 4 or 0)
                Try(caption, "SetWordWrap", not cut)
            end
        end
        if scale < 1 then
            notes.tight["(captions under the preview)"] = floor(scale * 100 + 0.5) .. "%"
        end
    end

    --- The pretend buttons wear pictures from your own bars.
    local function RefreshFaces()
        local faces = PreviewFaces()
        for index = 1, #Icons.STATES do
            local preview = view.previews[Icons.STATES[index].key]
            local face = faces[index] or QUESTION
            if preview.wears ~= face then
                preview.wears = face
                preview.face:SetTexture(face)
            end
        end
    end

    -- The bars may only have been read a moment after the panel opened.
    local waited = 0
    page:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + (type(elapsed) == "number" and elapsed or 0)
        if waited >= 0.5 then
            waited = 0
            ns.Guard(RefreshFaces)
        end
    end)

    function view.RefreshAppearance()
        enable.Set(ns.db.enabled)
        appear.Set(ns.db.appear)
        usable.Set(ns.db.usableOnly and "usable" or "always")
        local alpha = ns.db.enabled and 1 or 0.4 -- neither changes anything while the icons are off
        Try(appear.frame, "SetAlpha", alpha)
        Try(usable.frame, "SetAlpha", alpha)

        -- Size: the slider sits at the size in use, chosen or not.
        local chosen = ns.db.size
        local size = chosen > 0 and chosen or ns.AutoIconSize()
        slider.Set(max(ns.SIZE_MIN, min(ns.SIZE_MAX, size)))
        Say(readout, tostring(size), 34)
        auto.Set(chosen == 0)

        -- The hint has what the word "Preview" leaves it, up to the next column.
        Fit(hint, 292 - (16 + Drawn(previewLabel, 50) + 10))
        FitCaptions()

        -- The pretend buttons are as large as a real one looks from here, so the
        -- icon on them is the size it is on the bars.
        local width, ratio = ns.TypicalButton(page)
        local side = max(L.previewMin, min(L.previewMax, width * ratio))
        local scale = side / width
        local corner = ns.db.corner
        local offset = ns.CORNERS[corner] or ns.CORNERS.TOPLEFT
        RefreshFaces()
        for index = 1, #Icons.STATES do
            local key = Icons.STATES[index].key
            local preview = view.previews[key]
            preview.button:SetSize(side, side)
            for position, zone in pairs(preview.zones) do
                zone:SetSize(side / 3, side / 3)
                zone:ClearAllPoints()
                zone:SetPoint("TOPLEFT", preview.button, "TOPLEFT", (zone.column - 1) * side / 3,
                    -(zone.row - 1) * side / 3)
                Shown(zone.ghost, position ~= corner)
            end
            local art = Icons.Texture(key)
            if art then
                preview.icon:SetTexture(art)
                preview.icon:SetSize(size * scale, size * scale)
                preview.icon:ClearAllPoints()
                preview.icon:SetPoint(corner, preview.button, corner, offset[1] * scale, offset[2] * scale)
            end
            Shown(preview.icon, art ~= nil)
        end
        Say(sampleNote, ns.db.enabled
            and "Out of combat, your action buttons show sample icons while this tab is open."
            or "Status icons are turned off, so your action buttons show none.", L.right - 16)

        local set = Icons.CurrentSet()
        for setKey, button in pairs(view.sets) do
            if set and set.key == setKey then
                button.ring:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
            else
                button.ring:SetColorTexture(0.35, 0.35, 0.4, 1)
            end
            button.picked = set ~= nil and set.key == setKey
        end

        for index = 1, #Icons.STATES do
            local state = Icons.STATES[index]
            local key = state.key
            local current, custom = Icons.Current(key)
            local art = Icons.Texture(key)
            if art then
                view.current[key]:SetTexture(art)
            end
            Shown(view.current[key], art ~= nil)

            local tiles = view.swatches[key]
            for choiceKey, tile in pairs(tiles) do
                Shown(tile.ring, choiceKey == current)
            end
            -- The tile for your own texture shows it once there is one. Setting it
            -- is also the only way to learn that the game has no such texture.
            local missing = false
            if current == "custom" then
                local art = tiles.custom.art
                local answer = art:SetTexture(custom)
                missing = answer == false or (answer == nil and art:GetTexture() == nil)
            end
            Shown(tiles.custom.art, current == "custom")
            Shown(tiles.custom.dots, current ~= "custom")

            view.editors[key].Refresh(current, custom, missing)

            -- The result's sentence has what its heading leaves it, less the
            -- note at the far end when that is up.
            local clash, taken = view.clashes[key], 0
            local other = Icons.SharedWith(key)
            if other then
                Say(clash, "Same icon as \"" .. other.title .. "\"", 300)
                taken = Drawn(clash, 190) + 12
            end
            Shown(clash, other ~= nil)
            Fit(view.details[key], L.right - (38 + Drawn(view.names[key], 130) + 10) - taken)
        end
    end
end

--------------------------------------------------------------------------------
-- The Spells tab
--------------------------------------------------------------------------------

local SHOW_CHOICES = {
    { key = "auto", label = "Auto", width = 38, tip = "Let the addon decide",
        body = "It gets an icon when it looks like it leaves a status effect, and loses it if casts keep leaving nothing behind." },
    { key = "always", label = "Always", width = 50, tip = "Always show an icon" },
    { key = "never", label = "Never", width = 44, tip = "Never show an icon" },
}

local ON_CHOICES = {
    { key = "target", label = "Target", width = 48, tip = "A debuff on your target",
        body = "Judged on the enemy you have targeted." },
    { key = "all", label = "All enemies", width = 76, tip = "A debuff on every enemy in the fight",
        body = "Judged on all of them, so the icon can also say that only some have it." },
    { key = "self", label = "You", width = 36, tip = "A buff on you",
        body = "Or on the friend you have targeted, if the spell can be cast on others." },
}

-- Why a spell is treated the way it is: a few words for the row, and a sentence
-- for the tooltip.
local WHY = {
    you = { "you turned it on", "You chose Always." },
    ignored = { "you turned it off", "You chose Never." },
    seen = {
        debuff = { "debuff seen on an enemy", "Its debuff has been read off an enemy." },
        buff = { "buff seen on you", "Its buff has been read off you." },
    },
    ["built-in"] = { "a well known area debuff", "It is a well known area debuff." },
    tooltip = {
        debuff = { "tooltip mentions a duration", "It can be cast on enemies and its tooltip mentions a duration." },
        buff = { "tooltip mentions a duration",
            "It is cast on yourself or on friends and its tooltip mentions a duration." },
    },
}

local DURATION_WHY = {
    you = "You set this.",
    seen = "Read off the effect itself in play.",
    tooltip = "Taken from the spell's tooltip.",
    guess = "A guess: nothing better is known yet.",
}

--- A length of time in a few characters: "21 s", "2 min", "1 hr+".
local function Short(seconds)
    if seconds >= Spells.MAX_DURATION then
        return "1 hr+"
    elseif seconds >= 120 then
        return floor(seconds / 60 + 0.5) .. " min"
    end
    return floor(seconds + 0.5) .. " s"
end

local UNITS = {
    [""] = 1, s = 1, sec = 1, secs = 1, second = 1, seconds = 1,
    m = 60, min = 60, mins = 60, minute = 60, minutes = 60,
    h = 3600, hr = 3600, hour = 3600,
}

--- Reads a typed length of time, such as "21", "21 s" or "2 min": whole
--- seconds, or nil when it is not one.
local function ParseSpan(text)
    local number, unit = text:match("^%s*(%d+%.?%d*)%s*(%a*)%.?%s*$")
    local value = tonumber(number)
    local each = unit and UNITS[unit:lower()]
    if not value or not each then
        return nil
    end
    return floor(value * each + 0.5)
end

local function WhyText(info, tracked, source, kind)
    local why = WHY[source]
    if why and not why[1] then
        why = why[kind]
    end
    if why then
        return why[1], why[2]
    end
    local casts, hits = Spells:Record(info.name, kind)
    casts, hits = floor(casts + 0.5), floor(hits + 0.5)
    if source == "learned" then
        return "left an effect after " .. hits .. " of " .. casts .. " casts",
            "A new effect of yours followed " .. hits .. " of " .. casts .. " casts."
    elseif source == "demoted" then
        return "nothing after " .. (casts - hits) .. " of " .. casts .. " casts",
            "No new effect of yours followed " .. (casts - hits) .. " of " .. casts
                .. " casts, so it lost its icon. Pick Always to give it back."
    end
    return "not a status effect", "It does not look like it leaves a status effect. Pick Always if it does."
end

local function BuildRow(view, page, index)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(612, L.rowHeight)
    row:SetPoint("TOPLEFT", page, "TOPLEFT", 12, L.listTop - (index - 1) * L.rowHeight)
    row:Hide()

    if index % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints(row)
        stripe:SetColorTexture(1, 1, 1, 0.04)
    end

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    Try(icon, "SetTexCoord", 0.07, 0.93, 0.07, 0.93)

    local name = Text(row, "GameFontHighlight")
    name:SetJustifyV("MIDDLE")
    name:SetPoint("LEFT", row, "LEFT", 34, 0)
    name:SetWidth(108) -- a long name takes two lines, in smaller letters if it must; a longer one still is cut short

    local show = Segmented(row, SHOW_CHOICES)
    show.frame:SetPoint("LEFT", row, "LEFT", 146, 0)
    show.onPick = function(key)
        local info = row.info
        if not info then
            return
        end
        local choice = Spells:Choice(info.name)
        if key == "always" then
            choice.track = true
        elseif key == "never" then
            choice.track = false
            Tracker:Forget(info.name)
        else
            choice.track = nil
        end
        Spells:Tidy(info.name)
        SpellChanged()
    end

    local on = Segmented(row, ON_CHOICES)
    on.frame:SetPoint("LEFT", row, "LEFT", 284, 0)
    on.onPick = function(key)
        local info = row.info
        if not info then
            return
        end
        local _, _, _, _, kind = Spells:Tracking(info)
        local wanted = key == "self" and "buff" or "debuff"
        local choice = Spells:Choice(info.name)
        if wanted ~= kind then
            -- The same as /se buff and /se debuff: saying which kind it is also turns it on.
            choice.kind, choice.track = wanted, true
            Tracker:Forget(info.name)
        end
        if wanted == "debuff" then
            choice.aoe = key == "all"
        end
        SpellChanged()
    end

    local why = Text(row, "GameFontDisableSmall")
    why:SetJustifyV("MIDDLE")
    why:SetPoint("LEFT", row, "LEFT", 504, 0)
    why:SetWidth(106)
    local whyArea = CreateFrame("Frame", nil, row)
    whyArea:SetPoint("TOPLEFT", row, "TOPLEFT", 500, 0)
    whyArea:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    whyArea:EnableMouse(true)
    Tip(whyArea, "Why")

    local function ApplyDuration(box)
        local info = row.info
        if not info then
            return
        end
        local text = (box:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" or text:lower() == "auto" then
            local choice = ns.db.spells[info.name]
            if choice then
                choice.duration = nil
                Spells:Tidy(info.name)
            end
        else
            local seconds = ParseSpan(text)
            if not seconds or seconds < Spells.MIN_DURATION or seconds > Spells.MAX_DURATION then
                row.problem = "Type seconds, from " .. Spells.MIN_DURATION .. " to " .. Spells.MAX_DURATION .. "."
                why:SetText(row.problem)
                FitLines(why, 106, 2)
                Colour(why, BAD)
                return
            end
            Spells:Choice(info.name).duration = seconds
        end
        row.problem = nil
        box:ClearFocus()
        SpellChanged()
    end

    local built, lasts = pcall(Input, row, 46)
    if built and lasts then
        lasts:SetPoint("LEFT", row, "LEFT", 450, 0)
        Try(lasts, "SetJustifyH", "CENTER")
        lasts:SetMaxLetters(12)
        lasts:SetScript("OnEditFocusGained", function(self)
            -- Typing starts from the bare number of seconds.
            local info = row.info
            if info then
                local _, _, duration = Spells:Tracking(info)
                self:SetText(tostring(floor(duration + 0.5)))
                Try(self, "HighlightText")
            end
        end)
        lasts:SetScript("OnEditFocusLost", function(self)
            Try(self, "HighlightText", 0, 0)
            row.problem = nil
            ns.Guard(view.Refresh)
        end)
        lasts:SetScript("OnEnterPressed", function(self)
            ns.Guard(ApplyDuration, self)
        end)
        lasts:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)
        Tip(lasts, "How long the effect lasts")
    else
        lasts = nil
    end

    --- Shows a spell in this row, or nothing.
    function row.Bind(info)
        if row.info ~= info then
            row.problem = nil
            if lasts and lasts:HasFocus() then
                lasts:ClearFocus()
            end
        end
        row.info = info
        Shown(row, info ~= nil)
        if not info then
            return
        end

        local tracked, area, duration, source, kind = Spells:Tracking(info)
        local user = ns.db.spells[info.name]

        if row.iconFor ~= info.id then
            row.iconFor = info.id
            icon:SetTexture(ns.SpellIcon(info.id) or QUESTION)
        end
        Try(icon, "SetDesaturated", not tracked)
        icon:SetAlpha(tracked and 1 or 0.6)
        name:SetText(info.name)
        FitLines(name, 108, 2)
        if tracked then
            name:SetTextColor(1, 1, 1)
        else
            name:SetTextColor(0.6, 0.6, 0.6)
        end

        local pick = "auto"
        if user and user.track == true then
            pick = "always"
        elseif user and user.track == false then
            pick = "never"
        end
        show.Set(pick)

        -- Who it is judged on and how long it lasts only matter once it has an icon.
        Shown(on.frame, tracked)
        if tracked then
            on.Set(kind == "buff" and "self" or (area and "all" or "target"))
        end
        if lasts then
            Shown(lasts, tracked)
            if tracked and not lasts:HasFocus() then
                lasts:SetText(Short(duration))
            end
            lasts.tipBody = DURATION_WHY[Spells:DurationSource(info)]
                .. " Type a number of seconds to change it, or empty the box to let the addon work it out."
        end

        local short, long = WhyText(info, tracked, source, kind)
        whyArea.tipTitle, whyArea.tipBody = info.name, long
        if row.problem then
            why:SetText(row.problem)
            Colour(why, BAD)
        else
            why:SetText(short)
            why:SetTextColor(0.5, 0.5, 0.5)
        end
        FitLines(why, 106, 2) -- a row is two lines tall
    end

    row.icon, row.name, row.show, row.on, row.lasts, row.why, row.whyArea = icon, name, show, on, lasts, why, whyArea
    return row
end

local function BuildSpells(view, page)
    local list = { rows = {}, items = {}, offset = 0 }
    view.spells = list

    local intro = Text(page, "GameFontHighlightSmall",
        "Every spell on your action bars. The addon works out which ones leave a status effect and how to "
            .. "judge them. Change any it gets wrong.")
    intro:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -10)
    intro:SetWidth(608)
    FitLines(intro, 608, 2) -- the column headings start under its second line
    list.intro = intro

    local headings = { { "Spell", 16 }, { "Show an icon", 158 }, { "Judged on", 296 }, { "Lasts", 462 }, { "Why", 516 } }
    list.headings = {}
    for i = 1, #headings do
        local heading = Text(page, "GameFontNormalSmall", headings[i][1])
        heading:SetPoint("TOPLEFT", page, "TOPLEFT", headings[i][2], -38)
        -- Each has the room up to the next one.
        Fit(heading, (headings[i + 1] and headings[i + 1][2] or L.right) - headings[i][2] - 8)
        list.headings[i] = heading
    end
    local rule = page:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", page, "TOPLEFT", 12, -53)
    rule:SetSize(612, 1)
    rule:SetColorTexture(0.4, 0.4, 0.45, 1)

    for index = 1, L.rows do
        list.rows[index] = BuildRow(view, page, index)
    end

    local empty = Text(page, "GameFontDisable", "No spells found on your action bars yet.")
    empty:SetPoint("TOPLEFT", page, "TOPLEFT", 16, L.listTop - 8)
    Fit(empty, L.right - 16)
    empty:Hide()
    list.empty = empty

    local count = Text(page, "GameFontDisableSmall")
    count:SetPoint("TOPLEFT", page, "TOPLEFT", 16, L.listTop - L.rows * L.rowHeight - 12)
    list.count = count
    local more = Text(page, "GameFontDisableSmall", "Scroll for more.")
    more:SetJustifyH("RIGHT")
    more:SetPoint("TOPRIGHT", page, "TOPLEFT", L.right, L.listTop - L.rows * L.rowHeight - 12)
    Fit(more, 130)
    more:Hide()
    list.more = more

    -- A scroll bar of its own: the list is short, and this one cannot go missing.
    local setting = false
    local bar = CreateFrame("Slider", nil, page)
    bar:SetPoint("TOPLEFT", page, "TOPLEFT", 628, L.listTop)
    bar:SetSize(6, L.rows * L.rowHeight)
    bar:EnableMouse(true)
    bar:SetOrientation("VERTICAL")
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    Try(bar, "SetObeyStepOnDrag", true)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(bar)
    track:SetColorTexture(1, 1, 1, 0.06)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(6, 40)
    thumb:SetColorTexture(0.6, 0.6, 0.65, 1)
    bar:SetThumbTexture(thumb)
    bar:Hide()
    list.bar = bar

    local function Draw()
        local items = list.items
        local last = max(0, #items - L.rows)
        list.offset = max(0, min(last, list.offset))
        local shown = 0
        for index = 1, L.rows do
            local info = items[list.offset + index]
            list.rows[index].Bind(info)
            if info then
                shown = shown + 1
            end
        end

        local tracked = 0
        for i = 1, #items do
            if Spells:Tracking(items[i]) then
                tracked = tracked + 1
            end
        end
        Shown(empty, #items == 0)
        if #items == 0 then
            count:SetText("")
        else
            -- It has the line to itself, but for "Scroll for more." at the far end.
            Say(count, (#items == 1 and "1 spell" or (#items .. " spells")) .. " on your bars, "
                .. tracked .. " with an icon.", L.right - 16 - 130 - 12)
        end

        Shown(more, last > 0)
        Shown(bar, last > 0)
        setting = true
        bar:SetMinMaxValues(0, last)
        bar:SetValue(list.offset)
        setting = false
    end

    --- Moves the list by a number of rows.
    function list.Scroll(rows)
        local before = list.offset
        list.offset = list.offset + rows
        Draw()
        return list.offset ~= before
    end

    bar:SetScript("OnValueChanged", function(_, value)
        if not setting and type(value) == "number" then
            list.offset = floor(value + 0.5)
            ns.Guard(Draw)
        end
    end)
    Try(page, "EnableMouseWheel", true)
    page:SetScript("OnMouseWheel", function(_, delta)
        if type(delta) == "number" then
            ns.Guard(list.Scroll, -delta * 3)
        end
    end)

    --- Reads the bars again. The spells keep their places while the tab is open,
    --- so that a row does not jump away under the mouse: those with an icon are
    --- only sorted to the top when the tab opens (`resort`) or the bars change.
    function view.RefreshSpells(resort)
        local found = ns.BarSpells()
        local names, byName = {}, {}
        for i = 1, #found do
            names[i] = found[i].name
            byName[found[i].name] = found[i]
        end
        local signature = concat(names, "\n")
        if resort or signature ~= list.signature then
            list.signature = signature
            local items, rest = {}, {}
            for i = 1, #found do
                if Spells:Tracking(found[i]) then
                    items[#items + 1] = found[i]
                else
                    rest[#rest + 1] = found[i]
                end
            end
            for i = 1, #rest do
                items[#items + 1] = rest[i]
            end
            list.items = items
            if resort then
                list.offset = 0
            end
        else
            -- The same spells, though the client may have described them afresh.
            for i = 1, #list.items do
                list.items[i] = byName[list.items[i].name] or list.items[i]
            end
        end
        Draw()
    end

    -- What the addon learns in play shows up here without a click.
    local waited = 0
    page:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + (type(elapsed) == "number" and elapsed or 0)
        if waited >= 1 then
            waited = 0
            ns.Guard(view.RefreshSpells, false)
        end
    end)
end

--------------------------------------------------------------------------------
-- The panel: tabs, and a page under each
--------------------------------------------------------------------------------

local TABS = {
    { key = "appearance", label = "Appearance", width = 92 },
    { key = "spells", label = "Spells", width = 64 },
}

--- Fills `host` with the panel and returns a view.
--- `chrome` says where things go: { tabsOn, tabsX, tabsY, lineAt, pageTop }.
local function Build(host, chrome)
    local view = { host = host, tab = "appearance", tabs = {}, pages = {} }

    for index = 1, #TABS do
        local tab = TABS[index]
        local button = CreateFrame("Button", nil, chrome.tabsOn)
        button:SetSize(tab.width, 24)
        button:SetPoint("TOPLEFT", chrome.tabsOn, "TOPLEFT", chrome.tabsX + (index - 1) * (TABS[1].width + 4), chrome.tabsY)

        local back = button:CreateTexture(nil, "BORDER")
        back:SetAllPoints(button)
        back:SetColorTexture(0.06, 0.06, 0.08, 1)

        local line = button:CreateTexture(nil, "ARTWORK")
        line:SetPoint(chrome.lineAt .. "LEFT", button, chrome.lineAt .. "LEFT", 0, 0)
        line:SetPoint(chrome.lineAt .. "RIGHT", button, chrome.lineAt .. "RIGHT", 0, 0)
        line:SetHeight(2)
        line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)

        local glow = button:CreateTexture(nil, "HIGHLIGHT")
        glow:SetAllPoints(button)
        glow:SetColorTexture(1, 1, 1, 0.08)

        local label = Label(button, "OVERLAY", "GameFontNormal")
        label:SetPoint("CENTER", button, "CENTER", 0, 0)
        Say(label, tab.label, tab.width - 10)

        button.back, button.line, button.label = back, line, label
        button:SetScript("OnClick", function()
            Sound("IG_CHARACTER_INFO_TAB")
            ns.Guard(view.ShowTab, tab.key)
        end)
        view.tabs[tab.key] = button

        local page = CreateFrame("Frame", nil, host)
        page:SetSize(L.width, L.pageHeight)
        page:SetPoint("TOPLEFT", host, "TOPLEFT", 0, chrome.pageTop)
        page:Hide()
        view.pages[tab.key] = page
    end

    BuildAppearance(view, view.pages.appearance)
    BuildSpells(view, view.pages.spells)

    function view.Refresh()
        for key, button in pairs(view.tabs) do
            local picked = key == view.tab
            button.picked = picked
            Shown(button.back, picked and chrome.backed == true)
            Shown(button.line, picked)
            if picked then
                button.label:SetTextColor(1, 1, 1)
            else
                button.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            end
            Shown(view.pages[key], picked)
        end
        if view.tab == "spells" then
            view.RefreshSpells(false)
        else
            view.RefreshAppearance()
        end
    end

    --- Brings a tab to the front.
    function view.ShowTab(key)
        if not view.pages[key] then
            return
        end
        if key ~= view.tab then
            view.Settle()
        end
        view.tab = key
        if key == "spells" then
            view.RefreshSpells(true)
        end
        view.Refresh()
        Options.UpdateSampling()
    end

    --- Call when the panel comes on screen, and when it leaves.
    function view.Opened()
        Refit() -- a font may only have been ready, or have changed, since the panel was built
        if view.tab == "spells" then
            view.RefreshSpells(true)
        end
        view.Refresh()
        Options.UpdateSampling()
    end

    function view.Closed()
        view.Settle()
        Options.UpdateSampling()
        SaveNotes()
    end

    views[#views + 1] = view
    view.Refresh()
    return view
end

--------------------------------------------------------------------------------
-- Building a copy, and building it again
--------------------------------------------------------------------------------

--- Builds a copy of the panel with `make`, which is handed a list to note the
--- frames it starts on. Should it fail with the game's own controls in it, what
--- it had made is put away and it is run again with nothing but the addon's own
--- drawing, which asks far less of the client; every copy built later this
--- session is drawn that way too. Returns what `make` returned, or nil and the
--- reason when it cannot be built either way.
local function BuildSafely(make)
    local ok, result
    for attempt = 1, 2 do
        local scrap, before = {}, #views
        build = build + 1
        ok, result = pcall(make, scrap)
        if ok and result then
            break
        end
        ok, result = false, ok and "nothing was built" or result
        -- A view registers itself as the last thing it does, but may fail after.
        for i = #views, before + 1, -1 do
            views[i] = nil
        end
        for i = 1, #scrap do
            Try(scrap[i], "Hide")
        end
        for label, made in pairs(fitted) do
            if made == build then
                fitted[label] = nil -- its labels are not worth measuring again
            end
        end
        if attempt == 2 or Plain() then
            break
        end
        notes.rebuilt = Brief(result)
        forcedPlain = true
    end
    if not ok then
        notes.failed = Brief(result)
    end
    pcall(SaveNotes)
    if ok then
        return result
    end
    return nil, tostring(result)
end

--------------------------------------------------------------------------------
-- A window of its own: /se options
--------------------------------------------------------------------------------

local WINDOW_NAME = "StatusEfficiencyOptions"
local window

local POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

--- Puts the window where it was last dragged to, or in the middle of the screen.
local function Place(frame)
    local saved = ns.db.window
    frame:ClearAllPoints()
    if type(saved) == "table" and POINTS[saved.point] and POINTS[saved.relative]
        and type(saved.x) == "number" and type(saved.y) == "number" then
        frame:SetPoint(saved.point, UIParent, saved.relative, saved.x, saved.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

--- Notes where the window is, so that it opens there next time.
local function Remember(frame)
    local point, _, relative, x, y = frame:GetPoint(1)
    point, relative = ns.PlainString(point), ns.PlainString(relative)
    x, y = ns.PlainNumber(x), ns.PlainNumber(y)
    if point and relative and POINTS[point] and POINTS[relative] and x and y then
        local saved = ns.db.window
        if type(saved) ~= "table" then
            saved = {}
            ns.db.window = saved
        end
        saved.point, saved.relative, saved.x, saved.y = point, relative, x, y
    end
end

local function MakeGameClose(holder, parent)
    local button = CreateFrame("Button", nil, parent, "UIPanelCloseButtonNoScripts")
    holder.frame = button
    NeedArt("the game's close button", Ask(button, "GetNormalTexture"))
    button:SetSize(22, 22)
    button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -3, -3)
end

local function BuildWindow(scrap)
    local frame = CreateFrame("Frame", WINDOW_NAME, UIParent)
    scrap[#scrap + 1] = frame
    frame:Hide()
    frame:SetSize(L.width, L.bar + L.pageHeight)
    Place(frame)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ns.Guard(Remember, self)
    end)

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
    bar:SetHeight(L.bar - 1)
    bar:SetColorTexture(0.16, 0.16, 0.2, 1)

    local tabsX = 150
    local caption = Text(frame, "GameFontNormal", TITLE)
    caption:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -8)
    Fit(caption, tabsX - 12 - 8) -- the tabs start where it ends

    local close = Native("close", MakeGameClose, frame)
    if not close then
        close = PlainButton(frame, 22, 20, "X")
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    end
    close:SetScript("OnClick", function()
        Sound("IG_MAINMENU_OPTION_CHECKBOX_OFF")
        frame:Hide()
    end)
    Tip(close, "Close")

    local host = CreateFrame("Frame", nil, frame)
    host:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    host:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    local view = Build(host, { tabsOn = host, tabsX = tabsX, tabsY = -(L.bar - 24), lineAt = "TOP", backed = true,
        pageTop = -L.bar })
    frame:SetScript("OnShow", function()
        ns.Guard(view.Opened)
    end)
    frame:SetScript("OnHide", function()
        ns.Guard(view.Closed)
    end)
    frame.view, frame.close, frame.caption = view, close, caption

    -- Lets the Escape key close it, like the game's own windows.
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = WINDOW_NAME
    end
    return frame
end

--- Opens the settings window, on a tab if one is named ("appearance" or "spells").
function Options.Open(tab)
    if not window then
        local frame, problem = BuildSafely(BuildWindow)
        if not frame then
            -- Not even the addon's own drawing could be made: the commands are what is left.
            ns.Print("the settings window could not be built on this client. The same settings work as "
                .. "commands: /se on, /se when, /se usable, /se corner, /se size, /se icon and /se track. ("
                .. problem .. ")")
            return false
        end
        window = frame
    end
    local view = window.view
    if tab and view.pages[tab] and tab ~= view.tab then
        view.Settle()
        view.tab = tab
    end
    if window:IsShown() then
        ns.Guard(view.Opened)
    else
        window:Show() -- which calls view.Opened
    end
    return true
end

--- Opens the settings window, or closes it if it is open.
function Options.Toggle()
    if window and window:IsShown() then
        window:Hide()
    else
        Options.Open()
    end
end

function Options.Window()
    return window
end

--- Puts the window back where the settings say, after they were reset.
function Options.PlaceWindow()
    if window then
        ns.Guard(Place, window)
    end
end

--------------------------------------------------------------------------------
-- The game's own Options window: Options > AddOns > Status Efficiency
--------------------------------------------------------------------------------

local SMALLEST_PAGE = 0.5 -- how far the whole panel shrinks to fit the page it is given

local function Nothing() end

--- The page's heading, in the style the game uses for its own pages. `page`
--- is the whole page the Options window gives the panel: the game's divider
--- runs across the middle of that, as it does on the game's own pages.
local function BuildHeading(host, page)
    local title
    if Plain() then
        title = Text(host, "GameFontNormalLarge", TITLE)
        title:SetPoint("TOPLEFT", host, "TOPLEFT", 16, -16)
    else
        title = Text(host, "GameFontHighlightHuge", TITLE)
        title:SetPoint("TOPLEFT", host, "TOPLEFT", 7, -22)
    end
    Fit(title, L.width - 32)

    local divider = host:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOP", page, "TOP", 0, -50)
    if Plain() or ns.AtlasExists("Options_HorizontalDivider") == false
        or not Try(divider, "SetAtlas", "Options_HorizontalDivider", true) then
        divider:ClearAllPoints()
        divider:SetPoint("TOPLEFT", host, "TOPLEFT", 12, -50)
        divider:SetSize(L.width - 24, 1)
        divider:SetColorTexture(0.4, 0.4, 0.45, 1)
    end
    return title, divider
end

local function BuildCanvas(host, page)
    local title, divider = BuildHeading(host, page)
    local view = Build(host, { tabsOn = host, tabsX = 12, tabsY = -58, lineAt = "BOTTOM", pageTop = -L.canvasTop })
    view.title, view.divider = title, divider
    return view
end

--- Adds the panel to the game's Options window. Safe to call more than once.
function Options.Register()
    if Options.canvas then
        return
    end
    local ok, problem = pcall(function()
        local canvas = CreateFrame("Frame")
        canvas:Hide()
        Options.canvas = canvas

        local view, host, tried

        --- The panel is laid out for the page this client's Options window was
        --- seen to give it. Given a smaller page, by another client or by an
        --- addon that reshapes the Options window, all of it is drawn smaller.
        local function Rescale()
            local width, height = Measure(canvas, "GetWidth"), Measure(canvas, "GetHeight")
            local scale = 1
            if width and height then
                scale = max(SMALLEST_PAGE, min(1, width / L.width, height / (L.canvasTop + L.pageHeight)))
                notes.page = floor(width + 0.5) .. " x " .. floor(height + 0.5)
            end
            if abs((host.pageScale or 1) - scale) < 0.001 or not Try(host, "SetScale", scale) then
                return false
            end
            host.pageScale, notes.scale = scale, scale
            return true
        end

        canvas:SetScript("OnShow", function()
            if not view and not tried then
                tried = true -- one go: a panel that cannot be built is not built over and over
                local built, reason = BuildSafely(function(scrap)
                    host = CreateFrame("Frame", nil, canvas)
                    scrap[#scrap + 1] = host
                    host:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)
                    host:SetSize(L.width, L.canvasTop + L.pageHeight)
                    return BuildCanvas(host, canvas)
                end)
                if built then
                    view = built
                    canvas.view, canvas.host = view, host
                else
                    -- Not even the addon's own drawing could be made here.
                    Options.problem = reason
                    ns.Print("the settings panel could not be drawn here. /se options opens it in a window "
                        .. "of its own. (" .. reason .. ")")
                end
            end
            if view then
                ns.Guard(Rescale)
                ns.Guard(view.Opened)
            end
        end)
        canvas:SetScript("OnHide", function()
            if view then
                ns.Guard(view.Closed)
            end
        end)
        -- The Options window may only settle on the page's size once it is up.
        canvas:SetScript("OnSizeChanged", function()
            if view and Rescale() and canvas:IsVisible() then
                ns.Guard(view.Refresh)
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
