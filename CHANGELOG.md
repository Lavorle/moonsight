# Changelog

All notable MoonSight changes are documented here. The repository follows
semantic versioning for tracked release metadata.

## [1.0.0] - Unreleased

Formal 1.0 product content and **release tooling readiness** are tracked in-tree
for a future candidate freeze. The release remains **BLOCKED**: no immutable
candidate has complete external matrix evidence, and this entry does **not**
claim W1/D1/C1 matrix PASS, a published `v1.0.0` tag, or an authorized GitHub
Release.

### Added

- Aggregate atomic logical-state capture/restore and retryable backend
  reconciliation.
- Save v5 with stable presentation identity, grapheme reveal progress, and
  v2-v4 compatibility mapping contract.
- Explicit author-owned IDs, deterministic migration/freeze, MSB2 catalogs,
  whole-bundle digest validation, and transactional Host installation contract.
- Strict runtime locale catalogs and atomic hot switching.
- Rollback checkpoints with typed effect barriers, 64-entry/16 MiB limits, and
  observable failure diagnostics.
- Formal benchmark, reproducibility, immutable RC manifest, and external
  W1/D1/C1 evidence procedures (13 required IDs).
- Evidence index builder, Final Gate verifier, first-candidate artifact builder,
  and draft-first GitHub publisher (`publish_github_release.py`; dry-run default;
  execute requires `--authorize v1.0.0`).
- Bilingual Formal 1.0 author documentation, template locale assets, and demo
  catalog examples.
- Release verification template and RC tooling runbook aligned to Linux x86_64
  Web ZIP / AppImage / deb / rpm + `SHA256SUMS` via GitHub Release (not Pages).

### Changed

- Package metadata targets version 1.0.0.
- Formal packages declare default and supported locales.
- Release documentation now distinguishes automated gates and release-tooling
  unit tests from external WebGPU, desktop persistence, and representative-demo
  evidence; candidate fields stay `NOT SELECTED` / `NOT RUN` until Ops.

### Compatibility

- Save readers accept v2-v5; writers emit v5.
- Legacy single-locale content remains supported, while bilingual projects must
  freeze explicit stable IDs and complete catalogs.
- Obsolete Screen DSL input remains rejected.

