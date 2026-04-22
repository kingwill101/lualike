library;

import 'dart:convert';

import 'package:lualike/library_builder.dart'
    show BuiltinFunctionBuilder, LibraryContext;
import 'package:lualike/lualike.dart'
    show BuiltinFunction, LuaError, LuaRuntime, Value;

import '../../generated/love_api_reference.g.dart' show loveApiEnums;
import '../love_runtime.dart'
    show
        LoveGraphicsFilterMode,
        LoveRuntimeContext,
        LoveShaderTranslationException,
        loveShaderCodeToGlsl;

final Expando<bool> _loveGraphicsEnumsInstalled = Expando<bool>(
  'love2dGraphicsEnumsInstalled',
);

final Map<String, Map<String, Object?>> _loveGraphicsEnumMaps =
    _buildLoveGraphicsEnumMaps();
final Map<String, Value Function(LuaRuntime runtime)>
_loveGraphicsExtraSymbols = <String, Value Function(LuaRuntime runtime)>{
  '_newVideo': _bindGraphicsInternalNewVideo,
  '_shaderCodeToGLSL': _bindGraphicsShaderCodeToGlsl,
  '_setDefaultShaderCode': _bindGraphicsSetDefaultShaderCode,
  '_transformGLSLErrorMessages': _bindGraphicsTransformGLSLErrorMessages,
  'getDefaultMipmapFilter': _bindGraphicsGetDefaultMipmapFilter,
  'isCreated': _bindGraphicsIsCreated,
  'setDefaultMipmapFilter': _bindGraphicsSetDefaultMipmapFilter,
};

const Set<String> _graphicsDefaultShaderLanguages = <String>{
  'glsl1',
  'essl1',
  'glsl3',
  'essl3',
};

const Set<String> _graphicsDefaultShaderStages = <String>{
  'vertex',
  'pixel',
  'videopixel',
  'arraypixel',
};

Map<String, Map<String, Object?>> _buildLoveGraphicsEnumMaps() {
  final result = <String, Map<String, Object?>>{};
  for (final enumDoc in loveApiEnums) {
    if (enumDoc.module != 'love.graphics') {
      continue;
    }

    result[enumDoc.symbol] = <String, Object?>{
      for (final constant in enumDoc.constants) constant.name: constant.name,
    };
  }
  return result;
}

void installLoveGraphicsEnumBindings(LuaRuntime runtime) {
  if (_loveGraphicsEnumsInstalled[runtime] == true) {
    return;
  }

  final graphicsTable = _graphicsModuleTable(runtime);
  if (graphicsTable == null) {
    return;
  }

  for (final entry in _loveGraphicsEnumMaps.entries) {
    final enumValue = Value(Map<String, Object?>.from(entry.value));
    graphicsTable[entry.key] = enumValue;
    runtime.globals.define(entry.key, enumValue);
  }

  for (final entry in _loveGraphicsExtraSymbols.entries) {
    graphicsTable[entry.key] = entry.value(runtime);
  }

  _loveGraphicsEnumsInstalled[runtime] = true;
}

Value _bindGraphicsIsCreated(LuaRuntime runtime) {
  final builder = BuiltinFunctionBuilder(
    LibraryContext(environment: runtime.getCurrentEnv(), interpreter: runtime),
  );
  return Value(builder.create((args) => true), functionName: 'isCreated');
}

Value _bindGraphicsGetDefaultMipmapFilter(LuaRuntime runtime) {
  final builder = BuiltinFunctionBuilder(
    LibraryContext(environment: runtime.getCurrentEnv(), interpreter: runtime),
  );
  return Value(
    builder.create((args) {
      final graphics = LoveRuntimeContext.of(runtime).graphics;
      return Value.multi(<Object?>[
        switch (graphics.defaultMipmapFilter) {
          final LoveGraphicsFilterMode filter => _graphicsFilterModeName(
            filter,
          ),
          null => null,
        },
        graphics.defaultMipmapSharpness,
      ]);
    }),
    functionName: 'getDefaultMipmapFilter',
  );
}

Value _bindGraphicsInternalNewVideo(LuaRuntime runtime) {
  final builder = BuiltinFunctionBuilder(
    LibraryContext(environment: runtime.getCurrentEnv(), interpreter: runtime),
  );
  return Value(
    builder.create((args) {
      final graphicsTable = _graphicsModuleTable(runtime);
      final newVideoEntry = graphicsTable?['newVideo'];
      final newVideo = switch (newVideoEntry) {
        final Value value when value.raw is BuiltinFunction =>
          value.raw as BuiltinFunction,
        _ => throw StateError('love.graphics.newVideo is not installed'),
      };

      final source = args.isNotEmpty ? args.first : null;
      final dpiScale = args.length >= 2
          ? _graphicsNumber(args[1], symbol: 'love.graphics._newVideo')
          : 1.0;
      return newVideo.call(<Object?>[
        source,
        <Object?, Object?>{'audio': false, 'dpiscale': dpiScale},
      ]);
    }),
    functionName: '_newVideo',
  );
}

