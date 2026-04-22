import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/font_test_support.dart';
import 'test_support/memory_filesystem_test_support.dart';

void main() {
  group('love.font File overloads', () {
    test(
      'auto-detected true type constructors accept mounted File objects',
      () async {
        final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/Body.ttf': veraBytes,
            }),
          ),
        );
        expect(
          LoveFilesystemState.of(runtime).setSource(loveTestMountedSourceRoot),
          isTrue,
        );

        final rasterizerFile = await _call(
          runtime,
          const ['love', 'filesystem', 'newFile'],
          const <Object?>['assets/fonts/Body.ttf'],
        );
        final fontFile = await _call(
          runtime,
          const ['love', 'filesystem', 'newFile'],
          const <Object?>['assets/fonts/Body.ttf'],
        );

        final rasterizer = await _call(
          runtime,
          const ['love', 'font', 'newRasterizer'],
          <Object?>[rasterizerFile],
        );
        final baselineRasterizer = await _call(
          runtime,
          const ['love', 'font', 'newRasterizer'],
          const <Object?>['assets/fonts/Body.ttf'],
        );
        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[fontFile],
        );
        final baselineFont = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>['assets/fonts/Body.ttf'],
        );

        expect(
          await _callMethod(rasterizer, 'getHeight'),
          await _callMethod(baselineRasterizer, 'getHeight'),
        );
        expect(
          await _callMethod(rasterizer, 'getGlyphCount'),
          await _callMethod(baselineRasterizer, 'getGlyphCount'),
        );
        expect(
          await _callMethod(font, 'getHeight'),
          await _callMethod(baselineFont, 'getHeight'),
        );
        expect(
          await _callMethod(font, 'getWidth', const <Object?>['LuaLike']),
          await _callMethod(baselineFont, 'getWidth', const <Object?>[
            'LuaLike',
          ]),
        );
      },
    );

    test('true type constructors accept mounted File objects', () async {
      final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
      final runtime = Interpreter();
      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(),
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'assets/fonts/Body.ttf': veraBytes,
          }),
        ),
      );
      expect(
        LoveFilesystemState.of(runtime).setSource(loveTestMountedSourceRoot),
        isTrue,
      );

      final rasterizerFile = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['assets/fonts/Body.ttf'],
      );
      final fontFile = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['assets/fonts/Body.ttf'],
      );

      final rasterizer = await _call(
        runtime,
        const ['love', 'font', 'newTrueTypeRasterizer'],
        <Object?>[rasterizerFile, 16, 'mono', 2.0],
      );
      final baselineRasterizer = await _call(
        runtime,
        const ['love', 'font', 'newTrueTypeRasterizer'],
        const <Object?>['assets/fonts/Body.ttf', 16, 'mono', 2.0],
      );
      final font = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        <Object?>[fontFile, 16, 'mono', 2.0],
      );
      final baselineFont = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>['assets/fonts/Body.ttf', 16, 'mono', 2.0],
      );

      expect(
        await _callMethod(rasterizer, 'getHeight'),
        await _callMethod(baselineRasterizer, 'getHeight'),
      );
      expect(
        await _callMethod(rasterizer, 'getGlyphCount'),
        await _callMethod(baselineRasterizer, 'getGlyphCount'),
      );
      expect(
        await _callMethod(font, 'getDPIScale'),
        await _callMethod(baselineFont, 'getDPIScale'),
      );
      expect(
        await _callMethod(font, 'getHeight'),
        await _callMethod(baselineFont, 'getHeight'),
      );
      expect(
        await _callMethod(font, 'getWidth', const <Object?>['W']),
        await _callMethod(baselineFont, 'getWidth', const <Object?>['W']),
      );
    });

    test('image font constructors accept mounted File objects', () async {
      final runtime = Interpreter();
      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(),
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'assets/fonts/imagefont.png': LoveImageData.fromRgbaBytes(
              width: 9,
              height: 6,
              bytes: _imageFontStripBytes(),
            ).encode('png'),
          }),
        ),
      );
      expect(
        LoveFilesystemState.of(runtime).setSource(loveTestMountedSourceRoot),
        isTrue,
      );

      final rasterizerFile = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['assets/fonts/imagefont.png'],
      );
      final fontFile = await _call(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['assets/fonts/imagefont.png'],
      );

      final rasterizer = await _call(
        runtime,
        const ['love', 'font', 'newImageRasterizer'],
        <Object?>[rasterizerFile, 'ABC', 1, 1.0],
      );
      final font = await _call(
        runtime,
        const ['love', 'graphics', 'newImageFont'],
        <Object?>[fontFile, 'ABC', 1],
      );
      final baselineFont = await _call(
        runtime,
        const ['love', 'graphics', 'newImageFont'],
        const <Object?>['assets/fonts/imagefont.png', 'ABC', 1],
      );

      expect(await _callMethod(rasterizer, 'getGlyphCount'), 3);
      expect(await _callMethod(rasterizer, 'getAdvance'), 4);
      expect(await _callMethod(rasterizer, 'getHeight'), 6);
      expect(
        await _callMethod(font, 'getDPIScale'),
        await _callMethod(baselineFont, 'getDPIScale'),
      );
      expect(
        await _callMethod(font, 'getWidth', const <Object?>['AB']),
        await _callMethod(baselineFont, 'getWidth', const <Object?>['AB']),
      );
    });
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
  Object? target,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  final table = _unwrap(target);
  expect(table, isA<Map>());
  final entry = (table as Map<Object?, Object?>)[method];
  final function = switch (entry) {
    final Value wrapped when wrapped.raw is BuiltinFunction =>
      wrapped.raw as BuiltinFunction,
    final BuiltinFunction callable => callable,
    _ => throw TestFailure('Expected $method to be a callable Lua method'),
  };
  return _resolveCallResult(function.call(<Object?>[target, ...args]));
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
