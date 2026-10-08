# Releases (#25)

The owner tags and publishes; this page is the checklist and the evidence.

## Version

- **0.1.0** is the first release: a release, not a beta. It runs on the Forever
  client, which is itself in beta, so it is not 1.0.
- Tag `v0.1.0` on main. The packager makes a *release* file from a tag that has no
  `alpha` or `beta` in it, and writes the tag into the TOC (`## Version:
  @project-version@` becomes `v0.1.0`; `/tim status` and the AddOns list show it).
- CHANGELOG.md is the upload's changelog (`.pkgmeta` `manual-changelog`). Each
  release gets a heading for its version before it is tagged.

## The package

`.pkgmeta` packages the folder `TimeIsMoney` with LibGlass-1.0 embedded at its
pinned tag (r4). CI runs the pinned packager (`-d`, no upload) on every PR and push
to main, then `Tools/check_package.py`: the archive holds exactly the TOC's inputs,
the embedded library's runtime files and media, the TOC and LICENSE, and the
version is substituted.

Evidence for 0.1.0: the package-check run on main at c5aab0f (run 37822901849)
produced `TimeIsMoney-c5aab0f-forever.zip`: 66 entries, all addon runtime files,
LibGlass r4's runtime files and textures, TOC and LICENSE; no docs, tests, tools,
probe or agent files; `## Version: c5aab0f` (a tag gives `v0.1.0`).

## Acceptance

docs/ACCEPTANCE.md: the simulation, host and save rows pass offline; the client
rows passed on 1.60.1.70245 (2026-10-07). The owner tried the later UI rounds (#77
to #93) in game. Still open: the report sound (sound kit 120), the voice lines
other than 550785, and the taller scene and 2D portrait after #93 (docs/WINDOW.md).

## CurseForge (owner)

- The project is set up by the owner: **Time Is Money**, slug `time-is-money`
  (curseforge.com/wow/addons/time-is-money), unlisted until the owner lists it,
  with the round Gazlowe logo. Publishing is the owner's.
- `timeismoney`, without hyphens, is another project: a Retail gold tracker by Ryrin.
  The folder `TimeIsMoney` stays: that addon is Retail only, and Retail and Forever
  keep separate AddOns folders. The client names the saved-variables file after the
  folder, so a rename would be a save migration, not a packaging change.
- This repository's CI is read-only and never uploads.
- The project page can use docs/images/showcase.png.
