# MoonSight Formal 1.0 Public Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an exact-SHA, evidence-gated release pipeline that publishes MoonSight `v1.0.0` as a Web ZIP plus Linux x86_64 AppImage, deb, and rpm only after the full 13-item support matrix passes.

**Architecture:** Keep runtime behavior unchanged. Split release support into immutable candidate identity, separately generated evidence index/final gate report, deterministic artifact assembly, and a draft-first GitHub publisher. Existing Python release tooling remains the owner of schemas and validation; shell scripts orchestrate builds without becoming product APIs.

**Tech Stack:** Python 3 standard library and `unittest`, Bash, MoonBit CLI, Node/Vite/Svelte, Rust/Tauri 2, Git, GitHub CLI (`gh`).

## Global Constraints

- Target version is exactly `v1.0.0`; release tag must be annotated and point to the frozen candidate SHA.
- Public artifacts are x86_64 Web ZIP, AppImage, deb, rpm, and `SHA256SUMS`.
- Formal Web matrix is Chromium stable and Firefox stable on Ubuntu 24.04, frozen Fedora stable, and a frozen-date Arch snapshot.
- Formal Desktop matrix is AppImage+deb on Ubuntu, AppImage+rpm on Fedora, and AppImage on Arch.
- Exactly 13 evidence IDs are mandatory; any `FAIL`, `BLOCKED`, `NOT_RUN`, missing, duplicate, SHA mismatch, or digest mismatch blocks release.
- W1/D1/C1 evidence is external to the frozen candidate commit; public evidence is redacted and digest-linked to retained raw evidence.
- GitHub Release must remain draft until every remote attachment and digest is verified.
- No new runtime features or dependencies; no GitHub Pages, Windows, macOS, signing, or repository publication work.
- Publisher dry-run is safe and local; tag push and public Release require explicit operator authorization and valid credentials.

---

## Behavior Coverage

### Scenarios

| Scenario | Example | Observable evidence | Expected result | Failure signal | If it fails |
| --- | --- | --- | --- | --- | --- |
| S1 Web W1 | Final Web ZIP on each OS/browser pair: play, save, reload, locale switch, rollback/barrier, corrupt MSB fixtures | Six evidence JSON files plus logs/screenshots and source artifact digest | Every `W1-*` ID is `PASS` and references the frozen SHA/Web ZIP | Adapter failure, partial restore/switch, mutation past barrier, or wrong digest | Fix implementation/environment, freeze a new candidate, rerun all evidence |
| S2 Desktop D1 | Install/run each required package, save prefs/slot, fully exit, restart | Five evidence JSON files, process check, redacted appData listing | Every `D1-*` ID is `PASS`; appData survives complete exit | Install/start failure, live process, lost/corrupt state, wrong artifact | Fix and create a new candidate; never reuse old evidence |
| S3 Demo C1 | Complete demo once from Web ZIP and once from a desktop artifact | Ending, elapsed time, logs/video, artifact digest | `C1-web` and `C1-desktop` both `PASS` | Debug shortcut required, blocked story, state drift | Correct product or test procedure, then rerun full candidate matrix |
| S4 Gate rejection | Remove an evidence ID, duplicate one, change SHA/digest, or set `NOT_RUN` | Validator stderr and non-zero exit | Release gate rejects with the exact reason | Gate returns success | Return to implementation/tests; spec only if matrix meaning changes |
| S5 Draft-first publish | Run publisher dry-run, then authorized publish against a test/draft target | Command transcript and remote attachment list | Draft created, attachments verified, only then published | Public release appears incomplete or tag points elsewhere | Stop; never move/delete conflicting public history without human decision |

### Automation / Observation / Correction

| Scenario | Automated check | Human observation | Failure response |
| --- | --- | --- | --- |
| S1 | Schema, ID, SHA and digest validation | Real WebGPU behavior, visible state, logs | New candidate and complete rerun |
| S2 | Schema/digest validation and package smoke | GUI exit, appData recovery | New candidate and complete rerun |
| S3 | Evidence completeness and digest binding | Full playthrough | Product/test correction and rerun |
| S4 | Python unit tests for every rejection branch | None | Fix gate implementation |
| S5 | Publisher dry-run and mocked `gh` command tests | Final external authorization and GitHub UI/API verification | Keep Release draft; resolve conflict explicitly |

### Cross-Task Invariants

