/// Web implementation of platform utilities
library;

/// Platform-safe way to check if we're on Windows - always false on web
bool get isWindows => false;

/// Platform-safe way to check if we're on Linux - always false on web
bool get isLinux => false;

/// Platform-safe way to check if we're on macOS - always false on web
bool get isMacOS => false;

/// Platform-safe way to get environment variables - empty on web
Map<String, String> get environment => <String, String>{};

/// Platform-safe way to get a specific environment variable - always null on web
String? getEnvironmentVariable(String name) => null;

/// Platform-safe way to get path separator - always Unix-style on web
String get pathSeparator => '/';

/// Platform-safe way to get the executable name/path - generic on web
String get executableName => 'lualike-web';

/// Platform-safe way to get the script path - null on web
String? get scriptPath => null;

/// On the web, there is no executable path; return empty string.
String get resolvedExecutablePath => '';
