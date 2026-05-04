import 'package:flutter/material.dart';

import 'love_flame_input.dart';

enum LoveTouchControlSide { left, right }

enum LoveTouchButtonVisual { action, utility, capsule, bomb }

class LoveTouchKeyBinding {
  const LoveTouchKeyBinding({
    required this.label,
    required this.key,
    this.scancode,
  });

  final String label;
  final String key;
  final String? scancode;
}

class LoveTouchDirectionBindings {
  const LoveTouchDirectionBindings({this.up, this.down, this.left, this.right});

  final LoveTouchKeyBinding? up;
  final LoveTouchKeyBinding? down;
  final LoveTouchKeyBinding? left;
  final LoveTouchKeyBinding? right;
}

class LoveTouchJoystickConfig {
  const LoveTouchJoystickConfig({
    required this.side,
    required this.directions,
    this.radius = 60,
    this.knobRadius = 25,
    this.deadzone = 0.15,
    this.zoneWidthFactor = 0.5,
  });

  final LoveTouchControlSide side;
  final LoveTouchDirectionBindings directions;
  final double radius;
  final double knobRadius;
  final double deadzone;
  final double zoneWidthFactor;
}

class LoveTouchButtonConfig {
  const LoveTouchButtonConfig({
    required this.binding,
    required this.alignment,
    this.margin = EdgeInsets.zero,
    this.visual = LoveTouchButtonVisual.action,
    this.fillColor = const Color(0xFF3B82F6),
    this.glowColor = const Color(0x553B82F6),
    this.borderColor = const Color(0xFF93C5FD),
  });

  final LoveTouchKeyBinding binding;
  final Alignment alignment;
  final EdgeInsets margin;
  final LoveTouchButtonVisual visual;
  final Color fillColor;
  final Color glowColor;
  final Color borderColor;
}

class LoveTouchControlsConfig {
  const LoveTouchControlsConfig({
    this.leftJoystick,
    this.rightJoystick,
    this.buttons = const <LoveTouchButtonConfig>[],
    this.hint,
  });

  final LoveTouchJoystickConfig? leftJoystick;
  final LoveTouchJoystickConfig? rightJoystick;
  final List<LoveTouchButtonConfig> buttons;
  final String? hint;
}

class LoveTouchControlsOverlay extends StatelessWidget {
  const LoveTouchControlsOverlay({
    super.key,
    required this.config,
    required this.input,
  });

