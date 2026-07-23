import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('LoveFlameInputAdapter text editing bridge', () {
    late LoveHeadlessHost host;
    late LoveScriptRuntime runtime;
    late LoveFlameInputAdapter adapter;

    setUp(() async {
      host = LoveHeadlessHost();
      runtime = LoveScriptRuntime(host: host);
      adapter = LoveFlameInputAdapter(
        host: host,
        runtimeProvider: () => runtime,
      );

      await runtime.execute('''
testbed = {}

function love.textedited(text, start, length)
  local formatted = string.format("%s|%d|%d", text, start, length)
  testbed.editedCount = (testbed.editedCount or 0) + 1
  if testbed.firstEdited == nil then
    testbed.firstEdited = formatted
  end
  testbed.lastEdited = formatted
end

function love.textinput(text)
  testbed.inputCount = (testbed.inputCount or 0) + 1
  testbed.lastInput = text
end
''');
    });

    test(
      'dispatches candidate and committed text from editing values',
      () async {
        adapter.beginPlatformTextInputSession();

        adapter.handleTextEditingValue(
          const TextEditingValue(
            text: 'he',
            selection: TextSelection(baseOffset: 1, extentOffset: 2),
            composing: TextRange(start: 0, end: 2),
          ),
        );
        await _flushQueuedTextInput(adapter, runtime);

        expect(runtime.unwrapGlobalTable('testbed')!['firstEdited'], 'he|1|1');
        expect(runtime.unwrapGlobalTable('testbed')!['editedCount'], 1.0);
        expect(runtime.unwrapGlobalTable('testbed')!['inputCount'], isNull);

        adapter.handleTextEditingValue(
          const TextEditingValue(
            text: 'he',
            selection: TextSelection.collapsed(offset: 2),
          ),
        );
        await _flushQueuedTextInput(adapter, runtime);

        expect(runtime.unwrapGlobalTable('testbed')!['editedCount'], 2.0);
        expect(runtime.unwrapGlobalTable('testbed')!['lastEdited'], '|0|0');
        expect(runtime.unwrapGlobalTable('testbed')!['inputCount'], 1.0);
        expect(runtime.unwrapGlobalTable('testbed')!['lastInput'], 'he');
      },
    );

    test('clears pending composition when the platform session ends', () async {
      adapter.beginPlatformTextInputSession();

      adapter.handleTextEditingValue(
        const TextEditingValue(
          text: 'compose',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 0, end: 7),
        ),
      );
      await _flushQueuedTextInput(adapter, runtime);

      adapter.endPlatformTextInputSession();
      await _flushQueuedTextInput(adapter, runtime);

      expect(runtime.unwrapGlobalTable('testbed')!['editedCount'], 2.0);
      expect(
        runtime.unwrapGlobalTable('testbed')!['firstEdited'],
        'compose|3|0',
      );
      expect(runtime.unwrapGlobalTable('testbed')!['lastEdited'], '|0|0');
      expect(runtime.unwrapGlobalTable('testbed')!['inputCount'], isNull);
    });
  });
}

Future<void> _flushQueuedTextInput(
  LoveFlameInputAdapter adapter,
  LoveScriptRuntime runtime,
) async {
  await adapter.flush();
  await runtime.processMainLoopEvents();
}
