@Tags(['ir'])
library;

import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  test('main library exports the IR toolset', () {
    final builder = LualikeIrPrototypeBuilder(registerCount: 1);
    builder.addInstruction(
      const ABCInstruction(opcode: LualikeIrOpcode.loadI, a: 0, b: 0, c: 0),
    );
    builder.addInstruction(
      const ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
    );

    final ssa = buildLualikeIrSsaFunction(builder.build());
    expect(formatLualikeIrSsaFunction(ssa), contains('ssa {'));
  });
}
