import 'dart:collection';
import 'dart:typed_data';

import 'package:lualike/src/number_limits.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/value.dart';

bool isLuaNilValue(Object? value) =>
    value == null || (value is Value && value.raw == null);

int luaTableLengthBoundary(bool Function(int index) hasValueAt) {
  if (!hasValueAt(1)) {
    return 0;
  }

  var lower = 1;

  // Prefer an early local border when a table has holes near the start.
  const linearProbeLimit = 64;
  while (lower < linearProbeLimit) {
    final nextIndex = lower + 1;
    if (!hasValueAt(nextIndex)) {
      return lower;
    }
    lower = nextIndex;
  }

  var upper = lower;
  while (upper < NumberLimits.maxInteger) {
    final nextUpper = upper > (NumberLimits.maxInteger ~/ 2)
        ? NumberLimits.maxInteger
        : upper * 2;
    if (!hasValueAt(nextUpper)) {
      upper = nextUpper;
      break;
    }
    if (nextUpper == NumberLimits.maxInteger) {
      return NumberLimits.maxInteger;
    }
    lower = nextUpper;
    upper = nextUpper;
  }

  while (upper - lower > 1) {
    final middle = lower + ((upper - lower) >> 1);
    if (hasValueAt(middle)) {
      lower = middle;
    } else {
      upper = middle;
    }
  }

  return lower;
}

