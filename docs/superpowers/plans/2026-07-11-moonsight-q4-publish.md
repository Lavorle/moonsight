# MoonSight Q4 — 能发布（1.0 候选）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship **1.0 candidate**: authors can `moonsightc new` → build a Svelte-only Web dist → play on Web (localStorage) and Desktop (appData SaveStore) with a 30–60 minute sample chapter.

**Architecture:** Multi-track in one season. CLI gains `new` + hard-fails without `apps/host-web/dist`. Host extracts a `SaveStore` interface (Web = localStorage, Desktop = Tauri appData files); `GameSession` never touches storage APIs directly. `js_glue` leaves the default build path (archive). Demo expands in `demo/game`. Docs cover new / publish / desktop saves.

**Tech Stack:** MoonBit native CLI (`cmd/moonsightc`, `export CC=gcc`), Vite + Svelte 5 + TS (`apps/host-web`), Tauri 2 (`host_desktop/tauri`), Fumadocs (`apps/docs-site`), existing wasm Engine (save v4 unchanged).

**Spec:** `docs/superpowers/specs/2026-07-11-moonsight-q4-publish-design.md`  
**Roadmap:** `docs/superpowers/specs/2026-07-11-moonsight-roadmap-v2-design.md` (Q4 row)

**Pinned defaults (from spec):**

| Item | Choice |
|------|--------|
| Success story | Web + desktop can ship short-medium VN |
| Save | SaveStore; Web LS keys unchanged; desktop appData files |
| Template | `moonsightc new` + `templates/minimal` only |
| Shell | Svelte dist **required**; no js_glue fallback |
| js_glue | Archive under `archive/js_glue/` (not deleted from git history) |
| Save format | **v4** unchanged |
| Demo | Expand `demo/game` to ~30–60 min skeleton |
| `build` + npm | Does **not** auto-run npm; fails with clear message |
| Formal 1.0 | Still Q5 |

**Cut order if schedule slips:** SaveStore dual-end + Svelte-only build + `new` → archive js_glue → publish scripts/docs → demo body count → optional check heuristics → polish.

**Suggested parallel tracks after Task 1–2 land contracts:** Engine (Tasks 1–3, 9) ∥ Host SaveStore (4–5) ∥ Demo content (7) ∥ Docs (8). Task 10 is joint gate.

---

## File map

| Path | Role |
|------|------|
| `templates/minimal/**` | Scaffold source for `new` |
| `cmd/moonsightc/new.mbt` | `cmd_new` implementation |
| `cmd/moonsightc/main.mbt` | Wire `new` subcommand + usage |
| `cmd/moonsightc/build.mbt` | Svelte-only `find_host_shell`; hard fail if missing |
| `cmd/moonsightc/ui_link.mbt` | Stop writing wasm into `js_glue` |
| `archive/js_glue/**` | Retired vanilla shell (moved from `host_web/js_glue`) |
| `archive/js_glue/README.md` | Retired notice |
| `apps/host-web/src/lib/saveStore.ts` | `SaveStore` interface + `WebSaveStore` + memory fake for tests |
| `apps/host-web/src/lib/prefs.ts` | Prefs load/save accept `SaveStore` (no raw LS in call sites) |
| `apps/host-web/src/lib/gameSession.ts` | Inject `SaveStore`; seed/sync only via store |
| `apps/host-web/src/lib/desktopSaveStore.ts` | Desktop implementation via Tauri invoke |
| `apps/host-web/src/main.ts` / `App.svelte` | Construct Web vs Desktop store |
| `host_desktop/tauri/src-tauri/src/lib.rs` | `read_save_*` / `write_save_*` / prefs commands |
| `host_desktop/tauri/src-tauri/capabilities/*` | FS / appData permissions as needed |
| `host_desktop/README.md` | Desktop save + build path |
| `scripts/publish-web.sh` | npm + moon + moonsightc → dist |
| `scripts/publish-desktop.sh` | web dist then tauri build (document if GUI required) |
| `demo/game/**` | Sample chapter expansion |
| `docs/project-layout.md`, `docs/*.md` as needed | Repo truth |
| `apps/docs-site/content/{zh,en}/**` | new / publish / desktop pages |
| `README.mbt.md` | Q4 / 1.0-candidate scope |
| `moonsight-demo.sh` | Drop js_glue assumptions |

---

## Task 1: Minimal template + `moonsightc new`

**Files:**
- Create: `templates/minimal/moonsight.json`
- Create: `templates/minimal/main.yuki`
- Create: `templates/minimal/assets/.gitkeep` (and at least one PNG if scripts require it — prefer real tiny placeholder)
- Create: `templates/minimal/README.md`
- Create: `cmd/moonsightc/new.mbt`
- Modify: `cmd/moonsightc/main.mbt`

