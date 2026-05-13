import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:love2d/love2d.dart';

// ─── Data model ──────────────────────────────────────────────────────────────

/// Describes a single vendored LOVE demo that can be launched from the menu.
class GameEntry {
  const GameEntry({
    required this.title,
    required this.description,
    required this.entryAsset,
    required this.accentColor,
    this.automaticGc = false,
    this.imageWarmupAssetKeys,
    this.virtualPad,
  });

  final String title;
  final String description;
  final String entryAsset;
  final Color accentColor;
  final bool automaticGc;
  final Iterable<String>? imageWarmupAssetKeys;
  final LoveTouchControlsConfig? virtualPad;
}

typedef GameLauncherBuilder =
    Widget Function(BuildContext context, GameEntry entry, VoidCallback onBack);

const modernPongEntryAsset = 'assets/modern_pong/main.lua';
const loveExampleBrowserEntryAsset = 'assets/love_example_browser/main.lua';
const pocketBomberEntryAsset = 'assets/pocket_bomber/main.lua';
const shaderExplorerEntryAsset = 'assets/shader_explorer/main.lua';
const relicBreachEntryAsset = 'assets/relic_breach/main.lua';

const _relicBreachWarmupImages = <String>[
  'assets/relic_breach/art/kenney_roguelike_rpg_pack/Spritesheet/roguelikeSheet_runtime.png',
  'assets/relic_breach/art/kenney_roguelike_characters/Spritesheet/roguelikeChar_runtime.png',
  'assets/relic_breach/art/kenney_input_prompts_pixel/Tiles/tile_0294.png',
  'assets/relic_breach/art/kenney_input_prompts_pixel/Tiles/tile_0612.png',
  'assets/relic_breach/art/kenney_input_prompts_pixel/Tiles/tile_0620.png',
  'assets/relic_breach/art/kenney_light_masks/Default/circle_a_streaks_runtime.png',
  'assets/relic_breach/art/kenney_light_masks/Default/cone_a_blur_runtime.png',
  'assets/relic_breach/art/kenney_light_masks/Default/water_caustics_a_runtime.png',
];

const _modernPongVirtualPad = LoveTouchControlsConfig(
  leftJoystick: LoveTouchJoystickConfig(
    side: LoveTouchControlSide.left,
    directions: LoveTouchDirectionBindings(
      up: LoveTouchKeyBinding(label: 'Up', key: 'w'),
      down: LoveTouchKeyBinding(label: 'Down', key: 's'),
    ),
  ),
  buttons: <LoveTouchButtonConfig>[
    LoveTouchButtonConfig(
      binding: LoveTouchKeyBinding(label: 'Pause', key: 'escape'),
      alignment: Alignment.topRight,
      margin: EdgeInsets.only(top: 28, right: 12),
      visual: LoveTouchButtonVisual.utility,
      fillColor: Color(0xCC1E3A8A),
      glowColor: Color(0x332563EB),
      borderColor: Color(0xFF93C5FD),
    ),
  ],
  hint: 'Tap Play, then use the pad for the paddle.',
);

const _browserVirtualPad = LoveTouchControlsConfig(
  buttons: <LoveTouchButtonConfig>[
    LoveTouchButtonConfig(
      binding: LoveTouchKeyBinding(label: 'Esc', key: 'escape'),
      alignment: Alignment.bottomRight,
      margin: EdgeInsets.only(right: 12, bottom: 12),
      visual: LoveTouchButtonVisual.action,
      fillColor: Color(0xCC2563EB),
      glowColor: Color(0x332563EB),
      borderColor: Color(0xFF93C5FD),
    ),
  ],
  hint: 'Touch the list directly. Esc returns from a sample.',
);

const _shaderExplorerVirtualPad = LoveTouchControlsConfig(
  leftJoystick: LoveTouchJoystickConfig(
    side: LoveTouchControlSide.left,
    directions: LoveTouchDirectionBindings(
      up: LoveTouchKeyBinding(label: 'Up', key: 'up'),
      down: LoveTouchKeyBinding(label: 'Down', key: 'down'),
      left: LoveTouchKeyBinding(label: 'Left', key: 'left'),
      right: LoveTouchKeyBinding(label: 'Right', key: 'right'),
    ),
  ),
  buttons: <LoveTouchButtonConfig>[
    LoveTouchButtonConfig(
      binding: LoveTouchKeyBinding(label: 'Restart', key: 'r'),
      alignment: Alignment.centerRight,
      margin: EdgeInsets.only(right: 10, bottom: 120),
      visual: LoveTouchButtonVisual.capsule,
      fillColor: Color(0xCC1F3B08),
      glowColor: Color(0x223B82F6),
      borderColor: Color(0xFF334155),
    ),
    LoveTouchButtonConfig(
      binding: LoveTouchKeyBinding(label: 'Pause', key: 'space'),
      alignment: Alignment.bottomRight,
      margin: EdgeInsets.only(right: 138, bottom: 12),
      visual: LoveTouchButtonVisual.action,
      fillColor: Color(0xCC1F3B08),
      glowColor: Color(0x223B82F6),
      borderColor: Color(0xFF334155),
    ),
    LoveTouchButtonConfig(
      binding: LoveTouchKeyBinding(label: 'List', key: 'tab'),
      alignment: Alignment.bottomRight,
      margin: EdgeInsets.only(right: 0, bottom: 12),
      visual: LoveTouchButtonVisual.action,
      fillColor: Color(0xCC1F3B08),
      glowColor: Color(0x223B82F6),
      borderColor: Color(0xFF334155),
    ),
  ],
  hint: 'Left and right change shaders. Up and down adjust control.',
);

