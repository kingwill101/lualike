import 'package:archive/archive.dart';

/// Returns `null` when 7z archive decoding is not available in this build.
Archive? decode7zArchive(List<int> bytes) => null;
