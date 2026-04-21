import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('LoveFlameInputAdapter touch bridge', () {
    late LoveHeadlessHost host;
    late LoveScriptRuntime runtime;
    late LoveFlameInputAdapter adapter;

    setUp(() async {
      host = LoveHeadlessHost();
      runtime = LoveScriptRuntime(host: host);
      adapter = LoveFlameInputAdapter(
        host: host,
        runtimeProvider: () => runtime,
      );

      await runtime.execute('''
testbed = {}

function love.touchpressed(id, x, y, dx, dy, pressure)
  testbed.touchpressed = string.format("%d,%.0f,%.0f,%.0f,%.0f,%.2f", id, x, y, dx, dy, pressure)
end

function love.touchmoved(id, x, y, dx, dy, pressure)
  testbed.touchmoved = string.format("%d,%.0f,%.0f,%.0f,%.0f,%.2f", id, x, y, dx, dy, pressure)
  testbed.touchpressure = string.format("%.2f", love.touch.getPressure(id))
end

function love.touchreleased(id, x, y, dx, dy, pressure)
  testbed.touchreleased = string.format("%d,%.0f,%.0f,%.0f,%.0f,%.2f", id, x, y, dx, dy, pressure)
  local touches = love.touch.getTouches()
  testbed.touchreleasedempty = tostring(touches[1] == nil)
end
''');
    });

    test('tracks active touches and dispatches callbacks', () async {
      adapter.handlePointerDown(
        const PointerDownEvent(
          kind: PointerDeviceKind.touch,
          pointer: 17,
          position: Offset(10, 20),
          pressure: 0.75,
        ),
      );
      expect(host.touch.getTouches(), <int>[17]);
      expect(host.touch.activeTouch(17), isNotNull);
      expect(host.touch.activeTouch(17)!.x, 10);
      expect(host.touch.activeTouch(17)!.y, 20);

      adapter.handlePointerMove(
        const PointerMoveEvent(
          kind: PointerDeviceKind.touch,
          pointer: 17,
          position: Offset(14, 26),
          delta: Offset(4, 6),
          pressure: 0.5,
        ),
      );
      expect(host.touch.getTouches(), <int>[17]);
      expect(host.touch.activeTouch(17), isNotNull);
      expect(host.touch.activeTouch(17)!.x, 14);
      expect(host.touch.activeTouch(17)!.y, 26);
      expect(host.touch.activeTouch(17)!.dx, 4);
      expect(host.touch.activeTouch(17)!.dy, 6);
      expect(host.touch.activeTouch(17)!.pressure, 0.5);

      await adapter.flush();

      expect(
        runtime.unwrapGlobalTable('testbed')!['touchpressed'],
        '17,10,20,0,0,0.75',
      );
      expect(
        runtime.unwrapGlobalTable('testbed')!['touchmoved'],
        '17,14,26,4,6,0.50',
      );
      expect(runtime.unwrapGlobalTable('testbed')!['touchpressure'], '0.50');

      adapter.handlePointerUp(
        const PointerUpEvent(
          kind: PointerDeviceKind.touch,
          pointer: 17,
          position: Offset(15, 27),
          pressure: 0.0,
        ),
      );
      expect(host.touch.getTouches(), isEmpty);

      await adapter.flush();

      expect(
        runtime.unwrapGlobalTable('testbed')!['touchreleased'],
        '17,15,27,0,0,0.00',
      );
      expect(
        runtime.unwrapGlobalTable('testbed')!['touchreleasedempty'],
        'true',
      );
    });
  });
}
