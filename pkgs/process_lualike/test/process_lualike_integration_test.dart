import 'dart:io' as io;

import 'package:dartssh2/dartssh2.dart';
import 'package:lualike/lualike.dart';
import 'package:process_lualike/process_lualike.dart';
import 'package:test/test.dart';
import 'package:testcontainers_compose/testcontainers_compose.dart';

String _composeContext() {
  final inPackage = io.File('test/fixtures/docker-compose.yaml');
  if (inPackage.existsSync()) return 'test/fixtures';
  // Fallback for monorepo workspace runs
  return 'pkgs/process_lualike/test/fixtures';
}

Future<void> main() async {
  group('SshProcessBackend (Docker)', () {
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

    int sshPort() {
      return compose.container('ssh').publisher(byPort: 22).publishedPort!;
    }

    Future<SSHClient> connectSsh() async {
      final socket = await SSHSocket.connect('localhost', sshPort());
      final sshClient = SSHClient(
        socket,
        username: 'testuser',
        onPasswordRequest: () => 'testpass',
      );
      await sshClient.authenticated;
      return sshClient;
    }

    test('sets up SSH connection', () async {
      final client = await connectSsh();
      client.close();
      expect(true, isTrue);
    });

    group('SshProcessBackend', () {
      test('executes command remotely and captures stdout', () async {
        final client = await connectSsh();
        try {
          final backend = SshProcessBackend(client);
          final result = await backend.run('whoami');
          expect(result.stdout.trim(), equals('testuser'));
          expect(result.exitCode, equals(0));
          expect(result.stderr, isEmpty);
        } finally {
          client.close();
        }
      });

      test('captures stderr from remote command', () async {
        final client = await connectSsh();
        try {
          final backend = SshProcessBackend(client);
          final result = await backend.run('bash -c "echo err-msg >&2"');
          expect(result.stdout.trim(), isEmpty);
          expect(result.stderr.trim(), equals('err-msg'));
          expect(result.exitCode, equals(0));
        } finally {
          client.close();
        }
      });

      test('propagates non-zero exit code', () async {
        final client = await connectSsh();
        try {
          final backend = SshProcessBackend(client);
          final result = await backend.run('bash -c "exit 42"');
          expect(result.exitCode, equals(42));
        } finally {
          client.close();
        }
      });

      test('isShellAvailable reports true', () async {
        final client = await connectSsh();
        try {
          final backend = SshProcessBackend(client);
          expect(backend.isShellAvailable, isTrue);
        } finally {
          client.close();
        }
      });

      test('injection point wires SshProcessBackend into lualike', () async {
        final client = await connectSsh();
        try {
          final backend = SshProcessBackend(client);
          setProcessBackend(backend);
          addTearDown(() => setProcessBackend(null));

          final lua = LuaLike();
          final result = await lua.execute('return os.execute()');
          expect((result as Value).unwrap(), equals(true));
        } finally {
          client.close();
        }
      });

      test('runStreaming delivers live stdout chunks', () async {
        final client = await connectSsh();
        try {
          final backend = SshProcessBackend(client);
          final chunks = <List<int>>[];
          final exitCode = await backend.runStreaming(
            'bash -c "printf Hello-from-SSH"',
            onStdout: (chunk) => chunks.add(chunk),
          );
          expect(exitCode, equals(0));
          expect(chunks, isNotEmpty);
          expect(
            String.fromCharCodes(chunks.expand((c) => c).toList()).trim(),
            equals('Hello-from-SSH'),
          );
        } finally {
          client.close();
        }
      });

      test('runStreaming delivers live stderr chunks', () async {
        final client = await connectSsh();
        try {
          final backend = SshProcessBackend(client);
          final chunks = <List<int>>[];
          final exitCode = await backend.runStreaming(
            'bash -c "echo live-stderr >&2"',
            onStderr: (chunk) => chunks.add(chunk),
          );
          expect(exitCode, equals(0));
          expect(chunks, isNotEmpty);
          expect(
            String.fromCharCodes(chunks.expand((c) => c).toList()).trim(),
            equals('live-stderr'),
          );
        } finally {
          client.close();
        }
      });

      test('runStreaming invokes onDone when process exits', () async {
        final client = await connectSsh();
        try {
          final backend = SshProcessBackend(client);
          var doneCalled = false;
          await backend.runStreaming('whoami', onDone: () => doneCalled = true);
          expect(doneCalled, isTrue);
        } finally {
          client.close();
        }
      });
    });
  });
}
