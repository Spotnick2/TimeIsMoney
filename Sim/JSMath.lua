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

-- WoW's embedded Lua (measured on 1.60.1.70205) differs from C Lua for NaN and
-- zero divisors: x / 0 and x % 0 raise "Division by zero", a NaN numerator raises
-- "Numerator is not a number", and every comparison involving NaN is true (NaN ==
-- 1, NaN < 1 and NaN > 1 all hold). Nothing here divides by zero or by NaN, and
-- NaN is tested without relying on IEEE comparisons.
local NAN = huge - huge
JSMath.NAN = NAN

-- NaN on either host: IEEE NaN is unequal to itself; WoW's NaN equals both 0 and 1,
-- which no number does.
local function isNaN(x)
    return x ~= x or (x == 0 and x == 1)
end
JSMath.isNaN = isNaN
if not (isNaN(NAN) and not isNaN(0) and not isNaN(huge)) then error("NaN detection failed on this host", 0) end

-- JavaScript relational operators: false whenever either side is NaN.
function JSMath.lt(a, b) return not isNaN(a) and not isNaN(b) and a < b end
function JSMath.gt(a, b) return not isNaN(a) and not isNaN(b) and a > b end

-- Sign of zero without 1/x: the first test that tells -0 from +0 on this host.
local signTests = {
    { "math.atan2", function(x) return math.atan2(x, -1) < 0 end },
    { "tostring", function(x) return tostring(x) == "-0" end },
    { "division", function(x) return 1 / x < 0 end },
}
local negativeZeroTest
for _, test in ipairs(signTests) do
    local okNeg, neg = pcall(test[2], NEG_ZERO)
    local okPos, pos = pcall(test[2], tonumber("0"))
    if okNeg and okPos and neg == true and pos == false then
        negativeZeroTest, JSMath.signedZeroTest = test[2], test[1]
        break
    end
end
-- Whether x is -0. If no test can see the sign, -0 is treated as +0. (WoW's NaN
-- equals 0, so NaN is excluded first.)
local function isNegativeZero(x)
    return x == 0 and not isNaN(x) and negativeZeroTest ~= nil and negativeZeroTest(x)
end
JSMath.isNegativeZero = isNegativeZero

-- JavaScript division: x / ±0 is ±Infinity; 0 / 0 and NaN operands give NaN.
function JSMath.div(a, b)
    if isNaN(a) or isNaN(b) then return NAN end -- NaN operands never reach a native division
    if b ~= 0 then return a / b end
    if a == 0 then return NAN end
    if (a < 0) ~= isNegativeZero(b) then return -huge end
    return huge
end

-- JavaScript's undefined, kept distinct from nil so state tables keep the key.
-- Arithmetic sites convert it explicitly with JSMath.num (undefined -> NaN).
JSMath.undefined = setmetatable({}, { __tostring = function() return "undefined" end })

function JSMath.num(value)
    if value == JSMath.undefined then return NAN end
    return value
end

-- Math.round: nearest integer, ties toward +infinity, keeping -0 for [-0.5, -0].
function JSMath.round(x)
    if isNaN(x) or x == huge or x == -huge then return x end
    local r = floor(x)
    if x - r >= 0.5 then r = r + 1 end
    if r == 0 and (x < 0 or isNegativeZero(x)) then return NEG_ZERO end
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
    if isNaN(y) then return NAN end
    if y == 0 then return 1 end
    if isNaN(x) then return NAN end
    local ax = x < 0 and -x or x
    if y == huge or y == -huge then
        if ax == 1 then return NAN end
        if (ax > 1) == (y > 0) then return huge end
        return 0
    end
    if x == huge then return y > 0 and huge or 0 end
    if x == -huge then
        if y > 0 then return isOddInteger(y) and -huge or huge end
        return isOddInteger(y) and NEG_ZERO or 0
    end
    if x == 0 then
        local negativeZero = isNegativeZero(x)
        if y > 0 then return (negativeZero and isOddInteger(y)) and NEG_ZERO or 0 end
        return (negativeZero and isOddInteger(y)) and -huge or huge
    end
    if x < 0 and not isInteger(y) then return NAN end
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

