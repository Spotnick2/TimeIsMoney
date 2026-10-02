# Time Is Money — Implementation Spec

**Version:** 1.2 — 2 October 2026  
**Companion:** [Creative Brief and Project Titles](Time-Is-Money-Original-Plan.md)  
**Status:** Planning and source inspection only; the Lua port, test harness, and client integration have not been built.

## 1. Target and compact contract

Build one local single-player company per WoW account in the supported Forever installation. Preserve the selected Universal Paperclips edition's state transitions and player decisions while applying the creative brief as a presentation layer.

The executable reference snapshot controls costs, thresholds, formulas, update order, randomness, project availability, and repeatability. Preserve all 96 project definitions, three phases, recovery routes, two prestige choices, negative-Operations route, and complete terminal liquidation. Keep original identifiers internally where practical. Descriptions are not authoritative when they disagree with executed effects; record quirks before deciding whether a later release should change them.

One reference paperclip unit maps to one Handful of Copper Bolts; one reference wire unit maps numerically to one simulated Copper Bar. The fictional item use does not import WoW crafting yields, cooldowns, or stack limits. Keep lifetime production, spendable stock, and unsold inventory distinct. The reference's business economy ends at its original transition.

### Consolidated non-goals

- Additional currencies, ore tiers, worker management, salaries, fuel costs, profession requirements, or item-crafting dependencies.
- Cosmic research branches, realm-specific yields, faction/reputation perks, quests, bosses, moral scores, or new endings.
- Manual combat, multiplayer economy, leaderboards, cross-device saves, or character-gold/inventory/Auction House integration.
- Offline production, a new prestige shop, or balance changes introduced during the faithful port.

## 2. Implementation approach: translate and compare incrementally

Start with this short contract and a state/host-dependency inventory, then port one subsystem at a time. A complete prose mechanics specification is not a prerequisite. Keep formulas, branches, and source identifiers close to the JavaScript until the differential tests pass; refactor later in separately verified changes.

Use three layers: a pure-Lua simulation; adapters for clock, RNG, commands, and persistence; and the Forever UI/presentation. The simulation must run outside WoW without frame or addon API calls. Lua 5.1 is the initial compatibility target with double-precision numbers. The supplied API dump identifies client build 1.60.1.70170, interface 16001, and WOW_PROJECT_ID 18; it does not establish the embedded Lua version or number configuration. Check those before treating a standalone interpreter as sufficient validation.

### Reference runner

Execute the pinned scripts in Node using a browser host adapter. The recorded HTML loads **combat.js → globals.js → projects.js → main.js**. Preserve that initialization order. Provide the DOM fields, browser globals, storage, and canvas interface actually touched by the source. A generic no-op DOM is insufficient when the code reads values back.

Replace real time and scheduling with a controlled logical clock. Capture interval/timeout registration, cancellation, and callback ordering, including stable ordering for equal due times. Advance both implementations through the same scheduled callbacks and timestamped player commands. Compare after each command and meaningful callback; an end-of-run total alone can hide an earlier divergence. Validate the adapter against browser behavior for representative paths; timer delays in a throttled browser are not a new balance target.

**Inspected source finding:** `combat.js` schedules an update every 16 ms. That update calls `UpdateGrid`, `MoveShips`, and `DoCombat`; combat changes probe counts, losses, and honor. Preserve the battle dynamics and their logical tick even with drawing disabled. A lower UI frame rate must not lower combat frequency. `main.js` also registers multiple intervals and delayed tournament callbacks, so one generic 'N ticks' counter is not an adequate clock model.

### Randomness

Feed both runners the same explicit random-number stream, initially from a recorded fixture. Log each draw's ordinal and call-site label so a different branch or extra draw is caught immediately. Later, a shared specified PRNG may generate that stream; matching seeds on JavaScript and Lua's native random functions is not enough.

The source consumes randomness in generated names and combat initialization as well as economic decisions. Preserve reference draw consumption during parity work, even for a renamed or hidden presentation feature. Keep any new cosmetic randomness on a separate stream so glass effects cannot change outcomes.

### State comparison and evidence

Compare resources, flags, repeat counts, active projects, allocations, portfolios, tournaments, combat entities, pending callbacks, prestige state, and ending progress. Maintain a versioned state schema and command API as they emerge from the port. Each test records the source hashes, initial fixture, commands, time trace, random stream, and first differing state field.

