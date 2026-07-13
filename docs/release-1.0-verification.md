# MoonSight formal 1.0 verification record

This document is the durable evidence template for the release-critical 1.0
gates. It intentionally distinguishes automated checks from real-environment
play evidence. A build, static asset smoke, or headless browser result is not a
substitute for W1, D1, or C1. Repository CI never claims W1/D1/C1 PASS.

## Current release status

**BLOCKED** — no immutable release-candidate commit has complete W1, D1, and C1
evidence yet. Overall status remains **BLOCKED** until a real candidate is
selected and Ops completes retained external evidence for every required ID
below.

| Field | Value |
|---|---|
| Candidate commit | `NOT SELECTED` |
| Candidate tree status | `NOT RUN` |
| Candidate source archive SHA-256 | `NOT RUN` |
| Package SHA-256 | `NOT RUN` |
| Benchmark report path / SHA-256 | `NOT RUN` |
| Reproducibility report path / SHA-256 | `NOT RUN` |
| RC manifest path / SHA-256 | `NOT RUN` |
| Candidate build/run | `NOT RUN` |
| Tester | `NOT ASSIGNED` |
| Started (UTC) | `NOT RUN` |
| Completed (UTC) | `NOT RUN` |
| Overall result | **BLOCKED** |

Do not replace `NOT RUN`, `BLOCKED`, `NOT SELECTED`, or `FAIL` with `PASS`
unless the recorded steps were executed against the exact candidate commit and
the referenced artifacts are retained.

## Required external evidence IDs (13)

Formal 1.0 requires retained PASS records for **exactly** these IDs against one
immutable candidate SHA (order matches `scripts/release_schema.py`):

```text
W1-ubuntu-chromium
W1-ubuntu-firefox
W1-fedora-chromium
W1-fedora-firefox
W1-arch-chromium
W1-arch-firefox
D1-ubuntu-appimage
D1-ubuntu-deb
D1-fedora-appimage
D1-fedora-rpm
D1-arch-appimage
C1-web
C1-desktop
```

| ID | Surface (summary) | Candidate result |
|---|---|---|
| `W1-ubuntu-chromium` | Ubuntu 24.04 + Chromium stable + Web ZIP | NOT RUN |
| `W1-ubuntu-firefox` | Ubuntu 24.04 + Firefox stable + Web ZIP | NOT RUN |
| `W1-fedora-chromium` | Fedora current stable + Chromium + Web ZIP | NOT RUN |
| `W1-fedora-firefox` | Fedora current stable + Firefox + Web ZIP | NOT RUN |
| `W1-arch-chromium` | Arch current + Chromium + Web ZIP | NOT RUN |
| `W1-arch-firefox` | Arch current + Firefox + Web ZIP | NOT RUN |
| `D1-ubuntu-appimage` | Ubuntu + AppImage desktop persistence | NOT RUN |
| `D1-ubuntu-deb` | Ubuntu + deb desktop persistence | NOT RUN |
| `D1-fedora-appimage` | Fedora + AppImage desktop persistence | NOT RUN |
| `D1-fedora-rpm` | Fedora + rpm desktop persistence | NOT RUN |
| `D1-arch-appimage` | Arch + AppImage desktop persistence | NOT RUN |
| `C1-web` | Representative demo completion (web) | NOT RUN |
| `C1-desktop` | Representative demo completion (desktop) | NOT RUN |

## Public release artifacts

First-candidate package set (names match `build_release_artifacts.sh` /
`EXPECTED_RELEASE_ARTIFACTS`):

| Artifact | Role |
|---|---|
| `moonsight-web-x86_64-v1.0.0.zip` | Web package |
| `moonsight-linux-x86_64-v1.0.0.AppImage` | Desktop AppImage |
| `moonsight-linux-x86_64-v1.0.0.deb` | Desktop deb |
| `moonsight-linux-x86_64-v1.0.0.rpm` | Desktop rpm |
| `SHA256SUMS` | Canonical digests for the four packages |

Artifacts are delivered via **GitHub Release** attachments, not GitHub Pages.

