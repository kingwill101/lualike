import 'dart:math' as math;

import 'package:lualike/src/number_utils.dart';

typedef BenchFn = void Function();

void main() {
  const warmupIters = 100000;
  const benchIters = 1000000;

  final benches = <String, BenchFn>{
    'add_int': () => _benchBinary('+', 1, 2, benchIters),
    'add_double': () => _benchBinary('+', 1.5, 2.5, benchIters),
    'bitwise_and': () => _benchBinary('&', 0xFFFF0000, 0x0000FFFF, benchIters),
    'bitwise_or': () => _benchBinary('|', 0xFFFF0000, 0x0000FFFF, benchIters),
    'bitwise_xor': () =>
        _benchBinary('bxor', 0xFFFF0000, 0x0000FFFF, benchIters),
    'shift_left': () => _benchBinary('<<', 0x12345678, 3, benchIters),
    'shift_right': () => _benchBinary('>>', 0x12345678, 3, benchIters),
    'multiply': () => _benchBinary('*', 12345, 6789, benchIters),
    'divide': () => _benchBinary('/', 1234567, 3, benchIters),
    'floor_divide': () => _benchBinary('//', 1234567, 3, benchIters),
    'modulo': () => _benchBinary('%', 123456789, 97, benchIters),
    'power': () => _benchBinary('^', 1.0001, 3.0, warmupIters),
    'string_parse': () => _benchBinary('+', '12345', '67890', warmupIters),
  };

  for (var bench in benches.values) {
    bench();
  }

  for (final entry in benches.entries) {
    final stopwatch = Stopwatch()..start();
    entry.value();
    stopwatch.stop();
    final totalIters = entry.key == 'power' || entry.key == 'string_parse'
        ? warmupIters
        : benchIters;
    final elapsedMs = stopwatch.elapsedMilliseconds.clamp(1, 1 << 30);
    final throughput = totalIters / elapsedMs;
    print(
      '${entry.key.padRight(14)} -> ${stopwatch.elapsedMilliseconds} ms '
      '(~${throughput.toStringAsFixed(1)} iters/ms)',
    );
  }
}

void _benchBinary(String op, dynamic left, dynamic right, int iterations) {
  dynamic acc = left;
  for (var i = 0; i < iterations; i++) {
    acc = NumberUtils.performArithmetic(op, acc, right);
    if (op == '^') {
      acc = (acc as double) % math.pi;
    } else if (acc is int || acc is double || acc is BigInt) {
      continue;
    } else if (acc is num) {
      acc = acc;
    }
  }
}
