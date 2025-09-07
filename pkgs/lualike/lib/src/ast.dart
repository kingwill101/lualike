import 'package:source_span/source_span.dart';

import 'parsers/string.dart';
import 'ast_dump.dart';
import 'logging/logger.dart';

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

  /// Dumps span information to a serializable map
  Map<String, dynamic>? dumpSpan() {
    if (span == null) {
      Logger.debug('AST: No span to dump', category: 'AST');
      return null;
    }

    Logger.debug(
      'AST: Dumping span for ${span!.sourceUrl} (${span!.start.offset}-${span!.end.offset})',
      category: 'AST',
    );

    return {
      'sourceUrl': span!.sourceUrl?.toString(),
      'start': span!.start.offset,
      'end': span!.end.offset,
      'length': span!.length,
      'text': span!.text,
      'startLine': span!.start.line,
      'startColumn': span!.start.column,
      'endLine': span!.end.line,
      'endColumn': span!.end.column,
    };
  }

  /// Restores span information from a serialized map
  void restoreSpan(Map<String, dynamic>? spanData, String? fallbackSourceUrl) {
    Logger.debug(
      'AST: restoreSpan called with spanData=$spanData',
      category: 'AST',
    );
    if (spanData == null) {
      Logger.debug('AST: No span data to restore', category: 'AST');
      return;
    }

    try {
      final sourceUrl = spanData['sourceUrl'] as String? ?? fallbackSourceUrl;
      final start = spanData['start'] as int? ?? 0;
      final end = spanData['end'] as int? ?? 0;
      final text = spanData['text'] as String? ?? '';
      final length = spanData['length'] as int? ?? (end - start);

      Logger.debug(
        'AST: Attempting to restore span: sourceUrl=$sourceUrl, start=$start, end=$end',
        category: 'AST',
      );

      if (sourceUrl != null && text.isNotEmpty) {
        // Create a source file with the original content and URL
        final uri = Uri.parse(sourceUrl);
        final sourceFile = SourceFile.fromString(text, url: uri);
        span = sourceFile.span(start, end);
        Logger.debug(
          'AST: Restored span for ${uri} (${start}-${end})',
          category: 'AST',
        );
      } else if (sourceUrl != null) {
        // Fallback: create a minimal span with just the URL
        final uri = Uri.parse(sourceUrl);
        final sourceFile = SourceFile.fromString('', url: uri);
        span = sourceFile.span(0, 0);
        Logger.debug('AST: Restored minimal span for ${uri}', category: 'AST');
      }
    } catch (e) {
      // If restoration fails, silently continue without span
      Logger.debug('AST: Failed to restore span: $e', category: 'AST');
    }
  }

  /// Attempts to infer span information from child nodes
  void inferSpanFromChildren() {
    if (span != null) return; // Already has span

    // Try to find spans from child nodes to infer source location
    SourceSpan? firstSpan;
    SourceSpan? lastSpan;

    void findSpans(dynamic node) {
      if (node is AstNode && node.span != null) {
        firstSpan ??= node.span;
        lastSpan = node.span;
      } else if (node is List) {
        for (final item in node) {
          findSpans(item);
        }
      }
    }

    // Check different types of child collections
    if (this is FunctionBody) {
      final fb = this as FunctionBody;
      findSpans(fb.parameters);
      findSpans(fb.body);
    }

    // If we found spans from children, create a span that encompasses them
    if (firstSpan != null && lastSpan != null) {
      try {
        final sourceFile = firstSpan!.sourceUrl;
        final sourceText =
            firstSpan!.text + (lastSpan != firstSpan ? lastSpan!.text : '');
        final mockSourceFile = SourceFile.fromString(
          sourceText,
          url: sourceFile,
        );
        final start = 0;
        final end = sourceText.length;
        span = mockSourceFile.span(start, end);
        Logger.debug(
          'AST: Inferred span from children for ${sourceFile} ($start-$end)',
          category: 'AST',
        );
      } catch (e) {
        Logger.debug(
          'AST: Failed to infer span from children: $e',
          category: 'AST',
        );
      }
    }
  }

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

  Future<T> visitTableFieldAccess(TableFieldAccess node);
  Future<T> visitTableIndexAccess(TableIndexAccess node);
}

/// Grouped expression in parentheses: (expr)
class GroupedExpression extends AstNode with Dumpable {
  final AstNode expr;

  GroupedExpression(this.expr);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitGroupedExpression(this);

  @override
  String toSource() {
    return "(${expr.toSource()})";
  }

