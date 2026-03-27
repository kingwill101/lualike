import 'package:lualike/src/runtime/lua_runtime.dart';

final Expando<_RuntimeExecutionHints> _runtimeExecutionHints =
    Expando<_RuntimeExecutionHints>('runtimeExecutionHints');

bool isInsideSortComparator(LuaRuntime runtime) {
  return (_runtimeExecutionHints[runtime]?.sortComparatorDepth ?? 0) > 0;
}

void enterSortComparator(LuaRuntime runtime) {
  final hints = _runtimeExecutionHints[runtime] ??= _RuntimeExecutionHints();
  hints.sortComparatorDepth++;
}

void exitSortComparator(LuaRuntime runtime) {
  final hints = _runtimeExecutionHints[runtime];
  if (hints == null || hints.sortComparatorDepth == 0) {
    return;
  }
  hints.sortComparatorDepth--;
}

final class _RuntimeExecutionHints {
  int sortComparatorDepth = 0;
}
