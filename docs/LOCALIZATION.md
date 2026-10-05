# Localization (#22)

Every player-facing line in the Director's strip is a key, looked up in the active
locale. That covers the dialogue beats, the company's reports, the speakers, the
durations and counted nouns, and the credits line. The reference's English messages
stay in the simulation and in saves only; the window never shows them.

## How it works

- **Locales** (`UI/Locale.lua`) register a string table. `Locale.Use(GetLocale())`
  picks the client's locale when one is registered, otherwise English.
  - Each missing key falls back to English, so a partial translation never shows a
    hole.
  - A missing English key shows as `[key]`, and the tests check every key exists.
- **Placeholders are named:** `{count}`, `{time}`, `{name}`… A translation can put
  them in any order. Values are inserted as written: a `%` or `{` in a value is
  never read as a placeholder.
- **Plurals:** a key with plural forms is written `key.one`, `key.other`, and
  optionally `key.few`, `key.many`… A locale gives its own rule as
  `plural = function(n) return category end`. English uses `one` for 1, otherwise
  `other`.
- **Numbers** inside reports take the locale's `group` and `decimal` separators
  (English `,` and `.`).
- **Reports** (`UI/Messages.lua`) map each message the simulation posts, byte for
  byte, to a key, or match it with a pattern whose captures become named values.
  - Durations from the simulation's English `timeCruncher` are re-read and written
    in the locale, each unit in the plural form its count takes there.
  - The original game's credits stay as written, inside the localized
    `credits.line`.

## Adding a locale

1. Create `UI/Locale_xxXX.lua` that calls `ns.Locale.Register("xxXX", { ... })`
   with any subset of the English keys in `UI/Locale_enUS.lua`. Add `plural`,
   `group` and `decimal` if they differ from English.
2. List it in `TimeIsMoney.toc` after `UI/Locale_enUS.lua` and before
   `UI/Messages.lua`, which calls `Locale.Use`.
3. Run `pwsh tests/run.ps1`.

## Not yet localized

The window's card titles, labels, buttons and number display (`UI/View.lua` terms,
`View.count`) still use the English terms table. Moving them onto keys is follow-up
work.
