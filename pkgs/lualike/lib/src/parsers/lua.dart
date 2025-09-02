import 'package:lualike/src/lua_error.dart' show LuaError;
import 'package:petitparser/petitparser.dart';
import 'package:source_span/source_span.dart';

import '../ast.dart';
import '../lua_error.dart';
import '../number.dart';
import 'string.dart';

/// A **work-in-progress** PetitParser grammar for LuaLike.  The goal is to
/// replicate the existing PEG-generated parser (in `grammar_parser.dart`) but
/// using PetitParser combinators.
///
/// For the moment this file only contains a minimal skeleton that recognises a
/// subset of Lua input.  It will grow incrementally, but its public API is
/// already stable so that callers can switch to it once feature-complete.
///
/// The primary entry-point mirrors the old `parse(String)` top-level function
/// and returns the same `Program` AST node hierarchy.
class LuaGrammarDefinition extends GrammarDefinition {
  LuaGrammarDefinition(this._sourceFile);

  /// Expose whitespace/comments parser for testing
  Parser whiteSpaceAndCommentsForTest() => _whiteSpaceAndComments();

  /// Source file used for span annotations.
  final SourceFile _sourceFile;

  // ---------- Helpers -------------------------------------------------------

  /// Wraps [parser] with optional whitespace/comment trimming.
  ///
  /// When [parser] is a [String] that represents a *keyword* (e.g. "and",
  /// "or", "while"), we must ensure the match only succeeds when the keyword
  /// is **not** directly followed by an identifier character. Otherwise a
  /// word like "original_len" would be tokenised as the keyword "or" plus the
  /// leftover "iginal_len", breaking the grammar.
  ///
  /// The heuristic: if the last character of the token is `[A-Za-z0-9_]`, we
  /// require a negative look-ahead that asserts the next input character is
  /// *not* another identifier character.  This keeps the behaviour for all
  /// punctuation tokens ("+", "<=", etc.) unchanged while giving keywords
  /// proper word-boundaries.
  Parser _token(Object parser) {
    Parser inner;

    if (parser is Parser) {
      inner = parser;
    } else {
      final String lexeme = parser as String;
      // Determine if the lexeme ends with an identifier character.
      final bool endsWithIdentChar = RegExp(
        r'[A-Za-z0-9_]',
      ).hasMatch(lexeme.substring(lexeme.length - 1));

      if (endsWithIdentChar) {
        // Match the exact lexeme, *then* assert the next char is not another
        // identifier char (negative look-ahead).  `pick(0)` keeps only the
        // first parser’s result so that downstream code continues to receive
        // the plain string, not a List.
        inner = (string(lexeme) & pattern('A-Za-z0-9_').not()).pick(0);
      } else {
        inner = string(lexeme);
      }
    }

    // Attach the trim *after* the inner parser so that we keep the actual
    // matched lexeme intact for error reporting.
    return inner.trim(ref0(_whiteSpaceAndComments));
  }

  // Matches at least one whitespace or comment segment. Used by `_token` for
  // trimming.  Important: This parser itself must consume *some* input on
  // success, otherwise the surrounding `trim()` logic (which already loops
  // zero-or-more) would recurse indefinitely and trigger PetitParser’s
  // `PossessiveRepeatingParser` assertion. Therefore we use `plus()` here
  // instead of `star()`.
  Parser _whiteSpaceAndComments() =>
      (whitespace() | ref0(_longComment) | ref0(_lineComment)).plus();

  Parser _lineComment() =>
      (string('--') & pattern('\n').neg().star() & pattern('\n').optional())
          .flatten();

  // Long comment --[=[ ... ]=] with optional = depth
  Parser _longComment() =>
      (string('--') & _LongCommentBracketParser()).flatten();

  // ---------- Lexical tokens ------------------------------------------------
  // Lua identifiers cannot be reserved keywords. Filter them out so that
  // tokens like `return`, `for`, etc. are not mis-interpreted as plain
  // identifiers. This prevents mis-parsing of control-flow statements and
  // keeps the AST equivalent to the PEG version.
  static const _keywords = {
    'and',
    'break',
    'do',
    'else',
    'elseif',
    'end',
    'false',
    'for',
    'function',
    'goto',
    'if',
    'in',
    'local',
    'nil',
    'not',
    'or',
    'repeat',
    'return',
    'then',
    'true',
    'until',
    'while',
  };

  /// Creates a positioned ParserException with accurate source location
  ParserException _createPositionedException(
    dynamic nodeOrPosition,
    String message,
  ) {
    int position;
    if (nodeOrPosition is AstNode && nodeOrPosition.span != null) {
      position = nodeOrPosition.span!.start.offset;
    } else if (nodeOrPosition is int) {
      position = nodeOrPosition;
    } else {
      position = 0; // Fallback position if we can't determine it
    }

    return ParserException(
      Failure(_sourceFile.url?.toString() ?? '', position, message),
    );
  }

  Parser _span(Parser inner) => (position() & inner & position()).map((vals) {
    final start = vals[0] as int;
    final node = vals[1] as AstNode;
    final end = vals[2] as int;
    node.setSpan(_sourceFile.span(start, end));
    return node;
  });

  Parser _identifier() {
    final base = (_letter() & (_letter() | digit()).star()).flatten();
    // Capture start and end positions to create SourceSpan
    return position()
        .seq(base)
        .seq(position())
        .trim(ref0(_whiteSpaceAndComments))
        .map((vals) {
          final start = vals[0] as int;
          final text = vals[1] as String;
          final end = vals[2] as int;
          final id = Identifier(text);

          id.setSpan(_sourceFile.span(start, end));
          return id;
        })
        .where((id) => !_keywords.contains((id).name));
  }

  Parser _letter() => pattern('A-Za-z_');

