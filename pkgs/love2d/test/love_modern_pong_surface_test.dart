import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:lualike/src/io/io_device.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

void main() {
  group('Modern-Pong surface', () {
    test('shader send and setShader snapshot into draw commands', () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
local shader = love.graphics.newShader([[
  extern number innerRadius;
  extern number outerRadius;
  extern vec2 center;
  extern vec4 colorInner;
  extern vec4 colorOuter;
  vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    number dist = distance(screen_coords, center);
    number t = smoothstep(innerRadius, outerRadius, dist);
    return mix(colorInner, colorOuter, t) * Texel(texture, texture_coords);
  }
]])

function love.draw()
  shader:send("innerRadius", 20)
  shader:send("outerRadius", 200)
  shader:send("center", {100, 60})
  shader:send("colorInner", {1, 0, 0, 1})
  shader:send("colorOuter", {0, 0, 0, 1})
  love.graphics.setShader(shader)
  love.graphics.rectangle("fill", 0, 0, 320, 180)
  love.graphics.setShader()
end
''');

      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();

      final command =
          runtime.context.graphics.commands.single as LoveRectangleCommand;
      expect(command.shader, isNotNull);
      expect(command.shader!.kind, LoveShaderKind.radialGradient);
      expect(command.shader!.uniform('innerRadius'), 20);
      expect(command.shader!.uniform('center'), <Object?>[100, 60]);
      expect(runtime.context.graphics.shaderSwitches, 2);
    });

    test(
      'newShader reads string resources through LOVE filesystem first',
      () async {
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(),
          filesystemAdapter: _MemoryFilesystemAdapter(
            files: <String, List<int>>{
              'game/shaders/radial.glsl':
                  '''
extern number innerRadius;
extern number outerRadius;
extern vec2 center;
extern vec4 colorInner;
extern vec4 colorOuter;
vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  number dist = distance(screen_coords, center);
  number t = smoothstep(innerRadius, outerRadius, dist);
  return mix(colorInner, colorOuter, t) * Texel(texture, texture_coords);
}
'''
                      .codeUnits,
            },
          ),
        );
        final filesystem = LoveFilesystemState.attach(runtime.runtime);
        expect(filesystem.setSource('game'), isTrue);

        await runtime.execute('''
function love.draw()
  local shader = love.graphics.newShader("shaders/radial.glsl")
  shader:send("innerRadius", 12)
  love.graphics.setShader(shader)
  love.graphics.rectangle("fill", 0, 0, 64, 64)
end
''');

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final command =
            runtime.context.graphics.commands.single as LoveRectangleCommand;
        expect(command.shader, isNotNull);
        expect(command.shader!.kind, LoveShaderKind.radialGradient);
        expect(command.shader!.uniform('innerRadius'), 12);
      },
    );

    test('newShader rejects missing path-like string sources', () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute(r'''
local ok, err = pcall(function()
  return love.graphics.newShader("shaders/missing.glsl")
end)

shader_ok = ok
shader_error = tostring(err)
''');

      expect(runtime.unwrapGlobal('shader_ok'), isFalse);
      expect(
        runtime.unwrapGlobal('shader_error'),
        contains('Could not open file shaders/missing.glsl. Does not exist.'),
      );
    });

    test('newMesh, setVertices, and draw(mesh) record mesh commands', () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
function love.draw()
  local mesh = love.graphics.newMesh({
    {10, 20, 0, 0, 1, 0, 0, 1},
    {30, 20, 0, 0, 1, 0.5, 0.5, 1},
    {30, 70, 0, 0, 1, 0.2, 0.2, 1},
    {10, 70, 0, 0, 0.8, 0, 0, 1},
  }, "fan", "static")
  mesh:setVertices({
    {12, 24, 0, 0, 1, 0, 0, 1},
    {28, 24, 0, 0, 1, 0.5, 0.5, 1},
    {28, 72, 0, 0, 1, 0.2, 0.2, 1},
    {12, 72, 0, 0, 0.8, 0, 0, 1},
  })
  love.graphics.draw(mesh)
end
''');

      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();

      final command =
          runtime.context.graphics.commands.single as LoveMeshCommand;
      expect(command.mesh.drawMode, LoveMeshDrawMode.fan);
      expect(command.mesh.usage, LoveMeshUsage.staticUsage);
      expect(command.mesh.vertices.first.x, 12);
      expect(command.mesh.vertices.last.y, 72);
    });

    test(
      'newSource reads filesystem bytes and updates backend state',
      () async {
        final backend = _FakeAudioBackend();
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(
            audioBackendFactory:
                (
                  String source, {
                  required String sourceType,
                  Uint8List? bytes,
                  String? mimeType,
                }) async {
                  backend.loadedSource = source;
                  backend.loadedType = sourceType;
                  backend.loadedBytes = bytes;
                  backend.loadedMimeType = mimeType;
                  return backend;
                },
          ),
          filesystemAdapter: _MemoryFilesystemAdapter(
            files: <String, List<int>>{'game/theme.mp3': 'mp3-data'.codeUnits},
          ),
        );
        final filesystem = LoveFilesystemState.attach(runtime.runtime);
        expect(filesystem.setSource('game'), isTrue);

        await runtime.execute('''
function love.load()
  local source = love.audio.newSource("theme.mp3", "static")
  source:setLooping(true)
  played = source:play()
end
''');

        await runtime.callLoadIfDefined();

        expect(backend.loadedSource, 'theme.mp3');
        expect(backend.loadedType, 'static');
        expect(backend.loadedBytes, Uint8List.fromList('mp3-data'.codeUnits));
        expect(backend.loadedMimeType, 'audio/mpeg');
        expect(backend.looping, isTrue);
        expect(backend.playCalls, 1);
        expect(runtime.unwrapGlobal('played'), isTrue);
      },
    );

    test(
      'getJoysticks returns wrappers and isGamepadDown checks buttons',
      () async {
        final joystick = LoveJoystickDevice(
          id: 1,
          gamepadButtons: <String>{'dpup'},
        );
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(
            joysticks: LoveJoystickManager(
              devices: <LoveJoystickDevice>[joystick],
            ),
          ),
        );

        final joysticks = await _call(runtime, const [
          'love',
          'joystick',
          'getJoysticks',
        ]);
        expect(joysticks, isA<Map>());
        final first = (joysticks! as Map)[1];
        expect(first, isA<Map>());

        final result = await _callMethod(
          runtime,
          first,
          'isGamepadDown',
          const <Object?>['dpup'],
        );
        expect(result, isTrue);
      },
    );

    test(
      'newImage reads string resources through LOVE filesystem first',
      () async {
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(),
          filesystemAdapter: _MemoryFilesystemAdapter(
            files: <String, List<int>>{
              'game/sprite.png': LoveImageData.fromRgbaBytes(
                width: 1,
                height: 1,
                bytes: Uint8List.fromList(const <int>[255, 0, 0, 255]),
              ).encode('png'),
            },
          ),
        );
        final filesystem = LoveFilesystemState.attach(runtime.runtime);
        expect(filesystem.setSource('game'), isTrue);

        await runtime.execute('''
function love.load()
  sprite = love.graphics.newImage("sprite.png")
end
''');
        await runtime.callLoadIfDefined();

        final wrapped = runtime.unwrapGlobal('sprite');
        expect(wrapped, isA<Map>());
        final image = (wrapped! as Map)['__love2d_image__'];
        expect(image, isA<LoveImage>());
        expect((image! as LoveImage).width, 1);
        expect(image.height, 1);
      },
    );

    test(
      'newImage and newImageFont accept filesystem File and FileData inputs',
      () async {
        final spriteBytes = LoveImageData(width: 12, height: 6).encode('png');
        final fontBytes = LoveImageData.fromRgbaBytes(
          width: 9,
          height: 6,
          bytes: _imageFontStripBytes(),
        ).encode('png');
        final runtime = LoveScriptRuntime(
          host: LoveHeadlessHost(),
          filesystemAdapter: _MemoryFilesystemAdapter(
            files: <String, List<int>>{
              'game/sprite.png': spriteBytes,
              'game/font.png': fontBytes,
            },
          ),
        );
        final filesystem = LoveFilesystemState.attach(runtime.runtime);
        expect(filesystem.setSource('game'), isTrue);

        await runtime.execute('''
function love.load()
  local sprite_file = love.filesystem.newFile("sprite.png")
  local font_data = love.filesystem.newFileData("font.png")
  sprite = love.graphics.newImage(sprite_file)
  font = love.graphics.newImageFont(font_data, "ABC", 1)
  image_dimensions = string.format("%dx%d", sprite:getWidth(), sprite:getHeight())
  font_width = font:getWidth("AB")
end
''');
        await runtime.callLoadIfDefined();

        expect(runtime.unwrapGlobal('image_dimensions'), '12x6');
        expect(runtime.unwrapGlobal('font_width'), 5.0);
      },
    );

    test(
      'vendored Modern-Pong main menu loads and draws with real assets',
      () async {
        final backendFactory = _RecordingAudioBackendFactory();
        final runtime = await _createModernPongRuntime(
          backendFactory: backendFactory,
        );
        await _loadModernPong(runtime);

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        expect(backendFactory.loadedSources, contains('sounds/theme.mp3'));
        expect(backendFactory.playCalls, greaterThanOrEqualTo(1));

        final commands = runtime.context.graphics.commands;
        expect(commands, isNotEmpty);
        expect(
          commands.any((command) => command is LoveRectangleCommand),
          isTrue,
        );
        expect(commands.any((command) => command is LoveImageCommand), isTrue);

        final background =
            commands.firstWhere((command) => command is LoveRectangleCommand)
                as LoveRectangleCommand;
        expect(background.shader, isNotNull);
        expect(background.shader!.kind, LoveShaderKind.radialGradient);
      },
    );

    test(
      'vendored Modern-Pong main menu click transitions into inGame',
      () async {
        final backendFactory = _RecordingAudioBackendFactory();
        final runtime = await _createModernPongRuntime(
          backendFactory: backendFactory,
        );
        await _loadModernPong(runtime);

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final playButtonCenter = _modernPongPlayButtonCenter(runtime);
        runtime.context.mouse.setPosition(
          playButtonCenter.$1,
          playButtonCenter.$2,
        );

        await runtime.callUpdateIfDefined(0.6);
        runtime.context.mouse.setButtonDown(1, down: true);
        await runtime.callUpdateIfDefined(1 / 60);
        runtime.context.mouse.setButtonDown(1, down: false);

        expect(await _currentStateIs(runtime, 'states/inGame'), isTrue);
        expect(
          backendFactory.loadedSources,
          containsAll(<String>[
            'sounds/theme.mp3',
            'sounds/wall.mp3',
            'sounds/paddle.mp3',
            'sounds/score.mp3',
          ]),
        );

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final commands = runtime.context.graphics.commands;
        expect(commands.any((command) => command is LoveMeshCommand), isTrue);
        expect(commands.any((command) => command is LoveCircleCommand), isTrue);
      },
    );

    test('vendored Modern-Pong exit button pushes a quit event', () async {
      final runtime = await _createModernPongRuntime();
      await _loadModernPong(runtime);

      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();

      final exitButtonCenter = _modernPongMenuButtonCenter(runtime, index: 2);
      runtime.context.mouse.setPosition(
        exitButtonCenter.$1,
        exitButtonCenter.$2,
      );

      await runtime.callUpdateIfDefined(0.6);
      runtime.context.mouse.setButtonDown(1, down: true);
      await runtime.callUpdateIfDefined(1 / 60);
      runtime.context.mouse.setButtonDown(1, down: false);

      final quitEvent = runtime.context.events.poll();
      expect(quitEvent, isNotNull);
      expect(quitEvent!.toValues(), <Object?>['quit', 0]);
    });

    test(
      'vendored Modern-Pong inGame state loads meshes and draws geometry',
      () async {
        final backendFactory = _RecordingAudioBackendFactory();
        final runtime = await _createModernPongRuntime(
          backendFactory: backendFactory,
          joysticks: LoveJoystickManager(
            devices: <LoveJoystickDevice>[
              LoveJoystickDevice(id: 1, gamepadButtons: const <String>{'dpup'}),
            ],
          ),
        );
        await _loadModernPong(runtime);
        await runtime.execute(
          'GameStateManager:setState(require("states/inGame"))',
          scriptPath: 'switch_to_ingame.lua',
        );

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        expect(
          backendFactory.loadedSources,
          containsAll(<String>[
            'sounds/theme.mp3',
            'sounds/wall.mp3',
            'sounds/paddle.mp3',
            'sounds/score.mp3',
          ]),
        );

        final commands = runtime.context.graphics.commands;
        expect(commands, isNotEmpty);
        expect(commands.any((command) => command is LoveMeshCommand), isTrue);
        expect(commands.any((command) => command is LoveCircleCommand), isTrue);
        expect(
          commands.any((command) => command is LoveRectangleCommand),
          isTrue,
        );

        final mesh =
            commands.firstWhere((command) => command is LoveMeshCommand)
                as LoveMeshCommand;
        expect(mesh.mesh.vertices, hasLength(4));
        expect(mesh.mesh.drawMode, LoveMeshDrawMode.fan);
        expect(mesh.mesh.vertices.first.color.r, closeTo(1, 1e-9));
        expect(mesh.mesh.vertices.first.color.g, closeTo(0, 1e-9));
        expect(mesh.mesh.vertices.first.color.b, closeTo(0, 1e-9));
        expect(mesh.mesh.vertices.first.color.a, closeTo(1, 1e-9));
        expect(mesh.mesh.vertices[2].color.r, closeTo(1, 1e-9));
        expect(mesh.mesh.vertices[2].color.g, closeTo(0.2, 1e-9));
        expect(mesh.mesh.vertices[2].color.b, closeTo(0.2, 1e-9));
        expect(mesh.mesh.vertices[2].color.a, closeTo(1, 1e-9));
        expect(mesh.shader, isNull);
      },
    );

    test(
      'vendored Modern-Pong inGame keyboard input moves player paddle mesh',
      () async {
        final runtime = await _createModernPongRuntime();
        await _loadModernPong(runtime);
        await runtime.execute(
          'GameStateManager:setState(require("states/inGame"))',
          scriptPath: 'switch_to_ingame.lua',
        );

        runtime.context.keyboard.setKeyDown('w', down: true);
        await runtime.callUpdateIfDefined(0.1);
        runtime.context.keyboard.setKeyDown('w', down: false);

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final playerOneMesh = runtime.context.graphics.commands
            .whereType<LoveMeshCommand>()
            .first;
        expect(playerOneMesh.mesh.vertices.first.y, closeTo(245, 0.001));
        expect(playerOneMesh.mesh.vertices.last.y, closeTo(315, 0.001));
      },
    );

    test(
      'vendored Modern-Pong escape pauses gameplay and draws the overlay',
      () async {
        final runtime = await _createModernPongRuntime();
        await _loadModernPong(runtime);
        await runtime.execute(
          'GameStateManager:setState(require("states/inGame"))',
          scriptPath: 'switch_to_ingame.lua',
        );

        await runtime.callKeyPressedIfDefined('escape', scancode: 'escape');
        runtime.context.keyboard.setKeyDown('w', down: true);
        await runtime.callUpdateIfDefined(0.1);
        runtime.context.keyboard.setKeyDown('w', down: false);

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final textCommands = runtime.context.graphics.commands
            .whereType<LoveTextCommand>()
            .toList(growable: false);
        expect(
          textCommands.any(
            (command) =>
                command.text == "Game Paused\nPress 'Escape' to Resume",
          ),
          isTrue,
        );

        final playerOneMesh = runtime.context.graphics.commands
            .whereType<LoveMeshCommand>()
            .first;
        expect(playerOneMesh.mesh.vertices.first.y, closeTo(275, 0.001));
        expect(playerOneMesh.mesh.vertices.last.y, closeTo(345, 0.001));
      },
    );

    test(
      'vendored Modern-Pong inGame joystick input moves player paddle mesh',
      () async {
        final joystick = LoveJoystickDevice(id: 1);
        final runtime = await _createModernPongRuntime(
          joysticks: LoveJoystickManager(
            devices: <LoveJoystickDevice>[joystick],
          ),
        );
        await _loadModernPong(runtime);
        await runtime.execute(
          'GameStateManager:setState(require("states/inGame"))',
          scriptPath: 'switch_to_ingame.lua',
        );

        joystick.setGamepadButton('dpdown', down: true);
        await runtime.callUpdateIfDefined(0.1);
        joystick.setGamepadButton('dpdown', down: false);

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final playerOneMesh = runtime.context.graphics.commands
            .whereType<LoveMeshCommand>()
            .first;
        expect(playerOneMesh.mesh.vertices.first.y, closeTo(305, 0.001));
        expect(playerOneMesh.mesh.vertices.last.y, closeTo(375, 0.001));
      },
    );

    test(
      'vendored Modern-Pong wall collision plays wall audio and reflects ball',
      () async {
        final backendFactory = _RecordingAudioBackendFactory();
        final runtime = await _createModernPongRuntime(
          backendFactory: backendFactory,
        );
        await _loadModernPong(runtime);
        await _runtimeSwitchToInGame(runtime);
        await _exposeModernPongInGameState(runtime);

        await runtime.execute('''
gameBallRef.x = love.graphics.getWidth() / 2
gameBallRef.y = 1
gameBallRef.dx = 0
gameBallRef.dy = -120
''', scriptPath: 'position_wall_collision.lua');

        final initialWallPlayCount = backendFactory.playCountFor(
          'sounds/wall.mp3',
        );

        await runtime.callUpdateIfDefined(0.1);
        await runtime.execute(
          'wall_collision_dy = gameBallRef.dy',
          scriptPath: 'capture_wall_collision.lua',
        );

        expect(
          backendFactory.playCountFor('sounds/wall.mp3'),
          initialWallPlayCount + 1,
        );
        expect(runtime.unwrapGlobal('wall_collision_dy'), greaterThan(0));
      },
    );

    test(
      'vendored Modern-Pong paddle collision plays paddle audio and reverses ball',
      () async {
        final backendFactory = _RecordingAudioBackendFactory();
        final runtime = await _createModernPongRuntime(
          backendFactory: backendFactory,
        );
        await _loadModernPong(runtime);
        await _runtimeSwitchToInGame(runtime);
        await _exposeModernPongInGameState(runtime);

        await runtime.execute('''
math.random = function(...)
  return 0
end
gameBallRef.x = 60
gameBallRef.y = player1Ref.y + 10
gameBallRef.dx = -120
gameBallRef.dy = 0
''', scriptPath: 'position_paddle_collision.lua');

        final initialPaddlePlayCount = backendFactory.playCountFor(
          'sounds/paddle.mp3',
        );

        await runtime.callUpdateIfDefined(0.05);
        await runtime.execute('''
paddle_collision_dx = gameBallRef.dx
paddle_collision_dy = gameBallRef.dy
''', scriptPath: 'capture_paddle_collision.lua');

        expect(
          backendFactory.playCountFor('sounds/paddle.mp3'),
          initialPaddlePlayCount + 1,
        );
        expect(runtime.unwrapGlobal('paddle_collision_dx'), greaterThan(0));
        expect(runtime.unwrapGlobal('paddle_collision_dy'), 0);
      },
    );

    test(
      'vendored Modern-Pong scoring plays score audio and updates score text',
      () async {
        final backendFactory = _RecordingAudioBackendFactory();
        final runtime = await _createModernPongRuntime(
          backendFactory: backendFactory,
        );
        await _loadModernPong(runtime);
        await _runtimeSwitchToInGame(runtime);

        final initialScorePlayCount = backendFactory.playCountFor(
          'sounds/score.mp3',
        );

        await runtime.callUpdateIfDefined(2.0);

        expect(
          backendFactory.playCountFor('sounds/score.mp3'),
          initialScorePlayCount + 1,
        );

        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        final textCommands = runtime.context.graphics.commands
            .whereType<LoveTextCommand>()
            .map((command) => command.text)
            .toList(growable: false);
        expect(textCommands, contains('1'));
        expect(textCommands, contains('0'));
      },
    );
  });
}