- [ ] **Step 1: Create template tree**

`templates/minimal/moonsight.json`:

```json
{
  "name": "my-moonsight-game",
  "entry": "main.yuki",
  "logical_width": 1920,
  "logical_height": 1080,
  "save_slots": 6
}
```

`templates/minimal/main.yuki` (no `ui_package`; cold-start title still works via std_ui):

```text
- scene "entrypoint"
@flow.jump "intro"

- scene "intro"
y:Welcome. This project was created with moonsightc new.
y:Edit main.yuki and rebuild.
@flow.choice "Continue" "Quit path" --result act
@flow.jump_if act 0 "end_a"
@flow.jump "end_b"

- scene "end_a"
y:You chose Continue. Thanks for playing.
@flow.yield

- scene "end_b"
y:You chose the other path. Thanks for playing.
@flow.yield
```

`templates/minimal/README.md`: short steps — `export CC=gcc`, build host-web dist, `moon run cmd/moonsightc --target native -- check .`, `build . -o dist/game`, serve dist.

Copy a tiny existing PNG from `demo/game/assets/` into `templates/minimal/assets/` only if the template script references it; current template above needs **no** assets (OK). If later lines add layers, add matching files.

- [ ] **Step 2: Implement template discovery + `cmd_new`**

Create `cmd/moonsightc/new.mbt`:

```mbt
///|
/// Resolve monorepo `templates/minimal` by walking parents of cwd (same idea as find_host_shell).
fn find_minimal_template() -> String? {
  let candidates = [
    "templates/minimal", "./templates/minimal", "../templates/minimal",
  ]
  for c in candidates {
    if path_exists(c) && is_dir(c) && path_exists(join_path(c, "moonsight.json")) {
      return Some(c)
    }
  }
  match @env.current_dir() {
    Some(cwd) => {
      let mut dir = cwd
      for _ in 0..<8 {
        let t = join_path(dir, "templates/minimal")
        if path_exists(t) && is_dir(t) && path_exists(join_path(t, "moonsight.json")) {
          return Some(t)
        }
        let parent = dirname(dir)
        if parent == dir {
          break
        }
        dir = parent
      }
      None
    }
    None => None
  }
}

///|
/// `moonsightc new <name> [-o <parent_dir>]`
fn cmd_new(name : String, parent_dir : String) -> Int {
  if name.length() == 0 || name.contains("/") || name.contains("\\") {
    println("error: invalid project name: \{name}")
    return 1
  }
  let dest = join_path(parent_dir, name)
  if path_exists(dest) {
    println("error: destination already exists: \{dest}")
    return 1
  }
  match find_minimal_template() {
    None => {
      println("error: templates/minimal not found (run from moonsight monorepo)")
      1
    }
    Some(tmpl) =>
      try {
        ensure_dir(parent_dir)
        copy_dir(tmpl, dest)
        // Patch name in moonsight.json if present
        let cfg_path = join_path(dest, "moonsight.json")
        if path_exists(cfg_path) {
          let raw = read_file_string(cfg_path) // use existing fs helpers; adapt name if different
          // Minimal: leave template name or replace "my-moonsight-game" → name
          let patched = raw.replace_all("my-moonsight-game", name)
          write_string_to_file(cfg_path, patched)
        }
        println("created \{dest}")
        println("next: export CC=gcc && moon run cmd/moonsightc --target native -- check \{dest}")
        println("      (requires apps/host-web/dist before build — see docs)")
        0
      } catch {
        e => {
          println("error: new failed: \{e}")
          1
        }
      }
  }
}
```

Adapt to actual FS API names in `fs.mbt` (`read_file` / `write_string_to_file` / `copy_dir` already exist). If `replace_all` is unavailable, write a tiny string replace or leave JSON name as template default.

- [ ] **Step 3: Wire CLI**

In `cmd/moonsightc/main.mbt`:

- Update `print_usage` to include `new <name> [-o <parent_dir>]`.
- Parse `-o` for new (reuse pattern from `out_dir_from`, default `"."`).
- Match arm:

```mbt
["new"] => {
  println("error: new requires <name>")
  print_usage()
  1
}
["new", name, .. rest] => cmd_new(name, parent_dir_from(rest))
```

Bump version string to `moonsightc 0.9.0-candidate` in the version arm.

- [ ] **Step 4: Smoke `new`**

