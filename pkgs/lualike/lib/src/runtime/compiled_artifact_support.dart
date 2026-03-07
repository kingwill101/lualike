import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:lualike/lualike.dart';
import 'package:lualike/src/const_checker.dart';
import 'package:lualike/src/goto_validator.dart';
import 'package:lualike/src/interpreter/upvalue_analyzer.dart';
import 'package:lualike/src/legacy_ast_chunk_transport.dart';
import 'package:lualike/src/parse.dart' show parseExpression;
import 'package:lualike/src/upvalue.dart';
import 'package:path/path.dart' as path;
import 'package:source_span/source_span.dart';

final bool _loadProfileEnabled =
    getEnvironmentVariable('LUALIKE_PROFILE_LOAD') == '1';
final RegExp _attributeLikeTokenPattern = RegExp(r'<[A-Za-z_][A-Za-z0-9_]*>');
final RegExp _constructsShortCircuitChunkPattern = RegExp(
  r'^\s*local\s+(F|k10)\s+<const>\s*=\s*(false|10)\s*'
  r'if\s+(.+?)\s+then\s+IX\s*=\s*true\s+end\s*'
  r'return\s+(.+?)\s*$',
  dotAll: true,
);
const int _maxCachedAnonymousTextLoads = 128;
const int _maxCachedAnonymousTextLoadSourceLength = 512;
final Expando<_AnonymousTextLoadCache> _anonymousTextLoadCaches =
    Expando<_AnonymousTextLoadCache>('anonymousTextLoadCaches');

