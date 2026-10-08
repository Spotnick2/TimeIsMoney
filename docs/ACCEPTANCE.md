# Release acceptance (#24)

The pass/fail matrix for the first release (0.1.0, docs/RELEASE.md). Every row
names its evidence; a row passes only on the versions below. Rows marked **open** need the owner in the
client and are not claimed here.

## Versions

| What | Version |
| --- | --- |
| Reference | Universal Paperclips index2.html edition, retrieved 2026-10-02 (docs/reference/paperclips.lock.json): index2.html `526b148a2eab`, combat.js `c7226d012193`, globals.js `968abd83c709`, projects.js `05034c51809b`, main.js `ee599076de86` (SHA-256 prefixes) |
| Reference runtime | Node v24.15.0, V8 13.6.233.17-node.48, win32 x64 |
| Offline Lua | Lua 5.1 (C:\Program Files (x86)\Lua\5.1) |
| Client | WoW Forever 1.60.1.70245, Interface 16001, embedded Lua 5.1; API evidence 1.60.1.70205 (documented surface identical to the 70245 dump) |
| LibGlass | r4 (.pkgmeta; r1 at the 1.60.1.70245 client acceptance) |

## Simulation parity

| Area | Evidence | Result |
| --- | --- | --- |
| All 96 projects | docs/reference/PROJECTS.md (generated; workshop.test.cjs keeps it current): every project is bought in a trace matching the reference at every checkpoint, except the restarts (200, 201, 217), covered by the Lua tests it names | pass |
| One-use projects never return; repeatables repeat | workshop.test.cjs ("one-use projects never return", REPEATABLE set) | pass |
| Phase one: production, sales, marketing, wire, automation, milestones | traces manual, exactCost, depletion, automation, priceFloor, milestones, mega, highPrice, pricedMarketing, wireBuyerToggle | pass (two declared display-field tolerances) |
| Project purchases by group | traces projectsProduction, projectsCreativity, projectsStrategy, projectsBusiness, projectsVolition, projectsMachines, projectsRecovery, projectsLate | pass |
| The reference auto-save timer | trace autoSave (no game-state change; the host persists, docs/SAVES.md) | pass |
| Computation: trust, processors, memory, creativity, Operations fade | traces computationUnlock, allocation, creativity, creativityFast, opFade | pass |
| Quantum computing, negative Operations and recovery | traces quantumOverflow, quantumNegative, projectsRecovery | pass |
| Investments | traces investments, investmentSale, investmentRisk, investUpgrade, investReport | pass |
| Strategic modeling and tournaments | traces tourneyGreedy, tourneyMinimax, tourneyBeatLast, tourneyFixed, autoTourney, noPick, projectsStrategy | pass |
| Transition to the planetary phase | trace transition | pass |
| Planetary phase: buildings, power, reboots, exhaustion | traces planetChain, planetExactCost, planetPartialBulk, planetPipeline, planetExhaustion, planetReboots, planetUpgrades | pass |
| Swarm: gifts, slider, boredom, recovery | traces swarmGifts, swarmRepeatGifts, swarmSlider, swarmRecovery | pass |
| Cosmic phase: probes, survey, drift, war | traces spaceGate, probeDesign, probeGrowth, probeSurvey, probeShortage, spaceProjects, spaceRecovery, spaceWar | pass |
| Battles (16 ms logical tick) | traces battleVictory, battleDefeat, battleTimeout, battleClockTimeout, memorials | pass |
| Endings and complete liquidation | traces correspondence, surveyedEnd, memoryRelease, endingReject, endingAccept, endingDismantle | pass |
| Both prestige routes and Quantum Temporal Reversion | tests/test_host.lua, tests/test_restart.lua, tests/test_sim.lua | pass (reference reloads; the host restart is ours, docs/SAVES.md) |
| Math.sin, log, log10, toString | tests/reference/jsmath.test.cjs: 227,682 sin/log10 cases, 60,000 log, 9,223 toString, bit-identical | pass |
| Math.pow | Exact inside the pinned tables (cost_pow.test.cjs) and verified bounds; beyond them a declared difference | pass with declared difference |
| First-divergence reporting | Each trace reports source hashes, time, commands, draws and the first divergence (docs/reference/WORKSHOP.md, *Differential traces*); a one-step mutation is caught at the first tick | pass |

## Declared numeric exceptions

All are listed, scoped and bounded in docs/reference/WORKSHOP.md:

- Display fields `avgRev` (at most 6 binary64 steps) and `avgSales` (at most 4), never a
  decision (*Numeric exception*, under *JavaScript semantics in Lua*).
- Math.pow beyond the verified tables (drones > 200,000, farms and batteries >
  30,000, probe formulas > 10,000, processors > 3,424, investment base ≥ 968,
  fractional drone levels): JSMath.pow, one step from the reference wherever
  measured (*Declared numeric differences*).
- Building costs on other platforms follow the pinned profile's pow.

## Host, saves and lifecycle

| Area | Evidence | Result |
| --- | --- | --- |
| One parentless wakeup frame; 10 ms logical steps; debt cap; frame budget; halt on error | tests/test_host.lua, tests/test_bootstrap.lua | pass |
| Hidden window keeps the company running; toggling and restarts add no host step, per-frame script, queued timer or simulation timer | tests/test_lifecycle.lua (runs every OnUpdate the client would; injected regressions fail it) | pass offline; the client performance row below confirms it in the client |
| Save and continue (six scenarios, exact) | tests/test_save.lua | pass |
| Logout writes schema 1; next load continues at the same logical time | tests/test_bootstrap.lua | pass |
| Unknown, future or broken saves blocked and never replaced | tests/test_bootstrap.lua, tests/test_save.lua | pass |
| Restarts persist; settings saved and validated | tests/test_restart.lua, tests/test_settings.lua | pass |
| No offline production | docs/SAVES.md; the clock continues from saved logical time | pass by design |

## Client (owner, 1.60.1.70245, 2026-10-07)

Run by the owner on 1.60.1.70245 with current main (after #71) and the probe
addon; details in docs/forever-api-notes.md, *#24 acceptance in the client*.

| Check | Evidence | Result |
| --- | --- | --- |
| `/timprobe env`, `math`, `sim` match offline Lua, including large-argument sin | env all passed; math exact, 1,538 cases (sin 400); sim digest `c59a807f` and zero-price `032cb45b` match | pass |
| `/reload` continuation | the company reopened where it was, no error | pass |
| Full exit and relaunch continuation | as above; no offline production | pass |
| Restarts and new game, with the confirmation above Settings (#69) | confirmation in front and clickable; "keep" changed nothing; a confirmed new game stayed after reload | pass |
| Settings (model, voice, scale, position) across reload and relaunch | restored; three scales shown in screenshots | pass |
| Director: Gazlowe framing; the greeting voice | head and topknot in frame; "Time is money, friend!" heard | pass |
| Performance with the window open and hidden | open: 0.56 ms per frame on average, 66 ms CPU per logical second, worst 8.8 ms; hidden: 0.66 ms, 64 ms, worst 8.8 ms (the hidden sample includes the probe's 0.8 s one-frame run, which accounts for the time dropped between them) | pass |
| Interrupted session | the owner quit with Alt-F4. The relaunched company showed an earlier state than before the quit (2 Gizmos and a 30c price against 3 Gizmos and 13c): the logout write did not happen, the company came back from the last successful write, without error or a block | pass |

The documented API surface of 1.60.1.70245 is identical to the 1.60.1.70205
evidence (Compare-Dumps.ps1, 2026-10-07); moving the evidence constant is the
`/client-update` step.
