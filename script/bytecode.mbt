///|
/// Errors while encoding or decoding `.msb` bytecode.
pub(all) suberror BytecodeError {
  InvalidMagic
  UnsupportedVersion(Int)
  Truncated(message~ : String)
  BadOpcode(Byte)
  BadValueTag(Byte)
} derive(Debug, Eq)

// Opcodes (fixed, MSB1)

///|
let op_nop : Byte = 0

///|
let op_host : Byte = 1

///|
let op_jump : Byte = 2

///|
let op_jump_if : Byte = 3

///|
let op_jump_if_not : Byte = 4

///|
let op_yield : Byte = 5

///|
let op_choose : Byte = 6

///|
let op_return : Byte = 7

// IrValue tags

///|
let val_int : Byte = 0

///|
let val_float : Byte = 1

///|
let val_bool : Byte = 2

///|
let val_str : Byte = 3

///|
let val_var : Byte = 4

///|
let val_none : Byte = 5

///|
let msb_version : Int = 1

///|
/// One locale's stable presentation catalog. Keys are author-owned IDs and
/// values are the localized strings presented by the Host.
pub(all) struct LocaleCatalog {
  locale : String
  entries : Map[String, String]
} derive(Debug, Eq)

///|
/// Deterministic MSB2 payload. The executable module remains independently
/// decodable while catalogs are ordered by locale and stable presentation ID.
pub(all) struct Msb2Bundle {
  ir : IrModule
  catalogs : Array[LocaleCatalog]
} derive(Debug)

///|
/// Encode an IR module as little-endian MSB1 bytecode.
///
/// Layout:
/// ```
/// magic: b"MSB1"
/// u32 version = 1
/// u32 entry_len + utf8 entry
/// u32 scene_count
/// for each scene (insertion order):
///   u32 name_len + utf8 name
///   u32 op_count
///   for each linearized op: u8 opcode + payload
/// ```
pub fn encode_module(ir : IrModule) -> Bytes {
  let buf = Buffer(size_hint=256)
  buf.write_bytes(b"MSB1")
  write_u32(buf, msb_version)
  write_string(buf, ir.entry)
  write_u32(buf, ir.scenes.length())
  let scene_names : Array[String] = []
  for name, _ in ir.scenes {
    scene_names.push(name)
  }
  scene_names.sort()
  for name in scene_names {
    let scene = ir.scenes[name]
    // name should match scene.name; prefer map key for stability
    write_string(buf, name)
    let ops = linearize_ops(scene.ops)
    write_u32(buf, ops.length())
    for op in ops {
      encode_op(buf, op)
    }
  }
  buf.to_bytes()
}

///|
/// Encode deterministic MSB2 bytes with an executable section and locale
/// catalog section. Map insertion order never affects the encoded bytes.
///
/// Layout: `MSB2`, version 2, length-prefixed MSB1 module, catalog count,
/// followed by sorted locale/name/value strings.
pub fn encode_msb2(bundle : Msb2Bundle) -> Bytes {
  let buf = Buffer(size_hint=512)
  buf.write_bytes(b"MSB2")
  write_u32(buf, 2)
  let module_bytes = encode_module(bundle.ir)
  write_u32(buf, module_bytes.length())
  buf.write_bytes(module_bytes)
  let catalogs = bundle.catalogs.copy()
  catalogs.sort_by((a, b) => a.locale.compare(b.locale))
  write_u32(buf, catalogs.length())
  for catalog in catalogs {
    write_string(buf, catalog.locale)
    let ids : Array[String] = []
    for id, _ in catalog.entries {
      ids.push(id)
    }
    ids.sort()
    write_u32(buf, ids.length())
    for id in ids {
      write_string(buf, id)
      write_string(buf, catalog.entries[id])
    }
  }
  buf.to_bytes()
}

