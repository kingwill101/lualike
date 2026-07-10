/// Smoke tests for the constant folding pass.
///
/// These tests verify that the multi-pass compiler pipeline correctly folds
/// constant expressions and that the IR compiler emits loadK instead of
/// full expression lowering for folded nodes.

import 'dart:convert' show utf8;

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/compile/constant_folding_pass.dart';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/ir/chunk_builder.dart';
import 'package:lualike/src/ir/prototype.dart';
import 'package:lualike/src/ir/textual_formatter.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/serializer.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('ConstantFoldingPass', () {
    test('folds NumberLiteral', () {
      final pass = ConstantFoldingPass();
      final program = parse('return 42');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      expect(pass.result.isConstant(returnStmt.expr.first), isTrue);
      expect(pass.result.getValue(returnStmt.expr.first), equals(42));
    });

    test('folds boolean literals', () {
      final pass = ConstantFoldingPass();
      final program = parse('return true');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      expect(pass.result.isConstant(returnStmt.expr.first), isTrue);
      expect(pass.result.getValue(returnStmt.expr.first), equals(true));
    });

    test('folds nil literal', () {
      final pass = ConstantFoldingPass();
      final program = parse('return nil');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      expect(pass.result.isConstant(returnStmt.expr.first), isTrue);
      expect(
        pass.result.getValue(returnStmt.expr.first),
        equals(ConstantFoldingResult.constantNil),
      );
    });

    test('folds string literal', () {
      final pass = ConstantFoldingPass();
      final program = parse('return "hello"');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      expect(pass.result.isConstant(returnStmt.expr.first), isTrue);
      expect(
        pass.result.getValue(returnStmt.expr.first),
        equals(utf8.encode('hello')),
      );
    });

    test('folds binary arithmetic: 2 + 3', () {
      final pass = ConstantFoldingPass();
      final program = parse('return 2 + 3');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final binExpr = returnStmt.expr.first as BinaryExpression;
      expect(pass.result.isConstant(binExpr), isTrue);
      expect(pass.result.getValue(binExpr), equals(5));
    });

    test('folds string concatenation: "a" .. "b"', () {
      final pass = ConstantFoldingPass();
      final program = parse('return "a" .. "b"');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final binExpr = returnStmt.expr.first as BinaryExpression;
      expect(pass.result.isConstant(binExpr), isTrue);
      expect(
        pass.result.getValue(binExpr),
        equals(utf8.encode('ab')),
      );
    });

    test('folds unary not: not false', () {
      final pass = ConstantFoldingPass();
      final program = parse('return not false');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final unaryExpr = returnStmt.expr.first as UnaryExpression;
      expect(pass.result.isConstant(unaryExpr), isTrue);
      expect(pass.result.getValue(unaryExpr), equals(true));
    });

    test('folds unary negate: -5', () {
      final pass = ConstantFoldingPass();
      final program = parse('return -5');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final unaryExpr = returnStmt.expr.first as UnaryExpression;
      expect(pass.result.isConstant(unaryExpr), isTrue);
      expect(pass.result.getValue(unaryExpr), equals(-5));
    });

    test('folds grouped expression: (2 + 3) * 4', () {
      final pass = ConstantFoldingPass();
      final program = parse('return (2 + 3) * 4');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final binExpr = returnStmt.expr.first as BinaryExpression;
      expect(pass.result.isConstant(binExpr), isTrue);
      expect(pass.result.getValue(binExpr), equals(20));
    });

    test('folds comparison: 5 > 3', () {
      final pass = ConstantFoldingPass();
      final program = parse('return 5 > 3');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final binExpr = returnStmt.expr.first as BinaryExpression;
      expect(pass.result.isConstant(binExpr), isTrue);
      expect(pass.result.getValue(binExpr), equals(true));
    });

    test('folds logical and: true and false', () {
      final pass = ConstantFoldingPass();
      final program = parse('return true and false');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final binExpr = returnStmt.expr.first as BinaryExpression;
      expect(pass.result.isConstant(binExpr), isTrue);
      expect(pass.result.getValue(binExpr), equals(false));
    });

    test('folds logical short-circuit: false and expensive_call()', () {
      final pass = ConstantFoldingPass();
      final program = parse('return false and some_function()');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final binExpr = returnStmt.expr.first as BinaryExpression;
      // false and X → false (short-circuit, right side's value doesn't matter)
      expect(pass.result.isConstant(binExpr), isTrue);
      expect(pass.result.getValue(binExpr), equals(false));
    });

    test('folds logical short-circuit: true or expensive_call()', () {
      final pass = ConstantFoldingPass();
      final program = parse('return true or some_function()');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final binExpr = returnStmt.expr.first as BinaryExpression;
      expect(pass.result.isConstant(binExpr), isTrue);
      expect(pass.result.getValue(binExpr), equals(true));
    });

    test('does NOT fold function calls', () {
      final pass = ConstantFoldingPass();
      final program = parse('return foo()');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final callExpr = returnStmt.expr.first as FunctionCall;
      expect(pass.result.isConstant(callExpr), isFalse);
    });

    test('folds table field access on const table', () {
      final pass = ConstantFoldingPass();
      final program = parse('''
        local TBL <const> = {x = 5, y = 10}
        return TBL.x
      ''');
      pass.fold(program);
      final returnStmt = program.statements.last as ReturnStatement;
      final fieldAccess = returnStmt.expr.first as TableFieldAccess;
      expect(pass.result.isConstant(fieldAccess), isTrue);
      expect(pass.result.getValue(fieldAccess), equals(5));
    });

    test('folds table index access on const table', () {
      final pass = ConstantFoldingPass();
      final program = parse('''
        local TBL <const> = {10, 20, 30}
        return TBL[2]
      ''');
      pass.fold(program);
      final returnStmt = program.statements.last as ReturnStatement;
      final indexAccess = returnStmt.expr.first as TableIndexAccess;
      expect(pass.result.isConstant(indexAccess), isTrue);
      expect(pass.result.getValue(indexAccess), equals(20));
    });

    test('folds type() call with constant arg', () {
      final pass = ConstantFoldingPass();
      final program = parse('return type(42)');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final call = returnStmt.expr.first as FunctionCall;
      expect(pass.result.isConstant(call), isTrue);
      expect(
        String.fromCharCodes(pass.result.getValue(call) as List<int>),
        equals('number'),
      );
    });

    test('folds type(nil) call', () {
      final pass = ConstantFoldingPass();
      final program = parse('return type(nil)');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final call = returnStmt.expr.first as FunctionCall;
      expect(pass.result.isConstant(call), isTrue);
      expect(
        String.fromCharCodes(pass.result.getValue(call) as List<int>),
        equals('nil'),
      );
    });

    test('folds type(true) call', () {
      final pass = ConstantFoldingPass();
      final program = parse('return type(true)');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final call = returnStmt.expr.first as FunctionCall;
      expect(pass.result.isConstant(call), isTrue);
      expect(
        String.fromCharCodes(pass.result.getValue(call) as List<int>),
        equals('boolean'),
      );
    });

    test('folds type("hello") call', () {
      final pass = ConstantFoldingPass();
      final program = parse('return type("hello")');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final call = returnStmt.expr.first as FunctionCall;
      expect(pass.result.isConstant(call), isTrue);
      expect(
        String.fromCharCodes(pass.result.getValue(call) as List<int>),
        equals('string'),
      );
    });

    test('folds tostring(42)', () {
      final pass = ConstantFoldingPass();
      final program = parse('return tostring(42)');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final call = returnStmt.expr.first as FunctionCall;
      expect(pass.result.isConstant(call), isTrue);
      expect(
        String.fromCharCodes(pass.result.getValue(call) as List<int>),
        equals('42'),
      );
    });

    test('folds tonumber("42")', () {
      final pass = ConstantFoldingPass();
      final program = parse('return tonumber("42")');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final call = returnStmt.expr.first as FunctionCall;
      expect(pass.result.isConstant(call), isTrue);
      expect(pass.result.getValue(call), equals(42));
    });

    test('folds type() returns "number" for const numbers', () {
      final pass = ConstantFoldingPass();
      final program = parse('return type(42)');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final call = returnStmt.expr.first as FunctionCall;
      expect(pass.result.isConstant(call), isTrue);
      expect(
        String.fromCharCodes(pass.result.getValue(call) as List<int>),
        equals('number'),
      );
    });

    test('folds type(nil) returns "nil"', () {
      final pass = ConstantFoldingPass();
      final program = parse('return type(nil)');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final call = returnStmt.expr.first as FunctionCall;
      expect(pass.result.isConstant(call), isTrue);
      expect(
        String.fromCharCodes(pass.result.getValue(call) as List<int>),
        equals('nil'),
      );
    });

    test('folds type(true) returns "boolean"', () {
      final pass = ConstantFoldingPass();
      final program = parse('return type(true)');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final call = returnStmt.expr.first as FunctionCall;
      expect(pass.result.isConstant(call), isTrue);
      expect(
        String.fromCharCodes(pass.result.getValue(call) as List<int>),
        equals('boolean'),
      );
    });

    test('folds type("hello") returns "string"', () {
      final pass = ConstantFoldingPass();
      final program = parse('return type("hello")');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final call = returnStmt.expr.first as FunctionCall;
      expect(pass.result.isConstant(call), isTrue);
      expect(
        String.fromCharCodes(pass.result.getValue(call) as List<int>),
        equals('string'),
      );
    });

    test('folds tostring(42) returns "42"', () {
      final pass = ConstantFoldingPass();
      final program = parse('return tostring(42)');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final call = returnStmt.expr.first as FunctionCall;
      expect(pass.result.isConstant(call), isTrue);
      expect(
        String.fromCharCodes(pass.result.getValue(call) as List<int>),
        equals('42'),
      );
    });

    test('folds tonumber("42") returns 42', () {
      final pass = ConstantFoldingPass();
      final program = parse('return tonumber("42")');
      pass.fold(program);
      final returnStmt = program.statements.first as ReturnStatement;
      final call = returnStmt.expr.first as FunctionCall;
      expect(pass.result.isConstant(call), isTrue);
      expect(pass.result.getValue(call), equals(42));
    });

    test('folds local const declaration reference', () {
      final pass = ConstantFoldingPass();
      final program = parse('''
        local x <const> = 42
        return x + 1
      ''');
      pass.fold(program);
      final returnStmt = program.statements.last as ReturnStatement;
      final binExpr = returnStmt.expr.first as BinaryExpression;
      // x should resolve to 42, and 42 + 1 = 43
      expect(pass.result.isConstant(binExpr), isTrue);
      expect(pass.result.getValue(binExpr), equals(43));
    });
  });

  group('CompilePipeline', () {
    test('produces bytecode for simple program', () {
      final pipeline = CompilePipeline(
        config: const CompilePipelineConfig(
          enableConstantFolding: true,
          target: CompileBackend.luaBytecode,
        ),
      );
      final artifact = pipeline.compileSource('return 1 + 2');
      expect(artifact, isA<LuaBytecodeArtifact>());
      final luaArtifact = artifact as LuaBytecodeArtifact;
      expect(luaArtifact.serializedBytes.length, greaterThan(0));
      // With folding, 1+2 should be merged into a single constant 3.
      // Small integers use LOADI (no constant table entry).
      final chunk = luaArtifact.chunk;
      expect(chunk.mainPrototype.code.length, greaterThan(0));
    });

    test('produces IR artifact for simple program', () {
      final pipeline = CompilePipeline(
        config: const CompilePipelineConfig(
          enableConstantFolding: true,
          target: CompileBackend.lualikeIR,
        ),
      );
      final artifact = pipeline.compileSource('return 42');
      expect(artifact, isA<LualikeIrArtifact>());
      expect(artifact.serializedBytes.length, greaterThan(0));
    });

    test('folding reduces instructions for constant arithmetic', () {
      // With folding: 2 + 3 → loadK 5 (1 instruction)
      // Without folding: loadK 2, loadK 3, add (3 instructions)
      final foldedPipeline = CompilePipeline(
        config: const CompilePipelineConfig(
          enableConstantFolding: true,
          target: CompileBackend.lualikeIR,
        ),
      );
      final folded = foldedPipeline.compileSource('return 2 + 3');
      final foldedIr = folded as LualikeIrArtifact;

      final unfoldedPipeline = CompilePipeline(
        config: const CompilePipelineConfig(
          enableConstantFolding: false,
          target: CompileBackend.lualikeIR,
        ),
      );
      final unfolded = unfoldedPipeline.compileSource('return 2 + 3');
      final unfoldedIr = unfolded as LualikeIrArtifact;

      // With folding, the main prototype should have fewer instructions
      // (just loadK + return instead of loadK + loadK + add + return).
      expect(
        foldedIr.chunk.mainPrototype.instructions.length,
        lessThan(unfoldedIr.chunk.mainPrototype.instructions.length),
      );
    });
  });
}
