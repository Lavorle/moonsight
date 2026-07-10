///|
/// Default button geometry (matches Phase 3 screen layout constants).
let ui_btn_w : Float = 400.0

///|
let ui_btn_h : Float = 52.0

///|
let ui_line_h : Float = 64.0

///|
let ui_font_size : Float = 30.0

///|
let ui_dim_opacity : Float = 0.55

///|
let ui_z_dim : Int = 2000

///|
let ui_z_widget : Int = 2100

///|
let ui_res_button : String = "ui.button"

///|
let ui_res_button_focus : String = "ui.button_focus"

///|
let ui_res_dim : String = "ui.menu_dim"

///|
/// Laid-out focusable with hit rect.
struct LaidFocus {
  target : UiFocusTarget
  x : Float
  y : Float
  w : Float
  h : Float
} derive(Debug)

///|
/// Mutable walk state for layout / paint / focus collection.
struct UiWalkState {
  ops : Array[UiDrawOp]
  focusables : Array[LaidFocus]
  bind : UiBindCtx
  focus_index : Int
  mut focus_counter : Int
  paint : Bool
} derive(Debug)

///|
/// Runtime: modal stack, focus, layout, and paint ops over a `UiApp` tree.
pub(all) struct UiRuntime {
  app : UiApp
  mut mode : UiMode
  mut stack : Array[ModalInstance]
  mut save_slots : Int
  mut prefs : Prefs
  /// Last bind context (updated by paint_* / sync_bind); used by input paths.
  mut bind : UiBindCtx
  /// Focus index when no modal is open (HUD choices).
  mut hud_focus : Int
}

///|
/// Fresh runtime from a UiApp definition. Clamps `save_slots` to 1..20.
pub fn UiRuntime::from_app(app : UiApp, save_slots~ : Int) -> UiRuntime {
  let n = if save_slots < 1 {
    1
  } else if save_slots > 20 {
    20
  } else {
    save_slots
  }
  {
    app,
    mode: Title,
    stack: [],
    save_slots: n,
    prefs: Prefs::default(),
    bind: UiBindCtx::empty(),
    hud_focus: 0,
  }
}

///|
/// Store bind context for subsequent focus / activate / pointer.
pub fn UiRuntime::sync_bind(self : UiRuntime, bind : UiBindCtx) -> Unit {
  self.bind = bind
}

///|
/// Number of modals currently on the stack.
pub fn UiRuntime::stack_depth(self : UiRuntime) -> Int {
  self.stack.length()
}

///|
/// Push a modal. From `Playing`, switches to `Menu`.
pub fn UiRuntime::show_modal(
  self : UiRuntime,
  name : String,
  mode? : String,
) -> Unit {
  if self.mode is Playing {
    self.mode = Menu
  }
  self.stack.push({ name, mode, focus: 0 })
}

///|
/// Pop one modal. If the stack empties while in `Menu`, return to `Playing`.
pub fn UiRuntime::return_modal(self : UiRuntime) -> Unit {
  if self.stack.is_empty() {
    return
  }
  ignore(self.stack.pop())
  if self.stack.is_empty() && (self.mode is Menu) {
    self.mode = Playing
  }
}

///|
/// Hide by name (remove matching stack entries) or pop top when name is omitted.
pub fn UiRuntime::hide_modal(self : UiRuntime, name? : String) -> Unit {
  match name {
    None => self.return_modal()
    Some(n) => {
      if self.stack.is_empty() {
        return
      }
      let kept : Array[ModalInstance] = []
      for inst in self.stack {
        if inst.name != n {
          kept.push(inst)
        }
      }
      self.stack = kept
      if self.stack.is_empty() && (self.mode is Menu) {
        self.mode = Playing
      }
    }
  }
}

///|
/// Move focus by `delta`, wrapping within the current focusable list.
pub fn UiRuntime::focus_delta(
  self : UiRuntime,
  _caps : &Capabilities,
  delta : Int,
) -> Unit {
  let items = self.current_focusables(self.bind)
  let n = items.length()
  if n == 0 {
    return
  }
  if self.stack.is_empty() {
    self.hud_focus = ui_wrap_index(self.hud_focus + delta, n)
    return
  }
  let i = self.stack.length() - 1
  let cur = self.stack[i]
  let next = ui_wrap_index(cur.focus + delta, n)
  self.stack[i] = { ..cur, focus: next }
}

