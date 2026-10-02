# Build-matched client evidence

Before judging an API, identify the repository's declared evidence build and
read the matching dump's documented function/event/widget section. Check argument
order/defaults/optional returns and event payloads; don't rely on memory.
_G walks can include loaded addon symbols, so they are not proof of a native API.

Read the build-matched Blizzard UI source to understand callback usage/ordering
and owning objects; verify a shared checkout's ref before trusting its working tree.
Where declarations and measured behavior differ, keep the measured build explicit.
A name's presence, successful stub or returned texture ID cannot prove rendering.

Nil/asynchronously loaded item data, event listener before requests, bounded retries,
late callbacks after hide/reset, and no stale re-use deserve reachable-path checks.
Record missing evidence as a limitation instead of inventing behavior.

Persistence/performance/texture/model/animation/protected action claims often require
a live-client measurement. State exactly what offline checks establish and which
client observation remains. Re-measure affected behavior after client updates.
