-- Pause (#77): only the player's explicit pause stops the company. Logical time
-- freezes and resumes exactly where it stopped; the pause is saved; a paused
-- company's controls do nothing and say why.
local Harness = dofile("tests/window_harness.lua")

local function run(frames, pauseAt, pauseFor)
    local env, captured, ns = Harness.Load()
    local Host = ns.Host
    Host.start({ 12345, 67890 })
    for i = 1, frames do
        if i == pauseAt then
            assert(Host.setPaused(true))
            local now, draws = Host.game.clock.now, Host.random.count
            for _ = 1, pauseFor do Host.update(0.02) end
            assert(Host.game.clock.now == now and Host.random.count == draws, "paused: no time, no draws")
            assert(Host.setPaused(false))
        end
        Host.update(0.02)
    end
    local h = Harness.Helpers(captured)
    return h.digest(Host.game.S), Host.random.count, Host.game.clock.now
end
-- A paused run reaches exactly the unpaused run's state: same time, draws and state.
local a, adraws, anow = run(400)
local b, bdraws, bnow = run(400, 150, 300)
assert(anow == bnow and adraws == bdraws and a == b, "pause and resume change nothing but the wall time")

-- The window and the commands.
local env, captured, ns = Harness.Load()
local h = Harness.Helpers(captured)
local Host, Window = ns.Host, ns.Window
env.SlashCmdList.TIMEISMONEY("start")
env.SlashCmdList.TIMEISMONEY("pause")
assert(Host.paused and captured.messages[#captured.messages]:find("Company paused", 1, true))
Window.Refresh()
assert(Window.title.text == "Time Is Money (Paused)", "the title says so")
local make = h.button("btnMakePaperclip")
assert(not make:IsEnabled(), "controls do nothing while paused")
make.scripts.OnEnter(make)
assert(env.GameTooltip.lines[#env.GameTooltip.lines]:find("paused", 1, true), "and the tooltip says why")
make.scripts.OnLeave(make)
local ok, why = Host.click("btnMakePaperclip")
assert(not ok and why:find("paused", 1, true), "commands are refused")
assert(not Host.setValue("slider", "100"))
-- Status reports it.
env.SlashCmdList.TIMEISMONEY("status")
local said = false
for _, m in ipairs(captured.messages) do if m:find("Paused at", 1, true) then said = true end end
assert(said, "/tim status says Paused")

-- Settings: the button follows the state and resumes.
env.SlashCmdList.TIMEISMONEY("settings")
local p = Window.settings
assert(p.pause.label.text == "Resume the company")
p.pause.scripts.OnClick(p.pause)
assert(not Host.paused and p.pause.label.text == "Pause the company")
Window.Refresh()
assert(Window.title.text == "Time Is Money" and h.button("btnMakePaperclip"):IsEnabled())

-- Saved: logout keeps the pause, the next load restores it paused.
assert(Host.setPaused(true))
local db = Host.persist()
assert(db.paused == true and db.company, "the pause is saved with the company")
local env2, captured2, ns2 = Harness.Load()
assert(ns2.Host.loadSaved(db) == "restored" and ns2.Host.paused, "restored paused")
local now = ns2.Host.game.clock.now
for _ = 1, 20 do ns2.Host.update(0.02) end
assert(ns2.Host.game.clock.now == now, "a restored pause holds")
-- Older saves (no flag) and a damaged flag run.
db.paused = nil
local env3, captured3, ns3 = Harness.Load()
assert(ns3.Host.loadSaved(db) == "restored" and not ns3.Host.paused)
db.paused = "yes"
local env4, captured4, ns4 = Harness.Load()
assert(ns4.Host.loadSaved(db) == "restored" and not ns4.Host.paused, "only true pauses")
-- Running: nothing written.
assert(ns4.Host.persist().paused == nil)

-- A new game while paused starts a running company.
assert(Host.paused)
Window.NewGame()
Window.dialog.yes.scripts.OnClick(Window.dialog.yes)
assert(not Host.paused, "a new company runs")
-- No company: nothing to pause.
local env5, captured5, ns5 = Harness.Load()
assert(not ns5.Host.setPaused(true))

print("pause: frozen time and draws, exact resume, refused controls with a reason, title, status, settings, saved pause and new game passed")
