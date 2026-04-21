import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/font_test_support.dart';

void main() {
  group('default true type font bytes', () {
    test(
      'newTrueTypeRasterizer uses injected default font bytes for coverage and glyph count',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(defaultTrueTypeFontDataLoader: _loadVeraBytes),
        );

        final rasterizer = await _call(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>[12],
        );

        expect(await _callMethod(rasterizer, 'getGlyphCount'), 268);
        expect(await _callMethod(rasterizer, 'getHeight'), 14);
        expect(await _callMethod(rasterizer, 'getAscent'), 11);
        expect(await _callMethod(rasterizer, 'getDescent'), 3);
        expect(await _callMethod(rasterizer, 'getLineHeight'), 18);
        expect(
          await _callMethod(rasterizer, 'hasGlyphs', const <Object?>[
            'LuaLike',
          ]),
          isTrue,
        );
        expect(
          await _callMethod(rasterizer, 'hasGlyphs', const <Object?>['中']),
          isFalse,
        );
        expect(
          await _callMethod(rasterizer, 'hasGlyphs', const <Object?>['🙂']),
          isFalse,
        );
      },
    );

    test(
      'graphics.newFont uses injected default font bytes when no host-backed font is available',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(defaultTrueTypeFontDataLoader: _loadVeraBytes),
        );

        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        expect(await _callMethod(font, 'getHeight'), 14.0);
        expect(await _callMethod(font, 'getAscent'), 11.0);
        expect(await _callMethod(font, 'getDescent'), 3.0);
        expect(
          await _callMethod(font, 'hasGlyphs', const <Object?>['LuaLike']),
          isTrue,
        );
        expect(
          await _callMethod(font, 'hasGlyphs', const <Object?>['中']),
          isFalse,
        );
        expect(
          await _callMethod(font, 'hasGlyphs', const <Object?>['🙂']),
          isFalse,
        );

        final wideWidth =
            await _callMethod(font, 'getWidth', const <Object?>['W']) as num;
        final narrowWidth =
            await _callMethod(font, 'getWidth', const <Object?>['i']) as num;
        expect(wideWidth, greaterThan(narrowWidth));

        final aWidth =
            await _callMethod(font, 'getWidth', const <Object?>['A']) as num;
        final vWidth =
            await _callMethod(font, 'getWidth', const <Object?>['V']) as num;
        final avWidth =
            await _callMethod(font, 'getWidth', const <Object?>['AV']) as num;
        final avKerning =
            await _callMethod(font, 'getKerning', const <Object?>['A', 'V'])
                as num;

        expect(avKerning, lessThan(0));
        expect(avWidth, lessThan(aWidth + vWidth));
      },
    );
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
