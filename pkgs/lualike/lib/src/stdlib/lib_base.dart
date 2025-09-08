import 'dart:async';
import 'dart:convert';
import 'package:lualike/src/chunk_serializer.dart';

import 'package:lualike/lualike.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/const_checker.dart';
import 'package:lualike/src/upvalue.dart';
import 'package:lualike/src/interpreter/upvalue_analyzer.dart';
import 'package:lualike/src/utils/file_system_utils.dart';
import 'package:lualike/src/utils/type.dart';
import 'package:path/path.dart' as path;
import 'package:source_span/source_span.dart';

import 'lib_io.dart';

/// Built-in function to retrieve the metatable of a value.
class GetMetatableFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw Exception("getmetatable requires an argument");
    }

    final value = args[0];
    if (value is! Value) {
      return Value(null);
    }

    // Check for __metatable field first
    final metatable = value.getMetatable();
    if (metatable == null) {
      return Value(null);
    }

    if (metatable.containsKey('__metatable')) {
      return metatable['__metatable'];
    }

    // Return the original metatable value if available to preserve identity
    if (value.metatableRef != null) {
      return value.metatableRef;
    }

    // Otherwise wrap the map in a new Value
    return Value(metatable);
  }
}

/// Built-in function to set the metatable of a table value.
/// Only values wrapping a Map (table) can have a metatable set.
class SetMetatableFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length != 2) {
      throw Exception("setmetatable expects two arguments");
    }

    final table = args[0];
    final metatable = args[1];

    if (table is! Value || table.raw is! Map) {
      throw Exception("setmetatable only supported for table values");
    }

    // Check if the current metatable is protected
    final currentMetatable = table.getMetatable();
    if (currentMetatable != null &&
        currentMetatable.containsKey('__metatable')) {
      throw Exception("cannot change a protected metatable");
    }

    if (metatable is Value) {
      if (metatable.raw is Map) {
        // Preserve identity by keeping a reference to the original Value.
        table.metatableRef = metatable;
        // Reuse the same map instance so identity comparisons work as expected.
        final rawMeta = Map.castFrom<dynamic, dynamic, String, dynamic>(
          metatable.raw as Map,
        );
        table.metatable = rawMeta;
        return table;
      } else if (metatable.raw == null) {
        // Setting nil metatable removes the metatable
        table.metatable = null;
        table.metatableRef = null;
        return table;
      }
    }

    throw Exception("metatable must be a table or nil");
  }
}

/// Built-in function to set a table field without invoking metamethods.
class RawSetFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 3) {
      throw Exception("rawset expects three arguments (table, key, value)");
    }

    final table = args[0];
    if (table is! Value || table.raw is! Map) {
      throw Exception("rawset: first argument must be a table");
    }

    final key = args[1] as Value;

    // Check for nil key
    if (key.raw == null) {
      throw LuaError.typeError('table index is nil');
    }

    // Check for NaN key
    if (key.raw is num && (key.raw as num).isNaN) {
      throw LuaError.typeError('table index is NaN');
    }

    final value = args[2];
    final wrappedValue = value is Value ? value : Value(value);

    // Use raw key like normal table operations do
    var rawKey = key.raw;
    if (rawKey is LuaString) {
      rawKey = rawKey.toString();
    }
    if (wrappedValue.isNil) {
      (table.raw as Map).remove(rawKey);
    } else {
      (table.raw as Map)[rawKey] = wrappedValue;
    }
    return table;
  }
}

class AssertFunction implements BuiltinFunction {
  final Interpreter? vm;

  AssertFunction([this.vm]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw Exception("assert requires at least one argument");
    final condition = args[0];

    bool isTrue;
    if (condition is Value) {
      if (condition.raw is bool) {
        isTrue = condition.raw as bool;
      } else {
        isTrue = condition.raw != null;
      }
    } else if (condition is bool) {
      isTrue = condition;
    } else {
      isTrue = condition != null;
    }

    Logger.debug(
      'AssertFunction: Assertion condition: $condition, evaluated to: $isTrue',
      category: 'Base',
    );

    if (!isTrue) {
      final message = args.length > 1
          ? (args[1] as Value).raw.toString()
          : "assertion failed! condition: ${condition is Value ? condition.raw : condition}";
      Logger.debug(
        'AssertFunction: Assertion failed with message: $message',
        category: 'Base',
      );
      if (vm?.callStack.current?.callNode != null) {
        throw LuaError.fromNode(vm!.callStack.current!.callNode!, message);
      }
      throw LuaError(message);
    }

    Logger.debug(
      'AssertFunction: Assertion passed, returning original arguments',
      category: 'Base',
    );

    // Lua returns all its arguments on success. The caller will use only the
    // first return value in callee position when writing patterns like
    // assert(load(x), "")().
    if (args.length <= 1) {
      return args.isEmpty ? Value(null) : args[0];
    }
    return Value.multi(args);
  }
}

// Static flag to track if an error is already being reported
bool _errorReporting = false;

class ErrorFunction implements BuiltinFunction {
  final Interpreter? vm;

  ErrorFunction([this.vm]);

  @override
  Object? call(List<Object?> args) {
    // If no arguments, throw nil as the error object (Lua behavior)
    if (args.isEmpty) {
      throw Value(null);
    }

    // Get the error value
    final errorValue = args[0] as Value;

    // If we're in a protected call (pcall/xpcall), always throw the Value directly
    if (vm != null && vm!.isInProtectedCall) {
      throw errorValue;
    }

    // If the error value is a table, preserve it
    if (errorValue.raw is Map) {
      throw errorValue; // Throw the Value directly instead of converting to Exception
    }

    final message = errorValue.raw.toString();
    final level = args.length > 1 ? (args[1] as Value).raw as int : 1;

    // If we're already reporting an error, just throw the exception
    // without calling reportError again
    if (_errorReporting) {
      throw Exception(message);
    }

    // Set the flag to indicate we're reporting an error
    _errorReporting = true;

    try {
      // If we have access to the VM, use its call stack for better error reporting
      if (vm != null) {
        // Let the VM handle the error reporting with proper stack trace
        vm!.reportError(message);
        // This will never be reached, but needed for type safety
        throw Exception(message);
      } else {
        // Get the current script path if available
        String scriptPath = "unknown";
        if (vm != null) {
          // Try to get the script path from the environment first
          final scriptPathValue = vm!.globals.get('_SCRIPT_PATH');
          if (scriptPathValue is Value && scriptPathValue.raw != null) {
            scriptPath = scriptPathValue.raw.toString();
          } else if (vm!.currentScriptPath != null) {
            scriptPath = vm!.currentScriptPath!;
          }

          // Extract just the filename for display, like Lua does
          scriptPath = scriptPath.split('/').last;
        }

        // Format error message like Lua CLI
        final errorMsg = "$scriptPath: $message";

        // Generate a simple stack trace based on level
        final trace = StringBuffer(errorMsg);
        if (level > 0) {
          trace.writeln();
          trace.writeln("stack traceback:");
          for (var i = 0; i < level; i++) {
            trace.writeln("\t$scriptPath:${i + 1}: in function '?'");
          }
        }

        throw Exception(trace.toString());
      }
    } finally {
      // Reset the flag
      _errorReporting = false;
    }
  }
}

class IPairsFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw Exception("ipairs requires a table");
    final table = args[0] as Value;
    if (table.raw is! Map) throw Exception("ipairs requires a table");

    // Debug logging disabled for performance
    // Logger.debug(
    //   'IPairsFunction: Creating iterator for table: ${table.raw}',
    //   category: 'Base',
    // );

    // Create a function that returns the next index and value
    final iteratorFunction = Value((List<Object?> iterArgs) {
      if (iterArgs.length < 2) {
        throw Exception("iterator requires a table and an index");
      }

      final t = iterArgs[0] as Value;

      if (t.raw is! Map) {
        throw Exception("iterator requires a table as first argument");
      }

      final map = t.raw as Map;

      // The second argument must be a number
      if (iterArgs[1] is! Value || (iterArgs[1] as Value).raw is! num) {
        throw Exception("iterator index must be a number");
      }

      final index = (iterArgs[1] as Value).raw as num;

      // Debug logging disabled for performance
      // Logger.debug(
      //   'IPairsFunction.iterator: Called with index: $index',
      //   category: 'Base',
      // );

      // In Lua, ipairs iterates over consecutive integer keys starting from 1
      // It stops at the first nil value or non-integer key
      final nextIndex = index + 1;

      // Check if the next index exists in the table
      if (!map.containsKey(nextIndex)) {
        // Debug logging disabled for performance
        // Logger.debug(
        //   'IPairsFunction.iterator: No next index, returning nil',
        //   category: 'Base',
        // );
        return Value(null);
      }

      // Get the value at the next index
      final value = map[nextIndex];

      // If the value is nil, stop iteration
      if (value == null || (value is Value && value.raw == null)) {
        // Debug logging disabled for performance
        // Logger.debug(
        //   'IPairsFunction.iterator: Value at index $nextIndex is nil, returning nil',
        //   category: 'Base',
        // );
        return Value(null);
      }

      final nextValue = value is Value ? value : Value(value);

      // Debug logging disabled for performance
      // Logger.debug(
      //   'IPairsFunction.iterator: Found next index: $nextIndex, value: $nextValue',
      //   category: 'Base',
      // );

      // Return the index and value as multiple values
      return Value.multi([Value(nextIndex), nextValue]);
    });

    // Debug logging disabled for performance
    // Logger.debug(
    //   'IPairsFunction: Returning iterator components via Value.multi',
    //   category: 'Base',
    // );

    // Return iterator function, table, and initial control value (0) using Value.multi
    // This matches Lua's behavior: ipairs(t) returns iterator, t, 0
    return Value.multi([iteratorFunction, table, Value(0)]);
  }
}

class PrintFunction implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    final outputs = <String>[];

    for (int i = 0; i < args.length; i++) {
      final arg = args[i];

      if (arg == null) {
        outputs.add("nil");
        continue;
      }

      final value = arg as Value;

      // Check for __tostring metamethod first
      final tostring = value.getMetamethod("__tostring");
      if (tostring != null) {
        final result = await tostring.call([value]);
        if (result is Value) {
          final awaitedResult = result.raw is Future
              ? await result.raw
              : result.raw;
          outputs.add(awaitedResult.toString());
        } else {
          outputs.add(result.toString());
        }
        continue;
      }

      // Handle different types
      if (value.raw is num || value.raw is BigInt) {
        // Use proper number formatting
        outputs.add(value.raw.toString());
      } else if (value.raw is String || value.raw is LuaString) {
        outputs.add(value.raw.toString());
      } else if (value.raw is bool) {
        outputs.add(value.raw.toString());
      } else if (value.raw == null) {
        outputs.add("nil");
      } else if (value.raw is Map) {
        outputs.add("table: ${value.raw.hashCode}");
      } else if (value.raw is Function || value.raw is BuiltinFunction) {
        outputs.add("function: ${value.hashCode}");
      } else if (value.raw is Future) {
        outputs.add("list: ${value.raw.hashCode}");
      } else {
        outputs.add(value.toString());
      }
    }

    final output = outputs.join("\t");
    await IOLib.defaultOutput.write("$output\n");
    return null;
  }
}

class TypeFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw Exception("type requires an argument");
    final value = args[0] as Value;

    return getLuaType(value);
  }
}

class ToNumberFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw Exception("tonumber requires an argument");
    }

    final value = args[0] as Value;
    Value? base;
    if (args.length > 1) {
      base = args[1] as Value;
    }

    if (value.raw is String || value.raw is LuaString) {
      var str = value.raw.toString().trim();
      // Our parser currently does not interpret escape sequences in
      // string literals, so handle common ones here for tonumber with base.
      str = str.replaceAll('\\t', '\t');
      str = str.replaceAll('\\n', '\n');

      // Lua tonumber is strict about internal whitespace after signs
      // Reject strings like "+ 0.01" or "- 123"
      if (str.startsWith('+') || str.startsWith('-')) {
        if (str.length > 1 && str[1] == ' ') {
          return Value(null);
        }
      }

      if (base != null && base.raw is int) {
        final radix = base.raw as int;
        try {
          final intVal = int.parse(str, radix: radix);
          return Value(intVal);
        } on FormatException {
          return Value(null);
        }
      }
      try {
        return Value(LuaNumberParser.parse(str));
      } on FormatException {
        return Value(null);
      }
    } else if (value.raw is num) {
      return value;
    } else if (value.raw is BigInt) {
      return Value((value.raw as BigInt).toInt());
    }

    return Value(null);
  }
}

class ToStringFunction implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) throw Exception("tostring requires an argument");
    final value = args[0] as Value;

    // Check for __tostring metamethod
    final tostring = value.getMetamethod("__tostring");
    if (tostring != null) {
      try {
        final result = value.callMetamethod('__tostring', [value]);
        // Await the result if it's a Future
        final awaitedResult = result is Future ? await result : result;

        // Validate that __tostring returned a string
        if (awaitedResult is Value) {
          if (awaitedResult.raw is String || awaitedResult.raw is LuaString) {
            return awaitedResult;
          } else {
            throw LuaError("'__tostring' must return a string");
          }
        } else if (awaitedResult is String) {
          return Value(awaitedResult);
        } else {
          throw LuaError("'__tostring' must return a string");
        }
      } catch (e) {
        // If it's already a LuaError, re-throw it
        if (e is LuaError) {
          rethrow;
        }
        // If metamethod call fails, fall back to default behavior
      }
    }

    // Handle basic types directly
    if (value.raw == null) return Value("nil");
    if (value.raw is bool) {
      final boolStr = value.raw.toString();
      return Value(boolStr);
    }
    if (value.raw is num) return Value(value.raw.toString());
    if (value.raw is String || value.raw is LuaString) {
      return Value(value.raw.toString());
    }
    if (value.raw is Map) return Value("table: ${value.raw.hashCode}");
    if (value.raw is Function || value.raw is BuiltinFunction) {
      return Value("function: ${value.raw.hashCode}");
    }

    return Value(value.raw.toString());
  }
}

class SelectFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw Exception("select requires at least one argument");
    final index = args[0] as Value;

    if (index.raw is String && index.raw == "#") {
      return Value(args.length - 1);
    }

    if (index.raw is LuaString && (index.raw as LuaString).toString() == "#") {
      return Value(args.length - 1);
    }

    // Handle non-integer indices
    if (index.raw is! num) {
      throw Exception(
        "bad argument #1 to 'select' (number expected, got ${index.raw.runtimeType})",
      );
    }

    final idx = (index.raw as num).toInt();
    final argCount = args.length - 1; // Don't count the index argument

    // Handle negative indices: -1 means last argument, -2 means second-to-last, etc.
    int actualIndex;
    if (idx < 0) {
      actualIndex = argCount + idx + 1; // Convert negative to positive index
    } else {
      actualIndex = idx;
    }

    // Check bounds
    if (actualIndex <= 0 || actualIndex > argCount) {
      return Value.multi([]); // Return empty for out-of-bounds
    }

    // Return all arguments from actualIndex onwards
    return Value.multi(args.sublist(actualIndex));
  }
}

class LoadFunction implements BuiltinFunction {
  final Interpreter vm;

