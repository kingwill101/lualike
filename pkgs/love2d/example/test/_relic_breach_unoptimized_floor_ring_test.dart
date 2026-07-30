import 'dart:convert' as convert;

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/lua_bytecode/runtime.dart';
import 'package:lualike/src/parse.dart';

const String _entry = 'assets/relic_breach/main.lua';

void main() {
  test('ring line 1260 in unoptimized draw_floor', () async {
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
local ring = {}
local limit = 20
local function snap()
  local info = debug.getinfo(2, 'nSlf')
  if not info or info.currentline ~= 1260 then
    return
  end
  local entry = { name = info.name or 'nil', line = info.currentline }
  for i = 1, 28 do
    local name, value = debug.getlocal(2, i)
    if not name then break end
    entry[#entry+1] = string.format('%s=%s:%s', name, type(value), tostring(value))
  end
  ring[#ring+1] = entry
  if #ring > limit then
    table.remove(ring, 1)
  end
end
love.draw = function()
  local ok, err = xpcall(old, function(msg)
    print('HANDLER', tostring(msg))
    print('RING COUNT', #ring)
    for i, entry in ipairs(ring) do
      print('ENTRY', i, table.concat(entry, ' | '))
    end
    return debug.traceback(msg)
  end)
  if not ok then error(err) end
end

debug.sethook(snap, '', 1)
''', scriptPath: '=[floor ring install]');
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
