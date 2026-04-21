import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('HintingMode enum', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());
    });

    test('global HintingMode table is installed', () {
      final enumValue = runtime.globals.get('HintingMode');
      expect(enumValue, isA<Value>());
      final table = (enumValue! as Value).raw as Map;

      expect(table['normal'], 'normal');
      expect(table['light'], 'light');
      expect(table['mono'], 'mono');
      expect(table['none'], 'none');
      expect(table.length, 4);
    });

    test('love.font.HintingMode sub-table is installed', () {
      final love = runtime.globals.get('love');
      expect(love, isA<Value>());
      final loveTable = (love! as Value).raw as Map;
      final fontModule = (loveTable['font']! as Value).raw as Map;
      final enumEntry = fontModule['HintingMode'];

      expect(enumEntry, isA<Value>());
      final table = (enumEntry! as Value).raw as Map;
      expect(table['normal'], 'normal');
      expect(table['light'], 'light');
      expect(table['mono'], 'mono');
      expect(table['none'], 'none');
    });

    test(
      'global HintingMode and love.font.HintingMode share the same table',
      () {
        final globalValue = runtime.globals.get('HintingMode');
        expect(globalValue, isA<Value>());
        final globalTable = (globalValue! as Value).raw as Map;

        final love = runtime.globals.get('love');
        expect(love, isA<Value>());
        final loveTable = (love! as Value).raw as Map;
        final fontModule = (loveTable['font']! as Value).raw as Map;
        final moduleTable = (fontModule['HintingMode']! as Value).raw as Map;

        expect(identical(globalTable, moduleTable), isTrue);
      },
    );

    test('Lua scripts can read HintingMode constants', () async {
      final lua = LuaLike(runtime: runtime);
      final result = await lua.execute('''
        return HintingMode.normal, love.font.HintingMode.mono
      ''');

      expect(_unwrapMulti(result), <Object?>['normal', 'mono']);
    });
  });
}

List<Object?> _unwrapMulti(Object? result) {
  if (result is Value && result.isMulti) {
    return (result.raw as List<Object?>).map(_unwrap).toList(growable: false);
  }
  if (result is List) {
    return result.map(_unwrap).toList(growable: false);
  }
  final single = _unwrap(result);
  return single == null ? <Object?>[] : <Object?>[single];
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
