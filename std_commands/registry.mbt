///|
/// Standard VN host command names (must match `script.builtin_externs`).
pub fn standard_host_names() -> Array[String] {
  [
    "audio.bgm", "audio.se", "flow.choice", "flow.jump", "flow.jump_if", "flow.jump_if_not",
    "flow.wait", "flow.yield", "layer.hide", "layer.move", "layer.show", "sys.save_hint",
    "text.begin", "text.end", "text.type", "trans.fade", "var.set",
  ]
}

///|
/// Director with the full Phase 1 standard host table registered.
///
/// Uses `register_fn` so runtime stays free of a dependency on this package.
pub fn standard_registry() -> @runtime.Director {
  let dir = @runtime.Director::new()
  dir.register_fn("text.begin", cmd_text_begin)
  dir.register_fn("text.type", cmd_text_type)
  dir.register_fn("text.end", cmd_text_end)
  dir.register_fn("layer.show", cmd_layer_show)
  dir.register_fn("layer.hide", cmd_layer_hide)
  dir.register_fn("layer.move", cmd_layer_move)
  dir.register_fn("flow.jump", cmd_flow_jump)
  dir.register_fn("flow.jump_if", cmd_flow_jump_if)
  dir.register_fn("flow.jump_if_not", cmd_flow_jump_if_not)
  dir.register_fn("flow.wait", cmd_flow_wait)
  dir.register_fn("flow.yield", cmd_flow_yield)
  dir.register_fn("flow.choice", cmd_flow_choice)
  dir.register_fn("var.set", cmd_var_set)
  dir.register_fn("audio.bgm", cmd_audio_bgm)
  dir.register_fn("audio.se", cmd_audio_se)
  dir.register_fn("trans.fade", cmd_trans_fade)
  dir.register_fn("sys.save_hint", cmd_sys_save_hint)
  dir
}