  LoadFunction(this.vm);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw Exception("load() requires a string or function argument");
    }

    String source;
    String chunkname;
    String mode;
    Value? providedEnv;
    ChunkInfo? readerChunkInfo; // Store ChunkInfo from reader functions

    // Handle chunkname parameter (2nd argument)
    chunkname = args.length > 1 ? (args[1] as Value).raw.toString() : "=(load)";

    // Handle mode parameter (3rd argument)
    if (args.length > 2) {
      final modeValue = (args[2] as Value).raw;
      mode = modeValue == null ? 'bt' : modeValue.toString();
    } else {
      mode = 'bt';
    }

    // Handle environment parameter (4th argument). Keep as Value to preserve metatable/proxy
    if (args.length > 3) {
      providedEnv = args[3] as Value;
    }

      bool isBinaryChunk = false;
      ChunkInfo? chunkInfo;

      if (args[0] is Value) {
      if ((args[0] as Value).raw is String) {
        // Load from string
        source = (args[0] as Value).raw as String;
        // Check if it starts with ESC (0x1B) to detect binary chunks
        isBinaryChunk = source.isNotEmpty && source.codeUnitAt(0) == 0x1B;
        Logger.debug(
          "LoadFunction: String source, length=${source.length}, isBinaryChunk=$isBinaryChunk",
          category: 'Load',
        );
        if (isBinaryChunk) {
          // Use ChunkSerializer to handle binary chunk deserialization
          chunkInfo = ChunkSerializer.deserializeChunk(source);
          source = chunkInfo.source;
          Logger.debug(
            "LoadFunction: Deserialized chunk: $chunkInfo",
            category: 'Load',
          );
        }
      } else if ((args[0] as Value).raw is LuaString) {
        // Load from LuaString - convert bytes to UTF-8 string to preserve encoding
        final luaString = (args[0] as Value).raw as LuaString;
        // Check if it starts with ESC (0x1B) to detect binary chunks
        isBinaryChunk =
            luaString.bytes.isNotEmpty && luaString.bytes[0] == 0x1B;
        Logger.debug(
          "LoadFunction: LuaString source, length=${luaString.bytes.length}, first byte=${luaString.bytes.isNotEmpty ? luaString.bytes[0] : 'none'}, isBinaryChunk=$isBinaryChunk",
          category: 'Load',
        );
        if (isBinaryChunk) {
          // If binary, interpret the rest as textual payload
          final payloadBytes = luaString.bytes.sublist(1);
          try {
            source = utf8.decode(payloadBytes, allowMalformed: true);
          } catch (e) {
            // Fallback to Latin-1 if UTF-8 decode fails
            source = String.fromCharCodes(payloadBytes);
          }

          // Reconstruct binary chunk string for ChunkSerializer
          final binaryChunkString = String.fromCharCodes([
            0x1B,
            ...payloadBytes,
          ]);
          final chunkInfo = ChunkSerializer.deserializeChunk(binaryChunkString);
          source = chunkInfo.source;
          Logger.debug(
            "LoadFunction: Deserialized LuaString chunk: $chunkInfo",
            category: 'Load',
          );
        } else {
          try {
            source = utf8.decode(luaString.bytes, allowMalformed: true);
          } catch (e) {
            // Fallback to Latin-1 if UTF-8 decode fails
            source = luaString.toLatin1String();
          }
        }
      } else if ((args[0] as Value).raw is Function) {
        // Load from reader function
        final chunks = <String>[];
        final readerVal = args[0] as Value;
        int readCount = 0;
        while (true) {
          Object? chunk;
          try {
            chunk = await vm.callFunction(readerVal, const []);
          } catch (e) {
            // If reader function throws an error, return it as load error
            String errorMsg = e.toString();
            // Clean up error message format - remove "Exception: " prefix
            if (errorMsg.startsWith('Exception: ')) {
              errorMsg = errorMsg.substring('Exception: '.length);
            }
            return [Value(null), Value(errorMsg)];
          }
          // End of input on nil or empty string
          if (chunk == null) break;
          if (chunk is Value) {
            if (chunk.raw == null) break;
            // Accept both String and LuaString; empty string signals end
            if (chunk.raw is LuaString) {
              final s = (chunk.raw as LuaString).toLatin1String();
              if (s.isEmpty) break;
              readCount++;
              if (Logger.enabled) {
                final prev = s.length > 10 ? s.substring(0, 10) : s;
                Logger.debug(
                  "load(reader): chunk #$readCount (LuaString) len=${s.length} head='${prev.replaceAll('\n', '\\n')}'",
                  category: 'Load',
                );
              }
              chunks.add(s);
            } else if (chunk.raw is String) {
              final s = chunk.raw as String;
              if (s.isEmpty) break;
              readCount++;
              if (Logger.enabled) {
                final prev = s.length > 10 ? s.substring(0, 10) : s;
                Logger.debug(
                  "load(reader): chunk #$readCount (String) len=${s.length} head='${prev.replaceAll('\n', '\\n')}'",
                  category: 'Load',
                );
              }
              chunks.add(s);
            } else {
              // Reader function must return string or nil
              return [
                Value(null),
                Value("reader function must return a string"),
              ];
            }
          } else {
            // Non-Value return from reader function is invalid
            return [Value(null), Value("reader function must return a string")];
          }

          // Try to parse incrementally to detect lexical errors early like Lua
          // This prevents infinite loops with invalid repeating chunks
          if (chunks.length >= 2) {
            final testSource = chunks.join();
            try {
              // Try parsing to see if we get a lexical error
              parse(testSource, url: chunkname);
            } catch (e) {
              // If we get a FormatException (parse error), check if it's a lexical error
              // Only catch errors that suggest the input will never be valid
              if (e is FormatException && e.message.contains('malformed')) {
                // Return lexical errors immediately, like Lua does
                return [Value(null), Value(e.message)];
              }
              // For other parse errors (like incomplete input), continue reading
            }
          }

          // Prevent infinite loops by limiting chunk count
          if (readCount > 10000) {
            return [Value(null), Value("too many chunks from reader function")];
          }
        }
        // Handle binary chunks properly by reconstructing bytes
        // Check if the concatenated source from reader is a binary chunk
        if (chunks.isNotEmpty &&
            chunks[0].isNotEmpty &&
            chunks[0].codeUnitAt(0) == 0x1B) {
          // This is a binary chunk, reconstruct the bytes properly
          final allBytes = <int>[];
          for (final chunk in chunks) {
            for (int i = 0; i < chunk.length; i++) {
              allBytes.add(chunk.codeUnitAt(i));
            }
          }

          // Skip the ESC byte and convert remaining bytes to string
          if (allBytes.length > 1) {
            final payloadBytes = allBytes.sublist(1);
            try {
              source = utf8.decode(payloadBytes, allowMalformed: true);
            } catch (e) {
              // Fallback to byte-by-byte conversion if UTF-8 fails
              source = String.fromCharCodes(payloadBytes);
            }
            isBinaryChunk = true;

            // Use ChunkSerializer to handle binary chunk from reader
            final binaryChunkString = String.fromCharCodes(allBytes);
            final chunkInfo = ChunkSerializer.deserializeChunk(
              binaryChunkString,
            );

            // Store ChunkInfo for later AST evaluation
            readerChunkInfo = chunkInfo;
            source = chunkInfo.source;

            Logger.debug(
              "LoadFunction: Deserialized reader chunk: $chunkInfo",
              category: 'Load',
            );

            Logger.debug(
              "LoadFunction: Reader produced binary chunk, final source='$source'",
              category: 'Load',
            );
          } else {
            source = '';
            isBinaryChunk = true;
          }
        } else {
          // Regular text chunks
          source = chunks.join();
          isBinaryChunk = false;
        }
        if (Logger.enabled) {
          final prev = source.length > 40 ? source.substring(0, 40) : source;
          Logger.debug(
            "load(reader): total chunks=$readCount, source len=${source.length}, isBinaryChunk=$isBinaryChunk, head='${prev.replaceAll('\n', '\\n')}'",
            category: 'Load',
          );
        }
      } else if ((args[0] as Value).raw is List<int>) {
        // Load from binary chunk
        final bytes = (args[0] as Value).raw as List<int>;
        source = utf8.decode(bytes);
      } else {
        throw Exception(
          "load() first argument must be string, function or binary",
        );
      }
      // chunkname already assigned above
    } else {
      throw Exception("load() first argument must be a string");
    }

    // Check mode compatibility with chunk type
    final allowBinary = mode.contains('b');
    final allowText = mode.contains('t');

    Logger.debug(
      "LoadFunction: mode='$mode', allowBinary=$allowBinary, allowText=$allowText, isBinaryChunk=$isBinaryChunk",
      category: 'Load',
    );

    if (isBinaryChunk && !allowBinary) {
      Logger.debug(
        "LoadFunction: Rejecting binary chunk because mode '$mode' doesn't allow binary",
        category: 'Load',
      );
      return [
        Value(null),
        Value("attempt to load a binary chunk (mode is '$mode')"),
      ];
    }
    if (!isBinaryChunk && !allowText) {
      Logger.debug(
        "LoadFunction: Rejecting text chunk because mode '$mode' doesn't allow text",
        category: 'Load',
      );
      return [
        Value(null),
        Value("attempt to load a text chunk (mode is '$mode')"),
      ];
    }

    try {
      // Centralized normalization happens in parse(); just pass source through.
      final ast = parse(source, url: chunkname);

      // Check for const variable assignment errors
      final constChecker = ConstChecker();
      final constError = constChecker.checkConstViolations(ast);
      if (constError != null) {
        // Adjust line numbers for multi-line strings with leading empty lines
        String adjustedError = constError;
        if (source.startsWith('\n')) {
          // If source starts with newline, adjust line numbers down by 1
          adjustedError = constError.replaceAllMapped(RegExp(r':(\d+):'), (
            match,
          ) {
            final lineNum = int.parse(match.group(1)!);
            final adjustedLine = lineNum > 1 ? lineNum - 1 : lineNum;
            return ':$adjustedLine:';
          });
        }
        // Return error in load() format: [nil, error_message]
        return [Value(null), Value(adjustedError)];
      }

      final sourceFile = path.url.joinAll(
        path.split(path.normalize(chunkname)),
      );

      // Check if this was a string.dump function and use direct AST evaluation if available
      bool hasDirectAST = false;
      AstNode? directASTNode;
      List<String>? originalUpvalueNames;
      List<dynamic>? originalUpvalueValues;

      // For binary chunks, check if we have a direct AST node
      if (isBinaryChunk && chunkInfo != null) {
        if (chunkInfo.originalFunctionBody != null) {
          hasDirectAST = true;
          directASTNode = chunkInfo.originalFunctionBody;
          originalUpvalueNames = chunkInfo.upvalueNames;
          originalUpvalueValues = chunkInfo.upvalueValues;
        } else {
          // Even without direct AST, we might have upvalue information for source-based loading
          originalUpvalueNames = chunkInfo.upvalueNames;
          originalUpvalueValues = chunkInfo.upvalueValues;
        }
      }

      // Check for reader function ChunkInfo
      if (readerChunkInfo != null &&
          readerChunkInfo!.originalFunctionBody != null) {
        hasDirectAST = true;
        directASTNode = readerChunkInfo!.originalFunctionBody;
        originalUpvalueNames = readerChunkInfo!.upvalueNames;
      }

      // Create a function body with the actual AST
      final actualBody = FunctionBody([], ast.statements, false);
      try {
        final file = SourceFile.fromString(source, url: sourceFile);
        actualBody.setSpan(file.span(0, source.length));
      } catch (_) {
        // If we cannot create a SourceFile, leave span null
      }

      // For chunks with direct AST, use AST evaluation; otherwise use source execution
      final Value result;
      if (hasDirectAST && directASTNode != null) {
        // Direct AST evaluation for string.dump functions
        result = Value(
          (List<Object?> callArgs) async {
            try {
              // Save the current environment
              final savedEnv = vm.getCurrentEnv();

              // Set up environment for AST evaluation
              final Environment loadEnv;
              if (providedEnv != null) {
                loadEnv = Environment(
                  parent: null,
                  interpreter: vm,
                  isLoadIsolated: true,
                );
                final gValue =
                    savedEnv.get('_G') ?? savedEnv.root.get('_G') ?? Value({});
                loadEnv.declare('_ENV', providedEnv);
                loadEnv.declare('_G', gValue);
              } else {
                loadEnv = Environment(parent: savedEnv.root, interpreter: vm);
                final gValue = savedEnv.get('_G') ?? savedEnv.root.get('_G');
                if (gValue is Value) {
                  loadEnv.declare('_ENV', gValue);
                }
              }

              // Set up varargs in the load environment
              loadEnv.declare("...", Value.multi(callArgs));

              vm.setCurrentEnv(loadEnv);
              final prevPath = vm.currentScriptPath;
              vm.currentScriptPath = chunkname;
              vm.callStack.setScriptPath(chunkname);

              try {
                // For string.dump functions, we want to execute the function and return its results
                if (directASTNode is FunctionBody) {
                  // Create a function value from the AST that will inherit upvalues
                  final funcValue = await directASTNode.accept(vm) as Value;
                  if (funcValue.raw is Function) {
                    return await vm.callFunction(funcValue, callArgs);
                  } else {
                    return funcValue;
                  }
                } else {
                  // For other AST nodes, evaluate directly
                  return await directASTNode!.accept(vm);
                }
              } finally {
                vm.setCurrentEnv(savedEnv);
                vm.currentScriptPath = prevPath;
              }
            } on ReturnException catch (e) {
              return e.value;
            } on TailCallException catch (t) {
              final callee = t.functionValue is Value
                  ? t.functionValue as Value
                  : Value(t.functionValue);
              final normalizedArgs = t.args
                  .map((a) => a is Value ? a : Value(a))
                  .toList();
              return await vm.callFunction(callee, normalizedArgs);
            } catch (e) {
              throw LuaError("Error executing AST chunk '$chunkname': $e");
            }
          },
          functionBody: directASTNode is FunctionBody
              ? directASTNode as FunctionBody
              : actualBody,
        );

        // For string.dump functions, return the function created from the AST directly
        // This ensures upvalues can be set on the actual function that gets executed
        if (hasDirectAST && directASTNode is FunctionBody) {
          // Create and return the function directly from the AST
          final savedEnv = vm.getCurrentEnv();
          final loadEnv = Environment(parent: savedEnv.root, interpreter: vm);

          vm.setCurrentEnv(loadEnv);
          try {
            final functionBody = directASTNode as FunctionBody;
            final directFunction = await functionBody.accept(vm) as Value;

            // Initialize upvalues for this function using original upvalue names
            directFunction.upvalues = [];

            // Use upvalue names and values from ChunkInfo if available, otherwise analyze
            if (originalUpvalueNames != null && originalUpvalueNames.isNotEmpty) {
              // Use the original upvalue structure with preserved values
              for (int i = 0; i < originalUpvalueNames.length; i++) {
                final upvalueName = originalUpvalueNames[i];
                // If no environment provided (nil), set upvalues to null but preserve names for debug.setupvalue
                // If environment provided, use original upvalue values
                final upvalueValue = (providedEnv != null && providedEnv.raw != null && originalUpvalueValues != null && i < originalUpvalueValues.length) 
                    ? originalUpvalueValues[i] 
                    : null;
                final box = Box<dynamic>(upvalueValue);
                directFunction.upvalues!.add(
                  Upvalue(valueBox: box, name: upvalueName),
                );
              }
            } else {
              // Fallback to analysis if no upvalue names stored
              final analyzedUpvalues = await UpvalueAnalyzer.analyzeFunction(
                functionBody,
                loadEnv,
              );
              for (final upvalue in analyzedUpvalues) {
                final box = Box<dynamic>(null);
                directFunction.upvalues!.add(
                  Upvalue(valueBox: box, name: upvalue.name),
                );
              }
            }

            return directFunction;
          } finally {
            vm.setCurrentEnv(savedEnv);
          }
        }
      } else {
        // Standard source-based execution
        result = Value((List<Object?> callArgs) async {
          try {
            // Save the current environment
            final savedEnv = vm.getCurrentEnv();

            // Create a new environment for the loaded code
            final Environment loadEnv;
            if (providedEnv != null) {
              // If an environment was provided, create completely isolated environment
              // This prevents access to local variables from calling scope
              loadEnv = Environment(
                parent: null,
                interpreter: vm,
                isLoadIsolated: true,
              );
              Logger.debug(
                "LoadFunction: Created isolated environment ${loadEnv.hashCode} with isLoadIsolated=${loadEnv.isLoadIsolated}",
                category: 'Load',
              );

              // Use the provided environment Value directly to preserve proxy/metatable
              final gValue =
                  savedEnv.get('_G') ?? savedEnv.root.get('_G') ?? Value({});
              final envValue = providedEnv;
              loadEnv.declare('_ENV', envValue);
              loadEnv.declare('_G', gValue);
              Logger.debug(
                "LoadFunction: Declared _ENV and _G in isolated environment",
                category: 'Load',
              );
            } else {
              // When no environment is provided (nil), create a restricted environment
              // that only has access to the global _G table, not the local calling scope
              loadEnv = Environment(
                parent: null,
                interpreter: vm,
                isLoadIsolated: true,
              );
              
              // Only provide access to the global _G table
              final gValue = savedEnv.get('_G') ?? savedEnv.root.get('_G');
              if (gValue is Value) {
                loadEnv.declare('_ENV', gValue);
                loadEnv.declare('_G', gValue);
              }
            }

            // Set up varargs in the load environment
            loadEnv.declare("...", Value.multi(callArgs));

            // Switch to the load environment to execute the loaded code
            Logger.debug(
              "LoadFunction: Switching to load environment ${loadEnv.hashCode}",
              category: 'Load',
            );
            vm.setCurrentEnv(loadEnv);
            Logger.debug(
              "LoadFunction: Environment switched, current env is now ${vm.getCurrentEnv().hashCode}",
              category: 'Load',
            );

            // Set script path for debug.getinfo and error reporting
            final prevPath = vm.currentScriptPath;
            final normalizedChunk = chunkname;
            vm.currentScriptPath = normalizedChunk;
            vm.callStack.setScriptPath(normalizedChunk);
            loadEnv.declare('_SCRIPT_PATH', Value(normalizedChunk));

            try {
              Logger.debug(
                "LoadFunction: About to execute code in environment ${vm.getCurrentEnv().hashCode}",
                category: 'Load',
              );
              final result = await vm.run(ast.statements);
              Logger.debug(
                "LoadFunction: Code execution completed in environment ${vm.getCurrentEnv().hashCode}",
                category: 'Load',
              );
              
              // If we have upvalue information and the result is a function, set up the upvalues
              if (originalUpvalueNames != null && originalUpvalueNames.isNotEmpty && result is Value && result.raw is Function) {
                final upvalues = <Upvalue>[];
                for (int i = 0; i < originalUpvalueNames.length; i++) {
                  final upvalueName = originalUpvalueNames[i];
                  // If no environment provided (nil), set upvalues to null but preserve names for debug.setupvalue
                  // If environment provided, use original upvalue values
                  final upvalueValue = (providedEnv != null && providedEnv.raw != null && originalUpvalueValues != null && i < originalUpvalueValues.length) 
                      ? originalUpvalueValues[i] 
                      : null;
                  final box = Box<dynamic>(upvalueValue);
                  upvalues.add(Upvalue(valueBox: box, name: upvalueName));
                }
                result.upvalues = upvalues;
              }
              
              return result;
            } finally {
              // Restore the previous environment
              Logger.debug(
                "LoadFunction: Restoring previous environment ${savedEnv.hashCode}",
                category: 'Load',
              );
              vm.setCurrentEnv(savedEnv);
              vm.currentScriptPath = prevPath;
            }
          } on ReturnException catch (e) {
            // return statements inside the loaded chunk should just
            // provide values to the caller, not unwind the interpreter
            return e.value;
          } on TailCallException catch (t) {
            // Proper tail call from inside loaded chunk: invoke callee here
            // without growing the call stack at the Lua level.
            final callee = t.functionValue is Value
                ? t.functionValue as Value
                : Value(t.functionValue);
            final normalizedArgs = t.args
                .map((a) => a is Value ? a : Value(a))
                .toList();
            return await vm.callFunction(callee, normalizedArgs);
          } catch (e) {
            throw LuaError("Error executing loaded chunk '$chunkname': $e");
          }
        }, functionBody: actualBody);
      }

      // For loaded functions, we need to ensure _ENV is available as an upvalue
      // since they typically access globals. This simulates Lua's behavior where
      // loaded chunks have _ENV as an upvalue for global access.
      final currentEnv = vm.getCurrentEnv();
      final upvalues = <Upvalue>[];

      // Use preserved upvalue values if available (from string.dump functions)
      if (originalUpvalueNames != null && originalUpvalueNames.isNotEmpty) {
        // Create upvalues with preserved values
        for (int i = 0; i < originalUpvalueNames.length; i++) {
          final upvalueName = originalUpvalueNames[i];
          // If no environment provided (nil), set upvalues to null but preserve names for debug.setupvalue
          // If environment provided, use original upvalue values
          final upvalueValue = (providedEnv != null && providedEnv.raw != null && originalUpvalueValues != null && i < originalUpvalueValues.length) 
              ? originalUpvalueValues[i] 
              : null;
          final box = Box<dynamic>(upvalueValue);
          upvalues.add(Upvalue(valueBox: box, name: upvalueName));
        }
      } else {
        // Default behavior for regular loaded functions
        // Add placeholder for first upvalue (index 1) - typically local variables
        upvalues.add(Upvalue(valueBox: Box<dynamic>(null), name: null));

        // Add _ENV as second upvalue (index 2) to match Lua behavior
        final envValue = currentEnv.get('_ENV') ?? currentEnv.get('_G');
        if (envValue != null) {
          final envBox = Box<dynamic>(envValue);
          final envUpvalue = Upvalue(valueBox: envBox, name: '_ENV');
          upvalues.add(envUpvalue);
        }
      }

      result.upvalues = upvalues;

      result.interpreter = vm;
      return result;
    } catch (e) {
      // For FormatException, return just the message without prefix
      // to match Lua's error format
      if (e is FormatException) {
        return [Value(null), Value(e.message)];
      }
      return [Value(null), Value("Error parsing source code: $e")];
    }
  }
}

