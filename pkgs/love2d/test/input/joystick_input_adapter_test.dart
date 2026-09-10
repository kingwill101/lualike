import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('LoveJoystickInputAdapter', () {
    late LoveHeadlessHost host;
    late LoveScriptRuntime runtime;
    late LoveJoystickInputAdapter adapter;
    late LoveJoystickDevice joystick;

    setUp(() {
      host = LoveHeadlessHost();
      runtime = LoveScriptRuntime(host: host);
      adapter = LoveJoystickInputAdapter(
        host: host,
        runtimeProvider: () => runtime,
      );
      joystick = LoveJoystickDevice(
        id: 7,
        name: 'Arcade Stick',
        connected: false,
      );
    });

    test('tracks joystick state and dispatches callbacks', () async {
      adapter.handleDeviceAdded(joystick);
      await adapter.flush();
      await runtime.execute('''
testbed = {}
local poll = love.event.poll()
local name, j = poll()
testbed.added = string.format("%s|%s|%d|%d", name, tostring(j:isConnected()), love.joystick.getJoystickCount(), select(1, j:getID()))
testbed.empty_after_added = poll() == nil
''');

      adapter.handleJoystickButtonDown(joystick, 2);
      await adapter.flush();
      await runtime.execute('''
local poll = love.event.poll()
local name, j, button = poll()
testbed.jpressed = string.format("%s|%s|%d|%s", name, tostring(j:isConnected()), button, tostring(j:isDown(button)))
''');

      adapter.handleJoystickAxisMotion(joystick, 1, 0.5);
      await adapter.flush();
      await runtime.execute('''
local poll = love.event.poll()
local name, j, axis, value = poll()
testbed.jaxis = string.format("%s|%s|%d|%.2f|%.2f", name, tostring(j:isConnected()), axis, value, j:getAxis(axis))
''');

      adapter.handleJoystickHatMotion(joystick, 1, 'r');
      await adapter.flush();
      await runtime.execute('''
local poll = love.event.poll()
local name, j, hat, value = poll()
testbed.jhat = string.format("%s|%s|%d|%s|%s", name, tostring(j:isConnected()), hat, value, j:getHat(hat))
''');

      adapter.handleGamepadButtonDown(joystick, 'a');
      await adapter.flush();
      await runtime.execute('''
local poll = love.event.poll()
local name, j, button = poll()
testbed.gpressed = string.format("%s|%s|%s|%s", name, tostring(j:isConnected()), button, tostring(j:isGamepadDown(button)))
''');

      adapter.handleGamepadAxisMotion(joystick, 'leftx', 1.0);
      await adapter.flush();
      await runtime.execute('''
local poll = love.event.poll()
local name, j, axis, value = poll()
testbed.gaxis = string.format("%s|%s|%s|%.2f|%.2f", name, tostring(j:isConnected()), axis, value, j:getGamepadAxis(axis))
''');

      adapter.handleGamepadButtonUp(joystick, 'a');
      await adapter.flush();
      await runtime.execute('''
local poll = love.event.poll()
local name, j, button = poll()
testbed.greleased = string.format("%s|%s|%s|%s", name, tostring(j:isConnected()), button, tostring(j:isGamepadDown(button)))
''');

      adapter.handleJoystickButtonUp(joystick, 2);
      await adapter.flush();
      await runtime.execute('''
local poll = love.event.poll()
local name, j, button = poll()
testbed.jreleased = string.format("%s|%s|%d|%s", name, tostring(j:isConnected()), button, tostring(j:isDown(button)))
''');

      adapter.handleDeviceRemoved(joystick);
      await adapter.flush();
      await runtime.execute('''
local poll = love.event.poll()
local name, j = poll()
local sticks = love.joystick.getJoysticks()
testbed.removed = string.format("%s|%s|%s|%s|%d", name, tostring(j:isConnected()), tostring(j:isConnected()), tostring(sticks[1] == nil), love.joystick.getJoystickCount())
''');

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['added'], 'joystickadded|true|1|7');
      expect(snapshot['empty_after_added'], isTrue);
      expect(snapshot['jpressed'], 'joystickpressed|true|2|true');
      expect(snapshot['jreleased'], 'joystickreleased|true|2|false');
      expect(snapshot['jaxis'], 'joystickaxis|true|1|0.50|0.50');
      expect(snapshot['jhat'], 'joystickhat|true|1|r|r');
      expect(snapshot['gpressed'], 'gamepadpressed|true|a|true');
      expect(snapshot['greleased'], 'gamepadreleased|true|a|false');
      expect(snapshot['gaxis'], 'gamepadaxis|true|leftx|1.00|1.00');
      expect(snapshot['removed'], 'joystickremoved|false|false|true|0');
      expect(host.joysticks.devices, isEmpty);
      expect(host.joysticks.connectedDevices, isEmpty);
      expect(joystick.connected, isFalse);
    });

    test('queues joystick events when callbacks are undefined', () async {
      adapter.handleDeviceAdded(joystick);
      adapter.handleJoystickButtonDown(joystick, 2);
      adapter.handleGamepadButtonDown(joystick, 'a');
      adapter.handleDeviceRemoved(joystick);

      await adapter.flush();

      await runtime.execute('''
testbed = {}
local poll = love.event.poll()

for i = 1, 4 do
  local name, j, arg = poll()
  if name == nil then
    break
  end
  testbed[tostring(i)] = string.format("%s|%s|%d|%s", name, tostring(j:isConnected()), select(1, j:getID()), tostring(arg))
end

testbed.empty = poll() == nil
''');

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['1'], 'joystickadded|false|7|nil');
      expect(snapshot['2'], 'joystickpressed|false|7|2');
      expect(snapshot['3'], 'gamepadpressed|false|7|a');
      expect(snapshot['4'], 'joystickremoved|false|7|nil');
      expect(snapshot['empty'], isTrue);
      expect(host.joysticks.devices, isEmpty);
    });

    test('updates joystick state without a runtime', () async {
      final runtimeLessAdapter = LoveJoystickInputAdapter(
        host: host,
        runtimeProvider: () => null,
      );

      runtimeLessAdapter.handleDeviceAdded(joystick);
      runtimeLessAdapter.handleJoystickButtonDown(joystick, 3);
      runtimeLessAdapter.handleJoystickAxisMotion(joystick, 1, -0.25);
      runtimeLessAdapter.handleJoystickHatMotion(joystick, 1, 'lu');
      runtimeLessAdapter.handleGamepadButtonDown(joystick, 'b');
      runtimeLessAdapter.handleGamepadAxisMotion(joystick, 'lefty', 0.75);

      await runtimeLessAdapter.flush();

      expect(host.joysticks.connectedDevices, hasLength(1));
      expect(joystick.isDown(const <int>[3]), isTrue);
      expect(joystick.getAxis(1), -0.25);
      expect(joystick.getHat(1), 'lu');
      expect(joystick.isGamepadDown(const <String>['b']), isTrue);
      expect(joystick.getGamepadAxis('lefty'), 0.75);

      runtimeLessAdapter.handleGamepadButtonUp(joystick, 'b');
      runtimeLessAdapter.handleJoystickButtonUp(joystick, 3);
      runtimeLessAdapter.handleDeviceRemoved(joystick);

      await runtimeLessAdapter.flush();

      expect(joystick.isDown(const <int>[3]), isFalse);
      expect(joystick.isGamepadDown(const <String>['b']), isFalse);
      expect(joystick.connected, isFalse);
      expect(host.joysticks.devices, isEmpty);
      expect(host.joysticks.connectedDevices, isEmpty);
    });
  });
}
