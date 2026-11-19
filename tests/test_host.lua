-- Host adapter (#18): logical outcomes do not depend on how real time arrives.
dofile("tests/kit.lua") -- the assertions (check, done); this file builds its own client

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
            check(kind == "Frame" and name == nil and parent == nil, "the wakeup frame has no parent")
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
        check(x > 0 and x < 1 and x == b:draw())
    end
    check(a.count == 10000 and a.s1 == b.s1 and a.s2 == b.s2)
    check(not pcall(Host.newRandom, 0, 1) and not pcall(Host.newRandom, 1.5, 2))
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
                check(Host.click("btnMakePaperclip"))
            end
            local before = game.clock.now
            local elapsed = pattern()
            -- Stop exactly at the command time if this wakeup would pass it.
            if not clicked and before + math.floor((Host.debt + elapsed * 1000) / 10) * 10 > 1000 then
                while game.clock.now < 1000 do check(pcall(game.advanceTo, game, game.clock.now + 10)) end
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
        check(ok, "pattern " .. r .. " differs at " .. tostring(where))
        check(runs[1].random.count == runs[r].random.count)
        check(equal(runs[1].game.readouts, runs[r].game.readouts, "readouts"))
        check(equal(runs[1].game.disabled, runs[r].game.disabled, "controls"))
    end
    check(runs[1].game.S.clips >= 1 and runs[1].random.count > 3200)
end

-- A long gap (a loading screen) is capped: the game slows, it never races.
do
    local Host = Load()
    local game = Host.start({ 1, 1 })
    Host.update(10)
    check(game.clock.now == Host.MAX_DEBT and Host.stats.dropped == 9000 and Host.debt == 0)
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
    check(game.clock.now == 30, "three 3 ms steps reach the 8 ms budget: " .. game.clock.now)
    check(math.abs(Host.debt - 70) < 1e-9)
    Host.update(0)
    check(game.clock.now == 60)
end

-- An error inside a tick halts the simulation; it stays stopped and says why.
do
    local Host, _, _, messages = Load()
    local game = Host.start({ 3, 3 })
    game.clock:register(function() error("boom", 0) end, 25, false, "test")
    Host.update(0.1)
    check(not Host.running and Host.halted == "boom" and messages[#messages]:find("simulation stopped: boom", 1, true))
    local now = game.clock.now
    Host.update(1)
    check(game.clock.now == now and now == 25, "stopped at the failing timer: " .. now)
    local ok, err = Host.click("btnMakePaperclip")
    -- A halted company is not a missing one: no advice to /tim start (it would refuse).
    check(not ok and err:find("the company stopped: ", 1, true) and not err:find("/tim start", 1, true))
end

-- Commands are validated; a refused control leaves the game running.
do
    local Host = Load()
    local game = Host.start({ 5, 5 })
    local ok, err = Host.click("btnNotAControl")
    check(not ok and err:find("unknown control", 1, true))
    -- A control outside the slice is unknown to the host; a known one the game
    -- refuses (a project button not in the document) leaves the game running.
    ok, err = Host.click("btnFeedSwarm")
    check(not ok and err:find("unknown control", 1, true))
    ok, err = Host.click("projectButton18")
    check(not ok and err:find("Unknown clickable ID", 1, true) and Host.running)
    ok, err = Host.setValue("investStrat", "med")
    check(ok and game.selects.investStrat.value == "med")
    ok, err = Host.setValue("nope", "1")
    check(not ok and err:find("unknown value control", 1, true))
    -- The auto-save calls the host hook at 250 slow ticks without changing state.
    local saved = 0
    game.onSave = function() saved = saved + 1 end
    game.S.saveTimer = 249
    game:advanceTo(game.clock.now + 100)
    check(saved == 1 and game.S.saveTimer <= 1)
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
    check(game.projectElements[route[1]] and not game.disabled[route[1]], route[1] .. " is offered")
    local ok, how = Host.click(route[1])
    check(ok and how == "restart" and S[route[2]] == 1 and game.savedPrestige[route[2]] == 1)
    local fresh = Host.game
    check(fresh ~= game and Host.running and fresh.S[route[2]] == 1 and fresh.S.clips == 0,
        "the next company starts with the prestige")
    check(fresh.projectElements[route[1]] == nil, "and without the old offer: no second award")
    local now = game.clock.now
    Host.update(1)
    check(game.clock.now == now and fresh.clock.now > 0, "the old company does not run on")
    -- Logout writes the new company and the prestige.
    local db = Host.persist()
    check(db.company and db.prestige[route[2]] == 1)
end

-- Quantum Temporal Reversion and the new-game control: a fresh company, the
-- prestige kept (the reference's reset()); refused while saving is off.
do
    local Host = Load()
    check(Host.loadSaved({ schema = 1, prestige = { prestigeU = 2, prestigeS = 0 } }) == "empty")
    local game = Host.start({ 51, 53 })
    game.S.prestigeU = 5 -- the company's own value: the reversion keeps the account's (2)
    game.S.standardOps, game.S.compFlag = -20000, 1
    game:advanceTo(game.clock.now + 30)
    check(game.projectElements.projectButton217, "the reversion is offered")
    -- It needs the player's confirmation: refused without, done with.
    local refused, why = Host.click("projectButton217")
    check(not refused and why:find("confirmation", 1, true) and Host.game == game)
    local ok, how = Host.click("projectButton217", true)
    check(ok and how == "restart" and Host.game ~= game and Host.game.S.prestigeU == 2 and Host.game.S.clips == 0)
    local before = Host.game
    before.S.clips = 50
    check(Host.newGame() and Host.game ~= before and Host.game.S.clips == 0 and Host.game.S.prestigeU == 2)
    -- A company that halted on its prestige choice still hands its earned prestige
    -- to the new game (the review of #68).
    local halted = Host.game
    halted.restartRequested, halted.savedPrestige = "prestige", { prestigeU = 3, prestigeS = 0 }
    Host.halt("test")
    check(Host.newGame() and Host.game.S.prestigeU == 3 and Host.prestige.prestigeU == 3)
    -- A confirmation that arrives after the offer lapsed says so.
    Host.game.projectElements.projectButton217 = nil
    local lapsed, reason = Host.click("projectButton217", true)
    check(not lapsed and reason == "no longer available")
    Host.blocked = "a save from a newer version"
    refused, why = Host.newGame()
    check(not refused and why:find("saving is off", 1, true))
end

-- A reset is kept even when the new company halts before its first snapshot: a
-- restored company with no prestige, a new game, then a halt; logout must not let
-- the discarded company come back (Codex review of #68).
do
    local Host = Load()
    local original = Host.start({ 61, 63 })
    original.S.clips = 777
    local saved = Host.encodeCompany()
    local Host2 = Load()
    check(Host2.loadSaved({ schema = 1, company = saved }) == "restored" and Host2.game.S.clips == 777)
    check(Host2.newGame())
    Host2.halt("a tick error before the first snapshot")
    local db = Host2.persist()
    check(db and db.schema == 1 and db.company == nil and db.prestige == nil, "the reset is written")
    local Host3 = Load()
    check(Host3.loadSaved(db) == "empty" and Host3.game == nil, "reload does not restore the old company")
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
    check(Host.snapshot == nil and Host.saves == Host.SNAPSHOT_EVERY - 1)
    game.S.saveTimer = 249
    Host.update(0.1)
    check(Host.snapshot == nil and Host.snapshotDue, "marked during the step")
    Host.update(0) -- taken first thing in the next frame, before any step
    check(Host.snapshot ~= nil and Host.stats.snapshotMs ~= nil)
end
do
    local Host = Load()
    -- Without a company the save is still written (in the client it holds the
    -- settings), with no company or prestige in it.
    check(Host.loadSaved(nil) == "empty")
    local empty = Host.persist()
    check(empty.schema == 1 and empty.company == nil and empty.prestige == nil, "an empty save")
    local game = Host.start({ 21, 23 })
    Host.saves = Host.SNAPSHOT_EVERY - 1 -- the next auto-save refreshes the snapshot
    game.S.saveTimer = 249
    Host.update(0.1) -- the auto-save marks a snapshot for the next frame
    Host.update(0)
    check(Host.snapshot and Host.snapshot.clock.now == 100)
    -- The snapshot holds the slow timer already requeued: restoring it does not
    -- replay the slow tick that wrote it (Codex consult on #19).
    local slow
    for _, t in ipairs(Host.snapshot.clock.timers) do if t.kind == "slow" then slow = t end end
    check(slow.due == 200 and Host.snapshot.nodes[Host.snapshot.root].saveTimer == 0)
    Host.update(0.3)
    local db = Host.persist()
    check(db.schema == 1 and db.company.clock.now == 400, "a running company is saved as it is")
    -- A tick error: the partly run tick is never saved; the last auto-save is.
    game.clock:register(function() error("boom", 0) end, 5, false, "test")
    Host.update(0.01)
    check(not Host.running and Host.persist().company.clock.now == 100)
    -- Saved prestige carries on; after a prestige choice only the prestige is kept.
    local Host2 = Load()
    check(Host2.loadSaved({ schema = 1, prestige = { prestigeU = 2, prestigeS = 1 } }) == "empty")
    local game2 = Host2.start({ 25, 27 })
    game2.savedPrestige, game2.restartRequested = { prestigeU = 3, prestigeS = 1 }, "prestige"
    local db2 = Host2.persist()
    check(db2.company == nil and db2.prestige.prestigeU == 3 and db2.prestige.prestigeS == 1)
    -- A new company starts with the saved prestige (loadPrestige in the reference).
    local Host4 = Load()
    Host4.loadSaved({ schema = 1, prestige = { prestigeU = 2, prestigeS = 1 } })
    local game4 = Host4.start({ 29, 31 })
    check(game4.S.prestigeU == 2 and game4.S.prestigeS == 1)
    local Host3 = Load()
    check(Host3.loadSaved({ schema = 1, prestige = { prestigeU = 2, prestigeS = 1 } }) == "empty")
    check(Host3.persist().prestige.prestigeU == 2, "prestige survives a session without a company")
    check(Host3.loadSaved({ schema = 1, prestige = { prestigeU = "x" } }) == "blocked" and Host3.persist() == nil)
end

-- A save with a damaged random stream is refused at load, not halted later; a
-- snapshot that fails is reported at once (review of #55).
do
    local Host = Load()
    local game = Host.start({ 41, 43 })
    local data = Host.encodeCompany()
    data.random.count = nil
    check(Host.loadSaved({ schema = 1, company = data }) == "blocked" and Host.blocked:find("random count", 1, true))
    local Host2, _, _, messages = Load()
    local game2 = Host2.start({ 45, 47 })
    game2.S.badKey = { [0.5] = 1 } -- unsaveable: a fractional key
    Host2.takeSnapshot()
    check(Host2.saveFailed and messages[#messages]:find("SAVING FAILED", 1, true))
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
    check(allocated < 256, string.format("%.0f KB allocated in 10 s", allocated))
end

-- Covered: random stream, wakeup batching, commands, debt cap, frame budget, halting and allocation.
done("test_host")
