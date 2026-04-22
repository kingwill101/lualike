part of '../love_api_bindings.dart';

Value _wrapParticleSystem(
  LibraryRegistrationContext context,
  LoveParticleSystem particleSystem,
) {
  final cached = _loveParticleSystemWrapperCache[particleSystem];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final runtime = _runtimeContext(context);
  final table = ValueClass.table(<Object?, Object?>{
    _loveParticleSystemObjectKey: particleSystem,
    'clone': Value(
      builder.create(
        (args) => _wrapParticleSystem(
          context,
          _requireParticleSystem(args, 0, 'ParticleSystem:clone').clone(),
        ),
      ),
      functionName: 'clone',
    ),
    'emit': Value(
      builder.create((args) {
        _requireParticleSystem(args, 0, 'ParticleSystem:emit').emit(
          _requireRoundedInt(args, 1, 'ParticleSystem:emit'),
          runtime.random,
        );
        return null;
      }),
      functionName: 'emit',
    ),
    'getBufferSize': Value(
      builder.create(
        (args) => _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getBufferSize',
        ).bufferSize,
      ),
      functionName: 'getBufferSize',
    ),
    'getColors': Value(
      builder.create((args) {
        final colors = _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getColors',
        ).colors;
        return Value.multi(
          colors
              .map(
                (color) => ValueClass.table(<Object?, Object?>{
                  1: color.r,
                  2: color.g,
                  3: color.b,
                  4: color.a,
                }),
              )
              .toList(growable: false),
        );
      }),
      functionName: 'getColors',
    ),
    'getCount': Value(
      builder.create(
        (args) =>
            _requireParticleSystem(args, 0, 'ParticleSystem:getCount').count,
      ),
      functionName: 'getCount',
    ),
    'getDirection': Value(
      builder.create(
        (args) => _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getDirection',
        ).direction,
      ),
      functionName: 'getDirection',
    ),
    'getEmissionArea': Value(
      builder.create((args) {
        final area = _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getEmissionArea',
        ).emissionArea;
        return Value.multi(<Object?>[
          _particleDistributionName(area.distribution),
          area.dx,
          area.dy,
          area.angle,
          area.directionRelativeToCenter,
        ]);
      }),
      functionName: 'getEmissionArea',
    ),
    'getAreaSpread': Value(
      builder.create((args) {
        final area = _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getAreaSpread',
        ).emissionArea;
        return Value.multi(<Object?>[
          _particleDistributionName(area.distribution),
          area.dx,
          area.dy,
        ]);
      }),
      functionName: 'getAreaSpread',
    ),
    'getEmissionRate': Value(
      builder.create(
        (args) => _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getEmissionRate',
        ).emissionRate,
      ),
      functionName: 'getEmissionRate',
    ),
    'getEmitterLifetime': Value(
      builder.create(
        (args) => _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getEmitterLifetime',
        ).emitterLifetime,
      ),
      functionName: 'getEmitterLifetime',
    ),
    'getInsertMode': Value(
      builder.create(
        (args) => _particleInsertModeName(
          _requireParticleSystem(
            args,
            0,
            'ParticleSystem:getInsertMode',
          ).insertMode,
        ),
      ),
      functionName: 'getInsertMode',
    ),
    'getLinearAcceleration': Value(
      builder.create((args) {
        final acceleration = _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getLinearAcceleration',
        ).linearAcceleration;
        return Value.multi(<Object?>[
          acceleration.minX,
          acceleration.minY,
          acceleration.maxX,
          acceleration.maxY,
        ]);
      }),
      functionName: 'getLinearAcceleration',
    ),
    'getLinearDamping': Value(
      builder.create((args) {
        final damping = _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getLinearDamping',
        ).linearDamping;
        return Value.multi(<Object?>[damping.min, damping.max]);
      }),
      functionName: 'getLinearDamping',
    ),
    'getOffset': Value(
      builder.create((args) {
        final offset = _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getOffset',
        ).offset;
        return Value.multi(<Object?>[offset.x, offset.y]);
      }),
      functionName: 'getOffset',
    ),
    'getParticleLifetime': Value(
      builder.create((args) {
        final lifetime = _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getParticleLifetime',
        ).particleLifetime;
        return Value.multi(<Object?>[lifetime.min, lifetime.max]);
      }),
      functionName: 'getParticleLifetime',
    ),
    'getPosition': Value(
      builder.create((args) {
        final position = _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getPosition',
        ).position;
        return Value.multi(<Object?>[position.x, position.y]);
      }),
      functionName: 'getPosition',
    ),
    'getQuads': Value(
      builder.create((args) {
        final quads = _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getQuads',
        ).quads;
        final wrapped = <Object?, Object?>{};
        for (var index = 0; index < quads.length; index++) {
          wrapped[index + 1] = _wrapQuad(context, quads[index]);
        }
        return ValueClass.table(wrapped);
      }),
      functionName: 'getQuads',
    ),
    'getRadialAcceleration': Value(
      builder.create((args) {
        final acceleration = _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getRadialAcceleration',
        ).radialAcceleration;
        return Value.multi(<Object?>[acceleration.min, acceleration.max]);
      }),
      functionName: 'getRadialAcceleration',
    ),
    'getRotation': Value(
      builder.create((args) {
        final rotation = _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getRotation',
        ).rotation;
        return Value.multi(<Object?>[rotation.min, rotation.max]);
      }),
      functionName: 'getRotation',
    ),
    'getSizeVariation': Value(
      builder.create(
        (args) => _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getSizeVariation',
        ).sizeVariation,
      ),
      functionName: 'getSizeVariation',
    ),
    'getSizes': Value(
      builder.create(
        (args) => Value.multi(
          _requireParticleSystem(
            args,
            0,
            'ParticleSystem:getSizes',
          ).sizes.cast<Object?>(),
        ),
      ),
      functionName: 'getSizes',
    ),
    'getSpeed': Value(
      builder.create((args) {
        final speed = _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getSpeed',
        ).speed;
        return Value.multi(<Object?>[speed.min, speed.max]);
      }),
      functionName: 'getSpeed',
    ),
    'getSpin': Value(
      builder.create((args) {
        final system = _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getSpin',
        );
        return Value.multi(<Object?>[
          system.spin.min,
          system.spin.max,
          system.spinVariation,
        ]);
      }),
      functionName: 'getSpin',
    ),
    'getSpinVariation': Value(
      builder.create(
        (args) => _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getSpinVariation',
        ).spinVariation,
      ),
      functionName: 'getSpinVariation',
    ),
    'getSpread': Value(
      builder.create(
        (args) =>
            _requireParticleSystem(args, 0, 'ParticleSystem:getSpread').spread,
      ),
      functionName: 'getSpread',
    ),
    'getTangentialAcceleration': Value(
      builder.create((args) {
        final acceleration = _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getTangentialAcceleration',
        ).tangentialAcceleration;
        return Value.multi(<Object?>[acceleration.min, acceleration.max]);
      }),
      functionName: 'getTangentialAcceleration',
    ),
    'getTexture': Value(
      builder.create((args) {
        final texture = _requireParticleSystem(
          args,
          0,
          'ParticleSystem:getTexture',
        ).texture;
        return texture is LoveCanvas
            ? _wrapCanvas(context, texture)
            : _wrapImage(context, texture);
      }),
      functionName: 'getTexture',
    ),
    'hasRelativeRotation': Value(
      builder.create(
        (args) => _requireParticleSystem(
          args,
          0,
          'ParticleSystem:hasRelativeRotation',
        ).relativeRotation,
      ),
      functionName: 'hasRelativeRotation',
    ),
    'isActive': Value(
      builder.create(
        (args) =>
            _requireParticleSystem(args, 0, 'ParticleSystem:isActive').isActive,
      ),
      functionName: 'isActive',
    ),
    'isPaused': Value(
      builder.create(
        (args) =>
            _requireParticleSystem(args, 0, 'ParticleSystem:isPaused').isPaused,
      ),
      functionName: 'isPaused',
    ),
    'isStopped': Value(
      builder.create(
        (args) => _requireParticleSystem(
          args,
          0,
          'ParticleSystem:isStopped',
        ).isStopped,
      ),
      functionName: 'isStopped',
    ),
    'moveTo': Value(
      builder.create((args) {
        _requireParticleSystem(args, 0, 'ParticleSystem:moveTo').moveTo(
          _requireNumber(args, 1, 'ParticleSystem:moveTo'),
          _requireNumber(args, 2, 'ParticleSystem:moveTo'),
        );
        return null;
      }),
      functionName: 'moveTo',
    ),
    'pause': Value(
      builder.create((args) {
        _requireParticleSystem(args, 0, 'ParticleSystem:pause').pause();
        return null;
      }),
      functionName: 'pause',
    ),
    'release': Value(builder.create((args) => null), functionName: 'release'),
    'reset': Value(
      builder.create((args) {
        _requireParticleSystem(args, 0, 'ParticleSystem:reset').reset();
        return null;
      }),
      functionName: 'reset',
    ),
    'setBufferSize': Value(
      builder.create((args) {
        final size = _requireRoundedInt(
          args,
          1,
          'ParticleSystem:setBufferSize',
        );
        if (size < 1) {
          throw LuaError('Invalid buffer size');
        }
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setBufferSize',
        ).setBufferSize(size);
        return null;
      }),
      functionName: 'setBufferSize',
    ),
    'setColors': Value(
      builder.create((args) {
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setColors',
        ).setColors(_particleColorsFromArgs(args, 'ParticleSystem:setColors'));
        return null;
      }),
      functionName: 'setColors',
    ),
    'setDirection': Value(
      builder.create((args) {
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setDirection',
        ).setDirection(_requireNumber(args, 1, 'ParticleSystem:setDirection'));
        return null;
      }),
      functionName: 'setDirection',
    ),
    'setEmissionArea': Value(
      builder.create((args) {
        final distribution = _particleDistribution(
          _stringLike(_valueAt(args, 1)),
          'ParticleSystem:setEmissionArea',
        );
        if (distribution == LoveParticleAreaSpreadDistribution.none) {
          _requireParticleSystem(
            args,
            0,
            'ParticleSystem:setEmissionArea',
          ).setEmissionArea(distribution, 0.0, 0.0);
          return null;
        }

        final dx = _requireNumber(args, 2, 'ParticleSystem:setEmissionArea');
        final dy = _requireNumber(args, 3, 'ParticleSystem:setEmissionArea');
        if (dx < 0 || dy < 0) {
          throw LuaError('Invalid area spread parameters (must be >= 0)');
        }
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setEmissionArea',
        ).setEmissionArea(
          distribution,
          dx,
          dy,
          _optionalNumber(
            args,
            4,
            'ParticleSystem:setEmissionArea',
            defaultValue: 0.0,
          ),
          args.length >= 6
              ? _requireBoolean(args, 5, 'ParticleSystem:setEmissionArea')
              : false,
        );
        return null;
      }),
      functionName: 'setEmissionArea',
    ),
    'setAreaSpread': Value(
      builder.create((args) {
        final distribution = _particleDistribution(
          _stringLike(_valueAt(args, 1)),
          'ParticleSystem:setAreaSpread',
        );
        if (distribution == LoveParticleAreaSpreadDistribution.none) {
          _requireParticleSystem(
            args,
            0,
            'ParticleSystem:setAreaSpread',
          ).setEmissionArea(distribution, 0.0, 0.0);
          return null;
        }

        final dx = _requireNumber(args, 2, 'ParticleSystem:setAreaSpread');
        final dy = _requireNumber(args, 3, 'ParticleSystem:setAreaSpread');
        if (dx < 0 || dy < 0) {
          throw LuaError('Invalid area spread parameters (must be >= 0)');
        }
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setAreaSpread',
        ).setEmissionArea(distribution, dx, dy, 0.0, false);
        return null;
      }),
      functionName: 'setAreaSpread',
    ),
    'setEmissionRate': Value(
      builder.create((args) {
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setEmissionRate',
        ).setEmissionRate(
          _requireNumber(args, 1, 'ParticleSystem:setEmissionRate'),
        );
        return null;
      }),
      functionName: 'setEmissionRate',
    ),
    'setEmitterLifetime': Value(
      builder.create((args) {
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setEmitterLifetime',
        ).setEmitterLifetime(
          _requireNumber(args, 1, 'ParticleSystem:setEmitterLifetime'),
        );
        return null;
      }),
      functionName: 'setEmitterLifetime',
    ),
    'setInsertMode': Value(
      builder.create((args) {
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setInsertMode',
        ).setInsertMode(
          _particleInsertMode(
            _requireString(args, 1, 'ParticleSystem:setInsertMode'),
            'ParticleSystem:setInsertMode',
          ),
        );
        return null;
      }),
      functionName: 'setInsertMode',
    ),
    'setLinearAcceleration': Value(
      builder.create((args) {
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setLinearAcceleration',
        ).setLinearAcceleration(
          _requireNumber(args, 1, 'ParticleSystem:setLinearAcceleration'),
          _requireNumber(args, 2, 'ParticleSystem:setLinearAcceleration'),
          args.length >= 4
              ? _requireNumber(args, 3, 'ParticleSystem:setLinearAcceleration')
              : null,
          args.length >= 5
              ? _requireNumber(args, 4, 'ParticleSystem:setLinearAcceleration')
              : null,
        );
        return null;
      }),
      functionName: 'setLinearAcceleration',
    ),
    'setLinearDamping': Value(
      builder.create((args) {
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setLinearDamping',
        ).setLinearDamping(
          _requireNumber(args, 1, 'ParticleSystem:setLinearDamping'),
          args.length >= 3
              ? _requireNumber(args, 2, 'ParticleSystem:setLinearDamping')
              : null,
        );
        return null;
      }),
      functionName: 'setLinearDamping',
    ),
    'setOffset': Value(
      builder.create((args) {
        _requireParticleSystem(args, 0, 'ParticleSystem:setOffset').setOffset(
          _requireNumber(args, 1, 'ParticleSystem:setOffset'),
          _requireNumber(args, 2, 'ParticleSystem:setOffset'),
        );
        return null;
      }),
      functionName: 'setOffset',
    ),
    'setParticleLifetime': Value(
      builder.create((args) {
        final min = _requireNumber(
          args,
          1,
          'ParticleSystem:setParticleLifetime',
        );
        final max = args.length >= 3
            ? _requireNumber(args, 2, 'ParticleSystem:setParticleLifetime')
            : min;
        if (min < 0 || max < 0) {
          throw LuaError('Invalid particle lifetime (must be >= 0)');
        }
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setParticleLifetime',
        ).setParticleLifetime(min, max);
        return null;
      }),
      functionName: 'setParticleLifetime',
    ),
    'setPosition': Value(
      builder.create((args) {
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setPosition',
        ).setPosition(
          _requireNumber(args, 1, 'ParticleSystem:setPosition'),
          _requireNumber(args, 2, 'ParticleSystem:setPosition'),
        );
        return null;
      }),
      functionName: 'setPosition',
    ),
    'setQuads': Value(
      builder.create((args) {
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setQuads',
        ).setQuads(_particleQuadsFromArgs(args, 'ParticleSystem:setQuads'));
        return null;
      }),
      functionName: 'setQuads',
    ),
    'setRadialAcceleration': Value(
      builder.create((args) {
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setRadialAcceleration',
        ).setRadialAcceleration(
          _requireNumber(args, 1, 'ParticleSystem:setRadialAcceleration'),
          args.length >= 3
              ? _requireNumber(args, 2, 'ParticleSystem:setRadialAcceleration')
              : null,
        );
        return null;
      }),
      functionName: 'setRadialAcceleration',
    ),
    'setRelativeRotation': Value(
      builder.create((args) {
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setRelativeRotation',
        ).setRelativeRotation(
          _requireBoolean(args, 1, 'ParticleSystem:setRelativeRotation'),
        );
        return null;
      }),
      functionName: 'setRelativeRotation',
    ),
    'setRotation': Value(
      builder.create((args) {
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setRotation',
        ).setRotation(
          _requireNumber(args, 1, 'ParticleSystem:setRotation'),
          args.length >= 3
              ? _requireNumber(args, 2, 'ParticleSystem:setRotation')
              : null,
        );
        return null;
      }),
      functionName: 'setRotation',
    ),
    'setSizeVariation': Value(
      builder.create((args) {
        final value = _requireNumber(
          args,
          1,
          'ParticleSystem:setSizeVariation',
        );
        if (value < 0 || value > 1) {
          throw LuaError(
            'Size variation has to be between 0 and 1, inclusive.',
          );
        }
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setSizeVariation',
        ).setSizeVariation(value);
        return null;
      }),
      functionName: 'setSizeVariation',
    ),
    'setSizes': Value(
      builder.create((args) {
        final sizeCount = args.length - 1;
        if (sizeCount <= 0) {
          throw LuaError('ParticleSystem:setSizes expects at least 1 argument');
        }
        if (sizeCount > 8) {
          throw LuaError('At most eight (8) sizes may be used.');
        }
        _requireParticleSystem(args, 0, 'ParticleSystem:setSizes').setSizes(
          args
              .skip(1)
              .map((value) {
                final raw = _rawValue(value);
                if (raw is num) {
                  return raw.toDouble();
                }
                throw LuaError('ParticleSystem:setSizes expected a number');
              })
              .toList(growable: false),
        );
        return null;
      }),
      functionName: 'setSizes',
    ),
    'setSpeed': Value(
      builder.create((args) {
        _requireParticleSystem(args, 0, 'ParticleSystem:setSpeed').setSpeed(
          _requireNumber(args, 1, 'ParticleSystem:setSpeed'),
          args.length >= 3
              ? _requireNumber(args, 2, 'ParticleSystem:setSpeed')
              : null,
        );
        return null;
      }),
      functionName: 'setSpeed',
    ),
    'setSpin': Value(
      builder.create((args) {
        _requireParticleSystem(args, 0, 'ParticleSystem:setSpin').setSpin(
          _requireNumber(args, 1, 'ParticleSystem:setSpin'),
          args.length >= 3
              ? _requireNumber(args, 2, 'ParticleSystem:setSpin')
              : null,
        );
        return null;
      }),
      functionName: 'setSpin',
    ),
    'setSpinVariation': Value(
      builder.create((args) {
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setSpinVariation',
        ).setSpinVariation(
          _requireNumber(args, 1, 'ParticleSystem:setSpinVariation'),
        );
        return null;
      }),
      functionName: 'setSpinVariation',
    ),
    'setSpread': Value(
      builder.create((args) {
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setSpread',
        ).setSpread(_requireNumber(args, 1, 'ParticleSystem:setSpread'));
        return null;
      }),
      functionName: 'setSpread',
    ),
    'setTangentialAcceleration': Value(
      builder.create((args) {
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setTangentialAcceleration',
        ).setTangentialAcceleration(
          _requireNumber(args, 1, 'ParticleSystem:setTangentialAcceleration'),
          args.length >= 3
              ? _requireNumber(
                  args,
                  2,
                  'ParticleSystem:setTangentialAcceleration',
                )
              : null,
        );
        return null;
      }),
      functionName: 'setTangentialAcceleration',
    ),
    'setTexture': Value(
      builder.create((args) {
        _requireParticleSystem(
          args,
          0,
          'ParticleSystem:setTexture',
        ).setTexture(_requireImage(args, 1, 'ParticleSystem:setTexture'));
        return null;
      }),
      functionName: 'setTexture',
    ),
    'start': Value(
      builder.create((args) {
        _requireParticleSystem(args, 0, 'ParticleSystem:start').start();
        return null;
      }),
      functionName: 'start',
    ),
    'stop': Value(
      builder.create((args) {
        _requireParticleSystem(args, 0, 'ParticleSystem:stop').stop();
        return null;
      }),
      functionName: 'stop',
    ),
    'type': Value(
      builder.create((args) => 'ParticleSystem'),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        final name = _requireString(args, 1, 'ParticleSystem:typeOf');
        return name == 'ParticleSystem' ||
            name == 'Drawable' ||
            name == 'Object';
      }),
      functionName: 'typeOf',
    ),
    'update': Value(
      builder.create((args) {
        _requireParticleSystem(args, 0, 'ParticleSystem:update').update(
          _requireNumber(args, 1, 'ParticleSystem:update'),
          runtime.random,
        );
        return null;
      }),
      functionName: 'update',
    ),
  });
  _loveParticleSystemWrapperCache[particleSystem] = table;
  return table;
}

