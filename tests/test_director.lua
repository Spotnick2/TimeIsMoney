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
assert(who == "Director" and line == "New premises. New customers. Same excellent product.")

-- The strip in the window: the Director, live idle model, loaded once.
captured.modelBox = { -0.42, -0.53, -0.695, 0.42, 0.53, 0.695 } -- Gazlowe's measured 0.84 x 1.06 x 1.39
env.SlashCmdList.TIMEISMONEY("start")
local game = ns.Host.game
assert(h.shownText("DIRECTOR") and h.shownText("Time is money, friend!"))
assert(captured.actor.display == 7052 and captured.modelLoads == 1)
assert(Director.state == "loading")
captured:RunTimers()
assert(Director.state == "live", "the box arrived: framed")
local scale, offset = Director.Framing({ h = 1.39 }, 96, 72, 40, 0.15, 0.40, 1.15)
assert(math.abs(captured.actor.scaleValue - scale) < 1e-12 and math.abs(captured.actor.position[3] - offset) < 1e-12)
for _ = 1, 10 do Window.Refresh() end
assert(captured.modelLoads == 1, "the model loads once, not per redraw")
-- Drawing the strip never changes the company, and draws no random numbers.
local snapshot = h.digest(game.S)
local draws = ns.Host.random.count
for _ = 1, 5 do Window.Refresh() end
assert(h.digest(game.S) == snapshot and ns.Host.random.count == draws)

-- /tim model: the 2D portrait from the same display, and back.
env.SlashCmdList.TIMEISMONEY("model")
Window.Refresh()
assert(Director.state == "portrait" and Director.strip.portrait.portraitDisplay == 7052)
env.SlashCmdList.TIMEISMONEY("model")
Window.Refresh()
assert(Director.state == "loading" and captured.modelLoads == 2)
-- Hidden mid-load: the late box is dropped (the token changed).
Window.Toggle()
assert(not Window.frame:IsShown())
Director.strip.scripts.OnHide(Director.strip) -- the client fires OnHide with its parent
captured:RunTimers()
assert(Director.state ~= "live", "a callback after hiding must not frame the model")
Window.Toggle()
Window.Refresh()
captured:RunTimers()
assert(Director.state == "live")

-- A model that never reports a box: a bounded poll, then the portrait for good.
local env2, captured2, ns2 = Harness.Load()
captured2.modelBox = nil
env2.SlashCmdList.TIMEISMONEY("start")
local polls = 0
while #captured2.timers > 0 do
    captured2:RunTimers()
    polls = polls + 1
    assert(polls <= ns2.Director.POLLS + 2, "the poll is bounded")
end
assert(ns2.Director.state == "portrait" and ns2.Director.failed)
for _ = 1, 5 do ns2.Window.Refresh() end
assert(captured2.modelLoads == 1, "a failed model is not retried every redraw")

-- The takeover: the model goes, the Ledger's reports carry the company mark.
game.S.humanFlag = 0
Window.Refresh()
assert(h.shownText("THE LEDGER") and h.shownText("Terms accepted."))
assert(Director.state == "none" and captured.actor.display == nil and not Director.strip.scene.shown)
assert(Director.strip.portrait.texture == ns.Assets.IdentityIcon("clips"))

print((libGlass and "director (real LibGlass)" or "director (LibGlass stand-in)")
    .. ": campaign beats, speakers, model load, framing, toggle, cancellation, fallback and takeover passed")
