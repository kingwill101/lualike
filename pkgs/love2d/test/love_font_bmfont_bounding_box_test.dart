import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.font BMFont bounding box parity', () {
    test('bmfont glyph offsets map to LOVE bearings and bounding boxes', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final fileData = await _call(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[_offsetBmFontDefinition, 'assets/fonts/bmfont/offsets.fnt'],
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

      final glyphData = await _callMethod(rasterizer, 'getGlyphData', ['B']);

      expect(await _callMethod(glyphData, 'getDimensions'), <Object?>[2, 4]);
      expect(await _callMethod(glyphData, 'getBearing'), <Object?>[2, -1]);
      expect(await _callMethod(glyphData, 'getBoundingBox'), <Object?>[
        2,
        5,
        2,
        -6,
      ]);
      expect(await _callMethod(glyphData, 'getAdvance'), 5);
    });
  });
}

const String _offsetBmFontDefinition = '''
info face="OffsetTest" size=6 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1
common lineHeight=6 base=5 scaleW=8 scaleH=6 pages=1 packed=0
page id=0 file="page.png"
chars count=1
char id=66 x=0 y=0 width=2 height=4 xoffset=2 yoffset=1 xadvance=5 page=0 chnl=15
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
