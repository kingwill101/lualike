import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.touch module', () {
    late Interpreter runtime;
    late LoveHeadlessHost host;

    setUp(() {
      runtime = Interpreter();
      host = LoveHeadlessHost();
      installLove2d(runtime: runtime, host: host);
    });

    test('reports active touches in insertion order', () async {
      host.touch.beginTouch(id: 11, x: 10.5, y: 20.25, pressure: 0.75);
      host.touch.beginTouch(id: 12, x: 30.0, y: 40.0, pressure: 1.0);
      host.touch.beginTouch(id: 11, x: 15.0, y: 25.0, pressure: 0.5);

      expect(
        await luaCall(runtime, const ['love', 'touch', 'getTouches']),
        <Object?, Object?>{1: 12, 2: 11},
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'touch', 'getPosition'],
          const <Object?>[11],
        ),
        <Object?>[15.0, 25.0],
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'touch', 'getPressure'],
          const <Object?>[11],
        ),
        0.5,
      );
    });

    test('rejects inactive touch ids', () async {
      host.touch.beginTouch(id: 21, x: 1.0, y: 2.0, pressure: 1.0);
      host.touch.endTouch(21);

      await expectLater(
        luaCall(
          runtime,
          const ['love', 'touch', 'getPosition'],
          const <Object?>[21],
        ),
        throwsA(isA<LuaError>()),
      );
      await expectLater(
        luaCall(
          runtime,
          const ['love', 'touch', 'getPressure'],
          const <Object?>[21],
        ),
        throwsA(isA<LuaError>()),
      );
    });
  });
}
