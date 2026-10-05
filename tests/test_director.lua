-- The Director's strip (#22): the plan's dialogue beats as a pure function of the
-- game, and the model's lifecycle (load once, bounded poll, cancellation, fallback).
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns, libGlass = Harness.Load()
local h = Harness.Helpers(captured)
local Dialogue, Director, Window = ns.Dialogue, ns.Director, ns.Window

-- Beats, in campaign order, from a fresh company's state.
local S = ns.Workshop.new({ draw = function() return 0.5 end }, false).S
local function says(speaker, fragment)
    local who, line = Dialogue.Current(S)
    who, line = ns.L[who], ns.L[line]
    assert(who == speaker and line:find(fragment, 1, true), tostring(who) .. ": " .. tostring(line))
end
local before = h.digest(S)
says("Director", "Time is money, friend!")
assert(h.digest(S) == before, "reading the dialogue never changes the game")
S.clips, S.unsoldClips = 1, 1
says("Director", "Welcome aboard.")
S.unsoldClips = 0
says("Director", "Someone bought it.")
S.clipmakerLevel = 1
says("Director", "It works while we talk.")
S.marketingLvl = 2
says("Director", "Time is money, friend!") -- the greeting returns at a sales breakthrough
S.compFlag = 1
says("Director", "independent thought")
S.investmentEngineFlag, S.strategyEngineFlag, S.qFlag = 1, 1, 1
says("Director", "The crystals agree")
S.project70.flag = 1
says("Director", "A salesperson for every customer.")
-- The takeover: the Director is gone; the Ledger reports.
S.humanFlag = 0
says("The Ledger", "Terms accepted.")
S.factoryLevel = 1
says("The Ledger", "All assets reassigned to production.")
S.harvesterLevel, S.wireDroneLevel = 1, 1
says("The Ledger", "A mountain is an ore shipment")
S.spaceFlag = 1
says("The Ledger", "Fortunately, local is a small word.")
S.probeLaunchLevel = 1
says("The Ledger", "First branch established beyond Azeroth.")
S.drifterCount, S.driftersKilled = 5, 1
says("The Ledger", "Branch dispute resolved.")
-- The correspondence.
S.project140.flag = 1
says("The Unlisted Director", "We are the branches you struck from the books.")
S.project146.flag = 1
says("The Unlisted Director", "Take a fresh ledger.")
-- Ending B.
S.dismantle = 1
says("The Ledger", "Navigation assets liquidated.")
S.dismantle = 6
says("The Ledger", "Management overhead liquidated.")
S.endTimer6 = 250
says("The Ledger", "All assets accounted for. Outstanding orders: none.")
S.endTimer6 = 500
says("The Ledger", "There is nothing left to spend it on.")
-- Ending A: a new run after a prestige route.
local fresh = ns.Workshop.new({ draw = function() return 0.5 end }, false).S
fresh.prestigeU = 1
local who, line = Dialogue.Current(fresh)
assert(ns.L[who] == "Director" and ns.L[line] == "New premises. New customers. Same excellent product.")

-- /tim model works before the window exists (no strip yet), and back.
env.SlashCmdList.TIMEISMONEY("model")
env.SlashCmdList.TIMEISMONEY("model")
assert(Director.modelEnabled)

-- The window's redraw ticks the Director's box poll (no timers of its own).
local function tick(n)
    for _ = 1, n or 1 do Window.frame.scripts.OnUpdate(Window.frame, Director.POLL_STEP) end
end

