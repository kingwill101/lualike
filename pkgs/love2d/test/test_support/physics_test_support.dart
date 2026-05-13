import 'package:flutter_test/flutter_test.dart';

List<Object?> indexedValues(Map table) {
  final keys = table.keys.whereType<num>().map((key) => key.toInt()).toList()
    ..sort();
  return keys.map((key) => table[key]).toList(growable: false);
}

List<double> doubleTable(Map table) {
  return indexedValues(
    table,
  ).map((entry) => (entry as num).toDouble()).toList(growable: false);
}

List<double> doubleResults(Object? value) {
  if (value is Map) {
    return doubleTable(value);
  }
  return (value as List<Object?>)
      .map((entry) => (entry as num).toDouble())
      .toList(growable: false);
}

void expectDoubleListClose(
  Object? value,
  List<double> expected, [
  double epsilon = 1e-5,
]) {
  final actual = doubleResults(value);
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    expect(
      actual[i],
      closeTo(expected[i], epsilon),
      reason: 'Unexpected value at index $i',
    );
  }
}

void expectPointSetClose(
  Object? value,
  List<({double x, double y})> expected, [
  double epsilon = 1e-5,
]) {
  final actualValues = doubleResults(value);
  expect(actualValues.length, expected.length * 2);

  final actualPoints = <({double x, double y})>[];
  for (var i = 0; i < actualValues.length; i += 2) {
    actualPoints.add((x: actualValues[i], y: actualValues[i + 1]));
  }

  for (final expectedPoint in expected) {
    expect(
      actualPoints.any(
        (actualPoint) =>
            (actualPoint.x - expectedPoint.x).abs() <= epsilon &&
            (actualPoint.y - expectedPoint.y).abs() <= epsilon,
      ),
      isTrue,
      reason: 'Missing point (${expectedPoint.x}, ${expectedPoint.y})',
    );
  }
}