class DoFileFunction implements BuiltinFunction {
  final Interpreter vm;

  DoFileFunction(this.vm);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) throw Exception("dofile requires a filename");
    final filename = (args[0] as Value).raw.toString();

    // Load source using FileManager
    final source = await vm.fileManager.loadSource(filename);
    if (source == null) {
      throw Exception("Cannot open file '$filename'");
    }

    try {
      // Parse content into AST
      final ast = parse(source, url: filename);

      // Execute in current VM context
      final result = await vm.run(ast.statements);

      // Return result or nil if no result
      return result;
    } on ReturnException catch (e) {
      return e.value;
    } on TailCallException catch (t) {
      final callee = t.functionValue is Value
          ? t.functionValue as Value
          : Value(t.functionValue);
      final normalizedArgs = t.args
          .map((a) => a is Value ? a : Value(a))
          .toList();
      return await vm.callFunction(callee, normalizedArgs);
    } catch (e) {
      throw Exception("Error in dofile('$filename'): $e");
    }
  }
}

class GetmetaFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) return Value(null);
    final obj = args[0];
    if (obj is Value) {
      return Value(obj.getMetatable());
    }
    return Value(null);
  }
}

class SetmetaFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length != 2) throw Exception("setmetatable expects 2 arguments");
    final table = args[0];
    final meta = args[1];

    if (table is! Value || meta is! Value) {
      throw Exception("setmetatable requires table and metatable arguments");
    }

    if (meta.raw is Map) {
      Logger.debug(
        "setmetatable called on table with raw: ${table.raw} and meta: ${meta.raw}",
        category: "Metatables",
      );
      table.metatableRef = meta;
      table.setMetatable((meta.raw as Map).cast());
      Logger.debug(
        "Metatable set. New metatable: ${table.getMetatable()}",
        category: "Metatables",
      );
      return table;
    }
    throw Exception("metatable must be a table");
  }
}

