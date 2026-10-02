# Selective review checklist

- TOC paths/order, namespace initialization, dependencies, event registration,
  addon-name filtering, SavedVariables timing/schema and package runtime inputs.
- Nil/optional returns, argument/event shapes, widget versus global methods,
  stale caches/late callbacks, retries/cancellation, duplicate timers/frames.
- Protected ownership/actions and taint only where reachable; ordinary minigame
  frames should stay unprotected. Do not assume all Forever values are secret.
- State and numeric decisions: JS truthiness/remainder/rounding, zero-based arrays,
  ordered mutation, exact cost/unlock thresholds and large/final-unit arithmetic.
- Reference parity: timer equal-time order, 16 ms battles, RNG draw consumption and
  meaningful snapshots. Presentation/hide/frame rate must not change simulation.
- Save continuation, unsupported future versions, migrations, duplicate rewards,
  interrupted sessions and full exit/relaunch; never claim snapshot means disk save.
- Asset streaming/fallbacks, model bounds/loading/crop/idle/particles, frame levels,
  mouse input, reused objects and measured performance.
- Tests exercise a reachable defect and use independent evidence where possible.
  No findings for style preferences, speculative abstractions or out-of-scope features.
