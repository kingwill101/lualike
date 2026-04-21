import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  test('love.window installs enum tables and accepts enum constants', () async {
    LoveWindowMessageBoxData? lastMessageBox;
    final runtime = LoveScriptRuntime(
      host: LoveHeadlessHost(
        windowMetrics: const LoveWindowMetrics(
          fullscreen: false,
          fullscreenType: 'desktop',
          display: 1,
        ),
        windowDisplays: const <LoveWindowDisplay>[
          LoveWindowDisplay(
            name: 'Primary',
            orientation: 'landscape',
            fullscreenModes: <LoveWindowFullscreenMode>[
              LoveWindowFullscreenMode(width: 1920, height: 1080),
            ],
          ),
        ],
        windowMessageBoxHandler: (data) {
          lastMessageBox = data;
          return const LoveWindowMessageBoxResponse(success: true);
        },
      ),
    );

    await runtime.execute('''
testbed = {}

local orientation = love.window.getDisplayOrientation(1)
testbed.global_orientation = DisplayOrientation.landscape
testbed.module_orientation = love.window.DisplayOrientation.portrait
testbed.global_fullscreen = FullscreenType.desktop
testbed.module_fullscreen = love.window.FullscreenType.normal
testbed.global_messagebox = MessageBoxType.warning
testbed.module_messagebox = love.window.MessageBoxType.error
testbed.orientation_matches = orientation == DisplayOrientation.landscape

testbed.set_ok = love.window.setFullscreen(true, FullscreenType.normal)
testbed.fullscreen, testbed.fullscreen_type = love.window.getFullscreen()
testbed.msg_ok = love.window.showMessageBox(
  "Heads up",
  "Window enum check",
  MessageBoxType.warning,
  false
)
''');

    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    expect(snapshot['global_orientation'], 'landscape');
    expect(snapshot['module_orientation'], 'portrait');
    expect(snapshot['global_fullscreen'], 'desktop');
    expect(snapshot['module_fullscreen'], 'normal');
    expect(snapshot['global_messagebox'], 'warning');
    expect(snapshot['module_messagebox'], 'error');
    expect(snapshot['orientation_matches'], isTrue);
    expect(snapshot['set_ok'], isTrue);
    expect(snapshot['fullscreen'], isTrue);
    expect(snapshot['fullscreen_type'], 'normal');
    expect(snapshot['msg_ok'], isTrue);
    expect(lastMessageBox, isNotNull);
    expect(lastMessageBox!.type, 'warning');
    expect(lastMessageBox!.attachToWindow, isFalse);
  });
}
