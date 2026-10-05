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
    game.clock:register(function() error("boom", 0) end, 25, false, "test")
    Host.update(0.1)
    assert(not Host.running and Host.halted == "boom" and messages[#messages]:find("simulation stopped: boom", 1, true))
    local now = game.clock.now
    Host.update(1)
    assert(game.clock.now == now and now == 25, "stopped at the failing timer: " .. now)
    local ok, err = Host.click("btnMakePaperclip")
    -- A halted company is not a missing one: no advice to /tim start (it would refuse).
    assert(not ok and err:find("the company stopped: ", 1, true) and not err:find("/tim start", 1, true))
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
    ok, err = Host.click("projectButton18")
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

-- A prestige choice awards and saves its prestige, then the next company starts
-- with it at once (#23): the old company never runs again, so the reward cannot be
-- collected twice (Codex review of #54).
for _, route in ipairs({ { "projectButton200", "prestigeU", { compFlag = 1, standardOps = 400000, memory = 400 } },
        { "projectButton201", "prestigeS", { creativity = 400000 } } }) do
    local Host = Load()
    local game = Host.start({ 17, 19 })
    local S = game.S
    S.project147.flag = 1
    for k, v in pairs(route[3]) do S[k] = v end
    game:advanceTo(game.clock.now + 30) -- the project appears and its cost is met
    assert(game.projectElements[route[1]] and not game.disabled[route[1]], route[1] .. " is offered")
    local ok, how = Host.click(route[1])
    assert(ok and how == "restart" and S[route[2]] == 1 and game.savedPrestige[route[2]] == 1)
    local fresh = Host.game
    assert(fresh ~= game and Host.running and fresh.S[route[2]] == 1 and fresh.S.clips == 0,
        "the next company starts with the prestige")
    assert(fresh.projectElements[route[1]] == nil, "and without the old offer: no second award")
    local now = game.clock.now
    Host.update(1)
    assert(game.clock.now == now and fresh.clock.now > 0, "the old company does not run on")
    -- Logout writes the new company and the prestige.
    local db = Host.persist()
    assert(db.company and db.prestige[route[2]] == 1)
end

-- Quantum Temporal Reversion and the new-game control: a fresh company, the
-- prestige kept (the reference's reset()); refused while saving is off.
do
    local Host = Load()
    assert(Host.loadSaved({ schema = 1, prestige = { prestigeU = 2, prestigeS = 0 } }) == "empty")
    local game = Host.start({ 51, 53 })
    game.S.prestigeU = 5 -- the company's own value: the reversion keeps the account's (2)
    game.S.standardOps, game.S.compFlag = -20000, 1
    game:advanceTo(game.clock.now + 30)
    assert(game.projectElements.projectButton217, "the reversion is offered")
    -- It needs the player's confirmation: refused without, done with.
    local refused, why = Host.click("projectButton217")
    assert(not refused and why:find("confirmation", 1, true) and Host.game == game)
    local ok, how = Host.click("projectButton217", true)
    assert(ok and how == "restart" and Host.game ~= game and Host.game.S.prestigeU == 2 and Host.game.S.clips == 0)
    local before = Host.game
    before.S.clips = 50
    assert(Host.newGame() and Host.game ~= before and Host.game.S.clips == 0 and Host.game.S.prestigeU == 2)
    -- A company that halted on its prestige choice still hands its earned prestige
    -- to the new game (the review of #68).
    local halted = Host.game
    halted.restartRequested, halted.savedPrestige = "prestige", { prestigeU = 3, prestigeS = 0 }
    Host.halt("test")
    assert(Host.newGame() and Host.game.S.prestigeU == 3 and Host.prestige.prestigeU == 3)
    -- A confirmation that arrives after the offer lapsed says so.
    Host.game.projectElements.projectButton217 = nil
    local lapsed, reason = Host.click("projectButton217", true)
    assert(not lapsed and reason == "no longer available")
    Host.blocked = "a save from a newer version"
    refused, why = Host.newGame()
    assert(not refused and why:find("saving is off", 1, true))
end

-- Saves (#19): what logout writes in each case.
-- The snapshot comes on every SNAPSHOT_EVERY-th reference auto-save only.
do
    local Host = Load()
    local game = Host.start({ 33, 35 })
    for _ = 1, Host.SNAPSHOT_EVERY - 1 do
        game.S.saveTimer = 249
        Host.update(0.1)
    end
    assert(Host.snapshot == nil and Host.saves == Host.SNAPSHOT_EVERY - 1)
    game.S.saveTimer = 249
    Host.update(0.1)
    assert(Host.snapshot == nil and Host.snapshotDue, "marked during the step")
    Host.update(0) -- taken first thing in the next frame, before any step
    assert(Host.snapshot ~= nil and Host.stats.snapshotMs ~= nil)
end
do
    local Host = Load()
    assert(Host.loadSaved(nil) == "empty" and Host.persist() == nil, "nothing to write without a company")
    local game = Host.start({ 21, 23 })
    Host.saves = Host.SNAPSHOT_EVERY - 1 -- the next auto-save refreshes the snapshot
    game.S.saveTimer = 249
    Host.update(0.1) -- the auto-save marks a snapshot for the next frame
    Host.update(0)
    assert(Host.snapshot and Host.snapshot.clock.now == 100)
    -- The snapshot holds the slow timer already requeued: restoring it does not
    -- replay the slow tick that wrote it (Codex consult on #19).
    local slow
    for _, t in ipairs(Host.snapshot.clock.timers) do if t.kind == "slow" then slow = t end end
    assert(slow.due == 200 and Host.snapshot.nodes[Host.snapshot.root].saveTimer == 0)
    Host.update(0.3)
    local db = Host.persist()
    assert(db.schema == 1 and db.company.clock.now == 400, "a running company is saved as it is")
    -- A tick error: the partly run tick is never saved; the last auto-save is.
    game.clock:register(function() error("boom", 0) end, 5, false, "test")
    Host.update(0.01)
    assert(not Host.running and Host.persist().company.clock.now == 100)
    -- Saved prestige carries on; after a prestige choice only the prestige is kept.
    local Host2 = Load()
    assert(Host2.loadSaved({ schema = 1, prestige = { prestigeU = 2, prestigeS = 1 } }) == "empty")
    local game2 = Host2.start({ 25, 27 })
    game2.savedPrestige, game2.restartRequested = { prestigeU = 3, prestigeS = 1 }, "prestige"
    local db2 = Host2.persist()
    assert(db2.company == nil and db2.prestige.prestigeU == 3 and db2.prestige.prestigeS == 1)
    -- A new company starts with the saved prestige (loadPrestige in the reference).
    local Host4 = Load()
    Host4.loadSaved({ schema = 1, prestige = { prestigeU = 2, prestigeS = 1 } })
    local game4 = Host4.start({ 29, 31 })
    assert(game4.S.prestigeU == 2 and game4.S.prestigeS == 1)
    local Host3 = Load()
    assert(Host3.loadSaved({ schema = 1, prestige = { prestigeU = 2, prestigeS = 1 } }) == "empty")
    assert(Host3.persist().prestige.prestigeU == 2, "prestige survives a session without a company")
    assert(Host3.loadSaved({ schema = 1, prestige = { prestigeU = "x" } }) == "blocked" and Host3.persist() == nil)
end

-- A save with a damaged random stream is refused at load, not halted later; a
-- snapshot that fails is reported at once (review of #55).
do
    local Host = Load()
    local game = Host.start({ 41, 43 })
    local data = Host.encodeCompany()
    data.random.count = nil
    assert(Host.loadSaved({ schema = 1, company = data }) == "blocked" and Host.blocked:find("random count", 1, true))
    local Host2, _, _, messages = Load()
    local game2 = Host2.start({ 45, 47 })
    game2.S.badKey = { [0.5] = 1 } -- unsaveable: a fractional key
    Host2.takeSnapshot()
    assert(Host2.saveFailed and messages[#messages]:find("SAVING FAILED", 1, true))
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
