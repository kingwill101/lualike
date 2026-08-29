import 'dart:convert';

import 'package:lualike/lualike.dart';

double _median(List<int> samples) {
  final sorted = samples.toList()..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle].toDouble();
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

Future<void> main(List<String> arguments) async {
  final iterations = arguments.isNotEmpty ? int.parse(arguments[0]) : 20000;
  final trialCount = arguments.length > 1 ? int.parse(arguments[1]) : 5;
  if (iterations <= 0 || trialCount <= 0) {
    throw ArgumentError('iterations and trial count must be positive');
  }

  final elapsedSamples = <int>[];
  final createdSamples = <int>[];
  final reusedSamples = <int>[];
  Object? expectedChecksum;

  for (var trial = 0; trial < trialCount; trial++) {
    final lua = LuaLike();
    Box.resetBindingDiagnostics();
    final stopwatch = Stopwatch()..start();
    final result = await lua.execute('''
      local cursor = 0
      local offset = -3
      local function sample()
        local magnitude = math.abs((cursor % 97) + offset)
        cursor = cursor + 1
        return magnitude
      end

      local checksum = 0
      for i = 1, $iterations do
        checksum = checksum + sample()
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
    final diagnostics = Box.bindingDiagnostics();
    elapsedSamples.add(stopwatch.elapsedMicroseconds);
    createdSamples.add(diagnostics['created']! as int);
    reusedSamples.add(diagnostics['reused']! as int);
  }

  print(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'bindingPoolEnabled': const bool.fromEnvironment(
        'LUALIKE_FUNCTION_BINDING_POOL',
        defaultValue: true,
      ),
      'bindingDiagnosticsEnabled': Box.bindingDiagnosticsEnabled,
      'iterationsPerTrial': iterations,
      'trialCount': trialCount,
      'checksum': expectedChecksum,
      'elapsedMicros': elapsedSamples,
      'medianElapsedMicros': _median(elapsedSamples),
      'createdBoxes': createdSamples,
      'medianCreatedBoxes': _median(createdSamples),
      'reusedBindings': reusedSamples,
      'medianReusedBindings': _median(reusedSamples),
    }),
  );
}
