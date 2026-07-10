<script lang="ts">
  /** Empty shell — boot / WASM port is Task 8. */
  const status = "shell ready (no boot yet)";
</script>

<div id="status">{status}</div>
<div id="hint">
  Enter/Space: advance or confirm choice · ↑↓: choice focus · click row / 1–9: pick<br />
  Esc: menu · A: auto · Ctrl+S save · Ctrl+L load
</div>
<canvas id="game" width="1920" height="1080"></canvas>
