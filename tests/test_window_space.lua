-- The ledger window, phase III (#20 slice 4): exploration, the dragonling design and
-- combat.
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns, libGlass = Harness.Load()
local h = Harness.Helpers(captured)
local View, Host, Window = ns.View, ns.Host, ns.Window

-- numberCruncher and toFixed as the reference prints them (ties round up; the
-- reference's 999...9 literals, so 1e30 is "1000 octillion").
assert(View.numberCruncher(1500, 0) == "2 thousand" and View.numberCruncher(2500, 0) == "3 thousand")
assert(View.numberCruncher(5, 0) == "5 " and View.numberCruncher(1e30, 0) == "1000 octillion")
assert(View.toFixed(2.5, 0) == "3" and View.toFixed(-0.4, 0) == "-0" and View.toFixed(0.5, 0) == "1")
assert(View.toFixed(1e21, 0) == "1e+21" and View.numberCruncher(1.5e6) == "1.50 million")
-- NaN as JavaScript compares it (WoW's Lua compares NaN true): "NaN ".
assert(View.numberCruncher(0 / 0, 0) == "NaN ")

env.SlashCmdList.TIMEISMONEY("start")
local game = Host.game
local S = game.S
-- A company in space with Renown, combat and a battle on.
S.humanFlag, S.spaceFlag, S.battleFlag = 0, 1, 1
S.project121.flag, S.project131.flag = 1, 1
S.probeTrust, S.yomi, S.unusedClips, S.probeCount = 5, 1e9, 1e30, 1e6
Host.update(0.02)
Window.Refresh()
assert(h.shownText("Space Exploration") and h.shownText("Dragonling Design") and h.shownText("Combat"))
assert(h.shownText("Cosmos Surveyed") and h.shownText("Rift Engines") and h.shownText("Enforcement"))
assert(h.shownText("Renown"))
-- The cost of more Max Trust keeps the reference's page default (its update is
-- commented out).
assert(h.button("btnIncreaseMaxTrust").label.text:find("91,117.99", 1, true))

-- Drawing phase III never changes the company.
local function snapshot() return h.digest(S) .. h.digest(game.disabled) .. h.digest(game.readouts) end
local before = snapshot()
local draws = Host.random.count
for _ = 1, 5 do Window.Refresh() end
assert(snapshot() == before and Host.random.count == draws)

-- Allocations route through the host: one point into Rift Engines, then back.
Host.update(0.02)
Window.Refresh()
local raise = assert(h.button("btnRaiseProbeSpeed"))
raise.scripts.OnClick(raise)
assert(S.probeSpeed == 1)
Host.update(0.02) -- buttonUpdate enables Lower, as in the browser
Window.Refresh()
local lower = assert(h.button("btnLowerProbeSpeed"))
lower.scripts.OnClick(lower)
assert(S.probeSpeed == 0)
-- Launching a dragonling.
local launch = assert(h.button("btnMakeProbe"))
local launched = S.probeLaunchLevel
launch.scripts.OnClick(launch)
assert(S.probeLaunchLevel == launched + 1)

-- Combat: a battle runs through the simulation; the view draws its live ships as
-- pooled textures inside the battle box, and reads nothing back.
S.drifterCount, S.probeCount = 1e6, 1e6
local tries = 0
while #S.battles == 0 and tries < 200 do
    Host.update(0.1)
    tries = tries + 1
end
assert(#S.battles > 0, "a battle starts")
Window.Refresh()
local alive = 0
for _, ship in ipairs(S.ships) do if ship.alive then alive = alive + 1 end end
assert(alive > 0 and h.shownText(S.battleName) and h.shownText("Scale"))
-- Every live ship has a dot in its team's colour at its own position in the box.
local box
for _, w in ipairs(captured.widgets) do
    if w.kind == "Frame" and w.shown and w.width and w.height and math.abs(w.width / w.height - 310 / 150) < 0.01 then
        box = w
    end
end
assert(box, "the battle box keeps the canvas's proportions")
local scale = box.width / S.battleWIDTH
local dots = {}
for _, t in ipairs(captured.textures) do
    if t.parent == box and t.shown and t.point then
        dots[string.format("%.3f,%.3f", t.point[4], t.point[5])] = t
    end
end
for _, ship in ipairs(S.ships) do
    if ship.alive then
        local dot = dots[string.format("%.3f,%.3f", ship.x * scale, -ship.y * scale)]
        assert(dot, "a live ship is not drawn")
        local want = ship.team == 0 and 0.45 or 1
        assert(dot.colorTexture[1] == want, "a live ship drawn in the wrong colour")
    end
end
-- The combat view redraws on its own faster cadence, between full redraws.
Window.elapsed = 0
local moved
for _, ship in ipairs(S.ships) do if ship.alive then moved = ship break end end
moved.x, moved.y = 7, 9
Window.frame.scripts.OnUpdate(Window.frame, Window.BATTLE_REFRESH)
local found = false
for _, t in ipairs(captured.textures) do
    if t.parent == box and t.shown and t.point and math.abs(t.point[4] - 7 * scale) < 1e-9
        and math.abs(t.point[5] + 9 * scale) < 1e-9 then found = true end
end
assert(found, "the combat view redraws between full redraws")

-- The result panel follows checkForBattleEnd: VICTORY with the Renown won.
S.numRightShips, S.honorReward = 0, 230
local result, amount = View.battleResult(S)
assert(result == "VICTORY" and amount == "+230")
-- Both fleets fall together: the VICTORY branch runs last and keeps the left count.
S.numLeftShips = 0
result, amount = View.battleResult(S)
assert(result == "VICTORY" and amount == "+" .. ns.JSMath.toString(S.battleLEFTSHIPS))
S.numRightShips = 5
result, amount = View.battleResult(S)
assert(result == "DEFEAT" and amount == "-" .. ns.JSMath.toString(S.battleLEFTSHIPS))
-- Raw numbers, as the reference writes them.
S.numRightShips, S.numLeftShips, S.honorReward = 0, 5, 1010
assert(select(2, View.battleResult(S)) == "+1010")

-- The window fits a 1024x500 screen with every phase III card open.
env.UIParent.height = 500
Window.Refresh()
local scale = Window.frame.scale or 1
assert(Window.frame.width * scale <= 1024 and Window.frame.height * scale <= 500)

print((libGlass and "window phase III (real LibGlass)" or "window phase III (LibGlass stand-in)")
    .. ": numberCruncher, panels, no state change from drawing, allocations, launch, combat view and screen fit passed")
