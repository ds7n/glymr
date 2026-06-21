# Predictor candidate aggregation

**Date:** 2026-06-21
**Status:** Locked
**Phase:** 4d (predictor) — the read-side of windowing: a `CandidateSource`
abstraction and an `AggregateCandidateSource` that sums multiple sketches'
estimates, realizing the spec's `today ⊕ rolling_<window>` query without
materializing a merged sketch per keystroke. Pure value types, Linux-testable.
Implements the "Query path" of [[2026-06-13-predictor-design]]; the rollover
state machine that *maintains* the rolling sketches is the next slice.

## CandidateSource

```
protocol CandidateSource {
    func candidates(forPrefix: String) -> [TokenCount]
}
```

The one operation suggestion ranking needs: prefix → scored candidates.
``Vocabulary`` already has this method, so it conforms directly. This is the seam
that lets a ``SeededSuggester`` rank over *either* a single learned vocabulary or
a windowed aggregate, without knowing which.

## AggregateCandidateSource

Holds N sources; `candidates(forPrefix:)` **unions** their prefix candidates and
**sums** each token's count across sources (saturating at `UInt32.max`):

```
candidates(prefix):
  totals = {}
  for src in sources: for c in src.candidates(prefix): totals[c.token] += c.count
  return [TokenCount(token, total)]   // sorted by token bytes for determinism
```

This is the query path `today ⊕ rolling_<window>` realized on the **read** side:
rather than merge sketches into one and estimate, it estimates each token in each
source and adds. Both are pointwise sums; summing estimates avoids rebuilding a
sketch on every keystroke and preserves the one-sided error (each estimate `≥`
its true count, so the sum `≥` the true combined count). The candidate *set* is
the union of the sources' prefix matches.

Saturating add matters: two near-max sketches must not wrap to a tiny number and
mis-rank.

## SeededSuggester becomes a pure combiner

`SeededSuggester` (4c) previously owned a mutable learned `Vocabulary` and a
`record` method. With windowing, learning targets a specific sketch (`today`)
owned by the rollover store, and the query reads an *aggregate*. So the suggester
is refactored to a **pure ranking combiner**:

```
init(learned: any CandidateSource, seed: any CandidateSource, config:)
suggestions(forPrefix:) -> [String]   // unchanged two-layer gating/weighting
```

`record` is removed — learning is the store's job, not the ranker's. The gating
and weighting logic is unchanged; only the input types widen from `Vocabulary` to
`any CandidateSource`. A `SeededSuggester` can now rank a single vocabulary (pass
it directly) or `today ⊕ rolling` (pass an `AggregateCandidateSource`).

## Testing (Core tier)

- **Aggregate sum:** a token in two sources reports the summed count; a token in
  one source reports its own; the candidate set is the union; output is
  token-sorted.
- **Saturating sum:** two sources near `UInt32.max` sum to `.max`, not a wrap.
- **Empty / single source:** empty aggregate → `[]`; one source → passthrough.
- **SeededSuggester over an aggregate:** ranking a `today ⊕ rolling` aggregate as
  `learned` produces the same gating behavior as a single vocabulary with the
  combined counts — proving the seam works end to end.
- **Refactored suggester:** the 4c behavior matrix still holds with learning done
  externally (record into a `Vocabulary`, then rank).

## Out of scope (next slice)

- **Rollover state machine** — `today`/`rolling_7d/30d/90d`/sealed dailies, the
  midnight `merge`/`subtract`/seal/prune that maintains the rolling sketches this
  aggregate reads. (`CountMinSketch.merge`/`subtract` from 4a are the primitives.)
- Persistence, bigram aggregation, privacy filtering.

## Related

- [[2026-06-21-predictor-seed-deference-design]] — the suggester being refactored
- [[2026-06-21-predictor-core-sketches-design]] — pointwise sum / saturation
- [[2026-06-13-predictor-design]] — the `today ⊕ rolling ⊕ seed` query path
