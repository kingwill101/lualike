import 'dart:collection';

class TableStorage extends MapBase<dynamic, dynamic> {
  TableStorage();

  factory TableStorage.from(Map<dynamic, dynamic> other) {
    final storage = TableStorage();
    other.forEach((key, value) {
      storage[key] = value;
    });
    return storage;
  }

  final List<dynamic> _array = <dynamic>[];
  final Map<dynamic, dynamic> _hash = <dynamic, dynamic>{};

  int _arrayCount = 0;

  static const int _maxArraySize = 1 << 20; // ~1M entries

  int? _arrayIndexFor(Object? key) {
    if (key is int) {
      if (key > 0) return key - 1;
      return null;
    }
    if (key is num) {
      final intKey = key.toInt();
      if (intKey > 0 && intKey.toDouble() == key.toDouble()) {
        return intKey - 1;
      }
    }
    return null;
  }

  bool _shouldUseArray(int oneBasedIndex) {
    if (oneBasedIndex <= 0) return false;
    if (oneBasedIndex == _array.length + 1) return true;
    if (oneBasedIndex <= _array.length) return true;
    if (oneBasedIndex > _maxArraySize) return false;
    if (_array.isEmpty) return oneBasedIndex <= 32;
    return oneBasedIndex <= (_array.length * 2);
  }

  @override
  dynamic operator [](Object? key) {
    final arrayIdx = _arrayIndexFor(key);
    if (arrayIdx != null) {
      if (arrayIdx < _array.length) {
        final value = _array[arrayIdx];
        if (value != null) {
          return value;
        }
      }
      return _hash[key];
    }
    return _hash[key];
  }

  @override
  void operator []=(dynamic key, dynamic value) {
    final oneBasedIndex = _arrayIndexFor(key);
    if (value == null) {
      remove(key);
      return;
    }

    if (oneBasedIndex != null && _shouldUseArray(oneBasedIndex + 1)) {
      final arrayIdx = oneBasedIndex;
      if (arrayIdx < _array.length) {
        final current = _array[arrayIdx];
        if (current == null) {
          _arrayCount++;
        }
        _array[arrayIdx] = value;
      } else if (arrayIdx == _array.length) {
        _array.add(value);
        _arrayCount++;
      } else {
        _array.length = arrayIdx + 1;
        _array[arrayIdx] = value;
        _arrayCount++;
      }
      _hash.remove(key);
      return;
    }

    final contains = _hash.containsKey(key);
    _hash[key] = value;
    if (!contains) {
      // nothing extra; _hash.length reflects additions.
    }
  }

  @override
  void clear() {
    _array..clear();
    _hash.clear();
    _arrayCount = 0;
  }

  void ensureArrayCapacity(int capacity) {
    if (capacity <= 0) return;
    final target = capacity > _maxArraySize ? _maxArraySize : capacity;
    if (target <= _array.length) return;
    final additional = target - _array.length;
    _array.addAll(List<dynamic>.filled(additional, null));
  }

  @override
  Iterable<dynamic> get keys sync* {
    for (var i = 0; i < _array.length; i++) {
      final value = _array[i];
      if (value != null) {
        yield i + 1;
      }
    }
    yield* _hash.keys;
  }

  @override
  dynamic remove(Object? key) {
    final arrayIdx = _arrayIndexFor(key);
    if (arrayIdx != null) {
      if (arrayIdx >= _array.length) {
        return _hash.remove(key);
      }
      final current = _array[arrayIdx];
      if (current == null) {
        return _hash.remove(key);
      }
      _array[arrayIdx] = null;
      _arrayCount--;
      _trimArray();
      return current;
    }
    return _hash.remove(key);
  }

  void _trimArray() {
    var last = _array.length - 1;
    while (last >= 0 && _array[last] == null) {
      _array.removeLast();
      last--;
    }
  }

  @override
  bool containsKey(Object? key) {
    final arrayIdx = _arrayIndexFor(key);
    if (arrayIdx != null) {
      if (arrayIdx >= _array.length) {
        return _hash.containsKey(key);
      }
      if (_array[arrayIdx] != null) {
        return true;
      }
      return _hash.containsKey(key);
    }
    return _hash.containsKey(key);
  }

  @override
  int get length => _arrayCount + _hash.length;

  int get arrayLength => _array.length;

  dynamic arrayValueAt(int oneBasedIndex) {
    if (oneBasedIndex <= 0) return _hash[oneBasedIndex];
    final idx = oneBasedIndex - 1;
    if (idx < _array.length) {
      final value = _array[idx];
      if (value != null) {
        return value;
      }
    }
    return _hash[oneBasedIndex];
  }
}
