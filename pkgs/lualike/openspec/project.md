# Project Context

## Purpose
lualike is a Lua-like interpreter written in Dart. It aims to be a drop-in
replacement for the Lua CLI and an embeddable scripting runtime with minimal
script changes, a simple REPL, and Dart interoperability.

## Tech Stack
- Dart >=3.9 (Dart VM, pub packages)
- Parsing with petitparser
- CLI built on Dart command runner tooling
- Logging via contextual
- Tests with package:test and dart_test.yaml tags
- Tooling scripts under tool/

## Project Conventions

### Code Style
- Follow the Dart style guide; format with `dart format .`
- lowerCamelCase for variables/functions/constants; UpperCamelCase for types
- Use curly braces for all control flow
- Import order: `dart:` then `package:` then relative
- Keep lines <= 80 chars when possible
- File/package names use `lowercase_with_underscores`

### Architecture Patterns
- AST parsing + interpreter is the default execution path
- Bytecode backend is in progress; AST remains the default CLI mode
- Core runtime surfaces: values, environments/scoping, standard library, GC
- Public API focuses on `executeCode`/`LuaLike` for embedding and interop
- CLI entrypoint delegates to a command runner

### Documentation
- Update `doc/` and `docs/` progressively alongside code changes
- Write from the user perspective with small lualike examples
- Avoid Dart internals, class names, or file structure in docs
- Refer to the language as "lualike"
- Use proper Dart doc comments (`///`) for public classes and APIs with clear
  explanations and usage details

### Testing Strategy
- Run the full test suite (`dart test`) before merging
- Add targeted regression tests for bugs; prefer minimal repros
- Tagging is defined in `dart_test.yaml` (bytecode tag currently skipped)
- For parity/integration runs, use `dart run tool/test.dart`
- Compile the standalone runner with
  `dart run tool/test.dart --compile-runner`, then run `./test_runner`

### Git Workflow
- No special branching strategy documented; keep changes small and focused
- Use concise, descriptive commit messages; follow existing history if unsure
- Run tests and update docs when behavior changes

## Domain Context
- lualike mirrors Lua semantics with a Dart runtime; scripts should run with
  minimal changes
- CLI is a drop-in Lua replacement with extra logging flags (`--debug`,
  `--level`, `--category`)
- Logging can be configured via env vars (LOGGING_ENABLED, LOGGING_LEVEL,
  LOGGING_CATEGORY)
- The interpreter exposes Dart interop for calling Dart from lualike and vice
  versa

## Important Constraints
- Maintain Lua-compatible behavior unless explicitly changing semantics
- Prefer minimal, targeted changes; avoid breaking CLI flags or env vars
- Documentation should describe behavior from a user perspective and refer to
  the language as "lualike"
- Use `dart format .` and `dart fix --apply` when touching Dart code

## External Dependencies
- No external services required for runtime
- Third-party Dart packages include petitparser, contextual, pointycastle/
  crypto, archive, http, yaml, dart_console
- Optional: system Lua interpreter for output comparison via tool/compare
