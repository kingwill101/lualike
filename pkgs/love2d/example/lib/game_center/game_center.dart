import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
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
  });

  final String title;
  final String description;
  final String entryAsset;
  final Color accentColor;
  final bool automaticGc;
  final Iterable<String>? imageWarmupAssetKeys;
}

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

/// All demos shown in the game-center grid.
const kDemoEntries = <GameEntry>[
  GameEntry(
    title: 'Modern Pong',
    description: 'Retro neon paddle action.',
    entryAsset: 'assets/modern_pong/main.lua',
    accentColor: Color(0xFF3B82F6),
  ),
  GameEntry(
    title: 'Pocket Bomber',
    description: 'Bomberman-style arena blaster.',
    entryAsset: 'assets/pocket_bomber/main.lua',
    accentColor: Color(0xFFF59E0B),
  ),
  GameEntry(
    title: 'Shader Explorer',
    description: 'GPU shader showcase.',
    entryAsset: 'assets/shader_explorer/main.lua',
    accentColor: Color(0xFF8B5CF6),
  ),
  GameEntry(
    title: 'Relic Breach',
    description: 'Roguelike dungeon crawler.',
    entryAsset: 'assets/relic_breach/main.lua',
    accentColor: Color(0xFF10B981),
    automaticGc: true,
    imageWarmupAssetKeys: _relicBreachWarmupImages,
  ),
];

// ─── Starfield ────────────────────────────────────────────────────────────────

class _StarfieldComponent extends PositionComponent {
  _StarfieldComponent() : super(anchor: Anchor.topLeft);

  final _rng = math.Random(42);
  List<({double x, double y, double radius, double opacity})> _stars = const [];

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    size = gameSize;
    _stars = List.generate(180, (_) {
      return (
        x: _rng.nextDouble() * gameSize.x,
        y: _rng.nextDouble() * gameSize.y,
        radius: _rng.nextDouble() * 1.4 + 0.4,
        opacity: _rng.nextDouble() * 0.55 + 0.15,
      );
    });
  }

  @override
  void render(Canvas canvas) {
    for (final s in _stars) {
      canvas.drawCircle(
        Offset(s.x, s.y),
        s.radius,
        Paint()..color = const Color(0xFFFFFFFF).withAlpha((s.opacity * 255).round()),
      );
    }
  }
}

// ─── Game card ────────────────────────────────────────────────────────────────

class _GameCardComponent extends PositionComponent with TapCallbacks {
  _GameCardComponent({
    required this.entry,
    required super.position,
    required super.size,
    required this.onTap,
  });

  final GameEntry entry;
  final void Function(GameEntry) onTap;

  static const _radius = Radius.circular(10);
  static const _bgColor = Color(0xFF111827);
  static const _borderColor = Color(0xFF1E3A5F);

  static const _titleStyle = TextStyle(
    color: Colors.white,
    fontSize: 17,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.3,
  );
  static const _descStyle = TextStyle(
    color: Color(0xFF94A3B8),
    fontSize: 12.5,
    height: 1.45,
  );

  void _paintText(
    Canvas canvas,
    String text,
    TextStyle style,
    Offset offset,
    double maxWidth, {
    int maxLines = 2,
  }) {
    final paragraph = (ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textDirection: ui.TextDirection.ltr,
        maxLines: maxLines,
        ellipsis: '\u2026',
      ),
    )
          ..pushStyle(style.getTextStyle())
          ..addText(text))
        .build()
      ..layout(ui.ParagraphConstraints(width: maxWidth));
    canvas.drawParagraph(paragraph, offset);
  }

  @override
  void render(Canvas canvas) {
    final cardRect = Rect.fromLTWH(0, 0, size.x, size.y);
    final rr = RRect.fromRectAndRadius(cardRect, _radius);

    // Background
    canvas.drawRRect(rr, Paint()..color = _bgColor);

    // Border
    canvas.drawRRect(
      rr,
      Paint()
        ..color = _borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Accent bar at top
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        0,
        0,
        size.x,
        4,
        topLeft: _radius,
        topRight: _radius,
      ),
      Paint()..color = entry.accentColor,
    );

    final innerWidth = size.x - 32;

    // Title
    _paintText(canvas, entry.title, _titleStyle, const Offset(16, 20), innerWidth, maxLines: 1);

    // Description
    _paintText(canvas, entry.description, _descStyle, const Offset(16, 46), innerWidth);

    // CTA label
    final ctaStyle = TextStyle(
      color: entry.accentColor.withAlpha(230),
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.2,
    );
    _paintText(canvas, 'TAP TO PLAY', ctaStyle, Offset(16, size.y - 24), innerWidth, maxLines: 1);
  }

  @override
  bool onTapDown(TapDownEvent event) {
    onTap(entry);
    return true;
  }
}

