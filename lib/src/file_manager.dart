import 'dart:convert';
import 'package:lualike/src/utils/file_system_utils.dart' as fs;

import 'package:lualike/lualike.dart';
import 'package:lualike/src/utils/platform_utils.dart' as platform;
import 'package:path/path.dart' as path;

/// Manages source file loading and virtual file system for the VM.
///
/// Provides functionality to load source files from both the physical file system
/// and a virtual in-memory file system. Supports configurable search paths and
/// module resolution for the import system.
class FileManager {
  /// Map of virtual files by path.
  final Map<String, String> _virtualFiles = {};

  /// Base search paths for finding modules.
  final List<String> _searchPaths = ['.'];

  /// Reference to the interpreter (may be null)
  Interpreter? _interpreter;

  /// Tracks resolved globs and their absolute paths for debugging
  final List<Map<String, String>> _resolvedGlobs = [];

  /// Get the list of resolved globs for debugging
  List<Map<String, String>> get resolvedGlobs => _resolvedGlobs;

  /// Returns the current list of module search paths.
  List<String> get searchPaths => _searchPaths;

  /// Creates a new FileManager instance.
  ///
  /// [interpreter] - Optional reference to the interpreter for accessing script paths
  FileManager({Interpreter? interpreter}) : _interpreter = interpreter {
    // Initialize with current directory as default search path
    _searchPaths.add('.');

    // Add the current working directory to search paths
    try {
      final currentDir = fs.getCurrentDirectory();
      if (currentDir != null && !_searchPaths.contains(currentDir)) {
        _searchPaths.add(currentDir);
        Logger.debug(
          "Added current working directory to search paths: $currentDir",
          category: 'FileManager',
        );
      }
    } catch (e) {
      Logger.debug(
        "Could not add current working directory to search paths: $e",
        category: 'FileManager',
      );
    }

    // Add the Dart script directory to search paths - only if not in product mode
    if (!isProductMode) {
      try {
        // Try to get the script path
        String? dartScriptPath;
        try {
          dartScriptPath = platform.scriptPath;
        } catch (e) {
          Logger.debug(
            "Platform.script not available: $e",
            category: 'FileManager',
          );
        }

        if (dartScriptPath != null && dartScriptPath.isNotEmpty) {
          final dartScriptDir = path.dirname(dartScriptPath);
          if (!_searchPaths.contains(dartScriptDir)) {
            _searchPaths.add(dartScriptDir);
            Logger.debug(
              "Added Dart script directory to search paths: $dartScriptDir",
              category: 'FileManager',
            );
          }

          // Also try to add the project root directory
          try {
            final projectRoot = path.dirname(path.dirname(dartScriptPath));
            if (!_searchPaths.contains(projectRoot)) {
              _searchPaths.add(projectRoot);
              Logger.debug(
                "Added project root to search paths: $projectRoot",
                category: 'FileManager',
              );
            }
          } catch (e) {
            Logger.debug(
              "Could not add project root to search paths: $e",
              category: 'FileManager',
            );
          }
        }
      } catch (e) {
        Logger.debug(
          "Could not add Dart script directory to search paths: $e",
          category: 'FileManager',
        );
      }
    } else {
      Logger.debug(
        "Running as compiled executable, skipping Platform.script path resolution",
        category: 'FileManager',
      );
    }

    // If interpreter is provided, try to get the script path immediately
    if (_interpreter?.currentScriptPath != null) {
      final scriptDir = path.dirname(_interpreter!.currentScriptPath!);
      if (!_searchPaths.contains(scriptDir)) {
        _searchPaths.add(scriptDir);
        Logger.debug(
          "Added script directory to search paths: $scriptDir",
          category: 'FileManager',
        );
      }
    }
  }

  /// Clears the list of resolved globs
  void clearResolvedGlobs() {
    _resolvedGlobs.clear();
  }

  /// Adds a resolved glob to the tracking list
  void _addResolvedGlob(String pattern, String resolvedPath) {
    _resolvedGlobs.add({'pattern': pattern, 'resolved': resolvedPath});
  }

  /// Sets the interpreter reference.
  ///
  /// This allows the file manager to access the current script path.
  void setInterpreter(Interpreter interpreter) {
    _interpreter = interpreter;

    // When interpreter is set, add the current script path to search paths if available
    if (_interpreter?.currentScriptPath != null) {
      final scriptDir = path.dirname(_interpreter!.currentScriptPath!);
      if (!_searchPaths.contains(scriptDir)) {
        _searchPaths.add(scriptDir);
        Logger.debug(
          "Added script directory to search paths: $scriptDir",
          category: 'FileManager',
        );
      }
    }
  }