  final LoveTouchControlsConfig config;
  final LoveFlameInputAdapter? input;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Stack(
          children: [
            if (config.leftJoystick case final joystick?)
              _FloatingJoystickZone(config: joystick, input: input),
            if (config.rightJoystick case final joystick?)
              _FloatingJoystickZone(config: joystick, input: input),
            for (final button in config.buttons)
              Align(
                alignment: button.alignment,
                child: Padding(
                  padding: button.margin,
                  child: _LoveTouchButton(config: button, input: input),
                ),
              ),
            if (config.hint case final hint? when hint.isNotEmpty)
              IgnorePointer(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 120),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xCC0F172A),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Text(
                          hint,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontSize: 12,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FloatingJoystickZone extends StatefulWidget {
  const _FloatingJoystickZone({required this.config, required this.input});

  final LoveTouchJoystickConfig config;
  final LoveFlameInputAdapter? input;

  @override
  State<_FloatingJoystickZone> createState() => _FloatingJoystickZoneState();
}

class _FloatingJoystickZoneState extends State<_FloatingJoystickZone> {
  int? _pointerId;
  Offset? _base;
  Offset? _knob;
  bool _leftDown = false;
  bool _rightDown = false;
  bool _upDown = false;
  bool _downDown = false;

  bool get _active => _pointerId != null && _base != null && _knob != null;

  void _setBinding(LoveTouchKeyBinding? binding, bool down) {
    if (binding == null) {
      return;
    }
    widget.input?.setVirtualKeyDown(
      binding.key,
      scancode: binding.scancode,
      down: down,
    );
  }

  void _updateDirectionalState(Offset normalized) {
    final deadzone = widget.config.deadzone;
    final left = normalized.dx < -deadzone;
    final right = normalized.dx > deadzone;
    final up = normalized.dy < -deadzone;
    final down = normalized.dy > deadzone;

    if (_leftDown != left) {
      _leftDown = left;
      _setBinding(widget.config.directions.left, left);
    }
    if (_rightDown != right) {
      _rightDown = right;
      _setBinding(widget.config.directions.right, right);
    }
    if (_upDown != up) {
      _upDown = up;
      _setBinding(widget.config.directions.up, up);
    }
    if (_downDown != down) {
      _downDown = down;
      _setBinding(widget.config.directions.down, down);
    }
  }

  void _releaseDirectionalState() {
    _updateDirectionalState(Offset.zero);
  }

  void _start(Offset position, int pointer) {
    setState(() {
      _pointerId = pointer;
      _base = position;
      _knob = position;
    });
    _releaseDirectionalState();
  }

  void _move(Offset position) {
    final base = _base;
    if (base == null) {
      return;
    }

    final delta = position - base;
    final distance = delta.distance;
    final maxDistance = widget.config.radius;
    final clamped = distance > maxDistance && distance > 0
        ? delta / distance * maxDistance
        : delta;
    final normalized = maxDistance > 0 ? clamped / maxDistance : Offset.zero;

    setState(() {
      _knob = base + clamped;
    });
    _updateDirectionalState(normalized);
  }

  void _stop() {
    _releaseDirectionalState();
    setState(() {
      _pointerId = null;
      _base = null;
      _knob = null;
    });
  }

  @override
  void dispose() {
    _releaseDirectionalState();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alignment = widget.config.side == LoveTouchControlSide.left
        ? Alignment.centerLeft
        : Alignment.centerRight;
    return Align(
      alignment: alignment,
      child: FractionallySizedBox(
        widthFactor: widget.config.zoneWidthFactor,
        heightFactor: 1,
        alignment: alignment,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: widget.input == null
                  ? null
                  : (event) {
                      if (_pointerId != null) {
                        return;
                      }
                      _start(event.localPosition, event.pointer);
                    },
              onPointerMove: widget.input == null
                  ? null
                  : (event) {
                      if (_pointerId != event.pointer) {
                        return;
                      }
                      _move(event.localPosition);
                    },
              onPointerUp: widget.input == null
                  ? null
                  : (event) {
                      if (_pointerId != event.pointer) {
                        return;
                      }
                      _stop();
                    },
              onPointerCancel: widget.input == null
                  ? null
                  : (event) {
                      if (_pointerId != event.pointer) {
                        return;
                      }
                      _stop();
                    },
              child: CustomPaint(
                painter: _FloatingJoystickPainter(
                  active: _active,
                  base: _base,
                  knob: _knob,
                  radius: widget.config.radius,
                  knobRadius: widget.config.knobRadius,
                ),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FloatingJoystickPainter extends CustomPainter {
  const _FloatingJoystickPainter({
    required this.active,
    required this.base,
    required this.knob,
    required this.radius,
    required this.knobRadius,
  });

  final bool active;
  final Offset? base;
  final Offset? knob;
  final double radius;
  final double knobRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (!active || base == null || knob == null) {
      return;
    }

    final baseFill = Paint()..color = const Color(0x66111827);
    final baseStroke = Paint()
      ..color = const Color(0x88CBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final knobFill = Paint()..color = const Color(0xE8F2C14E);
    final knobStroke = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(base!, radius, baseFill);
    canvas.drawCircle(base!, radius, baseStroke);
    canvas.drawCircle(knob!, knobRadius, knobFill);
    canvas.drawCircle(knob!, knobRadius, knobStroke);
  }

  @override
  bool shouldRepaint(covariant _FloatingJoystickPainter oldDelegate) {
    return active != oldDelegate.active ||
        base != oldDelegate.base ||
        knob != oldDelegate.knob ||
        radius != oldDelegate.radius ||
        knobRadius != oldDelegate.knobRadius;
  }
}

class _LoveTouchButton extends StatefulWidget {
  const _LoveTouchButton({required this.config, required this.input});

  final LoveTouchButtonConfig config;
  final LoveFlameInputAdapter? input;

  @override
  State<_LoveTouchButton> createState() => _LoveTouchButtonState();
}

class _LoveTouchButtonState extends State<_LoveTouchButton> {
  final Set<int> _activePointers = <int>{};

  bool get _pressed => _activePointers.isNotEmpty;

  void _setPressed(bool pressed) {
    final binding = widget.config.binding;
    widget.input?.setVirtualKeyDown(
      binding.key,
      scancode: binding.scancode,
      down: pressed,
    );
  }

  void _handleDown(PointerDownEvent event) {
    final wasPressed = _pressed;
    setState(() {
      _activePointers.add(event.pointer);
    });
    if (!wasPressed) {
      _setPressed(true);
    }
  }

  void _handleUp(int pointer) {
    if (!_activePointers.contains(pointer)) {
      return;
    }
    setState(() {
      _activePointers.remove(pointer);
    });
    if (!_pressed) {
      _setPressed(false);
    }
  }

  @override
  void dispose() {
    if (_pressed) {
      _setPressed(false);
    }
    super.dispose();
  }

  Size _sizeForVisual(LoveTouchButtonVisual visual) {
    return switch (visual) {
      LoveTouchButtonVisual.utility => const Size(72, 72),
      LoveTouchButtonVisual.capsule => const Size(128, 70),
      LoveTouchButtonVisual.action => const Size(132, 132),
      LoveTouchButtonVisual.bomb => const Size(148, 148),
    };
  }

  BorderRadius _borderRadiusForVisual(LoveTouchButtonVisual visual) {
    return switch (visual) {
      LoveTouchButtonVisual.utility => BorderRadius.circular(999),
      LoveTouchButtonVisual.capsule => BorderRadius.circular(28),
      LoveTouchButtonVisual.action => BorderRadius.circular(999),
      LoveTouchButtonVisual.bomb => BorderRadius.circular(999),
    };
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final size = _sizeForVisual(config.visual);
    final enabled = widget.input != null;
    final fillColor = _pressed
        ? Color.alphaBlend(const Color(0x22000000), config.fillColor)
        : config.fillColor;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: enabled ? _handleDown : null,
      onPointerUp: enabled ? (event) => _handleUp(event.pointer) : null,
      onPointerCancel: enabled ? (event) => _handleUp(event.pointer) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: fillColor.withAlpha(
            config.visual == LoveTouchButtonVisual.utility ? 140 : 180,
          ),
          borderRadius: _borderRadiusForVisual(config.visual),
          border: Border.all(
            color: config.borderColor.withAlpha(_pressed ? 255 : 120),
            width: config.visual == LoveTouchButtonVisual.bomb ? 4 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: config.glowColor,
              blurRadius: config.visual == LoveTouchButtonVisual.bomb ? 24 : 18,
              spreadRadius: config.visual == LoveTouchButtonVisual.bomb ? 8 : 0,
            ),
          ],
        ),
        child: Center(
          child: Text(
            config.binding.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: switch (config.visual) {
                LoveTouchButtonVisual.utility => 15,
                LoveTouchButtonVisual.capsule => 18,
                LoveTouchButtonVisual.action => 20,
                LoveTouchButtonVisual.bomb => 16,
              },
              fontWeight: FontWeight.w800,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
