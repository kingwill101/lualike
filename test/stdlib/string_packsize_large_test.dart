import 'package:test/test.dart';
import 'package:lualike/lualike.dart';

void main() {
  test('packsize handles large fixed string sizes', () async {
    final bridge = LuaLike();
    await bridge.runCode(
      'result = string.packsize("c" .. tostring(math.maxinteger - 9))',
    );
    expect(
      (bridge.getGlobal('result') as Value).raw,
      equals(9223372036854775798),
    );
  });
}
