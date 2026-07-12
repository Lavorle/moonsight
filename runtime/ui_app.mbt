///|
/// UI app definition: HUD root, named modals, and action_id → handler table.
///
/// Handlers stay off the node tree so `UiNode` remains data-like and tests can
/// invoke actions without a real Engine.
pub(all) struct UiApp {
  mut hud : UiNode?
  mut modals : Map[String, UiNode]
  mut handlers : Map[Int, (&Capabilities) -> Unit]
  mut next_action_id : Int
}

///|
/// Empty UiApp with no HUD, no modals, and empty handler table.
pub fn UiApp::new() -> UiApp {
  { hud: None, modals: {}, handlers: {}, next_action_id: 0 }
}

///|
/// Replace the base HUD tree.
pub fn UiApp::set_hud(self : UiApp, root : UiNode) -> Unit {
  self.hud = Some(root)
}

///|
/// Register or replace a named modal root.
pub fn UiApp::register_modal(self : UiApp, name : String, root : UiNode) -> Unit {
  self.modals[name] = root
}

///|
/// Allocate a monotonic action id and store `handler` under it.
pub fn UiApp::alloc_action(
  self : UiApp,
  handler : (&Capabilities) -> Unit,
) -> Int {
  let id = self.next_action_id
  self.next_action_id = id + 1
  self.handlers[id] = handler
  id
}

///|
/// Build a Button node with a freshly allocated action id for `handler`.
pub fn UiApp::button(
  self : UiApp,
  label : String,
  handler : (&Capabilities) -> Unit,
) -> UiNode {
  let id = self.alloc_action(handler)
  Button(label~, action_id=id, visible=Always)
}

///|
/// Run the handler registered for `action_id`, if any.
pub fn UiApp::invoke(
  self : UiApp,
  action_id : Int,
  caps : &Capabilities,
) -> Unit {
  match self.handlers.get(action_id) {
    None => ()
    Some(h) => h(caps)
  }
}
