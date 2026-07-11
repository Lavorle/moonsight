//! MoonSight desktop shell.
//!
//! Thin webview host for the same static package as the browser: `dist/demo`
//! from `moonsightc build` (host shell = `apps/host-web/dist` Svelte).
//! No React/Svelte toolchain inside Tauri and no native render backend.
//! Saves stay in webview `localStorage`.

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("error while running MoonSight desktop shell");
}
