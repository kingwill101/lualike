part of '../love_api_bindings.dart';

final Expando<bool> _loveMeshReleased = Expando<bool>('love2dMeshReleased');

LoveMesh? _meshIfPresent(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final mesh = table[_loveMeshObjectKey];
  return mesh is LoveMesh ? mesh : null;
}

LoveMesh _requireMesh(List<Object?> args, int index, String symbol) {
  final mesh = _meshIfPresent(_valueAt(args, index));
  if (mesh != null) {
    return mesh;
  }

  throw LuaError('$symbol expected a Mesh at argument ${index + 1}');
}

Value _wrapMesh(LibraryRegistrationContext context, LoveMesh mesh) {
  final cached = _loveMeshWrapperCache[mesh];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    _loveMeshObjectKey: mesh,
    'release': Value(
      builder.create((args) {
        final mesh = _requireMesh(args, 0, 'Object:release');
        if (_loveMeshReleased[mesh] == true) {
          return false;
        }
        _loveMeshReleased[mesh] = true;
        return true;
      }),
      functionName: 'release',
    ),
    'setVertices': Value(
      builder.create((args) {
        final mesh = _requireMesh(args, 0, 'Mesh:setVertices');
        final vertTable = _requireLuaTable(args, 1, 'Mesh:setVertices');
        final startVertex = args.length >= 3
            ? _requireRoundedInt(args, 2, 'Mesh:setVertices')
            : 1;
        final count = args.length >= 4
            ? _requireRoundedInt(args, 3, 'Mesh:setVertices')
            : null;
        final vertices = _meshVerticesFromTableWithFormat(
          vertTable,
          mesh.vertexFormat,
          'Mesh:setVertices',
        );
        mesh.setVertices(vertices, startVertex: startVertex, count: count);
        return null;
      }),
      functionName: 'setVertices',
    ),
    'getVertexCount': Value(
      builder.create(
        (args) => _requireMesh(args, 0, 'Mesh:getVertexCount').vertexCount,
      ),
      functionName: 'getVertexCount',
    ),
    'getVertex': Value(
      builder.create((args) {
        final mesh = _requireMesh(args, 0, 'Mesh:getVertex');
        final index = _requireRoundedInt(args, 1, 'Mesh:getVertex');
        if (index < 1 || index > mesh.vertexCount) {
          throw LuaError(
            'Mesh:getVertex index $index out of range [1, ${mesh.vertexCount}]',
          );
        }
        final v = mesh.vertices[index - 1];
        return Value.multi(<Object?>[
          v.x,
          v.y,
          v.u,
          v.v,
          v.color.r,
          v.color.g,
          v.color.b,
          v.color.a,
        ]);
      }),
      functionName: 'getVertex',
    ),
    'setVertex': Value(
      builder.create((args) {
        final mesh = _requireMesh(args, 0, 'Mesh:setVertex');
        final index = _requireRoundedInt(args, 1, 'Mesh:setVertex') - 1;
        if (index < 0 || index >= mesh.vertexCount) {
          throw LuaError(
            'Mesh:setVertex index ${index + 1} out of range [1, ${mesh.vertexCount}]',
          );
        }
        // Accept a flat list of components after the index argument.
        final components = args.skip(2).toList(growable: false);
        final vertex = _meshVertexFromComponents(
          components,
          mesh.vertexFormat,
          'Mesh:setVertex',
        );
        mesh.setVertices(
          <LoveMeshVertex>[vertex],
          startVertex: index + 1,
          count: 1,
        );
        return null;
      }),
      functionName: 'setVertex',
    ),
    'getVertexFormat': Value(
      builder.create((args) {
        final mesh = _requireMesh(args, 0, 'Mesh:getVertexFormat');
        final result = <Object?, Object?>{};
        for (var i = 0; i < mesh.vertexFormat.length; i++) {
          final attr = mesh.vertexFormat[i];
          result[i + 1] = Value(<Object?, Object?>{
            1: attr.name,
            2: attr.dataType,
            3: attr.components,
          });
        }
        return Value(result);
      }),
      functionName: 'getVertexFormat',
    ),
    'getDrawMode': Value(
      builder.create((args) {
        final mesh = _requireMesh(args, 0, 'Mesh:getDrawMode');
        return switch (mesh.drawMode) {
          LoveMeshDrawMode.fan => 'fan',
          LoveMeshDrawMode.strip => 'strip',
          LoveMeshDrawMode.triangles => 'triangles',
          LoveMeshDrawMode.points => 'points',
        };
      }),
      functionName: 'getDrawMode',
    ),
    'setDrawMode': Value(
      builder.create((args) {
        final mesh = _requireMesh(args, 0, 'Mesh:setDrawMode');
        mesh.drawMode = _meshDrawMode(_valueAt(args, 1), 'Mesh:setDrawMode');
        return null;
      }),
      functionName: 'setDrawMode',
    ),
    'type': Value(builder.create((args) => 'Mesh'), functionName: 'type'),
    'typeOf': Value(
      builder.create((args) {
        final queried = _requireString(args, 1, 'Object:typeOf');
        return queried == 'Mesh' ||
            queried == 'Drawable' ||
            queried == 'Object';
      }),
      functionName: 'typeOf',
    ),
    'getTexture': Value(
      builder.create((args) {
        final mesh = _requireMesh(args, 0, 'Mesh:getTexture');
        final tex = mesh.textureObject;
        if (tex == null) return null;
        if (tex is LoveCanvas) return _wrapCanvas(context, tex);
        if (tex is LoveImage) return _wrapImage(context, tex);
        return null;
      }),
      functionName: 'getTexture',
    ),
    'setTexture': Value(
      builder.create((args) {
        final mesh = _requireMesh(args, 0, 'Mesh:setTexture');
        if (args.length < 2 || _rawValue(_valueAt(args, 1)) == null) {
          mesh.clearTexture();
          return null;
        }
        final canvas = _canvasIfPresent(_valueAt(args, 1));
        if (canvas != null) {
          mesh.setCanvasTexture(canvas);
          return null;
        }
        final image = _imageIfPresent(_valueAt(args, 1));
        if (image != null) {
          mesh.setImageTexture(image);
          return null;
        }
        throw LuaError(
          'Mesh:setTexture expected a Texture, Image, or Canvas at argument 2',
        );
      }),
      functionName: 'setTexture',
    ),
    'getDrawRange': Value(
      builder.create((args) {
        final range = _requireMesh(args, 0, 'Mesh:getDrawRange').drawRange;
        if (range == null) return null;
        return Value.multi(<Object?>[range.min, range.max]);
      }),
      functionName: 'getDrawRange',
    ),
    'setDrawRange': Value(
      builder.create((args) {
        final mesh = _requireMesh(args, 0, 'Mesh:setDrawRange');
        if (args.length < 2 || _rawValue(_valueAt(args, 1)) == null) {
          mesh.clearDrawRange();
          return null;
        }
        final min = _requireRoundedInt(args, 1, 'Mesh:setDrawRange');
        final max = _requireRoundedInt(args, 2, 'Mesh:setDrawRange');
        if (min < 1 || max < min) {
          throw LuaError('Mesh:setDrawRange invalid range [$min, $max]');
        }
        mesh.setDrawRange(min, max);
        return null;
      }),
      functionName: 'setDrawRange',
    ),
    'getVertexMap': Value(
      builder.create((args) {
        final map = _requireMesh(args, 0, 'Mesh:getVertexMap').vertexMap;
        if (map == null) return null;
        final result = <Object?, Object?>{};
        for (var i = 0; i < map.length; i++) {
          result[i + 1] = map[i]; // Already 1-indexed in our storage
        }
        return Value(result);
      }),
      functionName: 'getVertexMap',
    ),
    'setVertexMap': Value(
      builder.create((args) {
        final mesh = _requireMesh(args, 0, 'Mesh:setVertexMap');
        if (args.length < 2 || _rawValue(_valueAt(args, 1)) == null) {
          mesh.setVertexMapData(null);
          return null;
        }
        final table = _tableIfPresent(_valueAt(args, 1));
        if (table == null) {
          throw LuaError(
            'Mesh:setVertexMap expected a table of indices at argument 2',
          );
        }
        final indices = <int>[];
        for (var i = 1; ; i++) {
          final entry = _tableIndexedEntry(table, i);
          if (entry == null) break;
          final idx = (_rawValue(entry) as num?)?.round();
          if (idx == null || idx < 1) {
            throw LuaError('Mesh:setVertexMap index at position $i is invalid');
          }
          indices.add(idx); // store as 1-indexed
        }
        mesh.setVertexMapData(indices.isEmpty ? null : indices);
        return null;
      }),
      functionName: 'setVertexMap',
    ),
    'isAttributeEnabled': Value(
      builder.create((args) {
        final mesh = _requireMesh(args, 0, 'Mesh:isAttributeEnabled');
        final name = _requireString(args, 1, 'Mesh:isAttributeEnabled');
        return mesh.isAttributeEnabled(name);
      }),
      functionName: 'isAttributeEnabled',
    ),
    'setAttributeEnabled': Value(
      builder.create((args) {
        final mesh = _requireMesh(args, 0, 'Mesh:setAttributeEnabled');
        final name = _requireString(args, 1, 'Mesh:setAttributeEnabled');
        final enabled = _requireBoolean(args, 2, 'Mesh:setAttributeEnabled');
        mesh.setAttributeEnabled(name, enabled);
        return null;
      }),
      functionName: 'setAttributeEnabled',
    ),
    'attachAttribute': Value(
      builder.create((args) {
        // Record attribute as enabled; full multi-mesh attribute blending is
        // not yet implemented in this runtime.
        final mesh = _requireMesh(args, 0, 'Mesh:attachAttribute');
        final name = _requireString(args, 1, 'Mesh:attachAttribute');
        mesh.setAttributeEnabled(name, true);
        return null;
      }),
      functionName: 'attachAttribute',
    ),
    'detachAttribute': Value(
      builder.create((args) {
        final mesh = _requireMesh(args, 0, 'Mesh:detachAttribute');
        final name = _requireString(args, 1, 'Mesh:detachAttribute');
        mesh.setAttributeEnabled(name, false);
        return null;
      }),
      functionName: 'detachAttribute',
    ),
    'getVertexAttribute': Value(
      builder.create((args) {
        final mesh = _requireMesh(args, 0, 'Mesh:getVertexAttribute');
        final vertexIndex = _requireRoundedInt(
          args,
          1,
          'Mesh:getVertexAttribute',
        );
        final attribIndex = _requireRoundedInt(
          args,
          2,
          'Mesh:getVertexAttribute',
        );
        if (vertexIndex < 1 || vertexIndex > mesh.vertexCount) {
          throw LuaError(
            'Mesh:getVertexAttribute vertex index $vertexIndex out of range',
          );
        }
        if (attribIndex < 1 || attribIndex > mesh.vertexFormat.length) {
          throw LuaError(
            'Mesh:getVertexAttribute attribute index $attribIndex out of range',
          );
        }
        final vertex = mesh.vertices[vertexIndex - 1];
        final attr = mesh.vertexFormat[attribIndex - 1];
        final nameLower = attr.name.toLowerCase();
        if (nameLower == 'vertexposition' || nameLower == 'position') {
          return Value.multi(<Object?>[vertex.x, vertex.y]);
        } else if (nameLower == 'vertextexcoord' || nameLower == 'texcoord') {
          return Value.multi(<Object?>[vertex.u, vertex.v]);
        } else if (nameLower == 'vertexcolor' || nameLower == 'color') {
          final r = vertex.color.r;
          final g = vertex.color.g;
          final b = vertex.color.b;
          final a = vertex.color.a;
          return attr.components >= 4
              ? Value.multi(<Object?>[r, g, b, a])
              : Value.multi(<Object?>[r, g, b]);
        }
        // For unknown attributes, return zeros for each component.
        return Value.multi(List<Object?>.filled(attr.components, 0));
      }),
      functionName: 'getVertexAttribute',
    ),
    'setVertexAttribute': Value(
      builder.create((args) {
        final mesh = _requireMesh(args, 0, 'Mesh:setVertexAttribute');
        final vertexIndex = _requireRoundedInt(
          args,
          1,
          'Mesh:setVertexAttribute',
        );
        final attribIndex = _requireRoundedInt(
          args,
          2,
          'Mesh:setVertexAttribute',
        );
        if (vertexIndex < 1 || vertexIndex > mesh.vertexCount) {
          throw LuaError(
            'Mesh:setVertexAttribute vertex index $vertexIndex out of range',
          );
        }
        if (attribIndex < 1 || attribIndex > mesh.vertexFormat.length) {
          throw LuaError(
            'Mesh:setVertexAttribute attribute index $attribIndex out of range',
          );
        }
        final vertex = mesh.vertices[vertexIndex - 1].copy();
        final attr = mesh.vertexFormat[attribIndex - 1];
        final nameLower = attr.name.toLowerCase();
        if (nameLower == 'vertexposition' || nameLower == 'position') {
          final x = _requireNumber(args, 3, 'Mesh:setVertexAttribute');
          final y = _requireNumber(args, 4, 'Mesh:setVertexAttribute');
          mesh.setVertices(
            <LoveMeshVertex>[
              LoveMeshVertex(
                x: x,
                y: y,
                u: vertex.u,
                v: vertex.v,
                color: vertex.color,
              ),
            ],
            startVertex: vertexIndex,
            count: 1,
          );
        } else if (nameLower == 'vertextexcoord' || nameLower == 'texcoord') {
          final u = _requireNumber(args, 3, 'Mesh:setVertexAttribute');
          final v = _requireNumber(args, 4, 'Mesh:setVertexAttribute');
          mesh.setVertices(
            <LoveMeshVertex>[
              LoveMeshVertex(
                x: vertex.x,
                y: vertex.y,
                u: u,
                v: v,
                color: vertex.color,
              ),
            ],
            startVertex: vertexIndex,
            count: 1,
          );
        } else if (nameLower == 'vertexcolor' || nameLower == 'color') {
          final r = _requireNumber(args, 3, 'Mesh:setVertexAttribute');
          final g = _requireNumber(args, 4, 'Mesh:setVertexAttribute');
          final b = _requireNumber(args, 5, 'Mesh:setVertexAttribute');
          final a = attr.components >= 4
              ? _requireNumber(args, 6, 'Mesh:setVertexAttribute')
              : vertex.color.a;
          mesh.setVertices(
            <LoveMeshVertex>[
              LoveMeshVertex(
                x: vertex.x,
                y: vertex.y,
                u: vertex.u,
                v: vertex.v,
                color: LoveColor(r, g, b, a).clamped(),
              ),
            ],
            startVertex: vertexIndex,
            count: 1,
          );
        }
        // Unknown attributes are silently ignored.
        return null;
      }),
      functionName: 'setVertexAttribute',
    ),
    'flush': Value(
      builder.create((args) {
        _requireMesh(args, 0, 'Mesh:flush');
        // No GPU upload needed in the command-based runtime.
        return null;
      }),
      functionName: 'flush',
    ),
  });
  _loveMeshWrapperCache[mesh] = table;
  return table;
}

