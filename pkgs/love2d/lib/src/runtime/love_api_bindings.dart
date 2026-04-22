library;
// ignore_for_file: implementation_imports

import 'dart:convert' show utf8;
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'package:lualike/library_builder.dart';
import 'package:lualike/lualike.dart'
    show
        Box,
        BuiltinFunction,
        Interpreter,
        LuaChunkLoadRequest,
        LuaError,
        LuaNumberParser,
        NumberUtils,
        LuaRuntime,
        LuaString,
        Value;
import 'package:lualike/src/ast.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/number_limits.dart' show NumberLimits;
import 'package:lualike/src/upvalue.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;

import '../generated/love_api_reference.g.dart'
    as love_api_generated
    show installLove2d;
import '../generated/love_api_reference.g.dart' show loveApiEnums;
import 'audio/love_audio_extra_bindings.dart'
    show installLoveAudioExtraBindings;
import 'data/love_data_extra_bindings.dart' show installLoveDataExtraBindings;
import 'event/love_event_extra_bindings.dart'
    show installLoveEventExtraBindings;
import 'filesystem/love_filesystem_runtime.dart'
    show
        LoveFilesystemFileData,
        LoveFilesystemNodeType,
        LoveFilesystemRuntimeConfig,
        LoveFilesystemRuntimeMountOperations,
        LoveFilesystemState;
import 'font/love_font_extra_bindings.dart' show installLoveFontExtraBindings;
import 'filesystem/love_filesystem_bindings.dart'
    show ensureLoveFilesystemRuntimeBindingsLoaded;
import 'filesystem/love_filesystem_enum_bindings.dart'
    show installLoveFilesystemEnumBindings;
import 'filesystem/love_filesystem_extra_bindings.dart'
    show installLoveFilesystemExtraBindings;
import 'filesystem/love_filesystem_package_loader.dart'
    show syncLoveFilesystemPackageInterop;
import 'graphics/love_graphics_enum_bindings.dart'
    show installLoveGraphicsEnumBindings;
import 'input/love_joystick_extra_bindings.dart'
    show installLoveJoystickExtraBindings;
import 'physics/love_physics_extra_bindings.dart'
    show installLovePhysicsExtraBindings;
import 'system/love_system_extra_bindings.dart'
    show installLoveSystemExtraBindings;
import 'window/love_window_extra_bindings.dart'
    show installLoveWindowExtraBindings;
import '../love_api_support.dart';
import 'love_runtime.dart';

part 'love_api_bindings/audio_bindings.dart';
part 'love_api_bindings/audio_effect_bindings.dart';
part 'love_api_bindings/audio_object_wrappers.dart';
part 'love_api_bindings/audio_recording_bindings.dart';
part 'love_api_bindings/binding_helpers.dart';
part 'love_api_bindings/core_bindings.dart';
part 'love_api_bindings/data_bindings.dart';
part 'love_api_bindings/data_object_wrappers.dart';
part 'love_api_bindings/error_bindings.dart';
part 'love_api_bindings/event_bindings.dart';
part 'love_api_bindings/font_bindings.dart';
part 'love_api_bindings/font_lua_number_string_helpers.dart';
part 'love_api_bindings/font_object_wrappers.dart';
part 'love_api_bindings/font_utf8_helpers.dart';
part 'love_api_bindings/graphics_advanced_state_bindings.dart';
part 'love_api_bindings/graphics_canvas_bindings.dart';
part 'love_api_bindings/graphics_draw_bindings.dart';
part 'love_api_bindings/graphics_environment_bindings.dart';
part 'love_api_bindings/graphics_extra_bindings.dart';
part 'love_api_bindings/graphics_layered_image_bindings.dart';
part 'love_api_bindings/graphics_mesh_bindings.dart';
part 'love_api_bindings/graphics_particle_system_bindings.dart';
part 'love_api_bindings/graphics_resource_bindings.dart';
part 'love_api_bindings/graphics_screenshot_bindings.dart';
part 'love_api_bindings/graphics_shader_source_bindings.dart';
part 'love_api_bindings/graphics_shader_bindings.dart';
part 'love_api_bindings/graphics_sprite_batch_bindings.dart';
part 'love_api_bindings/graphics_state_bindings.dart';
part 'love_api_bindings/graphics_misc_bindings.dart';
part 'love_api_bindings/graphics_transform_bindings.dart';
part 'love_api_bindings/graphics_video_bindings.dart';
part 'love_api_bindings/image_compressed_object_wrappers.dart';
part 'love_api_bindings/image_compressed_support.dart';
part 'love_api_bindings/image_bindings.dart';
part 'love_api_bindings/image_extra_bindings.dart';
part 'love_api_bindings/keyboard_bindings.dart';
part 'love_api_bindings/lifecycle_bindings.dart';
part 'love_api_bindings/math_bindings.dart';
part 'love_api_bindings/math_object_wrappers.dart';
part 'love_api_bindings/mouse_bindings.dart';
part 'love_api_bindings/mouse_object_wrappers.dart';
part 'love_api_bindings/object_wrappers.dart';
part 'love_api_bindings/particle_system_object_wrappers.dart';
part 'love_api_bindings/physics_bindings.dart';
part 'love_api_bindings/physics_callback_object_wrappers.dart';
part 'love_api_bindings/physics_contact_object_wrappers.dart';
part 'love_api_bindings/physics_contact_filter_object_wrappers.dart';
part 'love_api_bindings/physics_joint_bindings.dart';
part 'love_api_bindings/physics_joint_object_wrappers.dart';
part 'love_api_bindings/physics_object_wrappers.dart';
part 'love_api_bindings/physics_sync_callback_support.dart';
part 'love_api_bindings/joystick_object_wrappers.dart';
part 'love_api_bindings/joystick_bindings.dart';
part 'love_api_bindings/resource_source_helpers.dart';
part 'love_api_bindings/sprite_batch_object_wrappers.dart';
part 'love_api_bindings/sound_bindings.dart';
part 'love_api_bindings/sound_object_wrappers.dart';
part 'love_api_bindings/system_bindings.dart';
part 'love_api_bindings/thread_bindings.dart';
part 'love_api_bindings/thread_object_wrappers.dart';
part 'love_api_bindings/touch_bindings.dart';
part 'love_api_bindings/timer_bindings.dart';
part 'love_api_bindings/video_bindings.dart';
part 'love_api_bindings/video_object_wrappers.dart';
part 'love_api_bindings/window_bindings.dart';

