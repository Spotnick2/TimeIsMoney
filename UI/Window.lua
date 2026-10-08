-- The ledger window (#20): Liquid Glass cards over the running company. Plain,
-- unprotected frames. Every control routes through the host's validated commands;
-- the window only reads the game. Hiding it stops its refresh, never the company
-- (the host's own wakeup frame runs the simulation).
local _, ns = ...
local View = ns.View
local JSMath = ns.JSMath
local T = View.TERMS

local Window = {}
ns.Window = Window
TimeIsMoney.Window = Window

Window.REFRESH = 0.1   -- seconds between redraws while shown (not the logical step)
Window.BATTLE_REFRESH = 0.03 -- the combat view's own redraw while a battle shows
Window.COLUMN = 236    -- column width
Window.GAP = 8
Window.ROW = 22        -- one line of a card
Window.BUTTON = 24     -- button height ("small" glass: under ~40 px tall)
-- Square buttons stay 32x32: sliced masks fail on boxes small in both directions
-- (16-22 px measured; 32x32 known good; LibGlass GLASS-MATERIAL.md section 6).
Window.SQUARE = 32
-- Room under the cards: the Director's strip (#22). The reference's messages show
-- there as the company's reports, localized (UI/Messages.lua), never in their own
-- wording.
Window.MESSAGE = 10

local COPPER = { 0.85, 0.6, 0.4 }
local MUTED = { 0.7, 0.7, 0.7 }
Window.COPPER, Window.MUTED = COPPER, MUTED -- the Director's strip shares them

local Glass

local function Report(message)
    print("|cffd9a066Time Is Money|r: " .. message)
end

-- Commands: the host validates and applies them at the current logical time.
-- Controls that end the company ask first (the reference's confirm()): the click
-- reaches the host, marked confirmed, only after an explicit yes.
local CONFIRM = { projectButton217 = "confirm.reversion" }

local function Send(id, confirmed)
    local ok, err = ns.Host.click(id, confirmed)
    if not ok then Report("not done: " .. tostring(err)) end
    Window.Refresh()
end

local function Click(id)
    if CONFIRM[id] then
        Window.Confirm(CONFIRM[id], function() Send(id, true) end)
        return
    end
    Send(id)
end

-- Surface tints (LibGlass r3 SetSurfaceTint): panels nearly opaque, the primary
-- action a restrained green. The settings cog is a client icon.
Window.PANEL_TINT = { 0.04, 0.05, 0.07, 0.96 }
Window.MAIN_TINT = { 0.06, 0.07, 0.10, 0.78 }
-- Buttons (#89): one system. Available: the plain glass; hover: brighter;
-- pressed: darker; unavailable: dimmed (LibGlass), with no hover highlight.
Window.HOVER_TINT = { 0.55, 0.58, 0.66, 0.42 }
Window.PRESSED_TINT = { 0.02, 0.02, 0.03, 0.60 }
-- Content padding inside a card. The thin rim reports a 4 px inset, but in the
-- client its visible bevel is wider: at 4 px a card's last button sat on its bottom
-- rim and the title on its top one (owner screenshot, 1.60.1.70245, 2026-10-07).
Window.CARD_INSET = 8
Window.PRIMARY_TINT = { 0.16, 0.42, 0.20, 0.55 }
Window.SETTINGS_ICON = "Interface\\Icons\\INV_Misc_Gear_01"
Window.CHECK_ICON = "Interface\\Buttons\\UI-CheckBox-Check"

-- The addon's own tooltip (#89): the client's tooltip template on a nearly opaque
-- glass body, so card text never shows through; the shared GameTooltip stays as it
-- is for every other addon. Falls back to GameTooltip if the template is missing.
function Window.Tip()
    if Window.tooltip then return Window.tooltip end
    Glass = Glass or LibStub("LibGlass-1.0"):New()
    local ok, tip = pcall(CreateFrame, "GameTooltip", "TimeIsMoneyTooltip", UIParent, "GameTooltipTemplate")
    if ok and tip then
        tip:SetFrameStrata("TOOLTIP")
        if tip.NineSlice then tip.NineSlice:Hide() end -- the glass replaces its border
        tip.glass = Glass.Apply(tip, "large")
        Glass.SetSurfaceTint(tip.glass, unpack(Window.PANEL_TINT))
        Window.tooltip = tip
    else
        Window.tooltip = GameTooltip
    end
    return Window.tooltip
end

-- "New" tags (#90): a card, row or project that appears after the window's first
-- draw is tagged "New" (not a glow: a glow reads as "click me") until it is hovered
-- or has shown for NEW_SECONDS. A newly shown card tags only its title, not each of
-- its rows. Presentation only, per session.
Window.NEW_SECONDS = 30
Window.clock = 0
local function NewTag(parent)
    local tag = Glass.Font(parent, 9, "LEFT")
    tag:SetTextColor(0.35, 1, 0.35)
    tag:Hide()
    return tag
end
-- Whether `thing` (a row, a card, a project button) shows its tag now, after its
-- visibility this redraw; starts the tag when it first appears (once ready).
local function NewState(thing, visible, allowed)
    if visible and not thing.wasShown and Window.ready and allowed then thing.newUntil = Window.clock + Window.NEW_SECONDS end
    if visible then thing.wasShown = true end
    if thing.newUntil and Window.clock >= thing.newUntil then thing.newUntil = nil end
    return visible and thing.newUntil ~= nil
end
Window.NewState = NewState

-- ESC (#89): the client closes every shown frame named in UISpecialFrames before
-- opening its menu. Our panels are always listed; the ledger only while no panel is
-- open, so the first ESC closes the panels and the next the ledger. Entries are added
-- and removed in place: the global table itself is never reassigned (a write to a
-- Blizzard global taints, PORTING-TBC-TO-FOREVER).
Window.ESC_PANELS = { "TimeIsMoneyHelp", "TimeIsMoneySettings", "TimeIsMoneyReports", "TimeIsMoneyConfirm",
    "TimeIsMoneyIcons" }
local function Listed(name)
    for i, n in ipairs(UISpecialFrames) do if n == name then return i end end
end
-- From a panel's OnHide: never edit the list inside the client's ESC loop (adding
-- the ledger there would close it with the same press); do it on the next frame.
function Window.EscapeLater()
    C_Timer.After(0, function() Window.UpdateEscape() end)
end
function Window.UpdateEscape()
    local open = false
    for _, name in ipairs(Window.ESC_PANELS) do
        local frame = _G[name]
        if frame then
            if not Listed(name) then table.insert(UISpecialFrames, name) end
            if frame:IsShown() then open = true end
        end
    end
    local i = Listed("TimeIsMoneyWindow")
    if open and i then
        table.remove(UISpecialFrames, i)
    elseif not open and not i then
        table.insert(UISpecialFrames, "TimeIsMoneyWindow")
    end
end

-- Tooltips: one renderer. lines[1] is the white title, the rest wrap muted.
local function ShowTip(owner, lines)
    local tip = Window.Tip()
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    tip:SetText(lines[1], 1, 1, 1)
    for i = 2, #lines do tip:AddLine(lines[i], MUTED[1], MUTED[2], MUTED[3], true) end
    tip:Show()
end

-- A tooltip line read from the running company, or nil.
local function FromGame(fn)
    return function()
        local game = ns.Host.game
        return game and fn(game.S) or nil
    end
end

-- Mouse areas (tooltips, hover) over the window still let it be dragged.
local function Draggable(area)
    area:RegisterForDrag("LeftButton")
    area:SetScript("OnDragStart", function() Window.frame:StartMoving() end)
    area:SetScript("OnDragStop", function() Window.frame:StopMovingOrSizing() end)
end

-- A glass button bound to a control id. Disabled exactly when the game disables
-- that control; the label says so too (not colour alone).
local function NewButton(parent, id, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(height or Window.BUTTON)
    -- Text goes on the glass's top layer, above the rim (host level + 10).
    -- The thin rim (LibGlass r3): many small buttons read as glass, not moulding.
    b.glass = Glass.Apply(b, "thin_small")
    b.label = Glass.Font(b.glass.top, 11, "CENTER")
    b.label:SetPoint("LEFT", b, "LEFT", 4, 0)
    b.label:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    b.id = id
    b:SetScript("OnClick", function(self) if self.id then Click(self.id) end end)
    -- Live like every hover tooltip: re-read on each redraw while hovered, so a cost
    -- that changes under the pointer (a purchase) shows its new value and title.
    -- Hover and pressed looks, only while it can be used.
    b:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() and not self.lit then Glass.SetSurfaceTint(self.glass, unpack(Window.PRESSED_TINT)) end
    end)
    b:SetScript("OnMouseUp", function(self)
        if self:IsEnabled() and self.hovered and not self.lit then Glass.SetSurfaceTint(self.glass, unpack(Window.HOVER_TINT)) end
    end)
    b:SetScript("OnEnter", function(self)
        self.hovered = true
        if self.newOf then self.newOf.newUntil = nil end -- seen: the "New" tag goes
        if self:IsEnabled() and not self.lit then Glass.SetSurfaceTint(self.glass, unpack(Window.HOVER_TINT)) end
        Window.liveTip = { owner = self, lines = function()
            -- Built afresh on every redraw from the button's own tip (fixed, or its
            -- tipFn), what it does (#89) and why not (#73); nothing is written back.
            local base = self.tipFn and self.tipFn() or self.tip
            local game = ns.Host.game
            local lines
            local does = game and View.actionTip(self.id, game.S)
            if does then
                lines = { self.text or "" }
                for _, line in ipairs(does) do lines[#lines + 1] = line end
                for i = 2, #(base or {}) do lines[#lines + 1] = base[i] end
            elseif base then
                lines = {}
                for i, line in ipairs(base) do lines[i] = line end
            end
            local why = not self:IsEnabled() and game and
                ((ns.Host.paused and (self.id or self.company) and ns.L["why.paused"]) or View.unavailable(self.id, game.S)
                    or (self.why and ns.L[self.why]))
            if why then
                lines = lines or { self.text or "" }
                lines[#lines + 1] = why
            end
            return lines
        end }
        Window.UpdateLiveTip()
    end)
    b:SetScript("OnLeave", function(self)
        self.hovered = false
        if not self.lit then Glass.SetSurfaceTint(self.glass) end
        if Window.liveTip and Window.liveTip.owner == self then Window.liveTip = nil end
        Window.Tip():Hide()
    end)
    b:SetMotionScriptsWhileDisabled(true)
    return b
end

local function SetButton(b, text, enabled, short)
    -- A paused company's controls do nothing (#77): unavailable, and the label and
    -- tooltip say it is the pause. Company controls have an id or the company flag
    -- (selects and range steps, which act through Host.setValue).
    local paused = (b.id or b.company) and ns.Host.paused
    if paused then enabled = false end
    b:SetEnabled(enabled)
    b.text = text
    -- Unaffordable is not locked: the label and cost stay as they are (#80). The
    -- control dims (glass, label and icon lose brightness and opacity) and its
    -- tooltip says why. Only the pause, a different reason, is named on the label
    -- (not on the squares, which have no room).
    b.label:SetText((paused and not short) and (text .. " " .. ns.L["window.pausedTag"]) or text)
    if enabled then b.label:SetTextColor(1, 1, 1) else b.label:SetTextColor(MUTED[1], MUTED[2], MUTED[3]) end
    b.label:SetAlpha(enabled and 1 or 0.6)
    -- The glass dims too (LibGlass r3), with any icon on it (content on g.top is
    -- ours to dim), and the primary action carries the accent only while it can be
    -- used. Only on a change: the window redraws ten times a second.
    if b.surfaceEnabled ~= enabled then
        b.surfaceEnabled = enabled
        Glass.SetSurfaceEnabled(b.glass, enabled)
        if b.icon then b.icon:SetAlpha(enabled and 1 or 0.4) end
        -- No hover highlight while unavailable; it comes back under the pointer.
        if not b.lit then
            if enabled and b.hovered then Glass.SetSurfaceTint(b.glass, unpack(Window.HOVER_TINT)) else Glass.SetSurfaceTint(b.glass) end
        end
    end
end

-- Cards: a glass panel of rows. Each row has a show(S, panels) predicate; hidden
-- rows take no space, and a card with no visible row is hidden.
local Card = {}
Card.__index = Card

-- titled(panels), when given, says whether the title's block shows: the reference
-- keeps each heading inside the block it hides, so the card's other rows can show
-- without it.
local function NewCard(parent, title, titled)
    local card = setmetatable({ rows = {}, titled = titled }, Card)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(Window.COLUMN)
    card.glass = Glass.Apply(f, "thin")
    card.frame = f
    card.content = CreateFrame("Frame", nil, f)
    card.content:SetAllPoints(f)
    card.content:SetFrameLevel(Glass.ContentLevel(f))
    card.title = Glass.Font(card.glass.top, 12, "LEFT")
    card.title:SetText(title)
    card.title:SetTextColor(COPPER[1], COPPER[2], COPPER[3])
    return card
end

-- A row: a label on the left and a value on the right.
-- tip(S), when given, is a tooltip line for the row (nil: no tooltip now). The
-- row's label and value become a mouse area for it; while hovered, the tooltip
-- follows the company on every redraw (it appears, changes or goes as the amount
-- does).
-- A row's hover area (it also drags the window). live(area) returns the live tip
-- ({ owner, lines } or { owner, render }) shown while hovered; one path for plain
-- line tips and item tips.
local function HoverArea(row, parent, live)
    row.tipArea = CreateFrame("Frame", nil, parent)
    row.tipArea:EnableMouse(true)
    Draggable(row.tipArea)
    row.tipArea:SetScript("OnEnter", function(area)
        row.newUntil = nil -- seen: the "New" tag goes
        Window.liveTip = live(area)
        Window.UpdateLiveTip()
    end)
    row.tipArea:SetScript("OnLeave", function(area)
        if Window.liveTip and Window.liveTip.owner == area then Window.liveTip = nil end
        Window.Tip():Hide()
    end)
end
local function TipArea(row, parent, tip)
    local line = FromGame(tip)
    HoverArea(row, parent, function(area)
        return { owner = area, lines = function()
            local text = line()
            return text and { row.label:GetText() or "", text } or nil
        end }
    end)
end

-- The hovered tooltip (a button or a row), refreshed on each redraw: it appears,
-- changes or goes as its lines do.
function Window.UpdateLiveTip()
    local tip = Window.liveTip
    if not tip then return end
    if tip.render then
        tip.shown = tip.render(tip.owner)
        if not tip.shown then Window.Tip():Hide() end
        return
    end
    local lines = tip.lines()
    if lines then
        ShowTip(tip.owner, lines)
        tip.shown = true
    elseif tip.shown then
        Window.Tip():Hide()
        tip.shown = false
    end
end

-- An identity's item icon at the start of a row (Assets), the label after it.
function Card:WithIcon(row, key)
    row.icon = self.content:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.iconKey = key
    -- Items (#84): a short role line under the name, and a WoW-style tooltip.
    if View.itemRole(key) then
        assert(not row.tipArea, "an item row takes the item tooltip, not a line tip")
        row.role = Glass.Font(self.glass.top, 9, "LEFT")
        row.role:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
        row.role:SetWordWrap(false)
        row.role:SetText(View.itemRole(key))
        if row.kind == "stat" then row.height = row.height + 11 end
        HoverArea(row, self.content, function(area)
            return { owner = area, render = function(owner) return Window.ShowItemTip(owner, key) end }
        end)
        row.tipArea.itemKey = key -- tests tell item areas from line-tip areas
    end
    return row
end

-- A WoW item tooltip for an item key: the name in its item's quality colour, the
-- category, what it does (live), a green "Use:" line and yellow flavour text.
function Window.ShowItemTip(owner, key)
    local game = ns.Host.game
    local item = game and View.itemTip(key, game)
    if not item then return false end
    local tip = Window.Tip()
    local identity = ns.Assets.identity[key]
    local r, g, b = 1, 1, 1
    if identity then
        local qr, qg, qb = TimeIsMoney.API.ItemQualityColor(identity.item)
        if qr then r, g, b = qr, qg, qb end
    end
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    tip:SetText(item.title, r, g, b)
    tip:AddLine(item.category, 1, 1, 1)
    for _, line in ipairs(item.lines) do tip:AddLine(line, 1, 1, 1, true) end
    -- The client's own colours when present (GREEN_FONT_COLOR, NORMAL_FONT_COLOR).
    local green, yellow = GREEN_FONT_COLOR, NORMAL_FONT_COLOR
    tip:AddLine(item.use, green and green.r or 0.12, green and green.g or 1, green and green.b or 0, true)
    tip:AddLine(item.flavor, yellow and yellow.r or 1, yellow and yellow.g or 0.82, yellow and yellow.b or 0, true)
    tip:Show()
    return true
end

function Card:Stat(label, value, show, tip)
    local row = { kind = "stat", height = Window.ROW, value = value, show = show }
    row.label = Glass.Font(self.glass.top, 11, "LEFT")
    row.label:SetText(label)
    row.text = Glass.Font(self.glass.top, 12, "RIGHT")
    if tip then TipArea(row, self.content, tip) end
    self.rows[#self.rows + 1] = row
    return row
end

-- A full-width button for a control; text(S) gives its label.
function Card:Action(id, text, show, tip)
    local row = { kind = "action", height = Window.BUTTON + 4, id = id, caption = text, show = show }
    row.button = NewButton(self.content, id)
    if tip then
        local line = FromGame(tip)
        row.button.tipFn = function()
            local text = line()
            return text and { row.caption(ns.Host.game.S), text } or nil
        end
    end
    self.rows[#self.rows + 1] = row
    return row
end

-- A stat with lower and raise buttons beside its value.
function Card:Adjust(label, value, lower, raise, show, tip)
    local row = self:Stat(label, value, show, tip)
    row.kind, row.height = "adjust", Window.SQUARE + 2
    row.raise = NewButton(self.content, raise, Window.SQUARE)
    row.raise:SetWidth(Window.SQUARE)
    if lower then
        row.lower = NewButton(self.content, lower, Window.SQUARE)
        row.lower:SetWidth(Window.SQUARE)
    end
    return row
end

-- A progress bar under a label (value, max), the numbers rounded as View.count's
-- rounding says (Operations: toward zero; stored power: Math.round).
function Card:Meter(label, value, show, rounding)
    local row = self:Stat(label, function(S)
        local v, m = value(S)
        return View.count(v, rounding) .. " / " .. View.count(m, rounding)
    end, show)
    row.kind, row.height, row.meter = "meter", Window.ROW + 12, value
    row.bar = Glass.Bar(self.content, 8)
    row.bar:SetStatusBarColor(0.3, 0.8, 0.4)
    return row
end

-- A select control: a button showing the selected option. A click opens the list
-- of options below it; choosing one sets it through the host (Host.setValue) in a
-- single step, as choosing it in the reference does. caption(value, S) labels both.
function Card:Select(id, caption, show)
    local row = { kind = "select", height = Window.BUTTON + 4, id = id, caption = caption, show = show,
        choices = {} }
    row.button = NewButton(self.content, nil)
    row.button.company = true
    row.button:SetScript("OnClick", function()
        row.open = not row.open
        Window.Refresh()
    end)
    row.choose = function(value)
        row.open = false
        local ok, err = ns.Host.setValue(id, value)
        if not ok then Report("not done: " .. tostring(err)) end
        Window.Refresh()
    end
    self.rows[#self.rows + 1] = row
    return row
end

-- Up to max lines of text; lines(S, game) returns them (fewer take less room, down
-- to reserve(game) lines when given). alpha(S), when given, fades them. hover, when
-- given, is { over = control, out = control }: the lines become a mouse area whose
-- enter and leave are host commands (the reference's mouseover/mouseout).
function Card:Lines(max, lines, show, alpha, hover, reserve)
    local row = { kind = "lines", height = 0, lines = lines, show = show, strings = {}, alpha = alpha,
        reserve = reserve }
    for i = 1, max do
        row.strings[i] = Glass.Font(self.glass.top, 10, "LEFT")
    end
    if hover then
        row.mouse = CreateFrame("Frame", nil, self.content)
        row.mouse:EnableMouse(true)
        Draggable(row.mouse)
        -- Pointer moves are not player decisions: a refusal (a stopped company) is
        -- not reported on every move.
        local function send(id) ns.Host.click(id) Window.Refresh() end
        row.mouse:SetScript("OnEnter", function() send(hover.over) end)
        row.mouse:SetScript("OnLeave", function() send(hover.out) end)
    end
    self.rows[#self.rows + 1] = row
    return row
end

-- A row of buttons sharing the width, each { id, text, tip }: bulk purchases and
-- their Disassemble All.
function Card:Buttons(list, show)
    local row = { kind = "buttons", height = Window.BUTTON + 4, list = list, show = show, buttons = {} }
    for i, entry in ipairs(list) do row.buttons[i] = NewButton(self.content, entry.id) end
    self.rows[#self.rows + 1] = row
    return row
end

-- A range control: the value over its range as a bar, with lower and raise
-- buttons that set it a step at a time through the host (Host.setValue sanitizes
-- it as the reference's range input does).
function Card:Range(id, label, max, show)
    local row = { kind = "range", height = Window.SQUARE + 20, id = id, max = max, show = show }
    row.label = Glass.Font(self.glass.top, 11, "LEFT")
    row.label:SetText(label)
    row.text = Glass.Font(self.glass.top, 12, "RIGHT")
    row.bar = Glass.Bar(self.content, 8)
    row.bar:SetStatusBarColor(0.4, 0.7, 1)
    local function nudge(delta)
        local game = ns.Host.game
        if not game then return end
        local ok, err = ns.Host.setValue(id, tostring(game.ranges[id].number + delta))
        if not ok then Report("not done: " .. tostring(err)) end
        Window.Refresh()
    end
    -- Every value of the range is reachable: steps of 1 and of 10 each way.
    local function square(delta, text)
        local b = NewButton(self.content, nil, Window.SQUARE)
        b:SetWidth(Window.SQUARE)
        b.company = true
        b:SetScript("OnClick", function() nudge(delta) end)
        b.text = text
        return b
    end
    row.lower10, row.lower = square(-10, "<<"), square(-1, "<")
    row.raise, row.raise10 = square(1, ">"), square(10, ">>")
    -- Reasons for the tooltip when a step cannot move further (#80).
    row.lower10.why, row.lower.why, row.raise.why, row.raise10.why = "why.rangeLow", "why.rangeLow", "why.rangeHigh", "why.rangeHigh"
    self.rows[#self.rows + 1] = row
    return row
end

-- The combat view: the reference's 310x150 battle canvas, scaled to the card. Live
-- ships are 2x2 squares in their team's colour; a destroyed ship flashes white and
-- fades over its ten explosion frames (the reference draws expanding pixels).
-- Textures are pooled and reused; the simulation's ships are only read.
local TEAM = { [0] = { 0.45, 0.75, 1 }, [1] = { 1, 0.35, 0.3 } } -- left (loyal), right (breakaway)
function Card:Battle(show)
    local row = { kind = "battle", show = show, dots = {} }
    row.box = CreateFrame("Frame", nil, self.content)
    row.background = row.box:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints(row.box)
    row.background:SetColorTexture(0, 0, 0, 0.45)
    self.rows[#self.rows + 1] = row
    return row
end

-- Draws the battle's ships into its box. A dot changes colour or size only when its
-- ship's team or state changes; each redraw moves it and sets its fade.
local WHITE = { 1, 1, 1 }
function Window.DrawBattle(row, S)
    local scale, used = row.scale, 0
    for _, ship in ipairs(S.ships) do
        local alpha, kind, color
        if ship.alive then
            alpha, kind, color = 1, ship.team, TEAM[ship.team] or TEAM[0]
        elseif ship.framesDead < 10 then
            alpha, kind, color = 1 - ship.framesDead / 10, "dead", WHITE
        end
        if alpha then
            used = used + 1
            local dot = row.dots[used]
            if not dot then
                dot = row.box:CreateTexture(nil, "ARTWORK")
                row.dots[used] = dot
            end
            if dot.kind ~= kind or dot.scale ~= scale then
                -- At least 2 px (3 for an explosion), so a scaled-down view keeps them.
                local size = math.max(kind == "dead" and 3 or 2, (kind == "dead" and 3 or 2) * scale)
                dot:SetColorTexture(color[1], color[2], color[3], 1)
                dot:SetSize(size, size)
                dot.kind, dot.scale = kind, scale
            end
            dot:SetAlpha(alpha)
            dot:SetPoint("CENTER", row.box, "TOPLEFT", ship.x * scale, -ship.y * scale)
            dot:Show()
        end
    end
    for i = used + 1, #row.dots do
        if row.dots[i]:IsShown() then row.dots[i]:Hide() end
    end
end

-- The photonic chips: ten cells whose brightness follows each chip's value, as the
-- reference sets each chip's opacity (a negative value shows nothing).
function Card:Chips(show)
    local row = { kind = "chips", height = 20, show = show, cells = {} }
    for i = 1, 10 do
        local cell = self.content:CreateTexture(nil, "ARTWORK")
        cell:SetColorTexture(0.45, 0.85, 1, 1)
        cell:SetSize(16, 16)
        row.cells[i] = cell
    end
    self.rows[#self.rows + 1] = row
    return row
end

local function place(region, card, y, inset)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", card.content, "TOPLEFT", inset, y)
end

-- Lays out the visible rows and fills them in; returns whether the card shows.
function Card:Update(game, panels)
    local S = game.S
    local inset = Window.CARD_INSET
    local y = -inset
    local titled = not self.titled or self.titled(panels)
    self.title:SetShown(titled)
    -- A card shown on the previous redraw may tag its new rows; a new card tags
    -- its title only.
    local cardWasShown = self.wasShown
    if titled then
        self.title:ClearAllPoints()
        self.title:SetPoint("TOPLEFT", self.content, "TOPLEFT", inset, y)
        y = y - 18
    end
    local width = Window.COLUMN - 2 * inset
    local any = false
    for _, row in ipairs(self.rows) do
        local visible = not row.show or row.show(S, panels)
        if not row.regions then
            row.regions = {}
            for _, r in pairs({ row.label, row.text, row.button, row.lower, row.raise, row.bar, row.mouse,
                row.lower10, row.raise10, row.box, row.tipArea, row.icon, row.role }) do
                row.regions[#row.regions + 1] = r
            end
            for _, r in ipairs(row.strings or row.cells or row.buttons or {}) do row.regions[#row.regions + 1] = r end
        end
        for _, r in ipairs(row.regions) do r:SetShown(visible) end
        -- The row's "New" tag: after its label, or on its button's corner.
        row.newTag = row.newTag or NewTag(self.glass.top)
        if row.button then row.button.newOf = row end
        if row.raise then row.raise.newOf = row end
        local tagged = NewState(row, visible, cardWasShown)
        row.newTag:SetShown(tagged)
        if tagged then
            row.newTag:SetText(ns.L["new.tag"])
            row.newTag:ClearAllPoints()
            if row.button then
                row.newTag:SetPoint("TOPRIGHT", row.button, "TOPRIGHT", -6, -3)
            elseif row.label then
                row.newTag:SetPoint("LEFT", row.label, "LEFT", row.label:GetStringWidth() + 6, 0)
            end
        end
        if not visible and row.choices then
            row.open = false
            for _, choice in ipairs(row.choices) do choice:Hide() end
        end
        if visible then
            any = true
            if row.kind == "action" then
                place(row.button, self, y - 2, inset)
                row.button:SetWidth(width)
                SetButton(row.button, row.caption(S), not game.disabled[row.id])
            elseif row.kind == "select" then
                local select = game.selects[row.id]
                place(row.button, self, y - 2, inset)
                row.button:SetWidth(width)
                SetButton(row.button, row.caption(select.value, S) .. (row.open and "  ^" or "  v"), true)
                row.height = Window.BUTTON + 4
                for i, option in ipairs(row.open and select.options or {}) do
                    local choice = row.choices[i]
                    if not choice then
                        choice = NewButton(self.content, nil)
                        choice.company = true
                        choice:SetScript("OnClick", function(b) row.choose(b.value) end)
                        row.choices[i] = choice
                    end
                    choice.value = option
                    place(choice, self, y - 2 - row.height, inset + 12)
                    choice:SetWidth(width - 12)
                    SetButton(choice, row.caption(option, S), true)
                    choice:Show()
                    row.height = row.height + Window.BUTTON + 2
                end
                for i = (row.open and #select.options or 0) + 1, #row.choices do row.choices[i]:Hide() end
            elseif row.kind == "lines" then
                local lines = row.lines(S, game)
                local alpha = row.alpha and math.max(0, math.min(1, row.alpha(S))) or 1
                row.height = 0
                for i, fs in ipairs(row.strings) do
                    local text = lines[i]
                    fs:SetShown(text ~= nil)
                    if text then
                        place(fs, self, y - 2 - (i - 1) * 14, inset)
                        fs:SetWidth(width)
                        fs:SetText(text)
                        fs:SetAlpha(alpha)
                        row.height = i * 14 + 4
                    end
                end
                if row.reserve then row.height = math.max(row.height, row.reserve(game) * 14 + 4) end
                if row.mouse then
                    place(row.mouse, self, y, inset)
                    row.mouse:SetSize(width, math.max(row.height, 14))
                end
            elseif row.kind == "buttons" then
                local gap = 4
                local each = (width - gap * (#row.buttons - 1)) / #row.buttons
                for i, b in ipairs(row.buttons) do
                    local entry = row.list[i]
                    place(b, self, y - 2, inset + (i - 1) * (each + gap))
                    b:SetWidth(each)
                    -- Built when hovered, not on every redraw.
                    if entry.tip and not b.tipFn then
                        local line = FromGame(entry.tip)
                        b.tipFn = function()
                            local text = line()
                            return text and { entry.text, text } or nil
                        end
                    end
                    SetButton(b, entry.text, not game.disabled[entry.id], true)
                end
            elseif row.kind == "range" then
                local range = game.ranges[row.id]
                place(row.label, self, y - 4, inset)
                row.text:ClearAllPoints()
                row.text:SetPoint("TOPRIGHT", self.content, "TOPLEFT", inset + width, y - 4)
                row.text:SetText(range.value)
                place(row.lower10, self, y - 18, inset)
                place(row.lower, self, y - 18, inset + Window.SQUARE + 2)
                row.raise10:ClearAllPoints()
                row.raise10:SetPoint("TOPRIGHT", self.content, "TOPLEFT", inset + width, y - 18)
                row.raise:ClearAllPoints()
                row.raise:SetPoint("TOPRIGHT", row.raise10, "TOPLEFT", -2, 0)
                for _, b in ipairs({ row.lower10, row.lower }) do SetButton(b, b.text, range.number > 0, true) end
                for _, b in ipairs({ row.raise, row.raise10 }) do SetButton(b, b.text, range.number < row.max, true) end
                row.bar:ClearAllPoints()
                row.bar:SetPoint("LEFT", row.lower, "RIGHT", 6, 0)
                row.bar:SetPoint("RIGHT", row.raise, "LEFT", -6, 0)
                Glass.SetBar(row.bar, row.max, math.max(0, math.min(range.number, row.max)), true)
            elseif row.kind == "battle" then
                local scale = width / S.battleWIDTH
                row.height = S.battleHEIGHT * scale + 6
                place(row.box, self, y - 2, inset)
                row.box:SetSize(width, S.battleHEIGHT * scale)
                row.scale = scale
                Window.DrawBattle(row, S)
                Window.battleRow = row
            elseif row.kind == "chips" then
                for i, cell in ipairs(row.cells) do
                    place(cell, self, y - 2, inset + (i - 1) * 20)
                    local v = S.qChips[i].value
                    cell:SetAlpha(v > 0 and math.min(v, 1) or 0)
                    cell:SetShown(View.chipShown(S, i))
                end
            else
                if row.icon then
                    place(row.icon, self, y - 2, inset)
                    local icon = ns.Assets.IdentityIcon(row.iconKey)
                    if row.icon.value ~= icon then
                        row.icon:SetTexture(icon)
                        row.icon.value = icon
                    end
                    place(row.label, self, y - 4, inset + 20)
                    if row.role then place(row.role, self, y - 18, inset + 20) end
                else
                    place(row.label, self, y - 4, inset)
                end
                if row.tipArea then
                    place(row.tipArea, self, y, inset)
                    local buttons = row.raise and (Window.SQUARE + (row.lower and Window.SQUARE + 4 or 0) + 6) or 0
                    row.tipArea:SetSize(width - buttons, row.role and row.height or Window.ROW)
                end
                row.text:ClearAllPoints()
                row.text:SetText(row.value(S, game))
                if row.icon then
                    -- The label takes what the value leaves, truncating only when needed.
                    row.label:SetWidth(math.max(40, width - 20 - row.text:GetStringWidth() - 8))
                    -- The role line runs under the label and value, short of the row's buttons.
                    if row.role then
                        local buttons = row.raise and (Window.SQUARE + (row.lower and Window.SQUARE + 4 or 0) + 6) or 0
                        row.role:SetWidth(math.max(40, width - 20 - buttons))
                    end
                end
                if row.kind == "adjust" then
                    row.raise:ClearAllPoints()
                    row.raise:SetPoint("TOPRIGHT", self.content, "TOPLEFT", inset + width, y)
                    SetButton(row.raise, "+", not game.disabled[row.raise.id], true)
                    local left = row.raise
                    if row.lower then
                        row.lower:ClearAllPoints()
                        row.lower:SetPoint("TOPRIGHT", row.raise, "TOPLEFT", -4, 0)
                        SetButton(row.lower, "-", not game.disabled[row.lower.id], true)
                        left = row.lower
                    end
                    row.text:SetPoint("RIGHT", left, "LEFT", -6, 0)
                else
                    row.text:SetPoint("TOPRIGHT", self.content, "TOPLEFT", inset + width, y - 4)
                end
                if row.kind == "meter" then
                    place(row.bar, self, y - Window.ROW + 2, inset)
                    row.bar:SetWidth(width)
                    local v, m = row.meter(S)
                    Glass.SetBar(row.bar, m > 0 and m or 1, math.max(0, math.min(v, m)), true)
                end
            end
            y = y - row.height
        end
    end
    self.frame:SetHeight(-y + inset)
    self.frame:SetShown(any)
    -- The card's own tag, by its title.
    self.newTag = self.newTag or NewTag(self.glass.top)
    local cardTagged = NewState(self, any, true)
    self.newTag:SetShown(cardTagged and titled)
    if cardTagged and titled then
        self.newTag:SetText(ns.L["new.tag"])
        self.newTag:ClearAllPoints()
        self.newTag:SetPoint("LEFT", self.title, "LEFT", self.title:GetStringWidth() + 8, 0)
    end
    return any
end

-- Projects: one button per project on offer, reference order, title and price tag.
-- Offers stay while the player defers them, so the list can outgrow the screen:
-- it shows a page that fits UIParent's height, with Prev/Next to reach the rest.
Window.PROJECT = 40       -- one project button and its gap
Window.CHROME = 200       -- window title, card title, paging row and margins
function Window.ProjectsPerPage()
    -- The Director's strip takes its share of the screen too.
    local chrome = Window.CHROME + ns.Director.MIN_STRIP + Window.GAP
    return math.max(3, math.floor((UIParent:GetHeight() - chrome) / Window.PROJECT))
end

local function NewProjects(parent)
    local card = NewCard(parent, "Projects")
    card.buttons, card.page = {}, 1
    local function turn(step)
        card.page = card.page + step
        Window.Refresh()
    end
    card.prev = NewButton(card.content, nil)
    card.prev:SetWidth(64)
    card.prev:SetScript("OnClick", function() turn(-1) end)
    card.next = NewButton(card.content, nil)
    card.next:SetWidth(64)
    card.next:SetScript("OnClick", function() turn(1) end)
    card.pageText = Glass.Font(card.glass.top, 11, "CENTER")
    function card:Update(game, panels)
        local inset = Window.CARD_INSET
        local list = panels.projects and View.projects(game) or {}
        local perPage = Window.ProjectsPerPage()
        local pages = math.max(1, math.ceil(#list / perPage))
        self.page = math.max(1, math.min(self.page, pages))
        local first = (self.page - 1) * perPage
        self.title:ClearAllPoints()
        self.title:SetPoint("TOPLEFT", self.content, "TOPLEFT", inset, -inset)
        local y = -inset - 18
        local shown = 0
        for i = 1, math.min(perPage, #list - first) do
            local project = list[first + i]
            local b = self.buttons[i]
            if not b then
                b = NewButton(self.content, nil, 36)
                b.label:SetWordWrap(true)
                b.icon = b.glass.top:CreateTexture(nil, "OVERLAY")
                b.icon:SetSize(26, 26)
                b.icon:SetPoint("LEFT", b, "LEFT", 5, 0)
                b.label:SetPoint("LEFT", b, "LEFT", 36, 0)
                self.buttons[i] = b
            end
            b.id = project.id
            local icon = ns.Assets.ProjectIcon(project.name)
            if b.icon.value ~= icon then
                b.icon:SetTexture(icon)
                b.icon.value = icon
            end
            b.tip = { project.title, project.priceTag, project.purpose, project.capacity }
            -- A newly offered project is "New" until hovered or for NEW_SECONDS.
            local seen = Window.seenProjects or {}
            Window.seenProjects = seen
            seen[project.id] = seen[project.id] or {}
            b.newOf = seen[project.id]
            b.newTag = b.newTag or NewTag(b.glass.top)
            local tagged = NewState(seen[project.id], true, true)
            b.newTag:SetShown(tagged)
            if tagged then
                b.newTag:SetText(ns.L["new.tag"])
                b.newTag:ClearAllPoints()
                b.newTag:SetPoint("TOPRIGHT", b, "TOPRIGHT", -6, -3)
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self.content, "TOPLEFT", inset, y)
            b:SetWidth(Window.COLUMN - 2 * inset)
            SetButton(b, project.title .. "\n" .. project.priceTag, project.enabled)
            b:Show()
            y = y - Window.PROJECT
            shown = i
        end
        for i = shown + 1, #self.buttons do self.buttons[i]:Hide() end
        local paging = pages > 1
        self.prev:SetShown(paging)
        self.next:SetShown(paging)
        self.pageText:SetShown(paging)
        if paging then
            self.prev:ClearAllPoints()
            self.prev:SetPoint("TOPLEFT", self.content, "TOPLEFT", inset, y)
            self.next:ClearAllPoints()
            self.next:SetPoint("TOPRIGHT", self.content, "TOPLEFT", Window.COLUMN - inset, y)
            self.pageText:ClearAllPoints()
            self.pageText:SetPoint("TOP", self.content, "TOPLEFT", Window.COLUMN / 2, y - 6)
            self.pageText:SetText(self.page .. " / " .. pages .. " (" .. #list .. " offers)")
            self.prev.why, self.next.why = "why.firstPage", "why.lastPage"
            SetButton(self.prev, "Prev", self.page > 1)
            SetButton(self.next, "Next", self.page < pages)
            y = y - Window.BUTTON - 4
        end
        self.frame:SetHeight(-y + inset)
        self.frame:SetShown(#list > 0)
        return #list > 0
    end
    return card
end

local function Build()
    Glass = Glass or LibStub("LibGlass-1.0"):New() -- one instance (the tooltip may come first)
    Window.Tip()
    -- An item icon that loads later redraws whatever shows it.
    -- The main window redraws every 0.1 s anyway; the check panel on its next tick.
    ns.Assets.onLoaded = function() Window.iconsDirty = true end
    local f = CreateFrame("Frame", "TimeIsMoneyWindow", UIParent)
    f:SetScript("OnShow", function() Window.UpdateEscape() end)
    -- Where the player left it (saved), else above the centre.
    if not ns.Settings.values.point then f:SetPoint("CENTER", UIParent, "CENTER", 0, 80) end
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- The settings keep the position (not the client's layout cache), as the top-left
        -- corner in UIParent units, so a scale change leaves it where it was.
        self:SetUserPlaced(false)
        local s = self:GetScale()
        ns.Settings.Set("point", { "TOPLEFT", "BOTTOMLEFT", self:GetLeft() * s, self:GetTop() * s })
        Window.PlaceWindow()
    end)
    local g = Glass.Apply(f, "large")
    -- A little darker than the bare material (#80), so a model or a nameplate behind
    -- competes less; the panels stay darker still.
    Glass.SetSurfaceTint(g, unpack(Window.MAIN_TINT))
    f.glass = g
    local content = CreateFrame("Frame", nil, f)
    content:SetAllPoints(f)
    content:SetFrameLevel(Glass.ContentLevel(f))
    Window.frame, Window.content = f, content

    local title = Glass.Font(g.top, 14, "LEFT")
    -- Centred on the header buttons' row, clear of the rim (#89).
    title:SetPoint("LEFT", content, "TOPLEFT", Glass.Inset("large") + 6, -Glass.Inset("large") - Window.SQUARE / 2)
    title:SetText("Time Is Money")
    Window.title = title
    title:SetTextColor(COPPER[1], COPPER[2], COPPER[3])
    local close = NewButton(content, nil, Window.SQUARE)
    close:SetWidth(Window.SQUARE)
    close:SetPoint("TOPRIGHT", content, "TOPRIGHT", -Glass.Inset("large"), -Glass.Inset("large"))
    close.label:SetText("x")
    close:SetScript("OnClick", function() f:Hide() end)
    -- Help and settings beside it.
    local settingsButton = NewButton(content, nil, Window.SQUARE)
    settingsButton:SetWidth(Window.SQUARE)
    settingsButton:SetPoint("RIGHT", close, "LEFT", -4, 0)
    -- A cog, not "=" (the label stays empty; the tooltip names it).
    settingsButton.icon = settingsButton.glass.top:CreateTexture(nil, "OVERLAY")
    settingsButton.icon:SetTexture(Window.SETTINGS_ICON)
    settingsButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    settingsButton.icon:SetSize(Window.SQUARE - 12, Window.SQUARE - 12)
    settingsButton.icon:SetPoint("CENTER", settingsButton, "CENTER", 0, 0)
    settingsButton.tipFn = function() return { ns.L["settings.title"] } end
    settingsButton:SetScript("OnClick", function() Window.ToggleSettings() end)
    local helpButton = NewButton(content, nil, Window.SQUARE)
    helpButton:SetWidth(Window.SQUARE)
    helpButton:SetPoint("RIGHT", settingsButton, "LEFT", -4, 0)
    helpButton.label:SetText("?")
    helpButton.tipFn = function() return { ns.L["help.title"] } end
    helpButton:SetScript("OnClick", function() Window.ShowHelp() end)
    -- While paused, an obvious way back (#77): a Resume button in the title bar,
    -- lit like the primary action, beside "(Paused)" in the title.
    local resume = NewButton(content, nil, Window.SQUARE)
    resume:SetWidth(96)
    resume:SetPoint("RIGHT", helpButton, "LEFT", -8, 0)
    Glass.SetSurfaceTint(resume.glass, unpack(Window.PRIMARY_TINT))
    resume.lit = true
    resume.tipFn = function() return { ns.L["window.resume"], ns.L["window.resumeTip"] } end
    resume:SetScript("OnClick", function()
        local ok, err = ns.Host.setPaused(false)
        if not ok then Report("not done: " .. tostring(err)) end
        Window.Refresh()
    end)
    resume:Hide()
    Window.resume = resume

    -- Production: the bolts and the press, then what feeds it.
    local production = NewCard(content, "Production")
    production:Stat("Universe / Sim Level", function(S)
        return JSMath.toString(S.prestigeU + 1) .. " / " .. JSMath.toString(S.prestigeS + 1)
    end, function(_, p) return p.prestige end)
    production:WithIcon(production:Stat(T.clips, function(S) return View.count(S.clips, "ceil") end), "clips")
    production:Action("btnMakePaperclip", function() return T.make end)
    local manufacturing = function(_, p) return p.manufacturing end
    production:Stat("Bolts per second", function(S) return View.count(S.clipRate, "round") end, manufacturing)
    production:WithIcon(production:Stat(T.wire, function(S) return View.count(S.wire) end, manufacturing), "wire")
    production:Action("btnBuyWire", function(S)
        return "Buy " .. View.count(S.wireSupply) .. " " .. T.wire .. " (" .. View.money(S.wireCost) .. ")"
    end,
        manufacturing)
    production:Action("btnToggleWireBuyer", function(S)
        return "Bar Buyer: " .. (S.wireBuyerStatus == 1 and "ON" or "OFF")
    end, function(_, p) return p.manufacturing and p.wireBuyer end)
    local gizmos = function(_, p) return p.manufacturing and p.autoClippers end
    production:WithIcon(production:Stat(T.autoClippers, function(S) return View.count(S.clipmakerLevel) end, gizmos),
        "autoClippers")
    production:Action("btnMakeClipper", function(S) return "Buy Gizmo (" .. View.money(S.clipperCost) .. ")" end, gizmos,
        function(S) return View.exactMoney(S.clipperCost) end)
    local widgets = function(_, p) return p.manufacturing and p.megaClippers end
    production:WithIcon(production:Stat(T.megaClippers, function(S) return View.count(S.megaClipperLevel) end, widgets),
        "megaClippers")
    production:Action("btnMakeMegaClipper", function(S)
        return "Buy Widget (" .. View.money(S.megaClipperCost) .. ")"
    end, widgets, function(S) return View.exactMoney(S.megaClipperCost) end)

    -- Sales: funds, price, demand and campaigns.
    local business = function(_, p) return p.business end
    local sales = NewCard(content, "Sales")
    sales:Stat(T.funds, function(S) return View.moneyFixed(S.funds) end, business, function(S) return View.exactMoney(S.funds) end)
    sales:Stat("Revenue per second", function(S) return View.moneyFixed(S.avgRev) end,
        function(_, p) return p.business and p.revPerSec end)
    sales:Stat(T.unsold, function(S) return View.count(S.unsoldClips) end, business)
    sales:Adjust(T.price, function(S) return View.moneyFixed(S.margin) end, "btnLowerPrice", "btnRaisePrice", business,
        function(S) return View.exactMoney(S.margin) end)
    sales:Stat("Public Demand", function(S) return View.count(S.demand * 10) .. "%" end, business)
    sales:Stat(T.marketing, function(S) return View.count(S.marketingLvl) end, business)
    sales:Action("btnExpandMarketing", function(S) return "Run a Campaign (" .. View.money(S.adCost) .. ")" end,
        business)

    -- The Ledger: trust, its allocation and the operations it buys.
    local ledger = NewCard(content, "The Ledger")
    local computing = function(_, p) return p.computing end
    -- trustDiv and swarmGiftDiv sit inside compDiv: they show only with it.
    local trust = function(_, p) return p.trust end -- inside compDiv (View.panels)
    ledger:Stat(T.trust, function(S) return View.count(S.trust) end, trust)
    -- What the + buttons can still use (#89).
    ledger:Stat("  Available", function(S) return View.count(View.availableTrust(S)) end,
        function(S, p) return p.trust and S.humanFlag == 1 end)
    ledger:Stat("Next Trust at", function(S) return View.count(S.nextTrust) .. " bolts" end, trust)
    ledger:Stat(T.swarmGifts, function(S) return View.count(S.swarmGifts) end,
        function(_, p) return p.swarmGift end)
    ledger:WithIcon(ledger:Adjust(T.processors, function(S) return View.count(S.processors) end, nil, "btnAddProc",
        function(_, p) return p.processor end), "processors")
    ledger:WithIcon(ledger:Adjust(T.memory, function(S) return View.count(S.memory) end, nil, "btnAddMem", computing),
        "memory")
    ledger:Meter(T.operations, function(S) return S.operations, S.memory * 1000 end, computing)
    ledger:Stat(T.creativity, function(S) return View.count(S.creativity) end,
        function(_, p) return p.computing and p.creativity end)

    -- Cartel Investments: risk, cash and stocks, deposits and the engine upgrade.
    local investing = function(_, p) return p.investments end
    local invest = NewCard(content, "Cartel Investments")
    local RISK = { low = "Low Risk", med = "Med Risk", hi = "High Risk" }
    invest:Select("investStrat", function(value) return RISK[value] or value end, investing)
    invest:Stat("Cash", function(S) return View.moneyFixed(S.bankroll) end, investing)
    invest:Stat("Stocks", function(S) return View.moneyFixed(S.secTotal) end, investing)
    invest:Stat("Total", function(S) return View.moneyFixed(S.portTotal) end, investing)
    invest:Action("btnInvest", function() return "Deposit" end, investing)
    invest:Action("btnWithdraw", function() return "Withdraw" end, investing)
    local slots = {}
    invest:Lines(10, function(S) return View.stockLines(S, slots) end, investing)
    invest:Stat("Engine Level", function(S) return View.count(S.investLevel) end, investing)
    invest:Action("btnImproveInvestments", function(S)
        return "Upgrade Engine (" .. View.count(S.investUpgradeCost) .. " " .. T.yomi .. ")"
    end, investing)

    -- Negotiation Simulator: strategy tournaments for Cunning.
    local strategy = function(_, p) return p.strategy end
    local negotiate = NewCard(content, "Negotiation Simulator")
    negotiate:Stat(T.yomi, function(S) return View.count(S.yomi) end, strategy)
    -- The options' text is the strategy each was added for (allStrats[index]).
    negotiate:Select("stratPicker", function(value, S)
        if value == "10" then return "Pick a Strat" end
        local strat = S.allStrats[(tonumber(value) or -1) + 1]
        return strat and strat.name or value
    end, strategy)
    negotiate:Action("btnNewTournament", function(S)
        return "New Tournament (" .. View.count(S.tourneyCost) .. " " .. T.operations .. ")"
    end, strategy)
    negotiate:Action("btnRunTournament", function() return "Run" end, strategy)
    negotiate:Action("btnToggleAutoTourney", function(S)
        return "Auto Tournaments: " .. (S.autoTourneyStatus == 1 and "ON" or "OFF")
    end, function(S, p) return p.strategy and S.autoTourneyFlag == 1 end)
    negotiate:Lines(10, function(_, game) return View.tournament(game) end, strategy, nil,
        { over = "tournamentStuff:mouseover", out = "tournamentStuff:mouseout" }, View.tournamentLines)

    -- Resonance Calculator: the photonic chips and the compute button.
    local quantum = function(_, p) return p.quantum end
    local resonance = NewCard(content, "Resonance Calculator")
    resonance:Chips(quantum)
    resonance:Action("btnQcompute", function() return "Compute" end, function(_, p) return p.quantum and p.qCompute end)
    resonance:Lines(1, function(_, game) return { View.qComp(game) } end, quantum, function(S) return S.qFade end)

    -- Phase II: manufacturing from Available Bolts, the material pipeline, power and
    -- the Company Network. Costs are in bolts (spellf, as the reference prints them).
    local function bolts(x) return View.spell(x) .. " bolts" end
    local creation = function(_, p) return p.creation end
    local factories = NewCard(content, "Manufacturing")
    factories:Stat("Next Upgrade at", function(S) local nfup = View.nextUpgrades(S) return View.count(nfup) .. " Foundries" end,
        function(_, p) return p.creation and p.factoryUpgrade end)
    factories:Stat("Bolts per Second", function(S) return View.spell(S.clipRate) end,
        function(_, p) return p.creation and p.clipsPerSec end)
    factories:Stat(T.unused, function(S) return View.spell(S.unusedClips) end,
        function(_, p) return p.creation and p.toth end)
    local factory = function(_, p) return p.creation and p.factory end
    factories:Stat(T.factories, function(S) return View.count(S.factoryLevel) end, factory)
    factories:Action("btnMakeFactory", function(S) return "Build a Foundry (" .. bolts(S.factoryCost) .. ")" end, factory)
    factories:Buttons({ { id = "btnFactoryReboot", text = "Disassemble All",
        tip = function(S) return "+" .. bolts(S.factoryBill) end } }, factory)
    factories:Stat(T.wire, function(S) return View.spell(S.wire) end, function(_, p) return p.creation and p.wireTrans end)
    factories:Stat(T.factories, function(S) return View.spell(S.factoryLevel) end,
        function(_, p) return p.creation and p.factorySpace end)

    -- wireProductionDiv and powerDiv sit outside creationDiv: their own flags only.
    local function pipeline(_, p) return p.wireProduction end
    local function within(key) return function(_, p) return p.wireProduction and p[key] end end
    local wire = NewCard(content, "Copper Production")
    wire:Stat("Next Upgrade at", function(S) local _, ndup = View.nextUpgrades(S) return View.count(ndup) .. " Drones" end,
        within("droneUpgrade"))
    wire:Stat(T.availableMatter, function(S) return View.spell(S.availableMatter) .. " g" end, pipeline)
    wire:Stat("  per second", function(_, game) return View.spell((game.exploreRate or 0) * 100) .. " g" end,
        within("mdps"))
    wire:Stat(T.acquiredMatter, function(S) return View.spell(S.acquiredMatter) .. " g" end, pipeline)
    wire:Stat("  per second", function(_, game) return View.spell((game.matterRate or 0) * 100) .. " g" end, pipeline)
    wire:Stat(T.wire, function(S) return View.spell(S.wire) end, pipeline)
    wire:Stat("  per second", function(_, game) return View.spell((game.wireRate or 0) * 100) end, pipeline)
    local harvester = within("harvester")
    wire:WithIcon(wire:Stat(T.harvesters, function(S) return View.count(S.harvesterLevel) end, harvester), "harvesters")
    wire:Action("btnMakeHarvester", function(S) return "Build a Reaper (" .. bolts(S.harvesterCost) .. ")" end, harvester)
    wire:Buttons({ { id = "btnHarvesterx10", text = "+10" }, { id = "btnHarvesterx100", text = "+100" },
        { id = "btnHarvesterx1000", text = "+1k" }, { id = "btnHarvesterReboot", text = "Scrap",
            tip = function(S) return "Disassemble All: +" .. bolts(S.harvesterBill) end } }, harvester)
    local wireDrone = within("wireDrone")
    wire:WithIcon(wire:Stat(T.wireDrones, function(S) return View.count(S.wireDroneLevel) end, wireDrone), "wireDrones")
    wire:Action("btnMakeWireDrone", function(S) return "Build a Converter (" .. bolts(S.wireDroneCost) .. ")" end,
        wireDrone)
    wire:Buttons({ { id = "btnWireDronex10", text = "+10" }, { id = "btnWireDronex100", text = "+100" },
        { id = "btnWireDronex1000", text = "+1k" }, { id = "btnWireDroneReboot", text = "Scrap",
            tip = function(S) return "Disassemble All: +" .. bolts(S.wireDroneBill) end } }, wireDrone)
    wire:Stat(T.harvesters, function(S) return View.spell(S.harvesterLevel) end, within("droneSpace"))
    wire:Stat(T.wireDrones, function(S) return View.spell(S.wireDroneLevel) end, within("droneSpace"))

    local function powered(_, p) return p.power end
    -- One set of power figures per redraw, shared by the rows below.
    local function watts(S)
        if Window.powerFor ~= Window.redraw then Window.power, Window.powerFor = View.power(S), Window.redraw end
        return Window.power
    end
    local power = NewCard(content, "Power")
    power:Stat("Performance", function(S) return View.count(watts(S).performance, "round") .. "%" end, powered)
    power:Stat("Consumption", function(S) return View.count(watts(S).consumption, "round") .. " MW" end, powered)
    power:Stat("  Foundries", function(S) return View.count(watts(S).factories, "round") .. " MW" end, powered)
    power:Stat("  Drones", function(S) return View.count(watts(S).drones, "round") .. " MW" end, powered)
    power:Stat("Production", function(S) return View.count(watts(S).production, "round") .. " MW" end, powered)
    power:Meter("Stored", function(S) local w = watts(S) return w.stored, w.capacity end, powered, "round")
    power:WithIcon(power:Stat(T.farms, function(S) return View.count(S.farmLevel) end, powered), "farms")
    power:Action("btnMakeFarm", function(S) return "Build a Core (" .. bolts(S.farmCost) .. ")" end, powered)
    power:Buttons({ { id = "btnFarmx10", text = "+10" }, { id = "btnFarmx100", text = "+100" },
        { id = "btnFarmReboot", text = "Scrap", tip = function(S) return "Disassemble All: +" .. bolts(S.farmBill) end } },
        powered)
    power:WithIcon(power:Stat(T.batteries, function(S) return View.count(S.batteryLevel) end, powered), "batteries")
    power:Action("btnMakeBattery", function(S) return "Build a Pack (" .. bolts(S.batteryCost) .. ")" end, powered)
    power:Buttons({ { id = "btnBatteryx10", text = "+10" }, { id = "btnBatteryx100", text = "+100" },
        { id = "btnBatteryReboot", text = "Scrap",
            tip = function(S) return "Disassemble All: +" .. bolts(S.batteryBill) end } }, powered)

    local swarming = function(_, p) return p.swarm end
    local network = NewCard(content, T.swarm, function(p) return p.swarm end)
    network:Stat("Drones", function(S) return View.spell(math.floor(S.harvesterLevel + S.wireDroneLevel)) end, swarming)
    network:Stat("Status", function(S) return View.swarmStatus(S) or "" end,
        function(S, p) return p.swarm and S.swarmStatus ~= 7 end)
    network:Stat("Next Breakthrough in", function(S) return ns.Workshop.timeCruncher(S.giftCountdown) end,
        function(S, p) return p.swarm and S.swarmStatus == 0 end)
    network:Action("btnEntertainSwarm", function(S)
        return "Entertain the Network (" .. View.count(S.entertainCost) .. " " .. T.creativity .. ")"
    end, function(S, p) return p.swarm and S.swarmStatus == 3 end)
    network:Action("btnSynchSwarm", function(S)
        return "Synchronize the Network (" .. View.count(S.synchCost) .. " " .. T.yomi .. ")"
    end, function(S, p) return p.swarm and S.swarmStatus == 5 end)
    network:Range("slider", "Work  <  >  Think", 200, function(_, p) return p.swarmSlider end)

    -- Phase III: exploration, the dragonling design and combat.
    local spaceShown = function(_, p) return p.space end
    local cosmos = NewCard(content, "Space Exploration")
    cosmos:Stat(T.colonized, function(S) return View.colonized(S) .. "%" end, spaceShown)
    cosmos:Action("btnMakeProbe", function(S) return "Launch a Dragonling (" .. bolts(S.probeCost) .. ")" end, spaceShown)
    cosmos:Stat("Launched", function(S) return ns.Workshop.formatWithCommas(S.probeLaunchLevel) end, spaceShown)
    cosmos:Stat("Descendants", function(S) return View.spell(S.probeDescendents) end, spaceShown)
    cosmos:Stat("Lost to hazards", function(S) return "(" .. View.spell(S.probesLostHaz) .. ")" end,
        function(_, p) return p.space and p.lostHazards end)
    cosmos:Stat("Lost to " .. T.drift, function(S) return "(" .. View.spell(S.probesLostDrift) .. ")" end,
        function(_, p) return p.space and p.lostDrift end)
    -- The reference writes this one only through numberCruncher (combat.js).
    cosmos:Stat("Lost in combat", function(S) return "(" .. View.numberCruncher(S.probesLostCombat) .. ")" end,
        function(_, p) return p.space and p.lostCombat end)
    cosmos:Stat("Total", function(S) return View.spell(S.probeCount) end, spaceShown)
    local drifting = function(_, p) return p.space and p.drifters end
    cosmos:Stat(T.drifters .. " defeated", function(S) return View.spell(S.driftersKilled) end, drifting)
    cosmos:Stat(T.drifters, function(S) return View.spell(S.drifterCount) end, drifting)

    local designing = function(_, p) return p.probeDesign end
    local design = NewCard(content, "Dragonling Design", function(p) return p.probeDesign end)
    design:Stat(T.probeTrust, function(S)
        return JSMath.toString(S.probeUsedTrust) .. " / " .. JSMath.toString(S.probeTrust) .. " ("
            .. ns.Workshop.formatWithCommas(S.maxTrust) .. " Max)"
    end, designing)
    for _, a in ipairs({ { "Speed", T.probeSpeed }, { "Nav", T.probeNav }, { "Rep", T.probeRep }, { "Haz", T.probeHaz },
        { "Fac", T.probeFac }, { "Harv", T.probeHarv }, { "Wire", T.probeWire } }) do
        design:Adjust(a[2], function(S) return JSMath.toString(S["probe" .. a[1]]) end,
            "btnLowerProbe" .. a[1], "btnRaiseProbe" .. a[1], designing)
    end
    design:Adjust(T.probeCombat, function(S) return JSMath.toString(S.probeCombat) end, "btnLowerProbeCombat",
        "btnRaiseProbeCombat", function(_, p) return p.probeDesign and p.combatAllocation end)
    design:Action("btnIncreaseProbeTrust", function(S)
        return "Increase " .. T.probeTrust .. " (" .. ns.Workshop.formatWithCommas(math.floor(S.probeTrustCost)) .. " "
            .. T.yomi .. ")"
    end, function(_, p) return p.increaseProbeTrust end)
    -- The reference never updates this cost's text (the line is commented out), so
    -- it keeps its page default.
    design:Action("btnIncreaseMaxTrust", function() return "Increase Max Trust (91,117.99 " .. T.honor .. ")" end,
        function(_, p) return p.increaseMaxTrust end)
    design:Stat(T.honor, function(S) return ns.Workshop.formatWithCommas(JSMath.round(S.honor)) end,
        function(_, p) return p.honor end)

    local fighting = function(_, p) return p.battle end
    local combat = NewCard(content, "Combat")
    combat:Stat("", function(S) return S.battleName end, fighting)
    combat:Battle(fighting)
    combat:Stat("", function(S)
        local result, amount = View.battleResult(S)
        return result and (result .. "  " .. amount .. " " .. T.honor) or ""
    end, function(S, p) return p.battle and View.battleResult(S) ~= nil end)
    combat:Stat("Scale", function(S) return View.numberCruncher(S.unitSize, 0) .. ":1" end, fighting)

    Window.columns = { { production }, { sales, ledger, factories, wire }, { invest, negotiate, resonance, power, network },
        { cosmos, design, combat }, { NewProjects(content) } }

    -- The Director's strip under the cards.
    Window.strip = ns.Director.Build(content, function(frame, size, justify) return Glass.Font(frame, size, justify) end)

    f:SetScript("OnUpdate", function(_, elapsed)
        Window.elapsed = (Window.elapsed or 0) + elapsed
        Window.clock = Window.clock + elapsed
        Window.battleElapsed = (Window.battleElapsed or 0) + elapsed
        ns.Director.Tick(elapsed) -- the Director's box poll, only while shown
        if Window.elapsed >= Window.REFRESH then
            Window.elapsed, Window.battleElapsed = 0, 0
            Window.Refresh()
        elseif Window.battleElapsed >= Window.BATTLE_REFRESH then
            -- The combat view alone redraws faster, so an explosion's ten 16 ms
            -- frames are seen; nothing else is laid out.
            Window.battleElapsed = 0
            local row, game = Window.battleRow, ns.Host.game
            if row and game and row.box:IsShown() then Window.DrawBattle(row, game.S) end
        end
    end)
    f:SetScript("OnHide", function() Window.CloseStaleDialog() end)
    f:Hide()
end

-- Redraws from the game: card contents, visibility and the window's size.
-- The newest reports, localized, newest first (#83).
function Window.LatestReports(n)
    local list, out = ns.Host.reports, {}
    for i = #list, math.max(1, #list - n + 1), -1 do
        local text = ns.Messages.Translate(list[i].text)
        if text then out[#out + 1] = text end
    end
    return out
end

-- The title bar's own minimum width: the title, then Resume (while paused) and the
-- three square buttons, so a narrow (single-column) window never overlaps them.
function Window.HeaderWidth()
    local inset = Glass.Inset("large")
    local buttons = 3 * Window.SQUARE + 2 * 4
    if Window.resume:IsShown() then buttons = buttons + Window.resume:GetWidth() + 8 end
    return inset + Window.title:GetStringWidth() + 12 + buttons + inset
end

function Window.Refresh()
    local f = Window.frame
    local game = ns.Host.game
    if not (f and f:IsShown() and game) then return end
    local panels = View.panels(game.S)
    Window.redraw = (Window.redraw or 0) + 1
    -- The title says when the company is paused, and an open settings panel follows
    -- any change of company state (a pause, a new game, a halt), only on a change.
    local state = tostring(game) .. tostring(ns.Host.paused) .. tostring(ns.Host.running)
    if state ~= Window.companyState then
        Window.companyState = state
        Window.title:SetText(ns.Host.paused and ("Time Is Money (" .. ns.L["window.paused"] .. ")") or "Time Is Money")
        Window.resume.label:SetText(ns.L["window.resume"])
        Window.resume:SetShown(ns.Host.paused)
        if Window.settings and Window.settings:IsShown() then Window.FillSettings() end
    end
    Window.CloseStaleDialog()
    local inset = Glass.Inset("large")
    -- A column that would outgrow the screen continues in the next one, so the
    -- window never gets taller than UIParent (the projects card pages itself).
    local top = -inset - Window.SQUARE - 4
    local speaker, line = ns.Dialogue.Current(game.S)
    -- Columns leave room for the strip at its smallest; its real height (a long line
    -- wraps further) is measured once laid out.
    local stripHeight = speaker and (ns.Director.MIN_STRIP + Window.GAP) or 0
    local limit = UIParent:GetHeight() - Window.MESSAGE - stripHeight - inset
    local x, tallest = inset, 0
    for _, column in ipairs(Window.columns) do
        local y, shown = top, false
        for _, card in ipairs(column) do
            if card:Update(game, panels) then
                local h = card.frame:GetHeight()
                if shown and -y + h > limit then
                    x = x + Window.COLUMN + Window.GAP
                    y = top
                end
                card.frame:ClearAllPoints()
                card.frame:SetPoint("TOPLEFT", Window.content, "TOPLEFT", x, y)
                y = y - h - Window.GAP
                shown = true
                if -y > tallest then tallest = -y end
            end
        end
        if shown then x = x + Window.COLUMN + Window.GAP end
    end
    local width = math.max(x - Window.GAP + inset, Window.COLUMN + 2 * inset, Window.HeaderWidth())
    Window.strip:ClearAllPoints()
    Window.strip:SetPoint("TOPLEFT", Window.content, "TOPLEFT", inset, -tallest)
    local drawn = ns.Director.Update(speaker, line, width - 2 * inset, Window.LatestReports(ns.Director.REPORT_LINES))
    -- A report since the last redraw (#90): the cue, once the window has drawn once.
    local newest = ns.Host.reports[#ns.Host.reports]
    if newest ~= Window.lastReport then
        if Window.lastReport ~= nil or Window.ready then ns.Director.Report(speaker) end
        Window.lastReport = newest
    end
    if speaker then stripHeight = drawn + Window.GAP end
    Window.UpdateLiveTip()
    local height = tallest + stripHeight + Window.MESSAGE + inset
    f:SetSize(width, height)
    Window.ready = true -- what shows from now on can be "New"
    -- Whatever the content (open selects, many columns), the window fits the screen
    -- in both directions: it scales down when it would not. The player's scale
    -- (settings) applies within that.
    f:SetScale(math.min(ns.Settings.values.scale, (UIParent:GetWidth() - 2 * Window.GAP) / width,
        (UIParent:GetHeight() - 2 * Window.GAP) / height))
    -- Re-anchored only when the scale changed (never mid-drag on every redraw).
    if f:GetScale() ~= Window.placedScale then Window.PlaceWindow() end
end

-- The saved top-left corner (UIParent units) at the window's current scale.
function Window.PlaceWindow()
    local point, f = ns.Settings.values.point, Window.frame
    if not point then return end
    local s = f:GetScale()
    Window.placedScale = s
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", point[3] / s, point[4] / s)
end

-- An explicit yes/no for an action that ends the company: a dialog above the window
-- with the localized question, "yes" and "no". Nothing happens until "yes".
function Window.Confirm(questionKey, onYes)
    if not Window.frame then Build() end
    local d = Window.dialog
    if not d then
        d = CreateFrame("Frame", "TimeIsMoneyConfirm", UIParent)
        d:Hide() -- created shown; hidden first so its first Show fires OnShow (ESC list)
        d:SetScript("OnShow", function() Window.UpdateEscape() end)
        d:SetScript("OnHide", function() Window.EscapeLater() end)
        d:SetSize(340, 120)
        d:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        -- Above the panels (help, settings: DIALOG), so a confirmation opened from them
        -- is always readable and clickable.
        d:SetFrameStrata("FULLSCREEN_DIALOG")
        d:SetToplevel(true)
        d:EnableMouse(true) -- clicks stop here, not on the window behind
        local g = Glass.Apply(d, "large")
        Glass.SetSurfaceTint(g, unpack(Window.PANEL_TINT))
        local content = CreateFrame("Frame", nil, d)
        content:SetAllPoints(d)
        content:SetFrameLevel(Glass.ContentLevel(d))
        d.question = Glass.Font(g.top, 12, "CENTER")
        d.question:SetPoint("TOPLEFT", d, "TOPLEFT", 14, -14)
        d.question:SetPoint("TOPRIGHT", d, "TOPRIGHT", -14, -14)
        d.question:SetWordWrap(true)
        d.yes = NewButton(content, nil)
        d.yes:SetSize(150, Window.BUTTON)
        d.yes:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 14, 14)
        d.no = NewButton(content, nil)
        d.no:SetSize(150, Window.BUTTON)
        d.no:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -14, 14)
        d.no:SetScript("OnClick", function() d:Hide() end)
        Window.dialog = d
    end
    d.question:SetText(ns.L[questionKey])
    d.yes.label:SetText(ns.L["confirm.yes"])
    d.no.label:SetText(ns.L["confirm.no"])
    -- The question belongs to this company: if it is replaced meanwhile, "yes" does
    -- nothing (the dialog also closes with the window, see Refresh and OnHide).
    d.game = ns.Host.game
    d.yes:SetScript("OnClick", function()
        d:Hide()
        if d.game ~= ns.Host.game then return end
        onYes()
    end)
    d:Show()
    d:Raise()
end

-- A dialog left open closes when the window does, or when its company is replaced.
function Window.CloseStaleDialog()
    local d = Window.dialog
    if d and d:IsShown() and (d.game ~= ns.Host.game or not Window.frame:IsShown()) then d:Hide() end
end

-- The new-game control: a fresh company, the prestige kept, after an explicit yes.
function Window.NewGame()
    Window.Confirm("confirm.newGame", function()
        local ok, err = ns.Host.newGame()
        if not ok then Report("not done: " .. tostring(err)) return end
        if Window.frame:IsShown() then Window.Refresh() else Window.Toggle() end
    end)
end

function Window.Toggle()
    if not Window.frame then Build() end
    if Window.frame:IsShown() then
        Window.frame:Hide()
    else
        Window.frame:Show()
        Window.Refresh()
        local game = ns.Host.game
        if game then ns.Director.Greet((ns.Dialogue.Current(game.S))) end
    end
end

-- /tim icons: every identity and icon family with its icon, source and status
-- (resolved, pending, fallback or path), so each can be checked in the client.
-- Hovering an entry lists its source ID and URL and the projects that use it.
-- Only resolved is green: pending waits (yellow), a path is unchecked (amber),
-- a fallback failed (red).
local STATUS_COLOUR = { resolved = { 0.6, 0.9, 0.6 }, pending = { 1, 0.85, 0.3 }, path = { 1, 0.6, 0.2 },
    fallback = { 1, 0.4, 0.3 } }

local function IconEntries()
    local Assets, list = ns.Assets, {}
    for _, entry in ipairs(Assets.IDENTITIES) do
        list[#list + 1] = { title = entry.name, source = Assets.IdentitySource(entry.key), users = {} }
    end
    local families = {}
    for family in pairs(Assets.FAMILIES) do
        if not Assets.FAMILIES[family].identity then families[#families + 1] = family end
    end
    table.sort(families)
    local byFamily = {}
    for _, family in ipairs(families) do
        local source = Assets.Source(family)
        byFamily[family] = { title = source.name, source = source, users = {} }
        list[#list + 1] = byFamily[family]
    end
    -- Projects: under their family, or the identity their family names.
    local identityEntry = {}
    for i, entry in ipairs(Assets.IDENTITIES) do identityEntry[entry.key] = list[i] end
    for _, project in ipairs(ns.Workshop.projects) do
        local family = Assets.PROJECT_FAMILY[project.name]
        local f = family and Assets.FAMILIES[family]
        local target = f and (f.identity and identityEntry[f.identity] or byFamily[family])
        if target then target.users[#target.users + 1] = ns.ProjectText[project.name].title end
    end
    return list
end

-- A glass panel with a title and a close button, shown above the window (help,
-- settings, the icon check). Opening one brings it to the front.
function Window.Panel(name, width, height)
    local p = CreateFrame("Frame", name, UIParent)
    p:SetSize(width, height)
    p:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    p:SetFrameStrata("DIALOG")
    p:SetToplevel(true)
    -- Opening a panel brings it in front of the others.
    p:SetScript("OnShow", function(self) self:Raise() Window.UpdateEscape() end)
    p:SetScript("OnHide", function() Window.EscapeLater() end)
    p:SetClampedToScreen(true)
    p:SetMovable(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    p.glass = Glass.Apply(p, "large")
    -- Nearly opaque: the window behind (its labels, the Director) must not compete
    -- with the panel's text.
    Glass.SetSurfaceTint(p.glass, unpack(Window.PANEL_TINT))
    p.content = CreateFrame("Frame", nil, p)
    p.content:SetAllPoints(p)
    p.content:SetFrameLevel(Glass.ContentLevel(p))
    local inset = Glass.Inset("large")
    p.title = Glass.Font(p.glass.top, 14, "LEFT")
    p.title:SetPoint("TOPLEFT", p, "TOPLEFT", inset + 6, -inset - 4)
    p.title:SetTextColor(COPPER[1], COPPER[2], COPPER[3])
    local close = NewButton(p.content, nil, Window.SQUARE)
    close:SetWidth(Window.SQUARE)
    close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -inset, -inset)
    close.label:SetText("x")
    close:SetScript("OnClick", function() p:Hide() end)
    p:Hide()
    return p
end

local function BuildIcons()
    local f = Window.Panel("TimeIsMoneyIcons", 750, 600)
    f.title:SetText("Time Is Money: icon check")
    f.cells = {}
    -- While shown, look again twice a second: an item can answer later, with or
    -- without a load event.
    f:SetScript("OnUpdate", function(_, elapsed)
        f.elapsed = (f.elapsed or 0) + elapsed
        if f.elapsed >= 0.5 or Window.iconsDirty then
            f.elapsed, Window.iconsDirty = 0, false
            Window.FillIcons()
        end
    end)
    Window.icons = f
end

function Window.FillIcons()
    local f = Window.icons
    local entries = IconEntries()
    local columns, cellW, cellH, inset = 3, 250, 36, Glass.Inset("large")
    for i, entry in ipairs(entries) do
        local cell = f.cells[i]
        if not cell then
            cell = CreateFrame("Frame", nil, f.content)
            cell:SetSize(cellW, cellH - 2)
            cell:EnableMouse(true)
            cell.icon = cell:CreateTexture(nil, "ARTWORK")
            cell.icon:SetSize(32, 32)
            cell.icon:SetPoint("LEFT", cell, "LEFT", 0, 0)
            cell.name = Glass.Font(f.content, 11, "LEFT")
            cell.status = Glass.Font(f.content, 10, "LEFT")
            cell:SetScript("OnEnter", function(self)
                local e = self.entry
                local lines = { e.title, e.source.kind == "texture" and ("texture " .. e.source.path)
                    or (e.source.kind .. " " .. e.source.id .. "  " .. (e.source.url or "")) }
                for _, user in ipairs(e.users) do lines[#lines + 1] = user end
                ShowTip(self, lines)
            end)
            cell:SetScript("OnLeave", function() Window.Tip():Hide() end)
            f.cells[i] = cell
        end
        cell.entry = entry
        local col, row = (i - 1) % columns, math.floor((i - 1) / columns)
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", f.content, "TOPLEFT", inset + col * cellW, -inset - 40 - row * cellH)
        local icon, status = ns.Assets.IconForSource(entry.source)
        cell.icon:SetTexture(icon)
        cell.name:ClearAllPoints()
        cell.name:SetPoint("TOPLEFT", cell, "TOPLEFT", 38, -3)
        cell.name:SetText(entry.title)
        cell.status:ClearAllPoints()
        cell.status:SetPoint("TOPLEFT", cell, "TOPLEFT", 38, -18)
        cell.status:SetText(status .. (#entry.users > 0 and ("  (" .. #entry.users .. " projects)") or ""))
        local colour = STATUS_COLOUR[status] or STATUS_COLOUR.fallback
        cell.status:SetTextColor(colour[1], colour[2], colour[3])
        cell:Show()
    end
    local rows = math.ceil(#entries / columns)
    local width, height = columns * cellW + 2 * inset, rows * cellH + 2 * inset + 40
    f:SetSize(width, height)
    f:SetScale(math.min(1, (UIParent:GetWidth() - 2 * Window.GAP) / width,
        (UIParent:GetHeight() - 2 * Window.GAP) / height))
end

function Window.ToggleIcons()
    if not Window.frame then Build() end
    if not Window.icons then BuildIcons() end
    if Window.icons:IsShown() then
        Window.icons:Hide()
    else
        Window.icons:Show()
        Window.FillIcons()
    end
end

-- Help and settings (#23) -------------------------------------------------------

local function Line(p, size, y, color)
    local fs = Glass.Font(p.glass.top, size, "LEFT")
    fs:SetPoint("TOPLEFT", p, "TOPLEFT", 18, y)
    fs:SetWidth(p:GetWidth() - 36)
    fs:SetWordWrap(true)
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    return fs
end

-- Help: the persistence message (the brief's exact words) and a short guide. Shown
-- once for the first company, and on /tim help or the "?" button.
-- Help in short sections (#80): getting started, the controls one per line, then
-- saving (the brief's exact wording). Each line sits below the last by its measured
-- height (translations wrap differently); the panel grows to fit.
Window.HELP_SECTIONS = {
    { title = "help.startTitle", lines = { "help.play", "help.projects", "help.reports" } },
    { title = "help.controlsTitle", compact = true,
        lines = { "help.cmdLedger", "help.cmdPause", "help.cmdSettings", "help.cmdMinimap", "help.cmdHelp", "help.cmdStatus",
            "help.cmdReports", "help.cmdStart" } },
    { title = "help.persistenceTitle", lines = { "help.persistence" } },
    { title = "help.creditsTitle", lines = { "help.credits", "help.creditsLink" } },
}
function Window.ShowHelp()
    if not Window.frame then Build() end
    local p = Window.help
    if not p then
        p = Window.Panel("TimeIsMoneyHelp", 440, 330)
        p.sections = {}
        for i, section in ipairs(Window.HELP_SECTIONS) do
            local s = { heading = Line(p, 12, 0, COPPER), lines = {} }
            -- Paragraphs muted; the controls list in full white.
            local color = (not section.compact) and MUTED or nil
            for j in ipairs(section.lines) do s.lines[j] = Line(p, 11, 0, color) end
            p.sections[i] = s
        end
        Window.help = p
    end
    local L = ns.L
    p.title:SetText(L["help.title"])
    local y = -46
    for i, section in ipairs(Window.HELP_SECTIONS) do
        local s = p.sections[i]
        s.heading:SetText(L[section.title])
        s.heading:ClearAllPoints()
        s.heading:SetPoint("TOPLEFT", p, "TOPLEFT", 18, y)
        y = y - s.heading:GetStringHeight() - 4
        for j, key in ipairs(section.lines) do
            local line = s.lines[j]
            line:SetText(L[key])
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", p, "TOPLEFT", 24, y)
            line:SetWidth(p:GetWidth() - 24 - 18)
            y = y - line:GetStringHeight() - (section.compact and 2 or 6)
        end
        y = y - 10
    end
    p:SetHeight(-y + 10)
    p:Show()
    p:Raise()
    ns.Settings.Set("helpSeen", true)
end

-- The full report history (#83): newest first, each with its game time; the mouse
-- wheel scrolls it.
Window.REPORT_ROWS = 14
local function Clock(ms)
    if not ms then return "" end
    local t = math.floor(ms / 1000)
    return string.format("%d:%02d:%02d", math.floor(t / 3600), math.floor(t / 60) % 60, t % 60)
end
function Window.FillReports()
    local p = Window.reports
    local list = ns.Host.reports
    local total = #list
    -- Scrolls until the oldest report is at the top.
    p.offset = math.max(0, math.min(p.offset, total - 1))
    p.title:SetText(ns.L["reports.title"])
    -- Rows wrap (translations and long reports take two lines or more), measured
    -- one below the other until the area is full (Codex review of #87).
    -- The first report that does not fit ends the page, so a page is always one
    -- unbroken run of the history (Codex review of #85).
    local y, bottom, shown, full = -46, -46 - Window.REPORT_ROWS * 18, 0, false
    for i, row in ipairs(p.rows) do
        local e = not full and list[total - p.offset - i + 1]
        local fits = e and true or false
        if e then
            row.time:SetText(Clock(e.at))
            row.text:SetText(ns.Messages.Translate(e.text) or "")
            local height = math.max(14, row.text:GetStringHeight())
            fits = shown == 0 or y - height >= bottom
            full = not fits
            if fits then
                row.time:ClearAllPoints()
                row.time:SetPoint("TOPLEFT", p, "TOPLEFT", 18, y)
                row.text:ClearAllPoints()
                row.text:SetPoint("TOPLEFT", p, "TOPLEFT", 18 + 60, y)
                y = y - height - 4
                shown = shown + 1
            end
        end
        row.time:SetShown(fits)
        row.text:SetShown(fits)
    end
    p.empty:SetShown(total == 0)
    p.empty:SetText(ns.L["reports.empty"])
    p.hint:SetShown(total > shown)
    p.hint:SetText(ns.Locale.Format("reports.range", { first = total == 0 and 0 or p.offset + 1,
        last = p.offset + shown, total = total }))
end
function Window.ToggleReports()
    if not Window.frame then Build() end
    local p = Window.reports
    if not p then
        p = Window.Panel("TimeIsMoneyReports", 460, 76 + Window.REPORT_ROWS * 18)
        p.offset, p.rows = 0, {}
        for i = 1, Window.REPORT_ROWS do
            local y = -46 - (i - 1) * 18
            local time = Line(p, 10, y, MUTED)
            time:SetWidth(56)
            local text = Line(p, 11, y)
            text:ClearAllPoints()
            text:SetPoint("TOPLEFT", p, "TOPLEFT", 18 + 60, y)
            text:SetWidth(p:GetWidth() - 18 - 60 - 18)
            text:SetWordWrap(true)
            p.rows[i] = { time = time, text = text }
        end
        p.empty = Line(p, 11, -46, MUTED)
        p.hint = Line(p, 10, -50 - Window.REPORT_ROWS * 18, MUTED)
        p:EnableMouseWheel(true)
        p:SetScript("OnMouseWheel", function(_, delta)
            p.offset = p.offset - delta * 3
            Window.FillReports()
        end)
        Window.reports = p
    end
    if p:IsShown() then p:Hide() return end
    p.offset = 0
    Window.FillReports()
    p:Show()
    p:Raise()
end

-- Settings: the Director's model and voice, the window scale, help, and the new-game
-- control (behind its confirmation).
function Window.ToggleSettings()
    if not Window.frame then Build() end
    local p = Window.settings
    if not p then
        p = Window.Panel("TimeIsMoneySettings", 320, 358)
        local function Changed() Window.FillSettings() Window.Refresh() end
        -- The Director's portrait: two choices, the current one lit.
        p.portraitLabel = Line(p, 11, -50)
        local function Choice(x, on)
            local b = NewButton(p.content, nil)
            b:SetSize(96, Window.BUTTON)
            b:SetPoint("TOPRIGHT", p, "TOPRIGHT", x, -42)
            -- Choosing the current option changes nothing (no model reload).
            b:SetScript("OnClick", function()
                if ns.Settings.values.model ~= on then ns.Director.SetModel(on) Changed() end
            end)
            -- The current choice is marked by a check, not by colour alone.
            b.check = b.glass.top:CreateTexture(nil, "OVERLAY")
            b.check:SetTexture(Window.CHECK_ICON)
            b.check:SetSize(16, 16)
            b.check:SetPoint("LEFT", b, "LEFT", 4, 0)
            return b
        end
        p.modelOn = Choice(-18 - 96 - 4, true)
        p.modelOff = Choice(-18, false)
        -- The greeting: a checkbox.
        -- Checkboxes: a square with a check, its label beside it.
        local function Checkbox(y, onClick)
            local box = NewButton(p.content, nil, Window.SQUARE)
            box:SetWidth(Window.SQUARE)
            box:SetPoint("TOPLEFT", p, "TOPLEFT", 18, y)
            box.check = box.glass.top:CreateTexture(nil, "OVERLAY")
            box.check:SetTexture(Window.CHECK_ICON)
            box.check:SetSize(Window.SQUARE - 6, Window.SQUARE - 6)
            box.check:SetPoint("CENTER", box, "CENTER", 0, 0)
            box:SetScript("OnClick", function() onClick() Changed() end)
            local label = Line(p, 11, y - 10)
            label:ClearAllPoints()
            label:SetPoint("LEFT", box, "RIGHT", 8, 0)
            label:SetWidth(p:GetWidth() - (18 + Window.SQUARE + 8) - 18) -- wraps inside the panel
            return box, label
        end
        p.voice, p.voiceLabel = Checkbox(-78, function() ns.Settings.Set("voice", not ns.Settings.values.voice) end)
        -- The soft sound for a new report (#90).
        p.reportSound, p.reportSoundLabel = Checkbox(-114, function()
            ns.Settings.Set("reportSound", not ns.Settings.values.reportSound)
        end)
        -- The minimap button (#78).
        p.minimap, p.minimapLabel = Checkbox(-150, function() ns.MinimapButton.Toggle() end)
        p.scaleLabel = Line(p, 11, -200)
        p.smaller = NewButton(p.content, nil, Window.SQUARE)
        p.smaller:SetWidth(Window.SQUARE)
        p.smaller:SetPoint("TOPRIGHT", p, "TOPRIGHT", -18 - Window.SQUARE - 4, -192)
        p.smaller.label:SetText("-")
        p.smaller:SetScript("OnClick", function() ns.Settings.StepScale(-1) Window.FillSettings() Window.Refresh() end)
        p.larger = NewButton(p.content, nil, Window.SQUARE)
        p.larger:SetWidth(Window.SQUARE)
        p.larger:SetPoint("TOPRIGHT", p, "TOPRIGHT", -18, -192)
        p.larger.label:SetText("+")
        p.larger:SetScript("OnClick", function() ns.Settings.StepScale(1) Window.FillSettings() Window.Refresh() end)
        -- Pause or resume the company (#77).
        p.pause = NewButton(p.content, nil)
        p.pause:SetSize(284, Window.BUTTON)
        p.pause:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -238)
        p.pause:SetScript("OnClick", function()
            local ok, err = ns.Host.setPaused(not ns.Host.paused)
            if not ok then Report("pause refused: " .. err) end
            Changed()
        end)
        p.helpButton = NewButton(p.content, nil)
        p.helpButton:SetSize(138, Window.BUTTON)
        p.helpButton:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -274)
        p.helpButton:SetScript("OnClick", function() Window.ShowHelp() end)
        p.newGame = NewButton(p.content, nil)
        p.newGame:SetSize(138, Window.BUTTON)
        p.newGame:SetPoint("TOPRIGHT", p, "TOPRIGHT", -18, -274)
        -- While saving is off, changes here are not kept: say so.
        p.notice = Line(p, 10, -312, { 1, 0.5, 0.3 })
        p.newGame:SetScript("OnClick", function()
            if ns.Host.blocked then
                Report("not starting over: " .. ns.Host.blocked .. "; the saved data is kept untouched")
            elseif not ns.Host.game then
                Report("no company yet: /tim start")
            else
                Window.NewGame()
            end
        end)
        Window.settings = p
    end
    if p:IsShown() then p:Hide() return end
    Window.FillSettings()
    p:Show()
    p:Raise()
end

function Window.FillSettings()
    local p, L, v = Window.settings, ns.L, ns.Settings.values
    p.title:SetText(L["settings.title"])
    p.portraitLabel:SetText(L["settings.portrait"])
    p.modelOn.label:SetText(L["settings.portraitModel"])
    p.modelOff.label:SetText(L["settings.portraitFlat"])
    -- The current choice lit; both stay clickable.
    Glass.SetSurfaceTint(p.modelOn.glass, unpack(v.model and Window.PRIMARY_TINT or {}))
    Glass.SetSurfaceTint(p.modelOff.glass, unpack(v.model and {} or Window.PRIMARY_TINT))
    p.modelOn.lit, p.modelOff.lit = v.model, not v.model
    p.modelOn.check:SetShown(v.model)
    p.modelOff.check:SetShown(not v.model)
    p.voice.check:SetShown(v.voice)
    p.reportSound.check:SetShown(v.reportSound)
    p.reportSoundLabel:SetText(L["settings.reportSound"])
    p.voiceLabel:SetText(L["settings.greeting"])
    p.minimap.check:SetShown(v.minimap)
    p.minimapLabel:SetText(L["settings.minimap"])
    p.scaleLabel:SetText(ns.Locale.Format("settings.scale", { percent = math.floor(v.scale * 100 + 0.5) }))
    p.pause.label:SetText(L[ns.Host.paused and "settings.resume" or "settings.pause"])
    p.pause:SetEnabled(ns.Host.game ~= nil and ns.Host.running == true)
    p.helpButton.label:SetText(L["settings.help"])
    p.newGame.label:SetText(L["settings.newGame"])
    p.notice:SetShown(ns.Host.blocked ~= nil)
    if ns.Host.blocked then p.notice:SetText(L["settings.notSaved"]) end
end
