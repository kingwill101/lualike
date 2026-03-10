import 'dart:convert';

import 'package:args/args.dart';
import 'package:lualike/src/utils/file_system_utils.dart' as fs;
import 'package:lualike/src/utils/io_abstractions.dart' as io_abs;
import 'package:lualike/src/utils/platform_utils.dart' as platform;
import 'package:path/path.dart' as path;

const _downloadsPattern = 'dart_devtools_';
const _lualikeRepoPrefix =
    '/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike/';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'latest',
      help: 'Load the latest export from ~/Downloads.',
      allowed: const ['cpu', 'heap', 'memory', 'performance', 'all', 'none'],
      defaultsTo: 'cpu',
    )
    ..addOption(
      'top',
      help: 'Number of rows to print per section.',
      defaultsTo: '12',
    )
    ..addFlag(
      'lualike-only',
      help: 'Only show lualike source files in file summaries.',
      defaultsTo: false,
    )
    ..addFlag('help', abbr: 'h', help: 'Print usage.', negatable: false);

  final parsed = parser.parse(args);
  if (parsed['help'] as bool) {
    io_abs.stdout.writeln('Summarize Dart DevTools exports');
    io_abs.stdout.writeln(parser.usage);
    return;
  }

  final top = int.parse(parsed['top'] as String);
  final lualikeOnly = parsed['lualike-only'] as bool;
  final targets = parsed.rest.isNotEmpty
      ? parsed.rest
      : await _resolveLatestTargets(parsed['latest'] as String);

  var failed = false;

  if (targets.isEmpty) {
    io_abs.stderr.writeln('No DevTools exports found.');
    io_abs.exitProcess(1);
  }

  for (final file in targets) {
    if (!await fs.fileExists(file)) {
      io_abs.stderr.writeln('Missing export: $file');
      failed = true;
      continue;
    }

    io_abs.stdout.writeln('');
    io_abs.stdout.writeln('=== $file ===');

    final lowerName = file.toLowerCase();
    if (lowerName.endsWith('.json')) {
      await _summarizeJson(file, top: top, lualikeOnly: lualikeOnly);
      continue;
    }
    if (lowerName.endsWith('.csv')) {
      await _summarizeHeapCsv(file, top: top);
      continue;
    }

    io_abs.stdout.writeln('Unsupported file type.');
  }

  if (failed) {
    io_abs.exitProcess(1);
  }
}

Future<List<String>> _resolveLatestTargets(String latest) async {
  if (latest == 'none') {
    return const [];
  }

  final home = platform.getEnvironmentVariable('HOME');
  if (home == null) {
    return const [];
  }

  final downloads = path.join(home, 'Downloads');
  if (!await fs.directoryExists(downloads)) {
    return const [];
  }

  final files = (await fs.listDirectory(downloads))
      .where((file) => path.basename(file).startsWith(_downloadsPattern))
      .toList();
  final actualFiles = <String>[];
  for (final file in files) {
    if (await fs.fileExists(file)) {
      actualFiles.add(file);
    }
  }

  Future<String?> newestWhere(
    Future<bool> Function(String file) predicate,
  ) async {
    final matches = <({String path, DateTime modified})>[];
    for (final file in actualFiles) {
      if (!await predicate(file)) {
        continue;
      }
      final modified = await fs.getLastModified(file);
      if (modified != null) {
        matches.add((path: file, modified: modified));
      }
    }
    matches.sort((a, b) => b.modified.compareTo(a.modified));
    return matches.isEmpty ? null : matches.first.path;
  }

  return switch (latest) {
    'cpu' => [if (await newestWhere(_isCpuSnapshot) case final file?) file],
    'performance' => [if (await newestWhere(_isPerformanceSnapshot) case final file?) file],
    'heap' => [
      if (await newestWhere((file) async => file.toLowerCase().endsWith('.csv'))
          case final file?)
        file,
    ],
    'memory' => [
      if (await newestWhere((file) async => file.toLowerCase().endsWith('.csv'))
          case final file?)
        file,
    ],
    'all' => [
      if (await newestWhere(_isCpuSnapshot) case final cpu?) cpu,
      if (await newestWhere(_isPerformanceSnapshot) case final perf?) perf,
      if (await newestWhere((file) async => file.toLowerCase().endsWith('.csv'))
          case final heap?)
        heap,
    ],
    _ => const [],
  };
}

