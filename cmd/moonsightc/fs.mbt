///|
/// Thin native filesystem helpers over MoonBit runtime C FFI.
/// Prefer this over vendoring moonbitlang/x until the registry is available.

///|
#external
priv type FileHandle

///|
#borrow(path, mode)
extern "C" fn fopen_ffi(path : Bytes, mode : Bytes) -> FileHandle = "moonbit_fopen_ffi"

///|
extern "C" fn is_null_ffi(ptr : FileHandle) -> Int = "moonbit_is_null"

///|
#borrow(ptr)
extern "C" fn fread_ffi(
  ptr : Bytes,
  size : Int,
  nitems : Int,
  stream : FileHandle,
) -> Int = "moonbit_fread_ffi"

///|
#borrow(ptr)
extern "C" fn fwrite_ffi(
  ptr : Bytes,
  size : Int,
  nitems : Int,
  stream : FileHandle,
) -> Int = "moonbit_fwrite_ffi"

///|
extern "C" fn fseek_ffi(file : FileHandle, offset : Int, whence : Int) -> Int = "moonbit_fseek_ffi"

///|
extern "C" fn ftell_ffi(file : FileHandle) -> Int = "moonbit_ftell_ffi"

///|
extern "C" fn fflush_ffi(stream : FileHandle) -> Int = "moonbit_fflush_ffi"

///|
extern "C" fn fclose_ffi(file : FileHandle) -> Int = "moonbit_fclose_ffi"

///|
#borrow(path)
extern "C" fn stat_ffi(path : Bytes) -> Int = "moonbit_stat_ffi"

///|
#borrow(path)
extern "C" fn is_dir_ffi(path : Bytes) -> Int = "moonbit_is_dir_ffi"

///|
#borrow(path)
extern "C" fn is_file_ffi(path : Bytes) -> Int = "moonbit_is_file_ffi"

///|
#borrow(path)
extern "C" fn create_dir_ffi(path : Bytes) -> Int = "moonbit_create_dir_ffi"

///|
#borrow(path)
extern "C" fn remove_dir_ffi(path : Bytes) -> Int = "moonbit_remove_dir_ffi"

///|
#borrow(path)
extern "C" fn remove_file_ffi(path : Bytes) -> Int = "moonbit_remove_file_ffi"

///|
#borrow(old, new_)
extern "C" fn rename_ffi(old : Bytes, new_ : Bytes) -> Int = "rename"

///|
#borrow(path)
extern "C" fn read_dir_ffi(path : Bytes) -> FileHandle = "moonbit_read_dir_ffi"

///|
extern "C" fn get_error_message_ffi() -> Bytes = "moonbit_get_error_message"

///|
#borrow(path, output)
extern "C" fn sha256_file_ffi(path : Bytes, output : Bytes) -> Int = "moonsight_sha256_file"

///|
priv suberror IoError {
  IoError(String)
} derive(Debug)

///|
fn last_io_error() -> String {
  @utf8.decode_lossy(get_error_message_ffi())
}

///|
/// Encode a path as a NUL-terminated UTF-8 byte string for C APIs.
fn c_path(s : String) -> Bytes {
  let enc = @utf8.encode(s)
  let buf = Buffer(size_hint=enc.length() + 1)
  buf.write_bytes(enc)
  buf.write_byte(b'\x00')
  buf.to_bytes()
}

///|
fn path_exists(path : String) -> Bool {
  stat_ffi(c_path(path)) != -1
}

///|
fn is_dir(path : String) -> Bool raise IoError {
  let code = is_dir_ffi(c_path(path))
  guard code != -1 else { raise IoError(last_io_error()) }
  code == 1
}

///|
fn is_file(path : String) -> Bool raise IoError {
  let code = is_file_ffi(c_path(path))
  guard code != -1 else { raise IoError(last_io_error()) }
  code == 1
}

///|
fn read_file_to_bytes(path : String) -> Bytes raise IoError {
  let file = fopen_ffi(c_path(path), b"rb\x00")
  guard is_null_ffi(file) == 0 else { raise IoError(last_io_error()) }
  guard fseek_ffi(file, 0, 2) == 0 else { raise IoError(last_io_error()) }
  let size = ftell_ffi(file)
  guard size >= 0 else { raise IoError(last_io_error()) }
  guard fseek_ffi(file, 0, 0) == 0 else { raise IoError(last_io_error()) }
  let bytes = Bytes::make(size, 0)
  let n = fread_ffi(bytes, 1, size, file)
  guard n == size else { raise IoError(last_io_error()) }
  guard fclose_ffi(file) == 0 else { raise IoError(last_io_error()) }
  bytes
}

///|
fn read_file_to_string(path : String) -> String raise IoError {
  @utf8.decode_lossy(read_file_to_bytes(path))
}

