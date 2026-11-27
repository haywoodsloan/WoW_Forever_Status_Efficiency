-- Status Efficiency: the settings panel.
--
-- Three tabs. "Display" has the on/off switch, when the icons appear and on
-- which skills, where the icon sits on a button and how big it is, with a
-- life-size preview of all three results. "Icons" has which icon each result
-- uses. "Spells" lists the skills on the action bars, and beside the list
-- shows everything about the one that is picked.
--
-- Every setting is a row of its own, laid out the way the game lays out its
-- own Options pages: what the setting is called on the left, the control for
-- it on the right, and rows that belong together under a heading. A screen
-- shows what is needed to decide on one thing at a time: the icons on offer
-- are those of the one result that is picked, and the choices for a spell
-- are those of the one spell that is picked.
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
-- label has, the label is drawn smaller until it fits. The rooms are sized for
-- letters a good third wider than the game's standard font draws them, so
-- that this is the exception.
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
    foot = 34, -- the strip along the bottom of a page

    left = 16, -- where a heading starts
    label = 24, -- where a row's label starts
    control = 220, -- and where its control does

    tile = 30, -- an icon to pick
    tileStep = 34,

    previewMin = 36, -- a pretend button is drawn life-size, within these
    previewMax = 60,

    rows = 12, -- spells shown at once
    rowHeight = 36,
    listTop = -44,
    listLeft = 12,
    listWidth = 244,
    paneLeft = 280, -- where the pane for one spell starts
    paneControl = 400, -- and where the controls in it do
}

local RADIO_LINE = 22 -- one choice of a list of them
local GRID_CELL, GRID_GAP = 20, 2 -- the nine squares that say where the icon sits
local PREVIEW_SLOT, PREVIEW_PITCH = 64, 200 -- the room a pretend button gets, and from one to the next
local SET_WIDTH = 76 -- a set of three icons
local RESULT_HEIGHT, RESULT_ICON = 44, 28 -- one of the three results, and the icon it uses
local EDITOR_BOX = 240 -- the box for a texture of your own
local LIST_ICON, PANE_ICON = 26, 36 -- a skill's picture in the list, and at the head of the pane
local LASTS_BOX, STACKS_BOX = 60, 40
local RESET_WIDTH, DEFAULTS_WIDTH = 150, 96
local MARK_WIDTH, FORGET_WIDTH = 104, 104
-- Where each row of the pane starts, from the pane's top.
local PANE_ROWS = { show = -56, on = -112, lasts = -168, stacks = -198, shared = -228, immune = -288 }

local GOLD = { 1, 0.82, 0 }
local WARN = { 1, 0.6, 0.2 }
local BAD = { 1, 0.35, 0.3 }
local GREY = { 0.6, 0.6, 0.6 }
local DIM = 0.35 -- how faint a control is drawn that has nothing to say right now

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
    { key = "always", label = "Always", words = "always", tip = "Always",
        body = "Whenever there is something to judge: a buff at any time, a debuff whenever there is an enemy to check "
            .. "and all through a fight." },
    { key = "combat", label = "When you are in combat", words = "when you are in combat",
        tip = "When you are in combat",
        body = "Only while you are in combat yourself. The rest of the time your buttons stay bare, even while "
            .. "others in your group are fighting." },
    { key = "group", label = "When you or your group are in combat",
        words = "when you or your group are in combat", tip = "When you or your group are in combat",
        body = "While you are in combat, and while someone in your party or raid is in combat close by. The rest "
            .. "of the time your buttons stay bare." },
}
Options.APPEAR_CHOICES = APPEAR_CHOICES

-- And on which skills: every one, or only those that can be used right now.
local USABLE_CHOICES = {
    { key = "always", label = "Every skill", words = "on every skill", tip = "Every skill",
        body = "Whether or not you can use the skill right now." },
    { key = "usable", label = "Only skills you can use right now",
        words = "only on skills you can use right now", tip = "Only skills you can use right now",
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
    pictures = {}, -- skill -> "none" while the client has no picture for it, "late" once one came after all
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
        controls = {}, fonts = {}, tight = {}, pictures = {},
    }
    for _, name in pairs({ "controls", "fonts", "tight", "pictures" }) do
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
    GameFontHighlightHuge = { "GameFontHighlightLarge", "GameFontNormalLarge", "GameFontHighlight", "GameFontNormal" },
    GameFontHighlightLarge = { "GameFontNormalLarge", "GameFontHighlight", "GameFontNormal" },
    GameFontNormalLarge = { "GameFontHighlightLarge", "GameFontNormal", "GameFontHighlight" },
    GameFontNormal = { "GameFontHighlight", "GameFontNormalSmall", "GameFontHighlightSmall" },
    GameFontHighlight = { "GameFontNormal", "GameFontHighlightSmall", "GameFontNormalSmall" },
    GameFontDisable = { "GameFontHighlight", "GameFontNormal", "GameFontDisableSmall" },
    GameFontNormalSmall = { "GameFontHighlightSmall", "GameFontNormal", "GameFontHighlight" },
    GameFontHighlightSmall = { "GameFontNormalSmall", "GameFontHighlight", "GameFontNormal" },
    GameFontDisableSmall = { "GameFontHighlightSmall", "GameFontNormalSmall", "GameFontDisable", "GameFontNormal" },
}
-- The rest: 10 when small, else 12.
local FONT_HEIGHTS = { GameFontHighlightHuge = 20, GameFontHighlightLarge = 16, GameFontNormalLarge = 16 }

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
    if room > 0 then
        -- On a client whose labels cannot be drawn smaller, one that is too long is cut short at once.
        local scalable = Scale(label, 1)
        local width = Measure(label, "GetUnboundedStringWidth") or Measure(label, "GetStringWidth")
        if width then
            if width > room then
                if scalable then
                    scale = max(SMALLEST, room / width)
                    Scale(label, scale)
                end
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
    if owner.tipLines then
        for i = 1, #owner.tipLines do
            Try(tip, "AddLine", owner.tipLines[i], 0.8, 0.8, 0.8, true)
        end
    end
    tip:Show()
end

local function HideTip()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

--- Gives a frame a tooltip: a title, and optionally a line or two under it.
--- Both can be changed later through frame.tipTitle and frame.tipBody, and
--- frame.tipLines adds a list under them, one line each.
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

--- A tick box of the addon's own drawing, without words: the box, and the mark
--- that shows while it is ticked.
local function OwnTick(parent, size)
    local box = CreateFrame("Button", nil, parent)
    box:SetSize(size, size)

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

    local mark = box:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
    mark:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
    mark:SetTexture(Icons.Choice("check").texture)
    return box, mark
end

--- A tick box with its words beside it: control.Set(ticked), and
--- control.onChange(ticked) is called when a click changes it. control.Fit(room)
--- says how much room the words have, and control.Enable(false) greys it out.
local function TickBox(parent, text, font)
    local control = { ticked = false, enabled = true }

    local mark
    local box = Native("tick", MakeGameTick, parent)
    if box then
        control.native = true
    else
        box, mark = OwnTick(parent, 20)
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

    --- Greys the box out and stops it taking clicks, or brings it back.
    function control.Enable(enabled)
        enabled = enabled and true or false
        control.enabled = enabled
        Try(box, "SetEnabled", enabled)
        Try(box, "SetAlpha", enabled and 1 or DIM)
        Try(label, "SetAlpha", enabled and 1 or DIM)
    end

    box:SetScript("OnClick", function()
        if not control.enabled then
            control.Set(control.ticked) -- a box of the game's that took the click all the same is put back
            return
        end
        local ticked = not control.ticked
        control.Set(ticked) -- the game's own box has flipped itself already; this keeps both kinds in step
        Sound(ticked and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
        if control.onChange then
            ns.Guard(control.onChange, ticked)
        end
    end)

    control.frame, control.label, control.mark = box, label, mark
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
--- control.onPick(key) is called on a click. control.Enable(false) greys the
--- row out. Each choice is { key, label, width, tip, body }.
local function Segmented(parent, choices)
    local control = { buttons = {}, enabled = true }
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
            if control.enabled and control.onPick then
                control.onPick(choice.key)
            end
        end)
        Tip(button, choice.tip, choice.body)
        control.buttons[choice.key] = button
    end
    frame:SetSize(x + 1, 20)

    --- Greys the row out and stops it taking clicks, or brings it back.
    function control.Enable(enabled)
        enabled = enabled and true or false
        control.enabled = enabled
        for _, button in pairs(control.buttons) do
            Try(button, "SetEnabled", enabled)
        end
        Try(frame, "SetAlpha", enabled and 1 or DIM)
    end

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
--- buttons while some copy is open on a tab that is about how the icons look,
--- and the bars read while any copy is open at all (the panel lists them even
--- with the icons off).
function Options.UpdateSampling()
    local open, sampling = false, false
    for i = 1, #views do
        local view = views[i]
        if view.pages[view.tab]:IsVisible() then
            open = true
            sampling = sampling or view.tab ~= "spells"
        end
    end
    ns.SetWatching(open)
    ns.SetSampling(sampling)
end

--------------------------------------------------------------------------------
-- A skill's own picture
--
-- Wherever the panel points at a skill it shows that skill's own picture, the
-- one on its action button. The game is asked for the spell's picture first,
-- and for the picture on the action slot it sits in second. The question mark
-- stands in only while the client gives neither: that is noted, and the skill
-- is asked about again every time the panel is brought up to date, so that a
-- picture the client only has a moment later still shows.
--------------------------------------------------------------------------------

local PICTURES_KEPT = 12
local picturesKept = 0

