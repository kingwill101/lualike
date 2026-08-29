import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String _browserEntry = 'example/assets/love_example_browser/main.lua';
const String _examplesDir = 'example/assets/love_example_browser/examples';
const String _viewSmokeExample = 'zzz_filler.lua';

void main() {
  final exampleFiles =
      Directory(_examplesDir)
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.lua'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  if (exampleFiles.isEmpty) {
    test('example browser smoke examples exist', () {
      fail('No example browser Lua files found in $_examplesDir');
    });
    return;
  }

  for (final file in exampleFiles) {
    final exampleName = file.uri.pathSegments.last;
    test(
      'example browser smoke: $exampleName',
      () async {
        await _runExampleSmoke(
          exampleName,
        ).timeout(const Duration(seconds: 10));
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  }

  test(
    'example browser right click smoke: $_viewSmokeExample',
    () async {
      await _runBrowserViewSmoke(
        _viewSmokeExample,
      ).timeout(const Duration(seconds: 10));
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
}

Future<void> _runExampleSmoke(String exampleName) async {
  final runtime = LoveScriptRuntime(
    host: LoveHeadlessHost(),
    filesystemAdapter: LoveLualikeFilesystemAdapter(),
  );
  final filesystem = LoveFilesystemState.of(runtime.runtime);

  expect(
    filesystem.setSource(_browserEntry),
    isTrue,
    reason: 'failed to set LOVE filesystem source root',
  );

  final relative = 'examples/$exampleName';
  try {
    await runtime.execute('''
local loaded = assert(love.filesystem.load("$relative"))
loaded()
''', scriptPath: '=[example smoke bootstrap]');

    await runtime.callLoadIfDefined();

    for (var frame = 0; frame < 3; frame++) {
      await runtime.callUpdateIfDefined(1 / 60);
      runtime.context.beginDrawFrame();
      runtime.context.graphics.origin();
      await runtime.callDrawIfDefined();
    }
  } catch (error, stackTrace) {
    fail('''
Smoke run failed for $exampleName

Error:
$error

Stack:
$stackTrace
''');
  }
}

Future<void> _runBrowserViewSmoke(String exampleName) async {
  final runtime = LoveScriptRuntime(
    host: LoveHeadlessHost(),
    filesystemAdapter: LoveLualikeFilesystemAdapter(),
  );
  final filesystem = LoveFilesystemState.of(runtime.runtime);

  expect(
    filesystem.setSource(_browserEntry),
    isTrue,
    reason: 'failed to set LOVE filesystem source root',
  );

  try {
    await runtime.execute('''
local loaded = assert(love.filesystem.load("main.lua"))
loaded()
''', scriptPath: '=[browser view smoke bootstrap]');

    await runtime.callLoadIfDefined();

    await runtime.execute('''
local target = "$exampleName"
local index = nil
for i, item in ipairs(exf.list.items) do
  if item.id == target then
    index = i
    break
  end
end
assert(index ~= nil, "missing example in browser list: " .. target)
exf.view(index)
''', scriptPath: '=[browser view smoke action]');

    runtime.context.beginDrawFrame();
    runtime.context.graphics.origin();
    await runtime.callDrawIfDefined();
  } catch (error, stackTrace) {
    fail('''
Browser view smoke run failed for $exampleName

Error:
$error

Stack:
$stackTrace
''');
  }
}