- Candidate identity never contains post-freeze W1/D1/C1 results.
- Evidence tooling records facts but never changes runtime/save/localization behavior.
- Final Gate Report means technical readiness, not external publication authorization.
- The first artifact build is the release candidate; the second build exists only for reproducibility comparison.
- Negative MSB fixtures are derived evidence artifacts and are never uploaded as release game packages.

## File Structure

- `scripts/release_schema.py`: shared schema constants, evidence IDs, digest and JSON helpers.
- `scripts/rc_manifest.py`: generate immutable candidate identity schema v2 and guard frozen SHA.
- `scripts/release_evidence.py`: validate individual evidence records and generate public Evidence Index.
- `scripts/verify_release_evidence.py`: create/validate Final Gate Report against candidate and index.
- `scripts/build_release_artifacts.sh`: build the first candidate artifact set and `SHA256SUMS`.
- `scripts/compare_reproducible_builds.py`: compare Web byte identity and normalized desktop payload identity.
- `scripts/publish_github_release.py`: dry-run/default publisher; annotated tag and draft-first GitHub workflow.
- `scripts/release-evidence-template.json`: copyable record with all required fields.
- `scripts/test_release_schema.py`, `scripts/test_release_evidence.py`, `scripts/test_publish_github_release.py`: focused Python tests.
- `docs/release-1.0-verification.md`: 13 IDs, external evidence lifecycle, exact commands, and retained BLOCKED state before real runs.
- `README.mbt.md`, `README.en.md`, `CHANGELOG.md`: final support and artifact statements.
- `.github/workflows/ci.yml`: run new tooling tests and artifact dry-run checks without claiming GUI PASS.

### Task 1: Shared Release Schema and Exact Evidence Matrix

**Files:**
- Create: `scripts/release_schema.py`
- Create: `scripts/test_release_schema.py`

**Behavior coverage:** implements S4; preserves all cross-task invariants

**Interfaces:**
- Produces: `REQUIRED_EVIDENCE_IDS: tuple[str, ...]`, `sha256_file(path: Path) -> str`, `read_object(path: Path, label: str) -> dict[str, Any]`, `validate_sha256(value: Any, path: str, errors: list[str]) -> str`.

- [ ] **Step 1: Write failing schema tests**

```python
from release_schema import REQUIRED_EVIDENCE_IDS

def test_required_matrix_is_closed_and_unique():
    assert len(REQUIRED_EVIDENCE_IDS) == 13
    assert len(set(REQUIRED_EVIDENCE_IDS)) == 13
    assert REQUIRED_EVIDENCE_IDS[0] == "W1-ubuntu-chromium"
    assert REQUIRED_EVIDENCE_IDS[-1] == "C1-desktop"
```

- [ ] **Step 2: Confirm failure**

Run: `python3 -m unittest scripts/test_release_schema.py -v`  
Expected: `ModuleNotFoundError: No module named 'release_schema'`.

- [ ] **Step 3: Implement constants and helpers**

```python
REQUIRED_EVIDENCE_IDS = (
    "W1-ubuntu-chromium", "W1-ubuntu-firefox",
    "W1-fedora-chromium", "W1-fedora-firefox",
    "W1-arch-chromium", "W1-arch-firefox",
    "D1-ubuntu-appimage", "D1-ubuntu-deb",
    "D1-fedora-appimage", "D1-fedora-rpm",
    "D1-arch-appimage", "C1-web", "C1-desktop",
)
```

Add strict object/hex digest helpers using only the Python standard library.

- [ ] **Step 4: Run tests**

Run: `python3 -m unittest scripts/test_release_schema.py -v`  
Expected: all tests `OK`.

- [ ] **Step 5: Commit**

```bash
git add scripts/release_schema.py scripts/test_release_schema.py
git commit -m "feat: define Formal 1.0 release evidence matrix"
```

### Task 2: Immutable Candidate Identity Manifest v2

**Files:**
- Modify: `scripts/rc_manifest.py`
- Modify: `scripts/test_release_candidate_tools.py`
- Create: `scripts/release-evidence-template.json`

**Behavior coverage:** preserves candidate/evidence separation and first-build invariant

