@Tags(['bytecode'])
library;

import 'package:lualike/bytecode.dart';
import 'package:lualike_test/test.dart' as lualike;
import 'package:test/test.dart';

void main() {
  group('BytecodeValue', () {
    test('basic value construction', () {
      expect(const Value.nil().type, equals(ValueType.nil));
      expect(Value.number(42).type, equals(ValueType.number));
      expect(Value.boolean(true).type, equals(ValueType.boolean));
      expect(Value.string("test").type, equals(ValueType.string));
      expect(Value.table({}).type, equals(ValueType.table));
    });

    test('value comparison', () {
      expect(Value.number(42) == Value.number(42), isTrue);
      expect(Value.string("a") == Value.string("a"), isTrue);
      expect(Value.nil() == Value.nil(), isTrue);
      expect(Value.number(42) == Value.number(43), isFalse);
    });

    test('value conversion from/to LuaLike', () {
      final original = lualike.Value({
        'x': lualike.Value(42),
        'y': lualike.Value("test"),
      });

      final converted = Value.fromLuaLike(original);
      expect(converted.type, equals(ValueType.table));

      final table = converted.raw as Map<Value, Value>;
      expect(table[Value.string('x')], equals(Value.number(42)));
      expect(table[Value.string('y')], equals(Value.string("test")));

      final backConverted = converted.toLuaLike();
      expect(backConverted.raw['x'].raw, equals(42));
      expect(backConverted.raw['y'].raw, equals("test"));
    });

    test('table operations', () {
      final table = Value.table({});
      table.raw[Value.string("key")] = Value.number(42);

      expect((table.raw as Map)[Value.string("key")], equals(Value.number(42)));
    });

    test('closure and upvalue handling', () {
      final chunk = BytecodeChunk(
        instructions: [],
        constants: [],
        numRegisters: 1,
        name: 'test',
      );

      final upvalue = Upvalue(0);
      final closure = Closure(chunk, [upvalue]);

      final closureVal = Value.closure(closure);
      expect(closureVal.type, equals(ValueType.closure));
      expect((closureVal.raw as Closure).chunk, equals(chunk));
      expect((closureVal.raw as Closure).upvalues.first, equals(upvalue));
    });
  });
}