///|
/// Decode MSB1 bytecode back to an IR module.
pub fn decode_module(bytes : Bytes) -> IrModule raise BytecodeError {
  let r = ByteReader::new(bytes)
  let magic = r.read_bytes(4)
  if magic != b"MSB1" {
    raise InvalidMagic
  }
  let version = r.read_u32()
  if version != msb_version {
    raise UnsupportedVersion(version)
  }
  let entry = r.read_string()
  let scene_count = r.read_u32()
  let scenes : Map[String, IrScene] = {}
  for _ in 0..<scene_count {
    let name = r.read_string()
    let op_count = r.read_u32()
    let ops : Array[IrOp] = []
    for _ in 0..<op_count {
      ops.push(decode_op(r))
    }
    scenes[name] = { name, ops }
  }
  { scenes, entry }
}

///|
/// Resolve `Label` markers and rewrite jump targets to instruction indices.
pub fn linearize_ops(ops : Array[IrOp]) -> Array[IrOp] {
  let label_to_ip : Map[Int, Int] = {}
  let mut ip = 0
  for op in ops {
    match op {
      Label(id) => label_to_ip[id] = ip
      _ => ip = ip + 1
    }
  }
  let out : Array[IrOp] = []
  for op in ops {
    match op {
      Label(_) => ()
      Jump(label~) =>
        out.push(Jump(label=label_to_ip.get_or_default(label, label)))
      JumpIf(cond~, label~) =>
        out.push(JumpIf(cond~, label=label_to_ip.get_or_default(label, label)))
      JumpIfNot(cond~, label~) =>
        out.push(
          JumpIfNot(cond~, label=label_to_ip.get_or_default(label, label)),
        )
      other => out.push(other)
    }
  }
  out
}

///|
fn encode_op(buf : Buffer, op : IrOp) -> Unit {
  match op {
    Nop => buf.write_byte(op_nop)
    Host(name~, args~) => {
      buf.write_byte(op_host)
      write_string(buf, name)
      write_u32(buf, args.length())
      for v in args {
        encode_value(buf, v)
      }
    }
    Jump(label~) => {
      buf.write_byte(op_jump)
      write_i32(buf, label)
    }
    JumpIf(cond~, label~) => {
      buf.write_byte(op_jump_if)
      encode_value(buf, cond)
      write_i32(buf, label)
    }
    JumpIfNot(cond~, label~) => {
      buf.write_byte(op_jump_if_not)
      encode_value(buf, cond)
      write_i32(buf, label)
    }
    Label(_) => () // should already be stripped
    Yield => buf.write_byte(op_yield)
    Choose(options~, result_var~) => {
      buf.write_byte(op_choose)
      write_u32(buf, options.length())
      for opt in options {
        write_string(buf, opt)
      }
      write_string(buf, result_var)
    }
    Return => buf.write_byte(op_return)
  }
}

///|
fn decode_op(r : ByteReader) -> IrOp raise BytecodeError {
  let code = r.read_byte()
  if code == op_nop {
    Nop
  } else if code == op_host {
    let name = r.read_string()
    let n = r.read_u32()
    let args : Array[IrValue] = []
    for _ in 0..<n {
      args.push(decode_value(r))
    }
    Host(name~, args~)
  } else if code == op_jump {
    Jump(label=r.read_i32())
  } else if code == op_jump_if {
    let cond = decode_value(r)
    JumpIf(cond~, label=r.read_i32())
  } else if code == op_jump_if_not {
    let cond = decode_value(r)
    JumpIfNot(cond~, label=r.read_i32())
  } else if code == op_yield {
    Yield
  } else if code == op_choose {
    let n = r.read_u32()
    let options : Array[String] = []
    for _ in 0..<n {
      options.push(r.read_string())
    }
    let result_var = r.read_string()
    Choose(options~, result_var~)
  } else if code == op_return {
    Return
  } else {
    raise BadOpcode(code)
  }
}

///|
fn encode_value(buf : Buffer, v : IrValue) -> Unit {
  match v {
    Int(n) => {
      buf.write_byte(val_int)
      write_i32(buf, n)
    }
    Float(f) => {
      buf.write_byte(val_float)
      buf.write_double_le(f)
    }
    Bool(b) => {
      buf.write_byte(val_bool)
      buf.write_byte(if b { 1 } else { 0 })
    }
    Str(s) => {
      buf.write_byte(val_str)
      write_string(buf, s)
    }
    Var(s) => {
      buf.write_byte(val_var)
      write_string(buf, s)
    }
    None_ => buf.write_byte(val_none)
  }
}

