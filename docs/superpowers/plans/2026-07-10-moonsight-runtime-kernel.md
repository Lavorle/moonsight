# MoonSight Phase 1 Runtime Kernel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the MoonSight Phase 1 runtime kernel: MoonYuki script compile → IR/bytecode VM → theater Stage/Director → WebGPU full-scene composition, with browser + minimal desktop shell, demo, and docs.

**Architecture:** Layered theater model. `script` lowers MoonYuki to IR/bytecode; `runtime` interprets host calls through a Director that mutates an authoritative Stage; `render` draws a read-only Stage snapshot via WebGPU (including UI/text); platform shells only own window, I/O, and storage.

**Tech Stack:** MoonBit (wasm-gc for browser, native for CLI/tests where useful), WebGPU + Web Audio via thin JS glue, PNG textures, OGG/MP3 audio, Tauri (or Wry) desktop shell loading the same web build, logical resolution 1920×1080.

**Spec:** `docs/superpowers/specs/2026-07-10-moonsight-runtime-design.md`

**Pinned defaults (from spec §11):**

| Item | Choice |
|------|--------|
| Module name | `moonsight/moonsight` |
| Dialect name | MoonYuki (files `*.yuki`) |
| Bytecode | Custom little-endian `.msb` v1 |
| Texture | PNG |
| Audio | Web Audio; prefer OGG, fallback MP3 |
| Desktop | Tauri 2 loading `host_web` static output |
| License | Apache-2.0 |

---

## File map (create)

```
moonsight/
  moon.mod
  LICENSE
  README.mbt.md
  .gitignore                          # extend existing
  script/
    moon.pkg
    span.mbt                          # SourceSpan
    token.mbt                         # Token kinds
    lexer.mbt
    ast.mbt
    parser.mbt
    macro.mbt
    resolve.mbt
    ir.mbt
    lower.mbt
    bytecode.mbt
    compile.mbt                       # public compile entry
    diag.mbt                          # diagnostics
    lexer_test.mbt
    parser_test.mbt
    macro_test.mbt
    lower_test.mbt
    bytecode_test.mbt
    compile_test.mbt
  runtime/
    moon.pkg
    value.mbt                         # script values / vars
    stage.mbt                         # layers, text block, choices
    host.mbt                          # HostOp + HostHandler trait-ish
    director.mbt
    vm.mbt
    save.mbt
    intent.mbt                        # input intents
    engine.mbt                        # frame tick orchestration
    stage_test.mbt
    vm_test.mbt
    director_test.mbt
    save_test.mbt
    engine_test.mbt
  std_commands/
    moon.pkg
    registry.mbt                      # register text/layer/flow/audio/trans/var/sys
    text.mbt
    layer.mbt
    flow.mbt
    audio_cmd.mbt
    trans.mbt
    var_cmd.mbt
    sys_cmd.mbt
    registry_test.mbt
  render/
    moon.pkg
    types.mbt                         # Color, Rect, Transform2D
    snapshot.mbt                      # Stage → draw list
    gpu.mbt                           # GpuDevice abstract + JS externs
    sprite_batch.mbt
    text_layout.mbt
    glyph_atlas.mbt
    renderer.mbt
    snapshot_test.mbt
    text_layout_test.mbt
  audio/
    moon.pkg
    mixer.mbt                         # logical BGM/SE state
    backend.mbt                       # platform backend interface
    mixer_test.mbt
  host_web/
    moon.pkg                          # is-main, wasm-gc link
    main.mbt
    js_glue/                          # checked-in JS (not MoonBit)
      index.html
      boot.js                         # canvas, WebGPU init, input, save, audio
      webgpu_bridge.js
    assets/                           # demo hooks optional here
  host_desktop/
    README.md                         # how to wrap host_web with Tauri
    tauri/                            # minimal Tauri project skeleton
      ...
  cmd/moonsightc/
    moon.pkg                          # is-main, preferred native
    main.mbt
  demo/
    moon.pkg                          # optional; primarily content
    game/
      main.yuki
      scenes/
        intro.yuki
      assets/
        bg_room.png                   # placeholder or generated solid
        char_y.png
        bgm_soft.ogg                  # optional stub
      moonsight.toml                  # project manifest
  docs/
    moon-yuki-subset.md
    host-commands.md
    project-layout.md
```

**Dependency direction (must hold):**

```
script  (no deps on runtime/render)
runtime → script (IR/bytecode types only; prefer shared bytecode module via script)
std_commands → runtime
render → runtime (snapshot from Stage) OR render depends only on snapshot DTOs in runtime
audio → (standalone logical; runtime/director calls via host)
host_web → runtime, std_commands, render, audio
cmd/moonsightc → script
```

To keep `runtime` free of GPU types, put **draw-list DTOs** in `runtime/stage.mbt` (or `runtime/view.mbt`) and let `render` consume them.

---

### Task 1: Scaffold MoonBit module and packages

**Files:**
- Create: `moon.mod`, `LICENSE`, `README.mbt.md`
- Create: `script/moon.pkg`, `runtime/moon.pkg`, `std_commands/moon.pkg`, `render/moon.pkg`, `audio/moon.pkg`, `host_web/moon.pkg`, `cmd/moonsightc/moon.pkg`
- Modify: `.gitignore`

- [ ] **Step 1: Initialize module in existing repo**

From repo root (already has `docs/` and `.gitignore`):

```bash
cd /mnt/nvme1n1p2/moonsight
# Create moon.mod manually (do not moon new into non-empty root if it refuses)
```

Write `moon.mod`:

```
name = "moonsight/moonsight"
version = "0.1.0"
readme = "README.mbt.md"
license = "Apache-2.0"
keywords = ["visual-novel", "webgpu", "engine"]
description = "MoonSight visual novel engine — Phase 1 runtime kernel"

options(
  "preferred-target": "wasm-gc",
)
```

