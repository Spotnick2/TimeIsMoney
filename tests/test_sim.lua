-- Pure-Lua simulation units: JavaScript number semantics, logical scheduling and
-- the absence of WoW, clock, I/O or native-random dependencies.
local function fails(pattern, fn, ...)
    local ok, message = pcall(fn, ...)
    assert(not ok and tostring(message):find(pattern), tostring(message))
end
local function same(a, b)
    if a ~= a then return b ~= b end
    return a == b and (a ~= 0 or 1 / a == 1 / b)
end

-- Load the simulation into a restricted environment: only pure Lua libraries,
-- no os/io, no math.random, and no reads or writes of other globals.
local allowedMath = {}
for k, v in pairs(math) do
    if k ~= "random" and k ~= "randomseed" then allowedMath[k] = v end
end
local allowed = {
    math = allowedMath, string = string, table = table, pairs = pairs, ipairs = ipairs,
    type = type, tostring = tostring, tonumber = tonumber, error = error, setmetatable = setmetatable,
    next = next, select = select, pcall = pcall,
}
local env = setmetatable({}, {
    __index = function(_, key)
        if allowed[key] == nil then error("simulation read global " .. tostring(key), 2) end
        return allowed[key]
    end,
    __newindex = function(_, key) error("simulation wrote global " .. tostring(key), 2) end,
})
local ns = {}
local function load(path)
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)
    chunk("TimeIsMoney", ns)
end
load("Sim/Reference.lua")
for _, path in ipairs(ns.Reference.files) do load(path) end
for _, path in ipairs(ns.Reference.files) do
    local text = assert(io.open(path, "rb")):read("*a")
    for _, banned in ipairs({ "math%.random", "[^%w_]os%.", "[^%w_]io%.", "CreateFrame", "GetTime", "[^%w_]_G[^%w_]", "C_Timer" }) do
        assert(not text:find(banned), path .. " uses " .. banned)
    end
end
local JSMath, Scheduler, Workshop = ns.JSMath, ns.Scheduler, ns.Workshop
local NEG_ZERO = -tonumber("0")
assert(1 / NEG_ZERO < 0 and 1 / JSMath.NEG_ZERO < 0)

-- Math.round ties toward +infinity and keeps -0.
assert(JSMath.round(2.5) == 3 and JSMath.round(-2.5) == -2 and JSMath.round(1.4999999999999998) == 1)
assert(same(JSMath.round(-0.4), NEG_ZERO) and same(JSMath.round(-0.5), NEG_ZERO) and same(JSMath.round(0.4), 0))
assert(JSMath.round(0.49999999999999994) == 0, "no x + 0.5 double rounding")
assert(same(JSMath.round(0 / 0), 0 / 0) and JSMath.round(math.huge) == math.huge)
assert(JSMath.mod(-5, 3) == -2 and JSMath.mod(5.5, 2) == 1.5, "JavaScript % truncates")
assert(same(JSMath.num(JSMath.undefined), 0 / 0) and JSMath.num(3) == 3)

