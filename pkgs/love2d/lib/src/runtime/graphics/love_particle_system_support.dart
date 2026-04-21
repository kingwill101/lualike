part of '../love_runtime.dart';

enum LoveParticleInsertMode { top, bottom, random }

enum LoveParticleAreaSpreadDistribution {
  uniform,
  normal,
  ellipse,
  borderEllipse,
  borderRectangle,
  none,
}

class LoveParticleDrawEntry {
  LoveParticleDrawEntry({
    required Matrix4 transform,
    required this.color,
    LoveQuad? quad,
  }) : transform = Matrix4.copy(transform),
       quad = quad?.copy();

  final Matrix4 transform;
  final LoveColor color;
  final LoveQuad? quad;

  LoveParticleDrawEntry copy() {
    return LoveParticleDrawEntry(
      transform: transform,
      color: color,
      quad: quad,
    );
  }
}

class LoveParticleSystemSnapshot {
  LoveParticleSystemSnapshot({
    required this.texture,
    required Iterable<LoveParticleDrawEntry> particles,
  }) : particles = List<LoveParticleDrawEntry>.unmodifiable(
         particles.map((particle) => particle.copy()),
       );

  final LoveImage texture;
  final List<LoveParticleDrawEntry> particles;

  LoveParticleSystemSnapshot copy() {
    return LoveParticleSystemSnapshot(texture: texture, particles: particles);
  }
}

class _LoveParticle {
  _LoveParticle({
    required this.originX,
    required this.originY,
    required this.x,
    required this.y,
    required this.velocityX,
    required this.velocityY,
    required this.linearAccelerationX,
    required this.linearAccelerationY,
    required this.radialAcceleration,
    required this.tangentialAcceleration,
    required this.linearDamping,
    required this.rotation,
    required this.spin,
    required this.sizeScale,
    required this.lifetime,
  });

  final double originX;
  final double originY;
  double x;
  double y;
  double velocityX;
  double velocityY;
  final double linearAccelerationX;
  final double linearAccelerationY;
  final double radialAcceleration;
  final double tangentialAcceleration;
  final double linearDamping;
  double rotation;
  final double spin;
  final double sizeScale;
  double age = 0.0;
  final double lifetime;

  double get progress {
    if (lifetime <= 0) {
      return 1.0;
    }

    return (age / lifetime).clamp(0.0, 1.0);
  }
}

class LoveParticleSystem {
  LoveParticleSystem({required LoveImage texture, int bufferSize = 1000})
    : _texture = texture,
      _bufferSize = math.max(1, bufferSize);

  LoveParticleSystem._clone({
    required LoveImage texture,
    required int bufferSize,
    required LoveParticleInsertMode insertMode,
    required double emissionRate,
    required double emitterLifetime,
    required double particleLifetimeMin,
    required double particleLifetimeMax,
    required double positionX,
    required double positionY,
    required LoveParticleAreaSpreadDistribution emissionAreaDistribution,
    required double emissionAreaDx,
    required double emissionAreaDy,
    required double emissionAreaAngle,
    required bool emissionAreaDirectionRelativeToCenter,
    required double direction,
    required double spread,
    required double speedMin,
    required double speedMax,
    required double linearAccelerationMinX,
    required double linearAccelerationMinY,
    required double linearAccelerationMaxX,
    required double linearAccelerationMaxY,
    required double radialAccelerationMin,
    required double radialAccelerationMax,
    required double tangentialAccelerationMin,
    required double tangentialAccelerationMax,
    required double linearDampingMin,
    required double linearDampingMax,
    required List<double> sizes,
    required double sizeVariation,
    required double rotationMin,
    required double rotationMax,
    required double spinMin,
    required double spinMax,
    required double spinVariation,
    required double offsetX,
    required double offsetY,
    required bool hasCustomOffset,
    required List<LoveColor> colors,
    required List<LoveQuad> quads,
    required bool relativeRotation,
  }) : _texture = texture,
       _bufferSize = bufferSize,
       _insertMode = insertMode,
       _emissionRate = emissionRate,
       _emitterLifetime = emitterLifetime,
       _particleLifetimeMin = particleLifetimeMin,
       _particleLifetimeMax = particleLifetimeMax,
       _positionX = positionX,
       _positionY = positionY,
       _previousPositionX = positionX,
       _previousPositionY = positionY,
       _emissionAreaDistribution = emissionAreaDistribution,
       _emissionAreaDx = emissionAreaDx,
       _emissionAreaDy = emissionAreaDy,
       _emissionAreaAngle = emissionAreaAngle,
       _emissionAreaDirectionRelativeToCenter =
           emissionAreaDirectionRelativeToCenter,
       _direction = direction,
       _spread = spread,
       _speedMin = speedMin,
       _speedMax = speedMax,
       _linearAccelerationMinX = linearAccelerationMinX,
       _linearAccelerationMinY = linearAccelerationMinY,
       _linearAccelerationMaxX = linearAccelerationMaxX,
       _linearAccelerationMaxY = linearAccelerationMaxY,
       _radialAccelerationMin = radialAccelerationMin,
       _radialAccelerationMax = radialAccelerationMax,
       _tangentialAccelerationMin = tangentialAccelerationMin,
       _tangentialAccelerationMax = tangentialAccelerationMax,
       _linearDampingMin = linearDampingMin,
       _linearDampingMax = linearDampingMax,
       _sizes = List<double>.unmodifiable(sizes),
       _sizeVariation = sizeVariation,
       _rotationMin = rotationMin,
       _rotationMax = rotationMax,
       _spinMin = spinMin,
       _spinMax = spinMax,
       _spinVariation = spinVariation,
       _offsetX = offsetX,
       _offsetY = offsetY,
       _hasCustomOffset = hasCustomOffset,
       _colors = List<LoveColor>.unmodifiable(colors),
       _quads = List<LoveQuad>.unmodifiable(quads.map((quad) => quad.copy())),
       _relativeRotation = relativeRotation {
    _active = false;
    _paused = false;
    _stopped = true;
  }

