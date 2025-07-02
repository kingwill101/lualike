import 'package:source_span/source_span.dart';
import 'ast.dart';
import 'number.dart';

bool _checkAttr(String attr, int start, int end, State state) {
  if (attr == "const" || attr == "close") return true;
  state.error("Invalid attribute '$attr'", start, end, 0);
  return false;
}

Program parse(String source, {Object? url}) {
  final state = State(source);
  final file = SourceFile.fromString(source, url: url);
  final parser = GrammarParser(file);

  final result = parser.parseStart(state);
  if (result == null) {
    throw FormatException(
      state
          .getErrors()
          .map((e) => file.span(e.start, e.end).message(e.message))
          .join('\n'),
    );
  }

  return result.$1;
}

class GrammarParser {
  bool isReserved(String name) {
    const reserved = {
      "function",
      "end",
      "if",
      "else",
      "elseif",
      "local",
      "while",
      "for",
      "repeat",
      "until",
      "return",
      "nil",
      "true",
      "false",
      "and",
      "break",
      "do",
      "goto",
      "in",
      "not",
      "or",
      "then",
    };
    return reserved.contains(name);
  }

  final SourceFile sourceFile;

  GrammarParser(this.sourceFile);

  T _setNodeSpan<T extends AstNode>(T node, int start, int end, State state) {
    node.setSpan(sourceFile.span(start, end));
    return node;
  }

