import 'package:lualike/src/testing/testing.dart';

/// Represents a reference to a variable in an outer scope (an "upvalue").
///
/// This object tracks whether the variable is still accessible on the stack
/// (open) or if its value has been captured because the original variable
/// went out of scope (closed).
class Upvalue {
  /// A direct reference to the Box holding the variable in its defining environment.
  final Box<dynamic> valueBox;

  /// Optional original name of the variable for debugging.
  final String? name;

  /// Indicates if the upvalue still refers to the live variable Box.
  bool _isOpen = true;
  bool get isOpen => _isOpen;

  /// Stores the value at the time of closing if [_isOpen] becomes false.
  dynamic _closedValue;

  Upvalue({required this.valueBox, this.name});

  /// Gets the current value of the upvalue.
  ///
  /// Returns the value from the original Box if open, or the captured
  /// closed value otherwise.
  dynamic getValue() {
    return _isOpen ? valueBox.value : _closedValue;
  }

  /// Sets the value of the upvalue.
  ///
  /// Updates the value in the original Box if open.
  /// Throws an error if trying to set a closed upvalue.
  void setValue(dynamic newValue) {
    if (_isOpen) {
      // TODO: Consider const checking here eventually, based on valueBox.isConst
      valueBox.value = newValue;
    } else {
      // In standard Lua, assigning to a closed upvalue shouldn't happen
      // because the variable itself is gone. We might refine this error.
      throw LuaError(
        'Cannot set value of a closed upvalue: ${name ?? 'unknown'}',
      );
    }
  }

  /// Closes the upvalue, capturing the current value.
  ///
  /// This should be called when the environment containing the original [valueBox]
  /// is being removed or goes out of scope, but the upvalue is still referenced
  /// by an active closure.
  void close() {
    if (_isOpen) {
      _closedValue = valueBox.value;
      _isOpen = false;
    }
  }

  @override
  String toString() {
    final status = _isOpen ? 'open' : 'closed';
    final value = _isOpen ? valueBox.value : _closedValue;
    return 'Upvalue[${name ?? 'unnamed'}]($status, value: $value)';
  }
}
