/// Platform-conditional export for 64-bit typed-data operations.
///
/// On native platforms, this delegates to `ByteData.setInt64`,
/// `ByteData.setUint64`, `ByteData.getInt64`, and `ByteData.getUint64`.
///
/// On the web (`dart2js`/`dart2wasm`), this uses `BigInt`-based
/// arithmetic to correctly handle 64-bit values, since JavaScript
/// bitwise operators are limited to 32 bits.
library;

export 'byte_data_native.dart'
    if (dart.library.js_interop) 'byte_data_web.dart';
