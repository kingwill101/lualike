import 'dart:convert';

import 'package:lualike/docs.dart';
import 'package:lualike/library_builder.dart';
import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  group('documentation rendering', () {
    test('renders a complete shared HTML page for any registered library', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final html = renderDocsPage(
        libraries,
        options: const DocPageOptions(
          title: 'Custom API Reference',
          brandName: 'Custom Runtime',
        ),
      );

      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('<title>Custom API Reference</title>'));
      expect(html, contains('Custom Runtime'));
      expect(html, contains('sample.echo'));
      expect(html, contains('function setExpanded'));
      expect(html, contains('class="sidebar"'));
    });

    test('emits a JSON manifest editors can consume', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final decoded =
          jsonDecode(renderDocsJson(libraries, packageName: 'sample_runtime'))
              as Map<String, Object?>;

      expect(decoded['schemaVersion'], 2);
      expect(decoded['generator'], 'lualike.docs');
      expect(decoded['package'], 'sample_runtime');

      final librariesJson = decoded['libraries']! as List<Object?>;
      final sample = librariesJson.cast<Map<String, Object?>>().singleWhere(
        (library) => library['name'] == 'sample',
      );
      final functions = sample['functions']! as List<Object?>;
      final echo = functions.cast<Map<String, Object?>>().singleWhere(
        (function) => function['name'] == 'echo',
      );

      expect(echo['signature'], 'echo value');
      expect(echo['qualifiedName'], 'sample.echo');
      expect(echo['summary'], 'Returns the provided value.');
      expect(echo['returns'], 'The original value.');
      expect(echo['kind'], 'function');

      final params = echo['params']! as List<Object?>;
      expect((params.single as Map<String, Object?>)['name'], 'value');
    });

    test('emits LuaLS annotation stubs existing Lua LSPs can index', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final annotations = renderLuaLsAnnotations(
        libraries,
        packageName: 'sample_runtime',
      );

      expect(annotations, contains('---@meta _'));
      expect(annotations, contains('---Generator: lualike.docs'));
      expect(annotations, contains('---@type table\nsample = sample or {}'));
      expect(annotations, contains('---Returns the provided value.'));
      expect(annotations, contains('---@param value any # Value to return.'));
      expect(annotations, contains('---@return any # The original value.'));
      expect(annotations, contains('function sample.echo(value) end'));
    });

    test('LuaLS annotation stubs include standard library tables', () {
      final lua = LuaLike();

      final annotations = renderLuaLsAnnotations(
        documentedLibrariesForRuntime(lua.vm),
      );

      expect(annotations, contains('---@type table\nmath = math or {}'));
      expect(annotations, contains('function math.type(x) end'));
      expect(annotations, contains('function debug.getmetatable(v) end'));
      expect(annotations, contains('---@param v any'));
      expect(annotations, contains('---@param thread? thread'));
    });

    test('initializes lazy standard libraries before collecting docs', () {
      final lua = LuaLike();

      final libraries = documentedLibrariesForRuntime(lua.vm);
      final manifest = buildDocsManifest(libraries);
      final libraryNames = (manifest['libraries']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .map((library) => library['name'])
          .toSet();

      expect(
        libraryNames,
        containsAll(<String>{'base', 'package', 'math', 'string'}),
      );
    });

    test('renders unique section and function ids for duplicate names', () {
      final lua = LuaLike();

      final html = renderDocsPage(documentedLibrariesForRuntime(lua.vm));
      final ids = RegExp(
        ' id="([^"]+)"',
      ).allMatches(html).map((match) => match.group(1)!).toList();

      expect(ids, isNotEmpty);
      expect(ids.toSet(), hasLength(ids.length));
      expect(html, contains('href="#math.type"'));
      expect(html, contains('href="#debug.getmetatable"'));
    });

    test('LuaLS renderer emits @deprecated annotation', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final annotations = renderLuaLsAnnotations(libraries);
      expect(annotations, contains('---@deprecated'));
      expect(annotations, contains('---This function is deprecated.'));
    });

    test('LuaLS renderer emits @async annotation', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final annotations = renderLuaLsAnnotations(libraries);
      expect(annotations, contains('---@async'));
    });

    test('LuaLS renderer emits @nodiscard annotation', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final annotations = renderLuaLsAnnotations(libraries);
      expect(annotations, contains('---@nodiscard'));
    });

    test('LuaLS renderer emits @generic annotation', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final annotations = renderLuaLsAnnotations(libraries);
      expect(annotations, contains('---@generic T : integer'));
    });

    test('LuaLS renderer emits @see annotation', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final annotations = renderLuaLsAnnotations(libraries);
      expect(annotations, contains('---@see http.get'));
    });

    test('LuaLS renderer emits @version annotation', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final annotations = renderLuaLsAnnotations(libraries);
      expect(annotations, contains('---@version >5.2, JIT'));
    });

    test('LuaLS renderer emits scope annotations', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final annotations = renderLuaLsAnnotations(libraries);
      expect(annotations, contains('---@private'));
    });

    test('LuaLS renderer emits @overload annotations', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final annotations = renderLuaLsAnnotations(libraries);
      expect(annotations, contains('---@overload fun(name: string): boolean'));
    });

    test('LuaLS renderer emits @alias blocks', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final annotations = renderLuaLsAnnotations(libraries);
      expect(annotations, contains('---@alias DeviceSide'));
      expect(annotations, contains("---| 'left' # The left side"));
      expect(annotations, contains("---| 'right' # The right side"));
    });

    test('LuaLS renderer emits @enum blocks', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final annotations = renderLuaLsAnnotations(libraries);
      expect(annotations, contains('---@enum colors'));
      expect(annotations, contains('  black = 0,'));
      expect(annotations, contains('  red = 2,'));
      expect(annotations, contains('local colors = {'));
    });

    test('JSON manifest includes deprecated, async, nodiscard fields', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final decoded =
          jsonDecode(renderDocsJson(libraries, packageName: 'sample_runtime'))
              as Map<String, Object?>;

      final libs = decoded['libraries']! as List<Object?>;
      final sample = libs.cast<Map<String, Object?>>().firstWhere(
        (l) => l['name'] == 'sample',
      );
      final functions = sample['functions']! as List<Object?>;
      final deprecatedFunc = functions.cast<Map<String, Object?>>().firstWhere(
        (f) => f['name'] == 'oldApi',
      );

      expect(deprecatedFunc['deprecated'], isTrue);
      expect(deprecatedFunc['deprecatedReason'], 'Use newApi instead');
      expect(deprecatedFunc['async'], isTrue);
      expect(deprecatedFunc['nodiscard'], isTrue);
      expect(deprecatedFunc['scope'], 'private');
      expect(deprecatedFunc['see'], 'http.get');
      expect(deprecatedFunc['version'], '>5.2, JIT');

      final generics = deprecatedFunc['generics']! as List<Object?>;
      expect(generics.length, 1);
      expect((generics.single as Map<String, Object?>)['name'], 'T');
      expect(
        (generics.single as Map<String, Object?>)['parentType'],
        'integer',
      );
    });

    test('JSON manifest includes aliases and enums', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final decoded =
          jsonDecode(renderDocsJson(libraries, packageName: 'sample_runtime'))
              as Map<String, Object?>;

      final libs = decoded['libraries']! as List<Object?>;
      final sample = libs.cast<Map<String, Object?>>().firstWhere(
        (l) => l['name'] == 'sample',
      );

      expect(sample['aliases'], isA<List<Object?>>());
      expect(sample['enums'], isA<List<Object?>>());

      final aliases = sample['aliases']! as List<Object?>;
      final aliasNames = aliases.cast<Map<String, Object?>>().map(
        (a) => a['name'],
      );
      expect(aliasNames, contains('DeviceSide'));

      final enums = sample['enums']! as List<Object?>;
      final enumNames = enums.cast<Map<String, Object?>>().map(
        (e) => e['name'],
      );
      expect(enumNames, contains('colors'));
    });

    test('HTML renderer shows badges for deprecated, async, nodiscard', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final html = renderDocsPage(libraries);
      expect(html, contains('badge-deprecated'));
      expect(html, contains('badge-async'));
      expect(html, contains('badge-nodiscard'));
      expect(html, contains('badge-scope'));
    });

    test('LuaLS renderer includes @source annotation', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final annotations = renderLuaLsAnnotations(libraries);
      expect(annotations, contains('---@source'));
    });

    test('LuaLS renderer emits @operator on table docs', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_LibraryWithTableDoc());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final annotations = renderLuaLsAnnotations(libraries);
      expect(annotations, contains('---@class math_data.Vector'));
      expect(annotations, contains('---@operator add(Vector): Vector'));
      expect(annotations, contains('---@operator unm:integer'));
    });

    test('JSON manifest includes table docs with operators', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_LibraryWithTableDoc());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final decoded =
          jsonDecode(renderDocsJson(libraries, packageName: 'sample_runtime'))
              as Map<String, Object?>;

      final libs = decoded['libraries']! as List<Object?>;
      final data = libs.cast<Map<String, Object?>>().firstWhere(
        (l) => l['name'] == 'math_data',
      );

      expect(data['tables'], isA<List<Object?>>());
      final tables = data['tables']! as List<Object?>;
      final vector = tables.cast<Map<String, Object?>>().firstWhere(
        (t) => t['name'] == 'Vector',
      );

      expect(vector['operators'], isA<List<Object?>>());
    });

    test('LuaLS renderer emits @type for ValueDoc constants', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_LibraryWithValueDocs());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final annotations = renderLuaLsAnnotations(libraries);
      expect(annotations, contains('---The app version string.'));
      expect(annotations, contains('---@type string'));
      expect(annotations, contains('app_version = "1.0.0"'));
      expect(annotations, contains('---@type number'));
      expect(
        annotations,
        contains('sample_values.pi = sample_values.pi or {}'),
      );
    });

    test('JSON manifest includes values for ValueDoc', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_LibraryWithValueDocs());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final decoded =
          jsonDecode(renderDocsJson(libraries, packageName: 'sample_runtime'))
              as Map<String, Object?>;

      final libs = decoded['libraries']! as List<Object?>;
      final sample = libs.cast<Map<String, Object?>>().firstWhere(
        (l) => l['name'] == 'sample_values',
      );

      expect(sample['values'], isA<List<Object?>>());
      final values = sample['values']! as List<Object?>;
      final version = values.cast<Map<String, Object?>>().firstWhere(
        (v) => v['name'] == 'app_version',
      );
      expect(version['type'], 'string');
      expect(version['value'], '"1.0.0"');
      expect(version['summary'], 'The app version string.');
    });

    test('HTML renderer shows ValueDoc entries', () {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_LibraryWithValueDocs());
      final libraries = documentedLibrariesForRuntime(lua.vm);

      final html = renderDocsPage(libraries);
      expect(html, contains('app_version: string'));
      expect(html, contains('The app version string.'));
      expect(html, contains('"1.0.0"'));
    });
  });
}

