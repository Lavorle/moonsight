# MoonSight Formal 1.0 Fedora Partial Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Freeze one immutable Formal 1.0 candidate on clean `main`, collect six Fedora/C1 evidence PASS records, leave seven Ubuntu/Arch IDs as honest `NOT_RUN`, produce a negative Final Gate (`technical_release_ready=false`), and hand off Ubuntu/Arch without tagging or publishing `v1.0.0`.

**Architecture:** Pure operational closure on existing release tooling—no new product APIs. Artifacts come from `scripts/build_release_artifacts.sh`; identity from `rc_manifest.py generate`; external JSON records live outside the candidate commit; `release_evidence.py build-index` + `verify_release_evidence.py` prove the matrix is incomplete and must not authorize publication.

**Tech Stack:** Bash, Python 3 release scripts, MoonBit (`moon`), Node/Vite host, Rust/Tauri desktop packaging, Chromium/Firefox WebGPU on Fedora, AppImage/rpm installers.

**Spec:** [`docs/superpowers/specs/2026-07-14-moonsight-formal-1.0-fedora-partial-closure-design.md`](../specs/2026-07-14-moonsight-formal-1.0-fedora-partial-closure-design.md)  
**Matrix authority:** [`docs/superpowers/specs/2026-07-13-moonsight-formal-1.0-public-release-design.md`](../specs/2026-07-13-moonsight-formal-1.0-public-release-design.md)  
**Runbooks:** [`docs/formal-1.0-rc-tooling.md`](../../formal-1.0-rc-tooling.md), [`docs/release-1.0-verification.md`](../../release-1.0-verification.md)

---

## Global Constraints

- **Working tree:** clean checkout of `main` at the intended candidate tip (include AppImage/repro fixes such as `ffaec0c` / `00cd943` or later). Do **not** freeze from dirty tree or from `.worktrees/native-1.1`.
- **Version string:** exactly `v1.0.0` for artifact builder.
- **Artifact names (authoritative):**
  - `moonsight-web-x86_64-v1.0.0.zip`
  - `moonsight-linux-x86_64-v1.0.0.AppImage`
  - `moonsight-linux-x86_64-v1.0.0.deb`
  - `moonsight-linux-x86_64-v1.0.0.rpm`
  - `SHA256SUMS`
- **Exactly 13 evidence IDs** from `scripts/release_schema.py` `REQUIRED_EVIDENCE_IDS`.
- **This plan PASS set (6):**  
  `W1-fedora-chromium`, `W1-fedora-firefox`, `D1-fedora-appimage`, `D1-fedora-rpm`, `C1-web`, `C1-desktop`.
- **This plan NOT_RUN set (7):**  
  `W1-ubuntu-chromium`, `W1-ubuntu-firefox`, `D1-ubuntu-appimage`, `D1-ubuntu-deb`,  
  `W1-arch-chromium`, `W1-arch-firefox`, `D1-arch-appimage`.
- **Forbidden:** annotated `v1.0.0` tag; `publish_github_release.py --execute`; claiming Overall PASS in docs.
- **Evidence root (outside git / gitignored):**  
  `EVIDENCE_ROOT="${HOME}/moonsight-evidence/formal-1.0/<candidate_short12>"`  
  Never `git add` raw logs/screenshots into the candidate commit.
- **String equality traps (validators are strict):**
  - `record.candidate_commit` == `candidate.candidate.commit` (full 40-char SHA).
  - Fedora: `record.environment.os_version` == `candidate.system.fedora` (exact string).
  - Arch stubs: `record.environment.os_version` == `candidate.system.arch`.
  - Ubuntu stubs: `record.environment.os_version` must be exactly `24.04`.
  - Browser versions: `record.environment.browser_or_webview_version` == matching `candidate.validation_targets.{chromium,firefox,webkitgtk}`.
  - D1 records: `browser_or_webview` must be `WebKitGTK` (Tauri webview label in schema).
  - W1 PASS records **must** include `negative_fixtures` for `missing-msb`, `empty-msb`, `corrupt-msb`.
  - C1-web: Fedora + Chromium or Firefox + Web ZIP is allowed if versions match candidate.
  - C1-desktop: Fedora + WebKitGTK + AppImage **or** rpm is allowed.

## Baseline (do not re-implement)

| Component | Path |
|-----------|------|
| Evidence IDs + digests | `scripts/release_schema.py` |
| Candidate identity + guard | `scripts/rc_manifest.py` |
| Record validate + index | `scripts/release_evidence.py` |
| Final technical gate | `scripts/verify_release_evidence.py` |
| Artifact dual-build | `scripts/build_release_artifacts.sh` |
| Repro comparison | `scripts/compare_reproducible_builds.py` |
| Benchmark report | `scripts/benchmark_report.py` |
| Publisher (dry-run only this plan) | `scripts/publish_github_release.py` |
| Evidence template | `scripts/release-evidence-template.json` |
| Step narrative SoT | `docs/release-1.0-verification.md` |

Baseline check:

```bash
cd /mnt/nvme1n1p2/moonsight
export CC=gcc
python3 -m unittest discover -s scripts -p 'test_*.py'
```

Expected: `OK` (all tests).

---

## File Structure (this plan)

| Path | Responsibility |
|------|----------------|
| External `EVIDENCE_ROOT/**` | Candidate copy, artifacts, records, raw, index, gate, handoff (not in candidate commit) |
| Modify `docs/release-1.0-verification.md` | Fill candidate SHA + Fedora progress; Overall stays **BLOCKED** |
| Modify `CHANGELOG.md` | Honest “tooling + partial evidence; not released” only if needed |
| Modify `README.md` / `README.en.md` / `README.mbt.md` | Optional progress pointer; matrix still BLOCKED |
| Create `EVIDENCE_ROOT/HANDOFF-ubuntu-arch.md` | Ops continuation for 7 remaining IDs |
| Create `.superpowers/sdd/formal-1.0-fedora-partial-closure-report.md` | Agent/operator completion report (repo-local, not candidate identity) |