final Directory _modernPongRoot = _resolveModernPongRoot();
final String _modernPongMainPath =
    '${_modernPongRoot.path}${Platform.pathSeparator}main.lua';

Directory _resolveModernPongRoot() {
  const candidatePaths = <String>[
    'pkgs/love2d/third_party/Modern-Pong',
    'third_party/Modern-Pong',
  ];

  for (final candidate in candidatePaths) {
    final directory = Directory(candidate);
    if (directory.existsSync()) {
      return directory;
    }
  }

  return Directory(candidatePaths.first);
}

class _FakeAudioBackend implements LoveAudioSourceBackend {
  String? loadedSource;
  String? loadedType;
  Uint8List? loadedBytes;
  String? loadedMimeType;
  bool looping = false;
  int playCalls = 0;
  double volume = 1.0;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {
    playCalls++;
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setLooping(bool looping) async {
    this.looping = looping;
  }

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
  }

  @override
  Future<void> stop() async {}
}

class _RecordingAudioBackendFactory {
  final List<String> loadedSources = <String>[];
  final List<String> loadedTypes = <String>[];
  int playCalls = 0;
  final Map<String, int> _playCounts = <String, int>{};

  Future<LoveAudioSourceBackend> create(
    String source, {
    required String sourceType,
    Uint8List? bytes,
    String? mimeType,
  }) async {
    loadedSources.add(source);
    loadedTypes.add(sourceType);
    return _CountingAudioBackend(
      onPlay: () {
        playCalls++;
        _playCounts.update(source, (count) => count + 1, ifAbsent: () => 1);
      },
    );
  }

