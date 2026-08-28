import 'dart:convert';

import 'package:lualike/lualike.dart';

double _median(List<int> samples) {
  final sorted = List<int>.from(samples)..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle].toDouble()
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

Future<void> main(List<String> arguments) async {
  final iterations = arguments.isEmpty ? 1200 : int.parse(arguments.first);
  final sampleCount = arguments.length < 2 ? 7 : int.parse(arguments[1]);
  final elapsedSamples = <int>[];
  final boxSamples = <int>[];
  final parameterBindSamples = <int>[];
  final localBindSamples = <int>[];
  Object? checksum;

  for (var sample = 0; sample < sampleCount + 1; sample++) {
    final lua = LuaLike();
    Box.resetBindingDiagnostics();
    Interpreter.resetAstLocalFrameDiagnostics();
    final stopwatch = Stopwatch()..start();
    final result = await lua.execute('''
      local function transform(seed)
        local captured = seed % 17
        local function bias(value)
          return value + captured
        end

        local total = 0
        for i = 1, 16 do
          local scaled = seed * i
          total = total + bias(scaled)
        end
        return total
      end

      local checksum = 0
      for i = 1, $iterations do
        checksum = checksum + transform(i % 100)
      end
      return checksum
    ''');
    stopwatch.stop();

    final rawChecksum = result.unwrap();
    checksum ??= rawChecksum;
    if (rawChecksum != checksum) {
      throw StateError('unexpected checksum: $rawChecksum != $checksum');
    }
    if (sample == 0) continue;

    elapsedSamples.add(stopwatch.elapsedMicroseconds);
    boxSamples.add(Box.bindingDiagnostics()['created']! as int);
    final diagnostics = Interpreter.astLocalFrameDiagnostics();
    parameterBindSamples.add(diagnostics['slotOnlyParameterBinds']! as int);
    localBindSamples.add(diagnostics['slotOnlyLocalBinds']! as int);
  }

  print(
    jsonEncode(<String, Object?>{
      'iterations': iterations,
      'samples': sampleCount,
      'checksum': checksum,
      'medianElapsedMicros': _median(elapsedSamples),
      'medianCreatedBoxes': _median(boxSamples),
      'medianSlotOnlyParameterBinds': _median(parameterBindSamples),
      'medianSlotOnlyLocalBinds': _median(localBindSamples),
      'slotOnlyUncapturedClosureBindingsEnabled': const bool.fromEnvironment(
        'LUALIKE_AST_SLOT_ONLY_UNCAPTURED_CLOSURE_BINDINGS',
        defaultValue: true,
      ),
    }),
  );
}
