import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.font BMFont page table parity', () {
    test(
      'newBMFontRasterizer maps contiguous image tables to zero-based page ids',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final definition = await _call(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_bmFontSecondPageDefinition, 'assets/fonts/bmfont/test.fnt'],
        );
        final pageImage = await _call(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[8, 6],
        );

        final rasterizer = await _call(
          runtime,
          const ['love', 'font', 'newBMFontRasterizer'],
          <Object?>[
            definition,
            <Object?, Object?>{1: pageImage, 2: pageImage},
          ],
        );

        expect(await _callMethod(rasterizer, 'getGlyphCount'), 1);
        final glyphData = await _callMethod(rasterizer, 'getGlyphData', ['B']);
        expect(await _callMethod(glyphData, 'getGlyphString'), 'B');
        expect(await _callMethod(glyphData, 'getDimensions'), <Object?>[2, 6]);
      },
    );

    test(
      'graphics.newFont ignores sparse BMFont page tables after the first hole',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final definition = await _call(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_bmFontSecondPageDefinition, 'assets/fonts/bmfont/test.fnt'],
        );
        final pageImage = await _call(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[8, 6],
        );

        await expectLater(
          () => _call(
            runtime,
            const ['love', 'graphics', 'newFont'],
            <Object?>[
              definition,
              <Object?, Object?>{2: pageImage},
            ],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('missing image for BMFont page 1'),
            ),
          ),
        );
      },
    );
  });
}

const String _bmFontSecondPageDefinition = '''
info face="SecondPage" size=6 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1
common lineHeight=6 base=5 scaleW=8 scaleH=6 pages=2 packed=0
page id=1 file=""
chars count=1
char id=66 x=3 y=0 width=2 height=6 xoffset=0 yoffset=0 xadvance=3 page=1 chnl=15
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
