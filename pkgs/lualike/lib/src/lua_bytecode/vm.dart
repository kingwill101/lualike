import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/instruction.dart';
import 'package:lualike/src/lua_bytecode/opcode.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/number.dart';
import 'package:lualike/src/number_utils.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/table_storage.dart';
import 'package:lualike/src/utils/type.dart' show getLuaType;
import 'package:lualike/src/value.dart';
import 'package:path/path.dart' as path;

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
    if (upvalues.isNotEmpty) {
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
    final results = await vm.invoke(this, args);
    return _packCallResults(runtime, results);
  }
}

final class LuaBytecodeVm {
  LuaBytecodeVm(this.runtime);

  final LuaRuntime runtime;

  Future<List<Value>> invoke(
    LuaBytecodeClosure closure,
    List<Object?> args,
  ) async {
    final frame = _LuaBytecodeFrame(
      runtime: runtime,
      closure: closure,
      arguments: args,
    );

    final previousEnv = runtime.getCurrentEnv();
    final previousScriptPath = runtime.currentScriptPath;
    runtime.setCurrentEnv(closure.environment);
    runtime.currentScriptPath = closure.prototype.source ?? previousScriptPath;
    runtime.callStack.push(
      closure.debugInfo.shortSource,
      env: closure.environment,
    );

    try {
      return await _executeFrame(frame);
    } catch (error) {
      if (!frame.closed) {
        await frame.closeResources(fromRegister: 0, error: error);
      }
      rethrow;
    } finally {
      if (!frame.closed) {
        await frame.closeResources(fromRegister: 0);
      }
      runtime.callStack.pop();
      runtime.currentScriptPath = previousScriptPath;
      runtime.setCurrentEnv(previousEnv);
    }
  }

