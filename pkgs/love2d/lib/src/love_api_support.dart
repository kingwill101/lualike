library;

import 'dart:async';

import 'package:lualike/library_builder.dart';
import 'package:lualike/lualike.dart' show LuaError;

/// Implements a single LOVE API symbol.
typedef LoveApiImplementation = FutureOr<Object?> Function(List<Object?> args);

/// Maps fully-qualified LOVE symbols to their implementations.
typedef LoveApiImplementationMap = Map<String, LoveApiImplementation>;

/// Builds a LOVE API implementation for the current library context.
typedef LoveApiBindingFactory =
    LoveApiImplementation Function(LibraryRegistrationContext context);

/// Maps fully-qualified LOVE symbols to context-aware factories.
typedef LoveApiBindingFactoryMap = Map<String, LoveApiBindingFactory>;

/// Documentation for one argument in a generated LOVE API variant.
class LoveApiArgumentDoc {
  /// Creates argument documentation metadata.
  const LoveApiArgumentDoc({
    required this.name,
    required this.type,
    required this.description,
    this.defaultValue,
  });

  /// The argument name exposed by the LOVE reference.
  final String name;

  /// The documented argument type.
  final String type;

  /// The argument description from the LOVE reference.
  final String description;

  /// The documented default value, if one exists.
  final String? defaultValue;
}

/// Documentation for one return value in a generated LOVE API variant.
class LoveApiReturnDoc {
  /// Creates return value documentation metadata.
  const LoveApiReturnDoc({
    required this.name,
    required this.type,
    required this.description,
  });

  /// The return value name exposed by the LOVE reference.
  final String name;

  /// The documented return type.
  final String type;

  /// The return value description from the LOVE reference.
  final String description;
}

/// Documentation for one callable overload in the LOVE reference.
class LoveApiVariantDoc {
  /// Creates overload documentation metadata.
  const LoveApiVariantDoc({required this.arguments, required this.returns});

  /// The argument list for this overload.
  final List<LoveApiArgumentDoc> arguments;

  /// The documented return values for this overload.
  final List<LoveApiReturnDoc> returns;
}

/// Documentation for one symbol in the generated LOVE reference.
class LoveApiSymbolDoc {
  /// Creates symbol documentation metadata.
  const LoveApiSymbolDoc({
    required this.symbol,
    required this.module,
    required this.name,
    required this.kind,
    required this.description,
    required this.variants,
    required this.wikiPath,
    this.container,
  });

  /// The fully-qualified LOVE symbol name.
  final String symbol;

  /// The module that owns this symbol.
  final String module;

  /// The short symbol name.
  final String name;

  /// The reference kind, such as `function` or `method`.
  final String kind;

  /// The summary description from the LOVE reference.
  final String description;

  /// The documented overloads for this symbol.
  final List<LoveApiVariantDoc> variants;

  /// The LOVE wiki path for this symbol.
  final String wikiPath;

  /// The owning type name for methods and fields, if one exists.
  final String? container;
}

/// Documentation for one LOVE object type.
class LoveTypeDoc {
  /// Creates type documentation metadata.
  const LoveTypeDoc({
    required this.symbol,
    required this.module,
    required this.name,
    required this.description,
    required this.supertypes,
    required this.methodSymbols,
    required this.wikiPath,
  });

  /// The fully-qualified LOVE type symbol.
  final String symbol;

  /// The module that owns this type.
  final String module;

  /// The short type name.
  final String name;

  /// The summary description from the LOVE reference.
  final String description;

  /// The supertypes listed by the LOVE reference.
  final List<String> supertypes;

  /// The fully-qualified method symbols attached to this type.
  final List<String> methodSymbols;

  /// The LOVE wiki path for this type.
  final String wikiPath;
}

/// Documentation for one named constant in a LOVE enum.
class LoveEnumConstantDoc {
  /// Creates enum constant documentation metadata.
  const LoveEnumConstantDoc({required this.name, required this.description});

  /// The enum constant name.
  final String name;

  /// The enum constant description from the LOVE reference.
  final String description;
}

/// Documentation for one LOVE enum.
class LoveEnumDoc {
  /// Creates enum documentation metadata.
  const LoveEnumDoc({
    required this.symbol,
    required this.module,
    required this.name,
    required this.description,
    required this.constants,
    required this.wikiPath,
  });

  /// The fully-qualified LOVE enum symbol.
  final String symbol;

  /// The module that owns this enum.
  final String module;

  /// The short enum name.
  final String name;

  /// The summary description from the LOVE reference.
  final String description;

  /// The enum constants defined by this enum.
  final List<LoveEnumConstantDoc> constants;

  /// The LOVE wiki path for this enum.
  final String wikiPath;
}

/// Documentation for one LOVE module.
class LoveModuleDoc {
  /// Creates module documentation metadata.
  const LoveModuleDoc({
    required this.symbol,
    required this.name,
    required this.description,
    required this.wikiPath,
  });

  /// The fully-qualified LOVE module symbol.
  final String symbol;

  /// The short module name.
  final String name;

  /// The summary description from the LOVE reference.
  final String description;

  /// The LOVE wiki path for this module.
  final String wikiPath;
}

/// Throws a standard unimplemented error for the LOVE symbol [symbol].
Never loveApiUnimplemented(String symbol) {
  throw LuaError('$symbol is not implemented yet in package:love2d');
}

