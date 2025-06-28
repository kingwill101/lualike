/// An abstract class representing a built-in function in the interpreter.
///
/// Built-in functions are implemented directly in Dart and provide core
/// functionality to the interpreted language. They can be called with a list
/// of arguments and return a value of any type.
abstract class BuiltinFunction {
  /// Executes the built-in function with the given arguments.
  ///
  /// [args] - The list of arguments passed to the function.
  /// Returns the result of the function call, which may be null.
  Object? call(List<Object?> args);
}
