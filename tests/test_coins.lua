-- Coins (#21): one reference unit is one silver, display only.
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns, libGlass = Harness.Load()
local h = Harness.Helpers(captured)
local View, Host, Window = ns.View, ns.Host, ns.Window

-- The spec's examples (section 4).
assert(View.coins(0.25) == "25c" and View.coins(1) == "1s" and View.coins(123.45) == "1g 23s 45c")
assert(View.coins(1000000) == "10,000g")
-- Negative keeps its sign; a value rounding to nothing shows none; zero is 0c.
assert(View.coins(-123.45) == "-1g 23s 45c" and View.coins(-0.004) == "0c" and View.coins(0) == "0c")
-- Huge: past exact whole copper only the gold shows, still with its sign.
assert(View.coins(1e30) == View.count(1e28) .. "g" and View.coins(-1e30) == "-" .. View.count(1e28) .. "g")
-- Non-finite values say so.
assert(View.coins(1 / 0) == "Infinity" and View.coins(0 / 0) == "NaN")
-- Icons: the same parts, each followed by its coin texture.
local G, S_, C = View.COIN_ICONS.g, View.COIN_ICONS.s, View.COIN_ICONS.c
assert(View.money(123.45) == "1" .. G .. " 23" .. S_ .. " 45" .. C)
assert(G == "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t")
-- The exact amount when the coins round it, for the tooltip; none when exact.
assert(View.exactMoney(0.25) == nil and View.exactMoney(123.45) == nil)
assert(View.exactMoney(0.2537) == "Exactly 0.2537 silver (25c shown)")
assert(View.exactMoney(1e30) == nil and View.exactMoney(0 / 0) == nil)
-- Whole copper by the number's own text, not float products (0.29 * 100 is not 29).
assert(View.exactMoney(0.29) == nil and View.exactMoney(0.07) == nil and View.exactMoney(1.13) == nil)
assert(View.exactMoney(0.1 + 0.2) == "Exactly 0.30000000000000004 silver (30c shown)")
-- Price tags in coins.
assert(View.priceTag("project40b", { bribe = 1000000 }, View.money) == "(10,000" .. G .. ")")

-- In the window: funds in coin icons, with the exact amount on hover, live.
env.SlashCmdList.TIMEISMONEY("start")
local game = Host.game
game.S.funds = 0
local disabledBefore = game.disabled.btnBuyWire
Window.Refresh()
-- The tooltip areas: mouse frames that also drag the window.
local areas = {}
for _, w in ipairs(captured.widgets) do
    if w.kind == "Frame" and w.scripts.OnEnter and w.scripts.OnDragStart and h.visible(w) and not w.itemKey and not w.cardTitle then
        areas[#areas + 1] = w
    end
end
assert(#areas >= 2, "funds and price have tooltip areas")
-- The price row's area stops short of its -/+ buttons (two 32 px squares). Rows span
-- the card inside its padding (Window.CARD_INSET, 8 px each side).
local widths = {}
for _, area in ipairs(areas) do widths[area.width] = true end
assert(widths[220] and widths[220 - (32 + 32 + 4 + 6)], "funds spans the row; the price stops at its buttons")
local shown
local tooltip = env.GameTooltip
tooltip.AddLine = function(_, text) shown = text end
tooltip.Hide = function() shown = nil end
-- Hover Funds while they are whole copper: no tooltip yet.
local fundsArea = areas[1]
fundsArea.scripts.OnEnter(fundsArea)
assert(shown == nil)
-- Funds become fractional while hovered: the next redraw shows the exact amount.
game.S.funds = 12.3456
Window.Refresh()
assert(h.shownText("12" .. S_ .. " 35" .. C), "funds in coins")
assert(shown == "Exactly 12.3456 silver (12s 35c shown)", "the exact funds on hover: " .. tostring(shown))
-- It follows the amount.
game.S.funds = 12.3457
Window.Refresh()
assert(shown == "Exactly 12.3457 silver (12s 35c shown)")
fundsArea.scripts.OnLeave(fundsArea)
assert(shown == nil and Window.liveTip == nil)
-- A purchase button keeps its exact cost live while the pointer stays on it
-- (Codex review of #61): buy a gizmo without moving, the tooltip shows the next one.
local title
tooltip.SetText = function(_, text) title = text end
game.S.funds = 1000
Host.update(0.02)
Window.Refresh()
local gizmo = assert(h.button("btnMakeClipper"))
gizmo.scripts.OnEnter(gizmo)
local first = shown
for _ = 1, 3 do
    gizmo.scripts.OnClick(gizmo)
    Host.update(0.02)
    Window.Refresh()
end
assert(game.S.clipmakerLevel >= 3)
local exact = View.exactMoney(game.S.clipperCost)
assert(exact and shown == exact, "the tooltip follows the cost: " .. tostring(shown))
assert(shown ~= first and title == gizmo.label.text, "and its title")
gizmo.scripts.OnLeave(gizmo)
assert(Window.liveTip == nil)

-- Dragging from a tooltip area moves the window.
local moved = false
Window.frame.StartMoving = function() moved = true end
fundsArea.scripts.OnDragStart(fundsArea)
assert(moved)
-- Display never decides: the purchase's state is the simulation's alone.
assert(game.disabled.btnBuyWire == disabledBefore)

print((libGlass and "coins (real LibGlass)" or "coins (LibGlass stand-in)")
    .. ": spec examples, sign, huge, non-finite, icons, exact tooltip and price tags passed")