  @override
  Map<String, dynamic> dump() => {
    'type': 'GroupedExpression',
    'expr': expr is Dumpable ? (expr as Dumpable).dump() : {'type': 'Unknown'},
    'span': dumpSpan(),
  };

  static GroupedExpression fromDump(Map<String, dynamic> data) {
    final expr = undumpAst(Map<String, dynamic>.from(data['expr']));
    final groupedExpr = GroupedExpression(expr);
    groupedExpr.restoreSpan(data['span'] as Map<String, dynamic>?, null);
    return groupedExpr;
  }
}

class DoBlock extends AstNode with Dumpable {
  final List<AstNode> body;

  DoBlock(this.body);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitDoBlock(this);

  @override
  String toSource() {
    final bodySrc = body.map((s) => s.toSource()).join("\n");
    return "do\n$bodySrc\nend";
  }

  @override
  Map<String, dynamic> dump() => {
    'type': 'DoBlock',
    'body': body
        .map((s) => s is Dumpable ? (s).dump() : {'type': 'Unknown'})
        .toList(),
    'span': dumpSpan(),
  };

  static DoBlock fromDump(Map<String, dynamic> data) {
    final bodyNodes = (data['body'] as List? ?? const <dynamic>[])
        .map((e) => undumpAst(Map<String, dynamic>.from(e)))
        .toList();
    final doBlock = DoBlock(bodyNodes);
    doBlock.restoreSpan(data['span'] as Map<String, dynamic>?, null);
    return doBlock;
  }
}

class VarArg extends AstNode with Dumpable {
  VarArg();

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitVarArg(this);

  @override
  String toSource() {
    return "...";
  }

  @override
  Map<String, dynamic> dump() => {'type': 'VarArg', 'span': dumpSpan()};

  static VarArg fromDump(Map<String, dynamic> data) {
    final varArg = VarArg();
    varArg.restoreSpan(data['span'] as Map<String, dynamic>?, null);
    return varArg;
  }
}

class Label extends AstNode with Dumpable {
  final Identifier label;

  Label(this.label);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitLabel(this);

  @override
  String toSource() {
    return "$label:";
  }

  @override
  Map<String, dynamic> dump() => {'type': 'Label', 'label': label.dump()};

  static Label fromDump(Map<String, dynamic> data) {
    final label = Identifier.fromDump(Map<String, dynamic>.from(data['label']));
    return Label(label);
  }
}

class Break extends AstNode with Dumpable {
  Break();

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitBreak(this);

  @override
  String toSource() {
    return "break";
  }

  @override
  Map<String, dynamic> dump() => {'type': 'Break'};

  static Break fromDump(Map<String, dynamic> data) {
    return Break();
  }
}

class Goto extends AstNode with Dumpable {
  final Identifier label;

  Goto(this.label);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitGoto(this);

  @override
  String toSource() {
    return "goto $label";
  }

  @override
  Map<String, dynamic> dump() => {'type': 'Goto', 'label': label.dump()};

  static Goto fromDump(Map<String, dynamic> data) {
    final label = Identifier.fromDump(Map<String, dynamic>.from(data['label']));
    return Goto(label);
  }
}

/// Represents the top-level program.
class Program extends AstNode with Dumpable {
  final List<AstNode> statements;

  Program(this.statements);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitProgram(this);

  @override
  String toSource() => statements.map((s) => s.toSource()).join("\n");

  @override
  Map<String, dynamic> dump() => {
    'type': 'Program',
    'statements': statements
        .map((s) => s is Dumpable ? (s).dump() : {'type': 'Unknown'})
        .toList(),
  };

  static Program fromDump(Map<String, dynamic> data) {
    final stmtsData = (data['statements'] as List? ?? const <dynamic>[])
        .map((e) => undumpAst(Map<String, dynamic>.from(e)))
        .toList();
    return Program(stmtsData);
  }
}

/// x = expr or k, v = next(t)
class Assignment extends AstNode with Dumpable {
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

  @override
  Map<String, dynamic> dump() => {
    'type': 'Assignment',
    'targets': targets
        .map((t) => t is Dumpable ? (t).dump() : {'type': 'Unknown'})
        .toList(),
    'exprs': exprs
        .map((e) => e is Dumpable ? (e).dump() : {'type': 'Unknown'})
        .toList(),
  };

  static Assignment fromDump(Map<String, dynamic> data) {
    final targets = (data['targets'] as List? ?? const <dynamic>[])
        .map((e) => undumpAst(Map<String, dynamic>.from(e)))
        .toList();
    final exprs = (data['exprs'] as List? ?? const <dynamic>[])
        .map((e) => undumpAst(Map<String, dynamic>.from(e)))
        .toList();
    return Assignment(targets, exprs);
  }
}

