import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('Event enum', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());
    });

    test('global Event table is installed with all 37 constants', () {
      final eventEnum = runtime.globals.get('Event');
      expect(eventEnum, isA<Value>());
      final table = (eventEnum! as Value).raw as Map;

      final expectedEvents = <String>[
        'focus',
        'joystickpressed',
        'joystickreleased',
        'keypressed',
        'keyreleased',
        'mousepressed',
        'mousereleased',
        'quit',
        'resize',
        'visible',
        'mousefocus',
        'threaderror',
        'joystickadded',
        'joystickremoved',
        'joystickaxis',
        'joystickhat',
        'gamepadpressed',
        'gamepadreleased',
        'gamepadaxis',
        'textinput',
        'mousemoved',
        'lowmemory',
        'textedited',
        'wheelmoved',
        'touchpressed',
        'touchreleased',
        'touchmoved',
        'directorydropped',
        'filedropped',
        // Legacy abbreviated aliases
        'jp',
        'jr',
        'kp',
        'kr',
        'mp',
        'mr',
        'q',
        'f',
      ];

      for (final name in expectedEvents) {
        expect(
          table[name],
          equals(name),
          reason: 'Event.$name should equal "$name"',
        );
      }

      expect(table.length, equals(37));
    });

    test('every Event constant is self-referential (name == value)', () {
      final eventEnum = runtime.globals.get('Event');
      expect(eventEnum, isA<Value>());
      final table = (eventEnum! as Value).raw as Map;

      for (final entry in table.entries) {
        expect(
          entry.value,
          equals(entry.key),
          reason: 'Event.${entry.key} should equal "${entry.key}"',
        );
      }
    });

    test('love.event.Event sub-table is installed', () {
      final love = runtime.globals.get('love');
      expect(love, isA<Value>());
      final loveTable = (love! as Value).raw as Map;

      final event = loveTable['event'];
      expect(event, isA<Value>());
      final eventTable = (event! as Value).raw as Map;

      final enumEntry = eventTable['Event'];
      expect(enumEntry, isA<Value>());
      final enumTable = (enumEntry! as Value).raw as Map;

      expect(enumTable['focus'], equals('focus'));
      expect(enumTable['keypressed'], equals('keypressed'));
      expect(enumTable['mousemoved'], equals('mousemoved'));
      expect(enumTable['quit'], equals('quit'));
      expect(enumTable['touchpressed'], equals('touchpressed'));
      expect(enumTable['f'], equals('f'));
    });

    test('global Event and love.event.Event are the same object', () {
      final globalEnum = runtime.globals.get('Event');
      expect(globalEnum, isA<Value>());
      final globalTable = (globalEnum! as Value).raw as Map;

      final love = runtime.globals.get('love');
      final loveTable = (love! as Value).raw as Map;
      final eventModule = (loveTable['event']! as Value).raw as Map;
      final moduleEnum = (eventModule['Event']! as Value).raw as Map;

      // Both should be the same underlying Dart map instance.
      expect(identical(globalTable, moduleEnum), isTrue);
    });

    test('Lua script can read Event constants via global table', () async {
      final lua = LuaLike(runtime: runtime);
      final result = await lua.execute('''
        return Event.focus, Event.keypressed, Event.mousereleased
      ''');
      expect(
        _unwrapMulti(result),
        equals(<String>['focus', 'keypressed', 'mousereleased']),
      );
    });

    test('Lua script can read Event constants via love.event.Event', () async {
      final lua = LuaLike(runtime: runtime);
      final result = await lua.execute('''
        return love.event.Event.quit, love.event.Event.textinput
      ''');
      expect(_unwrapMulti(result), equals(<String>['quit', 'textinput']));
    });

    test('Lua script can use Event constant as event name for push', () async {
      final lua = LuaLike(runtime: runtime);
      await lua.execute('''
        love.event.push(Event.focus, true)
      ''');

      // Retrieve via poll iterator
      final pollResult = await lua.execute('''
        local iter = love.event.poll()
        local name, arg = iter()
        return name, arg
      ''');
      expect(_unwrapMulti(pollResult), equals(<Object?>['focus', true]));
    });

    test('loveIsValidEventName returns true for all standard event names', () {
      // Access through Dart to verify the validation helper works
      expect(loveIsValidEventName('focus'), isTrue);
      expect(loveIsValidEventName('keypressed'), isTrue);
      expect(loveIsValidEventName('mousemoved'), isTrue);
      expect(loveIsValidEventName('quit'), isTrue);
      expect(loveIsValidEventName('touchpressed'), isTrue);
      expect(loveIsValidEventName('directorydropped'), isTrue);
      expect(loveIsValidEventName('filedropped'), isTrue);
      // Legacy aliases
      expect(loveIsValidEventName('jp'), isTrue);
      expect(loveIsValidEventName('kp'), isTrue);
      expect(loveIsValidEventName('f'), isTrue);
      expect(loveIsValidEventName('q'), isTrue);
    });

    test('loveIsValidEventName returns false for unknown event names', () {
      expect(loveIsValidEventName(''), isFalse);
      expect(loveIsValidEventName('unknown'), isFalse);
      expect(loveIsValidEventName('FOCUS'), isFalse);
      expect(loveIsValidEventName('customevent'), isFalse);
    });

    test('reinstalling love2d on same runtime is idempotent', () {
      // A second install should not crash or duplicate the table.
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final eventEnum = runtime.globals.get('Event');
      expect(eventEnum, isA<Value>());
      final table = (eventEnum! as Value).raw as Map;
      expect(table.length, equals(37));
    });
  });
}

List<Object?> _unwrapMulti(Object? result) {
  if (result is Value && result.isMulti) {
    return (result.raw as List<Object?>).map(luaUnwrapValue).toList(growable: false);
  }
  // LuaLike.execute converts multi-value returns into a plain Dart List<dynamic>
  // (each element already wrapped in Value). Handle that case here.
  if (result is List) {
    return result.map(luaUnwrapValue).toList(growable: false);
  }
  final single = luaUnwrapValue(result);
  return single == null ? <Object?>[] : <Object?>[single];
}
