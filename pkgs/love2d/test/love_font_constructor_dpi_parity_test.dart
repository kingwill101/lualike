import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.font constructor dpi parity', () {
    test('image font constructors accept zero dpiscale', () async {
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
        <Object?>[imageData, 'ABC', 1, 0.0],
      );
      final rasterizerFont = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        <Object?>[rasterizer],
      );
      final directFont = await _call(
        runtime,
        const ['love', 'graphics', 'newImageFont'],
        <Object?>[imageData, 'ABC', 1, 0.0],
      );

      expect(await _callMethod(directFont, 'getDPIScale'), 0.0);
      expect(await _callMethod(rasterizerFont, 'getDPIScale'), 0.0);
      expect(
        await _callMethod(directFont, 'getHeight'),
        await _callMethod(rasterizerFont, 'getHeight'),
      );
      expect(
        await _callMethod(directFont, 'getWidth', const <Object?>['ABC']),
        await _callMethod(rasterizerFont, 'getWidth', const <Object?>['ABC']),
      );
    });

    test('bmfont constructors accept negative dpiscale', () async {
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
        <Object?>[definition, imageData, -2.0],
      );
      final rasterizerFont = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        <Object?>[rasterizer],
      );
      final directFont = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        <Object?>[definition, imageData, -2.0],
      );

      expect(await _callMethod(directFont, 'getDPIScale'), -2.0);
      expect(await _callMethod(rasterizerFont, 'getDPIScale'), -2.0);
      expect(
        await _callMethod(directFont, 'getHeight'),
        await _callMethod(rasterizerFont, 'getHeight'),
      );
      expect(
        await _callMethod(directFont, 'getWidth', const <Object?>['AB']),
        await _callMethod(rasterizerFont, 'getWidth', const <Object?>['AB']),
      );
    });
  });
}

Future<Object?> _call(
  Interpreter runtime,
  List<String> pathSegments, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime, pathSegments).call(args));
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

BuiltinFunction _rawFunction(Interpreter runtime, List<String> pathSegments) {
  var current = runtime.getCurrentEnv().get(pathSegments.first);
  for (final segment in pathSegments.skip(1)) {
    final table = current is Value ? current.raw : current;
    expect(
      table,
      isA<Map>(),
      reason: 'Expected ${pathSegments.join('.')} to traverse a Lua table',
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

  fillColumns(0, 1, const <int>[255, 0, 255, 255]);
  fillColumns(1, 3, const <int>[255, 255, 255, 255]);
  fillColumns(3, 4, const <int>[255, 0, 255, 255]);
  fillColumns(4, 5, const <int>[255, 96, 96, 255]);
  fillColumns(5, 6, const <int>[255, 0, 255, 255]);
  fillColumns(6, 9, const <int>[96, 255, 96, 255]);
  return bytes;
}
