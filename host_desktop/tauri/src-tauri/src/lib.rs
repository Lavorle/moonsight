//! MoonSight desktop shell.
//!
//! Thin webview host for the same static package as the browser: `dist/demo`
//! from `moonsightc build` (host shell = `apps/host-web/dist` Svelte).
//! No React/Svelte toolchain inside Tauri and no native render backend.
//!
//! Persistence: prefs + save slots under OS appData (`…/moonsight/`), exposed
//! via invoke commands consumed by `DesktopSaveStore` in the Svelte host.

use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use tauri::Manager;

static WRITE_LOCK: Mutex<()> = Mutex::new(());

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum WriteFault {
    None,
    #[cfg(test)]
    InstallRename,
    #[cfg(test)]
    AfterBackup,
}

fn moonsight_dir(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?
        .join("moonsight");
    fs::create_dir_all(dir.join("saves")).map_err(|e| e.to_string())?;
    Ok(dir)
}

fn temporary_path(path: &Path) -> PathBuf {
    path.with_extension("json.tmp")
}

fn backup_path(path: &Path) -> PathBuf {
    path.with_extension("json.bak")
}

fn remove_if_exists(path: &Path) -> io::Result<bool> {
    match fs::remove_file(path) {
        Ok(()) => Ok(true),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(error),
    }
}

#[cfg(unix)]
fn sync_directory(path: &Path) -> io::Result<()> {
    fs::File::open(path)?.sync_all()
}

#[cfg(windows)]
fn sync_directory(path: &Path) -> io::Result<()> {
    use std::os::windows::fs::OpenOptionsExt;

    const FILE_FLAG_BACKUP_SEMANTICS: u32 = 0x0200_0000;
    OpenOptions::new()
        .read(true)
        .custom_flags(FILE_FLAG_BACKUP_SEMANTICS)
        .open(path)?
        .sync_all()
}

#[cfg(not(any(unix, windows)))]
fn sync_directory(_path: &Path) -> io::Result<()> {
    Ok(())
}

fn parent_directory(path: &Path) -> io::Result<&Path> {
    path.parent().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("persistence path has no parent: {}", path.display()),
        )
    })
}

fn recover_interrupted_replace_locked(path: &Path) -> io::Result<()> {
    let parent = parent_directory(path)?;
    let tmp = temporary_path(path);
    let backup = backup_path(path);
    let mut changed = false;

    if path.exists() {
        changed |= remove_if_exists(&backup)?;
    } else if backup.exists() {
        fs::rename(&backup, path)?;
        changed = true;
    }
    changed |= remove_if_exists(&tmp)?;

    if changed {
        sync_directory(parent)?;
    }
    Ok(())
}

fn read_durable(path: &Path) -> io::Result<Option<String>> {
    let _guard = WRITE_LOCK
        .lock()
        .map_err(|_| io::Error::other("persistence write lock poisoned"))?;
    recover_interrupted_replace_locked(path)?;
    match fs::read_to_string(path) {
        Ok(body) => Ok(Some(body)),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error),
    }
}

fn rollback_backup(path: &Path, backup: &Path, parent: &Path) -> io::Result<()> {
    fs::rename(backup, path)?;
    sync_directory(parent)
}

fn durable_write(path: &Path, body: &str) -> io::Result<()> {
    durable_write_with_fault(path, body, WriteFault::None)
}

fn durable_write_with_fault(path: &Path, body: &str, fault: WriteFault) -> io::Result<()> {
    let _guard = WRITE_LOCK
        .lock()
        .map_err(|_| io::Error::other("persistence write lock poisoned"))?;
    let parent = parent_directory(path)?;
    fs::create_dir_all(parent)?;
    recover_interrupted_replace_locked(path)?;

    let tmp = temporary_path(path);
    let backup = backup_path(path);
    remove_if_exists(&tmp)?;

    let mut file = OpenOptions::new().write(true).create_new(true).open(&tmp)?;
    file.write_all(body.as_bytes())?;
    file.sync_all()?;
    drop(file);

    let had_last_good = path.exists();
    if had_last_good {
        fs::rename(path, &backup)?;
        if let Err(error) = sync_directory(parent) {
            let _ = rollback_backup(path, &backup, parent);
            let _ = remove_if_exists(&tmp);
            return Err(error);
        }

        #[cfg(test)]
        if fault == WriteFault::AfterBackup {
            return Err(io::Error::other("injected interruption after backup"));
        }
    }

    #[cfg(test)]
    let install_result = if fault == WriteFault::InstallRename {
        Err(io::Error::other("injected install rename failure"))
    } else {
        fs::rename(&tmp, path)
    };
    #[cfg(not(test))]
    let install_result = fs::rename(&tmp, path);

    if let Err(install_error) = install_result {
        let rollback_error = if had_last_good {
            rollback_backup(path, &backup, parent).err()
        } else {
            None
        };
        let _ = remove_if_exists(&tmp);
        return match rollback_error {
            Some(rollback_error) => Err(io::Error::new(
                install_error.kind(),
                format!(
                    "install failed ({install_error}); last-good remains at {} because rollback failed ({rollback_error})",
                    backup.display()
                ),
            )),
            None => Err(install_error),
        };
    }

    // The command only resolves after the installed file and parent directory
    // are synced. Frontend flush/shutdown can therefore await invoke promises.
    sync_directory(parent)?;

    if had_last_good && remove_if_exists(&backup)? {
        sync_directory(parent)?;
    }
    Ok(())
}

