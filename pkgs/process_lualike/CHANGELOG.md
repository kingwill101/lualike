## 0.1.1

- `useProcessBackend()` now accepts `ProcessBackend` (not just `SshProcessBackend`),
  enabling custom backends beyond SSH.
- `SshProcessBackend.runSync()` now throws `LuaError` instead of `UnsupportedError`.
- `SshProcessBackend.runStreaming()` adds 100-attempt timeout guard for exit code
  polling.
- Bump `lualike` dependency to `^0.3.0`.
- Bump SDK constraint to `>=3.10.0 <4.0.0`.

## 0.1.0

- `SshProcessBackend` fully implemented with `run()`, `runStreaming()`, and
  `isShellAvailable` using `dartssh2` `SSHClient.runWithResult`.
- Bump `lualike` dependency to `^0.2.4`.
- Add Docker-based SSH integration tests (Ubuntu 22.04 + OpenSSH).
- Add README with install, quick start, SSH, custom backend, and streaming examples.
