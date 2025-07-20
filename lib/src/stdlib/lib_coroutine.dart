import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/value.dart';
import 'package:lualike/src/value_class.dart';
import 'package:lualike/src/logger.dart';

/// Initialize the coroutine library and add it to the global environment.
void initializeCoroutineLibrary(Interpreter interpreter) {
  final lib = ValueClass.table();

  lib[Value('create')] = Value((List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError.typeError(
        'bad argument #1 to "create" (function expected)',
      );
    }
    final func = args.first;
    if (func is! Value || !func.isCallable()) {
      throw LuaError.typeError(
        'bad argument #1 to "create" (function expected)',
      );
    }
    final env = interpreter.getCurrentEnv();
    Coroutine co;
    if (func.functionBody == null) {
      co = NativeCoroutine(func, env);
    } else {
      co = Coroutine(func, func.functionBody!, env);
    }
    interpreter.registerCoroutine(co);
    return Value(co);
  });

  lib[Value('resume')] = Value((List<Object?> args) async {
    if (args.isEmpty ||
        args.first is! Value ||
        (args.first as Value).raw is! Coroutine) {
      throw LuaError.typeError(
        'bad argument #1 to "resume" (coroutine expected)',
      );
    }
    final co = (args.first as Value).raw as Coroutine;
    final result = await co.resume(
      args.length > 1 ? args.sublist(1) : const [],
    );
    return result;
  });

  lib[Value('yield')] = Value((List<Object?> args) async {
    final co = interpreter.getCurrentCoroutine();
    Logger.info(
      'coroutine.yield called, current=${co.hashCode}',
      category: 'Coroutine',
    );
    if (co == null || co == interpreter.getMainThread()) {
      throw LuaError('attempt to yield from outside a coroutine');
    }
    final values = await co.yield_(args);
    if (values.isEmpty) return Value(null);
    if (values.length == 1) return values.first as Value;
    return Value.multi(values);
  });

  lib[Value('wrap')] = Value((List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError.typeError('bad argument #1 to "wrap" (function expected)');
    }
    final func = args.first;
    if (func is! Value || !func.isCallable() || func.functionBody == null) {
      throw LuaError.typeError('bad argument #1 to "wrap" (function expected)');
    }
    final env = interpreter.getCurrentEnv();
    final co = Coroutine(func, func.functionBody!, env);
    interpreter.registerCoroutine(co);
    return Value((List<Object?> wrapArgs) async {
      final result = await co.resume(wrapArgs);
      final vals = result.isMulti ? result.raw as List<Object?> : [result];
      final ok =
          vals.isNotEmpty &&
          vals.first is Value &&
          (vals.first as Value).raw == true;
      if (!ok) {
        final err = vals.length > 1 ? vals[1] : Value(null);
        throw LuaError(err is Value ? err.raw.toString() : err.toString());
      }
      final ret = vals.sublist(1);
      if (ret.isEmpty) return Value(null);
      if (ret.length == 1) return ret.first as Value;
      return Value.multi(ret);
    });
  });

  lib[Value('status')] = Value((List<Object?> args) async {
    if (args.isEmpty ||
        args.first is! Value ||
        (args.first as Value).raw is! Coroutine) {
      throw LuaError.typeError(
        'bad argument #1 to "status" (coroutine expected)',
      );
    }
    final co = (args.first as Value).raw as Coroutine;
    if (co == interpreter.getCurrentCoroutine() &&
        co.status == CoroutineStatus.suspended) {
      return Value('running');
    }
    switch (co.status) {
      case CoroutineStatus.running:
        return Value('running');
      case CoroutineStatus.suspended:
        return Value('suspended');
      case CoroutineStatus.normal:
        return Value('normal');
      case CoroutineStatus.dead:
        return Value('dead');
    }
  });

  lib[Value('running')] = Value((List<Object?> args) async {
    final current =
        interpreter.getCurrentCoroutine() ?? interpreter.getMainThread();
    final main = interpreter.getMainThread();
    return Value.multi([Value(current), Value(current == main)]);
  });

  lib[Value('isyieldable')] = Value((List<Object?> args) async {
    Coroutine co;
    if (args.isEmpty) {
      co = interpreter.getCurrentCoroutine() ?? interpreter.getMainThread();
    } else if (args.first is Value && (args.first as Value).raw is Coroutine) {
      co = (args.first as Value).raw as Coroutine;
    } else {
      throw LuaError.typeError(
        'bad argument #1 to "isyieldable" (coroutine expected)',
      );
    }
    final main = interpreter.getMainThread();
    return Value(co.isYieldable(main));
  });

  lib[Value('close')] = Value((List<Object?> args) async {
    if (args.isEmpty ||
        args.first is! Value ||
        (args.first as Value).raw is! Coroutine) {
      throw LuaError.typeError(
        'bad argument #1 to "close" (coroutine expected)',
      );
    }
    final co = (args.first as Value).raw as Coroutine;
    if (co.status == CoroutineStatus.running) {
      throw LuaError('cannot close a running coroutine');
    }
    final result = await co.close();
    return Value.multi(result);
  });

  interpreter.globals.define('coroutine', lib);
}
