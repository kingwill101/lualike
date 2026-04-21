import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';

void main() {
  group('love.font BMFont bindings', () {
    test(
      'newBMFontRasterizer reads BMFont definitions and preserves kerning in graphics fonts',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final fileData = await _call(
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
          <Object?>[fileData, imageData, 1.0],
        );

        expect(await _callMethod(rasterizer, 'type'), 'Rasterizer');
        expect(await _callMethod(rasterizer, 'getGlyphCount'), 2);
        expect(await _callMethod(rasterizer, 'getAdvance'), 4);
        expect(await _callMethod(rasterizer, 'getHeight'), 6);
        expect(await _callMethod(rasterizer, 'getAscent'), 5);
        expect(await _callMethod(rasterizer, 'getDescent'), 1);
        expect(await _callMethod(rasterizer, 'getLineHeight'), 6);
        expect(
          await _callMethod(rasterizer, 'hasGlyphs', const <Object?>['AB']),
          isTrue,
        );

        final glyphData = await _callMethod(rasterizer, 'getGlyphData', ['B']);
        expect(await _callMethod(glyphData, 'getGlyphString'), 'B');
        expect(await _callMethod(glyphData, 'getDimensions'), <Object?>[2, 6]);
        expect(await _callMethod(glyphData, 'getAdvance'), 3);

        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer],
        );
        expect(
          await _callMethod(font, 'getKerning', const <Object?>['A', 'B']),
          -1.0,
        );
        expect(await _callMethod(font, 'getWidth', const <Object?>['AB']), 6.0);
      },
    );

    test(
      'newRasterizer autodetects BMFont file data and loads relative page images',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/bmfont/page.png': LoveImageData(
                width: 8,
                height: 6,
              ).encode('png'),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final fileData = await _call(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_bmFontDefinition, 'assets/fonts/bmfont/test.fnt'],
        );

        final rasterizer = await _call(
          runtime,
          const ['love', 'font', 'newRasterizer'],
          <Object?>[fileData],
        );
        expect(await _callMethod(rasterizer, 'getGlyphCount'), 2);
        expect(await _callMethod(rasterizer, 'getAdvance'), 4);

        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer],
        );
        expect(await _callMethod(font, 'getWidth', const <Object?>['AB']), 6.0);
      },
    );

    test('graphics.newFont loads BMFont definitions directly', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final fileData = await _call(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[_bmFontDefinition, 'assets/fonts/bmfont/test.fnt'],
      );
      final imageData = await _call(
        runtime,
        const ['love', 'image', 'newImageData'],
        const <Object?>[8, 6],
      );

      final font = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        <Object?>[fileData, imageData],
      );

      expect(await _callMethod(font, 'getHeight'), 6.0);
      expect(await _callMethod(font, 'getAscent'), 5.0);
      expect(await _callMethod(font, 'getDescent'), 1.0);
      expect(
        await _callMethod(font, 'getKerning', const <Object?>['A', 'B']),
        -1.0,
      );
      expect(await _callMethod(font, 'getWidth', const <Object?>['AB']), 6.0);
    });

    test('bmfont fallbacks contribute missing glyph widths and kerning', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final primaryDefinition = await _call(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[_bmFontPrimaryOnlyDefinition, 'assets/fonts/bmfont/primary.fnt'],
      );
      final fallbackDefinition = await _call(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[_bmFontDefinition, 'assets/fonts/bmfont/test.fnt'],
      );
      final imageData = await _call(
        runtime,
        const ['love', 'image', 'newImageData'],
        const <Object?>[8, 6],
      );

      final primary = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        <Object?>[primaryDefinition, imageData],
      );
      final fallback = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        <Object?>[fallbackDefinition, imageData],
      );

      await _callMethod(primary, 'setFallbacks', <Object?>[fallback]);

      expect(
        await _callMethod(primary, 'getKerning', const <Object?>['A', 'B']),
        -1.0,
      );
      expect(await _callMethod(primary, 'getWidth', const <Object?>['AB']), 6.0);
      expect(
        await _callMethod(primary, 'hasGlyphs', const <Object?>['AB']),
        isTrue,
      );
    });
  });
}

const String _bmFontPrimaryOnlyDefinition = '''
info face="PrimaryOnly" size=6 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1
common lineHeight=6 base=5 scaleW=8 scaleH=6 pages=1 packed=0
page id=0 file="page.png"
chars count=1
char id=88 x=0 y=0 width=3 height=6 xoffset=0 yoffset=0 xadvance=4 page=0 chnl=15
''';

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
