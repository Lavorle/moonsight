///|
/// Errors raised while lowering screen AST to `ScreenDef` IR.
pub(all) suberror ScreenLowerError {
  /// `show_screen` mode must be `save`, `load`, or omitted.
  InvalidShowMode(mode~ : String, span~ : SourceSpan)
  /// `set_pref` value must be a number or bool literal.
  InvalidSetPrefType(key~ : String, span~ : SourceSpan)
} derive(Debug, Eq)

///|
/// Lower all screen decls in a unit to runtime `ScreenDef` trees.
pub fn lower_screens(screens : Array[ScreenDecl]) -> Array[ScreenDef] raise ScreenLowerError {
  let out : Array[ScreenDef] = []
  for decl in screens {
    out.push(lower_screen(decl))
  }
  out
}

///|
/// Lower one screen declaration.
pub fn lower_screen(decl : ScreenDecl) -> ScreenDef raise ScreenLowerError {
  let children = lower_nodes(decl.root_children)
  let root : SNode = match children {
    [] => SNode::VBox(x=None, y=None, children=[])
    [only] => only
    _ => SNode::VBox(x=None, y=None, children~)
  }
  { name: decl.name, root }
}

///|
fn lower_nodes(nodes : Array[ScreenNode]) -> Array[SNode] raise ScreenLowerError {
  let out : Array[SNode] = []
  for n in nodes {
    out.push(lower_node(n))
  }
  out
}

///|
fn lower_node(node : ScreenNode) -> SNode raise ScreenLowerError {
  match node {
    ScreenNode::VBox(x~, y~, children~, ..) =>
      SNode::VBox(x~, y~, children=lower_nodes(children))
    ScreenNode::HBox(x~, y~, children~, ..) =>
      SNode::HBox(x~, y~, children=lower_nodes(children))
    ScreenNode::Fixed(x~, y~, w~, h~, children~, ..) =>
      SNode::Fixed(x~, y~, w~, h~, children=lower_nodes(children))
    ScreenNode::Text(src~, ..) => SNode::Text(lower_text(src))
    ScreenNode::Button(label~, action~, span~) =>
      SNode::Button(label~, action=lower_action(action, span~))
  }
}

///|
fn lower_text(src : ScreenTextSrc) -> ScreenText {
  match src {
    ScreenTextSrc::Literal(s) => ScreenText::Literal(s)
    ScreenTextSrc::SlotLabel(i) => ScreenText::SlotLabel(i)
    ScreenTextSrc::Pref(k) => ScreenText::Pref(k)
  }
}

///|
fn lower_action(
  action : ScreenActionAst,
  span~ : SourceSpan,
) -> ScreenAction raise ScreenLowerError {
  match action {
    ScreenActionAst::Return => ScreenAction::Return
    ScreenActionAst::StartGame => ScreenAction::StartGame
    ScreenActionAst::QuitToTitle => ScreenAction::QuitToTitle
    ScreenActionAst::ShowScreen(name~, mode~) => {
      let mode = validate_show_mode(mode, span~)
      ScreenAction::ShowScreen(name~, mode~)
    }
    ScreenActionAst::HideScreen(name~) => ScreenAction::HideScreen(name~)
    ScreenActionAst::SaveSlot(i) => ScreenAction::SaveSlot(i)
    ScreenActionAst::LoadSlot(i) => ScreenAction::LoadSlot(i)
    ScreenActionAst::SetPref(key~, value~) => lower_set_pref(key, value, span~)
    ScreenActionAst::AdjustPref(key~, delta~) =>
      ScreenAction::AdjustPref(key~, delta~)
    ScreenActionAst::Noop => ScreenAction::Noop
  }
}

///|
fn validate_show_mode(
  mode : String?,
  span~ : SourceSpan,
) -> String? raise ScreenLowerError {
  match mode {
    None => None
    Some("save") => Some("save")
    Some("load") => Some("load")
    Some(other) => raise InvalidShowMode(mode=other, span~)
  }
}

///|
fn lower_set_pref(
  key : String,
  value : Expr,
  span~ : SourceSpan,
) -> ScreenAction raise ScreenLowerError {
  match value {
    Expr::Float(f) => ScreenAction::SetPrefF(key~, value=f)
    Expr::Int(n) => ScreenAction::SetPrefF(key~, value=n.to_double())
    Expr::Bool(b) => ScreenAction::SetPrefB(key~, value=b)
    Expr::Str(_) | Expr::Ident(_) => raise InvalidSetPrefType(key~, span~)
  }
}
