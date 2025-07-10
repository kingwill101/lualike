import 'ast.dart';

/// Simple checker for const variable assignment violations
class ConstChecker {
  final Set<String> _constVariables = {};

  /// Check for const assignment violations in a program
  String? checkConstViolations(Program program) {
    _constVariables.clear();

    try {
      for (final stmt in program.statements) {
        final error = _checkStatement(stmt);
        if (error != null) return error;
      }
      return null;
    } catch (e) {
      return 'Error checking const violations: $e';
    }
  }

  String? _checkStatement(AstNode stmt) {
    if (stmt is LocalDeclaration) {
      return _checkLocalDeclaration(stmt);
    } else if (stmt is Assignment) {
      return _checkAssignment(stmt);
    } else if (stmt is DoBlock) {
      return _checkDoBlock(stmt);
    } else if (stmt is ForLoop) {
      return _checkForLoop(stmt);
    } else if (stmt is ForInLoop) {
      return _checkForInLoop(stmt);
    } else if (stmt is WhileStatement) {
      return _checkWhileStatement(stmt);
    } else if (stmt is RepeatUntilLoop) {
      return _checkRepeatUntilLoop(stmt);
    } else if (stmt is IfStatement) {
      return _checkIfStatement(stmt);
    } else if (stmt is FunctionDef) {
      return _checkFunctionDef(stmt);
    } else if (stmt is LocalFunctionDef) {
      return _checkLocalFunctionDef(stmt);
    } else if (stmt is ExpressionStatement) {
      return _checkExpressionStatement(stmt);
    } else if (stmt is ReturnStatement) {
      return _checkReturnStatement(stmt);
    }
    // For other statement types, continue processing
    return null;
  }

  String? _checkLocalDeclaration(LocalDeclaration stmt) {
    // Check for unknown attributes and register const variables
    for (var i = 0; i < stmt.names.length; i++) {
      final name = stmt.names[i].name;
      if (i < stmt.attributes.length) {
        final attribute = stmt.attributes[i];
        if (attribute == 'const') {
          _constVariables.add(name);
        } else if (attribute == 'close') {
          // <close> is valid but treated as const for assignment purposes
          _constVariables.add(name);
        } else if (attribute.isNotEmpty) {
          // Unknown attribute
          int lineNumber = 1;
          if (stmt.span != null) {
            lineNumber =
                stmt.span!.start.line + 1; // Convert 0-based to 1-based
          }
          return ":$lineNumber: unknown attribute '$attribute'";
        }
      }
    }
    return null;
  }

  String? _checkAssignment(Assignment stmt) {
    // Check each assignment target
    for (final target in stmt.targets) {
      if (target is Identifier) {
        final name = target.name;
        if (_constVariables.contains(name)) {
          // Try to get line number from span if available
          int lineNumber = 1;
          if (stmt.span != null) {
            lineNumber =
                stmt.span!.start.line + 1; // Convert 0-based to 1-based
          }
          return ":$lineNumber: attempt to assign to const variable '$name'";
        }
      }
    }
    return null;
  }

  String? _checkDoBlock(DoBlock stmt) {
    final savedConsts = Set<String>.from(_constVariables);
    for (final s in stmt.body) {
      final error = _checkStatement(s);
      if (error != null) {
        _constVariables.clear();
        _constVariables.addAll(savedConsts);
        return error;
      }
    }
    // Restore const variables (exit scope)
    _constVariables.clear();
    _constVariables.addAll(savedConsts);
    return null;
  }

  String? _checkForLoop(ForLoop stmt) {
    final savedConsts = Set<String>.from(_constVariables);
    for (final s in stmt.body) {
      final error = _checkStatement(s);
      if (error != null) {
        _constVariables.clear();
        _constVariables.addAll(savedConsts);
        return error;
      }
    }
    _constVariables.clear();
    _constVariables.addAll(savedConsts);
    return null;
  }

  String? _checkForInLoop(ForInLoop stmt) {
    final savedConsts = Set<String>.from(_constVariables);
    for (final s in stmt.body) {
      final error = _checkStatement(s);
      if (error != null) {
        _constVariables.clear();
        _constVariables.addAll(savedConsts);
        return error;
      }
    }
    _constVariables.clear();
    _constVariables.addAll(savedConsts);
    return null;
  }

  String? _checkWhileStatement(WhileStatement stmt) {
    final savedConsts = Set<String>.from(_constVariables);
    for (final s in stmt.body) {
      final error = _checkStatement(s);
      if (error != null) {
        _constVariables.clear();
        _constVariables.addAll(savedConsts);
        return error;
      }
    }
    _constVariables.clear();
    _constVariables.addAll(savedConsts);
    return null;
  }