Write `LICENSE` as Apache-2.0 text (standard Apache-2.0 license body).

- [ ] **Step 2: Package manifests**

`script/moon.pkg` — empty imports initially:

```
// script package: MoonYuki compiler front/mid-end
```

`runtime/moon.pkg`:

```
import {
  "moonsight/moonsight/script",
}
```

`std_commands/moon.pkg`:

```
import {
  "moonsight/moonsight/runtime",
}
```

`render/moon.pkg`:

```
import {
  "moonsight/moonsight/runtime",
}
```

`audio/moon.pkg`:

```
// logical audio mixer
```

`host_web/moon.pkg`:

```
import {
  "moonsight/moonsight/runtime",
  "moonsight/moonsight/std_commands",
  "moonsight/moonsight/render",
  "moonsight/moonsight/audio",
}
options(
  "is-main": true,
)
```

`cmd/moonsightc/moon.pkg`:

```
import {
  "moonsight/moonsight/script",
}
supported_targets = "native | wasm-gc"
options(
  "is-main": true,
)
```

- [ ] **Step 3: Placeholder mains so packages typecheck**

`script/lib.mbt`:

```mbt
///|
/// MoonYuki script compiler package.
pub fn script_package_name() -> String {
  "script"
}
```

`runtime/lib.mbt`:

```mbt
///|
pub fn runtime_package_name() -> String {
  "runtime"
}
```

`std_commands/lib.mbt`:

```mbt
///|
pub fn std_commands_package_name() -> String {
  "std_commands"
}
```

`render/lib.mbt`:

```mbt
///|
pub fn render_package_name() -> String {
  "render"
}
```

`audio/lib.mbt`:

```mbt
///|
pub fn audio_package_name() -> String {
  "audio"
}
```

`cmd/moonsightc/main.mbt`:

```mbt
///|
fn main {
  println("moonsightc 0.1.0")
}
```

`host_web/main.mbt`:

```mbt
///|
fn main {
  println("moonsight host_web stub")
}
```

`README.mbt.md`:

````markdown
# MoonSight

MoonBit + WebGPU visual novel engine.

## Phase 1

Runtime kernel: MoonYuki → IR/VM → Stage → WebGPU.

```mbt check
test {
  inspect(@script.script_package_name(), content="script")
}
```
````

Note: root README test needs a root package or adjust — simpler: put README without cross-package test initially, only prose.

- [ ] **Step 4: Extend `.gitignore`**

```
.superpowers/
.omc/
_build/
.target/
.repos/
node_modules/
*.wasm
host_desktop/tauri/src-tauri/target/
```

- [ ] **Step 5: Verify scaffold**

```bash
moon check
moon test
```

Expected: success (or only missing-test packages OK). Fix import paths until clean.

- [ ] **Step 6: Commit**

```bash
git add moon.mod LICENSE README.mbt.md .gitignore script runtime std_commands render audio host_web cmd
git commit -m "chore: scaffold moonsight MoonBit module and packages"
```

---

### Task 2: Diagnostics, spans, and lexer

**Files:**
- Create: `script/span.mbt`, `script/diag.mbt`, `script/token.mbt`, `script/lexer.mbt`, `script/lexer_test.mbt`
- Modify: remove or keep `script/lib.mbt`

- [ ] **Step 1: Write failing lexer tests**

`script/lexer_test.mbt`:

```mbt
///|
test "lex scene header and dialogue" {
  let src =
    #|- scene "intro"
    #|y:Hello, world!
    #|@wait 1
    #|
  let tokens = @script.lex(src, file="intro.yuki")
  debug_inspect(tokens, content=...) // fill via moon test -u after impl; first assert length/kinds
}
```

Better explicit assertions first:

```mbt
///|
test "lex scene header and dialogue" {
  let src =
    #|- scene "intro"
    #|y:Hello
    #|@wait 1
    #|
  let tokens = lex(src, file="t.yuki")
  assert_true(tokens.length() >= 6)
  // First meaningful tokens: Minus, Ident(scene), String("intro"), ...
  guard tokens[0] is { kind: TokenKind::Minus, .. } else { fail("expected Minus") }
}
```

(Use package-private via black-box: `lex` must be `pub`.)

- [ ] **Step 2: Run test — expect fail**

```bash
moon test script --filter "lex scene*"
```

Expected: fail (lex undefined).

- [ ] **Step 3: Implement span, diag, token, lexer**

`script/span.mbt`:

```mbt
///|
pub(all) struct SourceSpan {
  file : String
  line : Int // 1-based
  col : Int // 1-based
  end_line : Int
  end_col : Int
} derive(Debug, Eq, Show)
```

`script/diag.mbt`:

```mbt
///|
pub(all) enum Severity {
  Error
  Warning
} derive(Debug, Eq, Show)

///|
pub(all) struct Diagnostic {
  severity : Severity
  span : SourceSpan
  message : String
} derive(Debug, Eq, Show)

///|
pub fn Diagnostic::to_cli(self : Diagnostic) -> String {
  "\{self.span.file}:\{self.span.line}:\{self.span.col}: \{self.message}"
}
```

`script/token.mbt`:

```mbt
///|
pub(all) enum TokenKind {
  Minus // leading "-" declaration
  At // "@" command
  Colon
  Ident(String)
  StringLit(String)
  IntLit(Int)
  FloatLit(Double)
  BoolLit(Bool)
  Flag(String) // --force style without value handled as Flag
  Newline
  Eof
  // dialogue-related emitted by line classifier if desired
  DialogueSpeaker(String)
  DialogueText(String)
  Error(String)
} derive(Debug, Eq, Show)

///|
pub(all) struct Token {
  kind : TokenKind
  span : SourceSpan
} derive(Debug, Eq, Show)
```

