-- The ledger window, phase II (#20 slice 3): manufacturing, the material pipeline,
-- power and the Company Network.
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns, libGlass = Harness.Load()
local h = Harness.Helpers(captured)
local View, Host, Window = ns.View, ns.Host, ns.Window

-- spellf: the leading group with one truncated decimal and the place name.
assert(View.spell(12345678) == "12.3 million" and View.spell(12) == "12.0" and View.spell(999.9) == "999.0")
assert(View.spell(1e21) == "1.0 sextillion" and View.spell(0) == "0" and View.spell(1999999) == "1.9 million")
assert(View.spell(6e27) == "6.0 octillion")
-- updateUpgrades' thresholds.
local nfup, ndup = View.nextUpgrades({ maxFactoryLevel = 12, maxDroneLevel = 700 })
assert(nfup == 20 and ndup == 5000)

env.SlashCmdList.TIMEISMONEY("start")
local game = Host.game
local S = game.S
-- A planetary company: past the human phase, with every phase II system unlocked.
S.humanFlag, S.factoryFlag, S.tothFlag, S.wireProductionFlag = 0, 1, 1, 1
S.harvesterFlag, S.wireDroneFlag, S.swarmFlag = 1, 1, 1
S.project127.flag, S.project45.flag = 1, 1
S.unusedClips = 1e12
Host.update(0.02)
Window.Refresh()
assert(h.shownText("Manufacturing") and h.shownText("Copper Production") and h.shownText("Power")
    and h.shownText("Company Network"))
assert(not h.shownText("Company Funds"), "the business panels are gone")
assert(h.shownText("Next Upgrade at") and h.shownText("Available Bolts"))

-- Drawing phase II never changes the company.
local before = h.digest(S) .. h.digest(game.disabled) .. h.digest(game.ranges)
local draws = Host.random.count
for _ = 1, 5 do Window.Refresh() end
assert(h.digest(S) .. h.digest(game.disabled) .. h.digest(game.ranges) == before and Host.random.count == draws)

-- Purchases route through the host: a foundry, ten reapers, a power core.
local foundry = assert(h.button("btnMakeFactory"))
assert(foundry.label.text:find("Build a Foundry (", 1, true) and foundry.label.text:find(" bolts)", 1, true))
foundry.scripts.OnClick(foundry)
assert(S.factoryLevel == 1)
Host.update(0.02)
Window.Refresh()
local ten = assert(h.button("btnHarvesterx10"))
ten.scripts.OnClick(ten)
assert(S.harvesterLevel == 10)
local core = assert(h.button("btnMakeFarm"))
core.scripts.OnClick(core)
assert(S.farmLevel == 1)
-- Disassemble All says what it returns.
Window.Refresh()
local scrap = assert(h.button("btnHarvesterReboot"))
assert(scrap.tip and scrap.tip[2]:find("^Disassemble All: %+"))

-- Power figures as updatePower prints them.
local power = View.power(S)
assert(power.production == S.farmLevel * S.farmRate and power.factories == S.factoryLevel * S.factoryPowerRate)
assert(h.shownText("Performance"))

-- The Work/Think slider sets the range through the host, a step at a time.
local raise
for _, w in ipairs(captured.widgets) do
    if w.kind == "Button" and w.shown and w.label and w.label.text == "+" and not w.id then raise = w end
end
assert(raise, "the slider's raise button")
local start = game.ranges.slider.number
raise.scripts.OnClick(raise)
assert(game.ranges.slider.number == start + 10 and game.ranges.slider.value == ns.JSMath.toString(start + 10))
Host.update(0.02)
assert(S.sliderPos == game.ranges.slider.value, "the swarm reads the slider")

-- The network's status and its remedy: disorganized offers Synchronize.
S.disorgFlag = 1
Host.update(0.02)
Window.Refresh()
assert(View.swarmStatus(S) == "Disorganized" and h.shownText("Disorganized"))
assert(h.button("btnSynchSwarm"))
-- The rates: reclaimed material per second follows the reapers' last tick.
assert(game.matterRate ~= nil and game.wireRate ~= nil)

-- The window fits a 1024x500 screen with every phase II card open.
env.UIParent.height = 500
Window.Refresh()
local scale = Window.frame.scale or 1
assert(Window.frame.width * scale <= 1024 and Window.frame.height * scale <= 500)

print((libGlass and "window phase II (real LibGlass)" or "window phase II (LibGlass stand-in)")
    .. ": spellf, upgrades, panels, no state change from drawing, purchases, power, slider, network status and screen fit passed")
