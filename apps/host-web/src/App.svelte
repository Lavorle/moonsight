<script lang="ts">
  import { onMount } from "svelte";
  import { startGameSession, type GameSessionHandle } from "./lib/gameSession";

  let status = $state("loading…");
  let canvasEl: HTMLCanvasElement | undefined = $state();
  let handle: GameSessionHandle | null = null;

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

<div id="status">{status}</div>
<div id="hint">
  Enter/Space: advance or confirm choice · ↑↓: choice focus · click row / 1–9: pick<br />
  Esc: menu · A: auto · Ctrl+S save · Ctrl+L load
</div>
<canvas
  id="game"
  bind:this={canvasEl}
  width="1920"
  height="1080"
></canvas>
