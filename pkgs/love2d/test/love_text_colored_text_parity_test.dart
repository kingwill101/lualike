import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics Text colored text parity', () {
    test('constructor and addf accept numeric text inputs', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );

      final numericText = await _call(
        runtime,
        const ['love', 'graphics', 'newText'],
        <Object?>[font, 12345],
      );
      final stringText = await _call(
        runtime,
        const ['love', 'graphics', 'newText'],
        <Object?>[font, '12345'],
      );

      expect(
        await _callMethod(numericText, 'getWidth'),
        await _callMethod(stringText, 'getWidth'),
      );

      final text = await _call(
        runtime,
        const ['love', 'graphics', 'newText'],
        <Object?>[font],
      );
      final numericIndex = await _callMethod(text, 'addf', const <Object?>[
        67890,
        100.0,
        'left',
      ]);
      final stringIndex = await _callMethod(text, 'addf', const <Object?>[
        '67890',
        100.0,
        'left',
      ]);

      expect(await _callMethod(text, 'getWidth', <Object?>[numericIndex]), 36.0);
      expect(
        await _callMethod(text, 'getWidth', <Object?>[numericIndex]),
        await _callMethod(text, 'getWidth', <Object?>[stringIndex]),
      );
    });

    test('constructor accepts numeric segments in colored text tables', () async {
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

      final colored = await _call(
        runtime,
        const ['love', 'graphics', 'newText'],
        <Object?>[font, coloredText],
      );
      final plain = await _call(
        runtime,
        const ['love', 'graphics', 'newText'],
        <Object?>[font, '1234'],
      );

      expect(
        await _callMethod(colored, 'getWidth'),
        await _callMethod(plain, 'getWidth'),
      );
    });

    test('constructor and methods validate partial color tables like LOVE', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );
      final text = await _call(
        runtime,
        const ['love', 'graphics', 'newText'],
        <Object?>[font, 'seed'],
      );

      final partialColorText = <Object?, Object?>{
        1: <Object?, Object?>{1: 1.0},
        2: 'A',
      };
      final invalidColorText = <Object?, Object?>{
        1: <Object?, Object?>{1: 'bad', 2: 'color', 3: 'table'},
        2: 'A',
      };

      await expectLater(
        () => _call(
          runtime,
          const ['love', 'graphics', 'newText'],
          <Object?>[font, partialColorText],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('color component at index 2'),
          ),
        ),
      );

      await expectLater(
        () => _callMethod(text, 'set', <Object?>[invalidColorText]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('numeric color component'),
          ),
        ),
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