/// local x = expr
class LocalDeclaration extends AstNode with Dumpable {
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

  @override
  Map<String, dynamic> dump() => {
    'type': 'LocalDeclaration',
    'names': names.map((n) => n.dump()).toList(),
    'attributes': attributes,
    'exprs': exprs
        .map((e) => e is Dumpable ? (e).dump() : {'type': 'Unknown'})
        .toList(),
  };

  static LocalDeclaration fromDump(Map<String, dynamic> data) {
    final names = (data['names'] as List? ?? const <dynamic>[])
        .map((n) => Identifier.fromDump(Map<String, dynamic>.from(n)))
        .toList();
    final attributes = (data['attributes'] as List? ?? const <dynamic>[])
        .map((a) => a as String)
        .toList();
    final exprs = (data['exprs'] as List? ?? const <dynamic>[])
        .map((e) => undumpAst(Map<String, dynamic>.from(e)))
        .toList();
    return LocalDeclaration(names, attributes, exprs);
  }
}

/// if cond then thenBlock ... end
class IfStatement extends AstNode with Dumpable {
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

  @override
  Map<String, dynamic> dump() => {
    'type': 'IfStatement',
    'cond': cond is Dumpable ? (cond as Dumpable).dump() : {'type': 'Unknown'},
    'thenBlock': thenBlock
        .map((s) => s is Dumpable ? (s).dump() : {'type': 'Unknown'})
        .toList(),
    'elseIfs': elseIfs.map((e) => (e as Dumpable).dump()).toList(),
    'elseBlock': elseBlock
        .map((s) => s is Dumpable ? (s).dump() : {'type': 'Unknown'})
        .toList(),
  };

  static IfStatement fromDump(Map<String, dynamic> data) {
    final cond = undumpAst(Map<String, dynamic>.from(data['cond']));
    final thenBlock = (data['thenBlock'] as List? ?? const <dynamic>[])
        .map((e) => undumpAst(Map<String, dynamic>.from(e)))
        .toList();
    final elseIfs = (data['elseIfs'] as List? ?? const <dynamic>[])
        .map((e) => ElseIfClause.fromDump(Map<String, dynamic>.from(e)))
        .toList();
    final elseBlock = (data['elseBlock'] as List? ?? const <dynamic>[])
        .map((e) => undumpAst(Map<String, dynamic>.from(e)))
        .toList();
    return IfStatement(cond, elseIfs, thenBlock, elseBlock);
  }
}

class ElseIfClause extends AstNode with Dumpable {
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

  @override
  Map<String, dynamic> dump() => {
    'type': 'ElseIfClause',
    'cond': cond is Dumpable ? (cond as Dumpable).dump() : {'type': 'Unknown'},
    'thenBlock': thenBlock
        .map((s) => s is Dumpable ? (s).dump() : {'type': 'Unknown'})
        .toList(),
  };

  static ElseIfClause fromDump(Map<String, dynamic> data) {
    final cond = undumpAst(Map<String, dynamic>.from(data['cond']));
    final thenBlock = (data['thenBlock'] as List? ?? const <dynamic>[])
        .map((e) => undumpAst(Map<String, dynamic>.from(e)))
        .toList();
    return ElseIfClause(cond, thenBlock);
  }
}

/// while cond do body end
class WhileStatement extends AstNode with Dumpable {
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

  @override
  Map<String, dynamic> dump() => {
    'type': 'WhileStatement',
    'cond': cond is Dumpable ? (cond as Dumpable).dump() : {'type': 'Unknown'},
    'body': body
        .map((s) => s is Dumpable ? (s).dump() : {'type': 'Unknown'})
        .toList(),
  };

  static WhileStatement fromDump(Map<String, dynamic> data) {
    final cond = undumpAst(Map<String, dynamic>.from(data['cond']));
    final body = (data['body'] as List? ?? const <dynamic>[])
        .map((e) => undumpAst(Map<String, dynamic>.from(e)))
        .toList();
    return WhileStatement(cond, body);
  }
}

/// for var = start, end [, step] do body end
class ForLoop extends AstNode with Dumpable {
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

  @override
  Map<String, dynamic> dump() => {
    'type': 'ForLoop',
    'varName': varName.dump(),
    'start': start is Dumpable
        ? (start as Dumpable).dump()
        : {'type': 'Unknown'},
    'endExpr': endExpr is Dumpable
        ? (endExpr as Dumpable).dump()
        : {'type': 'Unknown'},
    'stepExpr': stepExpr is Dumpable
        ? (stepExpr as Dumpable).dump()
        : {'type': 'Unknown'},
    'body': body
        .map((s) => s is Dumpable ? (s).dump() : {'type': 'Unknown'})
        .toList(),
  };

