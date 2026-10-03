-- JavaScript number semantics that Lua 5.1 does not provide directly.
-- Pure Lua: no WoW globals, clocks or native randomness.
local _, ns = ...
ns = ns or {}

local floor, ldexp, frexp = math.floor, math.ldexp, math.frexp
local huge = math.huge
-- Built at run time: Lua 5.1 can merge a literal -0.0 with the constant 0.
local NEG_ZERO = -tonumber("0")
local JSMath = {}
JSMath.NEG_ZERO = NEG_ZERO

-- JavaScript's undefined, kept distinct from nil so state tables keep the key.
-- Arithmetic sites convert it explicitly with JSMath.num (undefined -> NaN).
JSMath.undefined = setmetatable({}, { __tostring = function() return "undefined" end })

function JSMath.num(value)
    if value == JSMath.undefined then return 0 / 0 end
    return value
end

-- Math.round: nearest integer, ties toward +infinity, keeping -0 for [-0.5, -0].
function JSMath.round(x)
    if x ~= x or x == huge or x == -huge then return x end
    local r = floor(x)
    if x - r >= 0.5 then r = r + 1 end
    if r == 0 and (x < 0 or 1 / x < 0) then return NEG_ZERO end
    return r
end

-- JavaScript % (truncating remainder, sign of the dividend) is C fmod;
-- Lua 5.1's % floors instead.
JSMath.mod = math.fmod

-- Double-double arithmetic (value = hi + lo), used to compute pow correctly
-- rounded in pure Lua so results do not depend on the host C library.
local SPLIT = 134217729 -- 2^27 + 1

local function twoSum(a, b)
    local s = a + b
    local bb = s - a
    return s, (a - (s - bb)) + (b - bb)
end

local function quickTwoSum(a, b)
    local s = a + b
    return s, b - (s - a)
end

local function split(a)
    local t = SPLIT * a
    local hi = t - (t - a)
    return hi, a - hi
end

local function twoProd(a, b)
    local p = a * b
    local ah, al = split(a)
    local bh, bl = split(b)
    return p, ((ah * bh - p) + ah * bl + al * bh) + al * bl
end

local function ddAdd(ah, al, bh, bl)
    local s, e = twoSum(ah, bh)
    local t, f = twoSum(al, bl)
    e = e + t
    s, e = quickTwoSum(s, e)
    e = e + f
    return quickTwoSum(s, e)
end

local function ddMul(ah, al, bh, bl)
    local p, e = twoProd(ah, bh)
    e = e + (ah * bl + al * bh)
    return quickTwoSum(p, e)
end

local function ddMulD(ah, al, b)
    local p, e = twoProd(ah, b)
    e = e + al * b
    return quickTwoSum(p, e)
end

local function ddDiv(ah, al, bh, bl)
    local q1 = ah / bh
    local ph, pl = ddMulD(bh, bl, q1)
    local rh, rl = ddAdd(ah, al, -ph, -pl)
    local q2 = rh / bh
    ph, pl = ddMulD(bh, bl, q2)
    rh, rl = ddAdd(rh, rl, -ph, -pl)
    local q3 = rh / bh
    q1, q2 = quickTwoSum(q1, q2)
    return ddAdd(q1, q2, q3, 0)
end

local LN2_HI, LN2_LO = 0.6931471805599453, 2.3190468138462996e-17
local SQRT_HALF = 0.70710678118654752

