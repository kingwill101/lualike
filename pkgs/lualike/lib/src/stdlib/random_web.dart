// Web implementation using dart:math Random
import 'dart:math' as math;

// Export the standard Random class as a substitute for Xoshiro256ss
class Xoshiro256ss {
  final math.Random _random;

  Xoshiro256ss(int a, int b, int c, int d)
    : _random = math.Random(a ^ b ^ c ^ d);
  Xoshiro256ss.seeded([int? seed]) : _random = math.Random(seed);

  double nextDouble() => _random.nextDouble();
  int nextInt(int max) => _random.nextInt(max);

  // Web-compatible stub for nextRaw64 - returns positive 32-bit values
  int nextRaw64() => _random.nextInt(0x7FFFFFFF);
}