```bash
export CC=gcc
rm -rf /tmp/ms-new-smoke
moon run cmd/moonsightc --target native -- new smoke_game -o /tmp/ms-new-smoke
test -f /tmp/ms-new-smoke/smoke_game/moonsight.json
moon run cmd/moonsightc --target native -- check /tmp/ms-new-smoke/smoke_game
# second new must fail
moon run cmd/moonsightc --target native -- new smoke_game -o /tmp/ms-new-smoke ; test $? -ne 0
```

Expected: first create + check exit 0; second new non-zero.

- [ ] **Step 5: Commit**

```bash
git add templates/minimal cmd/moonsightc/new.mbt cmd/moonsightc/main.mbt
git commit -m "feat(moonsightc): add new command and minimal project template"
```

---

## Task 2: `build` hard-requires Svelte dist

**Files:**
- Modify: `cmd/moonsightc/build.mbt`

- [ ] **Step 1: Change `find_host_shell` to Svelte-only**

Remove all `host_web/js_glue` candidates and parent-walk glue branches.

```mbt
///|
/// Locate the web host shell: **only** `apps/host-web/dist` with `index.html`.
fn find_host_shell() -> String? {
  let candidates = [
    "apps/host-web/dist", "./apps/host-web/dist", "../apps/host-web/dist",
  ]
  for c in candidates {
    if is_host_shell_dir(c) {
      return Some(c)
    }
  }
  match @env.current_dir() {
    Some(cwd) => {
      let mut dir = cwd
      for _ in 0..<8 {
        let dist = join_path(dir, "apps/host-web/dist")
        if is_host_shell_dir(dist) {
          return Some(dist)
        }
        let parent = dirname(dir)
        if parent == dir {
          break
        }
        dir = parent
      }
      None
    }
    None => None
  }
}

///|
/// Svelte/Vite dist must ship `index.html` (no boot.js fallback).
fn is_host_shell_dir(dir : String) -> Bool {
  path_exists(join_path(dir, "index.html"))
}
```

- [ ] **Step 2: Hard-fail when shell missing**

In `cmd_build`, replace warning-and-continue with:

```mbt
match find_host_shell() {
  Some(shell) => {
    copy_host_shell(shell, staging)
    println("copied host shell from \{shell}")
  }
  None => {
    println(
      "error: Svelte host shell not found (apps/host-web/dist/index.html).\n" +
      "  Build it first: cd apps/host-web && npm i && npm run build\n" +
      "  Then: moon run cmd/moonsightc --target native -- build <project> -o <out>",
    )
    remove_tree_best_effort(staging)
    restore_project_ui_stub()
    return 1
  }
}
```

Update file header comment (line ~13): drop js_glue fallback wording.

- [ ] **Step 3: Smoke**

```bash
export CC=gcc
# With dist present:
cd apps/host-web && npm run build && cd ../..
moon run cmd/moonsightc --target native -- build /tmp/ms-new-smoke/smoke_game -o /tmp/ms-new-smoke/dist
test -f /tmp/ms-new-smoke/dist/index.html
test -f /tmp/ms-new-smoke/dist/game.msb

# Without dist (rename temporarily):
mv apps/host-web/dist apps/host-web/dist.bak
moon run cmd/moonsightc --target native -- build /tmp/ms-new-smoke/smoke_game -o /tmp/ms-new-smoke/dist2 ; test $? -ne 0
mv apps/host-web/dist.bak apps/host-web/dist
```

Expected: build succeeds with dist; fails without; error text mentions npm run build, not js_glue.

- [ ] **Step 4: Commit**

```bash
git add cmd/moonsightc/build.mbt
git commit -m "feat(moonsightc): require Svelte host-web dist for build"
```

---

## Task 3: Archive `js_glue` + purge default-path references

**Files:**
- Move: `host_web/js_glue/**` → `archive/js_glue/**`
- Create: `archive/js_glue/README.md`
- Modify: `cmd/moonsightc/ui_link.mbt` (stop copying wasm to js_glue)
- Modify: `README.mbt.md`, `host_desktop/README.md`, `moonsight-demo.sh` (if present), any CI under `.github/`
- Grep entire repo for `js_glue` and fix **default path** docs/scripts (leave historical specs as historical)

- [ ] **Step 1: Move tree**

```bash
mkdir -p archive
git mv host_web/js_glue archive/js_glue
```

`archive/js_glue/README.md`:

```markdown
# Archived: vanilla js_glue host

Retired in Q4. Default playable path is `apps/host-web` (Svelte).
`moonsightc build` does not copy this tree. Kept for historical reference only.
```

- [ ] **Step 2: `ui_link.mbt`**

