import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/font_test_support.dart';
import 'test_support/memory_filesystem_test_support.dart';

void main() {
  group('love.font advance rounding', () {
    test(
      'source-backed true type widths use LOVE-style snapped advances',
      () async {
        final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/Body.ttf': veraBytes,
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>['assets/fonts/Body.ttf', 16, 'mono', 2.0],
        );

        expect(await _callMethod(font, 'getWidth', const <Object?>['L']), 9.0);
        expect(await _callMethod(font, 'getWidth', const <Object?>['w']), 13.0);

        final wrapResult = await _callMethod(font, 'getWrap', const <Object?>[
          'LuaLike love wrap example',
          90.0,
        ]);
        final wrap = _deepUnwrap(wrapResult) as List<Object?>;
        expect(wrap[0], 80.0);
        expect(
          wrap[1],
          anyOf(
            <Object?, Object?>{1: 'LuaLike ', 2: 'love wrap ', 3: 'example'},
            <Object?, Object?>{
              '1': 'LuaLike ',
              '2': 'love wrap ',
              '3': 'example',
            },
          ),
        );
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
    _ => throw StateError('Expected method $method to be a BuiltinFunction'),
  };
}

Future<Object?> _resolveCallResult(Object? result) async {
  return switch (result) {
    final Future<Object?> future => future,
    _ => result,
  };
}

Object? _deepUnwrap(Object? value) {
  return switch (value) {
    final Value wrapped => _deepUnwrap(wrapped.raw),
    final Map<dynamic, dynamic> table => <Object?, Object?>{
      for (final entry in table.entries)
        _deepUnwrap(entry.key): _deepUnwrap(entry.value),
    },
    final List<dynamic> list => list.map(_deepUnwrap).toList(growable: false),
    _ => value,
  };
}
