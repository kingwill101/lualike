import 'package:lualike/library_builder.dart';

// ---------------------------------------------------------------------------
// BuiltinFunction subclasses
// ---------------------------------------------------------------------------

class DiscoverPlugins extends BuiltinFunction {
  DiscoverPlugins([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Scans the plugin directory and returns available plugin manifests.',
    params: [
      DocParam(
        'directory',
        'string?',
        'Optional path override (defaults to "./plugins").',
      ),
    ],
    returns: 'An array of PluginManifest tables.',
    category: 'plugin_api',
    example: 'local plugins = plugin_api.discover()',
  );

  @override
  Object? call(List<Object?> args) {
    // Stub: in a real implementation this would scan a directory.
    return [
      {
        'id': 'example_plugin',
        'name': 'Example Plugin',
        'version': '1.0.0',
        'isCore': false,
      },
    ];
  }
}

class ResolveDependencies extends BuiltinFunction {
  ResolveDependencies([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary:
        'Validates that all declared dependency IDs can be resolved.',
    params: [
      DocParam('manifest', 'table', 'A PluginManifest table with a '
          '"dependencies" field.'),
    ],
    returns: 'true if all dependencies exist, false + first missing ID otherwise.',
    category: 'plugin_api',
    example:
        'local ok, missing = plugin_api.resolveDependencies(manifest)',
  );

  @override
  Object? call(List<Object?> args) {
    // Stub
    return true;
  }
}

class FormatColor extends BuiltinFunction {
  FormatColor([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Wraps a colour hex string in terminal ANSI escape codes.',
    params: [
      DocParam('hex', 'string',
          'Hex colour string such as "#6366f1" or "#fff".'),
    ],
    returns: 'A string with the ANSI-wrapped colour for terminal display.',
    category: 'plugin_api',
    example: 'local red = plugin_api.formatColor("#ff0000")',
  );

  @override
  Object? call(List<Object?> args) {
    final hex = args.isNotEmpty ? args[0] as String? : '#000000';
    if (hex == null) return '\x1b[0m';
    return '\x1b[38;5;39m$hex\x1b[0m';
  }
}

// ---------------------------------------------------------------------------
// ValueClass — a Lua-side constructor
// ---------------------------------------------------------------------------

/// Lua-side class returned by `plugin_api.newConfig()`.
///
/// `config:set("key", value)` / `config:get("key")` work,
/// and `tostring(config)` dumps the entries.
final ValueClass configClass = ValueClass.create({
  '__tostring': (Object? self) {
    if (self is Map) {
      return self.entries
          .map((e) => '  ${e.key}: ${e.value}')
          .join('\n');
    }
    return '(empty config)';
  },
  '__index': (Object? self, Object? key) {
    if (self is Map && key is String) {
      if (key == 'set') {
        return (List<Object?> args) {
          if (args.length >= 2) {
            self[args[0]] = args[1];
          }
        };
      }
      if (key == 'get') {
        return (List<Object?> args) {
          if (args.isNotEmpty && args[0] is String) {
            return self[args[0]];
          }
          return null;
        };
      }
      return self[key];
    }
    return null;
  },
});