No new Python modules required if existing CLIs suffice.

---

## Behavior Coverage

| Scenario | Task |
|----------|------|
| Clean tree + automated matrix green | T1 |
| Four packages + dual-build repro | T2 |
| Benchmark report retained | T2 |
| Immutable candidate + RC manifest + guard | T3 |
| Fedora W1 ×2 + negative msb fixtures | T4 |
| Fedora D1 AppImage + rpm | T5 |
| C1-web + C1-desktop on Fedora | T6 |
| 7× NOT_RUN stubs validate | T7 |
| Index + negative Final Gate | T7 |
| Docs honesty + handoff + stop line | T8–T9 |

---

### Task 1: Prep — Clean Tree and Automated Matrix

**Files:**
- Read only (unless product defect found): entire repo
- Create (external): `$EVIDENCE_ROOT/logs/prep-*.log` after short SHA known; for prep use `/tmp/moonsight-prep-$$/`

- [ ] **Step 1: Confirm branch, cleanliness, and no 1.1 contamination**

```bash
cd /mnt/nvme1n1p2/moonsight
git status --short --branch
git rev-parse HEAD
git rev-parse --abbrev-ref HEAD
# Ensure you are NOT inside .worktrees/native-1.1
pwd
```

Expected:
- Branch `main` (or explicitly chosen freeze branch)  
- `git status` shows clean working tree (no tracked modifications)  
- `HEAD` is the intended freeze tip  

If dirty: stash/commit elsewhere or discard only with operator consent—**do not freeze dirty**.

- [ ] **Step 2: Export build env and record toolchains**

```bash
export CC=gcc
export NO_STRIP="${NO_STRIP:-true}"
export APPIMAGE_EXTRACT_AND_RUN="${APPIMAGE_EXTRACT_AND_RUN:-1}"
# Raise FD limit for linuxdeploy (AppImage)
ulimit -n 65536 2>/dev/null || ulimit -n 8192 2>/dev/null || true

moon version 2>&1 | tee /tmp/moonsight-toolchain.txt
node -v | tee -a /tmp/moonsight-toolchain.txt
rustc -V | tee -a /tmp/moonsight-toolchain.txt
# tauri CLI if installed via cargo/npm — record exact version string used later in metadata.toolchains.tauri_cli
(command -v cargo-tauri >/dev/null && cargo tauri -V) 2>&1 | tee -a /tmp/moonsight-toolchain.txt || true
(cd host_desktop/tauri && npx tauri -V) 2>&1 | tee -a /tmp/moonsight-toolchain.txt || true
```

- [ ] **Step 3: Run automated matrix**

```bash
cd /mnt/nvme1n1p2/moonsight
export CC=gcc

moon fmt --check
moon check --target all
moon test
moon build --target wasm-gc --release host_web

cd apps/host-web && npm ci && npm test && npx tsc --noEmit && npm run build && cd ../..

moon run cmd/moonsightc --target native -- check demo/game
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
./scripts/verify-package.sh dist/demo

python3 -m unittest discover -s scripts -p 'test_*.py'

cd host_desktop/tauri && npm ci \
  && cargo fmt --check --manifest-path src-tauri/Cargo.toml \
  && cargo check --manifest-path src-tauri/Cargo.toml \
  && cargo test --manifest-path src-tauri/Cargo.toml \
  && cd ../..
```

Expected: every command exit 0.

If any fail with a **product/packaging code** defect: fix on a normal commit, re-run Task 1 from Step 1 (new potential candidate SHA).  
If fail for **missing host packages only**: fix environment; do not claim product PASS.

- [ ] **Step 4: Record prep outcome (no git commit required if no code change)**

```bash
CANDIDATE_SHA="$(git rev-parse HEAD)"
echo "prep_candidate_sha=$CANDIDATE_SHA"
echo "prep_status=PASS"
```

If code was fixed: commit with a normal message (e.g. `fix: …`) before proceeding; the freeze SHA is the post-fix HEAD.

---

### Task 2: Art — Dual Artifact Build, Repro, Benchmark

**Files:**
- Create (external): `$RELEASE_OUT/first/*`, `$RELEASE_OUT/second/*`, repro + benchmark reports
- Read: `scripts/build_release_artifacts.sh`, `scripts/compare_reproducible_builds.py`, `scripts/benchmark_report.py`, `scripts/reproducibility-normalization-v1.json`

- [ ] **Step 1: Create external dirs (still clean tree)**

```bash
cd /mnt/nvme1n1p2/moonsight
test -z "$(git status --porcelain)" || { echo "dirty tree"; exit 1; }
CANDIDATE_SHA="$(git rev-parse HEAD)"
SHORT="${CANDIDATE_SHA:0:12}"
export EVIDENCE_ROOT="${HOME}/moonsight-evidence/formal-1.0/${SHORT}"
export RELEASE_OUT="${EVIDENCE_ROOT}/release-out"
mkdir -p "$EVIDENCE_ROOT"/{logs,records,raw,artifacts}
mkdir -p "$RELEASE_OUT"
echo "$CANDIDATE_SHA" > "$EVIDENCE_ROOT/CANDIDATE_SHA.txt"
```

- [ ] **Step 2: Build dual artifact sets**

