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
final _zero = char('\x00');
// %w in Lua also includes the underscore character
final _alnum = pattern('0-9A-Za-z_');

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
    case 'z':
      return _zero;
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
    if (open == close) {
      pos++;
      while (pos < buffer.length) {
        if (buffer[pos] == close) {
          return context.success(
            buffer.substring(context.position, pos + 1),
            pos + 1,
          );
        }
        pos++;
      }
      return context.failure('Unbalanced $open$close');
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

/// Parser that captures the current position as a string representation of a number
class _PositionCaptureParser extends Parser<String> {
  @override
  Result<String> parseOn(Context context) {
    // Return the current position (1-based as per Lua convention) as a string
    final position = context.position + 1;
    return context.success(position.toString(), context.position);
  }

  @override
  int fastParseOn(String buffer, int position) => position;

  @override
  _PositionCaptureParser copy() => _PositionCaptureParser();
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
  ({
    Parser<String> parser,
    int nextIndex,
    int? literalCodeUnit,
  }) readToken(int index) {
    if (index >= spec.length) {
      throw FormatException('Malformed set: \$spec');
    }
    final ch = spec[index];
    if (ch == '%') {
      if (index + 1 >= spec.length) {
        throw FormatException('Malformed set: \$spec');
      }
      final letter = spec[index + 1];
      if (RegExp(r'[a-zA-Z]').hasMatch(letter)) {
        final base = _classFor(letter.toLowerCase());
        final cls = letter == letter.toUpperCase() ? _negate(base) : base;
        return (parser: cls, nextIndex: index + 2, literalCodeUnit: null);
      }
      return (
        parser: char(letter),
        nextIndex: index + 2,
        literalCodeUnit: letter.codeUnitAt(0),
      );
    }
    return (
      parser: char(ch),
      nextIndex: index + 1,
      literalCodeUnit: ch.codeUnitAt(0),
    );
  }

  var index = 0;
  while (index < spec.length) {
    final token = readToken(index);
    if (token.literalCodeUnit != null &&
        token.nextIndex < spec.length &&
        spec[token.nextIndex] == '-' &&
        token.nextIndex + 1 < spec.length) {
      final rangeEnd = readToken(token.nextIndex + 1);
      if (rangeEnd.literalCodeUnit != null) {
        final startCode = token.literalCodeUnit!;
        final endCode = rangeEnd.literalCodeUnit!;
        final lower = startCode <= endCode ? startCode : endCode;
        final upper = startCode <= endCode ? endCode : startCode;
        allowed.add(_predicate((c) => c >= lower && c <= upper));
        index = rangeEnd.nextIndex;
        continue;
      }
    }
    allowed.add(token.parser);
    index = token.nextIndex;
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
  final List<bool> _completedCaptures = [];
  final Set<int> _positionCaptureIndexes = <int>{};
  final List<int> _openCaptures = [];

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

  int _findBracketEndFrom(int index) {
    var i = index;
    if (i < _pattern.length && _pattern[i] == ']') {
      i++;
    }
    while (i < _pattern.length) {
      if (_pattern[i] == '%' && i + 1 < _pattern.length) {
        i += 2;
        continue;
      }
      if (_pattern[i] == ']') {
        return i;
      }
      i++;
    }
    throw FormatException("malformed pattern (missing ']')");
  }

  String _readBracketSpecAt(int index) {
    final end = _findBracketEndFrom(index);
    if (end < index) {
      throw FormatException("malformed pattern (missing ']')");
    }
    return _pattern.substring(index, end);
  }

  Parser _parseLookaheadSequenceFrom(
    int index, {
    bool stopOnRightParen = false,
    bool closeCurrentCapture = false,
    int transparentRightParensRemaining = 0,
  }) {
    final savedPos = _pos;
    final savedCapturesLength = _captures.length;
    final savedCaptureValuesLength = _captureValues.length;
    final savedCompletedCapturesLength = _completedCaptures.length;
    final savedOpenCapturesLength = _openCaptures.length;
    int? temporarilyClosedCapture;
    _pos = index;
    if (closeCurrentCapture && _openCaptures.isNotEmpty) {
      temporarilyClosedCapture = _openCaptures.removeLast();
    }
    var parser = _parseSequence(
      stopOnRightParen: stopOnRightParen,
      transparentRightParensRemaining: transparentRightParensRemaining,
    );
    if (_pos > index && _pattern[_pos - 1] == '\$' && !_isEscaped(_pos - 1)) {
      parser = parser.end();
    }
    _pos = savedPos;
    if (_captures.length > savedCapturesLength) {
      _captures.length = savedCapturesLength;
    }
    if (_captureValues.length > savedCaptureValuesLength) {
      _captureValues.length = savedCaptureValuesLength;
    }
    if (_completedCaptures.length > savedCompletedCapturesLength) {
      _completedCaptures.length = savedCompletedCapturesLength;
    }
    if (_openCaptures.length > savedOpenCapturesLength) {
      _openCaptures.length = savedOpenCapturesLength;
    }
    if (temporarilyClosedCapture case final capture?) {
      _openCaptures.add(capture);
    }
    return parser;
  }

  Parser<String>? _lookaheadItem(int index) {
    if (index >= _pattern.length) return null;
    final ch = _pattern[index];
    if (ch == '%') {
      if (index + 1 >= _pattern.length) return null;
      final next = _pattern[index + 1];
      if (RegExp(r'[a-zA-Z]').hasMatch(next)) {
        return _classFor(next.toLowerCase());
      }
      if (next == 'b' && index + 2 < _pattern.length) {
        return char(_pattern[index + 2]);
      }
      if (next == 'f' &&
          index + 2 < _pattern.length &&
          _pattern[index + 2] == '[') {
        var i = index + 3;
        return pattern(_readBracketSpecAt(i));
      }
      return char(next);
    } else if (ch == '(') {
      return _lookaheadItem(index + 1);
    } else if (ch == '[') {
      var i = index + 1;
      var negate = false;
      if (i < _pattern.length && _pattern[i] == '^') {
        negate = true;
        i++;
      }
      return _bracketClass(_readBracketSpecAt(i), negate: negate);
    } else if (ch == '.') {
      return any();
    } else if (ch == '^' || ch == '\$' || ch == ')') {
      return null;
    } else {
      return char(ch);
    }
  }

  Parser _parseSequence({
    bool stopOnRightParen = false,
    int transparentRightParensRemaining = 0,
  }) {
    final elements = <Parser>[];
    while (_pos < _pattern.length) {
      final itemStart = _pos;
      final p = _parseItem(
        stopOnRightParen,
        transparentRightParensRemaining: transparentRightParensRemaining,
      );
      if (p == null) break;
      elements.add(p);
      if (itemStart < _pattern.length &&
          _pattern[itemStart] == ')' &&
          transparentRightParensRemaining > 0) {
        transparentRightParensRemaining--;
      }
    }
    return elements.length == 1 ? elements.single : SequenceParser(elements);
  }

  Parser? _parseItem(
    bool stopOnRightParen, {
    int transparentRightParensRemaining = 0,
  }) {
    if (_pos >= _pattern.length) return null;
    final ch = _pattern[_pos];

    if (stopOnRightParen && ch == ')') {
      if (transparentRightParensRemaining > 0) {
        _pos++;
        return epsilon();
      }
      return null;
    }
    if (ch == ')') {
      throw FormatException('invalid pattern capture');
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
    final startPos = _pos;
    final following = _parseSequence(stopOnRightParen: stopOnRightParen);
    final isEmpty = _pos == startPos;
    // Keep the parser position after the following sequence so we don't
    // reparse it again in the caller.

    Parser result;
    if (isEmpty) {
      Parser? limit;
      var trailingEndAnchor = false;
      if (stopOnRightParen && _pos < _pattern.length && _pattern[_pos] == ')') {
        limit = _parseLookaheadSequenceFrom(
          _pos + 1,
          stopOnRightParen: true,
          closeCurrentCapture: true,
        );
      } else if (_pos < _pattern.length &&
          _pattern[_pos] == '\$' &&
          !_isEscaped(_pos)) {
        // A trailing unescaped '$' becomes an end-of-input constraint in
        // [compile()]. Lazy repetition must still see that constraint here,
        // otherwise patterns like '^.-$' stop immediately at the empty match.
        limit = epsilon().end();
        trailingEndAnchor = true;
      }
      if (limit != null) {
        switch (op) {
          case '*':
            result = base.starGreedy(limit);
            break;
          case '+':
            result = base.plusGreedy(limit);
            break;
          case '?':
            result = base.optional();
            break;
          case '-':
            result = trailingEndAnchor
                ? base.starGreedy(limit)
                : base.starLazy(limit);
            break;
          default:
            throw StateError('Unhandled repetition $op');
        }
      } else {
        switch (op) {
          case '*':
            result = base.star();
            break;
          case '+':
            result = base.plus();
            break;
          case '?':
            result = base.optional();
            break;
          case '-':
            result = base.starLazy(epsilon());
            break;
          default:
            throw StateError('Unhandled repetition $op');
        }
      }
    } else {
      var fullFollowing = following;
      if (stopOnRightParen) {
        fullFollowing = _parseLookaheadSequenceFrom(
          startPos,
          stopOnRightParen: true,
          transparentRightParensRemaining: 1,
        );
      }
      switch (op) {
        case '*':
          result = base.starGreedy(fullFollowing).seq(following);
          break;
        case '+':
          result = base.plusGreedy(fullFollowing).seq(following);
          break;
        case '?':
          result = base.seq(following).or(following);
          break;
        case '-':
          result = base.starLazy(fullFollowing).seq(following);
          break;
        default:
          throw StateError('Unhandled repetition $op');
      }
    }
    return result;
  }

  Parser _parsePercent() {
    assert(_pattern[_pos] == '%');
    _pos++;
    if (_pos >= _pattern.length) {
      throw FormatException("malformed pattern (ends with '%')");
    }
    final next = _pattern[_pos];
    if (next == '0') {
      throw FormatException('invalid capture index %0');
    }
    if ('123456789'.contains(next)) {
      final index = int.parse(next) - 1;
      if (index >= _captures.length || _openCaptures.contains(index)) {
        throw FormatException('invalid capture index %$next');
      }
      _pos++;
      return _BackReferenceParser(index, _captureValues);
    }
    if (next == 'b') {
      if (_pos + 2 >= _pattern.length) {
        throw FormatException('malformed pattern (missing arguments to %b)');
      }
      final open = _pattern[_pos + 1];
      final close = _pattern[_pos + 2];
      _pos += 3;
      return _BalancedParser(open, close);
    }
    if (next == 'f') {
      _pos++;
      if (_pos >= _pattern.length || _pattern[_pos] != '[') {
        throw FormatException("missing '[' after '%f' in pattern");
      }
      _pos++; // skip [
      var negate = false;
      if (_pos < _pattern.length && _pattern[_pos] == '^') {
        negate = true;
        _pos++;
      }
      final set = _bracketClass(_readBracketSpecAt(_pos), negate: negate);
      _pos = _findBracketEndFrom(_pos) + 1;
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
    _pos++;
    var negate = false;
    if (_pattern[_pos] == '^') {
      negate = true;
      _pos++;
    }
    final set = _bracketClass(_readBracketSpecAt(_pos), negate: negate);
    _pos = _findBracketEndFrom(_pos) + 1;
    return set;
  }

  Parser _parseCapture() {
    assert(_pattern[_pos] == '(');
    _pos++;
    final index = _captures.length;
    _captures.add(epsilon().map((_) => ''));
    _completedCaptures.add(false);
    _openCaptures.add(index);

    if (_pattern[_pos] == ')') {
      _pos++;
      _positionCaptureIndexes.add(index);
      final capture = _RecordCaptureParser(
        _PositionCaptureParser(),
        index,
        _captureValues,
      );
      _captures[index] = capture;
      _completedCaptures[index] = true;
      _openCaptures.removeLast();
      return capture;
    }

    final inner = _parseSequence(stopOnRightParen: true);
    if (_pos >= _pattern.length || _pattern[_pos] != ')') {
      throw FormatException('unfinished capture');
    }
    _pos++;

    final capture = _RecordCaptureParser(
      inner.flatten(),
      index,
      _captureValues,
    );
    _captures[index] = capture;
    _completedCaptures[index] = true;
    _openCaptures.removeLast();
    return capture;
  }
}

Parser<String> compileLuaPattern(String pattern) =>
    LuaPatternCompiler(pattern).compile();

/// Result of a single Lua pattern match.
class LuaMatch {
  LuaMatch(
    this.start,
    this.end,
    this.match,
    this.captures,
    this.positionCaptureIndexes,
  );

  final int start;
  final int end;
  final String match;
  final List<String?> captures;
  final Set<int> positionCaptureIndexes;
}

/// Compiled Lua pattern that can search within strings.
class LuaPattern {
  LuaPattern._(
    this._parser,
    this._captures,
    this._positionCaptureIndexes,
    this._captureCount,
  );

  final _LuaPatternParser _parser;
  final List<String?> _captures;
  final Set<int> _positionCaptureIndexes;
  final int _captureCount;

  /// Compile [pattern] into a [LuaPattern].
  factory LuaPattern.compile(String pattern) {
    final compiler = LuaPatternCompiler(pattern);
    final parser = compiler.compile() as _LuaPatternParser;
    return LuaPattern._(
      parser,
      compiler._captureValues,
      Set<int>.from(compiler._positionCaptureIndexes),
      compiler._captures.length,
    );
  }

  /// Find the first match in [input] starting from [start].
  LuaMatch? firstMatch(String input, [int start = 0]) {
    for (var pos = start; pos <= input.length; pos++) {
      final result = _parser.parseOn(Context(input, pos));
      if (result is Success) {
        final captures = List<String?>.from(_captures.take(_captureCount));
        return LuaMatch(
          pos,
          result.position,
          result.value.toString() ?? '',
          captures,
          _positionCaptureIndexes,
        );
      }
    }
    return null;
  }

  /// Iterate over all matches in [input] starting from [start].
  Iterable<LuaMatch> allMatches(String input, [int start = 0]) sync* {
    var pos = start;
    while (pos <= input.length) {
      final result = _parser.parseOn(Context(input, pos));
      if (result is Success) {
        final captures = List<String?>.from(_captures.take(_captureCount));
        yield LuaMatch(
          pos,
          result.position,
          result.value.toString() ?? '',
          captures,
          _positionCaptureIndexes,
        );
        pos = result.position > pos ? result.position : pos + 1;
      } else {
        pos++;
      }
    }
  }
}
