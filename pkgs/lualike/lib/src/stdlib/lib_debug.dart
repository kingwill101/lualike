import 'package:lualike/lualike.dart';

import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/io/lua_file.dart';
import 'package:lualike/src/stdlib/lib_io.dart';
import 'package:lualike/src/stdlib/metatables.dart';
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
    context.define("gethook", _GetHook());
    context.define("getinfo", _GetInfoImpl(interpreter!));
    context.define("getlocal", _GetLocal(interpreter!));
    context.define("getmetatable", _GetMetatable());
    context.define("getregistry", _GetRegistry());
    context.define("getupvalue", _GetUpvalue(interpreter!));
    context.define("getuservalue", _GetUserValue());
    context.define("sethook", _SetHook());
    context.define("setlocal", _SetLocal());
    context.define("setmetatable", _SetMetatable());
    context.define("setupvalue", _SetUpvalue());
    context.define("setuservalue", _SetUserValue());
    context.define("traceback", _Traceback());
    context.define("upvalueid", _UpvalueId());
    context.define("upvaluejoin", _UpvalueJoin());
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
  _GetHook() : super();

  @override
  Object? call(List<Object?> args) {
    // Return current hook function, mask and count
    return [Value(null), Value(0), Value(0)];
  }
}

class _GetLocal extends BuiltinFunction {
  _GetLocal(Interpreter super.i);

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw Exception(
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
    if (args.isEmpty) throw Exception("debug.getmetatable requires a value");
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
  _GetUpvalue(Interpreter super.i);

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw Exception("debug.getupvalue requires function and index arguments");
    }

    final functionArg = args[0] as Value;
    final indexArg = args[1] as Value;

    // Validate that index is a number
    if (indexArg.raw is! num) {
      return Value.multi([Value(null), Value(null)]);
    }

    final index = (indexArg.raw as num).toInt();

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

    // For AST-based interpreter, we simulate standard Lua upvalue behavior
    // In Lua, functions typically have _ENV as an upvalue for global access
    if (functionArg.raw is Function) {
      // For any Dart function (with or without functionBody), simulate standard upvalue structure
      if (index == 2) {
        // Second upvalue is typically _ENV in Lua
        final envValue =
            interpreter?.getCurrentEnv().get('_ENV') ??
            interpreter?.getCurrentEnv().get('_G') ??
            Value(interpreter?.getCurrentEnv());
        return Value.multi([Value('_ENV'), envValue]);
      } else if (index == 1) {
        // First upvalue could be any captured variable, return nil for now
        return Value.multi([Value(null), Value(null)]);
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
      throw Exception(
        "debug.getuservalue requires userdata and index arguments",
      );
    }
    // Return nth user value
    return Value(null);
  }
}

class _SetHook extends BuiltinFunction {
  _SetHook() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.length < 3) {
      throw Exception("debug.sethook requires hook function, mask and count");
    }
    // Set debug hook function
    return Value(null);
  }
}

class _SetLocal extends BuiltinFunction {
  _SetLocal() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.length < 3) {
      throw Exception(
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
      throw Exception("debug.setmetatable requires value and metatable");
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
    throw Exception("metatable must be a table or nil");
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
      throw Exception("debug.setupvalue requires function, index and value");
    }

    final functionArg = args[0] as Value;
    final indexArg = args[1] as Value;
    final newValue = args[2] as Value;

    // Validate that index is a number
    if (indexArg.raw is! num) {
      return Value(null);
    }

    final index = (indexArg.raw as num).toInt();

    // Check if the function has explicit upvalues
    if (functionArg.upvalues != null &&
        index > 0 &&
        index <= functionArg.upvalues!.length) {
      final upvalue = functionArg.upvalues![index - 1];
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
    if (args.length < 3) {
      throw Exception("debug.setuservalue requires userdata, value and index");
    }
    // Set nth user value
    return Value(null);
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
      throw Exception("debug.upvalueid requires function and index");
    }
    // Return unique id for upvalue
    return Value(null);
  }
}

