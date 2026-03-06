import 'dart:async';

import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/gc.dart';
import 'package:lualike/src/gc/gc_weights.dart';
import 'package:lualike/src/gc/gc_access.dart';
import 'package:lualike/src/gc/memory_credits.dart';
import 'dart:collection';

import 'package:lualike/src/stdlib/metatables.dart';
import 'package:lualike/src/upvalue.dart';
import 'package:lualike/src/utils/type.dart' show getLuaType;
import 'table_storage.dart';

/// Represents an asynchronous function that can be called with a list of arguments.
typedef AsyncFunction = Future<Object?> Function(List<Object?> args);

/// Represents a value in the LuaLike runtime system.
///
/// Values can hold any Dart object and optionally have an associated metatable
/// that defines their behavior for various operations. Values that represent
/// tables implement the Map interface for easy interaction with Dart code.
class Value extends Object implements Map<String, dynamic>, GCObject {
  /// The underlying raw value being wrapped.
  dynamic _raw;

  /// Monotonically increasing counter for table mutations so the interpreter
  /// can invalidate cached lookups when a table changes.
  int _tableVersion = 0;

  /// Optional metatable defining the value's behavior for various operations.
  Map<String, dynamic>? metatable;

  /// Cached weak mode from the last setMetatable call for table values.
  /// This preserves knowledge of '__mode' even if the metatable is freed
  /// later in the GC cycle, which is important for honoring weak semantics
  /// during finalization ordering.
  String? _cachedWeakMode;

  /// Reference to the original metatable Value when set via `setmetatable`.
  /// This allows `getmetatable` to return the same table object that was
  /// provided, preserving identity semantics required by Lua tests.
  Value? metatableRef;

  /// References to captured upvalues if this value represents a function/closure.
  List<Upvalue>? upvalues;

  /// The AST node representing the function body, if this value is a Lua function.
  FunctionBody? functionBody;

  /// Captured environment for Lua functions to support coroutine cloning.
  Environment? closureEnvironment;

  /// The name of the function, if this value is a named function.
  String? functionName;

  /// Whether this value is a multi-result value.
  bool isMulti = false;

  /// Whether this value is a constant (cannot be modified after initialization)
  bool isConst = false;

  /// Whether this value is a to-be-closed variable
  bool isToBeClose = false;

  /// Whether this value is a temporary key used for table lookups.
  /// Temporary keys are not counted for GC debt to avoid tracking overhead.
  bool isTempKey = false;

  /// Hint for fast-calling simple Lua closures (e.g., comparator x < y)
  /// Currently used to accelerate very common patterns in tight loops.
  bool isLessComparator = false;

  /// Hint for trivial closures that always return nil (e.g.,
  /// `function(x, y) return nil end`). This allows the interpreter to
  /// bypass creating an execution environment and skip the closure call,
  /// while still evaluating argument expressions for side effects.
  bool isNilReturningClosure = false;

  /// Hint for simple reversed comparator closures of the form
  /// `function(x, y) return y < x end`. Used to accelerate validation
  /// checks in tight loops.
  bool isLessComparatorReversed = false;

  /// Whether this value has been initialized (used for const variables)
  bool _isInitialized = false;

  /// Runtime instance (for functions)
  LuaRuntime? interpreter;

  /// Whether this value is marked for garbage collection
  bool _marked = false;

  /// Whether this value has been freed by the GC.
  bool _isFreed = false;

  /// Whether this value is old (used for garbage collection)
  @override
  bool isOld = false;

  /// Whether this object is eligible for finalization. Per Lua semantics, an
  /// object is only finalized if its metatable had a `__gc` field when the
  /// metatable was set (KIN-23). Adding `__gc` later does not retroactively
  /// make the object finalizable.
  bool finalizerEligible = false;

  @override
  int get estimatedSize {
    var size = GcWeights.gcObjectHeader + GcWeights.valueBase;
    if (isTable && raw is Map) {
      final map = raw as Map;
      size += map.length * GcWeights.tableEntry;
      // Count only RAW string keys, not Value-wrapped keys.
      // Value keys are separate GC objects already tracked; counting their
      // content again would double-count them.
      int? bytes = _tableStringKeyBytes[map];
      if (bytes == null) {
        var total = 0;
        try {
          for (final k in map.keys) {
            // Only count raw strings - Value keys are tracked separately
            if (k is String) {
              total += k.length * GcWeights.stringUnit;
            } else if (k is LuaString) {
              total += k.length * GcWeights.stringUnit;
            }
            // Removed: Don't count Value-wrapped strings - they're separate GC objects
          }
        } catch (_) {}
        _tableStringKeyBytes[map] = total;
        bytes = total;
      }
      size += bytes;
    }

    if (upvalues != null) {
      size += upvalues!.length * GcWeights.valueUpvalueRef;
    }

    if (metatable != null) {
      size += GcWeights.metatableRef;
    }

    final payload = raw;
    if (payload is LuaString) {
      size += payload.length * GcWeights.stringUnit;
    } else if (payload is String) {
      size += payload.length * GcWeights.stringUnit;
    }

    return size;
  }

  /// Get the raw value
  dynamic get raw => _raw;

  /// Whether this value represents a table
  bool get isTable => _raw is Map;

  /// Incrementing version that changes every time the underlying table mutates.
  int get tableVersion => _tableVersion;

  /// Gets the weak mode of this table from its metatable's __mode field.
  /// Returns null if this is not a table or has no __mode.
  /// Returns 'k' for weak keys, 'v' for weak values, 'kv' for both.
  String? get tableWeakMode {
    if (!isTable) return null;
    // Prefer the direct metatable field, but fall back to the globally
    // registered metatable for this raw Map so that alternate wrappers
    // (e.g., those seen during GC traversal) still observe weak modes.
    Map<String, dynamic>? mt = metatable;
    if (mt == null) {
      mt = _getRegisteredTableMetatable();
      if (mt == null) {
        // If no active metatable is found, use the cached mode if present.
        return _cachedWeakMode;
      }
    }
    dynamic mode = mt['__mode'];
    Logger.debugLazy(
      () =>
          'tableWeakMode raw metatable __mode: $mode '
          '(${mode.runtimeType})',
      category: 'Value',
    );
    if (mode is Value) {
      mode = mode.raw;
    }
    if (mode == null) return null;
    String modeStr;
    if (mode is LuaString) {
      modeStr = mode.toString();
    } else if (mode is String) {
      modeStr = mode;
    } else {
      modeStr = mode.toString();
    }
    if (modeStr.contains('k') && modeStr.contains('v')) return 'kv';
    if (modeStr.contains('k')) return 'k';
    if (modeStr.contains('v')) return 'v';
    return null;
  }

  /// Whether this table has weak values (does not mark through values)
  bool get hasWeakValues => tableWeakMode?.contains('v') ?? false;

  /// Whether this table has weak keys (ephemeron behavior)
  bool get hasWeakKeys => tableWeakMode?.contains('k') ?? false;

  /// Whether this table is all-weak (both keys and values are weak)
  bool get isAllWeak => tableWeakMode == 'kv';

  /// Cached-only check for weak-values mode, using the last observed
  /// '__mode' string from setMetatable. Useful when the live metatable is
  /// already freed but we still need to honor semantics for this cycle.
  bool get cachedHasWeakValues => _cachedWeakMode?.contains('v') ?? false;

  /// Set the raw value with attribute enforcement
  set raw(dynamic value) {
    if (isConst && _isInitialized) {
      throw UnsupportedError("attempt to assign to const variable");
    }
    dynamic normalized = value;
    if (normalized is Map) {
      if (normalized is TableStorage) {
        _canonicalTableStorage[normalized] ??= normalized;
      } else if (normalized is! MapBase<String, dynamic>) {
        normalized = _ensureCanonicalStorage(normalized);
      }
    }
    _raw = normalized;
    _isInitialized = true;
    if (normalized is Map) {
      _incrementTableVersion();
    } else {
      _tableVersion = 0;
    }
    final gcLocal1 = GCAccess.fromValue(this);
    if (gcLocal1 != null) {
      MemoryCredits.instance.recalculate(this);
    }
  }

  /// Creates a new Value wrapping the given raw value.
  ///
  /// [raw] - The value to wrap
  /// [metatable] - Optional metatable to associate with the value. If not
  /// provided, a default metatable may be applied based on the value's type.
  /// [isConst] - Whether this value is a constant
  /// [isToBeClose] - Whether this value is a to-be-closed variable
  /// [interpreter] - Runtime instance (for functions/coroutines)
  /// [functionName] - Name of the function (for debugging/debug.getinfo)
  Value(
    dynamic raw, {
    Map<String, dynamic>? metatable,
    this.isConst = false,
    this.isToBeClose = false,
    this.isTempKey = false,
    this.upvalues,
    this.interpreter,
    this.functionBody,
    this.closureEnvironment,
    this.functionName,
  }) {
    dynamic normalized = raw;
    if (normalized is Map) {
      if (normalized is TableStorage) {
        _canonicalTableStorage[normalized] ??= normalized;
      } else if (normalized is! MapBase<String, dynamic>) {
        normalized = _ensureCanonicalStorage(normalized);
      }
    }
    _raw = normalized;
    _isInitialized = true;
    _isFreed = false;

    // Register identity for table (Map) values so that future lookups
    // can return the canonical Value wrapper and preserve per-instance
    // metatables and identity-sensitive behavior like __lt.
    if (_raw is Map) {
      _registerTableIdentity(_raw as Map);
    }

    // If no metatable is provided, apply the default metatable for this type.
    // This mirrors Lua's behavior where strings, numbers, etc. share
    // common metatables giving them methods like string.find.
    if (metatable == null) {
      MetaTable().applyDefaultMetatable(this);
    } else {
      this.metatable = metatable;
    }

    // Always register with the GC so mark/unmark and separation logic
    // remains correct, but avoid charging allocation debt for
    // primitive-like wrappers to reduce auto-trigger overhead.
    final gcLocal2 = GCAccess.fromValue(this);
    gcLocal2?.register(this, countAllocation: _shouldCountAllocation());
  }

  // ---------------------------------------------------------------------------
  // Identity registry for table (Map) values
  // ---------------------------------------------------------------------------
  static final Expando<Value> _tableIdentity = Expando<Value>('tableIdentity');
  static final Expando<TableStorage> _canonicalTableStorage =
      Expando<TableStorage>('canonicalTableStorage');
  static final Expando<Map<String, dynamic>> _tableMetatables =
      Expando<Map<String, dynamic>>('tableMetatables');
  // Tracks total credits for string-like keys stored in the underlying Map.
  static final Expando<int> _tableStringKeyBytes = Expando<int>(
    'tableStringKeyBytes',
  );
  static final Expando<int> _tableDenseWriteDebt = Expando<int>(
    'tableDenseWriteDebt',
  );

  /// Adjusts cached string-key credits for a raw Map when entries are
  /// mutated externally (e.g., by the GC during weak-table clearing).
  /// [deltaChars] is character count; multiplied by stringUnit.
  static void adjustStringKeyCreditsForMap(
    Map map,
    Object? key,
    int deltaChars,
  ) {
    if (deltaChars == 0) return;
    try {
      final current = _tableStringKeyBytes[map] ?? 0;
      _tableStringKeyBytes[map] = current + deltaChars * GcWeights.stringUnit;
    } catch (_) {}
  }

  /// Invalidates the cached string-key credits for a raw Map.
  /// This forces estimatedSize to recalculate from scratch on next access.
  /// Used by GC when removing multiple keys to avoid double-decrement bugs.
  static void invalidateStringKeyCache(Map map) {
    try {
      _tableStringKeyBytes[map] = null;
    } catch (_) {}
  }

  void _registerTableIdentity(Map table) {
    try {
      _tableIdentity[table] = this;
    } catch (_) {
      // If Expando association fails for any reason, ignore; behavior remains correct
    }
  }