  Future<List<Value>> _executeFrame(_LuaBytecodeFrame frame) async {
    final prototype = frame.closure.prototype;
    while (frame.pc < prototype.code.length) {
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
            frame.markToBeClosed(word.a);
            break;
          }
        case 'VARARGPREP':
          {
            break;
          }
        case 'JMP':
          {
            frame.pc += word.sJ;
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
            final results = await _callAt(frame, word);
            nextOpenTop = _storeCallResults(frame, word.a, word.c, results);
            break;
          }
        case 'TAILCALL':
          {
            final call = _resolveCall(frame, word);
            await frame.closeResources(fromRegister: 0);
            return _invokePreparedCall(call);
          }
        case 'RETURN':
          {
            final resultCount = word.b == 0
                ? frame.effectiveTop - word.a
                : word.b - 1;
            final results = frame.resultsFrom(word.a, resultCount);
            await frame.closeResources(fromRegister: 0);
            return results;
          }
        case 'RETURN0':
          {
            await frame.closeResources(fromRegister: 0);
            return const <Value>[];
          }
        case 'RETURN1':
          {
            await frame.closeResources(fromRegister: 0);
            return <Value>[frame.register(word.a)];
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
            final results = await _genericForCall(frame, word.a, word.c);
            for (var index = 0; index < results.length; index++) {
              frame.setRegister(word.a + 3 + index, results[index]);
            }
            frame.top = word.a + 3 + results.length;
            break;
          }
        case 'TFORLOOP':
          {
            if (!_isNil(frame.register(word.a + 3))) {
              frame.pc -= word.bx;
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
            final varargResults = frame.varargs;
            nextOpenTop = _storeVarargResults(frame, word, varargResults);
            break;
          }
        case 'GETVARG':
          {
            final indexValue = frame.register(word.c);
            final index = _integerValue(indexValue);
            if (index < 1 || index > frame.varargs.length) {
              frame.setRegister(word.a, _runtimeValue(runtime, null));
            } else {
              frame.setRegister(word.a, frame.varargs[index - 1]);
            }
            break;
          }
        case 'CLOSE':
          {
            await frame.closeResources(fromRegister: word.a);
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
    var current = frame.register(startRegister);
    for (var offset = 1; offset < operandCount; offset++) {
      final next = frame.register(startRegister + offset);
      final fastPath = _tryBinaryFastPath(
        _LuaBinaryOperation.concat,
        current,
        next,
      );
      if (fastPath != null) {
        current = fastPath;
        continue;
      }

      final metamethodResult = await _invokeBinaryMetamethod(
        '__concat',
        current,
        next,
      );
      if (metamethodResult != null) {
        current = metamethodResult;
        continue;
      }

      current = _forceBinaryOperation(
        _LuaBinaryOperation.concat,
        current,
        next,
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
    return _invokePreparedCall(_resolveCall(frame, word));
  }

  Future<List<Value>> _invokePreparedCall(
    ({Value callee, List<Value> args}) call,
  ) {
    return _invokeValue(call.callee, call.args);
  }

  Future<List<Value>> _invokeValue(Value callee, List<Value> args) async {
    callee.interpreter ??= runtime;
    if (callee.raw case final LuaBytecodeClosure closure) {
      return invoke(closure, args);
    }
    final result = await runtime.callFunction(callee, args);
    return _normalizeResults(result);
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

    if (_isInteger(initial) && _isInteger(step)) {
      final init = _integerValue(initial);
      final stepValue = _integerValue(step);
      if (stepValue == 0) {
        throw LuaError("'for' step is zero");
      }
      final limitValue = _forIntegerLimit(init, limit, stepValue);
      final shouldSkip = stepValue > 0 ? init > limitValue : init < limitValue;
      if (shouldSkip) {
        return true;
      }

      final count = stepValue > 0
          ? (limitValue - init) ~/ stepValue
          : (init - limitValue) ~/ (-stepValue);
      frame.setRegister(base, _runtimeValue(runtime, count));
      frame.setRegister(base + 1, _runtimeValue(runtime, stepValue));
      frame.setRegister(base + 2, _runtimeValue(runtime, init));
      return false;
    }

    final init = _numericValue(initial).toDouble();
    final limitValue = _numericValue(limit).toDouble();
    final stepValue = _numericValue(step).toDouble();
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
      final count = _integerValue(frame.register(base));
      if (count <= 0) {
        return false;
      }
      final step = _integerValue(frame.register(base + 1));
      final nextIndex = _integerValue(frame.register(base + 2)) + step;
      frame.setRegister(base, _runtimeValue(runtime, count - 1));
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
    final iterator = frame.register(base);
    final state = frame.register(base + 1);
    final control = frame.register(base + 3);
    final results = await _invokeValue(iterator, <Value>[state, control]);
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

final class _LuaBytecodeFrame {
  _LuaBytecodeFrame({
    required this.runtime,
    required this.closure,
    required List<Object?> arguments,
  }) : registers = List<Value>.generate(
         closure.prototype.maxStackSize,
         (_) => _runtimeValue(runtime, null),
         growable: true,
       ),
       varargs = <Value>[] {
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
    top = parameterCount;
  }

  final LuaRuntime runtime;
  final LuaBytecodeClosure closure;
  final List<Value> registers;
  final List<Value> varargs;
  final List<_LuaBytecodeUpvalue> _openUpvalues = <_LuaBytecodeUpvalue>[];
  final Set<int> _toBeClosedRegisters = <int>{};

  var pc = 0;
  var top = 0;
  int? openTop;
  var closed = false;

  int get effectiveTop => openTop ?? top;

  Value register(int index) => index < registers.length
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
    registers[index] = _prepareAssignedValue(index, value);
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
    _toBeClosedRegisters.add(registerIndex);
    setRegister(registerIndex, register(registerIndex));
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

    Object? closeError;
    StackTrace? closeStackTrace;
    for (final registerIndex in registersToClose) {
      final value = register(registerIndex);
      if (value.raw == null || value.raw == false) {
        continue;
      }
      final closeValue = value.isToBeClose ? value : Value.toBeClose(value);
      closeValue.interpreter ??= runtime;
      try {
        await closeValue.close(error);
      } catch (caughtError, caughtStackTrace) {
        closeError ??= caughtError;
        closeStackTrace ??= caughtStackTrace;
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

  Value _prepareAssignedValue(int index, Value value) {
    value.interpreter ??= runtime;
    if (!_toBeClosedRegisters.contains(index)) {
      return value;
    }

    if (value.raw == null || value.raw == false) {
      return value;
    }

    final prepared = value.isToBeClose ? value : Value.toBeClose(value);
    prepared.interpreter ??= runtime;
    return prepared;
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
    LuaBytecodeStringConstant(:final value) => _runtimeValue(
      runtime,
      LuaString.fromDartString(value),
    ),
  };
}

Value _stringConstant(
  LuaRuntime runtime,
  LuaBytecodePrototype prototype,
  int index,
) => _constantValue(runtime, prototype, index);

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
  try {
    return path.basename(source);
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

int _forIntegerLimit(int initial, Value limitValue, int step) {
  final raw = limitValue.raw;
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return step < 0 ? raw.ceil() : raw.floor();
  }
  throw LuaError("bad 'for' limit (${raw.runtimeType})");
}