**Interfaces:**
- Consumes: `REQUIRED_EVIDENCE_IDS`, digest/JSON helpers.
- Produces: candidate manifest schema v2 with attempt ID, `candidate.commit`, `candidate.version`, `candidate.architecture`, clean-tree proof, build UTC/host, exact toolchain/system/validation-target versions, first-build artifact path/size/SHA-256, reproducibility report references/digests, required evidence IDs, automated results, and no external result statuses.

- [ ] **Step 1: Add failing tests** asserting schema v2 rejects `external_checks`; requires candidate attempt ID, version `v1.0.0`, architecture `x86_64`, clean-tree proof, build UTC/host, exact Fedora/Arch/browser/toolchain/system versions, artifact sizes/digests, reproducibility input/report digests; and preserves `O_EXCL` immutability.
- [ ] **Step 2: Run failure**

Run: `python3 -m unittest scripts/test_release_candidate_tools.py -v`  
Expected: failures showing schema version 1 and legacy `external_checks`.

- [ ] **Step 3: Change generated shape**

```python
manifest = {
    "schema_version": 2,
    "attempt_id": metadata["attempt_id"],
    "candidate": {
        "version": "v1.0.0",
        "commit": args.candidate,
        "architecture": "x86_64",
        "clean_tree": metadata["clean_tree"],
        "built_at_utc": metadata["built_at_utc"],
        "build_host": metadata["build_host"],
        "artifacts": candidate_artifacts,
    },
    "toolchains": metadata["toolchains"],
    "system": metadata["system"],
    "reproducibility": reproducibility_reference,
    "validation_targets": metadata["validation_targets"],
    "required_evidence_ids": list(REQUIRED_EVIDENCE_IDS),
    "automated_checks": automated_checks,
    "notice": "Candidate identity does not authorize publication.",
}
```

Keep `guard` exact-HEAD and tracked-clean behavior.

- [ ] **Step 4: Add concrete template fields**: `schema_version`, `id`, `status`, `candidate_commit`, `artifact.path`, `artifact.sha256`, OS/version, kernel, desktop environment, browser or WebView/version, GPU, driver, UTC timestamp, tester, ordered executed steps with per-step expected/actual/result, logs, screenshots/video, redacted save/localStorage inspection, public evidence digest, raw evidence digest, and redaction statement.
- [ ] **Step 5: Run tests and validator smoke**

Run: `python3 -m unittest scripts/test_release_candidate_tools.py scripts/test_release_schema.py -v`  
Expected: all tests `OK`.

- [ ] **Step 6: Commit**

```bash
git add scripts/rc_manifest.py scripts/test_release_candidate_tools.py scripts/release-evidence-template.json
git commit -m "feat: separate immutable candidate identity from evidence"
```

### Task 3: Evidence Record Validation and Evidence Index

**Files:**
- Create: `scripts/release_evidence.py`
- Create: `scripts/test_release_evidence.py`

**Behavior coverage:** automates S1, S2, S3 evidence binding; implements S4

**Interfaces:**
- Produces CLI: `release_evidence.py validate-record CANDIDATE RECORD` and `release_evidence.py build-index --candidate ... --records DIR --output ...`.
- Evidence Index schema v1 contains exactly 13 IDs, public/raw digests, candidate SHA, artifact reference, and aggregate status.

- [ ] **Step 1: Write failing tests** for missing ID, duplicate ID, unknown ID, `NOT_RUN`, wrong candidate SHA, wrong artifact digest, and absent/empty OS, kernel, desktop, browser/WebView, GPU, driver, tester, UTC timestamp, executed steps/per-step results, logs, screenshots/video, save/localStorage inspection, raw/public digests, or redaction statement; also test a complete 13-record `PASS` index.
- [ ] **Step 2: Confirm failure**

Run: `python3 -m unittest scripts/test_release_evidence.py -v`  
Expected: import/CLI failures.

- [ ] **Step 3: Implement strict record validator**

```python
def validate_record(candidate: dict[str, Any], record: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if record.get("id") not in REQUIRED_EVIDENCE_IDS:
        errors.append("record.id is not a required evidence ID")
    if record.get("candidate_commit") != candidate["candidate"]["commit"]:
        errors.append("record.candidate_commit must equal candidate commit")
    if record.get("status") not in {"PASS", "FAIL", "BLOCKED", "NOT_RUN"}:
        errors.append("record.status is invalid")
    return errors
```