class _UpvalueJoin extends BuiltinFunction {
  _UpvalueJoin() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.length < 4) {
      throw Exception("debug.upvaluejoin requires f1,n1,f2,n2 arguments");
    }

    final f1Arg = args[0] as Value;
    final n1Arg = args[1] as Value;
    final f2Arg = args[2] as Value;
    final n2Arg = args[3] as Value;

    // Validate that indices are numbers
    if (n1Arg.raw is! num || n2Arg.raw is! num) {
      throw Exception("debug.upvaluejoin indices must be numbers");
    }

    final n1 = (n1Arg.raw as num).toInt();
    final n2 = (n2Arg.raw as num).toInt();

    // Validate that both functions have upvalues
    if (f1Arg.upvalues == null || f2Arg.upvalues == null) {
      throw Exception("debug.upvaluejoin: functions must have upvalues");
    }

    // Validate indices are within bounds
    if (n1 < 1 || n1 > f1Arg.upvalues!.length) {
      throw Exception("debug.upvaluejoin: f1 upvalue index $n1 out of bounds");
    }
    if (n2 < 1 || n2 > f2Arg.upvalues!.length) {
      throw Exception("debug.upvaluejoin: f2 upvalue index $n2 out of bounds");
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
        : "flnStu";

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
      final actualLevel = level + 1; // skip getinfo's own frame

      if (interpreterInstance != null) {
        // Get the frame from the call stack, fallback to top frame if level is out of bounds
        final frame =
            interpreterInstance.callStack.getFrameAtLevel(actualLevel) ??
            interpreterInstance.callStack.top;

        if (frame != null) {
          Logger.debug(
            'Found frame for level $level: name=${frame.functionName}, line=${frame.currentLine}',
            category: 'DebugLib',
          );

          String? functionName = frame.functionName;
          if (functionName == "unknown" || functionName == "function") {
            functionName = null;
          }

          final debugInfo = <String, Value>{};

          if (what.contains('n')) {
            debugInfo['name'] = Value(functionName);
            debugInfo['namewhat'] = Value(functionName != null ? "local" : "");
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
                // For script paths without prefix, check if it's a binary chunk
                final currentFunction = interpreterInstance
                    .getCurrentFunction();
                bool isBinaryChunk = false;

                if (currentFunction != null &&
                    currentFunction.functionBody != null) {
                  final span = currentFunction.functionBody!.span;
                  Logger.debug(
                    'debug.getinfo: currentFunction has functionBody, span=$span, sourceUrl=${span?.sourceUrl}',
                    category: 'DebugLib',
                  );

                  if (span != null && span.sourceUrl != null) {
                    // Use the original function's source location (binary chunk)
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
                    // Try to extract source from child nodes (binary chunk)
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

                // If not a binary chunk, use script path as string chunk name
                if (!isBinaryChunk) {
                  sourceValue = scriptPath;
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
    }

    // Function-based lookup
    if (firstArg.raw is Function || firstArg.raw is BuiltinFunction) {
      String src = "=[C]";
      String whatKind = "C";
      // Try to use function body span or interpreter script path if available
      if (firstArg.functionBody != null) {
        final span = firstArg.functionBody!.span;
        if (span != null && span.sourceUrl != null) {
          src = span.sourceUrl!.toString();
          whatKind = "Lua";
        } else if (interpreterInstance != null &&
            interpreterInstance.currentScriptPath != null) {
          src = interpreterInstance.currentScriptPath!;
          whatKind = "Lua";
        }
      } else if (interpreterInstance != null &&
          interpreterInstance.currentScriptPath != null) {
        src = interpreterInstance.currentScriptPath!;
        whatKind = "Lua";
      }

      // For compatibility with tests (calls.lua), do not prefix '@'
      final debugInfo = <String, Value>{
        'name': Value(null),
        'namewhat': Value(""),
        'what': Value(whatKind),
        'source': Value(src),
        'short_src': Value(
          src.split('/').isNotEmpty ? src.split('/').last : src,
        ),
        'currentline': Value(-1),
        'linedefined': Value(-1),
        'lastlinedefined': Value(-1),
        'nups': Value(0),
        'nparams': Value(0),
        'isvararg': Value(true),
        'istailcall': Value(false),
      };
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
BuiltinFunction createGetInfoFunction(Interpreter? vm) {
  return _GetInfoImpl(vm);
}

/// Creates debug library functions with the given interpreter instance
Map<String, BuiltinFunction> createDebugLib(Interpreter? astVm) {
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
    'gethook': _GetHook(),
    'getinfo': createGetInfoFunction(astVm), // Use new optimized implementation
    'getlocal': _GetLocal(astVm!),
    'getmetatable': _GetMetatable(),
    'getregistry': _GetRegistry(),
    'getupvalue': _GetUpvalue(astVm),
    'getuservalue': _GetUserValue(),
    'sethook': _SetHook(),
    'setlocal': _SetLocal(),
    'setmetatable': _SetMetatable(),
    'setupvalue': _SetUpvalue(),
    'setuservalue': _SetUserValue(),
    'traceback': _Traceback(),
    'upvalueid': _UpvalueId(),
    'upvaluejoin': _UpvalueJoin(),
  };
}

/// Initialize the debug library with the interpreter instance
///
/// This ensures the debug.getinfo function can access line information
/// [env] - The environment to define the debug table in
/// [astVm] - The interpreter instance to use for call stack access
/// [bytecodeVm] - Optional bytecode VM for bytecode mode
void defineDebugLibrary({required Environment env, Interpreter? astVm}) {
  // Store interpreter reference in environment for later access
  if (astVm != null) {
    env.interpreter = astVm;
    Logger.debug(
      'Setting interpreter reference in environment for debug library',
      category: 'Debug',
    );
  }

  // Create and define the debug table
  DebugLib.functions = createDebugLib(astVm);
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
    'Debug library initialized with interpreter: ${astVm != null}',
    category: 'Debug',
  );
}