// ---------------------------------------------------------------------------
// love.graphics.newMesh
// ---------------------------------------------------------------------------

LoveApiImplementation _bindGraphicsNewMesh(LibraryRegistrationContext context) {
  return (args) {
    const symbol = 'love.graphics.newMesh';
    final first = _valueAt(args, 0);
    final firstTable = _tableIfPresent(first);

    List<LoveMeshAttributeFormat>? vertexFormat;
    Object? verticesOrCount;
    Object? modeArg;
    Object? usageArg;

    if (firstTable != null) {
      // Determine whether the first table is a vertex-format spec or vertex
      // data.  A format spec has sub-tables whose first element is a string
      // (attribute name).  Vertex data has sub-tables whose first element is
      // a number (x coordinate).
      final firstEntry = _tableIndexedEntry(firstTable, 1);
      final isFormatSpec =
          firstEntry != null &&
          _tableIfPresent(firstEntry) != null &&
          _stringLike(_tableIndexedEntry(_tableIfPresent(firstEntry)!, 1)) !=
              null;

      if (isFormatSpec) {
        // Form: newMesh(vertexformat, vertices, mode, usage)
        //   or: newMesh(vertexformat, vertexcount, mode, usage)
        vertexFormat = _parseMeshFormat(firstTable, symbol);
        verticesOrCount = _valueAt(args, 1);
        modeArg = _valueAt(args, 2);
        usageArg = _valueAt(args, 3);
      } else {
        // Form: newMesh(vertices, mode, usage)
        verticesOrCount = first;
        modeArg = _valueAt(args, 1);
        usageArg = _valueAt(args, 2);
      }
    } else {
      // Form: newMesh(vertexcount, mode, usage)
      verticesOrCount = first;
      modeArg = _valueAt(args, 1);
      usageArg = _valueAt(args, 2);
    }

    final drawMode = _meshDrawMode(modeArg, symbol);
    final usage = _meshUsage(usageArg, symbol);

    final verticesTable = _tableIfPresent(verticesOrCount);
    if (verticesTable != null) {
      final vertices = vertexFormat != null
          ? _meshVerticesFromTableWithFormat(
              verticesTable,
              vertexFormat,
              symbol,
            )
          : _meshVerticesFromTable(verticesTable, symbol);
      return _wrapMesh(
        context,
        LoveMesh(
          vertices: vertices,
          drawMode: drawMode,
          usage: usage,
          vertexFormat: vertexFormat,
        ),
      );
    }

    final vertexCountValue = _numberIfPresent(verticesOrCount);
    if (vertexCountValue == null) {
      throw LuaError('$symbol expected a table or number at argument 1');
    }

    final vertexCount = vertexCountValue.round();
    if (vertexCount <= 0) {
      throw LuaError('$symbol expected a positive vertex count');
    }

    return _wrapMesh(
      context,
      LoveMesh(
        vertices: List<LoveMeshVertex>.filled(
          vertexCount,
          const LoveMeshVertex(x: 0, y: 0),
          growable: false,
        ),
        drawMode: drawMode,
        usage: usage,
        vertexFormat: vertexFormat,
      ),
    );
  };
}

