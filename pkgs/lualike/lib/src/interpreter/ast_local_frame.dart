import 'package:lualike/src/ast.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/lua_error.dart';

/// Conservatively returns outer-binding names that a nested function may use.
///
/// Every identifier below a nested function boundary is included, even when
/// it is declared by that nested function. Those false positives only retain
/// a Box for an otherwise eligible outer binding; they cannot incorrectly
/// move a captured binding into a direct slot. This intentionally favors
/// closure correctness over maximum slot coverage during the migration.
Set<String> potentiallyCapturedAstNames(List<AstNode> statements) {
  final names = <String>{};

  void visit(Object? value, {required bool insideNestedFunction}) {
    switch (value) {
      case final Map<Object?, Object?> node:
        final type = node['type'];
        final nested =
            insideNestedFunction ||
            type == 'FunctionDef' ||
            type == 'LocalFunctionDef' ||
            type == 'FunctionLiteral' ||
            type == 'FunctionBody';
        if (nested && type == 'Identifier') {
          final name = node['name'];
          if (name is String) {
            names.add(name);
          }
        }
        for (final entry in node.entries) {
          if (entry.key != 'span') {
            visit(entry.value, insideNestedFunction: nested);
          }
        }
      case final Iterable<Object?> values:
        for (final value in values) {
          visit(value, insideNestedFunction: insideNestedFunction);
        }
    }
  }

  for (final statement in statements) {
    if (statement is Dumpable) {
      visit((statement as Dumpable).dump(), insideNestedFunction: false);
    }
  }
  return names;
}

/// Immutable-across-calls slot assignment for one AST function body.
///
/// Parameter slots are known when the function is created. Local declaration
/// slots are assigned once, on their first execution, and then reused by every
/// invocation of the same function body. The declaration node identity keeps
/// shadowed names in distinct slots.
final class AstLocalLayout {
  AstLocalLayout({
    required List<String> parameterNames,
    required bool hasVarargs,
    String? namedVararg,
  }) : _parameterSlots = <String, int>{
         for (var index = 0; index < parameterNames.length; index++)
           parameterNames[index]: index,
       },
       _nextSlot = parameterNames.length {
    if (hasVarargs) {
      _syntheticSlots['...'] = _nextSlot++;
    }
    if (namedVararg != null) {
      _syntheticSlots[namedVararg] = _nextSlot++;
    }
    _firstDeclarationSlot = _nextSlot;
  }

  final Map<String, int> _parameterSlots;
  final Map<String, int> _syntheticSlots = <String, int>{};
  final Map<LocalDeclaration, List<int>> _declarationSlots =
      Map<LocalDeclaration, List<int>>.identity();
  final Set<LocalDeclaration> _slotOnlyDeclarations =
      Set<LocalDeclaration>.identity();
  late final int _firstDeclarationSlot;
  int _nextSlot;

  int get slotCount => _nextSlot;

  int get firstDeclarationSlot => _firstDeclarationSlot;

  int parameterSlot(String name) => _parameterSlots[name]!;

  int syntheticSlot(String name) => _syntheticSlots[name]!;

  void enableSlotOnlyDeclarations(Iterable<LocalDeclaration> declarations) {
    _slotOnlyDeclarations.addAll(declarations);
  }

  bool isSlotOnlyDeclaration(LocalDeclaration declaration) =>
      _slotOnlyDeclarations.contains(declaration);

  int declarationSlot(LocalDeclaration declaration, int nameIndex) {
    final existing = _declarationSlots[declaration];
    if (existing != null) {
      return existing[nameIndex];
    }
    final slots = List<int>.generate(
      declaration.names.length,
      (_) => _nextSlot++,
      growable: false,
    );
    _declarationSlots[declaration] = slots;
    return slots[nameIndex];
  }
}

/// Indexed local-binding view used by the AST compatibility engine.
///
/// During migration most slots still point at the authoritative [Box] objects
/// owned by lexical [Environment]s. Proven closure-free, call-free parameters
/// may instead live directly in [_slotValues]. A slot with a box always reads
/// the box as its source of truth; the parallel raw value is authoritative only
/// when no box exists. This keeps binding identity, close handling, debug
/// mutation, and upvalues unchanged while direct-slot coverage grows.
final class AstLocalFrame {
  AstLocalFrame(this.layout)
    : _boxes = List<Box<dynamic>?>.filled(
        layout.slotCount,
        null,
        growable: true,
      ),
      _slotValues = List<Object?>.filled(
        layout.slotCount,
        null,
        growable: true,
      ),
      _slotNames = List<String?>.filled(layout.slotCount, null, growable: true),
      _slotOwners = List<Environment?>.filled(
        layout.slotCount,
        null,
        growable: true,
      );

