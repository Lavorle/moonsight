# Formal 1.0 M1 Contract Freeze

Status: **frozen before Formal 1.0 feature implementation**

This file is the repository-visible index for the approved M1 contracts. It does
not replace the binding interview specification or approved consensus plan. The
authoritative sources are pinned below so parallel implementation lanes cannot
silently reinterpret shared state, format, effect, performance, or evidence
contracts.

## Authoritative inputs

| Artifact | SHA-256 |
| --- | --- |
| `.omx/specs/deep-interview-formal-1.0-continuation-master-plan.md` | `e0a78589b42a38a7b461e7c57283f3681d18f9a9cd6f5474a582a76b3a20aa60` |
| `.omx/plans/moonsight-formal-1.0-product-milestone.md` | `81642f560c1422a9cb5fea109a2fbc6cdc5680a564e6b040618bbb81fe52c7a5` |
| `.omx/context/formal-1-0-product-milestone-20260712T163223Z.md` | `f1bd0e810df7f14d50a92bdc89952e34989e5a57872e38a12f17223d4dbaf19b` |
| `.omx/checkpoints/formal-1.0-m0-20260712T163332Z/sha256.txt` | `ed49b34d0a7acab1016870b59cb2aba8c70fd789d0022d829301a0c5d9a9a1b0` |

Protected source baseline: `46130ef`  
Protected M0 closure checkpoint: `d92cdbf7b7583eab0aa29ecb8e33aaa3cdebb014`

If any pinned source changes, implementation pauses until the replacement is
reviewed and this manifest is updated in a coherent pre-feature commit.

## Frozen cross-lane contracts

1. **One logical restore path.** Subsystems own typed snapshots; the internal
   `EngineLogicalState` facade is the sole aggregate capture, validation,
   prepared-state construction, and atomic publication coordinator. Save and
   rollback projections must not independently copy live `Engine` fields.
2. **Validate before mutation.** Logical restore prepares every subsystem in
   isolation, proves cross-subsystem invariants, publishes one aggregate, and
   reconciles render/audio/resource/Host backends only after commit. Validation
   failure leaves live logical state unchanged. Backend failure is observable
   retry/rebuild state, not fictional reversal of an external effect.
3. **Director-owned effect semantics.** Every registration carries exactly one
   `Checkpointed`, `CompensatableAudio`, or `Barrier(reason_code)` descriptor.
   Unknown/custom/external commands default to a barrier. Successful barriers
   clear older reachable checkpoints; blocked rollback causes zero logical, UI
   transient, or backend mutation.
4. **Author-owned identity.** A second locale requires explicit, stable IDs for
   dialogue, speakers, choices, and locale-sensitive resources. Choice-ID order
   is canonical across locales. Compiler-generated IDs are legacy single-locale
   compatibility only; migration/freeze output is deterministic and reviewed.
5. **Locale profile and completeness.** Formal 1.0 accepts only
   `^[a-z]{2,3}(-[A-Z][a-z]{3})?(-([A-Z]{2}|[0-9]{3}))?$`. Every supported
   locale contains every required narrative and UI key. Text never silently
   falls back in production; resource fallback must be explicit and
   digest-validated.
6. **Presentation-independent persistence.** Save v5 persists the serializable
   logical-state projection, stable text/choice identity, and normalized
   grapheme reveal progress. Locale remains a preference. v2-v4 mapping uses
   MSB2 compatibility metadata and fails explicitly before mutation when the
   mapping is ambiguous or unavailable.
7. **Partial reveal rule.** Completed lines remain complete. Otherwise the new
   revealed grapheme count is
   `floor(old_revealed / old_total * new_total)`, clamped to grapheme
   boundaries; UTF-8 or code-unit offsets are not persistence authority.
