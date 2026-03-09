import 'package:lualike/src/table_storage.dart';
import 'package:test/test.dart';

void main() {
  group('TableStorage', () {
    test('stores dense numeric keys in array segment', () {
      final storage = TableStorage();

      for (var i = 1; i <= 5; i++) {
        storage[i] = i * 10;
      }

      expect(storage.length, 5);
      for (var i = 1; i <= 5; i++) {
        expect(storage[i], i * 10);
      }

      expect(storage.containsKey(3), isTrue);
      expect(storage.keys.toList(), equals([1, 2, 3, 4, 5]));
    });

    test('reassigning dense key updates value without increasing length', () {
      final storage = TableStorage()
        ..[1] = 'a'
        ..[1] = 'b';

      expect(storage.length, 1);
      expect(storage[1], 'b');
    });

    test('assigning null removes entry for array and hash values', () {
      final storage = TableStorage()
        ..[1] = 'keep'
        ..[2] = 'remove'
        ..['hash'] = 42;

      storage[2] = null;
      storage['hash'] = null;

      expect(storage.length, 1);
      expect(storage[1], 'keep');
      expect(storage.containsKey(2), isFalse);
      expect(storage.containsKey('hash'), isFalse);
      expect(storage[2], isNull);
    });

    test('sparse numeric keys fall back to hash segment', () {
      final storage = TableStorage()
        ..[1] = 'start'
        ..[1000] = 'far'
        ..[5000] = 'veryFar';

      expect(storage.length, 3);
      expect(storage[1], 'start');
      expect(storage[1000], 'far');
      expect(storage[5000], 'veryFar');

      expect(storage.containsKey(1000), isTrue);
      expect(storage.containsKey(5000), isTrue);

      final keys = storage.keys.toList();
      expect(keys, containsAll(<int>[1, 1000, 5000]));
    });

    test('remove works for both array and hash entries', () {
      final storage = TableStorage()
        ..[1] = 'a'
        ..[2] = 'b'
        ..[100] = 'hash';

      expect(storage.remove(2), 'b');
      expect(storage.length, 2);
      expect(storage.containsKey(2), isFalse);

      expect(storage.remove(100), 'hash');
      expect(storage.length, 1);
      expect(storage.containsKey(100), isFalse);

      expect(storage.remove(999), isNull);
    });

    test('clear empties both array and hash parts', () {
      final storage = TableStorage()
        ..[1] = 1
        ..[2] = 2
        ..['foo'] = 'bar'
        ..[1000] = 'baz';

      storage.clear();

      expect(storage.length, 0);
      expect(storage.keys, isEmpty);
      expect(storage.containsKey(1), isFalse);
      expect(storage.containsKey('foo'), isFalse);
    });

    test('factory constructor copies existing map content', () {
      final original = {1: 'one', 'foo': 'bar', 50: 'fifty'};

      final storage = TableStorage.from(original);

      expect(storage.length, original.length);
      expect(storage[1], 'one');
      expect(storage['foo'], 'bar');
      expect(storage[50], 'fifty');

      storage[2] = 'two';
      expect(original.containsKey(2), isFalse);
    });

    test('supports zero and negative numeric keys via hash path', () {
      final storage = TableStorage()
        ..[0] = 'zero'
        ..[-1] = 'negative'
        ..[1] = 'one';

      expect(storage[0], 'zero');
      expect(storage[-1], 'negative');
      expect(storage[1], 'one');

      final keys = storage.keys.toList();
      expect(keys, containsAll(<int>[1, 0, -1]));
    });

    test('setDense falls back to hash for very large indices', () {
      final storage = TableStorage();
      final int hugeIndex = 9223372036854775806; // near max 64-bit integer

      storage.setDense(hugeIndex, 'huge');

      expect(storage[hugeIndex], 'huge');
      expect(storage.containsKey(hugeIndex), isTrue);
    });

    test('tracks recently deleted hash keys for next-style iteration', () {
      final storage = TableStorage()
        ..['a'] = 1
        ..['b'] = 2
        ..['c'] = 3;

      expect(storage.firstHashEntry()?.key, 'a');
      expect(storage.nextHashEntryAfter('a')?.key, 'b');

      storage.remove('b');

      expect(storage.containsKey('b'), isFalse);
      expect(storage.containsIterationKey('b'), isTrue);
      expect(storage.keys.toList(), equals(['a', 'c']));
      expect(storage.nextHashEntryAfter('b')?.key, 'c');
    });

    test('tracks recently deleted dense keys for next-style iteration', () {
      final storage = TableStorage()
        ..[1] = 'a'
        ..[2] = 'b'
        ..[3] = 'c';

      expect(storage.containsDenseIterationIndex(2), isTrue);

      storage.remove(2);

      expect(storage.containsKey(2), isFalse);
      expect(storage.containsIterationKey(2), isTrue);
      expect(storage.containsDenseIterationIndex(2), isTrue);
      expect(storage.containsDenseIterationIndex(3), isTrue);
    });
  });
}
