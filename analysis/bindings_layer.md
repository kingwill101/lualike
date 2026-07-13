LOVE2D Lua binding layer — mechanical-port smell review

Scope: /run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/love2d/lib/src/runtime/love_api_bindings.dart + love_api_bindings/, with samples from graphics, audio, physics, font, filesystem. Wrapper identity caching via Expando is real and good; the main costs are per-instance method tables, repeated receiver/arg coercion on every call, hot-path type probing, and duplicated helper stacks.

───

Executive summary

┌─────────────────────────────────────┬──────────┬───────────────────┐
│ Area                                │ Severity │ Cost nature       │
├─────────────────────────────────────┼──────────┼───────────────────┤
│ Per-object method tables (no shared │ High     │ Construction +    │
│ prototype)                          │          │ memory            │
├─────────────────────────────────────┼──────────┼───────────────────┤
│ Full receiver unwrap/_requireX on   │ High     │ Per-call          │
│ every method                        │          │                   │
├─────────────────────────────────────┼──────────┼───────────────────┤
│ love.graphics.draw sequential       │ High     │ Hot path          │
│ drawable probes                     │          │                   │
├─────────────────────────────────────┼──────────┼───────────────────┤
│ Dual Source impls (wrapper table vs │ Medium   │ Maintenance +     │
│ loveApiBindingFactories)            │          │ dead weight       │
├─────────────────────────────────────┼──────────┼───────────────────┤
│ Parallel filesystem value helpers   │ Medium   │ Duplication /     │
│                                     │          │ drift             │
├─────────────────────────────────────┼──────────┼───────────────────┤
│ bindLoveApiFunction extra closure   │ Medium   │ Per-module-call   │
│ wrap                                │          │ indirection       │
├─────────────────────────────────────┼──────────┼───────────────────┤
│ Graphics command state snapshotting │ Medium   │ Hot path (host+   │
│                                     │          │ binding)          │
├─────────────────────────────────────┼──────────┼───────────────────┤
│ release/type/typeOf boilerplate     │ Medium   │ Code size +       │
│                                     │          │ construction      │
├─────────────────────────────────────┼──────────┼───────────────────┤
│ _tableIndexedEntry linear fallback  │ Low–     │ Some table walks  │
│                                     │ Medium   │                   │
├─────────────────────────────────────┼──────────┼───────────────────┤
│ Error formatting on happy path      │ Low      │ Mostly error-only │
│                                     │          │ (OK)              │
├─────────────────────────────────────┼──────────┼───────────────────┤
│ Primitive Value wrapping on returns │ Low      │ Interpreter may   │
│                                     │          │ wrap later        │
└─────────────────────────────────────┴──────────┴───────────────────┘

───

1. Per-instance full method tables (High)

Evidence
Every _wrap* builds a new ValueClass.table({ ... many methods ... }) with one BuiltinFunction + Value per method, then caches the whole table on the host object:

