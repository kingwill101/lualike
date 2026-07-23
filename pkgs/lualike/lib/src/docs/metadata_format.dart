/// Output formats supported by lualike documentation generation.
library;

/// A generated documentation artifact format.
enum MetadataFormat {
  /// Standalone HTML documentation page.
  html,

  /// JSON manifest for editor tooling and language servers.
  json,

  /// LuaLS annotation stubs for existing Lua LSPs.
  luals,
}
