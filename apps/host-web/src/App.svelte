<script lang="ts">
  import { onMount } from "svelte";
  import {
    DesktopSaveStore,
    getTauriInvoke,
    isTauriRuntime,
  } from "./lib/desktopSaveStore";
  import { startGameSession, type GameSessionHandle } from "./lib/gameSession";
  import { WebSaveStore, type SaveStore } from "./lib/saveStore";

  let status = $state("loading…");
  let canvasEl: HTMLCanvasElement | undefined = $state();
  let handle: GameSessionHandle | null = null;

  const isRunning = $derived(status.startsWith("running"));
  const isError = $derived(
    status.startsWith("error:") || status.startsWith("error "),
  );

  function formatError(e: unknown): string {
    const msg =
      e && typeof e === "object" && "message" in e
        ? String((e as Error).message)
        : String(e);
    return msg.startsWith("error:") ? msg : `error: ${msg}`;
  }

  /** Web → WebSaveStore; desktop Tauri → DesktopSaveStore (appData). */
  async function createSaveStore(): Promise<SaveStore> {
    if (isTauriRuntime()) {
      const invoke = getTauriInvoke();
      if (!invoke) {
        throw new Error("Tauri runtime detected but invoke is unavailable");
      }
      return DesktopSaveStore.create(invoke);
    }
    return new WebSaveStore();
  }

  onMount(() => {
    if (!canvasEl) {
      status = "error: no canvas";
      return;
    }
    let cancelled = false;
    (async () => {
      const store = await createSaveStore();
      if (cancelled) return;
      const h = await startGameSession(canvasEl!, {
        store,
        onStatus: (m) => {
          if (!cancelled) status = m;
        },
      });
      if (cancelled) {
        h.stop();
        return;
      }
      handle = h;
    })().catch((e) => {
      // WebGPU missing / other boot errors already set via onStatus
      // with error: prefix (preserves Gpu.init text from webgpu_bridge).
      if (!cancelled) status = formatError(e);
    });

    return () => {
      cancelled = true;
      handle?.stop();
      handle = null;
    };
  });
</script>

<div id="title-bar">MoonSight</div>
{#if !isRunning}
  <div
    id="status-panel"
    class:error={isError}
    role="status"
    aria-live="polite"
  >
    <div class="status-panel-inner">
      <div class="status-panel-title">
        {isError ? "MoonSight — error" : "MoonSight"}
      </div>
      <div class="status-panel-msg">{status}</div>
    </div>
  </div>
{:else}
  <div id="status" class="running">{status}</div>
{/if}
{#if isRunning}
  <div id="hint">
    Click: advance / menus · click choices · Esc menu · Enter/Space confirm<br />
    ↑↓ focus · 1–9 pick · A auto · Ctrl+S save · Ctrl+L load
  </div>
{/if}
<canvas
  id="game"
  bind:this={canvasEl}
  width="1920"
  height="1080"
  class:hidden={!isRunning}
></canvas>