// ---------------------------------------------------------------------------
// Mesh:setVertices helper (kept for backward compat with wrapper above)
// ---------------------------------------------------------------------------

LoveApiImplementation _bindMeshSetVertices(LibraryRegistrationContext context) {
  return (args) {
    final mesh = _requireMesh(args, 0, 'Mesh:setVertices');
    mesh.setVertices(
      _meshVerticesFromTableWithFormat(
        _requireLuaTable(args, 1, 'Mesh:setVertices'),
        mesh.vertexFormat,
        'Mesh:setVertices',
      ),
      startVertex: args.length >= 3
          ? _requireRoundedInt(args, 2, 'Mesh:setVertices')
          : 1,
      count: args.length >= 4
          ? _requireRoundedInt(args, 3, 'Mesh:setVertices')
          : null,
    );
    return null;
  };
}

// ---------------------------------------------------------------------------
// Draw-mode / usage helpers
// ---------------------------------------------------------------------------

LoveMeshDrawMode _meshDrawMode(Object? value, String symbol) {
  final raw = _stringLike(value);
  if (raw == null) {
    return LoveMeshDrawMode.fan;
  }

  return switch (raw) {
    'fan' => LoveMeshDrawMode.fan,
    'strip' => LoveMeshDrawMode.strip,
    'triangles' => LoveMeshDrawMode.triangles,
    'points' => LoveMeshDrawMode.points,
    _ => throw LuaError('$symbol invalid mesh draw mode "$raw"'),
  };
}