bool _bindingsLoaded = false;

const String _loveFontObjectKey = '__love2d_font__';
const String _loveAudioSourceObjectKey = '__love2d_audio_source__';
const String _loveRecordingDeviceObjectKey = '__love2d_recording_device__';
const String _loveByteDataObjectKey = '__love2d_byte_data__';
const String _loveDataViewObjectKey = '__love2d_data_view__';
const String _loveCompressedDataObjectKey = '__love2d_compressed_data__';
const String _loveSoundDataObjectKey = '__love2d_sound_data__';
const String _loveDecoderObjectKey = '__love2d_decoder__';
const String _loveImageObjectKey = '__love2d_image__';
const String _loveCanvasObjectKey = '__love2d_canvas__';
const String _loveImageDataObjectKey = '__love2d_image_data__';
const String _loveCompressedImageDataObjectKey =
    '__love2d_compressed_image_data__';
const String _loveQuadObjectKey = '__love2d_quad__';
const String _loveMeshObjectKey = '__love2d_mesh__';
const String _loveSpriteBatchObjectKey = '__love2d_sprite_batch__';
const String _loveParticleSystemObjectKey = '__love2d_particle_system__';
const String _loveShaderObjectKey = '__love2d_shader__';
const String _loveTextObjectKey = '__love2d_text__';
const String _loveTransformObjectKey = '__love2d_transform__';
const String _loveJoystickObjectKey = '__love2d_joystick__';
const String _loveChannelObjectKey = '__love2d_channel__';
const String _loveThreadObjectKey = '__love2d_thread__';
const String _loveVideoObjectKey = '__love2d_video__';
const String _loveVideoStreamObjectKey = '__love2d_video_stream__';
const String _lovePhysicsWorldObjectKey = '__love2d_physics_world__';
const String _lovePhysicsBodyObjectKey = '__love2d_physics_body__';
const String _lovePhysicsFixtureObjectKey = '__love2d_physics_fixture__';
const String _lovePhysicsShapeObjectKey = '__love2d_physics_shape__';
const String _lovePhysicsJointObjectKey = '__love2d_physics_joint__';
const String _lovePhysicsContactObjectKey = '__love2d_physics_contact__';
const String _loveFilesystemFileDataObjectKeyCompat =
    '__love2d_filesystem_filedata__';
const String _loveFilesystemObjectTypeKeyCompat = '__love2d_filesystem_type__';
const String _loveFilesystemObjectHierarchyKeyCompat =
    '__love2d_filesystem_hierarchy__';