class _LibraryWithTableDoc extends Library {
  @override
  String get name => 'math_data';

  @override
  String get description => 'Library with table docs.';

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    context.describeTable(
      'Vector',
      const TableDoc(
        name: 'Vector',
        description: 'A 2D vector.',
        fields: [
          FieldDoc(key: 'x', type: 'number', description: 'X coordinate.'),
          FieldDoc(key: 'y', type: 'number', description: 'Y coordinate.'),
        ],
        operators: [
          OperatorDoc(
            operation: 'add',
            paramType: 'Vector',
            returnType: 'Vector',
          ),
          OperatorDoc(operation: 'unm', returnType: 'integer'),
        ],
      ),
    );
    context.describe(
      'math_data.add',
      const FunctionDoc(
        summary: 'Adds two numbers.',
        params: [DocParam('a', 'number', 'First.')],
        returns: 'The sum.',
        category: 'math_data',
      ),
    );
  }
}

class _SampleLibrary extends Library {
  @override
  String get name => 'sample';

  @override
  String get description => 'Test-only sample library.';

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    context.define(
      'echo',
      FunctionDescriptor(
        summary: 'Returns the provided value.',
        params: [DocParam('value', 'any', 'Value to return.')],
        returns: 'The original value.',
        category: 'sample',
        rawValue: (List<Object?> args) => args.isEmpty ? null : args.first,
      ),
    );

