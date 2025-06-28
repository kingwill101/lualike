import 'package:lualike/lualike.dart';
import 'package:lualike/src/bytecode/vm.dart' show BytecodeVM;
import 'package:lualike/src/stdlib/lib_io.dart';
import '../value_class.dart';

/// Options for controlling serpent serialization behavior
class SerpentOptions {
  final bool indent; // Use indentation for readability
  final int? maxDepth; // Maximum nesting depth (null for unlimited)
  final bool handleCycles; // Handle circular references
  final bool compact; // Minimize whitespace
  final bool sortKeys; // Sort table keys
  final String indent_str; // Indentation string
  final String comment; // Comment string to include
  final List<String> exclude; // Keys to exclude
  final bool special; // Handle special values (nan, inf, -inf)

  SerpentOptions({
    this.indent = true,
    this.maxDepth,
    this.handleCycles = true,
    this.compact = false,
    this.sortKeys = false,
    this.indent_str = "  ",
    this.comment = "",
    this.exclude = const [],
    this.special = true,
  });
}

class _SerializationContext {
  final Map<dynamic, int> seen = {};
  final SerpentOptions options;
  int level = 0;
  int id = 0;

  _SerializationContext(this.options);

  String getIndent() {
    if (!options.indent) return '';
    return options.indent_str * level;
  }

  int getNextId() {
    return ++id;
  }
}

class SerpentLib {
  static final ValueClass serpentClass = ValueClass.create({
    "__call": (List<Object?> args) {
      // When called as a function, serpent acts like serpent.line
      if (args.length < 2) {
        throw Exception("serpent requires at least one argument");
      }
      final value = args[1] as Value;
      final opts = args.length > 2 ? (args[2] as Value).raw : null;

      return Value(SerpentLine().call([value, Value(opts)]));
    },
  });

  static final Map<String, dynamic> functions = {
    "dump": SerpentDump(),
    "line": SerpentLine(),
    "block": SerpentBlock(),
    "load": SerpentLoad(),
    "loadfile": SerpentLoadFile(),
    "addquotes": SerpentAddQuotes(),
    // Default options table
    "defaultOptions": Value({
      "indent": Value(true),
      "maxDepth": Value(null),
      "handleCycles": Value(true),
      "compact": Value(false),
      "sortKeys": Value(false),
      "indent_str": Value("  "),
      "comment": Value(""),
      "exclude": Value([]),
      "special": Value(true),
    }),
  };
}

/// Serializes a Lua value into a parseable string
class SerpentDump implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw Exception("serpent.dump requires at least one argument");
    }

    final value = args[0] as Value;
    final opts = args.length > 1 ? (args[1] as Value).raw : null;

    final options = _parseOptions(opts);
    final context = _SerializationContext(options);

    final result = _serializeAsParseable(value, context);
    return Value(result);
  }

  String _serializeAsParseable(Value value, _SerializationContext context) {
    final raw = value.raw;

    // Handle nil, boolean, and number literals directly
    if (raw == null) return "nil";
    if (raw is bool) return raw.toString();
    if (raw is num) {
      if (context.options.special) {
        if (raw.isNaN) return "0/0"; // NaN representation
        if (raw == double.infinity) return "1/0"; // Infinity
        if (raw == double.negativeInfinity) return "-1/0"; // -Infinity
      }
      return raw.toString();
    }

    // Handle strings
    if (raw is String) {
      return _escapeString(raw);
    }

    // Handle tables
    if (raw is Map) {
      if (context.options.handleCycles) {
        final id = context.seen[raw];
        if (id != null) {
          // This is a cycle, reference the existing table
          return '_[$id]';
        }
        context.seen[raw] = context.getNextId();
      }

      // Handle max depth
      if (context.options.maxDepth != null &&
          context.level >= context.options.maxDepth!) {
        return "...";
      }

      context.level++;
      final indent = context.getIndent();
      final prevIndent = context.options.indent
          ? context.getIndent().substring(
              0,
              context.getIndent().length - context.options.indent_str.length,
            )
          : "";

      // Serialize the table
      final parts = <String>[];

      // Get all keys and possibly sort them
      var keys = (raw).keys.toList();
      if (context.options.sortKeys) {
        keys.sort((a, b) {
          if (a is num && b is num) return a.compareTo(b);
          return a.toString().compareTo(b.toString());
        });
      }

      for (final key in keys) {
        if (context.options.exclude.contains(key)) continue;

        final val = raw[key];
        final valObj = val is Value ? val : Value(val);

        // Serialize key and value
        String keyStr;
        if (key is num && key == key.truncateToDouble()) {
          // Array-like table with integer keys
          keyStr = "[${key.toString()}]";
        } else if (key is String && _isValidIdentifier(key)) {
          keyStr = key;
        } else {
          keyStr = "[$_escapeString(key.toString())]";
        }

        final valueStr = _serializeAsParseable(valObj, context);
        parts.add("$keyStr = $valueStr");
      }

      context.level--;

      final separator = context.options.compact ? ", " : ",\n$indent";
      return "{${context.options.compact ? "" : "\n$indent"}${parts.join(separator)}${context.options.compact ? "" : "\n$prevIndent"}}";
    }

    // Handle functions - cannot be perfectly serialized
    if (raw is Function) {
      return "function() --[[ Function ]] end";
    }

    // Other types (userdata, threads, etc.)
    return "nil --[[ ${raw.runtimeType} ]]";
  }

  String _escapeString(String str) {
    final escaped = str
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t')
        .replaceAll('\b', '\\b')
        .replaceAll('\f', '\\f')
        .replaceAll('\v', '\\v')
        .replaceAll('0', '\\0');
    return '"$escaped"';
  }

  bool _isValidIdentifier(String key) {
    // Check if the string is a valid Lua identifier
    if (key.isEmpty) return false;
    if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(key)) return false;

    // Check if it's a Lua keyword
    final keywords = {
      'and',
      'break',
      'do',
      'else',
      'elseif',
      'end',
      'false',
      'for',
      'function',
      'goto',
      'if',
      'in',
      'local',
      'nil',
      'not',
      'or',
      'repeat',
      'return',
      'then',
      'true',
      'until',
      'while',
    };
    return !keywords.contains(key);
  }

  SerpentOptions _parseOptions(dynamic opts) {
    if (opts == null) return SerpentOptions();
    if (opts is! Map) return SerpentOptions();

    return SerpentOptions(
      indent: opts['indent'] is Value
          ? (opts['indent'] as Value).raw as bool
          : true,
      maxDepth: opts['maxDepth'] is Value
          ? (opts['maxDepth'] as Value).raw as int?
          : null,
      handleCycles: opts['handleCycles'] is Value
          ? (opts['handleCycles'] as Value).raw as bool
          : true,
      compact: opts['compact'] is Value
          ? (opts['compact'] as Value).raw as bool
          : false,
      sortKeys: opts['sortKeys'] is Value
          ? (opts['sortKeys'] as Value).raw as bool
          : false,
      indent_str: opts['indent_str'] is Value
          ? (opts['indent_str'] as Value).raw as String
          : "  ",
      comment: opts['comment'] is Value
          ? (opts['comment'] as Value).raw as String
          : "",
      exclude:
          opts['exclude'] is Value && (opts['exclude'] as Value).raw is List
          ? ((opts['exclude'] as Value).raw as List)
                .map((e) => e.toString())
                .toList()
          : const [],
      special: opts['special'] is Value
          ? (opts['special'] as Value).raw as bool
          : true,
    );
  }
}

