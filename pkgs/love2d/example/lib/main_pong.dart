import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:love2d/love2d.dart';

const String modernPongEntryAsset = 'assets/modern_pong/main.lua';

void main() {
  runApp(const ModernPongExampleApp());
}

class ModernPongExampleApp extends StatelessWidget {
  const ModernPongExampleApp({
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
      title: 'Modern Pong',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF050816),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFBFDBFE),
          secondary: Color(0xFFF59E0B),
          surface: Color(0xFF111827),
        ),
      ),
      home: Scaffold(
        body: SafeArea(
          child: LoveFlameHarness(
            title: 'Modern Pong',
            entryAsset: modernPongEntryAsset,
            bundle: bundle ?? rootBundle,
            filesystemAdapter: filesystemAdapter,
            audioBackendFactory: audioBackendFactory,
            onQuitRequested: onQuitRequested,
          ),
        ),
      ),
    );
  }
}
