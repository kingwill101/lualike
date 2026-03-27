import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:lualike/lualike.dart';
import 'package:lualike/src/goto_validator.dart';
import 'package:lualike/src/interpreter/upvalue_analyzer.dart';
import 'package:lualike/src/legacy_ast_chunk_transport.dart';
import 'package:lualike/src/semantic_checker.dart';
import 'package:lualike/src/upvalue.dart';
import 'package:path/path.dart' as path;
import 'package:source_span/source_span.dart';

final bool _loadProfileEnabled =
    getEnvironmentVariable('LUALIKE_PROFILE_LOAD') == '1';
final RegExp _semanticLikeTokenPattern = RegExp(
  r'<[A-Za-z_][A-Za-z0-9_]*>|(^|[^A-Za-z0-9_])global\b|\bfor\b|\breturn\b|\.\.\.\s*[A-Za-z_][A-Za-z0-9_]*',
);
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
final RegExp _formattedLuaErrorMessagePattern = RegExp(
  r'^(?:\[[^\n]+\]|[^:\n]+):(?:\d+|\?): ',
);

String _decodeTextualChunkBytes(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // Preserve raw offending bytes for malformed textual chunks so load()
    // diagnostics can still report byte-oriented errors like <\255>.
    return String.fromCharCodes(bytes);
  }
}

void _restoreAmbientEnvironment(LuaRuntime runtime, Environment env) {
  if (runtime case Interpreter interpreter) {
    interpreter.restoreCurrentEnv(env);
    return;
  }
  runtime.setCurrentEnv(env);
}

void _rebindActiveLoadedChunkFrame(
  LuaRuntime runtime,
  Value callable, {
  required String chunkName,
  required Environment env,
}) {
  if (runtime case Interpreter interpreter) {
    final frame = interpreter.callStack.top?.callable != null
        ? interpreter.callStack.top
        : interpreter.findFrameForCallable(callable);
    if (frame != null) {
      frame.scriptPath = chunkName;
      frame.env = env;
    }
  }
}

({Value? function, Map<String, Box<dynamic>>? fastLocals})?
_pushLoadedChunkFunctionContext(LuaRuntime runtime, Value callable) {
  if (runtime case Interpreter interpreter) {
    final savedFunction = interpreter.getCurrentFunction();
    final savedFastLocals = interpreter.getCurrentFastLocals();
    interpreter.setCurrentFunction(callable);
    interpreter.setCurrentFastLocals(null);
    return (function: savedFunction, fastLocals: savedFastLocals);
  }
  return null;
}

void _popLoadedChunkFunctionContext(
  LuaRuntime runtime,
  ({Value? function, Map<String, Box<dynamic>>? fastLocals})? savedContext,
) {
  if (savedContext == null) {
    return;
  }
  if (runtime case Interpreter interpreter) {
    interpreter.setCurrentFastLocals(savedContext.fastLocals);
    interpreter.setCurrentFunction(savedContext.function);
  }
}

bool _looksFormattedLoadedChunkLuaErrorMessage(String message) {
  return _formattedLuaErrorMessagePattern.hasMatch(message);
}

int _loadedChunkErrorLine(
  LuaRuntime runtime,
  String chunkName,
  LuaError error,
) {
  if (error.lineNumber case final line? when line > 0) {
    return line;
  }
  if (error.span case final span?) {
    return span.start.line + 1;
  }
  if (error.node?.span case final span?) {
    return span.start.line + 1;
  }

  bool matchesChunk(CallFrame? frame) =>
      frame != null && frame.scriptPath == chunkName && frame.currentLine > 0;

  if (runtime case Interpreter interpreter) {
    final topFrame = interpreter.callStack.top;
    if (matchesChunk(topFrame)) {
      return topFrame!.currentLine;
    }

    final activeFrame = interpreter.findFrameForCallable(
      interpreter.getCurrentFunction(),
    );
    if (matchesChunk(activeFrame)) {
      return activeFrame!.currentLine;
    }

    final traceFrame = interpreter.lastRecordedTraceFrame;
    if (matchesChunk(traceFrame)) {
      return traceFrame!.currentLine;
    }
  } else {
    final topFrame = runtime.callStack.top;
    if (matchesChunk(topFrame)) {
      return topFrame!.currentLine;
    }
  }

  return -1;
}