  LoveImage _texture;
  int _bufferSize;
  LoveParticleInsertMode _insertMode = LoveParticleInsertMode.top;
  double _emissionRate = 0.0;
  double _emitterLifetime = -1.0;
  double _particleLifetimeMin = 0.0;
  double _particleLifetimeMax = 0.0;
  double _positionX = 0.0;
  double _positionY = 0.0;
  double _previousPositionX = 0.0;
  double _previousPositionY = 0.0;
  LoveParticleAreaSpreadDistribution _emissionAreaDistribution =
      LoveParticleAreaSpreadDistribution.none;
  double _emissionAreaDx = 0.0;
  double _emissionAreaDy = 0.0;
  double _emissionAreaAngle = 0.0;
  bool _emissionAreaDirectionRelativeToCenter = false;
  double _direction = 0.0;
  double _spread = 0.0;
  double _speedMin = 0.0;
  double _speedMax = 0.0;
  double _linearAccelerationMinX = 0.0;
  double _linearAccelerationMinY = 0.0;
  double _linearAccelerationMaxX = 0.0;
  double _linearAccelerationMaxY = 0.0;
  double _radialAccelerationMin = 0.0;
  double _radialAccelerationMax = 0.0;
  double _tangentialAccelerationMin = 0.0;
  double _tangentialAccelerationMax = 0.0;
  double _linearDampingMin = 0.0;
  double _linearDampingMax = 0.0;
  List<double> _sizes = const <double>[1.0];
  double _sizeVariation = 0.0;
  double _rotationMin = 0.0;
  double _rotationMax = 0.0;
  double _spinMin = 0.0;
  double _spinMax = 0.0;
  double _spinVariation = 0.0;
  double _offsetX = 0.0;
  double _offsetY = 0.0;
  bool _hasCustomOffset = false;
  List<LoveColor> _colors = const <LoveColor>[LoveColor.white];
  List<LoveQuad> _quads = const <LoveQuad>[];
  bool _relativeRotation = false;
  bool _active = true;
  bool _paused = false;
  bool _stopped = false;
  double _emitterAge = 0.0;
  double _emissionCarry = 0.0;
  final List<_LoveParticle> _particles = <_LoveParticle>[];

  LoveImage get texture => _texture;

  int get bufferSize => _bufferSize;

  LoveParticleInsertMode get insertMode => _insertMode;

  double get emissionRate => _emissionRate;

  double get emitterLifetime => _emitterLifetime;

  ({double min, double max}) get particleLifetime =>
      (min: _particleLifetimeMin, max: _particleLifetimeMax);

  ({double x, double y}) get position => (x: _positionX, y: _positionY);