  static ForLoop fromDump(Map<String, dynamic> data) {
    final varName = Identifier.fromDump(
      Map<String, dynamic>.from(data['varName']),
    );
    final start = undumpAst(Map<String, dynamic>.from(data['start']));
    final endExpr = undumpAst(Map<String, dynamic>.from(data['endExpr']));
    final stepExpr = undumpAst(Map<String, dynamic>.from(data['stepExpr']));
    final body = (data['body'] as List? ?? const <dynamic>[])
        .map((e) => undumpAst(Map<String, dynamic>.from(e)))
        .toList();
    return ForLoop(varName, start, endExpr, stepExpr, body);
  }
}

// ForInLoop(names, iterators, body)
class ForInLoop extends AstNode with Dumpable {
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

  @override
  Map<String, dynamic> dump() => {
    'type': 'ForInLoop',
    'names': names.map((n) => n.dump()).toList(),
    'iterators': iterators
        .map((i) => i is Dumpable ? (i).dump() : {'type': 'Unknown'})
        .toList(),
    'body': body
        .map((s) => s is Dumpable ? (s).dump() : {'type': 'Unknown'})
        .toList(),
  };

  static ForInLoop fromDump(Map<String, dynamic> data) {
    final names = (data['names'] as List? ?? const <dynamic>[])
        .map((n) => Identifier.fromDump(Map<String, dynamic>.from(n)))
        .toList();
    final iterators = (data['iterators'] as List? ?? const <dynamic>[])
        .map((i) => undumpAst(Map<String, dynamic>.from(i)))
        .toList();
    final body = (data['body'] as List? ?? const <dynamic>[])
        .map((s) => undumpAst(Map<String, dynamic>.from(s)))
        .toList();
    return ForInLoop(names, iterators, body);
  }
}

/// repeat body until cond
class RepeatUntilLoop extends AstNode with Dumpable {
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

  @override
  Map<String, dynamic> dump() => {
    'type': 'RepeatUntilLoop',
    'body': body
        .map((s) => s is Dumpable ? (s).dump() : {'type': 'Unknown'})
        .toList(),
    'cond': cond is Dumpable ? (cond as Dumpable).dump() : {'type': 'Unknown'},
  };

  static RepeatUntilLoop fromDump(Map<String, dynamic> data) {
    final body = (data['body'] as List? ?? const <dynamic>[])
        .map((s) => undumpAst(Map<String, dynamic>.from(s)))
        .toList();
    final cond = undumpAst(Map<String, dynamic>.from(data['cond']));
    return RepeatUntilLoop(body, cond);
  }
}

/// function name(params) body end
class FunctionDef extends AstNode with Dumpable {
  final FunctionName name;
  final FunctionBody body;
  bool implicitSelf;

  FunctionDef(this.name, this.body, {this.implicitSelf = false});

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitFunctionDef(this);

  @override
  String toSource() => "function ${name.toSource()} ${body.toSource()}";

  @override
  Map<String, dynamic> dump() => {
    'type': 'FunctionDef',
    'name': name.dump(),
    'body': body.dump(),
    'implicitSelf': implicitSelf,
    'span': dumpSpan(),
  };

  static FunctionDef fromDump(Map<String, dynamic> data) {
    final name = FunctionName.fromDump(Map<String, dynamic>.from(data['name']));
    final body = FunctionBody.fromDump(Map<String, dynamic>.from(data['body']));
    final implicitSelf = data['implicitSelf'] as bool? ?? false;
    final functionDef = FunctionDef(name, body, implicitSelf: implicitSelf);
    functionDef.restoreSpan(data['span'] as Map<String, dynamic>?, null);
    return functionDef;
  }
}

//FunctionName(first, rest, method)
class FunctionName extends AstNode with Dumpable {
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

  @override
  Map<String, dynamic> dump() => {
    'type': 'FunctionName',
    'first': first.dump(),
    'rest': rest.map((r) => r.dump()).toList(),
    'method': method?.dump(),
  };

  static FunctionName fromDump(Map<String, dynamic> data) {
    final first = Identifier.fromDump(Map<String, dynamic>.from(data['first']));
    final rest = (data['rest'] as List? ?? const <dynamic>[])
        .map((r) => Identifier.fromDump(Map<String, dynamic>.from(r)))
        .toList();
    final method = data['method'] != null
        ? Identifier.fromDump(Map<String, dynamic>.from(data['method']))
        : null;
    return FunctionName(first, rest, method);
  }
}

