import 'dart:async' show FutureOr;
import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/call_stack.dart';
import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/exceptions.dart';
import 'package:lualike/src/gc/gc.dart';
import 'package:lualike/src/ast.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/io/lua_file.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/instruction.dart';
import 'package:lualike/src/lua_bytecode/opcode.dart';
import 'package:lualike/src/lua_bytecode/opcode_analysis.dart';
import 'package:lualike/src/lua_bytecode/instruction_analysis.dart';
import 'package:lualike/src/lua_bytecode/vm_frame.dart';
import 'package:lualike/src/lua_bytecode/vm_value_helpers.dart';
import 'package:lualike/src/lua_bytecode/vm_frame_helpers.dart';
import 'package:lualike/src/lua_bytecode/vm_call_frame_state.dart';
import 'package:lualike/src/lua_bytecode/vm_support.dart';
import 'package:lualike/src/lua_bytecode/vm_profile.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/number.dart';
import 'package:lualike/src/number_limits.dart';
import 'package:lualike/src/number_utils.dart';
import 'package:lualike/src/runtime/lua_results.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/parse.dart' show looksLikeLuaFilePath;
import 'package:lualike/src/stdlib/lib_io.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/table_storage.dart';
import 'package:lualike/src/utils/platform_utils.dart' as platform;
import 'package:lualike/src/utils/type.dart' show getLuaType;
import 'package:lualike/src/value.dart';

// ignore_for_file: library_private_types_in_public_api

part 'vm_call.dart';
part 'vm_tables.dart';
part 'vm_arithmetic.dart';
part 'vm_compare.dart';
part 'vm_control_flow.dart';
part 'vm_debug.dart';
part 'vm_gc.dart';
part 'vm_continuation.dart';
part 'vm_suspension_call.dart';
part 'vm_suspension_tail.dart';

final bool _debugFileOps =
    platform.getEnvironmentVariable('LUALIKE_DEBUG_FILE_OPS') == '1';
final bool _profileBytecode =
    platform.getEnvironmentVariable('LUALIKE_PROFILE_BYTECODE') == '1';
final bool _debugBytecodeHooks =
    platform.getEnvironmentVariable('LUALIKE_DEBUG_BYTECODE_HOOKS') == '1';

final RegExp _bytecodeFormattedLuaErrorPattern = RegExp(
  r'^(?:\[[^\n]+\]|[^:\n]+):(?:\d+|\?): ',
);

final class LuaBytecodeVm {
  LuaBytecodeVm(this.runtime)
    : _debugInterpreter = _resolveDebugInterpreter(runtime);

  final LuaRuntime runtime;
  final Interpreter? _debugInterpreter;
  LuaBytecodeProfile? _activeProfile;

  /// Per-table-storage GETFIELD cache: (pc, fieldConst) → (version, Value).
  /// Key is Object.hash(instructionPc, word.c) for collision-free combining.
  final _getFieldIc = Expando<Map<int, ({int version, Value value})>>();




  /// Resolves the underlying debug interpreter once at construction time.
  /// The debug interpreter never changes for a given VM instance.
  static Interpreter? _resolveDebugInterpreter(LuaRuntime runtime) {
    if (runtime is Interpreter) {
      return runtime;
    }
    try {
      final debugInterpreter = (runtime as dynamic).debugInterpreter;
      if (debugInterpreter is Interpreter) {
        return debugInterpreter;
      }
    } catch (_) {
      // Fall through to environment-bound interpreter discovery.
    }
    final envInterpreter = runtime.getCurrentEnv().interpreter;
    return envInterpreter is Interpreter ? envInterpreter : null;
  }

