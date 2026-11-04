# Releases (#25, #104, #109)

The owner tags and publishes; this page is the checklist and the evidence. The
shared guide is `C:\Projects\WoW\References\Docs\RELEASING.md`.

## Version

- **0.1.0** (2026-10-08) was the first release, while the Forever client was in
  beta. **1.0.0** follows the end of the beta (#109).
- Tag `vX.Y.Z` on main. The packager makes a *release* file from a tag that has no
  `alpha` or `beta` in it, and writes the tag into the TOC (`## Version:
  @project-version@` becomes `v1.0.0`; `/tim status` and the AddOns list show it).
- CHANGELOG.md is the upload's changelog (`.pkgmeta` `manual-changelog`). Each
  release gets a `## vX.Y.Z` heading before it is tagged: that section is also the
  GitHub Release notes and the Wago changelog (`tests/release_files.sh`).
- A release tag's prep PR updates README.md and the untracked README.curseforge.md
  (RELEASING.md section 3).

## The package

`.pkgmeta` packages the folder `TimeIsMoney` with LibGlass-1.0 embedded at its
pinned tag (r11). CI runs the pinned packager (`-d`, no upload) on every PR, push to
main and tag, then `Tools/check_package.py`: the archive holds exactly the TOC's
inputs, the embedded library's runtime files and media, the TOC and LICENSE, and the
version is substituted. It then builds `notes.md` and `release.json` from the
packaged TOC and the changelog.

Evidence for 0.1.0: the package-check run on main at c5aab0f (run 37822901849)
produced `TimeIsMoney-c5aab0f-forever.zip`: 66 entries, all addon runtime files,
LibGlass r4's runtime files and textures, TOC and LICENSE; no docs, tests, tools,
probe or agent files; `## Version: c5aab0f` (a tag gives `v0.1.0`).

## Publishing

A `v*` tag's package-check run publishes the zip `check` built and checked, never
rebuilt:
- `release`: a GitHub Release with the zip, `release.json` (for WowUp) and the tag's
  changelog section; alpha and beta tags are pre-releases.
- `wago`: the same zip on Wago Addons, project `RNL47eNo` (the packaged TOC's
  `X-Wago-ID`), for the patch the TOC's interface names (16001 is 1.60.1). It fails
  if Wago doesn't list that patch yet. The `WAGO_API_TOKEN` secret is set.
- CurseForge (project 1733557, `X-Curse-Project-ID`) builds its own file from the
  tag webhook.

A target that failed is published again from Actions > Package check > Run workflow,
from main, with `tag` and `publish: github|wago|both`. After a release, run the
checks in RELEASING.md section 4 (CurseForge's zip against CI's, `release.json`,
Wago's listing), then paste README.curseforge.md into CurseForge and Wago.

## Acceptance

docs/ACCEPTANCE.md: the simulation, host and save rows pass offline; the client
rows passed on 1.60.1.70245 (2026-10-07), and the owner checked the game again on
1.60.1.70338 (#100). The owner tried the later UI rounds (#77 to #93) in game.
Still open: the report sound (sound kit 120), the voice lines other than 550785,
and the taller scene and 2D portrait after #93 (docs/WINDOW.md).

## CurseForge (owner)

- The project is set up by the owner: **Time Is Money**, slug `time-is-money`
  (curseforge.com/wow/addons/time-is-money), project 1733557, with the round Gazlowe
  logo. Publishing is the owner's.
- `timeismoney`, without hyphens, is another project: a Retail gold tracker by Ryrin.
  The folder `TimeIsMoney` stays: that addon is Retail only, and Retail and Forever
  keep separate AddOns folders. The client names the saved-variables file after the
  folder, so a rename would be a save migration, not a packaging change.
- The packager never uploads from CI: CurseForge builds from its webhook, and only
  the `release` and `wago` jobs publish, from tags.
- The project page can use docs/images/showcase.png.
