import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/font_test_support.dart';

void main() {
  group('source-backed true type glyph coverage', () {
    test('rasterizers use cmap coverage for hasGlyphs', () async {
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

      expect(
        await _callMethod(rasterizer, 'hasGlyphs', const <Object?>['LuaLike']),
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
      expect(
        await _callMethod(rasterizer, 'hasGlyphs', const <Object?>[0x1f642]),
        isFalse,
      );

      final font = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        <Object?>[rasterizer],
      );
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
    });

    test('graphics.newFont keeps source-backed true type coverage', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final sourceDir = await love2dResourceDirectory();
      expect(LoveFilesystemState.of(runtime).setSource(sourceDir.path), isTrue);

      final font = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>['Vera.ttf', 16],
      );

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
      expect(
        await _callMethod(font, 'hasGlyphs', const <Object?>[0x1f642]),
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
    });

    test(
      'source-backed rasterizers use parsed outline metrics for glyph data',
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
          <Object?>[fileData, 12, 'normal', 2.0],
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

        expect(await _callMethod(wideGlyph, 'getFormat'), 'la8');
        expect(
          await _callMethod(wideGlyph, 'getWidth'),
          greaterThan(await _callMethod(narrowGlyph, 'getWidth') as num),
        );
        expect(
          await _callMethod(wideGlyph, 'getAdvance'),
          greaterThan(await _callMethod(narrowGlyph, 'getAdvance') as num),
        );
        expect(await _callMethod(spaceGlyph, 'getDimensions'), <Object?>[0, 0]);
        expect(await _callMethod(spaceGlyph, 'getAdvance'), greaterThan(0));
        expect(await _callMethod(spaceGlyph, 'getSize'), 0);
      },
    );

    test(
      'source-backed rasterizers and rasterizer-backed fonts use parsed vertical metrics',
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
          <Object?>[fileData, 16],
        );

        expect(await _callMethod(rasterizer, 'getHeight'), 19);
        expect(await _callMethod(rasterizer, 'getAscent'), 15);
        expect(await _callMethod(rasterizer, 'getDescent'), 4);
        expect(await _callMethod(rasterizer, 'getLineHeight'), 24);

        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer],
        );
        expect(await _callMethod(font, 'getHeight'), 19.0);
        expect(await _callMethod(font, 'getAscent'), 15.0);
        expect(await _callMethod(font, 'getDescent'), 4.0);
        expect(await _callMethod(font, 'getLineHeight'), 1.0);
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
