import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love core bindings', () {
    late LuaRuntime runtime;
    late LuaLike lualike;

    setUp(() {
      lualike = LuaLike();
      runtime = lualike.vm;
      installLove2d(runtime: runtime);
    });

    test('LoveScriptRuntime records explicit engine mode', () {
      final scriptRuntime = LoveScriptRuntime(
        engineMode: EngineMode.luaBytecode,
      );

      expect(scriptRuntime.lua.engineMode, EngineMode.luaBytecode);
      expect(
        LoveRuntimeContext.of(scriptRuntime.runtime).engineMode,
        EngineMode.luaBytecode,
      );
    });

    test('LOVE runtimes disable automatic GC by default', () async {
      final scriptRuntime = LoveScriptRuntime(runtime: runtime);

      expect(runtime.gc.isStopped, isTrue);
      expect(runtime.gc.autoTriggerEnabled, isFalse);
      expect(LoveRuntimeContext.of(runtime).automaticGc, isFalse);

      await scriptRuntime.execute('gcRunning = collectgarbage("isrunning")');

      expect(scriptRuntime.unwrapGlobal('gcRunning'), isFalse);
    });

    test('LOVE runtimes can opt back into automatic GC', () async {
      final scriptRuntime = LoveScriptRuntime(
        automaticGc: true,
        host: LoveHeadlessHost(),
      );

      expect(scriptRuntime.runtime.gc.isStopped, isFalse);
      expect(scriptRuntime.runtime.gc.autoTriggerEnabled, isTrue);
      expect(scriptRuntime.context.automaticGc, isTrue);

      await scriptRuntime.execute('gcRunning = collectgarbage("isrunning")');

      expect(scriptRuntime.unwrapGlobal('gcRunning'), isTrue);
    });

    test('bytecode runtime dispatches LOVE table callbacks', () async {
      final scriptRuntime = LoveScriptRuntime(
        engineMode: EngineMode.luaBytecode,
        host: LoveHeadlessHost(),
      );

      await scriptRuntime.execute('''
function love.resize(width, height)
  if width == 640 and height == 360 then
    love.event.quit()
  end
end
''');
      expect(scriptRuntime.userLoveCallback('resize'), isNotNull);

      await scriptRuntime.callResizeIfDefined(640, 360);
      final event = scriptRuntime.context.events.poll();

      expect(event?.name, 'quit');
    });

    test('bytecode runtime preserves nil-returning LOVE getters', () async {
      final scriptRuntime = LoveScriptRuntime(
        engineMode: EngineMode.luaBytecode,
        host: LoveHeadlessHost(),
      );

      await scriptRuntime.execute('''
local canvas = love.graphics.newCanvas(16, 16)
result = tostring(canvas:getDepthSampleMode())
''');

      expect(scriptRuntime.unwrapGlobal('result'), 'nil');
    });

    test('getVersion and isVersionCompatible follow LOVE 11.5', () async {
      final versionResult = await lualike.execute('return love.getVersion()');
      expect(
        (versionResult as List).map((e) => (e as Value).unwrap()).toList(),
        <Object?>[11, 5, 0, 'Mysterious Mysteries'],
      );
      expect(
        ((await lualike.execute('return love.isVersionCompatible("11.5")'))
                as Value)
            .unwrap(),
        isTrue,
      );
      expect(
        ((await lualike.execute('return love.isVersionCompatible("11.4")'))
                as Value)
            .unwrap(),
        isTrue,
      );
      expect(
        ((await lualike.execute('return love.isVersionCompatible("11")'))
                as Value)
            .unwrap(),
        isFalse,
      );
      expect(
        ((await lualike.execute('return love.isVersionCompatible(11, 2, 0)'))
                as Value)
            .unwrap(),
        isTrue,
      );
      expect(
        ((await lualike.execute('return love.isVersionCompatible(12, 0, 0)'))
                as Value)
            .unwrap(),
        isFalse,
      );
    });

    test('deprecation output state can be queried and changed', () async {
      expect(
        ((await lualike.execute('return love.hasDeprecationOutput()')) as Value)
            .unwrap(),
        isTrue,
      );

      await lualike.execute('love.setDeprecationOutput(false)');
      expect(
        ((await lualike.execute('return love.hasDeprecationOutput()')) as Value)
            .unwrap(),
        isFalse,
      );

      await lualike.execute('love.setDeprecationOutput(true)');
      expect(
        ((await lualike.execute('return love.hasDeprecationOutput()')) as Value)
            .unwrap(),
        isTrue,
      );
    });

    test(
      'Lua scripts can use the core version and deprecation helpers',
      () async {
        final script = LoveScriptRuntime(runtime: runtime);

        await script.execute('''
testbed = {}

local major, minor, revision, codename = love.getVersion()
testbed.version = string.format("%d.%d.%d|%s", major, minor, revision, codename)
testbed.compat_string = love.isVersionCompatible("11.5")
testbed.compat_numbers = love.isVersionCompatible(11, 0, 0)
testbed.before = love.hasDeprecationOutput()
love.setDeprecationOutput(false)
testbed.after = love.hasDeprecationOutput()
''');

        final snapshot = script.unwrapGlobalTable('testbed')!;
        expect(snapshot['version'], '11.5.0|Mysterious Mysteries');
        expect(snapshot['compat_string'], isTrue);
        expect(snapshot['compat_numbers'], isTrue);
        expect(snapshot['before'], isTrue);
        expect(snapshot['after'], isFalse);
      },
    );
  });
}