Future<bool> _isCpuSnapshot(String file) async {
  final name = path.basename(file).toLowerCase();
  if (!name.endsWith('.json')) {
    return false;
  }
  return _fileHeadContains(file, '"activeScreenId":"cpu-profiler"');
}

Future<bool> _isPerformanceSnapshot(String file) async {
  final name = path.basename(file).toLowerCase();
  if (!name.endsWith('.json')) {
    return false;
  }
  return _fileHeadContains(file, '"activeScreenId":"performance"');
}

Future<void> _summarizeJson(
  String file, {
  required int top,
  required bool lualikeOnly,
}) async {
  final fileContents = await fs.readFileAsString(file);
  if (fileContents == null) {
    io_abs.stdout.writeln('Could not read JSON export.');
    return;
  }
  final root = jsonDecode(fileContents);
  if (root is! Map<String, dynamic>) {
    io_abs.stdout.writeln('JSON export is not an object.');
    return;
  }

  final activeScreenId = root['activeScreenId'];
  _printConnectedAppSummary(root['connectedApp']);
  switch (activeScreenId) {
    case 'cpu-profiler':
      final cpu = root['cpu-profiler'];
      if (cpu is! Map<String, dynamic>) {
        io_abs.stdout.writeln('CPU snapshot payload missing.');
        return;
      }
      _summarizeCpuSnapshot(cpu, top: top, lualikeOnly: lualikeOnly);
    case 'performance':
      final perf = root['performance'];
      if (perf is! Map<String, dynamic>) {
        io_abs.stdout.writeln('Performance snapshot payload missing.');
        return;
      }
      _summarizePerformanceSnapshot(perf, top: top);
    default:
      io_abs.stdout.writeln('Unsupported snapshot type: $activeScreenId');
  }
}

void _printConnectedAppSummary(Object? rawConnectedApp) {
  if (rawConnectedApp is! Map<String, dynamic>) {
    return;
  }
  io_abs.stdout.writeln('Connected app');
  io_abs.stdout.writeln(
    '  vm: ${rawConnectedApp['isRunningOnDartVM'] == true ? 'yes' : 'no'}'
    '  flutter: ${rawConnectedApp['isFlutterApp'] == true ? 'yes' : 'no'}'
    '  profile-build: ${rawConnectedApp['isProfileBuild'] == true ? 'yes' : 'no'}'
    '  web: ${rawConnectedApp['isDartWebApp'] == true ? 'yes' : 'no'}',
  );
  final operatingSystem = rawConnectedApp['operatingSystem'];
  if (operatingSystem is String && operatingSystem.isNotEmpty) {
    io_abs.stdout.writeln('  os: $operatingSystem');
  }
}

