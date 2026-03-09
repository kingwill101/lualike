import 'package:lualike/lualike.dart';

import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/gc/memory_credits.dart';
import 'package:lualike/src/io/lua_file.dart';
import 'package:lualike/src/lua_bytecode/vm.dart';
import 'package:lualike/src/stdlib/lib_io.dart';
import 'package:lualike/src/stdlib/metatables.dart';
import 'package:lualike/src/upvalue.dart';
import 'package:lualike/src/utils/type.dart' show getLuaType;
import 'library.dart';

class DebugLib {
  static Map<String, BuiltinFunction> functions = {};
}

/// Debug library implementation using the new Library system
class DebugLibrary extends Library {
  @override
  String get name => "debug";

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    // Register all debug functions individually
    context.define("debug", _DebugInteractive());
    context.define("gethook", _GetHook(interpreter));
    context.define("getinfo", _GetInfoImpl(interpreter!));
    context.define("getlocal", _GetLocal(interpreter!));
    context.define("getmetatable", _GetMetatable());
    context.define("getregistry", _GetRegistry());
    context.define("getupvalue", _GetUpvalue(interpreter!));
    context.define("getuservalue", _GetUserValue());
    context.define("sethook", _SetHook(interpreter));
    context.define("setlocal", _SetLocal());
    context.define("setmetatable", _SetMetatable());
    context.define("setupvalue", _SetUpvalue());
    context.define("setuservalue", _SetUserValue());
    context.define("traceback", _Traceback());
    context.define("upvalueid", _UpvalueId());
    context.define("upvaluejoin", _UpvalueJoin());

    // Memory debugging functions
    context.define("memtrace", _MemTrace());
    context.define("memtree", _MemTree());
  }
}

/// Interactive debug console
class _DebugInteractive extends BuiltinFunction {
  _DebugInteractive() : super();
  @override
  dynamic call(List<dynamic> args) async {
    // Simple REPL-like debug console
    Logger.debug("Debug Console: Enter 'cont' to continue", category: 'Debug');

    while (true) {
      final defaultOutput = IOLib.defaultOutput;
      final outputLuaFile = defaultOutput.raw as LuaFile;
      await outputLuaFile.write('debug> ');

      final defaultInput = IOLib.defaultInput;
      final inputLuaFile = defaultInput.raw as LuaFile;
      final result = await inputLuaFile.read('l');
      final input = result[0]?.toString();

      if (input == 'cont') break;

      // TODO: Implement actual debug command parsing and execution
    }

    return null;
  }
}

class _GetHook extends BuiltinFunction {
  _GetHook(super.interpreter);

  @override
  Object? call(List<Object?> args) {
    if (interpreter is! Interpreter) {
      return Value.multi([Value(null), Value(null), Value(0)]);
    }
    final runtime = interpreter! as Interpreter;
    final hook = runtime.debugHookFunction;
    if (hook == null) {
      return Value.multi([Value(null), Value(null), Value(0)]);
    }
    return Value.multi([
      hook,
      Value(runtime.debugHookMask),
      Value(runtime.debugHookCount),
    ]);
  }
}

class _GetLocal extends BuiltinFunction {
  _GetLocal(LuaRuntime super.i);

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError(
        "debug.getlocal requires thread/function and level arguments",
      );
    }

    final levelArg = args[0] as Value;
    final indexArg = args[1] as Value;

    // Only support numeric level lookups (common case in tests)
    if (levelArg.raw is! num || indexArg.raw is! num) {
      return Value.multi([Value(null), Value(null)]);
    }

    final level = (levelArg.raw as num).toInt();
    final index = (indexArg.raw as num).toInt();

    // Map Lua levels to our call stack: skip this C function's own frame
    final frame = interpreter?.callStack.getFrameAtLevel(level + 1);
    if (frame == null) {
      return Value.multi([Value(null), Value(null)]);
    }

    // Enumerate debug locals recorded for the frame
    final locals = frame.debugLocals;
    if (index <= 0 || index > locals.length) {
      return Value.multi([Value(null), Value(null)]);
    }

    final entry = locals[index - 1];
    final name = entry.key;
    final value = entry.value;
    return Value.multi([Value(name), value]);
  }
}

