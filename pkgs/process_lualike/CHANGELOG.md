## 0.1.0

- `SshProcessBackend` fully implemented with `run()`, `runStreaming()`, and
  `isShellAvailable` using `dartssh2` `SSHClient.runWithResult`.
- Bump `lualike` dependency to `^0.2.4`.
- Add Docker-based SSH integration tests (Ubuntu 22.04 + OpenSSH).
- Add README with install, quick start, SSH, custom backend, and streaming examples.