  Future<List<Value>> _runFrame(LuaBytecodeFrame frame) async {
    final closure = frame.closure;
    final previousEnv = runtime.getCurrentEnv();
    final previousScriptPath = runtime.currentScriptPath;
    final previousCallStackScriptPath = runtime.callStack.scriptPath;
    final parentFrame = runtime.callStack.top;
    final parentFrameEnv = parentFrame?.env;
    runtime.pushExternalGcRoots(frame.externalGcRootProvider);
    runtime.setCurrentEnv(closure.environment);
    final activeScriptPath = closure.prototype.source ?? previousScriptPath;
    runtime.currentScriptPath = activeScriptPath;
    runtime.callStack.setScriptPath(activeScriptPath);
    final callableValue = switch (frame.functionValue) {
      final Value functionValue when functionValue.functionBody != null =>
        functionValue,
      final Value functionValue
          when rawLuaSlot(functionValue) is LuaBytecodeClosure =>
        closure.callableValue,
      final Value functionValue => functionValue,
      _ => closure.callableValue,
    };
    runtime.callStack.push(
      frame.callName ?? closure.debugInfo.shortSource,
      env: closure.environment,
      debugName: frame.callName,
      debugNameWhat: frame.callName == 'hook'
          ? 'hook'
          : (frame.callNameWhat ?? ''),
      callable: callableValue,
    );
    if (parentFrame != null) {
      parentFrame.env = parentFrameEnv;
    }
    final activeCallFrame = runtime.callStack.top!;
    bindBytecodeCallFrame(activeCallFrame, frame);
    final isHookCallback =
        frame.callName == 'hook' ||
        frame.callNameWhat == 'hook' ||
        // The interpreter wraps debug hooks with an outer call-stack frame
        // before dispatching into bytecode. The first bytecode frame inside
        // that wrapper is still the hook callback, but helper calls made from
        // inside the hook should not inherit hook visibility.
        (parentFrame?.isDebugHook == true &&
            bytecodeFrameForCallFrame(parentFrame!) == null);
    if (isHookCallback) {
      // Only the hook callback itself should count as a debug-hook frame for
      // visibility purposes. Helper functions that the hook calls must remain
      // visible in `debug.getlocal`/`debug.getinfo` stack walks so their
      // levels line up with the reference interpreter.
      activeCallFrame.isDebugHook = true;
    }
    if (frame.callName == null &&
        closure.debugInfo.what != 'main' &&
        activeCallFrame.callable?.functionBody != null) {
      activeCallFrame.functionName = 'unknown';
    }
    activeCallFrame.isTailCall = frame.isTailCall;
    activeCallFrame.extraArgs = frame.extraArgs;
    final entryDebugInterpreter = _debugInterpreter;
    // Only sync debug locals when a debug hook is active. The debug locals
    // are only consulted by debug.getlocal/getinfo which require a live hook.
    if (entryDebugInterpreter?.debugHookFunction != null) {
      _syncDebugLocals(frame, callFrame: activeCallFrame);
    }
    if (frame.pc == 0 &&
        !activeCallFrame.isDebugHook &&
        entryDebugInterpreter != null &&
        entryDebugInterpreter.debugHookMask.contains('l') &&
        !closure.prototype.hasDebugInfo) {
      await entryDebugInterpreter.fireDebugHook('line');
    }
    if (_debugBytecodeHooks) {
      print(
        '[bc-hook] entry debug=${entryDebugInterpreter != null} '
        'hook=${entryDebugInterpreter?.debugHookFunction != null} '
        'mask=${entryDebugInterpreter?.debugHookMask} '
        'co=${runtime.getCurrentCoroutine()?.hashCode}',
      );
    }
    if (entryDebugInterpreter != null &&
        entryDebugInterpreter.debugHookFunction != null &&
        !frame.didFireEntryCallHook &&
        !(frame.pc == 0 && frame.closure.prototype.isVararg)) {
      await _fireFrameCallHook(frame, entryDebugInterpreter);
    }

    var suspended = false;
    var poppedCallFrame = false;
    List<Value> returnTransferValues = const <Value>[];
    try {
      final result = await _executeFrame(frame, callFrame: activeCallFrame);
      returnTransferValues = result;
      return result;
    } on YieldException catch (error) {
      final coroutine = error.coroutine ?? runtime.getCurrentCoroutine();
      if (coroutine == null || !coroutine.hasContinuation) {
        throw LuaError(
          _opcodeDiagnostic(
            frame,
            'YIELD',
            detail: 'yield across unsupported lua_bytecode coroutine path',
          ),
        );
      }
      suspended = true;
      rethrow;
    } on CoroutineCloseSignal catch (signal) {
      var closeYieldable = closeSignalYieldableStates[signal];
      runtime.callStack.pop();
      poppedCallFrame = true;
      var closeResult = signal.result;
      if (!frame.closed) {
        final previousYieldable = runtime.isYieldable;
        try {
          if (closeYieldable != null) {
            runtime.isYieldable = closeYieldable;
          }
          await _closeFrameForCoroutine(frame, error: null);
        } on CoroutineCloseSignal catch (nestedSignal) {
          closeResult = nestedSignal.result;
          closeYieldable =
              closeSignalYieldableStates[nestedSignal] ?? closeYieldable;
        } on YieldException {
          closeResult = <Object?>[
            runtime.constantPrimitiveValue(false),
            runtime.constantDartStringValue(
              'attempt to yield across a C-call boundary',
            ),
          ];
        } catch (error) {
          final adjustedError = switch (error) {
            final LuaError luaError
                when runtime.isInProtectedCall &&
                    luaError.cause != null &&
                    luaError.cause is! LuaError =>
              luaError.cause!,
            final LuaError luaError => _normalizeStrippedFrameError(
              frame,
              _withFrameRuntimeLocation(frame, luaError),
            ),
            _ => error,
          };
          final normalizedError = _normalizeBytecodeCoroutineCloseError(
            adjustedError,
          );
          closeResult = <Object?>[
            runtime.constantPrimitiveValue(false),
            valueFromLuaSlot(runtime, normalizedError),
          ];
        } finally {
          runtime.isYieldable = previousYieldable;
        }
      }
      final propagatedSignal = CoroutineCloseSignal(closeResult);
      if (closeYieldable != null) {
        rememberCloseSignalYieldable(propagatedSignal, closeYieldable);
      }
      throw propagatedSignal;
    } catch (error, stackTrace) {
      final adjustedError = switch (error) {
        final LuaError luaError
            when runtime.isInProtectedCall &&
                luaError.cause != null &&
                luaError.cause is! LuaError =>
          luaError.cause!,
        final LuaError luaError => _normalizeStrippedFrameError(
          frame,
          _withFrameRuntimeLocation(frame, luaError),
        ),
        _ => error,
      };
      runtime.callStack.pop();
      poppedCallFrame = true;
      _tmpDebugFrame(
        frame,
        'runframe-error adjusted=${adjustedError.runtimeType}:$adjustedError pc=${frame.pc} '
        'closed=${frame.closed}',
      );
      if (!frame.closed) {
        try {
          await _closeFrameForCoroutine(frame, error: adjustedError);
        } on YieldException catch (yieldError) {
          suspended = true;
          _suspendErrorClose(frame, adjustedError, stackTrace, yieldError);
        }
      }
      throw adjustedError;
    } finally {
      runtime.popExternalGcRoots(frame.externalGcRootProvider);
      if (!suspended && !frame.closed) {
        if (!_closeFrameForCoroutineSync(frame)) {
          await _closeFrameForCoroutine(frame, error: null);
        }
      }
      final exitDebugInterpreter = _debugInterpreter;
      if (!suspended &&
          !poppedCallFrame &&
          exitDebugInterpreter != null &&
          exitDebugInterpreter.debugHookFunction != null) {
        final topFrame = activeCallFrame;
        _syncCallFrameDebugLocals(topFrame);
        _setTransferInfo(topFrame, returnTransferValues);
        await exitDebugInterpreter.fireDebugHook('return');
        _clearTransferInfo(topFrame);
      }
      if (!poppedCallFrame) {
        runtime.callStack.pop();
      }
      if (suspended) {
        while (runtime.callStack.top?.isDebugHook ?? false) {
          runtime.callStack.pop();
        }
      }
      // Skip state restoration on the happy path when no debug hook is active.
      // The next frame will overwrite env/scriptPath anyway. Errors and
      // debug hooks still need restored state, handled in catch blocks.
      // Must still restore for suspended coroutines (the runtime may be reused).
      if (exitDebugInterpreter?.debugHookFunction != null || suspended) {
        runtime.callStack.setScriptPath(previousCallStackScriptPath);
        runtime.currentScriptPath = previousScriptPath;
        runtime.setCurrentEnv(previousEnv);
        if (parentFrame != null) {
          parentFrame.env = parentFrameEnv;
        }
      }
    }
  }

  Future<List<Value>> _runFrameWithTailCalls(LuaBytecodeFrame frame) async {
    while (true) {
      try {
        final result = await _runFrame(frame);
        _releaseBytecodeFrameIfReusable(frame);
        return result;
      } on TailCallException catch (tail) {
        // Fast path: LuaBytecodeClosure with no debug hooks.
        final tailRawCallee = rawLuaSlot(tail.functionValue);
        if (tailRawCallee is LuaBytecodeClosure &&
            _debugInterpreter?.debugHookFunction == null) {
          final tailFnValue = tail.functionValue is Value
              ? tail.functionValue as Value
              : null;
          try {
            final result = await invoke(
              tailRawCallee,
              tail.args,
              functionValue: tailFnValue,
              isTailCall: true,
            );
            _releaseBytecodeFrameIfReusable(frame);
            return result;
          } on YieldException catch (error) {
            _suspendTailCall(frame, error);
          } catch (error) {
            _releaseBytecodeFrameIfReusable(frame);
            rethrow;
          }
        }
        final prepared = _flattenTailCallable(tail.functionValue, tail.args);
        final callee = prepared.callee;
        if (rawLuaSlot(callee) case final LuaBytecodeClosure nextClosure) {
          try {
            final result = await invoke(
              nextClosure,
              prepared.args,
              functionValue: callee,
              callName: tail.callName,
              extraArgs: prepared.extraArgs,
            );
            _releaseBytecodeFrameIfReusable(frame);
            return result;
          } on YieldException catch (error) {
            _suspendTailCall(frame, error);
          } catch (error) {
            _releaseBytecodeFrameIfReusable(frame);
            rethrow;
          }
        }
        try {
          final result = await _invokeValueWithName(
            callee,
            prepared.args,
            callName: tail.callName,
            extraArgs: prepared.extraArgs,
          );
          _releaseBytecodeFrameIfReusable(frame);
          return result;
        } on YieldException catch (error) {
          _suspendTailCall(frame, error);
        } catch (error) {
          _releaseBytecodeFrameIfReusable(frame);
          rethrow;
        }
      }
    }
  }

