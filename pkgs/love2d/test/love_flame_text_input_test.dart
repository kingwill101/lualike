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
  local poll = love.event.poll()
  local name, queuedText, queuedStart, queuedLength = poll()
  local formatted = string.format("%s|%s|%d|%d|%s|%d|%d", name, queuedText, queuedStart, queuedLength, text, start, length)
  testbed.editedCount = (testbed.editedCount or 0) + 1
  if testbed.firstEdited == nil then
    testbed.firstEdited = formatted
  end
  testbed.lastEdited = formatted
end

function love.textinput(text)
  local poll = love.event.poll()
  local name, queuedText = poll()
  testbed.inputCount = (testbed.inputCount or 0) + 1
  testbed.lastInput = string.format("%s|%s|%s", name, queuedText, text)
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
        await adapter.flush();

        expect(
          runtime.unwrapGlobalTable('testbed')!['firstEdited'],
          'textedited|he|1|1|he|1|1',
        );
        expect(runtime.unwrapGlobalTable('testbed')!['editedCount'], 1.0);
        expect(runtime.unwrapGlobalTable('testbed')!['inputCount'], isNull);

        adapter.handleTextEditingValue(
          const TextEditingValue(
            text: 'he',
            selection: TextSelection.collapsed(offset: 2),
          ),
        );
        await adapter.flush();

        expect(runtime.unwrapGlobalTable('testbed')!['editedCount'], 2.0);
        expect(
          runtime.unwrapGlobalTable('testbed')!['lastEdited'],
          'textedited||0|0||0|0',
        );
        expect(runtime.unwrapGlobalTable('testbed')!['inputCount'], 1.0);
        expect(
          runtime.unwrapGlobalTable('testbed')!['lastInput'],
          'textinput|he|he',
        );
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
      await adapter.flush();

      adapter.endPlatformTextInputSession();
      await adapter.flush();

      expect(runtime.unwrapGlobalTable('testbed')!['editedCount'], 2.0);
      expect(
        runtime.unwrapGlobalTable('testbed')!['firstEdited'],
        'textedited|compose|3|0|compose|3|0',
      );
      expect(
        runtime.unwrapGlobalTable('testbed')!['lastEdited'],
        'textedited||0|0||0|0',
      );
      expect(runtime.unwrapGlobalTable('testbed')!['inputCount'], isNull);
    });
  });
}