///|
/// Activate the focused focusable (button handler or choice confirm).
/// Slider activate is a no-op (use MenuLeft/Right to adjust).
pub fn UiRuntime::activate(self : UiRuntime, caps : &Capabilities) -> Unit {
  let items = self.current_focusables(self.bind)
  if items.is_empty() {
    return
  }
  let idx = self.clamped_focus(items.length())
  self.set_focus_index(idx)
  match items[idx].target {
    UiFocusTarget::Button(action_id) => self.app.invoke(action_id, caps)
    UiFocusTarget::Choice(i) => caps.confirm_choice(i)
    UiFocusTarget::Slider(_) => ()
  }
}

///|
/// When focus is a Slider, nudge its pref by `direction` × key-specific step.
///
/// `direction` sign selects left (−) or right (+). No-op if focus is not a Slider.
pub fn UiRuntime::slider_delta(
  self : UiRuntime,
  caps : &Capabilities,
  direction : Int,
) -> Unit {
  let items = self.current_focusables(self.bind)
  if items.is_empty() {
    return
  }
  let idx = self.clamped_focus(items.length())
  match items[idx].target {
    UiFocusTarget::Slider(key) => {
      let step = slider_step_for_key(key)
      let delta = if direction < 0 { 0.0 - step } else { step }
      caps.adjust_pref(key, delta)
    }
    _ => ()
  }
}

///|
/// Hit-test focusables under (x,y); set focus and activate on hit.
pub fn UiRuntime::handle_pointer(
  self : UiRuntime,
  caps : &Capabilities,
  x : Double,
  y : Double,
) -> Unit {
  let items = self.current_focusables(self.bind)
  if items.is_empty() {
    return
  }
  let px = Float::from_double(x)
  let py = Float::from_double(y)
  let mut i = 0
  while i < items.length() {
    let f = items[i]
    if px >= f.x && px < f.x + f.w && py >= f.y && py < f.y + f.h {
      self.set_focus_index(i)
      match f.target {
        UiFocusTarget::Button(action_id) => self.app.invoke(action_id, caps)
        UiFocusTarget::Choice(ci) => caps.confirm_choice(ci)
        UiFocusTarget::Slider(_) => ()
      }
      return
    }
    i = i + 1
  }
}

///|
/// Paint the top modal (and optional dim veil). Empty when stack is empty.
pub fn UiRuntime::paint_modal(
  self : UiRuntime,
  canvas_w~ : Double,
  canvas_h~ : Double,
  bind~ : UiBindCtx,
) -> Array[UiDrawOp] {
  if self.stack.is_empty() {
    self.bind = bind
    return []
  }
  let top = self.stack[self.stack.length() - 1]
  let bind2 = {
    ..bind,
    modal_mode: match top.mode {
      Some(m) => Some(m)
      None => bind.modal_mode
    },
  }
  self.bind = bind2
  let ops : Array[UiDrawOp] = []
  // Pin: dim when Menu or nested stack (depth > 1). Root Title alone undimmed.
  if (self.mode is Menu) || self.stack.length() > 1 {
    ops.push(
      {
        kind: 0,
        resource: ui_res_dim,
        x: 0.0,
        y: 0.0,
        w: Float::from_double(canvas_w),
        h: Float::from_double(canvas_h),
        opacity: ui_dim_opacity,
        z: ui_z_dim,
        text: None,
        font_size: 0.0,
        focused: false,
      },
    )
  }
  match self.app.modals.get(top.name) {
    None => ()
    Some(root) => {
      let st : UiWalkState = {
        ops,
        focusables: [],
        bind: bind2,
        focus_index: top.focus,
        focus_counter: 0,
        paint: true,
      }
      ignore(walk_ui_node(root, 0.0, 0.0, st))
      // Clamp stored focus if list shrank.
      let n = st.focusables.length()
      if n > 0 {
        let idx = ui_wrap_index(top.focus, n)
        if idx != top.focus {
          let i = self.stack.length() - 1
          let cur = self.stack[i]
          self.stack[i] = { ..cur, focus: idx }
        }
      }
    }
  }
  ops
}

