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

void main(List<String> arguments) {
  final uniqueValues = arguments.isNotEmpty ? int.parse(arguments[0]) : 100000;
  final trialCount = arguments.length > 1 ? int.parse(arguments[1]) : 7;
  if (uniqueValues <= 0 || trialCount <= 0) {
    throw ArgumentError('unique value and trial counts must be positive');
  }

  final elapsedSamples = <int>[];
  Map<String, Object>? diagnostics;
  var checksum = 0;
  for (var trial = 0; trial < trialCount; trial++) {
    final interpreter = Interpreter();
    final stopwatch = Stopwatch()..start();
    for (var index = 0; index < uniqueValues; index++) {
      final wrapped = interpreter.constantPrimitiveValue(index + 0.25);
      checksum ^= identityHashCode(wrapped);
    }
    stopwatch.stop();
    elapsedSamples.add(stopwatch.elapsedMicroseconds);
    diagnostics = interpreter.numericPrimitiveCacheDiagnostics();

    final latest = interpreter.constantPrimitiveValue(uniqueValues - 0.75);
    if (!identical(
      latest,
      interpreter.constantPrimitiveValue(uniqueValues - 0.75),
    )) {
      throw StateError('most recent numeric wrapper was not retained');
    }
  }

  print(
    jsonEncode(<String, Object>{
      'schemaVersion': 1,
      'uniqueValuesPerTrial': uniqueValues,
      'trialCount': trialCount,
      'checksum': checksum,
      'elapsedMicros': elapsedSamples,
      'medianElapsedMicros': _median(elapsedSamples),
      'cache': diagnostics!,
    }),
  );
}