  String? _checkRepeatUntilLoop(RepeatUntilLoop stmt) {
    final savedConsts = Set<String>.from(_constVariables);
    for (final s in stmt.body) {
      final error = _checkStatement(s);
      if (error != null) {
        _constVariables.clear();
        _constVariables.addAll(savedConsts);
        return error;
      }
    }
    _constVariables.clear();
    _constVariables.addAll(savedConsts);
    return null;
  }

  String? _checkIfStatement(IfStatement stmt) {
    final savedConsts = Set<String>.from(_constVariables);

    // Check then block
    for (final s in stmt.thenBlock) {
      final error = _checkStatement(s);
      if (error != null) {
        _constVariables.clear();
        _constVariables.addAll(savedConsts);
        return error;
      }
    }

    // Check else-if blocks
    for (final elseIf in stmt.elseIfs) {
      for (final s in elseIf.thenBlock) {
        final error = _checkStatement(s);
        if (error != null) {
          _constVariables.clear();
          _constVariables.addAll(savedConsts);
          return error;
        }
      }
    }

    // Check else block
    for (final s in stmt.elseBlock) {
      final error = _checkStatement(s);
      if (error != null) {
        _constVariables.clear();
        _constVariables.addAll(savedConsts);
        return error;
      }
    }

    _constVariables.clear();
    _constVariables.addAll(savedConsts);
    return null;
  }

  String? _checkFunctionDef(FunctionDef stmt) {
    // Function definitions create new scopes but const variables
    // from outer scopes are still visible and assignable
    final savedConsts = Set<String>.from(_constVariables);

    // Check function body for const violations
    for (final s in stmt.body.body) {
      final error = _checkStatement(s);
      if (error != null) {
        _constVariables.clear();
        _constVariables.addAll(savedConsts);
        return error;
      }
    }

    _constVariables.clear();
    _constVariables.addAll(savedConsts);
    return null;
  }

  String? _checkLocalFunctionDef(LocalFunctionDef stmt) {
    // Local function definitions create new scopes but const variables
    // from outer scopes are still visible and assignable
    final savedConsts = Set<String>.from(_constVariables);

    // Check function body for const violations
    for (final s in stmt.funcBody.body) {
      final error = _checkStatement(s);
      if (error != null) {
        _constVariables.clear();
        _constVariables.addAll(savedConsts);
        return error;
      }
    }

    _constVariables.clear();
    _constVariables.addAll(savedConsts);
    return null;
  }

  String? _checkExpressionStatement(ExpressionStatement stmt) {
    // Check if the expression contains function literals
    return _checkExpression(stmt.expr);
  }

  String? _checkReturnStatement(ReturnStatement stmt) {
    // Check expressions in return statement for function literals
    for (final expr in stmt.expr) {
      final error = _checkExpression(expr);
      if (error != null) return error;
    }
    return null;
  }

  String? _checkExpression(AstNode expr) {
    if (expr is FunctionLiteral) {
      return _checkFunctionLiteral(expr);
    } else if (expr is FunctionCall) {
      // Check function arguments for nested function literals
      for (final arg in expr.args) {
        final error = _checkExpression(arg);
        if (error != null) return error;
      }
      return _checkExpression(expr.name);
    } else if (expr is BinaryExpression) {
      final leftError = _checkExpression(expr.left);
      if (leftError != null) return leftError;
      return _checkExpression(expr.right);
    } else if (expr is UnaryExpression) {
      return _checkExpression(expr.expr);
    } else if (expr is TableConstructor) {
      // Check table entries for function literals
      for (final entry in expr.entries) {
        final error = _checkTableEntry(entry);
        if (error != null) return error;
      }
    }
    // For other expressions, we don't need to check them for now
    return null;
  }

  String? _checkTableEntry(TableEntry entry) {
    if (entry is TableEntryLiteral) {
      return _checkExpression(entry.expr);
    } else if (entry is KeyedTableEntry) {
      return _checkExpression(entry.value);
    } else if (entry is IndexedTableEntry) {
      final keyError = _checkExpression(entry.key);
      if (keyError != null) return keyError;
      return _checkExpression(entry.value);
    }
    return null;
  }

  String? _checkFunctionLiteral(FunctionLiteral expr) {
    // Function literals create new scopes but const variables
    // from outer scopes are still visible and assignable
    final savedConsts = Set<String>.from(_constVariables);

    // Check function body for const violations
    for (final s in expr.funcBody.body) {
      final error = _checkStatement(s);
      if (error != null) {
        _constVariables.clear();
        _constVariables.addAll(savedConsts);
        return error;
      }
    }

    _constVariables.clear();
    _constVariables.addAll(savedConsts);
    return null;
  }
}
