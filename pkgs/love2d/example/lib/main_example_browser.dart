import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:love2d/love2d.dart';

const String loveExampleBrowserEntryAsset =
    'assets/love_example_browser/main.lua';

void main() {
  runApp(const LoveExampleBrowserApp());
}

class LoveExampleBrowserApp extends StatelessWidget {
  const LoveExampleBrowserApp({
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
      title: 'LOVE Example Browser',
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
      home: Scaffold(
        body: SafeArea(
          child: LoveFlameHarness(
            title: 'LOVE Example Browser',
            entryAsset: loveExampleBrowserEntryAsset,
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
