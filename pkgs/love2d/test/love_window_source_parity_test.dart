import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('LOVE window source parity', () {
    test(
      'getNativeDPIScale mirrors the upstream source-backed API in main and thread runtimes',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(
            windowMetrics: const LoveWindowMetrics(dpiScale: 2.5),
          ),
        );

        expect(
          await _call(runtime, const ['love', 'window', 'getNativeDPIScale']),
          2.5,
        );
        expect(
          await _call(runtime, const ['love', 'window', 'getDPIScale']),
          2.5,
        );

        final output = await _call(runtime, const [
          'love',
          'thread',
          'newChannel',
        ]);
        final thread = await _call(
          runtime,
          const ['love', 'thread', 'newThread'],
          <Object?>[
            '''
local output = ...
output:push(love.window.getNativeDPIScale())
output:push(love.window.getDPIScale())
output:push(love.window.getNativeDPIScale() == love.window.getDPIScale())
''',
          ],
        );

        expect(await _callMethod(thread!, 'start', <Object?>[output]), isTrue);
        await _callMethod(thread, 'wait');
        expect(await _callMethod(thread, 'getError'), isNull);
        expect(await _callMethod(output!, 'pop'), 2.5);
        expect(await _callMethod(output, 'pop'), 2.5);
        expect(await _callMethod(output, 'pop'), isTrue);
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