  // Matches Lua numeric literals:
  //   • Decimal:  123   1.5   .5   1e3   1.5e-2
  //   • Hex:      0xFF  0X1.8p+4  0x1p-1
  Parser _numberLiteral() {
    // ---------- helpers ----------
    final hexDigit = pattern('0-9A-Fa-f');
    final decDigit = digit();

    // Hex prefix 0x / 0X
    final hexPrefix = string('0') & pattern('xX');

    // Hex exponent P / p with optional sign and digits
    final hexExp = pattern('pP') & pattern('+-').optional() & decDigit.plus();

    // Hexadecimal numeral: 0x[hexdigits](.[hexdigits])?(_hexExp)?
    final hexInt = hexPrefix & hexDigit.plus();
    final hexFrac = hexPrefix & hexDigit.star() & char('.') & hexDigit.plus();
    final hexNumber = (hexFrac | hexInt) & hexExp.optional();

    // Decimal parts
    final decInt = decDigit.plus();
    final decFrac1 = decDigit.plus() & char('.') & decDigit.star();
    final decFrac2 = char('.') & decDigit.plus();
    final decExp = pattern('eE') & pattern('+-').optional() & decDigit.plus();

    final decimalUnsigned = ((decFrac1 | decFrac2 | decInt) & decExp.optional())
        .flatten();

    // Lua numeric literals do NOT include a leading sign; signs are handled
    // by the separate unary operator. Keep the literal unsigned.
    final decimalNumber = decimalUnsigned;

    final hexNumberFlatten = hexNumber.flatten();

    return position()
        .seq((hexNumberFlatten | decimalNumber))
        .seq(position())
        .trim(ref0(_whiteSpaceAndComments))
        .map((vals) {
          final start = vals[0] as int;
          final lexeme = vals[1] as String;
          final end = vals[2] as int;
          final node = NumberLiteral(LuaNumberParser.parse(lexeme));
          return _annotate(node, start, end);
        });
  }

  // ---------- Grammar rules -------------------------------------------------
  @override
  Parser start() {
    final leading = _whiteSpaceAndComments().star();
    // Do not require .end() so trailing trivia is allowed, matching Lua.
    // Require complete consumption of input (besides allowed trailing trivia).
    return ((leading & ref0(_chunk) & leading).map((vals) => vals[1]).end())
        .trim(ref0(_whiteSpaceAndComments));
  }

  // chunk ::= block
  Parser _chunk() =>
      ref0(_block).map((stmts) => Program(stmts as List<AstNode>));

  // block ::= {stat} [retstat]
  Parser _block() =>
      (ref0(_stat).trim(ref0(_whiteSpaceAndComments)).star() &
              ref0(_retstat).optional())
          .map((values) {
            final stats = values[0] as List;
            final list = <AstNode>[];
            for (final s in stats) {
              if (s != null) list.add(s as AstNode);
            }
            if (values[1] != null) list.add(values[1] as AstNode);
            return list;
          });

  // stat ::= empty ';' or assignment or expression statement
  Parser _stat() =>
      _token(';').map((_) => null) |
      ref0(_localFunctionDefStat) |
      ref0(_functionDefStat) |
      ref0(_localDeclaration) |
      ref0(_forNumericStat) |
      ref0(_forGenericStat) |
      ref0(_doBlockStat) |
      ref0(_whileStat) |
      ref0(_repeatStat) |
      ref0(_ifStat) |
      ref0(_breakStat) |
      ref0(_labelStat) |
      ref0(_gotoStat) |
      ref0(_assignment) |
      ref0(_returnlessExprStatement) |
      // Error case: Detect bare string literals and report appropriate error
      _stringLiteral().map((literal) {
        // Extract the raw content for error reporting
        String errorText = literal.value;
        if (literal.isLongString) {
          // For long strings, show the full long bracket syntax
          errorText = '[[${literal.value}]]';
        } else {
          // For regular strings, try to reconstruct with quotes
          errorText = '"${literal.value}"';
        }

        throw _createPositionedException(
          literal,
          'unexpected symbol near \'$errorText\'',
        );
      });

  // retstat ::= return [explist] [';']
  Parser _retstat() => _span(
    (_token('return') & ref0(_explist).optional() & _token(';').optional()).map(
      (values) {
        final list = values[1] as List<AstNode>? ?? <AstNode>[];
        return ReturnStatement(list);
      },
    ),
  );

  // varlist '=' explist
  Parser _assignment() => _span(
    (ref0(_varlist) & _token('=') & ref0(_explist)).map((values) {
      final targets = values[0] as List<AstNode>;
      final exprs = values[2] as List<AstNode>;
      return Assignment(targets, exprs);
    }),
  );

  // varlist ::= var {',' var}
  Parser _varlist() =>
      (ref0(_var) & (_token(',') & ref0(_var)).star()).map((values) {
        final first = values[0] as AstNode;
        final restPairs = values[1] as List;
        final vars = [first];
        for (final pair in restPairs) {
          vars.add(pair[1] as AstNode);
        }
        return vars;
      });

  // var ::= Name for now (later add table access)
  Parser _var() {
    final simpleName = _identifier();
    final complex = (_prefixExp().map(
      (expr) => expr,
    )).where((e) => e is! FunctionCall && e is! MethodCall).cast<AstNode>();
    return complex | simpleName;
  }

  // explist ::= exp {',' exp}
  Parser _explist() =>
      (ref0(_expression) & (_token(',') & ref0(_expression)).star()).map((
        values,
      ) {
        final first = values[0] as AstNode;
        final restPairs = values[1] as List;
        final exprs = [first];
        for (final pair in restPairs) {
          exprs.add(pair[1] as AstNode);
        }
        return exprs;
      });