///|
/// Paint the HUD root. Caller decides when HUD is shown.
pub fn UiRuntime::paint_hud(
  self : UiRuntime,
  canvas_w~ : Double,
  canvas_h~ : Double,
  bind~ : UiBindCtx,
) -> Array[UiDrawOp] {
  ignore(canvas_w)
  ignore(canvas_h)
  self.bind = bind
  let ops : Array[UiDrawOp] = []
  match self.app.hud {
    None => ()
    Some(root) => {
      let st : UiWalkState = {
        ops,
        focusables: [],
        bind,
        focus_index: self.hud_focus,
        focus_counter: 0,
        paint: true,
      }
      ignore(walk_ui_node(root, 0.0, 0.0, st))
      let n = st.focusables.length()
      if n > 0 {
        self.hud_focus = ui_wrap_index(self.hud_focus, n)
      }
    }
  }
  ops
}

///|
/// Focus targets on the top modal (empty when no stack).
pub fn UiRuntime::focusables_top(
  self : UiRuntime,
  bind : UiBindCtx,
) -> Array[UiFocusTarget] {
  let laid = self.collect_modal_focusables(bind)
  let out : Array[UiFocusTarget] = []
  for f in laid {
    out.push(f.target)
  }
  out
}

///|
fn UiRuntime::current_focusables(
  self : UiRuntime,
  bind : UiBindCtx,
) -> Array[LaidFocus] {
  if self.stack.is_empty() {
    self.collect_hud_focusables(bind)
  } else {
    self.collect_modal_focusables(bind)
  }
}

///|
fn UiRuntime::collect_modal_focusables(
  self : UiRuntime,
  bind : UiBindCtx,
) -> Array[LaidFocus] {
  if self.stack.is_empty() {
    return []
  }
  let top = self.stack[self.stack.length() - 1]
  let bind2 = {
    ..bind,
    modal_mode: match top.mode {
      Some(m) => Some(m)
      None => bind.modal_mode
    },
  }
  match self.app.modals.get(top.name) {
    None => []
    Some(root) => {
      let st : UiWalkState = {
        ops: [],
        focusables: [],
        bind: bind2,
        focus_index: top.focus,
        focus_counter: 0,
        paint: false,
      }
      ignore(walk_ui_node(root, 0.0, 0.0, st))
      st.focusables
    }
  }
}

///|
fn UiRuntime::collect_hud_focusables(
  self : UiRuntime,
  bind : UiBindCtx,
) -> Array[LaidFocus] {
  match self.app.hud {
    None => []
    Some(root) => {
      let st : UiWalkState = {
        ops: [],
        focusables: [],
        bind,
        focus_index: self.hud_focus,
        focus_counter: 0,
        paint: false,
      }
      ignore(walk_ui_node(root, 0.0, 0.0, st))
      st.focusables
    }
  }
}

///|
fn UiRuntime::clamped_focus(self : UiRuntime, n : Int) -> Int {
  if self.stack.is_empty() {
    ui_wrap_index(self.hud_focus, n)
  } else {
    let cur = self.stack[self.stack.length() - 1]
    ui_wrap_index(cur.focus, n)
  }
}

///|
fn UiRuntime::set_focus_index(self : UiRuntime, idx : Int) -> Unit {
  if self.stack.is_empty() {
    self.hud_focus = idx
  } else {
    let i = self.stack.length() - 1
    let cur = self.stack[i]
    self.stack[i] = { ..cur, focus: idx }
  }
}

