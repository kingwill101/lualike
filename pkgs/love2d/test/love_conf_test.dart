import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';
import 'package:path/path.dart' as path;

void main() {
  group('love.conf bootstrap', () {
    late Directory tempRoot;
    late LoveHeadlessHost host;
    late LoveScriptRuntime runtime;
    late LoveFilesystemState filesystem;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('love-conf-');
      host = LoveHeadlessHost(
        windowMetrics: const LoveWindowMetrics(
          width: 640,
          height: 360,
          title: 'Default Title',
        ),
      );
      runtime = LoveScriptRuntime(
        host: host,
        filesystemAdapter: _SandboxFilesystemAdapter(tempRoot.path),
      );
      filesystem = LoveFilesystemState.of(runtime.runtime);
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('returns false when conf.lua is missing', () async {
      final mainPath = path.join(tempRoot.path, 'main.lua');
      await File(mainPath).writeAsString('function love.load() end');

      expect(filesystem.setSource(mainPath), isTrue);
      expect(await runtime.loadConfIfPresent(), isFalse);
      expect(host.windowMetrics.title, 'Default Title');
      expect(filesystem.identity, isEmpty);
    });

    test('applies love.conf state before love.load runs', () async {
      final mainPath = path.join(tempRoot.path, 'main.lua');
      final confPath = path.join(tempRoot.path, 'conf.lua');

      await File(confPath).writeAsString('''
function love.conf(t)
  marker = "called"
  t.identity = "love_conf_identity"
  t.appendidentity = true
  t.audio.mixwithsystem = true
  t.window.title = "Configured Title"
  t.window.width = 1024
  t.window.height = 576
  t.window.x = 48
  t.window.y = 72
  t.window.fullscreen = true
  t.window.fullscreentype = "exclusive"
  t.window.vsync = 0
  t.window.msaa = 4
  t.window.resizable = true
  t.window.borderless = true
  t.window.centered = false
  t.window.display = 2
  t.window.minwidth = 320
  t.window.minheight = 180
  t.window.highdpi = true
  t.window.refreshrate = 144
  t.modules.joystick = false
  t.modules.physics = false
end
''');
      await File(mainPath).writeAsString('''
snapshot = {}

function love.load()
  local width, height, flags = love.window.getMode()
  snapshot.title = love.window.getTitle()
  snapshot.width = width
  snapshot.height = height
  snapshot.vsync = flags.vsync
  snapshot.msaa = flags.msaa
  snapshot.resizable = flags.resizable
  snapshot.borderless = flags.borderless
  snapshot.centered = flags.centered
  snapshot.fullscreen = flags.fullscreen
  snapshot.fullscreentype = flags.fullscreentype
  snapshot.display = flags.display
  snapshot.minwidth = flags.minwidth
  snapshot.minheight = flags.minheight
  snapshot.highdpi = flags.highdpi
  snapshot.refreshrate = flags.refreshrate
  snapshot.joystick_missing = love.joystick == nil
  snapshot.physics_missing = love.physics == nil
  snapshot.graphics_present = love.graphics ~= nil
end
''');

      expect(filesystem.setSource(mainPath), isTrue);
      expect(await runtime.loadConfIfPresent(), isTrue);

      await runtime.execute(
        await File(mainPath).readAsString(),
        scriptPath: 'main.lua',
      );
      await runtime.callLoadIfDefined();

      final snapshot = runtime.unwrapGlobalTable('snapshot');
      expect(snapshot, isNotNull);
      expect(snapshot, containsPair('title', 'Configured Title'));
      expect(snapshot, containsPair('width', 1024));
      expect(snapshot, containsPair('height', 576));
      expect(snapshot, containsPair('vsync', 0));
      expect(snapshot, containsPair('msaa', 4));
      expect(snapshot, containsPair('resizable', isTrue));
      expect(snapshot, containsPair('borderless', isTrue));
      expect(snapshot, containsPair('centered', isFalse));
      expect(snapshot, containsPair('fullscreen', isTrue));
      expect(snapshot, containsPair('fullscreentype', 'exclusive'));
      expect(snapshot, containsPair('display', 2));
      expect(snapshot, containsPair('minwidth', 320));
      expect(snapshot, containsPair('minheight', 180));
      expect(snapshot, containsPair('highdpi', isTrue));
      expect(snapshot, containsPair('refreshrate', 144));
      expect(snapshot, containsPair('joystick_missing', isTrue));
      expect(snapshot, containsPair('physics_missing', isTrue));
      expect(snapshot, containsPair('graphics_present', isTrue));

      expect(host.windowMetrics.title, 'Configured Title');
      expect(host.windowMetrics.width, 1024);
      expect(host.windowMetrics.height, 576);
      expect(host.windowMetrics.x, 48);
      expect(host.windowMetrics.y, 72);
      expect(host.windowMetrics.fullscreen, isTrue);
      expect(host.windowMetrics.fullscreenType, 'exclusive');
      expect(host.windowMetrics.vsync, 0);
      expect(host.windowMetrics.msaa, 4);
      expect(host.windowMetrics.resizable, isTrue);
      expect(host.windowMetrics.borderless, isTrue);
      expect(host.windowMetrics.centered, isFalse);
      expect(host.windowMetrics.display, 2);
      expect(host.windowMetrics.minWidth, 320);
      expect(host.windowMetrics.minHeight, 180);
      expect(host.windowMetrics.highDpi, isTrue);
      expect(host.windowMetrics.refreshRate, 144);
      expect(runtime.context.audio.mixWithSystem, isTrue);

      expect(filesystem.identity, 'love_conf_identity');
      expect(
        filesystem.getSaveDirectory(),
        path.join(tempRoot.path, 'appdata', 'love', 'love_conf_identity'),
      );
    });
  });
}

class _SandboxFilesystemAdapter extends LoveLualikeFilesystemAdapter {
  _SandboxFilesystemAdapter(this.root);

  final String root;

  @override
  String? get workingDirectory => root;

  @override
  String? get userDirectory => path.join(root, 'user');

  @override
  String? get appdataDirectory => path.join(root, 'appdata');

  @override
  String? get executablePath => path.join(root, 'bin', 'love2d_test');

  @override
  bool get isWindows => false;

  @override
  bool get isLinux => true;

  @override
  bool get isMacOS => false;
}
