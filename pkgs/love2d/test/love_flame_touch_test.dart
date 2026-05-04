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
      await runtime.execute('''
testbed = {}
local poll = love.event.poll()
local name1, id1, x1, y1, dx1, dy1, pressure1
local name2, id2, x2, y2, dx2, dy2, pressure2
for i = 1, 4 do
  local name, a, b, c, d, e, f = poll()
  if name == nil then
    break
  end
  if name == "touchpressed" then
    name1, id1, x1, y1, dx1, dy1, pressure1 = name, a, b, c, d, e, f
  elseif name == "touchmoved" then
    name2, id2, x2, y2, dx2, dy2, pressure2 = name, a, b, c, d, e, f
  end
end
testbed.touchpressed = string.format("%s|%d|%.0f|%.0f|%.0f|%.0f|%.2f", name1, id1, x1, y1, dx1, dy1, pressure1)
testbed.touchmoved = string.format("%s|%d|%.0f|%.0f|%.0f|%.0f|%.2f", name2, id2, x2, y2, dx2, dy2, pressure2)
testbed.touchpressure = string.format("%.2f", love.touch.getPressure(id2))
''');

      expect(
        runtime.unwrapGlobalTable('testbed')!['touchpressed'],
        'touchpressed|17|10|20|0|0|0.75',
      );
      expect(
        runtime.unwrapGlobalTable('testbed')!['touchmoved'],
        'touchmoved|17|14|26|4|6|0.50',
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
      await runtime.execute('''
local poll = love.event.poll()
local name, id, x, y, dx, dy, pressure
for i = 1, 3 do
  local eventName, a, b, c, d, e, f = poll()
  if eventName == nil then
    break
  end
  if eventName == "touchreleased" then
    name, id, x, y, dx, dy, pressure = eventName, a, b, c, d, e, f
    break
  end
end
testbed.touchreleased = string.format("%s|%d|%.0f|%.0f|%.0f|%.0f|%.2f", name, id, x, y, dx, dy, pressure)
local touches = love.touch.getTouches()
testbed.touchreleasedempty = tostring(touches[1] == nil)
''');

      expect(
        runtime.unwrapGlobalTable('testbed')!['touchreleased'],
        'touchreleased|17|15|27|0|0|0.00',
      );
      expect(
        runtime.unwrapGlobalTable('testbed')!['touchreleasedempty'],
        'true',
      );
    });
  });
}
