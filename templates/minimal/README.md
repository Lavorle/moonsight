# MoonSight project

Created with `moonsightc new`.

## Build & play

From the MoonSight monorepo root:

```bash
export CC=gcc

# optional: preferred Svelte host shell
cd apps/host-web && npm i && npm run build && cd ../..

# typecheck this project
moon run cmd/moonsightc --target native -- check path/to/this/project

# build web dist
moon run cmd/moonsightc --target native -- build path/to/this/project -o dist/game

# serve (WebGPU required; use localhost)
cd dist/game && python3 -m http.server 8080
# open http://localhost:8080/
```

Edit `main.yuki` and rebuild. See monorepo `docs/` and `README.md` for layout and host setup.

## Formal 1.0 locale and identity workflow

The scaffold declares `default_locale: "en"` and complete `en` /
`zh-Hans-CN` catalog examples under `locales/`. Their portable dot-separated
keys demonstrate the author-owned identity contract; they are not derived from
translated text or line numbers.

Before shipping bilingual content:

1. replace the example strings and keep both locale key sets identical;
2. run the canonical `moonsightc` migration/freeze workflow after explicit-ID
   tooling is available in your checkout;
3. review deterministic stable IDs, choice order, resource mappings, and v2-v4
   save compatibility output;
4. run `check` and `build`; never hand-edit MSB2 or digest metadata.

Writers emit save v5 and readers accept v2-v5. Locale is a preference, not part
of a save slot. See `docs/formal-1.0-author-guide.md` in the MoonSight repo.
