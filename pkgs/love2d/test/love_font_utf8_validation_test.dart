import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.font UTF-8 validation', () {
    test(
      'image font constructors reject malformed UTF-8 glyph lists',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await _call(
          runtime,
          const ['love', 'image', 'newImageData'],
          <Object?>[9, 6, 'rgba8', _imageFontStripBytes()],
        );
        final malformed = LuaString.fromBytes(const <int>[0xc3, 0x28]);

        await expectLater(
          () => _call(
            runtime,
            const ['love', 'font', 'newImageRasterizer'],
            <Object?>[imageData, malformed, 1, 1.0],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('UTF-8 decoding error at argument 2: Invalid UTF-8'),
            ),
          ),
        );

        await expectLater(
          () => _call(
            runtime,
            const ['love', 'graphics', 'newImageFont'],
            <Object?>[imageData, malformed, 1],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('UTF-8 decoding error at argument 2: Invalid UTF-8'),
            ),
          ),
        );
      },
    );

    test(
      'glyph lookup and measurement APIs reject malformed UTF-8 LuaString inputs',
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
        final malformed = LuaString.fromBytes(const <int>[0xc3, 0x28]);

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
          () => _call(
            runtime,
            const ['love', 'font', 'newGlyphData'],
            <Object?>[rasterizer, malformed],
          ),
        );
        await expectUtf8Error(
          () => _callMethod(rasterizer, 'getGlyphData', <Object?>[malformed]),
        );
        await expectUtf8Error(
          () => _callMethod(rasterizer, 'hasGlyphs', <Object?>[malformed]),
        );
        await expectUtf8Error(
          () => _callMethod(font, 'hasGlyphs', <Object?>[malformed]),
        );
        await expectUtf8Error(
          () => _callMethod(font, 'getKerning', <Object?>[malformed, 'A']),
        );
        await expectUtf8Error(
          () => _callMethod(font, 'getWidth', <Object?>[malformed]),
        );
        await expectUtf8Error(
          () => _callMethod(font, 'getWrap', <Object?>[malformed, 10.0]),
        );
      },
    );

    test(
      'glyph data rejects invalid codepoints when re-encoding glyph strings',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final rasterizer = await _call(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>[12],
        );
        final glyphData = await _call(
          runtime,
          const ['love', 'font', 'newGlyphData'],
          <Object?>[rasterizer, 0x110000],
        );

        await expectLater(
          () => _callMethod(glyphData, 'getGlyphString'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('UTF-8 decoding error: Invalid code point'),
            ),
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

Uint8List _imageFontStripBytes() {
  final bytes = Uint8List(9 * 6 * 4);

  void fillColumns(int start, int end, List<int> rgba) {
    for (var row = 0; row < 6; row++) {
      for (var column = start; column < end; column++) {
        final offset = ((row * 9) + column) * 4;
        bytes[offset] = rgba[0];
        bytes[offset + 1] = rgba[1];
        bytes[offset + 2] = rgba[2];
        bytes[offset + 3] = rgba[3];
      }
    }
  }

  fillColumns(1, 3, const <int>[255, 255, 255, 255]);
  fillColumns(4, 5, const <int>[255, 96, 96, 255]);
  fillColumns(6, 9, const <int>[96, 255, 96, 255]);
  return bytes;
}
