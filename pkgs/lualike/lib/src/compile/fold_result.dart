/// Tracks which AST nodes were determined to be compile-time constants
/// by the [ConstantFoldingPass].
///
/// Each constant node maps to its precomputed value.  The sentinel
/// [constantNil] distinguishes the Lua `nil` literal from "not constant".
library;

import 'dart:collection';

import 'package:lualike/src/ast.dart';

final class ConstantFoldingResult {
  /// Sentinel for the Lua `nil` literal (distinct from "not constant").
  static const Object constantNil = Object();

  final HashMap<AstNode, Object?> _values = HashMap<AstNode, Object?>();
  final HashMap<AstNode, Object?> _originalValues =
      HashMap<AstNode, Object?>();

  /// Whether [node] was determined to be a compile-time constant.
  bool isConstant(AstNode node) => _values.containsKey(node);

  /// The folded value for [node], or `null` if not constant.
  ///
  /// For Lua `nil`, returns [constantNil].
  Object? getValue(AstNode node) => _values[node];

  /// The original AST value before folding (e.g. raw string bytes).
  Object? getOriginalValue(AstNode node) => _originalValues[node];

  /// Record a folded value for [node].
  void setValue(AstNode node, Object? value, {Object? originalValue}) {
    _values[node] = value;
    if (originalValue != null) {
      _originalValues[node] = originalValue;
    }
  }

  /// Merge all values from [other] into this result.
  void merge(ConstantFoldingResult other) {
    _values.addAll(other._values);
    _originalValues.addAll(other._originalValues);
  }

  /// Number of folded nodes.
  int get foldedCount => _values.length;
}
