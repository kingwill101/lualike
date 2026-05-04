library;

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'love_flame_audio.dart';
import 'love_flame_media_kit_audio.dart';
import '../love_runtime.dart';

/// The bundled TrueType font asset used for LOVE's default font fallback.
const String _loveDefaultTrueTypeFontAssetPath =
    'packages/love2d/third_party/love/extra/resources/Vera.ttf';

/// The cache key used for the bundled default TrueType font instance.
const String _loveDefaultTrueTypeFontCacheKey = '__love2d_default_vera__';
const int _loveFontMetricsCacheCapacity = 64;
const int _loveTextWidthCacheCapacity = 512;

/// A [LoveHost] implementation that maps LOVE services onto Flame and Flutter.
class LoveFlameHost<W extends World> implements LoveHost {
  /// Creates a Flame-backed LOVE host.
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
    LoveVideoFrameProviderFactory? videoFrameProviderFactory,
    void Function(LoveWindowMetrics metrics)? onWindowMetricsChanged,
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
       _audioBackendFactory = audioBackendFactory,
       _videoFrameProviderFactory = videoFrameProviderFactory,
       _onWindowMetricsChanged = onWindowMetricsChanged {
    // Use full Flutter asset keys so mounted LOVE source files can share one
    // Flame-owned image cache without relying on the default assets/images/ prefix.
    game.images = Images(prefix: '', bundle: _assetBundle);
  }

  /// The owning Flame game.
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
  final LinkedHashMap<({String family, double size}), _LoveFontMetrics>
  _fontMetricsCache =
      LinkedHashMap<({String family, double size}), _LoveFontMetrics>();
  final LinkedHashMap<({String family, double size, String text}), double>
  _textWidthCache =
      LinkedHashMap<({String family, double size, String text}), double>();
  LoveWindowMetrics? _windowOverride;
  Size? _hostViewportSize;
  List<LoveWindowDisplay>? _windowDisplaysOverride;
  bool _windowHasFocus;
  bool _windowHasMouseFocus;
  final LoveWindowMessageBoxHandler? _windowMessageBoxHandler;
  final AssetBundle _assetBundle;
  final LoveAudioBackendFactory? _audioBackendFactory;
  final LoveVideoFrameProviderFactory? _videoFrameProviderFactory;
  final void Function(LoveWindowMetrics metrics)? _onWindowMetricsChanged;

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

    if (!kIsWeb && sourceType == 'stream') {
      return LoveFlameMediaKitAudioSourceBackend.open(
        source: source,
        bytes: resolvedBytes,
        mimeType: mimeType,
      );
    }