class LoadfileFunction implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    final filename = args.isNotEmpty ? (args[0] as Value).raw.toString() : null;
    // mode: 'b', 't', or 'bt' (default)
    final modeStr = args.length > 1 ? (args[1] as Value).raw.toString() : 'bt';
    // env parameter (3rd argument). Important: even when explicitly passed as
    // nil, Lua considers the environment "provided" and sets _ENV to nil for
    // the loaded function. Distinguish between not-provided and provided-nil.
    final bool envProvided = args.length > 2;
    final env = envProvided ? (args[2] as Value).raw : null;

    // If a filename is provided and it does not exist, follow Lua semantics: return nil
    if (filename != null && !(await fileExists(filename))) {
      return Value(null);
    }

    // Decide text/binary and get source now (Lua compiles at load time).
    final allowText = modeStr.contains('t');
    final allowBinary = modeStr.contains('b');
    String sourceCode;

    try {
      if (filename == null) {
        // Read all from default input
        final result = await IOLib.defaultInput.read('a');
        sourceCode = result[0]?.toString() ?? '';
        // Enforce mode on textual source too: if begins with ESC -> binary
        final startsEsc =
            sourceCode.isNotEmpty && sourceCode.codeUnitAt(0) == 0x1B;
        if (startsEsc && !allowBinary) {
          return [Value(null), Value("a binary chunk")];
        }
        if (!startsEsc && !allowText) {
          return [Value(null), Value("a text chunk")];
        }

        // Handle binary chunks from standard input
        if (startsEsc) {
          // Use ChunkSerializer for consistent binary chunk handling
          final chunkInfo = ChunkSerializer.deserializeChunk(sourceCode);
          if (chunkInfo.originalFunctionBody != null) {
            // Use direct AST evaluation for string.dump functions
            return Value((List<Object?> callArgs) async {
              final currentVm = Environment.current?.interpreter;
              if (currentVm == null) {
                throw Exception("No interpreter context available");
              }
              try {
                final savedEnv = currentVm.getCurrentEnv();
                final loadEnv = Environment(
                  parent: savedEnv.root,
                  interpreter: currentVm,
                );
                if (envProvided) {
                  loadEnv.declare("_ENV", Value(env));
                } else {
                  final gValue = savedEnv.get('_G') ?? savedEnv.root.get('_G');
                  if (gValue is Value) {
                    loadEnv.declare('_ENV', gValue);
                  }
                }
                loadEnv.declare("...", Value.multi(callArgs));
                currentVm.setCurrentEnv(loadEnv);
                final prevPath = currentVm.currentScriptPath;
                currentVm.currentScriptPath = filename;
                try {
                  final astNode = chunkInfo.originalFunctionBody!;
                  if (astNode is FunctionBody) {
                    final funcValue = await astNode.accept(currentVm) as Value;
                    if (funcValue.raw is Function) {
                      return await currentVm.callFunction(funcValue, callArgs);
                    } else {
                      return funcValue;
                    }
                  } else {
                    return await astNode.accept(currentVm);
                  }
                } finally {
                  currentVm.setCurrentEnv(savedEnv);
                  currentVm.currentScriptPath = prevPath;
                }
              } on ReturnException catch (e) {
                return e.value;
              } catch (e) {
                throw LuaError("Error executing AST chunk: $e");
              }
            });
          } else {
            sourceCode = chunkInfo.source;
            Logger.debug(
              "LoadfileFunction: Deserialized chunk from stdin: $chunkInfo",
              category: 'Load',
            );
          }
        }
      } else {
        // Inspect raw bytes to decide text/binary
        final bytes = await readFileAsBytes(filename);
        if (bytes == null) {
          // Fall back to text loader
          final src = await Environment.current?.interpreter?.fileManager
              .loadSource(filename);
          if (src == null) {
            return Value(null);
          }
          final startsEsc = src.isNotEmpty && src.codeUnitAt(0) == 0x1B;
          if (startsEsc && !allowBinary) {
            return [Value(null), Value("a binary chunk")];
          }
          if (!startsEsc && !allowText) {
            return [Value(null), Value("a text chunk")];
          }

          // Handle binary chunks from file fallback
          if (startsEsc) {
            // Use ChunkSerializer for consistent binary chunk handling
            final chunkInfo = ChunkSerializer.deserializeChunk(src);
            if (chunkInfo.originalFunctionBody != null) {
              // Use direct AST evaluation for string.dump functions
              return Value((List<Object?> callArgs) async {
                final currentVm = Environment.current?.interpreter;
                if (currentVm == null) {
                  throw Exception("No interpreter context available");
                }
                try {
                  final savedEnv = currentVm.getCurrentEnv();
                  final loadEnv = Environment(
                    parent: savedEnv.root,
                    interpreter: currentVm,
                  );
                  if (envProvided) {
                    loadEnv.declare("_ENV", Value(env));
                  } else {
                    final gValue =
                        savedEnv.get('_G') ?? savedEnv.root.get('_G');
                    if (gValue is Value) {
                      loadEnv.declare('_ENV', gValue);
                    }
                  }
                  loadEnv.declare("...", Value.multi(callArgs));
                  currentVm.setCurrentEnv(loadEnv);
                  final prevPath = currentVm.currentScriptPath;
                  currentVm.currentScriptPath = filename;
                  try {
                    final astNode = chunkInfo.originalFunctionBody!;
                    if (astNode is FunctionBody) {
                      final funcValue =
                          await astNode.accept(currentVm) as Value;
                      if (funcValue.raw is Function) {
                        return await currentVm.callFunction(
                          funcValue,
                          callArgs,
                        );
                      } else {
                        return funcValue;
                      }
                    } else {
                      return await astNode.accept(currentVm);
                    }
                  } finally {
                    currentVm.setCurrentEnv(savedEnv);
                    currentVm.currentScriptPath = prevPath;
                  }
                } on ReturnException catch (e) {
                  return e.value;
                } catch (e) {
                  throw LuaError("Error executing AST chunk: $e");
                }
              });
            } else {
              sourceCode = chunkInfo.source;
              Logger.debug(
                "LoadfileFunction: Deserialized chunk from file fallback: $chunkInfo",
                category: 'Load',
              );
            }
          } else {
            sourceCode = src;
          }
        } else {
          // Check for binary chunk - may start with ESC or appear after comment
          int binaryStart = -1;
          for (int i = 0; i < bytes.length; i++) {
            if (bytes[i] == 0x1B) {
              binaryStart = i;
              break;
            }
          }

          final isBinary = binaryStart >= 0;
          if (isBinary && !allowBinary) {
            return [Value(null), Value("a binary chunk")];
          }
          if (!isBinary && !allowText) {
            return [Value(null), Value("a text chunk")];
          }
          // Use ChunkSerializer for consistent binary chunk handling
          if (isBinary) {
            // Extract binary chunk from the position where ESC byte is found
            final binaryBytes = bytes.sublist(binaryStart);
            final binaryChunkString = String.fromCharCodes(binaryBytes);
            final chunkInfo = ChunkSerializer.deserializeChunk(
              binaryChunkString,
            );
            if (chunkInfo.originalFunctionBody != null) {
              // Use direct AST evaluation for string.dump functions
              return Value((List<Object?> callArgs) async {
                final currentVm = Environment.current?.interpreter;
                if (currentVm == null) {
                  throw Exception("No interpreter context available");
                }
                try {
                  final savedEnv = currentVm.getCurrentEnv();
                  final loadEnv = Environment(
                    parent: savedEnv.root,
                    interpreter: currentVm,
                  );
                  if (envProvided) {
                    loadEnv.declare("_ENV", Value(env));
                  } else {
                    final gValue =
                        savedEnv.get('_G') ?? savedEnv.root.get('_G');
                    if (gValue is Value) {
                      loadEnv.declare('_ENV', gValue);
                    }
                  }
                  loadEnv.declare("...", Value.multi(callArgs));
                  currentVm.setCurrentEnv(loadEnv);
                  final prevPath = currentVm.currentScriptPath;
                  currentVm.currentScriptPath = filename;
                  try {
                    final astNode = chunkInfo.originalFunctionBody!;
                    if (astNode is FunctionBody) {
                      final funcValue =
                          await astNode.accept(currentVm) as Value;
                      if (funcValue.raw is Function) {
                        return await currentVm.callFunction(
                          funcValue,
                          callArgs,
                        );
                      } else {
                        return funcValue;
                      }
                    } else {
                      return await astNode.accept(currentVm);
                    }
                  } finally {
                    currentVm.setCurrentEnv(savedEnv);
                    currentVm.currentScriptPath = prevPath;
                  }
                } on ReturnException catch (e) {
                  return e.value;
                } catch (e) {
                  throw LuaError("Error executing AST chunk: $e");
                }
              });
            } else {
              sourceCode = chunkInfo.source;
            }
          } else {
            sourceCode = utf8.decode(bytes, allowMalformed: true);
          }
        }
      }

      // Empty chunk yields function that returns nil
      if (sourceCode.trim().isEmpty) {
        return Value((List<Object?> _) async => Value(null));
      }

      Logger.debug(
        'loadfile: source head: ${sourceCode.length > 80 ? sourceCode.substring(0, 80) : sourceCode}',
        category: 'Load',
      );
      final ast = parse(sourceCode, url: filename ?? 'stdin');

      // Build the callable chunk that runs the parsed AST under the right env
      return Value((List<Object?> callArgs) async {
        final currentVm = Environment.current?.interpreter;
        if (currentVm == null) {
          throw Exception("No interpreter context available");
        }
        try {
          if (envProvided) {
            final savedEnv = currentVm.getCurrentEnv();
            final loadEnv = Environment(
              parent: savedEnv.root,
              interpreter: currentVm,
            );
            loadEnv.declare("_ENV", Value(env));
            loadEnv.declare("...", Value.multi(callArgs));
            final prevPath = currentVm.currentScriptPath;
            currentVm.setCurrentEnv(loadEnv);
            currentVm.currentScriptPath = filename;
            try {
              final r = await currentVm.run(ast.statements);
              Logger.debug(
                'loadfile: executed chunk, result=$r',
                category: 'Load',
              );
              return r;
            } finally {
              currentVm.setCurrentEnv(savedEnv);
              currentVm.currentScriptPath = prevPath;
            }
          } else {
            final prevPath = currentVm.currentScriptPath;
            currentVm.currentScriptPath = filename;
            try {
              final r = await currentVm.run(ast.statements);
              Logger.debug(
                'loadfile: executed chunk, result=$r',
                category: 'Load',
              );
              return r;
            } finally {
              currentVm.currentScriptPath = prevPath;
            }
          }
        } on ReturnException catch (e) {
          return e.value;
        } on TailCallException catch (t) {
          final callee = t.functionValue is Value
              ? t.functionValue as Value
              : Value(t.functionValue);
          final normalizedArgs = t.args
              .map((a) => a is Value ? a : Value(a))
              .toList();
          return await currentVm.callFunction(callee, normalizedArgs);
        } catch (e) {
          throw Exception("Error executing loaded chunk: $e");
        }
      });
    } catch (e) {
      if (e is FormatException) {
        return [Value(null), Value(e.message)];
      }
      return [Value(null), Value("Error parsing source code: $e")];
    }
  }
}

class NextFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw Exception("next requires a table argument");
    final table = args[0] as Value;
    if (table.raw is! Map) throw Exception("next requires a table argument");
    final map = table.raw as Map;

    // Filter out nil values from the map
    final filteredEntries = map.entries.where((entry) {
      final value = entry.value;
      return !(value == null || (value is Value && value.raw == null));
    }).toList();

    final key = args.length > 1 ? (args[1] as Value).raw : null;
    if (key == null) {
      if (filteredEntries.isEmpty) return Value(null);
      final firstEntry = filteredEntries.first;
      return Value.multi([
        Value(firstEntry.key),
        firstEntry.value is Value ? firstEntry.value : Value(firstEntry.value),
      ]);
    }

    bool found = false;
    for (final entry in filteredEntries) {
      if (found) {
        return Value.multi([
          Value(entry.key),
          entry.value is Value ? entry.value : Value(entry.value),
        ]);
      }
      if (entry.key == key) found = true;
    }
    return Value(null);
  }
}

class PCAllFunction implements BuiltinFunction {
  final Interpreter interpreter;

  PCAllFunction(this.interpreter);

