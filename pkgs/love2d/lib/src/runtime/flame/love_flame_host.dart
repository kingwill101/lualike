library;

import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'dart:ui' as ui;

import 'love_flame_audio.dart';
import '../love_runtime.dart';

const String _loveDefaultTrueTypeFontAssetPath =
    'packages/love2d/third_party/love/extra/resources/Vera.ttf';
const String _loveDefaultTrueTypeFontCacheKey = '__love2d_default_vera__';

class LoveFlameHost<W extends World> implements LoveHost {
  LoveFlameHost({
    required this.game,
    AssetBundle? assetBundle,
    LoveClock? clock,
    LoveRandomGenerator? random,
    LoveKeyboardState? keyboard,
    LoveMouseState? mouse,
    LoveTouchState? touch,
    LoveJoystickManager? joysticks,
    LoveSystemState? system,
    LoveGraphicsFrame? graphics,
    LoveWindowMetrics? initialWindowMetrics,
    List<LoveWindowDisplay>? windowDisplays,
    bool windowHasFocus = false,
    bool windowHasMouseFocus = false,
    LoveWindowMessageBoxHandler? windowMessageBoxHandler,
    LoveAudioBackendFactory? audioBackendFactory,
  }) : _clock = clock ?? SystemLoveClock(),
       _random = random ?? LoveRandomGenerator(),
       _keyboard = keyboard ?? _defaultKeyboardState(),
       _mouse = mouse ?? LoveMouseState(),
       _touch = touch ?? LoveTouchState(),
       _joysticks = joysticks ?? LoveJoystickManager(),
       _system = system ?? _defaultSystemState(),
       _graphics = graphics ?? LoveGraphicsFrame(),
       _windowOverride = initialWindowMetrics,
       _windowDisplaysOverride = windowDisplays,
       _windowHasFocus = windowHasFocus,
       _windowHasMouseFocus = windowHasMouseFocus,
       _windowMessageBoxHandler = windowMessageBoxHandler,
       _assetBundle = assetBundle ?? rootBundle,
       _audioBackendFactory = audioBackendFactory;

  final FlameGame<W> game;
  final LoveClock _clock;
  final LoveRandomGenerator _random;
  final LoveKeyboardState _keyboard;
  final LoveMouseState _mouse;
  final LoveTouchState _touch;
  final LoveJoystickManager _joysticks;
  final LoveSystemState _system;
  final LoveGraphicsFrame _graphics;
  final Map<String, LoveImage> _images = <String, LoveImage>{};
  final Map<String, Future<String>> _fontFamilies = <String, Future<String>>{};
  LoveWindowMetrics? _windowOverride;
  List<LoveWindowDisplay>? _windowDisplaysOverride;
  bool _windowHasFocus;
  bool _windowHasMouseFocus;
  final LoveWindowMessageBoxHandler? _windowMessageBoxHandler;
  final AssetBundle _assetBundle;
  final LoveAudioBackendFactory? _audioBackendFactory;

  @override
  LoveClock get clock => _clock;

  @override
  bool get usesExternalFrameLoop => true;

  @override
  LoveRandomGenerator get random => _random;

  @override
  LoveKeyboardState get keyboard => _keyboard;

  @override
  LoveMouseState get mouse => _mouse;

  @override
  LoveTouchState get touch => _touch;

  @override
  LoveJoystickManager get joysticks => _joysticks;

  @override
  LoveSystemState get system => _system;

  @override
  LoveGraphicsFrame get graphics => _graphics;

  @override
  bool get requiresMountedFilesystemForRelativeResourcePaths => true;

  @override
  Future<LoveAudioSourceBackend> createAudioSourceBackend(
    String source, {
    required String sourceType,
    Uint8List? bytes,
    String? mimeType,
  }) async {
    final audioBackendFactory = _audioBackendFactory;
    if (audioBackendFactory != null) {
      return audioBackendFactory(
        source,
        sourceType: sourceType,
        bytes: bytes,
        mimeType: mimeType,
      );
    }

    final resolvedBytes = bytes ?? await _loadAudioBytes(source);
    if (resolvedBytes == null) {
      throw UnsupportedError('No audio asset loader configured for "$source"');
    }

    return LoveFlutterAudioSourceBackend(
      bytes: resolvedBytes,
      mimeType: mimeType,
    );
  }

