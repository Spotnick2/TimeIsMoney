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

-- Runtime facts the simulation relies on. Each check is {name, ok, observed}.
function Checks.environment(JSMath)
    local W = JSMath.fromWords
    local results = {}
    local function check(name, ok, observed) results[#results + 1] = { name = name, ok = ok, observed = observed } end
    local zero = tonumber("0")
    check("Lua version", _VERSION == "Lua 5.1", tostring(_VERSION))
    check("doubles: 2^53 + 1 rounds to 2^53", 2 ^ 53 + 1 == 2 ^ 53, tostring(2 ^ 53 + 1 == 2 ^ 53))
    check("negative zero survives", 1 / (-zero) == -math.huge, tostring(1 / (-zero)))
    check("NaN is unequal to itself", (zero / zero) ~= (zero / zero), "")
    check("math.frexp/ldexp/fmod exist", type(math.frexp) == "function" and type(math.ldexp) == "function"
        and type(math.fmod) == "function", "")
    check("math.floor keeps 2^60", math.floor(2 ^ 60) == 2 ^ 60, "")
    check("frexp/ldexp round-trip a subnormal", math.ldexp(math.frexp(W(0, 1))) == W(0, 1), "")
    -- Decimal parsing: the halfway case an older C runtime misrounded.
    check("tonumber halfway case", tonumber("20614348053932190") == W(0x43524F28, 0xFB41FA28),
        string.format("%.17g", tonumber("20614348053932190")))
    check("tonumber 0.5400000000000001", tonumber("0.5400000000000001") == W(0x3FE147AE, 0x147AE149),
        string.format("%.17g", tonumber("0.5400000000000001")))
    -- Informational: C long width and the bit library, which the simulation avoids.
    check("string.format %d of 2^31 (informational)", true, string.format("%d", 2 ^ 31))
    check("bit library (informational)", true, type(bit))
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

-- Runs the workshop simulation through a fixed plan and digests its final state.
function Checks.workshop(ns)
    local JSMath, Workshop = ns.JSMath, ns.Workshop
    local PHI = JSMath.fromWords(0x3FE3C6EF, 0x372FE950) -- 0.6180339887498949
    local draws = 0
    local random = { draw = function()
        draws = draws + 1
        return (draws * PHI) % 1
    end }
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
    local snapshot = {}
    for k, v in pairs(S) do if k ~= "grid" then snapshot[k] = v end end
    local digest = Checks.fnv1a(Checks.serialize({
        state = snapshot, readouts = game.readouts, timers = game.clock:describe(), draws = draws,
    }, JSMath))
    return digest, draws, S.ticks
end

ns.Checks = Checks
return Checks
