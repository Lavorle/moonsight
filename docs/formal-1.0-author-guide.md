# MoonSight Formal 1.0 author, migration, and runtime guide

Status: tracked release content for the Formal 1.0 candidate. This guide describes
repository contracts and author-facing procedures; it does **not** select a
candidate, authorize W1/D1/C1, create a tag, or publish a release.

## Project profile

A Formal 1.0 project declares a stable module name and locale set in
`moonsight.json`:

```json
{
  "name": "my-moonsight-game",
  "entry": "main.yuki",
  "logical_width": 1920,
  "logical_height": 1080,
  "save_slots": 6,
  "default_locale": "en",
  "supported_locales": ["en", "zh-Hans-CN"]
}
```

Locale tags must match the frozen core profile:
`^[a-z]{2,3}(-[A-Z][a-z]{3})?(-([A-Z]{2}|[0-9]{3}))?$`. The default locale must
appear exactly once in the non-empty supported set.

## Stable author identity

A project that ships more than one locale owns stable IDs for dialogue,
speakers, choices, and locale-sensitive resources. IDs are semantic identity,
not hashes of source text, byte offsets, line numbers, or translated strings.

Recommended namespaces:

- `speaker.*` for speaker labels;
- `dialogue.<scene>.*` for narrative presentation;
- `choice.<scene>.<group>.*` for options;
- `ui.*` for project UI strings;
- `resource.*` for locale-sensitive asset bindings.

Choice IDs and their order are identical across locales. Renaming or reusing an
ID is a compatibility change and must be reviewed with the migration output.
Legacy compiler-generated IDs are accepted only for single-locale compatibility;
they are not an authoring contract for new bilingual content.

## Catalogs and resources

Every supported locale supplies exactly the default catalog's key set. Missing
or extra keys fail validation; production text never silently falls back.
Resource fallback is allowed only when it is explicitly declared and the target
resource digest matches the package manifest.

The tracked examples under `templates/minimal/locales/` and
`demo/game/locales/` use JSON objects keyed by stable IDs. They are authoring
assets and migration review fixtures. The canonical MSB2/package encoder owns
the final binary layout and manifest digests.

## Deterministic migration and freeze

Use the canonical migration/freeze command supplied by `moonsightc` once the
explicit-ID lane is integrated. The review procedure is invariant even if CLI
spelling evolves before candidate freeze:

1. Run migration against a clean tree and retain its machine-readable output.
2. Run it again without editing the project; bytes must be identical.
3. Review every generated stable ID, choice order, and legacy save mapping.
4. Commit the approved source/catalog changes and the reviewed compatibility
   metadata together.
5. Run freeze/check. Ambiguous or unavailable v2-v4 mappings are release
   blockers; do not guess or mutate a save in place.

`docs/formal-1.0-migration-example.json` is a non-executable review example. It
shows the required concepts without pretending to be the canonical compiler
schema.

## MSB2 whole-bundle contract

Formal 1.0 packages use MSB2 for the deterministic executable/catalog bundle.
MSB2 carries logical module identity, stable operation/presentation/choice IDs,
complete locale catalogs, v2-v4 compatibility metadata, and section digests.
The package manifest carries package-schema, catalog, resource/audio, and raw
artifact digests.

Host installation is a transaction:

1. read and bound every section;
2. validate schema/version, module identity, locale completeness, stable-ID
   relationships, compatibility metadata, resource map, and raw digests;
3. construct the replacement bundle off to the side;
4. publish only after the complete bundle succeeds.

A corrupt, incomplete, mixed-digest, or unsupported bundle fails before any
engine installation mutation. MSB2, catalogs, manifest semantic bytes,
resources, Host WASM, and executable payloads are reproducibility core artifacts
and are byte-identical without normalization.

## Save v5 and legacy saves

Writers emit `format_version: 5`; readers accept v2, v3, v4, and v5. Save v5 is
a projection of the aggregate `EngineLogicalState`, not a second live-field copy
path. It persists stable text/choice identity, normalized grapheme reveal
progress, dissolve phase/total, VM/stage/audio/auto state, and the module ID.
Locale remains a preference rather than slot state.

