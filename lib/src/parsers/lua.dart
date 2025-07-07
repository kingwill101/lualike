import 'package:petitparser/petitparser.dart';
import 'package:source_span/source_span.dart';

import '../ast.dart';
import '../number.dart';

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

  /// Source file used for span annotations.
  final SourceFile _sourceFile;

  // ---------- Helpers -------------------------------------------------------

  /// Trims surrounding whitespace and comments for a [parser].
  Parser _token(Object parser) {
    final Parser inner = parser is Parser ? parser : string(parser as String);
    // Attach the trim *after* the inner parser so that we keep the actual
    // matched lexeme intact for error reporting.
    return inner.trim(ref0(_whiteSpaceAndComments));
  }

  Parser _whiteSpaceAndComments() =>
      (whitespace() | ref0(_lineComment) | ref0(_longComment)).plus();

  Parser _lineComment() => string('--') & pattern('\n').neg().star();

  // Very loose long-comment matcher "--[[ ... ]]" with nested = markers.
  // This is *not* production-ready yet – it merely prevents the skeleton from
  // choking on Lua test files.  A precise implementation will be added later.
  Parser _longComment() =>
      string('--') & char('[') & char('[').neg().star() & char(']') & char(']');

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

    final decimalNumber = ((decFrac1 | decFrac2 | decInt) & decExp.optional())
        .flatten();

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
  Parser start() => ref0(_chunk).end();

  // chunk ::= block
  Parser _chunk() =>
      ref0(_block).map((stmts) => Program(stmts as List<AstNode>));

  // block ::= {stat} [retstat]
  Parser _block() =>
      (ref0(_stat).star() & ref0(_retstat).optional()).map((values) {
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
      ref0(_returnlessExprStatement);

  // retstat ::= return [explist] [';']
  Parser _retstat() =>
      (_token('return') & ref0(_explist).optional() & _token(';').optional())
          .map((values) {
            final list = values[1] as List<AstNode>? ?? <AstNode>[];
            return ReturnStatement(list);
          });

  // varlist '=' explist
  Parser _assignment() =>
      (ref0(_varlist) & _token('=') & ref0(_explist)).map((values) {
        final targets = values[0] as List<AstNode>;
        final exprs = values[2] as List<AstNode>;
        return Assignment(targets, exprs);
      });

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

    // --- primitives (highest precedence) ---
    builder.primitive(ref0(_primaryExpression));

    // --- exponentiation ^ (right-assoc, higher than unary) ---
    builder.group().right(
      _token('^'),
      (dynamic a, dynamic op, dynamic b) =>
          BinaryExpression(a as AstNode, '^', b as AstNode),
    );

    // --- prefix unary operators (# ~ - not) ---
    builder.group().prefix(
      ref0(_unaryOperator),
      (dynamic op, dynamic a) => UnaryExpression(op as String, a as AstNode),
    );

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
      _token('*') | _token('/') | _token('%') | _token('//');

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
      ref0(_functionLiteral) |
      ref0(_prefixExp) |
      ref0(_numberLiteral) |
      ref0(_booleanLiteral) |
      ref0(_nilLiteral) |
      ref0(_vararg) |
      ref0(_stringLiteral) |
      ref0(_tableConstructor) |
      ref0(_groupedExpression);

  Parser _groupedExpression() =>
      _token('(') &
      ref0(_expression) &
      _token(')').map((values) => GroupedExpression(values[1] as AstNode));

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

  // Returnless expression statement (functioncall or generic expression)
  Parser _returnlessExprStatement() =>
      ref0(_expression).map((expr) => ExpressionStatement(expr));

  // ----------------- Literals ---------------------------------------------

  // String literal (single or double quoted, naive implementation)
  Parser _stringLiteral() {
    final dq = char('"') & pattern('^"').star().flatten() & char('"');
    final sq = char("'") & pattern("^'").star().flatten() & char("'");
    return position()
        .seq((dq | sq).flatten())
        .seq(position())
        .trim(ref0(_whiteSpaceAndComments))
        .map((vals) {
          final start = vals[0] as int;
          final lexeme = vals[1] as String;
          final end = vals[2] as int;
          final content = lexeme.substring(1, lexeme.length - 1);
          return _annotate(StringLiteral(content), start, end);
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
            final access = TableAccessExpr(expr, s[1] as AstNode);
            access.setSpan(expr.span ?? _sourceFile.span(0, 0));
            expr = access;
            break;
          case 'field':
            final access = TableAccessExpr(expr, s[1] as Identifier);
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

  Parser _breakStat() => _token('break').map((_) => Break());

  Parser _gotoStat() => (_token('goto') & _identifier()).map(
    (vals) => Goto(vals[1] as Identifier),
  );

  Parser _labelStat() => (_token('::') & _identifier() & _token('::')).map(
    (vals) => Label(vals[1] as Identifier),
  );

  // ----------------- Blocks ----------------------------------------------

  Parser _doBlockStat() => (_token('do') & _block() & _token('end')).map(
    (vals) => DoBlock(vals[1] as List<AstNode>),
  );

  Parser _whileStat() =>
      (_token('while') &
              ref0(_expression) &
              _token('do') &
              _block() &
              _token('end'))
          .map(
            (vals) =>
                WhileStatement(vals[1] as AstNode, vals[3] as List<AstNode>),
          );

  Parser _repeatStat() =>
      (_token('repeat') & _block() & _token('until') & ref0(_expression)).map(
        (vals) => RepeatUntilLoop(vals[1] as List<AstNode>, vals[3] as AstNode),
      );

  // ----------------- If Statement ----------------------------------------

  Parser _ifStat() {
    final elseifParser =
        (_token('elseif') & ref0(_expression) & _token('then') & _block()).map(
          (vals) => ElseIfClause(vals[1] as AstNode, vals[3] as List<AstNode>),
        );

    return (_token('if') &
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
        });
  }

  // ----------------- Local Declaration ------------------------------------

  Parser _localDeclaration() =>
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
      });

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

  Parser _attrib() => (_token('<') & _identifier() & _token('>')).map(
    (vals) => (vals[1] as Identifier).name,
  );

  // ----------------- For Loops -------------------------------------------

  Parser _forNumericStat() =>
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
          });

  Parser _forGenericStat() =>
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
          });

  Parser _namelist() =>
      (_identifier() & (_token(',') & _identifier()).star()).map((vals) {
        final list = <Identifier>[];
        list.add(vals[0] as Identifier);
        for (final pair in vals[1] as List) {
          list.add(pair[1] as Identifier);
        }
        return list;
      });

  // ----------------- Function Definitions ---------------------------------

  Parser _functionDefStat() =>
      (_token('function') & _funcName() & _funcBody()).map((vals) {
        final fname = vals[1] as FunctionName;
        final body = vals[2] as FunctionBody;
        final node = FunctionDef(
          fname,
          body,
          implicitSelf: fname.method != null,
        );
        return node;
      });

  Parser _localFunctionDefStat() =>
      (_token('local') & _token('function') & _identifier() & _funcBody()).map((
        vals,
      ) {
        final name = vals[2] as Identifier;
        final body = vals[3] as FunctionBody;
        return LocalFunctionDef(name, body);
      });

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

    // names followed by optional comma and '...'
    final namesWithComma =
        (_namelist() & (_token(',') & _token('...')).optional()).map((vals) {
          final ids = vals[0] as List<Identifier>;
          final varargOpt = vals[1] as List?; // [ ',', '...' ]
          return {'params': ids, 'vararg': varargOpt != null};
        });

    // names directly followed by '...' (no comma) – lenient variant to match
    // existing PEG grammar which tolerated missing comma.
    final namesNoComma = (_namelist() & _token('...')).map((vals) {
      final ids = vals[0] as List<Identifier>;
      return {'params': ids, 'vararg': true};
    });

    final names = namesWithComma | namesNoComma;
    return names | varargOnly;
  }

  // Utility to annotate a literal node with span
  T _annotate<T extends AstNode>(T node, int start, int end) {
    node.setSpan(_sourceFile.span(start, end));
    return node;
  }
}

/// Parse [source] into an [AST] using the **new PetitParser** implementation.
///
/// This will eventually replace the old `parse()` from `grammar_parser.dart`.
Program parse(String source, {Uri? url}) {
  final definition = LuaGrammarDefinition(
    SourceFile.fromString(source, url: url),
  );
  final parser = definition.build();
  final result = parser.parse(source);
  if (result is Success) {
    return (result).value as Program;
  } else {
    final failure = result as Failure;
    final position = failure.position;
    throw FormatException('Parse error at $position: ${failure.message}');
  }
}
