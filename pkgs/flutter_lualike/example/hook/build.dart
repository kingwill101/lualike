import 'package:hooks/hooks.dart';
import 'package:flutter_lualike/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final builder = LuaBuilder(sources: ['assets/lua/']);
    await builder.run(input: input, output: output, logger: null);
  });
}
