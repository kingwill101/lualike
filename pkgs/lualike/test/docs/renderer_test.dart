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

      expect(decoded['schemaVersion'], 1);
      expect(decoded['generator'], 'lualike.docs');
      expect(decoded['package'], 'sample_runtime');

      final librariesJson = decoded['libraries']! as List<Object?>;
      final sample = librariesJson.cast<Map<String, Object?>>().singleWhere(
        (library) => library['name'] == 'sample',
      );
      final functions = sample['functions']! as List<Object?>;
      final echo = functions.cast<Map<String, Object?>>().singleWhere(
        (function) => function['name'] == 'sample.echo',
      );

      expect(echo['signature'], 'sample.echo value');
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
      expect(
        annotations,
        contains('---@param value any # Value to return.'),
      );
      expect(
        annotations,
        contains('---@return any # The original value.'),
      );
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
  });
}

class _SampleLibrary extends Library {
  @override
  String get name => 'sample';

  @override
  String get description => 'Test-only sample library.';

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    context.define('echo', (List<Object?> args) {
      return args.isEmpty ? null : args.first;
    });
    context.describe(
      'sample.echo',
      const FunctionDoc(
        summary: 'Returns the provided value.',
        params: [DocParam('value', 'any', 'Value to return.')],
        returns: 'The original value.',
        category: 'sample',
      ),
    );
    context.define('setRole', (List<Object?> args) {
      return null;
    });
    context.describe(
      'setRole',
      const FunctionDoc(
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
      ),
    );
  }
}
