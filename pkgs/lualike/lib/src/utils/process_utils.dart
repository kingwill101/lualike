/// Process backend injection point for plugging custom process executors
/// (SSH, Docker, test mocks) into `os.execute()` and `io.popen()`.
library;

import 'process_backend.dart';
import 'io_abstractions.dart' as io_abs;

/// Overrides process execution with a custom [ProcessBackend].
///
/// Pass `null` to restore the platform default (`dart:io` on native,
/// throws on web).
void setProcessBackend(ProcessBackend? backend) =>
    io_abs.setProcessBackend(backend);

/// The currently installed [ProcessBackend], or `null` if the platform default
/// is in use.
ProcessBackend? get currentProcessBackend => io_abs.currentProcessBackend;
