/// Build- Runner builder configuration for lualike doc generators.
library;

import 'package:build/build.dart';

import 'src/build/table_schema_builder.dart';

/// Builder that generates [TableDoc] constants from `@TableSchema`-annotated
/// classes.
Builder tableSchemaBuilder(BuilderOptions options) => TableSchemaBuilder();
