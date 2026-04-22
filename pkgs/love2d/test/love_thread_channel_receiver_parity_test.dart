import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.thread Channel receiver parity', () {
    test(
      'Channel type metadata survives release while other methods fail',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final channel = await _call(runtime, const [
          'love',
          'thread',
          'newChannel',
        ]);

        final typeMethod = _rawMethod(channel, 'type');
        final typeOfMethod = _rawMethod(channel, 'typeOf');

        expect(
          await _resolveCallResult(typeMethod.call(<Object?>[channel])),
          'Channel',
        );
        expect(
          await _resolveCallResult(
            typeOfMethod.call(<Object?>[channel, 'Object']),
          ),
          isTrue,
        );

        await expectLater(
          () => _resolveCallResult(typeMethod.call(const <Object?>[])),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' (Channel expected, got nil)",
            ),
          ),
        );

        await expectLater(
          () => _resolveCallResult(typeMethod.call(const <Object?>['oops'])),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' (Channel expected, got string)",
            ),
          ),
        );

        await expectLater(
          () => _resolveCallResult(
            typeOfMethod.call(const <Object?>['oops', 'Object']),
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'typeOf' (Channel expected, got string)",
            ),
          ),
        );

        expect(await _callMethod(channel, 'release'), isTrue);
        expect(await _callMethod(channel, 'release'), isFalse);

        await expectLater(
          () => _callMethod(channel, 'getCount'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );

        expect(await _callMethod(channel, 'type'), 'Channel');
        expect(
          await _callMethod(channel, 'typeOf', const <Object?>['Object']),
          isTrue,
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
