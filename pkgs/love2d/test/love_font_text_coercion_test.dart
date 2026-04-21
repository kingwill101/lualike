import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.font text coercion', () {
    test('Font:getWidth and Font:getWrap accept numeric text inputs', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );

      expect(
        await _callMethod(font, 'getWidth', const <Object?>[12345]),
        await _callMethod(font, 'getWidth', const <Object?>['12345']),
      );
      expect(
        await _callMethod(font, 'getWrap', const <Object?>[12345, 100.0]),
        await _callMethod(font, 'getWrap', const <Object?>['12345', 100.0]),
      );
    });

    test(
      'Font:getWrap accepts numeric segments in colored text tables',
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
          2: 12,
          3: 34,
        };

        expect(
          await _callMethod(font, 'getWrap', <Object?>[coloredText, 100.0]),
          await _callMethod(font, 'getWrap', const <Object?>['1234', 100.0]),
        );
      },
    );

    test(
      'Font:getWrap rejects invalid non-string entries in colored text tables',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        final invalidColoredText = <Object?, Object?>{
          1: <Object?, Object?>{1: 'bad', 2: 'color', 3: 'table'},
          2: 'A',
        };

        await expectLater(
          () => _callMethod(font, 'getWrap', <Object?>[
            invalidColoredText,
            100.0,
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('numeric color component'),
            ),
          ),
        );
      },
    );

    test('Font:getWrap validates partial color tables like LOVE', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );

      final partialColorText = <Object?, Object?>{
        1: <Object?, Object?>{1: 1.0},
        2: 'A',
      };

      await expectLater(
        () => _callMethod(font, 'getWrap', <Object?>[partialColorText, 100.0]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('color component at index 2'),
          ),
        ),
      );
    });

    test(
      'Font:getWrap keeps strict UTF-8 validation for LuaString table segments',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await _call(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        final malformed = LuaString.fromBytes(const <int>[0xc3, 0x28]);
        final coloredText = <Object?, Object?>{
          1: <Object?, Object?>{1: 1.0, 2: 1.0, 3: 1.0, 4: 1.0},
          2: malformed,
        };

        await expectLater(
          () => _callMethod(font, 'getWrap', <Object?>[coloredText, 100.0]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('UTF-8 decoding error at argument 2: Invalid UTF-8'),
          ),
        ),
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
