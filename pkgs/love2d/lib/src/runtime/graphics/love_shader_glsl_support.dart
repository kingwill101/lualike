part of '../love_runtime.dart';

/// Reports a failure while translating LOVE shader code to GLSL.
final class LoveShaderTranslationException implements Exception {
  /// Creates a shader translation exception with [message].
  const LoveShaderTranslationException(this.message);

  /// The human-readable translation failure message.
  final String message;

  @override
  String toString() => message;
}

/// The vertex and pixel sources selected from a LOVE shader definition.
final class LoveShaderStageSelection {
  /// Creates a selected pair of shader stages.
  const LoveShaderStageSelection({
    this.vertexSource,
    this.pixelSource,
    this.customPixel = false,
    this.multiCanvas = false,
  });

  /// The selected vertex-stage source, if one was found.
  final String? vertexSource;

  /// The selected pixel-stage source, if one was found.
  final String? pixelSource;

  /// Whether the pixel stage uses LOVE's custom `void effect()` form.
  final bool customPixel;

  /// Whether the pixel stage references multi-canvas output.
  final bool multiCanvas;

  /// Whether at least one shader stage was identified.
  bool get hasStage => vertexSource != null || pixelSource != null;
}

/// The translated GLSL source produced for a shader pair.
final class LoveShaderGlslTranslation {
  /// Creates a translated shader-code pair.
  const LoveShaderGlslTranslation({this.vertexCode, this.pixelCode});

  /// The translated vertex shader code, if one was generated.
  final String? vertexCode;

  /// The translated pixel shader code, if one was generated.
  final String? pixelCode;
}

/// The inferred pixel-stage characteristics of one source string.
final class _LoveShaderPixelSelection {
  /// Creates a pixel-stage selection result.
  const _LoveShaderPixelSelection({
    required this.isPixel,
    this.customPixel = false,
    this.multiCanvas = false,
  });

  /// Whether the source contains a pixel-stage entry point.
  final bool isPixel;

  /// Whether the source uses the custom `void effect()` entry point.
  final bool customPixel;

  /// Whether the source refers to multi-canvas outputs.
  final bool multiCanvas;
}

/// The GLSL version directives used for LOVE shader targets.
const Map<String, Map<bool, String>> _loveShaderVersionDirectives =
    <String, Map<bool, String>>{
      'glsl1': <bool, String>{false: '#version 120', true: '#version 100'},
      'glsl3': <bool, String>{
        false: '#version 330 core',
        true: '#version 300 es',
      },
    };

/// Shared syntax aliases and extension enables inserted into every shader.
const String _loveShaderSyntaxPreamble = '''
#if !defined(GL_ES) && __VERSION__ < 140
	#define lowp
	#define mediump
	#define highp
#endif
#if defined(VERTEX) || __VERSION__ > 100 || defined(GL_FRAGMENT_PRECISION_HIGH)
	#define LOVE_HIGHP_OR_MEDIUMP highp
#else
	#define LOVE_HIGHP_OR_MEDIUMP mediump
#endif
#define number float
#define Image sampler2D
#define ArrayImage sampler2DArray
#define CubeImage samplerCube
#define VolumeImage sampler3D
#if __VERSION__ >= 300 && !defined(LOVE_GLSL1_ON_GLSL3)
	#define DepthImage sampler2DShadow
	#define DepthArrayImage sampler2DArrayShadow
	#define DepthCubeImage samplerCubeShadow
#endif
#define extern uniform
#if defined(GL_EXT_texture_array) && (!defined(GL_ES) || __VERSION__ > 100 || defined(GL_OES_gpu_shader5))
// Only used when !GLSLES1 to work around Ouya driver bug. But we still want it
// enabled for glslang validation when glsl 1-on-3 is used, so also enable it if
// OES_gpu_shader5 exists.
#define LOVE_EXT_TEXTURE_ARRAY_ENABLED
#extension GL_EXT_texture_array : enable
#endif
#ifdef GL_OES_texture_3D
#extension GL_OES_texture_3D : enable
#endif
#ifdef GL_OES_standard_derivatives
#extension GL_OES_standard_derivatives : enable
#endif
''';