///|
/// Walk a node tree: optionally paint, always collect focusables when visible.
fn walk_ui_node(
  node : UiNode,
  origin_x : Float,
  origin_y : Float,
  st : UiWalkState,
) -> (Float, Float) {
  match node {
    UiNode::VBox(x~, y~, children~) => {
      let ox = opt_f(x, origin_x)
      let oy = opt_f(y, origin_y)
      let mut cy = oy
      let mut max_w : Float = 0.0
      for c in children {
        let (w, h) = walk_ui_node(c, ox, cy, st)
        if w > max_w {
          max_w = w
        }
        cy = cy + h
      }
      let total_h = cy - oy
      let zero : Float = 0.0
      (max_w, if total_h > zero { total_h } else { ui_line_h })
    }
    UiNode::HBox(x~, y~, children~) => {
      let ox = opt_f(x, origin_x)
      let oy = opt_f(y, origin_y)
      let mut cx = ox
      let mut max_h : Float = 0.0
      for c in children {
        let (w, h) = walk_ui_node(c, cx, oy, st)
        if h > max_h {
          max_h = h
        }
        cx = cx + w
      }
      let total_w = cx - ox
      let zero : Float = 0.0
      (if total_w > zero { total_w } else { ui_btn_w }, max_h)
    }
    UiNode::Fixed(x~, y~, children~, ..) => {
      // Absolute container: all children share the Fixed origin (no flow stack).
      let ox = Float::from_double(x)
      let oy = Float::from_double(y)
      for c in children {
        ignore(walk_ui_node(c, ox, oy, st))
      }
      (0.0, 0.0)
    }
    UiNode::Spacer(w~, h~) => (Float::from_double(w), Float::from_double(h))
    UiNode::Panel(resource~, x~, y~, w~, h~, visible~) => {
      if visible.eval(st.bind) && st.paint {
        st.ops.push(
          {
            kind: 0,
            resource: resource,
            x: Float::from_double(x),
            y: Float::from_double(y),
            w: Float::from_double(w),
            h: Float::from_double(h),
            opacity: 1.0,
            z: ui_z_widget,
            text: None,
            font_size: 0.0,
            focused: false,
          },
        )
      }
      (0.0, 0.0)
    }
    UiNode::Text(src~, x~, y~, font_size~, visible~) => {
      if !visible.eval(st.bind) {
        return (0.0, 0.0)
      }
      // node x/y are offsets from the parent flow origin (0 for modal titles).
      let px = origin_x + Float::from_double(x)
      let py = origin_y + Float::from_double(y)
      if st.paint {
        let label = src.resolve(st.bind)
        st.ops.push(
          {
            kind: 1,
            resource: "",
            x: px,
            y: py,
            w: ui_btn_w,
            h: ui_line_h,
            opacity: 1.0,
            z: ui_z_widget,
            text: Some(label),
            font_size: Float::from_double(font_size),
            focused: false,
          },
        )
      }
      // Take a line so VBox/HBox advance past title labels (Phase 3 parity).
      (ui_btn_w, ui_line_h)
    }
    UiNode::Image(resource~, x~, y~, w~, h~, visible~) => {
      if visible.eval(st.bind) && st.paint {
        st.ops.push(
          {
            kind: 0,
            resource: resource,
            x: Float::from_double(x),
            y: Float::from_double(y),
            w: Float::from_double(w),
            h: Float::from_double(h),
            opacity: 1.0,
            z: ui_z_widget,
            text: None,
            font_size: 0.0,
            focused: false,
          },
        )
      }
      (0.0, 0.0)
    }
    UiNode::Button(label~, action_id~, visible~) => {
      if !visible.eval(st.bind) {
        return (0.0, 0.0)
      }
      let idx = st.focus_counter
      st.focus_counter = idx + 1
      let focused = idx == st.focus_index
      st.focusables.push(
        {
          target: UiFocusTarget::Button(action_id),
          x: origin_x,
          y: origin_y,
          w: ui_btn_w,
          h: ui_btn_h,
        },
      )
      if st.paint {
        let res = if focused { ui_res_button_focus } else { ui_res_button }
        let opacity : Float = if focused { 1.0 } else { 0.75 }
        st.ops.push(
          {
            kind: 0,
            resource: res,
            x: origin_x,
            y: origin_y,
            w: ui_btn_w,
            h: ui_btn_h,
            opacity,
            z: ui_z_widget,
            text: Some(label),
            font_size: ui_font_size,
            focused,
          },
        )
      }
      (ui_btn_w, ui_line_h)
    }
    UiNode::Slider(key~, x~, y~, w~, h~, visible~) => {
      if !visible.eval(st.bind) {
        return (0.0, 0.0)
      }
      let px = origin_x + Float::from_double(x)
      let py = origin_y + Float::from_double(y)
      let bw = Float::from_double(w)
      let bh = Float::from_double(h)
      let idx = st.focus_counter
      st.focus_counter = idx + 1
      let focused = idx == st.focus_index
      st.focusables.push(
        {
          target: UiFocusTarget::Slider(key),
          x: px,
          y: py,
          w: bw,
          h: bh,
        },
      )
      if st.paint {
        let t = pref_normalized(st.bind.prefs, key)
        let fill_w = bw * Float::from_double(t)
        // Track (full width).
        st.ops.push(
          {
            kind: 0,
            resource: ui_res_button,
            x: px,
            y: py,
            w: bw,
            h: bh,
            opacity: if focused { 0.55 } else { 0.4 },
            z: ui_z_widget,
            text: None,
            font_size: 0.0,
            focused: false,
          },
        )
        // Fill proportional to normalized pref value.
        if fill_w > 0.0 {
          st.ops.push(
            {
              kind: 0,
              resource: if focused { ui_res_button_focus } else { ui_res_button },
              x: px,
              y: py,
              w: fill_w,
              h: bh,
              opacity: if focused { 1.0 } else { 0.85 },
              z: ui_z_widget,
              text: None,
              font_size: 0.0,
              focused,
            },
          )
        }
      }
      // Flow size: at least one button line so VBox advances past the control.
      let flow_h = if bh > ui_line_h { bh } else { ui_line_h }
      (bw, flow_h)
    }
    UiNode::ChoiceList(x~, y~, w~, line_h~, visible~) => {
      if !visible.eval(st.bind) {
        return (0.0, 0.0)
      }
      let bx = Float::from_double(x)
      let by = Float::from_double(y)
      let bw = Float::from_double(w)
      let lh = Float::from_double(line_h)
      let labels = st.bind.choice_labels
      let mut i = 0
      while i < labels.length() {
        let row_y = by + Float::from_int(i) * lh
        let idx = st.focus_counter
        st.focus_counter = idx + 1
        let focused = idx == st.focus_index
        st.focusables.push(
          {
            target: UiFocusTarget::Choice(i),
            x: bx,
            y: row_y,
            w: bw,
            h: lh - 8.0,
          },
        )
        if st.paint {
          let res = if focused { ui_res_button_focus } else { ui_res_button }
          let opacity : Float = if focused { 1.0 } else { 0.75 }
          let btn_h = if lh > 8.0 { lh - 8.0 } else { lh }
          st.ops.push(
            {
              kind: 0,
              resource: res,
              x: bx,
              y: row_y,
              w: bw,
              h: btn_h,
              opacity,
              z: ui_z_widget,
              text: Some(labels[i]),
              font_size: ui_font_size,
              focused,
            },
          )
        }
        i = i + 1
      }
      (0.0, 0.0)
    }
  }
}

///|
fn opt_f(v : Double?, fallback : Float) -> Float {
  match v {
    Some(d) => Float::from_double(d)
    None => fallback
  }
}

///|
/// Normalized 0..1 fill fraction for a prefs key.
fn pref_normalized(prefs : Prefs, key : String) -> Double {
  match key {
    "text_speed" => (prefs.text_speed - 0.25) / (3.0 - 0.25)
    "master_volume" => prefs.master_volume
    "bgm_volume" => prefs.bgm_volume
    "se_volume" => prefs.se_volume
    _ => 0.0
  }
}

///|
/// MenuLeft/Right step for a slider prefs key.
fn slider_step_for_key(key : String) -> Double {
  match key {
    "text_speed" => 0.25
    _ => 0.1
  }
}

///|
/// Positive modulo wrap into `0..n-1`.
fn ui_wrap_index(i : Int, n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  let m = i % n
  if m < 0 {
    m + n
  } else {
    m
  }
}