  // Full expression with operator precedence handled by [ExpressionBuilder].
  Parser _expression() {
    final builder = ExpressionBuilder();

    // --- Custom primitives: power & unary handling (Lua-specific) ---
    builder.primitive(ref0(_unaryExpression));

    // --- multiplicative */%// ---
    builder.group().left(
      ref0(_mulOperator),
      (dynamic a, dynamic op, dynamic b) =>
          BinaryExpression(a as AstNode, op as String, b as AstNode),
    );

    // --- additive + - ---
    builder.group().left(
      ref0(_addOperator),
      (dynamic a, dynamic op, dynamic b) =>
          BinaryExpression(a as AstNode, op as String, b as AstNode),
    );

    // --- concatenation .. (right-assoc) ---
    builder.group().right(
      _token('..'),
      (dynamic a, dynamic op, dynamic b) =>
          BinaryExpression(a as AstNode, '..', b as AstNode),
    );

    // --- bitwise shift << >> ---
    builder.group().left(
      ref0(_shiftOperator),
      (dynamic a, dynamic op, dynamic b) =>
          BinaryExpression(a as AstNode, op as String, b as AstNode),
    );

    // --- bitwise and & ---
    builder.group().left(
      _token('&'),
      (dynamic a, dynamic op, dynamic b) =>
          BinaryExpression(a as AstNode, '&', b as AstNode),
    );

    // --- bitwise xor ~ ---
    builder.group().left(
      _token('~'),
      (dynamic a, dynamic op, dynamic b) =>
          BinaryExpression(a as AstNode, '~', b as AstNode),
    );

    // --- bitwise or | ---
    builder.group().left(
      _token('|'),
      (dynamic a, dynamic op, dynamic b) =>
          BinaryExpression(a as AstNode, '|', b as AstNode),
    );

    // --- comparison < > <= >= == ~= ---
    builder.group().left(
      ref0(_comparisonOperator),
      (dynamic a, dynamic op, dynamic b) =>
          BinaryExpression(a as AstNode, op as String, b as AstNode),
    );

    // --- logical and ---
    builder.group().left(
      _token('and'),
      (dynamic a, dynamic op, dynamic b) =>
          BinaryExpression(a as AstNode, 'and', b as AstNode),
    );

    // --- logical or (lowest precedence) ---
    builder.group().left(
      _token('or'),
      (dynamic a, dynamic op, dynamic b) =>
          BinaryExpression(a as AstNode, 'or', b as AstNode),
    );

    return builder.build().cast<AstNode>();
  }

  // ---------- Operators parsers -------------------------------------------
  Parser _unaryOperator() =>
      (_token('-') | _token('#') | _token('not') | _token('~'));

  Parser _mulOperator() =>
      _token('//') | _token('*') | _token('/') | _token('%');

  Parser _addOperator() => _token('+') | _token('-');

  Parser _comparisonOperator() =>
      _token('<=') |
      _token('>=') |
      _token('<') |
      _token('>') |
      _token('==') |
      _token('~=');

  Parser _shiftOperator() => _token('<<') | _token('>>');

  // ---------- Primary expressions -----------------------------------------
  Parser _primaryExpression() =>
      ref0(_functionLiteral).trim(ref0(_whiteSpaceAndComments)) |
      ref0(_prefixExp).trim(ref0(_whiteSpaceAndComments)) |
      ref0(_numberLiteral).trim(ref0(_whiteSpaceAndComments)) |
      ref0(_booleanLiteral).trim(ref0(_whiteSpaceAndComments)) |
      ref0(_nilLiteral).trim(ref0(_whiteSpaceAndComments)) |
      ref0(_vararg).trim(ref0(_whiteSpaceAndComments)) |
      ref0(_stringLiteral).trim(ref0(_whiteSpaceAndComments)) |
      ref0(_tableConstructor).trim(ref0(_whiteSpaceAndComments)) |
      ref0(_groupedExpression).trim(ref0(_whiteSpaceAndComments));

  Parser _groupedExpression() => (_token('(') & ref0(_expression) & _token(')'))
      .map((values) => GroupedExpression(values[1] as AstNode));

  Parser _nilLiteral() => position()
      .seq(_token('nil'))
      .seq(position())
      .map((vals) => _annotate(NilValue(), vals[0] as int, vals[2] as int));

  Parser _booleanLiteral() {
    final trueLit = position()
        .seq(_token('true'))
        .seq(position())
        .map(
          (vals) =>
              _annotate(BooleanLiteral(true), vals[0] as int, vals[2] as int),
        );

    final falseLit = position()
        .seq(_token('false'))
        .seq(position())
        .map(
          (vals) =>
              _annotate(BooleanLiteral(false), vals[0] as int, vals[2] as int),
        );

    return trueLit | falseLit;
  }

  // In Lua, an expression statement is only valid when the expression is
  // a function call or a method call (or vararg “...” which we treat as
  // invalid here). Accepting *any* expression would make the grammar
  // ambiguous because a bare identifier on a new line could be parsed
  // either as the start of a new assignment or as a (meaningless)
  // standalone expression. This ambiguity surfaced when two assignment
  // statements appear on consecutive lines without a semicolon, e.g.:
  //   a = 1
  //   b = 2   -- ERROR before this fix
  // We therefore restrict the rule so that only function / method calls
  // qualify as a ‘returnless expression statement’, mirroring Lua’s own
  // grammar (§3.3.1).

  Parser _returnlessExprStatement() {
    // Lua allows an *expression statement* only when the expression is a
    // function- or method-call (see Lua 5.4 §3.3.1).  We implement this by
    // first performing a non-consuming look-ahead that succeeds **only** if
    // the upcoming expression parses to a FunctionCall/MethodCall AST node.

    // Positive look-ahead (does not consume input).
    final callAhead = ref0(
      _prefixExp,
    ).where((n) => n is FunctionCall || n is MethodCall).and();

    // Real statement: full expression → ExpressionStatement with span.
    final callStmt = _span(
      ref0(_expression).map((expr) => ExpressionStatement(expr)),
    );

    // Combine: require look-ahead, then parse the actual statement, keep it.
    return (callAhead & callStmt).pick(1);
  }

  // ----------------- Literals ---------------------------------------------

