import 'package:petitparser/petitparser.dart';

/// Base class for pattern tokens produced by [LuaPatternParser].
sealed class PatternToken {}

/// Represents a percent-escaped special character such as `%%` or `%(`.
class EscapedCharToken extends PatternToken {
  final String char;
  EscapedCharToken(this.char);
  @override
  String toString() => 'Escaped($char)';
}

/// Represents a literal piece of text.
class LiteralToken extends PatternToken {
  final String literal;
  LiteralToken(this.literal);
  @override
  String toString() => 'Literal($literal)';
}

/// Represents a simple character class like `%d` or `%a`.
class SimpleClassToken extends PatternToken {
  final String char;
  SimpleClassToken(this.char);
  @override
  String toString() => 'Class(%$char)';
}

/// Represents a custom character class such as `[abc]`.
class CustomClassToken extends PatternToken {
  final String content;
  CustomClassToken(this.content);
  @override
  String toString() => 'Set([$content])';
}

/// Represents `%bxy` balanced items.
class BalancedToken extends PatternToken {
  final String open;
  final String close;
  BalancedToken(this.open, this.close);
  @override
  String toString() => 'Balanced($open$close)';
}

/// Represents `%f[set]` frontier patterns.
class FrontierToken extends PatternToken {
  final String set;
  FrontierToken(this.set);
  @override
  String toString() => 'Frontier([$set])';
}

/// Backreference like `%1`.
class BackRefToken extends PatternToken {
  final int index;
  BackRefToken(this.index);
  @override
  String toString() => 'BackRef($index)';
}

/// Start or end anchor: `^` or `$`.
class AnchorToken extends PatternToken {
  final String anchor;
  AnchorToken(this.anchor);
  @override
  String toString() => 'Anchor($anchor)';
}

/// Represents quantifiers after a token.
class QuantifiedToken extends PatternToken {
  final PatternToken inner;
  final String quantifier;
  QuantifiedToken(this.inner, this.quantifier);
  @override
  String toString() => 'Quantified($inner$quantifier)';
}

/// Represents a capture `( ... )`.
class CaptureToken extends PatternToken {
  final List<PatternToken> inner;
  CaptureToken(this.inner);
  @override
  String toString() => 'Capture($inner)';
}

/// Parser that attempts to parse Lua patterns into tokens.
class LuaPatternParser {
  Parser build() {
    final parser = undefined();

    final special = anyOf(r'^\$()%.[]*+-?');
    final escapedSpecial = char(
      '%',
    ).seq(special).map((v) => EscapedCharToken(v[1] as String));

    final literal = noneOf(
      r'^\$()%.[]*+-?',
    ).plus().flatten().map(LiteralToken.new);

    final simpleClass = char(
      '%',
    ).seq(pattern('a-zA-Z')).map((v) => SimpleClassToken(v[1]));

    final customClass = char('[')
        .seq(pattern('^]').star().flatten())
        .seq(char(']'))
        .map((v) => CustomClassToken(v[1] as String));

    final balanced = char('%')
        .seq(char('b'))
        .seq(any())
        .seq(any())
        .map((v) => BalancedToken(v[2] as String, v[3] as String));

    final frontier = char('%')
        .seq(char('f'))
        .seq(char('['))
        .seq(pattern('^]').star().flatten())
        .seq(char(']'))
        .map((v) => FrontierToken(v[3] as String));

    final backref = char(
      '%',
    ).seq(digit()).map((v) => BackRefToken(int.parse(v[1])));

    final anchor = anyOf(r'^$').map(AnchorToken.new);

    final atom = undefined();

    final capture = char('(')
        .seq(parser.star())
        .seq(char(')'))
        .map((v) => CaptureToken(List<PatternToken>.from(v[1] as List)));

    atom.set(
      balanced |
          frontier |
          escapedSpecial |
          backref |
          simpleClass |
          customClass |
          capture |
          anchor |
          literal,
    );

    final quantified = atom
        .seq(anyOf('*+?-'))
        .map((v) => QuantifiedToken(v[0] as PatternToken, v[1] as String));

    parser.set(quantified | atom);

    return parser.star().end();
  }

  List<PatternToken> parse(String input) {
    final result = build().parse(input);
    if (result is Success) {
      return List<PatternToken>.from(result.value as List);
    } else {
      throw FormatException('Invalid pattern at ${result.position}');
    }
  }
}
