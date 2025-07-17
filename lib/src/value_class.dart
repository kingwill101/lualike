import 'builtin_function.dart';
import 'lua_string.dart';
import 'stdlib/metatables.dart';
import 'value.dart';

/// Example usage:
/// ```dart
/// // Create a Point class with metamethods
/// final pointClass = ValueClass.create({
///   "__add": (a, b) => Value({
///     "x": (a.raw["x"] as num) + (b.raw["x"] as num),
///     "y": (a.raw["y"] as num) + (b.raw["y"] as num),
///   }),
///   "__tostring": (p) => "Point(${p.raw['x']}, ${p.raw['y']})",
/// });
/// ```
/// ValueClass represents a constructor for creating new Value objects with a predefined metatable.
class ValueClass implements BuiltinFunction {
  final Map<String, dynamic> _metatable;

  ValueClass(this._metatable);

  static Value meta([Map<String, dynamic>? initial]) {
    return Value(null, metatable: initial ?? {});
  }

  /// Creates a new table (without default metatable, as per Lua specification)
  static Value table([dynamic initial]) {
    dynamic table;

    if (initial != null && initial is Map) {
      table = initial.cast<dynamic, dynamic>();
    } else {
      table = initial ?? <dynamic, dynamic>{};
    }
    return Value(table);
  }

  /// Creates a new string with default string metamethods
  static Value string(String value) {
    return Value(
      LuaString.fromDartString(value),
      metatable: MetaTable().getTypeMetatable('string')?.metamethods,
    );
  }

  /// Creates a new number with default number metamethods
  static Value number(num value) {
    return Value(
      value,
      metatable: MetaTable().getTypeMetatable('number')?.metamethods,
    );
  }

  /// Creates a new function with default function metamethods
  static Value function(Function value) {
    return Value(
      value,
      metatable: MetaTable().getTypeMetatable('function')?.metamethods,
    );
  }

  /// Creates a new userdata with default userdata metamethods
  static Value userdata(dynamic value) {
    return Value(
      value,
      metatable: MetaTable().getTypeMetatable('userdata')?.metamethods,
    );
  }

  @override
  Object? call(List<Object?> args) {
    // Create a new Value with an empty map and the predefined metatable
    return Value(Map<String, dynamic>.from({}), metatable: _metatable);
  }

  /// Creates a new ValueClass with the given metamethods
  static ValueClass create(Map<String, dynamic> metamethods) {
    return ValueClass(metamethods);
  }

  Map<String, dynamic> get metamethods => _metatable;
}
