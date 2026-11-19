-- Lifecycle (#24): the window never drives the simulation. Hiding it does not pause
-- the company; opening, closing and restarting never add a second wakeup, another
-- per-frame script, a queued timer, or duplicate the reference's timers.
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns = Harness.Load()
local h = Harness.Helpers(captured)
local Host, Window = ns.Host, ns.Window

-- A client frame: the kit's WoW.step, i.e. the C_Timer callbacks due (C_Timer.After(0)
-- ones run on the next frame, as in the client), then OnUpdate once on every visible
-- frame (the host wakeup, the window's polls) and never on a hidden one. Counts how
-- often the host steps, and each frame's OnUpdate runs.
local steps = 0
local update = Host.update
Host.update = function(elapsed)
    steps = steps + 1
    return update(elapsed)
end
local runs, counted = {}, {}
local function frame(elapsed)
    steps = 0
    local shown = {}
    for _, f in ipairs(WoW.frames) do
        local fn = f._scripts.OnUpdate
        if fn and counted[f] ~= fn then
            local wrapped = function(self, ...) runs[self] = (runs[self] or 0) + 1 return fn(self, ...) end
            f._scripts.OnUpdate, counted[f] = wrapped, wrapped
        end
        runs[f] = 0
        if fn then shown[f] = h.visible(f) end
    end
    WoW.step(elapsed)
    check(steps == 1, "the host steps once per client frame, not " .. steps)
    local wrong
    for f, was in pairs(shown) do
        if runs[f] ~= (was and 1 or 0) then wrong = (f._name or f._type) .. " ran " .. runs[f] .. " times" end
    end
    check(wrong == nil, "each shown frame's OnUpdate runs once per client frame, a hidden one's never: " .. tostring(wrong))
    return runs
end
-- Per-frame work outside the simulation: scripts on every frame, shown or not, and
-- queued C_Timer callbacks.
local function perFrame()
    local n = 0
    for _, f in ipairs(WoW.frames) do if f._scripts.OnUpdate then n = n + 1 end end
    return n .. " scripts, " .. #WoW.timers .. " timers"
end
-- The host's wakeup: the one parentless frame with an OnUpdate.
local wakeup
for _, f in ipairs(captured.frames) do if f._scripts.OnUpdate then wakeup = f end end
check(wakeup ~= nil, "the host has its wakeup frame")
local function timers(game)
    local kinds = {}
    for _, t in ipairs(game.clock:save().timers) do kinds[#kinds + 1] = t.kind end
    table.sort(kinds)
    return table.concat(kinds, ",")
end

env.SlashCmdList.TIMEISMONEY("start")
frame(0.02)
check(Window.frame:IsShown(), "start opens the window")
local fresh, freshAt = timers(Host.game), Host.game.clock.now
check(fresh ~= "", "a running company has timers")
local work = perFrame()

-- Shown: the window's polls and the host wakeup each run exactly once a frame.
local shownRuns = frame(0.02)
check(Window.frame._scripts.OnUpdate and shownRuns[Window.frame] == 1 and shownRuns[wakeup] == 1,
    "a shown window updates once per client frame, and so does the host")

-- Hidden: the company keeps running at the same rate (a window poll calling the
-- host, or a host tied to the window, would fail the step count or the time).
Window.frame:Hide()
local before = Host.game.clock.now
local windowRuns, wakeupRuns = 0, 0
for _ = 1, 50 do
    local r = frame(0.02)
    windowRuns, wakeupRuns = windowRuns + r[Window.frame], wakeupRuns + r[wakeup]
end
check(Host.game.clock.now == before + 1000, "a hidden window does not pause the company")
check(windowRuns == 0 and wakeupRuns == 50,
    "a hidden window never updates, the host wakeup still does: " .. windowRuns .. ", " .. wakeupRuns)

-- Opened and closed many times: one step per frame, no new per-frame work.
for _ = 1, 20 do
    env.SlashCmdList.TIMEISMONEY("")
    frame(0.02)
end
check(perFrame() == work, "toggling the window adds no per-frame work: " .. perFrame() .. " vs " .. work)

-- A new company (confirmed): one wakeup, no new per-frame work, and exactly a fresh
-- company's timers at the same logical time.
local old = Host.game
Window.NewGame()
Window.dialog.yes._scripts.OnClick(Window.dialog.yes)
check(Host.game ~= old)
frame(0.02)
check(Host.game.clock.now == freshAt and timers(Host.game) == fresh,
    "a restart starts exactly a fresh company's timers")
check(perFrame() == work, "a restart adds no per-frame work")
-- The discarded company no longer advances.
local oldNow = old.clock.now
for _ = 1, 10 do frame(0.02) end
check(old.clock.now == oldNow, "the previous company stops")

-- Covered: hidden window keeps running, one host step per frame, no duplicate work or timers across toggles and restarts.
done("test_lifecycle")
