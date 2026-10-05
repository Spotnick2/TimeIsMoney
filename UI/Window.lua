-- The ledger window (#20): Liquid Glass cards over the running company. Plain,
-- unprotected frames. Every control routes through the host's validated commands;
-- the window only reads the game. Hiding it stops its refresh, never the company
-- (the host's own wakeup frame runs the simulation).
local _, ns = ...
local View = ns.View
local T = View.TERMS

local Window = {}
ns.Window = Window
TimeIsMoney.Window = Window

Window.REFRESH = 0.1   -- seconds between redraws while shown (not the logical step)
Window.COLUMN = 236    -- column width
Window.GAP = 8
Window.ROW = 22        -- one line of a card
Window.BUTTON = 24     -- button height ("small" glass: under ~40 px tall)
-- Square buttons stay 32x32: sliced masks fail on boxes small in both directions
-- (16-22 px measured; 32x32 known good; LibGlass GLASS-MATERIAL.md section 6).
Window.SQUARE = 32
Window.MESSAGE = 30    -- the message line under the cards

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
    b:SetScript("OnEnter", function(self)
        if self.tipFn then self.tip = self.tipFn() end
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tip[1], 1, 1, 1)
        for i = 2, #self.tip do GameTooltip:AddLine(self.tip[i], MUTED[1], MUTED[2], MUTED[3], true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

local function NewCard(parent, title)
    local card = setmetatable({ rows = {} }, Card)
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
function Card:Stat(label, value, show)
    local row = { kind = "stat", height = Window.ROW, value = value, show = show }
    row.label = Glass.Font(self.glass.top, 11, "LEFT")
    row.label:SetText(label)
    row.text = Glass.Font(self.glass.top, 12, "RIGHT")
    self.rows[#self.rows + 1] = row
    return row
end

-- A full-width button for a control; text(S) gives its label.
function Card:Action(id, text, show)
    local row = { kind = "action", height = Window.BUTTON + 4, id = id, caption = text, show = show }
    row.button = NewButton(self.content, id)
    self.rows[#self.rows + 1] = row
    return row
end

-- A stat with lower and raise buttons beside its value.
function Card:Adjust(label, value, lower, raise, show)
    local row = self:Stat(label, value, show)
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
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", self.content, "TOPLEFT", inset, y)
    y = y - 18
    local width = Window.COLUMN - 2 * inset
    local any = false
    for _, row in ipairs(self.rows) do
        local visible = not row.show or row.show(S, panels)
        if not row.regions then
            row.regions = {}
            for _, r in pairs({ row.label, row.text, row.button, row.lower, row.raise, row.bar, row.mouse,
                row.lower10, row.raise10 }) do
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
                    b.tipFn = entry.tip and function()
                        local game = ns.Host.game
                        return game and { entry.text, entry.tip(game.S) } or nil
                    end or nil
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
            elseif row.kind == "chips" then
                for i, cell in ipairs(row.cells) do
                    place(cell, self, y - 2, inset + (i - 1) * 20)
                    local v = S.qChips[i].value
                    cell:SetAlpha(v > 0 and math.min(v, 1) or 0)
                end
            else
                place(row.label, self, y - 4, inset)
                row.text:ClearAllPoints()
                row.text:SetText(row.value(S, game))
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
Window.CHROME = 200       -- window title, card title, paging row and message line
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
                self.buttons[i] = b
            end
            b.id = project.id
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
    production:Stat(T.clips, function(S) return View.count(S.clips) end)
    production:Action("btnMakePaperclip", function() return T.make end)
    local manufacturing = function(_, p) return p.manufacturing end
    production:Stat("Bolts per second", function(S) return View.count(S.clipRate) end, manufacturing)
    production:Stat(T.wire, function(S) return View.count(S.wire) end, manufacturing)
    production:Action("btnBuyWire", function(S) return "Buy " .. T.wire .. " (" .. View.coins(S.wireCost) .. ")" end,
        manufacturing)
    production:Action("btnToggleWireBuyer", function(S)
        return "Bar Buyer: " .. (S.wireBuyerStatus == 1 and "ON" or "OFF")
    end, function(_, p) return p.manufacturing and p.wireBuyer end)
    local gizmos = function(_, p) return p.manufacturing and p.autoClippers end
    production:Stat(T.autoClippers, function(S) return View.count(S.clipmakerLevel) end, gizmos)
    production:Action("btnMakeClipper", function(S) return "Buy Gizmo (" .. View.coins(S.clipperCost) .. ")" end, gizmos)
    local widgets = function(_, p) return p.manufacturing and p.megaClippers end
    production:Stat(T.megaClippers, function(S) return View.count(S.megaClipperLevel) end, widgets)
    production:Action("btnMakeMegaClipper", function(S)
        return "Buy Widget (" .. View.coins(S.megaClipperCost) .. ")"
    end, widgets)

    -- Sales: funds, price, demand and campaigns.
    local business = function(_, p) return p.business end
    local sales = NewCard(content, "Sales")
    sales:Stat(T.funds, function(S) return View.coins(S.funds) end, business)
    sales:Stat("Revenue per second", function(S) return View.coins(S.avgRev) end,
        function(_, p) return p.business and p.revPerSec end)
    sales:Stat(T.unsold, function(S) return View.count(S.unsoldClips) end, business)
    sales:Adjust(T.price, function(S) return View.coins(S.margin) end, "btnLowerPrice", "btnRaisePrice", business)
    sales:Stat("Public Demand", function(S) return View.count(S.demand * 10) .. "%" end, business)
    sales:Stat(T.marketing, function(S) return View.count(S.marketingLvl) end, business)
    sales:Action("btnExpandMarketing", function(S) return "Run a Campaign (" .. View.coins(S.adCost) .. ")" end,
        business)

    -- The Ledger: trust, its allocation and the operations it buys.
    local ledger = NewCard(content, "The Ledger")
    local trust = function(_, p) return p.trust end
    local computing = function(_, p) return p.computing end
    ledger:Stat(T.trust, function(S) return View.count(S.trust) end, trust)
    ledger:Stat("Next Trust at", function(S) return View.count(S.nextTrust) .. " bolts" end, trust)
    ledger:Adjust(T.processors, function(S) return View.count(S.processors) end, nil, "btnAddProc", computing)
    ledger:Adjust(T.memory, function(S) return View.count(S.memory) end, nil, "btnAddMem", computing)
    ledger:Meter(T.operations, function(S) return S.operations, S.memory * 1000 end, computing)
    ledger:Stat(T.creativity, function(S) return View.count(S.creativity) end,
        function(_, p) return p.computing and p.creativity end)

    -- Cartel Investments: risk, cash and stocks, deposits and the engine upgrade.
    local investing = function(_, p) return p.investments end
    local invest = NewCard(content, "Cartel Investments")
    local RISK = { low = "Low Risk", med = "Med Risk", hi = "High Risk" }
    invest:Select("investStrat", function(value) return RISK[value] or value end, investing)
    invest:Stat("Cash", function(S) return View.coins(S.bankroll) end, investing)
    invest:Stat("Stocks", function(S) return View.coins(S.secTotal) end, investing)
    invest:Stat("Total", function(S) return View.coins(S.portTotal) end, investing)
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
    resonance:Action("btnQcompute", function() return "Compute" end, quantum)
    resonance:Lines(1, function(_, game) return { View.qComp(game) } end, quantum, function(S) return S.qFade end)

    -- Phase II: manufacturing from Available Bolts, the material pipeline, power and
    -- the Company Network. Costs are in bolts (spellf, as the reference prints them).
    local function bolts(x) return View.spell(x) .. " bolts" end
    local creation = function(_, p) return p.creation end
    local factories = NewCard(content, "Manufacturing")
    factories:Stat("Next Upgrade at", function(S) local nfup = View.nextUpgrades(S) return View.count(nfup) .. " Foundries" end,
        function(_, p) return p.creation and p.factoryUpgrade end)
    factories:Stat("Bolts per Second", function(S) return View.spell(S.clipRate) end, creation)
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
    wire:Stat(T.harvesters, function(S) return View.count(S.harvesterLevel) end, harvester)
    wire:Action("btnMakeHarvester", function(S) return "Build a Reaper (" .. bolts(S.harvesterCost) .. ")" end, harvester)
    wire:Buttons({ { id = "btnHarvesterx10", text = "+10" }, { id = "btnHarvesterx100", text = "+100" },
        { id = "btnHarvesterx1000", text = "+1k" }, { id = "btnHarvesterReboot", text = "Scrap",
            tip = function(S) return "Disassemble All: +" .. bolts(S.harvesterBill) end } }, harvester)
    local wireDrone = within("wireDrone")
    wire:Stat(T.wireDrones, function(S) return View.count(S.wireDroneLevel) end, wireDrone)
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
    power:Stat(T.farms, function(S) return View.count(S.farmLevel) end, powered)
    power:Action("btnMakeFarm", function(S) return "Build a Core (" .. bolts(S.farmCost) .. ")" end, powered)
    power:Buttons({ { id = "btnFarmx10", text = "+10" }, { id = "btnFarmx100", text = "+100" },
        { id = "btnFarmReboot", text = "Scrap", tip = function(S) return "Disassemble All: +" .. bolts(S.farmBill) end } },
        powered)
    power:Stat(T.batteries, function(S) return View.count(S.batteryLevel) end, powered)
    power:Action("btnMakeBattery", function(S) return "Build a Pack (" .. bolts(S.batteryCost) .. ")" end, powered)
    power:Buttons({ { id = "btnBatteryx10", text = "+10" }, { id = "btnBatteryx100", text = "+100" },
        { id = "btnBatteryReboot", text = "Scrap",
            tip = function(S) return "Disassemble All: +" .. bolts(S.batteryBill) end } }, powered)

    local swarming = function(_, p) return p.swarm end
    local network = NewCard(content, T.swarm)
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
    network:Stat(T.swarmGifts, function(S) return View.count(S.swarmGifts) end, swarming)
    network:Range("slider", "Work  <  >  Think", 200, function(_, p) return p.swarmSlider end)

    Window.columns = { { production }, { sales, ledger, factories, wire }, { invest, negotiate, resonance, power, network },
        { NewProjects(content) } }

    -- Messages: the newest reference message (the Director's strip is #22).
    Window.message = Glass.Font(g.top, 11, "LEFT")
    Window.message:SetWordWrap(true)

    f:SetScript("OnUpdate", function(_, elapsed)
        Window.elapsed = (Window.elapsed or 0) + elapsed
        if Window.elapsed >= Window.REFRESH then
            Window.elapsed = 0
            Window.Refresh()
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
    local limit = UIParent:GetHeight() - Window.MESSAGE - inset
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
    Window.message:ClearAllPoints()
    Window.message:SetPoint("TOPLEFT", Window.content, "TOPLEFT", inset, -tallest)
    Window.message:SetWidth(width - 2 * inset)
    Window.message:SetText(game.readouts[1])
    local height = tallest + Window.MESSAGE + inset
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