```bash
cd /mnt/nvme1n1p2/moonsight
export CC=gcc NO_STRIP=true APPIMAGE_EXTRACT_AND_RUN=1
ulimit -n 65536 2>/dev/null || true

./scripts/build_release_artifacts.sh --version v1.0.0 --out "$RELEASE_OUT" \
  2>&1 | tee "$EVIDENCE_ROOT/logs/build-release-artifacts.log"
```

Expected stdout ends with:
```text
OK: release candidate artifacts: .../first
OK: reproducibility comparison artifacts: .../second
```

Expected files under `$RELEASE_OUT/first/`:
```text
moonsight-web-x86_64-v1.0.0.zip
moonsight-linux-x86_64-v1.0.0.AppImage
moonsight-linux-x86_64-v1.0.0.deb
moonsight-linux-x86_64-v1.0.0.rpm
SHA256SUMS
build-metadata.json
```

If AppImage/`linuxdeploy` fails: **stop**. Fix packaging/env (do not drop AppImage from the matrix). Re-run from clean tree after fix commits.

- [ ] **Step 3: Reproducibility comparison**

```bash
python3 scripts/compare_reproducible_builds.py \
  "$RELEASE_OUT/first" "$RELEASE_OUT/second" \
  --allowlist scripts/reproducibility-normalization-v1.json \
  --output "$EVIDENCE_ROOT/repro-report.json" \
  2>&1 | tee "$EVIDENCE_ROOT/logs/repro.log"

python3 - <<'PY'
import json, os
p=os.environ["EVIDENCE_ROOT"]+"/repro-report.json"
r=json.load(open(p))
print("outcome=", r.get("outcome"))
assert r.get("outcome")=="PASS", r
print("artifacts=", len(r.get("artifacts") or []))
PY
```

Expected: exit 0; `outcome=PASS`; non-empty `artifacts` with `left_size_bytes` + `left_raw_sha256` for the four packages (and any compared paths the tool inventories).

- [ ] **Step 4: Produce benchmark report**

Formal RC generate requires a benchmark report object with at least `outcome` and `input_sha256`. Prefer a **real** report via `scripts/benchmark_report.py` from retained samples (see `docs/formal-1.0-rc-tooling.md` for sample shape: 5 warm×1000, 5 cold×100, memory + frame gates).

If real samples are available at `$EVIDENCE_ROOT/raw/benchmark-samples.json`:

```bash
python3 scripts/benchmark_report.py \
  "$EVIDENCE_ROOT/raw/benchmark-samples.json" \
  --output "$EVIDENCE_ROOT/benchmark-report.json"
python3 -c 'import json; r=json.load(open("'"$EVIDENCE_ROOT"'/benchmark-report.json")); print(r["outcome"]); assert r["outcome"]=="PASS"'
```

If real samples **cannot** be collected this session: **stop Freeze** (do not invent passing timings). Document `BLOCKED` in `$EVIDENCE_ROOT/logs/benchmark-blocked.txt` and escalate to operator. Do not proceed to Task 3 DoD.

Optional interim (only for tooling dry-run **outside** this plan’s DoD): unit-test style stub is **not** allowed for the real freeze.

- [ ] **Step 5: Stage first artifacts into evidence tree**

```bash
cp -a "$RELEASE_OUT/first/." "$EVIDENCE_ROOT/artifacts/"
sha256sum "$EVIDENCE_ROOT/artifacts"/moonsight-* | tee "$EVIDENCE_ROOT/logs/artifact-digests.txt"
```

---

### Task 3: Freeze — Candidate Identity + RC Manifest + Guard Discipline

**Files:**
- Create: `$EVIDENCE_ROOT/rc-metadata.json`, `$EVIDENCE_ROOT/candidate.json` (RC manifest output; treat as candidate identity)
- Note: `rc_manifest.py generate --output` writes the schema_v2 candidate identity file used by evidence tools

- [ ] **Step 1: Capture live validation target versions on Fedora**

```bash
# Operator fills exact versions that will appear in records
FEDORA_VER="$(. /etc/os-release && echo "$VERSION_ID")"   # e.g. 42 — must match candidate.system.fedora EXACTLY
# If you prefer "Fedora Linux 42", use that string consistently in BOTH metadata.system.fedora AND every Fedora record os_version.
CHROMIUM_VER="$(chromium --version 2>/dev/null || chromium-browser --version 2>/dev/null | head -1)"
FIREFOX_VER="$(firefox --version 2>/dev/null | head -1)"
# WebKitGTK / Tauri webview version — from package or about dialog; must be stable string:
# e.g. rpm -q webkit2gtk4.1 --qf '%{VERSION}\n'  OR document Tauri webview version used in testing
echo "FEDORA_VER=$FEDORA_VER"
echo "CHROMIUM_VER=$CHROMIUM_VER"
echo "FIREFOX_VER=$FIREFOX_VER"
```

Pick **one** Fedora version string (recommended: numeric `VERSION_ID` like `42`) and use it everywhere.

- [ ] **Step 2: Write `rc-metadata.json`**

Create `$EVIDENCE_ROOT/rc-metadata.json` with real values (replace placeholders):

```json
{
  "attempt_id": "rc-YYYYMMDDTHHMMSSZ-<short12>",
  "clean_tree": true,
  "built_at_utc": "YYYY-MM-DDTHH:MM:SSZ",
  "build_host": "<hostname>",
  "toolchains": {
    "moon": "<from moon version>",
    "node": "<from node -v>",
    "rustc": "<from rustc -V>",
    "tauri_cli": "<from tauri -V>"
  },
  "system": {
    "build_os": "<build host OS string>",
    "kernel": "<uname -r>",
    "fedora": "42",
    "arch": "2026.07.01"
  },
  "validation_targets": {
    "chromium": "138.0.7204.92",
    "firefox": "140.0.4",
    "webkitgtk": "2.48.3"
  }
}
```