--- A skill's picture, as something a texture can show, or nil.
local function Picture(info)
    local art = ns.SpellIcon(info.id)
    if not art then
        local slot = ns.BarSlot(info.name)
        art = slot and ns.SlotIcon(slot) or nil
    end
    local noted = notes.pictures[info.name]
    if art then
        if noted == "none" then
            notes.pictures[info.name] = "late" -- the client had none for it at first
        end
    elseif noted == nil and picturesKept < PICTURES_KEPT then
        picturesKept = picturesKept + 1
        notes.pictures[info.name] = "none"
    end
    return art
end

Options.Picture = Picture

--- Shows a skill's picture on a texture, or the question mark for no skill.
local function Wear(texture, info)
    local face = info and Picture(info) or QUESTION
    if texture.wears ~= face then
        texture.wears = face
        texture:SetTexture(face)
    end
end

--- Pictures for the pretend buttons: skills from your own bars, those that get
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
                faces[#faces + 1] = list[i]
            end
        end
    end
    return faces
end

--------------------------------------------------------------------------------
-- Rows
--
-- Every setting is a row of its own: what it is called on the left, the
-- control for it on the right, and under the control, where it helps, a line
-- that says what the setting is doing right now. Rows that belong together
-- stand under a heading.
--------------------------------------------------------------------------------

--- A section's heading.
local function Heading(page, text, top)
    local heading = Text(page, "GameFontHighlightLarge", text)
    heading:SetPoint("TOPLEFT", page, "TOPLEFT", L.left, top)
    Fit(heading, L.right - L.left)
    return heading
end

--- What a setting is called, at the start of its row. With `body` it has a
--- tooltip that says what the setting does.
local function RowLabel(parent, text, left, top, room, body)
    local area = CreateFrame("Frame", nil, parent)
    area:SetSize(room, 20)
    area:SetPoint("TOPLEFT", parent, "TOPLEFT", left, top)
    local label = Text(area, "GameFontNormal", text)
    label:SetJustifyV("MIDDLE")
    label:SetPoint("LEFT", area, "LEFT", 0, 0)
    Fit(label, room)
    if body then
        area:EnableMouse(true)
        Tip(area, text, body)
    end
    area.label = label
    return area
end

--- A line or two of small grey words: what a setting is doing right now.
--- note.Tell(text, colour) changes what it says.
local function Note(parent, width, lines)
    local label = Text(parent, "GameFontHighlightSmall")
    lines = lines or 1
    if lines > 1 then
        label:SetWidth(width)
    end
    function label.Tell(text, colour)
        label:SetText(text or "")
        if lines > 1 then
            FitLines(label, width, lines)
        else
            Fit(label, width)
        end
        Colour(label, colour or GREY)
    end
    label.Tell("")
    return label
end

--- Greys a control out, or brings it back.
local function Dim(region, dimmed)
    Try(region, "SetAlpha", dimmed and DIM or 1)
end

--- A list of choices of which one is picked, one to a line, each with a round
--- mark before it: control.Set(key), and control.onPick(key) is called on a
--- click. control.Enable(false) greys the list out. Each choice is { key,
--- label, tip, body }.
local function RadioList(parent, choices, width)
    local control = { buttons = {}, enabled = true }
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, #choices * RADIO_LINE)
    for i = 1, #choices do
        local choice = choices[i]
        local button = CreateFrame("Button", nil, frame)
        button:SetSize(width, RADIO_LINE)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(i - 1) * RADIO_LINE)

        local glow = button:CreateTexture(nil, "HIGHLIGHT")
        glow:SetAllPoints(button)
        glow:SetColorTexture(1, 1, 1, 0.08)

        -- The mark is two of the addon's own icons: a ring, and a dot in it for the one picked.
        local ring = button:CreateTexture(nil, "ARTWORK")
        ring:SetSize(16, 16)
        ring:SetPoint("LEFT", button, "LEFT", 2, 0)
        ring:SetTexture(Icons.Choice("ring").texture)
        local dot = button:CreateTexture(nil, "OVERLAY")
        dot:SetSize(8, 8)
        dot:SetPoint("CENTER", ring, "CENTER", 0, 0)
        dot:SetTexture(Icons.Choice("yellowdot").texture)

        local label = Label(button, "ARTWORK", "GameFontHighlight")
        label:SetJustifyH("LEFT")
        label:SetPoint("LEFT", button, "LEFT", 24, 0)
        Say(label, choice.label, width - 28)

        button.ring, button.dot, button.label = ring, dot, label
        OnClick(button, function()
            if control.enabled and control.onPick then
                control.onPick(choice.key)
            end
        end)
        Tip(button, choice.tip, choice.body)
        control.buttons[choice.key] = button
    end

    function control.Set(key)
        control.picked = key
        for name, button in pairs(control.buttons) do
            local picked = name == key
            button.picked = picked
            Shown(button.dot, picked)
            Try(button.ring, "SetDesaturated", not picked)
            if picked then
                button.label:SetTextColor(1, 1, 1)
            else
                button.label:SetTextColor(0.75, 0.75, 0.75)
            end
        end
    end

    function control.Enable(enabled)
        enabled = enabled and true or false
        control.enabled = enabled
        for _, button in pairs(control.buttons) do
            Try(button, "SetEnabled", enabled)
        end
        Dim(frame, not enabled)
    end

    control.frame = frame
    control.Set(nil)
    return control
end

--- Nine squares, for the nine places on a button the icon can sit:
--- control.Set(position) marks one, and a click moves the icon there.
local function PositionGrid(parent)
    local control = { zones = {} }
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(3 * GRID_CELL + 2 * GRID_GAP, 3 * GRID_CELL + 2 * GRID_GAP)
    for row = 1, 3 do
        for column = 1, 3 do
            local position = GRID[row][column]
            local zone = CreateFrame("Button", nil, frame)
            zone:SetSize(GRID_CELL, GRID_CELL)
            zone:SetPoint("TOPLEFT", frame, "TOPLEFT", (column - 1) * (GRID_CELL + GRID_GAP),
                -(row - 1) * (GRID_CELL + GRID_GAP))

            local edge = zone:CreateTexture(nil, "BACKGROUND")
            edge:SetAllPoints(zone)
            local back = zone:CreateTexture(nil, "BORDER")
            back:SetPoint("TOPLEFT", zone, "TOPLEFT", 1, -1)
            back:SetPoint("BOTTOMRIGHT", zone, "BOTTOMRIGHT", -1, 1)
            local glow = zone:CreateTexture(nil, "HIGHLIGHT")
            glow:SetAllPoints(zone)
            glow:SetColorTexture(1, 1, 1, 0.25)

            zone.edge, zone.back, zone.row, zone.column = edge, back, row, column
            OnClick(zone, function()
                Change(function()
                    ns.db.corner = position
                end)
            end)
            Tip(zone, POSITION_NAMES[position])
            control.zones[position] = zone
        end
    end

    function control.Set(position)
        control.picked = position
        for name, zone in pairs(control.zones) do
            local picked = name == position
            zone.picked = picked
            if picked then
                zone.edge:SetColorTexture(1, 1, 1, 1)
                zone.back:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
            else
                zone.edge:SetColorTexture(0.35, 0.35, 0.4, 1)
                zone.back:SetColorTexture(0.1, 0.1, 0.13, 1)
            end
        end
    end

    control.frame = frame
    control.Set(nil)
    return control
end

--- The stroke that says "no icon" on a square, or the word for it on a client
--- that draws no lines.
local function Stroke(frame, size)
    local inset = floor(size * 0.27 + 0.5)
    local drawn, stroke = Try(frame, "CreateLine", nil, "ARTWORK")
    if drawn and stroke and Try(stroke, "SetStartPoint", "BOTTOMLEFT", frame, inset, inset)
        and Try(stroke, "SetEndPoint", "TOPRIGHT", frame, -inset, -inset) then
        Try(stroke, "SetThickness", 2)
        Try(stroke, "SetColorTexture", 0.6, 0.6, 0.65, 1)
        return stroke
    end
    local dash = Label(frame, "ARTWORK", "GameFontDisableSmall")
    dash:SetPoint("CENTER", frame, "CENTER", 0, 0)
    Say(dash, "none", size - 4)
    return dash
end

--------------------------------------------------------------------------------
-- The Display tab: whether the icons show, when, on which skills, where on the
-- button and how large
--------------------------------------------------------------------------------

--- One pretend action button, wearing a skill from your own bars, with the icon
--- of one result drawn on it where and as large as it is on the real ones.
local function BuildPreview(view, page, index, state, top)
    local preview = {}
    local left = L.label + (index - 1) * PREVIEW_PITCH

    -- The slot cuts off an icon that is set far larger than the button.
    local slot = CreateFrame("Frame", nil, page)
    slot:SetSize(PREVIEW_SLOT, PREVIEW_SLOT)
    slot:SetPoint("TOPLEFT", page, "TOPLEFT", left, top)
    Try(slot, "SetClipsChildren", true)

    local button = CreateFrame("Frame", nil, slot)
    button:SetPoint("CENTER", slot, "CENTER", 0, 0)
    button:SetSize(45, 45)

    local face = button:CreateTexture(nil, "BACKGROUND")
    face:SetAllPoints(button)
    Try(face, "SetTexCoord", 0.07, 0.93, 0.07, 0.93) -- trims the picture's own border, as action buttons do
    Wear(face, nil)

    -- The icon is drawn above the picture, on a frame of its own, as on the real buttons.
    local above = CreateFrame("Frame", nil, button)
    above:SetAllPoints(button)
    above:SetFrameLevel(button:GetFrameLevel() + 5)
    local icon = above:CreateTexture(nil, "OVERLAY")

    -- What the result is called, beside its button: two lines if it comes to that.
    local room = PREVIEW_PITCH - PREVIEW_SLOT - 8 - 12
    local caption = Text(page, "GameFontHighlightSmall", state.title)
    caption:SetJustifyV("MIDDLE")
    caption:SetWidth(room)
    caption:SetPoint("LEFT", slot, "RIGHT", 8, 0)
    FitLines(caption, room, 2)

    slot:EnableMouse(true)
    Tip(slot, state.title, state.detail)

    preview.slot, preview.button, preview.face, preview.icon, preview.caption = slot, button, face, icon, caption
    return preview