Remove or guard the block that copies release wasm to `host_web/js_glue/host_web.wasm` (around lines 203–210). Prefer **delete** that sync entirely.

- [ ] **Step 3: Grep cleanup**

```bash
rg -n 'js_glue' --glob '!docs/superpowers/**' --glob '!archive/**' --glob '!.git/**'
```

Update README Quickstart, host_desktop README intro, moonsight-demo.sh, CI workflows so no script **depends** on `host_web/js_glue`. Specs under `docs/superpowers/specs` that are historical may still mention js_glue; Q4 design already documents the break.

- [ ] **Step 4: Smoke demo build**

```bash
export CC=gcc
moon build --target wasm-gc --release host_web
cd apps/host-web && npm run build && cd ../..
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
test -f dist/demo/index.html && test -f dist/demo/host_web.wasm
```

- [ ] **Step 5: Commit**

```bash
git add -A archive cmd/moonsightc/ui_link.mbt README.mbt.md host_desktop/README.md moonsight-demo.sh .github
git commit -m "chore: archive js_glue; Svelte is the only host shell path"
```

---

## Task 4: SaveStore interface + Web wiring

**Files:**
- Create: `apps/host-web/src/lib/saveStore.ts`
- Modify: `apps/host-web/src/lib/prefs.ts`
- Modify: `apps/host-web/src/lib/gameSession.ts`
- Modify: `apps/host-web/src/main.ts` and/or `App.svelte` as needed

- [ ] **Step 1: Add `saveStore.ts`**

```ts
/** Host persistence boundary (spec Q4 §3.3). Engine save JSON stays v4. */

export interface SaveStore {
  loadPrefs(): string | null;
  savePrefs(json: string): void;
  loadSlot(slot: number): string | null;
  saveSlot(slot: number, json: string): void;
}

export const PREFS_KEY = "moonsight/prefs";
export const SAVE_KEY = (slot: number) => `moonsight/save/${slot}`;

/** In-memory store for unit tests. */
export class MemorySaveStore implements SaveStore {
  prefs: string | null = null;
  slots = new Map<number, string>();
  loadPrefs(): string | null {
    return this.prefs;
  }
  savePrefs(json: string): void {
    this.prefs = json;
  }
  loadSlot(slot: number): string | null {
    return this.slots.get(slot) ?? null;
  }
  saveSlot(slot: number, json: string): void {
    this.slots.set(slot, json);
  }
}

export class WebSaveStore implements SaveStore {
  loadPrefs(): string | null {
    try {
      return localStorage.getItem(PREFS_KEY);
    } catch {
      return null;
    }
  }
  savePrefs(json: string): void {
    try {
      if (json && json.length) localStorage.setItem(PREFS_KEY, json);
    } catch {
      console.error("[moonsight] savePrefs failed");
    }
  }
  loadSlot(slot: number): string | null {
    try {
      return localStorage.getItem(SAVE_KEY(slot));
    } catch {
      return null;
    }
  }
  saveSlot(slot: number, json: string): void {
    try {
      if (json && json.length) localStorage.setItem(SAVE_KEY(slot), json);
    } catch {
      console.error("[moonsight] saveSlot failed", slot);
    }
  }
}
```

- [ ] **Step 2: Refactor `prefs.ts`**

- Re-export `PREFS_KEY` from `saveStore` **or** keep constant single source in `saveStore` and import here.
- Change:

```ts
export function loadPrefsFromStorage(
  store: SaveStore,
  exports_: PrefsWasmExports | null,
  current: Prefs,
): Prefs {
  let prefs = { ...current };
  try {
    const raw = store.loadPrefs();
    if (raw && typeof exports_?.set_prefs_json === "function") {
      const rc = exports_.set_prefs_json(raw);
      if (rc === 0 && typeof exports_.prefs_json === "function") {
        const applied = exports_.prefs_json();
        if (applied) prefs = parsePrefsJson(applied, prefs);
      }
    } else if (raw) {
      prefs = parsePrefsJson(raw, prefs);
    }
  } catch {
    /* blocked storage */
  }
  return prefs;
}

export function savePrefsToStorage(
  store: SaveStore,
  exports_: PrefsWasmExports | null,
  current: Prefs,
): Prefs {
  let prefs = { ...current };
  try {
    if (typeof exports_?.prefs_json === "function") {
      const json = exports_.prefs_json();
      if (json && json.length) {
        store.savePrefs(json);
        prefs = parsePrefsJson(json, prefs);
      }
    }
  } catch {
    /* ignore */
  }
  return prefs;
}
```