  ({
    LoveParticleAreaSpreadDistribution distribution,
    double dx,
    double dy,
    double angle,
    bool directionRelativeToCenter,
  })
  get emissionArea => (
    distribution: _emissionAreaDistribution,
    dx: _emissionAreaDx,
    dy: _emissionAreaDy,
    angle: _emissionAreaAngle,
    directionRelativeToCenter: _emissionAreaDirectionRelativeToCenter,
  );

  double get direction => _direction;

  double get spread => _spread;

  ({double min, double max}) get speed => (min: _speedMin, max: _speedMax);

  ({double minX, double minY, double maxX, double maxY})
  get linearAcceleration => (
    minX: _linearAccelerationMinX,
    minY: _linearAccelerationMinY,
    maxX: _linearAccelerationMaxX,
    maxY: _linearAccelerationMaxY,
  );

  ({double min, double max}) get radialAcceleration =>
      (min: _radialAccelerationMin, max: _radialAccelerationMax);

  ({double min, double max}) get tangentialAcceleration =>
      (min: _tangentialAccelerationMin, max: _tangentialAccelerationMax);

  ({double min, double max}) get linearDamping =>
      (min: _linearDampingMin, max: _linearDampingMax);

  List<double> get sizes => List<double>.unmodifiable(_sizes);

  double get sizeVariation => _sizeVariation;

  ({double min, double max}) get rotation =>
      (min: _rotationMin, max: _rotationMax);

  ({double min, double max}) get spin => (min: _spinMin, max: _spinMax);

  double get spinVariation => _spinVariation;

  ({double x, double y}) get offset => (x: _offsetX, y: _offsetY);

  List<LoveColor> get colors => List<LoveColor>.unmodifiable(_colors);

  List<LoveQuad> get quads =>
      List<LoveQuad>.unmodifiable(_quads.map((quad) => quad.copy()));

  bool get relativeRotation => _relativeRotation;

  bool get isActive => _active;

  bool get isPaused => _paused;

  bool get isStopped => _stopped;

  int get count => _particles.length;

  LoveParticleSystem clone() {
    return LoveParticleSystem._clone(
      texture: _texture,
      bufferSize: _bufferSize,
      insertMode: _insertMode,
      emissionRate: _emissionRate,
      emitterLifetime: _emitterLifetime,
      particleLifetimeMin: _particleLifetimeMin,
      particleLifetimeMax: _particleLifetimeMax,
      positionX: _positionX,
      positionY: _positionY,
      emissionAreaDistribution: _emissionAreaDistribution,
      emissionAreaDx: _emissionAreaDx,
      emissionAreaDy: _emissionAreaDy,
      emissionAreaAngle: _emissionAreaAngle,
      emissionAreaDirectionRelativeToCenter:
          _emissionAreaDirectionRelativeToCenter,
      direction: _direction,
      spread: _spread,
      speedMin: _speedMin,
      speedMax: _speedMax,
      linearAccelerationMinX: _linearAccelerationMinX,
      linearAccelerationMinY: _linearAccelerationMinY,
      linearAccelerationMaxX: _linearAccelerationMaxX,
      linearAccelerationMaxY: _linearAccelerationMaxY,
      radialAccelerationMin: _radialAccelerationMin,
      radialAccelerationMax: _radialAccelerationMax,
      tangentialAccelerationMin: _tangentialAccelerationMin,
      tangentialAccelerationMax: _tangentialAccelerationMax,
      linearDampingMin: _linearDampingMin,
      linearDampingMax: _linearDampingMax,
      sizes: _sizes,
      sizeVariation: _sizeVariation,
      rotationMin: _rotationMin,
      rotationMax: _rotationMax,
      spinMin: _spinMin,
      spinMax: _spinMax,
      spinVariation: _spinVariation,
      offsetX: _offsetX,
      offsetY: _offsetY,
      hasCustomOffset: _hasCustomOffset,
      colors: _colors,
      quads: _quads,
      relativeRotation: _relativeRotation,
    );
  }

  void setTexture(LoveImage texture) {
    _texture = texture;
  }

  void setBufferSize(int bufferSize) {
    _bufferSize = math.max(1, bufferSize);
    if (_particles.length <= _bufferSize) {
      return;
    }

    _particles.removeRange(_bufferSize, _particles.length);
  }

  void setInsertMode(LoveParticleInsertMode mode) {
    _insertMode = mode;
  }

  void setEmissionRate(double value) {
    _emissionRate = value;
  }