  int playCountFor(String source) {
    return _playCounts[source] ?? 0;
  }
}

class _CountingAudioBackend implements LoveAudioSourceBackend {
  _CountingAudioBackend({required this.onPlay});

  final void Function() onPlay;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {
    onPlay();
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}
}

class _MemoryFilesystemAdapter implements LoveFilesystemAdapter {
  _MemoryFilesystemAdapter({required this.files});

  final Map<String, List<int>> files;

  @override
  String? get appdataDirectory => null;

  @override
  String? get executablePath => null;

  @override
  bool get isWindows => false;

  @override
  bool get isLinux => true;

  @override
  bool get isMacOS => false;

  @override
  String? get userDirectory => null;

  @override
  String? get workingDirectory => null;

  @override
  Future<bool> createDirectory(String path, {bool recursive = true}) async =>
      true;

  @override
  Future<bool> deletePath(String path, {bool recursive = true}) async => false;

  @override
  Future<bool> directoryExists(String path) async =>
      files.keys.any((key) => key.startsWith('$path/'));

  @override
  Future<bool> fileExists(String path) async => files.containsKey(path);

  @override
  Future<int?> fileSize(String path) async => files[path]?.length;

  @override
  Future<List<String>> listDirectory(String path) async => const <String>[];

  @override
  Future<DateTime?> modified(String path) async => null;

