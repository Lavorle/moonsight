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
let ui_res_button_hover : String = "ui.button_hover"

///|
let ui_res_choice : String = "ui.choice_row"

///|
let ui_res_choice_focus : String = "ui.choice_row_focus"

///|
let ui_res_choice_hover : String = "ui.choice_row_hover"

///|
let ui_res_slider_track : String = "ui.slider_track"

///|
let ui_res_slider_fill : String = "ui.slider_fill"

///|
let ui_res_dim : String = "ui.menu_dim"

///|
let ui_scroll_bar_w : Float = 16.0

///|
let ui_scroll_thumb_min_h : Float = 24.0

///|
let ui_res_scroll_track : String = "ui.scroll_track"

///|
let ui_res_scroll_thumb : String = "ui.scroll_thumb"

///|
/// Active ScrollView pointer drag (content pan or scrollbar thumb/track).
enum ScrollDrag {
  Idle
  Content(Double)
  Bar
} derive(Debug)

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
  /// Hovered focusable index (-1 = none).
  hover_index : Int
  mut focus_counter : Int
  paint : Bool
  /// When true, drop ops/focusables that do not intersect the clip rect.
  mut clip_active : Bool
  mut clip_x : Float
  mut clip_y : Float
  mut clip_w : Float
  mut clip_h : Float
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
  /// Hovered focusable index (-1 = none).
  mut hover : Int
  /// Vertical scroll offset for the active ScrollView (not saved).
  mut scroll_y : Double
  /// Measured content height of the active ScrollView.
  mut scroll_content_h : Double
  mut scroll_vp_x : Float
  mut scroll_vp_y : Float
  mut scroll_vp_w : Float
  mut scroll_vp_h : Float
  mut scroll_bar_w : Float
  /// When true, next ScrollView measure sets `scroll_y` to `scroll_max()` (pin to newest).
  mut pin_on_next_layout : Bool
  /// Active content-pan / scrollbar drag (not saved).
  mut scroll_drag : ScrollDrag
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
    hover: -1,
    scroll_y: 0.0,
    scroll_content_h: 0.0,
    scroll_vp_x: 0.0,
    scroll_vp_y: 0.0,
    scroll_vp_w: 0.0,
    scroll_vp_h: 0.0,
    scroll_bar_w: ui_scroll_bar_w,
    pin_on_next_layout: false,
    scroll_drag: Idle,
  }
}

///|
/// Maximum scroll_y for the last measured ScrollView (`max(0, content_h - vp_h)`).
pub fn UiRuntime::scroll_max(self : UiRuntime) -> Double {
  let m = self.scroll_content_h - self.scroll_vp_h.to_double()
  if m > 0.0 {
    m
  } else {
    0.0
  }
}

///|
fn UiRuntime::clamp_scroll(self : UiRuntime) -> Unit {
  let max = self.scroll_max()
  if self.scroll_y < 0.0 {
    self.scroll_y = 0.0
  }
  if self.scroll_y > max {
    self.scroll_y = max
  }
}

///|
/// Adjust vertical scroll by `delta` logical px, clamped to `[0, scroll_max()]`.
pub fn UiRuntime::scroll_by(self : UiRuntime, delta : Double) -> Unit {
  self.scroll_y = self.scroll_y + delta
  self.clamp_scroll()
}

///|
/// Pin scroll to the newest content (bottom). If content is not yet measured,
/// defers via `pin_on_next_layout` until the next ScrollView layout walk.
pub fn UiRuntime::pin_scroll_end(self : UiRuntime) -> Unit {
  if self.scroll_content_h <= 0.0 || self.scroll_vp_h.to_double() <= 0.0 {
    self.pin_on_next_layout = true
  } else {
    self.scroll_y = self.scroll_max()
  }
}

