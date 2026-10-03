-- Developer probe: lua lua_pow_probe.lua <pairs.txt> <results.txt>
-- Each input line holds two operands as exact "mantissa:exponent" pairs (or tokens
-- for NaN, infinities and negative zero); each output line is JSMath.pow of them,
-- written the same way.
local here = arg[0]:match("^(.*)[/\\]") or "."
local JSMath = assert(loadfile(here .. "/../../Sim/JSMath.lua"))("TimeIsMoney", {})
local tokens = { NaN = 0 / 0, Infinity = math.huge, ["-Infinity"] = -math.huge, ["-0"] = JSMath.NEG_ZERO }
local function read(s)
    if tokens[s] then return tokens[s] end
    local mantissa, exponent = s:match("^(%-?%d+):(%-?%d+)$")
    return math.ldexp(assert(tonumber(mantissa), s), assert(tonumber(exponent), s))
end
local function write(v)
    if v ~= v then return "NaN" end
    if v == math.huge then return "Infinity" end
    if v == -math.huge then return "-Infinity" end
    if v == 0 then return 1 / v < 0 and "-0" or "0:0" end
    local sign = v < 0 and "-" or ""
    local m, e = math.frexp(v < 0 and -v or v)
    m, e = m * 2 ^ 53, e - 53 -- exact integer mantissa below 2^53
    if e < -1074 then m, e = m / 2 ^ (-1074 - e), -1074 end
    return sign .. string.format("%.0f", m) .. ":" .. e
end
local out = assert(io.open(arg[2], "wb"))
for line in io.lines(arg[1]) do
    local a, b = line:match("^(%S+) (%S+)$")
    out:write(write(JSMath.pow(read(a), read(b))), "\n")
end
out:close()