Rules:
- `clean_tree` must be JSON `true`.
- `system.fedora` / `system.arch` / browser strings will be **copied into** candidate and must match every later evidence record.
- `system.arch` is required even though Arch evidence is NOT_RUN this round—use the intended Arch rolling date label operators will use later.

- [ ] **Step 3: Generate immutable RC / candidate identity**

```bash
cd /mnt/nvme1n1p2/moonsight
CANDIDATE_SHA="$(cat "$EVIDENCE_ROOT/CANDIDATE_SHA.txt")"
test "$(git rev-parse HEAD)" = "$CANDIDATE_SHA"
test -z "$(git status --porcelain)"

python3 scripts/rc_manifest.py generate \
  --candidate "$CANDIDATE_SHA" \
  --benchmark "$EVIDENCE_ROOT/benchmark-report.json" \
  --reproducibility "$EVIDENCE_ROOT/repro-report.json" \
  --metadata "$EVIDENCE_ROOT/rc-metadata.json" \
  --output "$EVIDENCE_ROOT/candidate.json"

# generate exits 0 only if automated_checks combined outcome is PASS
echo "rc_manifest_exit=$?"
python3 - <<'PY'
import json, os
c=json.load(open(os.environ["EVIDENCE_ROOT"]+"/candidate.json"))
assert c["schema_version"]==2
assert c["candidate"]["clean_tree"] is True
assert "external_checks" not in c
assert "release_authorized" not in c
print("commit", c["candidate"]["commit"])
print("artifacts", [a["path"] for a in c["candidate"]["artifacts"]])
print("fedora", c["system"]["fedora"])
print("validation_targets", c["validation_targets"])
PY
```

Expected: file created mode read-only; exit 0; four package digests present.

If file already exists: **do not overwrite**—use a new attempt directory or new SHA.

- [ ] **Step 4: Guard discipline (run before every evidence session)**

```bash
python3 scripts/rc_manifest.py guard \
  --candidate "$(cat "$EVIDENCE_ROOT/CANDIDATE_SHA.txt")" \
  --repo .
```

Expected: exit 0. On failure: stop collecting evidence; if tree changed for product fix, start a **new** candidate (Tasks 1–3 again).

---

### Task 4: Fedora W1 Evidence (Operator GUI + Agent Validate)

**Files:**
- Create: `$EVIDENCE_ROOT/records/W1-fedora-chromium.json`, `W1-fedora-firefox.json`
- Create: `$EVIDENCE_ROOT/raw/w1-*/**` logs/screenshots
- Create: negative web packages under `$EVIDENCE_ROOT/raw/negative-msb/`

**Operator steps (authoritative narrative):** `docs/release-1.0-verification.md` § W1.

- [ ] **Step 1: Guard + unpack Web ZIP**

```bash
cd /mnt/nvme1n1p2/moonsight
python3 scripts/rc_manifest.py guard --candidate "$(cat "$EVIDENCE_ROOT/CANDIDATE_SHA.txt")" --repo .
WEB_ZIP="$EVIDENCE_ROOT/artifacts/moonsight-web-x86_64-v1.0.0.zip"
WEB_SHA="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$WEB_ZIP")"
mkdir -p "$EVIDENCE_ROOT/raw/web-serve"
rm -rf "$EVIDENCE_ROOT/raw/web-serve/dist"
mkdir -p "$EVIDENCE_ROOT/raw/web-serve/dist"
python3 - <<'PY'
import zipfile, os
from pathlib import Path
z=Path(os.environ["EVIDENCE_ROOT"])/"artifacts/moonsight-web-x86_64-v1.0.0.zip"
dest=Path(os.environ["EVIDENCE_ROOT"])/"raw/web-serve/dist"
with zipfile.ZipFile(z) as zf: zf.extractall(dest)
print("extracted", dest)
PY
cd "$EVIDENCE_ROOT/raw/web-serve/dist" && python3 -m http.server 8765
# leave server running in another terminal
```

- [ ] **Step 2: Operator executes W1 on Chromium (Fedora)**

Manual checklist (must all pass):
1. Open `http://localhost:8765/` in **Chromium stable**; confirm WebGPU adapter present (`chrome://gpu` not disabled).
2. Title → Start → advance without error panel.
3. Save slot → reload page → load slot; state resumes.
4. Switch `en` ↔ `zh-Hans-CN` atomically; no text fallback.
5. Exercise rollback / compensatable BGM / barrier; blocked rollback shows `rollback.unavailable.*` with zero mutation.
6. Build three negative packages (missing / empty / corrupt `game.msb`); each shows production boot error and does not enter demo.

Retain under `$EVIDENCE_ROOT/raw/w1-fedora-chromium/`: console log, screenshots, redacted localStorage notes, three negative derived SHA-256s.

- [ ] **Step 3: Write PASS record for `W1-fedora-chromium`**

Agent assists filling JSON; operator confirms truthfulness. Use exact digests from candidate:

