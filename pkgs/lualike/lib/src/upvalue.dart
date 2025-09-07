import 'package:lualike/lualike.dart';

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

  /// Joins this upvalue with another upvalue by sharing the same value box.
  ///
  /// This is used by debug.upvaluejoin to make two upvalues share the same storage.
  /// Since we can't modify the valueBox field (it's final), we'll make this upvalue
  /// point to the same value as the target upvalue by updating the value in our box.
  void joinWith(Upvalue other) {
    if (_isOpen && other._isOpen) {
      // Make this upvalue's box contain the same value as the other upvalue's box
      valueBox.value = other.valueBox.value;
    } else if (!_isOpen && !other._isOpen) {
      // Both are closed, copy the closed value
      _closedValue = other._closedValue;
    } else if (_isOpen && !other._isOpen) {
      // This is open, other is closed - set our box to the other's closed value
      valueBox.value = other._closedValue;
    } else {
      // This is closed, other is open - capture the other's current value
      _closedValue = other.valueBox.value;
    }
  }

  @override
  String toString() {
    final status = _isOpen ? 'open' : 'closed';
    final value = _isOpen ? valueBox.value : _closedValue;
    return 'Upvalue[${name ?? 'unnamed'}]($status, value: $value)';
  }
}
