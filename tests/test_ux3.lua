-- UX round 3 (#89): every action says what it does, the shipment size on its
-- button, available Board Trust, projects blocked by capacity, fixed-width coins,
-- the addon's own opaque tooltip, credits, and ESC closing panels first.
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns = Harness.Load()
local h = Harness.Helpers(captured)
local Host, Window, View = ns.Host, ns.Window, ns.View

env.SlashCmdList.TIMEISMONEY("start")
local game = Host.game
local S = game.S
Window.Refresh()

-- The addon's own tooltip, from the client's template.
assert(captured.tooltipCreated and captured.tooltipCreated.name == "TimeIsMoneyTooltip"
    and captured.tooltipCreated.template == "GameTooltipTemplate")

-- Every main action has a tooltip saying what it does, available or not.
local function tipOf(id)
    local b = assert(h.button(id), id)
    b.scripts.OnEnter(b)
    local lines = env.GameTooltip.lines
    b.scripts.OnLeave(b)
    return table.concat(lines, "|")
end
S.wireSupply, S.wireCost, S.wire = 1500, 13, 42
Window.Refresh()
assert(h.button("btnBuyWire").label.text:find("^Buy 1,500 Copper Bars %("), "the shipment size on the button")
assert(tipOf("btnBuyWire"):find("Buys 1,500 Copper Bars for", 1, true))
assert(tipOf("btnMakePaperclip"):find("one handful of bolts from one Copper Bar", 1, true) and tipOf("btnMakePaperclip"):find("Copper Bars left: 42", 1, true))
assert(tipOf("btnLowerPrice"):find("Lowers the price", 1, true) and tipOf("btnRaisePrice"):find("Raises the price", 1, true))
S.funds, S.adCost, S.marketingLvl = 0, 100, 1
Host.update(0.02)
Window.Refresh()
local campaign = tipOf("btnExpandMarketing")
assert(campaign:find("Raises demand by 10%", 1, true) and campaign:find("Not enough Company Funds", 1, true),
    "what it does, and why not now")
for _, id in ipairs({ "btnMakePaperclip", "btnBuyWire", "btnToggleWireBuyer", "btnMakeClipper", "btnMakeMegaClipper",
    "btnExpandMarketing", "btnLowerPrice", "btnRaisePrice", "btnAddProc", "btnAddMem" }) do
    assert(View.actionTip(id, S) and #View.actionTip(id, S) >= 1, "a description for " .. id)
end

-- Every action control the window builds says what it does (Codex review of #91):
-- scanned from the window's source, plus the generated probe allocations.
local source = assert(io.open("UI/Window.lua", "rb")):read("*a")
local ids, scanned = {}, 0
for id in source:gmatch('Action%("(btn%w+)"') do ids[id] = true end
for id in source:gmatch('id = "(btn%w+)"') do ids[id] = true end
for id in source:gmatch('"(btn%w+)", function') do ids[id] = true end
for _, id in ipairs({ "btnLowerPrice", "btnRaisePrice", "btnAddProc", "btnAddMem" }) do ids[id] = true end
for _, name in ipairs({ "Speed", "Nav", "Rep", "Haz", "Fac", "Harv", "Wire", "Combat" }) do
    ids["btnRaiseProbe" .. name], ids["btnLowerProbe" .. name] = true, true
end
for id in pairs(ids) do
    local tip = View.actionTip(id, S)
    assert(tip and #tip >= 1 and not tip[1]:find("^act%."), "a description for " .. id)
    scanned = scanned + 1
end
assert(scanned >= 50, "the scan found the actions: " .. scanned)
-- Unlocked later: the investment engine's buttons, enabled and disabled.
S.investmentEngineFlag = 1
Window.Refresh()
local deposit = h.button("btnInvest")
assert(deposit, "the Deposit button shows once the engine is unlocked")
do
    assert(tipOf("btnInvest"):find("Moves your Company Funds", 1, true))
end
assert(View.actionTip("btnInvest", S)[1]:find("copper fraction is lost", 1, true))

-- Investment cash, stocks and total keep a fixed width too.
assert(source:find('invest:Stat%("Cash", function%(S%) return View.moneyFixed'), "cash is fixed-width")

-- Available Board Trust beside the total.
S.compFlag, S.trust, S.processors, S.memory = 1, 7, 3, 2
Window.Refresh()
assert(View.availableTrust(S) == 2 and h.shownText("Available"))

-- A project costing more Operations than the Punch Cards hold says how to get there.
S.memory = 0 -- no capacity: any Operations price exceeds it
local blocked
for _, p in ipairs(View.projects(game)) do
    if ns.ProjectText[p.name].priceTag and ns.ProjectText[p.name].priceTag:find(" ops", 1, true) then blocked = p end
end
assert(blocked, "an Operations-priced project is on offer")
assert(blocked.capacity and blocked.capacity:find("add Punch Cards", 1, true), "it says how to get there")
S.memory = 1000
for _, p in ipairs(View.projects(game)) do assert(p.capacity == nil, "no capacity line when it fits") end

-- Fixed-width coins for right-aligned values.
local I = View.COIN_ICONS
-- One reference unit is one silver: 205.04 is 2 gold 5 silver 4 copper.
assert(View.moneyFixed(205.04) == "2" .. I.g .. " 05" .. I.s .. " 04" .. I.c)
assert(View.moneyFixed(50.04) == "50" .. I.s .. " 04" .. I.c and View.moneyFixed(0.09) == "9" .. I.c)
assert(View.moneyFixed(200) == "2" .. I.g .. " 00" .. I.s .. " 00" .. I.c)
assert(View.money(200) == "2" .. I.g, "buttons and tags stay compact")

-- Credits.
Window.ShowHelp()
assert(h.shownText("a game by Frank Lantz") and h.shownText("Bennett Foddy") and h.shownText("decisionproblem.com/paperclips"))

-- ESC: panels first, then the ledger. An ESC press as the client makes it: every
-- shown frame named in UISpecialFrames is hidden, walking the table with pairs.
local list = env.UISpecialFrames
local function has(name) for _, n in ipairs(list) do if n == name then return true end end end
local function esc()
    for _, name in pairs(list) do
        local f = env[name]
        if f and f:IsShown() then f:Hide() end
    end
    captured:RunTimers() -- the next frame
end
assert(has("TimeIsMoneyHelp") and not has("TimeIsMoneyWindow"), "with Help open, ESC closes Help, not the ledger")
esc()
assert(not Window.help:IsShown() and Window.frame:IsShown(), "one ESC: Help only (the ledger is listed only afterwards)")
assert(has("TimeIsMoneyWindow"), "then the ledger is listed")
env.SlashCmdList.TIMEISMONEY("settings")
assert(has("TimeIsMoneySettings") and not has("TimeIsMoneyWindow"))
esc()
assert(not Window.settings:IsShown() and Window.frame:IsShown())
-- The first confirmation of the session is listed too (it starts hidden).
Window.NewGame()
assert(Window.dialog:IsShown() and has("TimeIsMoneyConfirm") and not has("TimeIsMoneyWindow"), "the first confirmation")
esc()
assert(not Window.dialog:IsShown() and Window.frame:IsShown(), "ESC closes only the confirmation")
esc()
assert(not Window.frame:IsShown(), "and the next ESC the ledger")
local count = 0
for _, n in ipairs(list) do if n == "TimeIsMoneyWindow" then count = count + 1 end end
assert(count == 1, "listed once")
env.SlashCmdList.TIMEISMONEY("")

-- A hovered tooltip stays the same size across redraws (lines are rebuilt, never
-- appended to the button's own tip).
local make = h.button("btnMakePaperclip")
make.scripts.OnEnter(make)
local n1 = #env.GameTooltip.lines
for _ = 1, 5 do Window.Refresh() end
assert(#env.GameTooltip.lines == n1, "no growth while hovered: " .. #env.GameTooltip.lines .. " vs " .. n1)
make.scripts.OnLeave(make)
make.scripts.OnEnter(make)
assert(#env.GameTooltip.lines == n1, "and none carried into the next hover")
make.scripts.OnLeave(make)

-- A lit button keeps its tint through a press (Resume while paused).
assert(Host.setPaused(true))
Window.Refresh()
local resume = Window.resume
local lit = resume.glass.surfaceTint
resume.scripts.OnEnter(resume)
resume.scripts.OnMouseDown(resume)
resume.scripts.OnMouseUp(resume)
resume.scripts.OnLeave(resume)
assert(resume.glass.surfaceTint == lit, "Resume stays lit")
assert(Host.setPaused(false))

-- Capacity: a computed Operations price counts (Photonic Chips); a negative one
-- (the reversion) never asks for Punch Cards.
local function capacityFor(name)
    local entry
    for _, e in ipairs(ns.Workshop.projects) do if e.name == name then entry = e end end
    game.S.activeProjects = { { id = entry.id } }
    return View.projects(game)[1].capacity
end
S.memory, S.qChipCost, S.project51 = 5, 10000, { flag = 0 }
assert(capacityFor("project51") and capacityFor("project51"):find("10,000", 1, true), "the computed chip price")
S.memory = 0
assert(capacityFor("project217") == nil, "a negative price never needs capacity")

-- Every card's title says what the card is for (owner, 2026-10-08).
local cards = 0
for _, column in ipairs(Window.columns) do
    for _, card in ipairs(column) do
        local title = card.title.text
        local key = Window.CARD_KEYS[title] or (title == View.TERMS.swarm and "network")
        assert(key and not ns.L["card." .. key]:find("^card%."), "a description for " .. tostring(title))
        cards = cards + 1
    end
end
assert(cards >= 14, "every card: " .. cards)

-- The crystals: the Arcane Crystal icon, charge as opacity, red while negative,
-- faint slots for the ones not owned, and a tooltip.
local chipRow
for _, column in ipairs(Window.columns) do
    for _, card in ipairs(column) do
        for _, row in ipairs(card.rows or {}) do if row.kind == "chips" then chipRow = row end end
    end
end
S.qChips[1].active, S.qChips[2].active = 1, 1
S.qChips[1].value, S.qChips[2].value, S.qChips[3].value = 0.6, -0.5, 0
S.qFlag = 1
Window.Refresh()
local c1, c2, c3 = chipRow.cells[1], chipRow.cells[2], chipRow.cells[3]
assert(c1.icon == ns.Assets.IdentityIcon("chips"), "the Arcane Crystal icon")
assert(math.abs(c1.alpha - 0.6) < 1e-9 and c1.vertexColor[2] == 1, "positive: as is, by its charge")
assert(math.abs(c2.alpha - 0.5) < 1e-9 and c2.vertexColor[2] < 0.5, "negative: red, never invisible")
assert(c3.alpha == 0 and chipRow.slots[3].shown, "not owned: an empty slot")
chipRow.tipArea.scripts.OnEnter(chipRow.tipArea)
assert(env.GameTooltip.lines[1] == "Arcane Crystals: 2 of 10", "the tooltip counts them")
chipRow.tipArea.scripts.OnLeave(chipRow.tipArea)

print("ux3: action tooltips, shipment size, available trust, capacity hint, fixed coins, own tooltip, credits and ESC order passed")