Extend it to verify the referenced artifact path/digest and every human-reviewable evidence field listed in Task 2 Step 4. A `PASS` record must have non-empty ordered steps and every step result must be `PASS`; negative fixture records must include derived artifact provenance.

- [ ] **Step 4: Implement immutable index creation** with `os.O_EXCL`; sort records by `REQUIRED_EVIDENCE_IDS`, reject duplicates/missing IDs, and set aggregate `PASS` only when every item passes.
- [ ] **Step 5: Run tests**

Run: `python3 -m unittest scripts/test_release_evidence.py -v`  
Expected: all tests `OK`.

- [ ] **Step 6: Commit**

```bash
git add scripts/release_evidence.py scripts/test_release_evidence.py
git commit -m "feat: validate release evidence and build exact matrix index"
```

### Task 4: Final Technical Gate Report

**Files:**
- Modify: `scripts/verify_release_evidence.py`
- Modify: `scripts/test_verify_release_evidence.py`

**Behavior coverage:** implements S4; keeps technical readiness separate from authorization

**Interfaces:**
- CLI: `verify_release_evidence.py --repo . --candidate candidate.json --index evidence-index.json --output final-gate.json`.
- Produces schema v1 report with `technical_release_ready: bool`, reasons, candidate/index digests, and explicit `publication_authorized: false`.

- [ ] **Step 1: Replace legacy manifest tests** with candidate+index tests for all 13 PASS, missing ID, duplicate ID, wrong commit, artifact mismatch, failed automation, HEAD different from candidate, dirty tracked/untracked release-content files, and an existing `v1.0.0` tag.
- [ ] **Step 2: Run failure**

Run: `python3 -m unittest scripts/test_verify_release_evidence.py -v`  
Expected: legacy API mismatch failures.

- [ ] **Step 3: Implement final gate**

```python
report = {
    "schema_version": 1,
    "candidate_sha256": sha256_file(args.candidate),
    "evidence_index_sha256": sha256_file(args.index),
    "technical_release_ready": not errors,
    "publication_authorized": False,
    "reasons": errors,
}
```

Before creating the report, run Git checks against `--repo`: `rev-parse HEAD` must equal the candidate, `status --porcelain=v1` must be empty, and `show-ref --verify refs/tags/v1.0.0` must fail. Exit 0 only when technically ready; write report immutably in both pass and fail cases.

- [ ] **Step 4: Run tests**

Run: `python3 -m unittest scripts/test_verify_release_evidence.py scripts/test_release_evidence.py -v`  
Expected: all tests `OK`.

- [ ] **Step 5: Commit**

```bash
git add scripts/verify_release_evidence.py scripts/test_verify_release_evidence.py
git commit -m "feat: add immutable Formal 1.0 technical release gate"
```

### Task 5: Versioned Artifact Builder and Reproducibility Boundary

**Files:**
- Create: `scripts/build_release_artifacts.sh`
- Modify: `scripts/publish-web.sh`
- Modify: `scripts/publish-desktop.sh`
- Modify: `scripts/compare_reproducible_builds.py`
- Modify: `scripts/reproducibility-normalization-v1.json`
- Modify: `scripts/test_release_candidate_tools.py`

**Behavior coverage:** preserves first-build and identical-payload invariants; supports S1/S2/S3

**Interfaces:**
- CLI: `build_release_artifacts.sh --version v1.0.0 --out RELEASE_DIR`.
- Output exact filenames from Global Constraints and machine-readable build metadata.

- [ ] **Step 1: Add failing tests** for exact x86_64 filenames, first/second build separation, normalized desktop payload comparison, and rejection of unexplained differences.
- [ ] **Step 2: Run failure**

Run: `python3 -m unittest scripts/test_release_candidate_tools.py -v`  
Expected: filename/normalization assertions fail.

- [ ] **Step 3: Implement builder preflight**

```bash
test "$(git status --porcelain)" = "" || { echo "error: dirty worktree" >&2; exit 1; }
test "$VERSION" = "v1.0.0" || { echo "error: expected v1.0.0" >&2; exit 1; }
ARCH=x86_64
```

Call existing Web/Tauri builds, zip Web content with normalized timestamps/order, collect Tauri bundle outputs, rename copies deterministically, and create `sha256sum` output for the first build only.

- [ ] **Step 4: Tighten reproducibility comparison** so Web ZIP raw digests match and desktop packages compare normalized extracted application payloads under the versioned policy; never exclude `game.msb`, wasm, JS, resources, or executables.
- [ ] **Step 5: Run tests and shell syntax checks**

