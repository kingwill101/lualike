import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/exceptions.dart';
import 'package:lualike/src/gc/gc.dart';
import 'package:lualike/src/ast.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/instruction.dart';
import 'package:lualike/src/lua_bytecode/opcode.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/number.dart';
import 'package:lualike/src/number_limits.dart';
import 'package:lualike/src/number_utils.dart';
import 'package:lualike/src/runtime/vararg_table.dart';
import 'package:lualike/src/parse.dart' show looksLikeLuaFilePath, luaChunkId;
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/table_storage.dart';
import 'package:lualike/src/utils/type.dart' show getLuaType;
import 'package:lualike/src/value.dart';
import 'package:path/path.dart' as path;
import 'dart:io' as io;

final bool _debugFileOps =
    io.Platform.environment['LUALIKE_DEBUG_FILE_OPS'] == '1';

void _debugFileLog(String message) {
  if (_debugFileOps) {
    print('[file-debug] $message');
  }
}

abstract interface class LuaBytecodeGCRootProvider {
  Iterable<GCObject> gcReferences();
}

enum _LuaBinaryOperation {
  add('+'),
  sub('-'),
  mul('*'),
  mod('%'),
  pow('^'),
  div('/'),
  idiv('//'),
  band('&', integerOnly: true),
  bor('|', integerOnly: true),
  bxor('bxor', integerOnly: true),
  shl('<<', integerOnly: true),
  shr('>>', integerOnly: true),
  concat('..', isConcat: true);

  const _LuaBinaryOperation(
    this.operatorSymbol, {
    this.integerOnly = false,
    this.isConcat = false,
  });

  final String operatorSymbol;
  final bool integerOnly;
  final bool isConcat;
}

final class LuaBytecodeClosure extends BuiltinFunction
    implements LuaCallableArtifact {
  factory LuaBytecodeClosure.main({
    required LuaRuntime runtime,
    required LuaBytecodeBinaryChunk chunk,
    required String chunkName,
    required Environment environment,
  }) {
    final upvalues = List<_LuaBytecodeUpvalue>.generate(
      chunk.rootUpvalueCount,
      (_) => _LuaBytecodeUpvalue.closed(_runtimeValue(runtime, null)),
      growable: false,
    );
    final shouldBindEnvironment =
        chunk.mainPrototype.upvalues.isNotEmpty &&
        (chunk.mainPrototype.upvalues.first.kind ==
                LuaBytecodeUpvalueKind.globalRegister ||
            chunk.mainPrototype.upvalues.first.name == '_ENV');
    if (upvalues.isNotEmpty && shouldBindEnvironment) {
      final envValue = environment.get('_ENV') ?? environment.root.get('_G');
      upvalues[0] = _LuaBytecodeUpvalue.closed(
        _runtimeValue(runtime, envValue),
      );
    }
    return LuaBytecodeClosure._(
      runtime: runtime,
      prototype: chunk.mainPrototype,
      chunkName: chunkName,
      environment: environment,
      upvalues: upvalues,
    );
  }

  LuaBytecodeClosure._({
    required this.runtime,
    required this.prototype,
    required this.chunkName,
    required this.environment,
    required List<_LuaBytecodeUpvalue> upvalues,
  }) : _upvalues = upvalues,
       super(runtime);

  final LuaRuntime runtime;
  final LuaBytecodePrototype prototype;
  final String chunkName;
  final Environment environment;
  final List<_LuaBytecodeUpvalue> _upvalues;

  int get upvalueCount => _upvalues.length;

  String? upvalueName(int index) => prototype.upvalues[index].name;

  Value readUpvalue(int index) => _upvalues[index].read();

  void writeUpvalue(int index, Value value) {
    _upvalues[index].write(value);
  }

  Object upvalueIdentity(int index) => _upvalues[index];

  void joinUpvalueWith(int index, LuaBytecodeClosure other, int otherIndex) {
    _upvalues[index] = other._upvalues[otherIndex];
  }

  @override
  LuaFunctionDebugInfo get debugInfo {
    final source = prototype.source ?? chunkName;
    return LuaFunctionDebugInfo(
      source: source,
      shortSource: _shortSource(source),
      what: 'Lua',
      lineDefined: prototype.lineDefined,
      lastLineDefined: prototype.lastLineDefined,
      nups: _upvalues.length,
      nparams: prototype.parameterCount,
      isVararg: prototype.isVararg,
    );
  }

  @override
  Future<Object?> call(List<Object?> args) async {
    final vm = LuaBytecodeVm(runtime);
    final results = await vm.invoke(this, args, isEntryFrame: true);
    return _packCallResults(runtime, results);
  }
}

final class LuaBytecodeVm {
  LuaBytecodeVm(this.runtime);

  final LuaRuntime runtime;

