import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  test('filesystem FileData clone preserves LOVE filedata semantics', () async {
    final runtime = LoveScriptRuntime();
    final interpreter = runtime.runtime as Interpreter;

    final original =
        await _callRawPath(
              interpreter,
              const ['love', 'filesystem', 'newFileData'],
              const <Object?>['payload', 'payload.txt'],
            )
            as Value;

    final clone = await _callMethodRaw(original, 'clone') as Value;

    expect(clone, isNot(same(original)));
    expect(await _callMethod(clone, 'type'), 'FileData');
    expect(
      await _callMethod(clone, 'typeOf', const <Object?>['FileData']),
      isTrue,
    );
    expect(await _callMethod(clone, 'typeOf', const <Object?>['Data']), isTrue);
    expect(await _callMethod(clone, 'getFilename'), 'payload.txt');
    expect(await _callMethod(clone, 'getExtension'), 'txt');
    expect(await _callMethod(clone, 'getSize'), 7);
    expect(await _callMethod(clone, 'getString'), 'payload');
    expect(await _callMethod(original, 'getString'), 'payload');
  });
}

Future<Object?> _callRawPath(
  Interpreter runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  var current = runtime.getCurrentEnv().get(path.first);
  for (final segment in path.skip(1)) {
    final table = current is Value ? current.raw : current;
    expect(table, isA<Map>());
    current = (table! as Map<dynamic, dynamic>)[segment];
  }

  expect(current, isA<Value>());
  final callable = (current! as Value).raw;
  expect(callable, isA<BuiltinFunction>());
  final result = (callable! as BuiltinFunction).call(_wrapArgs(args));
  return _resolveRaw(result);
}

Future<Object?> _callMethod(
  Value object,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolve(await _callMethodRaw(object, method, args));
}

Future<Object?> _callMethodRaw(
  Value object,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  final table = object.raw as Map<dynamic, dynamic>;
  final entry = table[method];
  expect(entry, isA<Value>());
  final callable = (entry! as Value).raw;
  expect(callable, isA<BuiltinFunction>());
  final result = (callable! as BuiltinFunction).call(<Object?>[
    object,
    ..._wrapArgs(args),
  ]);
  return _resolveRaw(result);
}

List<Object?> _wrapArgs(List<Object?> args) {
  return args
      .map<Object?>((arg) => arg is Value ? arg : Value(arg))
      .toList(growable: false);
}

Future<Object?> _resolveRaw(Object? result) async {
  return result is Future<Object?> ? await result : result;
}

Object? _resolve(Object? resolved) {
  if (resolved case final Value value when value.isMulti) {
    final values = (value.raw as List<Object?>)
        .map<Object?>((entry) => entry is Value ? entry.unwrap() : entry)
        .toList(growable: false);
    return values.isNotEmpty ? values.first : null;
  }
  return resolved is Value ? resolved.unwrap() : resolved;
}
