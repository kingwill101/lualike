library;

import 'dart:convert';

import '../runtime/lua_runtime.dart' show LuaRuntime;
import '../stdlib/doc.dart' show DocParam, FunctionDoc;
import '../stdlib/library.dart' show Library;

/// Result of rendering documentation to HTML fragments.
class DocHtmlResult {
  final String sidebar;
  final String content;

  const DocHtmlResult({required this.sidebar, required this.content});
}

/// Options for rendering the shared LuaLike documentation page shell.
class DocPageOptions {
  /// Creates shared documentation page options.
  const DocPageOptions({
    this.title = 'LuaLike API Reference',
    this.brandName = 'LuaLike',
    this.homeHref,
    this.homeLabel = 'Home',
  });

  /// Browser title and top-level page label.
  final String title;

  /// Sidebar brand text.
  final String brandName;

  /// Optional link shown in the sidebar brand row.
  final String? homeHref;

  /// Label used for [homeHref].
  final String homeLabel;
}

/// Initializes runtime libraries and returns them in registry order.
///
/// Standard namespaced libraries are installed lazily at runtime. Documentation
/// metadata is collected during library initialization, so doc generators and
/// editor tooling should use this helper when they want the complete registered
/// library surface.
List<Library> documentedLibrariesForRuntime(LuaRuntime runtime) {
  runtime.libraryRegistry.initializeAll();
  return runtime.libraryRegistry.libraries;
}

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _escapeAttribute(String s) =>
    _escape(s).replaceAll('"', '&quot;').replaceAll("'", '&#39;');

String _signatureText(String name, FunctionDoc doc) {
  final parts = [name];
  for (final p in doc.params) {
    parts.add(p.optional ? '[${p.name}]' : p.name);
  }
  return parts.join(' ');
}

String _libraryDocName(Library lib, Map<String, FunctionDoc> docs) {
  if (lib.name.isNotEmpty) {
    return lib.name;
  }
  final categories = docs.values
      .map((doc) => doc.category)
      .where((category) => category.isNotEmpty)
      .toSet();
  return categories.length == 1 ? categories.single : 'base';
}

String _qualifiedFunctionName(String libraryName, String name) {
  if (libraryName == 'base') {
    return name;
  }
  if (name == libraryName || name.startsWith('$libraryName.')) {
    return name;
  }
  return '$libraryName.$name';
}

String _luaIdentifier(String name) {
  const keywords = <String>{
    'and',
    'break',
    'do',
    'else',
    'elseif',
    'end',
    'false',
    'for',
    'function',
    'goto',
    'if',
    'in',
    'local',
    'nil',
    'not',
    'or',
    'repeat',
    'return',
    'then',
    'true',
    'until',
    'while',
  };
  if (name == '...') {
    return name;
  }
  final sanitized = name.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  final withPrefix = sanitized.startsWith(RegExp(r'[A-Za-z_]'))
      ? sanitized
      : '_$sanitized';
  return keywords.contains(withPrefix) ? '${withPrefix}_' : withPrefix;
}

String _uniqueAnchor(String libraryName, String name, Set<String> usedAnchors) {
  final qualifiedName = _qualifiedFunctionName(libraryName, name);
  if (usedAnchors.add(qualifiedName)) {
    return qualifiedName;
  }

  var suffix = 2;
  while (!usedAnchors.add('$qualifiedName-$suffix')) {
    suffix++;
  }
  return '$qualifiedName-$suffix';
}

