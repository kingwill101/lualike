@Tags(['interop'])
import 'package:test/test.dart';
import 'package:lualike/lualike.dart';
import 'package:lualike/src/value_class.dart';

void main() {
  group('ValueClass', () {
    test('creates new Value objects with metamethods', () async {
      // Create a Point class with add metamethod
      final pointClass = ValueClass.create({
        "__add": (List<Object?> args) {
          final a = (args[0] as Value).unwrap();
          final b = (args[1] as Value).unwrap();
          return Value({
            "x": (a["x"] as num) + (b["x"] as num),
            "y": (a["y"] as num) + (b["y"] as num),
          });
        },
      });

      // Create two points
      var p1 = pointClass.call([]) as Value;
      var p2 = pointClass.call([]) as Value;

      // Set coordinates
      p1["x"] = 1;
      p1["y"] = 2;
      p2["x"] = 3;
      p2["y"] = 4;

      // Test addition using metamethod
      var vm = Interpreter();
      vm.globals.define("Point", pointClass);
      vm.globals.define("p1", p1);
      vm.globals.define("p2", p2);

      var addExpr = BinaryExpression(Identifier("p1"), "+", Identifier("p2"));

      var result = (await addExpr.accept(vm) as Value).unwrap();
      expect(result["x"], equals(4));
      expect(result["y"], equals(6));
    });

    test('supports custom toString via __tostring metamethod', () {
      final pointClass = ValueClass.create({
        "__tostring": (List<Object?> args) {
          final p = (args[0] as Value).unwrap();
          return "Point(${p["x"]}, ${p["y"]})";
        },
      });

      var point = pointClass.call([]) as Value;
      point["x"] = 10;
      point["y"] = 20;

      final toStringMethod = point.getMetamethod("__tostring") as Function;
      expect(toStringMethod([point]), equals("Point(10, 20)"));
    });
  });
}