  @override
  Future<IODevice> openFile(String path, String mode) async {
    final bytes = files[path];
    if (mode == 'r' && bytes != null) {
      return _MemoryReadIODevice(bytes);
    }

    throw UnsupportedError('openFile only supports read mode in this test');
  }

  @override
  Future<List<int>?> readFileBytes(String path) async => files[path];
}

class _MemoryReadIODevice extends BaseIODevice {
  _MemoryReadIODevice(List<int> bytes)
    : _bytes = List<int>.unmodifiable(bytes),
      super('r') {
    isClosed = false;
  }

  final List<int> _bytes;
  int _position = 0;

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  Future<void> flush() async {
    checkOpen();
  }

  @override
  Future<ReadResult> read([String format = 'l']) async {
    checkOpen();
    validateReadFormat(format);

    final normalized = normalizeReadFormat(format);
    if (normalized == 'a') {
      final chunk = _bytes.sublist(_position.clamp(0, _bytes.length));
      _position = _bytes.length;
      return ReadResult(LuaString.fromBytes(chunk));
    }

    if (normalized == 'l' || normalized == 'L') {
      if (_position >= _bytes.length) {
        return ReadResult(null);
      }

      var end = _position;
      while (end < _bytes.length && _bytes[end] != 10) {
        end++;
      }

      final includeTerminator = normalized == 'L' && end < _bytes.length;
      final line = _bytes.sublist(_position, includeTerminator ? end + 1 : end);
      _position = end < _bytes.length ? end + 1 : _bytes.length;
      return ReadResult(LuaString.fromBytes(line));
    }

    if (normalized == 'n') {
      return ReadResult(null, 'number reads are not supported in this test');
    }

    final count = int.parse(normalized);
    if (_position >= _bytes.length) {
      return ReadResult(null);
    }

    final end = (_position + count).clamp(0, _bytes.length);
    final chunk = _bytes.sublist(_position, end);
    _position = end;
    return ReadResult(LuaString.fromBytes(chunk));
  }