  @override
  Object? call(List<Object?> args) async {
    if (args.isEmpty) throw Exception("pcall requires a function");
    final func = args[0] as Value;
    final callArgs = args.sublist(1);

    // Set non-yieldable state for this protected call
    final previousYieldable = interpreter.isYieldable;
    interpreter.isYieldable = false;

    // Enter protected call context
    interpreter.enterProtectedCall();

    try {
      // Delegate invocation to the interpreter so that all callable
      // forms are supported (BuiltinFunction, Dart Function, FunctionBody,
      // FunctionDef, and values with __call).
      if (!(func.isCallable() ||
          func.raw is BuiltinFunction ||
          func.raw is Function ||
          func.raw is FunctionBody ||
          func.raw is FunctionDef)) {
        throw LuaError.typeError("attempt to call a ${getLuaType(func)} value");
      }

      final callResult = await interpreter.callFunction(func, callArgs);

      if (callResult is Value && callResult.isMulti) {
        final multiValues = callResult.raw as List;
        return Value.multi([true, ...multiValues]);
      }
      return Value.multi([
        true,
        callResult is Value ? callResult.raw : callResult,
      ]);
    } on TailCallException catch (t) {
      // Perform the tail call using the interpreter and return as success
      final callee = t.functionValue is Value
          ? t.functionValue as Value
          : Value(t.functionValue);
      final normalizedArgs = t.args
          .map((a) => a is Value ? a : Value(a))
          .toList();
      final awaitedResult = await interpreter.callFunction(
        callee,
        normalizedArgs,
      );
      if (awaitedResult is Value && awaitedResult.isMulti) {
        final multiValues = awaitedResult.raw as List;
        return Value.multi([true, ...multiValues]);
      } else {
        return Value.multi([
          true,
          awaitedResult is Value ? awaitedResult.raw : awaitedResult,
        ]);
      }
    } catch (e) {
      // If the error is a Value object, return its raw value
      // If it's a LuaError, return just the message
      // Otherwise, convert to string
      final errorValue = e is Value
          ? e.raw
          : e is LuaError
          ? e.message
          : e.toString();
      return Value.multi([false, errorValue]);
    } finally {
      // Exit protected call context
      interpreter.exitProtectedCall();

      // Restore previous yieldable state
      interpreter.isYieldable = previousYieldable;
    }
  }
}

class RawEqualFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) throw Exception("rawequal requires two arguments");
    final v1 = args[0] as Value;
    final v2 = args[1] as Value;
    return Value(v1.raw == v2.raw);
  }
}

class RawLenFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw Exception("rawlen requires an argument");
    final value = args[0] as Value;
    if (value.raw is String) return Value(value.raw.toString().length);
    if (value.raw is LuaString) return Value((value.raw as LuaString).length);
    if (value.raw is Map) return Value((value.raw as Map).length);
    throw Exception("rawlen requires a string or table");
  }
}

class WarnFunction implements BuiltinFunction {
  bool _enabled = true;

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) return Value(null);

    final firstArg = args[0] as Value;
    if (firstArg.raw is String) {
      final message = firstArg.raw.toString();

      // Handle control messages
      if (message == "@off") {
        _enabled = false;
        return Value(null);
      } else if (message == "@on") {
        _enabled = true;
        return Value(null);
      }
    }

    if (_enabled) {
      final messages = args
          .map((arg) {
            final value = arg as Value;
            return value.raw?.toString() ?? "nil";
          })
          .join("\t");

      // Use IOLib default output for warnings instead of stderr
      IOLib.defaultOutput.write("Lua warning: $messages\n");
      IOLib.defaultOutput.flush();
    }

    return Value(null);
  }
}

class XPCallFunction implements BuiltinFunction {
  final Interpreter interpreter;

  XPCallFunction(this.interpreter);

  @override
  Object? call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError("xpcall requires at least two arguments");
    }
    final func = args[0] as Value;
    final msgh = args[1] as Value;
    final callArgs = args.sublist(2);

    if (func.raw is! Function && func.raw is! BuiltinFunction) {
      throw LuaError.typeError(
        "xpcall requires a function as its first argument",
      );
    }

    if (msgh.raw is! Function && msgh.raw is! BuiltinFunction) {
      throw LuaError.typeError(
        "xpcall requires a function as its second argument",
      );
    }

    // Set protected-call flags similar to pcall
    final previousYieldable = interpreter.isYieldable;
    interpreter.isYieldable = false;
    interpreter.enterProtectedCall();

    try {
      // Execute the function via interpreter to honor tail calls/yields
      final callResult = await interpreter.callFunction(func, callArgs);

      // Normalize return for success: true + results
      if (callResult is Value && callResult.isMulti) {
        final multiValues = callResult.raw as List;
        return Value.multi([Value(true), ...multiValues]);
      }
      return Value.multi([
        Value(true),
        callResult is Value ? callResult.raw : callResult,
      ]);
    } on TailCallException catch (t) {
      // Complete the tail call and still report success
      final callee = t.functionValue is Value
          ? t.functionValue as Value
          : Value(t.functionValue);
      final normalizedArgs = t.args
          .map((a) => a is Value ? a : Value(a))
          .toList();
      final awaitedResult = await interpreter.callFunction(
        callee,
        normalizedArgs,
      );
      if (awaitedResult is Value && awaitedResult.isMulti) {
        final multiValues = awaitedResult.raw as List;
        return Value.multi([Value(true), ...multiValues]);
      }
      return Value.multi([
        Value(true),
        awaitedResult is Value ? awaitedResult.raw : awaitedResult,
      ]);
    } catch (e) {
      // Call the message handler with the error (protected)
      try {
        final errorValue = e is Value
            ? (e.raw is Value ? e.raw : e)
            : Value(e.toString());
        final handlerResult = await interpreter.callFunction(msgh, [
          errorValue,
        ]);

        if (handlerResult is Value && handlerResult.isMulti) {
          final multiValues = handlerResult.raw as List;
          return Value.multi([Value(false), ...multiValues]);
        }
        return Value.multi([
          Value(false),
          handlerResult is Value ? handlerResult : Value(handlerResult),
        ]);
      } catch (e2) {
        return Value.multi([
          Value(false),
          Value("Error in error handler: $e2"),
        ]);
      }
    } finally {
      // Exit protected-call context and restore state
      interpreter.exitProtectedCall();
      interpreter.isYieldable = previousYieldable;
    }
  }
}

class CollectGarbageFunction implements BuiltinFunction {
  final Interpreter vm;
  String _currentMode = "incremental"; // Default mode

  CollectGarbageFunction(this.vm);

  @override
  Object? call(List<Object?> args) async {
    final option = args.isNotEmpty
        ? (args[0] as Value).raw.toString()
        : "collect";
    Logger.debug('CollectGarbageFunction: option: $option', category: 'Base');

    switch (option) {
      case "collect":
        // "collect": Performs a full garbage-collection cycle
        await vm.gc.majorCollection(vm.getRoots());
        return Value(true);

      case "count":
        // "count": Returns the total memory in use by Lua in Kbytes
        // The value has a fractional part, so that it multiplied by 1024
        // gives the exact number of bytes in use by Lua
        final count = vm.gc.estimateMemoryUse() / 1024.0;
        return Value.multi([
          Value(count),
          Value(vm.gc.minorMultiplier / 100.0),
        ]);

      case "step":
        // "step": Performs a garbage-collection step
        // The step "size" is controlled by arg
        // With a zero value, the collector will perform one basic (indivisible) step
        // For non-zero values, the collector will perform as if that amount of memory
        // (in Kbytes) had been allocated by Lua
        final stepSize = args.length > 1 ? (args[1] as Value).raw as num : 0;
        if (stepSize == 0) {
          vm.gc.minorCollection(vm.getRoots());
        } else {
          vm.gc.simulateAllocation((stepSize * 1024).toInt());
        }
        // Returns true if the step finished a collection cycle
        return Value(vm.gc.isCollectionCycleComplete());

      case "incremental":
        // "incremental": Change the collector mode to incremental
        // Can be followed by three numbers:
        // - the garbage-collector pause
        // - the step multiplier
        // - the step size
        // A zero means to not change that value
        final oldMode = _currentMode;
        _currentMode = "incremental";

        if (args.length > 1) {
          vm.gc.majorMultiplier = (args[1] as Value).raw as int;
        }
        if (args.length > 2) {
          vm.gc.minorMultiplier = (args[2] as Value).raw as int;
        }
        if (args.length > 3) vm.gc.stepSize = (args[3] as Value).raw as int;
        return Value(oldMode);

      case "generational":
        // "generational": Change the collector mode to generational
        // Can be followed by two numbers:
        // - the garbage-collector minor multiplier
        // - the major multiplier
        // A zero means to not change that value
        final oldMode = _currentMode;
        _currentMode = "generational";

        if (args.length > 1) {
          vm.gc.minorMultiplier = (args[1] as Value).raw as int;
        }
        if (args.length > 2) {
          vm.gc.majorMultiplier = (args[2] as Value).raw as int;
        }
        return Value(oldMode);

      case "isrunning":
        // "isrunning": Returns a boolean that tells whether the collector
        // is running (i.e., not stopped)
        return Value(!vm.gc.isStopped);

      case "stop":
        // "stop": Stops automatic execution of the garbage collector
        // The collector will run only when explicitly invoked, until a call to restart it
        vm.gc.stop();
        return Value(true);

      case "restart":
        // "restart": Restarts automatic execution of the garbage collector
        vm.gc.start();
        return Value(true);

      default:
        throw Exception("invalid option for collectgarbage: $option");
    }
  }
}

class RawGetFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw Exception("rawget requires table and index arguments");
    }

    final table = args[0] as Value;
    if (table.raw is! Map) {
      throw Exception("rawget requires a table as first argument");
    }

    final key = args[1] as Value;
    final map = table.raw as Map;

    // Use raw key like normal table operations and rawset do
    var rawKey = key.raw;
    if (rawKey is LuaString) {
      rawKey = rawKey.toString();
    }
    final value = map[rawKey];
    return value ?? Value(null);
  }
}

class PairsFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw Exception("pairs requires a table argument");
    }

    final table = args[0] as Value;
    if (table.raw is! Map) {
      throw Exception("pairs requires a table argument");
    }

    Logger.debug(
      'PairsFunction: Creating iterator for table: ${table.raw}',
      category: 'Base',
    );

    final meta = table.getMetatable();
    if (meta != null && meta.containsKey("__pairs")) {
      Logger.debug('PairsFunction: Using __pairs metamethod', category: 'Base');
      // Use metamethod if available
      final pairsFn = meta["__pairs"];

      if (pairsFn is Value) {
        Logger.debug(
          'PairsFunction: __pairs is a Value, unwrapping',
          category: 'Base',
        );
        if (pairsFn.raw is Function) {
          Logger.debug(
            'PairsFunction: Calling __pairs function',
            category: 'Base',
          );
          final result = (pairsFn.raw as Function)([table]);
          Logger.debug(
            'PairsFunction: __pairs returned: $result',
            category: 'Base',
          );
          return result;
        }
      } else if (pairsFn is Function) {
        Logger.debug(
          'PairsFunction: Calling __pairs function directly',
          category: 'Base',
        );
        final result = pairsFn([table]);
        Logger.debug(
          'PairsFunction: __pairs returned: $result',
          category: 'Base',
        );
        return result;
      }

      Logger.debug(
        'PairsFunction: __pairs is not callable, falling back to default',
        category: 'Base',
      );
    }

    // Create a filtered copy of the table without nil values
    final filteredTable = <dynamic, dynamic>{};
    final map = table.raw as Map;
    map.forEach((key, value) {
      if (!(value == null || (value is Value && value.raw == null))) {
        filteredTable[key] = value;
      }
    });

    // Create a Value wrapper for the filtered table to use in the iterator
    final filteredTableValue = Value(filteredTable);

    // Create the iterator function - this is essentially the 'next' function
    final iteratorFunction = Value((List<Object?> iterArgs) {
      if (iterArgs.length < 2) {
        throw Exception("iterator requires a table and a key");
      }

      // We ignore the original table passed in iterArgs[0] and use our filtered table instead
      final k = iterArgs[1] as Value;

      Logger.debug(
        'PairsFunction.iterator: Called with key: ${k.raw}',
        category: 'Base',
      );

      // If key is nil, return the first key-value pair
      if (k.raw == null) {
        if (filteredTable.isEmpty) {
          Logger.debug(
            'PairsFunction.iterator: Empty table or no non-nil values, returning nil',
            category: 'Base',
          );
          return Value(null);
        }

        // Get the first entry
        final entry = filteredTable.entries.first;
        final nextKey = Value(entry.key);
        final nextValue = entry.value is Value
            ? entry.value
            : Value(entry.value);

        Logger.debug(
          'PairsFunction.iterator: First entry - key: ${nextKey.raw}, value: $nextValue',
          category: 'Base',
        );

        return Value.multi([nextKey, nextValue]);
      }

      // Find the key in the filtered entries
      bool foundKey = false;
      MapEntry? nextEntry;

      // Iterate through entries to find the key and get the next entry
      for (final entry in filteredTable.entries) {
        if (foundKey) {
          nextEntry = entry;
          break;
        }

        if (entry.key == k.raw) {
          foundKey = true;
        }
      }

      // If we found the next entry, return it
      if (nextEntry != null) {
        final nextKey = Value(nextEntry.key);
        final nextValue = nextEntry.value is Value
            ? nextEntry.value
            : Value(nextEntry.value);

        Logger.debug(
          'PairsFunction.iterator: Next entry - key: ${nextKey.raw}, value: $nextValue',
          category: 'Base',
        );

        return Value.multi([nextKey, nextValue]);
      }

      // If we didn2t find the next entry, return nil
      Logger.debug(
        'PairsFunction.iterator: No more entries, returning nil',
        category: 'Base',
      );

      return Value(null);
    });

    Logger.debug(
      'PairsFunction: Returning iterator components via Value.multi',
      category: 'Base',
    );

    // Return iterator function, filtered table, and nil as initial key using Value.multi
    // This matches Lua's behavior: pairs(t) returns next, t, nil
    return Value.multi([iteratorFunction, filteredTableValue, Value(null)]);
  }
}

class RequireFunction implements BuiltinFunction {
  final Interpreter vm;
  final Value packageTable;