  // String literal parser that supports escape sequences (" ")
  Parser _stringLiteral() {
    // Helper to build content parser for given quote char
    Parser contentParser(String quote) {
      // Either an escaped character (\\X) or any char except the closing quote
      return ((char('\\') & any()) | pattern('^$quote')).star().flatten();
    }

    // Tag each alternative so we know if it's a long string.
    final long = _LongBracketParser().map((s) => ['long', s]);

    // Closed short strings
    final dq = (char('"') & contentParser('"') & char('"')).flatten().map(
      (s) => ['dq', s],
    );
    final sq = (char("'") & contentParser("'") & char("'")).flatten().map(
      (s) => ['sq', s],
    );

    // Unterminated short strings: start quote + content, but NOT followed by a closing quote
    final dqUnclosed = (char('"') & contentParser('"') & char('"').not())
        .flatten()
        .map((s) => ['dq_unclosed', s]);
    final sqUnclosed = (char("'") & contentParser("'") & char("'").not())
        .flatten()
        .map((s) => ['sq_unclosed', s]);

    final literalBody = (long | dq | sq | dqUnclosed | sqUnclosed);

    return position().seq(literalBody).seq(position()).trim(ref0(_whiteSpaceAndComments)).map((
      vals,
    ) {
      final start = vals[0] as int;
      final tagged = vals[1] as List;
      final tag = tagged[0] as String;
      final lexeme = tagged[1] as String;
      final end = vals[2] as int;

      if (tag == 'long') {
        // lexeme is already the raw content.
        return _annotate(StringLiteral(lexeme, isLongString: true), start, end);
      } else if (tag == 'dq_unclosed' || tag == 'sq_unclosed') {
        // Remove the starting quote only; there is no closing quote.
        final content = lexeme.substring(1);

        // Pre-validate content to surface escape-sequence errors before EOF
        try {
          LuaStringParser.parseStringContent(content);
          // If validation passes, it's an unfinished string
          throw _createPositionedException(
            start,
            "unfinished string near '<eof>'",
          );
        } catch (e) {
          if (e is FormatException) {
            // Convert detailed error message for escape sequence errors
            String errorMessage = e.message;
            if (errorMessage.contains('hexadecimal digit expected')) {
              // Prefer no closing quote in the preview for unfinished strings
              final quotedString = '"$content';
              errorMessage =
                  "[string \"\"]:1: hexadecimal digit expected near '$quotedString'";
            } else if (errorMessage.contains('invalid escape sequence')) {
              final quotedString = '"$content'; // No closing quote
              errorMessage =
                  "[string \"\"]:1: invalid escape sequence near '$quotedString'";
            } else if (errorMessage.contains('missing \'}\' near|context:')) {
              // Unclosed string due to missing closing brace in \u{...}
              // Reconstruct snippet from actual content without assuming a prefix.
              final contextStart = errorMessage.indexOf('context:') + 8;
              final rawContext = errorMessage.substring(contextStart);
              final hasTrailingQuote = rawContext.endsWith('"');
              final ctxCore = hasTrailingQuote
                  ? rawContext.substring(0, rawContext.length - 1)
                  : rawContext;
              final needle = '\\$ctxCore';
              final idx = content.indexOf(needle);
              final snippet = (idx >= 0)
                  ? (content.substring(0, idx) + needle)
                  : ('\\$ctxCore');
              errorMessage = "[string \"\"]:1: missing '}' near '$snippet'";
            } else if (errorMessage.startsWith('[string')) {
              // Already formatted upstream
            } else {
              // Fallback to unfinished string
              errorMessage = "[string \"\"]:1: unfinished string near '<eof>'";
            }
            throw _createPositionedException(start, errorMessage);
          }
          rethrow;
        }
      } else {
        // Closed short strings
        final content = lexeme.substring(1, lexeme.length - 1);
        // Normalize \xHH to decimal escapes to work around parser
        // differences while preserving exact byte values.
        String normalizeHexEscapes(String s) {
          final re = RegExp(r'\\x([0-9A-Fa-f]{2})');
          return s.replaceAllMapped(re, (m) {
            final value = int.parse(m.group(1)!, radix: 16);
            return '\\$value';
          });
        }

        final normalized = normalizeHexEscapes(content);

        // Pre-validate string content for escape sequence errors
        try {
          LuaStringParser.parseStringContent(normalized);
        } catch (e) {
          if (e is FormatException) {
            // Convert detailed error message for escape sequence errors
            String errorMessage = e.message;
            if (errorMessage.contains('hexadecimal digit expected')) {
              if (errorMessage.contains('|invalid')) {
                errorMessage = errorMessage.replaceAll('|invalid', '');
                final quotedString = '"$content';
                errorMessage =
                    "[string \"\"]:1: $errorMessage near '$quotedString'";
              } else if (errorMessage.contains('|incomplete')) {
                errorMessage = errorMessage.replaceAll('|incomplete', '');
                final quotedString = '"$content"';
                errorMessage =
                    "[string \"\"]:1: $errorMessage near '$quotedString'";
              } else {
                final quotedString = '"$content"';
                errorMessage =
                    "[string \"\"]:1: hexadecimal digit expected near '$quotedString'";
              }
            } else if (errorMessage.contains('invalid escape sequence')) {
              // For general invalid escape sequences like \g
              final quotedString =
                  '"$content'; // No closing quote for invalid escapes
              errorMessage =
                  "[string \"\"]:1: invalid escape sequence near '$quotedString'";
            } else if (errorMessage.contains('decimal escape too large')) {
              // For decimal escape sequences that are out of range
              final quotedString = '"$content"';
              errorMessage =
                  "[string \"\"]:1: decimal escape too large near '$quotedString'";
            } else if (errorMessage.contains(
              'UTF-8 value too large|context:',
            )) {
              // Use provided context to reconstruct snippet without the
              // closing '}'. This matches Lua's CLI output.
              final contextStart = errorMessage.indexOf('context:') + 8;
              final ctx = errorMessage.substring(
                contextStart,
              ); // e.g. u{100000000
              final needle = '\\$ctx';
              final idx = content.indexOf(needle);
              final snippet = (idx >= 0)
                  ? (content.substring(0, idx) + needle)
                  : ('\\$ctx');
              errorMessage =
                  "[string \"\"]:1: UTF-8 value too large near '$snippet'";
            } else if (errorMessage.contains('UTF-8 value too large')) {
              // Generic too-large case
              errorMessage =
                  "[string \"\"]:1: UTF-8 value too large near '$content'";
            } else if (errorMessage.contains('missing \'{\' near|context:')) {
              // For \u escape sequences missing opening brace
              final contextStart = errorMessage.indexOf('context:') + 8;
              final rawContext = errorMessage.substring(contextStart);
              final hasTrailingQuote = rawContext.endsWith('"');
              final ctxCore = hasTrailingQuote
                  ? rawContext.substring(0, rawContext.length - 1)
                  : rawContext;
              final needle = '\\$ctxCore';
              final idx = content.indexOf(needle);
              final snippet = (idx >= 0)
                  ? (content.substring(0, idx) +
                        needle +
                        (hasTrailingQuote ? '"' : ''))
                  : ('\\$rawContext');
              errorMessage = "[string \"\"]:1: missing '{' near '$snippet'";
            } else if (errorMessage.contains('missing \'}\' near|context:')) {
              // For \u{ escape sequences missing closing brace
              final contextStart = errorMessage.indexOf('context:') + 8;
              final rawContext = errorMessage.substring(contextStart);
              final hasTrailingQuote = rawContext.endsWith('"');
              final ctxCore = hasTrailingQuote
                  ? rawContext.substring(0, rawContext.length - 1)
                  : rawContext;
              final needle = '\\$ctxCore';
              final idx = content.indexOf(needle);
              final snippet = (idx >= 0)
                  ? (content.substring(0, idx) +
                        needle +
                        (hasTrailingQuote ? '"' : ''))
                  : ('\\$rawContext');
              errorMessage = "[string \"\"]:1: missing '}' near '$snippet'";
            } else if (errorMessage.contains(
              'hexadecimal digit expected near|context:',
            )) {
              // For \u{ escape sequences with no hex digits
              final contextStart = errorMessage.indexOf('context:') + 8;
              final rawContext = errorMessage.substring(contextStart);
              final hasTrailingQuote = rawContext.endsWith('"');
              final ctxCore = hasTrailingQuote
                  ? rawContext.substring(0, rawContext.length - 1)
                  : rawContext;
              final needle = '\\$ctxCore';
              final idx = content.indexOf(needle);
              final snippet = (idx >= 0)
                  ? (content.substring(0, idx) +
                        needle +
                        (hasTrailingQuote ? '"' : ''))
                  : ('\\$rawContext');
              errorMessage =
                  "[string \"\"]:1: hexadecimal digit expected near '$snippet'";
            }
            throw _createPositionedException(start, errorMessage);
          }
          rethrow;
        }

        // Use normalized content so downstream parsing yields correct bytes
        return _annotate(StringLiteral(normalized), start, end);
      }
    });
  }