/// Shared built-in uniforms and compatibility aliases for both stages.
const String _loveShaderSharedUniforms = '''
// According to the GLSL ES 1.0 spec, uniform precision must match between stages,
// but we can't guarantee that highp is always supported in fragment shaders...
// We *really* don't want to use mediump for these in vertex shaders though.
uniform LOVE_HIGHP_OR_MEDIUMP mat4 ViewSpaceFromLocal;
uniform LOVE_HIGHP_OR_MEDIUMP mat4 ClipSpaceFromView;
uniform LOVE_HIGHP_OR_MEDIUMP mat4 ClipSpaceFromLocal;
uniform LOVE_HIGHP_OR_MEDIUMP mat3 ViewNormalFromLocal;
uniform LOVE_HIGHP_OR_MEDIUMP vec4 love_ScreenSize;

// Compatibility
#define TransformMatrix ViewSpaceFromLocal
#define ProjectionMatrix ClipSpaceFromView
#define TransformProjectionMatrix ClipSpaceFromLocal
#define NormalMatrix ViewNormalFromLocal
''';

/// Shared helper functions inserted into both translated shader stages.
const String _loveShaderSharedFunctions = '''
#ifdef GL_ES
	#if __VERSION__ >= 300 || defined(LOVE_EXT_TEXTURE_ARRAY_ENABLED)
		precision lowp sampler2DArray;
	#endif
	#if __VERSION__ >= 300 || defined(GL_OES_texture_3D)
		precision lowp sampler3D;
	#endif
	#if __VERSION__ >= 300 && !defined(LOVE_GLSL1_ON_GLSL3)
		precision lowp sampler2DShadow;
		precision lowp samplerCubeShadow;
		precision lowp sampler2DArrayShadow;
	#endif
#endif

#if __VERSION__ >= 130 && !defined(LOVE_GLSL1_ON_GLSL3)
	#define Texel texture
#else
	#if __VERSION__ >= 130
		#define texture2D Texel
		#define texture3D Texel
		#define textureCube Texel
		#define texture2DArray Texel
		#define love_texture2D texture
		#define love_texture3D texture
		#define love_textureCube texture
		#define love_texture2DArray texture
	#else
		#define love_texture2D texture2D
		#define love_texture3D texture3D
		#define love_textureCube textureCube
		#define love_texture2DArray texture2DArray
	#endif
	vec4 Texel(sampler2D s, vec2 c) { return love_texture2D(s, c); }
	vec4 Texel(samplerCube s, vec3 c) { return love_textureCube(s, c); }
	#if __VERSION__ > 100 || defined(GL_OES_texture_3D)
		vec4 Texel(sampler3D s, vec3 c) { return love_texture3D(s, c); }
	#endif
	#if __VERSION__ >= 130 || defined(LOVE_EXT_TEXTURE_ARRAY_ENABLED)
		vec4 Texel(sampler2DArray s, vec3 c) { return love_texture2DArray(s, c); }
	#endif
	#ifdef PIXEL
		vec4 Texel(sampler2D s, vec2 c, float b) { return love_texture2D(s, c, b); }
		vec4 Texel(samplerCube s, vec3 c, float b) { return love_textureCube(s, c, b); }
		#if __VERSION__ > 100 || defined(GL_OES_texture_3D)
			vec4 Texel(sampler3D s, vec3 c, float b) { return love_texture3D(s, c, b); }
		#endif
		#if __VERSION__ >= 130 || defined(LOVE_EXT_TEXTURE_ARRAY_ENABLED)
			vec4 Texel(sampler2DArray s, vec3 c, float b) { return love_texture2DArray(s, c, b); }
		#endif
	#endif
	#define texture love_texture
#endif

float gammaToLinearPrecise(float c) {
	return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}
vec3 gammaToLinearPrecise(vec3 c) {
	bvec3 leq = lessThanEqual(c, vec3(0.04045));
	c.r = leq.r ? c.r / 12.92 : pow((c.r + 0.055) / 1.055, 2.4);
	c.g = leq.g ? c.g / 12.92 : pow((c.g + 0.055) / 1.055, 2.4);
	c.b = leq.b ? c.b / 12.92 : pow((c.b + 0.055) / 1.055, 2.4);
	return c;
}
vec4 gammaToLinearPrecise(vec4 c) { return vec4(gammaToLinearPrecise(c.rgb), c.a); }
float linearToGammaPrecise(float c) {
	return c < 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}
vec3 linearToGammaPrecise(vec3 c) {
	bvec3 lt = lessThanEqual(c, vec3(0.0031308));
	c.r = lt.r ? c.r * 12.92 : 1.055 * pow(c.r, 1.0 / 2.4) - 0.055;
	c.g = lt.g ? c.g * 12.92 : 1.055 * pow(c.g, 1.0 / 2.4) - 0.055;
	c.b = lt.b ? c.b * 12.92 : 1.055 * pow(c.b, 1.0 / 2.4) - 0.055;
	return c;
}
vec4 linearToGammaPrecise(vec4 c) { return vec4(linearToGammaPrecise(c.rgb), c.a); }

// http://chilliant.blogspot.com.au/2012/08/srgb-approximations-for-hlsl.html?m=1

mediump float gammaToLinearFast(mediump float c) { return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878); }
mediump vec3 gammaToLinearFast(mediump vec3 c) { return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878); }
mediump vec4 gammaToLinearFast(mediump vec4 c) { return vec4(gammaToLinearFast(c.rgb), c.a); }

mediump float linearToGammaFast(mediump float c) { return max(1.055 * pow(max(c, 0.0), 0.41666666) - 0.055, 0.0); }
mediump vec3 linearToGammaFast(mediump vec3 c) { return max(1.055 * pow(max(c, vec3(0.0)), vec3(0.41666666)) - 0.055, vec3(0.0)); }
mediump vec4 linearToGammaFast(mediump vec4 c) { return vec4(linearToGammaFast(c.rgb), c.a); }

#define gammaToLinear gammaToLinearFast
#define linearToGamma linearToGammaFast

#ifdef LOVE_GAMMA_CORRECT
	#define gammaCorrectColor gammaToLinear
	#define unGammaCorrectColor linearToGamma
	#define gammaCorrectColorPrecise gammaToLinearPrecise
	#define unGammaCorrectColorPrecise linearToGammaPrecise
	#define gammaCorrectColorFast gammaToLinearFast
	#define unGammaCorrectColorFast linearToGammaFast
#else
	#define gammaCorrectColor
	#define unGammaCorrectColor
	#define gammaCorrectColorPrecise
	#define unGammaCorrectColorPrecise
	#define gammaCorrectColorFast
	#define unGammaCorrectColorFast
#endif
''';

