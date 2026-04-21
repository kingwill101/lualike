part of '../love_runtime.dart';

final Expando<_LoveRandomNormalCacheEntry> _loveRandomNormalCache =
    Expando<_LoveRandomNormalCacheEntry>('loveRandomNormalCache');

class _LoveRandomNormalCacheEntry {
  double? value;
}

_LoveRandomNormalCacheEntry _loveRandomNormalCacheEntry(
  LoveRandomGenerator generator,
) {
  final cached = _loveRandomNormalCache[generator];
  if (cached != null) {
    return cached;
  }

  final entry = _LoveRandomNormalCacheEntry();
  _loveRandomNormalCache[generator] = entry;
  return entry;
}

void _resetLoveRandomNormalCache(LoveRandomGenerator generator) {
  _loveRandomNormalCacheEntry(generator).value = null;
}

BigInt _wangHash64(BigInt key) {
  final mask64 = LoveRandomGenerator._mask64;

  key = (~key) + (key << 21);
  key &= mask64;
  key ^= key >> 24;
  key &= mask64;
  key = (key + (key << 3) + (key << 8)) & mask64;
  key ^= key >> 14;
  key &= mask64;
  key = (key + (key << 2) + (key << 4)) & mask64;
  key ^= key >> 28;
  key &= mask64;
  key = (key + (key << 31)) & mask64;
  return key;
}

BigInt _loveRandomSeedToState({required int low, required int high}) {
  final combined =
      ((NumberUtils.toBigInt(high & LoveRandomGenerator._mask32) <<
              LoveRandomGenerator._seedBits) |
          NumberUtils.toBigInt(low & LoveRandomGenerator._mask32)) &
      LoveRandomGenerator._mask64;

  var state = combined;
  do {
    state = _wangHash64(state);
  } while (state == BigInt.zero);

  return state;
}

extension LoveRandomGeneratorCompatibility on LoveRandomGenerator {
  double random([double? low, double? high]) {
    final value = nextUnitDouble();
    if (low == null) {
      return value;
    }

    if (high == null) {
      return (value * low).floorToDouble() + 1.0;
    }

    return (value * (high - low + 1.0)).floorToDouble() + low;
  }

  double randomNormal([double stddev = 1.0, double mean = 0.0]) {
    final cacheEntry = _loveRandomNormalCacheEntry(this);
    final cached = cacheEntry.value;
    if (cached != null) {
      cacheEntry.value = null;
      return (cached * stddev) + mean;
    }

    final r = math.sqrt(-2.0 * math.log(1.0 - nextUnitDouble()));
    final phi = 2.0 * math.pi * (1.0 - nextUnitDouble());

    cacheEntry.value = r * math.cos(phi);
    return (r * math.sin(phi) * stddev) + mean;
  }

  void setState(String stateString) {
    if (!stateString.startsWith('0x') || stateString.length < 3) {
      throw ArgumentError('Invalid random state: $stateString');
    }

    final parsed = BigInt.tryParse(stateString.substring(2), radix: 16);
    if (parsed == null) {
      throw ArgumentError('Invalid random state: $stateString');
    }

    _state = LoveRandomGenerator._normalizeUint64(parsed);
    _resetLoveRandomNormalCache(this);
  }

  String getState() {
    final state = _state & LoveRandomGenerator._mask64;
    return '0x${state.toRadixString(16).padLeft(16, '0')}';
  }
}
