# Formal 1.0 — Full Local Tooling Verification and Candidate Dry Run

**Status:** `DONE_WITH_CONCERNS`  
**Date (UTC):** 2026-07-13T12:34:15Z  
**Branch:** `feat/formal-1.0-release`  
**HEAD SHA:** `839bc31292b6d52c29344034cea4ab1d28ca38b6`  
**Task:** Task 8 — prove release tooling works; **does not** run real W1/D1/C1 GUI evidence and **does not** publish.

## Explicit non-claims

| Claim | Result |
| --- | --- |
| Real W1 / D1 / C1 GUI evidence against this candidate | **NOT RUN** |
| Annotated tag `v1.0.0` on the real repository | **NOT CREATED** (pre/post check: `refs/tags/v1.0.0` absent) |
| GitHub Release for MoonSight v1.0.0 | **NOT PUBLISHED** (publisher dry-run only; no `gh release create` executed against a real remote) |
| Formal 1.0 release authorization | **NOT GRANTED** (`publication_authorized` remains false even on synthetic Final Gate PASS) |

## Environment

| Tool | Version / note |
| --- | --- |
| OS | Linux x86_64 |
| `CC` | `gcc` (exported for matrix) |
| moon | 0.1.20260703 (6fbf8c3 2026-07-03) |
| moonc | v0.10.3+16975d007 (2026-07-03) |
| node | v24.13.1 |
| npm | 11.8.0 |
| rustc | 1.97.0 (2d8144b78 2026-07-07) |
| cargo | 1.97.0 (c980f4866 2026-06-30) |
| python3 | 3.14.6 |
| Desktop packaging | deb/rpm produced by Tauri; AppImage bundling failed (`linuxdeploy`) — see §2 |

---

## 1. Automated matrix

Commands run from repository root with `export CC=gcc`.

| Step | Command | Result | Notes |
| --- | --- | --- | --- |
| Format | `moon fmt --check` | **PASS** | exit 0; 111 tasks up to date |
| Check all targets | `moon check --target all` | **PASS** | exit 0; 0 errors (existing deprecation warnings in wbtests only) |
| Unit / integration | `moon test` | **PASS** | Total tests: 283, passed: 283, failed: 0 |
| WASM host | `moon build --target wasm-gc --release host_web` | **PASS** | exit 0 |
| Host web install | `cd apps/host-web && npm ci` | **PASS** | 41 packages |
| Host web tests | `npm test` | **PASS** | 44 tests, 0 failed |
| Host web types | `npx tsc --noEmit` | **PASS** | exit 0 |
| Host web build | `npm run build` | **PASS** | vite production build OK |
| CLI check | `moon run cmd/moonsightc --target native -- check demo/game` | **PASS** | 4 ok, 0 failed |
| CLI package | `moon run cmd/moonsightc --target native -- build demo/game -o dist/demo` | **PASS** | build ok → `dist/demo` (gitignored) |
| Package smoke | `./scripts/verify-package.sh dist/demo` | **PASS** | `OK: verified packaged distribution at dist/demo` |
| Python release tooling | `python3 -m unittest discover -s scripts -p 'test_*.py'` | **PASS** | Ran 99 tests in ~4.9s — OK |
| Desktop npm | `cd host_desktop/tauri && npm ci` | **PASS** | 3 packages |
| Desktop fmt | `cargo fmt --check --manifest-path src-tauri/Cargo.toml` | **PASS** | exit 0 |
| Desktop check | `cargo check --manifest-path src-tauri/Cargo.toml` | **PASS** | exit 0 |
| Desktop tests | `cargo test --manifest-path src-tauri/Cargo.toml` | **PASS** | 5 lib tests passed |

**Automated matrix overall: PASS**

No product defects found in Tasks 1–7 ownership during this matrix. No fix commits required.

---

## 2. Artifact dual-build and reproducibility

### Commands attempted

```bash
RELEASE_OUT="$(mktemp -d /tmp/moonsight-rc-XXXX)"
./scripts/build_release_artifacts.sh --version v1.0.0 --out "$RELEASE_OUT"
# compare not reached:
# python3 scripts/compare_reproducible_builds.py "$RELEASE_OUT/first" "$RELEASE_OUT/second" \
#   --allowlist scripts/reproducibility-normalization-v1.json \
#   --output "$RELEASE_OUT/repro-report.json"
```

### Result: **BLOCKED** (environment / packaging toolchain)

| Phase | Result | Detail |
| --- | --- | --- |
| Worktree cleanliness gate | PASS | Script requires clean worktree; satisfied |
| Web package (publish-web + zip) | PASS (during first set) | `moonsight-web-x86_64-v1.0.0.zip` path built via `publish-web.sh` |
| Desktop Tauri release compile | PASS | `Finished release profile` for moonsight |
| Desktop deb bundle | PASS (observed) | `MoonSight_1.0.0_amd64.deb` produced |
| Desktop rpm bundle | PASS (observed) | `MoonSight-1.0.0-1.x86_64.rpm` produced |
| Desktop AppImage bundle | **FAIL** | Tauri: `failed to bundle project: failed to run linuxdeploy` / `Error failed to bundle project: failed to run linuxdeploy` |
| Dual dirs `first` / `second` | **NOT PRODUCED** | Script exits 1 before promoting staging to `$RELEASE_OUT` |
| `compare_reproducible_builds.py` | **NOT RUN** | No dual trees to compare |

