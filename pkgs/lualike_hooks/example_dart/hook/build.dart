import 'package:hooks/hooks.dart';
import 'package:lualike_hooks/lualike_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final builder = LuaBuilder(
      sources: ['lua/'],
    );
    await builder.run(input: input, output: output, logger: null);
  });
}
