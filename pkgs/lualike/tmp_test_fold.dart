import 'package:lualike/src/stdlib/lib_math.dart';
import 'package:lualike/src/stdlib/lib_string.dart';

void main() {
  print('math keys: ${MathLibrary.foldFunctions().keys}');
  print('string keys: ${StringLibrary.foldFunctions().keys}');
}