  static const bool diagnosticsEnabled = bool.fromEnvironment(
    'LUALIKE_BINDING_DIAGNOSTICS',
    defaultValue: false,
  );

  static const bool indexedLookupEnabled = bool.fromEnvironment(
    'LUALIKE_AST_INDEXED_LOCAL_FRAME',
    defaultValue: true,
  );

  /// Stores closure-free parameters directly in frame slots.
  ///
  /// Their Environment/Box facade is omitted only for call-free leaf bodies:
  /// no nested function can capture them and no asynchronous call boundary can
  /// resume under a different ambient AST frame. Debug APIs observe the same
  /// live slots through the owning CallFrame's engine state.
  static const bool slotOnlyParametersEnabled = bool.fromEnvironment(
    'LUALIKE_AST_SLOT_ONLY_PARAMETERS',
    defaultValue: true,
  );

  /// Stores eligible leaf-function locals directly in lexical frame slots.
  static const bool slotOnlyLocalsEnabled = bool.fromEnvironment(
    'LUALIKE_AST_SLOT_ONLY_LOCALS',
    defaultValue: true,
  );

  /// Stores uncaptured identity-bearing locals directly in frame slots.
  ///
  /// Tables, strings, functions, and userdata retain their canonical Value
  /// facade in the slot. The call frame exposes these values as custom-GC
  /// roots, while captured and attributed bindings remain Box-backed.
  static const bool slotOnlyIdentityLocalsEnabled = bool.fromEnvironment(
    'LUALIKE_AST_SLOT_ONLY_IDENTITY_LOCALS',
    defaultValue: true,
  );

  /// Extends direct local slots into nested lexical block declarations.
  ///
  /// Disabling this keeps the retained top-level-local path active and is the
  /// attribution baseline for nested block, branch, and loop-body slots.
  static const bool slotOnlyNestedLocalsEnabled = bool.fromEnvironment(
    'LUALIKE_AST_SLOT_ONLY_NESTED_LOCALS',
    defaultValue: true,
  );

  /// Keeps direct frame slots active while a closure-free function makes calls.
  ///
  /// Logical [CallFrame]s own their engine frame state, and nested calls,
  /// tail-call rebinding, and coroutine suspension preserve that state. This
  /// switch is kept separate from the leaf-function controls so the expanded
  /// continuation boundary has a precise A/B and emergency rollback.
  static const bool slotOnlyCallCapableFramesEnabled = bool.fromEnvironment(
    'LUALIKE_AST_SLOT_ONLY_CALL_CAPABLE_FRAMES',
    defaultValue: true,
  );

  /// Stores bindings that no nested closure can reference in direct slots.
  ///
  /// Potential captures remain Box-backed. Set the compile-time flag to false
  /// to restore the previous all-boxed boundary for closure-capable functions.
  static const bool slotOnlyUncapturedClosureBindingsEnabled =
      bool.fromEnvironment(
        'LUALIKE_AST_SLOT_ONLY_UNCAPTURED_CLOSURE_BINDINGS',
        defaultValue: true,
      );

  static int _diagnosticCreated = 0;
  static int _diagnosticReused = 0;
  static int _diagnosticCacheHits = 0;
  static int _diagnosticNameLookups = 0;
  static int _diagnosticSlotOnlyParameterBinds = 0;
  static int _diagnosticSlotOnlyLocalBinds = 0;
  static int _diagnosticSlotOnlyIdentityLocalBinds = 0;
  static int _diagnosticSlotWrites = 0;
  static int _diagnosticSlotOnlyWrites = 0;

  static void resetDiagnostics() {
    if (!diagnosticsEnabled) return;
    _diagnosticCreated = 0;
    _diagnosticReused = 0;
    _diagnosticCacheHits = 0;
    _diagnosticNameLookups = 0;
    _diagnosticSlotOnlyParameterBinds = 0;
    _diagnosticSlotOnlyLocalBinds = 0;
    _diagnosticSlotOnlyIdentityLocalBinds = 0;
    _diagnosticSlotWrites = 0;
    _diagnosticSlotOnlyWrites = 0;
  }

