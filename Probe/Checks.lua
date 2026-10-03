-- TimeIsMoneyProbe pure checks (issue #9). No WoW API: the same file runs in the
-- client and in offline Lua 5.1, so in-game results can be compared with offline
-- ones. Developer-only; not part of the TimeIsMoney addon or its package.
local _, ns = ...
ns = ns or {}

local Checks = {}
local floor = math.floor

-- Hex digits by arithmetic: string.format("%x") casts to a C long, which is
-- 32-bit on some runtimes.
local HEX = "0123456789abcdef"
local function hex(value, width)
    local out = {}
    for i = width, 1, -1 do
        local digit = value % 16
        out[i] = HEX:sub(digit + 1, digit + 1)
        value = floor(value / 16)
    end
    return table.concat(out)
end

-- FNV-1a (32-bit) with exact double arithmetic: the byte XOR touches only the low
-- 8 bits, and multiplying by 16777619 = 2^24 + 403 stays below 2^53.
local function xor8(a, b)
    local result, bit = 0, 1
    for _ = 1, 8 do
        if (a % 2) ~= (b % 2) then result = result + bit end
        a, b, bit = floor(a / 2), floor(b / 2), bit * 2
    end
    return result
end
function Checks.fnv1a(text)
    local h = 2166136261
    for i = 1, #text do
        local low = h % 256
        h = h - low + xor8(low, text:byte(i))
        h = ((h % 256) * 16777216 + h * 403) % 4294967296
    end
    return hex(h, 8)
end

-- Exact text for a value: numbers as their IEEE words, tables with sorted keys.
local function serialize(value, JSMath, out)
    local t = type(value)
    if value == JSMath.undefined then
        out[#out + 1] = "u"
    elseif t == "number" then
        local hi, lo = JSMath.toWords(value)
        if hi < 0 then hi = hi + 2 ^ 32 end
        out[#out + 1] = "n" .. hex(hi, 8) .. hex(lo, 8)
    elseif t == "string" then
        out[#out + 1] = "s" .. #value .. ":" .. value
    elseif t == "boolean" then
        out[#out + 1] = value and "t" or "f"
    elseif t == "table" then
        local keys = {}
        for k in pairs(value) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == "number"
        end)
        out[#out + 1] = "{"
        for _, k in ipairs(keys) do
            serialize(k, JSMath, out)
            out[#out + 1] = "="
            serialize(value[k], JSMath, out)
            out[#out + 1] = ";"
        end
        out[#out + 1] = "}"
    else
        error("Cannot serialize " .. t)
    end
end
function Checks.serialize(value, JSMath)
    local out = {}
    serialize(value, JSMath, out)
    return table.concat(out)
end

-- Runtime facts the simulation relies on. Each check is {name, ok, observed};
-- every probe runs under pcall so one host error cannot hide the rest.
function Checks.environment(JSMath)
    local W = JSMath.fromWords
    local results = {}
    local zero = tonumber("0")
    local function check(name, probe)
        local ran, ok, observed = pcall(probe)
        if not ran then ok, observed = false, "error: " .. tostring(ok) end
        results[#results + 1] = { name = name, ok = ok and true or false, observed = tostring(observed or "") }
    end
    local function measure(name, probe) -- informational: records the outcome either way
        local ran, value = pcall(probe)
        results[#results + 1] = { name = name .. " (informational)", ok = true,
            observed = ran and ("value " .. tostring(value)) or ("error: " .. tostring(value)) }
    end
    check("Lua version", function() return _VERSION == "Lua 5.1", _VERSION end)
    check("doubles: 2^53 + 1 rounds to 2^53", function() return 2 ^ 53 + 1 == 2 ^ 53, "" end)
    check("NaN from infinity minus infinity", function() return JSMath.isNaN(JSMath.NAN), tostring(JSMath.NAN) end)
    check("signed zero is observable", function() return JSMath.signedZeroTest ~= nil, JSMath.signedZeroTest end)
    check("JS division by zero", function()
        return JSMath.div(1, zero) == math.huge and JSMath.div(-1, zero) == -math.huge
            and JSMath.div(1, JSMath.NEG_ZERO) == -math.huge and JSMath.isNaN(JSMath.div(zero, zero)), ""
    end)
    check("math.frexp/ldexp/fmod exist", function()
        return type(math.frexp) == "function" and type(math.ldexp) == "function" and type(math.fmod) == "function", ""
    end)
    check("math.floor keeps 2^60", function() return math.floor(2 ^ 60) == 2 ^ 60, "" end)
    check("frexp/ldexp round-trip a subnormal", function() return math.ldexp(math.frexp(W(0, 1))) == W(0, 1), "" end)
    -- Decimal parsing: the halfway case an older C runtime misrounded.
    check("tonumber halfway case", function()
        local v = tonumber("20614348053932190")
        return v == W(0x43524F28, 0xFB41FA28), string.format("%.17g", v)
    end)
    check("tonumber 0.5400000000000001", function()
        local v = tonumber("0.5400000000000001")
        return v == W(0x3FE147AE, 0x147AE149), string.format("%.17g", v)
    end)
    -- What the host refuses or returns; the simulation avoids these.
    measure("1 / 0", function() return 1 / zero end)
    measure("0 / 0", function() return zero / zero end)
    measure("5 % 0", function() return 5 % zero end)
    measure("math.fmod(5, 0)", function() return math.fmod(5, zero) end)
    measure("tostring(-0)", function() return tostring(JSMath.NEG_ZERO) end)
    measure("math.atan2(-0, -1)", function() return math.atan2(JSMath.NEG_ZERO, -1) end)
    measure("string.format %d of 2^31", function() return string.format("%d", 2 ^ 31) end)
    measure("bit library", function() return type(bit) end)
    return results
end

-- NaN and infinity behavior of the host (WoW's Lua rejects some NaN arithmetic).
-- Every operation is recorded as its value or its error.
function Checks.nan()
    local zero, inf = tonumber("0"), math.huge
    local results = {}
    local function measure(name, probe)
        local ran, value = pcall(probe)
        results[#results + 1] = name .. " -> " .. (ran and tostring(value) or ("error: " .. tostring(value)))
    end
    local n = inf - inf
    if not (n ~= n or (n == 0 and n == 1)) then
        results[1] = "inf - inf did not produce NaN (" .. tostring(n) .. "); NaN rows skipped"
        return results
    end
    measure("inf - inf", function() return inf - inf end)
    measure("0 * inf", function() return zero * inf end)
    measure("math.fmod(5, 0)", function() return math.fmod(5, zero) end)
    measure("math.sqrt(-1)", function() return math.sqrt(-1) end)
    measure("nan == nan", function() return n == n end)
    measure("nan ~= nan", function() return n ~= n end)
    measure("nan < 1", function() return n < 1 end)
    measure("nan > 1", function() return n > 1 end)
    measure("nan <= 1", function() return n <= 1 end)
    measure("nan >= 1", function() return n >= 1 end)
    measure("1 < nan", function() return 1 < n end)
    measure("nan == 1", function() return n == 1 end)
    measure("nan + 1", function() return n + 1 end)
    measure("nan - 1", function() return n - 1 end)
    measure("nan * 2", function() return n * 2 end)
    measure("-nan", function() return -n end)
    measure("nan / 2", function() return n / 2 end)
    measure("2 / nan", function() return 2 / n end)
    measure("nan % 2", function() return n % 2 end)
    measure("2 % nan", function() return 2 % n end)
    measure("nan ^ 2", function() return n ^ 2 end)
    measure("math.floor(nan)", function() return math.floor(n) end)
    measure("math.ceil(nan)", function() return math.ceil(n) end)
    measure("math.abs(nan)", function() return math.abs(n) end)
    measure("math.max(nan, 1)", function() return math.max(n, 1) end)
    measure("math.frexp(nan)", function() return (math.frexp(n)) end)
    measure("string.format %.17g nan", function() return string.format("%.17g", n) end)
    measure("table key nan", function() local t = {} t[n] = 1 return "stored" end)
    measure("inf / 2", function() return inf / 2 end)
    measure("2 / inf", function() return 2 / inf end)
    measure("inf * 0 == inf * 0", function() return inf * zero == inf * zero end)
    measure("inf % 2", function() return inf % 2 end)
    measure("math.floor(inf)", function() return math.floor(inf) end)
    return results
end

-- Vectors: {fn, x, y, expected} with numbers as {hi, lo} words and toString
-- results as text. Returns counts per function and the first mismatches.
function Checks.math(vectors, JSMath)
    local W = JSMath.fromWords
    local counts, failures = {}, {}
    for _, v in ipairs(vectors) do
        local name = v[1]
        local x = W(v[2][1], v[2][2])
        local got
        if name == "pow" then
            got = JSMath.pow(x, W(v[3][1], v[3][2]))
        elseif name == "sin" then
            got = JSMath.sin(x)
        elseif name == "log10" then
            got = JSMath.log10(x)
        elseif name == "toString" then
            got = JSMath.toString(x)
        end
        local expected = v[4]
        local ok
        if type(expected) == "string" then
            ok = got == expected
        else
            local hi, lo = JSMath.toWords(got)
            local ehi = expected[1] >= 2 ^ 31 and expected[1] - 2 ^ 32 or expected[1]
            ok = hi == ehi and lo == expected[2]
        end
        counts[name] = counts[name] or { 0, 0 }
        counts[name][1] = counts[name][1] + 1
        if not ok then
            counts[name][2] = counts[name][2] + 1
            if #failures < 5 then failures[#failures + 1] = name .. "(" .. tostring(x) .. ") = " .. tostring(got) end
        end
    end
    return counts, failures
end

-- The overall digest plus one digest per state field (to locate a difference).
local function digest(game, draws, JSMath)
    local snapshot, fields = {}, {}
    for k, v in pairs(game.S) do
        if k ~= "grid" then
            snapshot[k] = v
            fields[k] = Checks.fnv1a(Checks.serialize(v, JSMath))
        end
    end
    fields["(readouts)"] = Checks.fnv1a(Checks.serialize(game.readouts, JSMath))
    fields["(timers)"] = Checks.fnv1a(Checks.serialize(game.clock:describe(), JSMath))
    return Checks.fnv1a(Checks.serialize({
        state = snapshot, readouts = game.readouts, timers = game.clock:describe(), draws = draws,
    }, JSMath)), fields
end

local function golden(JSMath)
    local PHI = JSMath.fromWords(0x3FE3C6EF, 0x372FE950) -- 0.6180339887498949
    local random = { count = 0 }
    function random:draw()
        self.count = self.count + 1
        return (self.count * PHI) % 1
    end
    return random
end

-- A zero price: demand becomes NaN (Infinity + Infinity * 0), so the sale roll and
-- revenue comparisons take JavaScript's NaN paths.
function Checks.workshopPriceFloor(ns)
    local random = golden(ns.JSMath)
    local game = ns.Workshop.new(random, {})
    game.S.margin, game.S.unsoldClips = .02, 400
    game:click("btnLowerPrice")
    game:click("btnLowerPrice")
    game:advanceTo(1500)
    local overall, fields = digest(game, random.count, ns.JSMath)
    return overall, random.count, fields
end

-- Runs the workshop simulation through a fixed plan and digests its final state.
function Checks.workshop(ns)
    local JSMath, Workshop = ns.JSMath, ns.Workshop
    local random = golden(JSMath)
    local game = Workshop.new(random, {})
    local S = game.S
    S.compFlag, S.memory, S.standardOps, S.processors, S.trust = 1, 50, 50000, 29, 100
    S.creativityOn, S.qFlag, S.qClock, S.funds = 1, 1, 60, 10000000
    S.investmentEngineFlag, S.strategyEngineFlag = 1, 1
    for i = 1, 5 do S.qChips[i].active = 1 end
    for _, id in ipairs({ "btnMakePaperclip", "btnMakeClipper", "btnAddProc", "btnInvest", "btnQcompute" }) do
        game:click(id)
    end
    game:advanceTo(50)
    game:click("btnQcompute")
    game:click("projectButton1")
    game:advanceTo(2500)
    local overall, fields = digest(game, random.count, JSMath)
    return overall, random.count, S.ticks, fields
end

ns.Checks = Checks
return Checks
