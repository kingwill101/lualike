/// Documentation metadata and renderers for lualike libraries.
///
/// Registered libraries can be rendered as a complete HTML reference, a JSON
/// manifest for editor tooling, or LuaLS annotation stubs. Start with
/// [documentedLibrariesForRuntime], then pass its result to [renderDocsPage],
/// [renderDocsJson], or [renderLuaLsAnnotations].
///
/// ```dart
/// final libraries = documentedLibrariesForRuntime(lua.vm);
/// final json = renderDocsJson(libraries, packageName: 'my_runtime');
/// ```
library;

export 'src/docs/metadata_format.dart';
export 'src/docs/renderer.dart';
export 'src/stdlib/doc.dart'
    show
        AccessScope,
        AliasDescriptor,
        AliasDoc,
        AliasVariant,
        ConstantDescriptor,
        DocDescriptor,
        DocParam,
        EnumDescriptor,
        EnumDoc,
        FieldDoc,
        FunctionDescriptor,
        FunctionDoc,
        GenericParam,
        OperatorDoc,
        OverloadDoc,
        TableDescriptor,
        TableDoc,
        ValueDoc;
