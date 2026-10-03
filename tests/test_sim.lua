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
    next = next, select = select,
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
fails("beyond the ported fdlibm", JSMath.sin, 2e6)
assert(JSMath.sin(1e6) == -0.34999350217129294)
assert(JSMath.log10(11) == 1.041392685158225 and JSMath.log10(40) == 1.6020599913279625)
assert(JSMath.log10(1000) == 3 and JSMath.log10(1) == 0 and JSMath.log10(0) == -math.huge)
assert(same(JSMath.log10(-1), 0 / 0))

-- Scheduler: due time then queue order, nested registration, shared cancellation,
-- requeue after the callback and the runaway guard.
local log, seen = {}, {}
local clock = Scheduler.new(log)
local interval
interval = clock:register(function()
    seen[#seen + 1] = "interval@" .. clock.now
    if clock.now == 20 then clock:clear(interval) end
end, 10, true)
clock:register(function()
    seen[#seen + 1] = "first@" .. clock.now
    clock:register(function() seen[#seen + 1] = "nested@" .. clock.now end, 0, false)
end, 10, false)
local cancelled = clock:register(function() seen[#seen + 1] = "cancelled" end, 10, false)
clock:clear(cancelled)
clock:register(function() seen[#seen + 1] = "second@" .. clock.now end, 10, false)
clock:advanceTo(30)
assert(table.concat(seen, ",") == "interval@10,first@10,second@10,nested@10,interval@20", table.concat(seen, ","))
assert(next(clock.pending) == nil)
assert(log[1].action == "register" and log[1]["repeat"] == true and log[1].due == 10)
fails("forward", clock.advanceTo, clock, 29)
clock:register(function() end, 0, true)
fails("budget", clock.advanceTo, clock, 31, nil, 4)

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
fails("Unported reference path: control btnMakeFactory", game.click, game, "btnMakeFactory")

-- addProc refuses to cross the verified processor count before changing state.
game.S.processors, game.S.trust = Workshop.VERIFIED_PROCESSORS, 10000
local speed = game.S.creativitySpeed
fails("verified processor count %(issue #24%)", game.addProc, game)
assert(game.S.processors == Workshop.VERIFIED_PROCESSORS and game.S.creativitySpeed == speed)
print("simulation: JavaScript numbers, scheduler, purity and workshop smoke passed")