class _GetMetatable extends BuiltinFunction {
  _GetMetatable() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw LuaError("debug.getmetatable requires a value");
    final value = args[0] as Value;
    final meta = value.getMetatable();
    if (meta == null) {
      return Value(null);
    }
    if (meta.containsKey('__metatable')) {
      return meta['__metatable'];
    }
    if (value.metatableRef != null) {
      return value.metatableRef;
    }
    return Value(meta);
  }
}

class _GetRegistry extends BuiltinFunction {
  _GetRegistry() : super();

  @override
  Object? call(List<Object?> args) {
    // Return the registry table
    return Value({});
  }
}

class _GetUpvalue extends BuiltinFunction {
  _GetUpvalue(LuaRuntime super.i);

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError("debug.getupvalue requires function and index arguments");
    }

    final functionArg = args[0] as Value;
    final indexArg = args[1] as Value;

    // Validate that index is a number
    if (indexArg.raw is! num) {
      return Value.multi([Value(null), Value(null)]);
    }

    final index = (indexArg.raw as num).toInt();

    if (functionArg.raw case final LuaBytecodeClosure closure) {
      if (index < 1 || index > closure.upvalueCount) {
        return Value.multi([Value(null), Value(null)]);
      }
      return Value.multi([
        Value(closure.upvalueName(index - 1)),
        closure.readUpvalue(index - 1),
      ]);
    }

    // Check if the function has explicit upvalues first
    if (functionArg.upvalues != null &&
        index > 0 &&
        index <= functionArg.upvalues!.length) {
      final upvalue = functionArg.upvalues![index - 1];
      final name = upvalue.name;
      final rawValue = upvalue.getValue();
      final value = rawValue is Value ? rawValue : Value(rawValue);
      return Value.multi([Value(name), value]);
    }

    // For AST-based interpreter, expose the implicit `_ENV` capture in the
    // first upvalue slot when the function does not already surface explicit
    // captures. This matches the upstream 5.5 tests for loaded chunks and
    // plain Lua closures.
    if (functionArg.raw is Function) {
      if (index == 1) {
        final envValue =
            interpreter?.getCurrentEnv().get('_ENV') ??
            interpreter?.getCurrentEnv().get('_G') ??
            Value(interpreter?.getCurrentEnv());
        return Value.multi([Value('_ENV'), envValue]);
      }
    }

    // For functions without upvalues, return null
    return Value.multi([Value(null), Value(null)]);
  }
}

class _GetUserValue extends BuiltinFunction {
  _GetUserValue() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError(
        "debug.getuservalue requires userdata and index arguments",
      );
    }
    // Return nth user value
    return Value(null);
  }
}

class _SetHook extends BuiltinFunction {
  _SetHook(super.interpreter);

  @override
  Object? call(List<Object?> args) {
    if (interpreter is! Interpreter) {
      return Value(null);
    }
    final runtime = interpreter! as Interpreter;

    if (args.isEmpty || (args[0] is Value && (args[0] as Value).isNil)) {
      runtime.debugHookFunction = null;
      runtime.debugHookMask = '';
      runtime.debugHookCount = 0;
      return Value(null);
    }

    if (args[0] is! Value || !(args[0] as Value).isCallable()) {
      throw LuaError("debug.sethook requires a hook function");
    }

    final hook = args[0] as Value;
    final mask = switch (args.length > 1 ? args[1] : null) {
      final Value value when value.raw != null => value.raw.toString(),
      null => '',
      _ => throw LuaError("debug.sethook mask must be a string"),
    };
    final count = switch (args.length > 2 ? args[2] : null) {
      final Value value when value.raw is num => (value.raw as num).toInt(),
      null => 0,
      _ => throw LuaError("debug.sethook count must be a number"),
    };

    runtime.debugHookFunction = hook;
    runtime.debugHookMask = mask;
    runtime.debugHookCount = count;
    return Value(null);
  }
}

class _SetLocal extends BuiltinFunction {
  _SetLocal() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.length < 3) {
      throw LuaError(
        "debug.setlocal requires thread/function, index and value",
      );
    }
    // Set local variable value
    return Value(null);
  }
}

