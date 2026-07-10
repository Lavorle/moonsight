//! MoonSight desktop shell.
//!
//! Phase 1: thin webview host for the same static build as the browser
//! (`dist/demo` from moonsightc + host_web). No native render backend.
//! Saves stay in webview `localStorage` (see host_web/js_glue/boot.js).

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("error while running MoonSight desktop shell");
}
