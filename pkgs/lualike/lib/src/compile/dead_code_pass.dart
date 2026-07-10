/// Tree-shakes unused exports from bundled modules.
///
/// After the [Bundler] inlines all dependencies, a module may export
/// functions and fields that are never referenced by any other module.
/// This pass scans the combined AST, identifies which fields are READ,
/// and removes unused writes and function definitions.
///
/// ## Example
///
/// ```lua
/// -- Before DCE:
/// local M = {}
/// function M.double(x) return x * 2 end   -- USED
/// function M.triple(x) return x * 3 end   -- never read → removed
/// M.PI = 3.14159                           -- never read → removed
/// __bundle_utils_0 = M
///
/// -- After DCE:
/// local M = {}
/// function M.double(x) return x * 2 end
/// __bundle_utils_0 = M
/// ```
library;


import 'package:lualike/src/ast.dart';
import 'package:lualike/src/compile/compiler_pass.dart';

class DeadCodeEliminationPass extends CompilerPass {
  @override
  String get name => 'dead_code_elimination';

  @override
  Program run(Program program, CompilerContext context) {
    // Phase 1: find which fields are read on each module variable.
    final usedFields = <String, Set<String>>{};
    final moduleVars = <String>{};
    final builderVars = <String, String>{};

    _findModuleVars(program, moduleVars);
    if (moduleVars.isEmpty) return program;

    _collectReads(program.statements, usedFields, moduleVars);
    _findBuilders(program.statements, moduleVars, builderVars);

    // Phase 2: remove unused writes.
    final cleaned = _eliminate(program.statements, usedFields, moduleVars, builderVars);
    return Program(cleaned);
  }

  /// Collect all `__bundle_*` variable names from local declarations.
  void _findModuleVars(Program program, Set<String> moduleVars) {
    void walk(List<AstNode> stmts) {
      for (final stmt in stmts) {
        if (stmt is LocalDeclaration) {
          for (final name in stmt.names) {
            if (name.name.startsWith('__bundle_')) moduleVars.add(name.name);
          }
        }
        if (stmt is DoBlock) walk(stmt.body);
      }
    }
    walk(program.statements);
  }

  /// Scan do-blocks for `local M = {}; ... __bundle_var = M` patterns.
  void _findBuilders(
    List<AstNode> stmts, Set<String> moduleVars, Map<String, String> builderVars,
  ) {
    for (final stmt in stmts) {
      if (stmt is! DoBlock) continue;
      final tableLocals = <String>{};
      String? bundleVar;
      for (final inner in stmt.body) {
        if (inner is LocalDeclaration &&
            inner.exprs.length == 1 &&
            inner.exprs.first is TableConstructor) {
          for (final n in inner.names) tableLocals.add(n.name);
        }
        if (inner is Assignment &&
            inner.targets.length == 1 &&
            inner.targets.first is Identifier &&
            moduleVars.contains((inner.targets.first as Identifier).name) &&
            inner.exprs.length == 1) {
          final src = inner.exprs.first is Identifier
              ? (inner.exprs.first as Identifier).name
              : null;
          if (src != null && tableLocals.contains(src)) {
            bundleVar = (inner.targets.first as Identifier).name;
            builderVars[src] = bundleVar;
          }
        }
      }
    }
  }

  /// Collect all field reads on module variables.
  void _collectReads(
    List<AstNode> stmts, Map<String, Set<String>> used, Set<String> vars,
  ) {
    for (final stmt in stmts) {
      _readNode(stmt, used, vars, {});
    }
  }

