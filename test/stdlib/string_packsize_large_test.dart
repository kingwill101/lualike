import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  test('packsize handles large fixed string sizes', () async {
    final bridge = LuaLike();
    await bridge.execute(
      'result = string.packsize("c" .. tostring(math.maxinteger - 9))',
    );
    expect(
      (bridge.getGlobal('result') as Value).raw,
      equals(9223372036854775798),
    );
  });
}
