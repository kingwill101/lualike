import 'package:lualike/lualike.dart';
import 'ssh_process_backend.dart';

/// Wires an SSH-based process backend into the current lualike runtime.
///
/// After calling this, `os.execute()` and `io.popen()` run commands on the
/// remote host via [backend] instead of the local machine.
///
/// ```dart
/// final session = SshClient(...);
/// await useProcessBackend(SshProcessBackend(session));
/// ```
void useProcessBackend(SshProcessBackend backend) {
  setProcessBackend(backend);
}
