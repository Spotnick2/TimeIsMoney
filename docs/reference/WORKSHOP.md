# Pure-Lua workshop slice

Issue [#5](https://github.com/Spotnick2/TimeIsMoney/issues/5). This is the first
port of the [pinned reference](README.md) into the pure-Lua simulation layer
(`Sim/`). The simulation has no WoW globals, frames, clocks, I/O or native
randomness. It is parity-tested outside the game and is **not yet in the TOC or
the addon archive** (.pkgmeta ignores `Sim/` until the host adapter, #18).

## What is ported

| File | Contents |
| --- | --- |
| Sim/Reference.lua | Source pins (the five lock hashes) and simulation load order |
| Sim/JSMath.lua | JavaScript number semantics: `undefined`, Math.round, `%`, a pure-Lua Math.pow |
| Sim/Scheduler.lua | The reference host's logical timer queue (due time, then a stable ordinal; intervals requeue after their callback) |
| Sim/Battle.lua | The always-running battle core from combat.js |
| Sim/Workshop.lua | The phase-one workshop, the seven reference intervals and the click commands |

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
| calculateOperations, quantumCompute, calculateCreativity | #6 |
| Stock purchases, sales and valuation, investment report, automatic tournaments, strategy selection | #7 |
| Project purchases and project-dependent milestones | #8 |
| Planetary production and phase-two controls (`humanFlag == 0`) | #11 |
| exploreUniverse and probe functions | #14 |
| checkForBattleEnd with an active battle | #15 |
| Ending sequence and dismantling clicks | #17 |
| Reference auto-save (after 25 s) | #19 |

Reaching 2,000 clips, or running out of wire, money and stock, sets `compFlag`.
The next tick reaches calculateOperations, so a workshop trace stops there.

## JavaScript semantics in Lua

- **`undefined`:** `incomeThen`, `incomeNow`, `trueAvgRev`, `avgSales`,
  `incomeLastSecond` and `sum` start as `undefined`. The first calculateRev
  therefore pushes NaN, and the revenue average stays NaN for ten seconds. A
  sentinel keeps the key; `JSMath.num` turns it into NaN at arithmetic sites.
- **Math.round:** rounds ties toward +∞ and keeps −0, without `x + 0.5` double
  rounding.
- **`%` and truthiness:** JavaScript `%` is C fmod (timeCruncher). Conditions
  such as `if (creativityOn)` use JavaScript truthiness (0 is false).
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
- **Math.sin:** the wire price uses Lua's `math.sin`, which comes from the C
  library. Its result passes through Math.ceil, so only a value within one step
  of an integer could differ. This is a known dependency, not proven exact.

Trace inputs reach Lua as exact `math.ldexp(mantissa, exponent)` pairs, not as
decimal text. The older 32-bit Lua build parsed the halfway case
20614348053932190 to the wrong double. The #4 recorded-stream reader
(RecordedRandom.parse) still parses decimals and has the same caveat on such
runtimes.

## Differential traces

tests/reference/workshop.cjs defines ten traces with an explicit equidistributed
stream: the fractional part of i × 0.6180339887498949, recorded into the trace.
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
| computationBoundary | Out of wire, money and stock: the slice stops with the #6 error, and the agreed prefix matches | match up to the stop |

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
