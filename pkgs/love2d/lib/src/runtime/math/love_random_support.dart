part of '../love_runtime.dart';

/// Caches the spare normal-distribution sample for each random generator.
final Expando<_LoveRandomNormalCacheEntry> _loveRandomNormalCache =
    Expando<_LoveRandomNormalCacheEntry>('loveRandomNormalCache');

/// The cached normal-distribution sample associated with one generator.
class _LoveRandomNormalCacheEntry {
  /// The spare Box-Muller sample waiting to be consumed, if one exists.
  double? value;
}

/// Returns the cached normal-sample entry associated with [generator].
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

/// Clears any cached normal-distribution sample for [generator].
void _resetLoveRandomNormalCache(LoveRandomGenerator generator) {
  _loveRandomNormalCacheEntry(generator).value = null;
}

/// Applies Wang's 64-bit integer hash to [key].
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

/// Converts LOVE's split 32-bit seed values into a non-zero generator state.
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

/// Compatibility helpers that implement LOVE-style random generator behavior.
extension LoveRandomGeneratorCompatibility on LoveRandomGenerator {
  /// Returns a random value using LOVE's `RandomGenerator:random` semantics.
  ///
  /// With no arguments this returns a unit double. With one argument it returns
  /// an integer in the inclusive range `1..low`. With two arguments it returns
  /// an integer in the inclusive range `low..high`.
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

  /// Returns a normally distributed random value.
  ///
  /// This uses the Box-Muller transform and caches the spare sample for the
  /// next call, matching LOVE's generator behavior.
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

  /// Restores the generator state from LOVE's hexadecimal state string.
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

  /// The current generator state encoded as LOVE's hexadecimal state string.
  String getState() {
    final state = _state & LoveRandomGenerator._mask64;
    return '0x${state.toRadixString(16).padLeft(16, '0')}';
  }
}
