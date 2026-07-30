import 'dart:convert' as convert;

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/lua_bytecode/runtime.dart';
import 'package:lualike/src/parse.dart';

const String _entry = 'assets/relic_breach/main.lua';

void main() {
  test('locals around relic breach failure', () async {
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
local hits = 0
local reported = false
local function dump(tag, level)
  local quadName, quad = debug.getlocal(level + 1, 1)
  local xName, x = debug.getlocal(level + 1, 2)
  local yName, y = debug.getlocal(level + 1, 3)
  if x ~= nil and y ~= nil and quad ~= nil then
    return
  end
  reported = true
  print('DUMP', tag)
  print('ARGS', quadName, type(quad), tostring(quad), xName, type(x), tostring(x), yName, type(y), tostring(y))
  for i = 1, 28 do
    local name, value = debug.getlocal(level + 1, i)
    if not name then break end
    print('LOCAL', i, name, type(value), tostring(value))
  end
  local info = debug.getinfo(level + 1, 'nSlf')
  if info then
    print('INFO', info.name or 'nil', info.currentline, info.short_src)
  end
end
local function hook()
  if reported then return end
  local info = debug.getinfo(2, 'nSlf')
  if not info or not info.short_src or not info.short_src:find('main.lua', 1, true) then
    return
  end
  if info.currentline == 663 and hits < 500 then
    hits = hits + 1
    dump('draw_quad', 2)
  elseif info.currentline == 1260 and hits < 500 then
    hits = hits + 1
    dump('draw_floor', 2)
  end
  if hits >= 500 or reported then
    debug.sethook()
  end
end
debug.sethook(hook, '', 1)
''', scriptPath: '=[relic_breach locals hook]');
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