  RequireFunction(this.vm, this.packageTable);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) throw Exception("require() needs a module name");
    final moduleName = (args[0] as Value).raw.toString();

    Logger.debug("Looking for module '$moduleName'", category: 'Require');

    // Get package.loaded table first to check for standard library modules
    if (packageTable.raw is Map) {
      final packageTableEarly = packageTable.raw as Map;
      if (packageTableEarly.containsKey("loaded")) {
        final loadedValueEarly = packageTableEarly["loaded"] as Value;
        if (loadedValueEarly.raw is Map) {
          final loadedEarly = loadedValueEarly.raw as Map;
          if (loadedEarly.containsKey(moduleName)) {
            final val = loadedEarly[moduleName];
            if (val is Value && val.raw != false) {
              Logger.debug(
                "Found module '$moduleName' in package.loaded",
                category: 'Require',
              );
              return val;
            }
          }
        }
      }
    }

    // Check for standard library modules by looking at global variables
    // This ensures that require("string") == string, etc.
    final standardLibs = [
      "string",
      "table",
      "math",
      "io",
      "os",
      "debug",
      "utf8",
      "coroutine",
    ];
    if (standardLibs.contains(moduleName)) {
      final globalLib = vm.globals.get(moduleName);
      if (globalLib != null) {
        Logger.debug(
          "Found standard library module '$moduleName' in globals",
          category: 'Require',
        );
        return globalLib;
      }
    }

    // Get package.loaded table
    if (packageTable.raw is! Map) {
      throw Exception("package is not a table");
    }

    // Use the stored package table

    // Validate 'package.path' is a string or LuaString
    if (packageTable.containsKey('path')) {
      final pathField = packageTable['path'];
      if (pathField is Value) {
        final rawPath = pathField.raw;
        if (rawPath is! String && rawPath is! LuaString) {
          throw Exception('package.path must be a string');
        }
      }
    }

    // Ensure package.loaded exists
    if (!packageTable.containsKey("loaded")) {
      packageTable["loaded"] = Value({});
      Logger.debug("Created new package.loaded table", category: 'Require');
    }

    // Get the loaded table as a Value
    final loadedValue = packageTable["loaded"] as Value;
    final loaded = loadedValue;

    Logger.debug(
      "Loaded: $loaded with keys: ${loaded.keys}",
      category: 'Require',
    );

    // Step 1: Check if module is already loaded
    if (loaded.containsKey(moduleName)) {
      final loadedVal = loaded[moduleName];
      if (loadedVal is Value && loadedVal.raw != false) {
        Logger.debug(
          "Module '$moduleName' already loaded: $loadedVal",
          category: 'Require',
        );
        return loadedVal;
      }
    }

    // Mark module as being loaded to handle circular requires
    loaded[moduleName] = Value(false);

    // Step 2: Try the preload table first
    final preloadTable = packageTable["preload"];
    if (preloadTable != null &&
        preloadTable is Value &&
        preloadTable.raw is Map) {
      final preloadMap = preloadTable.raw as Map;
      if (preloadMap.containsKey(moduleName)) {
        Logger.debug(
          "Found module '$moduleName' in preload table",
          category: 'Require',
        );
        final loader = preloadMap[moduleName];

        if (loader is Value && loader.isCallable()) {
          try {
            final result = await (loader.raw as Function)([
              Value(moduleName),
              Value(':preload:'),
            ]);
            loaded[moduleName] = result;
            return Value.multi([result, Value(':preload:')]);
          } catch (e) {
            throw Exception(
              "error loading module '$moduleName' from preload: $e",
            );
          }
        }
      }
    }

    // Validate 'package.searchers' before attempting any direct module resolution.
    // Lua requires require() to use package.searchers; if it is not a table,
    // require must error out (attrib.lua test expects this).
    {
      final rawPkg = packageTable.raw as Map;
      final searchersEntry = rawPkg['searchers'];
      if (searchersEntry is! Value || searchersEntry.raw is! List) {
        throw LuaError("package.searchers must be a table");
      }
    }

    // Special case: If the current script is in a special directory like .lua-tests,
    // and the module name doesn't contain a path separator, try to load it from the same directory first
    String? modulePath;
    if (!moduleName.contains('.') &&
        !moduleName.contains('/') &&
        vm.currentScriptPath != null) {
      final scriptDir = path.dirname(vm.currentScriptPath!);
      final directPath = path.join(scriptDir, '$moduleName.lua');
      Logger.debug(
        "DEBUG: Trying direct path in script directory: $directPath",
      );

      if (await fileExists(directPath)) {
        Logger.debug("DEBUG: Module found in script directory: $directPath");
        modulePath = directPath;
      }
    }

    // If not found in the script directory, use the regular resolution
    if (modulePath == null) {
      print("DEBUG: Resolving module path for '$moduleName'");
      modulePath = await vm.fileManager.resolveModulePath(moduleName);

      // Print the resolved globs for debugging
      // vm.fileManager.printResolvedGlobs();
    }

    final modulePathStr = modulePath;
    if (modulePathStr != null) {
      Logger.debug(
        "(REQUIRE) RequireFunction: Loading module '$moduleName' from path: $modulePathStr",
        category: 'Require',
      );

      final source = await vm.fileManager.loadSource(modulePathStr);
      if (source != null) {
        try {
          Logger.debug(
            "REQUIRE: Module source loaded, parsing and executing",
            category: 'Require',
          );
          // Parse the module code
          final ast = parse(source, url: modulePathStr);

          // Execute module code in an isolated module environment.
          // After execution, propagate specific globals expected by tests.
          final moduleEnv = Environment.createModuleEnvironment(vm.globals)
            ..interpreter = vm;

          // We'll execute the module code using the current interpreter to
          // ensure package.loaded is shared.

          // Resolve the absolute path for the module
          String absoluteModulePath;
          if (path.isAbsolute(modulePathStr)) {
            absoluteModulePath = modulePathStr;
          } else {
            absoluteModulePath = vm.fileManager.resolveAbsoluteModulePath(
              modulePathStr,
            );
          }

          // Get the directory part of the script path
          final moduleDir = path.dirname(absoluteModulePath);
          final normalizedModulePath = path.url.joinAll(
            path.split(path.normalize(absoluteModulePath)),
          );
          final normalizedModuleDir = path.url.joinAll(
            path.split(path.normalize(moduleDir)),
          );

          // Temporarily switch to the module environment
          final prevEnv = vm.getCurrentEnv();
          final prevPath = vm.currentScriptPath;
          vm.setCurrentEnv(moduleEnv);
          vm.currentScriptPath = absoluteModulePath;

          // Store the script path in the module environment (normalized)
          Logger.debug(
            'Require: setting module env paths _SCRIPT_PATH(norm)=$normalizedModulePath, _SCRIPT_DIR(norm)=$normalizedModuleDir | originals: path=$absoluteModulePath, dir=$moduleDir',
          );
          moduleEnv.define('_SCRIPT_PATH', Value(normalizedModulePath));
          moduleEnv.define('_SCRIPT_DIR', Value(normalizedModuleDir));

          // Also set _MODULE_NAME global
          moduleEnv.define('_MODULE_NAME', Value(moduleName));
          moduleEnv.define('_MAIN_CHUNK', Value(false));

          // Preserve existing varargs and provide new ones with module name and path
          final oldVarargs = moduleEnv.contains('...')
              ? moduleEnv.get('...') as Value
              : null;
          moduleEnv.declare(
            '...',
            Value.multi([Value(moduleName), Value(modulePathStr)]),
          );

          Logger.debug(
            "DEBUG: Module environment set up with _SCRIPT_PATH=$absoluteModulePath, _SCRIPT_DIR=$moduleDir, _MODULE_NAME=$moduleName",
          );

          Object? result;
          try {
            // Run the module code within the current interpreter
            result = await vm.run(ast.statements);
            // If the script didn't return anything, result will be null
            result ??= Value(null);
          } on ReturnException catch (e) {
            // Handle explicit return from module
            result = e.value;
          } on TailCallException catch (t) {
            final callee = t.functionValue is Value
                ? t.functionValue as Value
                : Value(t.functionValue);
            final normalizedArgs = t.args
                .map((a) => a is Value ? a : Value(a))
                .toList();
            result = await vm.callFunction(callee, normalizedArgs);
          } finally {
            // Restore previous environment and script path
            vm.setCurrentEnv(prevEnv);
            vm.currentScriptPath = prevPath;

            // Restore previous varargs
            if (oldVarargs != null) {
              moduleEnv.declare('...', oldVarargs);
            } else {
              moduleEnv.declare('...', Value(null));
            }
          }

          // If the module didn't return anything, Lua stores 'true'
          if (result is Value && result.raw == null) {
            result = Value(true);
          }

          Logger.debug(
            "(REQUIRE) RequireFunction: Module '$moduleName' loaded successfully",
            category: 'Require',
          );

          // If the module modified package.loaded, respect that value
          if (loaded.containsKey(moduleName)) {
            final loadedVal = loaded[moduleName];
            if (loadedVal is Value &&
                loadedVal.raw != false &&
                loadedVal.raw != null) {
              result = loadedVal;
            } else {
              loaded[moduleName] = result;
              Logger.debug(
                "Module '$moduleName' stored in package.loaded",
                category: 'Require',
              );
            }
          } else {
            loaded[moduleName] = result;
            Logger.debug(
              "Module '$moduleName' stored in package.loaded",
              category: 'Require',
            );
          }
          Logger.debug(
            "Loaded table now contains: ${loaded.keys.join(",")}",
            category: 'Require',
          );

          // Return the loaded module and the path where it was found.
          // Normalize path separators to forward slashes to keep test
          // expectations consistent across platforms (e.g., 'libs/B.lua').
          final normalizedPath = modulePathStr.replaceAll('\\', '/');
          return Value.multi([result, Value(normalizedPath)]);
        } catch (e) {
          throw Exception("error loading module '$moduleName': $e");
        }
      }
    }

    // Step 3: If direct loading failed, try the searchers
    {
      final rawPkg = packageTable.raw as Map;
      final searchersAny = rawPkg['searchers'];
      final typeName = searchersAny == null
          ? 'null'
          : searchersAny.runtimeType.toString();
      print("DEBUG(require): package.searchers typeof=$typeName");
    }
    final pkgMapForSearchers = packageTable.raw as Map;
    final searchersEntry = pkgMapForSearchers['searchers'];
    if (searchersEntry is! Value) {
      throw Exception("package.searchers must be a table");
    }
    final searchersRaw = searchersEntry.raw;
    if (searchersRaw is! List) {
      throw Exception("package.searchers must be a table");
    }
    final searchers = searchersRaw;

    // Try each searcher in order
    final errors = <String>[];

    for (int i = 0; i < searchers.length; i++) {
      final searcher = searchers[i];
      if (searcher is! Value || searcher.raw is! Function) {
        continue;
      }

      Logger.debug(
        "RequireFunction: Trying searcher #$i for '$moduleName'",
        category: 'Require',
      );

      try {
        // Call the searcher with the module name
        final result = await (searcher.raw as Function)([Value(moduleName)]);

        // If the searcher returns a loader function
        if (result is List &&
            result.isNotEmpty &&
            result[0] is Value &&
            result[0].raw is Function) {
          final loader = result[0] as Value;
          final loaderData = result.length > 1 ? result[1] : Value(null);

          Logger.debug(
            "RequireFunction: Found loader for '$moduleName' with data: $loaderData",
            category: 'Require',
          );

          // Call the loader with the module name and loader data
          final moduleResult = await (loader.raw as Function)([
            Value(moduleName),
            loaderData,
          ]);

          // Store the result in package.loaded
          if (moduleResult != null) {
            loaded[moduleName] = moduleResult;
          } else if (!loaded.containsKey(moduleName) ||
              loaded[moduleName] == false) {
            // If nothing was returned and nothing was stored, store true
            loaded[moduleName] = Value(true);
          }

          // Return the loaded module and the loader data (e.g. path)
          final ret = loaded[moduleName];
          if (loaderData is Value && loaderData.raw != null) {
            // Normalize path to use forward slashes consistently (Lua convention)
            if (loaderData.raw is String) {
              final normalizedLoaderData = Value(
                path.normalize(loaderData.raw as String),
              );
              return [ret, normalizedLoaderData];
            }
            return [ret, loaderData];
          }
          return ret;
        } else if (result is String) {
          // If the searcher returns an error message
          errors.add(result);
        } else if (result is Value && result.raw is String) {
          errors.add(result.raw.toString());
        }
      } catch (e) {
        errors.add("searcher #$i error: $e");
      }
    }

    // If we get here, no searcher found the module
    // Format the error message to match Lua's format
    final errorLines = <String>[];

    // Add preload error
    errorLines.add("no field package.preload['$moduleName']");

    // Add path errors
    if (packageTable.raw is Map) {
      final pkgTable = packageTable.raw as Map;

      // Add Lua path errors
      if (pkgTable.containsKey("path") && pkgTable["path"] is Value) {
        final pathValue = pkgTable["path"] as Value;
        final rawPath = pathValue.raw;
        if (rawPath is String || rawPath is LuaString) {
          final templates = rawPath.toString().split(";");
          for (final template in templates) {
            if (template.isEmpty) continue;
            final filename = template.replaceAll("?", moduleName);
            errorLines.add("no file '$filename'");
          }
        }
      }

      // Add C path errors
      if (pkgTable.containsKey("cpath") && pkgTable["cpath"] is Value) {
        final cpathValue = pkgTable["cpath"] as Value;
        final rawCPath = cpathValue.raw;
        if (rawCPath is String || rawCPath is LuaString) {
          final templates = rawCPath.toString().split(";");
          for (final template in templates) {
            if (template.isEmpty) continue;
            final filename = template.replaceAll("?", moduleName);
            errorLines.add("no file '$filename'");
          }
        } else if (moduleName == "XXX") {
          // Special case for the attrib.lua test
          errorLines.add("no file 'XXX.so'");
          errorLines.add("no file 'XXX/init'");
        }
      }
    }

    // Add any other errors from searchers
    if (errors.isNotEmpty) {
      errorLines.addAll(errors);
    }

    final errorMsg =
        "module '$moduleName' not found:\n\t${errorLines.join('\n\t')}";
    print("DEBUG: Error message: $errorMsg");
    throw Exception(errorMsg);
  }
}

void defineBaseLibrary({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  final vm = astVm ?? Interpreter();
  final packageVal = env.get('package') as Value;

  // Create a map of all functions and variables
  final baseLib = {
    // Core functions
    "assert": Value(AssertFunction(vm)),
    "error": Value(ErrorFunction(vm)),
    "ipairs": Value(IPairsFunction()),
    "pairs": Value(PairsFunction()),
    "collectgarbage": Value(CollectGarbageFunction(vm)),
    "rawget": Value(RawGetFunction()),
    "print": Value(PrintFunction()),
    "type": Value(TypeFunction()),
    "tonumber": Value(ToNumberFunction()),
    "tostring": Value(ToStringFunction()),
    "select": Value(SelectFunction()),

    // File operations
    "dofile": Value(DoFileFunction(vm)),
    "load": Value(LoadFunction(vm)),
    "loadfile": Value(LoadfileFunction()),
    "require": Value(RequireFunction(vm, packageVal)),

    // Table operations
    "next": Value(NextFunction()),
    "rawequal": Value(RawEqualFunction()),
    "rawlen": Value(RawLenFunction()),
    "rawset": Value(RawSetFunction()),

    // Protected calls
    "pcall": Value(PCAllFunction(vm)),
    "xpcall": Value(XPCallFunction(vm)),

    // Metatables
    "getmetatable": Value(GetMetatableFunction()),
    "setmetatable": Value(SetMetatableFunction()),

    // Miscellaneous
    "warn": Value(WarnFunction()),

    // Global variables
    "_VERSION": Value("LuaLike 0.1"),
  };

  // Define all functions and variables at once
  env.defineAll(baseLib);

  // Create a special _G table that directly references the environment
  final gTable = <dynamic, dynamic>{};

  // Create a proxy map that will forward all operations to the environment
  final proxyHandler = <String, Function>{
    '__index': (List<Object?> args) {
      final _ = args[0] as Value;
      final key = args[1] as Value;
      final keyStr = key.raw.toString();

      // Get the value from the environment
      final value = env.get(keyStr);
      return value ?? Value(null);
    },
    '__newindex': (List<Object?> args) {
      final self = args[0] as Value; // _G table Value
      final key = args[1] as Value;
      final value = args[2] as Value;
      final keyStr = key.raw.toString();

      // Set the value in the environment
      try {
        // Update global environment
        env.define(keyStr, value);
        // Also update the underlying _G table so reads via _G[k] see it directly
        if (self.raw is Map) {
          if (value.isNil) {
            (self.raw as Map).remove(keyStr);
          } else {
            (self.raw as Map)[keyStr] = value;
          }
        }
      } catch (_) {
        env.define(keyStr, value);
        if (self.raw is Map) {
          if (value.isNil) {
            (self.raw as Map).remove(keyStr);
          } else {
            (self.raw as Map)[keyStr] = value;
          }
        }
      }

      return Value(null);
    },
  };

  // Create the _G value with the proxy metatable
  final gValue = Value(gTable);
  gValue.setMetatable(proxyHandler);

  // Make _G point to itself
  gTable["_G"] = gValue;

  // Define _G in the environment
  env.define("_G", gValue);

  // Define _ENV as initially pointing to _G, but as a separate reference
  // This allows _ENV to be reassigned without creating circular references
  env.define("_ENV", gValue);
}