///|
fn write_bytes_to_file(path : String, content : Bytes) -> Unit raise IoError {
  let file = fopen_ffi(c_path(path), b"wb\x00")
  guard is_null_ffi(file) == 0 else { raise IoError(last_io_error()) }
  let n = fwrite_ffi(content, 1, content.length(), file)
  guard n == content.length() else { raise IoError(last_io_error()) }
  guard fflush_ffi(file) == 0 else { raise IoError(last_io_error()) }
  guard fclose_ffi(file) == 0 else { raise IoError(last_io_error()) }
}

///|
fn write_string_to_file(path : String, content : String) -> Unit raise IoError {
  write_bytes_to_file(path, @utf8.encode(content))
}

///|
fn create_dir(path : String) -> Unit raise IoError {
  guard create_dir_ffi(c_path(path)) == 0 else {
    raise IoError(last_io_error())
  }
}

///|
fn remove_file(path : String) -> Unit raise IoError {
  guard remove_file_ffi(c_path(path)) == 0 else {
    raise IoError(last_io_error())
  }
}

///|
/// Remove an empty directory (`rmdir`).
fn remove_dir(path : String) -> Unit raise IoError {
  guard remove_dir_ffi(c_path(path)) == 0 else {
    raise IoError(last_io_error())
  }
}

///|
/// Recursively remove a file or directory tree.
fn remove_tree(path : String) -> Unit raise IoError {
  if !path_exists(path) {
    return
  }
  if is_dir(path) {
    for name in read_dir(path) {
      remove_tree(join_path(path, name))
    }
    remove_dir(path)
  } else {
    remove_file(path)
  }
}

///|
/// Best-effort recursive remove (swallows I/O errors).
fn remove_tree_best_effort(path : String) -> Unit {
  remove_tree(path) catch {
    IoError(_) => ()
  }
}

///|
/// Rename/move `old` to `new_` (libc `rename`).
fn rename_path(old : String, new_ : String) -> Unit raise IoError {
  guard rename_ffi(c_path(old), c_path(new_)) == 0 else {
    raise IoError(last_io_error())
  }
}

///|
/// Create directory and any missing parents (mkdir -p).
fn ensure_dir(path : String) -> Unit raise IoError {
  if path == "" || path == "." {
    return
  }
  if path_exists(path) {
    guard is_dir(path) else { raise IoError("not a directory: \{path}") }
    return
  }
  let parent = dirname(path)
  if parent != path && parent != "" && parent != "." {
    ensure_dir(parent)
  }
  create_dir(path)
}

///|
fn handler_to_fixed_array(handler : FileHandle) -> FixedArray[Bytes] = "%identity"

///|
fn read_dir(path : String) -> Array[String] raise IoError {
  let res = read_dir_ffi(c_path(path))
  guard is_null_ffi(res) == 0 else { raise IoError(last_io_error()) }
  let files = Array::from_fixed_array(handler_to_fixed_array(res))
  let names = files.map(b => @utf8.decode_lossy(b))
  names.sort()
  names
}

///|
/// Return the lowercase raw SHA-256 digest for a regular file.
fn sha256_file(path : String) -> String raise IoError {
  let output = Bytes::make(64, 0)
  guard sha256_file_ffi(c_path(path), output) == 0 else {
    raise IoError(last_io_error())
  }
  @utf8.decode_lossy(output)
}

///|
fn copy_file(src : String, dst : String) -> Unit raise IoError {
  let parent = dirname(dst)
  ensure_dir(parent)
  write_bytes_to_file(dst, read_file_to_bytes(src))
}

///|
/// Recursively copy a directory tree. Destination root is created if needed.
fn copy_dir(src : String, dst : String) -> Unit raise IoError {
  ensure_dir(dst)
  for name in read_dir(src) {
    let from = join_path(src, name)
    let to = join_path(dst, name)
    if is_dir(from) {
      copy_dir(from, to)
    } else {
      copy_file(from, to)
    }
  }
}

///|
fn join_path(a : String, b : String) -> String {
  if a == "" {
    b
  } else if a.has_suffix("/") {
    "\{a}\{b}"
  } else {
    "\{a}/\{b}"
  }
}

///|
fn basename(path : String) -> String {
  match path.rev_split_once("/") {
    Some((_, name)) => name.to_owned()
    None => path
  }
}

///|
fn dirname(path : String) -> String {
  match path.rev_split_once("/") {
    Some((dir, _)) => {
      let d = dir.to_owned()
      if d == "" {
        "/"
      } else {
        d
      }
    }
    None => "."
  }
}

///|
fn strip_extension(name : String) -> String {
  match name.rev_split_once(".") {
    Some((base, _)) => {
      let b = base.to_owned()
      if b == "" {
        name
      } else {
        b
      }
    }
    None => name
  }
}

///|
fn has_extension(name : String, ext : String) -> Bool {
  name.has_suffix(ext)
}
