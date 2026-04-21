import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/font_test_support.dart';

void main() {
  group('love.font numeric truncation parity', () {
    test(
      'fractional numeric glyph lookups truncate toward zero like LOVE',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
        final fileData = await _call(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[veraBytes, 'Vera.ttf'],
        );
        final rasterizer = await _call(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          <Object?>[fileData, 12],
        );
        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[fileData, 12],
        );

        final constructorGlyph = await _call(
          runtime,
          const ['love', 'font', 'newGlyphData'],
          <Object?>[rasterizer, 65.9],
        );
        final methodGlyph = await _callMethod(
          rasterizer,
          'getGlyphData',
          const <Object?>[65.9],
        );

        expect(await _callMethod(constructorGlyph, 'getGlyph'), 65);
        expect(await _callMethod(constructorGlyph, 'getGlyphString'), 'A');
        expect(await _callMethod(methodGlyph, 'getGlyph'), 65);
        expect(await _callMethod(methodGlyph, 'getGlyphString'), 'A');

        final exactKerning =
            (await _callMethod(font, 'getKerning', const <Object?>[65, 86])
                    as num)
                .toDouble();
        final fractionalKerning =
            (await _callMethod(font, 'getKerning', const <Object?>[65.9, 86.9])
                    as num)
                .toDouble();

        expect(exactKerning, isNonZero);
        expect(fractionalKerning, exactKerning);
      },
    );

    test(
      'fractional numeric hasGlyphs inputs truncate before unicode validation',
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

        expect(
          await _callMethod(rasterizer, 'hasGlyphs', const <Object?>[
            0xd7ff + 0.9,
          ]),
          isTrue,
        );
        expect(
          await _callMethod(font, 'hasGlyphs', const <Object?>[0xd7ff + 0.9]),
          isTrue,
        );
      },
    );

    test(
      'fractional image font extra spacing truncates toward zero like LOVE',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await _call(
          runtime,
          const ['love', 'image', 'newImageData'],
          <Object?>[9, 6, 'rgba8', _imageFontStripBytes()],
        );

        final rasterizer = await _call(
          runtime,
          const ['love', 'font', 'newImageRasterizer'],
          <Object?>[imageData, 'ABC', 1.9],
        );
        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newImageFont'],
          <Object?>[imageData, 'ABC', 1.9],
        );

        expect(await _callMethod(rasterizer, 'getAdvance'), 4);
        expect(
          await _callMethod(font, 'getWidth', const <Object?>['ABC']),
          9.0,
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
