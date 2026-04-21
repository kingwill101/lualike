import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/font_test_support.dart';

void main() {
  group('love.font source-backed metadata fallback parity', () {
    test(
      'graphics.newFont preserves missing-glyph width and synthetic tab spacing',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final sourceDir = await love2dResourceDirectory();
        expect(
          LoveFilesystemState.of(runtime).setSource(sourceDir.path),
          isTrue,
        );

        final rasterizer = await _call(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          <Object?>['Vera.ttf', 12, null, 2.0],
        );
        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>['Vera.ttf', 12, null, 2.0],
        );

        const missingGlyph = '🙂';
        final glyphData = await _callMethod(
          rasterizer,
          'getGlyphData',
          const <Object?>[missingGlyph],
        );
        final expectedMissingWidth =
            (await _callMethod(glyphData, 'getAdvance') as num) / 2.0;

        expect(
          await _callMethod(rasterizer, 'hasGlyphs', const <Object?>[
            missingGlyph,
          ]),
          isFalse,
        );
        expect(
          await _callMethod(font, 'hasGlyphs', const <Object?>[missingGlyph]),
          isFalse,
        );
        expect(
          await _callMethod(font, 'getWidth', const <Object?>[missingGlyph]),
          closeTo(expectedMissingWidth, 1e-9),
        );

        expect(
          await _callMethod(font, 'hasGlyphs', const <Object?>['\t']),
          isFalse,
        );
        expect(
          await _callMethod(font, 'getWidth', const <Object?>['\t']),
          closeTo(
            await _callMethod(font, 'getWidth', const <Object?>['    ']) as num,
            1e-9,
          ),
        );
        expect(
          await _callMethod(font, 'getWidth', const <Object?>['A\tA']),
          closeTo(
            await _callMethod(
                  font,
                  'getWidth',
                  const <Object?>['A    A'],
                )
                as num,
            1e-9,
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