// LocalFunctionDef(name, funcBody)
class LocalFunctionDef extends AstNode with Dumpable {
  final Identifier name;
  final FunctionBody funcBody;

  LocalFunctionDef(this.name, this.funcBody);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitLocalFunctionDef(this);

  @override
  String toSource() =>
      "local function ${name.toSource()} ${funcBody.toSource()}";

  @override
  Map<String, dynamic> dump() => {
    'type': 'LocalFunctionDef',
    'name': name.dump(),
    'funcBody': funcBody.dump(),
  };

  static LocalFunctionDef fromDump(Map<String, dynamic> data) {
    final name = Identifier.fromDump(Map<String, dynamic>.from(data['name']));
    final funcBody = FunctionBody.fromDump(
      Map<String, dynamic>.from(data['funcBody']),
    );
    return LocalFunctionDef(name, funcBody);
  }
}

class FunctionBody extends AstNode with Dumpable {
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

  @override
  Map<String, dynamic> dump() => {
    'type': 'FunctionBody',
    'params': (parameters ?? const <Identifier>[]).map((p) => p.name).toList(),
    'vararg': isVararg,
    'body': body
        .map((s) => s is Dumpable ? (s).dump() : {'type': 'Unknown'})
        .toList(),
    'span': dumpSpan(),
  };

  static FunctionBody fromDump(Map<String, dynamic> data) {
    final params = (data['params'] as List? ?? const <dynamic>[])
        .map((n) => Identifier(n as String))
        .toList();
    final bodyNodes = (data['body'] as List? ?? const <dynamic>[])
        .map((e) => undumpAst(Map<String, dynamic>.from(e)))
        .toList();
    final isVararg = data['vararg'] as bool? ?? false;
    final functionBody = FunctionBody(params, bodyNodes, isVararg);

    // Restore span information
    final spanData = data['span'] as Map<String, dynamic>?;
    functionBody.restoreSpan(spanData, null);

    // If no span was restored, try to infer from child nodes
    functionBody.inferSpanFromChildren();

    return functionBody;
  }
}

class FunctionLiteral extends AstNode with Dumpable {
  final FunctionBody funcBody;

  FunctionLiteral(this.funcBody);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitFunctionLiteral(this);

  @override
  String toSource() => "function ${funcBody.toSource()}";

  @override
  Map<String, dynamic> dump() => {
    'type': 'FunctionLiteral',
    'body': funcBody.dump(),
    'span': dumpSpan(),
  };

  static FunctionLiteral fromDump(Map<String, dynamic> data) {
    final fb = FunctionBody.fromDump(Map<String, dynamic>.from(data['body']));
    final functionLiteral = FunctionLiteral(fb);
    functionLiteral.restoreSpan(data['span'] as Map<String, dynamic>?, null);
    return functionLiteral;
  }
}

/// return expr
class ReturnStatement extends AstNode with Dumpable {
  final List<AstNode> expr;

  ReturnStatement(this.expr);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitReturnStatement(this);

  @override
  String toSource() => "return ${expr.map((e) => e.toSource()).join(", ")}";

  @override
  Map<String, dynamic> dump() => {
    'type': 'ReturnStatement',
    'expr': expr
        .map((e) => e is Dumpable ? (e).dump() : {'type': 'Unknown'})
        .toList(),
  };

  static ReturnStatement fromDump(Map<String, dynamic> data) {
    final exprs = (data['expr'] as List? ?? const <dynamic>[])
        .map((e) => undumpAst(Map<String, dynamic>.from(e)))
        .toList();
    return ReturnStatement(exprs);
  }
}

/// yield expr
class YieldStatement extends AstNode with Dumpable {
  final List<AstNode> expr;

  YieldStatement(this.expr);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitYieldStatement(this);

  @override
  String toSource() => "yield ${expr.map((e) => e.toSource()).join(", ")}";

  @override
  Map<String, dynamic> dump() => {
    'type': 'YieldStatement',
    'expr': expr
        .map((e) => e is Dumpable ? (e).dump() : {'type': 'Unknown'})
        .toList(),
  };

  static YieldStatement fromDump(Map<String, dynamic> data) {
    final exprs = (data['expr'] as List? ?? const <dynamic>[])
        .map((e) => undumpAst(Map<String, dynamic>.from(e)))
        .toList();
    return YieldStatement(exprs);
  }
}

/// Expression used as a statement.
class ExpressionStatement extends AstNode with Dumpable {
  final AstNode expr;

