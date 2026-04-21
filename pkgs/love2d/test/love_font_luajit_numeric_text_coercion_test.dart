import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.font LuaJIT numeric text coercion parity', () {
    test('Font:getWidth and Font:getWrap stringify 1.0 like LuaJIT', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );
      final singleWidth =
          await _callMethod(font, 'getWidth', const <Object?>['1']) as num;

      expect(
        await _callMethod(font, 'getWidth', const <Object?>[1.0]),
        await _callMethod(font, 'getWidth', const <Object?>['1']),
      );
      expect(
        await _callMethod(font, 'getWidth', const <Object?>['1.0']),
        greaterThan(singleWidth),
      );

      expect(
        await _callMethod(font, 'getWrap', <Object?>[1.0, singleWidth]),
        await _callMethod(font, 'getWrap', <Object?>['1', singleWidth]),
      );
      expect(
        await _callMethod(font, 'getWrap', <Object?>['1.0', singleWidth]),
        isNot(
          await _callMethod(font, 'getWrap', <Object?>['1', singleWidth]),
        ),
      );
    });

    test(
      'Font:getWidth and Font:getWrap preserve LuaJIT formatting for -0.0 and 1000.0',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        final negativeZeroWidth =
            await _callMethod(font, 'getWidth', const <Object?>['-0']) as num;
        final integerThousandWidth =
            await _callMethod(font, 'getWidth', const <Object?>['1000']) as num;

        expect(
          await _callMethod(font, 'getWidth', const <Object?>[-0.0]),
          await _callMethod(font, 'getWidth', const <Object?>['-0']),
        );
        expect(
          await _callMethod(font, 'getWidth', const <Object?>['-0.0']),
          greaterThan(negativeZeroWidth),
        );

        expect(
          await _callMethod(font, 'getWrap', <Object?>[-0.0, negativeZeroWidth]),
          await _callMethod(font, 'getWrap', <Object?>['-0', negativeZeroWidth]),
        );
        expect(
          await _callMethod(font, 'getWrap', <Object?>['-0.0', negativeZeroWidth]),
          isNot(
            await _callMethod(
              font,
              'getWrap',
              <Object?>['-0', negativeZeroWidth],
            ),
          ),
        );

        expect(
          await _callMethod(font, 'getWidth', const <Object?>[1000.0]),
          await _callMethod(font, 'getWidth', const <Object?>['1000']),
        );
        expect(
          await _callMethod(font, 'getWidth', const <Object?>['1000.0']),
          greaterThan(integerThousandWidth),
        );

        expect(
          await _callMethod(
            font,
            'getWrap',
            <Object?>[1000.0, integerThousandWidth],
          ),
          await _callMethod(
            font,
            'getWrap',
            <Object?>['1000', integerThousandWidth],
          ),
        );
        expect(
          await _callMethod(
            font,
            'getWrap',
            <Object?>['1000.0', integerThousandWidth],
          ),
          isNot(
            await _callMethod(
              font,
              'getWrap',
              <Object?>['1000', integerThousandWidth],
            ),
          ),
        );
      },
    );

    test(
      'Font:getWrap colored text numeric segments stringify 1.0 like LuaJIT',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        final coloredText = <Object?, Object?>{
          1: <Object?, Object?>{1: 1.0, 2: 0.25, 3: 0.5, 4: 1.0},
          2: 1.0,
        };

        expect(
          await _callMethod(font, 'getWrap', <Object?>[coloredText, 100.0]),
          await _callMethod(font, 'getWrap', const <Object?>['1', 100.0]),
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
