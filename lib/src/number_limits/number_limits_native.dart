/// Number limits for native platforms (64-bit integers).
/// https://dart.dev/resources/language/number-representation
class NumberLimits {
  /// The maximum value for a 64-bit signed integer.
  static const int maxInteger = (1 << 63) - 1;

  /// The minimum value for a 64-bit signed integer.
  static const int minInteger = -(1 << 63);

  static const int sizeInBits = 64;
}
