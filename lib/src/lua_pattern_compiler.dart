// Library implementing Lua pattern parsing using PetitParser.
// This is experimental and not yet integrated with the interpreter.

library;

import 'package:petitparser/petitparser.dart';

Parser<String> _predicate(bool Function(int) test) =>
    any().where((c) => test(c.codeUnitAt(0)));

final _letter = _predicate(
  (c) => (c >= 65 && c <= 90) || (c >= 97 && c <= 122),
);
final _lower = _predicate((c) => c >= 97 && c <= 122);
final _upper = _predicate((c) => c >= 65 && c <= 90);
final _digit = digit();
final _xdigit = pattern('0-9A-Fa-f');
final _space = whitespace();
final _punct = pattern('!-/:-@\\[-`{-~');
final _control = _predicate((c) => c < 32 || c == 127);
final _graph = pattern('!-~');
final _alnum = pattern('0-9A-Za-z');

Parser<String> _classFor(String letter) {
  switch (letter) {
    case 'a':
      return _letter;
    case 'c':
      return _control;
    case 'd':
      return _digit;
    case 'g':
      return _graph;
    case 'l':
      return _lower;
    case 'p':
      return _punct;
    case 's':
      return _space;
    case 'u':
      return _upper;
    case 'w':
      return _alnum;
    case 'x':
      return _xdigit;
    default:
      throw ArgumentError('Unknown %\$letter class');
  }
}

Parser<String> _negate(Parser<String> p) => p.neg();

/// Parser that matches a balanced pair like `%bxy` in Lua.
class _BalancedParser extends Parser<String> {
  final String open;
  final String close;
  _BalancedParser(this.open, this.close);

  @override
  Result<String> parseOn(Context context) {
    final buffer = context.buffer;
    var pos = context.position;
    if (pos >= buffer.length || buffer[pos] != open) {
      return context.failure('Expected $open');
    }
    var depth = 1;
    pos++;
    while (pos < buffer.length) {
      final ch = buffer[pos];
      if (ch == open) {
        depth++;
      } else if (ch == close) {
        depth--;
        if (depth == 0) {
          return context.success(
            buffer.substring(context.position, pos + 1),
            pos + 1,
          );
        }
      }
      pos++;
    }
    return context.failure('Unbalanced $open$close');
  }

  @override
  int fastParseOn(String buffer, int position) {
    final result = parseOn(Context(buffer, position));
    return result is Failure ? -1 : result.position;
  }

  @override
  _BalancedParser copy() => _BalancedParser(open, close);
}

Parser<String> _bracketClass(String spec, {required bool negate}) {
  final allowed = <Parser<String>>[];
  var i = 0;
  while (i < spec.length) {
    final ch = spec[i];
    if (ch == '%') {
      if (i + 1 >= spec.length) {
        throw FormatException('Malformed set: \$spec');
      }
      final cls = _classFor(spec[i + 1]);
      allowed.add(cls);
      i += 2;
      continue;
    }
    if (i + 2 < spec.length && spec[i + 1] == '-') {
      final start = spec.codeUnitAt(i);
      final end = spec.codeUnitAt(i + 2);
      allowed.add(
        pattern('${String.fromCharCode(start)}-${String.fromCharCode(end)}'),
      );
      i += 3;
      continue;
    }
    allowed.add(char(ch));
    i += 1;
  }
  final union = allowed.length == 1 ? allowed.single : ChoiceParser(allowed);
  return negate ? _negate(union) : union;
}

class LuaPatternCompiler {
  LuaPatternCompiler(this._pattern);

  final String _pattern;
  int _pos = 0;
  final List<Parser> _captures = [];

  Parser<String> compile() {
    if (_pattern.startsWith('^') && !_isEscaped(0)) {
      _pos = 1;
    }
    var seq = _parseSequence();
    if (_pattern.endsWith('\$') && !_isEscaped(_pattern.length - 1)) {
      seq = seq.end();
    }
    return seq.flatten();
  }