Update all call sites of `loadPrefsFromStorage` / `savePrefsToStorage` / `readPrefsFromStorage` / `writePrefsToStorage` to pass a store (or implement thin wrappers that use `WebSaveStore` only inside deprecated helpers — **prefer deleting direct LS helpers**).

- [ ] **Step 3: Refactor `GameSession`**

- Add field: `store: SaveStore` (construct with `WebSaveStore` by default for browser).
- Constructor or `start({ store?: SaveStore })` injects store.
- Replace `hydrateSlotsFromStorage` / `syncSlotsToStorage` bodies:

```ts
private hydrateSlotsFromStorage(): void {
  const exports_ = this.exports_;
  if (!exports_ || typeof exports_.set_slot_json !== "function") return;
  const n =
    typeof exports_.save_slot_count === "function"
      ? exports_.save_slot_count() | 0
      : 6;
  for (let i = 0; i < Math.max(n, 1); i++) {
    try {
      const json = this.store.loadSlot(i);
      if (json && json.length) exports_.set_slot_json(i, json);
    } catch {
      /* skip bad slot */
    }
  }
}

private syncSlotsToStorage(): void {
  const exports_ = this.exports_;
  if (!exports_ || typeof exports_.get_slot_json !== "function") return;
  const n =
    typeof exports_.save_slot_count === "function"
      ? exports_.save_slot_count() | 0
      : 6;
  for (let i = 0; i < Math.max(n, 1); i++) {
    try {
      const json = exports_.get_slot_json(i);
      if (json && json.length) {
        const stamped = this.stampSavedAt(json);
        if (stamped !== json && typeof exports_.set_slot_json === "function") {
          exports_.set_slot_json(i, stamped);
        }
        this.store.saveSlot(i, stamped);
      }
    } catch {
      /* ignore */
    }
  }
}
```

- Remove module-level `SAVE_KEY` if moved to `saveStore.ts`.
- Grep `localStorage` under `apps/host-web/src`: **only** `saveStore.ts` (WebSaveStore) may reference it.

```bash
rg -n 'localStorage' apps/host-web/src
# expected: saveStore.ts only
```

- [ ] **Step 4: Manual / build check**

```bash
cd apps/host-web && npm run build
```

Expected: exit 0. Optionally add a tiny node test for `MemorySaveStore` if the package already has a test runner; if not, skip formal unit test and rely on grep + build.

- [ ] **Step 5: Commit**

```bash
git add apps/host-web/src/lib/saveStore.ts apps/host-web/src/lib/prefs.ts apps/host-web/src/lib/gameSession.ts apps/host-web/src
git commit -m "feat(host-web): SaveStore interface and WebSaveStore for prefs/slots"
```

---

## Task 5: Desktop SaveStore (Tauri appData)

**Files:**
- Modify: `host_desktop/tauri/src-tauri/src/lib.rs`
- Modify: `host_desktop/tauri/src-tauri/Cargo.toml` if plugin needed
- Modify: capabilities / `tauri.conf.json` as required for appData FS
- Create: `apps/host-web/src/lib/desktopSaveStore.ts`
- Modify: `apps/host-web/src` boot path to pick Desktop store when `window.__TAURI__` (or `import.meta.env` / Tauri detect)

- [ ] **Step 1: Rust commands**

In `lib.rs`, register commands (names fixed for TS):

```rust
use std::fs;
use std::path::PathBuf;
use tauri::Manager;

fn moonsight_dir(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?
        .join("moonsight");
    fs::create_dir_all(dir.join("saves")).map_err(|e| e.to_string())?;
    Ok(dir)
}

#[tauri::command]
fn read_prefs(app: tauri::AppHandle) -> Result<Option<String>, String> {
    let path = moonsight_dir(&app)?.join("prefs.json");
    if !path.exists() {
        return Ok(None);
    }
    fs::read_to_string(path).map(Some).map_err(|e| e.to_string())
}

#[tauri::command]
fn write_prefs(app: tauri::AppHandle, body: String) -> Result<(), String> {
    let path = moonsight_dir(&app)?.join("prefs.json");
    atomic_write(&path, body)
}

#[tauri::command]
fn read_save_slot(app: tauri::AppHandle, slot: u32) -> Result<Option<String>, String> {
    let path = moonsight_dir(&app)?.join("saves").join(format!("{slot}.json"));
    if !path.exists() {
        return Ok(None);
    }
    fs::read_to_string(path).map(Some).map_err(|e| e.to_string())
}

#[tauri::command]
fn write_save_slot(app: tauri::AppHandle, slot: u32, body: String) -> Result<(), String> {
    let path = moonsight_dir(&app)?.join("saves").join(format!("{slot}.json"));
    atomic_write(&path, body)
}

fn atomic_write(path: &std::path::Path, body: String) -> Result<(), String> {
    let tmp = path.with_extension("json.tmp");
    fs::write(&tmp, body).map_err(|e| e.to_string())?;
    fs::rename(&tmp, path).map_err(|e| e.to_string())
}

// In run():
// .invoke_handler(tauri::generate_handler![
//   read_prefs, write_prefs, read_save_slot, write_save_slot
// ])
```