  @override
  Future<WriteResult> write(String data) async =>
      WriteResult(false, 'File not open for writing');

  @override
  Future<WriteResult> writeBytes(List<int> bytes) async =>
      WriteResult(false, 'File not open for writing');

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    checkOpen();
    switch (whence) {
      case SeekWhence.set:
        _position = offset.clamp(0, _bytes.length);
      case SeekWhence.cur:
        _position = (_position + offset).clamp(0, _bytes.length);
      case SeekWhence.end:
        _position = (_bytes.length + offset).clamp(0, _bytes.length);
    }
    return _position;
  }

  @override
  Future<void> setBuffering(BufferMode mode, [int? size]) async {}

  @override
  Future<int> getPosition() async {
    checkOpen();
    return _position;
  }

  @override
  Future<bool> isEOF() async {
    checkOpen();
    return _position >= _bytes.length;
  }
}

Future<LoveScriptRuntime> _createModernPongRuntime({
  _RecordingAudioBackendFactory? backendFactory,
  LoveJoystickManager? joysticks,
}) async {
  late LoveScriptRuntime runtime;
  runtime = LoveScriptRuntime(
    host: LoveHeadlessHost(
      joysticks: joysticks,
      audioBackendFactory: backendFactory?.create,
      imageLoader: (source, {bytes, settings}) async {
        final resolvedBytes =
            bytes ??
            await LoveFilesystemState.of(runtime.runtime).readAllBytes(source);
        expect(
          resolvedBytes,
          isNotNull,
          reason: 'Missing image asset: $source',
        );
        final data = LoveImageData.decodeEncodedBytes(
          bytes: Uint8List.fromList(resolvedBytes!),
          source: source,
        );
        return LoveImage(
          source: source,
          width: data.width,
          height: data.height,
          imageData: data,
        );
      },
    ),
  );

  final filesystem = LoveFilesystemState.of(runtime.runtime);
  expect(filesystem.setSource(_modernPongRoot.path), isTrue);
  return runtime;
}

