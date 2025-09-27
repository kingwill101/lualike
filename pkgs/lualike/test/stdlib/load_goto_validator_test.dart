import 'package:lualike_test/test.dart';

void main() {
  group('load() goto validation', () {
    late LuaLike lua;

    setUp(() => lua = LuaLike());

    test('rejects goto jumping into local scope', () async {
      await lua.execute(r'''
        f, err = load("goto l1; local aa ::l1:: print(3)")
      ''');

      final f = lua.getGlobal('f') as Value;
      final err = lua.getGlobal('err') as Value;

      expect(f.unwrap(), isNull);
      expect(err.unwrap(), contains("local 'aa'"));
    });

    test('allows valid forward goto', () async {
      await lua.execute(r'''
        loader, loadErr = load([[goto finish; do local x = 1 end ::finish:: return 42]])
      ''');

      final loader = lua.getGlobal('loader') as Value;
      final loadErr = lua.getGlobal('loadErr') as Value;

      expect(loader.unwrap(), isNotNull);
      expect(loadErr.unwrap(), isNull);

      final result = await lua.execute('return loader()') as Value;
      expect(result.unwrap(), equals(42));
    });
  });
}