Adjust for actual Tauri 2 path API (`app.path().app_data_dir()` requires `tauri::Manager` + path plugin — enable `@tauri-apps/plugin-fs` **or** built-in path as already used by the project). Prefer **minimal** deps: if path plugin not present, use `dirs` crate or Tauri 2 `path` feature from docs in this repo's Tauri version.

Update module comment: saves no longer stay only in localStorage on desktop.

- [ ] **Step 2: `DesktopSaveStore`**

```ts
import type { SaveStore } from "./saveStore";

type Invoke = <T>(cmd: string, args?: Record<string, unknown>) => Promise<T>;

function getInvoke(): Invoke | null {
  const w = window as unknown as {
    __TAURI__?: { core?: { invoke?: Invoke } };
    __TAURI_INTERNALS__?: { invoke?: Invoke };
  };
  // Prefer @tauri-apps/api if package is added to host-web; else globals.
  return w.__TAURI__?.core?.invoke ?? w.__TAURI_INTERNALS__?.invoke ?? null;
}

export class DesktopSaveStore implements SaveStore {
  private invoke: Invoke;

  constructor(invoke?: Invoke) {
    const inv = invoke ?? getInvoke();
    if (!inv) throw new Error("DesktopSaveStore: Tauri invoke unavailable");
    this.invoke = inv;
  }

  loadPrefs(): string | null {
    // Sync interface: cache async results. Prefer async init in GameSession.
    return this._prefsCache;
  }
  // ... see Step 3 for async hydrate pattern
}
```

**Important:** Spec interface is sync (matches current GameSession). Desktop IO is async. **Pinned implementation pattern:**

1. `GameSession` gains `async initStore(): Promise<void>` **or** boot awaits `DesktopSaveStore.create()` which preloads all prefs + slots into a `MemorySaveStore`-like cache, then implements `SaveStore` against the cache and **write-through** async invoke (fire-and-await in async methods used from save paths).

**Recommended concrete approach (use this):**

```ts
export class DesktopSaveStore implements SaveStore {
  private prefs: string | null = null;
  private slots = new Map<number, string>();
  private invoke: Invoke;

  static async create(invoke: Invoke, slotCount = 6): Promise<DesktopSaveStore> {
    const s = new DesktopSaveStore(invoke);
    s.prefs = (await invoke<string | null>("read_prefs")) ?? null;
    for (let i = 0; i < slotCount; i++) {
      const body = await invoke<string | null>("read_save_slot", { slot: i });
      if (body) s.slots.set(i, body);
    }
    return s;
  }

  private constructor(invoke: Invoke) {
    this.invoke = invoke;
  }

  loadPrefs(): string | null {
    return this.prefs;
  }
  savePrefs(json: string): void {
    this.prefs = json;
    void this.invoke("write_prefs", { body: json }).catch((e) =>
      console.error("[moonsight] write_prefs", e),
    );
  }
  loadSlot(slot: number): string | null {
    return this.slots.get(slot) ?? null;
  }
  saveSlot(slot: number, json: string): void {
    this.slots.set(slot, json);
    void this.invoke("write_save_slot", { slot, body: json }).catch((e) =>
      console.error("[moonsight] write_save_slot", e),
    );
  }
}
```

- [ ] **Step 3: Boot selection**

In `App.svelte` / `main.ts` / `GameSession.start`:

```ts
async function createSaveStore(): Promise<SaveStore> {
  const isTauri = !!(window as unknown as { __TAURI_INTERNALS__?: unknown })
    .__TAURI_INTERNALS__;
  if (isTauri) {
    const { invoke } = await import("@tauri-apps/api/core"); // add dep if missing
    return DesktopSaveStore.create(invoke);
  }
  return new WebSaveStore();
}
```

If adding `@tauri-apps/api` to `apps/host-web` is undesirable for pure web bundle size, use dynamic import only when Tauri detected, or inject invoke from a tiny `window.__MOONSIGHT_INVOKE__` set by a desktop-only snippet. **Pinned:** dynamic import / feature-detect; web build must still succeed without Tauri present at build time (externalize or optional dep).

