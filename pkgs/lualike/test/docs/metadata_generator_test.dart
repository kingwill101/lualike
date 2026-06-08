import 'dart:convert';
import 'dart:io';

import 'package:lualike/docs.dart';
import 'package:lualike/library_builder.dart';
import 'package:lualike/lualike.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('lualike_meta_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  group('generateMetadata', () {
    test('writes combined JSON with stdlib and custom libraries', () async {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());

      await generateMetadata(
        lua,
        outputDir: tmpDir.path,
        formats: {MetadataFormat.json},
        packageName: 'test_pkg',
        packageVersion: '1.0.0',
      );

      final file = File(p.join(tmpDir.path, 'test_pkg.json'));
      expect(file.existsSync(), isTrue);

      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect(decoded['package'], 'test_pkg');
      expect(decoded['packageVersion'], '1.0.0');

      final libs = decoded['libraries']! as List<Object?>;
      final names = libs
          .cast<Map<String, Object?>>()
          .map((l) => l['name'])
          .toSet();
      expect(names, contains('sample'));
      expect(names, contains('math'));
    });

    test('writes combined LuaLS with stdlib and custom libraries', () async {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());

      await generateMetadata(
        lua,
        outputDir: tmpDir.path,
        formats: {MetadataFormat.luals},
        packageName: 'test_pkg',
      );

      final file = File(p.join(tmpDir.path, 'test_pkg.lua'));
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('---@meta _'));
      expect(content, contains('function sample.echo(value) end'));
      expect(content, contains('function math.type(x) end'));
    });

    test('writes combined HTML', () async {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());

      await generateMetadata(
        lua,
        outputDir: tmpDir.path,
        formats: {MetadataFormat.html},
        packageName: 'test_pkg',
        pageOptions: const DocPageOptions(title: 'Test API', brandName: 'Test'),
      );

      final file = File(p.join(tmpDir.path, 'test_pkg.html'));
      expect(file.existsSync(), isTrue);

      final html = file.readAsStringSync();
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('<title>Test API</title>'));
      expect(html, contains('sample.echo'));
    });

    test('writes all three formats at once', () async {
      final lua = LuaLike();

      await generateMetadata(
        lua,
        outputDir: tmpDir.path,
        packageName: 'test_pkg',
      );

      expect(File(p.join(tmpDir.path, 'test_pkg.html')).existsSync(), isTrue);
      expect(File(p.join(tmpDir.path, 'test_pkg.json')).existsSync(), isTrue);
      expect(File(p.join(tmpDir.path, 'test_pkg.lua')).existsSync(), isTrue);
    });

    test('excludeStdlib filters out built-in libraries', () async {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());

      await generateMetadata(
        lua,
        outputDir: tmpDir.path,
        formats: {MetadataFormat.json},
        includeStdlib: false,
        packageName: 'test_pkg',
      );

      final file = File(p.join(tmpDir.path, 'test_pkg.json'));
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final libs = decoded['libraries']! as List<Object?>;
      final names = libs
          .cast<Map<String, Object?>>()
          .map((l) => l['name'])
          .toSet();

      expect(names, contains('sample'));
      expect(names, isNot(contains('math')));
      expect(names, isNot(contains('string')));
      expect(names, isNot(contains('base')));
    });

    test('split writes one file per library', () async {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());

      await generateMetadata(
        lua,
        outputDir: tmpDir.path,
        formats: {MetadataFormat.json},
        split: true,
        includeStdlib: false,
        packageName: 'test_pkg',
      );

      final sampleFile = File(p.join(tmpDir.path, 'sample.json'));
      expect(sampleFile.existsSync(), isTrue);

      final decoded =
          jsonDecode(sampleFile.readAsStringSync()) as Map<String, Object?>;
      final libs = decoded['libraries']! as List<Object?>;
      expect(libs, hasLength(1));
      expect((libs.single as Map<String, Object?>)['name'], 'sample');
    });

    test('split with multiple formats writes per-library per-format', () async {
      final lua = LuaLike();
      lua.vm.libraryRegistry.register(_SampleLibrary());

      await generateMetadata(
        lua,
        outputDir: tmpDir.path,
        formats: {MetadataFormat.json, MetadataFormat.luals},
        split: true,
        includeStdlib: false,
        packageName: 'test_pkg',
      );

      expect(File(p.join(tmpDir.path, 'sample.json')).existsSync(), isTrue);
      expect(File(p.join(tmpDir.path, 'sample.lua')).existsSync(), isTrue);
    });

    test('creates output directory if missing', () async {
      final nested = p.join(tmpDir.path, 'a', 'b', 'c');
      final lua = LuaLike();

      await generateMetadata(
        lua,
        outputDir: nested,
        formats: {MetadataFormat.json},
        packageName: 'test_pkg',
      );

      expect(File(p.join(nested, 'test_pkg.json')).existsSync(), isTrue);
    });

    test('does nothing when formats is empty', () async {
      final lua = LuaLike();

      await generateMetadata(
        lua,
        outputDir: tmpDir.path,
        formats: {},
        packageName: 'test_pkg',
      );

      expect(tmpDir.listSync(), isEmpty);
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
  }
}