  static Value? _lookupTableIdentity(Object? table) {
    if (table is Map) {
      try {
        return _tableIdentity[table];
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Public helper to retrieve the canonical wrapper for a raw Map-backed
  /// table, if one is registered. Returns null if none is registered or the
  /// value is not a Map.
  static Value? lookupCanonicalTableWrapper(Object? table) {
    return _lookupTableIdentity(table);
  }

  static TableStorage _ensureCanonicalStorage(Map<dynamic, dynamic> map) {
    if (map is TableStorage) {
      _canonicalTableStorage[map] ??= map;
      return map;
    }
    final existing = _canonicalTableStorage[map];
    if (existing != null) {
      return existing;
    }
    final storage = TableStorage.from(map);
    _canonicalTableStorage[map] = storage;
    _canonicalTableStorage[storage] = storage;
    return storage;
  }

  /// Register [v] as the canonical wrapper for its underlying Map, so that
  /// subsequent lookups will return [v] and preserve its metatable/identity.
  static void registerTableIdentity(Value v) {
    if (v.raw is Map) {
      try {
        _tableIdentity[v.raw as Map] = v;
      } catch (_) {}
    }
  }

  /// Determines whether this Value should contribute allocation debt.
  ///
  /// Primitive-like wrappers are extremely common and cheap; we skip
  /// debt for them to avoid frequent auto-GC triggers in tight loops.
  bool _shouldCountAllocation() {
    if (isMulti) return false; // short-lived carrier, don't count
    if (isTempKey) {
      if (Logger.enabled) {
        Logger.debug(
          'Value $hashCode (${raw.runtimeType}) marked as temp key, NOT counting allocation',
          category: 'GC',
        );
      }
      return false; // temporary keys for table lookups, don't count
    }
    if (isTable) return true; // tables are significant
    final payload = raw;
    if (payload == null ||
        payload is bool ||
        payload is num ||
        payload is BigInt) {
      return false;
    }
    // Count strings to model Lua's GC pressure from string creation
    if (payload is String || payload is LuaString) {
      if (Logger.enabled) {
        final len = payload is String
            ? payload.length
            : (payload as LuaString).length;
        Logger.debug(
          'Value $hashCode wrapping ${payload.runtimeType}(len=$len), WILL count allocation',
          category: 'GC',
        );
      }
      return true;
    }
    return true;
  }

  bool isA<T>() {
    return raw is T;
  }

  /// Primitive-like values for weak-table semantics: numbers, booleans, nil,
  /// BigInt, and strings. In Lua's weak tables, strings and numbers behave as
  /// immediate values for clearing logic used by tests like gc.lua (e.g.,
  /// keeping number->string survivors in weak-values tables and allowing
  /// string->string survivors in all-weak tables).
  bool get isPrimitiveLike {
    final current = raw;
    return current == null ||
        current is bool ||
        current is num ||
        current is BigInt ||
        current is String ||
        current is LuaString;
  }

  bool get isStringLike {
    final current = raw;
    return current is String || current is LuaString;
  }

  factory Value.multi(List<dynamic> values) {
    final value = Value(values);
    value.isMulti = true;
    return value;
  }

  /// Creates a constant value that cannot be modified after initialization
  factory Value.constant(dynamic value, {Map<String, dynamic>? metatable}) {
    return Value(value, metatable: metatable, isConst: true);
  }

  /// Creates a to-be-closed value that will have its __close metamethod called when it goes out of scope
  ///
  /// ------------------------------------------------------------
  /// Internal helper: resolve the active runtime for this Value
  /// ------------------------------------------------------------
  /// We look in the following order:
  /// 1. `this.interpreter` field (set by libraries for closures/builtins)
  /// 2. If `raw` is a `BuiltinFunction`, use its interpreter
  /// 3. If `raw` is an AST Function node that captured an interpreter field
  /// 4. Otherwise, return null – callers must handle the unsupported case
  ///
  LuaRuntime? _resolveInterpreter() {
    if (interpreter != null) return interpreter;
    if (raw is BuiltinFunction) {
      return (raw as BuiltinFunction).interpreter;
    }
    // No interpreter found
    return null;
  }

  factory Value.toBeClose(dynamic value, {Map<String, dynamic>? metatable}) {
    if (value != null && value != false) {
      // Verify the value has a __close metamethod
      // If value is already a Value (like LuaFile), preserve it to keep its metamethods
      final tempValue = value is Value
          ? value
          : Value(value, metatable: metatable);
      if (!tempValue.hasMetamethod('__close')) {
        throw UnsupportedError(
          "to-be-closed variable value must have a __close metamethod",
        );
      }
    }
    // If value is already a Value (like LuaFile), create a new instance with isToBeClose flag
    // but preserve the original type and metamethods
    if (value is Value) {
      value.isToBeClose = true;
      return value;
    }
    return Value(value, metatable: metatable, isToBeClose: true);
  }

  /// Closes the value by calling its __close metamethod if it exists
  /// [error] - The error that caused the scope to exit, or null if normal exit
  Future<void> close([dynamic error]) async {
    if (!isToBeClose || raw == null || raw == false) {
      return; // Only close to-be-closed variables with non-false values
    }

    final closeMeta = getMetamethod('__close');
    if (closeMeta != null) {
      try {
        await callMetamethodAsync('__close', <Value>[
          this,
          error is Value ? error : Value(error),
        ]);
      } catch (e) {
        // Log the error but continue closing other variables
        Logger.error(
          'Error in __close metamethod',
          category: 'Value',
          error: e,
        );
        // Re-throw the error after closing
        rethrow;
      }
    }
  }

  /// Creates a deep copy of this Value and its metatable.
  ///
  /// For table values, recursively copies all nested values.
  /// Returns a new Value instance with copied contents.
  Value copy() {
    if (raw is Map) {
      // Deep copy for tables
      final newMap = <dynamic, dynamic>{};
      (raw as Map).forEach((key, value) {
        newMap[key] = value is Value ? value.copy() : Value(value).copy();
      });
      return Value(
        newMap,
        metatable: metatable != null ? Map.from(metatable!) : null,
        isConst: isConst,
        isToBeClose: isToBeClose,
        upvalues: upvalues,
        interpreter: interpreter,
        functionBody: functionBody,
        closureEnvironment: closureEnvironment,
        functionName: functionName,
      );
    }
    // For non-table values, copy with metatable
    return Value(
      raw,
      metatable: metatable != null ? Map.from(metatable!) : null,
      isConst: isConst,
      isToBeClose: isToBeClose,
      upvalues: upvalues,
      interpreter: interpreter,
      functionBody: functionBody,
      closureEnvironment: closureEnvironment,
      functionName: functionName,
    );
  }

  /// Gets the metatable associated with this value.
  ///
  /// Returns the metatable or null if none is set.
  Map<String, dynamic>? getMetatable() => metatable;
  Map<String, dynamic>? _getRegisteredTableMetatable() {
    if (raw is Map) {
      try {
        return _tableMetatables[raw as Map];
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Sets a new metatable for this value.
  ///
  /// [mt] - The new metatable to associate with this value.
  void setMetatable(Map<String, dynamic> mt) {
    metatable = mt;
    // Cache weak mode string for later semantics checks even if this
    // metatable is freed before finalization runs.
    try {
      final rawMode = mt['__mode'];
      String? modeStr;
      if (rawMode is LuaString) {
        modeStr = rawMode.toString();
      } else if (rawMode is Value) {
        modeStr = rawMode.raw?.toString();
      } else if (rawMode is String) {
        modeStr = rawMode;
      }
      if (modeStr != null) {
        if (modeStr.contains('k') && modeStr.contains('v')) {
          _cachedWeakMode = 'kv';
        } else if (modeStr.contains('k')) {
          _cachedWeakMode = 'k';
        } else if (modeStr.contains('v')) {
          _cachedWeakMode = 'v';
        } else {
          _cachedWeakMode = null;
        }
      } else {
        _cachedWeakMode = null;
      }
    } catch (_) {
      _cachedWeakMode = null;
    }
    if (raw is Map) {
      try {
        _tableMetatables[raw as Map] = mt;
      } catch (_) {}
    }
    final gcLocal3 = GCAccess.fromValue(this);
    if (gcLocal3 != null) {
      MemoryCredits.instance.recalculate(this);
    }
  }

  /// Looks up a metamethod in this value's metatable.
  ///
  /// [event] - The name of the metamethod to look up (e.g. "__add")
  /// Returns the metamethod if found, null otherwise.
  dynamic getMetamethod(String event) {
    if (metatable != null && metatable!.containsKey(event)) {
      var method = metatable![event];
      // If the metatable itself has weak values (via its own metatable's
      // __mode = 'v'), then a GC cycle may have logically cleared this entry
      // even if the raw map still contains it. Respect that by treating
      // unmarked GC values as absent when the owner metatable has weak values.
      if (metatableRef is Value) {
        final owner = metatableRef as Value;
        bool ownerWeakV =
            owner.isTable && (owner.hasWeakValues || owner.cachedHasWeakValues);
        if (!ownerWeakV && owner.isTable && owner.metatable == null) {
          // Fallback: inspect owner's metatableRef raw map for '__mode' even
          // if the live metatable is gone (e.g., freed earlier in GC). Keys
          // may be LuaString or Value-wrapped strings.
          try {
            final meta = owner.metatableRef;
            if (meta is Value && meta.raw is Map) {
              final m = meta.raw as Map;
              dynamic rawMode = m['__mode'];
              if (rawMode == null) {
                for (final k in m.keys) {
                  String? ks;
                  if (k is LuaString) {
                    ks = k.toString();
                  } else if (k is Value) {
                    final kr = k.raw;
                    if (kr is LuaString) {
                      ks = kr.toString();
                    } else if (kr is String) {
                      ks = kr;
                    }
                  }
                  if (ks == '__mode') {
                    rawMode = m[k];
                    break;
                  }
                }
              }
              String modeStr;
              if (rawMode is LuaString) {
                modeStr = rawMode.toString();
              } else if (rawMode is Value) {
                modeStr = rawMode.raw?.toString() ?? '';
              } else {
                modeStr = rawMode?.toString() ?? '';
              }
              if (modeStr.contains('v')) ownerWeakV = true;
            }
          } catch (_) {}
        }
        if (ownerWeakV) {
          if (Logger.enabled && event == '__gc') {
            Logger.debug(
              'getMetamethod("__gc"): owner=${owner.hashCode} weakMode=${owner.tableWeakMode} methodType=${method.runtimeType}',
              category: 'GC',
            );
          }
          // For __gc specifically, weak-values metatables should not drive
          // finalization; Lua tests rely on this pattern to ensure that
          // setting __gc under a weak-values metatable does not run.
          if (event == '__gc') {
            return null;
          }
          if (method is Value) {
            if (!method.isPrimitiveLike && (!method.marked || method.isFreed)) {
              return null;
            }
          } else if (method is GCObject) {
            if (!method.marked) return null;
          }
        }
      }
      return method;
    }
    final reg = _getRegisteredTableMetatable();
    if (reg != null && reg.containsKey(event)) return reg[event];
    return null;
  }

  /// Checks if the value has a metamethod associated with the given event.
  ///
  /// [event] - The name of the metamethod to check for.
  /// Returns `true` if the metamethod exists, `false` otherwise.
  bool hasMetamethod(String event) {
    // Use getMetamethod to honor weak semantics (e.g., __mode = 'v' on the
    // metatable of a metatable) and any guards we enforce there. Presence of
    // a key in the raw map is not sufficient when values are weak.
    try {
      return getMetamethod(event) != null;
    } catch (_) {
      return false;
    }
  }

  /// Checks if this value is callable (is a function or has __call metamethod)
  bool isCallable() {
    return raw is Function ||
        raw is BuiltinFunction ||
        raw is FunctionDef ||
        raw is FunctionLiteral ||
        raw is LuaCallableArtifact ||
        raw is FunctionBody ||
        hasMetamethod('__call');
  }

  /// Calls the value as a function with the given arguments.
  ///
  /// This method handles calling Dart functions, LuaLike functions (FunctionDef, FunctionBody),
  /// and functions that implement the '__call' metamethod.
  ///
  /// [args] - The arguments to pass to the function.
  /// Returns the result of the function call.
  /// Throws an [UnsupportedError] if the value is not callable.
  Future<Object?> invoke(List<Object?> args) async {
    if (raw is AsyncFunction) {
      // Call the asynchronous Dart function directly
      return await (raw as AsyncFunction)(args);
    } else if (raw is Function) {
      // Call synchronous Dart function
      return (raw as Function)(args);
    } else if (raw is FunctionDef) {
      // Call LuaLike function defined in AST
      final FunctionDef funcDef = raw as FunctionDef;
      final FunctionBody funcBody = funcDef.body;
      // Evaluate the function body
      final interp = _resolveInterpreter();
      if (interp == null) {
        throw UnsupportedError("No interpreter available to execute function");
      }
      final result = await funcBody.accept(interp as AstVisitor<Object?>);
      return result;
    } else if (raw is FunctionBody) {
      // Call LuaLike function body directly (closure)
      final FunctionBody funcBody = raw as FunctionBody;
      // Evaluate the function body
      final interp = _resolveInterpreter();
      if (interp == null) {
        throw UnsupportedError("No interpreter available to execute function");
      }
      final result = await funcBody.accept(interp as AstVisitor<Object?>);
      return result;
    } else if (raw is BuiltinFunction) {
      // Call BuiltinFunction
      return (raw as BuiltinFunction).call(args);
    } else if (hasMetamethod('__call')) {
      // Call __call metamethod
      final callMeta = getMetamethod('__call');
      if (callMeta is Value) {
        return await callMeta.invoke([this, ...args]);
      } else if (callMeta is Function) {
        return await callMeta([this, ...args]);
      }
    }
    throw UnsupportedError(
      'Attempt to call a non-function value: ${raw.runtimeType}',
    );
  }

  /// Converts a raw Dart value into a Value object.
  ///
  /// If the input is already a Value, returns it unchanged.
  /// For maps, recursively wraps all entries.
  ///
  /// [value] - The value to wrap
  /// Returns a new Value instance wrapping the input.
  static Value wrap(dynamic value) {
    if (value is Value) return value;
    if (value is Map) {
      // Create new table with copied entries
      final newMap = <dynamic, dynamic>{};
      value.forEach((key, val) {
        newMap[key] = wrap(val);
      });
      return Value(newMap);
    }
    return Value(value);
  }

  /// Unwraps a Value to get its raw value, recursively for tables and lists.
  dynamic unwrap() {
    if (raw is Map) {
      final unwrapped = <dynamic, dynamic>{};
      (raw as Map).forEach((key, value) {
        final realKey = key is LuaString ? key.toString() : key;
        dynamic out;
        if (value is Value) {
          out = value.unwrap();
        } else if (value is Map || value is List) {
          out = Value(value).completeUnwrap();
        } else if (value is LuaString) {
          out = value.toString();
        } else {
          out = value;
        }
        unwrapped[realKey] = out;
      });
      return unwrapped;
    }
    if (raw is List) {
      return (raw as List).map((e) {
        if (e is Value) {
          return e.unwrap();
        } else if (e is Map || e is List) {
          return Value(e).unwrap();
        } else if (e is LuaString) {
          return e.toString();
        }
        return e;
      }).toList();
    }
    if (raw is LuaString) {
      // Decode using UTF-8 so multi-byte characters (e.g. Chinese) are
      // preserved when users call `.unwrap()`.
      return (raw as LuaString).toString();
    }
    return raw is Value ? raw.completeUnwrap() : raw;
  }

  dynamic completeUnwrap() {
    var current = raw;
    while (current is Value) {
      current = current.unwrap();
    }
    if (current is LuaString) {
      return (current).toString();
    }
    return current;
  }

  @override
  int get hashCode => raw.hashCode;

  @override
  bool operator ==(Object other) => equals(other);

  // Guard to prevent infinite recursion in toString
  static final Set<int> _toStringGuard = <int>{};

  @override
  String toString() {
    final objectId = identityHashCode(this);

    // Check if we're already in a toString call for this object
    if (_toStringGuard.contains(objectId)) {
      // Fallback to simple representation to avoid recursion
      if (raw == null) return "Value:<nil>";
      if (raw is bool) return "Value:<$raw>";
      if (raw is num || raw is BigInt) return "Value:<$raw>";
      if (raw is String) return "Value:<$raw>";
      if (raw is List) return "Value:<list:${raw.hashCode}>";
      if (raw is Map) return "Value:<table:${raw.hashCode}>";
      if (raw is Function) return "Value:<function:${raw.hashCode}>";
      return "Value:<$raw>";
    }

    final tostringMeta = getMetamethod('__tostring');
    if (tostringMeta != null) {
      // Check if this is a Lua function (which would return a Future)
      if (tostringMeta is Value && tostringMeta.raw is Function) {
        // This is a Lua function, calling it would return a Future
        // For toString(), we can't handle Futures, so use default representation
        return "Value:<table:${raw.hashCode}>";
      }

      try {
        _toStringGuard.add(objectId);
        final result = callMetamethod('__tostring', [this]);
        // Handle both sync and async results
        if (result is Future) {
          // For toString(), we can't await, so return a placeholder
          return "Value:<table:${raw.hashCode}>";
        }
        return result is Value ? result.raw.toString() : result.toString();
      } catch (e) {
        // If metamethod call fails, fall back to default behavior
        Logger.debug('Error in __tostring metamethod: $e', category: 'Value');
      } finally {
        _toStringGuard.remove(objectId);
      }
    }

    if (raw == null) return "Value:<nil>";
    if (raw is bool) return "Value:<$raw>";
    if (raw is num || raw is BigInt) return "Value:<$raw>";
    if (raw is String) return "Value:<$raw>";
    if (raw is List) return "Value:<list:${raw.hashCode}>";
    if (raw is Map) return "Value:<table:${raw.hashCode}>";
    if (raw is Function) return "Value:<function:${raw.hashCode}>";
    return "Value:<$raw>";
  }

  static const tableMetamethods = {
    '__index', // for reading from tables
    '__newindex', // for writing to tables
    '__len', // for length operation (#)
    '__pairs', // for pairs iteration
    '__ipairs', // for ipairs iteration
    '__add', // for addition (+)
    '__sub', // for subtraction (-)
    '__mul', // for multiplication (*)
    '__div', // for division (/)
    '__mod', // for modulo (%)
    '__pow', // for exponentiation (^)
    '__unm', // for negation (-)
    '__idiv', // for floor division (//)
    '__band', // for bitwise AND (&)
    '__bor', // for bitwise OR (|)
    '__bxor', // for bitwise XOR (~)
    '__bnot', // for bitwise NOT (~)
    '__shl', // for left shift (<<)
    '__shr', // for right shift (>>)
    '__concat', // for concatenation (..)
    '__eq', // for equality (==)
    '__lt', // for less than (<)
    '__le', // for less than or equal (<=)
    '__call', // for function calls
    '__tostring', // for string conversion
    '__gc', // for garbage collection
    '__close', // for to-be-closed variables
  };

  @override
  dynamic operator [](Object? key) {
    if (raw is TableStorage) {
      final denseIndex = _extractPositiveIndex(key);
      if (denseIndex != null) {
        final stored = (raw as TableStorage).denseValueAt(denseIndex);
        if (stored != null) {
          if (stored is Value) {
            return stored;
          }
          final existing = _lookupTableIdentity(stored);
          if (existing != null) {
            return existing;
          }
          final wrapped = Value(stored);
          if (wrapped.raw is Map) {
            _tableIdentity[wrapped.raw as Map] = wrapped;
          }
          return wrapped;
        }
      }
    }

    if (raw is Map) {
      final storageKey = _computeStorageKey(key);
      if ((raw as Map).containsKey(storageKey)) {
        final result = (raw as Map)[storageKey];
        if (result is Value) {
          // If this Value wraps a Map and there is a canonical wrapper
          // registered for that Map, return the canonical one to preserve
          // metatables and identity semantics.
          if (result.raw is Map) {
            final existing = _lookupTableIdentity(result.raw);
            if (existing != null && !identical(existing, result)) {
              // Update stored entry to canonical wrapper
              (raw as Map)[storageKey] = existing;
              return existing;
            }
          }
          return result;
        }
        // If the stored result is a raw Map, try to return the canonical
        // Value wrapper to preserve metatables and identity.
        final existing = _lookupTableIdentity(result);
        if (existing != null) {
          // Do not write back into the underlying Map when it is not already
          // storing Value instances; some tables may use typed Maps (CastMap)
          // for native data (e.g., functions). Writing a Value into those
          // structures triggers type errors. Simply return the canonical
          // wrapper to preserve identity semantics at the Value layer.
          return existing;
        }
        final wrapped = Value(result);
        if (wrapped.raw is Map) {
          _tableIdentity[wrapped.raw as Map] = wrapped;
        }
        // Avoid mutating the underlying Map with a Value wrapper when it may
        // be a typed CastMap (e.g., Map<Object?, SomeFunctionType>). Such
        // writes can cause type cast exceptions. We still register identity
        // for Map-backed values so subsequent reads canonicalize correctly.
        return wrapped;
      }

      // Key doesn't exist, check for __index metamethod
      final indexMeta = getMetamethod('__index');
      if (indexMeta != null) {
        final result = callMetamethod('__index', [
          this,
          key is Value ? key : Value(key),
        ]);

        return result is Value ? result : Value(result);
      }

      // No metamethod and key not found, return nil
      return Value(null);
    } else {
      // Not a table, but might have an __index metamethod
      final indexMeta = getMetamethod('__index');
      if (indexMeta != null) {
        final result = callMetamethod('__index', [
          this,
          key is Value ? key : Value(key),
        ]);
        if (result is Value) return result;
        final existing = _lookupTableIdentity(result);
        if (existing != null) return existing;
        return result;
      }
      // No metamethod, cannot index
      final tname = NumberUtils.typeName(raw);
      throw LuaError.typeError('attempt to index a $tname value');
    }
  }

  /// Asynchronous version of [operator []] that awaits any `__index`
  /// metamethod results. This is needed when metamethods are implemented as
  /// Lua functions which return [Future]s.
  Future<dynamic> getValueAsync(Object? key) async {
    if (raw is TableStorage) {
      final denseIndex = _extractPositiveIndex(key);
      if (denseIndex != null) {
        final stored = (raw as TableStorage).denseValueAt(denseIndex);
        if (stored != null) {
          if (stored is Value) {
            return stored;
          }
          final existing = _lookupTableIdentity(stored);
          if (existing != null) {
            return existing;
          }
          final wrapped = Value(stored);
          if (wrapped.raw is Map) {
            _tableIdentity[wrapped.raw as Map] = wrapped;
          }
          return wrapped;
        }
      }
    }

    if (raw is Map) {
      final storageKey = _computeStorageKey(key);
      if (raw is TableStorage && key is Value) {
        final int? denseIndex = _extractPositiveIndex(key);
        if (denseIndex != null) {
          final stored = (raw as TableStorage).arrayValueAt(denseIndex);
          if (stored != null) {
            if (stored is Value) {
              return stored;
            }
            return Value(stored);
          }
        }
      }
      if ((raw as Map).containsKey(storageKey)) {
        final result = (raw as Map)[storageKey];
        if (result is Value) {
          if (result.raw is Map) {
            final existing = _lookupTableIdentity(result.raw);
            if (existing != null && !identical(existing, result)) {
              (raw as Map)[storageKey] = existing;
              return existing;
            }
          }
          return result;
        }
        final existing = _lookupTableIdentity(result);
        if (existing != null) {
          // See synchronous variant: return canonical wrapper without writing
          // back to avoid typed map cast issues.
          return existing;
        }
        final wrapped = Value(result);
        if (wrapped.raw is Map) {
          _tableIdentity[wrapped.raw as Map] = wrapped;
        }
        // See synchronous variant: avoid writing back wrapped Value into
        // possibly typed maps.
        return wrapped;
      }

      final indexMeta = getMetamethod('__index');
      if (indexMeta != null) {
        var result = await callMetamethodAsync('__index', [
          this,
          key is Value ? key : Value(key),
        ]);
        if (result is Value) return result;
        final existing = _lookupTableIdentity(result);
        if (existing != null) return existing;
        final wrapped = Value(result);
        if (wrapped.raw is Map) {
          _tableIdentity[wrapped.raw as Map] = wrapped;
        }
        return wrapped;
      }

      return Value(null);
    } else {
      final indexMeta = getMetamethod('__index');
      if (indexMeta != null) {
        var result = await callMetamethodAsync('__index', [
          this,
          key is Value ? key : Value(key),
        ]);
        if (result is Value) return result;
        final existing = _lookupTableIdentity(result);
        if (existing != null) return existing;
        return result;
      }
      final tname = NumberUtils.typeName(raw);
      throw LuaError.typeError('attempt to index a $tname value');
    }
  }

  @override
  void operator []=(Object key, dynamic value) {
    final rawKey = _computeRawKey(key);
    if (rawKey == null) {
      throw LuaError.typeError('table index is nil');
    }
    if (rawKey is num && rawKey.isNaN) {
      throw LuaError.typeError('table index is NaN');
    }

    final hasRawTable = raw is Map;
    final keyExists = hasRawTable && rawContainsKey(key);

    if (hasRawTable && keyExists) {
      _setRawTableEntry(key, value);
      return;
    }

    final newindexMeta = getMetamethod('__newindex');
    if (newindexMeta != null) {
      callMetamethod('__newindex', [
        this,
        key is Value ? key : Value(key),
        value is Value ? value : Value(value),
      ]);
      return;
    }

    if (hasRawTable) {
      _setRawTableEntry(key, value);
      return;
    }

    final tname = NumberUtils.typeName(raw);
    throw LuaError.typeError('attempt to index a $tname value');
  }

  /// Assigns [value] to [key], awaiting any __newindex metamethod.
  Future<void> setValueAsync(
    Object key,
    dynamic value, [
    Set<Value>? visited,
  ]) async {
    final rawKey = _computeRawKey(key);
    if (rawKey == null) {
      throw LuaError.typeError('table index is nil');
    }
    if (rawKey is num && rawKey.isNaN) {
      throw LuaError.typeError('table index is NaN');
    }

    final hasRawTable = raw is Map;
    final keyExists = hasRawTable && rawContainsKey(key);

    if (!keyExists) {
      final newindexMeta = getMetamethod('__newindex');
      if (newindexMeta != null) {
        visited ??= <Value>{};
        if (visited.contains(this)) {
          Logger.debugLazy(
            () => 'loop in settable triggered: table=$hashCode key=$key',
            category: 'Value',
          );
          throw LuaError('loop in settable');
        }
        visited.add(this);

        if (newindexMeta is Value && newindexMeta.raw is Map) {
          await newindexMeta.setValueAsync(key, value, visited);
          return;
        }

        final result = callMetamethod('__newindex', [
          this,
          key is Value ? key : Value(key),
          value is Value ? value : Value(value),
        ]);
        if (result is Future) await result;
        return;
      }
    }

    if (hasRawTable) {
      _setRawTableEntry(key, value);
      return;
    }

    final tname = NumberUtils.typeName(raw);
    throw LuaError.typeError('attempt to index a $tname value');
  }

  void _setRawTableEntry(Object key, dynamic value) {
    final valueToSet = value is Value ? value : Value(value);
    final storageKey = _computeStorageKey(key);
    final storageValue = valueToSet;
    final map = raw as Map;
    // Seed cache if missing (first mutation may precede a count)
    if (_tableStringKeyBytes[map] == null) {
      var total = 0;
      try {
        for (final k in map.keys) {
          if (k is String) {
            total += k.length * GcWeights.stringUnit;
          } else if (k is LuaString) {
            total += k.length * GcWeights.stringUnit;
          } else if (k is Value) {
            final kr = k.raw;
            if (kr is String) {
              total += kr.length * GcWeights.stringUnit;
            } else if (kr is LuaString) {
              total += kr.length * GcWeights.stringUnit;
            }
          }
        }
      } catch (_) {}
      _tableStringKeyBytes[map] = total;
    }
    final existed = map.containsKey(storageKey);
    if (Logger.enabled &&
        isTable &&
        tableWeakMode != null &&
        (tableWeakMode?.contains('k') ?? false)) {
      try {
        final keyType = storageKey.runtimeType;
        final keyRawType = storageKey is Value
            ? storageKey.raw.runtimeType
            : keyType;
        Logger.debug(
          'setRawTableEntry: weak-k store keyType=$keyType keyRawType=$keyRawType',
          category: 'GC',
        );
      } catch (_) {}
    }

    if (valueToSet.isNil) {
      map.remove(storageKey);
    } else {
      if (map is TableStorage && storageKey is int && storageKey > 0) {
        map.setDense(storageKey, storageValue);
      } else {
        map[storageKey] = storageValue;
      }
      final manager = GCAccess.fromValue(this);
      if (manager != null) {
        if (storageValue.interpreter == null && interpreter != null) {
          storageValue.interpreter = interpreter;
        }
        manager.ensureTracked(storageValue);
      }
    }
    _incrementTableVersion();
    final gcLocal4 = GCAccess.fromValue(this);
    if (gcLocal4 != null) {
      MemoryCredits.instance.recalculate(this);
    }
    // Maintain string-key credits incrementally when keys are Strings.
    try {
      int keyLen(Object k) {
        if (k is String) return k.length * GcWeights.stringUnit;
        if (k is LuaString) return k.length * GcWeights.stringUnit;
        return 0;
      }

      if (!existed && (storageKey is String || storageKey is LuaString)) {
        _tableStringKeyBytes[map] =
            (_tableStringKeyBytes[map] ?? 0) + keyLen(storageKey);
      }
      if (valueToSet.isNil &&
          existed &&
          (storageKey is String || storageKey is LuaString)) {
        _tableStringKeyBytes[map] =
            (_tableStringKeyBytes[map] ?? 0) - keyLen(storageKey);
      }
    } catch (_) {}
  }

  /// Marks the underlying table as modified so cached lookups can be
  /// invalidated.
  void markTableModified() {
    _incrementTableVersion();
  }

  /// Directly assigns [value] to the numeric index [index] without performing
  /// additional key normalization. Intended for dense-array fast paths where
  /// metamethods are known to be absent.
  void setNumericIndex(int index, Value value) {
    if (raw is! Map) {
      final tname = NumberUtils.typeName(raw);
      throw LuaError.typeError('attempt to index a $tname value');
    }
    final map = raw as Map;
    if (map is TableStorage && index > 0) {
      final manager = GCAccess.fromValue(this);
      if (value.isNil) {
        map.remove(index);
        _tableDenseWriteDebt[this] = 0;
        _incrementTableVersion();
        if (manager != null) {
          MemoryCredits.instance.recalculate(this);
        }
        return;
      }

      map[index] = value;
      _incrementTableVersion();
      if (manager != null) {
        if (value.interpreter == null && interpreter != null) {
          value.interpreter = interpreter;
        }
        manager.ensureTracked(value);
        final pending = (_tableDenseWriteDebt[this] ?? 0) + 1;
        if (pending >= 1024) {
          _tableDenseWriteDebt[this] = 0;
          MemoryCredits.instance.recalculate(this);
        } else {
          _tableDenseWriteDebt[this] = pending;
        }
      }
      return;
    }

    _setRawTableEntry(index, value);
  }

  int? _extractPositiveIndex(Object? key) {
    Object? candidate = key;
    if (candidate is Value) {
      candidate = candidate.raw;
    }
    if (candidate is int) {
      return candidate > 0 ? candidate : null;
    }
    if (candidate is num) {
      if (candidate is double && !candidate.isFinite) {
        return null;
      }
      final intKey = candidate.toInt();
      if (intKey > 0 && intKey.toDouble() == candidate.toDouble()) {
        return intKey;
      }
    }
    return null;
  }

  void _incrementTableVersion() {
    if (raw is Map) {
      _tableVersion++;
    }
  }

  @override
  void clear() {
    if (raw is! Map) throw UnsupportedError('Not a table');

    final newindexMeta = getMetamethod('__newindex');
    if (newindexMeta != null) {
      final keys = List.from((raw as Map).keys);
      for (final key in keys) {
        callMetamethod('__newindex', [this, Value(key), Value(null)]);
      }
      return;
    }

    (raw as Map).clear();
    _incrementTableVersion();
    final gcLocal5 = GCAccess.fromValue(this);
    if (gcLocal5 != null) {
      MemoryCredits.instance.recalculate(this);
    }
  }

  @override
  bool containsKey(Object? key) {
    if (raw is! Map) return false;

    final storageKey = _computeStorageKey(key);
    if ((raw as Map).containsKey(storageKey)) {
      return true;
    }

    // Key doesn't exist, check if __index metamethod would return a non-nil value
    final indexMeta = getMetamethod('__index');
    if (indexMeta != null) {
      final result = callMetamethod('__index', [this, Value(key)]);
      return result != null && (result is Value ? result.raw != null : true);
    }

    return false;
  }

  /// Checks if the raw table contains the key (without metamethods)
  bool rawContainsKey(Object? key) {
    if (raw is! Map) return false;

    final storageKey = _computeStorageKey(key);
    return (raw as Map).containsKey(storageKey);
  }

  @override
  bool containsValue(Object? value) =>
      entries.where((a) => a.value == value).isNotEmpty;

  @override
  void forEach(void Function(String key, Value value) action) {
    if (raw is! Map) throw UnsupportedError('Not a table');
    for (final entry in entries) {
      action(entry.key, entry.value as Value);
    }
  }

  @override
  bool get isEmpty {
    if (raw is! Map) return true;

    final lenMeta = getMetamethod('__len');
    if (lenMeta != null) {
      final result = callMetamethod('__len', [this]);
      return (result is Value ? result.raw : result) == 0;
    }

    return (raw as Map).isEmpty;
  }

  @override
  bool get isNotEmpty => !isEmpty;

  @override
  int get length {
    if (raw == null) return 0;

    if (raw is LuaString) {
      return (raw as LuaString).length;
    }

    final lenMeta = getMetamethod('__len');
    if (lenMeta != null) {
      final result = callMetamethod('__len', [this]);
      return result is Value ? result.raw as int : result as int;
    }

    if (raw is String) {
      return (raw as String).length;
    }

    if (raw is List) {
      return (raw as List).length;
    }

    if (raw is! Map) {
      throw LuaError.typeError('attempt to get length of a ${raw.runtimeType}');
    }

    final map = raw as Map;
    // Lua's length is undefined for tables with holes; adopt a practical rule:
    // use the highest positive integer index whose value is non-nil. This
    // lets callers iterate 1..#t across sparse results (e.g., unpack) while
    // ignoring trailing stored-nil slots like those from table.pack(...).
    int maxIndex = 0;
    map.forEach((k, v) {
      var key = k;
      if (key is Value) key = key.raw;
      // Only consider non-nil values
      final nonNil = !(v == null || (v is Value && v.raw == null));
      if (!nonNil) return;
      if (key is int && key > maxIndex) {
        maxIndex = key;
      } else if (key is num && key == key.floorToDouble()) {
        final asInt = key.toInt();
        if (asInt > maxIndex) maxIndex = asInt;
      }
    });
    return maxIndex;
  }

  @override
  Map<K, V> cast<K, V>() {
    if (raw is! Map) return {};
    return (raw as Map).cast<K, V>();
  }

  @override
  void addAll(Map<String, dynamic> other) {
    if (raw is! Map) throw UnsupportedError('Not a table');

    final newindexMeta = getMetamethod('__newindex');
    if (newindexMeta != null) {
      other.forEach((key, value) {
        callMetamethod('__newindex', [
          this,
          Value(key),
          value is Value ? value : Value(value),
        ]);
      });
      return;
    }

    other.forEach((key, value) {
      this[key] = value;
    });
  }

  @override
  dynamic putIfAbsent(String key, dynamic Function() ifAbsent) {
    if (raw is! Map) throw UnsupportedError('Not a table');

    final indexMeta = getMetamethod('__index');
    if (indexMeta != null) {
      final current = callMetamethod('__index', [this, Value(key)]);
      if (current != null && (current is Value ? current.raw != null : true)) {
        return current;
      }

      final value = ifAbsent();
      final wrappedValue = value is Value ? value : Value(value);
      callMetamethod('__newindex', [this, Value(key), wrappedValue]);
      return wrappedValue;
    }

    var inserted = false;
    final result = (raw as Map).putIfAbsent(key, () {
      inserted = true;
      final value = ifAbsent();
      return value is Value ? value : Value(value);
    });
    if (inserted) {
      _incrementTableVersion();
    }
    final gc = GCAccess.fromValue(this);
    if (gc != null) {
      MemoryCredits.instance.recalculate(this);
    }
    return result;
  }

  @override
  dynamic remove(Object? key) {
    if (raw is! Map) return null;

    final newindexMeta = getMetamethod('__newindex');
    if (newindexMeta != null) {
      final oldValue = this[key];
      callMetamethod('__newindex', [this, Value(key), Value(null)]);
      return oldValue;
    }

    final storageKey = _computeStorageKey(key);
    var value = (raw as Map).remove(storageKey);

    final gcLocal = GCAccess.fromValue(this);
    if (gcLocal != null) {
      MemoryCredits.instance.recalculate(this);
    }

    return value is Value
        ? value
        : value != null
        ? Value(value)
        : null;
  }

  @override
  Iterable<String> get keys {
    return entries.map((e) => e.key);
  }

  @override
  Iterable<dynamic> get values => entries.map((e) => e.value);

  @override
  Iterable<MapEntry<String, dynamic>> get entries {
    if (raw is! Map) return [];

    final pairsMeta = getMetamethod('__pairs');
    if (pairsMeta != null) {
      Logger.debugLazy(
        () => 'Using __pairs metamethod for entries',
        category: 'Value',
      );

      final entries = <MapEntry<String, dynamic>>[];
      final iter = callMetamethod('__pairs', [this]);

      if (iter is Value && iter.isMulti && iter.raw is List) {
        final iterFn = iter.raw[0] as Value;
        final state = iter.raw[1] as Value;
        var key = Value(null); // Initial key is nil for first iteration

        while (true) {
          // Call iterator function with state and previous key
          final List<dynamic> result;
          if (iterFn.raw is Function) {
            result = iterFn.raw([state, key]);
          } else {
            break;
          }

          // Check if we've reached the end of iteration
          if (result.isEmpty) {
            break;
          }

          final nextKey = result[0];
          if (nextKey == null || (nextKey is Value && nextKey.raw == null)) {
            break;
          }

          final nextVal = result.length > 1 ? result[1] : Value(null);

          // Convert key to string for MapEntry
          final keyStr = nextKey is Value
              ? nextKey.raw.toString()
              : nextKey.toString();

          // Make sure value is a Value
          final valueVal = nextVal is Value ? nextVal : Value(nextVal);

          entries.add(MapEntry(keyStr, valueVal));

          // Update key for next iteration
          key = nextKey is Value ? nextKey : Value(nextKey);
        }
      }

      return entries;
    }

    // Default implementation for normal maps
    return (raw as Map).entries.map(
      (e) => MapEntry(
        e.key.toString(),
        e.value is Value ? e.value : Value(e.value),
      ),
    );
  }

  @override
  Map<K, V> map<K, V>(
    MapEntry<K, V> Function(String key, dynamic value) convert,
  ) {
    if (raw is! Map) return {};

    final pairsMeta = getMetamethod('__pairs');
    if (pairsMeta != null) {
      final entries = <MapEntry<K, V>>[];
      final iter = callMetamethod('__pairs', [this]);
      if (iter is Value && iter.isMulti) {
        final iterFn = iter.raw[0] as Value;
        final state = iter.raw[1] as Value;
        var key = iter.raw[2] as Value;

        while (true) {
          final result = (iterFn.raw as Function)([state, key]);
          if (result is List && result.isNotEmpty) {
            key = result[0] as Value;
            if (key.raw == null) break;
            final val = result[1] as Value;
            entries.add(convert(key.raw.toString(), val));
          } else {
            break;
          }
        }
      }
      return Map.fromEntries(entries);
    }

    return Map.fromEntries(
      (raw as Map).entries.map(
        (e) => convert(
          e.key.toString(),
          e.value is Value ? e.value : Value(e.value),
        ),
      ),
    );
  }

  /// Asynchronous version of callMetamethod for use in async contexts
  Future<Object?> callMetamethodAsync(String s, List<Value> list) async {
    Logger.debugLazy(
      () =>
          'callMetamethodAsync called with $s, args: '
          '${list.map((e) => e.raw)}',
      category: 'Value',
    );
    final method = getMetamethod(s);
    if (method == null) {
      throw UnsupportedError("attempt to call a nil value");
    }

    // Special handling for __index and __newindex when they are tables
    if (s == '__index' && method is Value && method.raw is Map) {
      // __index is a table. Lua repeats the lookup on that table, allowing
      // further metamethod processing.
      if (list.length >= 2) {
        final key = list[1];
        var result = method[key];
        if (result is Value && result.raw is Future) {
          result = await result.raw;
        } else if (result is Future) {
          result = await result;
        }
        if (result is Value && result.isMulti && result.raw is List) {
          final values = result.raw as List;
          return values.isNotEmpty ? values.first : Value(null);
        } else if (result is List && result.isNotEmpty) {
          return result.first is Value ? result.first : Value(result.first);
        }
        return result;
      }
    } else if (s == '__newindex' && method is Value && method.raw is Map) {
      // __newindex is a table, so repeat the assignment on that table. This
      // allows the table's own metamethods to run, matching Lua semantics.
      if (list.length >= 3) {
        final key = list[1];
        final value = list[2];
        await method.setValueAsync(key, value, <Value>{this});
        return Value(null);
      }
    }

    if (method is Function) {
      try {
        var result = method(list);
        if (result is Future) result = await result;
        return result;
      } on TailCallException catch (t) {
        final callee = t.functionValue is Value
            ? t.functionValue as Value
            : Value(t.functionValue);
        final result = await callee.call(t.args);
        if (s == '__index') {
          if (result is Value && result.isMulti && result.raw is List) {
            final values = result.raw as List;
            return values.isNotEmpty ? values.first : Value(null);
          } else if (result is List && result.isNotEmpty) {
            return result.first is Value ? result.first : Value(result.first);
          }
        }
        return result;
      }
    } else if (method is BuiltinFunction) {
      try {
        var result = method.call(list);
        if (result is Future) result = await result;
        return result;
      } on TailCallException catch (t) {
        final callee = t.functionValue is Value
            ? t.functionValue as Value
            : Value(t.functionValue);
        final result = await callee.call(t.args);
        if (s == '__index') {
          if (result is Value && result.isMulti && result.raw is List) {
            final values = result.raw as List;
            return values.isNotEmpty ? values.first : Value(null);
          } else if (result is List && result.isNotEmpty) {
            return result.first is Value ? result.first : Value(result.first);
          }
        }
        return result;
      }
    } else if (method is Value) {
      if (method.raw is Function) {
        try {
          var result = (method.raw as Function)(list);
          if (result is Future) result = await result;
          return result;
        } on TailCallException catch (t) {
          final callee = t.functionValue is Value
              ? t.functionValue as Value
              : Value(t.functionValue);
          final result = await callee.call(t.args);
          if (s == '__index') {
            if (result is Value && result.isMulti && result.raw is List) {
              final values = result.raw as List;
              return values.isNotEmpty ? values.first : Value(null);
            } else if (result is List && result.isNotEmpty) {
              return result.first is Value ? result.first : Value(result.first);
            }
          }
          return result;
        }
      } else if (method.raw is BuiltinFunction) {
        try {
          var result = (method.raw as BuiltinFunction).call(list);
          if (result is Future) result = await result;
          return result;
        } on TailCallException catch (t) {
          final callee = t.functionValue is Value
              ? t.functionValue as Value
              : Value(t.functionValue);
          final result = await callee.call(t.args);
          if (s == '__index') {
            if (result is Value && result.isMulti && result.raw is List) {
              final values = result.raw as List;
              return values.isNotEmpty ? values.first : Value(null);
            } else if (result is List && result.isNotEmpty) {
              return result.first is Value ? result.first : Value(result.first);
            }
          }
          return result;
        }
      } else if (method.raw is FunctionDef ||
          method.raw is FunctionLiteral ||
          method.raw is FunctionBody) {
        // This is a Lua function defined as an AST node
        // We can await it here since this is an async method
        final interpreter = _resolveInterpreter();
        if (interpreter != null) {
          try {
            final result = await interpreter.callFunction(method, list);
            // For __index metamethod, only return the first value if multiple values are returned
            if (s == '__index') {
              if (result is Value && result.isMulti && result.raw is List) {
                final values = result.raw as List;
                return values.isNotEmpty ? values.first : Value(null);
              } else if (result is List && result.isNotEmpty) {
                return result.first is Value
                    ? result.first
                    : Value(result.first);
              }
            }
            return result;
          } on TailCallException catch (t) {
            final callee = t.functionValue is Value
                ? t.functionValue as Value
                : Value(t.functionValue);
            final result = await callee.call(t.args);
            if (s == '__index') {
              if (result is Value && result.isMulti && result.raw is List) {
                final values = result.raw as List;
                return values.isNotEmpty ? values.first : Value(null);
              } else if (result is List && result.isNotEmpty) {
                return result.first is Value
                    ? result.first
                    : Value(result.first);
              }
            }
            return result;
          }
        }
        throw UnsupportedError("No interpreter available to call function");
      } else if (method.raw is LuaCallableArtifact) {
        final interpreter =
            method._resolveInterpreter() ?? _resolveInterpreter();
        if (interpreter != null) {
          try {
            final result = await interpreter.callFunction(method, list);
            if (s == '__index') {
              if (result is Value && result.isMulti && result.raw is List) {
                final values = result.raw as List;
                return values.isNotEmpty ? values.first : Value(null);
              } else if (result is List && result.isNotEmpty) {
                return result.first is Value
                    ? result.first
                    : Value(result.first);
              }
            }
            return result;
          } on TailCallException catch (t) {
            final callee = t.functionValue is Value
                ? t.functionValue as Value
                : Value(t.functionValue);
            final result = await callee.call(t.args);
            if (s == '__index') {
              if (result is Value && result.isMulti && result.raw is List) {
                final values = result.raw as List;
                return values.isNotEmpty ? values.first : Value(null);
              } else if (result is List && result.isNotEmpty) {
                return result.first is Value
                    ? result.first
                    : Value(result.first);
              }
            }
            return result;
          }
        }
        throw UnsupportedError("No interpreter available to call function");
      }
    } else if (method is FunctionDef) {
      // Handle direct FunctionDef nodes
      final interpreter = _resolveInterpreter();
      if (interpreter != null) {
        try {
          final result = await interpreter.callFunction(Value(method), list);
          return result;
        } on TailCallException catch (t) {
          final callee = t.functionValue is Value
              ? t.functionValue as Value
              : Value(t.functionValue);
          return await callee.call(t.args);
        }
      }
      throw UnsupportedError("No interpreter available to call function");
    }

    throw UnsupportedError(
      "attempt to call a non-function $s(${list.map((a) => a.unwrap()).join(', ')})",
    );
  }

  Object? callMetamethod(String s, List<Value> list) {
    final method = getMetamethod(s);
    if (method == null) {
      throw UnsupportedError("attempt to call a nil value");
    }

    // Special handling for __index and __newindex when they are tables
    if (s == '__index' && method is Value && method.raw is Map) {
      // __index is a table, so do lookup through that table
      if (list.length >= 2) {
        final key = list[1];
        // Use the Value's indexing mechanism to handle potential metamethods
        final result = method[key];

        return result;
      }
    } else if (s == '__newindex' && method is Value && method.raw is Map) {
      // __newindex is a table, so repeat the assignment on that table and
      // propagate any asynchronous result up to the caller.
      if (list.length >= 3) {
        final key = list[1];
        final value = list[2];
        return method.setValueAsync(key, value, <Value>{this});
      }
    }

    if (method is Function) {
      return method(list);
    } else if (method is BuiltinFunction) {
      return method.call(list);
    } else if (method is Value) {
      if (method.raw is Function) {
        final result = (method.raw as Function)(list);
        return result;
      } else if (method.raw is BuiltinFunction) {
        return (method.raw as BuiltinFunction).call(list);
      } else if (method.raw is FunctionDef ||
          method.raw is FunctionLiteral ||
          method.raw is FunctionBody) {
        final interpreter = _resolveInterpreter();
        if (interpreter != null) {
          return interpreter.callFunction(method, list);
        }
        throw UnsupportedError("No interpreter available to call function");
      } else if (method.raw is LuaCallableArtifact) {
        final interpreter = _resolveInterpreter();
        if (interpreter != null) {
          return interpreter.callFunction(method, list);
        }
        throw UnsupportedError("No interpreter available to call function");
      }
    } else if (method is FunctionDef) {
      final interpreter = _resolveInterpreter();
      if (interpreter != null) {
        return interpreter.callFunction(Value(method), list);
      }
      throw UnsupportedError("No interpreter available to call function");
    }

    throw UnsupportedError(
      "attempt to call a non-function $s(${list.map((a) => a.unwrap()).join(', ')})",
    );
  }

  @override
  void addEntries(Iterable<MapEntry<String, dynamic>> newEntries) {
    if (raw is! Map) throw UnsupportedError('Not a table');

    final newindexMeta = getMetamethod('__newindex');
    if (newindexMeta != null) {
      for (final entry in newEntries) {
        callMetamethod('__newindex', [
          this,
          Value(entry.key),
          entry.value is Value ? entry.value : Value(entry.value),
        ]);
      }
      return;
    }

    (raw as Map).addEntries(
      newEntries.map(
        (e) => MapEntry(e.key, e.value is Value ? e.value : Value(e.value)),
      ),
    );
    final gcLocal2 = GCAccess.fromValue(this);
    if (gcLocal2 != null) {
      MemoryCredits.instance.recalculate(this);
    }
  }

  @override
  void removeWhere(bool Function(String key, dynamic value) test) {
    if (raw is! Map) return;

    final pairsMeta = getMetamethod('__pairs');
    if (pairsMeta != null) {
      final iter = callMetamethod('__pairs', [this]);
      if (iter is! Value || !iter.isMulti) return;

      final iterFn = iter.raw[0] as Value;
      final state = iter.raw[1] as Value;
      var key = iter.raw[2] as Value;

      while (true) {
        final result = (iterFn.raw as Function)([state, key]);
        if (result is List && result.isNotEmpty) {
          key = result[0] as Value;
          if (key.raw == null) break;

          final val = result[1] as Value;
          if (test(key.raw.toString(), val)) {
            callMetamethod('__newindex', [this, key, Value(null)]);
          }
        } else {
          break;
        }
      }
      return;
    }

    (raw as Map).removeWhere(
      (k, v) => test(k.toString(), v is Value ? v : Value(v)),
    );
    final gcLocal3 = GCAccess.fromValue(this);
    if (gcLocal3 != null) {
      MemoryCredits.instance.recalculate(this);
    }
  }

  @override
  void updateAll(dynamic Function(String key, dynamic value) update) {
    if (raw is! Map) throw UnsupportedError('Not a table');

    final pairsMeta = getMetamethod('__pairs');
    if (pairsMeta != null) {
      final iter = callMetamethod('__pairs', [this]);
      if (iter is! Value || !iter.isMulti) return;

      final iterFn = iter.raw[0] as Value;
      final state = iter.raw[1] as Value;
      var key = iter.raw[2] as Value;

      while (true) {
        final result = (iterFn.raw as Function)([state, key]);
        if (result is List && result.isNotEmpty) {
          key = result[0] as Value;
          if (key.raw == null) break;

          final val = result[1] as Value;
          final updatedValue = update(key.raw.toString(), val);
          callMetamethod('__newindex', [this, key, updatedValue]);
        } else {
          break;
        }
      }
      return;
    }

    (raw as Map).updateAll((k, v) {
      final result = update(k.toString(), v is Value ? v : Value(v));
      return result is Value ? result : Value(result);
    });
    final gcLocal4 = GCAccess.fromValue(this);
    if (gcLocal4 != null) {
      MemoryCredits.instance.recalculate(this);
    }
  }

  @override
  dynamic update(
    String key,
    dynamic Function(dynamic value) update, {
    dynamic Function()? ifAbsent,
  }) {
    if (raw is! Map) throw UnsupportedError('Not a table');

    final indexMeta = getMetamethod('__index');
    if (indexMeta != null) {
      final current = callMetamethod('__index', [this, Value(key)]);
      if (current != null && (current is Value ? current.raw != null : true)) {
        final updatedValue = update(current);
        callMetamethod('__newindex', [this, Value(key), updatedValue]);
        return updatedValue;
      }

      if (ifAbsent != null) {
        final value = ifAbsent();
        final wrappedValue = value is Value ? value : Value(value);
        callMetamethod('__newindex', [this, Value(key), wrappedValue]);
        return wrappedValue;
      }
      return null;
    }

    final result = (raw as Map).update(
      key,
      (value) {
        final updated = update(value is Value ? value : Value(value));
        return updated is Value ? updated : Value(updated);
      },
      ifAbsent: ifAbsent != null
          ? () {
              final created = ifAbsent();
              return created is Value ? created : Value(created);
            }
          : null,
    );
    final gcLocal5 = GCAccess.fromValue(this);
    if (gcLocal5 != null) {
      MemoryCredits.instance.recalculate(this);
    }
    return result;
  }

  // Overload the call operator
  /// Calls this value if it's callable (continued)
  Future<Object?> call(List<Object?> args) async {
    if (raw is Function) {
      // Direct function call
      return raw(args);
    } else if (raw is BuiltinFunction) {
      final result = raw.call(args);
      return result is Future ? await result : result;
    } else if (raw is LuaCallableArtifact) {
      final interpreter = _resolveInterpreter();
      if (interpreter != null) {
        return await interpreter.callFunction(this, args);
      }
    } else if (hasMetamethod('__call')) {
      // Use __call metamethod
      final callMethod = getMetamethod('__call');
      final callArgs = [this, ...args];

      if (callMethod is Function) {
        return await callMethod(callArgs);
      } else if (callMethod is Value) {
        // If the metamethod is a Value, it may be:
        // - a direct Dart function (raw is Function)
        // - a Lua function (FunctionDef/FunctionBody/Literal)
        // - a table with its own __call chain
        if (callMethod.raw is Function) {
          return await callMethod.raw(callArgs);
        }
        final interpreter = _resolveInterpreter();
        if (interpreter != null) {
          return await interpreter.callFunction(callMethod, callArgs);
        }
      }
    } else if (raw is FunctionDef ||
        raw is FunctionLiteral ||
        raw is FunctionBody) {
      // Get interpreter to evaluate the function
      final interpreter = _resolveInterpreter();
      if (interpreter != null) {
        return await interpreter.callFunction(this, args);
      }
    }

    throw Exception("attempt to call a non-function value");
  }

  @override
  List<Object?> getReferences() {
    return getReferencesForGC(strongKeys: true, strongValues: true);
  }

  /// Gets references for GC traversal with control over weak semantics.
  /// This is used internally by the GC to implement weak table behavior.
  ///
  /// [strongKeys] - If false, do not include table keys in references
  /// [strongValues] - If false, do not include table values in references
  List<Object?> getReferencesForGC({
    required bool strongKeys,
    required bool strongValues,
  }) {
    final refs = <Object?>[];

    // Handle table contents based on weak mode
    if (isTable) {
      final tableMap = raw as Map;

      // Add keys if they should be treated as strong references
      if (strongKeys) {
        for (final key in tableMap.keys) {
          if (key is GCObject || key is Value || _containsGCObject(key)) {
            refs.add(key);
          }
        }
      }

      // Add values if they should be treated as strong references
      if (strongValues) {
        for (final value in tableMap.values) {
          if (value is GCObject || value is Value || _containsGCObject(value)) {
            refs.add(value);
          }
        }
      }
    } else if (raw is Value) {
      // Non-table Value containing another Value
      refs.add(raw);
    } else if (raw is GCObject) {
      refs.add(raw);
    } else if (raw is List) {
      // Value containing a List - traverse list items
      for (final item in raw as List) {
        if (item is GCObject || item is Value || _containsGCObject(item)) {
          refs.add(item);
        }
      }
    }

    // Always include metatable (it's not part of weak semantics)
    if (metatable != null) {
      refs.add(metatable);
    }

    // Include upvalues and function body if present
    // Phase 7B: Include upvalue objects themselves (now GCObjects)
    if (upvalues != null) {
      for (final upvalue in upvalues!) {
        // Include the upvalue object itself for GC tracking
        refs.add(upvalue);
      }
    }

    if (functionBody != null) {
      // Function bodies contain AST nodes that may reference Values
      // For now, we don't traverse them as they're not GCObjects
      // AST nodes are managed by Dart GC and shared/cached
    }

    return refs;
  }

  /// Helper method to check if an object contains or is a GCObject
  bool _containsGCObject(dynamic obj) {
    if (obj is GCObject || obj is Value) return true;
    if (obj is Map) {
      return obj.values.any((v) => v is GCObject || v is Value) ||
          obj.keys.any((k) => k is GCObject || k is Value);
    }
    if (obj is Iterable) {
      return obj.any((item) => item is GCObject || item is Value);
    }
    return false;
  }

  /// Returns table entries for GC processing.
  /// Used internally by the GC to access table contents for weak clearing.
  Iterable<MapEntry<dynamic, dynamic>> tableEntriesForGC() {
    if (!isTable) return const [];
    return (raw as Map).entries;
  }

  dynamic _computeRawKey(Object? key) {
    if (key is Value) {
      var rawKey = key.raw;
      if (rawKey is LuaString) {
        rawKey = rawKey.toString();
      }
      return rawKey;
    }
    if (key is LuaString) {
      return key.toString();
    }
    return key;
  }

  dynamic _computeStorageKey(Object? key) {
    if (key is Value) {
      final rawKey = key.raw;

      // For weak-key tables, ALWAYS preserve the Value wrapper so GC can track it.
      // Otherwise inline expressions like a[string.rep(...)] will unwrap to raw
      // strings, the Value wrapper gets freed, and credits are lost.
      if (tableWeakMode != null && tableWeakMode!.contains('k')) {
        // Weak keys: keep Value wrapper for GC tracking
        return key;
      }

      if (rawKey is LuaString) {
        return rawKey.toString();
      }
      if (rawKey is num) {
        // Normalize -0.0 to 0.0 for consistent key handling (Lua treats them equal)
        return rawKey == 0 ? 0.0 : rawKey;
      }
      if (_isPrimitiveKey(rawKey)) {
        return rawKey;
      }
      // For non-primitive keys (e.g., tables), always use the canonical Value
      // wrapper for the underlying Map so lookups/writes agree and GC can
      // observe the key as a GCObject (for weak-keys semantics).
      if (rawKey is Map) {
        // For map keys, avoid binding this wrapper into the global identity
        // registry. Using the wrapper as-is prevents hidden strong references
        // that can confuse weak-keys collection semantics during GC.
        return key;
      }
      return key;
    }
    if (key is LuaString) {
      return key.toString();
    }
    if (key is num) {
      // Normalize -0.0 to 0.0 for consistent key handling (Lua treats them equal)
      return key == 0 ? 0.0 : key;
    }
    return key;
  }

  bool _isPrimitiveKey(Object? value) {
    return value is num || value is String || value is bool || value is BigInt;
  }

  @override
  void free() {
    // Reset GC bookkeeping so stale values don't remain marked when
    // referenced from weak tables after they've otherwise been collected.
    Logger.debugLazy(() => 'Value.free() called for $hashCode', category: 'GC');
    _marked = false;
    isOld = false;
    _isFreed = true;
  }

  /// Whether this value has been freed by the GC.
  bool get isFreed => _isFreed;

  /// Clear a stale freed marker when this value is rediscovered from a live
  /// root in a later collection cycle.
  void revive() {
    _isFreed = false;
  }

  @override
  bool get marked => _marked;

  @override
  set marked(bool value) => _marked = value;
}

extension OperatorExtension on Value {
  // Overload the bitwise XOR operator
  Value operator ^(dynamic other) => _arith('bxor', Value.wrap(other));

  // Overload the bitwise OR operator
  Value operator |(dynamic other) => _arith('|', Value.wrap(other));

  // Overload the bitwise AND operator
  Value operator &(dynamic other) => _arith('&', Value.wrap(other));

  // Logical OR method (Lua-style)
  Value or(dynamic other) {
    // In Lua, 'or' returns the first value if it's truthy, otherwise the second value
    if (raw != null && raw != false) {
      return this;
    }
    final wrappedOther = other is Value ? other : Value.wrap(other);
    return wrappedOther;
  }

  // Logical AND method (Lua-style)
  Value and(dynamic other) {
    // In Lua, 'and' returns the first value if it's falsy, otherwise the second value
    if (raw == null || raw == false) {
      return this;
    }
    final wrappedOther = other is Value ? other : Value.wrap(other);
    return wrappedOther;
  }

  // Helper method for Lua truthiness evaluation
  bool isTruthy() {
    // In Lua, only nil and false are falsy - everything else is truthy
    return raw != null && raw != false;
  }

  bool isFalsy() {
    // In Lua, only nil and false are falsy
    return raw == null || raw == false;
  }

  // Add a helper for Lua's ~= (not equal) semantics
  bool notEquals(Object other) {
    final otherRaw = other is Value ? other.raw : other;
    // Lua: NaN ~= anything is always true
    if ((raw is num && (raw as num).isNaN) ||
        (otherRaw is num && (otherRaw).isNaN)) {
      Logger.debugLazy(
        () => 'COMPARE ~=: NaN detected, returning true',
        category: 'Value',
      );
      return true;
    }
    // Lua: int ~= float if float does not exactly represent int
    if ((raw is int || raw is BigInt) && otherRaw is double) {
      if (!otherRaw.isFinite) {
        Logger.debugLazy(
          () => 'COMPARE ~=: int ~= non-finite double, returning true',
          category: 'Value',
        );
        return true;
      }
      final intVal = raw is BigInt ? raw as BigInt : BigInt.from(raw);
      final doubleVal = otherRaw;
      final doubleFromInt = intVal.toDouble();
      final intFromDouble = BigInt.from(doubleVal);
      final isExact = (doubleVal == doubleFromInt) && (intVal == intFromDouble);
      Logger.debugLazy(
        () =>
            'COMPARE ~=: int=$intVal, double=$doubleVal, doubleFromInt=$doubleFromInt, intFromDouble=$intFromDouble, isExact=$isExact',
        category: 'Value',
      );
      return !isExact;
    }
    if (raw is double && (otherRaw is int || otherRaw is BigInt)) {
      if (!(raw).isFinite) {
        Logger.debugLazy(
          () =>
              'COMPARE ~=: double ~= int, but double is not finite, '
              'returning true',
          category: 'Value',
        );
        return true;
      }
      final intVal = otherRaw is BigInt ? otherRaw : BigInt.from(otherRaw);
      final doubleVal = raw;
      final doubleFromInt = intVal.toDouble();
      final intFromDouble = BigInt.from(doubleVal);
      final isExact = (doubleVal == doubleFromInt) && (intVal == intFromDouble);
      Logger.debugLazy(
        () =>
            'COMPARE ~=: double=$doubleVal, int=$intVal, doubleFromInt=$doubleFromInt, intFromDouble=$intFromDouble, isExact=$isExact',
        category: 'Value',
      );
      return !isExact;
    }
    return !(this == other);
  }

  @pragma('vm:prefer-inline')
  Value _arith(String op, Value other) {
    final result = NumberUtils.performArithmetic(op, raw, other.raw);
    return Value(result);
  }

  /// Overload the addition operator
  @pragma('vm:prefer-inline')
  Value operator +(dynamic other) => _arith('+', Value.wrap(other));

  // Overload the subtraction operator
  @pragma('vm:prefer-inline')
  Value operator -(dynamic other) => _arith('-', Value.wrap(other));

  // Overload the multiplication operator
  @pragma('vm:prefer-inline')
  Value operator *(dynamic other) => _arith('*', Value.wrap(other));

  // Overload the division operator
  @pragma('vm:prefer-inline')
  Value operator /(dynamic other) => _arith('/', Value.wrap(other));

  // Overload the bitwise NOT operator
  Value operator ~() {
    final result = NumberUtils.bitwiseNot(raw);
    return Value(result);
  }

  // Overload the left shift operator
  @pragma('vm:prefer-inline')
  Value operator <<(dynamic other) => _arith('<<', Value.wrap(other));

  // Overload the right shift operator
  @pragma('vm:prefer-inline')
  Value operator >>(dynamic other) => _arith('>>', Value.wrap(other));

  // Overload the modulo operator
  @pragma('vm:prefer-inline')
  Value operator %(dynamic other) => _arith('%', Value.wrap(other));

  // Overload the floor division operator
  @pragma('vm:prefer-inline')
  Value operator ~/(dynamic other) => _arith('//', Value.wrap(other));

  // Overload the exponentiation operator
  @pragma('vm:prefer-inline')
  Value exp(dynamic other) => _arith('^', Value.wrap(other));

  // Overload the negation operator
  Value operator -() {
    final result = NumberUtils.negate(raw);
    return Value(result);
  }

  // Overload the concatenation operator
  Value concat(dynamic other) {
    // Wrap the other value if needed
    final wrappedOther = other is Value ? other : Value.wrap(other);

    // Handle LuaString concatenation
    if (raw is LuaString) {
      if (wrappedOther.raw is LuaString) {
        return Value((raw as LuaString) + (wrappedOther.raw as LuaString));
      } else if (wrappedOther.raw is num) {
        final otherStr = LuaString.fromDartString(wrappedOther.raw.toString());
        return Value((raw as LuaString) + otherStr);
      } else {
        final otherStr = LuaString.fromDartString(wrappedOther.raw.toString());
        return Value((raw as LuaString) + otherStr);
      }
    }

    if (wrappedOther.raw is LuaString) {
      if (raw is num) {
        final thisStr = LuaString.fromDartString(raw.toString());
        return Value(thisStr + (wrappedOther.raw as LuaString));
      } else {
        final thisStr = LuaString.fromDartString(raw.toString());
        return Value(thisStr + (wrappedOther.raw as LuaString));
      }
    }

    // Regular string concatenation - return Dart strings for better interop
    if (raw is String) {
      final otherRaw = wrappedOther.raw;
      final combined =
          raw + (otherRaw is String ? otherRaw : otherRaw.toString());
      return Value(LuaString.fromDartString(combined));
    }

    if (raw is num) {
      final otherRaw = wrappedOther.raw;
      final combined =
          raw.toString() +
          (otherRaw is String ? otherRaw : otherRaw.toString());
      return Value(LuaString.fromDartString(combined));
    }

    if (raw == null || other == null) {
      throw LuaError.typeError('Attempt to concatenate a nil value');
    }

    throw LuaError.typeError(
      'Concatenation not supported for these types ${raw.runtimeType} and ${wrappedOther.raw.runtimeType}',
    );
  }

  dynamic operator >(Object other) {
    final otherRaw = other is Value ? other.raw : other;
    // Lua: NaN > anything is always false
    if ((raw is num && (raw as num).isNaN) ||
        (otherRaw is num && (otherRaw).isNaN)) {
      Logger.debugLazy(
        () => 'COMPARE >: NaN detected, returning false',
        category: 'Value',
      );
      return false;
    }
    // Fast path: both are doubles (most common case)
    if (raw is double && otherRaw is double) {
      return raw > otherRaw;
    }
    // Always use mathematical ordering for int/BigInt vs double
    if ((raw is int || raw is BigInt) && otherRaw is double) {
      if (!otherRaw.isFinite) {
        if (otherRaw.isInfinite) {
          // int/BigInt vs infinity: int > +inf is false, int > -inf is true
          return otherRaw.isNegative;
        }
        // For NaN, return false (already handled above)
        return false;
      }
      final intVal = raw is BigInt ? raw as BigInt : BigInt.from(raw);
      final doubleVal = otherRaw;
      final doubleFromInt = intVal.toDouble();
      Logger.debugLazy(
        () =>
            'COMPARE >: int=$intVal, double=$doubleVal, '
            'doubleFromInt=$doubleFromInt',
        category: 'Value',
      );
      if (doubleFromInt == doubleVal) {
        BigInt intFromDouble;
        try {
          intFromDouble = BigInt.from(doubleVal);
        } on FormatException {
          return false;
        }
        return intVal > intFromDouble;
      }
      return doubleFromInt > doubleVal;
    }
    if (raw is double && (otherRaw is int || otherRaw is BigInt)) {
      if (!raw.isFinite) {
        if (raw.isInfinite) {
          // infinity vs int/BigInt: +inf > int is true, -inf > int is false
          return !raw.isNegative;
        }
        // For NaN, return false (already handled above)
        return false;
      }
      final intVal = otherRaw is BigInt ? otherRaw : BigInt.from(otherRaw);
      final doubleVal = raw;
      final doubleFromInt = intVal.toDouble();
      Logger.debugLazy(
        () =>
            'COMPARE >: double=$doubleVal, int=$intVal, '
            'doubleFromInt=$doubleFromInt',
        category: 'Value',
      );
      if (doubleFromInt == doubleVal) {
        BigInt intFromDouble;
        try {
          intFromDouble = BigInt.from(doubleVal);
        } on FormatException {
          return false;
        }
        return intFromDouble > intVal;
      }
      return doubleVal > doubleFromInt;
    }
    if (raw is num && otherRaw is num) return raw > otherRaw;
    if (raw is BigInt && otherRaw is BigInt) return raw > otherRaw;
    if (raw is BigInt && otherRaw is num) {
      if (otherRaw is int) return raw > BigInt.from(otherRaw);
      return raw.toDouble() > otherRaw;
    }
    if (raw is num && otherRaw is BigInt) {
      if (raw is int) return BigInt.from(raw) > otherRaw;
      return raw > otherRaw.toDouble();
    }
    if (raw is String && otherRaw is String) {
      return raw.compareTo(otherRaw) > 0;
    }
    if (raw is LuaString && otherRaw is LuaString) {
      return (raw as LuaString) > otherRaw;
    }
    if (raw is LuaString && otherRaw is String) {
      return (raw as LuaString) > LuaString.fromDartString(otherRaw);
    }
    if (raw is String && otherRaw is LuaString) {
      return LuaString.fromDartString(raw) > otherRaw;
    }
    throw UnsupportedError(
      'attempt to compare ${getLuaType(Value(raw))} with ${getLuaType(Value(otherRaw))}',
    );
  }

  dynamic operator <(Object other) {
    final otherRaw = other is Value ? other.raw : other;
    // Lua: NaN < anything is always false
    if ((raw is num && (raw as num).isNaN) ||
        (otherRaw is num && (otherRaw).isNaN)) {
      Logger.debugLazy(
        () => 'COMPARE <: NaN detected, returning false',
        category: 'Value',
      );
      return false;
    }
    // Fast path: both are doubles (most common case)
    if (raw is double && otherRaw is double) {
      return raw < otherRaw;
    }
    if ((raw is int || raw is BigInt) && otherRaw is double) {
      if (!otherRaw.isFinite) {
        if (otherRaw.isInfinite) {
          // int/BigInt vs infinity: int < +inf is true, int < -inf is false
          return !otherRaw.isNegative;
        }
        // For NaN, return false (already handled above)
        return false;
      }
      final intVal = raw is BigInt ? raw as BigInt : BigInt.from(raw);
      final doubleVal = otherRaw;
      final doubleFromInt = intVal.toDouble();
      Logger.debugLazy(
        () =>
            'COMPARE <: int=$intVal, double=$doubleVal, '
            'doubleFromInt=$doubleFromInt',
        category: 'Value',
      );
      if (doubleFromInt == doubleVal) {
        final intFromDouble = BigInt.from(doubleVal);
        return intVal < intFromDouble;
      }
      return doubleFromInt < doubleVal;
    }
    if (raw is double && (otherRaw is int || otherRaw is BigInt)) {
      if (!raw.isFinite) {
        if (raw.isInfinite) {
          // infinity vs int/BigInt: +inf < int is false, -inf < int is true
          return raw.isNegative;
        }
        // For NaN, return false (already handled above)
        return false;
      }
      final intVal = otherRaw is BigInt ? otherRaw : BigInt.from(otherRaw);
      final doubleVal = raw;
      final doubleFromInt = intVal.toDouble();
      Logger.debugLazy(
        () =>
            'COMPARE <: double=$doubleVal, int=$intVal, '
            'doubleFromInt=$doubleFromInt',
        category: 'Value',
      );
      if (doubleFromInt == doubleVal) {
        final intFromDouble = BigInt.from(doubleVal);
        return intFromDouble < intVal;
      }
      return doubleVal < doubleFromInt;
    }
    if (raw is num && otherRaw is num) return raw < otherRaw;
    if (raw is BigInt && otherRaw is BigInt) return raw < otherRaw;
    if (raw is BigInt && otherRaw is num) {
      if (otherRaw is int) return raw < BigInt.from(otherRaw);
      return raw.toDouble() < otherRaw;
    }
    if (raw is num && otherRaw is BigInt) {
      if (raw is int) return BigInt.from(raw) < otherRaw;
      return raw < otherRaw.toDouble();
    }
    if (raw is String && otherRaw is String) {
      return raw.compareTo(otherRaw) < 0;
    }
    if (raw is LuaString && otherRaw is LuaString) {
      return (raw as LuaString) < otherRaw;
    }
    if (raw is LuaString && otherRaw is String) {
      return (raw as LuaString) < LuaString.fromDartString(otherRaw);
    }
    if (raw is String && otherRaw is LuaString) {
      return LuaString.fromDartString(raw) < otherRaw;
    }
    throw UnsupportedError(
      'attempt to compare ${getLuaType(Value(raw))} with ${getLuaType(Value(otherRaw))}',
    );
  }

  dynamic operator >=(Object other) {
    final otherRaw = other is Value ? other.raw : other;
    // Lua: NaN >= anything is always false
    if ((raw is num && (raw as num).isNaN) ||
        (otherRaw is num && (otherRaw).isNaN)) {
      Logger.debugLazy(
        () => 'COMPARE >=: NaN detected, returning false',
        category: 'Value',
      );
      return false;
    }
    // Fast path: both are doubles (most common case)
    if (raw is double && otherRaw is double) {
      return raw >= otherRaw;
    }
    if ((raw is int || raw is BigInt) && otherRaw is double) {
      if (!otherRaw.isFinite) {
        if (otherRaw.isInfinite) {
          // int >= +inf is false, int >= -inf is true
          return otherRaw.isNegative;
        }
        return false; // NaN
      }
      final intVal = raw is BigInt ? raw as BigInt : BigInt.from(raw);
      final doubleVal = otherRaw;
      final doubleFromInt = intVal.toDouble();
      Logger.debugLazy(
        () =>
            'COMPARE >=: int=$intVal, double=$doubleVal, '
            'doubleFromInt=$doubleFromInt',
        category: 'Value',
      );
      if (doubleFromInt == doubleVal) {
        final intFromDouble = BigInt.from(doubleVal);
        return intVal >= intFromDouble;
      }
      return doubleFromInt >= doubleVal;
    }
    if (raw is double && (otherRaw is int || otherRaw is BigInt)) {
      if (!raw.isFinite) {
        if (raw.isInfinite) {
          // +inf >= int is true, -inf >= int is false
          return !raw.isNegative;
        }
        return false; // NaN
      }
      final intVal = otherRaw is BigInt ? otherRaw : BigInt.from(otherRaw);
      final doubleVal = raw;
      final doubleFromInt = intVal.toDouble();
      Logger.debugLazy(
        () =>
            'COMPARE >=: double=$doubleVal, int=$intVal, '
            'doubleFromInt=$doubleFromInt',
        category: 'Value',
      );
      if (doubleFromInt == doubleVal) {
        final intFromDouble = BigInt.from(doubleVal);
        return intFromDouble >= intVal;
      }
      return doubleVal >= doubleFromInt;
    }
    if (raw is num && otherRaw is num) return raw >= otherRaw;
    if (raw is BigInt && otherRaw is BigInt) return raw >= otherRaw;
    if (raw is BigInt && otherRaw is num) {
      if (otherRaw is int) return raw >= BigInt.from(otherRaw);
      return raw.toDouble() >= otherRaw;
    }
    if (raw is num && otherRaw is BigInt) {
      if (raw is int) return BigInt.from(raw) >= otherRaw;
      return raw >= otherRaw.toDouble();
    }
    if (raw is String && otherRaw is String) {
      return raw.compareTo(otherRaw) >= 0;
    }
    if (raw is LuaString && otherRaw is LuaString) {
      return (raw as LuaString) >= otherRaw;
    }
    if (raw is LuaString && otherRaw is String) {
      return (raw as LuaString) >= LuaString.fromDartString(otherRaw);
    }
    if (raw is String && otherRaw is LuaString) {
      return LuaString.fromDartString(raw) >= otherRaw;
    }
    throw UnsupportedError(
      'attempt to compare ${getLuaType(Value(raw))} with ${getLuaType(Value(otherRaw))}',
    );
  }

  dynamic operator <=(Object other) {
    final otherRaw = other is Value ? other.raw : other;
    // Lua: NaN <= anything is always false
    if ((raw is num && (raw as num).isNaN) ||
        (otherRaw is num && (otherRaw).isNaN)) {
      Logger.debugLazy(
        () => 'COMPARE <=: NaN detected, returning false',
        category: 'Value',
      );
      return false;
    }
    // Fast path: both are doubles (most common case)
    if (raw is double && otherRaw is double) {
      return raw <= otherRaw;
    }
    if ((raw is int || raw is BigInt) && otherRaw is double) {
      if (!otherRaw.isFinite) {
        if (otherRaw.isInfinite) {
          // int <= +inf is true, int <= -inf is false
          return !otherRaw.isNegative;
        }
        return false;
      }
      final intVal = raw is BigInt ? raw as BigInt : BigInt.from(raw);
      final doubleVal = otherRaw;
      final doubleFromInt = intVal.toDouble();
      Logger.debugLazy(
        () =>
            'COMPARE <=: int=$intVal, double=$doubleVal, '
            'doubleFromInt=$doubleFromInt',
        category: 'Value',
      );
      if (doubleFromInt == doubleVal) {
        final intFromDouble = BigInt.from(doubleVal);
        return intVal <= intFromDouble;
      }
      return doubleFromInt <= doubleVal;
    }
    if (raw is double && (otherRaw is int || otherRaw is BigInt)) {
      if (!raw.isFinite) {
        if (raw.isInfinite) {
          // +inf <= int is false, -inf <= int is true
          return raw.isNegative;
        }
        return false;
      }
      final intVal = otherRaw is BigInt ? otherRaw : BigInt.from(otherRaw);
      final doubleVal = raw;
      final doubleFromInt = intVal.toDouble();
      Logger.debugLazy(
        () =>
            'COMPARE <=: double=$doubleVal, int=$intVal, '
            'doubleFromInt=$doubleFromInt',
        category: 'Value',
      );
      if (doubleFromInt == doubleVal) {
        final intFromDouble = BigInt.from(doubleVal);
        return intFromDouble <= intVal;
      }
      return doubleVal <= doubleFromInt;
    }
    if (raw is num && otherRaw is num) return raw <= otherRaw;
    if (raw is BigInt && otherRaw is BigInt) return raw <= otherRaw;
    if (raw is BigInt && otherRaw is num) {
      if (otherRaw is int) return raw <= BigInt.from(otherRaw);
      return raw.toDouble() <= otherRaw;
    }
    if (raw is num && otherRaw is BigInt) {
      if (raw is int) return BigInt.from(raw) <= otherRaw;
      return raw <= otherRaw.toDouble();
    }
    if (raw is String && otherRaw is String) {
      return raw.compareTo(otherRaw) <= 0;
    }
    if (raw is LuaString && otherRaw is LuaString) {
      return (raw as LuaString) <= otherRaw;
    }
    if (raw is LuaString && otherRaw is String) {
      return (raw as LuaString) <= LuaString.fromDartString(otherRaw);
    }
    if (raw is String && otherRaw is LuaString) {
      return LuaString.fromDartString(raw) <= otherRaw;
    }
    throw UnsupportedError(
      'attempt to compare ${getLuaType(Value(raw))} with ${getLuaType(Value(otherRaw))}',
    );
  }

  bool equals(Object other) {
    final otherRaw = other is Value ? other.raw : other;
    // Lua: NaN == anything is always false
    if ((raw is num && raw.isNaN) || (otherRaw is num && otherRaw.isNaN)) {
      Logger.debugLazy(
        () => 'COMPARE ==: NaN detected, returning false',
        category: 'Value',
      );
      return false;
    }
    // Lua: int == float only if float is finite and exactly represents int
    if ((raw is int || raw is BigInt) && otherRaw is double) {
      if (!otherRaw.isFinite) {
        Logger.debugLazy(
          () => 'COMPARE ==: int == non-finite double, returning false',
          category: 'Value',
        );
        return false;
      }
      final intVal = raw is BigInt ? raw as BigInt : BigInt.from(raw);
      final doubleVal = otherRaw;
      BigInt intFromDouble;
      try {
        // Handle very large numbers that toStringAsFixed might return in scientific notation
        final stringVal = doubleVal.toStringAsFixed(0);
        if (stringVal.contains('e') || stringVal.contains('E')) {
          // Use LuaNumberParser for scientific notation
          final parsed = LuaNumberParser.parse(stringVal);
          if (parsed is double) {
            return false; // If it's not an exact integer, they're not equal
          }
          intFromDouble = parsed is BigInt ? parsed : BigInt.from(parsed);
        } else {
          intFromDouble = BigInt.parse(stringVal);
        }
      } catch (e) {
        return false; // If we can't parse it as an integer, they're not equal
      }
      final doubleFromInt = intVal.toDouble();
      final isExact = (doubleVal == doubleFromInt) && (intVal == intFromDouble);
      Logger.debugLazy(
        () =>
            'COMPARE ==: int=$intVal, double=$doubleVal, doubleFromInt=$doubleFromInt, intFromDouble=$intFromDouble, isExact=$isExact',
        category: 'Value',
      );
      return isExact;
    }
    if (raw is double && (otherRaw is int || otherRaw is BigInt)) {
      if (!raw.isFinite) {
        Logger.debugLazy(
          () =>
              'COMPARE ==: double == int, but double is not finite, '
              'returning false',
          category: 'Value',
        );
        return false;
      }
      final intVal = otherRaw is BigInt ? otherRaw : BigInt.from(otherRaw);
      final doubleVal = raw;
      BigInt intFromDouble;
      try {
        // Handle very large numbers that toStringAsFixed might return in scientific notation
        final stringVal = doubleVal.toStringAsFixed(0);
        if (stringVal.contains('e') || stringVal.contains('E')) {
          // Use LuaNumberParser for scientific notation
          final parsed = LuaNumberParser.parse(stringVal);
          if (parsed is double) {
            return false; // If it's not an exact integer, they're not equal
          }
          intFromDouble = parsed is BigInt ? parsed : BigInt.from(parsed);
        } else {
          intFromDouble = BigInt.parse(stringVal);
        }
      } catch (e) {
        return false; // If we can't parse it as an integer, they're not equal
      }
      final doubleFromInt = intVal.toDouble();
      final isExact = (doubleVal == doubleFromInt) && (intVal == intFromDouble);
      Logger.debugLazy(
        () =>
            'COMPARE ==: double=$doubleVal, int=$intVal, doubleFromInt=$doubleFromInt, intFromDouble=$intFromDouble, isExact=$isExact',
        category: 'Value',
      );
      return isExact;
    }
    if ((raw is BigInt && otherRaw is double) ||
        (raw is double && otherRaw is BigInt)) {
      final d1 = raw is BigInt ? raw.toDouble() : raw;
      final d2 = otherRaw is BigInt ? otherRaw.toDouble() : otherRaw;
      Logger.debugLazy(
        () => 'COMPARE ==: promoting BigInt to double: $d1 == $d2',
        category: 'Value',
      );
      return d1 == d2;
    }

    if (identical(this, other)) return true;
    if (raw is BigInt && otherRaw is BigInt) return raw == otherRaw;
    if (raw is BigInt && otherRaw is num) {
      if (otherRaw is int) return raw == BigInt.from(otherRaw);
      return otherRaw.isFinite &&
          raw.toDouble() == otherRaw &&
          raw == BigInt.from(otherRaw);
    }
    if (raw is num && otherRaw is BigInt) {
      if (raw is int) return BigInt.from(raw) == otherRaw;
      return raw.isFinite &&
          raw == otherRaw.toDouble() &&
          BigInt.from(raw) == otherRaw;
    }

    if (raw is LuaString && otherRaw is LuaString) {
      return raw == otherRaw;
    }
    if (raw is LuaString && otherRaw is String) {
      return raw == LuaString.fromDartString(otherRaw);
    }
    if (raw is String && otherRaw is LuaString) {
      return LuaString.fromDartString(raw) == otherRaw;
    }

    if (raw is Map && otherRaw is Map) {
      // Tables compare by reference when no '__eq' metamethod is present.
      // Using the default Dart equality here preserves this behavior.
      return raw == otherRaw;
    }
    return raw == otherRaw;
  }
}