-- IEEE-754 words for fdlibm ports: signed high word and unsigned low word, as in
-- EXTRACT_WORDS. Lua 5.1 has no bit library, so this uses frexp/ldexp.
local function toWords(x)
    -- One canonical NaN: its sign is unobservable in JavaScript, and WoW's
    -- NaN < 0 is true.
    if isNaN(x) then return 0x7FF80000, 0 end
    local sign = (x < 0 or isNegativeZero(x)) and 1 or 0
    local a = sign == 1 and -x or x
    local e, mantissa
    if isNaN(a) then
        e, mantissa = 2047, 2 ^ 51
    elseif a == huge then
        e, mantissa = 2047, 0
    elseif a == 0 then
        e, mantissa = 0, 0
    else
        local m, exponent = frexp(a)
        e = exponent + 1022
        if e >= 1 then mantissa = m * 2 ^ 53 - 2 ^ 52 else e, mantissa = 0, ldexp(a, 1074) end
    end
    local hi = sign * 2 ^ 31 + e * 2 ^ 20 + floor(mantissa / 2 ^ 32)
    if hi >= 2 ^ 31 then hi = hi - 2 ^ 32 end
    return hi, mantissa % 2 ^ 32
end

local function fromWords(hi, lo)
    if hi < 0 then hi = hi + 2 ^ 32 end
    local sign = hi >= 2 ^ 31
    if sign then hi = hi - 2 ^ 31 end
    local e = floor(hi / 2 ^ 20)
    local mantissa = (hi % 2 ^ 20) * 2 ^ 32 + lo
    local value
    if e == 2047 then
        value = mantissa == 0 and huge or NAN
    elseif e == 0 then
        value = ldexp(mantissa, -1074)
    else
        value = ldexp(2 ^ 52 + mantissa, e - 1075)
    end
    if sign then return -value end
    return value
end
JSMath.toWords, JSMath.fromWords = toWords, fromWords

-- The signed high word alone (sign, exponent and top 20 mantissa bits).
local function highWord(x)
    if isNaN(x) then return 0x7FF80000 end
    local sign = x < 0 or isNegativeZero(x)
    local a = sign and -x or x
    local hi
    if isNaN(a) or a == huge then
        hi = 2047 * 2 ^ 20 + (isNaN(a) and 2 ^ 19 or 0)
    elseif a == 0 then
        hi = 0
    else
        local m, exponent = frexp(a)
        local e = exponent + 1022
        if e >= 1 then
            hi = e * 2 ^ 20 + floor((m * 2 ^ 53 - 2 ^ 52) / 2 ^ 32)
        else
            hi = floor(ldexp(a, 1074) / 2 ^ 32)
        end
    end
    if sign then return hi - 2 ^ 31 end
    return hi
end
local function abs31(v) if v < 0 then return v + 2 ^ 31 end return v end
local W = fromWords

-- Math.sin and Math.log10 below are Lua ports of fdlibm 5.3 (k_sin.c, k_cos.c,
-- e_rem_pio2.c, e_log.c, e_log10.c), distributed under this notice:
--   Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
--   Developed at SunPro, a Sun Microsystems, Inc. business.
--   Permission to use, copy, modify, and distribute this
--   software is freely granted, provided that this notice
--   is preserved.

