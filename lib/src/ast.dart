import 'package:source_span/source_span.dart';
import 'lua_string_parser.dart';

/// Base class for all ASFuture`<T>` nodes.
abstract class AstNode {
  // Optional span info for error reporting, debugging, traces, etc.
  SourceSpan? span;

  // A helper to set/update the position information.
  void setSpan(SourceSpan span) {
    this.span = span;
  }

  // A getter so you can easily access the span.
  SourceSpan? getSpan() => span;

  Future<T> accept<T>(AstVisitor<T> visitor);

  String toSource();
}

/// Visitor interface for ASFuture`<T>` nodes.
abstract class AstVisitor<T> {
  Future<T> visitAssignment(Assignment node);

  Future<T> visitLocalDeclaration(LocalDeclaration node);

  Future<T> visitIfStatement(IfStatement node);

  Future<T> visitWhileStatement(WhileStatement node);

  Future<T> visitForLoop(ForLoop node);

  Future<T> visitRepeatUntilLoop(RepeatUntilLoop node);

  Future<T> visitFunctionDef(FunctionDef node);

  Future<T> visitReturnStatement(ReturnStatement node);

  Future<T> visitExpressionStatement(ExpressionStatement node);

  Future<T> visitBinaryExpression(BinaryExpression node);

  Future<T> visitTableAccess(TableAccessExpr node);

  Future<T> visitUnaryExpression(UnaryExpression node);

  Future<T> visitFunctionCall(FunctionCall node);

  Future<T> visitTableConstructor(TableConstructor node);

  Future<T> visitKeyedTableEntry(KeyedTableEntry node);

  Future<T> visitIndexedTableEntry(IndexedTableEntry node);

  Future<T> visitTableEntryLiteral(TableEntryLiteral node);

  Future<T> visitNilValue(NilValue node);

  Future<T> visitNumberLiteral(NumberLiteral node);

  Future<T> visitStringLiteral(StringLiteral node);

  Future<T> visitBooleanLiteral(BooleanLiteral node);

  Future<T> visitIdentifier(Identifier node);

  Future<T> visitForInLoop(ForInLoop forInLoop);

  Future<T> visitBreak(Break br);

  Future<T> visitGoto(Goto goto);

  Future<T> visitLabel(Label label);

  Future<T> visitDoBlock(DoBlock doBlockock);

  Future<T> visitLocalFunctionDef(LocalFunctionDef localFunctionDef);

  Future<T> visitFunctionName(FunctionName functionName);

  Future<T> visitFunctionBody(FunctionBody functionBody);

  Future<T> visitFunctionLiteral(FunctionLiteral functionLiteral);

  Future<T> visitVarArg(VarArg varArg);

  Future<T> visitMethodCall(MethodCall methodCall);

  Future<T> visitElseIfClause(ElseIfClause elseIfClause);

  Future<T> visitProgram(Program program);

  Future<T> visitAssignmentIndexAccessExpr(AssignmentIndexAccessExpr node);

  Future<T> visitGroupedExpression(GroupedExpression groupedExpression);

  Future<T> visitYieldStatement(YieldStatement yieldStatement);
}

/// Grouped expression in parentheses: (expr)
class GroupedExpression extends AstNode {
  final AstNode expr;

  GroupedExpression(this.expr);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitGroupedExpression(this);

  @override
  String toSource() {
    return "(${expr.toSource()})";
  }
}

class DoBlock extends AstNode {
  final List<AstNode> body;

  DoBlock(this.body);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitDoBlock(this);

  @override
  String toSource() {
    final bodySrc = body.map((s) => s.toSource()).join("\n");
    return "do\n$bodySrc\nend";
  }
}

class VarArg extends AstNode {
  VarArg();

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitVarArg(this);

  @override
  String toSource() {
    return "...";
  }
}

class Label extends AstNode {
  final Identifier label;

  Label(this.label);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitLabel(this);

  @override
  String toSource() {
    return "$label:";
  }
}

class Break extends AstNode {
  Break();

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitBreak(this);

  @override
  String toSource() {
    return "break";
  }
}

class Goto extends AstNode {
  final Identifier label;

