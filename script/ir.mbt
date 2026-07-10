///|
/// Intermediate representation operations for a linearized scene script.
pub(all) enum IrOp {
  Nop
  Host(name~ : String, args~ : Array[IrValue])
  Jump(label~ : Int)
  JumpIf(cond~ : IrValue, label~ : Int)
  JumpIfNot(cond~ : IrValue, label~ : Int)
  /// IR-only marker; stripped when linearizing to bytecode.
  Label(Int)
  /// Wait for Advance intent.
  Yield
  Choose(options~ : Array[String], result_var~ : String)
  Return
} derive(Debug, Eq)

///|
/// Immediate or variable value carried by IR ops / host calls.
pub(all) enum IrValue {
  Int(Int)
  Float(Double)
  Bool(Bool)
  Str(String)
  Var(String)
  None_
} derive(Debug, Eq)

///|
/// Compiled module: named scenes plus default entry scene name.
pub(all) struct IrModule {
  scenes : Map[String, IrScene]
  /// Default `"entrypoint"` when present, else first scene, else `"entrypoint"`.
  entry : String
} derive(Debug)

///|
/// One scene's linearized op list.
pub(all) struct IrScene {
  name : String
  ops : Array[IrOp]
} derive(Debug)
