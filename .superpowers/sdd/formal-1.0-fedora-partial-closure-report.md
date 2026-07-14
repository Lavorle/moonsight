# Formal 1.0 Fedora Partial Closure Report

- **Date (UTC):** 2026-07-14T02:36:34Z (candidate build/freeze window)
- **Candidate SHA:** `7b97efa58149b4b181c58752e9b9595cfb55a06e`
- **Evidence root:** `/home/Laouver/moonsight-evidence/formal-1.0/7b97efa58149`
- **Docs commit after this report (if any):** follow-up only; evidence binds to candidate SHA above, not a later docs commit

## Task outcomes

| Slice | Result | Notes |
|-------|--------|-------|
| Prep matrix | **PASS** | moon fmt/check/test, host-web, CLI package, scripts unittests, desktop Rust fmt/check/test |
| Artifacts + dual-build | **PASS** | Web ZIP + AppImage + deb + rpm under `artifacts/` |
| Reproducibility | **PASS** | `repro-report.json` outcome=PASS (4 packages) |
| Benchmark | **BLOCKED** | Real samples not collected; unit-test stubs forbidden (`logs/benchmark-blocked.txt`) |
| RC generate / guard | **Partial** | `candidate.json` created; generate exit 1 (benchmark not PASS); guard OK |
| Fedora 6 GUI evidence | **NOT_RUN** | Operator required; agent did not forge PASS |
| Ubuntu/Arch 7 | **NOT_RUN** | Honest stubs, full schema fields |
| Index aggregate | **NOT_RUN** | 13/13 records |
| `technical_release_ready` | **false** | Required negative success |
| Tag `v1.0.0` present | **no** | Required |
| Publisher `--execute` | **not run** | Required |

## Artifact digests (first build)

| Path | SHA-256 |
|------|---------|
| `moonsight-web-x86_64-v1.0.0.zip` | `29ed6396b381c41b610ea69d58644051569410f57b0df654a7eb76ef1b09fb12` |
| `moonsight-linux-x86_64-v1.0.0.AppImage` | `7213f1dba7ad20b79dbef9e0d5e155592e84234377ab3a38d24e204823bc8893` |
| `moonsight-linux-x86_64-v1.0.0.deb` | `1fde320f7b0f60fa7819d8e9b16e4a1ad5ebef3a9881a3e8448211d7f283e50f` |
| `moonsight-linux-x86_64-v1.0.0.rpm` | `f56fea55e50cb3b469788f7f77a82fb1bae4a03f20818ab4301fb9bb61c70426` |

## Validation targets frozen in candidate

- Fedora `os_version`: `44`
- Arch label: `2026.07.01`
- Chromium: `Chromium 150.0.7871.114 Built from source for Fedora release 44 (Forty Four)`
- Firefox: `Mozilla Firefox 152.0.4`
- WebKitGTK: `2.52.5`

## Stop-line deviations vs full plan DoD

Plan DoD asked for six Fedora/C1 **PASS** plus benchmark **PASS**. This session completed the **automatable** path and left GUI/benchmark as honest blockers:

1. **Benchmark** — no retained Formal 1.0 sample harness run; documented BLOCKED (not invented).
2. **T4–T6** — operator GUI only; records remain `NOT_RUN` stubs that validate.

Negative Final Gate and no tag/publish satisfy the plan’s non-release stop line for the automated slice. Operator continuation is documented in:

`/home/Laouver/moonsight-evidence/formal-1.0/7b97efa58149/HANDOFF-ubuntu-arch.md`

## Constraints honored

- No 1.1 native merge / worktree contamination
- No shrink of 13-ID matrix
- No `v1.0.0` tag
- No `publish_github_release.py --execute`
- Raw evidence outside candidate tree
- Overall docs remain **BLOCKED**
