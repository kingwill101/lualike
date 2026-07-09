import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

/// A test backend that stores files in a [Map] and tracks call counts.
class _TestBackend implements FileSystemBackend {
  final Map<String, String> files;
  final Map<String, List<String>> directories;
  final String name;
  var fileExistsCalls = 0;
  var readCalls = 0;

  _TestBackend({this.name = '', Map<String, String>? files})
    : files = Map.of(files ?? {}),
      directories = <String, List<String>>{};

  void addDirectory(String path, [List<String>? children]) {
    directories[path] = children ?? <String>[];
    for (final child in (children ?? <String>[])) {
      if (!child.endsWith('/')) {
        files[child] = '';
      }
    }
  }

  @override
  Future<bool> fileExists(String path) async {
    fileExistsCalls++;
    return files.containsKey(path);
  }

  @override
  Future<bool> directoryExists(String path) async {
    return directories.containsKey(path);
  }

  @override
  Future<String?> readFileAsString(String path) async {
    readCalls++;
    if (!readFileSuccess) return null;
    return files[path];
  }

  bool readFileSuccess = true;

  @override
  Future<List<int>?> readFileAsBytes(String path) async {
    final content = files[path];
    return content?.codeUnits;
  }

  @override
  Future<DateTime?> getLastModified(String path) async => null;

  @override
  String? getCurrentDirectory() => '/test';

  @override
  Future<bool> createDirectory(String path, {bool recursive = true}) async {
    directories[path] = <String>[];
    return true;
  }

  @override
  Future<void> writeFile(String path, String content) async {
    files[path] = content;
  }

  @override
  Future<List<String>> listDirectory(String path) async {
    final dir = directories[path];
    return dir ?? <String>[];
  }

  @override
  Future<int?> fileSize(String path) async {
    final content = files[path];
    return content?.length;
  }

  @override
  Future<void> deleteFile(String path) async {
    if (!files.containsKey(path)) {
      throw Exception('File not found: $path');
    }
    files.remove(path);
  }

  @override
  Future<bool> deletePath(String path, {bool recursive = true}) async {
    return files.remove(path) != null || directories.remove(path) != null;
  }

  @override
  Future<void> renameFile(String oldPath, String newPath) async {
    if (!files.containsKey(oldPath)) {
      throw Exception('File not found: $oldPath');
    }
    final content = files.remove(oldPath)!;
    files[newPath] = content;
  }

  void resetCounts() {
    fileExistsCalls = 0;
    readCalls = 0;
    readFileSuccess = true;
  }
}