    return LoveFlutterAudioSourceBackend(
      bytes: resolvedBytes,
      mimeType: mimeType,
    );
  }

  @override
  Future<LoveVideoFrameProvider?> createVideoFrameProvider(
    String source, {
    Uint8List? bytes,
    LoveVideoMetadata? metadata,
  }) async {
    final factory = _videoFrameProviderFactory;
    if (factory == null) {
      return null;
    }

    return factory(source, bytes: bytes, metadata: metadata);
  }

  @override
  Future<bool> setAudioMixWithSystem(bool mix) async => true;

  @override
  Future<LoveImage> loadImage(
    String source, {
    Uint8List? bytes,
    Map<dynamic, dynamic>? settings,
    String? assetKey,
  }) async {
    final cached = _images[source];
    if (cached != null) {
      return cached;
    }

    final encodedBytes = bytes == null
        ? await _loadImageBytes(assetKey ?? source)
        : ByteData.sublistView(bytes);
    if (encodedBytes == null) {
      throw StateError('No bundled Flutter image asset found for "$source".');
    }

    final image = assetKey == null
        ? await game.images.fetchOrGenerate(
            source,
            () => _decodeImage(encodedBytes),
          )
        : await _loadAssetKeyImage(assetKey, encodedBytes);
    final imageData = bytes == null && assetKey == null
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

  /// Preloads [assetKey] into Flame's image cache using the host decoder path.
  Future<void> prewarmImageAsset(String assetKey) async {
    if (game.images.containsKey(assetKey)) {
      return;
    }

    final encodedBytes = await _loadImageBytes(assetKey);
    if (encodedBytes == null) {
      throw StateError('No bundled Flutter image asset found for "$assetKey".');
    }

    final image = await _loadAssetKeyImage(assetKey, encodedBytes);
    if (game.images.containsKey(assetKey)) {
      return;
    }

    game.images.add(assetKey, image);
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
  Future<String?> validateRegisteredFragmentShaderAsset(String assetKey) async {
    try {
      await ui.FragmentProgram.fromAsset(assetKey);
      return null;
    } catch (error) {
      return 'Could not load Flutter fragment shader asset "$assetKey": $error';
    }
  }

  @override
  int get imageCount => _images.length;

  @visibleForTesting
  int get debugFontMetricsCacheSize => _fontMetricsCache.length;

  @visibleForTesting
  int get debugTextWidthCacheSize => _textWidthCache.length;

  @visibleForTesting
  int get debugTextWidthCacheCapacity => _loveTextWidthCacheCapacity;

  @visibleForTesting
  double debugMeasureTextWidth({
    required String family,
    required double size,
    required String text,
  }) => _measureTextWidth(family: family, size: size, text: text);

  @visibleForTesting
  LoveFontWrapResult debugWrapText({
    required String family,
    required double size,
    required String text,
    required double wrapLimit,
  }) => _wrapText(family: family, size: size, text: text, wrapLimit: wrapLimit);

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
    final hostViewportDimensions = _resolvedHostViewportDimensions();
    final override = _windowOverride;
    if (override != null) {
      return override.copyWith(
        dpiScale: _devicePixelRatio(override.dpiScale),
        desktopWidth: hostViewportDimensions?.width ?? override.desktopWidth,
        desktopHeight: hostViewportDimensions?.height ?? override.desktopHeight,
      );
    }

    final width = hostViewportDimensions?.width ?? 800;
    final height = hostViewportDimensions?.height ?? 600;
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
    _onWindowMetricsChanged?.call(windowMetrics);
  }

  /// Updates the current Flutter host viewport without mutating LOVE mode size.
  void updateHostViewportSize(Size size) {
    if (size.width <= 0 || size.height <= 0 || _hostViewportSize == size) {
      return;
    }

    _hostViewportSize = size;
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
    if (!rawValue.isFinite || rawValue <= 0) {
      return fallback;
    }
    return rawValue.round();
  }

  ({int width, int height})? _resolvedHostViewportDimensions() {
    final viewportSize = _hostViewportSize;
    if (viewportSize != null) {
      return (
        width: _gameDimension(viewportSize.width, 800),
        height: _gameDimension(viewportSize.height, 600),
      );
    }
    if (game.hasLayout) {
      return (
        width: _gameDimension(game.canvasSize.x, 800),
        height: _gameDimension(game.canvasSize.y, 600),
      );
    }
    return null;
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

  Future<ui.Image> _loadAssetKeyImage(
    String assetKey,
    ByteData encodedBytes,
  ) async {
    try {
      return await game.images.load(assetKey);
    } catch (_) {
      // A failed Flame load leaves behind a pending cache entry, so clear it
      // before seeding the cache from the bytes we already resolved.
      game.images.clear(assetKey);
      final image = await _decodeImage(encodedBytes);
      game.images.add(assetKey, image);
      return image;
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
    final cacheKey = (family: family, size: size);
    final cached = _readLruCache(_fontMetricsCache, cacheKey);
    if (cached != null) {
      return cached;
    }

    final painter = _textPainter(family: family, size: size, text: 'Hg')
      ..layout();
    final height = painter.height;
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    final metrics = (
      ascent: baseline,
      descent: (height - baseline).clamp(0.0, double.infinity),
      height: height,
    );
    _writeLruCache(
      _fontMetricsCache,
      cacheKey,
      metrics,
      _loveFontMetricsCacheCapacity,
    );
    return metrics;
  }

  double _measureTextWidth({
    required String family,
    required double size,
    required String text,
  }) {
    if (text.isEmpty) {
      return 0.0;
    }

    final cacheKey = (family: family, size: size, text: text);
    final cached = _readLruCache(_textWidthCache, cacheKey);
    if (cached != null) {
      return cached;
    }

    final painter = _textPainter(family: family, size: size, text: text)
      ..layout();
    final width = painter.width;
    _writeLruCache(
      _textWidthCache,
      cacheKey,
      width,
      _loveTextWidthCacheCapacity,
    );
    return width;
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
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
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

typedef _LoveFontMetrics = ({double ascent, double descent, double height});

T? _readLruCache<K, T>(LinkedHashMap<K, T> cache, K key) {
  if (!cache.containsKey(key)) {
    return null;
  }

  final value = cache.remove(key) as T;
  cache[key] = value;
  return value;
}

void _writeLruCache<K, T>(
  LinkedHashMap<K, T> cache,
  K key,
  T value,
  int capacity,
) {
  cache[key] = value;
  if (cache.length > capacity) {
    cache.remove(cache.keys.first);
  }
}
