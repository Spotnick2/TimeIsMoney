# Backlog and milestone gates

GitHub issues are the work queue. This catalog records the initialization baseline;
update the issue body when a decision changes. Implement one bounded PR at a time.
The original implementation spec controls mechanics; the brief controls presentation.

All six GitHub milestone objects exist and issues #1–25 are attached. The
[initialization provisioning run](https://github.com/Spotnick2/TimeIsMoney/actions/runs/37068534961)
executed Tools/provision_backlog.ps1 with gh. The script remains idempotent and
preserves issue bodies and owner edits.

## M0 — Foundation

Repository, agent instructions/skills, issue-first PR workflow, minimal loadable addon, validation and packaging; no gameplay.

| Issue | Work |
| --- | --- |
| [#1](https://github.com/Spotnick2/TimeIsMoney/issues/1) | Project scaffold, instructions, skills, validation and packaging |

## M1 — Reference and workshop

Pinned reference and deterministic runner, then the pure-Lua workshop and first transition. Run early client/model smoke probes.

| Issue | Work |
| --- | --- |
| [#2](https://github.com/Spotnick2/TimeIsMoney/issues/2) | Pin official Universal Paperclips bytes and source provenance |
| [#3](https://github.com/Spotnick2/TimeIsMoney/issues/3) | Deterministic Node reference runner with browser host adapter |
| [#4](https://github.com/Spotnick2/TimeIsMoney/issues/4) | Shared random stream and first-divergence comparison |
| [#5](https://github.com/Spotnick2/TimeIsMoney/issues/5) | Pure-Lua workshop slice: bolts, input, prices, sales and first automation |
| [#6](https://github.com/Spotnick2/TimeIsMoney/issues/6) | Workshop computation, Ingenuity and resonance |
| [#7](https://github.com/Spotnick2/TimeIsMoney/issues/7) | Cartel investments and Negotiation Simulator |
| [#8](https://github.com/Spotnick2/TimeIsMoney/issues/8) | Workshop projects, recovery and Universal Customer Agreement |
| [#9](https://github.com/Spotnick2/TimeIsMoney/issues/9) | Early Forever smoke: runtime, icons and persistence |
| [#10](https://github.com/Spotnick2/TimeIsMoney/issues/10) | Animated goblin probe using AltStable roster pet rendering |

## M2 — Planetary conversion

Material pipeline, construction, power/storage, network thinking, exhaustion and expansion gate.

| Issue | Work |
| --- | --- |
| [#11](https://github.com/Spotnick2/TimeIsMoney/issues/11) | Planetary material pipeline and construction |
| [#12](https://github.com/Spotnick2/TimeIsMoney/issues/12) | Power, battery storage and fully powered acceleration |
| [#13](https://github.com/Spotnick2/TimeIsMoney/issues/13) | Company Network, thinking, recovery and expansion gate |

## M3 — Cosmic phase and endings

Dragonling/probe expansion, 16 ms combat, recovery, prestige, correspondence and terminal liquidation.

| Issue | Work |
| --- | --- |
| [#14](https://github.com/Spotnick2/TimeIsMoney/issues/14) | Dragonling allocations, replication, surveying, hazards and drift |
| [#15](https://github.com/Spotnick2/TimeIsMoney/issues/15) | Franchise battles at the reference 16 ms logical tick |
| [#16](https://github.com/Spotnick2/TimeIsMoney/issues/16) | Cosmic recovery, campaign projects and correspondence |
| [#17](https://github.com/Spotnick2/TimeIsMoney/issues/17) | Both prestige choices, negative Operations and full liquidation |

## M4 — Forever integration and presentation

Logical-clock host, versioned persistence, progressive Liquid Glass UI, assets, animated goblin Director and settings.

| Issue | Work |
| --- | --- |
| [#18](https://github.com/Spotnick2/TimeIsMoney/issues/18) | Forever host clock and command adapter |
| [#19](https://github.com/Spotnick2/TimeIsMoney/issues/19) | Versioned SavedVariables and continuation/migration |
| [#20](https://github.com/Spotnick2/TimeIsMoney/issues/20) | Progressive Liquid Glass ledger and campaign controls |
| [#21](https://github.com/Spotnick2/TimeIsMoney/issues/21) | Coin formatting and all 96 project/14 item presentation assets |
| [#22](https://github.com/Spotnick2/TimeIsMoney/issues/22) | Animated goblin Director and dialogue strip |
| [#23](https://github.com/Spotnick2/TimeIsMoney/issues/23) | Help, settings and explicit new-game control |

## M5 — Release acceptance

Complete traceability and current-build client/performance/save checks, release packaging and distribution.

| Issue | Work |
| --- | --- |
| [#24](https://github.com/Spotnick2/TimeIsMoney/issues/24) | Campaign parity, all-project coverage and current-build acceptance |
| [#25](https://github.com/Spotnick2/TimeIsMoney/issues/25) | First beta distribution, changelog and release packaging |

The original docs/storyboards are committed byte-for-byte, and Linux/Windows
checks plus temporary-folder deployment pass both in CI and on the owner's machine.
The local checkout is synchronized and codex mcp list confirms the docs server.
The owner recorded /tim help and /tim status on client 1.60.1.70170, Interface
16001, Lua 5.1. M0 setup gates are complete; see [M0-STATUS.md](M0-STATUS.md). Early
client and model probes are in M1; they need not wait for the full simulation port.
No milestones after M0 are implemented by initialization.