-- fdlibm 5.3 sin (the variant V8 uses): __kernel_sin, the original __kernel_cos
-- with qx, and __ieee754_rem_pio2 for |x| <= 2^20 * pi/2 (high word 0x413921fb).
local S1, S2, S3 = W(0xBFC55555, 0x55555549), W(0x3F811111, 0x1110F8A6), W(0xBF2A01A0, 0x19C161D5)
local S4, S5, S6 = W(0x3EC71DE3, 0x57B1FE7D), W(0xBE5AE5E6, 0x8A2B9CEB), W(0x3DE5D93A, 0x5ACFD57C)
local C1, C2, C3 = W(0x3FA55555, 0x5555554C), W(0xBF56C16C, 0x16C15177), W(0x3EFA01A0, 0x19CB1590)
local C4, C5, C6 = W(0xBE927E4F, 0x809C52AD), W(0x3E21EE9E, 0xBDB4B1C4), W(0xBDA8FAE9, 0xBE8838D4)
local pio2_1, pio2_1t = W(0x3FF921FB, 0x54400000), W(0x3DD0B461, 0x1A626331)
local pio2_2, pio2_2t = W(0x3DD0B461, 0x1A600000), W(0x3BA3198A, 0x2E037073)
local pio2_3, pio2_3t = W(0x3BA3198A, 0x2E000000), W(0x397B839A, 0x252049C1)
local invpio2 = W(0x3FE45F30, 0x6DC9C883)
-- High words of n * pi/2 for n = 1..32 (npio2_hw).
local npio2_hw = {
    0x3FF921FB, 0x400921FB, 0x4012D97C, 0x401921FB, 0x401F6A7A, 0x4022D97C, 0x4025FDBB, 0x402921FB,
    0x402C463A, 0x402F6A7A, 0x4031475C, 0x4032D97C, 0x40346B9C, 0x4035FDBB, 0x40378FDB, 0x403921FB,
    0x403AB41B, 0x403C463A, 0x403DD85A, 0x403F6A7A, 0x40407E4C, 0x4041475C, 0x4042106C, 0x4042D97C,
    0x4043A28C, 0x40446B9C, 0x404534AC, 0x4045FDBB, 0x4046C6CB, 0x40478FDB, 0x404858EB, 0x404921FB,
}

local function kernelSin(x, y, iy)
    if (x < 0 and -x or x) < 2 ^ -27 then return x end -- |x| < 2^-27 (high word < 0x3e400000)
    local z = x * x
    local v = z * x
    local r = S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)))
    if iy == 0 then return x + v * (S1 + z * r) end
    return x - ((z * (0.5 * y - v * r) - y) - v * S1)
end

local function kernelCos(x, y)
    local ix = abs31(highWord(x))
    if ix < 0x3e400000 then return 1 end -- also the |x| < 2^-27 shortcut
    local z = x * x
    local r = z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))))
    if ix < 0x3FD33333 then return 1 - (0.5 * z - (z * r - x * y)) end
    local qx
    if ix > 0x3fe90000 then qx = 0.28125 else qx = W(ix - 0x00200000, 0) end
    local iz = 0.5 * z - qx
    local a = 1 - qx
    return a - (iz - (z * r - x * y))
end

-- Returns n, y0, y1 with x = n * pi/2 + (y0 + y1); hx is x's high word.
local function remPio2(x, hx)
    local ix = abs31(hx)
    if ix <= 0x3fe921fb then return 0, x, 0 end
    if ix < 0x4002d97c then
        local z, y0, y1
        if hx > 0 then
            z = x - pio2_1
            if ix ~= 0x3ff921fb then
                y0 = z - pio2_1t
                y1 = (z - y0) - pio2_1t
            else
                z = z - pio2_2
                y0 = z - pio2_2t
                y1 = (z - y0) - pio2_2t
            end
            return 1, y0, y1
        end
        z = x + pio2_1
        if ix ~= 0x3ff921fb then
            y0 = z + pio2_1t
            y1 = (z - y0) + pio2_1t
        else
            z = z + pio2_2
            y0 = z + pio2_2t
            y1 = (z - y0) + pio2_2t
        end
        return -1, y0, y1
    end
    if ix > 0x413921fb then
        error("Unported reference path: Math.sin beyond the ported fdlibm reduction range " ..
            "(|x| > 2^20*pi/2, about 1,647,099) (issue #24)", 0)
    end
    local t = x < 0 and -x or x
    local n = floor(t * invpio2 + 0.5)
    local r = t - n * pio2_1
    local w = n * pio2_1t
    local y0
    if n < 32 and ix ~= npio2_hw[n] then
        y0 = r - w -- quick check: no cancellation
    else
        local j = floor(ix / 2 ^ 20)
        y0 = r - w
        local i = j - floor(abs31(highWord(y0)) / 2 ^ 20) % 2048
        if i > 16 then
            t = r
            w = n * pio2_2
            r = t - w
            w = n * pio2_2t - ((t - r) - w)
            y0 = r - w
            i = j - floor(abs31(highWord(y0)) / 2 ^ 20) % 2048
            if i > 49 then
                t = r
                w = n * pio2_3
                r = t - w
                w = n * pio2_3t - ((t - r) - w)
                y0 = r - w
            end
        end
    end
    local y1 = (r - y0) - w
    if hx < 0 then return -n, -y0, -y1 end
    return n, y0, y1