`script/lexer.mbt` — line-oriented:

```mbt
///|
/// Lex full source into tokens. Line-oriented: each physical line starts fresh.
/// Declaration lines begin with `-`; command lines with `@`; `speaker:text` is dialogue.
pub fn lex(src : String, file~ : String) -> Array[Token] {
  let out : Array[Token] = []
  let lines = src.split("\n")
  for i, line in lines {
    let line_no = i + 1
    lex_line(line, file~, line_no~, out)
    out.push({ kind: TokenKind::Newline, span: span_at(file, line_no, 1) })
  }
  out.push({ kind: TokenKind::Eof, span: span_at(file, lines.length() + 1, 1) })
  out
}

// private helpers: lex_line, span_at, scan_ident, scan_string, scan_number, ...
```

Implement helpers until tests can classify:

- `- scene "intro"` → Minus, Ident("scene"), StringLit("intro")
- `y:Hello` → DialogueSpeaker("y"), DialogueText("Hello")
- `@wait 1` → At, Ident("wait"), IntLit(1)
- `@wait --force` → Flag("force")
- `@foo bar=1` → Ident keys / values as needed (Ident + Ident/Int after `=`)

- [ ] **Step 4: Run tests — expect pass**

```bash
moon test script --filter "lex*"
moon fmt
```

- [ ] **Step 5: Commit**

```bash
git add script
git commit -m "feat(script): add MoonYuki lexer with spans and diagnostics types"
```

---

### Task 3: AST and parser

**Files:**
- Create: `script/ast.mbt`, `script/parser.mbt`, `script/parser_test.mbt`

- [ ] **Step 1: Write failing parser tests**

`script/parser_test.mbt`:

```mbt
///|
test "parse extern macro scene dialogue command" {
  let src =
    #|- extern wait time=1
    #|- macro pause time=1
    #|@wait time
    #|
    #|- scene "intro"
    #|y:Hello [wait --time 1]
    #|@pause 2
    #|
  let unit = parse_source(src, file="t.yuki")
  assert_eq(unit.decls.length(), 3) // extern, macro, scene — adjust to actual model
  // inspect scene body length etc.
  debug_inspect(unit, content=...)
}
```

Prefer structured asserts without fragile full-tree snapshots until AST stabilizes:

```mbt
///|
test "parse scene with dialogue and command" {
  let src =
    #|- scene "intro"
    #|y:Hello
    #|@wait 1
    #|
  let unit = parse_source(src, file="t.yuki")
  guard unit.scenes.length() == 1 else { fail("one scene") }
  assert_eq(unit.scenes[0].name, "intro")
  assert_eq(unit.scenes[0].items.length(), 2)
}
```

- [ ] **Step 2: Run — expect fail**

```bash
moon test script --filter "parse*"
```

- [ ] **Step 3: Implement AST + parser**

`script/ast.mbt` (core shapes):

```mbt
///|
pub(all) struct ScriptUnit {
  file : String
  externs : Array[ExternDecl]
  macros : Array[MacroDecl]
  scenes : Array[SceneDecl]
} derive(Debug, Show)

///|
pub(all) struct ExternDecl {
  name : String
  params : Array[ParamDecl]
  span : SourceSpan
} derive(Debug, Show)

///|
pub(all) struct ParamDecl {
  name : String
  default : Expr? // optional default
} derive(Debug, Show)

///|
pub(all) struct MacroDecl {
  name : String
  params : Array[ParamDecl]
  body : Array[Stmt]
  span : SourceSpan
} derive(Debug, Show)

///|
pub(all) struct SceneDecl {
  name : String
  inherit : String? // inherit "parent"
  items : Array[Stmt]
  span : SourceSpan
} derive(Debug, Show)

///|
pub(all) enum Stmt {
  Command(cmd~ : String, args~ : Array[Arg], span~ : SourceSpan)
  Dialogue(speaker~ : String?, text~ : Array[TextPart], span~ : SourceSpan)
} derive(Debug, Show)

///|
pub(all) enum TextPart {
  Literal(String)
  InlineCommand(cmd~ : String, args~ : Array[Arg])
} derive(Debug, Show)

///|
pub(all) enum Arg {
  Positional(Expr)
  Named(name~ : String, Expr)
  Flag(String)
} derive(Debug, Show)

///|
pub(all) enum Expr {
  Int(Int)
  Float(Double)
  Bool(Bool)
  Str(String)
  Ident(String)
} derive(Debug, Show)
```

`script/parser.mbt`:

```mbt
///|
pub fn parse_source(src : String, file~ : String) -> ScriptUnit raise ParseError {
  let tokens = lex(src, file~)
  parse_tokens(tokens, file~)
}

///|
pub(all) suberror ParseError {
  ParseError(span~ : SourceSpan, message~ : String)
} derive(Debug, Show, Eq)
```

Parser walks tokens line-by-line (groups between Newline). On error, raise `ParseError` with span.

- [ ] **Step 4: Tests pass**

```bash
moon test script --filter "parse*"
```

- [ ] **Step 5: Commit**

```bash
git add script
git commit -m "feat(script): parse MoonYuki into AST"
```

---

### Task 4: Macro expansion and name resolution

**Files:**
- Create: `script/macro.mbt`, `script/resolve.mbt`, `script/macro_test.mbt`, `script/resolve_test.mbt`

- [ ] **Step 1: Failing macro test**

```mbt
///|
test "expand pause macro into wait command" {
  let src =
    #|- extern wait time=1
    #|- macro pause time=1
    #|@wait time
    #|
    #|- scene "s"
    #|@pause 3
    #|
  let unit = parse_source(src, file="t.yuki")
  let expanded = expand_macros(unit)
  // scene should contain @wait with time=3
  guard expanded.scenes[0].items is [Stmt::Command(cmd="wait", args~, ..), ..] else {
    fail("expected wait command")
  }
  // assert args encode time 3
}
```

