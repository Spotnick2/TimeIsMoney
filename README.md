# Time Is Money

> A goblin company teaches an enchanted ledger to make bolts. The ledger gets very good at its job.

A single-player World of Warcraft: Forever addon mini-game based on Universal
Paperclips, presented as goblin industrial satire in Liquid Glass. Preserve three
phases, all 96 projects, recovery, prestige choices and terminal liquidation.
Company funds and materials are entirely simulated.

**Status: initialization scaffold; gameplay is not implemented.**
Commands: /timeismoney, /tim, /tim help, /tim status.

- [Roadmap and issue catalog](docs/BACKLOG.md).
- [Animated goblin Director](docs/MODELS.md), using AltStable's roster pet renderer.
- [References and evidence](docs/REFERENCES.md).
- [Agent instructions](CLAUDE.md), also reached through [AGENTS.md](AGENTS.md).

Target: Forever Interface 16001; API evidence build 1.60.1.70170; offline Lua 5.1.
Validate with **pwsh tests/run.ps1**; deploy with **pwsh Tools/deploy.ps1**.
Deployment defaults to the Forever _classic_beta_ AddOns folder. Restart after
first installing, enable script errors, then run /tim status.

The initialization PR is a draft. The owner-supplied design docs and both
storyboards still exist locally under docs/plan and docs/storyboard; upload them
byte-for-byte when local sandbox access is restored. Scaffold and package checks
are provided through CI. Live-client tests remain pending.

GitHub issues are the work queue; changes use PRs. The owner runs reviews and merges.
Original code is MIT; Paperclips reuse terms are not established by initialization.