final Expando<Value> _loveFontWrapperCache = Expando<Value>(
  'love2dFontWrapper',
);
final Expando<Value> _loveAudioSourceWrapperCache = Expando<Value>(
  'love2dAudioSourceWrapper',
);
final Expando<Value> _loveRecordingDeviceWrapperCache = Expando<Value>(
  'love2dRecordingDeviceWrapper',
);
final Expando<Value> _loveByteDataWrapperCache = Expando<Value>(
  'love2dByteDataWrapper',
);
final Expando<Value> _loveDataViewWrapperCache = Expando<Value>(
  'love2dDataViewWrapper',
);
final Expando<Value> _loveCompressedDataWrapperCache = Expando<Value>(
  'love2dCompressedDataWrapper',
);
final Expando<Value> _loveSoundDataWrapperCache = Expando<Value>(
  'love2dSoundDataWrapper',
);
final Expando<Value> _loveDecoderWrapperCache = Expando<Value>(
  'love2dDecoderWrapper',
);
final Expando<Value> _loveImageWrapperCache = Expando<Value>(
  'love2dImageWrapper',
);
final Expando<Value> _loveCanvasWrapperCache = Expando<Value>(
  'love2dCanvasWrapper',
);
final Expando<Value> _loveImageDataWrapperCache = Expando<Value>(
  'love2dImageDataWrapper',
);
final Expando<Value> _loveCompressedImageDataWrapperCache = Expando<Value>(
  'love2dCompressedImageDataWrapper',
);
final Expando<Value> _loveQuadWrapperCache = Expando<Value>(
  'love2dQuadWrapper',
);
final Expando<Value> _loveMeshWrapperCache = Expando<Value>(
  'love2dMeshWrapper',
);
final Expando<Value> _loveSpriteBatchWrapperCache = Expando<Value>(
  'love2dSpriteBatchWrapper',
);
final Expando<Value> _loveParticleSystemWrapperCache = Expando<Value>(
  'love2dParticleSystemWrapper',
);
final Expando<Value> _loveShaderWrapperCache = Expando<Value>(
  'love2dShaderWrapper',
);
final Expando<Value> _loveTextWrapperCache = Expando<Value>(
  'love2dTextWrapper',
);
final Expando<Value> _loveTransformWrapperCache = Expando<Value>(
  'love2dTransformWrapper',
);
final Expando<Value> _loveJoystickWrapperCache = Expando<Value>(
  'love2dJoystickWrapper',
);
final Expando<Map<Object, Value>> _loveChannelWrapperCache =
    Expando<Map<Object, Value>>('love2dChannelWrapper');
final Expando<Map<Object, Value>> _loveThreadWrapperCache =
    Expando<Map<Object, Value>>('love2dThreadWrapper');
final Expando<Value> _loveVideoWrapperCache = Expando<Value>(
  'love2dVideoWrapper',
);
final Expando<Value> _loveVideoStreamWrapperCache = Expando<Value>(
  'love2dVideoStreamWrapper',
);
final Expando<Value> _lovePhysicsWorldWrapperCache = Expando<Value>(
  'love2dPhysicsWorldWrapper',
);
final Expando<Value> _lovePhysicsBodyWrapperCache = Expando<Value>(
  'love2dPhysicsBodyWrapper',
);
final Expando<Value> _lovePhysicsFixtureWrapperCache = Expando<Value>(
  'love2dPhysicsFixtureWrapper',
);
final Expando<Value> _lovePhysicsShapeWrapperCache = Expando<Value>(
  'love2dPhysicsShapeWrapper',
);
final Expando<Value> _lovePhysicsJointWrapperCache = Expando<Value>(
  'love2dPhysicsJointWrapper',
);
final Expando<Value> _lovePhysicsContactWrapperCache = Expando<Value>(
  'love2dPhysicsContactWrapper',
);
final Expando<Value> _loveFilesystemFileDataWrapperCache = Expando<Value>(
  'love2dFilesystemFileDataCompatWrapper',
);
final Expando<bool> _loveDataReleased = Expando<bool>('love2dDataReleased');
final Expando<bool> _loveDecoderReleased = Expando<bool>(
  'love2dDecoderReleased',
);
final Expando<bool> _loveFontReleased = Expando<bool>('love2dFontReleased');
final Expando<bool> _loveTextReleased = Expando<bool>('love2dTextReleased');
final Expando<bool> _loveChannelReleased = Expando<bool>(
  'love2dChannelReleased',
);
final Expando<bool> _loveThreadReleased = Expando<bool>('love2dThreadReleased');
final Expando<bool> _loveVideoReleased = Expando<bool>('love2dVideoReleased');
final Expando<bool> _loveVideoStreamReleased = Expando<bool>(
  'love2dVideoStreamReleased',
);
final Expando<bool> _lovePhysicsObjectReleased = Expando<bool>(
  'love2dPhysicsReleased',
);

