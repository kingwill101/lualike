import 'package:lualike/src/gc/gc.dart';
import 'package:lualike/src/utils/platform_utils.dart' as platform;

abstract interface class LuaBytecodeGCRootProvider {
  Iterable<GCObject> gcReferences();
}

final Object inlineBuiltinUnhandled = Object();

void debugFileLog(String message) {
  if (platform.getEnvironmentVariable('LUALIKE_DEBUG_FILE_OPS') == '1') {
    print('[file-debug] $message');
  }
}