class _SetMetatable extends BuiltinFunction {
  _SetMetatable() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError("debug.setmetatable requires value and metatable");
    }
    final value = args[0] as Value;
    final meta = args[1] as Value;
    if (value.raw is! Map) {
      final type = _typeOf(value.raw);
      if (meta.raw == null) {
        MetaTable().registerDefaultMetatable(type, null);
        return Value(true);
      }
      if (meta.raw is Map) {
        MetaTable().registerDefaultMetatable(
          type,
          ValueClass.create(
            Map.castFrom<dynamic, dynamic, String, dynamic>(meta.raw as Map),
          ),
          meta,
        );
        return Value(true);
      }
    } else {
      if (meta.raw == null) {
        value.metatable = null;
        value.metatableRef = null;
        return Value(true);
      }
      if (meta.raw is Map) {
        value.metatableRef = meta;
        value.setMetatable((meta.raw as Map).cast());
        return Value(true);
      }
    }
    throw LuaError("metatable must be a table or nil");
  }

  String _typeOf(Object? raw) {
    if (raw == null) return 'nil';
    if (raw is String || raw is LuaString) return 'string';
    if (raw is num || raw is BigInt) return 'number';
    if (raw is bool) return 'boolean';
    if (raw is Function || raw is BuiltinFunction) return 'function';
    if (raw is Map || raw is List) return 'table';
    if (raw is Coroutine) return 'thread';
    return 'userdata';
  }
}

class _SetUpvalue extends BuiltinFunction {
  _SetUpvalue() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.length < 3) {
      throw LuaError("debug.setupvalue requires function, index and value");
    }

    final functionArg = args[0] as Value;
    final indexArg = args[1] as Value;
    final newValue = args[2] as Value;

    // Validate that index is a number
    if (indexArg.raw is! num) {
      return Value(null);
    }

    final index = (indexArg.raw as num).toInt();

    if (functionArg.raw case final LuaBytecodeClosure closure) {
      if (index < 1 || index > closure.upvalueCount) {
        return Value(null);
      }
      final oldName = closure.upvalueName(index - 1);
      closure.writeUpvalue(index - 1, newValue);
      return Value(oldName);
    }

    // Check if the function has explicit upvalues
    if (functionArg.upvalues != null &&
        index > 0 &&
        index <= functionArg.upvalues!.length) {
      final upvalue = functionArg.upvalues![index - 1];
      Logger.debug(
        'debug.setupvalue explicit: name=${upvalue.name} value=${newValue.raw} open=${upvalue.isOpen}',
        category: 'DebugLib',
      );
      final oldName = upvalue.name;
      upvalue.setValue(newValue.raw);
      return Value(oldName);
    }

    // For AST-based interpreter, only modify existing upvalues
    if (functionArg.raw is Function) {
      // Check if upvalues exist and if the index is valid
      if (functionArg.upvalues != null &&
          index > 0 &&
          index <= functionArg.upvalues!.length) {
        final upvalue = functionArg.upvalues![index - 1];
        Logger.debug(
          'debug.setupvalue raw: name=${upvalue.name} value=${newValue.raw} open=${upvalue.isOpen}',
          category: 'DebugLib',
        );
        final oldName = upvalue.name;
        upvalue.setValue(newValue.raw);
        return Value(oldName);
      }
    }

    return Value(null);
  }
}

class _SetUserValue extends BuiltinFunction {
  _SetUserValue() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError("debug.setuservalue requires userdata and value");
    }

    final target = args[0];
    final userValue = args[1];
    final index = switch (args.length > 2 ? args[2] : null) {
      final Value value when value.raw is num => (value.raw as num).toInt(),
      final num value => value.toInt(),
      null => 1,
      _ => throw LuaError("debug.setuservalue index must be a number"),
    };

    if (target is! Value || !_isFullUserdata(target)) {
      throw LuaError.typeError(
        "bad argument #1 to 'setuservalue' (userdata expected, got ${getLuaType(target)})",
      );
    }

    if (index < 1) {
      return Value(null);
    }

    if (target.raw is Map) {
      final rawMap = target.raw as Map<dynamic, dynamic>;
      rawMap['__uservalue$index'] = userValue is Value ? userValue : Value(userValue);
    }
    return target;
  }

  bool _isFullUserdata(Value value) {
    final raw = value.raw;
    if (raw == null ||
        raw is bool ||
        raw is num ||
        raw is BigInt ||
        raw is String ||
        raw is LuaString ||
        raw is Map ||
        raw is List ||
        raw is Coroutine ||
        raw is Function ||
        raw is BuiltinFunction ||
        raw is LuaCallableArtifact) {
      return false;
    }
    return getLuaType(value) != 'light userdata';
  }
}

class _Traceback extends BuiltinFunction {
  _Traceback() : super();

