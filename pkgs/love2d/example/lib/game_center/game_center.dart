import 'dart:math' as math;
import 'package:flame/components.dart';
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
    this.virtualPad,
  });

  final String title;
  final String description;
  final String entryAsset;
  final Color accentColor;
  final bool automaticGc;
  final Iterable<String>? imageWarmupAssetKeys;
  final VirtualPadConfig? virtualPad;
}

class VirtualPadKeyBinding {
  const VirtualPadKeyBinding({
    required this.label,
    required this.key,
    this.scancode,
  });

  final String label;
  final String key;
  final String? scancode;
}

class VirtualPadDirectionalBindings {
  const VirtualPadDirectionalBindings({
    this.up,
    this.down,
    this.left,
    this.right,
  });

  final VirtualPadKeyBinding? up;
  final VirtualPadKeyBinding? down;
  final VirtualPadKeyBinding? left;
  final VirtualPadKeyBinding? right;
}

class VirtualPadSideConfig {
  const VirtualPadSideConfig({
    this.directions,
    this.primaryButtons = const <VirtualPadKeyBinding>[],
    this.secondaryButtons = const <VirtualPadKeyBinding>[],
  });

  final VirtualPadDirectionalBindings? directions;
  final List<VirtualPadKeyBinding> primaryButtons;
  final List<VirtualPadKeyBinding> secondaryButtons;

  bool get hasContent =>
      directions != null ||
      primaryButtons.isNotEmpty ||
      secondaryButtons.isNotEmpty;
}

class VirtualPadConfig {
  const VirtualPadConfig({
    this.left = const VirtualPadSideConfig(),
    this.right = const VirtualPadSideConfig(),
    this.hint,
  });

  final VirtualPadSideConfig left;
  final VirtualPadSideConfig right;
  final String? hint;
}

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

const _modernPongVirtualPad = VirtualPadConfig(
  left: VirtualPadSideConfig(
    directions: VirtualPadDirectionalBindings(
      up: VirtualPadKeyBinding(label: 'Up', key: 'w'),
      down: VirtualPadKeyBinding(label: 'Down', key: 's'),
    ),
  ),
  right: VirtualPadSideConfig(
    primaryButtons: <VirtualPadKeyBinding>[
      VirtualPadKeyBinding(label: 'Pause', key: 'escape'),
    ],
  ),
  hint: 'Tap Play, then use the pad for the paddle.',
);

const _browserVirtualPad = VirtualPadConfig(
  right: VirtualPadSideConfig(
    primaryButtons: <VirtualPadKeyBinding>[
      VirtualPadKeyBinding(label: 'Esc', key: 'escape'),
    ],
  ),
  hint: 'Touch the list directly. Esc returns from a sample.',
);

const _shaderExplorerVirtualPad = VirtualPadConfig(
  left: VirtualPadSideConfig(
    directions: VirtualPadDirectionalBindings(
      up: VirtualPadKeyBinding(label: 'Up', key: 'up'),
      down: VirtualPadKeyBinding(label: 'Down', key: 'down'),
      left: VirtualPadKeyBinding(label: 'Left', key: 'left'),
      right: VirtualPadKeyBinding(label: 'Right', key: 'right'),
    ),
  ),
  right: VirtualPadSideConfig(
    primaryButtons: <VirtualPadKeyBinding>[
      VirtualPadKeyBinding(label: 'Pause', key: 'space'),
      VirtualPadKeyBinding(label: 'List', key: 'tab'),
    ],
    secondaryButtons: <VirtualPadKeyBinding>[
      VirtualPadKeyBinding(label: 'Restart', key: 'r'),
    ],
  ),
  hint: 'Left and right change shaders. Up and down adjust control.',
);

const _relicBreachVirtualPad = VirtualPadConfig(
  left: VirtualPadSideConfig(
    directions: VirtualPadDirectionalBindings(
      up: VirtualPadKeyBinding(label: 'Up', key: 'up'),
      down: VirtualPadKeyBinding(label: 'Down', key: 'down'),
      left: VirtualPadKeyBinding(label: 'Left', key: 'left'),
      right: VirtualPadKeyBinding(label: 'Right', key: 'right'),
    ),
  ),
  right: VirtualPadSideConfig(
    primaryButtons: <VirtualPadKeyBinding>[
      VirtualPadKeyBinding(label: 'Bomb', key: 'space'),
      VirtualPadKeyBinding(label: 'Use', key: 'e'),
    ],
  ),
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
        Paint()
          ..color = const Color(
            0xFFFFFFFF,
          ).withAlpha((s.opacity * 255).round()),
      );
    }
  }
}