///|
fn decode_value(r : ByteReader) -> IrValue raise BytecodeError {
  let tag = r.read_byte()
  if tag == val_int {
    Int(r.read_i32())
  } else if tag == val_float {
    Float(r.read_f64())
  } else if tag == val_bool {
    Bool(r.read_byte() != 0)
  } else if tag == val_str {
    Str(r.read_string())
  } else if tag == val_var {
    Var(r.read_string())
  } else if tag == val_none {
    None_
  } else {
    raise BadValueTag(tag)
  }
}

///|
fn write_u32(buf : Buffer, n : Int) -> Unit {
  buf.write_int_le(n)
}

///|
fn write_i32(buf : Buffer, n : Int) -> Unit {
  buf.write_int_le(n)
}

///|
fn write_string(buf : Buffer, s : String) -> Unit {
  // length in UTF-8 bytes
  let encoded = @utf8.encode(s)
  write_u32(buf, encoded.length())
  buf.write_bytes(encoded)
}

///|
priv struct ByteReader {
  bytes : Bytes
  mut pos : Int
}

///|
fn ByteReader::new(bytes : Bytes) -> ByteReader {
  { bytes, pos: 0 }
}

///|
fn ByteReader::remain(self : ByteReader) -> Int {
  self.bytes.length() - self.pos
}

///|
fn ByteReader::need(self : ByteReader, n : Int) -> Unit raise BytecodeError {
  if self.remain() < n {
    raise Truncated(message="need \{n} bytes at \{self.pos}")
  }
}

///|
fn ByteReader::read_byte(self : ByteReader) -> Byte raise BytecodeError {
  self.need(1)
  let b = self.bytes[self.pos]
  self.pos = self.pos + 1
  b
}

///|
fn ByteReader::read_bytes(
  self : ByteReader,
  n : Int,
) -> Bytes raise BytecodeError {
  self.need(n)
  let start = self.pos
  self.pos = self.pos + n
  self.bytes.view(start~, end=self.pos).to_owned()
}

///|
fn ByteReader::read_u32(self : ByteReader) -> Int raise BytecodeError {
  self.read_i32()
}

///|
fn ByteReader::read_i32(self : ByteReader) -> Int raise BytecodeError {
  self.need(4)
  let b0 = self.bytes[self.pos].to_int()
  let b1 = self.bytes[self.pos + 1].to_int()
  let b2 = self.bytes[self.pos + 2].to_int()
  let b3 = self.bytes[self.pos + 3].to_int()
  self.pos = self.pos + 4
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
fn ByteReader::read_f64(self : ByteReader) -> Double raise BytecodeError {
  self.need(8)
  let b0 = self.bytes[self.pos].to_int64()
  let b1 = self.bytes[self.pos + 1].to_int64()
  let b2 = self.bytes[self.pos + 2].to_int64()
  let b3 = self.bytes[self.pos + 3].to_int64()
  let b4 = self.bytes[self.pos + 4].to_int64()
  let b5 = self.bytes[self.pos + 5].to_int64()
  let b6 = self.bytes[self.pos + 6].to_int64()
  let b7 = self.bytes[self.pos + 7].to_int64()
  self.pos = self.pos + 8
  let bits = b0 |
    (b1 << 8) |
    (b2 << 16) |
    (b3 << 24) |
    (b4 << 32) |
    (b5 << 40) |
    (b6 << 48) |
    (b7 << 56)
  bits.reinterpret_as_double()
}

///|
fn ByteReader::read_string(self : ByteReader) -> String raise BytecodeError {
  let len = self.read_u32()
  if len < 0 {
    raise Truncated(message="negative string length")
  }
  let raw = self.read_bytes(len)
  @utf8.decode(raw) catch {
    _ => raise Truncated(message="invalid utf8 string")
  }
}
