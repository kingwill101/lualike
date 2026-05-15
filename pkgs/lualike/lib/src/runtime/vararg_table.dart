import 'dart:collection';

import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/number_limits.dart';
import 'package:lualike/src/number_utils.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/table_storage.dart' show isLuaNilValue;
import 'package:lualike/src/value.dart';

Value packVarargsTable(List<Object?> varargs, {LuaRuntime? runtime}) {
  return Value(
    PackedVarargTable(varargs, copyValues: false, runtime: runtime),
    interpreter: runtime,
  );
}

final class PackedVarargTable extends MapBase<dynamic, dynamic>
    implements VirtualLuaTable {
  PackedVarargTable(
    List<Object?> values, {
    bool copyValues = true,
    this.runtime,
  }) : _values = copyValues
           ? List<Object?>.from(values, growable: false)
           : values;

  final List<Object?> _values;
  final Map<dynamic, dynamic> _extra = <dynamic, dynamic>{};
  final LuaRuntime? runtime;

  int get _count => _values.length;

  Value _nilValue() => cachedPrimitiveOrValue(runtime, null);

  Value _wrapValue(Object? value) => cachedPrimitiveOrValue(runtime, value);

  static Object? _rawKey(Object? key) => rawLuaSlot(key);

  static int? _normalizeIndex(Object? key) {
    final rawKey = _rawKey(key);
    return switch (rawKey) {
      final int integer when integer > 0 && integer <= NumberLimits.maxInt32 =>
        integer,
      final BigInt integer
          when integer >= BigInt.one &&
              integer <= BigInt.from(NumberLimits.maxInt32) =>
        integer.toInt(),
      final num number
          when number.isFinite &&
              number > 0 &&
              number.toInt() <= NumberLimits.maxInt32 &&
              number.toInt().toDouble() == number.toDouble() =>
        number.toInt(),
      _ => null,
    };
  }

  @override
  dynamic operator [](Object? key) {
    final rawKey = _rawKey(key);
    if (_extra.containsKey(rawKey)) {
      return _extra[rawKey];
    }
    if (rawKey == 'n') {
      return _extra['n'] ?? _count;
    }
    final index = _normalizeIndex(rawKey);
    if (index == null || index > _count) {
      return null;
    }
    return _values[index - 1];
  }

  @override
  void operator []=(dynamic key, dynamic value) {
    final rawKey = _rawKey(key);
    final wrapped = _wrapValue(value);

    if (rawKey == 'n') {
      if (isLuaNilValue(value)) {
        _extra.remove('n');
      } else {
        _extra['n'] = wrapped;
      }
      return;
    }

    final index = _normalizeIndex(rawKey);
    if (index != null && index <= _count) {
      _values[index - 1] = wrapped;
      return;
    }

    if (isLuaNilValue(value)) {
      _extra.remove(rawKey);
    } else {
      _extra[rawKey] = wrapped;
    }
  }

  List<Object?> expandedValues() {
    final count = expandedCount();
    if (count <= 0) {
      return const <Object?>[];
    }
    return List<Object?>.generate(count, (index) {
      return expandedValueAt(index + 1);
    }, growable: false);
  }

  int expandedCount() {
    final rawCount = _extra['n'];
    final normalizedCount = switch (rawCount) {
      null => _count,
      final Value wrapped => rawLuaSlot(wrapped),
      _ => rawCount,
    };
    if (normalizedCount is! int && normalizedCount is! BigInt) {
      throw LuaError("no proper 'n'");
    }
    final count = NumberUtils.tryToInteger(normalizedCount);
    if (count == null || count < 0 || count > NumberLimits.maxInt32) {
      throw LuaError("no proper 'n'");
    }
    return count;
  }

  Object? expandedValueAt(int oneBasedIndex) {
    final count = expandedCount();
    if (oneBasedIndex < 1 || oneBasedIndex > count) {
      return _nilValue();
    }
    if (oneBasedIndex <= _count) {
      return _values[oneBasedIndex - 1];
    }
    return _extra[oneBasedIndex] ?? _nilValue();
  }

  @override
  void clear() {
    for (var i = 0; i < _values.length; i++) {
      _values[i] = null;
    }
    _extra.clear();
  }

  @override
  Iterable<dynamic> get keys sync* {
    for (var index = 1; index <= _count; index++) {
      if (_values[index - 1] != null) {
        yield index;
      }
    }
    yield 'n';
    for (final key in _extra.keys) {
      if (key == 'n') {
        continue;
      }
      final index = _normalizeIndex(key);
      if (index != null && index <= _count) {
        continue;
      }
      yield key;
    }
  }

  @override
  dynamic remove(Object? key) {
    if (key == 'n') {
      return _extra.remove('n');
    }
    final index = _normalizeIndex(key);
    if (index != null && index <= _count) {
      final previous = _values[index - 1];
      _values[index - 1] = null;
      return previous;
    }
    return _extra.remove(key);
  }
}
