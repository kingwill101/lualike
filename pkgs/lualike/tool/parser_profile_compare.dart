import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('baseline', help: 'Baseline JSON from parser_profile.dart.')
    ..addOption('latest', help: 'Latest JSON from parser_profile.dart.')
    ..addOption(
      'title',
      help: 'Markdown report title.',
      defaultsTo: 'Parser Profile Comparison',
    )
    ..addOption('json-out', help: 'Write comparison data as JSON.')
    ..addOption('markdown-out', help: 'Write comparison as Markdown.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print usage.');

  final options = parser.parse(args);
  if (options.flag('help')) {
    stdout.writeln('Compare parser profile JSON snapshots.');
    stdout.writeln(parser.usage);
    return;
  }

  final baselinePath = options.option('baseline');
  final latestPath = options.option('latest');
  if (baselinePath == null || latestPath == null) {
    stderr.writeln('Both --baseline and --latest are required.');
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  final baseline = _readJsonFile(baselinePath);
  final latest = _readJsonFile(latestPath);
  final comparison = _compareSnapshots(
    title: options.option('title')!,
    baseline: baseline,
    latest: latest,
  );

  final jsonOut = options.option('json-out');
  if (jsonOut != null) {
    _writeTextFile(
      jsonOut,
      '${const JsonEncoder.withIndent('  ').convert(comparison.toJson())}\n',
    );
  }

  final markdown = comparison.toMarkdown();
  final markdownOut = options.option('markdown-out');
  if (markdownOut == null) {
    stdout.write(markdown);
  } else {
    _writeTextFile(markdownOut, markdown);
  }
}

Map<String, Object?> _readJsonFile(String filePath) {
  final decoded = jsonDecode(File(filePath).readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw FormatException('Expected JSON object in $filePath');
  }
  return decoded;
}