- [ ] **Step 2: Failing resolve test**

```mbt
///|
test "resolve rejects unknown command" {
  let src =
    #|- scene "s"
    #|@no_such 1
    #|
  let unit = expand_macros(parse_source(src, file="t.yuki"))
  try resolve_unit(unit, builtin_externs()) catch {
    ResolveError::UnknownCommand(name~, ..) => assert_eq(name, "no_such")
  } noraise { _ => fail("expected UnknownCommand") }
}
```

- [ ] **Step 3: Implement expand + resolve**

`expand_macros`: recursively replace `Command` whose name matches a macro with body, substituting params (positional bind by order; named by key). Detect recursive macros with a depth limit (e.g. 64) and error.

`resolve_unit`:

- Build map of externs (file + `builtin_externs()`)
- Ensure scene names unique
- Ensure commands refer to extern or remaining macro (after expand, only externs)
- Resolve `inherit` scene names
- Return `ResolvedUnit` (same shape + tables)

```mbt
///|
pub fn builtin_externs() -> Array[ExternDecl] {
  // Minimal stubs for compile path; full semantics live in std_commands.
  // text.begin, text.type, text.end, flow.jump, flow.yield, flow.choice,
  // layer.show, layer.hide, trans.fade, var.set, audio.bgm, audio.se, ...
  ...
}
```

- [ ] **Step 4: Tests pass + commit**

```bash
moon test script --filter "expand*|resolve*"
git add script
git commit -m "feat(script): macro expansion and command resolution"
```

---

### Task 5: IR, dialogue lowering, bytecode

**Files:**
- Create: `script/ir.mbt`, `script/lower.mbt`, `script/bytecode.mbt`, `script/compile.mbt`
- Create: `script/lower_test.mbt`, `script/bytecode_test.mbt`, `script/compile_test.mbt`

- [ ] **Step 1: Define IR**

`script/ir.mbt`:

```mbt
///|
pub(all) enum IrOp {
  Nop
  Host(name~ : String, args~ : Array[IrValue])
  Jump(label~ : Int)
  JumpIf(cond~ : IrValue, label~ : Int)
  JumpIfNot(cond~ : IrValue, label~ : Int)
  Label(Int) // stripped when linearizing
  Yield // wait for Advance intent
  Choose(options~ : Array[String], result_var~ : String)
  Return
} derive(Debug, Show, Eq)

///|
pub(all) enum IrValue {
  Int(Int)
  Float(Double)
  Bool(Bool)
  Str(String)
  Var(String)
  None_
} derive(Debug, Show, Eq)

///|
pub(all) struct IrModule {
  scenes : Map[String, IrScene]
  entry : String // default "entrypoint" or first scene
} derive(Debug, Show)

///|
pub(all) struct IrScene {
  name : String
  ops : Array[IrOp]
} derive(Debug, Show)
```

- [ ] **Step 2: Failing lower test for dialogue**

```mbt
///|
test "lower dialogue to text host ops and yield" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|
  let ir = compile_to_ir(src, file="t.yuki")
  let ops = ir.scenes["s"].ops
  // Expect Host text.begin speaker=y, Host text.type "Hi", Host text.end, Yield
  debug_inspect(ops, content=...)
}
```

Use explicit checks:

```mbt
  assert_true(ops.length() >= 4)
  guard ops[0] is IrOp::Host(name="text.begin", ..) else { fail("text.begin") }
```

- [ ] **Step 3: Implement lower + compile_to_ir**

Dialogue →:

1. `Host("text.begin", [speaker])`
2. For each `TextPart::Literal` → `Host("text.type", [str])`
3. For each inline command → `Host(...)` or expand already done
4. `Host("text.end", [])`
5. `Yield`

`@flow.jump "other"` → `Host("flow.jump", ...)` or dedicated jump if scene-local labels used.

Scene entry: compile each scene separately; `flow.jump` host uses scene name string.

- [ ] **Step 4: Bytecode encode/decode round-trip test**

```mbt
///|
test "bytecode roundtrip" {
  let ir = compile_to_ir(minimal_src(), file="t.yuki")
  let bytes = encode_module(ir)
  let ir2 = decode_module(bytes)
  debug_inspect(ir2.entry, content=ir.entry)
  assert_eq(ir2.scenes.length(), ir.scenes.length())
}
```

`.msb` v1 layout (little-endian):

```
magic: b"MSB1"
u32 version = 1
u32 scene_count
for each scene:
  u32 name_len + utf8 name
  u32 op_count
  for each op: u8 opcode + payload
string table optional; Phase 1 may inline strings per op
```

Opcodes (fixed):

| code | op |
|------|-----|
| 0 | Nop |
| 1 | Host |
| 2 | Jump |
| 3 | JumpIf |
| 4 | JumpIfNot |
| 5 | Yield |
| 6 | Choose |
| 7 | Return |

- [ ] **Step 5: Public compile API**

`script/compile.mbt`:

```mbt
///|
pub(all) struct CompileResult {
  ir : IrModule
  bytecode : Bytes
  diags : Array[Diagnostic]
}

///|
pub fn compile_source(src : String, file~ : String) -> CompileResult raise CompileError {
  let unit = parse_source(src, file~)
  let expanded = expand_macros(unit)
  let resolved = resolve_unit(expanded, builtin_externs())
  let ir = lower_unit(resolved)
  let bytecode = encode_module(ir)
  { ir, bytecode, diags: [] }
}
```

- [ ] **Step 6: Tests pass + commit**

```bash
moon test script
git add script
git commit -m "feat(script): lower MoonYuki to IR and MSB1 bytecode"
```

---

### Task 6: Stage, values, and intents

**Files:**
- Create: `runtime/value.mbt`, `runtime/stage.mbt`, `runtime/intent.mbt`, `runtime/stage_test.mbt`

