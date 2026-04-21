import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.font rasterizer constructor parity', () {
    test(
      'graphics.newFont ignores extra arguments when given a Rasterizer',
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
          <Object?>[imageData, 'ABC', 0, 2.0],
        );
        final baselineFont = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer],
        );

        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer, 99, 'ignored', 8.0],
        );

        expect(
          await _callMethod(font, 'getDPIScale'),
          await _callMethod(baselineFont, 'getDPIScale'),
        );
        expect(
          await _callMethod(font, 'getWidth', const <Object?>['ABC']),
          await _callMethod(baselineFont, 'getWidth', const <Object?>['ABC']),
        );
      },
    );

    test(
      'graphics.setNewFont ignores extra arguments when given a Rasterizer',
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
          <Object?>[imageData, 'ABC', 0, 2.0],
        );
        final baselineFont = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          <Object?>[rasterizer],
        );

        final font = await _call(
          runtime,
          const ['love', 'graphics', 'setNewFont'],
          <Object?>[rasterizer, 99, 'ignored', 8.0],
        );
        final current = await _call(runtime, const [
          'love',
          'graphics',
          'getFont',
        ]);

        expect(
          await _callMethod(font, 'getDPIScale'),
          await _callMethod(baselineFont, 'getDPIScale'),
        );
        expect(
          await _callMethod(font, 'getWidth', const <Object?>['ABC']),
          await _callMethod(baselineFont, 'getWidth', const <Object?>['ABC']),
        );
        expect(
          await _callMethod(current, 'getDPIScale'),
          await _callMethod(baselineFont, 'getDPIScale'),
        );
        expect(
          await _callMethod(current, 'getWidth', const <Object?>['ABC']),
          await _callMethod(baselineFont, 'getWidth', const <Object?>['ABC']),
        );
      },
    );

    test(
      'graphics.newImageFont ignores extra arguments when given a Rasterizer',
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
          <Object?>[imageData, 'ABC', 0, 2.0],
        );
        final baselineFont = await _call(
          runtime,
          const ['love', 'graphics', 'newImageFont'],
          <Object?>[rasterizer],
        );

        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newImageFont'],
          <Object?>[rasterizer, 'ignored', 99],
        );

        expect(
          await _callMethod(font, 'getDPIScale'),
          await _callMethod(baselineFont, 'getDPIScale'),
        );
        expect(
          await _callMethod(font, 'getWidth', const <Object?>['ABC']),
          await _callMethod(baselineFont, 'getWidth', const <Object?>['ABC']),
        );
      },
    );
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