Future<void> _loadModernPong(LoveScriptRuntime runtime) async {
  await runtime.loadConfIfPresent();
  await runtime.execute(
    await File(_modernPongMainPath).readAsString(),
    scriptPath: 'main.lua',
  );
  await runtime.callLoadIfDefined();
}

Future<void> _runtimeSwitchToInGame(LoveScriptRuntime runtime) async {
  await runtime.execute(
    'GameStateManager:setState(require("states/inGame"))',
    scriptPath: 'switch_to_ingame.lua',
  );
}

Future<void> _exposeModernPongInGameState(LoveScriptRuntime runtime) async {
  await runtime.execute('''
local state = require("states/inGame")
for i = 1, 32 do
  local name, value = debug.getupvalue(state.update, i)
  if not name then
    break
  end
  if name == "gameBall" then
    gameBallRef = value
  elseif name == "player1" then
    player1Ref = value
  elseif name == "player2" then
    player2Ref = value
  end
end
''', scriptPath: 'expose_ingame_state.lua');
}

Future<bool> _currentStateIs(
  LoveScriptRuntime runtime,
  String modulePath,
) async {
  await runtime.execute(
    'state_is_expected = GameStateManager:getState() == require("$modulePath")',
    scriptPath: 'state_assertion.lua',
  );
  return runtime.unwrapGlobal('state_is_expected') == true;
}