- [ ] **Step 4: Document manual desktop test**

In `host_desktop/README.md` add checklist:

1. Build dist/demo  
2. `npm run tauri dev`  
3. Play → save slot 0 → quit → relaunch → load  
4. Confirm files under platform appData `.../moonsight/saves/0.json`

- [ ] **Step 5: Commit**

```bash
git add host_desktop apps/host-web/src/lib/desktopSaveStore.ts apps/host-web
git commit -m "feat(desktop): appData SaveStore via Tauri commands"
```

---

## Task 6: Publish scripts

**Files:**
- Create: `scripts/publish-web.sh`
- Create: `scripts/publish-desktop.sh`
- Modify: `host_desktop/README.md` (link scripts)

- [ ] **Step 1: `scripts/publish-web.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="${1:-demo/game}"
OUT="${2:-dist/demo}"
export CC="${CC:-gcc}"
cd "$ROOT"
cd apps/host-web && npm ci && npm run build && cd "$ROOT"
moon build --target wasm-gc --release host_web
moon run cmd/moonsightc --target native -- build "$PROJECT" -o "$OUT"
echo "OK: $OUT — serve with: cd $OUT && python3 -m http.server 8080"
```

- [ ] **Step 2: `scripts/publish-desktop.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Ensures dist/demo exists then tauri build
"$ROOT/scripts/publish-web.sh" demo/game dist/demo
cd "$ROOT/host_desktop/tauri"
npm ci
npm run tauri build
```

`chmod +x` both scripts.

- [ ] **Step 3: Smoke web script**

```bash
./scripts/publish-web.sh demo/game dist/demo
test -f dist/demo/game.msb
```

- [ ] **Step 4: Commit**

```bash
git add scripts/publish-web.sh scripts/publish-desktop.sh host_desktop/README.md
git commit -m "chore: add publish-web and publish-desktop scripts"
```

---

## Task 7: Demo sample chapter (30–60 min skeleton)

**Files:**
- Modify: `demo/game/main.yuki`
- Create: `demo/game/scenes/*.yuki` as needed (multi-file merge already supported)
- Modify: `demo/game/assets/*` only if new resource ids are referenced
- Keep: `demo/game/moonsight.json` (existing `ui_package`)

- [ ] **Step 1: Outline scenes (content plan)**

Minimum graph:

```text
entrypoint → intro
intro → branch A | branch B
A → mid_common
B → mid_common
mid_common → chapter2 → chapter3 → finale (good) | finale_alt
```

Dialogue volume: aim for **many short lines** (reuse BGM/bg/char). Include:

- `@trans.dissolve` + `@flow.wait` at least twice  
- `@layer.set` scale beat at least once  
- `@sys.save_hint` once mid-game  
- Esc menu still works (no script change needed)  
- At least two distinct ending lines  

- [ ] **Step 2: Implement yuki files**

Prefer splitting long content:

- `demo/game/main.yuki` — entry + early scenes  
- `demo/game/scenes/chapter2.yuki` — mid  
- `demo/game/scenes/finale.yuki` — endings  

Follow existing style (`- scene "name"`, host commands, `y:` speaker lines). Reuse `bg_room`, `char_y`, `bgm_soft`, `se_click`.

- [ ] **Step 3: check + build**

```bash
export CC=gcc
moon run cmd/moonsightc --target native -- check demo/game
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
```

Expected: 0 failed.

- [ ] **Step 4: Commit**

```bash
git add demo/game
git commit -m "feat(demo): expand sample chapter toward 30-60 minute arc"
```

---

## Task 8: Documentation (repo + Fumadocs)

**Files:**
- Modify: `docs/project-layout.md` — `new`, templates, no js_glue  
- Modify: `README.mbt.md` — Quickstart Svelte-only; Scope Q4 / 1.0 candidate when gate ready (update Scope in Task 10 if preferred)  
- Create: `apps/docs-site/content/zh/publish.mdx`, `en/publish.mdx`  
- Create: `apps/docs-site/content/zh/desktop.mdx`, `en/desktop.mdx`  
- Modify: `apps/docs-site/content/zh/getting-started.mdx`, `en/getting-started.mdx` — `moonsightc new`  
- Modify: `apps/docs-site/content/{zh,en}/meta.json` — register pages  

- [ ] **Step 1: Getting started — new**

Add section:

```markdown
## 从空项目开始

```bash
export CC=gcc
moon run cmd/moonsightc --target native -- new mygame
cd apps/host-web && npm i && npm run build && cd ../..
moon run cmd/moonsightc --target native -- check mygame
moon run cmd/moonsightc --target native -- build mygame -o dist/mygame
```
```

