# Pure-Lua workshop slice

Issues [#5](https://github.com/Spotnick2/TimeIsMoney/issues/5),
[#6](https://github.com/Spotnick2/TimeIsMoney/issues/6) and
[#7](https://github.com/Spotnick2/TimeIsMoney/issues/7). This is the first port of
the [pinned reference](README.md) into the pure-Lua simulation layer (`Sim/`). The simulation has no WoW globals, frames, clocks, I/O or native
randomness. It is parity-tested outside the game and is **not yet in the TOC or
the addon archive** (.pkgmeta ignores `Sim/` until the host adapter, #18).

## What is ported

| File | Contents |
| --- | --- |
| Sim/Reference.lua | Source pins (the five lock hashes) and simulation load order |
| Sim/JSMath.lua | JavaScript number semantics: `undefined`, Math.round, `%`, a pure-Lua Math.pow, and the fdlibm Math.sin and Math.log10 that V8 uses |
| Sim/Scheduler.lua | The reference host's logical timer queue (due time, then a stable ordinal; intervals requeue after their callback) |
| Sim/Battle.lua | The always-running battle core from combat.js |
| Sim/Workshop.lua | The phase-one workshop and computation, the seven reference intervals, formatWithCommas and the click and select commands |
| Sim/Investments.lua | The investment engine (#7) |
| Sim/Strategy.lua | Strategic modeling and tournaments (#7) |

State uses the reference global names, formulas and statement order: `clips`
(lifetime production), `unusedClips` (spendable stock) and `unsoldClips`
(inventory) stay separate. Ported behavior:

- **Production and input:** manual production; wire purchases; wire price drift
  and fluctuation; depletion clamps.
- **Sales:** price, demand and sales, including both branches of sellClips and
  their different fund rounding.
- **Revenue:** calculateRev, with the `undefined` start and a ten-second
  tracker.
- **Marketing and automation:** marketing purchases; AutoClippers and
  MegaClippers with their recomputed costs; clip-rate tracking; the optional
  WireBuyer.
- **Trust and milestones:** Fibonacci trust targets, and milestones with
  timeCruncher text and the five message readouts.
- **Controls:** button eligibility from buttonUpdate. A click on a disabled
  control does nothing, as in the browser. A hidden control still clicks, as
  `element.click()` does.
- **Computation (#6):**
  - processor and memory allocation from trust, and creativitySpeed from
    Math.log10 and Math.pow;
  - Operations: the processor cycle, the memory cap, and temporary Operations
    with their delayed, accelerating fade;
  - creativity, in whole steps (check ≥ 1) and fractional steps (check < 1);
  - quantum chips evaluating Math.sin of the shared clock every tick;
  - qComp: overflow into temporary Operations, including the reference's
    negative tempOps on overflow, and the negative-Operations path when the chip
    sum is negative.
- **Investments (#7):**
  - deposits and withdrawals (the ledger);
  - stockShop budgets and reserves for each risk level;
  - createStock with generated symbols and roll-based prices;
  - price updates with gains, losses and the zero-price rescue roll;
  - sales once sellDelay reaches 5;
  - the risk select, read every 100 ms;
  - engine upgrades with `Math.pow(level, Math.E)` costs;
  - the lifetime report.
- **Strategy (#7):**
  - tournaments: the payoff grid, then each round of ten moves joined by two
    chained 50 ms timeouts;
  - all eight strategies' moves (RANDOM, A100, B100, GREEDY, GENEROUS, MINIMAX,
    TIT FOR TAT, BEAT LAST);
  - scoring, winner, place and show;
  - Yomi for the picked strategy, with the reference's message text;
  - the strategy picker (a string value) and automatic tournaments while results
    are shown.
  - Strategy purchases are project effects (#8). Traces use the host's strategies
    fixture.
- **Projects:** project availability (manageProjects) for every trigger that reads
  state this slice changes, in projects.js registration order. This includes the
  shared blinkCounter and the 30 ms blink intervals. Project purchases and
  per-project eligibility remain #8.
- **Load sequence:** combat.js loading (two ship resets, 3,200 draws), then all
  seven intervals in source order.

**The battle core is part of this slice.** combat.js starts its battle animation at
load. Its 400 ships converge, and from 960 ms each combat roll draws from the
shared stream, about 10,000 draws per second. The spec requires the port to
preserve that consumption. Ship setup, UpdateGrid, MoveShips, FindCentroid and
DoCombat use only `+ - * /`, abs, floor, min and max, so Lua reproduces them
bit for bit. Drawing is omitted; `framesDead` still advances. Battles, honor and
battle names remain #15.

## Explicit stops

Reference paths outside the slice raise
`Unported reference path: <what> (issue #N)`. They never diverge silently:

| Path | Issue |
| --- | --- |
| Strategy-picker values that name no strategy (the reference throws a TypeError reading strats[pick].name) | #8 |
| Tournament placing bonuses (project128) | #14 |
| Project purchases and project-dependent milestones | #8 |
| Planetary production and phase-two controls (`humanFlag == 0`) | #11 |
| exploreUniverse and probe functions | #14 |
| checkForBattleEnd with an active battle | #15 |
| Ending sequence and dismantling clicks | #17 |
| Reference auto-save (after 25 s) | #19 |
| addProc beyond 3,424 processors, where Math.pow(n, 1.1) first differs from V8 | #24 |
| investUpgrade at level 967 and beyond, where Math.pow(level + 1, Math.E) first differs from V8 (at 968) | #24 |
| Math.sin of arguments beyond 2²⁰·π/2 (about 1,647,099; the quantum clock reaches it after about 19 days) | #24 |

## JavaScript semantics in Lua

- **`undefined`:** `incomeThen`, `incomeNow`, `trueAvgRev`, `avgSales`,
  `incomeLastSecond` and `sum` start as `undefined`. The first calculateRev
  therefore pushes NaN, and the revenue average stays NaN for ten seconds. A
  sentinel keeps the key; `JSMath.num` turns it into NaN at arithmetic sites.
- **Math.round:** rounds ties toward +∞ and keeps −0, without `x + 0.5` double
  rounding.
- **`%`, truthiness and loose equality:** JavaScript `%` is C fmod
  (timeCruncher). Conditions such as `if (creativityOn)` use JavaScript truthiness
  (0 is false). `creativityOn == 1` is also true for `true`.
- **Negative zero:** a literal `-0.0` can merge with the constant `0` in Lua
  5.1, so negative zero is built at run time.
- **Math.pow:** V8's results are not correctly rounded and differ from every C
  library tested. Lua's `^` would also depend on the host C runtime, including
  WoW's. JSMath.pow therefore computes a correctly rounded result in pure Lua
  (double-double log/exp), so it gives the same answer everywhere.
  tests/reference/jsmath.test.cjs measures it against V8:

  | Exponents | Cases | One-step differences from V8 |
  | --- | ---: | ---: |
  | Integer (costs, marketing) | 3,397 | 0 |
  | Fractional (sales and revenue use 1.15) | 45,415 | 18 |
  | ECMAScript special values | 256 | 0 |

  On a separate 87,236 normal positive-base cases, an 80-digit decimal check
  found the Lua result correctly rounded in every case. All 34 differences from
  V8 there are at misrounded V8 results. Subnormal results are not claimed.

  **Numeric exception.** The #32 review found reachable cent prices where that
  one step reaches state: margin 10.06, and margin 1.50 at marketing level 4. The
  workshop comparison therefore declares a narrow exception for exactly
  `$.state.avgRev` (at most 6 steps) and `$.state.avgSales` (at most 4 steps).
  calculateRev writes these fields; the reference only displays and saves them,
  and no decision reads them. The comparison reports every accepted difference,
  and every other field, event, draw and timer stays exact.

  Threshold evidence (jsmath.test.cjs): the test covers every reachable demand in
  this slice, meaning cent prices up to $100 and marketing levels 1–60, with the
  slice's constant effectiveness, boost and prestige. Moving Math.pow(demand,
  1.15) one step either way (1,200,000 cases) never changes the sale quantity
  `floor(.7 * pow)`. It moves the two fields by at most 4 and 6 steps, which
  become the declared bounds. Sale probability uses demand, and demand uses only
  integer exponents, which match exactly. Later slices that change effectiveness,
  boost or prestige must extend this evidence.
- **Math.sin and Math.log10:** V8 implements both with fdlibm 5.3: the original
  `__kernel_cos` with `qx`, and the `__ieee754_log`-based log10. The FreeBSD
  revisions and the C library differ. JSMath ports exactly those routines,
  building IEEE words with frexp/ldexp because Lua 5.1 has no bit library. They
  match V8 in all 119,505 cases in jsmath.test.cjs:
  - quantum-clock arguments;
  - ± wire-price counters 1–5,000;
  - points near multiples of π/2;
  - random magnitudes and special values;
  - log10 of 1–20,000 and of random magnitudes.

  A 290,720-case probe found 2,633 differences with the FreeBSD cosine kernel
  and 9,824 with the C library. The wire price and the quantum chips are
  therefore exact on the measured profile (Node v24.15.0, V8 13.6). V8 has a
  build option that swaps in glibc-derived sin/cos, so other Chromium builds are
  not covered by this claim. The reduction includes fdlibm's npio2_hw quick
  path, and jsmath.test.cjs covers arguments one or more high words away from
  n·π/2.
- **Number::toString and formatWithCommas:** messages print numbers, for
  example 0.5 + 0.01 + 0.01 + 0.01 as `0.5400000000000001`. C printf rounds exact
  halves differently, and the older C runtime's strtod accepts wrong round-trips.
  JSMath.toString therefore generates the shortest digits exactly
  (Steele–White/Dragon4) with small big integers, and lays them out with
  ECMAScript's plain and exponent rules. It matches V8 in all 9,223 tested cases,
  including subnormals, huge values and exact ties. formatWithCommas matches the
  reference function in its VM, including the quirk where 1e21 becomes
  "1e+21,000,000,000,000,000,000,000".
- **String keys:** `pick` holds the select's string value. `pick < 10` converts it
  to a number, but `strats[pick]` is a property lookup, so `"0"` names the first
  strategy while `""` and `"00"` name nothing.
- **creativitySpeed:** `log10(n) * pow(n, 1.1) + n - 1` for an integer processor
  count. log10 is exact. The correctly rounded pow matches V8 for every count up
  to 3,424 (tested); V8 first differs at 3,425. Creativity drives project
  unlocks, so addProc stops explicitly beyond the verified count instead of
  accepting drift.

Trace inputs reach Lua as exact `math.ldexp(mantissa, exponent)` pairs, not as
decimal text. The older 32-bit Lua build parsed the halfway case
20614348053932190 to the wrong double. The #4 recorded-stream reader
(RecordedRandom.parse) still parses decimals and has the same caveat on such
runtimes.

## Differential traces

tests/reference/workshop.cjs defines twenty-seven traces with an explicit equidistributed
stream: the fractional part of (i + offset) × 0.6180339887498949, recorded into
the trace. Longer traces use longer streams. A few investment traces use an
offset so the 25 % purchase rolls succeed within seconds.
The #4 repeat pattern never draws below 0.06, so it would never sell at the
default 5 % sale probability.

The reference runner and tests/reference/lua_trace_runner.lua run each trace.
The reference document is projected to the fields the Lua document declares:
every ported global, the slice's button states, the readouts, the timers and the
draw count. compareTraces then requires **exact** agreement of every event, every
labeled draw and every checkpoint, apart from the declared numeric exception above.

| Trace | Covers | Result |
| --- | --- | --- |
| manual | 70 production clicks, price changes, sales, revenue seconds and 3.5 s of the battle core past its first combat roll | match |
| exactCost | Wire, AutoClipper and marketing bought at funds equal to the cost; unaffordable clicks run the no-op branch, then the controls disable | match |
| depletion | Partial final clicks, AutoClipper demand clamped to the remaining 1.2 wire, the disabled control and restocking | match |
| automation | An unaffordable click recomputes the AutoClipper cost from 5 to 1.1⁰ + 5 = 6. $5 announces AutoClippers, the first purchase starts fractional production, then clip-rate tracking and the AutoClippers project | match |
| priceFloor | Two clicks before the first tick reach margin 0. Demand becomes NaN (∞ + ∞ × 0) and sales stop until the price recovers | match |
| milestones | 500 and 1,000 clip messages ("1 hour 2 minutes 1 second"), trust and the next Fibonacci target | match |
| mega | MegaClipper purchase, the recomputed cost and the disabled control | match |
| highPrice | Margin 10.06: `avgRev` differs by one step under the declared exception; it diverges without it | match with exception |
| pricedMarketing | Margin 1.50, marketing level 4: `avgSales` uses the exception | match with exception |
| computationUnlock | Out of wire, money and stock: Operations unlock, and Beg for More Wire and the projects list appear in the same tick | match |
| allocation | Four processors and two memory before the next tick exceed trust (8 against 7). Then the controls disable, memory caps Operations, processors ≥ 5 unlocks its project, and qComp without photonic chips only resets the fade | match |
| creativity | creativitySpeed 91.27 from log10/pow: whole creativity steps and the 50-creativity project | match |
| creativityFast | creativitySpeed 2,293.89: fractional creativity steps and the 50–250 creativity projects | match |
| opFade | Temporary Operations fading after opFadeDelay, with the accelerating fade | match |
| quantumOverflow | Seven chips oscillating every tick; qComp fills to the memory cap and overflows. The reference leaves a negative tempOps on the first overflow | match |
| quantumNegative | A −7.1 chip sum drains about 2,550 Operations per click. Operations fall below −12,000, unlock the recovery project, and refill slowly | match |
| investments | A deposit, three stockShop purchases with generated symbols, price updates with gains and losses, a medium-risk select and a second deposit | match |
| investmentSale | A purchase sold once sellDelay reaches 5 | match |
| investmentRisk | High risk spends the whole bankroll; an unknown risk value empties the select (still high risk); withdrawal | match |
| investUpgrade | Two upgrades before the next tick overspend Yomi (−258); messages "…now 0.51" and "…now 0.52"; then the control disables | match |
| investReport | Lifetime report "$123,454,288" through formatWithCommas | match |
| tourneyGreedy, tourneyMinimax, tourneyBeatLast, tourneyFixed | Two-strategy tournaments covering all eight moves. Each runs 4 rounds × 10 moves on the timer chain and awards Yomi with the message; Run stays disabled while running | match |
| autoTourney | A finished tournament with shown results starts the next after 300 ticks | match |
| noPick | Without a picked strategy, the tournament finishes with no Yomi and no results flag | match |

The reference VM mutates fixture objects such as qChips. The host therefore
clones fixture values, so the report records the fixture as injected and the Lua
input keeps the original values.

Changing one decrement in the Lua port by a single binary64 step was caught at
the first tick. So was changing one acceleration factor in the battle core.

tests/test_sim.lua (Lua 5.1, also in Linux CI) covers JSMath edge cases and the
scheduler. It loads every simulation file in an environment without os, io,
math.random or other globals, and runs the workshop there.

~~~powershell
python Tools/paperclips_reference.py fetch
node --test tests/reference/jsmath.test.cjs tests/reference/workshop.test.cjs
node tests/reference/workshop.cjs manual   # one trace, prints the first divergence
pwsh tests/run.ps1
~~~

The Node tests need Lua 5.1 (TIM_LUA, default C:\Program Files (x86)\Lua\5.1\lua.exe).

## Limits

These traces establish parity for the covered paths on the measured Windows /
Node 24 profile. They do not establish:

- full-phase coverage;
- in-game behavior: Sim/ is not loaded by the addon yet;
- WoW's embedded Lua numeric configuration;
- presentation.

Message strings stay as the reference's text for parity. The goblin presentation
replaces them in the UI layer later. Reuse terms for translating the reference
remain unestablished (see README). The simulation stays unpackaged until that
and the host adapter are settled.
