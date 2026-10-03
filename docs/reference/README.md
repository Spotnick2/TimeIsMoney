# Pinned Universal Paperclips reference

Issue [#2](https://github.com/Spotnick2/TimeIsMoney/issues/2), checked 2026-10-02.
The owner [implementation spec](../plan/Time-Is-Money-Implementation-Spec.md)
selects the [official web edition](https://www.decisionproblem.com/paperclips/index2.html).
All five downloads match its SHA-256 hashes. The original documents and their
pins are unchanged. The older jgmize mirror was not used.

## Retrieval and acceptance

[paperclips.lock.json](paperclips.lock.json) records exact URLs, sizes and hashes.
[retrieval-2026-10-02.json](retrieval-2026-10-02.json) records HTTP responses,
final URLs, UTC times, ETags and Last-Modified headers. Headers are observations;
hashes select the edition.

| File | Verified bytes |
| --- | ---: |
| index2.html | 34,994 |
| combat.js?v3 | 23,856 |
| globals.js?v3 | 3,496 |
| projects.js?v3 | 80,149 |
| main.js?v3 | 209,215 |

Run from the repository root using the existing Python toolchain:

~~~powershell
python Tools/paperclips_reference.py fetch
python Tools/paperclips_reference.py verify
python Tools/paperclips_reference.py inventory --check
python -m unittest discover -s tests -p test_paperclips_reference.py -v
~~~

No new packages. Downloads go to the git-ignored .tmp-paperclips/ developer
cache; upstream HTML/JS are not committed or packaged. Keep these local inputs
for issue #3; another checkout must retrieve and verify them first.

The tool checks the lock against the owner spec and accepts only the five
official URLs. It hashes raw bytes without newline/encoding normalization and
parses HTML to verify combat.js?v3 -> globals.js?v3 -> projects.js?v3 -> main.js?v3
(HTML lines 941-944). All responses are validated before replacing cache inputs.
Missing files, wrong hashes/sizes or changed script order/query fail with a
nonzero exit and specific error. No fallback mirror or automatic repinning.
Network/hash failures preserve the cache; validated writes are not promised
to be a filesystem transaction.

The inventory command regenerates [inventory.json](inventory.json); --check
compares without rewriting it. CI checks synthetic inputs and committed
evidence offline. Full regeneration was checked locally on official bytes.

Acceptance: all five hashes **match**; retrieval is **reproducible**; script
order and ?v3 requests are **verified**; inventory is **recorded**; reuse terms
are **unestablished and explicitly reported** below. No missing/mismatching
file remains.

## Reuse terms and provenance

No explicit source redistribution/translation grant was found in the inspected
official HTML and four scripts. This bounded inspection does not prove
permission cannot exist elsewhere.

Pinned [main.js](https://www.decisionproblem.com/paperclips/main.js?v3) credits
Frank Lantz (line 4533), combat programming by Bennett Foddy (4538), music-specific
permission (4543), and Everybody House Games copyright, 2017 (4548).
The music credit does not establish source reuse terms.
The [official landing page](https://www.decisionproblem.com/paperclips/) and
[Frank Lantz's game page](https://www.franklantz.net/universal-paperclips/)
were inspected on 2026-10-02; neither inspected page supplies a source reuse
grant. No unofficial mirror license was applied.

**Status: unestablished.** Before vendoring upstream or distributing translated
source, obtain and record applicable permission/authoritative terms. No request
has been sent. Repository MIT covers original tooling/docs and compatible
attributed code, not Paperclips or its music/artwork. Issue #2 permits reporting
unestablished terms; this PR does not resolve that subsequent distribution gate.

## Inventory format and limits

The JSON records hashes, script order, 61 HTML event bindings, HTML IDs and
per-script indexes. Locations are **one-based lines in verified upstream
files**, not lines in JSON.

| Field | Meaning |
| --- | --- |
| top_level_declarations | Function-scope-aware declarations, retaining duplicates. Includes config/collections/host objects as well as simulation state. |
| implicit_global_write_candidates | Bare writes not declared in that script/enclosing function; many resolve to other scripts. Reconcile across scripts; not proven bugs. |
| functions / html_events | Function boundaries and browser command bindings; helpers/console cheats are indexed but are not normal player commands. |
| projects / project_registration_order | All 96 definitions, IDs, initial uses/flags, field lines including trigger/cost/effect, and exact registration order. |
| timers / random_calls | Executable lexical sites, labels and lines; excludes comments and string/regex literals. Site counts are not invocation counts. |
| host_calls / host_lookups | Grouped API sites, literal DOM/storage keys and dynamic-argument markers. Leading literals of dynamic arguments are not final IDs. |
| host_member_sites / member_names | Likely DOM/canvas/audio reads/writes/calls through aliases, plus a broader member index. Similar simulation fields can appear here. |

This is a lexical index for the pinned edition, not a general JS parser,
complete mutation analysis, save schema or parity proof. It does not resolve
aliases, compute call graphs, infer types or serialize closures.
read_or_reference means lexical use, not proven semantic access.
Issue #3 must validate host/runtime behavior; #4 must measure draw order.

| Script | Top-level declaration sites | Function sites | RNG sites | Timer API sites |
| --- | ---: | ---: | ---: | ---: |
| combat.js | 46 | 18 | 17 | 1 |
| globals.js | 157 | 0 | 0 | 0 |
| projects.js | 98 | 288 | 0 | 0 |
| main.js | 428 | 162 | 23 | 12 |

## Mutable state and commands

| Family | Principal identifiers and continuation concerns |
| --- | --- |
| Workshop | clips, unusedClips, unsoldClips, wire, funds, margin, demand, marketing, clipmakerLevel, megaClipperLevel. Output/stock/inventory are distinct; rates/costs/boosts/trackers/timers also change. |
| Computation/projects | processors, memory, trust, operations, standardOps, tempOps, creativity, qClock, qChips, projects/activeProjects, uses/flag and modified price tags. Never persist DOM element references. |
| Investment/strategy | bankroll, stocks, portfolio totals, risk selection, allStrats/strats, pick, payoffGrid, round/move/score counters, tournament state and pending callbacks. |
| Planetary | availableMatter, acquiredMatter, processedMatter, construction levels/bills/costs/boosts, power/storage, swarmStatus, sliderPos, gifts and momentum. |
| Cosmic/combat | Probe allocations/trust/counts/losses, drifterCount, battles, ships, grid, team counts, clocks, honor/rewards and names/numbers. Positions/velocity/grid order affect combat. |
| Recovery/endings | Phase/project flags, prestigeU/prestigeS, dismantle, endTimer1-endTimer6, finalClips; preserve negative Operations and terminal accounting. |
| Host | Element aliases, canvas/context, audio readiness, handles and closure state. Represent logical continuation deliberately without native objects. |

globals.js initializes shared state after combat startup. Preserve duplicate
declarations (e.g. marketingEffectiveness) until parity. main.js caches DOM at
691; startup storage checks precede the main loop (4175-4182). Declaration
sites do not automatically form a save schema.

HTML bindings cover production/input, prices/automation/marketing, computation,
investments/tournaments, construction/reboots, swarm and probe allocation.
Generated project buttons bind project.effect() in displayProjects
(main.js:889-917); manageProjects (870-886) evaluates triggers, decrements uses,
tracks active projects and updates disabled buttons. Dispatch must reproduce
browser availability/disabled behavior: effects are not uniformly self-guarding.
Preserve project IDs and ordered array mutations.

## Browser reads/writes

Real values and persistent lookup identity are needed, not fresh no-op elements.

- Reads: investment risk (investStratElement.value, 1619-1625), selected strategy
  (stratPickerElement.value, 2318), slider (sliderElement.value, 2652), visibility
  in blink routines and message readouts in displayMessage.
- Writes: innerHTML, display/visibility/opacity, disabled buttons, option values,
  IDs/classes and dynamic project/battle nodes. Preserve creation, append,
  insert/remove, parent/child links and subsequent lookups.
- Storage: JSON parse/stringify and localStorage getItem/setItem/removeItem.
  Keys: saveGame, saveProjectsUses, saveProjectsFlags, saveProjectsActive,
  saveStratsActive, their 1/2 variants, and savePrestige. Save/load variants/reset
  differ; sites are indexed. These are not the future WoW schema.
- Canvas/audio: dimensions, 2D getContext, fillStyle/fillRect, width reset;
  new Audio, src, canplaythrough and play. Controlled media avoids fetching music.
  Disabling drawing must retain combat.
- HTML analytics/styles/art are outside the four gameplay scripts. Analytics
  uses Date; indexed gameplay has no direct Date/performance clock reads.
  Do not execute analytics in the runner.

## Scheduling

| Source/registration | API / delay | Role |
| --- | --- | --- |
| combat.js:288 | interval / 16 ms | Clear drawing, update grid, move ships, combat |
| main.js:929, 953 | interval / 32 ms; cancellation | Hypnodrone presentation/counters |
| main.js:990, 997 | interval / 30 ms; cancellation | Blink presentation/counters |
| main.js:1617 | interval / 100 ms | Risk selector/portfolio/stock display |
| main.js:1666 | interval / 1,000 ms | Stock purchases |
| main.js:1673 | interval / 2,500 ms | Stock sale/update decisions |
| main.js:2283 | timeout / 50 ms | Tournament round -> clear grid |
| main.js:2299 | timeout / 50 ms | Clear grid -> next round |
| main.js:2316 | interval / 100 ms | Read selected strategy |
| main.js:4188 | interval / 10 ms | Simulation/projects/phases/endings |
| main.js:4564 | interval / 100 ms | Wire price/sales/revenue/autosave |

Nine interval registrations, two timeouts, two clearInterval sites; no executable
clearTimeout found. Seven intervals register at startup; two blink intervals
are event driven. Combat's new Battle() and app.initialize() (799-800) both
restart ships and consume initialization randomness before other scripts load.
Preserve registration order, cancellation, closures and stable equal-due order.
Do not collapse callbacks into one tick or tie combat to UI refresh.

## Random stream

All **40 executable Math.random() sites**: 17 combat, 23 main, zero
globals/projects. Preserve branch-dependent invocation order.

| Script | Families |
| --- | --- |
| combat.js | Battle checks/names/outcomes, dice, ship position/velocity initialization, battle sizes/territory and hindered encounters |
| main.js | Wire price, stock purchase/generation/symbols/updates/sales, strategy choice, payoff grids and sales demand |

Four commented movement draws (combat.js:650-653) are excluded. Names and initial
ship motion consume the reference stream even when hidden/renamed.
This PR has not executed a game, measured draw counts, built a scheduler or
demonstrated Lua parity. Those remain issues #3/#4 and workshop slices.

## Runner handoff

Issue #3 adds the [deterministic Node runner](RUNNER.md) and recorded native-DOM
comparison. Source-byte provenance and reuse limits above still apply.