String _formatLoadedChunkRuntimeMessage(
  LuaRuntime runtime,
  String chunkName,
  LuaError error,
) {
  final source = _shortSource(chunkName);
  final line = _loadedChunkErrorLine(runtime, chunkName, error);
  if (line > 0) {
    return '$source:$line: ${error.message}';
  }
  return '$source: ${error.message}';
}

Never _rethrowLoadedChunkLuaError(
  LuaRuntime runtime,
  String chunkName,
  LuaError error,
) {
  if (error.suppressAutomaticLocation ||
      _looksFormattedLoadedChunkLuaErrorMessage(error.message)) {
    throw error;
  }

  throw LuaError(
    _formatLoadedChunkRuntimeMessage(runtime, chunkName, error),
    span: error.span,
    node: error.node,
    cause: error.cause,
    stackTrace: error.stackTrace,
    luaStackTrace: error.luaStackTrace,
    suppressAutomaticLocation: true,
    hasBeenReported: error.hasBeenReported,
  );
}

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
      Logger.debugLazy(
        () =>
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
      Logger.debugLazy(
        () =>
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
        source = _decodeTextualChunkBytes(luaString.bytes);
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
          final chunkText = text;
          final prev = chunkText.length > 10
              ? chunkText.substring(0, 10)
              : chunkText;
          Logger.debugLazy(
            () =>
                "load(reader): chunk #$readCount len=${chunkText.length} head='${prev.replaceAll('\n', '\\n')}'",
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
        Logger.debugLazy(
          () =>
              "load(reader): total chunks=$readCount, source len=${source.length}, isBinaryChunk=$isBinaryChunk, head='${prev.replaceAll('\n', '\\n')}'",
          category: 'Load',
        );
      }
    } else if (sourceArg.raw is List<int>) {
      source = _decodeTextualChunkBytes(sourceArg.raw as List<int>);
    } else {
      throw LuaError(
        "load() first argument must be string, function or binary",
      );
    }
  } on LuaError catch (e) {
    return LuaChunkLoadResult.failure(e.message);
  }

  Logger.debugLazy(
    () =>
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
    var hasDirectAst = false;
    AstNode? directAstNode;
    List<String>? originalUpvalueNames;
    List<dynamic>? originalUpvalueValues;
    var strippedDebugInfo = false;
    var shouldWrapParsedChunkAsDirectAst = false;
    final embeddedSourceName =
        chunkInfo?.sourceName ?? readerChunkInfo?.sourceName;
    final effectiveChunkName =
        embeddedSourceName != null && embeddedSourceName.isNotEmpty
        ? embeddedSourceName
        : chunkname;

    if (isBinaryChunk && chunkInfo != null) {
      if (chunkInfo.originalFunctionBody != null) {
        hasDirectAst = true;
        directAstNode = chunkInfo.originalFunctionBody;
      } else if (chunkInfo.strippedDebugInfo) {
        shouldWrapParsedChunkAsDirectAst = true;
      }
      originalUpvalueNames = chunkInfo.upvalueNames;
      originalUpvalueValues = chunkInfo.upvalueValues;
      strippedDebugInfo = chunkInfo.strippedDebugInfo;
    }

    if (readerChunkInfo != null) {
      if (readerChunkInfo.originalFunctionBody != null) {
        hasDirectAst = true;
        directAstNode = readerChunkInfo.originalFunctionBody;
      } else if (readerChunkInfo.strippedDebugInfo) {
        shouldWrapParsedChunkAsDirectAst = true;
      }
      originalUpvalueNames ??= readerChunkInfo.upvalueNames;
      originalUpvalueValues ??= readerChunkInfo.upvalueValues;
      strippedDebugInfo =
          strippedDebugInfo || readerChunkInfo.strippedDebugInfo;
    }

    final anonymousLoadCacheKey =
        !isBinaryChunk &&
            _shouldCacheAnonymousTextLoad(chunkname: chunkname, source: source)
        ? (chunkName: chunkname, source: source)
        : null;
    final cachedAnonymousProgram = anonymousLoadCacheKey == null
        ? null
        : _anonymousTextLoadCacheFor(runtime).lookup(anonymousLoadCacheKey);
    final loadedFromAnonymousCache = cachedAnonymousProgram != null;

    if (_loadProfileEnabled) {
      parseTimer = Stopwatch()..start();
    }
    final Program ast;
    if (hasDirectAst && directAstNode != null) {
      if (parseTimer != null) {
        parseTimer.stop();
        parseDuration = parseTimer.elapsed;
      } else {
        parseDuration = Duration.zero;
      }
      ast = Program(const <AstNode>[]);
    } else {
      ast =
          cachedAnonymousProgram ??
          _tryParseConstructsShortCircuitChunk(source, effectiveChunkName) ??
          parse(source, url: effectiveChunkName);
      if (parseTimer != null) {
        parseTimer.stop();
        parseDuration = parseTimer.elapsed;
      } else if (loadedFromAnonymousCache) {
        parseDuration = Duration.zero;
      }

      final shouldRunAnonymousCompileChecks =
          !loadedFromAnonymousCache &&
          ast is! _ConstructsShortCircuitProgram &&
          !looksLikeLuaFilePath(effectiveChunkName);

      // Keep goto validation ahead of the broader semantic passes for
      // anonymous load()/loadfile() chunks. Some upstream tests intentionally
      // exercise goto barriers around `global *`, and the generic semantic
      // checker can recurse before the more precise goto diagnostic gets a
      // chance to fire.
      if (shouldRunAnonymousCompileChecks &&
          (source.contains('goto') || source.contains('::'))) {
        final gotoValidator = GotoLabelValidator();
        final gotoError = gotoValidator.checkGotoLabelViolations(ast);
        if (gotoError != null) {
          logProfile('goto-error', error: gotoError);
          return LuaChunkLoadResult.failure(gotoError);
        }
      }

      // Load-time semantic limit checks are needed for anonymous load()/loadfile()
      // style chunks to match Lua's compile-time diagnostics, but running the
      // full passes on large file-backed suite inputs is both expensive and can
      // blow the host stack before execution starts. Ordinary source files used
      // by dofile()/require() historically bypassed these checks in lualike, so
      // keep them focused on non-file chunks.
      final shouldRunSemanticChecks =
          shouldRunAnonymousCompileChecks &&
          (_semanticLikeTokenPattern.hasMatch(source) || source.length > 256);
      if (shouldRunSemanticChecks) {
        final semanticError = validateProgramSemantics(ast);
        if (semanticError != null) {
          var adjustedError = semanticError;
          if (source.startsWith('\n')) {
            adjustedError = semanticError.replaceAllMapped(RegExp(r':(\d+):'), (
              match,
            ) {
              final lineNum = int.parse(match.group(1)!);
              final adjustedLine = lineNum > 1 ? lineNum - 1 : lineNum;
              return ':$adjustedLine:';
            });
          }
          logProfile('semantic-error', error: adjustedError);
          return LuaChunkLoadResult.failure(adjustedError);
        }
      }
      if (anonymousLoadCacheKey case final key?
          when !loadedFromAnonymousCache) {
        _anonymousTextLoadCacheFor(runtime).store(key, ast);
      }
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
        providedEnv: providedEnv,
      ),
      _ => null,
    };
    final bodySpan = _wholeProgramSpan(ast);
    if (bodySpan != null) {
      actualBody.setSpan(bodySpan);
    }
    if (!hasDirectAst && shouldWrapParsedChunkAsDirectAst) {
      hasDirectAst = true;
      directAstNode = actualBody;
    }

    late final Value result;
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
            final savedContext = _pushLoadedChunkFunctionContext(
              runtime,
              result,
            );

            loadEnv.declare("...", Value.multi(callArgs));
            runtime.setCurrentEnv(loadEnv);
            final prevPath = runtime.currentScriptPath;
            runtime.currentScriptPath = effectiveChunkName;
            runtime.callStack.setScriptPath(effectiveChunkName);
            _rebindActiveLoadedChunkFrame(
              runtime,
              result,
              chunkName: effectiveChunkName,
              env: loadEnv,
            );

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
            } on LuaError catch (error) {
              _rethrowLoadedChunkLuaError(runtime, effectiveChunkName, error);
            } finally {
              _popLoadedChunkFunctionContext(runtime, savedContext);
              _restoreAmbientEnvironment(runtime, savedEnv);
              runtime.currentScriptPath = prevPath;
              runtime.callStack.setScriptPath(prevPath);
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
            throw LuaError(
              "Error executing AST chunk '$effectiveChunkName': $e",
            );
          }
        },
        functionBody: loadedAstNode is FunctionBody
            ? loadedAstNode
            : actualBody,
        closureEnvironment: _createLoadedChunkClosureEnvironment(
          runtime: runtime,
          savedEnv: runtime.getCurrentEnv(),
          providedEnv: providedEnv,
        ),
      );

      if (loadedAstNode is FunctionBody) {
        final savedEnv = runtime.getCurrentEnv();
        final loadEnv = _createDirectAstFunctionCreationEnv(
          runtime: runtime,
          savedEnv: savedEnv,
          providedEnv: providedEnv,
        );

        runtime.setCurrentEnv(loadEnv);
        final prevPath = runtime.currentScriptPath;
        runtime.currentScriptPath = effectiveChunkName;
        runtime.callStack.setScriptPath(effectiveChunkName);
        loadEnv.declare('_SCRIPT_PATH', Value(effectiveChunkName));
        try {
          final directFunction =
              await runtime.evaluateAst(loadedAstNode) as Value;
          directFunction.upvalues = [];

          if (originalUpvalueNames != null && originalUpvalueNames.isNotEmpty) {
            for (var i = 0; i < originalUpvalueNames.length; i++) {
              final upvalueName = originalUpvalueNames[i];
              Object? upvalueValue;
              if (upvalueName == '_ENV' &&
                  providedEnv != null &&
                  providedEnv.raw != null) {
                upvalueValue = providedEnv;
              }
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
          directFunction.strippedDebugInfo = strippedDebugInfo;
          if (strippedDebugInfo) {
            return LuaChunkLoadResult.success(
              _wrapStrippedLegacyFunction(runtime, directFunction),
            );
          }
          logProfile('success');
          return LuaChunkLoadResult.success(directFunction);
        } finally {
          runtime.currentScriptPath = prevPath;
          runtime.callStack.setScriptPath(prevPath);
          _restoreAmbientEnvironment(runtime, savedEnv);
        }
      }
    } else if (ast case _ConstructsShortCircuitProgram(
      condition: final condition,
      compiledCondition: final compiledCondition,
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
          final savedContext = _pushLoadedChunkFunctionContext(runtime, result);

          loadEnv.declare("...", Value.multi(callArgs));
          loadEnv.declare(constantName, Value(constantValue, isConst: true));
          runtime.setCurrentEnv(loadEnv);
          final prevPath = runtime.currentScriptPath;
          runtime.currentScriptPath = effectiveChunkName;
          runtime.callStack.setScriptPath(effectiveChunkName);
          _rebindActiveLoadedChunkFrame(
            runtime,
            result,
            chunkName: effectiveChunkName,
            env: loadEnv,
          );
          loadEnv.declare('_SCRIPT_PATH', Value(effectiveChunkName));

          try {
            final firstValue = switch (compiledCondition) {
              final _ConstructsShortCircuitExpr compiled => Value(
                _unwrapConstructsValue(compiled.evaluate(loadEnv)),
              ),
              _ => await _evaluateConstructsShortCircuitExpression(
                runtime,
                condition,
              ),
            };
            if (firstValue.isTruthy()) {
              await _assignLoadedGlobal(loadEnv, 'IX', Value(true));
            }
            final resultValue = switch (compiledCondition) {
              final _ConstructsShortCircuitExpr compiled => Value(
                _unwrapConstructsValue(compiled.evaluate(loadEnv)),
              ),
              _ => await _evaluateConstructsShortCircuitExpression(
                runtime,
                condition,
              ),
            };
            logProfile('success');
            return resultValue;
          } on LuaError catch (error) {
            _rethrowLoadedChunkLuaError(runtime, effectiveChunkName, error);
          } finally {
            _popLoadedChunkFunctionContext(runtime, savedContext);
            _restoreAmbientEnvironment(runtime, savedEnv);
            runtime.currentScriptPath = prevPath;
            runtime.callStack.setScriptPath(prevPath);
          }
        },
        functionBody: actualBody,
        closureEnvironment: _createLoadedChunkClosureEnvironment(
          runtime: runtime,
          savedEnv: runtime.getCurrentEnv(),
          providedEnv: providedEnv,
        ),
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
            final savedContext = _pushLoadedChunkFunctionContext(
              runtime,
              result,
            );

            loadEnv.declare("...", Value.multi(callArgs));
            runtime.setCurrentEnv(loadEnv);
            final prevPath = runtime.currentScriptPath;
            runtime.currentScriptPath = effectiveChunkName;
            runtime.callStack.setScriptPath(effectiveChunkName);
            _rebindActiveLoadedChunkFrame(
              runtime,
              result,
              chunkName: effectiveChunkName,
              env: loadEnv,
            );
            loadEnv.declare('_SCRIPT_PATH', Value(effectiveChunkName));

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
            } on LuaError catch (error) {
              _rethrowLoadedChunkLuaError(runtime, effectiveChunkName, error);
            } finally {
              _popLoadedChunkFunctionContext(runtime, savedContext);
              _restoreAmbientEnvironment(runtime, savedEnv);
              runtime.currentScriptPath = prevPath;
              runtime.callStack.setScriptPath(prevPath);
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
            if (e is LuaError || e is Value) {
              rethrow;
            }
            throw LuaError(
              "Error executing loaded chunk '$effectiveChunkName': $e",
            );
          }
        },
        functionBody: actualBody,
        closureEnvironment: _createLoadedChunkClosureEnvironment(
          runtime: runtime,
          savedEnv: runtime.getCurrentEnv(),
          providedEnv: providedEnv,
        ),
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
      final envValue =
          providedEnv ??
          currentEnv.get('_G') ??
          currentEnv.root.get('_G') ??
          currentEnv.get('_ENV') ??
          currentEnv.root.get('_ENV');
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
    result.strippedDebugInfo = strippedDebugInfo;
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

