import 'package:lualike/src/bytecode/debug.dart' show DebugChunk;
import 'package:lualike/src/bytecode/opcode.dart' show OpCode;
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/stdlib/init.dart';
import 'package:lualike/lualike.dart' show BuiltinFunction;
import 'bytecode.dart';
import 'value.dart';

class Register {
  Value value;
  Register(this.value);
}

class CallFrame {
  List<Value>? varargs; // Only present if function has varargs
  final List<Upvalue>? upvalues; // Only present for closure calls

  CallFrame(this.chunk, {this.upvalues, this.varargs})
    : registers = List.generate(
        chunk.numRegisters,
        (_) => Register(const Value.nil()),
      );

  Value getUpvalue(int index) {
    if (upvalues == null || index >= upvalues!.length) {
      throw Exception('Invalid upvalue access');
    }
    final upvalue = upvalues![index];
    return upvalue.isClosed ? upvalue.closed! : registers[upvalue.index].value;
  }

  void setUpvalue(int index, Value value) {
    if (upvalues == null || index >= upvalues!.length) {
      throw Exception('Invalid upvalue access');
    }
    final upvalue = upvalues![index];
    if (upvalue.isClosed) {
      upvalue.closed = value;
    } else {
      registers[upvalue.index].value = value;
    }
  }

  final BytecodeChunk chunk;
  final List<Register> registers;
  int pc = 0;
}

bool _isFalsy(Value value) {
  return value.type == ValueType.nil ||
      (value.type == ValueType.boolean && value.raw == false);
}

class BytecodeVM {
  final Map<String, BuiltinFunction> _builtinFunctionRegistry = {};

  final Environment globals = Environment(); // Global environment

  BytecodeVM() {
    _initializeBuiltinFunctions();
  }

  Map<String, BuiltinFunction> get functionRegistry => _builtinFunctionRegistry;

  void _initializeBuiltinFunctions() {
    initializeStandardLibrary(
      env: globals,
      astVm: null,
      bytecodeVm: this,
    ); // Pass null for astVm, 'this' for bytecodeVm
  }

  /// Stack trace of current execution
  final List<String> stackTrace = [];

  /// Current error handler if any
  void Function(String error, List<String> trace)? errorHandler;

  /// Records an error with debug information
  void _recordError(String message, CallFrame frame) {
    final trace = <String>[];

    // Add current instruction debug info
    if (frame.chunk is DebugChunk) {
      final debug = (frame.chunk as DebugChunk).getDebugInfo(frame.pc - 1);
      if (debug != null) {
        trace.add(debug.toString());
      }
    }

    // Add stack trace
    trace.addAll(stackTrace);

    // Call error handler or throw
    if (errorHandler != null) {
      errorHandler!(message, trace);
    } else {
      throw Exception('$message\n${trace.join('\n')}');
    }
  }

  /// Push a new stack frame
  void _pushFrame(CallFrame frame) {
    frames.add(frame);

    // Add to stack trace if debug info available
    if (frame.chunk is DebugChunk) {
      final chunk = frame.chunk as DebugChunk;
      stackTrace.add('at ${chunk.name}');
    }
  }

  /// Pop current stack frame
  void _popFrame() {
    frames.removeLast();
    if (stackTrace.isNotEmpty) {
      stackTrace.removeLast();
    }
  }

  final List<CallFrame> frames = [];
  final List<Value> stack = [];

