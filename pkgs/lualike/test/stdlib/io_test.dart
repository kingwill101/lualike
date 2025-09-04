import 'dart:io';

import 'package:lualike/src/io/io_device.dart';
import 'package:lualike/src/io/lua_file.dart';
import 'package:lualike/src/io/memory_io_device.dart';
import 'package:lualike/src/io/filesystem_provider.dart';
import 'package:lualike/src/stdlib/lib_io.dart';
import 'package:lualike_test/test.dart';

void main() {
  group('IO library', () {
    late Directory tempDir;
    late String tempPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();
      tempPath = tempDir.path;
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    group('IODevice', () {
      test('FileIODevice basic operations', () async {
        final filePath = '$tempPath/test.txt';
        final device = await FileIODevice.open(filePath, 'w');

        // Write test
        var result = await device.write('Hello, World!\n');
        expect(result.success, true);

        // Seek to beginning
        await device.seek(SeekWhence.set, 0);

        // Read test
        var readResult = await device.read('l');
        expect(readResult.value, 'Hello, World!');

        // Close test
        await device.close();
        expect(device.isClosed, true);
      });

      test('StdinDevice operations', () async {
        final device = StdinDevice();

        // Cannot write to stdin
        var result = await device.write('test');
        expect(result.success, false);

        // Close doesn't affect actual stdin
        await device.close();
        expect(device.isClosed, true);
      });

      test('StdoutDevice operations', () async {
        final device = StdoutDevice(stdout, false);

        // Cannot read from stdout
        var readResult = await device.read();
        expect(readResult.error, isNotNull);

        // Write works
        var writeResult = await device.write('test');
        expect(writeResult.success, true);
      });
    });

    group('LuaFile', () {
      test('Basic file operations', () async {
        final filePath = '$tempPath/test.txt';
        final device = await FileIODevice.open(filePath, 'w');
        final file = LuaFile(device);

        // Write test
        var result = await file.write('Hello, World!\n');
        expect(result[0], true);

        // Seek to beginning
        result = await file.seek('set', 0);
        expect(result[0], 0);

        // Read test
        result = await file.read('l');
        expect(result[0], 'Hello, World!');

        // Close test
        result = await file.close();
        expect(result[0], true);
        expect(file.isClosed, true);
      });

      test('Lines iterator', () async {
        final filePath = '$tempPath/test.txt';
        final device = await FileIODevice.open(filePath, 'w');
        final file = LuaFile(device);

        // Write some lines
        await file.write('Line 1\nLine 2\nLine 3\n');
        await file.seek('set', 0);

        // Get lines iterator
        final iterator = await file.lines();
        expect(iterator, isA<Value>());

        // Read lines
        final lines = <String>[];
        final func = iterator.raw as Function;
        while (true) {
          final result = await func([]);
          if (result.raw == null) break;
          lines.add(result.raw as String);
        }

        expect(lines, ['Line 1', 'Line 2', 'Line 3']);
        await file.close();
      });
    });

    group('IOLib', () {
      setUp(() async {
        // Reset default streams
        await IOLib.reset();
      });

      tearDown(() async {
        await IOLib.reset();
      });

      test('Default streams', () {
        expect(IOLib.defaultInput, isNotNull);
        expect(IOLib.defaultOutput, isNotNull);
      });

      test('File operations', () async {
        final filePath = '$tempPath/test.txt';

        // Open file
        final openFunc = IOLib.functions['open'] as IOOpen;
        final file = await openFunc.call([Value(filePath), Value('w')]);
        expect(file, isA<Value>());
        expect((file as Value).raw, isA<LuaFile>());

        // Set file as default output
        final outputFunc = IOLib.functions['output'] as IOOutput;
        await outputFunc.call([file]);

        // Write to file
        final writeFunc = IOLib.functions['write'] as IOWrite;
        var result = await writeFunc.call([Value('Hello, World!\n')]);
        expect((result as Value).raw, isA<LuaFile>());

        // Close file
        final closeFunc = IOLib.functions['close'] as IOClose;
        result = await closeFunc.call([file]);
        expect((result as Value).raw[0], true);

        // Read file
        final inputFunc = IOLib.functions['input'] as IOInput;
        final readFile = await inputFunc.call([Value(filePath)]);
        expect(readFile, isA<Value>());

        final readFunc = IOLib.functions['read'] as IORead;
        result = await readFunc.call([Value('l')]);
        expect((result as Value).raw[0], 'Hello, World!');
      });

      test('Temporary file', () async {
        // Create temp file
        final tmpFunc = IOLib.functions['tmpfile'] as IOTmpfile;
        final file = await tmpFunc.call([]);
        expect(file, isA<Value>());
        expect((file as Value).raw, isA<LuaFile>());

        // Set temp file as default output
        final outputFunc = IOLib.functions['output'] as IOOutput;
        await outputFunc.call([file]);

        // Write to temp file (now the default output)
        final writeFunc = IOLib.functions['write'] as IOWrite;
        var result = await writeFunc.call([Value('Hello, World!\n')]);
        expect((result as Value).raw, isA<LuaFile>());

        // Close temp file
        final closeFunc = IOLib.functions['close'] as IOClose;
        result = await closeFunc.call([file]);
        expect((result as Value).raw[0], true);

        // Reset default output to stdout
        await outputFunc.call([]);
      });

      test('File type checking', () async {
        final typeFunc = IOLib.functions['type'] as IOType;

        // Non-file value
        var result = await typeFunc.call([Value(42)]);
        expect((result as Value).raw, null);

        // Open file
        final filePath = '$tempPath/test.txt';
        final openFunc = IOLib.functions['open'] as IOOpen;
        final file = await openFunc.call([Value(filePath), Value('w')]);

        // Open file type
        result = await typeFunc.call([file as Value]);
        expect((result as Value).raw, 'file');

        // Close file
        final closeFunc = IOLib.functions['close'] as IOClose;
        await closeFunc.call([file]);

        // Closed file type
        result = await typeFunc.call([file]);
        expect((result as Value).raw, 'closed file');
      });
    });

    group('InMemory FileSystem', () {
      setUp(() {
        // Set up in-memory file system for each test
        IOLib.fileSystemProvider.setIODeviceFactory(
          createInMemoryIODevice,
          providerName: 'WebInMemoryFileSystem',
        );
      });

      tearDown(() {
        // Clean up memory storage after each test
        InMemoryIODevice.clearMemoryStorage();
        // Reset to default provider
        IOLib.fileSystemProvider = FileSystemProvider();
      });

      test(
        'should write and read files using io.open in web environment',
        () async {
          final code = '''
        -- Write to a file
        local file = io.open("test.txt", "w")
        if file then
            file:write("Hello from LuaLike!\\n")
            file:write("This is a test file.\\n")
            file:close()
            print("File written successfully")
        else
            print("Could not open file for writing")
        end

        -- Read from a file
        file = io.open("test.txt", "r")
        if file then
            print("File contents:")
            for line in file:lines() do
                print(line)
            end
            file:close()
        else
            print("Could not open file for reading")
        end
      ''';

          await executeCode(code);

          // Verify that files are actually stored in memory
          final memoryFiles = InMemoryIODevice.getMemoryStorage();
          expect(memoryFiles.containsKey('test.txt'), isTrue);
          expect(
            memoryFiles['test.txt'],
            equals('Hello from LuaLike!\nThis is a test file.\n'),
          );
        },
      );

      test('should handle multiple files in memory', () async {
        final code = '''
        -- Create multiple files
        local file1 = io.open("file1.txt", "w")
        file1:write("Content of file 1")
        file1:close()

        local file2 = io.open("file2.txt", "w")
        file2:write("Content of file 2")
        file2:close()

        -- Read them back
        local f1 = io.open("file1.txt", "r")
        local content1 = f1:read("*a")
        f1:close()

        local f2 = io.open("file2.txt", "r")
        local content2 = f2:read("*a")
        f2:close()

        return content1, content2
      ''';

        await executeCode(code);

        // Verify both files exist in memory
        final memoryFiles = InMemoryIODevice.getMemoryStorage();
        expect(memoryFiles.containsKey('file1.txt'), isTrue);
        expect(memoryFiles.containsKey('file2.txt'), isTrue);
        expect(memoryFiles['file1.txt'], equals('Content of file 1'));
        expect(memoryFiles['file2.txt'], equals('Content of file 2'));
      });

      test('should support file append operations', () async {
        final code = '''
        -- Create initial file
        local file = io.open("append.txt", "w")
        file:write("Initial content\\n")
        file:close()

        -- Append to it
        file = io.open("append.txt", "a")
        file:write("Appended content\\n")
        file:close()

        -- Read final content
        file = io.open("append.txt", "r")
        local content = file:read("*a")
        file:close()

        return content
      ''';

        final _ = await executeCode(code);

        final memoryFiles = InMemoryIODevice.getMemoryStorage();
        expect(
          memoryFiles['append.txt'],
          equals('Initial content\nAppended content\n'),
        );
      });

      test('should handle file seek operations', () async {
        final code = '''
        -- Create file with multiple lines
        local file = io.open("seektest.txt", "w")
        file:write("Line 1\\n")
        file:write("Line 2\\n")
        file:write("Line 3\\n")
        file:close()

        -- Open for reading and test seek
        file = io.open("seektest.txt", "r+")

        -- Read first line
        local line1 = file:read("l")

        -- Seek to beginning
        file:seek("set", 0)

        -- Read all content
        local allContent = file:read("*a")

        file:close()

        return line1, allContent
      ''';

        final _ = await executeCode(code);

        // Verify the file operations worked correctly
        final memoryFiles = InMemoryIODevice.getMemoryStorage();
        expect(memoryFiles['seektest.txt'], equals('Line 1\nLine 2\nLine 3\n'));
      });

      test('should persist files across multiple script executions', () async {
        // First script: create a file
        await executeCode('''
        local file = io.open("persistent.txt", "w")
        file:write("This should persist")
        file:close()
      ''');

        // Second script: read the file created by first script
        final _ = await executeCode('''
        local file = io.open("persistent.txt", "r")
        if file then
            local content = file:read("*a")
            file:close()
            return content
        else
            return "File not found"
        end
      ''');

        // Verify file persisted
        final memoryFiles = InMemoryIODevice.getMemoryStorage();
        expect(memoryFiles.containsKey('persistent.txt'), isTrue);
        expect(memoryFiles['persistent.txt'], equals('This should persist'));
      });

      test('should handle file errors gracefully', () async {
        final code = '''
        -- Try to read non-existent file
        local file = io.open("nonexistent.txt", "r")
        if file then
            return "Should not reach here"
        else
            return "File not found (as expected)"
        end
      ''';

        // This should not throw an exception
        expect(() => executeCode(code), returnsNormally);
      });

      test('should work with io.write and io.read functions', () async {
        final code = '''
        -- Set output to a file
        local file = io.open("output.txt", "w")
        io.output(file)

        -- Write using io.write (goes to current output file)
        io.write("Hello ")
        io.write("World!")

        -- Close the file
        io.close()

        -- Read it back
        file = io.open("output.txt", "r")
        local content = file:read("*a")
        file:close()

        return content
      ''';

        final _ = await executeCode(code);

        final memoryFiles = InMemoryIODevice.getMemoryStorage();
        expect(memoryFiles['output.txt'], equals('Hello World!'));
      });

      test('should run the exact user example code correctly', () async {
        // This is the exact code the user provided
        final userCode = '''
-- File I/O Operations
-- Write to a file
local file = io.open("test.txt", "w")
if file then
    file:write("Hello from LuaLike!\\n")
    file:write("This is a test file.\\n")
    file:close()
    print("File written successfully")
else
    print("Could not open file for writing")
end

-- Read from a file
file = io.open("test.txt", "r")
if file then
    print("\\nFile contents:")
    for line in file:lines() do
        print(line)
    end
    file:close()
else
    print("Could not open file for reading")
end

-- Working with strings as files
local data = "line1\\nline2\\nline3"
local stringFile = io.open("data", "w")
stringFile:write(data)
stringFile:close()

stringFile = io.open("data", "r")
print("\\nString file contents:")
for line in stringFile:lines() do
    print("Read: " .. line)
end
stringFile:close()
      ''';

        // Execute the user's code
        final _ = await executeCode(userCode);

        // Verify that the files were created correctly in memory
        final memoryFiles = InMemoryIODevice.getMemoryStorage();

        // Check that test.txt was created with correct content
        expect(memoryFiles.containsKey('test.txt'), isTrue);
        expect(
          memoryFiles['test.txt'],
          equals('Hello from LuaLike!\nThis is a test file.\n'),
        );

        // Check that data file was created with correct content
        expect(memoryFiles.containsKey('data'), isTrue);
        expect(memoryFiles['data'], equals('line1\nline2\nline3'));

        print('\n📁 Files in memory:');
        for (final entry in memoryFiles.entries) {
          print('  ${entry.key}: "${entry.value.replaceAll('\n', '\\n')}"');
        }
      });

      test('should demonstrate file persistence between operations', () async {
        // First operation: create files
        await executeCode('''
        local file1 = io.open("persistent1.txt", "w")
        file1:write("First file content")
        file1:close()

        local file2 = io.open("persistent2.txt", "w")
        file2:write("Second file content")
        file2:close()

        print("Files created")
      ''');

        // Second operation: read files
        await executeCode('''
        local file1 = io.open("persistent1.txt", "r")
        local content1 = file1:read("*a")
        file1:close()

        local file2 = io.open("persistent2.txt", "r")
        local content2 = file2:read("*a")
        file2:close()

        print("File 1: " .. content1)
        print("File 2: " .. content2)
      ''');

        // Verify files persisted
        final memoryFiles = InMemoryIODevice.getMemoryStorage();
        expect(memoryFiles['persistent1.txt'], equals('First file content'));
        expect(memoryFiles['persistent2.txt'], equals('Second file content'));
      });

      test('should handle file operations with proper line endings', () async {
        final code = '''
        local file = io.open("lines.txt", "w")
        file:write("Line 1\\n")
        file:write("Line 2\\n")
        file:write("Line 3")
        file:close()

        file = io.open("lines.txt", "r")
        print("Reading lines:")
        local lineCount = 0
        for line in file:lines() do
            lineCount = lineCount + 1
            print("Line " .. lineCount .. ": " .. line)
        end
        file:close()

        return lineCount
      ''';

        final _ = await executeCode(code);

        // Verify the file content
        final memoryFiles = InMemoryIODevice.getMemoryStorage();
        expect(memoryFiles['lines.txt'], equals('Line 1\nLine 2\nLine 3'));
      });

      test('should work with different file modes', () async {
        final code = '''
        -- Test write mode
        local file = io.open("modes.txt", "w")
        file:write("Original content")
        file:close()

        -- Test append mode
        file = io.open("modes.txt", "a")
        file:write("\\nAppended content")
        file:close()

        -- Test read mode
        file = io.open("modes.txt", "r")
        local content = file:read("*a")
        file:close()

        print("Final content:")
        print(content)

        return content
      ''';

        await executeCode(code);

        final memoryFiles = InMemoryIODevice.getMemoryStorage();
        expect(
          memoryFiles['modes.txt'],
          equals('Original content\nAppended content'),
        );
      });

      test(
        'should demonstrate that files work correctly instead of returning "r"',
        () async {
          // This test specifically addresses the issue the user encountered
          final code = '''
        -- Create a file with specific content
        local file = io.open("debug.txt", "w")
        file:write("CORRECT CONTENT\\n")
        file:write("Second line\\n")
        file:close()
        print("✓ File written")

        -- Read it back
        file = io.open("debug.txt", "r")
        print("✓ File opened for reading")

        local allContent = file:read("*a")
        print("Raw content: [" .. (allContent or "nil") .. "]")

        -- Reset file pointer and read line by line
        file:close()
        file = io.open("debug.txt", "r")

        local lineNum = 0
        for line in file:lines() do
            lineNum = lineNum + 1
            print("Line " .. lineNum .. ": [" .. line .. "]")
        end
        file:close()

        return allContent
      ''';

          final result = await executeCode(code);

          // Verify the memory storage contains the correct content
          final memoryFiles = InMemoryIODevice.getMemoryStorage();
          expect(
            memoryFiles['debug.txt'],
            equals('CORRECT CONTENT\nSecond line\n'),
          );

          // The result should NOT be just "r"
          expect(result, isNot(equals('r')));
        },
      );
    });
  });
}