(double, double) _modernPongPlayButtonCenter(LoveScriptRuntime runtime) {
  return _modernPongMenuButtonCenter(runtime, index: 1);
}

(double, double) _modernPongMenuButtonCenter(
  LoveScriptRuntime runtime, {
  required int index,
}) {
  final width = runtime.context.windowMetrics.width;
  final height = runtime.context.windowMetrics.height;
  const buttonHeight = 50.0;
  const buttonSpacing = 15.0;
  final totalHeight = (2 * (buttonHeight + buttonSpacing)) - buttonSpacing;
  final startY = (height - totalHeight) / 2;
  final centerY = startY + ((index - 1) * (buttonHeight + buttonSpacing));
  return (width / 2, centerY + (buttonHeight / 2));
}

Future<Object?> _call(
  Interpreter runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime, path).call(args));
}

Future<Object?> _callMethod(
  Interpreter runtime,
  Object? target,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  final table = target is Value ? target.raw : target;
  expect(table, isA<Map>());
  final callable = (table as Map)[method];
  final raw = switch (callable) {
    final Value value => value.raw,
    final BuiltinFunction function => function,
    _ => callable,
  };
  expect(raw, isA<BuiltinFunction>());
  return _resolveCallResult(
    (raw! as BuiltinFunction).call(<Object?>[target, ...args]),
  );
}

