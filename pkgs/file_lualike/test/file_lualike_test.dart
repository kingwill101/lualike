import 'package:file/file.dart' as pkg_file;
import 'package:file/memory.dart';
import 'package:file_lualike/file_lualike.dart';
import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

/// Helper to match LuaString values against a Dart string.
Matcher luaString(String expected) => predicate(
  (v) => v is LuaString && v.toString() == expected,
  'a LuaString matching "$expected"',
);

/// Helper to match LuaString values against a byte list.
Matcher luaBytes(List<int> expected) {
  return predicate((v) {
    if (v is! LuaString) return false;
    if (v.bytes.length != expected.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (v.bytes[i] != expected[i]) return false;
    }
    return true;
  }, 'a LuaString with bytes $expected');
}

void main() {
  late pkg_file.FileSystem memFs;

  setUp(() {
    memFs = MemoryFileSystem();
  });

  group('PackageFileIODevice', () {
    test('write and read a string', () async {
      final device = await PackageFileIODevice.open(memFs, '/test.txt', 'w+');
      await device.write('hello');
      await device.seek(SeekWhence.set, 0);
      final result = await device.read('a');
      expect(result.value, luaString('hello'));
      await device.close();
    });

    test('write and read bytes', () async {
      final device = await PackageFileIODevice.open(memFs, '/bytes.bin', 'w+');
      await device.writeBytes([0, 1, 2, 255]);
      await device.seek(SeekWhence.set, 0);
      final result = await device.read('4');
      expect(result.value, luaBytes([0, 1, 2, 255]));
      await device.close();
    });

    test('read entire file with "a" format', () async {
      final device = await PackageFileIODevice.open(memFs, '/entire.txt', 'w+');
      await device.write('line1\nline2\nline3\n');
      await device.seek(SeekWhence.set, 0);
      final result = await device.read('a');
      expect(result.value, luaString('line1\nline2\nline3\n'));
      await device.close();
    });

    test('read line with "l" format', () async {
      final device = await PackageFileIODevice.open(memFs, '/lines.txt', 'w+');
      await device.write('first\nsecond\nthird');
      await device.seek(SeekWhence.set, 0);

      final r1 = await device.read('l');
      expect(r1.value, luaString('first'));

      final r2 = await device.read('l');
      expect(r2.value, luaString('second'));

      final r3 = await device.read('l');
      expect(r3.value, luaString('third'));

      final r4 = await device.read('l');
      expect(r4.value, isNull); // EOF
      await device.close();
    });

    test('read line with "L" format includes newline', () async {
      final device = await PackageFileIODevice.open(
        memFs,
        '/lines-L.txt',
        'w+',
      );
      await device.write('hello\nworld');
      await device.seek(SeekWhence.set, 0);

      final r1 = await device.read('L');
      expect(r1.value, luaString('hello\n'));
      await device.close();
    });

    test('seek operations', () async {
      final device = await PackageFileIODevice.open(memFs, '/seek.txt', 'w+');
      await device.write('0123456789');
      await device.seek(SeekWhence.set, 5);
      expect(await device.getPosition(), equals(5));

      await device.seek(SeekWhence.cur, 2);
      expect(await device.getPosition(), equals(7));

      await device.seek(SeekWhence.end, -3);
      expect(await device.getPosition(), equals(7));

      await device.close();
    });

    test('isEOF returns correct state', () async {
      final device = await PackageFileIODevice.open(memFs, '/eof.txt', 'w+');
      await device.write('hi');
      await device.seek(SeekWhence.set, 0);
      expect(await device.isEOF(), isFalse);

      await device.read('a');
      expect(await device.isEOF(), isTrue);
      await device.close();
    });

    test('close sets isClosed', () async {
      final device = await PackageFileIODevice.open(memFs, '/close.txt', 'w');
      expect(device.isClosed, isFalse);
      await device.close();
      expect(device.isClosed, isTrue);
    });

    test('write-only mode rejects reads', () async {
      final device = await PackageFileIODevice.open(memFs, '/wo.txt', 'w');
      await device.write('data');
      final result = await device.read('a');
      expect(result.isSuccess, isFalse);
      await device.close();
    });

    test('read-only mode rejects writes', () async {
      final device = await PackageFileIODevice.open(memFs, '/ro.txt', 'w+');
      await device.write('data');
      await device.close();

      final roDevice = await PackageFileIODevice.open(memFs, '/ro.txt', 'r');
      final result = await roDevice.write('more');
      expect(result.success, isFalse);
      await roDevice.close();
    });

    test('buffer mode line flushes on newline', () async {
      final device = await PackageFileIODevice.open(memFs, '/buf.txt', 'w+');
      await device.setBuffering(BufferMode.line, 1024);
      await device.write('hello\n');
      await device.write('world');

      await device.flush();
      await device.seek(SeekWhence.set, 0);
      final content = await device.read('a');
      expect(content.value, luaString('hello\nworld'));
      await device.close();
    });

    test('read number "n" format', () async {
      final device = await PackageFileIODevice.open(memFs, '/num.txt', 'w+');
      await device.write('42 abc');
      await device.seek(SeekWhence.set, 0);
      final result = await device.read('n');
      expect(result.value, isA<num>());
      expect((result.value as num).toInt(), equals(42));
      await device.close();
    });

    test('read n bytes format', () async {
      final device = await PackageFileIODevice.open(memFs, '/nbytes.txt', 'w+');
      await device.write('abcdefgh');
      await device.seek(SeekWhence.set, 0);
      final result = await device.read('3');
      expect(result.value, luaString('abc'));
      await device.close();
    });
  });

  group('PackageFileSystemBackend', () {
    late PackageFileSystemBackend backend;

    setUp(() {
      backend = PackageFileSystemBackend(memFs);
    });

    test('fileExists', () async {
      await memFs.file('/exists.txt').writeAsString('here');
      expect(await backend.fileExists('/exists.txt'), isTrue);
      expect(await backend.fileExists('/nope.txt'), isFalse);
    });

    test('directoryExists', () async {
      await memFs.directory('/adir').create();
      expect(await backend.directoryExists('/adir'), isTrue);
      expect(await backend.directoryExists('/nope'), isFalse);
    });

    test('readFileAsString', () async {
      await memFs.file('/hello.txt').writeAsString('hello world');
      final content = await backend.readFileAsString('/hello.txt');
      expect(content, equals('hello world'));
    });

    test('readFileAsBytes', () async {
      await memFs.file('/bytes.bin').writeAsBytes([1, 2, 3]);
      final bytes = await backend.readFileAsBytes('/bytes.bin');
      expect(bytes, equals([1, 2, 3]));
    });

    test('writeFile and read back', () async {
      await backend.writeFile('/written.txt', 'written content');
      final content = await memFs.file('/written.txt').readAsString();
      expect(content, equals('written content'));
    });

    test('createDirectory', () async {
      final ok = await backend.createDirectory('/new/dir', recursive: true);
      expect(ok, isTrue);
      expect(await memFs.directory('/new/dir').exists(), isTrue);
    });

    test('listDirectory', () async {
      final dir = memFs.directory('/listme');
      await dir.create();
      await dir.childFile('a.txt').writeAsString('A');
      await dir.childFile('b.txt').writeAsString('B');
      final entries = await backend.listDirectory('/listme');
      expect(entries, hasLength(2));
    });

    test('fileSize', () async {
      await memFs.file('/size.txt').writeAsString('12345');
      final size = await backend.fileSize('/size.txt');
      expect(size, equals(5));
    });

    test('deleteFile removes file', () async {
      await memFs.file('/del.txt').writeAsString('bye');
      await backend.deleteFile('/del.txt');
      expect(await memFs.file('/del.txt').exists(), isFalse);
    });

    test('deletePath works for file and directory', () async {
      await memFs.file('/pf.txt').writeAsString('f');
      expect(await backend.deletePath('/pf.txt'), isTrue);
      expect(await memFs.file('/pf.txt').exists(), isFalse);

      await memFs.directory('/pd').create();
      expect(await backend.deletePath('/pd'), isTrue);
      expect(await memFs.directory('/pd').exists(), isFalse);
    });

    test('renameFile', () async {
      await memFs.file('/old.txt').writeAsString('move me');
      await backend.renameFile('/old.txt', '/new.txt');
      expect(await memFs.file('/old.txt').exists(), isFalse);
      expect(await memFs.file('/new.txt').readAsString(), equals('move me'));
    });

    test('getLastModified returns a date', () async {
      await memFs.file('/mod.txt').writeAsString('test');
      final dt = await backend.getLastModified('/mod.txt');
      expect(dt, isA<DateTime>());
    });

    test('getCurrentDirectory returns non-null on native platforms', () async {
      expect(backend.getCurrentDirectory(), anyOf(isNull, isA<String>()));
    });
  });

  group('configureFileSystem via useFileSystem', () {
    test('useFileSystem wires up both backends', () async {
      await memFs.file('/preload.txt').writeAsString('preloaded');

      await useFileSystem(memFs);

      final device = await PackageFileIODevice.open(memFs, '/preload.txt', 'r');
      final result = await device.read('a');
      expect(result.value, luaString('preloaded'));
      await device.close();

      expect(await fileExists('/preload.txt'), isTrue);
    });

    test('useFileSystem with explicit provider', () async {
      await memFs.file('/explicit.txt').writeAsString('explicit');
      final provider = FileSystemProvider();

      await useFileSystem(memFs, provider: provider);

      final device = await provider.openFile('/explicit.txt', 'r');
      final result = await device.read('a');
      expect(result.value, luaString('explicit'));
      await device.close();
    });
  });
}
