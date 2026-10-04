-- Host adapter (#18): runs the pure simulation (Sim/) in the client. The only
-- clock is the logical one the simulation already uses; native frame updates are
-- wakeups that advance it, never a source of ordering. Commands are validated and
-- applied at the current logical time. No offline production: logical time only
-- moves while the client runs a session.
local _, ns = ...
local TIM = TimeIsMoney

local Host = {}
TIM.Host = Host
ns.Host = Host

local floor = math.floor

-- Logical step per advance, and the most real time owed to the simulation. A
-- client too slow to keep up (or a loading screen) drops time beyond MAX_DEBT, so
-- the game slows instead of freezing the frame; it never runs ahead.
Host.STEP = 10            -- ms of logical time
Host.MAX_DEBT = 1000      -- ms
Host.FRAME_BUDGET = 8     -- ms of CPU per frame for the simulation

-- Random stream: L'Ecuyer (1988) combined multiplicative congruential generator.
-- Every product stays below 2^47, so double arithmetic is exact on every host; the
-- period is about 2.3e18 and the state is two integers (saved by #19). Draws are
-- in (0, 1). Cosmetic randomness must use a separate stream.
local M1, A1, M2, A2 = 2147483563, 40014, 2147483399, 40692
local Random = {}
Random.__index = Random

function Host.newRandom(s1, s2)
    if not (s1 == floor(s1) and s1 >= 1 and s1 < M1 and s2 == floor(s2) and s2 >= 1 and s2 < M2) then
        error("Random seeds must be integers in [1, m - 1]", 2)
    end
    return setmetatable({ s1 = s1, s2 = s2, count = 0 }, Random)
end

function Random:draw()
    self.s1 = (A1 * self.s1) % M1
    self.s2 = (A2 * self.s2) % M2
    local z = (self.s1 - self.s2) % (M1 - 1)
    if z == 0 then z = M1 - 1 end
    self.count = self.count + 1
    return z / M1
end


local function Report(message)
    print("|cffd9a066Time Is Money|r: " .. message)
end

-- Starts a new company. seeds is optional ({s1, s2}); by default the server time
-- and the profiler clock seed the stream.
function Host.start(seeds)
    local s1 = seeds and seeds[1] or (GetServerTime() % (M1 - 1)) + 1
    local s2 = seeds and seeds[2] or (floor(debugprofilestop() * 1000) % (M2 - 1)) + 1
    Host.random = Host.newRandom(s1, s2)
    Host.game = ns.Workshop.new(Host.random, false) -- no trace log in the client
    Host.debt = 0
    Host.halted = nil
    Host.stats = { frames = 0, cpu = 0, steps = 0, dropped = 0, worst = 0 }
    Host.running = true
    return Host.game
end

-- Stops on an explicit unported path or any other error inside a tick: the tick
-- has partly run, so the simulation must not continue.
function Host.halt(reason)
    Host.running = false
    Host.halted = tostring(reason)
    Report("simulation stopped: " .. Host.halted)
end

-- Owes the simulation `elapsed` real seconds, then advances it in logical steps
-- until the debt is paid or the frame's CPU budget is spent.
function Host.update(elapsed)
    if not Host.running then return end
    local stats = Host.stats
    Host.debt = Host.debt + elapsed * 1000
    if Host.debt > Host.MAX_DEBT then
        stats.dropped = stats.dropped + (Host.debt - Host.MAX_DEBT)
        Host.debt = Host.MAX_DEBT
    end
    local start = debugprofilestop()
    local game = Host.game
    while Host.debt >= Host.STEP do
        local ok, err = pcall(game.advanceTo, game, game.clock.now + Host.STEP)
        if not ok then
            Host.halt(err)
            break
        end
        Host.debt = Host.debt - Host.STEP
        stats.steps = stats.steps + 1
        if debugprofilestop() - start >= Host.FRAME_BUDGET then break end
    end
    local cost = debugprofilestop() - start
    stats.frames = stats.frames + 1
    stats.cpu = stats.cpu + cost
    if cost > stats.worst then stats.worst = cost end
end

-- Validated commands: a known control, applied at the current logical time. A
-- control the slice refuses (an unported path, a project not shown) raises before
-- changing state, so the game keeps running and the refusal is reported. The one
-- exception is a prestige choice: it awards and saves the prestige, then requests
-- the restart into a new game (#23). That company is over, so the host halts it.
function Host.click(id)
    local game = Host.game
    if not (game and Host.running) then return false, "no running game (/tim start)" end
    local known = ns.Workshop.clicks[id] or ns.Workshop.projectById[id]
    if not known then return false, "unknown control " .. tostring(id) end
    local ok, err = pcall(game.click, game, id)
    if not ok then
        if game.restartRequested then Host.halt(err) end
        return false, tostring(err)
    end
    return true
end

function Host.setValue(id, value)
    local game = Host.game
    if not (game and Host.running) then return false, "no running game (/tim start)" end
    if not (game.selects[id] or game.ranges[id]) then return false, "unknown value control " .. tostring(id) end
    local ok, err = pcall(game.setValue, game, id, value)
    if not ok then return false, tostring(err) end
    return true
end

-- One wakeup frame, created once at load. It has no parent, so hiding the UI
-- (Alt-Z), closing windows or combat never pause the simulation; reopening a
-- window creates no timer.
local wakeup = CreateFrame("Frame")
wakeup:SetScript("OnUpdate", function(_, elapsed) Host.update(elapsed) end)
Host.frame = wakeup