  ExpressionStatement(this.expr);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitExpressionStatement(this);

  @override
  String toSource() => expr.toSource();

  @override
  Map<String, dynamic> dump() => {
    'type': 'ExpressionStatement',
    'expr': expr is Dumpable ? (expr as Dumpable).dump() : {'type': 'Unknown'},
  };

  static ExpressionStatement fromDump(Map<String, dynamic> data) {
    final expr = undumpAst(Map<String, dynamic>.from(data['expr']));
    return ExpressionStatement(expr);
  }
}

/// `words[i] = 1`
/// `words.value[i] = 1`
class AssignmentIndexAccessExpr extends AstNode with Dumpable {
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

  @override
  Map<String, dynamic> dump() => {
    'type': 'AssignmentIndexAccessExpr',
    'target': target is Dumpable
        ? (target as Dumpable).dump()
        : {'type': 'Unknown'},
    'index': index is Dumpable
        ? (index as Dumpable).dump()
        : {'type': 'Unknown'},
    'value': value is Dumpable
        ? (value as Dumpable).dump()
        : {'type': 'Unknown'},
  };

  static AssignmentIndexAccessExpr fromDump(Map<String, dynamic> data) {
    final target = undumpAst(Map<String, dynamic>.from(data['target']));
    final index = undumpAst(Map<String, dynamic>.from(data['index']));
    final value = undumpAst(Map<String, dynamic>.from(data['value']));
    return AssignmentIndexAccessExpr(target, index, value);
  }
}

/// Table field access expression (table.field) - dot notation
class TableFieldAccess extends AstNode with Dumpable {
  final AstNode table;
  final Identifier fieldName; // Always an identifier for field access

  TableFieldAccess(this.table, this.fieldName);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitTableFieldAccess(this);

  @override
  String toSource() => "${table.toSource()}.${fieldName.toSource()}";

  @override
  Map<String, dynamic> dump() => {
    'type': 'TableFieldAccess',
    'table': table is Dumpable
        ? (table as Dumpable).dump()
        : {'type': 'Unknown'},
    'fieldName': fieldName.dump(),
  };

  static TableFieldAccess fromDump(Map<String, dynamic> data) {
    final table = undumpAst(Map<String, dynamic>.from(data['table']));
    final fieldName = Identifier.fromDump(
      Map<String, dynamic>.from(data['fieldName']),
    );
    return TableFieldAccess(table, fieldName);
  }
}

/// Table index access expression (table[expr]) - bracket notation
class TableIndexAccess extends AstNode with Dumpable {
  final AstNode table;
  final AstNode index; // Any expression for index access

  TableIndexAccess(this.table, this.index);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitTableIndexAccess(this);

  @override
  String toSource() => "${table.toSource()}[${index.toSource()}]";

  @override
  Map<String, dynamic> dump() => {
    'type': 'TableIndexAccess',
    'table': table is Dumpable
        ? (table as Dumpable).dump()
        : {'type': 'Unknown'},
    'index': index is Dumpable
        ? (index as Dumpable).dump()
        : {'type': 'Unknown'},
  };

  static TableIndexAccess fromDump(Map<String, dynamic> data) {
    final table = undumpAst(Map<String, dynamic>.from(data['table']));
    final index = undumpAst(Map<String, dynamic>.from(data['index']));
    return TableIndexAccess(table, index);
  }
}

/// Legacy table access expression - kept for backward compatibility
/// Will be deprecated in favor of TableFieldAccess and TableIndexAccess
class TableAccessExpr extends AstNode with Dumpable {
  final AstNode table;
  final AstNode index;

  TableAccessExpr(this.table, this.index);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitTableAccess(this);

  @override
  String toSource() => "${table.toSource()}.${index.toSource()}";

  @override
  Map<String, dynamic> dump() => {
    'type': 'TableAccessExpr',
    'table': table is Dumpable
        ? (table as Dumpable).dump()
        : {'type': 'Unknown'},
    'index': index is Dumpable
        ? (index as Dumpable).dump()
        : {'type': 'Unknown'},
  };

  static TableAccessExpr fromDump(Map<String, dynamic> data) {
    final table = undumpAst(Map<String, dynamic>.from(data['table']));
    final index = undumpAst(Map<String, dynamic>.from(data['index']));
    return TableAccessExpr(table, index);
  }
}

/// Binary operation: left op right.
class BinaryExpression extends AstNode with Dumpable {
  final AstNode left;
  final String op;
  final AstNode right;

  BinaryExpression(this.left, this.op, this.right);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitBinaryExpression(this);