void _summarizePerformanceSnapshot(
  Map<String, dynamic> perf, {
  required int top,
}) {
  final traceBinary = perf['traceBinary'];
  final bytes = traceBinary is List ? traceBinary.length : 0;
  final displayRefreshRate = perf['displayRefreshRate'];
  final flutterFrames = switch (perf['flutterFrames']) {
    final List frames => frames,
    _ => const <Object?>[],
  };
  final selectedFrameId = perf['selectedFrameId'];

  io_abs.stdout.writeln('Performance snapshot');
  io_abs.stdout.writeln('  trace bytes: ${_formatInt(bytes)}');
  if (displayRefreshRate is num) {
    io_abs.stdout.writeln(
      '  display refresh rate: ${displayRefreshRate.toString()} Hz',
    );
  }
  io_abs.stdout.writeln('  flutter frames: ${_formatInt(flutterFrames.length)}');
  if (selectedFrameId != null) {
    io_abs.stdout.writeln('  selected frame id: $selectedFrameId');
  }

  final frameStats = _extractFlutterFrameStats(flutterFrames);
  if (frameStats.isNotEmpty) {
    io_abs.stdout.writeln('');
    io_abs.stdout.writeln('Top flutter frames by elapsed time');
    for (final entry in frameStats.take(top)) {
      io_abs.stdout.writeln(
        '  ${_formatDurationMicros(entry.elapsedMicros).padLeft(10)}  '
        'id=${entry.id}  '
        'vsync=${entry.vsync ?? '-'}  '
        'build=${entry.buildMicros == null ? '-' : _formatDurationMicros(entry.buildMicros!)}  '
        'raster=${entry.rasterMicros == null ? '-' : _formatDurationMicros(entry.rasterMicros!)}',
      );
    }
  }

  io_abs.stdout.writeln('');
  io_abs.stdout.writeln(
    '  note: traceBinary is a binary performance trace payload; this tool does not decode the full timeline yet',
  );
}

