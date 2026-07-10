///|
/// Source for bound text widgets (literal or runtime fields).
pub(all) enum TextBindSrc {
  Literal(String)
  DialogueName
  DialogueBody
  Pref(String)
  SlotLabel(Int)
  Var(String)
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
  ChoiceList(
    x~ : Double,
    y~ : Double,
    w~ : Double,
    line_h~ : Double,
    visible~ : VisiblePred,
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
} derive(Debug)