  @override
  String toSource() => "(${left.toSource()} $op ${right.toSource()})";

  @override
  Map<String, dynamic> dump() => {
    'type': 'BinaryExpression',
    'left': left is Dumpable ? (left as Dumpable).dump() : {'type': 'Unknown'},
    'op': op,
    'right': right is Dumpable
        ? (right as Dumpable).dump()
        : {'type': 'Unknown'},
  };

  static BinaryExpression fromDump(Map<String, dynamic> data) {
    final left = undumpAst(Map<String, dynamic>.from(data['left']));
    final op = data['op'] as String;
    final right = undumpAst(Map<String, dynamic>.from(data['right']));
    return BinaryExpression(left, op, right);
  }
}

/// Unary operation: op expr.
/// Example: -5, not true.

class UnaryExpression extends AstNode with Dumpable {
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

  @override
  Map<String, dynamic> dump() => {
    'type': 'UnaryExpression',
    'op': op,
    'expr': expr is Dumpable ? (expr as Dumpable).dump() : {'type': 'Unknown'},
  };

  static UnaryExpression fromDump(Map<String, dynamic> data) {
    final op = data['op'] as String;
    final expr = undumpAst(Map<String, dynamic>.from(data['expr']));
    return UnaryExpression(op, expr);
  }
}

abstract class Call extends AstNode {}

/// Function call: name(args).
class FunctionCall extends Call with Dumpable {
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

  @override
  Map<String, dynamic> dump() => {
    'type': 'FunctionCall',
    'name': name is Dumpable ? (name as Dumpable).dump() : {'type': 'Unknown'},
    'args': args
        .map((a) => a is Dumpable ? (a).dump() : {'type': 'Unknown'})
        .toList(),
  };

  static FunctionCall fromDump(Map<String, dynamic> data) {
    final name = undumpAst(Map<String, dynamic>.from(data['name']));
    final args = (data['args'] as List? ?? const <dynamic>[])
        .map((a) => undumpAst(Map<String, dynamic>.from(a)))
        .toList();
    return FunctionCall(name, args);
  }
}

// MethodCall(prefix, methodName, args);
class MethodCall extends Call with Dumpable {
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

  @override
  Map<String, dynamic> dump() => {
    'type': 'MethodCall',
    'prefix': prefix is Dumpable
        ? (prefix as Dumpable).dump()
        : {'type': 'Unknown'},
    'methodName': methodName is Dumpable
        ? (methodName as Dumpable).dump()
        : {'type': 'Unknown'},
    'args': args
        .map((a) => a is Dumpable ? (a).dump() : {'type': 'Unknown'})
        .toList(),
    'implicitSelf': implicitSelf,
  };

  static MethodCall fromDump(Map<String, dynamic> data) {
    final prefix = undumpAst(Map<String, dynamic>.from(data['prefix']));
    final methodName = undumpAst(Map<String, dynamic>.from(data['methodName']));
    final args = (data['args'] as List? ?? const <dynamic>[])
        .map((a) => undumpAst(Map<String, dynamic>.from(a)))
        .toList();
    final implicitSelf = data['implicitSelf'] as bool? ?? false;
    return MethodCall(prefix, methodName, args, implicitSelf: implicitSelf);
  }
}

/// Table constructor: { entries }.
class TableConstructor extends AstNode with Dumpable {
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

  @override
  Map<String, dynamic> dump() => {
    'type': 'TableConstructor',
    'entries': entries
        .map(
          (e) => e is Dumpable ? (e as Dumpable).dump() : {'type': 'Unknown'},
        )
        .toList(),
  };

  static TableConstructor fromDump(Map<String, dynamic> data) {
    final entries = (data['entries'] as List? ?? const <dynamic>[])
        .map((e) => undumpAst(Map<String, dynamic>.from(e)) as TableEntry)
        .toList();
    return TableConstructor(entries);
  }
}

/// Abstract base class for table entries.
abstract class TableEntry extends AstNode {}

// Keyed table entry: key = value (field assignment)
class KeyedTableEntry extends TableEntry with Dumpable {
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

  @override
  Map<String, dynamic> dump() => {
    'type': 'KeyedTableEntry',
    'key': key is Dumpable ? (key as Dumpable).dump() : {'type': 'Unknown'},
    'value': value is Dumpable
        ? (value as Dumpable).dump()
        : {'type': 'Unknown'},
  };

  static KeyedTableEntry fromDump(Map<String, dynamic> data) {
    final key = undumpAst(Map<String, dynamic>.from(data['key']));
    final value = undumpAst(Map<String, dynamic>.from(data['value']));
    return KeyedTableEntry(key, value);
  }
}