LoveMeshUsage _meshUsage(Object? value, String symbol) {
  final raw = _stringLike(value);
  if (raw == null) {
    return LoveMeshUsage.dynamicUsage;
  }

  return switch (raw) {
    'dynamic' => LoveMeshUsage.dynamicUsage,
    'static' => LoveMeshUsage.staticUsage,
    'stream' => LoveMeshUsage.stream,
    _ => throw LuaError('$symbol invalid mesh usage "$raw"'),
  };
}

// ---------------------------------------------------------------------------
// Vertex format parsing
// ---------------------------------------------------------------------------

/// Valid LOVE vertex data types.
const Set<String> _validMeshDataTypes = <String>{
  'float',
  'float32',
  'float16',
  'byte',
  'unorm8',
  'snorm8',
  'int8',
  'uint8',
  'unorm16',
  'snorm16',
  'int16',
  'uint16',
  'int32',
  'uint32',
};

/// Parses a Lua vertex-format table of the form:
///   { {"VertexPosition","float",2}, {"VertexTexCoord","float",2}, ... }
List<LoveMeshAttributeFormat> _parseMeshFormat(
  Map<dynamic, dynamic> table,
  String symbol,
) {
  final format = <LoveMeshAttributeFormat>[];

  for (var i = 1; ; i++) {
    final entry = _tableIndexedEntry(table, i);
    if (entry == null) break;

    final entryTable = _tableIfPresent(entry);
    if (entryTable == null) {
      throw LuaError(
        '$symbol vertex format entry $i must be a table '
        '{attributeName, dataType, components}',
      );
    }

    final name = _stringLike(_tableIndexedEntry(entryTable, 1));
    if (name == null) {
      throw LuaError(
        '$symbol vertex format entry $i: first element must be an '
        'attribute name string',
      );
    }

    final dataType = _stringLike(_tableIndexedEntry(entryTable, 2));
    if (dataType == null) {
      throw LuaError(
        '$symbol vertex format entry $i ("$name"): second element must be a '
        'data type string',
      );
    }
    if (!_validMeshDataTypes.contains(dataType)) {
      throw LuaError(
        '$symbol vertex format entry $i ("$name"): unknown data type '
        '"$dataType"',
      );
    }

    final componentsRaw = _tableIndexedEntry(entryTable, 3);
    final components = componentsRaw == null
        ? null
        : (_rawValue(componentsRaw) is num
              ? (_rawValue(componentsRaw) as num).round()
              : null);
    if (components == null) {
      throw LuaError(
        '$symbol vertex format entry $i ("$name"): third element must be a '
        'component count (1–4)',
      );
    }
    if (components < 1 || components > 4) {
      throw LuaError(
        '$symbol vertex format entry $i ("$name"): component count '
        '$components is out of range [1, 4]',
      );
    }

    format.add(
      LoveMeshAttributeFormat(
        name: name,
        dataType: dataType,
        components: components,
      ),
    );
  }

  if (format.isEmpty) {
    throw LuaError('$symbol vertex format must have at least one attribute');
  }

  return format;
}

