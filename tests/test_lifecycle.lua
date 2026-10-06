-- Lifecycle (#24): the window never drives the simulation. Hiding it does not pause
-- the company; opening, closing and restarting never add a second wakeup or
-- duplicate the reference's timers.
local Harness = dofile("tests/window_harness.lua")
local env, captured, ns = Harness.Load()
local Host, Window = ns.Host, ns.Window

-- Every frame's OnUpdate, as the client runs them each frame. Counts how often the
-- host steps per client frame.
local steps = 0
local update = Host.update
Host.update = function(elapsed)
    steps = steps + 1
    return update(elapsed)
end
local function frame(elapsed)
    steps = 0
    for _, f in ipairs(captured.frames) do
        if f.scripts and f.scripts.OnUpdate then f.scripts.OnUpdate(f, elapsed) end
    end
    assert(steps == 1, "the host steps once per client frame, not " .. steps)
end
local function timers(game)
    local kinds = {}
    for _, t in ipairs(game.clock:save().timers) do kinds[#kinds + 1] = t.kind end
    table.sort(kinds)
    return table.concat(kinds, ",")
end

env.SlashCmdList.TIMEISMONEY("start")
local fresh = timers(Host.game)
assert(fresh ~= "", "a running company has timers")

-- Hidden: the company keeps running at the same rate.
Window.frame:Hide()
local before = Host.game.clock.now
for _ = 1, 50 do frame(0.02) end
assert(Host.game.clock.now == before + 1000, "a hidden window does not pause the company")

-- Opened and closed many times: still one step per frame, the same timers.
for _ = 1, 20 do
    env.SlashCmdList.TIMEISMONEY("")
    frame(0.02)
end
assert(timers(Host.game) == fresh, "toggling the window adds no timer")

-- A new company (confirmed): one wakeup, and exactly a fresh company's timers.
local old = Host.game
Window.NewGame()
Window.dialog.yes.scripts.OnClick(Window.dialog.yes)
assert(Host.game ~= old)
frame(0.02)
assert(timers(Host.game) == fresh, "a restart starts exactly a fresh company's timers")
-- The discarded company no longer advances.
local oldNow = old.clock.now
for _ = 1, 10 do frame(0.02) end
assert(old.clock.now == oldNow, "the previous company stops")

print("lifecycle: hidden window keeps running, one host step per frame, no duplicate timers across toggles and restarts passed")