  @override
  Object? call(List<Object?> args) {
    final message = args.isNotEmpty ? (args[0] as Value).raw.toString() : "";
    //level
    final _ = args.length > 1 ? (args[1] as Value).raw as int : 1;

    final trace = StringBuffer();
    if (message.isNotEmpty) {
      trace.writeln(message);
    }
    trace.writeln("stack traceback:");
    // Add dummy stack trace for now
    trace.writeln("\t[C]: in function 'traceback'");

    return Value(trace.toString());
  }
}

class _UpvalueId extends BuiltinFunction {
  _UpvalueId() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError("debug.upvalueid requires function and index");
    }
    final functionArg = args[0] as Value;
    final indexArg = args[1] as Value;

    if (indexArg.raw is! num) {
      throw LuaError("debug.upvalueid index must be a number");
    }

    final index = (indexArg.raw as num).toInt();
    if (index < 1) {
      return Value(null);
    }

    if (functionArg.raw case final LuaBytecodeClosure closure) {
      if (index > closure.upvalueCount) {
        return Value(null);
      }
      return Value(closure.upvalueIdentity(index - 1));
    }

    final upvalues = functionArg.upvalues;
    if (upvalues == null || index > upvalues.length) {
      return Value(null);
    }

    final Upvalue upvalue = upvalues[index - 1];
    return Value(upvalue.canonicalBox);
  }
}

class _UpvalueJoin extends BuiltinFunction {
  _UpvalueJoin() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.length < 4) {
      throw LuaError("debug.upvaluejoin requires f1,n1,f2,n2 arguments");
    }

    final f1Arg = args[0] as Value;
    final n1Arg = args[1] as Value;
    final f2Arg = args[2] as Value;
    final n2Arg = args[3] as Value;

    // Validate that indices are numbers
    if (n1Arg.raw is! num || n2Arg.raw is! num) {
      throw LuaError("debug.upvaluejoin indices must be numbers");
    }

    final n1 = (n1Arg.raw as num).toInt();
    final n2 = (n2Arg.raw as num).toInt();

    if (f1Arg.raw case final LuaBytecodeClosure f1Closure) {
      if (f2Arg.raw is! LuaBytecodeClosure) {
        throw LuaError(
          "debug.upvaluejoin: functions must both be bytecode closures",
        );
      }
      final f2Closure = f2Arg.raw as LuaBytecodeClosure;
      if (n1 < 1 || n1 > f1Closure.upvalueCount) {
        throw LuaError("debug.upvaluejoin: f1 upvalue index $n1 out of bounds");
      }
      if (n2 < 1 || n2 > f2Closure.upvalueCount) {
        throw LuaError("debug.upvaluejoin: f2 upvalue index $n2 out of bounds");
      }
      f1Closure.joinUpvalueWith(n1 - 1, f2Closure, n2 - 1);
      return Value(null);
    }

    // Validate that both functions have upvalues
    if (f1Arg.upvalues == null || f2Arg.upvalues == null) {
      throw LuaError("debug.upvaluejoin: functions must have upvalues");
    }

    // Validate indices are within bounds
    if (n1 < 1 || n1 > f1Arg.upvalues!.length) {
      throw LuaError("debug.upvaluejoin: f1 upvalue index $n1 out of bounds");
    }
    if (n2 < 1 || n2 > f2Arg.upvalues!.length) {
      throw LuaError("debug.upvaluejoin: f2 upvalue index $n2 out of bounds");
    }

    // Join the upvalues by making f1's upvalue point to the same value box as f2's upvalue
    final f1Upvalue = f1Arg.upvalues![n1 - 1];
    final f2Upvalue = f2Arg.upvalues![n2 - 1];

    // Use the new joinWith method to join the upvalues
    f1Upvalue.joinWith(f2Upvalue);

    Logger.debug(
      'UpvalueJoin: Joined f1 upvalue $n1 with f2 upvalue $n2',
      category: 'Debug',
    );

    return Value(null);
  }
}