8. **UI checkpoint boundary.** Rollback includes semantic mode/modal/focus,
   backlog anchor, save/load/settings position, stable choice focus/selection,
   and auto state. It excludes overwrite/quit confirmation, locale, prefs,
   slots, and load diagnostics. Restore clears transient confirmations and
   rebuilds derived layout/draw/glyph/gesture state.
9. **Rollback accounting.** The ring holds at most 64 checkpoints and at most
   16 MiB of estimated/serialized logical payload. Oldest checkpoints are
   evicted until both limits pass. A single oversize checkpoint is visibly
   rejected without destroying usable history. Count, bytes, high-water,
   evictions, and rejections are observable.
10. **MSB2 whole-package transaction.** MSB2 carries logical module identity,
    stable operation/presentation/choice IDs, complete catalogs, compatibility
    metadata, and section digests. The manifest carries locale, catalog,
    resource/audio, and package-schema digests. Host validation of the complete
    bundle succeeds before any engine installation mutation.
11. **Exact-SHA evidence is external.** Candidate code contains procedures and
    schemas, not post-test PASS edits. RC, W1, D1, and C1 evidence names one
    candidate SHA and matching artifact digests. A validator rejects mixed
    SHAs/digests. Tag/release authorization is not implied by repository tests.

## Dependency order and ownership gate

Feature work proceeds in this order because each later lane consumes contracts
from the preceding lane:

1. typed `EngineLogicalState` facade and save-v5 schema;
2. explicit IDs, deterministic migration, MSB2, and package transaction;
3. runtime/Host hot-switch i18n;
4. rollback ring and effect enforcement;
5. cross-feature, fault-injection, performance, and exact-SHA evidence.

Before editing a shared surface, the receiving lane must ACK the producer's
artifact/path, frozen contract, ownership, and next action. A lane must report a
changed assumption before widening scope. Verification owns cross-boundary
checks and reports missing fixtures, generated-file drift, and integration risk
rather than silently repairing another lane's files.

## Required M1 regression contracts

Characterization or golden fixtures must cover parser/IR identity behavior,
MSB1 compatibility, save v2-v4, prefs, lifecycle, UI, and audio. The M1 exit
also requires explicit field classification for every `Engine` field as
logical, preference-owned, backend-derived, transient, or barrier-producing;
unknown-command barrier, BGM compensation, and one-shot SE barrier behavior;
and a retained benchmark harness plus baseline evidence.

## Frozen numerical gates

- warm locale switch p95: at most 16 ms over 1,000 switches after warm-up;
- cold locale switch p95: at most 100 ms over 100 fresh sessions, with catalog
  decode separated from first GPU glyph upload;
- decoded catalogs: at most 32 MiB for the representative bilingual demo;
- catalogs plus rollback incremental resident memory: at most 48 MiB above M0
  at 64 checkpoints;
- steady-state rendered-frame p95 regression: at most 5% versus the same M0
  ten-minute trace.

The reference environment pins OS, CPU, RAM, browser/WebView, GPU/driver,
toolchain, power mode, viewport, and demo trace. Measurements use five
process-isolated repetitions and report the median of run-level p95 values.
These gates may be tightened, not weakened after RC freeze.

## Reproducibility and evidence schema freeze

The normalization allowlist is versioned. Each entry must name the artifact
glob, exact metadata field or byte range, deterministic replacement, rationale,
and owner. MSB2, catalogs, manifest semantic bytes, resources, Host WASM, and
executable payloads are byte-identical without normalization. Both raw and
normalized checksums are retained; any unlisted difference blocks RC.

External evidence records at least candidate SHA, toolchain and lockfile
identity, environment identity, exact commands, raw output/artifact locations,
raw and normalized digests where applicable, outcome, and authorized operator.
W1/D1/C1 success, tag creation, release publication, or external authorization
must never be inferred or fabricated from automated local checks.

## Exclusions

Q6 and 1.x stretch work remains excluded. This freeze does not authorize W1,
D1, C1, a tag, a release, external publication, or the 168-hour stabilization
clock.
