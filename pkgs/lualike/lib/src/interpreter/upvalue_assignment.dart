import 'package:lualike/src/value.dart';
import 'package:lualike/src/logging/logger.dart';

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
        Logger.debug(
          'UpvalueAssignment: Updating upvalue $varName from ${upvalue.getValue()} to ${newValue.raw}',
          category: 'UpvalueAssignment',
        );
        upvalue.setValue(newValue.raw);
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