## External evidence lifecycle

Evidence is collected **outside** the immutable candidate commit. Sequence:

1. **Freeze** — select candidate SHA; `rc_manifest.py guard` rejects dirty tree
   or mismatched `HEAD`.
2. **Records outside commit** — operators write the 13 evidence records (and
   related logs/screenshots) in an external evidence directory; untracked files
   must not alter the candidate commit.
3. **`release_evidence.py build-index`** — build the public evidence index from
   candidate + records directory.
4. **`verify_release_evidence.py`** — produce the Final Gate Report
   (`final-gate.json`); technical readiness must be true before publication.
5. **Operator secondary confirm** — human review of gate, digests, and notes;
   secondary confirmation is not CI.
6. **Publisher** — dry-run `publish_github_release.py` first; execute only with
   `--execute --authorize v1.0.0` after Final Gate PASS and confirmation.

Tool commands and dry-run/execute publisher examples:
[`formal-1.0-rc-tooling.md`](./formal-1.0-rc-tooling.md).

## Automated release matrix

The repository CI workflow enforces the following checks. Record the exact
candidate SHA, retained command output path, artifact digest, and GitHub
Actions run URL rather than copying results from another SHA. Benchmark,
two-build reproducibility, and immutable RC-manifest procedures are defined in
[`formal-1.0-rc-tooling.md`](./formal-1.0-rc-tooling.md).

| Surface | Required check | Candidate result |
|---|---|---|
| MoonBit | `moon fmt --check` | NOT RUN |
| MoonBit | `moon check --target all` | NOT RUN |
| MoonBit | `moon test` | NOT RUN |
| MoonBit | `moon build --target wasm-gc --release host_web` | NOT RUN |
| Web host | tests, `npx tsc --noEmit`, production build | NOT RUN |
| CLI | version, demo check, `new -> check -> build`, demo build | NOT RUN |
| CLI negative | build without `apps/host-web/dist` fails clearly | NOT RUN |
| Author IDs | portable dot-separated IDs; missing/duplicate/invalid diagnostics include file/span/ID/locale | NOT RUN |
| Locale catalogs | strict complete key equality; no text fallback; atomic hot switch | NOT RUN |
| Package | deterministic MSB2 executable + embedded catalogs; missing/empty/corrupt bundle rejected | NOT RUN |
| Save | writer v5; readers v2-v5; stable compatibility mapping and dissolve defaults/progress | NOT RUN |
| Rollback | aggregate `EngineLogicalState`; 64-entry/16 MiB limits; barriers and zero-mutation unavailable path | NOT RUN |
| Reproducibility | two clean builds compared with the reviewed normalization allowlist | NOT RUN |
| Benchmarks | five warm/cold runs, catalog/rollback memory, rendered-frame regression limits | NOT RUN |
| RC manifest | exact SHA, toolchains, locks, environment, commands, report/artifact digests; guard passes | NOT RUN |
| Release tooling | `python3 -m unittest discover -s scripts -p 'test_*.py'` (includes publisher tests) | NOT RUN |
| Docs | typecheck and production build | NOT RUN |
| Desktop Rust | format, check, tests | NOT RUN |

**Candidate CI run:** `NOT RUN`

CI green proves tooling and automated gates only. It does **not** authorize
W1/D1/C1 PASS, a tag, or a published GitHub Release.

### Retained automated evidence

| Check | Exact command | Output path | SHA-256 | Result |
|---|---|---|---|---|
| Candidate guard | `NOT RUN` | `NOT RUN` | `NOT RUN` | NOT RUN |
| Benchmark report | `NOT RUN` | `NOT RUN` | `NOT RUN` | NOT RUN |
| Reproducibility comparison | `NOT RUN` | `NOT RUN` | `NOT RUN` | NOT RUN |
| RC manifest generation | `NOT RUN` | `NOT RUN` | `NOT RUN` | NOT RUN |
| Evidence index | `NOT RUN` | `NOT RUN` | `NOT RUN` | NOT RUN |
| Final gate | `NOT RUN` | `NOT RUN` | `NOT RUN` | NOT RUN |