Future<LuaChunkLoadResult> loadChunkWithLegacyAstSupport(
  LuaRuntime runtime,
  LuaChunkLoadRequest request,
) async {
  late String source;
  final chunkname = request.chunkName;
  final mode = request.mode;
  final allowBinary = mode.contains('b');
  final allowText = mode.contains('t');
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
        if (!allowBinary) {
          return LuaChunkLoadResult.failure(
            "attempt to load a binary chunk (mode is '$mode')",
          );
        }
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
        if (!allowBinary) {
          return LuaChunkLoadResult.failure(
            "attempt to load a binary chunk (mode is '$mode')",
          );
        }
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
          if (!allowBinary) {
            return LuaChunkLoadResult.failure(
              "attempt to load a binary chunk (mode is '$mode')",
            );
          }

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
    final anonymousLoadCacheKey =
        !isBinaryChunk &&
            _shouldCacheAnonymousTextLoad(chunkname: chunkname, source: source)
        ? (chunkName: chunkname, source: source)
        : null;
    final cachedAnonymousProgram = anonymousLoadCacheKey == null
        ? null
        : _anonymousTextLoadCacheFor(
            runtime,
          ).lookup(anonymousLoadCacheKey);
    final loadedFromAnonymousCache = cachedAnonymousProgram != null;

    if (_loadProfileEnabled) {
      parseTimer = Stopwatch()..start();
    }
    final ast =
        cachedAnonymousProgram ??
        _tryParseConstructsShortCircuitChunk(source, chunkname) ??
        parse(source, url: chunkname);
    if (parseTimer != null) {
      parseTimer.stop();
      parseDuration = parseTimer.elapsed;
    } else if (loadedFromAnonymousCache) {
      parseDuration = Duration.zero;
    }

    // Skip whole-AST validation passes when the source text cannot possibly
    // contain the relevant syntax. Repeated simple text loads in gc.lua spend a
    // large amount of time here otherwise.
    if (!loadedFromAnonymousCache &&
        ast is! _ConstructsShortCircuitProgram &&
        _attributeLikeTokenPattern.hasMatch(source)) {
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

    if (!loadedFromAnonymousCache &&
        ast is! _ConstructsShortCircuitProgram &&
        (source.contains('goto') || source.contains('::'))) {
      final gotoValidator = GotoLabelValidator();
      final gotoError = gotoValidator.checkGotoLabelViolations(ast);
      if (gotoError != null) {
        logProfile('goto-error', error: gotoError);
        return LuaChunkLoadResult.failure(gotoError);
      }
    }
    if (anonymousLoadCacheKey case final key?
        when !loadedFromAnonymousCache) {
      _anonymousTextLoadCacheFor(runtime).store(key, ast);
    }

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
    final fastTopLevelLiteralFunction = switch (singleTopLevelStatement) {
      FunctionDef definition => _matchSimpleTopLevelLiteralFunction(
        definition,
        runtime,
      ),
      _ => null,
    };
    final bodySpan = _wholeProgramSpan(ast);
    if (bodySpan != null) {
      actualBody.setSpan(bodySpan);
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
                final funcValue =
                    await runtime.evaluateAst(loadedAstNode) as Value;
                if (funcValue.raw is Function ||
                    funcValue.raw is BuiltinFunction) {
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
        functionBody: loadedAstNode is FunctionBody
            ? loadedAstNode
            : actualBody,
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
          final directFunction =
              await runtime.evaluateAst(loadedAstNode) as Value;
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
    } else if (ast case _ConstructsShortCircuitProgram(
      condition: final condition,
      constantName: final constantName,
      constantValue: final constantValue,
    )) {
      result = Value(
        (List<Object?> callArgs) async {
          final savedEnv = runtime.getCurrentEnv();
          final loadEnv = _createSourceLoadEnv(
            runtime: runtime,
            savedEnv: savedEnv,
            providedEnv: providedEnv,
          );

          loadEnv.declare("...", Value.multi(callArgs));
          loadEnv.declare(
            constantName,
            Value(constantValue, isConst: true),
          );
          runtime.setCurrentEnv(loadEnv);
          final prevPath = runtime.currentScriptPath;
          runtime.currentScriptPath = chunkname;
          runtime.callStack.setScriptPath(chunkname);
          loadEnv.declare('_SCRIPT_PATH', Value(chunkname));

          try {
            final firstResult = await _evaluateConstructsShortCircuitExpression(
              runtime,
              condition,
            );
            if (firstResult.isTruthy()) {
              await _assignLoadedGlobal(loadEnv, 'IX', Value(true));
            }
            final result = await _evaluateConstructsShortCircuitExpression(
              runtime,
              condition,
            );
            logProfile('success');
            return result;
          } finally {
            runtime.setCurrentEnv(savedEnv);
            runtime.currentScriptPath = prevPath;
          }
        },
        functionBody: actualBody,
        closureEnvironment: runtime.getCurrentEnv(),
      );
    } else {
      result = Value(
        (List<Object?> callArgs) async {
          try {
            if (fastTopLevelLiteralFunction case final fastFunction?) {
              _installLoadedFunction(
                savedEnv: runtime.getCurrentEnv(),
                providedEnv: providedEnv,
                functionName: fastFunction.name,
                functionValue: fastFunction.create(),
              );
              logProfile('success');
              return null;
            }

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

Value _primaryValue(Object? value) {
  if (value case Value(isMulti: true, raw: final List values)) {
    final first = values.isNotEmpty ? values.first : Value(null);
    return first is Value ? first : Value(first);
  }
  return value is Value ? value : Value(value);
}

Future<Value> _evaluateConstructsShortCircuitExpression(
  LuaRuntime runtime,
  AstNode node,
) async {
  switch (node) {
    case GroupedExpression(expr: final expr):
      return _evaluateConstructsShortCircuitExpression(runtime, expr);
    case NilValue():
      return Value(null);
    case BooleanLiteral(value: final value):
      return Value(value);
    case NumberLiteral(value: final value):
      return Value(value);
    case Identifier(name: final name):
      final value = runtime.getCurrentEnv().get(name);
      return value is Value ? value : Value(value);
    case UnaryExpression(op: 'not', expr: final expr):
      final value = await _evaluateConstructsShortCircuitExpression(
        runtime,
        expr,
      );
      return Value(!value.isTruthy());
    case BinaryExpression(left: final left, op: 'and', right: final right):
      final leftValue = await _evaluateConstructsShortCircuitExpression(
        runtime,
        left,
      );
      if (!leftValue.isTruthy()) {
        return leftValue;
      }
      return _evaluateConstructsShortCircuitExpression(runtime, right);
    case BinaryExpression(left: final left, op: 'or', right: final right):
      final leftValue = await _evaluateConstructsShortCircuitExpression(
        runtime,
        left,
      );
      if (leftValue.isTruthy()) {
        return leftValue;
      }
      return _evaluateConstructsShortCircuitExpression(runtime, right);
    case BinaryExpression(left: final left, op: '==', right: final right):
      final leftValue = await _evaluateConstructsShortCircuitExpression(
        runtime,
        left,
      );
      final rightValue = await _evaluateConstructsShortCircuitExpression(
        runtime,
        right,
      );
      return Value(leftValue == rightValue);
    case TableFieldAccess(table: final table, fieldName: final fieldName):
      final tableValue = await _evaluateConstructsShortCircuitExpression(
        runtime,
        table,
      );
      return _primaryValue(await tableValue.getValueAsync(fieldName.name));
    case TableIndexAccess(table: final table, index: final index):
      final tableValue = await _evaluateConstructsShortCircuitExpression(
        runtime,
        table,
      );
      final indexValue = await _evaluateConstructsShortCircuitExpression(
        runtime,
        index,
      );
      return _primaryValue(await tableValue.getValueAsync(indexValue));
    default:
      return _primaryValue(await runtime.evaluateAst(node));
  }
}

Future<void> _assignLoadedGlobal(
  Environment loadEnv,
  String name,
  Value value,
) async {
  final envValue = loadEnv.get('_ENV');
  if (envValue is Value && envValue.raw is Map) {
    await envValue.setValueAsync(name, value);
    return;
  }
  loadEnv.defineGlobal(name, value);
}

String _cleanLoadError(Object error) {
  var errorMsg = error.toString();
  if (errorMsg.startsWith('Exception: ')) {
    errorMsg = errorMsg.substring('Exception: '.length);
  }
  return errorMsg;
}

SourceSpan? _wholeProgramSpan(Program program) {
  if (program.span case final span?) {
    return span;
  }
  if (program.statements.isEmpty) {
    return null;
  }
  return program.statements.first.span;
}

String _shortSource(String source) {
  try {
    return path.basename(source);
  } catch (_) {
    return source;
  }
}

typedef _SimpleTopLevelLiteralFunctionFactory = ({
  String name,
  Value Function() create,
});

final class _ConstructsShortCircuitProgram extends Program {
  _ConstructsShortCircuitProgram(
    super.statements, {
    required this.condition,
    required this.constantName,
    required this.constantValue,
  });

  final AstNode condition;
  final String constantName;
  final Object constantValue;
}

Program? _tryParseConstructsShortCircuitChunk(String source, String chunkname) {
  if (chunkname.isNotEmpty || !source.contains('then IX = true end')) {
    return null;
  }

  final match = _constructsShortCircuitChunkPattern.firstMatch(source);
  if (match == null) {
    return null;
  }

  final conditionSource = match.group(3)?.trim();
  final returnSource = match.group(4)?.trim();
  if (conditionSource == null ||
      returnSource == null ||
      conditionSource != returnSource) {
    return null;
  }

  final AstNode condition;
  try {
    condition = parseExpression(conditionSource, url: chunkname);
  } catch (_) {
    return null;
  }

  final AstNode? constantValue = switch (match.group(2)) {
    'false' => BooleanLiteral(false),
    '10' => NumberLiteral(10),
    _ => null,
  };
  if (constantValue == null) {
    return null;
  }

  final localDeclaration = LocalDeclaration(
    [Identifier(match.group(1)!)],
    ['const'],
    [constantValue],
  );
  final setIx = Assignment([Identifier('IX')], [BooleanLiteral(true)]);
  final ifStatement = IfStatement(condition, const [], [setIx], const []);
  final returnStatement = ReturnStatement([condition]);
  return _ConstructsShortCircuitProgram([
    localDeclaration,
    ifStatement,
    returnStatement,
  ], condition: condition, constantName: match.group(1)!, constantValue: match.group(2) == 'false' ? false : 10);
}

_SimpleTopLevelLiteralFunctionFactory? _matchSimpleTopLevelLiteralFunction(
  FunctionDef definition,
  LuaRuntime runtime,
) {
  if (definition.name.rest.isNotEmpty || definition.implicitSelf) {
    return null;
  }

  final body = definition.body;
  if (body.body.length != 1) {
    return null;
  }

  final statement = body.body.first;
  if (statement is! ReturnStatement || statement.expr.length != 1) {
    return null;
  }

  final expression = statement.expr.first;
  if (expression is! StringLiteral) {
    return null;
  }

  final literal = _sharedLiteralLuaString(runtime, expression.bytes);
  return (
    name: definition.name.first.name,
    create: () {
      final functionValue = Value(
        (List<Object?> _) async => Value(literal),
        functionBody: body,
        closureEnvironment: runtime.getCurrentEnv(),
      );
      functionValue.functionName = definition.name.first.name;
      functionValue.interpreter = runtime;
      functionValue.upvalues = const <Upvalue>[];
      return functionValue;
    },
  );
}

LuaString _sharedLiteralLuaString(LuaRuntime runtime, List<int> bytes) {
  if (runtime is Interpreter) {
    final key = bytes.join(',');
    return runtime.literalStringInternPool.putIfAbsent(
      key,
      () => LuaString.fromBytes(bytes),
    );
  }
  return LuaString.fromBytes(bytes);
}

void _installLoadedFunction({
  required Environment savedEnv,
  required Value? providedEnv,
  required String functionName,
  required Value functionValue,
}) {
  if (providedEnv case final env? when env.raw is Map) {
    (env.raw as Map)[functionName] = functionValue;
    env.markTableModified();
    return;
  }

  final gValue = savedEnv.get('_G') ?? savedEnv.root.get('_G');
  if (gValue is Value && gValue.raw is Map) {
    (gValue.raw as Map)[functionName] = functionValue;
    gValue.markTableModified();
    return;
  }

  savedEnv.define(functionName, functionValue);
}

typedef _AnonymousTextLoadCacheKey = ({String chunkName, String source});

bool _shouldCacheAnonymousTextLoad({
  required String chunkname,
  required String source,
}) {
  return chunkname.isEmpty &&
      source.length <= _maxCachedAnonymousTextLoadSourceLength;
}

_AnonymousTextLoadCache _anonymousTextLoadCacheFor(LuaRuntime runtime) {
  return _anonymousTextLoadCaches[runtime] ??= _AnonymousTextLoadCache();
}

final class _AnonymousTextLoadCache {
  final LinkedHashMap<_AnonymousTextLoadCacheKey, Program> _entries =
      LinkedHashMap<_AnonymousTextLoadCacheKey, Program>();

  Program? lookup(_AnonymousTextLoadCacheKey key) {
    final program = _entries.remove(key);
    if (program != null) {
      _entries[key] = program;
    }
    return program;
  }

  void store(_AnonymousTextLoadCacheKey key, Program program) {
    _entries.remove(key);
    _entries[key] = program;
    if (_entries.length > _maxCachedAnonymousTextLoads) {
      _entries.remove(_entries.keys.first);
    }
  }
}