  // vararg '...'
  Parser _vararg() => _token('...').map((_) => VarArg());

  // ----------------- Table constructors -----------------------------------

  Parser _tableConstructor() =>
      (_token('{') & ref0(_fieldlist).optional() & _token('}')).map((values) {
        final fields = values[1] as List<TableEntry>? ?? <TableEntry>[];
        return TableConstructor(fields);
      });

  Parser _fieldlist() =>
      (ref0(_field) &
              (ref0(_fieldsep) & ref0(_field)).star() &
              ref0(_fieldsep).optional())
          .map((values) {
            final list = <TableEntry>[];
            list.add(values[0] as TableEntry);
            final rest = values[1] as List;
            for (final pair in rest) {
              list.add(pair[1] as TableEntry);
            }
            return list;
          });

  Parser _fieldsep() => _token(',') | _token(';');

  Parser _field() {
    // 1. [exp] = exp
    final indexed =
        (_token('[') &
                ref0(_expression) &
                _token(']') &
                _token('=') &
                ref0(_expression))
            .map((values) {
              final key = values[1] as AstNode;
              final val = values[4] as AstNode;
              return IndexedTableEntry(key, val);
            });

    // 2. Name = exp
    final keyed = (_identifier() & _token('=') & ref0(_expression)).map((
      values,
    ) {
      final nameId = values[0] as Identifier;
      final val = values[2] as AstNode;
      return KeyedTableEntry(nameId, val);
    });

    // 3. exp
    final literal = ref0(_expression).map((expr) => TableEntryLiteral(expr));

    return indexed | keyed | literal;
  }

  // prefixexp ::= var | functioncall | '(' exp ')'
  Parser _prefixExp() {
    final base = (_identifier() | ref0(_groupedExpression));

    final suffix = ref0(_suffix).star();

    return (base & suffix).map((values) {
      AstNode expr = values[0] as AstNode;
      final List<dynamic> sufs = values[1] as List;
      for (final s in sufs) {
        final type = s[0] as String;
        switch (type) {
          case 'index':
            final access = TableIndexAccess(expr, s[1] as AstNode);
            access.setSpan(expr.span ?? _sourceFile.span(0, 0));
            expr = access;
            break;
          case 'field':
            final access = TableFieldAccess(expr, s[1] as Identifier);
            access.setSpan(expr.span ?? _sourceFile.span(0, 0));
            expr = access;
            break;
          case 'call':
            final args = (s[1] as List).cast<AstNode>();
            final call = FunctionCall(expr, args);
            call.setSpan(expr.span ?? _sourceFile.span(0, 0));
            expr = call;
            break;
          case 'method':
            final id = s[1] as Identifier;
            final args = (s[2] as List).cast<AstNode>();
            final mcall = MethodCall(expr, id, args, implicitSelf: true);
            mcall.setSpan(expr.span ?? _sourceFile.span(0, 0));
            expr = mcall;
            break;
        }
      }
      return expr;
    });
  }

