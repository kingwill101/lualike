import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('LOVE audio source parity', () {
    test(
      'getSourceCount and Source:getChannels mirror upstream deprecated aliases',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final soundData = await _call(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[4, 22050, 16, 2],
        );
        final source = await _call(
          runtime,
          const ['love', 'audio', 'newSource'],
          <Object?>[soundData, 'stream'],
        );

        expect(await _callMethod(source!, 'getChannels'), 2);
        expect(await _callMethod(source, 'getChannelCount'), 2);

        expect(
          await _call(runtime, const ['love', 'audio', 'getSourceCount']),
          0,
        );
        expect(
          await _call(runtime, const ['love', 'audio', 'getActiveSourceCount']),
          0,
        );

        expect(await _callMethod(source, 'play'), isTrue);
        expect(
          await _call(runtime, const ['love', 'audio', 'getSourceCount']),
          1,
        );
        expect(
          await _call(runtime, const ['love', 'audio', 'getActiveSourceCount']),
          1,
        );

        await _call(runtime, const ['love', 'audio', 'pause']);
        expect(
          await _call(runtime, const ['love', 'audio', 'getSourceCount']),
          0,
        );
        expect(
          await _call(runtime, const ['love', 'audio', 'getActiveSourceCount']),
          0,
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
  Object receiver,
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

BuiltinFunction _rawMethod(Object receiver, String method) {
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
  if (resolved is List<Object?>) {
    return resolved.map(_unwrap).toList(growable: false);
  }
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(
      wrapped.raw as List<Object?>,
      growable: false,
    ).map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