  Goto(this.label);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitGoto(this);

  @override
  String toSource() {
    return "goto $label";
  }
}

/// Represents the top-level program.
class Program extends AstNode {
  final List<AstNode> statements;

  Program(this.statements);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitProgram(this);

  @override
  String toSource() => statements.map((s) => s.toSource()).join("\n");
}

/// x = expr or k, v = next(t)
class Assignment extends AstNode {
  final List<AstNode> targets; // Changed from single target to list
  final List<AstNode> exprs;

  Assignment(this.targets, this.exprs);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitAssignment(this);

  @override
  String toSource() {
    final targetsStr = targets.map((t) => t.toSource()).join(", ");
    return "$targetsStr = ${exprs.map((e) => e.toSource()).join(",")}";
  }
}

/// local x = expr
class LocalDeclaration extends AstNode {
  final List<Identifier> names;
  final List<String> attributes; // "const", "close", or empty string
  final List<AstNode> exprs; // can be fewer, equal, or more than names

  LocalDeclaration(this.names, this.attributes, this.exprs);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitLocalDeclaration(this);

  @override
  String toSource() {
    final nameAttribPairs = List.generate(names.length, (i) {
      final name = names[i].toSource();
      final attribute = attributes[i];
      return attribute.isNotEmpty ? "$name <$attribute>" : name;
    }).join(", ");

    if (exprs.isEmpty) {
      return "local $nameAttribPairs";
    }
    final exprsStr = exprs.map((e) => e.toSource()).join(", ");
    return "local $nameAttribPairs = $exprsStr";
  }
}

/// if cond then thenBlock ... end
class IfStatement extends AstNode {
  final AstNode cond;
  final List<AstNode> thenBlock;
  final List<ElseIfClause> elseIfs;
  final List<AstNode> elseBlock;

  IfStatement(this.cond, this.elseIfs, this.thenBlock, this.elseBlock);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitIfStatement(this);

  @override
  String toSource() {
    final thenSrc = thenBlock.map((s) => s.toSource()).join("\n");
    final elseIfSrc = elseIfs.map((e) => e.toSource()).join("\n");
    final elseSrc = elseBlock.isNotEmpty
        ? "else\n${elseBlock.map((s) => s.toSource()).join("\n")}"
        : "";
    return "if ${cond.toSource()} then\n$thenSrc\n$elseIfSrc\n$elseSrc\nend";
  }
}

class ElseIfClause extends AstNode {
  final AstNode cond;
  final List<AstNode> thenBlock;

  ElseIfClause(this.cond, this.thenBlock);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitElseIfClause(this);

  @override
  String toSource() {
    final blockSrc = thenBlock.map((s) => s.toSource()).join("\n");
    return "elseif ${cond.toSource()} then\n$blockSrc";
  }
}

/// while cond do body end
class WhileStatement extends AstNode {
  final AstNode cond;
  final List<AstNode> body;

  WhileStatement(this.cond, this.body);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitWhileStatement(this);

  @override
  String toSource() {
    final bodySrc = body.map((s) => s.toSource()).join("\n");
    return "while ${cond.toSource()} do\n$bodySrc\nend";
  }
}

/// for var = start, end [, step] do body end
class ForLoop extends AstNode {
  final Identifier varName;
  final AstNode start;
  final AstNode endExpr;
  final AstNode stepExpr;
  final List<AstNode> body;

  ForLoop(this.varName, this.start, this.endExpr, this.stepExpr, this.body);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitForLoop(this);

  @override
  String toSource() {
    final bodySrc = body.map((s) => s.toSource()).join("\n");
    return "for ${varName.toSource()} = ${start.toSource()}, ${endExpr.toSource()}, ${stepExpr.toSource()} do\n$bodySrc\nend";
  }
}

// ForInLoop(names, iterators, body)
class ForInLoop extends AstNode {
  final List<Identifier> names;
  final List<AstNode> iterators;
  final List<AstNode> body;

  ForInLoop(this.names, this.iterators, this.body);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitForInLoop(this);

