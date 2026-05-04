import 'package:lualike/src/runtime/lua_results.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/runtime/lua_primitive.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/value.dart';

export 'package:lualike/src/runtime/lua_primitive.dart'
    show isLuaPrimitiveSlot, isLuaScalarPrimitiveSlot;

/// Returns true if the slot's raw Lua value is nil.
bool isLuaNilSlot(Object? slot) => rawLuaSlot(slot) == null;

/// Returns true by Lua truthiness rules (everything except nil and false).
bool isLuaTruthy(Object? slot) {
  final raw = rawLuaSlot(slot);
  return raw != null && raw != false;
}

/// Returns true if the slot's raw value is a Lua string (Dart [String] or
/// [LuaString]).
bool isLuaStringSlot(Object? slot) {
  final raw = rawLuaSlot(slot);
  return raw is String || raw is LuaString;
}

/// Returns the raw slot value converted to a Dart [String] via [toString].
String rawLuaSlotString(Object? slot) => rawLuaSlot(slot).toString();

/// Returns true if two slots are equal under Lua raw-equality rules, handling
/// mixed [LuaString] / Dart [String] comparisons correctly.
bool rawLuaSlotsEqual(Object? left, Object? right) {
  final l = rawLuaSlot(left);
  final r = rawLuaSlot(right);
  if (l is LuaString) return l == r;
  if (r is LuaString) return r == l;
  return l == r;
}

/// Lightweight internal runtime slot.
///
/// A slot may hold raw Lua primitives, a public [Value] facade, a table payload,
/// a closure payload, or a [LuaResults] carrier while the internals migrate
/// away from using [Value] for every temporary runtime value.
typedef LuaSlot = Object?;

/// Returns the raw payload for a public [Value] facade, or [slot] unchanged.
@pragma('vm:prefer-inline')
dynamic rawLuaSlot(Object? slot) => slot is Value ? slot.raw : slot;

/// Returns whether [value] is a multi-result carrier in either the new internal
/// shape or the existing public [Value.multi] shape.
bool isLuaResults(Object? value) =>
    value is LuaResults || (value is Value && value.multiResults != null);

/// Extracts multi-result values from [value], if it is a multi-result carrier.
List<Object?>? luaResultValues(Object? value) {
  if (value is LuaResults) {
    return value.values;
  }
  if (value is Value) {
    return value.multiResults;
  }
  return null;
}

/// Returns the first value produced by [value] using Lua result-adjustment
/// rules, or `null` when the carrier has zero results.
Object? firstLuaResult(Object? value, {bool expandPlainList = false}) {
  final values = luaResultValues(value);
  if (values != null) {
    return values.isEmpty ? null : values.first;
  }
  if (expandPlainList && value is List) {
    return value.isEmpty ? null : value.first;
  }
  return value;
}

/// Converts [slot] into a public [Value] facade while preserving the runtime's
/// existing primitive wrapper caches and canonical table wrappers.
Value valueFromLuaSlot(LuaRuntime runtime, LuaSlot slot) {
  if (slot is Value) {
    slot.interpreter ??= runtime;
    return slot;
  }

  if (slot is LuaResults) {
    return valueMultiFromLuaResults(slot.values, runtime: runtime);
  }

  if (slot is Map) {
    final canonical = Value.lookupCanonicalTableWrapper(slot);
    if (canonical != null) {
      canonical.interpreter ??= runtime;
      return canonical;
    }
  }

  if (isLuaScalarPrimitiveSlot(slot)) {
    return runtime.constantPrimitiveValue(slot);
  }
  if (slot is LuaString) {
    return runtime.constantStringValue(slot.bytes);
  }
  if (slot is String) {
    return runtime.constantDartStringValue(slot);
  }

  return Value(slot)..interpreter = runtime;
}

