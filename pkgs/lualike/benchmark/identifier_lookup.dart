import 'dart:convert';

import 'package:lualike/lualike.dart';

@pragma('vm:never-inline')
CallFrame? _legacyLookup(CallStack stack, Value callable) {
  for (final frame in stack.frames.toList().reversed) {
    if (identical(frame.callable, callable)) {
      return frame;
    }
  }
  return null;
}

@pragma('vm:never-inline')
CallFrame? _optimizedLookup(CallStack stack, Value callable) =>
    stack.findLatestFrameForCallable(callable);

({int micros, int checksum}) _measure(
  CallFrame? Function(CallStack, Value) lookup,
  CallStack stack,
  Value callable,
  int iterations,
) {
  var checksum = 0;
  final stopwatch = Stopwatch()..start();
  for (var iteration = 0; iteration < iterations; iteration++) {
    checksum ^= identityHashCode(lookup(stack, callable));
  }
  stopwatch.stop();
  return (micros: stopwatch.elapsedMicroseconds, checksum: checksum);
}

double _median(List<int> samples) {
  final sorted = samples.toList()..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[middle].toDouble();
  }
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

void main(List<String> arguments) {
  final iterations = arguments.isNotEmpty ? int.parse(arguments[0]) : 250000;
  final trialCount = arguments.length > 1 ? int.parse(arguments[1]) : 9;
  if (iterations <= 0 || trialCount <= 0) {
    throw ArgumentError('iterations and trial count must be positive');
  }

  final stack = CallStack();
  final callables = List<Value>.generate(
    8,
    (_) => Value(<Object?, Object?>{}),
    growable: false,
  );
  for (var index = 0; index < callables.length; index++) {
    stack.push('frame$index', callable: callables[index]);
  }
  final target = callables[2];
  final expected = _legacyLookup(stack, target);
  if (expected == null ||
      !identical(expected, _optimizedLookup(stack, target))) {
    throw StateError('lookup implementations selected different frames');
  }

  _measure(_legacyLookup, stack, target, 10000);
  _measure(_optimizedLookup, stack, target, 10000);

  final legacySamples = <int>[];
  final optimizedSamples = <int>[];
  for (var trial = 0; trial < trialCount; trial++) {
    final measurements = trial.isEven
        ? <CallFrame? Function(CallStack, Value)>[
            _legacyLookup,
            _optimizedLookup,
          ]
        : <CallFrame? Function(CallStack, Value)>[
            _optimizedLookup,
            _legacyLookup,
          ];
    for (final lookup in measurements) {
      final result = _measure(lookup, stack, target, iterations);
      if (result.checksum != 0 && iterations.isEven) {
        throw StateError('unexpected lookup checksum ${result.checksum}');
      }
      if (identical(lookup, _legacyLookup)) {
        legacySamples.add(result.micros);
      } else {
        optimizedSamples.add(result.micros);
      }
    }
  }

  final legacyMedian = _median(legacySamples);
  final optimizedMedian = _median(optimizedSamples);
  print(
    jsonEncode(<String, Object>{
      'schemaVersion': 1,
      'iterationsPerTrial': iterations,
      'trialCount': trialCount,
      'stackDepth': stack.depth,
      'legacySamplesMicros': legacySamples,
      'optimizedSamplesMicros': optimizedSamples,
      'legacyMedianMicros': legacyMedian,
      'optimizedMedianMicros': optimizedMedian,
      'medianReductionPercent':
          (legacyMedian - optimizedMedian) / legacyMedian * 100,
    }),
  );
}