fn atomic_write(path: &Path, body: String) -> Result<(), String> {
    durable_write(path, &body).map_err(|e| e.to_string())
}

fn flush_directory_tree(dir: &Path) -> io::Result<()> {
    let _guard = WRITE_LOCK
        .lock()
        .map_err(|_| io::Error::other("persistence write lock poisoned"))?;
    sync_directory(&dir.join("saves"))?;
    sync_directory(dir)
}

#[tauri::command]
fn read_prefs(app: tauri::AppHandle) -> Result<Option<String>, String> {
    let path = moonsight_dir(&app)?.join("prefs.json");
    read_durable(&path).map_err(|e| e.to_string())
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
    read_durable(&path).map_err(|e| e.to_string())
}

#[tauri::command]
fn write_save_slot(app: tauri::AppHandle, slot: u32, body: String) -> Result<(), String> {
    let path = moonsight_dir(&app)?
        .join("saves")
        .join(format!("{slot}.json"));
    atomic_write(&path, body)
}

#[tauri::command]
fn flush_persistence(app: tauri::AppHandle) -> Result<(), String> {
    let dir = moonsight_dir(&app)?;
    flush_directory_tree(&dir).map_err(|e| e.to_string())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            read_prefs,
            write_prefs,
            read_save_slot,
            write_save_slot,
            flush_persistence
        ])
        .run(tauri::generate_context!())
        .expect("error while running MoonSight desktop shell");
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static NEXT_TEST_DIR: AtomicU64 = AtomicU64::new(0);

    struct TestDir(PathBuf);

    impl TestDir {
        fn new() -> Self {
            let id = NEXT_TEST_DIR.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir()
                .join(format!("moonsight-save-tests-{}-{id}", std::process::id()));
            fs::create_dir_all(&path).unwrap();
            Self(path)
        }

        fn file(&self) -> PathBuf {
            self.0.join("slot.json")
        }
    }

    impl Drop for TestDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn durable_write_replaces_existing_file_and_cleans_artifacts() {
        let dir = TestDir::new();
        let path = dir.file();
        fs::write(&path, "old").unwrap();

        durable_write(&path, "new").unwrap();

        assert_eq!(fs::read_to_string(&path).unwrap(), "new");
        assert!(!temporary_path(&path).exists());
        assert!(!backup_path(&path).exists());
    }

    #[test]
    fn failed_install_restores_last_good_file() {
        let dir = TestDir::new();
        let path = dir.file();
        fs::write(&path, "last-good").unwrap();

        let result = durable_write_with_fault(&path, "new", WriteFault::InstallRename);

        assert!(result.is_err());
        assert_eq!(fs::read_to_string(&path).unwrap(), "last-good");
        assert!(!backup_path(&path).exists());
    }

    #[test]
    fn read_recovers_last_good_after_interrupted_replacement() {
        let dir = TestDir::new();
        let path = dir.file();
        fs::write(&path, "last-good").unwrap();

        let result = durable_write_with_fault(&path, "new", WriteFault::AfterBackup);
        assert!(result.is_err());
        assert!(!path.exists());
        assert_eq!(fs::read_to_string(backup_path(&path)).unwrap(), "last-good");

        assert_eq!(read_durable(&path).unwrap().as_deref(), Some("last-good"));
        assert_eq!(fs::read_to_string(&path).unwrap(), "last-good");
        assert!(!backup_path(&path).exists());
        assert!(!temporary_path(&path).exists());
    }
}
