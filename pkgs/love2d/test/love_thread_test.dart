import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';

void main() {
  group('love.thread Thread bindings', () {
    test(
      'threads can start, block on channels, and restart after wait',
      () async {
        final runtime = Interpreter();
        final lua = LuaLike(runtime: runtime);
        installLove2d(runtime: runtime);

        final gate = await _call(runtime, const [
          'love',
          'thread',
          'newChannel',
        ]);
        final output = await _call(runtime, const [
          'love',
          'thread',
          'newChannel',
        ]);
        final thread = await _call(
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

        expect(await _callMethod(thread, 'type'), 'Thread');
        expect(
          await _callMethod(thread, 'start', <Object?>[gate, output, 21]),
          isTrue,
        );
        expect(await _callMethod(thread, 'isRunning'), isTrue);
        expect(
          await _callMethod(thread, 'start', <Object?>[gate, output, 99]),
          isFalse,
        );
        expect(await _callMethod(output, 'pop'), isNull);

        expect(await _callMethod(gate, 'push', const <Object?>[true]), 1);
        await _callMethod(thread, 'wait');
        expect(await _callMethod(thread, 'isRunning'), isFalse);
        expect(await _callMethod(output, 'pop'), 42);
        expect(await _callMethod(thread, 'getError'), isNull);

        final secondGate = await _call(runtime, const [
          'love',
          'thread',
          'newChannel',
        ]);
        final secondOutput = await _call(runtime, const [
          'love',
          'thread',
          'newChannel',
        ]);
        expect(
          await _callMethod(thread, 'start', <Object?>[
            secondGate,
            secondOutput,
            11,
          ]),
          isTrue,
        );
        expect(await _callMethod(secondGate, 'push', const <Object?>[true]), 1);
        await _callMethod(thread, 'wait');
        expect(await _callMethod(secondOutput, 'pop'), 22);

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
      final runtime = Interpreter();
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

      final output = await _call(runtime, const [
        'love',
        'thread',
        'newChannel',
      ]);
      final thread = await _call(
        runtime,
        const ['love', 'thread', 'newThread'],
        const <Object?>['scripts/worker.lua'],
      );

      expect(
        await _callMethod(thread, 'start', <Object?>[output, 'from file']),
        isTrue,
      );
      await _callMethod(thread, 'wait');
      expect(await _callMethod(output, 'pop'), 'from file');
      expect(await _callMethod(thread, 'getError'), isNull);
    });

    test(
      'thread errors populate getError and queue threaderror events',
      () async {
        final runtime = Interpreter();
        final lua = LuaLike(runtime: runtime);
        installLove2d(runtime: runtime);

        final thread = await _call(
          runtime,
          const ['love', 'thread', 'newThread'],
          <Object?>[
            '''
error("boom from worker")
''',
          ],
        );

        expect(await _callMethod(thread, 'start'), isTrue);
        await _callMethod(thread, 'wait');

        final error = await _callMethod(thread, 'getError');
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

Future<Object?> _call(
  Interpreter runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime, path).call(args));
}

Future<Object?> _callMethod(
  Object? receiver,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(
    _rawMethod(receiver, method).call(<Object?>[receiver, ...args]),
  );
}

Future<Object?> _execute(LuaLike lua, String code, {String? scriptPath}) async {
  return _resolveCallResult(lua.execute(code, scriptPath: scriptPath));
}

BuiltinFunction _rawFunction(Interpreter runtime, List<String> path) {
  var current = runtime.getCurrentEnv().get(path.first);
  for (final segment in path.skip(1)) {
    final table = current is Value ? current.raw : current;
    expect(
      table,
      isA<Map>(),
      reason: 'Expected ${path.join('.')} to traverse a Lua table',
    );
    current = (table as Map)[segment];
  }

  expect(current, isA<Value>());
  final raw = (current! as Value).raw;
  expect(raw, isA<BuiltinFunction>());
  return raw as BuiltinFunction;
}

BuiltinFunction _rawMethod(Object? receiver, String method) {
  final table = receiver is Value ? receiver.raw : receiver;
  expect(table, isA<Map>());
  final entry = (table! as Map)[method];
  return switch (entry) {
    final Value wrapped when wrapped.raw is BuiltinFunction =>
      wrapped.raw as BuiltinFunction,
    final BuiltinFunction function => function,
    _ => throw TestFailure('Expected $method to be a callable Lua method'),
  };
}

Future<Object?> _resolveCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;
  if (resolved is List<Object?>) {
    return resolved.map(_unwrap).toList(growable: false);
  }
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(
      wrapped.raw as List<Object?>,
      growable: false,
    ).map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