  /// **AdditiveExpression**
  ///
  ///```text
  /// `AstNode`
  /// AdditiveExpression =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   result = MultiplicativeExpression
  ///   @while (*) (
  ///     S
  ///     op = <[+\-]>
  ///     S
  ///     right = MultiplicativeExpression
  ///     {
  ///       result = BinaryExpression(result, op, right);
  ///     }
  ///   )
  ///   $ = {
  ///     $$ = _setNodeSpan(result, startPos, state.position, state);
  ///   }
  ///```
  (AstNode,)? parseAdditiveExpression(State state) {
    final $1 = state.position;
    (AstNode,)? $0;
    final startPos = state.position;
    final $2 = parseMultiplicativeExpression(state);
    if ($2 != null) {
      AstNode result = $2.$1;
      while (true) {
        final $4 = state.position;
        var $3 = false;
        parseS(state);
        final $5 = state.position;
        final $6 = state.peek();
        if ($6 == 43 || $6 == 45) {
          state.position += state.charSize($6);
          final $7 = state.substring($5, state.position);
          String op = $7;
          parseS(state);
          final $8 = parseMultiplicativeExpression(state);
          if ($8 != null) {
            AstNode right = $8.$1;
            result = BinaryExpression(result, op, right);
            $3 = true;
          }
        } else {
          state.fail();
        }
        if (!$3) {
          state.position = $4;
          break;
        }
      }
      final AstNode $$;
      $$ = _setNodeSpan(result, startPos, state.position, state);
      AstNode $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **AndExpression**
  ///
  ///```text
  /// `AstNode`
  /// AndExpression =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   result = ComparisonExpression
  ///   @while (*) (
  ///     S
  ///     'and'
  ///     S
  ///     right = ComparisonExpression
  ///     {
  ///       result = BinaryExpression(result, "and", right);
  ///     }
  ///   )
  ///   $ = {
  ///     $$ = _setNodeSpan(result, startPos, state.position, state);
  ///   }
  ///```
  (AstNode,)? parseAndExpression(State state) {
    final $1 = state.position;
    (AstNode,)? $0;
    final startPos = state.position;
    final $2 = parseComparisonExpression(state);
    if ($2 != null) {
      AstNode result = $2.$1;
      while (true) {
        final $4 = state.position;
        var $3 = false;
        parseS(state);
        final $5 = state.position;
        if (state.peek() == 97 && state.startsWith('and', state.position)) {
          state.consume('and', $5);
          parseS(state);
          final $6 = parseComparisonExpression(state);
          if ($6 != null) {
            AstNode right = $6.$1;
            result = BinaryExpression(result, "and", right);
            $3 = true;
          }
        } else {
          state.expected('and');
        }
        if (!$3) {
          state.position = $4;
          break;
        }
      }
      final AstNode $$;
      $$ = _setNodeSpan(result, startPos, state.position, state);
      AstNode $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **Args**
  ///
  ///```text
  /// `List<AstNode>`
  /// Args =>
  ///   {
  ///     List<AstNode> result = [];
  ///   }
  ///   (
  ///     '('
  ///     S
  ///     exprs = ExpressionList?
  ///     TrailingComma
  ///     ')'
  ///     S
  ///     { result = exprs; }
  ///     ----
  ///     table = TableConstructor
  ///     { result = [table]; }
  ///     ----
  ///     str = String
  ///     { result = [str]; }
  ///   )
  ///   $ = {
  ///     // Args doesn't need _setNodeSpan since it's just returning a list, not an AstNode
  ///     $$ = result;
  ///   }
  ///```
  (List<AstNode>,)? parseArgs(State state) {
    final $1 = state.position;
    (List<AstNode>,)? $0;
    List<AstNode> result = [];
    var $2 = true;
    final $4 = state.position;
    var $3 = false;
    if (state.peek() == 40) {
      state.consume('(', $4);
      parseS(state);
      List<AstNode>? $6;
      final $5 = parseExpressionList(state);
      $6 = $5;
      List<AstNode>? exprs = $6;
      parseTrailingComma(state);
      final $7 = state.position;
      if (state.peek() == 41) {
        state.consume(')', $7);
        parseS(state);
        result = exprs;
        $3 = true;
      } else {
        state.expected(')');
      }
    } else {
      state.expected('(');
    }
    if (!$3) {
      state.position = $4;
      var $8 = false;
      final $9 = parseTableConstructor(state);
      if ($9 != null) {
        TableConstructor table = $9.$1;
        result = [table];
        $8 = true;
      }
      if (!$8) {
        var $10 = false;
        final $11 = parseString(state);
        if ($11 != null) {
          StringLiteral str = $11.$1;
          result = [str];
          $10 = true;
        }
        if (!$10) {
          $2 = false;
        }
      }
    }
    if ($2) {
      final List<AstNode> $$;
      // Args doesn't need _setNodeSpan since it's just returning a list, not an AstNode
      $$ = result;
      List<AstNode> $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **Assignment**
  ///
  ///```text
  /// `Assignment`
  /// Assignment =>
  ///   {
  ///     List<AstNode> targets = [];
  ///     final startPos = state.position;
  ///   }
  ///   first = AssignmentTarget
  ///   { targets.add(first); }
  ///   @while (*) (
  ///     ','
  ///     S
  ///     next = AssignmentTarget
  ///     { targets.add(next); }
  ///   )
  ///   '='
  ///   S
  ///   expr = ExpressionList
  ///   S
  ///   $ = {
  ///     final node = Assignment(targets, expr);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (Assignment,)? parseAssignment(State state) {
    final $1 = state.position;
    (Assignment,)? $0;
    List<AstNode> targets = [];
    final startPos = state.position;
    final $2 = parseAssignmentTarget(state);
    if ($2 != null) {
      AstNode first = $2.$1;
      targets.add(first);
      while (true) {
        final $4 = state.position;
        var $3 = false;
        if (state.peek() == 44) {
          state.consume(',', $4);
          parseS(state);
          final $5 = parseAssignmentTarget(state);
          if ($5 != null) {
            AstNode next = $5.$1;
            targets.add(next);
            $3 = true;
          }
        } else {
          state.expected(',');
        }
        if (!$3) {
          state.position = $4;
          break;
        }
      }
      final $6 = state.position;
      if (state.peek() == 61) {
        state.consume('=', $6);
        parseS(state);
        final $7 = parseExpressionList(state);
        List<AstNode> expr = $7;
        parseS(state);
        final Assignment $$;
        final node = Assignment(targets, expr);
        $$ = _setNodeSpan(node, startPos, state.position, state);
        Assignment $ = $$;
        $0 = ($,);
      } else {
        state.expected('=');
      }
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **AssignmentTarget**
  ///
  ///```text
  /// `AstNode`
  /// AssignmentTarget =>
  ///   (
  ///     target = ComplexTableAccess
  ///     $ = { $$ = target; }
  ///     ----
  ///     target = TableLookup
  ///     $ = { $$ = target; }
  ///     ----
  ///     target = ID
  ///     $ = { $$ = target; }
  ///   )
  ///```
  (AstNode,)? parseAssignmentTarget(State state) {
    (AstNode,)? $0;
    (AstNode,)? $1;
    final $2 = parseComplexTableAccess(state);
    if ($2 != null) {
      AstNode target = $2.$1;
      final AstNode $$;
      $$ = target;
      AstNode $ = $$;
      $1 = ($,);
    }
    if ($1 != null) {
      $0 = $1;
    } else {
      (AstNode,)? $3;
      final $4 = parseTableLookup(state);
      if ($4 != null) {
        AstNode target = $4.$1;
        final AstNode $$;
        $$ = target;
        AstNode $ = $$;
        $3 = ($,);
      }
      if ($3 != null) {
        $0 = $3;
      } else {
        (AstNode,)? $5;
        final $6 = parseID(state);
        if ($6 != null) {
          Identifier target = $6.$1;
          final AstNode $$;
          $$ = target;
          AstNode $ = $$;
          $5 = ($,);
        }
        if ($5 != null) {
          $0 = $5;
        }
      }
    }
    return $0;
  }

  /// **AttributeOpt**
  ///
  ///```text
  /// `String?`
  /// AttributeOpt =>
  ///   '<'
  ///   S
  ///   { final attrStart = state.position; }
  ///   attr = <
  ///     [a-zA-Z_]
  ///     [a-zA-Z0-9_]*
  ///   >
  ///   S
  ///   (
  ///     &{ _checkAttr(attr, attrStart, state.position, state) }
  ///     S
  ///      ~ { message = 'Invalid attribute \$attr' start = end }
  ///   )
  ///   S
  ///   '>'
  ///   S
  ///   $ = { $$ = attr; }
  ///```
  (String?,)? parseAttributeOpt(State state) {
    final $1 = state.position;
    (String?,)? $0;
    if (state.peek() == 60) {
      state.consume('<', $1);
      parseS(state);
      final attrStart = state.position;
      final $2 = state.position;
      var $3 = false;
      final $4 = state.peek();
      if ($4 >= 95 ? $4 <= 95 || $4 >= 97 && $4 <= 122 : $4 >= 65 && $4 <= 90) {
        state.position += state.charSize($4);
        for (
          var c = state.peek();
          c >= 65
              ? c <= 90 || c == 95 || c >= 97 && c <= 122
              : c >= 48 && c <= 57;
        ) {
          state.position += state.charSize(c);
          c = state.peek();
        }
        $3 = true;
      } else {
        state.fail();
      }
      if ($3) {
        final $5 = state.substring($2, state.position);
        String attr = $5;
        parseS(state);
        final $7 = state.failure;
        state.failure = state.position;
        var $6 = false;
        if (_checkAttr(attr, attrStart, state.position, state)) {
          parseS(state);
          $6 = true;
        }
        if ($6) {
          state.failure < $7 ? state.failure = $7 : null;
          parseS(state);
          final $8 = state.position;
          if (state.peek() == 62) {
            state.consume('>', $8);
            parseS(state);
            final String? $$;
            $$ = attr;
            String? $ = $$;
            $0 = ($,);
          } else {
            state.expected('>');
          }
        } else {
          state.error(
            'Invalid attribute \$attr',
            state.position,
            state.failure,
            2,
          );
          state.failure < $7 ? state.failure = $7 : null;
        }
      }
    } else {
      state.expected('<');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **BitwiseExpression**
  ///
  ///```text
  /// `AstNode`
  /// BitwiseExpression =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   result = ShiftExpression
  ///   @while (*) (
  ///     S
  ///     op = <([&~|])>
  ///     S
  ///     right = ShiftExpression
  ///     {
  ///       result = BinaryExpression(result, op, right);
  ///     }
  ///   )
  ///   $ = {
  ///     $$ = _setNodeSpan(result, startPos, state.position, state);
  ///   }
  ///```
  (AstNode,)? parseBitwiseExpression(State state) {
    final $1 = state.position;
    (AstNode,)? $0;
    final startPos = state.position;
    final $2 = parseShiftExpression(state);
    if ($2 != null) {
      AstNode result = $2.$1;
      while (true) {
        final $4 = state.position;
        var $3 = false;
        parseS(state);
        final $5 = state.position;
        final $6 = state.peek();
        if ($6 >= 124 ? $6 <= 124 || $6 == 126 : $6 == 38) {
          state.position += state.charSize($6);
          final $7 = state.substring($5, state.position);
          String op = $7;
          parseS(state);
          final $8 = parseShiftExpression(state);
          if ($8 != null) {
            AstNode right = $8.$1;
            result = BinaryExpression(result, op, right);
            $3 = true;
          }
        } else {
          state.fail();
        }
        if (!$3) {
          state.position = $4;
          break;
        }
      }
      final AstNode $$;
      $$ = _setNodeSpan(result, startPos, state.position, state);
      AstNode $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **Boolean**
  ///
  ///```text
  /// `BooleanLiteral`
  /// Boolean =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   'true'
  ///   !IdChar
  ///   S
  ///   $ = {
  ///     final node = BooleanLiteral(true);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///   ----
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   'false'
  ///   !IdChar
  ///   S
  ///   $ = {
  ///     final node = BooleanLiteral(false);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (BooleanLiteral,)? parseBoolean(State state) {
    final $2 = state.position;
    (BooleanLiteral,)? $0;
    (BooleanLiteral,)? $1;
    final startPos = state.position;
    final $3 = state.position;
    if (state.peek() == 116 && state.startsWith('true', state.position)) {
      state.consume('true', $3);
      final $4 = state.position;
      final $5 = state.predicate;
      state.predicate = true;
      var $7 = true;
      final $6 = parseIdChar(state);
      if ($6 != null) {
        state.failAndBacktrack($4);
        $7 = false;
      }
      state.predicate = $5;
      if ($7) {
        parseS(state);
        final BooleanLiteral $$;
        final node = BooleanLiteral(true);
        $$ = _setNodeSpan(node, startPos, state.position, state);
        BooleanLiteral $ = $$;
        $1 = ($,);
      }
    } else {
      state.expected('true');
    }
    if ($1 != null) {
      $0 = $1;
    } else {
      state.position = $2;
      (BooleanLiteral,)? $8;
      final startPos = state.position;
      final $9 = state.position;
      if (state.peek() == 102 && state.startsWith('false', state.position)) {
        state.consume('false', $9);
        final $10 = state.position;
        final $11 = state.predicate;
        state.predicate = true;
        var $13 = true;
        final $12 = parseIdChar(state);
        if ($12 != null) {
          state.failAndBacktrack($10);
          $13 = false;
        }
        state.predicate = $11;
        if ($13) {
          parseS(state);
          final BooleanLiteral $$;
          final node = BooleanLiteral(false);
          $$ = _setNodeSpan(node, startPos, state.position, state);
          BooleanLiteral $ = $$;
          $8 = ($,);
        }
      } else {
        state.expected('false');
      }
      if ($8 != null) {
        $0 = $8;
      } else {
        state.position = $2;
      }
    }
    return $0;
  }

  /// **Break**
  ///
  ///```text
  /// `Break`
  /// Break =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   'break'
  ///   S
  ///   $ = {
  ///     final node = Break();
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (Break,)? parseBreak(State state) {
    final $1 = state.position;
    (Break,)? $0;
    final startPos = state.position;
    final $2 = state.position;
    if (state.peek() == 98 && state.startsWith('break', state.position)) {
      state.consume('break', $2);
      parseS(state);
      final Break $$;
      final node = Break();
      $$ = _setNodeSpan(node, startPos, state.position, state);
      Break $ = $$;
      $0 = ($,);
    } else {
      state.expected('break');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **ComparisonExpression**
  ///
  ///```text
  /// `AstNode`
  /// ComparisonExpression =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   result = BitwiseExpression
  ///   @while (*) (
  ///     S
  ///     op = <
  ///       (
  ///         '=='
  ///         ----
  ///         '~='
  ///         ----
  ///         '<='
  ///         ----
  ///         '>='
  ///         ----
  ///         '<'
  ///         ----
  ///         '>'
  ///       )
  ///     >
  ///     S
  ///     right = BitwiseExpression
  ///     {
  ///       result = BinaryExpression(result, op, right);
  ///     }
  ///   )
  ///   $ = {
  ///     $$ = _setNodeSpan(result, startPos, state.position, state);
  ///   }
  ///```
  (AstNode,)? parseComparisonExpression(State state) {
    final $1 = state.position;
    (AstNode,)? $0;
    final startPos = state.position;
    final $2 = parseBitwiseExpression(state);
    if ($2 != null) {
      AstNode result = $2.$1;
      while (true) {
        final $4 = state.position;
        var $3 = false;
        parseS(state);
        final $5 = state.position;
        var $6 = true;
        if (state.peek() == 61 && state.startsWith('==', state.position)) {
          state.consume('==', $5);
        } else {
          state.expected('==');
          if (state.peek() == 126 && state.startsWith('~=', state.position)) {
            state.consume('~=', $5);
          } else {
            state.expected('~=');
            if (state.peek() == 60 && state.startsWith('<=', state.position)) {
              state.consume('<=', $5);
            } else {
              state.expected('<=');
              if (state.peek() == 62 &&
                  state.startsWith('>=', state.position)) {
                state.consume('>=', $5);
              } else {
                state.expected('>=');
                if (state.peek() == 60) {
                  state.consume('<', $5);
                } else {
                  state.expected('<');
                  if (state.peek() == 62) {
                    state.consume('>', $5);
                  } else {
                    state.expected('>');
                    $6 = false;
                  }
                }
              }
            }
          }
        }
        if ($6) {
          final $7 = state.substring($5, state.position);
          String op = $7;
          parseS(state);
          final $8 = parseBitwiseExpression(state);
          if ($8 != null) {
            AstNode right = $8.$1;
            result = BinaryExpression(result, op, right);
            $3 = true;
          }
        }
        if (!$3) {
          state.position = $4;
          break;
        }
      }
      final AstNode $$;
      $$ = _setNodeSpan(result, startPos, state.position, state);
      AstNode $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **ComplexTableAccess**
  ///
  ///```text
  /// `AstNode`
  /// ComplexTableAccess =>
  ///   {
  ///     AstNode? expr;
  ///     final startPos = state.position;
  ///   }
  ///   (
  ///     base = ID
  ///     { expr = base; }
  ///     ----
  ///     '('
  ///     S
  ///     base = Expression
  ///     ')'
  ///     S
  ///     { expr = base; }
  ///     ----
  ///     base = FunctionCall
  ///     { expr = base; }
  ///   )
  ///   &{ expr != null }
  ///   @while (+) (
  ///     (
  ///       '['
  ///       S
  ///       idx = Expression
  ///       ']'
  ///       S
  ///       {
  ///         expr = TableAccessExpr(expr!, idx);
  ///       }
  ///       ----
  ///       '.'
  ///       S
  ///       fld = ID
  ///       {
  ///         expr = TableAccessExpr(expr!, fld);
  ///       }
  ///     )
  ///     @while (*) (
  ///       (
  ///         '['
  ///         S
  ///         idx = Expression
  ///         ']'
  ///         S
  ///         {
  ///           expr = TableAccessExpr(expr!, idx);
  ///         }
  ///         ----
  ///         '.'
  ///         S
  ///         fld = ID
  ///         {
  ///           expr = TableAccessExpr(expr!, fld);
  ///         }
  ///       )
  ///     )
  ///   )
  ///   $ = {
  ///     $$ = _setNodeSpan(expr!, startPos, state.position, state);
  ///   }
  ///```
  (AstNode,)? parseComplexTableAccess(State state) {
    final $1 = state.position;
    (AstNode,)? $0;
    AstNode? expr;
    final startPos = state.position;
    var $2 = true;
    var $3 = false;
    final $4 = state.position;
    final $5 = parseID(state);
    if ($5 != null && state.peek() != 40) {
      Identifier base = $5.$1;
      expr = base;
      $3 = true;
    } else {
      state.position = $4;
    }
    if (!$3) {
      final $6 = state.position;
      var $5 = false;
      if (state.peek() == 40) {
        state.consume('(', $6);
        parseS(state);
        final $7 = parseExpression(state);
        if ($7 != null) {
          AstNode base = $7.$1;
          final $8 = state.position;
          if (state.peek() == 41) {
            state.consume(')', $8);
            parseS(state);
            expr = base;
            $5 = true;
          } else {
            state.expected(')');
          }
        }
      } else {
        state.expected('(');
      }
      if (!$5) {
        state.position = $6;
        var $9 = false;
        final $10 = parseFunctionCall(state);
        if ($10 != null) {
          Call base = $10.$1;
          expr = base;
          $9 = true;
        }
        if (!$9) {
          $2 = false;
        }
      }
    }
    if ($2) {
      if (expr != null) {
        final $11 = state.position;
        while (true) {
          var $12 = false;
          var $13 = true;
          final $15 = state.position;
          var $14 = false;
          if (state.peek() == 91) {
            state.consume('[', $15);
            parseS(state);
            final $16 = parseExpression(state);
            if ($16 != null) {
              AstNode idx = $16.$1;
              final $17 = state.position;
              if (state.peek() == 93) {
                state.consume(']', $17);
                parseS(state);
                expr = TableAccessExpr(expr!, idx);
                $14 = true;
              } else {
                state.expected(']');
              }
            }
          } else {
            state.expected('[');
          }
          if (!$14) {
            state.position = $15;
            final $19 = state.position;
            var $18 = false;
            if (state.peek() == 46) {
              state.consume('.', $19);
              parseS(state);
              final $20 = parseID(state);
              if ($20 != null) {
                Identifier fld = $20.$1;
                expr = TableAccessExpr(expr!, fld);
                $18 = true;
              }
            } else {
              state.expected('.');
            }
            if (!$18) {
              state.position = $19;
              $13 = false;
            }
          }
          if ($13) {
            while (true) {
              var $21 = true;
              final $23 = state.position;
              var $22 = false;
              if (state.peek() == 91) {
                state.consume('[', $23);
                parseS(state);
                final $24 = parseExpression(state);
                if ($24 != null) {
                  AstNode idx = $24.$1;
                  final $25 = state.position;
                  if (state.peek() == 93) {
                    state.consume(']', $25);
                    parseS(state);
                    expr = TableAccessExpr(expr!, idx);
                    $22 = true;
                  } else {
                    state.expected(']');
                  }
                }
              } else {
                state.expected('[');
              }
              if (!$22) {
                state.position = $23;
                final $27 = state.position;
                var $26 = false;
                if (state.peek() == 46) {
                  state.consume('.', $27);
                  parseS(state);
                  final $28 = parseID(state);
                  if ($28 != null) {
                    Identifier fld = $28.$1;
                    expr = TableAccessExpr(expr!, fld);
                    $26 = true;
                  }
                } else {
                  state.expected('.');
                }
                if (!$26) {
                  state.position = $27;
                  $21 = false;
                }
              }
              if (!$21) {
                break;
              }
            }
            $12 = true;
          }
          if (!$12) {
            break;
          }
        }
        if ($11 != state.position) {
          final AstNode $$;
          $$ = _setNodeSpan(expr!, startPos, state.position, state);
          AstNode $ = $$;
          $0 = ($,);
        }
      }
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **ConcatExpression**
  ///
  ///```text
  /// `AstNode`
  /// ConcatExpression =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   result = AdditiveExpression
  ///   @while (*) (
  ///     S
  ///     '..'
  ///     S
  ///     right = AdditiveExpression
  ///     {
  ///       result = BinaryExpression(result, "..", right);
  ///     }
  ///   )
  ///   $ = {
  ///     $$ = _setNodeSpan(result, startPos, state.position, state);
  ///   }
  ///```
  (AstNode,)? parseConcatExpression(State state) {
    final $1 = state.position;
    (AstNode,)? $0;
    final startPos = state.position;
    final $2 = parseAdditiveExpression(state);
    if ($2 != null) {
      AstNode result = $2.$1;
      while (true) {
        final $4 = state.position;
        var $3 = false;
        parseS(state);
        final $5 = state.position;
        if (state.peek() == 46 && state.startsWith('..', state.position)) {
          state.consume('..', $5);
          parseS(state);
          final $6 = parseAdditiveExpression(state);
          if ($6 != null) {
            AstNode right = $6.$1;
            result = BinaryExpression(result, "..", right);
            $3 = true;
          }
        } else {
          state.expected('..');
        }
        if (!$3) {
          state.position = $4;
          break;
        }
      }
      final AstNode $$;
      $$ = _setNodeSpan(result, startPos, state.position, state);
      AstNode $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **DirectStringCall**
  ///
  ///```text
  /// `AstNode`
  /// DirectStringCall =>
  ///   {
  ///     AstNode? expr;
  ///     final startPos = state.position;
  ///   }
  ///   name = ID
  ///   (
  ///     '"'
  ///     str = DoubleChars?
  ///     '"'
  ///     {
  ///       final strContent = str;
  ///       expr = FunctionCall(name, [StringLiteral(strContent)]);
  ///     }
  ///     ----
  ///     '\''
  ///     str = SingleChars?
  ///     '\''
  ///     {
  ///       final strContent = str;
  ///       expr = FunctionCall(name, [StringLiteral(strContent)]);
  ///     }
  ///   )
  ///   @while (*) (
  ///     S
  ///     '.'
  ///     S
  ///     fld = ID
  ///     (
  ///       '('
  ///       S
  ///       callArgs = ExpressionList?
  ///       ')'
  ///       S
  ///       {
  ///         expr = FunctionCall(TableAccessExpr(expr!, fld), callArgs );
  ///       }
  ///       ----
  ///       {
  ///         expr = TableAccessExpr(expr!, fld);
  ///       }
  ///     )
  ///   )
  ///   $ = {
  ///     $$ = _setNodeSpan(expr!, startPos, state.position, state);
  ///   }
  ///```
  (AstNode,)? parseDirectStringCall(State state) {
    final $1 = state.position;
    (AstNode,)? $0;
    AstNode? expr;
    final startPos = state.position;
    final $2 = parseID(state);
    if ($2 != null) {
      Identifier name = $2.$1;
      var $3 = true;
      final $5 = state.position;
      var $4 = false;
      if (state.peek() == 34) {
        state.consume('"', $5);
        String? $7;
        final $6 = parseDoubleChars(state);
        $7 = $6;
        String? str = $7;
        final $8 = state.position;
        if (state.peek() == 34) {
          state.consume('"', $8);
          final strContent = str;
          expr = FunctionCall(name, [StringLiteral(strContent)]);
          $4 = true;
        } else {
          state.expected('"');
        }
      } else {
        state.expected('"');
      }
      if (!$4) {
        state.position = $5;
        final $10 = state.position;
        var $9 = false;
        if (state.peek() == 39) {
          state.consume('\'', $10);
          String? $12;
          final $11 = parseSingleChars(state);
          $12 = $11;
          String? str = $12;
          final $13 = state.position;
          if (state.peek() == 39) {
            state.consume('\'', $13);
            final strContent = str;
            expr = FunctionCall(name, [StringLiteral(strContent)]);
            $9 = true;
          } else {
            state.expected('\'');
          }
        } else {
          state.expected('\'');
        }
        if (!$9) {
          state.position = $10;
          $3 = false;
        }
      }
      if ($3) {
        while (true) {
          final $15 = state.position;
          var $14 = false;
          parseS(state);
          final $16 = state.position;
          if (state.peek() == 46) {
            state.consume('.', $16);
            parseS(state);
            final $17 = parseID(state);
            if ($17 != null) {
              Identifier fld = $17.$1;
              var $18 = true;
              final $20 = state.position;
              var $19 = false;
              if (state.peek() == 40) {
                state.consume('(', $20);
                parseS(state);
                List<AstNode>? $22;
                final $21 = parseExpressionList(state);
                $22 = $21;
                List<AstNode>? callArgs = $22;
                final $23 = state.position;
                if (state.peek() == 41) {
                  state.consume(')', $23);
                  parseS(state);
                  expr = FunctionCall(TableAccessExpr(expr!, fld), callArgs);
                  $19 = true;
                } else {
                  state.expected(')');
                }
              } else {
                state.expected('(');
              }
              if (!$19) {
                state.position = $20;
                expr = TableAccessExpr(expr!, fld);
                if (false) {
                  $18 = false;
                }
              }
              if ($18) {
                $14 = true;
              }
            }
          } else {
            state.expected('.');
          }
          if (!$14) {
            state.position = $15;
            break;
          }
        }
        final AstNode $$;
        $$ = _setNodeSpan(expr!, startPos, state.position, state);
        AstNode $ = $$;
        $0 = ($,);
      }
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **DirectStringFunctionCall**
  ///
  ///```text
  /// `ExpressionStatement`
  /// DirectStringFunctionCall =>
  ///   {
  ///     String strContent = '';
  ///     final startPos = state.position;
  ///   }
  ///   name = <ID / TableFieldAccess>
  ///   (
  ///     '"'
  ///     str = DoubleChars?
  ///     '"'
  ///     {
  ///       strContent = str;
  ///     }
  ///     ----
  ///     '\''
  ///     str = SingleChars?
  ///     '\''
  ///     {
  ///       strContent = str;
  ///     }
  ///   )
  ///   {
  ///     final identifier = Identifier(name);
  ///     final stringLit = StringLiteral(strContent);
  ///     AstNode expr = FunctionCall(identifier, [stringLit]);
  ///   }
  ///   @while (*) (
  ///     S
  ///     '.'
  ///     S
  ///     field = ID
  ///     {
  ///       expr = TableAccessExpr(expr, field);
  ///     }
  ///   )
  ///   (
  ///     S
  ///     '('
  ///     S
  ///     callArgs = ExpressionList?
  ///     ')'
  ///     S
  ///     {
  ///       expr = FunctionCall(expr, callArgs);
  ///     }
  ///     ----
  ///     S
  ///     {
  ///     }
  ///   )
  ///   $ = {
  ///     final node = ExpressionStatement(expr);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (ExpressionStatement,)? parseDirectStringFunctionCall(State state) {
    final $1 = state.position;
    (ExpressionStatement,)? $0;
    String strContent = '';
    final startPos = state.position;
    final $2 = state.position;
    var $3 = true;
    final $4 = parseID(state);
    if ($4 == null) {
      final $5 = parseTableFieldAccess(state);
      if ($5 == null) {
        $3 = false;
      }
    }
    if ($3) {
      final $6 = state.substring($2, state.position);
      String name = $6;
      var $7 = true;
      final $9 = state.position;
      var $8 = false;
      if (state.peek() == 34) {
        state.consume('"', $9);
        String? $11;
        final $10 = parseDoubleChars(state);
        $11 = $10;
        String? str = $11;
        final $12 = state.position;
        if (state.peek() == 34) {
          state.consume('"', $12);
          strContent = str;
          $8 = true;
        } else {
          state.expected('"');
        }
      } else {
        state.expected('"');
      }
      if (!$8) {
        state.position = $9;
        final $14 = state.position;
        var $13 = false;
        if (state.peek() == 39) {
          state.consume('\'', $14);
          String? $16;
          final $15 = parseSingleChars(state);
          $16 = $15;
          String? str = $16;
          final $17 = state.position;
          if (state.peek() == 39) {
            state.consume('\'', $17);
            strContent = str;
            $13 = true;
          } else {
            state.expected('\'');
          }
        } else {
          state.expected('\'');
        }
        if (!$13) {
          state.position = $14;
          $7 = false;
        }
      }
      if ($7) {
        final identifier = Identifier(name);
        final stringLit = StringLiteral(strContent);
        AstNode expr = FunctionCall(identifier, [stringLit]);
        while (true) {
          final $19 = state.position;
          var $18 = false;
          parseS(state);
          final $20 = state.position;
          if (state.peek() == 46) {
            state.consume('.', $20);
            parseS(state);
            final $21 = parseID(state);
            if ($21 != null) {
              Identifier field = $21.$1;
              expr = TableAccessExpr(expr, field);
              $18 = true;
            }
          } else {
            state.expected('.');
          }
          if (!$18) {
            state.position = $19;
            break;
          }
        }
        var $22 = true;
        final $24 = state.position;
        var $23 = false;
        parseS(state);
        final $25 = state.position;
        if (state.peek() == 40) {
          state.consume('(', $25);
          parseS(state);
          List<AstNode>? $27;
          final $26 = parseExpressionList(state);
          $27 = $26;
          List<AstNode>? callArgs = $27;
          final $28 = state.position;
          if (state.peek() == 41) {
            state.consume(')', $28);
            parseS(state);
            expr = FunctionCall(expr, callArgs);
            $23 = true;
          } else {
            state.expected(')');
          }
        } else {
          state.expected('(');
        }
        if (!$23) {
          state.position = $24;
          parseS(state);
          if (false) {
            $22 = false;
          }
        }
        if ($22) {
          final ExpressionStatement $$;
          final node = ExpressionStatement(expr);
          $$ = _setNodeSpan(node, startPos, state.position, state);
          ExpressionStatement $ = $$;
          $0 = ($,);
        }
      }
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **DoBlock**
  ///
  ///```text
  /// `DoBlock`
  /// DoBlock =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   'do'
  ///   S
  ///   block = Statements
  ///   'end'
  ///   S
  ///   $ = {
  ///     final node = DoBlock(block);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (DoBlock,)? parseDoBlock(State state) {
    final $1 = state.position;
    (DoBlock,)? $0;
    final startPos = state.position;
    final $2 = state.position;
    if (state.peek() == 100 && state.startsWith('do', state.position)) {
      state.consume('do', $2);
      parseS(state);
      final $3 = parseStatements(state);
      List<AstNode> block = $3;
      final $4 = state.position;
      if (state.peek() == 101 && state.startsWith('end', state.position)) {
        state.consume('end', $4);
        parseS(state);
        final DoBlock $$;
        final node = DoBlock(block);
        $$ = _setNodeSpan(node, startPos, state.position, state);
        DoBlock $ = $$;
        $0 = ($,);
      } else {
        state.expected('end');
      }
    } else {
      state.expected('do');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **DoubleChars**
  ///
  ///```text
  /// `String`
  /// DoubleChars =>
  ///   <
  ///     @while (*) (
  ///       '\\'
  ///       .
  ///       ----
  ///       !'"'
  ///       .
  ///     )
  ///   >
  ///```
  String parseDoubleChars(State state) {
    final $0 = state.position;
    while (true) {
      var $1 = true;
      final $3 = state.position;
      var $2 = false;
      if (state.peek() == 92) {
        state.consume('\\', $3);
        final $4 = state.peek();
        if ($4 != 0) {
          state.position += state.charSize($4);
          $2 = true;
        } else {
          state.fail();
        }
      } else {
        state.expected('\\');
      }
      if (!$2) {
        state.position = $3;
        final $6 = state.position;
        var $5 = false;
        final $7 = state.predicate;
        state.predicate = true;
        var $8 = true;
        if (state.peek() == 34) {
          state.consume('"', $6);
          state.failAndBacktrack($6);
          $8 = false;
        } else {
          state.expected('"');
        }
        state.predicate = $7;
        if ($8) {
          final $9 = state.peek();
          if ($9 != 0) {
            state.position += state.charSize($9);
            $5 = true;
          } else {
            state.fail();
          }
        }
        if (!$5) {
          state.position = $6;
          $1 = false;
        }
      }
      if (!$1) {
        break;
      }
    }
    final $10 = state.substring($0, state.position);
    return $10;
  }

  /// **EOF**
  ///
  ///```text
  /// `void`
  /// EOF =>
  ///   !.
  ///```
  (void,)? parseEOF(State state) {
    if (state.peek() == 0) {
      return const (null,);
    } else {
      state.fail();
      return null;
    }
  }

  /// **ElseIfList**
  ///
  ///```text
  /// `List<ElseIfClause>`
  /// ElseIfList =>
  ///   {
  ///     List<ElseIfClause> clauses = [];
  ///     final startPos = state.position;
  ///   }
  ///   @while (*) (
  ///     'elseif'
  ///     S
  ///     cond = Expression
  ///     S
  ///     'then'
  ///     S
  ///     block = Statements
  ///     {
  ///       final clause = ElseIfClause(cond, block);
  ///       _setNodeSpan(clause, startPos, state.position, state);
  ///       clauses.add(clause);
  ///     }
  ///   )
  ///   $ = {
  ///     $$ = clauses;
  ///   }
  ///```
  List<ElseIfClause> parseElseIfList(State state) {
    List<ElseIfClause> clauses = [];
    final startPos = state.position;
    while (true) {
      final $1 = state.position;
      var $0 = false;
      if (state.peek() == 101 && state.startsWith('elseif', state.position)) {
        state.consume('elseif', $1);
        parseS(state);
        final $2 = parseExpression(state);
        if ($2 != null) {
          AstNode cond = $2.$1;
          parseS(state);
          final $3 = state.position;
          if (state.peek() == 116 && state.startsWith('then', state.position)) {
            state.consume('then', $3);
            parseS(state);
            final $4 = parseStatements(state);
            List<AstNode> block = $4;
            final clause = ElseIfClause(cond, block);
            _setNodeSpan(clause, startPos, state.position, state);
            clauses.add(clause);
            $0 = true;
          } else {
            state.expected('then');
          }
        }
      } else {
        state.expected('elseif');
      }
      if (!$0) {
        state.position = $1;
        break;
      }
    }
    final List<ElseIfClause> $$;
    $$ = clauses;
    List<ElseIfClause> $ = $$;
    return $;
  }

  /// **ExponentiationExpression**
  ///
  ///```text
  /// `AstNode`
  /// ExponentiationExpression =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   left = SimpleExpression
  ///   @while (*) (
  ///     S
  ///     '^'
  ///     S
  ///     right = UnaryExpression
  ///     {
  ///       left = BinaryExpression(left, "^", right);
  ///     }
  ///   )
  ///   $ = {
  ///     $$ = _setNodeSpan(left, startPos, state.position, state);
  ///   }
  ///```
  (AstNode,)? parseExponentiationExpression(State state) {
    final $1 = state.position;
    (AstNode,)? $0;
    final startPos = state.position;
    final $2 = parseSimpleExpression(state);
    if ($2 != null) {
      AstNode left = $2.$1;
      while (true) {
        final $4 = state.position;
        var $3 = false;
        parseS(state);
        final $5 = state.position;
        if (state.peek() == 94) {
          state.consume('^', $5);
          parseS(state);
          final $6 = parseUnaryExpression(state);
          if ($6 != null) {
            AstNode right = $6.$1;
            left = BinaryExpression(left, "^", right);
            $3 = true;
          }
        } else {
          state.expected('^');
        }
        if (!$3) {
          state.position = $4;
          break;
        }
      }
      final AstNode $$;
      $$ = _setNodeSpan(left, startPos, state.position, state);
      AstNode $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **Expression**
  ///
  ///```text
  /// `AstNode`
  /// Expression =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   expr = OrExpression
  ///   $ = {
  ///     $$ = _setNodeSpan(expr, startPos, state.position, state);
  ///   }
  ///```
  (AstNode,)? parseExpression(State state) {
    final $1 = state.position;
    (AstNode,)? $0;
    final startPos = state.position;
    final $2 = parseOrExpression(state);
    if ($2 != null) {
      AstNode expr = $2.$1;
      final AstNode $$;
      $$ = _setNodeSpan(expr, startPos, state.position, state);
      AstNode $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **ExpressionList**
  ///
  ///```text
  /// `List<AstNode>`
  /// ExpressionList =>
  ///   {
  ///     List<AstNode> entries = [];
  ///   }
  ///   (
  ///     first = Expression
  ///     {
  ///       entries.add(first);
  ///     }
  ///     @while (*) (
  ///       ','
  ///       S
  ///       (
  ///         nxt = Expression
  ///         {
  ///           entries.add(nxt);
  ///         }
  ///         ----
  ///         { }
  ///       )
  ///     )
  ///   )?
  ///   TrailingComma?
  ///   $ = {
  ///     $$ = entries;
  ///   }
  ///```
  List<AstNode> parseExpressionList(State state) {
    List<AstNode> entries = [];
    var $0 = false;
    final $1 = parseExpression(state);
    if ($1 != null) {
      AstNode first = $1.$1;
      entries.add(first);
      while (true) {
        var $2 = false;
        final $3 = state.position;
        if (state.peek() == 44) {
          state.consume(',', $3);
          parseS(state);
          var $4 = true;
          var $5 = false;
          final $6 = parseExpression(state);
          if ($6 != null) {
            AstNode nxt = $6.$1;
            entries.add(nxt);
            $5 = true;
          }
          if (!$5) {
            if (false) {
              $4 = false;
            }
          }
          if ($4) {
            $2 = true;
          }
        } else {
          state.expected(',');
        }
        if (!$2) {
          break;
        }
      }
      $0 = true;
    }
    parseTrailingComma(state);
    final List<AstNode> $$;
    $$ = entries;
    List<AstNode> $ = $$;
    return $;
  }

  /// **ExpressionStatement**
  ///
  ///```text
  /// `ExpressionStatement`
  /// ExpressionStatement =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   expr = Expression
  ///   S
  ///   $ = {
  ///     final node = ExpressionStatement(expr);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (ExpressionStatement,)? parseExpressionStatement(State state) {
    final $1 = state.position;
    (ExpressionStatement,)? $0;
    final startPos = state.position;
    final $2 = parseExpression(state);
    if ($2 != null) {
      AstNode expr = $2.$1;
      parseS(state);
      final ExpressionStatement $$;
      final node = ExpressionStatement(expr);
      $$ = _setNodeSpan(node, startPos, state.position, state);
      ExpressionStatement $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **ForInLoop**
  ///
  ///```text
  /// `ForInLoop`
  /// ForInLoop =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   'for'
  ///   !IdChar
  ///   S
  ///   names = NameList
  ///   S
  ///   'in'
  ///   !IdChar
  ///   S
  ///   iterators = ExpressionList
  ///   S
  ///   'do'
  ///   !IdChar
  ///   S
  ///   body = Statements
  ///   'end'
  ///   !IdChar
  ///   S
  ///   $ = {
  ///     final node = ForInLoop(names, iterators, body);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (ForInLoop,)? parseForInLoop(State state) {
    final $1 = state.position;
    (ForInLoop,)? $0;
    final startPos = state.position;
    final $2 = state.position;
    if (state.peek() == 102 && state.startsWith('for', state.position)) {
      state.consume('for', $2);
      final $3 = state.position;
      final $4 = state.predicate;
      state.predicate = true;
      var $6 = true;
      final $5 = parseIdChar(state);
      if ($5 != null) {
        state.failAndBacktrack($3);
        $6 = false;
      }
      state.predicate = $4;
      if ($6) {
        parseS(state);
        final $7 = parseNameList(state);
        if ($7 != null) {
          List<Identifier> names = $7.$1;
          parseS(state);
          final $8 = state.position;
          if (state.peek() == 105 && state.startsWith('in', state.position)) {
            state.consume('in', $8);
            final $9 = state.position;
            final $10 = state.predicate;
            state.predicate = true;
            var $12 = true;
            final $11 = parseIdChar(state);
            if ($11 != null) {
              state.failAndBacktrack($9);
              $12 = false;
            }
            state.predicate = $10;
            if ($12) {
              parseS(state);
              final $13 = parseExpressionList(state);
              List<AstNode> iterators = $13;
              parseS(state);
              final $14 = state.position;
              if (state.peek() == 100 &&
                  state.startsWith('do', state.position)) {
                state.consume('do', $14);
                final $15 = state.position;
                final $16 = state.predicate;
                state.predicate = true;
                var $18 = true;
                final $17 = parseIdChar(state);
                if ($17 != null) {
                  state.failAndBacktrack($15);
                  $18 = false;
                }
                state.predicate = $16;
                if ($18) {
                  parseS(state);
                  final $19 = parseStatements(state);
                  List<AstNode> body = $19;
                  final $20 = state.position;
                  if (state.peek() == 101 &&
                      state.startsWith('end', state.position)) {
                    state.consume('end', $20);
                    final $21 = state.position;
                    final $22 = state.predicate;
                    state.predicate = true;
                    var $24 = true;
                    final $23 = parseIdChar(state);
                    if ($23 != null) {
                      state.failAndBacktrack($21);
                      $24 = false;
                    }
                    state.predicate = $22;
                    if ($24) {
                      parseS(state);
                      final ForInLoop $$;
                      final node = ForInLoop(names, iterators, body);
                      $$ = _setNodeSpan(node, startPos, state.position, state);
                      ForInLoop $ = $$;
                      $0 = ($,);
                    }
                  } else {
                    state.expected('end');
                  }
                }
              } else {
                state.expected('do');
              }
            }
          } else {
            state.expected('in');
          }
        }
      }
    } else {
      state.expected('for');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **ForLoop**
  ///
  ///```text
  /// `ForLoop`
  /// ForLoop =>
  ///   {
  ///     AstNode stepExpr = NumberLiteral(1);
  ///     final startPos = state.position;
  ///   }
  ///   'for'
  ///   !IdChar
  ///   S
  ///   variable = ID
  ///   '='
  ///   S
  ///   start = Expression
  ///   ','
  ///   S
  ///   endExpr = Expression
  ///   (
  ///     ','
  ///     S
  ///     stepVal = Expression
  ///     {
  ///       stepExpr = stepVal;
  ///     }
  ///     ----
  ///     {
  ///       stepExpr = NumberLiteral(1);
  ///     }
  ///   )
  ///   (
  ///     'do'
  ///     S
  ///      ~ { message = 'Expected `do` after for loop' }
  ///   )
  ///   body = Statements
  ///   (
  ///     'end'
  ///     S
  ///      ~ { message = 'Expected `end` to close for loop' }
  ///   )
  ///   $ = {
  ///     final node = ForLoop(variable, start, endExpr, stepExpr, body);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (ForLoop,)? parseForLoop(State state) {
    final $1 = state.position;
    (ForLoop,)? $0;
    AstNode stepExpr = NumberLiteral(1);
    final startPos = state.position;
    final $2 = state.position;
    if (state.peek() == 102 && state.startsWith('for', state.position)) {
      state.consume('for', $2);
      final $3 = state.position;
      final $4 = state.predicate;
      state.predicate = true;
      var $6 = true;
      final $5 = parseIdChar(state);
      if ($5 != null) {
        state.failAndBacktrack($3);
        $6 = false;
      }
      state.predicate = $4;
      if ($6) {
        parseS(state);
        final $7 = parseID(state);
        if ($7 != null) {
          Identifier variable = $7.$1;
          final $8 = state.position;
          if (state.peek() == 61) {
            state.consume('=', $8);
            parseS(state);
            final $9 = parseExpression(state);
            if ($9 != null) {
              AstNode start = $9.$1;
              final $10 = state.position;
              if (state.peek() == 44) {
                state.consume(',', $10);
                parseS(state);
                final $11 = parseExpression(state);
                if ($11 != null) {
                  AstNode endExpr = $11.$1;
                  var $12 = true;
                  final $14 = state.position;
                  var $13 = false;
                  if (state.peek() == 44) {
                    state.consume(',', $14);
                    parseS(state);
                    final $15 = parseExpression(state);
                    if ($15 != null) {
                      AstNode stepVal = $15.$1;
                      stepExpr = stepVal;
                      $13 = true;
                    }
                  } else {
                    state.expected(',');
                  }
                  if (!$13) {
                    state.position = $14;
                    stepExpr = NumberLiteral(1);
                    if (false) {
                      $12 = false;
                    }
                  }
                  if ($12) {
                    final $18 = state.failure;
                    state.failure = state.position;
                    var $16 = false;
                    final $17 = state.position;
                    if (state.peek() == 100 &&
                        state.startsWith('do', state.position)) {
                      state.consume('do', $17);
                      parseS(state);
                      $16 = true;
                    } else {
                      state.expected('do');
                    }
                    if ($16) {
                      state.failure < $18 ? state.failure = $18 : null;
                      final $19 = parseStatements(state);
                      List<AstNode> body = $19;
                      final $22 = state.failure;
                      state.failure = state.position;
                      var $20 = false;
                      final $21 = state.position;
                      if (state.peek() == 101 &&
                          state.startsWith('end', state.position)) {
                        state.consume('end', $21);
                        parseS(state);
                        $20 = true;
                      } else {
                        state.expected('end');
                      }
                      if ($20) {
                        state.failure < $22 ? state.failure = $22 : null;
                        final ForLoop $$;
                        final node = ForLoop(
                          variable,
                          start,
                          endExpr,
                          stepExpr,
                          body,
                        );
                        $$ = _setNodeSpan(
                          node,
                          startPos,
                          state.position,
                          state,
                        );
                        ForLoop $ = $$;
                        $0 = ($,);
                      } else {
                        state.error(
                          'Expected `end` to close for loop',
                          state.position,
                          state.failure,
                          3,
                        );
                        state.failure < $22 ? state.failure = $22 : null;
                      }
                    } else {
                      state.error(
                        'Expected `do` after for loop',
                        state.position,
                        state.failure,
                        3,
                      );
                      state.failure < $18 ? state.failure = $18 : null;
                    }
                  }
                }
              } else {
                state.expected(',');
              }
            }
          } else {
            state.expected('=');
          }
        }
      }
    } else {
      state.expected('for');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **FunctionBody**
  ///
  ///```text
  /// `FunctionBody`
  /// FunctionBody =>
  ///   {
  ///     final startPos = state.position;
  ///     List<Identifier> params = [];
  ///     bool hasVararg = false;
  ///     bool implicitSelf = false;
  ///   }
  ///   '('
  ///   S
  ///   paramResult = ParameterList?
  ///   {
  ///     params = paramResult.$1;
  ///     hasVararg = paramResult.$2;
  ///   }
  ///   ')'
  ///   S
  ///   body = Statements
  ///   'end'
  ///   S
  ///   $ = {
  ///     final node = FunctionBody(params, body, hasVararg, implicitSelf: implicitSelf);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (FunctionBody,)? parseFunctionBody(State state) {
    final $1 = state.position;
    (FunctionBody,)? $0;
    final startPos = state.position;
    List<Identifier> params = [];
    bool hasVararg = false;
    bool implicitSelf = false;
    final $2 = state.position;
    if (state.peek() == 40) {
      state.consume('(', $2);
      parseS(state);
      (List<Identifier>, bool)? $4;
      final $3 = parseParameterList(state);
      $4 = $3;
      (List<Identifier>, bool)? paramResult = $4;
      params = paramResult.$1;
      hasVararg = paramResult.$2;
      final $5 = state.position;
      if (state.peek() == 41) {
        state.consume(')', $5);
        parseS(state);
        final $6 = parseStatements(state);
        List<AstNode> body = $6;
        final $7 = state.position;
        if (state.peek() == 101 && state.startsWith('end', state.position)) {
          state.consume('end', $7);
          parseS(state);
          final FunctionBody $$;
          final node = FunctionBody(
            params,
            body,
            hasVararg,
            implicitSelf: implicitSelf,
          );
          $$ = _setNodeSpan(node, startPos, state.position, state);
          FunctionBody $ = $$;
          $0 = ($,);
        } else {
          state.expected('end');
        }
      } else {
        state.expected(')');
      }
    } else {
      state.expected('(');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **FunctionCall**
  ///
  ///```text
  /// `Call`
  /// FunctionCall =>
  ///   {
  ///     Call? call;
  ///     AstNode? prefix;
  ///     final startPos = state.position;
  ///   }
  ///   (
  ///     pref = TableFieldAccess
  ///     {
  ///       prefix = pref;
  ///     }
  ///     ----
  ///     pref = ID
  ///     {
  ///       prefix = pref;
  ///     }
  ///   )
  ///   (
  ///     args = Args
  ///     {
  ///       call = FunctionCall(prefix!, args);
  ///     }
  ///     ----
  ///     ':'
  ///     S
  ///     methodName = ID
  ///     S
  ///     args = Args
  ///     {
  ///       call = MethodCall(prefix!, methodName, args, implicitSelf: true);
  ///     }
  ///     ----
  ///     '.'
  ///     S
  ///     methodName = ID
  ///     S
  ///     args = Args
  ///     {
  ///       call = MethodCall(prefix!, methodName, args, implicitSelf: true);
  ///     }
  ///   )
  ///   $ = {
  ///     $$ = _setNodeSpan(call!, startPos, state.position, state);
  ///   }
  ///```
  (Call,)? parseFunctionCall(State state) {
    final $1 = state.position;
    (Call,)? $0;
    Call? call;
    AstNode? prefix;
    final startPos = state.position;
    var $2 = true;
    var $3 = false;
    final $4 = parseTableFieldAccess(state);
    if ($4 != null) {
      AstNode pref = $4.$1;
      prefix = pref;
      $3 = true;
    }
    if (!$3) {
      var $5 = false;
      final $6 = parseID(state);
      if ($6 != null) {
        Identifier pref = $6.$1;
        prefix = pref;
        $5 = true;
      }
      if (!$5) {
        $2 = false;
      }
    }
    if ($2) {
      var $7 = true;
      var $8 = false;
      final $9 = parseArgs(state);
      if ($9 != null) {
        List<AstNode> args = $9.$1;
        call = FunctionCall(prefix!, args);
        $8 = true;
      }
      if (!$8) {
        final $11 = state.position;
        var $10 = false;
        if (state.peek() == 58) {
          state.consume(':', $11);
          parseS(state);
          final $12 = parseID(state);
          if ($12 != null) {
            Identifier methodName = $12.$1;
            parseS(state);
            final $13 = parseArgs(state);
            if ($13 != null) {
              List<AstNode> args = $13.$1;
              call = MethodCall(prefix!, methodName, args, implicitSelf: true);
              $10 = true;
            }
          }
        } else {
          state.expected(':');
        }
        if (!$10) {
          state.position = $11;
          final $15 = state.position;
          var $14 = false;
          if (state.peek() == 46) {
            state.consume('.', $15);
            parseS(state);
            final $16 = parseID(state);
            if ($16 != null) {
              Identifier methodName = $16.$1;
              parseS(state);
              final $17 = parseArgs(state);
              if ($17 != null) {
                List<AstNode> args = $17.$1;
                call = MethodCall(
                  prefix!,
                  methodName,
                  args,
                  implicitSelf: true,
                );
                $14 = true;
              }
            }
          } else {
            state.expected('.');
          }
          if (!$14) {
            state.position = $15;
            $7 = false;
          }
        }
      }
      if ($7) {
        final Call $$;
        $$ = _setNodeSpan(call!, startPos, state.position, state);
        Call $ = $$;
        $0 = ($,);
      }
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **FunctionCallWithTableAccess**
  ///
  ///```text
  /// `AstNode`
  /// FunctionCallWithTableAccess =>
  ///   {
  ///     AstNode? baseExpr;
  ///     final startPos = state.position;
  ///   }
  ///   (
  ///     base = FunctionCall
  ///     { baseExpr = base; }
  ///     ----
  ///     base = TableFieldAccess
  ///     { baseExpr = base; }
  ///     ----
  ///     base = TableLookup
  ///     { baseExpr = base; }
  ///     ----
  ///     base = ID
  ///     { baseExpr = base; }
  ///     ----
  ///     '('
  ///     S
  ///     expr = Expression
  ///     ')'
  ///     S
  ///     { baseExpr = expr; }
  ///   )
  ///   &{ baseExpr != null }
  ///   @while (+) (
  ///     (
  ///       '('
  ///       S
  ///       args = ExpressionList?
  ///       ')'
  ///       S
  ///       {
  ///         baseExpr = FunctionCall(baseExpr!, args);
  ///       }
  ///       ----
  ///       '.'
  ///       S
  ///       field = ID
  ///       {
  ///         baseExpr = TableAccessExpr(baseExpr!, field);
  ///       }
  ///       ----
  ///       '['
  ///       S
  ///       index = Expression
  ///       ']'
  ///       S
  ///       {
  ///         baseExpr = TableAccessExpr(baseExpr!, index);
  ///       }
  ///       ----
  ///       ':'
  ///       S
  ///       methodName = ID
  ///       S
  ///       args = Args
  ///       {
  ///         baseExpr = MethodCall(baseExpr!, methodName, args, implicitSelf: true);
  ///       }
  ///     )
  ///   )
  ///   $ = {
  ///     $$ = _setNodeSpan(baseExpr!, startPos, state.position, state);
  ///   }
  ///```
  (AstNode,)? parseFunctionCallWithTableAccess(State state) {
    final $1 = state.position;
    (AstNode,)? $0;
    AstNode? baseExpr;
    final startPos = state.position;
    var $2 = true;
    var $3 = false;
    final $4 = parseFunctionCall(state);
    if ($4 != null) {
      Call base = $4.$1;
      baseExpr = base;
      $3 = true;
    }
    if (!$3) {
      var $5 = false;
      final $6 = parseTableFieldAccess(state);
      if ($6 != null) {
        AstNode base = $6.$1;
        baseExpr = base;
        $5 = true;
      }
      if (!$5) {
        var $7 = false;
        final $8 = parseTableLookup(state);
        if ($8 != null) {
          AstNode base = $8.$1;
          baseExpr = base;
          $7 = true;
        }
        if (!$7) {
          var $9 = false;
          final $10 = parseID(state);
          if ($10 != null) {
            Identifier base = $10.$1;
            baseExpr = base;
            $9 = true;
          }
          if (!$9) {
            final $12 = state.position;
            var $11 = false;
            if (state.peek() == 40) {
              state.consume('(', $12);
              parseS(state);
              final $13 = parseExpression(state);
              if ($13 != null) {
                AstNode expr = $13.$1;
                final $14 = state.position;
                if (state.peek() == 41) {
                  state.consume(')', $14);
                  parseS(state);
                  baseExpr = expr;
                  $11 = true;
                } else {
                  state.expected(')');
                }
              }
            } else {
              state.expected('(');
            }
            if (!$11) {
              state.position = $12;
              $2 = false;
            }
          }
        }
      }
    }
    if ($2) {
      if (baseExpr != null) {
        final $15 = state.position;
        while (true) {
          var $16 = true;
          final $18 = state.position;
          var $17 = false;
          if (state.peek() == 40) {
            state.consume('(', $18);
            parseS(state);
            List<AstNode>? $20;
            final $19 = parseExpressionList(state);
            $20 = $19;
            List<AstNode>? args = $20;
            final $21 = state.position;
            if (state.peek() == 41) {
              state.consume(')', $21);
              parseS(state);
              baseExpr = FunctionCall(baseExpr!, args);
              $17 = true;
            } else {
              state.expected(')');
            }
          } else {
            state.expected('(');
          }
          if (!$17) {
            state.position = $18;
            final $23 = state.position;
            var $22 = false;
            if (state.peek() == 46) {
              state.consume('.', $23);
              parseS(state);
              final $24 = parseID(state);
              if ($24 != null) {
                Identifier field = $24.$1;
                baseExpr = TableAccessExpr(baseExpr!, field);
                $22 = true;
              }
            } else {
              state.expected('.');
            }
            if (!$22) {
              state.position = $23;
              final $26 = state.position;
              var $25 = false;
              if (state.peek() == 91) {
                state.consume('[', $26);
                parseS(state);
                final $27 = parseExpression(state);
                if ($27 != null) {
                  AstNode index = $27.$1;
                  final $28 = state.position;
                  if (state.peek() == 93) {
                    state.consume(']', $28);
                    parseS(state);
                    baseExpr = TableAccessExpr(baseExpr!, index);
                    $25 = true;
                  } else {
                    state.expected(']');
                  }
                }
              } else {
                state.expected('[');
              }
              if (!$25) {
                state.position = $26;
                final $30 = state.position;
                var $29 = false;
                if (state.peek() == 58) {
                  state.consume(':', $30);
                  parseS(state);
                  final $31 = parseID(state);
                  if ($31 != null) {
                    Identifier methodName = $31.$1;
                    parseS(state);
                    final $32 = parseArgs(state);
                    if ($32 != null) {
                      List<AstNode> args = $32.$1;
                      baseExpr = MethodCall(
                        baseExpr!,
                        methodName,
                        args,
                        implicitSelf: true,
                      );
                      $29 = true;
                    }
                  }
                } else {
                  state.expected(':');
                }
                if (!$29) {
                  state.position = $30;
                  $16 = false;
                }
              }
            }
          }
          if (!$16) {
            break;
          }
        }
        if ($15 != state.position) {
          final AstNode $$;
          $$ = _setNodeSpan(baseExpr!, startPos, state.position, state);
          AstNode $ = $$;
          $0 = ($,);
        }
      }
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **FunctionDef**
  ///
  ///```text
  /// `FunctionDef`
  /// FunctionDef =>
  ///   {
  ///     final startPos = state.position;
  ///     bool implicitSelf = false;
  ///   }
  ///   'function'
  ///   !IdChar
  ///   S
  ///   fname = FunctionName
  ///   {
  ///     implicitSelf = fname.method != null;
  ///   }
  ///   funcBody = FunctionBody
  ///   $ = {
  ///     final node = FunctionDef(fname, funcBody, implicitSelf: implicitSelf);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (FunctionDef,)? parseFunctionDef(State state) {
    final $1 = state.position;
    (FunctionDef,)? $0;
    final startPos = state.position;
    bool implicitSelf = false;
    final $2 = state.position;
    if (state.peek() == 102 && state.startsWith('function', state.position)) {
      state.consume('function', $2);
      final $3 = state.position;
      final $4 = state.predicate;
      state.predicate = true;
      var $6 = true;
      final $5 = parseIdChar(state);
      if ($5 != null) {
        state.failAndBacktrack($3);
        $6 = false;
      }
      state.predicate = $4;
      if ($6) {
        parseS(state);
        final $7 = parseFunctionName(state);
        if ($7 != null) {
          FunctionName fname = $7.$1;
          implicitSelf = fname.method != null;
          final $8 = parseFunctionBody(state);
          if ($8 != null) {
            FunctionBody funcBody = $8.$1;
            final FunctionDef $$;
            final node = FunctionDef(
              fname,
              funcBody,
              implicitSelf: implicitSelf,
            );
            $$ = _setNodeSpan(node, startPos, state.position, state);
            FunctionDef $ = $$;
            $0 = ($,);
          }
        }
      }
    } else {
      state.expected('function');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **FunctionLiteral**
  ///
  ///```text
  /// `FunctionLiteral`
  /// FunctionLiteral =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   'function'
  ///   S
  ///   funcBody = FunctionBody
  ///   $ = {
  ///     final node = FunctionLiteral(funcBody);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (FunctionLiteral,)? parseFunctionLiteral(State state) {
    final $1 = state.position;
    (FunctionLiteral,)? $0;
    final startPos = state.position;
    final $2 = state.position;
    if (state.peek() == 102 && state.startsWith('function', state.position)) {
      state.consume('function', $2);
      parseS(state);
      final $3 = parseFunctionBody(state);
      if ($3 != null) {
        FunctionBody funcBody = $3.$1;
        final FunctionLiteral $$;
        final node = FunctionLiteral(funcBody);
        $$ = _setNodeSpan(node, startPos, state.position, state);
        FunctionLiteral $ = $$;
        $0 = ($,);
      }
    } else {
      state.expected('function');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **FunctionName**
  ///
  ///```text
  /// `FunctionName`
  /// FunctionName =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   first = ID
  ///   {
  ///     List<Identifier> rest = [];
  ///   }
  ///   @while (*) (
  ///     '.'
  ///     S
  ///     next = ID
  ///     {
  ///       rest.add(next);
  ///     }
  ///   )
  ///   { Identifier?  method; }
  ///   (
  ///     ':'
  ///     S
  ///     m = ID
  ///     {
  ///       method = m;
  ///     }
  ///   )?
  ///   S
  ///   $ = {
  ///     final node = FunctionName(first, rest, method);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (FunctionName,)? parseFunctionName(State state) {
    final $1 = state.position;
    (FunctionName,)? $0;
    final startPos = state.position;
    final $2 = parseID(state);
    if ($2 != null) {
      Identifier first = $2.$1;
      List<Identifier> rest = [];
      while (true) {
        final $4 = state.position;
        var $3 = false;
        if (state.peek() == 46) {
          state.consume('.', $4);
          parseS(state);
          final $5 = parseID(state);
          if ($5 != null) {
            Identifier next = $5.$1;
            rest.add(next);
            $3 = true;
          }
        } else {
          state.expected('.');
        }
        if (!$3) {
          state.position = $4;
          break;
        }
      }
      Identifier? method;
      final $7 = state.position;
      var $6 = false;
      if (state.peek() == 58) {
        state.consume(':', $7);
        parseS(state);
        final $8 = parseID(state);
        if ($8 != null) {
          Identifier m = $8.$1;
          method = m;
          $6 = true;
        }
      } else {
        state.expected(':');
      }
      if (!$6) {
        state.position = $7;
      }
      parseS(state);
      final FunctionName $$;
      final node = FunctionName(first, rest, method);
      $$ = _setNodeSpan(node, startPos, state.position, state);
      FunctionName $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **Goto**
  ///
  ///```text
  /// `Goto`
  /// Goto =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   'goto'
  ///   S
  ///   name = ID
  ///   S
  ///   $ = {
  ///     final node = Goto(name);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (Goto,)? parseGoto(State state) {
    final $1 = state.position;
    (Goto,)? $0;
    final startPos = state.position;
    final $2 = state.position;
    if (state.peek() == 103 && state.startsWith('goto', state.position)) {
      state.consume('goto', $2);
      parseS(state);
      final $3 = parseID(state);
      if ($3 != null) {
        Identifier name = $3.$1;
        parseS(state);
        final Goto $$;
        final node = Goto(name);
        $$ = _setNodeSpan(node, startPos, state.position, state);
        Goto $ = $$;
        $0 = ($,);
      }
    } else {
      state.expected('goto');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **ID**
  ///
  ///```text
  /// `Identifier`
  /// ID =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   identifier = <
  ///     [a-zA-Z_]
  ///     [a-zA-Z0-9_]*
  ///   >
  ///   !{ isReserved(identifier) }
  ///   S
  ///   $ = {
  ///     final node = Identifier(identifier);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (Identifier,)? parseID(State state) {
    final $1 = state.position;
    (Identifier,)? $0;
    final startPos = state.position;
    final $2 = state.position;
    var $3 = false;
    final $4 = state.peek();
    if ($4 >= 95 ? $4 <= 95 || $4 >= 97 && $4 <= 122 : $4 >= 65 && $4 <= 90) {
      state.position += state.charSize($4);
      for (
        var c = state.peek();
        c >= 65
            ? c <= 90 || c == 95 || c >= 97 && c <= 122
            : c >= 48 && c <= 57;
      ) {
        state.position += state.charSize(c);
        c = state.peek();
      }
      $3 = true;
    } else {
      state.fail();
    }
    if ($3) {
      final $5 = state.substring($2, state.position);
      String identifier = $5;
      final $6 = isReserved(identifier);
      if (!$6) {
        parseS(state);
        final Identifier $$;
        final node = Identifier(identifier);
        $$ = _setNodeSpan(node, startPos, state.position, state);
        Identifier $ = $$;
        $0 = ($,);
      }
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **IdChar**
  ///
  ///```text
  /// `int`
  /// IdChar =>
  ///   [a-zA-Z0-9_]
  ///```
  (int,)? parseIdChar(State state) {
    final $0 = state.peek();
    if ($0 >= 65
        ? $0 <= 90 || $0 == 95 || $0 >= 97 && $0 <= 122
        : $0 >= 48 && $0 <= 57) {
      state.position += state.charSize($0);
      return ($0,);
    } else {
      state.fail();
      return null;
    }
  }

  /// **IfStatement**
  ///
  ///```text
  /// `IfStatement`
  /// IfStatement =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   'if'
  ///   S
  ///   cond = Expression
  ///   S
  ///   'then'
  ///   S
  ///   thenBlock = Statements
  ///   elseifs = ElseIfList?
  ///   { List<AstNode> elseBlock = [];}
  ///   (
  ///     'else'
  ///     S
  ///     statements = Statements
  ///     { elseBlock = statements; }
  ///   )?
  ///   S
  ///   'end'
  ///   S
  ///   $ = {
  ///     final node = IfStatement(cond, elseifs, thenBlock, elseBlock);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (IfStatement,)? parseIfStatement(State state) {
    final $1 = state.position;
    (IfStatement,)? $0;
    final startPos = state.position;
    final $2 = state.position;
    if (state.peek() == 105 && state.startsWith('if', state.position)) {
      state.consume('if', $2);
      parseS(state);
      final $3 = parseExpression(state);
      if ($3 != null) {
        AstNode cond = $3.$1;
        parseS(state);
        final $4 = state.position;
        if (state.peek() == 116 && state.startsWith('then', state.position)) {
          state.consume('then', $4);
          parseS(state);
          final $5 = parseStatements(state);
          List<AstNode> thenBlock = $5;
          List<ElseIfClause>? $7;
          final $6 = parseElseIfList(state);
          $7 = $6;
          List<ElseIfClause>? elseifs = $7;
          List<AstNode> elseBlock = [];
          var $8 = false;
          final $9 = state.position;
          if (state.peek() == 101 && state.startsWith('else', state.position)) {
            state.consume('else', $9);
            parseS(state);
            final $10 = parseStatements(state);
            List<AstNode> statements = $10;
            elseBlock = statements;
            $8 = true;
          } else {
            state.expected('else');
          }
          parseS(state);
          final $11 = state.position;
          if (state.peek() == 101 && state.startsWith('end', state.position)) {
            state.consume('end', $11);
            parseS(state);
            final IfStatement $$;
            final node = IfStatement(cond, elseifs, thenBlock, elseBlock);
            $$ = _setNodeSpan(node, startPos, state.position, state);
            IfStatement $ = $$;
            $0 = ($,);
          } else {
            state.expected('end');
          }
        } else {
          state.expected('then');
        }
      }
    } else {
      state.expected('if');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **Label**
  ///
  ///```text
  /// `Label`
  /// Label =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   '::'
  ///   label = ID
  ///   '::'
  ///   S
  ///   $ = {
  ///     final node = Label(label);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (Label,)? parseLabel(State state) {
    final $1 = state.position;
    (Label,)? $0;
    final startPos = state.position;
    final $2 = state.position;
    if (state.peek() == 58 && state.startsWith('::', state.position)) {
      state.consume('::', $2);
      final $3 = parseID(state);
      if ($3 != null) {
        Identifier label = $3.$1;
        final $4 = state.position;
        if (state.peek() == 58 && state.startsWith('::', state.position)) {
          state.consume('::', $4);
          parseS(state);
          final Label $$;
          final node = Label(label);
          $$ = _setNodeSpan(node, startPos, state.position, state);
          Label $ = $$;
          $0 = ($,);
        } else {
          state.expected('::');
        }
      }
    } else {
      state.expected('::');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **LocalDeclaration**
  ///
  ///```text
  /// `LocalDeclaration`
  /// LocalDeclaration =>
  ///   {
  ///     List<Identifier>? names = [];
  ///     List<String>? attributes = [];
  ///     List<AstNode>? expressions = [];
  ///     final startPos = state.position;
  ///   }
  ///   'local'
  ///   S
  ///   (
  ///     result = LocalNameListWithAttribs
  ///     {
  ///       names = result.$1;
  ///       attributes = result.$2;
  ///     }
  ///   )
  ///   (
  ///     '='
  ///     S
  ///     exprs = ExpressionList
  ///     { expressions = exprs; }
  ///     S
  ///   )?
  ///   $ = {
  ///     // If there's no '=' part, expressions will be empty list
  ///     final node = LocalDeclaration(names, attributes, expressions);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (LocalDeclaration,)? parseLocalDeclaration(State state) {
    final $1 = state.position;
    (LocalDeclaration,)? $0;
    List<Identifier>? names = [];
    List<String>? attributes = [];
    List<AstNode>? expressions = [];
    final startPos = state.position;
    final $2 = state.position;
    if (state.peek() == 108 && state.startsWith('local', state.position)) {
      state.consume('local', $2);
      parseS(state);
      var $3 = false;
      final $4 = parseLocalNameListWithAttribs(state);
      if ($4 != null) {
        (List<Identifier>, List<String>) result = $4.$1;
        names = result.$1;
        attributes = result.$2;
        $3 = true;
      }
      if ($3) {
        var $5 = false;
        final $6 = state.position;
        if (state.peek() == 61) {
          state.consume('=', $6);
          parseS(state);
          final $7 = parseExpressionList(state);
          List<AstNode> exprs = $7;
          expressions = exprs;
          parseS(state);
          $5 = true;
        } else {
          state.expected('=');
        }
        final LocalDeclaration $$;
        // If there's no '=' part, expressions will be empty list
        final node = LocalDeclaration(names, attributes, expressions);
        $$ = _setNodeSpan(node, startPos, state.position, state);
        LocalDeclaration $ = $$;
        $0 = ($,);
      }
    } else {
      state.expected('local');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **LocalFunctionDef**
  ///
  ///```text
  /// `LocalFunctionDef`
  /// LocalFunctionDef =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   'local'
  ///   !IdChar
  ///   S
  ///   'function'
  ///   !IdChar
  ///   S
  ///   name = ID
  ///   S
  ///   funcBody = FunctionBody
  ///   $ = {
  ///     final node = LocalFunctionDef(name, funcBody);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (LocalFunctionDef,)? parseLocalFunctionDef(State state) {
    final $1 = state.position;
    (LocalFunctionDef,)? $0;
    final startPos = state.position;
    final $2 = state.position;
    if (state.peek() == 108 && state.startsWith('local', state.position)) {
      state.consume('local', $2);
      final $3 = state.position;
      final $4 = state.predicate;
      state.predicate = true;
      var $6 = true;
      final $5 = parseIdChar(state);
      if ($5 != null) {
        state.failAndBacktrack($3);
        $6 = false;
      }
      state.predicate = $4;
      if ($6) {
        parseS(state);
        final $7 = state.position;
        if (state.peek() == 102 &&
            state.startsWith('function', state.position)) {
          state.consume('function', $7);
          final $8 = state.position;
          final $9 = state.predicate;
          state.predicate = true;
          var $11 = true;
          final $10 = parseIdChar(state);
          if ($10 != null) {
            state.failAndBacktrack($8);
            $11 = false;
          }
          state.predicate = $9;
          if ($11) {
            parseS(state);
            final $12 = parseID(state);
            if ($12 != null) {
              Identifier name = $12.$1;
              parseS(state);
              final $13 = parseFunctionBody(state);
              if ($13 != null) {
                FunctionBody funcBody = $13.$1;
                final LocalFunctionDef $$;
                final node = LocalFunctionDef(name, funcBody);
                $$ = _setNodeSpan(node, startPos, state.position, state);
                LocalFunctionDef $ = $$;
                $0 = ($,);
              }
            }
          }
        } else {
          state.expected('function');
        }
      }
    } else {
      state.expected('local');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **LocalNameListWithAttribs**
  ///
  ///```text
  /// `(List<Identifier>, List<String>)`
  /// LocalNameListWithAttribs =>
  ///   {
  ///     List<Identifier> ids = [];
  ///     List<String> attribs = [];
  ///   }
  ///   first = ID
  ///   {
  ///     ids.add(first);
  ///   }
  ///   firstAttrib = AttributeOpt?
  ///   {
  ///     // Add the attribute if present, otherwise add empty string
  ///     attribs.add(firstAttrib ?? "");
  ///   }
  ///   @while (*) (
  ///     ','
  ///     S
  ///     next = ID
  ///     {
  ///       ids.add(next);
  ///     }
  ///     nextAttrib = AttributeOpt?
  ///     {
  ///       // Add the attribute if present, otherwise add empty string
  ///       attribs.add(nextAttrib ?? "");
  ///     }
  ///   )
  ///   $ = {
  ///     $$ = (ids, attribs);
  ///   }
  ///```
  ((List<Identifier>, List<String>),)? parseLocalNameListWithAttribs(
    State state,
  ) {
    final $1 = state.position;
    ((List<Identifier>, List<String>),)? $0;
    List<Identifier> ids = [];
    List<String> attribs = [];
    final $2 = parseID(state);
    if ($2 != null) {
      Identifier first = $2.$1;
      ids.add(first);
      String? $4;
      final $3 = parseAttributeOpt(state);
      if ($3 != null) {
        $4 = $3.$1;
      }
      String? firstAttrib = $4;
      // Add the attribute if present, otherwise add empty string
      attribs.add(firstAttrib ?? "");
      while (true) {
        final $6 = state.position;
        var $5 = false;
        if (state.peek() == 44) {
          state.consume(',', $6);
          parseS(state);
          final $7 = parseID(state);
          if ($7 != null) {
            Identifier next = $7.$1;
            ids.add(next);
            String? $9;
            final $8 = parseAttributeOpt(state);
            if ($8 != null) {
              $9 = $8.$1;
            }
            String? nextAttrib = $9;
            // Add the attribute if present, otherwise add empty string
            attribs.add(nextAttrib ?? "");
            $5 = true;
          }
        } else {
          state.expected(',');
        }
        if (!$5) {
          state.position = $6;
          break;
        }
      }
      final (List<Identifier>, List<String>) $$;
      $$ = (ids, attribs);
      (List<Identifier>, List<String>) $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **LongString**
  ///
  ///```text
  /// `String`
  /// LongString =>
  ///   {
  ///     String text = '';
  ///     int eqCount = 0;
  ///     final startPos = state.position;
  ///   }
  ///   '['
  ///   eqs = <('='*)>
  ///   '['
  ///   S?
  ///   {
  ///     eqCount = eqs.length;
  ///   }
  ///   content = <
  ///     @while (*) (
  ///       !(
  ///         ']'
  ///         eqs2 = <('='*)>
  ///         ']'
  ///         &{ eqs2.length == eqCount }
  ///       )
  ///       .
  ///     )
  ///   >
  ///   ']'
  ///   eqs3 = <('='*)>
  ///   ']'
  ///   &{
  ///         eqs3.length == eqCount
  ///       }
  ///   S?
  ///   $ = {
  ///     $$ = content;
  ///   }
  ///```
  (String,)? parseLongString(State state) {
    final $1 = state.position;
    (String,)? $0;
    String text = '';
    int eqCount = 0;
    final startPos = state.position;
    final $2 = state.position;
    if (state.peek() == 91) {
      state.consume('[', $2);
      final $3 = state.position;
      while (true) {
        final $4 = state.position;
        if (state.peek() == 61) {
          state.consume('=', $4);
        } else {
          state.expected('=');
          break;
        }
      }
      final $5 = state.substring($3, state.position);
      String eqs = $5;
      final $6 = state.position;
      if (state.peek() == 91) {
        state.consume('[', $6);
        parseS(state);
        eqCount = eqs.length;
        final $7 = state.position;
        while (true) {
          final $9 = state.position;
          var $8 = false;
          final $10 = state.predicate;
          state.predicate = true;
          var $16 = true;
          var $11 = false;
          if (state.peek() == 93) {
            state.consume(']', $9);
            final $12 = state.position;
            while (true) {
              final $13 = state.position;
              if (state.peek() == 61) {
                state.consume('=', $13);
              } else {
                state.expected('=');
                break;
              }
            }
            final $14 = state.substring($12, state.position);
            String eqs2 = $14;
            final $15 = state.position;
            if (state.peek() == 93) {
              state.consume(']', $15);
              if (eqs2.length == eqCount) {
                $11 = true;
              }
            } else {
              state.expected(']');
            }
          } else {
            state.expected(']');
          }
          if ($11) {
            state.failAndBacktrack($9);
            $16 = false;
          } else {
            state.position = $9;
          }
          state.predicate = $10;
          if ($16) {
            final $17 = state.peek();
            if ($17 != 0) {
              state.position += state.charSize($17);
              $8 = true;
            } else {
              state.fail();
            }
          }
          if (!$8) {
            state.position = $9;
            break;
          }
        }
        final $18 = state.substring($7, state.position);
        String content = $18;
        final $19 = state.position;
        if (state.peek() == 93) {
          state.consume(']', $19);
          final $20 = state.position;
          while (true) {
            final $21 = state.position;
            if (state.peek() == 61) {
              state.consume('=', $21);
            } else {
              state.expected('=');
              break;
            }
          }
          final $22 = state.substring($20, state.position);
          String eqs3 = $22;
          final $23 = state.position;
          if (state.peek() == 93) {
            state.consume(']', $23);
            if (eqs3.length == eqCount) {
              parseS(state);
              final String $$;
              $$ = content;
              String $ = $$;
              $0 = ($,);
            }
          } else {
            state.expected(']');
          }
        } else {
          state.expected(']');
        }
      } else {
        state.expected('[');
      }
    } else {
      state.expected('[');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **MetatableAssignment**
  ///
  ///```text
  /// `AstNode`
  /// MetatableAssignment =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   base = FunctionCall
  ///   '.'
  ///   S
  ///   field = ID
  ///   '='
  ///   S
  ///   exprs = ExpressionList
  ///   S
  ///   $ = {
  ///     final node = Assignment([ TableAccessExpr(base, field) ], exprs);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (AstNode,)? parseMetatableAssignment(State state) {
    final $1 = state.position;
    (AstNode,)? $0;
    final startPos = state.position;
    final $2 = parseFunctionCall(state);
    if ($2 != null) {
      Call base = $2.$1;
      final $3 = state.position;
      if (state.peek() == 46) {
        state.consume('.', $3);
        parseS(state);
        final $4 = parseID(state);
        if ($4 != null) {
          Identifier field = $4.$1;
          final $5 = state.position;
          if (state.peek() == 61) {
            state.consume('=', $5);
            parseS(state);
            final $6 = parseExpressionList(state);
            List<AstNode> exprs = $6;
            parseS(state);
            final AstNode $$;
            final node = Assignment([TableAccessExpr(base, field)], exprs);
            $$ = _setNodeSpan(node, startPos, state.position, state);
            AstNode $ = $$;
            $0 = ($,);
          } else {
            state.expected('=');
          }
        }
      } else {
        state.expected('.');
      }
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **MultiplicativeExpression**
  ///
  ///```text
  /// `AstNode`
  /// MultiplicativeExpression =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   result = UnaryExpression
  ///   @while (*) (
  ///     S
  ///     { String op = "";}
  ///     (
  ///       operator = "//"
  ///       {
  ///         op = operator;
  ///       }
  ///       ----
  ///       operator = <[*/%]>
  ///       {
  ///         op = operator;
  ///       }
  ///     )
  ///     S
  ///     right = UnaryExpression
  ///     {
  ///       result = BinaryExpression(result, op, right);
  ///     }
  ///   )
  ///   $ = {
  ///     $$ = _setNodeSpan(result, startPos, state.position, state);
  ///   }
  ///```
  (AstNode,)? parseMultiplicativeExpression(State state) {
    final $1 = state.position;
    (AstNode,)? $0;
    final startPos = state.position;
    final $2 = parseUnaryExpression(state);
    if ($2 != null) {
      AstNode result = $2.$1;
      while (true) {
        final $4 = state.position;
        var $3 = false;
        parseS(state);
        String op = "";
        var $5 = true;
        var $6 = false;
        if (state.peek() == 47 && state.startsWith('//', state.position)) {
          state.position += state.strlen('//');
          String operator = '//';
          op = operator;
          $6 = true;
        } else {
          state.fail();
        }
        if (!$6) {
          var $7 = false;
          final $8 = state.position;
          final $9 = state.peek();
          if ($9 >= 42 ? $9 <= 42 || $9 == 47 : $9 == 37) {
            state.position += state.charSize($9);
            final $10 = state.substring($8, state.position);
            String operator = $10;
            op = operator;
            $7 = true;
          } else {
            state.fail();
          }
          if (!$7) {
            $5 = false;
          }
        }
        if ($5) {
          parseS(state);
          final $11 = parseUnaryExpression(state);
          if ($11 != null) {
            AstNode right = $11.$1;
            result = BinaryExpression(result, op, right);
            $3 = true;
          }
        }
        if (!$3) {
          state.position = $4;
          break;
        }
      }
      final AstNode $$;
      $$ = _setNodeSpan(result, startPos, state.position, state);
      AstNode $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **NameList**
  ///
  ///```text
  /// `List<Identifier>`
  /// NameList =>
  ///   {
  ///     List<Identifier> names = [];
  ///     final startPos = state.position;
  ///   }
  ///   first = ID
  ///   { names.add(first); }
  ///   @while (*) (
  ///     ','
  ///     S
  ///     nxt = ID
  ///     { names.add(nxt); }
  ///   )
  ///   $ = {
  ///     $$ = names;
  ///   }
  ///```
  (List<Identifier>,)? parseNameList(State state) {
    final $1 = state.position;
    (List<Identifier>,)? $0;
    List<Identifier> names = [];
    final startPos = state.position;
    final $2 = parseID(state);
    if ($2 != null) {
      Identifier first = $2.$1;
      names.add(first);
      while (true) {
        final $4 = state.position;
        var $3 = false;
        if (state.peek() == 44) {
          state.consume(',', $4);
          parseS(state);
          final $5 = parseID(state);
          if ($5 != null) {
            Identifier nxt = $5.$1;
            names.add(nxt);
            $3 = true;
          }
        } else {
          state.expected(',');
        }
        if (!$3) {
          state.position = $4;
          break;
        }
      }
      final List<Identifier> $$;
      $$ = names;
      List<Identifier> $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **NilValue**
  ///
  ///```text
  /// `NilValue`
  /// NilValue =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   'nil'
  ///   !IdChar
  ///   S
  ///   $ = {
  ///     final node = NilValue();
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (NilValue,)? parseNilValue(State state) {
    final $1 = state.position;
    (NilValue,)? $0;
    final startPos = state.position;
    final $2 = state.position;
    if (state.peek() == 110 && state.startsWith('nil', state.position)) {
      state.consume('nil', $2);
      final $3 = state.position;
      final $4 = state.predicate;
      state.predicate = true;
      var $6 = true;
      final $5 = parseIdChar(state);
      if ($5 != null) {
        state.failAndBacktrack($3);
        $6 = false;
      }
      state.predicate = $4;
      if ($6) {
        parseS(state);
        final NilValue $$;
        final node = NilValue();
        $$ = _setNodeSpan(node, startPos, state.position, state);
        NilValue $ = $$;
        $0 = ($,);
      }
    } else {
      state.expected('nil');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **Number**
  ///
  ///```text
  /// `NumberLiteral`
  /// Number =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   n = <
  ///     (
  ///       '0'
  ///       [xX]
  ///       (
  ///         (
  ///           [0-9A-Fa-f]+
  ///           (
  ///             '.'
  ///             [0-9A-Fa-f]*
  ///           )?
  ///         )
  ///         ----
  ///         (
  ///           '.'
  ///           [0-9A-Fa-f]+
  ///         )
  ///       )
  ///       (
  ///         [pP]
  ///         [+\-]?
  ///         [0-9]+
  ///       )?
  ///     )
  ///     ----
  ///     (
  ///       (
  ///         [0-9]+
  ///         (
  ///           '.'
  ///           [0-9]*
  ///         )?
  ///       )
  ///       ----
  ///       (
  ///         '.'
  ///         [0-9]+
  ///       )
  ///     )
  ///     (
  ///       [eE]
  ///       [+\-]?
  ///       [0-9]+
  ///     )?
  ///   >
  ///   S
  ///   $ = {
  ///     final node = NumberLiteral(LuaNumberParser.parse(n));
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (NumberLiteral,)? parseNumber(State state) {
    final $1 = state.position;
    (NumberLiteral,)? $0;
    final startPos = state.position;
    final $2 = state.position;
    var $3 = true;
    var $4 = false;
    if (state.peek() == 48) {
      state.consume('0', $2);
      final $5 = state.peek();
      if ($5 == 88 || $5 == 120) {
        state.position += state.charSize($5);
        var $6 = true;
        var $7 = false;
        final $8 = state.position;
        for (
          var c = state.peek();
          c >= 65 ? c <= 70 || c >= 97 && c <= 102 : c >= 48 && c <= 57;
        ) {
          state.position += state.charSize(c);
          c = state.peek();
        }
        if ($8 != state.position) {
          var $9 = false;
          final $10 = state.position;
          if (state.peek() == 46) {
            state.consume('.', $10);
            for (
              var c = state.peek();
              c >= 65 ? c <= 70 || c >= 97 && c <= 102 : c >= 48 && c <= 57;
            ) {
              state.position += state.charSize(c);
              c = state.peek();
            }
            $9 = true;
          } else {
            state.expected('.');
          }
          $7 = true;
        } else {
          state.fail();
        }
        if (!$7) {
          final $12 = state.position;
          var $11 = false;
          if (state.peek() == 46) {
            state.consume('.', $12);
            final $13 = state.position;
            for (
              var c = state.peek();
              c >= 65 ? c <= 70 || c >= 97 && c <= 102 : c >= 48 && c <= 57;
            ) {
              state.position += state.charSize(c);
              c = state.peek();
            }
            if ($13 != state.position) {
              $11 = true;
            } else {
              state.fail();
            }
          } else {
            state.expected('.');
          }
          if (!$11) {
            state.position = $12;
            $6 = false;
          }
        }
        if ($6) {
          final $15 = state.position;
          var $14 = false;
          final $16 = state.peek();
          if ($16 == 80 || $16 == 112) {
            state.position += state.charSize($16);
            final $17 = state.peek();
            if ($17 == 43 || $17 == 45) {
              state.position += state.charSize($17);
            } else {
              state.fail();
            }
            final $18 = state.position;
            for (var c = state.peek(); c >= 48 && c <= 57;) {
              state.position += state.charSize(c);
              c = state.peek();
            }
            if ($18 != state.position) {
              $14 = true;
            } else {
              state.fail();
            }
          } else {
            state.fail();
          }
          if (!$14) {
            state.position = $15;
          }
          $4 = true;
        }
      } else {
        state.fail();
      }
    } else {
      state.expected('0');
    }
    if (!$4) {
      state.position = $2;
      var $19 = false;
      var $20 = true;
      var $21 = false;
      for (var c = state.peek(); c >= 48 && c <= 57;) {
        state.position += state.charSize(c);
        c = state.peek();
      }
      if ($2 != state.position) {
        var $22 = false;
        final $23 = state.position;
        if (state.peek() == 46) {
          state.consume('.', $23);
          for (var c = state.peek(); c >= 48 && c <= 57;) {
            state.position += state.charSize(c);
            c = state.peek();
          }
          $22 = true;
        } else {
          state.expected('.');
        }
        $21 = true;
      } else {
        state.fail();
      }
      if (!$21) {
        var $24 = false;
        if (state.peek() == 46) {
          state.consume('.', $2);
          final $25 = state.position;
          for (var c = state.peek(); c >= 48 && c <= 57;) {
            state.position += state.charSize(c);
            c = state.peek();
          }
          if ($25 != state.position) {
            $24 = true;
          } else {
            state.fail();
          }
        } else {
          state.expected('.');
        }
        if (!$24) {
          state.position = $2;
          $20 = false;
        }
      }
      if ($20) {
        final $27 = state.position;
        var $26 = false;
        final $28 = state.peek();
        if ($28 == 69 || $28 == 101) {
          state.position += state.charSize($28);
          final $29 = state.peek();
          if ($29 == 43 || $29 == 45) {
            state.position += state.charSize($29);
          } else {
            state.fail();
          }
          final $30 = state.position;
          for (var c = state.peek(); c >= 48 && c <= 57;) {
            state.position += state.charSize(c);
            c = state.peek();
          }
          if ($30 != state.position) {
            $26 = true;
          } else {
            state.fail();
          }
        } else {
          state.fail();
        }
        if (!$26) {
          state.position = $27;
        }
        $19 = true;
      }
      if (!$19) {
        $3 = false;
      }
    }
    if ($3) {
      final $31 = state.substring($2, state.position);
      String n = $31;
      parseS(state);
      final NumberLiteral $$;
      final node = NumberLiteral(LuaNumberParser.parse(n));
      $$ = _setNodeSpan(node, startPos, state.position, state);
      NumberLiteral $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **OneOrMoreSemicolons**
  ///
  ///```text
  /// `void`
  /// OneOrMoreSemicolons =>
  ///   {
  ///     // Must consume at least one semicolon
  ///   }
  ///   S
  ///   @while (+) (';')
  ///   S
  ///```
  (void,)? parseOneOrMoreSemicolons(State state) {
    final $1 = state.position;
    var $0 = false;
    // Must consume at least one semicolon
    parseS(state);
    final $2 = state.position;
    while (true) {
      final $3 = state.position;
      if (state.peek() == 59) {
        state.consume(';', $3);
      } else {
        state.expected(';');
        break;
      }
    }
    if ($2 != state.position) {
      parseS(state);
      $0 = true;
    }
    if ($0) {
      return const (null,);
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **OptionalSemi**
  ///
  ///```text
  /// `void`
  /// OptionalSemi =>
  ///   @while (*) (
  ///     S
  ///     @while (+) (';')
  ///     S
  ///   )
  ///```
  void parseOptionalSemi(State state) {
    while (true) {
      final $1 = state.position;
      var $0 = false;
      parseS(state);
      final $2 = state.position;
      while (true) {
        final $3 = state.position;
        if (state.peek() == 59) {
          state.consume(';', $3);
        } else {
          state.expected(';');
          break;
        }
      }
      if ($2 != state.position) {
        parseS(state);
        $0 = true;
      }
      if (!$0) {
        state.position = $1;
        break;
      }
    }
  }

  /// **OrExpression**
  ///
  ///```text
  /// `AstNode`
  /// OrExpression =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   result = AndExpression
  ///   @while (*) (
  ///     S
  ///     'or'
  ///     S
  ///     right = AndExpression
  ///     {
  ///       result = BinaryExpression(result, "or", right);
  ///     }
  ///   )
  ///   $ = {
  ///     $$ = _setNodeSpan(result, startPos, state.position, state);
  ///   }
  ///```
  (AstNode,)? parseOrExpression(State state) {
    final $1 = state.position;
    (AstNode,)? $0;
    final startPos = state.position;
    final $2 = parseAndExpression(state);
    if ($2 != null) {
      AstNode result = $2.$1;
      while (true) {
        final $4 = state.position;
        var $3 = false;
        parseS(state);
        final $5 = state.position;
        if (state.peek() == 111 && state.startsWith('or', state.position)) {
          state.consume('or', $5);
          parseS(state);
          final $6 = parseAndExpression(state);
          if ($6 != null) {
            AstNode right = $6.$1;
            result = BinaryExpression(result, "or", right);
            $3 = true;
          }
        } else {
          state.expected('or');
        }
        if (!$3) {
          state.position = $4;
          break;
        }
      }
      final AstNode $$;
      $$ = _setNodeSpan(result, startPos, state.position, state);
      AstNode $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **ParameterList**
  ///
  ///```text
  /// `(List<Identifier>, bool)`
  /// ParameterList =>
  ///   {
  ///     List<Identifier> params = [];
  ///     bool hasVararg = false;
  ///   }
  ///   (
  ///     varargMatch = Vararg
  ///     {
  ///       hasVararg = true;
  ///     }
  ///     ----
  ///     first = ID
  ///     {
  ///       params.add(first);
  ///     }
  ///     @while (*) (
  ///       ','
  ///       S
  ///       next = ID
  ///       {
  ///         params.add(next);
  ///       }
  ///     )
  ///     (
  ///       ','
  ///       S
  ///       varargMatch = Vararg
  ///       {
  ///         hasVararg = true;
  ///       }
  ///       ----
  ///       varargMatch = Vararg
  ///       {
  ///         hasVararg = true;
  ///       }
  ///     )?
  ///   )?
  ///   $ = {
  ///     $$ = (params, hasVararg);
  ///   }
  ///```
  (List<Identifier>, bool) parseParameterList(State state) {
    List<Identifier> params = [];
    bool hasVararg = false;
    var $0 = true;
    var $1 = false;
    final $2 = parseVararg(state);
    if ($2 != null) {
      VarArg varargMatch = $2.$1;
      hasVararg = true;
      $1 = true;
    }
    if (!$1) {
      var $3 = false;
      final $4 = parseID(state);
      if ($4 != null) {
        Identifier first = $4.$1;
        params.add(first);
        while (true) {
          final $6 = state.position;
          var $5 = false;
          if (state.peek() == 44) {
            state.consume(',', $6);
            parseS(state);
            final $7 = parseID(state);
            if ($7 != null) {
              Identifier next = $7.$1;
              params.add(next);
              $5 = true;
            }
          } else {
            state.expected(',');
          }
          if (!$5) {
            state.position = $6;
            break;
          }
        }
        var $8 = true;
        final $10 = state.position;
        var $9 = false;
        if (state.peek() == 44) {
          state.consume(',', $10);
          parseS(state);
          final $11 = parseVararg(state);
          if ($11 != null) {
            VarArg varargMatch = $11.$1;
            hasVararg = true;
            $9 = true;
          }
        } else {
          state.expected(',');
        }
        if (!$9) {
          state.position = $10;
          var $12 = false;
          final $13 = parseVararg(state);
          if ($13 != null) {
            VarArg varargMatch = $13.$1;
            hasVararg = true;
            $12 = true;
          }
          if (!$12) {
            $8 = false;
          }
        }
        state.unused = $8;
        $3 = true;
      }
      if (!$3) {
        $0 = false;
      }
    }
    state.unused = $0;
    final (List<Identifier>, bool) $$;
    $$ = (params, hasVararg);
    (List<Identifier>, bool) $ = $$;
    return $;
  }

  /// **PrimaryExpression**
  ///
  ///```text
  /// `AstNode`
  /// PrimaryExpression =>
  ///   (
  ///     Number
  ///     ----
  ///     String
  ///     ----
  ///     Boolean
  ///     ----
  ///     NilValue
  ///     ----
  ///     TableFieldAccess
  ///     ----
  ///     TableLookup
  ///     ----
  ///     ID
  ///     ----
  ///     TableConstructor
  ///     ----
  ///     {
  ///       final startPos = state.position;
  ///     }
  ///     '('
  ///     S
  ///     inner = Expression
  ///     $ = {
  ///       final node = GroupedExpression(inner);
  ///       $$ = _setNodeSpan(node, startPos, state.position, state);
  ///     }
  ///     (
  ///       ')'
  ///       S
  ///        ~ { message = 'Expected closing parenthesis' }
  ///     )
  ///   )
  ///```
  (AstNode,)? parsePrimaryExpression(State state) {
    final $10 = state.position;
    (AstNode,)? $0;
    final $1 = parseNumber(state);
    if ($1 != null) {
      $0 = $1;
    } else {
      final $2 = parseString(state);
      if ($2 != null) {
        $0 = $2;
      } else {
        final $3 = parseBoolean(state);
        if ($3 != null) {
          $0 = $3;
        } else {
          final $4 = parseNilValue(state);
          if ($4 != null) {
            $0 = $4;
          } else {
            final $5 = parseTableFieldAccess(state);
            if ($5 != null) {
              $0 = $5;
            } else {
              final $6 = parseTableLookup(state);
              if ($6 != null) {
                $0 = $6;
              } else {
                final $7 = parseID(state);
                if ($7 != null) {
                  $0 = $7;
                } else {
                  final $8 = parseTableConstructor(state);
                  if ($8 != null) {
                    $0 = $8;
                  } else {
                    (AstNode,)? $9;
                    final startPos = state.position;
                    final $11 = state.position;
                    if (state.peek() == 40) {
                      state.consume('(', $11);
                      parseS(state);
                      final $12 = parseExpression(state);
                      if ($12 != null) {
                        AstNode inner = $12.$1;
                        final AstNode $$;
                        final node = GroupedExpression(inner);
                        $$ = _setNodeSpan(
                          node,
                          startPos,
                          state.position,
                          state,
                        );
                        AstNode $ = $$;
                        final $15 = state.failure;
                        state.failure = state.position;
                        var $13 = false;
                        final $14 = state.position;
                        if (state.peek() == 41) {
                          state.consume(')', $14);
                          parseS(state);
                          $13 = true;
                        } else {
                          state.expected(')');
                        }
                        if ($13) {
                          state.failure < $15 ? state.failure = $15 : null;
                          $9 = ($,);
                        } else {
                          state.error(
                            'Expected closing parenthesis',
                            state.position,
                            state.failure,
                            3,
                          );
                          state.failure < $15 ? state.failure = $15 : null;
                        }
                      }
                    } else {
                      state.expected('(');
                    }
                    if ($9 != null) {
                      $0 = $9;
                    } else {
                      state.position = $10;
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    return $0;
  }

  /// **RepeatUntilLoop**
  ///
  ///```text
  /// `RepeatUntilLoop`
  /// RepeatUntilLoop =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   'repeat'
  ///   !IdChar
  ///   S
  ///   body = Statements
  ///   (
  ///     'until'
  ///     !IdChar
  ///     S
  ///      ~ { message = 'Expected `until` to close repeat-until loop' }
  ///   )
  ///   cond = Expression
  ///   S
  ///   $ = {
  ///     final node = RepeatUntilLoop(body, cond);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (RepeatUntilLoop,)? parseRepeatUntilLoop(State state) {
    final $1 = state.position;
    (RepeatUntilLoop,)? $0;
    final startPos = state.position;
    final $2 = state.position;
    if (state.peek() == 114 && state.startsWith('repeat', state.position)) {
      state.consume('repeat', $2);
      final $3 = state.position;
      final $4 = state.predicate;
      state.predicate = true;
      var $6 = true;
      final $5 = parseIdChar(state);
      if ($5 != null) {
        state.failAndBacktrack($3);
        $6 = false;
      }
      state.predicate = $4;
      if ($6) {
        parseS(state);
        final $7 = parseStatements(state);
        List<AstNode> body = $7;
        final $14 = state.failure;
        state.failure = state.position;
        final $9 = state.position;
        var $8 = false;
        if (state.peek() == 117 && state.startsWith('until', state.position)) {
          state.consume('until', $9);
          final $10 = state.position;
          final $11 = state.predicate;
          state.predicate = true;
          var $13 = true;
          final $12 = parseIdChar(state);
          if ($12 != null) {
            state.failAndBacktrack($10);
            $13 = false;
          }
          state.predicate = $11;
          if ($13) {
            parseS(state);
            $8 = true;
          }
        } else {
          state.expected('until');
        }
        if ($8) {
          state.failure < $14 ? state.failure = $14 : null;
          final $15 = parseExpression(state);
          if ($15 != null) {
            AstNode cond = $15.$1;
            parseS(state);
            final RepeatUntilLoop $$;
            final node = RepeatUntilLoop(body, cond);
            $$ = _setNodeSpan(node, startPos, state.position, state);
            RepeatUntilLoop $ = $$;
            $0 = ($,);
          }
        } else {
          state.position = $9;
          state.error(
            'Expected `until` to close repeat-until loop',
            state.position,
            state.failure,
            3,
          );
          state.failure < $14 ? state.failure = $14 : null;
        }
      }
    } else {
      state.expected('repeat');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **ReturnStatement**
  ///
  ///```text
  /// `ReturnStatement`
  /// ReturnStatement =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   'return'
  ///   !IdChar
  ///   S
  ///   exprs = ExpressionList?
  ///   S
  ///   $ = {
  ///     final node = ReturnStatement(exprs);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (ReturnStatement,)? parseReturnStatement(State state) {
    final $1 = state.position;
    (ReturnStatement,)? $0;
    final startPos = state.position;
    final $2 = state.position;
    if (state.peek() == 114 && state.startsWith('return', state.position)) {
      state.consume('return', $2);
      final $3 = state.position;
      final $4 = state.predicate;
      state.predicate = true;
      var $6 = true;
      final $5 = parseIdChar(state);
      if ($5 != null) {
        state.failAndBacktrack($3);
        $6 = false;
      }
      state.predicate = $4;
      if ($6) {
        parseS(state);
        List<AstNode>? $8;
        final $7 = parseExpressionList(state);
        $8 = $7;
        List<AstNode>? exprs = $8;
        parseS(state);
        final ReturnStatement $$;
        final node = ReturnStatement(exprs);
        $$ = _setNodeSpan(node, startPos, state.position, state);
        ReturnStatement $ = $$;
        $0 = ($,);
      }
    } else {
      state.expected('return');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **S**
  ///
  ///```text
  /// `void`
  /// S =>
  ///   { List<dynamic> comment = []; }
  ///   @while (*) (
  ///     c = [ {9}{d}{a}]
  ///     { comment.add(c); }
  ///     ----
  ///     c = '--[['
  ///     @while (*) (
  ///       !']]'
  ///       .
  ///     )
  ///     ']]'
  ///     { comment.add(c); }
  ///     ----
  ///     c = '--[=['
  ///     @while (*) (
  ///       !']=]'
  ///       .
  ///     )
  ///     ']=]'
  ///     { comment.add(c); }
  ///     ----
  ///     c = '--[==['
  ///     @while (*) (
  ///       !']==]'
  ///       .
  ///     )
  ///     ']==]'
  ///     { comment.add(c); }
  ///     ----
  ///     c = '--'
  ///     [^{a}]*
  ///     [{a}]?
  ///     { comment.add(c); }
  ///   )
  ///```
  void parseS(State state) {
    List<dynamic> comment = [];
    while (true) {
      var $0 = true;
      var $1 = false;
      final $2 = state.peek();
      if ($2 >= 13 ? $2 <= 13 || $2 == 32 : $2 >= 9 && $2 <= 10) {
        state.position += state.charSize($2);
        int c = $2;
        comment.add(c);
        $1 = true;
      } else {
        state.fail();
      }
      if (!$1) {
        final $4 = state.position;
        var $3 = false;
        if (state.peek() == 45 && state.startsWith('--[[', state.position)) {
          state.consume('--[[', $4);
          String c = '--[[';
          while (true) {
            final $6 = state.position;
            var $5 = false;
            final $7 = state.predicate;
            state.predicate = true;
            var $8 = true;
            if (state.peek() == 93 && state.startsWith(']]', state.position)) {
              state.consume(']]', $6);
              state.failAndBacktrack($6);
              $8 = false;
            } else {
              state.expected(']]');
            }
            state.predicate = $7;
            if ($8) {
              final $9 = state.peek();
              if ($9 != 0) {
                state.position += state.charSize($9);
                $5 = true;
              } else {
                state.fail();
              }
            }
            if (!$5) {
              state.position = $6;
              break;
            }
          }
          final $10 = state.position;
          if (state.peek() == 93 && state.startsWith(']]', state.position)) {
            state.consume(']]', $10);
            comment.add(c);
            $3 = true;
          } else {
            state.expected(']]');
          }
        } else {
          state.expected('--[[');
        }
        if (!$3) {
          state.position = $4;
          final $12 = state.position;
          var $11 = false;
          if (state.peek() == 45 && state.startsWith('--[=[', state.position)) {
            state.consume('--[=[', $12);
            String c = '--[=[';
            while (true) {
              final $14 = state.position;
              var $13 = false;
              final $15 = state.predicate;
              state.predicate = true;
              var $16 = true;
              if (state.peek() == 93 &&
                  state.startsWith(']=]', state.position)) {
                state.consume(']=]', $14);
                state.failAndBacktrack($14);
                $16 = false;
              } else {
                state.expected(']=]');
              }
              state.predicate = $15;
              if ($16) {
                final $17 = state.peek();
                if ($17 != 0) {
                  state.position += state.charSize($17);
                  $13 = true;
                } else {
                  state.fail();
                }
              }
              if (!$13) {
                state.position = $14;
                break;
              }
            }
            final $18 = state.position;
            if (state.peek() == 93 && state.startsWith(']=]', state.position)) {
              state.consume(']=]', $18);
              comment.add(c);
              $11 = true;
            } else {
              state.expected(']=]');
            }
          } else {
            state.expected('--[=[');
          }
          if (!$11) {
            state.position = $12;
            final $20 = state.position;
            var $19 = false;
            if (state.peek() == 45 &&
                state.startsWith('--[==[', state.position)) {
              state.consume('--[==[', $20);
              String c = '--[==[';
              while (true) {
                final $22 = state.position;
                var $21 = false;
                final $23 = state.predicate;
                state.predicate = true;
                var $24 = true;
                if (state.peek() == 93 &&
                    state.startsWith(']==]', state.position)) {
                  state.consume(']==]', $22);
                  state.failAndBacktrack($22);
                  $24 = false;
                } else {
                  state.expected(']==]');
                }
                state.predicate = $23;
                if ($24) {
                  final $25 = state.peek();
                  if ($25 != 0) {
                    state.position += state.charSize($25);
                    $21 = true;
                  } else {
                    state.fail();
                  }
                }
                if (!$21) {
                  state.position = $22;
                  break;
                }
              }
              final $26 = state.position;
              if (state.peek() == 93 &&
                  state.startsWith(']==]', state.position)) {
                state.consume(']==]', $26);
                comment.add(c);
                $19 = true;
              } else {
                state.expected(']==]');
              }
            } else {
              state.expected('--[==[');
            }
            if (!$19) {
              state.position = $20;
              var $27 = false;
              final $28 = state.position;
              if (state.peek() == 45 &&
                  state.startsWith('--', state.position)) {
                state.consume('--', $28);
                String c = '--';
                for (var c = state.peek(); c != 10;) {
                  state.position += state.charSize(c);
                  c = state.peek();
                }
                if (state.peek() == 10) {
                  state.position += state.charSize(10);
                } else {
                  state.fail();
                }
                comment.add(c);
                $27 = true;
              } else {
                state.expected('--');
              }
              if (!$27) {
                $0 = false;
              }
            }
          }
        }
      }
      if (!$0) {
        break;
      }
    }
  }

  /// **ShebangLine**
  ///
  ///```text
  /// `void`
  /// ShebangLine =>
  ///   S
  ///   '#!'
  ///   [a-zA-Z0-9_./]+
  ///   S
  ///```
  (void,)? parseShebangLine(State state) {
    final $1 = state.position;
    var $0 = false;
    parseS(state);
    final $2 = state.position;
    if (state.peek() == 35 && state.startsWith('#!', state.position)) {
      state.consume('#!', $2);
      final $3 = state.position;
      for (
        var c = state.peek();
        c >= 65
            ? c <= 90 || c == 95 || c >= 97 && c <= 122
            : c >= 46 && c <= 57;
      ) {
        state.position += state.charSize(c);
        c = state.peek();
      }
      if ($3 != state.position) {
        parseS(state);
        $0 = true;
      } else {
        state.fail();
      }
    } else {
      state.expected('#!');
    }
    if ($0) {
      return const (null,);
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **ShiftExpression**
  ///
  ///```text
  /// `AstNode`
  /// ShiftExpression =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   result = ConcatExpression
  ///   @while (*) (
  ///     S
  ///     op = <('<<' / '>>')>
  ///     S
  ///     right = ConcatExpression
  ///     {
  ///       result = BinaryExpression(result, op, right);
  ///     }
  ///   )
  ///   $ = {
  ///     $$ = _setNodeSpan(result, startPos, state.position, state);
  ///   }
  ///```
  (AstNode,)? parseShiftExpression(State state) {
    final $1 = state.position;
    (AstNode,)? $0;
    final startPos = state.position;
    final $2 = parseConcatExpression(state);
    if ($2 != null) {
      AstNode result = $2.$1;
      while (true) {
        final $4 = state.position;
        var $3 = false;
        parseS(state);
        final $5 = state.position;
        var $6 = true;
        if (state.peek() == 60 && state.startsWith('<<', state.position)) {
          state.consume('<<', $5);
        } else {
          state.expected('<<');
          if (state.peek() == 62 && state.startsWith('>>', state.position)) {
            state.consume('>>', $5);
          } else {
            state.expected('>>');
            $6 = false;
          }
        }
        if ($6) {
          final $7 = state.substring($5, state.position);
          String op = $7;
          parseS(state);
          final $8 = parseConcatExpression(state);
          if ($8 != null) {
            AstNode right = $8.$1;
            result = BinaryExpression(result, op, right);
            $3 = true;
          }
        }
        if (!$3) {
          state.position = $4;
          break;
        }
      }
      final AstNode $$;
      $$ = _setNodeSpan(result, startPos, state.position, state);
      AstNode $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **SimpleExpression**
  ///
  ///```text
  /// `AstNode`
  /// SimpleExpression =>
  ///   {
  ///     final startPos = state.position;
  ///     AstNode? result;
  ///   }
  ///   (
  ///     expr = TableIndexAccess
  ///     { result = expr; }
  ///     ----
  ///     expr = FunctionCallWithTableAccess
  ///     { result = expr; }
  ///     ----
  ///     expr = DirectStringCall
  ///     { result = expr; }
  ///     ----
  ///     expr = FunctionCall
  ///     { result = expr; }
  ///     ----
  ///     expr = FunctionLiteral
  ///     { result = expr; }
  ///     ----
  ///     expr = TableConstructor
  ///     { result = expr; }
  ///     ----
  ///     expr = NilValue
  ///     { result = expr; }
  ///     ----
  ///     expr = VarArg
  ///     { result = expr; }
  ///     ----
  ///     expr = ComplexTableAccess
  ///     { result = expr; }
  ///     ----
  ///     expr = TableFieldAccess
  ///     { result = expr; }
  ///     ----
  ///     expr = TableLookup
  ///     { result = expr; }
  ///     ----
  ///     expr = ID
  ///     { result = expr; }
  ///     ----
  ///     expr = PrimaryExpression
  ///     { result = expr; }
  ///   )
  ///   $ = {
  ///     $$ = _setNodeSpan(result!, startPos, state.position, state);
  ///   }
  ///```
  (AstNode,)? parseSimpleExpression(State state) {
    final $1 = state.position;
    (AstNode,)? $0;
    final startPos = state.position;
    AstNode? result;
    var $2 = true;
    var $3 = false;
    final $4 = parseTableIndexAccess(state);
    if ($4 != null) {
      AstNode expr = $4.$1;
      result = expr;
      $3 = true;
    }
    if (!$3) {
      var $5 = false;
      final $6 = parseFunctionCallWithTableAccess(state);
      if ($6 != null) {
        AstNode expr = $6.$1;
        result = expr;
        $5 = true;
      }
      if (!$5) {
        var $7 = false;
        final $8 = parseDirectStringCall(state);
        if ($8 != null) {
          AstNode expr = $8.$1;
          result = expr;
          $7 = true;
        }
        if (!$7) {
          var $9 = false;
          final $10 = parseFunctionCall(state);
          if ($10 != null) {
            Call expr = $10.$1;
            result = expr;
            $9 = true;
          }
          if (!$9) {
            var $11 = false;
            final $12 = parseFunctionLiteral(state);
            if ($12 != null) {
              FunctionLiteral expr = $12.$1;
              result = expr;
              $11 = true;
            }
            if (!$11) {
              var $13 = false;
              final $14 = parseTableConstructor(state);
              if ($14 != null) {
                TableConstructor expr = $14.$1;
                result = expr;
                $13 = true;
              }
              if (!$13) {
                var $15 = false;
                final $16 = parseNilValue(state);
                if ($16 != null) {
                  NilValue expr = $16.$1;
                  result = expr;
                  $15 = true;
                }
                if (!$15) {
                  var $17 = false;
                  final $18 = parseVarArg(state);
                  if ($18 != null) {
                    VarArg expr = $18.$1;
                    result = expr;
                    $17 = true;
                  }
                  if (!$17) {
                    var $19 = false;
                    final $20 = parseComplexTableAccess(state);
                    if ($20 != null) {
                      AstNode expr = $20.$1;
                      result = expr;
                      $19 = true;
                    }
                    if (!$19) {
                      var $21 = false;
                      final $22 = parseTableFieldAccess(state);
                      if ($22 != null) {
                        AstNode expr = $22.$1;
                        result = expr;
                        $21 = true;
                      }
                      if (!$21) {
                        var $23 = false;
                        final $24 = parseTableLookup(state);
                        if ($24 != null) {
                          AstNode expr = $24.$1;
                          result = expr;
                          $23 = true;
                        }
                        if (!$23) {
                          var $25 = false;
                          final $26 = parseID(state);
                          if ($26 != null) {
                            Identifier expr = $26.$1;
                            result = expr;
                            $25 = true;
                          }
                          if (!$25) {
                            var $27 = false;
                            final $28 = parsePrimaryExpression(state);
                            if ($28 != null) {
                              AstNode expr = $28.$1;
                              result = expr;
                              $27 = true;
                            }
                            if (!$27) {
                              $2 = false;
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    if ($2) {
      final AstNode $$;
      $$ = _setNodeSpan(result!, startPos, state.position, state);
      AstNode $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **SingleChars**
  ///
  ///```text
  /// `String`
  /// SingleChars =>
  ///   <
  ///     @while (*) (
  ///       '\\'
  ///       .
  ///       ----
  ///       !"'"
  ///       .
  ///     )
  ///   >
  ///```
  String parseSingleChars(State state) {
    final $0 = state.position;
    while (true) {
      var $1 = true;
      final $3 = state.position;
      var $2 = false;
      if (state.peek() == 92) {
        state.consume('\\', $3);
        final $4 = state.peek();
        if ($4 != 0) {
          state.position += state.charSize($4);
          $2 = true;
        } else {
          state.fail();
        }
      } else {
        state.expected('\\');
      }
      if (!$2) {
        state.position = $3;
        final $6 = state.position;
        var $5 = false;
        final $7 = state.predicate;
        state.predicate = true;
        var $8 = true;
        if (state.peek() == 39) {
          state.position += state.charSize(39);
          state.failAndBacktrack($6);
          $8 = false;
        } else {
          state.fail();
        }
        state.predicate = $7;
        if ($8) {
          final $9 = state.peek();
          if ($9 != 0) {
            state.position += state.charSize($9);
            $5 = true;
          } else {
            state.fail();
          }
        }
        if (!$5) {
          state.position = $6;
          $1 = false;
        }
      }
      if (!$1) {
        break;
      }
    }
    final $10 = state.substring($0, state.position);
    return $10;
  }

  /// **Start**
  ///
  ///```text
  /// `Program`
  /// Start =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   ShebangLine?
  ///   S
  ///   statements = Statements
  ///   EOF
  ///   $ = {
  ///     final node = Program(statements);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (Program,)? parseStart(State state) {
    final $1 = state.position;
    (Program,)? $0;
    final startPos = state.position;
    final $2 = parseShebangLine(state);
    state.unused = $2;
    parseS(state);
    final $3 = parseStatements(state);
    List<AstNode> statements = $3;
    final $4 = parseEOF(state);
    if ($4 != null) {
      final Program $$;
      final node = Program(statements);
      $$ = _setNodeSpan(node, startPos, state.position, state);
      Program $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **Statement**
  ///
  ///```text
  /// `AstNode`
  /// Statement =>
  ///   (
  ///     IfStatement
  ///     ----
  ///     Assignment
  ///     ----
  ///     TableKeyAssignment
  ///     ----
  ///     LocalDeclaration
  ///     ----
  ///     WhileStatement
  ///     ----
  ///     ForLoop
  ///     ----
  ///     ForInLoop
  ///     ----
  ///     RepeatUntilLoop
  ///     ----
  ///     FunctionDef
  ///     ----
  ///     LocalFunctionDef
  ///     ----
  ///     ReturnStatement
  ///     ----
  ///     YieldStatement
  ///     ----
  ///     MetatableAssignment
  ///     ----
  ///     ExpressionStatement
  ///     ----
  ///     Break
  ///     ----
  ///     Label
  ///     ----
  ///     Goto
  ///     ----
  ///     DoBlock
  ///     ----
  ///     DirectStringFunctionCall
  ///   )
  ///```
  (AstNode,)? parseStatement(State state) {
    (AstNode,)? $0;
    final $1 = parseIfStatement(state);
    if ($1 != null) {
      $0 = $1;
    } else {
      final $2 = parseAssignment(state);
      if ($2 != null) {
        $0 = $2;
      } else {
        final $3 = parseTableKeyAssignment(state);
        if ($3 != null) {
          $0 = $3;
        } else {
          final $4 = parseLocalDeclaration(state);
          if ($4 != null) {
            $0 = $4;
          } else {
            final $5 = parseWhileStatement(state);
            if ($5 != null) {
              $0 = $5;
            } else {
              final $6 = parseForLoop(state);
              if ($6 != null) {
                $0 = $6;
              } else {
                final $7 = parseForInLoop(state);
                if ($7 != null) {
                  $0 = $7;
                } else {
                  final $8 = parseRepeatUntilLoop(state);
                  if ($8 != null) {
                    $0 = $8;
                  } else {
                    final $9 = parseFunctionDef(state);
                    if ($9 != null) {
                      $0 = $9;
                    } else {
                      final $10 = parseLocalFunctionDef(state);
                      if ($10 != null) {
                        $0 = $10;
                      } else {
                        final $11 = parseReturnStatement(state);
                        if ($11 != null) {
                          $0 = $11;
                        } else {
                          final $12 = parseYieldStatement(state);
                          if ($12 != null) {
                            $0 = $12;
                          } else {
                            final $13 = parseMetatableAssignment(state);
                            if ($13 != null) {
                              $0 = $13;
                            } else {
                              final $14 = parseExpressionStatement(state);
                              if ($14 != null) {
                                $0 = $14;
                              } else {
                                final $15 = parseBreak(state);
                                if ($15 != null) {
                                  $0 = $15;
                                } else {
                                  final $16 = parseLabel(state);
                                  if ($16 != null) {
                                    $0 = $16;
                                  } else {
                                    final $17 = parseGoto(state);
                                    if ($17 != null) {
                                      $0 = $17;
                                    } else {
                                      final $18 = parseDoBlock(state);
                                      if ($18 != null) {
                                        $0 = $18;
                                      } else {
                                        final $19 =
                                            parseDirectStringFunctionCall(
                                              state,
                                            );
                                        if ($19 != null) {
                                          $0 = $19;
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    return $0;
  }

  /// **Statements**
  ///
  ///```text
  /// `List<AstNode>`
  /// Statements =>
  ///   {
  ///     List<AstNode> statements = [];
  ///   }
  ///   @while (*) (
  ///     (
  ///       OneOrMoreSemicolons
  ///       {
  ///         // No statement, but we used some semicolons
  ///       }
  ///       ----
  ///       OptionalSemi
  ///       st = Statement
  ///       OptionalSemi
  ///       {
  ///         statements.add(st);
  ///       }
  ///     )
  ///   )
  ///   $ = {
  ///     $$ = statements;
  ///   }
  ///```
  List<AstNode> parseStatements(State state) {
    List<AstNode> statements = [];
    while (true) {
      var $0 = true;
      var $1 = false;
      final $2 = parseOneOrMoreSemicolons(state);
      if ($2 != null) {
        // No statement, but we used some semicolons
        $1 = true;
      }
      if (!$1) {
        final $4 = state.position;
        var $3 = false;
        parseOptionalSemi(state);
        final $5 = parseStatement(state);
        if ($5 != null) {
          AstNode st = $5.$1;
          parseOptionalSemi(state);
          statements.add(st);
          $3 = true;
        }
        if (!$3) {
          state.position = $4;
          $0 = false;
        }
      }
      if (!$0) {
        break;
      }
    }
    final List<AstNode> $$;
    $$ = statements;
    List<AstNode> $ = $$;
    return $;
  }

  /// **String**
  ///
  ///```text
  /// `StringLiteral`
  /// String =>
  ///   {
  ///     String value = '';
  ///     final startPos = state.position;
  ///   }
  ///   (
  ///     c = LongString
  ///     {value = c;}
  ///     ----
  ///     '"'
  ///     c = DoubleChars?
  ///     '"'
  ///     S
  ///     {value = c;}
  ///     ----
  ///     '\''
  ///     c = SingleChars?
  ///     '\''
  ///     S
  ///     {value = c;}
  ///   )
  ///   $ = {
  ///     final node = StringLiteral(value);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (StringLiteral,)? parseString(State state) {
    final $1 = state.position;
    (StringLiteral,)? $0;
    String value = '';
    final startPos = state.position;
    var $2 = true;
    var $3 = false;
    final $4 = parseLongString(state);
    if ($4 != null) {
      String c = $4.$1;
      value = c;
      $3 = true;
    }
    if (!$3) {
      final $6 = state.position;
      var $5 = false;
      if (state.peek() == 34) {
        state.consume('"', $6);
        String? $8;
        final $7 = parseDoubleChars(state);
        $8 = $7;
        String? c = $8;
        final $9 = state.position;
        if (state.peek() == 34) {
          state.consume('"', $9);
          parseS(state);
          value = c;
          $5 = true;
        } else {
          state.expected('"');
        }
      } else {
        state.expected('"');
      }
      if (!$5) {
        state.position = $6;
        final $11 = state.position;
        var $10 = false;
        if (state.peek() == 39) {
          state.consume('\'', $11);
          String? $13;
          final $12 = parseSingleChars(state);
          $13 = $12;
          String? c = $13;
          final $14 = state.position;
          if (state.peek() == 39) {
            state.consume('\'', $14);
            parseS(state);
            value = c;
            $10 = true;
          } else {
            state.expected('\'');
          }
        } else {
          state.expected('\'');
        }
        if (!$10) {
          state.position = $11;
          $2 = false;
        }
      }
    }
    if ($2) {
      final StringLiteral $$;
      final node = StringLiteral(value);
      $$ = _setNodeSpan(node, startPos, state.position, state);
      StringLiteral $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **TableConstructor**
  ///
  ///```text
  /// `TableConstructor`
  /// TableConstructor =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   '{'
  ///   S
  ///   entries = TableEntries?
  ///   '}'
  ///   S
  ///   $ = {
  ///     final node = TableConstructor(entries ?? []);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (TableConstructor,)? parseTableConstructor(State state) {
    final $1 = state.position;
    (TableConstructor,)? $0;
    final startPos = state.position;
    final $2 = state.position;
    if (state.peek() == 123) {
      state.consume('{', $2);
      parseS(state);
      List<TableEntry>? $4;
      final $3 = parseTableEntries(state);
      if ($3 != null) {
        $4 = $3.$1;
      }
      List<TableEntry>? entries = $4;
      final $5 = state.position;
      if (state.peek() == 125) {
        state.consume('}', $5);
        parseS(state);
        final TableConstructor $$;
        final node = TableConstructor(entries ?? []);
        $$ = _setNodeSpan(node, startPos, state.position, state);
        TableConstructor $ = $$;
        $0 = ($,);
      } else {
        state.expected('}');
      }
    } else {
      state.expected('{');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **TableEntries**
  ///
  ///```text
  /// `List<TableEntry>`
  /// TableEntries =>
  ///   {
  ///     List<TableEntry> entries = [];
  ///   }
  ///   (
  ///     first = TableEntry
  ///     { entries.add(first); }
  ///     @while (*) (
  ///       (
  ///         ','
  ///         S
  ///         ----
  ///         ';'
  ///         S
  ///       )
  ///       next = TableEntry
  ///       { entries.add(next); }
  ///     )
  ///   )
  ///   (
  ///     ','
  ///     S
  ///     ----
  ///     ';'
  ///     S
  ///   )?
  ///   $ = {
  ///     $$ = entries;
  ///   }
  ///```
  (List<TableEntry>,)? parseTableEntries(State state) {
    final $1 = state.position;
    (List<TableEntry>,)? $0;
    List<TableEntry> entries = [];
    var $2 = false;
    final $3 = parseTableEntry(state);
    if ($3 != null) {
      TableEntry first = $3.$1;
      entries.add(first);
      while (true) {
        final $5 = state.position;
        var $4 = false;
        var $6 = true;
        var $7 = false;
        if (state.peek() == 44) {
          state.consume(',', $5);
          parseS(state);
          $7 = true;
        } else {
          state.expected(',');
        }
        if (!$7) {
          var $8 = false;
          if (state.peek() == 59) {
            state.consume(';', $5);
            parseS(state);
            $8 = true;
          } else {
            state.expected(';');
          }
          if (!$8) {
            $6 = false;
          }
        }
        if ($6) {
          final $9 = parseTableEntry(state);
          if ($9 != null) {
            TableEntry next = $9.$1;
            entries.add(next);
            $4 = true;
          }
        }
        if (!$4) {
          state.position = $5;
          break;
        }
      }
      $2 = true;
    }
    if ($2) {
      var $10 = true;
      var $11 = false;
      final $12 = state.position;
      if (state.peek() == 44) {
        state.consume(',', $12);
        parseS(state);
        $11 = true;
      } else {
        state.expected(',');
      }
      if (!$11) {
        var $13 = false;
        final $14 = state.position;
        if (state.peek() == 59) {
          state.consume(';', $14);
          parseS(state);
          $13 = true;
        } else {
          state.expected(';');
        }
        if (!$13) {
          $10 = false;
        }
      }
      state.unused = $10;
      final List<TableEntry> $$;
      $$ = entries;
      List<TableEntry> $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **TableEntry**
  ///
  ///```text
  /// `TableEntry`
  /// TableEntry =>
  ///   {
  ///     final startPos = state.position;
  ///     TableEntry? node;
  ///   }
  ///   (
  ///     '['
  ///     S
  ///     key = Expression
  ///     S
  ///     ']'
  ///     S
  ///     '='
  ///     S
  ///     value = Expression
  ///     {
  ///       node = IndexedTableEntry(key, value);
  ///     }
  ///     ----
  ///     key = ID
  ///     S
  ///     '='
  ///     S
  ///     value = Expression
  ///     {
  ///       node = KeyedTableEntry(key, value);
  ///     }
  ///     ----
  ///     expr = Expression
  ///     {
  ///       node = TableEntryLiteral(expr);
  ///     }
  ///   )
  ///   $ = {
  ///     $$ = _setNodeSpan(node as TableEntry, startPos, state.position, state);
  ///   }
  ///```
  (TableEntry,)? parseTableEntry(State state) {
    final $1 = state.position;
    (TableEntry,)? $0;
    final startPos = state.position;
    TableEntry? node;
    var $2 = true;
    final $4 = state.position;
    var $3 = false;
    if (state.peek() == 91) {
      state.consume('[', $4);
      parseS(state);
      final $5 = parseExpression(state);
      if ($5 != null) {
        AstNode key = $5.$1;
        parseS(state);
        final $6 = state.position;
        if (state.peek() == 93) {
          state.consume(']', $6);
          parseS(state);
          final $7 = state.position;
          if (state.peek() == 61) {
            state.consume('=', $7);
            parseS(state);
            final $8 = parseExpression(state);
            if ($8 != null) {
              AstNode value = $8.$1;
              node = IndexedTableEntry(key, value);
              $3 = true;
            }
          } else {
            state.expected('=');
          }
        } else {
          state.expected(']');
        }
      }
    } else {
      state.expected('[');
    }
    if (!$3) {
      state.position = $4;
      final $10 = state.position;
      var $9 = false;
      final $11 = parseID(state);
      if ($11 != null) {
        Identifier key = $11.$1;
        parseS(state);
        final $12 = state.position;
        if (state.peek() == 61) {
          state.consume('=', $12);
          parseS(state);
          final $13 = parseExpression(state);
          if ($13 != null) {
            AstNode value = $13.$1;
            node = KeyedTableEntry(key, value);
            $9 = true;
          }
        } else {
          state.expected('=');
        }
      }
      if (!$9) {
        state.position = $10;
        var $14 = false;
        final $15 = parseExpression(state);
        if ($15 != null) {
          AstNode expr = $15.$1;
          node = TableEntryLiteral(expr);
          $14 = true;
        }
        if (!$14) {
          $2 = false;
        }
      }
    }
    if ($2) {
      final TableEntry $$;
      $$ = _setNodeSpan(node as TableEntry, startPos, state.position, state);
      TableEntry $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **TableFieldAccess**
  ///
  ///```text
  /// `AstNode`
  /// TableFieldAccess =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   table = ID
  ///   { List<Identifier> fields = []; }
  ///   @while (+) (
  ///     '.'
  ///     S
  ///     field = ID
  ///     { fields.add(field); }
  ///   )
  ///   $ = {
  ///     TableAccessExpr result = TableAccessExpr(table, fields[0]);
  ///     for (var i = 1; i < fields.length; i++) {
  ///       result = TableAccessExpr(result, fields[i]);
  ///     }
  ///     $$ = _setNodeSpan(result, startPos, state.position, state);
  ///   }
  ///```
  (AstNode,)? parseTableFieldAccess(State state) {
    final $1 = state.position;
    (AstNode,)? $0;
    final startPos = state.position;
    final $2 = parseID(state);
    if ($2 != null) {
      Identifier table = $2.$1;
      List<Identifier> fields = [];
      final $3 = state.position;
      while (true) {
        final $5 = state.position;
        var $4 = false;
        if (state.peek() == 46) {
          state.consume('.', $5);
          parseS(state);
          final $6 = parseID(state);
          if ($6 != null) {
            Identifier field = $6.$1;
            fields.add(field);
            $4 = true;
          }
        } else {
          state.expected('.');
        }
        if (!$4) {
          state.position = $5;
          break;
        }
      }
      if ($3 != state.position) {
        final AstNode $$;
        TableAccessExpr result = TableAccessExpr(table, fields[0]);
        for (var i = 1; i < fields.length; i++) {
          result = TableAccessExpr(result, fields[i]);
        }
        $$ = _setNodeSpan(result, startPos, state.position, state);
        AstNode $ = $$;
        $0 = ($,);
      }
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **TableIndexAccess**
  ///
  ///```text
  /// `AstNode`
  /// TableIndexAccess =>
  ///   {
  ///     AstNode? expr;
  ///     final startPos = state.position;
  ///   }
  ///   (
  ///     '('
  ///     S
  ///     inner = Expression
  ///     ')'
  ///     S
  ///     { expr = inner; }
  ///     ----
  ///     constructor = TableConstructor
  ///     { expr = constructor; }
  ///   )
  ///   &{ expr != null }
  ///   '['
  ///   S
  ///   index = Expression
  ///   ']'
  ///   S
  ///   $ = {
  ///     final node = TableAccessExpr(expr, index);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (AstNode,)? parseTableIndexAccess(State state) {
    final $1 = state.position;
    (AstNode,)? $0;
    AstNode? expr;
    final startPos = state.position;
    var $2 = true;
    final $4 = state.position;
    var $3 = false;
    if (state.peek() == 40) {
      state.consume('(', $4);
      parseS(state);
      final $5 = parseExpression(state);
      if ($5 != null) {
        AstNode inner = $5.$1;
        final $6 = state.position;
        if (state.peek() == 41) {
          state.consume(')', $6);
          parseS(state);
          expr = inner;
          $3 = true;
        } else {
          state.expected(')');
        }
      }
    } else {
      state.expected('(');
    }
    if (!$3) {
      state.position = $4;
      var $7 = false;
      final $8 = parseTableConstructor(state);
      if ($8 != null) {
        TableConstructor constructor = $8.$1;
        expr = constructor;
        $7 = true;
      }
      if (!$7) {
        $2 = false;
      }
    }
    if ($2) {
      if (expr != null) {
        final $9 = state.position;
        if (state.peek() == 91) {
          state.consume('[', $9);
          parseS(state);
          final $10 = parseExpression(state);
          if ($10 != null) {
            AstNode index = $10.$1;
            final $11 = state.position;
            if (state.peek() == 93) {
              state.consume(']', $11);
              parseS(state);
              final AstNode $$;
              final node = TableAccessExpr(expr, index);
              $$ = _setNodeSpan(node, startPos, state.position, state);
              AstNode $ = $$;
              $0 = ($,);
            } else {
              state.expected(']');
            }
          }
        } else {
          state.expected('[');
        }
      }
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **TableKeyAssignment**
  ///
  ///```text
  /// `AssignmentIndexAccessExpr`
  /// TableKeyAssignment =>
  ///   {
  ///     final startPos = state.position;
  ///     AssignmentIndexAccessExpr? node;
  ///   }
  ///   (
  ///     S
  ///     identifier = S
  ///     '['
  ///     S
  ///     key = Expression
  ///     S
  ///     ']'
  ///     S
  ///     '='
  ///     S
  ///     value = Expression
  ///     S
  ///     {  node = AssignmentIndexAccessExpr(identifier as AstNode, key, value); }
  ///     ----
  ///     S
  ///     identifier = ID
  ///     S
  ///     '['
  ///     S
  ///     key = Expression
  ///     S
  ///     ']'
  ///     S
  ///     '='
  ///     S
  ///     value = Expression
  ///     S
  ///     {node = AssignmentIndexAccessExpr(identifier, key, value);}
  ///   )
  ///   $ = {
  ///     $$ = _setNodeSpan(node!, startPos, state.position, state);
  ///   }
  ///```
  (AssignmentIndexAccessExpr,)? parseTableKeyAssignment(State state) {
    final $1 = state.position;
    (AssignmentIndexAccessExpr,)? $0;
    final startPos = state.position;
    AssignmentIndexAccessExpr? node;
    var $2 = true;
    final $4 = state.position;
    var $3 = false;
    parseS(state);
    final $5 = parseS(state);
    void identifier = $5;
    final $6 = state.position;
    if (state.peek() == 91) {
      state.consume('[', $6);
      parseS(state);
      final $7 = parseExpression(state);
      if ($7 != null) {
        AstNode key = $7.$1;
        parseS(state);
        final $8 = state.position;
        if (state.peek() == 93) {
          state.consume(']', $8);
          parseS(state);
          final $9 = state.position;
          if (state.peek() == 61) {
            state.consume('=', $9);
            parseS(state);
            final $10 = parseExpression(state);
            if ($10 != null) {
              AstNode value = $10.$1;
              parseS(state);
              node = AssignmentIndexAccessExpr(
                identifier as AstNode,
                key,
                value,
              );
              $3 = true;
            }
          } else {
            state.expected('=');
          }
        } else {
          state.expected(']');
        }
      }
    } else {
      state.expected('[');
    }
    if (!$3) {
      state.position = $4;
      final $12 = state.position;
      var $11 = false;
      parseS(state);
      final $13 = parseID(state);
      if ($13 != null) {
        Identifier identifier = $13.$1;
        parseS(state);
        final $14 = state.position;
        if (state.peek() == 91) {
          state.consume('[', $14);
          parseS(state);
          final $15 = parseExpression(state);
          if ($15 != null) {
            AstNode key = $15.$1;
            parseS(state);
            final $16 = state.position;
            if (state.peek() == 93) {
              state.consume(']', $16);
              parseS(state);
              final $17 = state.position;
              if (state.peek() == 61) {
                state.consume('=', $17);
                parseS(state);
                final $18 = parseExpression(state);
                if ($18 != null) {
                  AstNode value = $18.$1;
                  parseS(state);
                  node = AssignmentIndexAccessExpr(identifier, key, value);
                  $11 = true;
                }
              } else {
                state.expected('=');
              }
            } else {
              state.expected(']');
            }
          }
        } else {
          state.expected('[');
        }
      }
      if (!$11) {
        state.position = $12;
        $2 = false;
      }
    }
    if ($2) {
      final AssignmentIndexAccessExpr $$;
      $$ = _setNodeSpan(node!, startPos, state.position, state);
      AssignmentIndexAccessExpr $ = $$;
      $0 = ($,);
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **TableLookup**
  ///
  ///```text
  /// `AstNode`
  /// TableLookup =>
  ///   {
  ///     AstNode? expr;
  ///     final startPos = state.position;
  ///   }
  ///   table = ID
  ///   { expr = table; }
  ///   @while (+) (
  ///     (
  ///       '['
  ///       S
  ///       index = Expression
  ///       ']'
  ///       S
  ///       { expr = TableAccessExpr(expr!, index); }
  ///       ----
  ///       '.'
  ///       S
  ///       field = ID
  ///       { expr = TableAccessExpr(expr!, field); }
  ///     )
  ///   )
  ///   $ = {
  ///     $$ = _setNodeSpan(expr!, startPos, state.position, state);
  ///   }
  ///```
  (AstNode,)? parseTableLookup(State state) {
    final $1 = state.position;
    (AstNode,)? $0;
    AstNode? expr;
    final startPos = state.position;
    final $2 = parseID(state);
    if ($2 != null) {
      Identifier table = $2.$1;
      expr = table;
      final $3 = state.position;
      while (true) {
        var $4 = true;
        final $6 = state.position;
        var $5 = false;
        if (state.peek() == 91) {
          state.consume('[', $6);
          parseS(state);
          final $7 = parseExpression(state);
          if ($7 != null) {
            AstNode index = $7.$1;
            final $8 = state.position;
            if (state.peek() == 93) {
              state.consume(']', $8);
              parseS(state);
              expr = TableAccessExpr(expr!, index);
              $5 = true;
            } else {
              state.expected(']');
            }
          }
        } else {
          state.expected('[');
        }
        if (!$5) {
          state.position = $6;
          final $10 = state.position;
          var $9 = false;
          if (state.peek() == 46) {
            state.consume('.', $10);
            parseS(state);
            final $11 = parseID(state);
            if ($11 != null) {
              Identifier field = $11.$1;
              expr = TableAccessExpr(expr!, field);
              $9 = true;
            }
          } else {
            state.expected('.');
          }
          if (!$9) {
            state.position = $10;
            $4 = false;
          }
        }
        if (!$4) {
          break;
        }
      }
      if ($3 != state.position) {
        final AstNode $$;
        $$ = _setNodeSpan(expr!, startPos, state.position, state);
        AstNode $ = $$;
        $0 = ($,);
      }
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **TrailingComma**
  ///
  ///```text
  /// `void`
  /// TrailingComma =>
  ///   (
  ///     ','
  ///     S
  ///   )?
  ///```
  void parseTrailingComma(State state) {
    final $1 = state.position;
    var $0 = false;
    if (state.peek() == 44) {
      state.consume(',', $1);
      parseS(state);
      $0 = true;
    } else {
      state.expected(',');
    }
  }

  /// **UnaryExpression**
  ///
  ///```text
  /// `AstNode`
  /// UnaryExpression =>
  ///   (
  ///     {
  ///       final startPos = state.position;
  ///     }
  ///     op = Unop
  ///     S
  ///     expr = UnaryExpression
  ///     $ = {
  ///       final node = UnaryExpression(op, expr);
  ///       $$ = _setNodeSpan(node, startPos, state.position, state);
  ///     }
  ///   )
  ///   ----
  ///   ExponentiationExpression
  ///```
  (AstNode,)? parseUnaryExpression(State state) {
    final $2 = state.position;
    (AstNode,)? $0;
    (AstNode,)? $1;
    final startPos = state.position;
    final $3 = parseUnop(state);
    if ($3 != null) {
      String op = $3.$1;
      parseS(state);
      final $4 = parseUnaryExpression(state);
      if ($4 != null) {
        AstNode expr = $4.$1;
        final AstNode $$;
        final node = UnaryExpression(op, expr);
        $$ = _setNodeSpan(node, startPos, state.position, state);
        AstNode $ = $$;
        $1 = ($,);
      }
    }
    if ($1 != null) {
      $0 = $1;
    } else {
      state.position = $2;
      final $5 = parseExponentiationExpression(state);
      if ($5 != null) {
        $0 = $5;
      }
    }
    return $0;
  }

  /// **Unop**
  ///
  ///```text
  /// `String`
  /// Unop =>
  ///   'not'
  ///   ----
  ///   '-'
  ///   ----
  ///   '#'
  ///   ----
  ///   '~'
  ///   ----
  ///   '!'
  ///   ----
  ///   '&'
  ///   ----
  ///   '|'
  ///   ----
  ///   '^'
  ///```
  (String,)? parseUnop(State state) {
    final $1 = state.position;
    (String,)? $0;
    if (state.peek() == 110 && state.startsWith('not', state.position)) {
      state.consume('not', $1);
      $0 = ('not',);
    } else {
      state.expected('not');
      if (state.peek() == 45) {
        state.consume('-', $1);
        $0 = ('-',);
      } else {
        state.expected('-');
        if (state.peek() == 35) {
          state.consume('#', $1);
          $0 = ('#',);
        } else {
          state.expected('#');
          if (state.peek() == 126) {
            state.consume('~', $1);
            $0 = ('~',);
          } else {
            state.expected('~');
            if (state.peek() == 33) {
              state.consume('!', $1);
              $0 = ('!',);
            } else {
              state.expected('!');
              if (state.peek() == 38) {
                state.consume('&', $1);
                $0 = ('&',);
              } else {
                state.expected('&');
                if (state.peek() == 124) {
                  state.consume('|', $1);
                  $0 = ('|',);
                } else {
                  state.expected('|');
                  if (state.peek() == 94) {
                    state.consume('^', $1);
                    $0 = ('^',);
                  } else {
                    state.expected('^');
                  }
                }
              }
            }
          }
        }
      }
    }
    return $0;
  }

  /// **VarArg**
  ///
  ///```text
  /// `VarArg`
  /// VarArg =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   '...'
  ///   S
  ///   $ = {
  ///     final node = VarArg();
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (VarArg,)? parseVarArg(State state) {
    final $1 = state.position;
    (VarArg,)? $0;
    final startPos = state.position;
    final $2 = state.position;
    if (state.peek() == 46 && state.startsWith('...', state.position)) {
      state.consume('...', $2);
      parseS(state);
      final VarArg $$;
      final node = VarArg();
      $$ = _setNodeSpan(node, startPos, state.position, state);
      VarArg $ = $$;
      $0 = ($,);
    } else {
      state.expected('...');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **Vararg**
  ///
  ///```text
  /// `VarArg`
  /// Vararg =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   '...'
  ///   S
  ///   $ = {
  ///     final node = VarArg();
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (VarArg,)? parseVararg(State state) {
    final $1 = state.position;
    (VarArg,)? $0;
    final startPos = state.position;
    final $2 = state.position;
    if (state.peek() == 46 && state.startsWith('...', state.position)) {
      state.consume('...', $2);
      parseS(state);
      final VarArg $$;
      final node = VarArg();
      $$ = _setNodeSpan(node, startPos, state.position, state);
      VarArg $ = $$;
      $0 = ($,);
    } else {
      state.expected('...');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **WhileStatement**
  ///
  ///```text
  /// `WhileStatement`
  /// WhileStatement =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   'while'
  ///   !IdChar
  ///   S
  ///   cond = Expression
  ///   (
  ///     'do'
  ///     !IdChar
  ///     S
  ///      ~ { message = 'Expected `do` after condition in while loop' }
  ///   )
  ///   body = Statements
  ///   (
  ///     'end'
  ///     !IdChar
  ///     S
  ///      ~ { message = 'Expected `end` to close while loop' }
  ///   )
  ///   $ = {
  ///     final node = WhileStatement(cond, body);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (WhileStatement,)? parseWhileStatement(State state) {
    final $1 = state.position;
    (WhileStatement,)? $0;
    final startPos = state.position;
    final $2 = state.position;
    if (state.peek() == 119 && state.startsWith('while', state.position)) {
      state.consume('while', $2);
      final $3 = state.position;
      final $4 = state.predicate;
      state.predicate = true;
      var $6 = true;
      final $5 = parseIdChar(state);
      if ($5 != null) {
        state.failAndBacktrack($3);
        $6 = false;
      }
      state.predicate = $4;
      if ($6) {
        parseS(state);
        final $7 = parseExpression(state);
        if ($7 != null) {
          AstNode cond = $7.$1;
          final $14 = state.failure;
          state.failure = state.position;
          final $9 = state.position;
          var $8 = false;
          if (state.peek() == 100 && state.startsWith('do', state.position)) {
            state.consume('do', $9);
            final $10 = state.position;
            final $11 = state.predicate;
            state.predicate = true;
            var $13 = true;
            final $12 = parseIdChar(state);
            if ($12 != null) {
              state.failAndBacktrack($10);
              $13 = false;
            }
            state.predicate = $11;
            if ($13) {
              parseS(state);
              $8 = true;
            }
          } else {
            state.expected('do');
          }
          if ($8) {
            state.failure < $14 ? state.failure = $14 : null;
            final $15 = parseStatements(state);
            List<AstNode> body = $15;
            final $22 = state.failure;
            state.failure = state.position;
            final $17 = state.position;
            var $16 = false;
            if (state.peek() == 101 &&
                state.startsWith('end', state.position)) {
              state.consume('end', $17);
              final $18 = state.position;
              final $19 = state.predicate;
              state.predicate = true;
              var $21 = true;
              final $20 = parseIdChar(state);
              if ($20 != null) {
                state.failAndBacktrack($18);
                $21 = false;
              }
              state.predicate = $19;
              if ($21) {
                parseS(state);
                $16 = true;
              }
            } else {
              state.expected('end');
            }
            if ($16) {
              state.failure < $22 ? state.failure = $22 : null;
              final WhileStatement $$;
              final node = WhileStatement(cond, body);
              $$ = _setNodeSpan(node, startPos, state.position, state);
              WhileStatement $ = $$;
              $0 = ($,);
            } else {
              state.position = $17;
              state.error(
                'Expected `end` to close while loop',
                state.position,
                state.failure,
                3,
              );
              state.failure < $22 ? state.failure = $22 : null;
            }
          } else {
            state.position = $9;
            state.error(
              'Expected `do` after condition in while loop',
              state.position,
              state.failure,
              3,
            );
            state.failure < $14 ? state.failure = $14 : null;
          }
        }
      }
    } else {
      state.expected('while');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }

  /// **YieldStatement**
  ///
  ///```text
  /// `YieldStatement`
  /// YieldStatement =>
  ///   {
  ///     final startPos = state.position;
  ///   }
  ///   'return'
  ///   !IdChar
  ///   S
  ///   exprs = ExpressionList?
  ///   S
  ///   $ = {
  ///     final node = YieldStatement(exprs);
  ///     $$ = _setNodeSpan(node, startPos, state.position, state);
  ///   }
  ///```
  (YieldStatement,)? parseYieldStatement(State state) {
    final $1 = state.position;
    (YieldStatement,)? $0;
    final startPos = state.position;
    final $2 = state.position;
    if (state.peek() == 114 && state.startsWith('return', state.position)) {
      state.consume('return', $2);
      final $3 = state.position;
      final $4 = state.predicate;
      state.predicate = true;
      var $6 = true;
      final $5 = parseIdChar(state);
      if ($5 != null) {
        state.failAndBacktrack($3);
        $6 = false;
      }
      state.predicate = $4;
      if ($6) {
        parseS(state);
        List<AstNode>? $8;
        final $7 = parseExpressionList(state);
        $8 = $7;
        List<AstNode>? exprs = $8;
        parseS(state);
        final YieldStatement $$;
        final node = YieldStatement(exprs);
        $$ = _setNodeSpan(node, startPos, state.position, state);
        YieldStatement $ = $$;
        $0 = ($,);
      }
    } else {
      state.expected('return');
    }
    if ($0 != null) {
      return $0;
    } else {
      state.position = $1;
      return null;
    }
  }
}

class State {
  /// Intended for internal use only.
  static const flagUseStart = 1;

  /// Intended for internal use only.
  static const flagUseEnd = 2;

  /// Intended for internal use only.
  static const flagExpected = 4;

  /// Intended for internal use only.
  static const flagUnexpected = 8;

  /// The position of the parsing failure.
  int failure = 0;

  /// The length of the input data.
  final int length;

  /// Intended for internal use only.
  int nesting = -1;

  /// Intended for internal use only.
  bool predicate = false;

  /// Current parsing position.
  int position = 0;

  /// Current parsing position.
  Object? unused;

  int _ch = 0;

  int _errorIndex = 0;

  int _farthestError = 0;

  int _farthestFailure = 0;

  int _farthestFailureLength = 0;

  final List<int?> _flags = List.filled(128, null);

  final String _input;

  final List<String?> _messages = List.filled(128, null);

  int _peekPosition = -1;

  final List<int?> _starts = List.filled(128, null);

  State(String input) : _input = input, length = input.length {
    peek();
  }

  /// Intended for internal use only.
  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  int charSize(int char) => char > 0xffff ? 2 : 1;

  /// Intended for internal use only.
  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  void consume(String literal, int start) {
    position += strlen(literal);
    if (predicate && nesting < position) {
      error(literal, start, position, flagUnexpected);
    }
  }

  /// Intended for internal use only.
  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  void error(String message, int start, int end, int flag) {
    if (_farthestError > end) {
      return;
    }

    if (_farthestError < end) {
      _farthestError = end;
      _errorIndex = 0;
    }

    if (_errorIndex < _messages.length) {
      _flags[_errorIndex] = flag;
      _messages[_errorIndex] = message;
      _starts[_errorIndex] = start;
      _errorIndex++;
    }
  }

  /// Intended for internal use only.
  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  void expected(String literal) {
    if (nesting < position && !predicate) {
      error(literal, position, position, flagExpected);
    }

    fail();
  }

  /// Intended for internal use only.
  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  void fail([String? name]) {
    failure < position ? failure = position : null;
    if (_farthestFailure < position) {
      _farthestFailure = position;
      _farthestFailureLength = 0;
    }

    if (name != null && nesting < position) {
      error(name, position, position, flagExpected);
    }
  }

  /// Intended for internal use only.
  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  void failAndBacktrack(int position) {
    fail();
    final length = this.position - position;
    _farthestFailureLength < length ? _farthestFailureLength = length : null;
    this.position = position;
  }

  /// Converts error messages to errors and returns them as an error list.
  List<({int end, String message, int start})> getErrors() {
    final errors = <({int end, String message, int start})>[];
    final expected = <String>{};
    final unexpected = <(int, int), Set<String>>{};
    for (var i = 0; i < _errorIndex; i++) {
      final message = _messages[i];
      if (message == null) {
        continue;
      }

      final flag = _flags[i]!;
      final startPosition = _starts[i]!;
      if (flag & (flagExpected | flagUnexpected) == 0) {
        var start = flag & flagUseStart == 0 ? startPosition : _farthestError;
        var end = flag & flagUseEnd == 0 ? _farthestError : startPosition;
        if (start > end) {
          start = startPosition;
          end = _farthestError;
        }

        errors.add((message: message, start: start, end: end));
      } else if (flag & flagExpected != 0) {
        expected.add(message);
      } else if (flag & flagUnexpected != 0) {
        (unexpected[(startPosition, _farthestError)] ??= {}).add(message);
      }
    }

    if (expected.isNotEmpty) {
      final list = expected.toList();
      list.sort();
      final message = 'Expected: ${list.map((e) => '\'$e\'').join(', ')}';
      errors.add((
        message: message,
        start: _farthestError,
        end: _farthestError,
      ));
    }

    if (unexpected.isNotEmpty) {
      for (final entry in unexpected.entries) {
        final key = entry.key;
        final value = entry.value;
        final list = value.toList();
        list.sort();
        final message = 'Unexpected: ${list.map((e) => '\'$e\'').join(', ')}';
        errors.add((message: message, start: key.$1, end: key.$2));
      }
    }

    if (errors.isEmpty) {
      errors.add((
        message: 'Unexpected input data',
        start: _farthestFailure - _farthestFailureLength,
        end: _farthestFailure,
      ));
    }

    return errors.toSet().toList();
  }

  /// Intended for internal use only.
  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  void onFailure(String name, int start, int nesting, int failure) {
    if (failure == position && nesting < position && !predicate) {
      error(name, position, position, flagExpected);
    }

    this.nesting = nesting;
    this.failure < failure ? this.failure = failure : null;
  }

  /// Intended for internal use only.
  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  void onSuccess(String name, int start, int nesting) {
    if (predicate && nesting < start) {
      error(name, start, position, flagUnexpected);
    }

    this.nesting = nesting;
  }

  /// Intended for internal use only.
  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  int peek() {
    if (_peekPosition == position) {
      return _ch;
    }

    _peekPosition = position;
    if (position < length) {
      if ((_ch = _input.codeUnitAt(position)) < 0xd800) {
        return _ch;
      }

      if (_ch < 0xe000) {
        final c = _input.codeUnitAt(position + 1);
        if ((c & 0xfc00) == 0xdc00) {
          return _ch = 0x10000 + ((_ch & 0x3ff) << 10) + (c & 0x3ff);
        }

        throw FormatException('Invalid UTF-16 character', this, position);
      }

      return _ch;
    } else {
      return _ch = 0;
    }
  }

  /// Intended for internal use only.
  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  bool startsWith(String string, int position) =>
      _input.startsWith(string, position);

  /// Intended for internal use only.
  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  int strlen(String string) => string.length;

  /// Intended for internal use only.
  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  String substring(int start, int end) => _input.substring(start, end);

  @override
  String toString() {
    if (position >= length) {
      return '';
    }

    var rest = length - position;
    if (rest > 80) {
      rest = 80;
    }

    var line = substring(position, position + rest);
    line = line.replaceAll('\n', r'\n');
    return '|$position|$line';
  }
}