const _relicBreachVirtualPad = LoveTouchControlsConfig(
  leftJoystick: LoveTouchJoystickConfig(
    side: LoveTouchControlSide.left,
    directions: LoveTouchDirectionBindings(
      up: LoveTouchKeyBinding(label: 'Up', key: 'up'),
      down: LoveTouchKeyBinding(label: 'Down', key: 'down'),
      left: LoveTouchKeyBinding(label: 'Left', key: 'left'),
      right: LoveTouchKeyBinding(label: 'Right', key: 'right'),
    ),
  ),
  buttons: <LoveTouchButtonConfig>[
    LoveTouchButtonConfig(
      binding: LoveTouchKeyBinding(label: 'Bomb', key: 'space'),
      alignment: Alignment.bottomRight,
      margin: EdgeInsets.only(right: 138, bottom: 12),
      visual: LoveTouchButtonVisual.bomb,
      fillColor: Color(0xCC1F3B08),
      glowColor: Color(0x33F43F5E),
      borderColor: Color(0xFFF43F5E),
    ),
    LoveTouchButtonConfig(
      binding: LoveTouchKeyBinding(label: 'Use', key: 'e'),
      alignment: Alignment.bottomRight,
      margin: EdgeInsets.only(right: 0, bottom: 12),
      visual: LoveTouchButtonVisual.action,
      fillColor: Color(0xCC1F3B08),
      glowColor: Color(0x2210B981),
      borderColor: Color(0xFF93C5FD),
    ),
  ],
  hint: 'Move with the pad. Tap the scene to aim or place a bomb.',
);

/// All demos shown in the game-center grid.
const kDemoEntries = <GameEntry>[
  GameEntry(
    title: 'Modern Pong',
    description: 'Retro neon paddle action.',
    entryAsset: modernPongEntryAsset,
    accentColor: Color(0xFF3B82F6),
    virtualPad: _modernPongVirtualPad,
  ),
  GameEntry(
    title: 'LOVE Example Browser',
    description: 'Browse the upstream LOVE samples.',
    entryAsset: loveExampleBrowserEntryAsset,
    accentColor: Color(0xFF14B8A6),
    virtualPad: _browserVirtualPad,
  ),
  GameEntry(
    title: 'Pocket Bomber',
    description: 'Bomberman-style arena blaster.',
    entryAsset: pocketBomberEntryAsset,
    accentColor: Color(0xFFF59E0B),
  ),
  GameEntry(
    title: 'Shader Explorer',
    description: 'GPU shader showcase.',
    entryAsset: shaderExplorerEntryAsset,
    accentColor: Color(0xFF8B5CF6),
    virtualPad: _shaderExplorerVirtualPad,
  ),
  GameEntry(
    title: 'Relic Breach',
    description: 'Roguelike dungeon crawler.',
    entryAsset: relicBreachEntryAsset,
    accentColor: Color(0xFF10B981),
    automaticGc: true,
    imageWarmupAssetKeys: _relicBreachWarmupImages,
    virtualPad: _relicBreachVirtualPad,
  ),
];

// ─── Background ────────────────────────────────────────────────────────────────