///|
/// True when `(x, y)` lies inside the last measured ScrollView viewport.
fn point_in_scroll_viewport(rt : UiRuntime, x : Double, y : Double) -> Bool {
  let vx = rt.scroll_vp_x.to_double()
  let vy = rt.scroll_vp_y.to_double()
  let vw = rt.scroll_vp_w.to_double()
  let vh = rt.scroll_vp_h.to_double()
  x >= vx && y >= vy && x < vx + vw && y < vy + vh
}

///|
/// True when content overflows the viewport (scrollbar is shown).
fn UiRuntime::scroll_overflows(self : UiRuntime) -> Bool {
  self.scroll_content_h > self.scroll_vp_h.to_double() + 0.0
}

///|
/// Thumb height for the last measured ScrollView (min `ui_scroll_thumb_min_h`).
fn UiRuntime::scroll_thumb_h(self : UiRuntime) -> Float {
  let vh = self.scroll_vp_h
  let ch = Float::from_double(self.scroll_content_h)
  if ch <= 0.0 {
    return vh
  }
  let ratio = vh / ch
  let mut thumb_h = vh * ratio
  if thumb_h < ui_scroll_thumb_min_h {
    thumb_h = ui_scroll_thumb_min_h
  }
  if thumb_h > vh {
    thumb_h = vh
  }
  thumb_h
}

///|
/// Thumb top y for the last measured ScrollView.
fn UiRuntime::scroll_thumb_y(self : UiRuntime) -> Float {
  let vh = self.scroll_vp_h
  let vy = self.scroll_vp_y
  let thumb_h = self.scroll_thumb_h()
  let max_scroll = self.scroll_max()
  let travel = vh - thumb_h
  if max_scroll > 0.0 && travel > 0.0 {
    vy + Float::from_double(self.scroll_y / max_scroll) * travel
  } else {
    vy
  }
}

///|
/// Track x for the scrollbar (right edge of viewport).
fn UiRuntime::scroll_track_x(self : UiRuntime) -> Float {
  self.scroll_vp_x + self.scroll_vp_w - self.scroll_bar_w
}

///|
/// Map pointer y so the thumb center follows the pointer; clamp scroll_y.
fn UiRuntime::map_bar_y_to_scroll(self : UiRuntime, y : Double) -> Unit {
  let max = self.scroll_max()
  if max <= 0.0 {
    self.scroll_y = 0.0
    return
  }
  let vy = self.scroll_vp_y.to_double()
  let vh = self.scroll_vp_h.to_double()
  let thumb_h = self.scroll_thumb_h().to_double()
  let travel = vh - thumb_h
  if travel <= 0.0 {
    self.scroll_y = 0.0
    return
  }
  let thumb_top = y - thumb_h / 2.0
  let t = (thumb_top - vy) / travel
  self.scroll_y = t * max
  self.clamp_scroll()
}

///|
/// Begin a content-pan drag at pointer y (tests + pointer down path).
pub fn UiRuntime::begin_scroll_drag_content(self : UiRuntime, y~ : Double) -> Unit {
  self.scroll_drag = Content(y)
}

///|
/// End any active scroll drag (pointer up / leave).
pub fn UiRuntime::end_scroll_drag(self : UiRuntime) -> Unit {
  self.scroll_drag = Idle
}

///|
/// While dragging: Content pans by dy; Bar maps y to scroll_y. No-op when Idle.
pub fn UiRuntime::pointer_scroll_move(self : UiRuntime, y~ : Double) -> Unit {
  match self.scroll_drag {
    Idle => ()
    Content(last_y) => {
      let dy = y - last_y
      self.scroll_y = self.scroll_y - dy
      self.clamp_scroll()
      self.scroll_drag = Content(y)
    }
    Bar => self.map_bar_y_to_scroll(y)
  }
}

