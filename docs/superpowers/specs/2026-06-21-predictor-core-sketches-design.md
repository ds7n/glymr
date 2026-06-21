# Predictor core sketches — Count-Min Sketch + Bloom filter

**Date:** 2026-06-21
**Status:** Locked
**Phase:** 4a (predictor foundation) — the probabilistic data structures the whole
predictor is built on. Pure value types, Linux-testable. Implements the
"Sketches and tables" + "sketch sizing" sections of
[[2026-06-13-predictor-design]].

## Goal

Two sketches with bounded memory and O(1) ops, plus the deterministic hashing
they share:

- **`CountMinSketch`** — per-token frequency with one-sided (over-)estimate
  error. Backs unigram and bigram frequency.
- **`BloomFilter`** — approximate set membership ("seen this token?"). Backs the
  typo / known-token check and output-token harvesting.

Everything above this slice (prefix ranking, seed deference, daily rollover,
storage) is deferred — but the **merge / subtract / serialize** primitives those
slices need are built and tested here, because they are properties of the
sketches themselves.

## Determinism is a cross-device contract (load-bearing)

Sketches sync across a user's devices via CloudKit ([[2026-06-16-icloud-sync-scope-design]]).
A merge of a sketch from device A into device B's is only meaningful if **the
same token maps to the same cells on every device and every run**. Therefore:

- **No `Swift.Hasher`** — it is randomly seeded per process; identical tokens
  would hash differently across launches and devices, corrupting every merge.
- Hashing is a **fixed FNV-1a** over the token's UTF-8 bytes, defined here and
  frozen. The serialization format carries a version byte so a future hash change
  is an explicit, detectable format bump — never a silent divergence.

### Hash scheme

`StableHash.indices(token, count: k, modulo: m)` → `k` indices in `[0, m)`:

- `h1 = fnv1a64(utf8, basis: 0xcbf29ce484222325)` (standard FNV-1a offset basis)
- `h2 = fnv1a64(utf8, basis: 0x100000001b3)` (a second basis to decorrelate)
- index `i` = `(h1 &+ i &* h2) % m` for `i` in `0..<k` (Kirsch–Mitzenmacher
  double hashing; wrapping arithmetic so no overflow trap)

FNV-1a uses wrapping multiply/xor. The two bases give two independent-enough base
hashes; double hashing synthesizes `k` of them without `k` full hashes.

## CountMinSketch

`depth` rows (= number of hash functions) × `width` cells per row, `UInt32`
counters, row-major. Row `r` uses index `indices(token, depth, width)[r]` within
its row, i.e. cell `r*width + idx[r]`.

| Op | Behavior |
|---|---|
| `add(token, count = 1)` | each row's cell `+= count`, **saturating** at `UInt32.max` (never wraps) |
| `estimate(token)` | **min** over the `depth` rows → one-sided error: result `≥` true count, never below (until a `subtract`) |
| `merge(other) -> Bool` | pointwise cell add (saturating); `false` + no-op if dims differ |
| `subtract(other) -> Bool` | pointwise cell `max(0, a-b)` — **clamp at zero**, never underflow/wrap; `false` + no-op if dims differ |

`subtract` is the rollover evict (`rolling_7d -= daily/(today-7)`); clamping at
zero is the spec's accepted, tolerable noise (a subtracted sketch may then
*under*-estimate — that is fine for eviction). `merge`/`subtract` require equal
`depth` **and** `width` (hashing is globally fixed, so dims are the only
compatibility axis).

Default sizing (from the spec, not hard-coded here — the predictor passes them):
unigram `depth = 4`, `width = 2^14`.

## BloomFilter

`bitCount` (m) bits packed into `ceil(m/8)` bytes, `hashCount` (k) hash
functions via `indices(token, k, m)`.

| Op | Behavior |
|---|---|
| `insert(token)` | set the `k` bits |
| `mightContain(token)` | `true` iff **all** `k` bits set — **no false negatives**, false positives possible |

No merge/subtract in this slice (Bloom union = bitwise OR; add when a caller
needs it). Default sizing: `m ≈ 64K` bits, `k = 7` for ~10K tokens at ~1% FPR.

## Serialization (the synced blob format)

Both serialize to a self-describing little-endian blob; `init?(deserializing:)`
**fails closed (`nil`)** on wrong magic, unknown version, dim mismatch, or wrong
length — a corrupt blob never yields a half-populated sketch.

```
CountMinSketch:  "GCMS"(4) | version(1=1) | depth(u32) | width(u32) | cells(depth*width × u32)
BloomFilter:     "GBLM"(4) | version(1=1) | bitCount(u32) | hashCount(u32) | bits(ceil(m/8) bytes)
```

Round-trip is exact: `deserialize(serialize(s)) == s`.

## Testing (Critical tier — correctness-critical + a sync contract)

- **Hash determinism / known-answer**: `indices` is stable across calls; pin the
  raw `fnv1a64` of a known vector so the frozen format can't drift silently.
- **CMS one-sided error**: after `add(t, n)`, `estimate(t) >= n` (EP); empty
  sketch estimates `0` (boundary).
- **CMS saturating add**: `add(t, .max)` then `add(t, 1)` stays `.max` (no wrap).
- **CMS merge**: estimate after merge `≥` sum of the two true counts; dim
  mismatch → `false`, no mutation.
- **CMS subtract clamp** (adversarial): subtract more than present → `estimate ==
  0`, never a wrapped huge value; dim mismatch → `false`.
- **Bloom no false negatives**: every inserted token `mightContain == true`.
- **Bloom empty negative**: an empty filter returns `false` (the safe, non-flaky
  negative).
- **Serialization**: exact round-trip for both; truncated / wrong-magic /
  wrong-version / dim-mismatch blob → `nil`.

## Out of scope (later 4x slices)

- Prefix indexing + ranking (`query(prefix)` → top-K) — CMS estimates frequency
  for a *known* token; mapping a typed prefix to candidate tokens needs a token
  dictionary, a separate slice.
- Seed deference (Layer 1 weighting + Layer 2 per-prefix gating).
- Daily versioning / rollover / rolling aggregates.
- Storage (SQLite metadata, file protection, event log), privacy write-time
  filtering, CloudKit sync envelope.

## Related

- [[2026-06-13-predictor-design]] — the subsystem spec this implements the base of
- [[2026-06-16-icloud-sync-scope-design]] — why determinism is a hard requirement
