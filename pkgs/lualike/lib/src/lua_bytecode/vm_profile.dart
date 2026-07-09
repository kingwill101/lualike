final class LuaBytecodeProfileEntry {
  int count = 0;
  int micros = 0;
}

final class LuaBytecodeProfile {
  LuaBytecodeProfile({required this.label});

  final String label;
  final Stopwatch wall = Stopwatch()..start();
  int totalInstructions = 0;
  final Map<String, LuaBytecodeProfileEntry> entries =
      <String, LuaBytecodeProfileEntry>{};
  final Map<String, int> callTargets = <String, int>{};

  void record(String opcodeName, int micros) {
    totalInstructions++;
    final entry = entries.putIfAbsent(opcodeName, LuaBytecodeProfileEntry.new);
    entry.count++;
    entry.micros += micros;
  }

  void recordCallTarget(String label) {
    callTargets.update(label, (count) => count + 1, ifAbsent: () => 1);
  }

  void printSummary() {
    wall.stop();
    final sorted = entries.entries.toList()
      ..sort((a, b) => b.value.micros.compareTo(a.value.micros));
    final top = sorted.take(12);
    final totalMicros = entries.values.fold<int>(
      0,
      (sum, entry) => sum + entry.micros,
    );
    print('--- $label profile ---');
    print('instructions=$totalInstructions wall=${wall.elapsedMicroseconds}us');
    for (final entry in top) {
      final percent = totalMicros == 0
          ? 0.0
          : (entry.value.micros / totalMicros) * 100.0;
      print(
        '  ${entry.key}: ${entry.value.micros}us '
        '(${entry.value.count}x, ${percent.toStringAsFixed(1)}%)',
      );
    }
    if (callTargets.isNotEmpty) {
      final targets = callTargets.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final preview = targets.take(8).map((entry) => '${entry.key}=${entry.value}');
      print('  callTargets: ${preview.join(', ')}');
    }
  }
}