// Indexed table entry: [key] = value (index assignment)
class IndexedTableEntry extends TableEntry with Dumpable {
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

  @override
  Map<String, dynamic> dump() => {
    'type': 'IndexedTableEntry',
    'key': key is Dumpable ? (key as Dumpable).dump() : {'type': 'Unknown'},
    'value': value is Dumpable
        ? (value as Dumpable).dump()
        : {'type': 'Unknown'},
  };

  static IndexedTableEntry fromDump(Map<String, dynamic> data) {
    final key = undumpAst(Map<String, dynamic>.from(data['key']));
    final value = undumpAst(Map<String, dynamic>.from(data['value']));
    return IndexedTableEntry(key, value);
  }
}

/// Table entry given as a lone expression.
class TableEntryLiteral extends TableEntry with Dumpable {
  final AstNode expr;

  TableEntryLiteral(this.expr);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitTableEntryLiteral(this);

  @override
  String toSource() => expr.toSource();

  @override
  String toString() => "TableEntryLiteral(${expr.toString()})";

  @override
  Map<String, dynamic> dump() => {
    'type': 'TableEntryLiteral',
    'expr': expr is Dumpable ? (expr as Dumpable).dump() : {'type': 'Unknown'},
  };

  static TableEntryLiteral fromDump(Map<String, dynamic> data) {
    final expr = undumpAst(Map<String, dynamic>.from(data['expr']));
    return TableEntryLiteral(expr);
  }
}

/// Literal representing a nil value.
class NilValue extends AstNode with Dumpable {
  NilValue();

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitNilValue(this);

  @override
  String toSource() => "nil";

  @override
  Map<String, dynamic> dump() => {'type': 'NilValue'};

  static NilValue fromDump(Map<String, dynamic> data) {
    return NilValue();
  }
}

/// Numeric literal.
class NumberLiteral extends AstNode with Dumpable {
  final dynamic value;

  NumberLiteral(this.value) : assert(value is num || value is BigInt);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitNumberLiteral(this);

  @override
  String toSource() => value.toString();

  @override
  Map<String, dynamic> dump() => {'type': 'NumberLiteral', 'value': value};

  static NumberLiteral fromDump(Map<String, dynamic> data) {
    final v = data['value'];
    return NumberLiteral(v is int ? v : (v is double ? v : (v as num)));
  }
}

/// String literal.
class StringLiteral extends AstNode with Dumpable {
  final String value;
  final bool isLongString;

  // Cache the parsed bytes for efficient access
  late final List<int> _bytes;

  StringLiteral(String raw, {this.isLongString = false}) : value = raw {
    if (isLongString) {
      // Long strings don't process escape sequences - use raw bytes
      _bytes = raw.codeUnits;
    } else {
      // Regular strings process escape sequences
      _bytes = LuaStringParser.parseStringContent(raw);
    }
  }

  /// Get the byte representation of this string literal
  List<int> get bytes => _bytes;

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitStringLiteral(this);

  @override
  String toSource() => "\"$value\"";

  @override
  Map<String, dynamic> dump() => {
    'type': 'StringLiteral',
    'value': value,
    'isLongString': isLongString,
  };

  static StringLiteral fromDump(Map<String, dynamic> data) {
    return StringLiteral(
      data['value'] as String,
      isLongString: data['isLongString'] as bool? ?? false,
    );
  }
}

/// Boolean literal.
class BooleanLiteral extends AstNode with Dumpable {
  final bool value;

  BooleanLiteral(this.value);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) =>
      visitor.visitBooleanLiteral(this);

  @override
  String toSource() => value ? "true" : "false";

  @override
  Map<String, dynamic> dump() => {'type': 'BooleanLiteral', 'value': value};

  static BooleanLiteral fromDump(Map<String, dynamic> data) {
    return BooleanLiteral(data['value'] as bool);
  }
}

/// Identifier.
class Identifier extends AstNode with Dumpable {
  final String name;

  Identifier(this.name);

  @override
  Future<T> accept<T>(AstVisitor<T> visitor) => visitor.visitIdentifier(this);

  @override
  String toSource() => name;

  @override
  String toString() => name;

  @override
  Map<String, dynamic> dump() => {
    'type': 'Identifier',
    'name': name,
    'span': dumpSpan(),
  };

  static Identifier fromDump(Map<String, dynamic> data) {
    final identifier = Identifier(data['name'] as String);
    identifier.restoreSpan(data['span'] as Map<String, dynamic>?, null);
    return identifier;
  }
}
