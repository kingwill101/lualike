/// Number limits for native platforms (64-bit integers).
/// https://dart.dev/resources/language/number-representation
class NumberLimits {
  /// The maximum value for a 64-bit signed integer.
  static const int maxInteger = (1 << 63) - 1;

  /// The minimum value for a 64-bit signed integer.
  static const int minInteger = -(1 << 63);

  /// Maximum value for a 32-bit signed integer (INT_MAX in C/Lua)
  /// This is used for operations that need to match Lua's INT_MAX behavior
  /// such as table.unpack "too many results" checks
  static const int maxInt32 = 2147483647; // 2^31 - 1

  /// Minimum value for a 32-bit signed integer (INT_MIN in C/Lua)
  static const int minInt32 = -2147483648; // -2^31

  static const int sizeInBits = 64;
}