Run: `python3 -m unittest scripts/test_release_candidate_tools.py -v && bash -n scripts/build_release_artifacts.sh scripts/publish-web.sh scripts/publish-desktop.sh`  
Expected: all tests and syntax checks pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/build_release_artifacts.sh scripts/publish-web.sh scripts/publish-desktop.sh scripts/compare_reproducible_builds.py scripts/reproducibility-normalization-v1.json scripts/test_release_candidate_tools.py
git commit -m "feat: build reproducible Formal 1.0 release artifacts"
```

### Task 6: Draft-First GitHub Publisher

**Files:**
- Create: `scripts/publish_github_release.py`
- Create: `scripts/test_publish_github_release.py`

**Behavior coverage:** implements S5

**Interfaces:**
- CLI defaults to `--dry-run`; real mode requires `--execute --authorize v1.0.0`.
- Consumes candidate, evidence index, final gate, `SHA256SUMS`, release notes, and four artifacts.

- [ ] **Step 1: Write failing mocked-command tests** asserting annotated tag command, draft creation before upload, attachment verification before `gh release edit --draft=false`, refusal when technical gate is false, authorization string differs, attachment set is incomplete, or an existing local/remote tag resolves to another commit. Also cover recovery states: fresh publication, local tag awaiting push, correctly pushed tag awaiting draft creation, existing draft awaiting missing attachments, and complete draft awaiting publication.
- [ ] **Step 2: Confirm failure**

Run: `python3 -m unittest scripts/test_publish_github_release.py -v`  
Expected: module not found.

- [ ] **Step 3: Implement command planner** returning a list of argv arrays; never use `shell=True`.

```python
if not args.execute:
    print(json.dumps({"mode": "dry-run", "commands": commands}, indent=2))
    return 0
if args.authorize != "v1.0.0":
    raise SystemExit("error: explicit --authorize v1.0.0 required")
```

- [ ] **Step 4: Implement resumable execute sequence**: rerun exact-HEAD, clean-worktree and Final Gate checks; verify `gh auth status`; inspect local tag, remote tag and Release state. If no tag exists, create the annotated tag at the candidate and push it. If a local or remote tag exists, peel it and accept it only when it resolves exactly to the candidate SHA; any conflicting tag stops for human decision. Create the draft only when absent, otherwise resume the existing draft; upload only missing attachments; query the exact attachment set; download every remote attachment into a temporary directory and compare SHA-256 byte-for-byte with the local source. Immediately before publication, re-read and peel the remote annotated tag and confirm it still equals the candidate SHA, then re-read the draft metadata and attachments. Any unavailable lookup/download or mismatch fails closed and leaves the Release draft. Publish via `gh release edit v1.0.0 --draft=false` only after every check passes.
- [ ] **Step 5: Run tests and a local dry-run fixture**

Run: `python3 -m unittest scripts/test_publish_github_release.py -v`  
Expected: all tests `OK`; no Git ref or network mutation.

- [ ] **Step 6: Commit**

```bash
git add scripts/publish_github_release.py scripts/test_publish_github_release.py
git commit -m "feat: add draft-first GitHub release publisher"
```

### Task 7: CI and Release Documentation Alignment

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `docs/release-1.0-verification.md`
- Modify: `docs/formal-1.0-rc-tooling.md`
- Modify: `README.mbt.md`
- Modify: `README.en.md`
- Modify: `CHANGELOG.md`

**Behavior coverage:** observes S1/S2/S3; preserves honest BLOCKED semantics

**Interfaces:**
- CI runs unit/schema/dry-run tests only; it never emits W1/D1/C1 PASS.
- Verification doc contains the exact 13 IDs and external evidence lifecycle.

- [ ] **Step 1: Add CI assertions** to the release-tooling job:

```yaml
- name: Test release schemas, gates, and publisher dry-run
  run: python3 -m unittest discover -s scripts -p 'test_*.py'