// ─── Flame game ───────────────────────────────────────────────────────────────

class GameCenterGame extends FlameGame with TapCallbacks {
  GameCenterGame({required this.onLaunch});

  final void Function(GameEntry) onLaunch;

  @override
  Color backgroundColor() => const Color(0xFF060816);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _buildLayout();
  }

  void _buildLayout() {
    final s = size;

    add(_StarfieldComponent());

    // Title
    add(
      TextComponent(
        text: 'LOVE Game Center',
        textRenderer: TextPaint(
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.4,
          ),
        ),
        anchor: Anchor.topCenter,
        position: Vector2(s.x / 2, 22),
      ),
    );

    // Subtitle
    add(
      TextComponent(
        text: 'Select a demo to play',
        textRenderer: TextPaint(
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
        ),
        anchor: Anchor.topCenter,
        position: Vector2(s.x / 2, 58),
      ),
    );

    // Cards — 2-column grid
    const hPad = 20.0;
    const vPad = 20.0;
    const gutter = 14.0;
    const topOffset = 92.0;
    const cardHeight = 130.0;
    const cols = 2;

    final cardWidth = (s.x - hPad * 2 - gutter * (cols - 1)) / cols;

    for (var i = 0; i < kDemoEntries.length; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      add(
        _GameCardComponent(
          entry: kDemoEntries[i],
          position: Vector2(
            hPad + col * (cardWidth + gutter),
            topOffset + row * (cardHeight + vPad),
          ),
          size: Vector2(cardWidth, cardHeight),
          onTap: onLaunch,
        ),
      );
    }
  }
}

// ─── Game launcher overlay ───────────────────────────────────────────────────

class _GameLauncherWidget extends StatelessWidget {
  const _GameLauncherWidget({required this.entry, required this.onBack});

  final GameEntry entry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        LoveFlameHarness(
          entryAsset: entry.entryAsset,
          automaticGc: entry.automaticGc,
          imageWarmupAssetKeys: entry.imageWarmupAssetKeys,
          onQuitRequested: () async => onBack(),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: SafeArea(
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
              onPressed: onBack,
              tooltip: 'Back to Game Center',
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class GameCenterScreen extends StatefulWidget {
  const GameCenterScreen({super.key});

  @override
  State<GameCenterScreen> createState() => _GameCenterScreenState();
}

class _GameCenterScreenState extends State<GameCenterScreen> {
  late final GameCenterGame _game = GameCenterGame(onLaunch: _launch);
  GameEntry? _activeEntry;

  void _launch(GameEntry entry) => setState(() => _activeEntry = entry);
  void _returnToMenu() => setState(() => _activeEntry = null);

  @override
  Widget build(BuildContext context) {
    final active = _activeEntry;
    if (active != null) {
      return _GameLauncherWidget(entry: active, onBack: _returnToMenu);
    }
    return GameWidget<GameCenterGame>(game: _game);
  }
}

// ─── App root ─────────────────────────────────────────────────────────────────

class GameCenterApp extends StatelessWidget {
  const GameCenterApp({super.key});

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
      home: const Scaffold(
        body: SafeArea(child: GameCenterScreen()),
      ),
    );
  }
}
