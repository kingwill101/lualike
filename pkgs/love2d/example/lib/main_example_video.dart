import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:love2d/love2d.dart';

const String loveExampleVideoEntryAsset =
    'assets/love_example_browser/video_test_runner.lua';

void main() {
  runApp(const LoveExampleVideoApp());
}

class LoveExampleVideoApp extends StatelessWidget {
  const LoveExampleVideoApp({
    super.key,
    this.bundle,
    this.filesystemAdapter,
    this.audioBackendFactory,
    this.onQuitRequested,
  });

  final AssetBundle? bundle;
  final LoveFilesystemAdapter? filesystemAdapter;
  final LoveAudioBackendFactory? audioBackendFactory;
  final Future<void> Function()? onQuitRequested;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LOVE Video Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF050816),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF9AB7FF),
          secondary: Color(0xFF5EEAD4),
          surface: Color(0xFF111827),
        ),
      ),
      home: _LoveExampleVideoShell(
        bundle: bundle ?? rootBundle,
        filesystemAdapter: filesystemAdapter,
        audioBackendFactory: audioBackendFactory,
        onQuitRequested: onQuitRequested,
      ),
    );
  }
}

class _LoveExampleVideoShell extends StatefulWidget {
  const _LoveExampleVideoShell({
    required this.bundle,
    this.filesystemAdapter,
    this.audioBackendFactory,
    this.onQuitRequested,
  });

  final AssetBundle bundle;
  final LoveFilesystemAdapter? filesystemAdapter;
  final LoveAudioBackendFactory? audioBackendFactory;
  final Future<void> Function()? onQuitRequested;

  @override
  State<_LoveExampleVideoShell> createState() => _LoveExampleVideoShellState();
}

class _LoveExampleVideoShellState extends State<_LoveExampleVideoShell> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LoveFlameHarness(
          title: 'LOVE Video Example',
          entryAsset: loveExampleVideoEntryAsset,
          bundle: widget.bundle,
          filesystemAdapter: widget.filesystemAdapter,
          audioBackendFactory: widget.audioBackendFactory,
          onQuitRequested: widget.onQuitRequested,
        ),
      ),
    );
  }
}