- [ ] **Step 1: Failing stage test**

```mbt
///|
test "layer show updates stage snapshot fields" {
  let st = Stage::new()
  st.show_layer(id="bg", layer=LayerKind::Background, resource="bg_room", z=0)
  assert_eq(st.layers.length(), 1)
  assert_eq(st.layers[0].resource, "bg_room")
}
```

- [ ] **Step 2: Implement types**

`runtime/value.mbt`:

```mbt
///|
pub(all) enum Value {
  Int(Int)
  Float(Double)
  Bool(Bool)
  Str(String)
  None_
} derive(Debug, Eq, Show)

///|
pub fn Value::truthy(self : Value) -> Bool {
  match self {
    Bool(b) => b
    Int(0) => false
    None_ => false
    Str("") => false
    _ => true
  }
}
```

`runtime/stage.mbt`:

```mbt
///|
pub(all) enum LayerKind {
  Background
  Character
  Effect
  UI
  Overlay
} derive(Debug, Eq, Show)

///|
pub(all) struct LayerState {
  id : String
  kind : LayerKind
  resource : String
  z : Int
  x : Double
  y : Double
  opacity : Double
  visible : Bool
} derive(Debug, Show)

///|
pub(all) struct TextBlock {
  speaker : String?
  full_text : String
  visible_chars : Int
  complete : Bool
} derive(Debug, Show)

///|
pub(all) struct ChoiceState {
  options : Array[String]
  selected : Int? // filled when user picks
} derive(Debug, Show)

///|
pub(all) struct Stage {
  mut layers : Array[LayerState]
  mut text : TextBlock?
  mut choices : ChoiceState?
  mut vars : Map[String, Value]
  mut scene : String
  mut overlay_opacity : Double
} derive(Debug)

///|
pub fn Stage::new() -> Stage {
  {
    layers: [],
    text: None,
    choices: None,
    vars: {},
    scene: "",
    overlay_opacity: 0.0,
  }
}

// methods: show_layer, hide_layer, set_var, get_var, begin_text, type_more, complete_text, set_choices, clear_choices, snapshot_layers...
```

`runtime/intent.mbt`:

```mbt
///|
pub(all) enum Intent {
  None_
  Advance
  Select(Int)
  SkipTyping
  OpenMenu
  ToggleAuto
} derive(Debug, Eq, Show)
```

- [ ] **Step 3: Tests pass + commit**

```bash
moon test runtime --filter "layer*"
git add runtime
git commit -m "feat(runtime): Stage, values, and input intents"
```

---

### Task 7: VM + Director with mock host

**Files:**
- Create: `runtime/host.mbt`, `runtime/director.mbt`, `runtime/vm.mbt`, `runtime/vm_test.mbt`, `runtime/director_test.mbt`

- [ ] **Step 1: Host protocol**

```mbt
///|
pub(all) struct HostCall {
  name : String
  args : Array[Value]
} derive(Debug, Show)

///|
/// Result of a host call.
pub(all) enum HostResult {
  Ok
  Yield // host requests VM yield (e.g. after text.end)
  Error(String)
} derive(Debug, Show)

///|
/// Register map: name -> handler function pointer style via enum dispatch in Director.
pub typealias HostFn = (Stage, Array[Value]) -> HostResult
```

MoonBit may not have function types in maps easily depending on version — use:

```mbt
pub(all) enum BuiltinHost {
  TextBegin
  TextType
  TextEnd
  LayerShow
  // ...
}

pub fn dispatch_builtin(op : String, stage : Stage, args : Array[Value]) -> HostResult
```

For extensibility, `Director` holds `Map[String, HostHandler]` where:

```mbt
pub(all) enum HostHandler {
  Builtin(BuiltinHost)
  // later: plugin id
}
```

- [ ] **Step 2: Failing VM test (no GPU)**

```mbt
///|
test "vm runs dialogue then yields; advance continues" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|y:There
    #|
  let ir = @script.compile_to_ir(src, file="t.yuki")
  let eng = Engine::from_ir(ir, entry="s")
  // first tick without intent should show first line and hang on Yield
  eng.tick(Intent::None_)
  guard eng.stage.text is Some(t) else { fail("text") }
  assert_eq(t.full_text, "Hi")
  eng.tick(Intent::Advance) // complete / next
  eng.tick(Intent::Advance)
  guard eng.stage.text is Some(t2) else { fail("second") }
  assert_eq(t2.full_text, "There")
}
```

(Adjust Advance semantics: first Advance completes typing if incomplete; second advances to next yield.)

- [ ] **Step 3: Implement VM**

`runtime/vm.mbt` state:

```mbt
pub(all) struct Vm {
  module : @script.IrModule // or decoded bytecode ops
  mut ip : Int
  mut scene : String
  mut stack : Array[Value] // if needed
  mut halted : Bool
  mut wait : WaitKind
}

pub(all) enum WaitKind {
  Running
  Yield
  Choose
  Halted
}
```

Execution loop:

```mbt
pub fn Vm::run_until_wait(self : Vm, director : Director, stage : Stage, budget~ : Int = 10000) -> Unit {
  for _ in 0..<budget {
    if self.wait is (Yield | Choose | Halted) {
      break
    }
    // fetch op at ip, match Host/Jump/Yield/Choose/...
  }
}
```

- [ ] **Step 4: Director implements text/layer/var minimum**

Enough for tests; full table lands in Task 8.

- [ ] **Step 5: Tests pass + commit**

```bash
moon test runtime
git add runtime
git commit -m "feat(runtime): IR VM and Director host dispatch"
```

---

### Task 8: Standard host commands package

**Files:**
- Create: `std_commands/*.mbt`, `std_commands/registry_test.mbt`
- Modify: `runtime` Director to load registry from `std_commands`

