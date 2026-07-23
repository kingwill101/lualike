@Tags(['ir'])
library;

import 'package:lualike/ir.dart';
import 'package:test/test.dart';

void main() {
  test('exports the SSA formatter', () {
    final builder = LualikeIrPrototypeBuilder(registerCount: 1);
    builder.addInstruction(
      const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 0, b: 0, c: 0),
    );
    builder.addInstruction(
      const ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
    );

    final ssa = LualikeIrSsaFunction.fromPrototype(builder.build());
    expect(formatLualikeIrSsaFunction(ssa), contains('ssa {'));
  });
}