/// Serializes a Lua value into a single line parseable string
class SerpentLine implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw Exception("serpent.line requires at least one argument");
    }

    final value = args[0] as Value;
    final opts = args.length > 1 ? (args[1] as Value).raw : null;

    // Create options with compact = true for single line output
    final defaultOpts = (opts is Map) ? Map.from(opts) : {};
    defaultOpts['compact'] = Value(true);

    final dumper = SerpentDump();
    return dumper.call([value, Value(defaultOpts)]);
  }
}

/// Serializes a Lua value into a multi-line, human-readable string
class SerpentBlock implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw Exception("serpent.block requires at least one argument");
    }

    final value = args[0] as Value;
    final opts = args.length > 1 ? (args[1] as Value).raw : null;

    final dumper = SerpentDump();
    final result = dumper.call([value, Value(opts)]);

    // Add any comment if specified in options
    var comment = "";
    if (opts is Map && opts['comment'] is Value) {
      final commentText = (opts['comment'] as Value).raw;
      if (commentText is String && commentText.isNotEmpty) {
        comment = " --[[ $commentText ]]";
      }
    }

    return result is Value ? Value(result.raw.toString() + comment) : result;
  }
}

/// Deserializes a previously serialized Lua value
class SerpentLoad implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw Exception("serpent.load requires at least one argument");
    }

    final str = (args[0] as Value).raw.toString();

    // We need to use loadstring to evaluate the serialized string
    // In LuaLike, we need to get a reference to the interpreter
    final ast = parse("local _ = {}; return $str");

    try {
      // Assuming this is part of a standard library with access to the VM
      final vm = Interpreter();
      final result = vm.run(ast.statements);
      return result;
    } catch (e) {
      throw Exception("Error deserializing: ${e.toString()}");
    }
  }
}

/// Loads a serialized Lua value from a file
class SerpentLoadFile implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw Exception("serpent.loadfile requires at least one argument");
    }

    final filename = (args[0] as Value).raw.toString();

    // Use io library to load from file
    try {
      final openFunc = IOLib.functions["open"] as IOOpen;
      final file = await openFunc.call([Value(filename), Value("r")]);

      if (file is Value && file.raw != null) {
        final readFunc = IOLib.functions["read"] as IORead;
        final content = await readFunc.call([file, Value("*a")]);

        // Close the file
        final closeFunc = IOLib.functions["close"] as IOClose;
        await closeFunc.call([file]);

        if (content is Value) {
          // Load the content
          final loader = SerpentLoad();
          return loader.call([content]);
        }
      }

      throw Exception("Could not read file: $filename");
    } catch (e) {
      throw Exception("Error loading file: ${e.toString()}");
    }
  }
}

/// Utility function to add quotes around a string
class SerpentAddQuotes implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw Exception("serpent.addquotes requires at least one argument");
    }

    final str = (args[0] as Value).raw.toString();
    return Value('"${_escapeQuotes(str)}"');
  }

  String _escapeQuotes(String str) {
    return str
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n');
  }
}

void defineSerpentLibrary({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  final serpentTable = <String, dynamic>{};
  SerpentLib.functions.forEach((key, value) {
    serpentTable[key] = value;
  });

  env.define(
    "serpent",
    Value(serpentTable, metatable: SerpentLib.serpentClass.metamethods),
  );
}
