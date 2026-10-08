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

-- ESC: panels first, then the ledger.
local list = env.UISpecialFrames
local function has(name) for _, n in ipairs(list) do if n == name then return true end end end
assert(has("TimeIsMoneyHelp") and not has("TimeIsMoneyWindow"), "with Help open, ESC closes Help, not the ledger")
Window.help:Hide()
assert(has("TimeIsMoneyWindow"), "then the ledger")
env.SlashCmdList.TIMEISMONEY("settings")
assert(has("TimeIsMoneySettings") and not has("TimeIsMoneyWindow"))
Window.settings:Hide()
assert(has("TimeIsMoneyWindow"))
local count = 0
for _, n in ipairs(list) do if n == "TimeIsMoneyWindow" then count = count + 1 end end
assert(count == 1, "listed once")

print("ux3: action tooltips, shipment size, available trust, capacity hint, fixed coins, own tooltip, credits and ESC order passed")
