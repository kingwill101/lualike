import 'dart:convert';
import 'dart:typed_data';

import 'package:lualike/lualike.dart';
import 'package:lualike/src/const_checker.dart';
import 'package:lualike/src/goto_validator.dart';
import 'package:lualike/src/interpreter/upvalue_analyzer.dart';
import 'package:lualike/src/legacy_ast_chunk_transport.dart';
import 'package:lualike/src/upvalue.dart';
import 'package:path/path.dart' as path;
import 'package:source_span/source_span.dart';

final bool _loadProfileEnabled = getEnvironmentVariable('LUALIKE_PROFILE_LOAD') == '1';

Future<LuaChunkLoadResult> loadChunkWithLegacyAstSupport(
  LuaRuntime runtime,
  LuaChunkLoadRequest request,
) async {
  late String source;
  final chunkname = request.chunkName;
  final mode = request.mode;
  final providedEnv = request.environment;
  LegacyChunkInfo? readerChunkInfo;

  final Stopwatch? totalTimer = _loadProfileEnabled
      ? (Stopwatch()..start())
      : null;
  Stopwatch? parseTimer;
  Duration? parseDuration;
  var loggedProfile = false;

  void logProfile(String phase, {String? error}) {
    if (!_loadProfileEnabled || loggedProfile) {
      return;
    }
    if (totalTimer != null && totalTimer.isRunning) {
      totalTimer.stop();
    }
    final totalMicros = totalTimer?.elapsedMicroseconds ?? -1;
    final parseMicros = parseDuration?.inMicroseconds ?? -1;
    final message = error != null
        ? 'load profile [$phase]: chunk="$chunkname" len=${source.length} '
              'parse_us=$parseMicros total_us=$totalMicros error=$error'
        : 'load profile [$phase]: chunk="$chunkname" len=${source.length} '
              'parse_us=$parseMicros total_us=$totalMicros';
    Logger.info(message, category: 'LoadProfile');
    loggedProfile = true;
  }

  bool isBinaryChunk = false;
  LegacyChunkInfo? chunkInfo;
  final sourceArg = request.source;

  try {
    if (sourceArg.raw is String) {
      source = sourceArg.raw as String;
      isBinaryChunk = source.isNotEmpty && source.codeUnitAt(0) == 0x1B;
      Logger.debug(
        "LoadChunk: String source, length=${source.length}, isBinaryChunk=$isBinaryChunk",
        category: 'Load',
      );
      if (isBinaryChunk) {
        try {
          chunkInfo = LegacyAstChunkTransport.deserializeChunk(source);
          source = chunkInfo.source;
        } catch (e) {
          return LuaChunkLoadResult.failure(_cleanLoadError(e));
        }
      }
    } else if (sourceArg.raw is LuaString) {
      final luaString = sourceArg.raw as LuaString;
      isBinaryChunk = luaString.bytes.isNotEmpty && luaString.bytes[0] == 0x1B;
      Logger.debug(
        "LoadChunk: LuaString source, length=${luaString.bytes.length}, first byte=${luaString.bytes.isNotEmpty ? luaString.bytes[0] : 'none'}, isBinaryChunk=$isBinaryChunk",
        category: 'Load',
      );
      if (isBinaryChunk) {
        try {
          chunkInfo = LegacyAstChunkTransport.deserializeChunkFromLuaString(
            luaString,
          );
          source = chunkInfo.source;
        } catch (e) {
          return LuaChunkLoadResult.failure(_cleanLoadError(e));
        }
      } else {
        try {
          source = utf8.decode(luaString.bytes, allowMalformed: true);
        } catch (_) {
          source = luaString.toLatin1String();
        }
      }
    } else if (sourceArg.raw is Function) {
      final chunks = <String>[];
      var readCount = 0;
      while (true) {
        Object? chunk;
        try {
          chunk = await runtime.callFunction(sourceArg, const []);
        } catch (e) {
          return LuaChunkLoadResult.failure(_cleanLoadError(e));
        }
        if (chunk == null) {
          break;
        }
        if (chunk is! Value) {
          return const LuaChunkLoadResult.failure(
            "reader function must return a string",
          );
        }
        if (chunk.raw == null) {
          break;
        }

        String? text;
        if (chunk.raw is LuaString) {
          text = (chunk.raw as LuaString).toLatin1String();
        } else if (chunk.raw is String) {
          text = chunk.raw as String;
        } else {
          return const LuaChunkLoadResult.failure(
            "reader function must return a string",
          );
        }

        if (text.isEmpty) {
          break;
        }

        readCount++;
        if (Logger.enabled) {
          final prev = text.length > 10 ? text.substring(0, 10) : text;
          Logger.debug(
            "load(reader): chunk #$readCount len=${text.length} head='${prev.replaceAll('\n', '\\n')}'",
            category: 'Load',
          );
        }
        chunks.add(text);

        if (chunks.length >= 2) {
          final testSource = chunks.join();
          try {
            parse(testSource, url: chunkname);
          } catch (e) {
            if (e is FormatException && e.message.contains('malformed')) {
              return LuaChunkLoadResult.failure(e.message);
            }
          }
        }

        if (readCount > 10000) {
          return const LuaChunkLoadResult.failure(
            "too many chunks from reader function",
          );
        }
      }

      if (chunks.isNotEmpty &&
          chunks.first.isNotEmpty &&
          chunks.first.codeUnitAt(0) == 0x1B) {
        final allBytes = <int>[];
        for (final chunk in chunks) {
          for (var i = 0; i < chunk.length; i++) {
            allBytes.add(chunk.codeUnitAt(i));
          }
        }

        if (allBytes.length > 1) {
          final payloadBytes = allBytes.sublist(1);
          try {
            source = utf8.decode(payloadBytes, allowMalformed: true);
          } catch (_) {
            source = String.fromCharCodes(payloadBytes);
          }
          isBinaryChunk = true;

          final binaryChunkLuaString = LuaString.fromBytes(
            Uint8List.fromList(allBytes),
          );
          try {
            readerChunkInfo =
                LegacyAstChunkTransport.deserializeChunkFromLuaString(
                  binaryChunkLuaString,
                );
            source = readerChunkInfo.source;
          } catch (e) {
            return LuaChunkLoadResult.failure(_cleanLoadError(e));
          }
        } else {
          source = '';
          isBinaryChunk = true;
        }
      } else {
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
    } else if (sourceArg.raw is List<int>) {
      source = utf8.decode(sourceArg.raw as List<int>);
    } else {
      throw LuaError(
        "load() first argument must be string, function or binary",
      );
    }
  } on LuaError catch (e) {
    return LuaChunkLoadResult.failure(e.message);
  }

  final allowBinary = mode.contains('b');
  final allowText = mode.contains('t');

  Logger.debug(
    "LoadChunk: mode='$mode', allowBinary=$allowBinary, allowText=$allowText, isBinaryChunk=$isBinaryChunk",
    category: 'Load',
  );

  if (isBinaryChunk && !allowBinary) {
    return LuaChunkLoadResult.failure(
      "attempt to load a binary chunk (mode is '$mode')",
    );
  }
  if (!isBinaryChunk && !allowText) {
    return LuaChunkLoadResult.failure(
      "attempt to load a text chunk (mode is '$mode')",
    );
  }

  try {
    if (_loadProfileEnabled) {
      parseTimer = Stopwatch()..start();
    }
    final ast = parse(source, url: chunkname);
    if (parseTimer != null) {
      parseTimer.stop();
      parseDuration = parseTimer.elapsed;
    }

    // Skip whole-AST validation passes when the source text cannot possibly
    // contain the relevant syntax. Repeated simple text loads in gc.lua spend a
    // large amount of time here otherwise.
    if (source.contains('<')) {
      final constChecker = ConstChecker();
      final constError = constChecker.checkConstViolations(ast);
      if (constError != null) {
        var adjustedError = constError;
        if (source.startsWith('\n')) {
          adjustedError = constError.replaceAllMapped(RegExp(r':(\d+):'), (
            match,
          ) {
            final lineNum = int.parse(match.group(1)!);
            final adjustedLine = lineNum > 1 ? lineNum - 1 : lineNum;
            return ':$adjustedLine:';
          });
        }
        logProfile('const-error', error: adjustedError);
        return LuaChunkLoadResult.failure(adjustedError);
      }
    }

    if (source.contains('goto') || source.contains('::')) {
      final gotoValidator = GotoLabelValidator();
      final gotoError = gotoValidator.checkGotoLabelViolations(ast);
      if (gotoError != null) {
        logProfile('goto-error', error: gotoError);
        return LuaChunkLoadResult.failure(gotoError);
      }
    }

    final sourceFile = path.url.joinAll(path.split(path.normalize(chunkname)));

    var hasDirectAst = false;
    AstNode? directAstNode;
    List<String>? originalUpvalueNames;
    List<dynamic>? originalUpvalueValues;

    if (isBinaryChunk && chunkInfo != null) {
      if (chunkInfo.originalFunctionBody != null) {
        hasDirectAst = true;
        directAstNode = chunkInfo.originalFunctionBody;
        originalUpvalueNames = chunkInfo.upvalueNames;
        originalUpvalueValues = chunkInfo.upvalueValues;
      } else {
        originalUpvalueNames = chunkInfo.upvalueNames;
        originalUpvalueValues = chunkInfo.upvalueValues;
      }
    }

    if (readerChunkInfo != null &&
        readerChunkInfo.originalFunctionBody != null) {
      hasDirectAst = true;
      directAstNode = readerChunkInfo.originalFunctionBody;
      originalUpvalueNames = readerChunkInfo.upvalueNames;
    }

    final actualBody = FunctionBody([], ast.statements, false);
    final singleTopLevelStatement = ast.statements.length == 1
        ? ast.statements.first
        : null;
    final hasSimpleTopLevelFunctionDef = singleTopLevelStatement is FunctionDef;
    try {
      final file = SourceFile.fromString(source, url: sourceFile);
      actualBody.setSpan(file.span(0, source.length));
    } catch (_) {
      // Leave span null if SourceFile cannot be constructed.
    }

    final Value result;
    if (hasDirectAst && directAstNode != null) {
      final loadedAstNode = directAstNode;
      result = Value(
        (List<Object?> callArgs) async {
          try {
            final savedEnv = runtime.getCurrentEnv();
            final loadEnv = _createDirectAstExecutionEnv(
              runtime: runtime,
              savedEnv: savedEnv,
              providedEnv: providedEnv,
            );

            loadEnv.declare("...", Value.multi(callArgs));
            runtime.setCurrentEnv(loadEnv);
            final prevPath = runtime.currentScriptPath;
            runtime.currentScriptPath = chunkname;
            runtime.callStack.setScriptPath(chunkname);

            try {
              if (loadedAstNode is FunctionBody) {
                final funcValue = await runtime.evaluateAst(loadedAstNode)
                    as Value;
                if (funcValue.raw is Function || funcValue.raw is BuiltinFunction) {
                  return await runtime.callFunction(funcValue, callArgs);
                }
                return funcValue;
              }
              return await runtime.evaluateAst(loadedAstNode);
            } finally {
              runtime.setCurrentEnv(savedEnv);
              runtime.currentScriptPath = prevPath;
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
            return await runtime.callFunction(callee, normalizedArgs);
          } catch (e) {
            throw LuaError("Error executing AST chunk '$chunkname': $e");
          }
        },
        functionBody: loadedAstNode is FunctionBody ? loadedAstNode : actualBody,
        closureEnvironment: runtime.getCurrentEnv(),
      );

      if (loadedAstNode is FunctionBody) {
        final savedEnv = runtime.getCurrentEnv();
        final loadEnv = _createDirectAstFunctionCreationEnv(
          runtime: runtime,
          savedEnv: savedEnv,
          providedEnv: providedEnv,
        );

        runtime.setCurrentEnv(loadEnv);
        try {
          final directFunction = await runtime.evaluateAst(loadedAstNode) as Value;
          directFunction.upvalues = [];

          if (originalUpvalueNames != null && originalUpvalueNames.isNotEmpty) {
            for (var i = 0; i < originalUpvalueNames.length; i++) {
              final upvalueName = originalUpvalueNames[i];
              final upvalueValue =
                  (providedEnv != null &&
                          providedEnv.raw != null &&
                          originalUpvalueValues != null &&
                          i < originalUpvalueValues.length)
                      ? originalUpvalueValues[i]
                      : null;
              final box = Box<dynamic>(upvalueValue);
              final upvalue = Upvalue(
                valueBox: box,
                name: upvalueName,
                interpreter: runtime,
              );
              upvalue.close();
              directFunction.upvalues!.add(upvalue);
            }
          } else {
            final analyzedUpvalues = await UpvalueAnalyzer.analyzeFunction(
              loadedAstNode,
              loadEnv,
            );
            for (final analyzed in analyzedUpvalues) {
              final box = Box<dynamic>(null);
              final upvalue = Upvalue(
                valueBox: box,
                name: analyzed.name,
                interpreter: runtime,
              );
              upvalue.close();
              directFunction.upvalues!.add(upvalue);
            }
          }

          directFunction.interpreter = runtime;
          logProfile('success');
          return LuaChunkLoadResult.success(directFunction);
        } finally {
          runtime.setCurrentEnv(savedEnv);
        }
      }
    } else {
      result = Value(
        (List<Object?> callArgs) async {
          try {
            final savedEnv = runtime.getCurrentEnv();
            final loadEnv = _createSourceLoadEnv(
              runtime: runtime,
              savedEnv: savedEnv,
              providedEnv: providedEnv,
            );

            loadEnv.declare("...", Value.multi(callArgs));
            runtime.setCurrentEnv(loadEnv);
            final prevPath = runtime.currentScriptPath;
            runtime.currentScriptPath = chunkname;
            runtime.callStack.setScriptPath(chunkname);
            loadEnv.declare('_SCRIPT_PATH', Value(chunkname));

            try {
              Object? executionResult;
              if (hasSimpleTopLevelFunctionDef) {
                await runtime.evaluateAst(singleTopLevelStatement);
              } else {
                executionResult = await runtime.runAst(ast.statements);
              }
              if (originalUpvalueNames != null &&
                  originalUpvalueNames.isNotEmpty &&
                  executionResult is Value &&
                  executionResult.raw is Function) {
                final upvalues = <Upvalue>[];
                for (var i = 0; i < originalUpvalueNames.length; i++) {
                  final upvalueName = originalUpvalueNames[i];
                  final upvalueValue =
                      (providedEnv != null &&
                              providedEnv.raw != null &&
                              originalUpvalueValues != null &&
                              i < originalUpvalueValues.length)
                          ? originalUpvalueValues[i]
                          : null;
                  final box = Box<dynamic>(upvalueValue);
                  final uv = Upvalue(
                    valueBox: box,
                    name: upvalueName,
                    interpreter: runtime,
                  );
                  upvalues.add(uv);
                }
                executionResult.upvalues = upvalues;
              }

              logProfile('success');
              return executionResult;
            } finally {
              runtime.setCurrentEnv(savedEnv);
              runtime.currentScriptPath = prevPath;
            }
          } on ReturnException catch (e) {
            logProfile('success');
            return e.value;
          } on TailCallException catch (t) {
            final callee = t.functionValue is Value
                ? t.functionValue as Value
                : Value(t.functionValue);
            final normalizedArgs = t.args
                .map((a) => a is Value ? a : Value(a))
                .toList();
            final value = await runtime.callFunction(callee, normalizedArgs);
            logProfile('success');
            return value;
          } catch (e) {
            throw LuaError("Error executing loaded chunk '$chunkname': $e");
          }
        },
        functionBody: actualBody,
        closureEnvironment: runtime.getCurrentEnv(),
      );
    }

    final currentEnv = runtime.getCurrentEnv();
    final upvalues = <Upvalue>[];

    if (originalUpvalueNames != null && originalUpvalueNames.isNotEmpty) {
      for (var i = 0; i < originalUpvalueNames.length; i++) {
        final upvalueName = originalUpvalueNames[i];
        final upvalueValue =
            (providedEnv != null &&
                    providedEnv.raw != null &&
                    originalUpvalueValues != null &&
                    i < originalUpvalueValues.length)
                ? originalUpvalueValues[i]
                : null;
        final box = Box<dynamic>(upvalueValue);
        final upvalue = Upvalue(
          valueBox: box,
          name: upvalueName,
          interpreter: runtime,
        );
        upvalue.close();
        upvalues.add(upvalue);
      }
    } else {
      final placeholder = Upvalue(
        valueBox: Box<dynamic>(null),
        name: null,
        interpreter: runtime,
      );
      placeholder.close();
      upvalues.add(placeholder);

      final envValue = currentEnv.get('_ENV') ?? currentEnv.get('_G');
      if (envValue != null) {
        final envBox = Box<dynamic>(envValue);
        final envUpvalue = Upvalue(
          valueBox: envBox,
          name: '_ENV',
          interpreter: runtime,
        );
        envUpvalue.close();
        upvalues.add(envUpvalue);
      }
    }

    result.upvalues = upvalues;
    result.interpreter = runtime;
    logProfile('success');
    return LuaChunkLoadResult.success(result);
  } catch (e) {
    if (e is FormatException) {
      logProfile('parse-error', error: e.message);
      return LuaChunkLoadResult.failure(e.message);
    }
    logProfile('parse-error', error: e.toString());
    return LuaChunkLoadResult.failure("Error parsing source code: $e");
  }
}

Object? dumpFunctionWithLegacyAstTransport(Value function) {
  if (function.raw is BuiltinFunction) {
    throw LuaError("unable to dump given function");
  }

  final fb = function.functionBody;
  if (fb != null) {
    Logger.debug(
      'string.dump: function has functionBody, span=${fb.span}, sourceUrl=${fb.span?.sourceUrl}',
      category: 'StringLib',
    );

    List<String>? upvalueNames;
    List<dynamic>? upvalueValues;
    if (function.upvalues != null && function.upvalues!.isNotEmpty) {
      upvalueNames = function.upvalues!
          .map((upvalue) => upvalue.name ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
      upvalueValues = function.upvalues!.map((upvalue) {
        final value = upvalue.getValue();
        final rawValue = value is Value ? value.raw : value;
        if (rawValue is String ||
            rawValue is num ||
            rawValue is bool ||
            rawValue == null) {
          return rawValue;
        }
        return rawValue.toString();
      }).toList();
    }

    return LegacyAstChunkTransport.serializeFunctionAsLuaString(
      fb,
      upvalueNames,
      upvalueValues,
    );
  }

  final source = "return function(...) end";
  final payload = utf8.encode(source);
  final bytes = Uint8List(payload.length + 1);
  bytes[0] = 0x1B;
  bytes.setRange(1, bytes.length, payload);
  return String.fromCharCodes(bytes);
}

LuaFunctionDebugInfo? defaultDebugInfoForFunction(
  LuaRuntime runtime,
  Value function,
) {
  final raw = function.raw;
  if (raw is LuaCallableArtifact && raw.debugInfo != null) {
    return raw.debugInfo;
  }

  final functionBody = function.functionBody;
  if (functionBody != null) {
    final span = functionBody.span;
    final source = span?.sourceUrl?.toString() ?? runtime.currentScriptPath;
    if (source != null) {
      return LuaFunctionDebugInfo(
        source: source,
        shortSource: _shortSource(source),
        lineDefined: span != null ? span.start.line + 1 : -1,
        lastLineDefined: span != null ? span.end.line + 1 : -1,
        nups: function.upvalues?.length ?? 0,
        nparams: functionBody.parameters?.length ?? 0,
        isVararg: functionBody.isVararg,
      );
    }
  }

  if (runtime.currentScriptPath != null) {
    final source = runtime.currentScriptPath!;
    return LuaFunctionDebugInfo(
      source: source,
      shortSource: _shortSource(source),
      what: 'Lua',
      nups: function.upvalues?.length ?? 0,
    );
  }

  if (raw is Function || raw is BuiltinFunction) {
    return const LuaFunctionDebugInfo(
      source: '=[C]',
      shortSource: '[C]',
      what: 'C',
      isVararg: true,
    );
  }

  return null;
}

Environment _createDirectAstExecutionEnv({
  required LuaRuntime runtime,
  required Environment savedEnv,
  required Value? providedEnv,
}) {
  final Environment loadEnv;
  if (providedEnv != null) {
    loadEnv = Environment(
      parent: null,
      interpreter: runtime,
      isLoadIsolated: true,
    );
    final gValue = savedEnv.get('_G') ?? savedEnv.root.get('_G') ?? Value({});
    loadEnv.declare('_ENV', providedEnv);
    loadEnv.declare('_G', gValue);
  } else {
    loadEnv = Environment(parent: savedEnv.root, interpreter: runtime);
    final gValue = savedEnv.get('_G') ?? savedEnv.root.get('_G');
    if (gValue is Value) {
      loadEnv.declare('_ENV', gValue);
    }
  }
  return loadEnv;
}

Environment _createDirectAstFunctionCreationEnv({
  required LuaRuntime runtime,
  required Environment savedEnv,
  required Value? providedEnv,
}) {
  final loadEnv = Environment(parent: savedEnv.root, interpreter: runtime);
  if (providedEnv != null) {
    if (providedEnv.raw != null) {
      loadEnv.declare('_ENV', providedEnv);
      final gValue = savedEnv.get('_G') ?? savedEnv.root.get('_G');
      if (gValue is Value) {
        loadEnv.declare('_G', gValue);
      }
    } else {
      loadEnv.declare('_ENV', providedEnv);
    }
  }
  return loadEnv;
}

Environment _createSourceLoadEnv({
  required LuaRuntime runtime,
  required Environment savedEnv,
  required Value? providedEnv,
}) {
  final loadEnv = Environment(
    parent: null,
    interpreter: runtime,
    isLoadIsolated: true,
  );
  if (providedEnv != null) {
    final gValue = savedEnv.get('_G') ?? savedEnv.root.get('_G') ?? Value({});
    loadEnv.declare('_ENV', providedEnv);
    loadEnv.declare('_G', gValue);
  } else {
    final gValue = savedEnv.get('_G') ?? savedEnv.root.get('_G');
    if (gValue is Value) {
      loadEnv.declare('_ENV', gValue);
      loadEnv.declare('_G', gValue);
    }
  }
  return loadEnv;
}

String _cleanLoadError(Object error) {
  var errorMsg = error.toString();
  if (errorMsg.startsWith('Exception: ')) {
    errorMsg = errorMsg.substring('Exception: '.length);
  }
  return errorMsg;
}

String _shortSource(String source) {
  try {
    return path.basename(source);
  } catch (_) {
    return source;
  }
}
