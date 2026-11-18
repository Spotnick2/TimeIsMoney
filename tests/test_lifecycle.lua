-- Lifecycle (#24): the window never drives the simulation. Hiding it does not pause
-- the company; opening, closing and restarting never add a second wakeup, another
-- per-frame script, a queued timer, or duplicate the reference's timers.
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns = Harness.Load()
local h = Harness.Helpers(captured)
local Host, Window = ns.Host, ns.Window

-- A client frame: every OnUpdate the client would run, i.e. the parentless frames
-- (the host wakeup) and every visible widget (the window's polls). Counts how often
-- the host steps.
local steps = 0
local update = Host.update
Host.update = function(elapsed)
    steps = steps + 1
    return update(elapsed)
end
local function frame(elapsed)
    steps = 0
    captured:RunTimers() -- C_Timer.After(0) callbacks run on the next frame, as in the client
    for _, f in ipairs(captured.frames) do
        if f._scripts.OnUpdate then f._scripts.OnUpdate(f, elapsed) end
    end
    for _, w in ipairs(captured.widgets) do
        if w._scripts.OnUpdate and h.visible(w) then w._scripts.OnUpdate(w, elapsed) end
    end
    check(steps == 1, "the host steps once per client frame, not " .. steps)
end
-- Per-frame work outside the simulation: scripts on every frame, shown or not, and
-- queued C_Timer callbacks.
local function perFrame()
    local n = 0
    for _, f in ipairs(captured.frames) do if f._scripts.OnUpdate then n = n + 1 end end
    for _, w in ipairs(captured.widgets) do if w._scripts.OnUpdate then n = n + 1 end end
    return n .. " scripts, " .. #WoW.timers .. " timers"
end
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

-- Hidden: the company keeps running at the same rate (a window poll calling the
-- host, or a host tied to the window, would fail the step count or the time).
Window.frame:Hide()
local before = Host.game.clock.now
for _ = 1, 50 do frame(0.02) end
check(Host.game.clock.now == before + 1000, "a hidden window does not pause the company")

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
