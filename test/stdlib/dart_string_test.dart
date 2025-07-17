import 'package:lualike/testing.dart';

void main() {
  group('dart.string', () {
    Future<void> testFunction(
      String funcName,
      List<dynamic> args,
      dynamic expected,
    ) async {
      final bridge = LuaLike();
      for (var i = 0; i < args.length; i++) {
        bridge.setGlobal('arg$i', Value(args[i]));
      }
      final argString = List.generate(args.length, (i) => 'arg$i').join(',');
      await bridge.execute('result = dart.string.$funcName($argString)');
      final result = bridge.getGlobal('result');
      if (expected is List) {
        expect((result! as Value).unwrap(), isA<List>());
        expect(
          ((result as Value).unwrap() as List)
              .map((v) => v is Value ? v.unwrap() : v)
              .toList(),
          orderedEquals(expected),
        );
      } else {
        expect((result! as Value).unwrap(), expected);
      }
    }

    test('split', () async {
      await testFunction('split', ['a,b,c', ','], ['a', 'b', 'c']);
    });

    test('trim', () async {
      await testFunction('trim', ['  abc  '], 'abc');
    });

    test('toUpperCase', () async {
      await testFunction('toUpperCase', ['abc'], 'ABC');
    });

    test('toLowerCase', () async {
      await testFunction('toLowerCase', ['ABC'], 'abc');
    });

    test('contains', () async {
      await testFunction('contains', ['abc', 'b'], true);
      await testFunction('contains', ['abc', 'd'], false);
      await testFunction('contains', ['abc', 'b', 1], true);
      await testFunction('contains', ['abc', 'a', 1], false);
    });

    test('replaceAll', () async {
      await testFunction('replaceAll', ['abacaba', 'a', 'z'], 'zbzczbz');
    });

    test('substring', () async {
      await testFunction('substring', ['abcde', 1], 'bcde');
      await testFunction('substring', ['abcde', 1, 3], 'bc');
    });

    test('trimLeft', () async {
      await testFunction('trimLeft', ['  abc  '], 'abc  ');
    });

    test('trimRight', () async {
      await testFunction('trimRight', ['  abc  '], '  abc');
    });

    test('padLeft', () async {
      await testFunction('padLeft', ['a', 4], '   a');
      await testFunction('padLeft', ['a', 4, 'x'], 'xxxa');
    });

    test('padRight', () async {
      await testFunction('padRight', ['a', 4], 'a   ');
      await testFunction('padRight', ['a', 4, 'x'], 'axxx');
    });

    test('startsWith', () async {
      await testFunction('startsWith', ['abc', 'a'], true);
      await testFunction('startsWith', ['abc', 'b'], false);
      await testFunction('startsWith', ['abc', 'b', 1], true);
    });

    test('endsWith', () async {
      await testFunction('endsWith', ['abc', 'c'], true);
      await testFunction('endsWith', ['abc', 'b'], false);
    });

    test('indexOf', () async {
      await testFunction('indexOf', ['abcabc', 'b'], 1);
      await testFunction('indexOf', ['abcabc', 'b', 2], 4);
    });

    test('lastIndexOf', () async {
      await testFunction('lastIndexOf', ['abcabc', 'b'], 4);
      await testFunction('lastIndexOf', ['abcabc', 'b', 3], 1);
    });

    test('replaceFirst', () async {
      await testFunction('replaceFirst', ['abacaba', 'a', 'z'], 'zbacaba');
    });

    test('isEmpty', () async {
      await testFunction('isEmpty', [''], true);
      await testFunction('isEmpty', ['a'], false);
    });

    test('fromCharCodes', () async {
      await testFunction('fromCharCodes', [
        {
          Value(1): Value(104),
          Value(2): Value(101),
          Value(3): Value(108),
          Value(4): Value(108),
          Value(5): Value(111),
        },
      ], 'hello');
    });
  });
}
