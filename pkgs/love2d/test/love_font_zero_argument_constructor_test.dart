import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.font zero-argument constructors', () {
    test('graphics.newFont() uses the LOVE default size 12 path', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final implicitFont = await _call(runtime, const [
        'love',
        'graphics',
        'newFont',
      ]);
      final explicitFont = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );

      expect(
        await _callMethod(implicitFont, 'getHeight'),
        await _callMethod(explicitFont, 'getHeight'),
      );
      expect(
        await _callMethod(implicitFont, 'getLineHeight'),
        await _callMethod(explicitFont, 'getLineHeight'),
      );
      expect(
        await _callMethod(implicitFont, 'getWidth', const <Object?>['AV']),
        await _callMethod(explicitFont, 'getWidth', const <Object?>['AV']),
      );
    });

    test('graphics.setNewFont() uses the LOVE default size 12 path', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final implicitFont = await _call(runtime, const [
        'love',
        'graphics',
        'setNewFont',
      ]);
      final current = await _call(runtime, const [
        'love',
        'graphics',
        'getFont',
      ]);
      final explicitFont = await _call(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );

      expect(
        await _callMethod(implicitFont, 'getHeight'),
        await _callMethod(explicitFont, 'getHeight'),
      );
      expect(
        await _callMethod(current, 'getHeight'),
        await _callMethod(explicitFont, 'getHeight'),
      );
      expect(
        await _callMethod(current, 'getWidth', const <Object?>['LuaLike']),
        await _callMethod(explicitFont, 'getWidth', const <Object?>['LuaLike']),
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
