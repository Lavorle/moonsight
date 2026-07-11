//! MoonSight desktop shell.
//!
//! Thin webview host for the same static package as the browser: `dist/demo`
//! from `moonsightc build` (host shell = `apps/host-web/dist` Svelte).
//! No React/Svelte toolchain inside Tauri and no native render backend.
//!
//! Persistence: prefs + save slots under OS appData (`…/moonsight/`), exposed
//! via invoke commands consumed by `DesktopSaveStore` in the Svelte host.

use std::fs;
use std::path::{Path, PathBuf};

use tauri::Manager;

fn moonsight_dir(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?
        .join("moonsight");
    fs::create_dir_all(dir.join("saves")).map_err(|e| e.to_string())?;
    Ok(dir)
}

fn atomic_write(path: &Path, body: String) -> Result<(), String> {
    let tmp = path.with_extension("json.tmp");
    fs::write(&tmp, body).map_err(|e| e.to_string())?;
    fs::rename(&tmp, path).map_err(|e| e.to_string())
}

#[tauri::command]
fn read_prefs(app: tauri::AppHandle) -> Result<Option<String>, String> {
    let path = moonsight_dir(&app)?.join("prefs.json");
    if !path.exists() {
        return Ok(None);
    }
    fs::read_to_string(path).map(Some).map_err(|e| e.to_string())
}

#[tauri::command]
fn write_prefs(app: tauri::AppHandle, body: String) -> Result<(), String> {
    let path = moonsight_dir(&app)?.join("prefs.json");
    atomic_write(&path, body)
}

#[tauri::command]
fn read_save_slot(app: tauri::AppHandle, slot: u32) -> Result<Option<String>, String> {
    let path = moonsight_dir(&app)?
        .join("saves")
        .join(format!("{slot}.json"));
    if !path.exists() {
        return Ok(None);
    }
    fs::read_to_string(path).map(Some).map_err(|e| e.to_string())
}

#[tauri::command]
fn write_save_slot(app: tauri::AppHandle, slot: u32, body: String) -> Result<(), String> {
    let path = moonsight_dir(&app)?
        .join("saves")
        .join(format!("{slot}.json"));
    atomic_write(&path, body)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            read_prefs,
            write_prefs,
            read_save_slot,
            write_save_slot
        ])
        .run(tauri::generate_context!())
        .expect("error while running MoonSight desktop shell");
}
