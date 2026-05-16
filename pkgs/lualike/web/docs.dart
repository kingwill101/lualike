import 'dart:js_interop';

import 'package:lualike/docs.dart';
import 'package:lualike/lualike.dart';
import 'package:web/web.dart' as web;

@JS('Prism.highlightAll')
external JSAny? _highlightAll();

void main() {
  final lua = LuaLike();
  final vm = lua.vm;

  // Force-initialize lazy libraries so registerFunctions populates docs.
  vm.libraryRegistry.initializeAll();

  final result = renderDocs(vm.libraryRegistry.libraries);

  final sidebar = web.document.querySelector('#sidebarLinks') as web.HTMLElement;
  final content = web.document.querySelector('#content') as web.HTMLElement;
  sidebar.textContent = '';
  content.textContent = '';
  sidebar.insertAdjacentHTML('beforeend', result.sidebar.toJS);
  content.insertAdjacentHTML('beforeend', result.content.toJS);

  _highlightAll();
}
