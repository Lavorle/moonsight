///|
/// Standard VN host command names (must match `script.builtin_externs`).
pub fn standard_host_names() -> Array[String] {
  [
    "audio.bgm", "audio.se", "flow.choice", "flow.jump", "flow.jump_if", "flow.jump_if_not",
    "flow.wait", "flow.yield", "layer.hide", "layer.move", "layer.set", "layer.show",
    "sys.save_hint", "text.begin", "text.end", "text.type", "trans.dissolve", "trans.fade",
    "ui.hide", "ui.show", "var.set",
  ]
}

///|
/// Director with the full Phase 1 standard host table registered.
///
/// Uses explicit Director-owned effect descriptors for every standard command.
pub fn standard_registry() -> @runtime.Director {
  let dir = @runtime.Director::new()
  dir.register_fn_with_effect("text.begin", cmd_text_begin, Checkpointed)
  dir.register_fn_with_effect("text.type", cmd_text_type, Checkpointed)
  dir.register_fn_with_effect("text.end", cmd_text_end, Checkpointed)
  dir.register_fn_with_effect("layer.show", cmd_layer_show, Checkpointed)
  dir.register_fn_with_effect("layer.hide", cmd_layer_hide, Checkpointed)
  dir.register_fn_with_effect("layer.move", cmd_layer_move, Checkpointed)
  dir.register_fn_with_effect("layer.set", cmd_layer_set, Checkpointed)
  dir.register_fn_with_effect("flow.jump", cmd_flow_jump, Checkpointed)
  dir.register_fn_with_effect("flow.jump_if", cmd_flow_jump_if, Checkpointed)
  dir.register_fn_with_effect("flow.jump_if_not", cmd_flow_jump_if_not, Checkpointed)
  dir.register_fn_with_effect("flow.wait", cmd_flow_wait, Checkpointed)
  dir.register_fn_with_effect("flow.yield", cmd_flow_yield, Checkpointed)
  dir.register_fn_with_effect("flow.choice", cmd_flow_choice, Checkpointed)
  dir.register_fn_with_effect("var.set", cmd_var_set, Checkpointed)
  dir.register_fn_with_effect("audio.bgm", cmd_audio_bgm, CompensatableAudio)
  dir.register_fn_with_effect(
    "audio.se",
    cmd_audio_se,
    Barrier("rollback.barrier.audio-se"),
  )
  dir.register_fn_with_effect("trans.fade", cmd_trans_fade, Checkpointed)
  dir.register_fn_with_effect("trans.dissolve", cmd_trans_dissolve, Checkpointed)
  dir.register_fn_with_effect(
    "sys.save_hint",
    cmd_sys_save_hint,
    Barrier("rollback.barrier.save-hint"),
  )
  dir.register_fn_with_effect("ui.show", cmd_ui_show, Checkpointed)
  dir.register_fn_with_effect("ui.hide", cmd_ui_hide, Checkpointed)
  dir
}
