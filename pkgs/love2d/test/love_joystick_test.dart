import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

const String _testGuid = '030000005e0400008e02000014010000';

void main() {
  group('love.joystick', () {
    test('exposes joystick state, mappings, and enum tables', () async {
      final joysticks = LoveJoystickManager();
      final device = LoveJoystickDevice(
        id: 7,
        instanceId: 42,
        name: 'Pad 1',
        guid: _testGuid,
        vendorId: 1118,
        productId: 654,
        productVersion: 2,
        axes: const <double>[0.25, -0.5, 1.0],
        buttonCount: 4,
        buttonsDown: const <int>{2, 4},
        hats: const <String>['ru', 'c'],
        gamepadAxes: const <String, double>{'leftx': 0.5, 'triggerleft': 1.0},
        gamepadButtons: const <String>{'a', 'dpup'},
        vibrationSupported: true,
      );
      joysticks.addDevice(device);
      expect(
        joysticks.setGamepadMapping(_testGuid, 'leftx', 'axis', 1),
        isTrue,
      );
      expect(joysticks.setGamepadMapping(_testGuid, 'a', 'button', 2), isTrue);
      expect(
        joysticks.setGamepadMapping(
          _testGuid,
          'dpup',
          'hat',
          1,
          hatDirection: 'u',
        ),
        isTrue,
      );

      final runtime = LoveScriptRuntime(
        host: LoveHeadlessHost(joysticks: joysticks),
      );

      await runtime.execute('''
testbed = {}

local pad = love.joystick.getJoysticks()[1]
local id, instanceid = pad:getID()
local vendor, product, version = pad:getDeviceInfo()
local ax1, ax2, ax3 = pad:getAxes()
local map_hat_type, map_hat_index, map_hat_dir = pad:getGamepadMapping("dpup")
local map_axis_type, map_axis_index = pad:getGamepadMapping("leftx")
local map_button_type, map_button_index = pad:getGamepadMapping("a")
local initial_left, initial_right = pad:getVibration()
local set_ok = pad:setVibration(0.6, 0.2)
local vibrating_left, vibrating_right = pad:getVibration()
local stop_ok = pad:setVibration()
local stopped_left, stopped_right = pad:getVibration()

testbed.count = love.joystick.getJoystickCount()
testbed.type = pad:type()
testbed.type_of_object = pad:typeOf("Object")
testbed.id = id
testbed.instanceid = instanceid
testbed.name = pad:getName()
testbed.guid = pad:getGUID()
testbed.vendor = vendor
testbed.product = product
testbed.version = version
testbed.axis1 = ax1
testbed.axis2 = ax2
testbed.axis3 = ax3
testbed.axis2_direct = pad:getAxis(2)
testbed.axis_count = pad:getAxisCount()
testbed.button_count = pad:getButtonCount()
testbed.hat1 = pad:getHat(1)
testbed.hat2 = pad:getHat(2)
testbed.hat_count = pad:getHatCount()
testbed.button_down = pad:isDown(1, 2)
testbed.button_table_down = pad:isDown({1, 4})
testbed.gamepad = pad:isGamepad()
testbed.gamepad_a = pad:isGamepadDown("a")
testbed.gamepad_any = pad:isGamepadDown({"start", "a"})
testbed.leftx = pad:getGamepadAxis("leftx")
testbed.triggerleft = pad:getGamepadAxis("triggerleft")
testbed.map_hat_type = map_hat_type
testbed.map_hat_index = map_hat_index
testbed.map_hat_dir = map_hat_dir
testbed.map_axis_type = map_axis_type
testbed.map_axis_index = map_axis_index
testbed.map_button_type = map_button_type
testbed.map_button_index = map_button_index
testbed.module_mapping = love.joystick.getGamepadMappingString(pad:getGUID())
testbed.object_mapping = pad:getGamepadMappingString()
testbed.vibration_supported = pad:isVibrationSupported()
testbed.initial_left = initial_left
testbed.initial_right = initial_right
testbed.set_ok = set_ok
testbed.vibrating_left = vibrating_left
testbed.vibrating_right = vibrating_right
testbed.stop_ok = stop_ok
testbed.stopped_left = stopped_left
testbed.stopped_right = stopped_right
testbed.global_axis = GamepadAxis.leftx
testbed.module_button = love.joystick.GamepadButton.a
testbed.global_hat = JoystickHat.ru
testbed.global_input_type = JoystickInputType.hat
''');

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['count'], 1);
      expect(snapshot['type'], 'Joystick');
      expect(snapshot['type_of_object'], isTrue);
      expect(snapshot['id'], 7);
      expect(snapshot['instanceid'], 42);
      expect(snapshot['name'], 'Pad 1');
      expect(snapshot['guid'], _testGuid);
      expect(snapshot['vendor'], 1118);
      expect(snapshot['product'], 654);
      expect(snapshot['version'], 2);
      expect(snapshot['axis1'], 0.25);
      expect(snapshot['axis2'], -0.5);
      expect(snapshot['axis3'], 1.0);
      expect(snapshot['axis2_direct'], -0.5);
      expect(snapshot['axis_count'], 3);
      expect(snapshot['button_count'], 4);
      expect(snapshot['hat1'], 'ru');
      expect(snapshot['hat2'], 'c');
      expect(snapshot['hat_count'], 2);
      expect(snapshot['button_down'], isTrue);
      expect(snapshot['button_table_down'], isTrue);
      expect(snapshot['gamepad'], isTrue);
      expect(snapshot['gamepad_a'], isTrue);
      expect(snapshot['gamepad_any'], isTrue);
      expect(snapshot['leftx'], 0.5);
      expect(snapshot['triggerleft'], 1.0);
      expect(snapshot['map_hat_type'], 'hat');
      expect(snapshot['map_hat_index'], 1);
      expect(snapshot['map_hat_dir'], 'u');
      expect(snapshot['map_axis_type'], 'axis');
      expect(snapshot['map_axis_index'], 1);
      expect(snapshot['map_button_type'], 'button');
      expect(snapshot['map_button_index'], 2);
      expect(snapshot['module_mapping'], contains('leftx:a0'));
      expect(snapshot['module_mapping'], contains('a:b1'));
      expect(snapshot['module_mapping'], contains('dpup:h0.1'));
      expect(snapshot['object_mapping'], snapshot['module_mapping']);
      expect(snapshot['vibration_supported'], isTrue);
      expect(snapshot['initial_left'], 0.0);
      expect(snapshot['initial_right'], 0.0);
      expect(snapshot['set_ok'], isTrue);
      expect(snapshot['vibrating_left'], 0.6);
      expect(snapshot['vibrating_right'], 0.2);
      expect(snapshot['stop_ok'], isTrue);
      expect(snapshot['stopped_left'], 0.0);
      expect(snapshot['stopped_right'], 0.0);
      expect(snapshot['global_axis'], 'leftx');
      expect(snapshot['module_button'], 'a');
      expect(snapshot['global_hat'], 'ru');
      expect(snapshot['global_input_type'], 'hat');
    });

    test('saves and reloads gamepad mappings from strings and files', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'love2d_joystick_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final adapter = _TempFilesystemAdapter(tempDir.path);
      final initialManager = LoveJoystickManager();
      initialManager.addDevice(
        LoveJoystickDevice(
          id: 1,
          name: 'Pad 1',
          guid: _testGuid,
          gamepad: false,
        ),
      );

      final runtime = LoveScriptRuntime(
        host: LoveHeadlessHost(joysticks: initialManager),
        filesystemAdapter: adapter,
      );

      await runtime.execute('''
testbed = {}

love.filesystem.setIdentity("gamepad-tests")
testbed.ok_axis = love.joystick.setGamepadMapping(
  "$_testGuid",
  "leftx",
  "axis",
  1
)
testbed.ok_button = love.joystick.setGamepadMapping(
  "$_testGuid",
  "a",
  "button",
  2
)
testbed.ok_hat = love.joystick.setGamepadMapping(
  "$_testGuid",
  "dpup",
  "hat",
  1,
  "u"
)
testbed.saved = love.joystick.saveGamepadMappings("gamecontrollerdb.txt")
testbed.readback = love.filesystem.read("gamecontrollerdb.txt")
''');

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      final saved = snapshot['saved'] as String;
      expect(snapshot['ok_axis'], isTrue);
      expect(snapshot['ok_button'], isTrue);
      expect(snapshot['ok_hat'], isTrue);
      expect(saved, contains('leftx:a0'));
      expect(saved, contains('a:b1'));
      expect(saved, contains('dpup:h0.1'));
      expect(snapshot['readback'], saved);

      final stringManager = LoveJoystickManager();
      stringManager.addDevice(
        LoveJoystickDevice(
          id: 2,
          name: 'Pad 2',
          guid: _testGuid,
          gamepad: false,
        ),
      );
      final stringRuntime = LoveScriptRuntime(
        host: LoveHeadlessHost(joysticks: stringManager),
        filesystemAdapter: adapter,
      );
      stringRuntime.runtime.globals.define('savedMappings', saved);

      await stringRuntime.execute('''
testbed = {}

love.filesystem.setIdentity("gamepad-tests")
love.joystick.loadGamepadMappings(savedMappings)

local pad = love.joystick.getJoysticks()[1]
local axis_type, axis_index = pad:getGamepadMapping("leftx")
local button_type, button_index = pad:getGamepadMapping("a")
local hat_type, hat_index, hat_dir = pad:getGamepadMapping("dpup")

testbed.gamepad = pad:isGamepad()
testbed.axis_type = axis_type
testbed.axis_index = axis_index
testbed.button_type = button_type
testbed.button_index = button_index
testbed.hat_type = hat_type
testbed.hat_index = hat_index
testbed.hat_dir = hat_dir
testbed.mapping = love.joystick.getGamepadMappingString("$_testGuid")
''');

      final stringSnapshot = stringRuntime.unwrapGlobalTable('testbed')!;
      expect(stringSnapshot['gamepad'], isTrue);
      expect(stringSnapshot['axis_type'], 'axis');
      expect(stringSnapshot['axis_index'], 1);
      expect(stringSnapshot['button_type'], 'button');
      expect(stringSnapshot['button_index'], 2);
      expect(stringSnapshot['hat_type'], 'hat');
      expect(stringSnapshot['hat_index'], 1);
      expect(stringSnapshot['hat_dir'], 'u');
      expect(stringSnapshot['mapping'], contains('leftx:a0'));

      final fileManager = LoveJoystickManager();
      fileManager.addDevice(
        LoveJoystickDevice(
          id: 3,
          name: 'Pad 3',
          guid: _testGuid,
          gamepad: false,
        ),
      );
      final fileRuntime = LoveScriptRuntime(
        host: LoveHeadlessHost(joysticks: fileManager),
        filesystemAdapter: adapter,
      );

      await fileRuntime.execute('''
testbed = {}

love.filesystem.setIdentity("gamepad-tests")
love.joystick.loadGamepadMappings("gamecontrollerdb.txt")

local pad = love.joystick.getJoysticks()[1]
local hat_type, hat_index, hat_dir = pad:getGamepadMapping("dpup")

testbed.gamepad = pad:isGamepad()
testbed.mapping = pad:getGamepadMappingString()
testbed.hat = hat_type .. ":" .. hat_index .. ":" .. hat_dir
''');

      final fileSnapshot = fileRuntime.unwrapGlobalTable('testbed')!;
      expect(fileSnapshot['gamepad'], isTrue);
      expect(fileSnapshot['mapping'], contains('leftx:a0'));
      expect(fileSnapshot['hat'], 'hat:1:u');
    });

    test('loadGamepadMappings only treats existing files as files', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'love2d_joystick_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final runtime = LoveScriptRuntime(
        filesystemAdapter: _TempFilesystemAdapter(tempDir.path),
      );

      await runtime.execute('''
testbed = {}

love.filesystem.setIdentity("gamepad-tests")
love.filesystem.createDirectory("controllers")

local ok_missing, err_missing = pcall(function()
  love.joystick.loadGamepadMappings("missing/gamecontrollerdb.txt")
end)
local ok_directory, err_directory = pcall(function()
  love.joystick.loadGamepadMappings("controllers")
end)

testbed.ok_missing = ok_missing
testbed.err_missing = tostring(err_missing)
testbed.ok_directory = ok_directory
testbed.err_directory = tostring(err_directory)
''');

      final snapshot = runtime.unwrapGlobalTable('testbed')!;
      expect(snapshot['ok_missing'], isFalse);
      expect(snapshot['err_missing'], contains('Invalid gamepad mappings.'));
      expect(snapshot['err_missing'], isNot(contains('Could not open file')));
      expect(snapshot['ok_directory'], isFalse);
      expect(snapshot['err_directory'], contains('Invalid gamepad mappings.'));
      expect(snapshot['err_directory'], isNot(contains('Could not open file')));
    });

    test(
      'saveGamepadMappings reports filesystem write errors with LOVE write semantics',
      () async {
        final runtime = LoveScriptRuntime();

        await runtime.execute('''
testbed = {}

local ok, err = pcall(function()
  return love.joystick.saveGamepadMappings("gamecontrollerdb.txt")
end)

testbed.ok = ok
testbed.err = tostring(err)
''');

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['ok'], isFalse);
        expect(snapshot['err'], contains('Could not set write directory.'));
        expect(
          snapshot['err'],
          isNot(contains('love.joystick.saveGamepadMappings failed')),
        );
      },
    );

    test(
      'retained wrappers stop reporting live state after disconnect',
      () async {
        final joysticks = LoveJoystickManager();
        final device = LoveJoystickDevice(
          id: 9,
          instanceId: 99,
          guid: _testGuid,
          axes: const <double>[0.75],
          buttonCount: 1,
          buttonsDown: const <int>{1},
          gamepadButtons: const <String>{'a'},
        );
        joysticks.addDevice(device);

        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(joysticks: joysticks),
        );

        await runtime.execute('pad = love.joystick.getJoysticks()[1]');
        device.connected = false;

        await runtime.execute('''
testbed = {}

local id, instanceid = pad:getID()
testbed.id = id
testbed.instance_missing = instanceid == nil
testbed.connected = pad:isConnected()
testbed.axis = pad:getAxis(1)
testbed.down = pad:isDown(1)
testbed.gamepad_down = pad:isGamepadDown("a")
testbed.count = love.joystick.getJoystickCount()
''');

        final snapshot = runtime.unwrapGlobalTable('testbed')!;
        expect(snapshot['id'], 9);
        expect(snapshot['instance_missing'], isTrue);
        expect(snapshot['connected'], isFalse);
        expect(snapshot['axis'], 0.0);
        expect(snapshot['down'], isFalse);
        expect(snapshot['gamepad_down'], isFalse);
        expect(snapshot['count'], 0);
      },
    );
  });
}

class _TempFilesystemAdapter extends LoveLualikeFilesystemAdapter {
  _TempFilesystemAdapter(this.rootPath);

  final String rootPath;

  @override
  String? get workingDirectory => rootPath;

  @override
  String? get userDirectory => rootPath;

  @override
  String? get appdataDirectory => rootPath;

  @override
  String? get executablePath => '$rootPath/lualike-test';
}
