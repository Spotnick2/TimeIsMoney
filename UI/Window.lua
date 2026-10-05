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
-- Room under the cards: the Director's strip (#22). The reference's messages are not
-- shown in their own wording.
Window.MESSAGE = 4

local COPPER = { 0.85, 0.6, 0.4 }
local MUTED = { 0.7, 0.7, 0.7 }

local Glass

local function Report(message)
    print("|cffd9a066Time Is Money|r: " .. message)
end

-- Commands: the host validates and applies them at the current logical time.
local function Click(id)
    local ok, err = ns.Host.click(id)
    if not ok then Report("not done: " .. tostring(err)) end
    Window.Refresh()
end

-- Tooltips: one renderer. lines[1] is the white title, the rest wrap muted.
local function ShowTip(owner, lines)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(lines[1], 1, 1, 1)
    for i = 2, #lines do GameTooltip:AddLine(lines[i], MUTED[1], MUTED[2], MUTED[3], true) end
    GameTooltip:Show()
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
    b.glass = Glass.Apply(b, "small")
    b.label = Glass.Font(b.glass.top, 11, "CENTER")
    b.label:SetPoint("LEFT", b, "LEFT", 4, 0)
    b.label:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    b.id = id
    b:SetScript("OnClick", function(self) if self.id then Click(self.id) end end)
    -- Live like every hover tooltip: re-read on each redraw while hovered, so a cost
    -- that changes under the pointer (a purchase) shows its new value and title.
    b:SetScript("OnEnter", function(self)
        Window.liveTip = { owner = self, lines = function()
            if self.tipFn then self.tip = self.tipFn() end
            return self.tip
        end }
        Window.UpdateLiveTip()
    end)
    b:SetScript("OnLeave", function(self)
        if Window.liveTip and Window.liveTip.owner == self then Window.liveTip = nil end
        GameTooltip:Hide()
    end)
    b:SetMotionScriptsWhileDisabled(true)
    return b
end

local function SetButton(b, text, enabled, short)
    b:SetEnabled(enabled)
    -- Square buttons have no room for words: "(+)" marks them unavailable.
    if short then
        b.label:SetText(enabled and text or ("(" .. text .. ")"))
    else
        b.label:SetText(enabled and text or (text .. " (not yet)"))
    end
    if enabled then b.label:SetTextColor(1, 1, 1) else b.label:SetTextColor(MUTED[1], MUTED[2], MUTED[3]) end
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
    card.glass = Glass.Apply(f, "large")
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
local function TipArea(row, parent, tip)
    local line = FromGame(tip)
    row.tipArea = CreateFrame("Frame", nil, parent)
    row.tipArea:EnableMouse(true)
    Draggable(row.tipArea)
    row.tipArea:SetScript("OnEnter", function(area)
        Window.liveTip = { owner = area, lines = function()
            local text = line()
            return text and { row.label:GetText() or "", text } or nil
        end }
        Window.UpdateLiveTip()
    end)
    row.tipArea:SetScript("OnLeave", function(area)
        if Window.liveTip and Window.liveTip.owner == area then Window.liveTip = nil end
        GameTooltip:Hide()
    end)
end

-- The hovered tooltip (a button or a row), refreshed on each redraw: it appears,
-- changes or goes as its lines do.
function Window.UpdateLiveTip()
    local tip = Window.liveTip
    if not tip then return end
    local lines = tip.lines()
    if lines then
        ShowTip(tip.owner, lines)
        tip.shown = true
    elseif tip.shown then
        GameTooltip:Hide()
        tip.shown = false
    end
end

-- An identity's item icon at the start of a row (Assets), the label after it.
function Card:WithIcon(row, key)
    row.icon = self.content:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.iconKey = key
    return row
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