  // In lualike/lib/src/file_manager.dart

  /// Registers a virtual file that will be available to load().
  ///
  /// [virtualPath] - The path where the virtual file will be accessible
  /// [content] - The content of the virtual file
  void registerVirtualFile(String virtualPath, String content) {
    // Normalize the path before storing
    final normalizedPath = path.normalize(virtualPath);
    _virtualFiles[normalizedPath] = content;

    // Also register without extension if it has one
    if (path.extension(normalizedPath).isNotEmpty) {
      final baseName = normalizedPath.substring(
        0,
        normalizedPath.lastIndexOf('.'),
      );
      if (!_virtualFiles.containsKey(baseName)) {
        _virtualFiles[baseName] = content;
      }
    }

    Logger.debug(
      "Registered virtual file: $normalizedPath",
      category: 'FileManager',
    );
  }

  /// Adds a directory to the module search path.
  ///
  /// [searchPath] - The directory path to add to the search paths
  void addSearchPath(String searchPath) {
    _searchPaths.add(searchPath);
  }

  /// Loads source code from a file or virtual file.
  ///
  /// Attempts to load the file from both virtual and physical file systems,
  /// trying different extensions and search paths.
  ///
  /// [filePath] - The path of the file to load
  /// [preserveRawBytes] - If true, read as raw bytes to preserve high byte values
  /// Returns the file contents if found, null otherwise
  Future<String?> loadSource(
    String filePath, {
    bool preserveRawBytes = false,
  }) async {
    final extensions = ['', '.lua'];

    // Check if we have a current script path and add its directory to search paths
    if (_interpreter?.currentScriptPath != null) {
      final scriptDir = path.dirname(_interpreter!.currentScriptPath!);
      if (!_searchPaths.contains(scriptDir)) {
        _searchPaths.add(scriptDir);
        Logger.debug(
          "Added script directory to search paths: $scriptDir",
          category: 'FileManager',
        );
      }
    }

    // Add current working directory to search paths
    try {
      final currentDir = fs.getCurrentDirectory();
      if (currentDir != null && !_searchPaths.contains(currentDir)) {
        _searchPaths.add(currentDir);
        Logger.debug(
          "Added current working directory to search paths: $currentDir",
          category: 'FileManager',
        );
      }
    } catch (e) {
      Logger.debug(
        "Could not add current working directory to search paths: $e",
        category: 'FileManager',
      );
    }

    // Add Dart script directory to search paths if available and not in product mode
    if (!isProductMode) {
      try {
        final dartScriptPath = platform.scriptPath;
        if (dartScriptPath == null) {
          throw Exception("Dart script path is null");
        }
        final dartScriptDir = path.dirname(dartScriptPath);
        if (!_searchPaths.contains(dartScriptDir)) {
          _searchPaths.add(dartScriptDir);
          Logger.debug(
            "Added Dart script directory to search paths: $dartScriptDir",
            category: 'FileManager',
          );
        }

        // Also add project root to search paths
        final projectRoot = path.dirname(path.dirname(dartScriptPath));
        if (!_searchPaths.contains(projectRoot)) {
          _searchPaths.add(projectRoot);
          Logger.debug(
            "Added project root to search paths: $projectRoot",
            category: 'FileManager',
          );
        }

        // Add special directories to search paths
        final specialDirs = [
          path.join(projectRoot, 'test'),
          path.join(projectRoot, '.lua-tests'),
        ];

        for (final dir in specialDirs) {
          if (!_searchPaths.contains(dir) && (await fs.directoryExists(dir))) {
            _searchPaths.add(dir);
            Logger.debug(
              "Added special directory to search paths: $dir",
              category: 'FileManager',
            );
          }
        }
      } catch (e) {
        Logger.debug(
          "Could not add Dart script directory to search paths: $e",
          category: 'FileManager',
        );
      }
    } else {
      Logger.debug(
        "Running as compiled executable, skipping Platform.script path resolution in loadSource",
        category: 'FileManager',
      );
    }

    // Try exact name first
    for (final ext in extensions) {
      final name = filePath + ext;
      // Check virtual files
      if (_virtualFiles.containsKey(name)) {
        return _virtualFiles[name];
      }
    }

    // Try with search paths
    for (final searchPath in _searchPaths) {
      for (final ext in extensions) {
        final fullPath = path.join(searchPath, filePath + ext);

        // Check virtual files again with full path
        if (_virtualFiles.containsKey(fullPath)) {
          return _virtualFiles[fullPath];
        }

        // Try physical file
        final file = await fs.fileExists(fullPath);
        if (file) {
          return await _readFileWithStrategy(fullPath, preserveRawBytes);
        }
      }
    }

    // If the path is relative, try resolving it relative to the current working directory
    if (!path.isAbsolute(filePath)) {
      try {
        final currentDir = fs.getCurrentDirectory();
        if (currentDir == null) {
          throw Exception("Current directory is null");
        }

        for (final ext in extensions) {
          final fullPath = path.join(currentDir, filePath + ext);

          // Check virtual files with this path
          if (_virtualFiles.containsKey(fullPath)) {
            return _virtualFiles[fullPath];
          }

          // Try physical file
          final file = await fs.fileExists(fullPath);
          if (file) {
            return await _readFileWithStrategy(fullPath, preserveRawBytes);
          }
        }
      } catch (e) {
        Logger.debug(
          "Error resolving path relative to current directory: $e",
          category: 'FileManager',
        );
      }
    }

    // If the path is relative, try resolving it relative to the Dart script path
    if (!path.isAbsolute(filePath)) {
      try {
        final dartScriptPath = platform.scriptPath;
        if (dartScriptPath == null) {
          throw Exception("Dart script path is null");
        }
        final dartScriptDir = path.dirname(dartScriptPath);

        for (final ext in extensions) {
          final fullPath = path.join(dartScriptDir, filePath + ext);

          // Check virtual files with this path
          if (_virtualFiles.containsKey(fullPath)) {
            return _virtualFiles[fullPath];
          }

          // Try physical file
          final file = await fs.fileExists(fullPath);
          if (file) {
            return await _readFileWithStrategy(fullPath, preserveRawBytes);
          }
        }

        // Try project root
        final projectRoot = path.dirname(path.dirname(dartScriptPath));
        for (final ext in extensions) {
          final fullPath = path.join(projectRoot, filePath + ext);

          // Check virtual files with this path
          if (_virtualFiles.containsKey(fullPath)) {
            return _virtualFiles[fullPath];
          }

          // Try physical file
          final file = await fs.fileExists(fullPath);
          if (file) {
            return await _readFileWithStrategy(fullPath, preserveRawBytes);
          }
        }
      } catch (e) {
        Logger.debug(
          "Error resolving path relative to Dart script path: $e",
          category: 'FileManager',
        );
      }
    }

    return null;
  }

