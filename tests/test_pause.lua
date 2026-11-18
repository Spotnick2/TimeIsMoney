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
            check(Host.setPaused(true))
            local now, draws = Host.game.clock.now, Host.random.count
            for _ = 1, pauseFor do Host.update(0.02) end
            check(Host.game.clock.now == now and Host.random.count == draws, "paused: no time, no draws")
            check(Host.setPaused(false))
        end
        Host.update(0.02)
    end
    local h = Harness.Helpers(captured)
    return h.digest(Host.game.S), Host.random.count, Host.game.clock.now
end
-- A paused run reaches exactly the unpaused run's state: same time, draws and state.
local a, adraws, anow = run(400)
local b, bdraws, bnow = run(400, 150, 300)
check(anow == bnow and adraws == bdraws and a == b, "pause and resume change nothing but the wall time")

-- The window and the commands.
local env, captured, ns = Harness.Load()
local h = Harness.Helpers(captured)
local Host, Window = ns.Host, ns.Window
env.SlashCmdList.TIMEISMONEY("start")
env.SlashCmdList.TIMEISMONEY("pause")
check(Host.paused and captured.messages[#captured.messages]:find("Company paused", 1, true))
Window.Refresh()
check(Window.title._text == "Time Is Money (Paused)", "the title says so")
check(h.visible(Window.resume) and Window.resume.label._text == "Resume", "and offers a way back")
local make = h.button("btnMakePaperclip")
check(not make:IsEnabled(), "controls do nothing while paused")
check(make.label._text == "Make Copper Bolts (paused)", "the label names the pause, not a requirement")
make._scripts.OnEnter(make)
check(env.GameTooltip.lines[#env.GameTooltip.lines]:find("paused", 1, true), "and the tooltip says why")
make._scripts.OnLeave(make)
local ok, why = Host.click("btnMakePaperclip")
check(not ok and why:find("paused", 1, true), "commands are refused")
check(not Host.setValue("slider", "100"))
-- Pointer moves over the tournament lines pass (not decisions; no stuck reveal).
check(Host.click("tournamentStuff:mouseover") and Host.click("tournamentStuff:mouseout"))
-- Selects and range steps (no control id) are company controls too.
local function nilIdCompany()
    local n = 0
    for _, w in ipairs(captured.widgets) do
        if w._type == "Button" and w.company and h.visible(w) then
            n = n + 1
            check(not w:IsEnabled(), "a select or range step is unavailable while paused")
        end
    end
    return n
end
Host.game.S.investmentEngineFlag = 1
Window.Refresh()
check(nilIdCompany() > 0, "a select shows (the investment risk)")
-- Status reports it.
env.SlashCmdList.TIMEISMONEY("status")
local said = false
for _, m in ipairs(captured.messages) do if m:find("Paused at", 1, true) then said = true end end
check(said, "/tim status says Paused")

-- Settings: the button follows the state and resumes.
env.SlashCmdList.TIMEISMONEY("settings")
local p = Window.settings
check(p.pause.label._text == "Resume the company")
p.pause._scripts.OnClick(p.pause)
check(not Host.paused and p.pause.label._text == "Pause the company")
Window.Refresh()
check(Window.title._text == "Time Is Money" and h.button("btnMakePaperclip"):IsEnabled())
check(not h.visible(Window.resume), "no Resume while running")
-- The title bar's Resume resumes.
check(Host.setPaused(true))
Window.Refresh()
Window.resume._scripts.OnClick(Window.resume)
check(not Host.paused and not h.visible(Window.resume))

-- Saved: logout keeps the pause, the next load restores it paused.
check(Host.setPaused(true))
local db = Host.persist()
check(db.paused == true and db.company, "the pause is saved with the company")
local env2, captured2, ns2 = Harness.Load()
check(ns2.Host.loadSaved(db) == "restored" and ns2.Host.paused, "restored paused")
local now = ns2.Host.game.clock.now
for _ = 1, 20 do ns2.Host.update(0.02) end
check(ns2.Host.game.clock.now == now, "a restored pause holds")
-- Older saves (no flag) run; a damaged flag blocks, as any broken saved data does.
db.paused = nil
local env3, captured3, ns3 = Harness.Load()
check(ns3.Host.loadSaved(db) == "restored" and not ns3.Host.paused)
check(ns3.Host.persist().paused == nil, "running: nothing written")
db.paused = "yes"
local env4, captured4, ns4 = Harness.Load()
check(ns4.Host.loadSaved(db) == "blocked" and ns4.Host.persist() == nil, "a damaged pause is kept untouched")

-- A new game while paused starts a running company; an open settings panel follows.
check(Host.paused)
env.SlashCmdList.TIMEISMONEY("settings")
env.SlashCmdList.TIMEISMONEY("settings")
check(p:IsShown() and p.pause.label._text == "Resume the company")
Window.NewGame()
Window.dialog.yes._scripts.OnClick(Window.dialog.yes)
check(not Host.paused, "a new company runs")
check(p.pause.label._text == "Pause the company", "the settings button follows the new company")
-- Owed time dropped by a pause is counted.
Host.debt = 500
local dropped = Host.stats.dropped
check(Host.setPaused(true))
check(Host.stats.dropped == dropped + 500 and Host.debt == 0, "counted as dropped")
check(Host.setPaused(false))
-- No company: nothing to pause.
local env5, captured5, ns5 = Harness.Load()
check(not ns5.Host.setPaused(true))

-- Covered: frozen time and draws, exact resume, refused controls with a reason, title, status, settings, saved pause and new game.
done("test_pause")