-- A progress bar under a label (value, max).
function Card:Meter(label, value, show)
    local row = self:Stat(label, function(S) local v, m = value(S) return View.count(v) .. " / " .. View.count(m) end,
        show)
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
        b:SetScript("OnClick", function() nudge(delta) end)
        b.text = text
        return b
    end
    row.lower10, row.lower = square(-10, "<<"), square(-1, "<")
    row.raise, row.raise10 = square(1, ">"), square(10, ">>")
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
    local inset = Glass.Inset("large")
    local y = -inset
    local titled = not self.titled or self.titled(panels)
    self.title:SetShown(titled)
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
                row.lower10, row.raise10, row.box, row.tipArea, row.icon }) do
                row.regions[#row.regions + 1] = r
            end
            for _, r in ipairs(row.strings or row.cells or row.buttons or {}) do row.regions[#row.regions + 1] = r end
        end
        for _, r in ipairs(row.regions) do r:SetShown(visible) end
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
                else
                    place(row.label, self, y - 4, inset)
                end
                if row.tipArea then
                    place(row.tipArea, self, y, inset)
                    local buttons = row.raise and (Window.SQUARE + (row.lower and Window.SQUARE + 4 or 0) + 6) or 0
                    row.tipArea:SetSize(width - buttons, Window.ROW)
                end
                row.text:ClearAllPoints()
                row.text:SetText(row.value(S, game))
                if row.icon then
                    -- The label takes what the value leaves, truncating only when needed.
                    row.label:SetWidth(math.max(40, width - 20 - row.text:GetStringWidth() - 8))
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
    return any
end

-- Projects: one button per project on offer, reference order, title and price tag.
-- Offers stay while the player defers them, so the list can outgrow the screen:
-- it shows a page that fits UIParent's height, with Prev/Next to reach the rest.
Window.PROJECT = 40       -- one project button and its gap
Window.CHROME = 200       -- window title, card title, paging row and margins
function Window.ProjectsPerPage()
    return math.max(3, math.floor((UIParent:GetHeight() - Window.CHROME) / Window.PROJECT))
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
        local inset = Glass.Inset("large")
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
            b.tip = { project.title, project.priceTag, project.purpose }
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
    Glass = LibStub("LibGlass-1.0"):New()
    -- An item icon that loads later redraws whatever shows it.
    -- The main window redraws every 0.1 s anyway; the check panel on its next tick.
    ns.Assets.onLoaded = function() Window.iconsDirty = true end
    local f = CreateFrame("Frame", "TimeIsMoneyWindow", UIParent)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local g = Glass.Apply(f, "large")
    local content = CreateFrame("Frame", nil, f)
    content:SetAllPoints(f)
    content:SetFrameLevel(Glass.ContentLevel(f))
    Window.frame, Window.content = f, content

    local title = Glass.Font(g.top, 14, "LEFT")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", Glass.Inset("large"), -Glass.Inset("large"))
    title:SetText("Time Is Money")
    title:SetTextColor(COPPER[1], COPPER[2], COPPER[3])
    local close = NewButton(content, nil, Window.SQUARE)
    close:SetWidth(Window.SQUARE)
    close:SetPoint("TOPRIGHT", content, "TOPRIGHT", -Glass.Inset("large"), -Glass.Inset("large"))
    close.label:SetText("x")
    close:SetScript("OnClick", function() f:Hide() end)

    -- Production: the bolts and the press, then what feeds it.
    local production = NewCard(content, "Production")
    production:Stat("Universe / Sim Level", function(S)
        return JSMath.toString(S.prestigeU + 1) .. " / " .. JSMath.toString(S.prestigeS + 1)
    end, function(_, p) return p.prestige end)
    production:WithIcon(production:Stat(T.clips, function(S) return View.count(S.clips) end), "clips")
    production:Action("btnMakePaperclip", function() return T.make end)
    local manufacturing = function(_, p) return p.manufacturing end
    production:Stat("Bolts per second", function(S) return View.count(S.clipRate) end, manufacturing)
    production:WithIcon(production:Stat(T.wire, function(S) return View.count(S.wire) end, manufacturing), "wire")
    production:Action("btnBuyWire", function(S) return "Buy " .. T.wire .. " (" .. View.money(S.wireCost) .. ")" end,
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
    sales:Stat(T.funds, function(S) return View.money(S.funds) end, business, function(S) return View.exactMoney(S.funds) end)
    sales:Stat("Revenue per second", function(S) return View.money(S.avgRev) end,
        function(_, p) return p.business and p.revPerSec end)
    sales:Stat(T.unsold, function(S) return View.count(S.unsoldClips) end, business)
    sales:Adjust(T.price, function(S) return View.money(S.margin) end, "btnLowerPrice", "btnRaisePrice", business,
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
    invest:Stat("Cash", function(S) return View.money(S.bankroll) end, investing)
    invest:Stat("Stocks", function(S) return View.money(S.secTotal) end, investing)
    invest:Stat("Total", function(S) return View.money(S.portTotal) end, investing)
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
    power:Stat("Performance", function(S) return View.count(watts(S).performance) .. "%" end, powered)
    power:Stat("Consumption", function(S) return View.count(watts(S).consumption) .. " MW" end, powered)
    power:Stat("  Foundries", function(S) return View.count(watts(S).factories) .. " MW" end, powered)
    power:Stat("  Drones", function(S) return View.count(watts(S).drones) .. " MW" end, powered)
    power:Stat("Production", function(S) return View.count(watts(S).production) .. " MW" end, powered)
    power:Meter("Stored", function(S) local w = watts(S) return w.stored, w.capacity end, powered)
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
    Window.strip = ns.Director.Build(content, function(size, justify) return Glass.Font(g.top, size, justify) end)

    f:SetScript("OnUpdate", function(_, elapsed)
        Window.elapsed = (Window.elapsed or 0) + elapsed
        Window.battleElapsed = (Window.battleElapsed or 0) + elapsed
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
    f:Hide()
end

-- Redraws from the game: card contents, visibility and the window's size.
function Window.Refresh()
    local f = Window.frame
    local game = ns.Host.game
    if not (f and f:IsShown() and game) then return end
    local panels = View.panels(game.S)
    Window.redraw = (Window.redraw or 0) + 1
    local inset = Glass.Inset("large")
    -- A column that would outgrow the screen continues in the next one, so the
    -- window never gets taller than UIParent (the projects card pages itself).
    local top = -inset - Window.SQUARE - 4
    local speaker, line = ns.Dialogue.Current(game.S)
    local stripHeight = speaker and (ns.Director.STRIP + Window.GAP) or 0
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
    local width = math.max(x - Window.GAP + inset, Window.COLUMN + 2 * inset)
    Window.strip:ClearAllPoints()
    Window.strip:SetPoint("TOPLEFT", Window.content, "TOPLEFT", inset, -tallest)
    ns.Director.Update(speaker, line, width - 2 * inset)
    Window.UpdateLiveTip()
    local height = tallest + stripHeight + Window.MESSAGE + inset
    f:SetSize(width, height)
    -- Whatever the content (open selects, many columns), the window fits the screen
    -- in both directions: it scales down when it would not.
    f:SetScale(math.min(1, (UIParent:GetWidth() - 2 * Window.GAP) / width,
        (UIParent:GetHeight() - 2 * Window.GAP) / height))
end

function Window.Toggle()
    if not Window.frame then Build() end
    if Window.frame:IsShown() then
        Window.frame:Hide()
    else
        Window.frame:Show()
        Window.Refresh()
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

local function BuildIcons()
    local f = CreateFrame("Frame", "TimeIsMoneyIcons", UIParent)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local g = Glass.Apply(f, "large")
    local content = CreateFrame("Frame", nil, f)
    content:SetAllPoints(f)
    content:SetFrameLevel(Glass.ContentLevel(f))
    local title = Glass.Font(g.top, 14, "LEFT")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", Glass.Inset("large"), -Glass.Inset("large"))
    title:SetText("Time Is Money: icon check")
    title:SetTextColor(COPPER[1], COPPER[2], COPPER[3])
    local close = NewButton(content, nil, Window.SQUARE)
    close:SetWidth(Window.SQUARE)
    close:SetPoint("TOPRIGHT", content, "TOPRIGHT", -Glass.Inset("large"), -Glass.Inset("large"))
    close.label:SetText("x")
    close:SetScript("OnClick", function() f:Hide() end)
    f.content, f.cells = content, {}
    -- While shown, look again twice a second: an item can answer later, with or
    -- without a load event.
    f:SetScript("OnUpdate", function(_, elapsed)
        f.elapsed = (f.elapsed or 0) + elapsed
        if f.elapsed >= 0.5 or Window.iconsDirty then
            f.elapsed, Window.iconsDirty = 0, false
            Window.FillIcons()
        end
    end)
    f:Hide() -- a new frame is shown; the toggle opens it
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
            cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
