import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/font_test_support.dart';

void main() {
  group('love.font true type bounding box parity', () {
    test('source-backed glyph data uses LOVE bounding-box semantics', () async {
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
        <Object?>[fileData, 16],
      );

      final wideGlyph = await _callMethod(
        rasterizer,
        'getGlyphData',
        const <Object?>['W'],
      );
      final narrowGlyph = await _callMethod(
        rasterizer,
        'getGlyphData',
        const <Object?>['i'],
      );
      final spaceGlyph = await _callMethod(
        rasterizer,
        'getGlyphData',
        const <Object?>[' '],
      );

      await _expectBoundingBoxMatchesMetrics(wideGlyph);
      await _expectBoundingBoxMatchesMetrics(narrowGlyph);
      await _expectBoundingBoxMatchesMetrics(spaceGlyph);

      expect(
        await _callMethod(spaceGlyph, 'getBoundingBox'),
        <Object?>[0, 0, 0, 0],
      );
    });
  });
}

Future<void> _expectBoundingBoxMatchesMetrics(Object? glyphData) async {
  final dimensions =
      await _callMethod(glyphData, 'getDimensions') as List<Object?>;
  final bearing = await _callMethod(glyphData, 'getBearing') as List<Object?>;
  final box = await _callMethod(glyphData, 'getBoundingBox') as List<Object?>;

  final width = dimensions[0] as num;
  final height = dimensions[1] as num;
  final bearingX = bearing[0] as num;
  final bearingY = bearing[1] as num;

  expect(box, <Object?>[
    bearingX,
    height - bearingY,
    width,
    bearingY - (height - bearingY),
  ]);
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
    current = (table! as Map)[segment];
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
