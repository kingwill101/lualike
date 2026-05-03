/// Internal carrier for Lua multi-result values.
///
/// Public APIs still expose multi-results as `Value.multi(...)`. This type is
/// the lighter runtime shape that internal call paths can move toward without
/// changing that public contract.
final class LuaResults {
  LuaResults(Iterable<Object?> values)
    : _values = values is List<Object?>
          ? values
          : List<Object?>.of(values, growable: false);

  const LuaResults.empty() : _values = const <Object?>[];

  final List<Object?> _values;

  List<Object?> get values => _values;

  int get length => _values.length;

  bool get isEmpty => _values.isEmpty;

  bool get isNotEmpty => _values.isNotEmpty;

  Object? get firstOrNull => _values.isEmpty ? null : _values.first;

  Object? operator [](int index) => _values[index];

  @override
  String toString() => 'LuaResults($_values)';
}
