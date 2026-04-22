import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/font_test_support.dart';

void main() {
  group('love.font optional arguments', () {
    test('true type constructors accept nil hinting before dpiscale', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final rasterizer = await _call(
        runtime,
        const ['love', 'font', 'newTrueTypeRasterizer'],
        <Object?>[12, null, 2.0],
      );
      expect(await _callMethod(rasterizer, 'getHeight'), 24);

      final font = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        <Object?>[12, null, 2.0],
      );
      expect(await _callMethod(font, 'getDPIScale'), 2.0);

      final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
      final fileData = await _call(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[veraBytes, 'Vera.ttf'],
      );
      final sourceRasterizer = await _call(
        runtime,
        const ['love', 'font', 'newTrueTypeRasterizer'],
        <Object?>[fileData, 12, null, 2.0],
      );
      expect(await _callMethod(sourceRasterizer, 'getGlyphCount'), 268);
      expect(await _callMethod(sourceRasterizer, 'getHeight'), greaterThan(24));

      final nilSizeRasterizer = await _call(
        runtime,
        const ['love', 'font', 'newTrueTypeRasterizer'],
        <Object?>[fileData, null, 'mono', 2.0],
      );
      final defaultSizeRasterizer = await _call(
        runtime,
        const ['love', 'font', 'newTrueTypeRasterizer'],
        <Object?>[fileData, 12, 'mono', 2.0],
      );
      expect(
        await _callMethod(nilSizeRasterizer, 'getHeight'),
        await _callMethod(defaultSizeRasterizer, 'getHeight'),
      );
      expect(
        await _callMethod(nilSizeRasterizer, 'getGlyphCount'),
        await _callMethod(defaultSizeRasterizer, 'getGlyphCount'),
      );
    });

    test(
      'image font constructors accept nil extraspacing before later arguments',
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
          <Object?>[imageData, 'ABC', null, 2.0],
        );
        expect(await _callMethod(rasterizer, 'getAdvance'), 3);

        final rasterizerFont = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer],
        );
        expect(await _callMethod(rasterizerFont, 'getDPIScale'), 2.0);
        expect(
          await _callMethod(rasterizerFont, 'getWidth', const <Object?>['ABC']),
          3.0,
        );

        final imageFont = await _call(
          runtime,
          const ['love', 'graphics', 'newImageFont'],
          <Object?>[imageData, 'ABC', null],
        );
        expect(
          await _callMethod(imageFont, 'getWidth', const <Object?>['ABC']),
          6.0,
        );
      },
    );

    test('bmfont constructors accept nil dpiscale', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final definition = await _call(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[_bmFontDefinition, 'assets/fonts/bmfont/test.fnt'],
      );
      final imageData = await _call(
        runtime,
        const ['love', 'image', 'newImageData'],
        const <Object?>[8, 6],
      );

      final rasterizer = await _call(
        runtime,
        const ['love', 'font', 'newBMFontRasterizer'],
        <Object?>[definition, imageData, null],
      );
      expect(await _callMethod(rasterizer, 'getGlyphCount'), 2);

      final font = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        <Object?>[definition, imageData, null],
      );
      expect(await _callMethod(font, 'getDPIScale'), 1.0);
      expect(await _callMethod(font, 'getHeight'), 6.0);
    });

    test(
      'graphics.newFont treats nil source size like the single-argument auto path',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final sourceDir = await love2dResourceDirectory();
        expect(
          LoveFilesystemState.of(runtime).setSource(sourceDir.path),
          isTrue,
        );

        final autoFont = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>['Vera.ttf'],
        );
        final nilSizeFont = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>['Vera.ttf', null, 2.0],
        );

        expect(
          await _callMethod(nilSizeFont, 'getHeight'),
          await _callMethod(autoFont, 'getHeight'),
        );
        expect(
          await _callMethod(nilSizeFont, 'getDPIScale'),
          await _callMethod(autoFont, 'getDPIScale'),
        );
        expect(
          await _callMethod(nilSizeFont, 'getWidth', const <Object?>['AV']),
          await _callMethod(autoFont, 'getWidth', const <Object?>['AV']),
        );
      },
    );

    test(
      'graphics.setNewFont treats nil source size like the single-argument auto path',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final sourceDir = await love2dResourceDirectory();
        expect(
          LoveFilesystemState.of(runtime).setSource(sourceDir.path),
          isTrue,
        );

        final autoFont = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>['Vera.ttf'],
        );
        final nilSizeFont = await _call(
          runtime,
          const ['love', 'graphics', 'setNewFont'],
          <Object?>['Vera.ttf', null, 'mono', 2.0],
        );
        final currentFont = await _call(runtime, const [
          'love',
          'graphics',
          'getFont',
        ]);

        expect(
          await _callMethod(nilSizeFont, 'getHeight'),
          await _callMethod(autoFont, 'getHeight'),
        );
        expect(
          await _callMethod(nilSizeFont, 'getDPIScale'),
          await _callMethod(autoFont, 'getDPIScale'),
        );
        expect(
          await _callMethod(nilSizeFont, 'getWidth', const <Object?>['AV']),
          await _callMethod(autoFont, 'getWidth', const <Object?>['AV']),
        );
        expect(
          await _callMethod(currentFont, 'getHeight'),
          await _callMethod(autoFont, 'getHeight'),
        );
        expect(
          await _callMethod(currentFont, 'getDPIScale'),
          await _callMethod(autoFont, 'getDPIScale'),
        );
        expect(
          await _callMethod(currentFont, 'getWidth', const <Object?>['AV']),
          await _callMethod(autoFont, 'getWidth', const <Object?>['AV']),
        );
      },
    );
  });
}

const String _bmFontDefinition = '''
info face="Test" size=6 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1
common lineHeight=6 base=5 scaleW=8 scaleH=6 pages=1 packed=0
page id=0 file="page.png"
chars count=2
char id=65 x=0 y=0 width=3 height=6 xoffset=0 yoffset=0 xadvance=4 page=0 chnl=15
char id=66 x=3 y=0 width=2 height=6 xoffset=0 yoffset=0 xadvance=3 page=0 chnl=15
kernings count=1
kerning first=65 second=66 amount=-1
''';

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