BuiltinFunction _rawFunction(Interpreter runtime, List<String> path) {
  var current = runtime.getCurrentEnv().get(path.first);
  for (final segment in path.skip(1)) {
    final table = current is Value ? current.raw : current;
    expect(table, isA<Map>());
    current = (table as Map)[segment];
  }

  expect(current, isA<Value>());
  final raw = (current! as Value).raw;
  expect(raw, isA<BuiltinFunction>());
  return raw as BuiltinFunction;
}

Future<Object?> _resolveCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return (wrapped.raw as List<Object?>)
        .map((entry) => entry is Value ? entry.unwrap() : entry)
        .toList(growable: false);
  }
  return resolved is Value ? resolved.unwrap() : resolved;
}

Uint8List _imageFontStripBytes() {
  final bytes = Uint8List(9 * 6 * 4);

  void fillColumns(int start, int end, List<int> rgba) {
    for (var row = 0; row < 6; row++) {
      for (var column = start; column < end; column++) {
        final offset = ((row * 9) + column) * 4;
        bytes[offset] = rgba[0];
        bytes[offset + 1] = rgba[1];
        bytes[offset + 2] = rgba[2];
        bytes[offset + 3] = rgba[3];
      }
    }
  }

  fillColumns(1, 3, const <int>[255, 255, 255, 255]);
  fillColumns(4, 5, const <int>[255, 96, 96, 255]);
  fillColumns(6, 9, const <int>[96, 255, 96, 255]);
  return bytes;
}
