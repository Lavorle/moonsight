# Changelog

All notable MoonSight changes are documented here. The repository follows
semantic versioning for tracked release metadata.

## [1.0.0] - Unreleased

Formal 1.0 content is complete for candidate freeze, but the release remains
**BLOCKED** until W1, D1, and C1 pass against one immutable candidate SHA. This
entry does not authorize a tag or publication.

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
  W1/D1/C1 evidence procedures.
- Bilingual Formal 1.0 author documentation, template locale assets, and demo
  catalog examples.

### Changed

- Package metadata targets version 1.0.0.
- Formal packages declare default and supported locales.
- Release documentation now distinguishes automated gates from external
  WebGPU, desktop persistence, and representative-demo evidence.

### Compatibility

- Save readers accept v2-v5; writers emit v5.
- Legacy single-locale content remains supported, while bilingual projects must
  freeze explicit stable IDs and complete catalogs.
- Obsolete Screen DSL input remains rejected.