Remove all “fallback to js_glue” language.

- [ ] **Step 2: publish.mdx (zh + en)**

Cover: publish-web.sh, static host, WebGPU note, localStorage saves.

- [ ] **Step 3: desktop.mdx (zh + en)**

Cover: Tauri prerequisites, publish-desktop.sh / tauri build, appData path semantics, **Web slots ≠ desktop slots**.

- [ ] **Step 4: Build docs site**

```bash
cd apps/docs-site && npm run build
```

Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add docs apps/docs-site README.mbt.md
git commit -m "docs: Q4 new, publish, and desktop save author guides"
```

---

## Task 9 (optional): `check` jump-target heuristic

**Files:**
- Modify: `cmd/moonsightc/check.mbt` (and compile path as needed)

- [ ] **Step 1:** After successful compile in `cmd_check`, walk IR / module for jump targets (`flow.jump` / scene names) and report **error** if target scene missing.  
- [ ] **Step 2:** Ensure `templates/minimal` and `demo/game` still check clean.  
- [ ] **Step 3:** Commit `feat(moonsightc): check unknown jump targets`  

Skip entirely if time-constrained; not a joint-gate killer.

---

## Task 10: Joint gate verification + README Scope

**Files:**
- Modify: `README.mbt.md` Scope → Q4 / 1.0 candidate delivered list  
- Optional: `.superpowers/sdd/q4-final-verify-report.md`

- [ ] **Step 1: Automated gates**

```bash
export CC=gcc
moon check
moon test
moon build --target wasm-gc --release host_web
cd apps/host-web && npm run build && cd ../..
rm -rf /tmp/ms-q4-new && moon run cmd/moonsightc --target native -- new q4t -o /tmp/ms-q4-new
moon run cmd/moonsightc --target native -- check /tmp/ms-q4-new/q4t
moon run cmd/moonsightc --target native -- build /tmp/ms-q4-new/q4t -o /tmp/ms-q4-new/dist
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
cd apps/docs-site && npm run build && cd ../..
# Fail path:
mv apps/host-web/dist /tmp/host-dist-bak
moon run cmd/moonsightc --target native -- build demo/game -o /tmp/should-fail ; test $? -ne 0
mv /tmp/host-dist-bak apps/host-web/dist
# Grep gate:
rg -n 'localStorage' apps/host-web/src | grep -v saveStore.ts && exit 1 || true
```

All must pass (fail path must fail).

- [ ] **Step 2: Manual checklists (honest)**

| # | Item | Env |
|---|------|-----|
| W1 | Serve dist/demo; title→play; save/load LS | Browser WebGPU |
| D1 | Tauri run; save; kill; load from appData | Desktop GUI |
| C1 | Demo arc completable; branch felt | Browser |

Defer with written note if no WebGPU/GUI — do **not** fake-pass.

- [ ] **Step 3: README Scope update**

Add **Q4 / 1.0 candidate** section summarizing: `new`, Svelte-only build, SaveStore, desktop appData, sample chapter, publish scripts, js_glue archived. Out of scope remains Q5+ items from design §6.3.

- [ ] **Step 4: Final commit**

```bash
git add README.mbt.md .superpowers/sdd/q4-final-verify-report.md
git commit -m "docs: Q4 1.0-candidate verification and README scope"
```

---

## Self-review (plan vs spec)

| Spec requirement | Task |
|------------------|------|
| `moonsightc new` + minimal template | T1 |
| build hard-requires Svelte dist | T2 |
| delete js_glue main path | T3 |
| SaveStore + Web LS | T4 |
| Desktop appData SaveStore | T5 |
| Publish scaffold scripts | T6 |
| 30–60 min demo skeleton | T7 |
| Docs new/publish/desktop | T8 |
| Optional check heuristic | T9 |
| Joint gate + README | T10 |
| save v4 unchanged | T4/T5 (no runtime format change) |
| build does not auto npm | T2 + T6 (script does) |
| no Web↔desktop migration | T5/T8 docs |
| formal 1.0 = Q5 | T10 wording |

**Placeholder scan:** none intentional.  
**Type consistency:** `SaveStore` methods `loadPrefs` / `savePrefs` / `loadSlot` / `saveSlot`; Tauri cmds `read_prefs` / `write_prefs` / `read_save_slot` / `write_save_slot`; Desktop cache + write-through pattern locked in T5.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-11-moonsight-q4-publish.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — this session with executing-plans and checkpoints  

Which approach?
