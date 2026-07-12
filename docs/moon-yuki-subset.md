# MoonYuki subset (Phase 1–4)

MoonYuki is a line-oriented visual-novel DSL compiled by the `script` package
into IR and deterministic MSB2 executable/catalog bundles. **UI is not authored in MoonYuki** (Phase 4: MoonBit
`std_ui` / `ui_package` — see [`ui-moonbit.md`](./ui-moonbit.md)). This document
describes **the subset that is implemented and exercised by tests and the demo**.

Formal 1.0 adds author-owned stable presentation IDs, complete locale catalogs,
MSB2 packaging, save v5, and rollback/effect contracts. The canonical explicit-ID
grammar and migration output are owned by `moonsightc`; see
[`formal-1.0-author-guide.md`](./formal-1.0-author-guide.md).

Still out of scope: visual editor, achievements, Live2D / 3D, full timeline /
animation queues, blocking presentation DSL, official YukimiScript bytecode
compatibility, slot screenshots, DOM menus, and project `- screen` / Screen DSL.

## Phase notes

### Phase 2 — presentation

| Feature | Notes |
|---------|--------|
| Named host args | `kind=background`, `duration=0.5`, `opacity=1.0` preserved through lower (`#:name` markers) |
| `layer` kinds | `background` / `character` / `effect` / `ui`; default **`character`** |
| Property tweens | `x` / `y` / `opacity` + `duration`; linear; fire-and-forget |
| `layer.set` | Change props without rebinding resource; errors if id missing |
| `flow.wait` | Real wall-clock timing; Advance ignored during timed wait |
| `trans.fade` | Wall-clock `fade_remaining`; pair with `@flow.wait` to pause script |
| Save | Writers emit **v5**; readers accept v2-v5; v5 persists stable presentation identity and dissolve continuation |

Bare keywords work for string-valued named args after resolve/lower
(`kind=background` or `kind="background"`). Prefer bare for kinds/enums in demos.

### Phase 3 — system UI + D+B (historical in yuki)

| Feature | Notes |
|---------|--------|
| Multi-slot + prefs | Save slots + prefs keys; UI chrome was Screen DSL (removed in Phase 4) |
| `@ui.show` / `@ui.hide` | Narrative bridge to modal stack (**kept** in Phase 4) |
| Named negatives | `x=-200`, `y=-1.5` lexed correctly |
| Audio | `@audio.bgm` `volume=` / `fade=`; hard-fail missing audio at build/load |

### Phase 4 — MoonBit UI (not MoonYuki)

| Feature | Notes |
|---------|--------|
| UI authoring | `std_ui` + optional project `ui_package` (MoonBit); see [`ui-moonbit.md`](./ui-moonbit.md) |
| `- screen` | **Rejected** at parse with migration message → `docs/ui-moonbit.md` |
| `@ui.show` / `@ui.hide` | Still map to modal show/hide on `UiRuntime` |
| `screens.json` | No longer a dist primary artifact |

## File shape

A compilation unit (one `.yuki` file) may contain, in any order at top level:

| Construct | Form |
|-----------|------|
| Comment | `# …` (full-line; `#` after content is not a mid-line comment) |
| Extern | `- extern name [params…]` |
| Macro | `- macro name [params…]` then body lines ending at next top-level decl |
| Scene | `- scene "name"` or `- scene "name" inherit "parent"` |
| ~~Screen~~ | **Removed** — `- screen` is a compile error |

Scene bodies contain:

- Dialogue lines: `speaker:text…` (speaker is an identifier; text may include inline commands)
- Host / macro commands: `@cmd args…`
- Blank lines (ignored)

Top-level `@` commands outside a scene/macro body are a **parse error**.

### Multi-file projects

`moonsightc build` collects every `*.yuki` under the project directory, compiles
each independently, and **merges scenes** into one IR module / `game.msb`.

- Scene names must be unique across the merged set (duplicate = error).
- Macros and file-local `extern`s do **not** cross files.
- Entry scene preference: a scene named `"entrypoint"` if present, else the
  first scene of the **entry file** graph; the demo uses `entrypoint` → jumps
  after title **Start** (`start_game` from UI Capabilities).

Optional project UI is linked via `moonsight.json` `ui_package` into host wasm
(not via `.yuki`). The browser host still loads **entry source** as `demo.yuki`;
`game.msb` is the narrative publish artifact.

