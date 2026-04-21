import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.font limitations', () {
    test(
      'default true type rasterizers without source data still reject glyph count enumeration',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final rasterizer = await _call(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>[12],
        );

        const message =
            'true type rasterizer glyph count is not supported yet without source font data';

        await expectLater(
          () => _callMethod(rasterizer, 'getGlyphCount'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(message),
            ),
          ),
        );
      },
    );

    test('font fallbacks reject different underlying font data types', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final bmFontDefinition = await _call(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[_bmFontDefinition, 'assets/fonts/bmfont/test.fnt'],
      );
      final bmFontPage = await _call(
        runtime,
        const ['love', 'image', 'newImageData'],
        const <Object?>[8, 6],
      );
      final bmFont = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        <Object?>[bmFontDefinition, bmFontPage],
      );

      final imageFontStrip = await _call(
        runtime,
        const ['love', 'image', 'newImageData'],
        <Object?>[9, 6, 'rgba8', _imageFontStripBytes()],
      );
      final imageFont = await _call(
        runtime,
        const ['love', 'graphics', 'newImageFont'],
        <Object?>[imageFontStrip, 'ABC', 1],
      );

      await expectLater(
        () => _callMethod(bmFont, 'setFallbacks', <Object?>[imageFont]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('same font type'),
          ),
        ),
      );
    });
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

List<int> _imageFontStripBytes() {
  final bytes = <int>[];
  for (var y = 0; y < 6; y++) {
    for (var x = 0; x < 9; x++) {
      final alpha = switch (x) {
        0 || 2 || 5 || 8 => 0,
        _ => 255,
      };
      bytes.addAll(<int>[255, 255, 255, alpha]);
    }
  }
  return bytes;
}
