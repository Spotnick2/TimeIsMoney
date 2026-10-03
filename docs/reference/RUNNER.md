# Deterministic reference runner

Issue [#3](https://github.com/Spotnick2/TimeIsMoney/issues/3). This is developer
tooling, not addon gameplay. It executes the [pinned edition](README.md) unchanged
in Node's VM, in combat -> globals -> projects -> main order, and compares
representative traces with the same files in a native browser DOM.

## Run and reproduce

The measured numerical profile is Windows with Node 24 and its built-in VM/test
runner, existing Python 3, and an installed
Chromium browser for native checks. There are no npm dependencies or browser
downloads. Local measurements used Node v24.15.0, Python 3.13.13 and
HeadlessChrome 154 on Windows; the evidence records the observed versions.
The Windows CI job runs on the owner's self-hosted runner (labels self-hosted,
Windows, tim), using its installed Node 24, Python, Chrome and MSVC. It fails if
Node is not version 24; it does not download another runtime.

~~~powershell
python Tools/paperclips_reference.py fetch
node --test tests/reference/runner.test.cjs tests/reference/divergence.test.cjs
node Tools/reference/check_browser.cjs
~~~

The first command retrieves only the five officially pinned inputs into the
ignored .tmp-paperclips/ cache. The runner rechecks raw hashes/sizes and inventory
pins before executing. It does not substitute another edition. Set TIM_PYTHON
if Python is not named python. Set TIM_BROWSER to an
existing Chromium executable if the usual Chrome/Edge paths do not apply.

To create a fixture input and print a trace report:

~~~powershell
node -e "const fs=require('node:fs'), f=require('./tests/reference/traces.cjs'); fs.writeFileSync('.tmp-paperclips/workshop-trace.json',JSON.stringify(f.make('workshop')));"
node Tools/reference/runner.cjs .tmp-paperclips/workshop-trace.json
~~~

The report is a trace document (schema 2): source hashes, fixture globals,
commands/times, random-stream and input hashes, callback/command checkpoint hashes,
the ordered event log (registrations, cancellations, callbacks, labeled draws and
checkpoints), per-site draw counts with inventory scopes and the final state hash.
`--full` also embeds each checkpoint's JSON so a comparison can name the first
differing field. Reports stay in the ignored cache; they are not committed copies
of the game's source/presentation.

## Host behavior