  static Map<String, Object> diagnostics() => <String, Object>{
    'enabled': diagnosticsEnabled,
    'created': _diagnosticCreated,
    'reused': _diagnosticReused,
    'cacheHits': _diagnosticCacheHits,
    'nameLookups': _diagnosticNameLookups,
    'slotOnlyParameterBinds': _diagnosticSlotOnlyParameterBinds,
    'slotOnlyLocalBinds': _diagnosticSlotOnlyLocalBinds,
    'slotOnlyIdentityLocalBinds': _diagnosticSlotOnlyIdentityLocalBinds,
    'slotOnlyIdentityLocalsEnabled': slotOnlyIdentityLocalsEnabled,
    'slotWrites': _diagnosticSlotWrites,
    'slotOnlyWrites': _diagnosticSlotOnlyWrites,
  };

  final AstLocalLayout layout;
  final List<Box<dynamic>?> _boxes;
  final List<Object?> _slotValues;
  final List<String?> _slotNames;
  final List<Environment?> _slotOwners;
  final Map<String, int> _activeNameSlots = <String, int>{};
  final Map<String, List<int>> _nameSlots = <String, List<int>>{};
  final Map<String, Box<dynamic>> _legacyActiveBoxes = <String, Box<dynamic>>{};
  final Map<Box<dynamic>, int> _boxSlots = Map<Box<dynamic>, int>.identity();

  void beginCall({required bool reused}) {
    if (diagnosticsEnabled) {
      if (reused) {
        _diagnosticReused++;
      } else {
        _diagnosticCreated++;
      }
    }
    _activeNameSlots.clear();
    _nameSlots.clear();
    _legacyActiveBoxes.clear();
    _boxSlots.clear();
    for (var index = 0; index < _boxes.length; index++) {
      _boxes[index] = null;
      _slotValues[index] = null;
      _slotNames[index] = null;
      _slotOwners[index] = null;
    }
  }

  void bindParameter(String name, Box<dynamic> box, Environment owner) {
    _bindBox(layout.parameterSlot(name), name, box, owner);
  }

  void bindParameterSlot(String name, Object? value, Environment owner) {
    if (diagnosticsEnabled) {
      _diagnosticSlotOnlyParameterBinds++;
    }
    _bind(layout.parameterSlot(name), name, value, null, owner);
  }

  void bindSynthetic(String name, Box<dynamic> box, Environment owner) {
    _bindBox(layout.syntheticSlot(name), name, box, owner);
  }

  void bindDeclaration(
    LocalDeclaration declaration,
    int nameIndex,
    String name,
    Box<dynamic> box,
    Environment owner,
  ) {
    _bindBox(layout.declarationSlot(declaration, nameIndex), name, box, owner);
  }

  bool canBindDeclarationSlot(LocalDeclaration declaration) =>
      layout.isSlotOnlyDeclaration(declaration);

  void bindDeclarationSlot(
    LocalDeclaration declaration,
    int nameIndex,
    String name,
    Object? value,
    Environment owner, {
    bool identityBearing = false,
  }) {
    if (diagnosticsEnabled) {
      _diagnosticSlotOnlyLocalBinds++;
      if (identityBearing) {
        _diagnosticSlotOnlyIdentityLocalBinds++;
      }
    }
    _bind(
      layout.declarationSlot(declaration, nameIndex),
      name,
      value,
      null,
      owner,
    );
  }

  void _bindBox(int slot, String name, Box<dynamic> box, Environment owner) {
    _bind(slot, name, box.value, box, owner);
  }

  void _bind(
    int slot,
    String name,
    Object? value,
    Box<dynamic>? box,
    Environment owner,
  ) {
    while (_boxes.length <= slot) {
      _boxes.add(null);
      _slotValues.add(null);
      _slotNames.add(null);
      _slotOwners.add(null);
    }
    _boxes[slot] = box;
    _slotValues[slot] = value;
    _slotNames[slot] = name;
    _slotOwners[slot] = owner;
    _activeNameSlots[name] = slot;
    final slots = _nameSlots.putIfAbsent(name, () => <int>[]);
    if (!slots.contains(slot)) {
      slots.add(slot);
    }
    if (!indexedLookupEnabled && box != null) {
      _legacyActiveBoxes[name] = box;
    }
    if (box != null) {
      _boxSlots[box] = slot;
    }
  }

