# Predictor engine (facade)

**Date:** 2026-06-21
**Status:** Locked
**Phase:** 4o (predictor) — the single runtime API that composes every predictor
piece into one record/suggest unit: privacy filter + learned windowed stores +
pinned seed + seed-deferring ranker. The keystone the app talks to. Pure
composition over existing parts; Linux-testable. Realizes the runtime of
[[2026-06-13-predictor-design]].

## The gap this fills

All the parts exist — ``TokenFilter`` (write-time privacy),
``RollingVocabulary``/``RollingBigramVocabulary`` (learned), ``PredictorSeed``
(pinned, via ``SeedStore``), ``SeededSuggester`` (deference) — but nothing ties
them together. The app should not hand-wire five types and remember the
record/suggest invariants; it should hold one ``PredictorEngine`` and call
`record` / `suggestions` / `rollover`.

## API

```
struct PredictorEngine {
  init(learned: LearnedState, seed: PredictorSeed?,
       filter: TokenFilter = .init(), config: SuggestionConfig = .init(),
       window: RollingWindow = .days30)

  mutating func record(_ token: String, after previous: String? = nil)
  func suggestions(forPrefix: String, after previous: String? = nil) -> [String]
  mutating func rollover()
  var state: LearnedState { get }      // for the app to flush via LearnedStore
}
```

The app constructs it from the two stores —
`PredictorEngine(learned: learnedStore.load(), seed: seedStore.loadSeed())` — and
persists `engine.state` via `learnedStore.save(...)` at flush time. `seed` is
optional: a missing/uninstalled seed just means learned-only suggestions (the
`SeedStore` fail-soft path), never a broken engine.

### record — write-time privacy at the boundary

```
record(token, after: previous):
  if filter.excludes(token):  return            // never learn an excluded token at all
  learned.unigram.record(token)
  if let previous, !filter.excludes(previous):
      learned.bigram.record(previous: previous, next: token)
```

Privacy is applied **here, once, at the write boundary** — the spec's "filter at
write time, not read time." An excluded `token` is learned nowhere (no unigram,
no adjacency). An excluded `previous` only suppresses the *adjacency* (the
non-excluded `token` is still a fine unigram). This is the one place the engine
consults the filter; `suggestions` never does (the data simply isn't there).

### suggestions — unigram or next-token, each seed-deferred

```
suggestions(forPrefix: p, after: previous):
  if let previous:                              // next-token (bigram) axis
      learnedSrc = learned.bigram.nextSource(after: previous, window: window)
      seedSrc    = seed?.bigram.nextSource(after: previous) ?? empty
  else:                                         // single-word (unigram) axis
      learnedSrc = learned.unigram.learnedSource(window: window)
      seedSrc    = seed?.unigram ?? empty
  return SeededSuggester(learned: learnedSrc, seed: seedSrc, config: config)
           .suggestions(forPrefix: p)
```

Both axes reduce to the same `SeededSuggester` composition over a learned and a
seed ``CandidateSource`` — the two-layer per-prefix deference
([[2026-06-21-predictor-seed-deference-design]]) is reused verbatim, never
re-implemented. A seedless engine passes an **empty** source
(`AggregateCandidateSource([])`), so the fill path simply adds nothing and the
result is learned-only. Reads are never privacy-gated.

### rollover / state

`rollover()` rolls both learned axes (the app calls it at user-local midnight).
`state` exposes the current `LearnedState` so the app flushes it through
``LearnedStore``; the engine itself does no I/O (storage stays at the edges,
testable in isolation).

## Tunables

`window` (default `.days30`), and the `SuggestionConfig` (`topK`,
`confidenceFloor`, `seedWeight`) and `TokenFilter` are all injected — starting
points per the master spec, empirically tunable, never hard-coded in the engine.

## Out of scope (later slices)

- **App-edge assembly** — building `PredictorSeed`/`LearnedState` from `Bundle` +
  Application-Support and owning the flush cadence (needs an app target).
- **Output-token harvesting**, time-of-day axis, flag prediction — master-spec
  features beyond the core record/suggest engine.