  /// Reads a file using the appropriate strategy based on the preserveRawBytes flag
  Future<String?> _readFileWithStrategy(
    String file,
    bool preserveRawBytes,
  ) async {
    if (preserveRawBytes) {
      // Read as raw bytes and convert to Latin-1 string to preserve byte values
      // This ensures that high bytes (like 225) are preserved as individual bytes
      // instead of being interpreted as UTF-8 sequences
      final bytes = await fs.readFileAsBytes(file);
      if (bytes == null) {
        return null;
      }
      return utf8.decode(bytes);
    } else {
      // Read as UTF-8 string (default behavior)
      // This properly handles UTF-8 characters like å, æ, ö
      return await fs.readFileAsString(file);
    }
  }

  /// Clears all registered virtual files.
  void clearVirtualFiles() {
    _virtualFiles.clear();
  }

  /// Sets the module search paths.
  ///
  /// [paths] - The new list of paths to search for modules
  void setSearchPaths(List<String> paths) {
    _searchPaths
      ..clear()
      ..addAll(paths);
  }

  /// Gets the full path for a module name.
  ///
  /// Resolves a module name to its full path by checking virtual files and
  /// physical files in all search paths, with support for dot notation.
  ///
  /// [moduleName] - The name of the module to resolve
  /// Returns the resolved path if found, null otherwise
  Future<String?> resolveModulePath(String moduleName) async {
    final extensions = ['', '.lua'];

    // Clear previous resolved globs for this resolution
    clearResolvedGlobs();

    Logger.debug("DEBUG: Resolving module path for: $moduleName");
    Logger.debug("DEBUG: Current search paths: $_searchPaths");

    // Try exact module name first
    for (final ext in extensions) {
      final name = moduleName + ext;
      if (_virtualFiles.containsKey(name)) {
        Logger.debug(
          "Module '$moduleName' found in virtual files as '$name'",
          category: 'FileManager',
        );
        return name;
      }
    }

    Logger.debug('Module name: $moduleName', category: 'FileManager');
    Logger.debug(
      'Module name with dots: ${moduleName.replaceAll('.', path.separator)}',
      category: 'FileManager',
    );
    Logger.debug("Search paths: $_searchPaths", category: 'FileManager');

    // Get package.path if available
    String packagePath = '';
    try {
      // Get package.path from the environment
      final packagePathValue = _getPackagePath();
      if (packagePathValue != null) {
        packagePath = packagePathValue;
        Logger.debug(
          "Using package.path: $packagePath",
          category: 'FileManager',
        );
      }
    } catch (e) {
      Logger.debug("Error getting package.path: $e", category: 'FileManager');
    }

    // Parse package.path into templates
    final List<String> templates = [];
    if (packagePath.isNotEmpty) {
      templates.addAll(packagePath.split(';'));
    }

    // Add default templates if package.path is empty
    if (templates.isEmpty) {
      templates.add('./?.lua');
      templates.add('./?/init.lua');
    }

    // Add current working directory templates
    try {
      final currentDir = fs.getCurrentDirectory();
      if (currentDir == null) {
        throw Exception("Current directory is null");
      }
      print("DEBUG: Using current working directory: $currentDir");
      Logger.debug(
        "Using current working directory: $currentDir",
        category: 'FileManager',
      );

      // Add current directory templates at the beginning to prioritize them
      if (!templates.contains('$currentDir/?.lua')) {
        templates.insert(0, '$currentDir/?/init.lua');
        templates.insert(0, '$currentDir/?.lua');
        print(
          "DEBUG: Added current directory templates: $currentDir/?.lua, $currentDir/?/init.lua",
        );
        Logger.debug(
          "Added current directory templates to beginning of search path",
          category: 'FileManager',
        );
      }

      // Also add project root templates if not in product mode
      if (!isProductMode) {
        try {
          final projectRoot = path.dirname(
            path.dirname(platform.scriptPath ?? ''),
          );
          if (projectRoot != currentDir &&
              !templates.contains('$projectRoot/?.lua')) {
            templates.insert(0, '$projectRoot/?/init.lua');
            templates.insert(0, '$projectRoot/?.lua');
            print(
              "DEBUG: Added project root templates: $projectRoot/?.lua, $projectRoot/?/init.lua",
            );
            Logger.debug(
              "Added project root templates to beginning of search path",
              category: 'FileManager',
            );
          }
        } catch (e) {
          print("DEBUG: Error getting project root: $e");
          Logger.debug(
            "Error getting project root: $e",
            category: 'FileManager',
          );
        }
      }
    } catch (e) {
      print("DEBUG: Error getting current working directory: $e");
      Logger.debug(
        "Error getting current working directory: $e",
        category: 'FileManager',
      );
    }

    // Get the current script directory if available
    String? scriptDir;
    if (_interpreter?.currentScriptPath != null) {
      scriptDir = path.dirname(_interpreter!.currentScriptPath!);
      print("DEBUG: Using script directory: $scriptDir");
      Logger.debug(
        "Using script directory: $scriptDir",
        category: 'FileManager',
      );

      // Add script directory templates at the beginning to prioritize them
      if (!templates.contains('$scriptDir/?.lua')) {
        templates.insert(0, '$scriptDir/?/init.lua');
        templates.insert(0, '$scriptDir/?.lua');
        print(
          "DEBUG: Added script directory templates: $scriptDir/?.lua, $scriptDir/?/init.lua",
        );
        Logger.debug(
          "Added script directory templates to beginning of search path",
          category: 'FileManager',
        );
      }
    }

    // Add Dart script directory templates if available and not in product mode
    if (!isProductMode) {
      try {
        final dartScriptPath = platform.scriptPath;
        if (dartScriptPath == null) {
          throw Exception("Dart script path is null");
        }
        final dartScriptDir = path.dirname(dartScriptPath);
        print("DEBUG: Using Dart script directory: $dartScriptDir");
        Logger.debug(
          "Using Dart script directory: $dartScriptDir",
          category: 'FileManager',
        );

        // Add Dart script directory templates at the beginning to prioritize them
        if (!templates.contains('$dartScriptDir/?.lua')) {
          templates.insert(0, '$dartScriptDir/?/init.lua');
          templates.insert(0, '$dartScriptDir/?.lua');
          print(
            "DEBUG: Added Dart script directory templates: $dartScriptDir/?.lua, $dartScriptDir/?/init.lua",
          );
          Logger.debug(
            "Added Dart script directory templates to beginning of search path",
            category: 'FileManager',
          );
        }
      } catch (e) {
        print("DEBUG: Error getting Dart script directory: $e");
        Logger.debug(
          "Error getting Dart script directory: $e",
          category: 'FileManager',
        );
      }
    } else {
      Logger.debug(
        "Running as compiled executable, skipping Platform.script path resolution in resolveModulePath",
        category: 'FileManager',
      );
    }

    // Try each template
    for (final template in templates) {
      // Replace ? with module name (with dots converted to path separators)
      final modNameWithSep = moduleName.replaceAll('.', path.separator);
      final fileName = template.replaceAll('?', modNameWithSep);

      print("DEBUG: Trying template: $template -> $fileName");
      Logger.debug(
        "Trying template: $template -> $fileName",
        category: 'FileManager',
      );

      // Check virtual files
      if (_virtualFiles.containsKey(fileName)) {
        print("DEBUG: Module found in virtual files as '$fileName'");
        Logger.debug(
          "Module found in virtual files as '$fileName'",
          category: 'FileManager',
        );
        return fileName;
      }

      // Check physical files
      final file = await fs.fileExists(fileName);
      if (file) {
        print("DEBUG: Module found in physical files as '$fileName'");
        Logger.debug(
          "Module found in physical files as '$fileName'",
          category: 'FileManager',
        );
        return fileName;
      }

      // Try glob pattern matching for this template
      try {
        final directory = path.dirname(fileName);
        final pattern = path.basename(fileName);

        print(
          "DEBUG: Trying glob pattern in directory: $directory with pattern: $pattern",
        );

        // Check if directory exists before trying to list it
        final dir = await fs.directoryExists(directory);
        if (dir) {
          print("DEBUG: Directory exists, listing files:");
          final entities = await fs.listDirectory(directory);
          print(
            "DEBUG: Found ${entities.length} files/directories in $directory",
          );

          for (final entity in entities) {
            print("DEBUG: Checking entity: $entity");
            if (await fs.fileExists(entity)) {
              final basename = path.basename(entity);
              print(
                "DEBUG: Checking if file '$basename' matches pattern '$pattern'",
              );
              if (_matchesGlobPattern(basename, pattern)) {
                print("DEBUG: Module found via glob as '$entity'");
                Logger.debug(
                  "Module found via glob as '$entity'",
                  category: 'FileManager',
                );

                // Track the resolved glob
                final absolutePath = path.absolute(entity);
                _addResolvedGlob(path.join(directory, pattern), absolutePath);

                return entity;
              }
            }
          }
          print("DEBUG: No matching files found in directory $directory");
        } else {
          print("DEBUG: Directory $directory does not exist");
        }
      } catch (e) {
        // If directory doesn't exist or can't be accessed, just continue
        print("DEBUG: Error with glob pattern '$fileName': $e");
        Logger.debug(
          "Error with glob pattern '$fileName': $e",
          category: 'FileManager',
        );
      }
    }

    // Try with search paths and extensions as a fallback
    for (final searchPath in _searchPaths) {
      // First try with dots converted to separators
      final modNameWithSep = moduleName.replaceAll('.', path.separator);

      for (final ext in extensions) {
        final paths = [
          path.join(searchPath, moduleName + ext),
          path.join(searchPath, modNameWithSep + ext),
        ];

        for (final fullPath in paths) {
          print("DEBUG: Trying path: $fullPath");
          if (_virtualFiles.containsKey(fullPath)) {
            print(
              "DEBUG: Module found in virtual files with search path as '$fullPath'",
            );
            Logger.debug(
              "Module found in virtual files with search path as '$fullPath'",
              category: 'FileManager',
            );
            return fullPath;
          }

          final file = await fs.fileExists(fullPath);
          if (file) {
            print(
              "DEBUG: Module found in physical files with search path as '$fullPath'",
            );
            Logger.debug(
              "Module found in physical files with search path as '$fullPath'",
              category: 'FileManager',
            );
            return fullPath;
          }

          // Try glob pattern matching for this path
          try {
            final directory = path.dirname(fullPath);
            final pattern = path.basename(fullPath);

            print(
              "DEBUG: Trying glob pattern in directory: $directory with pattern: $pattern",
            );

            // Check if directory exists before trying to list it
            final dir = await fs.directoryExists(directory);
            if (dir) {
              print("DEBUG: Directory exists, listing files:");
              final entities = await fs.listDirectory(directory);
              print(
                "DEBUG: Found ${entities.length} files/directories in $directory",
              );

              for (final entity in entities) {
                print("DEBUG: Checking entity: $entity");
                if (await fs.fileExists(entity)) {
                  final basename = path.basename(entity);
                  print(
                    "DEBUG: Checking if file '$basename' matches pattern '$pattern'",
                  );
                  if (_matchesGlobPattern(basename, pattern)) {
                    print(
                      "DEBUG: Module found via glob with search path as '$entity'",
                    );
                    Logger.debug(
                      "Module found via glob with search path as '$entity'",
                      category: 'FileManager',
                    );

                    // Track the resolved glob
                    final absolutePath = path.absolute(entity);
                    _addResolvedGlob(
                      path.join(directory, pattern),
                      absolutePath,
                    );

                    return entity;
                  }
                }
              }
              print("DEBUG: No matching files found in directory $directory");
            } else {
              print("DEBUG: Directory $directory does not exist");
            }
          } catch (e) {
            // If directory doesn't exist or can't be accessed, just continue
            print("DEBUG: Error with glob pattern '$fullPath': $e");
            Logger.debug(
              "Error with glob pattern '$fullPath': $e",
              category: 'FileManager',
            );
          }
        }
      }
    }

    // Try special directories that might contain modules
    final specialDirs = [
      // Current directory and its subdirectories
      fs.getCurrentDirectory(),
      path.join(fs.getCurrentDirectory() ?? '', 'test'),
      path.join(fs.getCurrentDirectory() ?? '', '.lua-tests'),
    ];

    // Add project root directories if not in product mode
    if (!isProductMode) {
      try {
        final projectRoot = path.dirname(
          path.dirname(platform.scriptPath ?? ''),
        );
        specialDirs.addAll([
          // Project root and its subdirectories
          projectRoot,
          path.join(projectRoot, 'test'),
          path.join(projectRoot, '.lua-tests'),
        ]);
      } catch (e) {
        print("DEBUG: Error adding project root special directories: $e");
        Logger.debug(
          "Error adding project root special directories: $e",
          category: 'FileManager',
        );
      }
    }

    for (final dir in specialDirs) {
      try {
        final directory = await fs.directoryExists(dir ?? '');
        if (directory) {
          // Try with dots converted to separators
          final modNameWithSep = moduleName.replaceAll('.', path.separator);

          for (final ext in extensions) {
            final paths = [
              path.join(dir ?? '', moduleName + ext),
              path.join(dir ?? '', modNameWithSep + ext),
            ];

            for (final fullPath in paths) {
              print("DEBUG: Trying special directory path: $fullPath");
              final file = await fs.fileExists(fullPath);
              if (file) {
                print(
                  "DEBUG: Module found in special directory as '$fullPath'",
                );
                return fullPath;
              }
            }
          }
        }
      } catch (e) {
        print("DEBUG: Error checking special directory $dir: $e");
      }
    }

    print("DEBUG: Module '$moduleName' not found after trying all paths");
    Logger.debug("Module '$moduleName' not found", category: 'FileManager');
    return null;
  }