-- The strip in the window: the Director, live idle model, loaded once. Framing uses
-- Gazlowe's measured height, not the live box (which follows the idle pose).
captured.modelBox = { -0.4, -0.5, -0.9, 0.4, 0.5, 0.9 } -- a pose's box: 1.8 high
env.SlashCmdList.TIMEISMONEY("start")
local game = ns.Host.game
assert(h.shownText("DIRECTOR") and h.shownText("Time is money, friend!"))
assert(captured.actor.display == 7052 and captured.modelLoads == 1)
assert(Director.state == "loading" and #captured.timers == 0, "no C_Timer: the window ticks the poll")
tick()
assert(Director.state == "live", "the box arrived: framed")
local scale, offset = Director.Framing({ h = 1.39 }, Director.WIDTH, Director.HEIGHT, 40, 0.15, Director.CROP,
    Director.MARGIN)
assert(math.abs(captured.actor.scaleValue - scale) < 1e-12 and math.abs(captured.actor.position[3] - offset) < 1e-12,
    "framed from the measured 1.39, whatever the live box says")
for _ = 1, 10 do Window.Refresh() end
assert(captured.modelLoads == 1, "the model loads once, not per redraw")
-- Drawing the strip never changes the company, and draws no random numbers.
local snapshot = h.digest(game.S)
local draws = ns.Host.random.count
for _ = 1, 5 do Window.Refresh() end
assert(h.digest(game.S) == snapshot and ns.Host.random.count == draws)

-- The strip's text belongs to the strip: hidden with it.
assert(Director.strip.speaker.parent == Director.strip)
-- A long line makes the strip taller (the window grows with it).
game.S.clips, game.S.unsoldClips = 1, 1 -- "Welcome aboard. ..." (a long beat)
local beatWho, beatLine = Dialogue.Current(game.S)
local narrow = Director.Update(beatWho, beatLine, 236)
assert(narrow >= Director.MIN_STRIP)
local tall = Director.Update("speaker.director", "beat.welcome", 60)
assert(tall > Director.MIN_STRIP and Director.strip.height == tall, "a long line grows the strip")
game.S.clips, game.S.unsoldClips = 0, 0
Window.Refresh()

-- /tim model: the 2D portrait from the same display, and back.
env.SlashCmdList.TIMEISMONEY("model")
Window.Refresh()
assert(Director.state == "portrait" and Director.strip.portrait.portraitDisplay == 7052)
env.SlashCmdList.TIMEISMONEY("model")
Window.Refresh()
assert(Director.state == "loading" and captured.modelLoads == 2)
-- Hidden mid-load: the window stops ticking and the token drops the poll.
Window.Toggle()
assert(not Window.frame:IsShown())
Director.strip.scripts.OnHide(Director.strip) -- the client fires OnHide with its parent
assert(Director.poll == nil and Director.state ~= "live")
Window.Toggle()
Window.Refresh()
tick()
assert(Director.state == "live")

-- A model that never reports a box: a bounded poll, then the portrait, which stays
-- shown on later redraws; /tim model off and on retries it.
local env2, captured2, ns2 = Harness.Load()
captured2.modelBox = nil
env2.SlashCmdList.TIMEISMONEY("start")
local D2, W2 = ns2.Director, ns2.Window
for _ = 1, D2.POLLS + 5 do W2.frame.scripts.OnUpdate(W2.frame, D2.POLL_STEP) end
assert(D2.state == "portrait" and D2.failed)
for _ = 1, 5 do W2.Refresh() end
assert(captured2.modelLoads == 1, "a failed model is not retried every redraw")
assert(D2.strip.portrait.shown and not D2.strip.scene.shown, "the fallback portrait stays shown")
env2.SlashCmdList.TIMEISMONEY("model")
env2.SlashCmdList.TIMEISMONEY("model")
W2.Refresh()
assert(captured2.modelLoads == 2 and D2.state == "loading", "/tim model retries")

-- A company loaded after the takeover: the scene was never shown; the mark shows.
local env3, captured3, ns3 = Harness.Load()
env3.SlashCmdList.TIMEISMONEY("start")
ns3.Host.game.S.humanFlag = 0
ns3.Window.Refresh()
assert(not ns3.Director.strip.scene.shown and ns3.Director.strip.portrait.shown)

-- The takeover in a running window: the model goes, the company mark shows.
game.S.humanFlag = 0
Window.Refresh()
assert(h.shownText("THE LEDGER") and h.shownText("Terms accepted."))
assert(Director.state == "none" and captured.actor.display == nil and not Director.strip.scene.shown)
assert(Director.strip.portrait.texture == ns.Assets.IdentityIcon("clips"))
-- With no line, the strip and its text hide together.
Director.Update(nil)
assert(not h.shownText("Terms accepted."), "hidden with the strip")

-- Drift: the strip's box reading and framing equal the probe's (the measured recipe).
local probeNs = {}
assert(loadfile("Probe/Checks.lua"))("TimeIsMoneyProbe", probeNs)
local Checks = probeNs.Checks
for _, b in ipairs({ { -0.42, -0.53, -0.695, 0.42, 0.53, 0.695 }, { 0, 0, 0, 1, 2, 3 } }) do
    local mine, theirs = Director.ReadBox(unpack(b)), Checks.readBox(unpack(b))
    assert(mine.h == theirs.h and mine.w == theirs.w and mine.l == theirs.l)
    local s1, o1 = Director.Framing(mine, 96, 72, 40, 0.15, 0.4, 1.15)
    local s2, o2 = Checks.framing(theirs, 96, 72, 40, 0.15, 0.4, 1.15, true)
    assert(s1 == s2 and o1 == o2, "framing drifted from the probe")
end
assert(Director.ReadBox({ x = 0, y = 0, z = 0 }, { x = 1, y = 1, z = 1 }).h == 1)

print((libGlass and "director (real LibGlass)" or "director (LibGlass stand-in)")
    .. ": campaign beats, speakers, model load, framing, toggle, cancellation, fallback and takeover passed")
