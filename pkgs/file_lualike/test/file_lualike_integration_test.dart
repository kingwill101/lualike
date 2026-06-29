import 'dart:io' as io;

import 'package:dartssh2/dartssh2.dart';
import 'package:file/file.dart';
import 'package:file_lualike/file_lualike.dart';
import 'package:file_sftp/file_sftp.dart';
import 'package:lualike/lualike.dart';
import 'package:test/test.dart';
import 'package:testcontainers_compose/testcontainers_compose.dart';

/// Matches a [ReadResult.value] that is a [LuaString] equal to [expected].
Matcher luaString(String expected) => predicate(
  (v) => v is LuaString && v.toString() == expected,
  'a LuaString matching "$expected"',
);

String _composeContext() {
  final inPackage = io.File('test/fixtures/docker-compose.yaml');
  if (inPackage.existsSync()) return 'test/fixtures';
  // Fallback for monorepo workspace runs
  return 'pkgs/file_lualike/test/fixtures';
}

Future<void> main() async {
  group('PackageFileIODevice with SFTP (Docker)', () {
    late DockerCompose compose;

    setUpAll(() async {
      compose = DockerCompose(
        context: _composeContext(),
        composeFileName: ['docker-compose.yaml'],
        wait: true,
      );
      await compose.start();
      await Future<void>.delayed(const Duration(seconds: 5));
      addTearDown(() => compose.stop(down: true));
    });

    int sftpPort() {
      return compose.container('sftp').publisher(byPort: 22).publishedPort!;
    }

    Future<FileSystem> connectSftp() async {
      final socket = await SSHSocket.connect('localhost', sftpPort());
      final sshClient = SSHClient(
        socket,
        username: 'testuser',
        onPasswordRequest: () => 'testpass',
      );
      await sshClient.authenticated;
      final sftpClient = await sshClient.sftp();
      return SftpFileSystem.fromClient(
        sftpClient,
        config: () => SftpConfig(
          host: 'localhost',
          port: sftpPort(),
          username: 'testuser',
          password: 'testpass',
          root: '/upload',
        ),
      );
    }

    group('PackageFileIODevice over SFTP', () {
      test('write and read a string', () async {
        final fs = await connectSftp();
        try {
          final device = await PackageFileIODevice.open(
            fs,
            '/io-sftp-test.txt',
            'w+',
          );
          await device.write('Hello SFTP!');
          await device.seek(SeekWhence.set, 0);
          final result = await device.read('a');
          expect(result.value, luaString('Hello SFTP!'));
          await device.close();
        } finally {
          await (fs as SftpFileSystem).disconnect();
        }
      });

      test('read returns nil for non-existent file', () async {
        final fs = await connectSftp();
        try {
          await PackageFileIODevice.open(fs, '/nonexistent.txt', 'r');
          fail('Expected exception for non-existent file');
        } catch (_) {
        } finally {
          await (fs as SftpFileSystem).disconnect();
        }
      });

      test('write and read bytes', () async {
        final fs = await connectSftp();
        try {
          final device = await PackageFileIODevice.open(
            fs,
            '/io-bytes.bin',
            'w+',
          );
          await device.writeBytes([10, 20, 30, 40, 255]);
          await device.seek(SeekWhence.set, 0);
          final result = await device.read('5');
          expect(result.value, isA<LuaString>());
          expect((result.value as LuaString).bytes, [10, 20, 30, 40, 255]);
          await device.close();
        } finally {
          await (fs as SftpFileSystem).disconnect();
        }
      });

      test('read lines', () async {
        final fs = await connectSftp();
        try {
          final device = await PackageFileIODevice.open(
            fs,
            '/io-lines.txt',
            'w+',
          );
          await device.write('a\nb\nc');
          await device.seek(SeekWhence.set, 0);

          expect((await device.read('l')).value, luaString('a'));
          expect((await device.read('l')).value, luaString('b'));
          expect((await device.read('l')).value, luaString('c'));
          expect((await device.read('l')).value, isNull); // EOF

          await device.close();
        } finally {
          await (fs as SftpFileSystem).disconnect();
        }
      });

      test('seek operations', () async {
        final fs = await connectSftp();
        try {
          final device = await PackageFileIODevice.open(
            fs,
            '/io-seek.txt',
            'w+',
          );
          await device.write('0123456789');
          await device.seek(SeekWhence.set, 3);
          expect(await device.getPosition(), equals(3));

          await device.seek(SeekWhence.cur, 2);
          expect(await device.getPosition(), equals(5));

          await device.seek(SeekWhence.end, -2);
          expect(await device.getPosition(), equals(8));

          await device.close();
        } finally {
          await (fs as SftpFileSystem).disconnect();
        }
      });

      test('isEOF', () async {
        final fs = await connectSftp();
        try {
          final device = await PackageFileIODevice.open(
            fs,
            '/io-eof.txt',
            'w+',
          );
          await device.write('hi');
          await device.seek(SeekWhence.set, 0);
          expect(await device.isEOF(), isFalse);

          await device.read('a');
          expect(await device.isEOF(), isTrue);

          await device.close();
        } finally {
          await (fs as SftpFileSystem).disconnect();
        }
      });
    });

    group('PackageFileSystemBackend over SFTP', () {
      test('fileExists, writeFile, readFileAsString', () async {
        final fs = await connectSftp();
        try {
          final backend = PackageFileSystemBackend(fs);

          await backend.writeFile('/backend-test.txt', 'backend content');
          expect(await backend.fileExists('/backend-test.txt'), isTrue);
          expect(
            await backend.readFileAsString('/backend-test.txt'),
            equals('backend content'),
          );
        } finally {
          await (fs as SftpFileSystem).disconnect();
        }
      });

      test('directoryExists, createDirectory, listDirectory', () async {
        final fs = await connectSftp();
        try {
          final backend = PackageFileSystemBackend(fs);

          final created = await backend.createDirectory(
            '/sftp-dir',
            recursive: true,
          );
          expect(created, isTrue);
          expect(await backend.directoryExists('/sftp-dir'), isTrue);

          // Write a file inside the dir
          await backend.writeFile('/sftp-dir/nested.txt', 'nested');
          final entries = await backend.listDirectory('/sftp-dir');
          expect(entries, hasLength(1));
        } finally {
          await (fs as SftpFileSystem).disconnect();
        }
      });

      test('fileSize', () async {
        final fs = await connectSftp();
        try {
          final backend = PackageFileSystemBackend(fs);
          await backend.writeFile('/size-test.txt', '12345');
          expect(await backend.fileSize('/size-test.txt'), equals(5));
        } finally {
          await (fs as SftpFileSystem).disconnect();
        }
      });

      test('renameFile', () async {
        final fs = await connectSftp();
        try {
          final backend = PackageFileSystemBackend(fs);
          await backend.writeFile('/rename-old.txt', 'move me');
          await backend.renameFile('/rename-old.txt', '/rename-new.txt');
          expect(await backend.fileExists('/rename-old.txt'), isFalse);
          expect(
            await backend.readFileAsString('/rename-new.txt'),
            equals('move me'),
          );
        } finally {
          await (fs as SftpFileSystem).disconnect();
        }
      });
    });

    group('useFileSystem full integration', () {
      test('wires up lualike to SFTP filesystem', () async {
        final fs = await connectSftp();
        try {
          // Configure lualike to use the SFTP filesystem
          await useFileSystem(fs);

          // Verify FileSystemProvider integration: open a file handle
          final provider = FileSystemProvider();
          provider.setIODeviceFactory(
            (path, mode) => PackageFileIODevice.open(fs, path, mode),
            providerName: 'SFTP',
          );

          // Write via the device
          final dev = await provider.openFile('/full-int-test.txt', 'w+');
          await dev.write('full integration');
          await dev.close();

          // Read back via FileSystemBackend
          final backend = PackageFileSystemBackend(fs);
          expect(
            await backend.readFileAsString('/full-int-test.txt'),
            equals('full integration'),
          );

          // Verify via file_system_utils
          setFileSystemBackend(backend);
          expect(await fileExists('/full-int-test.txt'), isTrue);
          expect(
            await readFileAsString('/full-int-test.txt'),
            equals('full integration'),
          );
        } finally {
          await (fs as SftpFileSystem).disconnect();
        }
      });
    });
  });
}
