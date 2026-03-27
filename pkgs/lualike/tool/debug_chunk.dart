import 'package:lualike/src/ir/runtime.dart';
import 'package:lualike/src/parse.dart';

Future<void> main() async {
  const source = '''
local cap
local function f(op)
  return function (...)
    cap = {[0] = op, ...}
    return (...)
  end
end
local g = f("add")
g({}, 5)
return cap[0], cap[1], cap[2]
''';
  final program = parse(source);
  final runtime = LualikeIrRuntime();
  final result = await runtime.runAst(program.statements);
  print(result);
}
