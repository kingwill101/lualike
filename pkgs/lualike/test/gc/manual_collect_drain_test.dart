import 'package:lualike/lualike.dart';
import 'package:lualike/src/stdlib/lib_base.dart';
import 'package:test/test.dart';

void main() {
  Logger.setEnabled(false);

  group('collectgarbage manual collect semantics', () {
    test(
      'collectgarbage("collect") drains active incremental cycle',
      () async {
        final interpreter = Interpreter();
        final gc = interpreter.gc;

        // Create enough allocations to start an incremental cycle.
        final allocations = <Value>[];
        for (var i = 0; i < 128; i++) {
          final entry = Value({'idx': Value(i), 'mirror': Value(i * 2)});
          allocations.add(entry);
        }

        // Trigger the incremental collector so it enters a non-idle phase.
        var iterations = 0;
        while (!gc.isCycleActive && iterations < 16) {
          gc.performIncrementalStep(4);
          iterations++;
        }
        expect(gc.isCycleActive, isTrue);

        final collectFn = CollectGarbageFunction(interpreter);
        final result = await collectFn.call([]);
        expect(result, isA<Value>());
        expect((result as Value).raw, isTrue);
        expect(gc.isCycleActive, isFalse);
        expect(gc.isManualCollectRunning, isFalse);

        // Keep allocations referenced until after collection completes.
        allocations.clear();
      },
    );
  });
}