Require exact agreement for discrete state, branch outcomes, purchase eligibility, timer order, and random draw counts. Aim for exact numeric results where operations and evaluation order match. IEEE doubles alone do not guarantee bit-for-bit agreement for all math-library functions, formatting, or differently ordered calculations. Any numerical exception needs a narrow documented tolerance and a threshold test proving it does not alter decisions; do not use one broad epsilon to hide drift.

Tests demonstrate covered behavior, not a proof that every path is equivalent. Keep a concise traceability checklist linking every project and subsystem to its tests. Generate detailed project/cost documentation from the reference and tested implementation rather than duplicating it by hand.

## 3. JavaScript-to-Lua hazards

| Area | Porting requirement |
| --- | --- |
| Truthiness | Translate JS false-like values explicitly where relevant. Lua considers `0` and `""` true. Audit defaulting idioms and conditions instead of mechanically replacing operators. |
| Arrays | Lua permits key `0`. Keeping reference indices can reduce translation errors, but requires explicit lengths/loops; `#`, `ipairs`, and list helpers do not implement JS array semantics. Audit holes, splices, sort ties, and deletion. |
| Remainder | JS uses a quotient truncated toward zero; Lua 5.1 `%` uses floor. For example, `-5 % 3` is `-2` in JS and `1` in Lua. Use a compatibility helper at affected operations. Negative Operations require tests, but their existence alone does not prove a particular modulo path is affected. |
| Rounding and strings | Audit `Math.round`, `floor`, `ceil`, `toFixed`, numeric coercion, string concatenation, and formatting separately. `toFixed` returns text. Match calculation behavior and keep display changes outside state updates. |
| Numeric edge cases | Check zero, negative zero, NaN/infinity, huge totals, exponentiation, trig functions, and values near purchase/unlock boundaries. Confirm the Lua build uses doubles. |
| Iteration and mutation | Preserve reference traversal and mutation order where it affects decisions or random draws. Do not replace an ordered loop with unordered table traversal. |
| Save representation | Handle missing values, arrays, and non-finite values deliberately. A serializer must not silently change types or collapse state. |

