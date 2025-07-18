/// Number limits for web platforms (53-bit integer precision).
/// https://dart.dev/resources/language/number-representation
class NumberLimits {
  /// The maximum safe integer value for a 53-bit float.
  static const int maxInteger = 9007199254740991; // 2^53 - 1

  /// The minimum safe integer value for a 53-bit float.
  static const int minInteger = -9007199254740991; // -(2^53 - 1)

  static const int sizeInBits = 64;
}