/// Implementation of debug.getinfo that correctly reports line numbers
class _GetInfoImpl extends BuiltinFunction {
  _GetInfoImpl(super.interpreter);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw ArgumentError('debug.getinfo requires at least one argument');
    }

    final firstArg = args[0] as Value;
    String? what = args.length > 1
        ? (args[1] as Value).raw.toString()
        : "flnSrtu";

    final optionError = _validateGetInfoOptions(what);
    if (optionError != null) {
      throw LuaError(optionError);
    }

    // Log that debug.getinfo was called to help with troubleshooting
    Logger.debug(
      'debug.getinfo called with args: $firstArg, what: $what, interpreter: ${interpreter != null}',
      category: 'DebugLib',
    );

    // If we don't have an interpreter instance, try to get one
    final interpreterInstance = interpreter;
    if (interpreterInstance == null) {
      Logger.warning(
        'No interpreter instance available for debug.getinfo',
        category: 'DebugLib',
      );
    }

    // Handle level-based lookup (when first arg is a number)
    if (firstArg.raw is num) {
      final level = (firstArg.raw as num).toInt();
      if (level < 0) {
        return Value(null);
      }
      final actualLevel = level + 1;

    if (interpreterInstance != null) {
        // Get the frame from the call stack; invalid levels return nil.
        final hookAdjustedLevel =
            interpreterInstance is Interpreter &&
                interpreterInstance.callStack.top?.isDebugHook == true
            ? level
            : actualLevel;
        final frame = interpreterInstance is Interpreter
            ? interpreterInstance.getVisibleFrameAtLevel(hookAdjustedLevel)
            : interpreterInstance.callStack.getFrameAtLevel(actualLevel);

        if (frame != null) {
          Logger.debug(
            'Found frame for level $level: name=${frame.functionName}, line=${frame.currentLine}',
            category: 'DebugLib',
          );

          final debugInfo = <String, Value>{};
          final frameNameInfo = _inferFrameNameInfo(frame);

          if (what.contains('n')) {
            debugInfo['name'] = Value(frameNameInfo.name);
            debugInfo['namewhat'] = Value(frameNameInfo.namewhat);
          }
          if (what.contains('S')) {
            debugInfo['what'] = Value("Lua");

            // Check if we can get source from current function first
            String sourceValue = "=[C]";
            String shortSrc = "[C]";

            // First, check script path for explicit chunk names (string chunks)
            final scriptPath =
                frame.scriptPath ?? interpreterInstance.callStack.scriptPath;
            Logger.debug(
              'debug.getinfo: frame.scriptPath=${frame.scriptPath}, callStack.scriptPath=${interpreterInstance.callStack.scriptPath}',
              category: 'DebugLib',
            );

            if (scriptPath != null) {
              // For string chunks, use script path directly
              if (scriptPath.startsWith('@') ||
                  scriptPath.startsWith('=') ||
                  scriptPath.startsWith('[')) {
                sourceValue = scriptPath;
                shortSrc = scriptPath.startsWith('@')
                    ? scriptPath.substring(1)
                    : scriptPath;
                Logger.debug(
                  'debug.getinfo: using scriptPath as-is: $sourceValue',
                  category: 'DebugLib',
                );
              } else {
                // For unprefixed script paths, check whether the active
                // function came from a loaded chunk-like artifact.
                Value? currentFunction;
                if (interpreterInstance is Interpreter) {
                  currentFunction = interpreterInstance.getCurrentFunction();
                }
                bool isBinaryChunk = false;

                if (currentFunction != null &&
                    currentFunction.functionBody != null) {
                  final span = currentFunction.functionBody!.span;
                  Logger.debug(
                    'debug.getinfo: currentFunction has functionBody, span=$span, sourceUrl=${span?.sourceUrl}',
                    category: 'DebugLib',
                  );

                  if (span != null && span.sourceUrl != null) {
                    // Preserve the source location carried by the loaded
                    // function artifact when one is available.
                    final rawSource = span.sourceUrl!.toString();
                    sourceValue = _formatSourceForLua(rawSource);
                    shortSrc = sourceValue.startsWith('@')
                        ? sourceValue.substring(1)
                        : sourceValue;
                    isBinaryChunk = true;
                    Logger.debug(
                      'debug.getinfo: using current function source: $sourceValue',
                      category: 'DebugLib',
                    );
                  } else {
                    // Fall back to source spans attached to child nodes when
                    // the loaded function body does not have a direct span.
                    String? childSource = _extractSourceFromChildren(
                      currentFunction.functionBody!,
                    );
                    if (childSource != null) {
                      sourceValue = _formatSourceForLua(childSource);
                      shortSrc = sourceValue.startsWith('@')
                          ? sourceValue.substring(1)
                          : sourceValue;
                      isBinaryChunk = true;
                      Logger.debug(
                        'debug.getinfo: using source from child nodes: $sourceValue',
                        category: 'DebugLib',
                      );
                    }
                  }
                }

                // If the current function does not carry loaded-chunk source
                // metadata, use the raw script path as the chunk name.
                if (!isBinaryChunk) {
                  sourceValue = _formatSourceForLua(scriptPath);
                  shortSrc = scriptPath;
                  Logger.debug(
                    'debug.getinfo: using script path as string chunk: $sourceValue',
                    category: 'DebugLib',
                  );
                }
              }
            }

            debugInfo['source'] = Value(sourceValue);
            debugInfo['short_src'] = Value(shortSrc);
            debugInfo['linedefined'] = Value(-1);
            debugInfo['lastlinedefined'] = Value(-1);
          }
          if (what.contains('l')) {
            // Report the current line from the requested frame directly.
            // This matches expectations in lexstring tests (literals.lua).
            final line = frame.currentLine > 0 ? frame.currentLine : -1;
            debugInfo['currentline'] = Value(line);
          }
          if (what.contains('t')) {
            debugInfo['istailcall'] = Value(false);
            debugInfo['extraargs'] = Value(frame.extraArgs);
          }
          if (what.contains('u')) {
            debugInfo['nups'] = Value(0);
            debugInfo['nparams'] = Value(0);
            debugInfo['isvararg'] = Value(true);
          }
          if (what.contains('f')) {
            debugInfo['func'] = Value(null);
          }

          return Value(debugInfo);
        }
      }

      return Value(null);
    }

    // Function-based lookup
    if (firstArg.isCallable()) {
      final metadata = interpreterInstance?.debugInfoForFunction(firstArg);
      String src = metadata?.source ?? "=[C]";
      String whatKind = metadata?.what ?? "C";

      final debugInfo = <String, Value>{};
      if (what.contains('n')) {
        debugInfo['name'] = Value(null);
        debugInfo['namewhat'] = Value("");
      }
      if (what.contains('S')) {
        debugInfo['what'] = Value(whatKind);
        debugInfo['source'] = Value(src);
        debugInfo['short_src'] = Value(
          metadata?.shortSource ??
              (src.split('/').isNotEmpty ? src.split('/').last : src),
        );
        debugInfo['linedefined'] = Value(metadata?.lineDefined ?? -1);
        debugInfo['lastlinedefined'] = Value(metadata?.lastLineDefined ?? -1);
      }
      if (what.contains('l')) {
        debugInfo['currentline'] = Value(-1);
      }
      if (what.contains('u')) {
        debugInfo['nups'] = Value(metadata?.nups ?? 0);
        debugInfo['nparams'] = Value(metadata?.nparams ?? 0);
        debugInfo['isvararg'] = Value(metadata?.isVararg ?? true);
      }
      if (what.contains('r')) {
        debugInfo['ftransfer'] = Value(0);
        debugInfo['ntransfer'] = Value(0);
      }
      if (what.contains('t')) {
        debugInfo['istailcall'] = Value(false);
        debugInfo['extraargs'] = Value(0);
      }
      if (what.contains('f')) {
        debugInfo['func'] = firstArg;
      }
      if (what.contains('L')) {
        debugInfo['activelines'] = _collectActiveLines(firstArg);
      }
      return Value(debugInfo);
    }

    // Fallback: unknown type
    return Value({
      'name': Value(null),
      'namewhat': Value(""),
      'what': Value("C"),
      'source': Value("=[C]"),
      'short_src': Value("[C]"),
      'currentline': Value(-1),
      'linedefined': Value(-1),
      'lastlinedefined': Value(-1),
      'nups': Value(0),
      'nparams': Value(0),
      'isvararg': Value(false),
      'istailcall': Value(false),
    });
  }
}