void _summarizeCpuSnapshot(
  Map<String, dynamic> cpu, {
  required int top,
  required bool lualikeOnly,
}) {
  final frames = <String, _StackFrame>{};
  final rawFrames = cpu['stackFrames'];
  if (rawFrames is Map<String, dynamic>) {
    for (final entry in rawFrames.entries) {
      if (entry.value case final Map<String, dynamic> frame) {
        frames[entry.key] = _StackFrame.fromJson(entry.key, frame);
      }
    }
  }

  final events = cpu['traceEvents'];
  if (events is! List) {
    io_abs.stdout.writeln('CPU snapshot has no trace events.');
    return;
  }

  final selfByMethod = <String, int>{};
  final inclusiveByMethod = <String, int>{};
  final selfByFile = <String, int>{};
  final inclusiveByFile = <String, int>{};
  final stacks = <String, int>{};
  var sampleCount = 0;

  for (final rawEvent in events) {
    if (rawEvent is! Map<String, dynamic>) {
      continue;
    }
    if (rawEvent['ph'] != 'P') {
      continue;
    }
    if (rawEvent['sf'] is! String) {
      continue;
    }
    final frameId = rawEvent['sf'] as String;
    final frame = frames[frameId];
    if (frame == null) {
      continue;
    }

    sampleCount++;
    final methodKey = '${frame.name}\t${frame.displayUrl}';
    selfByMethod.update(methodKey, (count) => count + 1, ifAbsent: () => 1);
    selfByFile.update(
      frame.displayUrl,
      (count) => count + 1,
      ifAbsent: () => 1,
    );

    final seen = <String>{};
    final seenMethodKeys = <String>{};
    final seenFiles = <String>{};
    String? currentId = frameId;
    final chainLabels = <String>[];
    while (currentId != null && seen.add(currentId)) {
      final current = frames[currentId];
      if (current == null) {
        break;
      }
      final currentMethodKey = '${current.name}\t${current.displayUrl}';
      if (seenMethodKeys.add(currentMethodKey)) {
        inclusiveByMethod.update(
          currentMethodKey,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      if (seenFiles.add(current.displayUrl)) {
        inclusiveByFile.update(
          current.displayUrl,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      if (chainLabels.length < 6) {
        chainLabels.add(current.name);
      }
      currentId = current.parent;
    }

    final stackLabel = chainLabels.join(' <- ');
    if (stackLabel.isNotEmpty) {
      stacks.update(stackLabel, (count) => count + 1, ifAbsent: () => 1);
    }
  }

  final samplePeriodMicros = _asInt(cpu['samplePeriod']);
  final timeExtentMicros = _asInt(cpu['timeExtentMicros']);
  io_abs.stdout.writeln('CPU profiler snapshot');
  io_abs.stdout.writeln(
    '  samples: ${_formatInt(sampleCount)} '
    '(@ $samplePeriodMicros us, wall ${_formatDurationMicros(timeExtentMicros)})',
  );
  io_abs.stdout.writeln('  unique frames: ${_formatInt(frames.length)}');

  _printMethodSection(
    title: 'Top self methods',
    counts: selfByMethod,
    totalSamples: sampleCount,
    top: top,
  );
  _printMethodSection(
    title: 'Top inclusive methods',
    counts: inclusiveByMethod,
    totalSamples: sampleCount,
    top: top,
  );
  _printFileSection(
    title: 'Top self files',
    counts: selfByFile,
    totalSamples: sampleCount,
    top: top,
    lualikeOnly: lualikeOnly,
  );
  _printFileSection(
    title: 'Top inclusive files',
    counts: inclusiveByFile,
    totalSamples: sampleCount,
    top: top,
    lualikeOnly: lualikeOnly,
  );
  _printStackSection(
    title: 'Representative hot stacks',
    counts: stacks,
    totalSamples: sampleCount,
    top: top.clamp(1, 8),
  );
}

void _printMethodSection({
  required String title,
  required Map<String, int> counts,
  required int totalSamples,
  required int top,
}) {
  io_abs.stdout.writeln('');
  io_abs.stdout.writeln(title);
  for (final entry in _topEntries(counts, top)) {
    final (:name, :url) = _splitMethodKey(entry.key);
    io_abs.stdout.writeln(
      '  ${_formatPercent(entry.value, totalSamples)} '
      '${_formatInt(entry.value).padLeft(6)}  $name  [$url]',
    );
  }
}

({String name, String url}) _splitMethodKey(String key) {
  final separator = key.indexOf('\t');
  if (separator < 0) {
    return (name: key, url: '<unknown>');
  }
  return (name: key.substring(0, separator), url: key.substring(separator + 1));
}

void _printFileSection({
  required String title,
  required Map<String, int> counts,
  required int totalSamples,
  required int top,
  required bool lualikeOnly,
}) {
  final filtered = lualikeOnly
      ? Map.fromEntries(
          counts.entries.where(
            (entry) =>
                entry.key.startsWith('lib/') ||
                entry.key.startsWith('package:lualike/') ||
                entry.key.contains('/lualike/'),
          ),
        )
      : counts;

  io_abs.stdout.writeln('');
  io_abs.stdout.writeln(title);
  for (final entry in _topEntries(filtered, top)) {
    io_abs.stdout.writeln(
      '  ${_formatPercent(entry.value, totalSamples)} '
      '${_formatInt(entry.value).padLeft(6)}  ${entry.key}',
    );
  }
}

void _printStackSection({
  required String title,
  required Map<String, int> counts,
  required int totalSamples,
  required int top,
}) {
  io_abs.stdout.writeln('');
  io_abs.stdout.writeln(title);
  for (final entry in _topEntries(counts, top)) {
    io_abs.stdout.writeln(
      '  ${_formatPercent(entry.value, totalSamples)} '
      '${_formatInt(entry.value).padLeft(6)}  ${entry.key}',
    );
  }
}

Future<void> _summarizeHeapCsv(String file, {required int top}) async {
  final csv = await fs.readFileAsString(file);
  if (csv == null) {
    io_abs.stdout.writeln('Could not read heap CSV.');
    return;
  }
  final lines = const LineSplitter().convert(csv);
  if (lines.length < 2) {
    io_abs.stdout.writeln('Heap CSV is empty.');
    return;
  }

  final header = _parseCsvLine(lines.first);
  final rows = lines.skip(1).map(_parseCsvLine).where((row) => row.isNotEmpty);

  int indexOf(String name) => header.indexOf(name);

  final classIndex = indexOf('Class');
  final libraryIndex = indexOf('Library');
  final instancesIndex = indexOf('Total Instances');
  final sizeIndex = indexOf('Total Size');
  final dartHeapSizeIndex = indexOf('Total Dart Heap Size');
  final externalSizeIndex = indexOf('Total External Size');
  final newSpaceInstancesIndex = indexOf('New Space Instances');
  final newSpaceSizeIndex = indexOf('New Space Size');
  final oldSpaceInstancesIndex = indexOf('Old Space Instances');
  final oldSpaceSizeIndex = indexOf('Old Space Size');

  if ([classIndex, libraryIndex, instancesIndex, sizeIndex].contains(-1)) {
    io_abs.stdout.writeln(
      'Heap CSV header does not match the expected DevTools export.',
    );
    return;
  }

  final summaries = rows
      .where((row) => row.length > sizeIndex)
      .map(
        (row) => (
          className: row[classIndex],
          library: row[libraryIndex],
          instances: int.tryParse(row[instancesIndex]) ?? 0,
          size: int.tryParse(row[sizeIndex]) ?? 0,
          dartHeapSize: dartHeapSizeIndex >= 0
              ? int.tryParse(row[dartHeapSizeIndex]) ?? 0
              : 0,
          externalSize: externalSizeIndex >= 0
              ? int.tryParse(row[externalSizeIndex]) ?? 0
              : 0,
          newSpaceInstances: newSpaceInstancesIndex >= 0
              ? int.tryParse(row[newSpaceInstancesIndex]) ?? 0
              : 0,
          newSpaceSize: newSpaceSizeIndex >= 0
              ? int.tryParse(row[newSpaceSizeIndex]) ?? 0
              : 0,
          oldSpaceInstances: oldSpaceInstancesIndex >= 0
              ? int.tryParse(row[oldSpaceInstancesIndex]) ?? 0
              : 0,
          oldSpaceSize: oldSpaceSizeIndex >= 0
              ? int.tryParse(row[oldSpaceSizeIndex]) ?? 0
              : 0,
        ),
      )
      .toList();

  final totalInstances = summaries.fold<int>(
    0,
    (sum, row) => sum + row.instances,
  );
  final totalSize = summaries.fold<int>(0, (sum, row) => sum + row.size);
  final totalDartHeap = summaries.fold<int>(
    0,
    (sum, row) => sum + row.dartHeapSize,
  );
  final totalExternal = summaries.fold<int>(
    0,
    (sum, row) => sum + row.externalSize,
  );
  final totalNewSpace = summaries.fold<int>(
    0,
    (sum, row) => sum + row.newSpaceSize,
  );
  final totalOldSpace = summaries.fold<int>(
    0,
    (sum, row) => sum + row.oldSpaceSize,
  );

  final librarySummaries = <String, ({int instances, int size})>{};
  for (final summary in summaries) {
    librarySummaries.update(
      summary.library,
      (current) => (
        instances: current.instances + summary.instances,
        size: current.size + summary.size,
      ),
      ifAbsent: () => (instances: summary.instances, size: summary.size),
    );
  }

  io_abs.stdout.writeln('Heap class summary');
  io_abs.stdout.writeln('  rows: ${_formatInt(summaries.length)}');
  io_abs.stdout.writeln('  total instances: ${_formatInt(totalInstances)}');
  io_abs.stdout.writeln(
    '  total size: ${_formatBytes(totalSize)} '
    '(dart heap ${_formatBytes(totalDartHeap)}, external ${_formatBytes(totalExternal)})',
  );
  io_abs.stdout.writeln(
    '  space split: new ${_formatBytes(totalNewSpace)}, old ${_formatBytes(totalOldSpace)}',
  );

  io_abs.stdout.writeln('');
  io_abs.stdout.writeln('Top classes by total size');
  for (final summary in summaries.sortedBySize().take(top)) {
    io_abs.stdout.writeln(
      '  ${_formatBytes(summary.size).padLeft(9)} '
      '${_formatInt(summary.instances).padLeft(7)}  '
      '${summary.className}  [${summary.library}]',
    );
  }

  io_abs.stdout.writeln('');
  io_abs.stdout.writeln('Top libraries by total size');
  for (final entry in _topLibraryEntries(librarySummaries, top)) {
    io_abs.stdout.writeln(
      '  ${_formatBytes(entry.size).padLeft(9)} '
      '${_formatInt(entry.instances).padLeft(7)}  '
      '${entry.library}',
    );
  }

  final lualikeSummaries = summaries
      .where((summary) => _isLualikeLocation(summary.library))
      .sortedBySize();
  if (lualikeSummaries.isNotEmpty) {
    io_abs.stdout.writeln('');
    io_abs.stdout.writeln('Top lualike classes by total size');
    for (final summary in lualikeSummaries.take(top)) {
      io_abs.stdout.writeln(
        '  ${_formatBytes(summary.size).padLeft(9)} '
        '${_formatInt(summary.instances).padLeft(7)}  '
        '${summary.className}  [${summary.library}]',
      );
    }
  }
}

List<String> _parseCsvLine(String line) {
  final values = <String>[];
  var buffer = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buffer.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }
    if (char == ',' && !inQuotes) {
      values.add(buffer.toString());
      buffer = StringBuffer();
      continue;
    }
    buffer.write(char);
  }
  values.add(buffer.toString());
  return values;
}

Future<bool> _fileHeadContains(String file, String needle) async {
  final bytes = await fs.readFileAsBytes(file);
  if (bytes == null) {
    return false;
  }
  final prefix = bytes.length > 1024 ? bytes.sublist(0, 1024) : bytes;
  return utf8.decode(prefix, allowMalformed: true).contains(needle);
}

List<MapEntry<String, int>> _topEntries(Map<String, int> counts, int top) {
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final countCompare = b.value.compareTo(a.value);
      return countCompare != 0 ? countCompare : a.key.compareTo(b.key);
    });
  return entries.take(top).toList();
}