  bool _slotIsVisible(int slot, Environment activeEnvironment) {
    final owner = _slotOwners[slot];
    Environment? current = activeEnvironment;
    while (current != null) {
      if (identical(current, owner)) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  int cachedSlot(Identifier identifier, Environment activeEnvironment) {
    if (!indexedLookupEnabled) {
      return -1;
    }
    if (!identical(identifier.runtimeLocalLayoutCache, layout)) {
      return -1;
    }
    final slot = identifier.runtimeLocalSlotCache;
    if (slot < 0 ||
        slot >= _boxes.length ||
        _slotNames[slot] == null ||
        !_slotIsVisible(slot, activeEnvironment)) {
      return -1;
    }
    if (diagnosticsEnabled) {
      _diagnosticCacheHits++;
    }
    return slot;
  }

  int lookupAndCacheSlot(Identifier identifier, Environment activeEnvironment) {
    if (diagnosticsEnabled) {
      _diagnosticNameLookups++;
    }
    if (!indexedLookupEnabled) {
      return -1;
    }
    final candidates = _nameSlots[identifier.name];
    if (candidates == null) {
      return -1;
    }
    var slot = -1;
    for (final candidate in candidates.reversed) {
      if (candidate < _boxes.length &&
          _slotNames[candidate] != null &&
          _slotIsVisible(candidate, activeEnvironment)) {
        slot = candidate;
        break;
      }
    }
    if (slot < 0) return -1;
    identifier.runtimeLocalLayoutCache = layout;
    identifier.runtimeLocalSlotCache = slot;
    return slot;
  }

  Object? readSlot(int slot) {
    final box = _boxes[slot];
    if (box != null) {
      return box.value;
    }
    return _slotValues[slot];
  }

  void writeSlot(int slot, Object? value) {
    final box = _boxes[slot];
    if (diagnosticsEnabled) {
      _diagnosticSlotWrites++;
      if (box == null) {
        _diagnosticSlotOnlyWrites++;
      }
    }
    if (box != null) {
      if (box.preventsAssignment) {
        final name = _slotNames[slot] ?? box.debugName ?? 'local';
        throw LuaError("attempt to assign to const variable '$name'");
      }
      box.value = value;
    }
    _slotValues[slot] = value;
  }

  Box<dynamic>? boxAt(int slot) => _boxes[slot];

  int _visibleNameSlot(String name, Environment? activeEnvironment) {
    if (activeEnvironment == null) {
      return _activeNameSlots[name] ?? -1;
    }
    final candidates = _nameSlots[name];
    if (candidates == null) return -1;
    for (final candidate in candidates.reversed) {
      if (_slotIsVisible(candidate, activeEnvironment)) {
        return candidate;
      }
    }
    return -1;
  }

  bool containsName(String name, [Environment? activeEnvironment]) =>
      _visibleNameSlot(name, activeEnvironment) >= 0;

  Object? readName(String name, [Environment? activeEnvironment]) {
    final slot = _visibleNameSlot(name, activeEnvironment);
    return slot < 0 ? null : readSlot(slot);
  }

  bool writeName(String name, Object? value, [Environment? activeEnvironment]) {
    final slot = _visibleNameSlot(name, activeEnvironment);
    if (slot < 0) {
      return false;
    }
    writeSlot(slot, value);
    return true;
  }

  /// Slot-only bindings for debugger enumeration and custom-GC rooting.
  Iterable<({String name, Object? value})> get slotOnlyBindings sync* {
    for (var slot = 0; slot < _slotNames.length; slot++) {
      final name = _slotNames[slot];
      if (name != null && _boxes[slot] == null) {
        yield (name: name, value: _slotValues[slot]);
      }
    }
  }

  Iterable<Object?> get slotOnlyGcRoots sync* {
    for (var slot = 0; slot < _slotValues.length; slot++) {
      if (_slotNames[slot] != null && _boxes[slot] == null) {
        yield _slotValues[slot];
      }
    }
  }

  /// Live local declarations in their stable frame-slot order.
  ///
  /// Parameters and synthetic vararg slots are deliberately excluded because
  /// call frames expose those separately. Both Box-backed and direct bindings
  /// are returned so debugger enumeration does not reorder mixed storage.
  Iterable<({String name, Object? value})> visibleDeclarationBindings(
    Environment activeEnvironment,
  ) sync* {
    for (
      var slot = layout.firstDeclarationSlot;
      slot < _slotNames.length;
      slot++
    ) {
      final name = _slotNames[slot];
      if (name != null && _slotIsVisible(slot, activeEnvironment)) {
        yield (name: name, value: readSlot(slot));
      }
    }
  }

  void cacheResolvedBox(Identifier identifier, Box<dynamic> box) {
    if (!indexedLookupEnabled) {
      return;
    }
    final slot = _boxSlots[box];
    if (slot == null) {
      return;
    }
    identifier.runtimeLocalLayoutCache = layout;
    identifier.runtimeLocalSlotCache = slot;
  }
}