  Interpreter? get _debugInterpreter {
    if (runtime is Interpreter) {
      return runtime as Interpreter;
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

  Future<List<Value>> invoke(
    LuaBytecodeClosure closure,
    List<Object?> args, {
    String? callName,
    bool isEntryFrame = false,
    int extraArgs = 0,
  }) async {
    var currentClosure = closure;
    var currentArgs = args;
    var currentCallName = callName;
    var currentIsEntryFrame = isEntryFrame;
    var currentExtraArgs = extraArgs;

    while (true) {
      final callStackBaseDepth =
          runtime.getCurrentCoroutine()?.callStackBaseDepth ?? 0;
      if ((runtime.callStack.depth - callStackBaseDepth) >=
          Interpreter.maxCallDepth) {
        throw LuaError('C stack overflow');
      }

      final frame = _LuaBytecodeFrame(
        runtime: runtime,
        closure: currentClosure,
        arguments: currentArgs,
        callName: currentCallName,
        isEntryFrame: currentIsEntryFrame,
        extraArgs: currentExtraArgs,
      );

      try {
        return await _runFrame(frame);
      } on TailCallException catch (tail) {
        final prepared = _flattenTailCallable(
          tail.functionValue is Value
              ? tail.functionValue as Value
              : Value(tail.functionValue),
          tail.args
              .map((arg) => arg is Value ? arg : _runtimeValue(runtime, arg))
              .toList(growable: false),
        );
        final callee = prepared.callee;
        callee.interpreter ??= runtime;
        if (callee.raw case final LuaBytecodeClosure nextClosure) {
          currentClosure = nextClosure;
          currentArgs = prepared.args;
          currentCallName = tail.callName ?? currentCallName;
          currentExtraArgs = prepared.extraArgs;
          continue;
        }
        return _invokeValueWithName(
          callee,
          prepared.args,
          callName: tail.callName ?? currentCallName,
          extraArgs: prepared.extraArgs,
        );
      }
    }
  }

  ({Value callee, List<Value> args, int extraArgs}) _flattenTailCallable(
    Value callee,
    List<Value> args,
  ) {
    var extraArgs = 0;
    while (true) {
      callee.interpreter ??= runtime;
      switch (callee.raw) {
        case LuaBytecodeClosure():
        case Function():
        case BuiltinFunction():
        case FunctionDef():
        case FunctionLiteral():
        case FunctionBody():
        case LuaCallableArtifact():
          return (callee: callee, args: args, extraArgs: extraArgs);
        case String():
          final rebound = runtime.globals.get(callee.raw);
          if (rebound != null) {
            callee = rebound;
            continue;
          }
          return (callee: callee, args: args, extraArgs: extraArgs);
        default:
          if (!callee.hasMetamethod('__call')) {
            return (callee: callee, args: args, extraArgs: extraArgs);
          }
          final callMeta = callee.getMetamethod('__call');
          if (callMeta == null) {
            return (callee: callee, args: args, extraArgs: extraArgs);
          }
          if (extraArgs >= 15) {
            throw LuaError("'__call' chain too long");
          }
          final originalCallee = callee;
          callee = callMeta is Value ? callMeta : Value(callMeta);
          args = <Value>[originalCallee, ...args];
          extraArgs += 1;
      }
    }
  }

  Future<List<Value>> _runFrame(_LuaBytecodeFrame frame) async {
    final closure = frame.closure;
    final previousEnv = runtime.getCurrentEnv();
    final previousScriptPath = runtime.currentScriptPath;
    final previousCallStackScriptPath = runtime.callStack.scriptPath;
    final parentFrame = runtime.callStack.top;
    (runtime as dynamic).pushActiveFrameRoots(frame);
    runtime.setCurrentEnv(closure.environment);
    final activeScriptPath = closure.prototype.source ?? previousScriptPath;
    runtime.currentScriptPath = activeScriptPath;
    runtime.callStack.setScriptPath(activeScriptPath);
    final callableValue = Value(
      closure,
      functionName: frame.callName ?? closure.debugInfo.shortSource,
    )..interpreter = runtime;
    runtime.callStack.push(
      frame.callName ?? closure.debugInfo.shortSource,
      env: closure.environment,
      debugName: frame.callName,
      debugNameWhat: frame.callName == 'hook' ? 'hook' : '',
      callable: callableValue,
    );
    if (parentFrame?.isDebugHook == true && runtime.callStack.top != null) {
      runtime.callStack.top!.isDebugHook = true;
    }
    runtime.callStack.top?.extraArgs = frame.extraArgs;
    _syncDebugLocals(frame);
    final entryDebugInterpreter = _debugInterpreter;
    if (entryDebugInterpreter != null) {
      final interpreter = entryDebugInterpreter;
      await interpreter.fireDebugHook('call');
    }

    var suspended = false;
    var poppedCallFrame = false;
    try {
      return await _executeFrame(frame);
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
    } catch (error) {
      runtime.callStack.pop();
      poppedCallFrame = true;
      if (!frame.closed) {
        await frame.closeResources(fromRegister: 0, error: error);
      }
      rethrow;
    } finally {
      (runtime as dynamic).popActiveFrameRoots(frame);
      if (!suspended && !frame.closed) {
        await frame.closeResources(fromRegister: 0);
      }
      final exitDebugInterpreter = _debugInterpreter;
      if (!poppedCallFrame && exitDebugInterpreter != null) {
        final interpreter = exitDebugInterpreter;
        await interpreter.fireDebugHook('return');
      }
      if (!poppedCallFrame) {
        runtime.callStack.pop();
      }
      runtime.callStack.setScriptPath(previousCallStackScriptPath);
      runtime.currentScriptPath = previousScriptPath;
      runtime.setCurrentEnv(previousEnv);
    }
  }

  Future<List<Value>> _runFrameWithTailCalls(_LuaBytecodeFrame frame) async {
    while (true) {
      try {
        return await _runFrame(frame);
      } on TailCallException catch (tail) {
        final prepared = _flattenTailCallable(
          tail.functionValue is Value
              ? tail.functionValue as Value
              : Value(tail.functionValue),
          tail.args
              .map((arg) => arg is Value ? arg : _runtimeValue(runtime, arg))
              .toList(growable: false),
        );
        final callee = prepared.callee;
        callee.interpreter ??= runtime;
        if (callee.raw case final LuaBytecodeClosure nextClosure) {
          return invoke(
            nextClosure,
            prepared.args,
            callName: tail.callName,
            extraArgs: prepared.extraArgs,
          );
        }
        return _invokeValueWithName(
          callee,
          prepared.args,
          callName: tail.callName,
          extraArgs: prepared.extraArgs,
        );
      }
    }
  }

  Future<List<Value>> _executeFrame(_LuaBytecodeFrame frame) async {
    final prototype = frame.closure.prototype;
    while (frame.pc < prototype.code.length) {
      frame.expireDeadLocals();
      _syncCurrentCoroutine();
      _syncDebugLocals(frame);
      if (++frame.safePointCounter >= 64) {
        frame.safePointCounter = 0;
        (runtime as dynamic).runAutoGcAtSafePoint();
      }
      int? nextOpenTop;
      final lineNumber = prototype.lineForPc(frame.pc);
      if (lineNumber != null) {
        runtime.callStack.top?.currentLine = lineNumber;
      }

      final word = prototype.code[frame.pc++];
      final opcode = LuaBytecodeOpcodes.byCode(word.opcodeValue);
      switch (opcode.name) {
        case 'MOVE':
          {
            frame.setRegister(word.a, frame.register(word.b));
            break;
          }
        case 'LOADI':
          {
            frame.setRegister(word.a, _runtimeValue(runtime, word.sBx));
            break;
          }
        case 'LOADF':
          {
            frame.setRegister(
              word.a,
              _runtimeValue(runtime, word.sBx.toDouble()),
            );
            break;
          }
        case 'LOADK':
          {
            frame.setRegister(
              word.a,
              _constantValue(runtime, prototype, word.bx),
            );
            break;
          }
        case 'LOADKX':
          {
            frame.setRegister(
              word.a,
              _constantValue(runtime, prototype, _consumeExtraArg(frame).ax),
            );
            break;
          }
        case 'LOADFALSE':
          {
            frame.setRegister(word.a, _runtimeValue(runtime, false));
            break;
          }
        case 'LFALSESKIP':
          {
            frame.setRegister(word.a, _runtimeValue(runtime, false));
            frame.pc += 1;
            break;
          }
        case 'LOADTRUE':
          {
            frame.setRegister(word.a, _runtimeValue(runtime, true));
            break;
          }
        case 'LOADNIL':
          {
            for (var index = 0; index <= word.b; index++) {
              frame.setRegister(word.a + index, _runtimeValue(runtime, null));
            }
            break;
          }
        case 'GETUPVAL':
          {
            frame.setRegister(word.a, frame.closure._upvalues[word.b].read());
            break;
          }
        case 'SETUPVAL':
          {
            frame.closure._upvalues[word.b].write(frame.register(word.a));
            break;
          }
        case 'GETTABUP':
          {
            frame.setRegister(
              word.a,
              await _tableGet(
                frame.closure._upvalues[word.b].read(),
                _stringConstant(runtime, prototype, word.c),
              ),
            );
            break;
          }
        case 'GETTABLE':
          {
            frame.setRegister(
              word.a,
              await _tableGet(frame.register(word.b), frame.register(word.c)),
            );
            break;
          }
        case 'GETI':
          {
            frame.setRegister(
              word.a,
              await _tableGet(
                frame.register(word.b),
                _runtimeValue(runtime, word.c),
              ),
            );
            break;
          }
        case 'GETFIELD':
          {
            frame.setRegister(
              word.a,
              await _tableGet(
                frame.register(word.b),
                _stringConstant(runtime, prototype, word.c),
              ),
            );
            break;
          }
        case 'SETTABUP':
          {
            await _tableSet(
              frame.closure._upvalues[word.a].read(),
              _stringConstant(runtime, prototype, word.b),
              _rkValue(frame, word.c, word.kFlag),
            );
            break;
          }
        case 'CHECKGLOBAL':
          {
            final name = _constantValue(
              runtime,
              prototype,
              word.bx,
            ).raw.toString();
            if (await _explicitGlobalIsAlreadyDefined(
              frame.register(word.a),
              frame.closure.environment,
              name,
            )) {
              throw LuaError("global '$name' already defined");
            }
            break;
          }
        case 'SETTABLE':
          {
            await _tableSet(
              frame.register(word.a),
              frame.register(word.b),
              _rkValue(frame, word.c, word.kFlag),
            );
            break;
          }
        case 'SETI':
          {
            await _tableSet(
              frame.register(word.a),
              _runtimeValue(runtime, word.b),
              _rkValue(frame, word.c, word.kFlag),
            );
            break;
          }
        case 'SETFIELD':
          {
            await _tableSet(
              frame.register(word.a),
              _stringConstant(runtime, prototype, word.b),
              _rkValue(frame, word.c, word.kFlag),
            );
            break;
          }
        case 'NEWTABLE':
          {
            final extra = _consumeExtraArg(frame);
            final tableStorage = TableStorage();
            final arraySize =
                word.vc +
                (word.kFlag
                    ? extra.ax * (LuaBytecodeInstructionLayout.maxArgVC + 1)
                    : 0);
            if (arraySize > 0) {
              tableStorage.ensureArrayCapacity(arraySize);
            }
            frame.setRegister(word.a, _runtimeValue(runtime, tableStorage));
            break;
          }
        case 'SELF':
          {
            final receiver = frame.register(word.b);
            frame.setRegister(word.a + 1, receiver);
            frame.setRegister(
              word.a,
              await _tableGet(
                receiver,
                _stringConstant(runtime, prototype, word.c),
              ),
            );
            break;
          }
        case 'ADDI':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: _runtimeValue(runtime, _signedC(word)),
              operation: _LuaBinaryOperation.add,
            );
            break;
          }
        case 'ADDK':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: _constantValue(runtime, prototype, word.c),
              operation: _LuaBinaryOperation.add,
            );
            break;
          }
        case 'SUBK':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: _constantValue(runtime, prototype, word.c),
              operation: _LuaBinaryOperation.sub,
            );
            break;
          }
        case 'MULK':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: _constantValue(runtime, prototype, word.c),
              operation: _LuaBinaryOperation.mul,
            );
            break;
          }
        case 'MODK':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: _constantValue(runtime, prototype, word.c),
              operation: _LuaBinaryOperation.mod,
            );
            break;
          }
        case 'POWK':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: _constantValue(runtime, prototype, word.c),
              operation: _LuaBinaryOperation.pow,
            );
            break;
          }
        case 'DIVK':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: _constantValue(runtime, prototype, word.c),
              operation: _LuaBinaryOperation.div,
            );
            break;
          }
        case 'IDIVK':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: _constantValue(runtime, prototype, word.c),
              operation: _LuaBinaryOperation.idiv,
            );
            break;
          }
        case 'BANDK':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: _constantValue(runtime, prototype, word.c),
              operation: _LuaBinaryOperation.band,
            );
            break;
          }
        case 'BORK':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: _constantValue(runtime, prototype, word.c),
              operation: _LuaBinaryOperation.bor,
            );
            break;
          }
        case 'BXORK':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: _constantValue(runtime, prototype, word.c),
              operation: _LuaBinaryOperation.bxor,
            );
            break;
          }
        case 'SHLI':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: _runtimeValue(runtime, _signedC(word)),
              right: frame.register(word.b),
              operation: _LuaBinaryOperation.shl,
            );
            break;
          }
        case 'SHRI':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: _runtimeValue(runtime, _signedC(word)),
              operation: _LuaBinaryOperation.shr,
            );
            break;
          }
        case 'ADD':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: frame.register(word.c),
              operation: _LuaBinaryOperation.add,
            );
            break;
          }
        case 'SUB':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: frame.register(word.c),
              operation: _LuaBinaryOperation.sub,
            );
            break;
          }
        case 'MUL':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: frame.register(word.c),
              operation: _LuaBinaryOperation.mul,
            );
            break;
          }
        case 'MOD':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: frame.register(word.c),
              operation: _LuaBinaryOperation.mod,
            );
            break;
          }
        case 'POW':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: frame.register(word.c),
              operation: _LuaBinaryOperation.pow,
            );
            break;
          }
        case 'DIV':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: frame.register(word.c),
              operation: _LuaBinaryOperation.div,
            );
            break;
          }
        case 'IDIV':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: frame.register(word.c),
              operation: _LuaBinaryOperation.idiv,
            );
            break;
          }
        case 'BAND':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: frame.register(word.c),
              operation: _LuaBinaryOperation.band,
            );
            break;
          }
        case 'BOR':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: frame.register(word.c),
              operation: _LuaBinaryOperation.bor,
            );
            break;
          }
        case 'BXOR':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: frame.register(word.c),
              operation: _LuaBinaryOperation.bxor,
            );
            break;
          }
        case 'SHL':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: frame.register(word.c),
              operation: _LuaBinaryOperation.shl,
            );
            break;
          }
        case 'SHR':
          {
            _executeBinaryInstruction(
              frame,
              targetRegister: word.a,
              left: frame.register(word.b),
              right: frame.register(word.c),
              operation: _LuaBinaryOperation.shr,
            );
            break;
          }
        case 'UNM':
          {
            frame.setRegister(
              word.a,
              await _executeUnaryInstruction(
                frame.register(word.b),
                metamethod: '__unm',
                fastPath: (value) => _canFastPathNumeric(value)
                    ? _runtimeValue(runtime, NumberUtils.negate(value.raw))
                    : null,
              ),
            );
            break;
          }
        case 'BNOT':
          {
            frame.setRegister(
              word.a,
              await _executeUnaryInstruction(
                frame.register(word.b),
                metamethod: '__bnot',
                fastPath: (value) => _canFastPathInteger(value)
                    ? _runtimeValue(runtime, NumberUtils.bitwiseNot(value.raw))
                    : null,
              ),
            );
            break;
          }
        case 'NOT':
          {
            frame.setRegister(
              word.a,
              _runtimeValue(runtime, !_isTruthy(frame.register(word.b))),
            );
            break;
          }
        case 'LEN':
          {
            frame.setRegister(
              word.a,
              await _executeUnaryInstruction(
                frame.register(word.b),
                metamethod: '__len',
                fastPath: (value) => _canFastPathLength(value)
                    ? _runtimeValue(runtime, _lengthOf(value))
                    : null,
              ),
            );
            break;
          }
        case 'CONCAT':
          {
            frame.setRegister(
              word.a,
              await _executeConcatInstruction(frame, word.a, word.b),
            );
            break;
          }
        case 'MMBIN':
          {
            frame.setRegister(
              _previousInstruction(frame).a,
              await _executeMetamethodBinaryInstruction(
                frame,
                metamethod: _metamethodName(word.c),
                left: frame.register(word.a),
                right: frame.register(word.b),
              ),
            );
            break;
          }
        case 'MMBINI':
          {
            final immediate = _runtimeValue(runtime, _signedB(word));
            final (left, right) = word.kFlag
                ? (immediate, frame.register(word.a))
                : (frame.register(word.a), immediate);
            frame.setRegister(
              _previousInstruction(frame).a,
              await _executeMetamethodBinaryInstruction(
                frame,
                metamethod: _metamethodName(word.c),
                left: left,
                right: right,
              ),
            );
            break;
          }
        case 'MMBINK':
          {
            final constant = _constantValue(runtime, prototype, word.b);
            final (left, right) = word.kFlag
                ? (constant, frame.register(word.a))
                : (frame.register(word.a), constant);
            frame.setRegister(
              _previousInstruction(frame).a,
              await _executeMetamethodBinaryInstruction(
                frame,
                metamethod: _metamethodName(word.c),
                left: left,
                right: right,
              ),
            );
            break;
          }
        case 'TBC':
          {
            try {
              frame.markToBeClosed(word.a);
            } on LuaError catch (error) {
              final localName = frame.activeLocalName(word.a);
              if (localName != null &&
                  error.message ==
                      'to-be-closed variable value must have a __close metamethod') {
                throw LuaError(
                  "variable '$localName' got a non-closable value",
                );
              }
              rethrow;
            }
            break;
          }
        case 'VARARGPREP':
          {
            break;
          }
        case 'JMP':
          {
            frame.pc += word.sJ;
            if (word.sJ < 0) {
              await _runGcLoopSafePoint(runtime, frame);
            }
            break;
          }
        case 'EQ':
          {
            _docondjump(
              frame,
              word,
              await _compareEquals(
                frame.register(word.a),
                frame.register(word.b),
              ),
            );
            break;
          }
        case 'LT':
          {
            _docondjump(
              frame,
              word,
              await _compareOrdering(
                frame.register(word.a),
                frame.register(word.b),
                metamethod: '__lt',
                primitiveCompare: _PrimitiveCompare.lessThan,
              ),
            );
            break;
          }
        case 'LE':
          {
            _docondjump(
              frame,
              word,
              await _compareOrdering(
                frame.register(word.a),
                frame.register(word.b),
                metamethod: '__le',
                primitiveCompare: _PrimitiveCompare.lessThanOrEqual,
              ),
            );
            break;
          }
        case 'EQK':
          {
            _docondjump(
              frame,
              word,
              _rawEquals(
                frame.register(word.a),
                _constantValue(runtime, prototype, word.b),
              ),
            );
            break;
          }
        case 'EQI':
          {
            _docondjump(
              frame,
              word,
              _compareImmediateEquals(frame.register(word.a), _signedB(word)),
            );
            break;
          }
        case 'LTI':
          {
            _docondjump(
              frame,
              word,
              await _compareImmediateOrdering(
                frame.register(word.a),
                _signedB(word),
                metamethod: '__lt',
                primitiveCompare: _PrimitiveCompare.lessThan,
              ),
            );
            break;
          }
        case 'LEI':
          {
            _docondjump(
              frame,
              word,
              await _compareImmediateOrdering(
                frame.register(word.a),
                _signedB(word),
                metamethod: '__le',
                primitiveCompare: _PrimitiveCompare.lessThanOrEqual,
              ),
            );
            break;
          }
        case 'GTI':
          {
            _docondjump(
              frame,
              word,
              await _compareImmediateOrdering(
                frame.register(word.a),
                _signedB(word),
                metamethod: '__lt',
                primitiveCompare: _PrimitiveCompare.greaterThan,
                flipOperands: true,
              ),
            );
            break;
          }
        case 'GEI':
          {
            _docondjump(
              frame,
              word,
              await _compareImmediateOrdering(
                frame.register(word.a),
                _signedB(word),
                metamethod: '__le',
                primitiveCompare: _PrimitiveCompare.greaterThanOrEqual,
                flipOperands: true,
              ),
            );
            break;
          }
        case 'TEST':
          {
            _docondjump(frame, word, _isTruthy(frame.register(word.a)));
            break;
          }
        case 'TESTSET':
          {
            final value = frame.register(word.b);
            final shouldSkipJump = !_isTruthy(value) == word.kFlag;
            if (shouldSkipJump) {
              frame.pc += 1;
            } else {
              frame.setRegister(word.a, value);
            }
            break;
          }
        case 'CALL':
          {
            try {
              if (_debugFileOps) {
                final callee = frame.register(word.a);
                _debugFileLog(
                  'CALL pc=${frame.pc - 1} a=${word.a} b=${word.b} c=${word.c} '
                  'callee=${callee.raw.runtimeType} name=${_callSiteName(frame, word.a, callee)}',
                );
              }
              final results = await _callAt(frame, word);
              if (word.c == 1) {
                await _closeDiscardedCallResults(results);
              }
              nextOpenTop = _storeCallResults(frame, word.a, word.c, results);
            } on YieldException catch (error) {
              _suspendCall(frame, word.a, word.c, error);
            }
            break;
          }
        case 'TAILCALL':
          {
            try {
              final call = _resolveCall(frame, word);
              await frame.closeResources(fromRegister: 0);
              throw TailCallException(
                call.callee,
                call.args,
                callName: _callSiteName(frame, word.a, call.callee),
              );
            } on YieldException catch (error) {
              _suspendTailCall(frame, word, error);
            }
          }
        case 'RETURN':
          {
            try {
              await frame.closeResources(fromRegister: 0);
              final resultCount = word.b == 0
                  ? frame.effectiveTop - word.a
                  : word.b - 1;
              return frame.resultsFrom(word.a, resultCount);
            } on YieldException catch (error) {
              _suspendReturn(frame, word.a, word.b, error);
            }
          }
        case 'RETURN0':
          {
            try {
              await frame.closeResources(fromRegister: 0);
              return const <Value>[];
            } on YieldException catch (error) {
              _suspendReturn(frame, 0, 1, error);
            }
          }
        case 'RETURN1':
          {
            try {
              await frame.closeResources(fromRegister: 0);
              return <Value>[frame.register(word.a)];
            } on YieldException catch (error) {
              _suspendReturn(frame, word.a, 2, error);
            }
          }
        case 'FORPREP':
          {
            if (_forPrep(frame, word.a)) {
              frame.pc += word.bx + 1;
            }
            break;
          }
        case 'FORLOOP':
          {
            if (_forLoop(frame, word.a)) {
              frame.pc -= word.bx;
              await _runGcLoopSafePoint(runtime, frame);
            }
            break;
          }
        case 'TFORPREP':
          {
            final closingValue = frame.register(word.a + 3);
            final controlValue = frame.register(word.a + 2);
            frame.setRegister(word.a + 2, closingValue);
            frame.setRegister(word.a + 3, controlValue);
            frame.markToBeClosed(word.a + 2);
            frame.pc += word.bx;
            break;
          }
        case 'TFORCALL':
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
        case 'TFORLOOP':
          {
            if (!_isNil(frame.register(word.a + 3))) {
              frame.pc -= word.bx;
              await _runGcLoopSafePoint(runtime, frame);
            }
            break;
          }
        case 'SETLIST':
          {
            await _setList(frame, word);
            break;
          }
        case 'CLOSURE':
          {
            final child = prototype.prototypes[word.bx];
            frame.setRegister(
              word.a,
              _wrapClosure(_createClosure(frame, child)),
            );
            break;
          }
        case 'VARARG':
          {
            final varargResults = frame.expandedVarargs;
            nextOpenTop = _storeVarargResults(frame, word, varargResults);
            break;
          }
        case 'GETVARG':
          {
            final indexValue = frame.register(word.c);
            final index = _integerValue(indexValue);
            final expandedVarargs = frame.expandedVarargs;
            if (index < 1 || index > expandedVarargs.length) {
              frame.setRegister(word.a, _runtimeValue(runtime, null));
            } else {
              frame.setRegister(word.a, expandedVarargs[index - 1]);
            }
            break;
          }
        case 'CLOSE':
          {
            if (_debugFileOps) {
              _debugFileLog(
                'CLOSE pc=${frame.pc - 1} fromRegister=${word.a} '
                'toBeClosed=${frame._toBeClosedRegisters.toList()..sort()}',
              );
            }
            try {
              await frame.closeResources(fromRegister: word.a);
            } on YieldException catch (error) {
              _suspendClose(frame, word.a, error);
            }
            break;
          }
        case 'EXTRAARG':
          {
            throw LuaError(
              _opcodeDiagnostic(
                frame,
                opcode.name,
                detail: 'unexpected EXTRAARG without a consuming opcode',
              ),
            );
          }
        case 'ERRNNIL':
          {
            if (!_isNil(frame.register(word.a))) {
              throw LuaError('attempt to use a nil value');
            }
            break;
          }
        default:
          _throwUnsupportedOpcode(frame, opcode.name);
      }

      frame.openTop = nextOpenTop;
    }

    await frame.closeResources(fromRegister: 0);
    return const <Value>[];
  }

  void _syncDebugLocals(_LuaBytecodeFrame frame) {
    final callFrame = runtime.callStack.top;
    if (callFrame == null) {
      return;
    }

    final currentPc = frame.pc + 1;
    callFrame.debugLocals
      ..clear()
      ..addAll([
        for (final local in frame.closure.prototype.localVariables)
          if (local.register case final register?
              when local.startPc <= currentPc && currentPc < local.endPc)
            MapEntry(local.name ?? '(local)', frame.register(register)),
      ]);
  }

  void _syncCurrentCoroutine() {
    if (Coroutine.active case final active?) {
      if (active.status == CoroutineStatus.normal) {
        active.status = CoroutineStatus.running;
      }
      runtime.setCurrentCoroutine(active);
      return;
    }

    final current = runtime.getCurrentCoroutine();
    if (current != null && !identical(current, runtime.getMainThread())) {
      return;
    }

    runtime.setCurrentCoroutine(runtime.getMainThread());
  }

  LuaBytecodeClosure _createClosure(
    _LuaBytecodeFrame frame,
    LuaBytecodePrototype prototype,
  ) {
    final upvalues = <_LuaBytecodeUpvalue>[
      for (final descriptor in prototype.upvalues)
        descriptor.inStack
            ? frame.captureUpvalue(descriptor.index)
            : frame.closure._upvalues[descriptor.index],
    ];
    return LuaBytecodeClosure._(
      runtime: runtime,
      prototype: prototype,
      chunkName: frame.closure.chunkName,
      environment: frame.closure.environment,
      upvalues: upvalues,
    );
  }

  void _executeBinaryInstruction(
    _LuaBytecodeFrame frame, {
    required int targetRegister,
    required Value left,
    required Value right,
    required _LuaBinaryOperation operation,
  }) {
    final fastPath = _tryBinaryFastPath(operation, left, right);
    if (fastPath != null) {
      frame.setRegister(targetRegister, fastPath);
      _skipBinaryMetamethodFollowup(frame);
      return;
    }

    if (_hasBinaryMetamethodFollowup(frame)) {
      return;
    }

    frame.setRegister(
      targetRegister,
      _forceBinaryOperation(operation, left, right),
    );
  }

  Future<Value> _executeUnaryInstruction(
    Value operand, {
    required String metamethod,
    required Value? Function(Value operand) fastPath,
  }) async {
    final direct = fastPath(operand);
    if (direct != null) {
      return direct;
    }

    final metamethodResult = await _invokeBinaryMetamethod(
      metamethod,
      operand,
      operand,
    );
    if (metamethodResult != null) {
      return metamethodResult;
    }

    return switch (metamethod) {
      '__unm' => _runtimeValue(runtime, NumberUtils.negate(operand.raw)),
      '__bnot' => _runtimeValue(runtime, NumberUtils.bitwiseNot(operand.raw)),
      '__len' => _runtimeValue(runtime, _lengthOf(operand)),
      _ => throw LuaError('unsupported unary metamethod $metamethod'),
    };
  }

  Future<Value> _executeConcatInstruction(
    _LuaBytecodeFrame frame,
    int startRegister,
    int operandCount,
  ) async {
    var current = frame.register(startRegister + operandCount - 1);
    for (var offset = operandCount - 2; offset >= 0; offset--) {
      final next = frame.register(startRegister + offset);
      final fastPath = _tryBinaryFastPath(
        _LuaBinaryOperation.concat,
        next,
        current,
      );
      if (fastPath != null) {
        current = fastPath;
        continue;
      }

      final metamethodResult = await _invokeBinaryMetamethod(
        '__concat',
        next,
        current,
      );
      if (metamethodResult != null) {
        current = metamethodResult;
        continue;
      }

      current = _forceBinaryOperation(
        _LuaBinaryOperation.concat,
        next,
        current,
      );
    }
    return current;
  }

  Future<Value> _executeMetamethodBinaryInstruction(
    _LuaBytecodeFrame frame, {
    required String metamethod,
    required Value left,
    required Value right,
  }) async {
    final metamethodResult = await _invokeBinaryMetamethod(
      metamethod,
      left,
      right,
    );
    if (metamethodResult != null) {
      return metamethodResult;
    }

    return _forceBinaryOperation(
      _binaryOperationForMetamethod(metamethod),
      left,
      right,
    );
  }

  Value? _tryBinaryFastPath(
    _LuaBinaryOperation operation,
    Value left,
    Value right,
  ) {
    if (!_canFastPathBinaryOperation(operation, left, right)) {
      return null;
    }
    return _forceBinaryOperation(operation, left, right);
  }

  Value _forceBinaryOperation(
    _LuaBinaryOperation operation,
    Value left,
    Value right,
  ) {
    if (operation.isConcat) {
      return _runtimeValue(runtime, left.concat(right));
    }
    return _runtimeValue(
      runtime,
      NumberUtils.performArithmetic(
        operation.operatorSymbol,
        left.raw,
        right.raw,
      ),
    );
  }

  bool _canFastPathBinaryOperation(
    _LuaBinaryOperation operation,
    Value left,
    Value right,
  ) {
    if (operation.isConcat) {
      return _canFastPathConcat(left) && _canFastPathConcat(right);
    }
    if (operation.integerOnly) {
      return _canFastPathInteger(left) && _canFastPathInteger(right);
    }
    return _canFastPathNumeric(left) && _canFastPathNumeric(right);
  }

  bool _hasBinaryMetamethodFollowup(_LuaBytecodeFrame frame) {
    return switch (_nextOpcodeName(frame)) {
      'MMBIN' || 'MMBINI' || 'MMBINK' => true,
      _ => false,
    };
  }

  void _skipBinaryMetamethodFollowup(_LuaBytecodeFrame frame) {
    if (_hasBinaryMetamethodFollowup(frame)) {
      frame.pc += 1;
    }
  }

  String? _nextOpcodeName(_LuaBytecodeFrame frame) {
    if (frame.pc >= frame.closure.prototype.code.length) {
      return null;
    }
    return LuaBytecodeOpcodes.byCode(
      frame.closure.prototype.code[frame.pc].opcodeValue,
    ).name;
  }

  LuaBytecodeInstructionWord _previousInstruction(_LuaBytecodeFrame frame) {
    final index = frame.pc - 2;
    if (index < 0 || index >= frame.closure.prototype.code.length) {
      throw LuaError(
        _opcodeDiagnostic(
          frame,
          'MMBIN*',
          detail: 'missing arithmetic instruction before metamethod fallback',
        ),
      );
    }
    return frame.closure.prototype.code[index];
  }

  Future<Value?> _invokeBinaryMetamethod(
    String metamethod,
    Value left,
    Value right,
  ) async {
    return await _callBinaryMetamethodOn(metamethod, left, left, right) ??
        await _callBinaryMetamethodOn(metamethod, right, left, right);
  }

  Future<Value?> _callBinaryMetamethodOn(
    String metamethod,
    Value receiver,
    Value left,
    Value right,
  ) async {
    if (!receiver.hasMetamethod(metamethod)) {
      return null;
    }

    final result = await receiver.callMetamethodAsync(metamethod, <Value>[
      left,
      right,
    ]);
    final value = _firstResultValue(result);
    value.interpreter ??= runtime;
    return value;
  }

  void _throwUnsupportedOpcode(
    _LuaBytecodeFrame frame,
    String opcodeName, {
    String? detail,
  }) {
    throw LuaError(_opcodeDiagnostic(frame, opcodeName, detail: detail));
  }

  String _opcodeDiagnostic(
    _LuaBytecodeFrame frame,
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

  ({Value callee, List<Value> args}) _resolveCall(
    _LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word,
  ) {
    final callee = frame.register(word.a);
    final args = word.b == 0
        ? frame.resultsFrom(word.a + 1, frame.effectiveTop - (word.a + 1))
        : frame.resultsFrom(word.a + 1, word.b - 1);
    return (callee: callee, args: args);
  }

  Future<List<Value>> _callAt(
    _LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word,
  ) async {
    final call = _resolveCall(frame, word);
    return _invokePreparedCall(
      call,
      frame: frame,
      callName: _callSiteName(frame, word.a, call.callee),
    );
  }

  Future<List<Value>> _invokePreparedCall(
    ({Value callee, List<Value> args}) call, {
    _LuaBytecodeFrame? frame,
    String opcodeName = 'CALL',
    String? callName,
  }) async {
    try {
      return await _invokeValueWithName(
        call.callee,
        call.args,
        callName: callName,
      );
    } on LuaError catch (error) {
      if (frame != null && !runtime.isInProtectedCall) {
        throw LuaError(
          _opcodeDiagnostic(frame, opcodeName, detail: error.message),
        );
      }
      rethrow;
    } on Exception catch (error) {
      if (frame != null &&
          !runtime.isInProtectedCall &&
          error.toString().contains('attempt to call a non-function value')) {
        throw LuaError(
          _opcodeDiagnostic(
            frame,
            opcodeName,
            detail: 'attempt to call a non-function value',
          ),
        );
      }
      rethrow;
    }
  }

  Never _suspendCall(
    _LuaBytecodeFrame frame,
    int register,
    int resultSpec,
    YieldException error,
  ) {
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    coroutine.installContinuation(
      _LuaBytecodeCallSuspension(
        vm: this,
        frame: frame,
        register: register,
        resultSpec: resultSpec,
        child: child,
      ),
    );
    throw YieldException(error.values, error.resumeFuture, coroutine);
  }

  Never _suspendTailCall(
    _LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word,
    YieldException error,
  ) {
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    coroutine.installContinuation(
      _LuaBytecodeTailCallSuspension(
        vm: this,
        frame: frame,
        word: word,
        child: child,
      ),
    );
    throw YieldException(error.values, error.resumeFuture, coroutine);
  }

  Never _suspendTForCall(
    _LuaBytecodeFrame frame,
    int base,
    int resultCount,
    YieldException error,
  ) {
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    coroutine.installContinuation(
      _LuaBytecodeTForCallSuspension(
        vm: this,
        frame: frame,
        base: base,
        resultCount: resultCount,
        child: child,
      ),
    );
    throw YieldException(error.values, error.resumeFuture, coroutine);
  }

  Never _suspendClose(
    _LuaBytecodeFrame frame,
    int fromRegister,
    YieldException error,
  ) {
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    coroutine.installContinuation(
      _LuaBytecodeCloseSuspension(
        vm: this,
        frame: frame,
        fromRegister: fromRegister,
        savedTop: frame.top,
        savedOpenTop: frame.openTop,
        child: child,
      ),
    );
    throw YieldException(error.values, error.resumeFuture, coroutine);
  }

  Never _suspendReturn(
    _LuaBytecodeFrame frame,
    int register,
    int resultSpec,
    YieldException error,
  ) {
    final coroutine = _requireCoroutineForYield(frame, error);
    final child = coroutine.takeContinuation();
    coroutine.installContinuation(
      _LuaBytecodeReturnSuspension(
        vm: this,
        frame: frame,
        register: register,
        resultSpec: resultSpec,
        savedTop: frame.top,
        savedOpenTop: frame.openTop,
        child: child,
      ),
    );
    throw YieldException(error.values, error.resumeFuture, coroutine);
  }

  Coroutine _requireCoroutineForYield(
    _LuaBytecodeFrame frame,
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

  Future<List<Value>> _invokeValueWithName(
    Value callee,
    List<Value> args, {
    String? callName,
    int extraArgs = 0,
  }) async {
    final prepared = _flattenTailCallable(callee, args);
    callee = prepared.callee;
    args = prepared.args;
    extraArgs += prepared.extraArgs;
    callee.interpreter ??= runtime;
    if (callee.raw case final LuaBytecodeClosure closure) {
      return invoke(closure, args, callName: callName, extraArgs: extraArgs);
    }
    runtime.callStack.push(
      callName ?? _callableName(callee),
      env: runtime.getCurrentEnv(),
    );
    runtime.callStack.top?.extraArgs = extraArgs;
    final callDebugInterpreter = _debugInterpreter;
    if (callDebugInterpreter != null) {
      final interpreter = callDebugInterpreter;
      await interpreter.fireDebugHook('call');
    }
    Iterable<Value> tempRootProvider() sync* {
      yield callee;
      for (final arg in args) {
        yield arg;
      }
    }

    (runtime as dynamic).pushExternalGcRoots(tempRootProvider);
    try {
      final result = await runtime.callFunction(callee, args);
      return _normalizeResults(result);
    } finally {
      final returnDebugInterpreter = _debugInterpreter;
      if (returnDebugInterpreter != null) {
        final interpreter = returnDebugInterpreter;
        await interpreter.fireDebugHook('return');
      }
      (runtime as dynamic).popExternalGcRoots(tempRootProvider);
      runtime.callStack.pop();
    }
  }

  String _callableName(Value callee) {
    return switch (callee.functionName) {
      final String name when name.isNotEmpty => name,
      _ => switch (callee.raw) {
        final String name => name,
        _ => 'function',
      },
    };
  }

  String? _callSiteName(_LuaBytecodeFrame frame, int register, Value callee) {
    final currentPc = frame.pc;
    for (final local in frame.closure.prototype.localVariables) {
      if (!(local.startPc <= currentPc && currentPc < local.endPc)) {
        continue;
      }
      final name = local.name;
      if (name == null || name.isEmpty || name.startsWith('(')) {
        continue;
      }
      if (local.register == register) {
        return name;
      }
      if (local.register case final localRegister?) {
        final localValue = frame.register(localRegister);
        if (identical(localValue, callee) ||
            identical(localValue.raw, callee.raw)) {
          return name;
        }
      }
    }
    final inferred = _inferRegisterCallName(
      frame,
      register,
      beforePc: currentPc - 1,
      visitedRegisters: <int>{},
    );
    if (inferred != null) {
      return inferred;
    }
    return switch (callee.raw) {
      final String name => name,
      _ => null,
    };
  }

  String? _inferRegisterCallName(
    _LuaBytecodeFrame frame,
    int register, {
    required int beforePc,
    required Set<int> visitedRegisters,
  }) {
    if (!visitedRegisters.add(register)) {
      return null;
    }
    final prototype = frame.closure.prototype;
    for (var pc = beforePc; pc >= 0; pc--) {
      final word = prototype.code[pc];
      final opcode = LuaBytecodeOpcodes.byCode(word.opcodeValue).name;
      if (!_instructionWritesRegister(word, opcode, register)) {
        continue;
      }
      return switch (opcode) {
        'MOVE' => _inferRegisterCallName(
          frame,
          word.b,
          beforePc: pc - 1,
          visitedRegisters: visitedRegisters,
        ),
        'GETFIELD' ||
        'SELF' => _stringConstant(runtime, prototype, word.c).raw.toString(),
        'GETTABUP' => _stringConstant(
          runtime,
          prototype,
          word.c,
        ).raw.toString(),
        'GETUPVAL' => frame.closure.upvalueName(word.b),
        'LOADK' => switch (_constantValue(runtime, prototype, word.bx).raw) {
          final String name => name,
          final LuaString name => name.toString(),
          _ => null,
        },
        'LOADKX' => switch (_constantValue(
          runtime,
          prototype,
          prototype.code[pc + 1].ax,
        ).raw) {
          final String name => name,
          final LuaString name => name.toString(),
          _ => null,
        },
        _ => null,
      };
    }
    return null;
  }

  bool _instructionWritesRegister(
    LuaBytecodeInstructionWord word,
    String opcode,
    int register,
  ) {
    return switch (opcode) {
      'MOVE' ||
      'LOADI' ||
      'LOADF' ||
      'LOADK' ||
      'LOADKX' ||
      'LOADFALSE' ||
      'LFALSESKIP' ||
      'LOADTRUE' ||
      'GETUPVAL' ||
      'GETTABUP' ||
      'GETTABLE' ||
      'GETI' ||
      'GETFIELD' ||
      'NEWTABLE' ||
      'SELF' ||
      'CLOSURE' ||
      'VARARGPREP' ||
      'VARARG' => word.a == register,
      'LOADNIL' => register >= word.a && register <= word.a + word.b,
      'CALL' || 'TAILCALL' =>
        word.c == 0
            ? register >= word.a
            : register >= word.a && register < word.a + word.c - 1,
      _ => false,
    };
  }

  Future<void> _closeDiscardedCallResults(List<Value> results) async {
    Object? closeError;
    StackTrace? closeStackTrace;

    for (var index = results.length - 1; index >= 0; index--) {
      final value = results[index];
      if (!value.isToBeClose || value.raw == null || value.raw == false) {
        continue;
      }
      final closeValue = value.isToBeClose ? value : Value.toBeClose(value);
      closeValue.interpreter ??= runtime;
      try {
        await closeValue.close();
      } catch (error, stackTrace) {
        closeError ??= error;
        closeStackTrace ??= stackTrace;
      }
    }

    if (closeError != null && closeStackTrace != null) {
      Error.throwWithStackTrace(closeError, closeStackTrace);
    }
  }

  int? _storeCallResults(
    _LuaBytecodeFrame frame,
    int register,
    int resultSpec,
    List<Value> results,
  ) {
    if (resultSpec == 0) {
      for (var index = 0; index < results.length; index++) {
        frame.setRegister(register + index, results[index]);
      }
      frame.top = register + results.length;
      return frame.top;
    }

    final expectedCount = resultSpec - 1;
    for (var index = 0; index < expectedCount; index++) {
      final value = index < results.length
          ? results[index]
          : _runtimeValue(runtime, null);
      frame.setRegister(register + index, value);
    }
    frame.top = register + expectedCount;
    return null;
  }

  int? _storeVarargResults(
    _LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word,
    List<Value> varargs,
  ) {
    if (word.c == 0) {
      for (var index = 0; index < varargs.length; index++) {
        frame.setRegister(word.a + index, varargs[index]);
      }
      frame.top = word.a + varargs.length;
      return frame.top;
    }

    final expectedCount = word.c - 1;
    for (var index = 0; index < expectedCount; index++) {
      final value = index < varargs.length
          ? varargs[index]
          : _runtimeValue(runtime, null);
      frame.setRegister(word.a + index, value);
    }
    frame.top = word.a + expectedCount;
    return null;
  }

  bool _forPrep(_LuaBytecodeFrame frame, int base) {
    final initial = frame.register(base);
    final limit = frame.register(base + 1);
    final step = frame.register(base + 2);

    final coercedInitial = _forNumericOperand(initial, 'initial value');
    final coercedLimit = _forNumericOperand(limit, 'limit');
    final coercedStep = _forNumericOperand(step, 'step');

    final integerInitial = _exactForIntegerValue(coercedInitial);
    final integerStep = _exactForIntegerValue(coercedStep);
    if (integerInitial != null && integerStep != null) {
      final init = integerInitial;
      final stepValue = integerStep;
      if (stepValue == 0) {
        throw LuaError("'for' step is zero");
      }
      final limitInfo = _forIntegerLimit(init, coercedLimit, stepValue);
      if (limitInfo.skip) {
        return true;
      }
      final limitValue = limitInfo.limit;

      final count = stepValue > 0
          ? _unsignedDifference64(
                  _unsignedInt64(init: limitValue),
                  _unsignedInt64(init: init),
                ) ~/
                _unsignedInt64(init: stepValue)
          : _unsignedDifference64(
                  _unsignedInt64(init: init),
                  _unsignedInt64(init: limitValue),
                ) ~/
                _negativeStepDivisor(stepValue);
      frame.setRegister(
        base,
        _runtimeValue(runtime, _signedInt64FromUnsigned(count)),
      );
      frame.setRegister(base + 1, _runtimeValue(runtime, stepValue));
      frame.setRegister(base + 2, _runtimeValue(runtime, init));
      return false;
    }

    final init = _numericForOperand(coercedInitial).toDouble();
    final limitValue = _numericForOperand(coercedLimit).toDouble();
    final stepValue = _numericForOperand(coercedStep).toDouble();
    if (stepValue == 0) {
      throw LuaError("'for' step is zero");
    }
    final shouldSkip = stepValue > 0 ? limitValue < init : init < limitValue;
    if (shouldSkip) {
      return true;
    }

    frame.setRegister(base, _runtimeValue(runtime, limitValue));
    frame.setRegister(base + 1, _runtimeValue(runtime, stepValue));
    frame.setRegister(base + 2, _runtimeValue(runtime, init));
    return false;
  }

  bool _forLoop(_LuaBytecodeFrame frame, int base) {
    if (_isInteger(frame.register(base + 1))) {
      final count = _unsignedForLoopCounter(frame.register(base));
      if (count <= BigInt.zero) {
        return false;
      }
      final step = _integerValue(frame.register(base + 1));
      final nextIndex = NumberUtils.add(
        _integerValue(frame.register(base + 2)),
        step,
      );
      frame.setRegister(
        base,
        _runtimeValue(runtime, _signedInt64FromUnsigned(count - BigInt.one)),
      );
      frame.setRegister(base + 2, _runtimeValue(runtime, nextIndex));
      return true;
    }

    final step = _numericValue(frame.register(base + 1)).toDouble();
    final limit = _numericValue(frame.register(base)).toDouble();
    final nextIndex = _numericValue(frame.register(base + 2)).toDouble() + step;
    final shouldContinue = step > 0 ? nextIndex <= limit : nextIndex >= limit;
    if (!shouldContinue) {
      return false;
    }
    frame.setRegister(base + 2, _runtimeValue(runtime, nextIndex));
    return true;
  }

  Future<List<Value>> _genericForCall(
    _LuaBytecodeFrame frame,
    int base,
    int resultCount,
  ) async {
    if (io.Platform.environment['LUALIKE_DEBUG_TFOR'] == '1') {
      print(
        '[tfdebug] base=$base '
        'iterator=${frame.register(base)} '
        'state=${frame.register(base + 1)} '
        'control=${frame.register(base + 3)}',
      );
    }
    final iterator = frame.register(base);
    final state = frame.register(base + 1);
    final control = frame.register(base + 3);
    final results = await _invokePreparedCall(
      (callee: iterator, args: <Value>[state, control]),
      frame: frame,
      opcodeName: 'TFORCALL',
    );
    final expected = List<Value>.generate(
      resultCount,
      (index) => index < results.length
          ? results[index]
          : _runtimeValue(runtime, null),
      growable: false,
    );
    return expected;
  }

  Future<void> _setList(
    _LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word,
  ) async {
    final table = frame.register(word.a);
    final count = word.vb == 0 ? frame.effectiveTop - word.a - 1 : word.vb;
    var last = word.vc + count;
    if (word.kFlag) {
      last +=
          _consumeExtraArg(frame).ax *
          (LuaBytecodeInstructionLayout.maxArgVC + 1);
    }
    for (var remaining = count; remaining > 0; remaining--) {
      final value = frame.register(word.a + remaining);
      await _tableSet(table, _runtimeValue(frame.runtime, last), value);
      last--;
    }
  }

  void _docondjump(
    _LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word,
    bool condition,
  ) {
    if (condition != word.kFlag) {
      frame.pc += 1;
    }
  }

  Future<Value> _tableGet(Value table, Value key) async {
    table.interpreter ??= runtime;
    key.interpreter ??= runtime;
    final result = await table.getValueAsync(key);
    return _runtimeValue(runtime, result);
  }

  Future<void> _tableSet(Value table, Value key, Value value) async {
    table.interpreter ??= runtime;
    key.interpreter ??= runtime;
    value.interpreter ??= runtime;
    await table.setValueAsync(key, value);
  }

  LuaBytecodeInstructionWord _consumeExtraArg(_LuaBytecodeFrame frame) {
    if (frame.pc >= frame.closure.prototype.code.length) {
      throw LuaError('missing EXTRAARG operand');
    }
    final extra = frame.closure.prototype.code[frame.pc++];
    if (LuaBytecodeOpcodes.byCode(extra.opcodeValue).name != 'EXTRAARG') {
      throw LuaError('expected EXTRAARG after extending opcode');
    }
    return extra;
  }

  Future<List<Value>> _normalizeResults(Object? result) async {
    if (result == null) {
      return const <Value>[];
    }
    return switch (result) {
      final Value value when value.isMulti =>
        (value.raw as List<Object?>)
            .map((item) => _runtimeValue(runtime, item))
            .toList(growable: false),
      final Value value => <Value>[_runtimeValue(runtime, value)],
      final List<Object?> values =>
        values
            .map((item) => _runtimeValue(runtime, item))
            .toList(growable: false),
      _ => <Value>[_runtimeValue(runtime, result)],
    };
  }
}

final class _LuaBytecodeFrame implements LuaBytecodeGCRootProvider {
  _LuaBytecodeFrame({
    required this.runtime,
    required this.closure,
    required List<Object?> arguments,
    this.callName,
    required this.isEntryFrame,
    this.extraArgs = 0,
  }) : registers = List<Value>.generate(
         closure.prototype.maxStackSize,
         (_) => _runtimeValue(runtime, null),
         growable: true,
       ),
       varargs = <Value>[] {
    top = closure.prototype.parameterCount;
    final normalizedArgs = arguments
        .map((argument) => _runtimeValue(runtime, argument))
        .toList(growable: false);
    final parameterCount = closure.prototype.parameterCount;
    for (var index = 0; index < parameterCount; index++) {
      final value = index < normalizedArgs.length
          ? normalizedArgs[index]
          : _runtimeValue(runtime, null);
      setRegister(index, value);
    }
    if (closure.prototype.isVararg && normalizedArgs.length > parameterCount) {
      varargs.addAll(normalizedArgs.skip(parameterCount));
    }
    if (closure.prototype.needsVarargTable) {
      final packed = packVarargsTable(varargs);
      setRegister(parameterCount, packed);
      if (packed.raw case final PackedVarargTable table) {
        namedVarargTable = table;
      }
    }
  }

  final LuaRuntime runtime;
  final LuaBytecodeClosure closure;
  final String? callName;
  final bool isEntryFrame;
  final int extraArgs;
  final List<Value> registers;
  final List<Value> varargs;
  PackedVarargTable? namedVarargTable;
  final List<_LuaBytecodeUpvalue> _openUpvalues = <_LuaBytecodeUpvalue>[];
  final Set<int> _toBeClosedRegisters = <int>{};

  var pc = 0;
  var top = 0;
  int? openTop;
  var safePointCounter = 0;
  var loopGcCounter = 0;
  var closed = false;

  int get effectiveTop => openTop ?? top;

  Value register(int index) => slotValue(index);

  Value slotValue(int index) => index < registers.length
      ? registers[index]
      : _runtimeValue(runtime, null);

  void setRegister(int index, Value value) {
    if (index >= registers.length) {
      registers.addAll(
        List<Value>.generate(
          index - registers.length + 1,
          (_) => _runtimeValue(runtime, null),
          growable: false,
        ),
      );
    }
    value.interpreter ??= runtime;
    registers[index] = value;
    if (index + 1 > top) {
      top = index + 1;
    }
  }

  List<Value> resultsFrom(int start, int count) {
    if (count <= 0) {
      return const <Value>[];
    }
    return List<Value>.generate(
      count,
      (index) => start + index < registers.length
          ? register(start + index)
          : _runtimeValue(runtime, null),
      growable: false,
    );
  }

  List<Value> get expandedVarargs {
    if (namedVarargTable case final PackedVarargTable table) {
      final count = table.expandedCount();
      if (count == varargs.length) {
        return varargs;
      }
      return table
          .expandedValues()
          .map(
            (value) => value is Value ? value : _runtimeValue(runtime, value),
          )
          .toList(growable: false);
    }
    return varargs;
  }

  String? activeLocalName(int registerIndex) {
    final currentPc = pc;
    for (final local in closure.prototype.localVariables.reversed) {
      final name = local.name;
      if (name == null || name.isEmpty || name.startsWith('(')) {
        continue;
      }
      if (local.register != registerIndex) {
        continue;
      }
      if (local.startPc <= currentPc && currentPc < local.endPc) {
        return name;
      }
    }
    return null;
  }

  void expireDeadLocals() {
    final currentPc = pc;
    final registersToClear = <int>{};

    for (final local in closure.prototype.localVariables) {
      final registerIndex = local.register;
      if (registerIndex == null) {
        continue;
      }
      if (local.endPc > currentPc) {
        continue;
      }
      if (_toBeClosedRegisters.contains(registerIndex)) {
        continue;
      }
      if (_openUpvalues.any(
        (upvalue) => upvalue.isOpen && upvalue.registerIndex == registerIndex,
      )) {
        continue;
      }
      final stillActive = closure.prototype.localVariables.any(
        (candidate) =>
            candidate.register == registerIndex &&
            candidate.startPc <= currentPc &&
            currentPc < candidate.endPc,
      );
      if (!stillActive) {
        registersToClear.add(registerIndex);
      }
    }

    for (final registerIndex in registersToClear) {
      if (registerIndex >= registers.length) {
        continue;
      }
      final value = registers[registerIndex];
      if (value.raw == null && !value.isToBeClose) {
        continue;
      }
      registers[registerIndex] = _runtimeValue(runtime, null);
    }
  }

  _LuaBytecodeUpvalue captureUpvalue(int registerIndex) {
    for (final upvalue in _openUpvalues) {
      if (upvalue.registerIndex == registerIndex && upvalue.isOpen) {
        return upvalue;
      }
    }
    final upvalue = _LuaBytecodeUpvalue.open(this, registerIndex);
    _openUpvalues.add(upvalue);
    return upvalue;
  }

  void markToBeClosed(int registerIndex) {
    final rawValue = slotValue(registerIndex);
    if (rawValue.raw == null || rawValue.raw == false) {
      _toBeClosedRegisters.add(registerIndex);
      return;
    }
    try {
      final closable = rawValue.isToBeClose
          ? rawValue
          : Value.toBeClose(rawValue);
      setRegister(registerIndex, closable);
      _toBeClosedRegisters.add(registerIndex);
    } on UnsupportedError catch (error, stackTrace) {
      final message = error.message ?? error.toString();
      throw LuaError(message, cause: error, stackTrace: stackTrace);
    }
  }

  Future<void> closeResources({
    required int fromRegister,
    Object? error,
  }) async {
    final registersToClose =
        _toBeClosedRegisters
            .where((registerIndex) => registerIndex >= fromRegister)
            .toList(growable: false)
          ..sort((left, right) => right.compareTo(left));
    _toBeClosedRegisters.removeWhere(
      (registerIndex) => registerIndex >= fromRegister,
    );

    var currentError = error;
    Object? closeError;
    StackTrace? closeStackTrace;
    for (final registerIndex in registersToClose) {
      final slotValue = this.slotValue(registerIndex);
      if (slotValue.raw == null || slotValue.raw == false) {
        continue;
      }
      final Value closeValue;
      try {
        closeValue = slotValue.isToBeClose
            ? slotValue
            : Value.toBeClose(slotValue);
      } on UnsupportedError catch (error, stackTrace) {
        final localName = activeLocalName(registerIndex);
        final message = localName != null
            ? "variable '$localName' got a non-closable value"
            : (error.message ?? error.toString());
        Error.throwWithStackTrace(
          LuaError(message, cause: error, stackTrace: stackTrace),
          stackTrace,
        );
      }
      closeValue.interpreter ??= runtime;
      try {
        await closeValue.close(currentError);
      } catch (caughtError, caughtStackTrace) {
        currentError = caughtError;
        closeError = caughtError;
        closeStackTrace = caughtStackTrace;
      }
    }
    closeUpvalues(fromRegister: fromRegister);
    if (closeError != null && closeStackTrace != null) {
      Error.throwWithStackTrace(closeError, closeStackTrace);
    }
  }

  void closeUpvalues({required int fromRegister}) {
    final toClose = <_LuaBytecodeUpvalue>[
      for (final upvalue in _openUpvalues)
        if (upvalue.isOpen && upvalue.registerIndex >= fromRegister) upvalue,
    ];
    for (final upvalue in toClose) {
      upvalue.close();
    }
    _openUpvalues.removeWhere((upvalue) => !upvalue.isOpen);
    if (fromRegister == 0) {
      closed = true;
    }
  }

  @override
  Iterable<GCObject> gcReferences() sync* {
    yield closure.environment;
    // Keep named local slots alive even when debug-scope metadata is at a
    // boundary the runtime cannot represent precisely during async GC safe
    // points. This is especially important for top-level chunks, where a live
    // local can otherwise be collected between bytecode instructions.
    final reservedLocalLimit = closure.prototype.localVariables
        .map((local) => local.register)
        .whereType<int>()
        .fold<int>(
          -1,
          (limit, register) => register > limit ? register : limit,
        );
    final liveRegisters = <int>{
      for (var index = 0; index < top; index++) index,
      for (var index = 0; index < registers.length; index++)
        if (registers[index].raw != null || registers[index].isToBeClose) index,
      for (var index = 0; index <= reservedLocalLimit; index++) index,
      if (openTop case final openTop?)
        for (var index = 0; index < openTop; index++) index,
      for (final upvalue in _openUpvalues)
        if (upvalue.isOpen) upvalue.registerIndex,
      ..._toBeClosedRegisters,
      for (final local in closure.prototype.localVariables)
        if (local.register case final register?
            when local.startPc <= pc + 1 && pc + 1 < local.endPc)
          register,
    };
    for (final registerIndex in liveRegisters.toList()..sort()) {
      if (registerIndex < registers.length) {
        yield slotValue(registerIndex);
      }
    }
    for (final value in varargs) {
      yield value;
    }
    if (namedVarargTable case final PackedVarargTable table) {
      yield Value(table);
    }
  }
}

final class _LuaBytecodeCallSuspension implements CoroutineContinuation {
  const _LuaBytecodeCallSuspension({
    required this.vm,
    required this.frame,
    required this.register,
    required this.resultSpec,
    this.child,
  });

  final LuaBytecodeVm vm;
  final _LuaBytecodeFrame frame;
  final int register;
  final int resultSpec;
  final CoroutineContinuation? child;

  @override
  Future<Object?> resume(List<Object?> args) async {
    late final List<Value> results;
    try {
      results = await _resumeResults(args);
    } on YieldException catch (error) {
      final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
      if (coroutine != null) {
        final nextChild = coroutine.takeContinuation();
        coroutine.installContinuation(
          _LuaBytecodeCallSuspension(
            vm: vm,
            frame: frame,
            register: register,
            resultSpec: resultSpec,
            child: nextChild,
          ),
        );
      }
      rethrow;
    }
    if (resultSpec == 1) {
      await vm._closeDiscardedCallResults(results);
    }
    frame.openTop = vm._storeCallResults(frame, register, resultSpec, results);
    final resumedResults = await vm._runFrameWithTailCalls(frame);
    return _packCallResults(vm.runtime, resumedResults);
  }

  Future<List<Value>> _resumeResults(List<Object?> args) async {
    if (child case final nested?) {
      final result = await nested.resume(args);
      return vm._normalizeResults(result);
    }
    return args
        .map((arg) => _runtimeValue(vm.runtime, arg))
        .toList(growable: false);
  }

  @override
  Future<void> close([Object? error]) async {
    if (child case final nested?) {
      await nested.close(error);
    }
    if (!frame.closed) {
      await frame.closeResources(fromRegister: 0, error: error);
    }
  }

  @override
  Iterable<GCObject> getReferences() sync* {
    yield* frame.gcReferences();
    if (child case final nested?) {
      yield* nested.getReferences();
    }
  }
}

final class _LuaBytecodeCloseSuspension implements CoroutineContinuation {
  const _LuaBytecodeCloseSuspension({
    required this.vm,
    required this.frame,
    required this.fromRegister,
    required this.savedTop,
    required this.savedOpenTop,
    this.child,
  });

  final LuaBytecodeVm vm;
  final _LuaBytecodeFrame frame;
  final int fromRegister;
  final int savedTop;
  final int? savedOpenTop;
  final CoroutineContinuation? child;

  @override
  Future<Object?> resume(List<Object?> args) async {
    try {
      if (child case final nested?) {
        final nestedResult = await nested.resume(args);
        if (_continuationCompletesFrame(nested, frame)) {
          return nestedResult;
        }
      }
      frame.top = savedTop;
      frame.openTop = savedOpenTop;
      await frame.closeResources(fromRegister: fromRegister);
      final resumedResults = await vm._runFrameWithTailCalls(frame);
      return _packCallResults(vm.runtime, resumedResults);
    } on YieldException catch (error) {
      final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
      if (coroutine != null) {
        final nextChild = coroutine.takeContinuation();
        coroutine.installContinuation(
          _LuaBytecodeCloseSuspension(
            vm: vm,
            frame: frame,
            fromRegister: fromRegister,
            savedTop: frame.top,
            savedOpenTop: frame.openTop,
            child: nextChild,
          ),
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> close([Object? error]) async {
    if (child case final nested?) {
      await nested.close(error);
    }
    if (!frame.closed) {
      await frame.closeResources(fromRegister: 0, error: error);
    }
  }

  @override
  Iterable<GCObject> getReferences() sync* {
    yield* frame.gcReferences();
    if (child case final nested?) {
      yield* nested.getReferences();
    }
  }
}

final class _LuaBytecodeReturnSuspension implements CoroutineContinuation {
  const _LuaBytecodeReturnSuspension({
    required this.vm,
    required this.frame,
    required this.register,
    required this.resultSpec,
    required this.savedTop,
    required this.savedOpenTop,
    this.child,
  });

  final LuaBytecodeVm vm;
  final _LuaBytecodeFrame frame;
  final int register;
  final int resultSpec;
  final int savedTop;
  final int? savedOpenTop;
  final CoroutineContinuation? child;

  @override
  Future<Object?> resume(List<Object?> args) async {
    try {
      if (child case final nested?) {
        final nestedResult = await nested.resume(args);
        if (_continuationCompletesFrame(nested, frame)) {
          return nestedResult;
        }
      }
      frame.top = savedTop;
      frame.openTop = savedOpenTop;
      await frame.closeResources(fromRegister: 0);
      final resultCount = resultSpec == 0
          ? frame.effectiveTop - register
          : resultSpec - 1;
      return _packCallResults(
        vm.runtime,
        frame.resultsFrom(register, resultCount),
      );
    } on YieldException catch (error) {
      final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
      if (coroutine != null) {
        final nextChild = coroutine.takeContinuation();
        coroutine.installContinuation(
          _LuaBytecodeReturnSuspension(
            vm: vm,
            frame: frame,
            register: register,
            resultSpec: resultSpec,
            savedTop: frame.top,
            savedOpenTop: frame.openTop,
            child: nextChild,
          ),
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> close([Object? error]) async {
    if (child case final nested?) {
      await nested.close(error);
    }
    if (!frame.closed) {
      await frame.closeResources(fromRegister: 0, error: error);
    }
  }

  @override
  Iterable<GCObject> getReferences() sync* {
    yield* frame.gcReferences();
    if (child case final nested?) {
      yield* nested.getReferences();
    }
  }
}

bool _continuationCompletesFrame(
  CoroutineContinuation continuation,
  _LuaBytecodeFrame currentFrame,
) {
  if (continuation case _LuaBytecodeReturnSuspension(:final frame)) {
    return identical(frame, currentFrame);
  }
  if (continuation case _LuaBytecodeTailCallSuspension(:final frame)) {
    return identical(frame, currentFrame);
  }
  return false;
}

final class _LuaBytecodeTailCallSuspension implements CoroutineContinuation {
  const _LuaBytecodeTailCallSuspension({
    required this.vm,
    required this.frame,
    required this.word,
    this.child,
  });

  final LuaBytecodeVm vm;
  final _LuaBytecodeFrame frame;
  final LuaBytecodeInstructionWord word;
  final CoroutineContinuation? child;

  @override
  Future<Object?> resume(List<Object?> args) async {
    try {
      final results = await _resumeResults(args);
      await frame.closeResources(fromRegister: 0);
      return _packCallResults(vm.runtime, results);
    } on YieldException catch (error) {
      final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
      if (coroutine != null) {
        final nextChild = coroutine.takeContinuation();
        coroutine.installContinuation(
          _LuaBytecodeTailCallSuspension(
            vm: vm,
            frame: frame,
            word: word,
            child: nextChild,
          ),
        );
      }
      rethrow;
    }
  }

  Future<List<Value>> _resumeResults(List<Object?> args) async {
    if (child case final nested?) {
      final result = await nested.resume(args);
      return vm._normalizeResults(result);
    }
    return args
        .map((arg) => _runtimeValue(vm.runtime, arg))
        .toList(growable: false);
  }

  @override
  Future<void> close([Object? error]) async {
    if (child case final nested?) {
      await nested.close(error);
    }
    if (!frame.closed) {
      await frame.closeResources(fromRegister: 0, error: error);
    }
  }

  @override
  Iterable<GCObject> getReferences() sync* {
    yield* frame.gcReferences();
    if (child case final nested?) {
      yield* nested.getReferences();
    }
  }
}

final class _LuaBytecodeTForCallSuspension implements CoroutineContinuation {
  const _LuaBytecodeTForCallSuspension({
    required this.vm,
    required this.frame,
    required this.base,
    required this.resultCount,
    this.child,
  });

  final LuaBytecodeVm vm;
  final _LuaBytecodeFrame frame;
  final int base;
  final int resultCount;
  final CoroutineContinuation? child;

  @override
  Future<Object?> resume(List<Object?> args) async {
    late final List<Value> results;
    try {
      results = await _resumeResults(args);
    } on YieldException catch (error) {
      final coroutine = error.coroutine ?? vm.runtime.getCurrentCoroutine();
      if (coroutine != null) {
        final nextChild = coroutine.takeContinuation();
        coroutine.installContinuation(
          _LuaBytecodeTForCallSuspension(
            vm: vm,
            frame: frame,
            base: base,
            resultCount: resultCount,
            child: nextChild,
          ),
        );
      }
      rethrow;
    }
    for (var index = 0; index < results.length; index++) {
      frame.setRegister(base + 3 + index, results[index]);
    }
    frame.top = base + 3 + results.length;
    final resumedResults = await vm._runFrameWithTailCalls(frame);
    return _packCallResults(vm.runtime, resumedResults);
  }

  Future<List<Value>> _resumeResults(List<Object?> args) async {
    if (child case final nested?) {
      final result = await nested.resume(args);
      return vm._normalizeResults(result);
    }
    final resumed = args
        .map((arg) => _runtimeValue(vm.runtime, arg))
        .toList(growable: false);
    return List<Value>.generate(
      resultCount,
      (index) => index < resumed.length
          ? resumed[index]
          : _runtimeValue(vm.runtime, null),
      growable: false,
    );
  }

  @override
  Future<void> close([Object? error]) async {
    if (child case final nested?) {
      await nested.close(error);
    }
    if (!frame.closed) {
      await frame.closeResources(fromRegister: 0, error: error);
    }
  }

  @override
  Iterable<GCObject> getReferences() sync* {
    yield* frame.gcReferences();
    if (child case final nested?) {
      yield* nested.getReferences();
    }
  }
}

final class _LuaBytecodeUpvalue {
  _LuaBytecodeUpvalue.open(this._frame, this.registerIndex);

  _LuaBytecodeUpvalue.closed(Value value)
    : _closedValue = value,
      registerIndex = -1;

  _LuaBytecodeFrame? _frame;
  final int registerIndex;
  Value? _closedValue;

  bool get isOpen => _frame != null;

  Value read() => _frame?.register(registerIndex) ?? _closedValue!;

  void write(Value value) {
    final frame = _frame;
    if (frame != null) {
      frame.setRegister(registerIndex, value);
      return;
    }
    _closedValue = value;
  }

  void close() {
    final frame = _frame;
    if (frame == null) {
      return;
    }
    _closedValue = frame.register(registerIndex);
    _frame = null;
  }
}

Object? _packCallResults(LuaRuntime runtime, List<Value> results) {
  if (results.isEmpty) {
    return _runtimeValue(runtime, null);
  }
  if (results.length == 1) {
    return results.single;
  }
  final packed = Value.multi(results);
  packed.interpreter ??= runtime;
  return packed;
}

Value _wrapClosure(LuaBytecodeClosure closure) {
  final value = Value(closure);
  value.interpreter ??= closure.runtime;
  return value;
}

Value _constantValue(
  LuaRuntime runtime,
  LuaBytecodePrototype prototype,
  int index,
) {
  if (index < 0 || index >= prototype.constants.length) {
    throw RangeError.range(index, 0, prototype.constants.length - 1, 'index');
  }
  return switch (prototype.constants[index]) {
    LuaBytecodeNilConstant() => _runtimeValue(runtime, null),
    LuaBytecodeBooleanConstant(:final value) => _runtimeValue(runtime, value),
    LuaBytecodeIntegerConstant(:final value) => _runtimeValue(runtime, value),
    LuaBytecodeFloatConstant(:final value) => _runtimeValue(runtime, value),
    LuaBytecodeStringConstant(:final value) => runtime.constantStringValue(
      value.codeUnits,
    ),
  };
}

Value _stringConstant(
  LuaRuntime runtime,
  LuaBytecodePrototype prototype,
  int index,
) => _constantValue(runtime, prototype, index);

Future<bool> _explicitGlobalIsAlreadyDefined(
  Value envValue,
  Environment environment,
  String name,
) async {
  if (name == '_ENV') {
    final current = environment.root.get(name);
    return current != null && (current is! Value || current.raw != null);
  }

  if (envValue is Value && envValue.raw != null) {
    final current = await envValue.getValueAsync(name);
    return current is Value ? current.raw != null : current != null;
  }

  final current = environment.readRootGlobal(name);
  return current is Value ? current.raw != null : current != null;
}

Value _rkValue(_LuaBytecodeFrame frame, int operand, bool isConstant) {
  return isConstant
      ? _constantValue(frame.runtime, frame.closure.prototype, operand)
      : frame.register(operand);
}

Value _runtimeValue(LuaRuntime runtime, Object? value) {
  final wrapped = switch (value) {
    final Value existing => existing,
    _ => Value.wrap(value),
  };
  wrapped.interpreter ??= runtime;
  return wrapped;
}

Value _firstResultValue(Object? result) {
  if (result case final Value value when value.isMulti) {
    final values = value.raw as List<Object?>;
    return values.isEmpty ? Value.wrap(null) : Value.wrap(values.first);
  }
  if (result case final List<Object?> values) {
    return values.isEmpty ? Value.wrap(null) : Value.wrap(values.first);
  }
  if (result case final Value value) {
    return value;
  }
  return Value.wrap(result);
}

bool _canFastPathNumeric(Value value) => _coerceLuaNumber(value.raw) != null;

bool _canFastPathInteger(Value value) => _coerceLuaInteger(value.raw) != null;

bool _canFastPathConcat(Value value) {
  return switch (value.raw) {
    num() || String() || LuaString() => true,
    _ => false,
  };
}

bool _canFastPathLength(Value value) =>
    !value.hasMetamethod('__len') &&
    switch (value.raw) {
      LuaString() ||
      String() ||
      List<dynamic>() ||
      Map<dynamic, dynamic>() => true,
      _ => false,
    };

Object? _coerceLuaNumber(Object? value) {
  return switch (value) {
    int() || double() || BigInt() => value,
    final String stringValue => _tryParseLuaNumber(stringValue),
    final LuaString stringValue => _tryParseLuaNumber(stringValue.toString()),
    _ => null,
  };
}

Object? _coerceLuaInteger(Object? value) {
  return switch (_coerceLuaNumber(value)) {
    final int number => number,
    final BigInt number => number,
    final double number
        when number.isFinite && number.truncateToDouble() == number =>
      number,
    _ => null,
  };
}

Object? _tryParseLuaNumber(String text) {
  try {
    return LuaNumberParser.parse(text);
  } catch (_) {
    return null;
  }
}

String _metamethodName(int event) => switch (event) {
  0 => '__index',
  1 => '__newindex',
  2 => '__gc',
  3 => '__mode',
  4 => '__len',
  5 => '__eq',
  6 => '__add',
  7 => '__sub',
  8 => '__mul',
  9 => '__mod',
  10 => '__pow',
  11 => '__div',
  12 => '__idiv',
  13 => '__band',
  14 => '__bor',
  15 => '__bxor',
  16 => '__shl',
  17 => '__shr',
  18 => '__unm',
  19 => '__bnot',
  20 => '__lt',
  21 => '__le',
  22 => '__concat',
  23 => '__call',
  24 => '__close',
  _ => throw LuaError('unknown lua_bytecode metamethod event $event'),
};

_LuaBinaryOperation _binaryOperationForMetamethod(String metamethod) {
  return switch (metamethod) {
    '__add' => _LuaBinaryOperation.add,
    '__sub' => _LuaBinaryOperation.sub,
    '__mul' => _LuaBinaryOperation.mul,
    '__mod' => _LuaBinaryOperation.mod,
    '__pow' => _LuaBinaryOperation.pow,
    '__div' => _LuaBinaryOperation.div,
    '__idiv' => _LuaBinaryOperation.idiv,
    '__band' => _LuaBinaryOperation.band,
    '__bor' => _LuaBinaryOperation.bor,
    '__bxor' => _LuaBinaryOperation.bxor,
    '__shl' => _LuaBinaryOperation.shl,
    '__shr' => _LuaBinaryOperation.shr,
    '__concat' => _LuaBinaryOperation.concat,
    _ => throw LuaError('unsupported lua_bytecode metamethod $metamethod'),
  };
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

bool _isTruthy(Value value) {
  final raw = value.raw;
  return raw != null && raw != false;
}

bool _isNil(Value value) => value.raw == null;

bool _isInteger(Value value) => value.raw is int;

enum _PrimitiveCompare {
  lessThan,
  lessThanOrEqual,
  greaterThan,
  greaterThanOrEqual;

  bool apply(Value left, Value right) {
    return switch (this) {
          lessThan => left < right,
          lessThanOrEqual => left <= right,
          greaterThan => left > right,
          greaterThanOrEqual => left >= right,
        }
        as bool;
  }
}

int _integerValue(Value value) {
  return switch (value.raw) {
    final int integer => integer,
    final num numeric => numeric.toInt(),
    _ => throw LuaError('expected integer, got ${value.raw.runtimeType}'),
  };
}

num _numericValue(Value value) {
  return switch (value.raw) {
    final num numeric => numeric,
    _ => throw LuaError(
      'attempt to perform arithmetic on a ${value.raw.runtimeType} value',
    ),
  };
}

bool _rawEquals(Value left, Value right) {
  return left.equals(right);
}

bool? _tryPrimitiveOrdering(
  Value left,
  Value right,
  _PrimitiveCompare primitiveCompare,
) {
  final leftRaw = left.raw;
  final rightRaw = right.raw;
  final leftString = _stringLike(leftRaw);
  final rightString = _stringLike(rightRaw);
  return switch ((leftRaw, rightRaw)) {
    (num() || BigInt(), num() || BigInt()) => primitiveCompare.apply(
      left,
      right,
    ),
    _ when leftString != null && rightString != null => primitiveCompare.apply(
      left,
      right,
    ),
    _ => null,
  };
}

bool _compareImmediateEquals(Value left, int right) {
  final leftRaw = left.raw;
  return switch (leftRaw) {
    final int integer => integer == right,
    final double doubleValue => doubleValue == right,
    final BigInt integer => integer == BigInt.from(right),
    _ => false,
  };
}

bool? _tryPrimitiveImmediateOrdering(
  Value left,
  int right,
  _PrimitiveCompare primitiveCompare,
) {
  final leftRaw = left.raw;
  return switch (leftRaw) {
    num() || BigInt() => primitiveCompare.apply(left, Value.wrap(right)),
    _ => null,
  };
}

int _lengthOf(Value value) {
  return switch (value.raw) {
    final LuaString stringValue => stringValue.length,
    final String stringValue => stringValue.length,
    final List<dynamic> listValue => listValue.length,
    final Map<dynamic, dynamic> mapValue => _tableBoundaryLength(mapValue),
    _ => throw LuaError(
      'attempt to get length of a ${value.raw.runtimeType} value',
    ),
  };
}

extension on LuaBytecodeVm {
  Future<bool> _compareEquals(Value left, Value right) async {
    if (_rawEquals(left, right)) {
      return true;
    }
    if (!_supportsEqualityMetamethod(left, right)) {
      return false;
    }
    final metamethodResult = await _invokeBinaryMetamethod('__eq', left, right);
    return metamethodResult != null && _isTruthy(metamethodResult);
  }

  Future<bool> _compareOrdering(
    Value left,
    Value right, {
    required String metamethod,
    required _PrimitiveCompare primitiveCompare,
  }) async {
    final primitiveResult = _tryPrimitiveOrdering(
      left,
      right,
      primitiveCompare,
    );
    if (primitiveResult != null) {
      return primitiveResult;
    }

    final metamethodResult = await _invokeBinaryMetamethod(
      metamethod,
      left,
      right,
    );
    if (metamethodResult != null) {
      return _isTruthy(metamethodResult);
    }

    throw LuaError(_orderComparisonError(left, right));
  }

  Future<bool> _compareImmediateOrdering(
    Value left,
    int right, {
    required String metamethod,
    required _PrimitiveCompare primitiveCompare,
    bool flipOperands = false,
  }) async {
    final primitiveResult = _tryPrimitiveImmediateOrdering(
      left,
      right,
      primitiveCompare,
    );
    if (primitiveResult != null) {
      return primitiveResult;
    }

    final rightValue = _runtimeValue(runtime, right);
    final (metamethodLeft, metamethodRight) = flipOperands
        ? (rightValue, left)
        : (left, rightValue);
    final metamethodResult = await _invokeBinaryMetamethod(
      metamethod,
      metamethodLeft,
      metamethodRight,
    );
    if (metamethodResult != null) {
      return _isTruthy(metamethodResult);
    }

    throw LuaError(_orderComparisonError(metamethodLeft, metamethodRight));
  }
}

bool _supportsEqualityMetamethod(Value left, Value right) {
  return getLuaType(left) == 'table' && getLuaType(right) == 'table';
}

String _orderComparisonError(Value left, Value right) {
  final leftType = getLuaType(left);
  final rightType = getLuaType(right);
  return leftType == rightType
      ? 'attempt to compare two $leftType values'
      : 'attempt to compare $leftType with $rightType';
}

int _tableBoundaryLength(Map<dynamic, dynamic> mapValue) {
  final occupiedPositiveIndices = <int>{};
  for (final MapEntry(:key, :value) in mapValue.entries) {
    final index = _positiveIntegerKey(key);
    if (index == null || _isNilLike(value)) {
      continue;
    }
    occupiedPositiveIndices.add(index);
  }

  var length = 0;
  while (occupiedPositiveIndices.contains(length + 1)) {
    length += 1;
  }
  return length;
}

int? _positiveIntegerKey(Object? key) {
  final rawKey = switch (key) {
    final Value value => value.raw,
    _ => key,
  };
  return switch (rawKey) {
    final int value when value > 0 => value,
    final num value
        when value.isFinite &&
            value > 0 &&
            value.toInt().toDouble() == value.toDouble() =>
      value.toInt(),
    _ => null,
  };
}

bool _isNilLike(Object? value) => switch (value) {
  null => true,
  final Value wrapped => wrapped.raw == null,
  _ => false,
};

String? _stringLike(Object? value) => switch (value) {
  final LuaString stringValue => stringValue.toString(),
  final String stringValue => stringValue,
  _ => null,
};

int _signedB(LuaBytecodeInstructionWord word) =>
    word.b - LuaBytecodeInstructionLayout.offsetSB;

int _signedC(LuaBytecodeInstructionWord word) =>
    word.c - LuaBytecodeInstructionLayout.offsetSC;

Future<void> _runGcLoopSafePoint(
  LuaRuntime runtime,
  _LuaBytecodeFrame frame,
) async {
  final dynamicRuntime = runtime as dynamic;
  frame.loopGcCounter += 1;
  await dynamicRuntime.runLoopGcAtSafePoint(frame.loopGcCounter);
}

({bool skip, int limit}) _forIntegerLimit(
  int initial,
  Object rawLimit,
  int step,
) {
  if (rawLimit is int) {
    return (
      skip: step > 0 ? initial > rawLimit : initial < rawLimit,
      limit: rawLimit,
    );
  }
  if (rawLimit is BigInt) {
    if (NumberUtils.isInIntegerRange(rawLimit)) {
      final limit = rawLimit.toInt();
      return (skip: step > 0 ? initial > limit : initial < limit, limit: limit);
    }
    if (rawLimit.isNegative) {
      return step > 0
          ? (skip: true, limit: NumberLimits.minInteger)
          : (skip: false, limit: NumberLimits.minInteger);
    }
    return step < 0
        ? (skip: true, limit: NumberLimits.maxInteger)
        : (skip: false, limit: NumberLimits.maxInteger);
  }
  if (rawLimit is num) {
    if (!rawLimit.isFinite) {
      if (rawLimit.isNegative) {
        return step > 0
            ? (skip: true, limit: NumberLimits.minInteger)
            : (skip: false, limit: NumberLimits.minInteger);
      }
      return step < 0
          ? (skip: true, limit: NumberLimits.maxInteger)
          : (skip: false, limit: NumberLimits.maxInteger);
    }
    if (rawLimit < NumberLimits.minInteger) {
      return step > 0
          ? (skip: true, limit: NumberLimits.minInteger)
          : (skip: false, limit: NumberLimits.minInteger);
    }
    if (rawLimit > NumberLimits.maxInteger) {
      return step < 0
          ? (skip: true, limit: NumberLimits.maxInteger)
          : (skip: false, limit: NumberLimits.maxInteger);
    }
    final limit = step < 0 ? rawLimit.ceil() : rawLimit.floor();
    return (skip: step > 0 ? initial > limit : initial < limit, limit: limit);
  }
  throw LuaError("bad 'for' limit (${rawLimit.runtimeType})");
}

BigInt _unsignedInt64({required int init}) => NumberUtils.toUnsigned64(init);

BigInt _unsignedDifference64(BigInt left, BigInt right) {
  final mod = BigInt.one << NumberLimits.sizeInBits;
  var difference = left - right;
  if (difference.isNegative) {
    difference += mod;
  }
  return difference;
}

BigInt _negativeStepDivisor(int step) => BigInt.from(-(step + 1)) + BigInt.one;

BigInt _unsignedForLoopCounter(Value value) {
  final raw = value.raw;
  return switch (raw) {
    final int integer => NumberUtils.toUnsigned64(integer),
    _ => throw LuaError('expected integer, got ${raw.runtimeType}'),
  };
}

int _signedInt64FromUnsigned(BigInt value) {
  final mod = BigInt.one << NumberLimits.sizeInBits;
  final masked = value & (mod - BigInt.one);
  if (masked > BigInt.from(NumberLimits.maxInteger)) {
    return (masked - mod).toInt();
  }
  return masked.toInt();
}

Object _forNumericOperand(Value value, String role) {
  final raw = value.raw;
  final coerced = _coerceLuaNumber(raw);
  if (coerced != null) {
    return coerced;
  }
  throw LuaError(
    "bad 'for' $role (number expected, got ${NumberUtils.typeName(raw)})",
  );
}

int? _exactForIntegerValue(Object value) {
  return switch (value) {
    final int integer => integer,
    final BigInt integer when NumberUtils.isInIntegerRange(integer) =>
      integer.toInt(),
    _ => null,
  };
}

num _numericForOperand(Object value) {
  return switch (value) {
    final int integer => integer,
    final double numeric => numeric,
    final BigInt integer when NumberUtils.isInIntegerRange(integer) =>
      integer.toInt(),
    final BigInt integer => integer.toDouble(),
    _ => throw LuaError(
      'attempt to perform arithmetic on a ${value.runtimeType} value',
    ),
  };
}
