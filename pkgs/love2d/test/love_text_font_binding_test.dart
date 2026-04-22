import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics Text font bindings', () {
    test('newText uses the provided font and setFont replaces it', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final largeFont = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[20],
      );
      final text = await _call(
        runtime,
        const ['love', 'graphics', 'newText'],
        <Object?>[largeFont, 'Lua'],
      );

      final initialFont = await _callMethod(text, 'getFont');
      expect(await _callMethod(initialFont, 'getHeight'), 20.0);
      expect(await _callMethod(text, 'getWidth'), 36.0);

      final smallFont = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[10],
      );

      expect(await _callMethod(text, 'setFont', <Object?>[smallFont]), isNull);

      final currentFont = await _callMethod(text, 'getFont');
      expect(await _callMethod(currentFont, 'getHeight'), 10.0);
      expect(await _callMethod(text, 'getWidth'), 18.0);
    });

    test('Text font methods enforce Text and Font receivers', () async {
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
        <Object?>[font, 'Lua'],
      );

      expect(
        () => _rawMethod(text, 'getFont').call(const <Object?>['oops']),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'Text:getFont expected a Text at argument 1',
          ),
        ),
      );

      expect(
        () => _rawMethod(text, 'setFont').call(const <Object?>['oops', null]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'Text:setFont expected a Text at argument 1',
          ),
        ),
      );

      expect(
        () => _rawMethod(text, 'setFont').call(<Object?>[text, 'oops']),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'Text:setFont expected a Font at argument 2',
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