```bash
python3 - <<'PY'
import json, hashlib, os
from pathlib import Path
from datetime import datetime, timezone

root = Path(os.environ["EVIDENCE_ROOT"])
cand = json.loads((root/"candidate.json").read_text())
commit = cand["candidate"]["commit"]
arts = {a["path"]: a["sha256"] for a in cand["candidate"]["artifacts"]}
web = "moonsight-web-x86_64-v1.0.0.zip"
# Operator replaces NEG_* digests with real derived package hashes
NEG_MISSING = "REPLACE_WITH_64_HEX"
NEG_EMPTY = "REPLACE_WITH_64_HEX"
NEG_CORRUPT = "REPLACE_WITH_64_HEX"
# Optional: hash public zip of redacted attachments
public_blob = b"public-evidence-placeholder"
raw_blob = b"raw-evidence-placeholder"
record = {
  "schema_version": 1,
  "id": "W1-fedora-chromium",
  "status": "PASS",
  "candidate_commit": commit,
  "artifact": {"path": web, "sha256": arts[web]},
  "environment": {
    "os": "Fedora",
    "os_version": cand["system"]["fedora"],
    "kernel": "REPLACE_uname_r",
    "desktop_environment": "REPLACE",
    "browser_or_webview": "Chromium",
    "browser_or_webview_version": cand["validation_targets"]["chromium"],
    "gpu": "REPLACE",
    "driver": "REPLACE",
  },
  "tester": "REPLACE_OPERATOR_ID",
  "timestamp_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "executed_steps": [
    {"order": 1, "action": "Serve Web ZIP; open Chromium with WebGPU", "expected": "Title loads; no error panel", "actual": "REPLACE", "result": "PASS"},
    {"order": 2, "action": "Start and advance narrative", "expected": "Advance works", "actual": "REPLACE", "result": "PASS"},
    {"order": 3, "action": "Save slot; reload; load slot", "expected": "State restored", "actual": "REPLACE", "result": "PASS"},
    {"order": 4, "action": "Atomic locale switch en/zh-Hans-CN", "expected": "No fallback; catalogs complete", "actual": "REPLACE", "result": "PASS"},
    {"order": 5, "action": "Rollback / BGM compensatable / barrier", "expected": "Blocked path zero mutation", "actual": "REPLACE", "result": "PASS"},
    {"order": 6, "action": "missing/empty/corrupt game.msb packages", "expected": "Boot error; no demo", "actual": "REPLACE", "result": "PASS"},
  ],
  "attachments": {
    "logs": ["public/logs/w1-fedora-chromium.txt"],
    "screenshots": ["public/screenshots/w1-fedora-chromium.png"],
    "video": []
  },
  "redacted_inspection": {
    "save": "Redacted save summary",
    "localStorage": "Redacted localStorage key list"
  },
  "public_evidence_sha256": hashlib.sha256(public_blob).hexdigest(),
  "raw_evidence_sha256": hashlib.sha256(raw_blob).hexdigest(),
  "redaction_statement": (
    "Public evidence excludes secrets, personal data, machine identifiers, "
    "and unredacted save contents."
  ),
  "negative_fixtures": [
    {"source_artifact": {"path": web, "sha256": arts[web]}, "transformation": "missing-msb", "derived_artifact_sha256": NEG_MISSING},
    {"source_artifact": {"path": web, "sha256": arts[web]}, "transformation": "empty-msb", "derived_artifact_sha256": NEG_EMPTY},
    {"source_artifact": {"path": web, "sha256": arts[web]}, "transformation": "corrupt-msb", "derived_artifact_sha256": NEG_CORRUPT},
  ],
}
out = root/"records"/"W1-fedora-chromium.json"
out.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
print("wrote", out)
PY
```

- [ ] **Step 4: Validate the Chromium record**

```bash
cd /mnt/nvme1n1p2/moonsight
python3 scripts/release_evidence.py validate-record \
  --candidate "$EVIDENCE_ROOT/candidate.json" \
  --record "$EVIDENCE_ROOT/records/W1-fedora-chromium.json"
```

Expected: exit 0, no validation errors. Fix fields until clean—**do not** mark PASS if operator did not complete steps.

- [ ] **Step 5: Repeat Steps 2–4 for Firefox → `W1-fedora-firefox.json`**

Same Web ZIP digest; environment:
- `browser_or_webview`: `Firefox`
- `browser_or_webview_version`: `cand["validation_targets"]["firefox"]`
- New negative fixture digests if rebuilt (or reuse if identical bytes)

Validate:

```bash
python3 scripts/release_evidence.py validate-record \
  --candidate "$EVIDENCE_ROOT/candidate.json" \
  --record "$EVIDENCE_ROOT/records/W1-fedora-firefox.json"
```

Expected: exit 0.

---

### Task 5: Fedora D1 Evidence (AppImage + rpm)

**Files:**
- Create: `$EVIDENCE_ROOT/records/D1-fedora-appimage.json`, `D1-fedora-rpm.json`
- Raw: `$EVIDENCE_ROOT/raw/d1-*/**`

**Operator narrative:** `docs/release-1.0-verification.md` § D1.

- [ ] **Step 1: Guard**

```bash
cd /mnt/nvme1n1p2/moonsight
python3 scripts/rc_manifest.py guard --candidate "$(cat "$EVIDENCE_ROOT/CANDIDATE_SHA.txt")" --repo .
```

- [ ] **Step 2: Operator — AppImage persistence**

1. Launch `$EVIDENCE_ROOT/artifacts/moonsight-linux-x86_64-v1.0.0.AppImage` (or install path).
2. Play to known point; save slot 0; change a preference.
3. Fully exit; confirm no process remains.
4. Inspect appData: `prefs.json`, `saves/0.json` (paths per `host_desktop/README.md` / DesktopSaveStore).
5. Relaunch; load slot 0; confirm progress + prefs.

Retain redacted appData listing + digests under `$EVIDENCE_ROOT/raw/d1-fedora-appimage/`.

- [ ] **Step 3: Write + validate `D1-fedora-appimage.json`**

Record requirements:
- `id`: `D1-fedora-appimage`
- `artifact.path`: `moonsight-linux-x86_64-v1.0.0.AppImage`
- `artifact.sha256`: from candidate
- `environment.os`: `Fedora`
- `environment.os_version`: `candidate.system.fedora`
- `environment.browser_or_webview`: `WebKitGTK`
- `environment.browser_or_webview_version`: `candidate.validation_targets.webkitgtk`
- `status`: `PASS` only if all D1 steps passed
- `executed_steps`: consecutive `order` 1..N, each `result: PASS`
- No `negative_fixtures` required for D1