-- log(x) for finite x > 0, as a double-double.
local function ddLog(x)
    local m, e = frexp(x) -- x = m * 2^e, m in [0.5, 1)
    if m < SQRT_HALF then m, e = m * 2, e - 1 end
    -- log(m) = 2 atanh(s), s = (m - 1) / (m + 1), |s| < 0.172. m - 1 is exact
    -- (Sterbenz); m + 1 is not, so keep its rounding error.
    local dh, dl = twoSum(m, 1)
    local sh, sl = ddDiv(m - 1, 0, dh, dl)
    local s2h, s2l = ddMul(sh, sl, sh, sl)
    local th, tl = sh, sl
    local sumh, suml = sh, sl
    for k = 3, 61, 2 do
        th, tl = ddMul(th, tl, s2h, s2l)
        local qh, ql = ddDiv(th, tl, k, 0)
        sumh, suml = ddAdd(sumh, suml, qh, ql)
        if qh == 0 or (qh < 0 and -qh or qh) < 1e-34 then break end
    end
    sumh, suml = sumh * 2, suml * 2
    local eh, el = ddMulD(LN2_HI, LN2_LO, e)
    return ddAdd(eh, el, sumh, suml)
end

-- exp(t) for a double-double t, as (double-double mantissa, power of two).
local function ddExp(th, tl)
    local k = floor(th / LN2_HI + 0.5)
    local kh, kl = ddMulD(LN2_HI, LN2_LO, k)
    local rh, rl = ddAdd(th, tl, -kh, -kl)
    rh, rl = rh / 1024, rl / 1024
    -- Taylor series for exp(r) - 1 with |r| < 3.4e-4.
    local sumh, suml = rh, rl
    local ph, pl = rh, rl
    for n = 2, 14 do
        ph, pl = ddMul(ph, pl, rh, rl)
        ph, pl = ddDiv(ph, pl, n, 0)
        sumh, suml = ddAdd(sumh, suml, ph, pl)
    end
    local eh, el = ddAdd(1, 0, sumh, suml)
    for _ = 1, 10 do eh, el = ddMul(eh, el, eh, el) end
    return eh, el, k
end

local function isInteger(y)
    return y == floor(y) and y ~= huge and y ~= -huge
end

local function isOddInteger(y)
    return isInteger(y) and y < 2 ^ 53 and y > -2 ^ 53 and y % 2 ~= 0
end

-- Math.pow for the reference's finite operands, correctly rounded except for
-- results within about 2^-90 of a rounding boundary. Special values follow
-- ECMAScript Number::exponentiate. Measured against V8 in docs/reference/WORKSHOP.md.
function JSMath.pow(x, y)
    if y ~= y then return 0 / 0 end
    if y == 0 then return 1 end
    if x ~= x then return 0 / 0 end
    local ax = x < 0 and -x or x
    if y == huge or y == -huge then
        if ax == 1 then return 0 / 0 end
        if (ax > 1) == (y > 0) then return huge end
        return 0
    end
    if x == huge then return y > 0 and huge or 0 end
    if x == -huge then
        if y > 0 then return isOddInteger(y) and -huge or huge end
        return isOddInteger(y) and NEG_ZERO or 0
    end
    if x == 0 then
        local negativeZero = 1 / x < 0
        if y > 0 then return (negativeZero and isOddInteger(y)) and NEG_ZERO or 0 end
        return (negativeZero and isOddInteger(y)) and -huge or huge
    end
    if x < 0 and not isInteger(y) then return 0 / 0 end
    if y == 1 then return x end
    if ax == 1 then return (x < 0 and isOddInteger(y)) and -1 or 1 end

    local lh, ll = ddLog(ax)
    if y > 2 ^ 900 or y < -2 ^ 900 then
        -- |log(x) * y| is far beyond the double range; avoid splitting y.
        local result = ((lh > 0) == (y > 0)) and huge or 0
        if x < 0 and isOddInteger(y) then return -result end
        return result
    end
    local th, tl = ddMulD(lh, ll, y)
    local result
    if th > 709.8 then
        result = huge
    elseif th < -745.2 then
        result = 0
    else
        local eh, el, k = ddExp(th, tl)
        local rounded = eh + el
        if k > 1023 or k < -1021 then
            -- Scale in two steps so a normal mantissa is not rounded twice early.
            local half = floor(k / 2)
            result = ldexp(ldexp(rounded, half), k - half)
        else
            result = ldexp(rounded, k)
        end
    end
    if x < 0 and isOddInteger(y) then return -result end
    return result
end

ns.JSMath = JSMath
return JSMath