String? _validateGetInfoOptions(String what) {
  if (what.startsWith('>')) {
    return "bad argument #2 to 'debug.getinfo' (invalid option '>')";
  }

  const allowed = 'flnSrtuL';
  for (final codeUnit in what.codeUnits) {
    final option = String.fromCharCode(codeUnit);
    if (!allowed.contains(option)) {
      return "bad argument #2 to 'debug.getinfo' (invalid option)";
    }
  }
  return null;
}

Value _collectActiveLines(Value function) {
  final body = function.functionBody;
  if (body == null) {
    return Value(null);
  }

  final lines = <Object?, Object?>{};
  void markLine(int? line) {
    if (line == null || line <= 0) {
      return;
    }
    lines[line] = Value(true);
  }

  for (final statement in body.body) {
    final span = statement.span;
    markLine(span?.start.line != null ? span!.start.line + 1 : null);
  }
  markLine(_lastFunctionBodyLine(body));

  return Value(lines);
}

int _lastFunctionBodyLine(FunctionBody body) {
  var maxLine = -1;
  for (final statement in body.body) {
    final span = statement.span;
    if (span != null) {
      final endLine = span.end.line + 1;
      if (endLine > maxLine) {
        maxLine = endLine;
      }
    }
  }

  if (maxLine > 0) {
    return maxLine;
  }

  final span = body.span;
  return span != null ? span.end.line + 1 : -1;
}

