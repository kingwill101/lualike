part of 'vm.dart';

const Object _unhandledTableSlot = Object();

extension LuaBytecodeVmTables on LuaBytecodeVm {
  Future<void> _setList(
    LuaBytecodeFrame frame,
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
      final valueSlot = frame.rawSlot(word.a + remaining);
      if (!_tryFastTableSetSlot(table, last, valueSlot)) {
        await _tableSet(
          table,
          runtimeValue(frame.runtime, last),
          valueFromLuaSlot(frame.runtime, valueSlot),
        );
      }
      last--;
    }
  }

  void _docondjump(
    LuaBytecodeFrame frame,
    LuaBytecodeInstructionWord word,
    bool condition,
  ) {
    if (condition != word.kFlag) {
      frame.pc += 1;
    }
  }

  Future<Value> _tableGet(Value table, Value key) async {
    if (_tryFastTableGet(table, key) case final Value fastValue) {
      return fastValue;
    }
    table.interpreter ??= runtime;
    key.interpreter ??= runtime;
    final result = await table.getValueAsync(key);
    return runtimeValue(runtime, result);
  }

  LuaSlot _tryFastTableGetSlot(Value table, LuaSlot key) {
    final rawTable = rawLuaSlot(table);
    final storageKey = _plainTableStorageKey(key);
    if (rawTable is Map &&
        table.globalProxyEnvironment != null &&
        table.tableWeakMode == null) {
      if (!rawTable.containsKey(storageKey)) {
        return _unhandledTableSlot;
      }
      return rawTable[storageKey];
    }
    if (rawTable is TableStorage && _canReadPlainTable(table)) {
      return switch (_plainPositiveIntegerKey(key)) {
        final int index => rawTable.arrayValueAt(index),
        _ => rawTable[storageKey],
      };
    }
    if (rawTable is Map && _canReadPlainTable(table)) {
      return rawTable[storageKey];
    }
    return _unhandledTableSlot;
  }

  LuaSlot _tryFastTableGetStringKeySlot(Value table, String rawKey) {
    final rawTable = rawLuaSlot(table);
    if (rawTable is Map &&
        table.globalProxyEnvironment != null &&
        table.tableWeakMode == null) {
      if (!rawTable.containsKey(rawKey)) {
        return _unhandledTableSlot;
      }
      return rawTable[rawKey];
    }
    if (rawTable is Map && _canReadPlainTable(table)) {
      return rawTable[rawKey];
    }
    return _unhandledTableSlot;
  }

  Value? _tryFastTableGet(Value table, Value key) {
    final rawTable = rawLuaSlot(table);
    if (_canFastPathGlobalProxyTableGet(table, key)) {
      final result = (rawTable as Map)[_plainTableStorageKey(key)];
      return runtimeValue(runtime, result);
    }
    // Weak tables rely on Value's normal key normalization and memory-credit
    // bookkeeping. `__mode` is not a metamethod, so keep them off the raw
    // storage fast path even when `__index`/`__newindex` are absent.
    if (rawTable is TableStorage && _canReadPlainTable(table)) {
      final result = switch (_plainPositiveIntegerKey(key)) {
        final int index => rawTable.arrayValueAt(index),
        _ => rawTable[_plainTableStorageKey(key)],
      };
      return runtimeValue(runtime, result);
    }
    if (rawTable is Map && _canReadPlainTable(table)) {
      final result = rawTable[_plainTableStorageKey(key)];
      return runtimeValue(runtime, result);
    }
    return null;
  }

  Value? _tryFastTableGetStringKey(Value table, String rawKey) {
    final rawTable = rawLuaSlot(table);
    if (rawTable is Map &&
        table.globalProxyEnvironment != null &&
        table.tableWeakMode == null) {
      final result = rawTable[rawKey];
      if (result != null || rawTable.containsKey(rawKey)) {
        return runtimeValue(runtime, result);
      }
    }
    if (rawTable is TableStorage && _canReadPlainTable(table)) {
      final result = rawTable[rawKey];
      return runtimeValue(runtime, result);
    }
    if (rawTable is Map && _canReadPlainTable(table)) {
      final result = rawTable[rawKey];
      return runtimeValue(runtime, result);
    }
    return null;
  }

  bool _canFastPathGlobalProxyTableGet(Value table, Value key) {
    final rawTable = rawLuaSlot(table);
    if (rawTable is! Map || table.globalProxyEnvironment == null) {
      return false;
    }
    if (table.tableWeakMode != null) {
      return false;
    }
    final storageKey = _plainTableStorageKey(key);
    return rawTable.containsKey(storageKey);
  }

  bool _canFastPathGlobalProxyTableGetStringKey(Value table, String rawKey) {
    final rawTable = rawLuaSlot(table);
    if (rawTable is! Map || table.globalProxyEnvironment == null) {
      return false;
    }
    if (table.tableWeakMode != null) {
      return false;
    }
    return rawTable.containsKey(rawKey);
  }

  bool _tryFastTableSetStringKey(Value table, String rawKey, Value value) {
    return _tryFastTableSetStringKeySlot(table, rawKey, value);
  }

  bool _tryFastTableSetStringKeySlot(
    Value table,
    String rawKey,
    LuaSlot value,
  ) {
    final rawTable = rawLuaSlot(table);
    final rawValue = rawLuaSlot(value);
    if (value is Value) {
      _writeBarrier(table, value);
    }
    final storedValue = _primitiveSlotForStorage(value);
    if (rawTable is TableStorage &&
        _canWritePlainTable(table) &&
        _isPlainPrimitiveValue(rawValue)) {
      if (rawValue == null) {
        rawTable.remove(rawKey);
      } else {
        rawTable[rawKey] = storedValue;
      }
      table.markTableModified();
      return true;
    }
    if (rawTable is Map &&
        _canWritePlainTable(table) &&
        _isPlainPrimitiveValue(rawValue)) {
      if (rawValue == null) {
        rawTable.remove(rawKey);
      } else {
        rawTable[rawKey] = storedValue;
      }
      table.markTableModified();
      return true;
    }
    return false;
  }

  void _writeBarrier(Value table, Value value) {
    if (table.isOld && !value.isOld) {
      runtime.gc.recordWriteBarrier(table);
    }
  }

  bool _tryFastTableSet(Value table, Value key, Value value) {
    return _tryFastTableSetSlot(table, key, value);
  }

  bool _tryFastTableSetSlot(Value table, LuaSlot key, LuaSlot value) {
    if (value is Value) {
      _writeBarrier(table, value);
    }
    final rawTable = rawLuaSlot(table);
    final rawValue = rawLuaSlot(value);
    final storedValue = _primitiveSlotForStorage(value);
    if (rawTable is TableStorage && _canWritePlainTable(table)) {
      if (_plainPositiveIntegerKey(key) case final int index) {
        if (rawValue == null) {
          rawTable.remove(index);
        } else if (_isPlainPrimitiveValue(rawValue)) {
          rawTable.setDense(index, storedValue);
        } else {
          return false;
        }
        table.markTableModified();
        return true;
      }
      if (_canFastSetPlainPrimitiveEntry(key, value)) {
        final storageKey = _plainTableStorageKey(key);
        if (rawValue == null) {
          rawTable.remove(storageKey);
        } else {
          rawTable[storageKey] = storedValue;
        }
        table.markTableModified();
        return true;
      }
      return false;
    }
    if (rawTable is Map &&
        _canWritePlainTable(table) &&
        _canFastSetPlainPrimitiveEntry(key, value)) {
      final storageKey = _plainTableStorageKey(key);
      if (rawValue == null) {
        rawTable.remove(storageKey);
      } else {
        rawTable[storageKey] = storedValue;
      }
      table.markTableModified();
      return true;
    }
    return false;
  }

  Future<void> _tableSet(Value table, Value key, Value value) async {
    if (_tryFastTableSet(table, key, value)) {
      return;
    }
    final rawTable = rawLuaSlot(table);
    if (rawTable is Map && _canWritePlainTable(table)) {
      table[key] = value;
      return;
    }
    await table.setValueAsync(key, value);
  }

  Object? _plainTableStorageKey(LuaSlot key) {
    final rawKey = rawLuaSlot(key);
    return switch (rawKey) {
      final LuaString string => string.toString(),
      final num number => number == 0 ? 0.0 : number,
      final String string => string,
      final bool boolean => boolean,
      final BigInt integer => integer,
      _ => key,
    };
  }

  int? _plainPositiveIntegerKey(LuaSlot key) {
    final rawKey = rawLuaSlot(key);
    return switch (rawKey) {
      final int integer when integer > 0 => integer,
      final num number
          when number.isFinite &&
              number.toInt() > 0 &&
              number.toInt().toDouble() == number.toDouble() =>
        number.toInt(),
      _ => null,
    };
  }

  bool _canFastSetPlainPrimitiveEntry(LuaSlot key, LuaSlot value) {
    final rawKey = rawLuaSlot(key);
    final rawValue = rawLuaSlot(value);
    return _isPlainPrimitiveKey(rawKey) && _isPlainPrimitiveValue(rawValue);
  }

  bool _isPlainPrimitiveKey(Object? raw) =>
      raw != null && isLuaPrimitiveSlot(raw);

  bool _isPlainPrimitiveValue(Object? raw) => isLuaPrimitiveSlot(raw);

  LuaSlot _primitiveSlotForStorage(LuaSlot value) {
    if (value case final Value wrapped when !wrapped.canStoreAsRawLuaSlot) {
      return wrapped;
    }
    return rawLuaSlot(value);
  }

  bool _canReadPlainTable(Value table) =>
      table.tableWeakMode == null && !table.hasMetamethod('__index');

  bool _canWritePlainTable(Value table) =>
      _canReadPlainTable(table) &&
      !Value.rawTableIsMetatable(rawLuaSlot(table)) &&
      !table.hasMetamethod('__newindex');

  LuaBytecodeInstructionWord _consumeExtraArg(LuaBytecodeFrame frame) {
    if (frame.pc >= frame.closure.prototype.code.length) {
      throw LuaError('missing EXTRAARG operand');
    }
    final extra = frame.closure.prototype.code[frame.pc++];
    if (extra.opcode != Opcode.extraArg) {
      throw LuaError('expected EXTRAARG after extending opcode');
    }
    return extra;
  }

  LuaBytecodeInstructionWord? _consumeOptionalZeroExtraArg(
    LuaBytecodeFrame frame,
  ) {
    if (frame.pc >= frame.closure.prototype.code.length) {
      return null;
    }
    final next = frame.closure.prototype.code[frame.pc];
    if (next.opcode == Opcode.extraArg && next.ax == 0) {
      frame.pc++;
      return next;
    }
    return null;
  }
}