end

local function BuildDisplay(view, page)
    view.previews = {}
    local labelRoom = L.control - L.label - 10
    local wide = L.right - L.control

    Heading(page, "Visibility", -12)

    RowLabel(page, "Show status icons", L.label, -40, labelRoom,
        "The icons this addon puts on your action buttons. Unticked, your buttons stay bare.")
    local enable = TickBox(page, "")
    enable.frame:SetPoint("LEFT", page, "TOPLEFT", L.control, -50)
    enable.onChange = function(ticked)
        ns.SetEnabled(ticked)
        Options.RefreshAll()
    end
    Tip(enable.frame, "Show status icons")
    view.enable = enable
    local off = Note(page, wide - 40)
    off:SetPoint("LEFT", page, "TOPLEFT", L.control + 40, -50)
    view.off = off

    RowLabel(page, "When to show them", L.label, -70, labelRoom,
        "The icons can stay away until there is a fight, so that your buttons are bare the rest of the time.")
    local appear = RadioList(page, APPEAR_CHOICES, wide)
    appear.frame:SetPoint("TOPLEFT", page, "TOPLEFT", L.control, -69)
    appear.onPick = function(key)
        Change(function()
            ns.SetAppear(key)
        end)
    end
    view.appear = appear

    RowLabel(page, "On which skills", L.label, -144, labelRoom,
        "A skill the game will not let you use right now can go without its icon.")
    local usable = RadioList(page, USABLE_CHOICES, wide)
    usable.frame:SetPoint("TOPLEFT", page, "TOPLEFT", L.control, -143)
    usable.onPick = function(key)
        Change(function()
            ns.SetUsableOnly(key == "usable")
        end)
    end
    view.usable = usable
    local usableNote = Note(page, wide - 24, 2)
    usableNote:SetPoint("TOPLEFT", page, "TOPLEFT", L.control + 24, -189)
    view.usableNote = usableNote

    Heading(page, "Position and size", -224)

    -- Where on a button: nine squares, laid out like the button itself.
    local grid = PositionGrid(page)
    grid.frame:SetPoint("TOPLEFT", page, "TOPLEFT", L.control, -252)
    local gridHeight = 3 * GRID_CELL + 2 * GRID_GAP
    RowLabel(page, "Position", L.label, -252 - (gridHeight - 20) / 2, labelRoom,
        "Where on each action button the icon sits. Click one of the nine squares.")
    local where = Text(page, "GameFontHighlight")
    where:SetJustifyV("MIDDLE")
    where:SetPoint("LEFT", grid.frame, "RIGHT", 12, 0)
    view.grid, view.zones, view.where = grid, grid.zones, where

    -- How large: a slider, or follow the button.
    RowLabel(page, "Size", L.label, -328, labelRoom, "How large the icon is drawn, from " .. ns.SIZE_MIN .. " to "
        .. ns.SIZE_MAX .. ". Auto sizes it from the button it sits on.")
    local slider = NumberSlider(page, 200, ns.SIZE_MIN, ns.SIZE_MAX)
    slider.frame:SetPoint("TOPLEFT", page, "TOPLEFT", L.control, -328)
    slider.onChange = function(value)
        Change(function()
            ns.db.size = value
        end)
    end

    local readout = Text(page, "GameFontHighlight")
    readout:SetJustifyH("CENTER")
    readout:SetJustifyV("MIDDLE")
    readout:SetPoint("CENTER", slider.frame, "RIGHT", 20, 0)

    local auto = TickBox(page, "Auto")
    auto.frame:SetPoint("LEFT", slider.frame, "RIGHT", 44, 0)
    auto.Fit(L.right - (L.control + 200 + 44) - Wide(auto.frame, 30) - 4)
    auto.onChange = function(ticked)
        Change(function()
            -- Unticked, the icon stays the size it was, as a size of its own.
            ns.db.size = ticked and 0 or max(ns.SIZE_MIN, min(ns.SIZE_MAX, ns.AutoIconSize()))
        end)
    end
    Tip(auto.frame, "Auto", "Size the icon from the button it sits on.")
    view.size = { slider = slider, readout = readout, auto = auto }

    local sizeNote = Note(page, wide)
    sizeNote:SetPoint("TOPLEFT", page, "TOPLEFT", L.control, -352)
    view.sizeNote = sizeNote

    -- A pretend button for each result.
    Heading(page, "Preview", -380)
    for index = 1, #Icons.STATES do
        local state = Icons.STATES[index]
        view.previews[state.key] = BuildPreview(view, page, index, state, -406)
    end

    --- The pretend buttons wear pictures of skills on your own bars.
    local function RefreshFaces()
        local faces = PreviewFaces()
        for index = 1, #Icons.STATES do
            Wear(view.previews[Icons.STATES[index].key].face, faces[index])
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

    function view.RefreshDisplay()
        local on = ns.db.enabled and true or false
        enable.Set(on)
        off.Tell(on and "" or "Off: your action buttons stay bare.")
        appear.Set(ns.db.appear)
        usable.Set(ns.db.usableOnly and "usable" or "always")
        -- Neither changes anything while the icons are off.
        appear.Enable(on)
        usable.Enable(on)
        usableNote.Tell(ns.db.usableOnly
            and "Being short of rage, mana or energy does not hide an icon, and neither does a cooldown." or "")
        Dim(usableNote, not on)

        local corner = ns.db.corner
        grid.Set(corner)
        Say(where, POSITION_NAMES[corner] or "", L.right - (L.control + gridHeight + 12))

        -- Size: the slider sits at the size in use, chosen or not.
        local chosen = ns.db.size
        local size = chosen > 0 and chosen or ns.AutoIconSize()
        slider.Set(max(ns.SIZE_MIN, min(ns.SIZE_MAX, size)))
        Say(readout, tostring(size), 36)
        auto.Set(chosen == 0)
        sizeNote.Tell(chosen == 0 and "Sized from the button it sits on." or "The same size on every button.")

        -- The pretend buttons are as large as a real one looks from here, so the
        -- icon on them is the size it is on the bars.
        local width, ratio = ns.TypicalButton(page)
        local side = max(L.previewMin, min(L.previewMax, width * ratio))
        local scale = side / width
        local offset = ns.CORNERS[corner] or ns.CORNERS.TOPLEFT
        RefreshFaces()
        for index = 1, #Icons.STATES do
            local key = Icons.STATES[index].key
            local preview = view.previews[key]
            preview.button:SetSize(side, side)
            local art = Icons.Texture(key)
            if art then
                preview.icon:SetTexture(art)
                preview.icon:SetSize(size * scale, size * scale)
                preview.icon:ClearAllPoints()
                preview.icon:SetPoint(corner, preview.button, corner, offset[1] * scale, offset[2] * scale)
            end
            Shown(preview.icon, art ~= nil)
        end

        view.Foot(on and "Out of combat, your action buttons show sample icons while this tab is open."
            or "Status icons are turned off, so your action buttons show none.")
    end
end

--------------------------------------------------------------------------------
-- The Icons tab: which icon each of the three results uses
--------------------------------------------------------------------------------

--- The box for a texture of your own: somewhere to type, and a line that says
--- what to type or what went wrong. It belongs to whichever result is picked.
local function BuildEditor(view, page, left, top)
    local editor = CreateFrame("Frame", nil, page)
    editor:SetSize(L.right - left, 24)
    editor:SetPoint("TOPLEFT", page, "TOPLEFT", left, top)
    editor:Hide()

    local room = L.right - left - EDITOR_BOX - 14
    local note = Note(editor, room, 2)
    note:SetPoint("TOPLEFT", editor, "TOPLEFT", EDITOR_BOX + 14, 0)

    local function Apply(box)
        local key = view.picked
        local text = box:GetText() or ""
        if not text:find("%S") then
            -- Emptied: back to the usual icon if this result was on a texture of its own.
            box:ClearFocus()
            view.editing = nil
            if Icons.Current(key) == "custom" then
                Change(function()
                    Icons.Set(key, nil)
                end)
            else
                view.Refresh()
            end
            return
        end
        local texture = Icons.ParseCustom(text)
        if not texture then
            editor.problem = true
            note.Tell("Not a texture. Type a file ID such as 136243, or a path that starts with Interface.", BAD)
            return
        end
        box:ClearFocus()
        Change(function()
            Icons.SetCustom(key, texture)
        end)
    end

    local built, box = pcall(Input, editor, EDITOR_BOX)
    if built and box then
        box:SetPoint("TOPLEFT", editor, "TOPLEFT", 1, -1)
        box:SetScript("OnEnterPressed", function(self)
            ns.Guard(Apply, self)
        end)
        box:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            if Icons.Current(view.picked) ~= "custom" then
                view.editing = nil
            end
            ns.Guard(view.Refresh)
        end)
        editor.box = box
    end

    --- Brings the box in line with the settings. `missing` says that the game
    --- has no texture where the player's own one points.
    function editor.Refresh(current, custom, missing)
        local key = view.picked
        local open = current == "custom" or view.editing == key
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
            note.Tell("/se icon " .. key .. " <file ID or path>")
        elseif editor.missing then
            note.Tell("The game has no texture there, so no icon shows.", WARN)
        elseif current == "custom" then
            note.Tell("In use. Empty the box and press Enter to undo.")
        else
            note.Tell("A file ID or a path, then Enter.")
        end
    end

    editor.note = note
    return editor
end