  void setEmitterLifetime(double value) {
    _emitterLifetime = value;
  }

  void setParticleLifetime(double min, [double? max]) {
    _particleLifetimeMin = min;
    _particleLifetimeMax = max ?? min;
  }

  void setPosition(double x, double y) {
    _positionX = x;
    _positionY = y;
    _previousPositionX = x;
    _previousPositionY = y;
  }

  void moveTo(double x, double y) {
    _positionX = x;
    _positionY = y;
  }

  void setEmissionArea(
    LoveParticleAreaSpreadDistribution distribution,
    double dx,
    double dy, [
    double angle = 0.0,
    bool directionRelativeToCenter = false,
  ]) {
    _emissionAreaDistribution = distribution;
    _emissionAreaDx = dx;
    _emissionAreaDy = dy;
    _emissionAreaAngle = angle;
    _emissionAreaDirectionRelativeToCenter = directionRelativeToCenter;
  }

  void setDirection(double value) {
    _direction = value;
  }

  void setSpread(double value) {
    _spread = value;
  }

  void setSpeed(double min, [double? max]) {
    _speedMin = min;
    _speedMax = max ?? min;
  }

  void setLinearAcceleration(
    double minX,
    double minY, [
    double? maxX,
    double? maxY,
  ]) {
    _linearAccelerationMinX = minX;
    _linearAccelerationMinY = minY;
    _linearAccelerationMaxX = maxX ?? minX;
    _linearAccelerationMaxY = maxY ?? minY;
  }

  void setRadialAcceleration(double min, [double? max]) {
    _radialAccelerationMin = min;
    _radialAccelerationMax = max ?? min;
  }

  void setTangentialAcceleration(double min, [double? max]) {
    _tangentialAccelerationMin = min;
    _tangentialAccelerationMax = max ?? min;
  }

  void setLinearDamping(double min, [double? max]) {
    _linearDampingMin = min;
    _linearDampingMax = max ?? min;
  }

  void setSizes(List<double> sizes) {
    _sizes = List<double>.unmodifiable(sizes);
  }

  void setSizeVariation(double value) {
    _sizeVariation = value;
  }

  void setRotation(double min, [double? max]) {
    _rotationMin = min;
    _rotationMax = max ?? min;
  }

  void setSpin(double min, [double? max]) {
    _spinMin = min;
    _spinMax = max ?? min;
  }

  void setSpinVariation(double value) {
    _spinVariation = value;
  }

  void setOffset(double x, double y) {
    _offsetX = x;
    _offsetY = y;
    _hasCustomOffset = true;
  }

  void setColors(List<LoveColor> colors) {
    _colors = List<LoveColor>.unmodifiable(
      colors.map((color) => color.clamped()),
    );
  }

  void setQuads(List<LoveQuad> quads) {
    _quads = List<LoveQuad>.unmodifiable(quads.map((quad) => quad.copy()));
  }

  void setRelativeRotation(bool enable) {
    _relativeRotation = enable;
  }

  void start() {
    _active = true;
    _paused = false;
    _stopped = false;
  }

  void stop() {
    _active = false;
    _paused = false;
    _stopped = true;
    _emitterAge = 0.0;
    _emissionCarry = 0.0;
  }

  void pause() {
    _active = false;
    _paused = true;
    _stopped = false;
  }

  void reset() {
    _particles.clear();
    _emitterAge = 0.0;
    _emissionCarry = 0.0;
  }

  void emit(int count, LoveRandomGenerator random) {
    if (count <= 0 || _particleLifetimeMax <= 0) {
      return;
    }

    for (var index = 0; index < count; index++) {
      final progress = count == 1 ? 0.0 : index / (count - 1);
      _insertParticle(
        _spawnParticle(random, progressFraction: progress, extraAge: 0.0),
        random,
      );
    }
  }

  void update(double dt, LoveRandomGenerator random) {
    if (dt <= 0) {
      _previousPositionX = _positionX;
      _previousPositionY = _positionY;
      return;
    }

    if (_paused) {
      _previousPositionX = _positionX;
      _previousPositionY = _positionY;
      return;
    }

    _updateLiveParticles(dt);
    _emitDuringUpdate(dt, random);
    _previousPositionX = _positionX;
    _previousPositionY = _positionY;
  }

