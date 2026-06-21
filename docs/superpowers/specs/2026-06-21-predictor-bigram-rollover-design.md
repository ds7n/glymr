# Predictor bigram daily rollover

**Date:** 2026-06-21
**Status:** Locked
**Phase:** 4h (predictor) — gives next-token (bigram) prediction the same daily
time-windowing the unigram path got in 4e: a hot `today` plus `rolling_7d/30d/90d`
pre-aggregates, queried as `today ⊕ rolling_W`. Pure value types, Linux-testable.
Extends [[2026-06-21-predictor-bigram-next-token-design]] with the windowing of
[[2026-06-21-predictor-daily-rollover-design]].

## The gap this fills

[[2026-06-21-predictor-bigram-next-token-design]] (4g) shipped a single-sketch
``BigramVocabulary`` — all adjacencies counted forever, no recency. The unigram
path already solved recency with ``RollingVocabulary`` (4e): seal each day, keep
sliding-window pre-aggregates, query `today ⊕ rolling_W` in O(1). Bigrams need the
identical treatment so "what follows `git` *lately*" tracks the user's evolving
habits instead of all-time totals.

## Same insight, one layer up: a windowed bigram is a windowed unigram over composite keys

4g's whole trick was *a bigram is a unigram over `previous + US + next`*. That
trick is orthogonal to windowing, so it nests: a **windowed** bigram is a
**windowed** unigram over the same composite keys. ``RollingBigramVocabulary``
therefore wraps the existing ``RollingVocabulary`` exactly as ``BigramVocabulary``
wraps ``Vocabulary`` — no new sketch, no new rollover arithmetic, no new
merge/subtract logic.

```
record(previous:next:count = 1)        → rolling.record(composite(previous, next))
rollover()                             → rolling.rollover()            (unchanged)
nextSource(after previous:, window:)   → strip-lead( rolling.learnedSource(window:) )
candidates(after previous:, window:, prefix = "")   → convenience over nextSource
```

`rollover()` and the `today/rolling_7d/30d/90d` machinery — including CMS pointwise
add for merge and clamp-at-zero subtract for eviction — are inherited verbatim
from ``RollingVocabulary``. The composite key is just a string to all of it.

## Refactor: NextTokenSource over any CandidateSource

4g's `NextTokenSource` (the lead-stripping adapter) wrapped a concrete
``Vocabulary``. The only operation it uses is `candidates(forPrefix:)` — the
``CandidateSource`` protocol. Widening its stored source from `Vocabulary` to
`any CandidateSource` lets **both** bigram stores reuse it:

- `BigramVocabulary.nextSource` passes its `Vocabulary` (already a `CandidateSource`).
- `RollingBigramVocabulary.nextSource` passes `rolling.learnedSource(window:)`
  (an ``AggregateCandidateSource`` — `today ⊕ rolling_W`, also a `CandidateSource`).

The lead-strip math is unchanged: query `previous + US + prefix`, drop
`(previous + US).utf8.count` bytes off each returned composite key, decode the
rest. The contiguous-run / no-bleed guarantee holds for the aggregate too,
because each summed source is the same composite-key index.

## Refactor: shared composite-key encode + guard

4g's fail-closed guard (reject empty side, zero count, separator byte in either
side) and the `previous + US + next` encoding now have two call sites. Extract one
helper on ``BigramVocabulary``:

```
static compositeKey(previous:next:) -> String?   // nil when unrecordable
```

Both stores call it, so the privacy/encoding invariant lives in exactly one place
and cannot drift between the windowed and non-windowed paths.

## Composition — still free

`nextSource(after:window:)` returns a plain ``CandidateSource``, so seed deference
is unchanged from 4g — a windowed-learned source and a (windowless) seed source
drop straight into ``SeededSuggester``:

```
SeededSuggester(learned: userBigram.nextSource(after: "git", window: .days7),
                seed:    seedBigram.nextSource(after: "git"))
```

## Out of scope (later slices / deferred)

- **Bigram seed blob** — the build-time `(command, subcommand)` pipeline; this
  slice consumes any `CandidateSource` as the seed, windowed or not.
- **Persistence / serialization of the rolling set** — shared with the unigram
  rolling store; a storage slice covers both at once.
- **Trigrams, flag prediction** — as noted in 4g.
