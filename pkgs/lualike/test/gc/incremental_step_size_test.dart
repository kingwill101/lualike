import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  Logger.setEnabled(false);

  group('Incremental step respects size', () {
    int runIncrementalCycle(int stepSize, {int objectCount = 400}) {
      final interpreter = Interpreter();
      final gc = interpreter.gc;

      gc.stop();

      final allocations = <Value>[];
      for (var i = 0; i < objectCount; i++) {
        allocations.add(Value({'index': Value(i), 'mirror': Value(i * 2)}));
      }

      allocations.clear();

      var steps = 0;
      var completed = false;
      while (!completed && steps < 2000) {
        steps++;
        completed = gc.performIncrementalStep(stepSize);
      }

      gc.start();

      return steps;
    }

    test('larger step size completes in fewer iterations', () {
      final smallStepIterations = runIncrementalCycle(2);
      final largeStepIterations = runIncrementalCycle(10);

      expect(largeStepIterations, lessThan(smallStepIterations));
    });
  });
}