- [ ] **Step 1: Tests for each command group**

```mbt
///|
test "layer.show and trans.fade mutate stage" {
  let stage = Stage::new()
  let reg = standard_registry()
  assert_eq(reg.call("layer.show", stage, [Value::Str("bg"), Value::Str("bg_room")]), HostResult::Ok)
  assert_eq(stage.layers.length(), 1)
  ignore(reg.call("trans.fade", stage, [Value::Float(0.0), Value::Float(1.0), Value::Float(0.3)]))
  // overlay_opacity animation may be target-based; store fade target on stage
}
```

- [ ] **Step 2: Implement registry**

Map string names used by lowered IR (`text.begin`, `text.type`, `text.end`, `layer.show`, `layer.hide`, `layer.move`, `flow.jump`, `flow.wait`, `var.set`, `var.get` via values, `audio.bgm`, `audio.se`, `trans.fade`, `sys.save_hint`).

`flow.jump` should return a structured signal — either:

```mbt
pub(all) enum HostResult {
  Ok
  Yield
  JumpScene(String)
  Error(String)
}
```

VM handles `JumpScene` by switching `IrScene` and resetting `ip`.

- [ ] **Step 3: Align `script.builtin_externs` names exactly with registry keys**

Add compile test that every lowered host name exists in registry (string list equality test).

- [ ] **Step 4: Commit**

```bash
moon test std_commands
moon test runtime
git add std_commands runtime script
git commit -m "feat(std_commands): register standard VN host commands"
```

---

### Task 9: Save / load

**Files:**
- Create: `runtime/save.mbt`, `runtime/save_test.mbt`
- Modify: `runtime/engine.mbt` if needed

- [ ] **Step 1: Failing round-trip test**

```mbt
///|
test "save roundtrip restores scene ip vars and layers" {
  let eng = load_min_demo_engine()
  eng.tick(Intent::Advance)
  eng.stage.set_var("met_y", Value::Bool(true))
  let blob = eng.save(slot=0)
  let eng2 = load_min_demo_engine()
  eng2.load(blob)
  assert_eq(eng2.vm.scene, eng.vm.scene)
  assert_eq(eng2.vm.ip, eng.vm.ip)
  assert_eq(eng2.stage.get_var("met_y"), Value::Bool(true))
  assert_eq(eng2.stage.layers.length(), eng.stage.layers.length())
}
```

- [ ] **Step 2: Save format**

JSON via `moonbitlang/core/json` (human-debuggable Phase 1):

```mbt
pub(all) struct SaveGame {
  format_version : Int // 1
  module_id : String
  scene : String
  ip : Int
  call_stack : Array[StackFrame]
  vars : Map[String, Value]
  layers : Array[LayerState]
  text : TextBlock?
  overlay_opacity : Double
  audio : AudioLogicState // from audio package or mirrored fields
} derive(ToJson)
```

Reject `format_version != 1` with clear error.

- [ ] **Step 3: Commit**

```bash
moon test runtime --filter "save*"
git add runtime
git commit -m "feat(runtime): JSON save/load with version field"
```

---

### Task 10: Engine frame loop (headless)

**Files:**
- Create: `runtime/engine.mbt`, `runtime/engine_test.mbt`

- [ ] **Step 1: Engine API**

```mbt
///|
pub(all) struct Engine {
  vm : Vm
  director : Director
  stage : Stage
  mut auto : Bool
  // audio mixer handle optional
}

///|
pub fn Engine::tick(self : Engine, intent : Intent) -> Unit {
  // 1. apply intent to wait state (complete text / choose / resume yield)
  // 2. vm.run_until_wait
  // 3. tick transitions (fade overlay toward target)
}

///|
pub fn Engine::view(self : Engine) -> StageView {
  StageView::from_stage(self.stage)
}
```

`StageView` is the immutable snapshot DTO for render.

- [ ] **Step 2: Choice test**

```mbt
///|
test "choice selects branch" {
  let src =
    #|- scene "s"
    #|@flow.choice result="c" "Yes" "No"
    #|// lower Choose op with options
    #|
  // After compile, tick until Choose, Select(0), assert var c == 0
}
```

Ensure lower supports choice syntax decided here:

```
@flow.choice "Yes" "No" --result c
```

→ `IrOp::Choose(options=["Yes","No"], result_var="c")`

- [ ] **Step 3: Commit**

```bash
moon test runtime
git add runtime script
git commit -m "feat(runtime): engine tick loop with choices and transitions"
```

---

### Task 11: Render snapshot, text layout, glyph atlas (logic)

**Files:**
- Create: `render/types.mbt`, `render/snapshot.mbt`, `render/text_layout.mbt`, `render/glyph_atlas.mbt`, `render/snapshot_test.mbt`, `render/text_layout_test.mbt`

- [ ] **Step 1: Draw list types**

```mbt
///|
pub(all) struct Color {
  r : Float
  g : Float
  b : Float
  a : Float
} derive(Debug, Show)

///|
pub(all) struct SpriteDraw {
  resource : String
  x : Float
  y : Float
  w : Float
  h : Float
  opacity : Float
  z : Int
} derive(Debug, Show)

///|
pub(all) struct GlyphDraw {
  atlas_x : Int
  atlas_y : Int
  atlas_w : Int
  atlas_h : Int
  x : Float
  y : Float
  color : Color
} derive(Debug, Show)

///|
pub(all) struct DrawList {
  sprites : Array[SpriteDraw]
  glyphs : Array[GlyphDraw]
  veil_opacity : Float
} derive(Debug, Show)
```

- [ ] **Step 2: Stage → DrawList (no GPU)**

```mbt
///|
pub fn build_draw_list(view : @runtime.StageView, layout : UiLayout) -> DrawList
```

