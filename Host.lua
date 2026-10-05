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
-- The in-memory snapshot (the fallback for a company halted by a tick error) costs
-- several ms in one frame, so it is refreshed on every SNAPSHOT_EVERY-th reference
-- auto-save (25 s each): about every 5 minutes. Disk writes happen at logout.
Host.SNAPSHOT_EVERY = 12
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

local function Begin(game)
    Host.game = game
    Host.debt = 0
    Host.halted = nil
    Host.stats = { frames = 0, cpu = 0, steps = 0, dropped = 0, worst = 0 }
    Host.running = true
    -- The 25 s reference auto-save refreshes the in-memory save (#19). It fires
    -- inside the slow tick, before the scheduler requeues that timer, so the snapshot
    -- is taken after the step returns, when the queue is consistent.
    Host.saves = 0
    game.onSave = function()
        Host.saves = Host.saves + 1
        if Host.saves % Host.SNAPSHOT_EVERY == 0 then Host.snapshotDue = true end
    end
    Host.snapshotDue = false
    return game
end

-- Starts a new company. seeds is optional ({s1, s2}); by default the server time
-- and the profiler clock seed the stream.
function Host.start(seeds)
    local s1 = seeds and seeds[1] or (GetServerTime() % (M1 - 1)) + 1
    local s2 = seeds and seeds[2] or (floor(debugprofilestop() * 1000) % (M2 - 1)) + 1
    Host.random = Host.newRandom(s1, s2)
    Host.snapshot = nil
    local game = ns.Workshop.new(Host.random, false) -- no trace log in the client
    -- Saved prestige applies to a new company, as loadPrestige does in the reference.
    if Host.prestige then
        game.S.prestigeU, game.S.prestigeS = Host.prestige.prestigeU, Host.prestige.prestigeS
    end
    return Begin(game)
end

-- Saves (#19) ---------------------------------------------------------------------
-- TimeIsMoneyDB = { schema = 1, company = <Sim/Save.lua data> or nil,
--                   prestige = { prestigeU, prestigeS } or nil }
-- One company per account. Logical time continues from the save: no offline time.

function Host.encodeCompany()
    return ns.Save.encode(Host.game, Host.random)
end

-- Refreshes the in-memory snapshot. A failure means the company can no longer be
-- saved: it is reported at once (not only at logout), with what the player keeps.
function Host.takeSnapshot()
    local before = debugprofilestop()
    local ok, data = pcall(Host.encodeCompany)
    Host.stats.snapshotMs = debugprofilestop() - before
    if ok then
        Host.snapshot = data
        Host.saveFailed = nil
    elseif not Host.saveFailed then
        Host.saveFailed = tostring(data)
        local at = Host.snapshot and Host.snapshot.clock.now
        Report("SAVING FAILED: " .. Host.saveFailed .. ". Logging out keeps the company as of "
            .. (type(at) == "number" and string.format("%.0f s", at / 1000) or "its last load")
            .. "; please report this.")
    end
end

local function validPrestige(p)
    return type(p) == "table" and type(p.prestigeU) == "number" and type(p.prestigeS) == "number"
end
-- A copy of a prestige record (a valid one, or nil).
local function copyPrestige(p)
    if not validPrestige(p) then return nil end
    return { prestigeU = p.prestigeU, prestigeS = p.prestigeS }
end

-- Reads TimeIsMoneyDB at load. Unknown, future or broken data blocks saving so it is
-- never replaced; it is reported and left as it is.
function Host.loadSaved(db)
    Host.blocked, Host.prestige = nil, nil
    if db == nil then return "empty" end
    if type(db) ~= "table" or type(db.schema) ~= "number" then
        Host.blocked = "unrecognized saved data"
        return "blocked"
    end
    if db.schema ~= ns.Save.SCHEMA then
        Host.blocked = db.schema > ns.Save.SCHEMA and ("a save from a newer version (schema " .. db.schema .. ")")
            or ("an unsupported old save (schema " .. db.schema .. ")")
        return "blocked"
    end
    if db.prestige ~= nil then
        if not validPrestige(db.prestige) then
            Host.blocked = "unrecognized saved prestige"
            return "blocked"
        end
        Host.prestige = copyPrestige(db.prestige)
    end
    if db.company == nil then return "empty" end
    local ok, err = pcall(function()
        local saved = db.company
        local r = saved.random
        if type(r) ~= "table" then error("Malformed save: random", 0) end
        if not (type(r.count) == "number" and r.count >= 0 and r.count == floor(r.count)) then
            error("Malformed save: random count", 0)
        end
        local random = Host.newRandom(r.s1, r.s2)
        random.count = r.count
        local game = ns.Save.decode(saved, random, false)
        Host.random = random
        Begin(game)
        Host.snapshot = saved
    end)
    if not ok then
        Host.game, Host.running = nil, false
        Host.blocked = "the saved company could not be restored (" .. tostring(err) .. ")"
        return "blocked"
    end
    return "restored"
end

-- What to store at logout, or nil to leave TimeIsMoneyDB untouched. A halted game
-- (a tick that partly ran) keeps its last good auto-save. A restart normally
-- replaces the company at once (Host.restart); only when it could not (the choice's
-- tick halted) is the old company still here, over, and only its earned prestige
-- carries on.
function Host.persist()
    if Host.blocked then return nil end
    local game = Host.game
    local db = { schema = ns.Save.SCHEMA, prestige = Host.prestige }
    if game and game.restartRequested and game.savedPrestige then
        db.prestige = copyPrestige(game.savedPrestige)
        return db
    end
    if game and Host.running then
        local ok, data = pcall(Host.encodeCompany)
        if ok then
            db.company = data
        else
            Report("could not save the company (" .. tostring(data) .. "); keeping the last auto-save")
            db.company = Host.snapshot
        end
    else
        db.company = Host.snapshot
    end
    if db.company == nil and db.prestige == nil then return nil end
    return db
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
    -- A snapshot marked by the last frame's auto-save comes first, so this frame
    -- spends at most its budget: the snapshot, then steps if time is left.
    if Host.snapshotDue then
        Host.snapshotDue = false
        Host.takeSnapshot()
    end
    while Host.debt >= Host.STEP and debugprofilestop() - start < Host.FRAME_BUDGET do
        local ok, err = pcall(game.advanceTo, game, game.clock.now + Host.STEP)
        if not ok then
            Host.halt(err)
            break
        end
        Host.debt = Host.debt - Host.STEP
        stats.steps = stats.steps + 1
        -- An auto-save marks the snapshot for the next frame.
        if Host.snapshotDue then break end
        if debugprofilestop() - start >= Host.FRAME_BUDGET then break end
    end
    local cost = debugprofilestop() - start
    stats.frames = stats.frames + 1
    stats.cpu = stats.cpu + cost
    if cost > stats.worst then stats.worst = cost end
end

-- Restarts (#23): the reference's reset() clears the company's save, keeps the
-- prestige and reloads. A prestige choice or Quantum Temporal Reversion requests it
-- from inside the simulation; the new-game control asks for it directly. The next
-- company starts at once with the prestige; the old one is never run again.
function Host.restart(prestige)
    if Host.blocked then return false, "saving is off (" .. Host.blocked .. "); the saved data is kept untouched" end
    if prestige then Host.prestige = copyPrestige(prestige) end
    Host.start()
    return true
end

-- The new-game control: a fresh company, the account's prestige kept (as reset()).
-- A company that ended on a prestige choice but halted before its restart still
-- carries its earned prestige into the new one. The window asks for explicit
-- confirmation first.
function Host.newGame()
    local game = Host.game
    local earned = game and game.restartRequested == "prestige" and game.savedPrestige or nil
    return Host.restart(earned)
end

-- Controls that end the company need an explicit confirmation (the reference asks
-- confirm() inside the effect): Host.click refuses them unless the caller says the
-- player confirmed (the window's dialog does).
Host.CONFIRM = { projectButton217 = true }

-- Validated commands: a known control, applied at the current logical time. A
-- control the slice refuses (an unported path, a project not shown) raises before
-- changing state, so the game keeps running and the refusal is reported. A click
-- that ends the company (a prestige choice, Quantum Temporal Reversion) requests a
-- restart, and the next company starts with the saved prestige.
function Host.click(id, confirmed)
    local game = Host.game
    if not game then return false, "no company (/tim start)" end
    if not Host.running then return false, "the company stopped: " .. tostring(Host.halted) .. " (/tim status)" end
    local known = ns.Workshop.clicks[id] or ns.Workshop.projectById[id]
    if not known then return false, "unknown control " .. tostring(id) end
    if Host.CONFIRM[id] and not confirmed then return false, "this needs the player's confirmation" end
    -- A confirmation can arrive after the offer lapsed (the game kept running while
    -- the dialog was open): say so rather than doing nothing silently.
    if confirmed and (game.disabled[id] or (ns.Workshop.projectById[id] and not game.projectElements[id])) then
        return false, "no longer available"
    end
    local ok, err = pcall(game.click, game, id)
    if game.restartRequested then
        -- The company is over whatever happened next: never run it again.
        if not ok then Host.halt(err) return false, tostring(err) end
        -- A prestige choice carries its prestige; a reversion keeps the account's
        -- (reset() reloads the stored prestige, not the company's own values).
        local prestige = game.restartRequested == "prestige" and game.savedPrestige or nil
        local restarted, why = Host.restart(prestige)
        if not restarted then Host.halt(why) return false, why end
        return true, "restart"
    end
    if not ok then return false, tostring(err) end
    return true
end

function Host.setValue(id, value)
    local game = Host.game
    if not game then return false, "no company (/tim start)" end
    if not Host.running then return false, "the company stopped: " .. tostring(Host.halted) .. " (/tim status)" end
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
