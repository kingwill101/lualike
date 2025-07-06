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

/// Parser that matches a frontier pattern `%f[set]`.
class _FrontierParser extends Parser<String> {
  _FrontierParser(this.set);

  final Parser<String> set;

  @override
  Result<String> parseOn(Context context) {
    final buffer = context.buffer;
    final pos = context.position;
    final prev = pos > 0 ? buffer[pos - 1] : '\x00';
    final next = pos < buffer.length ? buffer[pos] : '\x00';
    if (!set.accept(prev) && set.accept(next)) {
      return context.success('', pos);
    }
    return context.failure('Frontier not found');
  }

  @override
  int fastParseOn(String buffer, int position) {
    final prev = position > 0 ? buffer[position - 1] : '\x00';
    final next = position < buffer.length ? buffer[position] : '\x00';
    if (!set.accept(prev) && set.accept(next)) {
      return position;
    }
    return -1;
  }

  @override
  _FrontierParser copy() => _FrontierParser(set);
}

/// Parser that records the captured substring at [index].
class _RecordCaptureParser extends Parser<String> {
  _RecordCaptureParser(this.parser, this.index, this.storage);

  final Parser<String> parser;
  final int index;
  final List<String?> storage;

  @override
  Result<String> parseOn(Context context) {
    final result = parser.parseOn(context);
    if (result is Failure) return result;
    if (storage.length <= index) {
      storage.length = index + 1;
    }
    storage[index] = result.value;
    return result;
  }

  @override
  int fastParseOn(String buffer, int position) =>
      parser.fastParseOn(buffer, position);

  @override
  _RecordCaptureParser copy() => _RecordCaptureParser(parser, index, storage);
}

/// Parser that matches the previously captured substring at [index].

class _BackReferenceParser extends Parser<String> {
  _BackReferenceParser(this.index, this.storage);

  final int index;
  final List<String?> storage;

  @override
  Result<String> parseOn(Context context) {
    if (index >= storage.length || storage[index] == null) {
      return context.failure('Back reference $index not defined');
    }
    final value = storage[index]!;
    final end = context.position + value.length;
    if (end > context.buffer.length ||
        context.buffer.substring(context.position, end) != value) {
      return context.failure('Back reference $index mismatch');
    }
    return context.success(value, end);
  }

  @override
  int fastParseOn(String buffer, int position) {
    if (index >= storage.length || storage[index] == null) {
      return -1;
    }
    final value = storage[index]!;
    final end = position + value.length;
    if (end > buffer.length || buffer.substring(position, end) != value) {
      return -1;
    }
    return end;
  }

  @override
  _BackReferenceParser copy() => _BackReferenceParser(index, storage);
}

/// Root parser that resets capture storage before parsing.
class _LuaPatternParser extends Parser<String> {
  _LuaPatternParser(this.delegate, this.storage);

  final Parser<String> delegate;
  final List<String?> storage;

  @override
  Result<String> parseOn(Context context) {
    storage.clear();
    return delegate.parseOn(context);
  }

  @override
  int fastParseOn(String buffer, int position) {
    storage.clear();
    return delegate.fastParseOn(buffer, position);
  }

  @override
  _LuaPatternParser copy() => _LuaPatternParser(delegate, <String?>[]);
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
      final letter = spec[i + 1];
      final base = _classFor(letter.toLowerCase());
      final cls = letter == letter.toUpperCase() ? _negate(base) : base;
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
  final List<String?> _captureValues = [];

  Parser<String> compile() {
    if (_pattern.startsWith('^') && !_isEscaped(0)) {
      _pos = 1;
    }
    var seq = _parseSequence();
    if (_pattern.endsWith('\$') && !_isEscaped(_pattern.length - 1)) {
      seq = seq.end();
    }
    return _LuaPatternParser(seq.flatten(), _captureValues);
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
        _pos++; // consume repetition operator
        item = _applyRepetition(item, rep, stopOnRightParen);
      }
    }
    return item;
  }

  Parser _applyRepetition(Parser base, String op, bool stopOnRightParen) {
    switch (op) {
      case '*':
        final following = _parseSequence(stopOnRightParen: stopOnRightParen);
        return base.starGreedy(following).seq(following);
      case '+':
        final following = _parseSequence(stopOnRightParen: stopOnRightParen);
        return base.plusGreedy(following).seq(following);
      case '?':
        final following = _parseSequence(stopOnRightParen: stopOnRightParen);
        return base.seq(following).or(following);
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
      final index = int.parse(next) - 1;
      if (index >= _captures.length) {
        throw FormatException('Invalid back reference %$next');
      }
      _pos++;
      return _BackReferenceParser(index, _captureValues);
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
      _pos++;
      if (_pos >= _pattern.length || _pattern[_pos] != '[') {
        throw FormatException('Malformed %f sequence');
      }
      _pos++; // skip [
      final buffer = StringBuffer();
      while (_pos < _pattern.length && _pattern[_pos] != ']') {
        buffer.write(_pattern[_pos]);
        _pos++;
      }
      if (_pos >= _pattern.length) {
        throw FormatException('Unclosed %f[]');
      }
      _pos++; // consume ]
      final set = _bracketClass(buffer.toString(), negate: false);
      return _FrontierParser(set);
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
    final index = _captures.length;
    _captures.add(epsilon().map((_) => ''));

    if (_pattern[_pos] == ')') {
      _pos++;
      final capture = _RecordCaptureParser(
        epsilon().map((_) => ''),
        index,
        _captureValues,
      );
      _captures[index] = capture;
      return capture;
    }

    final inner = _parseSequence(stopOnRightParen: true);
    if (_pos >= _pattern.length || _pattern[_pos] != ')') {
      throw FormatException('Unclosed ( in pattern');
    }
    _pos++;

    final capture = _RecordCaptureParser(
      inner.flatten(),
      index,
      _captureValues,
    );
    _captures[index] = capture;
    return capture;
  }
}

Parser<String> compileLuaPattern(String pattern) =>
    LuaPatternCompiler(pattern).compile();

/// Result of a single Lua pattern match.
class LuaMatch {
  LuaMatch(this.start, this.end, this.match, this.captures);

  final int start;
  final int end;
  final String match;
  final List<String?> captures;
}

/// Compiled Lua pattern that can search within strings.
class LuaPattern {
  LuaPattern._(this._parser, this._captures);

  final _LuaPatternParser _parser;
  final List<String?> _captures;

  /// Compile [pattern] into a [LuaPattern].
  factory LuaPattern.compile(String pattern) {
    final compiler = LuaPatternCompiler(pattern);
    final parser = compiler.compile() as _LuaPatternParser;
    return LuaPattern._(parser, compiler._captureValues);
  }

  /// Find the first match in [input] starting from [start].
  LuaMatch? firstMatch(String input, [int start = 0]) {
    for (var pos = start; pos <= input.length; pos++) {
      final result = _parser.parseOn(Context(input, pos));
      if (result is Success<String>) {
        final captures = List<String?>.from(_captures);
        return LuaMatch(pos, result.position, result.value, captures);
      }
    }
    return null;
  }

  /// Iterate over all matches in [input] starting from [start].
  Iterable<LuaMatch> allMatches(String input, [int start = 0]) sync* {
    var pos = start;
    while (pos <= input.length) {
      final result = _parser.parseOn(Context(input, pos));
      if (result is Success<String>) {
        final captures = List<String?>.from(_captures);
        yield LuaMatch(pos, result.position, result.value, captures);
        pos = result.position > pos ? result.position : pos + 1;
      } else {
        pos++;
      }
    }
  }
}