Dialogue box: fixed UI rect bottom 30% of 1920×1080; nameplate; text origin inside box.

- [ ] **Step 3: Text layout tests**

```mbt
///|
test "layout wraps long line" {
  let runs = layout_text("Hello world from MoonSight", max_width=100.0, font_size=24.0, measure=fixed_width_measure(12.0))
  assert_true(runs.length() >= 2)
}
```

`fixed_width_measure` for tests; real host provides font metrics later.

- [ ] **Step 4: Glyph atlas logic**

```mbt
///|
pub(all) struct GlyphAtlas {
  width : Int
  height : Int
  // map codepoint+size -> rect; CPU bitmap owned by JS side in browser
  mut entries : Map[Int, AtlasEntry]
}

///|
pub fn GlyphAtlas::get_or_queue(self : GlyphAtlas, ch : Char, size : Int) -> AtlasEntry
```

Phase 1 browser path: JS rasterizes missing glyphs into a canvas and uploads texture; MoonBit only stores UV rects. Define extern later in Task 12.

- [ ] **Step 5: Commit**

```bash
moon test render
git add render
git commit -m "feat(render): draw list, text layout, glyph atlas bookkeeping"
```

---

### Task 12: WebGPU JS bridge + MoonBit GPU externs

**Files:**
- Create: `host_web/js_glue/index.html`, `host_web/js_glue/boot.js`, `host_web/js_glue/webgpu_bridge.js`
- Create: `render/gpu.mbt`, `render/sprite_batch.mbt`, `render/renderer.mbt`
- Modify: `host_web/main.mbt`, `host_web/moon.pkg` link options for wasm-gc

- [ ] **Step 1: JS bridge API (stable)**

`webgpu_bridge.js` exports on `globalThis.MoonSightGpu`:

```js
export async function init(canvas) { /* requestAdapter, device, context */ }
export function resize(w, h) { /* configure context */ }
export function uploadRgbaTexture(id, width, height, rgbaUint8) { ... }
export function uploadPngUrl(id, url) { /* createImageBitmap → texture */ }
export function beginFrame() { ... }
export function drawSprites(spriteBuffer) { /* interleaved floats */ }
export function drawGlyphs(glyphBuffer, atlasTextureId) { ... }
export function drawVeil(opacity) { ... }
export function endFrame() { /* submit */ }
```

Keep WGSL shaders inline in JS for Phase 1 (two pipelines: textured quad, solid veil).

- [ ] **Step 2: MoonBit externs**

`render/gpu.mbt` (wasm-gc / JS backend):

```mbt
///|
pub fn gpu_init() -> Unit = "MoonSightGpu" "initFromMoon"
// exact extern syntax per MoonBit JS interop docs for current toolchain —
// implementers must verify with `moon ide doc` / MoonBit JS FFI guide and adjust.
```

If pure MoonBit extern is awkward, pattern:

1. MoonBit exports `frame(dt)` / `on_pointer` via wasm exports
2. JS owns GPU; MoonBit only produces packed `FixedArray[Float]` draw data
3. `host_web` calls `engine.tick` + `build_draw_list` + passes arrays to JS

**Preferred Phase 1 pattern (simpler, fewer FFI hazards):**

```mbt
///| MoonBit side
pub fn export_frame(intent_code : Int) -> FixedArray[Float] {
  // tick engine, build draw list, pack sprites into float array
}
```

JS:

```js
const floats = instance.exports.export_frame(intent);
MoonSightGpu.drawSprites(floats);
```

Document packing format in `docs/host-commands.md` or `docs/draw-list-pack.md`:

```
// Sprite pack: [count, x,y,w,h,opacity, resId, z,  ...]
// Glyph pack: similar
// Trailer: veil_opacity
```

- [ ] **Step 3: index.html + boot.js**

- Full window canvas
- pointer/keyboard → intent codes
- game loop `requestAnimationFrame`
- load `.msb` + manifest via fetch
- localStorage save keys `moonsight/save/{slot}`

- [ ] **Step 4: Manual smoke (document in README)**

```bash
moon build --target wasm-gc -C host_web   # or module-level build
# serve host_web/js_glue with wasm artifact copied in
```

Expected: clear color / placeholder sprite; no panic.

- [ ] **Step 5: Commit**

```bash
git add host_web render docs
git commit -m "feat(host_web): WebGPU JS bridge and frame export packing"
```

---

### Task 13: Audio mixer + web backend

**Files:**
- Create: `audio/mixer.mbt`, `audio/backend.mbt`, `audio/mixer_test.mbt`
- Modify: `std_commands/audio_cmd.mbt`, `host_web/js_glue/boot.js`

- [ ] **Step 1: Logical mixer tests**

```mbt
///|
test "bgm play and stop update logical state" {
  let m = Mixer::new()
  m.play_bgm("bgm_soft", loop~=true, volume=0.8)
  assert_eq(m.bgm, Some("bgm_soft"))
  m.stop_bgm()
  assert_eq(m.bgm, None)
}
```

- [ ] **Step 2: Wire audio.* hosts to mixer; JS plays URLs from resource table**

- [ ] **Step 3: Commit**

```bash
git add audio std_commands host_web
git commit -m "feat(audio): logical mixer and web audio hooks"
```

---

### Task 14: moonsightc CLI

**Files:**
- Modify: `cmd/moonsightc/main.mbt`
- Create: tests via native run / small golden files under `script/testdata/`

- [ ] **Step 1: CLI behavior**

```
moonsightc check <file.yuki|dir>
moonsightc build <project_dir> -o <out_dir>
moonsightc version
```

`build`:

1. Read `moonsight.toml` (simple key format or JSON)
2. Compile all `.yuki` into one `IrModule` / `.msb`
3. Copy assets + write `manifest.json` (resource id → path)
4. Copy wasm + js_glue into out_dir

`moonsight.toml` Phase 1:

