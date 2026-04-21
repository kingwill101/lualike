import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.data bindings', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime);
    });

    test(
      'newByteData supports size, string, and data slicing inputs',
      () async {
        final empty = await _call(
          runtime,
          const ['love', 'data', 'newByteData'],
          const <Object?>[4],
        );
        expect(await _callMethod(empty, 'type'), 'ByteData');
        expect(
          await _callMethod(empty, 'typeOf', const <Object?>['Data']),
          isTrue,
        );
        expect(await _callMethod(empty, 'getSize'), 4);

        final source = await _call(
          runtime,
          const ['love', 'data', 'newByteData'],
          const <Object?>['hello world'],
        );
        expect(await _callMethod(source, 'getString'), 'hello world');

        final slice = await _call(
          runtime,
          const ['love', 'data', 'newByteData'],
          <Object?>[source, 6, 5],
        );
        expect(await _callMethod(slice, 'getString'), 'world');

        final tail = await _call(
          runtime,
          const ['love', 'data', 'newByteData'],
          <Object?>[source, 6],
        );
        expect(await _callMethod(tail, 'getString'), 'world');
      },
    );

    test(
      'newDataView slices existing data and clone preserves view type',
      () async {
        final source = await _call(
          runtime,
          const ['love', 'data', 'newByteData'],
          const <Object?>['abcdef'],
        );

        final view = await _call(
          runtime,
          const ['love', 'data', 'newDataView'],
          <Object?>[source, 1, 3],
        );
        expect(await _callMethod(view, 'type'), 'DataView');
        expect(
          await _callMethod(view, 'typeOf', const <Object?>['Data']),
          isTrue,
        );
        expect(await _callMethod(view, 'getString'), 'bcd');

        final clone = await _callMethod(view, 'clone');
        expect(await _callMethod(clone, 'type'), 'DataView');
        expect(await _callMethod(clone, 'getString'), 'bcd');
      },
    );

    test(
      'encode, decode, and hash support string and data containers',
      () async {
        final fileData = await _call(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          const <Object?>['binary payload', 'payload.bin'],
        );

        final copiedFromFileData = await _call(
          runtime,
          const ['love', 'data', 'newByteData'],
          <Object?>[fileData, 7, 7],
        );
        expect(await _callMethod(copiedFromFileData, 'getString'), 'payload');

        expect(
          await _call(
            runtime,
            const ['love', 'data', 'encode'],
            <Object?>['string', 'hex', fileData],
          ),
          '62696e617279207061796c6f6164',
        );

        expect(
          await _call(
            runtime,
            const ['love', 'data', 'encode'],
            const <Object?>['string', 'hex', 'Hi'],
          ),
          '4869',
        );

        final decoded = await _call(
          runtime,
          const ['love', 'data', 'decode'],
          const <Object?>['data', 'hex', '48656c6c6f'],
        );
        expect(await _callMethod(decoded, 'type'), 'ByteData');
        expect(await _callMethod(decoded, 'getString'), 'Hello');

        expect(
          await _call(
            runtime,
            const ['love', 'data', 'encode'],
            const <Object?>['string', 'base64', 'hello', 4],
          ),
          'aGVs\nbG8=',
        );
        expect(
          await _call(
            runtime,
            const ['love', 'data', 'decode'],
            const <Object?>['string', 'base64', 'aGVs\nbG8='],
          ),
          'hello',
        );

        final digest = await _callRaw(
          runtime,
          const ['love', 'data', 'hash'],
          const <Object?>['sha256', 'abc'],
        );
        expect(
          await _call(
            runtime,
            const ['love', 'data', 'encode'],
            <Object?>['string', 'hex', digest],
          ),
          'ba7816bf8f01cfea414140de5dae2223'
          'b00361a396177a9cb410ff61f20015ad',
        );
      },
    );

    test('compress and decompress roundtrip zlib, gzip, and deflate', () async {
      final compressed = await _call(
        runtime,
        const ['love', 'data', 'compress'],
        const <Object?>['data', 'zlib', 'hello hello hello'],
      );
      expect(await _callMethod(compressed, 'type'), 'CompressedData');
      expect(await _callMethod(compressed, 'getFormat'), 'zlib');
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
        'hello hello hello',
      );

      final source = await _call(
        runtime,
        const ['love', 'data', 'newByteData'],
        const <Object?>['payload'],
      );
      final gzipBytes = await _callRaw(
        runtime,
        const ['love', 'data', 'compress'],
        <Object?>['string', 'gzip', source],
      );
      expect(
        await _call(
          runtime,
          const ['love', 'data', 'decompress'],
          <Object?>['string', 'gzip', gzipBytes],
        ),
        'payload',
      );

      final deflated = await _callRaw(
        runtime,
        const ['love', 'data', 'compress'],
        const <Object?>['string', 'deflate', 'raw bytes'],
      );
      final inflated = await _call(
        runtime,
        const ['love', 'data', 'decompress'],
        <Object?>['data', 'deflate', deflated],
      );
      expect(await _callMethod(inflated, 'getString'), 'raw bytes');
    });

    test(
      'pack, unpack, and getPackedSize delegate to Lua string packing',
      () async {
        expect(
          await _call(
            runtime,
            const ['love', 'data', 'getPackedSize'],
            const <Object?>['<I4'],
          ),
          4,
        );

        final packed = await _call(
          runtime,
          const ['love', 'data', 'pack'],
          const <Object?>['data', '<I4', 0x12345678],
        );
        expect(await _callMethod(packed, 'type'), 'ByteData');
        expect(
          await _call(
            runtime,
            const ['love', 'data', 'encode'],
            <Object?>['string', 'hex', packed],
          ),
          '78563412',
        );

        expect(
          await _call(
            runtime,
            const ['love', 'data', 'unpack'],
            <Object?>['<I4', packed],
          ),
          <Object?>[0x12345678, 5],
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
