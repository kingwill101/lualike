/// Constant weights used by the garbage collector's credit-based accounting.
///
/// These numbers are not exact byte counts. They indicate the relative cost of
/// allocating common runtime structures so heuristics can react to growth even
/// though Dart does not expose precise allocation sizes.
class GcWeights {
  GcWeights._();

  /// Base overhead for any GCObject header.
  static const int gcObjectHeader = 64;

  /// Additional overhead for Value wrappers irrespective of payload.
  static const int valueBase = 128;

  /// Per entry cost for table slots stored inside a Value.
  static const int tableEntry = 48;

  /// Cost for retaining a metatable reference on a Value.
  static const int metatableRef = 64;

  /// Cost for each captured upvalue reference stored on a Value.
  static const int valueUpvalueRef = 8;

  /// String content scaling for either LuaString or plain Dart strings.
  ///
  /// We account 1 credit per character to approximate Lua's byte-based
  /// accounting so that `collectgarbage("count")` deltas line up with
  /// string lengths in KB (2^10). Using higher multipliers causes the
  /// long-string assertions in gc.lua (e.g., +2^13 before GC, then between
  /// +2^12 and +2^13 after one key is collected) to overshoot.
  static const int stringUnit = 1;

  // No fixed base for strings; we count by character length only.

  /// Base weight for an Environment.
  static const int environmentBase = 96;

  /// Per variable binding cost within an Environment.
  static const int environmentEntry = 40;

  /// Base cost for a Box wrapper.
  static const int boxBase = 40;

  /// Base cost for an Upvalue structure.
  static const int upvalueBase = 96;

  /// Additional storage when an upvalue captures a closed value.
  static const int upvalueClosedValue = 32;

  /// Base cost for a coroutine object.
  static const int coroutineBase = 192;

  /// Per stacked frame/environment a coroutine keeps alive.
  static const int coroutineEnvironmentRef = 32;
}