/// Helper method to extract source URL from child AST nodes
String? _extractSourceFromChildren(dynamic node) {
  Logger.debug(
    'AST: _extractSourceFromChildren called with node type: ${node.runtimeType}',
    category: 'DebugLib',
  );

  if (node == null) return null;

  // If this node has a span, return its source URL
  if (node is AstNode && node.span?.sourceUrl != null) {
    final sourceUrl = node.span!.sourceUrl!.toString();
    Logger.debug(
      'AST: Found span with sourceUrl: $sourceUrl',
      category: 'DebugLib',
    );
    return sourceUrl;
  }

  // Recursively search child nodes
  if (node is FunctionBody) {
    Logger.debug(
      'AST: Searching FunctionBody with ${node.parameters?.length ?? 0} params and ${node.body.length} body statements',
      category: 'DebugLib',
    );

    // Check parameters
    if (node.parameters != null) {
      for (final param in node.parameters!) {
        final source = _extractSourceFromChildren(param);
        if (source != null) return source;
      }
    }

    // Check body statements
    for (final stmt in node.body) {
      final source = _extractSourceFromChildren(stmt);
      if (source != null) return source;
    }
  } else if (node is List) {
    Logger.debug(
      'AST: Searching List with ${node.length} items',
      category: 'DebugLib',
    );
    for (final item in node) {
      final source = _extractSourceFromChildren(item);
      if (source != null) return source;
    }
  }

  Logger.debug(
    'AST: No source found in node type: ${node.runtimeType}',
    category: 'DebugLib',
  );
  return null;
}

/// Formats source URL to match Lua's format
String _formatSourceForLua(String rawSource) {
  // Handle command line sources
  if (rawSource.contains('command') || rawSource.contains('line')) {
    return '=(command line)';
  }

  // Handle file URLs
  if (rawSource.startsWith('file:///')) {
    final uri = Uri.parse(rawSource);
    final fileName = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : rawSource;
    return '@$fileName';
  }

  // Handle already prefixed sources
  if (rawSource.startsWith('@') ||
      rawSource.startsWith('=') ||
      rawSource.startsWith('[')) {
    return rawSource;
  }

  // Default: add @ prefix for file-like sources
  return '@$rawSource';
}

/// Function to create a debug.getinfo function that correctly reports line numbers
/// (kept for backwards compatibility)
BuiltinFunction createGetInfoFunction(LuaRuntime? vm) {
  return _GetInfoImpl(vm);
}

/// Creates debug library functions with the given interpreter instance
Map<String, BuiltinFunction> createDebugLib(LuaRuntime? astVm) {
  // Ensure we have a valid VM instance for debug functions
  if (astVm == null) {
    Logger.warning(
      "No VM instance provided to debug library, line tracking might not work correctly",
      category: "Debug",
    );

    // Note: Cannot access Environment.current anymore
    // Interpreter should be passed directly to debug functions
    Logger.info(
      "Cannot access Environment.current for debug library (deprecated)",
      category: "Debug",
    );
  }

  // Create debug functions with interpreter reference
  return {
    'debug': _DebugInteractive(),
    'gethook': _GetHook(astVm),
    'getinfo': createGetInfoFunction(astVm), // Use new optimized implementation
    'getlocal': _GetLocal(astVm!),
    'getmetatable': _GetMetatable(),
    'getregistry': _GetRegistry(),
    'getupvalue': _GetUpvalue(astVm),
    'getuservalue': _GetUserValue(),
    'sethook': _SetHook(astVm),
    'setlocal': _SetLocal(),
    'setmetatable': _SetMetatable(),
    'setupvalue': _SetUpvalue(),
    'setuservalue': _SetUserValue(),
    'traceback': _Traceback(),
    'upvalueid': _UpvalueId(),
    'upvaluejoin': _UpvalueJoin(),

    // Memory debugging functions
    'memtrace': _MemTrace(),
    'memtree': _MemTree(),
    'memclear': _MemClear(),
  };
}