int _asInt(Object? value) => switch (value) {
  int n => n,
  num n => n.toInt(),
  _ => 0,
};

String _formatDurationMicros(int micros) {
  final milliseconds = micros / Duration.microsecondsPerMillisecond;
  if (milliseconds < 1000) {
    return '${milliseconds.toStringAsFixed(2)} ms';
  }
  return '${(milliseconds / 1000).toStringAsFixed(2)} s';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kib = bytes / 1024;
  if (kib < 1024) {
    return '${kib.toStringAsFixed(1)} KiB';
  }
  final mib = kib / 1024;
  if (mib < 1024) {
    return '${mib.toStringAsFixed(1)} MiB';
  }
  return '${(mib / 1024).toStringAsFixed(1)} GiB';
}

String _formatInt(int value) {
  final digits = value.abs().toString();
  final groups = <String>[];
  for (var i = digits.length; i > 0; i -= 3) {
    final start = i - 3 < 0 ? 0 : i - 3;
    groups.add(digits.substring(start, i));
  }
  final formatted = groups.reversed.join(',');
  return value < 0 ? '-$formatted' : formatted;
}

String _formatPercent(int count, int total) {
  if (total <= 0) {
    return '0.00%';
  }
  return '${(count * 100 / total).toStringAsFixed(2)}%';
}