  // Helper method to get package.path
  String? _getPackagePath() {
    // Try to get package.path from the interpreter's globals
    if (_interpreter != null) {
      final packageTable = _interpreter!.globals.get('package');
      if (packageTable is Value && packageTable.raw is Map) {
        final path = (packageTable.raw as Map)['path'];
        if (path is Value) {
          return path.raw.toString();
        }
      }
    }
    return null;
  }

  // Helper method to match a filename against a glob pattern
  bool _matchesGlobPattern(String filename, String pattern) {
    print("DEBUG: Matching filename '$filename' against pattern '$pattern'");
    // Convert glob pattern to RegExp
    // Replace * with .* and ? with .
    // Escape other special regex characters
    String regexPattern = pattern
        .replaceAll('.', '\\.')
        .replaceAll('*', '.*')
        .replaceAll('?', '.');

    // Anchor the pattern to match the whole string
    regexPattern = '^$regexPattern\$';
    print("DEBUG: Converted to regex pattern: '$regexPattern'");

    try {
      final regex = RegExp(regexPattern);
      final matches = regex.hasMatch(filename);
      print("DEBUG: Match result: $matches");
      return matches;
    } catch (e) {
      print("DEBUG: Error creating regex from pattern '$pattern': $e");
      Logger.debug(
        "Error creating regex from pattern '$pattern': $e",
        category: 'FileManager',
      );
      return false;
    }
  }

