import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

typedef LuaTestValueUnwrapper = Object? Function(Object? value);

Future<Object?> luaCall(
  Object runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return luaResolveCallResult(luaRawFunction(runtime, path).call(args));
}

Future<Object?> luaCallList(
  Object runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return luaResolveCallResultList(luaRawFunction(runtime, path).call(args));
}

Future<Object?> luaCallRaw(
  Object runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return luaResolveCallResultRaw(luaRawFunction(runtime, path).call(args));
}

Future<Object?> luaCallRawList(
  Object runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return luaResolveCallResultRawList(luaRawFunction(runtime, path).call(args));
}

Future<Object?> luaExecute(LuaLike lua, String code, {String? scriptPath}) {
  return luaResolveCallResult(lua.execute(code, scriptPath: scriptPath));
}

Future<Object?> luaExecuteList(LuaLike lua, String code, {String? scriptPath}) {
  return luaResolveCallResultList(lua.execute(code, scriptPath: scriptPath));
}

Future<Object?> luaCallCallable(
  BuiltinFunction function, [
  List<Object?> args = const <Object?>[],
]) async {
  return luaResolveCallResult(function.call(args));
}

Future<Object?> luaCallMethod(
  Object? receiver,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  return luaResolveCallResult(
    luaRawMethod(receiver, method).call(<Object?>[receiver, ...args]),
  );
}

Future<Object?> luaCallMethodList(
  Object? receiver,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  return luaResolveCallResultList(
    luaRawMethod(receiver, method).call(<Object?>[receiver, ...args]),
  );
}

Future<Object?> luaCallMethodRaw(
  Object? receiver,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  return luaResolveCallResultRaw(
    luaRawMethod(receiver, method).call(<Object?>[receiver, ...args]),
  );
}

Future<Object?> luaCallMethodRawList(
  Object? receiver,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  return luaResolveCallResultRawList(
    luaRawMethod(receiver, method).call(<Object?>[receiver, ...args]),
  );
}

BuiltinFunction luaRawFunction(Object runtime, List<String> path) {
  var current = _luaRuntime(runtime).getCurrentEnv().get(path.first);
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

BuiltinFunction luaRawMethod(Object? receiver, String method) {
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

Future<Object?> luaResolveRawCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(wrapped.raw as List<Object?>, growable: false);
  }
  return resolved;
}

Future<Object?> luaResolveCallResult(Object? result) {
  return _luaResolveCallResult(result, unwrapValue: luaUnwrapValue);
}

Future<Object?> luaResolveCallResultList(Object? result) {
  return _luaResolveCallResult(
    result,
    unwrapValue: luaUnwrapValue,
    unwrapPlainListResults: true,
  );
}

Future<Object?> luaResolveCallResultRaw(Object? result) {
  return _luaResolveCallResult(result, unwrapValue: luaUnwrapRawValue);
}

Future<Object?> luaResolveCallResultRawList(Object? result) {
  return _luaResolveCallResult(
    result,
    unwrapValue: luaUnwrapRawValue,
    unwrapPlainListResults: true,
  );
}

Object? luaUnwrapValue(Object? value) =>
    value is Value ? value.unwrap() : value;

Object? luaUnwrapRawValue(Object? value) => value is Value ? value.raw : value;

LuaRuntime _luaRuntime(Object runtime) {
  return switch (runtime) {
    final LoveScriptRuntime scriptRuntime => scriptRuntime.runtime,
    final LuaRuntime luaRuntime => luaRuntime,
    _ => throw ArgumentError.value(
      runtime,
      'runtime',
      'Expected a LoveScriptRuntime or LuaRuntime',
    ),
  };
}

Future<Object?> _luaResolveCallResult(
  Object? result, {
  required LuaTestValueUnwrapper unwrapValue,
  bool unwrapPlainListResults = false,
}) async {
  final resolved = result is Future<Object?> ? await result : result;
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(
      wrapped.raw as List<Object?>,
      growable: false,
    ).map(unwrapValue).toList(growable: false);
  }
  if (unwrapPlainListResults && resolved is List<Object?>) {
    return List<Object?>.from(resolved.map(unwrapValue), growable: false);
  }
  return unwrapValue(resolved);
}

class TestLoveClock implements LoveClock {
  TestLoveClock({required double nowSeconds}) : _nowSeconds = nowSeconds;

  double _nowSeconds;

  set currentTime(double value) => _nowSeconds = value;

  @override
  double nowSeconds() => _nowSeconds;

  final List<double> sleeps = <double>[];

  @override
  Future<void> sleepSeconds(double seconds) async {
    sleeps.add(seconds);
  }
}