Language references: [Lua 5.1 manual](https://www.lua.org/manual/5.1/manual.html), [Lua logical operators](https://www.lua.org/pil/3.3.html), [Lua arrays](https://www.lua.org/pil/11.1.html), [ECMAScript numeric operations](https://tc39.es/ecma262/multipage/ecmascript-data-types-and-values.html#sec-numeric-types-number-remainder), [ECMAScript conversions](https://tc39.es/ecma262/multipage/abstract-operations.html#sec-toboolean), and [ECMAScript numbers/math](https://tc39.es/ecma262/multipage/numbers-and-dates.html). These support the compatibility checks; target-client behavior still needs testing.

## 4. Money presentation

Retain the reference money value as a number. **One reference monetary unit equals one silver.** Derive gold/silver/copper for display; do not convert persistent simulation arithmetic to integer copper.

| Reference value | Primary display |
| --- | --- |
| 0.25 | 25c |
| 1 | 1s |
| 123.45 | 1g 23s 45c |
| 1,000,000 | 10,000g |

Use Forever coin icons with readable text equivalents. Display rounding never controls affordability, interest, prices, or sales. Preserve fractions of a copper internally; expose extra precision in a tooltip when rounding could obscure a threshold. Formatting must handle large and negative values without wrapping or losing the sign. Preserve any rounding that the reference itself applies to state; this section changes presentation only.

## 5. Forever assets: validate early, finalize for release

The creative brief contains the 14 initial item identities. Treat beta entries as provisional and record the build tested. An item ID is not a texture handle, and a database entry alone is not an in-client rendering test.

### Evidence supplied for this revision

| Source | Evidence and scope |
| --- | --- |
| `forever-recipes-2026-09-30.md` | A 2,496-recipe Wowhead snapshot. It matches recipe-to-item IDs for 12 selected items, including the Forever-only battery recipe 1293088 → item 274048. It is not a client recipe scan; the file explicitly documents discrepancies with client availability. |
| `forever-consumables-1.60.1.70009.md` | Client scan of named classID 0 consumables, not all game items. Includes Harvest Reaper Kit 4391 and Battery Pack 274048 with their item spells. Absence from this file does not disprove an engineering part's existence. |
| `forever-api-1.60.1.70170.md` | Client-generated function/event/widget inventory, dated 1 October 2026. Signatures and presence are evidence; the file explicitly warns that exposed functions may lack working behavior. |
| [Gethe's Forever UI source](https://github.com/Gethe/wow-ui-source/tree/9a789c074b8e73c5d604ef2d6af3bb5b3aefb348) | Pinned commit `9a789c074b8e73c5d604ef2d6af3bb5b3aefb348`, labelled `1.60.1 (70170)`, matching the API dump. It supplies client UI code and generated API declarations, not the client's full binary artwork or engine internals. |

### Concrete adapter candidates

The API dump and pinned generated documentation agree on these entry points:

| Need | Candidate | Handling requirement |
| --- | --- | --- |
| Item icon | `C_Item.GetItemIconByID(itemID)` | Return is an optional texture file ID; handle nil and verify rendering. |
| Immediate item classification/icon | `C_Item.GetItemInfoInstant(itemID)` | The icon is the fifth return when data exists; the repository declaration allows no result. |
| Full item data | `C_Item.GetItemInfo(itemID)` | Handle missing data rather than requiring ownership of the item. |
| Asynchronous loading | `C_Item.RequestLoadItemDataByID(itemID)` and `ITEM_DATA_LOAD_RESULT(itemID, success)` | Register the listener before requesting; retry the relevant lookup after success. Bound retries and keep a supported fallback. |
| Native coin text | `C_CurrencyInfo.GetCoinTextureString(amount, fontHeight)` | Use a whole-copper display value within tested limits. Preserve fractional/internal state and provide formatting for unsupported large/negative values. |
| Host wakeups | `C_Timer.After`, `C_Timer.NewTicker`, `C_Timer.NewTimer` | Feed the controlled simulation scheduler; do not rely on native callback interleaving to reproduce the reference. |
| Elapsed time and build | `GetTime`, `GetTimePreciseSec`, `GetBuildInfo` | Present in the client dump. Verify behavior and record the runtime build during smoke tests. |

Inspected repository files: [ItemDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/9a789c074b8e73c5d604ef2d6af3bb5b3aefb348/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua), [CurrencyInfoDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/9a789c074b8e73c5d604ef2d6af3bb5b3aefb348/Interface/AddOns/Blizzard_APIDocumentationGenerated/CurrencyInfoDocumentation.lua), and [UITimerDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/9a789c074b8e73c5d604ef2d6af3bb5b3aefb348/Interface/AddOns/Blizzard_APIDocumentationGenerated/UITimerDocumentation.lua). There is no need to guess legacy API names from the game's visual era.

### Validation schedule

**Now:** build a small client smoke test for one long-established item icon, one Forever-specific item such as the 9-60 Battery Pack, a profession/spell icon, an optional portrait/model, and save/reload. This checks assumptions cheaply while simulation work proceeds.

**During UI integration:** complete the icon mapping for all 96 project IDs using existing Forever assets. Abstract concepts can use appropriate profession, spell, document, coin, or UI art. Model rendering is optional; icons are the baseline. Reuse family icons where appropriate.

**Release build:** rerun the complete asset and addon-API smoke tests, resolve missing/changed entries, and record the verified build. Repeat affected checks after later patches. Do not defer all compatibility discovery until launch, and do not freeze beta-only references as permanent.

The presentation catalog records role/project ID, source item/spell/NPC ID, source URL, display name, resolved asset reference, tested build, and status: database-listed, client-verified, or fallback-required. A missing preferred asset gets another verified Forever asset. The custom Liquid Glass layout remains independent of those content assets.

## 6. Persistence and runtime behavior

Use versioned SavedVariables state covering resource pools, allocations, project state, phase, scheduler/subsystem progress needed for continuation, RNG state if applicable, prestige, and endings. Never serialize frames or closures as game state. Migrations must preserve recoverable data and reject unsupported future schemas without overwriting them with defaults.

Updating a Lua table during play is not the same as flushing it to disk. The player-facing contract is normal logout or `/reload`; a crash or forced close may lose changes since the last successful write. Do not advertise 'clean disconnect' as a guaranteed save point or show 'saved to disk' merely because an in-memory snapshot was made. Confirm actual persistence on the target Forever build.

Use the brief's short persistence message in first-use help and settings. A player-invoked reload remains a normal WoW action; no automatic reload interrupts gameplay. A future backup/export feature would be a separate scope decision.

The simulation continues consistently while its window is hidden. Combat may collapse the panel without selectively pausing production or losses. Reopening must not create duplicate timers. UI refresh frequency is independent of logical simulation frequency. Closing WoW stops this baseline simulation; no elapsed-time production is applied on reopening.

Compare save/load continuation with uninterrupted simulation where state restoration is defined, including tournament and battle progression, project purchases, prestige, and ending steps. Preserve the reference's special final-unit accounting rather than trusting ordinary huge-number addition to display the last few units.

## 7. Development sequence and acceptance gates

1. **Pin the reference and build the runner.** Confirm hashes, script order, host inputs, logical scheduling, and random-stream injection. Inventory mutable state and command boundaries.
2. **Port and compare the workshop.** Translate production, price/demand, inputs, automation, computation, projects, investments, strategy, resonance, and the first transition. Add differential fixtures as each subsystem lands.
3. **Port and compare planetary conversion.** Cover the input chain, construction, power, network thinking, exhaustion, recovery, and expansion gate.
4. **Port and compare the cosmic phase.** Cover allocations, replication, hazards, drift, battle dynamics, recovery, prestige, correspondence, and final manual production.
5. **Integrate the Forever host.** Connect commands, logical time, saved state, and basic frames. Run the early compatibility smoke test as soon as a minimal addon can load; it need not wait for steps 2–4 to finish.
6. **Apply the creative brief and assets.** Add names, dialogue, coin presentation, progressive Liquid Glass UI, and the project icon mapping. Validate that presentation does not alter results.
7. **Run release acceptance.** Recheck the current client build, deterministic fixtures, restore paths, hidden-window performance, and both endings. Record the source/runtime versions and unresolved exceptions.

Minimum meaningful acceptance suite:

- Fixed command/time/random traces for each subsystem and both phase transitions; log the first divergence.
- Coverage for all 96 project definitions, including conditional, optional, repeatable, and recovery entries. Each verifies eligibility, cost/effect, flags, and availability changes as applicable.
- Boundary cases: depleted stock, unaffordable purchase, exact costs, exhausted matter, power shortage/full storage, negative Operations, losing the fleet, and huge totals.
- Both prestige routes and all terminal liquidation steps, including the final manual action.
- Save/reload continuation, schema migration, no repeated rewards, no duplicated timers, and no state change caused by window visibility or UI frame rate.
- In-client tests for normal logout, `/reload`, and a controlled interrupted-session recovery check using disposable test data. Do not promise a crash will write current state.
- Asset rendering and readable coin/large-number formatting in the supported Forever build.

## Appendix — Pinned reference

Authoritative edition: [official Universal Paperclips](https://www.decisionproblem.com/paperclips/index2.html), retrieved on 2 October 2026. These local reference bytes were rechecked against their recorded hashes for this revision. Live URLs can change; hashes identify the edition.

| Official file | SHA-256 |
| --- | --- |
| `index2.html` | `526b148a2eabe6543c4964e625fc3bba53984b2c294415fdec939b077478b9cb` |
| `main.js` | `ee599076de868869e533490505189ddcb72dcc8748909ceeebe11e789f1b3a0a` |
| `projects.js` | `05034c51809bc0632e8963e671c8e68c68604ca3643da291e0c6fabc86152774` |
| `globals.js` | `968abd83c7090f24b6817842b4453b6d24de0e03e06d7ccb5ec4d15bee520919` |
| `combat.js` | `c7226d012193c32a00bed53d7cb0119d4d3f91cb556b8e8d1b98dd3375be811a` |

The page requests the four gameplay scripts with `?v3`. The files' executed state controls behavior, not initial HTML placeholders. This revision inspected the timer and combat coupling; it did not execute a complete reference playthrough or parity test.

Secondary comparison only: [jgmize/paperclips](https://github.com/jgmize/paperclips/tree/d1e9177d02f7460363ebc7d28fe133228db18ed5). That older snapshot differs in costs and conditions; do not mix it into the pinned edition. For example, official `project27` uses 3,000 Yomi while the mirror uses 1,000, and official `project126` uses 36,000 while the mirror uses 12,000. Original source identifiers remain useful even when the UI calls Yomi 'Cunning'.

**First implementation handoff:** build the deterministic reference runner and a pure-Lua workshop slice with unchanged source identifiers. Demonstrate matching traces for manual production, purchasing input, prices/sales, and first automation before scaling the port. Add detailed reference documentation where tests expose a decision, rather than requiring a separate exhaustive mechanics document up front.