--- One result: the icon it uses now, what it is called and what it means. A
--- click picks it, and the icons under the three are then on offer for it.
local function BuildResult(view, page, index, state, top)
    local key = state.key
    local width = L.right - L.left

    local row = CreateFrame("Button", nil, page)
    row:SetSize(width, RESULT_HEIGHT - 2)
    row:SetPoint("TOPLEFT", page, "TOPLEFT", L.left, top - (index - 1) * RESULT_HEIGHT)

    local chosen = row:CreateTexture(nil, "BACKGROUND")
    chosen:SetAllPoints(row)
    chosen:SetColorTexture(0.24, 0.2, 0.08, 0.8)
    local bar = row:CreateTexture(nil, "BORDER")
    bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    bar:SetWidth(3)
    bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    local glow = row:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints(row)
    glow:SetColorTexture(1, 1, 1, 0.07)

    -- The icon in use, on a dark square that stays when the result has none.
    local box = CreateFrame("Frame", nil, row)
    box:SetSize(RESULT_ICON, RESULT_ICON)
    box:SetPoint("LEFT", row, "LEFT", 10, 0)
    local back = box:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(box)
    back:SetColorTexture(0.1, 0.1, 0.12, 1)
    local icon = box:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
    local none = Stroke(box, RESULT_ICON)

    local textLeft = 10 + RESULT_ICON + 10
    local name = Text(row, "GameFontNormal", state.title)
    name:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -6)
    Fit(name, 220)
    local detail = Text(row, "GameFontHighlightSmall", state.detail)
    detail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", textLeft, 7)
    Fit(detail, width - textLeft - 8)

    -- Says so when this result cannot be told from an earlier one.
    local clash = Text(row, "GameFontHighlightSmall")
    clash:SetJustifyH("RIGHT")
    clash:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -8)
    Colour(clash, WARN)
    clash:Hide()

    OnClick(row, function()
        view.Pick(key)
    end)
    Tip(row, state.title, "Click to choose its icon below.")

    row.chosen, row.bar, row.icon, row.none = chosen, bar, icon, none
    view.results[key], view.current[key] = row, icon
    view.names[key], view.details[key], view.clashes[key] = name, detail, clash
end

local function BuildIcons(view, page)
    view.sets, view.current, view.clashes, view.names, view.details = {}, {}, {}, {}, {}
    view.results, view.tiles = {}, {}
    view.picked = Icons.STATES[1].key -- the result whose icons are on offer
    view.editing = nil -- the result for which the box for a texture of your own is open, before one is in use

    -- Sets: all three icons in one click.
    Heading(page, "Icon set", -12)
    for index = 1, #Icons.SETS do
        local set = Icons.SETS[index]
        local button = CreateFrame("Button", nil, page)
        button:SetSize(SET_WIDTH, 30)
        button:SetPoint("TOPLEFT", page, "TOPLEFT", L.label + (index - 1) * (SET_WIDTH + 8), -40)

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
            view.editing = nil
            Change(function()
                Icons.ApplySet(set)
            end)
        end)
        Tip(button, set.name, "Uses these three icons for the three results.")
        view.sets[set.key] = button
    end
    -- Which set is in use, in words, beside the four.
    local setLeft = L.label + #Icons.SETS * (SET_WIDTH + 8) + 6
    local setName = Note(page, L.right - setLeft, 2)
    setName:SetJustifyV("MIDDLE")
    setName:SetPoint("LEFT", page, "TOPLEFT", setLeft, -55)
    view.setName = setName

    -- The three results. One of them is picked, and its icons are on offer below.
    Heading(page, "One icon for each result", -88)
    local hint = Note(page, L.right - L.label)
    hint:SetPoint("TOPLEFT", page, "TOPLEFT", L.label, -110)
    hint.Tell("Pick a result, then the icon it should use.")
    view.hint = hint
    for index = 1, #Icons.STATES do
        BuildResult(view, page, index, Icons.STATES[index], -130)
    end

    local gridTop = -130 - #Icons.STATES * RESULT_HEIGHT - 14
    local offer = Text(page, "GameFontNormal")
    offer:SetPoint("TOPLEFT", page, "TOPLEFT", L.label, gridTop)
    view.offer = offer

    -- The icons: the addon's own on the first line, with "no icon" and "your
    -- own" after them, and the game's on the second.
    local tiles = view.tiles
    local tilesTop = gridTop - 22
    local own, game = 0, 0
    for i = 1, #Icons.CHOICES do
        local choice = Icons.CHOICES[i]
        local column, line
        if choice.own then
            column, line, own = own, 0, own + 1
        else
            column, line, game = game, 1, game + 1
        end
        local tile = Tile(page, L.tile)
        tile:SetPoint("TOPLEFT", page, "TOPLEFT", L.label + column * L.tileStep, tilesTop - line * L.tileStep)
        tile.art:SetTexture(choice.texture)
        OnClick(tile, function()
            view.editing = nil
            Change(function()
                Icons.Set(view.picked, choice.key)
            end)
        end)
        Tip(tile, choice.name)
        tiles[choice.key] = tile
    end

    -- No icon at all: a bare tile with a stroke through it.
    local hidden = Tile(page, L.tile)
    hidden:SetPoint("TOPLEFT", page, "TOPLEFT", L.label + own * L.tileStep, tilesTop)
    Stroke(hidden, L.tile)
    OnClick(hidden, function()
        view.editing = nil
        Change(function()
            Icons.SetHidden(view.picked)
        end)
    end)
    Tip(hidden, Icons.HIDDEN_NAME, "Buttons stay bare for this result.")
    tiles[Icons.HIDDEN] = hidden

    -- A texture of your own: the tile opens a box to type it into.
    local editor = BuildEditor(view, page, L.label, tilesTop - 2 * L.tileStep - 8)
    local custom = Tile(page, L.tile)
    custom:SetPoint("TOPLEFT", page, "TOPLEFT", L.label + (own + 1) * L.tileStep, tilesTop)
    local dots = Label(custom, "ARTWORK", "GameFontHighlight")
    dots:SetPoint("CENTER", custom, "CENTER", 0, 3)
    Say(dots, "...", L.tile - 4)
    custom.dots = dots
    OnClick(custom, function()
        view.editing = view.picked
        view.Refresh()
        if editor.box then
            editor.box:SetFocus()
        end
    end)
    Tip(custom, "Your own texture", "Any picture in the game, by file ID or by path.")
    tiles.custom = custom
    view.editor, view.input = editor, editor.box

    --- Picks the result whose icons are on offer.
    function view.Pick(key)
        if not view.results[key] then
            return
        end
        if key ~= view.picked then
            -- What was being typed for the other result is put away. (A box
            -- that is not being typed into forgets its complaint by itself.)
            view.editing = nil
            if editor.box then
                editor.box:ClearFocus()
            end
        end
        view.picked = key
        view.Refresh()
    end

    function view.RefreshIcons()
        local set = Icons.CurrentSet()
        for setKey, button in pairs(view.sets) do
            local picked = set ~= nil and set.key == setKey
            if picked then
                button.ring:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
            else
                button.ring:SetColorTexture(0.35, 0.35, 0.4, 1)
            end
            button.picked = picked
        end
        setName.Tell(set and set.name or "A mix of your own.")

        for index = 1, #Icons.STATES do
            local state = Icons.STATES[index]
            local key = state.key
            local row = view.results[key]
            local picked = key == view.picked
            row.picked = picked
            Shown(row.chosen, picked)
            Shown(row.bar, picked)

            local current = Icons.Current(key)
            local art = Icons.Texture(key)
            if art then
                row.icon:SetTexture(art)
            end
            Shown(row.icon, art ~= nil)
            Shown(row.none, current == Icons.HIDDEN)

            local clash = view.clashes[key]
            local other = Icons.SharedWith(key)
            if other then
                Say(clash, "Same icon as \"" .. other.title .. "\"", 280)
            end
            Shown(clash, other ~= nil)
        end

        -- The icons on offer are for the result that is picked.
        local key = view.picked
        local current, custom = Icons.Current(key)
        Say(offer, "Icon for \"" .. Icons.State(key).title .. "\"", L.right - L.label)
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
        editor.Refresh(current, custom, missing)

        view.Foot(ns.db.enabled and "Out of combat, your action buttons show sample icons while this tab is open."
            or "Status icons are turned off, so your action buttons show none.")
    end
end

--------------------------------------------------------------------------------
-- The Skills tab: the skills on your bars in a list, and beside it everything
-- about the one that is picked
--------------------------------------------------------------------------------

local SHOW_CHOICES = {
    { key = "auto", label = "Auto", width = 50, tip = "Let the addon decide",
        body = "It gets an icon when it looks like it leaves a status effect, and loses it if casts keep leaving nothing behind." },
    { key = "always", label = "Always", width = 64, tip = "Always show an icon" },
    { key = "never", label = "Never", width = 58, tip = "Never show an icon" },
}

local ON_CHOICES = {
    { key = "target", label = "Your target", width = 88, tip = "A debuff on your target",
        body = "Judged on the enemy you have targeted.", note = "The enemy you have targeted.",
        short = "Your target" },
    { key = "all", label = "All enemies", width = 88, tip = "A debuff on every enemy in the fight",
        body = "Judged on all of them, so the icon can also say that only some have it.",
        note = "Every enemy in the fight: some may have it, some not.", short = "All enemies" },
    { key = "self", label = "You", width = 46, tip = "A buff on you",
        body = "Or on the friend you have targeted, if the skill can be cast on others.",
        note = "You, or a friend you have targeted.", short = "On you" },
}

local ON_BY_KEY = {}
for i = 1, #ON_CHOICES do
    ON_BY_KEY[ON_CHOICES[i].key] = ON_CHOICES[i]
end

