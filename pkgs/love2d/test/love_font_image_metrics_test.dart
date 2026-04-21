import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.font image metrics parity', () {
    test('graphics.newImageFont preserves LOVE image font metrics', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final imageData = await _call(
        runtime,
        const ['love', 'image', 'newImageData'],
        <Object?>[9, 6, 'rgba8', _imageFontStripBytes()],
      );
      final font = await _call(
        runtime,
        const ['love', 'graphics', 'newImageFont'],
        <Object?>[imageData, 'ABC', 1],
      );

      expect(await _callMethod(font, 'getHeight'), 6.0);
      expect(await _callMethod(font, 'getAscent'), 6.0);
      expect(await _callMethod(font, 'getDescent'), 0.0);
      expect(await _callMethod(font, 'getBaseline'), 6.0);
    });

    test(
      'rasterizer-backed image fonts preserve dpi-scaled LOVE metrics',
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
          <Object?>[imageData, 'ABC', 1, 2.0],
        );
        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer],
        );

        expect(await _callMethod(font, 'getDPIScale'), 2.0);
        expect(await _callMethod(font, 'getHeight'), 3.0);
        expect(await _callMethod(font, 'getAscent'), 3.0);
        expect(await _callMethod(font, 'getDescent'), 0.0);
        expect(await _callMethod(font, 'getBaseline'), 3.0);
      },
    );
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
  fillColumns(4, 5, const <int>[255, 255, 255, 255]);
  fillColumns(5, 6, const <int>[255, 0, 255, 255]);
  fillColumns(6, 8, const <int>[255, 255, 255, 255]);
  fillColumns(8, 9, const <int>[255, 0, 255, 255]);

  return bytes;
}
