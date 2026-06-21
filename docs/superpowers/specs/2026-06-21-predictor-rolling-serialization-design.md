# Predictor rolling-state serialization

**Date:** 2026-06-21
**Status:** Locked
**Phase:** 4m (predictor) — serialize/deserialize the user's full windowed learned
state (``RollingVocabulary`` and ``RollingBigramVocabulary``), so it survives app
relaunch. The foundational brick under learned-store persistence — the read-write
counterpart to the read-only seed of
[[2026-06-21-predictor-seed-runtime-load-design]]. Pure value types,
Linux-testable. Implements the persistence half of
[[2026-06-13-predictor-design]]'s storage model.

## The gap this fills

The seed (4i–4l) round-trips and loads at runtime, but the **user's own learned
vocabulary is still in-memory only** — every relaunch forgets it. A
``RollingVocabulary`` holds the whole windowed state: a shared ``PrefixIndex``,
the hot `today` sketch, the `rolling_7d/30d/90d` pre-aggregates, and the sealed
`dailies`. All of those are already individually serializable
([[2026-06-21-predictor-core-sketches-design]] CMS,
[[2026-06-21-predictor-vocab-serialization-design]] PrefixIndex); this slice
composes them into one whole-state blob plus its bigram wrapper.

## Format — whole state, in the established mould

### RollingVocabulary — `GRLV` v1

```
magic "GRLV" | version(1)
  len|index-GPIX | len|today-GCMS
  len|rolling7   | len|rolling30 | len|rolling90
  dailyCount(LE32) | (len|daily-GCMS) × dailyCount
```

- Sub-blobs are length-prefixed and read with the shared `readLengthPrefixed`
  primitive; every sub-deserializer is fail-closed, so corruption anywhere → `nil`.
- **`depth`/`width` are recovered from the deserialized `today` sketch** (a CMS
  carries its own dimensions), not stored twice. Deserialization then **validates
  that every sketch — today, all three rollings, every daily — shares those
  dimensions**; a blob mixing widths is rejected, because the pointwise
  merge/subtract the rollover relies on requires equal dimensions. A hostile blob
  can't yield a `RollingVocabulary` whose `rollover` would silently no-op a merge.
- `dailyCount` is bounded by the buffer (each daily costs ≥ a length prefix), so a
  hostile count fails fast rather than pre-allocating.
- No trailing slack permitted.

### RollingBigramVocabulary — `GRBG` v1

```
magic "GRBG" | version(1) | inner-RollingVocabulary-GRLV-blob
```

A ``RollingBigramVocabulary`` is a ``RollingVocabulary`` over composite keys, so
its blob is the inner one's under a distinct magic — the same wrap
``BigramVocabulary`` uses over ``Vocabulary``. The distinct magic is the type
guard: a unigram `GRLV` state can't load as a bigram store.

## Equatable for verification

``RollingVocabulary`` and ``RollingBigramVocabulary`` gain `Equatable` (and
`Sendable`) — all their fields already are — so the load-bearing round-trip test
is a direct `deserialize(serialize(v)) == v`, backed by behavioral checks
(restored windows answer the same counts, and `rollover` still works post-load).

## Whole-state vs incremental flush

This slice serializes the **entire** state as one blob — the right primitive for
load-on-launch and for the master spec's "rebuild from event log" path (which
reconstructs a full state). The spec's *hot-path* optimization — flushing only
`today.sketch` frequently and rewriting sealed dailies once at rollover — is a
later store-layer concern that can layer on top; it does not change this
serialization. The store slice that follows (atomic file, fail-soft load,
first-run empty state) will decide flush cadence.

## Out of scope (later slices)

- **The on-disk learned store** — atomic save/load to the predictor dir,
  fail-soft, mirroring ``SeedStore``.
- **Incremental flush + append-only event log** — the master spec's hot-path and
  crash-recovery refinements.
- **Assembling seed + learned into the live ranker** at app start.