  @override
  String toSource() {
    final bodySrc = body.map((s) => s.toSource()).join("\n");
    final paramsSrc = names.map((p) => p.toSource()).join(", ");
    return "for $paramsSrc in ${iterators.map((i) => i.toSource()).join(", ")} do\n$bodySrc\nend";
  }
}

/// repeat body until cond
class RepeatUntilLoop extends AstNode {
  final List<AstNode> body;
  final AstNode cond;

  RepeatUntilLoop(this.body, this.cond);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitRepeatUntilLoop(this);

  @override
  String toSource() {
    final bodySrc = body.map((s) => s.toSource()).join("\n");
    return "repeat\n$bodySrc\nuntil ${cond.toSource()}";
  }
}

/// function name(params) body end
class FunctionDef extends AstNode {
  final FunctionName name;
  final FunctionBody body;
  bool implicitSelf;

  FunctionDef(this.name, this.body, {this.implicitSelf = false});

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitFunctionDef(this);

  @override
  String toSource() => "function ${name.toSource()} ${body.toSource()}";
}

//FunctionName(first, rest, method)
class FunctionName extends AstNode {
  final Identifier first;
  final List<Identifier> rest;
  final Identifier? method;

  FunctionName(this.first, this.rest, this.method);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitFunctionName(this);

  @override
  String toSource() {
    final restSrc = rest.map((r) => r.toSource()).join(", ");
    return "${first.toSource()}${restSrc.isNotEmpty ? "($restSrc)" : ""}${method != null ? ".$method" : ""}";
  }
}

// LocalFunctionDef(name, funcBody)
class LocalFunctionDef extends AstNode {
  final Identifier name;
  final FunctionBody funcBody;

  LocalFunctionDef(this.name, this.funcBody);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitLocalFunctionDef(this);

  @override
  String toSource() =>
      "local function ${name.toSource()} ${funcBody.toSource()}";
}

class FunctionBody extends AstNode {
  List<Identifier>? parameters;
  final bool isVararg;
  final List<AstNode> body;
  bool implicitSelf;

  FunctionBody(
    this.parameters,
    this.body,
    this.isVararg, {
    this.implicitSelf = false,
  });

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitFunctionBody(this);

  @override
  String toSource() {
    final paramsSrc = parameters?.map((p) => p.toSource()).join(", ") ?? "";
    final bodySrc = body.map((s) => s.toSource()).join("\n");
    return "function ($paramsSrc)\n$bodySrc\nend";
  }
}

class FunctionLiteral extends AstNode {
  final FunctionBody funcBody;

  FunctionLiteral(this.funcBody);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitFunctionLiteral(this);

  @override
  String toSource() => "function ${funcBody.toSource()}";
}

/// return expr
class ReturnStatement extends AstNode {
  final List<AstNode> expr;

  ReturnStatement(this.expr);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitReturnStatement(this);

  @override
  String toSource() => "return ${expr.map((e) => e.toSource()).join(", ")}";
}

/// yield expr
class YieldStatement extends AstNode {
  final List<AstNode> expr;

  YieldStatement(this.expr);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitYieldStatement(this);

  @override
  String toSource() => "yield ${expr.map((e) => e.toSource()).join(", ")}";
}

/// Expression used as a statement.
class ExpressionStatement extends AstNode {
  final AstNode expr;

  ExpressionStatement(this.expr);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitExpressionStatement(this);

  @override
  String toSource() => expr.toSource();
}

/// `words[i] = 1`
/// `words.value[i] = 1`
class AssignmentIndexAccessExpr extends AstNode {
  final AstNode target;
  final AstNode index;
  final AstNode value;

  AssignmentIndexAccessExpr(this.target, this.index, this.value);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) {
    return visitor.visitAssignmentIndexAccessExpr(this);
  }

  @override
  String toSource() {
    return "${target.toSource()}[${index.toSource()}] = ${value.toSource()}";
  }
}

/// Table field access expression (table.field)
class TableAccessExpr extends AstNode {
  final AstNode table;
  final AstNode index;

  TableAccessExpr(this.table, this.index);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitTableAccess(this);

  @override
  String toSource() => "${table.toSource()}.${index.toSource()}";
}

/// Binary operation: left op right.
class BinaryExpression extends AstNode {
  final AstNode left;
  final String op;
  final AstNode right;