  @override
  Future<LoveImage> loadImage(
    String source, {
    Uint8List? bytes,
    Map<dynamic, dynamic>? settings,
  }) async {
    final cached = _images[source];
    if (cached != null) {
      return cached;
    }

    final encodedBytes = bytes == null
        ? await _loadImageBytes(source)
        : ByteData.sublistView(bytes);
    if (encodedBytes == null && !_canUseFlameImageCache(source)) {
      throw StateError('No bundled Flutter image asset found for "$source".');
    }

    final image = encodedBytes == null
        ? await game.images.load(_normalizedFlameImageKey(source))
        : await _decodeImage(encodedBytes);
    final imageData = encodedBytes == null
        ? await _decodeImageData(image)
        : LoveImageData.decodeEncodedBytes(
            bytes: encodedBytes.buffer.asUint8List(
              encodedBytes.offsetInBytes,
              encodedBytes.lengthInBytes,
            ),
            source: source,
          );
    final resolved = LoveImage(
      source: source,
      width: image.width,
      height: image.height,
      imageData: imageData,
      nativeImage: image,
    );
    _images[source] = resolved;
    return resolved;
  }

  @override
  Future<LoveFont?> loadTrueTypeFont(
    String source, {
    required Uint8List bytes,
    required double size,
    required String hinting,
    required double dpiScale,
    required LoveGraphicsDefaultFilter defaultFilter,
  }) async {
    return _buildTrueTypeFont(
      cacheKey: source,
      source: source,
      bytes: bytes,
      size: size,
      hinting: hinting,
      dpiScale: dpiScale,
      defaultFilter: defaultFilter,
    );
  }

  @override
  Future<LoveFont?> loadDefaultTrueTypeFont({
    required double size,
    required String hinting,
    required double dpiScale,
    required LoveGraphicsDefaultFilter defaultFilter,
  }) async {
    final bytes = await loadDefaultTrueTypeFontBytes();
    if (bytes == null) {
      return null;
    }

    return _buildTrueTypeFont(
      cacheKey: _loveDefaultTrueTypeFontCacheKey,
      source: null,
      bytes: bytes,
      size: size,
      hinting: hinting,
      dpiScale: dpiScale,
      defaultFilter: defaultFilter,
    );
  }

