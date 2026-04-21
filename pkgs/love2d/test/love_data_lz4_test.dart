import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.data lz4 bindings', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime);
    });

    test(
      'compresses to LOVE-style LZ4 blocks and roundtrips through object and string containers',
      () async {
        final compressed = await _call(
          runtime,
          const ['love', 'data', 'compress'],
          const <Object?>['data', 'lz4', 'hello'],
        );
        expect(await _callMethod(compressed, 'type'), 'CompressedData');
        expect(await _callMethod(compressed, 'getFormat'), 'lz4');
        expect(
          await _callMethod(compressed, 'typeOf', const <Object?>['Data']),
          isTrue,
        );
        expect(
          await _call(
            runtime,
            const ['love', 'data', 'decompress'],
            <Object?>['string', compressed],
          ),
          'hello',
        );

        final rawCompressed = await _callRaw(
          runtime,
          const ['love', 'data', 'compress'],
          const <Object?>['string', 'lz4', 'hello'],
        );
        expect(
          await _call(
            runtime,
            const ['love', 'data', 'encode'],
            <Object?>['string', 'hex', rawCompressed],
          ),
          '050000005068656c6c6f',
        );
      },
    );

    test('encodes extended literal lengths in LOVE LZ4 output', () async {
      const payload = 'abcdefghijklmnopqrst';
      final rawCompressed = await _callRaw(
        runtime,
        const ['love', 'data', 'compress'],
        const <Object?>['string', 'lz4', payload],
      );
      expect(
        await _call(
          runtime,
          const ['love', 'data', 'encode'],
          <Object?>['string', 'hex', rawCompressed],
        ),
        '14000000f0056162636465666768696a6b6c6d6e6f7071727374',
      );
      expect(
        await _call(
          runtime,
          const ['love', 'data', 'decompress'],
          <Object?>['string', 'lz4', rawCompressed],
        ),
        payload,
      );
    });

    test('decompresses LOVE-style LZ4 match sequences from raw bytes', () async {
      final encoded = await _call(
        runtime,
        const ['love', 'data', 'decode'],
        const <Object?>['data', 'hex', '0a000000326162630300107a'],
      );
      expect(
        await _call(
          runtime,
          const ['love', 'data', 'decompress'],
          <Object?>['string', 'lz4', encoded],
        ),
        'abcabcabcz',
      );
    });

    test('reports invalid lz4 payloads as Lua errors', () async {
      final invalid = await _call(
        runtime,
        const ['love', 'data', 'decode'],
        const <Object?>['data', 'hex', '04000000000000'],
      );
      expect(
        _call(
          runtime,
          const ['love', 'data', 'decompress'],
          <Object?>['string', 'lz4', invalid],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Could not decompress LZ4-compressed data.'),
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

Future<Object?> _callRaw(
  Interpreter runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveRawCallResult(_rawFunction(runtime, path).call(args));
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
  final resolved = await _resolveRawCallResult(result);
  if (resolved is List<Object?>) {
    return resolved.map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Future<Object?> _resolveRawCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(wrapped.raw as List<Object?>, growable: false);
  }
  return resolved;
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