  void _readNode(
    AstNode node, Map<String, Set<String>> used, Set<String> vars, Set<String> aliases,
  ) {
    // Track local aliases: `local x = __bundle_foo` → x is alias
    if (node is LocalDeclaration) {
      for (var i = 0; i < node.names.length && i < node.exprs.length; i++) {
        final src = _varName(node.exprs[i]);
        if (src != null && (vars.contains(src) || aliases.contains(src))) {
          aliases.add(node.names[i].name);
        }
      }
    }
    // Detect field reads: `moduleVar.field` or `alias.field`
    if (node is TableFieldAccess) {
      final tbl = _varName(node.table);
      if (tbl != null && (vars.contains(tbl) || aliases.contains(tbl))) {
        final actualVar = vars.contains(tbl) ? tbl : _resolveAlias(tbl, aliases, vars);
        if (actualVar != null) {
          used.putIfAbsent(actualVar, () => <String>{});
          used[actualVar]!.add(node.fieldName.name);
        }
      }
    }
    // Detect index reads: `moduleVar["key"]` or `moduleVar[1]`
    if (node is TableIndexAccess) {
      final tbl = _varName(node.table);
      if (tbl != null && (vars.contains(tbl) || aliases.contains(tbl))) {
        final key = _constKey(node.index);
        if (key != null) {
          final actualVar = vars.contains(tbl) ? tbl : _resolveAlias(tbl, aliases, vars);
          if (actualVar != null) {
            used.putIfAbsent(actualVar, () => <String>{});
            used[actualVar]!.add(key);
          }
        }
      }
    }
    // Recurse
    if (node is DoBlock) _collectReads(node.body, used, vars);
    if (node is FunctionDef) _collectReads(node.body.body, used, vars);
    if (node is FunctionBody) _collectReads(node.body, used, vars);
    if (node is LocalFunctionDef) _collectReads(node.funcBody.body, used, vars);
    if (node is ReturnStatement) {
      for (final e in node.expr) _readNode(e, used, vars, aliases);
    }
    if (node is Assignment) {
      for (final t in node.targets) _readNode(t, used, vars, aliases);
      for (final e in node.exprs) _readNode(e, used, vars, aliases);
    }
    if (node is ExpressionStatement) _readNode(node.expr, used, vars, aliases);
  }

  /// Remove unused field writes from the AST.
  List<AstNode> _eliminate(
    List<AstNode> stmts, Map<String, Set<String>> used,
    Set<String> vars, Map<String, String> builders,
  ) {
    final result = <AstNode>[];
    for (final stmt in stmts) {
      _keepStmt(stmt, used, vars, builders, result);
    }
    return result;
  }

  void _keepStmt(
    AstNode node, Map<String, Set<String>> used,
    Set<String> vars, Map<String, String> builders,
    List<AstNode> out,
  ) {
    // function M.foo(...) → remove if M is a builder and foo unused
    if (node is FunctionDef && node.name.method != null && node.name.rest.isEmpty) {
      final builderName = node.name.first.name;
      if (builders.containsKey(builderName)) {
        final moduleVar = builders[builderName]!;
        if (!_isFieldUsed(node.name.method!.name, moduleVar, used)) return;
      }
      out.add(node);
      return;
    }
    // M.field = value → remove if M is a builder and field unused
    if (node is Assignment &&
        node.targets.length == 1 &&
        node.exprs.length == 1 &&
        node.targets.first is TableFieldAccess) {
      final tfa = node.targets.first as TableFieldAccess;
      final builderName = _varName(tfa.table);
      if (builderName != null && builders.containsKey(builderName)) {
        final moduleVar = builders[builderName]!;
        if (!_isFieldUsed(tfa.fieldName.name, moduleVar, used)) return;
      }
    }
    // Recurse into blocks
    if (node is DoBlock) {
      final cleaned = _eliminate(node.body, used, vars, builders);
      out.add(identical(cleaned, node.body) ? node : DoBlock(cleaned));
      return;
    }
    if (node is FunctionDef) {
      final body = node.body;
      final cleaned = _eliminate(body.body, used, vars, builders);
      out.add(identical(cleaned, body.body)
          ? node
          : FunctionDef(
              node.name,
              FunctionBody(body.parameters, cleaned, body.isVararg,
                  varargName: body.varargName),
              implicitSelf: node.implicitSelf,
            ));
      return;
    }
    out.add(node);
  }

  bool _isFieldUsed(String field, String moduleVar, Map<String, Set<String>> used) {
    final fields = used[moduleVar];
    return fields != null && fields.contains(field);
  }

  String? _varName(AstNode node) =>
      node is Identifier ? node.name : null;

  String? _resolveAlias(String alias, Set<String> aliases, Set<String> vars) {
    // Simple: just check if alias maps to a var. We'd need proper dataflow.
    return null;
  }

  String? _constKey(AstNode node) {
    if (node is StringLiteral) return node.value;
    if (node is NumberLiteral && node.value is int) return node.value.toString();
    return null;
  }
}
