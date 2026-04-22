import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.font BMFont image validation', () {
    test(
      'newBMFontRasterizer rejects non-rgba page images with LOVE error text',
      () async {
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
          const <Object?>[8, 6, 'la8'],
        );

        await expectLater(
          () => _call(
            runtime,
            const ['love', 'font', 'newBMFontRasterizer'],
            <Object?>[definition, imageData],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Only 32-bit RGBA images are supported in BMFonts.',
            ),
          ),
        );
      },
    );

    test(
      'graphics.newFont rejects non-rgba BMFont page images with LOVE error text',
      () async {
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
          const <Object?>[8, 6, 'la8'],
        );

        await expectLater(
          () => _call(
            runtime,
            const ['love', 'graphics', 'newFont'],
            <Object?>[definition, imageData],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Only 32-bit RGBA images are supported in BMFonts.',
            ),
          ),
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
