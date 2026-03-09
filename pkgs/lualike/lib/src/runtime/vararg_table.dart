import 'dart:collection';

import 'package:lualike/src/number_limits.dart';
import 'package:lualike/src/number_utils.dart';
import 'package:lualike/src/value.dart';

Value packVarargsTable(List<Object?> varargs) {
  return Value(PackedVarargTable(varargs));
}

final class PackedVarargTable extends MapBase<dynamic, dynamic>
    implements VirtualLuaTable {
  PackedVarargTable(List<Object?> values)
    : _values = List<Object?>.from(values, growable: false);

  final List<Object?> _values;
  final Map<dynamic, dynamic> _extra = <dynamic, dynamic>{};

  int get _count => _values.length;

  static int? _normalizeIndex(Object? key) {
    final rawKey = switch (key) {
      final Value wrapped => wrapped.raw,
      _ => key,
    };
    final integer = NumberUtils.tryToInteger(rawKey);
    if (integer == null || integer < 1 || integer > NumberLimits.maxInt32) {
      return null;
    }
    return integer;
  }

  @override
  dynamic operator [](Object? key) {
    if (_extra.containsKey(key)) {
      return _extra[key];
    }
    if (key == 'n') {
      return _count;
    }
    final index = _normalizeIndex(key);
    if (index == null || index > _count) {
      return null;
    }
    return _values[index - 1];
  }

  @override
  void operator []=(dynamic key, dynamic value) {
    if (key == 'n') {
      if (value == null || (value is Value && value.raw == null)) {
        _extra.remove('n');
      } else {
        _extra['n'] = value;
      }
      return;
    }

    final index = _normalizeIndex(key);
    if (index != null && index <= _count) {
      _values[index - 1] = value is Value && value.raw == null ? null : value;
      return;
    }

    if (value == null || (value is Value && value.raw == null)) {
      _extra.remove(key);
    } else {
      _extra[key] = value;
    }
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