end

function JSMath.sin(x)
    local hx = highWord(x)
    local ix = abs31(hx)
    if ix <= 0x3fe921fb then return kernelSin(x, 0, 0) end
    if ix >= 0x7ff00000 then return x - x end
    local n, y0, y1 = remPio2(x, hx)
    local q = n % 4
    if q == 0 then return kernelSin(y0, y1, 1) end
    if q == 1 then return kernelCos(y0, y1) end
    if q == 2 then return -kernelSin(y0, y1, 1) end
    return -kernelCos(y0, y1)
end

-- fdlibm 5.3 __ieee754_log and __ieee754_log10 (the variants V8 uses).
local Lg1, Lg2, Lg3 = W(0x3FE55555, 0x55555593), W(0x3FD99999, 0x9997FA04), W(0x3FD24924, 0x94229359)
local Lg4, Lg5, Lg6 = W(0x3FCC71C5, 0x1D8E78AF), W(0x3FC74664, 0x96CB03DE), W(0x3FC39A09, 0xD078C69F)
local Lg7 = W(0x3FC2F112, 0xDF3E5244)
local ln2_hi, ln2_lo = W(0x3fe62e42, 0xfee00000), W(0x3dea39ef, 0x35793c76)
local two54 = W(0x43500000, 0)
local ivln10 = W(0x3FDBCB7B, 0x1526E50E)
local log10_2hi, log10_2lo = W(0x3FD34413, 0x509F6000), W(0x3D59FEF3, 0x11F12B36)

local function ieeeLog(x)
    local hx, lx = toWords(x)
    local k = 0
    if hx < 0x00100000 then
        if abs31(hx) == 0 and lx == 0 then return -huge end
        if hx < 0 then return NAN end
        k = k - 54
        x = x * two54
        hx, lx = toWords(x)
    end
    if hx >= 0x7ff00000 then return x + x end
    k = k + floor(hx / 2 ^ 20) - 1023
    hx = hx % 2 ^ 20
    local i = ((hx + 0x95f64) % 2 ^ 21 >= 2 ^ 20) and 0x100000 or 0
    x = W(hx + (i == 0 and 0x3ff00000 or 0x3fe00000), lx) -- hx | (i ^ 0x3ff00000)
    k = k + i / 2 ^ 20
    local f = x - 1
    if (2 + hx) % 2 ^ 20 < 3 then
        if f == 0 then
            if k == 0 then return 0 end
            return k * ln2_hi + k * ln2_lo
        end
        local R = f * f * (0.5 - 0.33333333333333333 * f)
        if k == 0 then return f - R end
        return k * ln2_hi - ((R - k * ln2_lo) - f)
    end
    local s = f / (2 + f)
    local dk = k
    local z = s * s
    local ii = hx - 0x6147a
    local w = z * z
    local j = 0x6b851 - hx
    local t1 = w * (Lg2 + w * (Lg4 + w * Lg6))
    local t2 = z * (Lg1 + w * (Lg3 + w * (Lg5 + w * Lg7)))
    local R = t2 + t1
    if ii >= 0 and j >= 0 and (ii > 0 or j > 0) then -- (i | j) > 0
        local hfsq = 0.5 * f * f
        if k == 0 then return f - (hfsq - s * (hfsq + R)) end
        return dk * ln2_hi - ((hfsq - (s * (hfsq + R) + dk * ln2_lo)) - f)
    end
    if k == 0 then return f - s * (f - R) end
    return dk * ln2_hi - ((s * (f - R) - dk * ln2_lo) - f)
end

function JSMath.log10(x)
    local hx, lx = toWords(x)
    local k = 0
    if hx < 0x00100000 then
        if abs31(hx) == 0 and lx == 0 then return -huge end
        if hx < 0 then return NAN end
        k = k - 54
        x = x * two54
        hx, lx = toWords(x)
    end
    if hx >= 0x7ff00000 then return x + x end
    k = k + floor(hx / 2 ^ 20) - 1023
    local i = k < 0 and 1 or 0
    hx = hx % 2 ^ 20 + (0x3ff - i) * 2 ^ 20
    local y = k + i
    x = W(hx, lx)
    local z = y * log10_2lo + ivln10 * ieeeLog(x)
    return z + y * log10_2hi
