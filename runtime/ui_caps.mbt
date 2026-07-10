///|
/// Closed host surface for UI button handlers (no free-form action strings).
///
/// Engine / test doubles implement this; handlers receive `&Capabilities`.
pub(open) trait Capabilities {
  fn start_game(Self) -> Unit
  fn quit_to_title(Self) -> Unit
  fn show_modal(Self, String, mode~ : String?) -> Unit
  fn return_modal(Self) -> Unit
  fn hide_modal(Self, name~ : String?) -> Unit
  fn save_slot(Self, Int) -> Unit
  fn load_slot(Self, Int) -> Unit
  fn slot_occupied(Self, Int) -> Bool
  fn slot_label(Self, Int) -> String
  fn set_pref_f(Self, String, Double) -> Unit
  fn set_pref_b(Self, String, Bool) -> Unit
  fn adjust_pref(Self, String, Double) -> Unit
  fn confirm_choice(Self, Int) -> Unit
  fn advance(Self) -> Unit
  fn prefs(Self) -> Prefs
}
