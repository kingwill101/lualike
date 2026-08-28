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

({int micros, int checksum}) _measure(Environment environment, int iterations) {
  var checksum = 0;
  final stopwatch = Stopwatch()..start();
  for (var iteration = 0; iteration < iterations; iteration++) {
    checksum += environment.get('localValue') as int;
    checksum += environment.get('parentValue') as int;
  }
  stopwatch.stop();
  return (micros: stopwatch.elapsedMicroseconds, checksum: checksum);
}

void main(List<String> arguments) {
  final iterations = arguments.isNotEmpty ? int.parse(arguments[0]) : 500000;
  final trialCount = arguments.length > 1 ? int.parse(arguments[1]) : 9;
  if (iterations <= 0 || trialCount <= 0) {
    throw ArgumentError('iterations and trial count must be positive');
  }

  final parent = Environment()..values['parentValue'] = Box<int>(7);
  final environment = Environment(parent: parent)
    ..values['localValue'] = Box<int>(3);
  final expectedChecksum = iterations * 10;

  _measure(environment, 10000);
  final elapsedSamples = <int>[];
  for (var trial = 0; trial < trialCount; trial++) {
    final result = _measure(environment, iterations);
    if (result.checksum != expectedChecksum) {
      throw StateError(
        'trial $trial produced ${result.checksum} instead of $expectedChecksum',
      );
    }
    elapsedSamples.add(result.micros);
  }

  print(
    jsonEncode(<String, Object>{
      'schemaVersion': 1,
      'lookupsPerTrial': iterations * 2,
      'trialCount': trialCount,
      'checksum': expectedChecksum,
      'elapsedMicros': elapsedSamples,
      'medianElapsedMicros': _median(elapsedSamples),
    }),
  );
}