    context.define(
      'setRole',
      FunctionDescriptor(
        summary: 'Sets a role flag.',
        params: [
          DocParam('role', 'string', 'Role name.'),
          DocParam(
            'isActive',
            'boolean',
            'Whether the role is active.',
            optional: true,
          ),
        ],
        category: 'sample',
        rawValue: (List<Object?> args) => null,
      ),
    );

    // Deprecated function with full annotations
    context.define(
      'oldApi',
      FunctionDescriptor(
        summary: 'This function is deprecated.',
        deprecated: true,
        deprecatedReason: 'Use newApi instead',
        async: true,
        nodiscard: true,
        scope: AccessScope.private,
        generics: [GenericParam(name: 'T', parentType: 'integer')],
        see: 'http.get',
        version: '>5.2, JIT',
        source: 'src/sample.lua:10:5',
        category: 'sample',
        rawValue: (List<Object?> args) => null,
      ),
    );

    // Overloaded function
    context.define(
      'find',
      FunctionDescriptor(
        summary: 'Finds an item.',
        params: [
          DocParam('id', 'integer', 'Item ID.'),
          DocParam('name', 'string', 'Item name.', optional: true),
        ],
        returns: 'The found item or nil.',
        overloads: [
          OverloadDoc(
            params: [DocParam('name', 'string', 'Search by name.')],
            returnType: 'boolean',
            returns: 'Whether found.',
          ),
        ],
        category: 'sample',
        rawValue: (List<Object?> args) => null,
      ),
    );

    // Aliases
    context.define(
      'DeviceSide',
      AliasDescriptor(
        name: 'DeviceSide',
        variants: [
          AliasVariant(value: 'left', description: 'The left side'),
          AliasVariant(value: 'right', description: 'The right side'),
        ],
      ),
    );

    // Simple alias
    context.define(
      'userID',
      AliasDescriptor(
        name: 'userID',
        type: 'integer',
        description: 'A user identifier.',
      ),
    );

    // Enums
    context.define(
      'colors',
      EnumDescriptor(
        name: 'colors',
        description: 'Standard color constants.',
        entries: {'black': '0', 'red': '2'},
      ),
    );
  }
}

class _LibraryWithValueDocs extends Library {
  @override
  String get name => 'sample_values';

  @override
  String get description => 'Library with value docs.';

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    context.define(
      'app_version',
      ConstantDescriptor(
        summary: 'The app version string.',
        type: 'string',
        value: '"1.0.0"',
        rawValue: '1.0.0',
      ),
    );

    context.define(
      'pi',
      ConstantDescriptor(
        summary: 'The value of π.',
        type: 'number',
        rawValue: 3.14,
      ),
    );
  }
}
