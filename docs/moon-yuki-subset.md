# MoonYuki Phase 1 subset

MoonYuki is a line-oriented visual-novel DSL compiled by the `script` package
into IR / bytecode (`MSB1`). This document describes **only the Phase 1
subset that is implemented and exercised by tests and the demo**.

Out of scope for Phase 1 (do not invent): visual editor, i18n, achievements,
Live2D / 3D, official YukimiScript bytecode compatibility.

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

The browser host still loads **entry source** as `demo.yuki` in Phase 1;
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
@flow.wait 1.0                 # positional number
@var.set "flag" true           # positional string + bool
@layer.show "y" "char_y" 10    # id, resource, optional z
@foo bar=1 --force             # named + flag
@flow.choice "Talk" "Leave" --result act
@flow.choice result="c" "Yes" "No"
```

Values:

| Kind | Examples |
|------|----------|
| Int | `0`, `10`, `-1` |
| Float | `1.0`, `0.5` |
| Bool | `true`, `false` |
| String | `"intro"`, `"bg_room"` |
| Ident | `act`, `time` (macro param refs / choice result names) |

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
must resolve to a known `extern` (file or builtin). Phase 1 demo does not rely
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
  scripts do not need `- extern` for `@layer.show`, `@flow.jump`, etc.

## Scenes and inheritance

```yuki
- scene "parent"
@text.begin

- scene "child" inherit "parent"
@text.end
```

- `inherit "parent"` records a parent name; the parent must exist in the unit
  (resolve error if missing).
- Phase 1 resolve validates the link; **runtime inheritance merge of stage
  state is minimal** — treat parent mainly as a structural/authoring hint
  unless a later task expands it.

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
| `@flow.wait [time]` | Implemented (yield; duration reserved for engine) |
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

## Variables

```yuki
@var.set "met_y" true
@var.set "demo_choice" act
```

- Only `@var.set name value` in Phase 1 (no `@var.get` command).
- Values are runtime `Value` (int/float/bool/str/none); names are strings.

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
      → Lower → IR (Host / Yield / Choose / …)
      → Bytecode encode (MSB1, magic "MSB1")
```

CLI:

```bash
moon run cmd/moonsightc --target native -- check path/to/file_or_dir
moon run cmd/moonsightc --target native -- build project_dir -o dist/out
```

Diagnostics surface as compile/check errors (unknown command, duplicate scene,
parse failures). Runtime host errors soft-halt the VM (`HostResult::Error`).

## Minimal complete example

```yuki
- scene "entrypoint"
@flow.jump "intro"

- scene "intro"
@layer.show "bg" "bg_room"
@audio.bgm "bgm_soft"
@trans.fade 1.0 0.0 0.5
y:Welcome.
@sys.save_hint
@flow.choice "Talk" "Leave" --result act
@var.set "choice" act
@flow.jump "end"

- scene "end"
@layer.hide "bg"
y:Thanks for playing.
@flow.yield
```

See also:

- [`host-commands.md`](./host-commands.md) — standard host table
- [`project-layout.md`](./project-layout.md) — repo + `moonsight.json`
- [`draw-list-pack.md`](./draw-list-pack.md) — frame pack + intent codes
