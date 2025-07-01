import 'package:lualike/src/pattern_parser.dart';
import 'package:lualike/testing.dart';

void main() {
  final parser = LuaPatternParser();

  test('parse simple class with quantifier', () {
    final tokens = parser.parse('%d+');
    expect(tokens.length, 1);
    final t = tokens.first as QuantifiedToken;
    expect(t.quantifier, '+');
    expect(t.inner is SimpleClassToken, true);
  });

  test('parse balanced pattern', () {
    final tokens = parser.parse('%b()');
    expect(tokens.length, 1);
    expect(tokens.first is BalancedToken, true);
  });

  test('parse capture with literal', () {
    final tokens = parser.parse('(%a+)%d');
    expect(tokens.length, 2);
    expect(tokens.first is CaptureToken, true);
    expect(tokens[1] is SimpleClassToken, true);
  });
}