// ─── Flame background ─────────────────────────────────────────────────────────

class GameCenterGame extends FlameGame {
  @override
  Color backgroundColor() => const Color(0xFF060816);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(_StarfieldComponent());
  }
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
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Select a demo to play',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          entry.description,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12.5,
                            height: 1.45,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'TAP TO PLAY',
                          style: TextStyle(
                            color: entry.accentColor.withAlpha(230),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
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
    setState(() {
      _input = input;
    });
  }

  void _releaseVirtualControls() {
    _input?.resetVirtualKeyboardState();
  }

  void _handleBack() {
    _releaseVirtualControls();
    widget.onBack();
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
          onInputAdaptersReady: _handleInputAdaptersReady,
          onQuitRequested: () async => _handleBack(),
        ),
        if (showVirtualPad)
          _VirtualPadOverlay(config: virtualPad, input: _input),
        Positioned(
          top: 8,
          left: 8,
          child: SafeArea(
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
              onPressed: _handleBack,
              tooltip: 'Back to Game Center',
            ),
          ),
        ),
      ],
    );
  }
}

class _VirtualPadOverlay extends StatelessWidget {
  const _VirtualPadOverlay({required this.config, required this.input});

  final VirtualPadConfig config;
  final LoveFlameInputAdapter? input;

  @override
  Widget build(BuildContext context) {
    final hint = config.hint;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Stack(
          children: [
            if (hint != null && hint.isNotEmpty)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 120),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xAA020617),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Text(
                        hint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (config.left.hasContent)
              Align(
                alignment: Alignment.bottomLeft,
                child: _VirtualPadSideContents(
                  side: config.left,
                  input: input,
                  alignEnd: false,
                ),
              ),
            if (config.right.hasContent)
              Align(
                alignment: Alignment.bottomRight,
                child: _VirtualPadSideContents(
                  side: config.right,
                  input: input,
                  alignEnd: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DirectionalPad extends StatelessWidget {
  const _DirectionalPad({required this.bindings, required this.input});

  final VirtualPadDirectionalBindings bindings;
  final LoveFlameInputAdapter? input;

  static const _gap = 10.0;
  static const _buttonSize = 68.0;

  Widget _slot({VirtualPadKeyBinding? binding, IconData? icon}) {
    if (binding == null) {
      return const SizedBox.square(dimension: _buttonSize);
    }

    return _VirtualPadButton(
      binding: binding,
      input: input,
      width: _buttonSize,
      height: _buttonSize,
      child: Icon(icon, color: Colors.white70, size: 34),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(dimension: _buttonSize),
            const SizedBox(width: _gap),
            _slot(binding: bindings.up, icon: Icons.keyboard_arrow_up_rounded),
            const SizedBox(width: _gap),
            const SizedBox.square(dimension: _buttonSize),
          ],
        ),
        const SizedBox(height: _gap),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _slot(
              binding: bindings.left,
              icon: Icons.keyboard_arrow_left_rounded,
            ),
            const SizedBox(width: _gap),
            const SizedBox.square(dimension: _buttonSize),
            const SizedBox(width: _gap),
            _slot(
              binding: bindings.right,
              icon: Icons.keyboard_arrow_right_rounded,
            ),
          ],
        ),
        const SizedBox(height: _gap),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(dimension: _buttonSize),
            const SizedBox(width: _gap),
            _slot(
              binding: bindings.down,
              icon: Icons.keyboard_arrow_down_rounded,
            ),
            const SizedBox(width: _gap),
            const SizedBox.square(dimension: _buttonSize),
          ],
        ),
      ],
    );
  }
}

class _VirtualPadSideContents extends StatelessWidget {
  const _VirtualPadSideContents({
    required this.side,
    required this.input,
    required this.alignEnd,
  });