end

-- Exact shortest decimal digits (Steele-White free-format / Dragon4) with small
-- base-10^7 big integers, so Number::toString never depends on the C library's
-- printf rounding or strtod.
local BASE = 10000000
local function big(n) -- n: nonnegative integer below 2^53
    local t = {}
    repeat
        t[#t + 1] = n % BASE
        n = floor(n / BASE)
    until n == 0
    return t
end
local function bigMulSmall(a, m)
    local carry = 0
    for i = 1, #a do
        local v = a[i] * m + carry
        a[i] = v % BASE
        carry = floor(v / BASE)
    end
    while carry > 0 do
        a[#a + 1] = carry % BASE
        carry = floor(carry / BASE)
    end
    return a
end
local function bigCopy(a) local t = {} for i = 1, #a do t[i] = a[i] end return t end
local function bigCompare(a, b)
    local na, nb = #a, #b
    while na > 1 and a[na] == 0 do na = na - 1 end
    while nb > 1 and b[nb] == 0 do nb = nb - 1 end
    if na ~= nb then return na < nb and -1 or 1 end
    for i = na, 1, -1 do
        if a[i] ~= b[i] then return a[i] < b[i] and -1 or 1 end
    end
    return 0
end
local function bigAdd(a, b) -- new value a + b
    local t, carry = {}, 0
    for i = 1, math.max(#a, #b) do
        local v = (a[i] or 0) + (b[i] or 0) + carry
        t[i] = v % BASE
        carry = floor(v / BASE)
    end
    if carry > 0 then t[#t + 1] = carry end
    return t
end
local function bigSub(a, b) -- a := a - b, requires a >= b
    local borrow = 0
    for i = 1, #a do
        local v = a[i] - (b[i] or 0) - borrow
        if v < 0 then v = v + BASE; borrow = 1 else borrow = 0 end
        a[i] = v
    end
    return a
end
-- Multiply by 2^n in exact 2^20 steps (a limb times 2^20 stays below 2^53).
local function bigPow2(a, n)
    while n >= 20 do
        bigMulSmall(a, 2 ^ 20)
        n = n - 20
    end
    if n > 0 then bigMulSmall(a, 2 ^ n) end
    return a
end

-- Returns the shortest digit string d1..dk and n with value = 0.d1..dk * 10^n,
-- choosing the closest such string (ties to an even last digit).
local function shortestDigits(x)
    local hi, lo = toWords(x)
    local e = floor(abs31(hi) / 2 ^ 20) % 2048
    local mantissa = (abs31(hi) % 2 ^ 20) * 2 ^ 32 + lo
    local exponent
    if e == 0 then exponent = -1074 else mantissa = mantissa + 2 ^ 52; exponent = e - 1075 end
    local even = mantissa % 2 == 0
    local r, s, mPlus, mMinus
    if exponent >= 0 then
        local be = bigPow2(big(1), exponent)
        if mantissa ~= 2 ^ 52 then
            r = bigMulSmall(bigPow2(big(mantissa), exponent), 2)
            s = big(2)
            mPlus, mMinus = be, bigCopy(be)
        else
            r = bigMulSmall(bigPow2(big(mantissa), exponent), 4)
            s = big(4)
            mPlus, mMinus = bigMulSmall(bigCopy(be), 2), be
        end
    else
        if e <= 1 or mantissa ~= 2 ^ 52 then
            r = bigMulSmall(big(mantissa), 2)
            s = bigPow2(big(1), 1 - exponent)
            mPlus, mMinus = big(1), big(1)
        else
            r = bigMulSmall(big(mantissa), 4)
            s = bigPow2(big(1), 2 - exponent)
            mPlus, mMinus = big(2), big(1)
        end
    end
    -- Scale so that the first digit is generated next.
    local k = math.ceil(math.log10(x) - 1e-10)
    if k >= 0 then
        for _ = 1, k do bigMulSmall(s, 10) end
    else
        for _ = 1, -k do bigMulSmall(r, 10); bigMulSmall(mPlus, 10); bigMulSmall(mMinus, 10) end
    end
    local function high(rr) local c = bigCompare(bigAdd(rr, mPlus), s) return even and c >= 0 or c > 0 end
    while high(r) do bigMulSmall(s, 10); k = k + 1 end
    local function highScaled()
        local c = bigCompare(bigMulSmall(bigAdd(r, mPlus), 10), s)
        return even and c >= 0 or c > 0
    end
    while not highScaled() do
        bigMulSmall(r, 10); bigMulSmall(mPlus, 10); bigMulSmall(mMinus, 10); k = k - 1
    end
    local digits = {}
    while true do
        bigMulSmall(r, 10); bigMulSmall(mPlus, 10); bigMulSmall(mMinus, 10)
        local d = 0
        while bigCompare(r, s) >= 0 do bigSub(r, s); d = d + 1 end
        local cl = bigCompare(r, mMinus)
        local low = even and cl <= 0 or cl < 0
        local hiOk = high(r)
        if low or hiOk then
            if low and hiOk then
                local c = bigCompare(bigMulSmall(bigCopy(r), 2), s)
                if c > 0 or (c == 0 and d % 2 == 1) then d = d + 1 end
            elseif hiOk then
                d = d + 1
            end
            digits[#digits + 1] = d
            break
        end
        digits[#digits + 1] = d
    end
    return table.concat(digits), k
end

-- Number::toString (radix 10) with ECMAScript's plain and exponent layouts.
function JSMath.toString(x)
    if isNaN(x) then return "NaN" end
    if x == 0 then return "0" end
    if x == huge then return "Infinity" end
    if x == -huge then return "-Infinity" end
    local sign = x < 0 and "-" or ""
    local digits, n = shortestDigits(x < 0 and -x or x)
    local k = #digits
    if k <= n and n <= 21 then return sign .. digits .. string.rep("0", n - k) end
    if 0 < n and n <= 21 then return sign .. digits:sub(1, n) .. "." .. digits:sub(n + 1) end
    if -6 < n and n <= 0 then return sign .. "0." .. string.rep("0", -n) .. digits end
    local e = n - 1
    local mantissaText = k == 1 and digits or (digits:sub(1, 1) .. "." .. digits:sub(2))
    return sign .. mantissaText .. "e" .. (e >= 0 and "+" or "-") .. (e < 0 and -e or e)
end

-- ToNumber for strings such as a select's value (StringNumericLiteral): blank is
-- 0; decimal literals, unsigned 0x/0o/0b integers and [+-]Infinity convert;
-- anything else (including "inf" or "-0x10", which C strtod accepts) is NaN.
-- Decimal digits go through tonumber only after this grammar check.
local function stringToNumber(text)
    local trimmed = text:match("^%s*(.-)%s*$")
    if trimmed == "" then return 0 end
    if trimmed == "Infinity" or trimmed == "+Infinity" then return huge end
    if trimmed == "-Infinity" then return -huge end
    local prefix, digits = trimmed:match("^0([xXoObB])(%w+)$")
    if prefix then
        local base = ({ x = 16, o = 8, b = 2 })[prefix:lower()]
        local value = 0
        for c in digits:gmatch(".") do
            local d = tonumber(c, 36)
            if not d or d >= base then return NAN end
            value = value * base + d
        end
        return value
    end
    local body = trimmed:match("^[+-]?(.*)$")
    local mantissa = body:match("^(%d+%.?%d*)[eE][+-]?%d+$") or body:match("^(%.%d+)[eE][+-]?%d+$")
        or body:match("^(%d+%.?%d*)$") or body:match("^(%.%d+)$")
    if not mantissa then return NAN end
    return tonumber(trimmed)
end

function JSMath.toNumber(v)
    if type(v) == "number" then return v end
    if v == JSMath.undefined then return NAN end
    if type(v) == "string" then return stringToNumber(v) end
    if v == true then return 1 end
    if v == false then return 0 end
    return NAN
end

ns.JSMath = JSMath
return JSMath