  LoveParticleSystemSnapshot snapshotForDraw() {
    final texture = switch (_texture) {
      final LoveCanvas canvas => canvas.snapshot(),
      final LoveImage image => image,
    };
    return LoveParticleSystemSnapshot(
      texture: texture,
      particles: _particles.map(
        (particle) => _drawEntryForParticle(texture, particle),
      ),
    );
  }

  void _updateLiveParticles(double dt) {
    for (var index = _particles.length - 1; index >= 0; index--) {
      final particle = _particles[index];
      _advanceParticle(particle, dt);
      if (particle.age >= particle.lifetime) {
        _particles.removeAt(index);
      }
    }
  }

  void _emitDuringUpdate(double dt, LoveRandomGenerator random) {
    if (!_active || _emissionRate <= 0 || _particleLifetimeMax <= 0) {
      if (_emitterLifetime >= 0 && _active) {
        _emitterAge += dt;
        if (_emitterAge >= _emitterLifetime) {
          _active = false;
          _stopped = true;
        }
      }
      return;
    }

    var emissionDt = dt;
    if (_emitterLifetime >= 0) {
      final remaining = _emitterLifetime - _emitterAge;
      if (remaining <= 0) {
        _active = false;
        _stopped = true;
        _emitterAge = _emitterLifetime;
        return;
      }

      emissionDt = math.min(dt, remaining);
      _emitterAge += dt;
      if (_emitterAge >= _emitterLifetime) {
        _active = false;
        _stopped = true;
      }
    }

    _emissionCarry += emissionDt * _emissionRate;
    final emitCount = _emissionCarry.floor();
    _emissionCarry -= emitCount;
    if (emitCount <= 0) {
      return;
    }

    for (var index = 0; index < emitCount; index++) {
      final progress = (index + 1) / (emitCount + 1);
      final particle = _spawnParticle(
        random,
        progressFraction: progress,
        extraAge: dt * (1.0 - progress),
      );
      _insertParticle(particle, random);
    }
  }

  _LoveParticle _spawnParticle(
    LoveRandomGenerator random, {
    required double progressFraction,
    required double extraAge,
  }) {
    final emitterX = _particleLerp(
      _previousPositionX,
      _positionX,
      progressFraction,
    );
    final emitterY = _particleLerp(
      _previousPositionY,
      _positionY,
      progressFraction,
    );
    final emissionAreaOffset = _spawnEmissionAreaOffset(random);
    final rotatedOffset = _rotatePoint(
      emissionAreaOffset.x,
      emissionAreaOffset.y,
      _emissionAreaAngle,
    );
    final spawnX = emitterX + rotatedOffset.x;
    final spawnY = emitterY + rotatedOffset.y;
    final directionFromCenter =
        _emissionAreaDirectionRelativeToCenter &&
            (rotatedOffset.x != 0 || rotatedOffset.y != 0)
        ? math.atan2(rotatedOffset.y, rotatedOffset.x)
        : 0.0;
    final particleDirection =
        _direction + directionFromCenter + _randomSpread(random);
    final speed = _randomBetween(random, _speedMin, _speedMax);
    final rotation = _randomBetween(random, _rotationMin, _rotationMax);
    final sampledSpin = _randomBetween(random, _spinMin, _spinMax);
    final spin = _particleLerp(
      _spinMin,
      sampledSpin,
      _randomUnit(random).clamp(1.0 - _spinVariation.clamp(0.0, 1.0), 1.0),
    );
    final sizeScale =
        1.0 + ((_randomUnit(random) - 0.5) * _sizeVariation.clamp(0.0, 1.0));
    final particle = _LoveParticle(
      originX: emitterX,
      originY: emitterY,
      x: spawnX,
      y: spawnY,
      velocityX: math.cos(particleDirection) * speed,
      velocityY: math.sin(particleDirection) * speed,
      linearAccelerationX: _randomBetween(
        random,
        _linearAccelerationMinX,
        _linearAccelerationMaxX,
      ),
      linearAccelerationY: _randomBetween(
        random,
        _linearAccelerationMinY,
        _linearAccelerationMaxY,
      ),
      radialAcceleration: _randomBetween(
        random,
        _radialAccelerationMin,
        _radialAccelerationMax,
      ),
      tangentialAcceleration: _randomBetween(
        random,
        _tangentialAccelerationMin,
        _tangentialAccelerationMax,
      ),
      linearDamping: _randomBetween(
        random,
        _linearDampingMin,
        _linearDampingMax,
      ),
      rotation: rotation,
      spin: spin,
      sizeScale: sizeScale,
      lifetime: _randomBetween(
        random,
        _particleLifetimeMin,
        _particleLifetimeMax,
      ),
    );
    if (extraAge > 0) {
      _advanceParticle(particle, extraAge);
    }
    return particle;
  }

