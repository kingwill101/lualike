import 'ast.dart';

/// Mixin for AST nodes that can be serialized ("dumped") into a
/// data structure and reconstructed ("undumped") later.
mixin Dumpable on AstNode {
  /// Returns a JSON-serializable representation of this AST node.
  /// Implementations should include a 'type' field to assist decoding.
  Map<String, dynamic> dump();
}

/// Helper for encoding/decoding AST nodes that implement [Dumpable].
///
/// This is intentionally minimal and focused on nodes we need for
/// string.dump support and simple round-tripping. It can be extended
/// progressively to cover more node types.
/// Top-level undump function that dispatches to the respective
/// AST class factory based on the 'type' field.
AstNode undumpAst(Map<String, dynamic> data) {
  final type = data['type'] as String?;
  switch (type) {
    case 'NilValue':
      return NilValue.fromDump(data);
    case 'BooleanLiteral':
      return BooleanLiteral.fromDump(data);
    case 'NumberLiteral':
      return NumberLiteral.fromDump(data);
    case 'StringLiteral':
      return StringLiteral.fromDump(data);
    case 'Identifier':
      return Identifier.fromDump(data);
    case 'ReturnStatement':
      return ReturnStatement.fromDump(data);
    case 'FunctionBody':
      return FunctionBody.fromDump(data);
    case 'FunctionLiteral':
      return FunctionLiteral.fromDump(data);
    case 'Program':
      return Program.fromDump(data);
    case 'GroupedExpression':
      return GroupedExpression.fromDump(data);
    case 'DoBlock':
      return DoBlock.fromDump(data);
    case 'VarArg':
      return VarArg.fromDump(data);
    case 'Label':
      return Label.fromDump(data);
    case 'Break':
      return Break.fromDump(data);
    case 'Goto':
      return Goto.fromDump(data);
    case 'Assignment':
      return Assignment.fromDump(data);
    case 'LocalDeclaration':
      return LocalDeclaration.fromDump(data);
    case 'IfStatement':
      return IfStatement.fromDump(data);
    case 'ElseIfClause':
      return ElseIfClause.fromDump(data);
    case 'WhileStatement':
      return WhileStatement.fromDump(data);
    case 'ForLoop':
      return ForLoop.fromDump(data);
    case 'ForInLoop':
      return ForInLoop.fromDump(data);
    case 'RepeatUntilLoop':
      return RepeatUntilLoop.fromDump(data);
    case 'FunctionDef':
      return FunctionDef.fromDump(data);
    case 'FunctionName':
      return FunctionName.fromDump(data);
    case 'LocalFunctionDef':
      return LocalFunctionDef.fromDump(data);
    case 'YieldStatement':
      return YieldStatement.fromDump(data);
    case 'ExpressionStatement':
      return ExpressionStatement.fromDump(data);
    case 'AssignmentIndexAccessExpr':
      return AssignmentIndexAccessExpr.fromDump(data);
    case 'TableFieldAccess':
      return TableFieldAccess.fromDump(data);
    case 'TableIndexAccess':
      return TableIndexAccess.fromDump(data);
    case 'TableAccessExpr':
      return TableAccessExpr.fromDump(data);
    case 'BinaryExpression':
      return BinaryExpression.fromDump(data);
    case 'UnaryExpression':
      return UnaryExpression.fromDump(data);
    case 'FunctionCall':
      return FunctionCall.fromDump(data);
    case 'MethodCall':
      return MethodCall.fromDump(data);
    case 'TableConstructor':
      return TableConstructor.fromDump(data);
    case 'KeyedTableEntry':
      return KeyedTableEntry.fromDump(data);
    case 'IndexedTableEntry':
      return IndexedTableEntry.fromDump(data);
    case 'TableEntryLiteral':
      return TableEntryLiteral.fromDump(data);
    default:
      throw UnsupportedError('Unknown dump type: $type');
  }
}
