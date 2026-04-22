import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics text alignment parity', () {
    test('printf treats nil alignment like an omitted left alignment', () async {
      final host = LoveHeadlessHost();
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: host);

      final font = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );

      host.graphics.beginFrame();
      expect(
        await _call(
          runtime,
          const ['love', 'graphics', 'printf'],
          <Object?>['Lua', font, 4.0, 8.0, 96.0, null],
        ),
        isNull,
      );

      expect(host.graphics.commands, hasLength(1));
      final command = host.graphics.commands.single as LoveTextCommand;
      expect(command.text, 'Lua');
      expect(command.limit, 96.0);
      expect(command.align, 'left');
    });

    test('printf and Text formatted methods use LOVE alignment error text',
        () async {
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

      await expectLater(
        () => _call(
          runtime,
          const ['love', 'graphics', 'printf'],
          <Object?>['Lua', font, 0.0, 0.0, 96.0, 'bogus'],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            "Invalid alignment 'bogus', expected one of: "
                "'left', 'right', 'center', 'justify'",
          ),
        ),
      );

      await expectLater(
        () => _callMethod(text, 'addf', <Object?>['Lua', 96.0, 'bogus']),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            "Invalid align mode 'bogus', expected one of: "
                "'left', 'right', 'center', 'justify'",
          ),
        ),
      );

      await expectLater(
        () => _callMethod(text, 'setf', <Object?>['Lua', 96.0, 'bogus']),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            "Invalid align mode 'bogus', expected one of: "
                "'left', 'right', 'center', 'justify'",
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