  bool _isEscaped(int index) =>
      index > 0 && _pattern[index - 1] == '%' && !_isEscaped(index - 1);

  Parser _parseSequence({bool stopOnRightParen = false}) {
    final elements = <Parser>[];
    while (_pos < _pattern.length) {
      final p = _parseItem(stopOnRightParen);
      if (p == null) break;
      elements.add(p);
    }
    return elements.length == 1 ? elements.single : SequenceParser(elements);
  }

  Parser? _parseItem(bool stopOnRightParen) {
    if (_pos >= _pattern.length) return null;
    final ch = _pattern[_pos];

    if (stopOnRightParen && ch == ')') {
      return null;
    }
    if (ch == '\$' && _pos == _pattern.length - 1 && !_isEscaped(_pos)) {
      _pos++;
      return null;
    }

    late Parser item;
    if (ch == '(') {
      item = _parseCapture();
    } else if (ch == '[') {
      item = _parseBracket();
    } else if (ch == '.') {
      item = any();
      _pos++;
    } else if (ch == '%') {
      item = _parsePercent();
    } else {
      item = char(ch);
      _pos++;
    }

    if (_pos < _pattern.length) {
      final rep = _pattern[_pos];
      if ('*+-?'.contains(rep)) {
        item = _applyRepetition(item, rep, stopOnRightParen);
        _pos++;
      }
    }
    return item;
  }

  Parser _applyRepetition(Parser base, String op, bool stopOnRightParen) {
    switch (op) {
      case '*':
        return base.star();
      case '+':
        return base.plus();
      case '?':
        return base.optional();
      case '-':
        final following = _parseSequence(stopOnRightParen: stopOnRightParen);
        return base.starLazy(following).seq(following);
      default:
        throw StateError('Unhandled repetition \$op');
    }
  }

  Parser _parsePercent() {
    assert(_pattern[_pos] == '%');
    _pos++;
    if (_pos >= _pattern.length) {
      throw FormatException('Trailing % in pattern');
    }
    final next = _pattern[_pos];

    if ('123456789'.contains(next)) {
      throw UnimplementedError('%n back-reference not implemented');
    }
    if (next == 'b') {
      if (_pos + 2 >= _pattern.length) {
        throw FormatException('Malformed %b sequence');
      }
      final open = _pattern[_pos + 1];
      final close = _pattern[_pos + 2];
      _pos += 3;
      return _BalancedParser(open, close);
    }
    if (next == 'f') {
      throw UnimplementedError('%f[set] frontier match not implemented');
    }
    if (RegExp(r'[a-zA-Z]').hasMatch(next)) {
      _pos++;
      final base = _classFor(next.toLowerCase());
      final parser = next == next.toUpperCase() ? _negate(base) : base;
      return parser;
    }
    _pos++;
    return char(next);
  }

  Parser _parseBracket() {
    assert(_pattern[_pos] == '[');
    final start = _pos;
    _pos++;
    var negate = false;
    if (_pattern[_pos] == '^') {
      negate = true;
      _pos++;
    }
    final buffer = StringBuffer();
    while (_pos < _pattern.length && _pattern[_pos] != ']') {
      buffer.write(_pattern[_pos]);
      _pos++;
    }
    if (_pos >= _pattern.length) {
      throw FormatException('Unclosed character class in pattern at $start');
    }
    _pos++;
    return _bracketClass(buffer.toString(), negate: negate);
  }

  Parser _parseCapture() {
    assert(_pattern[_pos] == '(');
    _pos++;
    if (_pattern[_pos] == ')') {
      _pos++;
      return epsilon();
    }
    final inner = _parseSequence(stopOnRightParen: true);
    if (_pos >= _pattern.length || _pattern[_pos] != ')') {
      throw FormatException('Unclosed ( in pattern');
    }
    _pos++;
    final capture = inner.flatten();
    _captures.add(capture);
    return capture;
  }
}

Parser<String> compileLuaPattern(String pattern) =>
    LuaPatternCompiler(pattern).compile();