// ---------------------------------------------------------------------------
// Vertex table parsing
// ---------------------------------------------------------------------------

/// Parses a vertices table using [format] to map components to the standard
/// [LoveMeshVertex] fields (position, texcoord, color).
///
/// Each vertex sub-table must contain one number per component across all
/// attributes in [format] order.
List<LoveMeshVertex> _meshVerticesFromTableWithFormat(
  Map<dynamic, dynamic> table,
  List<LoveMeshAttributeFormat> format,
  String symbol,
) {
  // Resolve the component offset (0-based) for each well-known attribute.
  int? posOffset;
  int? texOffset;
  int? colorOffset;
  int colorComponents = 0;
  String colorDataType = 'float';

  var componentIndex = 0;
  for (var i = 0; i < format.length; i++) {
    final attr = format[i];
    final nameLower = attr.name.toLowerCase();

    if (posOffset == null &&
        (nameLower == 'vertexposition' || nameLower == 'position') &&
        attr.components >= 2) {
      posOffset = componentIndex;
    } else if (texOffset == null &&
        (nameLower == 'vertextexcoord' || nameLower == 'texcoord') &&
        attr.components >= 2) {
      texOffset = componentIndex;
    } else if (colorOffset == null &&
        (nameLower == 'vertexcolor' || nameLower == 'color') &&
        attr.components >= 3) {
      colorOffset = componentIndex;
      colorComponents = attr.components;
      colorDataType = attr.dataType;
    }

    componentIndex += attr.components;
  }

  final vertices = <LoveMeshVertex>[];

  for (var index = 1; ; index++) {
    final entry = _tableIndexedEntry(table, index);
    if (entry == null) break;

    final vertexTable = _tableIfPresent(entry);
    if (vertexTable == null) {
      throw LuaError('$symbol expected a table of vertex tables');
    }

    // Helper: read a number from a 1-based position in the vertex table.
    double getComp(int offset, double defaultVal) => _tableIndexedNumber(
      vertexTable,
      offset + 1,
      symbol,
      defaultValue: defaultVal,
    );

    final x = posOffset != null ? getComp(posOffset, 0) : 0.0;
    final y = posOffset != null ? getComp(posOffset + 1, 0) : 0.0;
    final u = texOffset != null ? getComp(texOffset, 0) : 0.0;
    final v = texOffset != null ? getComp(texOffset + 1, 0) : 0.0;

    final LoveColor color;
    if (colorOffset != null) {
      final def = 1.0;
      final cr = getComp(colorOffset, def);
      final cg = getComp(colorOffset + 1, def);
      final cb = getComp(colorOffset + 2, def);
      final ca = colorComponents >= 4 ? getComp(colorOffset + 3, def) : 1.0;
      color = LoveColor(cr, cg, cb, ca).clamped();
    } else {
      color = LoveColor.white;
    }

    vertices.add(LoveMeshVertex(x: x, y: y, u: u, v: v, color: color));
  }

  return List<LoveMeshVertex>.unmodifiable(vertices);
}

