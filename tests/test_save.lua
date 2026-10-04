-- Saved games (#19): a restored game continues exactly like an uninterrupted one.
local ns = {}
local function load(path) assert(loadfile(path))("TimeIsMoney", ns) end
load("Sim/Reference.lua")
for _, path in ipairs(ns.Reference.files) do load(path) end
local JSMath, Workshop, Save = ns.JSMath, ns.Workshop, ns.Save

-- The host's stream (Host.lua): L'Ecuyer combined MLCG, restorable from its state.
local M1, A1, M2, A2 = 2147483563, 40014, 2147483399, 40692
local function newRandom(s1, s2, count)
    local r = { s1 = s1, s2 = s2, count = count or 0 }
    function r:draw()
        self.s1 = (A1 * self.s1) % M1
        self.s2 = (A2 * self.s2) % M2
        local z = (self.s1 - self.s2) % (M1 - 1)
        if z == 0 then z = M1 - 1 end
        self.count = self.count + 1
        return z / M1
    end
    return r
end

-- A conservative SavedVariables writer: plain tables only, numbers with %.14g, then
-- loaded back as Lua source. Shared references or non-finite numbers would break it.
local function write(v)
    local t = type(v)
    if t == "number" then
        assert(v == v and v ~= math.huge and v ~= -math.huge, "the writer gets only finite numbers")
        return string.format("%.14g", v)
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "table" then
        local parts = {}
        for k, x in pairs(v) do parts[#parts + 1] = "[" .. write(k) .. "]=" .. write(x) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    error("writer cannot store " .. t)
end
local function roundTrip(data)
    return assert(loadstring("return " .. write(data)))()
end

local function equal(a, b, path, seen)
    seen = seen or {}
    if type(a) ~= type(b) then return false, path end
    if type(a) == "function" then return true end
    if type(a) ~= "table" then
        if a ~= a and b ~= b then return true end
        if a == 0 and b == 0 then return (1 / a < 0) == (1 / b < 0), path end
        return a == b, path
    end
    if seen[a] then return true end
    seen[a] = true
    for k, v in pairs(a) do
        if k ~= "grid" then
            local ok, where = equal(v, b[k], path .. "." .. tostring(k), seen)
            if not ok then return false, where end
        end
    end
    for k in pairs(b) do if k ~= "grid" and a[k] == nil then return false, path .. "." .. tostring(k) end end
    return true
end

-- Runs a scenario twice: uninterrupted, and saved at `at` then restored; both then
-- run the same commands to `finish` and must agree everywhere.
local function continuation(name, setup, at, finish, commands)
    local function fresh()
        local random = newRandom(97531, 86420)
        local game = Workshop.new(random, false)
        setup(game, game.S)
        return game, random
    end
    local function play(game, from, to)
        for _, c in ipairs(commands) do
            if c.at > from and c.at <= to then
                game:advanceTo(c.at)
                if c.click then pcall(game.click, game, c.click) else game:setValue(c.id, c.value) end
            end
        end
        game:advanceTo(to)
    end
    local a, ra = fresh()
    play(a, 0, finish)
    local b, rb = fresh()
    play(b, 0, at)
    local saved = roundTrip(Save.encode(b, rb))
    local rc = newRandom(saved.random.s1, saved.random.s2, saved.random.count)
    local c = Save.decode(saved, rc, false)
    assert(c.clock.now == at, name .. ": restored clock")
    play(c, at, finish)
    local ok, where = equal(a.S, c.S, "S")
    assert(ok, name .. ": state differs at " .. tostring(where))
    assert(ra.count == rc.count, name .. ": draws " .. ra.count .. " vs " .. rc.count)
    assert(equal(a.readouts, c.readouts, "readouts"), name .. ": readouts")
    assert(equal(a.disabled, c.disabled, "disabled"), name .. ": controls")
    assert(equal(a.projectElements, c.projectElements, "elements"), name .. ": project buttons")
    assert(equal(a.clock:describe(), c.clock:describe(), "timers"), name .. ": timers")
    return a, c
end

local function set(values) return function(_, S) for k, v in pairs(values) do S[k] = v end end end

-- Phase one: production, sales, revenue NaN seconds, projects shown with blinks.
continuation("workshop", set({ compFlag = 1, projectsFlag = 1, memory = 60, standardOps = 60000,
    clipmakerLevel = 30, funds = 200, margin = .05, unsoldClips = 300 }), 1234, 4000, {
    { at = 500, click = "btnMakeClipper" }, { at = 1300, click = "projectButton1" }, { at = 2600, click = "btnBuyWire" } })

-- A tournament saved between its chained timeouts.
local a = continuation("tournament", function(game, S)
    S.compFlag, S.strategyEngineFlag, S.memory, S.standardOps = 1, 1, 20, 15000
    game:setValue("stratPicker", "0")
end, 175, 4600, { { at = 20, click = "btnNewTournament" }, { at = 30, click = "btnRunTournament" } })
assert(a.S.resultsFlag == 1 or a.S.currentRound > 1, "the tournament progressed")

-- Investments: stocks held across the save.
continuation("investments", set({ funds = 20000, investmentEngineFlag = 1, sellDelay = 4 }), 2777, 6000,
    { { at = 1, click = "btnInvest" } })

-- Phase two: the swarm with the slider's string, power and matter.
continuation("planet", set({ humanFlag = 0, harvesterLevel = 150, wireDroneLevel = 150, farmLevel = 10,
    swarmFlag = 1, batteryLevel = 3, storedPower = 5, compFlag = 1, memory = 200, standardOps = 200000 }), 640, 2000,
    { { at = 100, id = "slider", value = "150" }, { at = 1500, click = "btnHarvesterx10" } })

-- The cosmic phase with a battle in progress (fractional probe counts, battle state).
continuation("battle", set({ humanFlag = 0, spaceFlag = 1, availableMatter = 0, farmLevel = 1, powMod = 1,
    milestoneFlag = 14, probeCount = 3e8, probeTrust = 30, maxTrust = 30, drifterCount = 9e8, probeCombat = 4,
    probeHaz = 8 }), 1555, 3500, {})

-- The ending: dismantling timers, final clips and the credits.
continuation("ending", set({ humanFlag = 0, spaceFlag = 1, availableMatter = 0, farmLevel = 1, powMod = 1,
    milestoneFlag = 15, dismantle = 5, endTimer4 = 140, endTimer6 = 880, wire = 12, compFlag = 1, memory = 200,
    standardOps = 200000, processors = 600000 }), 333, 1500,
    { { at = 400, click = "btnMakePaperclip" }, { at = 420, click = "btnMakePaperclip" } })

-- Exact numbers: NaN, infinities, -0, undefined and huge values survive the writer.
do
    local game = Workshop.new(newRandom(1, 2), false)
    local S = game.S
    S.nanValue, S.infValue, S.negZero, S.huge, S.tiny = JSMath.NAN, -math.huge, JSMath.NEG_ZERO, 3e55, 5e-324
    S.bigInt = 2 ^ 52 + 1
    local c = Save.decode(roundTrip(Save.encode(game, nil)), newRandom(1, 2), false)
    assert(JSMath.isNaN(c.S.nanValue) and c.S.infValue == -math.huge and 1 / c.S.negZero < 0)
    assert(c.S.huge == 3e55 and c.S.tiny == 5e-324 and c.S.bigInt == 2 ^ 52 + 1)
    assert(c.S.incomeThen == JSMath.undefined, "undefined survives")
    assert(c.S.strats[1] == c.S.allStrats[1], "shared references survive")
end

-- Automatic tournaments continue after a restore with results shown (the results
-- table display state lives outside S; Codex consult on #19).
local tourney = continuation("autoTourney", function(game, S)
    S.compFlag, S.strategyEngineFlag, S.memory, S.standardOps, S.autoTourneyFlag = 1, 1, 20, 15000, 1
    game:setValue("stratPicker", "0")
end, 2000, 5000, { { at = 20, click = "btnNewTournament" }, { at = 30, click = "btnRunTournament" } })
-- Saved mid-countdown (results shown); by the end the next tournament has started.
assert(tourney.S.tourneyInProg == 1 and tourney.resultsTableDisplay == "none", "the next automatic tournament")

-- Damaged timer lists are refused, not shortened.
do
    local game = Workshop.new(newRandom(3, 4), false)
    local saved = Save.encode(game, nil)
    saved.clock.timers[1] = nil
    local ok, err = pcall(Save.decode, saved, newRandom(3, 4), false)
    assert(not ok and err:find("not a dense list", 1, true), tostring(err))
    saved = Save.encode(game, nil)
    table.remove(saved.clock.timers, 1)
    ok, err = pcall(Save.decode, saved, newRandom(3, 4), false)
    assert(not ok and err:find("Malformed save", 1, true), tostring(err))
end

-- Damaged parts are refused, never filled in (review of #55).
do
    local game = Workshop.new(newRandom(5, 6), false)
    local function refused(damage, why)
        local saved = roundTrip(Save.encode(game, nil))
        damage(saved)
        local ok, err = pcall(Save.decode, saved, newRandom(5, 6), false)
        assert(not ok and tostring(err):find(why, 1, true), why .. ": " .. tostring(err))
    end
    refused(function(d) d.controls.selects.stratPicker = nil end, "select stratPicker")
    refused(function(d) d.controls.disabled.btnMakePaperclip = nil end, "control btnMakePaperclip")
    refused(function(d) d.controls.ranges.slider = "0x10" end, "range slider")
    refused(function(d)
        for _, t in ipairs(d.clock.timers) do if t.kind == "main" then t.delay = 1000 end end
    end, "cadence of main")
    refused(function(d)
        for _, t in ipairs(d.clock.timers) do if t.kind == "main" then t.delay = 0 end end
    end, "entry values")
end

-- Malformed saves are refused without partial results.
for _, bad in ipairs({ "text", {}, { schema = 2 }, { schema = 1, nodes = {}, root = 1, clock = {}, controls = {} },
    { schema = 1, nodes = { [1] = { x = { r = 9 } } }, root = 1, clock = { now = 0, nextId = 1, order = 0, timers = {} },
        controls = {} } }) do
    local ok, err = pcall(Save.decode, bad, newRandom(1, 1), false)
    assert(not ok and tostring(err):find("Malformed save", 1, true), tostring(err))
end

print("save: continuation (workshop, tournament, investments, planet, battle, ending), exact numbers and malformed saves passed")
