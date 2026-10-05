-- The ledger window, the liquidation (#20 slice 5): the panels close in the
-- reference's order until only manual production remains.
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns, libGlass = Harness.Load()
local h = Harness.Helpers(captured)
local View, Host, Window = ns.View, ns.Host, ns.Window

env.SlashCmdList.TIMEISMONEY("start")
local game = Host.game
local S = game.S
-- A company with every late panel open: space, combat, Renown, the network, the
-- engines and the Ledger.
S.humanFlag, S.spaceFlag, S.battleFlag, S.swarmFlag = 0, 1, 1, 1
S.factoryFlag, S.tothFlag, S.wireProductionFlag, S.harvesterFlag, S.wireDroneFlag = 1, 1, 1, 1, 1
S.project121.flag, S.project131.flag = 1, 1
S.strategyEngineFlag, S.qFlag, S.compFlag, S.projectsFlag = 1, 1, 1, 1
Host.update(0.02)

local function at(dismantle, timers)
    S.dismantle = dismantle
    for k, v in pairs(timers or {}) do S[k] = v end
    return View.panels(S)
end

-- Before the ending, everything shows.
local p = at(0)
assert(p.probeDesign and p.space and p.battle and p.honor and p.wireProduction and p.swarm and p.strategy
    and p.quantum and p.qCompute and p.computing and p.projects and p.creation and p.clipsPerSec)

-- 1: the probe design at once, then trust, max trust, space, combat and Renown.
p = at(1, { endTimer1 = 0 })
assert(not p.probeDesign and p.increaseProbeTrust and p.space)
p = at(1, { endTimer1 = 50 })
assert(not p.increaseProbeTrust and p.increaseMaxTrust)
p = at(1, { endTimer1 = 100 })
assert(not p.increaseMaxTrust and p.space)
p = at(1, { endTimer1 = 150 })
assert(not p.space and p.battle)
p = at(1, { endTimer1 = 175 })
assert(not p.battle and p.honor)
p = at(1, { endTimer1 = 190 })
assert(not p.honor)
-- 2: copper production goes and the bars come back; then the network's gifts,
-- engine and slider.
p = at(2, { endTimer2 = 0 })
assert(not p.wireProduction and p.wireTrans and p.swarmGift and p.swarm)
p = at(2, { endTimer2 = 50 })
assert(not p.swarmGift and p.swarm)
p = at(2, { endTimer2 = 100 })
assert(not p.swarm and p.swarmSlider)
p = at(2, { endTimer2 = 150 })
assert(not p.swarmSlider)
-- 3: bolts per second, Available Bolts and the space foundry count; 4: the
-- Negotiation Simulator.
p = at(3)
assert(not p.clipsPerSec and not p.toth and not p.factorySpace and p.strategy)
p = at(4)
assert(not p.strategy and p.qCompute)
-- 5: Compute goes, then the chips one by one (chip 10 first), then the calculator.
p = at(5, { endTimer4 = 0 })
assert(not p.qCompute and p.quantum and View.chipShown(S, 10))
S.endTimer4 = 10
assert(not View.chipShown(S, 10) and View.chipShown(S, 9))
S.endTimer4 = 174
for i = 1, 10 do assert(not View.chipShown(S, i)) end
p = at(5, { endTimer4 = 250 })
assert(not p.quantum)
-- 6: the processors; 7: computing and projects.
p = at(6)
assert(not p.processor and p.computing)
p = at(7)
assert(not p.computing and not p.projects and p.creation)

-- Timers as the reference checked them: once project148 runs endTimer1, the state
-- after a tick is one ahead of the value the ending block saw.
S.project148.flag = 1
p = at(1, { endTimer1 = 50 })
assert(p.increaseProbeTrust, "the check saw 49")
p = at(1, { endTimer1 = 51 })
assert(not p.increaseProbeTrust)
S.project148.flag = 0

-- The window at each stage (review of #60).
-- 1: the design's heading goes with it; the trust increases outlast it, untitled.
at(1, { endTimer1 = 10 })
Window.Refresh()
assert(not h.shownText("Dragonling Design") and h.button("btnIncreaseProbeTrust"))
-- 2: the network's heading goes at 100; the slider stays until 150, untitled.
at(2, { endTimer2 = 120 })
Window.Refresh()
assert(not h.shownText("Company Network") and h.labelled(">>"))
-- 5: Compute goes; chips 10, 9 and 8 are gone at endTimer4 100, seven remain.
at(5, { endTimer4 = 100 })
Window.Refresh()
assert(not h.button("btnQcompute") and h.shownText("Resonance Calculator"))
local chips = 0
for _, t in ipairs(captured.textures) do
    local c = t.colorTexture
    if c and c[1] == 0.45 and c[2] == 0.85 and h.visible(t) then chips = chips + 1 end
end
assert(chips == 7, chips .. " chips show")
-- compDiv holds the network, the slider and the calculator: hidden with it.
S.dismantle = 0
S.compFlag = 0
p = View.panels(S)
assert(not p.swarm and not p.swarmSlider and not p.quantum and not p.trust and not p.swarmGift)
S.compFlag = 1

-- The window follows: drawn at the seventh dismantling, the late cards are gone.
at(7, { endTimer1 = 190, endTimer2 = 150, endTimer4 = 250 }) -- every earlier timer has run its course
Window.Refresh()
for _, title in ipairs({ "Dragonling Design", "Space Exploration", "Combat", "Negotiation Simulator",
    "Resonance Calculator", "Copper Production", "Company Network", "The Ledger", "Projects" }) do
    assert(not h.shownText(title), title .. " still shows")
end
assert(h.shownText("Manufacturing"))

-- Last, the simulation itself runs the final timer: once memory is gone and the
-- last bar is used, endTimer6 counts and Manufacturing closes at 250 ticks.
S.project216.flag, S.wire = 1, 0
local before = S.endTimer6
-- (The host takes at most a second of logical time per update.)
for _ = 1, 40 do
    if S.endTimer6 >= before + 250 then break end
    Host.update(0.5)
end
assert(Host.running and S.endTimer6 >= before + 250, "the simulation advanced the final timer: " .. S.endTimer6)
Window.Refresh()
assert(not h.shownText("Manufacturing"))
-- Only manual production remains.
local make = h.button("btnMakePaperclip")
assert(make and h.shownText("Handfuls of Copper Bolts"))
local others = 0
for _, w in ipairs(captured.widgets) do
    if w.kind == "Button" and h.visible(w) and w.id and w.id ~= "btnMakePaperclip" then others = others + 1 end
end
assert(others == 0, others .. " other controls still show")

print((libGlass and "window liquidation (real LibGlass)" or "window liquidation (LibGlass stand-in)")
    .. ": every closing in order, the chips one by one, the final timer and manual production alone passed")
