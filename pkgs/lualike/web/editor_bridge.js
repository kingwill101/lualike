(() => {
  const aceScriptUrls = [
    'https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/ace.js',
    'https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/mode-lua.min.js',
    'https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/theme-tomorrow_night_bright.min.js',
  ];

  let editor = null;
  let pendingValue = '';
  let loaderPromise = null;
  let previousRequire = null;
  let previousDefine = null;

  function restoreAmdGlobals() {
    if (previousRequire !== null) {
      window.require = previousRequire;
    } else {
      delete window.require;
    }

    if (previousDefine !== null) {
      window.define = previousDefine;
    } else {
      delete window.define;
    }
  }

  function loadScript(url) {
    return new Promise((resolve, reject) => {
      const existing = document.querySelector(`script[src="${url}"]`);
      if (existing) {
        resolve();
        return;
      }

      const script = document.createElement('script');
      script.src = url;
      script.onload = () => resolve();
      script.onerror = () =>
        reject(new Error(`Failed to load script: ${url}`));
      document.head.appendChild(script);
    });
  }

  function loadAce() {
    if (loaderPromise) {
      return loaderPromise;
    }

    loaderPromise = new Promise((resolve, reject) => {
      if (window.ace?.edit) {
        resolve(window.ace);
        return;
      }

      previousRequire = window.require ?? null;
      previousDefine = window.define ?? null;

      aceScriptUrls
        .reduce(
          (promise, url) => promise.then(() => loadScript(url)),
          Promise.resolve(),
        )
        .then(() => {
          restoreAmdGlobals();
          if (!window.ace?.edit) {
            throw new Error('Ace editor did not initialize.');
          }
          resolve(window.ace);
        })
        .catch((error) => {
          restoreAmdGlobals();
          reject(error);
        });
    });

    return loaderPromise;
  }

  function updateCursorStatus() {
    const target = document.getElementById('editorCursor');
    if (!target) {
      return;
    }

    if (!editor) {
      target.textContent = 'Ln 1, Col 1';
      return;
    }

    const position = editor.getCursorPosition();
    target.textContent = `Ln ${position.row + 1}, Col ${position.column + 1}`;
  }

  function createEditor(initialValue) {
    const container = document.getElementById('sourceCode');
    if (!container) {
      throw new Error('Missing #sourceCode editor mount.');
    }
    if (!window.ace) {
      throw new Error('Ace editor is not available.');
    }

    editor = window.ace.edit(container);
    editor.setTheme('ace/theme/tomorrow_night_bright');
    editor.session.setMode('ace/mode/lua');
    editor.setValue(initialValue, -1);
    editor.setOptions({
      autoScrollEditorIntoView: true,
      behavioursEnabled: true,
      copyWithEmptySelection: true,
      displayIndentGuides: true,
      fontFamily: '"JetBrains Mono", "Fira Code", monospace',
      fontSize: '14px',
      highlightActiveLine: true,
      printMargin: 96,
      scrollPastEnd: 0.25,
      showPrintMargin: true,
      showGutter: true,
      tabSize: 2,
      useSoftTabs: true,
      wrap: true,
    });

    editor.commands.addCommand({
      name: 'run-lualike',
      bindKey: { win: 'Ctrl-Enter', mac: 'Command-Enter' },
      exec: () => {
        window.dispatchEvent(new CustomEvent('lualike-run-request'));
      },
    });

    editor.selection.on('changeCursor', updateCursorStatus);
    editor.session.on('change', () => {
      pendingValue = editor.getValue();
      window.dispatchEvent(new CustomEvent('lualike-editor-change'));
    });

    pendingValue = editor.getValue();
    updateCursorStatus();
    container.dataset.ready = 'true';
    window.dispatchEvent(new CustomEvent('lualike-editor-ready'));
  }

  window.mountLuaLikeEditor = function mountLuaLikeEditor(initialValue) {
    if (typeof initialValue === 'string') {
      pendingValue = initialValue;
    }

    return loadAce().then(() => {
      createEditor(pendingValue);
      return true;
    });
  };

  window.getLuaLikeEditorValue = function getLuaLikeEditorValue() {
    return editor ? editor.getValue() : pendingValue;
  };

  window.setLuaLikeEditorValue = function setLuaLikeEditorValue(value) {
    pendingValue = typeof value === 'string' ? value : '';

    if (!editor) {
      return;
    }

    editor.setValue(pendingValue, -1);
    editor.clearSelection();
    updateCursorStatus();
  };

  window.focusLuaLikeEditor = function focusLuaLikeEditor() {
    editor?.focus();
  };
})();
