import 'package:test/test.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/lua_error.dart';

void main() {
  group('Invalid escape sequences', () {
    const literals = [
      '"abc\\x"',
      '"abc\\x',
      '"\\x',
      '"\\x5"',
      '"\\x5',
      '"\\xr"',
      '"\\xr',
      '"\\x."',
      '"\\x8%"',
      '"\\xAG',
      '"\\g"',
      '"\\g',
      '"\\."',
      '"\\999"',
      '"xyz\\300"',
      '"   \\256"',
    ];

    for (final lit in literals) {
      test('fails for $lit', () {
        expect(
          () => parse('return $lit'),
          throwsA(anyOf(isA<LuaError>(), isA<FormatException>())),
        );
      });
    }
  });
}
