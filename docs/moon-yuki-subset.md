# MoonYuki subset (Phase 1 + Phase 2)

MoonYuki is a line-oriented visual-novel DSL compiled by the `script` package
into IR / bytecode (`MSB1`). This document describes **the subset that is
implemented and exercised by tests and the demo**.

Out of scope (do not invent): visual editor, i18n, achievements, Live2D / 3D,
full timeline / animation queues, blocking presentation DSL, official
YukimiScript bytecode compatibility, `trans.dissolve`.

## Phase 2 notes

Phase 2 hardens presentation on the Phase 1 theater model:

| Feature | Notes |
|---------|--------|
| Named host args | `kind=background`, `duration=0.5`, `opacity=1.0` preserved through lower (`#:name` markers) |
| `layer` kinds | `background` / `character` / `effect` / `ui`; default **`character`** |
| Property tweens | `x` / `y` / `opacity` + `duration`; linear; fire-and-forget |
| `layer.set` | Change props without rebinding resource; errors if id missing |
| `flow.wait` | Real wall-clock timing; Advance ignored during timed wait |
| `trans.fade` | Wall-clock `fade_remaining`; pair with `@flow.wait` to pause script |
| Save | Format **v3** (tweens, fade_remaining, wait_remaining); v2 still loads |

Bare keywords work for string-valued named args after resolve/lower
(`kind=background` or `kind="background"`). Prefer bare for kinds/enums in demos.

## File shape

A compilation unit (one `.yuki` file) may contain, in any order at top level:

| Construct | Form |
|-----------|------|
| Comment | `# …` (full-line; `#` after content is not a mid-line comment) |
| Extern | `- extern name [params…]` |
| Macro | `- macro name [params…]` then body lines ending at next top-level decl |
| Scene | `- scene "name"` or `- scene "name" inherit "parent"` |

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
  first scene of the **entry file** graph; the demo uses `entrypoint` → jumps.

The browser host still loads **entry source** as `demo.yuki`;
`game.msb` is emitted for the publish path and tests.

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

command     ::= "@" dotted_name arg*
dialogue    ::= speaker ":" text_parts
text_parts  ::= (literal | inline)*
inline      ::= "[" dotted_name arg* "]"

arg         ::= positional | named | flag
positional  ::= literal | ident
named       ::= name "=" (literal | ident)
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
@layer.show "y" "char_y" kind=character z=10 x=0 opacity=0
@layer.show "y" "char_y" 10 -200 0 0 kind=character
@layer.set "y" x=200 opacity=1.0 duration=0.5
@layer.move "y" 400 0 duration=0.3
@layer.hide "y" duration=0.3
```

Named numeric values do not accept a leading `-` in the current lexer
(`x=-200` fails); use positionals for negative coordinates (e.g. `10 -200 0 0`).

See [`host-commands.md`](./host-commands.md) for full arg tables, defaults, and
tween rules.

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
      → Bytecode encode (MSB1, magic "MSB1")
```

CLI:

```bash
moon run cmd/moonsightc --target native -- check path/to/file_or_dir
moon run cmd/moonsightc --target native -- build project_dir -o dist/out
```

`build` fails if literal image/audio resource ids used in scripts are missing
from project assets/manifest.

Diagnostics surface as compile/check errors (unknown command, duplicate scene,
parse failures). Runtime host errors soft-halt the VM (`HostResult::Error`).

## Minimal complete example

```yuki
- scene "entrypoint"
@flow.jump "intro"

- scene "intro"
@layer.show "bg" "bg_room" kind=background
@layer.show "y" "char_y" 10 -200 0 0 kind=character
@layer.set "y" x=200 opacity=1.0 duration=0.5
@audio.bgm "bgm_soft"
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

See also:

- [`host-commands.md`](./host-commands.md) — standard host table, intents, save v3
- [`project-layout.md`](./project-layout.md) — repo + `moonsight.json`
- [`draw-list-pack.md`](./draw-list-pack.md) — frame pack + intent codes