/// Initialize the debug library with the interpreter instance
///
/// This ensures the debug.getinfo function can access line information
/// [env] - The environment to define the debug table in
/// [vm] - The runtime instance to use for call stack access
void defineDebugLibrary({required Environment env, LuaRuntime? vm}) {
  // Store interpreter reference in environment for later access
  if (vm != null) {
    env.interpreter = vm;
    Logger.debug(
      'Setting interpreter reference in environment for debug library',
      category: 'Debug',
    );
  }

  // Create and define the debug table
  DebugLib.functions = createDebugLib(vm);
  final debugTable = Value(DebugLib.functions);
  env.define("debug", debugTable);

  // Ensure the same object is stored in package.loaded for require() equality
  final packageTable = env.get("package");
  if (packageTable != null &&
      packageTable is Value &&
      packageTable.raw is Map) {
    final packageMap = packageTable.raw as Map;

    // Ensure package.loaded exists
    if (!packageMap.containsKey("loaded")) {
      packageMap["loaded"] = Value({});
    }

    final loadedTable = packageMap["loaded"];
    if (loadedTable is Value && loadedTable.raw is Map) {
      final loadedMap = loadedTable.raw as Map;
      // Store the same debug table object to ensure require("debug") == debug
      loadedMap["debug"] = debugTable;
      Logger.debug(
        'Debug table stored in package.loaded for require() equality',
        category: 'Debug',
      );
    }
  }

  Logger.debug(
    'Debug library initialized with interpreter: ${vm != null}',
    category: 'Debug',
  );
}

({String? name, String namewhat}) _inferFrameNameInfo(CallFrame frame) {
  if (frame.isDebugHook) {
    return (name: 'hook', namewhat: 'hook');
  }

  final callNode = frame.callNode;
  final env = frame.env;

  if (callNode case MethodCall(methodName: final Identifier methodName)) {
    return (name: methodName.name, namewhat: 'method');
  }

  if (callNode case FunctionCall(name: final AstNode callee)) {
    if (callee case Identifier(name: final name)) {
      return (name: name, namewhat: _inferIdentifierNameWhat(env, name));
    }
    if (callee case TableFieldAccess(fieldName: final Identifier fieldName)) {
      return (name: fieldName.name, namewhat: 'field');
    }
  }

  final fallbackName = switch (frame.functionName) {
    'unknown' || 'function' => null,
    final name => name,
  };
  return (
    name: fallbackName,
    namewhat: fallbackName != null
        ? _inferIdentifierNameWhat(env, fallbackName)
        : '',
  );
}

String _inferIdentifierNameWhat(Environment? env, String name) {
  Environment? current = env;
  while (current != null) {
    if (current.values.containsKey(name)) {
      final box = current.values[name]!;
      if (!box.isLocal) {
        return 'global';
      }
      // For active call-site naming, Lua reports identifiers resolved through
      // enclosing lexical blocks as "local" too; they are still called by a
      // local name, even if that binding lives in a parent environment frame.
      return 'local';
    }
    if (current.declaredGlobals.containsKey(name)) {
      return 'global';
    }
    current = current.parent;
  }
  return 'global';
}

/// Enable/disable memory allocation stack trace tracking
class _MemTrace extends BuiltinFunction {
  _MemTrace() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      return Value(MemoryCredits.enableStackTraces);
    }

    final enable = args[0];
    if (enable is Value) {
      MemoryCredits.enableStackTraces = enable.raw == true;
    } else {
      MemoryCredits.enableStackTraces = enable == true;
    }

    return Value(null);
  }
}

/// Print memory allocation tree
class _MemTree extends BuiltinFunction {
  _MemTree() : super();

  @override
  Object? call(List<Object?> args) {
    MemoryCredits.instance.printAllocationTree();
    return Value(null);
  }
}

/// Clear tracked objects list for debugging specific allocations
class _MemClear extends BuiltinFunction {
  _MemClear() : super();

  @override
  Object? call(List<Object?> args) {
    MemoryCredits.instance.clearTrackedObjects();
    return Value(null);
  }
}
