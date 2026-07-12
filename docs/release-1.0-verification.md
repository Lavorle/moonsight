# MoonSight formal 1.0 verification record

This document is the durable evidence template for the release-critical 1.0
gates. It intentionally distinguishes automated checks from real-environment
play evidence. A build, static asset smoke, or headless browser result is not a
substitute for W1, D1, or C1.

## Current release status

**BLOCKED** — no immutable release-candidate commit has complete W1, D1, and C1
evidence yet.

| Field | Value |
|---|---|
| Candidate commit | `NOT SELECTED` |
| Candidate build/run | `NOT RUN` |
| Tester | `NOT ASSIGNED` |
| Started (UTC) | `NOT RUN` |
| Completed (UTC) | `NOT RUN` |
| Overall result | **BLOCKED** |

Do not replace `NOT RUN`, `BLOCKED`, or `FAIL` with `PASS` unless the recorded
steps were executed against the exact candidate commit and the referenced
artifacts are retained.

## Automated release matrix

The repository CI workflow enforces the following checks. Record the GitHub
Actions run URL for the candidate rather than copying results from another SHA.

| Surface | Required check | Candidate result |
|---|---|---|
| MoonBit | `moon fmt --check` | NOT RUN |
| MoonBit | `moon check --target all` | NOT RUN |
| MoonBit | `moon test` | NOT RUN |
| MoonBit | `moon build --target wasm-gc --release host_web` | NOT RUN |
| Web host | tests, `npx tsc --noEmit`, production build | NOT RUN |
| CLI | version, demo check, `new -> check -> build`, demo build | NOT RUN |
| CLI negative | build without `apps/host-web/dist` fails clearly | NOT RUN |
| Package | required assets; missing/empty/corrupt MSB rejected | NOT RUN |
| Docs | typecheck and production build | NOT RUN |
| Desktop Rust | format, check, tests | NOT RUN |

**Candidate CI run:** `NOT RUN`

## W1 — WebGPU browser play and web persistence

**Status: NOT RUN**

### Environment

- Candidate commit:
- Packaged artifact / checksum:
- OS and version:
- Browser and version:
- GPU and driver:
- WebGPU adapter information:
- Tester:
- Timestamp (UTC):

### Steps and expected results

1. Serve the candidate `dist/demo` over HTTP and open it in a browser with a
   real WebGPU adapter.
2. Confirm title -> Start -> advance works without the error panel.
3. Save to a slot, record the visible slot metadata, and reload the page.
4. Load the slot and confirm scene, text, variables, layers, UI, and audio state
   resume at the saved point.
5. Separately serve a package with missing, empty, and corrupt `game.msb` files.
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

### Environment

- Candidate commit:
- Packaged artifact / checksum:
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

### Environment

- Candidate commit:
- Host (web or desktop) and version:
- OS / browser / webview / GPU:
- Tester:
- Timestamp (UTC):

### Steps and expected results

1. Start a fresh playthrough of `demo/game` from the title.
2. Complete the representative story arc without debug shortcuts.
3. Exercise choices, menu save/load, quick save/load, preferences, backlog, and
   return-to-title behavior during the playthrough.
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

Formal 1.0 can be marked ready only when the automated matrix is green and W1,
D1, and C1 are all `PASS` for the same immutable candidate commit. Any `FAIL`,
`BLOCKED`, `NOT RUN`, mismatched SHA, or missing artifact keeps the release
blocked.
