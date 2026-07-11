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