```bash
python3 scripts/release_evidence.py validate-record \
  --candidate "$EVIDENCE_ROOT/candidate.json" \
  --record "$EVIDENCE_ROOT/records/D1-fedora-appimage.json"
```

Expected: exit 0.

- [ ] **Step 4: Operator — rpm package**

Install/run `$EVIDENCE_ROOT/artifacts/moonsight-linux-x86_64-v1.0.0.rpm` on Fedora; repeat D1 persistence steps (clean appData or distinct module path if needed so tests are independent).

- [ ] **Step 5: Write + validate `D1-fedora-rpm.json`**

Same as Step 3 with:
- `id`: `D1-fedora-rpm`
- `artifact.path`: `moonsight-linux-x86_64-v1.0.0.rpm`

```bash
python3 scripts/release_evidence.py validate-record \
  --candidate "$EVIDENCE_ROOT/candidate.json" \
  --record "$EVIDENCE_ROOT/records/D1-fedora-rpm.json"
```

Expected: exit 0.

---

### Task 6: C1 Evidence (Web + Desktop on Fedora)

**Files:**
- Create: `$EVIDENCE_ROOT/records/C1-web.json`, `C1-desktop.json`

**Operator narrative:** `docs/release-1.0-verification.md` § C1.

- [ ] **Step 1: Guard**

```bash
python3 scripts/rc_manifest.py guard --candidate "$(cat "$EVIDENCE_ROOT/CANDIDATE_SHA.txt")" --repo .
```

- [ ] **Step 2: Operator — `C1-web` complete demo**

Fresh playthrough of packaged demo from title through representative arc: choices, menu save/load, quick save/load, prefs, backlog, locale switch, rollback/barrier, return-to-title. No debug shortcuts.

Environment example (allowed):
- `os`: `Fedora`
- `os_version`: candidate fedora string
- `browser_or_webview`: `Chromium` (or `Firefox`)
- matching validation_targets version
- artifact: Web ZIP

- [ ] **Step 3: Write + validate `C1-web.json`**

```bash
python3 scripts/release_evidence.py validate-record \
  --candidate "$EVIDENCE_ROOT/candidate.json" \
  --record "$EVIDENCE_ROOT/records/C1-web.json"
```

Expected: exit 0.

- [ ] **Step 4: Operator — `C1-desktop` complete demo**

Same arc on AppImage (or rpm). Schema requires:
- `browser_or_webview`: `WebKitGTK`
- package kind `appimage` or `rpm` for Fedora
- artifact path/digest match

- [ ] **Step 5: Write + validate `C1-desktop.json`**

```bash
python3 scripts/release_evidence.py validate-record \
  --candidate "$EVIDENCE_ROOT/candidate.json" \
  --record "$EVIDENCE_ROOT/records/C1-desktop.json"
```

Expected: exit 0.

---

### Task 7: NOT_RUN Stubs, Index, Negative Final Gate

**Files:**
- Create: seven NOT_RUN records under `$EVIDENCE_ROOT/records/`
- Create: `$EVIDENCE_ROOT/evidence-index.json`, `$EVIDENCE_ROOT/final-gate.json`

- [ ] **Step 1: Generate seven honest NOT_RUN stubs that still validate**

Each stub needs full schema fields and **matching** target combo for its ID (Ubuntu 24.04 / Arch version from candidate / correct artifact). Steps may be a single `NOT_RUN` step. `status` must be `NOT_RUN`. W1 stubs should **omit** `negative_fixtures` (only required when `status==PASS` or fixtures present).

```bash
python3 - <<'PY'
import json, hashlib, os
from pathlib import Path
from datetime import datetime, timezone

root = Path(os.environ["EVIDENCE_ROOT"])
cand = json.loads((root/"candidate.json").read_text())
commit = cand["candidate"]["commit"]
arts = {a["path"]: a["sha256"] for a in cand["candidate"]["artifacts"]}
WEB = "moonsight-web-x86_64-v1.0.0.zip"
APP = "moonsight-linux-x86_64-v1.0.0.AppImage"
DEB = "moonsight-linux-x86_64-v1.0.0.deb"
vt = cand["validation_targets"]
sysv = cand["system"]
public = hashlib.sha256(b"not-run-public").hexdigest()
raw = hashlib.sha256(b"not-run-raw").hexdigest()
ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def stub(eid, os_name, os_version, browser, browser_ver, artifact):
    return {
      "schema_version": 1,
      "id": eid,
      "status": "NOT_RUN",
      "candidate_commit": commit,
      "artifact": {"path": artifact, "sha256": arts[artifact]},
      "environment": {
        "os": os_name,
        "os_version": os_version,
        "kernel": "not-run",
        "desktop_environment": "not-run",
        "browser_or_webview": browser,
        "browser_or_webview_version": browser_ver,
        "gpu": "not-run",
        "driver": "not-run",
      },
      "tester": "not-assigned",
      "timestamp_utc": ts,
      "executed_steps": [
        {
          "order": 1,
          "action": "Deferred to Ubuntu/Arch handoff",
          "expected": "Full W1/D1 steps on target OS",
          "actual": "Not executed this candidate round",
          "result": "NOT_RUN",
        }
      ],
      "attachments": {"logs": [], "screenshots": [], "video": []},
      "redacted_inspection": {"save": "N/A", "localStorage": "N/A"},
      "public_evidence_sha256": public,
      "raw_evidence_sha256": raw,
      "redaction_statement": (
        "Public evidence excludes secrets, personal data, machine identifiers, "
        "and unredacted save contents."
      ),
    }

stubs = [
  ("W1-ubuntu-chromium", "Ubuntu", "24.04", "Chromium", vt["chromium"], WEB),
  ("W1-ubuntu-firefox", "Ubuntu", "24.04", "Firefox", vt["firefox"], WEB),
  ("D1-ubuntu-appimage", "Ubuntu", "24.04", "WebKitGTK", vt["webkitgtk"], APP),
  ("D1-ubuntu-deb", "Ubuntu", "24.04", "WebKitGTK", vt["webkitgtk"], DEB),
  ("W1-arch-chromium", "Arch Linux", sysv["arch"], "Chromium", vt["chromium"], WEB),
  ("W1-arch-firefox", "Arch Linux", sysv["arch"], "Firefox", vt["firefox"], WEB),
  ("D1-arch-appimage", "Arch Linux", sysv["arch"], "WebKitGTK", vt["webkitgtk"], APP),
]
for eid, os_name, os_ver, browser, bver, art in stubs:
    path = root/"records"/f"{eid}.json"
    path.write_text(json.dumps(stub(eid, os_name, os_ver, browser, bver, art), indent=2)+"\n")
    print("wrote", path)
PY
```

