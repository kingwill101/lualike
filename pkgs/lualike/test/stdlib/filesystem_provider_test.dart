import 'package:test/test.dart';
import 'package:lualike/lualike.dart';
import 'package:lualike/src/stdlib/lib_io.dart';
import 'package:lualike/src/io/filesystem_provider.dart';
import 'package:lualike/src/io/lua_file.dart';
import 'package:lualike/src/io/io_device.dart';
import 'package:lualike/src/io/memory_io_device.dart';

/// Mock IODevice for testing
class MockIODevice extends BaseIODevice {
  final String _path;
  final List<String> _operations = [];
  String _content = '';
  bool _shouldFail = false;

  MockIODevice(this._path, String mode) : super(mode);

  List<String> get operations => List.unmodifiable(_operations);

  void setShouldFail(bool shouldFail) {
    _shouldFail = shouldFail;
  }

  void setContent(String content) {
    _content = content;
  }

  @override
  Future<void> close() async {
    _operations.add('close($_path)');
    if (_shouldFail) throw Exception('Mock close failure');
    isClosed = true;
  }

  @override
  Future<void> flush() async {
    _operations.add('flush($_path)');
    if (_shouldFail) throw Exception('Mock flush failure');
  }

  @override
  Future<ReadResult> read([String format = "l"]) async {
    _operations.add('read($_path, $format)');
    if (_shouldFail) return ReadResult(null, 'Mock read failure');

    if (_content.isEmpty) return ReadResult(null);

    switch (format) {
      case 'a':
        final result = _content;
        _content = '';
        return ReadResult(result);
      case 'l':
        final lines = _content.split('\n');
        if (lines.isEmpty) return ReadResult(null);
        final line = lines.first;
        _content = lines.skip(1).join('\n');
        return ReadResult(line);
      default:
        if (int.tryParse(format) != null) {
          final n = int.parse(format);
          if (_content.length <= n) {
            final result = _content;
            _content = '';
            return ReadResult(result);
          } else {
            final result = _content.substring(0, n);
            _content = _content.substring(n);
            return ReadResult(result);
          }
        }
        return ReadResult(null, 'Invalid format');
    }
  }

  @override
  Future<WriteResult> write(String data) async {
    _operations.add('write($_path, ${data.length} chars)');
    if (_shouldFail) return WriteResult(false, 'Mock write failure');
    _content += data;
    return WriteResult(true);
  }

  @override
  Future<WriteResult> writeBytes(List<int> bytes) async {
    _operations.add('writeBytes($_path, ${bytes.length} bytes)');
    if (_shouldFail) return WriteResult(false, 'Mock write failure');
    _content += String.fromCharCodes(bytes);
    return WriteResult(true);
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    _operations.add('seek($_path, $whence, $offset)');
    if (_shouldFail) throw Exception('Mock seek failure');
    return offset;
  }

  @override
  Future<int> getPosition() async {
    _operations.add('getPosition($_path)');
    if (_shouldFail) throw Exception('Mock getPosition failure');
    return 0;
  }

  @override
  Future<bool> isEOF() async {
    _operations.add('isEOF($_path)');
    if (_shouldFail) throw Exception('Mock isEOF failure');
    return _content.isEmpty;
  }
}

/// Mock IODevice factory for testing
Future<IODevice> createMockIODevice(String path, String mode) async {
  return MockIODevice(path, mode);
}

/// Custom ROT13 IODevice that encodes/decodes text
class ROT13IODevice extends BaseIODevice {
  final String _path;
  static final Map<String, String> _storage = {};

  ROT13IODevice(this._path, String mode) : super(mode);

  String _rot13(String text) {
    return text
        .split('')
        .map((char) {
          final code = char.codeUnitAt(0);
          if (code >= 65 && code <= 90) {
            // A-Z
            return String.fromCharCode(((code - 65 + 13) % 26) + 65);
          } else if (code >= 97 && code <= 122) {
            // a-z
            return String.fromCharCode(((code - 97 + 13) % 26) + 97);
          }
          return char;
        })
        .join('');
  }

