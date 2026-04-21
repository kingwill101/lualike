import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.font layout parity', () {
    test('Font:getWidth follows LOVE newline and carriage-return rules', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );

      final widthA =
          (await _callMethod(font, 'getWidth', const <Object?>['A']) as num)
              .toDouble();
      final widthB =
          (await _callMethod(font, 'getWidth', const <Object?>['B']) as num)
              .toDouble();
      final widthAB =
          (await _callMethod(font, 'getWidth', const <Object?>['AB']) as num)
              .toDouble();
      final widthMultiLine =
          (await _callMethod(font, 'getWidth', const <Object?>['A\nB']) as num)
              .toDouble();
      final widthWithCarriageReturn =
          (await _callMethod(font, 'getWidth', const <Object?>['A\rB']) as num)
              .toDouble();

      final expectedMultiLineWidth = widthA > widthB ? widthA : widthB;

      expect(widthMultiLine, closeTo(expectedMultiLineWidth, 1e-9));
      expect(widthWithCarriageReturn, closeTo(widthAB, 1e-9));
    });

    test('Font:getWrap preserves trailing spaces in wrapped lines', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );

      final widthA =
          (await _callMethod(font, 'getWidth', const <Object?>['A']) as num)
              .toDouble();
      final widthB =
          (await _callMethod(font, 'getWidth', const <Object?>['B']) as num)
              .toDouble();
      final widthABWithSpace =
          (await _callMethod(font, 'getWidth', const <Object?>['A B']) as num)
              .toDouble();

      final wrapLimit = (widthA + widthABWithSpace) / 2.0;
      final wrapped = await _callMethod(
        font,
        'getWrap',
        <Object?>['A B', wrapLimit],
      ) as List<Object?>;

      final expectedWidth = widthA > widthB ? widthA : widthB;

      expect((wrapped[0] as num).toDouble(), closeTo(expectedWidth, 1e-9));
      expect(wrapped[1], <Object?, Object?>{1: 'A ', 2: 'B'});
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
