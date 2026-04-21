import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.font true type rasterizers', () {
    test('expose estimated glyph data for individual glyph queries', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final rasterizer = await _call(
        runtime,
        const ['love', 'font', 'newTrueTypeRasterizer'],
        const <Object?>[12, 'light', 2.0],
      );

      final glyphData = await _call(
        runtime,
        const ['love', 'font', 'newGlyphData'],
        <Object?>[rasterizer, 'A'],
      );

      expect(await _callMethod(glyphData, 'type'), 'GlyphData');
      expect(await _callMethod(glyphData, 'getGlyph'), 65);
      expect(await _callMethod(glyphData, 'getGlyphString'), 'A');
      expect(await _callMethod(glyphData, 'getFormat'), 'la8');
      expect(await _callMethod(glyphData, 'getDimensions'), <Object?>[14, 24]);
      expect(await _callMethod(glyphData, 'getBearing'), <Object?>[0, 19]);
      expect(await _callMethod(glyphData, 'getAdvance'), 14);
      expect(await _callMethod(glyphData, 'getSize'), 672);

      final viaMethod = await _callMethod(
        rasterizer,
        'getGlyphData',
        const <Object?>[' '],
      );
      expect(await _callMethod(viaMethod, 'getFormat'), 'la8');
      expect(await _callMethod(viaMethod, 'getDimensions'), <Object?>[8, 24]);
      expect(await _callMethod(viaMethod, 'getAdvance'), 8);
      expect(await _callMethod(viaMethod, 'getSize'), 384);
    });

    test(
      'report approximate glyph availability for valid unicode scalars',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final rasterizer = await _call(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>[12],
        );

        expect(
          await _callMethod(rasterizer, 'hasGlyphs', const <Object?>[
            'LuaLike',
          ]),
          isTrue,
        );
        expect(
          await _callMethod(rasterizer, 'hasGlyphs', const <Object?>[0x1f642]),
          isTrue,
        );
        expect(
          await _callMethod(rasterizer, 'hasGlyphs', const <Object?>[0x110000]),
          isFalse,
        );
        expect(
          await _callMethod(rasterizer, 'hasGlyphs', const <Object?>[0xd800]),
          isFalse,
        );
        expect(
          await _callMethod(rasterizer, 'hasGlyphs', const <Object?>['']),
          isFalse,
        );
        await expectLater(
          () => _callMethod(rasterizer, 'hasGlyphs'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('Rasterizer:hasGlyphs expected a number at argument 2'),
            ),
          ),
        );
      },
    );

    test(
      'estimated glyph data uses transparent-white la8 placeholder bytes',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final rasterizer = await _call(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>[12, 'light', 2.0],
        );
        final glyphData = await _call(
          runtime,
          const ['love', 'font', 'newGlyphData'],
          <Object?>[rasterizer, 'A'],
        );

        final payload = _requireLuaStringBytes(
          await _callMethodRaw(glyphData, 'getString'),
        );
        expect(payload.length, 672);
        expect(payload[0], 255);
        expect(payload[1], 0);
        expect(payload[2], 255);
        expect(payload[3], 0);
        expect(payload[payload.length - 2], 255);
        expect(payload[payload.length - 1], 0);
      },
    );

    test(
      'glyph extraction distinguishes empty strings and non-string errors',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final rasterizer = await _call(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>[12],
        );

        await expectLater(
          () => _call(
            runtime,
            const ['love', 'font', 'newGlyphData'],
            <Object?>[rasterizer, ''],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'love.font.newGlyphData UTF-8 decoding error at argument 2: Not enough space',
              ),
            ),
          ),
        );

        await expectLater(
          () => _call(
            runtime,
            const ['love', 'font', 'newGlyphData'],
            <Object?>[rasterizer, <Object?, Object?>{}],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'love.font.newGlyphData expected a number at argument 2',
              ),
            ),
          ),
        );

        await expectLater(
          () => _callMethod(rasterizer, 'getGlyphData', const <Object?>['']),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Rasterizer:getGlyphData UTF-8 decoding error at argument 2: Not enough space',
              ),
            ),
          ),
        );

        await expectLater(
          () => _callMethod(rasterizer, 'getGlyphData', <Object?>[
            <Object?, Object?>{},
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Rasterizer:getGlyphData expected a number at argument 2',
              ),
            ),
          ),
        );
      },
    );

    test('glyph extraction reports LOVE-style invalid UTF-8 errors', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final rasterizer = await _call(
        runtime,
        const ['love', 'font', 'newTrueTypeRasterizer'],
        const <Object?>[12],
      );
      final malformed = LuaString.fromBytes(const <int>[0xc3, 0x28]);

      await expectLater(
        () => _call(
          runtime,
          const ['love', 'font', 'newGlyphData'],
          <Object?>[rasterizer, malformed],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains(
              'love.font.newGlyphData UTF-8 decoding error at argument 2: Invalid UTF-8',
            ),
          ),
        ),
      );

      await expectLater(
        () => _callMethod(rasterizer, 'getGlyphData', <Object?>[malformed]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains(
              'Rasterizer:getGlyphData UTF-8 decoding error at argument 2: Invalid UTF-8',
            ),
          ),
        ),
      );
    });
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

Future<Object?> _callMethodRaw(
  Object? receiver,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveRawCallResult(
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
  final resolved = await _resolveRawCallResult(result);
  if (resolved is List<Object?>) {
    return resolved.map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Future<Object?> _resolveRawCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(wrapped.raw as List<Object?>, growable: false);
  }
  return resolved;
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;

Uint8List _requireLuaStringBytes(Object? value) {
  final raw = value is Value ? value.raw : value;
  return switch (raw) {
    final LuaString stringValue => stringValue.bytes,
    _ => throw TestFailure('Expected a LuaString result'),
  };
}
