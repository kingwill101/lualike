import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/memory_credits.dart';
import 'package:test/test.dart';

void main() {
  test('late-tracked transient values remain excluded from memory use', () {
    final interpreter = Interpreter();
    final gc = interpreter.gc..stop();
    final before = gc.estimateMemoryUse();
    final scalar = Value.primitive(42, skipGcRegistration: true);
    final transientString = Value.primitive(
      'temporary',
      skipAllocationDebt: true,
      skipGcRegistration: true,
    );

    gc.ensureTracked(scalar);
    gc.ensureTracked(transientString);

    expect(gc.estimateMemoryUse(), before);
    expect(scalar.gcSpace, GCGenerationSpace.young);
    expect(transientString.gcSpace, GCGenerationSpace.young);
  });
}