bool _isLualikeLocation(String location) {
  return location.startsWith('lib/') ||
      location.startsWith('package:lualike/') ||
      location.contains('/lualike/');
}

List<({String library, int instances, int size})> _topLibraryEntries(
  Map<String, ({int instances, int size})> counts,
  int top,
) {
  final entries =
      counts.entries
          .map(
            (entry) => (
              library: entry.key,
              instances: entry.value.instances,
              size: entry.value.size,
            ),
          )
          .toList()
        ..sort((a, b) {
          final sizeCompare = b.size.compareTo(a.size);
          return sizeCompare != 0
              ? sizeCompare
              : a.library.compareTo(b.library);
        });
  return entries.take(top).toList();
}

List<_FlutterFrameStat> _extractFlutterFrameStats(List<Object?> rawFrames) {
  final stats = <_FlutterFrameStat>[];
  for (final rawFrame in rawFrames) {
    if (rawFrame is! Map<String, dynamic>) {
      continue;
    }
    final elapsedMicros = _firstPositiveInt(rawFrame, const [
      'elapsedTimeMicros',
      'elapsedMicros',
      'totalDurationMicros',
      'frameTimeMicros',
    ]);
    if (elapsedMicros == null) {
      continue;
    }
    stats.add(
      _FlutterFrameStat(
        id:
            rawFrame['id']?.toString() ??
            rawFrame['frameId']?.toString() ??
            '?',
        elapsedMicros: elapsedMicros,
        buildMicros: _firstPositiveInt(rawFrame, const [
          'buildTimeMicros',
          'buildMicros',
          'uiDurationMicros',
        ]),
        rasterMicros: _firstPositiveInt(rawFrame, const [
          'rasterTimeMicros',
          'rasterMicros',
          'rasterDurationMicros',
        ]),
        vsync: rawFrame['vsyncOverheadMicros']?.toString(),
      ),
    );
  }
  stats.sort((a, b) => b.elapsedMicros.compareTo(a.elapsedMicros));
  return stats;
}

