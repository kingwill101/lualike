import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/font_test_support.dart';

void main() {
  group('love.font single-glyph UTF-8 parity', () {
    test(
      'newGlyphData and getGlyphData ignore trailing invalid bytes after the first codepoint',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final rasterizer = await _call(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>[12],
        );
        final malformedA = LuaString.fromBytes(const <int>[0x41, 0xff]);

        final constructorGlyph = await _call(
          runtime,
          const ['love', 'font', 'newGlyphData'],
          <Object?>[rasterizer, malformedA],
        );
        final methodGlyph = await _callMethod(
          rasterizer,
          'getGlyphData',
          <Object?>[malformedA],
        );

        expect(await _callMethod(constructorGlyph, 'getGlyph'), 65);
        expect(await _callMethod(constructorGlyph, 'getGlyphString'), 'A');
        expect(await _callMethod(methodGlyph, 'getGlyph'), 65);
        expect(await _callMethod(methodGlyph, 'getGlyphString'), 'A');
      },
    );

    test(
      'Font:getKerning string overload ignores trailing invalid bytes after the first codepoint',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
        final fileData = await _call(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[veraBytes, 'Vera.ttf'],
        );
        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[fileData, 16],
        );

        final baseline =
            await _callMethod(font, 'getKerning', const <Object?>['A', 'V'])
                as num;

        expect(
          await _callMethod(
            font,
            'getKerning',
            <Object?>[LuaString.fromBytes(const <int>[0x41, 0xff]), 'V'],
          ),
          baseline,
        );
        expect(
          await _callMethod(
            font,
            'getKerning',
            <Object?>['A', LuaString.fromBytes(const <int>[0x56, 0xff])],
          ),
          baseline,
        );
      },
    );

    test(
      'full-string APIs still reject trailing invalid bytes after the first codepoint',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final rasterizer = await _call(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>[12],
        );
        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );
        final malformedA = LuaString.fromBytes(const <int>[0x41, 0xff]);

        Future<void> expectUtf8Error(
          Future<Object?> Function() callback,
        ) async {
          await expectLater(
            callback,
            throwsA(
              isA<LuaError>().having(
                (error) => error.message,
                'message',
                contains('UTF-8 decoding error at argument 2: Invalid UTF-8'),
              ),
            ),
          );
        }

        await expectUtf8Error(
          () => _callMethod(rasterizer, 'hasGlyphs', <Object?>[malformedA]),
        );
        await expectUtf8Error(
          () => _callMethod(font, 'hasGlyphs', <Object?>[malformedA]),
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
