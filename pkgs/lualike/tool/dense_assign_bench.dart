import 'dart:math';

import 'package:lualike/src/table_storage.dart';
import 'package:lualike/src/value.dart';

void main() {
  const limit = 50000;
  final random = Random(1234);

  final tableValue = Value(TableStorage());

  final sw = Stopwatch()..start();
  for (var i = 1; i <= limit; i++) {
    tableValue.setNumericIndex(i, Value(random.nextDouble()));
  }
  sw.stop();

  print('dense set time: ${sw.elapsedMilliseconds} ms');
}