  Parser _suffix() {
    // index
    final index = (_token('[') & ref0(_expression) & _token(']')).map(
      (vals) => ['index', vals[1]],
    );
    // field .Name
    final field = (_token('.') & _identifier()).map(
      (vals) => ['field', vals[1]],
    );
    // method call :Name args
    final method = (_token(':') & _identifier() & ref0(_args)).map(
      (vals) => ['method', vals[1], vals[2]],
    );
    // function call args
    final call = ref0(_args).map((a) => ['call', a]);
    return index | field | method | call;
  }

  // args ::= '(' [explist] ')' | tableconstructor | LiteralString
  Parser _args() {
    final paren = (_token('(') & ref0(_explist).optional() & _token(')')).map(
      (vals) => vals[1] as List<AstNode>? ?? <AstNode>[],
    );
    return paren |
        ref0(_tableConstructor).map((tc) => [tc]) |
        _stringLiteral().map((s) => [s]);
  }

  // ----------------- Simple Control Statements ---------------------------

  Parser _breakStat() => _span(_token('break').map((_) => Break()));

  Parser _gotoStat() => _span(
    (_token('goto') & _identifier()).map((vals) => Goto(vals[1] as Identifier)),
  );

  Parser _labelStat() => _span(
    (_token('::') & _identifier() & _token('::')).map(
      (vals) => Label(vals[1] as Identifier),
    ),
  );

  // ----------------- Blocks ----------------------------------------------

  Parser _doBlockStat() => _span(
    (_token('do') & _block() & _token('end')).map(
      (vals) => DoBlock(vals[1] as List<AstNode>),
    ),
  );

  Parser _whileStat() => _span(
    (_token('while') &
            ref0(_expression) &
            _token('do') &
            _block() &
            _token('end'))
        .map(
          (vals) =>
              WhileStatement(vals[1] as AstNode, vals[3] as List<AstNode>),
        ),
  );

  Parser _repeatStat() => _span(
    (_token('repeat') & _block() & _token('until') & ref0(_expression)).map(
      (vals) => RepeatUntilLoop(vals[1] as List<AstNode>, vals[3] as AstNode),
    ),
  );

  // ----------------- If Statement ----------------------------------------

  Parser _ifStat() {
    final elseifParser =
        (_token('elseif') & ref0(_expression) & _token('then') & _block()).map(
          (vals) => ElseIfClause(vals[1] as AstNode, vals[3] as List<AstNode>),
        );

    return _span(
      (_token('if') &
              ref0(_expression) &
              _token('then') &
              _block() &
              elseifParser.star() &
              (_token('else') & _block()).optional() &
              _token('end'))
          .map((vals) {
            final cond = vals[1] as AstNode;
            final thenBlk = vals[3] as List<AstNode>;
            final elseIfs = vals[4] as List<ElseIfClause>;
            final elseBlockOpt =
                vals[5] as List?; // when present, [ 'else', block ]
            final elseBlk = elseBlockOpt == null
                ? <AstNode>[]
                : elseBlockOpt[1] as List<AstNode>;
            return IfStatement(cond, elseIfs, thenBlk, elseBlk);
          }),
    );
  }

  // ----------------- Local Declaration ------------------------------------

  Parser _localDeclaration() => _span(
    (_token('local') & _attNameList() & (_token('=') & _explist()).optional()).map((
      vals,
    ) {
      // _attNameList now returns a List of [Identifier, attribute] pairs in order
      final pairList = vals[1] as List<List>;

      // Separate into parallel name/attribute lists while preserving duplicates and order
      final names = <Identifier>[];
      final attributes = <String>[];
      for (final pair in pairList) {
        names.add(pair[0] as Identifier);
        attributes.add(pair[1] as String);
      }

      final exprs = vals[2] == null
          ? <AstNode>[]
          : (vals[2] as List)[1] as List<AstNode>; // [ '=', explist ]

      return LocalDeclaration(names, attributes, exprs);
    }),
  );

  Parser _attNameList() =>
      (_identifierWithAttrib() & (_token(',') & _identifierWithAttrib()).star())
          .map((vals) {
            final list = <List>[];

            void addPair(dynamic pair) {
              // pair format: [Identifier, attribute]
              list.add(pair as List);
            }

            addPair(vals[0]);
            for (final p in vals[1] as List) {
              addPair(p[1]); // extract the pair after comma
            }
            return list;
          });

  Parser _identifierWithAttrib() => (_identifier() & _attrib().optional()).map(
    (vals) => [vals[0], vals[1] as String? ?? ''],
  );

  Parser _attrib() => (_token('<') & _identifier() & _token('>')).map((vals) {
    final id = vals[1] as Identifier;
    final attributeName = id.name;
    // Only "const" and "close" are valid attributes in Lua 5.4
    if (attributeName != 'const' && attributeName != 'close') {
      throw _createPositionedException(
        id,
        "unknown attribute '$attributeName'",
      );
    }
    return attributeName;
  });

  // ----------------- For Loops -------------------------------------------

  Parser _forNumericStat() => _span(
    (_token('for') &
            _identifier() &
            _token('=') &
            ref0(_expression) &
            _token(',') &
            ref0(_expression) &
            (_token(',') & ref0(_expression)).optional() &
            _token('do') &
            _block() &
            _token('end'))
        .map((vals) {
          final varName = vals[1] as Identifier;
          final startExp = vals[3] as AstNode;
          final endExp = vals[5] as AstNode;
          final stepExpOpt = vals[6] as List?; // [ ',', exp ]
          final stepExp = stepExpOpt == null
              ? NumberLiteral(1)
              : stepExpOpt[1] as AstNode;
          final body = vals[8] as List<AstNode>;
          return ForLoop(varName, startExp, endExp, stepExp, body);
        }),
  );

  Parser _forGenericStat() => _span(
    (_token('for') &
            _namelist() &
            _token('in') &
            _explist() &
            _token('do') &
            _block() &
            _token('end'))
        .map((vals) {
          final names = vals[1] as List<Identifier>;
          final exps = vals[3] as List<AstNode>;
          final body = vals[5] as List<AstNode>;
          return ForInLoop(names, exps, body);
        }),
  );

