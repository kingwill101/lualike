import 'package:lualike/src/bytecode/bytecode.dart' show BytecodeChunk;

import '../value.dart' as lualike;

/// Value types for bytecode VM
enum ValueType {
  nil,
  boolean,
  number,
  string,
  table,
  function,
  closure,
  upvalue,
}

/// Value representation for bytecode VM
class Value {
  // Add support for varargs
  const Value.varargs(List<Value> values)
    : type = ValueType.table,
      raw = values;
  final ValueType type;
  final dynamic raw;

  // Update Value class constructor for functions/closures
  const Value.closure(Closure closure)
    : type = ValueType.closure,
      raw = closure;
  const Value.upvalue(Upvalue upvalue)
    : type = ValueType.upvalue,
      raw = upvalue;

  const Value.nil() : type = ValueType.nil, raw = null;
  const Value.boolean(bool value) : type = ValueType.boolean, raw = value;
  const Value.number(num value) : type = ValueType.number, raw = value;
  const Value.string(String value) : type = ValueType.string, raw = value;
  const Value.table(Map<Value, Value> value)
    : type = ValueType.table,
      raw = value;

  // Convert from lualike Value
  factory Value.fromLuaLike(lualike.Value value) {
    if (value.raw == null) return const Value.nil();
    if (value.raw is bool) return Value.boolean(value.raw);
    if (value.raw is num) return Value.number(value.raw);
    if (value.raw is String) return Value.string(value.raw);
    if (value.raw is Map) {
      final map = <Value, Value>{};
      value.raw.forEach((k, v) {
        map[Value.fromLuaLike(lualike.Value(k))] = Value.fromLuaLike(
          lualike.Value(v),
        );
      });
      return Value.table(map);
    }
    throw Exception('Cannot convert ${value.raw.runtimeType}');
  }

  // Convert to lualike Value
  lualike.Value toLuaLike() {
    switch (type) {
      case ValueType.nil:
        return lualike.Value(null);
      case ValueType.boolean:
      case ValueType.number:
      case ValueType.string:
        return lualike.Value(raw);
      case ValueType.table:
        final map = <dynamic, dynamic>{};
        (raw as Map<Value, Value>).forEach((k, v) {
          map[k.toLuaLike().raw] = v.toLuaLike().raw;
        });
        return lualike.Value(map);
      default:
        throw Exception('Cannot convert $type');
    }
  }

  @override
  String toString() => '$raw';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Value && type == other.type && raw == other.raw;
  }

  @override
  int get hashCode => Object.hash(type, raw);
}

// Add Closure and Upvalue classes to value.dart
class Closure {
  final BytecodeChunk chunk;
  final List<Upvalue> upvalues;

  Closure(this.chunk, [this.upvalues = const []]);
}

class Upvalue {
  final int index;
  Value? closed; // When closed, stores the final value

  Upvalue(this.index);

  bool get isClosed => closed != null;
}
