import 'dart:convert' as convert;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';
import 'package:path/path.dart' as path;

Future<void> _bootEntry(String entryAsset) async {
  final host = LoveHeadlessHost();
  final runtime = LoveScriptRuntime(
    engineMode: EngineMode.luaBytecode,
    host: host,
    filesystemAdapter: await LoveAssetBundleFilesystemAdapter.load(
      bundle: rootBundle,
      fallback: LoveLualikeFilesystemAdapter(),
    ),
  );
  final filesystem = LoveFilesystemState.of(runtime.runtime);

  expect(filesystem.setSource(entryAsset), isTrue);
  await runtime.loadConfIfPresent();
  final logicalEntryAsset = path.basename(entryAsset);
  final entryData = await filesystem.readFileData(
    logicalEntryAsset,
    filename: entryAsset,
  );
  expect(entryData, isNotNull);

  final data = entryData!;
  await runtime
      .execute(convert.utf8.decode(data.bytes), scriptPath: data.filename)
      .timeout(const Duration(seconds: 10));
  await runtime.callLoadIfDefined().timeout(const Duration(seconds: 10));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('basic hello world boots and draws', (tester) async {
    await _bootEntry('assets/scripts/basic_hello.lua');

    final host = LoveHeadlessHost();
    final runtime = LoveScriptRuntime(
      engineMode: EngineMode.luaBytecode,
      host: host,
      filesystemAdapter: await LoveAssetBundleFilesystemAdapter.load(
        bundle: rootBundle,
        fallback: LoveLualikeFilesystemAdapter(),
      ),
    );
    final filesystem = LoveFilesystemState.of(runtime.runtime);
    expect(filesystem.setSource('assets/scripts/basic_hello.lua'), isTrue);
    await runtime.loadConfIfPresent();
    final entryData = await filesystem.readFileData(
      path.basename('assets/scripts/basic_hello.lua'),
      filename: 'assets/scripts/basic_hello.lua',
    );
    expect(entryData, isNotNull);
    await runtime.execute(
      convert.utf8.decode(entryData!.bytes),
      scriptPath: entryData.filename,
    );
    await runtime.callLoadIfDefined();
    await runtime.callUpdateIfDefined(1 / 60);
    runtime.context.beginDrawFrame();
    runtime.context.graphics.origin();
    await runtime.callDrawIfDefined();

    expect(runtime.context.graphics.commands, isNotEmpty);
    expect(runtime.unwrapGlobalTable('testbed'), isNull);
  });

  testWidgets('basic counter increments on update', (tester) async {
    final host = LoveHeadlessHost();
    final runtime = LoveScriptRuntime(
      engineMode: EngineMode.luaBytecode,
      host: host,
      filesystemAdapter: await LoveAssetBundleFilesystemAdapter.load(
        bundle: rootBundle,
        fallback: LoveLualikeFilesystemAdapter(),
      ),
    );
    final filesystem = LoveFilesystemState.of(runtime.runtime);
    expect(filesystem.setSource('assets/scripts/basic_counter.lua'), isTrue);
    await runtime.loadConfIfPresent();
    final entryData = await filesystem.readFileData(
      path.basename('assets/scripts/basic_counter.lua'),
      filename: 'assets/scripts/basic_counter.lua',
    );
    expect(entryData, isNotNull);
    await runtime.execute(
      convert.utf8.decode(entryData!.bytes),
      scriptPath: entryData.filename,
    );
    await runtime.callLoadIfDefined();
    await runtime.callUpdateIfDefined(1 / 60);
    await runtime.callUpdateIfDefined(1 / 60);

    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    expect(snapshot['count'], greaterThanOrEqualTo(2));
  });

  testWidgets('basic input probe records keyboard, mouse, and touch', (
    tester,
  ) async {
    final host = LoveHeadlessHost();
    final runtime = LoveScriptRuntime(
      engineMode: EngineMode.luaBytecode,
      host: host,
      filesystemAdapter: await LoveAssetBundleFilesystemAdapter.load(
        bundle: rootBundle,
        fallback: LoveLualikeFilesystemAdapter(),
      ),
    );
    final filesystem = LoveFilesystemState.of(runtime.runtime);
    expect(filesystem.setSource('assets/scripts/basic_input_probe.lua'), isTrue);
    await runtime.loadConfIfPresent();
    final entryData = await filesystem.readFileData(
      path.basename('assets/scripts/basic_input_probe.lua'),
      filename: 'assets/scripts/basic_input_probe.lua',
    );
    expect(entryData, isNotNull);
    await runtime.execute(
      convert.utf8.decode(entryData!.bytes),
      scriptPath: entryData.filename,
    );
    await runtime.callLoadIfDefined();
    await runtime.callKeyPressedIfDefined('space');
    await runtime.callMousePressedIfDefined(100, 120, 1);
    await runtime.callTouchPressedIfDefined(7, 50, 60, 0, 0, 1.0);
    runtime.context.beginDrawFrame();
    runtime.context.graphics.origin();
    await runtime.callDrawIfDefined();

    final snapshot = runtime.unwrapGlobalTable('testbed')!;
    expect(snapshot['key'], 'space');
    expect(snapshot['mouse'], isNotNull);
    expect(snapshot['touch'], isNotNull);
    expect(snapshot['draws'], greaterThanOrEqualTo(1));
  });
}