  Value execute(BytecodeChunk chunk) {
    _pushFrame(CallFrame(chunk));

    while (true) {
      final frame = frames.last;
      if (frame.pc >= frame.chunk.instructions.length) {
        _popFrame();
        if (frames.isEmpty) break;
        continue;
      }

      final instruction = frame.chunk.instructions[frame.pc];
      frame.pc++;

      switch (instruction.op) {
        case OpCode.CLOSURE:
          final protoIndex = instruction.operands[0];
          final chunk = frame.chunk.constants[protoIndex] as BytecodeChunk;
          final upvalueCount = instruction.operands[1] as int;
          final upvalues = <Upvalue>[];

          // Capture upvalues
          for (var i = 0; i < upvalueCount; i++) {
            final isLocal = instruction.operands[2 + i * 2] as bool;
            final index = instruction.operands[3 + i * 2] as int;

            if (isLocal) {
              upvalues.add(Upvalue(index));
            } else {
              // Copy upvalue from enclosing function
              upvalues.add(frame.upvalues![index]);
            }
          }

          stack.add(Value.closure(Closure(chunk, upvalues)));

        case OpCode.GETUPVAL:
          final upvalueIndex = instruction.operands[0];
          stack.add(frame.getUpvalue(upvalueIndex));

        case OpCode.SETUPVAL:
          final upvalueIndex = instruction.operands[0];
          final value = stack.removeLast();
          frame.setUpvalue(upvalueIndex, value);

        case OpCode.CALL:
          final int argCount = instruction.operands[0];
          final func = stack[stack.length - argCount - 1];

          if (func.type != ValueType.closure) {
            throw Exception('Attempt to call non-function');
          }

          final closure = func.raw as Closure;
          final newFrame = CallFrame(closure.chunk, upvalues: closure.upvalues);

          // Set arguments as local variables
          for (var i = 0; i < argCount; i++) {
            newFrame.registers[i].value = stack[stack.length - argCount + i];
          }

          // Remove arguments and function from stack
          stack.length -= (argCount + 1);

          frames.add(newFrame);

        case OpCode.CONCAT:
          final int count = instruction.operands[0];
          if (count < 2) throw Exception('CONCAT requires at least 2 values');

          final result = StringBuffer();
          for (var i = 0; i < count; i++) {
            final val = stack[stack.length - count + i];
            if (val.type != ValueType.string) {
              throw Exception('CONCAT requires string values');
            }
            result.write(val.raw);
          }

          // Remove concatenated strings and push result
          stack.length -= count;
          stack.add(Value.string(result.toString()));

        case OpCode.LEN:
          final val = stack.removeLast();
          switch (val.type) {
            case ValueType.string:
              stack.add(Value.number((val.raw as String).length));
            case ValueType.table:
              stack.add(Value.number((val.raw as Map).length));
            default:
              throw Exception('Cannot get length of ${val.type}');
          }

        case OpCode.SELF:
          // Extract method and prepare for call
          final key = stack.removeLast();
          final table = stack[stack.length - 1]; // Leave table on stack

          if (table.type != ValueType.table) {
            throw Exception('SELF requires table');
          }

          final map = table.raw as Map<Value, Value>;
          final method = map[key] ?? const Value.nil();

          // Push method and self parameter
          stack.add(method);
          stack.add(table);

        case OpCode.VARARGS:
          final count = instruction.operands[0] as int;
          if (frame.varargs == null) {
            throw Exception('No varargs available');
          }

          // Push requested number of varargs (or all if count is -1)
          final args =
              count < 0 ? frame.varargs! : frame.varargs!.take(count).toList();
          stack.addAll(args);

        case OpCode.SETUPVARARGS:
          final startIndex = instruction.operands[0] as int;
          final length = stack.length - startIndex;

          // Collect varargs from stack
          final varargs = stack.sublist(startIndex, startIndex + length);
          frame.varargs = varargs;

          // Remove collected args from stack
          stack.length = startIndex;
        // Load operations
        case OpCode.LOAD_CONST:
          final constIndex = instruction.operands[0];
          final value = frame.chunk.constants[constIndex];
          stack.add(Value.fromLuaLike(value));

        case OpCode.LOAD_NIL:
          stack.add(const Value.nil());

        case OpCode.LOAD_BOOL:
          final value = instruction.operands[0];
          stack.add(Value.boolean(value));

        case OpCode.LOAD_LOCAL:
          final regIndex = instruction.operands[0];
          stack.add(frame.registers[regIndex].value);

        case OpCode.STORE_LOCAL:
          final regIndex = instruction.operands[0];
          frame.registers[regIndex].value = stack.removeLast();

        // Arithmetic operations
        case OpCode.ADD:
          final b = stack.removeLast();
          final a = stack.removeLast();
          if (a.type == ValueType.number && b.type == ValueType.number) {
            stack.add(Value.number((a.raw as num) + (b.raw as num)));
          } else {
            throw Exception('ADD requires number operands');
          }

        case OpCode.SUB:
          final b = stack.removeLast();
          final a = stack.removeLast();
          if (a.type == ValueType.number && b.type == ValueType.number) {
            stack.add(Value.number((a.raw as num) - (b.raw as num)));
          } else {
            throw Exception('SUB requires number operands');
          }

        case OpCode.MUL:
          final b = stack.removeLast();
          final a = stack.removeLast();
          if (a.type == ValueType.number && b.type == ValueType.number) {
            stack.add(Value.number((a.raw as num) * (b.raw as num)));
          } else {
            throw Exception('MUL requires number operands');
          }

        case OpCode.DIV:
          final b = stack.removeLast();
          final a = stack.removeLast();
          if (a.type == ValueType.number && b.type == ValueType.number) {
            if (b.raw == 0) throw Exception('Division by zero');
            stack.add(Value.number((a.raw as num) / (b.raw as num)));
          } else {
            throw Exception('DIV requires number operands');
          }

        case OpCode.MOD:
          final b = stack.removeLast();
          final a = stack.removeLast();
          if (a.type == ValueType.number && b.type == ValueType.number) {
            stack.add(Value.number((a.raw as num) % (b.raw as num)));
          } else {
            throw Exception('MOD requires number operands');
          }

        case OpCode.UNM:
          final a = stack.removeLast();
          if (a.type == ValueType.number) {
            stack.add(Value.number(-(a.raw as num)));
          } else {
            throw Exception('UNM requires number operand');
          }

        case OpCode.NOT:
          final a = stack.removeLast();
          stack.add(Value.boolean(_isFalsy(a)));

        // Comparison operations
        case OpCode.EQ:
          final b = stack.removeLast();
          final a = stack.removeLast();
          stack.add(Value.boolean(a == b));

        case OpCode.LT:
          final b = stack.removeLast();
          final a = stack.removeLast();
          if (a.type == ValueType.number && b.type == ValueType.number) {
            stack.add(Value.boolean((a.raw as num) < (b.raw as num)));
          } else {
            throw Exception('LT requires number operands');
          }

        case OpCode.LE:
          final b = stack.removeLast();
          final a = stack.removeLast();
          if (a.type == ValueType.number && b.type == ValueType.number) {
            stack.add(Value.boolean((a.raw as num) <= (b.raw as num)));
          } else {
            throw Exception('LE requires number operands');
          }

        // Control flow
        case OpCode.JMP:
          final int offset = instruction.operands[0];
          frame.pc += offset;

        case OpCode.JMPF:
          final int offset = instruction.operands[0];
          final cond = stack.removeLast();
          if (_isFalsy(cond)) {
            frame.pc += offset;
          }

        case OpCode.JMPT:
          final int offset = instruction.operands[0];
          final cond = stack.removeLast();
          if (!_isFalsy(cond)) {
            frame.pc += offset;
          }

        case OpCode.RETURN:
          final result = stack.removeLast();
          frames.removeLast();
          if (frames.isEmpty) {
            return result;
          }
          stack.add(result);

        // Table operations
        case OpCode.NEWTABLE:
          stack.add(Value.table({}));

        case OpCode.GETTABLE:
          final key = stack.removeLast();
          final table = stack.removeLast();
          if (table.type != ValueType.table) {
            throw Exception('GETTABLE requires table');
          }
          final map = table.raw as Map<Value, Value>;
          stack.add(map[key] ?? const Value.nil());

        case OpCode.SETTABLE:
          final value = stack.removeLast();
          final key = stack.removeLast();
          final table = stack.removeLast();
          if (table.type != ValueType.table) {
            throw Exception('SETTABLE requires table');
          }
          final map = table.raw as Map<Value, Value>;
          map[key] = value;
          stack.add(table);

        default:
          throw Exception('Unimplemented opcode ${instruction.op}');
      }
    }

    try {
      return stack.removeLast();
    } catch (e) {
      _recordError('Stack underflow', frames.last);
      return const Value.nil();
    }
  }
}