-- JavaScript division without dividing by zero (WoW's Lua raises on x/0).
assert(JSMath.div(1, 0) == math.huge and JSMath.div(-3, 0) == -math.huge and JSMath.div(1, NEG_ZERO) == -math.huge)
assert(JSMath.div(-1, NEG_ZERO) == math.huge and same(JSMath.div(0, 0), 0 / 0) and same(JSMath.div(0 / 0, 0), 0 / 0))
assert(JSMath.div(6, 3) == 2 and JSMath.NAN ~= JSMath.NAN and JSMath.signedZeroTest ~= nil)
assert(JSMath.isNegativeZero(NEG_ZERO) and not JSMath.isNegativeZero(0) and not JSMath.isNegativeZero(-1))

-- Math.pow: V8 results for reference-style operands, and ECMAScript special values.
assert(JSMath.pow(1.1, 32) == 21.113776745352606)
assert(JSMath.pow(1.07, 9) == 1.8384592124201555 and JSMath.pow(1.07, 10) == 1.9671513572895665)
assert(JSMath.pow(1.1, -4) == 0.68301345536507052)
assert(JSMath.pow(158.31127762794495, 1.15) == 338.4064498674108)
assert(JSMath.pow(1.1, 0) == 1 and JSMath.pow(2, 10) == 1024 and JSMath.pow(-2, 3) == -8)
assert(same(JSMath.pow(0 / 0, 0), 1) and same(JSMath.pow(1, math.huge), 0 / 0) and same(JSMath.pow(-1, -math.huge), 0 / 0))
assert(same(JSMath.pow(-8, 1 / 3), 0 / 0) and same(JSMath.pow(2, 0 / 0), 0 / 0))
assert(same(JSMath.pow(NEG_ZERO, -1), -math.huge) and same(JSMath.pow(0, -1), math.huge) and same(JSMath.pow(NEG_ZERO, 3), NEG_ZERO))
assert(same(JSMath.pow(-math.huge, 3), -math.huge) and same(JSMath.pow(-math.huge, -3), NEG_ZERO))
assert(same(JSMath.pow(math.huge, 1.15), math.huge) and JSMath.pow(0.5, math.huge) == 0)
assert(JSMath.pow(10, 400) == math.huge and JSMath.pow(10, -400) == 0)

-- fdlibm Math.sin and Math.log10: V8 values, including the variant-sensitive
-- cases where the C library and other fdlibm variants differ.
assert(JSMath.sin(1) == 0.8414709848078965 and JSMath.sin(0.7360000000000005) == 0.6713286509741181)
assert(JSMath.sin(0.8280000000000005) == 0.7365801446274045 and same(JSMath.sin(NEG_ZERO), NEG_ZERO))
assert(same(JSMath.sin(math.huge), 0 / 0) and JSMath.sin(-3) == -0.1411200080598672)
-- Beyond 2^20 * pi/2, __kernel_rem_pio2 (#24); exact V8 values.
assert(JSMath.sin(2e6) == -0.65571431556347004 and JSMath.sin(1e22) == -0.85220084976718879)
-- The large-argument reduction allocates nothing (the quantum chips call it every tick).
JSMath.sin(3e6)
collectgarbage("stop")
local before = collectgarbage("count")
for i = 1, 200 do JSMath.sin(2e6 + i * 0.37) end
assert(collectgarbage("count") == before, "no allocation per call")
collectgarbage("restart")
assert(JSMath.sin(1e6) == -0.34999350217129294)
assert(JSMath.log10(11) == 1.041392685158225 and JSMath.log10(40) == 1.6020599913279625)
assert(JSMath.log10(1000) == 3 and JSMath.log10(1) == 0 and JSMath.log10(0) == -math.huge)
assert(same(JSMath.log10(-1), 0 / 0))

-- ToNumber for strings (select values): JavaScript grammar, not C strtod.
local toNumber = JSMath.toNumber
assert(toNumber("") == 0 and toNumber("  12  ") == 12 and toNumber("1e3") == 1000 and toNumber(".5") == .5)
assert(toNumber("5.") == 5 and toNumber("0x10") == 16 and toNumber("0b101") == 5 and toNumber("0o17") == 15)
assert(toNumber("Infinity") == math.huge and toNumber("-Infinity") == -math.huge and toNumber("-12.5") == -12.5)
for _, text in ipairs({ "inf", "infinity", "-0x10", "0x1p4", "abc", "1e", "1.2.3", "0x", "nan" }) do
    assert(same(toNumber(text), 0 / 0), "toNumber(" .. text .. ") should be NaN")
end

-- Scheduler: due time then queue order, nested registration, shared cancellation,
-- requeue after the callback and the runaway guard.
local log, seen = {}, {}
local clock = Scheduler.new(log)
local interval
interval = clock:register(function()
    seen[#seen + 1] = "interval@" .. clock.now
    if clock.now == 20 then clock:clear(interval) end
end, 10, true, "test")
clock:register(function()
    seen[#seen + 1] = "first@" .. clock.now
    clock:register(function() seen[#seen + 1] = "nested@" .. clock.now end, 0, false, "test")
end, 10, false, "test")
local cancelled = clock:register(function() seen[#seen + 1] = "cancelled" end, 10, false, "test")
clock:clear(cancelled)
clock:register(function() seen[#seen + 1] = "second@" .. clock.now end, 10, false, "test")
clock:advanceTo(30)
assert(table.concat(seen, ",") == "interval@10,first@10,second@10,nested@10,interval@20", table.concat(seen, ","))
assert(next(clock.pending) == nil)
assert(log[1].action == "register" and log[1]["repeat"] == true and log[1].due == 10)
fails("forward", clock.advanceTo, clock, 29)
clock:register(function() end, 0, true, "test")
fails("budget", clock.advanceTo, clock, 31, nil, 4)
-- A timer without a kind could not be saved (#19): refused where it is made.
fails("Every timer needs a kind", clock.register, clock, function() end, 10, false)

-- The restricted simulation runs the workshop and battle with a stub stream.
local draws = 0
local stub = { draw = function(_, site)
    assert(type(site) == "string" and site:find("^%a+%.js:%d+:%d+$"), site)
    draws = draws + 1
    return (draws * 0.6180339887498949) % 1
end }
local game = Workshop.new(stub, {})
assert(draws == 3200, "both initialization ship resets")
assert(#game.clock:describe() == 7)
game:click("btnMakePaperclip")
game:advanceTo(2000)
assert(game.S.clips == 1 and game.S.ticks == 200)
fails("Unported reference path: control btnFeedSwarm", game.click, game, "btnFeedSwarm")

-- Planetary costs (#11, #12): the reference profile's pow where JSMath differs; beyond
-- the verified domain, and for fractional bases, the correctly rounded pow (#24).
local costPow = Workshop.costPow
assert(costPow(2969, "2.25") == JSMath.fromWords(0x418F06F8, 0xB0418DE1), "pinned profile value")
assert(costPow(2969, "2.25") ~= JSMath.pow(2969, 2.25), "JSMath alone differs there")
assert(costPow(2, "2.25") == JSMath.pow(2, 2.25))
assert(costPow(200001, "2.25") == JSMath.pow(200001, 2.25) and costPow(2.5, "2.25") == JSMath.pow(2.5, 2.25))
fails("Math%.pow%(NaN, 2%.25%) %(issue #24%)", costPow, 0 / 0, "2.25")
-- Beyond the table the memo keeps two bounded generations (both drone types share it).
for n = 300001, 300001 + 8192 do assert(costPow(n, "2.25") == JSMath.pow(n, 2.25)) end
assert(costPow(300001, "2.25") == JSMath.pow(300001, 2.25), "a turned-over base")
-- Purchases and reboots past the tables go through (no stop where verification ends).
local planet = Workshop.new(stub, {})
planet.S.harvesterLevel, planet.S.unusedClips = 199000, 1e25
planet:makeHarvester(1)
assert(planet.S.harvesterLevel == 199001 and planet.S.harvesterCost == costPow(199002, "2.25") * 1000000, "purchase past the table")
planet.S.farmLevel = 29950
planet:makeFarm(1)
assert(planet.S.farmLevel == 29951)
planet.S.batteryLevel = 29950
planet:batteryReboot()
assert(planet.S.batteryLevel == 0)

-- The cosmic phase (#14): fractional drone levels (probe-built) and probe trust past
-- the table go through too (#24).
local cosmos = Workshop.new(stub, {})
cosmos.S.harvesterLevel, cosmos.S.wireDroneLevel, cosmos.S.unusedClips = 5, 12.34, 1e30
cosmos:makeHarvester(1)
assert(cosmos.S.harvesterLevel == 6)
cosmos.S.probeTrust, cosmos.S.maxTrust, cosmos.S.yomi, cosmos.S.probeTrustCost = 9999, 20000, 1e12, 1
cosmos:increaseProbeTrust()
assert(cosmos.S.probeTrust == 10000 and cosmos.S.probeTrustCost == math.floor(JSMath.pow(10001, 1.47) * 500))

-- Battles (#15): a named victory adds the drifter fleet plus Glory's bonus once;
-- a defeat costs the probe fleet and names the threnody; the result delay ends it.
local war = Workshop.new(stub, {})
local Battle = ns.Battle
war.S.battles = { { id = 1 } }
war.S.project121.flag, war.S.project134.flag = 1, 1
war.S.numRightShips, war.S.battleRIGHTSHIPS, war.S.bonusHonor = 0, 7, 3
Battle.checkForBattleEnd(war.S)
Battle.checkForBattleEnd(war.S)
assert(war.S.honor == 10 and war.S.bonusHonor == 13 and war.S.honorCount == 1 and war.S.battleEndDelay == 2)
war.S.battleEndDelay = war.S.battleEndTimer - 1
Battle.checkForBattleEnd(war.S)
assert(#war.S.battles == 0 and war.S.honorCount == 0 and war.S.battleEndDelay == 0)
war.S.battles, war.S.numRightShips, war.S.numLeftShips, war.S.battleLEFTSHIPS = { { id = 2 } }, 5, 0, 4
war.S.battleName = "Ulm 2"
Battle.checkForBattleEnd(war.S)
assert(war.S.honor == 6 and war.S.bonusHonor == 0 and war.S.threnodyTitle == "Ulm 2")
-- A prestige choice (#17) saves the next game's prestige and requests the restart,
-- which the host performs (#23).
war.S.standardOps, war.S.prestigeU = 400000, 2
Workshop.projectById.projectButton200.effect(war)
assert(war.S.prestigeU == 3 and war.savedPrestige.prestigeU == 3 and war.savedPrestige.prestigeS == 0)
assert(war.restartRequested == "prestige")
assert(war.readouts[1] == "Entering New Universe.")

-- The swarm (#13): with no drones and the slider at 0, a repeating gift is
-- log10(0) * 0 = NaN. It must never reach a native division (WoW's Lua raises), and
-- swarmGifts returns to 0 on the next tick, as in the reference.
local swarm = Workshop.new(stub, {})
swarm.S.humanFlag, swarm.S.swarmFlag, swarm.S.giftCountdown = 0, 1, 0
swarm:updateSwarm()
assert(JSMath.isNaN(swarm.S.nextGift) and JSMath.isNaN(swarm.S.swarmGifts))
swarm:updateSwarm()
assert(swarm.S.swarmGifts ~= swarm.S.swarmGifts or swarm.S.swarmGifts >= 0)
swarm:setValue("slider", "1.25e2")
assert(swarm.ranges.slider.value == "125" and swarm.ranges.slider.number == 125)
swarm:setValue("slider", "0x10")
assert(swarm.ranges.slider.value == "100")

-- addProc continues past the verified processor count (#24), correctly rounded.
game.S.processors, game.S.trust = Workshop.VERIFIED_PROCESSORS, 10000
game:addProc()
local n = Workshop.VERIFIED_PROCESSORS + 1
assert(game.S.processors == n and game.S.creativitySpeed == JSMath.log10(n) * JSMath.pow(n, 1.1) + n - 1)
-- A battle with no ship alive keeps running, as in the reference (NaN centroid unused).
local empty = Workshop.new(stub, {})
for _, ship in ipairs(empty.S.ships) do ship.alive = false end
empty:advanceTo(200)
assert(empty.S.ships[1].framesDead == 10 and empty.S.i == empty.S.numShips)

-- Project purchases: a button must be in the document.
local projects = Workshop.new(stub, {})
local ok, message = pcall(projects.click, projects, "projectButton1")
assert(not ok and message == "Unknown clickable ID", tostring(message))
ok, message = pcall(projects.click, projects, "projectButton18")
assert(not ok and message == "Unknown clickable ID", tostring(message))
-- Quantum Temporal Reversion (the window confirms first): the Operations come
-- back, "Restart", the prestige is kept and the host is asked to reset (#23).
projects.projectElements.projectButton217 = true
projects.S.activeProjects[#projects.S.activeProjects + 1] = projects.S.project217
projects.S.standardOps, projects.S.prestigeU = -10000, 1
projects:click("projectButton217")
assert(projects.S.standardOps == 0 and projects.S.project217.flag == 1 and projects.readouts[1] == "Restart")
assert(projects.restartRequested == "reversion" and projects.savedPrestige == nil,
    "a reversion keeps the account's prestige (the host's), not the company's")
assert(not projects.projectElements.projectButton217)

-- Milestones after the transition: full autonomy, then clip-count milestones.
local later = Workshop.new(stub, {})
later.S.milestoneFlag, later.S.project35.flag, later.S.clips, later.S.ticks = 6, 1, 2e12, 360000
later:milestoneCheck()
assert(later.S.milestoneFlag == 8, tostring(later.S.milestoneFlag))
assert(later.readouts[2] == "Full autonomy attained in 1 hour " and later.readouts[1] == "One Trillion Clips Created in 1 hour ")
assert(JSMath.pow(10, 24) == 1e24 and JSMath.pow(10, 27) == 1e27)

-- Strategic Attachment (#14): the picked strategy winning adds 50,000 Yomi after
-- the score award.
local tourney = Workshop.new(stub, {})
tourney.S.pick, tourney.S.project128.flag, tourney.S.winnerPtr = "0", 1, 0
tourney.S.results = { tourney.S.strats[1] }
local yomiBefore = tourney.S.yomi
tourney:declareWinner()
assert(tourney.S.yomi == yomiBefore + 50000 and tourney.S.resultsFlag == 1)
assert(tourney.readouts[1] == "Selected strategy won the tournament (or tied for first). +50,000 yomi")
print("simulation: JavaScript numbers, scheduler, purity and workshop smoke passed")
