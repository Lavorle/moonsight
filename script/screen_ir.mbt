///|
/// Runtime-facing screen definition (no source spans).
pub(all) struct ScreenDef {
  name : String
  root : SNode
} derive(Debug, ToJson, FromJson)

///|
/// Screen widget tree node after lowering.
pub(all) enum SNode {
  VBox(x~ : Double?, y~ : Double?, children~ : Array[SNode])
  HBox(x~ : Double?, y~ : Double?, children~ : Array[SNode])
  Fixed(x~ : Double, y~ : Double, w~ : Double?, h~ : Double?, children~ : Array[SNode])
  Text(ScreenText)
  Button(label~ : String, action~ : ScreenAction)
} derive(Debug, ToJson, FromJson)

///|
/// Text content for a screen text widget.
pub(all) enum ScreenText {
  Literal(String)
  SlotLabel(Int)
  Pref(String)
} derive(Debug, Eq, ToJson, FromJson)

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
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Dist/host payload for `screens.json` next to `game.msb`.
pub(all) struct ScreensFile {
  save_slots : Int
  defs : Array[ScreenDef]
} derive(Debug, ToJson, FromJson)

///|
/// Serialize screen defs + slot count for host boot.
pub fn encode_screens_file(defs : Array[ScreenDef], save_slots~ : Int) -> String {
  let file : ScreensFile = { save_slots, defs }
  file.to_json().stringify(indent=2) + "\n"
}

///|
/// Parse `screens.json`. Raises on invalid JSON / shape.
pub fn decode_screens_file(text : String) -> ScreensFile raise {
  let j = @json.parse(text)
  @json.from_json(j)
}