  void _advanceParticle(_LoveParticle particle, double dt) {
    if (particle.age >= particle.lifetime) {
      return;
    }

    final dx = particle.x - particle.originX;
    final dy = particle.y - particle.originY;
    final length = math.sqrt((dx * dx) + (dy * dy));
    var radialX = 0.0;
    var radialY = 0.0;
    if (length > 0.0001) {
      radialX = dx / length;
      radialY = dy / length;
    }

    final tangentialX = -radialY;
    final tangentialY = radialX;
    final accelerationX =
        particle.linearAccelerationX +
        (radialX * particle.radialAcceleration) +
        (tangentialX * particle.tangentialAcceleration);
    final accelerationY =
        particle.linearAccelerationY +
        (radialY * particle.radialAcceleration) +
        (tangentialY * particle.tangentialAcceleration);

    particle.velocityX += accelerationX * dt;
    particle.velocityY += accelerationY * dt;
    if (particle.linearDamping != 0) {
      final damping = math.max(0.0, 1.0 - (particle.linearDamping * dt));
      particle.velocityX *= damping;
      particle.velocityY *= damping;
    }
    particle.x += particle.velocityX * dt;
    particle.y += particle.velocityY * dt;
    particle.rotation += particle.spin * dt;
    particle.age = math.min(particle.lifetime, particle.age + dt);
  }

  void _insertParticle(_LoveParticle particle, LoveRandomGenerator random) {
    switch (_insertMode) {
      case LoveParticleInsertMode.top:
        _particles.insert(0, particle);
      case LoveParticleInsertMode.bottom:
        _particles.add(particle);
      case LoveParticleInsertMode.random:
        final index = _particles.isEmpty
            ? 0
            : (_randomUnit(random) * (_particles.length + 1)).floor();
        _particles.insert(index, particle);
    }

    if (_particles.length <= _bufferSize) {
      return;
    }

    switch (_insertMode) {
      case LoveParticleInsertMode.top:
        _particles.removeLast();
      case LoveParticleInsertMode.bottom:
        _particles.removeAt(0);
      case LoveParticleInsertMode.random:
        final index = (_randomUnit(random) * _particles.length).floor();
        _particles.removeAt(index.clamp(0, _particles.length - 1));
    }
  }

  LoveParticleDrawEntry _drawEntryForParticle(
    LoveImage texture,
    _LoveParticle particle,
  ) {
    final progress = particle.progress;
    final quad = _quadForProgress(progress);
    final size = _sizeForProgress(progress) * particle.sizeScale;
    final tint = _colorForProgress(progress);
    final velocityAngle = (particle.velocityX == 0 && particle.velocityY == 0)
        ? 0.0
        : math.atan2(particle.velocityY, particle.velocityX);
    final rotation = _relativeRotation
        ? velocityAngle + particle.rotation
        : particle.rotation;
    final resolvedOffset = _resolvedOffset(texture, quad);

    return LoveParticleDrawEntry(
      transform: _matrixFromTransformation(
        x: particle.x,
        y: particle.y,
        angle: rotation,
        scaleX: size,
        scaleY: size,
        originX: resolvedOffset.x,
        originY: resolvedOffset.y,
        shearX: 0.0,
        shearY: 0.0,
      ),
      color: tint,
      quad: quad,
    );
  }

  LoveQuad? _quadForProgress(double progress) {
    if (_quads.isEmpty) {
      return null;
    }

    final index = math.min(
      _quads.length - 1,
      (progress * _quads.length).floor(),
    );
    return _quads[index];
  }

  ({double x, double y}) _resolvedOffset(LoveImage texture, LoveQuad? quad) {
    if (_hasCustomOffset) {
      return (x: _offsetX, y: _offsetY);
    }

    if (quad != null) {
      return (x: quad.width / 2.0, y: quad.height / 2.0);
    }

    return (x: texture.width / 2.0, y: texture.height / 2.0);
  }

