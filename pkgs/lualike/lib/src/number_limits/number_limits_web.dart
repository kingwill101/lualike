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

  /// Number of explicitly stored significand bits in an IEEE-754 double.
  static const int doubleStoredSignificandBits = 52;

  /// Exponent bias for an IEEE-754 double.
  static const int doubleExponentBias = 1023;

  /// Largest unbiased exponent for a finite IEEE-754 double.
  static const int doubleMaxExponent = 1023;

  /// Smallest unbiased exponent for a normal IEEE-754 double.
  static const int doubleMinExponent = -1022;

  /// Smallest unbiased exponent for a subnormal IEEE-754 double.
  static const int doubleMinSubnormalExponent = -1074;

  /// Sign bit plus fraction bits from an IEEE-754 double bit pattern.
  ///
  /// Keep this out of a shared const literal because dart2js rejects the full
  /// 64-bit hex literal during compilation.
  static final int doubleSignAndFractionMask = int.parse(
    '800fffffffffffff',
    radix: 16,
  );

  static const int sizeInBits = 64;
}
