import '../value.dart';

Object? _rawCollectionValue(Object? value) =>
    value is Value ? value.raw : value;

/// Extension methods for Lists to simplify Value operations
extension ListValueExtension on List<dynamic> {
  /// Convert all elements in a list to Values
  List<Value> toValueList() =>
      map((item) => item is Value ? item : Value.wrap(item)).toList();

  /// Unwrap all Value objects in a list
  List<dynamic> unwrapValueList() => map(_rawCollectionValue).toList();

  /// Convert to a Lua-style multi-return Value
  Value toMultiValue() => Value.multi(this);
}

/// Extension methods for Maps to simplify Value operations
extension MapValueExtension on Map<dynamic, dynamic> {
  /// Convert all values in a map to Values
  Map<dynamic, Value> toValueMap() {
    final result = <dynamic, Value>{};
    forEach((key, value) {
      result[key] = value is Value ? value : Value.wrap(value);
    });
    return result;
  }

  /// Create a new Value table from this map
  Value toValueTable() {
    final table = Value(<dynamic, dynamic>{});
    forEach((key, value) {
      table[key] = value is Value ? value : Value.wrap(value);
    });
    return table;
  }
}
