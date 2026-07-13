# Formal 1.0 benchmark, reproducibility, and RC tooling

These scripts implement the retained-evidence procedures frozen at M1. They do
not create benchmark samples, select a release candidate, authorize W1/D1/C1,
create a tag, or publish a release.

Use this procedure together with the tracked authoring contract in
[`formal-1.0-author-guide.md`](./formal-1.0-author-guide.md) and record the
resulting exact-SHA evidence in
[`release-1.0-verification.md`](./release-1.0-verification.md).

## Benchmark report

`scripts/benchmark_report.py` consumes a retained JSON sample file. It requires
five process-isolated warm repetitions of exactly 1,000 samples and five cold
repetitions of exactly 100 fresh-session samples. Cold input retains catalog
decode and first GPU glyph-upload samples separately. The report uses the
nearest-rank p95 for each run and the median of the five run-level p95 values.

The same report validates decoded-catalog memory, catalog-plus-rollback
incremental memory at exactly 64 checkpoints, and rendered-frame p95 regression
against the M0 trace. The frozen limits are embedded in the tool; input can
provide observations but cannot weaken a limit.

```sh
python3 scripts/benchmark_report.py evidence/benchmark-samples.json \
  --output evidence/benchmark-report.json
```

## Two-build reproducibility

Build the same candidate twice in separate clean environments, retaining both
package trees. The comparator inventories the complete trees, checks tracked
file modes and bytes, and retains raw and normalized SHA-256 digests.

```sh
python3 scripts/compare_reproducible_builds.py \
  evidence/build-a/package evidence/build-b/package \
  --allowlist scripts/reproducibility-normalization-v1.json \
  --output evidence/reproducibility.json
```

The checked-in version-1 allowlist is intentionally empty. A normalization
entry must name a unique id, artifact glob, exact half-open byte range,
same-length deterministic UTF-8 replacement, rationale, and owner. Unknown or
ambiguous differences fail. MSB/MSB2, catalogs, manifests, Host WASM, native
payloads, and common resource formats are raw-byte core artifacts and cannot be
normalized. Any allowlist change is a reviewed policy change, not evidence
generated during an RC run.

## Immutable external RC manifest

`rc_manifest.py generate` combines the exact candidate SHA, benchmark and
reproducibility report digests, toolchains, lock identities, environment,
commands, raw output references, artifact digests, and authorized operator.
The output uses create-only file semantics and is written read-only; an existing
manifest is never overwritten. It always initializes W1/D1/C1 to `NOT_RUN` and
`release_authorized` to `false`.

```sh
python3 scripts/rc_manifest.py generate \
  --candidate "$CANDIDATE_SHA" \
  --benchmark evidence/benchmark-report.json \
  --reproducibility evidence/reproducibility.json \
  --metadata evidence/rc-metadata.json \
  --output evidence/rc-manifest.json
```

RC metadata has non-empty `toolchains`, `locks`, and `environment` objects, a
non-empty `commands` array whose entries identify commands and retained output
paths, and an `authorized_operator` string. This records who performed the
evidence run; it is not release authorization.

## Post-M9 freeze guard

After the candidate SHA is frozen, run the guard before every later evidence or
publication step. It rejects a different `HEAD` and any tracked worktree diff.
Untracked external evidence is deliberately ignored so results remain outside
the immutable candidate commit.

```sh
python3 scripts/rc_manifest.py guard \
  --candidate "$CANDIDATE_SHA" --repo .
```

## Evidence index and Final Gate

After the candidate is frozen, operators collect the 13 required external
evidence records **outside** the candidate commit. Build the public index, then
verify the Final Gate Report. These steps never authorize a tag by themselves.

```sh
python3 scripts/release_evidence.py build-index \
  --candidate path/to/candidate.json \
  --records path/to/records \
  --output path/to/evidence-index.json

python3 scripts/verify_release_evidence.py \
  --repo . \
  --candidate path/to/candidate.json \
  --index path/to/evidence-index.json \
  --output path/to/final-gate.json
```

Record paths and digests in
[`release-1.0-verification.md`](./release-1.0-verification.md). Publication still
requires human secondary confirmation after Final Gate PASS.

## GitHub publisher

`scripts/publish_github_release.py` plans an annotated tag and draft-first
GitHub Release from candidate identity, evidence index, Final Gate Report,
release notes, and the first-candidate artifact directory (four packages +
`SHA256SUMS`). Default mode is dry-run: it prints planned argv arrays and
performs no mutations.

Dry-run (safe, no side effects):

```bash
python3 scripts/publish_github_release.py \
  --repo . \
  --candidate path/to/candidate.json \
  --index path/to/evidence-index.json \
  --gate path/to/final-gate.json \
  --artifacts path/to/first \
  --notes path/to/release-notes.md
```

Execute only after Final Gate PASS and human secondary confirmation:

```bash
python3 scripts/publish_github_release.py \
  --repo . \
  --candidate path/to/candidate.json \
  --index path/to/evidence-index.json \
  --gate path/to/final-gate.json \
  --artifacts path/to/first \
  --notes path/to/release-notes.md \
  --execute --authorize v1.0.0
```

`--execute` without `--authorize v1.0.0` (exact string) is rejected. Execute mode
is the only path that may create the annotated tag, draft release, and upload
attachments. Repository CI runs publisher unit tests only; it never executes
publication and never claims W1/D1/C1 PASS.
