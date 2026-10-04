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

local function SetButton(b, text, enabled)
    b:SetEnabled(enabled)
    b.label:SetText(enabled and text or (text .. " (not yet)"))
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
        local regions = { row.label, row.text, row.button, row.lower, row.raise, row.bar }
        for _, r in pairs(regions) do r:SetShown(visible) end
        if visible then
            any = true
            if row.kind == "action" then
                place(row.button, self, y - 2, inset)
                row.button:SetWidth(width)
                SetButton(row.button, row.caption(S), not game.disabled[row.id])
            else
                place(row.label, self, y - 4, inset)
                row.text:ClearAllPoints()
                row.text:SetText(row.value(S))
                if row.kind == "adjust" then
                    row.raise:ClearAllPoints()
                    row.raise:SetPoint("TOPRIGHT", self.content, "TOPLEFT", inset + width, y)
                    SetButton(row.raise, "+", not game.disabled[row.raise.id])
                    row.raise.label:SetText("+")
                    local left = row.raise
                    if row.lower then
                        row.lower:ClearAllPoints()
                        row.lower:SetPoint("TOPRIGHT", row.raise, "TOPLEFT", -4, 0)
                        SetButton(row.lower, "-", not game.disabled[row.lower.id])
                        row.lower.label:SetText("-")
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
local function NewProjects(parent)
    local card = NewCard(parent, "Projects")
    card.buttons = {}
    function card:Update(game, panels)
        local inset = Glass.Inset("large")
        local list = panels.projects and View.projects(game) or {}
        self.title:ClearAllPoints()
        self.title:SetPoint("TOPLEFT", self.content, "TOPLEFT", inset, -inset)
        local y = -inset - 18
        for i, project in ipairs(list) do
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
            y = y - 40
        end
        for i = #list + 1, #self.buttons do self.buttons[i]:Hide() end
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

    Window.columns = { { production }, { sales, ledger }, { NewProjects(content) } }

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
    local inset = Glass.Inset("large")
    local x, tallest = inset, 0
    for _, column in ipairs(Window.columns) do
        local y, shown = -inset - Window.SQUARE - 4, false
        for _, card in ipairs(column) do
            if card:Update(game, panels) then
                card.frame:ClearAllPoints()
                card.frame:SetPoint("TOPLEFT", Window.content, "TOPLEFT", x, y)
                y = y - card.frame:GetHeight() - Window.GAP
                shown = true
            end
        end
        if shown then
            x = x + Window.COLUMN + Window.GAP
            if -y > tallest then tallest = -y end
        end
    end
    local width = math.max(x - Window.GAP + inset, Window.COLUMN + 2 * inset)
    Window.message:ClearAllPoints()
    Window.message:SetPoint("TOPLEFT", Window.content, "TOPLEFT", inset, -tallest)
    Window.message:SetWidth(width - 2 * inset)
    Window.message:SetText(game.readouts[1])
    f:SetSize(width, tallest + 30 + inset)
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