Loading validates and prepares every replacement before publishing one logical
aggregate. Failure leaves logical state unchanged. Backend reconciliation occurs
after commit and remains retryable.

For v2-v4 saves, MSB2 compatibility metadata maps legacy scene/IP/text/choice
positions to stable identity. Missing or ambiguous mapping is an explicit load
failure before mutation. Do not rewrite a legacy blob merely because it was
inspected.

Partial reveal is presentation-independent: completed lines stay complete;
otherwise the new revealed grapheme count is
`floor(old_revealed / old_total * new_total)`, clamped to grapheme boundaries.
UTF-8 bytes and language-specific code-unit offsets are not persistence
authority.

## Runtime locale switching

Locale switching is an atomic hot switch over a strict complete catalog. Text
has no production fallback. Legacy resolved values without stable IDs remain
unchanged rather than being guessed.

The switch prepares all stable narrative, choice, backlog, UI, and
locale-sensitive resource resolutions first. Any missing key, invalid resource,
or digest mismatch leaves the previous locale and presentation intact. Locale
is stored in preferences, not saves or rollback checkpoints.

Frozen performance gates:

- warm switch p95 <= 16 ms over 1,000 switches after warm-up;
- cold switch p95 <= 100 ms over 100 fresh sessions, with catalog decode
  separated from first GPU glyph upload;
- decoded catalogs <= 32 MiB for the representative bilingual demo.

## Rollback and effect barriers

Rollback checkpoints capture the aggregate `EngineLogicalState`. The ring holds
at most 64 entries and at most 16 MiB of estimated logical payload. Oldest
entries are evicted until both limits pass; an oversize checkpoint is rejected
without destroying usable history.

Effects have exactly one class:

- `Checkpointed` — restored by logical state;
- `CompensatableAudio` — BGM reconciliation is compensated after commit;
- `Barrier(reason_code)` — successful execution clears older reachable
  checkpoints.

Unknown/custom/external commands default to a barrier. One-shot SE is a barrier.
A failed effect does not clear history. Blocked rollback reports a stable
`rollback.unavailable.*` diagnostic and causes zero logical, UI, or backend
mutation.

New game, successful load, and return to title clear rollback reachability.
Locale, preferences, slots, load diagnostics, and transient overwrite/quit
confirmations are excluded. Derived layout, draw, glyph, hover, and gesture
state is rebuilt after restore. Backend reconciliation is post-commit and
retryable.

The combined catalog-plus-rollback incremental resident-memory gate is <= 48
MiB above the M0 baseline at 64 checkpoints. Steady-state rendered-frame p95 may
regress by at most 5% against the same M0 ten-minute trace.

## Build and verification

```bash
export CC=gcc
moon fmt --check
moon check --target all
moon test --target all

cd apps/host-web && npm ci && npm test && npx tsc --noEmit && npm run build
cd ../..
moon run cmd/moonsightc --target native -- check demo/game
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo

cd apps/docs-site && npm ci && npm run types:check && npm run build
```

Run the reproducibility and immutable evidence procedures in
[`formal-1.0-rc-tooling.md`](./formal-1.0-rc-tooling.md). Automated success does
not imply W1, D1, C1, tag, release, or publication authorization.

## Release exclusions

Formal 1.0 does not include a visual editor, achievements, Live2D/3D,
particle/postprocess stack, voice track, slot screenshots, DOM narrative menus,
a second native GPU backend, a second wasm/dynamic UI loader, cloud save, or
automatic Web-to-desktop slot migration. The obsolete Screen DSL remains a hard
error. Q6 and 1.x stretch work remains excluded.

## External evidence boundary

Repository files contain procedures and schemas only. Actual benchmark,
reproducibility, W1, D1, and C1 results live outside the immutable candidate and
must name the same candidate SHA and matching artifact digests. Until those
records exist, [`release-1.0-verification.md`](./release-1.0-verification.md)
remains `BLOCKED` / `NOT RUN`.
