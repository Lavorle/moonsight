///|
/// Runtime-facing screen definition (no source spans).
pub(all) struct ScreenDef {
  name : String
  root : SNode
} derive(Debug)

///|
/// Screen widget tree node after lowering.
pub(all) enum SNode {
  VBox(x~ : Double?, y~ : Double?, children~ : Array[SNode])
  HBox(x~ : Double?, y~ : Double?, children~ : Array[SNode])
  Fixed(x~ : Double, y~ : Double, w~ : Double?, h~ : Double?, children~ : Array[SNode])
  Text(ScreenText)
  Button(label~ : String, action~ : ScreenAction)
} derive(Debug)

///|
/// Text content for a screen text widget.
pub(all) enum ScreenText {
  Literal(String)
  SlotLabel(Int)
  Pref(String)
} derive(Debug, Eq)

///|
/// Closed action set for screen buttons (runtime-facing).
pub(all) enum ScreenAction {
  Return
  StartGame
  QuitToTitle
  ShowScreen(name~ : String, mode~ : String?)
  HideScreen(name~ : String?)
  SaveSlot(Int)
  LoadSlot(Int)
  SetPrefF(key~ : String, value~ : Double)
  SetPrefB(key~ : String, value~ : Bool)
  AdjustPref(key~ : String, delta~ : Double)
  Noop
} derive(Debug, Eq)
