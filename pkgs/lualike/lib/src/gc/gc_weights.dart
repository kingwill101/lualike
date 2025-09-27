/// Constant weights used by the garbage collector's credit based accounting.
///
/// These values are not real byte measurements. They express the relative cost
/// of allocating common runtime structures so that GC heuristics can react to
/// growth without needing the exact platform byte size. The numbers are based on
/// the previous heuristic estimations and can be tuned if the runtime behaviour
/// changes.
class GcWeights {
  GcWeights._();

  /// Base overhead for any GCObject header.
  static const int gcObjectHeader = 64;

  /// Additional overhead for Value wrappers irrespective of their payload.
  static const int valueBase = 128;

  /// Per entry cost for table slots stored inside a Value.
  static const int tableEntry = 48;

  /// Cost for retaining a metatable reference on a Value.
  static const int metatableRef = 64;

  /// Cost for each captured upvalue reference stored on a Value.
  static const int valueUpvalueRef = 8;

  /// String content scaling for either LuaString or plain Dart strings.
  static const int stringUnit = 2;

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
