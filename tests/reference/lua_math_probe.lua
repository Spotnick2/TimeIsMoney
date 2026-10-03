-- Developer probe: lua lua_math_probe.lua <cases.txt> <results.txt>
-- Each input line is "pow x y", "sin x", "log10 x", "toString x" or
-- "formatWithCommas x [decimal]" with operands as exact
-- "mantissa:exponent" pairs (or tokens for NaN, infinities and negative zero);
-- each output line is the JSMath result, written the same way.
local here = arg[0]:match("^(.*)[/\\]") or "."
local ns = {}
assert(loadfile(here .. "/../../Sim/Reference.lua"))("TimeIsMoney", ns)
for _, path in ipairs(ns.Reference.files) do assert(loadfile(here .. "/../../" .. path))("TimeIsMoney", ns) end
local JSMath, Workshop = ns.JSMath, ns.Workshop
local tokens = { NaN = 0 / 0, Infinity = math.huge, ["-Infinity"] = -math.huge, ["-0"] = JSMath.NEG_ZERO }
local function read(s)
    if tokens[s] then return tokens[s] end
    local mantissa, exponent = s:match("^(%-?%d+):(%-?%d+)$")
    return math.ldexp(assert(tonumber(mantissa), s), assert(tonumber(exponent), s))
end
local function write(v)
    if type(v) == "string" then return v end -- "=text" results of toString
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
    local name, a, b = line:match("^(%a+%d*) (%S+) ?(%S*)$")
    local result
    if name == "pow" then
        result = JSMath.pow(read(a), read(b))
    elseif name == "sin" then
        result = JSMath.sin(read(a))
    elseif name == "log10" then
        result = JSMath.log10(read(a))
    elseif name == "toString" then
        result = "=" .. JSMath.toString(read(a))
    elseif name == "formatWithCommas" then
        result = "=" .. Workshop.formatWithCommas(read(a), b ~= "" and tonumber(b) or nil)
    else
        error("Unknown function: " .. tostring(name))
    end
    out:write(write(result), "\n")
end
out:close()
