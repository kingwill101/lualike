import 'dart:collection';

import 'package:lualike/src/lua_bytecode/opcode.dart';
import 'package:lualike/src/lua_bytecode/vm_value_helpers.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/value.dart';

Value bytecodeFrameNilValue(dynamic frame) {
  return frame.env?.interpreter?.constantPrimitiveValue(null) ??
      frame.callable?.interpreter?.constantPrimitiveValue(null) ??
      Value.primitive(null);
}

bool localStartsOnCurrentLine(
  dynamic prototype,
  dynamic local,
  int currentLine,
) {
  final startPc = local.startPc;
  if (startPc >= prototype.code.length) {
    return prototype.lineDefined > 0 && currentLine == prototype.lineDefined;
  }
  final directLine = startPc < prototype.code.length
      ? prototype.lineForPc(startPc)
      : null;
  if (directLine == currentLine) {
    return true;
  }
  if (startPc > 0) {
    final previousLine = prototype.lineForPc(startPc - 1);
    if (previousLine == currentLine) {
      return true;
    }
  }
  return false;
}

bool localHasPendingClosureTemporaryOnCurrentLine(
  dynamic prototype,
  dynamic local,
  int currentLine,
) {
  final register = local.register;
  if (register == null) {
    return false;
  }
  final closurePc = local.startPc - 2;
  if (closurePc < 0 || closurePc >= prototype.code.length) {
    return false;
  }
  if (prototype.lineForPc(closurePc) != currentLine) {
    return false;
  }
  final word = prototype.code[closurePc];
  return word.opcode == Opcode.closure && word.a == register;
}

void overwriteValue(Value target, Value source) {
  target.raw = rawLuaSlot(source);
  target.metatable = source.metatable;
  target.metatableRef = source.metatableRef;
  target.upvalues = source.upvalues;
  target.interpreter = source.interpreter;
  target.functionBody = source.functionBody;
  target.closureEnvironment = source.closureEnvironment;
  target.functionName = source.functionName;
  target.debugLineDefined = source.debugLineDefined;
}

final class LuaBytecodeFrameArgsView extends ListBase<Object?> {
  LuaBytecodeFrameArgsView(
    this._frame, {
    required this.start,
    required this.count,
  });

  final dynamic _frame;
  final int start;
  final int count;

  Iterable<Value> get gcRoots sync* {
    for (var index = 0; index < count; index++) {
      yield _frame.slotValue(start + index);
    }
  }

  @override
  int get length => count;

  @override
  set length(int newLength) => throw UnsupportedError('Cannot resize view');

  @override
  Object? operator [](int index) => _frame.slotValue(start + index);

  @override
  void operator []=(int index, Object? value) {
    _frame.setRegister(start + index, runtimeValue(_frame.runtime, value));
  }
}