LoveParticleInsertMode _particleInsertMode(String value, String symbol) {
  return switch (value) {
    'top' => LoveParticleInsertMode.top,
    'bottom' => LoveParticleInsertMode.bottom,
    'random' => LoveParticleInsertMode.random,
    _ => throw LuaError('$symbol invalid insert mode "$value"'),
  };
}

String _particleInsertModeName(LoveParticleInsertMode mode) {
  return switch (mode) {
    LoveParticleInsertMode.top => 'top',
    LoveParticleInsertMode.bottom => 'bottom',
    LoveParticleInsertMode.random => 'random',
  };
}

LoveParticleAreaSpreadDistribution _particleDistribution(
  String? value,
  String symbol,
) {
  return switch (value ?? 'none') {
    'uniform' => LoveParticleAreaSpreadDistribution.uniform,
    'normal' => LoveParticleAreaSpreadDistribution.normal,
    'ellipse' => LoveParticleAreaSpreadDistribution.ellipse,
    'borderellipse' => LoveParticleAreaSpreadDistribution.borderEllipse,
    'borderrectangle' => LoveParticleAreaSpreadDistribution.borderRectangle,
    'none' => LoveParticleAreaSpreadDistribution.none,
    final distribution => throw LuaError(
      '$symbol invalid particle distribution "$distribution"',
    ),
  };
}