List<String> _docLines(String text) {
  return text
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

String _paramRowsHtml(List<DocParam> params) {
  if (params.isEmpty) return '';
  return '''
  <table class="params-table">
    <tr><th>Name</th><th>Type</th><th>Description</th></tr>
    ${params.map((p) {
    final type = p.optional ? '${p.type} (optional)' : p.type;
    return '''
    <tr>
      <td class="p-name">${_escape(p.name)}</td>
      <td class="p-type">${_escape(type)}</td>
      <td class="p-desc">${_escape(p.description)}</td>
    </tr>''';
  }).join('\n')}
  </table>''';
}

/// Renders a list of [Library] objects into sidebar and content HTML.
///
/// Each library's [Library.getDocs] and [Library.description] are used to
/// produce the output. Libraries with no documented functions are skipped.
DocHtmlResult renderDocs(List<Library> libraries) {
  final sidebarBuf = StringBuffer();
  final contentBuf = StringBuffer();
  final usedAnchors = <String>{};
  var sectionIndex = 0;

  for (final lib in libraries) {
    final docs = lib.getDocs();
    if (docs.isEmpty) continue;
    final cat = _libraryDocName(lib, docs);
    final sectionId = 'section-$sectionIndex-${_escapeAttribute(cat)}';
    final anchors = <String, String>{
      for (final name in docs.keys) name: _uniqueAnchor(cat, name, usedAnchors),
    };
    sectionIndex++;

    sidebarBuf.writeln('<div class="section-group">');
    sidebarBuf.writeln(
      '<button class="section-toggle" type="button" '
      'aria-controls="$sectionId-nav" aria-expanded="true">'
      '<span class="toggle-icon" aria-hidden="true">v</span>'
      '<span>${_escape(cat)}</span></button>',
    );
    sidebarBuf.writeln('<div class="section-items" id="$sectionId-nav">');
    for (final name in docs.keys) {
      final href = _escapeAttribute(anchors[name]!);
      sidebarBuf.writeln('<a class="func" href="#$href">${_escape(name)}</a>');
    }
    sidebarBuf.writeln('</div>');
    sidebarBuf.writeln('</div>');

    contentBuf.writeln('<section class="section-group">');
    contentBuf.writeln(
      '<button class="section-toggle" type="button" '
      'aria-controls="$sectionId-content" aria-expanded="true">'
      '<span class="toggle-icon" aria-hidden="true">v</span>'
      '<span>${_escape(cat)}</span></button>',
    );
    contentBuf.writeln('<div class="section-items" id="$sectionId-content">');
    if (lib.description.isNotEmpty) {
      contentBuf.writeln(
        '<p class="library-desc">${_escape(lib.description)}</p>',
      );
    }

    for (final entry in docs.entries) {
      final name = entry.key;
      final doc = entry.value;
      final sig = _signatureText(name, doc);
      final anchor = anchors[name]!;

      contentBuf.writeln('<article class="func-entry">');
      contentBuf.writeln('<a id="${_escapeAttribute(anchor)}"></a>');
      contentBuf.writeln('<div class="func-signature">${_escape(sig)}</div>');
      contentBuf.writeln(
        '<div class="func-summary">${_escape(doc.summary)}</div>',
      );
      if (doc.params.isNotEmpty) {
        contentBuf.write(_paramRowsHtml(doc.params));
      }
      if (doc.returns != null) {
        contentBuf.writeln(
          '<div class="returns"><strong>Returns:</strong> '
          '${_escape(doc.returns!)}</div>',
        );
      }
      if (doc.example != null) {
        contentBuf.writeln(
          '<pre class="language-lua"><code class="language-lua">'
          '${_escape(doc.example!)}</code></pre>',
        );
      }
      contentBuf.writeln('</article>');
    }
    contentBuf.writeln('</div>');
    contentBuf.writeln('</section>');
  }

  return DocHtmlResult(
    sidebar: sidebarBuf.toString(),
    content: contentBuf.toString(),
  );
}

/// Renders the shared, complete LuaLike documentation HTML page.
///
/// Packages that embed LuaLike or add libraries should call this instead of
/// carrying their own HTML shell. The library list supplies the content; the UI
/// behavior, layout, and JSON-friendly class names stay centralized here.
String renderDocsPage(
  List<Library> libraries, {
  DocPageOptions options = const DocPageOptions(),
}) {
  final fragments = renderDocs(libraries);
  final homeLink = options.homeHref == null
      ? ''
      : '<a href="${_escapeAttribute(options.homeHref!)}">'
            '${_escape(options.homeLabel)}</a>';

  return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${_escape(options.title)}</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #101214;
      --panel: #181b1f;
      --line: #2b3138;
      --text: #f4f1ea;
      --muted: #a5adb8;
      --soft: #717b88;
      --accent: #5fb3a1;
      --code: #e2c06d;
      --type: #f08d6c;
      --sidebar-width: 18rem;
      --font-ui: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI",
        sans-serif;
      --font-code: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    }
    * { box-sizing: border-box; }
    html { scroll-behavior: smooth; }
    body {
      margin: 0;
      min-height: 100vh;
      display: flex;
      background: var(--bg);
      color: var(--text);
      font-family: var(--font-ui);
      font-size: 15px;
      line-height: 1.5;
    }
    .sidebar-overlay {
      display: none;
      position: fixed;
      inset: 0;
      background: rgb(0 0 0 / 0.48);
      z-index: 8;
    }
    .sidebar-overlay.open { display: block; }
    .sidebar {
      position: sticky;
      top: 0;
      width: var(--sidebar-width);
      height: 100vh;
      overflow-y: auto;
      flex-shrink: 0;
      background: var(--panel);
      border-right: 1px solid var(--line);
      z-index: 9;
    }
    .brand {
      min-height: 4rem;
      padding: 1rem 1.1rem;
      display: flex;
      align-items: center;
      gap: 0.75rem;
      border-bottom: 1px solid var(--line);
    }
    .brand-mark {
      width: 1.6rem;
      height: 1.6rem;
      border-radius: 50%;
      background: linear-gradient(135deg, var(--accent), var(--code));
      box-shadow: inset 0 0 0 4px rgb(16 18 20 / 0.42);
      flex: 0 0 auto;
    }
    .brand-title {
      min-width: 0;
      flex: 1;
      font-weight: 700;
      overflow-wrap: anywhere;
    }
    .brand a {
      color: var(--muted);
      font-size: 0.78rem;
      text-decoration: none;
    }
    .brand a:hover { color: var(--accent); }
    .sidebar-links { padding: 0.8rem 0; }
    .section-group { margin: 0 0 0.4rem; }
    .section-toggle {
      width: 100%;
      border: 0;
      background: transparent;
      color: var(--soft);
      cursor: pointer;
      display: flex;
      align-items: center;
      gap: 0.45rem;
      font: inherit;
      font-weight: 700;
      text-align: left;
      user-select: none;
    }
    .sidebar .section-toggle {
      padding: 0.7rem 1.1rem 0.3rem;
      font-size: 0.72rem;
      letter-spacing: 0.06em;
      text-transform: uppercase;
    }
    .content .section-toggle {
      margin-top: 1.5rem;
      padding: 0.8rem 0;
      border-bottom: 1px solid var(--line);
      color: var(--text);
      font-size: 1.35rem;
    }
    .section-toggle:hover { color: var(--accent); }
    .toggle-icon {
      font-family: var(--font-code);
      font-size: 0.75em;
      transition: transform 0.16s ease;
    }
    .section-toggle.collapsed .toggle-icon {
      transform: rotate(-90deg);
    }
    .section-items {
      overflow: hidden;
      transition: max-height 0.2s ease;
    }
    .section-toggle.collapsed + .section-items {
      max-height: 0 !important;
    }
    .sidebar a.func {
      display: block;
      padding: 0.25rem 1.1rem 0.25rem 1.75rem;
      border-left: 2px solid transparent;
      color: var(--muted);
      font-family: var(--font-code);
      font-size: 0.8rem;
      overflow-wrap: anywhere;
      text-decoration: none;
    }
    .sidebar a.func:hover {
      color: var(--text);
      background: rgb(255 255 255 / 0.04);
      border-left-color: var(--accent);
    }
    .menu-toggle {
      display: none;
      width: 2rem;
      height: 2rem;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: transparent;
      color: var(--text);
      cursor: pointer;
      font: 700 1.2rem var(--font-code);
    }
    .content {
      width: min(100%, 64rem);
      padding: 2rem 3rem 4rem;
    }
    .library-desc {
      max-width: 54rem;
      color: var(--muted);
      margin: 0.9rem 0 1.1rem;
    }
    .func-entry {
      margin: 1rem 0 1.35rem;
      padding: 1rem;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: rgb(255 255 255 / 0.025);
    }
    .func-signature {
      margin-bottom: 0.5rem;
      color: var(--code);
      font-family: var(--font-code);
      overflow-wrap: anywhere;
    }
    .func-summary { color: #d8dbe0; margin-bottom: 0.75rem; }
    .params-table {
      width: 100%;
      border-collapse: collapse;
      margin: 0.65rem 0;
      font-size: 0.86rem;
    }
    .params-table th {
      color: var(--soft);
      font-weight: 700;
      text-align: left;
      border-bottom: 1px solid var(--line);
    }
    .params-table th,
    .params-table td {
      padding: 0.4rem 0.5rem;
      vertical-align: top;
    }
    .params-table td { border-bottom: 1px solid rgb(255 255 255 / 0.06); }
    .p-name, .p-type { font-family: var(--font-code); }
    .p-name { color: var(--code); white-space: nowrap; }
    .p-type { color: var(--type); font-size: 0.8rem; }
    .p-desc, .returns { color: #d8dbe0; }
    .returns { margin: 0.6rem 0; font-size: 0.86rem; }
    .returns strong { color: var(--soft); }
    pre {
      overflow: auto;
      margin: 0.7rem 0 0;
      padding: 0.9rem;
      border-radius: 6px;
      background: #0b0d0f;
    }
    code {
      font-family: var(--font-code);
      font-size: 0.9rem;
    }
    @media (max-width: 820px) {
      body { display: block; }
      .sidebar {
        position: fixed;
        left: -100%;
        transition: left 0.24s ease;
      }
      .sidebar.open { left: 0; }
      .menu-toggle { display: inline-block; }
      .content { padding: 1.25rem; }
    }
    @media (max-width: 520px) {
      .content { padding: 1rem; }
      .params-table th:nth-child(3),
      .params-table td:nth-child(3) { display: none; }
    }
  </style>
</head>
<body>
  <div class="sidebar-overlay" id="sidebarOverlay"></div>
  <nav class="sidebar" id="sidebar">
    <div class="brand">
      <span class="brand-mark" aria-hidden="true"></span>
      <span class="brand-title">${_escape(options.brandName)}</span>
      <button class="menu-toggle" id="menuToggle" type="button"
        aria-label="Toggle navigation">=</button>
      $homeLink
    </div>
    <div class="sidebar-links" id="sidebarLinks">${fragments.sidebar}</div>
  </nav>
  <main class="content" id="content">${fragments.content}</main>
  <script>
    function setExpanded(button, expanded) {
      const group = button.closest('.section-group');
      const items = group.querySelector('.section-items');
      button.classList.toggle('collapsed', !expanded);
      button.setAttribute('aria-expanded', expanded ? 'true' : 'false');
      items.style.maxHeight = expanded ? items.scrollHeight + 'px' : '0px';
    }
    document.querySelectorAll('.section-toggle').forEach((button) => {
      button.addEventListener('click', () => {
        setExpanded(button, button.classList.contains('collapsed'));
      });
    });
    document.querySelectorAll('.section-items').forEach((items) => {
      items.style.maxHeight = items.scrollHeight + 'px';
    });
    const sidebar = document.getElementById('sidebar');
    const overlay = document.getElementById('sidebarOverlay');
    const menuToggle = document.getElementById('menuToggle');
    function closeSidebar() {
      sidebar.classList.remove('open');
      overlay.classList.remove('open');
    }
    menuToggle.addEventListener('click', () => {
      sidebar.classList.toggle('open');
      overlay.classList.toggle('open');
    });
    overlay.addEventListener('click', closeSidebar);
    document.querySelectorAll('.sidebar a.func').forEach((link) => {
      link.addEventListener('click', closeSidebar);
    });
  </script>
</body>
</html>''';
}

/// Builds a stable JSON-serializable manifest for editor tooling.
///
/// The manifest intentionally mirrors the documentation data exposed by
/// [Library.getDocs] so IDEs, language servers, and generators can discover the
/// same library surface that the shared HTML UI displays.
Map<String, Object?> buildDocsManifest(
  List<Library> libraries, {
  String packageName = 'lualike',
  String? packageVersion,
}) {
  final documentedLibraries = <Map<String, Object?>>[];
  for (final lib in libraries) {
    final docs = lib.getDocs();
    if (docs.isEmpty) continue;
    final libraryName = _libraryDocName(lib, docs);
    documentedLibraries.add(<String, Object?>{
      'name': libraryName,
      'description': lib.description,
      'functions': [
        for (final entry in docs.entries)
          _functionManifestEntry(
            name: entry.key,
            libraryName: libraryName,
            doc: entry.value,
          ),
      ],
    });
  }

  final manifest = <String, Object?>{
    'schemaVersion': 1,
    'generator': 'lualike.docs',
    'package': packageName,
  };
  if (packageVersion != null) {
    manifest['packageVersion'] = packageVersion;
  }
  manifest['libraries'] = documentedLibraries;
  return manifest;
}

Map<String, Object?> _functionManifestEntry({
  required String name,
  required String libraryName,
  required FunctionDoc doc,
}) {
  return <String, Object?>{
    'name': name,
    'qualifiedName': _qualifiedFunctionName(libraryName, name),
    'kind': 'function',
    'library': libraryName,
    'category': doc.category,
    'signature': _signatureText(name, doc),
    'summary': doc.summary,
    'params': [
      for (final param in doc.params)
        <String, Object?>{
          'name': param.name,
          'type': param.type,
          'description': param.description,
          'optional': param.optional,
        },
    ],
    if (doc.returns != null) 'returns': doc.returns,
    if (doc.example != null) 'example': doc.example,
  };
}

/// Encodes [buildDocsManifest] as indented JSON for tools and editors.
String renderDocsJson(
  List<Library> libraries, {
  String packageName = 'lualike',
  String? packageVersion,
}) {
  final manifest = buildDocsManifest(
    libraries,
    packageName: packageName,
    packageVersion: packageVersion,
  );
  return const JsonEncoder.withIndent('  ').convert(manifest);
}

/// Renders LuaLS-compatible annotation stubs for the documented libraries.
///
/// The output is valid Lua source intended to be indexed by LuaLS as a
/// definition file. It uses `---@meta`, table declarations, `---@param`, and
/// `---@return` annotations so existing Lua language tooling can provide
/// completion, hover text, and signature help without LuaLike owning an LSP.
String renderLuaLsAnnotations(
  List<Library> libraries, {
  String packageName = 'lualike',
  String? packageVersion,
}) {
  final buf = StringBuffer()
    ..writeln('---@meta _')
    ..writeln('---Generated LuaLS annotations for $packageName.')
    ..writeln('---Do not execute this file; add it to LuaLS as a library.')
    ..writeln('---Generator: lualike.docs')
    ..writeln('---Schema: 1');
  if (packageVersion != null) {
    buf.writeln('---Package version: $packageVersion');
  }
  buf.writeln();

  final emittedTables = <String>{};
  for (final lib in libraries) {
    final docs = lib.getDocs();
    if (docs.isEmpty) {
      continue;
    }
    final libraryName = _libraryDocName(lib, docs);
    if (libraryName != 'base') {
      _emitLuaLsTable(buf, libraryName, emittedTables);
    }

    for (final entry in docs.entries) {
      final qualifiedName = _qualifiedFunctionName(libraryName, entry.key);
      _emitLuaLsFunction(
        buf,
        qualifiedName: qualifiedName,
        doc: entry.value,
        emittedTables: emittedTables,
      );
    }
  }

  return buf.toString();
}

void _emitLuaLsTable(
  StringBuffer buf,
  String qualifiedName,
  Set<String> emittedTables,
) {
  final parts = qualifiedName.split('.');
  for (var i = 1; i <= parts.length; i++) {
    final tableName = parts.take(i).join('.');
    if (!emittedTables.add(tableName)) {
      continue;
    }
    buf
      ..writeln('---@type table')
      ..writeln('$tableName = $tableName or {}')
      ..writeln();
  }
}

void _emitLuaLsFunction(
  StringBuffer buf, {
  required String qualifiedName,
  required FunctionDoc doc,
  required Set<String> emittedTables,
}) {
  final parentPath = _parentPath(qualifiedName);
  if (parentPath != null) {
    _emitLuaLsTable(buf, parentPath, emittedTables);
  }

  for (final line in _docLines(doc.summary)) {
    buf.writeln('---$line');
  }
  for (final param in doc.params) {
    final name = _luaIdentifier(param.name);
    final optional = param.optional && name != '...' ? '?' : '';
    final type = _luaLsType(param.type);
    final description = _luaLsTrailingDescription(param.description);
    buf.writeln('---@param $name$optional $type$description');
  }
  if (doc.returns != null && !_returnsNothing(doc.returns!)) {
    final description = _luaLsTrailingDescription(doc.returns!);
    final types = doc.returnType ?? _returnTypeForLuaLs(doc.returns!);
    final parts = types.split(', ');
    for (var i = 0; i < parts.length; i++) {
      final annotation = i == 0
          ? '---@return ${parts[i]}$description'
          : '---@return ${parts[i]}';
      buf.writeln(annotation);
    }
  }

  final parameters = doc.params
      .map((param) => _luaIdentifier(param.name))
      .where((name) => name.isNotEmpty)
      .join(', ');
  buf
    ..writeln('function $qualifiedName($parameters) end')
    ..writeln();
}

String? _parentPath(String qualifiedName) {
  final dot = qualifiedName.lastIndexOf('.');
  if (dot == -1) {
    return null;
  }
  return qualifiedName.substring(0, dot);
}

String _luaLsTrailingDescription(String description) {
  final text = _docLines(description).join(' ');
  if (text.isEmpty) {
    return '';
  }
  return ' # ${text.replaceAll('|', '\\|')}';
}

String _luaLsType(String type) {
  final normalized = type
      .trim()
      .replaceAll(' ', '')
      .replaceAll(',', '|');
  if (normalized.isEmpty) {
    return 'any';
  }
  return normalized
      .split('|')
      .map(_singleLuaLsType)
      .where((part) => part.isNotEmpty)
      .join('|');
}

String _singleLuaLsType(String type) {
  return switch (type) {
    'bool' => 'boolean',
    'int' => 'integer',
    'double' => 'number',
    'num' => 'number',
    'list' => 'table',
    'map' => 'table',
    'void' => 'nil',
    _ => type,
  };
}

bool _returnsNothing(String returns) {
  final normalized = returns.toLowerCase();
  return normalized.contains('nothing') ||
      normalized.contains('never returns') ||
      normalized == 'nil';
}

String _returnTypeForLuaLs(String returns) {
  final lower = returns.toLowerCase();
  if (lower.startsWith('true') || lower.startsWith('false')) {
    return 'boolean';
  }
  if (lower.contains('boolean') || lower.contains('true if')) {
    return 'boolean';
  }
  if (lower.contains('integer')) {
    return lower.contains('nil') ? 'integer|nil' : 'integer';
  }
  if (lower.contains('number')) {
    return lower.contains('nil') ? 'number|nil' : 'number';
  }
  if (lower.contains('string')) {
    return lower.contains('nil') ? 'string|nil' : 'string';
  }
  if (lower.contains('table')) {
    return lower.contains('nil') ? 'table|nil' : 'table';
  }
  if (lower.contains('function')) {
    return lower.contains('nil') ? 'function|nil' : 'function';
  }
  if (lower.contains('thread') || lower.contains('coroutine')) {
    return lower.contains('nil') ? 'thread|nil' : 'thread';
  }
  return lower.contains('nil') ? 'any|nil' : 'any';
}
