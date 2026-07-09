library;

import 'dart:convert';

import '../runtime/lua_runtime.dart' show LuaRuntime;
import '../stdlib/doc.dart'
    show
        AccessScope,
        AliasDoc,
        AliasVariant,
        DocParam,
        EnumDoc,
        FieldDoc,
        FunctionDoc,
        GenericParam,
        OperatorDoc,
        OverloadDoc,
        TableDoc,
        ValueDoc;
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
    final valueDocs = lib.getValueDocs();
    if (docs.isEmpty &&
        lib.getTableDocs().isEmpty &&
        valueDocs.isEmpty &&
        lib.getAliasDocs().isEmpty &&
        lib.getEnumDocs().isEmpty) {
      continue;
    }
    final cat = _libraryDocName(lib, docs);
    final sectionId = 'section-$sectionIndex-${_escapeAttribute(cat)}';
    final anchors = <String, String>{
      for (final name in docs.keys) name: _uniqueAnchor(cat, name, usedAnchors),
      for (final name in valueDocs.keys)
        name: _uniqueAnchor(cat, name, usedAnchors),
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
    for (final name in valueDocs.keys) {
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

    for (final entry in valueDocs.entries) {
      final name = entry.key;
      final doc = entry.value;
      final anchor = anchors[name]!;

      contentBuf.writeln('<article class="func-entry">');
      contentBuf.writeln('<a id="${_escapeAttribute(anchor)}"></a>');
      contentBuf.writeln(
        '<div class="func-signature">${_escape(name)}: '
        '${_escape(doc.type)}</div>',
      );

      final badges = <String>[];
      if (doc.deprecated) {
        badges.add('<span class="badge badge-deprecated">deprecated</span>');
      }
      if (badges.isNotEmpty) {
        contentBuf.writeln('<div class="badges">${badges.join(' ')}</div>');
      }

      if (doc.deprecated) {
        contentBuf.writeln(
          '<div class="func-summary deprecated">${_escape(doc.summary)}</div>',
        );
      } else {
        contentBuf.writeln(
          '<div class="func-summary">${_escape(doc.summary)}</div>',
        );
      }
      if (doc.value != null) {
        contentBuf.writeln(
          '<div class="returns"><strong>Value:</strong> '
          '<code>${_escape(doc.value!)}</code></div>',
        );
      }
      if (doc.see != null) {
        contentBuf.writeln(
          '<div class="see"><strong>See:</strong> '
          '<code>${_escape(doc.see!)}</code></div>',
        );
      }
      if (doc.source != null) {
        contentBuf.writeln(
          '<div class="source"><strong>Source:</strong> '
          '<code>${_escape(doc.source!)}</code></div>',
        );
      }
      if (doc.version != null) {
        contentBuf.writeln(
          '<div class="version"><strong>Version:</strong> '
          '<code>${_escape(doc.version!)}</code></div>',
        );
      }
      contentBuf.writeln('</article>');
    }

    for (final entry in docs.entries) {
      final name = entry.key;
      final doc = entry.value;
      final sig = _signatureText(name, doc);
      final anchor = anchors[name]!;

      contentBuf.writeln('<article class="func-entry">');
      contentBuf.writeln('<a id="${_escapeAttribute(anchor)}"></a>');
      contentBuf.writeln('<div class="func-signature">${_escape(sig)}</div>');

      final badges = <String>[];
      if (doc.deprecated) {
        badges.add('<span class="badge badge-deprecated">deprecated</span>');
      }
      if (doc.async) {
        badges.add('<span class="badge badge-async">async</span>');
      }
      if (doc.nodiscard) {
        badges.add('<span class="badge badge-nodiscard">nodiscard</span>');
      }
      if (doc.scope != AccessScope.public) {
        badges.add('<span class="badge badge-scope">${doc.scope.name}</span>');
      }
      if (badges.isNotEmpty) {
        contentBuf.writeln('<div class="badges">${badges.join(' ')}</div>');
      }

      if (doc.deprecated) {
        contentBuf.writeln(
          '<div class="func-summary deprecated">${_escape(doc.summary)}</div>',
        );
      } else {
        contentBuf.writeln(
          '<div class="func-summary">${_escape(doc.summary)}</div>',
        );
      }
      if (doc.params.isNotEmpty) {
        contentBuf.write(_paramRowsHtml(doc.params));
      }
      if (doc.returns != null) {
        contentBuf.writeln(
          '<div class="returns"><strong>Returns:</strong> '
          '${_escape(doc.returns!)}</div>',
        );
      }
      if (doc.see != null) {
        contentBuf.writeln(
          '<div class="see"><strong>See:</strong> '
          '<code>${_escape(doc.see!)}</code></div>',
        );
      }
      if (doc.source != null) {
        contentBuf.writeln(
          '<div class="source"><strong>Source:</strong> '
          '<code>${_escape(doc.source!)}</code></div>',
        );
      }
      if (doc.version != null) {
        contentBuf.writeln(
          '<div class="version"><strong>Version:</strong> '
          '<code>${_escape(doc.version!)}</code></div>',
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
      --deprecated: #e06c75;
      --async: #61afef;
      --nodiscard: #c678dd;
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
    .func-entry.deprecated {
      opacity: 0.6;
    }
    .badges {
      margin-bottom: 0.4rem;
      display: flex;
      flex-wrap: wrap;
      gap: 0.3rem;
    }
    .badge {
      display: inline-block;
      padding: 0.1rem 0.45rem;
      border-radius: 4px;
      font-size: 0.7rem;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    .badge-deprecated {
      background: var(--deprecated);
      color: #fff;
    }
    .badge-async {
      background: var(--async);
      color: #fff;
    }
    .badge-nodiscard {
      background: var(--nodiscard);
      color: #fff;
    }
    .badge-scope {
      background: var(--soft);
      color: #fff;
    }
    .func-signature {
      margin-bottom: 0.5rem;
      color: var(--code);
      font-family: var(--font-code);
      overflow-wrap: anywhere;
    }
    .func-summary { color: #d8dbe0; margin-bottom: 0.75rem; }
    .func-summary.deprecated {
      text-decoration: line-through;
      color: var(--deprecated);
    }
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
    .p-desc, .returns, .see, .source, .version { color: #d8dbe0; }
    .returns, .see, .source, .version { margin: 0.6rem 0; font-size: 0.86rem; }
    .returns strong, .see strong, .source strong, .version strong { color: var(--soft); }
    .see code, .source code, .version code { color: var(--accent); }
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
    final valueDocs = lib.getValueDocs();
    if (docs.isEmpty &&
        valueDocs.isEmpty &&
        lib.getTableDocs().isEmpty &&
        lib.getAliasDocs().isEmpty &&
        lib.getEnumDocs().isEmpty) {
      continue;
    }
    final libraryName = _libraryDocName(lib, docs);
    final libraryEntry = <String, Object?>{
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
    };

    if (valueDocs.isNotEmpty) {
      libraryEntry['values'] = [
        for (final entry in valueDocs.entries)
          _valueManifestEntry(entry.key, entry.value),
      ];
    }

    final aliases = lib.getAliasDocs();
    if (aliases.isNotEmpty) {
      libraryEntry['aliases'] = [
        for (final entry in aliases.entries) _aliasManifestEntry(entry.value),
      ];
    }

    final enums = lib.getEnumDocs();
    if (enums.isNotEmpty) {
      libraryEntry['enums'] = [
        for (final entry in enums.entries) _enumManifestEntry(entry.value),
      ];
    }

    final tableDocs = lib.getTableDocs();
    if (tableDocs.isNotEmpty) {
      libraryEntry['tables'] = [
        for (final entry in tableDocs.entries)
          _tableDocManifestEntry(entry.key, entry.value),
      ];
    }

    documentedLibraries.add(libraryEntry);
  }

  final manifest = <String, Object?>{
    'schemaVersion': 2,
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
  final entry = <String, Object?>{
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
    if (doc.returnType != null) 'returnType': doc.returnType,
    if (doc.example != null) 'example': doc.example,
  };

  if (doc.deprecated) {
    entry['deprecated'] = true;
    if (doc.deprecatedReason != null) {
      entry['deprecatedReason'] = doc.deprecatedReason;
    }
  }
  if (doc.async) {
    entry['async'] = true;
  }
  if (doc.nodiscard) {
    entry['nodiscard'] = true;
  }
  if (doc.scope != AccessScope.public) {
    entry['scope'] = doc.scope.name;
  }
  if (doc.generics.isNotEmpty) {
    entry['generics'] = doc.generics
        .map(
          (g) => <String, Object?>{
            'name': g.name,
            if (g.parentType != null) 'parentType': g.parentType,
          },
        )
        .toList();
  }
  if (doc.overloads.isNotEmpty) {
    entry['overloads'] = doc.overloads.map(_overloadManifestEntry).toList();
  }
  if (doc.see != null) {
    entry['see'] = doc.see;
  }
  if (doc.source != null) {
    entry['source'] = doc.source;
  }
  if (doc.version != null) {
    entry['version'] = doc.version;
  }

  return entry;
}

Map<String, Object?> _overloadManifestEntry(OverloadDoc doc) {
  return <String, Object?>{
    'params': [
      for (final param in doc.params)
        <String, Object?>{
          'name': param.name,
          'type': param.type,
          'description': param.description,
          'optional': param.optional,
        },
    ],
    if (doc.returnType != null) 'returnType': doc.returnType,
    if (doc.returns != null) 'returns': doc.returns,
  };
}

Map<String, Object?> _aliasManifestEntry(AliasDoc doc) {
  return <String, Object?>{
    'name': doc.name,
    if (doc.type != null) 'type': doc.type,
    if (doc.description != null) 'description': doc.description,
    if (doc.variants.isNotEmpty)
      'variants': doc.variants
          .map(
            (AliasVariant v) => <String, Object?>{
              'value': v.value,
              if (v.description != null) 'description': v.description,
            },
          )
          .toList(),
  };
}

Map<String, Object?> _valueManifestEntry(String name, ValueDoc doc) {
  return <String, Object?>{
    'name': name,
    'type': doc.type,
    'summary': doc.summary,
    if (doc.value != null) 'value': doc.value,
    if (doc.deprecated) 'deprecated': true,
    if (doc.deprecatedReason != null) 'deprecatedReason': doc.deprecatedReason,
    if (doc.see != null) 'see': doc.see,
    if (doc.source != null) 'source': doc.source,
    if (doc.version != null) 'version': doc.version,
  };
}

Map<String, Object?> _enumManifestEntry(EnumDoc doc) {
  return <String, Object?>{
    'name': doc.name,
    if (doc.description != null) 'description': doc.description,
    'useKeys': doc.useKeys,
    'entries': doc.entries,
  };
}

Map<String, Object?> _tableDocManifestEntry(String name, TableDoc doc) {
  return <String, Object?>{
    'name': doc.name,
    'description': doc.description,
    'fields': doc.fields.map(_fieldDocManifestEntry).toList(),
    if (doc.version != null) 'version': doc.version,
    if (doc.operators.isNotEmpty)
      'operators': doc.operators
          .map(
            (OperatorDoc o) => <String, Object?>{
              'operation': o.operation,
              if (o.paramType != null) 'paramType': o.paramType,
              'returnType': o.returnType,
            },
          )
          .toList(),
  };
}

Map<String, Object?> _fieldDocManifestEntry(FieldDoc doc) {
  return <String, Object?>{
    'key': doc.key,
    'type': doc.type,
    'description': doc.description,
    'required': doc.required,
    if (doc.deprecated) 'deprecated': true,
    if (doc.scope != AccessScope.public) 'scope': doc.scope.name,
    if (doc.defaultValue != null) 'defaultValue': '${doc.defaultValue}',
    if (doc.group != null) 'group': doc.group,
    if (doc.dependsOn != null) 'dependsOn': doc.dependsOn,
    if (doc.min != null) 'min': doc.min,
    if (doc.max != null) 'max': doc.max,
    if (doc.step != null) 'step': doc.step,
    if (doc.choices != null) 'choices': doc.choices,
    if (doc.fields != null && doc.fields!.isNotEmpty)
      'fields': doc.fields!.map(_fieldDocManifestEntry).toList(),
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
    ..writeln('---Schema: 2');
  if (packageVersion != null) {
    buf.writeln('---Package version: $packageVersion');
  }
  buf.writeln();

  final emittedTables = <String>{};
  for (final lib in libraries) {
    final docs = lib.getDocs();
    final tableDocs = lib.getTableDocs();
    final aliasDocs = lib.getAliasDocs();
    final enumDocs = lib.getEnumDocs();
    final valueDocs = lib.getValueDocs();

    if (docs.isEmpty &&
        tableDocs.isEmpty &&
        aliasDocs.isEmpty &&
        enumDocs.isEmpty &&
        valueDocs.isEmpty) {
      continue;
    }
    final libraryName = _libraryDocName(lib, docs);
    if (lib.name.isNotEmpty) {
      _emitLuaLsTable(buf, libraryName, emittedTables);
    }

    final useNamespace = lib.name.isNotEmpty;

    // Emit aliases
    for (final entry in aliasDocs.entries) {
      _emitLuaLsAliasDoc(buf, entry.value);
    }

    // Emit enums
    for (final entry in enumDocs.entries) {
      _emitLuaLsEnumDoc(buf, entry.value);
    }

    // Emit value/constant definitions
    for (final entry in valueDocs.entries) {
      final qualifiedName = useNamespace
          ? _qualifiedFunctionName(libraryName, entry.key)
          : entry.key;
      _emitLuaLsValueDoc(buf, qualifiedName, entry.value, emittedTables);
    }

    // Emit table schema class definitions
    for (final entry in tableDocs.entries) {
      final qualifiedName = useNamespace
          ? _qualifiedFunctionName(libraryName, entry.key)
          : entry.key;
      _emitLuaLsTableDoc(buf, qualifiedName, entry.value);
    }

    // Emit function definitions (skip names already defined as tables)
    for (final entry in docs.entries) {
      final qualifiedName = _qualifiedFunctionName(libraryName, entry.key);
      if (tableDocs.containsKey(entry.key) ||
          tableDocs.containsKey(qualifiedName)) {
        final globalName = useNamespace ? qualifiedName : entry.key;
        _emitLuaLsTypedGlobal(buf, globalName, emittedTables);
        continue;
      }
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

void _emitLuaLsAliasDoc(StringBuffer buf, AliasDoc doc) {
  if (doc.variants.isNotEmpty) {
    buf.writeln('---@alias ${doc.name}');
    if (doc.description != null) {
      for (final line in _docLines(doc.description!)) {
        buf.writeln('---$line');
      }
    }
    for (final AliasVariant variant in doc.variants) {
      final desc = variant.description != null
          ? ' # ${variant.description}'
          : '';
      buf.writeln("---| '${variant.value}'$desc");
    }
  } else {
    final type = doc.type ?? 'any';
    final desc = doc.description != null ? ' ${doc.description}' : '';
    buf.writeln('---@alias ${doc.name} $type$desc');
  }
  buf.writeln();
}

void _emitLuaLsEnumDoc(StringBuffer buf, EnumDoc doc) {
  final attr = doc.useKeys ? '(key) ' : '';
  buf.writeln('---@enum $attr${doc.name}');
  if (doc.description != null) {
    for (final line in _docLines(doc.description!)) {
      buf.writeln('---$line');
    }
  }
  buf.writeln('local ${_luaIdentifier(doc.name)} = {');
  for (final entry in doc.entries.entries) {
    buf.writeln('  ${entry.key} = ${entry.value},');
  }
  buf.writeln('}');
  buf.writeln();
}

void _emitLuaLsValueDoc(
  StringBuffer buf,
  String qualifiedName,
  ValueDoc doc,
  Set<String> emittedTables,
) {
  final parentPath = _parentPath(qualifiedName);
  if (parentPath != null) {
    _emitLuaLsTable(buf, parentPath, emittedTables);
  }

  if (doc.deprecated) {
    buf.writeln('---@deprecated');
  }

  for (final line in _docLines(doc.summary)) {
    buf.writeln('---$line');
  }

  if (doc.see != null) {
    buf.writeln('---@see ${doc.see}');
  }

  if (doc.source != null) {
    buf.writeln('---@source ${doc.source}');
  }

  if (doc.version != null) {
    buf.writeln('---@version ${doc.version}');
  }

  buf.writeln('---@type ${doc.type}');

  if (doc.value != null) {
    buf.writeln('$qualifiedName = ${doc.value}');
  } else {
    buf.writeln('$qualifiedName = $qualifiedName or {}');
  }
  buf.writeln();
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

  // Deprecated
  if (doc.deprecated) {
    buf.writeln('---@deprecated');
  }

  // Async
  if (doc.async) {
    buf.writeln('---@async');
  }

  // Nodiscard
  if (doc.nodiscard) {
    buf.writeln('---@nodiscard');
  }

  // Scope
  if (doc.scope != AccessScope.public) {
    buf.writeln('---@${doc.scope.name}');
  }

  // Summary
  for (final line in _docLines(doc.summary)) {
    buf.writeln('---$line');
  }

  // See
  if (doc.see != null) {
    buf.writeln('---@see ${doc.see}');
  }

  // Source
  if (doc.source != null) {
    buf.writeln('---@source ${doc.source}');
  }

  // Version
  if (doc.version != null) {
    buf.writeln('---@version ${doc.version}');
  }

  // Generics
  for (final GenericParam generic in doc.generics) {
    if (generic.parentType != null) {
      buf.writeln('---@generic ${generic.name} : ${generic.parentType}');
    } else {
      buf.writeln('---@generic ${generic.name}');
    }
  }

  // Params
  for (final param in doc.params) {
    final name = _luaIdentifier(param.name);
    final optional = param.optional && name != '...' ? '?' : '';
    final type = _luaLsType(param.type);
    final description = _luaLsTrailingDescription(param.description);
    buf.writeln('---@param $name$optional $type$description');
  }

  // Returns
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

  // Overloads
  for (final overload in doc.overloads) {
    final params = overload.params
        .map((p) => '${p.name}: ${_luaLsType(p.type)}')
        .join(', ');
    final returnTypes = overload.returnType != null
        ? overload.returnType!
        : (overload.returns != null
              ? _returnTypeForLuaLs(overload.returns!)
              : 'any');
    buf.writeln('---@overload fun($params): $returnTypes');
  }

  final parameters = doc.params
      .map((param) => _luaIdentifier(param.name))
      .where((name) => name.isNotEmpty)
      .join(', ');
  buf
    ..writeln('function $qualifiedName($parameters) end')
    ..writeln();
}

void _emitLuaLsTableDoc(StringBuffer buf, String qualifiedName, TableDoc doc) {
  buf.writeln('---@class $qualifiedName');

  // Version
  if (doc.version != null) {
    buf.writeln('---@version ${doc.version}');
  }

  for (final line in _docLines(doc.description)) {
    buf.writeln('---$line');
  }
  buf.writeln('---');
  for (final field in doc.fields) {
    _emitLuaLsField(buf, qualifiedName, field, '');
  }

  // Operators
  for (final OperatorDoc op in doc.operators) {
    if (op.paramType != null) {
      buf.writeln(
        '---@operator ${op.operation}(${op.paramType}): ${op.returnType}',
      );
    } else {
      buf.writeln('---@operator ${op.operation}:${op.returnType}');
    }
  }

  buf.writeln();
}

void _emitLuaLsField(
  StringBuffer buf,
  String className,
  FieldDoc field,
  String prefix,
) {
  if (field.deprecated) {
    buf.writeln('---@deprecated');
  }
  final opt = field.required ? '' : '?';
  final key = '$prefix${field.key}';
  final type = _luaLsType(field.type);
  final description = _luaLsTrailingDescription(field.description);
  final scope = field.scope != AccessScope.public ? '${field.scope.name} ' : '';
  buf.writeln('---@field $scope$key$opt $type$description');

  if (field.fields != null && field.fields!.isNotEmpty) {
    for (final sub in field.fields!) {
      _emitLuaLsField(buf, className, sub, '$key.');
    }
  }
}

void _emitLuaLsTypedGlobal(
  StringBuffer buf,
  String qualifiedName,
  Set<String> emittedTables,
) {
  final parentPath = _parentPath(qualifiedName);
  if (parentPath != null) {
    _emitLuaLsTable(buf, parentPath, emittedTables);
  }
  buf
    ..writeln('---@type $qualifiedName')
    ..writeln('$qualifiedName = {}')
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
  final normalized = type.trim().replaceAll(' ', '').replaceAll(',', '|');
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