/// The fixed header prepended to translated vertex shaders.
const String _loveShaderVertexHeader = '''
#define love_Position gl_Position

#if __VERSION__ >= 130
	#define attribute in
	#define varying out
	#ifndef LOVE_GLSL1_ON_GLSL3
		#define love_VertexID gl_VertexID
		#define love_InstanceID gl_InstanceID
	#endif
#endif

#ifdef GL_ES
	uniform mediump float love_PointSize;
#endif
''';

/// Vertex-stage helper functions inserted before user code.
const String _loveShaderVertexFunctions = '''
void setPointSize() {
#ifdef GL_ES
	gl_PointSize = love_PointSize;
#endif
}
''';

/// The default vertex-stage main wrapper used by translated shaders.
const String _loveShaderVertexMain = '''
attribute vec4 VertexPosition;
attribute vec4 VertexTexCoord;
attribute vec4 VertexColor;
attribute vec4 ConstantColor;

varying vec4 VaryingTexCoord;
varying vec4 VaryingColor;

vec4 position(mat4 clipSpaceFromLocal, vec4 localPosition);

void main() {
	VaryingTexCoord = VertexTexCoord;
	VaryingColor = gammaCorrectColor(VertexColor) * ConstantColor;
	setPointSize();
	love_Position = position(ClipSpaceFromLocal, VertexPosition);
}
''';

/// The fixed header prepended to translated pixel shaders.
const String _loveShaderPixelHeader = '''
#ifdef GL_ES
	precision mediump float;
#endif

#define love_MaxCanvases gl_MaxDrawBuffers

#if __VERSION__ >= 130
	#define varying in
	// Some drivers seem to make the pixel shader do more work when multiple
	// pixel shader outputs are defined, even when only one is actually used.
	// TODO: We should use reflection or something instead of this, to determine
	// how many outputs are actually used in the shader code.
	#ifdef LOVE_MULTI_CANVAS
		layout(location = 0) out vec4 love_Canvases[love_MaxCanvases];
		#define love_PixelColor love_Canvases[0]
	#else
		layout(location = 0) out vec4 love_PixelColor;
	#endif
#else
	#ifdef LOVE_MULTI_CANVAS
		#define love_Canvases gl_FragData
	#endif
	#define love_PixelColor gl_FragColor
#endif

// See Shader::updateScreenParams in Shader.cpp.
#define love_PixelCoord (vec2(gl_FragCoord.x, (gl_FragCoord.y * love_ScreenSize.z) + love_ScreenSize.w))
''';