Value _bindGraphicsSetDefaultShaderCode(LuaRuntime runtime) {
  final builder = BuiltinFunctionBuilder(
    LibraryContext(environment: runtime.getCurrentEnv(), interpreter: runtime),
  );
  return Value(
    builder.create((args) {
      const symbol = 'love.graphics._setDefaultShaderCode';
      if (args.length < 2) {
        throw LuaError('$symbol expects 2 tables');
      }

      for (var argumentIndex = 0; argumentIndex < 2; argumentIndex++) {
        final table = _graphicsRequireTable(
          args[argumentIndex],
          symbol: symbol,
          context:
              'argument ${argumentIndex + 1} must be a table of shader code',
        );

        for (final language in _graphicsDefaultShaderLanguages) {
          final languageTable = _graphicsRequireTable(
            table[language],
            symbol: symbol,
            context:
                'argument ${argumentIndex + 1} missing shader language "$language"',
          );
          for (final stage in _graphicsDefaultShaderStages) {
            _graphicsRequireString(
              languageTable[stage],
              symbol: symbol,
              context:
                  'argument ${argumentIndex + 1} missing $language.$stage shader code',
            );
          }
        }
      }

      // The Dart/Flutter backend does not use LOVE's generated default GLSL
      // code paths, but exposing this internal helper keeps the source-visible
      // API surface aligned with upstream.
      return null;
    }),
    functionName: '_setDefaultShaderCode',
  );
}

Value _bindGraphicsShaderCodeToGlsl(LuaRuntime runtime) {
  final builder = BuiltinFunctionBuilder(
    LibraryContext(environment: runtime.getCurrentEnv(), interpreter: runtime),
  );
  return Value(
    builder.create((args) {
      const symbol = 'love.graphics._shaderCodeToGLSL';
      final rawGles = _graphicsRawValue(args.isNotEmpty ? args.first : null);
      if (rawGles is! bool) {
        throw LuaError('$symbol expected a boolean at argument 1');
      }

      final firstSource = _graphicsOptionalString(
        args.length >= 2 ? args[1] : null,
        symbol: symbol,
        argumentIndex: 2,
      );
      final secondSource = _graphicsOptionalString(
        args.length >= 3 ? args[2] : null,
        symbol: symbol,
        argumentIndex: 3,
      );

      try {
        final translation = loveShaderCodeToGlsl(
          gles: rawGles,
          firstSource: firstSource,
          secondSource: secondSource,
          supportsGlsl3: true,
          gammaCorrect: false,
        );
        return Value.multi(<Object?>[
          translation.vertexCode,
          translation.pixelCode,
        ]);
      } on LoveShaderTranslationException catch (error) {
        throw LuaError(error.message);
      }
    }),
    functionName: '_shaderCodeToGLSL',
  );
}

Value _bindGraphicsTransformGLSLErrorMessages(LuaRuntime runtime) {
  final builder = BuiltinFunctionBuilder(
    LibraryContext(environment: runtime.getCurrentEnv(), interpreter: runtime),
  );
  return Value(
    builder.create((args) {
      const symbol = 'love.graphics._transformGLSLErrorMessages';
      final message = _graphicsRequireString(
        args.isNotEmpty ? args.first : null,
        symbol: symbol,
        context: 'expected a string message at argument 1',
      );
      return _graphicsTransformGlslErrorMessages(message);
    }),
    functionName: '_transformGLSLErrorMessages',
  );
}

Value _bindGraphicsSetDefaultMipmapFilter(LuaRuntime runtime) {
  final builder = BuiltinFunctionBuilder(
    LibraryContext(environment: runtime.getCurrentEnv(), interpreter: runtime),
  );
  return Value(
    builder.create((args) {
      final graphics = LoveRuntimeContext.of(runtime).graphics;
      final mode = args.isEmpty ? null : _graphicsRawValue(args.first);
      graphics.defaultMipmapFilter = mode == null
          ? null
          : _graphicsFilterMode(
              mode is String
                  ? mode
                  : (throw LuaError(
                      'love.graphics.setDefaultMipmapFilter expected a string or nil',
                    )),
            );
      graphics.defaultMipmapSharpness = args.length >= 2
          ? _graphicsNumber(
              args[1],
              symbol: 'love.graphics.setDefaultMipmapFilter',
            )
          : 0.0;
      return null;
    }),
    functionName: 'setDefaultMipmapFilter',
  );
}