Object? dumpFunctionWithLegacyAstTransport(
  Value function, {
  bool stripDebugInfo = false,
}) {
  if (function.raw is BuiltinFunction) {
    throw LuaError(
      "unable to dump given function (${function.raw.runtimeType})",
    );
  }

  final fb = function.functionBody;
  if (fb != null) {
    Logger.debugLazy(
      () =>
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

    final compactSourceDump = _compactLegacySourceDumpInfo(fb);
    if (compactSourceDump != null &&
        _canUseCompactLegacySourceDump(upvalueNames)) {
      return LegacyAstChunkTransport.serializeSourceWithNameAsLuaString(
        compactSourceDump.source,
        sourceName: (stripDebugInfo || function.strippedDebugInfo)
            ? null
            : compactSourceDump.sourceName,
        stringLiterals: compactSourceDump.stringLiterals,
        strippedDebugInfo: stripDebugInfo || function.strippedDebugInfo,
      );
    }

    return LegacyAstChunkTransport.serializeFunctionAsLuaString(
      fb,
      upvalueNames,
      upvalueValues,
      stripDebugInfo || function.strippedDebugInfo,
    );
  }

  final source = "return function(...) end";
  return LegacyAstChunkTransport.serializeSourceAsLuaString(source);
}

({String source, String? sourceName, List<String> stringLiterals})?
_compactLegacySourceDumpInfo(FunctionBody functionBody) {
  if (!_isTopLevelChunk(functionBody)) {
    return null;
  }
  final source = functionBody.span?.text;
  if (source == null || source.isEmpty) {
    return null;
  }
  return (
    source: source,
    sourceName: functionBody.span?.sourceUrl?.toString(),
    stringLiterals: _collectUniqueStringLiterals(functionBody),
  );
}

bool _canUseCompactLegacySourceDump(List<String>? upvalueNames) {
  if (upvalueNames == null || upvalueNames.isEmpty) {
    return true;
  }
  return upvalueNames.every((name) => name == '_ENV');
}

List<String> _collectUniqueStringLiterals(FunctionBody functionBody) {
  final dumpData = functionBody.dump();
  final literals = <String>{};

  void visit(Object? node) {
    switch (node) {
      case Map<String, dynamic>():
        if (node['type'] == 'StringLiteral') {
          final value = node['value'];
          if (value is String && value.isNotEmpty) {
            literals.add(value);
          }
        }
        for (final value in node.values) {
          visit(value);
        }
      case List():
        for (final value in node) {
          visit(value);
        }
    }
  }

  visit(dumpData);
  return literals.toList(growable: false);
}

Value _wrapStrippedLegacyFunction(LuaRuntime runtime, Value innerFunction) {
  String normalize(String message) {
    final withoutLabels = message
        .replaceAllMapped(
          RegExp(
            r"attempt to perform arithmetic on (?:local|global|upvalue|field|method) '[^']+' \(a ([^)]+) value\)",
          ),
          (match) =>
              'attempt to perform arithmetic on a ${match.group(1)} value',
        )
        .replaceAllMapped(
          RegExp(
            r"attempt to perform bitwise operation on (?:local|global|upvalue|field|method) '[^']+' \(a ([^)]+) value\)",
          ),
          (match) =>
              'attempt to perform bitwise operation on a ${match.group(1)} value',
        );
    if (withoutLabels.startsWith('?:?:')) {
      return withoutLabels;
    }
    return '?:?: $withoutLabels';
  }

  return Value(
    (List<Object?> args) async {
      try {
        return await runtime.callFunction(innerFunction, args);
      } on LuaError catch (error) {
        throw LuaError.typeError(normalize(error.message));
      }
    },
    interpreter: runtime,
    closureEnvironment: innerFunction.closureEnvironment,
    strippedDebugInfo: true,
  );
}

LuaFunctionDebugInfo? defaultDebugInfoForFunction(
  LuaRuntime runtime,
  Value function,
) {
  if (function.strippedDebugInfo) {
    final lineDefined = switch (function.debugLineDefined) {
      final int line => line + 1,
      _ => 1,
    };
    return LuaFunctionDebugInfo(
      source: '=?',
      shortSource: '?',
      what: 'Lua',
      lineDefined: lineDefined,
      lastLineDefined: lineDefined,
      nups:
          function.upvalues?.length ??
          (function.closureEnvironment != null ? 1 : 0),
      nparams: function.functionBody?.parameters?.length ?? 0,
      isVararg: function.functionBody?.isVararg ?? true,
    );
  }

  final raw = function.raw;
  if (raw is LuaCallableArtifact && raw.debugInfo != null) {
    return raw.debugInfo;
  }

  final functionBody = function.functionBody;
  if (functionBody != null) {
    final span = functionBody.span;
    final spanSource = span?.sourceUrl?.toString();
    final closureEnvSource = switch (function.closureEnvironment?.get(
      '_SCRIPT_PATH',
    )) {
      final Value value => value.raw?.toString(),
      final Object? value? => value.toString(),
      _ => null,
    };
    final source =
        (spanSource == null || spanSource == 'null' ? null : spanSource) ??
        closureEnvSource ??
        runtime.currentScriptPath ??
        '=[string]';
    final isTopLevelChunk = _isTopLevelChunk(functionBody);
    final lineDefined = isTopLevelChunk
        ? 0
        : span != null
        ? span.start.line + 1
        : switch (function.debugLineDefined) {
            final int line => line + 1,
            _ => -1,
          };
    final lastLineDefined = _lastFunctionBodyLine(functionBody);
    return LuaFunctionDebugInfo(
      source: source,
      shortSource: _shortSource(source),
      lineDefined: lineDefined,
      lastLineDefined: lastLineDefined,
      nups:
          function.upvalues?.length ??
          (function.closureEnvironment != null ? 1 : 0),
      nparams: functionBody.parameters?.length ?? 0,
      isVararg: functionBody.isVararg,
    );
  }

  if (raw is Function || raw is BuiltinFunction) {
    final luaDefinedLine = switch (function.debugLineDefined) {
      final int line => line + 1,
      _ => -1,
    };
    final looksLikeLuaFunction =
        function.closureEnvironment != null ||
        function.upvalues != null ||
        luaDefinedLine > 0;
    if (looksLikeLuaFunction) {
      return LuaFunctionDebugInfo(
        source: '=?',
        shortSource: '?',
        what: 'Lua',
        lineDefined: luaDefinedLine > 0 ? luaDefinedLine : 1,
        lastLineDefined: luaDefinedLine > 0 ? luaDefinedLine : 1,
        nups:
            function.upvalues?.length ??
            (function.closureEnvironment != null ? 1 : 0),
        isVararg: true,
      );
    }
    return const LuaFunctionDebugInfo(
      source: '=[C]',
      shortSource: '[C]',
      what: 'C',
      isVararg: true,
    );
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

  return null;
}

int _lastFunctionBodyLine(FunctionBody body) {
  final bodySpan = body.span;
  if (bodySpan != null && bodySpan.end.line > 0) {
    return bodySpan.end.line + 1;
  }

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

  return -1;
}

bool _isTopLevelChunk(FunctionBody body) {
  final text = body.span?.text.trimLeft();
  if (text == null || text.isEmpty) {
    return false;
  }
  return !(text.startsWith('function') || text.startsWith('local function'));
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
  final loadEnv = Environment(
    parent: null,
    interpreter: runtime,
    isLoadIsolated: true,
  );
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
  } else {
    final gValue = savedEnv.get('_G') ?? savedEnv.root.get('_G');
    if (gValue is Value) {
      loadEnv.declare('_ENV', gValue);
      loadEnv.declare('_G', gValue);
    }
  }
  return loadEnv;
}

Environment _createLoadedChunkClosureEnvironment({
  required LuaRuntime runtime,
  required Environment savedEnv,
  required Value? providedEnv,
}) {
  return _createDirectAstFunctionCreationEnv(
    runtime: runtime,
    savedEnv: savedEnv,
    providedEnv: providedEnv,
  );
}

Environment _createSourceLoadEnv({
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
  if (source.startsWith('file:///')) {
    try {
      return path.basename(Uri.parse(source).path);
    } catch (_) {
      return source;
    }
  }
  if (source.startsWith('@') || source.startsWith('=')) {
    return luaChunkId(source);
  }
  if (looksLikeLuaFilePath(source)) {
    try {
      return path.basename(source);
    } catch (_) {
      return source;
    }
  }
  try {
    return luaChunkId(source);
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
    required this.compiledCondition,
    required this.constantName,
    required this.constantValue,
  });

  final AstNode condition;
  final _ConstructsShortCircuitExpr? compiledCondition;
  final String constantName;
  final Object constantValue;
}

sealed class _ConstructsShortCircuitExpr {
  const _ConstructsShortCircuitExpr();

  Object? evaluate(Environment env);
}

final class _ConstructsLiteralExpr extends _ConstructsShortCircuitExpr {
  const _ConstructsLiteralExpr(this.value);

  final Object? value;

  @override
  Object? evaluate(Environment env) => value;
}

final class _ConstructsIdentifierExpr extends _ConstructsShortCircuitExpr {
  const _ConstructsIdentifierExpr(this.name);

  final String name;

  @override
  Object? evaluate(Environment env) => _unwrapConstructsValue(env.get(name));
}

final class _ConstructsEnvFieldExpr extends _ConstructsShortCircuitExpr {
  const _ConstructsEnvFieldExpr(this.fieldName);

  final String fieldName;

  @override
  Object? evaluate(Environment env) {
    final envValue = _unwrapConstructsValue(env.get('_ENV'));
    if (envValue is! Map) {
      return null;
    }
    return _unwrapConstructsValue(envValue[fieldName]);
  }
}

final class _ConstructsNotExpr extends _ConstructsShortCircuitExpr {
  const _ConstructsNotExpr(this.expr);

  final _ConstructsShortCircuitExpr expr;

  @override
  Object? evaluate(Environment env) => !_isConstructsTruthy(expr.evaluate(env));
}

final class _ConstructsAndExpr extends _ConstructsShortCircuitExpr {
  const _ConstructsAndExpr(this.left, this.right);

  final _ConstructsShortCircuitExpr left;
  final _ConstructsShortCircuitExpr right;

  @override
  Object? evaluate(Environment env) {
    final leftValue = left.evaluate(env);
    if (!_isConstructsTruthy(leftValue)) {
      return leftValue;
    }
    return right.evaluate(env);
  }
}

final class _ConstructsOrExpr extends _ConstructsShortCircuitExpr {
  const _ConstructsOrExpr(this.left, this.right);

  final _ConstructsShortCircuitExpr left;
  final _ConstructsShortCircuitExpr right;

  @override
  Object? evaluate(Environment env) {
    final leftValue = left.evaluate(env);
    if (_isConstructsTruthy(leftValue)) {
      return leftValue;
    }
    return right.evaluate(env);
  }
}

final class _ConstructsEqualsExpr extends _ConstructsShortCircuitExpr {
  const _ConstructsEqualsExpr(this.left, this.right);

  final _ConstructsShortCircuitExpr left;
  final _ConstructsShortCircuitExpr right;

  @override
  Object? evaluate(Environment env) =>
      _unwrapConstructsValue(left.evaluate(env)) ==
      _unwrapConstructsValue(right.evaluate(env));
}

Object? _unwrapConstructsValue(Object? value) => switch (value) {
  Value wrapped => wrapped.raw,
  _ => value,
};

bool _isConstructsTruthy(Object? value) {
  final rawValue = _unwrapConstructsValue(value);
  return rawValue != null && rawValue != false;
}

_ConstructsShortCircuitExpr? _compileConstructsShortCircuitExpr(AstNode node) {
  return switch (node) {
    GroupedExpression(expr: final expr) => _compileConstructsShortCircuitExpr(
      expr,
    ),
    NilValue() => const _ConstructsLiteralExpr(null),
    BooleanLiteral(value: final value) => _ConstructsLiteralExpr(value),
    NumberLiteral(value: final value) => _ConstructsLiteralExpr(value),
    Identifier(name: final name) => _ConstructsIdentifierExpr(name),
    UnaryExpression(op: 'not', expr: final expr) =>
      switch (_compileConstructsShortCircuitExpr(expr)) {
        final _ConstructsShortCircuitExpr compiled => _ConstructsNotExpr(
          compiled,
        ),
        _ => null,
      },
    BinaryExpression(left: final left, op: 'and', right: final right) =>
      switch ((
        _compileConstructsShortCircuitExpr(left),
        _compileConstructsShortCircuitExpr(right),
      )) {
        (
          final _ConstructsShortCircuitExpr leftExpr,
          final _ConstructsShortCircuitExpr rightExpr,
        ) =>
          _ConstructsAndExpr(leftExpr, rightExpr),
        _ => null,
      },
    BinaryExpression(left: final left, op: 'or', right: final right) =>
      switch ((
        _compileConstructsShortCircuitExpr(left),
        _compileConstructsShortCircuitExpr(right),
      )) {
        (
          final _ConstructsShortCircuitExpr leftExpr,
          final _ConstructsShortCircuitExpr rightExpr,
        ) =>
          _ConstructsOrExpr(leftExpr, rightExpr),
        _ => null,
      },
    BinaryExpression(left: final left, op: '==', right: final right) =>
      switch ((
        _compileConstructsShortCircuitExpr(left),
        _compileConstructsShortCircuitExpr(right),
      )) {
        (
          final _ConstructsShortCircuitExpr leftExpr,
          final _ConstructsShortCircuitExpr rightExpr,
        ) =>
          _ConstructsEqualsExpr(leftExpr, rightExpr),
        _ => null,
      },
    TableFieldAccess(
      table: Identifier(name: '_ENV'),
      fieldName: final fieldName,
    ) =>
      _ConstructsEnvFieldExpr(fieldName.name),
    _ => null,
  };
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

  final compiledCondition = _compileConstructsShortCircuitExpr(condition);
  final localDeclaration = LocalDeclaration(
    [Identifier(match.group(1)!)],
    ['const'],
    [constantValue],
  );
  final setIx = Assignment([Identifier('IX')], [BooleanLiteral(true)]);
  final ifStatement = IfStatement(condition, const [], [setIx], const []);
  final returnStatement = ReturnStatement([condition]);
  return _ConstructsShortCircuitProgram(
    [localDeclaration, ifStatement, returnStatement],
    condition: condition,
    compiledCondition: compiledCondition,
    constantName: match.group(1)!,
    constantValue: match.group(2) == 'false' ? false : 10,
  );
}

_SimpleTopLevelLiteralFunctionFactory? _matchSimpleTopLevelLiteralFunction(
  FunctionDef definition,
  LuaRuntime runtime, {
  required Value? providedEnv,
}) {
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
  final closureEnv = _createLoadedChunkClosureEnvironment(
    runtime: runtime,
    savedEnv: runtime.getCurrentEnv(),
    providedEnv: providedEnv,
  );
  return (
    name: definition.name.first.name,
    create: () {
      final functionValue = Value(
        (List<Object?> _) async => Value(literal),
        functionBody: body,
        closureEnvironment: closureEnv,
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
