import 'dart:convert' as convert;

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/lua_bytecode/runtime.dart';
import 'package:lualike/src/parse.dart';

const String _entry = 'assets/relic_breach/main.lua';

void main() {
  test('ring buffer for relic breach unoptimized failure', () async {
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
local ringLimit = 30
local function push(entry)
  ring[#ring+1] = entry
  if #ring > ringLimit then
    table.remove(ring, 1)
  end
end
local function snapshot(level, tag)
  local info = debug.getinfo(level + 1, 'nSlf')
  if not info or not info.short_src or not info.short_src:find('main.lua', 1, true) then
    return nil
  end
  local entry = { tag = tag, name = info.name or 'nil', line = info.currentline or -1 }
  for i = 1, 6 do
    local name, value = debug.getlocal(level + 1, i)
    if not name then break end
    entry[#entry+1] = string.format('%s=%s:%s', name, type(value), tostring(value))
  end
  return table.concat(entry, ' | ')
end
local function hook()
  local entry = snapshot(2, 'L')
  if entry then
    push(entry)
  end
end
love.draw = function()
  debug.sethook(hook, '', 1)
  local ok, err = xpcall(old, function(msg)
    debug.sethook()
    print('HANDLER', tostring(msg))
    print('RING:')
    for i, item in ipairs(ring) do
      print(i, item)
    end
    return debug.traceback(msg)
  end)
  debug.sethook()
  if not ok then error(err) end
end
''', scriptPath: '=[ring install]');
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
