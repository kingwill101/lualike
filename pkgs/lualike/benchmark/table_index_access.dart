import 'dart:convert';

import 'package:lualike/lualike.dart';

double _median(List<int> samples) {
  final sorted = samples.toList()..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[middle].toDouble();
  }
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

Future<void> main(List<String> arguments) async {
  final iterations = arguments.isNotEmpty ? int.parse(arguments[0]) : 20000;
  final trialCount = arguments.length > 1 ? int.parse(arguments[1]) : 7;
  if (iterations <= 0 || trialCount <= 0) {
    throw ArgumentError('iterations and trial count must be positive');
  }

  final elapsedSamples = <int>[];
  Object? expectedChecksum;

  for (var trial = 0; trial < trialCount; trial++) {
    final lua = LuaLike();
    final stopwatch = Stopwatch()..start();
    final result = await lua.execute('''
      local values = {7}
      local checksum = 0
      for i = 1, $iterations do
        checksum = checksum + values[1]
      end
      return checksum
    ''');
    stopwatch.stop();

    final checksum = result is Value ? result.unwrap() : result;
    expectedChecksum ??= checksum;
    if (checksum != expectedChecksum) {
      throw StateError(
        'trial $trial produced $checksum instead of $expectedChecksum',
      );
    }
    elapsedSamples.add(stopwatch.elapsedMicroseconds);
  }

  print(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'iterationsPerTrial': iterations,
      'trialCount': trialCount,
      'checksum': expectedChecksum,
      'elapsedMicros': elapsedSamples,
      'medianElapsedMicros': _median(elapsedSamples),
    }),
  );
}
