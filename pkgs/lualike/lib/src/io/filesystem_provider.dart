/// File system provider for creating IODevice instances
library;

import 'package:lualike/lualike.dart';
import 'io_device.dart';
import 'package:lualike/src/utils/io_abstractions.dart' as io_abs;
import 'package:lualike/src/utils/file_system_utils.dart' as fs_utils;

/// Factory function type for creating IODevice instances
typedef IODeviceFactory = Future<IODevice> Function(String path, String mode);

/// Single file system provider that can be configured with different IODevice implementations
class FileSystemProvider {
  IODeviceFactory? _ioDeviceFactory;
  IODevice? _ioDevice;
  String _providerName;

  FileSystemProvider({IODeviceFactory? ioDeviceFactory, String? providerName})
    : _ioDeviceFactory = ioDeviceFactory ?? _createDefaultIODevice,
      _providerName = providerName ?? 'DefaultFileSystem';

  /// Set a custom IODevice factory (e.g., for DropBox, InMemory, etc.)
  void setIODeviceFactory(IODeviceFactory factory, {String? providerName}) {
    Logger.debug(
      'Setting IODevice factory to: ${providerName ?? "Custom"}',
      category: 'FileSystem',
    );
    _ioDeviceFactory = factory;
    _ioDevice = null; // Clear any set device since we're using factory
    if (providerName != null) {
      _providerName = providerName;
    }
  }

  /// Set a specific IODevice instance directly
  /// This overrides any factory and uses this device for all operations
  set ioDevice(IODevice device) {
    Logger.debug(
      'Setting IODevice directly to: ${device.runtimeType}',
      category: 'FileSystem',
    );
    _ioDevice = device;
    _ioDeviceFactory = null; // Clear factory since we're using direct device
    _providerName = '${device.runtimeType}';
  }

  /// Get the current IODevice if set directly
  IODevice? get ioDevice => _ioDevice;

  /// Get the current provider name/type for debugging
  String get providerName => _providerName;

  /// Open a file with the specified path and mode
  /// Returns an IODevice that can be used for file operations
  Future<IODevice> openFile(String path, String mode) async {
    Logger.debug(
      'FileSystemProvider opening file: $path with mode: $mode using $_providerName',
      category: 'FileSystem',
    );

    if (_ioDevice != null) {
      // If a specific device is set, return it directly
      // Note: This assumes the device can handle multiple files or is stateless
      // For stateful devices, you might need to clone or create new instances
      return _ioDevice!;
    } else if (_ioDeviceFactory != null) {
      // Use factory to create new device
      return await _ioDeviceFactory!(path, mode);
    } else {
      // Fallback to local file system
      return await _createDefaultIODevice(path, mode);
    }
  }

  /// Create a temporary file with the given prefix
  /// Returns an IODevice for the temporary file
  Future<IODevice> createTempFile(String prefix) async {
    Logger.debug(
      'FileSystemProvider creating temp file with prefix: $prefix using $_providerName',
      category: 'FileSystem',
    );

    if (_ioDevice != null) {
      // If using a direct device, delegate temp file creation to it
      // This might need to be implemented differently depending on the device type
      return _ioDevice!;
    } else if (_ioDeviceFactory != null) {
      // Use factory with a temp file path
      final tempFilePath = _createTempFilePath(prefix);
      return await _ioDeviceFactory!(tempFilePath, "w+");
    } else {
      // Fallback to local temp file
      final tempFilePath = _createTempFilePath(prefix);
      return await _createDefaultIODevice(tempFilePath, "w+");
    }
  }

  /// Check if a file exists (implementation depends on current IODevice type)
  Future<bool> fileExists(String path) async {
    // This is a placeholder - in a real implementation, you'd delegate to the current device
    // For now, fallback to local file system check
    return await _fileExists(path);
  }

  /// Delete a file (implementation depends on current IODevice type)
  Future<bool> deleteFile(String path) async {
    // This is a placeholder - in a real implementation, you'd delegate to the current device
    // For now, fallback to local file system
    return await _deleteFile(path);
  }

  /// Default IODevice factory function
  static Future<IODevice> _createDefaultIODevice(
    String path,
    String mode,
  ) async {
    return await FileIODevice.open(path, mode);
  }

  /// Create a temporary file path
  static String _createTempFilePath(String prefix) {
    return io_abs.createTempFilePath(prefix);
  }

  /// Check if a file exists
  static Future<bool> _fileExists(String path) async {
    try {
      return await fs_utils.fileExists(path);
    } catch (e) {
      return false;
    }
  }

  /// Delete a file
  static Future<bool> _deleteFile(String path) async {
    try {
      await fs_utils.deleteFile(path);
      return true;
    } catch (e) {
      return false;
    }
  }
}
