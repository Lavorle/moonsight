# Formal 1.0 M0 checkpoint verification

## Scope

- Protected baseline: `46130ef793ed57685a063bdbbd0731d66c8db35d`
- Protected checkpoint: `d92cdbf7b7583eab0aa29ecb8e33aaa3cdebb014`
- Recovery artifacts: `.omx/checkpoints/formal-1.0-m0-20260712T163332Z`
- Closure plan: `.omx/plans/moonsight-formal-1.0-blocker-closure.md`

This record verifies the protected blocker-closure checkpoint before M1/M2
work. It does not select a release candidate or replace real-environment W1,
D1, or C1 evidence.

## Recovery verification

The artifact manifest was verified from the leader repository root because its
entries are repository-relative:

```sh
(cd /mnt/nvme1n1p2/moonsight && \
  sha256sum -c .omx/checkpoints/formal-1.0-m0-20260712T163332Z/artifact-sha256.txt)
sha256sum -c \
  /mnt/nvme1n1p2/moonsight/.omx/checkpoints/formal-1.0-m0-20260712T163332Z/sha256.txt
```

Result: all six recovery artifacts and all 50 preserved files matched their
recorded SHA-256 digests.

The original tree was reconstructed without a checkout/reset operation:

```sh
tmp=$(mktemp -d)
git archive 46130ef | tar -x -C "$tmp"
(cd "$tmp" && git apply "$checkpoint/tracked.patch")
tar -xzf "$checkpoint/dirty-files.tar.gz" -C "$tmp"
(cd "$tmp" && sha256sum -c "$checkpoint/sha256.txt")
```

Result: all 50 reconstructed paths matched. The NUL-delimited path set from
`dirty-paths.zlist` also matched `git diff --name-only -z 46130ef d92cdbf`.

## Path classification

Every preserved path maps to the blocker-closure plan. Categories below are
primary ownership; `README.mbt.md` and `gameSession.ts` also bridge adjacent
closure outcomes.

### B1 — production boot fails closed (4)

- `apps/host-web/src/App.svelte`
- `apps/host-web/src/lib/contentBoot.test.mjs`
- `apps/host-web/src/lib/gameSession.ts`
- `apps/host-web/src/lib/wasm.ts`

### B2 — menu load diagnostics and atomic failure (7)

- `host_web/main.mbt`
- `host_web/main_wbtest.mbt`
- `host_web/moon.pkg`
- `host_web/pkg.generated.mbti`
- `runtime/engine.mbt`
- `runtime/engine_test.mbt`
- `runtime/pkg.generated.mbti`

The generated `.mbti` files are owned by the exported runtime/host API changes;
`host_web/moon.pkg` owns the WebAssembly test dependency needed by the new host
diagnostic regression test.

### B3 — CI matrix, formatter closure, CLI fixtures, and package smoke (36)

- `.github/workflows/ci.yml`
- `audio/mixer.mbt`
- `cmd/moonsightc/assets_check.mbt`
- `cmd/moonsightc/check.mbt`
- `cmd/moonsightc/fs.mbt`
- `cmd/moonsightc/moon.pkg`
- `cmd/moonsightc/new.mbt`
- `cmd/moonsightc/ui_link.mbt`
- `render/noto_advances.mbt`
- `render/snapshot.mbt`
- `render/snapshot_test.mbt`
- `render/text_layout.mbt`
- `runtime/backlog.mbt`
- `runtime/director_test.mbt`
- `runtime/host.mbt`
- `runtime/prefs.mbt`
- `runtime/save.mbt`
- `runtime/save_test.mbt`
- `runtime/stage.mbt`
- `runtime/stage_test.mbt`
- `runtime/ui_app.mbt`
- `runtime/ui_runtime.mbt`
- `runtime/ui_test.mbt`
- `runtime/ui_types.mbt`
- `script/lexer_test.mbt`
- `script/macro.mbt`
- `script/parser.mbt`
- `scripts/verify-package.sh`
- `std_commands/audio_cmd.mbt`
- `std_commands/layer.mbt`
- `std_commands/registry.mbt`
- `std_commands/registry_test.mbt`
- `std_ui/hud.mbt`
- `std_ui/lib.mbt`
- `std_ui/lib_test.mbt`
- `std_ui/modals.mbt`

### B4 — truthful manual evidence and release claims (3)

- `README.mbt.md`
- `docs/release-1.0-verification.md`
- `host_desktop/README.md`

`docs/release-1.0-verification.md` remains `BLOCKED`, with W1/D1/C1 and the
candidate matrix still `NOT RUN`. No manual result was promoted to `PASS`.

## Automated matrix on the protected checkpoint

Toolchains used:

- MoonBit `0.1.20260703 (6fbf8c3 2026-07-03)`
- Node.js `v24.13.1`, npm `11.8.0`
- Rust `1.97.0`, Cargo `1.97.0`

<!-- markdownlint-disable MD013 -->

| Surface | Command | Result |
| --- | --- | --- |
| Format | `moon fmt --check` | PASS |
| MoonBit | `moon check --target all` | PASS |
| MoonBit | `moon test` | PASS — 244/244 |
| WebAssembly | `moon build --target wasm-gc --release host_web` | PASS |
| Host | `npm ci && npm test && npx tsc --noEmit && npm run build` in `apps/host-web` | PASS — 31/31 tests |
| Docs | `npm ci && npm run types:check && npm run build` in `apps/docs-site` | PASS |
| Desktop | `cargo fmt --check && cargo check && cargo test` in `host_desktop/tauri/src-tauri` | PASS — 5/5 tests |
| CLI | `version`, demo `check`, and temporary `new -> check -> build` | PASS |
| Package | demo build plus `scripts/verify-package.sh` | PASS |
| Negative package | missing, empty, and corrupt `game.msb` | PASS — all rejected |
| Negative CLI | build without `apps/host-web/dist` from an isolated `git archive` | PASS — failed with the documented `npm run build` guidance and left no output |

<!-- markdownlint-enable MD013 -->

The missing-host negative was rerun from an isolated `git archive`. A linked
worktree run can discover the main checkout's ignored `apps/host-web/dist`
while walking ancestor directories, which does not model a clean CI checkout.
The isolated archive removes that harness-only false positive.

## M0 conclusion

- Recovery artifacts reproduce the protected closure diff exactly.
- All 50 paths belong to B1-B4 closure work; no unrelated path was found.
- The automated closure matrix is green on `d92cdbf`.
- The worktree returned clean after the matrix.
- W1, D1, and C1 remain truthfully blocked/not run.
