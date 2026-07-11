///|
/// Pending confirm dialog kind (overwrite save or quit to title).
pub(all) enum ConfirmKind {
  OverwriteSave(Int)
  QuitToTitle
} derive(Debug, Eq)

///|
/// Source for bound text widgets (literal or runtime fields).
pub(all) enum TextBindSrc {
  Literal(String)
  DialogueName
  DialogueBody
  Pref(String)
  SlotLabel(Int)
  Var(String)
  /// Preformatted backlog line at index `i` (0 = oldest of the bound window).
  BacklogLine(Int)
} derive(Debug, Eq)

///|
/// Predicate controlling whether a widget is visible this frame.
pub(all) enum VisiblePred {
  Always
  Never
  HasText
  HasChoices
  PrefBool(String)
  SlotOccupied(Int)
  ModeIs(String)
  /// Short-circuit conjunction of two predicates.
  And(VisiblePred, VisiblePred)
  /// Negation of an inner predicate (e.g. empty slot icons).
  Not(VisiblePred)
} derive(Debug, Eq)

///|
/// Retained UI tree node (data-like; actions are `action_id`s into UiApp).
pub(all) enum UiNode {
  VBox(x~ : Double?, y~ : Double?, children~ : Array[UiNode])
  HBox(x~ : Double?, y~ : Double?, children~ : Array[UiNode])
  Fixed(
    x~ : Double,
    y~ : Double,
    w~ : Double?,
    h~ : Double?,
    children~ : Array[UiNode],
  )
  Spacer(w~ : Double, h~ : Double)
  Panel(
    resource~ : String,
    x~ : Double,
    y~ : Double,
    w~ : Double,
    h~ : Double,
    visible~ : VisiblePred,
  )
  Text(
    src~ : TextBindSrc,
    x~ : Double,
    y~ : Double,
    font_size~ : Double,
    visible~ : VisiblePred,
  )
  Image(
    resource~ : String,
    x~ : Double,
    y~ : Double,
    w~ : Double,
    h~ : Double,
    visible~ : VisiblePred,
  )
  Button(label~ : String, action_id~ : Int, visible~ : VisiblePred)
  /// Horizontal pref slider; MenuLeft/Right adjust the named pref.
  Slider(
    key~ : String,
    x~ : Double,
    y~ : Double,
    w~ : Double,
    h~ : Double,
    visible~ : VisiblePred,
  )
  ChoiceList(
    x~ : Double,
    y~ : Double,
    w~ : Double,
    line_h~ : Double,
    visible~ : VisiblePred,
  )
  /// Vertical scroll viewport. Children laid out from top; runtime owns scroll_y.
  ScrollView(
    x~ : Double,
    y~ : Double,
    w~ : Double,
    h~ : Double,
    children~ : Array[UiNode],
  )
} derive(Debug)

///|
/// Paint request emitted by UI layout for the renderer.
pub(all) struct UiDrawOp {
  /// 0=sprite, 1=glyph-run marker handled by paint path
  kind : Int
  resource : String
  x : Float
  y : Float
  w : Float
  h : Float
  opacity : Float
  z : Int
  /// Optional label text for button/text (paint expands to glyphs)
  text : String?
  font_size : Float
  focused : Bool
  /// True when this focusable is hovered but not focused.
  hovered : Bool
} derive(Debug)

///|
/// One modal instance on the UiRuntime stack.
pub(all) struct ModalInstance {
  name : String
  /// Optional mode for multi-mode modals (e.g. save_load: "save" | "load").
  mode : String?
  /// Index into the current focusable list.
  focus : Int
} derive(Debug)

///|
/// Focusable target collected during layout (button, choice row, or slider key).
pub(all) enum UiFocusTarget {
  Button(Int)
  Choice(Int)
  /// Prefs key for `UiNode::Slider` (e.g. `master_volume`).
  Slider(String)
} derive(Debug, Eq)

///|
/// Bind context for VisiblePred, TextBindSrc, and ChoiceList expansion.
pub(all) struct UiBindCtx {
  has_text : Bool
  has_choices : Bool
  prefs : Prefs
  occupied : Array[Bool]
  modal_mode : String?
  vars : Map[String, String]
  choice_labels : Array[String]
  dialogue_name : String
  dialogue_body : String
  /// Bound backlog lines preformatted as "Name: text" (or bare text); newest last.
  /// Length is `min(store.len(), capacity)` from the engine ring (up to 100 by default).
  backlog_lines : Array[String]
  /// Per-slot labels (length = save_slots); resolved by `TextBindSrc::SlotLabel`.
  slot_labels : Array[String]
} derive(Debug)

///|
/// Empty bind context (no text, no choices, default prefs).
pub fn UiBindCtx::empty() -> UiBindCtx {
  {
    has_text: false,
    has_choices: false,
    prefs: Prefs::default(),
    occupied: [],
    modal_mode: None,
    vars: {},
    choice_labels: [],
    dialogue_name: "",
    dialogue_body: "",
    backlog_lines: [],
    slot_labels: [],
  }
}

///|
/// Evaluate a visibility predicate against bind context.
pub fn VisiblePred::eval(self : VisiblePred, bind : UiBindCtx) -> Bool {
  match self {
    Always => true
    Never => false
    HasText => bind.has_text
    HasChoices => bind.has_choices
    PrefBool(key) => pref_bool(bind.prefs, key)
    SlotOccupied(i) => {
      if i < 0 || i >= bind.occupied.length() {
        false
      } else {
        bind.occupied[i]
      }
    }
    ModeIs(m) =>
      match bind.modal_mode {
        Some(mm) => mm == m
        None => false
      }
    And(a, b) => a.eval(bind) && b.eval(bind)
    Not(inner) => !inner.eval(bind)
  }
}

///|
fn pref_bool(prefs : Prefs, key : String) -> Bool {
  match key {
    "auto_mode" => prefs.auto_mode
    _ => false
  }
}

///|
/// Resolve bound text for paint.
pub fn TextBindSrc::resolve(self : TextBindSrc, bind : UiBindCtx) -> String {
  match self {
    Literal(s) => s
    DialogueName => bind.dialogue_name
    DialogueBody => bind.dialogue_body
    Pref(key) => format_pref_bind(bind.prefs, key)
    SlotLabel(i) => {
      if i < 0 || i >= bind.slot_labels.length() {
        "Slot \{i} (empty)"
      } else {
        bind.slot_labels[i]
      }
    }
    Var(name) =>
      match bind.vars.get(name) {
        Some(s) => s
        None => ""
      }
    BacklogLine(i) => {
      if i < 0 || i >= bind.backlog_lines.length() {
        ""
      } else {
        bind.backlog_lines[i]
      }
    }
  }
}

///|
fn format_pref_bind(prefs : Prefs, key : String) -> String {
  match key {
    "text_speed" => "\{prefs.text_speed}"
    "auto_mode" => if prefs.auto_mode { "on" } else { "off" }
    "master_volume" => "\{prefs.master_volume}"
    "bgm_volume" => "\{prefs.bgm_volume}"
    "se_volume" => "\{prefs.se_volume}"
    _ => ""
  }
}
