import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:love2d/love2d.dart';

const String shaderExplorerEntryAsset = 'assets/shader_explorer/main.lua';

void main() {
  runApp(const ShaderExplorerExampleApp());
}

class ShaderExplorerExampleApp extends StatelessWidget {
  const ShaderExplorerExampleApp({
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
      title: 'LOVE Shader Explorer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF060816),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8FD3FF),
          secondary: Color(0xFF7DD3FC),
          surface: Color(0xFF111827),
        ),
      ),
      home: Scaffold(
        body: SafeArea(
          child: LoveFlameHarness(
            title: 'LOVE Shader Explorer',
            entryAsset: shaderExplorerEntryAsset,
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
