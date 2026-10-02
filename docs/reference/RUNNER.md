# Deterministic reference runner

Issue [#3](https://github.com/Spotnick2/TimeIsMoney/issues/3). This is developer
tooling, not addon gameplay. It executes the [pinned edition](README.md) unchanged
in Node's VM, in combat -> globals -> projects -> main order, and compares
representative traces with the same files in a native browser DOM.

## Run and reproduce

Use Node 20+ with its built-in VM/test runner, existing Python 3, and an installed
Chromium browser for native checks. There are no npm dependencies or browser
downloads. Local measurements used Node v24.15.0, Python 3.13.13 and
HeadlessChrome 154 on Windows; the evidence records the observed versions.
CI uses the hosted runner's existing Node/Python/Chrome installation.

~~~powershell
python Tools/paperclips_reference.py fetch
node --test tests/reference/runner.test.cjs
node Tools/reference/check_browser.cjs
~~~

The first command retrieves only the five officially pinned inputs into the
ignored .tmp-paperclips/ cache. The runner rechecks raw hashes/sizes and inventory
pins before executing. It does not substitute another edition. Set TIM_PYTHON
if Python is not named python; CI sets it to python3. Set TIM_BROWSER to an
existing Chromium executable if the usual Chrome/Edge paths do not apply.

To create a fixture input and print a trace report:

~~~powershell
node -e "const fs=require('node:fs'), f=require('./tests/reference/traces.cjs'); fs.writeFileSync('.tmp-paperclips/workshop-trace.json',JSON.stringify(f.make('workshop')));"
node Tools/reference/runner.cjs .tmp-paperclips/workshop-trace.json
~~~

The report includes source hashes, fixture globals, commands/times, random-stream
and input hashes, callback/command checkpoint hashes, registrations/cancellations,
draw counts and the final state hash. Full checkpoint JSON remains available in
the runner API and in the local browser diagnostic endpoint for first-field
differences. It is not committed as a copy of the game's source/presentation.

## Host behavior

- Parse the verified HTML through Python's standard-library HTMLParser into a
  local tree. Node models real element identity, attributes, inline handlers,
  parent/child relationships, insertion/removal, text/innerHTML, style, disabled
  click behavior, option selection and the range input used by the source.
  Missing IDs return null. Initial HTML IDs also supply the named window bindings
  read by the original scripts; ordinary script globals can shadow them.
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
Every checkpoint records consumed draws. Call-site labeling, shared PRNG design
and Lua first-divergence comparisons remain issue #4.

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

SHA-256 checks locate a divergent checkpoint; the browser diagnostic then
compares parsed state and reports the first differing field. The six current
cases compare all checkpoints exactly, with no numerical tolerance.

## Measured native-browser acceptance

[browser-evidence.json](browser-evidence.json) records source/tool/input hashes,
runtime versions, checkpoint totals, draw consumption, final hashes and native
timer-order results. The automated probe serves verified bytes on loopback,
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
| combat | 325 | 100 combat updates at 16 ms, ship/grid motion and nine million probe losses |
| combat-nodraw | 325 | Same complete state and draws as combat with drawing suppressed |

All 1,146 callback/command/setup/final checkpoints matched in the recorded run.
Thirteen Node tests cover deterministic repeats, native final-state expectations,
timer rules, DOM lifecycle/selection, storage, numeric encoding, drawing
independence, input exhaustion and evidence consistency. CI repeats source
retrieval, Node checks and the native-browser comparison before existing
Lua/Windows/package checks.

No in-game addon behavior, Lua translation, gameplay UI, persistence schema,
full-campaign parity, media playback or native browser timing guarantee is
implemented here. Upstream reuse terms remain unestablished; upstream bytes
remain ignored local/CI developer inputs and are absent from the addon archive.
Issue #4 and the workshop slices are the next implementation work after review
and merge.
