/// Centralized type sizes for Lua 5.4 binary packing/unpacking.
/// These are the default C sizes for each type; adjust as needed for platform.
class BinaryTypeSize {
  static const int b = 1; // signed byte
  static const int B = 1; // unsigned byte
  static const int h = 2; // signed short
  static const int H = 2; // unsigned short
  static const int l = 8; // signed long (assuming 64-bit)
  static const int L = 8; // unsigned long (assuming 64-bit)
  static const int j = 8; // lua_Integer (assuming 64-bit)
  static const int J = 8; // unsigned lua_Integer (assuming 64-bit)
  static const int T = 8; // size_t (assuming 64-bit)
  static const int f = 4; // float
  static const int d = 8; // double
  static const int n = 8; // native float (Lua number, assuming double)
  static const int i = 4; // int (default, can be overridden by format)
  static const int I = 4; // unsigned int (default, can be overridden by format)
}
