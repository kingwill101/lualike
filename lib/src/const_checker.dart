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
    } else if (stmt is FunctionDef || stmt is LocalFunctionDef) {
      // Function definitions create new scopes, but we don't need to check them
      // for this simple implementation
      return null;
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
          return ":1: unknown attribute '$attribute'";
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
          return ":1: attempt to assign to const variable '$name'";
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
    if (stmt.elseBlock != null) {
      for (final s in stmt.elseBlock!) {
        final error = _checkStatement(s);
        if (error != null) {
          _constVariables.clear();
          _constVariables.addAll(savedConsts);
          return error;
        }
      }
    }

    _constVariables.clear();
    _constVariables.addAll(savedConsts);
    return null;
  }
}