void _writeTextFile(String filePath, String contents) {
  final file = File(filePath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
  stdout.writeln('Wrote ${path.normalize(file.path)}');
}

_Comparison _compareSnapshots({
  required String title,
  required Map<String, Object?> baseline,
  required Map<String, Object?> latest,
}) {
  final baselineRows = _rowsByCase(baseline);
  final rows = <_ComparisonRow>[];

  for (final latestRow in _snapshotRows(latest)) {
    final caseName = latestRow['case'] as String;
    final baselineRow = baselineRows[caseName];
    if (baselineRow == null) {
      continue;
    }
    rows.add(
      _ComparisonRow(
        caseName: caseName,
        baselineMeanMicros: _number(baselineRow['meanMicros']),
        latestMeanMicros: _number(latestRow['meanMicros']),
      ),
    );
  }

  final baselineTotal = rows.fold<double>(
    0,
    (total, row) => total + row.baselineMeanMicros,
  );
  final latestTotal = rows.fold<double>(
    0,
    (total, row) => total + row.latestMeanMicros,
  );

  return _Comparison(
    title: title,
    generatedAt: DateTime.now(),
    baseline: _SnapshotSummary.fromJson(baseline, fallbackLabel: 'baseline'),
    latest: _SnapshotSummary.fromJson(latest, fallbackLabel: 'latest'),
    rows: rows,
    total: _ComparisonTotal(
      baselineMeanMicros: baselineTotal,
      latestMeanMicros: latestTotal,
    ),
  );
}

Map<String, Map<String, Object?>> _rowsByCase(Map<String, Object?> snapshot) {
  return {
    for (final row in _snapshotRows(snapshot)) row['case'] as String: row,
  };
}

List<Map<String, Object?>> _snapshotRows(Map<String, Object?> snapshot) {
  final rows = snapshot['rows'];
  if (rows is! List) {
    throw const FormatException('Snapshot missing rows list.');
  }
  return [
    for (final row in rows)
      if (row is Map<String, Object?>) row,
  ];
}

double _number(Object? value) {
  if (value is int) {
    return value.toDouble();
  }
  if (value is double) {
    return value;
  }
  throw FormatException('Expected number, got $value');
}

String _formatMs(double micros) => '${(micros / 1000).toStringAsFixed(3)} ms';

String _formatPercent(double value) => '${value.toStringAsFixed(1)}%';

String _formatSpeedup(double value) => '${value.toStringAsFixed(1)}x';

String _shortRevision(String? revision) {
  if (revision == null || revision.length <= 12) {
    return revision ?? 'unknown';
  }
  return revision.substring(0, 12);
}

final class _SnapshotSummary {
  const _SnapshotSummary({
    required this.label,
    required this.capturedAt,
    required this.revision,
    required this.branch,
  });

  factory _SnapshotSummary.fromJson(
    Map<String, Object?> snapshot, {
    required String fallbackLabel,
  }) {
    final git = snapshot['git'];
    final gitMap = git is Map<String, Object?>
        ? git
        : const <String, Object?>{};
    return _SnapshotSummary(
      label: snapshot['label'] as String? ?? fallbackLabel,
      capturedAt: snapshot['capturedAt'] as String?,
      revision: gitMap['revision'] as String?,
      branch: gitMap['branch'] as String?,
    );
  }

  final String label;
  final String? capturedAt;
  final String? revision;
  final String? branch;

  Map<String, Object?> toJson() => {
    'label': label,
    'capturedAt': capturedAt,
    'revision': revision,
    'branch': branch,
  };

  String toMarkdownLine(String name) {
    final pieces = <String>[
      '$name: `$label`',
      'revision `${_shortRevision(revision)}`',
    ];
    if (branch != null && branch!.isNotEmpty) {
      pieces.add('branch `$branch`');
    }
    if (capturedAt != null) {
      pieces.add('captured `$capturedAt`');
    }
    return pieces.join(', ');
  }
}

final class _ComparisonRow {
  const _ComparisonRow({
    required this.caseName,
    required this.baselineMeanMicros,
    required this.latestMeanMicros,
  });

  final String caseName;
  final double baselineMeanMicros;
  final double latestMeanMicros;

  double get reductionPercent =>
      (baselineMeanMicros - latestMeanMicros) * 100 / baselineMeanMicros;

  double get speedup => baselineMeanMicros / latestMeanMicros;

  Map<String, Object?> toJson() => {
    'case': caseName,
    'baselineMeanMicros': baselineMeanMicros,
    'latestMeanMicros': latestMeanMicros,
    'timeReductionPercent': reductionPercent,
    'speedup': speedup,
  };
}

final class _ComparisonTotal {
  const _ComparisonTotal({
    required this.baselineMeanMicros,
    required this.latestMeanMicros,
  });

  final double baselineMeanMicros;
  final double latestMeanMicros;

  double get reductionPercent =>
      (baselineMeanMicros - latestMeanMicros) * 100 / baselineMeanMicros;

  double get speedup => baselineMeanMicros / latestMeanMicros;

  Map<String, Object?> toJson() => {
    'baselineMeanMicros': baselineMeanMicros,
    'latestMeanMicros': latestMeanMicros,
    'timeReductionPercent': reductionPercent,
    'speedup': speedup,
  };
}

final class _Comparison {
  const _Comparison({
    required this.title,
    required this.generatedAt,
    required this.baseline,
    required this.latest,
    required this.rows,
    required this.total,
  });

  final String title;
  final DateTime generatedAt;
  final _SnapshotSummary baseline;
  final _SnapshotSummary latest;
  final List<_ComparisonRow> rows;
  final _ComparisonTotal total;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'generatedBy': 'tool/parser_profile_compare.dart',
    'title': title,
    'generatedAt': generatedAt.toIso8601String(),
    'baseline': baseline.toJson(),
    'latest': latest.toJson(),
    'rows': [for (final row in rows) row.toJson()],
    'total': total.toJson(),
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# $title')
      ..writeln()
      ..writeln('Generated: `${generatedAt.toIso8601String()}`')
      ..writeln()
      ..writeln(baseline.toMarkdownLine('Baseline'))
      ..writeln()
      ..writeln(latest.toMarkdownLine('Latest'))
      ..writeln()
      ..writeln('Percentage improvement is mean parse-time reduction:')
      ..writeln()
      ..writeln('```text')
      ..writeln('(baseline mean - latest mean) / baseline mean')
      ..writeln('```')
      ..writeln()
      ..writeln('| Case | Baseline | Latest | Reduction | Speedup |')
      ..writeln('| --- | ---: | ---: | ---: | ---: |');

    for (final row in rows) {
      buffer.writeln(
        '| `${row.caseName}` | `${_formatMs(row.baselineMeanMicros)}` | '
        '`${_formatMs(row.latestMeanMicros)}` | '
        '`${_formatPercent(row.reductionPercent)}` | '
        '`${_formatSpeedup(row.speedup)}` |',
      );
    }

    buffer.writeln(
      '| **Total** | `${_formatMs(total.baselineMeanMicros)}` | '
      '`${_formatMs(total.latestMeanMicros)}` | '
      '**`${_formatPercent(total.reductionPercent)}`** | '
      '**`${_formatSpeedup(total.speedup)}`** |',
    );
    return buffer.toString();
  }
}
