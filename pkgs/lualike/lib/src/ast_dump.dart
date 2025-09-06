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
      return NilValue();
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
    default:
      throw UnsupportedError('Unknown dump type: $type');
  }
}
