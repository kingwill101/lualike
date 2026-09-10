import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  test('love.system installs PowerState enum tables', () async {
    final runtime = LoveScriptRuntime(
      host: LoveHeadlessHost(
        system: LoveSystemState(
          powerInfo: const LoveSystemPowerInfo(
            state: 'charging',
            percent: 90,
            seconds: 1800,
          ),
        ),
      ),
    );

    await runtime.execute('''
testbed = {}

local state, percent, seconds = love.system.getPowerInfo()
testbed.global_charging = PowerState.charging
testbed.module_charged = love.system.PowerState.charged
testbed.matches_global = state == PowerState.charging
testbed.matches_module = state == love.system.PowerState.charging
testbed.percent = percent
testbed.seconds = seconds
''');

    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    expect(snapshot['global_charging'], 'charging');
    expect(snapshot['module_charged'], 'charged');
    expect(snapshot['matches_global'], isTrue);
    expect(snapshot['matches_module'], isTrue);
    expect(snapshot['percent'], 90);
    expect(snapshot['seconds'], 1800);
  });
}