///|
/// Wheel over viewport. `dy > 0` decreases `scroll_y` (reveal earlier lines).
/// Returns true if the event was consumed.
pub fn UiRuntime::handle_wheel(
  self : UiRuntime,
  x : Double,
  y : Double,
  dy : Double,
) -> Bool {
  if self.stack.is_empty() {
    return false
  }
  if !point_in_scroll_viewport(self, x, y) {
    return false
  }
  let k = 1.0 // logical px per dy unit; host can scale
  self.scroll_y = self.scroll_y - k * dy
  self.clamp_scroll()
  true
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
  // New modal layer: stale hover indices from the previous layer are invalid.
  self.hover = -1
  self.scroll_drag = Idle
  // Opening backlog pins scroll to newest (bottom) on next layout.
  if name == "backlog" {
    self.pin_on_next_layout = true
    self.scroll_y = 0.0
  }
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
  // Focusables changed with the stack; drop hover until next pointer_hover.
  self.hover = -1
  self.scroll_drag = Idle
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
      self.hover = -1
      self.scroll_drag = Idle
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
/// Hit-test focusables, then scrollbar, then ScrollView content.
///
/// Priority: focusable → thumb → track → content pan.
/// Focusable hit clears drag and activates. Scroll hits set `scroll_drag`.
/// Returns `true` if the event was consumed (so Engine does not Advance).
pub fn UiRuntime::handle_pointer(
  self : UiRuntime,
  caps : &Capabilities,
  x : Double,
  y : Double,
) -> Bool {
  let items = self.current_focusables(self.bind)
  let px = Float::from_double(x)
  let py = Float::from_double(y)
  let mut i = 0
  while i < items.length() {
    let f = items[i]
    if px >= f.x && px < f.x + f.w && py >= f.y && py < f.y + f.h {
      // Focusable wins over pan / scrollbar.
      self.scroll_drag = Idle
      self.set_focus_index(i)
      match f.target {
        UiFocusTarget::Button(action_id) => self.app.invoke(action_id, caps)
        UiFocusTarget::Choice(ci) => caps.confirm_choice(ci)
        UiFocusTarget::Slider(key) => {
          let t = (x - f.x.to_double()) / f.w.to_double()
          apply_slider_normalized(caps, key, t)
        }
      }
      return true
    }
    i = i + 1
  }
  // No focusable: scrollbar thumb / track / content pan.
  self.handle_pointer_scroll(x, y)
}

///|
/// ScrollView-only pointer down after focusable miss.
/// Thumb → Bar; track → jump + Bar; viewport content → Content drag.
fn UiRuntime::handle_pointer_scroll(
  self : UiRuntime,
  x : Double,
  y : Double,
) -> Bool {
  if self.stack.is_empty() {
    return false
  }
  if self.scroll_overflows() {
    let bar_w = self.scroll_bar_w.to_double()
    let track_x = self.scroll_track_x().to_double()
    let vy = self.scroll_vp_y.to_double()
    let vh = self.scroll_vp_h.to_double()
    let in_track = x >= track_x &&
      x < track_x + bar_w &&
      y >= vy &&
      y < vy + vh
    if in_track {
      let thumb_y = self.scroll_thumb_y().to_double()
      let thumb_h = self.scroll_thumb_h().to_double()
      let on_thumb = y >= thumb_y && y < thumb_y + thumb_h
      if on_thumb {
        self.scroll_drag = Bar
        return true
      }
      // Track (non-thumb): jump scroll from y ratio, then Bar for continued drag.
      self.map_bar_y_to_scroll(y)
      self.scroll_drag = Bar
      return true
    }
  }
  if point_in_scroll_viewport(self, x, y) {
    self.scroll_drag = Content(y)
    return true
  }
  false
}

///|
/// Hit-test focusables under (x,y); set hover index on hit, clear on miss.
/// Returns `true` if some focusable contains (x,y).
pub fn UiRuntime::pointer_hover(
  self : UiRuntime,
  x : Double,
  y : Double,
) -> Bool {
  let items = self.current_focusables(self.bind)
  if items.is_empty() {
    self.hover = -1
    return false
  }
  let px = Float::from_double(x)
  let py = Float::from_double(y)
  let mut i = 0
  while i < items.length() {
    let f = items[i]
    if px >= f.x && px < f.x + f.w && py >= f.y && py < f.y + f.h {
      self.hover = i
      return true
    }
    i = i + 1
  }
  self.hover = -1
  false
}

///|
/// Clear hover state (pointer left the canvas / UI) and end scroll drag.
pub fn UiRuntime::pointer_leave(self : UiRuntime) -> Unit {
  self.hover = -1
  self.scroll_drag = Idle
}

///|
/// Hovered focusable kind: 0=none, 1=button, 2=choice, 3=slider.
pub fn UiRuntime::hover_kind(self : UiRuntime) -> Int {
  if self.hover < 0 {
    return 0
  }
  let items = self.current_focusables(self.bind)
  if self.hover >= items.length() {
    return 0
  }
  match items[self.hover].target {
    UiFocusTarget::Button(_) => 1
    UiFocusTarget::Choice(_) => 2
    UiFocusTarget::Slider(_) => 3
  }
}

///|
/// Map a normalized 0..1 slider click ratio to a prefs value via `set_pref_f`.
fn apply_slider_normalized(caps : &Capabilities, key : String, t : Double) -> Unit {
  let t = if t < 0.0 { 0.0 } else if t > 1.0 { 1.0 } else { t }
  match key {
    "text_speed" => caps.set_pref_f(key, 0.25 + t * (3.0 - 0.25))
    "master_volume" | "bgm_volume" | "se_volume" => caps.set_pref_f(key, t)
    _ => ()
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
        hovered: false,
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
        hover_index: self.hover,
        focus_counter: 0,
        paint: true,
        clip_active: false,
        clip_x: 0.0,
        clip_y: 0.0,
        clip_w: 0.0,
        clip_h: 0.0,
      }
      ignore(walk_ui_node(root, 0.0, 0.0, st, self))
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
        hover_index: self.hover,
        focus_counter: 0,
        paint: true,
        clip_active: false,
        clip_x: 0.0,
        clip_y: 0.0,
        clip_w: 0.0,
        clip_h: 0.0,
      }
      ignore(walk_ui_node(root, 0.0, 0.0, st, self))
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
        hover_index: self.hover,
        focus_counter: 0,
        paint: false,
        clip_active: false,
        clip_x: 0.0,
        clip_y: 0.0,
        clip_w: 0.0,
        clip_h: 0.0,
      }
      ignore(walk_ui_node(root, 0.0, 0.0, st, self))
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
        hover_index: self.hover,
        focus_counter: 0,
        paint: false,
        clip_active: false,
        clip_x: 0.0,
        clip_y: 0.0,
        clip_w: 0.0,
        clip_h: 0.0,
      }
      ignore(walk_ui_node(root, 0.0, 0.0, st, self))
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
/// True when `(x,y,w,h)` intersects the active clip rect (or clip is off).
fn rect_intersects_clip(
  st : UiWalkState,
  x : Float,
  y : Float,
  w : Float,
  h : Float,
) -> Bool {
  if !st.clip_active {
    return true
  }
  // Reject when fully above/below or left/right of the viewport.
  if y + h <= st.clip_y || y >= st.clip_y + st.clip_h {
    return false
  }
  if x + w <= st.clip_x || x >= st.clip_x + st.clip_w {
    return false
  }
  true
}

