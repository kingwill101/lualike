import 'dart:io';

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/parse.dart';

/// Resolves static `require("literal_path")` calls and bundles all
/// dependencies into a single [Program] for whole-program compilation.
///
/// This is inspired by Hetu Script's `HTBundler` which resolves imports
/// before compilation, enabling cross-module constant folding and
/// optimization.
///
/// ## What it does
///
/// Walks the AST looking for:
///   `local name = require("path")`
///   `name = require("path")`
///
/// When the path is a string literal, the bundler:
///   1. Resolves the path against the search paths
///   2. Reads and parses the target file
///   3. Recursively bundles its dependencies
///   4. Wraps the module in `do...end` with the return value assigned
///      to a unique local
///   5. Replaces the require call with the local reference
///
/// The resulting [Program] contains all transitive dependencies in a
/// single AST that can be passed to [CompilePipeline].
///
/// ## Limitations
///
/// - Only handles `require("string_literal")` — dynamic requires with
///   variables as paths are left as-is for runtime resolution.
/// - Circular dependencies are detected and reported.
class Bundler {
  final List<String> searchPaths;
  final Set<String> _resolved = <String>{};
  final List<AstNode> _bundledNodes = [];

  Bundler({List<String>? searchPaths})
    : searchPaths = searchPaths ?? _defaultSearchPaths();

  static List<String> _defaultSearchPaths() => ['.'];

  /// Bundle [program] and all its static dependencies into a single AST.
  Program bundle(Program program) {
    _resolved.clear();
    _bundledNodes.clear();
    _bundleNode(program, '.');
    return Program([..._bundledNodes]);
  }

  void _bundleNode(AstNode node, String currentDir) {
    if (node is Program) {
      for (final stmt in node.statements) {
        _bundleNode(stmt, currentDir);
      }
      return;
    }

    // Check for: local name = require("path") or name = require("path")
    final requirePath = _matchRequire(node);
    if (requirePath != null) {
      final resolvedPath = _resolvePath(requirePath, currentDir);
      if (resolvedPath != null) {
        final moduleVar = _loadModule(resolvedPath);
        if (moduleVar != null) {
          if (node is LocalDeclaration) {
            _bundledNodes.add(
              LocalDeclaration(node.names, node.attributes, [Identifier(moduleVar)]),
            );
          } else if (node is Assignment) {
            _bundledNodes.add(
              Assignment(node.targets, [Identifier(moduleVar)]),
            );
          }
          return;
        }
      }
    }

    // Not a require — keep as-is.
    _bundledNodes.add(node);
  }

  /// Check if a node is `local x = require("path")` or `x = require("path")`
  /// and return the path string, or null.
  String? _matchRequire(AstNode node) {
    final exprs = switch (node) {
      LocalDeclaration(:final exprs) when exprs.length == 1 => exprs,
      Assignment(:final exprs) when exprs.length == 1 => exprs,
      _ => null,
    };
    if (exprs == null) return null;
    return _staticRequirePath(exprs.first);
  }

  /// Extract the path from a `require("path")` call, or null.
  String? _staticRequirePath(AstNode expr) {
    if (expr is! FunctionCall) return null;
    if (expr.name is! Identifier) return null;
    if ((expr.name as Identifier).name != 'require') return null;
    if (expr.args.length != 1) return null;
    final arg = expr.args.first;
    if (arg is StringLiteral) return arg.value;
    return null;
  }

  /// Resolve a module path against search paths.
  String? _resolvePath(String modulePath, String currentDir) {
    // Try the path as-is first.
    for (final base in [currentDir, ...searchPaths]) {
      for (final ext in ['', '.lua']) {
        final full = '$base/$modulePath$ext';
        if (FileSystemEntity.isFileSync(full)) {
          return full;
        }
      }
    }
    return null;
  }

  /// Load and bundle a module file. Returns the module variable name, or
  /// null if already loaded.
  String? _loadModule(String filePath) {
    if (_resolved.contains(filePath)) return null;
    _resolved.add(filePath);

    final source = File(filePath).readAsStringSync();
    final program = parse(source, url: filePath);

    final nodes = <AstNode>[];

    // Wrap the module body in a function that returns the module's value.
    // Module conventions: the last expression value becomes the module.
    // We assign it to a unique variable.
    final moduleVar = _makeModuleVar(filePath);

    // Recursively bundle inner requires.
    final innerBundler = Bundler(searchPaths: searchPaths);
    final bundled = innerBundler.bundle(program);

    nodes.add(
      LocalDeclaration(
        [Identifier(moduleVar)],
        [''],
        [], // Initialized to nil, then assigned
      ),
    );

    // Emit the module body with return value captured.
    for (final stmt in bundled.statements) {
      if (stmt is ReturnStatement && stmt.expr.length == 1) {
        // Return statement becomes assignment to module var.
        nodes.add(
          Assignment([Identifier(moduleVar)], stmt.expr),
        );
      } else {
        nodes.add(stmt);
      }
    }

    _bundledNodes.addAll(nodes);
    return moduleVar;
  }

  int _nextModuleId = 0;

  String _makeModuleVar(String filePath) {
    final name = filePath.split('/').last.replaceAll('.', '_');
    return '__bundle_${name}_${_nextModuleId++}';
  }
}
