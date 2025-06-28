import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

Future<void> checkAndDownloadTestSuite(
  String downloadUrl,
  String testSuitePath,
) async {
  final url = Uri.parse(downloadUrl);
  final destinationPath = Directory(testSuitePath);

  if (!destinationPath.existsSync()) {
    print('Downloading test suite from $url to ${destinationPath.path}');
    try {
      final request = http.Request('GET', url);
      final streamedResponse = await http.Client().send(request);
      if (streamedResponse.statusCode == 200) {
        final bytes = await streamedResponse.stream.toBytes();
        print('Download complete. Extracting...');

        // Create the destination directory if it doesn't exist
        if (!destinationPath.existsSync()) {
          destinationPath.createSync(recursive: true);
        }

        // Extract the archive
        final archive = TarDecoder().decodeBytes(gzip.decode(bytes));
        for (final file in archive) {
          final filename = file.name;
          // Extract only files from the tests folder
          if (!filename.startsWith('lua-5.4.7-tests/')) {
            continue;
          }
          final relativePath = filename.replaceFirst('lua-5.4.7-tests/', '');
          if (file.isFile) {
            final filePath = p.join(destinationPath.path, relativePath);
            final outFile = File(filePath);
            final parent = Directory(p.dirname(filePath));
            if (!parent.existsSync()) {
              parent.createSync(recursive: true);
            }
            outFile.writeAsBytesSync(file.content as List<int>);
          } else {
            final dirPath = p.join(destinationPath.path, relativePath);
            final dir = Directory(dirPath);
            dir.createSync(recursive: true);
          }
        }

        print('Extraction complete.');
      } else {
        print(
          'Error downloading test suite. Status code: ${streamedResponse.statusCode}',
        );
        exit(1);
      }
    } catch (e, stackTrace) {
      print('Error downloading or extracting test suite: $e');
      print('Stack trace: $stackTrace');
      exit(1);
    }
  } else {
    print('Test suite already exists at ${destinationPath.path}');
  }
}
