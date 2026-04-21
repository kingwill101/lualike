import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:love2d/love2d.dart';

const String testBedEntryAsset = 'assets/scripts/test_bed.lua';

void main() {
  runApp(const LoveTestBedExampleApp());
}

class LoveTestBedExampleApp extends StatelessWidget {
  const LoveTestBedExampleApp({
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
      title: 'LOVE Test Bed',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF060816),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF9AB7FF),
          secondary: Color(0xFF5EEAD4),
          surface: Color(0xFF111827),
        ),
      ),
      home: _LoveTestBedShell(
        bundle: bundle ?? rootBundle,
        filesystemAdapter: filesystemAdapter,
        audioBackendFactory: audioBackendFactory,
        onQuitRequested: onQuitRequested,
      ),
    );
  }
}

class _LoveTestBedShell extends StatefulWidget {
  const _LoveTestBedShell({
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
  State<_LoveTestBedShell> createState() => _LoveTestBedShellState();
}

class _LoveTestBedShellState extends State<_LoveTestBedShell> {
  late Future<String> _sourceCodeFuture;
  int _reloadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _sourceCodeFuture = _loadSourceCode();
  }

  Future<String> _loadSourceCode() async {
    final source = await widget.bundle.loadString(testBedEntryAsset);
    final lines = const LineSplitter().convert(source);
    final numberWidth = lines.length.toString().length;
    return [
      for (var index = 0; index < lines.length; index++)
        '${(index + 1).toString().padLeft(numberWidth)}  ${lines[index]}',
    ].join('\n');
  }

  void _reloadScript() {
    setState(() {
      _reloadGeneration += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeaderBar(onReload: _reloadScript),
              const SizedBox(height: 16),
              Expanded(
                child: _AdaptiveWorkspace(
                  viewport: _PanelFrame(
                    title: 'Live View',
                    subtitle:
                        'Runs the bundled Lua script through the LOVE compatibility harness.',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: LoveFlameHarness(
                        key: ValueKey<int>(_reloadGeneration),
                        entryAsset: testBedEntryAsset,
                        bundle: widget.bundle,
                        filesystemAdapter: widget.filesystemAdapter,
                        audioBackendFactory: widget.audioBackendFactory,
                        onQuitRequested: widget.onQuitRequested,
                      ),
                    ),
                  ),
                  source: _PanelFrame(
                    title: 'Lua Source',
                    subtitle: testBedEntryAsset,
                    child: _SourceViewer(sourceCodeFuture: _sourceCodeFuture),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.onReload});

  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF121826), Color(0xFF0B1120)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF243046)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'LOVE Test Bed',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Adaptive Flutter example for the bundled LuaLike LOVE runtime.',
                    style: TextStyle(
                      color: Color(0xFF9AA6BD),
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              key: const Key('reload-script'),
              onPressed: onReload,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reload Script'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF9AB7FF),
                foregroundColor: const Color(0xFF08111F),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdaptiveWorkspace extends StatelessWidget {
  const _AdaptiveWorkspace({required this.viewport, required this.source});

  final Widget viewport;
  final Widget source;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1180) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 8, child: viewport),
              const SizedBox(width: 16),
              Expanded(flex: 5, child: source),
            ],
          );
        }

        return DefaultTabController(
          length: 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF0D1321),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFF1F2937)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                  child: TabBar(
                    indicator: BoxDecoration(
                      color: const Color(0xFF172133),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    dividerColor: Colors.transparent,
                    labelColor: const Color(0xFFF8FAFC),
                    unselectedLabelColor: const Color(0xFF94A3B8),
                    tabs: const [
                      Tab(
                        key: Key('viewport-tab'),
                        icon: Icon(Icons.play_circle_outline_rounded),
                        text: 'Viewport',
                      ),
                      Tab(
                        key: Key('lua-source-tab'),
                        icon: Icon(Icons.code_rounded),
                        text: 'Lua Source',
                      ),
                    ],
                  ),
                ),
                Expanded(child: TabBarView(children: [viewport, source])),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PanelFrame extends StatelessWidget {
  const _PanelFrame({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1321),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _SourceViewer extends StatefulWidget {
  const _SourceViewer({required this.sourceCodeFuture});

  final Future<String> sourceCodeFuture;

  @override
  State<_SourceViewer> createState() => _SourceViewerState();
}

class _SourceViewerState extends State<_SourceViewer> {
  late final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF07101D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1D2A3F)),
      ),
      child: FutureBuilder<String>(
        future: widget.sourceCodeFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData && snapshot.error == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  '${snapshot.error}',
                  style: const TextStyle(color: Color(0xFFFCA5A5)),
                ),
              ),
            );
          }

          return Scrollbar(
            thumbVisibility: true,
            controller: _scrollController,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(18),
              child: SelectionArea(
                child: Text(
                  snapshot.data!,
                  key: const Key('lua-source-view'),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13.5,
                    height: 1.5,
                    color: Color(0xFFD8E2F0),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