/// Parses a vertices table using the default LOVE vertex format:
///   {x, y, u, v, r, g, b, a}  (r/g/b/a use LOVE 11.x normalized 0..1 color
///   components even though the stored vertex format is byte-backed).
List<LoveMeshVertex> _meshVerticesFromTable(
  Map<dynamic, dynamic> table,
  String symbol,
) {
  return _meshVerticesFromTableWithFormat(table, defaultVertexFormat, symbol);
}

/// Parses a single vertex from a flat component list (used by Mesh:setVertex).
LoveMeshVertex _meshVertexFromComponents(
  List<Object?> components,
  List<LoveMeshAttributeFormat> format,
  String symbol,
) {
  // Build a fake 1-indexed table from the component list and reuse the
  // table-based parser.
  final fakeTable = <Object?, Object?>{};
  for (var i = 0; i < components.length; i++) {
    fakeTable[i + 1] = components[i];
  }

  // Wrap in an outer table so _meshVerticesFromTableWithFormat sees one vertex.
  final outerTable = <Object?, Object?>{1: Value(fakeTable)};
  final result = _meshVerticesFromTableWithFormat(outerTable, format, symbol);
  return result.isEmpty ? const LoveMeshVertex(x: 0, y: 0) : result.first;
}

Map<dynamic, dynamic> _requireLuaTable(
  List<Object?> args,
  int index,
  String symbol,
) {
  final table = _tableIfPresent(_valueAt(args, index));
  if (table != null) {
    return table;
  }

  throw LuaError('$symbol expected a table at argument ${index + 1}');
}
