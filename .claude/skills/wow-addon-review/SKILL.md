---
name: wow-addon-review
description: "Review committed changes in World of Warcraft addon repositories, including WoW Forever. Use for pull-request and code reviews when a TOC or project instructions establish the addon target; do not use for ordinary implementation work or generic Lua."
---

# WoW Addon Review

Project adaptation of the owner's installed shared review skill. Repository
instructions own project facts, commands, cost/approval limits and posting policy.

## Confirm target and scope

Identify product/content rules separately from API family, build, Interface,
embedded Lua/numbers, TOC load order, dependencies and SavedVariables. Forever is
Vanilla content on Mainline UI code; never reduce every addon to Retail or Classic.
For Forever read [forever.md](references/forever.md).
For client API/event/widget/persistence changes read
[client-evidence.md](references/client-evidence.md).

Review a PR's committed merge-base diff, not unrelated working-tree changes.
Verify repository/PR identity and reviewed head. Read surrounding callers and
load order. Preserve unrelated edits. Do not mutate code merely to fix a finding.

## Route substantive reviews

Recommend an appropriate model/effort before a substantive review; do not silently
switch. Routine substantive: gpt-6.1-sol/medium. Dense bounded logic:
gpt-6.1-sol/high. Broad/ambiguous cross-component: gpt-6-astra/medium.
Broad high-consequence security/data-loss/concurrency: gpt-6-astra/high.
Documentation-only or mechanical changes do not need that substantive baseline.

These are recommendations, not authorization. The owner's global default and
escalation policy take precedence: no stronger model/high effort without required
approval; never xhigh by default. Security scans are separate and require their
own explicit authorization. Do not automatically spawn agents or launch reviews.

## Inspect and validate

Apply [review-checklist.md](references/review-checklist.md) selectively. Prioritize
silent wrong behavior/data loss, client/load-order/protocol incompatibility, event/
cache/lifecycle/save defects, then missing meaningful regression coverage.
Style preferences/speculative architecture are not findings without a concrete defect.

Check changed APIs against the declared build evidence: arguments, optionality,
returns, event payloads, enum/widget ownership and availability. Stubs that repeat
an incorrect API assumption are not independent proof. Run proportionate repository
validation with declared Lua; check TOC and packaging changes. Distinguish API
declarations from measured client behavior and identify required in-game evidence.

## Report and post

Lead with actionable findings ordered by severity. Each needs file/line, reachable
failing scenario, target-client impact and minimal correction direction.
If none, explicitly state no findings and report validation/material limitations.
For every PR/follow-up review use exactly one verdict:
- Ready for merge: no required correction remains.
- Not ready for merge: list remaining required work.

Always post the requested review directly on the actual PR before returning, even
with no findings. Include reviewed commit, findings/no-findings, validation and
limitations, and exactly one verdict. Posting is authorized by the owner's standing
review instruction; no separate approval. Respect explicit local-only/no-post requests.
When the posting account does not identify Codex, start with "## Codex review" or
"## Codex follow-up review". Link the posted review in the final response.
If posting fails, state the blocker and provide the complete unposted review;
never claim it posted. Initialization does not itself request a review.