- Parse the verified HTML through Python's standard-library HTMLParser into a
  local tree. Node models real element identity, attributes, inline handlers,
  parent/child relationships, insertion/removal, text/innerHTML, style, disabled
  click behavior, option selection and the range input used by the source.
  Missing IDs return null. Initial HTML IDs also supply the named window bindings
  read by the original scripts; ordinary script globals can shadow them.
  The range adapter supports the pinned 0..200 unit-step slider. Decimal input
  follows browser rounding (ties upward), clamping and invalid-value midpoint
  fallback; other range configurations fail explicitly. See the
  [HTML range-value rules](https://html.spec.whatwg.org/multipage/input.html#range-state-(type=range)).
- Storage has browser string/null semantics and contains JSON values from the
  reference's own save/load routines. The snapshot reads the resulting stored
  JSON, not a made-up no-op save. It is not a WoW SavedVariables schema.
- Canvas models dimensions and the 2D calls exercised by the game. Node records
  drawing calls without rasterizing. Drawing suppression is independent of
  UpdateGrid, MoveShips and DoCombat. Browser checks use a real canvas; the
  no-drawing case suppresses fillRect only.
- Audio is a controlled host with src, deduplicated canplaythrough listeners,
  an explicit media-ready fixture command, and play calls. No music is retrieved.
  Native audio loading/playback is not established by these tests.
- Restart confirmation/reload throw unless a future explicit host decision
  handles them. The harness does not silently accept or restart a run.
- VM isolation organizes the trusted pinned scripts' globals; it is not claimed
  to be a security sandbox for arbitrary input.

The DOM model is deliberately bounded to the source and exercised paths. Its
parser does not implement all HTML tree-repair rules, CSS/layout or browser
event propagation. Unsupported paths can fail; missing lookups are not replaced
with fabricated elements. Native comparisons below establish covered behavior,
not full browser or full-campaign equivalence.

## Logical clock and command policy

The source's seven startup intervals retain registration and callback order,
including the 16 ms combat update. Register every timeout/interval with an ID,
delay, due time and stable queue ordinal. Fire by due time then ordinal.
An interval is requeued after its callback; cancellation prevents requeue.
Timeouts scheduled during a callback join the queue after already due work.
Both clear APIs cancel from the same timer map.

Time moves only through advanceTo. No wall-clock tick, background browser delay
or addon UI refresh drives production. Trace commands are in nondecreasing
timestamp order; **already-due callbacks run before a command at that timestamp**.
Commands at the same timestamp retain input order. Backward time, excessive
callbacks, an unknown command or exhausted random input fails explicitly.

This is a specified logical schedule for the pinned scripts, not a reproduction
of real-world browser throttling. The pinned delays are all at least 10 ms;
general string timers, delay coercion and nested sub-4-ms clamping are outside
the harness. Synthetic clock tests cover same-due ordering, nested registration,
callback this/arguments, shared cancellation and runaway termination. The native
probe independently checks registration order and cancellation with real
zero-delay browser timers; its expected sequence is first, second.

## Fixtures, snapshots and randomness

tests/reference/traces.cjs expands an explicit eight-value repeat pattern into
a **finite 60,000-value fixture stream**. It is not a seeded PRNG or native RNG;
it does not wrap when exhausted. Initialization consumes 3,200 values through
the constructor and initialization ship resets before later scripts load.
Every checkpoint records consumed draws. The specified shared PRNG that may later
generate such streams is still undesigned; matching JavaScript and Lua native
seeds would not be enough.

Issue [#4](https://github.com/Spotnick2/TimeIsMoney/issues/4) labels every draw.
The simulation stream logs a zero-based ordinal, logical time, value and call site
as file:line:column of the first frame outside host.js (URL queries removed, so
VM filenames and served scripts agree). Reports add the
[inventory](inventory.json) scope for each site. Every observed site is
inventoried. The traces cover combat initialization (Ship, createBattle),
generated names (generateBattleName, generateSymbol/createStock), market,
sales, tournament and grid draws. All source Math.random calls, names included,
are simulation draws because the port must preserve their consumption.

A separate **cosmetic** stream has its own ordinals and log and never enters the
simulation event log. The pinned source has no cosmetic draws; the stream exists
so later presentation effects cannot shift outcomes. A test draws cosmetic values
during a command and gets the identical simulation trace.

tests/reference/RecordedRandom.lua is the Lua side of the same contract. It reads
the recorded stream document `{"schema":1,"stream":...,"values":[...]}`, labels
each draw, refuses exhaustion and emits the same draw events. A Node test runs it
under Lua 5.1 (TIM_LUA, default C:\Program Files (x86)\Lua\5.1\lua.exe). Edge
doubles convert identically, and an extra Lua draw is found at its ordinal. It is
developer tooling, not addon runtime code; the shipped RNG adapter and the Lua
simulation that calls it belong to the workshop slices.

A fixture can set known globals, project flags or strategy selection after
ordinary source initialization. This is explicitly seeded developer state,
not a new player command or balance rule. Timestamped commands click real
controls, change existing values, or call a small allowlist of source helpers
for covered host paths. Disabled clicks do not execute effects. Console cheats
are not allowed commands. Element arguments use an explicit ID reference.

Snapshot after initialization, fixture setup, **every callback**, each command
and the final time. Compare indexed global state and ordered arrays, project
flags/uses and active IDs, portfolio/strategy/combat state, relevant DOM values,
JSON storage, pending timer metadata and draw counts. Preserve NaN/infinity,
negative zero, undefined and array holes explicitly. Skip functions, native
host objects and project presentation text; no closures are serialized.
The snapshots are inspection evidence, not a resumable save format.

Exact numerical hashes are tied to this measured profile. A preliminary Ubuntu
hosted-runner comparison failed at workshop checkpoint 46, in state.p10f:
Node produced 190931795304.0943 and native Chrome produced
190931795304.09433 (one binary64 step, 0.000030517578125).
This is the sum of ten Math.pow-based factory costs, not a DOM/timer discrepancy.
[The diagnostic CI run](https://github.com/Spotnick2/TimeIsMoney/actions/runs/37079870514)
records the first field and both values. ECMAScript specifies
[implementation-approximated exponentiation](https://tc39.es/ecma262/2025/multipage/ecmascript-data-types-and-values.html#sec-numeric-types-number-exponentiate).
The runner preserves each runtime's arithmetic rather than replacing Math.pow,
rounding persistent state or applying a broad epsilon. Exact Windows comparisons
remain required; these traces do not establish exact arithmetic on Linux or other
JS engines. The comparator reports a numeric difference's distance in doubles
(state.p10f above is 1) as evidence. By default it **accepts no tolerance**. A
caller may pass `tolerances`: exact checkpoint field paths, each with a maximum
distance in doubles and a reason. Every accepted difference is reported through
`onTolerated`, and later differences are still found. An exception needs a
documented bound and a threshold test showing that no decision changes. The only
current use is the workshop's two display fields ([WORKSHOP.md](WORKSHOP.md)).

## First-divergence comparison

`node Tools/reference/compare.cjs <left.json> <right.json>` compares two trace
documents from any runner (for example two `runner.cjs --full` reports). It exits
0 when they agree, 1 at a divergence and 2 on bad input. The same compareTraces
function in host.js runs in Node, in the native-browser probe and on the
evidence server.

Each document must have schema 2. Each checkpoint must have exactly one
checkpoint event, in index order, so walking the events visits every checkpoint.
A checkpoint compares by SHA-256 when both sides have one, otherwise by JSON.
A pair with neither in common is refused (exit 2), not reported as a state
divergence. Arrays never equal objects with the same keys, array lengths must
match, and differing hashes are reported even if the field walk finds nothing. Source hashes compare by file, regardless of key order, and different
hashes stop the comparison. Otherwise events are compared in order, so the
earliest difference wins:

- **draw**: an extra, missing or relabeled draw, or a different value, at its
  ordinal. The scopes of both sites are included.
- **timer**: a different registration, cancellation or callback (for example
  the same due time firing in a different order).
- **checkpoint**: different checkpoint metadata, such as a command or callback ID.
- **state**: the first differing checkpoint field, with its category (resource,
  flag, array, project, entity, value, pending-callback, draw-count, host-dom or
  reference-storage) and distance in doubles. Hash-only documents report the
  checkpoint and both hashes. The browser probe then fetches the Node JSON for
  that checkpoint and names the field.
- **length**: one trace ends early.

Each result includes both source hashes and inputs (fixture, commands, end time,
random/trace hashes), the last matched checkpoint and the eight preceding events
on each side. host.js TRACE_SCHEMA (version 2) lists the emerging event fields,
checkpoint sections, command forms and categories. It will grow as the port adds
state; it is not a SavedVariables schema.

tests/reference/divergence.test.cjs injects deliberate divergences into one
runner. Each is reported at the first differing point:

| Injection | Reported as |
| --- | --- |
| Extra draw inside the buyWire click handler | draw at ordinal 3,200, the injected.js site against the reference's next event |
| Skipped adjustWirePrice branch | draw at main.js:704:14 (adjustWirePrice); the next reference draw arrives one ordinal early |
| clipClick making one extra clip (no draws) | state $.state.clips (resource), 1 against 2, at the btnMakePaperclip checkpoint |
| Reversed tie-break for equal due times | timer: callbacks 1 and 6 swap at t=80 |
| Changed checkpoint, hashes only | state at checkpoint 5 with both hashes; with JSON, $.state.funds |

A temporary local probe that added the same extra draw in native Chrome reported
the same event and ordinal. That probe is not committed.

## Measured native-browser acceptance

[browser-evidence.json](browser-evidence.json) records source/tool/input hashes,
runtime versions, checkpoint and event totals, draw consumption, the event-log
hash (timer events plus labeled draws), final hashes and native timer-order
results. The automated probe serves verified bytes on loopback,
removes analytics/style/art requests, injects the logical host before gameplay,
and executes all four gameplay scripts unchanged with a **native DOM**.
It uses the same clock/random fixture so the comparison isolates host/VM
behavior. It does not independently prove native wall-clock timing.

| Case | Checkpoints matched | Covered behavior |
| --- | ---: | --- |
| initialization | 32 | Both ship resets, seven intervals, equal-due callbacks and initial host values |
| workshop | 73 | Manual production/input, first automation and project, price/risk selection, dynamic button removal and reference save/load |
| cancellation | 106 | A blink interval fires twelve times, cancels itself, restores visibility and stays cancelled |
| tournament | 285 | Selection, operations charge, alternating 50 ms callbacks, completion, results and Yomi reward |
| range | 165 | Eight slider assignments: fractional tie/down rounding, empty/hex/newline fallback, bounds, exponent input and subsequent swarm read-back |
| investment | 597 | Deposit, stockShop purchase, stock-symbol name generation and 19,362 labeled draws |
| combat | 325 | 100 combat updates at 16 ms, ship/grid motion and nine million probe losses |
| combat-nodraw | 325 | Same complete state and draws as combat with drawing suppressed |

All 1,908 callback/command/setup/final checkpoints and all 46,398 events matched
in the recorded run. The events include every draw's call-site label. Twelve
first-divergence tests and fifteen runner tests on the Windows profile cover:
deterministic repeats; native final-state and event-log expectations; timer rules;
DOM lifecycle/selection; range sanitization/read-back; storage; numeric encoding;
drawing independence; input exhaustion; and evidence consistency. The Windows CI
job retrieves sources and runs the native-browser comparison, then builds Lua 5.1
and runs the Node checks (the Lua stream test needs Lua) before its Lua/deploy
checks. Linux keeps its original-byte, provenance, Lua (including
test_recorded_random.lua), tooling and package checks.

No in-game addon behavior, Lua simulation, gameplay UI, persistence schema,
full-campaign parity, media playback or native browser timing guarantee is
implemented here. Upstream reuse terms remain unestablished; upstream bytes
remain ignored local/CI developer inputs and are absent from the addon archive.
The Lua workshop slice ([WORKSHOP.md](WORKSHOP.md), #5) emits this trace format
and is compared exactly against a projection of the reference document.