  Future<List<Value>> _executeFrame(
    LuaBytecodeFrame frame, {
    required CallFrame callFrame,
  }) async {
    final prototype = frame.closure.prototype;
    final opcodesByPc = prototype.opcodesByPc;
    final mainThread = runtime.getMainThread();
    final linesByPc = prototype.hasDebugInfo ? prototype.linesByPc : null;
    var currentCoroutine = runtime.getCurrentCoroutine();
    // Cache profiling state — profile is immutable during frame execution.
    final profile = _activeProfile;
    final hasProfile = profile != null;
    while (frame.pc < prototype.code.length) {
      frame.expireDeadLocals();
      currentCoroutine = _syncCurrentCoroutine(mainThread, currentCoroutine);
      if (++frame.safePointCounter >= 512) {
        frame.safePointCounter = 0;
        runtime.runAutoGcAtSafePoint();
      }
      int? nextOpenTop;
      final instructionPc = frame.pc++;
      final word = prototype.code[instructionPc];
      final opcode = opcodesByPc[instructionPc];
      final lineNumber = linesByPc?[instructionPc];
      final debugInterpreter = _debugInterpreter;
      final hasDebugHook = debugInterpreter?.debugHookFunction != null;
      final previousVisibleLine = hasDebugHook ? callFrame.currentLine : -1;
      final needsCoroutineWideBoundary =
          currentCoroutine != null && !identical(currentCoroutine, mainThread);
      final opTimer = hasProfile ? (Stopwatch()..start()) : null;
      try {
        if (needsCoroutineWideBoundary) {
          await _preserveSuspendingBytecodeBoundary(
            currentCoroutine: currentCoroutine,
            mainThread: mainThread,
          );
        } else if (opcode.needsSuspendingBoundary &&
            _needsSuspendingOpcodeBoundaryForInstruction(frame, opcode, word)) {
          await _preserveSuspendingBytecodeBoundary(
            currentCoroutine: currentCoroutine,
            mainThread: mainThread,
          );
        }
        final forceLineHook = frame.forceNextLineHook;
        frame.forceNextLineHook = false;
        final deferCountHook = hasDebugHook
            ? _deferCountHookForOpcode(opcode)
            : false;
        if (hasDebugHook && !deferCountHook) {
          _syncDebugLocals(frame, callFrame: callFrame);
          await debugInterpreter!.maybeFireCountDebugHook();
        }
        if (lineNumber != null) {
          callFrame.currentLine = lineNumber;
          final suppressOwnLineHook = opcode == Opcode.jmp && word.sJ < 0;
          if (hasDebugHook &&
              opcode != Opcode.varArgPrep &&
              !suppressOwnLineHook) {
            _syncDebugLocals(frame, callFrame: callFrame);
            await debugInterpreter!.maybeFireLineDebugHook(
              lineNumber,
              force: forceLineHook,
            );
          }
        }
        switch (opcode) {
          case Opcode.move:
            {
              frame.setRegister(word.a, frame.register(word.b));
              break;
            }
          case Opcode.loadI:
            {
              frame.setRegister(word.a, framePrimitiveValue(runtime, word.sBx));
              break;
            }
          case Opcode.loadF:
            {
              frame.setRegister(
                word.a,
                framePrimitiveValue(runtime, word.sBx.toDouble()),
              );
              break;
            }
          case Opcode.loadK:
            {
              frame.setRegister(
                word.a,
                constantValue(runtime, prototype, word.bx),
              );
              break;
            }
          case Opcode.loadKx:
            {
              frame.setRegister(
                word.a,
                constantValue(runtime, prototype, _consumeExtraArg(frame).ax),
              );
              break;
            }
          case Opcode.loadFalse:
            {
              frame.setRegister(word.a, framePrimitiveValue(runtime, false));
              break;
            }
          case Opcode.lFalseSkip:
            {
              frame.setRegister(word.a, framePrimitiveValue(runtime, false));
              frame.pc += 1;
              break;
            }
          case Opcode.loadTrue:
            {
              frame.setRegister(word.a, framePrimitiveValue(runtime, true));
              break;
            }
          case Opcode.loadNil:
            {
              for (var index = 0; index <= word.b; index++) {
                frame.setRegister(
                  word.a + index,
                  framePrimitiveValue(runtime, null),
                );
              }
              break;
            }
          case Opcode.getUpval:
            {
              frame.setRegister(word.a, frame.closure.readUpvalue(word.b));
              break;
            }
          case Opcode.setUpval:
            {
              frame.closure.writeUpvalue(word.b, frame.register(word.a));
              break;
            }
          case Opcode.getTabUp:
            {
              final receiver = frame.closure.readUpvalue(word.b);
              final rawKey = stringConstantRaw(prototype, word.c);
              final fastValue = _tryFastTableGetStringKey(receiver, rawKey);
              if (fastValue != null) {
                frame.setRegister(word.a, fastValue);
                break;
              }
              final key = stringConstant(runtime, prototype, word.c);
              try {
                final value = await _tableGet(receiver, key);
                frame.setRegister(word.a, value);
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, word.a, error);
              } on LuaError catch (error) {
                throw _rewriteIndexOperandError(
                  frame,
                  receiver,
                  error,
                  labelOverride: "global '${rawLuaSlot(key)}'",
                );
              }
              break;
            }
          case Opcode.getTable:
            {
              final receiver = frame.register(word.b);
              final key = frame.register(word.c);
              final fastValue = _tryFastTableGet(receiver, key);
              if (fastValue != null) {
                frame.setRegister(word.a, fastValue);
                break;
              }
              try {
                final value = await _tableGet(receiver, key);
                frame.setRegister(word.a, value);
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, word.a, error);
              } on LuaError catch (error) {
                throw _rewriteIndexOperandError(frame, receiver, error);
              }
              break;
            }
          case Opcode.getI:
            {
              final receiver = frame.register(word.b);
              final key = runtime.constantPrimitiveValue(word.c);
              final fastValue = _tryFastTableGet(receiver, key);
              if (fastValue != null) {
                frame.setRegister(word.a, fastValue);
                break;
              }
              try {
                final value = await _tableGet(receiver, key);
                frame.setRegister(word.a, value);
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, word.a, error);
              } on LuaError catch (error) {
                throw _rewriteIndexOperandError(frame, receiver, error);
              }
              break;
            }
          case Opcode.getField:
            {
              final receiver = frame.register(word.b);
              final rawKey = stringConstantRaw(prototype, word.c);

              // Inline cache: per-storage Expando, keyed by (pc, fieldConst)
              if (rawLuaSlot(receiver) case final TableStorage storage) {
                final fieldCache = _getFieldIc[storage];
                if (fieldCache != null) {
                  final key = Object.hash(instructionPc, word.c);
                  final entry = fieldCache[key];
                  if (entry != null && entry.version == storage.icVersion) {
                    frame.setRegister(word.a, entry.value);
                    break;
                  }
                }
              }

              final fastValue = _tryFastTableGetStringKey(receiver, rawKey);
              if (fastValue != null) {
                if (rawLuaSlot(receiver) case final TableStorage storage) {
                  final fieldCache = _getFieldIc[storage] ??
                      <int, ({int version, Value value})>{};
                  final key = Object.hash(instructionPc, word.c);
                  fieldCache[key] = (
                    version: storage.icVersion,
                    value: fastValue,
                  );
                  _getFieldIc[storage] = fieldCache;
                }
                frame.setRegister(word.a, fastValue);
                break;
              }
              final key = stringConstant(runtime, prototype, word.c);
              try {
                final value = await _tableGet(receiver, key);
                frame.setRegister(word.a, value);
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, word.a, error);
              } on LuaError catch (error) {
                throw _rewriteIndexOperandError(frame, receiver, error);
              }
              break;
            }
          case Opcode.setTabUp:
            {
              final receiver = frame.closure.readUpvalue(word.a);
              final rawKey = stringConstantRaw(prototype, word.b);
              final value = rkValue(frame, word.c, word.kFlag);
              if (_tryFastTableSetStringKey(receiver, rawKey, value)) {
                break;
              }
              final key = stringConstant(runtime, prototype, word.b);
              try {
                await _tableSet(receiver, key, value);
              } on YieldException catch (error) {
                _suspendResumeOnly(frame, error);
              } on LuaError catch (error) {
                throw _rewriteIndexOperandError(
                  frame,
                  receiver,
                  error,
                  labelOverride: "global '${rawLuaSlot(key)}'",
                );
              }
              break;
            }
          case Opcode.checkGlobal:
            {
              final name = stringConstantRaw(prototype, word.bx);
              if (await explicitGlobalIsAlreadyDefined(
                frame.register(word.a),
                frame.closure.environment,
                name,
              )) {
                throw LuaError("global '$name' already defined");
              }
              break;
            }
          case Opcode.setTable:
            {
              final receiver = frame.register(word.a);
              final key = frame.register(word.b);
              final value = rkValue(frame, word.c, word.kFlag);
              if (_tryFastTableSet(receiver, key, value)) {
                break;
              }
              try {
                await _tableSet(receiver, key, value);
              } on YieldException catch (error) {
                _suspendResumeOnly(frame, error);
              } on LuaError catch (error) {
                throw _rewriteIndexOperandError(frame, receiver, error);
              }
              break;
            }
          case Opcode.setI:
            {
              final receiver = frame.register(word.a);
              final key = runtime.constantPrimitiveValue(word.b);
              final value = rkValue(frame, word.c, word.kFlag);
              if (_tryFastTableSet(receiver, key, value)) {
                break;
              }
              try {
                await _tableSet(receiver, key, value);
              } on YieldException catch (error) {
                _suspendResumeOnly(frame, error);
              } on LuaError catch (error) {
                throw _rewriteIndexOperandError(frame, receiver, error);
              }
              break;
            }
          case Opcode.setField:
            {
              final receiver = frame.register(word.a);
              final rawKey = stringConstantRaw(prototype, word.b);
              final value = rkValue(frame, word.c, word.kFlag);
              if (_tryFastTableSetStringKey(receiver, rawKey, value)) {
                break;
              }
              final key = stringConstant(runtime, prototype, word.b);
              try {
                await _tableSet(receiver, key, value);
              } on YieldException catch (error) {
                _suspendResumeOnly(frame, error);
              } on LuaError catch (error) {
                throw _rewriteIndexOperandError(frame, receiver, error);
              }
              break;
            }
          case Opcode.newTable:
            {
              final extra = word.kFlag
                  ? _consumeExtraArg(frame)
                  : _consumeOptionalZeroExtraArg(frame);
              final extraAx = extra?.ax ?? 0;
              final tableStorage = TableStorage();
              final arraySize =
                  word.vc +
                  (word.kFlag
                      ? extraAx * (LuaBytecodeInstructionLayout.maxArgVC + 1)
                      : 0);
              if (arraySize > 0) {
                tableStorage.ensureArrayCapacity(arraySize);
              }
              frame.setRegister(word.a, runtimeValue(runtime, tableStorage));
              break;
            }
          case Opcode.self:
            {
              final receiver = frame.register(word.b);
              frame.setRegister(word.a + 1, receiver);
              final rawKey = stringConstantRaw(prototype, word.c);
              final fastValue = _tryFastTableGetStringKey(receiver, rawKey);
              if (fastValue != null) {
                frame.setRegister(word.a, fastValue);
                break;
              }
              final key = stringConstant(runtime, prototype, word.c);
              try {
                final value = await _tableGet(receiver, key);
                frame.setRegister(word.a, value);
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, word.a, error);
              } on LuaError catch (error) {
                throw _rewriteIndexOperandError(frame, receiver, error);
              }
              break;
            }
          case Opcode.addI:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: runtime.constantPrimitiveValue(signedC(word)),
                operation: LuaBinaryOperation.add,
              );
              break;
            }
          case Opcode.addK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: constantValue(runtime, prototype, word.c),
                operation: LuaBinaryOperation.add,
              );
              break;
            }
          case Opcode.subK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: constantValue(runtime, prototype, word.c),
                operation: LuaBinaryOperation.sub,
              );
              break;
            }
          case Opcode.mulK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: constantValue(runtime, prototype, word.c),
                operation: LuaBinaryOperation.mul,
              );
              break;
            }
          case Opcode.modK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: constantValue(runtime, prototype, word.c),
                operation: LuaBinaryOperation.mod,
              );
              break;
            }
          case Opcode.powK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: constantValue(runtime, prototype, word.c),
                operation: LuaBinaryOperation.pow,
              );
              break;
            }
          case Opcode.divK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: constantValue(runtime, prototype, word.c),
                operation: LuaBinaryOperation.div,
              );
              break;
            }
          case Opcode.idivK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: constantValue(runtime, prototype, word.c),
                operation: LuaBinaryOperation.idiv,
              );
              break;
            }
          case Opcode.bandK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: constantValue(runtime, prototype, word.c),
                operation: LuaBinaryOperation.band,
              );
              break;
            }
          case Opcode.borK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: constantValue(runtime, prototype, word.c),
                operation: LuaBinaryOperation.bor,
              );
              break;
            }
          case Opcode.bxorK:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: constantValue(runtime, prototype, word.c),
                operation: LuaBinaryOperation.bxor,
              );
              break;
            }
          case Opcode.shlI:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: runtime.constantPrimitiveValue(signedC(word)),
                right: frame.register(word.b),
                operation: LuaBinaryOperation.shl,
              );
              break;
            }
          case Opcode.shrI:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: runtime.constantPrimitiveValue(signedC(word)),
                operation: LuaBinaryOperation.shr,
              );
              break;
            }
          case Opcode.add:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: LuaBinaryOperation.add,
              );
              break;
            }
          case Opcode.sub:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: LuaBinaryOperation.sub,
              );
              break;
            }
          case Opcode.mul:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: LuaBinaryOperation.mul,
              );
              break;
            }
          case Opcode.mod:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: LuaBinaryOperation.mod,
              );
              break;
            }
          case Opcode.pow:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: LuaBinaryOperation.pow,
              );
              break;
            }
          case Opcode.div:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: LuaBinaryOperation.div,
              );
              break;
            }
          case Opcode.idiv:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: LuaBinaryOperation.idiv,
              );
              break;
            }
          case Opcode.band:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: LuaBinaryOperation.band,
              );
              break;
            }
          case Opcode.bor:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: LuaBinaryOperation.bor,
              );
              break;
            }
          case Opcode.bxor:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: LuaBinaryOperation.bxor,
              );
              break;
            }
          case Opcode.shl:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: LuaBinaryOperation.shl,
              );
              break;
            }
          case Opcode.shr:
            {
              _executeBinaryInstruction(
                frame,
                targetRegister: word.a,
                left: frame.register(word.b),
                right: frame.register(word.c),
                leftRegister: word.b,
                rightRegister: word.c,
                operation: LuaBinaryOperation.shr,
              );
              break;
            }
          case Opcode.unm:
            {
              final operand = frame.register(word.b);
              final rawOperand = rawLuaSlot(operand);
              if (canFastPathNumeric(operand)) {
                frame.setRegister(
                  word.a,
                  runtimeValue(runtime, NumberUtils.negate(rawOperand)),
                );
                break;
              }
              try {
                frame.setRegister(
                  word.a,
                  await _executeUnaryInstruction(
                    frame,
                    operand,
                    operandRegister: word.b,
                    metamethod: '__unm',
                    fastPath: (value) => canFastPathNumeric(value)
                        ? runtimeValue(
                            runtime,
                            NumberUtils.negate(rawLuaSlot(value)),
                          )
                        : null,
                  ),
                );
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, word.a, error);
              }
              break;
            }
          case Opcode.bnot:
            {
              final operand = frame.register(word.b);
              final rawOperand = rawLuaSlot(operand);
              if (canFastPathInteger(operand)) {
                frame.setRegister(
                  word.a,
                  runtimeValue(runtime, NumberUtils.bitwiseNot(rawOperand)),
                );
                break;
              }
              try {
                frame.setRegister(
                  word.a,
                  await _executeUnaryInstruction(
                    frame,
                    operand,
                    operandRegister: word.b,
                    metamethod: '__bnot',
                    fastPath: (value) => canFastPathInteger(value)
                        ? runtimeValue(
                            runtime,
                            NumberUtils.bitwiseNot(rawLuaSlot(value)),
                          )
                        : null,
                  ),
                );
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, word.a, error);
              }
              break;
            }
          case Opcode.notOp:
            {
              frame.setRegister(
                word.a,
                runtimeValue(runtime, !isLuaTruthy(frame.register(word.b))),
              );
              break;
            }
          case Opcode.len:
            {
              final operand = frame.register(word.b);
              if (canFastPathLength(operand)) {
                frame.setRegister(
                  word.a,
                  runtimeValue(runtime, lengthOf(operand)),
                );
                break;
              }
              try {
                frame.setRegister(
                  word.a,
                  await _executeUnaryInstruction(
                    frame,
                    operand,
                    operandRegister: word.b,
                    metamethod: '__len',
                    fastPath: (value) => canFastPathLength(value)
                        ? runtimeValue(runtime, lengthOf(value))
                        : null,
                  ),
                );
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, word.a, error);
              }
              break;
            }
          case Opcode.concat:
            {
              frame.setRegister(
                word.a,
                await _executeConcatInstruction(frame, word.a, word.b),
              );
              break;
            }
          case Opcode.mmBin:
            {
              final targetRegister = _previousInstruction(frame).a;
              try {
                frame.setRegister(
                  targetRegister,
                  await _executeMetamethodBinaryInstruction(
                    frame,
                    metamethod: metamethodName(word.c),
                    left: frame.register(word.a),
                    right: frame.register(word.b),
                  ),
                );
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, targetRegister, error);
              }
              break;
            }
          case Opcode.mmBinI:
            {
              final immediate = runtime.constantPrimitiveValue(signedB(word));
              final (left, right) = word.kFlag
                  ? (immediate, frame.register(word.a))
                  : (frame.register(word.a), immediate);
              final targetRegister = _previousInstruction(frame).a;
              try {
                frame.setRegister(
                  targetRegister,
                  await _executeMetamethodBinaryInstruction(
                    frame,
                    metamethod: metamethodName(word.c),
                    left: left,
                    right: right,
                  ),
                );
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, targetRegister, error);
              }
              break;
            }
          case Opcode.mmBinK:
            {
              final constant = constantValue(runtime, prototype, word.b);
              final (left, right) = word.kFlag
                  ? (constant, frame.register(word.a))
                  : (frame.register(word.a), constant);
              final targetRegister = _previousInstruction(frame).a;
              try {
                frame.setRegister(
                  targetRegister,
                  await _executeMetamethodBinaryInstruction(
                    frame,
                    metamethod: metamethodName(word.c),
                    left: left,
                    right: right,
                  ),
                );
              } on YieldException catch (error) {
                _suspendStoreRegister(frame, targetRegister, error);
              }
              break;
            }
          case Opcode.tbc:
            {
              // Mark register A as a to-be-closed variable. If the value has
              // no __close metamethod, Value.toBeClose throws UnsupportedError.
              // markToBeClosed wraps that in LuaError with the Lua message, but
              // in some code paths (e.g. shared-primitive detach variants) the
              // UnsupportedError can escape unwrapped. Both catch arms normalise
              // the error and produce the Lua-spec message
              // "variable '<name>' got a non-closable value" when debug info is
              // available, so pcall sees a proper Lua string rather than a raw
              // Dart exception toString().
              try {
                frame.markToBeClosed(word.a);
              } on LuaError catch (error) {
                // markToBeClosed already wrapped the UnsupportedError; rewrite
                // the message to include the local variable name if debug info
                // is present and the message hasn't been rewritten yet.
                final localName = frame.localNameForError(word.a);
                if (localName != null &&
                    error.message ==
                        'to-be-closed variable value must have a __close metamethod') {
                  throw LuaError(
                    "variable '$localName' got a non-closable value",
                  );
                }
                rethrow;
              } on UnsupportedError catch (error) {
                // Belt-and-suspenders: catch UnsupportedError that escapes
                // markToBeClosed unwrapped (e.g. thrown by a code path
                // introduced by refactoring before the inner try/catch).
                // Apply the same local-name rewrite so the error message is
                // always Lua-spec compliant.
                final localName = frame.localNameForError(word.a);
                final baseMessage = error.message ?? error.toString();
                final message =
                    localName != null &&
                        baseMessage ==
                            'to-be-closed variable value must have a __close metamethod'
                    ? "variable '$localName' got a non-closable value"
                    : baseMessage;
                throw LuaError(message);
              }
              break;
            }
          case Opcode.varArgPrep:
            {
              if (debugInterpreter?.debugHookFunction != null &&
                  !frame.didFireEntryCallHook) {
                await _fireFrameCallHook(frame, debugInterpreter!);
                frame.forceNextLineHook = true;
              }
              break;
            }
          case Opcode.jmp:
            {
              frame.pc += word.sJ;
              if (word.sJ < 0) {
                _resetBackedgeLineHookState(
                  runtime,
                  _debugInterpreter,
                  frame,
                  callFrame: callFrame,
                  loopLine: lineNumber ?? previousVisibleLine,
                );
                if (_runGcLoopSafePoint(runtime, frame) case final gcWork?) {
                  await gcWork;
                }
              }
              break;
            }
          case Opcode.eq:
            {
              final left = frame.register(word.a);
              final right = frame.register(word.b);
              if (rawEquals(left, right)) {
                _docondjump(frame, word, true);
                break;
              }
              if (!supportsEqualityMetamethod(left, right) ||
                  (!left.hasMetamethod('__eq') &&
                      !right.hasMetamethod('__eq'))) {
                _docondjump(frame, word, false);
                break;
              }
              try {
                _docondjump(frame, word, await _compareEquals(left, right));
              } on YieldException catch (error) {
                _suspendConditionalJump(frame, word, error);
              }
              break;
            }
          case Opcode.lt:
            {
              final left = frame.register(word.a);
              final right = frame.register(word.b);
              final primitiveResult = tryPrimitiveOrdering(
                left,
                right,
                PrimitiveCompare.lessThan,
              );
              if (primitiveResult != null) {
                _docondjump(frame, word, primitiveResult);
                break;
              }
              try {
                _docondjump(
                  frame,
                  word,
                  await _compareOrdering(
                    left,
                    right,
                    metamethod: '__lt',
                    primitiveCompare: PrimitiveCompare.lessThan,
                  ),
                );
              } on YieldException catch (error) {
                _suspendConditionalJump(frame, word, error);
              }
              break;
            }
          case Opcode.le:
            {
              final left = frame.register(word.a);
              final right = frame.register(word.b);
              final primitiveResult = tryPrimitiveOrdering(
                left,
                right,
                PrimitiveCompare.lessThanOrEqual,
              );
              if (primitiveResult != null) {
                _docondjump(frame, word, primitiveResult);
                break;
              }
              try {
                _docondjump(
                  frame,
                  word,
                  await _compareOrdering(
                    left,
                    right,
                    metamethod: '__le',
                    primitiveCompare: PrimitiveCompare.lessThanOrEqual,
                  ),
                );
              } on YieldException catch (error) {
                _suspendConditionalJump(frame, word, error);
              }
              break;
            }
          case Opcode.eqK:
            {
              _docondjump(
                frame,
                word,
                rawEquals(
                  frame.register(word.a),
                  constantValue(runtime, prototype, word.b),
                ),
              );
              break;
            }
          case Opcode.eqI:
            {
              _docondjump(
                frame,
                word,
                compareImmediateEquals(frame.register(word.a), signedB(word)),
              );
              break;
            }
          case Opcode.ltI:
            {
              final left = frame.register(word.a);
              final right = signedB(word);
              final primitiveResult = tryPrimitiveImmediateOrdering(
                left,
                right,
                PrimitiveCompare.lessThan,
              );
              if (primitiveResult != null) {
                _docondjump(frame, word, primitiveResult);
                break;
              }
              try {
                _docondjump(
                  frame,
                  word,
                  await _compareImmediateOrdering(
                    left,
                    right,
                    metamethod: '__lt',
                    primitiveCompare: PrimitiveCompare.lessThan,
                  ),
                );
              } on YieldException catch (error) {
                _suspendConditionalJump(frame, word, error);
              }
              break;
            }
          case Opcode.leI:
            {
              final left = frame.register(word.a);
              final right = signedB(word);
              final primitiveResult = tryPrimitiveImmediateOrdering(
                left,
                right,
                PrimitiveCompare.lessThanOrEqual,
              );
              if (primitiveResult != null) {
                _docondjump(frame, word, primitiveResult);
                break;
              }
              try {
                _docondjump(
                  frame,
                  word,
                  await _compareImmediateOrdering(
                    left,
                    right,
                    metamethod: '__le',
                    primitiveCompare: PrimitiveCompare.lessThanOrEqual,
                  ),
                );
              } on YieldException catch (error) {
                _suspendConditionalJump(frame, word, error);
              }
              break;
            }
          case Opcode.gtI:
            {
              final left = frame.register(word.a);
              final right = signedB(word);
              final primitiveResult = tryPrimitiveImmediateOrdering(
                left,
                right,
                PrimitiveCompare.greaterThan,
              );
              if (primitiveResult != null) {
                _docondjump(frame, word, primitiveResult);
                break;
              }
              try {
                _docondjump(
                  frame,
                  word,
                  await _compareImmediateOrdering(
                    left,
                    right,
                    metamethod: '__lt',
                    primitiveCompare: PrimitiveCompare.greaterThan,
                    flipOperands: true,
                  ),
                );
              } on YieldException catch (error) {
                _suspendConditionalJump(frame, word, error);
              }
              break;
            }
          case Opcode.geI:
            {
              final left = frame.register(word.a);
              final right = signedB(word);
              final primitiveResult = tryPrimitiveImmediateOrdering(
                left,
                right,
                PrimitiveCompare.greaterThanOrEqual,
              );
              if (primitiveResult != null) {
                _docondjump(frame, word, primitiveResult);
                break;
              }
              try {
                _docondjump(
                  frame,
                  word,
                  await _compareImmediateOrdering(
                    left,
                    right,
                    metamethod: '__le',
                    primitiveCompare: PrimitiveCompare.greaterThanOrEqual,
                    flipOperands: true,
                  ),
                );
              } on YieldException catch (error) {
                _suspendConditionalJump(frame, word, error);
              }
              break;
            }
          case Opcode.test:
            {
              _docondjump(frame, word, isLuaTruthy(frame.register(word.a)));
              break;
            }
          case Opcode.testSet:
            {
              final value = frame.register(word.b);
              final shouldSkipJump = !isLuaTruthy(value) == word.kFlag;
              if (shouldSkipJump) {
                frame.pc += 1;
              } else {
                frame.setRegister(word.a, value);
              }
              break;
            }
          case Opcode.call:
            {
              try {
                final callee = frame.register(word.a);
                final rawCallee = rawLuaSlot(callee);
                if (profile case final activeProfile?) {
                  activeProfile.recordCallTarget(
                    _callSiteTargetLabel(frame, word.a, callee) ??
                        rawCallee.runtimeType.toString(),
                  );
                }
                if (_debugInterpreter?.debugHookFunction == null &&
                    rawCallee is BuiltinFunction &&
                    word.b != 0) {
                  final fixedArityInlineResult =
                      _tryHandleFixedArityInlineBuiltinCall(
                        frame,
                        word,
                        callee,
                        rawCallee,
                      );
                  if (!identical(
                    fixedArityInlineResult,
                    inlineBuiltinUnhandled,
                  )) {
                    nextOpenTop = fixedArityInlineResult as int?;
                    break;
                  }
                }
                final callTop = word.b == 0
                    ? frame.effectiveTop
                    : word.a + word.b;
                frame.top = callTop;
                frame.openTop = word.b == 0 ? callTop : null;
                if (_debugFileOps) {
                  final nameInfo = _callSiteNameInfo(frame, word.a, callee);
                  final receiver =
                      word.b >= 2 && word.a + 1 < frame.registers.length
                      ? frame.register(word.a + 1)
                      : null;
                  final receiverDetail = switch (rawLuaSlot(receiver)) {
                    final LuaFile file =>
                      ' receiverValue=${identityHashCode(receiver)}'
                          ' receiverRaw=${identityHashCode(file)}'
                          ' trackedValue=${identityHashCode(IOLib.trackedOpenFileWrapper(file))}',
                    _ => '',
                  };
                  debugFileLog(
                    'CALL pc=${frame.pc - 1} a=${word.a} b=${word.b} c=${word.c} '
                    'callee=${rawCallee.runtimeType} name=${nameInfo.name}'
                    '$receiverDetail',
                  );
                }
                List<Value>? results;
                if (_debugInterpreter?.debugHookFunction == null &&
                    rawCallee is BuiltinFunction &&
                    _canInlineBuiltinWithoutManagedFrame(rawCallee)) {
                  final storedAssertResult = _tryStoreInlineAssertSuccess(
                    frame,
                    word,
                    builtin: rawCallee,
                  );
                  if (!identical(storedAssertResult, inlineBuiltinUnhandled)) {
                    nextOpenTop = storedAssertResult as int?;
                    break;
                  } else {
                    if (rawCallee.isBytecodeAssertBuiltin) {
                      results = await _callAt(frame, word);
                    } else {
                      final rawFastResult =
                          _tryInlineBuiltinFastArityRawFromFrame(
                            frame,
                            word,
                            builtin: rawCallee,
                          );
                      if (!identical(
                        rawFastResult,
                        BuiltinFunction.fastCallUnsupported,
                      )) {
                        final storedFastResult = _tryStoreFastInlineResult(
                          frame,
                          word.a,
                          word.c,
                          rawFastResult,
                        );
                        if (!identical(
                          storedFastResult,
                          inlineBuiltinUnhandled,
                        )) {
                          nextOpenTop = storedFastResult as int?;
                          break;
                        }
                      }
                      results = await _invokeInlineBuiltinFromFrame(
                        callee,
                        frame,
                        word,
                        builtin: rawCallee,
                      );
                    }
                  }
                } else {
                  if (rawCallee case final LuaBytecodeClosure closure) {
                    final nameInfo = _callSiteNameInfo(frame, word.a, callee);
                    final callArgs = LuaBytecodeFrameArgsView(
                      frame,
                      start: word.a + 1,
                      count: word.b == 0
                          ? frame.effectiveTop - (word.a + 1)
                          : word.b - 1,
                    );
                    results = await invoke(
                      closure,
                      callArgs,
                      functionValue: callee,
                      callName: nameInfo.name,
                      callNameWhat: nameInfo.namewhat,
                    );
                  } else {
                    results = await _callAt(frame, word);
                  }
                }
                if (word.c == 1) {
                  await _closeDiscardedCallResults(frame, results);
                }
                nextOpenTop = _storeCallResults(frame, word.a, word.c, results);
              } on YieldException catch (error) {
                _suspendCall(frame, word.a, word.c, error);
              }
              break;
            }
          case Opcode.tailCall:
            {
              try {
                final callTop = word.b == 0
                    ? frame.effectiveTop
                    : word.a + word.b;
                frame.top = callTop;
                frame.openTop = word.b == 0 ? callTop : null;
                final call = _resolveCall(frame, word);
                final rawCallee = rawLuaSlot(call.callee);
                final debugHooksEnabled =
                    _debugInterpreter?.debugHookFunction != null;

                // Fast path: tail calls between bytecode closures with no
                // debug hooks. Close the frame synchronously, then hand the
                // callee back through TailCallException so invoke() can reuse
                // its existing tail-call loop without re-flattening.
                if (rawCallee is LuaBytecodeClosure && !debugHooksEnabled) {
                  if (!_closeFrameForCoroutineSync(frame)) {
                    await _closeFrameForCoroutine(frame, error: null);
                  }
                  throw TailCallException(call.callee, call.args);
                }

                // Slow path: metatables, debug hooks, or non-closure callees.
                // We still compute the call-site label here so non-function
                // tail-call errors keep their field/method/global names.
                final tailName = _callSiteTargetLabel(frame, word.a, call.callee);
                final tailNameInfo = _decodeTailCallNameInfo(tailName);
                final prepared = _flattenTailCallable(call.callee, call.args);
                final callee = prepared.callee;
                if (rawLuaSlot(callee) is LuaBytecodeClosure) {
                  if (!_closeFrameForCoroutineSync(frame)) {
                    await _closeFrameForCoroutine(frame, error: null);
                  }
                  throw TailCallException(
                    callee,
                    prepared.args,
                    callName: tailName,
                  );
                }
                final results = await _invokePreparedCall(
                  (callee: callee, args: prepared.args),
                  frame: frame,
                  callName: tailNameInfo.name,
                  callNameWhat: tailNameInfo.namewhat,
                  isTailCall: true,
                );
                if (!_closeFrameForCoroutineSync(frame)) {
                  await _closeFrameForCoroutine(frame, error: null);
                }
                return results;
              } on YieldException catch (error) {
                _suspendTailCall(frame, error);
              }
            }
          case Opcode.return_:
            {
              try {
                if (!_closeFrameForCoroutineSync(frame)) {
                  await _closeFrameForCoroutine(frame, error: null);
                }
                final resultCount = word.b == 0
                    ? frame.effectiveTop - word.a
                    : word.b - 1;
                return frame.resultsFrom(word.a, resultCount);
              } on YieldException catch (error) {
                _suspendReturn(frame, word.a, word.b, error);
              }
            }
          case Opcode.return0:
            {
              try {
                if (!_closeFrameForCoroutineSync(frame)) {
                  await _closeFrameForCoroutine(frame, error: null);
                }
                return const <Value>[];
              } on YieldException catch (error) {
                _suspendReturn(frame, 0, 1, error);
              }
            }
          case Opcode.return1:
            {
              try {
                if (!_closeFrameForCoroutineSync(frame)) {
                  await _closeFrameForCoroutine(frame, error: null);
                }
                return <Value>[frame.register(word.a)];
              } on YieldException catch (error) {
                _suspendReturn(frame, word.a, 2, error);
              }
            }
          case Opcode.forPrep:
            {
              if (_forPrep(frame, word.a)) {
                frame.pc += word.bx + 1;
              }
              break;
            }
          case Opcode.forLoop:
            {
              if (_forLoop(frame, word.a)) {
                frame.pc -= word.bx;
                _resetBackedgeLineHookState(
                  runtime,
                  _debugInterpreter,
                  frame,
                  callFrame: callFrame,
                  loopLine: lineNumber ?? previousVisibleLine,
                );
                if (_runGcLoopSafePoint(runtime, frame) case final gcWork?) {
                  await gcWork;
                }
              }
              break;
            }
          case Opcode.tForPrep:
            {
              final closingValue = frame.register(word.a + 3);
              final controlValue = frame.register(word.a + 2);
              frame.setRegister(word.a + 2, closingValue);
              frame.setRegister(word.a + 3, controlValue);
              frame.markToBeClosed(word.a + 2);
              frame.pc += word.bx;
              break;
            }
          case Opcode.tForCall:
            {
              try {
                final results = await _genericForCall(frame, word.a, word.c);
                for (var index = 0; index < results.length; index++) {
                  frame.setRegister(word.a + 3 + index, results[index]);
                }
                frame.top = word.a + 3 + results.length;
              } on YieldException catch (error) {
                _suspendTForCall(frame, word.a, word.c, error);
              }
              break;
            }
          case Opcode.tForLoop:
            {
              if (!isLuaNilSlot(frame.register(word.a + 3))) {
                frame.pc -= word.bx;
                if (_runGcLoopSafePoint(runtime, frame) case final gcWork?) {
                  await gcWork;
                }
              }
              break;
            }
          case Opcode.setList:
            {
              await _setList(frame, word);
              break;
            }
          case Opcode.closure:
            {
              final child = prototype.prototypes[word.bx];
              frame.setRegister(
                word.a,
                wrapClosure(_createClosure(frame, child)),
              );
              break;
            }
          case Opcode.varArg:
            {
              nextOpenTop = _storeVarargResults(frame, word);
              break;
            }
          case Opcode.getVarArg:
            {
              final keyValue = frame.register(word.c);
              final rawKey = rawLuaSlot(keyValue);
              final index = switch (rawKey) {
                final int integer => integer,
                final BigInt integer => NumberUtils.tryToInteger(integer),
                final double number
                    when number.isFinite &&
                        number.truncateToDouble() == number =>
                  number.toInt(),
                _ => null,
              };
              if (index != null) {
                if (index < 1 || index > frame.varargCount) {
                  frame.setRegister(
                    word.a,
                    runtime.constantPrimitiveValue(null),
                  );
                } else {
                  frame.setRegister(word.a, frame.varargAt(index - 1)!);
                }
              } else {
                final keyText = switch (rawKey) {
                  final String text => text,
                  final LuaString text => text.toString(),
                  _ => null,
                };
                if (keyText == 'n') {
                  frame.setRegister(
                    word.a,
                    runtime.constantPrimitiveValue(frame.varargCount),
                  );
                } else {
                  frame.setRegister(
                    word.a,
                    runtime.constantPrimitiveValue(null),
                  );
                }
              }
              break;
            }
          case Opcode.close:
            {
              if (word.b != 0) {
                break;
              }
              if (_debugFileOps) {
                debugFileLog(
                  'CLOSE pc=${frame.pc - 1} fromRegister=${word.a} '
                  'toBeClosed=${frame.toBeClosedRegisters}',
                );
              }
              if (!frame.hasCloseWorkFrom(word.a)) {
                break;
              }
              try {
                await _closeFrameForCoroutine(
                  frame,
                  fromRegister: word.a,
                  error: null,
                );
              } on YieldException catch (error) {
                _suspendClose(frame, word.a, error);
              }
              break;
            }
          case Opcode.extraArg:
            {
              throw LuaError(
                _opcodeDiagnostic(
                  frame,
                  opcode.luaName,
                  detail: 'unexpected EXTRAARG without a consuming opcode',
                ),
              );
            }
          case Opcode.errNNil:
            {
              if (!isLuaNilSlot(frame.register(word.a))) {
                throw LuaError('attempt to use a nil value');
              }
              break;
            }
        }

        if (hasDebugHook && deferCountHook) {
          _syncDebugLocals(frame, callFrame: callFrame);
          await debugInterpreter!.maybeFireCountDebugHook();
        }
        frame.openTop = nextOpenTop;
      } finally {
        if (opTimer != null) {
          opTimer.stop();
          profile!.record(opcode.luaName, opTimer.elapsedMicroseconds);
        }
      }
    }

    await _closeFrameForCoroutine(frame, error: null);
    return const <Value>[];
  }

  Future<void> _preserveSuspendingBytecodeBoundary({
    required Coroutine? currentCoroutine,
    required Coroutine mainThread,
  }) async {
    if (_debugInterpreter?.debugHookFunction != null) {
      return;
    }
    if (currentCoroutine != null && !identical(currentCoroutine, mainThread)) {
      // Non-main coroutines still rely on the legacy per-opcode async split to
      // preserve suspended expression state across yield/resume hops. Keep that
      // broader boundary only there so hot main-thread loops stay fast.
      await Future<void>.value();
      return;
    }
    // Yield-sensitive bytecode opcodes relied on the old per-opcode hook awaits
    // to create an async boundary before entering resumable metamethod logic.
    // Preserve that boundary only for opcodes that can suspend through
    // metamethod/table fallback instead of paying it on every instruction.
    await Future<void>.value();
  }

  /// Like [OpcodeAnalysis.needsSuspendingBoundary] but with per-operand
  /// refinement. The caller must have already confirmed
  /// `opcode.needsSuspendingBoundary` before calling this.
  bool _needsSuspendingOpcodeBoundaryForInstruction(
    LuaBytecodeFrame frame,
    Opcode opcode,
    LuaBytecodeInstructionWord word,
  ) {
    return switch (opcode) {
      Opcode.call ||
      Opcode.tailCall => !_canSkipSuspendingBoundaryForCall(frame, word.a),
      Opcode.eq => !_canSkipSuspendingBoundaryForEquality(
        frame.register(word.a),
        frame.register(word.b),
      ),
      Opcode.lt || Opcode.le => !_canSkipSuspendingBoundaryForOrdering(
        frame.register(word.a),
        frame.register(word.b),
        primitiveCompare: opcode == Opcode.lt
            ? PrimitiveCompare.lessThan
            : PrimitiveCompare.lessThanOrEqual,
      ),
      Opcode.ltI ||
      Opcode.leI ||
      Opcode.gtI ||
      Opcode.geI => !_canSkipSuspendingBoundaryForImmediateOrdering(
        frame.register(word.a),
        signedB(word),
        primitiveCompare: switch (opcode) {
          Opcode.ltI => PrimitiveCompare.lessThan,
          Opcode.leI => PrimitiveCompare.lessThanOrEqual,
          Opcode.gtI => PrimitiveCompare.greaterThan,
          Opcode.geI => PrimitiveCompare.greaterThanOrEqual,
          _ => throw StateError('unreachable opcode $opcode'),
        },
      ),
      Opcode.unm => !_canSkipSuspendingBoundaryForUnary(
        frame.register(word.b),
        '__unm',
      ),
      Opcode.bnot => !_canSkipSuspendingBoundaryForUnary(
        frame.register(word.b),
        '__bnot',
      ),
      Opcode.len => !_canSkipSuspendingBoundaryForUnary(
        frame.register(word.b),
        '__len',
      ),
      Opcode.getTabUp => !_canSkipSuspendingBoundaryForTableGet(
        frame.closure.readUpvalue(word.b),
        rawStringKey: stringConstantRaw(frame.closure.prototype, word.c),
      ),
      Opcode.getTable ||
      Opcode.getI ||
      Opcode.getField => !_canSkipSuspendingBoundaryForTableGet(
        frame.register(word.b),
        key: switch (opcode) {
          Opcode.getTable => frame.register(word.c),
          Opcode.getI => runtime.constantPrimitiveValue(word.c),
          _ => null,
        },
        rawStringKey: switch (opcode) {
          Opcode.getField => stringConstantRaw(frame.closure.prototype, word.c),
          _ => null,
        },
      ),
      Opcode.setTabUp => !_canSkipSuspendingBoundaryForTableSet(
        frame.closure.readUpvalue(word.a),
      ),
      Opcode.setTable || Opcode.setI || Opcode.setField =>
        !_canSkipSuspendingBoundaryForTableSet(frame.register(word.a)),
      Opcode.close => word.b == 0 && frame.hasCloseWorkFrom(word.a),
      Opcode.return_ ||
      Opcode.return0 ||
      Opcode.return1 => frame.hasCloseWorkFrom(0),
      _ => true,
    };
  }

  bool _canSkipSuspendingBoundaryForCall(
    LuaBytecodeFrame frame,
    int calleeRegister,
  ) {
    // Direct calls already await inside the callee's invoke/callFunction
    // path; the pre-call boundary was only buying us an extra async hop.
    // That hop showed up heavily in `calls.lua`, which is mostly nested
    // function and tail calls, so we skip it for the hot call opcode.
    return true;
  }

  bool _canSkipSuspendingBoundaryForTableGet(
    Value table, {
    Value? key,
    String? rawStringKey,
  }) {
    final rawTable = rawLuaSlot(table);
    final hasWeakMode = table.tableWeakMode != null;
    if (rawStringKey != null &&
        _canFastPathGlobalProxyTableGetStringKey(table, rawStringKey)) {
      return true;
    }
    if (key != null && _canFastPathGlobalProxyTableGet(table, key)) {
      return true;
    }
    return (rawTable is TableStorage || rawTable is Map) &&
        !hasWeakMode &&
        !table.hasMetamethod('__index');
  }

  bool _canSkipSuspendingBoundaryForEquality(Value left, Value right) {
    if (rawEquals(left, right)) {
      return true;
    }
    if (!supportsEqualityMetamethod(left, right)) {
      return true;
    }
    return !left.hasMetamethod('__eq') && !right.hasMetamethod('__eq');
  }

  bool _canSkipSuspendingBoundaryForOrdering(
    Value left,
    Value right, {
    required PrimitiveCompare primitiveCompare,
  }) {
    return tryPrimitiveOrdering(left, right, primitiveCompare) != null;
  }

  bool _canSkipSuspendingBoundaryForImmediateOrdering(
    Value left,
    int right, {
    required PrimitiveCompare primitiveCompare,
  }) {
    return tryPrimitiveImmediateOrdering(left, right, primitiveCompare) != null;
  }

  bool _canSkipSuspendingBoundaryForUnary(Value operand, String metamethod) {
    return switch (metamethod) {
      '__unm' => canFastPathNumeric(operand),
      '__bnot' => canFastPathInteger(operand),
      '__len' => canFastPathLength(operand),
      _ => false,
    };
  }

  bool _canSkipSuspendingBoundaryForTableSet(Value table) {
    final rawTable = rawLuaSlot(table);
    final hasWeakMode = table.tableWeakMode != null;
    return (rawTable is TableStorage || rawTable is Map) &&
        !hasWeakMode &&
        !table.hasMetamethod('__newindex') &&
        !table.hasMetamethod('__index');
  }

  String _opcodeDiagnostic(
    LuaBytecodeFrame frame,
    String opcodeName, {
    String? detail,
  }) {
    final pc = frame.pc - 1;
    final prototype = frame.closure.prototype;
    final location = <String>['pc $pc'];
    final line = prototype.lineForPc(pc);
    if (line != null) {
      location.add('line $line');
    }
    final source = prototype.source ?? frame.closure.chunkName;
    if (source.isNotEmpty) {
      location.add(source);
    }
    final suffix = detail == null ? '' : ': $detail';
    return 'unsupported lua_bytecode opcode $opcodeName '
        '(${location.join(', ')})$suffix';
  }

  ({Value callee, List<Object?> args}) _resolveCall(
    LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word,
  ) {
    final callee = frame.register(word.a);
    final args = _callArgsFromFrame(frame, word);
    return (callee: callee, args: args);
  }

  List<Object?> _callArgsFromFrame(
    LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word,
  ) {
    final start = word.a + 1;
    final count = word.b == 0 ? frame.effectiveTop - start : word.b - 1;
    return frame.resultsFrom(start, count);
  }

  Coroutine _requireCoroutineForYield(
    LuaBytecodeFrame frame,
    YieldException error,
  ) {
    final coroutine = error.coroutine ?? runtime.getCurrentCoroutine();
    if (coroutine != null) {
      return coroutine;
    }
    throw LuaError(
      _opcodeDiagnostic(
        frame,
        'YIELD',
        detail: 'attempt to yield without an active coroutine',
      ),
    );
  }

  List<Value> _normalizeResults(Object? result) {
    if (result == null) {
      return const <Value>[];
    }
    final resultValues = luaResultValues(result);
    if (resultValues != null) {
      return resultValues
          .map((item) => runtimeValue(runtime, item))
          .toList(growable: false);
    }
    return switch (result) {
      final Value value => <Value>[runtimeValue(runtime, value)],
      final List<Object?> values =>
        values
            .map((item) => runtimeValue(runtime, item))
            .toList(growable: false),
      _ => <Value>[runtimeValue(runtime, result)],
    };
  }
}

