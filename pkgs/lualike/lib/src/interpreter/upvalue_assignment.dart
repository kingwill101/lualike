import 'package:lualike/src/value.dart';
import 'package:lualike/src/logging/logger.dart';

Object? _rawUpvalueAssignmentValue(Object? value) =>
    value is Value ? value.raw : value;

/// Handler for upvalue assignments in functions
class UpvalueAssignmentHandler {
  /// Attempts to assign a value to an upvalue
  /// Returns true if assignment was handled, false if not an upvalue
  static bool tryAssignToUpvalue(
    String varName,
    Value newValue,
    Value? currentFunction,
  ) {
    if (currentFunction?.upvalues == null ||
        currentFunction!.upvalues!.isEmpty) {
      return false;
    }

    for (final upvalue in currentFunction.upvalues!) {
      if (upvalue.name == varName) {
        final rawNewValue = _rawUpvalueAssignmentValue(newValue);
        Logger.debugLazy(
          () =>
              'UpvalueAssignment: Updating upvalue $varName from ${upvalue.getValue()} to $rawNewValue',
          category: 'UpvalueAssignment',
          contextBuilder: () => {
            'varName': varName,
            'hasValue': upvalue.getValue() != null,
          },
        );
        upvalue.setValue(rawNewValue);
        return true;
      }
    }

    return false; // Variable name not found in upvalues
  }

  /// Gets the names of all upvalues for debugging
  static List<String> getUpvalueNames(Value? currentFunction) {
    if (currentFunction?.upvalues == null) return [];
    return currentFunction!.upvalues!
        .map((upvalue) => upvalue.name ?? '<unnamed>')
        .toList();
  }
}