/// Context-aware factories that override the generated LOVE bindings.
final LoveApiBindingFactoryMap loveApiBindingFactories =
    <String, LoveApiBindingFactory>{};

/// Wraps the implementation for [symbol] as a Lua builtin named [publicName].
///
/// Throws a [StateError] if no generated stub or override implementation is
/// available for [symbol].
Value bindLoveApiFunction(
  LibraryRegistrationContext context, {
  required String symbol,
  required String publicName,
  required LoveApiImplementationMap implementations,
  FunctionDoc? doc,
  String? docName,
}) {
  if (doc != null) {
    context.describe(docName ?? publicName, doc);
  }

  final implementation =
      loveApiBindingFactories[symbol]?.call(context) ?? implementations[symbol];
  if (implementation == null) {
    throw StateError('Missing LOVE API implementation stub for $symbol');
  }

  if (_bytecodeInlineLoveApiSymbols.contains(symbol)) {
    return Value(
      _InlineableLoveApiBuiltin(context.vm, implementation),
      functionName: publicName,
    );
  }

  final builder = BuiltinFunctionBuilder(context);
  return Value(
    builder.create((args) => implementation(args)),
    functionName: publicName,
  );
}

final class _InlineableLoveApiBuiltin extends BuiltinFunction {
  _InlineableLoveApiBuiltin(super.interpreter, this._implementation);

  final LoveApiImplementation _implementation;

  @override
  bool get canBytecodeInlineWithoutManagedFrame => true;

  @override
  FutureOr<Object?> call(List<Object?> args) => _implementation(args);
}

const Set<String> _bytecodeInlineLoveApiSymbols = <String>{
  'love.graphics.applyTransform',
  'love.graphics.arc',
  'love.graphics.circle',
  'love.graphics.clear',
  'love.graphics.discard',
  'love.graphics.draw',
  'love.graphics.drawInstanced',
  'love.graphics.drawLayer',
  'love.graphics.ellipse',
  'love.graphics.flushBatch',
  'love.graphics.getBackgroundColor',
  'love.graphics.getBlendMode',
  'love.graphics.getCanvas',
  'love.graphics.getColor',
  'love.graphics.getColorMask',
  'love.graphics.getDefaultFilter',
  'love.graphics.getDefaultMipmapFilter',
  'love.graphics.getDimensions',
  'love.graphics.getDPIScale',
  'love.graphics.getFont',
  'love.graphics.getHeight',
  'love.graphics.getLineJoin',
  'love.graphics.getLineStyle',
  'love.graphics.getLineWidth',
  'love.graphics.getPointSize',
  'love.graphics.getScissor',
  'love.graphics.getStackDepth',
  'love.graphics.getWidth',
  'love.graphics.intersectScissor',
  'love.graphics.inverseTransformPoint',
  'love.graphics.isActive',
  'love.graphics.isCreated',
  'love.graphics.isGammaCorrect',
  'love.graphics.isWireframe',
  'love.graphics.line',
  'love.graphics.origin',
  'love.graphics.points',
  'love.graphics.polygon',
  'love.graphics.pop',
  'love.graphics.present',
  'love.graphics.print',
  'love.graphics.printf',
  'love.graphics.push',
  'love.graphics.rectangle',
  'love.graphics.replaceTransform',
  'love.graphics.reset',
  'love.graphics.rotate',
  'love.graphics.scale',
  'love.graphics.setBackgroundColor',
  'love.graphics.setBlendMode',
  'love.graphics.setCanvas',
  'love.graphics.setColor',
  'love.graphics.setColorMask',
  'love.graphics.setDefaultFilter',
  'love.graphics.setDefaultMipmapFilter',
  'love.graphics.setFont',
  'love.graphics.setLineJoin',
  'love.graphics.setLineStyle',
  'love.graphics.setLineWidth',
  'love.graphics.setPointSize',
  'love.graphics.setScissor',
  'love.graphics.setWireframe',
  'love.graphics.shear',
  'love.graphics.transformPoint',
  'love.graphics.translate',
  'love.joystick.getJoysticks',
  'love.keyboard.hasKeyRepeat',
  'love.keyboard.hasScreenKeyboard',
  'love.keyboard.hasTextInput',
  'love.keyboard.isDown',
  'love.math.colorFromBytes',
  'love.math.colorToBytes',
  'love.math.gammaToLinear',
  'love.math.getRandomSeed',
  'love.math.getRandomState',
  'love.math.isConvex',
  'love.math.linearToGamma',
  'love.math.noise',
  'love.math.random',
  'love.math.randomNormal',
  'love.math.setRandomSeed',
  'love.math.setRandomState',
  'love.math.triangulate',
  'love.mouse.getPosition',
  'love.mouse.getRelativeMode',
  'love.mouse.getX',
  'love.mouse.getY',
  'love.mouse.isDown',
  'love.mouse.isGrabbed',
  'love.mouse.isVisible',
  'love.mouse.setGrabbed',
  'love.mouse.setPosition',
  'love.mouse.setRelativeMode',
  'love.mouse.setVisible',
  'love.mouse.setX',
  'love.mouse.setY',
  'love.timer.getAverageDelta',
  'love.timer.getDelta',
  'love.timer.getFPS',
  'love.timer.getTime',
  'love.timer.sleep',
  'love.timer.step',
};
