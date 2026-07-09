import 'package:lualike/lualike.dart';

/// Wires a custom [ProcessBackend] into the current lualike runtime.
///
/// After calling this, `os.execute()` and `io.popen()` use [backend]
/// instead of the platform default.
///
/// ```dart
/// class DockerBackend implements ProcessBackend { ... }
/// await useProcessBackend(DockerBackend());
/// ```
void useProcessBackend(ProcessBackend backend) {
  setProcessBackend(backend);
}