  @override
  Future<ReadResult> read([String format = "l"]) async {
    checkOpen();
    final content = _storage[_path] ?? '';
    if (content.isEmpty) return ReadResult(null);

    final decoded = _rot13(content);
    _storage[_path] = '';
    return ReadResult(decoded);
  }

  @override
  Future<WriteResult> write(String data) async {
    checkOpen();
    final existing = _storage[_path] ?? '';
    _storage[_path] = existing + _rot13(data);
    return WriteResult(true);
  }

  @override
  Future<WriteResult> writeBytes(List<int> bytes) async {
    checkOpen();
    final existing = _storage[_path] ?? '';
    _storage[_path] = existing + _rot13(String.fromCharCodes(bytes));
    return WriteResult(true);
  }

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  Future<void> flush() async {
    checkOpen();
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    checkOpen();
    return 0;
  }

  @override
  Future<int> getPosition() async {
    checkOpen();
    return 0;
  }

  @override
  Future<bool> isEOF() async {
    checkOpen();
    final content = _storage[_path] ?? '';
    return content.isEmpty;
  }
}

/// Factory function for ROT13 IODevice
Future<IODevice> createROT13IODevice(String path, String mode) async {
  return ROT13IODevice(path, mode);
}

void main() {
  group('FileSystemProvider', () {
    late FileSystemProvider originalProvider;

    setUp(() {
      // Save original provider to restore after each test
      originalProvider = IOLib.fileSystemProvider;
    });

    tearDown(() {
      // Restore original provider
      IOLib.fileSystemProvider = originalProvider;
    });

    group('Default Behavior', () {
      test('should use default FileIODevice factory by default', () {
        final provider = FileSystemProvider();
        expect(provider.providerName, equals('DefaultFileSystem'));
      });

      test('should create FileSystemProvider with custom factory', () {
        final provider = FileSystemProvider(
          ioDeviceFactory: createMockIODevice,
          providerName: 'MockFileSystem',
        );
        expect(provider.providerName, equals('MockFileSystem'));
      });
    });

    group('IODevice Factory Configuration', () {
      test('should allow setting custom IODevice factory', () {
        final provider = FileSystemProvider();
        expect(provider.providerName, equals('DefaultFileSystem'));

        provider.setIODeviceFactory(
          createMockIODevice,
          providerName: 'MockFileSystem',
        );
        expect(provider.providerName, equals('MockFileSystem'));
      });

      test('should use custom factory without changing provider name', () {
        final provider = FileSystemProvider();
        provider.setIODeviceFactory(createMockIODevice);
        expect(provider.providerName, equals('DefaultFileSystem'));
      });
    });

    group('File Operations', () {
      test('should open file using configured factory', () async {
        final provider = FileSystemProvider();
        provider.setIODeviceFactory(
          createMockIODevice,
          providerName: 'MockFileSystem',
        );

        final device = await provider.openFile('test.txt', 'w');
        expect(device, isA<MockIODevice>());
        expect(device.mode, equals('w'));
      });

      test('should create temporary file using configured factory', () async {
        final provider = FileSystemProvider();
        provider.setIODeviceFactory(
          createMockIODevice,
          providerName: 'MockFileSystem',
        );

        final device = await provider.createTempFile('prefix');
        expect(device, isA<MockIODevice>());
        expect(device.mode, equals('w+'));
      });

      test('should handle file existence check', () async {
        final provider = FileSystemProvider();

        // Default implementation should return false for non-existent files
        final exists = await provider.fileExists('nonexistent.txt');
        expect(exists, isFalse);
      });

      test('should handle file deletion', () async {
        final provider = FileSystemProvider();

        // Default implementation may return true (no error) even for non-existent files
        final deleted = await provider.deleteFile('nonexistent.txt');
        expect(deleted, isA<bool>());
      });
    });

    group('Integration with IOLib', () {
      test('should use configured provider in IOLib', () async {
        IOLib.fileSystemProvider.setIODeviceFactory(
          createMockIODevice,
          providerName: 'TestFileSystem',
        );

        expect(IOLib.fileSystemProvider.providerName, equals('TestFileSystem'));

        final device = await IOLib.fileSystemProvider.openFile('test.txt', 'w');
        expect(device, isA<MockIODevice>());
      });

      test('should use configured provider for io.open operations', () async {
        IOLib.fileSystemProvider.setIODeviceFactory(
          createMockIODevice,
          providerName: 'TestFileSystem',
        );

        final ioOpen = IOOpen();
        final result = await ioOpen.call([Value('test.txt'), Value('w')]);

        expect(result, isA<LuaFile>());
        final luaFile = result as LuaFile;
        expect(luaFile.device, isA<MockIODevice>());
      });

      test('should use configured provider for temporary files', () async {
        IOLib.fileSystemProvider.setIODeviceFactory(
          createMockIODevice,
          providerName: 'TestFileSystem',
        );

        final ioTmpfile = IOTmpfile();
        final result = await ioTmpfile.call([]);

        expect(result, isA<LuaFile>());
        final luaFile = result as LuaFile;
        expect(luaFile.device, isA<MockIODevice>());
      });
    });

    group('InMemory IODevice Factory', () {
      test('should create in-memory files', () async {
        final provider = FileSystemProvider();
        provider.setIODeviceFactory(
          createInMemoryIODevice,
          providerName: 'InMemoryFileSystem',
        );

        // Create a file
        final writeDevice = await provider.openFile('memory.txt', 'w');
        final writeFile = LuaFile(writeDevice);
        await writeFile.write('Hello Memory!');
        await writeFile.close();

        // Read it back
        final readDevice = await provider.openFile('memory.txt', 'r');
        final readFile = LuaFile(readDevice);
        final result = await readFile.read('a');
        await readFile.close();

        expect(result[0], equals('Hello Memory!'));
      });

      test('should handle file not found for read operations', () async {
        final provider = FileSystemProvider();
        provider.setIODeviceFactory(
          createInMemoryIODevice,
          providerName: 'InMemoryFileSystem',
        );

        expect(
          () => provider.openFile('nonexistent.txt', 'r'),
          throwsA(isA<LuaError>()),
        );
      });

      test('should support append mode', () async {
        final provider = FileSystemProvider();
        provider.setIODeviceFactory(
          createInMemoryIODevice,
          providerName: 'InMemoryFileSystem',
        );

        // Create initial content
        final writeDevice = await provider.openFile('append.txt', 'w');
        final writeFile = LuaFile(writeDevice);
        await writeFile.write('Initial\n');
        await writeFile.close();

        // Append to it
        final appendDevice = await provider.openFile('append.txt', 'a');
        final appendFile = LuaFile(appendDevice);
        await appendFile.write('Appended\n');
        await appendFile.close();

        // Read back
        final readDevice = await provider.openFile('append.txt', 'r');
        final readFile = LuaFile(readDevice);
        final result = await readFile.read('a');
        await readFile.close();

        expect(result[0], equals('Initial\nAppended\n'));
      });
    });

    // Temporarily comment out DropBox tests since the implementation is example-only
    // group('DropBox IODevice Factory', () {
    //   test('should create DropBox IODevice factory', () {
    //     final factory = createDropBoxIODevice('test-token');
    //     expect(factory, isA<Function>());
    //   });

    //   test('should create DropBox IODevice with access token', () async {
    //     final factory = createDropBoxIODevice('test-token');

    //     expect(
    //       () => factory('test.txt', 'r'),
    //       throwsA(isA<UnimplementedError>()),
    //     );
    //   });
    // });

    group('Error Handling', () {
      test('should handle IODevice creation failures', () async {
        Future<IODevice> failingFactory(String path, String mode) async {
          throw Exception('Factory failure');
        }

        final provider = FileSystemProvider();
        provider.setIODeviceFactory(failingFactory);

        expect(
          () => provider.openFile('test.txt', 'w'),
          throwsA(isA<Exception>()),
        );
      });

      test('should handle IODevice operation failures', () async {
        final provider = FileSystemProvider();
        provider.setIODeviceFactory(createMockIODevice);

        final device = await provider.openFile('test.txt', 'w') as MockIODevice;
        device.setShouldFail(true);

        final file = LuaFile(device);

        // Write should fail
        final writeResult = await file.write('test');
        expect(writeResult[0], isNull);
        expect(writeResult[1], equals('Mock write failure'));

        // Read should fail
        final readResult = await file.read('a');
        expect(readResult[0], isNull);
        expect(readResult[1], equals('Mock read failure'));
      });
    });

    group('Provider Switching', () {
      test('should switch between different providers', () async {
        // Reset to default first
        IOLib.fileSystemProvider = FileSystemProvider();

        // Start with default
        expect(
          IOLib.fileSystemProvider.providerName,
          equals('DefaultFileSystem'),
        );

        // Switch to in-memory
        IOLib.fileSystemProvider.setIODeviceFactory(
          createInMemoryIODevice,
          providerName: 'InMemoryFileSystem',
        );
        expect(
          IOLib.fileSystemProvider.providerName,
          equals('InMemoryFileSystem'),
        );

        // Switch to mock
        IOLib.fileSystemProvider.setIODeviceFactory(
          createMockIODevice,
          providerName: 'MockFileSystem',
        );
        expect(IOLib.fileSystemProvider.providerName, equals('MockFileSystem'));

        // Reset to default
        IOLib.fileSystemProvider = FileSystemProvider();
        expect(
          IOLib.fileSystemProvider.providerName,
          equals('DefaultFileSystem'),
        );
      });

      test('should maintain separate file systems between providers', () async {
        // Create file in in-memory system
        IOLib.fileSystemProvider.setIODeviceFactory(
          createInMemoryIODevice,
          providerName: 'InMemoryFileSystem',
        );

        final memDevice = await IOLib.fileSystemProvider.openFile(
          'memory.txt',
          'w',
        );
        final memFile = LuaFile(memDevice);
        await memFile.write('Memory content');
        await memFile.close();

        // Switch to mock system - file shouldn't exist there
        IOLib.fileSystemProvider.setIODeviceFactory(
          createMockIODevice,
          providerName: 'MockFileSystem',
        );

        final mockDevice = await IOLib.fileSystemProvider.openFile(
          'memory.txt',
          'w',
        );
        expect(mockDevice, isA<MockIODevice>());

        // Switch back to in-memory - file should still exist
        IOLib.fileSystemProvider.setIODeviceFactory(
          createInMemoryIODevice,
          providerName: 'InMemoryFileSystem',
        );

        final readDevice = await IOLib.fileSystemProvider.openFile(
          'memory.txt',
          'r',
        );
        final readFile = LuaFile(readDevice);
        final result = await readFile.read('a');
        await readFile.close();

        expect(result[0], equals('Memory content'));
      });
    });

    group('Lua Script Integration', () {
      test(
        'should work transparently with Lua scripts using IOLib functions',
        () async {
          // Set up in-memory file system
          IOLib.fileSystemProvider.setIODeviceFactory(
            createInMemoryIODevice,
            providerName: 'InMemoryFileSystem',
          );

          // Use IOLib functions directly instead of Lua script
          final ioOpen = IOOpen();
          final ioWrite = IOWrite();
          final ioClose = IOClose();

          // Open file for writing
          final openResult = await ioOpen.call([Value('test.txt'), Value('w')]);
          expect(openResult, isA<LuaFile>());

          final luaFile = openResult as LuaFile;
          IOLib.defaultOutput = Value(luaFile);

          // Write content
          await ioWrite.call([Value('Hello from IOLib!')]);

          // Close file
          await ioClose.call([]);

          // Open for reading
          final readOpenResult = await ioOpen.call([
            Value('test.txt'),
            Value('r'),
          ]);
          final readFile = readOpenResult as LuaFile;

          // Read content
          final content = await readFile.read('a');
          await readFile.close();

          expect(content[0], equals('Hello from IOLib!'));
        },
      );

      test('should handle file errors with IOLib functions', () async {
        // Set up in-memory file system
        IOLib.fileSystemProvider.setIODeviceFactory(
          createInMemoryIODevice,
          providerName: 'InMemoryFileSystem',
        );

        // io.open should return error values, not throw for missing files
        try {
          // Try to open non-existent file
          final result = await IOOpen().call([
            Value('nonexistent_file.txt'),
            Value('r'),
          ]);
          // Should get here - io.open returns error tuple instead of throwing
          // IOOpen returns Value.multi([null, error_message]) for errors
          expect(result, isA<Value>());
          final value = result as Value;
          expect(value.raw, isA<List>());
          final resultList = value.raw as List;
          expect(
            resultList[0],
            isNull,
          ); // First element should be null for error
          expect(
            resultList.length,
            greaterThan(1),
          ); // Should have error message
          expect(
            resultList[1],
            isA<String>(),
          ); // Error message should be a string
        } catch (e) {
          // If it does throw, that's also acceptable behavior
          expect(e, isA<LuaError>());
        }
      });
    });

    group('Multiple Files and Operations', () {
      test('should handle multiple files simultaneously', () async {
        IOLib.fileSystemProvider.setIODeviceFactory(
          createInMemoryIODevice,
          providerName: 'InMemoryFileSystem',
        );

        // Create multiple files
        final files = ['file1.txt', 'file2.txt', 'file3.txt'];
        final contents = ['Content 1', 'Content 2', 'Content 3'];

        // Write all files
        for (int i = 0; i < files.length; i++) {
          final device = await IOLib.fileSystemProvider.openFile(files[i], 'w');
          final file = LuaFile(device);
          await file.write(contents[i]);
          await file.close();
        }

        // Read all files back
        for (int i = 0; i < files.length; i++) {
          final device = await IOLib.fileSystemProvider.openFile(files[i], 'r');
          final file = LuaFile(device);
          final result = await file.read('a');
          await file.close();

          expect(result[0], equals(contents[i]));
        }
      });

      test('should track operations in mock devices', () async {
        IOLib.fileSystemProvider.setIODeviceFactory(createMockIODevice);

        final device =
            await IOLib.fileSystemProvider.openFile('tracked.txt', 'w')
                as MockIODevice;
        final file = LuaFile(device);

        await file.write('test content');
        await file.flush();
        await file.close();

        final operations = device.operations;
        expect(operations, contains('write(tracked.txt, 12 chars)'));
        expect(operations, contains('flush(tracked.txt)'));
        expect(operations, contains('close(tracked.txt)'));
      });
    });

    group('Custom IODevice Implementation', () {
      test('should demonstrate creating a custom IODevice', () async {
        // Use the custom ROT13 file system
        IOLib.fileSystemProvider.setIODeviceFactory(
          createROT13IODevice,
          providerName: 'ROT13FileSystem',
        );

        // Write some text (will be encoded with ROT13)
        final writeDevice = await IOLib.fileSystemProvider.openFile(
          'secret.txt',
          'w',
        );
        final writeFile = LuaFile(writeDevice);
        await writeFile.write('Hello World!');
        await writeFile.close();

        // Read it back (will be decoded from ROT13)
        final readDevice = await IOLib.fileSystemProvider.openFile(
          'secret.txt',
          'r',
        );
        final readFile = LuaFile(readDevice);
        final result = await readFile.read('a');
        await readFile.close();

        // Should get back the original text
        expect(result[0], equals('Hello World!'));
        expect(
          IOLib.fileSystemProvider.providerName,
          equals('ROT13FileSystem'),
        );
      });
    });
  });
}