  final VirtualPadSideConfig side;
  final LoveFlameInputAdapter? input;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final crossAxisAlignment = alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final wrapAlignment = alignEnd ? WrapAlignment.end : WrapAlignment.start;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        if (side.secondaryButtons.isNotEmpty)
          _VirtualPadButtonGroup(
            bindings: side.secondaryButtons,
            input: input,
            compact: true,
            alignment: wrapAlignment,
          ),
        if (side.secondaryButtons.isNotEmpty &&
            (side.primaryButtons.isNotEmpty || side.directions != null))
          const SizedBox(height: 12),
        if (side.primaryButtons.isNotEmpty)
          _VirtualPadButtonGroup(
            bindings: side.primaryButtons,
            input: input,
            compact: false,
            alignment: wrapAlignment,
          ),
        if (side.primaryButtons.isNotEmpty && side.directions != null)
          const SizedBox(height: 12),
        if (side.directions case final directions?)
          _DirectionalPad(bindings: directions, input: input),
      ],
    );
  }
}

class _VirtualPadButtonGroup extends StatelessWidget {
  const _VirtualPadButtonGroup({
    required this.bindings,
    required this.input,
    required this.compact,
    required this.alignment,
  });

  final List<VirtualPadKeyBinding> bindings;
  final LoveFlameInputAdapter? input;
  final bool compact;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: alignment,
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final binding in bindings)
          _VirtualPadButton(
            binding: binding,
            input: input,
            width: compact ? 82 : 86,
            height: compact ? 54 : 86,
            borderRadius: compact ? null : BorderRadius.circular(999),
            child: Text(
              binding.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: compact ? FontWeight.w700 : FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }
}

class _VirtualPadButton extends StatefulWidget {
  const _VirtualPadButton({
    required this.binding,
    required this.input,
    required this.child,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  final VirtualPadKeyBinding binding;
  final LoveFlameInputAdapter? input;
  final Widget child;
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  State<_VirtualPadButton> createState() => _VirtualPadButtonState();
}

class _VirtualPadButtonState extends State<_VirtualPadButton> {
  final Set<int> _activePointers = <int>{};

  bool get _isPressed => _activePointers.isNotEmpty;

  void _setPressed(bool pressed) {
    widget.input?.setVirtualKeyDown(
      widget.binding.key,
      scancode: widget.binding.scancode,
      down: pressed,
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    final wasPressed = _isPressed;
    setState(() {
      _activePointers.add(event.pointer);
    });
    if (!wasPressed) {
      _setPressed(true);
    }
  }

  void _handlePointerRelease(int pointer) {
    if (!_activePointers.contains(pointer)) {
      return;
    }

    setState(() {
      _activePointers.remove(pointer);
    });
    if (!_isPressed) {
      _setPressed(false);
    }
  }

  @override
  void dispose() {
    if (_isPressed) {
      _setPressed(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.input != null;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: enabled ? _handlePointerDown : null,
      onPointerUp: enabled
          ? (event) => _handlePointerRelease(event.pointer)
          : null,
      onPointerCancel: enabled
          ? (event) => _handlePointerRelease(event.pointer)
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: _isPressed ? const Color(0xCC2563EB) : const Color(0x88111827),
          borderRadius: widget.borderRadius ?? BorderRadius.circular(20),
          border: Border.all(
            color: _isPressed
                ? const Color(0xFF93C5FD)
                : const Color(0xFF334155),
          ),
          boxShadow: _isPressed
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x552563EB),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: Center(child: widget.child),
      ),
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
  late final GameCenterGame _game = GameCenterGame();
  GameEntry? _activeEntry;

  void _launch(GameEntry entry) => setState(() => _activeEntry = entry);
  void _returnToMenu() => setState(() => _activeEntry = null);

  @override
  Widget build(BuildContext context) {
    final active = _activeEntry;
    if (active != null) {
      return _GameLauncherWidget(entry: active, onBack: _returnToMenu);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        GameWidget<GameCenterGame>(game: _game),
        _GameCenterMenu(onLaunch: _launch),
      ],
    );
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
      home: const Scaffold(body: GameCenterScreen()),
    );
  }
}