void main() {
  group('CompositeFileSystemBackend', () {
    late _TestBackend alpha;
    late _TestBackend beta;
    late CompositeFileSystemBackend composite;

    setUp(() {
      alpha = _TestBackend(
        name: 'alpha',
        files: {'only_in_alpha.txt': 'from alpha', 'shared.txt': 'from alpha'},
      );
      beta = _TestBackend(
        name: 'beta',
        files: {'only_in_beta.txt': 'from beta', 'shared.txt': 'from beta'},
      );
      composite = CompositeFileSystemBackend([alpha, beta]);
    });

    group('reads (first-wins)', () {
      test('fileExists returns true if any backend has the file', () async {
        expect(await composite.fileExists('only_in_alpha.txt'), isTrue);
        expect(await composite.fileExists('only_in_beta.txt'), isTrue);
        expect(await composite.fileExists('nonexistent.txt'), isFalse);
      });

      test('fileExists stops at first match', () async {
        expect(await composite.fileExists('shared.txt'), isTrue);
        expect(alpha.fileExistsCalls, 1);
        expect(beta.fileExistsCalls, 0);
      });

      test(
        'readFileAsString returns content from first matching backend',
        () async {
          expect(
            await composite.readFileAsString('only_in_alpha.txt'),
            equals('from alpha'),
          );
          expect(
            await composite.readFileAsString('only_in_beta.txt'),
            equals('from beta'),
          );
          expect(
            await composite.readFileAsString('shared.txt'),
            equals('from alpha'),
          );
        },
      );

      test(
        'readFileAsString returns null when no backend has the file',
        () async {
          expect(await composite.readFileAsString('nonexistent.txt'), isNull);
        },
      );

      test('readFileAsString falls through when first backend fails', () async {
        alpha.readFileSuccess = false;
        expect(
          await composite.readFileAsString('shared.txt'),
          equals('from beta'),
        );
        expect(alpha.readCalls, 1);
        expect(beta.readCalls, 1);
      });

      test(
        'readFileAsBytes returns bytes from first matching backend',
        () async {
          final bytes = await composite.readFileAsBytes('only_in_alpha.txt');
          expect(bytes, isNotNull);
          expect(String.fromCharCodes(bytes!), equals('from alpha'));
        },
      );

      test('directoryExists returns true if any backend has the dir', () async {
        alpha.addDirectory('/data');
        expect(await composite.directoryExists('/data'), isTrue);
        expect(await composite.directoryExists('/nonexistent'), isFalse);
      });

      test(
        'listDirectory returns entries from first non-empty backend',
        () async {
          alpha.addDirectory('/empty', []);
          beta.addDirectory('/empty', ['beta_file.txt']);
          final entries = await composite.listDirectory('/empty');
          expect(entries, equals(['beta_file.txt']));
        },
      );

      test('fileSize returns size from first matching backend', () async {
        final size = await composite.fileSize('only_in_alpha.txt');
        expect(size, equals('from alpha'.length));
      });

      test('getCurrentDirectory returns first non-null result', () async {
        expect(composite.getCurrentDirectory(), equals('/test'));
      });

      test('getLastModified returns first non-null result', () async {
        expect(await composite.getLastModified('any.txt'), isNull);
      });
    });

    group('writes (try-all)', () {
      test('writeFile writes to first backend that succeeds', () async {
        await composite.writeFile('new.txt', 'new content');
        expect(alpha.files['new.txt'], equals('new content'));
        expect(beta.files['new.txt'], isNull);
      });

      test('createDirectory creates on first writable backend', () async {
        expect(await composite.createDirectory('/new_dir'), isTrue);
        expect(alpha.directories, contains('/new_dir'));
      });

      test('deleteFile removes from first backend that has the file', () async {
        await composite.deleteFile('only_in_beta.txt');
        expect(beta.files, isNot(contains('only_in_beta.txt')));
      });

      test('deletePath removes from first backend that has the path', () async {
        await composite.deletePath('only_in_alpha.txt');
        expect(alpha.files, isNot(contains('only_in_alpha.txt')));
      });

      test(
        'renameFile moves within the first backend that has the file',
        () async {
          await composite.renameFile('only_in_beta.txt', 'moved.txt');
          expect(beta.files, isNot(contains('only_in_beta.txt')));
          expect(beta.files['moved.txt'], equals('from beta'));
        },
      );
    });

    group('edge cases', () {
      test('empty backend list', () async {
        final empty = CompositeFileSystemBackend([]);
        expect(await empty.fileExists('any.txt'), isFalse);
        expect(await empty.readFileAsString('any.txt'), isNull);
        expect(await empty.readFileAsBytes('any.txt'), isNull);
        expect(await empty.directoryExists('/any'), isFalse);
        expect(await empty.listDirectory('/any'), isEmpty);
        expect(await empty.fileSize('any.txt'), isNull);
        expect(await empty.getLastModified('any.txt'), isNull);
        expect(empty.getCurrentDirectory(), isNull);
        expect(await empty.createDirectory('/d'), isFalse);
      });

      test('single backend delegates', () async {
        final single = CompositeFileSystemBackend([alpha]);
        expect(await single.fileExists('only_in_alpha.txt'), isTrue);
        expect(await single.fileExists('only_in_beta.txt'), isFalse);
        expect(
          await single.readFileAsString('only_in_alpha.txt'),
          equals('from alpha'),
        );
      });

      test('three backends chain correctly', () async {
        final gamma = _TestBackend(
          name: 'gamma',
          files: {'gamma_only.txt': 'from gamma'},
        );
        final triple = CompositeFileSystemBackend([alpha, beta, gamma]);
        expect(
          await triple.readFileAsString('gamma_only.txt'),
          equals('from gamma'),
        );
        expect(
          await triple.readFileAsString('only_in_alpha.txt'),
          equals('from alpha'),
        );
      });

      test('fileExists short-circuits on first match', () async {
        await composite.fileExists('shared.txt');
        expect(alpha.fileExistsCalls, 1);
        expect(beta.fileExistsCalls, 0);
      });
    });
  });
}
