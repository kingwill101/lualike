/// LOVE 11.5 runtime bindings and Flutter integration for LuaLike.
///
/// Import this library to install the generated LOVE API surface into a
/// [LuaRuntime], drive scripts with [LoveScriptRuntime], or embed a LOVE entry
/// point in Flutter with [LoveFlameHarness].
library;

export 'package:lualike/lualike.dart' show EngineMode;

export 'src/generated/love_api_reference.g.dart' hide installLove2d;
export 'src/generated/love_api_stubs.g.dart' show loveApiStubImplementations;
export 'src/install_love2d.dart' show attachLoveHost, installLove2d;
export 'src/love_api_overrides.dart' show loveApiOverrides;
export 'src/love_api_support.dart';
export 'src/runtime/flame/love_flame_harness.dart' show LoveFlameHarness;
export 'src/runtime/flame/love_flame_host.dart' show LoveFlameHost;
export 'src/runtime/flame/love_flame_input.dart' show LoveFlameInputAdapter;
export 'src/runtime/flame/love_touch_controls.dart'
    show
        LoveTouchButtonConfig,
        LoveTouchButtonVisual,
        LoveTouchControlSide,
        LoveTouchControlsConfig,
        LoveTouchControlsOverlay,
        LoveTouchDirectionBindings,
        LoveTouchJoystickConfig,
        LoveTouchKeyBinding;
export 'src/runtime/flame/love_flame_harness_renderer.dart'
    show
        LoveFlameFrameTimingSample,
        LoveFlameFrameTimingStats,
        LoveFlameHarnessGame,
        LoveFlameRenderStats,
        renderSurfaceSnapshot;
export 'src/runtime/renderer/renderer.dart';
export 'src/runtime/input/love_joystick_input_adapter.dart'
    show LoveJoystickInputAdapter;
export 'src/runtime/filesystem/love_asset_bundle_filesystem.dart'
    show LoveAssetBundleFilesystemAdapter;
export 'src/runtime/filesystem/love_flutter_filesystem.dart'
    show LoveFlutterFilesystemAdapter;
export 'src/runtime/filesystem/love_filesystem_runtime.dart'
    show
        LoveFilesystemAdapter,
        LoveFilesystemFileData,
        LoveFilesystemInfo,
        LoveFilesystemNodeType,
        LoveLualikeFilesystemAdapter;
export 'src/runtime/love_script_runtime.dart'
    show LoveScriptRuntime, LoveScriptRuntimeJoystickCallbacks;
export 'src/runtime/love_runtime.dart';
export 'src/runtime/video/love_media_kit_video_frame_provider.dart'
    show
        LoveMediaKitInitializer,
        LoveMediaKitVideoFrameProvider,
        ensureLoveMediaKitInitialized,
        loveMediaKitVideoFrameProviderFactory;