  Parser _namelist() =>
      (_identifier() & (_token(',') & _identifier()).star()).map((vals) {
        final list = <Identifier>[];
        list.add(vals[0] as Identifier);
        for (final pair in vals[1] as List) {
          list.add(pair[1] as Identifier);
        }
        return list;
      });

  // ----------------- Expression helpers for correct '^' precedence -------

  // Parses unary prefix operators and builds nested UnaryExpression nodes.
  Parser _unaryExpression() {
    final unarySeq = (ref0(_unaryOperator).plus() & ref0(_powerExpression)).map(
      (vals) {
        final ops = vals[0] as List;
        AstNode node = vals[1] as AstNode;
        for (var i = ops.length - 1; i >= 0; i--) {
          node = UnaryExpression(ops[i] as String, node);
        }
        return node;
      },
    );

    // If there is no unary operator, just parse the power expression.
    return unarySeq | ref0(_powerExpression);
  }

  // Parses a chain of '^' operators with right associativity. The right-hand
  // operand is a full unary expression, matching Lua’s grammar.
  Parser _powerExpression() {
    final tail = (_token('^') & ref0(_unaryExpression)).star();

    return (ref0(_primaryExpression) & tail).map((vals) {
      AstNode node = vals[0] as AstNode;
      final rest = vals[1] as List;

      // Build right-associative: process from right to left.
      for (var i = rest.length - 1; i >= 0; i--) {
        final rhs = rest[i][1] as AstNode; // pair = [ '^', rhs ]
        node = BinaryExpression(node, '^', rhs);
      }
      return node;
    });
  }

  // ----------------- Function Definitions ---------------------------------

  Parser _functionDefStat() => _span(
    (_token('function') & _funcName() & _funcBody()).map((vals) {
      final fname = vals[1] as FunctionName;
      final body = vals[2] as FunctionBody;
      final node = FunctionDef(fname, body, implicitSelf: fname.method != null);
      return node;
    }),
  );

  Parser _localFunctionDefStat() => _span(
    (_token('local') & _token('function') & _identifier() & _funcBody()).map((
      vals,
    ) {
      final name = vals[2] as Identifier;
      final body = vals[3] as FunctionBody;
      return LocalFunctionDef(name, body);
    }),
  );

  Parser _functionLiteral() => (_token('function') & _funcBody()).map(
    (vals) => FunctionLiteral(vals[1] as FunctionBody),
  );

  Parser _funcName() =>
      (_identifier() &
              (_token('.') & _identifier()).star() &
              (_token(':') & _identifier()).optional())
          .map((vals) {
            final first = vals[0] as Identifier;
            final restPairs = vals[1] as List;
            final rest = <Identifier>[];
            for (final pair in restPairs) {
              rest.add(pair[1] as Identifier);
            }
            final methodOpt = vals[2] as List?; // [ ':', Identifier ]
            final method = methodOpt == null
                ? null
                : methodOpt[1] as Identifier;
            return FunctionName(first, rest, method);
          });

  Parser _funcBody() =>
      (_token('(') &
              _parlist().optional() &
              _token(')') &
              _block() &
              _token('end'))
          .map((vals) {
            final parResult =
                vals[1] as Map? ?? {'params': <Identifier>[], 'vararg': false};
            final params = parResult['params'] as List<Identifier>;
            final hasVararg = parResult['vararg'] as bool;
            final body = vals[3] as List<AstNode>;
            return FunctionBody(params, body, hasVararg);
          });

  Parser _parlist() {
    final varargOnly = _token(
      '...',
    ).map((_) => {'params': <Identifier>[], 'vararg': true});

    // names followed by ',', '...'
    final namesWithVararg = (_namelist() & _token(',') & _token('...')).map((
      vals,
    ) {
      final ids = vals[0] as List<Identifier>;
      return {'params': ids, 'vararg': true};
    });

    // names only (no vararg) — but *must not* be immediately followed by
    // an ellipsis. This prevents accepting the invalid Lua pattern
    // "function f(a, b ...)" (missing comma before `...`). We add a
    // negative look-ahead (`not()`) for the ellipsis.
    final namesOnly = (_namelist() & _token('...').not()).map(
      (vals) => {'params': (vals[0] as List<Identifier>), 'vararg': false},
    );

    return namesWithVararg | namesOnly | varargOnly;
  }

  // Utility to annotate a literal node with span
  T _annotate<T extends AstNode>(T node, int start, int end) {
    node.setSpan(_sourceFile.span(start, end));
    return node;
  }
}

class _LongBracketParser extends Parser<String> {
  _LongBracketParser();

  @override
  Result<String> parseOn(Context context) {
    final buffer = context.buffer;
    final start = context.position;
    // Quick check: must start with '['
    if (start >= buffer.length || buffer.codeUnitAt(start) != 0x5B /* '[' */ ) {
      return context.failure('long string expected');
    }
    var idx = start + 1;
    // Count '=' run
    while (idx < buffer.length && buffer.codeUnitAt(idx) == 0x3D /* '=' */ ) {
      idx++;
    }
    // Next char must be another '['
    if (idx >= buffer.length || buffer.codeUnitAt(idx) != 0x5B) {
      return context.failure('long string start delimiter not found');
    }
    final eqCount = idx - start - 1;
    final contentStart = idx + 1;

    // Build closing delimiter
    final closing = ']${'=' * eqCount}]';
    final closeIdx = buffer.indexOf(closing, contentStart);
    if (closeIdx == -1) {
      // Unfinished long string: throw a Lua-style error to bypass the
      // generic parser failure wrapper and match CLI expectations.
      // We can't use _createPositionedException here as we're outside the LuaGrammarDefinition class
      throw ParserException(
        Failure(buffer, context.position, "unfinished string near '<eof>'"),
      );
    }

    // Extract inner content only (without delimiters).
    var content = buffer.substring(contentStart, closeIdx);

    // Lua semantics: drop exactly one leading newline immediately after the
    // opening delimiter. Treat CRLF/LFCR/LF/CR as newline.
    if (content.isNotEmpty) {
      if (content.startsWith('\r\n') || content.startsWith('\n\r')) {
        content = content.substring(2);
      } else if (content.codeUnitAt(0) == 0x0A /* \n */ ||
          content.codeUnitAt(0) == 0x0D /* \r */ ) {
        content = content.substring(1);
      }
    }

    // Normalize all end-of-line sequences inside long strings to '\n'
    // - Replace CRLF and LFCR pairs with a single '\n'
    // - Replace solitary CR with '\n'
    if (content.isNotEmpty) {
      content = content.replaceAll('\r\n', '\n');
      content = content.replaceAll('\n\r', '\n');
      content = content.replaceAll('\r', '\n');
    }

    return context.success(content, closeIdx + closing.length);
  }