```toml
name = "demo"
entry = "main.yuki"
logical_width = 1920
logical_height = 1080
```

If TOML parser unavailable in MoonBit std, use JSON `moonsight.json` instead — **pin JSON** to avoid extra deps:

```json
{
  "name": "demo",
  "entry": "main.yuki",
  "logical_width": 1920,
  "logical_height": 1080
}
```

- [ ] **Step 2: Implement argv parsing manually (no heavy framework)**

```mbt
fn main raise {
  let args = /* get cli args via moonbitlang/x/sys on native */
  match args {
    ["version", ..] => println("moonsightc 0.1.0")
    ["check", path, ..] => cmd_check(path)
    ["build", path, ..] => cmd_build(path, out_dir_from(args))
    _ => println("usage: moonsightc <check|build|version> ...")
  }
}
```

- [ ] **Step 3: Manual verify**

```bash
moon run cmd/moonsightc --target native -- version
moon run cmd/moonsightc --target native -- check demo/game/main.yuki
```

- [ ] **Step 4: Commit**

```bash
git add cmd/moonsightc
git commit -m "feat(moonsightc): check and build commands"
```

---

### Task 15: Demo game content

**Files:**
- Create: `demo/game/moonsight.json`, `demo/game/main.yuki`, `demo/game/scenes/intro.yuki`, placeholder assets

- [ ] **Step 1: Write demo script**

`main.yuki`:

```
- extern text.begin speaker
- extern text.type text
- extern text.end
- extern layer.show id res
- extern layer.hide id
- extern flow.jump target
- extern flow.choice 
- extern var.set name value
- extern audio.bgm res
- extern trans.fade to time
# (or rely on builtins without repeating — if builtins implicit, skip)

- scene "entrypoint"
@flow.jump "intro"

- scene "intro"
@layer.show "bg" "bg_room"
@audio.bgm "bgm_soft"
@trans.fade 0 0.5
y:Welcome to MoonSight.
y:This demo uses MoonYuki.
@flow.choice "Talk" "Leave" --result act
# branch via JumpIf on var act — may need @flow.jump_if helpers
```

Include at least: multi-scene, dialogue, choice, variable branch, bg+character, fade, bgm, and a save hint command.

- [ ] **Step 2: Placeholder PNG assets**

Generate solid-color PNGs with a tiny script or checked-in minimal PNGs (1×1 scaled in engine is OK for CI; demo can use larger later).

- [ ] **Step 3: Build and play**

```bash
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
# serve dist/demo && open browser
```

- [ ] **Step 4: Commit**

```bash
git add demo
git commit -m "feat(demo): sample MoonYuki game exercising Phase 1 features"
```

---

### Task 16: Desktop shell (Tauri minimal)

**Files:**
- Create: `host_desktop/README.md`, `host_desktop/tauri/*` minimal

- [ ] **Step 1: Scaffold Tauri 2 app** that loads `dist/demo` as static assets (or `http://localhost` in dev)

- [ ] **Step 2: Map save path to app data dir via Tauri plugin if localStorage insufficient — Phase 1 may keep localStorage inside webview**

- [ ] **Step 3: Document**

```bash
# build web dist, then
cd host_desktop/tauri && npm install && npm run tauri dev
```

- [ ] **Step 4: Commit**

```bash
git add host_desktop
git commit -m "feat(host_desktop): minimal Tauri shell for web build"
```

---

### Task 17: Documentation + CI smoke

**Files:**
- Create: `docs/moon-yuki-subset.md`, `docs/host-commands.md`, `docs/project-layout.md`, `.github/workflows/ci.yml` (optional if GH used)
- Modify: `README.mbt.md`

- [ ] **Step 1: Write docs matching implemented syntax and command table**

Include:

- Grammar subset with examples
- Every host command: args, effect, errors
- Project layout and `moonsight.json`
- Intent mapping (click, space, 1-9 choices)
- Draw-list pack format

- [ ] **Step 2: README quickstart**

```bash
moon test
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
```

- [ ] **Step 3: CI script**

```yaml
# .github/workflows/ci.yml
# on push: install moon, moon check, moon test
```

- [ ] **Step 4: Final verification against spec success criteria**

Checklist:

1. Demo compiles with moonsightc  
2. Browser plays through choice + branch  
3. Save/load survives refresh  
4. Desktop shell loads same dist  
5. Docs present  
6. `moon test` green  

- [ ] **Step 5: Commit**

```bash
git add docs README.mbt.md .github
git commit -m "docs: MoonYuki subset, host commands, project layout"
```

---

## Spec coverage self-check

| Spec requirement | Task(s) |
|------------------|---------|
| MoonYuki parse/type/IR/bytecode | 2–5 |
| VM + Director + Stage + layers | 6–8, 10 |
| WebGPU full composition + text | 11–12 |
| Dialogue typing, choices, vars, jumps | 5, 7–8, 10, 15 |
| BGM/SE | 13, 15 |
| Save/load | 9 |
| Standard host table + docs | 8, 17 |
| Browser host | 12 |
| Desktop shell | 16 |
| Demo | 15 |
| CLI | 14 |
| Core tests | all packages |
| No editor/i18n/achievements/Live2D | out of scope |

## Placeholder / consistency notes

- Host result includes `JumpScene` so flow control stays in VM.  
- Project manifest pinned to **JSON** (`moonsight.json`) for zero extra deps.  
- GPU: MoonBit exports packed frames; JS owns WebGPU (reduces FFI risk).  
- Extern string names in `script.builtin_externs` must match `std_commands` keys exactly — enforced by test in Task 8.  
- Logical resolution 1920×1080 throughout layout helpers.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-10-moonsight-runtime-kernel.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks  
2. **Inline Execution** — execute tasks in this session with executing-plans and checkpoints  

Which approach?