Value _wrapFont(LibraryRegistrationContext context, LoveFont font) {
  final cached = _loveFontWrapperCache[font];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  const hierarchy = <String>{'Font', 'Object'};
  final table = ValueClass.table(<Object?, Object?>{
    _loveFontObjectKey: font,
    'getAscent': Value(
      builder.create((args) => _requireFont(args, 0, 'Font:getAscent').ascent),

Same pattern for Image/Canvas/Text (object_wrappers.dart), Source (audio_object_wrappers.dart ~87–100+), Mesh (graphics_mesh_bindings.dart ~41–70), ParticleSystem (particle_system_object_wrappers.dart ~35–75), Physics World (physics_object_wrappers.dart ~427–450), SpriteBatch, Video, Cursor, etc.

There is no __index / shared method metatable usage in wrapper files.

ValueClass.table is thin (Value(map) only) — cost is N× builder.create + N× Value(...) + large map, not the helper itself:

  static Value table([dynamic initial]) {
    // ...
    return Value(table);
  }

Why it smells mechanical
C/Lua LOVE typically uses shared type method tables (or userdata metatables). This port copies the method surface onto each instance.

Impact
• Construction: first wrap of a fat type (Source, ParticleSystem, Mesh, World) allocates tens of closures/BuiltinFunctions.
• Memory: scales ≈ objects × methods, not types × methods.
• Expando caches (_loveFontWrapperCache, etc. in love_api_bindings.dart ~187–274) avoid rebuild on every re-wrap, but not the per-object bloat.

Refactor
1. Build one method map / metatable per type at install time.
2. Instance table holds only: object key, maybe release flag, hierarchy metadata.
3. Set metatable = { __index = sharedMethods } (or lualike equivalent).
4. Keep Expando only for identity of the thin instance table.
5. _wrapLoveDataObject / _physicsObjectEntries / _textureEntries are partial steps — finish that pattern for Font/Source/Image/etc.

───

2. Receiver coercion tax on every method call (High)

Evidence
Canonical path:

Object? _valueAt(List<Object?> args, int index) {
  return index < args.length ? args[index] : null;
}

Object? _rawValue(Object? value) {
  if (value is Value) {
    return value.unwrap();
  }
  // ...
}

double _requireNumber(List<Object?> args, int index, String symbol) {
  final raw = _rawValue(_valueAt(args, index));
  if (raw is num) {
    return raw.toDouble();
  }
  throw LuaError('$symbol expected a number at argument ${index + 1}');
}

Object extractors repeat the same stack: _rawValue → map cast → private key → Expando released check:

LoveFont _requireFont(List<Object?> args, int index, String symbol) {
  final value = _valueAt(args, index);
  final font = _fontIfPresent(value);
  if (font != null) {
    if (_loveFontReleased[font] == true) {
      _throwReleasedObjectError();
    }
    return font;
  }
  _throwLuaStyleTypeError(/* ... */);
}

Even trivial getters pay full price:

    'getHeight': Value(
      builder.create((args) => _requireFont(args, 0, 'Font:getHeight').height),

Audio/physics add extra layers (_audioSourceWrapperReleased + _audioSourceIfPresent, _requirePhysicsTypedObject hierarchy set checks).

Impact
For font:getHeight() roughly: index, unwrap Value, map lookup, Expando, field read. Fine once; death by thousands of graphics/audio/physics calls per frame.

Refactor
1. Trusted receiver path: methods installed on the table can read args[0] as Value and table[_key] with a single cast (type-check only in debug/assert builds if needed).
2. Or store host pointer in a userdata/Box so methods avoid map key string lookup.
3. Fast path: if (identical(args[0], selfTable)) return cachedHost;
4. Batch numeric args: one loop over indices instead of N× _requireNumber each doing _valueAt+_rawValue.

───

3. love.graphics.draw sequential type probing (High)

Evidence

  return (args) {
    if (_textDrawableIfPresent(_valueAt(args, 0)) case final LoveTextDrawable text) { ... }
    if (_meshIfPresent(_valueAt(args, 0)) case final LoveMesh mesh) { ... }
    if (_spriteBatchIfPresent(_valueAt(args, 0)) case final LoveSpriteBatch spriteBatch) { ... }
    if (_particleSystemIfPresent(_valueAt(args, 0)) case final LoveParticleSystem particleSystem) { ... }
    if (_videoIfPresent(_valueAt(args, 0)) case final LoveVideo video) { ... }
    final image = _requireImage(args, 0, 'love.graphics.draw');

Each *IfPresent re-unwraps the table and probes a different key. Images (common case) pay all failed probes first.

Refactor
1. Single unwrap of arg0 → map.
2. Dispatch on first matching private key, or a single __love2d_drawable_kind__ tag written at wrap time.
3. Or tag in Expando: Expando<LoveDrawableKind>.

───

4. Graphics command construction copies full state every call (Medium–High)

Evidence
Rectangle/circle/draw all repeatedly pack:

    runtime.graphics.addCommand(
      LoveRectangleCommand(
        color: runtime.graphics.color,
        lineWidth: runtime.graphics.lineWidth,
        // ... blend, scissor, shader ...
        transform: runtime.graphics.copyTransform(),

copyTransform() is a real Matrix4 copy (love_runtime.dart ~3506). Combined with ~6–8 number coercions per shape, draw is heavy.

Refactor
1. Snapshot graphics state once per frame/batch; commands hold a state id / shared snapshot.
2. Copy transform only when dirty.
3. Binding layer: parse numbers into a small struct / stack locals without re-wrapping.

───

5. Duplicate method implementations: object table vs factory registry (Medium)

Evidence
Source:play / Source:setLooping exist inline on the wrapper and as factories:

    'play': Value(
      builder.create((args) async {
        return await _requireAudioSource(args, 0, 'Source:play').play();
      }),

LoveApiImplementation _bindSourcePlay(...) {
  return (args) async {
    return await _requireAudioSource(args, 0, 'Source:play').play();
  };
}

Registered again in love_api_bindings.dart (~340–344). Some methods correctly reuse factories (getEffect via _bindSourceGetEffect); most do not.

Smell
Mechanical “register every wiki symbol as a factory” plus “build full method table on wrap” → two surfaces for one API.

Refactor
• One source of truth: either factories install into shared method tables, or wrappers own methods and factories only cover module-level APIs.
• Prefer: builder.create(_bindSourcePlay(context)) everywhere (already done for effects).

───

6. bindLoveApiFunction always wraps non-inlined APIs (Medium)

Evidence

  final builder = BuiltinFunctionBuilder(context);
  return Value(
    builder.create((args) => implementation(args)),
    functionName: publicName,
  );

Factories already return LoveApiImplementation. This adds another _BuiltinFunctionImpl + lambda. Hot graphics symbols avoid it via _bytecodeInlineLoveApiSymbols (~272+); most module APIs do not.

Refactor
Use _InlineableLoveApiBuiltin (or equivalent) for all factory-backed bindings, or make factories return BuiltinFunction directly.

───

7. Duplicate helper stacks: main bindings vs filesystem (Medium)

Evidence
Filesystem reimplements the same helpers in a separate library part:

Object? _valueAt(List<Object?> args, int index) { ... }
Object? _rawValue(Object? value) { ... }
String _requireString(...) { ... }
double _numberValue(...) { ... }

vs binding_helpers.dart _valueAt / _rawValue / _requireString / _requireNumber.

Also dual string semantics (_luaStringLike coerces numbers; main _stringLike does not) → subtle behavioral drift risk.

Refactor
Share one coercion module; keep filesystem-only rules as thin adapters.

───

8. release / type / typeOf boilerplate (Medium)

Evidence
Nearly every wrapper pastes the same ~40–60 lines. Physics centralizes well:

Map<Object?, Object?> _physicsObjectEntries<T>({ ... }) {
  return <Object?, Object?>{
    // release / type / typeOf
  };
}

Data types use _wrapLoveDataObject (data_object_wrappers.dart ~114–208). Font/Image/Text/Source/Mesh/Cursor still hand-roll.

Released-state bookkeeping is also dual in many types:
• Expando (_loveAudioSourceReleased)
• table marker key (_loveAudioSourceReleasedWrapperKey)
• sometimes nulling the object key

Refactor
Single _objectLifecycleEntries(typeName, hierarchy, objectKey, releasedExpando).
One released source of truth (prefer table flag or Expando, not both unless required for identity after nulling).

───

9. Args / multi-return allocations (Medium)

Evidence
• args.skip(1).toList(growable: false) in polygon (graphics_draw_bindings.dart ~167–169).
• args.sublist(...) in Canvas:renderTo (object_wrappers.dart ~981).
• Value.multi(<Object?>[...]) on common getters (getDimensions, color, gravity, etc.).
• _coordinateSequence builds a growable list of doubles, then another list of records (~1413–1478).
• _physicsArray builds a new map every list return (physics_object_wrappers.dart ~242–246).

Refactor
• Index-offset parsers (_coordinateSequenceFrom(args, start)).
• Reuse multi-return buffers where interpreter allows.
• For hot multi-returns, consider specialized multi-value returns without intermediate List growth if VM supports it.

───

10. Table index helpers: O(n) fallback (Low–Medium)

Evidence

Object? _tableIndexedEntry(Map<dynamic, dynamic> table, int index) {
  if (table.containsKey(index)) return table[index];
  final asDouble = index.toDouble();
  if (table.containsKey(asDouble)) return table[asDouble];
  for (final entry in table.entries) {
    final rawKey = _rawValue(entry.key);
    if (rawKey == index || rawKey == asDouble) return entry.value;
  }
  return null;
}

Used in color tables, coordinates, shaders, mesh vertices, etc. Happy path with int keys is fine; missing keys still pay full iteration.

_tableEntry string keys have the same linear scan pattern (~1312–1323).

Refactor
Assume dense int keys for LOVE array tables; only fall back on miss. Or normalize keys once when crossing the boundary.

───

11. Empty / thin middle layers (Medium, structural)

Patterns observed

┌───────────────────────────────────────┬────────────────────────────┐
│ Layer                                 │ Role often is…             │
├───────────────────────────────────────┼────────────────────────────┤
│ *_bindings.dart _bindX                │ Capture runtime, coerce    │
│                                       │ args, call host            │
├───────────────────────────────────────┼────────────────────────────┤
│ Support (love_audio_support.dart,     │ Real host model — good     │
│ physics support)                      │                            │
├───────────────────────────────────────┼────────────────────────────┤
│ Object wrappers                       │ Coerce again + call same   │
│                                       │ host fields                │
├───────────────────────────────────────┼────────────────────────────┤
│ LoveApiImplementation factories for   │ Duplicate of wrapper       │
│ methods                               │ methods                    │
└───────────────────────────────────────┴────────────────────────────┘

Good thinness (OK): many getters are literally require → field.
Smell: validation-only wrappers like _physicsWithLuaErrors around every mutator (physics_object_wrappers.dart ~7–20, used heavily in World methods) add try/catch frames on happy path.

Channel/Thread cache is Expando<Map<Object, Value>> keyed by context (thread_object_wrappers.dart ~129–131, love_api_bindings.dart ~247–250) — extra map hop justified only if multi-interpreter; otherwise over-designed.

Refactor
• Keep support as host logic; bindings as one coercion layer only.
• Collapse method factories into shared method tables.
• Use try/catch only at outer host boundary, not every property setter.

───

12. Async wrappers for simple methods (Low–Medium)

Evidence
Source:play / pause / setVolume / setLooping are async even when work is a single host future. That forces Future scheduling overhead on the Lua call path.

Refactor
Return FutureOr only when the host is actually async; avoid async keyword when body is return host.play();.

───

13. Error formatting on happy path (Low — mostly OK)

_throwLuaStyleTypeError builds strings only on failure (binding_helpers.dart ~466–475).
_requireNumber only interpolates on throw. Good.

Minor: symbol strings like 'Font:getHeight' are constants passed around (cheap). Avoid building dynamic messages on success (already mostly avoided).

───

14. Primitive wrapping (Low)

Most methods return raw num/bool/String and rely on the VM to wrap.
Data:getString correctly uses interpreter.constantStringValue (data_object_wrappers.dart ~149).
Value(null) for depth sample mode (object_wrappers.dart ~1725) is unnecessary allocation vs bare null.

BuiltinFunctionBuilder exists partly for primitiveValue caching (library.dart ~119–128), but love2d wrappers rarely use that path for returns.

───

15. Wrapper caching — what’s good vs incomplete

Good:
• Expando caches across nearly all types (love_api_bindings.dart ~187–274).
• Physics/audio re-validate cache isn’t a released stub.
• Data pointer cache (_loveDataPointerCache).

Incomplete / inconsistent:
• Some caches return cached blindly (_wrapFont); others re-check (_wrapAudioSource, _wrapParticleSystem).
• Released objects: mixed Expando-only (Font) vs Expando+table marker+null key (Source, physics).
• No shared method prototype, so cache still stores fat tables.

───

Priority refactor roadmap

P0 — hot path / memory
1. Shared method metatables for Font, Image, Canvas, Source, Mesh, Body, SpriteBatch, ParticleSystem.
2. Single-key drawable dispatch in love.graphics.draw.
3. Trusted receiver extract for methods on known tables.

P1 — structure / maintenance
4. Unify lifecycle entries (release/type/typeOf) like physics/data.
5. Eliminate duplicate Source factories vs wrapper methods.
6. Share filesystem coercion with binding_helpers.
7. Remove extra builder.create((args) => implementation(args)) wrap.

P2 — secondary costs
8. Graphics state snapshot sharing / dirty transform.
9. Avoid async when not needed; avoid args.skip().toList().
10. Harden _tableIndexedEntry for dense arrays.
11. Optional: tag tables with type enum for O(1) *IfPresent.

───

Representative “mechanical port” anti-patterns (checklist)

┌──────────────────────────┬──────────────────────────────┬──────────┐
│ Smell                    │ Where                        │ Severity │
├──────────────────────────┼──────────────────────────────┼──────────┤
│ Full method table per    │ All *_object_wrappers.dart,  │ High     │
│ instance                 │ Mesh, Font, Image            │          │
├──────────────────────────┼──────────────────────────────┼──────────┤
│ Require-X on self for    │ Universal                    │ High     │
│ every method             │                              │          │
├──────────────────────────┼──────────────────────────────┼──────────┤
│ Probe 5 drawable types   │ graphics_draw_bindings.      │ High     │
│ before Image             │ dart:322+                    │          │
├──────────────────────────┼──────────────────────────────┼──────────┤
│ Copy full gfx state +    │ graphics_draw_bindings.dart  │ Med–High │
│ Matrix4 per command      │                              │          │
├──────────────────────────┼──────────────────────────────┼──────────┤
│ Dual Source method       │ wrappers + audio_bindings    │ Medium   │
│ surfaces                 │ .dart + factory map          │          │
├──────────────────────────┼──────────────────────────────┼──────────┤
│ Duplicate _valueAt/_     │ binding_helpers vs           │ Medium   │
│ rawValue stacks          │ filesystem helpers           │          │
├──────────────────────────┼──────────────────────────────┼──────────┤
│ release/type/typeOf      │ Nearly every wrap            │ Medium   │
│ copy-paste               │                              │          │
├──────────────────────────┼──────────────────────────────┼──────────┤
│ Dual released            │ Source, physics, particle,   │ Medium   │
│ bookkeeping              │ video…                       │          │
├──────────────────────────┼──────────────────────────────┼──────────┤
│ try/catch on every       │ _physicsWithLuaErrors        │ Medium   │
│ physics setter           │                              │          │
├──────────────────────────┼──────────────────────────────┼──────────┤
│ Extra factory→           │ bindLoveApiFunction          │ Medium   │
│ BuiltinFunction hop      │                              │          │
├──────────────────────────┼──────────────────────────────┼──────────┤
│ Linear table key scan    │ _tableIndexedEntry / _       │ Low–Med  │
│                          │ tableEntry                   │          │
├──────────────────────────┼──────────────────────────────┼──────────┤
│ Value.multi / sublist    │ multi-returns, polygon,      │ Medium   │
│ allocs                   │ renderTo                     │          │
├──────────────────────────┼──────────────────────────────┼──────────┤
│ Error string on happy    │ Mostly absent (good)         │ Low      │
│ path                     │                              │          │
└──────────────────────────┴──────────────────────────────┴──────────┘

───

What’s already in good shape

• Expando identity caches prevent re-wrapping the same host object every call.
• _wrapLoveDataObject / _textureEntries / _physicsObjectEntries show the intended consolidation direction.
• Bytecode-inline allowlist for hot love.graphics.* symbols is the right idea; should expand and pair with thinner wrappers.
• Error helpers generally stay off the happy path.
• Support modules (audio/physics/font hosts) hold real logic; the binding layer’s problem is mechanical thickness, not missing architecture.

───

Bottom line: The binding layer is a faithful, table-shaped mechanical port of LOVE’s object surface. The biggest wins are share method tables, stop re-validating the receiver every call, and make drawable dispatch O(1) — those dominate both allocation at wrap time and per-frame call overhead.