- [ ] **Step 2: Validate every record (13 files)**

```bash
cd /mnt/nvme1n1p2/moonsight
for f in "$EVIDENCE_ROOT"/records/*.json; do
  echo "=== $f ==="
  python3 scripts/release_evidence.py validate-record \
    --candidate "$EVIDENCE_ROOT/candidate.json" \
    --record "$f" || exit 1
done
ls "$EVIDENCE_ROOT/records" | wc -l   # expect 13
```

Expected: 13 files; all validate exit 0.

- [ ] **Step 3: Build evidence index**

```bash
python3 scripts/release_evidence.py build-index \
  --candidate "$EVIDENCE_ROOT/candidate.json" \
  --records "$EVIDENCE_ROOT/records" \
  --output "$EVIDENCE_ROOT/evidence-index.json"

python3 - <<'PY'
import json, os
idx=json.load(open(os.environ["EVIDENCE_ROOT"]+"/evidence-index.json"))
print("aggregate_status", idx.get("aggregate_status"))
# Expect NOT_RUN or non-PASS because 7 IDs are NOT_RUN
assert idx.get("aggregate_status") != "PASS"
print("ok non-PASS aggregate")
PY
```

Expected: index written; aggregate ≠ `PASS`.

- [ ] **Step 4: Final Gate (expect technical not ready)**

```bash
python3 scripts/verify_release_evidence.py \
  --repo . \
  --candidate "$EVIDENCE_ROOT/candidate.json" \
  --index "$EVIDENCE_ROOT/evidence-index.json" \
  --output "$EVIDENCE_ROOT/final-gate.json"; echo "gate_exit=$?"

python3 - <<'PY'
import json, os
g=json.load(open(os.environ["EVIDENCE_ROOT"]+"/final-gate.json"))
print(g)
assert g.get("technical_release_ready") is False
print("SUCCESS: technical_release_ready is false as required")
PY
```

Expected:
- Tool exits non-zero **or** writes gate with `technical_release_ready=false` (both acceptable if file exists and assertion holds).
- **This negative result is plan success**, not failure.

- [ ] **Step 5: Optional publisher dry-run only (must not execute)**

```bash
# Only if release notes file exists; otherwise skip
# Must NOT pass --execute
python3 scripts/publish_github_release.py \
  --repo . \
  --candidate "$EVIDENCE_ROOT/candidate.json" \
  --index "$EVIDENCE_ROOT/evidence-index.json" \
  --gate "$EVIDENCE_ROOT/final-gate.json" \
  --artifacts "$EVIDENCE_ROOT/artifacts" \
  --notes /dev/null 2>&1 | head -50 || true

# Hard ban:
# python3 scripts/publish_github_release.py ... --execute --authorize v1.0.0
test ! -e .git/refs/tags/v1.0.0
git tag -l 'v1.0.0'
```

Expected: no `v1.0.0` tag created.

---

### Task 8: Handoff Document + Honest In-Repo Docs

**Files:**
- Create: `$EVIDENCE_ROOT/HANDOFF-ubuntu-arch.md`
- Create: `.superpowers/sdd/formal-1.0-fedora-partial-closure-report.md`
- Modify: `docs/release-1.0-verification.md` (candidate fields + Fedora results; Overall **BLOCKED**)
- Modify (optional honesty only): `CHANGELOG.md`, `README.md`, `README.en.md`, `README.mbt.md`

- [ ] **Step 1: Write HANDOFF**

Create `$EVIDENCE_ROOT/HANDOFF-ubuntu-arch.md` containing at least:

```markdown
# Handoff: remaining Formal 1.0 evidence (Ubuntu + Arch)

## Candidate
- Full SHA: <40 hex>
- Evidence root: <EVIDENCE_ROOT>
- Artifacts: see artifacts/ + SHA256SUMS
- candidate.json / final-gate.json prove technical_release_ready=false

## Already PASS (do not re-use on a new SHA)
- W1-fedora-chromium
- W1-fedora-firefox
- D1-fedora-appimage
- D1-fedora-rpm
- C1-web
- C1-desktop

## Remaining NOT_RUN (7)
1. W1-ubuntu-chromium / W1-ubuntu-firefox — Ubuntu 24.04, Web ZIP, steps in docs/release-1.0-verification.md §W1
2. D1-ubuntu-appimage / D1-ubuntu-deb — Ubuntu, AppImage+deb, §D1
3. W1-arch-chromium / W1-arch-firefox — Arch current, §W1
4. D1-arch-appimage — Arch, §D1

## Guard before each session
```bash
python3 scripts/rc_manifest.py guard --candidate <FULL_SHA> --repo .
```

If the tree changes for a product fix: **new candidate**, rebuild artifacts, **invalidate all** prior evidence including Fedora PASS.

## Publication ban
Do not create tag v1.0.0 or run publish_github_release.py --execute until all 13 IDs are PASS and Final Gate technical_release_ready=true **and** operator secondary confirmation.
```