## Grammar sketch

```
unit        ::= item*
item        ::= extern | macro | scene | comment | blank

extern      ::= "- extern" name param*
param       ::= name | name "=" literal

macro       ::= "- macro" name param* body_line*
body_line   ::= command | dialogue | blank   (until next top-level "- …")

scene       ::= "- scene" string ("inherit" string)? scene_line*
scene_line  ::= command | dialogue | blank | comment

# "- screen" is a hard error (Phase 4); UI lives in MoonBit packages

command     ::= "@" dotted_name arg*
dialogue    ::= speaker ":" text_parts
text_parts  ::= (literal | inline)*
inline      ::= "[" dotted_name arg* "]"

arg         ::= positional | named | flag
positional  ::= literal | ident
named       ::= name "=" (literal | ident)   # literals may be negative: x=-200
flag        ::= "--" name

literal     ::= int | float | bool | string
string      ::= '"' … '"'
bool        ::= true | false
dotted_name ::= ident ("." ident)*
```

### Argument forms

```yuki
@flow.wait 1.0                              # positional number
@var.set "flag" true                        # positional string + bool
@layer.show "y" "char_y" 10                 # id, resource, optional z (legacy)
@layer.show "bg" "bg_room" kind=background  # named kind (Phase 2)
@layer.set "y" x=200 opacity=1.0 duration=0.5
@foo bar=1 --force                          # named + flag
@flow.choice "Talk" "Leave" --result act
@flow.choice result="c" "Yes" "No"
```

Named args lower to IR as pairs: `Str("#:<name>")` then the value. Flags stay
single string tokens without the `#:` prefix. Scripts must not use `#:…` as a
normal string literal (reserved marker prefix).

Values:

| Kind | Examples |
|------|----------|
| Int | `0`, `10`, `-1` |
| Float | `1.0`, `0.5` |
| Bool | `true`, `false` |
| String | `"intro"`, `"bg_room"` |
| Ident | `act`, `time`, `background` (macro params, choice results, bare keywords) |

## Dialogue

```yuki
- scene "intro"
y:Hello.
yuki:Welcome to MoonSight.
```

Lowering expands dialogue to the host sequence:

1. `text.begin [speaker]`
2. `text.type` for each text chunk (inline commands interleave as Host ops)
3. `text.end`
4. `Yield` (wait for Advance)

### Inline commands

```yuki
y:Hello [wait --time 1]
```

Parsed as `Literal("Hello ")` + `InlineCommand(wait, …)`. The command name
must resolve to a known `extern` (file or builtin). The demo does not rely
on rich inline markup.

## Extern and macro

```yuki
- extern wait time=1
- macro pause time=1
@wait time

- scene "s"
@pause 2
```

- **extern** declares a host command signature for resolve (runtime handlers
  live in `std_commands` / `Director`).
- **macro** expands to body statements before resolve.
- Standard host names are **pre-registered** as builtins (`script.builtin_externs`);
  scripts do not need `- extern` for `@layer.show`, `@layer.set`, `@flow.jump`, etc.

## Scenes and inheritance

```yuki
- scene "parent"
@text.begin

- scene "child" inherit "parent"
@text.end
```

- `inherit "parent"` records a parent name; the parent must exist in the unit
  (resolve error if missing).
- Resolve validates the link; **runtime inheritance merge of stage state is
  minimal** — treat parent mainly as a structural/authoring hint unless a later
  phase expands it.

Preferred entry:

```yuki
- scene "entrypoint"
@flow.jump "intro"
```

## Flow control (script level)

| Feature | Status |
|---------|--------|
| `@flow.jump "scene"` | Implemented (host → `JumpScene`) |
| `@flow.yield` | Implemented |
| `@flow.wait [time]` | Implemented — real wall-clock when `time > 0`; bare waits for Advance |
| `@flow.choice …` | Implemented → IR `Choose` |
| Conditional jump / JumpIf | `@flow.jump_if` / `@flow.jump_if_not` → IR `JumpIf`/`JumpIfNot` |
| `@menu` sugar | Not implemented; use `@flow.choice` |

### Choice

```yuki
@flow.choice "Talk" "Leave" --result act
@var.set "demo_choice" act
@flow.jump_if act 0 "talk"
@flow.jump "leave"
```