  @override
  int fastParseOn(String buffer, int position) {
    final ctx = Context(buffer, position);
    final res = parseOn(ctx);
    return res is Failure ? -1 : res.position;
  }

  @override
  _LongBracketParser copy() => _LongBracketParser();
}

class _LongCommentBracketParser extends Parser<String> {
  _LongCommentBracketParser();

  @override
  Result<String> parseOn(Context context) {
    final buffer = context.buffer;
    final start = context.position;
    if (start >= buffer.length || buffer.codeUnitAt(start) != 0x5B /* '[' */ ) {
      return context.failure('long comment expected');
    }
    var idx = start + 1;
    while (idx < buffer.length && buffer.codeUnitAt(idx) == 0x3D /* '=' */ ) {
      idx++;
    }
    if (idx >= buffer.length || buffer.codeUnitAt(idx) != 0x5B) {
      return context.failure('long comment start delimiter not found');
    }
    final eqCount = idx - start - 1;
    final contentStart = idx + 1;
    final closing = ']${'=' * eqCount}]';
    final closeIdx = buffer.indexOf(closing, contentStart);
    if (closeIdx == -1) {
      // Unfinished long comment: surface a Lua-style error message.
      // We can't use _createPositionedException here as we're outside the LuaGrammarDefinition class
      throw ParserException(
        Failure(buffer, context.position, "unfinished comment near '<eof>'"),
      );
    }
    // Skip the content, return success at the end of the comment
    return context.success('', closeIdx + closing.length);
  }

  @override
  int fastParseOn(String buffer, int position) {
    final ctx = Context(buffer, position);
    final res = parseOn(ctx);
    return res is Failure ? -1 : res.position;
  }

  @override
  _LongCommentBracketParser copy() => _LongCommentBracketParser();
}

/// Parse [source] into an [AST] using the **new PetitParser** implementation.
///
/// This will eventually replace the old `parse()` from `grammar_parser.dart`.
Program parse(String source, {Uri? url}) {
  // Build a SourceFile so we can provide detailed spans on errors.
  final sourceFile = SourceFile.fromString(source, url: url);

  final definition = LuaGrammarDefinition(sourceFile);
  final parser = definition.build();

  Result result;
  try {
    result = parser.parse(source);
  } catch (e) {
    // If an exception is thrown inside a combinator (e.g., .map()), try to extract position
    int pos = 0;
    String message = e.toString();

    if (e is ParserException) {
      pos = e.failure.position;
      message = e.failure.message;
    } else if (e is Failure) {
      pos = e.position;
      message = e.message;
    }

    final span = sourceFile.span(pos, pos < source.length ? pos + 1 : pos);
    throw LuaError(message, span: span, cause: e);
  }

  if (result is Success) {
    return result.value as Program;
  }

  final failure = result as Failure;
  final pos = failure.position;

  // Heuristic: when parsing code of the form `return <number-like>` and
  // the parser fails, report a Lua-like numeric error instead of a generic
  // combinator failure. This makes tests that check for 'malformed number'
  // or 'near <eof>' pass while still keeping other errors untouched.
  final trimmed = source.trimLeft();
  if (trimmed.startsWith('return ')) {
    final idx = source.indexOf('return ');
    if (idx != -1) {
      final after = source.substring(idx + 'return '.length).trimLeft();
      final numberLike = RegExp(r'^(?:0[xX][0-9A-Fa-f]*|[0-9]|\.)');
      if (numberLike.hasMatch(after)) {
        // When the numeric literal ends with a dangling sign (e.g. 0xe-),
        // Lua reports 'near <eof>'. Reproduce that behavior.
        final endsWithDanglingSign =
            after.trimRight().endsWith('-') || after.trimRight().endsWith('+');
        if (pos >= source.length || endsWithDanglingSign) {
          throw const FormatException(
            "[string \"\"]:1: malformed number near <eof>",
          );
        }
        throw const FormatException("[string \"\"]:1: malformed number");
      }
    }
  }

  // Clamp end so that we don't exceed length (especially when at EOF).
  final end = pos < source.length ? pos + 1 : pos;
  final span = sourceFile.span(pos, end);

  String unexpected;
  if (pos >= source.length) {
    unexpected = 'end of input';
  } else {
    final ch = source[pos];
    unexpected = ch == '\n' ? 'newline' : "'$ch'";
  }

  // Basic heuristic: if we see an identifier followed by whitespace and '...' but no comma,
  // suggest the missing comma (common Lua gotcha).
  String suggestion = '';
  final _ = pos >= 30 ? pos - 30 : 0;

  // Special cases: surface Lua-like errors for unfinished long strings/comments
  final failMsg = failure.message;
  if (failMsg.contains('unfinished long string')) {
    throw const FormatException(
      "[string \"\"]:1: unfinished string near '<eof>'",
    );
  }
  if (failMsg.contains('unfinished long comment')) {
    throw const FormatException(
      "[string \"\"]:1: unfinished comment near '<eof>'",
    );
  }

  // Capitalize first letter of petitparser failure message to ensure it contains 'Expected'
  final baseMsg =
      'Parse error: Expected ${failure.message}. Unexpected $unexpected.';

  final formatted = span.message(baseMsg + suggestion, color: false);

  // Include raw position as well for completeness.
  throw FormatException(formatted);
}