-- Why a spell is treated the way it is: a sentence for the pane, and a longer
-- one for the tooltip where there is more to say.
local WHY = {
    you = { "You chose Always." },
    ignored = { "You chose Never." },
    seen = {
        debuff = { "Its debuff has been seen on an enemy.", "Its debuff has been read off an enemy." },
        buff = { "Its buff has been seen on you.", "Its buff has been read off you." },
    },
    ["built-in"] = { "A well known area debuff." },
    tooltip = {
        debuff = { "Cast on enemies, and its tooltip gives a duration.",
            "It can be cast on enemies and its tooltip mentions a duration." },
        buff = { "Cast on you or friends, and its tooltip gives a duration.",
            "It is cast on yourself or on friends and its tooltip mentions a duration." },
    },
}

-- Where a figure comes from: a few words beside its box, and a sentence for the tooltip.
local DURATION_WHY = {
    you = { "You set this.", "You set this." },
    seen = { "Seen in play.", "Read off the effect itself in play." },
    tooltip = { "From the tooltip.", "Taken from the skill's tooltip." },
    guess = { "A guess so far.", "A guess: nothing better is known yet." },
}

-- What was seen on a unit is the weakest of them: the effect may go higher
-- than it has been seen to.
local STACKS_WHY = {
    you = { "You set this.", "You set this." },
    tooltip = { "From the tooltip.", "Taken from the skill's tooltip." },
    game = { "The game's own figure.", "The game's own figure for the skill." },
    seen = { "The most seen so far.", "The most seen on a unit so far, so the effect may go higher." },
}

--- What the box for an effect's stacks says when the mouse is on it.
local function StacksTip(info)
    local user = ns.db.spells[info.name]
    local auto = " or empty the box to let the addon work it out."
    if Spells:Stacking(info) then
        local why = STACKS_WHY[Spells:StackingSource(info)]
        return (why and why[2] or "By what is known of the skill.")
            .. " A unit only counts as having the effect once it has that many stacks: until then the skill stays "
            .. "worth casting. Type another number to change it, 1 if the effect does not stack," .. auto
    elseif user and type(user.stacks) == "number" then
        return "You set this: the effect does not stack. Type the most stacks it can have to change it," .. auto
    end
    return "Nothing says that the effect stacks. If it does, type the most stacks it can have."
end

--- Where the answer to "does another player's copy count" comes from.
local function SharedSource(info)
    local user = ns.db.spells[info.name]
    if user and user.shared ~= nil then
        return "You set this."
    elseif info.described ~= true then
        return "The tooltip could not be read."
    end
    return "From the tooltip."
end

--- And what the tick for it says when the mouse is on it.
local function SharedTip(info, shared)
    local user = ns.db.spells[info.name]
    local source = " This is what the addon made of the skill's tooltip."
    if user and user.shared ~= nil then
        source = " You set this."
    elseif info.described ~= true then
        source = " The skill's tooltip could not be read, so its effect is taken to be yours alone."
    end
    if shared then
        return "A unit carries the effect only once, whoever casts it, so another player's copy counts like your own. "
            .. "Untick this if every caster has their own, as with a bleed." .. source
    end
    return "Only an effect you put there yourself counts. Tick this if a unit carries the effect only once, whoever "
        .. "casts it, so that another player's copy counts like your own." .. source
end

local NO_KINDS = {}

-- Why Add target could not add anything: what /se immune says then, in short.
local MARK_WHY = {
    target = "Target the creature first.",
    player = "That is a player. Only creatures can be added.",
    hidden = "The game will not say what kind of creature that is right now. Try again after the fight.",
}
local MARK_UNSAID = "That could not be added." -- for a reason this panel has no words for

local IMMUNE_ROOM = 80 -- letters of kinds in the pane: three lines of it, also in a font a third wider
local IMMUNE_NAMED = 6 -- at most this many names of either sort are tried
local IMMUNE_LISTED = 30 -- kinds named in the tooltip

--- The first `shown` names of a list of kinds, and how many it leaves out:
--- "Fire Elemental, Rock Elemental and 3 more".
local function Named(list, shown)
    local names = {}
    for i = 1, shown do
        names[i] = list[i].name
    end
    local more = #list - shown
    return concat(names, ", ") .. (more > 0 and (" and " .. more .. " more") or "")
end

