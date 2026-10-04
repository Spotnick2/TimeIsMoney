-- Host adapter (#18): logical outcomes do not depend on how real time arrives.
local function Load()
    local clock = 0
    local frames, messages = {}, {}
    local env = {
        math = math, string = string, table = table, pairs = pairs, ipairs = ipairs, type = type,
        tonumber = tonumber, tostring = tostring, error = error, setmetatable = setmetatable, next = next,
        select = select, pcall = pcall,
        print = function(message) messages[#messages + 1] = message end,
        GetServerTime = function() return 1790000000 end,
        debugprofilestop = function() return clock end,
        CreateFrame = function(kind, name, parent)
            assert(kind == "Frame" and name == nil and parent == nil, "the wakeup frame has no parent")
            local frame = { scripts = {} }
            function frame:SetScript(script, fn) self.scripts[script] = fn end
            frames[#frames + 1] = frame
            return frame
        end,
    }
    env.TimeIsMoney = {}
    setmetatable(env, { __index = function(_, key) error("Unvalidated global: " .. tostring(key), 2) end })
    local ns = {}
    local files = {}
    for line in io.lines("TimeIsMoney.toc") do
        line = line:match("^%s*(.-)%s*$")
        if line:match("^Sim/") or line == "Host.lua" then files[#files + 1] = line end
    end
    for _, path in ipairs(files) do
        local chunk = assert(loadfile(path))
        setfenv(chunk, env)
        chunk("TimeIsMoney", ns)
    end
    local control = {}
    function control.advanceClock(ms) clock = clock + ms end
    return ns.Host, ns, frames, messages, control
end

local function equal(a, b, path)
    if type(a) ~= type(b) then return false, path end
    if type(a) ~= "table" then
        if a ~= a and b ~= b then return true end
        return a == b, path
    end
    for k, v in pairs(a) do
        local ok, where = equal(v, b[k], path .. "." .. tostring(k))
        if not ok then return false, where end
    end
    for k in pairs(b) do
        if a[k] == nil then return false, path .. "." .. tostring(k) end
    end
    return true
end

-- The random stream: deterministic, in (0, 1), two integers of state.
do
    local Host = Load()
    local a, b = Host.newRandom(12345, 67890), Host.newRandom(12345, 67890)
    for _ = 1, 10000 do
        local x = a:draw()
        assert(x > 0 and x < 1 and x == b:draw())
    end
    assert(a.count == 10000 and a.s1 == b.s1 and a.s2 == b.s2)
    assert(not pcall(Host.newRandom, 0, 1) and not pcall(Host.newRandom, 1.5, 2))
end

-- Different frame rates and irregular wakeups reach the same state at the same
-- logical time; a command at the same logical time has the same outcome.
do
    local patterns = {
        function() return 1 / 60 end,
        function() return 0.05 end,
        (function()
            local list, i = { 0.003, 0.051, 0.017, 0.2, 0.009, 0.033 }, 0
            return function() i = i % #list + 1 return list[i] end
        end)(),
    }
    local runs = {}
    for r, pattern in ipairs(patterns) do
        local Host = Load()
        local game = Host.start({ 4242, 2424 })
        local clicked = false
        while game.clock.now < 2500 do
            -- The command lands at logical 1000 in every run.
            if not clicked and game.clock.now >= 1000 then
                while game.clock.now > 1000 do error("advanced past the command time") end
                clicked = true
                assert(Host.click("btnMakePaperclip"))
            end
            local before = game.clock.now
            local elapsed = pattern()
            -- Stop exactly at the command time if this wakeup would pass it.
            if not clicked and before + math.floor((Host.debt + elapsed * 1000) / 10) * 10 > 1000 then
                while game.clock.now < 1000 do assert(pcall(game.advanceTo, game, game.clock.now + 10)) end
            else
                Host.update(elapsed)
            end
        end
        runs[r] = Host
    end
    local target = 0
    for _, Host in ipairs(runs) do target = math.max(target, Host.game.clock.now) end
    for _, Host in ipairs(runs) do
        while Host.game.clock.now < target do Host.game:advanceTo(Host.game.clock.now + 10) end
    end
    for r = 2, #runs do
        local ok, where = equal(runs[1].game.S, runs[r].game.S, "S")
        assert(ok, "pattern " .. r .. " differs at " .. tostring(where))
        assert(runs[1].random.count == runs[r].random.count)
        assert(equal(runs[1].game.readouts, runs[r].game.readouts, "readouts"))
        assert(equal(runs[1].game.disabled, runs[r].game.disabled, "controls"))
    end
    assert(runs[1].game.S.clips >= 1 and runs[1].random.count > 3200)
end

-- A long gap (a loading screen) is capped: the game slows, it never races.
do
    local Host = Load()
    local game = Host.start({ 1, 1 })
    Host.update(10)
    assert(game.clock.now == Host.MAX_DEBT and Host.stats.dropped == 9000 and Host.debt == 0)
end

-- The per-frame CPU budget: an expensive frame stops early and carries its debt.
do
    local Host, _, _, _, control = Load()
    local game = Host.start({ 7, 7 })
    local advance = game.advanceTo
    game.advanceTo = function(self, target)
        control.advanceClock(3) -- each step costs 3 ms here
        return advance(self, target)
    end
    Host.update(0.1)
    assert(game.clock.now == 30, "three 3 ms steps reach the 8 ms budget: " .. game.clock.now)
    assert(math.abs(Host.debt - 70) < 1e-9)
    Host.update(0)
    assert(game.clock.now == 60)
end

-- An error inside a tick halts the simulation; it stays stopped and says why.
do
    local Host, _, _, messages = Load()
    local game = Host.start({ 3, 3 })
    game.clock:register(function() error("boom", 0) end, 25, false)
    Host.update(0.1)
    assert(not Host.running and Host.halted == "boom" and messages[#messages]:find("simulation stopped: boom", 1, true))
    local now = game.clock.now
    Host.update(1)
    assert(game.clock.now == now and now == 25, "stopped at the failing timer: " .. now)
    local ok, err = Host.click("btnMakePaperclip")
    assert(not ok and err:find("no running game", 1, true))
end

-- Commands are validated; a refused control leaves the game running.
do
    local Host = Load()
    local game = Host.start({ 5, 5 })
    local ok, err = Host.click("btnNotAControl")
    assert(not ok and err:find("unknown control", 1, true))
    -- A control outside the slice is unknown to the host; a known one the game
    -- refuses (a project button not in the document) leaves the game running.
    ok, err = Host.click("btnFeedSwarm")
    assert(not ok and err:find("unknown control", 1, true))
    ok, err = Host.click("projectButton217")
    assert(not ok and err:find("Unknown clickable ID", 1, true) and Host.running)
    ok, err = Host.setValue("investStrat", "med")
    assert(ok and game.selects.investStrat.value == "med")
    ok, err = Host.setValue("nope", "1")
    assert(not ok and err:find("unknown value control", 1, true))
    -- The auto-save calls the host hook at 250 slow ticks without changing state.
    local saved = 0
    game.onSave = function() saved = saved + 1 end
    game.S.saveTimer = 249
    game:advanceTo(game.clock.now + 100)
    assert(saved == 1 and game.S.saveTimer <= 1)
end

-- Garbage: the client measured 111 MB of addon memory before the grid reuse and
-- the log-free scheduler; ten logical seconds now allocate almost nothing.
do
    local Host = Load()
    local game = Host.start({ 11, 13 })
    game:advanceTo(1000)
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    game:advanceTo(11000)
    local allocated = collectgarbage("count") - before
    collectgarbage("restart")
    assert(allocated < 256, string.format("%.0f KB allocated in 10 s", allocated))
end

print("host: random stream, wakeup batching, commands, debt cap, frame budget, halting and allocation passed")
