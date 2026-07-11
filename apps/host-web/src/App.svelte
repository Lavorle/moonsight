<script lang="ts">
  import { onMount } from "svelte";
  import { startGameSession, type GameSessionHandle } from "./lib/gameSession";

  let status = $state("loading…");
  let canvasEl: HTMLCanvasElement | undefined = $state();
  let handle: GameSessionHandle | null = null;

  const isRunning = $derived(status.startsWith("running"));

  onMount(() => {
    if (!canvasEl) {
      status = "no canvas";
      return;
    }
    let cancelled = false;
    startGameSession(canvasEl, {
      onStatus: (m) => {
        if (!cancelled) status = m;
      },
    })
      .then((h) => {
        if (cancelled) {
          h.stop();
          return;
        }
        handle = h;
      })
      .catch((e) => {
        // WebGPU missing / other boot errors already set via onStatus
        // with e.message (preserves Gpu.init text from webgpu_bridge).
        const msg = e && e.message ? String(e.message) : String(e);
        if (!cancelled) status = msg;
      });

    return () => {
      cancelled = true;
      handle?.stop();
      handle = null;
    };
  });
</script>

<div id="title-bar">MoonSight</div>
<div id="status" class:running={isRunning}>{status}</div>
<div id="hint">
  Click: advance / menus · click choices · Esc menu · Enter/Space confirm<br />
  ↑↓ focus · 1–9 pick · A auto · Ctrl+S save · Ctrl+L load
</div>
<canvas
  id="game"
  bind:this={canvasEl}
  width="1920"
  height="1080"
></canvas>
