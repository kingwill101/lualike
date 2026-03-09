import 'dart:collection';

import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/number_limits.dart';
import 'package:lualike/src/number_utils.dart';
import 'package:lualike/src/value.dart';

Value packVarargsTable(List<Object?> varargs) {
  return Value(PackedVarargTable(varargs, copyValues: false));
}

final class PackedVarargTable extends MapBase<dynamic, dynamic>
    implements VirtualLuaTable {
  PackedVarargTable(List<Object?> values, {bool copyValues = true})
    : _values = copyValues
          ? List<Object?>.from(values, growable: false)
          : values;

  final List<Object?> _values;
  final Map<dynamic, dynamic> _extra = <dynamic, dynamic>{};

  int get _count => _values.length;

  static Object? _rawKey(Object? key) {
    return switch (key) {
      final Value wrapped => wrapped.raw,
      _ => key,
    };
  }

  static int? _normalizeIndex(Object? key) {
    final rawKey = _rawKey(key);
    final integer = NumberUtils.tryToInteger(rawKey);
    if (integer == null || integer < 1 || integer > NumberLimits.maxInt32) {
      return null;
    }
    return integer;
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
    final wrapped = value is Value ? value : Value(value);

    if (rawKey == 'n') {
      if (value == null || (value is Value && value.raw == null)) {
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

    if (value == null || (value is Value && value.raw == null)) {
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
      final Value wrapped => wrapped.raw,
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
      return Value(null);
    }
    if (oneBasedIndex <= _count) {
      return _values[oneBasedIndex - 1];
    }
    return _extra[oneBasedIndex] ?? Value(null);
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