void ensureLoveApiRuntimeBindingsLoaded() {
  if (_bindingsLoaded) {
    return;
  }

  _bindingsLoaded = true;
  loveApiBindingFactories.addAll(<String, LoveApiBindingFactory>{
    'love.audio.getActiveEffects': _bindAudioGetActiveEffects,
    'love.audio.getActiveSourceCount': _bindAudioGetActiveSourceCount,
    'love.audio.getDistanceModel': _bindAudioGetDistanceModel,
    'love.audio.getDopplerScale': _bindAudioGetDopplerScale,
    'love.audio.getEffect': _bindAudioGetEffect,
    'love.audio.getMaxSceneEffects': _bindAudioGetMaxSceneEffects,
    'love.audio.getMaxSourceEffects': _bindAudioGetMaxSourceEffects,
    'love.audio.getOrientation': _bindAudioGetOrientation,
    'love.audio.getPosition': _bindAudioGetPosition,
    'love.audio.getRecordingDevices': _bindAudioGetRecordingDevices,
    'love.audio.getVelocity': _bindAudioGetVelocity,
    'love.audio.getVolume': _bindAudioGetVolume,
    'love.audio.isEffectsSupported': _bindAudioIsEffectsSupported,
    'love.audio.newQueueableSource': _bindAudioNewQueueableSource,
    'love.audio.newSource': _bindAudioNewSource,
    'love.audio.pause': _bindAudioPause,
    'love.audio.play': _bindAudioPlay,
    'love.audio.setDistanceModel': _bindAudioSetDistanceModel,
    'love.audio.setDopplerScale': _bindAudioSetDopplerScale,
    'love.audio.setEffect': _bindAudioSetEffect,
    'love.audio.setMixWithSystem': _bindAudioSetMixWithSystem,
    'love.audio.setOrientation': _bindAudioSetOrientation,
    'love.audio.setPosition': _bindAudioSetPosition,
    'love.audio.setVelocity': _bindAudioSetVelocity,
    'love.audio.setVolume': _bindAudioSetVolume,
    'love.audio.stop': _bindAudioStop,
    'Source:getEffect': _bindSourceGetEffect,
    'Source:getFilter': _bindSourceGetFilter,
    'RecordingDevice:getBitDepth': _bindRecordingDeviceGetBitDepth,
    'RecordingDevice:getChannelCount': _bindRecordingDeviceGetChannelCount,
    'RecordingDevice:getData': _bindRecordingDeviceGetData,
    'RecordingDevice:getName': _bindRecordingDeviceGetName,
    'RecordingDevice:getSampleCount': _bindRecordingDeviceGetSampleCount,
    'RecordingDevice:getSampleRate': _bindRecordingDeviceGetSampleRate,
    'RecordingDevice:isRecording': _bindRecordingDeviceIsRecording,
    'RecordingDevice:start': _bindRecordingDeviceStart,
    'RecordingDevice:stop': _bindRecordingDeviceStop,
    'Source:play': _bindSourcePlay,
    'Source:queue': _bindSourceQueue,
    'Source:setEffect': _bindSourceSetEffect,
    'Source:setFilter': _bindSourceSetFilter,
    'Source:setLooping': _bindSourceSetLooping,
    'love.errorhandler': _bindLoveErrorHandler,
    'love.getVersion': _bindGetVersion,
    'love.hasDeprecationOutput': _bindHasDeprecationOutput,
    'love.isVersionCompatible': _bindIsVersionCompatible,
    'love.run': _bindLoveRun,
    'love.setDeprecationOutput': _bindSetDeprecationOutput,
    'love.data.compress': _bindDataCompress,
    'love.data.decode': _bindDataDecode,
    'love.data.decompress': _bindDataDecompress,
    'love.data.encode': _bindDataEncode,
    'love.data.getPackedSize': _bindDataGetPackedSize,
    'love.data.hash': _bindDataHash,
    'love.data.newByteData': _bindDataNewByteData,
    'love.data.newDataView': _bindDataNewDataView,
    'love.data.pack': _bindDataPack,
    'love.data.unpack': _bindDataUnpack,
    'Data:clone': _bindDataClone,
    'love.event.clear': _bindEventClear,
    'love.event.poll': _bindEventPoll,
    'love.event.pump': _bindEventPump,
    'love.event.push': _bindEventPush,
    'love.event.quit': _bindEventQuit,
    'love.font.newBMFontRasterizer': _bindFontNewBmFontRasterizer,
    'love.font.newGlyphData': _bindFontNewGlyphData,
    'love.font.newImageRasterizer': _bindFontNewImageRasterizer,
    'love.font.newRasterizer': _bindFontNewRasterizer,
    'love.font.newTrueTypeRasterizer': _bindFontNewTrueTypeRasterizer,
    'love.event.wait': _bindEventWait,
    'love.graphics.applyTransform': _bindGraphicsApplyTransform,
    'love.graphics.arc': _bindGraphicsArc,
    'love.graphics.clear': _bindGraphicsClear,
    'love.graphics.circle': _bindGraphicsCircle,
    'love.graphics.ellipse': _bindGraphicsEllipse,
    'love.graphics.getBackgroundColor': _bindGraphicsGetBackgroundColor,
    'love.graphics.getBlendMode': _bindGraphicsGetBlendMode,
    'love.graphics.getCanvas': _bindGraphicsGetCanvas,
    'love.graphics.getCanvasFormats': _bindGraphicsGetCanvasFormats,
    'love.graphics.getColor': _bindGraphicsGetColor,
    'love.graphics.getColorMask': _bindGraphicsGetColorMask,
    'love.graphics.getDPIScale': _bindGraphicsGetDpiScale,
    'love.graphics.getDefaultFilter': _bindGraphicsGetDefaultFilter,
    'love.graphics.getDefaultMipmapFilter': _bindGraphicsGetDefaultMipmapFilter,
    'love.graphics.getDimensions': _bindGraphicsGetDimensions,
    'love.graphics.getFont': _bindGraphicsGetFont,
    'love.graphics.getHeight': _bindGraphicsGetHeight,
    'love.graphics.getImageFormats': _bindGraphicsGetImageFormats,
    'love.graphics.getLineJoin': _bindGraphicsGetLineJoin,
    'love.graphics.getLineStyle': _bindGraphicsGetLineStyle,
    'love.graphics.getLineWidth': _bindGraphicsGetLineWidth,
    'love.graphics.getPixelDimensions': _bindGraphicsGetPixelDimensions,
    'love.graphics.getPixelHeight': _bindGraphicsGetPixelHeight,
    'love.graphics.getPixelWidth': _bindGraphicsGetPixelWidth,
    'love.graphics.getPointSize': _bindGraphicsGetPointSize,
    'love.graphics.getRendererInfo': _bindGraphicsGetRendererInfo,
    'love.graphics.getScissor': _bindGraphicsGetScissor,
    'love.graphics.getShader': _bindGraphicsGetShader,
    'love.graphics.getStackDepth': _bindGraphicsGetStackDepth,
    'love.graphics.getStats': _bindGraphicsGetStats,
    'love.graphics.getSupported': _bindGraphicsGetSupported,
    'love.graphics.getSystemLimits': _bindGraphicsGetSystemLimits,
    'love.graphics.getWidth': _bindGraphicsGetWidth,
    'love.graphics.intersectScissor': _bindGraphicsIntersectScissor,
    'love.graphics.inverseTransformPoint': _bindGraphicsInverseTransformPoint,
    'love.graphics.isActive': _bindGraphicsIsActive,
    'love.graphics.isCreated': _bindGraphicsIsCreated,
    'love.graphics.isGammaCorrect': _bindGraphicsIsGammaCorrect,
    'love.graphics.isWireframe': _bindGraphicsIsWireframe,
    'love.graphics.line': _bindGraphicsLine,
    'love.graphics.newArrayImage': _bindGraphicsNewArrayImage,
    'love.graphics.newCanvas': _bindGraphicsNewCanvas,
    'love.graphics.newCubeImage': _bindGraphicsNewCubeImage,
    'love.graphics.newFont': _bindGraphicsNewFont,
    'love.graphics.newImage': _bindGraphicsNewImage,
    'love.graphics.newImageFont': _bindGraphicsNewImageFont,
    'love.graphics.newMesh': _bindGraphicsNewMesh,
    'love.graphics.newVolumeImage': _bindGraphicsNewVolumeImage,
    'love.graphics.newParticleSystem': _bindGraphicsNewParticleSystem,
    'love.graphics.newSpriteBatch': _bindGraphicsNewSpriteBatch,
    'love.graphics.newShader': _bindGraphicsNewShader,
    'love.graphics.newText': _bindGraphicsNewText,
    'love.graphics.newQuad': _bindGraphicsNewQuad,
    'love.graphics.newVideo': _bindGraphicsNewVideo,
    'love.graphics.origin': _bindGraphicsOrigin,
    'love.graphics.present': _bindGraphicsPresent,
    'love.graphics.flushBatch': _bindGraphicsFlushBatch,
    'love.graphics.discard': _bindGraphicsDiscard,
    'love.graphics.getTextureTypes': _bindGraphicsGetTextureTypes,
    'love.graphics.pop': _bindGraphicsPop,
    'love.graphics.polygon': _bindGraphicsPolygon,
    'love.graphics.points': _bindGraphicsPoints,
    'love.graphics.draw': _bindGraphicsDraw,
    'love.graphics.drawInstanced': _bindGraphicsDrawInstanced,
    'love.graphics.drawLayer': _bindGraphicsDrawLayer,
    'love.graphics.captureScreenshot': _bindGraphicsCaptureScreenshot,
    'love.graphics.print': _bindGraphicsPrint,
    'love.graphics.printf': _bindGraphicsPrintf,
    'love.graphics.push': _bindGraphicsPush,
    'love.graphics.rectangle': _bindGraphicsRectangle,
    'love.graphics.reset': _bindGraphicsReset,
    'love.graphics.replaceTransform': _bindGraphicsReplaceTransform,
    'love.graphics.rotate': _bindGraphicsRotate,
    'love.graphics.scale': _bindGraphicsScale,
    'love.graphics.setBackgroundColor': _bindGraphicsSetBackgroundColor,
    'love.graphics.setBlendMode': _bindGraphicsSetBlendMode,
    'love.graphics.setDepthMode': _bindGraphicsSetDepthMode,
    'love.graphics.getDepthMode': _bindGraphicsGetDepthMode,
    'love.graphics.setStencilTest': _bindGraphicsSetStencilTest,
    'love.graphics.getStencilTest': _bindGraphicsGetStencilTest,
    'love.graphics.stencil': _bindGraphicsStencil,
    'love.graphics.setCanvas': _bindGraphicsSetCanvas,
    'love.graphics.setColor': _bindGraphicsSetColor,
    'love.graphics.setColorMask': _bindGraphicsSetColorMask,
    'love.graphics.setDefaultFilter': _bindGraphicsSetDefaultFilter,
    'love.graphics.setDefaultMipmapFilter': _bindGraphicsSetDefaultMipmapFilter,
    'love.graphics.setFont': _bindGraphicsSetFont,
    'love.graphics.setLineJoin': _bindGraphicsSetLineJoin,
    'love.graphics.setLineStyle': _bindGraphicsSetLineStyle,
    'love.graphics.setLineWidth': _bindGraphicsSetLineWidth,
    'love.graphics.setNewFont': _bindGraphicsSetNewFont,
    'love.graphics.setPointSize': _bindGraphicsSetPointSize,
    'love.graphics.setScissor': _bindGraphicsSetScissor,
    'love.graphics.setShader': _bindGraphicsSetShader,
    'love.graphics.setFrontFaceWinding': _bindGraphicsSetFrontFaceWinding,
    'love.graphics.getFrontFaceWinding': _bindGraphicsGetFrontFaceWinding,
    'love.graphics.setMeshCullMode': _bindGraphicsSetMeshCullMode,
    'love.graphics.getMeshCullMode': _bindGraphicsGetMeshCullMode,
    'love.graphics.setWireframe': _bindGraphicsSetWireframe,
    'love.graphics.validateShader': _bindGraphicsValidateShader,
    'love.graphics.shear': _bindGraphicsShear,
    'love.graphics.transformPoint': _bindGraphicsTransformPoint,
    'love.graphics.translate': _bindGraphicsTranslate,
    'love.image.isCompressed': _bindImageIsCompressed,
    'love.image.newCompressedData': _bindImageNewCompressedData,
    'love.image.newImageData': _bindImageNewImageData,
    'love.keyboard.getKeyFromScancode': _bindKeyboardGetKeyFromScancode,
    'love.keyboard.getScancodeFromKey': _bindKeyboardGetScancodeFromKey,
    'love.keyboard.hasKeyRepeat': _bindKeyboardHasKeyRepeat,
    'love.keyboard.hasScreenKeyboard': _bindKeyboardHasScreenKeyboard,
    'love.keyboard.hasTextInput': _bindKeyboardHasTextInput,
    'love.keyboard.isDown': _bindKeyboardIsDown,
    'love.keyboard.isScancodeDown': _bindKeyboardIsScancodeDown,
    'love.keyboard.setKeyRepeat': _bindKeyboardSetKeyRepeat,
    'love.keyboard.setTextInput': _bindKeyboardSetTextInput,
    'Mesh:setVertices': _bindMeshSetVertices,
    'love.math.colorFromBytes': _bindMathColorFromBytes,
    'love.math.colorToBytes': _bindMathColorToBytes,
    'love.math.gammaToLinear': _bindMathGammaToLinear,
    'love.math.getRandomSeed': _bindMathGetRandomSeed,
    'love.math.getRandomState': _bindMathGetRandomState,
    'love.math.isConvex': _bindMathIsConvex,
    'love.math.linearToGamma': _bindMathLinearToGamma,
    'love.math.newBezierCurve': _bindMathNewBezierCurve,
    'love.math.newRandomGenerator': _bindMathNewRandomGenerator,
    'love.math.newTransform': _bindMathNewTransform,
    'love.math.noise': _bindMathNoise,
    'love.math.random': _bindMathRandom,
    'love.math.randomNormal': _bindMathRandomNormal,
    'love.math.setRandomSeed': _bindMathSetRandomSeed,
    'love.math.setRandomState': _bindMathSetRandomState,
    'love.math.triangulate': _bindMathTriangulate,
    'love.mouse.getCursor': _bindMouseGetCursor,
    'love.mouse.getPosition': _bindMouseGetPosition,
    'love.mouse.getRelativeMode': _bindMouseGetRelativeMode,
    'love.mouse.getSystemCursor': _bindMouseGetSystemCursor,
    'love.mouse.getX': _bindMouseGetX,
    'love.mouse.getY': _bindMouseGetY,
    'love.mouse.isCursorSupported': _bindMouseIsCursorSupported,
    'love.mouse.isDown': _bindMouseIsDown,
    'love.mouse.isGrabbed': _bindMouseIsGrabbed,
    'love.mouse.isVisible': _bindMouseIsVisible,
    'love.mouse.newCursor': _bindMouseNewCursor,
    'love.mouse.setCursor': _bindMouseSetCursor,
    'love.mouse.setGrabbed': _bindMouseSetGrabbed,
    'love.mouse.setPosition': _bindMouseSetPosition,
    'love.mouse.setRelativeMode': _bindMouseSetRelativeMode,
    'love.mouse.setVisible': _bindMouseSetVisible,
    'love.mouse.setX': _bindMouseSetX,
    'love.mouse.setY': _bindMouseSetY,
    'love.physics.getDistance': _bindPhysicsGetDistance,
    'love.physics.getMeter': _bindPhysicsGetMeter,
    'love.physics.newBody': _bindPhysicsNewBody,
    'love.physics.newChainShape': _bindPhysicsNewChainShape,
    'love.physics.newCircleShape': _bindPhysicsNewCircleShape,
    'love.physics.newDistanceJoint': _bindPhysicsNewDistanceJoint,
    'love.physics.newEdgeShape': _bindPhysicsNewEdgeShape,
    'love.physics.newFrictionJoint': _bindPhysicsNewFrictionJoint,
    'love.physics.newFixture': _bindPhysicsNewFixture,
    'love.physics.newGearJoint': _bindPhysicsNewGearJoint,
    'love.physics.newMotorJoint': _bindPhysicsNewMotorJoint,
    'love.physics.newMouseJoint': _bindPhysicsNewMouseJoint,
    'love.physics.newPolygonShape': _bindPhysicsNewPolygonShape,
    'love.physics.newPrismaticJoint': _bindPhysicsNewPrismaticJoint,
    'love.physics.newPulleyJoint': _bindPhysicsNewPulleyJoint,
    'love.physics.newRectangleShape': _bindPhysicsNewRectangleShape,
    'love.physics.newRevoluteJoint': _bindPhysicsNewRevoluteJoint,
    'love.physics.newRopeJoint': _bindPhysicsNewRopeJoint,
    'love.physics.newWeldJoint': _bindPhysicsNewWeldJoint,
    'love.physics.newWheelJoint': _bindPhysicsNewWheelJoint,
    'love.physics.newWorld': _bindPhysicsNewWorld,
    'love.physics.setMeter': _bindPhysicsSetMeter,
    'love.joystick.getGamepadMappingString':
        _bindJoystickGetGamepadMappingString,
    'love.joystick.getJoystickCount': _bindJoystickGetJoystickCount,
    'love.joystick.getJoysticks': _bindJoystickGetJoysticks,
    'love.joystick.loadGamepadMappings': _bindJoystickLoadGamepadMappings,
    'love.joystick.saveGamepadMappings': _bindJoystickSaveGamepadMappings,
    'love.joystick.setGamepadMapping': _bindJoystickSetGamepadMapping,
    'Joystick:getAxes': _bindJoystickGetAxes,
    'Joystick:getAxis': _bindJoystickGetAxis,
    'Joystick:getAxisCount': _bindJoystickGetAxisCount,
    'Joystick:getButtonCount': _bindJoystickGetButtonCount,
    'Joystick:getDeviceInfo': _bindJoystickGetDeviceInfo,
    'Joystick:getGUID': _bindJoystickGetGuid,
    'Joystick:getGamepadAxis': _bindJoystickGetGamepadAxis,
    'Joystick:getGamepadMapping': _bindJoystickGetGamepadMapping,
    'Joystick:getGamepadMappingString':
        _bindJoystickGetGamepadMappingStringMethod,
    'Joystick:getHat': _bindJoystickGetHat,
    'Joystick:getHatCount': _bindJoystickGetHatCount,
    'Joystick:getID': _bindJoystickGetId,
    'Joystick:getName': _bindJoystickGetName,
    'Joystick:getVibration': _bindJoystickGetVibration,
    'Joystick:isConnected': _bindJoystickIsConnected,
    'Joystick:isDown': _bindJoystickIsDown,
    'Joystick:isGamepad': _bindJoystickIsGamepad,
    'Joystick:isGamepadDown': _bindJoystickIsGamepadDown,
    'Joystick:isVibrationSupported': _bindJoystickIsVibrationSupported,
    'Joystick:setVibration': _bindJoystickSetVibration,
    'Shader:send': _bindShaderSend,
    'love.sound.newDecoder': _bindSoundNewDecoder,
    'love.sound.newSoundData': _bindSoundNewSoundData,
    'love.system.getClipboardText': _bindSystemGetClipboardText,
    'love.system.getOS': _bindSystemGetOs,
    'love.system.getPowerInfo': _bindSystemGetPowerInfo,
    'love.system.getProcessorCount': _bindSystemGetProcessorCount,
    'love.system.hasBackgroundMusic': _bindSystemHasBackgroundMusic,
    'love.system.openURL': _bindSystemOpenUrl,
    'love.system.setClipboardText': _bindSystemSetClipboardText,
    'love.system.vibrate': _bindSystemVibrate,
    'love.thread.getChannel': _bindThreadGetChannel,
    'love.thread.newChannel': _bindThreadNewChannel,
    'love.thread.newThread': _bindThreadNewThread,
    'Channel:clear': _bindChannelClear,
    'Channel:demand': _bindChannelDemand,
    'Channel:getCount': _bindChannelGetCount,
    'Channel:hasRead': _bindChannelHasRead,
    'Channel:peek': _bindChannelPeek,
    'Channel:performAtomic': _bindChannelPerformAtomic,
    'Channel:pop': _bindChannelPop,
    'Channel:push': _bindChannelPush,
    'Channel:supply': _bindChannelSupply,
    'Thread:getError': _bindThreadGetError,
    'Thread:isRunning': _bindThreadIsRunning,
    'Thread:start': _bindThreadStart,
    'Thread:wait': _bindThreadWait,
    'love.video.newVideoStream': _bindVideoNewVideoStream,
    'love.touch.getPosition': _bindTouchGetPosition,
    'love.touch.getPressure': _bindTouchGetPressure,
    'love.touch.getTouches': _bindTouchGetTouches,
    'love.timer.getAverageDelta': _bindTimerGetAverageDelta,
    'love.timer.getDelta': _bindTimerGetDelta,
    'love.timer.getFPS': _bindTimerGetFps,
    'love.timer.getTime': _bindTimerGetTime,
    'love.timer.sleep': _bindTimerSleep,
    'love.timer.step': _bindTimerStep,
    'love.window.close': _bindWindowClose,
    'love.window.fromPixels': _bindWindowFromPixels,
    'love.window.getDPIScale': _bindWindowGetDpiScale,
    'love.window.getDesktopDimensions': _bindWindowGetDesktopDimensions,
    'love.window.getDisplayCount': _bindWindowGetDisplayCount,
    'love.window.getDisplayName': _bindWindowGetDisplayName,
    'love.window.getDisplayOrientation': _bindWindowGetDisplayOrientation,
    'love.window.getFullscreen': _bindWindowGetFullscreen,
    'love.window.getFullscreenModes': _bindWindowGetFullscreenModes,
    'love.window.getIcon': _bindWindowGetIcon,
    'love.window.hasFocus': _bindWindowHasFocus,
    'love.window.hasMouseFocus': _bindWindowHasMouseFocus,
    'love.window.getMode': _bindWindowGetMode,
    'love.window.getPosition': _bindWindowGetPosition,
    'love.window.getSafeArea': _bindWindowGetSafeArea,
    'love.window.getTitle': _bindWindowGetTitle,
    'love.window.getVSync': _bindWindowGetVsync,
    'love.window.isDisplaySleepEnabled': _bindWindowIsDisplaySleepEnabled,
    'love.window.isMaximized': _bindWindowIsMaximized,
    'love.window.isMinimized': _bindWindowIsMinimized,
    'love.window.isOpen': _bindWindowIsOpen,
    'love.window.isVisible': _bindWindowIsVisible,
    'love.window.maximize': _bindWindowMaximize,
    'love.window.minimize': _bindWindowMinimize,
    'love.window.requestAttention': _bindWindowRequestAttention,
    'love.window.restore': _bindWindowRestore,
    'love.window.showMessageBox': _bindWindowShowMessageBox,
    'love.window.setDisplaySleepEnabled': _bindWindowSetDisplaySleepEnabled,
    'love.window.setFullscreen': _bindWindowSetFullscreen,
    'love.window.setIcon': _bindWindowSetIcon,
    'love.window.setMode': _bindWindowSetMode,
    'love.window.setPosition': _bindWindowSetPosition,
    'love.window.setTitle': _bindWindowSetTitle,
    'love.window.setVSync': _bindWindowSetVsync,
    'love.window.toPixels': _bindWindowToPixels,
    'love.window.updateMode': _bindWindowUpdateMode,
  });
}
