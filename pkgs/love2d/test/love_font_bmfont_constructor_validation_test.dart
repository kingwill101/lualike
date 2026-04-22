import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';

void main() {
  group('love.font BMFont constructor validation', () {
    test(
      'newBMFontRasterizer uses LOVE BMFont error text for invalid FileData definitions',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final definition = await _call(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          const <Object?>[_notABmFontDefinition, 'assets/fonts/invalid.fnt'],
        );
        final imageData = await _call(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[4, 4, 'rgba8'],
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
              'Invalid BMFont file (no character definitions?)',
            ),
          ),
        );
      },
    );

    test(
      'graphics.newFont uses LOVE BMFont error text for invalid FileData definitions',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final definition = await _call(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          const <Object?>[_notABmFontDefinition, 'assets/fonts/invalid.fnt'],
        );
        final imageData = await _call(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[4, 4, 'rgba8'],
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
              'Invalid BMFont file (no character definitions?)',
            ),
          ),
        );
      },
    );

    test(
      'graphics.newFont uses LOVE BMFont error text for invalid mounted definitions',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/invalid.fnt': utf8.encode(_notABmFontDefinition),
            }),
          ),
        );
        expect(
          LoveFilesystemState.of(runtime).setSource(loveTestMountedSourceRoot),
          isTrue,
        );

        final imageData = await _call(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[4, 4, 'rgba8'],
        );

        await expectLater(
          () => _call(
            runtime,
            const ['love', 'graphics', 'newFont'],
            <Object?>['assets/fonts/invalid.fnt', imageData],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid BMFont file (no character definitions?)',
            ),
          ),
        );
      },
    );

    test(
      'newBMFontRasterizer rejects whitespace-prefixed valid definitions like upstream',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final definition = await _call(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          const <Object?>[
            _whitespacePrefixedValidBmFontDefinition,
            'assets/fonts/invalid.fnt',
          ],
        );
        final imageData = await _call(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[4, 4, 'rgba8'],
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
              'Invalid BMFont file (no character definitions?)',
            ),
          ),
        );
      },
    );

    test(
      'graphics.newFont rejects whitespace-prefixed valid definitions like upstream',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/invalid.fnt': utf8.encode(
                _whitespacePrefixedValidBmFontDefinition,
              ),
            }),
          ),
        );
        expect(
          LoveFilesystemState.of(runtime).setSource(loveTestMountedSourceRoot),
          isTrue,
        );

        final imageData = await _call(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[4, 4, 'rgba8'],
        );

        await expectLater(
          () => _call(
            runtime,
            const ['love', 'graphics', 'newFont'],
            <Object?>['assets/fonts/invalid.fnt', imageData],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid BMFont file (no character definitions?)',
            ),
          ),
        );
      },
    );
  });
}

const String _notABmFontDefinition = 'this is not a bmfont definition';

const String _whitespacePrefixedValidBmFontDefinition = '''
 info face="Test" size=6 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1
 common lineHeight=6 base=5 scaleW=8 scaleH=6 pages=1 packed=0
 page id=0 file="page.png"
 chars count=1
 char id=65 x=0 y=0 width=1 height=1 xoffset=0 yoffset=0 xadvance=1 page=0 chnl=15
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
