import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.thread Thread bindings', () {
    test(
      'threads can start, block on channels, and restart after wait',
      () async {
        final runtime = createLuaLikeTestRuntime();
        final lua = LuaLike(runtime: runtime);
        installLove2d(runtime: runtime);

        final gate = await luaCallList(runtime, const [
          'love',
          'thread',
          'newChannel',
        ]);
        final output = await luaCallList(runtime, const [
          'love',
          'thread',
          'newChannel',
        ]);
        final thread = await luaCallList(
          runtime,
          const ['love', 'thread', 'newThread'],
          <Object?>[
            '''
local gate, output, value = ...
gate:demand()
output:push(value * 2)
''',
          ],
        );

        expect(await luaCallMethodList(thread, 'type'), 'Thread');
        expect(
          await luaCallMethodList(thread, 'start', <Object?>[gate, output, 21]),
          isTrue,
        );
        expect(await luaCallMethodList(thread, 'isRunning'), isTrue);
        expect(
          await luaCallMethodList(thread, 'start', <Object?>[gate, output, 99]),
          isFalse,
        );
        expect(await luaCallMethodList(output, 'pop'), isNull);

        expect(await luaCallMethodList(gate, 'push', const <Object?>[true]), 1);
        await luaCallMethodList(thread, 'wait');
        expect(await luaCallMethodList(thread, 'isRunning'), isFalse);
        expect(await luaCallMethodList(output, 'pop'), 42);
        expect(await luaCallMethodList(thread, 'getError'), isNull);

        final secondGate = await luaCallList(runtime, const [
          'love',
          'thread',
          'newChannel',
        ]);
        final secondOutput = await luaCallList(runtime, const [
          'love',
          'thread',
          'newChannel',
        ]);
        expect(
          await luaCallMethodList(thread, 'start', <Object?>[
            secondGate,
            secondOutput,
            11,
          ]),
          isTrue,
        );
        expect(
          await luaCallMethodList(secondGate, 'push', const <Object?>[true]),
          1,
        );
        await luaCallMethodList(thread, 'wait');
        expect(await luaCallMethodList(secondOutput, 'pop'), 22);

        final threadResult = await _execute(lua, '''
local gate = love.thread.newChannel()
local output = love.thread.newChannel()
local worker = love.thread.newThread([[
  local gate, output, value = ...
  gate:demand()
  output:push(value + 5)
]])
worker:start(gate, output, 10)
gate:push(true)
worker:wait()
return output:pop()
''');
        expect(threadResult, 15);
      },
    );

    test('threads can be created from mounted filesystem filenames', () async {
      final runtime = createLuaLikeTestRuntime();
      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(),
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'scripts/worker.lua':
                '''
local output, text = ...
output:push(text)
'''
                    .codeUnits,
          }),
        ),
      );
      final filesystem = LoveFilesystemState.of(runtime);
      expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

      final output = await luaCallList(runtime, const [
        'love',
        'thread',
        'newChannel',
      ]);
      final thread = await luaCallList(
        runtime,
        const ['love', 'thread', 'newThread'],
        const <Object?>['scripts/worker.lua'],
      );

      expect(
        await luaCallMethodList(thread, 'start', <Object?>[
          output,
          'from file',
        ]),
        isTrue,
      );
      await luaCallMethodList(thread, 'wait');
      expect(await luaCallMethodList(output, 'pop'), 'from file');
      expect(await luaCallMethodList(thread, 'getError'), isNull);
    });

    test(
      'thread errors populate getError and queue threaderror events',
      () async {
        final runtime = createLuaLikeTestRuntime();
        final lua = LuaLike(runtime: runtime);
        installLove2d(runtime: runtime);

        final thread = await luaCallList(
          runtime,
          const ['love', 'thread', 'newThread'],
          <Object?>[
            '''
error("boom from worker")
''',
          ],
        );

        expect(await luaCallMethodList(thread, 'start'), isTrue);
        await luaCallMethodList(thread, 'wait');

        final error = await luaCallMethodList(thread, 'getError');
        expect(error, isA<String>());
        expect(error as String, contains('boom from worker'));

        final event = await _execute(lua, '''
local poll = love.event.poll()
local name, queuedThread, err = poll()
return name, queuedThread:type(), queuedThread:isRunning(), err
''');
        expect(event, isA<List<Object?>>());
        final eventItems = event! as List<Object?>;
        expect(eventItems[0], 'threaderror');
        expect(eventItems[1], 'Thread');
        expect(eventItems[2], false);
        expect(eventItems[3], isA<String>());
        expect(eventItems[3] as String, contains('boom from worker'));
      },
    );
  });
}

Future<Object?> _execute(LuaLike lua, String code, {String? scriptPath}) async {
  return luaResolveCallResultList(lua.execute(code, scriptPath: scriptPath));
}
