library;

import 'dart:async';

import 'package:lualike/library_builder.dart';
import 'package:lualike/lualike.dart' show LuaError;

typedef LoveApiImplementation = FutureOr<Object?> Function(List<Object?> args);
typedef LoveApiImplementationMap = Map<String, LoveApiImplementation>;
typedef LoveApiBindingFactory =
    LoveApiImplementation Function(LibraryRegistrationContext context);
typedef LoveApiBindingFactoryMap = Map<String, LoveApiBindingFactory>;

class LoveApiArgumentDoc {
  const LoveApiArgumentDoc({
    required this.name,
    required this.type,
    required this.description,
    this.defaultValue,
  });

  final String name;
  final String type;
  final String description;
  final String? defaultValue;
}

class LoveApiReturnDoc {
  const LoveApiReturnDoc({
    required this.name,
    required this.type,
    required this.description,
  });

  final String name;
  final String type;
  final String description;
}

class LoveApiVariantDoc {
  const LoveApiVariantDoc({required this.arguments, required this.returns});

  final List<LoveApiArgumentDoc> arguments;
  final List<LoveApiReturnDoc> returns;
}

class LoveApiSymbolDoc {
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

  final String symbol;
  final String module;
  final String name;
  final String kind;
  final String description;
  final List<LoveApiVariantDoc> variants;
  final String wikiPath;
  final String? container;
}

class LoveTypeDoc {
  const LoveTypeDoc({
    required this.symbol,
    required this.module,
    required this.name,
    required this.description,
    required this.supertypes,
    required this.methodSymbols,
    required this.wikiPath,
  });

  final String symbol;
  final String module;
  final String name;
  final String description;
  final List<String> supertypes;
  final List<String> methodSymbols;
  final String wikiPath;
}

class LoveEnumConstantDoc {
  const LoveEnumConstantDoc({required this.name, required this.description});

  final String name;
  final String description;
}

class LoveEnumDoc {
  const LoveEnumDoc({
    required this.symbol,
    required this.module,
    required this.name,
    required this.description,
    required this.constants,
    required this.wikiPath,
  });

  final String symbol;
  final String module;
  final String name;
  final String description;
  final List<LoveEnumConstantDoc> constants;
  final String wikiPath;
}

class LoveModuleDoc {
  const LoveModuleDoc({
    required this.symbol,
    required this.name,
    required this.description,
    required this.wikiPath,
  });

  final String symbol;
  final String name;
  final String description;
  final String wikiPath;
}

Never loveApiUnimplemented(String symbol) {
  throw LuaError('$symbol is not implemented yet in package:love2d');
}

final LoveApiBindingFactoryMap loveApiBindingFactories =
    <String, LoveApiBindingFactory>{};

Value bindLoveApiFunction(
  LibraryRegistrationContext context, {
  required String symbol,
  required String publicName,
  required LoveApiImplementationMap implementations,
}) {
  final implementation =
      loveApiBindingFactories[symbol]?.call(context) ?? implementations[symbol];
  if (implementation == null) {
    throw StateError('Missing LOVE API implementation stub for $symbol');
  }

  final builder = BuiltinFunctionBuilder(context);
  return Value(
    builder.create((args) => implementation(args)),
    functionName: publicName,
  );
}
