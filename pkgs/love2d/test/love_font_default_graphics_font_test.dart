import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/font_test_support.dart';

void main() {
  group('default graphics font', () {
    test('getFont lazily loads and restores the cached default font', () async {
      final runtime = Interpreter();
      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(defaultTrueTypeFontDataLoader: _loadVeraBytes),
      );

      final firstFont = await _call(runtime, const [
        'love',
        'graphics',
        'getFont',
      ]);

      expect(await _callMethod(firstFont, 'getHeight'), 14.0);
      expect(
        await _callMethod(firstFont, 'hasGlyphs', const <Object?>['LuaLike']),
        isTrue,
      );

      await _callMethod(firstFont, 'setLineHeight', const <Object?>[1.5]);
      await _call(runtime, const ['love', 'graphics', 'reset']);

      final secondFont = await _call(runtime, const [
        'love',
        'graphics',
        'getFont',
      ]);

      expect(await _callMethod(secondFont, 'getLineHeight'), 1.5);
      expect(LoveRuntimeContext.of(runtime).graphicsStats()['fonts'], 1);
    });

    test(
      'setNewFont keeps the default graphics font counted in stats',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(defaultTrueTypeFontDataLoader: _loadVeraBytes),
        );

        expect(LoveRuntimeContext.of(runtime).graphicsStats()['fonts'], 1);

        await _call(
          runtime,
          const ['love', 'graphics', 'setNewFont'],
          const <Object?>[18.0],
        );

        expect(LoveRuntimeContext.of(runtime).graphicsStats()['fonts'], 2);
      },
    );

    test('print and printf lazily use the cached default font', () async {
      final host = LoveHeadlessHost(
        defaultTrueTypeFontDataLoader: _loadVeraBytes,
      );
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: host);

      host.graphics.beginFrame();
      await _call(runtime, const ['love', 'graphics', 'reset']);
      await _call(
        runtime,
        const ['love', 'graphics', 'print'],
        const <Object?>['Wi', 4.0, 8.0],
      );
      await _call(
        runtime,
        const ['love', 'graphics', 'printf'],
        const <Object?>['Wi', 4.0, 8.0, 120.0, 'left'],
      );

      expect(host.graphics.commands, hasLength(2));

      final printCommand = host.graphics.commands[0] as LoveTextCommand;
      final printfCommand = host.graphics.commands[1] as LoveTextCommand;

      expect(printCommand.font.height, 14.0);
      expect(printfCommand.font.height, 14.0);
      expect(
        printCommand.font.measureWidth('W'),
        greaterThan(printCommand.font.measureWidth('i')),
      );
      expect(
        printfCommand.font.measureWidth('W'),
        printCommand.font.measureWidth('W'),
      );
      expect(
        printCommand.font.hasGlyphValues(const <Object?>['LuaLike']),
        isTrue,
      );
      expect(LoveRuntimeContext.of(runtime).graphicsStats()['fonts'], 1);
    });
  });
}

Future<Uint8List> _loadVeraBytes() async {
  final bytes = await (await love2dVeraFontFile()).readAsBytes();
  return Uint8List.fromList(bytes);
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
    _ => throw TestFailure('Expected $method to be a callable Lua method'),
  };
}

Future<Object?> _resolveCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(
      wrapped.raw as List<Object?>,
      growable: false,
    ).map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