int? _firstPositiveInt(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    final parsed = switch (value) {
      int n => n,
      num n => n.toInt(),
      _ => null,
    };
    if (parsed != null && parsed >= 0) {
      return parsed;
    }
  }
  return null;
}

extension
    on
        Iterable<
          ({
            String className,
            String library,
            int instances,
            int size,
            int dartHeapSize,
            int externalSize,
            int newSpaceInstances,
            int newSpaceSize,
            int oldSpaceInstances,
            int oldSpaceSize,
          })
        > {
  List<
    ({
      String className,
      String library,
      int instances,
      int size,
      int dartHeapSize,
      int externalSize,
      int newSpaceInstances,
      int newSpaceSize,
      int oldSpaceInstances,
      int oldSpaceSize,
    })
  >
  sortedBySize() {
    final list = toList()
      ..sort((a, b) {
        final sizeCompare = b.size.compareTo(a.size);
        return sizeCompare != 0
            ? sizeCompare
            : a.className.compareTo(b.className);
      });
    return list;
  }
}

final class _StackFrame {
  const _StackFrame({
    required this.id,
    required this.name,
    required this.parent,
    required this.resolvedUrl,
  });

  factory _StackFrame.fromJson(String id, Map<String, dynamic> json) {
    return _StackFrame(
      id: id,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : '<unknown>',
      parent: json['parent'] as String?,
      resolvedUrl: _normalizeUrl(json['resolvedUrl'] as String?),
    );
  }

  final String id;
  final String name;
  final String? parent;
  final String resolvedUrl;

  String get displayUrl => resolvedUrl;
}

final class _FlutterFrameStat {
  const _FlutterFrameStat({
    required this.id,
    required this.elapsedMicros,
    required this.buildMicros,
    required this.rasterMicros,
    required this.vsync,
  });

  final String id;
  final int elapsedMicros;
  final int? buildMicros;
  final int? rasterMicros;
  final String? vsync;
}

String _normalizeUrl(String? url) {
  if (url == null || url.isEmpty) {
    return '<unknown>';
  }
  if (!url.startsWith('file://')) {
    return url;
  }

  final parsed = Uri.tryParse(url);
  final filePath = parsed?.toFilePath() ?? url.substring('file://'.length);
  if (filePath.startsWith(_lualikeRepoPrefix)) {
    return filePath.substring(_lualikeRepoPrefix.length);
  }
  return filePath;
}
