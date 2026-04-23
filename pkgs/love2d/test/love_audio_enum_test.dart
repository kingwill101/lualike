import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('audio enums', () {
    late LuaRuntime runtime;

    setUp(() {
      runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());
    });

    test(
      'global enum tables are installed with self-referential constants',
      () {
        const expected = <String, List<String>>{
          'DistanceModel': <String>[
            'none',
            'inverse',
            'inverseclamped',
            'linear',
            'linearclamped',
            'exponent',
            'exponentclamped',
          ],
          'EffectType': <String>[
            'chorus',
            'compressor',
            'distortion',
            'echo',
            'equalizer',
            'flanger',
            'reverb',
            'ringmodulator',
          ],
          'EffectWaveform': <String>['sawtooth', 'sine', 'square', 'triangle'],
          'FilterType': <String>['lowpass', 'highpass', 'bandpass'],
          'SourceType': <String>['static', 'stream', 'queue'],
          'TimeUnit': <String>['seconds', 'samples'],
        };

        for (final entry in expected.entries) {
          final enumValue = runtime.globals.get(entry.key);
          expect(enumValue, isA<Value>(), reason: '${entry.key} should exist');
          final table = (enumValue! as Value).raw as Map;
          for (final constant in entry.value) {
            expect(
              table[constant],
              constant,
              reason: '${entry.key}.$constant should equal "$constant"',
            );
          }
          expect(table.length, entry.value.length);
        }
      },
    );

    test('love.audio exposes the same enum tables as globals', () {
      final love = runtime.globals.get('love');
      final loveTable = (love! as Value).raw as Map;
      final audioTable = (loveTable['audio']! as Value).raw as Map;

      for (final name in const <String>[
        'DistanceModel',
        'EffectType',
        'EffectWaveform',
        'FilterType',
        'SourceType',
        'TimeUnit',
      ]) {
        final globalTable = (runtime.globals.get(name)! as Value).raw as Map;
        final moduleTable = (audioTable[name]! as Value).raw as Map;
        expect(identical(globalTable, moduleTable), isTrue);
      }
    });

    test('Lua code can use audio enums in calls and comparisons', () async {
      final lua = LuaLike(runtime: runtime);
      final result = await lua.execute('''
        love.audio.setDistanceModel(DistanceModel.linearclamped)
        local queue = love.audio.newQueueableSource(22050, 16, 2)
        return love.audio.getDistanceModel(), SourceType.queue, TimeUnit.samples, queue:getType()
      ''');

      final values = _unwrapMulti(result);
      expect(values, <Object?>['linearclamped', 'queue', 'samples', 'queue']);
    });
  });
}

List<Object?> _unwrapMulti(Object? result) {
  return switch (result) {
    final Value wrapped when wrapped.isMulti => List<Object?>.from(
      (wrapped.raw as List<Object?>).map(_unwrap),
      growable: false,
    ),
    final Value wrapped => <Object?>[_unwrap(wrapped)],
    final List<Object?> values when values.length == 1 => switch (_unwrap(
      values.first,
    )) {
      final List<Object?> nested => nested,
      final other => <Object?>[other],
    },
    final List<Object?> values => List<Object?>.from(
      values.map(_unwrap),
      growable: false,
    ),
    _ => <Object?>[_unwrap(result)],
  };
}

Object? _unwrap(Object? value) => switch (value) {
  final Value wrapped => wrapped.unwrap(),
  final List<Object?> values => List<Object?>.from(
    values.map(_unwrap),
    growable: false,
  ),
  final other => other,
};