///|
/// Walk a node tree: optionally paint, always collect focusables when visible.
fn walk_ui_node(
  node : UiNode,
  origin_x : Float,
  origin_y : Float,
  st : UiWalkState,
  rt : UiRuntime,
) -> (Float, Float) {
  match node {
    UiNode::VBox(x~, y~, children~) => {
      let ox = opt_f(x, origin_x)
      let oy = opt_f(y, origin_y)
      let mut cy = oy
      let mut max_w : Float = 0.0
      for c in children {
        let (w, h) = walk_ui_node(c, ox, cy, st, rt)
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
        let (w, h) = walk_ui_node(c, cx, oy, st, rt)
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
        ignore(walk_ui_node(c, ox, oy, st, rt))
      }
      (0.0, 0.0)
    }
    UiNode::Spacer(w~, h~) => (Float::from_double(w), Float::from_double(h))
    UiNode::Panel(resource~, x~, y~, w~, h~, visible~) => {
      let px = Float::from_double(x)
      let py = Float::from_double(y)
      let pw = Float::from_double(w)
      let ph = Float::from_double(h)
      if visible.eval(st.bind) &&
        st.paint &&
        rect_intersects_clip(st, px, py, pw, ph) {
        st.ops.push(
          {
            kind: 0,
            resource: resource,
            x: px,
            y: py,
            w: pw,
            h: ph,
            opacity: 1.0,
            z: ui_z_widget,
            text: None,
            font_size: 0.0,
            focused: false,
            hovered: false,
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
      if st.paint && rect_intersects_clip(st, px, py, ui_btn_w, ui_line_h) {
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
            hovered: false,
          },
        )
      }
      // Take a line so VBox/HBox advance past title labels (Phase 3 parity).
      (ui_btn_w, ui_line_h)
    }
    UiNode::Image(resource~, x~, y~, w~, h~, visible~) => {
      let px = Float::from_double(x)
      let py = Float::from_double(y)
      let pw = Float::from_double(w)
      let ph = Float::from_double(h)
      if visible.eval(st.bind) &&
        st.paint &&
        rect_intersects_clip(st, px, py, pw, ph) {
        st.ops.push(
          {
            kind: 0,
            resource: resource,
            x: px,
            y: py,
            w: pw,
            h: ph,
            opacity: 1.0,
            z: ui_z_widget,
            text: None,
            font_size: 0.0,
            focused: false,
            hovered: false,
          },
        )
      }
      (0.0, 0.0)
    }
    UiNode::Button(label~, action_id~, visible~) => {
      if !visible.eval(st.bind) {
        return (0.0, 0.0)
      }
      // Off-viewport focusables are dropped so indices match clipped hit list.
      if !rect_intersects_clip(st, origin_x, origin_y, ui_btn_w, ui_btn_h) {
        return (ui_btn_w, ui_line_h)
      }
      let idx = st.focus_counter
      st.focus_counter = idx + 1
      let focused = idx == st.focus_index
      let hovered = (!focused) && (idx == st.hover_index)
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
        let res = if focused {
          ui_res_button_focus
        } else if hovered {
          ui_res_button_hover
        } else {
          ui_res_button
        }
        let opacity : Float = if focused {
          1.0
        } else if hovered {
          0.9
        } else {
          0.75
        }
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
            hovered,
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
      let flow_h = if bh > ui_line_h { bh } else { ui_line_h }
      if !rect_intersects_clip(st, px, py, bw, bh) {
        return (bw, flow_h)
      }
      let idx = st.focus_counter
      st.focus_counter = idx + 1
      let focused = idx == st.focus_index
      let hovered = (!focused) && (idx == st.hover_index)
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
            resource: ui_res_slider_track,
            x: px,
            y: py,
            w: bw,
            h: bh,
            opacity: if focused {
              0.55
            } else if hovered {
              0.5
            } else {
              0.4
            },
            z: ui_z_widget,
            text: None,
            font_size: 0.0,
            focused: false,
            hovered: false,
          },
        )
        // Fill proportional to normalized pref value.
        if fill_w > 0.0 {
          st.ops.push(
            {
              kind: 0,
              resource: ui_res_slider_fill,
              x: px,
              y: py,
              w: fill_w,
              h: bh,
              opacity: if focused {
                1.0
              } else if hovered {
                0.95
              } else {
                0.85
              },
              z: ui_z_widget,
              text: None,
              font_size: 0.0,
              focused,
              hovered,
            },
          )
        }
      }
      // Flow size: at least one button line so VBox advances past the control.
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
        let btn_h = if lh > 8.0 { lh - 8.0 } else { lh }
        if rect_intersects_clip(st, bx, row_y, bw, btn_h) {
          let idx = st.focus_counter
          st.focus_counter = idx + 1
          let focused = idx == st.focus_index
          let hovered = (!focused) && (idx == st.hover_index)
          st.focusables.push(
            {
              target: UiFocusTarget::Choice(i),
              x: bx,
              y: row_y,
              w: bw,
              h: btn_h,
            },
          )
          if st.paint {
            let res = if focused {
              ui_res_choice_focus
            } else if hovered {
              ui_res_choice_hover
            } else {
              ui_res_choice
            }
            let opacity : Float = if focused {
              1.0
            } else if hovered {
              0.9
            } else {
              0.75
            }
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
                hovered,
              },
            )
          }
        }
        i = i + 1
      }
      (0.0, 0.0)
    }
    UiNode::ScrollView(x~, y~, w~, h~, children~) => {
      let vx = Float::from_double(x)
      let vy = Float::from_double(y)
      let vw = Float::from_double(w)
      let vh = Float::from_double(h)
      rt.scroll_vp_x = vx
      rt.scroll_vp_y = vy
      rt.scroll_vp_w = vw
      rt.scroll_vp_h = vh
      rt.scroll_bar_w = ui_scroll_bar_w
      // Measure pass: content height without painting or collecting focusables.
      let measure_st : UiWalkState = {
        ops: [],
        focusables: [],
        bind: st.bind,
        focus_index: -1,
        hover_index: -1,
        focus_counter: 0,
        paint: false,
        clip_active: false,
        clip_x: 0.0,
        clip_y: 0.0,
        clip_w: 0.0,
        clip_h: 0.0,
      }
      let mut content_h : Float = 0.0
      let mut content_w : Float = 0.0
      let mut my = vy
      for c in children {
        let (cw, ch) = walk_ui_node(c, vx, my, measure_st, rt)
        if cw > content_w {
          content_w = cw
        }
        my = my + ch
        content_h = content_h + ch
      }
      // VBox-like empty fallback is already handled by children; store measured h.
      rt.scroll_content_h = content_h.to_double()
      if rt.pin_on_next_layout {
        rt.scroll_y = rt.scroll_max()
        rt.pin_on_next_layout = false
      }
      rt.clamp_scroll()
      // Paint/hit pass: children shifted by -scroll_y; CPU-clip to viewport.
      let prev_clip = st.clip_active
      let prev_cx = st.clip_x
      let prev_cy = st.clip_y
      let prev_cw = st.clip_w
      let prev_ch = st.clip_h
      st.clip_active = true
      st.clip_x = vx
      st.clip_y = vy
      st.clip_w = vw
      st.clip_h = vh
      let origin_scrolled = vy - Float::from_double(rt.scroll_y)
      let mut py = origin_scrolled
      for c in children {
        let (_, ch) = walk_ui_node(c, vx, py, st, rt)
        py = py + ch
      }
      st.clip_active = prev_clip
      st.clip_x = prev_cx
      st.clip_y = prev_cy
      st.clip_w = prev_cw
      st.clip_h = prev_ch
      // Scrollbar track + thumb when content overflows the viewport.
      if st.paint && content_h > vh {
        let bar_w = rt.scroll_bar_w
        let track_x = rt.scroll_track_x()
        st.ops.push(
          {
            kind: 0,
            resource: ui_res_scroll_track,
            x: track_x,
            y: vy,
            w: bar_w,
            h: vh,
            opacity: 0.45,
            z: ui_z_widget,
            text: None,
            font_size: 0.0,
            focused: false,
            hovered: false,
          },
        )
        let thumb_h = rt.scroll_thumb_h()
        let thumb_y = rt.scroll_thumb_y()
        st.ops.push(
          {
            kind: 0,
            resource: ui_res_scroll_thumb,
            x: track_x,
            y: thumb_y,
            w: bar_w,
            h: thumb_h,
            opacity: 0.85,
            z: ui_z_widget,
            text: None,
            font_size: 0.0,
            focused: false,
            hovered: false,
          },
        )
      }
      // Absolute viewport like Panel: no flow size contribution.
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