String orderComparisonError(Value left, Value right) {
  final leftType = getLuaType(left);
  final rightType = getLuaType(right);
  return leftType == rightType
      ? 'attempt to compare two $leftType values'
      : 'attempt to compare $leftType with $rightType';
}

void _resetBackedgeLineHookState(
  LuaRuntime runtime,
  Interpreter? debugInterpreter,
  LuaBytecodeFrame frame, {
  CallFrame? callFrame,
  required int loopLine,
}) {
  // Without a debug interpreter the line-hook state is never consulted.
  if (debugInterpreter == null) {
    return;
  }
  final targetLine = frame.closure.prototype.lineForPc(frame.pc);
  if (targetLine == null || targetLine != loopLine) {
    return;
  }
  final targetCallFrame = callFrame ?? runtime.callStack.top;
  targetCallFrame?.lastDebugHookLine = -1;
  debugInterpreter.rememberDebugHookLine(
    -1,
    source: targetCallFrame?.scriptPath ?? runtime.currentScriptPath,
  );
}

void _resetResumeLineHookState(
  LuaRuntime runtime,
  Interpreter? debugInterpreter,
  LuaBytecodeFrame frame, {
  CallFrame? callFrame,
}) {
  final targetCallFrame = callFrame ?? runtime.callStack.top;
  targetCallFrame?.lastDebugHookLine = -1;
  debugInterpreter?.rememberDebugHookLine(
    -1,
    source: frame.closure.debugInfo.source,
  );
}