- Positional strings/idents are option labels (0-based index on select).
- Result variable: `--result name`, `result=name`, or `result="name"`.
  Default result var is `"_"`.
- On select, the VM stores an **Int** option index in that variable and resumes.
- Branch with `@flow.jump_if <var> <value> "scene"` (equality) or
  `@flow.jump_if <cond> "scene"` (truthy). `_not` inverts the condition.

### Wait and presentation sync

```yuki
@trans.fade 1.0 0.0 0.5
@flow.wait 0.5
@layer.set "y" x=200 opacity=1.0 duration=0.5
@flow.wait 0.5
```

Layer tweens and overlay fades do **not** block the VM. Use `@flow.wait` with
a matching duration when dialogue must not start until the effect finishes.
During a timed wait, Advance/Select/SkipTyping are ignored.

## Variables

```yuki
@var.set "met_y" true
@var.set "demo_choice" act
```

- Only `@var.set name value` (no `@var.get` command).
- Values are runtime `Value` (int/float/bool/str/none); names are strings.

## Layers (author summary)

```yuki
@layer.show "bg" "bg_room" kind=background
@layer.show "y" "char_y" kind=character z=10 x=-200 y=0 opacity=0
@layer.show "y" "char_y" 10 -200 0 0 kind=character   # positionals still fine
@layer.set "y" x=200 opacity=1.0 duration=0.5
@layer.move "y" 400 0 duration=0.3
@layer.hide "y" duration=0.3
```

Named negatives work: `x=-200`, `y=-1.5`, `opacity=0`.

See [`host-commands.md`](./host-commands.md) for full arg tables, defaults, and
tween rules.

## UI bridge (author summary)

Do **not** write `- screen` in `.yuki` (compile error). Title / menu / HUD are
MoonBit (`std_ui` + optional `ui_package`) — see [`ui-moonbit.md`](./ui-moonbit.md).

Narrative open/close of modals:

```yuki
@ui.show "game_menu"
@ui.show "save_load" mode=load
@ui.hide
```

## Comments and whitespace

```yuki
# full-line comment
- scene "s"
y:Line
```

Blank lines are ignored. Keep one statement per line (line-oriented lexer).

## Compile pipeline

```
.yuki → Lexer → Parser → AST
      → Macro expand
      → Resolve (externs, scenes, commands)
      → Lower → IR (Host / Yield / Choose / …; named args as #: markers)
      → Bytecode encode (MSB2, magic "MSB2", embedded locale catalogs)
```

UI trees are **not** produced by this pipeline; they are registered at host
init from `std_ui` / linked `ui_package`.

CLI:

```bash
moon run cmd/moonsightc --target native -- check path/to/file_or_dir
moon run cmd/moonsightc --target native -- build project_dir -o dist/out
```

`build` fails if literal image/audio resource ids used in scripts are missing
from project assets/manifest. Failed builds do not promote a half-written
`out_dir`. Optional `ui_package` rebuilds host wasm and restores the project_ui
stub afterward.

Diagnostics surface as compile/check errors (unknown command, duplicate scene,
parse failures, rejected `- screen`). Runtime host errors soft-halt the VM
(`HostResult::Error`).

## Minimal complete example

```yuki
- scene "entrypoint"
@flow.jump "intro"

- scene "intro"
@layer.show "bg" "bg_room" kind=background
@layer.show "y" "char_y" kind=character z=10 x=-200 y=0 opacity=0
@layer.set "y" x=200 opacity=1.0 duration=0.5
@audio.bgm "bgm_soft" volume=0.9 fade=0.5
@trans.fade 1.0 0.0 0.5
@flow.wait 0.5
y:Welcome.
@sys.save_hint
@flow.choice "Talk" "Leave" --result act
@var.set "choice" act
@flow.jump "end"

- scene "end"
@layer.hide "y" duration=0.2
@flow.wait 0.2
y:Thanks for playing.
@flow.yield
```

Cold start uses the std `title` modal (Start → `start_game` → entry). Press
**Esc** in play for `game_menu`.

See also:

- [`ui-moonbit.md`](./ui-moonbit.md) — MoonBit UI (HUD + modals, Capabilities)
- [`host-commands.md`](./host-commands.md) — standard host table, intents, save v4
- [`project-layout.md`](./project-layout.md) — repo + `moonsight.json`
- [`draw-list-pack.md`](./draw-list-pack.md) — frame pack + intent codes