  @override
  Future<Uint8List?> loadDefaultTrueTypeFontBytes() async {
    try {
      final data = await _assetBundle.load(_loveDefaultTrueTypeFontAssetPath);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  @override
  int get imageCount => _images.length;

  @override
  String get rendererName => 'LuaLike Flutter';

  @override
  String get rendererVersion => loveVersionString;

  @override
  String get rendererVendor => 'LuaLike';

  @override
  String get rendererDevice => game.runtimeType.toString();

  @override
  LoveWindowMetrics get windowMetrics {
    final override = _windowOverride;
    if (override != null) {
      return override.copyWith(dpiScale: _devicePixelRatio(override.dpiScale));
    }

    final width = _gameDimension(game.canvasSize.x, 800);
    final height = _gameDimension(game.canvasSize.y, 600);
    return LoveWindowMetrics(
      width: width,
      height: height,
      desktopWidth: width,
      desktopHeight: height,
      dpiScale: _devicePixelRatio(1.0),
    );
  }

  @override
  set windowMetrics(LoveWindowMetrics value) {
    _windowOverride = value;
  }

  @override
  List<LoveWindowDisplay> get windowDisplays =>
      _windowDisplaysOverride ??
      loveDefaultWindowDisplaysForMetrics(windowMetrics);

  @override
  set windowDisplays(List<LoveWindowDisplay> value) {
    _windowDisplaysOverride = List<LoveWindowDisplay>.unmodifiable(value);
  }

  @override
  bool get windowHasFocus => _windowHasFocus;

  @override
  set windowHasFocus(bool value) {
    _windowHasFocus = value;
  }

  @override
  bool get windowHasMouseFocus => _windowHasMouseFocus;

  @override
  set windowHasMouseFocus(bool value) {
    _windowHasMouseFocus = value;
  }

  @override
  Future<LoveWindowMessageBoxResponse> showWindowMessageBox(
    LoveWindowMessageBoxData data,
  ) async {
    final handler = _windowMessageBoxHandler;
    if (handler != null) {
      return await handler(data);
    }

    return LoveWindowMessageBoxResponse(
      success: true,
      pressedButtonIndex: data.buttons.isEmpty ? 0 : 1,
    );
  }

  double _devicePixelRatio(double fallback) {
    final context = game.buildContext;
    if (context == null) {
      return fallback;
    }

    return View.maybeOf(context)?.devicePixelRatio ?? fallback;
  }

  int _gameDimension(double rawValue, int fallback) {
    return rawValue > 0 ? rawValue.round() : fallback;
  }

  Future<ByteData?> _loadImageBytes(String source) async {
    try {
      return await _assetBundle.load(source);
    } on FlutterError {
      final normalized = _normalizedFlameImageKey(source);
      if (normalized == source) {
        return null;
      }

      try {
        return await _assetBundle.load(normalized);
      } on FlutterError {
        return null;
      }
    }
  }

  Future<Uint8List?> _loadAudioBytes(String source) async {
    try {
      final data = await _assetBundle.load(source);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on FlutterError {
      return null;
    }
  }

  Future<ui.Image> _decodeImage(ByteData data) async {
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  Future<LoveImageData?> _decodeImageData(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      return null;
    }

    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    return LoveImageData.fromRgbaBytes(
      width: image.width,
      height: image.height,
      bytes: bytes,
    );
  }

  Future<String> _loadFontFamily(String source, Uint8List bytes) async {
    final family = 'love2d_${source.hashCode.abs()}';
    final loader = FontLoader(family)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    return family;
  }

  Future<LoveFont> _buildTrueTypeFont({
    required String cacheKey,
    required String? source,
    required Uint8List bytes,
    required double size,
    required String hinting,
    required double dpiScale,
    required LoveGraphicsDefaultFilter defaultFilter,
  }) async {
    final family = await _fontFamilies.putIfAbsent(
      cacheKey,
      () => _loadFontFamily(cacheKey, bytes),
    );
    final fontMetrics = _measureFontMetrics(family: family, size: size);
    final metadata = parseLoveTrueTypeFontMetadata(bytes);
    final resolvedDpiScale = dpiScale <= 0 ? 1.0 : dpiScale;
    final pixelHeight = math.max(1, (size * dpiScale).round());
    final glyphAdvance = metadata?.logicalMaxAdvance(size, dpiScale: dpiScale);
    final glyphAdvances = metadata?.logicalGlyphAdvances(
      size,
      dpiScale: dpiScale,
    );
    final glyphKernings = metadata?.logicalKerning(size, dpiScale: dpiScale);
    final missingGlyphAdvance = switch (metadata?.pixelMaxAdvance(
      pixelHeight,
    )) {
      final pixelAdvance? => pixelAdvance / resolvedDpiScale,
      null => null,
    };
    final syntheticTabAdvance = switch (metadata?.pixelGlyphAdvance(
      0x20,
      pixelHeight,
    )) {
      final pixelAdvance?
          when !metadata!.containsCodepoint(0x09) && pixelAdvance > 0 =>
        (pixelAdvance * 4) / resolvedDpiScale,
      _ => null,
    };

    return LoveFont(
      size: size,
      family: family,
      source: source,
      fontType: LoveFont.trueTypeFontType,
      glyphAdvance: glyphAdvance,
      glyphAdvances: glyphAdvances,
      glyphKernings: glyphKernings,
      hinting: hinting,
      dpiScale: dpiScale,
      heightOverride: fontMetrics.height,
      ascentOverride: fontMetrics.ascent,
      descentOverride: fontMetrics.descent,
      missingGlyphAdvance: missingGlyphAdvance,
      syntheticTabAdvance: syntheticTabAdvance,
      filter: defaultFilter,
      measureWidthCallback: (text) =>
          _measureTextWidth(family: family, size: size, text: text),
      wrapTextCallback: (text, wrapLimit) => _wrapText(
        family: family,
        size: size,
        text: text,
        wrapLimit: wrapLimit,
      ),
      supportsCodepointCallback: metadata?.supportsCodepointCallback,
    );
  }

  ({double ascent, double descent, double height}) _measureFontMetrics({
    required String family,
    required double size,
  }) {
    final painter = _textPainter(family: family, size: size, text: 'Hg')
      ..layout();
    final height = painter.height;
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    return (
      ascent: baseline,
      descent: (height - baseline).clamp(0.0, double.infinity),
      height: height,
    );
  }

  double _measureTextWidth({
    required String family,
    required double size,
    required String text,
  }) {
    if (text.isEmpty) {
      return 0.0;
    }

    final painter = _textPainter(family: family, size: size, text: text)
      ..layout();
    return painter.width;
  }

  LoveFontWrapResult _wrapText({
    required String family,
    required double size,
    required String text,
    required double wrapLimit,
  }) {
    double measureWidth(String segment) {
      return _measureTextWidth(family: family, size: size, text: segment);
    }

    double advanceForCodepoint(int codepoint) {
      return measureWidth(String.fromCharCode(codepoint));
    }

    double kerningForPair(int leftGlyph, int rightGlyph) {
      final left = String.fromCharCode(leftGlyph);
      final right = String.fromCharCode(rightGlyph);
      return measureWidth('$left$right') -
          measureWidth(left) -
          measureWidth(right);
    }

    double charWidthForLayout(int? previous, int codepoint) {
      final advance = advanceForCodepoint(codepoint);
      if (previous == null) {
        return advance;
      }
      return advance + kerningForPair(previous, codepoint);
    }

    final codepoints = text.runes.toList(growable: false);
    final lines = <String>[];
    final widths = <double>[];
    final lineCodepoints = <int>[];

    var width = 0.0;
    var widthBeforeLastSpace = 0.0;
    var widthOfTrailingSpace = 0.0;
    int? previous;
    var lastSpaceIndex = -1;

    var index = 0;
    while (index < codepoints.length) {
      final codepoint = codepoints[index];

      if (codepoint == 0x0a) {
        lines.add(String.fromCharCodes(lineCodepoints));
        widths.add(width - widthOfTrailingSpace);

        width = 0.0;
        widthBeforeLastSpace = 0.0;
        widthOfTrailingSpace = 0.0;
        previous = null;
        lastSpaceIndex = -1;
        lineCodepoints.clear();
        index++;
        continue;
      }

      if (codepoint == 0x0d) {
        index++;
        continue;
      }

      final charWidth = charWidthForLayout(previous, codepoint);
      final newWidth = width + charWidth;

      if (codepoint != 0x20 && newWidth > wrapLimit) {
        if (lineCodepoints.isEmpty) {
          index++;
        } else if (lastSpaceIndex != -1) {
          while (lineCodepoints.isNotEmpty && lineCodepoints.last != 0x20) {
            lineCodepoints.removeLast();
          }
          width = widthBeforeLastSpace;
          index = lastSpaceIndex + 1;
        }

        lines.add(String.fromCharCodes(lineCodepoints));
        widths.add(width);

        width = 0.0;
        widthBeforeLastSpace = 0.0;
        widthOfTrailingSpace = 0.0;
        previous = null;
        lastSpaceIndex = -1;
        lineCodepoints.clear();
        continue;
      }

      if (previous != 0x20 && codepoint == 0x20) {
        widthBeforeLastSpace = width;
      }

      width = newWidth;
      previous = codepoint;
      lineCodepoints.add(codepoint);

      if (codepoint == 0x20) {
        lastSpaceIndex = index;
        widthOfTrailingSpace += charWidth;
      } else {
        widthOfTrailingSpace = 0.0;
      }

      index++;
    }

    lines.add(String.fromCharCodes(lineCodepoints));
    widths.add(width - widthOfTrailingSpace);

    var maxWidth = 0.0;
    for (final lineWidth in widths) {
      maxWidth = math.max(maxWidth, lineWidth);
    }
    return (width: maxWidth, lines: lines);
  }

  TextPainter _textPainter({
    required String family,
    required double size,
    required String text,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, fontFamily: family, height: 1.0),
      ),
      textDirection: TextDirection.ltr,
      maxLines: null,
    );
  }

  String _normalizedFlameImageKey(String source) {
    if (source.startsWith('assets/images/')) {
      return source.substring('assets/images/'.length);
    }

    if (source.startsWith('images/')) {
      return source.substring('images/'.length);
    }

    return source;
  }

  bool _canUseFlameImageCache(String source) {
    return !source.contains('/') ||
        source.startsWith('images/') ||
        source.startsWith('assets/images/');
  }

  static LoveSystemState _defaultSystemState() {
    return LoveSystemState(
      os: _defaultLoveOs(),
      clipboardReadHandler: _readClipboardText,
      clipboardWriteHandler: _writeClipboardText,
      vibrateHandler: _vibrateDevice,
    );
  }

  static LoveKeyboardState _defaultKeyboardState() {
    final screenKeyboardSupported = !kIsWeb && _platformHasScreenKeyboard();
    return LoveKeyboardState(
      screenKeyboardSupported: screenKeyboardSupported,
      textInputEnabled: _defaultTextInputEnabled(),
    );
  }

  static bool _platformHasScreenKeyboard() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
  }

  static bool _defaultTextInputEnabled() {
    if (kIsWeb) {
      return true;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => false,
      TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux =>
        true,
      _ => true,
    };
  }

  static String _defaultLoveOs() {
    if (kIsWeb) {
      return 'Unknown';
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.macOS => 'OS X',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.linux => 'Linux',
      _ => 'Unknown',
    };
  }

  static Future<String> _readClipboardText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text ?? '';
  }

  static Future<void> _writeClipboardText(String text) {
    return Clipboard.setData(ClipboardData(text: text));
  }

  static Future<void> _vibrateDevice(double seconds) {
    return HapticFeedback.vibrate();
  }
}
