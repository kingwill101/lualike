import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.touch module', () {
    late LuaRuntime runtime;
    late LuaLike lualike;
    late LoveHeadlessHost host;

    setUp(() {
      lualike = LuaLike();
      runtime = lualike.vm;
      host = LoveHeadlessHost();
      installLove2d(runtime: runtime, host: host);
    });

    test('reports active touches in insertion order', () async {
      host.touch.beginTouch(id: 11, x: 10.5, y: 20.25, pressure: 0.75);
      host.touch.beginTouch(id: 12, x: 30.0, y: 40.0, pressure: 1.0);
      host.touch.beginTouch(id: 11, x: 15.0, y: 25.0, pressure: 0.5);

      expect(
        ((await lualike.execute('return love.touch.getTouches()')) as Value)
            .unwrap(),
        <Object?>[12, 11],
      );
      final positionResult = await lualike.execute('return love.touch.getPosition(11)');
      expect(
        (positionResult as List).map((e) => (e as Value).unwrap()).toList(),
        <Object?>[15.0, 25.0],
      );
      expect(
        ((await lualike.execute('return love.touch.getPressure(11)')) as Value)
            .unwrap(),
        0.5,
      );
    });

    test('rejects inactive touch ids', () async {
      host.touch.beginTouch(id: 21, x: 1.0, y: 2.0, pressure: 1.0);
      host.touch.endTouch(21);

      await expectLater(
        lualike.execute('return love.touch.getPosition(21)'),
        throwsA(isA<LuaError>()),
      );
      await expectLater(
        lualike.execute('return love.touch.getPressure(21)'),
        throwsA(isA<LuaError>()),
      );
    });
  });
}