--- The kinds of creature a skill does nothing to, as a line for the pane: the
--- ones the addon counts on first, then the ones the game called immune only
--- once. As many names as there is room for, the ones it counts on before
--- the others.
local function ImmuneLine(kinds)
    if #kinds == 0 then
        return "None known yet."
    end
    local sure, once = {}, {}
    for i = 1, #kinds do
        local into = kinds[i].sure and sure or once
        into[#into + 1] = kinds[i]
    end
    local a, b = min(#sure, IMMUNE_NAMED), min(#once, IMMUNE_NAMED)
    while true do
        local line = a > 0 and (Named(sure, a) .. ".") or ""
        if b > 0 then
            line = line .. (a > 0 and " " or "") .. "Heard once: " .. Named(once, b) .. "."
        end
        if #line <= IMMUNE_ROOM or (a <= 1 and b <= 1) then
            return line
        end
        if b > 1 then
            b = b - 1
        else
            a = a - 1
        end
    end
end

--- The same as lines for a tooltip: every kind, and how the addon came by it.
local function ImmuneLines(kinds)
    local lines = {}
    for i = 1, min(#kinds, IMMUNE_LISTED) do
        local kind = kinds[i]
        lines[i] = kind.name .. (kind.told and " (you said so)" or (kind.sure and "" or " (heard once)"))
    end
    if #kinds > IMMUNE_LISTED then
        lines[#lines + 1] = "and " .. (#kinds - IMMUNE_LISTED) .. " more"
    end
    return lines
end

--- Greys a push button out and stops it taking clicks, or brings it back.
local function Able(button, enabled)
    Try(button, "SetEnabled", enabled)
    if not button.native then
        Dim(button, not enabled)
    end
end

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

--- Why a spell has an icon or has none: a sentence, and a longer one.
local function WhyText(info, tracked, source, kind)
    local why = WHY[source]
    if why and not why[1] then
        why = why[kind]
    end
    if why then
        return why[1], why[2] or why[1]
    end
    local casts, hits = Spells:Record(info.name, kind)
    casts, hits = floor(casts + 0.5), floor(hits + 0.5)
    if source == "learned" then
        return hits .. " of " .. casts .. " casts left an effect behind.",
            "A new effect of yours followed " .. hits .. " of " .. casts .. " casts."
    elseif source == "demoted" then
        return "Nothing followed " .. (casts - hits) .. " of " .. casts .. " casts, so it lost its icon.",
            "No new effect of yours followed " .. (casts - hits) .. " of " .. casts
                .. " casts, so it lost its icon. Pick Always to give it back."
    end
    return "It does not look like it leaves a status effect.",
        "It does not look like it leaves a status effect. Pick Always if it does."
end

--- A spell in a few words, for its line in the list: who its effect is judged
--- on and how long that lasts, or that it has no icon.
local function Summary(info)
    local tracked, area, duration, _, kind = Spells:Tracking(info)
    if not tracked then
        return "No icon", false
    end
    local on = ON_BY_KEY[kind == "buff" and "self" or (area and "all" or "target")]
    return on.short .. ", " .. Short(duration), true
end

--- Takes your own choices for a skill away again. What the addon is following
--- of its effect stays, like what it learned in play, except another player's
--- copy that only counted because of those choices. `info` is nil for a skill
--- that is off the bars, where nothing says what its choices decided.
local function Unchoose(name, info)
    local counted = info == nil or Spells:Shared(info)
    ns.db.spells[name] = nil
    if counted and (info == nil or not Spells:Shared(info)) then
        Tracker:ForgetTheirs(name)
    end
end

--- One line of the list: the skill's picture, its name, and how it is treated.
local function BuildListRow(view, page, index)
    local row = CreateFrame("Button", nil, page)
    row:SetSize(L.listWidth, L.rowHeight)
    row:SetPoint("TOPLEFT", page, "TOPLEFT", L.listLeft, L.listTop - (index - 1) * L.rowHeight)
    row:Hide()

    if index % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints(row)
        stripe:SetColorTexture(1, 1, 1, 0.04)
    end
    local chosen = row:CreateTexture(nil, "BORDER")
    chosen:SetAllPoints(row)
    chosen:SetColorTexture(0.24, 0.2, 0.08, 0.9)
    local bar = row:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    bar:SetWidth(3)
    bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    local glow = row:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints(row)
    glow:SetColorTexture(1, 1, 1, 0.08)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(LIST_ICON, LIST_ICON)
    icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    Try(icon, "SetTexCoord", 0.07, 0.93, 0.07, 0.93)

    local textLeft = 8 + LIST_ICON + 8
    local room = L.listWidth - textLeft - 6
    local name = Text(row, "GameFontHighlight")
    name:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -4)
    local status = Text(row, "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", textLeft, 4)

    OnClick(row, function()
        if row.info then
            view.Select(row.info.name)
        end
    end)

    --- Shows a spell in this line, or nothing.
    function row.Bind(info, selected)
        row.info = info
        Shown(row, info ~= nil)
        if not info then
            return
        end
        local summary, tracked = Summary(info)
        Wear(icon, info)
        Try(icon, "SetDesaturated", not tracked)
        icon:SetAlpha(tracked and 1 or 0.6)
        Say(name, info.name, room)
        if tracked then
            name:SetTextColor(1, 1, 1)
        else
            name:SetTextColor(0.6, 0.6, 0.6)
        end
        Say(status, summary, room)
        if tracked then
            status:SetTextColor(0.8, 0.8, 0.8)
        else
            status:SetTextColor(0.5, 0.5, 0.5)
        end
        row.selected = selected
        Shown(chosen, selected)
        Shown(bar, selected)
    end

    row.icon, row.name, row.status, row.chosen = icon, name, status, chosen
    return row
end

--- Everything about one spell: whether it gets an icon and why, who its effect
--- is judged on, how long that lasts, how often it stacks, whether another
--- player's copy counts, and which kinds of creature it does nothing to.
local function BuildPane(view, page)
    local width = L.right - L.paneLeft
    local control = L.paneControl - L.paneLeft -- where the controls start, from the pane's left edge
    local wide = width - control
    local labelRoom = control - 8

    local pane = CreateFrame("Frame", nil, page)
    pane:SetSize(width, L.rows * L.rowHeight)
    pane:SetPoint("TOPLEFT", page, "TOPLEFT", L.paneLeft, L.listTop)
    pane:Hide()

    -- Which spell it is.
    local icon = pane:CreateTexture(nil, "ARTWORK")
    icon:SetSize(PANE_ICON, PANE_ICON)
    icon:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
    Try(icon, "SetTexCoord", 0.07, 0.93, 0.07, 0.93)
    local nameRoom = width - PANE_ICON - 10
    local name = Text(pane, "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", pane, "TOPLEFT", PANE_ICON + 10, -2)
    local summary = Note(pane, nameRoom)
    summary:SetPoint("TOPLEFT", pane, "TOPLEFT", PANE_ICON + 10, -22)
    local rule = pane:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -(PANE_ICON + 8))
    rule:SetSize(width, 1)
    rule:SetColorTexture(0.4, 0.4, 0.45, 1)

    --- Says what is wrong with what was typed, beside the box it was typed
    --- into, until it is put right.
    local function Complain(at, problem)
        pane.problem, pane.problemAt = problem, at
        ns.Guard(view.Refresh)
    end

    local function Settled()
        pane.problem, pane.problemAt = nil, nil
    end

    -- Whether it gets an icon.
    local showArea = RowLabel(pane, "Show an icon", 0, PANE_ROWS.show, labelRoom,
        "Auto lets the addon decide: a skill gets an icon when it looks like it leaves a status effect, and "
            .. "loses it if casts keep leaving nothing behind.")
    local show = Segmented(pane, SHOW_CHOICES)
    show.frame:SetPoint("TOPLEFT", pane, "TOPLEFT", control, PANE_ROWS.show)
    show.onPick = function(key)
        local info = pane.info
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
    local why = Note(pane, wide, 2)
    why:SetPoint("TOPLEFT", pane, "TOPLEFT", control, PANE_ROWS.show - 24)
    -- The mouse on the reason spells it out.
    local whyArea = CreateFrame("Frame", nil, pane)
    whyArea:SetSize(wide, 26)
    whyArea:SetPoint("TOPLEFT", pane, "TOPLEFT", control, PANE_ROWS.show - 23)
    whyArea:EnableMouse(true)
    Tip(whyArea, nil)

    -- Who its effect is judged on.
    RowLabel(pane, "Lands on", 0, PANE_ROWS.on, labelRoom,
        "Who the effect is looked for on. That decides what the icon can say: only a debuff judged on every "
            .. "enemy can be on some of them and not on others.")
    local on = Segmented(pane, ON_CHOICES)
    on.frame:SetPoint("TOPLEFT", pane, "TOPLEFT", control, PANE_ROWS.on)
    on.onPick = function(key)
        local info = pane.info
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
    local onNote = Note(pane, wide, 2)
    onNote:SetPoint("TOPLEFT", pane, "TOPLEFT", control, PANE_ROWS.on - 24)

    -- How long the effect lasts.
    local function ApplyDuration(box)
        local info = pane.info
        if not info then
            return
        end
        local text = (box:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text == box.before then
            -- Enter on what was already there: nothing was changed, so nothing
            -- is. Above all the addon's own figure does not become yours.
        elseif text == "" or text:lower() == "auto" then
            local choice = ns.db.spells[info.name]
            if choice then
                choice.duration = nil
                Spells:Tidy(info.name)
            end
        else
            local seconds = ParseSpan(text)
            if not seconds or seconds < Spells.MIN_DURATION or seconds > Spells.MAX_DURATION then
                Complain("lasts", "Type seconds, from " .. Spells.MIN_DURATION .. " to " .. Spells.MAX_DURATION .. ".")
                return
            end
            Spells:Choice(info.name).duration = seconds
        end
        Settled()
        box:ClearFocus()
        SpellChanged()
    end

    RowLabel(pane, "Lasts", 0, PANE_ROWS.lasts, labelRoom,
        "How long the effect is taken to last when it cannot be watched. Type a number of seconds to change it, "
            .. "or empty the box to let the addon work it out.")
    local built, lasts = pcall(Input, pane, LASTS_BOX)
    if built and lasts then
        lasts:SetPoint("TOPLEFT", pane, "TOPLEFT", control + 1, PANE_ROWS.lasts)
        Try(lasts, "SetJustifyH", "CENTER")
        lasts:SetMaxLetters(12)
        lasts:SetScript("OnEditFocusGained", function(self)
            -- Typing starts from the bare number of seconds.
            local info = pane.info
            if info then
                local _, _, duration = Spells:Tracking(info)
                self.before = tostring(floor(duration + 0.5))
                self:SetText(self.before)
                Try(self, "HighlightText")
            end
        end)
        lasts:SetScript("OnEditFocusLost", function(self)
            Try(self, "HighlightText", 0, 0)
            Settled()
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
    local lastsNote = Note(pane, wide - LASTS_BOX - 12, 2)
    lastsNote:SetJustifyV("MIDDLE")
    lastsNote:SetPoint("LEFT", pane, "TOPLEFT", control + LASTS_BOX + 12, PANE_ROWS.lasts - 10)

    -- How many times over the effect goes on one unit: the same as /se stacks.
    local function ApplyStacks(box)
        local info = pane.info
        if not info then
            return
        end
        local text = (box:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text == box.before then
            -- Nothing was changed, as with how long it lasts.
        elseif text == "" or text == "-" or text:lower() == "auto" then
            local choice = ns.db.spells[info.name]
            if choice then
                choice.stacks = nil
                Spells:Tidy(info.name)
            end
        else
            local most = text:find("^%d+$") and tonumber(text)
            if not most or most < 1 or most > 100 then
                Complain("stacks", "Type a number from 1 to 100.")
                return
            end
            Spells:Choice(info.name).stacks = most
        end
        Settled()
        box:ClearFocus()
        SpellChanged()
    end

    RowLabel(pane, "Stacks up to", 0, PANE_ROWS.stacks, labelRoom,
        "How many times over the effect goes on one unit. A unit only counts as having the effect once it "
            .. "has that many stacks: until then the skill stays worth casting.")
    local stacks
    built, stacks = pcall(Input, pane, STACKS_BOX)
    if built and stacks then
        stacks:SetPoint("TOPLEFT", pane, "TOPLEFT", control + 1, PANE_ROWS.stacks)
        Try(stacks, "SetJustifyH", "CENTER")
        stacks:SetMaxLetters(4)
        stacks:SetScript("OnEditFocusGained", function(self)
            -- Typing starts from the bare number: your own if you set one, or
            -- from nothing for an effect that does not stack.
            local info = pane.info
            if info then
                local user = ns.db.spells[info.name]
                local most = (user and type(user.stacks) == "number" and user.stacks) or Spells:Stacking(info)
                self.before = most and tostring(most) or ""
                self:SetText(self.before)
                Try(self, "SetTextColor", 1, 1, 1)
                Try(self, "HighlightText")
            end
        end)
        stacks:SetScript("OnEditFocusLost", function(self)
            Try(self, "HighlightText", 0, 0)
            Settled()
            ns.Guard(view.Refresh)
        end)
        stacks:SetScript("OnEnterPressed", function(self)
            ns.Guard(ApplyStacks, self)
        end)
        stacks:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)
        Tip(stacks, "How many times the effect stacks")
    else
        stacks = nil
    end
    local stacksNote = Note(pane, wide - STACKS_BOX - 12, 2)
    stacksNote:SetJustifyV("MIDDLE")
    stacksNote:SetPoint("LEFT", pane, "TOPLEFT", control + STACKS_BOX + 12, PANE_ROWS.stacks - 10)

    -- Whether another player's copy of the effect counts: the same as /se anyone
    -- and /se mine. A choice of yours is only kept while it differs from what
    -- the addon makes of the spell by itself, so ticking it back is going back.
    RowLabel(pane, "Other players", 0, PANE_ROWS.shared, labelRoom,
        "Whether the same effect counts when someone else put it there. It does for an effect a unit carries "
            .. "only once, whoever casts it, and not for one every caster has their own of, such as a bleed.")
    local shared = TickBox(pane, "Their copy counts too")
    shared.frame:SetPoint("LEFT", pane, "TOPLEFT", control, PANE_ROWS.shared - 10)
    shared.Fit(wide - Wide(shared.frame, 30) - 6)
    shared.onChange = function(ticked)
        local info = pane.info
        if not info then
            return
        end
        local choice = Spells:Choice(info.name)
        choice.shared = nil
        if Spells:Shared(info) ~= ticked then
            choice.shared = ticked
        end
        Spells:Tidy(info.name)
        if not ticked then
            Tracker:ForgetTheirs(info.name)
        end
        SpellChanged()
    end
    Tip(shared.frame, "Another player's copy counts")
    local sharedNote = Note(pane, wide, 2)
    sharedNote:SetPoint("TOPLEFT", pane, "TOPLEFT", control, PANE_ROWS.shared - 24)

    -- Which kinds of creature the skill does nothing to: what the addon has
    -- found of that in play, and the two things /se immune does.
    local immuneLabel = RowLabel(pane, "Immune", 0, PANE_ROWS.immune, labelRoom,
        "Kinds of creature this skill does nothing to. The addon notes a kind when the game says \"Immune\" in a "
            .. "fight, and counts on it from the second time: a creature of that kind is then left out when the "
            .. "skill is judged.")
    local mark = PushButton(pane, MARK_WIDTH, 22, "Add target")
    mark:SetPoint("TOPLEFT", pane, "TOPLEFT", control, PANE_ROWS.immune + 1)
    -- The kinds, under the two buttons like the note of any other row. The
    -- mouse on them lists every one.
    local immuneNote = Note(pane, wide, 3)
    immuneNote:SetPoint("TOPLEFT", pane, "TOPLEFT", control, PANE_ROWS.immune - 25)
    local immuneArea = CreateFrame("Frame", nil, pane)
    immuneArea:SetSize(wide, 36)
    immuneArea:SetPoint("TOPLEFT", pane, "TOPLEFT", control, PANE_ROWS.immune - 24)
    immuneArea:EnableMouse(true)
    Tip(immuneArea, nil)

    OnClick(mark, function()
        local info = pane.info
        if not info then
            return
        end
        local added, why = ns.MarkImmune(info.name)
        if added then
            Settled()
        else
            pane.problem, pane.problemAt = MARK_WHY[why] or MARK_UNSAID, "immune"
        end
        Options.RefreshAll()
    end)
    Tip(mark, "Add target", "Says that the kind of creature you have targeted is immune to this skill. The same as "
        .. "/se immune with the skill's name.")

    local forget = PushButton(pane, FORGET_WIDTH, 22, "Forget all")
    forget:SetPoint("TOPLEFT", pane, "TOPLEFT", control + MARK_WIDTH + 6, PANE_ROWS.immune + 1)
    OnClick(forget, function()
        local info = pane.info
        if not info then
            return
        end
        local name = info.name
        view.Ask("immune", "Forget the creatures immune to " .. name .. "?", "Forget", function()
            Settled()
            ns.ForgetImmune(name)
            Options.RefreshAll()
        end)
    end)
    Tip(forget, "Forget all", "Forgets every kind of creature listed for this skill, also the ones you added "
        .. "yourself. It asks first.")

    -- Back to what the addon works out by itself.
    local reset = PushButton(pane, RESET_WIDTH, 22, "Reset this skill")
    reset:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 4)
    OnClick(reset, function()
        local info = pane.info
        if info and ns.db.spells[info.name] then
            Settled()
            Unchoose(info.name, info)
            SpellChanged()
        end
    end)
    Tip(reset, "Reset this skill",
        "Forgets your own choices for this skill, so that the addon works it out by itself again. What it has "
            .. "learned about the skill in play stays.")
    local resetNote = Note(pane, width - RESET_WIDTH - 12, 2)
    resetNote:SetJustifyV("MIDDLE")
    resetNote:SetPoint("LEFT", pane, "BOTTOMLEFT", 0, 15)

    --- Shows a spell in the pane, or puts the pane away.
    function pane.Bind(info)
        local name1, name2 = pane.info and pane.info.name, info and info.name
        if name1 ~= name2 then
            Settled()
            view.Unask("immune") -- a question about the skill that was picked
            if lasts and lasts:HasFocus() then
                lasts:ClearFocus()
            end
            if stacks and stacks:HasFocus() then
                stacks:ClearFocus()
            end
        end
        pane.info = info
        Shown(pane, info ~= nil)
        if not info then
            return
        end

        local tracked, area, duration, source, kind = Spells:Tracking(info)
        local user = ns.db.spells[info.name]

        Wear(icon, info)
        Say(name, info.name, nameRoom)
        summary.Tell((Summary(info)))

        local pick = "auto"
        if user and user.track == true then
            pick = "always"
        elseif user and user.track == false then
            pick = "never"
        end
        show.Set(pick)
        local short, long = WhyText(info, tracked, source, kind)
        why.Tell(short)
        whyArea.tipTitle, whyArea.tipBody = info.name, long

        -- Who it is judged on, how long it lasts, how often it stacks and whose
        -- copy counts only matter once it has an icon.
        on.Enable(tracked)
        if tracked then
            local key = kind == "buff" and "self" or (area and "all" or "target")
            on.Set(key)
            onNote.Tell(ON_BY_KEY[key].note)
        else
            on.Set(nil)
            onNote.Tell("The rest only matters for a skill that has an icon.")
        end

        if lasts then
            Try(lasts, "SetEnabled", tracked)
            lasts:EnableMouse(tracked)
            Dim(lasts, not tracked)
            if not lasts:HasFocus() then
                lasts:SetText(tracked and Short(duration) or "")
            end
            local from = DURATION_WHY[Spells:DurationSource(info)]
            lasts.tipBody = from[2]
                .. " Type a number of seconds to change it, or empty the box to let the addon work it out."
            if pane.problemAt == "lasts" then
                lastsNote.Tell(pane.problem, BAD)
            else
                lastsNote.Tell(tracked and from[1] or "")
            end
        else
            lastsNote.Tell(tracked and ("/se duration " .. info.name .. " <seconds>") or "")
        end

        if stacks then
            Try(stacks, "SetEnabled", tracked)
            stacks:EnableMouse(tracked)
            Dim(stacks, not tracked)
            local most = Spells:Stacking(info)
            -- A dash, in grey, for an effect that goes on once: most do.
            local once = not most and not (user and type(user.stacks) == "number")
            if not stacks:HasFocus() then
                stacks:SetText(tracked and (most and tostring(most) or (once and "-" or "1")) or "")
                if once then
                    Try(stacks, "SetTextColor", 0.5, 0.5, 0.5)
                else
                    Try(stacks, "SetTextColor", 1, 1, 1)
                end
            end
            stacks.tipBody = StacksTip(info)
            if pane.problemAt == "stacks" then
                stacksNote.Tell(pane.problem, BAD)
            elseif not tracked then
                stacksNote.Tell("")
            elseif most then
                local from = STACKS_WHY[Spells:StackingSource(info)]
                stacksNote.Tell(from and from[1] or "")
            else
                stacksNote.Tell(once and "Goes on once." or "You set this: it goes on once.")
            end
        else
            stacksNote.Tell(tracked and ("/se stacks " .. info.name .. " <number>") or "")
        end

        -- Nobody else can put on you what a skill only ever puts on its caster.
        local alone = kind == "buff" and info.selfOnly == true
        local sharable = tracked and not alone
        shared.Enable(sharable)
        if sharable then
            local anyone = Spells:Shared(info)
            shared.Set(anyone)
            shared.frame.tipBody = SharedTip(info, anyone)
            sharedNote.Tell((anyone and "Counted whoever cast it. " or "Only your own counts. ") .. SharedSource(info))
        else
            shared.Set(false)
            shared.frame.tipBody = nil
            sharedNote.Tell(tracked and "Only you can have this effect." or "")
        end

        -- Only an effect that lands on enemies can meet an immune one.
        local hostile = tracked and kind ~= "buff"
        local kinds = hostile and Spells:ImmuneKinds(info.name) or NO_KINDS
        Able(mark, hostile)
        Able(forget, #kinds > 0)
        if pane.problemAt == "immune" then
            immuneNote.Tell(pane.problem, BAD)
        elseif not tracked then
            immuneNote.Tell("")
        elseif not hostile then
            immuneNote.Tell("Only enemies can be immune.")
        else
            immuneNote.Tell(ImmuneLine(kinds))
        end
        immuneArea.tipTitle = #kinds > 0 and ("Immune to " .. info.name) or nil
        immuneArea.tipLines = ImmuneLines(kinds)

        local yours = user ~= nil
        Able(reset, yours)
        resetNote.Tell(yours and "You have changed this skill." or "Nothing changed: the addon decides.")
    end

    pane.icon, pane.name, pane.summary = icon, name, summary
    pane.show, pane.showArea, pane.why, pane.whyArea = show, showArea, why, whyArea
    pane.on, pane.onNote = on, onNote
    pane.lasts, pane.lastsNote, pane.stacks, pane.stacksNote = lasts, lastsNote, stacks, stacksNote
    pane.shared, pane.sharedNote, pane.reset, pane.resetNote = shared, sharedNote, reset, resetNote
    pane.immuneLabel, pane.immuneNote, pane.immuneArea = immuneLabel, immuneNote, immuneArea
    pane.mark, pane.forget = mark, forget
    return pane
end

local function BuildSpells(view, page)
    local list = { rows = {}, items = {}, offset = 0 }
    view.spells = list

    local intro = Text(page, "GameFontHighlightSmall",
        "The skills on your action bars. Pick one to see how the addon judges it, and to change what it got wrong.")
    intro:SetPoint("TOPLEFT", page, "TOPLEFT", L.left, -8)
    intro:SetWidth(L.right - L.left)
    FitLines(intro, L.right - L.left, 2) -- the list starts under its second line
    list.intro = intro

    for index = 1, L.rows do
        list.rows[index] = BuildListRow(view, page, index)
    end
    local pane = BuildPane(view, page)
    view.pane = pane

    local empty = Text(page, "GameFontDisable", "No skills found on your action bars yet.")
    empty:SetPoint("TOPLEFT", page, "TOPLEFT", L.left, L.listTop - 8)
    Fit(empty, L.right - L.left)
    empty:Hide()
    list.empty = empty

    -- A scroll bar of its own: the list is short, and this one cannot go missing.
    local setting = false
    local bar = CreateFrame("Slider", nil, page)
    bar:SetPoint("TOPLEFT", page, "TOPLEFT", L.listLeft + L.listWidth + 4, L.listTop)
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

    --- The spell that is picked: the one last clicked while it is still on the
    --- bars, or else the first of the list.
    local function Selected()
        local items = list.items
        for i = 1, #items do
            if items[i].name == list.selected then
                return items[i], i
            end
        end
        list.selected = items[1] and items[1].name or nil
        return items[1], 1
    end

    local function Draw()
        local items = list.items
        local last = max(0, #items - L.rows)
        list.offset = max(0, min(last, list.offset))
        local selected = Selected()
        for index = 1, L.rows do
            local info = items[list.offset + index]
            list.rows[index].Bind(info, info ~= nil and info == selected)
        end
        pane.Bind(selected)

        local tracked, yours = 0, 0
        for i = 1, #items do
            if Spells:Tracking(items[i]) then
                tracked = tracked + 1
            end
            if ns.db.spells[items[i].name] then
                yours = yours + 1
            end
        end
        Shown(empty, #items == 0)
        Shown(bar, last > 0)
        setting = true
        bar:SetMinMaxValues(0, last)
        bar:SetValue(list.offset)
        setting = false

        if #items == 0 then
            view.Foot("")
        else
            view.Foot((#items == 1 and "1 skill" or (#items .. " skills")) .. " on your bars, " .. tracked
                .. " with an icon" .. (yours > 0 and (", " .. yours .. " changed by you.") or ".")
                .. (last > 0 and " Scroll the list for more." or ""))
        end
    end

    --- Moves the list by a number of rows.
    function list.Scroll(rows)
        local before = list.offset
        list.offset = list.offset + rows
        Draw()
        return list.offset ~= before
    end

    --- Picks a spell by name: the pane then shows it.
    function view.Select(name)
        list.selected = name
        Draw()
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
    --- so that a line does not jump away under the mouse: those with an icon are
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
                -- The list opens with the spell that is picked in sight.
                local _, at = Selected()
                list.offset = max(0, (at or 1) - L.rows)
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
-- The panel: tabs, a page under each, and a strip along the bottom
--------------------------------------------------------------------------------

-- `ask` is the question before a tab is put back to how it started.
local TABS = {
    { key = "display", label = "Display", ask = "Put everything on the Display tab back to how it started?" },
    { key = "icons", label = "Icons", ask = "Put the three icons back to how they started?" },
    { key = "spells", label = "Skills", ask = "Forget your own choices for every skill?" },
}
local TAB_WIDTH = 84

-- The names a tab goes by: its own, and the ones from before there were three.
local TAB_KEYS = { display = "display", appearance = "display", icons = "icons", spells = "spells", skills = "spells" }
Options.TAB_KEYS = TAB_KEYS

-- How the Display tab starts out. (The same values as a new player's settings.)
local DEFAULTS = { enabled = true, appear = "group", usableOnly = true, corner = "TOPLEFT", size = 0 }
Options.DEFAULTS = DEFAULTS

-- What the Defaults button does on each tab.
local RESETS = {
    display = function()
        ns.SetEnabled(DEFAULTS.enabled)
        ns.SetAppear(DEFAULTS.appear)
        ns.SetUsableOnly(DEFAULTS.usableOnly)
        ns.db.corner = DEFAULTS.corner
        ns.db.size = DEFAULTS.size
    end,
    icons = function()
        Icons.ResetAll()
    end,
    spells = function()
        local byName = {}
        local found = ns.BarSpells()
        for i = 1, #found do
            byName[found[i].name] = found[i]
        end
        local names = {}
        for name in pairs(ns.db.spells) do
            names[#names + 1] = name
        end
        for i = 1, #names do
            Unchoose(names[i], byName[names[i]])
        end
        ns.MarkBarsDirty()
    end,
}

--- Fills `host` with the panel and returns a view. `chrome` says where things
--- go: { tabsOn, tabsX, tabsY, lineAt, backed, pageTop, defaultsX, defaultsY,
--- defaultsHeight }.
local function Build(host, chrome)
    local view = { host = host, tab = "display", tabs = {}, pages = {} }
    local asks = {}

    for index = 1, #TABS do
        local tab = TABS[index]
        asks[tab.key] = tab.ask
        local button = CreateFrame("Button", nil, chrome.tabsOn)
        button:SetSize(TAB_WIDTH, 24)
        button:SetPoint("TOPLEFT", chrome.tabsOn, "TOPLEFT", chrome.tabsX + (index - 1) * (TAB_WIDTH + 4), chrome.tabsY)

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
        Say(label, tab.label, TAB_WIDTH - 10)

        button.back, button.line, button.label = back, line, label
        button:SetScript("OnClick", function()
            Sound("IG_CHARACTER_INFO_TAB")
            ns.Guard(view.ShowTab, tab.key)
        end)
        view.tabs[tab.key] = button

        local page = CreateFrame("Frame", nil, host)
        page:SetSize(L.width, L.pageHeight - L.foot)
        page:SetPoint("TOPLEFT", host, "TOPLEFT", 0, chrome.pageTop)
        page:Hide()
        view.pages[tab.key] = page
    end

    -- The strip along the bottom: a line about the tab that is open, or the
    -- question before that tab is put back to how it started.
    local foot = CreateFrame("Frame", nil, host)
    foot:SetSize(L.width, L.foot)
    foot:SetPoint("TOPLEFT", host, "TOPLEFT", 0, chrome.pageTop - (L.pageHeight - L.foot))
    local rule = foot:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", foot, "TOPLEFT", 12, 0)
    rule:SetSize(L.width - 24, 1)
    rule:SetColorTexture(0.4, 0.4, 0.45, 0.7)
    local footer = Text(foot, "GameFontDisableSmall")
    footer:SetJustifyV("MIDDLE")
    footer:SetPoint("LEFT", foot, "LEFT", L.left, 0)
    view.foot, view.footer = foot, footer

    --- Says something about the tab that is open, at the bottom of the panel.
    function view.Foot(text)
        Say(footer, text, L.right - L.left)
    end

    local confirm = CreateFrame("Frame", nil, foot)
    confirm:SetAllPoints(foot)
    confirm:Hide()
    local no = PushButton(confirm, 90, 22, "Cancel")
    no:SetPoint("RIGHT", confirm, "RIGHT", -(L.width - L.right), 0)
    local yes = PushButton(confirm, 90, 22, "Reset")
    yes:SetPoint("RIGHT", no, "LEFT", -6, 0)
    local question = Text(confirm, "GameFontHighlight")
    question:SetJustifyV("MIDDLE")
    question:SetPoint("LEFT", confirm, "LEFT", L.left, 0)
    local questionRoom = L.right - L.left - 90 - 6 - 90 - 12
    view.question = question
    view.confirm = { frame = confirm, yes = yes, no = no }

    -- One question at a time: what a click on the first button would do.
    local pending

    --- Asks before something is thrown away, in place of the line at the
    --- bottom. `what` names what is asked about (view.asking holds it while the
    --- question is up), `label` goes on the button that does it, and `action`
    --- is what that button does.
    function view.Ask(what, text, label, action)
        view.asking, pending = what, action
        yes.SetLabel(label)
        Say(question, text, questionRoom)
        Shown(confirm, true)
        Shown(footer, false)
    end

    --- Puts the question away unanswered. With `what`, only a question about that.
    function view.Unask(what)
        if what and view.asking ~= what then
            return
        end
        view.asking, pending = nil, nil
        Shown(confirm, false)
        Shown(footer, true)
    end

    -- Defaults, where the game's own pages have theirs. It asks first.
    local defaults = PushButton(chrome.tabsOn, DEFAULTS_WIDTH, chrome.defaultsHeight, "Defaults")
    defaults:SetPoint("TOPLEFT", chrome.tabsOn, "TOPLEFT", chrome.defaultsX, chrome.defaultsY)
    Tip(defaults, "Defaults", "Puts the tab that is open back to how it started. It asks first.")
    OnClick(defaults, function()
        local reset = RESETS[view.tab]
        view.Ask(view.tab, asks[view.tab], "Reset", function()
            view.editing = nil
            Change(reset)
        end)
    end)
    OnClick(no, function()
        view.Unask()
    end)
    OnClick(yes, function()
        local action = pending
        view.Unask()
        if action then
            action()
        end
    end)
    view.defaults = defaults

    BuildDisplay(view, view.pages.display)
    BuildIcons(view, view.pages.icons)
    BuildSpells(view, view.pages.spells)

    --- Puts away whatever was half done when the panel closes or the tab changes.
    function view.Settle()
        view.Unask()
        view.editing = nil
        if view.input then
            view.input:ClearFocus()
        end
        view.editor.problem = nil
        local pane = view.pane
        if pane.lasts then
            pane.lasts:ClearFocus()
        end
        if pane.stacks then
            pane.stacks:ClearFocus()
        end
        pane.problem, pane.problemAt = nil, nil
    end

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
        elseif view.tab == "icons" then
            view.RefreshIcons()
        else
            view.RefreshDisplay()
        end
    end

    --- Brings a tab to the front.
    function view.ShowTab(key)
        key = TAB_KEYS[key]
        if not key then
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

    local tabsX = 160
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

    -- Defaults sits in the title bar, before the button that closes the window.
    local view = Build(host, { tabsOn = host, tabsX = tabsX, tabsY = -(L.bar - 24), lineAt = "TOP", backed = true,
        pageTop = -L.bar, defaultsX = L.width - 30 - DEFAULTS_WIDTH, defaultsY = -4, defaultsHeight = 20 })
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

--- Opens the settings window, on a tab if one is named ("display", "icons" or "spells").
function Options.Open(tab)
    tab = tab and TAB_KEYS[tab] or nil
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
    Fit(title, L.right - DEFAULTS_WIDTH - 12 - 16) -- Defaults is at the far end of the same line

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
    -- Defaults is where the game's own pages have theirs: at the far end of the heading.
    local view = Build(host, { tabsOn = host, tabsX = 12, tabsY = -58, lineAt = "BOTTOM", pageTop = -L.canvasTop,
        defaultsX = L.right - DEFAULTS_WIDTH, defaultsY = -16, defaultsHeight = 22 })
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
