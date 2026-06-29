/// Bridges remote process execution into the lualike scripting runtime.
///
/// Provides [SshProcessBackend] — a [ProcessBackend] that runs commands over
/// SSH via `dartssh2`. Use [useProcessBackend] to wire it into `os.execute()`.
library;

export 'src/ssh_process_backend.dart';
export 'src/config.dart';
