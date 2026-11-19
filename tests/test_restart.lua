-- Restarts (#23): Quantum Temporal Reversion asks first, a prestige choice does not
-- (as in the reference), and the new-game control needs an explicit yes. Each
-- starts a fresh company with the prestige kept; none happens while saving is off.
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns, libGlass = Harness.Load()
local h = Harness.Helpers(captured)
local Host, Window = ns.Host, ns.Window

Host.prestige = { prestigeU = 2, prestigeS = 0 } -- the account's prestige
env.SlashCmdList.TIMEISMONEY("start")
local game = Host.game
game.S.compFlag, game.S.projectsFlag = 1, 1
game.S.standardOps = -20000
Host.update(0.05)
Window.Refresh()

-- Quantum Temporal Reversion: the button opens the confirmation; "no" leaves the
-- company as it was.
local reversion = assert(h.button("projectButton217"), "the reversion is offered")
reversion._scripts.OnClick(reversion)
local dialog = Window.dialog
check(dialog and dialog:IsShown() and dialog.question._text:find("Turn back the hourglass?", 1, true))
dialog.no._scripts.OnClick(dialog.no)
check(not dialog:IsShown() and Host.game == game and game.S.project217.flag == 0, "no: nothing happens")
-- "Yes": the reference's effect, then a fresh company with the prestige kept.
reversion._scripts.OnClick(reversion)
dialog.yes._scripts.OnClick(dialog.yes)
check(Host.game ~= game and Host.game.S.prestigeU == 2 and Host.game.S.clips == 0, "yes: a fresh company")
check(game.S.project217.flag == 1 and game.readouts[1] == "Restart")
Window.Refresh()
check(h.shownText("New premises. New customers. Same excellent product."),
    "a company with prestige opens with the fresh-start line")

-- The new-game control: /tim newgame asks; only "yes" starts over.
local second = Host.game
second.S.clips = 42
env.SlashCmdList.TIMEISMONEY("newgame")
check(dialog:IsShown() and dialog.question._text:find("Start a new company?", 1, true))
dialog.no._scripts.OnClick(dialog.no)
check(Host.game == second and second.S.clips == 42)
env.SlashCmdList.TIMEISMONEY("newgame")
dialog.yes._scripts.OnClick(dialog.yes)
check(Host.game ~= second and Host.game.S.clips == 0 and Host.game.S.prestigeU == 2)

-- A prestige choice needs no confirmation (the reference has none): the next
-- company starts with the new prestige.
local third = Host.game
third.S.project147.flag, third.S.compFlag, third.S.standardOps, third.S.memory = 1, 1, 400000, 400
third.S.projectsFlag = 1
third:advanceTo(third.clock.now + 30)
Window.Refresh()
local universe = assert(h.button("projectButton200"))
universe._scripts.OnClick(universe)
check(not dialog:IsShown() and Host.game ~= third and Host.game.S.prestigeU == 3)

-- /tim click cannot bypass the confirmation.
local before = Host.game
before.S.standardOps, before.S.compFlag, before.S.projectsFlag = -20000, 1, 1
Host.update(0.05)
env.SlashCmdList.TIMEISMONEY("click projectButton217")
check(Host.game == before and captured.messages[#captured.messages]:find("confirmation", 1, true))
-- A dialog left open closes with the window, and a "yes" for a replaced company does
-- nothing.
Window.Refresh()
local again = assert(h.button("projectButton217"))
again._scripts.OnClick(again)
check(dialog:IsShown())
Window.Toggle() -- close the ledger
check(not dialog:IsShown(), "the dialog closes with the window")
Window.Toggle()
again._scripts.OnClick(again)
local stale = Host.game
check(Host.newGame())
dialog.yes._scripts.OnClick(dialog.yes)
check(Host.game ~= stale and Host.game.S.project217.flag == 0, "a stale yes does nothing")

-- Saving off (unrecognized data): no new game, the data kept.
local env2, captured2, ns2 = Harness.Load()
ns2.Host.loadSaved({ schema = 999 })
env2.SlashCmdList.TIMEISMONEY("newgame")
check(captured2.messages[#captured2.messages]:find("Not starting over", 1, true))
check(ns2.Window.dialog == nil, "no dialog offered while saving is off")

-- Covered: reversion confirm (no/yes), new-game confirm, prestige restart and saving-off refusal.
done(libGlass and "test_restart (real LibGlass)" or "test_restart (LibGlass stand-in)")
