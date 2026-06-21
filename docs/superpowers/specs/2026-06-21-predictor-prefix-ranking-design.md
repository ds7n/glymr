# Predictor prefix index + ranked suggestions

**Date:** 2026-06-21
**Status:** Locked
**Phase:** 4b (predictor) — turns the Phase 4a frequency sketch into actual
suggestions: type `clau` → suggest `claude`. Pure value types, Linux-testable.
Implements the unigram suggestion path of [[2026-06-13-predictor-design]] for a
single learned sketch (seed deference and windowing are later slices).

## The gap this fills

A `CountMinSketch` ([[2026-06-21-predictor-core-sketches-design]]) estimates the
frequency of a **known** token but is structurally lossy — it cannot enumerate
its keys, so it can't answer "which tokens start with `clau`?". Suggestion needs
both halves:

1. **`PrefixIndex`** — stores the actual token strings, answers prefix queries.
2. **`Vocabulary`** — pairs a `PrefixIndex` with a `CountMinSketch`: prefix query
   gives the *candidates*, the sketch gives their *scores*, ranking combines them.

## PrefixIndex

A sorted, de-duplicated array of token strings with binary-search prefix lookup.

```
insert(token)             → maintains sorted-unique invariant
matching(prefix) -> [String]   → all tokens having `prefix`, in sorted order
```

- **Lookup:** binary-search the lower bound (first token `>= prefix`), then scan
  forward while `token.hasPrefix(prefix)`. O(log n + k) for k matches.
- **Case-sensitive** — terminal tokens are (`Git` ≠ `git`); no folding.
- **Empty prefix** matches every token (a valid "no input yet" query).
- Array (not a trie) for v1: token counts are small (thousands), the array
  serializes trivially for the later storage slice, and binary search is plenty
  fast. A trie is a future optimization if profiling demands it.

## Vocabulary

```
record(token, count = 1)        → index.insert(token); counts.add(token, count)
suggestions(forPrefix:, limit:) -> [String]
```

`suggestions` ranks `index.matching(prefix)` by `counts.estimate(token)`:

- **Primary key:** estimate **descending** (most-used first).
- **Tie-break:** token **ascending** (lexicographic) — a *total*, deterministic
  order, so equal-frequency candidates never come back in a hash-dependent or
  arbitrary order. Determinism matters for testability and for a stable UI that
  doesn't reshuffle chips between identical states.
- Return the first `limit` (the suggestion row's `top_k`, default 3).
- `limit <= 0` → empty. No prefix match → empty.

The **confidence floor** and **seed deference** (Layer 1 weighting, Layer 2
per-prefix gating) are deliberately *not* here — this slice is the single-sketch
ranked-lookup mechanism. 4c layers seed + gating on top by composing two
`Vocabulary`-like sources; keeping ranking pure and seedless here makes that
composition clean.

## Worked example (the marquee behavior)

```
var v = Vocabulary(depth: 4, width: 1<<14)
for _ in 0..<10 { v.record("claude") }
for _ in 0..<2  { v.record("crayon") }
v.suggestions(forPrefix: "c",  limit: 3)  // ["claude", "crayon"]  — learned freq wins
v.suggestions(forPrefix: "cl", limit: 3)  // ["claude"]
v.suggestions(forPrefix: "z",  limit: 3)  // []
```

## Testing (Core tier)

- **PrefixIndex:** insert/dedup (same token twice → one entry); `matching`
  returns sorted matches; full-token prefix includes the token; no-match → `[]`;
  empty prefix → all; prefix longer than any token → `[]`; case sensitivity
  (`Git` not matched by `git`).
- **Vocabulary:** frequency ordering (higher count ranks first); tie → lexico­
  graphic; `limit` caps and `limit <= 0` → `[]`; no-prefix-match → `[]`; the
  marquee `claude`-beats-`crayon` case with exact expected arrays.

## Out of scope (later 4x slices)

- **Seed deference** — Layer 1 per-token weighting + Layer 2 per-prefix gating
  across a learned + a pinned seed source (4c).
- **Bigram / next-token** suggestion (`git` → `push`).
- **Daily windowing / rollover** — `today ⊕ rolling ⊕ seed` aggregation.
- **Persistence** — SQLite token metadata, file protection, event log, sync.
- **Privacy write-time filtering** — exclude-pattern gating before `record`.

## Related

- [[2026-06-21-predictor-core-sketches-design]] — the CMS this ranks over
- [[2026-06-13-predictor-design]] — per-prefix gating + seed deference (next slice)