LoveGraphicsFilterMode _graphicsFilterMode(String value) {
  return switch (value) {
    'linear' => LoveGraphicsFilterMode.linear,
    'nearest' => LoveGraphicsFilterMode.nearest,
    _ => throw LuaError(
      'love.graphics.setDefaultMipmapFilter invalid filter mode "$value"',
    ),
  };
}

String _graphicsFilterModeName(LoveGraphicsFilterMode value) {
  return switch (value) {
    LoveGraphicsFilterMode.linear => 'linear',
    LoveGraphicsFilterMode.nearest => 'nearest',
  };
}

Object? _graphicsRawValue(Object? value) => value is Value ? value.raw : value;

double _graphicsNumber(Object? value, {required String symbol}) {
  final raw = value is Value ? value.unwrap() : value;
  if (raw is num) {
    return raw.toDouble();
  }
  throw LuaError('$symbol expected a number');
}

Map<dynamic, dynamic> _graphicsRequireTable(
  Object? value, {
  required String symbol,
  required String context,
}) {
  final raw = _graphicsRawValue(value);
  if (raw is Map<dynamic, dynamic>) {
    return raw;
  }
  throw LuaError('$symbol $context');
}

String _graphicsRequireString(
  Object? value, {
  required String symbol,
  required String context,
}) {
  final raw = _graphicsRawValue(value);
  if (raw is String) {
    return raw;
  }
  throw LuaError('$symbol $context');
}

String? _graphicsOptionalString(
  Object? value, {
  required String symbol,
  required int argumentIndex,
}) {
  final raw = _graphicsRawValue(value);
  if (raw == null) {
    return null;
  }
  if (raw is String) {
    return raw;
  }
  throw LuaError('$symbol expected a string or nil at argument $argumentIndex');
}

String _graphicsTransformGlslErrorMessages(String message) {
  final compileMatch = RegExp(
    r'Cannot compile ([A-Za-z]+) shader code',
  ).firstMatch(message);
  final validateMatch = compileMatch == null
      ? RegExp(r'Error validating ([A-Za-z]+) shader').firstMatch(message)
      : null;
  final shaderType = compileMatch?.group(1) ?? validateMatch?.group(1);
  if (shaderType == null) {
    return message;
  }

  final prefix = compileMatch != null ? 'Cannot compile ' : 'Error validating ';
  final lines = <String>['${prefix}${shaderType} shader code:'];

  for (final line in const LineSplitter().convert(message)) {
    final nvidiaMatch = RegExp(
      r'^0\((\d+)\)\s*:\s*(\w+)[^:]+:\s*(.+)$',
    ).firstMatch(line);
    if (nvidiaMatch != null) {
      lines.add(
        'Line ${nvidiaMatch.group(1)}: ${nvidiaMatch.group(2)}: '
        '${nvidiaMatch.group(3)}',
      );
      continue;
    }

    final amdMatch = RegExp(
      r'^\w+: 0:(\d+):\s*(\w+)\([^)]+\)\s*(.+)$',
    ).firstMatch(line);
    if (amdMatch != null) {
      lines.add(
        'Line ${amdMatch.group(1)}: ${amdMatch.group(2)}: '
        '${amdMatch.group(3)}',
      );
      continue;
    }

    final macMatch = RegExp(r'^(\w+): \d+:(\d+): (.+)$').firstMatch(line);
    if (macMatch != null) {
      lines.add(
        'Line ${macMatch.group(2)}: ${macMatch.group(1)}: '
        '${macMatch.group(3)}',
      );
      continue;
    }

    if (line.startsWith('ERROR:')) {
      lines.add(line);
    }
  }

  if (lines.length == 1) {
    return message;
  }
  return lines.join('\n');
}

Map<dynamic, dynamic>? _graphicsModuleTable(LuaRuntime runtime) {
  final love = runtime.globals.get('love');
  final loveTable = love is Value ? love.raw : love;
  if (loveTable is! Map<dynamic, dynamic>) {
    return null;
  }

  final graphics = loveTable['graphics'];
  final graphicsTable = graphics is Value ? graphics.raw : graphics;
  if (graphicsTable is! Map<dynamic, dynamic>) {
    return null;
  }

  return graphicsTable;
}
