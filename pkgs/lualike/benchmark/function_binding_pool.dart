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
  final trialCount = arguments.length > 1 ? int.parse(arguments[1]) : 5;
  if (iterations <= 0 || trialCount <= 0) {
    throw ArgumentError('iterations and trial count must be positive');
  }

  final elapsedSamples = <int>[];
  final createdSamples = <int>[];
  final reusedSamples = <int>[];
  final localFrameCreatedSamples = <int>[];
  final localFrameReusedSamples = <int>[];
  final localFrameCacheHitSamples = <int>[];
  final localFrameNameLookupSamples = <int>[];
  Object? expectedChecksum;

  for (var trial = 0; trial < trialCount; trial++) {
    final lua = LuaLike();
    Box.resetBindingDiagnostics();
    Interpreter.resetAstLocalFrameDiagnostics();
    final stopwatch = Stopwatch()..start();
    final result = await lua.execute('''
      local function adjusted(value, low, high)
        local result = value + 1
        if result < low then return low end
        if result > high then return high end
        return result
      end

      local checksum = 0
      for i = 1, $iterations do
        checksum = checksum + adjusted(i % 100, 5, 95)
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
    final localFrameDiagnostics = Interpreter.astLocalFrameDiagnostics();
    elapsedSamples.add(stopwatch.elapsedMicroseconds);
    createdSamples.add(diagnostics['created']! as int);
    reusedSamples.add(diagnostics['reused']! as int);
    localFrameCreatedSamples.add(localFrameDiagnostics['created']! as int);
    localFrameReusedSamples.add(localFrameDiagnostics['reused']! as int);
    localFrameCacheHitSamples.add(localFrameDiagnostics['cacheHits']! as int);
    localFrameNameLookupSamples.add(
      localFrameDiagnostics['nameLookups']! as int,
    );
  }

  print(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'bindingPoolEnabled': const bool.fromEnvironment(
        'LUALIKE_FUNCTION_BINDING_POOL',
        defaultValue: true,
      ),
      'bindingDiagnosticsEnabled': Box.bindingDiagnosticsEnabled,
      'indexedLocalFrameEnabled': const bool.fromEnvironment(
        'LUALIKE_AST_INDEXED_LOCAL_FRAME',
        defaultValue: true,
      ),
      'iterationsPerTrial': iterations,
      'trialCount': trialCount,
      'checksum': expectedChecksum,
      'elapsedMicros': elapsedSamples,
      'medianElapsedMicros': _median(elapsedSamples),
      'createdBoxes': createdSamples,
      'medianCreatedBoxes': _median(createdSamples),
      'reusedBindings': reusedSamples,
      'medianReusedBindings': _median(reusedSamples),
      'localFramesCreated': localFrameCreatedSamples,
      'medianLocalFramesCreated': _median(localFrameCreatedSamples),
      'localFramesReused': localFrameReusedSamples,
      'medianLocalFramesReused': _median(localFrameReusedSamples),
      'localFrameCacheHits': localFrameCacheHitSamples,
      'medianLocalFrameCacheHits': _median(localFrameCacheHitSamples),
      'localFrameNameLookups': localFrameNameLookupSamples,
      'medianLocalFrameNameLookups': _median(localFrameNameLookupSamples),
    }),
  );
}
