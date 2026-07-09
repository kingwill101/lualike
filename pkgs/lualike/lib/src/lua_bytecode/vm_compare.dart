part of 'vm.dart';

extension LuaBytecodeVmCompare on LuaBytecodeVm {
  Future<bool> _compareEquals(Value left, Value right) async {
    if (rawEquals(left, right)) {
      return true;
    }
    if (!supportsEqualityMetamethod(left, right)) {
      return false;
    }
    final metamethodResult = await _invokeBinaryMetamethod('__eq', left, right);
    return metamethodResult != null && isLuaTruthy(metamethodResult);
  }

  Future<bool> _compareOrdering(
    Value left,
    Value right, {
    required String metamethod,
    required PrimitiveCompare primitiveCompare,
  }) async {
    final primitiveResult = tryPrimitiveOrdering(left, right, primitiveCompare);
    if (primitiveResult != null) {
      return primitiveResult;
    }

    final metamethodResult = await _invokeBinaryMetamethod(
      metamethod,
      left,
      right,
    );
    if (metamethodResult != null) {
      return isLuaTruthy(metamethodResult);
    }

    throw LuaError(orderComparisonError(left, right));
  }

  Future<bool> _compareImmediateOrdering(
    Value left,
    int right, {
    required String metamethod,
    required PrimitiveCompare primitiveCompare,
    bool flipOperands = false,
  }) async {
    final primitiveResult = tryPrimitiveImmediateOrdering(
      left,
      right,
      primitiveCompare,
    );
    if (primitiveResult != null) {
      return primitiveResult;
    }

    final rightValue = runtimeValue(runtime, right);
    final (metamethodLeft, metamethodRight) = flipOperands
        ? (rightValue, left)
        : (left, rightValue);
    final metamethodResult = await _invokeBinaryMetamethod(
      metamethod,
      metamethodLeft,
      metamethodRight,
    );
    if (metamethodResult != null) {
      return isLuaTruthy(metamethodResult);
    }

    throw LuaError(orderComparisonError(left, rightValue));
  }
}