  BinaryExpression(this.left, this.op, this.right);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitBinaryExpression(this);

  @override
  String toSource() => "(${left.toSource()} $op ${right.toSource()})";
}

/// Unary operation: op expr.
/// Example: -5, not true.

class UnaryExpression extends AstNode {
  final String op;
  final AstNode expr;

  UnaryExpression(this.op, this.expr);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitUnaryExpression(this);

  @override
  String toSource() {
    if (op == "-") {
      return "-$expr";
    }
    return "$op$expr";
  }
}

abstract class Call extends AstNode {}

/// Function call: name(args).
class FunctionCall extends Call {
  final AstNode name;
  final List<AstNode> args;

  FunctionCall(this.name, this.args);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitFunctionCall(this);

  @override
  String toSource() {
    final argsSrc = args.map((a) => a.toSource()).join(", ");
    return "${name.toSource()}($argsSrc)";
  }
}

// MethodCall(prefix, methodName, args);
class MethodCall extends Call {
  final AstNode prefix;
  final AstNode methodName;
  final List<AstNode> args;
  final bool implicitSelf;

  MethodCall(
    this.prefix,
    this.methodName,
    this.args, {
    this.implicitSelf = false,
  });

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitMethodCall(this);

  @override
  String toSource() {
    final argsSrc = args.map((a) => a.toSource()).join(", ");
    return "${prefix.toSource()}.${methodName.toSource()}($argsSrc)";
  }
}

/// Table constructor: { entries }.
class TableConstructor extends AstNode {
  final List<TableEntry> entries;

  TableConstructor(this.entries);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitTableConstructor(this);

  @override
  String toSource() {
    final entriesSrc = entries.map((e) => e.toSource()).join(", ");
    return "{ $entriesSrc }";
  }
}

/// Abstract base class for table entries.
abstract class TableEntry extends AstNode {}

// Keyed table entry: key = value (field assignment)
class KeyedTableEntry extends TableEntry {
  final AstNode key; // Identifier for field name
  final AstNode value;

  KeyedTableEntry(this.key, this.value);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitKeyedTableEntry(this);

  @override
  String toSource() {
    return "${key.toSource()} = ${value.toSource()}";
  }
}

// Indexed table entry: [key] = value (index assignment)
class IndexedTableEntry extends TableEntry {
  final AstNode key; // Expression to be evaluated as key
  final AstNode value;

  IndexedTableEntry(this.key, this.value);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitIndexedTableEntry(this);

  @override
  String toSource() {
    return '[${key.toSource()}] = ${value.toSource()}';
  }
}

/// Table entry given as a lone expression.
class TableEntryLiteral extends TableEntry {
  final AstNode expr;

  TableEntryLiteral(this.expr);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitTableEntryLiteral(this);

  @override
  String toSource() => expr.toSource();

  @override
  String toString() => "TableEntryLiteral(${expr.toString()})";
}

/// Literal representing a nil value.
class NilValue extends AstNode {
  NilValue();

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitNilValue(this);

  @override
  String toSource() => "nil";
}

/// Numeric literal.
class NumberLiteral extends AstNode {
  final dynamic value;

  NumberLiteral(this.value) : assert(value is num || value is BigInt);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitNumberLiteral(this);

  @override
  String toSource() => value.toString();
}

/// String literal.
class StringLiteral extends AstNode {
  final String value;

  // Cache the parsed bytes for efficient access
  late final List<int> _bytes;

  StringLiteral(String raw) : value = raw {
    _bytes = LuaStringParser.parseStringContent(raw);
  }

  /// Get the byte representation of this string literal
  List<int> get bytes => _bytes;

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitStringLiteral(this);

  @override
  String toSource() => "\"$value\"";
}

/// Boolean literal.
class BooleanLiteral extends AstNode {
  final bool value;

  BooleanLiteral(this.value);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitBooleanLiteral(this);

  @override
  String toSource() => value ? "true" : "false";
}

/// Identifier.
class Identifier extends AstNode {
  final String name;

  Identifier(this.name);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitIdentifier(this);

  @override
  String toSource() => name;

  @override
  String toString() => name;
}
