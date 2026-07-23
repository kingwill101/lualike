import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('LoveScriptRuntime joystick callback helpers', () {
    test(
      'call joystick and gamepad callback helpers pass wrapped joysticks',
      () async {
        final connected = LoveJoystickDevice(id: 1, name: 'Arcade Pad');
        final added = LoveJoystickDevice(id: 2, name: 'Hotplug Pad');
        final removed = LoveJoystickDevice(id: 3, name: 'Ghost Pad')
          ..connected = false;
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(
            joysticks: LoveJoystickManager(
              devices: <LoveJoystickDevice>[connected],
            ),
          ),
        );

        await runtime.execute('''
testbed = {}

local function describe(j)
  local id, instance = j:getID()
  return string.format(
    "%s|%s|%s|%d|%s|%s|%d",
    j:type(),
    tostring(j:typeOf("Joystick")),
    tostring(j:typeOf("Object")),
    id,
    tostring(instance),
    tostring(j:isConnected()),
    j:release() and 1 or 0
  )
end

function love.joystickpressed(j, button)
  testbed.joystickpressed = string.format("%s|%d", describe(j), button)
end

function love.joystickreleased(j, button)
  testbed.joystickreleased = string.format("%s|%d", describe(j), button)
end

function love.joystickaxis(j, axis, value)
  testbed.joystickaxis = string.format("%s|%d|%.2f", describe(j), axis, value)
end

function love.joystickhat(j, hat, value)
  testbed.joystickhat = string.format("%s|%d|%s", describe(j), hat, value)
end

function love.gamepadpressed(j, button)
  testbed.gamepadpressed = string.format("%s|%s", describe(j), button)
end

function love.gamepadreleased(j, button)
  testbed.gamepadreleased = string.format("%s|%s", describe(j), button)
end

function love.gamepadaxis(j, axis, value)
  testbed.gamepadaxis = string.format("%s|%s|%.2f", describe(j), axis, value)
end

function love.joystickadded(j)
  testbed.joystickadded = describe(j)
end

function love.joystickremoved(j)
  testbed.joystickremoved = describe(j)
end
''');

        await runtime.callJoystickPressedIfDefined(connected, 3);
        await runtime.callJoystickReleasedIfDefined(connected, 4);
        await runtime.callJoystickAxisIfDefined(connected, 2, 0.75);
        await runtime.callJoystickHatIfDefined(connected, 1, 'lu');
        await runtime.callGamepadPressedIfDefined(connected, 'start');
        await runtime.callGamepadReleasedIfDefined(connected, 'back');
        await runtime.callGamepadAxisIfDefined(connected, 'rightx', -0.5);
        await runtime.callJoystickAddedIfDefined(added);
        await runtime.callJoystickRemovedIfDefined(removed);

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['joystickpressed'], 'Joystick|true|true|1|1|true|1|3');
        expect(snapshot['joystickreleased'], 'Joystick|true|true|1|1|true|0|4');
        expect(
          snapshot['joystickaxis'],
          'Joystick|true|true|1|1|true|0|2|0.75',
        );
        expect(snapshot['joystickhat'], 'Joystick|true|true|1|1|true|0|1|lu');
        expect(
          snapshot['gamepadpressed'],
          'Joystick|true|true|1|1|true|0|start',
        );
        expect(
          snapshot['gamepadreleased'],
          'Joystick|true|true|1|1|true|0|back',
        );
        expect(
          snapshot['gamepadaxis'],
          'Joystick|true|true|1|1|true|0|rightx|-0.50',
        );
        expect(snapshot['joystickadded'], 'Joystick|true|true|2|2|true|1');
        expect(snapshot['joystickremoved'], 'Joystick|true|true|3|nil|false|1');
      },
    );

    test(
      'dispatch joystick and gamepad helpers queue events and invoke callbacks with matching payloads',
      () async {
        final connected = LoveJoystickDevice(id: 1, name: 'Arcade Pad');
        final added = LoveJoystickDevice(id: 2, name: 'Hotplug Pad');
        final removed = LoveJoystickDevice(id: 3, name: 'Ghost Pad')
          ..connected = false;
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(
            joysticks: LoveJoystickManager(
              devices: <LoveJoystickDevice>[connected],
            ),
          ),
        );

        await runtime.execute('''
testbed = {}

function love.joystickpressed(j, button)
  local poll = love.event.poll()
  local name, queued, queuedButton = poll()
  testbed.joystickpressed = string.format("%s|%s|%d|%d|%s", name, tostring(queued == j), queuedButton, button, tostring(queued:isConnected()))
end

function love.joystickreleased(j, button)
  local poll = love.event.poll()
  local name, queued, queuedButton = poll()
  testbed.joystickreleased = string.format("%s|%s|%d|%d|%s", name, tostring(queued == j), queuedButton, button, tostring(queued:isConnected()))
end

function love.joystickaxis(j, axis, value)
  local poll = love.event.poll()
  local name, queued, queuedAxis, queuedValue = poll()
  testbed.joystickaxis = string.format("%s|%s|%d|%d|%.2f|%.2f", name, tostring(queued == j), queuedAxis, axis, queuedValue, value)
end

function love.joystickhat(j, hat, value)
  local poll = love.event.poll()
  local name, queued, queuedHat, queuedValue = poll()
  testbed.joystickhat = string.format("%s|%s|%d|%d|%s|%s", name, tostring(queued == j), queuedHat, hat, queuedValue, value)
end

function love.gamepadpressed(j, button)
  local poll = love.event.poll()
  local name, queued, queuedButton = poll()
  testbed.gamepadpressed = string.format("%s|%s|%s|%s|%s", name, tostring(queued == j), queuedButton, button, tostring(queued:isConnected()))
end

function love.gamepadreleased(j, button)
  local poll = love.event.poll()
  local name, queued, queuedButton = poll()
  testbed.gamepadreleased = string.format("%s|%s|%s|%s|%s", name, tostring(queued == j), queuedButton, button, tostring(queued:isConnected()))
end

function love.gamepadaxis(j, axis, value)
  local poll = love.event.poll()
  local name, queued, queuedAxis, queuedValue = poll()
  testbed.gamepadaxis = string.format("%s|%s|%s|%s|%.2f|%.2f", name, tostring(queued == j), queuedAxis, axis, queuedValue, value)
end

function love.joystickadded(j)
  local poll = love.event.poll()
  local name, queued = poll()
  testbed.joystickadded = string.format("%s|%s|%s|%s", name, tostring(queued == j), queued:getName(), tostring(queued:isConnected()))
end

function love.joystickremoved(j)
  local poll = love.event.poll()
  local name, queued = poll()
  testbed.joystickremoved = string.format("%s|%s|%s|%s", name, tostring(queued == j), queued:getName(), tostring(queued:isConnected()))
end
''');

        await runtime.dispatchJoystickPressed(connected, 4);
        await runtime.dispatchJoystickReleased(connected, 5);
        await runtime.dispatchJoystickAxis(connected, 2, 0.75);
        await runtime.dispatchJoystickHat(connected, 1, 'lu');
        await runtime.dispatchGamepadPressed(connected, 'start');
        await runtime.dispatchGamepadReleased(connected, 'back');
        await runtime.dispatchGamepadAxis(connected, 'rightx', -0.5);
        await runtime.dispatchJoystickAdded(added);
        await runtime.dispatchJoystickRemoved(removed);

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['joystickpressed'], 'joystickpressed|true|4|4|true');
        expect(snapshot['joystickreleased'], 'joystickreleased|true|5|5|true');
        expect(snapshot['joystickaxis'], 'joystickaxis|true|2|2|0.75|0.75');
        expect(snapshot['joystickhat'], 'joystickhat|true|1|1|lu|lu');
        expect(
          snapshot['gamepadpressed'],
          'gamepadpressed|true|start|start|true',
        );
        expect(
          snapshot['gamepadreleased'],
          'gamepadreleased|true|back|back|true',
        );
        expect(
          snapshot['gamepadaxis'],
          'gamepadaxis|true|rightx|rightx|-0.50|-0.50',
        );
        expect(
          snapshot['joystickadded'],
          'joystickadded|true|Hotplug Pad|true',
        );
        expect(
          snapshot['joystickremoved'],
          'joystickremoved|true|Ghost Pad|false',
        );
      },
    );

    test(
      'dispatch joystick helpers still queue events when callbacks are undefined',
      () async {
        final connected = LoveJoystickDevice(id: 1, name: 'Arcade Pad');
        final removed = LoveJoystickDevice(id: 3, name: 'Ghost Pad')
          ..connected = false;
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(
            joysticks: LoveJoystickManager(
              devices: <LoveJoystickDevice>[connected],
            ),
          ),
        );

        await runtime.dispatchJoystickPressed(connected, 4);
        await runtime.dispatchJoystickReleased(connected, 5);
        await runtime.dispatchJoystickAxis(connected, 2, 0.75);
        await runtime.dispatchJoystickHat(connected, 1, 'lu');
        await runtime.dispatchGamepadPressed(connected, 'start');
        await runtime.dispatchGamepadReleased(connected, 'back');
        await runtime.dispatchGamepadAxis(connected, 'rightx', -0.5);
        await runtime.dispatchJoystickAdded(
          LoveJoystickDevice(id: 2, name: 'Hotplug Pad'),
        );
        await runtime.dispatchJoystickRemoved(removed);

        await runtime.execute('''
testbed = {}
local poll = love.event.poll()

local function capture(index)
  local name, joystick, a, b = poll()
  if name == nil then
    testbed[index] = nil
    return
  end

  local id = select(1, joystick:getID())
  local summary = string.format("%s|%s|%d", name, tostring(joystick:isConnected()), id)
  if a ~= nil then
    summary = summary .. "|" .. tostring(a)
  end
  if b ~= nil then
    summary = summary .. "|" .. tostring(b)
  end
  testbed[index] = summary
end

for i = 1, 9 do
  capture(i)
end
testbed.empty = poll() == nil
''');

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['1'], 'joystickpressed|true|1|4');
        expect(snapshot['2'], 'joystickreleased|true|1|5');
        expect(snapshot['3'], 'joystickaxis|true|1|2|0.75');
        expect(snapshot['4'], 'joystickhat|true|1|1|lu');
        expect(snapshot['5'], 'gamepadpressed|true|1|start');
        expect(snapshot['6'], 'gamepadreleased|true|1|back');
        expect(snapshot['7'], 'gamepadaxis|true|1|rightx|-0.5');
        expect(snapshot['8'], 'joystickadded|true|2');
        expect(snapshot['9'], 'joystickremoved|false|3');
        expect(snapshot['empty'], isTrue);
      },
    );

    test('return null when joystick callbacks are undefined', () async {
      final removed = LoveJoystickDevice(id: 3, name: 'Ghost Pad')
        ..connected = false;
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      expect(await runtime.callJoystickPressedIfDefined(removed, 1), isNull);
      expect(await runtime.callJoystickReleasedIfDefined(removed, 1), isNull);
      expect(await runtime.callJoystickAxisIfDefined(removed, 1, 0.0), isNull);
      expect(await runtime.callJoystickHatIfDefined(removed, 1, 'c'), isNull);
      expect(await runtime.callGamepadPressedIfDefined(removed, 'a'), isNull);
      expect(await runtime.callGamepadReleasedIfDefined(removed, 'a'), isNull);
      expect(
        await runtime.callGamepadAxisIfDefined(removed, 'leftx', 0.0),
        isNull,
      );
      expect(await runtime.callJoystickAddedIfDefined(removed), isNull);
      expect(await runtime.callJoystickRemovedIfDefined(removed), isNull);
    });
  });
}