String _particleDistributionName(LoveParticleAreaSpreadDistribution value) {
  return switch (value) {
    LoveParticleAreaSpreadDistribution.uniform => 'uniform',
    LoveParticleAreaSpreadDistribution.normal => 'normal',
    LoveParticleAreaSpreadDistribution.ellipse => 'ellipse',
    LoveParticleAreaSpreadDistribution.borderEllipse => 'borderellipse',
    LoveParticleAreaSpreadDistribution.borderRectangle => 'borderrectangle',
    LoveParticleAreaSpreadDistribution.none => 'none',
  };
}

List<LoveColor> _particleColorsFromArgs(List<Object?> args, String symbol) {
  final firstTable = _tableIfPresent(_valueAt(args, 1));
  if (firstTable != null && _looksLikeColorTable(firstTable)) {
    if (args.length - 1 > 8) {
      throw LuaError('At most eight (8) colors may be used.');
    }
    return args
        .skip(1)
        .map((entry) {
          final table = _tableIfPresent(entry);
          if (table == null || !_looksLikeColorTable(table)) {
            throw LuaError('$symbol expected a color table');
          }
          return LoveColor(
            _tableIndexedNumber(table, 1, symbol),
            _tableIndexedNumber(table, 2, symbol),
            _tableIndexedNumber(table, 3, symbol),
            _tableIndexedNumber(table, 4, symbol, defaultValue: 1.0),
          ).clamped();
        })
        .toList(growable: false);
  }

  final components = args.length - 1;
  if (components == 0) {
    throw LuaError('$symbol expected at least one color');
  }
  if (components == 3) {
    return <LoveColor>[_requireColor(args, 1, symbol).clamped()];
  }
  if (components % 4 != 0) {
    throw LuaError(
      'Expected red, green, blue, and alpha. Only got ${components % 4} of 4 components.',
    );
  }

  final colorCount = components ~/ 4;
  if (colorCount > 8) {
    throw LuaError('At most eight (8) colors may be used.');
  }
  return List<LoveColor>.generate(
    colorCount,
    (index) => _requireColor(args, 1 + (index * 4), symbol).clamped(),
    growable: false,
  );
}

List<LoveQuad> _particleQuadsFromArgs(List<Object?> args, String symbol) {
  final first = _valueAt(args, 1);
  final table = _tableIfPresent(first);
  if (_quadIfPresent(first) == null && table != null) {
    final quads = <LoveQuad>[];
    for (var index = 1; ; index++) {
      final entry = _tableIndexedEntry(table, index);
      if (entry == null) {
        break;
      }
      quads.add(_requireQuad(<Object?>[entry], 0, symbol));
    }
    return quads;
  }

  return args
      .skip(1)
      .map((entry) => _requireQuad(<Object?>[entry], 0, symbol))
      .toList(growable: false);
}
