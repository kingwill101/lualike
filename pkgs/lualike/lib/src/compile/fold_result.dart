/// Compile-time constant values determined by the [ConstantFoldingPass].
///
/// Maps each AST node that the folding pass determined is a compile-time
/// constant to its precomputed value.  The sentinel [constantNil]
/// distinguishes the Lua `nil` literal from "node is not constant".
///
/// Downstream passes (the [ASTSimplifier], or compilers that check folding
/// results directly) use this to emit `LOADK` or `LOADI` instructions
/// instead of emitting the full expression tree.
library;

import 'dart:collection';

import 'package:lualike/src/ast.dart';

/// A mapping from AST nodes to their precomputed compile-time values.
final class ConstantFoldingResult {
  /// Sentinel value representing the Lua `nil` literal.
  ///
  /// Stored as the folded value for `nil` literal nodes, distinct from
  /// "node is not constant" (which uses a `null` entry in the map).
  static const Object constantNil = Object();

  final HashMap<AstNode, Object?> _values = HashMap<AstNode, Object?>();
  final HashMap<AstNode, Object?> _originalValues =
      HashMap<AstNode, Object?>();

  /// Whether the folding pass determined [node] is a compile-time constant.
  bool isConstant(AstNode node) => _values.containsKey(node);

  /// Returns the precomputed value for [node].
  ///
  /// Returns [constantNil] for the Lua `nil` literal.  Returns `null` when
  /// [node] is not constant (check with [isConstant] first).
  Object? getValue(AstNode node) => _values[node];

  /// Returns the original AST value before folding.
  ///
  /// For a [StringLiteral], this provides access to the raw string bytes
  /// that the compiler needs for emission, even after folding.
  Object? getOriginalValue(AstNode node) => _originalValues[node];

  /// Records a folded value for [node].
  void setValue(AstNode node, Object? value, {Object? originalValue}) {
    _values[node] = value;
    if (originalValue != null) {
      _originalValues[node] = originalValue;
    }
  }

  /// Merges all entries from [other] into this result.
  void merge(ConstantFoldingResult other) {
    _values.addAll(other._values);
    _originalValues.addAll(other._originalValues);
  }

  /// Returns the number of AST nodes that have been folded.
  int get foldedCount => _values.length;
}