int luaTableLengthFromMap(Map<dynamic, dynamic> map) {
  bool hasValueAt(int index) {
    final directValue = map[index];
    if (!isLuaNilValue(directValue)) {
      return true;
    }

    final numericValue = map[index.toDouble()];
    return !isLuaNilValue(numericValue);
  }

  return luaTableLengthBoundary(hasValueAt);
}

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
  final HashMap<dynamic, _HashOrderLink> _hashLinks =
      HashMap<dynamic, _HashOrderLink>();
  final LinkedHashMap<dynamic, dynamic> _deletedHashSuccessors =
      LinkedHashMap<dynamic, dynamic>();
  final LinkedHashMap<int, Object?> _deletedDenseIndices =
      LinkedHashMap<int, Object?>();
  int _reservedHashSlots = 0;
  dynamic _hashHead;
  dynamic _hashTail;

  int _arrayCount = 0;
  int _hashCount = 0;
  int _rawStringKeyChars = 0;

  static const int _maxArraySize = 1 << 20; // ~1M entries
  static const int _maxDeletedIterationKeys = 256;

  static int _rawStringKeyCharsFor(Object? key) {
    if (key is String) {
      return key.length;
    }
    if (key is LuaString) {
      return key.length;
    }
    return 0;
  }

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
        _deletedDenseIndices.remove(arrayIdx + 1);
      } else if (arrayIdx == _array.length) {
        _array.add(value);
        _growOccupied(arrayIdx + 1);
        _occupied[arrayIdx] = 1;
        _arrayCount++;
        _deletedDenseIndices.remove(arrayIdx + 1);
      } else {
        ensureArrayCapacity(arrayIdx + 1);
        _array[arrayIdx] = value;
        _occupied[arrayIdx] = 1;
        _arrayCount++;
        _deletedDenseIndices.remove(arrayIdx + 1);
      }
      _removeHashKey(key, recordDeletedSuccessor: false);
      return;
    }

    final previous = _hash[key];
    final contains = _hash.containsKey(key);
    _hash[key] = value;
    if (!contains) {
      _appendHashKey(key);
      _hashCount++;
      _rawStringKeyChars += _rawStringKeyCharsFor(key);
    } else if (previous == null && !_hashLinks.containsKey(key)) {
      _appendHashKey(key);
    }
    _deletedHashSuccessors.remove(key);
  }

  @override
  void clear() {
    _array.clear();
    _occupied = Uint8List(0);
    _hash.clear();
    _hashLinks.clear();
    _deletedHashSuccessors.clear();
    _deletedDenseIndices.clear();
    _hashHead = null;
    _hashTail = null;
    _arrayCount = 0;
    _hashCount = 0;
    _rawStringKeyChars = 0;
  }

  /// Appends [value] at the next sequential integer slot.
  void append(dynamic value) {
    final idx = _array.length;
    _array.add(value);
    _growOccupied(idx + 1);
    _occupied[idx] = 1;
    _arrayCount++;
    _deletedDenseIndices.remove(idx + 1);
    _removeHashKey(idx + 1, recordDeletedSuccessor: false);
  }

  /// Writes [value] at the (1-based) [index], leaving holes as necessary.
  /// Assumes [index] > 0.
  void setDense(int index, dynamic value) {
    if (index <= 0 || index > _maxArraySize) {
      this[index] = value;
      return;
    }

    final arrayIdx = index - 1;
    if (arrayIdx == _array.length) {
      _array.add(value);
      _growOccupied(arrayIdx + 1);
      _occupied[arrayIdx] = 1;
      _arrayCount++;
      _deletedDenseIndices.remove(index);
      _removeHashKey(index, recordDeletedSuccessor: false);
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
      _deletedDenseIndices.remove(index);
      _removeHashKey(index, recordDeletedSuccessor: false);
      return;
    }
    ensureArrayCapacity(index);
    _array[index - 1] = value;
    _occupied[index - 1] = 1;
    _arrayCount++;
    _deletedDenseIndices.remove(index);
    _removeHashKey(index, recordDeletedSuccessor: false);
  }

  void ensureArrayCapacity(int capacity) {
    if (capacity <= 0) return;
    final target = capacity > _maxArraySize ? _maxArraySize : capacity;
    if (target <= _array.length) return;
    final additional = target - _array.length;
    _array.addAll(List<dynamic>.filled(additional, null));
    _growOccupied(target);
  }

  void reserveHashCapacity(int capacity) {
    if (capacity <= 0) {
      return;
    }
    if (capacity > _reservedHashSlots) {
      _reservedHashSlots = capacity;
    }
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
    var key = _hashHead;
    while (key != null) {
      yield key;
      key = _hashLinks[key]?.nextKey;
    }
  }

  @override
  dynamic remove(Object? key) {
    final arrayIdx = _arrayIndexFor(key);
    if (arrayIdx != null) {
      if (arrayIdx >= _array.length) {
        return _removeHashKey(key);
      }
      if (arrayIdx >= _occupied.length || _occupied[arrayIdx] == 0) {
        return _removeHashKey(key);
      }
      final current = _array[arrayIdx];
      _array[arrayIdx] = null;
      _occupied[arrayIdx] = 0;
      _arrayCount--;
      _recordDeletedDenseIndex(arrayIdx + 1);
      _trimArray();
      return current;
    }
    return _removeHashKey(key);
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
      }
      return _hash.containsKey(key);
    }
    return _hash.containsKey(key);
  }

  @override
  int get length => _arrayCount + _hashCount;

  int get arrayLength => _array.length;
  int get reservedHashSlots => _reservedHashSlots;
  int get rawStringKeyChars => _rawStringKeyChars;

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

  bool hasPositiveIntegerValueAt(int oneBasedIndex) {
    if (oneBasedIndex <= 0) {
      return false;
    }

    final idx = oneBasedIndex - 1;
    if (idx < _array.length &&
        idx < _occupied.length &&
        _occupied[idx] != 0 &&
        !isLuaNilValue(_array[idx])) {
      return true;
    }

    final hashValue = _hash[oneBasedIndex];
    return !isLuaNilValue(hashValue);
  }

  int luaLengthBoundary() => luaTableLengthBoundary(hasPositiveIntegerValueAt);

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

    for (final MapEntry(key: key, value: value) in hashEntries) {
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

  bool containsIterationKey(Object? key) =>
      _hash.containsKey(key) ||
      _deletedHashSuccessors.containsKey(key) ||
      switch (_arrayIndexFor(key)) {
        final index? => _deletedDenseIndices.containsKey(index + 1),
        _ => false,
      };

  bool containsDenseIterationIndex(int oneBasedIndex) {
    if (oneBasedIndex <= 0) {
      return false;
    }
    if (denseValueAt(oneBasedIndex) != null) {
      return true;
    }
    return _deletedDenseIndices.containsKey(oneBasedIndex);
  }

  MapEntry<dynamic, dynamic>? firstHashEntry() {
    final key = _resolveNextLiveHashKey(_hashHead);
    if (key == null) {
      return null;
    }
    return MapEntry(key, _hash[key]);
  }

  MapEntry<dynamic, dynamic>? nextHashEntryAfter(Object? key) {
    final nextKey = _nextLiveHashKeyAfter(key);
    if (nextKey == null) {
      return null;
    }
    return MapEntry(nextKey, _hash[nextKey]);
  }

  Iterable<MapEntry<dynamic, dynamic>> get hashEntries sync* {
    var key = _resolveNextLiveHashKey(_hashHead);
    while (key != null) {
      final value = _hash[key];
      if (!isLuaNilValue(value)) {
        yield MapEntry(key, value);
      }
      key = _resolveNextLiveHashKey(_hashLinks[key]?.nextKey);
    }
  }

  void _appendHashKey(dynamic key) {
    if (_hashLinks.containsKey(key)) {
      return;
    }
    final link = _HashOrderLink(previousKey: _hashTail);
    _hashLinks[key] = link;
    if (_hashTail != null) {
      _hashLinks[_hashTail]?.nextKey = key;
    } else {
      _hashHead = key;
    }
    _hashTail = key;
  }

  dynamic _removeHashKey(Object? key, {bool recordDeletedSuccessor = true}) {
    if (!_hash.containsKey(key)) {
      return null;
    }

    final removed = _hash.remove(key);
    _rawStringKeyChars -= _rawStringKeyCharsFor(key);
    final link = _hashLinks.remove(key);
    if (link != null) {
      final previousKey = link.previousKey;
      final nextKey = link.nextKey;
      if (previousKey != null) {
        _hashLinks[previousKey]?.nextKey = nextKey;
      } else {
        _hashHead = nextKey;
      }
      if (nextKey != null) {
        _hashLinks[nextKey]?.previousKey = previousKey;
      } else {
        _hashTail = previousKey;
      }

      if (recordDeletedSuccessor) {
        _recordDeletedHashSuccessor(key, nextKey);
      }
    }

    _hashCount--;
    return removed;
  }

  void _recordDeletedHashSuccessor(Object? key, dynamic nextKey) {
    _deletedHashSuccessors.remove(key);
    _deletedHashSuccessors[key] = nextKey;
    while (_deletedHashSuccessors.length > _maxDeletedIterationKeys) {
      _deletedHashSuccessors.remove(_deletedHashSuccessors.keys.first);
    }
  }

  void _recordDeletedDenseIndex(int oneBasedIndex) {
    _deletedDenseIndices.remove(oneBasedIndex);
    _deletedDenseIndices[oneBasedIndex] = null;
    while (_deletedDenseIndices.length > _maxDeletedIterationKeys) {
      _deletedDenseIndices.remove(_deletedDenseIndices.keys.first);
    }
  }

  dynamic _resolveNextLiveHashKey(dynamic key) {
    final visited = <dynamic>{};
    var candidate = key;
    while (candidate != null) {
      if (!visited.add(candidate)) {
        return null;
      }
      if (_hash.containsKey(candidate)) {
        return candidate;
      }
      if (_deletedHashSuccessors.containsKey(candidate)) {
        candidate = _deletedHashSuccessors[candidate];
        continue;
      }
      return null;
    }
    return null;
  }

  dynamic _nextLiveHashKeyAfter(Object? key) {
    if (key == null) {
      return _resolveNextLiveHashKey(_hashHead);
    }
    final liveLink = _hashLinks[key];
    if (liveLink != null) {
      return _resolveNextLiveHashKey(liveLink.nextKey);
    }
    if (_deletedHashSuccessors.containsKey(key)) {
      return _resolveNextLiveHashKey(_deletedHashSuccessors[key]);
    }
    return null;
  }
}

final class _HashOrderLink {
  _HashOrderLink({this.previousKey});

  dynamic previousKey;
  dynamic nextKey;
}