  LoveColor _colorForProgress(double progress) {
    if (_colors.length == 1) {
      return _colors.single;
    }

    final scaled = progress * (_colors.length - 1);
    final index = scaled.floor().clamp(0, _colors.length - 1);
    final nextIndex = math.min(_colors.length - 1, index + 1);
    final localT = scaled - index;
    final from = _colors[index];
    final to = _colors[nextIndex];
    return LoveColor(
      _particleLerp(from.r, to.r, localT),
      _particleLerp(from.g, to.g, localT),
      _particleLerp(from.b, to.b, localT),
      _particleLerp(from.a, to.a, localT),
    ).clamped();
  }

  double _sizeForProgress(double progress) {
    if (_sizes.length == 1) {
      return _sizes.single;
    }

    final scaled = progress * (_sizes.length - 1);
    final index = scaled.floor().clamp(0, _sizes.length - 1);
    final nextIndex = math.min(_sizes.length - 1, index + 1);
    final localT = scaled - index;
    return _particleLerp(_sizes[index], _sizes[nextIndex], localT);
  }

  ({double x, double y}) _spawnEmissionAreaOffset(LoveRandomGenerator random) {
    switch (_emissionAreaDistribution) {
      case LoveParticleAreaSpreadDistribution.none:
        return (x: 0.0, y: 0.0);
      case LoveParticleAreaSpreadDistribution.uniform:
        return (
          x: _randomBetween(random, -_emissionAreaDx, _emissionAreaDx),
          y: _randomBetween(random, -_emissionAreaDy, _emissionAreaDy),
        );
      case LoveParticleAreaSpreadDistribution.normal:
        return (
          x: random.randomNormal(_emissionAreaDx, 0.0),
          y: random.randomNormal(_emissionAreaDy, 0.0),
        );
      case LoveParticleAreaSpreadDistribution.ellipse:
        final angle = _randomBetween(random, 0.0, math.pi * 2.0);
        final radius = math.sqrt(_randomUnit(random));
        return (
          x: math.cos(angle) * _emissionAreaDx * radius,
          y: math.sin(angle) * _emissionAreaDy * radius,
        );
      case LoveParticleAreaSpreadDistribution.borderEllipse:
        final angle = _randomBetween(random, 0.0, math.pi * 2.0);
        return (
          x: math.cos(angle) * _emissionAreaDx,
          y: math.sin(angle) * _emissionAreaDy,
        );
      case LoveParticleAreaSpreadDistribution.borderRectangle:
        final perimeter = (_emissionAreaDx * 4) + (_emissionAreaDy * 4);
        if (perimeter <= 0) {
          return (x: 0.0, y: 0.0);
        }

        final distance = _randomBetween(random, 0.0, perimeter);
        if (distance < _emissionAreaDx * 2) {
          return (x: distance - _emissionAreaDx, y: -_emissionAreaDy);
        }

        if (distance < (_emissionAreaDx * 2) + (_emissionAreaDy * 2)) {
          return (
            x: _emissionAreaDx,
            y: (distance - (_emissionAreaDx * 2)) - _emissionAreaDy,
          );
        }

        if (distance < (_emissionAreaDx * 4) + (_emissionAreaDy * 2)) {
          return (
            x:
                _emissionAreaDx -
                (distance - ((_emissionAreaDx * 2) + (_emissionAreaDy * 2))),
            y: _emissionAreaDy,
          );
        }

        return (
          x: -_emissionAreaDx,
          y:
              _emissionAreaDy -
              (distance - ((_emissionAreaDx * 4) + (_emissionAreaDy * 2))),
        );
    }
  }

  double _randomSpread(LoveRandomGenerator random) {
    if (_spread == 0) {
      return 0.0;
    }

    return _randomBetween(random, -_spread / 2.0, _spread / 2.0);
  }
}

double _randomBetween(LoveRandomGenerator random, double min, double max) {
  if (min == max) {
    return min;
  }

  final low = math.min(min, max);
  final high = math.max(min, max);
  return low + (_randomUnit(random) * (high - low));
}

double _randomUnit(LoveRandomGenerator random) {
  return random.nextUnitDouble();
}

double _particleLerp(double a, double b, double t) {
  return a + ((b - a) * t);
}

({double x, double y}) _rotatePoint(double x, double y, double angle) {
  if (angle == 0) {
    return (x: x, y: y);
  }

  final cosAngle = math.cos(angle);
  final sinAngle = math.sin(angle);
  return (
    x: (x * cosAngle) - (y * sinAngle),
    y: (x * sinAngle) + (y * cosAngle),
  );
}