```

Keep GUI/WebGPU claims out of CI output.

- [ ] **Step 2: Rewrite verification checklist** with one subsection per exact evidence ID, candidate/artifact digest fields, redaction fields, and `NOT RUN` initial status.
- [ ] **Step 3: Update bilingual support statements** to Linux x86_64; Ubuntu 24.04, Fedora current stable, and Arch current as public support channels; record the exact Fedora version and Arch snapshot date only in candidate evidence; Chromium stable/Firefox stable; Web ZIP/AppImage/deb/rpm; no Pages.
- [ ] **Step 4: Update changelog** to describe tooling readiness without claiming real matrix PASS or publication.
- [ ] **Step 5: Run documentation and tooling checks**

Run: `python3 -m unittest discover -s scripts -p 'test_*.py' && cd apps/docs-site && npm run types:check && npm run build`  
Expected: tests `OK`, typecheck/build exit 0, verification statuses remain `NOT RUN`/`BLOCKED`.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/ci.yml docs/release-1.0-verification.md docs/formal-1.0-rc-tooling.md README.mbt.md README.en.md CHANGELOG.md
git commit -m "docs: define Formal 1.0 release support and evidence matrix"
```

### Task 8: Full Local Verification and Candidate Dry Run

**Files:**
- Modify only if verification exposes a defect in files owned by Tasks 1–7.

**Behavior coverage:** automates S4/S5 and prepares observation of S1/S2/S3

- [ ] **Step 1: Run complete automated matrix**

```bash
export CC=gcc
moon fmt --check
moon check --target all
moon test
moon build --target native --release
moon build --target wasm-gc --release host_web
cd apps/host-web && npm ci && npm test && npx tsc --noEmit && npm run build && cd ../..
moon run cmd/moonsightc --target native -- check demo/game
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
tmp="$(mktemp -d)"; moon run cmd/moonsightc --target native -- new ci-game -o "$tmp"; moon run cmd/moonsightc --target native -- check "$tmp/ci-game"; moon run cmd/moonsightc --target native -- build "$tmp/ci-game" -o "$tmp/new-dist"
./scripts/verify-package.sh dist/demo
python3 -m unittest scripts/test_verify_package.py scripts/test_release_candidate_tools.py scripts/test_verify_release_evidence.py -v
cd apps/docs-site && npm ci && npm run types:check && npm run build && cd ../..
cd host_desktop/tauri && npm ci && cargo fmt --check --manifest-path src-tauri/Cargo.toml && cargo check --manifest-path src-tauri/Cargo.toml && cargo test --manifest-path src-tauri/Cargo.toml && cd ../..
python3 -m unittest discover -s scripts -p 'test_*.py'
```

Expected: every command exits 0.

The package/tooling tests must exercise missing, empty and corrupt `game.msb`, missing host distribution, unknown jump/resource fixtures, CLI `new`, and all release-schema negative branches; do not replace these with a single happy-path package smoke.

- [ ] **Step 2: Build two local artifact sets** and run reproducibility comparison; expected Final Gate remains blocked because real 13-item evidence is absent.
- [ ] **Step 3: Generate candidate identity fixture, 13 synthetic test-only PASS records, Evidence Index, and Final Gate Report in a temporary directory; verify gate PASS for fixtures and rejection after changing one status to `NOT_RUN`.
- [ ] **Step 4: Run publisher dry-run** and inspect that the last mutating command is draft publication only after attachment verification.
- [ ] **Step 5: Record verification evidence** in `.superpowers/sdd/formal-1.0-release-tooling-final-verify-report.md`, explicitly separating tooling PASS from real W1/D1/C1 `NOT RUN`.
- [ ] **Step 6: Commit verification report**

```bash
git add .superpowers/sdd/formal-1.0-release-tooling-final-verify-report.md
git commit -m "test: verify Formal 1.0 release tooling"
```

## Post-Implementation Operational Runbook

These are release operations, not implementation tasks. Execute them only after Tasks 1–8 are merged and the candidate commit is frozen:

1. Build the immutable first artifact set and reproducibility comparison set.
2. Generate candidate identity manifest and run `rc_manifest.py guard` throughout validation.
3. Perform all six W1, five D1, and two C1 real runs on the frozen versions/snapshot.
4. Redact public evidence, retain raw evidence, and build the exact Evidence Index.
5. Generate Final Gate Report; it must show technical readiness and publication authorization false.
6. Present final SHA, artifact digests, matrix and remote target to the authorized operator.
7. Only after explicit authorization, run `publish_github_release.py --execute --authorize v1.0.0 ...`.
8. Verify remote annotated tag, public Release state, attachment set and checksums.