/// Pixel-stage helper functions inserted before user code.
const String _loveShaderPixelFunctions = '''
uniform sampler2D love_VideoYChannel;
uniform sampler2D love_VideoCbChannel;
uniform sampler2D love_VideoCrChannel;

vec4 VideoTexel(vec2 texcoords) {
	vec3 yuv;
	yuv[0] = Texel(love_VideoYChannel, texcoords).r;
	yuv[1] = Texel(love_VideoCbChannel, texcoords).r;
	yuv[2] = Texel(love_VideoCrChannel, texcoords).r;
	yuv += vec3(-0.0627451017, -0.501960814, -0.501960814);

	vec4 color;
	color.r = dot(yuv, vec3(1.164,  0.000,  1.596));
	color.g = dot(yuv, vec3(1.164, -0.391, -0.813));
	color.b = dot(yuv, vec3(1.164,  2.018,  0.000));
	color.a = 1.0;

	return gammaCorrectColor(color);
}
''';

/// The default pixel-stage main wrapper for `vec4 effect(...)` shaders.
const String _loveShaderPixelMain = '''
uniform sampler2D MainTex;
varying LOVE_HIGHP_OR_MEDIUMP vec4 VaryingTexCoord;
varying mediump vec4 VaryingColor;

vec4 effect(vec4 vcolor, Image tex, vec2 texcoord, vec2 pixcoord);

void main() {
	love_PixelColor = effect(VaryingColor, MainTex, VaryingTexCoord.st, love_PixelCoord);
}
''';

/// The pixel-stage main wrapper for custom `void effect()` shaders.
const String _loveShaderPixelMainCustom = '''
varying LOVE_HIGHP_OR_MEDIUMP vec4 VaryingTexCoord;
varying mediump vec4 VaryingColor;

void effect();

void main() {
	effect();
}
''';

/// Returns the requested shader language target declared in [code].
///
/// When no pragma is present, this defaults to `glsl1`.
String? loveShaderLanguageTarget(String? code) {
  if (code == null) {
    return null;
  }

  final match = RegExp(r'^\s*#pragma language (\w+)').firstMatch(code);
  return match?.group(1) ?? 'glsl1';
}

/// Returns whether [code] looks like LOVE vertex shader source.
bool loveShaderSourceIsVertexCode(String code) {
  return RegExp(r'vec4\s+position\s*\(').hasMatch(code);
}

/// Selects vertex and pixel stages from up to two LOVE shader sources.
LoveShaderStageSelection loveSelectShaderStageSources(
  String? firstSource,
  String? secondSource,
) {
  String? vertexSource;
  String? pixelSource;
  var customPixel = false;
  var multiCanvas = false;

  for (final source in <String?>[firstSource, secondSource]) {
    if (source == null) {
      continue;
    }

    if (loveShaderSourceIsVertexCode(source)) {
      vertexSource = source;
    }

    final pixelSelection = _loveShaderPixelSelection(source);
    if (pixelSelection.isPixel) {
      pixelSource = source;
      customPixel = pixelSelection.customPixel;
      multiCanvas = pixelSelection.multiCanvas;
    }
  }

  return LoveShaderStageSelection(
    vertexSource: vertexSource,
    pixelSource: pixelSource,
    customPixel: customPixel,
    multiCanvas: multiCanvas,
  );
}

/// Resolves shader stages and validates that they can be translated.
///
/// This throws [LoveShaderTranslationException] when the stage pair is invalid
/// or unsupported for the requested target environment.
LoveShaderStageSelection loveResolveShaderStageSources({
  required String? firstSource,
  required String? secondSource,
  required bool gles,
  required bool supportsGlsl3,
  required bool gammaCorrect,
}) {
  final translation = loveShaderCodeToGlsl(
    gles: gles,
    firstSource: firstSource,
    secondSource: secondSource,
    supportsGlsl3: supportsGlsl3,
    gammaCorrect: gammaCorrect,
  );

  if (firstSource != null &&
      secondSource != null &&
      translation.vertexCode == null) {
    throw const LoveShaderTranslationException(
      "Could not parse vertex shader code (missing 'position' function?)",
    );
  }

  if (firstSource != null &&
      secondSource != null &&
      translation.pixelCode == null) {
    throw const LoveShaderTranslationException(
      "Could not parse pixel shader code (missing 'effect' function?)",
    );
  }

  final selection = loveSelectShaderStageSources(firstSource, secondSource);
  if (!selection.hasStage) {
    throw const LoveShaderTranslationException(
      "missing 'position' or 'effect' function?",
    );
  }

  return selection;
}