## W1 — WebGPU browser play and web persistence

**Status: NOT RUN**

Required IDs: `W1-ubuntu-chromium`, `W1-ubuntu-firefox`, `W1-fedora-chromium`,
`W1-fedora-firefox`, `W1-arch-chromium`, `W1-arch-firefox`.

### Environment

- Candidate commit:
- Packaged artifact / checksum:
- Exact candidate commit and clean-tree proof:
- RC manifest / checksum:
- OS and version:
- Browser and version:
- GPU and driver:
- WebGPU adapter information:
- Tester:
- Timestamp (UTC):

### Steps and expected results

1. Serve the candidate web package over HTTP and open it in a browser with a
   real WebGPU adapter.
2. Confirm title -> Start -> advance works without the error panel.
3. Save to a slot, record the visible slot metadata, and reload the page.
4. Load the slot and confirm scene, text, variables, layers, UI, and audio state
   resume at the saved point.
5. Switch between `en` and `zh-Hans-CN` while playing. Confirm the operation is
   atomic, catalogs are complete, and no display-text fallback occurs.
6. Exercise available rollback, a compensatable BGM transition, and a barrier.
   Confirm blocked rollback reports `rollback.unavailable.*` and produces zero
   logical/UI/backend mutation.
7. Separately serve a package with missing, empty, and corrupt `game.msb` files.
   Each package must show a production boot error and must not enter the demo.

### Actual result and artifacts

- Result: NOT RUN
- Actual behavior:
- Console / application logs:
- Screenshots or video:
- Saved `localStorage` inspection:
- Issues:

## D1 — Tauri full-exit persistence

**Status: NOT RUN**

Required IDs: `D1-ubuntu-appimage`, `D1-ubuntu-deb`, `D1-fedora-appimage`,
`D1-fedora-rpm`, `D1-arch-appimage`.

### Environment

- Candidate commit:
- Packaged artifact / checksum:
- Exact candidate commit and clean-tree proof:
- RC manifest / checksum:
- OS and version:
- Tauri/WebView version:
- GPU and driver:
- appData directory:
- Tester:
- Timestamp (UTC):

### Steps and expected results

1. Launch the candidate desktop package and play to a known point.
2. Save to slot 0 and change at least one preference.
3. Fully exit the application; confirm no MoonSight process remains.
4. Inspect `prefs.json`, `saves/0.json`, and any `.tmp`/`.bak` files in appData.
5. Relaunch, load slot 0, and confirm progress and preferences persist.
6. Record last-good recovery behavior if a recovery fixture is exercised.

### Actual result and artifacts

- Result: NOT RUN
- Actual behavior:
- Desktop / Rust logs:
- Screenshots or video:
- Redacted appData file listing and checksums:
- Issues:

## C1 — Representative demo completion

**Status: NOT RUN**

Required IDs: `C1-web`, `C1-desktop`.

### Environment

- Candidate commit:
- Package / checksum:
- RC manifest / checksum:
- Host (web or desktop) and version:
- OS / browser / webview / GPU:
- Tester:
- Timestamp (UTC):

### Steps and expected results

1. Start a fresh playthrough of `demo/game` from the title.
2. Complete the representative story arc without debug shortcuts.
3. Exercise choices, menu save/load, quick save/load, preferences, backlog,
   atomic locale switching, rollback/barrier behavior, and return-to-title
   behavior during the playthrough.
4. Record the ending reached, elapsed time, and every blocking or confusing
   issue encountered.

### Actual result and artifacts

- Result: NOT RUN
- Ending / completion point:
- Elapsed play time:
- Screenshots or video:
- Logs:
- Issues:

## Release decision

Formal 1.0 can be marked ready only when the automated matrix is green and all
13 required external evidence IDs are `PASS` for the same immutable candidate
commit, the Final Gate Report is retained, and a human secondary confirmation
authorizes publication. Any `FAIL`, `BLOCKED`, `NOT RUN`, mismatched SHA, or
missing artifact keeps the release blocked.