/// Converts [slot] into a public [Value] facade when a runtime may not be
/// available.
///
/// Callers that do have a runtime still get the same cache/canonicalization
/// behavior as [valueFromLuaSlot]. Runtime-less callers keep the compatibility
/// fallback of creating a plain [Value] wrapper.
Value valueFromOptionalLuaSlot(LuaRuntime? runtime, LuaSlot slot) {
  if (runtime != null) {
    return valueFromLuaSlot(runtime, slot);
  }

  if (slot is Value) {
    return slot;
  }

  if (slot is LuaResults) {
    return valueMultiFromLuaResults(slot.values);
  }

  if (slot is Map) {
    final canonical = Value.lookupCanonicalTableWrapper(slot);
    if (canonical != null) {
      return canonical;
    }
  }

  if (isLuaPrimitiveSlot(slot)) {
    return Value.primitive(slot);
  }

  return Value(slot);
}

/// Converts [slot] into a fresh [Value] facade without using runtime caches.
///
/// This is for short-lived wrappers that carry per-wrapper flags, such as
/// temporary table keys. Primitive-like payloads still use the lighter
/// [Value.primitive] constructor while preserving the fresh-wrapper semantics.
Value freshValueFromLuaSlot(
  LuaRuntime? runtime,
  LuaSlot slot, {
  bool isTempKey = false,
}) {
  if (slot is Value) {
    slot.interpreter ??= runtime;
    return slot;
  }

  if (isLuaPrimitiveSlot(slot)) {
    return Value.primitive(slot, isTempKey: isTempKey, interpreter: runtime);
  }

  return Value(slot, isTempKey: isTempKey, interpreter: runtime);
}

/// Returns the runtime-cached wrapper for lightweight scalar values.
///
/// For non-primitive values this falls back to [valueFromOptionalLuaSlot].
/// This keeps primitive/string-cache policy centralized while preserving the
/// lighter generic slot wrapper for objects, tables, and result carriers.
Value cachedPrimitiveOrValue(LuaRuntime? runtime, LuaSlot slot) {
  if (slot is Value) return slot; // Already wrapped, no work needed
  if (isLuaScalarPrimitiveSlot(slot)) {
    return runtime?.constantPrimitiveValue(slot) ?? Value.primitive(slot);
  }
  if (slot is String) {
    return runtime?.constantDartStringValue(slot) ?? Value.primitive(slot);
  }
  if (slot is LuaString) {
    return runtime?.constantStringValue(slot.bytes) ?? Value.primitive(slot);
  }
  return valueFromOptionalLuaSlot(runtime, slot);
}

/// Converts [value] to the first Lua result as a [Value].
Value firstLuaResultValue(LuaRuntime runtime, Object? value) =>
    cachedPrimitiveOrValue(
      runtime,
      firstLuaResult(value, expandPlainList: true),
    );

/// Appends all results produced by [value] to [out].
///
/// Existing interpreter call paths also treat a plain Dart [List] as an
/// expanded result list, so [expandPlainList] defaults to true.
void appendExpandedLuaResults(
  List<Object?> out,
  LuaRuntime runtime,
  Object? value, {
  bool expandPlainList = true,
}) {
  final results = luaResultValues(value);
  if (results != null) {
    for (final entry in results) {
      out.add(cachedPrimitiveOrValue(runtime, entry));
    }
    return;
  }

  if (expandPlainList && value is List) {
    for (final entry in value) {
      out.add(cachedPrimitiveOrValue(runtime, entry));
    }
    return;
  }

  out.add(cachedPrimitiveOrValue(runtime, value));
}

/// Appends the first result produced by [value] to [out].
void appendFirstLuaResult(
  List<Object?> out,
  LuaRuntime runtime,
  Object? value, {
  bool expandPlainList = true,
}) {
  out.add(
    cachedPrimitiveOrValue(
      runtime,
      firstLuaResult(value, expandPlainList: expandPlainList),
    ),
  );
}

/// Converts [values] to the compatibility public multi-result wrapper.
///
/// When [runtime] is available, entries are normalized through the same
/// primitive/string caches used by other slot conversion helpers.
Value valueMultiFromLuaResults(
  Iterable<Object?> values, {
  LuaRuntime? runtime,
}) {
  final normalized = runtime == null
      ? List<Object?>.from(values)
      : values
            .map<Object?>((entry) => cachedPrimitiveOrValue(runtime, entry))
            .toList(growable: false);
  final multi = Value.multi(normalized);
  if (runtime != null) {
    multi.interpreter = runtime;
  }
  return multi;
}