class _GameCenterBackground extends StatelessWidget {
  const _GameCenterBackground();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF060816),
      child: CustomPaint(
        painter: const _GameCenterBackgroundPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GameCenterBackgroundPainter extends CustomPainter {
  const _GameCenterBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42);
    final paint = Paint();
    for (var index = 0; index < 180; index++) {
      final opacity = rng.nextDouble() * 0.55 + 0.15;
      paint.color = const Color(0xFFFFFFFF).withAlpha((opacity * 255).round());
      canvas.drawCircle(
        Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
        rng.nextDouble() * 1.4 + 0.4,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Menu layout ──────────────────────────────────────────────────────────────

class _GameCenterMenu extends StatelessWidget {
  const _GameCenterMenu({required this.onLaunch});

  final ValueChanged<GameEntry> onLaunch;

  int _columnCountForWidth(double width) {
    if (width >= 1180) {
      return 3;
    }
    if (width >= 720) {
      return 2;
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final horizontalPadding = width < 420 ? 12.0 : 16.0;
          final verticalPadding = width < 420 ? 20.0 : 24.0;
          final gap = width < 420 ? 10.0 : 14.0;
          final contentWidth = math.max(
            0.0,
            math.min(width - horizontalPadding * 2, 1380.0),
          );
          final columns = _columnCountForWidth(contentWidth);
          final cardWidth = columns <= 1
              ? contentWidth
              : (contentWidth - gap * (columns - 1)) / columns;

          return Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                verticalPadding,
                horizontalPadding,
                28,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'LOVE Game Center',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: width < 420 ? 18 : 22,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Select a demo to play',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 13,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final entry in kDemoEntries)
                          SizedBox(
                            width: cardWidth,
                            child: _GameCenterMenuCard(
                              entry: entry,
                              onTap: () => onLaunch(entry),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GameCenterMenuCard extends StatelessWidget {
  const _GameCenterMenuCard({required this.entry, required this.onTap});

  final GameEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE0111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E3A5F)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ColoredBox(
                  color: entry.accentColor,
                  child: const SizedBox(height: 4),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 102),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          entry.description,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12.5,
                            height: 1.45,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'TAP TO PLAY',
                          style: TextStyle(
                            color: entry.accentColor.withAlpha(230),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Game launcher overlay ───────────────────────────────────────────────────

class _GameLauncherWidget extends StatefulWidget {
  const _GameLauncherWidget({required this.entry, required this.onBack});

  final GameEntry entry;
  final VoidCallback onBack;

  @override
  State<_GameLauncherWidget> createState() => _GameLauncherWidgetState();
}

class _GameLauncherWidgetState extends State<_GameLauncherWidget> {
  LoveFlameInputAdapter? _input;

  void _scheduleAfterBuild(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      action();
    });
  }

  bool _shouldShowVirtualPad(BuildContext context) {
    return MediaQuery.sizeOf(context).shortestSide < 900;
  }

  void _handleInputAdaptersReady(
    LoveFlameInputAdapter input,
    LoveJoystickInputAdapter joystickInput,
  ) {
    if (!mounted) {
      return;
    }
    _input = input;
    _scheduleAfterBuild(() => setState(() {}));
  }

  void _releaseVirtualControls() {
    _input?.resetVirtualKeyboardState();
  }

  void _handleBack() {
    _releaseVirtualControls();
    _scheduleAfterBuild(widget.onBack);
  }

  @override
  void dispose() {
    _releaseVirtualControls();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final virtualPad = widget.entry.virtualPad;
    final showVirtualPad = virtualPad != null && _shouldShowVirtualPad(context);

    return Stack(
      children: [
        LoveFlameHarness(
          entryAsset: widget.entry.entryAsset,
          automaticGc: widget.entry.automaticGc,
          imageWarmupAssetKeys: widget.entry.imageWarmupAssetKeys,
          engineMode: kIsWeb ? EngineMode.ast : EngineMode.luaBytecode,
          onInputAdaptersReady: _handleInputAdaptersReady,
          onQuitRequested: () async => _handleBack(),
        ),
        if (showVirtualPad)
          LoveTouchControlsOverlay(config: virtualPad, input: _input),
        Positioned(
          top: 8,
          left: 8,
          child: SafeArea(
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
              onPressed: _handleBack,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class GameCenterScreen extends StatefulWidget {
  const GameCenterScreen({super.key, this.launcherBuilder});

  final GameLauncherBuilder? launcherBuilder;

  @override
  State<GameCenterScreen> createState() => _GameCenterScreenState();
}

class _GameCenterScreenState extends State<GameCenterScreen> {
  GameEntry? _activeEntry;

  void _scheduleAfterBuild(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      action();
    });
  }

  void _launch(GameEntry entry) {
    _scheduleAfterBuild(() {
      setState(() {
        _activeEntry = entry;
      });
    });
  }

  void _returnToMenu() {
    _scheduleAfterBuild(() {
      setState(() {
        _activeEntry = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeEntry;
    if (active != null) {
      final launcherBuilder = widget.launcherBuilder;
      if (launcherBuilder != null) {
        return launcherBuilder(context, active, _returnToMenu);
      }
      return _GameLauncherWidget(entry: active, onBack: _returnToMenu);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        const _GameCenterBackground(),
        _GameCenterMenu(onLaunch: _launch),
      ],
    );
  }
}

// ─── App root ─────────────────────────────────────────────────────────────────

class GameCenterApp extends StatelessWidget {
  const GameCenterApp({super.key, this.launcherBuilder});

  final GameLauncherBuilder? launcherBuilder;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LOVE Game Center',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF060816),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          secondary: Color(0xFFF59E0B),
          surface: Color(0xFF111827),
        ),
      ),
      home: GameCenterScreen(launcherBuilder: launcherBuilder),
    );
  }
}
