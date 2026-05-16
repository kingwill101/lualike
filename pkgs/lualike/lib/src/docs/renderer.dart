library;

import '../stdlib/doc.dart' show DocParam, FunctionDoc;
import '../stdlib/library.dart' show Library;

/// Result of rendering documentation to HTML fragments.
class DocHtmlResult {
  final String sidebar;
  final String content;

  const DocHtmlResult({required this.sidebar, required this.content});
}

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _signatureHtml(String name, FunctionDoc doc) {
  final parts = [name];
  for (final p in doc.params) {
    parts.add(p.optional ? '[${p.name}]' : p.name);
  }
  return parts.join(' ');
}

String _paramRowsHtml(List<DocParam> params) {
  if (params.isEmpty) return '';
  return '''
  <table class="params-table">
    <tr><th>Name</th><th>Type</th><th>Description</th></tr>
    ${params.map((p) {
      return '''
    <tr>
      <td class="p-name">${_escape(p.name)}</td>
      <td class="p-type">${_escape(p.type)}${p.optional ? ' (optional)' : ''}</td>
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

  for (final lib in libraries) {
    final docs = lib.getDocs();
    if (docs.isEmpty) continue;
    final cat = lib.name.isEmpty ? 'base' : lib.name;

    sidebarBuf.writeln('<h2>${_escape(cat)}</h2>');
    for (final name in docs.keys) {
      sidebarBuf.writeln(
        '<a class="func" href="#${_escape(name)}">${_escape(name)}</a>',
      );
    }

    contentBuf.writeln('<h2>${_escape(cat)}</h2>');
    if (lib.description.isNotEmpty) {
      contentBuf.writeln(
        '<p class="library-desc">${_escape(lib.description)}</p>',
      );
    }

    for (final entry in docs.entries) {
      final name = entry.key;
      final doc = entry.value;
      final sig = _signatureHtml(name, doc);

      contentBuf.writeln('<div class="func-entry">');
      contentBuf.writeln('<a id="${_escape(name)}"></a>');
      contentBuf.writeln(
        '<div class="func-signature">${_escape(sig)}</div>',
      );
      contentBuf.writeln(
        '<div class="func-summary">${_escape(doc.summary)}</div>',
      );
      if (doc.params.isNotEmpty) {
        contentBuf.write(_paramRowsHtml(doc.params));
      }
      if (doc.returns != null) {
        contentBuf.writeln(
          '<div class="returns"><strong>Returns:</strong> ${_escape(doc.returns!)}</div>',
        );
      }
      if (doc.example != null) {
        contentBuf.writeln(
          '<pre class="language-lua"><code class="language-lua">'
          '${_escape(doc.example!)}</code></pre>',
        );
      }
      contentBuf.writeln('</div>');
    }
  }

  return DocHtmlResult(
    sidebar: sidebarBuf.toString(),
    content: contentBuf.toString(),
  );
}
