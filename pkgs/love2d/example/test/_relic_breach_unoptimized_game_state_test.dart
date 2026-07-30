import 'dart:convert' as convert;

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/lua_bytecode/runtime.dart';
import 'package:lualike/src/parse.dart';

const String _entry = 'assets/relic_breach/main.lua';

void main() {
  test('game state in unoptimized draw_quad', () async {
    final runtime = LoveScriptRuntime(
      runtime: LuaBytecodeRuntime(),
      host: LoveHeadlessHost(),
      filesystemAdapter: LoveLualikeFilesystemAdapter(),
    );
    final filesystem = LoveFilesystemState.of(runtime.runtime);
    expect(filesystem.setSource(_entry), isTrue);
    await runtime.loadConfIfPresent();
    final entryData = await filesystem.readFileData('main.lua', filename: _entry);
    final source = convert.utf8.decode(entryData!.bytes);
    final program = parse(source, url: entryData.filename);
    final pipeline = CompilePipeline(
      config: const CompilePipelineConfig(
        target: CompileBackend.luaBytecode,
        enableAnalyzer: false,
        enableConstantFolding: false,
        enableConstPropagation: false,
        enableTypeNarrowing: false,
        enableMetatableFolding: false,
        enablePeephole: false,
        enableBytecodePeephole: false,
        enableSsaDeadCodeElimination: false,
        enableSsaGlobalValueNumbering: false,
        enableSsaSccp: false,
        enableSsaLicm: false,
        enableSsaCoalesce: false,
        enableSsaEscape: false,
        enableFunctionInlining: false,
        enableLoopUnrolling: false,
        enableBundling: false,
        bundleSearchPaths: ['.'],
        enableDeadCodeElimination: false,
      ),
    );
    final artifact = pipeline.compile(program) as LuaBytecodeArtifact;
    final chunk = await runtime.runtime.loadBytecode(artifact.serializedBytes, moduleName: _entry);
    await runtime.runtime.callFunction(chunk, const <Object?>[]);
    await runtime.callLoadIfDefined();
    await runtime.callUpdateIfDefined(1 / 60);
    await runtime.execute(r'''
local old = love.draw
local seen = false
love.draw = function()
  local ok, err = xpcall(old, function(msg)
    if not seen then
      seen = true
      print('HANDLER', tostring(msg))
      local game
      for i = 1, 20 do
        local name, value = debug.getupvalue(old, i)
        if not name then break end
        if name == 'game' then
          game = value
          print('GAME-UPVALUE', i, name, type(game), tostring(game))
          break
        end
      end
      if game then
        print('ATLAS', type(game.atlas), tostring(game.atlas))
        print('FLOORS', type(game.quads and game.quads.floors), tostring(game.quads and game.quads.floors))
      end
    end
    return debug.traceback(msg)
  end)
  if not ok then error(err) end
end
''', scriptPath: '=[state install]');
    runtime.context.beginDrawFrame();
    runtime.context.graphics.origin();
    try {
      await runtime.callDrawIfDefined();
      fail('expected failure');
    } catch (_) {
      // expected
    }
  });
}
