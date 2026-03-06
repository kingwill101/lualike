@Tags(['ir'])
library;

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/prototype.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('LualikeIrCompiler const locals', () {
    test('marks literal const locals and schedules seal points', () {
      const source = '''
local a <const>, b <const> = 1, 2
return a, b
''';
      final chunk = LualikeIrCompiler().compile(parse(source));
      final proto = chunk.mainPrototype;

      expect(proto.registerConstFlags.length, greaterThanOrEqualTo(2));
      expect(proto.registerConstFlags[0], isTrue);
      expect(proto.registerConstFlags[1], isTrue);

      final seals = proto.constSealPoints;
      expect(seals.values.expand((points) => points), containsAll(<int>[0, 1]));
      expect(seals.entries.any((entry) => entry.value.contains(0)), isTrue);
      expect(seals.entries.any((entry) => entry.value.contains(1)), isTrue);
    });

    test('marks const locals initialised from varargs', () {
      const source = '''
local a <const>, b <const> = ...
return a, b
''';
      final chunk = LualikeIrCompiler().compile(parse(source));
      final proto = chunk.mainPrototype;

      expect(proto.registerConstFlags[0], isTrue);
      expect(proto.registerConstFlags[1], isTrue);

      final sealEntries = proto.constSealPoints.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      expect(sealEntries.length, greaterThanOrEqualTo(2));
      expect(sealEntries[0].value, contains(0));
      expect(sealEntries[1].value, contains(1));
    });

    test('marks const locals with implicit nil initialisers', () {
      const source = '''
local a <const>, b <const>
return a, b
''';
      final chunk = LualikeIrCompiler().compile(parse(source));
      final proto = chunk.mainPrototype;

      expect(proto.registerConstFlags[0], isTrue);
      expect(proto.registerConstFlags[1], isTrue);
      expect(
        proto.constSealPoints.values.expand((points) => points),
        containsAll(<int>[0, 1]),
      );
    });
  });
}