  /// Prints all the resolved globs for debugging
  void printResolvedGlobs() {
    if (_resolvedGlobs.isEmpty) {
      print("No globs were resolved during the last module resolution");
      return;
    }

    print("\n=== Resolved Globs ===");
    for (int i = 0; i < _resolvedGlobs.length; i++) {
      final glob = _resolvedGlobs[i];
      print("${i + 1}. Pattern: ${glob['pattern']}");
      print("   Resolved to: ${glob['resolved']}");
    }
    print("=====================\n");
  }

  /// Resolves a module path to an absolute path.
  ///
  /// This method takes a module path (which may be relative) and resolves it to an absolute path
  /// using various strategies:
  /// 1. If the path is already absolute, it's returned as is
  /// 2. If a current script path is available, it tries to resolve relative to that
  /// 3. It tries to resolve relative to the current working directory
  /// 4. If not in product mode, it tries to resolve relative to the Dart script path
  /// 5. As a last resort, it converts the path to a simple absolute path
  ///
  /// [modulePath] - The module path to resolve
  /// Returns the resolved absolute path
  String resolveAbsoluteModulePath(String modulePath) {
    // If the path is already absolute, return it as is
    if (path.isAbsolute(modulePath)) {
      Logger.debug(
        "Module path is already absolute: $modulePath",
        category: 'FileManager',
      );
      return modulePath;
    }

    // Try different strategies to resolve the path
    try {
      // First try relative to the current script path if available
      if (_interpreter?.currentScriptPath != null) {
        final scriptDir = path.dirname(_interpreter!.currentScriptPath!);
        final resolvedPath = path.normalize(path.join(scriptDir, modulePath));
        Logger.debug(
          "Resolved module path relative to current script: $resolvedPath",
          category: 'FileManager',
        );
        return resolvedPath;
      }

      // Then try relative to the current working directory
      try {
        final currentDir = fs.getCurrentDirectory();
        if (currentDir == null) {
          throw Exception("Current directory is null");
        }
        final resolvedPath = path.normalize(path.join(currentDir, modulePath));
        Logger.debug(
          "Resolved module path relative to current directory: $resolvedPath",
          category: 'FileManager',
        );
        return resolvedPath;
      } catch (e) {
        // If that fails, try relative to the Dart script path
        try {
          // Only use Platform.script if not in product mode
          if (!isProductMode) {
            final dartScriptPath = platform.scriptPath;
            if (dartScriptPath == null) {
              throw Exception("Dart script path is null");
            }
            final dartScriptDir = path.dirname(dartScriptPath);
            final resolvedPath = path.normalize(
              path.join(dartScriptDir, modulePath),
            );
            Logger.debug(
              "Resolved module path relative to Dart script: $resolvedPath",
              category: 'FileManager',
            );
            return resolvedPath;
          } else {
            Logger.debug(
              "Running as compiled executable, skipping Platform.script path resolution",
              category: 'FileManager',
            );
            // In product mode, skip Platform.script and use simple absolute path
            final resolvedPath = path.absolute(modulePath);
            Logger.debug(
              "Using simple absolute path in product mode: $resolvedPath",
              category: 'FileManager',
            );
            return resolvedPath;
          }
        } catch (e2) {
          // Fallback to simple absolute path
          final resolvedPath = path.absolute(modulePath);
          Logger.debug(
            "Error resolving module path, using simple absolute path: $resolvedPath",
            category: 'FileManager',
          );
          return resolvedPath;
        }
      }
    } catch (e) {
      // Fallback to simple absolute path
      final resolvedPath = path.absolute(modulePath);
      Logger.debug(
        "Error resolving module path: $e, using simple absolute path: $resolvedPath",
        category: 'FileManager',
      );
      return resolvedPath;
    }
  }
}
