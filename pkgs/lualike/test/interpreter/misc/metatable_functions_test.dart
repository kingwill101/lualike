import 'package:lualike_test/test.dart';

void main() {
  group('Metatable Functions', () {
    test('rawset sets table field directly', () async {
      var vm = Interpreter();

      // Create a table with a __newindex metamethod
      await vm.run([
        LocalDeclaration(
          [Identifier("t")],
          [],
          [TableConstructor([])], // empty table
        ),
        // Set metatable with __newindex
        ExpressionStatement(
          FunctionCall(Identifier("setmetatable"), [
            Identifier("t"),
            TableConstructor([
              KeyedTableEntry(
                Identifier("__newindex"),
                FunctionLiteral(
                  FunctionBody(
                    [
                      Identifier("table"),
                      Identifier("key"),
                      Identifier("value"),
                    ],
                    [
                      // Metamethod that would modify the key
                      ExpressionStatement(
                        FunctionCall(Identifier("rawset"), [
                          Identifier("table"),
                          BinaryExpression(
                            Identifier("key"),
                            ".",
                            StringLiteral("_modified"),
                          ),
                          Identifier("value"),
                        ]),
                      ),
                    ],
                    false, // isVararg: false
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ]);

      // Use rawset to bypass the metamethod
      await vm.run([
        ExpressionStatement(
          FunctionCall(Identifier("rawset"), [
            Identifier("t"),
            StringLiteral("x"),
            NumberLiteral(10),
          ]),
        ),
      ]);

      // Verify that rawset bypassed the metamethod
      var table = vm.globals.get("t") as Value;
      var tableMap = table.unwrap() as Map;
      expect(tableMap["x"], equals(10));
      expect(tableMap.containsKey("x_modified"), isFalse);
    });

    test('rawset throws on non-table value', () async {
      var vm = Interpreter();
      vm.globals.define("n", Value(42));

      expect(
        () async => await ExpressionStatement(
          FunctionCall(Identifier("rawset"), [
            Identifier("n"),
            StringLiteral("field"),
            NumberLiteral(10),
          ]),
        ).accept(vm),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('first argument must be a table'),
          ),
        ),
      );
    });
  });
}
