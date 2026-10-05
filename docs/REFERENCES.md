# References and provenance

## Authoritative owner-supplied design

[Implementation spec](plan/Time-Is-Money-Implementation-Spec.md) and
[creative brief](plan/Time-Is-Money-Original-Plan.md) are version 1.2, dated 2026-10-02.
Both original storyboards under [storyboard](storyboard) are illustrative concepts.
The four originals are committed byte-for-byte. [originals.json](originals.json)
records their source byte sizes and Git blob hashes; CI verifies them.

The implementation spec pins official Universal Paperclips, retrieved 2026-10-02.
Issue #2 reverified all five official files against these hashes; see
[reference evidence](reference/README.md) and the reproducible retrieval tool.
Upstream bytes remain in an ignored local cache. Hashes:

| Official file | SHA-256 |
| --- | --- |
| index2.html | 526b148a2eabe6543c4964e625fc3bba53984b2c294415fdec939b077478b9cb |
| main.js | ee599076de868869e533490505189ddcb72dcc8748909ceeebe11e789f1b3a0a |
| projects.js | 05034c51809bc0632e8963e671c8e68c68604ca3643da291e0c6fabc86152774 |
| globals.js | 968abd83c7090f24b6817842b4453b6d24de0e03e06d7ccb5ec4d15bee520919 |
| combat.js | c7226d012193c32a00bed53d7cb0119d4d3f91cb556b8e8d1b98dd3375be811a |

Edition: https://www.decisionproblem.com/paperclips/index2.html
Script order: combat.js -> globals.js -> projects.js -> main.js (page uses ?v3).
Secondary comparison only:
https://github.com/jgmize/paperclips/tree/d1e9177d02f7460363ebc7d28fe133228db18ed5
The older mirror differs in costs/conditions; never mix editions or silently repin.

Reuse/license permission remains unestablished after the bounded inspection in
[issue #2 evidence](reference/README.md). Applicable terms
must be established before vendoring/distributing translated implementation.
Repository MIT covers original code/compatible attributed copies, not Paperclips
or Blizzard art. Public source availability alone is not a reuse license.

Developer execution and native-DOM comparison: [reference runner](reference/RUNNER.md).

## Forever evidence supplied by the owner

| Local source | Scope |
| --- | --- |
| C:\Projects\References\forever-api-1.60.1.70205.md | Client API inventory: Interface 16001, WOW_PROJECT_ID 18; presence/signatures, not working behavior. Documented surface identical to 1.60.1.70170 (Compare-Dumps, #40). |
| C:\Projects\References\forever-consumables-1.60.1.70009.md | Client classID 0 consumables scan, not all items. Reaper kit 4391 and battery 274048 included. |
| C:\Projects\References\forever-recipes-2026-09-30.md | Wowhead snapshot; client availability can differ. Matches 12 of the brief's 14 identities. |
| C:\Projects\References\PORTING-TBC-TO-FOREVER.md | Canonical measured field notes, build-specific. Full client exit matters for persistence evidence. |

Keep shared sources external, not stale full duplicates. On other machines obtain
owner-supplied files before making compatibility claims. Addon-specific measurements:
forever-api-notes.md. Shared findings: canonical porting guide when access is authorized.

Build-matched Blizzard UI source (also pinned by the spec):
https://github.com/Gethe/wow-ui-source/tree/9a789c074b8e73c5d604ef2d6af3bb5b3aefb348

## Sibling patterns and project skills

Gnomesweeper: bootstrap/workflow and test/deploy idiom.
AltStable/GlassRaidFrames: evidence, packaging and maintenance conventions.
LibGlass-1.0 (Spotnick2/LibGlass) owns the Liquid Glass material, embedded at
Libs/LibGlass-1.0 (its docs/GLASS-MATERIAL.md section 5 is the embedding contract).
AltStable's roster pet renderer guides the animated Director; see MODELS.md.

Sibling original code: MIT, copyright 2026 Spotnick. Retain attribution when copied.
Review skill: project adaptation of the owner's installed wow-addon-review read
during initialization, packaged for both Codex and Claude with client/review references.
Both project copies are identical; the owner's global installation is not modified.
Consult/client-update skills adapt sibling workflows while retaining global cost limits.
