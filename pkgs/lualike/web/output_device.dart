import 'package:lualike/src/io/io_device.dart';
import 'package:web/web.dart' as web;

// WebOutputDevice implements IODevice for web UI output
class WebOutputDevice implements IODevice {
  final web.HTMLDivElement outputDiv;
  bool _isClosed = false;

  WebOutputDevice(this.outputDiv);

  @override
  bool get isClosed => _isClosed;

  @override
  String get mode => 'w';

  @override
  Future<void> close() async {
    _isClosed = true;
  }

  @override
  Future<void> flush() async {}

  @override
  Future<ReadResult> read([String format = "l"]) async {
    throw UnimplementedError("WebOutputDevice does not support read");
  }

  @override
  Future<WriteResult> write(String data) async {
    if (_isClosed) {
      return WriteResult(false, "Device is closed");
    }

    // Add the output to the web UI
    final line = web.document.createElement('div') as web.HTMLDivElement;
    line.className = 'output-line';
    line.textContent = data;
    outputDiv.appendChild(line);

    // Auto-scroll to bottom
    outputDiv.scrollTop = outputDiv.scrollHeight;

    return WriteResult(true);
  }

  @override
  Future<WriteResult> writeBytes(List<int> bytes) async {
    if (_isClosed) {
      return WriteResult(false, "Device is closed");
    }

    final str = String.fromCharCodes(bytes);
    final line = web.document.createElement('div') as web.HTMLDivElement;
    line.className = 'output-line';
    line.textContent = str;
    outputDiv.appendChild(line);
    outputDiv.scrollTop = outputDiv.scrollHeight;
    return WriteResult(true);
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    throw UnimplementedError("WebOutputDevice does not support seek");
  }

  @override
  Future<void> setBuffering(BufferMode mode, [int? size]) async {}

  @override
  Future<int> getPosition() async => 0;

  @override
  Future<bool> isEOF() async => true;
}
