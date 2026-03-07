import 'dart:collection';
import 'dart:typed_data';

import 'package:lualike/src/value.dart';

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
  Uint8List _occupied = Uint8List(0);
  final HashMap<dynamic, dynamic> _hash = HashMap<dynamic, dynamic>();

  int _arrayCount = 0;

  static const int _maxArraySize = 1 << 20; // ~1M entries

  int? _arrayIndexFor(Object? key) {
    if (key is int) {
      if (key > 0) return key - 1;
      return null;
    }
    if (key is num) {
      if (key is double && !key.isFinite) {
        return null;
      }
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
        if (arrayIdx < _occupied.length && _occupied[arrayIdx] != 0) {
          return _array[arrayIdx];
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
        if (arrayIdx >= _occupied.length) {
          _growOccupied(arrayIdx + 1);
        }
        final wasEmpty = _occupied[arrayIdx] == 0;
        _array[arrayIdx] = value;
        if (wasEmpty) {
          _occupied[arrayIdx] = 1;
          _arrayCount++;
        }
      } else if (arrayIdx == _array.length) {
        _array.add(value);
        _growOccupied(arrayIdx + 1);
        _occupied[arrayIdx] = 1;
        _arrayCount++;
      } else {
        ensureArrayCapacity(arrayIdx + 1);
        _array[arrayIdx] = value;
        _occupied[arrayIdx] = 1;
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
    _array.clear();
    _occupied = Uint8List(0);
    _hash.clear();
    _arrayCount = 0;
  }

  /// Appends [value] at the next sequential integer slot.
  void append(dynamic value) {
    final idx = _array.length;
    _array.add(value);
    _growOccupied(idx + 1);
    _occupied[idx] = 1;
    _arrayCount++;
    _hash.remove(idx + 1);
  }

  /// Writes [value] at the (1-based) [index], leaving holes as necessary.
  /// Assumes [index] > 0.
  void setDense(int index, dynamic value) {
    if (index <= 0 || index > _maxArraySize) {
      _hash[index] = value;
      return;
    }

    final arrayIdx = index - 1;
    if (arrayIdx == _array.length) {
      _array.add(value);
      _growOccupied(arrayIdx + 1);
      _occupied[arrayIdx] = 1;
      _arrayCount++;
      _hash.remove(index);
      return;
    }
    if (arrayIdx >= 0 && arrayIdx < _array.length) {
      _array[arrayIdx] = value;
      if (arrayIdx >= _occupied.length) {
        _growOccupied(arrayIdx + 1);
      }
      if (_occupied[arrayIdx] == 0) {
        _occupied[arrayIdx] = 1;
        _arrayCount++;
      }
      _hash.remove(index);
      return;
    }
    ensureArrayCapacity(index);
    _array[index - 1] = value;
    _occupied[index - 1] = 1;
    _arrayCount++;
    _hash.remove(index);
  }

  void ensureArrayCapacity(int capacity) {
    if (capacity <= 0) return;
    final target = capacity > _maxArraySize ? _maxArraySize : capacity;
    if (target <= _array.length) return;
    final additional = target - _array.length;
    _array.addAll(List<dynamic>.filled(additional, null));
    _growOccupied(target);
  }

  void _growOccupied(int requiredLength) {
    if (requiredLength <= _occupied.length) {
      return;
    }
    final target = requiredLength > _maxArraySize
        ? _maxArraySize
        : requiredLength;
    final next = Uint8List(target);
    if (_occupied.isNotEmpty) {
      next.setRange(0, _occupied.length, _occupied);
    }
    _occupied = next;
  }

  @override
  Iterable<dynamic> get keys sync* {
    final occupied = _occupied;
    final limit = occupied.length < _array.length
        ? occupied.length
        : _array.length;
    for (var i = 0; i < limit; i++) {
      if (occupied[i] != 0) {
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
      if (arrayIdx >= _occupied.length || _occupied[arrayIdx] == 0) {
        return _hash.remove(key);
      }
      final current = _array[arrayIdx];
      _array[arrayIdx] = null;
      _occupied[arrayIdx] = 0;
      _arrayCount--;
      _trimArray();
      return current;
    }
    return _hash.remove(key);
  }

  void _trimArray() {
    var last = _array.length - 1;
    while (last >= 0) {
      final isOccupied = last < _occupied.length && _occupied[last] != 0;
      if (isOccupied) {
        break;
      }
      _array.removeLast();
      if (_occupied.isNotEmpty && last < _occupied.length) {
        // shrink occupancy mirror
        final next = Uint8List(last);
        if (last > 0) {
          next.setRange(0, last, _occupied);
        }
        _occupied = next;
      }
      last--;
    }
  }

  @override
  bool containsKey(Object? key) {
    final arrayIdx = _arrayIndexFor(key);
    if (arrayIdx != null) {
      if (arrayIdx < _array.length && arrayIdx < _occupied.length) {
        if (_occupied[arrayIdx] != 0) {
          return true;
        }
      } else if (arrayIdx >= _array.length) {
        return _hash.containsKey(key);
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
    if (idx < _array.length && idx < _occupied.length) {
      if (_occupied[idx] != 0) {
        return _array[idx];
      }
    }
    return _hash[oneBasedIndex];
  }

  dynamic denseValueAt(int oneBasedIndex) {
    if (oneBasedIndex <= 0) return null;
    final idx = oneBasedIndex - 1;
    if (idx < _array.length && idx < _occupied.length) {
      return _occupied[idx] != 0 ? _array[idx] : null;
    }
    return null;
  }

  int highestPositiveIntegerKey() {
    var maxIndex = 0;

    for (var index = _array.length - 1; index >= 0; index--) {
      if (index >= _occupied.length || _occupied[index] == 0) {
        continue;
      }
      final value = _array[index];
      final isNil = value == null || (value is Value && value.raw == null);
      if (!isNil) {
        maxIndex = index + 1;
        break;
      }
    }

    for (final MapEntry(key: key, value: value) in _hash.entries) {
      final isNil = value == null || (value is Value && value.raw == null);
      if (isNil) {
        continue;
      }
      final arrayIndex = _arrayIndexFor(key);
      if (arrayIndex != null) {
        final oneBasedIndex = arrayIndex + 1;
        if (oneBasedIndex > maxIndex) {
          maxIndex = oneBasedIndex;
        }
      }
    }

    return maxIndex;
  }

  Iterable<MapEntry<dynamic, dynamic>> get hashEntries => _hash.entries;
}
