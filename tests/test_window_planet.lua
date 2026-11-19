-- The ledger window, phase II (#20 slice 3): manufacturing, the material pipeline,
-- power and the Company Network.
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns, libGlass = Harness.Load()
local h = Harness.Helpers(captured)
local View, Host, Window = ns.View, ns.Host, ns.Window

-- spellf: the leading group with one truncated decimal and the place name, exactly
-- as the reference prints it (checked against main.js in Node), quirks included.
check(View.spell(12345678) == "12.3 million " and View.spell(12) == "12.0" and View.spell(999.9) == "999.0")
check(View.spell(1e21) == "1.0 sextillion " and View.spell(0) == "0" and View.spell(1999999) == "1.9 million ")
check(View.spell(6e27) == "6.0 octillion " and View.spell(-5) == "-5")
check(View.spell(1e-7) == "NaN.0 thousand " and View.spell(1 / 0) == "NaN.0 million ")
-- timeCruncher on an endless countdown (the slider at 0): JavaScript's text, and no
-- NaN division (WoW's Lua raises on one).
check(ns.Workshop.timeCruncher(1 / 0) == "Infinity hours " and ns.Workshop.timeCruncher(0 / 0) == "")
-- updateUpgrades' thresholds.
local nfup, ndup = View.nextUpgrades({ maxFactoryLevel = 12, maxDroneLevel = 700 })
check(nfup == 20 and ndup == 5000)

env.SlashCmdList.TIMEISMONEY("start")
local game = Host.game
local S = game.S
-- A planetary company: past the human phase, with every phase II system unlocked.
S.humanFlag, S.factoryFlag, S.tothFlag, S.wireProductionFlag = 0, 1, 1, 1
S.harvesterFlag, S.wireDroneFlag, S.swarmFlag = 1, 1, 1
S.project127.flag, S.project45.flag = 1, 1
S.compFlag = 1 -- the network sits inside the computing panel
S.unusedClips = 1e12
Host.update(0.02)
Window.Refresh()
check(h.shownText("Manufacturing") and h.shownText("Copper Production") and h.shownText("Power")
    and h.shownText("Company Network"))
check(not h.shownText("Company Funds"), "the business panels are gone")
check(h.shownText("Next Upgrade at") and h.shownText("Available Bolts"))

-- Drawing phase II never changes the company.
local function snapshot() return h.digest(S) .. h.digest(game.disabled) .. h.digest(game.ranges) .. h.digest(game.readouts) end
local before = snapshot()
local draws = Host.random.count
for _ = 1, 5 do Window.Refresh() end
check(snapshot() == before and Host.random.count == draws)

-- Purchases route through the host: a foundry, ten reapers, a power core.
local foundry = assert(h.button("btnMakeFactory"))
check(foundry.label._text:find("Build a Foundry (", 1, true) and foundry.label._text:find(" bolts)", 1, true))
foundry._scripts.OnClick(foundry)
check(S.factoryLevel == 1)
Host.update(0.02)
Window.Refresh()
local ten = assert(h.button("btnHarvesterx10"))
ten._scripts.OnClick(ten)
check(S.harvesterLevel == 10)
local core = assert(h.button("btnMakeFarm"))
core._scripts.OnClick(core)
check(S.farmLevel == 1)
-- Disassemble All says what it returns.
Window.Refresh()
local scrap = assert(h.button("btnHarvesterReboot"))
check(not scrap.tip, "tooltips are built on hover, not on every redraw")
scrap._scripts.OnEnter(scrap)
local shown = env.GameTooltip.lines
local returns = false
for _, line in ipairs(shown or {}) do if line:find("^Disassemble All: %+") then returns = true end end
check(returns and table.concat(shown, "|"):find("Takes every one", 1, true), "what it does and what it returns")
scrap._scripts.OnLeave(scrap)

-- Power figures as updatePower prints them.
local power = View.power(S)
check(power.production == S.farmLevel * S.farmRate and power.factories == S.factoryLevel * S.factoryPowerRate)
check(h.shownText("Performance"))

-- The Work/Think slider sets the range through the host: every value is reachable
-- (steps of 1 and 10).
local start = game.ranges.slider.number
local up10, up1 = assert(h.labelled(">>")), assert(h.labelled(">"))
up10._scripts.OnClick(up10)
up1._scripts.OnClick(up1)
check(game.ranges.slider.number == start + 11 and game.ranges.slider.value == ns.JSMath.toString(start + 11))
local down1 = assert(h.labelled("<"))
down1._scripts.OnClick(down1)
check(game.ranges.slider.number == start + 10)
Host.update(0.02)
check(S.sliderPos == game.ranges.slider.value, "the swarm reads the slider")
-- With the slider at 0 an Active network's countdown is endless: shown, no error.
check(ns.Host.setValue("slider", "0"))
S.disorgFlag, S.boredomFlag = 0, 0
Host.update(0.02)
check(S.swarmStatus == 0 and S.giftCountdown == 1 / 0)
Window.Refresh()
check(h.shownText("Infinity hours"))

-- The network's status and its remedy: disorganized offers Synchronize.
S.disorgFlag = 1
Host.update(0.02)
Window.Refresh()
check(View.swarmStatus(S) == "Disorganized" and h.shownText("Disorganized"))
check(h.button("btnSynchSwarm"))
-- The rates: each "per second" row prints the last tick's amount times 100.
Window.Refresh()
check(h.shownText(View.spell(game.matterRate * 100) .. " g"))
-- In space the probes build: foundry and drone counts replace the build rows, and
-- the Unclaimed Material rate (mdps) appears.
S.spaceFlag = 1
game.exploreRate = 1234
Window.Refresh()
check(not h.button("btnMakeFactory") and not h.button("btnMakeHarvester"))
check(h.shownText(View.spell(123400) .. " g"), "the exploration rate")
S.spaceFlag = 0

-- The window fits a 1024x500 screen with every phase II card open.
env.UIParent._height = 500
Window.Refresh()
local scale = Window.frame._scale or 1
check(Window.frame._width * scale <= 1024 and Window.frame._height * scale <= 500)

-- Covered: spellf, upgrades, panels, no state change from drawing, purchases, power, slider, network status and screen fit.
done(libGlass and "test_window_planet (real LibGlass)" or "test_window_planet (LibGlass stand-in)")