**Exact failure (verbatim from build log):**

```text
Bundling MoonSight_1.0.0_amd64.AppImage (.../bundle/appimage/MoonSight_1.0.0_amd64.AppImage)
failed to bundle project: `failed to run linuxdeploy`
       Error failed to bundle project: `failed to run linuxdeploy`
BUILD_RC_EXIT=1
```

**Interpretation:** This is an environment/packaging-host issue during AppImage bundling (Tauri downloads `linuxdeploy-*.AppImage` and fails to run it). It is **not** treated as a product defect in Tasks 1–7 ownership for this verification pass. No code fix was applied. Dual-build/repro remains **BLOCKED** on a host with working AppImage/`linuxdeploy` packaging.

Temp release directory cleaned after capture; worktree left without untracked release artifact dirs.

---

## 3. Synthetic gate fixture (temp git repo)

**Method:** Temporary git repository **outside** the real worktree (no mutation of real tags). Fixture patterns follow unit tests for `release_evidence.py` / `verify_release_evidence.py` / publisher, using real CLIs:

1. `git init` + single commit → candidate SHA  
2. Four synthetic artifact files + `SHA256SUMS` with matching digests  
3. Full schema-v2 candidate manifest bound to that commit  
4. Thirteen PASS evidence records under `records/`  
5. `python3 scripts/release_evidence.py build-index ...`  
6. `python3 scripts/verify_release_evidence.py ...`  
7. Flip first record to `NOT_RUN`, rebuild index, re-verify (expect fail)  
8. Temp dir removed after verification (`shutil.rmtree`)

| Step | Result | Detail |
| --- | --- | --- |
| build-index (13 PASS) | **PASS** | `aggregate_status=PASS`, 13 records |
| Final Gate (13 PASS) | **PASS** | `technical_release_ready=true`, `publication_authorized=false`, reasons `[]` |
| build-index after flip W1-ubuntu-chromium → NOT_RUN | **PASS** | `aggregate_status=NOT_RUN` |
| Final Gate after NOT_RUN flip | **PASS** (gate correctly fails) | exit 1; `technical_release_ready=false`; reasons include `index.aggregate_status must be PASS` and `records[0].status must be PASS` |

**Synthetic gate overall: PASS**

---

## 4. Publisher dry-run (synthetic fixture)

Command shape (paths under the temporary fixture; **not** the real remote):

```bash
python3 scripts/publish_github_release.py \
  --repo <temp-repo> \
  --candidate <candidate.json> \
  --index <evidence-index.json> \
  --gate <final-gate.json> \
  --artifacts <artifacts-dir> \
  --notes <notes.md>
```

| Check | Result | Detail |
| --- | --- | --- |
| Exit code | **PASS** | 0 |
| Output | **PASS** | JSON plan with `mode: "dry-run"`, `version: "v1.0.0"` |
| Tags | **PASS** | No `refs/tags/v1.0.0` created on temp or real repo |
| Draft-first plan | **PASS** | `create-draft` includes `--draft` |
| Last mutator | **PASS** | `publish` phase: `gh release edit v1.0.0 --draft=false` |
| Planned phases | **PASS** | `tag` → `push-tag` → `create-draft` → `upload` → `view-assets` → `download-verify` → `publish` |
| Attachment digests | **PASS** | Plan binds digests for 4 packages + `SHA256SUMS` + metadata files |
| Execute / remote publish | **NOT RUN** | No `--execute`; no `gh release create` against real remote |

**Publisher dry-run overall: PASS**

---

## 5. Worktree hygiene

| Check | Result |
| --- | --- |
| Real repo `v1.0.0` tag absent after all steps | PASS |
| Synthetic fixture removed from `/tmp` | PASS |
| Dual-build temp cleaned | PASS |
| No untracked release candidate directories left in worktree | PASS |
| Only intended deliverable for this task | this report file (committed separately) |

---

## 6. Summary table

| Area | Status |
| --- | --- |
| Automated matrix (moon / host-web / moonsightc / package / python / desktop cargo) | **PASS** |
| Artifact dual-build + reproducibility compare | **BLOCKED** (AppImage `linuxdeploy` host failure) |
| Synthetic 13-PASS Final Gate | **PASS** |
| Synthetic NOT_RUN flip fails gate | **PASS** |
| Publisher dry-run JSON plan, no tags, last mutator `--draft=false` | **PASS** |
| Real W1/D1/C1 evidence | **NOT RUN** |
| v1.0.0 publish | **NOT PUBLISHED** |

## 7. Overall status

**`DONE_WITH_CONCERNS`**

- All required local tooling paths that are not packaging-host dependent **PASS**.
- Dual-build/repro remains **BLOCKED** until AppImage bundling works on the release host (`linuxdeploy` run failure after successful deb/rpm bundling).
- Formal public 1.0 remains blocked on **real** W1/D1/C1 evidence and human authorization; this task only proves tooling.

## 8. Commit intent

```text
test: verify Formal 1.0 release tooling dry-run
```

Only this report is added. No product fix commits (none required).