/// Translates LOVE shader source into GLSL stage code.
///
/// The returned translation may contain only a vertex stage, only a pixel
/// stage, or both, depending on the supplied source strings.
LoveShaderGlslTranslation loveShaderCodeToGlsl({
  required bool gles,
  required String? firstSource,
  required String? secondSource,
  required bool supportsGlsl3,
  required bool gammaCorrect,
}) {
  final selection = loveSelectShaderStageSources(firstSource, secondSource);
  final targetLanguage = loveShaderLanguageTarget(
    selection.pixelSource ?? selection.vertexSource,
  );
  final alternateLanguage = loveShaderLanguageTarget(
    selection.vertexSource ?? selection.pixelSource,
  );

  if (alternateLanguage != targetLanguage) {
    throw const LoveShaderTranslationException(
      'vertex and pixel shader languages must match',
    );
  }

  if (targetLanguage == 'glsl3' && !supportsGlsl3) {
    throw const LoveShaderTranslationException(
      'GLSL 3 shaders are not supported on this system!',
    );
  }

  if (targetLanguage != null &&
      !_loveShaderVersionDirectives.containsKey(targetLanguage)) {
    throw LoveShaderTranslationException(
      'Invalid shader language: $targetLanguage',
    );
  }

  var language = targetLanguage ?? 'glsl1';
  var glsl1On3 = false;
  if (language == 'glsl1' && supportsGlsl3) {
    language = 'glsl3';
    glsl1On3 = true;
  }

  return LoveShaderGlslTranslation(
    vertexCode: selection.vertexSource == null
        ? null
        : _loveCreateShaderStageCode(
            'VERTEX',
            selection.vertexSource!,
            language: language,
            gles: gles,
            glsl1On3: glsl1On3,
            gammaCorrect: gammaCorrect,
          ),
    pixelCode: selection.pixelSource == null
        ? null
        : _loveCreateShaderStageCode(
            'PIXEL',
            selection.pixelSource!,
            language: language,
            gles: gles,
            glsl1On3: glsl1On3,
            gammaCorrect: gammaCorrect,
            customPixel: selection.customPixel,
            multiCanvas: selection.multiCanvas,
          ),
  );
}

/// Classifies [code] as a regular or custom LOVE pixel shader.
_LoveShaderPixelSelection _loveShaderPixelSelection(String code) {
  if (RegExp(r'vec4\s+effect\s*\(').hasMatch(code)) {
    return const _LoveShaderPixelSelection(isPixel: true);
  }

  if (RegExp(r'void\s+effect\s*\(').hasMatch(code)) {
    return _LoveShaderPixelSelection(
      isPixel: true,
      customPixel: true,
      multiCanvas: code.contains('love_Canvases'),
    );
  }

  return const _LoveShaderPixelSelection(isPixel: false);
}

/// Builds the complete GLSL source for one translated shader [stage].
String _loveCreateShaderStageCode(
  String stage,
  String code, {
  required String language,
  required bool gles,
  required bool glsl1On3,
  required bool gammaCorrect,
  bool customPixel = false,
  bool multiCanvas = false,
}) {
  final lines = <String>[
    _loveShaderVersionDirectives[language]![gles]!,
    '#define $stage $stage',
    if (glsl1On3) '#define LOVE_GLSL1_ON_GLSL3 1',
    if (gammaCorrect) '#define LOVE_GAMMA_CORRECT 1',
    if (multiCanvas) '#define LOVE_MULTI_CANVAS 1',
    _loveShaderSyntaxPreamble,
    switch (stage) {
      'VERTEX' => _loveShaderVertexHeader,
      'PIXEL' => _loveShaderPixelHeader,
      _ => throw ArgumentError.value(
        stage,
        'stage',
        'Unsupported shader stage',
      ),
    },
    _loveShaderSharedUniforms,
    _loveShaderSharedFunctions,
    switch (stage) {
      'VERTEX' => _loveShaderVertexFunctions,
      'PIXEL' => _loveShaderPixelFunctions,
      _ => throw ArgumentError.value(
        stage,
        'stage',
        'Unsupported shader stage',
      ),
    },
    switch (stage) {
      'VERTEX' => _loveShaderVertexMain,
      'PIXEL' when customPixel => _loveShaderPixelMainCustom,
      'PIXEL' => _loveShaderPixelMain,
      _ => throw ArgumentError.value(
        stage,
        'stage',
        'Unsupported shader stage',
      ),
    },
    (!gles && (language == 'glsl1' || glsl1On3)) ? '#line 0' : '#line 1',
    code,
  ];

  return lines.join('\n');
}
