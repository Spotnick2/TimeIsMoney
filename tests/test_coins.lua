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
-- Price tags in coins.
assert(View.priceTag("project40b", { bribe = 1000000 }, View.money) == "(10,000" .. G .. ")")

-- In the window: funds in coin icons, with the exact amount on hover.
env.SlashCmdList.TIMEISMONEY("start")
local game = Host.game
game.S.funds = 12.3456
local disabledBefore = game.disabled.btnBuyWire
Window.Refresh()
assert(h.shownText("12" .. S_ .. " 35" .. C), "funds in coins")
local shown
local tooltip = env.GameTooltip
local realAdd = tooltip.AddLine
tooltip.AddLine = function(_, text) shown = text end
for _, w in ipairs(captured.widgets) do
    if w.kind == "Frame" and w.scripts.OnEnter and h.visible(w) and not shown then
        w.scripts.OnEnter(w)
        if shown and not shown:find("Exactly", 1, true) then shown = nil end
    end
end
tooltip.AddLine = realAdd
assert(shown == "Exactly 12.3456 silver (12s 35c shown)", "the exact funds on hover: " .. tostring(shown))
-- Display never decides: the purchase's state is the simulation's alone.
assert(game.disabled.btnBuyWire == disabledBefore)

print((libGlass and "coins (real LibGlass)" or "coins (LibGlass stand-in)")
    .. ": spec examples, sign, huge, non-finite, icons, exact tooltip and price tags passed")
