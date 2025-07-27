/// Number limits for web platforms (53-bit integer precision).
/// https://dart.dev/resources/language/number-representation
class NumberLimits {
  /// The maximum safe integer value for a 53-bit float.
  static const int maxInteger = 9007199254740991; // 2^53 - 1

  /// The minimum safe integer value for a 53-bit float.
  static const int minInteger = -9007199254740991; // -(2^53 - 1)

  /// Maximum value for a 32-bit signed integer (INT_MAX in C/Lua)
  /// This is used for operations that need to match Lua's INT_MAX behavior
  /// such as table.unpack "too many results" checks
  static const int maxInt32 = 2147483647; // 2^31 - 1

  /// Minimum value for a 32-bit signed integer (INT_MIN in C/Lua)
  static const int minInt32 = -2147483648; // -2^31

  static const int sizeInBits = 64;
}