- [ ] **Step 2: Update `docs/release-1.0-verification.md` honestly**

Fill:
- Candidate commit = frozen SHA  
- Fedora W1/D1/C1 rows with PASS + paths to external evidence (not fake CI URLs)  
- Ubuntu/Arch remain NOT RUN  
- Overall result remains **BLOCKED**  
- Do **not** invent package SHA fields if not retained—copy from `SHA256SUMS`

- [ ] **Step 3: Write SDD completion report**

Create `.superpowers/sdd/formal-1.0-fedora-partial-closure-report.md`:

```markdown
# Formal 1.0 Fedora Partial Closure Report

- Date (UTC):
- Candidate SHA:
- Evidence root:
- Prep matrix: PASS|FAIL
- Artifacts + repro: PASS|FAIL
- Benchmark: PASS|FAIL
- Fedora 6 evidence: PASS|FAIL (list IDs)
- Index aggregate:
- technical_release_ready: false (required)
- Tag v1.0.0 present: no (required)
- Publisher execute: not run (required)
```

- [ ] **Step 4: Commit only in-repo documentation (never evidence blobs)**

```bash
cd /mnt/nvme1n1p2/moonsight
git status --short
# Stage only docs / report under repo:
git add docs/release-1.0-verification.md \
  .superpowers/sdd/formal-1.0-fedora-partial-closure-report.md
# plus README/CHANGELOG only if modified honestly
git commit -m "$(cat <<'EOF'
docs: record Formal 1.0 Fedora partial evidence progress

Document the frozen candidate and Fedora PASS subset while keeping the
overall Formal 1.0 release BLOCKED until Ubuntu/Arch evidence completes.
EOF
)"
```

**Important:** This docs commit is **not** the freeze candidate. If you already froze SHA `S0`, either:
- keep verification docs on a **follow-up** commit and note in handoff that evidence binds to `S0`, or  
- freeze only after docs are ready if you want verification file inside the candidate tree.

**Preferred for this plan:** freeze SHA is pure tooling+product tip; verification progress lives on a follow-up commit and/or external handoff. State both SHAs in the SDD report.

---

### Task 9: Stop Line — Explicit Non-Release Checklist

**Files:** none required

- [ ] **Step 1: Run stop-line assertions**

```bash
cd /mnt/nvme1n1p2/moonsight

# 1) Six PASS files exist
for id in W1-fedora-chromium W1-fedora-firefox D1-fedora-appimage D1-fedora-rpm C1-web C1-desktop; do
  python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); assert r["status"]=="PASS", r["status"]' \
    "$EVIDENCE_ROOT/records/${id}.json"
done

# 2) Seven NOT_RUN
for id in W1-ubuntu-chromium W1-ubuntu-firefox D1-ubuntu-appimage D1-ubuntu-deb \
          W1-arch-chromium W1-arch-firefox D1-arch-appimage; do
  python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); assert r["status"]=="NOT_RUN", r["status"]' \
    "$EVIDENCE_ROOT/records/${id}.json"
done

# 3) Gate not ready
python3 -c 'import json,os; g=json.load(open(os.environ["EVIDENCE_ROOT"]+"/final-gate.json")); assert g.get("technical_release_ready") is False'

# 4) No tag
test -z "$(git tag -l 'v1.0.0')"

# 5) Handoff exists
test -f "$EVIDENCE_ROOT/HANDOFF-ubuntu-arch.md"

echo "STOP LINE OK — partial closure complete; do not publish"
```

Expected: all asserts pass; message printed.

- [ ] **Step 2: Operator verbal confirmation**

Operator confirms aloud/in session notes:
1. No `v1.0.0` tag pushed.  
2. No GitHub Release execute.  
3. Ubuntu/Arch still required for Formal 1.0.  
4. Evidence root path retained.

---

## Plan Self-Review

| Spec requirement | Task |
|------------------|------|
| Clean freeze SHA + guard | T1, T3 |
| Four artifacts + SUMS | T2 |
| Repro allowlist PASS | T2 |
| Automated matrix | T1 |
| Benchmark retained PASS | T2 |
| Six Fedora/C1 PASS | T4–T6 |
| Seven NOT_RUN | T7 |
| Index + technical_release_ready=false | T7 |
| Handoff Ubuntu/Arch | T8 |
| Docs Overall BLOCKED | T8 |
| No tag / no execute | T7, T9 |
| No 1.1 / no matrix shrink | Global constraints |
| Candidate invalidation on product fix | T3, Handoff |

Placeholder scan: no TBD/TODO left as work instructions; operators replace only marked `REPLACE_*` fields with measured values.

Type/field consistency: record schema v1; candidate schema v2; artifact filenames identical across build, candidate, records.

---

## Execution Notes for Agents

1. **GUI steps (T4–T6) cannot be fake-greened** in headless CI. If WebGPU/`requestAdapter` is null, record `BLOCKED`/`FAIL` and stop DoD.  
2. Prefer one continuous operator session per host package to reduce version drift.  
3. After any product commit: abandon `$EVIDENCE_ROOT` for that SHA; new short directory.  
4. Do not merge `feat/native-1.1-desktop` into the freeze tree as part of this plan.
